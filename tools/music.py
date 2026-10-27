#!/usr/bin/env python3
"""The music and sound effects: src/gen/music.asm for src/sound.asm.

Songs are written here in a small notation, a pattern per string:

    @lead       the instrument from here on
    D5 F#5 Bb4  notes (C1 is the lowest, B6 the highest)
    r           a rest
    /4          after a note or rest: its duration in rows, which stays
                until the next one (a pattern starts with none: give one)

A song has a speed (interrupts per row, 50 a second) and an order list per
channel: pattern names, with "|" where it goes round to after the last.
The three lists must be as long as each other, row for row. Channel C has
the drums: sound effects play over it.

Sound effects are tone sweeps with a decaying volume (sound.asm S_*): the
later in SFX, the higher their number, and a higher one wins.

    tools/music.py
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "src", "gen", "music.asm")

NOISE, NO_TONE, OCTAVE, HOLD = 0x10, 0x20, 0x40, 0x80
NOTES = 72                              # C1 to B6 (sound.asm note_tab)

# An instrument: its noise period, then a step per interrupt (volume and
# flags); the last one holds.
INSTRUMENTS = {
    "lead": (0, [11, 13, 12, 12, 11, 11, 10, 10, 10, 9, 9, 9, 8]),
    "brass": (0, [12, 14, 13, 13, 12, 12, 12, 11, 11, 11, 10]),
    "bass": (0, [14, 13, 12, 11, 10, 10, 9, 9, 8]),
    "kick": (0, [15 | OCTAVE, 14, 11, 8, 5, 2, 0]),
    "snare": (7, [14 | NOISE, 12 | NOISE | NO_TONE, 10 | NOISE | NO_TONE,
                  8 | NOISE | NO_TONE, 6 | NOISE | NO_TONE, 4 | NOISE | NO_TONE,
                  2 | NOISE | NO_TONE, 0 | NO_TONE]),
    "hat": (1, [9 | NOISE | NO_TONE, 6 | NOISE | NO_TONE, 3 | NOISE | NO_TONE,
                0 | NO_TONE]),
}

# Sound effects, lowest number first: flags (1 tone, 2 noise), noise
# period, tone period, its change per interrupt, volume, interrupts per
# step down, length, interrupts before the tone starts again.
SFX = [
    ("swing", 2, 3, 0, 0, 10, 1, 6, 0),         # an attack starts
    ("block", 3, 2, 80, 10, 13, 1, 5, 0),       # an attack blocked
    ("tweet", 1, 0, 70, -5, 12, 0, 12, 6),      # Trump's tweet flies
    ("hit", 3, 10, 600, 60, 15, 1, 10, 0),      # an attack lands
    ("throw", 3, 12, 900, -40, 14, 2, 14, 0),   # a throw
    ("bell", 1, 0, 113, 0, 15, 3, 45, 0),       # a round starts
    ("ko", 1, 0, 200, 12, 15, 4, 60, 0),        # a knockout
]

# The fight: D minor at 150 bpm (4 rows a beat), two bars of drums and
# bass, then sixteen bars round and round: i VI VII V twice, then
# iv i VI V.
FIGHT_PATTERNS = {
    "rest2": "r/32",
    "lA": "@lead D5/2 F5 A5/4 G5/2 F5 E5 F5 "
          "D5 F5 Bb5/4 A5/2 G5 F5 G5 "
          "E5 G5 C6/4 Bb5/2 A5 G5 E5",
    "lA1": "@lead A5/6 G5/2 F5 E5 C#5/4",
    "lA2": "@lead A5/4 E5 C#5 A4",
    "lB1": "@lead G5/4 Bb5 D6/6 C6/2 "
           "A5/4 F5 D5/6 E5/2 "
           "F5/2 G5 F5 D5 Bb4/4 D5 "
           "E5/2 F5 E5 C#5 A4/8",
    "lB2": "@lead G5/2 A5 Bb5/4 A5/2 G5 F5/4 "
           "F5/2 E5 D5/4 A5/8 "
           "Bb5/4 A5 G5 F5 "
           "E5 C#5 E5 A5",
    "bD": "@bass D2/2 D3 D2 D3 D2 D3 D2 D3",
    "bBb": "@bass Bb1/2 Bb2 Bb1 Bb2 Bb1 Bb2 Bb1 Bb2",
    "bC": "@bass C2/2 C3 C2 C3 C2 C3 C2 C3",
    "bA": "@bass A1/2 A2 A1 A2 A1 A2 A1 A2",
    "bG": "@bass G1/2 G2 G1 G2 G1 G2 G1 G2",
    "dr": "@kick C2/2 @hat C5 @snare E4 @hat C5 @kick C2 @hat C5 @snare E4 @hat C5",
    "drf": "@kick C2/2 @kick C2 @snare E4 @snare E4 @kick C2 @snare E4 @snare E4 @snare E4/1 @snare E4",
}
FIGHT = (5, [
    ["rest2", "|", "lA", "lA1", "lA", "lA2", "lB1", "lB2"],
    ["bD", "bD", "|", "bD", "bBb", "bC", "bA", "bD", "bBb", "bC", "bA",
     "bG", "bD", "bBb", "bA", "bG", "bD", "bBb", "bA"],
    ["dr", "dr", "|"] + ["dr", "dr", "dr", "drf"] * 4,
])

# The victory: a fanfare in D, then quiet.
WIN_PATTERNS = {
    "wl": "@brass D5/2 D5 D5 A5/6 F#5/2 A5 D6/16",
    "wb": "@bass D3/8 A2 D2/16",
    "wd": "@kick C2/2 @snare E4 @snare E4 @kick C2/6 @snare E4/2 @snare E4 "
          "@kick C2/16",
    "quiet": "r/64",
}
WIN = (5, [
    ["wl", "|", "quiet"],
    ["wb", "|", "quiet"],
    ["wd", "|", "quiet"],
])

NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note(tok):
    n = NAMES[tok[0]]
    rest = tok[1:]
    while rest and rest[0] in "#b":
        n += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    v = (int(rest) - 1) * 12 + n
    if not 0 <= v < NOTES:
        sys.exit("music: note %s out of range" % tok)
    return v


def pattern(name, text):
    """A pattern's bytes and its length in rows."""
    out, rows, dur = [], 0, None
    insts = list(INSTRUMENTS)
    for tok in text.split():
        if tok.startswith("@"):
            out.append(0xC0 + insts.index(tok[1:]))
            continue
        tok, _, d = tok.partition("/")
        if d:
            if not 1 <= int(d) <= 64:
                sys.exit("music: %s: duration %s" % (name, d))
            if int(d) != dur:
                dur = int(d)
                out.append(0x7F + dur)
        if dur is None:
            sys.exit("music: %s: a note before any duration" % name)
        out.append(0x60 if tok == "r" else note(tok))
        rows += dur
    return out + [0xFF], rows


def song(label, spec, patterns, lines):
    speed, orders = spec
    lengths = []
    for ch, order in enumerate(orders):
        loop = order.index("|")
        names = order[:loop] + order[loop + 1:]
        lengths.append([sum(patterns[n][1] for n in order[:loop]),
                        sum(patterns[n][1] for n in names)])
        lines.append("%s_%d" % (label, ch))
        for i, n in enumerate(names):
            if i == loop:
                lines.append("%s_%d_loop" % (label, ch))
            lines.append("    defw pat_%s" % n)
        lines.append("    defw 0,%s_%d_loop" % (label, ch))
    if any(l != lengths[0] for l in lengths):
        sys.exit("music: %s: the channels' lengths differ: %s" % (label, lengths))
    lines.insert(0, "%s defb %d\n    defw %s_0,%s_1,%s_2" % (label, speed, label, label, label))


def main():
    lines = [";; generated by tools/music.py: the music and sound effects (sound.asm)", ""]
    lines.append(";; Tone periods, C1 to B6, for the CPC's 1 MHz AY: 1e6 / 16 / f.")
    lines.append("note_tab")
    per = [round(1e6 / 16 / (440 * 2 ** ((n - 45) / 12))) for n in range(NOTES)]
    for k in range(0, NOTES, 12):
        lines.append("    defw " + ",".join(str(p) for p in per[k:k + 12]))
    lines.append("")
    lines.append("instruments")
    for name in INSTRUMENTS:
        lines.append("    defw ins_%s" % name)
    for name, (noise, steps) in INSTRUMENTS.items():
        lines.append("ins_%s defb %d,%s,#80" % (name, noise, ",".join("#%02X" % s for s in steps)))
    lines.append("")
    for i, s in enumerate(SFX):
        lines.append("SFX_%s EQU %d" % (s[0].upper(), i + 1))
    lines.append("sfx_tab")
    for name, flags, noise, per, dper, vol, decay, length, rep in SFX:
        lines.append("    defb %d,%d : defw %d,%d : defb %d,%d,%d,%d  ; %s"
                     % (flags, noise, per, dper & 0xFFFF, vol, decay, length, rep, name))
    lines.append("")
    total = 0
    for label, spec, pats in (("song_fight", FIGHT, FIGHT_PATTERNS), ("song_win", WIN, WIN_PATTERNS)):
        encoded = {n: pattern(n, t) for n, t in pats.items()}
        body = []
        song(label, spec, encoded, body)
        lines += body
        for n, (data, _) in encoded.items():
            lines.append("pat_%s defb %s" % (n, ",".join("#%02X" % b for b in data)))
            total += len(data)
        lines.append("")
    new = "\n".join(lines) + "\n"
    old = open(OUT).read() if os.path.exists(OUT) else ""
    if new != old:
        with open(OUT, "w") as fh:
            fh.write(new)
    print("music: %d bytes of patterns" % total)


if __name__ == "__main__":
    main()
