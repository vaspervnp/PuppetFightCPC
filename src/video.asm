;; ===========================================================================
;; video.asm - line table, the HUD's bars, and the background mirror.
;; ===========================================================================

;; line_addr - HL = line_tab entry for scanline HL. Destroys DE.
line_addr
    add hl,hl
    ld de,line_tab
    add hl,de
    ret

;; fill_rect - HL = first scanline, (fr_h) lines, (fr_x) x, (fr_w) width,
;; (fr_b) byte. Eight bytes at a time where it can (a new round refills
;; both health bars in the picture it starts in). Destroys AF, BC, DE, HL.
fill_rect
    call line_addr
fr_line
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld a,(fr_x)
    add a,e
    ld l,a
    ld a,d
    adc a,0
    ld h,a
    ld a,(fr_b)
    ld b,a
    ld a,(fr_w)
    ld c,a
    and 7
    jr z,fr_eights
fr_byte
    ld (hl),b
    inc hl
    dec a
    jr nz,fr_byte
fr_eights
    ld a,c
    rrca
    rrca
    rrca
    and 31
    jr z,fr_next
fr_eight
    REPEAT 8
    ld (hl),b
    inc hl
    REND
    dec a
    jr nz,fr_eight
fr_next
    pop hl
    ld a,(fr_h)
    dec a
    ld (fr_h),a
    jr nz,fr_line
    ret
