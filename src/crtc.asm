;; ===========================================================================
;; crtc.asm - CRTC overscan registers and the Gate Array palette.
;; ===========================================================================

;; setup_crtc - program the 6845 for the 96x272 overscan window.
;; Destroys AF, BC, HL.
setup_crtc
    ld hl,crtc_data
setup_crtc_loop
    ld a,(hl)
    inc hl
    cp #FF
    ret z
    ld b,#BC
    out (c),a                   ; select register
    ld a,(hl)
    inc hl
    inc b                       ; #BD: write it
    out (c),a
    jr setup_crtc_loop

crtc_data
    defb 0,CRTC_R0, 1,CRTC_R1, 2,CRTC_R2, 3,CRTC_R3
    defb 4,CRTC_R4, 5,CRTC_R5, 6,CRTC_R6, 7,CRTC_R7
    defb 8,CRTC_R8, 9,CRTC_R9, 12,CRTC_R12, 13,CRTC_R13
    defb #FF

;; set_palette - HL = 17 Gate Array colour bytes: pens 0-15, then the border.
;; Destroys AF, BC, HL.
set_palette
    ld bc,#7F00
set_palette_loop
    out (c),c                   ; select pen C
    ld a,(hl)
    inc hl
    out (c),a
    inc c
    ld a,c
    cp 17
    jr c,set_palette_loop
    ret

;; set_black - every pen and the border black, while the screen is built.
;; Destroys AF, BC.
set_black
    ld bc,#7F10
set_black_loop
    out (c),c
    ld a,#54
    out (c),a
    dec c
    jp p,set_black_loop
    ret

;; The game palette (GAME_PLAN 3.3, tools/cpc_palette.py FIXED_COLOURS),
;; then the border. Pens 6-9 and 10-13 are the fighters' own colours, which
;; start copies from their characters' directories.
palette_game
    defb #54,#54,#4B,#44,#5C,#40
    defs 8                      ; fighter A's 4 inks, fighter B's
    defb #5F,#56
    defb #54
