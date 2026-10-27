;; ===========================================================================
;; discread.asm - a track off the disc (the driver: fdc.asm). Cold code in
;; a gap of the background mirror.
;; ===========================================================================

;; disc_track - the rest of track dk_trk, from sector dk_sec, into DISC_BUF:
;; sb_ptr at its start, sb_end past it, dk_trk and dk_sec on to the next
;; track's first. Destroys AF, BC, DE, HL.
disc_track
    call fdc_drain              ; on the track
    ld a,(dk_trk)
    ld (fdc_seek+3),a
    ld (fdc_read+3),a
    ld hl,fdc_seek
    call fdc_cmd
    call fdc_seekend
    ld hl,DISC_BUF
    ld (sb_ptr),hl
dt_sector
    call fdc_drain              ; a sector
    ld a,(dk_sec)
    ld (fdc_read+5),a
    ld (fdc_read+7),a           ; (the last sector: this one)
    push hl
    ld hl,fdc_read
    call fdc_cmd
    pop hl
    ld de,0
    ld bc,FDC_MSR
dt_wait
    in a,(c)
    jp m,dt_ready
    dec de
    ld a,d
    or e
    jr nz,dt_wait
    jp disc_fail
dt_ready
    and #20                     ; the data still coming?
    jr z,dt_end
    inc c                       ; 81 T a byte: in time
    in a,(c)
    ld (hl),a
    inc hl
    dec c
    jr dt_wait
dt_end
    call fdc_result
    ld a,(fdc_res+1)            ; ST1, but for end of cylinder
    and #37
    jp nz,disc_fail
    ld a,(fdc_res+2)            ; ST2
    and #77
    jp nz,disc_fail
    ld de,dk_sec                ; the next sector
    ld a,(de)
    inc a
    ld (de),a
    cp #C1+9
    jr c,dt_sector
    ld a,#C1
    ld (de),a
    inc de                      ; (dk_trk)
    ld a,(de)
    inc a
    ld (de),a
    ld (sb_end),hl
    ret
