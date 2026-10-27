;; ===========================================================================
;; fdcseek.asm - the µPD765 (fdc.asm): interrupts sensed, the head moved,
;; the motor. Cold code in a gap of the background mirror.
;; ===========================================================================

;; fdc_sense - sense interrupt status: A = ST0 (#80: nothing to say).
;; fdc_drain - sense it until there is nothing, 8 times at most (the most
;; a real 765 has to say: emulators may never say nothing). Keep HL.
;; Destroy AF, BC, DE.
fdc_sense
    ld a,#08
    call fdc_send
    call fdc_result
    ld a,(fdc_res)
    ret
fdc_drain
    ld d,8
fd_more
    call fdc_sense
    cp #80
    ret z
    dec d
    jr nz,fd_more
    ret

;; fdc_seekend - wait for a seek or recalibrate to end. Destroys AF, BC, DE.
fdc_seekend
    ld de,0
sk_wait
    call fdc_sense
    bit 5,a                     ; seek end
    ret nz
    dec de
    ld a,d
    or e
    jr nz,sk_wait
    jp disc_fail

;; disc_on - the motor on, a second to come up to speed, the controller
;; cleared of whatever a failed try left, set up, and the head on track 0.
;; disc_off - the motor off. Destroy AF, BC, DE, HL.
disc_on
    ld bc,FDC_MOTOR
    ld a,1
    out (c),a
    ld hl,DISC_SPIN
do_spin
    djnz do_spin                ; (256 times: 0.8 ms)
    dec hl
    ld a,h
    or l
    jr nz,do_spin
    ld e,16
do_flush
    ld bc,FDC_MSR
    in a,(c)
    and #D0                     ; ready, its way, busy
    cp #90                      ; it wants a command's next byte
    jr nz,do_result
    xor a                       ; (a sector ID 0 matches nothing)
    call fdc_send
    jr do_more
do_result
    cp #D0                      ; it has a result byte left
    jr nz,do_ready
    inc c
    in a,(c)
do_more
    dec e
    jr nz,do_flush
do_ready
    call fdc_drain
    ld hl,fdc_specify
    call fdc_cmd
    call fdc_drain
    ld hl,fdc_recal
    call fdc_cmd
    jr fdc_seekend
disc_off
    ld bc,FDC_MOTOR
    xor a
    out (c),a
    ret

fdc_specify     defb 3,#03,#8F,#1F  ; step, head unload and load times; no DMA
fdc_recal       defb 2,#07,0
