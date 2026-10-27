;; ===========================================================================
;; loader.asm - the select screen and the character loader (PFLOAD.BIN).
;;
;; Runs under the firmware, before the engine takes the machine over:
;; PF.BAS loads it at #8000 and calls it, then loads and starts the engine.
;;
;; ROSTER.TXT lists the characters on the disc, one name a line, and each
;; NAME.PFC holds one (tools/sprite_codegen.py pfc): a header with its name,
;; title and colours, then its two banks. The select screen shows the names
;; and titles from the headers. Each player picks one with left and right
;; and fire, the same character twice too. Then fighter A's goes into banks
;; 4-5 and fighter B's into banks 6-7, read a byte at a time so it can be
;; paged in a bank at a time. Fighter B's frames then have their own colours
;; moved from pens 6-9 to 10-13 (remap_tab), and in a mirror match its
;; directory gets the character's second set of colours. Last, fighter B's
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
H_LEN0          EQU 44
H_LEN1          EQU 46
H_STAGE         EQU 48
STAGE_AT        EQU #2000       ; src/config.asm
ST_LEN          EQU 6           ; a stage file: header, packed length
ST_HEADER       EQU 8
DIR_MOVES_N     EQU #4003       ; in bank 0 (src/main.asm DIR_*)
DIR_INKS        EQU #4007
DIR_MOVES       EQU #400E
REC_SIZE        EQU 16

PS_LEFT         EQU 0           ; a player's controls this frame
PS_RIGHT        EQU 1
PS_FIRE         EQU 2

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
    ld hl,inks
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

    call read_roster
    jp nc,disc_error
    call read_headers
    jp nc,disc_error
    call select

    ld hl,s_loading
    call say
    ld a,(sel_a)                ; fighter A: banks 4-5 as it is
    ld d,#C4
    call load_char
    jp nc,disc_error
    ld a,(sel_b)                ; fighter B: banks 6-7, own colours moved
    ld d,#C6
    call load_char
    jp nc,disc_error
    call remap_b
    ld a,(sel_a)                ; a mirror match: B in the second colours
    ld hl,sel_b
    cp (hl)
    call z,alt_inks
    ld bc,#7FC0
    out (c),c
    call load_stage
    jp nc,disc_error
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
    ld l,a                      ; HL = the next name
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,roster
    add hl,de
    ld c,0
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
    ld de,(lc_header+H_LEN0)
    call read_long
    ret nc
    ld a,(lc_ram)               ; bank 1
    inc a
    call page
    ld hl,#4000
    ld de,(lc_header+H_LEN1)
    call read_long
    ret nc
    ld bc,#7FC0
    out (c),c
    call CAS_IN_CLOSE
    scf
    ret

;; page - A = RAM configuration. Destroys BC.
page
    ld bc,#7F00
    out (c),a
    ret

;; remap_b - fighter B's frames (banks 6-7): own colours to pens 10-13.
remap_b
    ld a,#C6
    call page
    ld a,(DIR_MOVES_N)
    ld (rb_moves),a
    ld hl,DIR_MOVES
    ld (rb_move),hl
rb_move_next
    ld a,#C6
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
    ld a,#C6
    call page
    ld hl,(rb_rec)              ; the record: bank, w, off, spans
    ld a,(hl)
    add a,#C6
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
;; select - both players choose: sel_a, sel_b.
;; ---------------------------------------------------------------------------
select
    ld hl,s_screen
    call say
    xor a
    ld (sel_a),a
    ld (rdy_a),a
    ld (rdy_b),a
    ld a,(n_chars)              ; B starts on the second character
    cp 2
    ld a,0
    jr c,se_b
    inc a
se_b
    ld (sel_b),a
    call show_a
    call show_b
se_frame
    call MC_WAIT_FLYBACK
    ld hl,keys_a
    call controls
    ld hl,ps_a
    ld de,sel_a
    ld bc,rdy_a
    call choose
    call c,show_a
    ld hl,keys_b
    call controls
    ld hl,ps_b
    ld de,sel_b
    ld bc,rdy_b
    call choose
    call c,show_b
    ld a,(rdy_a)
    ld hl,rdy_b
    and (hl)
    jr z,se_frame
    ld b,25                     ; both ready: half a second to see it
se_wait
    push bc
    call MC_WAIT_FLYBACK
    pop bc
    djnz se_wait
    ret

;; controls - HL = a player's keys (left, right, fire: each a list of key
;; numbers ended by #FF): A = PS_ bits held. Destroys everything.
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
    cp 1<<(PS_FIRE+1)
    jr nz,co_key
    ld a,c
    ret

;; choose - A = held, HL = last frame's held, DE = selection, BC = ready:
;; a newly pushed left or right changes the character, fire makes the
;; player ready (and fire again changes its mind). CY if anything changed.
choose
    ld (ch_ready),bc
    ld c,(hl)                   ; pressed = held and not held before
    ld (hl),a
    ld b,a
    ld a,c
    cpl
    and b
    ret z                       ; (NC)
    ld b,a
    ld hl,(ch_ready)
    bit PS_FIRE,b
    jr z,ch_move
    ld a,(hl)
    xor 1
    ld (hl),a
    scf
    ret
ch_move
    ld a,(hl)                   ; ready: the choice stays
    or a
    ret nz
    ld a,(de)
    bit PS_LEFT,b
    jr z,ch_right
    or a
    jr nz,ch_left
    ld a,(n_chars)
ch_left
    dec a
    jr ch_set
ch_right
    inc a
    ld hl,n_chars
    cp (hl)
    jr c,ch_set
    xor a
ch_set
    ld (de),a
    scf
    ret

;; show_a, show_b - a player's choice: name, title, ready or not.
show_a
    ld a,(sel_a)
    ld hl,#0108                 ; column 1, row 8
    ld bc,(rdy_a)
    jr show
show_b
    ld a,(sel_b)
    ld hl,#0110                 ; column 1, row 16
    ld bc,(rdy_b)
show
    push bc
    push hl
    call header_addr
    ex de,hl                    ; DE = header
    pop hl
    push hl
    push de
    call TXT_SET_CURSOR
    ld a,2
    call TXT_SET_PEN
    ld a,'<'
    call TXT_OUTPUT
    ld a,' '
    call TXT_OUTPUT
    pop hl
    push hl
    ld bc,H_NAME
    add hl,bc
    ld b,8
    call say_n
    ld a,' '
    call TXT_OUTPUT
    ld a,'>'
    call TXT_OUTPUT
    pop de
    pop hl
    push hl
    push de
    inc l
    call TXT_SET_CURSOR         ; the title on two lines of 12
    ld a,1
    call TXT_SET_PEN
    pop hl
    push hl
    ld bc,H_TITLE
    add hl,bc
    ld b,12
    call say_n
    pop de
    pop hl
    push hl
    push de
    inc l
    inc l
    call TXT_SET_CURSOR
    pop hl
    ld bc,H_TITLE+12
    add hl,bc
    ld b,12
    call say_n
    pop hl
    inc l
    inc l
    inc l
    inc l
    call TXT_SET_CURSOR
    ld a,3
    call TXT_SET_PEN
    pop bc
    ld hl,s_ready
    ld a,c
    or a
    jr nz,say_str
    ld hl,s_blank
    jr say_str

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

;; Keys (firmware key numbers), left, right, fire, each list ended by #FF.
keys_a                          ; cursor keys, Space, Copy, joystick 0
    defb 8,74,#FF, 1,75,#FF, 47,9,76,77,#FF
keys_b                          ; A, D, Z, X, joystick 1
    defb 69,50,#FF, 61,51,#FF, 71,63,52,53,#FF

s_screen
    defb 31,3,2,15,2,"PUPPET FIGHT"
    defb 31,1,6,15,3,"PLAYER 1"
    defb 31,1,14,15,3,"PLAYER 2"
    defb 31,1,23,15,1,"< > CHOOSE"
    defb 31,1,24,"FIRE: READY",0
s_ready
    defb "READY!",0
s_blank
    defb "      ",0
s_loading
    defb 31,1,21,15,2,"LOADING...",0
s_error
    defb 31,1,21,15,2,"DISC ERROR",0

f_roster
    defb "ROSTER.TXT"
f_roster_end
f_ext
    defb ".PFC"
f_stg
    defb ".STG"

    include "gen/remap.asm"     ; page aligned

loader_end
;; Not in the file.
n_chars         EQU loader_end
sel_a           EQU n_chars+1
sel_b           EQU sel_a+1
rdy_a           EQU sel_b+1     ; (a word apart from rdy_b: show reads BC)
rdy_b           EQU rdy_a+2
ps_a            EQU rdy_b+2
ps_b            EQU ps_a+1
ch_ready        EQU ps_b+1
lc_ram          EQU ch_ready+2
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
