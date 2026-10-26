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


;; ---------------------------------------------------------------------------
;; draw_r / draw_l - the generic drawers: a span stream drawn facing right,
;; or mirrored (facing left). Jobs for the scheduler like a compiled draw:
;; they run whole chunks (span streams are padded to them) and yield.
;;   in:  DE = line record, SP = line_tab entry, IY = yield,
;;        IXL = chunks to draw now (>= 1),
;;        A = the frame's left edge                     for draw_r
;;        A = its left edge + width - 1 (byte 0's place) for draw_l
;; Every byte goes through mask_tab; draw_l also mirrors it through flip_tab
;; and walks the line right to left. The unrolled chains are entered n
;; blocks from their end through dr_entries / dl_entries. Every 8 lines they
;; let a pending interrupt in on the real stack (see irq.asm), so the slow
;; drawers never keep interrupts off for long.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
DR_BLOCK        EQU 8           ; bytes of code per drawn byte
DL_BLOCK        EQU 12

    MACRO GEN_START xpatch,count
    ld ({xpatch}+1),a
    ld a,ixl
    add a,a
    add a,a
    add a,a                     ; lines = chunks * 8
    ld ({count}),a
    MEND

    MACRO GEN_NEXT count,line,resume
    ld hl,{count}
    dec (hl)
    jr z,@done
    ld a,(hl)
    and 7
    jp nz,{line}
    ld (gen_sp),sp
    ld sp,(rebuild_sp)
    ei
    nop
    di
    ld sp,(gen_sp)
    jp {line}
@done
    ld hl,{resume}
    jp (iy)
    MEND

draw_r
    GEN_START dr_x,gen_count
dr_line
    pop hl
dr_x
    ld bc,0                     ; patched: x
    add hl,bc
    ld a,(de)                   ; s
    inc de
    add a,l
    ld l,a
    jr nc,dr_nc
    inc h
dr_nc
    ld a,(de)                   ; n
    inc de
    or a
    jp z,dr_next
    add a,a
    ld c,a
    ld b,dr_entries/256
    ld a,(bc)
    ld (dr_jp+1),a
    inc c
    ld a,(bc)
    ld (dr_jp+2),a
    ld b,mask_tab/256
dr_jp
    jp 0                        ; patched: into the chain
dr_chain
    REPEAT SPR_W*2
    ld a,(de)                   ; data byte
    inc de
    ld c,a
    ld a,(bc)                   ; its mask
    and (hl)
    or c
    ld (hl),a
    inc hl
    REND
dr_chain_end
dr_next
    GEN_NEXT gen_count,dr_line,draw_r

    ASSERT dr_chain_end-dr_chain==SPR_W*2*DR_BLOCK

draw_l
    GEN_START dl_xr,gen_count
dl_line
    pop hl
dl_xr
    ld bc,0                     ; patched: x + w - 1
    add hl,bc
    ld a,(de)                   ; s: step left by it
    inc de
    ld c,a
    ld a,l
    sub c
    ld l,a
    jr nc,dl_nb
    dec h
dl_nb
    ld a,(de)                   ; n
    inc de
    or a
    jp z,dl_next
    add a,a
    ld c,a
    ld b,dl_entries/256
    ld a,(bc)
    ld (dl_jp+1),a
    inc c
    ld a,(bc)
    ld (dl_jp+2),a
    ld b,flip_tab/256
dl_jp
    jp 0                        ; patched: into the chain
dl_chain
    REPEAT SPR_W*2
    ld a,(de)                   ; data byte
    inc de
    ld c,a
    ld a,(bc)                   ; mirrored
    ld c,a
    inc b                       ; mask_tab is the next page
    ld a,(bc)
    dec b
    and (hl)
    or c
    ld (hl),a
    dec hl
    REND
dl_chain_end
dl_next
    GEN_NEXT gen_count,dl_line,draw_l

    ASSERT dl_chain_end-dl_chain==SPR_W*2*DL_BLOCK
