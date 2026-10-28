;; ===========================================================================
;; bannerlow.asm - a piece of banner_vis (banner.asm), in low RAM after
;; stream.asm (LOW_ORG).
;; ===========================================================================

;; nv_fighter - HL = a fighter's F_Y: back if it and F_OY are both below
;; the banner's lines, else on to banner_vis's nv_no (not shown).
;; Destroys AF, BC, HL.
nv_fighter
    ld a,(hl)
    ld bc,F_OY-F_Y
    add hl,bc
    cp (hl)
    jr c,nf_min
    ld a,(hl)
nf_min
    cp BN_CLEAR
    ret nc
    pop af
    jp nv_no

