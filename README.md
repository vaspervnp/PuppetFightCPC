# Puppet Fight CPC

A one-on-one fighting game for the **Amstrad CPC 6128**, written in Z80
assembly. World leaders, as felt caricature puppets inspired by GZERO
Media's satire series *Puppet Regime*, fight with large pre-rendered
sprites on a full overscan screen at a locked 25 frames a second.

![Trump vs Putin preview](docs/preview_versus.gif)

> Status: **release candidate** (milestone 9). Six fighters, a boss, a
> ladder against the computer and two-player matches all work in the
> emulator. Not yet tested on a real 6128.

## Playing

Build the disc (`make`, or `make release` for a zip with the manuals), put
`build/puppetfight.dsk` in drive A of a 6128 or an emulator, and type

    RUN"PUPPET

The manual is in English ([manual.md](manual.md), [PDF](manual.pdf)) and
Greek ([manual_gr.md](manual_gr.md), [PDF](manual_gr.pdf)).

- 192 × 272 Mode 0 overscan, 32 × 64 pixel fighters (64 × 64 for falls),
  14 moves each, with combinations for the sweep, uppercut, back kick and
  special
- 1P against the computer (three levels) or 2P versus
- The ladder: win against the computer and the next opponent loads from
  the disc with its home stage, until the secret boss, the Puppet Master
- Characters are separate disc files, packed, so the roster can grow

## Fighters

| Fighter | Billing | Special |
|---|---|---|
| Donald Trump | "The Greatest American 2.0" | Tweet Storm (projectile) |
| Vladimir Putin | "Tsar of All the Puppets" | Judo Throw |
| Kim Jong-Un | "Supremest Leader" | Surf's Up Missile (projectile) |
| Xi Jinping | "President Emperor" | Belt and Road (strike) |
| Elon Musk | "Tech Support" | Chainsaw Rampage (strike) |
| Volodymyr Zelensky | "Humble President" | More Ammo! (projectile) |
| Ian Bremmer (boss) | "The Puppet Master" | G-Zero World (projectile) |

Profiles and ideas for more: [docs/CHARACTERS.md](docs/CHARACTERS.md).

## Building

Needs rasm, Python 3 with Pillow, and for the manuals `markdown` and
`fpdf2`. `make` builds the disc and a test snapshot (`build/pfspike.sna`);
`make bench-all` measures the 25 fps rule on the headless emulator
(see the Makefile for the bench options); `make manual` builds the PDFs.
The engine's design, measurements and history: [docs/SPIKE.md](docs/SPIKE.md).

## Repository layout

```
art/blender/      puppets.blend: puppet scenes (PF_<name>), poses keyframed
art/render/       Blender renders (material-ID + lit passes per frame)
art/sprites/      quantised sprite PNGs, character and hit box settings
art/stages/       the stages (stage_art.py) and their colours
src/              the engine (main.asm), the loader and select screen (loader.asm)
src/gen/          generated: banks, disc map, tables, music
docs/             game plan, roster, pipeline, engine notes, manual screenshots
tools/            pipeline, disc and bench scripts (Blender, Python, Aseprite Lua)
```

## Rebuilding the sprites

Requirements: Blender 5.2 and Aseprite 1.3 (both used through MCP in this
project), Python 3 with Pillow.

1. **Render** in Blender. This builds the puppets and renders every frame:
   ```python
   REPO = r"\\wsl.localhost\Ubuntu\home\vasilhs\repos\PuppetFightCPC"
   g = dict(globals(), REPO=REPO, CHARACTERS=["trump", "putin"], RENDER=True)
   exec(open(REPO + r"\tools\blender_puppets.py").read(), g)
   ```
2. **Quantise** to Mode 0 sprites:
   ```bash
   python3 tools/make_sprites.py
   ```
3. **Aseprite**: run `tools/aseprite_build.lua` to create the `.aseprite`
   files, edit them, then run `tools/aseprite_export.lua` to write the frames
   back out.
4. **Export** the CPC data:
   ```bash
   python3 tools/cpc_export.py
   ```
5. **Preview** GIFs:
   ```bash
   python3 tools/preview_gif.py
   ```

Details (sprite spec, palette, quantisation, memory figures):
[docs/PIPELINE.md](docs/PIPELINE.md).

## Documentation

- [Game plan](docs/GAME_PLAN.md): gameplay, controls, combat model, screen
  and memory design, character file format, toolchain, milestones, risks
- [Character roster](docs/CHARACTERS.md): researched *Puppet Regime* cast with
  personas, specials and palette notes
- [Art pipeline](docs/PIPELINE.md): Blender → Aseprite → CPC data

## Credits and disclaimer

A non-commercial fan project. The characters are caricatures inspired by
[*Puppet Regime*](https://gzeromedia.com/puppet-regime/) by GZERO Media
(Eurasia Group). This project is not affiliated with or endorsed by GZERO
Media, Eurasia Group, or any person depicted. All characters are satirical.
