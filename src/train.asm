;; ===========================================================================
;; train.asm - training's own code (TRAIN.BIN), in the dummy's bank 0 at
;; TRAIN_AT, past its frames: the loader puts it there in training only, so
;; it costs the engine nothing but the jump to it (traingo.asm, then
;; exit.asm's first lines).
;;
;; Once a picture, in place of the computer's controls for fighter B
;; (ai.asm ap_b), with the bank paged in: what the dummy does, the choice
;; on the select screen (game_mode's level bits: stand, crouch, jump or
;; block). It reads only the workspace, never the mirror's gaps, which
;; the bank hides.
;; ===========================================================================

TD_STAND        EQU 0           ; the dummy's choices
TD_CROUCH       EQU 1
TD_JUMP         EQU 2
TD_BLOCK        EQU 3
TR_SHOT_NEAR    EQU 24          ; a projectile this close is blocked

train_start
    ld a,(rnd_state)            ; between rounds nobody moves
    or a
    ld a,0
    jr nz,tr_set
    ld a,(game_mode)
    and 3<<GM_LEVEL
    jr z,tr_set                 ; TD_STAND
    cp TD_JUMP<<GM_LEVEL
    ld a,1<<CT_UP               ; one hop after another
    jr z,tr_set
    ld a,1<<CT_DOWN
    jr c,tr_set                 ; TD_CROUCH
    ld c,0                      ; TD_BLOCK: back while a projectile is
    ld a,(fighter_a+F_PACT)     ; close
    or a
    jr z,tr_attack
    ld a,(fighter_a+F_PX)
    ld hl,fighter_b+F_X
    sub (hl)
    jr nc,tr_near
    neg
tr_near
    cp TR_SHOT_NEAR
    jr c,tr_high
tr_attack
    ld a,(fighter_a+F_MOVE)     ; or an attack comes (fighter.asm
    cp MV_SPECIAL               ; attacking)
    jr z,tr_high
    cp MV_PUNCH
    jr c,tr_none
    cp MV_BACKKICK+1
    jr nc,tr_none
    cp MV_SWEEP                 ; low against a sweep
    jr nz,tr_high
    ld c,1<<CT_DOWN
tr_high
    ld a,(fighter_b+F_FACE)     ; back: away from the way it faces
    or a
    ld a,1<<CT_LEFT
    jr z,tr_dir
    ld a,1<<CT_RIGHT
tr_dir
    or c
    jr tr_set
tr_none
    xor a
tr_set
    ld (fighter_b+F_CTL),a
    jp page_main                ; the bank out again, and back
train_end
