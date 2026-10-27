#!/usr/bin/env python3
"""Smoke test in Caprice32, a second emulator with its own floppy
controller emulation, as far as possible from the headless one the
benches use: the disc driver (src/fdc.asm) meets a different µPD765.

Boots the disc, takes a screenshot of the title, of the select screen, of
the controls screen, chooses the computer as the opponent and starts, then
takes a screenshot every few seconds and quits. With a QUICKWIN=1 disc
(make QUICKWIN=1) player 1 wins every match at once, so the screenshots
show the ladder loading opponent after opponent by itself.

Needs the Caprice32 snap: its cap32 is run inside its confinement (the
disc and the typed keys go through its home directory), with SDL's dummy
drivers and no speed limit, so it needs no display and takes seconds.

Caprice32 names its screenshots by the second, in one folder: a run of
another Caprice32 at the same time mixes its screenshots in, and two in
the same second keep only the last.

Usage: tools/cap32_smoke.py disc.dsk out_dir [screenshots]
"""
import glob
import os
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~/snap/caprice32/current")
RUNNER = """export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
exec timeout 300 "$SNAP/usr/bin/cap32" --cfg_file="$SNAP_USER_DATA/etc/cap32.cfg" \\
  -O system.limit_speed=0 -O system.model=2 -O system.ram_size=128 -O video.scr_fps=0 \\
  -a "$(cat $SNAP_USER_DATA/pf_autocmd.txt)" "$SNAP_USER_DATA/disk/pf.dsk"
"""
WAIT = "q"          # a key the game ignores: typing it passes the time
SHOT = "\\(CAP32_SCRNSHOT)"


def main(dsk, out, n="24"):
    shots = os.path.join(HOME, "screenshots")
    before = set(glob.glob(os.path.join(shots, "*.png")))   # (other sessions'
    shutil.copy(dsk, os.path.join(HOME, "disk", "pf.dsk"))
    with open(os.path.join(HOME, "pf.sh"), "w") as f:
        f.write(RUNNER)
    down, right = "s", "d"          # player 2's keys work the menu too
    cmd = ('RUN"PUPPET\n' + WAIT * 400 + SHOT              # the title
           + " " + WAIT * 200 + SHOT                         # the menu
           + down + WAIT * 10 + down + WAIT * 10 + right + WAIT * 20 + SHOT
           + " " + WAIT * 60 + SHOT                          # the controls
           + WAIT * 400 + SHOT + " "                         # fire to fight
           + (WAIT * 150 + SHOT) * int(n)
           + "\\(CAP32_EXIT)")
    with open(os.path.join(HOME, "pf_autocmd.txt"), "w") as f:
        f.write(cmd)
    subprocess.run(["snap", "run", "--shell", "caprice32.launcher", "-c",
                    "sh $SNAP_USER_DATA/pf.sh"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=400)
    os.makedirs(out, exist_ok=True)
    taken = sorted(set(glob.glob(os.path.join(shots, "*.png"))) - before)
    for i, path in enumerate(taken):
        shutil.copy(path, os.path.join(out, "shot%02d.png" % i))
    print("%d screenshots in %s" % (len(taken), out))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
