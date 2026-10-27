;; ===========================================================================
;; logic.asm - the logic's entry point: each picture, the next picture's
;; frames and positions, from the players or (DEMO=1) a script. Cold code in
;; a gap of the background mirror (GAP6_ORG): load_frame, which pages a
;; character's bank in, stays in the payload and comes back with main RAM.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; logic - next picture's frames and positions.
;;
;; The game: read both players' controls, let each fighter think
;; (fighter.asm), keep them apart, and fetch the frames they now show.
;; With -DDEMO=1 the fighters follow a script instead (logic_demo), which
;; is what the bench scenarios measure.
;; ---------------------------------------------------------------------------
logic
    ld hl,render_count
    inc (hl)
    IF DEMO
    jp logic_demo
    ELSE
    call read_controls
    ld a,(rnd_state)            ; between rounds nobody moves
    or a
    jr z,lg_ctl
    xor a
    ld (p1_ctl),a
    ld (p2_ctl),a
lg_ctl
    ld a,(p1_ctl)
    ld (fighter_a+F_CTL),a
    ld a,(p2_ctl)
    ld (fighter_b+F_CTL),a
    call ai_players             ; or the computer's (ai.asm)
    ld ix,fighter_a
    ld iy,fighter_b
    call think
    ld ix,fighter_b
    ld iy,fighter_a
    call think
    call separate
    call fly_shots              ; projectiles (special.asm), then attacks
    call combat
    call round_tick
    ld ix,fighter_a
    call load_frame
    ld ix,fighter_b
    jp load_frame
    ENDIF

;; logic_demo - idle advances every second picture; both fighters sway a
;; few bytes to and fro so the restore has somewhere to put the ground back;
;; with JUMP=1 they jump in turns, then together.
logic_demo
    ld hl,render_count
    ld a,(hl)
    rra
    and 3
    ld (fighter_a+F_FRAME),a
    ld (fighter_b+F_FRAME),a
    xor a
    ld (fighter_a+F_MOVE),a
    ld (fighter_b+F_MOVE),a

    ld a,(render_count)
    rra
    and 31
    ld e,a
    ld d,0
    ld hl,sway
    add hl,de
    ld b,(hl)
    ld a,TRUMP_X0
    add a,b
    ld (fighter_a+F_X),a
    ld a,PUTIN_X0
    sub b
    ld (fighter_b+F_X),a

    ;; Jumps (JUMP=1): a 48-picture cycle - Trump jumps, then Putin, then
    ;; both together. Otherwise both stand.
    ld a,FIGHTER_Y
    ld (fighter_a+F_Y),a
    ld (fighter_b+F_Y),a
    IF JUMP
    ld a,(render_count)
lg_mod48
    cp 48
    jr c,lg_mod_ok
    sub 48
    jr lg_mod48
lg_mod_ok
    ld c,a
    and 15
    ld e,a
    ld d,0
    ld hl,jump_arc
    add hl,de
    ld a,FIGHTER_Y
    sub (hl)
    ld b,a                      ; B = the airborne top line
    ld a,c
    cp 16
    jr c,lg_a_jumps
    cp 32
    jr c,lg_b_jumps
    ld a,b                      ; both
    ld (fighter_a+F_Y),a
lg_b_jumps
    ld a,b
    ld (fighter_b+F_Y),a
    jr lg_frames
lg_a_jumps
    ld a,b
    ld (fighter_a+F_Y),a
lg_frames
    ENDIF
    IF SHOTS                    ; SHOTS=1: projectiles (of characters that
    ld ix,fighter_a             ; have one) sweep across, A's to the right,
    ld c,0                      ; B's to the left
    call demo_shot
    ld ix,fighter_b
    ld c,1
    call demo_shot
    ENDIF
    ld ix,fighter_a
    call load_frame
    ld ix,fighter_b
    jp load_frame

    IF SHOTS
;; demo_shot - IX = fighter, C = direction: its projectile at hand height,
;; 2 bytes on every picture over 32 pictures, then round again.
demo_shot
    ld a,(ix+F_SPKIND)
    cp SP_SHOT
    ret nz
    ld (ix+F_PACT),1
    ld (ix+F_PDIR),c
    ld (ix+F_PY),FIGHTER_Y+27
    ld a,(render_count)
    and 31
    add a,a
    dec c
    jr nz,ds_x
    neg
    add a,BYTES_PER_LINE-16
    jr ds_set
ds_x
    add a,8
ds_set
    ld (ix+F_PX),a
    ret
    ENDIF

jump_arc                        ; rise and fall over 16 pictures, top at
    defb 7,21,32,42,50,55,59,60,60,59,55,50,42,32,21,7  ; JUMP_MAX lines
    ASSERT JUMP_MAX>=60

sway                            ; -6..6, a triangle over 32 steps
    defb 0,1,2,3,4,5,6,6,6,5,4,3,2,1,0,0
    defb 0,-1,-2,-3,-4,-5,-6,-6,-6,-5,-4,-3,-2,-1,0,0
