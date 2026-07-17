#!/usr/bin/env bash
# Launch U.B. Funkeys (FunkeyOne) under Wine on Linux, with the USB portal.
#
# Applies at runtime:
#   * USB portal bridge — winebridge/libusb-1.0.dll.so replaces the Windows
#     libusb-1.0.dll (which needs the libusbK kernel driver). Both the game
#     and MegaByte.exe inherit the env below, so the bridge is active.
#   * ninput no-op       — the game dir's ninput.dll replaces Wine's builtin,
#     whose StopInteractionContext stub otherwise aborts the process.
#   * Flash de-licensing — on disk: the game's Flash.ocx is the shim, the real
#     control is FlashReal.ocx (the shim loads it). Nothing to set here.
#
# The game does not start the portal reader itself, so we run MegaByte.exe
# alongside it; MegaByte finds the game window, reads the hub over the bridge,
# and forwards figures via WM_COPYDATA. It is stopped when the game exits.
#
# Env knobs:
#   FUNKEY_HOME          override the "U.B. Funkeys" install dir
#   FUNKEY_BRIDGE_DEBUG=1  trace USB traffic
#   FUNKEY_SHIM_DEBUG=1    trace the Flash shim
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

# ---- locate the game install ("U.B. Funkeys" dir) ----------------------------
find_home() {
  [ -n "$FUNKEY_HOME" ] && { echo "$FUNKEY_HOME"; return; }
  local c
  for c in \
      "$(xdg-user-dir DOCUMENTS 2>/dev/null)/U.B. Funkeys" \
      "$HOME/Documents/U.B. Funkeys" \
      "$HOME/Dokumente/U.B. Funkeys"; do
    [ -d "$c/RadicaGame" ] && { echo "$c"; return; }
  done
}
FUNKEY_HOME="$(find_home)"
if [ -z "$FUNKEY_HOME" ] || [ ! -d "$FUNKEY_HOME/RadicaGame" ]; then
  echo "error: could not find the U.B. Funkeys install." >&2
  echo "       run setup.sh first, or set FUNKEY_HOME to the 'U.B. Funkeys' dir." >&2
  exit 1
fi
GAME_DIR="$FUNKEY_HOME/RadicaGame"
MB_DIR="$FUNKEY_HOME/MegaByte"

# ---- Wine environment --------------------------------------------------------
# Locate the USB bridge (the built libusb-1.0.dll.so): explicit override first,
# then beside this script, then the per-user build dir the .deb uses. Pick
# whichever actually contains the .so, so it works however we're launched.
BRIDGE_DIR="${FUNKEY_BRIDGE_DIR:-}"
if [ -z "$BRIDGE_DIR" ] || [ ! -f "$BRIDGE_DIR/libusb-1.0.dll.so" ]; then
  for cand in "$HERE/winebridge" "$HOME/.local/share/funkeyone/winebridge"; do
    [ -f "$cand/libusb-1.0.dll.so" ] && { BRIDGE_DIR="$cand"; break; }
  done
fi
BRIDGE_DIR="${BRIDGE_DIR:-$HERE/winebridge}"
export WINEDLLPATH="$BRIDGE_DIR${WINEDLLPATH:+:$WINEDLLPATH}"
export WINEDLLOVERRIDES="libusb-1.0=b;ninput=n,b${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"

# ---- portal reader alongside the game ---------------------------------------
if [ -x "$MB_DIR/MegaByte.exe" ] || [ -f "$MB_DIR/MegaByte.exe" ]; then
  ( cd "$MB_DIR" && exec wine MegaByte.exe -MBRun ) >/dev/null 2>&1 &
  MB_PID=$!
  trap 'kill "$MB_PID" 2>/dev/null; pkill -f "MegaByte.exe" 2>/dev/null' EXIT INT TERM
fi

cd "$GAME_DIR"
wine FunkeyOne.exe "$@"
