;; ===========================================================================
;; rebuild.asm - the banded rebuild: take the fighters' old pictures off and
;; put the new ones down, working down the screen ahead of the beam.
;;
;; A rebuild is up to four jobs:
;;     restore A, restore B     copy the mirror back over the old frame
;;     draw A, draw B           draw the new frame (B ends up on top)
;; Instead of running them one after another, the scheduler walks the screen
;; in bands of BAND scanlines, top to bottom, and runs each job as far as the
;; band allows. Every band is finished soon after its work is, so a fighter
;; high on the screen (a jump) is back before the beam reaches it, even when
;; both fighters share one window because they overlap.
;;
;; Per scanline the order must stay restore, restore, draw A, draw B, or a
;; restore would bite into a draw, or A would land on top of B. Restores and
;; the generic drawer can stop on any line; compiled draws only every CHUNK
;; lines. So each job runs to its own target, staggered by one chunk:
;;     restores  to band_end + 2*CHUNK   (exactly)
;;     draw A    to band_end + CHUNK     (next chunk boundary, < +2*CHUNK)
;;     draw B    to band_end             (next chunk boundary, < +CHUNK)
;; Any line a job touches has then already been finished by every job that
;; must come before it on that line.
;;
;; Lines are kept relative to BAND_TOP so all the arithmetic is 8-bit: a
;; fighter is never above BAND_TOP, the top of the background mirror.
;;
;; The rebuild starts on line 222 and runs across VSYNC, so interrupts are
;; let in after every job (INT_WINDOW, on the real stack): no stretch with
;; them off is longer than ~1.3 ms, and the interrupt count stays exact
;; (irq.asm).
;; ===========================================================================

BAND            EQU 16          ; scanlines per band

;; INT_WINDOW - take any pending interrupt on the real stack. The next job
;; reloads SP from its record, so SP is free to point anywhere here.
    MACRO INT_WINDOW
    ld sp,(rebuild_sp)
    ei
    nop                         ; EI takes effect after the next instruction
    di
    MEND
CHUNK           EQU 8           ; compiled draws yield every CHUNK lines
LOOK_RESTORE    EQU 2*CHUNK
LOOK_DRAW_A     EQU CHUNK
LOOK_DRAW_B     EQU 0

;; Job record
J_RESUME        EQU 0           ; where the job continues
J_SP            EQU 2           ; its line_tab pointer (or restore list)
J_DE            EQU 4           ; stream pointer, or x for a compiled draw
J_CUR           EQU 6           ; next scanline, relative to BAND_TOP
J_LEFT          EQU 7           ; scanlines (or chunks) still to do
J_RAM           EQU 8           ; RAM configuration it runs in (#C0: mirror)
J_X             EQU 9           ; passed in A: a generic drawer's column
J_SIZE          EQU 10

;; Both RUN macros end in the same dispatch: page the job's RAM in, load
;; its registers and run it from where it stopped. It yields to @ret with
;; HL = where to resume. (Written out in each: rasm's @ labels are local to
;; one macro level.)

;; ---------------------------------------------------------------------------
;; RUN_RESTORE - run a restore, which can stop on any scanline, up to
;; target. The two restores run back to back and each is under ~0.75 ms
;; with interrupts off, so only the second lets interrupts in.
;; RUN_CHUNKS - run a compiled draw for whole chunks, to the first chunk
;; boundary at or past target.
;; ---------------------------------------------------------------------------
    MACRO RUN_RESTORE job,look,phase,window
    ld a,({job}+J_LEFT)
    or a
    jr z,@skip
    ld a,(band_end)
    add a,{look}
    ld hl,{job}+J_CUR
    sub (hl)                    ; scanlines to the target
    jr c,@skip
    jr z,@skip
    ld hl,{job}+J_LEFT
    cp (hl)
    jr c,@n_ok
    ld a,(hl)                   ; no more than are left
@n_ok
    ld (rr_count),a
    ld c,a
    ld a,(hl)
    sub c
    ld (hl),a
    ld a,({job}+J_CUR)
    add a,c
    ld ({job}+J_CUR),a
    ld bc,#7FC0                 ; a restore reads the mirror: always #C0,
    out (c),c                   ; and it needs nothing but SP
    ld a,{phase}
    ld (bench_phase),a
    ld sp,({job}+J_SP)
    ld hl,({job}+J_RESUME)
    ld iy,@ret
    jp (hl)
@ret
    ld ({job}+J_SP),sp
    ld ({job}+J_RESUME),hl
    ld a,PH_SCHED
    ld (bench_phase),a
    IF {window}
    INT_WINDOW
    ENDIF
@skip
    MEND

    MACRO RUN_CHUNKS job,look,phase
    ld a,({job}+J_LEFT)
    or a
    jr z,@skip
    ld a,(band_end)
    add a,{look}
    ld hl,{job}+J_CUR
    sub (hl)
    jr c,@skip
    jr z,@skip
    add a,CHUNK-1               ; chunks to reach the target, rounded up
    rrca
    rrca
    rrca
    and #1F
    ld hl,{job}+J_LEFT
    cp (hl)
    jr c,@n_ok
    ld a,(hl)
@n_ok
    ld c,a
    ld a,(hl)
    sub c
    ld (hl),a
    ld a,c
    add a,a
    add a,a
    add a,a                     ; * CHUNK
    ld hl,{job}+J_CUR
    add a,(hl)
    ld (hl),a
    ld a,c
    ld ixl,a
    ld a,({job}+J_RAM)
    ld bc,#7F00
    out (c),a
    ld a,{phase}
    ld (bench_phase),a
    ld a,({job}+J_X)
    ld de,({job}+J_DE)
    ld sp,({job}+J_SP)
    ld hl,({job}+J_RESUME)
    ld iy,@ret
    jp (hl)
@ret
    ld ({job}+J_SP),sp
    ld ({job}+J_RESUME),hl
    ld ({job}+J_DE),de          ; a generic drawer's stream pointer
    ld a,PH_SCHED
    ld (bench_phase),a
    INT_WINDOW
@skip
    MEND

;; ---------------------------------------------------------------------------
;; rebuild - run the jobs that setup_* prepared, band by band.
;; Interrupts are off throughout and SP walks line_tab; the stack pointer is
;; saved first and put back at the end. Destroys everything.
;; ---------------------------------------------------------------------------
rebuild
    di
    ld (rebuild_sp),sp
    ld a,PH_SCHED
    ld (bench_phase),a
rb_band
    RUN_RESTORE job_ra,LOOK_RESTORE,PH_RESTORE_A,0
    RUN_RESTORE job_rb,LOOK_RESTORE,PH_RESTORE_B,1
    RUN_CHUNKS job_da,LOOK_DRAW_A,PH_DRAW_A
    RUN_CHUNKS job_db,LOOK_DRAW_B,PH_DRAW_B
    ld a,(job_ra+J_LEFT)
    ld hl,job_rb+J_LEFT
    or (hl)
    ld hl,job_da+J_LEFT
    or (hl)
    ld hl,job_db+J_LEFT
    or (hl)
    jr z,rb_done
    ld a,(band_end)
    add a,BAND
    ld (band_end),a
    jp rb_band
rb_done
    ld sp,(rebuild_sp)
    ld bc,#7FC0                 ; the mirror back at #4000
    out (c),c
    ei
    xor a
    ld (bench_phase),a
    ret

;; ---------------------------------------------------------------------------
;; Job set-up, before the rebuild (ordinary code, with a stack).
;;
;; prepare - set up the first window of the next picture: both fighters if
;; their ground overlaps (together = 1), otherwise A; B's window is set up
;; after A's rebuild, while the loop waits for the next tick. Done at the
;; end of the logic so the rebuild can start on the tick itself.
;; rebuild_clear - no jobs, and band_end as far down as it goes.
;; setup_a / setup_b - the restore and draw jobs for one fighter; each pulls
;; band_end up to its fighter's first scanline + BAND.
;; ---------------------------------------------------------------------------
prepare
    call rebuild_clear
    call ground_overlap
    ld (together),a
    call setup_a
    ld a,(together)
    or a
    ret z
    jp setup_b

rebuild_clear
    xor a
    ld (job_ra+J_LEFT),a
    ld (job_rb+J_LEFT),a
    ld (job_da+J_LEFT),a
    ld (job_db+J_LEFT),a
    ld a,255
    ld (band_end),a
    ret

setup_a
    ld ix,fighter_a
    ld hl,job_ra
    ld de,job_da
    jr setup_fighter

setup_b
    ld ix,fighter_b
    ld hl,job_rb
    ld de,job_db

;; setup_fighter - IX = fighter, HL = its restore job, DE = its draw job.
;; The restore takes off what is on the screen, from the list prebuild made
;; of it; the draw puts down the frame load_frame fetched, and the F_O*
;; fields then describe that frame. Destroys everything but IX.
setup_fighter
    ld (sf_draw),de
    ld a,(ix+F_DRAWN)
    or a
    jr z,sf_draw_job
    push hl                     ; restore job
    pop iy
    ld e,(ix+F_RLIST)
    ld d,(ix+F_RLIST+1)
    ld l,(ix+F_RFIRST)
    ld a,(ix+F_RLINES)
    call setup_restore
sf_draw_job
    ld a,(ix+F_FBANK)           ; the new frame's spans
    ld bc,#7F00
    out (c),a
    ld a,(ix+F_X)               ; the frame's left edge: box x + offset
    add a,(ix+F_OFF)
    ld (sf_x),a
    ld iy,(sf_draw)
    ld l,(ix+F_SPANS)
    ld h,(ix+F_SPANS+1)
    ld a,(ix+F_Y)
    call setup_job              ; lines are padded to whole chunks
    ld a,(iy+J_LEFT)
    rrca
    rrca
    rrca
    and #1F
    ld (iy+J_LEFT),a
    ld a,(ix+F_CDRAW)
    or (ix+F_CDRAW+1)
    jr z,sf_generic
    ld a,(ix+F_CDRAW)           ; compiled: runs from its bank, DE = x
    ld (iy+J_RESUME),a
    ld a,(ix+F_CDRAW+1)
    ld (iy+J_RESUME+1),a
    ld a,(ix+F_CBANK)
    ld (iy+J_RAM),a
    ld a,(sf_x)
    ld (iy+J_DE),a
    ld (iy+J_DE+1),0
    jr sf_record
sf_generic
    ld a,(ix+F_FBANK)
    ld (iy+J_RAM),a
    ld a,(ix+F_FACE)
    or a
    ld a,(sf_x)
    ld hl,draw_r
    jr z,sf_gen_x
    add a,(ix+F_W)              ; facing left: byte 0 lands at x + w - 1
    dec a
    ld hl,draw_l
sf_gen_x
    ld (iy+J_X),a
    ld (iy+J_RESUME),l
    ld (iy+J_RESUME+1),h
sf_record
    ld a,(sf_x)                 ; what is now on the screen
    ld (ix+F_OX),a
    ld a,(ix+F_Y)
    ld (ix+F_OY),a
    ld a,(ix+F_W)
    ld (ix+F_OW),a
    ld a,(ix+F_FACE)
    ld (ix+F_OFACE),a
    ld a,(ix+F_FBANK)
    ld (ix+F_OBANK),a
    ld a,(ix+F_SPANS)
    ld (ix+F_OSPANS),a
    ld a,(ix+F_SPANS+1)
    ld (ix+F_OSPANS+1),a
    ld a,(ix+F_SN)
    ld (ix+F_OSN),a
    ld a,(ix+F_SN+1)
    ld (ix+F_OSN+1),a
    ld (ix+F_DRAWN),1
    ld bc,#7FC0
    out (c),c
    ret

;; setup_restore - IY = job, DE = restore list, L = its first scanline,
;; A = its lines. Points the job at the list. Destroys AF, BC, DE, HL.
setup_restore
    ld (iy+J_SP),e
    ld (iy+J_SP+1),d
    ld (iy+J_LEFT),a
    ld (iy+J_RESUME),restore AND #FF
    ld (iy+J_RESUME+1),restore>>8
    ld (iy+J_RAM),#C0
    ld a,l
    jr sj_cur

;; prebuild - IX = fighter: build the restore list of what the F_O* fields
;; say is on the screen (or will be, once a pending window has run), into
;; the fighter's other list, for the next setup_fighter. The main loop runs
;; it in the time between windows, so the set-up after the logic is cheap.
;; Destroys everything but IX.
prebuild
    ld a,(ix+F_DRAWN)
    or a
    ret z
    ld a,(ix+F_OBANK)           ; the (s, n) table is in the frame's bank
    ld bc,#7F00
    out (c),a
    ld a,(ix+F_OW)
    ld (br_w),a
    ld a,(ix+F_RLIST+1)         ; the list not in use
    xor RESTORE_FLIP
    ld (ix+F_RLIST+1),a
    ld d,a
    ld e,(ix+F_RLIST)
    ld l,(ix+F_OSN)
    ld h,(ix+F_OSN+1)
    ld c,(ix+F_OX)
    ld b,(ix+F_OFACE)
    ld a,(ix+F_OY)
    call build_restore
    ld (ix+F_RFIRST),l
    ld (ix+F_RLINES),a
    ld bc,#7FC0
    out (c),c
    ret

;; setup_job - IY = job, HL = span stream, A = sprite top scanline. Points
;; the job at the stream's first line. Destroys AF, BC, DE, HL.
setup_job
    add a,(hl)                  ; first drawn scanline (y + top < 256)
    inc hl
    ld c,(hl)                   ; lines
    inc hl
    ld (iy+J_DE),l
    ld (iy+J_DE+1),h
    ld (iy+J_LEFT),c
    ld e,a
    ld d,0
    ld hl,line_tab
    add hl,de
    add hl,de
    ld (iy+J_SP),l
    ld (iy+J_SP+1),h
sj_cur
    sub BAND_TOP
    ld (iy+J_CUR),a
    add a,BAND                  ; the first band ends BAND lines below the
    ld hl,band_end              ; highest job's first line
    cp (hl)
    ret nc
    ld (hl),a
    ret
