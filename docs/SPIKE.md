# Milestone 1 — Tech Spike Results

Can two big puppet fighters be drawn on a full overscan Mode 0 screen at
25 fps with no flicker? Yes, in every case tested. That includes the worst
one: both fighters in the air and overlapping, which share one window. The
first pass worked when the fighters were apart but had almost no margin
when they overlapped. The follow-up (banded rebuild + restore lists, below)
covers overlaps and jumps with 2-3 ms to spare. The decisions are in
[GAME_PLAN.md §3](GAME_PLAN.md#3-technical-design).

![spike screen](spike_screen.png)

*Trump (compiled, facing right) and Putin (mirrored, facing left) idling and
swaying on a 192×272 overscan stage, captured from the emulated 6128.*

## What was built

| File | What it does |
|---|---|
| `src/main.asm` | boot and move down to &0200, 25 fps loop, two-window schedule, spike logic (idle animation, sway, jumps) |
| `src/rebuild.asm` | the banded scheduler: restore and draw jobs for both fighters, run band by band ahead of the beam; job set-up |
| `src/crtc.asm`, `src/irq.asm`, `src/video.asm` | overscan CRTC set-up, VSYNC-recognised frame tick, line table, stage, background mirror |
| `src/sprite.asm` | restore from a prepared restore list, the list builder, and the generic mirrored span drawer |
| `tools/sprite_codegen.py` | span streams, (s, n) tables, compiled routines with a yield every 8 lines (both facings), flip/mask tables |
| `tools/spike_bench.py` | runs the snapshot on the headless 6128 and measures it |

```bash
make                                    # build/pfspike.sna and build/pfspike.dsk (RUN"PFSPIKE)
make bench                              # measure on the headless 6128
make run                                # open in Caprice32
make bench-all                          # the three scenarios the 25 fps rule must hold in
make PUTIN_DRAW=compiled CLOSE_UP=1 JUMP=1   # variants, see the Makefile
make bench ... SLACK=20                 # margin test: start every rebuild 2 ms late
```

## How it was measured

`tools/spike_bench.py` drives floooh/chips' CPC 6128 (cycle-accurate Z80,
gate array and CRTC, real ROMs) through `~/repos/CPCTools/cpcemu`, 16 µs at
a time:

- **Phase timing.** The rebuild writes `bench_phase` at every step, so the
  time each value is held is the cost of that step.
- **Beam check.** As the beam starts each scanline of the fighter band, the
  bytes it is about to fetch are captured. Every frame is judged: if the
  bytes match neither the band at the frame's start nor at its end, that
  line was *caught* half drawn, which is visible flicker. Matching the start
  only is *late*: the line shows the previous picture for one frame.
- **Correctness.** The band is rebuilt in Python from the background mirror
  and the span streams in RAM, then compared with the screen byte for byte.
  Any difference is debris or a drawing bug.

## First pass results (60 pictures each)

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

- rasm divides in floating point and rounds, so `label/256` is the high
  byte only for page-aligned labels: &04F6/256 assembled as 5. Use
  `label>>8`.
- rasm doesn't export `-D` defines to the symbol file, even with `-sq`.
  `config.asm` copies the scenario switches into `SCN_*` EQUs for the bench.

## Follow-up: 25 fps in every case (banded rebuild)

25 fps is a hard rule ([GAME_PLAN §3.2b](GAME_PLAN.md#32b-frame-rate-locked-at-25-fps)),
so the overlap case had to fit with room to spare, jumps included.

**Banded rebuild** (`src/rebuild.asm`). The four steps of a shared window
(restore A, restore B, draw A, draw B) are jobs. The scheduler walks the
screen in 16-line bands, top to bottom, and runs every job as far as its
target in that band. Restores can stop on any line. Compiled draws yield
every 8 lines (the generator puts a `DEC IXL : JR NZ` checkpoint there). To
keep the per-line order, the targets are staggered: restores to
band + 16, draw A to band + 8, draw B to band + 0. Whatever line a job
touches has already been finished by every job that must come before it.
Lines are kept relative to the band's top line so all the bookkeeping is 8-bit.

**Restore lists.** The restore was twice the cost of a compiled draw, nearly
all of it per-line set-up (~53 µs). Now `prepare`, which runs in idle logic
time after each picture, turns each fighter's on-screen frame into a list
of (screen address, byte count) per scanline. Inside the window the
restore is `POP DE : POP BC`, mirror address, `LDIR`: ~17 µs per line. The
lists sit in unused tails of screen page 3 (&CCE0, &D4E0), next to
`line_tab` (&C4E0), so they cost no payload.

**Prepared jobs.** Job set-up also moved into `prepare`, so the rebuild
starts 32-80 µs after the tick instead of 300-700.

### Results (96 pictures, every frame judged)

| Step | First pass | Now |
|---|---|---|
| Restore Trump | 5.40 ms | 3.33 ms |
| Restore Putin | 5.13 ms | 2.78 ms |
| Compiled draw Trump / Putin | 2.83 / 2.36 ms | 2.93 / 2.44 ms (+8-line yields) |
| Scheduler overhead | — | ~1.3 ms per picture |

| Scenario | Latest window end | Lines caught | Lines late | Bytes wrong |
|---|---|---|---|---|
| Apart (two windows), generic Putin | 12.3 ms | 0 | 0 | 0 |
| Toe to toe (shared window), compiled | 12.6 ms | 0 | 0 | 0 |
| Toe to toe + jumps, compiled: Trump up | 13.1 ms | 0 | 0 | 0 |
| ... Putin up | 13.2 ms | 0 | 0 | 0 |
| ... **both up** (tops at line 144) | 12.8 ms | 0 | 0 | 0 |

**Margin.** `SLACK=n` starts every rebuild n×100 µs late. In the worst case
(both in the air, overlapping): 2.0 ms late is still clean, 3.0 ms late
catches 13 lines. Before the restore lists and prepared jobs, 0.5 ms late
already caught 29.

Banding alone wasn't enough. With the old restore, the both-up case caught
56 lines: everything sits in lines 144-207, which the beam has finished by
15.8 ms, and the work was ~17.5 ms. The cheaper restore is what made it fit.
Banding's job is ordering: every line is finished in top-to-bottom order,
whichever fighter is higher. The old fixed order (all restores, then all
draws) wasn't benchmarked with jumps, so this run doesn't show how much
margin banding adds on its own.

## Follow-up: raised floor

Every stage now keeps the bottom 60 lines as a raised floor, because RVM
cuts off the bottom of the overscan picture. The fighters moved 56 lines
up (feet on line 212, band 88-211), so the beam reaches them 3.6 ms sooner
after VSYNC. That would have eaten the whole margin.

Instead the rebuild now starts on the interrupt at line 222, the fifth
after VSYNC, just after the beam leaves the fighters. The head start to
their tops is 0.4 ms shorter than before (15.2 ms standing, 11.4 ms at the
top of a jump). Because the window now crosses VSYNC, the scheduler lets
interrupts in after every job and the generic drawer every 8 lines. No
stretch with them off is over ~1.3 ms, so the Gate Array keeps the
interrupt count exact.

The bench now keeps exact emulator time from boot. It fixes VSYNC from the
first tick after `irq_init`, finds the beam by arithmetic (the frame is
always 19968 µs), and judges each beam pass against the band at the start
of its rebuild and at the start of the next.

| Scenario | Rebuild ends with the beam on line | Lines caught | Late | Bytes wrong |
|---|---|---|---|---|
| Apart, generic Putin | 121 | 0 | 0 | 0 |
| Toe to toe, compiled | 120 | 0 | 0 | 0 |
| Toe to toe + jumps, worst state | 130 | 0 | 0 | 0 |

Margin in the both-jumping case: clean at `SLACK=15` (1.5 ms late), 26
lines caught at `SLACK=20`. That's 0.5 ms less than before the floor moved.

## Milestone 2 step 1: characters in the banks

Every frame of both characters (48 each, all 14 moves) now lives in the
extra 64K. Trump is in banks 4-5 and Putin in 6-7, each found through a
directory at &4000 of its first bank (GAME_PLAN §3.4). The engine payload
dropped from &38D5 to &10BE.

- **Fighter records.** Each fighter is an `F_*` record: position, facing,
  move and frame. `load_frame` fills in what the directory says about that
  frame, and the `F_O*` fields hold what is on the screen. The same
  `setup_fighter` serves both fighters.
- **Generic drawers for both facings** (`draw_r`, `draw_l`). They work in
  8-line chunks like the compiled draws, because span streams are now
  padded to whole chunks. They take their column in A from the job record,
  so either fighter can face either way.
- **Paging per job.** Each draw job carries the RAM configuration it runs
  in. Restores always run with #C0 (the mirror), with a constant `OUT`
  and no other loads. That's what won back the margin the paging had cost.
- **Disc.** Each bank is a file, and `PFSPIKE.BAS` pages it in and loads it.
  ASCII BASIC on a CPC disc needs CR LF line endings (`.gitattributes`
  keeps them).

Bench (every scanline pass judged, sprites read back from the banks):
0 lines caught, 0 late, 0 wrong bytes in all three scenarios, and
`SLACK=15` still clean in the both-jumping case.

## Next (milestone 2 work this feeds)

- A runtime compiler: turn the current move's span frames into compiled
  code for the current facing, in a per-fighter cache. Overlaps need both
  fighters compiled: the generic drawer alone is 8.7 ms.
- Input for two players and the fighter state machine (walk, crouch, jump,
  facing, walls). Close combat then needs the runtime compiler: only the
  idle frames have compiled draws today, and generic draws don't fit a
  shared window.
- Confirm on real hardware (CRTC types 0-2), as OverscanCPC did.
