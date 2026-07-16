#!/usr/bin/env bash
# Build the Flash de-licensing shim as a real PE DLL (Wine's COM loader will
# not load a winelib ELF as an in-process server — it needs a PE image).
# Needs: mingw-w64-gcc  (sudo pacman -S mingw-w64-gcc)
set -e
cd "$(dirname "$0")"

CC=x86_64-w64-mingw32-gcc
command -v "$CC" >/dev/null || { echo "ERROR: $CC not found — sudo pacman -S mingw-w64-gcc"; exit 1; }

"$CC" -shared -O2 -Wall -o flashshim.dll \
    flashshim.c flashshim.def \
    -luuid -lole32 -Wl,--enable-stdcall-fixup -static-libgcc

echo "OK: $(pwd)/flashshim.dll"
file flashshim.dll
