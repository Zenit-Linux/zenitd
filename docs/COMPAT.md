# Zgodność z systemd

zenitd czyta pliki jednostek systemd i implementuje **podzbiór** dyrektyw. Nieznane klucze dają ostrzeżenie w
`zenitctl status` (nie przerywają ładowania); znane, ale nieobsługiwane — ostrzeżenie w dzienniku przy starcie usługi.

## Obsługiwane dyrektywy

| Sekcja | Dyrektywy |
|---|---|
| `[Unit]` | Description, Requires, Requisite, Wants, BindsTo, PartOf, Conflicts, Before, After, OnFailure, DefaultDependencies, AllowIsolate, IgnoreOnIsolate, RefuseManualStart, StartLimitIntervalSec, StartLimitBurst, Condition*/Assert* (PathExists, PathIsDirectory, PathIsSymbolicLink, PathIsReadWrite, PathIsMountPoint, FileNotEmpty, FileIsExecutable, DirectoryNotEmpty, Virtualization, KernelCommandLine, Host, User, Architecture, Environment; prefiksy `!` i `|`) |
| `[Service]` | Type (simple exec forking oneshot notify idle; dbus ≙ simple), ExecStart/Pre/Post/Reload/Stop/StopPost (modyfikatory `-` `@`; `$VAR`, `${VAR}`, `$MAINPID`), Restart, RestartSec, RestartPreventExitStatus, RestartForceExitStatus, SuccessExitStatus, RemainAfterExit, PIDFile, NotifyAccess, WatchdogSec, TimeoutSec/StartSec/StopSec, KillMode, KillSignal, SendSIGKILL, SendSIGHUP, User, Group, SupplementaryGroups, WorkingDirectory, RootDirectory, Environment, EnvironmentFile, PassEnvironment, UMask, Nice, Limit{NOFILE,NPROC,CORE,MEMLOCK,AS,CPU,FSIZE,DATA,STACK,RSS}, StandardInput/Output/Error (null inherit journal syslog kmsg tty file: append: truncate:), TTYPath, SyslogIdentifier, NoNewPrivileges, PrivateTmp, PrivateNetwork, ProtectSystem, ProtectHome, ReadOnlyPaths, ReadWritePaths, InaccessiblePaths, CapabilityBoundingSet, AmbientCapabilities, RuntimeDirectory/StateDirectory/CacheDirectory/LogsDirectory/ConfigurationDirectory (+Mode), MemoryMax/High/Min/SwapMax, TasksMax, CPUWeight, CPUQuota, IOWeight |
| `[Socket]` | ListenStream (unix, `@abstrakcyjne`, `port`, `host:port`, `[v6]:port`), ListenDatagram (unix), Accept=no, Backlog, SocketMode, SocketUser, SocketGroup, DirectoryMode, FileDescriptorName, Service |
| `[Timer]` | OnCalendar (skróty, dni tygodnia, `*`, listy, zakresy `..`, kroki `/`), OnBootSec, OnStartupSec, OnActiveSec, OnUnitActiveSec, OnUnitInactiveSec, Persistent, Unit |
| `[Install]` | WantedBy, RequiredBy, Alias, Also, DefaultInstance |
| `[Mount]`/`[Swap]` | What, Where, Type, Options (wykonywane jako `mount`/`swapon`) |

## Nieobsługiwane (znane, ignorowane z ostrzeżeniem)

`DynamicUser`, `PrivateDevices`, `ProtectKernel*`, `ProtectControlGroups`, `RestrictAddressFamilies`, `SystemCallFilter`,
`MemoryDenyWriteExecute`, `RestrictNamespaces`, `LockPersonality`, `Accept=yes` (jednostka `.socket` kończy się błędem),
`ListenFIFO/SequentialPacket/UDP`, jednostki `.path`/`.device`/`.scope`/`.slice` (slice = pusty cel).

## Polecenia

`systemctl`: start stop restart reload try-restart reload-or-restart condrestart status show is-active is-failed is-enabled
enable disable mask unmask cat list-units list-unit-files list-jobs list-timers list-sockets list-dependencies get-default
set-default isolate default rescue emergency daemon-reload daemon-reexec reset-failed kill show-environment set-environment
unset-environment is-system-running poweroff reboot halt kexec analyze (time|blame). Opcje: `--user --no-block --now --no-reload
-a -t --state= --failed -p --value -n --signal= --kill-whom= -q --no-legend --no-pager` (ostatnia jest ignorowana).
Nieobsługiwane: suspend hibernate edit preset link revert.

`journalctl`: `-u -n -f -b -r -k -p -o (short|cat|json) -g -S/--since`.  `shutdown`: `now`, `+m`, `hh:mm`, `-r -h -P -H`.
`telinit N`: 0 poweroff, 6 reboot, 1/S rescue, 2-4 multi-user, 5 graphical, q reload.
`systemd-notify`: `--ready --status= --pid --reloading --stopping --booted KEY=VAL`.

## Co jest „udawane” (i czego nie)

- `NOTIFY_SOCKET` — prawdziwa implementacja protokołu sd_notify (jedno gniazdo na usługę).
- `LISTEN_FDS/LISTEN_PID/LISTEN_FDNAMES` — prawdziwa aktywacja gniazdem (`sd_listen_fds()` działa).
- `/dev/log` — prawdziwy odbiornik syslog (programy używające `syslog(3)` trafiają do dziennika).
- `/run/systemd/system` — tworzony **tylko** przy `CompatSdBooted=yes`. Programy, które po jego wykryciu zaczynają mówić
  D-Bus z `org.freedesktop.systemd1`, nie znajdą tam nikogo — dlatego domyślnie wyłączone.
- D-Bus, `sd_bus`, `loginctl`, `hostnamectl` itd. — **brak** i bez planów (zob. README, „Poza zakresem”).
