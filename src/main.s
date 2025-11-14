.include "ppu.inc"
.include "boot.inc"

.importzp buttons
.import read_joypad1

; Sprite positions
.segment "ZEROPAGE"
    frame: .res 1
    pos_x: .res 1
    pos_y: .res 1
    bstate: .res 1


.setcpu "6502"
.segment "CODE"

; Parabolic bounce lookup
bounce_table:
    .byte <-6, <-5, <-5, <-5, <-5, <-5, <-5, <-4, <-4, <-4, <-4, <-4, <-3, <-3, <-3, <-3, <-3, <-2, <-2, <-2, <-2, <-2, <-1, <-1, <-1, <-1, <-1, <0, <0, <0, <0, <0, <0, <1, <1, <1, <1, <1, <2, <2, <2, <2, <2, <3, <3, <3, <3, <3, <4, <4, <4, <4, <4, <5, <5, <5, <5, <5, <5, <6
bounce_table_end:

BOUNCE_PERIOD = bounce_table_end - bounce_table


reset:
    INITIALIZE_NES

    ;; Render background background

    ; Reset PPU latch
    lda PPUSTATUS

    ; Set the universal background color
    SET_PPUADDR BG_PALETTE
    lda #$0f
    sta PPUDATA

    ; Enable background rendering
    SET_PPUMASK #%00001000

    ;; Render a single sprite

    ; Set up the sprite palette
    lda PPUSTATUS
    SET_PPUADDR SPRITE_PALETTE+1

    ; NOTE: $3f10 is wired to $3f00
    lda #$0c
    sta PPUDATA
    lda #$21
    sta PPUDATA
    lda #$32
    sta PPUDATA

    ; enable background and sprites
    SET_PPUMASK #%00010000


    ;; Setup the Object Attribute Memory (OAM) buffer

    ; Y position
    lda #160
    sta $0200
    sta pos_y

    ; Tile 0
    lda #4
    sta $0201

    ; Palette 0, disable flip, move to front
    lda #0
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


    ;; System setup

    ; Re-enable NMI
    lda #%10000000
    sta PPUCTRL

    ; The NMI now runs when bit7 of PPUSTATUS is set.

    ; Now that NMI is enabled, do not check PPUSTATUS, and do not use
    ; WAIT_FOR_VBLANK.  It will unset bit7 and cause the NMI skipping.

    ; Initialize frame flag
    lda #$00
    sta frame

    ; Lookup table counter
    lda #0
    sta bstate


main:
    ;; Wait for vblank NMI to complete (defined below)
@wait:
    lda frame
    beq @wait

    ; Unset the frame draw flag
    lda #0
    sta frame


    ;; Animate bounce

    ; update position
    ldx bstate
    lda bounce_table, x
    clc
    adc pos_y
    sta pos_y

    ; Update lookup index
    ; TODO: Fast power-of-two check?  Could set frames to 32 or 64
    inc bstate
    lda bstate
    cmp #BOUNCE_PERIOD
    bne @skip_reset
    lda #0
    sta bstate
@skip_reset:

    ;; Update controller

    ; Read controller
    jsr read_joypad1

    ; Check Right
    lda buttons
    and #%00000001    ; Right
    beq @skip_right
    inc pos_x
@skip_right:

    ; Check Left
    lda buttons
    and #%00000010    ; Left
    ; If nonzero, decrement pos_x.  Else skip ahead to next label.
    beq @skip_left
    dec pos_x
@skip_left:

    ; Update positions in OAM buffer
    lda pos_y
    sta $0200
    lda pos_x
    sta $0203

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
