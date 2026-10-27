;; ===========================================================================
;; sound.asm - music and sound effects on the AY-3-8912, from an interrupt.
;;
;; sound_tick runs in the handler of interrupt SOUND_IRQ (line ~118), 50
;; times a second. The rebuild has finished the fighters' top half by then
;; (it starts on line 170: config.asm), and in the frame before a picture's
;; tick the compiler has stopped by then anyway. A character's bank may be paged in at #4000, so
;; all of this, code and data, is in the payload. read_controls keeps
;; interrupts off while it has the PSG's port A turned round.
;;
;; Music: three channels, each an order list of patterns (tools/music.py,
;; gen/music.asm). A pattern is bytes:
;;     #00-#47   a note (0 = C1, to B6), held for the duration
;;     #60       a rest, for the duration
;;     #80-#BF   the duration: n - #7F rows
;;     #C0-#DF   the instrument: n - #C0
;;     #FF       the end: the next pattern in the order list
;; An order list is pattern addresses, then 0 and where to go round from.
;; An instrument is its noise period, then a step per interrupt: volume
;; (bits 0-3), noise on (bit 4), tone off (bit 5), an octave up (bit 6);
;; #80 holds the step before it.
;;
;; Sound effects play on channel C over the music's drums: a record of
;; SFX_SIZE bytes (gen/music.asm) whose tone sweeps and whose volume decays.
;; A higher number wins over a lower one.
;;
;; What the rest of the game calls (sound_init, music_play, music_stop,
;; sfx_play) is in soundctl.asm, in a gap of the mirror.
;; ===========================================================================

SOUND_IRQ       EQU TICK_IRQ-1  ; line ~118, the period before the tick

C_PTR           EQU 0           ; a channel: where it is in its pattern,
C_ORD           EQU 2           ; and in its order list, rows to its next
C_WAIT          EQU 4           ; event, the duration, its instrument's
C_DUR           EQU 5           ; step and first step, its noise period,
C_INST          EQU 6           ; the note's tone period
C_IBASE         EQU 8
C_NOISE         EQU 10
C_PER           EQU 11
C_SIZE          EQU 13

S_FLAGS         EQU 0           ; a sound effect: bit 0 tone, bit 1 noise,
S_NOISE         EQU 1           ; its noise period, tone period, the
S_PER           EQU 2           ; period's change per interrupt (signed),
S_DPER          EQU 4           ; volume, interrupts per step down (0:
S_VOL           EQU 6           ; none), length, and interrupts before the
S_DECAY         EQU 7           ; tone starts again from its period (0:
S_LEN           EQU 8           ; never)
S_REP           EQU 9
SFX_SIZE        EQU 10
PSG_REGS        EQU 11          ; registers 0-10 (port A's 14 is the keys')

;; psg_buf holds each register's next value followed by what was last
;; written to it, all in one page: register r at psg_buf + 2 * r.
R_TONE          EQU 0
R_NOISE         EQU 2*6
R_MIXER         EQU 2*7
R_VOL           EQU 2*8

;; CHANNEL - channel {n} (record {ch}): its instrument's step, its tone
;; period (an octave up if the step says), its volume, and its tone and noise
;; into the mixer in D (its noise period into register 6). Destroys AF, C, HL.
    MACRO CHANNEL ch,n
    ld hl,({ch}+C_INST)
    ld a,(hl)
    cp #80
    jr nz,@step
    dec hl                      ; held
    ld a,(hl)
@step
    inc hl
    ld ({ch}+C_INST),hl
    ld c,a
    ld hl,({ch}+C_PER)
    bit 6,c
    jr z,@period
    srl h                       ; an octave up
    rr l
@period
    ld a,l
    ld (psg_buf+R_TONE+4*{n}),a
    ld a,h
    ld (psg_buf+R_TONE+4*{n}+2),a
    ld a,c
    and #0F
    ld (psg_buf+R_VOL+2*{n}),a
    bit 5,c
    jr nz,@notone
    res {n},d
@notone
    bit 4,c
    jr z,@nonoise
    res {n}+3,d
    ld a,({ch}+C_NOISE)
    ld (psg_buf+R_NOISE),a
@nonoise
    MEND

;; PSG_REG - HL = register {r}'s place in psg_buf: write it if it changed,
;; and HL to the next. Destroys AF, BC, E.
    MACRO PSG_REG r
    ld a,(hl)
    inc l
    cp (hl)
    jr z,@same
    ld (hl),a
    ld c,a
    ld e,{r}
    call psg_write
@same
    inc l
    MEND

;; sound_tick - one interrupt's worth: the music's rows when they are due,
;; each channel's instrument, the sound effect, then the registers that
;; changed. Destroys AF, BC, HL (the handler keeps them).
sound_tick
    push de
    ld a,(music_on)
    or a
    jp z,st_quiet
    ld hl,row_tick
    dec (hl)
    jr nz,st_env
    ld a,(song_speed)
    ld (hl),a
    push ix
    ld ix,ch_a
    call ch_row
    ld ix,ch_b
    call ch_row
    ld ix,ch_c
    call ch_row
    pop ix
st_env
    ld d,#3F                    ; D = the mixer, built up
    CHANNEL ch_a,0
    CHANNEL ch_b,1
    CHANNEL ch_c,2
    jr st_sfx
st_quiet
    ld d,#3F
    xor a
    ld (psg_buf+R_VOL),a
    ld (psg_buf+R_VOL+2),a
    ld (psg_buf+R_VOL+4),a
st_sfx
    call sfx_tick
    ld a,d
    ld (psg_buf+R_MIXER),a
    ld hl,psg_buf               ; the registers that changed
    PSG_REG 0
    PSG_REG 1
    PSG_REG 2
    PSG_REG 3
    PSG_REG 4
    PSG_REG 5
    PSG_REG 6
    PSG_REG 7
    PSG_REG 8
    PSG_REG 9
    PSG_REG 10
    ASSERT PSG_REGS==11
    pop de
    ret

;; psg_write - C into PSG register E. Destroys AF, B.
psg_write
    ld b,#F4                    ; the register on port A
    out (c),e
    ld b,#F6                    ; select it
    ld a,#C0
    out (c),a
    xor a
    out (c),a
    ld b,#F4                    ; the value
    out (c),c
    ld b,#F6                    ; write it
    ld a,#80
    out (c),a
    xor a
    out (c),a
    ret

;; ch_row - IX = channel: a row of its music. Destroys AF, BC, DE, HL.
ch_row
    dec (ix+C_WAIT)
    ret nz
    ld l,(ix+C_PTR)
    ld h,(ix+C_PTR+1)
cr_next
    ld a,(hl)
    inc hl
    cp #60
    jr c,cr_note
    jr z,cr_rest
    cp #FF
    jr z,cr_end
    cp #C0
    jr nc,cr_inst
    sub #7F                     ; the duration
    ld (ix+C_DUR),a
    jr cr_next
cr_inst
    push hl
    sub #C0
    add a,a
    ld l,a
    ld h,0
    ld de,instruments
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,(de)                   ; its noise period, then its steps
    inc de
    ld (ix+C_NOISE),a
    ld (ix+C_IBASE),e
    ld (ix+C_IBASE+1),d
    pop hl
    jr cr_next
cr_end
    ld l,(ix+C_ORD)             ; the next pattern
    ld h,(ix+C_ORD+1)
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,d
    or e
    jr nz,cr_pattern
    ld a,(hl)                   ; the end of the list: round again
    inc hl
    ld h,(hl)
    ld l,a
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
cr_pattern
    ld (ix+C_ORD),l
    ld (ix+C_ORD+1),h
    ex de,hl
    jr cr_next
cr_rest
    ld de,silence
    ld (ix+C_INST),e
    ld (ix+C_INST+1),d
    jr cr_wait
cr_note
    push hl
    add a,a                     ; its tone period
    ld l,a
    ld h,0
    ld de,note_tab
    add hl,de
    ld a,(hl)
    ld (ix+C_PER),a
    inc hl
    ld a,(hl)
    ld (ix+C_PER+1),a
    ld a,(ix+C_IBASE)           ; its instrument from the start
    ld (ix+C_INST),a
    ld a,(ix+C_IBASE+1)
    ld (ix+C_INST+1),a
    pop hl
cr_wait
    ld a,(ix+C_DUR)
    ld (ix+C_WAIT),a
    ld (ix+C_PTR),l
    ld (ix+C_PTR+1),h
    ret

;; sfx_tick - start the sound effect asked for, if it wins, and play the
;; one there is on channel C (its tone and volume, and the mixer in D).
;; Destroys AF, BC, E, HL.
sfx_tick
    ld a,(sfx_req)
    or a
    jr z,sx_play
    ld hl,sfx_cur
    cp (hl)
    jr c,sx_done                ; the one playing wins
    ld (hl),a
    dec a                       ; its record
    ld l,a
    ld h,0
    ld c,l
    ld b,h
    add hl,hl
    add hl,hl
    add hl,bc
    add hl,hl                   ; * SFX_SIZE
    ld bc,sfx_tab
    add hl,bc
    ld (sfx_ptr),hl
    ld bc,S_PER
    add hl,bc
    ld c,(hl)
    inc hl
    ld b,(hl)
    ld (sfx_per),bc
    inc hl
    inc hl
    inc hl
    ld a,(hl)                   ; S_VOL
    ld (sfx_vol),a
    inc hl
    ld a,(hl)                   ; S_DECAY
    ld (sfx_dc),a
    inc hl
    ld a,(hl)                   ; S_LEN
    ld (sfx_t),a
    inc hl
    ld a,(hl)                   ; S_REP
    ld (sfx_rc),a
sx_done
    xor a
    ld (sfx_req),a
sx_play
    ld a,(sfx_cur)
    or a
    ret z
    ld hl,(sfx_per)
    ld a,l
    ld (psg_buf+R_TONE+8),a
    ld a,h
    ld (psg_buf+R_TONE+10),a
    ld a,(sfx_vol)
    ld (psg_buf+R_VOL+4),a
    ld a,d                      ; channel C: tone and noise as it says
    or #24
    ld d,a
    ld hl,(sfx_ptr)
    ld a,(hl)                   ; S_FLAGS
    rra
    jr nc,sx_notone
    res 2,d
sx_notone
    rra
    jr nc,sx_nonoise
    res 5,d
    inc hl
    ld a,(hl)                   ; S_NOISE
    ld (psg_buf+R_NOISE),a
    dec hl
sx_nonoise
    push de
    inc hl                      ; S_DPER: the sweep
    inc hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld bc,(sfx_per)
    ex de,hl
    add hl,bc
    ld (sfx_per),hl
    ex de,hl
    inc hl
    inc hl                      ; S_DECAY
    ld a,(sfx_dc)
    or a
    jr z,sx_vol
    dec a
    jr nz,sx_dc
    ld a,(sfx_vol)
    or a
    jr z,sx_quiet
    dec a
    ld (sfx_vol),a
sx_quiet
    ld a,(hl)
sx_dc
    ld (sfx_dc),a
sx_vol
    inc hl
    inc hl                      ; S_REP
    ld a,(sfx_rc)
    or a
    jr z,sx_len
    dec a
    jr nz,sx_rc
    ld bc,-S_REP+S_PER
    add hl,bc
    ld c,(hl)
    inc hl
    ld b,(hl)
    ld (sfx_per),bc
    ld bc,S_REP-S_PER-1
    add hl,bc
    ld a,(hl)
sx_rc
    ld (sfx_rc),a
sx_len
    pop de
    ld hl,sfx_t
    dec (hl)
    ret nz
    xor a                       ; over
    ld (sfx_cur),a
    ret

pat_end         defb #FF        ; music_play: the first row's next pattern
silence         defb 0,#80      ; an instrument's steps: quiet

    include "gen/music.asm"
