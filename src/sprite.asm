;; ===========================================================================
;; sprite.asm - restore and draw for span-encoded fighters.
;;
;; All of these run inside the rebuild, with interrupts off and SP pointing
;; into line_tab: each scanline address is a POP. Nothing here may CALL;
;; every routine returns with JP (IY).
;;
;; Span stream (tools/sprite_codegen.py):
;;     defb top, lines             first drawn line, lines from there
;;     per line: defb s, n, d0..dn-1
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; restore_r / restore_l - copy the background mirror back over the spans of
;; a frame drawn facing right / left.
;;   in:  IX = span stream, SP = line_tab + 2*y, IY = return
;;        (rr_x+1) = x                      for restore_r
;;        (rl_xw+1) = x + SPR_W             for restore_l
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
restore_r
    ld a,(ix+0)
    add a,a
    ld l,a
    ld h,0
    add hl,sp
    ld sp,hl
    ld a,(ix+1)
    ld (rst_count),a
    inc ix
    inc ix
rr_line
    pop hl                      ; scanline
rr_x
    ld bc,0                     ; patched: x
    add hl,bc
    ld c,(ix+0)                 ; s
    add hl,bc                   ; B is 0
    ld c,(ix+1)                 ; n
    inc ix
    inc ix
    ld a,c
    or a
    jr z,rr_next
    add ix,bc                   ; past the data bytes
    ex de,hl                    ; DE = screen
    ld a,d
    and MIRROR_H_AND
    or MIRROR_H_OR
    ld h,a
    ld l,e                      ; HL = mirror
    ldir                        ; leaves BC = 0, which rr_x reloads anyway
rr_next
    ld hl,rst_count
    dec (hl)
    jr nz,rr_line
    jp (iy)

restore_l
    ld a,(ix+0)
    add a,a
    ld l,a
    ld h,0
    add hl,sp
    ld sp,hl
    ld a,(ix+1)
    ld (rst_count),a
    inc ix
    inc ix
rl_line
    pop hl
rl_xw
    ld bc,0                     ; patched: x + SPR_W
    add hl,bc
    ld a,(ix+0)                 ; mirrored span starts at x + W - s - n
    ld c,(ix+1)
    add a,c
    ld e,c                      ; keep n
    ld c,a
    ld b,0
    or a
    sbc hl,bc
    ld c,e                      ; BC = n
    inc ix
    inc ix
    ld a,c
    or a
    jr z,rl_next
    add ix,bc
    ex de,hl
    ld a,d
    and MIRROR_H_AND
    or MIRROR_H_OR
    ld h,a
    ld l,e
    ldir
rl_next
    ld hl,rst_count
    dec (hl)
    jr nz,rl_line
    jp (iy)

;; ---------------------------------------------------------------------------
;; draw_l - draw a span stream mirrored (facing left).
;;   in:  HL = span stream, SP = line_tab + 2*y, IY = return
;;        (dl_xr+1) = x + SPR_W - 1  (the screen byte of the sprite's byte 0)
;; Each byte goes through flip_tab (swap the two pixels) and then mask_tab,
;; and the line is walked right to left. The unrolled chain is entered n
;; blocks from its end through dl_entries.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
DL_BLOCK        EQU 12          ; bytes of code per drawn byte

draw_l
    ld a,(hl)                   ; top
    inc hl
    ld c,(hl)                   ; lines
    inc hl
    ex de,hl                    ; DE = stream
    add a,a
    ld l,a
    ld h,0
    add hl,sp
    ld sp,hl
    ld a,c
    ld (dl_count),a
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
    jp (iy)

    ASSERT dl_chain_end-dl_chain==SPR_W*2*DL_BLOCK
