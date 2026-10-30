;; ===========================================================================
;; traingo.asm - into training's own code (train.asm), in fighter B's bank:
;; out of the mirror's gaps, which the bank hides. It comes back through
;; page_main. Low, under the interrupt jump (bannercel.asm).
;; ===========================================================================

train_go
    ld bc,#7F00+TRAIN_RAM
    out (c),c
    jp TRAIN_AT
