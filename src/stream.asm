;; ===========================================================================
;; stream.asm - a file into memory as it comes off the disc (ladder.asm),
;; and the disc code's variables. In low RAM, under the stack (LOW_ORG):
;; it pages the banks in at #4000, and calls the disc code (in the mirror's
;; gaps) with main RAM back. The stage goes over the screen's tails, the
;; workspace too, so what the load needs is here.
;; ===========================================================================

;; stream_unpack - A = a RAM configuration, HL = where: the file's next
;; packed part (tools/stage_pack.py) there, unpacked as it comes: n < #7F:
;; n + 1 bytes as they are; n >= #80: n - #7D bytes from an offset word
;; back; #7F: the end. Comes back with main RAM. Destroys everything.
stream_unpack
    ld (su_page+1),a
    call su_page
su_next
    call su_get
    cp #7F
    jr z,su_end
    jr nc,su_match
    inc a
    ld b,a
su_lit
    call su_get
    ld (hl),a
    inc hl
    djnz su_lit
    jr su_next
su_match
    sub #7D
    ld c,a
    ld b,0
    call su_get                 ; the offset
    ld e,a
    call su_get
    ld d,a
    push hl
    or a
    sbc hl,de                   ; where it comes from
    pop de
    ldir
    ex de,hl
    jr su_next
su_end
    ld a,#C0
    jr su_out

;; su_get - A = the file's next byte: the next track off the disc when the
;; one read runs out. Keeps BC, DE, HL.
su_get
    push hl
    push de
    ld hl,(sb_ptr)
    ld de,(sb_end)
    or a
    sbc hl,de
    jr nz,sg_byte
    push bc
    ld a,#C0
    call su_out
    call disc_track
    call su_page
    pop bc
sg_byte
    ld hl,(sb_ptr)
    ld a,(hl)
    inc hl
    ld (sb_ptr),hl
    pop de
    pop hl
    ret
su_page
    ld a,0                      ; (stream_unpack's configuration)
su_out
    push bc
    ld bc,#7F00
    out (c),a
    pop bc
    ret

sb_ptr          defw 0          ; the next byte of the track read, its end
sb_end          defw 0
dk_sec          defb 0          ; discread.asm: where the next sector
dk_trk          defb 0          ; comes from (in this order)
fdc_res         defs 7          ; fdc.asm: the last result phase
fdc_seek        defb 3,#0F,0,0  ; seek: drive A, the track
fdc_read        defb 9,#46,0,0,0,0,2,0,#2A,#FF  ; read data: track, head,
                                ; sector, 512 bytes, the last, gap, length
nm_sel          defw 0          ; ladder.asm: the player's character, the
nm_mode         defb 0          ; opponent's, and game_mode, through the load

    include "gen/diskmap.asm"
