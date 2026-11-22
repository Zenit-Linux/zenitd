# Architektura zenitd

## Warstwy

```
main ── compat (aplety) ── ctl ──────────────┐            klient: gniazdo /run/zenit/control
  │                                          │
  └─ boot (PID 1) ── manager ── control ─────┘            demon
                      │  ├─ loader ─ unit ─ ini           pliki jednostek
                      │  ├─ graph                         transakcje (czysta logika)
                      │  ├─ runtime: Target, Service, Socket, Timer
                      │  ├─ execspec, cgroup, journal, config
                      └─ sys ── mem ── libc (extern)      JEDYNE miejsce dotykające systemu
```

Zasada: **cała logika jest czysta** (zależy od obiektu `$sys`), a `sys.zsharp` to jedyny moduł wołający libc. Dlatego testy
podstawiają `tests/fake/sys.zsharp` o tym samym interfejsie (przez `ZS_WORKSPACE`).

## Pętla zdarzeń (`Manager::loop`)

`epoll` na: signalfd (SIGCHLD, SIGTERM, SIGINT, SIGHUP, SIGPWR, SIGRTMIN+3..6, SIGUSR1/2), gniazdo sterujące, połączenia
klientów, potoki logów usług, gniazda `notify` (jedno na usługę — tożsamość nadawcy wynika z gniazda, bez SCM_CREDENTIALS),
`/dev/log`, gniazda `.socket`. Timeout = najbliższy termin spośród `Runtime::nextWake()` (timeouty, restarty, watchdog, timery).
Każda iteracja: zdarzenia → terminy → `waitpid(-1)` → silnik zadań → postęp zamykania. Wyjątki w iteracji są logowane,
PID 1 nigdy nie pada.

## Silnik zadań

`submit(jednostka, typ)` → `graph.planStart/planStop` (domknięcie Requires/Wants/BindsTo, konflikty, sortowanie topologiczne
z łamaniem cykli na węźle leżącym na cyklu) → po jednym `Job` na jednostkę. Zadanie czeka (`blocked`), dopóki istnieje
zadanie, które musi je poprzedzić (After/Before, Conflicts; przy stopie — odwrotnie). `changed()` (wołane z `setState`)
rozstrzyga zakończenie zadań, propaguje awarie (Requires/BindsTo), uruchamia OnFailure, wznawia nasłuch gniazd i
przelicza timery. Cel startowy, który się nie powiedzie, przełącza na `emergency.target`, a na końcu na powłokę awaryjną.

## Maszyna stanów usługi

```
start ─ ExecStartPre ─ ExecStart ─(simple/exec: od razu | notify: czeka na READY | forking: czeka na wyjście | oneshot: kolejno)
      ─ ExecStartPost ─ ACTIVE(running|exited)
stop  ─ ExecStop ─ SIGTERM (KillMode) ─ [limit] SIGKILL ─ czekanie na pusty cgroup ─ ExecStopPost ─ sprzątanie
koniec głównego procesu ─ ExecStopPost ─ sprzątanie ─ failed | inactive ─ Restart= ─ auto-restart (RestartSec) ─ start
```

Sprzątanie: SIGKILL reszty cgroupu, opróżnienie i zamknięcie potoku logów, usunięcie cgroupu, gniazda notify, RuntimeDirectory.
Limit startów liczony w oknie `StartLimitIntervalSec`; po przekroczeniu `failed (start-limit-hit)`.

## Uruchamianie procesów (`Sys::spawn`)

`fork` w Z#, po stronie dziecka (kolejność): reset sygnałów, `setsid`, dołączenie do cgroup, przekazanie fd (3..), stdio,
umask/nice/rlimity, bounding set, piaskownica (unshare + mounty), chroot, `LISTEN_PID`, grupy, `setresgid/uid`, ambient caps,
chdir, `execve`. Błąd na dowolnym etapie wraca do rodzica rurą CLOEXEC (`etap errno`), więc `start` zgłasza dokładną przyczynę.

## Zamykanie systemu

Stop wszystkich jednostek (odwrotna kolejność) → timeout `ShutdownTimeoutSec` → `kill(-1, SIGTERM)`, 3 s, `SIGKILL` →
zamknięcie sterowania, wpis do dziennika, `sync` → `umount` wszystkiego poza API → `remount,ro /` → `reboot(2)`.
Poza PID 1 / w kontenerze: wyjście z kodem 0 (poweroff/halt) lub 2 (reboot).

## Dziennik

Linie TSV (`czas_ms, jednostka, pid, priorytet, ident, wiadomość`), pliki `zenit.log[.N]` w `/run/log/zenit` (ulotny) i
`/var/log/zenit` (trwały, gdy istnieje). Rotacja po `LogMaxFileSize`. `journalctl` czyta pliki bezpośrednio — nie wymaga demona.
