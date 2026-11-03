;; ===========================================================================
;; traingo.asm - into fighter B's bank: A = 0, training's own code
;; (train.asm), else ESC's question (exit.asm). Out of the mirror's gaps,
;; which the bank hides; it comes back through page_main. Low, under the
;; interrupt jump (bannercel.asm).
;; ===========================================================================

train_go
    ld bc,#7F00+TRAIN_RAM
    out (c),c
    jp EXIT_AT
