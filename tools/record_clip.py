#!/usr/bin/env python3
"""Record a clip of the game on the headless 6128 (~/repos/CPCTools/cpcemu):
every 50 Hz frame and what the AY plays, as an mp4 (lossless-ish H.264 and
AAC), for trailers.

    tools/record_clip.py OUT.mp4 --sna build/pfspike.sna --seconds 20
    tools/record_clip.py OUT.mp4 --disc build/puppetfight.dsk --seconds 60 \\
        --keys 'run@50,SPACE@900-903,s@1000-1002'

--keys holds keys by emulator frame (50 a second): NAME@from-to, where NAME
is LEFT RIGHT UP DOWN SPACE, a single character, or "run" (types RUN"PUPPET
and RETURN, starting at that frame). --skip runs that many frames before
recording starts (to cut a boot).

The picture is the emulator's 768x272 doubled in height (the 4:3 a monitor
shows), scaled to 1080 lines and centred on a 1920x1080 black frame.
"""
import argparse
import os
import struct
import subprocess
import sys
import wave

sys.path.insert(0, os.path.expanduser("~/repos/CPCTools/cpcemu"))
import cpc as cpcmod  # noqa: E402
from cpc import CPC  # noqa: E402

RATE = 44100
KEYS = {"LEFT": cpcmod.KEY_LEFT, "RIGHT": cpcmod.KEY_RIGHT, "UP": cpcmod.KEY_UP,
        "DOWN": cpcmod.KEY_DOWN, "SPACE": cpcmod.KEY_SPACE, "RETURN": cpcmod.KEY_RETURN}


def script(spec):
    """{frame: (keys to press, keys to release)} from --keys."""
    out = {}
    def at(f, down, key):
        out.setdefault(f, ([], []))[0 if down else 1].append(key)
    for item in filter(None, spec.split(",")):
        name, _, span = item.partition("@")
        a, _, b = span.partition("-")
        a, b = int(a), int(b or a)
        if name == "run":
            for i, ch in enumerate('RUN"PUPPET\n'):
                k = cpcmod.KEY_RETURN if ch == "\n" else ch
                at(a + i * 6, True, k)
                at(a + i * 6 + 3, False, k)
            continue
        k = KEYS.get(name, name if len(name) == 1 else None)
        if k is None:
            sys.exit("unknown key " + name)
        at(a, True, k)
        at(b + 1, False, k)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--sna")
    ap.add_argument("--disc")
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("--keys", default="")
    args = ap.parse_args()

    c = CPC()
    c.run_frames(5)
    if args.disc:
        c.insert_disc(args.disc)
        c.run_frames(100)
    if args.sna:
        c.quickload(args.sna)
    keys = script(args.keys)
    f = 0
    def step():
        nonlocal f
        down, up = keys.get(f, ([], []))
        for k in down:
            c.key_down(k)
        for k in up:
            c.key_up(k)
        c.run_frames(1)
        f += 1
    for _ in range(args.skip):
        step()

    w, h = c.image().size
    tmp = args.out + ".wav"
    vid = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", "%dx%d" % (w, h), "-r", "50", "-i", "-",
         "-vf", "scale=%d:1080:flags=neighbor,pad=1920:1080:(ow-iw)/2:0" % (w * 540 // h // 2 * 2),
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "12", "-pix_fmt", "yuv420p",
         args.out + ".v.mp4"], stdin=subprocess.PIPE)
    c.audio_capture(True)
    c.audio_take()
    samples = []
    for _ in range(int(args.seconds * 50)):
        step()
        img = c.image()
        if img.size != (w, h):
            img = img.resize((w, h))
        vid.stdin.write(img.tobytes())
        samples += c.audio_take()
    vid.stdin.close()
    vid.wait()
    with wave.open(tmp, "wb") as wv:
        wv.setnchannels(1)
        wv.setsampwidth(2)
        wv.setframerate(RATE)
        wv.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 24000))))
                                for s in samples))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", args.out + ".v.mp4", "-i", tmp,
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", args.out],
                   check=True)
    os.remove(tmp)
    os.remove(args.out + ".v.mp4")
    print("%s: %.1f s" % (args.out, len(samples) / RATE))


if __name__ == "__main__":
    main()
