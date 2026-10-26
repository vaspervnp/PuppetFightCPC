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

### 3.1 Screen

Overscan Mode 0, aiming for **192×256 visible pixels**: 96 bytes per line ×
256 lines ≈ 24 KB. The CRTC is set up for a 32 KB screen (R12 bits 2-3 = 11)
so the screen can cross a 16K page.

Key constraint: **the CRTC and Gate Array always read video from the base
64K**. Extra RAM banks are only visible to the Z80 (paged in at &4000-&7FFF,
or in the C1-C3 layouts). Banked sprite code must never be paged over the
buffer being drawn to.

Buffering options. Pick one in milestone 1:

| Option | Layout | Pros | Cons |
|---|---|---|---|
| A. Double buffer | screens at &0000 and &8000 (24K each). Engine in the 8K gaps. Sprites in banks paged at &4000 only while drawing to the &8000 screen | no tearing, simple drawing | when drawing to the &0000 screen, sprite code must be paged elsewhere (e.g. C1: bank at &C000, over the front buffer the CPU isn't writing to). Tight main RAM |
| B. Single buffer, beam-raced | one screen. Erase/redraw each fighter just after the beam has passed it | frees ~24K | needs precise timing. Flicker risk with large overlapping sprites |
| C. Double buffer, reduced height | two 16K screens (e.g. 192×168 play area) plus HUD via a CRTC split (raster interrupt) | simple paging | loses the "full overscan" look |

Baseline recommendation: **A**, with a hand-tuned memory map (§3.4). Fall
back to C if paging gets too tangled.

### 3.2 Sprite drawing

The art pipeline already exports masked Mode 0 frames. The engine will use
two encodings:

1. **Span-encoded masked frames** (default). Per line: skip count, then the
   run of bytes where opaque bytes are plain data and edge bytes are
   mask+data. Roughly 500 bytes per frame (Trump averages 282 opaque + 64
   edge bytes per frame) → ~20 KB per character. Mirroring for the
   left-facing fighter uses a 256-byte pixel-swap table and walks each line
   backwards. One copy of the art covers both directions.
2. **Compiled sprites** for the hottest frames only (idle and walk loops).
   They are generated as `LD (HL),n` / `LD A,(HL) : AND m : OR d : LD (HL),A`
   sequences, with the overscan next-line address arithmetic inlined. That is
   about 1.2 KB per frame, per facing.

Background restore: the stage is static. Each fighter saves the background
under its bounding box (dirty rectangles) before drawing, or redraws from the
stage image kept in a bank.

Target: two fighters + two projectiles + HUD updates within one 50 Hz frame
pair (25 fps ≈ 40,000 usable NOPs per frame pair).

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

### 3.4 Memory map (draft, 128K)

| Area | Size | Contents |
|---|---|---|
| &0000-&5FFF | 24K | screen 0 |
| &6000-&7FFF | 8K | engine core, interrupt handler, input, state machines |
| &8000-&DFFF | 24K | screen 1 |
| &E000-&FFFF | 8K | stack, tables (flip, pen remap, line addresses), HUD font |
| Bank 4-5 | 32K | fighter A: span-encoded frames, compiled hot frames, move data |
| Bank 6-7 | 32K | fighter B |
| (shared via paging) | | stage graphics, music + player |

The stage and music need room too. Options: compress the stage (ZX0) and
unpack it into the screens at round start, keep stage tiles in a fighter
bank's spare space, or trim per-character data to 28K. Turning this into a
firm budget is the first deliverable of milestone 1.

### 3.5 Character file format (`TRUMP.PFC` etc.)

```
header      magic "PF", version, name, personal colours (4 firmware colours)
move table  12+ moves: frame count, per-frame duration, hitbox/hurtbox,
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
| 0 | **Art pipeline + first fighters** ✅ | Trump and Putin, 12 moves, CPC data export |
| 1 | **Tech spike** | overscan screen up. Buffering option chosen. Span-sprite and compiled-sprite drawers benchmarked. Memory map frozen. Two idle fighters animating at 25 fps |
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
| Overscan + double buffer + banking doesn't fit | milestone 1 decides early. Fallback is option C (reduced height + CRTC split) |
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
