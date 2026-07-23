#!/usr/bin/env python3
# Pull the FunkeyOne revival client out of the game's own Windows installer,
# on Linux, without running it (no Wine, no clicking, no driver install).
#
# UBFunkeys-Setup-x64.exe is a .NET assembly that carries two embedded
# manifest resources:
#     Payload.ClientPayload.zip   -> FunkeyOne.exe + Flash.ocx + the two
#                                    ShockwaveFlash interop DLLs
#     Payload.MegaByte.exe        -> the modern MegaByte portal reader
# Both are stored raw, each prefixed by a 4-byte little-endian length (the
# standard .NET embedded-resource framing). We carve them straight out of the
# file, so nothing copyrighted ever ships in this package -- the user supplies
# the installer, and we only unpack what's already inside it.
#
# Usage: extract-payload.py <installer.exe> <RadicaGame dir> <MegaByte dir>
import sys, struct, zipfile, io, os

def carve(data, sig):
    """Yield (offset, length, bytes) for every 4-byte-length-prefixed blob
    starting with sig."""
    i = 0
    while True:
        j = data.find(sig, i)
        if j < 0:
            break
        if j >= 4:
            (length,) = struct.unpack('<I', data[j - 4:j])
            if 0 < length <= len(data) - j:
                yield j, length, data[j:j + length]
        i = j + 1

def find_client_zip(data):
    """The embedded ClientPayload.zip: a length-prefixed, valid zip that
    contains FunkeyOne.exe."""
    for _off, _len, blob in carve(data, b'PK\x03\x04'):
        try:
            z = zipfile.ZipFile(io.BytesIO(blob))
            if any(n.endswith('FunkeyOne.exe') for n in z.namelist()):
                return z
        except Exception:
            continue
    return None

def find_megabyte(data):
    """Payload.MegaByte.exe: a small .NET PE that mentions MegaByte and is not
    the (much larger) hub-driver installer."""
    best = None
    for _off, length, blob in carve(data, b'MZ'):
        if not (10_000 < length < 2_000_000):
            continue
        if b'PE\x00\x00' not in blob[:2048]:
            continue
        if b'BSJB' not in blob:            # .NET metadata signature
            continue
        if b'MegaByte' not in blob:
            continue
        if b'HubInstaller' in blob:        # that's MegaByteHubInstaller.exe
            continue
        if best is None or length < best[0]:
            best = (length, blob)
    return best[1] if best else None

def main():
    if len(sys.argv) != 4:
        print("usage: extract-payload.py <installer.exe> <RadicaGame dir> <MegaByte dir>",
              file=sys.stderr)
        return 2
    installer, radica, megadir = sys.argv[1], sys.argv[2], sys.argv[3]
    data = open(installer, 'rb').read()

    z = find_client_zip(data)
    if z is None:
        print("error: ClientPayload.zip not found in installer", file=sys.stderr)
        return 1
    os.makedirs(radica, exist_ok=True)
    for name in z.namelist():
        if name.endswith('/'):
            continue
        dest = os.path.join(radica, os.path.basename(name))
        with open(dest, 'wb') as f:
            f.write(z.read(name))
        print(f"  client: {os.path.basename(name)}")

    mb = find_megabyte(data)
    if mb is None:
        print("error: MegaByte.exe not found in installer", file=sys.stderr)
        return 1
    os.makedirs(megadir, exist_ok=True)
    with open(os.path.join(megadir, 'MegaByte.exe'), 'wb') as f:
        f.write(mb)
    print(f"  megabyte: MegaByte.exe ({len(mb)} bytes)")
    return 0

if __name__ == '__main__':
    sys.exit(main())
