;; ===========================================================================
;; burstvis.asm - whether a burst may be shown (burst.asm), and its word.
;; In a gap of the background mirror (GAP3_ORG).
;; ===========================================================================

;; burst_vis - from shot_vis, once a picture: the burst's time runs down,
;; whether it may be shown (sv_one), and what the pass has to do: 1 take
;; it off (on the screen, and hidden or replaced), 2 draw it. Destroys
;; everything.
burst_vis
    ld ix,BURST
    ld (ix+F_PW),BURST_W        ; (for sv_one)
    ld (ix+F_PH),BURST_H
    ld a,(ix+F_PACT)
    or a
    jr z,bv_vis
    dec (ix+F_PACT)
bv_vis
    call sv_one
    ld a,(ix+F_PDRAWN)
    or a
    jr z,bv_draw
    ld a,(ix+F_PDMG)
    or a
    jr nz,bv_off
    ld a,(ix+F_PVIS)
    xor 1                       ; shown and staying: nothing
    jr z,bv_set
bv_off
    ld a,1
bv_draw
    ld b,a
    ld a,(ix+F_PVIS)
    add a,a
    or b
bv_set
    ld (ix+F_PSTUN),a
    ret

;; bd_word - IX = BURST, A = its top line: its word, in dark red on white.
;; Destroys AF, BC, DE, HL, IX.
bd_word
    push af
    ld a,#20                    ; pen 4 on pen 2, as left pixels
    ld (vt_on),a
    ld a,#08
    ld (vt_off),a
    pop af
    add a,BURST_TEXT
    call vt_line
    ld a,(ix+F_PSPEED)
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,burst_words
    add hl,de
    ld a,(ix+F_PX)
    add a,(BURST_W-8)/2
    ld b,4
    jp vt_at

