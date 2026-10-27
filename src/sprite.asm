;; ===========================================================================
;; sprite.asm - restore and draw for span-encoded fighters.
;;
;; All of these run inside the rebuild, with interrupts off and SP pointing
;; into line_tab: each scanline address is a POP. Nothing here may CALL.
;;
;; They are jobs for the banded scheduler in rebuild.asm, so each one runs a
;; given number of scanlines and then yields: JP (IY) with HL = the address
;; to resume at and DE = the job's stream pointer. The scheduler keeps SP,
;; HL and DE per job and hands them back on the next band.
;;
;; Span stream (tools/sprite_codegen.py):
;;     defb top, lines             first drawn line, lines from there
;;     per line: defb s, n, d0..dn-1
;; A job's DE starts at the first line record (stream + 2) and its SP at
;; line_tab + 2*(y + top).
;; ---------------------------------------------------------------------------

;; ---------------------------------------------------------------------------
;; restore - copy the background mirror back over the spans of the frame a
;; fighter has on the screen, from a restore list made by build_restore.
;;   in:  SP = the job's place in its restore list, IY = yield,
;;        (rr_count) = scanlines to do now (>= 1)
;; A list entry is one scanline: defw screen address, byte count. Everything
;; that costs time per line - the line table, x, the span start, mirroring -
;; was paid in build_restore, outside the window, so a line here is about
;; 17 us plus 6 per byte. Destroys AF, BC, DE, HL, IXH.
;; ---------------------------------------------------------------------------
restore
    ld a,(rr_count)
    ld ixh,a
rs_line
    pop de                      ; screen
    pop bc                      ; bytes (never 0: see build_restore)
    ld a,d
    and MIRROR_H_AND
    or MIRROR_H_OR
    ld h,a
    ld l,e                      ; HL = mirror
    ldir
    dec ixh
    jr nz,rs_line
    ld hl,restore
    jp (iy)

;; ---------------------------------------------------------------------------
;; rect_restore - copy the mirror back over a rectangle: a projectile.
;;   in:  SP = line_tab + 2*(its top line), E = x, D = width (bytes),
;;        (rr_count) = lines, IY = yield
;; About 24 us a line plus 6 per byte. Destroys AF, BC, DE, HL, IXH.
;; ---------------------------------------------------------------------------
rect_restore
    ld a,e
    ld (rr_x+1),a
    ld a,d
    ld (rr_w+1),a
    ld a,(rr_count)
    ld ixh,a
rr_line
    pop hl                      ; scanline
rr_x
    ld de,0                     ; + x (patched)
    add hl,de
    ld d,h                      ; DE = screen
    ld e,l
    ld a,h
    and MIRROR_H_AND
    or MIRROR_H_OR
    ld h,a                      ; HL = mirror
rr_w
    ld bc,0                     ; width (patched)
    ldir
    dec ixh
    jr nz,rr_line
    jp (iy)

;; ---------------------------------------------------------------------------
;; build_restore - make the restore list for a frame on the screen.
;;   in:  HL = the frame's (s, n) table, DE = list buffer, A = y,
;;        C = x (the frame's left edge), B = 0 facing right or 1 facing
;;        left, (br_w) = the frame's width in bytes
;;   out: HL = the list's first scanline (y + top), A = its line count
;; Ordinary code, run by prepare between pictures. An empty line gets a
;; one-byte copy into RESTORE_DUMMY, an unused byte of screen RAM, so the
;; restore loop never has to test for a zero count. Destroys everything
;; except the result.
;; ---------------------------------------------------------------------------
;; BR_LOOP - build_restore's loop for one facing. SP walks line_tab with
;; interrupts off, 16 lines at a time; IXL counts them, HL = (s, n),
;; DE = list. The column comes from x (patched into the code), s and n.
    MACRO BR_LOOP left
@chunk
    ld a,(br_left)              ; up to 16 lines with interrupts off
    ld b,16
    sub b
    jr nc,@part
    add a,b
    ld b,a
    xor a
@part
    ld (br_left),a
    ld ixl,b
    di
    ld sp,(br_tsp)
@line
    pop bc                      ; BC = scanline
    IF {left}
br_x_l
    ld a,0                      ; facing left: x + w (patched) - s - n
    sub (hl)
    inc hl
    sub (hl)
    ELSE
    ld a,(hl)                   ; facing right: x (patched) + s
    inc hl
br_x_r
    add a,0
    ENDIF
    add a,c                     ; screen = scanline + column
    ld (de),a
    inc de
    ld a,b
    adc a,0
    ld (de),a
    inc de
    ld a,(hl)                   ; n
    or a
    jr z,@empty
    ldi                         ; count (its high byte is always 0)
    inc de
    dec ixl
    jr nz,@line
@chunk_end
    ld (br_tsp),sp
    ld sp,(br_sp)
    ei
    ld a,(br_left)
    or a
    jr nz,@chunk
    jr @done
@empty
    dec de                      ; an empty line: a one-byte copy into
    dec de                      ; RESTORE_DUMMY
    ld a,RESTORE_DUMMY AND #FF
    ld (de),a
    inc de
    ld a,RESTORE_DUMMY>>8
    ld (de),a
    inc de
    ld a,1
    ld (de),a
    inc de
    inc de
    inc hl
    dec ixl
    jr nz,@line
    jr @chunk_end
@done
    MEND

build_restore
    push ix
    ld (br_list),de
    add a,(hl)                  ; first scanline
    inc hl
    ld (br_first),a
    ld e,a
    ld d,0
    push hl
    ld hl,line_tab
    add hl,de
    add hl,de
    ld (br_tsp),hl              ; where SP starts in line_tab
    pop hl
    ld a,(hl)                   ; lines
    inc hl
    ld (br_lines),a
    ld (br_left),a
    or a
    jp z,br_end
    ld (br_sp),sp
    ld de,(br_list)             ; DE = list, HL = (s, n)
    ld a,b
    or a
    jp nz,br_facing_l
    ld a,c
    ld (br_x_r+1),a
    BR_LOOP 0
    jr br_end
br_facing_l
    ld a,(br_w)
    add a,c
    ld (br_x_l+1),a
    BR_LOOP 1
br_end
    pop ix
    ld a,(br_first)
    ld l,a
    ld h,0
    ld a,(br_lines)
    ret
