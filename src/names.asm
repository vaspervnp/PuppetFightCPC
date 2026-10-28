;; ===========================================================================
;; names.asm - a help for the fighters' names on the HUD (round.asm
;; draw_names), in a gap of the background mirror (GAP4_ORG): COLD2 is
;; full.
;; ===========================================================================

;; dn_len - A = the pen, HL = a line: B = the length of its first word.
dn_len
    ld (vt_on),a
    push hl
    ld b,0
dl_char
    ld a,(hl)
    inc hl
    cp ' '
    jr z,dl_end
    inc b
    jr dl_char
dl_end
    pop hl
    ret
