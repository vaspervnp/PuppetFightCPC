# Puppet Fight CPC - build
#
#   make          build/pfspike.sna and build/pfspike.dsk (RUN"PFSPIKE: the
#                 BASIC loader pages each character bank in and loads it)
#   make bench    run the spike on the headless 6128 and measure it
#   make run      open the snapshot in Caprice32
#
# PUTIN_DRAW=generic (default) draws Putin with the generic mirrored span
# drawer; PUTIN_DRAW=compiled uses compiled left-facing routines instead.
# CLOSE_UP=1 puts the fighters toe to toe, so both are rebuilt in one window.
# JUMP=1 makes them take turns to jump, then jump together (top at line 144).
# SLACK=n starts every rebuild n*100 us late: the margin test (SLACK=15
# must stay clean in the jump scenario).
#
#   make bench-all   every scenario the 25 fps rule has to hold in

RASM   ?= rasm
PYTHON ?= python3
PUTIN_DRAW ?= generic
CLOSE_UP ?= 0
JUMP ?= 0
SLACK ?= 0
RASMFLAGS := $(if $(filter compiled,$(PUTIN_DRAW)),-DPUTIN_COMPILED=1,-DPUTIN_COMPILED=0) \
             -DCLOSE_UP=$(CLOSE_UP) -DJUMP=$(JUMP) -DSLACK=$(SLACK)
BUILD  := build

GEN := src/gen/tables.asm src/gen/trump_bank0.asm src/gen/trump_bank1.asm \
       src/gen/putin_bank0.asm src/gen/putin_bank1.asm
SRC := $(wildcard src/*.asm) $(GEN)

all: $(BUILD)/pfspike.sna

$(BUILD):
	mkdir -p $@

src/gen/tables.asm: tools/sprite_codegen.py
	$(PYTHON) tools/sprite_codegen.py tables

# A character's two bank images come out of one run. The idle frames the
# spike shows also get compiled draws, for the facing each fighter has.
src/gen/trump_bank0.asm src/gen/trump_bank1.asm &: tools/sprite_codegen.py \
        art/sprites/trump.json $(wildcard art/sprites/trump/*.png)
	$(PYTHON) tools/sprite_codegen.py character trump --compiled-right idle_0 idle_2

src/gen/putin_bank0.asm src/gen/putin_bank1.asm &: tools/sprite_codegen.py \
        art/sprites/putin.json $(wildcard art/sprites/putin/*.png)
	$(PYTHON) tools/sprite_codegen.py character putin --compiled-left idle_0 idle_2

# One rasm pass writes the snapshot, the symbols and (via SAVE) the disc.
$(BUILD)/pfspike.sna: $(SRC) FORCE | $(BUILD)
	rm -f $(BUILD)/pfspike.dsk
	cd src && $(RASM) main.asm -oi ../$@ -s -sl -sq -os ../$(BUILD)/pfspike.sym -eo -v2 $(RASMFLAGS)
	iDSK $(BUILD)/pfspike.dsk -i src/pfspike.bas -t 0 -f >/dev/null

bench: $(BUILD)/pfspike.sna
	$(PYTHON) tools/spike_bench.py

# Apart (two windows), and toe to toe with jumps (one shared window, banded).
# Overlaps need compiled draws for both fighters: see GAME_PLAN 3.2b.
bench-all:
	$(MAKE) --no-print-directory bench
	$(MAKE) --no-print-directory bench PUTIN_DRAW=compiled CLOSE_UP=1
	$(MAKE) --no-print-directory bench PUTIN_DRAW=compiled CLOSE_UP=1 JUMP=1

run: $(BUILD)/pfspike.sna
	caprice32 $(abspath $(BUILD)/pfspike.sna)

clean:
	rm -rf $(BUILD)

FORCE:
.PHONY: all bench bench-all run clean FORCE
