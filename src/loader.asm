;; ===========================================================================
;; loader.asm - the select screen and the character loader (PFLOAD.BIN).
;;
;; Runs under the firmware, before the engine takes the machine over:
;; PF.BAS loads it at #8000 and calls it, then loads and starts the engine.
;;
;; First the title screen (TITLE.SCR, tools/title_art.py), which stays up
;; while the roster and the headers are read, until a player presses fire.
;; ROSTER.TXT lists the characters on the disc, one name a line, and each
;; NAME.PFC holds one (tools/sprite_codegen.py pfc): a header with its name,
;; title and colours, then its two banks, packed. The select screen shows the names
;; and titles from the headers. Each player picks one with left and right
;; and fire, the same character twice too. C makes player 2 the computer,
;; at three levels (and C again a player): player 1 then chooses its
;; character as well, once ready. Training (GM_TRAIN) puts the training
;; dummy (DUMMY.PFC, not in the roster) up as fighter B, with no end to
;; it. The engine finds that, and who was
;; chosen (roster numbers), at SETTINGS_AT. Then fighter A's goes into
;; banks 4-5 and fighter B's into banks 6-7, unpacked as they are read a
;; byte at a time (tools/stage_pack.py's format), one bank paged in at a
;; time. The files are made for fighter B's pens, as the engine loads the
;; next opponent mid-game (src/disc.asm), so fighter A's frames then have
;; their own colours moved from pens 10-13 to 6-9 (remap_tab), and in a
;; mirror match fighter B's directory gets the character's second set of
;; colours. Last, fighter B's
;; character's home stage (NAME.STG, tools/stage_pack.py) goes to STAGE_AT,
;; where the engine's boot unpacks it into the screen.
;; ===========================================================================

TXT_OUTPUT      EQU #BB5A
TXT_SET_CURSOR  EQU #BB75
TXT_SET_PEN     EQU #BB90
KM_TEST_KEY     EQU #BB1E
SCR_SET_MODE    EQU #BC0E
SCR_SET_INK     EQU #BC32
SCR_SET_BORDER  EQU #BC38
MC_WAIT_FLYBACK EQU #BD19
CAS_IN_OPEN     EQU #BC77
CAS_IN_CLOSE    EQU #BC7A
CAS_IN_CHAR     EQU #BC80

MAX_CHARS       EQU 8
HDR_SIZE        EQU 64          ; tools/sprite_codegen.py PFC_HEADER
H_NAME          EQU 4           ; header fields
H_TITLE         EQU 12
H_ALT_INKS      EQU 40
H_LEN0          EQU 44          ; (unpacked: unused, the end mark ends one)
H_LEN1          EQU 46
H_STAGE         EQU 48
STAGE_AT        EQU #2000       ; src/config.asm
SETTINGS_AT     EQU #3FF0       ; (the engine's game_mode)
GM_CPU_B        EQU 1
GM_LEVEL        EQU 2
GM_TRAIN        EQU 4
FIGHTERS        EQU #4000       ; FIGHTERS.BIN in bank 4 (tools/title_art.py)
FI_INKS         EQU 0           ; per character: its own colours, a mirror
FI_ALT          EQU 4           ; match's, its frame as fighter A and as B
FI_A            EQU 8
FI_B            EQU FI_A+1024
FI_SIZE         EQU FI_B+1024
FI_Y            EQU 30          ; where the select screen has them: line,
FI_XA           EQU 10          ; and bytes across
FI_XB           EQU 54
MENU_ROW        EQU 14          ; the menu's first text row
ST_LEN          EQU 6           ; a stage file: header, packed length
ST_HEADER       EQU 8
TITLE_AT        EQU #9800       ; the packed title, up to the firmware's
TITLE_ROOM      EQU #B000-TITLE_AT  ; memory
TL_INKS         EQU 3           ; its file: 16 firmware colours, then (after
TL_LEN          EQU 19          ; the length) the data
TL_DATA         EQU 21
DIR_MOVES_N     EQU #4003       ; in bank 0 (src/main.asm DIR_*)
DIR_INKS        EQU #4007
DIR_MOVES       EQU #4010
REC_SIZE        EQU 16

PS_LEFT         EQU 0           ; a player's controls this frame
PS_RIGHT        EQU 1
PS_FIRE         EQU 2
PS_UP           EQU 3
PS_DOWN         EQU 4

    ORG #8000
loader
    ld hl,n_chars               ; the variables
    ld b,roster-n_chars
ld_zero
    ld (hl),0
    inc hl
    djnz ld_zero
    xor a
    call SCR_SET_MODE           ; mode 0: 20 columns, the game's look
    ld bc,0
    call SCR_SET_BORDER
    call text_inks
    call show_title             ; (none on the disc: straight on)
    call read_roster
    jp nc,disc_error
    ld hl,n_chars               ; the training dummy after them, for its
    ld a,(hl)                   ; header and its picture, but not chosen
    inc (hl)                    ; on the select screen (n_chars back)
    call rr_slot
    ex de,hl
    ld hl,s_dummy
    ld bc,8
    ldir
    call read_headers
    jp nc,disc_error
    call read_fighters
    jp nc,disc_error
    ld hl,n_chars
    dec (hl)
    call title_wait
    call select
    ld a,(cpu_b)                ; the computer's part, for the engine
    or a
    jr z,ld_mode
    dec a
    add a,a
    add a,a                     ; << GM_LEVEL
    or 1<<GM_CPU_B
ld_mode
    ld b,a                      ; or training
    ld a,(m_cpu)
    cp 2
    ld a,b
    jr nz,ld_set
    ld a,1<<GM_TRAIN
ld_set
    ld (SETTINGS_AT),a
    ld hl,(sel_a)               ; and who: sel_a, sel_b
    ld (SETTINGS_AT+1),hl

    call how_to                 ; the controls while they load
    ld hl,s_loading
    call say
    ld a,(sel_a)                ; fighter A: banks 4-5, own colours moved
    ld d,#C4
    call load_char
    jp nc,disc_error
    call remap_a
    ld a,(sel_b)                ; fighter B: banks 6-7 as it is
    ld d,#C6
    call load_char
    jp nc,disc_error
    ld a,(sel_a)                ; a mirror match: B in the second colours
    ld hl,sel_b
    cp (hl)
    call z,alt_inks
    ld bc,#7FC0
    out (c),c
    call load_stage
    jp nc,disc_error
    ld hl,s_fight
    call say
    call fire_wait
    scf
    ret

disc_error
    ld bc,#7FC0
    out (c),c
    ld hl,s_error
    call say
de_wait
    jr de_wait

;; ---------------------------------------------------------------------------
;; show_title - TITLE.SCR into the screen, in its colours: title_up = 1.
;; Nothing if it isn't there. show_screen - HL = a screen file's name, B
;; its length: the same for that one, CY if it was there. Destroys
;; everything.
;; title_wait - if the title is up: wait for fire (either player, pressed
;; after this is called), then back to the text screen.
;; ---------------------------------------------------------------------------
show_title
    ld hl,f_title
    ld b,f_title_end-f_title
    call show_screen
    ret nc
    ld a,1
    ld (title_up),a
    ret
show_screen
    ld de,cas_buffer
    call CAS_IN_OPEN
    ret nc
    ld hl,TITLE_AT
    ld b,TL_DATA
    call read_bytes
    ret nc
    ld de,(TITLE_AT+TL_LEN)
    ld hl,TITLE_AT+TL_DATA
    call read_long
    ret nc
    call CAS_IN_CLOSE
    ld hl,TITLE_AT+TL_DATA      ; (the firmware's screen is at #C000 after
    ld de,#C000                 ; SCR SET MODE)
    call unpack
    ld hl,TITLE_AT+TL_INKS
    xor a
sti_ink
    ld b,(hl)
    ld c,b
    push af
    push hl
    call SCR_SET_INK
    pop hl
    pop af
    inc hl
    inc a
    cp 16
    jr nz,sti_ink
    scf
    ret

title_wait
    ld a,(title_up)
    or a
    ret z
    call fire_wait
    xor a
    call SCR_SET_MODE
    jp text_inks

;; fire_wait - fire (either player) let go, then pressed. Destroys
;; everything.
fire_wait
    call tw_fire
    jr nz,fire_wait
fw_down
    call tw_fire
    jr z,fw_down
    ret

;; how_to - the controls and the moves, in Mode 1, while the fighters load.
;; Destroys everything.
how_to
    ld a,1
    call SCR_SET_MODE
    ld hl,ht_inks
    call set_inks
    ld hl,s_howto
    jp say

;; text_inks - the text screen's 4 inks. set_inks - HL = 4 inks: pens 0-3
;; those. Destroy everything.
text_inks
    ld hl,inks
set_inks
    xor a
ld_ink
    ld b,(hl)
    ld c,b
    push af
    push hl
    call SCR_SET_INK
    pop hl
    pop af
    inc hl
    inc a
    cp 4
    jr nz,ld_ink
    ret

;; tw_fire - NZ if either player holds fire. Destroys everything.
tw_fire
    call MC_WAIT_FLYBACK
    ld hl,keys_a
    call controls
    push af
    ld hl,keys_b
    call controls
    pop bc
    or b
    and 1<<PS_FIRE
    ret

;; unpack - HL = packed (tools/stage_pack.py), DE = where it goes. As in
;; src/main.asm. Destroys AF, BC, DE, HL.
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
    ld a,(hl)
    inc hl
    push hl
    ld h,(hl)
    ld l,a
    push de
    ex de,hl
    or a
    sbc hl,de
    pop de
    ldir
    pop hl
    inc hl
    jr unpack

;; ---------------------------------------------------------------------------
;; read_roster - roster: MAX_CHARS names of 8 characters (space padded),
;; n_chars of them. CY if the file was read.
;; ---------------------------------------------------------------------------
read_roster
    ld hl,f_roster
    ld b,f_roster_end-f_roster
    ld de,cas_buffer
    call CAS_IN_OPEN
    ret nc
    ld hl,roster                ; spaces everywhere
    ld de,roster+1
    ld bc,MAX_CHARS*8-1
    ld (hl),' '
    ldir
    ld hl,roster
    ld c,0                      ; characters on this line
rr_char
    call CAS_IN_CHAR
    jr nc,rr_end
    cp #1A                      ; soft end of file
    jr z,rr_end
    cp ' '+1                    ; end of a line (or a space)
    jr c,rr_eol
    ld b,a
    ld a,c
    cp 8
    jr nc,rr_char               ; names are 8 characters at most
    ld (hl),b
    inc hl
    inc c
    jr rr_char
rr_eol
    call rr_name
    jr rr_char
rr_end
    call rr_name
    call CAS_IN_CLOSE
    ld a,(n_chars)
    or a
    ret z                       ; NC: nobody on the disc
    scf
    ret
rr_name                         ; a line ends: a name if it had any
    ld a,c
    or a
    ret z
    ld a,(n_chars)
    cp MAX_CHARS
    ret nc
    inc a
    ld (n_chars),a
    ld c,0
rr_slot                         ; A = a character: HL = its name
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,roster
    add hl,de
    ret

;; read_headers - every character's header, into headers. CY if all read.
read_headers
    xor a
rh_one
    ld hl,n_chars
    cp (hl)
    scf
    ret z
    push af
    call open_char
    jr nc,rh_fail
    pop af
    push af
    call header_addr
    ld b,HDR_SIZE
    call read_bytes
    jr nc,rh_fail
    call CAS_IN_CLOSE
    pop af
    inc a
    jr rh_one
rh_fail
    pop af
    or a
    ret

;; load_stage - fighter B's character's home stage to STAGE_AT. CY if
;; loaded.
load_stage
    ld a,(sel_b)
    call header_addr
    ld de,H_STAGE
    add hl,de
    ld de,f_stg
    call open_file
    ret nc
    ld hl,STAGE_AT
    ld b,ST_HEADER
    call read_bytes
    ret nc
    ld de,(STAGE_AT+ST_LEN)
    ld hl,STAGE_AT+ST_HEADER
    call read_long
    ret nc
    call CAS_IN_CLOSE
    scf
    ret

;; open_char - A = character: open NAME.PFC. CY if opened.
;; open_file - HL = a name (8 characters, space padded), DE = its
;; extension (4 characters): open it. CY if opened.
open_char
    ld l,a                      ; its name, then ".PFC"
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,roster
    add hl,de
    ld de,f_ext
open_file
    push de
    ld de,f_name
    ld b,0
oc_char
    ld a,(hl)
    cp ' '
    jr z,oc_ext
    ld (de),a
    inc hl
    inc de
    inc b
    ld a,b
    cp 8
    jr nz,oc_char
oc_ext
    pop hl
    ld c,4
oc_ext_char
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    inc b
    dec c
    jr nz,oc_ext_char
    ld hl,f_name
    ld de,cas_buffer
    jp CAS_IN_OPEN

;; header_addr - A = character: HL = its header. Destroys AF, DE.
header_addr
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; * HDR_SIZE
    ld de,headers
    add hl,de
    ret

;; read_bytes - B bytes (0: 256) from the open file to HL. CY if all read.
;; read_long - the same for DE bytes. Destroy AF, BC, DE, HL.
;; AMSDOS reports every #1A byte as a soft end of file, even in a binary
;; file: that is a byte like any other here. Only the hard end (#0F) or an
;; error stops it.
read_bytes
    ld e,b
    ld d,0
    ld a,e
    or a
    jr nz,read_long
    inc d
read_long
    ld a,d
    or e
    scf
    ret z
    push de
    push hl
    call CAS_IN_CHAR
    pop hl
    pop de
    jr c,rl_byte
    cp #1A
    ret nz                      ; (NC)
rl_byte
    ld (hl),a
    inc hl
    dec de
    jr read_long

;; ---------------------------------------------------------------------------
;; load_char - A = character, D = RAM configuration of the bank 0 to load it
;; in (bank 1 is the next). CY if loaded. Destroys everything.
;; ---------------------------------------------------------------------------
load_char
    ld e,a
    push de
    call open_char
    pop de
    ret nc
    ld a,d
    ld (lc_ram),a
    ld hl,lc_header
    ld b,HDR_SIZE
    call read_bytes
    ret nc
    ld a,(lc_ram)               ; bank 0
    call page
    ld hl,#4000
    call unpack_bank
    ret nc
    ld a,(lc_ram)               ; bank 1
    inc a
    call page
    ld hl,#4000
    call unpack_bank
    ret nc
    ld bc,#7FC0
    out (c),c
    call CAS_IN_CLOSE
    scf
    ret

;; unpack_bank - the open file's next packed bank (tools/stage_pack.py)
;; to HL, unpacked as it is read: n < #7F: n + 1 bytes as they are;
;; n >= #80: n - #7D bytes from an offset word back (in the bank already
;; written); #7F: the end. CY if it all came. Destroys everything.
unpack_bank
    call get_byte
    ret nc
    cp #7F
    jr z,ub_end
    jr nc,ub_match
    ld e,a                      ; literal bytes
    ld d,0
    inc de
    call read_long
    ret nc
    jr unpack_bank
ub_match
    sub #7D
    ld c,a
    ld b,0
    call get_byte               ; the offset
    ret nc
    ld e,a
    call get_byte
    ret nc
    ld d,a
    push hl
    or a
    sbc hl,de                   ; where it comes from
    pop de
    ldir
    ex de,hl
    jr unpack_bank
ub_end
    scf
    ret

;; get_byte - A = the open file's next byte, CY if there was one (a #1A
;; counts, as in read_long). Destroys F.
get_byte
    push hl
    push de
    push bc
    call CAS_IN_CHAR
    pop bc
    pop de
    pop hl
    ret c
    cp #1A
    scf
    ret z
    or a
    ret

;; page - A = RAM configuration. Destroys BC.
page
    ld bc,#7F00
    out (c),a
    ret

;; remap_a - fighter A's frames (banks 4-5): own colours to pens 6-9.
remap_a
    ld a,#C4
    call page
    ld a,(DIR_MOVES_N)
    ld (rb_moves),a
    ld hl,DIR_MOVES
    ld (rb_move),hl
rb_move_next
    ld a,#C4
    call page
    ld hl,(rb_move)             ; the move: frames, records
    ld a,(hl)
    ld (rb_frames),a
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (rb_move),hl
    ld (rb_rec),de
rb_frame
    ld a,(rb_frames)
    or a
    jr z,rb_move_done
    dec a
    ld (rb_frames),a
    ld a,#C4
    call page
    ld hl,(rb_rec)              ; the record: bank, w, off, spans
    ld a,(hl)
    add a,#C4
    inc hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld hl,(rb_rec)
    ld bc,REC_SIZE
    add hl,bc
    ld (rb_rec),hl
    call page                   ; the frame's bank
    call remap_stream
    jr rb_frame
rb_move_done
    ld hl,rb_moves
    dec (hl)
    jr nz,rb_move_next
    ld bc,#7FC0
    out (c),c
    ret

;; remap_stream - DE = a span stream (top, lines padded, lines drawn, then
;; per line s, n and the escaped bytes) in the paged bank: every byte
;; through remap_tab. Destroys AF, BC, DE, HL.
remap_stream
    ex de,hl
    inc hl
    ld b,(hl)                   ; lines, padded
    inc hl
    inc hl
rs_line
    inc hl                      ; s
    ld c,(hl)                   ; n
    inc hl
    inc c
    jr rs_next
rs_byte
    ld a,(hl)
    or a
    jr nz,rs_map
    inc hl                      ; escaped: the byte follows its 0
    ld a,(hl)
rs_map
    ld e,a
    ld d,remap_tab>>8
    ld a,(de)
    ld (hl),a
    inc hl
rs_next
    dec c
    jr nz,rs_byte
    djnz rs_line
    ret

;; alt_inks - fighter B's directory gets its character's second colours.
alt_inks
    ld a,#C6
    call page
    ld hl,lc_header+H_ALT_INKS  ; (B's header, the last one read)
    ld de,DIR_INKS
    ld bc,4
    ldir
    ld bc,#7FC0
    out (c),c
    ret

;; ---------------------------------------------------------------------------
;; select - the menu, over SELECT.SCR (tools/title_art.py): player 1's and
;; player 2's characters, the opponent (a player, the computer or training:
;; player 2's row is then the dummy) and, for
;; the computer, its level, a row each. Up and down choose a row, left and
;; right change it, fire starts (either player's controls). The fighters
;; chosen stand above it in their own colours (FIGHTERS.BIN, in bank 4
;; meanwhile). Sets sel_a, sel_b, cpu_b. Destroys everything.
;; ---------------------------------------------------------------------------
select
    xor a
    call SCR_SET_MODE
    ld hl,f_select
    ld b,f_select_end-f_select
    call show_screen
    jp nc,disc_error
    xor a
    ld (sel_a),a
    ld (m_row),a
    ld (m_cpu),a
    inc a
    ld (m_level),a              ; medium
    ld a,(n_chars)              ; B starts on the second character
    cp 2
    ld a,0
    jr c,se_b
    inc a
se_b
    ld (sel_b),a
    call menu_keys              ; (what is held now isn't pressed)
se_show
    call show_menu
se_frame
    call MC_WAIT_FLYBACK
    call menu_keys
    or a
    jr z,se_frame
    bit PS_FIRE,a
    jp nz,se_go
    ld c,a
    ld b,3                      ; rows: 3, or 4 with the computer
    ld a,(m_cpu)
    dec a
    jr nz,se_rows
    inc b
se_rows
    ld hl,m_row
    bit PS_UP,c
    jr z,se_down
    ld a,(hl)
    or a
    jr nz,se_up
    ld a,b
se_up
    dec a
    ld (hl),a
    jr se_show
se_down
    bit PS_DOWN,c
    jr z,se_side
    ld a,(hl)
    inc a
    cp b
    jr c,se_row
    xor a
se_row
    ld (hl),a
    jr se_show
se_side
    ld a,c                      ; left or right: the row's value
    and 1<<PS_LEFT|1<<PS_RIGHT
    jr z,se_frame
    ld a,(hl)
    ld de,sel_a
    or a
    jr z,se_char
    ld de,sel_b
    dec a
    jr nz,se_opp
    ld a,(m_cpu)                ; (in training, the dummy)
    cp 2
    jp z,se_frame
    jr se_char
se_opp
    dec a
    jr nz,se_level
    ld a,(m_cpu)                ; the opponent: a player, the computer,
    bit PS_LEFT,c               ; training
    jr z,se_onext
    or a
    jr nz,se_oprev
    ld a,3
se_oprev
    dec a
    jr se_oset
se_onext
    inc a
    cp 3
    jr c,se_oset
    xor a
se_oset
    ld hl,m_cpu
    ld b,(hl)
    ld (hl),a
    cp 2                        ; training: fighter B is the dummy (the
    jr nz,se_onot               ; last character), player 2's own choice
    ld a,(sel_b)                ; kept aside until it ends
    ld (m_keep_b),a
    ld a,(n_chars)
    jr se_bset
se_onot
    ld a,b
    cp 2
    jp nz,se_show
    ld a,(m_keep_b)
se_bset
    ld (sel_b),a
    jp se_show
se_level
    ld a,(m_level)              ; the computer's level: 0-2
    bit PS_LEFT,c
    jr z,se_harder
    or a
    jp z,se_show
    dec a
    jr se_lset
se_harder
    cp 2
    jp z,se_show
    inc a
se_lset
    ld (m_level),a
    jp se_show
se_char
    ld a,(de)                   ; a character: round the roster
    bit PS_LEFT,c
    jr z,se_next
    or a
    jr nz,se_prev
    ld a,(n_chars)
se_prev
    dec a
    jr se_cset
se_next
    inc a
    ld hl,n_chars
    cp (hl)
    jr c,se_cset
    xor a
se_cset
    ld (de),a
    jp se_show
se_go
    ld a,(m_cpu)                ; cpu_b: the level + 1 for the computer,
    cp 1                        ; else 0
    ld a,0
    jr nz,se_cpu
    ld a,(m_level)
    inc a
se_cpu
    ld (cpu_b),a
    ret

;; menu_keys - A = the PS_ bits newly pressed on either player's controls.
;; Destroys everything.
menu_keys
    ld hl,keys_a
    call controls
    push af
    ld hl,keys_b
    call controls
    pop bc
    or b
    ld hl,ps_a                  ; pressed: held, and not held before
    ld c,(hl)
    ld (hl),a
    ld b,a
    ld a,c
    cpl
    and b
    ret

;; show_menu - the rows (the one chosen in yellow, with an arrow), the
;; fighters and their colours. Destroys everything.
show_menu
    xor a
    ld (m_i),a
    ld hl,s_rows
sm_row
    ld (m_lbl),hl
    ld a,(m_i)                  ; every other text row
    add a,a
    add a,MENU_ROW
    ld l,a
    ld h,1
    call TXT_SET_CURSOR
    ld a,(m_row)
    ld hl,m_i
    cp (hl)
    ld a,2                      ; white,
    ld b,' '
    jr nz,sm_pen
    ld a,15                     ; or yellow, with the arrow
    ld b,'>'
sm_pen
    push bc
    call TXT_SET_PEN
    pop bc
    ld a,b
    call TXT_OUTPUT
    ld a,' '
    call TXT_OUTPUT
    ld hl,(m_lbl)               ; the label,
    call say_str
    inc hl
    push hl
    call sm_value               ; then the value
    call say_n
    pop hl
    ld a,(m_i)
    inc a
    ld (m_i),a
    cp 3
    jr c,sm_row
    jr nz,sm_fighters
    ld a,(m_cpu)                ; the level's row only for the computer
    dec a
    jr z,sm_row
    ld hl,#0100+MENU_ROW+6
    call TXT_SET_CURSOR
    ld hl,s_blank
    call say_str
sm_fighters
    ld hl,s_start
    call say
    ld a,(sel_a)                ; fighter A: pens 6-9, its colours
    ld hl,FIGHTERS+FI_INKS
    ld c,6
    call sm_inks
    ld a,(sel_a)                ; fighter B: pens 10-13, the second set in
    ld hl,sel_b                 ; a mirror match
    cp (hl)
    ld hl,FIGHTERS+FI_INKS
    jr nz,sm_b
    ld hl,FIGHTERS+FI_ALT
sm_b
    ld a,(sel_b)
    ld c,10
    call sm_inks
    ld a,(sel_a)
    ld hl,FIGHTERS+FI_A
    ld de,#C000+FI_XA
    call sm_draw
    ld a,(sel_b)
    ld hl,FIGHTERS+FI_B
    ld de,#C000+FI_XB
    ; fall into sm_draw

;; sm_draw - A = character, HL = FIGHTERS + its frame's offset, DE =
;; #C000 + the bytes across: the frame there from line FI_Y down.
;; Destroys everything.
sm_draw
    push de
    call fi_addr
    pop de
    ld bc,#7FC4
    out (c),c
    ld c,FI_Y
    ld b,64
sd_line
    push bc
    push de
    ld a,c                      ; the line: 2K a line of a row,
    and 7
    add a,a
    add a,a
    add a,a
    add a,d
    ld d,a
    ld a,c                      ; 80 bytes a row
    rrca
    rrca
    rrca
    and 31
    push hl
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld b,h
    ld c,l
    add hl,hl
    add hl,hl
    add hl,bc
    add hl,de
    ex de,hl
    pop hl
    ld bc,16
    ldir
    pop de
    pop bc
    inc c
    djnz sd_line
    ld bc,#7FC0
    out (c),c
    ret

;; sm_value - HL = the value of row m_i, B = its length. Destroys AF, DE.
sm_value
    ld b,8
    ld a,(m_i)
    or a
    ld a,(sel_a)
    jr z,sv_name
    ld a,(m_i)
    dec a
    ld a,(sel_b)
    jr z,sv_name
    ld a,(m_i)
    cp 2
    ld hl,s_human
    ld a,(m_cpu)
    jr z,sv_pick
    ld b,6
    ld hl,s_easy
    ld a,(m_level)
sv_pick
    add a,a
    add a,a
    add a,a                     ; (8 characters each)
    ld e,a
    ld d,0
    add hl,de
    ret
sv_name
    call header_addr
    ld de,H_NAME
    add hl,de
    ret

;; sm_inks - A = character, HL = FIGHTERS + its colours' offset, C = the
;; first pen: 4 pens those colours. Destroys everything.
sm_inks
    push bc
    call fi_addr
    ld bc,#7FC4
    out (c),c
    ld de,m_inks
    ld bc,4
    ldir
    ld bc,#7FC0
    out (c),c
    pop bc
    ld hl,m_inks
    ld b,4
si_ink
    push bc
    push hl
    ld a,c
    ld b,(hl)
    ld c,b
    call SCR_SET_INK
    pop hl
    pop bc
    inc hl
    inc c
    djnz si_ink
    ret

;; fi_addr - A = character, HL = FIGHTERS + an offset in its record: HL
;; that byte of its record. Destroys AF, BC.
fi_addr
    or a
    ret z
    ld bc,FI_SIZE
fa_next
    add hl,bc
    dec a
    jr nz,fa_next
    ret

;; read_fighters - FIGHTERS.BIN into bank 4 (FIGHTERS). CY if read.
;; Destroys everything.
read_fighters
    ld hl,f_fighters
    ld b,f_fighters_end-f_fighters
    ld de,cas_buffer
    call CAS_IN_OPEN
    ret nc
    ld bc,#7FC4
    out (c),c
    ld hl,FIGHTERS
    ld a,(n_chars)
rf_char
    push af
    ld de,FI_SIZE
    call read_long              ; (HL ends past it)
    pop bc
    jr nc,rf_out
    ld a,b
    dec a
    jr nz,rf_char
    scf
rf_out
    push af
    ld bc,#7FC0
    out (c),c
    call CAS_IN_CLOSE
    pop af
    ret

;; controls - HL = a player's keys (left, right, fire, up, down: each a
;; list of key numbers ended by #FF): A = PS_ bits held. Destroys
;; everything.
controls
    ld c,0                      ; C = held
    ld b,1<<PS_LEFT             ; B = this list's bit
co_key
    ld a,(hl)
    inc hl
    cp #FF
    jr z,co_list
    push bc
    push hl
    call KM_TEST_KEY
    pop hl
    pop bc
    jr z,co_key
    ld a,c
    or b
    ld c,a
    jr co_key
co_list
    sla b
    ld a,b
    cp 1<<(PS_DOWN+1)
    jr nz,co_key
    ld a,c
    ret

;; say_n - B characters from HL. Destroys AF, B, HL.
say_n
    ld a,(hl)
    call TXT_OUTPUT
    inc hl
    djnz say_n
    ret

;; say - HL = a string: 0 ends it, 31 col row moves the cursor, 15 pen
;; changes the pen (the firmware's own control codes). Destroys AF, HL.
say
say_str
    ld a,(hl)
    or a
    ret z
    call TXT_OUTPUT
    inc hl
    jr say_str

;; ---------------------------------------------------------------------------
inks                            ; mode 0 pens 0-3: black, pastel blue,
    defb 0,14,24,26             ; bright yellow, bright white

;; Keys (firmware key numbers), left, right, fire, up, down, each list
;; ended by #FF.
keys_a                          ; cursor keys, Space, Copy, joystick 0
    defb 8,74,#FF, 1,75,#FF, 47,9,76,77,#FF, 0,72,#FF, 2,73,#FF
keys_b                          ; W A S D, Z, X, joystick 1
    defb 69,50,#FF, 61,51,#FF, 71,63,52,53,#FF, 59,48,#FF, 60,49,#FF

s_rows                          ; the menu's labels
    defb "PLAYER 1: ",0
    defb "PLAYER 2: ",0
    defb "OPPONENT: ",0
    defb "DIFFICULTY: ",0
s_dummy defb "DUMMY   "        ; the training dummy's file
s_human                         ; its values, 8 characters each
    defb "HUMAN   COMPUTERTRAINING"
s_easy
    defb "EASY    MEDIUM  HARD    "
s_blank
    defb "                    ",0
s_start
    defb 31,1,23,15,14,"FIRE/SPACE TO START ",0
s_loading
    defb 31,15,24,15,3,"LOADING...    ",0
s_fight
    defb 31,15,24,15,2,"FIRE TO FIGHT!",0
ht_inks                         ; Mode 1: black, white, yellow, pastel blue
    defb 0,26,24,14
s_howto                         ; (31 column row: the cursor; 15 pen)
    defb 31,14,1,15,2,"HOW TO FIGHT"
    defb 31,12,3,15,3,"PLAYER 1",31,28,3,"PLAYER 2"
    defb 31,1,4,15,1,"MOVE",31,12,4,"CURSORS/JOY 1",31,28,4,"W A S D/JOY 2"
    defb 31,1,5,"PUNCH",31,12,5,"SPACE/FIRE 1",31,28,5,"Z/FIRE 1"
    defb 31,1,6,"KICK",31,12,6,"COPY/FIRE 2",31,28,6,"X/FIRE 2"
    defb 31,16,8,15,2,"THE MOVES"
    defb 31,5,9,15,3,"FORWARD: TOWARDS THE OPPONENT"
    defb 31,1,11,15,1,"JUMP",31,16,11,"UP (+ FORWARD/BACK)"
    defb 31,1,12,"CROUCH",31,16,12,"DOWN"
    defb 31,1,13,"BLOCK",31,16,13,"HOLD BACK"
    defb 31,1,14,"PUNCH, KICK",31,16,14,"PUNCH, KICK"
    defb 31,1,15,"BACK KICK",31,16,15,"BACK + KICK"
    defb 31,1,16,"SWEEP",31,16,16,"DOWN + KICK"
    defb 31,1,17,"UPPERCUT",31,16,17,"DOWN + PUNCH"
    defb 31,1,18,15,2,"SPECIAL",31,16,18,"DOWN, DOWN-FORWARD,"
    defb 31,16,19,"FORWARD + PUNCH/KICK"
    defb 31,1,20,15,1,"ESCAPE A THROW",31,16,20,"BACK AS IT GRABS"
    defb 31,1,22,15,3,"2 ROUNDS WIN A MATCH, 99 SECONDS EACH.",0
s_error
    defb 31,1,23,15,14,"DISC ERROR          ",0

f_roster
    defb "ROSTER.TXT"
f_roster_end
f_ext
    defb ".PFC"
f_stg
    defb ".STG"
f_title
    defb "TITLE.SCR"
f_title_end
f_select
    defb "SELECT.SCR"
f_select_end
f_fighters
    defb "FIGHTERS.BIN"
f_fighters_end

    include "gen/remap.asm"     ; page aligned

loader_end
;; Not in the file.
n_chars         EQU loader_end
sel_a           EQU n_chars+1
sel_b           EQU sel_a+1
m_row           EQU sel_b+1     ; the menu: the row chosen, the opponent
m_cpu           EQU m_row+1     ; (1: the computer, 2: training) and its
                                ; level (0-2)
m_level         EQU m_cpu+1
m_i             EQU m_level+1   ; show_menu: the row it is on, its label,
m_lbl           EQU m_i+1       ; the 4 colours it sets
m_inks          EQU m_lbl+2
ps_a            EQU m_inks+4    ; the controls held last frame
title_up        EQU ps_a+1
cpu_b           EQU title_up+1  ; 0 a player, 1-3 the computer's level + 1
m_keep_b        EQU cpu_b+1     ; player 2's character during training
lc_ram          EQU m_keep_b+1
rb_moves        EQU lc_ram+1
rb_frames       EQU rb_moves+1
rb_move         EQU rb_frames+1
rb_rec          EQU rb_move+2
f_name          EQU rb_rec+2    ; NAME.PFC
roster          EQU f_name+12
lc_header       EQU roster+MAX_CHARS*8
headers         EQU lc_header+HDR_SIZE
cas_buffer      EQU #9000       ; 2K for the firmware's file reading
    ASSERT headers+MAX_CHARS*HDR_SIZE<=cas_buffer

    SAVE '../build/PFLOAD.BIN',loader,loader_end-loader
