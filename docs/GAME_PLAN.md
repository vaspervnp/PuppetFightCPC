# Puppet Fight CPC — Game Plan

A one-on-one fighting game for the Amstrad CPC 6128 in Z80 assembly. It is a
satirical take on world leaders and celebrities, in the felt-puppet style of
GZERO Media's *Puppet Regime*. Big pre-rendered puppet sprites fight in Mode 0
overscan. Two fighters are loaded from disk per match.

## 1. Goals

- **Look**: large, colourful puppet sprites (32×64 Mode 0 pixels, 64×64 for
  falls) on a full overscan screen, so it reads as a "big sprite" CPC game.
- **Feel**: responsive, readable combat at a steady 25 fps. Simple inputs
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

**Single buffer.** A second overscan screen plus engine does not fit
comfortably in 128K, and the spike shows we don't need one:

- **Background mirror.** Main RAM &4000-&7FFF holds a copy of the fighter
  band (lines 144-271). Each screen byte is mirrored at the same address
  with `H = (H AND &3F) OR &40`. Page 3 rows land at offsets &000-&4DF and
  page 2 rows 18-20 at &6E0-&7FF of each 2K slice, so they never collide.
  Erasing a fighter is a copy from the mirror over the spans of its old
  frame. There are no save buffers, and fighters can overlap freely because
  the mirror never holds a fighter.
- **Two windows per picture.** We render at 25 fps, so each picture spans
  two frames. The beam reaches the fighters' top line (204 when standing)
  15.6 ms after the frame tick. Fighter A is rebuilt (restore + draw) right
  after the first tick, fighter B right after the second. When their ground
  overlaps, both are restored and redrawn in one window.
- Interrupts are recognised on VSYNC, as in OverscanCPC: a frame tick is the
  interrupt that lands inside VSYNC, so every frame's work starts at the
  same raster position.

Measured on the cycle-accurate emulator, with both idle fighters swaying:
no scanline is caught half drawn, and the screen matches mirror + sprites
byte for byte. See [SPIKE.md](SPIKE.md).

Constraints this leaves:
- When the fighters overlap, everything must fit one window. That means
  under 15.6 ms when standing, and only ~11.8 ms when a fighter's top is at
  line 144 (the top of a jump).
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
| Restore from mirror (span, LDIR) | 5.1-5.4 ms | ~53 µs per line + 6 µs per byte |
| Compiled draw, right or left | 2.4-2.8 ms | ~8 µs per drawn byte, all in |
| Generic mirrored span draw | 8.7 ms | ~32 µs per drawn byte, all in |

What this decides:
- When the fighters are apart, every combination fits its window, including
  the generic drawer (5.1 + 8.7 = 13.8 ms < 15.6).
- When they overlap, only compiled draws fit (15.8 ms, standing). That's
  with no margin, and none at all for a jumping fighter.
- Compiled code for every frame and both facings would be ~150 KB per
  character, so it can't all be resident.

**Next steps** (part of milestone 2):
- **Make restore cheaper**: a separate (s, n) table read through the
  alternate register set, and skipping bytes the new frame overwrites when
  the fighter hasn't moved.
- **Compile on demand**: a runtime compiler that turns the current move's
  span frames into compiled code for the current facing, in a per-fighter
  RAM cache (~6-8 KB). Idle, walk, crouch and block are compiled ahead of
  time for both facings.

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
| &0200-&3FFF | 15.5K | engine, tables (flip, mask, line_tab), hot compiled frames |
| &4000-&7FFF | 16K | background mirror of the fighter band (~12K used, ~4K free in 512-byte gaps) |
| &8000-&FFFF | 32K | overscan screen (26K used, ~6K free in 800-byte gaps of page 3) |
| Bank 4-5 | 32K | fighter A: span frames, move data, compiled cache |
| Bank 6-7 | 32K | fighter B |

The load image starts at &4000, where AMSDOS hands over. It moves itself
down to &0200 before the mirror is built. In the spike, the engine plus
four compiled frames and eight span frames fill the payload to &33E2.
Stage graphics and music have to come from the gaps or be ZX0-packed and
unpacked at round start.

### 3.5 Character file format (`TRUMP.PFC` etc.)

```
header      magic "PF", version, name, personal colours (4 firmware colours)
move table  14+ moves: frame count, per-frame duration, hitbox/hurtbox,
            damage/stun data, special-move input pattern
frames      span-encoded masked frames (pens 0-9)
hot frames  compiled idle/walk routines (generated for the right-facing side)
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
| 2 | **Engine core** | game loop, joystick/keyboard for 2 players, fighter state machine, walking, jumping arcs, facing and flip, ground and walls |
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
| Overlapping fighters miss the beam (one shared window) | cheaper restore and on-demand compiled frames (§3.2). If that is not enough: drop to 12.5 fps only on overlapping pictures |
| Sprite drawing too slow at 25 fps | span encoding + compiled hot frames. Drop to 17 fps for KO/special frames. Only redraw the changed fighter |
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
