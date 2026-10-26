#!/usr/bin/env python3
"""Animated preview of every move, both fighters facing each other.

Writes docs/preview_<char>.gif (one character, all moves) and
docs/preview_versus.gif. Mode 0 pixels are shown at their 2:1 aspect.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpc_palette import pen_rgb  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCALE = 3
BG = pen_rgb(13)
FLOOR = pen_rgb(14)


def load(char):
    with open(os.path.join(REPO, "art", "sprites", char + ".json")) as f:
        tbl = json.load(f)
    moves = []
    for m in tbl["moves"]:
        frames = []
        for fr in m["frames"]:
            im = Image.open(os.path.join(REPO, "art", "sprites", char, fr["file"] + ".png")).convert("RGBA")
            im = im.resize((im.width * 2 * SCALE, im.height * SCALE), Image.NEAREST)
            frames.append((im, fr["offset_x"] * 2 * SCALE))
        moves.append((m["name"], frames))
    return moves


def stage(w, h, label):
    im = Image.new("RGBA", (w, h), BG + (255,))
    d = ImageDraw.Draw(im)
    d.rectangle((0, h - 10 * SCALE, w, h), fill=FLOOR + (255,))
    d.text((6, 4), label, fill=(255, 255, 255, 255))
    return im


def sequence(moves, repeats=2):
    """Each move played `repeats` times, held on its last frame briefly."""
    for name, frames in moves:
        for _ in range(repeats):
            for im, off in frames:
                yield name, im, off
        yield name, frames[-1][0], frames[-1][1]


def save(frames, path):
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=110, loop=0, disposal=2)


def single(char):
    moves = load(char)
    w, h = 64 * 2 * SCALE, 64 * SCALE + 14 * SCALE
    out = []
    for name, im, off in sequence(moves):
        st = stage(w, h, "%s: %s" % (char, name))
        st.alpha_composite(im, (16 * 2 * SCALE + off, h - 10 * SCALE - im.height + 2 * SCALE))
        out.append(st.convert("RGB"))
    save(out, os.path.join(REPO, "docs", "preview_%s.gif" % char))


def versus(a, b):
    ma, mb = load(a), load(b)
    w, h = 128 * 2 * SCALE, 64 * SCALE + 14 * SCALE
    sa, sb = list(sequence(ma)), list(sequence(mb))
    out = []
    for i in range(max(len(sa), len(sb))):
        na, ia, oa = sa[i % len(sa)]
        nb, ib, ob = sb[i % len(sb)]
        st = stage(w, h, "%s: %s   vs   %s: %s" % (a, na, b, nb))
        base = h - 10 * SCALE + 2 * SCALE
        st.alpha_composite(ia, (24 * 2 * SCALE + oa, base - ia.height))
        # the engine flips the second fighter; preview mirrors the frame
        fb = ib.transpose(Image.FLIP_LEFT_RIGHT)
        st.alpha_composite(fb, (72 * 2 * SCALE - ob - (fb.width - 32 * 2 * SCALE), base - fb.height))
        out.append(st.convert("RGB"))
    save(out, os.path.join(REPO, "docs", "preview_versus.gif"))


if __name__ == "__main__":
    os.makedirs(os.path.join(REPO, "docs"), exist_ok=True)
    for c in ("trump", "putin"):
        single(c)
    versus("trump", "putin")
    print("wrote docs/preview_*.gif")
