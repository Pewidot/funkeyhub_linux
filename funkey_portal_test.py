#!/usr/bin/env python3
"""
Native Linux reader / test for the U.B. Funkeys portal (Radica 0e4c:7288).

Proves the portal works on Linux with NO custom kernel driver — just libusb via
pyusb, the same way the web player uses WebUSB. Place a Funkey figure on the hub
and its 8-hex figure id prints; lift it and you get "Funkey lifted".

Decoding is a direct port of decodeFunkeyCode() in play/usbhub.js.

Setup (no root needed for Python; the udev rule handles device permission):
    python3 -m venv .venv && . .venv/bin/activate && pip install pyusb
    # or, system-wide:  sudo pacman -S python-pyusb libusb
Run:
    python3 funkey_portal_test.py
Requires the udev rule (99-ubfunkeys.rules) installed + a replug first, so your
user can open the device read/write.
"""
import sys

try:
    import usb.core
    import usb.util
except ModuleNotFoundError:
    sys.exit("pyusb not installed. Run:  pip install pyusb   (or: sudo pacman -S python-pyusb libusb)")

VID, PID = 0x0E4C, 0x7288
EP_IN = 0x81            # interrupt IN, endpoint 1 (from the device descriptor)
REPORT_LEN = 7
READ_LEN = 8           # endpoint sends 8-byte packets; read the full packet
PORTAL_MCODE = "FFFFFFF0"
NO_FIGURE = PORTAL_MCODE + "00000000"

# resistor -> figure-digit ranges, straight from usbhub.js
RANGES = [
    (7820, 19180), (23460, 37540), (42780, 60220), (69460, 91540),
    (108100, 136900), (154100, 190900), (227700, 277300),
    (338100, 406900), (522100, 642900), (844100, 1035900),
]


def decode_funkey_code(buf):
    """Port of decodeFunkeyCode(). Returns 8-hex id, '00000000' (empty), or None (invalid)."""
    if buf is None or len(buf) < REPORT_LEN:
        return "00000000"
    raw = [(((buf[4] >> (i * 2)) & 3) << 8) | buf[i] for i in range(4)]
    offset = (buf[6] << 8) | buf[5]
    if offset < 10:
        return "00000000"
    ohms = [0 if raw[i] == 0x3FF else int((raw[i] - offset) * 100000 / (0x3FF - raw[i]))
            for i in range(4)]
    types = []
    for i in range(4):
        found = -1
        for t in range(10):
            if RANGES[t][0] <= ohms[i] <= RANGES[t][1]:
                found = t
                break
        if found < 0:
            return None
        types.append(found)
    if (types[0] + types[1] + types[2]) % 10 != types[3]:
        return None
    dec_id = types[2] * 100 + types[1] * 10 + types[0]
    return format(dec_id & 0xFFFFFFFF, "08X")


def main():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        sys.exit("Portal not found (0e4c:7288). Is it plugged in? Check `lsusb`.")

    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except (usb.core.USBError, NotImplementedError):
        pass

    try:
        dev.set_configuration()
        usb.util.claim_interface(dev, 0)
    except usb.core.USBError as e:
        sys.exit(f"Could not open the device: {e}\n"
                 "Almost certainly a permission problem — install 99-ubfunkeys.rules,\n"
                 "reload udev, and replug the portal (see the file's header).")

    # best-effort init handshake, mirrors the class control transfer in usbhub.js
    try:
        dev.ctrl_transfer(0xA0, 0x00, 0, 0, 4)
    except usb.core.USBError:
        pass

    print("Portal ONLINE — place a Funkey on the hub. Ctrl-C to quit.\n")
    last = None
    while True:
        try:
            data = dev.read(EP_IN, READ_LEN, timeout=2000)
        except usb.core.USBError as e:
            if e.errno == 110:        # timed out, no report — keep polling
                continue
            try:
                dev.clear_halt(EP_IN)  # recover from a stall
            except usb.core.USBError:
                pass
            continue

        code = decode_funkey_code(bytes(data))
        if code is None:              # failed checksum -> ignore
            continue
        full = PORTAL_MCODE + code
        if full == last:
            continue
        last = full
        if full == NO_FIGURE:
            print("— Funkey lifted")
        else:
            print(f"+ Funkey  id #{code}   (raw {bytes(data).hex()})")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nbye")
