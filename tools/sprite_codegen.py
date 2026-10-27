#!/usr/bin/env python3
"""Generate Z80 sprite code and data from the sprite PNGs.

Two encodings, both fed from art/sprites/<char>/<move>_<n>.png:

* Span stream - what every sprite has. One span per scanline, data only:

      db top, lines           first non-empty line, number of lines after it
      per line: db s, n       first drawn byte, byte count (n = 0: empty line)
                db d0..dn-1   Mode 0 bytes, pen 0 transparent

  The mask is not stored: pen 0 is the only transparent pen, so a byte's mask
  is a function of the byte (mask_tab). A pixel that must be opaque black uses
  pen 15. The same stream drives the background restore (which only needs s
  and n) and the generic drawer, which can mirror the sprite on the fly.

* Compiled draw - a routine per frame that stores each byte with an
  immediate. About three times as fast as the generic mirrored drawer and
  about four times the size. <label>_draw faces right; --compiled-left also
  writes <label>_drawl, the same frame mirrored (DE = x is still the box's
  left edge).

Calling convention for a compiled routine (interrupts off). The routine
starts at the frame's first drawn line (the span header's "top"), and runs
in chunks of CHUNK lines so the banded rebuild can interleave it with the
other fighter's work (src/rebuild.asm):
      SP  = line_tab + 2*(y + top)
      DE  = x                 (byte column of the sprite's left edge)
      IXL = chunks to draw before yielding (>= 1)
      IY  = where to yield to; HL then holds the address to resume at,
            and DE is unchanged. After the last chunk HL is 0.
  Destroys AF, BC, HL. A frame of n lines has (n + CHUNK - 1) / CHUNK
  chunks.

Usage:
    tools/sprite_codegen.py tables                  -> src/gen/tables.asm
    tools/sprite_codegen.py frames OUT LABEL CHAR FRAME... [--compiled FRAME...]
                                [--compiled-left FRAME...]
"""
import argparse
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpc_palette import (GAME_PALETTE, HW_COLOURS, PERSONAL_A, PERSONAL_B,  # noqa: E402
                         SHARED_PENS)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LEFT_BITS = (7, 3, 5, 1)
RIGHT_BITS = (6, 2, 4, 0)
LEFT_MASK = 0xAA
RIGHT_MASK = 0x55


def encode_pixel(pen, bits):
    return sum(((pen >> i) & 1) << b for i, b in enumerate(bits))


def encode_byte(left, right):
    return encode_pixel(left, LEFT_BITS) | encode_pixel(right, RIGHT_BITS)


def mask_of(b):
    m = 0
    if b & LEFT_MASK == 0:
        m |= LEFT_MASK
    if b & RIGHT_MASK == 0:
        m |= RIGHT_MASK
    return m


def flip_of(b):
    return ((b & LEFT_MASK) >> 1) | ((b & RIGHT_MASK) << 1)


def char_settings(char):
    with open(os.path.join(REPO, "art", "sprites", char + "_pfc.json")) as fh:
        return json.load(fh)


def pen_map(char, side="a"):
    """Art pen -> game pen (GAME_PLAN 3.3): the shared pens, then the
    character's own colours at 6-9 (side a) or 10-13 (side b), after its
    merges."""
    cfg = char_settings(char)
    merge = {int(k): v for k, v in cfg["merge"].items()}
    base = PERSONAL_A if side == "a" else PERSONAL_B
    out = [0] * 16
    for p in range(1, 16):
        q = merge.get(p, p)
        if q in SHARED_PENS:
            out[p] = SHARED_PENS[q]
        elif GAME_PALETTE[q] in cfg["colours"]:
            out[p] = base + cfg["colours"].index(GAME_PALETTE[q])
        else:
            out[p] = None                   # an error only if a frame uses it
    return out


def load_frame(char, frame, side="a"):
    im = Image.open(os.path.join(REPO, "art", "sprites", char, frame + ".png"))
    if im.mode != "P":
        sys.exit("%s/%s: not an indexed PNG" % (char, frame))
    pens = pen_map(char, side)
    px = im.load()
    w, h = im.size
    rows = []
    for y in range(h):
        row = []
        for x in range(0, w, 2):
            a, b = pens[px[x, y]], pens[px[x + 1, y]]
            if a is None or b is None:
                sys.exit("%s/%s: art pen %d at (%d, %d) is neither shared nor one of "
                         "the character's colours" % (char, frame, px[x, y] if a is None
                                                      else px[x + 1, y], x, y))
            row.append(encode_byte(a, b))
        rows.append(row)
    return w // 2, rows


def spans(rows):
    """Per line (s, bytes) trimmed to the drawn bytes; (0, []) when empty."""
    out = []
    for r in rows:
        nz = [i for i, b in enumerate(r) if b]
        out.append((nz[0], r[nz[0]:nz[-1] + 1]) if nz else (0, []))
    first = next((i for i, (_, d) in enumerate(out) if d), 0)
    last = max((i for i, (_, d) in enumerate(out) if d), default=0)
    return first, out[first:last + 1]


def hexs(bs):
    return ",".join("#%02X" % b for b in bs)


def emit_sn(label, rows):
    """Just (s, n) per line: what a restore needs, without the data to skip."""
    top, lines = spans(rows)
    out = ["%s_sn" % label, "    defb %d,%d" % (top, len(lines))]
    for i in range(0, len(lines), 8):
        out.append("    defb " + ",".join("%d,%d" % (s, len(d)) for s, d in lines[i:i + 8]))
    return out


def emit_spans(label, width, rows):
    top, lines = spans(rows)
    out = ["%s_spans  ; %d bytes wide" % (label, width),
           "    defb %d,%d" % (top, len(lines))]
    for s, d in lines:
        out.append("    defb %d,%d%s" % (s, len(d), ("," + hexs(d)) if d else ""))
    return out


def mirror(rows):
    return [[flip_of(b) for b in reversed(r)] for r in rows]


CHUNK = 8


def emit_compiled(label, rows, suffix="draw"):
    """Straight-line code: one store per drawn byte, a yield point every
    CHUNK lines."""
    _top, lines = spans(rows)
    name = "%s_%s" % (label, suffix)
    out = [name]
    for k, (s, d) in enumerate(lines):
        if k and k % CHUNK == 0:
            nxt = "%s_c%d" % (name, k // CHUNK)
            out += ["    dec ixl", "    jr nz,%s" % nxt,
                    "    ld hl,%s" % nxt, "    jp (iy)", nxt]
        out.append("    pop hl")
        if not d:
            continue
        out.append("    add hl,de")
        if s <= 2:
            out += ["    inc hl"] * s
        else:
            out += ["    ld bc,%d" % s, "    add hl,bc"]
        for i, b in enumerate(d):
            m = mask_of(b)
            if b == 0:
                pass                                   # hole: leave the ground
            elif m == 0:
                out.append("    ld (hl),#%02X" % b)
            else:
                out += ["    ld a,(hl)", "    and #%02X" % m,
                        "    or #%02X" % b, "    ld (hl),a"]
            if i != len(d) - 1:
                out.append("    inc hl")
    out += ["    ld hl,0", "    jp (iy)"]
    return out


def compiled_size(rows):
    """Bytes of code emit_compiled produces for these rows (Z80 encodings)."""
    _top, lines = spans(rows)
    size = 5                                            # ld hl,0 : jp (iy)
    for k, (s, d) in enumerate(lines):
        if k and k % CHUNK == 0:
            size += 9                                   # the yield point
        size += 1                                       # pop hl
        if not d:
            continue
        size += 1 + (s if s <= 2 else 4)                # add hl,de + skip
        for b in d:
            size += 0 if b == 0 else 2 if mask_of(b) == 0 else 6
        size += len(d) - 1                              # inc hl between
    return size


def runtime_size(rows):
    """Bytes src/jit.asm writes for these rows, facing left (the larger):
    per line pop hl : pop bc : add hl,bc, then per byte a dec hl and its
    store, over the padded lines, with a yield every CHUNK lines."""
    _top, lines = spans(rows)
    lines = lines + [(0, [])] * (-len(lines) % CHUNK)
    size = 5                                            # ld hl,0 : jp (iy)
    for k, (s, d) in enumerate(lines):
        if k and k % CHUNK == 0:
            size += 9
        size += 3
        for b in d:
            size += 1 + (0 if b == 0 else 2 if mask_of(b) == 0 else 6)
    return size


def escaped(d):
    """A line's bytes as the runtime compiler reads them: an opaque byte as
    itself, any other byte (a hole, or one with a pen 0 pixel) as 0 then the
    byte, so the common case is told apart by a single test for zero."""
    out = []
    for b in d:
        out += [b] if b and not mask_of(b) else [0, b]
    return out


def padded_spans(label, width, rows):
    """The span stream src/jit.asm compiles: top, lines (padded), lines
    (drawn), then per line s, n (bytes on the line) and the escaped bytes,
    with empty lines added to a multiple of CHUNK lines so the code always
    ends on a whole chunk."""
    top, lines = spans(rows)
    pad = -len(lines) % CHUNK
    out = ["%s_spans  ; %d bytes wide" % (label, width),
           "    defb %d,%d,%d" % (top, len(lines) + pad, len(lines))]
    size = 3
    for s, d in lines:
        e = escaped(d)
        out.append("    defb %d,%d%s" % (s, len(d), ("," + hexs(e)) if e else ""))
        size += 2 + len(e)
    out += ["    defb 0,0"] * pad
    return out, size + 2 * pad


BANK_SIZE = 16384
BANK1_SLOTS = 6     # cache slots in bank 1 at most (src/config.asm)
REC_SIZE = 16
HIT_REACH = 2       # bytes a hit box reaches past the limb drawn: at the
                    # closest the fighters stand, bodies only just touch


def cmd_character(args):
    """Both bank images of a character: a directory at #4000 of the first
    bank, every frame's span stream, and compiled-frame cache slots for the
    runtime compiler (src/jit.asm) at the top of the second bank. The engine
    finds everything through the directory, so nothing outside the banks
    needs this file's labels.

        #4000  defb "P","F",5,moves
               defb bank 1 slots : defw their first address (--slot apart)
               defb the hardware inks of the character's 4 colours
               defb special kind (0 strike, 1 projectile, 2 throw)
               defw projectile record (0: none)
               defw victory lines: "NAME WINS!" and the taunt, each a
                    length then the characters, padded to TAUNT_SIZE
               per move: defb frames : defw frame records
        frame record (REC_SIZE bytes):
               defb bank (0/1), width in bytes, x offset in bytes (signed)
               defw spans, its size in bytes
               defb hurt box x0, x1 (bytes), y0, y1 (lines), frame-relative
               defb hit box the same (all 0: this frame doesn't hit)
               then REC_SIZE - 15 unused
        projectile record (PR_* in src/main.asm):
               defb width in bytes, lines, speed (bytes per picture),
                    damage, hitstun
               defw compiled draw facing right, facing left
               then its bytes, line by line (for tools/spike_bench.py)

    The compiler reads and writes with one bank paged in, so a frame from
    bank 0 going into a bank 1 slot is copied to main RAM first. The moves
    listed first in the character's table, the ones a fight shows most, go
    to bank 1, where that copy isn't needed, and as many slots as still fit
    go above them.
    """
    with open(os.path.join(REPO, "art", "sprites", args.char + ".json")) as fh:
        tbl = json.load(fh)
    c = args.char
    cfg = char_settings(c)
    lp = c if args.side == "a" else c + "_b"    # label prefix: both sides can be one character
    hits = {}
    hp = os.path.join(REPO, "art", "sprites", c + "_hits.json")
    if os.path.exists(hp):
        with open(hp) as fh:
            hits = {k: v for k, v in json.load(fh).items() if not k.startswith("_")}
    blocks = []                 # (label, size, lines) in table order
    recs = {}                   # frame file -> fields
    biggest = 0                 # largest compiled frame, either facing
    for m in tbl["moves"]:
        for fr in m["frames"]:
            f = fr["file"]
            width, rows = load_frame(c, f, args.side)
            label = "%s_%s" % (lp, f)
            sp, sp_size = padded_spans(label, width, rows)
            blocks.append((label, sp_size, sp))
            top, lines = spans(rows)
            drawn = [(top + i, sp, sp + len(d) - 1) for i, (sp, d) in enumerate(lines) if d]
            hurt = [min(a for _, a, _ in drawn), max(b for _, _, b in drawn),
                    drawn[0][0], drawn[-1][0]]
            recs[f] = dict(label=label, w=width, off=fr["offset_x"] // 2, size=sp_size,
                           hurt=hurt)
            need = runtime_size(rows)
            if need > args.slot:
                sys.exit("%s: %s compiles to %d bytes, more than a %d-byte slot"
                         % (c, f, need, args.slot))
            biggest = max(biggest, need)

    special = cfg.get("special", {"kind": "strike"})
    kind = SPECIAL_KINDS.index(special["kind"])
    proj = []
    if kind == 1:
        proj = emit_projectile("%s_shot" % lp, c, special)
    nframes = sum(len(m["frames"]) for m in tbl["moves"])
    dir_size = (16 + 3 * len(tbl["moves"]) + REC_SIZE * nframes + projectile_size(c, special)
                + TAUNT_SIZE)
    for nslots in range(min(BANK_SIZE // args.slot, BANK1_SLOTS), -1, -1):
        room = [BANK_SIZE - dir_size, BANK_SIZE - nslots * args.slot]
        used = [dir_size, 0]
        body = [[], []]
        where = {}
        ok = True
        for label, size, lines in blocks:      # hot moves first, to bank 1
            bank = 1 if used[1] + size <= room[1] + 0 else 0
            if bank == 0 and used[0] + size > BANK_SIZE:
                ok = False
                break
            used[bank] += size
            body[bank] += [""] + lines
            where[label] = bank
        if ok:
            break
    else:
        sys.exit("%s: the frames do not fit in two banks" % c)
    slot_base = 0x8000 - nslots * args.slot

    out0 = [";; generated by tools/sprite_codegen.py character - do not edit",
            ";; %s, bank 0 of 2: directory, frames" % c,
            "    ORG #4000",
            "%s_dir" % lp,
            '    defb "P","F",5,%d' % len(tbl["moves"]),
            "    defb %d : defw #%04X        ; cache slots in bank 1" % (nslots, slot_base),
            "    defb %s        ; inks" % ",".join("#%02X" % HW_COLOURS[k][2]
                                                  for k in cfg["colours"]),
            "    defb %d : defw %s        ; special: %s" % (kind, "%s_shot" % lp if proj else "0",
                                                         special["kind"]),
            "    defw %s_taunt" % lp]
    for m in tbl["moves"]:
        out0.append("    defb %d : defw %s_m_%s" % (len(m["frames"]), lp, m["name"]))
    for m in tbl["moves"]:
        out0.append("%s_m_%s" % (lp, m["name"]))
        for fr in m["frames"]:
            r = recs[fr["file"]]
            hurt = r["hurt"]
            hit = hits.get(m["name"])
            hitb = [0, 0, 0, 0]
            if hit and hit["frame"] == m["frames"].index(fr):
                x0, y0, x1, y1 = hit["box"]
                hitb = [x0 // 2, x1 // 2 + HIT_REACH, y0, y1]
            out0.append("    defb %d,%d,%d : defw %s_spans,%d : defb %s : defs %d"
                        % (where[r["label"]], r["w"], r["off"], r["label"], r["size"],
                           ",".join(str(v) for v in hurt + hitb), REC_SIZE - 15))
    out0 += [""] + emit_taunt("%s_taunt" % lp, cfg) + proj + body[0] + ["", "    ASSERT $<=#8000"]
    out1 = [";; generated by tools/sprite_codegen.py character - do not edit",
            ";; %s, bank 1 of 2: frames, then %d cache slots" % (c, nslots),
            "    ORG #4000"] + body[1] + ["", "    ASSERT $<=#%04X" % slot_base]
    base = args.out or os.path.join(REPO, "src", "gen", "%s_%s" % (c, args.side))
    write(base + "_bank0.asm", out0)
    write(base + "_bank1.asm", out1)
    hot = sorted({fr["file"].rsplit("_", 1)[0] for m in tbl["moves"] for fr in m["frames"]
                  if where["%s_%s" % (lp, fr["file"])] == 1},
                 key=lambda n: [m["name"] for m in tbl["moves"]].index(n))
    print("%s: bank 0 %d bytes, bank 1 %d bytes + %d cache slots; bank 1 moves: %s; "
          "largest compiled frame %d bytes" % (c, used[0], used[1], nslots, " ".join(hot), biggest))


SPECIAL_KINDS = ["strike", "projectile", "throw"]
# A projectile's pens are the same for both fighters, so the loader never
# has to remap its code: art pen -> game pen, the shared pens and the
# stage's pastel blue and green.
SHOT_PENS = {0: 0, 15: 1, 10: 2, 1: 3, 3: 4, 9: 5, 11: 14, 14: 15}


def load_shot(char, special):
    """The projectile's rows, cropped to what is drawn."""
    f = special["file"]
    im = Image.open(os.path.join(REPO, "art", "sprites", char, f + ".png"))
    px = im.load()
    w, h = im.size
    if w % 2:
        sys.exit("%s/%s: odd width" % (char, f))
    rows = []
    for y in range(h):
        row = []
        for x in range(0, w, 2):
            a, b = SHOT_PENS.get(px[x, y]), SHOT_PENS.get(px[x + 1, y])
            if a is None or b is None:
                sys.exit("%s/%s: a projectile may only use the shared and the stage pens"
                         % (char, f))
            row.append(encode_byte(a, b))
        rows.append(row)
    rows = [r for r in rows if any(r)]
    while not any(r[0] for r in rows):
        rows = [r[1:] for r in rows]
    while not any(r[-1] for r in rows):
        rows = [r[:-1] for r in rows]
    if len(rows) > 16 or len(rows[0]) > 8:
        sys.exit("%s/%s: a projectile is at most 8 bytes x 16 lines" % (char, f))
    return rows


def emit_projectile(label, char, special):
    """The projectile record and its compiled draws. Called with IXL >= the
    yields the code has (rebuild.asm RUN_ONCE gives 255), it draws every
    line in one go."""
    rows = load_shot(char, special)
    out = [label,
           "    defb %d,%d,%d,%d,%d" % (len(rows[0]), len(rows), special["speed"],
                                       special["damage"], special["hitstun"]),
           "    defw %s_draw,%s_drawl" % (label, label)]
    out += ["    defb " + hexs(r) for r in rows]
    out += emit_compiled(label, rows) + emit_compiled(label, mirror(rows), "drawl")
    return out


def projectile_size(char, special):
    if special["kind"] != "projectile":
        return 0
    rows = load_shot(char, special)
    return 9 + sum(len(r) for r in rows) + compiled_size(rows) + compiled_size(mirror(rows))


TAUNT_SIZE = 50         # src/main.asm
TEXT_CHARS = set(" ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?.,'-:")


def emit_taunt(label, cfg):
    """The victory screen's two lines (src/victory.asm): the character's
    name + " WINS!", and its taunt."""
    lines = [cfg["name"].upper() + " WINS!", cfg["taunt"]]
    data = []
    for t in lines:
        if len(t) > 24 or set(t) - TEXT_CHARS:
            sys.exit("%s: %r: at most 24 characters from %r"
                     % (cfg["name"], t, "".join(sorted(TEXT_CHARS))))
        data += [len(t)] + [ord(ch) for ch in t]
    data += [0] * (TAUNT_SIZE - len(data))
    return [label] + ["    defb " + ",".join(str(b) for b in data[i:i + 25])
                      for i in range(0, len(data), 25)]


PFC_HEADER = 64


def cmd_pfc(args):
    """A character file for the disc (GAME_PLAN 3.5): build/pfc/CHAR.PFC,
    a PFC_HEADER-byte header, then bank 0, then bank 1, both made for
    fighter A's pens (the loader moves fighter B's own colours to 10-13):

        0   "PFC", version 1
        4   name, 8 characters, space padded
        12  title, two lines of 12 characters, space padded
        36  hardware inks of the 4 own colours, then 4 for a mirror match
        44  defw bank 0 length, bank 1 length
        48  the home stage's file name (art/stages/<stage>.json), 8
            characters, space padded
    """
    import subprocess
    c = args.char
    cfg = char_settings(c)
    out = os.path.join(REPO, "build", "pfc")
    cmd_character(argparse.Namespace(char=c, slot=args.slot, side="a",
                                     out=os.path.join(out, c)))
    write(os.path.join(out, c + ".asm"), [
        ";; generated by tools/sprite_codegen.py pfc - do not edit",
        "    BANK 4", '    include "%s_bank0.asm"' % c,
        "    SAVE '%s0.bin',#4000,$-#4000" % c,
        "    BANK 5", '    include "%s_bank1.asm"' % c,
        "    SAVE '%s1.bin',#4000,$-#4000" % c])
    subprocess.run([os.environ.get("RASM", "rasm"), c + ".asm", "-oi", c + ".sna", "-v2"],
                   cwd=out, check=True, stdout=subprocess.DEVNULL)
    banks = [open(os.path.join(out, "%s%d.bin" % (c, i)), "rb").read() for i in (0, 1)]
    hdr = bytearray(b"PFC\x01")
    hdr += cfg["name"].upper().ljust(8)[:8].encode()
    hdr += title_lines(c, cfg["title"]).encode()
    hdr += bytes(HW_COLOURS[k][2] for k in cfg["colours"] + cfg["alt_colours"])
    hdr += len(banks[0]).to_bytes(2, "little") + len(banks[1]).to_bytes(2, "little")
    with open(os.path.join(REPO, "art", "stages", cfg["stage"] + ".json")) as fh:
        hdr += json.load(fh)["name"].ljust(8)[:8].encode()
    hdr += bytes(PFC_HEADER - len(hdr))
    with open(os.path.join(out, c.upper() + ".PFC"), "wb") as fh:
        fh.write(hdr + banks[0] + banks[1])


def title_lines(char, title):
    """The title as the select screen shows it: two lines of 12 characters,
    broken between words."""
    lines = [""]
    for word in title.split():
        if lines[-1] and len(lines[-1]) + 1 + len(word) > 12:
            lines.append("")
        lines[-1] += (" " if lines[-1] else "") + word
    if len(lines) > 2 or max(len(t) for t in lines) > 12:
        sys.exit("%s: the title does not fit two lines of 12: %r" % (char, title))
    return "".join(t.ljust(12) for t in lines + [""])[:24]


def cmd_remap(_args):
    """The loader's table: a Mode 0 byte with fighter A's own pens (6-9)
    moved to fighter B's (10-13)."""
    def pens(b, bits):
        return sum(((b >> bit) & 1) << i for i, bit in enumerate(bits))

    def move(p):
        return p + PERSONAL_B - PERSONAL_A if PERSONAL_A <= p < PERSONAL_B else p
    tab = [encode_byte(move(pens(b, LEFT_BITS)), move(pens(b, RIGHT_BITS))) for b in range(256)]
    out = [";; generated by tools/sprite_codegen.py remap - do not edit",
           "    ALIGN 256",
           "remap_tab"]
    for i in range(0, 256, 16):
        out.append("    defb " + hexs(tab[i:i + 16]))
    write(os.path.join(REPO, "src", "gen", "remap.asm"), out)


def tbl_frames(tbl):
    return [fr["file"] for m in tbl["moves"] for fr in m["frames"]]


def cmd_tables(_args):
    out = [";; generated by tools/sprite_codegen.py tables - do not edit",
           ";; Both tables must be page aligned: code indexes them with C and",
           ";; steps between them with INC B / DEC B.",
           "    ALIGN 256",
           "flip_tab  ; swap the two pixels of a Mode 0 byte"]
    for i in range(0, 256, 16):
        out.append("    defb " + hexs(flip_of(b) for b in range(i, i + 16)))
    out.append("mask_tab  ; #AA/#55 set where a pixel is pen 0")
    for i in range(0, 256, 16):
        out.append("    defb " + hexs(mask_of(b) for b in range(i, i + 16)))
    write(os.path.join(REPO, "src", "gen", "tables.asm"), out)


def cmd_frames(args):
    out = [";; generated by tools/sprite_codegen.py - do not edit",
           ";; %s: %s" % (args.char, " ".join(args.frame))]
    compiled = set(args.compiled or [])
    compiled_left = set(args.compiled_left or [])
    for f in args.frame:
        width, rows = load_frame(args.char, f)
        label = "%s_%s" % (args.label, f)
        out.append("")
        out += emit_spans(label, width, rows)
        out += emit_sn(label, rows)
        if f in compiled:
            body = emit_compiled(label, rows)
            if f in (args.right_unless or []):
                body = ["    IFNOT %s" % args.right_unless_sym] + body + ["    ENDIF"]
            out += body
        if f in compiled_left:
            body = emit_compiled(label, mirror(rows), "drawl")
            if args.left_if:
                body = ["    IF %s" % args.left_if] + body + ["    ENDIF"]
            out += body
    write(args.out, out)


def write(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("tables")
    sub.add_parser("remap")
    pf = sub.add_parser("pfc")
    pf.add_argument("char")
    pf.add_argument("--slot", type=int, required=True)
    ch = sub.add_parser("character")
    ch.add_argument("char")
    ch.add_argument("--slot", type=int, required=True,
                    help="cache slot size: every frame must compile into it")
    ch.add_argument("--side", choices="ab", default="a",
                    help="the fighter it is loaded as: own colours in pens 6-9 or 10-13")
    ch.add_argument("--out", help="output path and name prefix (default src/gen/CHAR_SIDE)")
    fr = sub.add_parser("frames")
    fr.add_argument("out")
    fr.add_argument("label")
    fr.add_argument("char")
    fr.add_argument("frame", nargs="+")
    fr.add_argument("--compiled", nargs="+")
    fr.add_argument("--compiled-left", nargs="+")
    fr.add_argument("--left-if", help="assemble the left-facing code only IF this symbol")
    fr.add_argument("--right-unless-sym", help="with --right-unless: the symbol")
    fr.add_argument("--right-unless", nargs="+",
                    help="assemble these frames' compiled code only IFNOT --right-unless-sym")
    args = ap.parse_args()
    {"tables": cmd_tables, "frames": cmd_frames, "character": cmd_character,
     "pfc": cmd_pfc, "remap": cmd_remap}[args.cmd](args)


if __name__ == "__main__":
    main()
