#!/usr/bin/env python3
"""Listen to the game: run build/pfspike.sna in the headless 6128
(~/repos/CPCTools/cpcemu) and keep what the AY plays, as build/sound.wav.
First it times sound_tick (src/sound.asm) for a few seconds, from where the
program counter is.

    tools/sound_check.py [--seconds 30] [--keys SPACE@100-102,...]
                         [--poke NAME=VALUE@picture,...] [--out build/sound.wav]

--keys holds keys by picture number (render_count), like spike_bench.py.
--poke writes a byte to a symbol at a picture (fighter_b+F_HEALTH style sums
work), to get to the end of a round quickly.
"""
import argparse
import os
import struct
import sys
import wave

sys.path.insert(0, os.path.expanduser("~/repos/CPCTools/cpcemu"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpc as cpcmod  # noqa: E402
from cpc import CPC  # noqa: E402
from spike_bench import BUILD, load_syms  # noqa: E402

RATE = 44100
STEP = 4                                    # us, while timing
TIMED = 3                                   # seconds timed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=30)
    ap.add_argument("--keys", default="")
    ap.add_argument("--poke", default="")
    ap.add_argument("--out", default=os.path.join(BUILD, "sound.wav"))
    args = ap.parse_args()
    S = load_syms()
    keys = {"LEFT": cpcmod.KEY_LEFT, "RIGHT": cpcmod.KEY_RIGHT, "UP": cpcmod.KEY_UP,
            "DOWN": cpcmod.KEY_DOWN, "SPACE": cpcmod.KEY_SPACE}
    script = []
    for item in filter(None, args.keys.split(",")):
        name, _, span = item.partition("@")
        a, _, b = span.partition("-")
        script.append((keys.get(name, ord(name[0])), int(a), int(b or a)))
    pokes = []
    for item in filter(None, args.poke.split(",")):
        what, _, frame = item.partition("@")
        name, _, value = what.partition("=")
        addr = sum(S[n.strip().upper()] for n in name.split("+"))
        pokes.append((addr, int(value, 0), int(frame)))

    c = CPC()
    c.run_frames(5)
    c.quickload(os.path.join(BUILD, "pfspike.sna"))
    c.audio_capture(True)
    lo, hi = S["SOUND_TICK"], S["NOTE_TAB"]
    runs, inside, t0 = [], False, 0
    held = set()
    samples = []
    frames = int(args.seconds * 50)
    poked = set()
    pic = 0
    for f in range(frames):
        now = c.peek(S["RENDER_COUNT"])         # (a byte: count its turns)
        pic += (now - pic) & 0xFF
        want = {k for k, a, b in script if a <= pic <= b}
        for k in want - held:
            c.key_down(k)
        for k in held - want:
            c.key_up(k)
        held = want
        for addr, value, at in pokes:
            if at <= pic and (addr, at) not in poked:
                c.poke(addr, value)
                poked.add((addr, at))
        if f < TIMED * 50:
            t = 0
            while t < 20000:
                t += c.run_us(STEP) // 4
                pc = c.pc
                now = lo <= pc < hi
                if now and not inside:
                    t0 = f * 20000 + t
                elif inside and not now:
                    runs.append(f * 20000 + t - t0)
                inside = now
        else:
            c.run_frames(1)
        samples += c.audio_take()
    if runs:
        runs = runs[1:]                     # (the first may be cut)
        print("sound_tick: %d calls, min %d us, mean %d us, max %d us (to %d us)"
              % (len(runs), min(runs), sum(runs) // len(runs), max(runs), STEP))
    peak = max(1e-6, max(abs(s) for s in samples))
    with wave.open(args.out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 30000)) for s in samples))
    print("%s: %.1f s" % (args.out, len(samples) / RATE))


if __name__ == "__main__":
    main()
