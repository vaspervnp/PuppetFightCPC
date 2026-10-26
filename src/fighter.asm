;; ===========================================================================
;; fighter.asm - what a fighter does with its controls, once a picture.
;;
;; A fighter's move is one of its character's moves (the directory's move
;; numbers), and the move is its state:
;;     idle, walk, crouch    free: controls choose the next move
;;     jump                  in the air for JUMP_PICS pictures
;;     punch, kick, ...      attacks: play through once, then idle
;;     block, hit            held for their stun (and a block while the
;;                           opponent attacks), then idle
;;     KO                    with no health down for good; otherwise a
;;                           knockdown: fall, lie, get up over KD_PICS
;; Frames advance every FRAME_PICS pictures (12.5 fps). An attack frame with
;; a hit box that reaches the opponent's hurt box lands once per attack
;; (combat): blocked if the opponent holds back while free, otherwise damage,
;; a hit reaction for the move's hitstun, a knockdown for the sweep, the
;; uppercut, the special or any hit in the air, and at no health a KO.
;;
;; Every picture the stick goes into a motion history, turned to the
;; fighter's facing, so moves can ask for a motion: down, down-forward,
;; forward + a button for the special, down then up + punch for the
;; uppercut (down + punch also works).
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
MV_SPECIAL      EQU 12
MV_VICTORY      EQU 13

FRAME_PICS      EQU 2           ; pictures per animation frame
WALK_STEP       EQU 1           ; bytes per picture (2 mode 0 pixels)
JUMP_STEP       EQU 1           ; bytes per picture across, in a jump
JUMP_PICS       EQU 16          ; pictures in the air (jump_arc)
X_MAX           EQU BYTES_PER_LINE-SPR_W
MIN_SEP         EQU 10          ; closest two standing boxes may be (bytes)
HEALTH_MAX      EQU 40          ; a full health bar, one byte a point
HIT_PUSH        EQU 3           ; bytes a hit knocks the defender back,
BLOCK_PUSH      EQU 1           ; and a block
BLOCK_STUN      EQU 4           ; pictures a standing block holds at least
KD_PICS         EQU 36          ; a knockdown: falling, lying, getting up
HIST_LEN        EQU 12          ; pictures of motion history (0.48 s)
DR_UP           EQU 1           ; the history: the stick turned to the
DR_DOWN         EQU 2           ; fighter's facing
DR_BACK         EQU 4           ; (facing right these are the CT_ bits)
DR_FWD          EQU 8

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
    call record_motion
    ld a,(ix+F_MOVE)
    cp MV_JUMP
    jp z,th_jump
    cp MV_KO
    jp z,th_down
    cp MV_VICTORY
    jp z,animate_hold           ; and the winner stays up
    cp MV_BLOCK
    jp z,th_block
    cp MV_HIT
    jp z,th_stun
    cp MV_PUNCH
    jp nc,th_attack             ; attacks play out

    ;; Free: the special, attacks, then a jump, a crouch, a walk, or standing.
    ld a,b
    and 1<<CT_PUNCH|1<<CT_KICK
    jr z,th_no_kick
    ld hl,mo_special
    call motion
    jr nc,th_no_special
    call clear_motion           ; used up
    ld a,MV_SPECIAL
    jr th_go
th_no_special
    bit CT_PUNCH,b
    jr z,th_no_punch
    ld a,MV_UPPERCUT
    bit CT_DOWN,c
    jr nz,th_go
    ld hl,mo_uppercut
    call motion
    ld a,MV_UPPERCUT
    jr c,th_go
    ld a,MV_PUNCH
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

;; Blocking: held for BLOCK_STUN, then while back is held and the opponent
;; attacks.
th_block
    ld a,(ix+F_STUN)
    or a
    jr z,th_bl_free
    dec (ix+F_STUN)
    jp animate_hold
th_bl_free
    call back_held
    jr z,th_unblock
    call opp_attacking
    jp c,animate_hold
th_unblock
    ld a,MV_IDLE
    jp start_move

;; Down: a KO stays down. A knockdown falls (the KO frames) and lies there,
;; then gets up in the last 2 pictures a frame, the same frames backwards.
;; Nothing hits a fighter that is down or getting up (combat).
th_down
    ld a,(ix+F_HEALTH)
    or a
    jp z,animate_hold
    dec (ix+F_STUN)
    jr z,th_up
    ld a,(ix+F_NFR)
    add a,a
    cp (ix+F_STUN)
    jp c,animate_hold           ; falling or lying
    ld a,(ix+F_STUN)            ; getting up
    dec a
    srl a
    ld (ix+F_FRAME),a
    ret
th_up
    ld a,MV_IDLE
    call start_move
    jp face_opponent

;; Hit: the reaction plays, then holds for the rest of the hitstun.
th_stun
    call animate_hold
    dec (ix+F_STUN)
    ret nz
    ld a,MV_IDLE
    jp start_move

;; opp_attacking - IY = opponent: CY if it is in an attack.
;; attacking - A = move: CY if it is an attack. Destroy AF.
opp_attacking
    ld a,(iy+F_MOVE)
attacking
    cp MV_PUNCH
    ccf
    ret nc
    cp MV_BACKKICK+1
    ret c
    cp MV_SPECIAL
    scf
    ret z
    ccf
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
