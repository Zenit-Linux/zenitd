#!/usr/bin/env bash
# Uruchamia VM z zenitd jako PID 1 i sprawdza wynik selftestu.
# Użycie: KERNEL=/ścieżka/vmlinuz scripts/vm/run.sh <reboot|poweroff> [katalog-wyjściowy] [timeout-s]
# Kryterium: ZTEST-RESULT ... fail=0 oraz komunikat jądra „Restarting system" (reboot) / „Power down" (poweroff).
# Jądro: np. `apt-get download linux-image-<wersja>-generic && dpkg-deb -x … ex` → ex/boot/vmlinuz-*.
set -u
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
END="${1:-reboot}"; OUT="${2:-$HERE/build/vm}"; T="${3:-300}"
KERNEL="${KERNEL:?ustaw KERNEL=ścieżka do vmlinuz}"
LOG="$OUT/vm-$END.log"; rm -f "$LOG"
timeout "$T" qemu-system-x86_64 -m 1024 -smp 1 -nographic -no-reboot -nodefaults -serial stdio -display none \
  -kernel "$KERNEL" -initrd "$OUT/initramfs.gz" \
  -append "console=ttyS0 panic=-1 rdinit=/sbin/init loglevel=4 ztest.end=$END" > "$LOG" 2>&1 < /dev/null
grep -a "ZTEST FAIL" "$LOG" | tr -d '\r'
grep -a "ZTEST-RESULT" "$LOG" | tr -d '\r'
want="Restarting system"; [ "$END" = poweroff ] && want="Power down"
ok=1
grep -aq "ZTEST-RESULT checks=[0-9]* fail=0" "$LOG" || ok=0
grep -aq "reboot: $want" "$LOG" || { echo "brak 'reboot: $want' w logu jądra"; ok=0; }
[ $ok = 1 ] && echo "VM $END: OK" || echo "VM $END: BŁĄD (log: $LOG)"
[ $ok = 1 ]
