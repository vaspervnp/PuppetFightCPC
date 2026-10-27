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
    ld c,16                     ; every ink black, border too, while the
bt_black                        ; stage goes into the screen
    out (c),c
    ld a,#54
    out (c),a
    dec c
    jp p,bt_black
    ld hl,STAGE_AT+ST_DATA      ; first, before anything lands on it
    ld de,#8000
    call unpack
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
    ld hl,gap1_store            ; and the logic to the mirror's gaps
    ld de,GAP1_ORG
    ld bc,gap1_end-gap1_start
    ldir
    ld hl,gap2_store
    ld de,GAP2_ORG
    ld bc,gap2_end-gap2_start
    ldir
    ld hl,gap3_store
    ld de,GAP3_ORG
    ld bc,gap3_end-gap3_start
    ldir
    ld hl,gap4_store
    ld de,GAP4_ORG
    ld bc,gap4_end-gap4_start
    ldir
    ld hl,STAGE_AT+ST_INKS      ; and the stage's inks: pen 0, pens 14-15
    ld de,palette_game
    ldi
    ld de,palette_game+14
    ldi
    ldi
    jp start

;; unpack - HL = a packed stage (tools/stage_pack.py), DE = where it goes:
;; n < #7F: n + 1 bytes as they are; n >= #80: n - #7D bytes from an
;; offset word back; #7F: the end. Destroys AF, BC, DE, HL.
unpack
    ld a,(hl)
    inc hl
    cp #7F
    ret z
    jr nc,up_match
    ld c,a
    ld b,0
    inc bc
    ldir
    jr unpack
up_match
    sub #7D
    ld c,a
    ld b,0
    ld a,(hl)                   ; the offset
    inc hl
    push hl
    ld h,(hl)
    ld l,a
    push de
    ex de,hl
    or a
    sbc hl,de                   ; where it comes from
    pop de
    ldir
    pop hl
    inc hl
    jr unpack
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
    call draw_hud               ; on the stage boot unpacked
    call clock_reset            ; and the round clock on it
    call copy_mirror
    call clear_lists
    call make_tables
    call cache_split            ; the compiled frame caches
    push bc
    ld ix,fighter_a
    ld hl,SLOT_TAB_A
    xor a
    ld c,b
    call jit_init
    pop bc
    ld ix,fighter_b
    ld hl,SLOT_TAB_B
    ld a,b
    ld c,MAIN_SLOTS
    sub c
    neg
    ld c,a
    ld a,b
    call jit_init
    ld ix,fighter_a             ; each fighter's own colours
    ld de,palette_game+6
    call own_inks
    ld ix,fighter_b
    ld de,palette_game+10
    call own_inks
    ld ix,fighter_a             ; and specials
    call load_special
    ld ix,fighter_b
    call load_special
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


;; cache_split - B = fighter A's main RAM cache slots (B gets the rest of
;; MAIN_SLOTS): about as many slots in all for both, at least one each, and
;; at most MAX_SLOTS. Destroys AF, BC, DE, IX.
cache_split
    ld ix,fighter_a
    call char_slots
    ld d,a                      ; D = A's slots in bank 1, E = B's
    ld ix,fighter_b
    call char_slots
    ld e,a
    ld a,MAIN_SLOTS             ; (MAIN_SLOTS + E - D) / 2
    add a,e
    sub d
    srl a
    ld b,a
    ld a,e                      ; B's total within MAX_SLOTS
    sub MAX_SLOTS-MAIN_SLOTS
    jr c,cs_one
    cp b
    jr c,cs_one
    ld b,a
cs_one
    ld a,b                      ; at least one
    or a
    jr nz,cs_max
    inc b
cs_max
    ld a,MAX_SLOTS              ; A's total within MAX_SLOTS
    sub d
    cp b
    jr nc,cs_left
    ld b,a
cs_left
    ld a,MAIN_SLOTS-1           ; and one left for B
    cp b
    ret nc
    ld b,a
    ret

;; load_special - IX = fighter: its special's kind and projectile record
;; into F_SPKIND..F_PCODEL. Destroys AF, BC, DE, HL.
load_special
    call page_char
    ld a,(DIR_SPECIAL)
    ld (ix+F_SPKIND),a
    ld hl,(DIR_SHOT)
    ld a,h
    or l
    jr z,page_main
    push ix
    pop de
    push hl
    ld hl,F_PW
    add hl,de
    ex de,hl
    pop hl
    ld bc,PR_SIZE
    ldir
    jr page_main

;; char_slots - IX = fighter: A = its character's cache slots in bank 1.
;; own_inks - IX = fighter, DE = 4 palette entries: its character's inks
;; there. Destroy AF, BC (and DE, HL).
char_slots
    call page_char
    ld a,(DIR_SLOTS)
    jr page_main
own_inks
    call page_char
    ld hl,DIR_INKS
    ld bc,4
    ldir
page_main
    ld bc,#7FC0
    out (c),c
    ret
page_char
    ld a,(ix+F_RAM0)
    ld bc,#7F00
    out (c),a
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
;; ticks after the last picture started. Destroys AF, BC, DE, HL, IY.
wait_render
    call shot_pass              ; (the projectiles, when the beam allows)
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
F_SPKIND        EQU F_HIST+HIST_LEN         ; the special (special.asm):
F_PW            EQU F_SPKIND+1              ; its kind, and the projectile's
F_PH            EQU F_PW+1                  ; width, lines, speed, damage,
F_PSPEED        EQU F_PH+1                  ; hitstun and compiled draws,
F_PDMG          EQU F_PSPEED+1              ; copied from the directory
F_PSTUN         EQU F_PDMG+1
F_PCODE         EQU F_PSTUN+1
F_PCODEL        EQU F_PCODE+2
F_PACT          EQU F_PCODEL+2              ; the projectile: flying, where,
F_PX            EQU F_PACT+1                ; which way (0 right, 1 left),
F_PY            EQU F_PX+1
F_PDIR          EQU F_PY+1
F_PDRAWN        EQU F_PDIR+1                ; and what is on the screen
F_POX           EQU F_PDRAWN+1
F_POY           EQU F_POX+1
F_PODIR         EQU F_POY+1
F_PVIS          EQU F_PODIR+1               ; shown in the next pass
F_FB            EQU F_PVIS+1                ; the frame's drawn box (x0, x1,
F_OFB           EQU F_FB+4                  ; y0, y1 from its left edge and
F_SIZE          EQU F_OFB+4                 ; top, facing), and the shown one

;; The moves and the rules they follow (fighter.asm).
MV_IDLE         EQU 0
MV_WALK         EQU 1
MV_CROUCH       EQU 2
MV_JUMP         EQU 3
MV_PUNCH        EQU 4
MV_KICK         EQU 5
MV_SWEEP        EQU 6
MV_UPPERCUT     EQU 7
MV_BACKKICK     EQU 8
MV_BLOCK        EQU 9
MV_HIT          EQU 10
MV_KO           EQU 11
MV_SPECIAL      EQU 12
MV_VICTORY      EQU 13

FRAME_PICS      EQU 2           ; pictures per animation frame
WALK_STEP       EQU 1           ; bytes per picture (2 mode 0 pixels)
JUMP_STEP       EQU 1           ; bytes per picture across, in a jump
JUMP_PICS       EQU 16          ; pictures in the air (jump_arc)
X_MAX           EQU BYTES_PER_LINE-SPR_W
MIN_SEP         EQU 10          ; closest two standing boxes may be (bytes)
HEALTH_MAX      EQU 40          ; a full health bar, one byte a point
HIT_PUSH        EQU 3           ; bytes a hit knocks the defender back,
BLOCK_PUSH      EQU 1           ; and a block
BLOCK_STUN      EQU 4           ; pictures a standing block holds at least
KD_PICS         EQU 36          ; a knockdown: falling, lying, getting up
HIST_LEN        EQU 12          ; pictures of motion history (0.48 s)
DR_UP           EQU 1           ; the history: the stick turned to the
DR_DOWN         EQU 2           ; fighter's facing
DR_BACK         EQU 4           ; (facing right these are the CT_ bits)
DR_FWD          EQU 8

DIR_SLOTS       EQU #4004       ; in a character's bank 0: bank 1 cache
DIR_INKS        EQU #4007       ; slots (count, first), the inks of its 4
DIR_SPECIAL     EQU #400B       ; colours, its special's kind and
DIR_SHOT        EQU #400C       ; projectile record, then the moves
DIR_MOVES       EQU #400E
SP_STRIKE       EQU 0           ; special kinds
SP_SHOT         EQU 1
SP_THROW        EQU 2
PR_SIZE         EQU 9           ; a projectile record: F_PW..F_PCODEL
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
    call fly_shots              ; projectiles (special.asm), then attacks
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
    IF SHOTS                    ; SHOTS=1: projectiles (of characters that
    ld ix,fighter_a             ; have one) sweep across, A's to the right,
    ld c,0                      ; B's to the left
    call demo_shot
    ld ix,fighter_b
    ld c,1
    call demo_shot
    ENDIF
    ld ix,fighter_a
    call load_frame
    ld ix,fighter_b
    jp load_frame

    IF SHOTS
;; demo_shot - IX = fighter, C = direction: its projectile at hand height,
;; 2 bytes on every picture over 32 pictures, then round again.
demo_shot
    ld a,(ix+F_SPKIND)
    cp SP_SHOT
    ret nz
    ld (ix+F_PACT),1
    ld (ix+F_PDIR),c
    ld (ix+F_PY),FIGHTER_Y+27
    ld a,(render_count)
    and 31
    add a,a
    dec c
    jr nz,ds_x
    neg
    add a,BYTES_PER_LINE-16
    jr ds_set
ds_x
    add a,8
ds_set
    ld (ix+F_PX),a
    ret
    ENDIF

jump_arc                        ; rise and fall over 16 pictures, top at
    defb 7,21,32,42,50,55,59,60,60,59,55,50,42,32,21,7  ; JUMP_MAX lines
    ASSERT JUMP_MAX>=60

sway                            ; -6..6, a triangle over 32 steps
    defb 0,1,2,3,4,5,6,6,6,5,4,3,2,1,0,0
    defb 0,-1,-2,-3,-4,-5,-6,-6,-6,-5,-4,-3,-2,-1,0,0

;; load_frame - IX = fighter: show its F_MOVE / F_FRAME in its F_FACE
;; facing (and F_FB, where it draws, for special.asm shot_vis). The frame's compiled draw comes from the fighter's cache (jit.asm);
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
    inc hl                      ; (its size)
    inc hl
    inc hl                      ; the drawn box (its hurt box), turned to
    ld a,(ix+F_FACE)            ; the facing
    or a
    jr nz,lf_left
    ld a,(hl)
    ld (ix+F_FB),a
    inc hl
    ld a,(hl)
    ld (ix+F_FB+1),a
    jr lf_y
lf_left
    ld a,(ix+F_W)               ; w - 1 - x, ends swapped
    dec a
    ld c,a
    sub (hl)
    ld (ix+F_FB+1),a
    inc hl
    ld a,c
    sub (hl)
    ld (ix+F_FB),a
lf_y
    inc hl
    ld a,(hl)
    ld (ix+F_FB+2),a
    inc hl
    ld a,(hl)
    ld (ix+F_FB+3),a
    ld bc,#7FC0
    out (c),c
    ret

;; move_frames - F_NFR = the number of frames in F_MOVE, from the
;; character's directory. Destroys AF, BC, DE, HL.
move_frames
    ld a,(ix+F_RAM0)
    ld bc,#7F00
    out (c),a
    ld a,(ix+F_MOVE)
    ld l,a
    add a,a
    add a,l
    ld l,a
    ld h,0
    ld de,DIR_MOVES
    add hl,de
    ld a,(hl)
    ld (ix+F_NFR),a
    ld bc,#7FC0
    out (c),c
    ret

;; ---------------------------------------------------------------------------
;; shot_pass - the projectiles' restore and draw, outside the rebuild, once
;; between pictures after prepare (shot_pending): each one shown is taken
;; off, then each one shot_vis allowed is drawn where it is now. A
;; projectile is never drawn where a fighter's frame is, on the screen or
;; next (shot_vis), so this and the rebuild never touch the same bytes, and
;; only the beam is in the way: projectiles are on lines SHOT_TOP to the
;; floor, so the pass runs from the rebuild tick (interrupt TICK_IRQ) until
;; interrupt 3 (line 118), and is done before the beam reaches SHOT_TOP.
;; jit_work calls it between compiles, and wait_render while it waits.
;; Destroys AF, BC, DE, HL, IY.
;; ---------------------------------------------------------------------------
shot_pass
    ld a,(shot_pending)
    or a
    ret z
    ld a,(irq_count)
    cp 3
    jr c,sp_go
    cp TICK_IRQ
    ret c
sp_go
    xor a
    ld (shot_pending),a
    ld (jc_flag),a              ; (not in period TICK_IRQ-1: see above)
    push ix
    ld a,(bench_phase)
    push af
    ld a,PH_SHOT
    ld (bench_phase),a
    ld ix,fighter_a             ; both off first: they may overlap
    call sp_restore
    ld ix,fighter_b
    call sp_restore
    ld ix,fighter_a
    call sp_draw
    ld ix,fighter_b
    call sp_draw
    pop af
    ld (bench_phase),a
    pop ix
    ret

sp_restore
    ld a,(ix+F_PDRAWN)
    or a
    ret z
    ld (ix+F_PDRAWN),0
    ld a,(ix+F_PH)
    ld (rr_count),a
    ld e,(ix+F_POX)
    ld d,(ix+F_PW)
    ld a,(ix+F_POY)
    ld hl,rect_restore
    ld b,#C0
    jr sp_call

sp_draw
    ld a,(ix+F_PVIS)
    or a
    ret z
    ld (ix+F_PDRAWN),1
    ld a,(ix+F_PX)
    ld (ix+F_POX),a
    ld e,a
    ld d,0
    ld l,(ix+F_PCODE)
    ld h,(ix+F_PCODE+1)
    ld a,(ix+F_PDIR)
    ld (ix+F_PODIR),a
    or a
    jr z,sd_right
    ld l,(ix+F_PCODEL)
    ld h,(ix+F_PCODEL+1)
sd_right
    ld b,(ix+F_RAM0)
    ld a,(ix+F_PY)
    ld (ix+F_POY),a

;; sp_call - A = top line, HL = routine, DE for it, B = the RAM it runs in:
;; run a rebuild routine (SP walking line_tab from A, IXL = chunks, yield
;; by JP (IY)) with interrupts off.
sp_call
    push ix
    push hl
    ld l,a
    ld h,0
    add hl,hl
    ld a,b
    ld bc,line_tab
    add hl,bc
    ld (sc_sp),hl
    pop hl
    ld bc,#7F00
    di
    out (c),a
    ld (rebuild_sp),sp
    ld ixl,255
    ld sp,(sc_sp)
    ld iy,sc_ret
    jp (hl)
sc_ret
    ld sp,(rebuild_sp)
    ld bc,#7FC0
    out (c),c
    ei
    pop ix
    ret

    include "jit.asm"
    include "crtc.asm"
    include "irq.asm"
    include "video.asm"
    include "sprite.asm"
    include "rebuild.asm"

;; ---------------------------------------------------------------------------
;; Tables and sprite data
;; ---------------------------------------------------------------------------


line_tab        EQU LINE_TAB_AT

payload_end
    ASSERT payload_end<=STAGE_AT    ; boot unpacks the stage before the copy
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
shot_pending    defb 0          ; special.asm: the projectiles' pass is due
sc_sp           defw 0          ; shot_pass: SP for the routine it runs
jc_flag         defb 0          ; irq.asm: the compiler should look up

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

;; The logic: in gaps of the background mirror, which only runs with main
;; RAM at #4000. Boot copies it there last, above the load image.
gap1_store      EQU cold2_store+cold2_end-cold2_start
    ORG GAP1_ORG,gap1_store
gap1_start
    include "fighter.asm"
gap1_end
    ASSERT gap1_end<=GAP1_ORG+GAP_ROOM
gap2_store      EQU gap1_store+gap1_end-gap1_start
    ORG GAP2_ORG,gap2_store
gap2_start
    include "moves.asm"
gap2_end
    ASSERT gap2_end<=GAP2_ORG+GAP_ROOM
gap3_store      EQU gap2_store+gap2_end-gap2_start
    ORG GAP3_ORG,gap3_store
gap3_start
    include "input.asm"
    include "shotvis.asm"
gap3_end
    ASSERT gap3_end<=GAP3_ORG+GAP_ROOM
gap4_store      EQU gap3_store+gap3_end-gap3_start
    ORG GAP4_ORG,gap4_store
gap4_start
    include "special.asm"
gap4_end
    ASSERT gap4_end<=GAP4_ORG+GAP_ROOM
image_end       EQU gap4_store+gap4_end-gap4_start
    ASSERT image_end<=GAP1_ORG          ; the copies never overwrite their source

    RUN boot
    SAVE 'PFSPIKE.BIN',boot,image_end-boot,DSK,'../build/pfspike.dsk'

;; ---------------------------------------------------------------------------
;; The characters, in the extra 64K, for the snapshot: fighter A in banks
;; 4-5, fighter B in banks 6-7 (make CHAR_A=... CHAR_B=..., Trump and Putin
;; by default). On the disc they are character files that the select
;; screen loads (loader.asm).
;; ---------------------------------------------------------------------------
    include "gen/chars.asm"

;; The stage, packed, where the select screen would have loaded it (make
;; STAGE=..., fighter B's character's home stage by default).
    BANKSET 0
    ORG STAGE_AT
    include "gen/stage.asm"
    ASSERT $<=STAGE_AT+STAGE_ROOM
