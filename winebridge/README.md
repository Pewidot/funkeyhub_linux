# Wine USB bridge for the U.B. Funkeys portal

Makes the Funkeys USB portal (Radica "funkey reader", `0e4c:7288`) work in the
FunkeyOne/OpenFK Windows game running under Wine on Linux — **without any
kernel driver on either side**.

## Why the portal was "not detected"

The game's portal reader (`MegaByte/MegaByte.exe`) talks to the hub through
`libusb-1.0.dll`, which on real Windows is backed by the **libusbK kernel
driver** that `MegaByteHubInstaller.exe` installs. A Windows kernel driver
can't run under Wine, so the reader never saw the device — even though Linux
enumerated it fine all along (`lsusb` shows it as "Radica Games, Ltd funkey
reader").

## What the bridge does

`libusb-1.0.dll.so` is a winelib module that Wine loads *instead of* the
game's Windows `libusb-1.0.dll` (via `WINEDLLOVERRIDES=libusb-1.0=b` +
`WINEDLLPATH`, both set by `../funkeyone.sh`). Its exports forward the 11
libusb calls the game makes straight to the host's `/usr/lib/libusb-1.0.so`:

    MegaByte.exe (.NET, Wine)                      Linux
    P/Invoke libusb_* ──► bridge.c (ms_abi side)
                            └──► bridge_unix.c (sysv side)
                                   └──► host libusb ──► /dev/bus/usb/…

Two Wine-specific landmines the implementation works around — keep these if
you ever modify it:

1. **ABI split.** winegcc compiles with `-mabi=ms`, so a winegcc TU calling a
   host SysV library puts arguments in the wrong registers (this crashed as
   page faults at addresses like `0xE4C` — the VID ending up used as a
   pointer). Hence two objects: `bridge.c` (winegcc, exports only) calls into
   `bridge_unix.c` (plain gcc, all real work) through `sysv_abi`-attributed
   declarations.
2. **No libusb discovery inside Wine.** libusb's normal udev/netlink
   enumeration crashes in a Wine process. The context is created with
   `LIBUSB_OPTION_NO_DEVICE_DISCOVERY`; the device node is found by scanning
   `/sys/bus/usb/devices` and handed to libusb with `libusb_wrap_sys_device()`
   (the documented sandbox pattern). Verified natively: enumeration is fine
   outside Wine, so this is Wine-environment-specific.

## One-time setup (needs root): device permission

libusb needs read/write on the USB device node; by default only root has it.
Install the udev rule (from the folder above):

    sudo cp ../99-ubfunkeys.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules
    sudo udevadm trigger --attr-match=idVendor=0e4c

then **unplug and replug the portal**.

## Run

    ./portalcheck 1        # native sanity check: should print "claim -> 0"
                           # and read the endpoint (mode 1 = the bridge's path)
    ../funkeyone.sh        # launch the game with the bridge active
    FUNKEY_BRIDGE_DEBUG=1 ../funkeyone.sh   # with USB traces on stderr

## Files

    bridge.c          winegcc half — DLL exports (ms_abi), no host calls
    bridge_unix.c     gcc half — all libusb/sysfs work (SysV)
    libusb-1.0.spec   export table (the 11 functions MegaByte imports)
    libusb-1.0.dll.so the built bridge module
    build.sh          rebuild everything
    portalcheck.c     native test tool (mode 0: enumeration, mode 1: wrap fd)
    decoy.c           test helper: fake "FunkeyOne" window so MegaByte.exe
                      can be exercised without the full game
