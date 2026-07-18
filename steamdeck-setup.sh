#!/usr/bin/env bash
# U.B. Funkeys on a Steam Deck (SteamOS), the read-only-friendly way.
#
# SteamOS has an immutable root, so we don't install into the system (no pacman).
# Instead we run the Ruffle web player in a Chromium browser (WebUSB drives the
# portal), install the portal udev rule on the host, and add "U.B. Funkeys" to
# your Steam library.
#
# Run in Desktop Mode, from the cloned repo folder:  ./steamdeck-setup.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WEB_URL="${FUNKEY_WEB_URL:-https://www.funkeyone.com/play}"
APPS="$HOME/.local/share/applications"
BINDIR="$HOME/.local/bin"
ICONS="$HOME/.local/share/icons"

say(){ printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m!\033[0m %s\n' "$*"; }

command -v flatpak >/dev/null 2>&1 || { echo "flatpak not found — is this a Steam Deck / SteamOS?"; exit 1; }

# ---- 1. a WebUSB-capable browser (Flatpak) ----------------------------------
say "Making sure a Chromium-based browser is installed (for WebUSB)"
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
BROWSER=""
for id in com.google.Chrome org.chromium.Chromium com.microsoft.Edge com.brave.Browser; do
  if flatpak info "$id" >/dev/null 2>&1; then BROWSER="$id"; break; fi
done
if [ -z "$BROWSER" ]; then
  say "Installing Chromium"
  flatpak install -y --user flathub org.chromium.Chromium && BROWSER=org.chromium.Chromium
fi
[ -n "$BROWSER" ] || { echo "no browser available"; exit 1; }
echo "  browser: $BROWSER"
# let the sandboxed browser reach the USB portal
flatpak override --user --device=all "$BROWSER" 2>/dev/null || true

# ---- 2. portal udev rule (host; brief read-only unlock) ---------------------
say "Installing the portal udev rule (needs sudo)"
if [ -e /etc/udev/rules.d/70-funkeys-hub.rules ]; then
  echo "  already present"
elif [ ! -f "$HERE/70-funkeys-hub.rules" ]; then
  warn "70-funkeys-hub.rules not found next to this script; skipping (portal won't be readable)"
else
  command -v steamos-readonly >/dev/null 2>&1 && sudo steamos-readonly disable || true
  if sudo cp "$HERE/70-funkeys-hub.rules" /etc/udev/rules.d/70-funkeys-hub.rules; then
    sudo udevadm control --reload-rules
    sudo udevadm trigger --attr-match=idVendor=0e4c || true
    echo "  installed — unplug and replug the portal once"
    warn "after a big SteamOS update you may need to re-run this to restore the rule"
  else
    warn "couldn't write the rule — set a sudo password first with 'passwd', then re-run"
  fi
  command -v steamos-readonly >/dev/null 2>&1 && sudo steamos-readonly enable || true
fi

# ---- 3. launcher + icon -----------------------------------------------------
say "Creating the launcher and fetching the icon"
mkdir -p "$APPS" "$BINDIR" "$ICONS"
# real PNG logo (512x500); falls back to the favicon, then a stock icon
ICON_FILE="$ICONS/funkeyone.png"
if curl -fsSL -o "$ICON_FILE" "https://www.funkeyone.com/images/funkeyone.png" 2>/dev/null && [ -s "$ICON_FILE" ]; then
  :
elif curl -fsSL -o "$ICONS/funkeyone.ico" "https://www.funkeyone.com/favicon.ico" 2>/dev/null && [ -s "$ICONS/funkeyone.ico" ]; then
  ICON_FILE="$ICONS/funkeyone.ico"
else
  ICON_FILE="applications-games"
fi
echo "  icon: $ICON_FILE"
LAUNCHER="$BINDIR/funkeyone-web"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
exec flatpak run $BROWSER --kiosk --app="$WEB_URL"
EOF
chmod +x "$LAUNCHER"
DESKTOP="$APPS/funkeyone.desktop"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=U.B. Funkeys
Comment=Play U.B. Funkeys (web player)
Exec=$LAUNCHER
Icon=$ICON_FILE
Terminal=false
Categories=Game;
EOF
update-desktop-database "$APPS" 2>/dev/null || true

# ---- 4. add to Steam --------------------------------------------------------
say "Adding it to Steam"
if command -v steamos-add-to-steam >/dev/null 2>&1; then
  steamos-add-to-steam "$DESKTOP" 2>/dev/null && echo "  requested — confirm the Steam popup if it appears" \
    || warn "steamos-add-to-steam failed; add it manually (below)"
else
  warn "Add it manually: Steam (Desktop Mode) -> Add a Non-Steam Game -> Browse -> $LAUNCHER"
fi

say "Done."
echo "Find 'U.B. Funkeys' in your Steam library; in Game Mode it opens fullscreen."
echo "The list icon is the FunkeyOne logo. For the big library capsule you can"
echo "right-click the game in Steam -> Manage -> Set custom artwork (optional)."
echo "Put a Funkey on the hub and allow the WebUSB prompt the first time."
