.setcpu "6502"
.segment "CODE"

.include "ppu.inc"
.include "boot.inc"

;; CPU setup
reset:
    INITIALIZE_NES

;; Render pink background

    ; Reset PPU latch and set PPU RAM address
    lda PPUSTATUS
    SET_PPUADDR $3f00

    ; Write color to PPUDATA, which writes to $3f00
    lda #$25
    sta PPUDATA

    ; Enable background rendering
    SET_PPUMASK #%00001000

; Try to render a single sprite

    ; Set up the sprite palette
    lda PPUSTATUS
    SET_PPUADDR $3410

    lda #$1d
    sta PPUDATA
    lda #$30
    sta PPUDATA
    lda #$27
    sta PPUDATA
    lda #$16
    sta PPUDATA

    ; approx position (124, 116)
    lda #116    ; Y
    sta $0200
    lda #0      ; tile 0
    sta $0201
    lda #0      ; palette 0, no flip, to front
    sta $0202
    lda #124    ; X
    sta $0203

    ; DMA to OAM
    lda #$00
    sta OAMADDR
    lda #$02
    sta $4014   ; OAMDMA
    
    ; enable sprites
    SET_PPUMASK #%00010000

;; Main loop

main:
    jmp main


; Interrupts (return to program)

nmi:
    rti

irq:
    rti


; Vector interrupt table
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
