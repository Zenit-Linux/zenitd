# libc przez `extern` — ABI i status weryfikacji

zenitd nie zawiera kodu C. Jedyną zależnością spoza Z# jest libc (glibc lub musl), wołana przez `extern "c" { ... }`
(blok na początku `src/main.zsharp` — linker Z# dopuszcza `extern` tylko w pliku wejściowym). W `Z#.toml`: `[extern.c]`.

## Założenia ABI systemu extern

| Z# | C |
|---|---|
| `int` | `int64_t` / wskaźnik; wynik C-owego `int` zwężany w Z# (`mem.i32`), bo górne 32 bity rejestru są nieokreślone |
| `string` (argument) | `const char *`, UTF-8, NUL na końcu; `null` → `NULL` |
| `string` (wynik) | napis kopiowany przez runtime z `char *` (używane wyłącznie w `strstr`, `strerror`) |

## Struktury bez wskaźników: `mem.zsharp`

Z# nie ma wskaźników ani struktur, więc `Mem` operuje na adresach (liczbach):

- zapis bajtu: `memset(addr, v, 1)`; odczyt: `memcmp(addr, bufor_zer, 1)` (glibc i musl zwracają różnicę bajtów);
- napis spod adresu: `strstr(addr, "")` (zwraca ten sam wskaźnik, runtime kopiuje napis);
- little-endian (x86_64, aarch64, riscv64). Różnice architektur: rozmiar `epoll_event` (12 vs 16), `st_mode` w `stat`
  (offset 24 vs 16), numery syscalli `capget/capset` — wybierane w `Sys` po `System.architecture()`.

Struktury składane w pamięci: `epoll_event`, `signalfd_siginfo`, `sockaddr_un/in/in6`, `struct stat` (size@48, mtime@88),
`struct tm`, `timespec`, `rlimit`, `pollfd`, `ifreq`, `__user_cap_header/data`, `passwd`/`group` (odczyt), `dirent` (d_name@19).
Offsety zweryfikowano na x86_64/glibc (ctypes): memset/memcmp/strstr, `lstat`.

## Fork z poziomu Z#

`Sys::spawn` woła `fork()` i kontynuuje kod Z# w dziecku (`childMain`), kończąc `execve` albo `_exit(127)`. Wymaga to
jednowątkowego runtime Z# i niczego nieflushowanego w buforach stdout przed forkiem (zenitd nie używa `echo` w demonie).

## Status weryfikacji (uczciwie)

| Co | Jak sprawdzone |
|---|---|
| Logika (ini, jednostki, graf, kalendarz, silnik zadań, usługi, sockety, timery, dziennik, ctl, protokół) | 243 asercje w interpreterze stage0, fałszywy `Sys` |
| Zgodność z natywnym backendem Z# | `scripts/native-check.sh`: linker + `ir.lower` → zero problemów poza samym `extern` |
| Triki pamięciowe i offsety struktur | ctypes na x86_64/glibc |
| `src/sys.zsharp` na prawdziwej libc/jądrze | `scripts/live-test.sh`: 12 sprawdzeń na żywo w trybie `--user` (interpreter stage0 z `ffi.rs` albo bundle `.zbc`): start/stop/restart, grupa procesów, rlimity, start-limit, oneshot, journalctl, aktywacja gniazdem, timer. `scripts/vm/run.sh`: zenitd jako PID 1 na prawdziwym jądrze w QEMU (cgroup v2, notify, forking, `reboot(2)`, poweroff — 23/23). Dodatkowo ręcznie: PID 1 w przestrzeni PID (`unshare --pid --fork --mount-proc`, `container=docker`): `poweroff` → kod 0, `reboot` → kod 2 |
| Natywny backend Z# | nadal nie linkuje `extern` ani klas — zenitd działa jako pakiet `.zbc` (`zsc build --emit zbc` + `zsc0 bundle`) |

Następny krok: uruchom najpierw tryb kontenerowy (`docker run --init=false ... /usr/lib/zenit/zenitd`),
potem QEMU z `init=/sbin/init`.
