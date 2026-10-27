;; ===========================================================================
;; pick.asm - who the ladder (ladder.asm) brings on next. In the payload
;; (the mirror's gaps are full in the SHOTS bench build).
;; ===========================================================================

;; nm_pick - nm_sel: the player's character and the next opponent, the
;; roster's next character but the player's, or the boss (the map's last,
;; DM_CHARS) once every other one is beaten; after the boss, the ladder
;; again. nm_mode: the choices as the select screen made them (the boss
;; plays at its hardest, nmstage.asm). Destroys AF, HL.
nm_pick
    ld hl,(sel_a)               ; L = the player's, H = the opponent's
    ld a,h
    cp DM_CHARS
    jr z,np_again
    ld a,(game_mode)            ; (not the boss's)
    ld (nm_mode),a
    ld a,(nm_wins)
    inc a
    cp DM_CHARS-1
    jr nc,np_boss
    ld (nm_wins),a
    ld a,h
    jr np_next
np_again
    xor a
    ld (nm_wins),a
    ld a,l
np_next
    inc a
    cp DM_CHARS
    jr c,np_in
    xor a
np_in
    cp l
    jr z,np_next
    jr np_set
np_boss
    ld a,DM_CHARS
np_set
    ld h,a
    ld (nm_sel),hl
    ret
