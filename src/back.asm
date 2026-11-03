;; ===========================================================================
;; back.asm - ESC twice in a fight (exit.asm): back to the select screen
;; (BACK.BIN). In fighter A's bank 0 at EXIT_AT, past every character's
;; frames, as exit.asm is in fighter B's: exit.asm switches to this bank at
;; EX_SWITCH, and the code goes on here after it. The firmware is started
;; again, which then loads the select screen and the engine from the disc,
;; as PUPPET.BAS does: the loader leaves where MC START PROGRAM is at
;; bk_mcsp, 0 in a snapshot, where it switches back and goes on asking.
;; ===========================================================================

KL_ROM_WALK     EQU #BCCB
CAS_IN_OPEN     EQU #BC77
CAS_IN_CLOSE    EQU #BC7A
CAS_IN_DIRECT   EQU #BC83

back_start
bk_mcsp         defw 0          ; (the loader writes it)
    ASSERT bk_mcsp==EXIT_AT
    defs EX_SWITCH-$
    out (c),c                   ; back to fighter B's bank (exit.asm)
    ASSERT $==EX_SWITCH+2       ; (exit.asm's switch lands here)
    ld hl,(bk_mcsp)
    ld a,h
    or l
    ld bc,#7FC6
    jr z,EX_SWITCH
    di
    ld de,-(bk_entry_end-bk_entry)
    add hl,de
    push hl                     ; where bk_entry goes: it ends at MC START
    ld hl,bk_stub_store         ; PROGRAM. The rest below the bank, which
    ld de,STUB_AT               ; goes
    ld bc,bk_stub_end-STUB_AT
    ldir
    pop de
    push de
    ld hl,bk_entry
    ld bc,bk_entry_end-bk_entry
    ldir
    ret

;; Copied to just before MC START PROGRAM, in the lower ROM's place: once
;; the ROM is in, the next byte comes from it. The main RAM back, then the
;; firmware started again with a program at bk_prog (C: no ROM for it).
bk_entry
    ld bc,#7FC0
    out (c),c
    ld hl,bk_prog
    ld bc,#7FFF
    ld a,#89                    ; lower ROM in, upper out, mode 1
    out (c),a
bk_entry_end

;; Copied to STUB_AT.
bk_stub_store   EQU $
    ORG STUB_AT,EXIT_AT+bk_stub_store-back_start

;; The firmware's screen back (it leaves the CRTC as the game set it),
;; then as PUPPET.BAS: the disc's ROM, the select screen, the engine.
bk_prog
    ld hl,bk_crtc
    ld e,0
bk_crtc_reg
    ld b,#BC
    out (c),e
    ld b,#BD
    ld a,(hl)
    out (c),a
    inc hl
    inc e
    ld a,e
    cp bk_crtc_end-bk_crtc
    jr nz,bk_crtc_reg
    ld de,#0040
    ld hl,#ABFF
    call KL_ROM_WALK
    ld hl,bk_f_load
    ld de,#8000
    call bk_load
    call #8000
    ld bc,#7FC0
    out (c),c
    ld hl,bk_f_engine
    ld de,#4000
    call bk_load
    jp #4000

;; bk_load - HL = a file's name (10 characters), DE = where: load it.
bk_load
    push de
    ld b,10
    ld de,STUB_BUF
    call CAS_IN_OPEN
    pop hl
    call CAS_IN_DIRECT
    jp CAS_IN_CLOSE

bk_crtc         defb 63,40,46,#8E,38,0,25,30,0,7,0,0,#30,0     ; R0-R13
bk_crtc_end
bk_f_load       defb "PFLOAD.BIN"
bk_f_engine     defb "PUPPET.BIN"
bk_stub_end
    ASSERT bk_stub_end<=STUB_BUF
back_end        EQU bk_stub_store+bk_stub_end-STUB_AT
    ASSERT back_end<=#8000
