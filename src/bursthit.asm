;; ===========================================================================
;; bursthit.asm - a burst (burst.asm) for a hit that lands. Logic, in a
;; gap of the background mirror (GAP1_ORG).
;; ===========================================================================

;; burst_hit - IX = who a hit landed on (combat.asm land_hit): a burst over
;; its head, or as high as the beam allows (BURST_TOP), with a word picked
;; by the picture count. Destroys AF.
burst_hit
    ld a,(ix+F_X)               ; (the walls keep it on the screen)
    add a,(SPR_W-BURST_W)/2
    ld (BURST+F_PX),a
    ld a,(ix+F_Y)
    sub BURST_H+2
    cp BURST_TOP
    jr nc,bh_y
    ld a,BURST_TOP
bh_y
    ld (BURST+F_PY),a
    ld a,(render_count)
    and 7
    ld (BURST+F_PSPEED),a
    ld a,BURST_PICS
    ld (BURST+F_PACT),a
    ld (BURST+F_PDMG),a         ; new
    ret
    ASSERT X_MAX+(SPR_W-BURST_W)/2<=BYTES_PER_LINE-BURST_W
