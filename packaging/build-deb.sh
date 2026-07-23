#!/usr/bin/env bash
# Build a self-bootstrapping .deb for Debian/Ubuntu.
# Produces funkeyone-wine_<ver>_amd64.deb.
#
# Ships ONLY our own code — the native USB daemon + a PE libusb proxy, the
# Flash/ninput shims, the launcher, the udev rule, an icon and the setup
# scripts. NO game or Adobe binaries are packaged: on first launch,
# funkeyone-setup downloads the game and EXTRACTS the revival client out of the
# user's own installer (extract-payload.py). The user supplies the game.
#
# A .deb CANNOT install Wine or build a per-user Wine prefix during its own
# dpkg install (root, no user session, apt lock held), so the package installs
# light and the FIRST launch runs funkeyone-setup (one password prompt).
#
# Works without dpkg-deb (a .deb is just an `ar` archive). Needs: ar (binutils),
# tar, python3, and x86_64-w64-mingw32-gcc to prebuild the PE shims + proxy.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VER="${1:-1.0.0}"
PKGNAME="funkeyone-wine"
OUT="$REPO/${PKGNAME}_${VER}_amd64.deb"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
msg(){ printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# ---- 1. prebuild the PE shims + the PE libusb proxy (mingw) ------------------
msg "Building PE shims + libusb proxy (mingw)"
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "need mingw-w64 gcc"; exit 1; }
( cd "$REPO/wineflash"  && ./build.sh >/dev/null )
( cd "$REPO/wineninput" && ./build.sh >/dev/null )
x86_64-w64-mingw32-gcc -O2 -shared "$REPO/packaging/winebridge/libusb_pe.c" \
    -o "$STAGE/libusb-1.0.dll" -lws2_32

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

# launcher (daemon variant) + the native-bridge sources built on first run
install -m755 "$REPO/packaging/files/funkeyone.sh"      "$D/usr/lib/funkeyone/funkeyone.sh"
install -m644 "$REPO/packaging/winebridge/funkeyusbd.c" "$D/usr/lib/funkeyone/winebridge/"
install -m644 "$REPO/packaging/winebridge/bridge_unix.c" "$D/usr/lib/funkeyone/winebridge/"
install -m644 "$REPO/packaging/winebridge/portalcheck.c" "$D/usr/lib/funkeyone/winebridge/"
install -m644 "$STAGE/libusb-1.0.dll"                   "$D/usr/lib/funkeyone/winebridge/libusb-1.0.dll"
# prebuilt PE shims (our code)
install -m644 "$REPO/wineflash/flashshim.dll"           "$D/usr/lib/funkeyone/wineflash/"
install -m644 "$REPO/wineninput/ninput.dll"             "$D/usr/lib/funkeyone/wineninput/"
# udev rule + docs
install -m644 "$REPO/70-funkeys-hub.rules"              "$D/lib/udev/rules.d/70-funkeys-hub.rules"
install -m644 "$REPO/README.md"                         "$D/usr/share/doc/$PKGNAME/README.md"

# ---- runtime scripts (editable files under packaging/files/) ---------------
install -m755 "$REPO/packaging/files/funkeyone"        "$D/usr/bin/funkeyone"
install -m755 "$REPO/packaging/files/funkeyone-setup"  "$D/usr/bin/funkeyone-setup"
install -m755 "$REPO/packaging/files/install-deps.sh"  "$D/usr/lib/funkeyone/install-deps.sh"
install -m755 "$REPO/packaging/files/extract-payload.py" "$D/usr/lib/funkeyone/extract-payload.py"

# ---- icon --------------------------------------------------------------------
# Fetch the FunkeyOne logo at BUILD time and ship it as a named icon (no runtime
# download, no fragile .ico). Fetched, not committed. Falls back to a stock name.
ICON=applications-games
install -d "$D/usr/share/pixmaps"
if curl -fsSL -o "$D/usr/share/pixmaps/funkeyone.png" \
        "https://www.funkeyone.com/images/funkeyone.png" 2>/dev/null \
   && [ -s "$D/usr/share/pixmaps/funkeyone.png" ]; then
  ICON=funkeyone
  if command -v magick >/dev/null 2>&1; then
    install -d "$D/usr/share/icons/hicolor/256x256/apps"
    magick "$D/usr/share/pixmaps/funkeyone.png" -background none -gravity center \
      -resize 256x256 -extent 256x256 \
      "$D/usr/share/icons/hicolor/256x256/apps/funkeyone.png" 2>/dev/null || true
  fi
fi

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
StartupWMClass=funkeyone.exe
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
Original support code (native USB daemon + PE libusb proxy, Wine shims,
launcher, udev rule, payload extractor) for running the third-party U.B.
Funkeys / FunkeyOne game under Wine. No game assets and no Adobe Flash are
included or distributed; the user supplies the game, and the revival client is
extracted on the user's machine from the user's own installer.
EOF

# ---- 3. control -------------------------------------------------------------
msg "Writing control metadata"
C="$STAGE/control"; install -d "$C"
SIZE_KB="$(du -sk "$D" | cut -f1)"
# Light Depends so the .deb ALWAYS installs on one double-click. gcc +
# libusb-1.0-0-dev build the native daemon on first run; python3 + unzip drive
# the payload extraction; Wine itself is installed by funkeyone-setup.
cat > "$C/control" <<EOF
Package: $PKGNAME
Version: $VER
Section: games
Priority: optional
Architecture: amd64
Maintainer: FunkeyOne on Linux <nobody@example.com>
Installed-Size: $SIZE_KB
Depends: sudo, xdg-user-dirs, pkexec | policykit-1, zenity, curl, wget, unzip, ca-certificates, python3, gcc, libusb-1.0-0-dev
Description: U.B. Funkeys (FunkeyOne) under Wine, with USB portal support
 Installs a small support layer for running the FunkeyOne U.B. Funkeys revival
 under Wine with a physical USB portal: a native libusb daemon plus a PE proxy,
 a Flash de-licensing shim, an ninput stub and a udev rule. The first time you
 launch "U.B. Funkeys" it installs Wine and all dependencies, sets up the Wine
 prefix, downloads the game, extracts the revival client from your installer and
 applies the fixes automatically (one password prompt) — then plays.
 No game assets are included; you supply the game, for copyright reasons.
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
# host (no dpkg-deb needed). Member names are space-padded with NO trailing
# slash (GNU `ar` adds a slash that stricter dpkg tooling rejects).
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
