#!/usr/bin/env python3
"""Run the milestone 1 spike on a headless CPC 6128 and measure it.

Uses ~/repos/CPCTools/cpcemu (floooh/chips: cycle-accurate Z80, gate array,
CRTC, with the 6128's own ROMs). The snapshot is quickloaded, left to draw
its stage, then stepped 16 us at a time so the beam can be followed:

* Phase timing - the program writes bench_phase at every step of the
  rebuild; the time each value is held is the cost of that step.
* Beam check - each time the beam starts a scanline in the fighter band, the
  bytes it is about to fetch are read. A line that matches neither the
  picture before the rebuild nor the one after it was caught half drawn:
  that is visible flicker. A line still showing the previous picture is
  only late (the fighter moves a frame later on that line: a tear).
* Correctness - after the run the band is rebuilt in Python from the
  background mirror and the span streams in RAM, and compared byte for byte
  with the screen. Any difference is debris or a drawing bug.

    tools/spike_bench.py [--renders 50] [--png build/spike.png]
"""
import argparse
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.expanduser("~/repos/CPCTools/cpcemu"))
from cpc import CPC  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(REPO, "build")
sys.path.insert(0, os.path.join(REPO, "tools"))
from sprite_codegen import flip_of, mask_of  # noqa: E402

STEP = 16           # us per emulator step
LINE_US = 64
BLANK = 40          # scanlines from the frame tick to display line 0
LINES = 272
BAND_TOP = 144
W = 16
FIGHTER_Y = 204
PHASES = {1: "restore A (Trump, right)", 2: "restore B (Putin, left)",
          3: "draw A (compiled)", 4: "draw B (Putin, left)", 5: "logic"}


def load_syms():
    syms = {}
    for line in open(os.path.join(BUILD, "pfspike.sym")):
        p = line.split()
        if len(p) >= 2 and p[1].startswith("#"):
            syms[p[0].upper()] = int(p[1][1:], 16)
    return syms


class Bench:
    def __init__(self):
        self.S = load_syms()
        self.c = CPC()
        self.c.run_frames(5)
        self.c.quickload(os.path.join(BUILD, "pfspike.sna"))
        self.c.run_frames(60)           # stage, mirror, first pictures
        lt = self.c.read_ram(self.S["LINE_TAB"], LINES * 2)
        self.line_addr = [lt[2 * i] | lt[2 * i + 1] << 8 for i in range(LINES)]

    def peek(self, name, size=1):
        b = self.c.read_ram(self.S[name], size)
        return b[0] if size == 1 else b[0] | b[1] << 8

    def band(self):
        return {L: self.c.read_ram(self.line_addr[L], 96) for L in range(BAND_TOP, LINES)}

    def run(self, renders):
        t = 0
        tick_t = None
        last_fc = self.peek("FRAME_COUNT")
        last_ph = self.peek("BENCH_PHASE")
        ph_start = 0
        durations = defaultdict(list)
        rebuild_start = None
        rebuild_spans = []                  # (start from tick, end from tick)
        frames = []                         # per frame: {line: bytes seen}
        seen = None
        pictures = [self.band()]            # picture after each rebuild
        caught = defaultdict(int)
        late = defaultdict(int)
        rebuilt_frames = []                 # index into frames of rebuild frames
        done = 0
        while done < renders:
            self.c.run_us(STEP)
            t += STEP
            fc = self.peek("FRAME_COUNT")
            if fc != last_fc:
                last_fc = fc
                tick_t = t
                if seen is not None:
                    frames.append(seen)
                seen = {}
            ph = self.peek("BENCH_PHASE")
            if ph != last_ph:
                if last_ph in PHASES:
                    durations[last_ph].append(t - ph_start)
                if last_ph == 0 and ph in (1, 2, 3, 4) and rebuild_start is None:
                    rebuild_start = t
                if ph in (0, 5) and last_ph in (1, 2, 3, 4):
                    # rebuild finished: the new picture
                    rebuild_spans.append((rebuild_start - tick_t, t - tick_t))
                    rebuilt_frames.append(len(frames))
                    pictures.append(self.band())
                    rebuild_start = None
                    done += 1
                last_ph, ph_start = ph, t
            if tick_t is not None and seen is not None:
                beam = (t - tick_t) // LINE_US - BLANK
                if BAND_TOP <= beam < LINES and beam not in seen:
                    seen[beam] = self.c.read_ram(self.line_addr[beam], 96)

        # judge every frame in which a rebuild ran
        for k, fi in enumerate(rebuilt_frames):
            if fi >= len(frames):
                continue
            before, after = pictures[k], pictures[k + 1]
            for L, got in frames[fi].items():
                if got == after[L]:
                    continue
                if got == before[L]:
                    late[L] += 1
                else:
                    caught[L] += 1
        return durations, rebuild_spans, caught, late, len(rebuilt_frames)

    def expected_band(self):
        """The band rebuilt from the mirror plus both fighters' span data."""
        out = {}
        for L in range(BAND_TOP, LINES):
            a = self.line_addr[L]
            m = ((a >> 8) & 0x3F | 0x40) << 8 | (a & 0xFF)
            out[L] = bytearray(self.c.read_ram(m, 96))
        for spans_sym, x_sym, flipped in (("FA_OLD_SPANS", "FA_OLD_X", False),
                                          ("FB_OLD_SPANS", "FB_OLD_X", True)):
            p = self.peek(spans_sym, 2)
            x = self.peek(x_sym)
            top, lines = self.c.read_ram(p, 2)
            p += 2
            for i in range(lines):
                s, n = self.c.read_ram(p, 2)
                data = self.c.read_ram(p + 2, n)
                p += 2 + n
                row = out[FIGHTER_Y + top + i]
                for j, d in enumerate(data):
                    if flipped:
                        d = flip_of(d)
                        col = x + W - 1 - s - j
                    else:
                        col = x + s + j
                    row[col] = (row[col] & mask_of(d)) | d
        return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--renders", type=int, default=50)
    ap.add_argument("--png", default=os.path.join(BUILD, "spike.png"))
    args = ap.parse_args()

    b = Bench()
    durations, spans, caught, late, nreb = b.run(args.renders)

    print("Phase timings over %d pictures (us, from the cycle-accurate 6128):" % nreb)
    for ph, name in PHASES.items():
        d = durations.get(ph, [])
        if d:
            print("  %-28s min %5d  mean %5d  max %5d" % (name, min(d), sum(d) // len(d), max(d)))
    st = [s for s, _ in spans]
    en = [e for _, e in spans]
    print("  rebuild after the tick:       starts %d-%d, ends %d-%d us" % (min(st), max(st), min(en), max(en)))
    top_us = (BLANK + FIGHTER_Y) * LINE_US
    print("  beam reaches the fighters' top line (%d) at %d us" % (FIGHTER_Y, top_us))

    print("Beam check (fighter band, lines %d-%d):" % (BAND_TOP, LINES - 1))
    print("  lines caught half drawn: %d (in %d line-frames)" % (len(caught), sum(caught.values())))
    print("  lines late (previous picture shown): %d (in %d line-frames)" % (len(late), sum(late.values())))
    if caught:
        print("  caught lines:", sorted(caught)[:20], "..." if len(caught) > 20 else "")

    b.c.run_us(400)                     # let rb_done record what it drew
    while b.peek("BENCH_PHASE") in (1, 2, 3, 4):
        b.c.run_us(STEP)
    exp = b.expected_band()
    got = b.band()
    bad = [(L, i) for L in exp for i in range(96) if exp[L][i] != got[L][i]]
    if bad and os.environ.get("BENCH_DEBUG"):
        for L, i in bad[:12]:
            print("   line %d byte %d: screen #%02X expected #%02X" % (L, i, got[L][i], exp[L][i]))
    print("Correctness: %d bytes differ from mirror + sprites%s" % (
        len(bad), "" if not bad else " - first at line %d byte %d" % bad[0]))

    b.c.screenshot(args.png, scale=2)
    print("Screenshot:", os.path.relpath(args.png, REPO))
    return 1 if (bad or caught) else 0


if __name__ == "__main__":
    sys.exit(main())
