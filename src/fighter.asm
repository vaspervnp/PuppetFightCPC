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
;;
;; Cold code in a gap of the background mirror (config.asm GAP1_ORG), like
;; moves.asm, special.asm and input.asm: it only runs with main RAM at
;; #4000. The move numbers and rules (MV_*, ...) are in main.asm.
;; ===========================================================================


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
