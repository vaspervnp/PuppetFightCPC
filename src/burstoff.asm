;; ===========================================================================
;; burstoff.asm - a burst off the screen (burst.asm). In a gap of the
;; background mirror (GAP4_ORG): burst_pass has paged main RAM in.
;; ===========================================================================

;; burst_off - IX = BURST: the bytes its shape covers back from the mirror,
;; line by line, with interrupts on (~2.3 ms). Destroys AF, BC, DE, HL.
burst_off
    ld (ix+F_PDRAWN),0
    ld a,(ix+F_POY)
    call vt_line                ; victory.asm
    ld de,burst_shape
    ld b,BURST_H
bo_row
    push bc
    ld a,(de)                   ; insets: left (high nibble), right
    inc de
    push de
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
    add a,BURST_W
    ld c,a                      ; BC = the line's bytes
    ld b,0
    ld hl,(vt_lptr)
    ld a,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (vt_lptr),hl
    add a,(ix+F_POX)
    jr nc,bo_x
    inc d
bo_x
    add a,e
    ld e,a
    jr nc,bo_l
    inc d
bo_l                            ; DE = the screen
    ld l,a
    ld a,d
    and MIRROR_H_AND
    or MIRROR_H_OR
    ld h,a                      ; HL = its mirror
    ldir
    pop de
    pop bc
    djnz bo_row
    ret
