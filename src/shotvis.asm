;; ===========================================================================
;; shotvis.asm - which projectiles the next pass may draw (special.asm,
;; main.asm shot_pass). Cold code in a gap of the background mirror.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; shot_vis - from prepare, before it sets up the fighters: each projectile
;; is shown in the next pass (main.asm shot_pass) only if it meets neither
;; fighter's drawn box, the one on the screen (F_OFB) nor the one the
;; rebuild will draw (F_FB). Destroys everything.
;; ---------------------------------------------------------------------------
shot_vis
    call burst_vis              ; and the burst's (burst.asm)
    ld ix,fighter_a
    call sv_one
    ld ix,fighter_b
    call sv_one
    ld hl,fighter_a+F_PDRAWN    ; a pass only if there is something to
    ld de,fighter_b+F_PDRAWN    ; take off or draw
    ld a,(fighter_a+F_PVIS)
    or (hl)
    ex de,hl
    or (hl)
    ld hl,fighter_b+F_PVIS
    or (hl)
    ld (shot_pending),a
    ret
sv_one
    ld (ix+F_PVIS),0
    ld a,(ix+F_PACT)
    or a
    ret z
    ld hl,bx_a
    call shot_box
    ld iy,fighter_a
    call sv_clear
    ret c
    ld iy,fighter_b
    call sv_clear
    ret c
    ld (ix+F_PVIS),1
    ret

;; sv_clear - IY = fighter: CY if bx_a meets its drawn box, new or old.
sv_clear
    ld a,(iy+F_X)
    add a,(iy+F_OFF)
    ld c,a
    ld b,(iy+F_Y)
    ld hl,F_FB
    call sv_box
    ret c
    ld a,(iy+F_DRAWN)
    or a
    ret z
    ld c,(iy+F_OX)
    ld b,(iy+F_OY)
    ld hl,F_OFB

;; sv_box - IY + HL = a drawn box, C = its frame's left edge, B = top line:
;; CY if bx_a meets it on the screen.
sv_box
    push iy
    pop de
    add hl,de
    ld de,bx_b
    ld a,(hl)
    add a,c
    ld (de),a
    inc hl
    inc de
    ld a,(hl)
    add a,c
    ld (de),a
    inc hl
    inc de
    ld a,(hl)
    add a,b
    ld (de),a
    inc hl
    inc de
    ld a,(hl)
    add a,b
    ld (de),a
    ld hl,bx_a
    ld de,bx_b
    jp box_overlap
