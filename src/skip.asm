;; ===========================================================================
;; skip.asm - can_skip, for prepare (prepare.asm). Cold code in a gap of the
;; background mirror (GAP5_ORG), with victory.asm.
;; ===========================================================================

;; can_skip - IX = fighter, IY = the other: A = 1 if IX's window work can be
;; left out: it shows the same frame in the same place as on the screen, and
;; neither the other's old box (its restore) nor its new one (its draw)
;; reaches IX's box. Else A = 0. Destroys AF, B, DE, HL.
can_skip
    call fighter_same
    jr nz,cs_no
    push ix                     ; the other unchanged too: nothing touches
    push iy
    pop ix
    call fighter_same
    pop ix
    jr z,cs_yes
    ld a,(iy+F_DRAWN)           ; the other's old box
    or a
    jr z,cs_new
    ld d,(iy+F_OX)
    ld e,(iy+F_OW)
    call cs_overlap
    jr c,cs_no
cs_new
    ld a,(iy+F_X)               ; and its new one
    add a,(iy+F_OFF)
    ld d,a
    ld e,(iy+F_W)
    call cs_overlap
    jr c,cs_no
cs_yes
    ld a,1
    ret
cs_no
    xor a
    ret

;; cs_overlap - CY if bytes D..D+E-1 meet IX's box on the screen.
cs_overlap
    ld a,(ix+F_OX)              ; D < OX + OW
    add a,(ix+F_OW)
    ld b,a
    ld a,d
    cp b
    ret nc
    ld a,d                      ; and OX < D + E
    add a,e
    ld b,a
    ld a,(ix+F_OX)
    cp b
    ret

;; fighter_same - IX = fighter: Z if what it will show is what the screen
;; has: same frame (bank, spans) in the same facing, place and width.
;; Destroys AF, B.
fighter_same
    ld a,(ix+F_DRAWN)
    or a
    jr z,fs_diff
    ld a,(ix+F_X)
    add a,(ix+F_OFF)
    cp (ix+F_OX)
    ret nz
    ld a,(ix+F_Y)
    cp (ix+F_OY)
    ret nz
    ld a,(ix+F_DFACE)
    cp (ix+F_OFACE)
    ret nz
    ld a,(ix+F_FBANK)
    cp (ix+F_OBANK)
    ret nz
    ld a,(ix+F_SPANS)
    cp (ix+F_OSPANS)
    ret nz
    ld a,(ix+F_SPANS+1)
    cp (ix+F_OSPANS+1)
    ret
fs_diff
    or 1
    ret
