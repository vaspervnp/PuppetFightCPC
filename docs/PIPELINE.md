# Art Pipeline

How puppet sprites go from Blender to CPC data. See the [README](../README.md) for the project overview.

## Sprite spec

| | |
|---|---|
| Mode | 0 (160-pixel mode, 2:1 wide pixels, 16 pens) |
| Frame | 32×64 Mode 0 pixels (16 bytes × 64 lines) |
| Wide frame | 64×64 for horizontal/falling poses, drawn with `offset_x = -16` px |
| Transparency | pen 0; pen 15 is a second black used for opaque outlines |
| Palette | one shared 16-pen game palette, see `tools/cpc_palette.py` |
| Frame rate | 12 fps animation |

### Moves (all ≥ 3 frames)

| Move | Frames | Notes |
|---|---|---|
| idle | 4 | loop |
| walk | 4 | loop |
| crouch | 3 | last frame is the hold |
| jump | 3 | prep / tuck / land. The engine moves the sprite; height is not baked in |
| punch | 3 | wind-up / extend / recover |
| kick | 3 | chamber / extend / retract |
| sweep | 3 | crouching low kick |
| uppercut | 4 | dip / rise / full extension / recover. Anti-air |
| backkick | 4 | spinning mule kick: turn away, leg driven straight back at the opponent |
| block | 3 | last frame is the hold |
| hit | 3 | |
| ko | 4 | frames 2-4 are 64×64 wide frames |
| special | 4 | Trump: **Tweet Storm** (phone throw). Putin: **Judo Throw** |
| victory | 3 | Trump: thumbs-up shimmy. Putin: strongman flex |

## Pipeline

```
Blender (3D puppets, poses)  ->  art/render/<char>/*_id.png + *_lit.png
        tools/make_sprites.py  ->  art/sprites/<char>/<move>_<n>.png  (indexed, CPC palette)
  tools/aseprite_build.lua     ->  art/sprites/<char>.aseprite        (editable master, tags per move)
  tools/aseprite_export.lua    ->  art/sprites/<char>/*.png            (after hand edits)
        tools/cpc_export.py    ->  data/sprites/<char>.asm / .bin, palette.asm
        tools/preview_gif.py   ->  docs/preview_*.gif
```

1. **Blender**: `tools/blender_puppets.py` builds each puppet from rigid "felt"
   parts on a joint hierarchy in its own scene (`PF_trump`, `PF_putin`). Every
   move is keyframed (timeline markers name the moves). Each frame is rendered
   twice with Workbench: a flat material-ID pass and a white studio-lit pass.
   It also writes `art/blender/puppets.blend` with just the puppet scenes. Run
   it from the Blender MCP:
   ```python
   REPO = r"\\wsl.localhost\Ubuntu\home\vasilhs\repos\PuppetFightCPC"
   g = dict(globals(), REPO=REPO, CHARACTERS=["trump", "putin"], RENDER=True)
   exec(open(REPO + r"\tools\blender_puppets.py").read(), g)
   ```
   Poses live in `COMMON_MOVES` / `TRUMP_MOVES` / `PUTIN_MOVES` as joint angles.
2. **Quantise**: `python3 tools/make_sprites.py` maps each hi-res pixel to a
   pen (material ramp × light level), then each 8×4 block votes for one Mode 0
   pixel. Eyes and mouths get extra weight so they survive. It also adds
   separation lines where an arm crosses the body, plus a black outline.
3. **Aseprite**: `tools/aseprite_build.lua` builds a 64×64 indexed `.aseprite`
   per character with one tag per move. Touch-ups by hand go here. Then run
   `tools/aseprite_export.lua` to write the frames back out.
   Note: re-running `make_sprites.py` overwrites the PNGs, and
   `aseprite_build.lua` overwrites the `.aseprite` file, so hand edits are lost.
4. **CPC data**: `python3 tools/cpc_export.py` writes masked Mode 0 frame data
   (`(screen AND mask) OR data`), a move table and the Gate Array palette.

## Memory notes

- Raw masked frames: ~102 KB per character, 48 frames (every byte stored).
- Drawn bytes per frame: Trump avg ~350, Putin ~260. A compiled sprite
  (LD/AND/OR per byte) is about 40-47 KB per character facing one way, so a
  pair fits in a 128K machine's banks. Storing both facing directions doubles
  this. The alternatives are flipping at draw time with a 256-byte flip table
  (masked path), or having only the active facing compiled.

## Pipeline to-dos

- Compiled-sprite generator for the overscan screen layout.
- Projectiles/effects: tweet bird (Trump special), hit sparks.
- Pose polish: victory poses raise the arms sideways, toward the camera, so
  they read weakly in profile. Trump's phone is too small to see.
- More characters: add a spec + head function in `blender_puppets.py`.
