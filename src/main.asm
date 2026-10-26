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
    ld hl,cold_store            ; and the cold code to its screen tails
    ld de,COLD_ORG
    ld bc,cold_end-cold_start
    ldir
    ld hl,cold2_store
    ld de,COLD2_ORG
    ld bc,cold2_end-cold2_start
    ldir
    jp start
payload_store

    ORG PAYLOAD_ORG,$
payload_start

start
    ld hl,work_start            ; the workspace: zeros, then
    ld de,work_start+1
    ld bc,work_end-work_start-1
    ld (hl),0
    ldir
    ld a,1                      ; compile whatever the time until the
    ld (jit_force),a            ; first picture
    ld hl,SN_TAIL0
    ld (sn_next),hl
    ld a,6
    ld (sn_left),a
    ld ix,fighter_a
    ld (ix+F_RAM0),#C4
    ld (ix+F_X),TRUMP_X0
    ld (ix+F_RLIST+1),RESTORE_LIST_A>>8
    ld ix,fighter_b
    ld (ix+F_RAM0),#C6
    ld (ix+F_X),PUTIN_X0
    ld (ix+F_FACE),1
    ld (ix+F_RLIST+1),RESTORE_LIST_B>>8
    ld a,FIGHTER_Y
    ld (fighter_a+F_Y),a
    ld (fighter_b+F_Y),a
    ld a,RESTORE_LIST_A AND #FF  ; (both lists start at #xxE0)
    ld (fighter_a+F_RLIST),a
    ld (fighter_b+F_RLIST),a
    call set_black
    call build_line_tab
    call draw_stage
    call clock_reset            ; and the round clock on it
    call copy_mirror
    call clear_lists
    call make_tables
    ld ix,fighter_a             ; the compiled frame caches
    ld hl,SLOT_TAB_A
    xor a
    ld c,CACHE_SLOTS_A
    call jit_init
    ld ix,fighter_b
    ld hl,SLOT_TAB_B
    ld a,CACHE_SLOTS_A
    ld c,CACHE_SLOTS_B
    call jit_init
    call setup_crtc
    ld hl,palette_game
    call set_palette
    call irq_init
    ld a,HEALTH_MAX
    ld (fighter_a+F_HEALTH),a
    ld (fighter_b+F_HEALTH),a
    ld ix,fighter_a             ; both start standing
    ld a,MV_IDLE
    call start_move
    ld ix,fighter_b
    ld a,MV_IDLE
    call start_move
    call logic                  ; positions and frames for the first picture
    call prepare                ; (compiled whatever the time)
    xor a
    ld (jit_force),a

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
    call rebuild                ; both fighters, set up by prepare
    call ml_logic               ; then, while the beam goes round twice:
                                ; the logic,
    call ml_prepare             ; the next picture's jobs,
    call jit_work               ; and compiling, in the time that's left
    jr main_loop

ml_logic
    ld a,PH_LOGIC
    ld (bench_phase),a
    call logic
    xor a
    ld (bench_phase),a
    ret

ml_prepare
    ld a,PH_PREPARE
    ld (bench_phase),a
    call prepare
    xor a
    ld (bench_phase),a
    ret


;; make_tables - flip_tab (the two pixels of a Mode 0 byte swapped) and
;; mask_tab (#AA / #55 set where a pixel is pen 0), which the compiler
;; uses. Built here rather than carried: 512 bytes of payload is a cache
;; slot's worth with the rest. Destroys AF, C, HL.
make_tables
    ld hl,flip_tab
mt_byte
    ld a,l                      ; left pixel bits 7 5 3 1, right 6 4 2 0
    and #AA
    rrca
    ld c,a
    ld a,l
    and #55
    rlca
    or c
    ld (hl),a
    inc h                       ; mask_tab
    ld c,0
    ld a,l
    and #AA
    jr nz,mt_left
    ld c,#AA
mt_left
    ld a,l
    and #55
    ld a,c
    jr nz,mt_right
    or #55
mt_right
    ld (hl),a
    dec h
    inc l
    jr nz,mt_byte
    ret

;; clear_lists - zero the four restore lists: build_restore never writes
;; the high bytes of their counts. Destroys AF, BC, DE, HL.
clear_lists
    ld a,RESTORE_LIST_A>>8
    call cl_one
    ld a,(RESTORE_LIST_A>>8) XOR RESTORE_FLIP
    call cl_one
    ld a,RESTORE_LIST_B>>8
    call cl_one
    ld a,(RESTORE_LIST_B>>8) XOR RESTORE_FLIP
cl_one
    ld h,a
    ld l,RESTORE_LIST_A AND #FF ; both lists start at #xxE0
    ld d,h
    ld e,l
    inc e
    ld (hl),0
    ld bc,255
    ldir
    ret

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
F_TIMER         EQU 27          ; state machine (fighter.asm): pictures into
F_PCTL          EQU 28          ; the frame (or the jump), last picture's
F_JX            EQU 29          ; controls, step across in a jump, this
F_CTL           EQU 30          ; picture's controls, frames in the move
F_NFR           EQU 31
F_RLIST         EQU 32          ; restore list for what is on the screen,
F_RFIRST        EQU 34          ; built by prebuild: buffer, first scanline,
F_RLINES        EQU 35          ; lines
F_DFACE         EQU 36          ; the facing its frame is drawn in
F_WANT          EQU 37          ; the frame it would show if it were
F_WFACE         EQU 39          ; compiled (record, facing), and whether it
F_HELD          EQU 40          ; is waiting for it
F_STAB          EQU 41          ; its cache (jit.asm): slot table, slots
F_NSLOTS        EQU 43
F_PKEY          EQU 44          ; F_OX..F_OSN when its restore list was made
F_HEALTH        EQU F_PKEY+F_OSN+2-F_OX     ; combat (fighter.asm): health,
F_HITDONE       EQU F_HEALTH+1              ; this attack has landed,
F_WINS          EQU F_HITDONE+1             ; rounds won (round.asm),
F_STUN          EQU F_WINS+1                ; hitstun or blockstun left,
F_HIST          EQU F_STUN+1                ; motion history, newest first
F_SIZE          EQU F_HIST+HIST_LEN

MOVE_IDLE       EQU 0
DIR_SLOTS       EQU #4004       ; in a character's bank 0: bank 1 cache
DIR_MOVES       EQU #4007       ; slots (count, first), then the moves
REC_SIZE        EQU 16
    ASSERT REC_SIZE==16             ; rec_addr shifts

;; ---------------------------------------------------------------------------
;; logic - next picture's frames and positions.
;;
;; The game: read both players' controls, let each fighter think
;; (fighter.asm), keep them apart, and fetch the frames they now show.
;; With -DDEMO=1 the fighters follow a script instead (logic_demo), which
;; is what the bench scenarios measure.
;; ---------------------------------------------------------------------------
logic
    ld hl,render_count
    inc (hl)
    IF DEMO
    jp logic_demo
    ELSE
    call read_controls
    ld a,(rnd_state)            ; between rounds nobody moves
    or a
    jr z,lg_ctl
    xor a
    ld (p1_ctl),a
    ld (p2_ctl),a
lg_ctl
    ld a,(p1_ctl)
    ld (fighter_a+F_CTL),a
    ld a,(p2_ctl)
    ld (fighter_b+F_CTL),a
    ld ix,fighter_a
    ld iy,fighter_b
    call think
    ld ix,fighter_b
    ld iy,fighter_a
    call think
    call separate
    call combat
    call round_tick
    ld ix,fighter_a
    call load_frame
    ld ix,fighter_b
    jp load_frame
    ENDIF

;; logic_demo - idle advances every second picture; both fighters sway a
;; few bytes to and fro so the restore has somewhere to put the ground back;
;; with JUMP=1 they jump in turns, then together.
logic_demo
    ld hl,render_count
    ld a,(hl)
    rra
    and 3
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

;; load_frame - IX = fighter: show its F_MOVE / F_FRAME in its F_FACE
;; facing. The frame's compiled draw comes from the fighter's cache (jit.asm);
;; if it isn't there, the fighter keeps the frame it shows and waits for
;; jit_work to compile it (F_HELD). Otherwise the frame's record fills in
;; F_FBANK..F_CDRAW and F_DFACE, the facing it is drawn in. Destroys
;; everything but IX.
load_frame
    ld a,(ix+F_MOVE)
    ld c,(ix+F_FRAME)
    call rec_addr
    ld (ix+F_WANT),l
    ld (ix+F_WANT+1),h
    ld a,(ix+F_FACE)
    ld (ix+F_WFACE),a
    ld (ix+F_HELD),1
    push hl
    call jit_get
    pop de
    ret c                       ; held
    ld (ix+F_HELD),0
    push hl                     ; the slot: code, its RAM, (s, n) table
    pop iy
    ld a,(iy+SL_ADDR)
    ld (ix+F_CDRAW),a
    ld a,(iy+SL_ADDR+1)
    ld (ix+F_CDRAW+1),a
    ld a,(iy+SL_RAM)
    ld (ix+F_CBANK),a
    ld a,(iy+SL_SN)
    ld (ix+F_SN),a
    ld a,(iy+SL_SN+1)
    ld (ix+F_SN+1),a
    ld a,(ix+F_FACE)
    ld (ix+F_DFACE),a
    ld a,(ix+F_RAM0)
    ld bc,#7F00
    out (c),a
    ex de,hl
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
    ld bc,#7FC0
    out (c),c
    ret

    include "jit.asm"
    include "crtc.asm"
    include "irq.asm"
    include "video.asm"
    include "sprite.asm"
    include "rebuild.asm"
    include "input.asm"
    include "fighter.asm"

;; ---------------------------------------------------------------------------
;; Tables and sprite data
;; ---------------------------------------------------------------------------


line_tab        EQU LINE_TAB_AT

payload_end
jit_stage       EQU payload_end     ; a frame on its way to another bank
STAGE_SIZE      EQU 600             ; (sprite_codegen.py: largest stream 599)
    ASSERT jit_stage+STAGE_SIZE<=CACHE_AT   ; the compiled frame caches follow
;; ---------------------------------------------------------------------------
;; Workspace: in the unused tail of screen slice 3, past restore list A1.
;; Not in the file: start clears it and sets what isn't zero.
;; ---------------------------------------------------------------------------
    ORG WORK_AT
work_start
;; The two fighters: Trump in banks 4-5 facing right, Putin in banks 6-7
;; facing left (start fills in the first fields).
fighter_a       defs F_SIZE
fighter_b       defs F_SIZE
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
br_first        defb 0
br_left         defb 0
br_sp           defw 0
br_tsp          defw 0
br_lines        defb 0
fr_h            defb 0
fr_x            defb 0
fr_w            defb 0
fr_b            defb 0
key_rows        defs 10
p1_ctl          defb 0
p2_ctl          defb 0
sf_draw         defw 0
skip_a          defb 0          ; prepare: no window work for A / B
skip_b          defb 0
rnd_state       defb 0          ; round.asm: 0 fighting, 1 round over,
rnd_timer       defb 0          ; pictures to the next round, winner
rnd_winner      defw 0          ; (0: a draw), the clock (BCD seconds, and
rnd_secs        defb 0          ; pictures into the second)
rnd_tick        defb 0
bx_a            defs 8          ; combat: attacker's boxes, defender's
bx_b            defs 8
bx_w1           defb 0          ; boxes: frame width - 1, left edge
bx_left         defb 0
sf_x            defb 0
br_w            defb 0
jit_done        defw 0          ; frames compiled (the bench reads it)
jit_clock       defb 0          ; jit.asm: cache use counter,
jit_force       defb 0          ; compile whatever the time (at boot),
jg_rec          defw 0          ; the frame asked for,
jg_face         defb 0
jv_best         defw 0
jc_phase        defb 0
pf_turn         defb 0          ; which fighter prefetches first
jw_busy         defb 0          ; a compile in hand: its slot, frame,
jw_slot         defw 0          ; facing, frame bank, width - 1, and where
jw_rec          defw 0          ; it stopped (code, spans, lines left)
jw_face         defb 0
jw_bank         defb 0
jw_hl           defw 0
jw_de           defw 0
jw_lines        defb 0
jw_sn           defw 0
jw_size         defw 0
jw_guessing     defb 0          ; the job in hand is a guess (jw_guess)
jw_stage        defb 0          ; the slot's bank, if the frame is copied
sn_next         defw 0          ; jit_init: where the next (s, n) table
sn_left         defb 0          ; goes, room left in this tail, which tail
sn_tail         defb 0
job_ra          defs J_SIZE     ; restore A, restore B, draw A, draw B
job_rb          defs J_SIZE
job_da          defs J_SIZE
job_db          defs J_SIZE

work_end
    ASSERT work_end<=WORK_AT+WORK_ROOM
;; ---------------------------------------------------------------------------
;; Cold code: in the file after the payload, copied by boot to a screen tail.
;; ---------------------------------------------------------------------------
cold_store      EQU payload_store+payload_end-payload_start
    ORG COLD_ORG,cold_store
cold_start
    include "combat.asm"
cold_end
    ASSERT cold_end<=COLD_ORG+COLD_ROOM
cold2_store     EQU cold_store+cold_end-cold_start
    ORG COLD2_ORG,cold2_store
cold2_start
    include "round.asm"
cold2_end
    ASSERT cold2_end<=COLD2_ORG+COLD_ROOM

    RUN boot
    SAVE 'PFSPIKE.BIN',boot,cold2_store-boot+cold2_end-cold2_start,DSK,'../build/pfspike.dsk'

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
