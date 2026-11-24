# zenitd

**Init (PID 1) i menedżer usług dla [Zenit Linux](https://github.com/), napisany w całości w Z#.**
Lekki, szybki następca systemd bez molocha: jedna binarka, zero demonów w tle poza samym zenitd, jednostki w formacie
zgodnym z systemd (czyta istniejące pliki `.service` z dystrybucji), a dla programów zakładających systemd — warstwa
zgodności (`systemctl`, `journalctl`, `reboot`, `systemd-notify`...).

## Po co?

| Problem systemd | Podejście zenitd |
|---|---|
| Moloch: init + logind + networkd + resolved + timesyncd + D-Bus... | Tylko init + menedżer usług + dziennik. Reszta to osobne, wymienialne programy |
| W kontenerze ciągnie cały stos | `zenitd` jako PID 1 kontenera: pomija mounty/hostname, ma `exit` zamiast `reboot(2)` |
| Programy zakładają `systemctl`/`journalctl` | Aplety w tej samej binarce, tłumaczą tylko realnie używane wywołania |
| Jeden wielki, nieczytelny kod | Małe moduły z wąskimi interfejsami, czysta logika testowana bez jądra |

## Co potrafi

- **Jednostki**: `.service` (simple, exec, forking, oneshot, notify, idle), `.target`, `.socket` (aktywacja gniazdem), `.timer`
  (OnCalendar, OnBootSec, OnUnitActiveSec, Persistent), `.mount`/`.swap` (przez mount/swapon).
- **Zależności**: Requires, Wants, Requisite, BindsTo, PartOf, Conflicts, After/Before, OnFailure, `*.wants`/`*.requires`,
  szablony `foo@.service` (`%i %I %n %N %p %t %S ...`), drop-iny `*.d/*.conf`, aliasy, maskowanie, `isolate`.
- **Nadzór**: Restart= (wszystkie polityki), RestartSec, limity startów, TimeoutStart/StopSec, KillMode, SendSIGKILL,
  watchdog (`WatchdogSec`), `sd_notify` (READY/STATUS/MAINPID/WATCHDOG/RELOADING) przez `NOTIFY_SOCKET`.
- **Zasoby i bezpieczeństwo**: cgroup v2 na jednostkę (MemoryMax, CPUWeight, CPUQuota, TasksMax, IOWeight), zabijanie całej
  grupy, `User/Group`, rlimity, `NoNewPrivileges`, `PrivateTmp`, `PrivateNetwork`, `ProtectSystem/Home`, `ReadOnlyPaths`...,
  `CapabilityBoundingSet`, `AmbientCapabilities`, katalogi `RuntimeDirectory=`/`StateDirectory=`.
- **Dziennik**: przechwytuje stdout/stderr usług i `/dev/log` (syslog), rotacja, `journalctl` (-u -n -f -b -p -g -S -o).
- **PID 1**: mounty API (`/proc /sys /dev /run` cgroup2), konsola, hostname, machine-id, sprzątanie zombie, Ctrl-Alt-Del,
  zamykanie (stop usług w odwrotnej kolejności → SIGTERM/SIGKILL reszty → sync → umount → `reboot(2)`), tryb awaryjny.
- **Tryby**: system (PID 1), kontener, `--user` (menedżer sesji użytkownika).

## Użycie

```
zenitctl status nginx            # (też: systemctl ...)
zenitctl start|stop|restart|reload|try-restart UNIT...
zenitctl enable --now sshd       # działa też offline (chroot, budowa obrazów)
zenitctl list-units [-a] [-t service] [--failed]
zenitctl list-timers | list-sockets | list-dependencies UNIT | analyze blame
zenitctl isolate rescue.target   # albo: default | rescue | emergency
journalctl -u nginx -f           # dziennik
shutdown -r now / reboot / poweroff
```

Jądro: `init=/sbin/init`. Parametry: `zenit.unit=rescue`, `systemd.unit=...`, `single`, `emergency`, `3`, `5`.
Konfiguracja: `/etc/zenit/zenit.conf` (zob. `data/conf/zenit.conf`). Jednostki: `/etc/zenit/system`,
`/usr/lib/zenit/system`, a przy `SystemdUnitCompat=yes` także katalogi systemd.

## Budowanie i instalacja

Testy: `ZSC0=… scripts/test.sh` (logika, fałszywy `Sys`) oraz `ZENITD=… scripts/live-test.sh` (prawdziwa libc/jądro, tryb `--user`).
Binarka standalone: `zsc build src/main.zsharp --emit zbc -o zenitd.zbc && zsc0 bundle zenitd.zbc -o zenitd`.

```
z# build --release          # target/release/zenitd (wejście: src/main.zsharp)
DESTDIR=/tmp/rootfs scripts/install.sh
```

Jedna binarka, wiele apletów — wybór po nazwie (`argv[0]`) lub `zenitd --applet=NAZWA ...`:
`zenitd`/`init`, `zenitctl`/`systemctl`, `journalctl`, `reboot` `poweroff` `halt` `shutdown` `telinit`, `systemd-notify`/`zenit-notify`.

## Układ repozytorium

```
src/main.zsharp      wejście: extern libc + wybór apletu + uruchomienie demona
src/sys.zsharp       cała warstwa systemowa (fork/exec, epoll, gniazda, mount, cgroup...) na libc przez extern
src/mem.zsharp       surowa pamięć dla struktur C (peek/poke przez memset/memcmp) — w Z#
src/manager.zsharp   rejestr jednostek, silnik zadań, pętla zdarzeń, zamykanie
src/service.zsharp   maszyna stanów usługi        src/socket.zsharp, timer.zsharp, runtime.zsharp (Target, warunki)
src/unit.zsharp, ini.zsharp, loader.zsharp, graph.zsharp, calendar.zsharp   czysta logika
src/execspec.zsharp, cgroup.zsharp, journal.zsharp, config.zsharp, boot.zsharp
src/control.zsharp, proto.zsharp, ctl.zsharp, compat.zsharp                 sterowanie i zgodność
data/                jednostki domyślne, przykłady, zenit.conf
tests/               testy w interpreterze z fałszywym Sys (tests/fake)
docs/                ARCHITECTURE.md, COMPAT.md, EXTERN.md
```

## Testy

```
ZSC0=/ścieżka/do/zsc0 scripts/test.sh                    # 243 asercje, bez roota i bez jądra
ZSHARP_HOME=/ścieżka/do/Z-Sharp scripts/native-check.sh  # zgodność z podzbiorem natywnym Z#
```

Logika (parsery, graf, silnik zadań, maszyna stanów usług, sockety, timery, dziennik, ctl) jest testowana w interpreterze
stage0 na fałszywej warstwie `Sys` (wirtualne pliki, procesy, czas). Warstwa `src/sys.zsharp` (prawdziwa libc) nie ma
testów automatycznych — zob. „Status” w [docs/EXTERN.md](docs/EXTERN.md).

## Poza zakresem (świadomie)

D-Bus (`org.freedesktop.systemd1`), `logind`/`loginctl`, `networkd`, `resolved`, `timesyncd`, `hostnamectl`/`timedatectl`,
`systemd-tmpfiles`/`sysusers` (użyj `opentmpfiles`/własnych skryptów), `DynamicUser=`, filtry seccomp (`SystemCallFilter=`),
`Accept=yes` w `.socket`, `.path`, `daemon-reexec` ze zachowaniem stanu (działa jak `daemon-reload`), opóźnione `shutdown` z anulowaniem.
Szczegóły i tabela dyrektyw: [docs/COMPAT.md](docs/COMPAT.md).

Licencja: MPL-2.0.
