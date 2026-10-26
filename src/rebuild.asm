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
;; ===========================================================================

BAND            EQU 16          ; scanlines per band
CHUNK           EQU 8           ; compiled draws yield every CHUNK lines
LOOK_RESTORE    EQU 2*CHUNK
LOOK_DRAW_A     EQU CHUNK
LOOK_DRAW_B     EQU 0

;; Job record
J_RESUME        EQU 0           ; where the job continues
J_SP            EQU 2           ; its line_tab pointer
J_DE            EQU 4           ; stream pointer, or x for a compiled draw
J_CUR           EQU 6           ; next scanline, relative to BAND_TOP
J_LEFT          EQU 7           ; scanlines (or chunks) still to do
J_SIZE          EQU 8

;; ---------------------------------------------------------------------------
;; RUN_LINES - run a job that can stop on any scanline, up to target.
;; RUN_CHUNKS - run a compiled draw for whole chunks, to the first chunk
;; boundary at or past target.
;; ---------------------------------------------------------------------------
    MACRO RUN_LINES job,look,count,phase
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
    ld ({count}),a
    ld c,a
    ld a,(hl)
    sub c
    ld (hl),a
    ld a,({job}+J_CUR)
    add a,c
    ld ({job}+J_CUR),a
    ld a,{phase}
    ld (bench_phase),a
    ld de,({job}+J_DE)
    ld sp,({job}+J_SP)
    ld hl,({job}+J_RESUME)
    ld iy,@ret
    jp (hl)
@ret
    ld ({job}+J_SP),sp
    ld ({job}+J_RESUME),hl
    ld ({job}+J_DE),de
    ld a,PH_SCHED
    ld (bench_phase),a
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
    ld a,{phase}
    ld (bench_phase),a
    ld de,({job}+J_DE)
    ld sp,({job}+J_SP)
    ld hl,({job}+J_RESUME)
    ld iy,@ret
    jp (hl)
@ret
    ld ({job}+J_SP),sp
    ld ({job}+J_RESUME),hl
    ld a,PH_SCHED
    ld (bench_phase),a
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
    RUN_LINES job_ra,LOOK_RESTORE,rr_count,PH_RESTORE_A
    RUN_LINES job_rb,LOOK_RESTORE,rr_count,PH_RESTORE_B
    RUN_CHUNKS job_da,LOOK_DRAW_A,PH_DRAW_A
    IF PUTIN_COMPILED
    RUN_CHUNKS job_db,LOOK_DRAW_B,PH_DRAW_B
    ELSE
    RUN_LINES job_db,LOOK_DRAW_B,dl_count,PH_DRAW_B
    ENDIF
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
    ei
    xor a
    ld (bench_phase),a
    ret

;; ---------------------------------------------------------------------------
;; Job set-up, before the rebuild (ordinary code, with a stack).
;;
;; prepare - set up the first window of the next picture: both fighters if
;; their ground overlaps (together = 1), otherwise Trump; Putin's window is
;; set up after Trump's rebuild, while the loop waits for the next tick.
;; Done at the end of the logic so the rebuild can start on the tick itself.
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
    ld a,(fa_drawn)             ; restore: the frame still on the screen
    or a
    jr z,sa_draw
    ld ix,job_ra
    ld hl,(fa_old_sn)
    ld de,RESTORE_LIST_A
    ld a,(fa_old_x)
    ld c,a
    ld b,0                      ; facing right
    ld a,(fa_old_y)
    call setup_restore
sa_draw
    ld hl,(fa_sn)               ; what the next restore will take off
    ld (fa_old_sn),hl
    ld ix,job_da                ; draw: the new frame, compiled
    ld hl,(fa_spans)
    ld (fa_old_spans),hl
    ld a,(fa_y)
    ld (fa_old_y),a
    ld bc,(fa_draw)
    call setup_job
    call to_chunks
    ld a,(fa_x)
    ld (fa_old_x),a
    ld (job_da+J_DE),a
    xor a
    ld (job_da+J_DE+1),a
    inc a
    ld (fa_drawn),a
    ret

setup_b
    ld a,(fb_drawn)
    or a
    jr z,sb_draw
    ld ix,job_rb
    ld hl,(fb_old_sn)
    ld de,RESTORE_LIST_B
    ld a,(fb_old_x)
    ld c,a
    ld b,1                      ; facing left
    ld a,(fb_old_y)
    call setup_restore
sb_draw
    ld hl,(fb_sn)
    ld (fb_old_sn),hl
    ld ix,job_db
    ld hl,(fb_spans)
    ld (fb_old_spans),hl
    ld a,(fb_y)
    ld (fb_old_y),a
    IF PUTIN_COMPILED
    ld bc,(fb_draw)
    call setup_job
    call to_chunks
    ld a,(fb_x)
    ld (fb_old_x),a
    ld (job_db+J_DE),a
    xor a
    ld (job_db+J_DE+1),a
    ELSE
    ld bc,draw_l
    call setup_job
    ld a,(fb_x)
    ld (fb_old_x),a
    add a,SPR_W-1
    ld (dl_xr+1),a
    ENDIF
    ld a,1
    ld (fb_drawn),a
    ret

;; setup_restore - IX = job, HL = (s, n) table, DE = list buffer, A = y,
;; C = x, B = facing (0 right, 1 left). Builds the restore list and points
;; the job at it. Destroys everything but IX.
setup_restore
    push de
    call build_restore          ; HL = first scanline, A = lines
    pop de
    ld (ix+J_SP),e
    ld (ix+J_SP+1),d
    ld (ix+J_LEFT),a
    ld (ix+J_RESUME),restore AND #FF
    ld (ix+J_RESUME+1),restore>>8
    ld a,l
    jr sj_cur

;; setup_job - IX = job, HL = span stream, A = sprite top scanline,
;; BC = resume address. Sets the job up for every line of the frame.
;; Destroys AF, BC, DE, HL.
setup_job
    ld (ix+J_RESUME),c
    ld (ix+J_RESUME+1),b
    add a,(hl)                  ; first drawn scanline (y + top < 256)
    inc hl
    ld c,(hl)                   ; lines
    inc hl
    ld (ix+J_DE),l
    ld (ix+J_DE+1),h
    ld (ix+J_LEFT),c
    ld e,a
    ld d,0
    ld hl,line_tab
    add hl,de
    add hl,de
    ld (ix+J_SP),l
    ld (ix+J_SP+1),h
sj_cur
    sub BAND_TOP
    ld (ix+J_CUR),a
    add a,BAND                  ; the first band ends BAND lines below the
    ld hl,band_end              ; highest job's first line
    cp (hl)
    ret nc
    ld (hl),a
    ret

;; to_chunks - turn IX's scanline count into a chunk count. Destroys AF.
to_chunks
    ld a,(ix+J_LEFT)
    add a,CHUNK-1
    rrca
    rrca
    rrca
    and #1F
    ld (ix+J_LEFT),a
    ret
