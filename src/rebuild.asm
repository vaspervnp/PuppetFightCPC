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
J_SIZE          EQU 9

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
    ld a,({job}+J_RAM)          ; main RAM, or the bank the code is in
    ld bc,#7F00
    out (c),a
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
;; prepare - set up the next picture's window: both fighters, always in one
;; window, since every frame is drawn by compiled code. Done at the end of
;; the logic so the rebuild can start on the tick itself.
;; rebuild_clear - no jobs, and band_end as far down as it goes.
;; setup_a / setup_b - the restore and draw jobs for one fighter; each pulls
;; band_end up to its fighter's first scanline + BAND.
;; ---------------------------------------------------------------------------
prepare
    call shot_vis               ; the projectiles' pass (special.asm)
    call rebuild_clear
    ld ix,fighter_a             ; decide both before either is set up
    ld iy,fighter_b
    call can_skip
    ld (skip_a),a
    ld ix,fighter_b
    ld iy,fighter_a
    call can_skip
    ld (skip_b),a
    ld a,(skip_a)
    or a
    call z,setup_a
    ld a,(skip_b)
    or a
    ret nz
    jp setup_b

;; can_skip - IX = fighter, IY = the other: A = 1 if IX's window work can be
;; left out: it shows the same frame in the same place as on the screen, and
;; neither the other's old box (its restore) nor its new one (its draw)
;; reaches IX's box. Else A = 0. Destroys AF, B, DE, HL.
can_skip
    call fighter_same
    jr nz,cs_no
    push ix                     ; the other unchanged too: nothing touches
    push iy
    pop ix
    call fighter_same
    pop ix
    jr z,cs_yes
    ld a,(iy+F_DRAWN)           ; the other's old box
    or a
    jr z,cs_new
    ld d,(iy+F_OX)
    ld e,(iy+F_OW)
    call cs_overlap
    jr c,cs_no
cs_new
    ld a,(iy+F_X)               ; and its new one
    add a,(iy+F_OFF)
    ld d,a
    ld e,(iy+F_W)
    call cs_overlap
    jr c,cs_no
cs_yes
    ld a,1
    ret
cs_no
    xor a
    ret

;; cs_overlap - CY if bytes D..D+E-1 meet IX's box on the screen.
cs_overlap
    ld a,(ix+F_OX)              ; D < OX + OW
    add a,(ix+F_OW)
    ld b,a
    ld a,d
    cp b
    ret nc
    ld a,d                      ; and OX < D + E
    add a,e
    ld b,a
    ld a,(ix+F_OX)
    cp b
    ret

;; fighter_same - IX = fighter: Z if what it will show is what the screen
;; has: same frame (bank, spans) in the same facing, place and width.
;; Destroys AF, B.
fighter_same
    ld a,(ix+F_DRAWN)
    or a
    jr z,fs_diff
    ld a,(ix+F_X)
    add a,(ix+F_OFF)
    cp (ix+F_OX)
    ret nz
    ld a,(ix+F_Y)
    cp (ix+F_OY)
    ret nz
    ld a,(ix+F_DFACE)
    cp (ix+F_OFACE)
    ret nz
    ld a,(ix+F_FBANK)
    cp (ix+F_OBANK)
    ret nz
    ld a,(ix+F_SPANS)
    cp (ix+F_OSPANS)
    ret nz
    ld a,(ix+F_SPANS+1)
    cp (ix+F_OSPANS+1)
    ret
fs_diff
    or 1
    ret

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
;; The restore takes off what is on the screen, from its restore list. Then
;; the F_O* fields take the new frame and prebuild makes that frame's list,
;; which the draw job walks for its scanline addresses (see jit.asm
;; JC_BODY) and the next picture restores from. Destroys everything but IX.
setup_fighter
    ld (sf_draw),de
    ld a,(ix+F_DRAWN)
    or a
    jr z,sf_record
    push hl                     ; restore job
    pop iy
    ld e,(ix+F_RLIST)
    ld d,(ix+F_RLIST+1)
    ld l,(ix+F_RFIRST)
    ld a,(ix+F_RLINES)
    call setup_restore
sf_record
    ld a,(ix+F_X)               ; what will be on the screen: the frame's
    add a,(ix+F_OFF)            ; left edge, box x + offset
    ld (ix+F_OX),a
    ld a,(ix+F_Y)
    ld (ix+F_OY),a
    ld a,(ix+F_W)
    ld (ix+F_OW),a
    ld a,(ix+F_DFACE)
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
    ld a,(ix+F_FB)              ; (its drawn box, for special.asm)
    ld (ix+F_OFB),a
    ld a,(ix+F_FB+1)
    ld (ix+F_OFB+1),a
    ld a,(ix+F_FB+2)
    ld (ix+F_OFB+2),a
    ld a,(ix+F_FB+3)
    ld (ix+F_OFB+3),a
    ld (ix+F_DRAWN),1
    call prebuild               ; its list (unless it is the same as now)
    ld iy,(sf_draw)             ; the draw: compiled code, walking it
    ld a,(ix+F_RLIST)
    ld (iy+J_SP),a
    ld a,(ix+F_RLIST+1)
    ld (iy+J_SP+1),a
    ld a,(ix+F_RLINES)          ; whole chunks
    add a,CHUNK-1
    rrca
    rrca
    rrca
    and #1F
    ld (iy+J_LEFT),a
    ld a,(ix+F_CDRAW)
    ld (iy+J_RESUME),a
    ld a,(ix+F_CDRAW+1)
    ld (iy+J_RESUME+1),a
    ld a,(ix+F_CBANK)
    ld (iy+J_RAM),a
    ld a,(ix+F_RFIRST)
    jp sj_cur

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
;; say will be on the screen into the fighter's other list (the one in use
;; is still the restore job's). A fighter showing the same frame in the same
;; place keeps its list. Destroys everything but IX.
prebuild
    ld a,(ix+F_DRAWN)
    or a
    ret z
    push ix                     ; the same frame in the same place as when
    pop hl                      ; the list was made: it still holds
    ld de,F_OX
    add hl,de
    push hl
    ld de,F_PKEY-F_OX
    add hl,de
    ex de,hl                    ; DE = F_PKEY, HL = F_OX
    pop hl
    ld b,F_OSN+2-F_OX
    ld c,0
pb_cmp
    ld a,(de)
    xor (hl)
    or c
    ld c,a
    ld a,(hl)
    ld (de),a                   ; (and the key becomes this)
    inc hl
    inc de
    djnz pb_cmp
    ld a,c
    or a
    ret z
    ld a,(ix+F_OW)              ; (the (s, n) table is in a screen tail)
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
    ret

;; sj_cur - IY = job, A = its first scanline: J_CUR, and band_end pulled
;; up to it + BAND. Destroys AF, HL.
sj_cur
    sub BAND_TOP
    ld (iy+J_CUR),a
    add a,BAND                  ; the first band ends BAND lines below the
    ld hl,band_end              ; highest job's first line
    cp (hl)
    ret nc
    ld (hl),a
    ret
