;; ===========================================================================
;; banner.asm - big words across the screen: "BEGIN FIGHT" as a round
;; starts, and as it ends "K.O.", "PERFECT" (a K.O. at full health),
;; "TIME UP" or "DRAW".
;;
;; The victory font (victory.asm), every pixel a byte wide and 4 lines
;; tall, in white with a black shadow a pixel right and down: 4 bytes and
;; 24 lines a character, centred on lines BN_TOP to BN_TOP+23, the top of
;; the fighter band. Only a jump reaches that high, so it is drawn like a
;; burst (burst.asm), outside the rebuild and only while neither fighter,
;; on the screen or next, is in its lines; the mirror puts the stage back
;; under it. It shares the burst's pass, its times and its pending byte
;; (bits 2 and 3 of BURST+F_PSTUN: take off, draw); the burst's unused
;; fields hold its state. Drawing it takes the pass's turn: the burst can
;; wait a picture. It is drawn BN_CHUNK letters a picture (all eleven of
;; BEGIN FIGHT took 12 ms, and the beam caught their top), so the words
;; appear left to right.
;; ===========================================================================

BN_TOP          EQU BAND_TOP    ; its first line (a character row's first)
BN_LINES        EQU 24          ; 5 rows of 4 lines, and the shadow's 4
BN_CLEAR        EQU BN_TOP+BN_LINES     ; a fighter's top no higher
    ASSERT (BN_TOP AND 7)==0         ; (and under the bursts: burst.asm)
BN_TEXT         EQU BURST+F_PCODE       ; which words (0: none),
BN_TIME         EQU BURST+F_PCODE+1     ; pictures left,
BN_FLAGS        EQU BURST+F_PCODEL      ; bit 0 drawn, 1 new, 2 unfinished,
BN_X            EQU BURST+F_PCODEL+1    ; where it is drawn and how wide
BN_W            EQU BURST+F_PDIR
BN_DONE         EQU BURST+F_PODIR       ; and the letters drawn so far
BN_BEGIN        EQU 1           ; the words (bn_texts)
BN_KO           EQU 2
BN_PERFECT      EQU 3
BN_TIMEUP       EQU 4
BN_EVEN         EQU 5
BN_BEGIN_PICS   EQU 40
BN_END_PICS     EQU 50          ; (gone before ROUND_END_PICS are up)
BN_CHUNK        EQU 4           ; letters a pass: ~4.5 ms

;; banner_vis - from shot_vis, once a picture: its time runs down, whether
;; it may be shown, and what the pass has to do (bits 2-3 of the pending
;; byte). Destroys AF, BC, HL.
banner_vis
    ld hl,BN_TIME               ; (from 0 it goes round again, and clears
    dec (hl)                    ; words that are long gone once more)
    jr nz,nv_time
    dec hl
    ld (hl),0                   ; (BN_TEXT) its time is up
nv_time
    ld a,(BN_TEXT)              ; C = shown: words, and both fighters
    or a                        ; below its lines, on the screen and next
    jr z,nv_want
    ld hl,fighter_a+F_Y
    call nv_fighter
    ld hl,fighter_b+F_Y
    call nv_fighter
    ld a,1
    jr nv_want
nv_no
    xor a
nv_want
    ld c,a
    ld b,0
    ld hl,BN_FLAGS
    bit 0,(hl)
    jr z,nv_draw                ; not drawn: draw it if it is shown
    bit 1,(hl)
    jr nz,nv_both               ; drawn but new: off, and on if shown
    or a
    jr z,nv_both                ; drawn and hidden: off
    bit 2,(hl)
    jr nz,nv_draw               ; drawn, shown, letters to go: on with them
    jr nv_set                   ; drawn and staying: nothing
nv_both
    ld b,4
nv_draw
    ld a,c
    or a
    jr z,nv_set
    set 3,b
nv_set
    ld a,(BURST+F_PSTUN)
    and 3
    or b
    ld (BURST+F_PSTUN),a
    ret

;; bn_draw - from burst_pass, main RAM in, in period CLEAR_IRQ: the words,
;; centred. Destroys AF, BC, DE, HL, IX.
bn_draw
    ld a,(BN_TEXT)              ; (IX is burst_pass's to put back)
    ld hl,bn_texts-1
    ld b,a
nd_find
    inc hl                      ; past the words before: length, letters
    ld a,(hl)
    dec b
    jr z,nd_got
    add a,l
    ld l,a
    jr nc,nd_find
    inc h
    jr nd_find
nd_got
    ld c,a                      ; C letters, 4 bytes each
    inc hl
    ld a,(BN_DONE)
    or a
    jr nz,nd_more               ; (where it goes: with its first letters)
    ld a,c
    add a,a
    ld b,a
    add a,a
    ld (BN_W),a
    ld a,48
    sub b
    ld (BN_X),a
    xor a
nd_more
    ld e,a                      ; on from the letters done: at most
    ld d,0                      ; BN_CHUNK more
    add hl,de
    add a,a
    add a,a
    ld b,a
    ld a,(BN_X)
    add a,b
    ld (vt_x),a
    ld a,c
    sub e
    cp BN_CHUNK+1
    jr c,nd_n
    ld a,BN_CHUNK
nd_n
    ld b,a
    add a,e
    ld (BN_DONE),a
    ld a,BN_TOP
    call vt_line
nd_char
    push bc
    push hl
    ld a,(hl)
    call bn_glyph
    ld hl,vt_x
    ld a,(hl)
    add a,4
    ld (hl),a
    pop hl
    inc hl
    pop bc
    djnz nd_char
    ld a,(BN_DONE)              ; drawn, not new; letters left: unfinished
    cp c
    ld a,1
    jr nc,nd_flags
    ld a,5
nd_flags
    ld (BN_FLAGS),a
    ret

;; bn_glyph - A = a letter at (vt_x) on the banner's lines (vt_lptr).
bn_glyph
    add a,a                     ; (letters are below 128)
    ld l,a
    ld h,0
    ld de,font-2*FONT_FIRST
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a                      ; HL = its rows, the top 3 bits first
    ld ix,(vt_lptr)
    ld c,5
ng_row
    ld a,(vt_x)
    ld d,a
    ld b,3
ng_pixel
    add hl,hl
    call c,bn_cell
    inc d
    djnz ng_pixel
    ld de,8                     ; the next row: 4 lines on
    add ix,de
    dec c
    jr nz,ng_row
    ret

bn_texts
    defb 11,"BEGIN FIGHT"
    defb 4,"K.O."
    defb 7,"PERFECT"
    defb 7,"TIME UP"
    defb 4,"DRAW"
