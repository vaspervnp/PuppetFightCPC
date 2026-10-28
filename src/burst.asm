;; ===========================================================================
;; burst.asm - comic-book bursts: a hit that lands puts "POW!", "BAM!" and
;; the like over the head of whoever took it, for BURST_PICS pictures.
;;
;; A burst is drawn outside the rebuild like a projectile (main.asm
;; shot_pass), and only where no fighter is drawn: it has a projectile's
;; fields (burst_rec, F_PW..F_PVIS of a record that would start F_PW before
;; it: BURST), so shot_vis's sv_one serves it too. The dead ones hold its
;; word (F_PSPEED), whether it is new (F_PDMG) and what the pass has to do
;; (F_PSTUN). It is higher up than a projectile, so the beam must not be
;; on it: it is taken off (burstoff.asm, ~36 lines) in interrupt periods
;; TICK_IRQ to 0 (lines 170 to 13, done by line 49; period 1 as well let
;; a take-off late in it, slowed by the interrupts, reach the burst's top
;; after the beam did), which is
;; mostly in wait_render on the tick, before the rebuild it is due before
;; (and wait_render puts the rebuild back if it isn't done yet); it is
;; drawn in period CLEAR_IRQ (lines 222-273: over 200 lines before the
;; beam is back on it), never on the way to a picture's rebuild, so
;; drawing it can wait for a later picture.
;;
;; The pass is in low RAM, in the part of the stack it never reaches
;; (LOW2_ORG), so the compiler can run it with a character's bank in
;; (jit.asm jc_shot); it pages main RAM in for the drawing, which is in a
;; gap of the background mirror (burstdraw.asm, burstvis.asm, burstoff.asm), like
;; burst_hit (bursthit.asm) and the tables (burstdat.asm).
;; ===========================================================================

BURST           EQU burst_rec-F_PW
BURST_PICS      EQU 12          ; half a second
BURST_W         EQU 14          ; bytes
BURST_H         EQU 28          ; lines
BURST_TOP       EQU 112         ; no higher (the beam: see above)
BURST_TEXT      EQU 9           ; its word's first line
    ASSERT BURST_TOP>=BAND_TOP

;; burst_pass - from shot_pass: take the burst off, then draw it, if the
;; beam allows. Comes back with main RAM. Destroys AF, BC, DE, HL, IY.
burst_pass
    ld a,(BURST+F_PSTUN)
    or a
    ret z
    ld a,(irq_count)
    cp 1
    jr c,bp_go
    cp TICK_IRQ
    ret c
bp_go
    push ix
    ld ix,BURST
    ld a,(bench_phase)
    push af
    ld a,PH_SHOT
    ld (bench_phase),a
    ld bc,#7FC0                 ; main RAM, for the gaps
    out (c),c
    bit 0,(ix+F_PSTUN)
    call nz,burst_off
    res 0,(ix+F_PSTUN)
    ld a,(irq_count)            ; drawing: period CLEAR_IRQ,
    cp CLEAR_IRQ
    jr nz,bp_out
    ld a,(last_render)          ; not on the way to a rebuild
    ld b,a
    ld a,(tick_count)
    sub b
    cp 2
    jr nc,bp_out
    bit 1,(ix+F_PSTUN)
    jr z,bp_out
    ld (ix+F_PSTUN),0
    ld (ix+F_PDRAWN),1
    ld (ix+F_PDMG),0
    call burst_draw
bp_out
    pop af
    ld (bench_phase),a
    pop ix
    ret
