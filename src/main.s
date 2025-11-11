.include "ppu.inc"
.include "boot.inc"

.importzp buttons
.import read_joypad1

; Sprite positions
.segment "ZEROPAGE"
    pos_x: .res 1
    pos_y: .res 1


.setcpu "6502"
.segment "CODE"

reset:
    INITIALIZE_NES

    ;; Render pink background

    ; Reset PPU latch and set PPU RAM address
    lda PPUSTATUS
    SET_PPUADDR $3f00

    ; Write color to PPUDATA, which writes to $3f00
    lda #$18
    sta PPUDATA

    ; Enable background rendering
    SET_PPUMASK #%00001000

    ; Render a single sprite

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
    sta pos_y
    lda #0      ; tile 0
    sta $0201
    lda #0      ; palette 0, no flip, to front
    sta $0202
    lda #124    ; X
    sta $0203
    sta pos_x

    ; DMA to OAM
    lda #$00
    sta OAMADDR
    lda #$02
    sta $4014   ; OAMDMA

    ; Re-enable NMI
    lda #%10000000
    sta $2000

    ; enable sprites
    SET_PPUMASK #%00010000

main:
    jsr read_joypad1

;;; cut and paste!

    lda buttons
    and #%00000010    ; Left
    beq :+
    dec pos_x
:   lda buttons
    and #%00000001    ; Right
    beq :+
    inc pos_x
:
    ; up/down
    lda buttons
    and #%00000100    ; Down
    beq :+
    inc pos_y
:   lda buttons
    and #%00001000    ; Up
    beq :+
    dec pos_y
:
    ; write updated X/Y into OAM buffer
    lda pos_y
    sta $0200
    lda pos_x
    sta $0203
:
;;; end cut and paste!

    ; Wait for NMI
    WAIT_FOR_VBLANK

    jmp main


; Interrupts (return to program)

nmi:
    ; Trigger DMA transfer during vblank
    lda #$00
    sta OAMADDR
    lda #$02
    sta $4014   ; OAMDMA

    rti

irq:
    rti


; Vector interrupt table
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
