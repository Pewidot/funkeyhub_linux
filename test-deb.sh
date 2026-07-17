#!/usr/bin/env bash
# Run INSIDE the Ubuntu VM to test the .deb. Enables the repos wine needs,
# then installs the package so apt pulls in Wine + all dependencies.
# Usage (in the guest, after mounting the share):  sudo bash test-deb.sh
set -e
DEB="$(dirname "$0")/funkeyone-wine_1.0.0_amd64.deb"
echo "==> Enabling universe/multiverse (wine lives there)"
add-apt-repository -y universe multiverse >/dev/null 2>&1 || true
echo "==> apt update"
apt-get update -qq
echo "==> Installing $DEB"
apt-get install -y "$DEB"
echo
echo "======================================================"
echo " Installed. Check it landed correctly:"
echo "   which funkeyone funkeyone-setup"
echo "   ls /usr/lib/funkeyone /lib/udev/rules.d/70-funkeys-hub.rules"
echo " Then run the per-user setup:  funkeyone-setup"
echo "======================================================"
