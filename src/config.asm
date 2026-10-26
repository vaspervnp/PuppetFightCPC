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

;; --- Fighter band and background mirror ------------------------------------
;; Lines BAND_TOP..271 can hold a fighter. Their background is copied once
;; into #4000-#7FFF at the screen address with H = (H AND #3F) OR #40: page 3
;; rows 21-33 use offsets #000-#4DF of each 2 KB slice, page 2 rows 18-20 use
;; #6E0-#7FF, so the two halves never collide. Restoring a sprite is then a
;; straight copy from the mirror: no save buffers, and fighters can overlap.
BAND_TOP        EQU 144
MIRROR_H_AND    EQU #3F
MIRROR_H_OR     EQU #40

;; --- Sprites -----------------------------------------------------------------
SPR_W           EQU 16          ; bytes (32 mode 0 pixels)
SPR_H           EQU 64
FLOOR_Y         EQU 268         ; feet; a standing fighter's top is 204
FIGHTER_Y       EQU FLOOR_Y-SPR_H

;; --- Spike scene ---------------------------------------------------------
HUD_LINES       EQU 24
SKY_END         EQU 200
HORIZON_END     EQU 204
TRUMP_X0        EQU 20
    IFNDEF CLOSE_UP
CLOSE_UP        EQU 0
    ENDIF
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

;; --- Bench phases (tools/spike_bench.py watches bench_phase) ---------------
PH_IDLE         EQU 0
PH_RESTORE_A    EQU 1
PH_RESTORE_B    EQU 2
PH_DRAW_A       EQU 3
PH_DRAW_B       EQU 4
PH_LOGIC        EQU 5
