;; ===========================================================================
;; combat.asm - attacks landing, blocks, damage, KO, health bars and rounds.
;;
;; Cold code: it runs once a picture in the logic, never in the window, so
;; it lives in the unused tail of screen slice 4 (COLD_ORG), copied there by
;; boot, which leaves main RAM to the engine and the frame caches.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; combat - each fighter's attack against the other. Destroys everything.
;; ---------------------------------------------------------------------------
combat
    ld ix,fighter_a
    ld iy,fighter_b
    call strike
    ld ix,fighter_b
    ld iy,fighter_a
    ; fall into strike

;; strike - IX = attacker, IY = defender: does IX's attack land now?
strike
    ld a,(ix+F_MOVE)            ; an attack that hasn't landed yet,
    call attacking
    ret nc
    ld a,(ix+F_HITDONE)
    or a
    ret nz
    ld a,(iy+F_MOVE)            ; on someone still standing
    cp MV_KO
    ret z
    ld hl,bx_a
    call boxes
    ld a,(bx_a+7)               ; this frame hits?
    or a
    ret z
    push ix
    push iy
    pop ix
    ld hl,bx_b
    call boxes
    pop ix
    ld hl,bx_a+4                ; its hit box against the defender's hurt box
    ld de,bx_b
    call box_overlap
    ret nc
    ld (ix+F_HITDONE),1
    push ix                     ; IX = defender from here
    push iy
    pop ix
    pop iy                      ; IY = attacker
    ld c,(ix+F_CTL)             ; blocked: holding back, and
    call back_held
    jr z,sk_hit
    ld a,(ix+F_MOVE)
    cp MV_CROUCH                ; crouching blocks anything;
    jr z,sk_crouch
    cp MV_BLOCK                 ; standing (free or blocking) all but the
    jr z,sk_stand               ; sweep, which is low
    cp MV_WALK+1
    jr nc,sk_hit
sk_stand
    ld a,(iy+F_MOVE)
    cp MV_SWEEP
    jr z,sk_hit
    ld a,(ix+F_MOVE)
    cp MV_BLOCK
    ld a,MV_BLOCK
    call nz,start_move
    ld (ix+F_STUN),BLOCK_STUN
sk_crouch
    ld b,BLOCK_PUSH
    jr knock_back
sk_hit
    ld a,(iy+F_MOVE)            ; damage and hitstun for the move
    sub MV_PUNCH
    ld e,a
    ld d,0
    ld hl,damage
    add hl,de
    ld de,hitstun-damage
    push hl
    add hl,de
    ld a,(hl)
    ld (ix+F_STUN),a
    pop hl
    ld a,(ix+F_HEALTH)
    sub (hl)
    jr nc,sk_alive
    xor a
sk_alive
    ld (ix+F_HEALTH),a
    push af
    call health_bar
    pop af
    or a
    ld a,MV_KO                  ; no health: KO
    jr z,sk_react
    ld a,(ix+F_Y)               ; hit in the air: knocked down
    cp FIGHTER_Y
    jr nz,sk_down
    ld a,(ix+F_STUN)            ; and by a knockdown move
    or a
    ld a,MV_HIT
    jr nz,sk_react
sk_down
    ld (ix+F_STUN),KD_PICS
    ld a,MV_KO
sk_react
    ld (ix+F_Y),FIGHTER_Y       ; out of a jump too
    call start_move
    ld b,HIT_PUSH
    ; fall into knock_back

;; knock_back - IX = defender, IY = attacker, B = bytes: push IX away.
knock_back
    ld a,(ix+F_X)
    cp (iy+F_X)
    jr c,kb_left
    add a,b
    jp set_x
kb_left
    sub b
    jp set_x

;; Per attack, from MV_PUNCH: punch, kick, sweep, uppercut, back kick,
;; (block, hit, KO: not attacks), special.
damage                          ; health points
    defb 4,5,4,6,6,0,0,0,8
hitstun                         ; pictures in the hit reaction (its own
    defb 6,8,0,0,10,0,0,0,0     ; frames take 6), 0: a knockdown

;; boxes - IX = fighter, HL = 8 bytes: the hurt box then the hit box of its
;; logic frame (F_MOVE, F_FRAME) on the screen, each x0, x1 (bytes), y0, y1
;; (lines), inclusive. No hit box: all 0. Destroys AF, BC, DE, HL.
boxes
    push hl
    ld a,(ix+F_MOVE)
    ld c,(ix+F_FRAME)
    call rec_addr
    ld a,(ix+F_RAM0)
    ld bc,#7F00
    out (c),a
    inc hl
    ld a,(hl)                   ; width - 1
    dec a
    ld (bx_w1),a
    inc hl
    ld a,(hl)                   ; the frame's left edge: x + offset
    add a,(ix+F_X)
    ld (bx_left),a
    ld de,5
    add hl,de                   ; the boxes
    pop de
    ld b,2
bx_box
    ld a,(ix+F_FACE)
    or a
    jr nz,bx_mirror
    ld a,(bx_left)              ; facing right: left + x
    add a,(hl)
    ld (de),a
    inc hl
    inc de
    ld a,(bx_left)
    add a,(hl)
    ld (de),a
    jr bx_y
bx_mirror
    inc hl                      ; facing left: left + w - 1 - x, ends swapped
    ld a,(bx_w1)
    sub (hl)
    ld c,a
    ld a,(bx_left)
    add a,c
    ld (de),a
    inc de
    dec hl
    ld a,(bx_w1)
    sub (hl)
    ld c,a
    ld a,(bx_left)
    add a,c
    ld (de),a
    inc hl
bx_y
    inc hl
    inc de
    ld a,(hl)                   ; lines: y + top, unless there is no box
    inc hl
    ld c,(hl)
    inc hl
    push af
    ld a,c
    or a
    jr z,bx_none
    pop af
    add a,(ix+F_Y)
    ld (de),a
    inc de
    ld a,c
    add a,(ix+F_Y)
    ld (de),a
    inc de
    djnz bx_box
    jr bx_done
bx_none
    pop af
    xor a
    ld (de),a
    inc de
    ld (de),a
    inc de
    djnz bx_box
bx_done
    ld bc,#7FC0
    out (c),c
    ret

;; box_overlap - HL, DE = two boxes (x0, x1, y0, y1): CY if they meet.
;; Destroys AF, C, DE, HL.
box_overlap
    call bo_axis                ; x, then y
    ret nc
bo_axis
    ld a,(de)                   ; C = DE.0
    ld c,a
    inc de
    ld a,(hl)                   ; HL.0 <= DE.1?
    inc hl
    ex de,hl
    cp (hl)
    ex de,hl
    jr z,bo_one
    jr c,bo_one
    or a                        ; NC: apart
    ret
bo_one
    ld a,c                      ; DE.0 <= HL.1?
    cp (hl)
    inc hl
    inc de
    jr z,bo_two
    jr c,bo_two
    or a
    ret
bo_two
    scf
    ret

;; health_bar - IX = fighter: blank the part of its bar it has lost. Both
;; bars empty from the middle of the screen outwards: A's runs x 4-43, B's
;; x 52-91. The logic runs while the beam is below the HUD. Destroys AF,
;; BC, DE, HL.
health_bar
    ld a,HEALTH_MAX
    sub (ix+F_HEALTH)
    ret z
    ld (fr_w),a
    ld a,8
    ld (fr_h),a
    xor a
    ld (fr_b),a
    push ix
    pop hl
    ld de,fighter_a
    or a
    sbc hl,de
    ld a,52                     ; B: from the bar's left (middle) end
    jr nz,hb_x
    ld a,4                      ; A: past what is left, to the middle end
    add a,(ix+F_HEALTH)
hb_x
    ld (fr_x),a
    ld hl,8
    jp fill_rect
