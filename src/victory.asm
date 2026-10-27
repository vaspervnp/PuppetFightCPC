;; ===========================================================================
;; victory.asm - the end of a match: when a round win takes it, the HUD
;; gives way to the winner's two lines from its character file ("NAME
;; WINS!" in its first colour, its taunt in white, start copied them to
;; taunt_a / taunt_b). The winner holds its victory pose for VICTORY_PICS,
;; then the HUD comes back and the next match starts.
;;
;; Text is a 3 x 5 pixel font, like the clock's digits, 2 lines a pixel
;; row, centred. Cold code in a gap of the background mirror (GAP5_ORG).
;; ===========================================================================

VICTORY_PICS    EQU 200         ; 8 s
VT_LINE1        EQU 2           ; the two text lines
VT_LINE2        EQU 13
FONT_FIRST      EQU ' '
FONT_CHARS      EQU 'Z'+1-FONT_FIRST

;; victory - IX = the winner of the match, from round_tick. Destroys
;; everything.
victory
    push ix
    ld hl,song_win
    call music_play             ; (it takes IX)
    pop ix
    ld a,2
    ld (rnd_state),a
    ld a,VICTORY_PICS
    ld (rnd_timer),a
    call is_a
    ld hl,taunt_a
    ld a,#28                    ; pen 6, the left pixel: A's first colour
    jr z,vi_lines
    ld hl,taunt_b
    ld a,#0A                    ; pen 10: B's
vi_lines
    push af
    push hl
    call hud_clear
    pop hl
    pop af
    ld (vt_on),a
    ld a,VT_LINE1
    call vt_text
    ld a,#08                    ; pen 2: white
    ld (vt_on),a
    ld a,VT_LINE2
    ; fall into vt_text

;; vt_text - HL = a line (length, characters), A = its first scanline,
;; (vt_on) = the text's pen as a left pixel: draw it centred on pen 1.
;; HL ends past the line. Destroys AF, BC, DE, IX.
vt_text
    ld e,a
    ld d,0
    push hl
    ld hl,LINE_TAB_AT
    add hl,de
    add hl,de
    ld (vt_lptr),hl
    pop hl
    ld b,(hl)                   ; x = 48 - length: 2 bytes a character
    inc hl
    ld a,48
    sub b
    ld (vt_x),a
vt_char
    push bc
    ld a,(hl)
    inc hl
    push hl
    call vt_glyph
    ld hl,vt_x
    inc (hl)
    inc (hl)
    pop hl
    pop bc
    djnz vt_char
    ret

;; vt_glyph - A = a character at (vt_x) on the line (vt_lptr) points at.
vt_glyph
    sub FONT_FIRST
    cp FONT_CHARS
    jr c,vg_ok
    xor a
vg_ok
    add a,a
    ld l,a
    ld h,0
    ld de,font
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a                      ; HL = its rows, the top 3 bits first
    ld ix,(vt_lptr)
    ld a,(vt_x)
    ld c,a
    ld b,5
vg_row
    xor a                       ; the row's 3 bits into A
    add hl,hl
    rla
    add hl,hl
    rla
    add hl,hl
    rla
    push hl
    call vt_bits
    call dc_line                ; round.asm: E, D at x C, IX to the next
    call dc_line
    pop hl
    djnz vg_row
    ret

;; vt_bits - A = 3 pixels (bit 2 left): E, D = the two Mode 0 bytes, on in
;; (vt_on), off in pen 1, the 4th pixel off. Destroys AF, L.
vt_bits
    ld l,a
    ld a,(vt_on)
    bit 2,l
    jr nz,vb_l
    ld a,#80
vb_l
    ld e,a
    ld a,(vt_on)                ; a right pixel is the left one's bits >> 1
    srl a
    bit 1,l
    jr nz,vb_m
    ld a,#40
vb_m
    or e
    ld e,a
    ld a,(vt_on)
    bit 0,l
    jr nz,vb_r
    ld a,#80
vb_r
    or #40
    ld d,a
    ret

;; victory_tick - each picture of the victory: at the end, the HUD back
;; and the next match, or the next opponent if the player beat the
;; computer (ladder.asm).
victory_tick
    ld hl,rnd_timer
    dec (hl)
    ret nz
    ld a,(game_mode)
    and 1<<GM_CPU_A|1<<GM_CPU_B
    cp 1<<GM_CPU_B
    jr nz,vt_again
    ld hl,(rnd_winner)
    ld de,fighter_a
    or a
    sbc hl,de
    jp z,next_match
vt_again
    call hud_clear
    ld ix,fighter_a
    call clear_wins
    ld ix,fighter_b
    call clear_wins
    ld hl,song_fight            ; the fight's music from the start
    call music_play
    jp rt_next

;; hud_clear - the HUD's lines all black. Destroys AF, BC, DE, HL.
hud_clear
    ld de,0
    ld b,HUD_LINES
    ld hl,BYTES_PER_LINE*256
    ld c,PB_1_1
    jp hud_rect

;; The font: per character from FONT_FIRST, 5 rows of 3 pixels (bit 2 on
;; the left), top row first, as a word shifted left once.
    MACRO GLYPH r0,r1,r2,r3,r4
    defw (({r0}<<12)|({r1}<<9)|({r2}<<6)|({r3}<<3)|{r4})<<1
    MEND
font
    GLYPH 0,0,0,0,0             ; space
    GLYPH 2,2,2,0,2             ; !
    GLYPH 0,0,0,0,0             ; "
    GLYPH 0,0,0,0,0             ; #
    GLYPH 0,0,0,0,0             ; $
    GLYPH 0,0,0,0,0             ; %
    GLYPH 0,0,0,0,0             ; &
    GLYPH 2,2,0,0,0             ; '
    GLYPH 0,0,0,0,0             ; (
    GLYPH 0,0,0,0,0             ; )
    GLYPH 0,0,0,0,0             ; *
    GLYPH 0,0,0,0,0             ; +
    GLYPH 0,0,0,2,4             ; ,
    GLYPH 0,0,7,0,0             ; -
    GLYPH 0,0,0,0,2             ; .
    GLYPH 0,0,0,0,0             ; /
    GLYPH 7,5,5,5,7             ; 0
    GLYPH 2,6,2,2,7
    GLYPH 7,1,7,4,7
    GLYPH 7,1,3,1,7
    GLYPH 5,5,7,1,1
    GLYPH 7,4,7,1,7
    GLYPH 7,4,7,5,7
    GLYPH 7,1,1,2,2
    GLYPH 7,5,7,5,7
    GLYPH 7,5,7,1,7             ; 9
    GLYPH 0,2,0,2,0             ; :
    GLYPH 0,0,0,0,0             ; ;
    GLYPH 0,0,0,0,0             ; <
    GLYPH 0,0,0,0,0             ; =
    GLYPH 0,0,0,0,0             ; >
    GLYPH 6,1,2,0,2             ; ?
    GLYPH 0,0,0,0,0             ; @
    GLYPH 2,5,7,5,5             ; A
    GLYPH 6,5,6,5,6
    GLYPH 3,4,4,4,3
    GLYPH 6,5,5,5,6
    GLYPH 7,4,6,4,7
    GLYPH 7,4,6,4,4
    GLYPH 3,4,5,5,3
    GLYPH 5,5,7,5,5
    GLYPH 7,2,2,2,7
    GLYPH 1,1,1,5,2
    GLYPH 5,5,6,5,5
    GLYPH 4,4,4,4,7
    GLYPH 5,7,7,5,5
    GLYPH 6,5,5,5,5
    GLYPH 2,5,5,5,2
    GLYPH 7,5,7,4,4
    GLYPH 2,5,5,6,3
    GLYPH 6,5,6,5,5
    GLYPH 3,4,2,1,6
    GLYPH 7,2,2,2,2
    GLYPH 5,5,5,5,7
    GLYPH 5,5,5,5,2
    GLYPH 5,5,7,7,5
    GLYPH 5,5,2,5,5
    GLYPH 5,5,2,2,2
    GLYPH 7,1,2,4,7             ; Z
