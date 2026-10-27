;; ===========================================================================
;; round.asm - rounds and the match: a KO (down with no health) ends the
;; round, and so does the clock running out after ROUND_SECS seconds, when
;; more health wins (the same health: a draw, nobody's round). The winner
;; holds its victory pose for ROUND_END_PICS pictures, gets a win marker
;; under its bar, and both fighters start again. WINS_NEEDED round wins
;; take the match: the victory screen (victory.asm), then the next match
;; starts from nothing. Cold code
;; (COLD2_ORG).
;; ===========================================================================

ROUND_END_PICS  EQU 75          ; 3 s
WINS_NEEDED     EQU 2
MARK_LINE       EQU 18          ; win markers: under the bars, 3 x 3
ROUND_SECS      EQU #99         ; the clock, BCD
PICS_PER_SEC    EQU 25
CLOCK_LINE      EQU 5           ; its digits: 3 x 5 pixels, 3 lines a row,
CLOCK_X         EQU 46          ; between the bars

;; round_tick - once a picture, after combat. Destroys everything.
round_tick
    ld a,(rnd_state)
    or a
    jr nz,rt_over
    IF QUICKWIN                 ; QUICKWIN=1 (a test disc): player 1 wins
    ld ix,fighter_a             ; every match at once, so the ladder runs
    ld (rnd_winner),ix          ; by itself
    jp victory
    ENDIF
    ld ix,fighter_b             ; fighting: whoever isn't down after a KO
    ld hl,fighter_a
    call rt_out
    jr z,rt_ko
    ld ix,fighter_a
    ld hl,fighter_b
    call rt_out
    jr z,rt_ko
    ld hl,rnd_tick              ; nobody down: the clock
    dec (hl)
    ret nz
    ld (hl),PICS_PER_SEC
    ld a,(rnd_secs)
    sub 1
    daa
    ld (rnd_secs),a
    push af
    call draw_clock
    pop af
    ret nz
    ld a,(fighter_a+F_HEALTH)   ; time: more health wins
    ld hl,fighter_b+F_HEALTH
    cp (hl)
    ld ix,fighter_a
    jr z,rt_draw
    jr nc,rt_ko
    ld ix,fighter_b
rt_ko
    ld (rnd_winner),ix
    call rt_end
    ld (ix+F_Y),FIGHTER_Y
    ld a,MV_VICTORY
    jp start_move
rt_draw
    ld hl,0
    ld (rnd_winner),hl
rt_end
    ld a,ROUND_END_PICS
    ld (rnd_timer),a
    ld a,1
    ld (rnd_state),a
    ret
rt_over
    cp 2                        ; the match is over: victory.asm
    jp z,victory_tick
    ld hl,rnd_timer
    dec (hl)
    ret nz
    ld hl,(rnd_winner)          ; the round to the winner, if any
    ld a,h
    or l
    jr z,rt_next
    push hl
    pop ix
    inc (ix+F_WINS)
    call win_marker
    ld a,(ix+F_WINS)
    cp WINS_NEEDED
    jp nc,victory               ; and the match (victory.asm)
rt_next
    ld a,SFX_BELL               ; the next round
    call sfx_play
    xor a
    ld (rnd_state),a
    call clock_reset
    ld ix,fighter_a
    ld a,TRUMP_X0
    ld b,0
    call fighter_reset
    ld ix,fighter_b
    ld a,PUTIN_X0
    ld b,1
    ; fall into fighter_reset

;; fighter_reset - IX = fighter, A = x, B = facing: on its feet, full health.
fighter_reset
    ld (ix+F_X),a
    ld (ix+F_FACE),b
    ld (ix+F_Y),FIGHTER_Y
    ld (ix+F_JX),0
    ld (ix+F_HEALTH),HEALTH_MAX
    ld (ix+F_STUN),0
    ld (ix+F_PACT),0            ; no projectile left flying
    ld a,MV_IDLE
    call start_move
    call is_a                   ; and its bar full again
    ld hl,4+40*256
    ld c,PB_6_6
    jr z,fr_bar
    ld hl,52+40*256
    ld c,PB_10_10
fr_bar
    ld b,8
    ld de,8
    jp hud_rect

;; clock_reset - the clock back to ROUND_SECS, on the screen too.
;; draw_clock - its two digits. Destroy AF, BC, DE, HL.
clock_reset
    ld a,ROUND_SECS
    ld (rnd_secs),a
    ld a,PICS_PER_SEC
    ld (rnd_tick),a
draw_clock
    push ix
    ld a,(rnd_secs)
    rrca
    rrca
    rrca
    rrca
    and 15
    ld c,CLOCK_X
    call dc_digit
    ld a,(rnd_secs)
    and 15
    ld c,CLOCK_X+2
    call dc_digit
    pop ix
    ret

;; dc_digit - A = digit, C = x: 5 rows, each three lines of 2 bytes.
dc_digit
    ld l,a
    add a,a
    add a,a
    add a,l
    ld e,a
    ld d,0
    ld hl,digits
    add hl,de                   ; HL = its rows
    ld ix,LINE_TAB_AT+CLOCK_LINE*2
    ld b,5
dc_row
    ld a,(hl)                   ; the row's 3 pixels as 2 bytes
    inc hl
    push hl
    add a,a
    ld e,a
    ld d,0
    ld hl,row_bytes
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    call dc_line
    call dc_line
    call dc_line
    pop hl
    djnz dc_row
    ret

;; dc_line - E, D at x C of the line IX points at in line_tab; IX to the
;; next. Destroys AF, HL.
dc_line
    ld a,(ix+0)
    add a,c
    ld l,a
    ld a,(ix+1)
    adc a,0
    ld h,a
    inc ix
    inc ix
    ld (hl),e
    inc hl
    ld (hl),d
    ret

digits                          ; 3 pixels a row (bit 2 left), 5 rows
    defb 7,5,5,5,7, 2,6,2,2,7, 7,1,7,4,7, 7,1,3,1,7, 5,5,7,1,1
    defb 7,4,7,1,7, 7,4,7,5,7, 7,1,1,2,2, 7,5,7,5,7, 7,5,7,1,7
row_bytes                       ; the 3 pixels in pen 2 (white) on pen 1
    defb #C0,#C0, #C0,#48, #84,#C0, #84,#48   ; (black): two Mode 0 bytes,
    defb #48,#C0, #48,#48, #0C,#C0, #0C,#48   ; the 4th pixel blank

;; win_marker - IX = fighter: the marker for its latest round win.
win_marker
    ld a,(ix+F_WINS)
    dec a
    add a,a
    add a,a                     ; 4 bytes apart
    ld c,a
    call is_a
    ld a,4                      ; A: from the left end of its bar
    jr z,wm_x
    ld a,89                     ; B: from the right end of its bar
    sub c
    sub c
wm_x
    add a,c
    ld l,a
    ld h,3
    ld c,PB_2_2
    jr wm_draw

;; clear_wins - IX = fighter: no wins, no markers.
clear_wins
    ld (ix+F_WINS),0
    call is_a
    ld l,4
    jr z,cw_x
    ld l,85
cw_x
    ld h,7
    ld c,PB_1_1                 ; the HUD's black
wm_draw
    ld b,3
    ld de,MARK_LINE
    ; fall into hud_rect

;; hud_rect - DE = first line, B = lines, L = x, H = width, C = byte.
;; Destroys AF, BC, DE, HL.
hud_rect
    ld a,b
    ld (fr_h),a
    ld a,l
    ld (fr_x),a
    ld a,h
    ld (fr_w),a
    ld a,c
    ld (fr_b),a
    ex de,hl
    jp fill_rect

;; is_a - IX = fighter: Z if it is fighter A. Destroys AF, DE, HL.
is_a
    push ix
    pop hl
    ld de,fighter_a
    or a
    sbc hl,de
    ret

;; rt_out - HL = fighter: Z if it is knocked out (down, no health), not
;; just knocked down. Destroys AF, DE, HL.
rt_out
    ld de,F_MOVE
    add hl,de
    ld a,(hl)
    cp MV_KO
    ret nz
    ld de,F_HEALTH-F_MOVE
    add hl,de
    ld a,(hl)
    or a
    ret
