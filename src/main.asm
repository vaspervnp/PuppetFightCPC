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
    call prepare

main_loop
    call wait_render            ; first frame of the picture
    IF SLACK                    ; margin test only: start SLACK*100 us late
    ld b,SLACK
ml_slack
    ld c,24
ml_slack_in
    dec c
    jr nz,ml_slack_in
    djnz ml_slack
    ENDIF
    call rebuild                ; jobs set up by prepare, last picture
    ld a,(together)
    or a
    jr nz,ml_logic
    call rebuild_clear          ; apart: Putin gets the next window
    call setup_b
    call wait_tick
    call rebuild
ml_logic
    ld a,PH_LOGIC
    ld (bench_phase),a
    call logic
    call prepare
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
    ld hl,trump_frames
    call frame_entry
    ld (fa_spans),de
    ld (fa_draw),bc
    ld (fa_sn),hl
    ld hl,putin_frames
    call frame_entry
    ld (fb_spans),de
    ld (fb_draw),bc
    ld (fb_sn),hl

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

    ;; Jumps (JUMP=1): a 48-picture cycle - Trump jumps, then Putin, then
    ;; both together. Otherwise both stand.
    ld a,FIGHTER_Y
    ld (fa_y),a
    ld (fb_y),a
    IF JUMP
    ld a,(render_count)
lg_mod48
    cp 48
    jr c,lg_mod_ok
    sub 48
    jr lg_mod48
lg_mod_ok
    ld c,a
    and 15
    ld e,a
    ld d,0
    ld hl,jump_arc
    add hl,de
    ld a,FIGHTER_Y
    sub (hl)
    ld b,a                      ; B = the airborne top line
    ld a,c
    cp 16
    jr c,lg_a_jumps
    cp 32
    jr c,lg_b_jumps
    ld a,b                      ; both
    ld (fa_y),a
lg_b_jumps
    ld a,b
    ld (fb_y),a
    ret
lg_a_jumps
    ld a,b
    ld (fa_y),a
    ENDIF
    ret

jump_arc                        ; rise and fall over 16 pictures, top at
    defb 7,21,32,42,50,55,59,60,60,59,55,50,42,32,21,7  ; JUMP_MAX lines
    ASSERT JUMP_MAX>=60

;; frame_entry - HL = a fighter's frame table; picks the idle frame for this
;; picture (12.5 fps animation). Out: DE = spans, BC = draw, HL = (s, n).
;; Destroys AF.
frame_entry
    ld a,(render_count)
    rra
    and 3
    ld c,a
    add a,a
    add a,c
    add a,a                     ; 6 bytes per entry
    ld c,a
    ld b,0
    add hl,bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ret

sway                            ; -6..6, a triangle over 32 steps
    defb 0,1,2,3,4,5,6,6,6,5,4,3,2,1,0,0
    defb 0,-1,-2,-3,-4,-5,-6,-6,-6,-5,-4,-3,-2,-1,0,0

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
    include "rebuild.asm"

;; ---------------------------------------------------------------------------
;; Tables and sprite data
;; ---------------------------------------------------------------------------
    include "gen/tables.asm"    ; flip_tab, mask_tab (page aligned)

    ALIGN 256
dl_entries                      ; draw_l chain entry for n drawn bytes
    REPEAT SPR_W*2+1,n
    defw dl_chain_end-(n-1)*DL_BLOCK
    REND

trump_frames                    ; spans, compiled draw, (s, n) table
    IF PUTIN_COMPILED               ; overlaps: two compiled frames, for room
    defw trump_idle_0_spans,trump_idle_0_draw,trump_idle_0_sn
    defw trump_idle_2_spans,trump_idle_2_draw,trump_idle_2_sn
    defw trump_idle_0_spans,trump_idle_0_draw,trump_idle_0_sn
    defw trump_idle_2_spans,trump_idle_2_draw,trump_idle_2_sn
    ELSE
    defw trump_idle_0_spans,trump_idle_0_draw,trump_idle_0_sn
    defw trump_idle_1_spans,trump_idle_1_draw,trump_idle_1_sn
    defw trump_idle_2_spans,trump_idle_2_draw,trump_idle_2_sn
    defw trump_idle_3_spans,trump_idle_3_draw,trump_idle_3_sn
    ENDIF
putin_frames                    ; spans, compiled left-facing draw, (s, n)
    IF PUTIN_COMPILED               ; only two frames fit compiled
    defw putin_idle_0_spans,putin_idle_0_drawl,putin_idle_0_sn
    defw putin_idle_2_spans,putin_idle_2_drawl,putin_idle_2_sn
    defw putin_idle_0_spans,putin_idle_0_drawl,putin_idle_0_sn
    defw putin_idle_2_spans,putin_idle_2_drawl,putin_idle_2_sn
    ELSE
    defw putin_idle_0_spans,0,putin_idle_0_sn
    defw putin_idle_1_spans,0,putin_idle_1_sn
    defw putin_idle_2_spans,0,putin_idle_2_sn
    defw putin_idle_3_spans,0,putin_idle_3_sn
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
band_end        defb 0
rr_count        defb 0
br_list         defw 0
br_x            defb 0          ; build_restore: x, then facing
br_dir          defb 0
br_first        defb 0
br_lines        defb 0
dl_count        defb 0
fr_h            defb 0
fr_x            defb 0
fr_w            defb 0
fr_b            defb 0
fa_x            defb 0
fa_y            defb 0
fa_old_x        defb 0
fa_old_y        defb 0
fa_spans        defw 0
fa_old_spans    defw 0
fa_draw         defw 0
fa_sn           defw 0
fa_old_sn       defw 0
fb_x            defb 0
fb_y            defb 0
fb_old_x        defb 0
fb_old_y        defb 0
fb_spans        defw 0
fb_old_spans    defw 0
fb_draw         defw 0
fb_sn           defw 0
fb_old_sn       defw 0
together        defb 0
job_ra          defs J_SIZE     ; restore A, restore B, draw A, draw B
job_rb          defs J_SIZE
job_da          defs J_SIZE
job_db          defs J_SIZE
line_tab        EQU LINE_TAB_AT

payload_end
    ASSERT payload_end<=LOAD_ORG    ; must not reach the load image it came from

    RUN boot
    SAVE 'PFSPIKE.BIN',boot,payload_store-boot+payload_end-payload_start,DSK,'../build/pfspike.dsk'
