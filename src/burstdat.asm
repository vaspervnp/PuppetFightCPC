;; ===========================================================================
;; burstdat.asm - the bursts' tables (burst.asm). In a gap of the background
;; mirror (GAP1_ORG), read while the pass has main RAM in.
;; ===========================================================================

;; Per line of a burst: the bytes left out on the left (high nibble) and on
;; the right, at most BURST_W - 3 in all; its word's lines (BURST_TEXT on,
;; 10 of them) leave its 8 bytes in the middle and an edge byte each side.
burst_shape
    defb #29,#28,#37,#36,#35,#34,#23
    defb #22,#22,#12,#02,#12,#21,#21
    defb #22,#21,#21,#20,#21,#11,#22
    defb #22,#33,#53,#82,#92,#92,#92
    ASSERT $-burst_shape==BURST_H
;; The words, 4 characters each, picked by the picture count (burst_hit).
burst_words
    defb "POW!BAM!ZAP!WHAMBIFFSOK!BOP!OOF!"
