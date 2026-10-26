;; ===========================================================================
;; jit.asm - the runtime compiler: span frames into compiled draws.
;;
;; Every frame on the screen is drawn by compiled code, so both fighters fit
;; one window whatever they do. Compiled code for every frame in both
;; facings would be ~150 KB per character, so each fighter has a cache of
;; compiled frames instead (main RAM slots, and bank 1 slots for the frames
;; whose spans are in bank 1), filled on demand:
;;
;;   load_frame  takes the frame the logic chose from the cache (jit_get).
;;               If it isn't there, the fighter keeps the frame it shows
;;               and the frame is wanted (F_HELD).
;;   jit_work    after prepare, in whatever time is left before the next
;;               picture's tick: compiles wanted frames first, then the frame
;;               each fighter will most likely show next. A compile stops at
;;               a chunk boundary when less than one interrupt period
;;               (3.3 ms) is left, and goes on in the next picture, so it
;;               never makes a picture late.
;;
;; The code is what tools/sprite_codegen.py runtime_size describes (one
;; store per drawn byte, a yield every CHUNK lines), so it runs as a draw
;; job in the banded scheduler with DE = the frame's left edge.
;; ===========================================================================

SL_REC          EQU 0           ; cache slot: frame record (0 = empty, or
SL_FACE         EQU 2           ; being compiled), facing, last use,
SL_STAMP        EQU 3
SL_ADDR         EQU 4           ; where its code goes, the RAM configuration
SL_RAM          EQU 6           ; it runs in (#C0, or its bank's), and its
SL_SN           EQU 7           ; (s, n) table
SL_SIZE         EQU 9

;; ---------------------------------------------------------------------------
;; jit_get - IX = fighter, HL = frame record (in its character's directory),
;; A = facing. Out: NC and HL = the cache slot with the frame's compiled
;; draw, or CY if it isn't cached (at boot, jit_force: it is compiled there
;; and then). Destroys everything but IX.
;; ---------------------------------------------------------------------------
jit_get
    ld (jg_rec),hl
    ld (jg_face),a
    ld hl,jit_clock
    inc (hl)
    call jit_find
    jr nz,jg_miss
jg_stamp                        ; HL = slot
    push hl
    inc hl
    inc hl
    inc hl
    ld a,(jit_clock)
    ld (hl),a                   ; SL_STAMP
    pop hl
    or a
    ret
jg_miss
    ld a,(jit_force)
    or a
    scf
    ret z                       ; the caller keeps its frame
    call jw_start               ; at boot: compile it to the end
    jr jg_stamp

;; ---------------------------------------------------------------------------
;; jit_work - compile in the time left before the next picture's tick: the
;; job in hand, then frames fighters are waiting for, then each fighter's
;; likely next frame (they take turns to go first). Destroys everything.
;; ---------------------------------------------------------------------------
jit_work
    ld a,(jw_busy)
    or a
    jr z,jw_pick
    call irqs_left              ; a chunk needs a whole period
    or a
    ret z
    call jw_resume
    ret nz                      ; out of time again
jw_pick
    call irqs_left
    or a
    ret z
    ld ix,fighter_a
    call jw_wanted
    jr z,jw_go
    ld ix,fighter_b
    call jw_wanted
    jr z,jw_go
    ld a,(pf_turn)
    xor 1
    ld (pf_turn),a
    ld ix,fighter_a
    jr z,jw_turn
    ld ix,fighter_b
jw_turn
    call jw_next
    jr z,jw_go
    ld a,(pf_turn)              ; the other one
    or a
    ld ix,fighter_b
    jr z,jw_other
    ld ix,fighter_a
jw_other
    call jw_next
    ret nz                      ; nothing to do
jw_go
    call jw_start
    ret nz
    jr jw_pick

;; jw_wanted - IX = fighter: Z (and jg_rec, jg_face set) if it is holding a
;; frame because the one it wants isn't cached. Destroys AF, BC, DE, HL.
jw_wanted
    ld a,(ix+F_HELD)
    or a
    jr z,jw_no
    ld l,(ix+F_WANT)
    ld h,(ix+F_WANT+1)
    ld (jg_rec),hl
    ld a,(ix+F_WFACE)
    ld (jg_face),a
    jr jw_cached

;; jw_next - IX = fighter: Z (and jg_rec, jg_face set) if the frame it will
;; most likely show next isn't cached: the next frame of its move; idle and
;; walk go round, crouch holds its last frame, everything else ends in idle.
;; Destroys AF, BC, DE, HL.
jw_next
    ld a,(ix+F_MOVE)
    ld c,(ix+F_FRAME)
    inc c
    ld b,a
    ld a,c
    cp (ix+F_NFR)
    ld a,b
    jr c,jn_rec
    ld c,0
    cp MV_CROUCH
    jr z,jw_no
    cp MV_WALK+1
    jr c,jn_rec
    xor a
jn_rec
    call rec_addr
    ld (jg_rec),hl
    ld a,(ix+F_FACE)
    ld (jg_face),a
jw_cached
    call jit_find
    jr z,jw_no
    xor a                       ; Z: compile it
    ret
jw_no
    or 1
    ret

;; jw_start - IX = fighter, (jg_rec), (jg_face) = a frame to compile. Takes
;; a slot (jit_victim) and runs the job: Z and HL = the slot when it is
;; done, NZ if it ran out of time (jit_work goes on with it next picture).
;; Destroys everything but IX.
jw_start
    ld hl,(jg_rec)
    ld (jw_rec),hl
    ld a,(jg_face)
    ld (jw_face),a
    ld a,(ix+F_RAM0)            ; the record: frame bank, width, spans
    ld bc,#7F00
    out (c),a
    ld a,(hl)
    add a,(ix+F_RAM0)
    ld (jw_bank),a
    inc hl                      ; (width, offset)
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = span stream
    push de
    call jit_victim             ; a slot the frame's bank can reach
    ld (jw_slot),hl
    xor a
    ld (hl),a                   ; empty until the code is all there
    inc hl
    ld (hl),a
    ld de,SL_ADDR-1
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (jw_hl),de               ; where the code goes
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = its (s, n) table
    pop hl                      ; HL = span stream
    ld a,(jw_bank)
    ld bc,#7F00
    out (c),a
    ld a,(hl)                   ; top
    ld (de),a
    inc hl
    inc de
    ld a,(hl)                   ; lines (whole chunks)
    ld (jw_lines),a
    inc hl
    ld a,(hl)                   ; lines drawn
    ld (de),a
    inc hl
    inc de
    ld (jw_sn),de
    ld (jw_de),hl
    ld a,1
    ld (jw_busy),a

;; jw_resume - run the job in hand on: Z and HL = its slot when it is done,
;; NZ if it ran out of time. Destroys everything but IX.
jw_resume
    ld a,(jw_bank)
    ld bc,#7F00
    out (c),a
    ld a,(bench_phase)
    ld (jc_phase),a
    ld a,PH_COMPILE
    ld (bench_phase),a
    push ix
    ld hl,(jw_hl)
    ld de,(jw_de)
    ld iy,(jw_sn)
    ld a,(jw_lines)
    ld ixh,a
    ld a,(jw_face)
    or a
    jr nz,jr_left
    call jc_right
    jr jr_back
jr_left
    call jc_left
jr_back
    pop ix
    push af
    ld a,(jc_phase)
    ld (bench_phase),a
    ld bc,#7FC0
    out (c),c
    pop af
    ret nz
    ld hl,(jw_slot)             ; done: now it can be found
    push hl
    ld de,(jw_rec)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld a,(jw_face)
    ld (hl),a
    ld hl,(jit_done)            ; (for the bench)
    inc hl
    ld (jit_done),hl
    xor a
    ld (jw_busy),a
    pop hl
    ret                         ; Z

;; jit_find - IX = fighter, (jg_rec), (jg_face) = the frame. Out: Z and
;; HL = its slot if it is cached. Destroys AF, BC, DE, HL.
jit_find
    ld l,(ix+F_STAB)
    ld h,(ix+F_STAB+1)
    ld b,(ix+F_NSLOTS)
jf_slot
    ld de,(jg_rec)
    ld a,(hl)
    cp e
    jr nz,jf_next
    inc hl
    ld a,(hl)
    dec hl
    cp d
    jr nz,jf_next
    inc hl
    inc hl
    ld a,(jg_face)
    cp (hl)
    dec hl
    dec hl
    ret z
jf_next
    ld de,SL_SIZE
    add hl,de
    djnz jf_slot
    or 1                        ; NZ: not cached
    ret

;; jit_victim - IX = fighter, (jw_bank) = the frame's bank: the slot to
;; compile into. Of the slots that bank can reach (main RAM, or the same
;; bank), an empty one, or else the one unused longest, but never the one
;; holding the frame the fighter is set to show (F_CDRAW): the next window
;; may draw it. Out: HL = slot. Destroys AF, BC, DE.
jit_victim
    ld l,(ix+F_STAB)
    ld h,(ix+F_STAB+1)
    ld b,(ix+F_NSLOTS)
    ld c,0                      ; oldest age so far
jv_slot
    push hl
    ld de,SL_RAM
    add hl,de
    ld a,(hl)
    cp #C0
    jr z,jv_reach
    ld a,(jw_bank)
    cp (hl)
    jr nz,jv_skip               ; another bank
jv_reach
    dec hl
    ld a,(hl)                   ; SL_ADDR: on show?
    cp (ix+F_CDRAW+1)
    jr nz,jv_free
    dec hl
    ld a,(hl)
    cp (ix+F_CDRAW)
    jr z,jv_skip
jv_free
    pop hl
    push hl
    inc hl
    ld a,(hl)                   ; SL_REC high byte: 0 = empty
    or a
    jr z,jv_empty
    inc hl
    inc hl
    ld a,(jit_clock)
    sub (hl)                    ; age (stamps wrap; only ages matter)
    cp c
    jr c,jv_skip
    ld c,a
    pop hl
    ld (jv_best),hl
    push hl
jv_skip
    pop hl
    ld de,SL_SIZE
    add hl,de
    djnz jv_slot
    ld hl,(jv_best)
    ret
jv_empty
    pop hl
    ret

;; jit_init - IX = fighter, HL = its slot table, (sn_next) = where the next
;; (s, n) table goes, A = the first of its main RAM slots, C = how many:
;; fill in the table, main slots then the bank 1 slots its directory lists.
;; Destroys everything but IX.
jit_init
    ld (ix+F_STAB),l
    ld (ix+F_STAB+1),h
    ld (ix+F_NSLOTS),c
    ld e,a                      ; DE = CACHE_AT + A * CACHE_SLOT
    ld d,0
    push hl
    ld hl,CACHE_AT
    ld bc,CACHE_SLOT
    inc e
ji_main
    dec e
    jr z,ji_main_at
    add hl,bc
    jr ji_main
ji_main_at
    ex de,hl                    ; DE = first main slot
    pop hl
    ld b,(ix+F_NSLOTS)
    ld c,#C0
    call ji_slots
    push hl
    ld a,(ix+F_RAM0)            ; the directory: bank 1 slots
    ld bc,#7F00
    out (c),a
    ld a,(DIR_SLOTS)
    ld de,(DIR_SLOTS+1)
    ld bc,#7FC0
    out (c),c
    pop hl
    ld b,a
    add a,(ix+F_NSLOTS)
    ld (ix+F_NSLOTS),a
    ld a,b
    or a
    ret z
    ld a,(ix+F_RAM0)
    inc a
    ld c,a
    ; fall into ji_slots

;; ji_slots - HL = table entry, B slots from DE, C = their RAM
;; configuration. Out: HL = the next entry. Destroys AF, B, DE.
ji_slots
    xor a
    ld (hl),a                   ; empty
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a                   ; facing, stamp
    inc hl
    ld (hl),a
    inc hl
    ld (hl),e                   ; code
    inc hl
    ld (hl),d
    inc hl
    ld (hl),c
    inc hl
    push bc
    ld bc,(sn_next)             ; (s, n) table
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    push hl
    ld hl,SN_SIZE
    add hl,bc
    ld a,(sn_left)              ; six per tail
    dec a
    jr nz,ji_same_tail
    ld a,(sn_tail)
    inc a
    ld (sn_tail),a
    ld hl,SN_TAIL1
    dec a
    jr z,ji_tail
    ld hl,SN_TAIL2
ji_tail
    ld a,6
ji_same_tail
    ld (sn_left),a
    ld (sn_next),hl
    pop hl
    ex de,hl
    ld bc,CACHE_SLOT
    add hl,bc
    ex de,hl
    pop bc
    djnz ji_slots
    ret

;; irqs_left - A = whole interrupt periods (52 lines, 3.3 ms) certain to be
;; left before the tick that starts the next picture (last_render + 2).
;; Destroys AF, BC.
irqs_left
    di                          ; read both counts in one go
    ld a,(irq_count)
    ld b,a
    ld a,(tick_count)
    ei
    push hl
    ld hl,last_render
    sub (hl)                    ; ticks since this picture started
    pop hl
    cp 2
    jr nc,il_none
    ld c,a
    ld a,TICK_IRQ               ; periods to the next tick
    sub b
    jr z,il_whole
    jr nc,il_part
il_whole
    add a,IRQS_PER_FRAME
il_part
    dec c
    jr z,il_one                 ; that tick starts the next picture
    add a,IRQS_PER_FRAME        ; it doesn't: one frame more
il_one
    dec a                       ; the period we are in is partly gone
    ret
il_none
    xor a
    ret

;; rec_addr - IX = fighter, A = move, C = frame: HL = its frame record in
;; the directory. Destroys AF, BC, DE.
rec_addr
    ld b,a
    ld a,(ix+F_RAM0)
    push bc
    ld bc,#7F00
    out (c),a
    pop bc
    ld a,b
    ld l,a                      ; move table entry: frames, record list
    add a,a
    add a,l
    ld l,a
    ld h,0
    ld de,DIR_MOVES+1
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the move's first record
    ld a,c                      ; + REC_SIZE * frame
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld b,h
    ld c,l
    add hl,hl
    add hl,bc                   ; * 12
    add hl,de
    ld bc,#7FC0
    out (c),c
    ret

;; JC_BODY - the compiler for one facing. HL = code, DE = spans, IXH = lines
;; left, IY = the (s, n) table it writes. The draw job's SP walks the
;; fighter's restore list for the new frame (setup_fighter): per line the
;; screen address of the line's leftmost byte, then its byte count. So a
;; line starts pop hl : pop af facing right, then one store per byte with an
;; inc hl between. Facing left it starts pop hl : pop bc : add hl,bc (one
;; past the rightmost byte) and each byte is dec hl, then the store, of the
;; byte mirrored (flip_tab). Bytes come escaped (sprite_codegen.py escaped):
;; an opaque byte as itself, anything else as 0 then the byte.
    MACRO JC_BODY left,entry
{entry}
@first
    ld a,(irq_count)            ; every line: in the last period before
    cp TICK_IRQ-1               ; the tick? (a quick look first)
    jr nz,@go
    call jc_time
    jp c,@stop
@go
    ld (hl),#E1                 ; pop hl
    inc hl
    IF {left}
    ld (hl),#C1                 ; pop bc : add hl,bc
    inc hl
    ld (hl),#09
    ELSE
    ld (hl),#F1                 ; pop af
    ENDIF
    inc hl
    ld a,(de)                   ; s, n: into the (s, n) table
    inc de
    ld (iy+0),a
    ld a,(de)
    inc de
    ld (iy+1),a
    inc iy
    inc iy
    or a                        ; nothing on this line
    jp z,@eol
    IF {left}
    ld ixl,a                    ; IXL counts, B = flip_tab's page
    ld b,flip_tab>>8
@byte
    ld (hl),#2B                 ; dec hl
    inc hl
    ld a,(de)
    inc de
    or a
    jr z,@esc
    ld c,a
    ld a,(bc)                   ; mirrored
    ld (hl),#36                 ; ld (hl),byte
    inc hl
    ld (hl),a
    inc hl
@next
    dec ixl
    jp nz,@byte
    jp @eol
@esc
    ld a,(de)
    inc de
    or a
    jr z,@next                  ; a hole: leave the ground
    ld c,a
    ld a,(bc)                   ; mirrored
    ld c,a
    inc b                       ; mask_tab is the next page
    ld a,(bc)
    dec b
    ELSE
    ld b,a                      ; B counts, C = inc hl
    ld c,#23
@byte
    ld a,(de)
    inc de
    or a
    jr z,@esc
    ld (hl),#36                 ; ld (hl),byte
    inc hl
    ld (hl),a
    inc hl
@next
    ld (hl),c                   ; inc hl
    inc hl
    djnz @byte
    dec hl                      ; no step after the last byte
    jp @eol
@esc
    ld a,(de)
    inc de
    or a
    jr z,@next                  ; a hole: leave the ground
    push bc
    ld c,a
    ld b,mask_tab>>8
    ld a,(bc)
    ENDIF
    ld (hl),#7E                 ; ld a,(hl) : and mask : or byte : ld (hl),a
    inc hl
    ld (hl),#E6
    inc hl
    ld (hl),a
    inc hl
    ld (hl),#F6
    inc hl
    ld (hl),c
    inc hl
    ld (hl),#77
    inc hl
    IF {left} == 0
    pop bc
    ENDIF
    jr @next
@eol
    dec ixh
    jr z,@end
    ld a,ixh                    ; every CHUNK lines: yield
    and CHUNK-1
    jp nz,@first
    ld (hl),#DD                 ; dec ixl
    inc hl
    ld (hl),#2D
    inc hl
    ld (hl),#20                 ; jr nz,$+7
    inc hl
    ld (hl),5
    inc hl
    ld (hl),#21                 ; ld hl,resume
    inc hl
    ld c,l                      ; resume: past lo, hi, jp (iy)
    ld b,h
    inc bc
    inc bc
    inc bc
    inc bc
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    ld (hl),#FD                 ; jp (iy)
    inc hl
    ld (hl),#E9
    inc hl
    jp @first
@stop
    ld (jw_hl),hl               ; no time: put the job down
    ld (jw_de),de
    ld (jw_sn),iy
    ld a,ixh
    ld (jw_lines),a
    or 1                        ; NZ
    ret
@end
    ld (hl),#21                 ; ld hl,0 : jp (iy)
    inc hl
    ld (hl),0
    inc hl
    ld (hl),0
    inc hl
    ld (hl),#FD
    inc hl
    ld (hl),#E9
    xor a                       ; Z: done
    ret
    MEND

;; jc_time - CY if a compile must stop: no whole interrupt period is left
;; before the next picture's tick (never while jit_force). Destroys AF, BC.
jc_time
    ld a,(jit_force)
    or a
    ret nz                      ; NC
    call irqs_left
    cp 1                        ; CY if 0
    ret

;; ---------------------------------------------------------------------------
;; jc_right / jc_left - compile from the start of a line: HL = code,
;; DE = the line in the span stream (its bank paged in), IXH = lines left,
;; IY = the (s, n) table. Out: Z when the frame is done, NZ when it stopped for
;; lack of time (jw_hl, jw_de, jw_lines saved). Destroys everything.
;; ---------------------------------------------------------------------------
    JC_BODY 0,jc_right
    JC_BODY 1,jc_left
