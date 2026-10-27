;; ===========================================================================
;; start.asm - once, after boot: the workspace, the fighters, the stage's
;; HUD and mirror, the characters' caches, colours and specials, then the
;; first picture. Cold code in a gap of the background mirror (GAP7_ORG):
;; whatever it calls that pages a character's bank in comes back with main
;; RAM.
;; ===========================================================================

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
    ld ix,fighter_a             ; and specials, and victory lines
    ld de,taunt_a
    call load_special
    ld ix,fighter_b
    ld de,taunt_b
    call load_special
    call setup_crtc
    ld hl,palette_game
    call set_palette
    call sound_init
    call irq_init
    ld hl,song_fight
    call music_play
    ld a,SFX_BELL
    call sfx_play
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
    jp main_loop

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
