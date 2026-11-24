#!/usr/bin/env bash
# Test na żywo: prawdziwy zenitd (prawdziwa libc i jądro) w trybie --user, bez roota i bez PID 1.
# Użycie: ZENITD=/ścieżka/do/zenitd scripts/live-test.sh      (binarka z `zsc build --emit zbc` + `zsc0 bundle`)
#    albo: ZSC0=/ścieżka/do/zsc0 scripts/live-test.sh        (interpreter uruchamia src/main.zsharp)
# Wymaga interpretera/bundla z obsługą `extern` (stage0 z ffi.rs).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/zenitd-live.XXXXXX)"
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run"
U="$HOME/.config/zenit/user"
mkdir -p "$U" "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

if [ -n "${ZENITD:-}" ]; then BASE=("$ZENITD")
else BASE=("${ZSC0:-zsc0}" run "$HERE/src/main.zsharp"); fi
ctl()  { timeout 30 "${BASE[@]}" --applet=zenitctl --user "$@" 2>&1; }
jctl() { timeout 30 "${BASE[@]}" --applet=journalctl --user "$@" 2>&1; }

fails=0; total=0
check() { total=$((total + 1)); if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 got=[$2] want=[$3]"; fails=$((fails + 1)); fi; }
has()   { total=$((total + 1)); if printf '%s' "$2" | grep -q -- "$3"; then echo "ok   $1"; else echo "FAIL $1 (brak '$3')"; fails=$((fails + 1)); fi; }

cat > "$U/multi-user.target" <<'U1'
[Unit]
Description=Live test target
Wants=hello.service
U1
cat > "$U/hello.service" <<'U1'
[Service]
LimitNOFILE=4096
LimitCORE=infinity
ExecStart=/bin/sh -c 'echo nofile=$(ulimit -n) core=$(ulimit -c); sleep 300'
U1
cat > "$U/crash.service" <<'U1'
[Service]
ExecStart=/bin/sh -c 'exit 3'
Restart=on-failure
RestartSec=100ms
StartLimitBurst=3
StartLimitInterval=30s
U1
cat > "$U/once.service" <<'U1'
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/echo oneshot-done
U1
cat > "$U/ping.socket" <<U1
[Socket]
ListenStream=$XDG_RUNTIME_DIR/ping.sock
U1
cat > "$U/ping.service" <<U1
[Service]
ExecStart=/bin/sh -c 'echo activated >> $T/ping.out; sleep 1'
U1
cat > "$U/tick.timer" <<'U1'
[Timer]
OnActiveSec=1s
Unit=tickjob.service
U1
cat > "$U/tickjob.service" <<U1
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo tick >> $T/tick.out'
U1

setsid "${BASE[@]}" --applet=zenitd --user > "$T/daemon.log" 2>&1 < /dev/null &
DPID=$!; disown $DPID 2>/dev/null
trap 'kill -9 $DPID 2>/dev/null; pkill -x sleep 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do [ -S "$XDG_RUNTIME_DIR/zenit/control" ] && break; sleep 0.1; done

check "demon nasłuchuje" "$([ -S "$XDG_RUNTIME_DIR/zenit/control" ] && echo yes)" "yes"
sleep 0.5
check "hello.service aktywny po starcie celu" "$(ctl is-active hello.service)" "active"
has   "rlimity zastosowane (LimitNOFILE/CORE)" "$(jctl -u hello.service)" "nofile=4096 core=unlimited"
ctl stop hello.service >/dev/null
check "stop -> inactive" "$(ctl is-active hello.service)" "inactive"
sleep 0.3
check "stop zabija całą grupę (brak sleep)" "$(pgrep -x sleep | wc -l | tr -d ' ')" "0"
ctl start hello.service >/dev/null; ctl restart hello.service >/dev/null
check "restart -> active" "$(ctl is-active hello.service)" "active"

ctl start crash.service >/dev/null; sleep 2
has   "start-limit-hit po 3 szybkich startach" "$(ctl status crash.service)" "start-limit-hit"
ctl start once.service >/dev/null
has   "oneshot RemainAfterExit" "$(ctl status once.service)" "active (exited)"
has   "journalctl --user -u" "$(jctl --user -u once.service)" "oneshot-done"

ctl start ping.socket >/dev/null
sleep 0.3
python3 - "$XDG_RUNTIME_DIR/ping.sock" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.send(b"x"); s.close()
PY
sleep 1.5
has   "aktywacja gniazdem" "$(cat "$T/ping.out" 2>/dev/null)" "activated"
ctl start tick.timer >/dev/null; sleep 2.5
has   "timer uruchamia usługę" "$(cat "$T/tick.out" 2>/dev/null)" "tick"
check "brak wyjątków w pętli głównej" "$(grep -ac 'Wyjątek w pętli' "$XDG_RUNTIME_DIR/zenit/log/zenit.log" 2>/dev/null)" "0"

echo "razem: $total sprawdzeń, nieudanych: $fails"
exit $fails
