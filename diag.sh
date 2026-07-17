#!/usr/bin/env bash
# Run INSIDE the VM to see why the "U.B. Funkeys" menu entry does nothing.
#   bash /mnt/funkeys/diag.sh     (adjust the path to wherever you mounted the share)
echo "===== funkeyone wrapper ====="
which funkeyone && cat "$(which funkeyone)"
echo
echo "===== first-run stamp ====="
ls -la "$HOME/.local/share/funkeyone/.setup-done" 2>&1
echo
echo "===== built bridge ====="
ls -la "$HOME/.local/share/funkeyone/winebridge/" 2>&1
echo
echo "===== where is the game installed? ====="
for d in "$(xdg-user-dir DOCUMENTS 2>/dev/null)/U.B. Funkeys" \
         "$HOME/Documents/U.B. Funkeys" "$HOME/Dokumente/U.B. Funkeys"; do
  printf '  %s : ' "$d"; [ -d "$d/RadicaGame" ] && echo "FOUND" || echo "no"
done
echo "  (search anywhere else:)"; find "$HOME" -maxdepth 4 -type d -name "RadicaGame" 2>/dev/null | head
echo
echo "===== any game/MegaByte already running? ====="
pgrep -af "FunkeyOne.exe|MegaByte.exe" || echo "  none"
echo
echo "===== LAUNCHING with debug — watch for [usb-bridge] lines and any error ====="
echo "      (close the game window to end this)"
FUNKEY_BRIDGE_DEBUG=1 FUNKEY_SHIM_DEBUG=1 funkeyone
echo
echo "===== funkeyone exited with code $? ====="
