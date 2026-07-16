#!/usr/bin/env bash
# One-shot setup for running U.B. Funkeys (FunkeyOne) + the physical USB portal
# on Arch Linux under Wine. Safe to re-run (idempotent).
#
# What it does:
#   1. checks system packages (wine, winetricks, libusb, gcc, mingw-w64-gcc)
#   2. sets up the Wine prefix with real .NET 4.8 (winetricks dotnet48)
#   3. installs the game if not already installed (runs UBFunkeys-Setup-x64.exe)
#   4. builds the USB libusb bridge (winelib) if the prebuilt one is absent
#   5. swaps the Flash de-licensing shim into the game (Flash.ocx<->FlashReal.ocx)
#   6. drops the ninput no-op stub into the game dir
#   7. installs the udev rule (needs sudo) so your user can open the portal
#
# Run: ./setup.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
say() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 1. system packages ------------------------------------------------------
say "Checking system packages"
need_pkg=()
for p in wine winetricks libusb gcc mingw-w64-gcc; do
  pacman -Q "$p" >/dev/null 2>&1 || need_pkg+=("$p")
done
if ((${#need_pkg[@]})); then
  warn "missing packages: ${need_pkg[*]}"
  echo "    install them with:  sudo pacman -S --needed ${need_pkg[*]}"
  echo "    (also enable the multilib repo if wine complains about 32-bit deps)"
  read -rp "    install now with sudo? [y/N] " a
  [[ "$a" == [yY] ]] && sudo pacman -S --needed "${need_pkg[@]}"
fi
command -v wine >/dev/null || die "wine not found"

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
say "Using WINEPREFIX=$WINEPREFIX"

# ---- 2. .NET 4.8 in the prefix ----------------------------------------------
if wine reg query "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Version 2>/dev/null | grep -q "4\."; then
  say ".NET 4.x already present in prefix — skipping dotnet48"
else
  say "Installing .NET 4.8 into the prefix (winetricks dotnet48 — this is slow)"
  winetricks -q dotnet48
fi

# ---- 3. game install ---------------------------------------------------------
find_home() {
  local c
  for c in "$(xdg-user-dir DOCUMENTS 2>/dev/null)/U.B. Funkeys" \
           "$HOME/Documents/U.B. Funkeys" "$HOME/Dokumente/U.B. Funkeys"; do
    [ -d "$c/RadicaGame" ] && { echo "$c"; return; }
  done
}
FUNKEY_HOME="$(find_home || true)"
if [ -z "${FUNKEY_HOME:-}" ]; then
  installer="$HERE/UBFunkeys-Setup-x64.exe"
  [ -f "$installer" ] || die "game not installed and $installer missing. Put the installer next to setup.sh."
  say "Installing the game (running the Windows installer under Wine)"
  wine "$installer" || true
  FUNKEY_HOME="$(find_home || true)"
  [ -n "${FUNKEY_HOME:-}" ] || die "install finished but 'U.B. Funkeys/RadicaGame' not found."
fi
say "Game install: $FUNKEY_HOME"
GAME_DIR="$FUNKEY_HOME/RadicaGame"

# ---- 4. build the USB bridge if needed --------------------------------------
if [ ! -f "$HERE/winebridge/libusb-1.0.dll.so" ]; then
  say "Building the libusb bridge"
  ( cd "$HERE/winebridge" && ./build.sh )
else
  say "libusb bridge present (winebridge/libusb-1.0.dll.so)"
fi

# ---- 5. Flash de-licensing shim swap ----------------------------------------
say "Installing the Flash de-licensing shim"
[ -f "$HERE/wineflash/flashshim.dll" ] || ( cd "$HERE/wineflash" && ./build.sh )
cd "$GAME_DIR"
if [ ! -f FlashReal.ocx ]; then
  # genuine Adobe control is the big one; back it up and rename
  cp -n Flash.ocx Flash.ocx.orig-backup
  mv Flash.ocx FlashReal.ocx
fi
cp "$HERE/wineflash/flashshim.dll" Flash.ocx          # shim takes Flash.ocx's place
# keep the registry pointing at the genuine control for non-manifest callers
wine reg add 'HKCR\CLSID\{D27CDB6E-AE6D-11cf-96B8-444553540000}\InprocServer32' \
  /ve /d "$(wine winepath -w "$GAME_DIR/FlashReal.ocx" 2>/dev/null | tr -d '\r')" /f >/dev/null 2>&1 || true

# ---- 6. ninput no-op stub ----------------------------------------------------
say "Installing the ninput stub into the game dir"
[ -f "$HERE/wineninput/ninput.dll" ] || ( cd "$HERE/wineninput" && ./build.sh )
cp "$HERE/wineninput/ninput.dll" "$GAME_DIR/ninput.dll"

# ---- 7. udev rule ------------------------------------------------------------
say "Installing the USB portal udev rule (needs sudo)"
if [ ! -f /etc/udev/rules.d/70-funkeys-hub.rules ]; then
  sudo cp "$HERE/70-funkeys-hub.rules" /etc/udev/rules.d/70-funkeys-hub.rules
  sudo rm -f /etc/udev/rules.d/99-ubfunkeys.rules   # remove any earlier bad-ordered copy
  sudo udevadm control --reload-rules
  sudo udevadm trigger --attr-match=idVendor=0e4c || true
  echo "    (unplug and replug the portal once)"
else
  echo "    rule already installed"
fi

say "Done. Launch the game with:  $HERE/funkeyone.sh"
