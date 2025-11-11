.include "ppu.inc"
.include "boot.inc"

.importzp buttons
.import read_joypad1

; Sprite positions
.segment "ZEROPAGE"
    frame: .res 1
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
    lda #$2c
    sta PPUDATA

    ; Enable background rendering
    SET_PPUMASK #%00001000

    ; Render a single sprite

    ; Set up the sprite palette
    lda PPUSTATUS
    SET_PPUADDR $3410

    lda #$21
    sta PPUDATA
    lda #$23
    sta PPUDATA
    lda #$25
    sta PPUDATA
    lda #$27
    sta PPUDATA


    ; Setup the Object Attribute Memory (OAM) buffer

    ; Y position
    lda #116
    sta $0200
    sta pos_y

    ; Tile 0, Palette 0, disable flip, move to front
    lda #0
    sta $0201
    sta $0202

    ; X position
    lda #124
    sta $0203
    sta pos_x


    ; Trigger DMA (direct memory addressing) to OAM (object attribute memory)
    lda #$00
    sta OAMADDR
    lda #$02
    sta OAMDMA

    ; Re-enable NMI
    lda #%10000000
    sta $2000

    ; The NMI now runs when bit7 of PPUSTATUS is set.

    ; Now that NMI is enabled, do not check PPUSTATUS, and do not use
    ; WAIT_FOR_VBLANK.  It will unset bit7 and cause the NMI skipping.

    ; enable sprites
    SET_PPUMASK #%00010000

main:
    ; Wait for vblank NMI to complete (defined below)
@wait:
    lda frame
    beq @wait
    ; Unset the frame draw flag
    lda #0
    sta frame

    ; Read controller
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

    ; Update positions in OAM buffer
    lda pos_y
    sta $0200
    lda pos_x
    sta $0203
;:
;;; end cut and paste!

    ; Wait for NMI
    ;WAIT_FOR_VBLANK

    jmp main


; Interrupts (return to program)

nmi:
    ; Update sprite position with DMA
    lda #$00
    sta OAMADDR
    lda #$02
    sta OAMDMA
    lda #$01

    ; Set the frame drawn flag
    sta frame

    rti

irq:
    rti


; Vector interrupt table
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
