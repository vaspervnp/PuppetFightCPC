;; ===========================================================================
;; fighter.asm - what a fighter does with its controls, once a picture.
;;
;; A fighter's move is one of its character's moves (the directory's move
;; numbers), and the move is its state:
;;     idle, walk, crouch    free: controls choose the next move
;;     jump                  in the air for JUMP_PICS pictures
;;     punch, kick, ...      attacks: play through once, then idle
;; Frames advance every FRAME_PICS pictures (12.5 fps). An attack frame with
;; a hit box that reaches the opponent's hurt box lands once per attack
;; (combat): blocked if the opponent holds back while free, otherwise damage,
;; a hit reaction, and at no health a KO.
;;
;; Positions are box x in bytes (the frame's left edge before its offset)
;; and the top scanline. Fighters face each other while they are free, stay
;; inside the screen, and never stand inside each other; a jump may pass
;; over the opponent, and the landing pushes them apart.
;; ===========================================================================

MV_IDLE         EQU 0
MV_WALK         EQU 1
MV_CROUCH       EQU 2
MV_JUMP         EQU 3
MV_PUNCH        EQU 4
MV_KICK         EQU 5
MV_SWEEP        EQU 6
MV_UPPERCUT     EQU 7
MV_BACKKICK     EQU 8
MV_BLOCK        EQU 9
MV_HIT          EQU 10
MV_KO           EQU 11

FRAME_PICS      EQU 2           ; pictures per animation frame
WALK_STEP       EQU 1           ; bytes per picture (2 mode 0 pixels)
JUMP_STEP       EQU 1           ; bytes per picture across, in a jump
JUMP_PICS       EQU 16          ; pictures in the air (jump_arc)
X_MAX           EQU BYTES_PER_LINE-SPR_W
MIN_SEP         EQU 10          ; closest two standing boxes may be (bytes)
HEALTH_MAX      EQU 40          ; a full health bar, one byte a point
HIT_PUSH        EQU 3           ; bytes a hit knocks the defender back,
BLOCK_PUSH      EQU 1           ; and a block

;; ---------------------------------------------------------------------------
;; think - IX = fighter, IY = its opponent. One picture of the fighter's
;; life. Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
think
    ld c,(ix+F_CTL)             ; C = held
    ld a,(ix+F_PCTL)
    cpl
    and c
    ld b,a                      ; B = pressed this picture
    ld (ix+F_PCTL),c
    ld a,(ix+F_MOVE)
    cp MV_JUMP
    jp z,th_jump
    cp MV_KO
    jp z,animate_hold           ; down for good
    cp MV_BLOCK
    jp z,th_block
    cp MV_PUNCH
    jp nc,th_attack             ; attacks, block and hit play out

    ;; Free: attacks first, then a jump, a crouch, a walk, or standing.
    bit CT_PUNCH,b
    jr z,th_no_punch
    ld a,MV_PUNCH
    bit CT_DOWN,c
    jr z,th_go
    ld a,MV_UPPERCUT
    jr th_go
th_no_punch
    bit CT_KICK,b
    jr z,th_no_kick
    ld a,MV_SWEEP
    bit CT_DOWN,c
    jr nz,th_go
    call back_held
    ld a,MV_BACKKICK
    jr nz,th_go
    ld a,MV_KICK
th_go
    jp start_move

th_no_kick
    bit CT_UP,c
    jr z,th_no_jump
    xor a                       ; across: the way the stick is pushed
    bit CT_RIGHT,c
    jr z,th_j_l
    ld a,JUMP_STEP
th_j_l
    bit CT_LEFT,c
    jr z,th_j_set
    ld a,-JUMP_STEP
th_j_set
    ld (ix+F_JX),a
    ld a,MV_JUMP
    call start_move
    ld (ix+F_TIMER),0
    ret

th_no_jump
    bit CT_DOWN,c
    jr z,th_no_crouch
    ld a,(ix+F_MOVE)
    cp MV_CROUCH
    ld a,MV_CROUCH
    jp nz,start_move
    jp animate_hold             ; crouch down, then hold the last frame

th_no_crouch
    call back_held              ; back while the opponent attacks: block
    jr z,th_no_block
    call opp_attacking
    jr nc,th_no_block
    ld a,MV_BLOCK
    jp start_move
th_no_block
    ld a,c
    and 1<<CT_LEFT|1<<CT_RIGHT
    jr z,th_stand
    ld d,WALK_STEP
    bit CT_RIGHT,c
    jr nz,th_walk_dir
    ld d,-WALK_STEP
th_walk_dir
    call walk_by
    ld a,(ix+F_MOVE)
    cp MV_WALK
    ld a,MV_WALK
    jp nz,start_move
    call animate_loop
    jp face_opponent

th_stand
    ld a,(ix+F_MOVE)
    or a                        ; MV_IDLE
    ld a,MV_IDLE
    jp nz,start_move
    call animate_loop
    jp face_opponent

;; Blocking: held while back is held and the opponent attacks.
th_block
    call back_held
    jr z,th_unblock
    call opp_attacking
    jp c,animate_hold
th_unblock
    ld a,MV_IDLE
    jp start_move

;; opp_attacking - IY = opponent: CY if it is in an attack. Destroys AF.
opp_attacking
    ld a,(iy+F_MOVE)
    cp MV_PUNCH
    ccf
    ret nc
    cp MV_BACKKICK+1
    ret

;; An attack plays through once. A sweep ends crouched if down is held.
th_attack
    call animate_once
    ret nc                      ; still going
    ld a,(ix+F_MOVE)
    cp MV_SWEEP
    jr nz,th_att_idle
    bit CT_DOWN,c
    jr z,th_att_idle
    ld a,MV_CROUCH
    call start_move
    ld (ix+F_FRAME),2           ; straight to the crouched frame
    ret
th_att_idle
    ld a,MV_IDLE
    jp start_move

;; In the air: the arc for the height, F_JX across, the tuck going up and
;; the stretch coming down.
th_jump
    ld a,(ix+F_TIMER)
    inc a
    cp JUMP_PICS
    jr nc,th_land
    ld (ix+F_TIMER),a
    ld e,a
    ld d,0
    ld hl,jump_arc
    add hl,de
    ld a,FIGHTER_Y
    sub (hl)
    ld (ix+F_Y),a
    ld a,e                      ; frame: 0 taking off, 1 rising, 2 falling
    ld d,0
    cp 2
    jr c,th_j_frame
    inc d
    cp JUMP_PICS/2+2
    jr c,th_j_frame
    inc d
th_j_frame
    ld (ix+F_FRAME),d
    ld a,(ix+F_X)
    add a,(ix+F_JX)
    jp set_x
th_land
    ld (ix+F_Y),FIGHTER_Y
    ld a,MV_IDLE
    call start_move
    jp face_opponent

;; ---------------------------------------------------------------------------
;; Helpers. All take IX = fighter (and IY = opponent where it matters).
;; ---------------------------------------------------------------------------

;; start_move - A = move: begin it at frame 0. Destroys AF, BC, DE, HL.
start_move
    ld (ix+F_MOVE),a
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

;; move_frames - F_NFR = the number of frames in F_MOVE, from the
;; character's directory. Destroys AF, BC, DE, HL.
move_frames
    ld a,(ix+F_RAM0)
    ld bc,#7F00
    out (c),a
    ld a,(ix+F_MOVE)
    ld l,a
    add a,a
    add a,l
    ld l,a
    ld h,0
    ld de,DIR_MOVES
    add hl,de
    ld a,(hl)
    ld (ix+F_NFR),a
    ld bc,#7FC0
    out (c),c
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
    cp MV_PUNCH
    ret c
    cp MV_BACKKICK+1
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
    ld a,(ix+F_MOVE)            ; blocked: free or blocking, holding back
    cp MV_BLOCK
    jr z,sk_block
    cp MV_CROUCH+1
    jr nc,sk_hit
sk_block
    ld c,(ix+F_CTL)
    call back_held
    jr z,sk_hit
    ld a,(ix+F_MOVE)
    cp MV_BLOCK
    ld a,MV_BLOCK
    call nz,start_move
    ld b,BLOCK_PUSH
    jr knock_back
sk_hit
    ld a,(iy+F_MOVE)            ; damage for the move
    sub MV_PUNCH
    ld e,a
    ld d,0
    ld hl,damage
    add hl,de
    ld a,(ix+F_HEALTH)
    sub (hl)
    jr nc,sk_alive
    xor a
sk_alive
    ld (ix+F_HEALTH),a
    push af
    call health_bar
    pop af
    ld (ix+F_Y),FIGHTER_Y       ; knocked out of a jump too
    or a
    ld a,MV_HIT
    jr nz,sk_react
    ld a,MV_KO
sk_react
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

damage                          ; punch, kick, sweep, uppercut, back kick
    defb 4,5,4,6,6

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
