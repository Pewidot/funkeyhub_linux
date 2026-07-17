#!/usr/bin/env bash
# Reset a Debian/Ubuntu system to a clean state so you can re-test installing
# the .deb from scratch. Run it INSIDE the test VM.
#
#   bash clean-system.sh              # full clean (default): app + game + Wine
#                                     #   prefix + Wine packages + shortcuts
#   bash clean-system.sh --keep-deps    keep wine/winetricks/... (faster retest)
#   bash clean-system.sh --keep-prefix  keep ~/.wine  (skip the slow .NET reinstall)
#   bash clean-system.sh --keep-installer   keep the downloaded game installer
#   bash clean-system.sh -y             don't ask for confirmation
set -u

KEEP_DEPS=0; KEEP_PREFIX=0; KEEP_INSTALLER=0; YES=0
for a in "$@"; do case "$a" in
  --keep-deps) KEEP_DEPS=1 ;;
  --keep-prefix) KEEP_PREFIX=1 ;;
  --keep-installer) KEEP_INSTALLER=1 ;;
  -y|--yes) YES=1 ;;
  -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
  *) echo "unknown option: $a" >&2; exit 1 ;;
esac; done

PREFIX="${WINEPREFIX:-$HOME/.wine}"

# never rm these
safe_rm() {
  for p in "$@"; do
    [ -z "$p" ] && continue
    case "$p" in /|"$HOME"|"$HOME"/) echo "refusing to remove '$p'"; continue ;; esac
    rm -rf "$p"
  done
}

# collect installed game dirs
GAME_DIRS=()
for d in "$(xdg-user-dir DOCUMENTS 2>/dev/null)/U.B. Funkeys" \
         "$HOME/Documents/U.B. Funkeys" "$HOME/Dokumente/U.B. Funkeys"; do
  [ -e "$d" ] && GAME_DIRS+=("$d")
done

echo "This will remove:"
echo "  • package  funkeyone-wine (+ udev rule, menu entries, icon)"
echo "  • per-user ~/.local/share/funkeyone"
for d in "${GAME_DIRS[@]}"; do echo "  • game     $d"; done
[ $KEEP_PREFIX = 0 ]    && echo "  • Wine prefix  $PREFIX  (removes .NET, game registry, etc.)"
[ $KEEP_INSTALLER = 0 ] && echo "  • installer    ~/Downloads/UBFunkeys-Setup-x64.exe"
[ $KEEP_DEPS = 0 ]      && echo "  • packages     wine, wine64-tools, winetricks, libusb-1.0-0-dev …"
echo "  • Wine-generated FunkeyOne menu/desktop shortcuts"
echo
if [ $YES = 0 ]; then
  read -rp "Proceed? [y/N] " a; [[ "${a:-n}" == [yY] ]] || { echo "aborted."; exit 1; }
fi

echo "==> stopping any running game/Wine"
pkill -f 'FunkeyOne.exe' 2>/dev/null || true
pkill -f 'MegaByte.exe' 2>/dev/null || true
command -v wineserver >/dev/null 2>&1 && WINEPREFIX="$PREFIX" wineserver -k 2>/dev/null || true
sleep 1

echo "==> removing the package"
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get remove --purge -y funkeyone-wine 2>/dev/null || true
fi
sudo dpkg -r funkeyone-wine 2>/dev/null || true
# belt-and-suspenders: clear any package-owned paths left behind
sudo rm -rf /usr/lib/funkeyone /usr/bin/funkeyone /usr/bin/funkeyone-setup \
  /usr/share/applications/funkeyone*.desktop /usr/share/pixmaps/funkeyone.png \
  /usr/share/icons/hicolor/*/apps/funkeyone.png \
  /lib/udev/rules.d/70-funkeys-hub.rules /etc/udev/rules.d/70-funkeys-hub.rules 2>/dev/null || true
command -v udevadm >/dev/null 2>&1 && sudo udevadm control --reload-rules 2>/dev/null || true

echo "==> removing per-user data + game"
safe_rm "$HOME/.local/share/funkeyone"
for d in "${GAME_DIRS[@]}"; do safe_rm "$d"; done

if [ $KEEP_PREFIX = 0 ]; then echo "==> removing Wine prefix"; safe_rm "$PREFIX"; fi
if [ $KEEP_INSTALLER = 0 ]; then
  echo "==> removing downloaded installer"
  safe_rm "$HOME/Downloads/UBFunkeys-Setup-x64.exe" "$HOME/UBFunkeys-Setup-x64.exe"
fi

echo "==> removing Wine-generated shortcuts"
find "$HOME/.local/share/applications" -iname '*funkey*' -delete 2>/dev/null || true
find "$HOME/.config/menus" -iname '*funkey*' -delete 2>/dev/null || true
for dd in "$HOME/Desktop" "$HOME/Schreibtisch" "$(xdg-user-dir DESKTOP 2>/dev/null)"; do
  [ -d "$dd" ] && find "$dd" -maxdepth 1 -iname '*funkey*' -delete 2>/dev/null || true
done

if [ $KEEP_DEPS = 0 ] && command -v apt-get >/dev/null 2>&1; then
  echo "==> removing Wine + dependencies (this frees a lot, takes a moment)"
  sudo apt-get remove --purge -y wine wine64 wine32 wine64-tools winetricks \
    libusb-1.0-0-dev 2>/dev/null || true
  sudo apt-get autoremove --purge -y 2>/dev/null || true
fi

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
command -v gtk-update-icon-cache  >/dev/null 2>&1 && gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || true

echo
echo "✅ Clean. Now re-test a fresh install:"
echo "   sudo apt install /mnt/f/funkeyone-wine_1.0.0_amd64.deb"
echo "   then click \"U.B. Funkeys\" in the menu."
