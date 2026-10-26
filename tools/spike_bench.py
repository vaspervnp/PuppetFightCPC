#!/usr/bin/env python3
"""Run the spike on a headless CPC 6128 and measure it against the beam.

Uses ~/repos/CPCTools/cpcemu (floooh/chips: cycle-accurate Z80, gate array,
CRTC, with the 6128's own ROMs). The snapshot is quickloaded and stepped
16 us at a time from the start, so the bench always knows the exact time:

* Where the beam is - the first frame tick after irq_init is serviced on
  time (interrupts are on and the program is idle), which fixes when VSYNC
  starts. Every later VSYNC is exactly one 19968 us frame after it: the
  CRTC's frame never changes length. Display line 0 is 40 lines after VSYNC.
* Phase timing - the program writes bench_phase at every step of the
  rebuild; the time each value is held is the cost of that step.
* Beam check - each time the beam starts a scanline in the fighter band, the
  bytes it is about to fetch are read. They are judged against the band as
  it was when the current rebuild started and as it is when the next one
  starts. Neither: the line was caught half drawn, which is visible flicker.
  Still the old picture: late, the line changes a frame after the rest (a
  tear).
* Correctness - after the run the band is rebuilt in Python from the
  background mirror and the span streams in RAM, and compared byte for byte
  with the screen. Any difference is debris or a drawing bug.

    tools/spike_bench.py [--renders 96] [--png build/spike.png]
                         [--keys RIGHT@10-30,a@10-30,SPACE@40]

--keys holds keys by picture number (render_count): NAME@n for one picture,
NAME@n-m for a run. Player 1 is the cursor keys and SPACE (punch); player 2
is w a s d, z (punch) and x (kick).
"""
import argparse
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.expanduser("~/repos/CPCTools/cpcemu"))
import ctypes  # noqa: E402
import cpc as cpcmod  # noqa: E402
from cpc import CPC  # noqa: E402

_ram_ptr = cpcmod._lib.cpcemu_ram_ptr
_ram_ptr.restype = ctypes.POINTER(ctypes.c_uint8)
_ram_ptr.argtypes = [ctypes.c_void_p, ctypes.c_int]

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(REPO, "build")
sys.path.insert(0, os.path.join(REPO, "tools"))
from sprite_codegen import flip_of, mask_of  # noqa: E402

STEP = 16           # us per emulator step
LINE_US = 64
FRAME_US = 312 * LINE_US
BLANK = 40          # scanlines from the start of VSYNC to display line 0
LINES = 272
PHASES = {1: "restore A (Trump, right)", 2: "restore B (Putin, left)",
          3: "draw A", 4: "draw B (Putin, left)",
          6: "scheduler overhead", 5: "logic", 7: "prepare",
          8: "restore lists (both)", 9: "compile"}
REBUILD_PHASES = (1, 2, 3, 4, 6)


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
        self.band_top = self.S["BAND_TOP"]
        self.band_end = self.S["FLOOR_Y"]
        self.fighter_y = self.S["FIGHTER_Y"]
        self.windows = defaultdict(list)        # jump state -> beam line at the end
        self.c = CPC()
        self.c.run_frames(5)
        self.c.quickload(os.path.join(BUILD, "pfspike.sna"))
        self.t = 0
        # The first frame tick after irq_init: VSYNC started 2 lines (and the
        # handler's few us) before frame_count moved.
        fc = self.peek("FRAME_COUNT")
        while self.peek("FRAME_COUNT") == fc:
            self.step()
        self.vsync0 = self.t - 2 * LINE_US - STEP
        self.step(60 * FRAME_US)                # first pictures
        lt = self.c.read_ram(self.S["LINE_TAB_AT"], LINES * 2)
        self.line_addr = [lt[2 * i] | lt[2 * i + 1] << 8 for i in range(LINES)]

    def step(self, us=STEP):
        self.t += self.c.run_us(us) // 4        # exec returns 4 MHz ticks

    def beam(self):
        """Display line the beam is on (negative: in the blanking)."""
        return ((self.t - self.vsync0) % FRAME_US) // LINE_US - BLANK

    def field(self, fighter, name, size=1):
        a = self.S[fighter] + self.S[name]
        b = self.c.read_ram(a, size)
        return b[0] if size == 1 else b[0] | b[1] << 8

    def bank_read(self, config, addr, size):
        """Read from the extra RAM that RAM configuration #C4-#C7 puts at #4000."""
        p = _ram_ptr(self.c._h, config - 0xC0)
        return bytes(p[addr - 0x4000 + i] for i in range(size))

    def jump_state(self):
        fa, fb = self.field("FIGHTER_A", "F_OY"), self.field("FIGHTER_B", "F_OY")
        return (("A up" if fa < self.fighter_y else "A down") + ", " +
                ("B up" if fb < self.fighter_y else "B down"))

    def scenario(self):
        close = self.S.get("SCN_CLOSE_UP", 0)
        jump = self.S.get("SCN_JUMP", 0)
        if not self.S.get("SCN_DEMO", 0):
            return "play (controls)" + (": " + self.keys if self.keys else "")
        return "%s%s" % ("toe to toe" if close else "apart",
                         ", taking turns to jump then jumping together" if jump else "")

    def peek(self, name, size=1):
        b = self.c.read_ram(self.S[name], size)
        return b[0] if size == 1 else b[0] | b[1] << 8

    def band(self):
        return {L: self.c.read_ram(self.line_addr[L], 96) for L in range(self.band_top, self.band_end)}

    KEYS = {"LEFT": cpcmod.KEY_LEFT, "RIGHT": cpcmod.KEY_RIGHT,
            "UP": cpcmod.KEY_UP, "DOWN": cpcmod.KEY_DOWN, "SPACE": cpcmod.KEY_SPACE}

    def set_keys(self, script):
        self.script = []
        for item in filter(None, (script or "").split(",")):
            name, _, span = item.partition("@")
            a, _, b = span.partition("-")
            code = self.KEYS.get(name, ord(name[0]) if len(name) == 1 else None)
            if code is None:
                sys.exit("unknown key %r" % name)
            self.script.append((code, int(a), int(b or a)))
        self.held = set()

    def apply_keys(self, pic):
        want = {code for code, a, b in self.script if a <= pic <= b}
        for code in want - self.held:
            self.c.key_down(code)
        for code in self.held - want:
            self.c.key_up(code)
        self.held = want

    def run(self, renders):
        last_ph = self.peek("BENCH_PHASE")
        last_pic = None
        ph_start = self.t
        durations = defaultdict(list)
        acc = defaultdict(int)              # this picture's time per phase
        epochs = []                         # band snapshot at each rebuild start
        seen = []                           # (epoch, line, bytes) per beam pass
        start_line = []                     # beam line at each rebuild start
        self.pic_starts = []                # time each picture's first rebuild starts
        self.pic_tick = self.peek("LAST_RENDER")
        self.waits = defaultdict(int)       # pictures each fighter waited for a frame
        self.trace = []                     # (time, beam, phase) for --trace
        last_beam = None
        state = None
        done = 0
        last_done_t = self.t
        while done < renders:
            self.step()
            if self.t - last_done_t > 50 * FRAME_US:
                sys.exit("stuck: no picture for 50 frames (pc %04X, phase %d)"
                         % (self.c.pc, self.peek("BENCH_PHASE")))
            pic = self.peek("RENDER_COUNT")
            if pic != last_pic:
                last_pic = pic
                self.apply_keys(done)
            ph = self.peek("BENCH_PHASE")
            if ph != last_ph:
                if last_ph in PHASES:
                    acc[last_ph] += self.t - ph_start
                if ph in REBUILD_PHASES and self.peek("LAST_RENDER") != self.pic_tick:
                    self.pic_tick = self.peek("LAST_RENDER")   # wait_render: a new picture
                    self.pic_starts.append(self.t)
                if last_ph in (0, 5) and ph in REBUILD_PHASES:
                    epochs.append(self.band())      # nothing touched yet
                    start_line.append(self.beam())
                    state = self.jump_state()
                if ph in (0, 5) and last_ph in REBUILD_PHASES and state:
                    self.windows[state].append(self.beam())
                if ph == 5 and last_ph != 9:
                    for k, v in acc.items():
                        durations[k].append(v)
                    acc.clear()
                    done += 1
                    last_done_t = self.t
                if ph == 7:                         # prepare: the picture is drawn
                    for f in ("FIGHTER_A", "FIGHTER_B"):
                        self.waits[f] += self.field(f, "F_HELD")
                    if done in getattr(self, "shots", ()):
                        self.c.screenshot(os.path.join(BUILD, "play_%03d.png" % done), scale=1)
                if last_ph == 5 and ph != 9:
                    durations[5].append(acc.pop(5, 0))
                last_ph, ph_start = ph, self.t
                self.trace.append((self.t, self.beam(), ph, done))
            b = self.beam()
            if b != last_beam:
                last_beam = b
                if epochs and self.band_top <= b < self.band_end:
                    seen.append((len(epochs) - 1, b, self.c.read_ram(self.line_addr[b], 96)))
        while self.peek("BENCH_PHASE") in REBUILD_PHASES:
            self.step()
        epochs.append(self.band())

        caught = defaultdict(int)
        late = defaultdict(int)
        for e, L, got in seen:
            before, after = epochs[e][L], epochs[e + 1][L]
            if got == after:
                continue
            if got == before:
                late[L] += 1
            else:
                caught[L] += 1
        return durations, start_line, caught, late, done, len(seen)

    def expected_band(self):
        """The band rebuilt from the mirror plus both fighters' span data."""
        out = {}
        for L in range(self.band_top, self.band_end):
            a = self.line_addr[L]
            m = ((a >> 8) & 0x3F | 0x40) << 8 | (a & 0xFF)
            out[L] = bytearray(self.c.read_ram(m, 96))
        for f in ("FIGHTER_A", "FIGHTER_B"):
            if not self.field(f, "F_DRAWN"):
                continue
            p = self.field(f, "F_OSPANS", 2)
            bank = self.field(f, "F_OBANK")
            x = self.field(f, "F_OX")
            y = self.field(f, "F_OY")
            w = self.field(f, "F_OW")
            flipped = self.field(f, "F_OFACE")
            top, lines, _drawn = self.bank_read(bank, p, 3)
            p += 3
            for i in range(lines):
                s, n = self.bank_read(bank, p, 2)
                p += 2
                data = []
                for _ in range(n):              # escaped: 0, b for any
                    b = self.bank_read(bank, p, 1)[0]   # byte not opaque
                    p += 1
                    if b == 0:
                        b = self.bank_read(bank, p, 1)[0]
                        p += 1
                    data.append(b)
                if not n:
                    continue
                row = out[y + top + i]
                for j, d in enumerate(data):
                    if flipped:
                        d = flip_of(d)
                        col = x + w - 1 - s - j
                    else:
                        col = x + s + j
                    row[col] = (row[col] & mask_of(d)) | d
        return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--renders", type=int, default=96)   # two jump cycles
    ap.add_argument("--png", default=os.path.join(BUILD, "spike.png"))
    ap.add_argument("--keys", default="")
    ap.add_argument("--trace", action="store_true", help="print phase changes with frame and beam line")
    ap.add_argument("--shots", default="", help="pictures to screenshot, e.g. 20,40")
    args = ap.parse_args()

    b = Bench()
    b.keys = args.keys
    b.shots = {int(x) for x in args.shots.split(",") if x}
    b.set_keys(args.keys)
    durations, starts, caught, late, npics, nseen = b.run(args.renders)

    if args.trace:
        t0 = b.vsync0
        for t, beam, ph, n in b.trace:
            print("trace pic %3d frame %4d line %3d phase %d" % (n, (t - t0) // FRAME_US, beam, ph))
    print("Scenario: %s" % b.scenario())
    print("Phase timings per picture over %d pictures (us, from the cycle-accurate 6128):" % npics)
    for ph, name in PHASES.items():
        d = durations.get(ph, [])
        if d:
            print("  %-28s min %5d  mean %5d  max %5d" % (name, min(d), sum(d) // len(d), max(d)))
    print("  rebuilds start with the beam on line %d-%d (the tick is line %d)" % (
        min(starts), max(starts), b.S["TICK_LINE"]))
    gaps = defaultdict(int)
    ps = b.pic_starts
    for t0, t1 in zip(ps, ps[1:]):
        gaps[round((t1 - t0) / FRAME_US)] += 1
    print("  frames between pictures: %s (2 = 25 fps)" % ", ".join(
        "%d x%d" % (k, gaps[k]) for k in sorted(gaps)))
    print("  frame held (not compiled yet): Trump %d, Putin %d pictures of %d" % (
        b.waits["FIGHTER_A"], b.waits["FIGHTER_B"], npics))
    print("  fighter band: lines %d-%d; a standing fighter's top is line %d" % (
        b.band_top, b.band_end - 1, b.fighter_y))
    print("  rebuilds end with the beam on line (next frame), by jump state:")
    for k in sorted(b.windows):
        v = b.windows[k]
        print("    %-16s %3d windows, latest line %4d" % (k, len(v), max(v)))
    print("Beam check (%d scanline passes over the band, judged per rebuild):" % nseen)
    print("  lines caught half drawn: %d (in %d line-frames)" % (len(caught), sum(caught.values())))
    print("  lines late (previous picture shown): %d (in %d line-frames)" % (len(late), sum(late.values())))
    if caught:
        print("  caught lines:", sorted(caught)[:20], "..." if len(caught) > 20 else "")

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
