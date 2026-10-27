;; ===========================================================================
;; ladder.asm - the player against the computer: when the player wins a
;; match, the next opponent, the roster's next character but the player's,
;; comes off the disc with its home stage (fdc.asm, discread.asm, and
;; tools/make_dsk.py's map of the disc), and the match starts as the first
;; did.
;;
;; The screen black and the interrupts off, fighter B's file goes into
;; banks 6-7 and the stage into the screen, both unpacked as they come a
;; track at a time (stream_unpack, through DISC_BUF in the compiled frame
;; caches, which are free now). The stage covers the screen's tails too:
;; the workspace and the tables there start makes again, and the cold code
;; is kept aside meanwhile. The choices go back to SETTINGS_AT for start.
;; Cold code in gaps of the background mirror, this and nmstage.asm; the
;; map is in low RAM with stream_unpack.
;; ===========================================================================

DISC_BUF        EQU CACHE_AT            ; a track,
DISC_COLD       EQU DISC_BUF+9*512      ; the cold code while the stage
    ASSERT DISC_COLD+2*COLD_ROOM<=SETTINGS_AT   ; goes in
AMSDOS_HDR      EQU 128
PFC_HEADER      EQU 64                  ; tools/sprite_codegen.py

;; next_match - from victory_tick, the player having won. Never returns.
next_match
    di
    call set_black
    call sound_init
    ld hl,(sel_a)               ; L = the player's, H = the opponent's
    ld a,h
nm_next
    inc a
    cp DM_CHARS
    jr c,nm_in
    xor a
nm_in
    cp l
    jr z,nm_next
    ld h,a
    ld (nm_sel),hl
    ld a,(game_mode)
    ld (nm_mode),a
nm_load                         ; (disc_fail: again from here)
    ld sp,STACK_TOP
    call disc_on
    ld a,(nm_sel+1)             ; its files' places
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,dm_files
    add hl,de
    push hl
    call nm_file                ; the character, past its headers
    ld hl,DISC_BUF+AMSDOS_HDR+PFC_HEADER
    ld (sb_ptr),hl
    ld a,#C6
    ld hl,#4000
    call stream_unpack
    ld a,#C7
    ld hl,#4000
    call stream_unpack
    pop hl
    inc hl
    inc hl
    call nm_file
    jp nm_stage

;; nm_file - HL = a file's place (track, sector): its first track read.
nm_file
    ld a,(hl)
    ld (dk_trk),a
    inc hl
    ld a,(hl)
    ld (dk_sec),a
    jp disc_track
