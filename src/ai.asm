;; ===========================================================================
;; ai.asm - the computer as a player. It makes a fighter's controls the way
;; a player would, so the rest of the game can't tell: once a picture,
;; after the keys are read, ai_players replaces the controls of each
;; fighter the select screen gave it (game_mode).
;;
;; It looks again every few pictures (fewer the harder it plays), and what
;; it chose stays held until then; sooner when an attack comes (within its
;; level's reaction time), and at once when it is free after a hit. It blocks attacks close by (and once
;; blocking, goes on while they keep coming) and
;; projectiles coming at it (or jumps them), uppercuts someone jumping in,
;; mixes attacks at close range (punch from a little further), and walks in
;; from afar, or fires its projectile if it has one. The chance of each is
;; its level's. The special's motion takes three pictures (F_AISEQ).
;;
;; Controls are worked out as if the fighter faced right (back is left,
;; forward right, like the motion history) and turned at the end.
;;
;; Cold code in a gap of the background mirror (GAP8_ORG).
;; ===========================================================================

AI_UP           EQU 1<<CT_UP
AI_DOWN         EQU 1<<CT_DOWN
AI_BACK         EQU 1<<CT_LEFT
AI_FWD          EQU 1<<CT_RIGHT
AI_PUNCH        EQU 1<<CT_PUNCH
AI_KICK         EQU 1<<CT_KICK
AI_REACH        EQU 11          ; bytes apart (box x) where every attack
AI_PUNCH_REACH  EQU 13          ; lands, and the punch (MIN_SEP is 10)
AI_GUARD        EQU 16          ; an attack this close is worth blocking
AI_SHOT_NEAR    EQU 24          ; a projectile this close too
AI_FAR          EQU 20          ; far enough to fire one

L_REACT         EQU 0           ; a level: pictures between looks and a
L_JITTER        EQU 1           ; random number more (a mask), then
L_BLOCK         EQU 2           ; chances out of 256: block (an attack, a
L_LOW           EQU 3           ; projectile), low as well, uppercut a
L_ANTI          EQU 4           ; jump, attack at close range, fire from
L_ATTACK        EQU 5           ; afar
L_SHOOT         EQU 6
L_SIZE          EQU 7

ai_levels
    defb 4,7,120,40,70,130,50       ; easy
    defb 2,3,190,150,150,180,90     ; normal
    defb 1,1,225,235,210,220,140    ; hard

ai_attacks                      ; at close range (0: the special)
    defb AI_PUNCH,AI_KICK,AI_DOWN|AI_KICK,AI_DOWN|AI_PUNCH
    defb AI_BACK|AI_KICK,0,AI_PUNCH,AI_KICK

ai_special                      ; its motion, last step first: down,
    defb AI_FWD|AI_PUNCH,AI_DOWN|AI_FWD,AI_DOWN     ; down-forward, forward + punch

;; ai_players - the computer's controls for the fighters it plays.
;; Destroys everything.
ai_players
    ld a,(game_mode)
    bit GM_CPU_A,a
    jr z,ap_b
    ld ix,fighter_a
    ld iy,fighter_b
    call ai_tick
    ld (fighter_a+F_CTL),a
ap_b
    ld a,(game_mode)
    bit GM_CPU_B,a
    ret z
    ld ix,fighter_b
    ld iy,fighter_a
    call ai_tick
    ld (fighter_b+F_CTL),a
    ret

;; ai_tick - IX = a fighter the computer plays, IY = its opponent: A = its
;; controls this picture (CT_ bits). Destroys everything but IX, IY.
ai_tick
    ld a,(rnd_state)            ; between rounds nobody moves
    or a
    ld a,0
    ret nz
    ld a,(ix+F_AISEQ)
    or a
    jr nz,at_seq
    ld a,(ix+F_MOVE)            ; hit or down: a fresh look once free
    cp MV_HIT
    jr z,at_busy
    cp MV_KO
    jr nz,at_threat
at_busy
    ld (ix+F_AIWAIT),1
    xor a
    ret
at_threat
    call opp_attacking          ; an attack: look again within its time
    jr nc,at_wait               ; to react
    ld e,L_REACT
    call ai_level
    ld a,(ix+F_AIWAIT)
    cp (hl)
    jr c,at_wait
    ld a,(hl)
    ld (ix+F_AIWAIT),a
at_wait
    ld a,(ix+F_AIWAIT)          ; time to look again?
    or a
    jr z,at_choose
    dec a
    ld (ix+F_AIWAIT),a
    jr nz,at_hold
at_choose
    call ai_choose
    ld a,(ix+F_AISEQ)
    or a
    jr nz,at_seq
at_hold
    ld a,(ix+F_AIHOLD)          ; a button for one picture: pressed once
    ld c,a
    and AI_UP|AI_DOWN|AI_BACK|AI_FWD
    ld (ix+F_AIHOLD),a
    ld a,c
    jr at_turn
at_seq
    dec a                       ; the special's next step
    ld (ix+F_AISEQ),a
    ld e,a
    ld d,0
    ld hl,ai_special
    add hl,de
    ld a,(hl)
at_turn
    bit 0,(ix+F_FACE)           ; facing left: back and forward swap
    ret z
    ld c,a
    and #FF-AI_BACK-AI_FWD
    bit CT_LEFT,c
    jr z,at_left
    or AI_FWD
at_left
    bit CT_RIGHT,c
    ret z
    or AI_BACK
    ret

;; ai_choose - IX = fighter, IY = opponent: what to hold until it looks
;; again (F_AIHOLD, or F_AISEQ for the special), and when that is
;; (F_AIWAIT). Destroys AF, BC, DE, HL.
ai_choose
    call ai_rnd
    ld c,a
    ld e,L_JITTER
    call ai_level
    ld a,c
    and (hl)
    dec hl
    add a,(hl)
    ld (ix+F_AIWAIT),a
    ld (ix+F_AIHOLD),0
    ld a,(ix+F_X)               ; B = how far apart
    sub (iy+F_X)
    jr nc,ac_dx
    neg
ac_dx
    ld b,a

    ld a,(iy+F_PACT)            ; a projectile coming at it?
    or a
    jr z,ac_noshot
    ld a,(iy+F_PX)
    sub (ix+F_X)
    jr nc,ac_sright
    neg                         ; from the left: coming if it flies right
    ld c,a
    ld a,(iy+F_PDIR)
    jr ac_scome
ac_sright
    ld c,a                      ; from the right: if it flies left
    ld a,(iy+F_PDIR)
    xor 1
ac_scome
    or a
    jr nz,ac_noshot
    ld a,c
    cp AI_SHOT_NEAR
    jr nc,ac_noshot
    ld e,L_BLOCK
    call ai_chance
    jr nc,ac_noshot
    call ai_rnd                 ; block it low, or jump it
    rra
    ld a,AI_DOWN|AI_BACK
    jr nc,ac_hold
    ld a,AI_UP|AI_FWD
    jr ac_hold

ac_noshot
    call opp_attacking          ; an attack close by: block
    jr nc,ac_calm
    ld a,b
    cp AI_GUARD
    jr nc,ac_calm
    ld a,(ix+F_MOVE)            ; blocking already: it goes on (only the
    cp MV_BLOCK                 ; first reaction is a matter of chance)
    jr z,ac_guard
    cp MV_CROUCH
    jr z,ac_guard
    ld e,L_BLOCK
    call ai_chance
    jr nc,ac_calm
ac_guard
    ld e,L_LOW                  ; low blocks anything
    call ai_chance
    ld a,AI_BACK
    jr nc,ac_hold
    ld a,AI_DOWN|AI_BACK
ac_hold
    ld (ix+F_AIHOLD),a
    ret

ac_calm
    ld a,(iy+F_MOVE)            ; someone jumping in: uppercut, or get
    cp MV_JUMP                  ; out of the way
    jr nz,ac_ground
    ld a,b
    cp AI_GUARD
    ret nc
    ld e,L_ANTI
    call ai_chance
    ld a,AI_DOWN|AI_PUNCH
    jr c,ac_hold
    ld a,AI_BACK
    jr ac_hold

ac_ground
    ld a,b                      ; close: an attack, or wait
    cp AI_REACH+1
    jr nc,ac_apart
    ld e,L_ATTACK
    call ai_chance
    ret nc
    call ai_rnd
    and 7
    ld e,a
    ld d,0
    ld hl,ai_attacks
    add hl,de
    ld a,(hl)
    or a
    jr nz,ac_hold
    ld a,(ix+F_SPKIND)          ; the special, unless it fires (a punch)
    cp SP_SHOT
    ld a,AI_PUNCH
    jr z,ac_hold
ac_special
    ld (ix+F_AISEQ),3
    ret

ac_apart
    cp AI_PUNCH_REACH+1         ; a little further: a punch, or closer
    jr nc,ac_far
    ld e,L_ATTACK
    call ai_chance
    ld a,AI_PUNCH
    jr c,ac_hold
    ld a,AI_FWD
    jp ac_hold

ac_far
    ld a,(ix+F_SPKIND)          ; its projectile, if none is flying
    cp SP_SHOT
    jr nz,ac_walk
    ld a,(ix+F_PACT)
    or a
    jr nz,ac_walk
    ld a,b
    cp AI_FAR
    jr c,ac_walk
    ld e,L_SHOOT
    call ai_chance
    jr c,ac_special
ac_walk
    call ai_rnd                 ; in, or now and then a jump in or a step
    and 15                      ; back
    ld c,a
    ld a,AI_UP|AI_FWD
    jr z,ac_hold
    dec c
    ld a,AI_BACK
    jr z,ac_hold
    ld a,AI_FWD
    jp ac_hold

;; ai_chance - E = a chance in the level record: CY with that chance.
;; Destroys AF, C, HL.
ai_chance
    call ai_rnd
    ld c,a
    call ai_level
    ld a,c
    cp (hl)
    ret

;; ai_level - E = a place in the level record: HL = it. Destroys AF.
ai_level
    ld a,(game_mode)
    and 3<<GM_LEVEL
    rrca
    rrca
    ld l,a                      ; * L_SIZE
    add a,a
    add a,a
    add a,a
    sub l
    add a,e
    ld hl,ai_levels
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ret
    ASSERT L_SIZE==7

;; ai_rnd - A = a random byte: a 16-bit xorshift (John Metcalf's). Not
;; stirred with anything that depends on timing, so a game with the same
;; controls plays the same (the bench). Destroys F, HL.
ai_rnd
    ld hl,(ai_rnd_seed)
    ld a,h
    or l
    jr nz,ar_go
    inc l                       ; (never all zeros)
ar_go
    ld a,h
    rra
    ld a,l
    rra
    xor h
    ld h,a
    ld a,l
    rra
    ld a,h
    rra
    xor l
    ld l,a
    xor h
    ld h,a
    ld (ai_rnd_seed),hl
    ret
