#!/bin/sh
# Test wewnątrz maszyny wirtualnej: zenitd jako PID 1 na prawdziwym jądrze.
say() { echo "ZTEST $*" > /dev/console; echo "ZTEST $*" >> /ztest.log; }
FAIL=0; N=0
ok()  { N=$((N+1)); say "ok   $1"; }
bad() { N=$((N+1)); FAIL=$((FAIL+1)); say "FAIL $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 got=[$2] want=[$3]"; fi; }
has() { if echo "$2" | grep -q -- "$3"; then ok "$1"; else bad "$1 (brak '$3' w [$2])"; fi; }
ctl() { /usr/bin/zenitctl "$@" 2>&1; }
sleep 2

say "== PID 1 i rozruch"
chk "zenitd jest PID 1" "$(tr '\0' ' ' < /proc/1/cmdline | cut -d' ' -f1)" "/sbin/init"
has "cgroup2 zamontowany" "$(cat /proc/mounts)" "cgroup2 /sys/fs/cgroup"
has "devpts zamontowany" "$(cat /proc/mounts)" " /dev/pts "
has "tmpfs /run" "$(cat /proc/mounts)" "tmpfs /run "
chk "hostname z /etc/hostname" "$(cat /proc/sys/kernel/hostname)" "zenitvm"
chk "machine-id ma 32 znaki" "$(wc -c < /etc/machine-id | tr -d ' ')" "33"
chk "multi-user.target aktywny" "$(ctl is-active multi-user.target)" "active"
has "is-system-running" "$(ctl is-system-running)" "running\|degraded\|starting"

say "== cgroup v2"
has "kontrolery cgroup v2" "$(cat /sys/fs/cgroup/cgroup.controllers)" "memory"
ctl start cg.service > /dev/null; sleep 1
P="$(sed -n 's/^0:://p' /run/cg.path)"
say "   cgroup usługi: $P"
chk "usługa w grupie zenit.slice" "$(echo "$P" | cut -d/ -f2)" "zenit.slice"
chk "memory.max z MemoryMax=64M" "$(cat /sys/fs/cgroup$P/memory.max 2>&1)" "67108864"
chk "pids.max z TasksMax=50" "$(cat /sys/fs/cgroup$P/pids.max 2>&1)" "50"
chk "cpu.weight z CPUWeight=200" "$(cat /sys/fs/cgroup$P/cpu.weight 2>&1)" "200"
ctl start kids.service > /dev/null; sleep 1
chk "kids: 3 procesy w cgroup (sh + 2 podpowłoki)" "$(wc -l < /sys/fs/cgroup/zenit.slice/kids.service/cgroup.procs | tr -d ' ')" "3"
ctl stop kids.service > /dev/null; sleep 1
chk "stop zabija całą cgroup" "$(ps -o args | grep -c '[s]leep 11')" "0"
chk "katalog cgroup usunięty po stopie" "$([ -d /sys/fs/cgroup/zenit.slice/kids.service ] && echo exists || echo gone)" "gone"

say "== Type=notify (prawdziwy sd_notify)"
ctl start nt.service > /dev/null
chk "notify: active po READY=1" "$(ctl is-active nt.service)" "active"
has "notify: STATUS=" "$(ctl status nt.service)" "gotowe"
ctl start ntslow.service > /dev/null
chk "notify bez READY: nie jest active" "$(ctl is-active ntslow.service)" "failed"

say "== Type=forking"
ctl start fk.service > /dev/null
chk "forking z PIDFile: active" "$(ctl is-active fk.service)" "active"
ctl start fk2.service > /dev/null
chk "forking bez PIDFile: active" "$(ctl is-active fk2.service)" "active"
ctl stop fk.service > /dev/null; ctl stop fk2.service > /dev/null; sleep 1
chk "forking: stop kończy demony" "$(ps -o args | grep -c '[s]leep 4')" "0"

say "== PID 1 zbiera zombie"
ctl start orphan.service > /dev/null; sleep 2
chk "brak zombie po osieroceniu" "$(ps -o stat | grep -c '^Z')" "0"

say "== zamykanie"
say "ZTEST-RESULT checks=$N fail=$FAIL"
END="$(sed -n 's/.*ztest.end=\([a-z]*\).*/\1/p' /proc/cmdline)"
say "zamykanie: $END"
if [ "$END" = "poweroff" ]; then ctl poweroff; else ctl reboot; fi
sleep 120
