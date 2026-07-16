#!/usr/bin/env bash
# One-shot setup for running U.B. Funkeys (FunkeyOne) + the physical USB portal
# on Linux under Wine. Works on Arch, Debian/Ubuntu, Fedora and openSUSE.
# Safe to re-run (idempotent).
#
# What it does:
#   1. checks/installs system packages (wine, winetricks, libusb, gcc, mingw)
#      — auto-detects pacman / apt / dnf / zypper
#   2. sets up the Wine prefix with real .NET 4.8 (winetricks dotnet48)
#   3. installs the game if not already installed (runs UBFunkeys-Setup-x64.exe)
#   4. builds the USB libusb bridge (winelib) if the prebuilt one is absent
#   5. swaps the Flash de-licensing shim into the game (Flash.ocx<->FlashReal.ocx)
#   6. drops the ninput no-op stub into the game dir
#  6b. marks MegaByte up to date (stops the driver-installer update from crashing)
#   7. installs the udev rule (needs sudo) so your user can open the portal
#      (with a group fallback for non-systemd distros)
#   8. adds an application-menu entry
#
# Needs a recent Wine (11.x+, WoW64). Distros with an old Wine (e.g. Debian/
# Ubuntu stable) should use the WineHQ repo: https://wiki.winehq.org/Download
#
# Run: ./setup.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
say() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 1. system packages (distro-agnostic) -----------------------------------
say "Checking system packages"

if   command -v pacman  >/dev/null 2>&1; then PM=pacman
elif command -v apt-get >/dev/null 2>&1; then PM=apt
elif command -v dnf     >/dev/null 2>&1; then PM=dnf
elif command -v zypper  >/dev/null 2>&1; then PM=zypper
else PM=unknown; fi

# package names per distro: wine, winetricks, libusb+headers, gcc, mingw,
# and (dnf/zypper) the wine dev tools that provide winegcc.
case "$PM" in
  pacman) PKGS=(wine winetricks libusb gcc mingw-w64-gcc); PM_INSTALL=(sudo pacman -S --needed) ;;
  apt)    PKGS=(wine winetricks libusb-1.0-0-dev gcc gcc-mingw-w64-x86-64); PM_INSTALL=(sudo apt-get install -y) ;;
  dnf)    PKGS=(wine wine-devel winetricks libusb1-devel gcc mingw64-gcc); PM_INSTALL=(sudo dnf install -y) ;;
  zypper) PKGS=(wine wine-devel winetricks libusb-1_0-devel gcc cross-x86_64-w64-mingw32-gcc); PM_INSTALL=(sudo zypper install -y) ;;
  *)      PKGS=() ;;
esac

# probe for the tools/files we actually need (more reliable than package names)
missing=()
command -v wine       >/dev/null 2>&1 || missing+=("wine")
command -v winetricks >/dev/null 2>&1 || missing+=("winetricks")
command -v gcc        >/dev/null 2>&1 || missing+=("gcc")
command -v winegcc    >/dev/null 2>&1 || missing+=("winegcc (wine dev tools)")
command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 || missing+=("mingw-w64 gcc")
[ -f /usr/include/libusb-1.0/libusb.h ] || missing+=("libusb dev headers")

if ((${#missing[@]})); then
  warn "missing: ${missing[*]}"
  if [ "$PM" = unknown ] || ((${#PKGS[@]}==0)); then
    echo "    Unknown package manager — install manually: a recent Wine (incl. winegcc),"
    echo "    winetricks, libusb + dev headers, gcc, and the mingw-w64 GCC cross-compiler."
  else
    echo "    install with:  ${PM_INSTALL[*]} ${PKGS[*]}"
    [ "$PM" = apt ] && echo "    NOTE: Debian/Ubuntu often ship an old Wine — if the game misbehaves, use the WineHQ repo (https://wiki.winehq.org/Download)."
    read -rp "    install now with sudo? [y/N] " a || a=n
    if [[ "${a:-n}" == [yY] ]]; then
      [ "$PM" = apt ] && { sudo apt-get update || true; }
      "${PM_INSTALL[@]}" "${PKGS[@]}"
    fi
  fi
fi
command -v wine >/dev/null 2>&1 || die "wine not found — install it and re-run."
command -v winegcc >/dev/null 2>&1 || warn "winegcc missing — the USB bridge can't be built (install your distro's wine dev tools)."
command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 || warn "mingw missing — the Flash/ninput shims can't be built."

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

# ---- 6b. neutralise the self-crashing MegaByte "update" ---------------------
# The in-game updater checks HKCU\Software\OpenFK\FunkeyOne\MegaByteVersion. On
# a fresh install that value is missing, so it reads as "0", thinks MegaByte is
# out of date (server: 1.0.1.0), downloads the update and runs the libusbK
# *driver* installer — which cannot work under Wine and crashes the game right
# after the download finishes. We don't need that driver (the bridge replaces
# it), so we mark MegaByte as already up to date, exactly as a successful update
# would. Matches the version of the bundled MegaByte.exe.
say "Marking MegaByte up to date (prevents the driver-installer update crash)"
MB_VER="$(strings "$FUNKEY_HOME/MegaByte/MegaByte.exe" 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1)"
MB_VER="${MB_VER:-1.0.1.0}"
wine reg add 'HKCU\Software\OpenFK\FunkeyOne' /v MegaByteVersion /t REG_SZ /d "$MB_VER" /f >/dev/null 2>&1 || true

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
# The rule's TAG+="uaccess" needs systemd-logind (or elogind) to grant your
# login session the device ACL. On non-systemd distros it does nothing, so
# point the user at a group-based fallback.
if [ -d /run/systemd/system ] || command -v loginctl >/dev/null 2>&1; then
  : # systemd-logind present — uaccess handles access
else
  warn "no systemd-logind detected — 'uaccess' won't grant portal access on this system."
  echo "    Fix: install elogind, or use a group-based rule and join the group:"
  echo "      echo 'SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"0e4c\", ATTRS{idProduct}==\"7288\", MODE=\"0660\", GROUP=\"plugdev\"' | sudo tee /etc/udev/rules.d/70-funkeys-hub.rules"
  echo "      sudo groupadd -f plugdev && sudo usermod -aG plugdev \"$USER\""
  echo "      sudo udevadm control --reload-rules && sudo udevadm trigger --attr-match=idVendor=0e4c"
  echo "      (then re-login and replug the portal)"
fi

# ---- 8. application-menu entry ----------------------------------------------
if [ -x "$HERE/install-menu.sh" ]; then
  say "Adding the application-menu entry"
  "$HERE/install-menu.sh" || warn "menu entry failed (non-fatal)"
fi

say "Done. Launch \"U.B. Funkeys\" from your menu, or run:  $HERE/funkeyone.sh"
