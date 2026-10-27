;; ===========================================================================
;; moves.asm - the fighter helpers think and combat use: starting moves,
;; animation, the motion history, walking and keeping apart.
;;
;; Cold code, like fighter.asm: in a gap of the background mirror, so it
;; may only run with main RAM at #4000 (move_frames, which pages the
;; character's bank in, stays in main.asm).
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; Helpers. All take IX = fighter (and IY = opponent where it matters).
;; ---------------------------------------------------------------------------

;; start_move - A = move: begin it at frame 0 (an attack with a swish).
;; Destroys AF, BC, DE, HL.
start_move
    ld (ix+F_MOVE),a
    call attacking
    ld a,SFX_SWING
    call c,sfx_play
    ld (ix+F_FRAME),0
    ld (ix+F_TIMER),0
    ld (ix+F_HITDONE),0
    jp move_frames              ; F_NFR from the directory

;; animate_loop - next frame every FRAME_PICS pictures, round and round.
;; animate_hold - the same, but stop on the last frame.
;; animate_once - the same, CY set once the last frame has had its time.
;; Destroy AF.
animate_loop
    call frame_tick
    ret nz
    ld a,(ix+F_FRAME)
    inc a
    cp (ix+F_NFR)
    jr c,al_set
    xor a
al_set
    ld (ix+F_FRAME),a
    ret

animate_hold
    call frame_tick
    ret nz
    ld a,(ix+F_FRAME)
    inc a
    cp (ix+F_NFR)
    ret nc
    ld (ix+F_FRAME),a
    ret

animate_once
    call frame_tick
    scf
    ccf
    ret nz
    ld a,(ix+F_FRAME)
    inc a
    cp (ix+F_NFR)
    ccf
    ret c                       ; past the last frame
    ld (ix+F_FRAME),a
    ret

;; frame_tick - Z when it is time for the next frame. Destroys AF.
frame_tick
    ld a,(ix+F_TIMER)
    inc a
    cp FRAME_PICS
    jr c,ft_wait
    xor a
ft_wait
    ld (ix+F_TIMER),a
    ret

;; record_motion - C = held: this picture's stick, turned to the fighter's
;; facing, goes in front of its motion history. Keeps BC. Destroys AF, DE,
;; HL.
record_motion
    ld a,c
    and DR_UP|DR_DOWN|DR_BACK|DR_FWD
    ld e,a
    ld a,(ix+F_FACE)
    or a
    ld a,e
    jr z,rm_store
    and DR_UP|DR_DOWN           ; facing left: left is forward
    bit CT_LEFT,e
    jr z,rm_l
    or DR_FWD
rm_l
    bit CT_RIGHT,e
    jr z,rm_store
    or DR_BACK
rm_store
    push bc
    push af
    push ix
    pop hl
    ld bc,F_HIST+HIST_LEN-1
    add hl,bc
    ld d,h                      ; DE = the oldest,
    ld e,l
    dec hl                      ; HL = the one before: all one older
    ld bc,HIST_LEN-1
    lddr
    pop af
    ld (de),a                   ; and this picture's in front
    pop bc
    ret

;; motion - HL = a motion: its steps newest first, each a mask and the
;; value the history must show under it, and 0 to end. CY if the history
;; holds the steps in order, each in an older picture than the last.
;; Keeps BC. Destroys AF, DE, HL.
motion
    push bc
    ex de,hl                    ; DE = steps
    push ix
    pop hl
    ld bc,F_HIST
    add hl,bc                   ; HL = the newest picture
    ld b,HIST_LEN+1
mo_step
    ld a,(de)
    or a
    jr z,mo_found               ; every step found
mo_pic
    dec b
    jr z,mo_none                ; out of history (NC)
    ld a,(de)
    and (hl)
    inc hl
    inc de
    ex de,hl
    cp (hl)
    ex de,hl
    dec de
    jr nz,mo_pic                ; not this picture: an older one
    inc de                      ; found: the next step, further back
    inc de
    jr mo_step
mo_found
    pop bc
    scf
    ret
mo_none
    pop bc
    or a
    ret

;; clear_motion - forget the history (a motion used up). Destroys AF, HL.
clear_motion
    push bc
    push ix
    pop hl
    ld bc,F_HIST
    add hl,bc
    ld b,HIST_LEN
cm_byte
    ld (hl),0
    inc hl
    djnz cm_byte
    pop bc
    ret

;; Motions for motion: mask, value, ... 0.
mo_special                      ; down, down-forward, forward
    defb DR_DOWN|DR_FWD,DR_FWD
    defb DR_DOWN|DR_FWD,DR_DOWN|DR_FWD
    defb DR_DOWN|DR_FWD,DR_DOWN
    defb 0
mo_uppercut                     ; down, then up
    defb DR_UP|DR_DOWN,DR_UP
    defb DR_DOWN,DR_DOWN
    defb 0

;; back_held - NZ if the stick is pushed away from the opponent (C = held).
;; Destroys AF.
back_held
    ld a,(ix+F_FACE)
    or a
    jr nz,bh_left
    ld a,c
    and 1<<CT_LEFT
    ret
bh_left
    ld a,c
    and 1<<CT_RIGHT
    ret

;; walk_by - D = signed step. Walk, but not into the opponent while both
;; stand. Destroys AF, E.
walk_by
    ld a,(ix+F_X)
    add a,d
    ld e,a                      ; the new x
    ld a,(iy+F_Y)               ; opponent in the air: walk under them
    cp FIGHTER_Y
    jr nz,wb_ok
    ld a,e                      ; distance to the opponent after the step
    sub (iy+F_X)
    jr nc,wb_abs
    neg
wb_abs
    cp MIN_SEP
    jr nc,wb_ok
    ld a,(ix+F_X)               ; too close: allowed only if moving away
    sub (iy+F_X)
    jr nc,wb_abs0
    neg
wb_abs0
    ld d,a                      ; distance before
    ld a,e
    sub (iy+F_X)
    jr nc,wb_abs1
    neg
wb_abs1
    cp d
    ret c                       ; it would get closer: stay put
wb_ok
    ld a,e
    ; fall into set_x

;; set_x - A = new box x: keep it on the screen. Destroys AF.
set_x
    cp X_MAX+1
    jr c,sx_ok
    cp 256-32                   ; went below 0 (wrapped): the left wall
    ld a,0
    jr nc,sx_ok
    ld a,X_MAX
sx_ok
    ld (ix+F_X),a
    ret

;; face_opponent - turn to face the opponent (free moves only). Destroys AF.
face_opponent
    ld a,(iy+F_X)
    cp (ix+F_X)
    ld a,0
    jr nc,fo_set                ; opponent to the right (or level): right
    inc a
fo_set
    ld (ix+F_FACE),a
    ret

;; ---------------------------------------------------------------------------
;; separate - two standing fighters closer than MIN_SEP are pushed apart,
;; half each, and the walls push back. (A landing can leave them inside each
;; other; walking never does.) Destroys AF, BC, IX, IY.
;; ---------------------------------------------------------------------------
separate
    ld a,(fighter_a+F_Y)
    cp FIGHTER_Y
    ret nz
    ld a,(fighter_b+F_Y)
    cp FIGHTER_Y
    ret nz
    ld ix,fighter_a             ; IX = the one on the left, IY the right
    ld iy,fighter_b
    ld a,(ix+F_X)
    cp (iy+F_X)
    jr c,sp_order               ; (level: A counts as the left one)
    jr z,sp_order
    ld ix,fighter_b
    ld iy,fighter_a
sp_order
    ld a,(iy+F_X)
    sub (ix+F_X)                ; distance
    cp MIN_SEP
    ret nc
    ld b,a
    ld a,MIN_SEP
    sub b                       ; how much too close
    ld c,a
    srl a                       ; the left one takes half (rounded down)
    ld b,a
    ld a,(ix+F_X)
    sub b
    jr nc,sp_left_ok
    xor a                       ; the wall: the right one takes the rest
sp_left_ok
    ld (ix+F_X),a
    add a,MIN_SEP
    cp X_MAX+1
    jr c,sp_right_ok
    ld a,X_MAX                  ; the other wall: shove the left one back
    ld (iy+F_X),a
    sub MIN_SEP
    ld (ix+F_X),a
    ret
sp_right_ok
    ld (iy+F_X),a
    ret
