#!/usr/bin/env bash
# Testy zenitd w interpreterze stage0 (zsc0) z fałszywą warstwą Sys (tests/fake) — bez roota i bez jądra.
# Użycie: ZSC0=/ścieżka/do/zsc0 scripts/test.sh
set -u
ZSC0="${ZSC0:-zsc0}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE/tests"
export ZS_WORKSPACE="$HERE/tests/fake"
total=0; bad=0
for t in t_util t_core t_exec t_manager t_more t_units; do
    out="$(timeout 300 "$ZSC0" run "$t.zsharp" 2>&1)"; rc=$?
    ok=$(printf '%s\n' "$out" | grep -c '^ok')
    fl=$(printf '%s\n' "$out" | grep -c '^FAIL')
    printf '%-12s ok=%-4s fail=%-3s rc=%s\n' "$t" "$ok" "$fl" "$rc"
    printf '%s\n' "$out" | grep '^FAIL'
    total=$((total + ok)); if [ "$rc" -ne 0 ] || [ "$fl" -ne 0 ]; then bad=$((bad + 1)); fi
done
echo "razem: $total asercji, nieudanych zestawów: $bad"
exit $bad
