;; ===========================================================================
;; nmstage.asm - the end of ladder.asm's load: the stage, whose first track
;; is in DISC_BUF, into the screen, then the match; and what a fault does.
;; Cold code in a gap of the background mirror.
;; ===========================================================================

nm_stage
    ld hl,DISC_BUF+AMSDOS_HDR+ST_INKS   ; its inks: pen 0, pens 14-15
    ld de,palette_game
    ldi
    ld de,palette_game+14
    ldi
    ldi
    ld hl,DISC_BUF+AMSDOS_HDR+ST_DATA
    ld (sb_ptr),hl
    ld hl,COLD_ORG              ; the cold code aside
    ld de,DISC_COLD
    ld bc,COLD_ROOM
    ldir
    ld hl,COLD2_ORG
    ld bc,COLD_ROOM
    ldir
    ld a,#C0
    ld hl,#8000
    call stream_unpack
    call disc_off
    ld hl,DISC_COLD             ; and back
    ld de,COLD_ORG
    ld bc,COLD_ROOM
    ldir
    ld de,COLD2_ORG
    ld bc,COLD_ROOM
    ldir
    ld a,(nm_sel+1)             ; the boss plays its hardest
    cp DM_CHARS
    ld a,(nm_mode)
    jr nz,ns_mode
    and 255-(3<<GM_LEVEL)
    or 2<<GM_LEVEL
ns_mode
    ld (SETTINGS_AT),a
    ld hl,(nm_sel)
    ld (SETTINGS_AT+1),hl
    jp start

;; disc_fail - a fault: start the load again, the border red meanwhile.
disc_fail
    ld sp,STACK_TOP
    ld bc,#7F10
    out (c),c
    ld a,#4C
    out (c),a
    jp nm_load
