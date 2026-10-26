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


def load_frame(char, frame):
    im = Image.open(os.path.join(REPO, "art", "sprites", char, frame + ".png"))
    if im.mode != "P":
        sys.exit("%s/%s: not an indexed PNG" % (char, frame))
    px = im.load()
    w, h = im.size
    rows = []
    for y in range(h):
        rows.append([encode_byte(px[x, y], px[x + 1, y]) for x in range(0, w, 2)])
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


def padded_spans(label, width, rows):
    """emit_spans, with empty lines added to a multiple of CHUNK lines so a
    drawer working in chunks never runs past the end of the stream."""
    top, lines = spans(rows)
    pad = -len(lines) % CHUNK
    out = ["%s_spans  ; %d bytes wide" % (label, width),
           "    defb %d,%d" % (top, len(lines) + pad)]
    for s, d in lines:
        out.append("    defb %d,%d%s" % (s, len(d), ("," + hexs(d)) if d else ""))
    out += ["    defb 0,0"] * pad
    return out, 2 + sum(2 + len(d) for _, d in lines) + 2 * pad


BANK_SIZE = 16384
REC_SIZE = 12


def cmd_character(args):
    """Both bank images of a character: a directory at #4000 of the first
    bank, then every frame's span stream and (s, n) table, then compiled
    draws where asked for. The engine finds everything through the
    directory, so nothing outside the banks needs this file's labels.

        #4000  defb "P","F",1,moves
               per move: defb frames : defw frame records
        frame record (REC_SIZE bytes):
               defb bank (0/1), width in bytes, x offset in bytes (signed)
               defw spans, (s, n) table
               defb compiled bank : defw draw facing right, draw facing left
                                     (0 = draw it with the generic drawer)
    """
    with open(os.path.join(REPO, "art", "sprites", args.char + ".json")) as fh:
        tbl = json.load(fh)
    c = args.char
    right = set(args.compiled_right or [])
    left = set(args.compiled_left or [])

    blocks = []                 # (label, size, lines) to place
    recs = {}                   # frame file -> fields
    for m in tbl["moves"]:
        for fr in m["frames"]:
            f = fr["file"]
            width, rows = load_frame(c, f)
            label = "%s_%s" % (c, f)
            sp, sp_size = padded_spans(label, width, rows)
            sn = emit_sn(label, rows)
            sn_size = 2 + 2 * len(spans(rows)[1])
            blocks.append((label, sp_size + sn_size, sp + sn))
            recs[f] = dict(label=label, w=width, off=fr["offset_x"] // 2, rows=rows)
    code = []
    for f in tbl_frames(tbl):
        r = recs[f]
        if f in right:
            code.append((r["label"] + "_draw", compiled_size(r["rows"]),
                         emit_compiled(r["label"], r["rows"]), f, "r"))
        if f in left:
            mr = mirror(r["rows"])
            code.append((r["label"] + "_drawl", compiled_size(mr),
                         emit_compiled(r["label"], mr, "drawl"), f, "l"))

    nframes = sum(len(m["frames"]) for m in tbl["moves"])
    used = [4 + 3 * len(tbl["moves"]) + REC_SIZE * nframes, 0]
    body = [[], []]
    where = {}
    for label, size, lines in blocks + [(l, s, ls) for l, s, ls, _f, _d in code]:
        bank = 0 if used[0] + size <= BANK_SIZE else 1
        if used[bank] + size > BANK_SIZE:
            sys.exit("%s: %s does not fit in two banks" % (c, label))
        used[bank] += size
        body[bank] += [""] + lines
        where[label] = bank

    out0 = [";; generated by tools/sprite_codegen.py character - do not edit",
            ";; %s, bank 0 of 2: directory, frames" % c,
            "    ORG #4000",
            "%s_dir" % c,
            '    defb "P","F",1,%d' % len(tbl["moves"])]
    for m in tbl["moves"]:
        out0.append("    defb %d : defw %s_m_%s" % (len(m["frames"]), c, m["name"]))
    for m in tbl["moves"]:
        out0.append("%s_m_%s" % (c, m["name"]))
        for fr in m["frames"]:
            r = recs[fr["file"]]
            lab = r["label"]
            cr = lab + "_draw" if fr["file"] in right else "0"
            cl = lab + "_drawl" if fr["file"] in left else "0"
            cb = where.get(lab + "_draw", where.get(lab + "_drawl", 0))
            if fr["file"] in right and fr["file"] in left and \
                    where[lab + "_draw"] != where[lab + "_drawl"]:
                sys.exit("%s: both facings of %s must share a bank" % (c, lab))
            out0.append("    defb %d,%d,%d : defw %s_spans,%s_sn : defb %d : defw %s,%s"
                        % (where[lab], r["w"], r["off"], lab, lab, cb, cr, cl))
    out0 += body[0] + ["", "    ASSERT $<=#8000"]
    out1 = [";; generated by tools/sprite_codegen.py character - do not edit",
            ";; %s, bank 1 of 2" % c, "    ORG #4000"] + body[1] + ["", "    ASSERT $<=#8000"]
    base = os.path.join(REPO, "src", "gen", c)
    write(base + "_bank0.asm", out0)
    write(base + "_bank1.asm", out1)
    print("%s: bank 0 %d bytes, bank 1 %d bytes, %d free" % (
        c, used[0], used[1], 2 * BANK_SIZE - used[0] - used[1]))


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
    ch = sub.add_parser("character")
    ch.add_argument("char")
    ch.add_argument("--compiled-right", nargs="+")
    ch.add_argument("--compiled-left", nargs="+")
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
    {"tables": cmd_tables, "frames": cmd_frames, "character": cmd_character}[args.cmd](args)


if __name__ == "__main__":
    main()
