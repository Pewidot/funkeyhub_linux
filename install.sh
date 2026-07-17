#!/usr/bin/env bash
# Friendly double-click installer for U.B. Funkeys (FunkeyOne) on Linux.
#
# - Double-clicked from a file manager (no terminal): it re-opens itself inside
#   a terminal window so you can see progress and type your sudo password.
# - Run from a terminal: it just runs.
# In both cases it hands off to setup.sh, which installs Wine + all deps
# (auto-detecting pacman/apt/dnf/zypper), sets up the prefix, and installs the
# game and portal support.
#
# NOTE: installing Wine and friends needs root, so you'll be asked for your
# password once. Nothing is installed silently.

HERE="$(cd "$(dirname "$0")" && pwd)"
SELF="$HERE/$(basename "$0")"

banner() {
  printf '\n\033[1;36m'
  echo "┌───────────────────────────────────────────────┐"
  echo "│   U.B. Funkeys (FunkeyOne) — Linux installer   │"
  echo "└───────────────────────────────────────────────┘"
  printf '\033[0m\n'
  echo "This installs Wine, .NET, the game and USB-portal support."
  echo "You'll be asked for your password to install system packages."
  echo
}

do_install() {
  banner
  "$HERE/setup.sh"
  local ec=$?
  echo
  if [ "$ec" -eq 0 ]; then
    printf '\033[1;32m✅ Done!\033[0m Launch "U.B. Funkeys" from your application menu.\n'
  else
    printf '\033[1;31m❌ Setup failed (exit %s).\033[0m Scroll up to see what went wrong.\n' "$ec"
  fi
  return "$ec"
}

# Mode used when we (or the .desktop) launch inside a terminal: run + pause so
# the window doesn't vanish before you can read it.
if [ "${1:-}" = "--run" ]; then
  do_install; ec=$?
  echo
  read -rp "Press Enter to close this window…" _ || true
  exit "$ec"
fi

# Already in a terminal? Just run.
if [ -t 1 ]; then
  do_install
  exit $?
fi

# Double-clicked without a terminal — try to open one and re-run in --run mode.
INNER="exec \"$SELF\" --run"
for t in x-terminal-emulator gnome-terminal konsole xfce4-terminal mate-terminal \
         tilix kitty alacritty foot xterm; do
  command -v "$t" >/dev/null 2>&1 || continue
  case "$t" in
    gnome-terminal|tilix) exec "$t" -- bash -lc "$INNER" ;;
    xfce4-terminal)       exec "$t" -x bash -lc "$INNER" ;;
    kitty|foot)           exec "$t" bash -lc "$INNER" ;;
    *)                    exec "$t" -e bash -lc "$INNER" ;;
  esac
done

# No terminal emulator found — tell the user how to run it.
msg="No terminal emulator found.\nOpen a terminal in this folder and run:\n\n    ./install.sh"
if command -v zenity  >/dev/null 2>&1; then zenity  --info --title="U.B. Funkeys installer" --text="$msg"
elif command -v kdialog >/dev/null 2>&1; then kdialog --msgbox "$msg"
else printf '%b\n' "$msg"; fi
exit 1
