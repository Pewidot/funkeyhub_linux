#!/usr/bin/env bash
# Build the ninput.dll no-op stub as a real PE DLL.
# Needs: mingw-w64-gcc  (sudo pacman -S mingw-w64-gcc)
set -e
cd "$(dirname "$0")"
CC=x86_64-w64-mingw32-gcc
command -v "$CC" >/dev/null || { echo "ERROR: $CC not found — sudo pacman -S mingw-w64-gcc"; exit 1; }
"$CC" -shared -O2 -Wall -o ninput.dll ninputstub.c ninput.def -static-libgcc
echo "OK: $(pwd)/ninput.dll"
file ninput.dll
