#!/usr/bin/env python3
"""Pack a stage for the disc: art/stages/<stage>.png -> build/stages/<NAME>.STG

The picture becomes the overscan screen's 32 KB as it is in memory
(#8000-#FFFF, the unused tails as zeros), packed with a small LZ that boot
unpacks straight into the screen (src/main.asm unpack):

    n = #00-#7E    n + 1 literal bytes follow
    n = #80-#FF    n - #7D bytes (3-130) from an offset word back
    n = #7F        the end

The file: "ST", version 1, the hardware inks of pens 0, 14 and 15, the
packed length (word), then the packed data. It must fit STAGE_ROOM.

    tools/stage_pack.py <stage> [--out FILE]
"""
import argparse
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpc_palette import HW_COLOURS  # noqa: E402
from sprite_codegen import encode_byte  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEADER = 8
STAGE_ROOM = 0x3FF0 - 0x2000    # src/config.asm (SETTINGS_AT follows)
STAGE_PENS = {0, 1, 2, 3, 4, 5, 14, 15}


def line_addr(y):
    row, raster = divmod(y, 8)
    if row < 21:
        return 0x8020 + raster * 2048 + row * 96
    return 0xC000 + raster * 2048 + (row - 21) * 96


def screen_image(path):
    im = Image.open(path)
    if im.mode != "P" or im.size != (192, 272):
        sys.exit("%s: not a 192 x 272 indexed PNG" % path)
    px = im.load()
    mem = bytearray(32768)
    for y in range(272):
        a = line_addr(y) - 0x8000
        for x in range(0, 192, 2):
            l, r = px[x, y], px[x + 1, y]
            if l not in STAGE_PENS or r not in STAGE_PENS:
                sys.exit("%s: pen %d at (%d, %d) is not a stage pen"
                         % (path, l if l not in STAGE_PENS else r, x, y))
            mem[a + x // 2] = encode_byte(l, r)
    return bytes(mem)


def pack(data):
    out = bytearray()
    lits = bytearray()
    heads = {}

    def flush():
        while lits:
            n = min(len(lits), 127)
            out.append(n - 1)
            out.extend(lits[:n])
            del lits[:n]

    def best(i):
        if i + 3 > len(data):
            return 0, 0
        bl, bo = 0, 0
        for j in reversed(heads.get(data[i:i + 3], [])[-96:]):
            n = 0
            while n < 130 and i + n < len(data) and data[j + n] == data[i + n]:
                n += 1
            if n > bl:
                bl, bo = n, i - j
                if n == 130:
                    break
        return bl, bo

    def add(i):
        if i + 3 <= len(data):
            heads.setdefault(data[i:i + 3], []).append(i)

    i = 0
    while i < len(data):
        n, off = best(i)
        if n >= 4:
            n2, _ = best(i + 1)                 # one literal first, if that
            if n2 > n + 1:                      # finds a longer match
                n = 0
        if n >= 4:
            flush()
            out.append(n + 0x7D)
            out += off.to_bytes(2, "little")
            for k in range(n):
                add(i + k)
            i += n
        else:
            lits.append(data[i])
            add(i)
            i += 1
    flush()
    out.append(0x7F)
    return bytes(out)


def unpack(src):
    """The Z80 unpacker in Python, to check the packer."""
    out = bytearray()
    i = 0
    while True:
        n = src[i]
        i += 1
        if n == 0x7F:
            return bytes(out)
        if n < 0x7F:
            out += src[i:i + n + 1]
            i += n + 1
        else:
            off = src[i] | src[i + 1] << 8
            i += 2
            for _ in range(n - 0x7D):
                out.append(out[-off])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage")
    ap.add_argument("--out")
    args = ap.parse_args()
    with open(os.path.join(REPO, "art", "stages", args.stage + ".json")) as fh:
        cfg = json.load(fh)
    data = screen_image(os.path.join(REPO, "art", "stages", args.stage + ".png"))
    packed = pack(data)
    if unpack(packed) != data:
        sys.exit("stage_pack: the packed stage does not unpack to the picture")
    if HEADER + len(packed) > STAGE_ROOM:
        sys.exit("%s: packs to %d bytes, more than the %d there is room for"
                 % (args.stage, HEADER + len(packed), STAGE_ROOM))
    head = b"ST\x01" + bytes(HW_COLOURS[k][2] for k in cfg["inks"])
    head += len(packed).to_bytes(2, "little")
    out = args.out or os.path.join(REPO, "build", "stages", cfg["name"] + ".STG")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as fh:
        fh.write(head + packed)
    print("%s: %d bytes packed to %d" % (cfg["name"], len(data), HEADER + len(packed)))


if __name__ == "__main__":
    main()
