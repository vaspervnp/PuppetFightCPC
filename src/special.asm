;; ===========================================================================
;; special.asm - specials that aren't strikes: projectiles and throws.
;;
;; A character's directory says what its special (down, down-forward,
;; forward + a button) does (F_SPKIND, loaded at start):
;;     strike       its hit frame lands like any attack (combat.asm)
;;     projectile   its hit frame fires the character's projectile from the
;;                  front of the hit box, unless one is still flying
;;     throw        its hit frame grabs an opponent on the ground in reach
;;                  and throws them over to the other side: a knockdown that
;;                  can't be blocked, only escaped by pressing back just as
;;                  the grab lands (holding it, a block, is too late)
;; A projectile flies F_PSPEED bytes a picture until it leaves the screen,
;; hits the opponent (blockable, with one point of chip damage that never
;; takes the last) or meets the other projectile, and both are gone.
;; Someone who is down lets it pass. It is drawn outside the rebuild
;; (main.asm shot_pass), and only where no fighter is drawn (shot_vis): it
;; is out of sight while it overlaps one, which for the opponent is the
;; picture it hits.
;;
;; Cold code in a gap of the background mirror (config.asm GAP1_ORG): it
;; may call into combat.asm, whose boxes pages a bank in and back out.
;; ===========================================================================

THROW_X         EQU 12          ; a throw lands this far behind the thrower
SHOT_TOP        EQU 160         ; projectiles fly no higher (main.asm
    ASSERT SHOT_TOP>=118+40     ; shot_pass: done 40 lines before)

;; special_strike - IX = attacker in its special, IY = defender, from
;; strike: fire or throw on the special's hit frame. Destroys everything
;; but IX, IY (which may swap).
special_strike
    ld hl,bx_a
    call boxes
    ld a,(bx_a+7)               ; not the frame that does it yet
    or a
    ret z
    ld (ix+F_HITDONE),1
    ld a,(ix+F_SPKIND)
    cp SP_THROW
    jr z,special_throw

;; Fire: from the front edge of the hit box, at its top line.
    ld a,(ix+F_PACT)
    or a
    ret nz
    ld a,(ix+F_FACE)
    ld (ix+F_PDIR),a
    or a
    ld a,(bx_a+4)
    jr z,fi_x
    ld a,(bx_a+5)               ; facing left: its right edge is the front
    inc a
    sub (ix+F_PW)
fi_x
    ld b,a                      ; all of it on the screen, or no shot
    ld a,BYTES_PER_LINE
    sub (ix+F_PW)
    cp b
    ret c
    ld (ix+F_PX),b
    ld a,(bx_a+6)
    cp SHOT_TOP
    jr nc,fi_y
    ld a,SHOT_TOP
fi_y
    ld (ix+F_PY),a
    ld (ix+F_PACT),1
    ld a,SFX_TWEET
    jp sfx_play

special_throw
    ld a,(iy+F_MOVE)            ; someone on the ground, and not down
    cp MV_KO
    ret z
    ld a,(iy+F_Y)
    cp FIGHTER_Y
    ret nz
    push ix
    push iy
    pop ix
    ld hl,bx_b
    call boxes
    pop ix
    ld hl,bx_a+4                ; in reach?
    ld de,bx_b
    call box_overlap
    ret nc
    push ix                     ; IX = defender from here, IY = thrower
    push iy
    pop ix
    pop iy
    ld a,(ix+F_MOVE)            ; escaped: back pressed just now (in the
    cp MV_BLOCK                 ; last two pictures, not held before)
    jr z,st_free                ; while free or blocking; the two just
    cp MV_CROUCH+1              ; come apart
    jr nc,st_land
st_free
    ld a,(ix+F_HIST)
    and DR_BACK
    jr z,st_land
    ld a,(ix+F_HIST+1)
    and (ix+F_HIST+2)
    and DR_BACK
    ld b,HIT_PUSH
    jp z,knock_back
st_land
    ld a,SFX_THROW
    call sfx_play
    ld a,(iy+F_FACE)            ; over the shoulder: to the thrower's back
    or a
    ld a,(iy+F_X)
    jr nz,st_right
    sub THROW_X
    jr st_set
st_right
    add a,THROW_X
st_set
    call set_x_wide             ; (the walls stop it)
    jp sk_hit                   ; the special's damage, a knockdown

;; ---------------------------------------------------------------------------
;; fly_shots - each picture, before combat: move both projectiles and see what
;; they hit. Destroys everything.
;; ---------------------------------------------------------------------------
fly_shots
    ld ix,fighter_a
    ld iy,fighter_b
    call shot_fly
    ld ix,fighter_b
    ld iy,fighter_a
    call shot_fly
    ld a,(fighter_a+F_PACT)     ; both still flying, and they meet: both
    ld hl,fighter_b+F_PACT      ; are gone
    and (hl)
    ret z
    ld ix,fighter_a
    ld hl,bx_a
    call shot_box
    ld ix,fighter_b
    ld hl,bx_b
    call shot_box
    ld hl,bx_a
    ld de,bx_b
    call box_overlap
    ret nc
    xor a
    ld (fighter_a+F_PACT),a
    ld (fighter_b+F_PACT),a
    ret

;; shot_fly - IX = owner, IY = opponent: one picture of IX's projectile.
shot_fly
    ld a,(ix+F_PACT)
    or a
    ret z
    ld a,(ix+F_PDIR)
    or a
    ld a,(ix+F_PX)
    jr nz,sy_left
    add a,(ix+F_PSPEED)
    jr sy_x
sy_left
    sub (ix+F_PSPEED)
sy_x
    ld b,a                      ; off the screen: gone
    ld a,BYTES_PER_LINE
    sub (ix+F_PW)
    cp b
    jr c,sy_gone
    ld (ix+F_PX),b
    ld a,(iy+F_MOVE)            ; it passes over someone who is down
    cp MV_KO
    ret z
    ld hl,bx_a
    call shot_box
    push ix
    push iy
    pop ix
    ld hl,bx_b                  ; the opponent's hurt box
    call boxes
    pop ix
    ld hl,bx_a
    ld de,bx_b
    call box_overlap
    ret nc
    ld (ix+F_PACT),0
    push ix                     ; IX = the one hit, IY = the owner
    push iy
    pop ix
    pop iy
    ld d,(iy+F_PDMG)
    ld e,(iy+F_PSTUN)
    call guard
    or a
    jp z,land_hit
    ld b,a                      ; blocked: a point of chip damage, but
    ld a,(ix+F_HEALTH)          ; never the last
    cp 2
    jr c,sy_block
    dec a
    ld (ix+F_HEALTH),a
    push bc
    call health_bar
    pop bc
sy_block
    ld a,b
    cp 2
    jp z,sk_crouch
    jp sk_block
sy_gone
    ld (ix+F_PACT),0
    ret

;; shot_box - IX = owner, HL = 4 bytes: its projectile's box (x0, x1, y0,
;; y1, inclusive). Destroys AF, HL.
shot_box
    ld a,(ix+F_PX)
    ld (hl),a
    inc hl
    add a,(ix+F_PW)
    dec a
    ld (hl),a
    inc hl
    ld a,(ix+F_PY)
    ld (hl),a
    inc hl
    add a,(ix+F_PH)
    dec a
    ld (hl),a
    ret
