#!/usr/bin/env python3
"""The title screen: art/title.png (160 x 200, a firmware Mode 0 screen) and
build/TITLE.SCR, packed for the loader (src/loader.asm show_title).

The picture uses the game's pens: the shared ones, Trump's own colours in
6-9 and Putin's in 10-13 (as fighter A and B), and two title colours in 14
and 15 (art/title.json). The big letters are the victory screen's 3 x 5
font (src/victory.asm), scaled up.

TITLE.SCR: "TL", version 1, the 16 firmware colours, the packed length
(word), then the screen's 16 KB as it is in memory (#C000-#FFFF), packed
like a stage (tools/stage_pack.py).

    tools/title_art.py
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpc_palette import FIXED_COLOURS, HW_COLOURS  # noqa: E402
from sprite_codegen import char_settings, encode_byte, pen_map  # noqa: E402
from stage_pack import pack, unpack  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 160, 200
ROOM = 0xB000 - 0x9800                  # where the loader puts it

GLYPHS = {                              # src/victory.asm font
    "P": (7, 5, 7, 4, 4), "U": (5, 5, 5, 5, 7), "E": (7, 4, 6, 4, 7),
    "T": (7, 2, 2, 2, 2), "F": (7, 4, 6, 4, 4), "I": (7, 2, 2, 2, 7),
    "G": (3, 4, 5, 5, 3), "H": (5, 5, 7, 5, 5), "V": (5, 5, 5, 5, 2),
    "S": (3, 4, 2, 1, 6), "R": (6, 5, 6, 5, 5), " ": (0, 0, 0, 0, 0),
    "C": (3, 4, 4, 4, 3), "N": (6, 5, 5, 5, 5), "A": (2, 5, 7, 5, 5),
    "O": (2, 5, 5, 5, 2), "2": (7, 1, 7, 4, 7), "0": (7, 5, 5, 5, 7),
    "6": (7, 4, 7, 5, 7), "-": (0, 0, 7, 0, 0),
}


BIG = {                                 # 5 x 7, for the title's letters
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "U": ("10001",) * 6 + ("01110",),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "T": ("11111",) + ("00100",) * 6,
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "I": ("01110",) + ("00100",) * 5 + ("01110",),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01110"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
}


def big(px, s, y0, sx, sy, pen, shadow):
    """s in the 5 x 7 font, centred, each pixel sx by sy, with a shadow."""
    step = 6 * sx
    x0 = (W - (len(s) * step - sx)) // 2
    for k, ch in enumerate(s):
        for r, row in enumerate(BIG[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    for yy in range(sy):
                        for xx in range(sx):
                            x, y = x0 + k * step + c * sx + xx, y0 + r * sy + yy
                            put(px, x + 1, y + 2, shadow)
    for k, ch in enumerate(s):
        for r, row in enumerate(BIG[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    for yy in range(sy):
                        for xx in range(sx):
                            put(px, x0 + k * step + c * sx + xx, y0 + r * sy + yy,
                                pen if yy < sy - 1 or r < 6 else 15)


def text(px, s, x0, y0, sx, sy, pen, shadow=None):
    """s in the 3 x 5 font, each pixel sx by sy, 1 pixel apart (scaled)."""
    for k, ch in enumerate(s):
        for r, bits in enumerate(GLYPHS[ch]):
            for c in range(3):
                if bits >> (2 - c) & 1:
                    x = x0 + (k * 4 + c) * sx
                    y = y0 + r * sy
                    for yy in range(sy):
                        for xx in range(sx):
                            if shadow is not None:
                                put(px, x + xx + 1, y + yy + 2, shadow)
                            put(px, x + xx, y + yy, pen)


def put(px, x, y, p):
    if 0 <= x < W and 0 <= y < H:
        px[y][x] = p


def sprite(px, char, frame, side, x0, y0, flip):
    im = Image.open(os.path.join(REPO, "art", "sprites", char, frame + ".png"))
    pens = pen_map(char, side)
    src = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            p = pens[src[x, y]]
            if p:
                put(px, x0 + (w - 1 - x if flip else x), y0 + y, p)


def draw(cfg):
    px = [[0] * W for _ in range(H)]
    for y in range(4, 100):                 # a navy glow behind the letters
        for x in range(W):
            if (x + y) % 2 == 0 and ((x - 80) / 84) ** 2 + ((y - 50) / 50) ** 2 < 1:
                px[y][x] = 3
    big(px, "PUPPET", 10, 4, 5, 6, 15)
    big(px, "FIGHT", 56, 4, 5, 6, 15)
    for x in range(8, W - 8):               # a stage edge under them
        px[185][x] = 2
        px[186][x] = 5
    sprite(px, "trump", "idle_0", "a", 22, 121, False)
    sprite(px, "putin", "idle_0", "b", 106, 121, True)
    text(px, "VS", 68, 144, 3, 4, 14, 3)
    text(px, "PRESS FIRE", 41, 189, 2, 2, 2)
    return px


def screen(px):
    mem = bytearray(16384)
    for y in range(H):
        a = (y % 8) * 2048 + (y // 8) * 80
        for x in range(0, W, 2):
            mem[a + x // 2] = encode_byte(px[y][x], px[y][x + 1])
    return bytes(mem)


def main():
    with open(os.path.join(REPO, "art", "title.json")) as fh:
        cfg = json.load(fh)
    inks = dict(FIXED_COLOURS)
    for i, k in enumerate(char_settings("trump")["colours"]):
        inks[6 + i] = k
    for i, k in enumerate(char_settings("putin")["colours"]):
        inks[10 + i] = k
    inks[14], inks[15] = cfg["inks"]
    px = draw(cfg)
    im = Image.new("P", (W, H))
    pal = []
    for p in range(16):
        pal += list(HW_COLOURS[inks[p]][1])
    im.putpalette(pal)
    im.putdata([p for row in px for p in row])
    im.save(os.path.join(REPO, "art", "title.png"))
    data = screen(px)
    packed = pack(data)
    assert unpack(packed) == data
    out = b"TL\x01" + bytes(inks[p] for p in range(16))
    out += len(packed).to_bytes(2, "little") + packed
    if len(out) > ROOM:
        sys.exit("title: %d bytes, more than the %d there is room for" % (len(out), ROOM))
    os.makedirs(os.path.join(REPO, "build"), exist_ok=True)
    with open(os.path.join(REPO, "build", "TITLE.SCR"), "wb") as fh:
        fh.write(out)
    print("title: 16384 bytes packed to %d" % len(out))


if __name__ == "__main__":
    main()
