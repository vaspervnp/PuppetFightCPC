;; ===========================================================================
;; video.asm - line table, the spike's stage, and the background mirror.
;; ===========================================================================

;; build_line_tab - start address of each of the 272 scanlines.
;;   rows 0..20 : #8020 + raster*2048 + row*96   (page 2)
;;   rows 21..33: #C000 + raster*2048 + (row-21)*96 (page 3)
;; Destroys AF, BC, DE, HL.
build_line_tab
    ld hl,line_tab
    ld de,PAGE2_BASE
    ld c,PAGE2_ROWS
blt_p2
    call blt_row
    dec c
    jr nz,blt_p2
    ld de,PAGE3_BASE
    ld c,DISPLAY_ROWS-PAGE2_ROWS
blt_p3
    call blt_row
    dec c
    jr nz,blt_p3
    ret

;; One character row: 8 entries 2048 bytes apart, then DE on by one row.
blt_row
    push de
    ld b,8
blt_raster
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld a,d
    add a,8
    ld d,a
    djnz blt_raster
    pop de
    ld a,e
    add a,BYTES_PER_LINE
    ld e,a
    ret nc
    inc d
    ret

;; line_addr - HL = line_tab entry for scanline HL. Destroys DE.
line_addr
    add hl,hl
    ld de,line_tab
    add hl,de
    ret

;; ---------------------------------------------------------------------------
;; draw_stage - paint the whole screen: bands of sky and floor from
;; stage_rows, then a few rectangles. The pillars and the rope sit inside the
;; fighter band on purpose: a background that is not the same all the way
;; across is what shows up a restore that copies from the wrong place.
;; Destroys everything.
;; ---------------------------------------------------------------------------
draw_stage
    ld hl,line_tab
    ld ix,stage_rows
    ld de,0                     ; scanline
ds_line
    ld a,e                      ; past this band's last line? next band
    cp (ix+0)
    ld a,d
    sbc a,(ix+1)
    jr c,ds_band_ok
    ld bc,4
    add ix,bc
ds_band_ok
    ld a,(ix+2)                 ; even line byte
    bit 0,e
    jr z,ds_even
    ld a,(ix+3)                 ; odd line byte
ds_even
    push de
    push hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl                    ; HL = scanline start
    ld (hl),a
    ld d,h
    ld e,l
    inc de
    ld bc,BYTES_PER_LINE-1
    ldir
    pop hl
    inc hl
    inc hl
    pop de
    inc de
    ld a,e
    cp DISPLAY_LINES AND #FF
    jr nz,ds_line
    ld a,d
    cp DISPLAY_LINES/256
    jr nz,ds_line

    ld ix,stage_rects
ds_rect
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
    jr ds_rect

;; Band ends (exclusive, words) with the byte for even and odd lines.
stage_rows
    defw HUD_LINES
    defb #00,#00
    defw 96
    defb PB_11_11,PB_11_11
    defw 112
    defb PB_11_13,PB_13_11      ; dithered seam between the two sky blues
    defw SKY_END
    defb PB_13_13,PB_13_13
    defw HORIZON_END
    defb PB_9_9,PB_9_9
    defw 216
    defb PB_14_8,PB_8_14
    defw DISPLAY_LINES
    defb PB_14_14,PB_14_14

;; Rectangles: first line (word), lines, x, width, byte. #FF ends.
stage_rects
    defw 8
    defb 8,4,40,PB_12_12        ; Trump's health bar
    defw 8
    defb 8,52,40,PB_4_4         ; Putin's health bar
    defw 120
    defb 80,2,4,PB_9_1          ; left pillar
    defw 120
    defb 80,90,4,PB_9_1         ; right pillar
    defw 170
    defb 2,0,96,PB_10_10        ; the rope, right across the band
    defw 240
    defb 2,0,96,PB_14_8         ; floor stripe
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

;; ---------------------------------------------------------------------------
;; copy_mirror - copy the fighter band of the screen into #4000-#7FFF, each
;; line at its screen address with H = (H AND #3F) OR #40.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
copy_mirror
    ld hl,BAND_TOP
    call line_addr
    ld a,DISPLAY_LINES-BAND_TOP
cm_line
    push af
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld h,d                      ; HL = screen line
    ld l,e
    ld a,d
    and MIRROR_H_AND
    or MIRROR_H_OR
    ld d,a                      ; DE = its mirror
    ld bc,BYTES_PER_LINE
    ldir
    pop hl
    pop af
    dec a
    jr nz,cm_line
    ret
