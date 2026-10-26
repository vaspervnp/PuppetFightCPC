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

;; wait_render - 25 pictures a second: return on a rebuild tick at least two
;; ticks after the last picture started. Destroys AF, HL.
wait_render
    call wait_tick
    ld a,(last_render)
    ld l,a
    ld a,(tick_count)
    sub l
    cp 2
    jr c,wait_render
    ld a,(tick_count)
    ld (last_render),a
    ret

;; ---------------------------------------------------------------------------
;; Fighters. Each is a record of F_* fields: where it is and what it shows,
;; the frame load_frame fetched from its character's directory, and what is
;; on the screen now (the F_O* fields, for the restore and the bench).
;; ---------------------------------------------------------------------------
F_RAM0          EQU 0           ; RAM configuration of the character's bank 0
F_X             EQU 1           ; box x, bytes
F_Y             EQU 2           ; top scanline
F_FACE          EQU 3           ; 0 right, 1 left
F_MOVE          EQU 4
F_FRAME         EQU 5
F_FBANK         EQU 6           ; the frame: RAM configuration of its data,
F_W             EQU 7           ; width (bytes), x offset (bytes, signed),
F_OFF           EQU 8
F_SPANS         EQU 9           ; span stream, (s, n) table,
F_SN            EQU 11
F_CBANK         EQU 13          ; compiled draw for this facing (0: none)
F_CDRAW         EQU 14
F_DRAWN         EQU 16          ; what is on the screen
F_OX            EQU 17          ; its left edge
F_OY            EQU 18
F_OW            EQU 19
F_OFACE         EQU 20
F_OBANK         EQU 21
F_OSPANS        EQU 23
F_OSN           EQU 25
F_SIZE          EQU 27

MOVE_IDLE       EQU 0
DIR_MOVES       EQU #4004       ; move table in a character's bank 0
REC_SIZE        EQU 12

;; ---------------------------------------------------------------------------
;; logic - next picture's frames and positions. Idle advances every second
;; picture; both fighters sway a few bytes to and fro so the restore has
;; somewhere to put the ground back.
;; ---------------------------------------------------------------------------
logic
    ld hl,render_count
    inc (hl)
    ld a,(hl)
    rra
    and 3
    IF PUTIN_COMPILED           ; overlaps need compiled draws: idle 0 and 2
    and 2
    ENDIF
    ld (fighter_a+F_FRAME),a
    ld (fighter_b+F_FRAME),a
    xor a
    ld (fighter_a+F_MOVE),a
    ld (fighter_b+F_MOVE),a

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
    ld (fighter_a+F_X),a
    ld a,PUTIN_X0
    sub b
    ld (fighter_b+F_X),a

    ;; Jumps (JUMP=1): a 48-picture cycle - Trump jumps, then Putin, then
    ;; both together. Otherwise both stand.
    ld a,FIGHTER_Y
    ld (fighter_a+F_Y),a
    ld (fighter_b+F_Y),a
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
    ld (fighter_a+F_Y),a
lg_b_jumps
    ld a,b
    ld (fighter_b+F_Y),a
    jr lg_frames
lg_a_jumps
    ld a,b
    ld (fighter_a+F_Y),a
lg_frames
    ENDIF
    ld ix,fighter_a
    call load_frame
    ld ix,fighter_b
    jp load_frame

jump_arc                        ; rise and fall over 16 pictures, top at
    defb 7,21,32,42,50,55,59,60,60,59,55,50,42,32,21,7  ; JUMP_MAX lines
    ASSERT JUMP_MAX>=60

sway                            ; -6..6, a triangle over 32 steps
    defb 0,1,2,3,4,5,6,6,6,5,4,3,2,1,0,0
    defb 0,-1,-2,-3,-4,-5,-6,-6,-6,-5,-4,-3,-2,-1,0,0

;; load_frame - IX = fighter: fetch its F_MOVE / F_FRAME record from its
;; character's directory into the F_FBANK..F_CDRAW fields (the compiled draw
;; for its facing). Pages the character's bank 0 in and back out.
;; Destroys AF, BC, DE, HL.
load_frame
    ld a,(ix+F_RAM0)
    ld bc,#7F00
    out (c),a
    ld a,(ix+F_MOVE)            ; move table entry: frames, record list
    ld l,a
    add a,a
    add a,l
    ld l,a
    ld h,0
    ld de,DIR_MOVES+1
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the move's first record
    ld a,(ix+F_FRAME)           ; + REC_SIZE * frame
    add a,a
    add a,a                     ; * 4
    ld l,a
    ld h,0
    add hl,hl                   ; * 8
    ld c,l
    ld b,h
    srl b
    rr c                        ; BC = * 4
    add hl,bc                   ; * 12
    add hl,de
    ld a,(hl)                   ; bank (0/1)
    add a,(ix+F_RAM0)
    ld (ix+F_FBANK),a
    inc hl
    ld a,(hl)
    ld (ix+F_W),a
    inc hl
    ld a,(hl)
    ld (ix+F_OFF),a
    inc hl
    ld a,(hl)
    ld (ix+F_SPANS),a
    inc hl
    ld a,(hl)
    ld (ix+F_SPANS+1),a
    inc hl
    ld a,(hl)
    ld (ix+F_SN),a
    inc hl
    ld a,(hl)
    ld (ix+F_SN+1),a
    inc hl
    ld a,(hl)                   ; compiled code's bank
    add a,(ix+F_RAM0)
    ld (ix+F_CBANK),a
    inc hl                      ; facing right, then left
    ld a,(ix+F_FACE)
    or a
    jr z,lf_draw
    inc hl
    inc hl
lf_draw
    ld a,(hl)
    ld (ix+F_CDRAW),a
    inc hl
    ld a,(hl)
    ld (ix+F_CDRAW+1),a
    ld bc,#7FC0
    out (c),c
    ret

;; ground_overlap - A = 1 if the bytes A covers (old and new) meet B's,
;; whichever side each is on, else A = 0. Destroys AF, BC, DE, HL.
ground_overlap
    ld ix,fighter_a
    call ground_span            ; D = left, E = right (exclusive)
    push de
    ld ix,fighter_b
    call ground_span
    pop bc                      ; B,C = A's span; D,E = B's
    ld a,d                      ; apart if B starts at or past A's end
    cp c
    jr nc,go_apart
    ld a,b                      ; or A starts at or past B's end
    cp e
    jr nc,go_apart
    ld a,1
    ret
go_apart
    xor a
    ret

;; ground_span - IX = fighter: D = the leftmost byte it covers (new frame
;; and the one on the screen), E = one past the rightmost. Destroys AF, HL.
ground_span
    ld a,(ix+F_X)
    add a,(ix+F_OFF)
    ld d,a
    add a,(ix+F_W)
    ld e,a
    ld a,(ix+F_DRAWN)
    or a
    ret z
    ld a,(ix+F_OX)
    cp d
    jr nc,gs_left
    ld d,a
gs_left
    add a,(ix+F_OW)
    cp e
    ret c
    ld e,a
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
    ALIGN 256
dr_entries                      ; draw_r chain entry for n drawn bytes
    REPEAT SPR_W*2+1,n
    defw dr_chain_end-(n-1)*DR_BLOCK
    REND

;; The two fighters: Trump in banks 4-5 facing right, Putin in banks 6-7
;; facing left. Everything else in a record is filled in at run time.
fighter_a
    defb #C4,TRUMP_X0,FIGHTER_Y,0
    defs F_SIZE-4
fighter_b
    defb #C6,PUTIN_X0,FIGHTER_Y,1
    defs F_SIZE-4

;; ---------------------------------------------------------------------------
;; Workspace (carried in the file for the spike; costs ~600 bytes)
;; ---------------------------------------------------------------------------
bench_phase     defb 0          ; first, so the bench can find it easily
frame_count     defb 0
irq_count       defb 0
tick_count      defb 0
last_render     defb 0
render_count    defb 0
rebuild_sp      defw 0
band_end        defb 0
rr_count        defb 0
br_list         defw 0
br_x            defb 0          ; build_restore: x, then facing
br_dir          defb 0
br_first        defb 0
br_lines        defb 0
fr_h            defb 0
fr_x            defb 0
fr_w            defb 0
fr_b            defb 0
together        defb 0
sf_draw         defw 0
sf_list         defw 0
sf_x            defb 0
br_w            defb 0
gen_count       defb 0
gen_sp          defw 0
job_ra          defs J_SIZE     ; restore A, restore B, draw A, draw B
job_rb          defs J_SIZE
job_da          defs J_SIZE
job_db          defs J_SIZE
line_tab        EQU LINE_TAB_AT

payload_end
    ASSERT payload_end<=LOAD_ORG    ; must not reach the load image it came from

    RUN boot
    SAVE 'PFSPIKE.BIN',boot,payload_store-boot+payload_end-payload_start,DSK,'../build/pfspike.dsk'

;; ---------------------------------------------------------------------------
;; The characters, in the extra 64K. On the disc each bank is its own file,
;; and PFSPIKE.BAS pages the bank in before loading it at #4000.
;; ---------------------------------------------------------------------------
BANK 4
    include "gen/trump_bank0.asm"
    SAVE 'TRUMP0.BIN',#4000,$-#4000,DSK,'../build/pfspike.dsk'
BANK 5
    include "gen/trump_bank1.asm"
    SAVE 'TRUMP1.BIN',#4000,$-#4000,DSK,'../build/pfspike.dsk'
BANK 6
    include "gen/putin_bank0.asm"
    SAVE 'PUTIN0.BIN',#4000,$-#4000,DSK,'../build/pfspike.dsk'
BANK 7
    include "gen/putin_bank1.asm"
    SAVE 'PUTIN1.BIN',#4000,$-#4000,DSK,'../build/pfspike.dsk'
