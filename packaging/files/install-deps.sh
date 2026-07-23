#!/bin/sh
# Run as ROOT (via pkexec or sudo): enable the repos Wine needs, add i386, and
# install Wine + the build/runtime dependencies. One privileged step.
#
# The USB bridge is now a native daemon (plain gcc + libusb) talking to a PE
# proxy over a socket — so NO winegcc / wine dev-tools are required anymore.
set -e
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
  sed -i 's/^Components:.*/Components: main restricted universe multiverse/' \
      /etc/apt/sources.list.d/ubuntu.sources || true
elif [ -f /etc/apt/sources.list ]; then
  sed -i 's/\(deb [^#].*main\)$/\1 universe multiverse/' /etc/apt/sources.list || true
fi
dpkg --add-architecture i386 || true
apt-get update -y || true
# gcc + libusb-1.0-0-dev build the daemon; python3 + unzip extract the client.
DEPS="winetricks gcc libusb-1.0-0-dev python3 unzip wget curl zenity xdg-user-dirs ca-certificates"
apt-get install -y wine $DEPS || apt-get install -y wine64 $DEPS
