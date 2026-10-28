;; ===========================================================================
;; banneroff.asm - the banner taken off (banner.asm). In the stack's
;; unused part, with the bursts' pass (LOW2_ORG).
;; ===========================================================================

;; bn_off - from burst_pass, main RAM in: the stage back from the mirror
;; under it, line by line, with interrupts on. Destroys AF, BC, DE, HL.
bn_off
    ld a,BN_TOP
    call vt_line                ; victory.asm
    ld hl,(vt_lptr)
    ld b,BN_LINES
bo_line
    push bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld a,(BN_X)
    add a,e
    ld e,a
    ld l,a
    ld a,d
    adc a,0
    ld d,a                      ; DE = the screen,
    and MIRROR_H_AND
    or MIRROR_H_OR
    ld h,a                      ; HL = its mirror
    ld a,(BN_W)
    ld c,a
    ld b,0
    ldir
    pop hl
    pop bc
    djnz bo_line
    xor a                       ; off: none of it drawn
    ld (BN_FLAGS),a
    ld (BN_DONE),a
    ret
