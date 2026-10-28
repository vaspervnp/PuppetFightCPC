;; ===========================================================================
;; bannercel.asm - the banner's pixels (banner.asm). Under the interrupt
;; jump, #0000-#0037, where nothing else is (ROMs are off).
;; ===========================================================================

;; bn_cell - D = a column, IX = its row's line_tab entry: the pixel's
;; shadow a byte right and a row down, then the pixel. Destroys AF, E.
bn_cell
    push hl
    ld a,(ix+8)
    add a,d
    inc a
    ld l,a
    ld a,(ix+9)
    adc a,0
    ld h,a
    ld e,PB_1_1
    call bn_four
    ld a,(ix+0)
    add a,d
    ld l,a
    ld a,(ix+1)
    adc a,0
    ld h,a
    ld e,PB_2_2
    call bn_four
    pop hl
    ret
bn_four                         ; HL on a row's first line: its 4 lines
    ld (hl),e
    set 3,h
    ld (hl),e
    set 4,h
    ld (hl),e
    res 3,h
    ld (hl),e
    ret
