;; ===========================================================================
;; boot.asm - what start does once, out of the files it belongs with (the
;; interrupt, the line table, the mirror). Cold code in a gap of the
;; background mirror (GAP6_ORG), with logic.asm. Not jit_init: it pages a
;; character's bank in.
;; ===========================================================================

;; irq_init - install the handler at #0038 and enable interrupts.
;; ROMs are off, so #0038 is plain RAM and must hold the jump before EI.
;; Destroys AF, BC, HL.
irq_init
    di
    im 1
    ld a,#C3                    ; JP nn
    ld (#0038),a
    ld hl,irq_handler
    ld (#0039),hl
    call wait_vsync
    xor a
    ld (irq_count),a
    ld (frame_count),a
    ei
    ret

;; wait_vsync - return at the leading edge of VSYNC. Destroys AF, BC.
wait_vsync
    ld b,#F5
wait_vsync_off
    in a,(c)
    rra
    jr c,wait_vsync_off
wait_vsync_on
    in a,(c)
    rra
    jr nc,wait_vsync_on
    ret

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

;; ---------------------------------------------------------------------------
;; copy_mirror - copy the fighter band of the screen into #4000-#7FFF, each
;; line at its screen address with H = (H AND #3F) OR #40.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
copy_mirror
    ld hl,BAND_TOP
    call line_addr
    ld a,BAND_BOTTOM-BAND_TOP
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
