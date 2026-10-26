# Milestone 1 — Tech Spike Results

Can two big puppet fighters be drawn on a full overscan Mode 0 screen at
25 fps with no flicker? Yes when they're apart. When they overlap it works
for standing fighters, but with almost no margin. The decisions that came
out of this are in [GAME_PLAN.md §3](GAME_PLAN.md#3-technical-design).

![spike screen](spike_screen.png)

*Trump (compiled, facing right) and Putin (mirrored, facing left) idling and
swaying on a 192×272 overscan stage, captured from the emulated 6128.*

## What was built

| File | What it does |
|---|---|
| `src/main.asm` | boot and move down to &0200, 25 fps loop, two-window rebuild schedule, spike logic (idle animation + sway) |
| `src/crtc.asm`, `src/irq.asm`, `src/video.asm` | overscan CRTC set-up, VSYNC-recognised frame tick, line table, stage, background mirror |
| `src/sprite.asm` | span restore (both facings) and the generic mirrored span drawer |
| `tools/sprite_codegen.py` | span streams, compiled routines (both facings), flip/mask tables |
| `tools/spike_bench.py` | runs the snapshot on the headless 6128 and measures it |

```bash
make                                    # build/pfspike.sna and build/pfspike.dsk (RUN"PFSPIKE)
make bench                              # measure on the headless 6128
make run                                # open in Caprice32
make PUTIN_DRAW=compiled CLOSE_UP=1     # variants, see the Makefile
```

## How it was measured

`tools/spike_bench.py` drives floooh/chips' CPC 6128 (cycle-accurate Z80,
gate array and CRTC, real ROMs) through `~/repos/CPCTools/cpcemu`, 16 µs at
a time:

- **Phase timing.** The rebuild writes `bench_phase` at every step, so the
  time each value is held is the cost of that step.
- **Beam check.** As the beam starts each scanline of the fighter band, the
  bytes it is about to fetch are captured. If they match neither the picture
  before the rebuild nor the one after, that line was *caught* half drawn,
  which is visible flicker.
- **Correctness.** The band is rebuilt in Python from the background mirror
  and the span streams in RAM, then compared with the screen byte for byte.
  Any difference is debris or a drawing bug.

## Results (60 pictures each)

| Step | Trump (352 bytes, 62 lines) | Putin (275 bytes, 57 lines) |
|---|---|---|
| Restore from mirror | 5.40 ms | 5.13 ms |
| Compiled draw | 2.83 ms (right) | 2.36 ms (left) |
| Generic mirrored span draw | — | 8.71 ms |

The beam reaches the standing fighters' top line (204) 15.6 ms after the
frame tick.

| Scenario | Rebuild ends | Lines caught | Bytes wrong |
|---|---|---|---|
| Apart, generic Putin | 13.9 ms | 0 | 0 |
| Apart, compiled Putin | 8.4 ms | 0 | 0 |
| Overlapping, generic Putin | 22.2 ms | **33** (lines 234-266) | 0 |
| Overlapping, compiled Putin | 15.8 ms | 0 (no margin) | 0 |

Before the two-window schedule, both fighters were rebuilt after every
other tick: 22 ms, and Putin's lower half was caught every picture.

## Findings

1. **Single buffer + background mirror works.** There are no save buffers
   and no debris, and overlapping fighters restore correctly in any order.
   The mirror costs 12K of the &4000-&7FFF page.
2. **Each fighter gets its own frame.** At 25 fps there are two 15.6 ms
   windows per picture. Rebuilding one fighter in each is what made the
   generic drawer flicker-free.
3. **Per-line overhead dominates.** Restore spends ~53 µs per line before
   copying a byte, and the generic drawer ~56 µs. Compiled code spends
   ~12 µs per line.
4. **Compiled is 3.7× faster but 3.4× bigger** than the span data (~1.5 KB
   against ~450 bytes per frame). Every frame in both facings would be
   ~150 KB per character.
5. **The overlap case is the limit.** Both fighters in one window need
   compiled draws *and* a cheaper restore. A fighter jumping while they
   overlap (top at line 144, deadline 11.8 ms) doesn't fit yet.

## Gotchas found

- rasm's default v3 snapshot is packed, and `cpcemu` segfaults on it. The
  Makefile passes `-v2`.
- Inside the rebuild, SP walks `line_tab`. A single `push` there (even
  `push hl : pop iy`) overwrites a scanline address, and the next picture
  then writes to the wrong place. Steps chain through IY and never push.

## Next (milestone 2 work this feeds)

- Restore with a separate (s, n) table through the alternate registers
  (target ~40 µs per line). Skip bytes the new frame covers when a fighter
  hasn't moved.
- A runtime compiler: turn the current move's span frames into compiled
  code for the current facing, in a per-fighter cache.
- Rebuild the higher fighter first when they overlap, and move fighter data
  into banks 4-7 (paging between mirror and bank for restore and draw).
- Confirm on real hardware (CRTC types 0-2), as OverscanCPC did.
