;; ===========================================================================
;; bannerset.asm - the banner's words set (banner.asm). Cold code
;; (COLD_ORG).
;; ===========================================================================

;; banner_begin - a round starts (clock_reset): BEGIN FIGHT. banner_set -
;; A = the words, B = pictures. Destroy AF, HL.
banner_begin
    ld a,BN_BEGIN
    ld b,BN_BEGIN_PICS
banner_set
    ld hl,BN_TEXT
    ld (hl),a
    inc hl
    ld (hl),b
    ld hl,BN_FLAGS
    set 1,(hl)
    xor a                       ; (none of its letters drawn)
    ld (BN_DONE),a
    ret
