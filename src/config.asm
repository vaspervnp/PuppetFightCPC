;; ===========================================================================
;; config.asm - screen geometry, memory map and the spike's scene layout.
;;
;; The overscan geometry is the one OverscanCPC proved on a real 6128:
;; 96 bytes x 272 scanlines in a 32 KB screen at #8000-#FFFF, no rupture.
;; ===========================================================================

;; --- CRTC ------------------------------------------------------------------
CRTC_R0     EQU 63          ; horizontal total - 64 us lines. Never change.
CRTC_R1     EQU 48          ; 48 chars = 96 bytes = 192 mode 0 pixels
CRTC_R2     EQU 50          ; HSYNC position
CRTC_R3     EQU #8E         ; HSYNC 14 chars, VSYNC 8 lines
CRTC_R4     EQU 38          ; 39 rows
CRTC_R5     EQU 0
CRTC_R6     EQU 34          ; 34 rows displayed = 272 lines
CRTC_R7     EQU 34          ; VSYNC straight after the last displayed row
CRTC_R8     EQU 0
CRTC_R9     EQU 7           ; 8 scanlines per row
CRTC_R12    EQU #2C         ; MA = #2C10: page 2 from #8020, rolls into
CRTC_R13    EQU #10         ; page 3 (#C000) at row 21

BYTES_PER_LINE  EQU CRTC_R1*2           ; 96
DISPLAY_ROWS    EQU CRTC_R6             ; 34
DISPLAY_LINES   EQU DISPLAY_ROWS*8      ; 272
PAGE2_ROWS      EQU 21
PAGE2_BASE      EQU #8000+32
PAGE3_BASE      EQU #C000

;; VSYNC starts right after the last displayed line, so the beam reaches
;; display line 0 forty scanlines (2.56 ms) after the frame tick.
BLANK_LINES     EQU (CRTC_R4+1)*(CRTC_R9+1)-DISPLAY_LINES

;; --- Memory map --------------------------------------------------------------
;; #0038        interrupt jump (ROMs are off, so this is RAM)
;; #0040-#00FF  low code (stream.asm), copied down from the load image
;; #0100-#01FF  the stack (it goes down to #01E0)
;; #0200-#3FFF  engine, tables, sprite data (copied down from the load image)
;; #4000-#7FFF  background mirror of the fighter band (see below)
;; #8000-#FFFF  overscan screen
;; Banks 4-7 (later): fighter data, paged in at #4000 only while drawing.
;; At boot only: the stage, packed (tools/stage_pack.py), which the select
;; screen loads to STAGE_AT and boot unpacks into the screen before it moves
;; the payload down. The compiled frame caches have it later.
STAGE_AT        EQU #2000
STAGE_ROOM      EQU SETTINGS_AT-STAGE_AT
;; The select screen's choices, after the stage: who the computer plays
;; (GM_CPU_A, GM_CPU_B) and how well (GM_LEVEL: 0-2), then the characters
;; (roster numbers). start reads them before the compiled frame caches go
;; there; ladder.asm puts them back for the next opponent.
SETTINGS_AT     EQU #3FF0
GM_CPU_A        EQU 0           ; bits of the settings (game_mode)
GM_CPU_B        EQU 1
GM_LEVEL        EQU 2           ; bits 2-3
ST_INKS         EQU 3           ; a stage file: hardware inks of pens 0, 14
ST_DATA         EQU 8           ; and 15, then (after the length) the data
PAYLOAD_ORG     EQU #0200
LOAD_ORG        EQU #4000
STACK_TOP       EQU #0200       ; grows down from just under the payload
LOW_ORG         EQU #0040
LOW_ROOM        EQU #0100-LOW_ORG

;; --- Floor, fighter band and background mirror ---------------------------
;; Every stage has a raised floor: the bottom FLOOR_H lines are floor, never
;; fighters. The bottom of a full overscan picture is cut off on some
;; emulators and monitors (RVM), so nothing that matters is drawn there.
FLOOR_H         EQU 60
FLOOR_Y         EQU DISPLAY_LINES-FLOOR_H   ; 212: the fighters' feet
SPR_W           EQU 16          ; bytes (32 mode 0 pixels)
SPR_H           EQU 64
FIGHTER_Y       EQU FLOOR_Y-SPR_H           ; 148: a standing fighter's top
JUMP_MAX        EQU 60                      ; a jump's top is BAND_TOP
BAND_TOP        EQU FIGHTER_Y-JUMP_MAX      ; 88
BAND_BOTTOM        EQU FLOOR_Y                 ; first line below the band

;; Lines BAND_TOP..BAND_BOTTOM-1 can hold a fighter. Their background is copied
;; once into #4000-#7FFF at the screen address with H = (H AND #3F) OR #40:
;; page 3 rows 21-26 use offsets #000-#23F of each 2 KB slice, page 2 rows
;; 11-20 use #440-#7FF, so the two never collide (#240-#43F stays free).
;; Restoring a sprite is then a straight copy from the mirror: no save
;; buffers, and fighters can overlap.
MIRROR_H_AND    EQU #3F
MIRROR_H_OR     EQU #40
    ASSERT BAND_TOP>=11*8 && BAND_BOTTOM<=27*8

;; --- When a rebuild starts -------------------------------------------------
;; Not on the frame tick (VSYNC) but on an interrupt while the beam is low
;; on the fighters. Interrupts come every 52 lines, the first two lines into
;; VSYNC (line 274), so the fourth after it falls on line 170 and the fifth
;; on line 222, 10 lines into the floor. The rebuild starts on the fourth:
;; the beam has passed every line above it, and needs 142 + L lines to reach
;; line L again (14.7 ms to the top of a jump). Lines from GUARD_LINE down
;; wait for the fifth, when the beam has passed the whole band (rebuild.asm).
TICK_IRQ        EQU 4
TICK_LINE       EQU 170
CLEAR_IRQ       EQU TICK_IRQ+1  ; the beam below the band
CLEAR_LINE      EQU TICK_LINE+52
    ASSERT CLEAR_LINE>=BAND_BOTTOM
GUARD_LINE      EQU TICK_LINE-2 ; (a line in hand for the interrupt's time)

;; line_tab (272 words, built at boot) lives in the unused tail of the first
;; 2 KB slice of screen page 3: rows 21-33 fill #C000-#C4DF of every slice,
;; and the CRTC never fetches #C4E0-#C7FF.
LINE_TAB_AT     EQU #C4E0
;; The same unused tails of later slices hold the restore lists that
;; prebuild makes (4 bytes per scanline, at most 64 lines), two per fighter
;; #1000 apart, and the dummy byte an empty line copies into.
RESTORE_LIST_A  EQU #CCE0       ; slices 1 and 3: #xCE0-#xFFF free
RESTORE_LIST_B  EQU #E4E0       ; slices 4 and 6: #x4E0-#x7FF free
RESTORE_FLIP    EQU #10         ; high byte: one list of a pair to the other
    ASSERT (RESTORE_LIST_A AND #FF)==(RESTORE_LIST_B AND #FF)
RESTORE_DUMMY   EQU #C7FF       ; past line_tab in slice 0
WORK_AT         EQU (RESTORE_LIST_A XOR #1000)+256  ; #DDE0: workspace,
WORK_ROOM       EQU #E000-WORK_AT   ; past list A1 in slice 3's tail
COLD_ORG        EQU (RESTORE_LIST_B)+256    ; #E5E0: cold code (combat.asm),
COLD_ROOM       EQU #E800-COLD_ORG          ; past list B0 in slice 4's tail
COLD2_ORG       EQU (RESTORE_LIST_B XOR #1000)+256  ; #F5E0: round.asm, past
    ASSERT COLD2_ORG+COLD_ROOM<=#F800               ; list B1 in slice 6
;; The mirror leaves #x240-#x43F of each 2 KB slice free (above). Those
;; gaps hold the logic, which only runs with main RAM at #4000: never code
;; that pages a character's bank in, or that the rebuild or an interrupt
;; runs. Boot copies it from the load image by way of GAP_SCRATCH, where
;; the packed stage was (boot has unpacked it by then), and the compiled
;; frame caches go later.
GAP_ROOM        EQU #200
GAP_SCRATCH     EQU STAGE_AT
GAP1_ORG        EQU #6240
GAP2_ORG        EQU #6A40
GAP3_ORG        EQU #7240
GAP4_ORG        EQU #7A40
GAP5_ORG        EQU #5240
GAP6_ORG        EQU #4240
GAP7_ORG        EQU #4A40
GAP8_ORG        EQU #5A40
flip_tab        EQU #CE00       ; built at boot (make_tables), in the rest
mask_tab        EQU #CF00       ; of slice 1's tail: page aligned
    ASSERT RESTORE_LIST_A+256<=flip_tab

;; Compiled frame caches (jit.asm). Each fighter has slots at the top of
;; main RAM below the mirror, which take any frame, and the slots its
;; character's directory puts at the top of bank 1, which take the frames
;; whose spans are in bank 1 (Trump 3, Putin 6, at most BANK1_SLOTS). A
;; slot fits any frame's compiled draw in either facing
;; (tools/sprite_codegen.py checks: --slot). start splits the main slots
;; so that both fighters have about as many in all.
MAIN_SLOTS      EQU 6           ; in main RAM, for both
BANK1_SLOTS     EQU 6           ; at most, per character (sprite_codegen.py)
CACHE_SLOT      EQU 1744
CACHE_AT        EQU #4000-MAIN_SLOTS*CACHE_SLOT
MAX_SLOTS       EQU 9           ; main + bank 1, per fighter
    ASSERT MAIN_SLOTS+2*BANK1_SLOTS<=18     ; (s, n) tables: 3 tails of 6
    ASSERT 2*MAX_SLOTS>=MAIN_SLOTS+2*BANK1_SLOTS
GUESS_AGE       EQU 96          ; uses of the cache (~40 pictures) before a
                                ; slot may go to a guessed frame
;; The slot tables live after line_tab in slice 0 (#C700-#C7FE), and each
;; slot's (s, n) table, which the compiler writes for build_restore, in the
;; tails of slices 2, 5 and 7: six 130-byte tables in each.
SLOT_TAB_A      EQU #C700
SLOT_TAB_B      EQU SLOT_TAB_A+MAX_SLOTS*9
    ASSERT SLOT_TAB_B+MAX_SLOTS*9<=RESTORE_DUMMY
SN_SIZE         EQU 2+2*SPR_H
SN_TAIL0        EQU #D4E0
SN_TAIL1        EQU #ECE0
SN_TAIL2        EQU #FCE0
    ASSERT 6*SN_SIZE<=#320

;; --- Spike scene ---------------------------------------------------------
HUD_LINES       EQU 24
TRUMP_X0        EQU 20
    IFNDEF CLOSE_UP
CLOSE_UP        EQU 0
    ENDIF
    IFNDEF JUMP
JUMP            EQU 0           ; -DJUMP=1: they take turns to jump, then
    ENDIF                       ; jump together (implies a shared window)
    IF CLOSE_UP                 ; -DCLOSE_UP=1: toe to toe, so their ground
PUTIN_X0        EQU TRUMP_X0+14 ; overlaps and both share one window
    ELSE
PUTIN_X0        EQU 60
    ENDIF

;; --- Mode 0 bytes: both pixels of pen a,b (left,right) ---------------------
;; Pens (GAME_PLAN 3.3, tools/cpc_palette.py): 0 background black, 1-5 shared
;; fighter pens (outline black, white, navy, dark red, grey), 6-9 fighter A's
;; own colours, 10-13 fighter B's, 14-15 the stage's (pastel blue, green).
;; The first own colour of each fighter is its health bar.
PB_14_14 EQU #3F
PB_14_2  EQU #2E
PB_2_14  EQU #1D
PB_5_5   EQU #F0
PB_15_3  EQU #EE
PB_3_15  EQU #DD
PB_2_2   EQU #0C
PB_15_15 EQU #FF
PB_3_3   EQU #CC
PB_1_1   EQU #C0
PB_5_3   EQU #E4
PB_6_6   EQU #3C
PB_10_10 EQU #0F

;; --- Bench phases (tools/spike_bench.py watches bench_phase) ---------------
PH_IDLE         EQU 0
PH_RESTORE_A    EQU 1
PH_RESTORE_B    EQU 2
PH_DRAW_A       EQU 3
PH_DRAW_B       EQU 4
PH_LOGIC        EQU 5
PH_SCHED        EQU 6           ; the banded scheduler between jobs
PH_PREPARE      EQU 7           ; job set-up for the next picture
PH_PREBUILD     EQU 8           ; restore lists for the next set-up
PH_COMPILE      EQU 9           ; the runtime compiler
PH_SHOT         EQU 10          ; a projectile's restore or draw

    IFNDEF CPU
CPU             EQU 0           ; -DCPU=n: the computer plays A (1), B (2),
    ENDIF                       ; or both (3), at -DLEVEL=0-2
    IFNDEF LEVEL
LEVEL           EQU 1
    ENDIF
    IFNDEF QUICKWIN
QUICKWIN        EQU 0
    ENDIF
    IFNDEF DEMO
DEMO            EQU 0           ; -DDEMO=1: scripted fighters (the bench)
    ENDIF
    IFNDEF SHOTS
SHOTS           EQU 0           ; -DSHOTS=1: projectiles sweep across too
    ENDIF
    IFNDEF SLACK
SLACK           EQU 0           ; -DSLACK=n: margin test, rebuild n*100 us late
    ENDIF

;; --- Copies of the -D build options, so they reach the symbol file ---------
;; (rasm exports EQUs with -sq, but not command-line defines.)
SCN_CLOSE_UP    EQU CLOSE_UP
SCN_JUMP        EQU JUMP
SCN_DEMO        EQU DEMO
SCN_SHOTS       EQU SHOTS
