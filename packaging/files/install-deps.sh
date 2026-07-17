#!/bin/sh
# Run as ROOT (via pkexec or sudo): enable the repos Wine needs, add the i386
# architecture, and install Wine + the build dependencies. One privileged step.
set -e
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
  sed -i 's/^Components:.*/Components: main restricted universe multiverse/' \
      /etc/apt/sources.list.d/ubuntu.sources || true
elif [ -f /etc/apt/sources.list ]; then
  sed -i 's/\(deb [^#].*main\)$/\1 universe multiverse/' /etc/apt/sources.list || true
fi
dpkg --add-architecture i386 || true
apt-get update -y || true
# wine64-tools provides winegcc on Ubuntu (the wine package omits the dev tools)
DEPS="wine64-tools winetricks libusb-1.0-0-dev gcc xdg-user-dirs wget zenity ca-certificates"
apt-get install -y wine $DEPS || apt-get install -y wine64 $DEPS
