;; ===========================================================================
;; burstdraw.asm - a burst's outline (burst.asm). In a gap of the background
;; mirror (GAP2_ORG): burst_pass has paged main RAM in.
;; ===========================================================================

;; burst_draw - IX = BURST, main RAM in (burst_pass): its outline, a pixel
;; of black edge and white inside (black on its first and last lines),
;; line by line from burst_shape, then its
;; word (burstvis.asm bd_word). Destroys AF, BC, DE, HL, IX.
burst_draw
    ld a,(ix+F_PY)
    ld (ix+F_POY),a
    push af
    call vt_line                ; victory.asm
    ld a,(ix+F_PX)
    ld (ix+F_POX),a
    ld c,a
    push ix
    ld ix,(vt_lptr)
    ld de,burst_shape
    ld b,BURST_H
bd_row
    ld a,b                      ; the first and last lines all black
    dec a
    jr z,bd_dark
    cp BURST_H-1
bd_dark
    ld a,PB_2_2
    jr nz,bd_fill
    ld a,PB_1_1
bd_fill
    ld (bd_byte+1),a
    ld a,(de)                   ; insets: left (high nibble), right
    inc de
    push de
    push bc
    ld b,a
    and 15
    ld d,a
    ld a,b
    rrca
    rrca
    rrca
    rrca
    and 15
    ld e,a
    add a,d
    neg
    add a,BURST_W-2
    ld b,a                      ; bytes inside the edges
    ld a,(ix+0)
    add a,c
    ld l,a
    ld a,(ix+1)
    adc a,0
    ld h,a
    ld d,0
    add hl,de
    ld (hl),PB_1_2
bd_white
    inc hl
bd_byte
    ld (hl),PB_2_2              ; (patched: the line's inside)
    djnz bd_white
    inc hl
    ld (hl),PB_2_1
    inc ix
    inc ix
    pop bc
    pop de
    djnz bd_row
    pop ix
    pop af
    jp bd_word
