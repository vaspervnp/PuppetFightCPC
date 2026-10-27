;; ===========================================================================
;; prepare.asm - set up the next picture's rebuild (rebuild.asm), at the
;; end of the logic so the rebuild can start on the tick itself. In the
;; payload; its can_skip in a gap of the background mirror (skip.asm).
;; ===========================================================================

;; prepare - both fighters' jobs, always in one window, since every frame is
;; drawn by compiled code; each left out if nothing touches it (can_skip).
;; Then when the rebuild starts (start_irq): on the tick, line 170, if its
;; first band is above GUARD_LINE, else on the interrupt after, line 222.
;; Destroys everything.
prepare
    call shot_vis               ; the projectiles' pass (special.asm)
    call rebuild_clear
    ld ix,fighter_a             ; decide both before either is set up
    ld iy,fighter_b
    call can_skip
    ld (skip_a),a
    ld ix,fighter_b
    ld iy,fighter_a
    call can_skip
    ld (skip_b),a
    ld a,(skip_a)
    or a
    call z,setup_a
    ld a,(skip_b)
    or a
    call z,setup_b
    ld a,(band_end)             ; the first band reaches GUARD_LINE: the
    cp GUARD_BAND               ; rebuild starts when the beam has passed
    ld a,TICK_IRQ               ; the floor (and the compiler has a period
    jr c,pr_start               ; more)
    inc a
pr_start
    ld (start_irq),a
    ret
