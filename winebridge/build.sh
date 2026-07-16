#!/usr/bin/env bash
# Rebuild the Wine libusb bridge. Needs: wine (winegcc), gcc, libusb headers.
set -e
cd "$(dirname "$0")"
gcc -fPIC -O2 -Wall -c bridge_unix.c -I/usr/include/libusb-1.0
winegcc -shared bridge.c bridge_unix.o libusb-1.0.spec \
        -o libusb-1.0.dll.so -lusb-1.0 -Wall
gcc -O2 -Wall portalcheck.c -o portalcheck -I/usr/include/libusb-1.0 -lusb-1.0
echo "OK: libusb-1.0.dll.so + portalcheck rebuilt"
