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
;; #0200-#3FFF  engine, tables, sprite data (copied down from the load image)
;; #4000-#7FFF  background mirror of the fighter band (see below)
;; #8000-#FFFF  overscan screen
;; Banks 4-7 (later): fighter data, paged in at #4000 only while drawing.
PAYLOAD_ORG     EQU #0200
LOAD_ORG        EQU #4000
STACK_TOP       EQU #0200       ; grows down from just under the payload

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
;; Not on the frame tick (VSYNC) but on the interrupt just after the beam
;; has passed the fighters' lowest line. Interrupts come every 52 lines,
;; the first two lines into VSYNC (line 274), so the fifth after it falls on
;; line 222: 10 lines into the floor. From there the beam needs 90 + L lines
;; to reach line L again: 15.2 ms to a standing fighter's top, 11.4 ms to
;; the top of a jump.
TICK_IRQ        EQU 5
TICK_LINE       EQU 222
    ASSERT TICK_LINE>=BAND_BOTTOM

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
flip_tab        EQU #CE00       ; built at boot (make_tables), in the rest
mask_tab        EQU #CF00       ; of slice 1's tail: page aligned
    ASSERT RESTORE_LIST_A+256<=flip_tab

;; Compiled frame caches (jit.asm). Each fighter has slots at the top of
;; main RAM below the mirror, which take any frame, and the slots its
;; character's directory puts at the top of bank 1, which take the frames
;; whose spans are in bank 1 (Trump 3, Putin 5). A slot fits any frame's
;; compiled draw in either facing (tools/sprite_codegen.py checks: --slot).
CACHE_SLOTS_A   EQU 4           ; main RAM slots: Trump,
CACHE_SLOTS_B   EQU 2           ; Putin (who has more in bank 1)
CACHE_SLOT      EQU 1744
CACHE_AT        EQU #4000-(CACHE_SLOTS_A+CACHE_SLOTS_B)*CACHE_SLOT
MAX_SLOTS       EQU 8           ; main + bank 1, per fighter
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
PB_13_13 EQU #F3
PB_11_11 EQU #CF
PB_13_11 EQU #E7
PB_11_13 EQU #DB
PB_14_14 EQU #3F
PB_14_8  EQU #2B
PB_8_14  EQU #17
PB_9_9   EQU #C3
PB_9_1   EQU #C2
PB_12_12 EQU #33
PB_4_4   EQU #30
PB_10_10 EQU #0F
PB_1_1   EQU #C0
PB_2_2   EQU #0C

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

    IFNDEF DEMO
DEMO            EQU 0           ; -DDEMO=1: scripted fighters (the bench)
    ENDIF
    IFNDEF SLACK
SLACK           EQU 0           ; -DSLACK=n: margin test, rebuild n*100 us late
    ENDIF

;; --- Copies of the -D build options, so they reach the symbol file ---------
;; (rasm exports EQUs with -sq, but not command-line defines.)
SCN_CLOSE_UP    EQU CLOSE_UP
SCN_JUMP        EQU JUMP
SCN_DEMO        EQU DEMO
