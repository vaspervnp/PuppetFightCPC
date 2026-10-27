;; ===========================================================================
;; video.asm - line table, the HUD's bars, and the background mirror.
;; ===========================================================================

;; line_addr - HL = line_tab entry for scanline HL. Destroys DE.
line_addr
    add hl,hl
    ld de,line_tab
    add hl,de
    ret

;; ---------------------------------------------------------------------------
;; draw_hud - the health bars, full, on the stage boot unpacked (its lines
;; 0-23 are the HUD's black). Destroys everything.
;; ---------------------------------------------------------------------------
draw_hud
    ld ix,hud_rects
dh_rect
    ld a,(ix+0)
    cp #FF
    ret z
    ld l,(ix+0)
    ld h,(ix+1)
    ld a,(ix+2)
    ld (fr_h),a
    ld a,(ix+3)
    ld (fr_x),a
    ld a,(ix+4)
    ld (fr_w),a
    ld a,(ix+5)
    ld (fr_b),a
    call fill_rect
    ld bc,6
    add ix,bc
    jr dh_rect

;; Rectangles: first line (word), lines, x, width, byte. #FF ends.
hud_rects
    defw 8
    defb 8,4,40,PB_6_6          ; fighter A's health bar, in its first colour
    defw 8
    defb 8,52,40,PB_10_10       ; fighter B's
    defb #FF

;; fill_rect - HL = first scanline, (fr_h) lines, (fr_x) x, (fr_w) width,
;; (fr_b) byte. Destroys AF, BC, DE, HL.
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
fr_byte
    ld (hl),b
    inc hl
    dec a
    jr nz,fr_byte
    pop hl
    ld a,(fr_h)
    dec a
    ld (fr_h),a
    jr nz,fr_line
    ret

ret
