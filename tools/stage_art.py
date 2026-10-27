#!/usr/bin/env python3
"""Draw the stages: art/stages/<stage>.png, 192 x 272 Mode 0 pixels.

Each pixel is a game pen (GAME_PLAN 3.3). A stage may use the shared pens
1-5 (black, white, navy, dark red, grey) and its own three: pen 0, 14 and
15, whose firmware colours art/stages/<stage>.json gives. Pen 14 stays
pastel blue on every stage, because projectiles use it. Lines 0-23 are the
HUD (pen 1: black); the fighters stand on line 212, the raised floor's top.

    tools/stage_art.py [stage...]       (all of them by default)
"""
import json
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpc_palette import FIXED_COLOURS, HW_COLOURS  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 192, 272
HUD = 24
FLOOR = 212
K, WH, NV, DR, GR = 1, 2, 3, 4, 5           # shared pens
P0, P14, P15 = 0, 14, 15                    # the stage's own


class Canvas:
    def __init__(self, fill):
        self.px = [[fill] * W for _ in range(H)]

    def put(self, x, y, p):
        if 0 <= x < W and 0 <= y < H:
            self.px[y][x] = p

    def rect(self, x0, y0, x1, y1, p):
        """Inclusive."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, p)

    def checker(self, x0, y0, x1, y1, p, q):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, p if (x + y) % 2 == 0 else q)

    def ellipse(self, cx, cy, rx, ry, p, q=None):
        """Filled; q (if given) dithers the lower half for shading."""
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                    if q is not None and y > cy + ry * 0.2 and (x + y) % 2:
                        self.put(x, y, q)
                    else:
                        self.put(x, y, p)

    def hline(self, x0, x1, y, p):
        self.rect(x0, y, x1, y, p)

    def vline(self, x, y0, y1, p):
        self.rect(x, y0, x, y1, p)

    def image(self, inks):
        colours = dict(FIXED_COLOURS)
        colours.update({0: inks[0], 14: inks[1], 15: inks[2]})
        pal = []
        for p in range(16):
            pal += list(HW_COLOURS[colours.get(p, 0)][1])
        im = Image.new("P", (W, H))
        im.putpalette(pal)
        im.putdata([p for row in self.px for p in row])
        return im


def cloud(c, cx, cy, s):
    """A puff of pastel blue with a white top."""
    for dx, dy, r in ((0, 0, 1.0), (-1.3, 0.3, 0.7), (1.3, 0.3, 0.75), (0.6, -0.5, 0.7)):
        c.ellipse(cx + dx * s * 2, cy + dy * s, r * s * 2, r * s, P14)
    for dx, dy, r in ((0, -0.2, 0.75), (0.6, -0.6, 0.5), (-1.1, 0.1, 0.45)):
        c.ellipse(cx + dx * s * 2, cy + dy * s, r * s * 2, r * s, WH)


def tree(c, cx, top, bottom):
    c.rect(cx - 2, top + 40, cx + 2, bottom, DR)
    c.vline(cx + 2, top + 40, bottom, K)
    for dx, dy, rx, ry in ((0, 18, 16, 16), (-10, 30, 12, 12), (10, 28, 13, 13),
                           (0, 36, 15, 12)):
        c.ellipse(cx + dx, top + dy, rx, ry, P15, K)


def whitehouse():
    """The White House lawn: sky, the North Portico, trees, a black iron
    fence in the fighters' band, and a podium with bunting as the floor."""
    c = Canvas(P0)
    c.rect(0, 0, W - 1, HUD - 1, K)
    c.checker(0, HUD, W - 1, HUD + 7, NV, P0)          # the sky deepens upwards
    for y in range(HUD + 8, HUD + 20, 2):
        for x in range(0, W, 4):
            c.put(x + (y // 2) % 4, y, NV)
    cloud(c, 26, 46, 7)
    cloud(c, 150, 38, 9)
    cloud(c, 100, 58, 5)

    # The building: wings, then the portico and its pediment in front.
    x0, x1 = 30, 161
    c.rect(x0, 104, x1, 164, WH)
    c.hline(x0 - 2, x1 + 2, 102, GR)                 # cornice
    c.hline(x0 - 2, x1 + 2, 103, WH)
    for x in range(x0, x1 + 1, 4):                   # balustrade
        c.rect(x, 96, x + 1, 101, WH)
    c.hline(x0, x1, 95, WH)
    c.hline(x0, x1, 101, GR)
    for wx in list(range(x0 + 4, 66, 10)) + list(range(126, x1 - 6, 10)):
        for wy in (110, 134):                        # windows, two floors
            c.rect(wx, wy, wx + 5, wy + 14, NV)
            c.hline(wx - 1, wx + 6, wy - 2, GR)      # pediment over each
            c.hline(wx, wx + 5, wy + 7, WH)          # sash bar
            c.vline(wx + 2, wy, wy + 14, WH)
    c.rect(x0, 160, x1, 164, GR)                     # plinth
    # Portico: columns in front of a shaded recess.
    px0, px1 = 70, 121
    c.rect(px0, 100, px1, 162, GR)
    c.rect(px0 + 4, 110, px1 - 4, 158, NV)           # the shadow behind
    c.rect(90, 132, 101, 158, DR)                    # the door
    c.rect(91, 133, 100, 140, NV)
    for cx in range(px0, px1 + 1, 10):
        c.rect(cx, 102, cx + 3, 160, WH)
        c.vline(cx + 3, 102, 160, GR)
    for y in range(80, 100):                         # pediment
        half = (y - 79) * 2 + 4
        c.hline(96 - half, 95 + half, y, WH)
    for y in range(86, 99):
        half = (y - 85) * 2 - 2
        if half > 0:
            c.hline(96 - half, 95 + half, y, GR)
    c.hline(px0 - 4, px1 + 4, 100, GR)
    # The flag on the roof.
    c.vline(95, 56, 80, GR)
    for i in range(10):
        c.hline(96, 117, 58 + i, DR if i % 2 == 0 else WH)
    c.rect(96, 58, 104, 63, NV)
    c.put(98, 60, WH)
    c.put(102, 60, WH)
    c.put(100, 62, WH)

    # Lawn, mowed in stripes, with hedges along the house.
    for y in range(165, FLOOR):
        if (y - 165) // 6 % 2:
            c.checker(0, y, W - 1, y, P15, K)
        else:
            c.hline(0, W - 1, y, P15)
    for hx in range(x0 - 4, x1 + 4, 12):
        c.ellipse(hx + 6, 165, 7, 4, P15, K)
    tree(c, 12, 86, 168)
    tree(c, 178, 82, 168)
    # A black iron fence across the band, behind the fighters.
    c.hline(0, W - 1, 178, K)
    c.hline(0, W - 1, 200, K)
    for x in range(0, W, 6):
        c.vline(x, 176, 203, K)
        c.put(x, 175, GR)
    # The podium: white edge, grey top, navy front with bunting.
    c.hline(0, W - 1, FLOOR, WH)
    c.hline(0, W - 1, FLOOR + 1, WH)
    c.checker(0, FLOOR + 2, W - 1, FLOOR + 3, GR, WH)
    c.rect(0, FLOOR + 4, W - 1, FLOOR + 15, GR)
    c.hline(0, W - 1, FLOOR + 16, K)
    c.rect(0, FLOOR + 17, W - 1, H - 1, NV)
    for sx in range(0, W, 32):                       # swags: red, white, navy
        for x in range(sx, sx + 32):
            t = (x - sx + 0.5) / 32
            depth = int(14 * math.sin(math.pi * t))
            for y in range(FLOOR + 18, FLOOR + 20 + depth):
                band = (FLOOR + 20 + depth - y)
                c.put(x, y, DR if band <= 3 else WH if band <= 6 else NV if band <= 9 else DR)
        c.ellipse(sx, FLOOR + 20, 3, 3, WH)          # rosettes
        c.ellipse(sx, FLOOR + 20, 1.5, 1.5, DR)
    c.ellipse(96, FLOOR + 46, 18, 9, WH)             # the seal
    c.ellipse(96, FLOOR + 46, 15, 7.5, NV)
    c.ellipse(96, FLOOR + 46, 9, 4.5, GR)
    c.hline(0, W - 1, FLOOR + 40, DR)
    return c


def kremlin():
    """A Kremlin hall: red walls between gold pilasters, arched windows, a
    chandelier, a marble floor behind the fighters and a carpeted dais."""
    c = Canvas(P0)
    c.rect(0, 0, W - 1, HUD - 1, K)
    c.rect(0, HUD, W - 1, HUD + 5, DR)               # the ceiling's edge
    c.hline(0, W - 1, HUD + 6, P15)
    c.checker(0, HUD + 7, W - 1, HUD + 8, P15, DR)
    for y in range(HUD + 12, 166, 8):                # the wall's damask
        for x in range((y // 8) % 2 * 4, W, 8):
            c.put(x + 1, y, DR)
            c.hline(x, x + 2, y + 1, DR)
            c.put(x + 1, y + 2, DR)
    # Arched windows between the pilasters.
    for wx in (20, 76, 132):
        w = 40
        top, bottom = 58, 150
        for y in range(top - 12, bottom + 1):
            for x in range(wx, wx + w):
                if y < top:                          # the arch
                    if ((x - wx - w / 2 + 0.5) / (w / 2)) ** 2 + ((y - top) / 14) ** 2 > 1:
                        continue
                c.put(x, y, P14)
        for y in range(top - 12, bottom + 1):        # the frame
            for x in range(wx - 2, wx + w + 2):
                inside = (y >= top or ((x - wx - w / 2 + 0.5) / (w / 2)) ** 2
                          + ((y - top) / 14) ** 2 <= 1) and wx <= x < wx + w
                near = (y >= top - 2 or ((x - wx - w / 2 + 0.5) / (w / 2 + 2)) ** 2
                        + ((y - top) / 16) ** 2 <= 1)
                if near and not inside and y <= bottom + 2:
                    c.put(x, y, P15)
        for x in range(wx + 9, wx + w, 10):          # mullions
            c.vline(x, top - 10, bottom, WH)
        for y in range(top + 10, bottom, 18):
            c.hline(wx, wx + w - 1, y, WH)
        c.checker(wx, bottom - 26, wx + w - 1, bottom, P14, WH)   # light low down
        c.rect(wx - 4, bottom + 3, wx + w + 3, bottom + 6, P15)   # sill
        c.hline(wx - 4, wx + w + 3, bottom + 7, DR)
    # Gold pilasters.
    for px in (4, 62, 118, 176):
        c.rect(px, HUD + 9, px + 11, 168, P15)
        c.vline(px + 9, HUD + 9, 168, DR)
        c.vline(px + 10, HUD + 9, 168, DR)
        c.vline(px + 2, HUD + 12, 166, WH)
        for y in range(HUD + 14, 166, 8):
            c.hline(px + 4, px + 7, y, DR)
        c.rect(px - 2, HUD + 9, px + 13, HUD + 12, P15)           # capital
        c.rect(px - 2, 164, px + 13, 168, P15)                    # base
    # The chandelier.
    c.vline(96, HUD + 9, 42, P15)
    c.ellipse(96, 50, 26, 6, P15, DR)
    c.ellipse(96, 47, 18, 4, WH)
    for x in range(72, 121, 6):
        c.vline(x, 40, 46, WH)
        c.put(x, 39, P14)
    for x in range(74, 119, 4):
        c.vline(x, 56, 58 + (x // 4) % 3, P15)
    # Marble floor behind the fighters: grey and white tiles in rows.
    c.hline(0, W - 1, 169, P15)
    c.hline(0, W - 1, 170, DR)
    for y in range(171, FLOOR):
        row = (y - 171) // 7
        for x in range(W):
            tile = (x // 16 + row) % 2
            c.put(x, y, WH if tile else GR)
        if (y - 171) % 7 == 6:
            c.checker(0, y, W - 1, y, GR, K)
    # The dais: gold edge, red carpet, an ornamented front.
    c.hline(0, W - 1, FLOOR, P15)
    c.hline(0, W - 1, FLOOR + 1, WH)
    c.rect(0, FLOOR + 2, W - 1, FLOOR + 15, P0)
    c.checker(0, FLOOR + 12, W - 1, FLOOR + 15, P0, DR)
    c.hline(0, W - 1, FLOOR + 16, P15)
    c.hline(0, W - 1, FLOOR + 17, K)
    c.rect(0, FLOOR + 18, W - 1, H - 1, DR)
    for dx in range(0, W, 16):                       # a band of gold lozenges
        for i in range(8):
            c.hline(dx + 8 - i, dx + 7 + i, FLOOR + 22 + i, P15)
            c.hline(dx + 8 - i, dx + 7 + i, FLOOR + 37 - i, P15)
        c.rect(dx + 7, FLOOR + 28, dx + 8, FLOOR + 31, P0)
    c.hline(0, W - 1, FLOOR + 20, P15)
    c.hline(0, W - 1, FLOOR + 39, P15)
    c.checker(0, FLOOR + 44, W - 1, FLOOR + 45, P15, DR)
    return c


STAGES = {"whitehouse": whitehouse, "kremlin": kremlin}


def main():
    names = sys.argv[1:] or list(STAGES)
    for n in names:
        with open(os.path.join(REPO, "art", "stages", n + ".json")) as fh:
            cfg = json.load(fh)
        c = STAGES[n]()
        out = os.path.join(REPO, "art", "stages", n + ".png")
        c.image(cfg["inks"]).save(out)
        print("wrote", os.path.relpath(out, REPO))


if __name__ == "__main__":
    main()
