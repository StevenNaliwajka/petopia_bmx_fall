#!/usr/bin/env python3
"""Fail (exit 1) unless a BSP carries baked light: its LDR lighting lump (8)
and HDR lighting lump (53) must both hold samples, and the samples must not
all be black. tools/build-map.sh runs it on what vrad wrote, so a lighting
step that fails, or that wine lets "succeed" without lighting anything, can
never ship an unlit map.

    python3 tools/check-bsp-lit.py maps/petopia_bmx_fall.bsp
"""
import struct
import sys


def lump(data, i):
    off, length, _, _ = struct.unpack_from("<iiii", data, 8 + i * 16)
    return off, length


def check(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"VBSP":
        return "not a BSP"
    for i, name in ((8, "LDR lighting"), (53, "HDR lighting")):
        off, length = lump(data, i)
        if length < 4 or off + length > len(data):
            return "no %s (lump %d is %d bytes)" % (name, i, length)
        # ColorRGBExp32 samples: some must carry light
        lit = sum(1 for k in range(off, off + length - 3, 4) if any(data[k:k + 3]))
        if lit * 100 < (length // 4):
            return "%s is black (%d of %d samples lit)" % (name, lit, length // 4)
    return None


if __name__ == "__main__":
    err = check(sys.argv[1])
    if err:
        print("%s: UNLIT: %s" % (sys.argv[1], err), file=sys.stderr)
        sys.exit(1)
    print("%s: lit" % sys.argv[1])
