# Puppet Fight CPC - build
#
#   make          build/pfspike.sna and build/pfspike.dsk (RUN"PFSPIKE: the
#                 BASIC loader pages each character bank in and loads it)
#   make bench    run the spike on the headless 6128 and measure it
#   make run      open the snapshot in Caprice32
#
# DEMO=1 replaces the controls with a script (idle, swaying); the bench
# scenarios use it.
# CLOSE_UP=1 puts the fighters toe to toe, so both are rebuilt in one window.
# JUMP=1 makes them take turns to jump, then jump together (top at line 144).
# SLACK=n starts every rebuild n*100 us late: the margin test (SLACK=15
# must stay clean in the jump scenario).
#
#   make bench-all   every scenario the 25 fps rule has to hold in

RASM   ?= rasm
PYTHON ?= python3
CLOSE_UP ?= 0
JUMP ?= 0
DEMO ?= 0
SLACK ?= 0
CACHE_SLOT := $(shell awk '$$1=="CACHE_SLOT"{print $$3}' src/config.asm)
RASMFLAGS := -DCLOSE_UP=$(CLOSE_UP) -DJUMP=$(JUMP) -DSLACK=$(SLACK) -DDEMO=$(DEMO)
BUILD  := build

GEN := src/gen/trump_bank0.asm src/gen/trump_bank1.asm \
       src/gen/putin_bank0.asm src/gen/putin_bank1.asm
SRC := $(wildcard src/*.asm) $(GEN)

all: $(BUILD)/pfspike.sna

$(BUILD):
	mkdir -p $@

src/gen/tables.asm: tools/sprite_codegen.py
	$(PYTHON) tools/sprite_codegen.py tables

# A character's two bank images come out of one run. Draws are compiled at
# run time (src/jit.asm); --slot checks every frame fits a cache slot.
src/gen/trump_bank0.asm src/gen/trump_bank1.asm &: tools/sprite_codegen.py \
        art/sprites/trump.json $(wildcard art/sprites/trump/*.png)
	$(PYTHON) tools/sprite_codegen.py character trump --slot $(CACHE_SLOT)

src/gen/putin_bank0.asm src/gen/putin_bank1.asm &: tools/sprite_codegen.py \
        art/sprites/putin.json $(wildcard art/sprites/putin/*.png)
	$(PYTHON) tools/sprite_codegen.py character putin --slot $(CACHE_SLOT)

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
	$(MAKE) --no-print-directory bench DEMO=1
	$(MAKE) --no-print-directory bench DEMO=1 CLOSE_UP=1
	$(MAKE) --no-print-directory bench DEMO=1 CLOSE_UP=1 JUMP=1

run: $(BUILD)/pfspike.sna
	caprice32 $(abspath $(BUILD)/pfspike.sna)

clean:
	rm -rf $(BUILD)

FORCE:
.PHONY: all bench bench-all bench-play run clean FORCE

# The game with scripted controls: walk in, jump over, attacks. Close combat
# needs the runtime compiler (only idle frames have compiled draws), so this
# reports caught lines rather than gating on them.
PLAY_KEYS := RIGHT@2-26,a@2-20,SPACE@30,z@34,x@40,DOWN@46-56,x@48,DOWN@60-64,SPACE@62,UP@70-71,RIGHT@70-80,LEFT@86-90,x@88
bench-play:
	$(MAKE) --no-print-directory $(BUILD)/pfspike.sna
	$(PYTHON) tools/spike_bench.py --keys $(PLAY_KEYS) --shots 20,31,50,76,90 || true
