;; ===========================================================================
;; train.asm - training's own code (TRAIN.BIN), in the dummy's bank 0 at
;; TRAIN_AT, past its frames: the loader puts it there in training only, so
;; it costs the engine nothing but the jump to it (traingo.asm).
;;
;; Once a picture, in place of the computer's controls for fighter B
;; (ai.asm ap_b), with the bank paged in: what the dummy does, the choice
;; on the select screen (game_mode's level bits: stand, crouch, jump or
;; block). It reads only the workspace, never the mirror's gaps, which
;; the bank hides. ESC goes back to the select screen: the firmware is
;; started again, which then loads the select screen and the engine from
;; the disc, as PUPPET.BAS does (the loader leaves where MC START PROGRAM
;; is at tr_mcsp; 0 in a snapshot, where ESC does nothing).
;; ===========================================================================

TD_STAND        EQU 0           ; the dummy's choices
TD_CROUCH       EQU 1
TD_JUMP         EQU 2
TD_BLOCK        EQU 3
TR_SHOT_NEAR    EQU 24          ; a projectile this close is blocked

KL_ROM_WALK     EQU #BCCB
CAS_IN_OPEN     EQU #BC77
CAS_IN_CLOSE    EQU #BC7A
CAS_IN_DIRECT   EQU #BC83

train_start
    jr tr_tick
tr_mcsp         defw 0
    ASSERT tr_mcsp==TRAIN_AT+2  ; (the loader writes it)

tr_tick
    ld a,(key_rows+8)           ; ESC: back to the select screen
    and #04
    jr z,tr_exit
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

tr_exit
    ld hl,(tr_mcsp)
    ld a,h
    or l
    jr z,tr_none
    di
    ld de,-(tr_entry_end-tr_entry)
    add hl,de
    push hl                     ; where tr_entry goes: it ends at MC START
    ld hl,tr_stub_store         ; PROGRAM. The rest below the bank, which
    ld de,STUB_AT               ; goes
    ld bc,tr_stub_end-STUB_AT
    ldir
    pop de
    push de
    ld hl,tr_entry
    ld bc,tr_entry_end-tr_entry
    ldir
    ret

;; Copied to just before MC START PROGRAM, in the lower ROM's place: once
;; the ROM is in, the next byte comes from it. The main RAM back, then the
;; firmware started again with a program at tr_prog (C: no ROM for it).
tr_entry
    ld bc,#7FC0
    out (c),c
    ld hl,tr_prog
    ld bc,#7FFF
    ld a,#89                    ; lower ROM in, upper out, mode 1
    out (c),a
tr_entry_end

;; Copied to STUB_AT.
tr_stub_store   EQU $
    ORG STUB_AT,TRAIN_PHYS+tr_stub_store-TRAIN_AT

;; The firmware's screen back (it leaves the CRTC as the game set it),
;; then as PUPPET.BAS: the disc's ROM, the select screen, the engine.
tr_prog
    ld hl,tr_crtc
    ld e,0
tr_crtc_reg
    ld b,#BC
    out (c),e
    ld b,#BD
    ld a,(hl)
    out (c),a
    inc hl
    inc e
    ld a,e
    cp tr_crtc_end-tr_crtc
    jr nz,tr_crtc_reg
    ld de,#0040
    ld hl,#ABFF
    call KL_ROM_WALK
    ld hl,tr_f_load
    ld de,#8000
    call tr_load
    call #8000
    ld bc,#7FC0
    out (c),c
    ld hl,tr_f_engine
    ld de,#4000
    call tr_load
    jp #4000

;; tr_load - HL = a file's name (10 characters), DE = where: load it.
tr_load
    push de
    ld b,10
    ld de,STUB_BUF
    call CAS_IN_OPEN
    pop hl
    call CAS_IN_DIRECT
    jp CAS_IN_CLOSE

tr_crtc         defb 63,40,46,#8E,38,0,25,30,0,7,0,0,#30,0     ; R0-R13
tr_crtc_end
tr_f_load       defb "PFLOAD.BIN"
tr_f_engine     defb "PUPPET.BIN"
tr_stub_end
    ASSERT tr_stub_end<=STUB_BUF
train_end       EQU tr_stub_store+tr_stub_end-STUB_AT
