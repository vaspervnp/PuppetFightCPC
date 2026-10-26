;; ===========================================================================
;; irq.asm - the 50 Hz heartbeat, locked to VSYNC.
;;
;; The Gate Array interrupts every 52 scanlines, six times a frame. Exactly
;; one of the six lands inside the 8-line VSYNC pulse, and that one is the
;; frame tick: the handler recognises it by reading VSYNC on PPI port B
;; rather than counting, so every frame's work starts at the same raster
;; position. Counting stays as a fallback (OverscanCPC src/irq.asm).
;;
;; The rebuild tick is a different interrupt: the TICK_IRQ'th after VSYNC
;; (line 222, just below the fighters - see config.asm), counted in
;; tick_count. The rebuild runs across the next VSYNC, so it must never keep
;; interrupts off for more than ~2 ms at a time: an interrupt acknowledged 32
;; or more lines late gets bit 5 of the Gate Array's counter cleared and the
;; rest of the frame's interrupts move, and one that is still pending when
;; the next arrives is lost. Short gaps keep the count exact, so the
;; interrupt in VSYNC is still the 0th even when it is serviced too late to
;; see VSYNC on the PPI.
;; ===========================================================================

IRQS_PER_FRAME  EQU 6

;; irq_init - install the handler at #0038 and enable interrupts.
;; ROMs are off, so #0038 is plain RAM and must hold the jump before EI.
;; Destroys AF, BC, HL.
irq_init
    di
    im 1
    ld a,#C3                    ; JP nn
    ld (#0038),a
    ld hl,irq_handler
    ld (#0039),hl
    call wait_vsync
    xor a
    ld (irq_count),a
    ld (frame_count),a
    ei
    ret

irq_handler
    push af
    push bc
    push hl
    ld b,#F5                    ; PPI port B, bit 0 = VSYNC
    in a,(c)
    rra
    jr nc,irq_handler_mid
    xor a                       ; inside VSYNC: the top of the frame
    ld (irq_count),a
    ld hl,frame_count
    inc (hl)
    jr irq_handler_done
irq_handler_mid
    ld hl,irq_count
    inc (hl)
    ld a,(hl)
    cp TICK_IRQ
    jr nz,irq_not_tick
    ld hl,tick_count
    inc (hl)
    jr irq_handler_done
irq_not_tick
    cp IRQS_PER_FRAME
    jr c,irq_handler_done
    ld (hl),0                   ; VSYNC was over before we got here: count
    ld hl,frame_count
    inc (hl)
irq_handler_done
    pop hl
    pop bc
    pop af
    ei
    ret

;; wait_vsync - return at the leading edge of VSYNC. Destroys AF, BC.
wait_vsync
    ld b,#F5
wait_vsync_off
    in a,(c)
    rra
    jr c,wait_vsync_off
wait_vsync_on
    in a,(c)
    rra
    jr nc,wait_vsync_on
    ret

;; wait_tick - return on the next rebuild tick (line 222). Destroys AF, HL.
wait_tick
    ld hl,tick_count
    ld a,(hl)
wait_tick_loop
    cp (hl)
    jr z,wait_tick_loop
    ret
