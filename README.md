# U.B. Funkeys (FunkeyOne) on Linux

This is the Linux-side plumbing I use to run the FunkeyOne U.B. Funkeys revival
under Wine, including the physical USB portal. The game itself isn't in here;
you install that separately (it comes from funkeyone.com).

A few things about the game don't survive Wine on their own. It's a .NET
WinForms app that embeds Adobe Flash, and the portal reader talks to the hub
through a Windows kernel driver. Out of that you get: the Flash control crashing
on startup, the portal driver failing to load, and one of Wine's input stubs
killing the process. So there are three small shims and a launcher that deal
with each of those.

* `winebridge/` is a stand-in `libusb-1.0.dll` that forwards to the host's
  libusb. That way the portal reader works without the Windows libusbK driver.
* `wineflash/` is a shim that sits in front of the real `Flash.ocx` and stops
  .NET's `AxHost` from taking the licensed COM path, which is what corrupts
  memory and crashes the game under Wine.
* `wineninput/` is a replacement `ninput.dll`. Wine's own one has an entry point
  (`StopInteractionContext`) that aborts the process when Flash calls it; ours
  just returns and does nothing.
* `funkeyone.sh` is the launcher. It starts the portal reader (`MegaByte.exe`)
  next to the game, because the game doesn't start it by itself.

You bring the game. Nothing in here contains the installer, the SWFs, Flash, or
any Funkeys assets. The setup downloads `UBFunkeys-Setup-x64.exe` from
funkeyone.com for you (with a confirmation first).

## Getting it running

### Ubuntu / Debian

Grab the `.deb` from the [Releases page](../../releases), or build it yourself
with `./packaging/build-deb.sh`, and install it:

```bash
sudo apt install ./funkeyone-wine_1.0.0_amd64.deb
```

Double-clicking a `.deb` on recent Ubuntu just opens Archive Manager, so use the
terminal (or install `gdebi`).

The package is tiny and barely depends on anything, so the install itself always
goes through. The real work happens the first time you open "U.B. Funkeys" from
the menu. A progress window walks through installing Wine, setting up the prefix
with .NET, downloading the game, and applying the fixes. You'll get one password
prompt for the Wine install, and the app icon is pulled from the site's favicon.

Partway through, the game's own installer opens. When it does:

* untick the Start Menu and Desktop shortcut options,
* don't install the hub/portal driver,
* click "No" if it offers to download .NET or Visual C++,
* and don't tick "Launch FunkeyOne" at the end. Just close the window.

There's a dialog that reminds you of all this right before the installer shows
up.

It's two steps (install the package, then launch once) because a `.deb` install
runs as root with no desktop session, so it can't build your Wine prefix or run
the game's installer. That part has to run as you, on first launch. After that
the menu entry just starts the game.

### Other distros

```bash
git clone https://github.com/Pewidot/funkeyhub_linux_mac funkeyone-linux
cd funkeyone-linux
./setup.sh
```

`setup.sh` figures out your package manager (pacman, apt, dnf or zypper),
installs what's missing, puts .NET 4.8 in the Wine prefix, installs the game,
builds the three shims, swaps in the Flash shim, adds the udev rule, and creates
a menu entry. It's safe to re-run.

When it finishes, unplug and replug the portal once, then start the game from
the menu or with `./funkeyone.sh`. Put a Funkey on the hub and it should show up
in the game.

One thing to watch: you need a reasonably recent Wine (11.x, WoW64) for .NET 4.8
and Flash. Arch, Fedora and openSUSE Tumbleweed are fine as they are.
Debian/Ubuntu stable ship an older Wine, so install it from the
[WineHQ repo](https://wiki.winehq.org/Download) there.

The packages you need per distro:

| Distro | Packages |
|--------|----------|
| Arch | `wine winetricks libusb gcc mingw-w64-gcc` |
| Debian/Ubuntu | `wine wine64-tools winetricks libusb-1.0-0-dev gcc gcc-mingw-w64-x86-64` |
| Fedora | `wine wine-devel winetricks libusb1-devel gcc mingw64-gcc` |
| openSUSE | `wine wine-devel winetricks libusb-1_0-devel gcc cross-x86_64-w64-mingw32-gcc` |

`winegcc` builds the USB bridge (it's in `wine64-tools` on Ubuntu, in `wine`
elsewhere). mingw builds the two PE shims. Nothing is shipped as a binary; it's
all compiled on your machine so it matches your Wine and libusb.

## If the hub isn't detected

Launch through `./funkeyone.sh` (or the menu entry), not the game `.exe`
directly. Only the launcher starts the portal reader with the bridge active;
run the exe on its own and nothing reads the hub. To see what the bridge is
doing:

```bash
FUNKEY_BRIDGE_DEBUG=1 ./funkeyone.sh
```

Then check `~/…/U.B. Funkeys/MegaByte/MegaByte_log.txt`. "MegaByte portal
attached" means it's working. "Device not found … libusbK/WinUSB" usually means
the bridge override didn't apply (you started the exe directly). A permission
error means the udev rule isn't active yet, so replug the portal.

If you get a permission error on the device, the udev rule has to sort before
`73-seat-late.rules`, which is why it's named `70-…`. Reload and retrigger it:

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger --attr-match=idVendor=0e4c
```

then replug. Delete any old `/etc/udev/rules.d/99-ubfunkeys.rules` if it's still
around.

A couple of other failure modes:

* Crash on startup at `AxHost.CreateWithLicense` means the Flash shim swap
  didn't take. The game dir's `Flash.ocx` should be the ~180 KB shim, with the
  real ~14 MB control renamed to `FlashReal.ocx`.
* An abort mentioning `ninput.dll.StopInteractionContext` means `ninput.dll`
  isn't in the game dir or the override isn't set. Re-run `setup.sh`.
* If the game is installed somewhere unusual, point the launcher at it with
  `FUNKEY_HOME="/path/to/U.B. Funkeys" ./funkeyone.sh`.
* If the game crashes right after an in-game update finishes downloading, the
  updater thinks MegaByte is out of date and tries to run the Windows libusbK
  driver installer, which can't work under Wine. You don't need that driver.
  The setup already writes a version key to stop this; to fix it by hand:
  ```bash
  wine reg add 'HKCU\Software\OpenFK\FunkeyOne' /v MegaByteVersion /t REG_SZ /d 1.0.1.0 /f
  ```
  (use the version of your `MegaByte/MegaByte.exe`). It only silences that one
  bogus update, not real content updates.

## How it works

Each shim is a small, commented C file with its own `build.sh`:

* [`winebridge/`](winebridge/) is a winelib module, split across two objects
  because of an ABI issue (its [README](winebridge/README.md) has the details:
  the ms/SysV split, and libusb's normal device discovery crashing inside Wine,
  which is why it opens the device by scanning sysfs instead).
  `winebridge/portalcheck` is a small native tool to poke the portal directly.
* [`wineflash/flashshim.c`](wineflash/flashshim.c) is a COM class factory that
  returns `E_NOINTERFACE` for `IClassFactory2`, so `AxHost` skips the licensed
  path, then hands real object creation off to `FlashReal.ocx`. It's installed
  by a plain file swap because the game loads Flash through a reg-free-COM
  manifest that names `Flash.ocx` directly.
* [`wineninput/ninputstub.c`](wineninput/ninputstub.c) is every
  InteractionContext function as a no-op returning `S_OK`.

Rebuild any of them with its `./build.sh`.

## What's in here (and what isn't)

Only original support code: the shims, the launcher, the udev rule, the
packaging and setup scripts. No Adobe Flash, no Radica or U.B. Funkeys assets,
no FunkeyOne binaries. You supply the game from wherever you're entitled to get
it. U.B. Funkeys is a trademark of its owners; this is an unaffiliated
compatibility layer.
