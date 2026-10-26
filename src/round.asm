;; ===========================================================================
;; round.asm - rounds and the match: a KO ends the round, the winner holds
;; its victory pose for ROUND_END_PICS pictures, gets a win marker under its
;; bar, and both fighters start again. WINS_NEEDED round wins take the
;; match, and the next one starts from nothing. Cold code (COLD2_ORG).
;; ===========================================================================

ROUND_END_PICS  EQU 75          ; 3 s
WINS_NEEDED     EQU 2
MARK_LINE       EQU 18          ; win markers: under the bars, 3 x 3

;; round_tick - once a picture, after combat. Destroys everything.
round_tick
    ld a,(rnd_state)
    or a
    jr nz,rt_over
    ld ix,fighter_b             ; fighting: whoever isn't down after a KO
    ld a,(fighter_a+F_MOVE)
    cp MV_KO
    jr z,rt_ko
    ld ix,fighter_a
    ld a,(fighter_b+F_MOVE)
    cp MV_KO
    ret nz
rt_ko
    ld (rnd_winner),ix
    ld a,ROUND_END_PICS
    ld (rnd_timer),a
    ld a,1
    ld (rnd_state),a
    ld (ix+F_Y),FIGHTER_Y
    ld a,MV_VICTORY
    jp start_move
rt_over
    ld hl,rnd_timer
    dec (hl)
    ret nz
    ld ix,(rnd_winner)          ; the round to the winner
    inc (ix+F_WINS)
    call win_marker
    ld a,(ix+F_WINS)
    cp WINS_NEEDED
    jr c,rt_next
    ld ix,fighter_a             ; and the match: start again from nothing
    call clear_wins
    ld ix,fighter_b
    call clear_wins
rt_next
    xor a
    ld (rnd_state),a
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
    ld a,MV_IDLE
    call start_move
    call is_a                   ; and its bar full again
    ld hl,4+40*256
    ld c,PB_12_12
    jr z,fr_bar
    ld hl,52+40*256
    ld c,PB_4_4
fr_bar
    ld b,8
    ld de,8
    jr hud_rect

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
    ld c,PB_10_10
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
    ld c,0
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
