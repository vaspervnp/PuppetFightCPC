;; ===========================================================================
;; wallx.asm - set_x_wide, in low RAM after bannerlow.asm (LOW_ORG).
;; ===========================================================================

;; set_x_wide - set_x for a fighter knocked back or thrown: X_WIDE bytes
;; clear of the walls, so that its wide frames (a fall, X_WIDE bytes out on
;; each side) don't wrap round the screen. Destroys AF.
set_x_wide
    sub X_WIDE                  ; (below the wall, or wrapped: 128 and up)
    cp X_MAX-2*X_WIDE+1
    jr c,sw_in
    rla
    sbc a,a                     ; past a wall: the nearer end
    cpl
    and X_MAX-2*X_WIDE
sw_in
    add a,X_WIDE
    jp set_x
