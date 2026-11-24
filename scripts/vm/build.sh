#!/usr/bin/env bash
# Buduje initramfs z zenitd jako /sbin/init (bundle .zbc) + busybox + jednostki testowe + selftest.
# Użycie: ZENITD=/ścieżka/do/zenitd scripts/vm/build.sh [katalog-wyjściowy]
# Wymaga: busybox-static (statyczny busybox), cpio, gzip, libc/libm/libgcc_s hosta (bundle to dynamiczny ELF).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$HERE/build/vm}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
ZENITD="${ZENITD:?ustaw ZENITD=ścieżka do binarki zenitd (zsc build --emit zbc + zsc0 bundle)}"
BB="${BUSYBOX:-$(command -v busybox)}"
R="$OUT/rootfs"; rm -rf "$R"
mkdir -p "$R"/{bin,sbin,usr/bin,usr/lib/zenit/system,etc/zenit/system/multi-user.target.wants,lib/x86_64-linux-gnu,lib64,proc,sys,dev,run,tmp,var/log,root}
cp "$BB" "$R/bin/busybox"
for a in sh ps grep sed tr cut wc cat sleep echo ls tail head mkdir rm touch kill id mount sync date true false test hostname; do ln -sf busybox "$R/bin/$a"; done
for l in libc.so.6 libm.so.6 libgcc_s.so.1; do cp -L "/lib/x86_64-linux-gnu/$l" "$R/lib/x86_64-linux-gnu/"; done
cp -L /lib64/ld-linux-x86-64.so.2 "$R/lib64/"
cp "$ZENITD" "$R/sbin/init"
for a in zenitctl systemctl journalctl systemd-notify reboot poweroff halt shutdown; do ln -sf ../../sbin/init "$R/usr/bin/$a"; done
cp "$HERE"/data/units/* "$R/usr/lib/zenit/system/"
echo zenitvm > "$R/etc/hostname"
cp "$HERE/scripts/vm/selftest.sh" "$R/usr/lib/zenit/selftest.sh"; chmod +x "$R/usr/lib/zenit/selftest.sh"
U="$R/etc/zenit/system"
cat > "$U/selftest.service" <<'U1'
[Unit]
Description=Self-test zenitd w VM
[Service]
Type=simple
ExecStart=/bin/sh /usr/lib/zenit/selftest.sh
U1
ln -sf ../selftest.service "$U/multi-user.target.wants/selftest.service"
cat > "$U/cg.service" <<'U1'
[Service]
MemoryMax=64M
TasksMax=50
CPUWeight=200
ExecStart=/bin/sh -c 'cat /proc/self/cgroup > /run/cg.path; sleep 300'
U1
cat > "$U/kids.service" <<'U1'
[Service]
ExecStart=/bin/sh -c 'sleep 111 & sleep 112 & wait'
U1
cat > "$U/nt.service" <<'U1'
[Service]
Type=notify
NotifyAccess=all
ExecStart=/bin/sh -c '/usr/bin/systemd-notify --ready --status=gotowe; sleep 300'
U1
cat > "$U/ntslow.service" <<'U1'
[Service]
Type=notify
TimeoutStartSec=3s
ExecStart=/bin/sh -c 'sleep 300'
U1
cat > "$U/fk.service" <<'U1'
[Service]
Type=forking
PIDFile=/run/fk.pid
ExecStart=/bin/sh -c '(sleep 40 & echo $! > /run/fk.pid); exit 0'
U1
cat > "$U/fk2.service" <<'U1'
[Service]
Type=forking
ExecStart=/bin/sh -c 'sleep 41 & exit 0'
U1
cat > "$U/orphan.service" <<'U1'
[Service]
Type=oneshot
ExecStart=/bin/sh -c '(sh -c "sleep 0.2" &) ; (sh -c "exit 3" &) ; exit 0'
U1
(cd "$R" && find . | cpio -o -H newc 2>/dev/null | gzip -1 > "$OUT/initramfs.gz")
echo "initramfs: $OUT/initramfs.gz"
