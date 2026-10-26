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
;;        C = x, B = 0 facing right or 1 facing left
;;   out: HL = the list's first scanline (y + top), A = its line count
;; Ordinary code, run by prepare between pictures. An empty line gets a
;; one-byte copy into RESTORE_DUMMY, an unused byte of screen RAM, so the
;; restore loop never has to test for a zero count. Destroys everything
;; except the result.
;; ---------------------------------------------------------------------------
build_restore
    ld (br_list),de
    ld (br_x),bc                ; br_x = x, br_dir = facing
    add a,(hl)                  ; first scanline
    inc hl
    ld (br_first),a
    ld b,(hl)                   ; lines
    inc hl
    ld a,b
    ld (br_lines),a
    or a
    jr z,br_end
    push hl                     ; (s, n) pointer
    ld a,(br_first)
    ld l,a
    ld h,0
    add hl,hl
    ld de,line_tab
    add hl,de
    ex de,hl                    ; DE = line_tab entry
    pop hl
br_line
    push bc                     ; B = lines left
    ld c,(hl)                   ; s
    inc hl
    ld b,(hl)                   ; n
    inc hl
    push hl
    ld a,b
    or a
    jr nz,br_span
    ld hl,RESTORE_DUMMY         ; empty line: a harmless one-byte copy
    ld b,1
    jr br_store
br_span
    ld a,(br_dir)
    or a
    ld a,(br_x)
    jr z,br_right
    add a,SPR_W                 ; facing left: x + W - n - s
    sub b
    sub c
    jr br_col
br_right
    add a,c                     ; facing right: x + s
br_col
    ld l,a                      ; HL = scanline + column
    ld a,(de)
    add a,l
    ld l,a
    inc de
    ld a,(de)
    adc a,0
    dec de
    ld h,a
br_store                        ; HL = screen, B = bytes
    ex de,hl                    ; DE = screen, HL = line_tab entry
    push hl
    ld hl,(br_list)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld (hl),b
    inc hl
    ld (hl),0
    inc hl
    ld (br_list),hl
    pop de
    inc de                      ; next line_tab entry
    inc de
    pop hl                      ; (s, n) pointer
    pop bc
    djnz br_line
br_end
    ld a,(br_first)
    ld l,a
    ld h,0
    ld a,(br_lines)
    ret

;; ---------------------------------------------------------------------------
;; draw_l - draw a span stream mirrored (facing left).
;;   in:  DE = line record, SP = line_tab entry, IY = yield
;;        (dl_count) = scanlines to do now (>= 1)
;;        (dl_xr+1) = x + SPR_W - 1  (the screen byte of the sprite's byte 0)
;; Each byte goes through flip_tab (swap the two pixels) and then mask_tab,
;; and the line is walked right to left. The unrolled chain is entered n
;; blocks from its end through dl_entries.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
DL_BLOCK        EQU 12          ; bytes of code per drawn byte

draw_l
dl_line
    pop hl
dl_xr
    ld bc,0                     ; patched: x + SPR_W - 1
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
    ld hl,dl_count
    dec (hl)
    jp nz,dl_line
    ld hl,draw_l
    jp (iy)

    ASSERT dl_chain_end-dl_chain==SPR_W*2*DL_BLOCK
