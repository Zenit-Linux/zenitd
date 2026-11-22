#!/usr/bin/env bash
# Sprawdza, czy cały zenitd mieści się w podzbiorze Z# obsługiwanym przez backend natywny:
# linker Z# (importy, moduły) + obniżenie do IR (ir.lower). Wymaga repozytorium Z-Sharp (ZSHARP_HOME).
# Oczekiwany wynik: wyłącznie błędy dotyczące `extern` (blok extern + wywołania libc), dopóki backend nie linkuje extern.
set -eu
: "${ZSHARP_HOME:?ustaw ZSHARP_HOME na katalog repozytorium Z-Sharp}"
ZSC0="${ZSC0:-$ZSHARP_HOME/target/release/zsc0}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cp "$HERE/scripts/native_check.zsharp" "$ZSHARP_HOME/tests/zenitd_native_check.zsharp"
"$ZSC0" run "$ZSHARP_HOME/tests/zenitd_native_check.zsharp" "$HERE/src/main.zsharp" > /tmp/zenitd_native.txt 2>&1 || true
python3 - "$HERE/src/main.zsharp" <<'PY'
import re, sys
main = open(sys.argv[1]).read()
blk = main[main.index('extern "c"'):main.index('import Workspace.sys')]
ext = set(re.findall(r'func (\w+)\(', blk))
other = []
for l in open('/tmp/zenitd_native.txt'):
    if l.startswith(('IR line', 'LINK')):
        m = re.search(r'funkcja `(\w+)`', l)
        if m and m.group(1) in ext: continue
        if 'instrukcja Extern' in l: continue
        other.append(l.strip())
print("deklaracji extern:", len(ext))
print("problemów poza extern:", len(other))
for o in other: print(" ", o)
sys.exit(1 if other else 0)
PY
