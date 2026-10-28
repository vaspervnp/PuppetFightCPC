;; ===========================================================================
;; fill.asm - draw_hud, at the start. In a gap of the background mirror
;; (GAP6_ORG).
;; ===========================================================================

;; draw_hud - the health bars, full, on the stage boot unpacked (its lines
;; 0-23 are the HUD's black). Destroys everything.
draw_hud
    ld de,BAR_LINE              ; fighter A's, in its first colour
    ld hl,4+40*256
    ld bc,8*256+PB_6_6
    call hud_rect
    ld de,BAR_LINE              ; fighter B's
    ld hl,52+40*256
    ld bc,8*256+PB_10_10
    jp hud_rect
