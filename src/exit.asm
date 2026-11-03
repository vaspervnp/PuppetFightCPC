;; ===========================================================================
;; exit.asm - ESC in a fight (EXIT.BIN): "EXIT ? ESC=YES, FIRE1=NO" over
;; the names, then ESC again goes back to the select screen (back.asm) and
;; fire goes on with the fight. In fighter B's bank 0 at EXIT_AT, past every
;; character's frames (tools/sprite_codegen.py checks): the loader puts it
;; there, and the ladder's next opponents leave it be.
;;
;; read_controls (input.asm) comes here by train_go when ESC is down, the
;; bank paged in, which hides the mirror and its gaps: only the screen, the
;; payload and the workspace. The fight stands still meanwhile (the music
;; plays on). Fire: the names' lines black again and the clock back, then
;; read_controls draws the names. ESC: on in fighter A's bank 0, at the
;; same place (back.asm): the switch is at EX_SWITCH in both, and the code
;; goes on in the other bank after it.
;;
;; train_go comes with A = 0 from training's controls (ai.asm ap_b): on to
;; the dummy's own code (train.asm) at TRAIN_AT, which is only there then.
;; ===========================================================================
EX_LINE         EQU NAME_LINE-1 ; the question: 5 rows of 2 lines, over the
EX_LINES        EQU 10          ; names (and the clock's first line, which
EX_CHARS        EQU 24          ; is drawn again); 3 bytes a character
EX_MARGIN       EQU (BYTES_PER_LINE-3*EX_CHARS)/2

exit_start
    or a
    jp z,TRAIN_AT
    jr ex_ask
    ASSERT $==EX_SWITCH
    out (c),c                   ; on in fighter A's bank (back.asm)
    jr ex_release               ; and back from there (a snapshot)
ex_ask
    ld a,#FF                    ; the question
    call ex_draw
ex_release                      ; ESC up first
    call ex_scan
    jr z,ex_release
ex_wait
    call ex_scan
    ld bc,#7FC4                 ; ESC again: fighter A's bank (back.asm)
    jr z,EX_SWITCH
    call ex_fire
    jr nz,ex_wait
ex_no
    call ex_scan                ; fire up, or the fighter would punch
    call ex_fire
    jr z,ex_no
    xor a                       ; the names' lines black, the clock back
    call ex_draw
    call draw_clock
    jp page_main

;; ex_scan - the key matrix into key_rows, a frame on (the bounce goes by):
;; Z if ESC is down. ex_fire - Z if fire 1 of either joystick, or Space,
;; is down. Destroy AF, BC, E, HL.
ex_scan
    ld b,IRQS_PER_FRAME
es_frame
    halt
    djnz es_frame
    di                          ; (as read_controls)
    ld bc,#F40E
    out (c),c
    ld bc,#F6C0
    out (c),c
    ld bc,#F600
    out (c),c
    ld bc,#F792
    out (c),c
    ld hl,key_rows
    ld e,#40
es_line
    ld bc,#F600
    out (c),e
    ld b,#F4
    in a,(c)
    ld (hl),a
    inc hl
    inc e
    ld a,e
    cp #4A
    jr nz,es_line
    ld bc,#F782
    out (c),c
    ei
    ld a,(key_rows+8)
    and #04
    ret
ex_fire
    ld a,(key_rows+5)           ; Space
    and #80
    ret z
    ld a,(key_rows+9)           ; joystick 0 and 1
    ld hl,key_rows+6
    and (hl)
    and #10
    ret

;; ex_draw - A = #FF: the question on lines EX_LINE.., or 0: those lines
;; black. White on black, a font of 5 x 5 pixels, each row 2 lines.
;; Destroys AF, BC, DE, HL, IX.
ex_draw
    ld (ed_mask+1),a
    ld ix,LINE_TAB_AT+EX_LINE*2
    ld c,0                      ; the font's row, 0-4
ed_row
    ld b,2
ed_line
    push bc
    ld l,(ix+0)
    ld h,(ix+1)
    inc ix
    inc ix
    ld b,EX_MARGIN
    call ed_black
    ld de,ex_text
    ld b,EX_CHARS
ed_char
    push bc
    ld a,(de)
    inc de
ed_mask
    and 0                       ; (0: a space)
    ld b,a                      ; its row: ex_font + 5 x character + row
    add a,a
    add a,a
    add a,b
    add a,c
    push de
    ld e,a
    ld d,0
    push hl
    ld hl,ex_font
    add hl,de
    ld a,(hl)
    pop hl
    add a,a                     ; its 5 pixels to bits 7-3, and a blank
    add a,a
    add a,a
    ld b,3
ed_pair
    ld e,#C0                    ; pen 1, pen 1
    add a,a
    jr nc,ed_left
    ld e,#48                    ; pen 2 on the left
ed_left
    add a,a
    jr nc,ed_right
    ld d,a
    ld a,e
    xor #C0 XOR #84             ; pen 2 on the right
    ld e,a
    ld a,d
ed_right
    ld (hl),e
    inc hl
    djnz ed_pair
    pop de
    pop bc
    djnz ed_char
    ld b,EX_MARGIN
    call ed_black
    pop bc
    djnz ed_line
    inc c
    ld a,c
    cp EX_LINES/2
    jr nz,ed_row
    ret
ed_black
    ld (hl),#C0
    inc hl
    djnz ed_black
    ret

;; The question, as characters of ex_font.
EXC_SP          EQU 0
EXC_E           EQU 1
EXC_X           EQU 2
EXC_I           EQU 3
EXC_T           EQU 4
EXC_Q           EQU 5
EXC_S           EQU 6
EXC_C           EQU 7
EXC_EQ          EQU 8
EXC_Y           EQU 9
EXC_COMMA       EQU 10
EXC_F           EQU 11
EXC_R           EQU 12
EXC_1           EQU 13
EXC_N           EQU 14
EXC_O           EQU 15
ex_text
    defb EXC_E,EXC_X,EXC_I,EXC_T,EXC_SP,EXC_Q,EXC_SP                ; EXIT ?
    defb EXC_E,EXC_S,EXC_C,EXC_EQ,EXC_Y,EXC_E,EXC_S,EXC_COMMA,EXC_SP ; ESC=YES,
    defb EXC_F,EXC_I,EXC_R,EXC_E,EXC_1,EXC_EQ,EXC_N,EXC_O            ; FIRE1=NO
    ASSERT $-ex_text==EX_CHARS
ex_font                         ; 5 rows of 5 pixels (bit 4 left)
    defb %00000,%00000,%00000,%00000,%00000     ; space
    defb %11111,%10000,%11110,%10000,%11111     ; E
    defb %10001,%01010,%00100,%01010,%10001     ; X
    defb %01110,%00100,%00100,%00100,%01110     ; I
    defb %11111,%00100,%00100,%00100,%00100     ; T
    defb %01110,%10001,%00110,%00000,%00100     ; ?
    defb %01111,%10000,%01110,%00001,%11110     ; S
    defb %01111,%10000,%10000,%10000,%01111     ; C
    defb %00000,%11111,%00000,%11111,%00000     ; =
    defb %10001,%01010,%00100,%00100,%00100     ; Y
    defb %00000,%00000,%00000,%00100,%01000     ; ,
    defb %11111,%10000,%11110,%10000,%10000     ; F
    defb %11110,%10001,%11110,%10010,%10001     ; R
    defb %00100,%01100,%00100,%00100,%01110     ; 1
    defb %10001,%11001,%10101,%10011,%10001     ; N
    defb %01110,%10001,%10001,%10001,%01110     ; O
exit_end
    ASSERT exit_end<=#8000
