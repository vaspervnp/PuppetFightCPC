;; ===========================================================================
;; input.asm - two players' controls from the key matrix.
;;
;; The matrix hangs off the AY-3-8912's port A, reached through the 8255 PPI:
;; put PSG register 14 on PPI port A, select it, turn port A round to input,
;; then put each matrix line on port C and read it back. A pressed key reads
;; as 0. (OverscanCPC src/keys.asm, where this was worked out.)
;;
;; Both joysticks are matrix lines too: joystick 0 is line 9, joystick 1
;; shares line 6 with 6 5 R T G F.
;; ===========================================================================

CT_UP           EQU 0           ; bits in a player's control byte
CT_DOWN         EQU 1
CT_LEFT         EQU 2
CT_RIGHT        EQU 3
CT_PUNCH        EQU 4
CT_KICK         EQU 5

;; KEY - set control bit {bit} of C if the key at matrix line {line}, mask
;; {mask} is down (it reads 0).
    MACRO KEY line,mask,bit
    ld a,(key_rows+{line})
    and {mask}
    jr nz,@up
    set {bit},c
@up
    MEND

;; ---------------------------------------------------------------------------
;; read_controls - scan the matrix and set p1_ctl / p2_ctl (1 = held).
;; About 100 us, with interrupts off while port A is turned round: the
;; sound's interrupt writes to the PSG through it (sound.asm). Destroys
;; AF, BC, E, HL.
;; ---------------------------------------------------------------------------
read_controls
    di
    ld bc,#F40E                 ; PPI port A = PSG register 14, the matrix
    out (c),c
    ld bc,#F6C0                 ; port C: select that register
    out (c),c
    ld bc,#F600
    out (c),c
    ld bc,#F792                 ; port A round to input
    out (c),c
    ld hl,key_rows
    ld e,#40                    ; port C: read, matrix line 0
rc_line
    ld bc,#F600
    out (c),e
    ld b,#F4
    in a,(c)
    ld (hl),a
    inc hl
    inc e
    ld a,e
    cp #4A                      ; ten lines
    jr nz,rc_line
    ld bc,#F782                 ; port A back to output
    out (c),c
    ei

    ld c,0                      ; player 1: joystick 0, or the cursor
    KEY 9,#01,CT_UP             ; keys with Space (punch) and Copy (kick)
    KEY 9,#02,CT_DOWN
    KEY 9,#04,CT_LEFT
    KEY 9,#08,CT_RIGHT
    KEY 9,#10,CT_PUNCH          ; fire 1
    KEY 9,#20,CT_KICK           ; fire 2
    KEY 0,#01,CT_UP             ; cursor up
    KEY 0,#04,CT_DOWN           ; cursor down
    KEY 1,#01,CT_LEFT           ; cursor left
    KEY 0,#02,CT_RIGHT          ; cursor right
    KEY 5,#80,CT_PUNCH          ; Space
    KEY 1,#02,CT_KICK           ; Copy
    ld a,c
    ld (p1_ctl),a
    ld c,0                      ; player 2: joystick 1, or W A S D with
    KEY 6,#01,CT_UP             ; Z (punch) and X (kick)
    KEY 6,#02,CT_DOWN
    KEY 6,#04,CT_LEFT
    KEY 6,#08,CT_RIGHT
    KEY 6,#10,CT_PUNCH          ; fire 1
    KEY 6,#20,CT_KICK           ; fire 2
    KEY 7,#08,CT_UP             ; W
    KEY 7,#10,CT_DOWN           ; S
    KEY 8,#20,CT_LEFT           ; A
    KEY 7,#20,CT_RIGHT          ; D
    KEY 8,#80,CT_PUNCH          ; Z
    KEY 7,#80,CT_KICK           ; X
    ld a,c
    ld (p2_ctl),a
    ret
