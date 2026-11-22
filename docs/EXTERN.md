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
| `src/sys.zsharp` na prawdziwej libc/jądrze | **brak testu automatycznego** — backend natywny tej wersji Z# nie linkuje jeszcze `extern`. Pierwszy rozruch w QEMU/kontenerze to właściwy test; zacznij od `zenitd --user` albo kontenera |

Gdy extern będzie działać: uruchom najpierw tryb kontenerowy (`docker run --init=false ... /usr/lib/zenit/zenitd`),
potem QEMU z `init=/sbin/init`.
