# Puppet Fight CPC — Game Plan

A one-on-one fighting game for the Amstrad CPC 6128 in Z80 assembly. It is a
satirical take on world leaders and celebrities, in the felt-puppet style of
GZERO Media's *Puppet Regime*. Big pre-rendered puppet sprites fight in Mode 0
overscan. Two fighters are loaded from disk per match.

## 1. Goals

- **Look**: large, colourful puppet sprites (32×64 Mode 0 pixels, 64×64 for
  falls) on a full overscan screen, so it reads as a "big sprite" CPC game.
- **Feel**: responsive, readable combat locked at 25 fps, with no drops even
  when fighters overlap (§3.2b). Simple inputs
  (one- or two-button joystick) with a few special moves per character.
- **Humour**: each character's specials and victory poses riff on their
  *Puppet Regime* persona.
- **Expandable**: characters are self-contained disk files. Adding one means
  modelling and posing in Blender, running the pipeline, and dropping the
  file on the disk.

### Target hardware

| | |
|---|---|
| Machine | CPC 6128 (or 464/664 with 64K expansion). 128K is required |
| Display | Mode 0, overscan, 50 Hz |
| Input | Joystick 1 + 2 or keyboard. Two-button joystick optional |
| Sound | AY-3-8912: music + SFX |
| Media | 3" disk (DATA format, 178K per side). Two-sided if the roster grows |

## 2. Gameplay

### Match structure
- Best of 3 rounds, 99-second round timer, health bars, KO or time-out win.
- Modes: **1P vs CPU**, **2P versus**, and later a short **Arcade ladder**
  ending in a boss fight against "The Puppet Master" (see
  [CHARACTERS.md](CHARACTERS.md)).
- Character select → stage → fight → victory screen with a one-line taunt.

### Controls (joystick, facing right)

| Input | Action |
|---|---|
| ← / → | walk back / forward. Holding back blocks |
| ↓ | crouch (↓ + back = crouch block) |
| ↑ | jump (↑ + direction = jump arc) |
| Fire 1 | punch (crouching: low punch) |
| Fire 2, or Fire 1 + ↓ when no second button | kick (crouching: sweep) |
| ↓ then ↑ + Fire 1 | uppercut (anti-air) |
| ← + kick | back kick (spinning mule kick) |
| ↓ ↘ → + Fire | special 1 (projectile or rush) |
| → ↓ ↘ + Fire | special 2 (when a character has one) |

The input buffer keeps the last ~12 frames of joystick state for motion
detection. It is kept forgiving, because CPC joysticks are stiff.

### Combat model
- Every frame has a **hurtbox**, and attack frames also have a **hitbox**.
  Boxes are authored as Aseprite slices (or a JSON sidecar) and exported with
  the sprite data.
- Per-move data: startup / active / recovery frames, damage, hitstun,
  blockstun, pushback and knockdown flag.
- States: idle, walk, crouch, jump, attack, block, hitstun, knockdown, KO,
  victory.
- Chip damage on blocked specials. A throw (Putin's judo, Xi's "friendship")
  can't be blocked, only escaped by holding back on the first frame.
- Projectiles are separate small sprites (≤ 16×16) owned by the fighter. At
  most one per fighter on screen.

## 3. Technical design

### 3.1 Screen (decided in milestone 1)

Overscan Mode 0, **192×272 visible pixels**: 96 bytes per line × 272 lines
= 26,112 bytes in a 32 KB screen at &8000-&FFFF. The CRTC values are the
ones OverscanCPC proved on a real 6128 (R1=48, R6=34, R12/R13=&2C10, so the
fetch rolls from page 2 into page 3 at row 21 with no rupture).

**Raised floor on every stage.** The bottom 60 lines (212-271) are always
floor, a raised platform the fighters stand on. The bottom of a full
overscan picture is cut off on some emulators (Retro Virtual Machine) and
monitors, so nothing that matters is drawn there. Fighters' feet are on
line 212, a standing fighter's top is line 148, and the top of a jump is
line 88.

**Single buffer.** A second overscan screen plus engine does not fit
comfortably in 128K, and the spike shows we don't need one:

- **Background mirror.** Main RAM &4000-&7FFF holds a copy of the fighter
  band (lines 88-211). Each screen byte is mirrored at the same address
  with `H = (H AND &3F) OR &40`. Page 3 rows 21-26 land at offsets
  &000-&23F and page 2 rows 11-20 at &440-&7FF of each 2K slice, so they
  never collide.
  Erasing a fighter is a copy from the mirror over the spans of its old
  frame. There are no save buffers, and fighters can overlap freely because
  the mirror never holds a fighter.
- **Two windows per picture.** We render at 25 fps, so each picture spans
  two frames. A rebuild starts on the **interrupt at line 222**, the fifth
  after VSYNC, just after the beam has left the fighters' lowest line. From
  there the beam needs 15.2 ms to reach a standing fighter's top (line
  148) and 11.4 ms to reach the top of a jump (line 88). Fighter A is
  rebuilt in the first window, fighter B in the second. When their ground
  overlaps, both are rebuilt in one window.
- That window runs across VSYNC, so it lets interrupts in after every job
  (on the real stack). No stretch with them off is longer than ~1.3 ms.
  Otherwise the Gate Array would lose or move interrupts and the count that
  finds line 222 would drift. The interrupt in VSYNC is still recognised
  as the frame tick, as in OverscanCPC, even when it's serviced too late to
  see VSYNC on the PPI.

Measured on the cycle-accurate emulator, with both idle fighters swaying:
no scanline is caught half drawn, and the screen matches mirror + sprites
byte for byte. See [SPIKE.md](SPIKE.md).

Constraints this leaves:
- When the fighters overlap, everything must fit one window. That means
  under 15.2 ms when standing, and only ~11.4 ms when a fighter's top is at
  line 88 (the top of a jump).
- Extra RAM is only paged in with &C4-&C7 (bank at &4000). That never
  touches the screen at &8000-&FFFF, whichever way the video fetch follows
  the RAM configuration. It does hide the background mirror, so restore
  and draw must page between them.

### 3.2 Sprite drawing (measured in milestone 1)

Two encodings come out of `tools/sprite_codegen.py`:

1. **Span stream** (every frame). Per line: first byte s, count n, then n
   data bytes. No masks are stored: pen 0 is the only transparent pen, so
   the mask is `mask_tab[byte]`. About 1.4 bytes of storage per drawn byte,
   ~450 bytes per frame. Restores use it for every frame, and the generic
   drawer can draw it mirrored through `flip_tab`.
2. **Compiled routine** (hot frames). `LD (HL),n` for opaque bytes,
   `LD A,(HL) : AND m : OR d : LD (HL),A` for edges, and a line-table `POP`
   per scanline. About 4.6 bytes of code per drawn byte, ~1.5 KB per frame
   per facing.

| Step (idle frames, ~350 / ~275 bytes) | Time | Per unit |
|---|---|---|
| Restore from mirror, from a prepared restore list | 2.8-3.3 ms | ~17 µs per line + 6 µs per byte |
| Compiled draw, right or left (yields every 8 lines) | 2.4-2.9 ms | ~8 µs per drawn byte, all in |
| Generic mirrored span draw | 8.7 ms | ~32 µs per drawn byte, all in |

Restore lists: `prepare` turns the frame a fighter has on the screen into
one (screen address, byte count) entry per scanline, in idle time after
the picture. The restore inside the window then only pops, mirrors the
address and copies. The first pass computed all of that per line, inside
the window (~53 µs per line, 5.1-5.4 ms).

What this decides:
- When the fighters are apart, every combination fits its window, including
  the generic drawer (5.1 + 8.7 = 13.8 ms < 15.6).
- When they overlap, only compiled draws fit. With them, every overlap case
  fits with 2-3 ms to spare (§3.2b).
- Compiled code for every frame and both facings would be ~150 KB per
  character, so it can't all be resident.

**Next step** (part of milestone 2):
- **Compile on demand**: a runtime compiler that turns the current move's
  span frames into compiled code for the current facing, in a per-fighter
  RAM cache (~6-8 KB). Idle, walk, crouch and block are compiled ahead of
  time for both facings.

### 3.2b Frame rate: locked at 25 fps

**The fight renders at 25 fps on every picture.** That includes overlaps,
jumps, specials, projectiles and KO falls. There is no fallback to 17 or
12.5 fps: if a move doesn't fit, the move or the art changes, not the frame
rate. Logic runs at 50 Hz (two steps per picture), as in OverscanCPC.

Per-picture budget: 40 ms = two windows of ~15.6 ms before the beam reaches
the standing fighters, plus the rest of each frame.

| Case | What has to fit | Plan |
|---|---|---|
| Fighters apart | one fighter per window: restore + draw < 15.6 ms, or < 11.8 ms at the top of a jump | already met. 13.9 ms worst with the generic drawer |
| Fighters overlapping | both fighters in one window, done before the beam reaches each line | **banded rebuild**, below |
| Projectiles, hit sparks | small sprites (≤ 8 bytes × 16 lines) in the window of the fighter that owns them | span-drawn, ~0.5 ms each |
| Logic, input, AI, HUD, music | after the rebuild in each frame. The music player goes on the third interrupt, off the frame tick | ≤ 4 ms per frame |

**Banded rebuild** (`src/rebuild.asm`, built and measured). Restore A,
restore B, draw A and draw B are jobs. The scheduler walks the screen in
16-line bands, top to bottom, and runs each job as far as its target in
the band: restores to band + 16, draw A to band + 8, draw B to band + 0.
Compiled draws yield every 8 lines. The staggered targets keep the order
restore, restore, draw A, draw B on every scanline. Both windows use the
same scheduler; a window that holds one fighter just has two jobs.

The hardest case is both fighters in the air and overlapping. All the work
then sits in lines 88-151, which the beam has finished ~15.4 ms after the
tick, so the total has to fit before that whatever the order. Measured on
the cycle-accurate 6128 with the raised floor (`make bench-all`, every
scanline pass judged):

| Case | Rebuild ends with the beam on line | Lines caught |
|---|---|---|
| Apart, generic draw for Putin | 121 (fighters' top: 148) | 0 |
| Toe to toe, standing | 120 (148) | 0 |
| Toe to toe, one fighter jumping | 130 | 0 |
| Toe to toe, both jumping (tops at line 88) | 121 | 0 |

Margin, by starting the rebuild late on purpose (`SLACK`): 1.5 ms late is
still clean in the both-jumping case, 2 ms late is not. Before the raised
floor it was 2-3 ms: the head start is 0.4 ms shorter from line 222, and
the interrupt windows cost ~0.25 ms. Lowering the jump top by 8 lines would
buy 0.5 ms back. This margin is the budget for projectiles and HUD changes
in a shared window, until the on-demand compiler and further restore work
add more.

Overlaps need both fighters drawn with compiled code. The on-demand
compiler guarantees it: a frame is compiled the picture before it's needed,
while the fighters are still apart or the frame is still being held.

**Rules that keep 25 fps true:**
- Jump apex no higher than line 88 (the top of the background mirror), 60
  lines above a standing fighter's top.
- No frame over 32×64 in a shared window. Wide 64×64 KO frames only happen
  after the round is decided, when the opponent is idle or doing a victory
  pose. Their window then holds only the falling fighter.
- `make bench-all` (apart, toe to toe, toe to toe with jumps) must report
  0 lines caught. That is the acceptance test for milestones 2 and 3, and
  `SLACK=15` must stay clean so the 1.5 ms margin isn't eaten silently.

### 3.3 Palette strategy

Mode 0 gives 16 pens for both fighters and the stage. For the roster to grow
past Trump/Putin, the palette gets split:

| Pens | Use |
|---|---|
| 0 | transparent / background black |
| 1-5 | shared fighter pens: outline black, white, navy, dark red, grey |
| 6-9 | fighter A personal pens (skin, hair, outfit accent) |
| 10-13 | fighter B personal pens |
| 14-15 | stage pens (plus any shared pens the stage can reuse) |

Each character file declares its personal colours. At load, the second
fighter's pixels are remapped from pens 6-9 to 10-13 (cheap, because the
pen bits are packed and can go through a 256-byte translation table). The
current Trump/Putin palette in `tools/cpc_palette.py` will be refactored to
this scheme.

The CPC has no true brown, which matters for several roster skin tones. The
usable skin ramps are orange (FF8000) → dark red (800000), pink (FF8080) →
dark red, and pastel yellow (FFFF80) → olive (808000).

### 3.4 Memory map (frozen in milestone 1)

| Area | Size | Contents |
|---|---|---|
| &0038 | 3 | interrupt jump (both ROMs are off, so this is RAM) |
| &0100-&01FF | 256 | stack |
| &0200-&3FFF | 15.5K | engine and tables (flip, mask, chain entries). The spike ends at &10BE, ~12K free |
| &4000-&7FFF | 16K | background mirror of the fighter band, lines 88-211 (~12K used, ~4K free in 512-byte gaps at &x240-&x43F) |
| &8000-&FFFF | 32K | overscan screen (26K used). The unused 800-byte tails of page 3 hold `line_tab` (&C4E0) and the two restore lists (&CCE0, &D4E0); ~4K of tails are still free |
| Bank 4-5 | 32K | fighter A's character: directory, all 48 frames (span stream + (s, n) table), compiled frames |
| Bank 6-7 | 32K | fighter B's character |

The load image starts at &4000, where AMSDOS hands over. It moves itself
down to &0200 before the mirror is built.

**Characters live in the banks** (milestone 2). `tools/sprite_codegen.py
character` writes each character as two bank images. Bank 0 starts with a
directory at &4000: per move, the frame count and a list of 12-byte frame
records (bank, width, x offset, span stream, (s, n) table, compiled bank,
compiled draw facing right and facing left). The engine finds every frame
through it, so no character label appears in the engine. Trump uses 32,496
of 32,768 bytes (two compiled idle frames included), Putin 26,940.

Paging rules:
- Logic and job set-up page the character's bank in to read the directory,
  a frame header, or an (s, n) table, then page #C0 back.
- In the rebuild every draw job carries its RAM configuration (its frame's
  bank, or the bank its compiled code is in) and is paged in when it runs.
  Restores always run with #C0, because they read the mirror.
- Nothing else in &4000-&7FFF is touched while a bank is in: the screen,
  `line_tab`, the restore lists and the tables are all outside it.

On the disc each bank is its own file (`TRUMP0.BIN` ...). `PFSPIKE.BAS` does
`OUT &7F00,&C4` and so on, then `LOAD`s each one at &4000 before loading the
engine. Checked on the emulated 6128: `RUN"PFSPIKE` loads all five files and
the fight starts. Stage graphics and music have to come from the gaps or be
ZX0-packed and unpacked at round start.

### 3.5 Character file format (`TRUMP.PFC` etc.)

```
header      magic "PF", version, name, personal colours (4 firmware colours)
move table  14+ moves: frame count, per-frame duration, hitbox/hurtbox,
            damage/stun data, special-move input pattern
frames      span-encoded masked frames (pens 0-9): today's bank layout
            (directory + frame records, §3.4) is the start of this format
hot frames  compiled routines, both facings where they fit
projectile  small sprite + speed/behaviour id
text        victory taunt, select-screen title ("The Greatest American 2.0")
```

Loaded with AMSDOS (firmware) in the select screen, before the engine takes
over the machine. The size cap is 32K so a character fits two banks.

### 3.6 Toolchain

| Tool | Use |
|---|---|
| Blender 5.2 + MCP | puppet models, posing, rendering (`tools/blender_puppets.py`) |
| Aseprite 1.3 + MCP | pixel touch-ups, tags, hitbox slices |
| Python 3 + Pillow | quantise, export, compiled-sprite generator |
| RASM | assembler (bank support, writes `.dsk` directly) |
| Arkos Tracker 2 | music + SFX, AKG/AKY player |
| ACE-DL / WinAPE / CPCEC | emulators (ACE-DL has a good debugger) |
| Real 6128 + M4/HxC | hardware testing |

Build: a `Makefile` running pipeline → assemble → `.dsk`.

## 4. Milestones

| # | Milestone | Done when |
|---|---|---|
| 0 | **Art pipeline + first fighters** ✅ | Trump and Putin, 14 moves, CPC data export |
| 1 | **Tech spike** ✅ | overscan screen up. Buffering option chosen. Span-sprite and compiled-sprite drawers benchmarked. Memory map frozen. Two idle fighters animating at 25 fps |
| 2 | **Engine core** | game loop, joystick/keyboard for 2 players, fighter state machine, walking, jumping arcs, facing and flip, ground and walls. Banded overlap rebuild, cheaper restore, on-demand compiler. `make bench` overlap+jump scenario at 25 fps with 0 lines caught |
| 3 | **Combat** | hit/hurt boxes from Aseprite slices, damage, block, hitstun, knockdown, KO, rounds, timer, health bars |
| 4 | **Character loading** | `.PFC` format, loader, pen remap, select screen, two characters from disk |
| 5 | **Specials + projectiles** | motion input, Tweet Storm (tweet-bird projectile), Judo Throw (throw state) |
| 6 | **Presentation** | stages (White House lawn, Kremlin hall), title, music, SFX, victory screens with taunts |
| 7 | **CPU opponent** | reactive AI with difficulty levels |
| 8 | **Roster wave 1** | Kim Jong-Un, Xi Jinping, Elon Musk, Zelensky (see [CHARACTERS.md](CHARACTERS.md)) |
| 9 | **Release 1.0** | arcade ladder + Puppet Master boss, two-sided disk, real-hardware test, `.dsk` release |

## 5. Risks

| Risk | Mitigation |
|---|---|
| Overlapping fighters miss the beam (one shared window) | banded rebuild + cheaper restore + on-demand compiled frames (§3.2b). The frame rate is not a mitigation: if it still doesn't fit, cap jump height or trim the frame's art |
| Sprite drawing too slow at 25 fps | span encoding + compiled frames, only redraw a fighter that changed, wide KO frames only once the round is decided. `make bench` overlap scenario must show 0 lines caught |
| Character data over 32K | fewer unique frames (mirror and reuse), shared frames for hit/block, ZX0-compress cold moves and unpack on demand |
| Palette clashes between characters | personal-pen scheme (§3.3). Design new characters from the shared ramps |
| Satire of real people | keep it in the show's affectionate-absurd register. No real violence imagery beyond slapstick. Credit *Puppet Regime* as inspiration. It's a non-commercial fan project |

## 6. Open questions

- One button or two? (A single button with ↓ for kick keeps every joystick
  usable.)
- Should fighters keep legs? The show's puppets are legless hand puppets.
  Ours have legs so they can kick. A stage-themed "puppet theatre" backdrop
  could nod to the original.
- Disk layout once the roster passes ~6 characters (each up to 32K):
  two-sided disk or a custom format.
