;; ===========================================================================
;; Puppet Fight CPC - milestone 1 tech spike.
;;
;; Two fighters idling on an overscan stage at 25 fps: Trump facing right,
;; drawn by compiled routines, and Putin facing left, drawn by the generic
;; mirrored span drawer. Both are erased from a background mirror. The point
;; is to measure all three against the beam - see tools/spike_bench.py and
;; docs/SPIKE.md.
;;
;; Build: make (build/pfspike.sna, build/pfspike.dsk - RUN"PFSPIKE)
;; ===========================================================================

    include "config.asm"

BUILDSNA
BANKSET 0

;; ---------------------------------------------------------------------------
;; The file loads at #4000 (where AMSDOS can hand over) and moves the payload
;; down to #0200, leaving #4000-#7FFF free for the background mirror.
;; ---------------------------------------------------------------------------
    ORG LOAD_ORG
boot
    di
    ld sp,STACK_TOP
    ld bc,#7F8C                 ; mode 0, both ROMs off
    out (c),c
    ld hl,payload_store
    ld de,PAYLOAD_ORG
    ld bc,payload_end-payload_start
    ldir
    jp start
payload_store

    ORG PAYLOAD_ORG,$
payload_start

start
    call set_black
    call build_line_tab
    call draw_stage
    call copy_mirror
    call setup_crtc
    ld hl,palette_game
    call set_palette
    call irq_init
    call logic                  ; positions and frames for the first picture

main_loop
    call wait_render            ; first frame of the picture: Trump
    call ground_overlap
    jr nz,ml_together
    call rebuild_a
    call wait_tick              ; second frame: Putin gets a window of his own
    call rebuild_b
    jr ml_logic
ml_together
    call rebuild_both           ; overlapping: both in one window
ml_logic
    ld a,PH_LOGIC
    ld (bench_phase),a
    call logic
    xor a
    ld (bench_phase),a
    jr main_loop

;; wait_render - 25 pictures a second: return on a frame tick at least two
;; ticks after the last picture started. Destroys AF, HL.
wait_render
    call wait_tick
    ld a,(last_render)
    ld l,a
    ld a,(frame_count)
    sub l
    cp 2
    jr c,wait_render
    ld a,(frame_count)
    ld (last_render),a
    ret

;; ---------------------------------------------------------------------------
;; logic - next picture's frames and positions. Idle advances every second
;; picture; both fighters sway a few bytes to and fro so the restore has
;; somewhere to put the ground back.
;; ---------------------------------------------------------------------------
logic
    ld hl,render_count
    inc (hl)
    ld a,(hl)
    rra                         ; /2: 12.5 fps animation
    and 3
    add a,a
    add a,a                     ; 4 bytes per frame entry
    ld e,a
    ld d,0
    ld hl,trump_frames
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (fa_spans),de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (fa_draw),de
    ld a,(render_count)
    rra
    and 3
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,putin_frames
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (fb_spans),de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (fb_draw),de

    ld a,(render_count)
    rra
    and 31
    ld e,a
    ld d,0
    ld hl,sway
    add hl,de
    ld b,(hl)
    ld a,TRUMP_X0
    add a,b
    ld (fa_x),a
    ld a,PUTIN_X0
    sub b
    ld (fb_x),a
    ret

sway                            ; -6..6, a triangle over 32 steps
    defb 0,1,2,3,4,5,6,6,6,5,4,3,2,1,0,0
    defb 0,-1,-2,-3,-4,-5,-6,-6,-6,-5,-4,-3,-2,-1,0,0

;; ---------------------------------------------------------------------------
;; Rebuilding a fighter: take its old picture off (copy the mirror back over
;; its spans) and put the new one down.
;;
;; At 25 pictures a second each picture spans two frames, and the beam
;; reaches the fighters' top line 15.6 ms into each frame. A fighter rebuilt
;; within that window is never seen half drawn, so the two fighters take one
;; frame each: Trump in the first, Putin in the second. Only when their
;; ground overlaps must both come off before either goes back, in a single
;; window - restoring one over the other would bite into it.
;; The mirror makes restoring safe in any order: it never holds a fighter.
;;
;; Everything runs with interrupts off and SP walking line_tab, so the
;; steps chain through IY rather than calling each other.
;; ---------------------------------------------------------------------------
rebuild_a
    di
    ld (rebuild_sp),sp
    ld iy,rba_1
    jp step_restore_a
rba_1
    ld iy,rb_end
    jp step_draw_a

rebuild_b
    di
    ld (rebuild_sp),sp
    ld iy,rbb_1
    jp step_restore_b
rbb_1
    ld iy,rb_end
    jp step_draw_b

rebuild_both
    di
    ld (rebuild_sp),sp
    ld iy,rbt_1
    jp step_restore_a
rbt_1
    ld iy,rbt_2
    jp step_restore_b
rbt_2
    ld iy,rbt_3
    jp step_draw_a
rbt_3
    ld iy,rb_end
    jp step_draw_b

rb_end
    ld sp,(rebuild_sp)
    ei
    xor a
    ld (bench_phase),a
    ret

;; Each step continues at IY when it is done. Steps never push: by the second
;; one SP points into line_tab, and a push would overwrite a scanline address.
;; A draw step also records what is now on the screen, for the next restore.
step_restore_a
    ld a,(fa_drawn)
    or a
    jr z,step_skip
    ld a,PH_RESTORE_A
    ld (bench_phase),a
    ld a,(fa_old_x)
    ld (rr_x+1),a
    ld ix,(fa_old_spans)
    ld sp,line_tab+FIGHTER_Y*2
    jp restore_r
step_skip
    jp (iy)

step_restore_b
    ld a,(fb_drawn)
    or a
    jr z,step_skip
    ld a,PH_RESTORE_B
    ld (bench_phase),a
    ld a,(fb_old_x)
    add a,SPR_W
    ld (rl_xw+1),a
    ld ix,(fb_old_spans)
    ld sp,line_tab+FIGHTER_Y*2
    jp restore_l

step_draw_a
    ld a,PH_DRAW_A
    ld (bench_phase),a
    ld a,(fa_x)
    ld (fa_old_x),a
    ld e,a
    ld d,0
    ld hl,(fa_spans)
    ld (fa_old_spans),hl
    ld a,1
    ld (fa_drawn),a
    ld hl,(fa_draw)
    ld sp,line_tab+FIGHTER_Y*2
    jp (hl)

step_draw_b
    ld a,PH_DRAW_B
    ld (bench_phase),a
    ld hl,(fb_spans)
    ld (fb_old_spans),hl
    ld a,1
    ld (fb_drawn),a
    ld a,(fb_x)
    ld (fb_old_x),a
    ld sp,line_tab+FIGHTER_Y*2
    IF PUTIN_COMPILED
    ld e,a
    ld d,0
    ld hl,(fb_draw)
    jp (hl)
    ELSE
    add a,SPR_W-1
    ld (dl_xr+1),a
    jp draw_l
    ENDIF

;; ground_overlap - NZ if the bytes A covers (old or new) meet B's.
;; Destroys AF, BC.
ground_overlap
    ld a,(fa_x)                 ; C = A's right edge (exclusive)
    ld b,a
    ld a,(fa_old_x)
    cp b
    jr nc,go_a_max
    ld a,b
go_a_max
    add a,SPR_W
    ld c,a
    ld a,(fb_x)                 ; B = B's left edge
    ld b,a
    ld a,(fb_old_x)
    cp b
    jr c,go_b_min
    ld a,b
go_b_min
    cp c                        ; B starts at or past A's end: apart
    jr nc,go_apart
    or 1                        ; NZ: overlapping
    ret
go_apart
    xor a                       ; Z
    ret

    include "crtc.asm"
    include "irq.asm"
    include "video.asm"
    include "sprite.asm"

;; ---------------------------------------------------------------------------
;; Tables and sprite data
;; ---------------------------------------------------------------------------
    include "gen/tables.asm"    ; flip_tab, mask_tab (page aligned)

    ALIGN 256
dl_entries                      ; draw_l chain entry for n drawn bytes
    REPEAT SPR_W*2+1,n
    defw dl_chain_end-(n-1)*DL_BLOCK
    REND

trump_frames                    ; spans, compiled draw
    defw trump_idle_0_spans,trump_idle_0_draw
    defw trump_idle_1_spans,trump_idle_1_draw
    defw trump_idle_2_spans,trump_idle_2_draw
    defw trump_idle_3_spans,trump_idle_3_draw
putin_frames                    ; spans, compiled left-facing draw
    IF PUTIN_COMPILED               ; only two frames fit compiled
    defw putin_idle_0_spans,putin_idle_0_drawl
    defw putin_idle_2_spans,putin_idle_2_drawl
    defw putin_idle_0_spans,putin_idle_0_drawl
    defw putin_idle_2_spans,putin_idle_2_drawl
    ELSE
    defw putin_idle_0_spans,0
    defw putin_idle_1_spans,0
    defw putin_idle_2_spans,0
    defw putin_idle_3_spans,0
    ENDIF

    include "gen/trump_idle.asm"
    include "gen/putin_idle.asm"

;; ---------------------------------------------------------------------------
;; Workspace (carried in the file for the spike; costs ~600 bytes)
;; ---------------------------------------------------------------------------
bench_phase     defb 0          ; first, so the bench can find it easily
frame_count     defb 0
irq_count       defb 0
last_render     defb 0
render_count    defb 0
fa_drawn        defb 0
fb_drawn        defb 0
rebuild_sp      defw 0
rst_count       defb 0
dl_count        defb 0
fr_h            defb 0
fr_x            defb 0
fr_w            defb 0
fr_b            defb 0
fa_x            defb 0
fa_old_x        defb 0
fa_spans        defw 0
fa_old_spans    defw 0
fa_draw         defw 0
fb_x            defb 0
fb_old_x        defb 0
fb_spans        defw 0
fb_old_spans    defw 0
fb_draw         defw 0
line_tab        defs DISPLAY_LINES*2

payload_end
    ASSERT payload_end<=LOAD_ORG    ; must not reach the load image it came from

    RUN boot
    SAVE 'PFSPIKE.BIN',boot,payload_store-boot+payload_end-payload_start,DSK,'../build/pfspike.dsk'
