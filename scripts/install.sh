#!/usr/bin/env bash
# Instalacja zenitd: binarka, aplety (symlinki), jednostki domyślne i konfiguracja.
# Użycie: DESTDIR=/tmp/rootfs PREFIX=/usr scripts/install.sh [--no-compat] [--no-build]
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${PREFIX:-/usr}"
DESTDIR="${DESTDIR:-}"
COMPAT=1; BUILD=1
for a in "$@"; do case "$a" in --no-compat) COMPAT=0;; --no-build) BUILD=0;; esac; done

if [ "$BUILD" = 1 ]; then (cd "$HERE" && z# build --release); fi
BIN="$HERE/target/release/zenitd"
[ -x "$BIN" ] || { echo "brak $BIN — zbuduj: z# build --release" >&2; exit 1; }

install -d "$DESTDIR$PREFIX/lib/zenit/system" "$DESTDIR$PREFIX/bin" "$DESTDIR/sbin" "$DESTDIR/etc/zenit/system" "$DESTDIR$PREFIX/share/zenit/examples"
install -m 0755 "$BIN" "$DESTDIR$PREFIX/lib/zenit/zenitd"
install -m 0644 "$HERE"/data/units/* "$DESTDIR$PREFIX/lib/zenit/system/"
install -m 0644 "$HERE"/data/examples/* "$DESTDIR$PREFIX/share/zenit/examples/"
[ -e "$DESTDIR/etc/zenit/zenit.conf" ] || install -m 0644 "$HERE/data/conf/zenit.conf" "$DESTDIR/etc/zenit/zenit.conf"

ln -sf "../usr/lib/zenit/zenitd" "$DESTDIR/sbin/init"
ln -sf "$PREFIX/lib/zenit/zenitd" "$DESTDIR/sbin/zenitd"
for t in zenitctl zenit-notify; do ln -sf "../lib/zenit/zenitd" "$DESTDIR$PREFIX/bin/$t"; done
if [ "$COMPAT" = 1 ]; then
    for t in systemctl journalctl systemd-notify reboot poweroff halt shutdown telinit; do
        ln -sf "../lib/zenit/zenitd" "$DESTDIR$PREFIX/bin/$t"
    done
fi
# domyślny cel i podstawowe włączenia
[ -e "$DESTDIR/etc/zenit/system/default.target" ] || ln -s "$PREFIX/lib/zenit/system/multi-user.target" "$DESTDIR/etc/zenit/system/default.target"
install -d "$DESTDIR/etc/zenit/system/getty.target.wants" "$DESTDIR/etc/zenit/system/multi-user.target.wants"
[ -e "$DESTDIR/etc/zenit/system/getty.target.wants/getty@tty1.service" ] || ln -s "$PREFIX/lib/zenit/system/getty@.service" "$DESTDIR/etc/zenit/system/getty.target.wants/getty@tty1.service"
[ -e "$DESTDIR/etc/zenit/system/multi-user.target.wants/getty.target" ] || ln -s "$PREFIX/lib/zenit/system/getty.target" "$DESTDIR/etc/zenit/system/multi-user.target.wants/getty.target"
echo "zenitd zainstalowany w ${DESTDIR:-/} (prefix $PREFIX). Jądro: init=/sbin/init"
