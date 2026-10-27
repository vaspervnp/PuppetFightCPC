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

## Milestone 2 step 2: two players and the fighter state machine

`DEMO=0`, the default now, is the game. `DEMO=1` keeps the scripted sway
and jumps that `bench-all` measures.

- **Input** (`src/input.asm`). Scans the keyboard matrix through the PSG
  each picture (~0.1 ms) and maps it to a control byte per player:
  joystick 0, or the cursor keys with Space and Copy, for player 1;
  joystick 1, or W A S D with Z and X, for player 2.
- **State machine** (`src/fighter.asm`). The move is the state. Idle, walk
  and crouch are free: the controls choose the next move. Attacks play once
  and go back to idle (a sweep stays crouched while ↓ is held). A jump is a
  16-picture arc that can carry the fighter across, even over the opponent.
  Free fighters turn to face each other. Walls stop them, a walk stops
  10 bytes from a standing opponent, and `separate` pushes apart two that
  a landing left inside each other. Frames advance every 2 pictures.
- **Scripted play bench.** `make bench-play` presses keys on a script
  (`--keys RIGHT@2-26,x@40,...`, by picture number) and saves screenshots
  (`--shots`). The run walks Trump and Putin together, then has them punch,
  kick, crouch, sweep and uppercut, jump over each other and turn round.
- **Frames per picture.** The bench now also reports the frames between
  pictures. That exposed a frame drop the line check couldn't see: with
  the fighters apart, the set-up after a window took longer than the time
  left before the next tick (~3.5 ms per fighter against ~5.5 ms). Two
  changes fixed it. `build_restore` was rewritten (SP walks `line_tab` 16
  lines per interrupt-off stretch, one loop per facing, x patched into the
  code): ~2.8 ms. And `prebuild` runs it in the time between windows, into
  a second list per fighter: A's after the first window, B's after the
  second, before the logic. The set-up after the logic costs 0.6-1.1 ms.
  The keys are tested with straight-line code instead of a table loop
  (logic 2.1 → 1.3 ms).

| Scenario | Frames between pictures | Lines caught | Bytes wrong |
|---|---|---|---|
| Apart, generic Putin | 2 every time | 0 | 0 |
| Toe to toe, compiled | 2 every time | 0 | 0 |
| Toe to toe + jumps, compiled | 2 every time | 0 | 0 |
| Play script (close combat, generic draws) | 2, except one picture: 3 | 57 lines in 1,559 line passes | 0 |

Margin in the both-jumping case: clean at `SLACK=14`, one line caught in
one picture at `SLACK=15`. The committed engine dropped two frames at
`SLACK=15`, which hid it.

Close combat in the game still flickers. Only the idle frames have
compiled draws, and two generic draws (~8.5 + 7.5 ms) don't fit a shared
window. That's the runtime compiler's job.

## Milestone 2 step 3: runtime compiler (in progress)

Every frame is now drawn by compiled code, compiled at run time
(`src/jit.asm`). With both fighters compiled, a single window always fits,
so the two-window "apart" mode, the generic drawers and the precompiled
idle frames are gone.

- **Compiler.** Reads the span stream and writes, per line,
  `pop hl : add hl,de : ld bc,col : add hl,bc`, then one store per byte, with
  a yield every 8 lines. Facing left, the line starts at column w − 1 − s and
  steps left (`dec hl`), with each byte through `flip_tab`, so both facings
  read the bytes in the same order. Span streams are escaped: an opaque byte
  is itself, and a hole or a byte with a pen 0 pixel is 0 then the byte, so
  the common case costs one test. The compiler also writes each frame's
  (s, n) table for `build_restore`, so the banks no longer carry them.
- **Cache.** Trump has 4 slots in main RAM and Putin 2 (1,872 bytes each,
  &1420-&3FFF). On top of those, each character has the slots its directory
  puts at the top of bank 1: 3 for Trump, 5 for Putin. A bank slot only
  takes frames whose spans are in bank 1, because the compiler reads and
  writes with that one bank paged in. So `sprite_codegen.py` puts the moves
  a fight shows most (idle, walk, crouch, jump, punch, and kick for Trump)
  in bank 1, and as many slots as fit above them. The idle and walk loops
  (4 frames each) now stay cached. Slot tables sit at &C700, the (s, n)
  tables in the tails of screen slices 2, 5 and 7, and `flip_tab` /
  `mask_tab` are built at boot in slice 1's tail. That frees 512 bytes of
  payload, enough for Trump's fourth main slot.
- **Scheduling.** `load_frame` takes the logic's frame from the cache. On a
  miss the fighter keeps the frame it shows, and the frame is marked as
  wanted. After `prepare`, `jit_work` compiles wanted frames first, then
  each fighter's likely next frame. Before every line, the compiler checks
  whether it has reached the last interrupt period before the tick. If so,
  it stops and carries on in the next picture, so a picture is never late.
- **Restore lists are kept** when a fighter shows the same frame in the
  same place: 5.4 → 3.2 ms per picture in play.

| Scenario | Frames between pictures | Lines caught | Pictures with a held frame (Trump / Putin, of 96) |
|---|---|---|---|
| Apart | 2 every time | 0 | 0 / 0 |
| Toe to toe | 2 every time | 0 | 0 / 0 |
| Toe to toe + jumps | 2 every time | 0 | 0 / 0 |
| Play script (close combat) | 2 every time | 0 | 52 / 23 |

Margin: `SLACK=15` is clean again in the both-jumping case.

**What's left.** In the play script the compiler is busy almost all the
time. It changes move every few pictures, and every new move or turn needs
3-4 frames at 13-17 ms each, about one frame per picture. Fighters hold a
frame while they wait, mostly at the start of a move and after a turn.

A `PUSH` compiler doesn't help. An opaque byte's code is 3 bytes
(`36 b 23`), so pushes need extra register loads or an `inc sp`: about
23 µs per byte against 24 now. `LDI`/`LDIR` drawing from the span data
would make compiling cheap, but on the CPC `LDIR` costs 6 µs a byte
against 5 for `ld (hl),n : inc hl`. Facing left also needs flipped data.

### Improvements

- **The draw walks the new frame's restore list.** A restore list already
  holds, per line, the screen address of the frame's leftmost byte and its
  byte count. It is now built in `prepare` for the frame about to be drawn,
  not after the window for the one just drawn. The draw job's SP walks it,
  and the next picture restores from the same list. A compiled line starts
  `pop hl : pop af` facing right, or `pop hl : pop bc : add hl,bc` facing
  left, where each byte is then `dec hl` and its store. Before, a line
  started `pop hl : add hl,de : ld bc,col : add hl,bc`. The largest frame
  shrank from 1,871 to 1,740 bytes, so slots are now 1,744 bytes and Putin
  gets a sixth bank slot. Draws are ~0.35 ms faster per fighter, and the
  separate restore-list step after the window is gone.
- **Fighters that don't change are left alone.** If a fighter shows the
  same frame in the same place and the other fighter's old and new boxes
  don't reach it, neither its restore nor its draw runs.

| Play script | Before | Now |
|---|---|---|
| Compile per frame | 17.4 ms | 16.0 ms |
| Frames compiled | 80 | 67 |
| Pictures with a held frame (Trump / Putin) | 52 / 23 | 32 / 30 |
| Latest window end, fighters standing (DEMO) | line 124 | line 116 |

The DEMO scenarios still show 2 frames between every pair of pictures,
0 lines caught and no held frames. `SLACK=15` is clean, and at `SLACK=20`
2 lines are caught (it was 26 before the raised floor).

- **Any frame into any slot.** A frame from bank 0 can now go into a
  bank 1 slot. It is copied to a 600-byte buffer after the payload first
  (~3.5 ms, started only with two interrupt periods to spare). Its stream
  size is in the frame record. This stopped Putin's kick (bank 0, three
  frames) from recompiling in his two main RAM slots every time: Putin's
  held pictures fell from 30 to 21. Trump's rose from 32 to 42, so the
  total is about the same.

Where the held frames in the play script come from now: the first time a
move or a facing is used (walk at the start, both fighters turning after
the jump-over, a first kick or uppercut), and Trump's idle after walking.
His idle and walk loops are 8 frames and he has 7 slots. In other words,
the compiler's speed (about one frame per picture) against a burst of 3-8
new frames.

- **Guesses when there's nothing certain to compile.** With no wanted
  frame and both next frames cached, `jit_work` compiles the first frame of
  a move a fighter may start next: walk, punch, kick, crouch, jump in its
  facing, then idle in the other facing (a turn). A guess only takes a slot
  that is empty or hasn't been used for 96 cache uses, and is stamped as
  old, so it is the first to go if nothing uses it. Looking for one costs
  time (a find per move), so it only happens with two interrupt periods to
  spare. Most guesses are compiled at the start of a round, while the
  fighters stand idle.

| Play script | No guesses | With guesses |
|---|---|---|
| Pictures with a held frame (Trump / Putin) | 42 / 21 | 16 / 18 |
| Frames compiled | 66 | 47 |

What's left in the compiler is the byte loop itself: ~24 µs per opaque
byte facing right and ~29 facing left (read, test, two stores and a step,
count). The remaining tweaks (`exx` for the (s, n) pointer, the mask
worked out instead of looked up) are worth ~5%.

## Milestone 3 step 1: hits, blocks, damage, KO

- **Boxes.** Frame records are now 16 bytes. `sprite_codegen.py` adds each
  frame's hurt box (the bounding box of its pixels) and, for an attack's
  hitting frame, its hit box. Hit boxes come from
  `art/sprites/<char>_hits.json`, written by hand from the frames (the
  frame that hits and a pixel rectangle facing right). Working them out
  from the silhouettes didn't hold up: whole bodies lean into punches, and
  kicks don't reach past the idle outline.
- **Combat** (`fighter.asm`, after `separate`, on the logic's frames, so a
  frame held for the compiler doesn't change the fight). An attack lands
  once, when its hit box meets the opponent's hurt box (facing left the
  boxes mirror). A fighter holding back while free or blocking blocks it:
  1 byte of pushback, no damage. Otherwise the defender takes damage
  (punch 4, kick 5, sweep 4, uppercut 6, back kick 6, of 40), plays the hit
  reaction, is knocked back 3 bytes (out of a jump too), and at 0 is down
  for good (KO, last frame held).
- **Blocking.** Holding back while the opponent attacks stops a walk and
  holds the block pose.
- **Health bars.** The lost part of a bar is blanked from the middle of
  the screen outwards, during the logic, while the beam is below the HUD.
- **Memory.** The workspace and the fighter records moved to the unused
  tail of screen slice 3 (&DDE0-&DECF), and `start` sets them up. That
  leaves room under the cache for the copy buffer: the payload ends at
  &14AC, with 28 bytes to spare.
- **Bench.** Keys now change at `prepare`, so a one-picture press can't
  fall between two reads of the keyboard (some presses were being lost).
  `make bench-fight` plays a short fight: Trump lands a punch, Putin walks
  in and lands one, Trump blocks a kick and lands another. It ends at
  Trump 36, Putin 32, with 2 frames per picture and 0 lines caught.

## Milestone 3 step 2: crouch block, reach, rounds

- **Blocks.** Holding back blocks while standing (free or in the block
  pose) or crouching. A standing block stops everything but the sweep,
  which is low. A crouching block stops everything.
- **Reach.** At the closest the fighters can stand (10 bytes apart), their
  bodies just touch, so a hit box exactly over the drawn limb could stay
  inside the attacker's own outline (Putin's sweep did). Hit boxes now reach
  2 bytes past the limb (`HIT_REACH` in `sprite_codegen.py`).
- **Rounds** (`round.asm`). A KO ends the round. The winner holds its
  victory pose for 3 seconds, and nobody can move. Then the winner gets a
  white marker under its bar, both fighters start again at full health
  with full bars, and 2 round wins take the match. The next match starts
  with no markers.
- **Cold code.** Combat and rounds run once a picture in the logic, never
  in the window. They now live in the unused tails of screen slices 4 and 6
  (&E5E0, &F5E0), copied there by `boot` from the file, so main RAM stays
  free for the engine and the frame caches. The payload ends at &1343.

Checked on the emulator, with keys scripted per picture:

| Test | Result |
|---|---|
| Putin punches a standing Trump who holds back | blocked: 1 byte pushback, no damage |
| Putin sweeps a standing Trump who holds back | hit: −4, 3 bytes knockback |
| Putin sweeps a crouching Trump who holds back | blocked |
| Putin's health set to 4, Trump punches, twice | KO and victory pose; round to Trump with a marker after 75 pictures; second KO, then a new match with no markers |

`make bench-all`, `bench-fight` and `bench-play` still show 2 frames
between pictures and 0 lines caught, and `SLACK=15` is clean.

## Milestone 3 step 3: clock, motion history, hitstun

- **Clock** (`round.asm`). 99 seconds a round, in BCD, as two 3 × 5 pixel
  digits between the bars, 3 lines a pixel row. It is drawn only when a
  second passes, in the logic, while the beam is below the HUD. At 0 the
  fighter with more health wins the round, in its victory pose, as after a
  KO. With the same health it is a draw: no marker, and the round starts
  again.
- **Motion history** (`fighter.asm`). Every picture the stick goes in front
  of a 12-picture history (0.48 s), turned to the fighter's facing (up,
  down, back, forward). A motion is a list of steps, newest first, each a
  mask and a value, and it matches when the history shows the steps in
  order, each in an older picture than the one before. Motions:
  - special: ↓, ↘, → with either button. The history is cleared once it
    fires, so the next press is a plain attack.
  - uppercut: ↓ then ↑ + punch, so it can come out of standing as an
    anti-air. ↓ + punch still works.
- **Special.** Both characters already had `special` frames (move 12).
  Until milestone 5 makes them Trump's tweet storm and Putin's throw, they
  are a strong strike: 8 damage, hit boxes in the `_hits.json` sidecars.
- **Hitstun and blockstun.** A hit now holds the hit reaction for the
  attack's hitstun, in pictures: punch 6, kick 8, sweep 10, uppercut 12,
  back kick 10, special 14. The reaction's own frames take 6. A punch
  leaves the attacker 2 pictures ahead, but not enough for a second punch
  to land before the defender recovers. A heavier move gives more. A
  standing block holds at least 4 pictures (`BLOCK_STUN`), even if back is
  let go.
- **Memory.** Each fighter record grows by 13 bytes (`F_STUN`, `F_HIST`).
  The clock sits in the second cold block (81 bytes left). The payload
  ends at &13FB, leaving ~800 bytes before the caches with the staging
  buffer.

Checked on the emulator with keys and pokes per picture:

| Test | Result |
|---|---|
| Trump ↓ ↘ → + punch, up close | special, Putin −8, 14 pictures of hitstun |
| Putin ↓ ↙ ← + punch | special |
| Trump ↓, then ↑ + punch | uppercut (↑ alone: a jump) |
| Putin punches Trump | −4, 6 pictures of hitstun |
| Trump blocks, lets go of back during the punch | block held 4 pictures after it lands |
| Clock set to 1 s, Putin on less health | time-out: Trump's victory pose, his marker, a new round at 99 |
| Clock set to 1 s, health level | draw: no marker, a new round at 99 |

A bench with both specials landing (−8 each) and the motion uppercut, and
`make bench-all`, `bench-fight`, `bench-play` and `SLACK=15`, all show
2 frames between pictures, 0 lines caught and 0 bytes wrong.

## Milestone 3 step 4: knockdown

The sweep, the uppercut, the special, and any hit on a fighter in the air
knock it down instead of a hit reaction. In the `hitstun` table, 0 marks a
knockdown move.

A knockdown is the KO move with health left, and it lasts `KD_PICS` (36)
pictures:
- the KO frames play as a fall, then the last one holds while the fighter
  lies there;
- in the last 8 pictures it gets up on the same frames backwards, 2
  pictures a frame;
- then it is idle, turned to face the opponent.

Nothing hits a fighter that is down or getting up, and its controls do
nothing until it is up. A round ends only on a KO with no health left
(`rt_out`).

Checked on the emulator:

| Test | Result |
|---|---|
| Trump's uppercut on a standing Putin | −6, down 36 pictures, gets up, idle |
| Trump's punch on Putin coming down from a jump | −4, knocked down |
| Trump punches Putin from in range while he is down | no hit |
| Uppercut on Putin with 4 health | KO, round to Trump, new round with both up |

A bench with the uppercut knockdown and a hit in the air, and `make
bench-all`, `bench-fight`, `bench-play` and `SLACK=15`, show 2 frames
between pictures, 0 lines caught and 0 bytes wrong. That completes
milestone 3.

## Milestone 4: characters from the disc

**Palette** (GAME_PLAN 3.3). The pens now follow the plan:
- 0 is the background black.
- 1-5 are shared fighter pens: outline black, white, navy, dark red, grey.
- 6-9 are fighter A's own colours, and 10-13 are fighter B's.
- 14-15 belong to the stage: pastel blue and green.

The art keeps its old pens. `sprite_codegen.py` turns them into game pens
through each character's `art/sprites/<char>_pfc.json`, which holds:
- its name and select-screen title;
- its 4 own colours, the first of which is also its health bar;
- 4 more colours for the second fighter in a mirror match;
- merges for art colours that are neither shared nor its own.

Trump had 5 colours of his own, so his tie goes from bright red to dark red
and the pastel highlights merge into bright yellow and white. Putin needs 3.
The directory carries the inks of the character's colours (version 3,
`DIR_INKS` &4007, so the moves move to &400B). `start` copies each
fighter's inks into pens 6-9 and 10-13. The stage and HUD were redrawn in
the stage pens and the shared pens: sky, haze, grass, floor, white clock
and markers, each health bar in its fighter's first colour.

**Character files** (`make` → `build/pfc/NAME.PFC`, GAME_PLAN 3.5). Each is a
64-byte header followed by bank 0 and bank 1, made for fighter A's pens. The
header holds:
- "PFC" and the version;
- the name, and the title as two lines of 12 characters;
- the two sets of 4 inks;
- the two bank lengths.

`ROSTER.TXT` lists the names. Trump's file is 26.8 KB and Putin's 22.2 KB.

**Select screen and loader** (`src/loader.asm`, `PFLOAD.BIN` at &8000).
`PFSPIKE.BAS` loads and calls it, then loads the engine as before.
1. It runs under the firmware in mode 0. It reads the roster and every
   header, and shows each player a name and title.
2. Each player picks with left/right and fire. Player 1 uses the cursor
   keys, Space or Copy, or joystick 0. Player 2 uses A, D, Z or X, or
   joystick 1.
3. Fighter A's file goes into banks 4-5 and fighter B's into banks 6-7, read
   a byte at a time with `CAS IN CHAR`, so a bank is paged in at #4000 while
   it fills.
4. Fighter B's frames are then walked through the directory, and every
   pixel byte goes through `remap_tab` to move pens 6-9 to 10-13. The
   escaping never changes, because it only depends on which pixels are
   pen 0.
5. In a mirror match, B's directory gets the second set of inks.

AMSDOS reports every &1A byte as a soft end of file, even in a binary file,
so the loader treats &1A as data and stops only at the hard end.

**Cache split.** `start` now splits the 6 main-RAM cache slots from the two
directories, so that both fighters have about as many slots in all:
- Trump against Putin gets 4 + 3 and 2 + 6, as before.
- Putin against Putin gets 3 + 6 each.
- Trump against Trump gets 3 + 3 each.

A character has at most 6 slots in bank 1, so the (s, n) tables (18) and
`MAX_SLOTS` 9 always fit.

**Snapshot.** `make CHAR_A=putin CHAR_B=putin` builds the snapshot (and the
benches) with any pair. B's banks are made with `--side b`, which gives the
same bytes the loader's remap does.

Checked on the emulator, from the disc (`RUN"PFSPIKE`, keys typed):

| Test | Result |
|---|---|
| Select screen | both rosters' names and titles, READY per player |
| Trump against Putin | loads in ~40 s of emulated time; all four banks match the snapshot byte for byte; the fight starts |
| Putin against Putin | B in the second colours (orange); its banks match apart from the 2 changed inks |

`make bench-all`, `bench-fight`, `bench-play` and `SLACK=15`, and
`bench-all`, `bench-play` and `bench-fight` for Putin against Putin, Trump
against Trump and Putin against Trump, all show 2 frames between pictures,
0 lines caught or late and 0 bytes wrong. Held frames in `bench-play` stay
between 25 and 42 fighter-pictures of 192, depending on the pair.

The payload ends at &148F, 57 bytes below the frame caches with the staging
buffer, so new engine code from here needs room found first.

## Milestone 5: specials and projectiles

**Room first.** The payload was 57 bytes short of the frame caches. The
background mirror only uses #x000-#x23F and #x440-#x7FF of each 2 KB slice
of #4000-#7FFF, so the gaps #x240-#x43F (512 bytes each) are free whenever
main RAM is at #4000. Boot copies the logic into the four gaps above the
load image (#6240, #6A40, #7240, #7A40):
- `fighter.asm` (`think`)
- `moves.asm` (its helpers, split out of it)
- `input.asm` and `shotvis.asm`
- `special.asm`

Code there must never run with a character's bank paged in, so
`move_frames` (which pages one) stays in main RAM. The move constants moved
into `main.asm`. The payload then ended at &1211, 695 bytes below the caches
with the staging buffer.

**Specials.** Directory version 4 adds the special's kind (strike,
projectile, throw) and a projectile record. Settings live in
`<char>_pfc.json` `special`:
- **Trump: Tweet Storm.** Frame 2 of the special fires a tweet bird
  (12×9 pixels: 6 bytes, 9 lines, pastel blue, white and navy) from the
  front of the hit box. It flies 3 bytes a picture, does 6 damage and 10
  hitstun, and can be blocked for 1 point of chip damage (never the last
  point). It passes over a fighter who is down. It is gone at the screen
  edge, on a hit, or when it meets the other fighter's tweet. Only one flies
  per fighter.
- **Putin: Judo Throw.** Frame 1 of the special grabs an opponent on the
  ground within the hit box. The opponent lands behind Putin with a
  knockdown and 10 damage. A throw can't be blocked. Pressing back just as
  it lands breaks it and the two come apart: back has to be in the newest
  picture of the motion history but missing from one of the two before it.
  Holding back (a block) is too late.

The projectile's code is compiled by `sprite_codegen.py` into bank 0, for
both facings. It may only use the shared pens and the stage's, so the loader
never has to remap it.

**Drawing projectiles outside the rebuild.** The first version drew them
with two jobs each in the banded rebuild. Each restore takes ~0.65 ms and
each draw ~0.35 ms. In the hardest case (Trump against Trump, both jumping
toe to toe) the rebuild already uses the whole window, and two projectiles
caught 10-17 lines, however the jobs were ordered. Now:
- `shot_vis` (at the start of `prepare`) shows a projectile in the next pass
  only if it meets neither fighter's drawn box (the frame's hurt box, from
  its record), on the screen or next.
- `shot_pass` takes the shown ones off and draws the allowed ones, once
  between pictures. It runs only while the beam is clear of the lines they
  can be on (`SHOT_TOP` 160 to the floor), from interrupt 5 to interrupt 3.
  `jit_work`, the compiler (once a line, through `jc_flag`, which the
  interrupt handler raises) and `wait_render` call it.

So a projectile and a fighter never share a byte, and the rebuild doesn't
change at all. A projectile is out of sight while it overlaps a fighter: for
the opponent that is the picture it hits, and at the throw it shows one
picture after leaving the hand.

The bench treats the pass as an epoch boundary like a rebuild. It counts
passes not done by the next rebuild, and its correctness check includes
the projectiles. `SHOTS=1` (with `DEMO=1`) sweeps both fighters'
projectiles across the screen. `bench-all` now has the both-jumping
scenario with two projectiles (Trump against Trump).

| Bench | Result |
|---|---|
| `bench-all` (4 scenarios, incl. two projectiles over both jumping) | 2 frames between pictures, 0 caught, 0 late, 0 passes missed, 0 bytes wrong |
| `SLACK=15`, both jumping | clean (latest line 150) |
| `bench-fight`, `bench-play`; fight for every pair | clean; fight ends A 36, B 32 as before |
| traces: tweet hits, tweets cancel, throw, escape, both sides and facings | as designed, 0 caught, 0 bytes wrong |
| disc boot, Trump against Putin | all four banks match the snapshot byte for byte |

Costs:
- Rebuilds end 1-2 lines later, from the interrupt handler's few extra
  instructions.
- The compiler is 0.1 ms slower per frame.
- Held frames in `bench-fight` are 23 + 21 against 21 + 19, from ~0.15 ms
  more logic.

Trump against Trump with `SLACK=15` catches lines, but it did so before
this milestone too, line for line: that pairing simply has no 1.5 ms
margin.

## Milestone 6 step 1: stages

Two stages replace the spike's sky and pillars. Each is a picture that
`tools/stage_art.py` draws in code (192 × 272, `art/stages/<stage>.png`):
- **The White House lawn:** sky and clouds, the North Portico with its flag,
  trees, a mowed lawn, a black iron fence across the fighters' band, and a
  podium with bunting and a seal as the raised floor.
- **A Kremlin hall:** red damask walls between gold pilasters, arched
  windows, a chandelier, a marble floor behind the fighters, and a carpeted
  dais with a band of gold lozenges.

A stage uses the shared pens 1-5 and three of its own: pens 0, 14 and 15.
Pen 14 stays pastel blue for the tweet. The HUD (lines 0-23) is pen 1 on
every stage. So the bars, the clock's background and the win markers now
blank to pen 1, not pen 0.

**Packing.** `tools/stage_pack.py` turns the picture into the screen's 32 KB
as it is in memory, the unused tails as zeros. It packs that with a small
LZ: literal runs, (length, offset word) matches, and an end byte. It checks
the result with a Python copy of the unpacker. The White House packs to
2,437 bytes, the Kremlin to 1,727 (room: 8 KB). A `.STG` file holds "ST",
version, the hardware inks of pens 0, 14 and 15, the packed length, then the
data.

**Loading.**
- A character's `_pfc.json` names its home stage, and the `.PFC` header
  carries the stage's file name (offset 48).
- After the characters, the select screen loads fighter B's home stage to
  &2000. `PFSPIKE.BAS` now sets `MEMORY &1FFF`.
- Boot blacks every ink and unpacks the stage into &8000-&FFFF before it
  moves anything there. The 30-byte unpacker sits in the load image, not the
  payload. Then it copies the payload and cold code, and the stage's inks
  into the palette.
- `start` draws only the bars over the stage, then copies the mirror as
  before.
- For the snapshot, `make STAGE=...` (fighter B's home stage by default)
  puts the packed stage at &2000.

The old stage drawing is gone, so the payload ends at &118E.

| Test | Result |
|---|---|
| `bench-all`, `bench-fight`, `bench-play`, `SLACK=15` (Kremlin) | 2 frames between pictures, 0 caught, 0 late, 0 passes missed, 0 bytes wrong; fight ends A 36, B 32 |
| `bench` Putin against Trump (White House) | the same |
| disc: Trump against Putin | the Kremlin; all four banks match the snapshot |
| disc: Trump against Trump | the White House, B in the second colours |

## Milestone 6 step 2: victory screen and title screen

**Victory screen** (`src/victory.asm`, in a fifth mirror gap at &5240).
1. When a round win takes the match, the HUD is cleared to black.
2. Two lines take its place: "TRUMP WINS!" in the winner's first colour,
   then its taunt in white.
3. The winner holds its victory pose for 8 s (`VICTORY_PICS` 200).
4. The HUD comes back (bars, clock, no markers) and the next match starts.

Details:
- `rnd_state` 2 is the victory, and nobody moves during it.
- Text is a 3 × 5 font like the clock's: 59 characters from space to Z,
  2 bytes each. It is drawn 2 lines a pixel row, centred, at lines 2 and 13.
- The lines come from the character file. Directory version 5 adds a
  pointer to them, written by `sprite_codegen.py` from `name` and `taunt` in
  `_pfc.json` (24 characters at most, checked against the font). `start`
  copies both fighters' lines into the workspace.
  - Trump: "YOU'RE FIRED! SAD!"
  - Putin: "DA. TOO EASY, COMRADE."
- Boot copies the fifth gap last. It lies inside the load image, but below
  everything copied from it.
- Choosing other characters still means starting again from the disc,
  because the firmware is gone once the engine runs.

**Title screen** (`tools/title_art.py`, `TITLE.SCR`).
- A firmware Mode 0 screen: "PUPPET FIGHT" in a 5 × 7 font, Trump and
  Putin facing each other with "VS", and "PRESS FIRE".
- It uses the game's pens with both fighters' own colours. Packed like a
  stage, it is 2,192 bytes, with its 16 firmware colours in front.
- The loader reads it to &9800 and unpacks it into &C000 first. It stays up
  while the roster and the headers are read, and either player's fire moves
  on to the select screen. Without the file the loader goes straight on.

| Test | Result |
|---|---|
| match to the end (Putin's health set to 1, two tweets) | round, round, victory screen at picture 226, the next match at 426 with the HUD back; 0 caught, 0 bytes wrong |
| the same for Putin (two throws) | "PUTIN WINS!" in his pink and his taunt |
| disc: title, fire, select, load | as designed; all four banks match the snapshot |
| `bench-all`, `bench-fight`, `bench-play`, `SLACK=15` | 2 frames between pictures, 0 caught, 0 late, 0 bytes wrong; fight ends A 36, B 32 |

## Milestone 6 step 3: music and sound effects

**Where it runs.** The player (`src/sound.asm`) runs in the handler of
interrupt 4 (`SOUND_IRQ`, line ~168), 50 times a second. That interrupt never
meets the rebuild, which ends by line 151 at the latest (`SLACK=15`). In the
frame before a picture's tick, the compiler has already stopped by then, so
there the time is free. In the other frame it comes out of the compiler's
time. A character's bank may be paged in at &4000 when the interrupt
arrives, so the player and all its data are in the payload. `read_controls`
keeps interrupts off (~100 µs) while the PSG's port A is turned round to
read the keys. The player only writes registers 0-10, and its mixer keeps
port A an input.

**The player** is our own, not Arkos. An AKG player plus its data would not
fit beside the engine, and its time per call varies too much.
- Three channels, each an order list of patterns: notes (C1-B6), rests,
  durations in rows, instrument changes. Rows come every `song_speed`
  interrupts.
- An instrument is a noise period, then one step per interrupt: volume,
  noise on, tone off, an octave up. Its last step holds.
- Sound effects play on channel C over the drums: a tone period that sweeps,
  a volume that decays, optional noise, and an optional restart (two chirps
  for the tweet). A higher number wins over a lower one. The game asks for
  one with `sfx_play`, a one-byte request the interrupt picks up.
- The register values are built in a buffer, and only the ones that changed
  are written, each followed in the buffer by what was last written.
- 762 bytes of code (the hot parts are unrolled per channel and per
  register), 670 bytes of data. `sound_init`, `music_play`, `music_stop` and
  `sfx_play` run from the game's logic, so they live in a mirror gap
  (`soundctl.asm`).

**The music** (`tools/music.py` → `src/gen/music.asm`). The songs are
written in the script as text, a pattern per string, and the script checks
that the three channels' order lists are the same length row for row.
- The fight: an original tune in D minor at 150 bpm. Two bars of drums and
  bass, then sixteen bars round and round (i–VI–VII–V twice, then
  iv–i–VI–V). Lead, octave-bouncing bass, and kick/snare/hat drums.
- The victory: a two-bar fanfare in D, then quiet.

**Sound effects**, and where they come from:

| Sound | When |
|---|---|
| swing | an attack starts (`start_move`) |
| block | an attack is blocked, standing or crouching |
| tweet | Trump's tweet flies |
| hit | an attack lands (`land_hit`), the tweet and the throw too |
| throw | Putin's throw lands |
| bell | the first round, and every round after it |
| KO | a hit takes the last of the health |

At the end of a match the music changes to the fanfare, and back to the
fight's music for the rematch.

**Making room.** The payload needs ~1.4 KB for the player and its data:
- `logic` and the boot-only routines that don't page a bank in (`irq_init`,
  `wait_vsync`, `build_line_tab`, `copy_mirror`) went to mirror gap &4240
  (`logic.asm`, `boot.asm`).
- `start`, `cache_split`, `make_tables`, `clear_lists` and the sound calls
  went to gap &4A40 (`start.asm`, `soundctl.asm`). Boot copies both gaps
  last, like &5240.
- `jit_init` stays in the payload: it pages a bank in itself.
- The payload ends at &14AB (room to &14C8), the load image at &61FC (room
  to &6240), the workspace at &DFDE.
- One mirror gap is left, &5A40.

**Hearing it.** The headless 6128 (`~/repos/CPCTools/cpcemu`) now keeps the
AY's output on request (`audio_capture`, `audio_take`, `psg_reg`).
`tools/sound_check.py` plays the snapshot with a key script and pokes,
writes `build/sound.wav`, and first times `sound_tick` from the program
counter:

| `sound_tick` | Time |
|---|---|
| a row of music due in all three channels (the worst) | 1.24-1.54 ms |
| mean over three seconds | ~0.5 ms |
| music off, nothing playing | 40 µs |

The worst case ends long before the tick at line 222.

| Test | Result |
|---|---|
| `bench-all`, `bench-play`, `SLACK=15` (latest line 151) | 2 frames between pictures, 0 caught, 0 late, 0 passes missed, 0 bytes wrong |
| `bench-fight` | the same; the fight ends A 36, B 32 |
| pictures with a held frame, sound on against off | fight 24 / 24 against 22 / 21, play 20 / 22 against 18 / 19 |
| the AY's notes, decoded from its registers | the lead, bass and drums as written |
| a fight to the end (`sound_check.py`) | bell, swing, hit, block, tweet, throw, KO, the fanfare on the victory screen, and the bell and fight music again on the rematch |
| disc: title, select, load | all four banks match the snapshot; the music plays |

## Milestone 7: the computer as an opponent

**Memory first.**
- The load image could not pass &6240: boot copied the gaps' code from the
  image to the gaps, and the first of them would have landed on code not
  copied yet.
- Now boot copies all the gaps' code first to `GAP_SCRATCH` (&2000). That is
  where the packed stage was, and boot has unpacked it by then. Each gap
  then gets its code from there.
- The image may now reach &8000 (the stage is unpacked over the screen
  first). It ends at &6435.
- The last mirror gap, &5A40, holds the AI (`ai.asm`, 504 of 512 bytes).

**Settings.** One byte at `SETTINGS_AT` (&3FF0), after the stage's room
(now 8,176 bytes):
- bit 0: the computer plays A;
- bit 1: it plays B;
- bits 2-3: its level (0 easy, 1 normal, 2 hard).

The select screen writes it, and `start` reads it into `game_mode` before
the compiled frame caches cover that area. For the snapshot, `make CPU=n
LEVEL=n` sets it (`CPU=3` is the computer against itself).

**Select screen.**
- C changes player 2: a player, then the computer at easy, normal and hard,
  then back to a player.
- Player 2's label shows which. When the computer plays, player 1 chooses
  their own character, and once ready, the computer's as well.

**The AI** (`src/ai.asm`).
- After the keys are read, `ai_players` replaces the controls of each
  fighter the computer plays. It makes the same CT_ bits a player would, so
  the rest of the game can't tell.
- The controls are worked out as if the fighter faced right, then turned.
- A button is pressed for one picture only, so the next attack is a new
  press.
- The special's motion (down, down-forward, forward + punch) takes three
  pictures (`F_AISEQ`).

What it does, in order:
1. A projectile coming within 24 bytes: block it low, or jump it.
2. An attack within 16 bytes: block, low with the level's chance (low
   blocks everything). Once blocking, it keeps blocking while attacks keep
   coming: only the first reaction is a matter of chance.
3. Someone jumping in close: an uppercut, or step back.
4. At contact (11 bytes or less, where every attack lands): a random mix of
   punch, kick, sweep, uppercut, back kick, and the special if it is a
   strike or a throw.
5. At 12-13 bytes: a punch (the only attack that reaches), or step in.
6. From afar: walk in, now and then a jump in or a step back. A character
   with a projectile fires it from 20 bytes or more, if none of its own is
   flying.

When it looks again:
- Every `L_REACT` + random(`L_JITTER`) pictures.
- Sooner when an attack comes: within `L_REACT`.
- At once when it is free after a hit or a knockdown. Without this, it kept
  a choice from before the hit and walked into the next punch.

| Level | Pictures between looks | Block | Low | Uppercut | Attack | Fire |
|---|---|---|---|---|---|---|
| easy | 4 + 0-7 | 47% | 16% | 27% | 51% | 20% |
| normal | 2 + 0-3 | 74% | 59% | 59% | 70% | 35% |
| hard | 1 + 0-1 | 88% | 92% | 82% | 86% | 55% |

The dice are a 16-bit xorshift. They aren't stirred with the refresh
register: that depended on timing, so every change to the code changed the
fight in the bench.

**Reach** was measured in the emulator, as bytes between the two box x's at
which each move lands, for both characters: the punch reaches up to 13,
everything else up to 10-11. (The two can't come closer than 10.)

**Results** (scripts driving the keys in the emulator, 200 s each). "Rush"
walks in and punches every 6 pictures at 12 bytes or less. "Mash" walks in
all the time and punches every 4 pictures.

| Computer | Against rush (player : computer) | Against mash |
|---|---|---|
| easy | 11 : 2 | 1 : 0 (it blocks, mash can't get through, rounds run long) |
| normal | 0 : 13 | 1 : 8 |
| hard | 0 : 15 | 0 : 13 |

Computer against computer at hard: Putin against Putin 7 : 4, Trump against
Putin 8 : 3 (the tweet).

**Two engine fixes the computer found.**
- **Trades.** When both attacks landed in the same picture, `combat` always
  took A's first. B was hit and its attack never counted, so A won every
  trade: 12 : 0 computer against computer, whoever played A. Now the order
  changes every picture.
- **Interrupts in the rebuild.** A fighter lying down is wide, and its
  restore took 1.7 ms in one band. The two restores ran back to back with
  interrupts off (2.5 ms), the VSYNC interrupt was taken 44 lines late, and
  the Gate Array moved the rest of the frame's interrupts. The tick then
  came at line 260, and pictures took 3 frames (4 in 600 pictures of the
  computer against itself). Now each restore lets interrupts in after it.
  The same 600 pictures are all 2 frames.

| Test | Result |
|---|---|
| `bench-all`, `bench-fight`, `bench-play`, `SLACK=15` | 2 frames between pictures, 0 caught, 0 late, 0 passes missed, 0 bytes wrong; the fight ends A 36, B 32 |
| `bench-ai` (new: `CPU=3 LEVEL=2`, 96 pictures) | the same; logic 3.5 ms a picture on average, 8.3 ms at most |
| the computer against itself, 600 pictures | 599 × 2 frames, 0 caught, 0 bytes wrong |
| disc: C to the computer (normal), player 1 chooses both | `game_mode` &06; the computer plays B and beats a player who does nothing |

## Milestone 8 step 1: Kim Jong-Un

The third fighter, built through the existing pipeline:
- **Blender** (`tools/blender_puppets.py`, scene `PF_kim`). He is short
  and round (scale 0.88), with a full moon face and small eyes under heavy
  black brows. The flat-top haircut sits over shaved sides.
- **Suit.** A grey Mao suit buttoned to a stand-up collar (`mao=True`: a
  collar ring and three buttons instead of a shirt and tie).
- **Special.** A launch remote with a red button in his near hand, shown
  only in the special (it hides with its button now).
- **Sprites.** New materials `hair_black` (navy over black) and
  `button_red`. `make_sprites.py` turns the 48 renders into sprites.

| | |
|---|---|
| Special | **Surf's Up Missile**: a projectile (`missile.png`, 14 × 7, grey with dark red nose and fins), speed 3, damage 6, hitstun 10 |
| Victory | applauds himself |
| Taunt | "MINE IS BIGGER." |
| Title | "Supremest Leader" (two lines of 12 at most) |
| Colours | bright red (health bar), pink, pastel blue, unused; mirror match: bright magenta, orange, pastel cyan |
| Hit boxes | Putin's, a pixel shorter (he is smaller); the missile leaves from the remote's hand |
| File | bank 0 15,113 bytes, bank 1 5,796 bytes, 6 cache slots; `KIM.PFC` 20,973 bytes |

**His home stage, Pyongyang** (`stage_art.py pyongyang`, inks sky blue,
pastel blue, bright red; packed to 1,788 bytes).
- Behind: a tower with a red flame, and a columned hall hung with red
  banners under a big red star.
- The band: a pale paved square. Grey slabs hid his grey suit, so the slabs
  are white with grey joints.
- The floor: a reviewing stand with a red front and a row of stars. The
  stars are filled five-point shapes, half as wide as tall in pixels,
  because Mode 0 pixels are wide.

**The disc** now holds three characters and three stages, 94 KB of 178.
The three to come need about 75 KB more.

| Test | Result |
|---|---|
| `bench-fight` keys, Trump against Kim | 2 frames between pictures, 0 caught, 0 bytes wrong |
| Kim's missile (down, down-forward, forward + punch) | flies across and hits; 0 passes missed |
| the computer against itself, Kim against Putin, 300 pictures | 2 frames between pictures, 0 caught; Putin wins 6 rounds to 2 |
| disc: player 2 chooses Kim | all four banks match the snapshot |

## Milestone 8 step 2: Xi Jinping

The fourth fighter (Blender scene `PF_xi`):
- **Look.** A broad, smooth face; neat black hair parted and swept over; a
  dark suit with a white shirt and red tie (Trump's suit ramps).
- **Skin.** `CHARACTERS.md` planned pastel yellow with olive shading. It
  read as the old "yellow skin" stereotype, so he is pink like Kim and
  Putin (the material `skin_yellow` stays in the list, unused, so the other
  material colours don't move).
- **Victory.** An overhead wave went out of the top of the frame (it ends
  just above the head), so it is hands clasped behind the back with a slow
  nod.
- **Props.** A pose can now show props by name (`show=(...)`, objects
  `prop_*` hidden otherwise), not only Trump's phone.

| | |
|---|---|
| Special | **Belt and Road**: a strike (special damage 10, a knockdown). The belt cracks out straight ahead in a wide frame (64 pixels); it lands from up to 20 bytes apart, against 13 for a punch |
| Victory | hands behind his back, a nod |
| Taunt | "NO LIMITS, MY FRIEND." |
| Title | "President Emperor" |
| Colours | bright blue (health bar), pink, bright red, unused (the shirt's pastel blue shadow merges into white, as Trump's does); mirror match: bright cyan, orange, bright magenta |
| File | bank 0 15,716 bytes, bank 1 9,131 bytes, 4 cache slots; `XI.PFC` 24,911 bytes |

**A bug the belt found.**
- Before a frame from bank 0 is compiled into a bank 1 slot, its span stream
  is copied to a 600-byte staging buffer in main RAM. The belt's first wide
  frame had a 624-byte stream, and the copy ran into the first cache slot.
  The game hung in a compile.
- `sprite_codegen.py` never checked that limit; Trump's largest stream is
  599. Now it refuses a frame whose stream is over `STAGE_SIZE`.
- The belt is thinner and level in that frame now. A diagonal belt cost a
  line of stream on every scanline it crossed. The frame is under 600.

**His home stage, Beijing** (`stage_art.py beijing`, inks pastel cyan,
pastel blue, bright yellow; packed to 1,854 bytes).
- Tiananmen: the gate tower's golden roofs, curving in to the ridge with
  upturned eaves (`roof()`), over a red hall.
- A long red wall with five arched doorways and gold lanterns.
- White marble balustrades behind the fighters, and a marble terrace with
  a red front of golden clouds as the floor.

**The computer** uses the special only at close range, as it does every
strike or throw. Using the belt from 14-20 bytes would suit it better, but
the AI's gap has 8 bytes left.

**The disc**: four characters and four stages, 121 KB of 178. Musk and
Zelensky need about 52 KB more.

| Test | Result |
|---|---|
| `bench-all`, `bench-fight`, `bench-play`, `SLACK=15`, `bench-ai` | 2 frames between pictures, 0 caught, 0 late, 0 passes missed, 0 bytes wrong |
| `bench-fight` keys, Trump against Xi | the same; the fight ends A 36, B 32 |
| the belt, Xi as B and as A | lands from 10 to 20 bytes apart both ways; 10 damage and a knockdown |
| the computer against itself, Xi against Putin, 300 pictures | 2 frames between pictures, 0 caught, 0 bytes wrong; Putin 7 rounds, Xi 3 |
| disc: player 2 chooses Xi | all four banks match the snapshot |

## Milestone 8 step 3: Elon Musk

The fifth fighter (Blender scene `PF_musk`):
- **Look.** Long-legged in a black T-shirt (new materials `tshirt_black`,
  `arm_black_n/f`; a spec can now give the forearms their own material, so
  his are bare) and jeans (the navy suit ramps).
- **Face.** A long face with a square jaw, a big grin with white teeth, and
  dark hair swept back.
- **Fit.** At first his head ran off the top of the frame. Shorter thighs
  and torso and a scale of 0.98 fixed it; the frame ends just above every
  fighter's head.

| | |
|---|---|
| Special | **Chainsaw Rampage**: a strike (special damage 10, a knockdown) with a toy chainsaw (`prop_saw`: a red motor, a grey bar, a white chain), revved up high, then thrust ahead; it lands from up to 15 bytes apart |
| Victory | a fist pump and a grin |
| Taunt | "I'LL BUY THIS STAGE." |
| Title | "Tech Support" |
| Colours | bright cyan (health bar; nothing else uses it), pink, bright blue, bright red; mirror match: bright green, orange, sky blue, purple |
| File | bank 0 15,624 bytes, bank 1 7,658 bytes, 5 cache slots; `MUSK.PFC` 23,346 bytes |

**His home stage, Starbase** (`stage_art.py starbase`, inks orange, pastel
blue, pastel yellow; packed to 1,883 bytes).
- An orange sunset sky darkening upwards, a low sun over dark red desert
  hills.
- A slim steel rocket with flaps and black tiles on its mount, beside a
  black lattice launch tower.
- A concrete apron behind the fighters, and a steel pad with hazard stripes
  as the floor.

**The disc**: five characters and five stages, 146 KB of 178. With five
headers to read behind the title, the loader takes longer before it takes
fire. The boot test waits longer for that (on a real machine you just press
fire again).

| Test | Result |
|---|---|
| `bench-all`, `bench-fight`, `bench-play`, `SLACK=15`, `bench-ai` | 2 frames between pictures, 0 caught, 0 late, 0 passes missed, 0 bytes wrong |
| `bench-fight` keys, Trump against Musk | the same; the fight ends A 36, B 32 |
| the chainsaw, Musk as B | lands from 10 to 15 bytes apart; 10 damage and a knockdown |
| the computer against itself, Musk against Xi, 300 pictures | 2 frames between pictures, 0 caught, 0 bytes wrong; Musk 5 rounds, Xi 3 |
| disc: player 2 chooses Musk | all four banks match the snapshot |

## Milestone 8 step 4: Volodymyr Zelensky

The sixth fighter (Blender scene `PF_zelensky`), kept to the show's gags
(supplies, determination), with no war imagery:
- **Look.** An olive T-shirt with bare forearms over dark green trousers
  (`tshirt_olive`, `arm_olive_n/f`, `pants_green`), close-cropped dark hair
  and a short beard (`beard`, dark red over black).
- **Crate.** The supply crate in his hands (`prop_crate`, with grey bands)
  first came out too small to see; it is larger now.

| | |
|---|---|
| Special | **More Ammo!**: a supply crate heaved across, a projectile (`crate.png`, 12 × 10, dark red with grey bands and a white diamond), slower and heavier than the tweet: speed 2, damage 7, hitstun 12 |
| Victory | a comedian's bow (a nod to his comedy career) |
| Taunt | "I NEED AMMO, NOT A RIDE." |
| Title | "Humble President" |
| Colours | olive (health bar), pink, green, unused; mirror match: pastel yellow, orange, bright green |
| File | bank 0 15,407 bytes, bank 1 5,916 bytes, 6 cache slots; `ZELENSKY.PFC` 21,387 bytes |

**His home stage, Kyiv** (`stage_art.py kyiv`, inks pastel cyan, pastel
blue, bright yellow; packed to 1,953 bytes).
- St Michael's Golden-Domed Monastery. The pale blue walls use pen 14,
  which stays pastel blue on every stage anyway; white pilasters and
  arched windows.
- Golden onion domes (`dome()`: a bulb from a narrow neck, pinched to a
  spire), on drums over the church and on the bell tower.
- A cobbled square behind the fighters, and a stone platform with a pale
  blue front and gold rosettes as the floor.

**The disc** is nearly full: six characters, six stages, the engine, the
loader and the title take 171 KB of 178. A seventh character needs the
character files packed (or the second side of the disc).

| Test | Result |
|---|---|
| `bench-all`, `bench-fight`, `bench-play`, `SLACK=15`, `bench-ai` | 2 frames between pictures, 0 caught, 0 late, 0 passes missed, 0 bytes wrong |
| `bench-fight` keys, Trump against Zelensky | the same; the fight ends A 36, B 32 |
| the crate, Zelensky as B | flies across and hits Trump for 7; 0 passes missed |
| the computer against itself, Zelensky against Trump, 300 pictures | 2 frames between pictures, 0 caught, 0 bytes wrong; Trump 6 rounds, Zelensky 3 |
| disc: player 2 chooses Zelensky (six on the select screen) | all four banks match the snapshot |

**Milestone 8 is done**: Kim, Xi, Musk and Zelensky join Trump and Putin,
each with a special (two projectiles, two strikes) and a home stage.
Balance between them hasn't been tuned yet: the computer against itself
favours Trump and Putin.

## Packed character files

The disc was at 171 KB of 178 with six characters, so the character files
are packed now.
- **Format.** `sprite_codegen.py pfc` packs each bank on its own with the
  stages' LZ (`tools/stage_pack.py`), checks that it unpacks back, and
  writes `.PFC` version 2: the same 64-byte header (the bank lengths are
  still the unpacked ones), then the two packed banks.
- **Loader.** `unpack_bank` reads the file a byte at a time and unpacks
  straight into the bank paged in at &4000. A match copies from what is
  already written in the same bank, so no buffer is needed. It adds about
  60 bytes to the loader.

| Character | Before | Packed |
|---|---|---|
| Trump | 27,284 | 14,314 |
| Putin | 22,238 | 11,680 |
| Kim | 20,973 | 10,783 |
| Xi | 24,911 | 12,675 |
| Musk | 23,346 | 11,460 |
| Zelensky | 21,387 | 11,634 |

The disc takes 106 KB of 178 now, room for about five more characters.
Loading got faster too: half as many bytes come off the disc. In the
emulator, from fire on the select screen to the fight takes 26-28 s
instead of 46.

| Test | Result |
|---|---|
| disc: Trump against Putin, Xi against Zelensky | all four banks match the snapshot byte for byte |
| disc: Musk against Musk | the same, but B's 4 inks, which the loader sets to the mirror-match colours on purpose |

## Small fixes before milestone 9

**Trump against Trump at `SLACK=15`.** Two Trumps both jumping caught 35
lines (121-140) with the rebuild 1.5 ms late; the margin was ~0.7 ms. The
work is honest (restores 6.6 ms, draws 5.5, the scheduler 1.7, and the two
restores overlap by only ~10 bytes), so the rebuild now starts earlier
instead:
- **The tick is interrupt 4, line 170** (`TICK_IRQ`), not 5. The beam has
  passed every line above it, so the top of a jump gets 3.3 ms more.
- **A guard in the band loop.** While the interrupt count is still 4, a
  band whose targets would reach `GUARD_LINE` (168) waits, with
  interrupts on, for interrupt 5 (line 222): the beam is then below the
  fighters, as before.
- **`start_irq`, per picture.** `prepare` (now in a mirror gap,
  `prepare.asm`, with `can_skip` in `skip.asm`) looks at the first band:
  when it already reaches line 168, the rebuild would only wait, so it
  starts on interrupt 5 and the compiler keeps that period. `irqs_left`,
  `jc_look` and the interrupt's `jc_flag` count to `start_irq`, and
  `wait_render` returns in that period. Without this, fights with both
  fighters on the ground lost a period of compiling a picture (held frames
  48 → 88 in `bench-fight`).
- **The projectiles' pass** can't run in period 4 (the beam is on them).
  If it is still due when a picture would start on line 170, that picture
  starts on line 222 after it (`bench-ai` missed 5 passes without this).
- **The sound** moved to interrupt 3 (line 118), so it doesn't delay the
  start (0.4-1.7 ms when it shared the tick). That period is the
  compiler's last before a line-170 start, which it doesn't use anyway.
- **The bench** judges a line the beam passes below the start line, in
  the frame the rebuild started, against the picture before: every line
  shows the new picture from the next frame. Not for the projectiles'
  pass, which draws ahead of the beam on purpose.

Also tried: bands of 24 lines with restores capped at 16 lines between
interrupt windows. The scheduler's time didn't drop and lines were caught
earlier (the top of a band finishes later), so bands stay 16.

| Test | Result |
|---|---|
| Trump against Trump, both jumping, `SLACK=15` / `25` / `35` | 0 / 0 / 3 lines caught (was 35 at `SLACK=15`) |
| `SLACK=15` Trump against Putin; `bench-all` | 0 caught, 0 late, 0 passes missed, 0 bytes wrong |
| `bench-fight`, `bench-play`, `bench-ai`: held frames A/B | 28/20, 21/20, 31/30 (before: 25/23, 20/20, 28/28) |
| Kim against Zelensky in Kyiv, projectiles | 0 caught, 0 bytes wrong |

**Kim's remote** was a 6×9×10 cm box behind his fist, edge-on to the
camera: it came out as a pixel or two of grey on his grey suit. Now it is
twice the size, black (`tshirt_black`: navy and black on the screen), with
its red button on the face the camera sees and a stub antenna, and the
first two frames hold it out in front instead of at his mouth.

**The Kyiv domes** were drawn in from their widest to a point like a
spinning top. Now they keep round shoulders (`1 - u²` over 1.4 ry) and
come to a short tip a byte wide under the spire, closer to St Michael's.

## Milestone 9 step 1: our own disc reading

The ladder needs the next opponent mid-game, after the engine has taken
the machine from the firmware. Of the options in GAME_PLAN ("Milestone 9
plan"), this is B: the engine drives the µPD765 itself.

**The disc** is now written by `tools/make_dsk.py`, not iDSK. It is an
EXTENDED CPC DSK in AMSDOS's data format: 42 tracks, every one formatted.
iDSK left tracks 40-41 with no sectors, and some drives and emulators
choke on that. Sectors are #C1-#C9 in AMSDOS's 2:1 interleave. Every file
is in the directory, so the loader still reads everything through the
firmware. The files the engine reads itself come first, character files
and then stages, so their places depend only on them. `make_dsk.py map`
writes `src/gen/diskmap.asm` before the engine is assembled: for each
character of the roster, the track and sector of its file and of its home
stage. rasm now only `SAVE`s the engine's binary.

**Character files are fighter B's** (pens 10-13). The engine loads the
next opponent straight into banks 6-7, and the loader moves fighter A's
own colours to 6-9 instead (`remap_tab` is the other way round). The
select screen also leaves the two roster numbers at `SETTINGS_AT+1`.

**The driver** is TerraCPC's, made compact:
- sense interrupt status before every command, at most 8 times;
- a seek ends on ST0's seek end;
- result bytes are read while the controller is busy;
- one sector per command, with end of cylinder not counted as an error;
- every wait has a time out.

Any fault starts the whole load again, with the border red, so no routine
returns an error.

The floooh emulator never answers sense interrupt status with "nothing"
(#80): an unbounded drain hung there. The load runs with interrupts off
and the inks black, a track at a time into `DISC_BUF`, which is in the
compiled frame caches (free between matches):
- `stream_unpack` unpacks fighter B's two banks as they come;
- then it unpacks the stage straight into the screen. That covers the
  screen's tails too, so the cold code is kept aside meanwhile, and
  `start` rebuilds the workspace and the tables.

Then the choices go back to `SETTINGS_AT` and the match starts through
`start`, the same as after boot.

**Where it lives:**

| Where | What |
|---|---|
| Low RAM #0040-#00FF, new (the stack goes down to #01E0, measured) | `stream.asm` (pages the banks in), the driver's variables, the disc map |
| Mirror gaps 1, 2, 6 | `fdc.asm`, `discread.asm`, `fdcseek.asm` |
| Mirror gaps 3, 4 | `ladder.asm`, `nmstage.asm` |
| Payload | `prepare` is back here: the SHOTS bench build needed gap 6 |

Boot also turns the drive's motor off. The firmware would have, but it is
gone by then.

**The ladder, for now:**
- It applies when player 1 plays the computer and wins a match.
- The next opponent is the roster's next character, skipping the player's,
  with its home stage.
- If the computer wins, it is the same opponent again, as before.

| Test | Result |
|---|---|
| Disc boot, Trump against the computer, the match won (a poke), 6 times | Kim, Xi, Musk, Zelensky, Putin, Kim. Each ~3 s in the emulator, banks 6-7 byte-exact with the character files, banks 4-5 with the snapshot's fighter A |
| `bench-all` | 0 caught, 0 late, 0 passes missed, 0 bytes wrong |
| `bench-fight`, `bench-play`, `bench-ai`: held frames A/B | 28/20, 21/20, 31/30 (as before) |

The emulator doesn't time the disc's turning. On a real drive a track
takes two turns (the interleave), so a load should be ~4-5 s with the
motor's second. Not yet tried on a real 6128.

Free memory then: payload 87, low RAM 37, workspace 22, COLD/COLD2 27/60
bytes. Gaps 1-8: 7, 12, 4, 17, 24, 73 (45 in the SHOTS build), 3, 8.

## Milestone 9 step 2: the Puppet Master

The ladder's boss is Ian Bremmer, the show's very first puppet (Blender
scene `PF_bremmer`):
- **Look.** A black suit (`suit_black`: navy over black), white shirt and
  blue tie, short dark hair combed back, arched brows and a knowing grin.
- **Not on the select screen.** `BOSS` in the Makefile puts his file on
  the disc and last in the disc map (index `DM_CHARS`), but not in
  `ROSTER.TXT`.

| | |
|---|---|
| Special | **G-Zero World**: a globe bowled across (a projectile, `globe.png`, 12 × 12: navy seas, pastel blue land, a white glint), speed 3, damage 8, hitstun 12 |
| Victory | works a marionette control over his head, its strings hanging |
| Taunt | "EVERYONE HAS STRINGS." |
| Title | "The Puppet Master" |
| Colours | bright magenta (health bar), pink, bright blue (tie, globe in hand), green (its land) |
| File | bank 0 15,785 bytes, bank 1 7,346 bytes, 5 cache slots; `BREMMER.PFC` 11,517 bytes |

**His stage, the puppet theatre** (`stage_art.py theatre`, inks sky blue,
pastel blue, bright red; packed to 2,433 bytes):
- red curtains drawn back from a painted world map (pastel blue
  continents under a white grid);
- two marionette controls hanging from the flies;
- board stage behind the fighters, and an apron with a row of footlights.

**The ladder** (`pick.asm`, in the payload: the gaps are full in the SHOTS
bench build):
- Each win counts. Once the player has beaten `DM_CHARS - 1` opponents
  (all five others), the boss comes on.
- He plays at the computer's hardest level, whatever was chosen
  (`nmstage.asm` sets `SETTINGS_AT`).
- Beat him and the ladder starts again from the roster, at the level
  chosen. Lose, and he comes again, like any opponent.

| Test | Result |
|---|---|
| Disc: Trump against the computer, the matches won by a poke, 8 times | Kim, Xi, Musk, Zelensky, then the boss at level 2, then Putin, Kim, Xi at level 0. Every load byte-exact |
| `SHOTS=1`, Bremmer as B: globes flying, both jumping | 0 caught, 0 late, 0 passes missed, 0 bytes wrong |
| `bench-fight` keys, Trump against Bremmer | 0 caught; held frames 26/25; the fight ends A 36, B 32 |
| the computer against itself, Trump against Bremmer | 0 caught, 0 bytes wrong |

The disc now holds 123 of its 180 blocks.

Free memory now: payload 36, low RAM 32, workspace 22, COLD/COLD2 27/60
bytes. Gaps 1-8: 7, 12, 24, 6, 24, 73 (45 in the SHOTS build), 3, 8.

## Milestone 9 step 3: the select screen and the manuals

**The select screen is a menu** (loader.asm `select`). It draws over
`SELECT.SCR` (tools/title_art.py): the title in small, "VS" between the two
fighters, and "REVIVE8BIT - 2026 - VASPER" at the foot. The rows are
Player 1, Player 2, Opponent (Human or Computer), and Difficulty (Easy,
Medium, Hard), which shows only for the computer:
- up and down choose a row, left and right change it, fire or Space
  starts (either player's controls);
- the chosen row is yellow with an arrow;
- the two fighters chosen stand above the menu, in their own colours (the
  second set in a mirror match).

Their first idle frames and colours come from `FIGHTERS.BIN`, which goes
into bank 4 until the characters load over it. Each character has its
frame there twice, as fighter A and as fighter B (2,056 bytes a
character).

**A controls screen** (`how_to`, Mode 1) follows. It shows both players'
keys and every move's combination while the fighters load, then "FIRE TO
FIGHT!" and waits for fire.

**A victory screen fix.** `victory` called `music_play`, which takes IX,
before it looked at who had won. The lines shown were fighter B's whatever
the result. It keeps IX now.

**The manuals**, `manual.md` and `manual_gr.md`, are turned into PDFs by
`make manual` (`tools/mkmanual.py`, from BuildDangerousCPC). They use
screenshots from the disc in the emulator (`docs/img`).

## Milestone 9 step 4: the release

- **The disc's name.** It is `RUN"PUPPET` now (`PUPPET.BAS`,
  `PUPPET.BIN`), not the spike's `PFSPIKE`. The image is
  `build/puppetfight.dsk`. The test snapshot keeps its name.
- **`make release`** puts the disc and both manuals in
  `build/PuppetFight.zip`.
- **`QUICKWIN=1`** builds a test disc where player 1 wins every match at
  once, so the ladder runs by itself.
- **Caprice32** (`tools/cap32_smoke.py`) is a second emulator with its
  own µPD765 emulation. The script runs its snap with SDL's dummy drivers
  and no speed limit, types into the menu (player 2's S and D: the
  autotype's cursor keys don't work there), and takes a screenshot every
  few seconds. On a `QUICKWIN=1` disc the ladder loaded about 20
  opponents in a row: Kim, Xi, Musk, Zelensky, the boss in the theatre,
  Putin, round and round. No fault, no red border, and no hang.
  - The first try failed for two reasons. The window version's autotype
    crawled. Another session's Caprice32 also wrote its screenshots into
    the same folder (they are named by the second), so the script now
    only takes the new ones.
  - The same test found that `QUICKWIN` didn't set `rnd_winner`, which
    gave rematches instead of the ladder (only the test flag was wrong).

Still to do for 1.0: a real 6128, with a 3" drive and with a Gotek/HxC,
and RetroVirtualMachine or WinAPE. Those are the driver's and the
overscan's real tests.

## Next (milestone 2 work this feeds)

- Held frames in busy play (34 of 192 fighter-pictures in the script): the
  compiler does about one frame per picture. Further options: guesses from
  the game state (the opponent close, a button down), or letting the logic
  start a move on a frame that is already cached.
- Confirm on real hardware (CRTC types 0-2), as OverscanCPC did.