#!/usr/bin/env bash
# Build a self-bootstrapping .deb for Debian/Ubuntu.
# Produces funkeyone-wine_<ver>_amd64.deb.
#
# Design (see the note in README): a .deb CANNOT install Wine or build a
# per-user Wine prefix during its own dpkg install (root, no user session, apt
# lock held). So this package installs light, and the FIRST time the user
# launches "U.B. Funkeys" it auto-runs funkeyone-setup, which installs Wine +
# all deps (one password prompt), sets up the prefix, installs the game and
# applies the fixes, then launches. Two double-clicks, zero typed commands.
#
# Works without dpkg-deb (a .deb is just an `ar` archive). Needs: ar (binutils),
# tar, and x86_64-w64-mingw32-gcc to prebuild the two PE shims.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VER="${1:-1.0.0}"
PKGNAME="funkeyone-wine"
OUT="$REPO/${PKGNAME}_${VER}_amd64.deb"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
msg(){ printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# ---- 1. prebuild the portable PE shims --------------------------------------
msg "Building PE shims (mingw)"
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "need mingw-w64 gcc"; exit 1; }
( cd "$REPO/wineflash"  && ./build.sh >/dev/null )
( cd "$REPO/wineninput" && ./build.sh >/dev/null )

# ---- 2. data tree -----------------------------------------------------------
msg "Staging package tree"
D="$STAGE/data"
install -d "$D/usr/bin" \
          "$D/usr/lib/funkeyone/winebridge" \
          "$D/usr/lib/funkeyone/wineflash" \
          "$D/usr/lib/funkeyone/wineninput" \
          "$D/lib/udev/rules.d" \
          "$D/usr/share/applications" \
          "$D/usr/share/doc/$PKGNAME"

install -m755 "$REPO/funkeyone.sh"               "$D/usr/lib/funkeyone/funkeyone.sh"
install -m644 "$REPO/winebridge/bridge.c"        "$D/usr/lib/funkeyone/winebridge/"
install -m644 "$REPO/winebridge/bridge_unix.c"   "$D/usr/lib/funkeyone/winebridge/"
install -m644 "$REPO/winebridge/libusb-1.0.spec" "$D/usr/lib/funkeyone/winebridge/"
install -m644 "$REPO/wineflash/flashshim.dll"    "$D/usr/lib/funkeyone/wineflash/"
install -m644 "$REPO/wineninput/ninput.dll"      "$D/usr/lib/funkeyone/wineninput/"
install -m644 "$REPO/70-funkeys-hub.rules"       "$D/lib/udev/rules.d/70-funkeys-hub.rules"
install -m644 "$REPO/README.md"                  "$D/usr/share/doc/$PKGNAME/README.md"

# ---- runtime scripts (editable files under packaging/files/) ---------------
install -m755 "$REPO/packaging/files/funkeyone"       "$D/usr/bin/funkeyone"
install -m755 "$REPO/packaging/files/funkeyone-setup" "$D/usr/bin/funkeyone-setup"
install -m755 "$REPO/packaging/files/install-deps.sh" "$D/usr/lib/funkeyone/install-deps.sh"

# ---- icon --------------------------------------------------------------------
# The app icon is fetched from funkeyone.com's favicon by funkeyone-setup at
# install time and applied per-user on first run — so no game asset lives in
# this repo. The .desktop entries just reference the name.
ICON=funkeyone

# ---- menu entries (unquoted heredocs so $ICON expands) ----------------------
cat > "$D/usr/share/applications/funkeyone.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=U.B. Funkeys
Comment=Play U.B. Funkeys (FunkeyOne). First launch installs Wine and the game.
Exec=funkeyone
Icon=$ICON
Terminal=false
Categories=Game;
EOF
cat > "$D/usr/share/applications/funkeyone-setup.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=U.B. Funkeys — Setup / Repair
Comment=Re-run the Wine, game and portal setup
Exec=funkeyone-setup
Icon=$ICON
Terminal=false
Categories=Game;
NoDisplay=false
EOF

cat > "$D/usr/share/doc/$PKGNAME/copyright" <<'EOF'
Original support code (Wine shims, launcher, udev rule) for running the
third-party U.B. Funkeys / FunkeyOne game under Wine. No game assets and no
Adobe Flash are included; the user supplies the game.
EOF

# ---- 3. control -------------------------------------------------------------
msg "Writing control metadata"
C="$STAGE/control"; install -d "$C"
SIZE_KB="$(du -sk "$D" | cut -f1)"
# Deliberately light Depends so the .deb ALWAYS installs on one double-click.
# Wine + the heavy bits are installed by funkeyone-setup on first launch.
cat > "$C/control" <<EOF
Package: $PKGNAME
Version: $VER
Section: games
Priority: optional
Architecture: amd64
Maintainer: FunkeyOne on Linux <nobody@example.com>
Installed-Size: $SIZE_KB
Depends: sudo, xdg-user-dirs
Description: U.B. Funkeys (FunkeyOne) under Wine, with USB portal support
 Installs a small support layer for running the FunkeyOne U.B. Funkeys revival
 under Wine with a physical USB portal: a libusb bridge, a Flash de-licensing
 shim, an ninput stub and a udev rule. The first time you launch "U.B. Funkeys"
 it installs Wine and all dependencies, sets up the Wine prefix, installs the
 game and applies the fixes automatically (one password prompt) — then plays.
 The game itself is supplied by you (not included) for copyright reasons.
EOF

cat > "$C/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules 2>/dev/null || true
  udevadm trigger --attr-match=idVendor=0e4c 2>/dev/null || true
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || true
echo "Installed. Click 'U.B. Funkeys' in your menu — first launch sets up everything."
exit 0
EOF
cat > "$C/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then udevadm control --reload-rules 2>/dev/null || true; fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q || true
exit 0
EOF
chmod 755 "$C/postinst" "$C/postrm"
( cd "$D" && find . -type f -printf '%P\n' | while read -r f; do printf '%s  %s\n' "$(md5sum "$f" | cut -d' ' -f1)" "$f"; done ) > "$C/md5sums"

# ---- 4. assemble the .deb ---------------------------------------------------
msg "Packing $OUT"
echo "2.0" > "$STAGE/debian-binary"
( cd "$C" && tar --owner=0 --group=0 -czf "$STAGE/control.tar.gz" ./* )
( cd "$D" && tar --owner=0 --group=0 -czf "$STAGE/data.tar.gz" ./* )
rm -f "$OUT"
# Assemble the .deb as a canonical ar archive ourselves — works on any build
# host (no dpkg-deb needed) and gives identical output. Member names are
# space-padded with NO trailing slash (GNU `ar` adds a slash that stricter
# dpkg tooling rejects).
python3 - "$OUT" "$STAGE/debian-binary" "$STAGE/control.tar.gz" "$STAGE/data.tar.gz" <<'PY'
import sys
out, members = sys.argv[1], sys.argv[2:]
with open(out, 'wb') as f:
    f.write(b'!<arch>\n')
    for m in members:
        data = open(m, 'rb').read()
        name = m.rsplit('/', 1)[-1]
        hdr = (name.ljust(16) + '0'.ljust(12) + '0'.ljust(6) + '0'.ljust(6)
               + '100644'.ljust(8) + str(len(data)).ljust(10)).encode() + b'\x60\n'
        assert len(hdr) == 60
        f.write(hdr); f.write(data)
        if len(data) % 2: f.write(b'\n')
PY
msg "Built: $OUT"
ls -la "$OUT"
echo
echo "Install: double-click it, or  sudo apt install $OUT"
echo "Then click 'U.B. Funkeys' — first launch installs Wine + the game automatically."
