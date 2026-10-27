;; ===========================================================================
;; fdc.asm - the disc without the firmware: the µPD765 driven by polling,
;; for the next opponent mid-game (ladder.asm). After TerraCPC's driver,
;; which learned on real 6128s, WinAPE and RVM what it does:
;;  * Sense interrupt status until it says "nothing" before every command:
;;    emulators keep an interrupt after each read and swallow the next
;;    command until it is sensed.
;;  * A seek is over when sense interrupt status says so (ST0's seek end),
;;    not when the drive's busy bit clears: on a real 765 that only clears
;;    once it is sensed.
;;  * Result bytes are read while the controller is busy, not a fixed
;;    seven: some emulators give fewer.
;;  * One sector a command. With no terminal count wired on the CPC, every
;;    good read ends with "end of cylinder", which is no error.
;;  * Every wait has a time out.
;; Any fault (a time out, a sector with an error) starts the whole load
;; again (disc_fail), the border red, so nothing returns an error.
;;
;; The disc (tools/make_dsk.py): drive A, side 0, 9 sectors of 512 bytes a
;; track, IDs #C1-#C9. A byte comes every 32 us and nothing may come in
;; between: the load runs with interrupts off and the inks black.
;; Cold code in gaps of the background mirror (it reads into main RAM):
;; this file, fdcseek.asm and discread.asm; its variables are in low RAM
;; (stream.asm).
;; ===========================================================================

FDC_MOTOR       EQU #FA7E
FDC_MSR         EQU #FB7E       ; and its data register at #FB7F
DISC_SPIN       EQU 1200        ; ~1 s for the motor to come up to speed

;; fdc_send - A = a byte for the controller, when it asks for one. Keeps DE,
;; HL. Destroys AF, BC.
fdc_send
    push de
    push af
    ld de,0
    ld bc,FDC_MSR
fs_wait
    in a,(c)
    add a,a                     ; CY: ready, S: its way (1: to us)
    jr nc,fs_not
    jp p,fs_out
fs_not
    dec de
    ld a,d
    or e
    jr nz,fs_wait
    jp disc_fail
fs_out
    pop af
    pop de
    inc c
    out (c),a
    ret

;; fdc_cmd - HL = a command: its length, then its bytes. Keeps DE.
;; Destroys AF, BC, HL.
fdc_cmd
    push de
    ld e,(hl)
fc_byte
    inc hl
    ld a,(hl)
    call fdc_send
    dec e
    jr nz,fc_byte
    pop de
    ret

;; fdc_result - the result phase into fdc_res (the first 7 bytes), as long
;; as the controller is busy. Keeps DE, HL. Destroys AF, BC.
fdc_result
    push hl
    push de
    xor a
    ld (fdc_res+1),a
    ld (fdc_res+2),a
    ld hl,fdc_res
fx_next
    ld de,0
fx_wait
    ld bc,FDC_MSR
    in a,(c)
    bit 4,a                     ; busy?
    jr z,fx_done
    and #C0
    cp #C0                      ; a byte for us
    jr z,fx_byte
    dec de
    ld a,d
    or e
    jr nz,fx_wait
    jp disc_fail
fx_byte
    inc c
    in a,(c)
    ld (hl),a
    ld a,l
    cp (fdc_res+6) AND #FF
    jr z,fx_next
    inc hl
    jr fx_next
fx_done
    pop de
    pop hl
    ret
