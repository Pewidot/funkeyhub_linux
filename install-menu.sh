#!/usr/bin/env bash
# Add (or remove) a "U.B. Funkeys" entry to the Linux application menu.
#   ./install-menu.sh            install
#   ./install-menu.sh --remove   remove
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons"
DESKTOP="$APPS/funkeyone.desktop"

if [[ "${1:-}" == "--remove" ]]; then
  rm -f "$DESKTOP" "$ICONS/funkeyone.png"
  update-desktop-database "$APPS" 2>/dev/null || true
  echo "removed."
  exit 0
fi

mkdir -p "$APPS" "$ICONS"

# locate the game install (same logic as funkeyone.sh) to grab its icon
find_home() {
  local c
  for c in "$(xdg-user-dir DOCUMENTS 2>/dev/null)/U.B. Funkeys" \
           "$HOME/Documents/U.B. Funkeys" "$HOME/Dokumente/U.B. Funkeys"; do
    [ -e "$c/funkeyone.ico" ] && { echo "$c"; return; }
  done
}
HOME_DIR="$(find_home || true)"

ICON_LINE="Icon=applications-games"   # sensible fallback
if [ -n "${HOME_DIR:-}" ] && command -v magick >/dev/null; then
  # extract the largest frame from the .ico into a PNG
  tmp="$(mktemp -d)"
  magick "$HOME_DIR/funkeyone.ico" "$tmp/f-%d.png" 2>/dev/null || true
  big="$(for f in "$tmp"/f-*.png; do printf '%s %s\n' "$(magick identify -format '%w' "$f" 2>/dev/null || echo 0)" "$f"; done | sort -rn | head -1 | cut -d' ' -f2-)"
  [ -n "$big" ] && cp "$big" "$ICONS/funkeyone.png" && ICON_LINE="Icon=$ICONS/funkeyone.png"
  rm -rf "$tmp"
elif [ -n "${HOME_DIR:-}" ]; then
  ICON_LINE="Icon=$HOME_DIR/funkeyone.ico"   # many menus accept .ico directly
fi

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=U.B. Funkeys
GenericName=Funkeys Game
Comment=Play U.B. Funkeys (FunkeyOne) with the USB portal, via Wine
Exec=$HERE/funkeyone.sh
$ICON_LINE
Terminal=false
Categories=Game;
Keywords=funkeys;ubfunkeys;funkeyone;wine;
StartupNotify=false
EOF

desktop-file-validate "$DESKTOP" 2>/dev/null || true
update-desktop-database "$APPS" 2>/dev/null || true
echo "installed: $DESKTOP"
echo "Look for \"U.B. Funkeys\" in your application menu (may need a re-login)."
