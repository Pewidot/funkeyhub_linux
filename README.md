# U.B. Funkeys (FunkeyOne) on Linux — Wine support kit

Run the **FunkeyOne** U.B. Funkeys revival, *with a real physical USB portal*,
on Arch Linux under Wine. This repo is the glue that makes the Windows game and
its hub work on Linux — it does **not** contain the game itself.

The game embeds Adobe Flash via .NET WinForms and talks to the Radica USB
portal through a Windows kernel driver. None of that works out-of-the-box under
Wine. This kit provides three small shims plus a launcher that fix it:

| Piece | Problem it solves |
|-------|-------------------|
| **winebridge/** — `libusb-1.0.dll` bridge | The portal reader needs the Windows **libusbK kernel driver**, which can't run under Wine. This forwards its libusb calls to Linux's own libusb, so the hub works with no kernel driver. |
| **wineflash/** — Flash de-licensing shim | .NET's `AxHost` creates the Flash control through a **licensed** COM path that corrupts memory under Wine and crashes the game on startup. The shim hides the licensing interface so the working path is used instead. |
| **wineninput/** — `ninput.dll` no-op stub | Wine's builtin `ninput` has a stub (`StopInteractionContext`) that **aborts the process**. Flash 34 calls it right after init. This replaces those with harmless no-ops. |
| **funkeyone.sh** — launcher | Wires the above in and runs the portal reader (`MegaByte.exe`) alongside the game — the game doesn't start it itself. |

> ⚠️ **You must supply the game.** For copyright reasons this repo ships only
> our own code. Get the installer (`UBFunkeys-Setup-x64.exe`) from the FunkeyOne
> project itself (<https://www.funkeyone.com>) and place it next to `setup.sh`,
> or install the game first, before running setup.

---

## Requirements

- **Arch Linux** (or derivative) with the **multilib** repo enabled
- A Radica **U.B. Funkeys USB portal** (`0e4c:7288`) for hub features (the game
  runs fine without one — you just can't scan physical Funkeys)
- System packages:

  ```bash
  sudo pacman -S --needed wine winetricks libusb gcc mingw-w64-gcc
  ```

  - `wine` + `winetricks` — run the game and install .NET
  - `libusb` — the USB bridge forwards to it at runtime
  - `gcc` + `mingw-w64-gcc` — build the shims (compiled locally; no binaries are
    shipped)

## Install

```bash
git clone <this-repo> funkeyone-linux
cd funkeyone-linux
# put UBFunkeys-Setup-x64.exe here if the game isn't installed yet
./setup.sh
```

`setup.sh` is idempotent and does the whole thing:

1. checks the system packages above
2. installs **real .NET 4.8** into the Wine prefix (`winetricks dotnet48`) — the
   game needs Microsoft .NET, not wine-mono; this step is slow the first time
3. installs the game if it isn't already (runs the Windows installer)
4. builds the three shims from source
5. swaps the Flash shim into the game (`Flash.ocx` → shim, real control kept as
   `FlashReal.ocx`)
6. drops `ninput.dll` into the game directory
7. installs the udev rule so your user can open the portal (needs `sudo`)
8. adds a **"U.B. Funkeys" entry to your application menu** (icon taken from the
   game). Run `./install-menu.sh` on its own to (re)create it, or
   `./install-menu.sh --remove` to remove it.

After it finishes, **unplug and replug the portal once**, then launch
**U.B. Funkeys** from your application menu, or run:

```bash
./funkeyone.sh
```

Place a Funkey on the hub — it should appear in the game.

## Troubleshooting

- **Hub not detected** — make sure you launch via `./funkeyone.sh` (not the game
  `.exe` directly). It starts the portal reader with the bridge; running the exe
  alone leaves the hub unread. Debug the USB path with:
  ```bash
  FUNKEY_BRIDGE_DEBUG=1 ./funkeyone.sh
  ```
  and check `~/…/U.B. Funkeys/MegaByte/MegaByte_log.txt` — `MegaByte portal
  attached` means it's working. `Device not found … libusbK/WinUSB` means the
  bridge override didn't apply (you launched the exe directly), and a permission
  error means the udev rule isn't active yet (replug the portal).
- **Portal permission denied** — the udev rule file must sort *before*
  `73-seat-late.rules`; it's named `70-…` for that reason. Re-run:
  ```bash
  sudo udevadm control --reload-rules && sudo udevadm trigger --attr-match=idVendor=0e4c
  ```
  then replug. Remove any stale `/etc/udev/rules.d/99-ubfunkeys.rules`.
- **Game crashes on startup with `AxHost.CreateWithLicense`** — the Flash shim
  swap didn't take. Confirm the game dir's `Flash.ocx` is ~180 KB (the shim),
  not ~14 MB (the real control, which should be `FlashReal.ocx`).
- **Aborts with `ninput.dll.StopInteractionContext`** — `ninput.dll` isn't in
  the game dir, or the override isn't set. Re-run `setup.sh`.
- **Different install path** — if the game lives somewhere unusual, point the
  launcher at it: `FUNKEY_HOME="/path/to/U.B. Funkeys" ./funkeyone.sh`.
- **Crashes right after an in-game update finishes downloading** — the updater
  wrongly thinks the hub component (MegaByte) is out of date and, on "apply",
  runs the Windows **libusbK driver installer**, which can't run under Wine.
  You don't need that driver (the bridge replaces it). `setup.sh` prevents this
  by marking MegaByte up to date; to fix an existing install manually:
  ```bash
  wine reg add 'HKCU\Software\OpenFK\FunkeyOne' /v MegaByteVersion /t REG_SZ /d 1.0.1.0 /f
  ```
  (use the version of your `MegaByte/MegaByte.exe`). This makes the update stop
  re-triggering; it does not skip any real game/content updates.

## How it works / hacking

Each component is small, commented C with its own `build.sh`:

- [`winebridge/`](winebridge/) — split-ABI winelib bridge (see its
  [README](winebridge/README.md) for the two Wine gotchas: the ms/SysV ABI split
  and libusb device-discovery crashing inside Wine). `winebridge/portalcheck`
  is a native tool to test the portal directly.
- [`wineflash/flashshim.c`](wineflash/flashshim.c) — a COM class-factory that
  answers `E_NOINTERFACE` for `IClassFactory2`, so `AxHost` skips licensing, and
  forwards real object creation to `FlashReal.ocx`. Installed via a reg-free-COM
  file swap (the game's manifest loads `Flash.ocx` by name).
- [`wineninput/ninputstub.c`](wineninput/ninputstub.c) — every InteractionContext
  entry point as a no-op returning `S_OK`.

Rebuild any one with its `./build.sh`. The prebuilt binaries are intentionally
**not** committed — they're compiled locally so they match your Wine/libusb.

## Legal

This repository contains only original support code (the shims, launcher, udev
rule) under no particular game license. It includes **no** Adobe Flash, no
Radica/U.B. Funkeys assets, and no FunkeyOne binaries — you provide those
yourself from sources you're entitled to use. U.B. Funkeys is a trademark of its
respective owners; this project is an unaffiliated compatibility layer.
