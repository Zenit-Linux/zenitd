# Zmiany w zenitd (sesja „poligon dla Z#")

Pliki zmienione względem archiwum wejściowego:

| Plik | Zmiana |
|---|---|
| `src/main.zsharp` | `System.args()[0]` to ścieżka programu — usunięta z argumentów (`util.drop_first`); wcześniej `--applet=` nie działał, a aplety dostawały dodatkowy argument. Po zamknięciu PID 1 **kontenera** demon kończy się kodem wyjścia (0 poweroff/halt, 2 reboot) zamiast czekać w pętli „PID 1 nie wychodzi". |
| `src/sys.zsharp` | Limity zasobów (`Limit*=`) są napisami z `execspec`; `poke64` robił na nich `&` → wyjątek w dziecku. Teraz `intval`, a `"inf"` = `RLIM_INFINITY`. Wyjątek w dziecku po `fork()` kończy się `_exit` (`childFail`) — wcześniej dziecko wracało do pętli demona jako jego klon. |
| `src/unit.zsharp` | Zgodność z systemd: `StartLimitBurst`, `StartLimitInterval`, `StartLimitIntervalSec` w `[Service]` trafiają do `[Unit]` (bez ostrzeżenia „nieznana dyrektywa"). |
| `src/util.zsharp` | `expandVars`: `$` bez nazwy (np. `$(cmd)`) zostaje dosłownie (wcześniej znikał, `sh -c 'echo $(…)'` kończył się błędem składni); niedomknięte `${` zostaje bez zmian. |
| `src/compat.zsharp` | `journalctl` przyjmuje `--user` i `--system`. |
| `src/manager.zsharp` | Komunikat o wyjątku w pętli głównej zawiera numer linii. **Cykl porządku zależności** (np. cel z `Wants=X`, a `X` z `After=cel` — cele dostają niejawne `After=` na swoje `Wants=`) był tylko zgłaszany ostrzeżeniem, a `blocked()` dalej czekało na przerwane krawędzie: oba zadania wisiały w nieskończoność i system nie dochodził do `multi-user.target`. Teraz krawędzie przerwane przy cyklu (`plan["broken"]`) są pomijane także w czasie wykonania (`ignoreWait`), jak w systemd. |
| `src/graph.zsharp` | `order()`, `planStart()` i `planStop()` zwracają przerwane krawędzie (`broken`); nowa funkcja `reaches()`. |
| `src/control.zsharp` | Wyścig w `cmdJobs`: `submit()` wykonuje zadania synchronicznie, więc zadanie `start` zwykłej usługi mogło się zakończyć, zanim klient trafił do `waiters` — `zenitctl start` nie dostawał odpowiedzi i wisiał (do 10 min). Zakończone zadania są teraz rozliczane od razu. |
| `tests/t_util.zsharp` | +2 asercje (`expandVars`). |
| `tests/t_cycle.zsharp` | **nowy**: cykl porządku nie zawiesza zadań; odpowiedź `start` dociera do klienta mimo synchronicznego zakończenia zadania (odtwarza oba błędy bez poprawek). |
| `scripts/test.sh` | dodany zestaw `t_cycle`. |
| `tests/t_units.zsharp` | +3 asercje (`StartLimit*` w `[Service]`). |
| `scripts/live-test.sh` | **nowy**: test na żywo (12 sprawdzeń). |
| `scripts/vm/build.sh`, `run.sh`, `selftest.sh` | **nowe**: zenitd jako PID 1 w QEMU na prawdziwym jądrze (initramfs: busybox + bundle `.zbc` + jednostki testowe). 23 sprawdzenia: rozruch, cgroup v2 (`memory.max`, `pids.max`, `cpu.weight`), usuwanie cgroup, `Type=notify` z prawdziwym `sd_notify`, `Type=forking`, zbieranie zombie, `reboot(2)` (komunikat jądra „Restarting system") i `poweroff` („Power down"). |
| `docs/EXTERN.md`, `README.md` | status weryfikacji, opis testów i budowania bundla. |
| `docs/CHANGES.md` | ten plik (nowy). |

Wynik: `scripts/test.sh` — 254 asercje, 0 błędów; `scripts/live-test.sh` — 12/12; VM (`scripts/vm/run.sh reboot` i `poweroff`) — 23/23 w obu scenariuszach.

Błędy, których przyczyna leżała poza zenitd (naprawione po stronie Z#, w zenitd bez zmian): samodzielna binarka nie startowała jako PID 1 (brak `/proc` przy starcie → panic jądra; zbyt duży stos wątku na VM z 1 GB), oraz opóźnione (~5 s) wykrywanie zakończenia procesów potomnych, przez które `Restart=` i limit startów działały źle.
