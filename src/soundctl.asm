;; ===========================================================================
;; soundctl.asm - what the game calls to make sound happen (sound.asm plays
;; it, from an interrupt). Cold code in a gap of the background mirror
;; (GAP7_ORG).
;; ===========================================================================

;; sound_init - silence, with interrupts off (before irq_init). Destroys
;; AF, BC, DE, HL.
sound_init
    ld hl,psg_buf              ; what to write: silence, port A an input
    ld de,psg_buf+1
    ld bc,2*PSG_REGS-1
    ld (hl),0
    ldir
    ld a,#3F                    ; mixer: everything off
    ld (psg_buf+R_MIXER),a
    ld (psg_buf+R_MIXER+1),a
    ld bc,#F782                 ; PPI port A an output
    out (c),c
    ld hl,psg_buf
    ld e,0
si_all
    ld c,(hl)
    call psg_write
    inc hl
    inc hl
    inc e
    ld a,e
    cp PSG_REGS
    jr nz,si_all
    ret

;; music_play - HL = a song (speed, then three order lists): play it from
;; the start. music_stop - silence the music. Destroy AF, B, DE, HL, IX.
music_play
    di
    ld a,(hl)
    inc hl
    ld (song_speed),a
    ld a,1
    ld (row_tick),a
    ld ix,ch_a
    call mp_chan
    ld ix,ch_b
    call mp_chan
    ld ix,ch_c
    call mp_chan
    ld a,1
    jr ms_set
music_stop
    xor a
ms_set
    ld (music_on),a
    ei
    ret
mp_chan
    ld e,(hl)                   ; its order list
    inc hl
    ld d,(hl)
    inc hl
    ld (ix+C_ORD),e
    ld (ix+C_ORD+1),d
    ld de,pat_end               ; on the first row: the first pattern
    ld (ix+C_PTR),e
    ld (ix+C_PTR+1),d
    ld (ix+C_WAIT),1
    ld (ix+C_DUR),1
    ld de,silence
    ld (ix+C_INST),e
    ld (ix+C_INST+1),d
    ld (ix+C_IBASE),e
    ld (ix+C_IBASE+1),d
    ret

;; sfx_play - A = a sound effect (SFX_*): play it, unless one that wins
;; over it is already asked for. Destroys AF, HL.
sfx_play
    ld hl,sfx_req
    cp (hl)
    ret c
    ld (hl),a
    ret
