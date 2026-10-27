#!/usr/bin/env python3
"""Turn Blender renders into 32x64 Amstrad CPC Mode 0 sprites.

Input:  art/render/<char>/{manifest.json, <move>_<n>_id.png, <move>_<n>_lit.png}
Output: art/sprites/<char>/<move>_<n>.png   indexed PNG, game palette, 32x64
                                             (64x64 for "wide" falling frames)
        art/sprites/<char>_sheet.png         all frames, one row per move
        art/sprites/<char>_preview.png       4x scale with 2:1 Mode 0 pixels
        art/sprites/<char>.json              frame/move table for the Aseprite step

Mode 0 pixels are twice as wide as they are tall, so the 256x256 square
render is reduced by 8 horizontally and 4 vertically. Each hi-res pixel is
first mapped to a pen (material ramp + light level), then every 8x4 block
votes for its final pen. Facial features carry extra weight so a 1-pixel eye
survives the reduction.
"""
import json
import os
import sys
from collections import Counter

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpc_palette import OUTLINE, TRANSPARENT, palette_hex, pen_rgb  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 32, 64   # normal frame; wide frames are 64x64
BX, BY = 8, 4

# material -> (highlight, base, shadow) pens
RAMPS = {
    "suit_navy":   (2, 1, 1),
    "suit_grey":   (11, 9, 1),
    "shirt":       (10, 10, 11),
    "tie_red":     (4, 4, 3),
    "tie_blue":    (2, 2, 1),
    "skin_orange": (12, 5, 3),
    "skin_pink":   (6, 6, 3),
    "hair_yellow": (7, 12, 8),
    "hair_grey":   (10, 9, 8),
    "shoe":        (9, OUTLINE, OUTLINE),
    "eye_white":   (10, 10, 10),
    "pupil":       (OUTLINE, OUTLINE, OUTLINE),
    "mouth":       (3, 3, 3),
    "brow":        (8, 8, 8),
    "phone":       (10, 9, 9),
    "arm_navy_n":  (2, 2, 1),
    "arm_navy_f":  (2, 1, 1),
    "arm_grey_n":  (11, 9, 1),
    "arm_grey_f":  (11, 9, 1),
    "vest_white":  (10, 10, 9),
    "arm_skin_n":  (6, 6, 3),
    "arm_skin_f":  (6, 6, 3),
    "hair_black":  (1, OUTLINE, OUTLINE),
    "button_red":  (4, 4, 3),
    "skin_yellow": (7, 7, 8),
    "belt":        (9, OUTLINE, OUTLINE),
    "tshirt_black": (1, OUTLINE, OUTLINE),
    "arm_black_n": (1, OUTLINE, OUTLINE),
    "arm_black_f": (1, OUTLINE, OUTLINE),
    "chainsaw":    (10, 9, 9),
    "tshirt_olive": (8, 8, 14),
    "arm_olive_n": (8, 8, 14),
    "arm_olive_f": (8, 14, 14),
    "pants_green": (8, 14, OUTLINE),
    "beard":       (3, 3, OUTLINE),
    "crate":       (3, 3, OUTLINE),
    "suit_black":  (1, OUTLINE, OUTLINE),
    "globe_sea":   (2, 2, 1),
    "globe_land":  (14, 14, 14),
    "control":     (3, 3, OUTLINE),
    "strings":     (10, 10, 10),
}

WEIGHT = {"eye_white": 5, "pupil": 8, "mouth": 6, "brow": 3,
          "tie_red": 2, "tie_blue": 2, "phone": 3, "shirt": 1.5}

HIGHLIGHT = 0.90   # fraction of the frame's max light level
SHADOW = 0.50
# faces stay mostly mid-tone so dark features (mouth, eyes) stay readable
THRESHOLDS = {"skin_orange": (0.97, 0.30), "skin_pink": (0.97, 0.30),
              "skin_yellow": (0.97, 0.30)}
OPAQUE_MIN = 11    # of 32 hi-res pixels in a block needed to be opaque


def nearest_material(rgb, mats):
    best, bd = None, 1 << 30
    for name, c in mats.items():
        d = (rgb[0] - c[0]) ** 2 + (rgb[1] - c[1]) ** 2 + (rgb[2] - c[2]) ** 2
        if d < bd:
            best, bd = name, d
    return best


def convert_frame(id_img, lit_img, mats):
    idp = id_img.load()
    lp = lit_img.load()
    lits = [lp[x, y][0] for y in range(id_img.height) for x in range(id_img.width)
            if idp[x, y][3] >= 128]
    top = max(lits) if lits else 1
    cache = {}
    w = id_img.width // BX
    out = [[TRANSPARENT] * w for _ in range(H)]
    mat = [[None] * w for _ in range(H)]
    for by in range(H):
        for bx in range(w):
            votes = Counter()
            opaque = 0
            for y in range(by * BY, by * BY + BY):
                for x in range(bx * BX, bx * BX + BX):
                    r, g, b, a = idp[x, y]
                    if a < 128:
                        continue
                    opaque += 1
                    m = cache.get((r, g, b))
                    if m is None:
                        m = cache[(r, g, b)] = nearest_material((r, g, b), mats)
                    light = lp[x, y][0] / top
                    hi, base, sh = RAMPS[m]
                    t_hi, t_sh = THRESHOLDS.get(m, (HIGHLIGHT, SHADOW))
                    pen = hi if light >= t_hi else sh if light < t_sh else base
                    votes[(pen, m)] += WEIGHT.get(m, 1)
            if opaque >= OPAQUE_MIN:
                out[by][bx], mat[by][bx] = votes.most_common(1)[0][0]
    return add_outline(add_separation(out, mat))


def add_separation(px, mat):
    """Dark line where an arm crosses the body. The near arm is in front of
    the jacket, so the line goes on the jacket side; the far arm is behind
    it, so the line goes on the arm side."""
    def kind(m):
        if m is None:
            return None
        if m.startswith("arm_"):
            return "near" if m.endswith("_n") else "far"
        if m.startswith(("suit_", "vest_", "tshirt_")):
            return "body"
        return None

    behind = {("body", "near"), ("far", "body"), ("far", "near")}
    res = [row[:] for row in px]
    w = len(px[0])
    for y in range(H):
        for x in range(w):
            k = kind(mat[y][x])
            if k is None:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < H and (k, kind(mat[ny][nx])) in behind:
                    res[y][x] = OUTLINE
                    break
    return res


def add_outline(px):
    """Black outline around the silhouette, drawn into transparent pixels."""
    res = [row[:] for row in px]
    w = len(px[0])
    for y in range(H):
        for x in range(w):
            if px[y][x] != TRANSPARENT:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < H and px[ny][nx] not in (TRANSPARENT, OUTLINE):
                    res[y][x] = OUTLINE
                    break
    return res


def to_image(px):
    im = Image.new("P", (len(px[0]), H))
    flat = []
    for p in range(16):
        flat.extend(pen_rgb(p))
    im.putpalette(flat)
    im.putdata([p for row in px for p in row])
    im.info["transparency"] = TRANSPARENT
    return im


def preview(im, scale=4, bg=(40, 40, 60)):
    """Show Mode 0 pixels at their real 2:1 aspect."""
    rgba = im.convert("RGBA")
    big = rgba.resize((im.width * 2 * scale, H * scale), Image.NEAREST)
    canvas = Image.new("RGBA", big.size, bg + (255,))
    canvas.alpha_composite(big)
    return canvas


def process(char):
    src = os.path.join(REPO, "art", "render", char)
    dst = os.path.join(REPO, "art", "sprites", char)
    os.makedirs(dst, exist_ok=True)
    with open(os.path.join(src, "manifest.json")) as f:
        man = json.load(f)
    mats = {k: tuple(v) for k, v in man["materials"].items()}

    rows = []
    table = {"character": char, "width": W, "height": H,
             "palette": palette_hex(), "moves": []}
    for move in man["moves"]:
        frames = []
        for fr in move["frames"]:
            base = fr["file"]
            id_img = Image.open(os.path.join(src, base + "_id.png")).convert("RGBA")
            lit_img = Image.open(os.path.join(src, base + "_lit.png")).convert("RGBA")
            im = to_image(convert_frame(id_img, lit_img, mats))
            im.save(os.path.join(dst, base + ".png"), transparency=TRANSPARENT)
            frames.append(im)
        rows.append(frames)
        table["moves"].append({
            "name": move["name"],
            "frames": [{"file": fr["file"], "width": fr.get("width", W),
                        "offset_x": fr.get("offset_x", 0)} for fr in move["frames"]]})

    # rows are packed left to right; wide frames take two cells
    sheet_w = max(sum(im.width for im in r) for r in rows)
    sheet = Image.new("P", (sheet_w, H * len(rows)), TRANSPARENT)
    sheet.putpalette(rows[0][0].getpalette())
    for j, r in enumerate(rows):
        x = 0
        for im in r:
            sheet.paste(im, (x, j * H))
            x += im.width
    sheet.save(os.path.join(REPO, "art", "sprites", char + "_sheet.png"), transparency=TRANSPARENT)

    pv = Image.new("RGBA", (sheet_w * 8, H * 4 * len(rows)), (40, 40, 60, 255))
    for j, r in enumerate(rows):
        x = 0
        for im in r:
            pv.alpha_composite(preview(im), (x * 8, j * H * 4))
            x += im.width
    pv.save(os.path.join(REPO, "art", "sprites", char + "_preview.png"))

    with open(os.path.join(REPO, "art", "sprites", char + ".json"), "w") as f:
        json.dump(table, f, indent=1)
    return sum(len(r) for r in rows)


if __name__ == "__main__":
    for c in sys.argv[1:] or ["trump", "putin", "kim", "xi", "musk", "zelensky", "bremmer"]:
        print(c, process(c), "frames")
