;; ===========================================================================
;; Puppet Fight CPC - milestone 1 tech spike.
;;
;; Two fighters idling on an overscan stage at 25 fps: Trump facing right,
;; drawn by compiled routines, and Putin facing left, drawn by the generic
;; mirrored span drawer. Both are erased from a background mirror. The point
;; is to measure all three against the beam - see tools/spike_bench.py and
;; docs/SPIKE.md.
;;
;; Build: make (build/pfspike.sna, build/puppetfight.dsk - RUN"PUPPET)
;; ===========================================================================

    include "config.asm"

BUILDSNA
BANKSET 0

;; GAP_COPY - gap {n}'s code from where boot put it to its gap.
    MACRO GAP_COPY n
    ld hl,gap{n}_store-gap1_store+GAP_SCRATCH
    ld de,GAP{n}_ORG
    ld bc,gap{n}_end-gap{n}_start
    ldir
    MEND

;; ---------------------------------------------------------------------------
;; The file loads at #4000 (where AMSDOS can hand over) and moves the payload
;; down to #0200, leaving #4000-#7FFF free for the background mirror.
;; ---------------------------------------------------------------------------
    ORG LOAD_ORG
boot
    di
    ld sp,STACK_TOP
    ld bc,#FA7E                 ; the disc's motor off (the firmware would
    xor a                       ; have, later)
    out (c),a
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
    ld hl,low_store             ; and the low code under the stack
    ld de,LOW_ORG
    ld bc,low_end-low_start
    ldir
    ld hl,STAGE_AT+ST_INKS      ; the stage's inks: pen 0, pens 14-15
    ld de,palette_game
    ldi
    ld de,palette_game+14
    ldi
    ldi
    ld hl,gap1_store            ; and the logic to the mirror's gaps, by
    ld de,GAP_SCRATCH           ; way of the stage's room: the image may
    ld bc,image_end-gap1_store  ; cover the gaps
    ldir
    GAP_COPY 1
    GAP_COPY 2
    GAP_COPY 3
    GAP_COPY 4
    GAP_COPY 5
    GAP_COPY 6
    GAP_COPY 7
    GAP_COPY 8
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

main_loop
    IF SLACK                    ; margin test only: start SLACK*100 us late
    call slack_wait
    ELSE
    call wait_render            ; first frame of the picture
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


;; load_special - IX = fighter, DE = its victory lines' buffer: its
;; special's kind and projectile record into F_SPKIND..F_PCODEL, and the
;; victory lines. Destroys AF, BC, DE, HL.
load_special
    call page_char
    ld hl,(DIR_TAUNT)
    ld bc,TAUNT_SIZE
    ldir
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

;; wait_render - 25 pictures a second: return in interrupt period start_irq
;; of a frame at least two ticks after the last picture started (the tick is
;; in that frame's period TICK_IRQ), with the projectiles' pass done: if it
;; is still due on the tick, the rebuild starts on the interrupt after.
;; Destroys AF, BC, DE, HL, IY.
wait_render
    call shot_pass              ; (the projectiles, when the beam allows)
    ld a,(last_render)
    ld l,a
    ld a,(tick_count)
    sub l
    cp 2
    jr c,wr_tick                ; not the frame yet
    ld a,(irq_count)
    ld hl,start_irq
    cp (hl)
    jr z,wr_start
    cp TICK_IRQ                 ; the tick's period, to start on the next:
    jr z,wait_render            ; nearly there
wr_tick
    call wait_tick
    jr wait_render
wr_start
    ld a,(shot_pending)         ; the projectiles' pass not done yet (the
    or a                        ; beam is on them): it goes first, on the
    jr z,wr_go                  ; next interrupt (or now, if this is it)
    ld (hl),CLEAR_IRQ
    jr wait_render
wr_go
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
F_AIWAIT        EQU F_OFB+4                 ; top, facing), and the shown one;
F_AIHOLD        EQU F_AIWAIT+1              ; when the computer plays it
F_AISEQ         EQU F_AIHOLD+1              ; (ai.asm): pictures to its next
F_SIZE          EQU F_AISEQ+1               ; choice, the controls it holds,
                                            ; the special's steps left

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
DIR_SHOT        EQU #400C       ; projectile record, victory lines, then
DIR_TAUNT       EQU #400E       ; the moves
DIR_MOVES       EQU #4010
TAUNT_SIZE      EQU 50          ; victory lines (victory.asm)
SP_STRIKE       EQU 0           ; special kinds
SP_SHOT         EQU 1
SP_THROW        EQU 2
PR_SIZE         EQU 9           ; a projectile record: F_PW..F_PCODEL
REC_SIZE        EQU 16
    ASSERT REC_SIZE==16             ; rec_addr shifts

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
;; floor, so the pass runs from interrupt CLEAR_IRQ (line 222) until
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
    cp CLEAR_IRQ
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
    include "sound.asm"
    include "video.asm"
    include "sprite.asm"
    include "rebuild.asm"
    include "prepare.asm"
    include "pick.asm"

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
start_irq       defb 0          ; prepare: the rebuild starts on this interrupt
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
taunt_a         defs TAUNT_SIZE ; victory.asm: each fighter's two lines,
taunt_b         defs TAUNT_SIZE ; its pen as a left pixel, where it draws
vt_on           defb 0
vt_x            defb 0
vt_lptr         defw 0
music_on        defb 0          ; sound.asm: the music is playing, its
song_speed      defb 0          ; interrupts per row, and until the next
row_tick        defb 0
ch_a            defs C_SIZE     ; its channels
ch_b            defs C_SIZE
ch_c            defs C_SIZE
sfx_req         defb 0          ; the sound effect asked for, and the one
sfx_cur         defb 0          ; playing: its record, tone period,
sfx_ptr         defw 0          ; volume, and interrupts to its next step
sfx_per         defw 0          ; down, its end, its tone's next start
sfx_vol         defb 0
sfx_dc          defb 0
sfx_t           defb 0
sfx_rc          defb 0
game_mode       defb 0          ; the select screen's choices (SETTINGS_AT)
sel_a           defb 0          ; and the characters (roster numbers)
sel_b           defb 0
ai_rnd_seed     defw 0          ; ai.asm: its dice
psg_buf         defs 2*PSG_REGS ; registers 0-10: to write, as written
    ASSERT psg_buf>>8==(psg_buf+2*PSG_REGS-1)>>8

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
low_store       EQU cold2_store+cold2_end-cold2_start
    ORG LOW_ORG,low_store
low_start
    include "stream.asm"
low_end
    ASSERT low_end<=LOW_ORG+LOW_ROOM

;; The logic: in gaps of the background mirror, which only runs with main
;; RAM at #4000. Boot copies it all to GAP_SCRATCH first, then each gap's
;; to its gap, so the image may lie over the gaps.
gap1_store      EQU low_store+low_end-low_start
    ORG GAP1_ORG,gap1_store
gap1_start
    include "fighter.asm"
    include "fdc.asm"
gap1_end
    ASSERT gap1_end<=GAP1_ORG+GAP_ROOM
gap2_store      EQU gap1_store+gap1_end-gap1_start
    ORG GAP2_ORG,gap2_store
gap2_start
    include "moves.asm"
    include "discread.asm"
gap2_end
    ASSERT gap2_end<=GAP2_ORG+GAP_ROOM
gap3_store      EQU gap2_store+gap2_end-gap2_start
    ORG GAP3_ORG,gap3_store
gap3_start
    include "input.asm"
    include "shotvis.asm"
    include "ladder.asm"
gap3_end
    ASSERT gap3_end<=GAP3_ORG+GAP_ROOM
gap4_store      EQU gap3_store+gap3_end-gap3_start
    ORG GAP4_ORG,gap4_store
gap4_start
    include "special.asm"
    include "nmstage.asm"
gap4_end
    ASSERT gap4_end<=GAP4_ORG+GAP_ROOM
gap5_store      EQU gap4_store+gap4_end-gap4_start
    ORG GAP5_ORG,gap5_store
gap5_start
    include "victory.asm"
    include "skip.asm"
gap5_end
    ASSERT gap5_end<=GAP5_ORG+GAP_ROOM
gap6_store      EQU gap5_store+gap5_end-gap5_start
    ORG GAP6_ORG,gap6_store
gap6_start
    include "logic.asm"
    include "boot.asm"
    include "fdcseek.asm"
gap6_end
    ASSERT gap6_end<=GAP6_ORG+GAP_ROOM
gap7_store      EQU gap6_store+gap6_end-gap6_start
    ORG GAP7_ORG,gap7_store
gap7_start
    include "start.asm"
    include "soundctl.asm"
gap7_end
    ASSERT gap7_end<=GAP7_ORG+GAP_ROOM
gap8_store      EQU gap7_store+gap7_end-gap7_start
    ORG GAP8_ORG,gap8_store
gap8_start
    include "ai.asm"
gap8_end
    ASSERT gap8_end<=GAP8_ORG+GAP_ROOM
image_end       EQU gap8_store+gap8_end-gap8_start
    ASSERT image_end<=#8000             ; boot unpacks the stage over #8000 first
    ASSERT GAP_SCRATCH+image_end-gap1_store<=SETTINGS_AT

    RUN boot
    SAVE '../build/PUPPET.BIN',boot,image_end-boot   ; (tools/make_dsk.py)

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
    ORG SETTINGS_AT             ; and its choices (make CPU=... LEVEL=...)
    defb CPU|LEVEL<<GM_LEVEL,CHAR_A_I,CHAR_B_I
