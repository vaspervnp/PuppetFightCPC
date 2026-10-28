;; ===========================================================================
;; bannerend.asm - the banner's words when a round ends (banner.asm). In
;; a gap of the background mirror (GAP6_ORG).
;; ===========================================================================

;; banner_end - the round is over (round.asm rt_end): a draw, the clock
;; out, or a K.O., at full health a perfect one. Destroys AF, B, DE, HL.
;; (DEMO=1 has no rounds, and no room for it in this gap with JUMP=1.)
banner_end
    IF DEMO
    ret
    ELSE
    ld hl,(rnd_winner)
    ld a,h
    or l
    ld a,BN_EVEN
    jr z,be_set
    ld a,(rnd_secs)
    or a
    ld a,BN_TIMEUP
    jr z,be_set
    ld de,F_HEALTH
    add hl,de
    ld a,(hl)
    cp HEALTH_MAX
    ld a,BN_PERFECT
    jr z,be_set
    ld a,BN_KO
be_set
    ld b,BN_END_PICS
    jp banner_set
    ENDIF
