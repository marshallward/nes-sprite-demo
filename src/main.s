.include "ppu.inc"
.include "boot.inc"

.importzp buttons
.import read_joypad1

; Sprite positions
.segment "ZEROPAGE"
    frame: .res 1
    pos_x: .res 1
    pos_y: .res 1
    pos_y_lo: .res 1
    vel_y_hi: .res 1
    vel_y_lo: .res 1
    acc_y_hi: .res 1
    acc_y_lo: .res 1


; Jump parameters (positive is downward)
VEL_JUMP_LO = 0
VEL_JUMP_HI = <-5
G_UP_PRESS = 1
G_UP_RELEASE = 0
G_DOWN_MAX = 32

.setcpu "6502"
.segment "CODE"


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
    lda #0
    sta frame

    ; Initialize kinematic state
    lda #0
    sta vel_y_hi
    sta vel_y_lo
    sta acc_y_hi
    sta acc_y_lo

main:
    ;; Wait for vblank NMI to complete (defined below)
@wait:
    lda frame
    beq @wait

    ; Unset the frame draw flag
    lda #0
    sta frame


    ;; Update controller

    ; Read controller
    jsr read_joypad1

    ; Check Right
    lda buttons
    and #%00000001
    beq @skip_right
    inc pos_x
    inc pos_x
@skip_right:

    ; Check Left
    lda buttons
    and #%00000010
    beq @skip_left
    dec pos_x
    dec pos_x
@skip_left:

    ; Check jump
    lda buttons
    and #%01000000
    beq @skip_btn_b
    ; Don't apply if already jumping
    ; TODO: This is a bad check!
    lda pos_y
    cmp #160
    bcc @skip_btn_b
    ; Apply the "impulse" velocity
    lda #VEL_JUMP_LO
    sta vel_y_lo
    lda #VEL_JUMP_HI
    sta vel_y_hi
@skip_btn_b:


    ;; Apply acceleration
    ; Fetch velocity
    ; TODO: Check lo+hi
    lda vel_y_hi
    bmi @jump_up
;@jump_down:
    lda #60
    sta acc_y_lo
    jmp @apply_accel
@jump_up:
    lda #30
    sta acc_y_lo
@apply_accel:
    ;lda #G_DOWN_MAX
    ;sta acc_y_lo

    ; Update velocity
    lda vel_y_lo
    clc
    adc acc_y_lo
    sta vel_y_lo
    ; Keep the carry bit this time
    lda vel_y_hi
    adc acc_y_hi
    sta vel_y_hi

    ; Update position
    lda pos_y_lo
    clc
    adc vel_y_lo
    sta pos_y_lo
    lda pos_y
    adc vel_y_hi
    sta pos_y

    ; Stop if pos_y is below ground
    lda pos_y   ; TODO: remove this and the previous sta pos_y
    cmp #160    ; C = pos_y <= 160
    bcc @skip_ground
    ; We've hit (or passed) the ground, so stop here.
    lda #160
    sta pos_y
    lda #0
    sta vel_y_lo
    sta vel_y_hi
    sta acc_y_lo
    sta acc_y_hi
@skip_ground:

    ;; Transfer positions to OAM buffer
    lda pos_y
    sta $0200
    lda pos_x
    sta $0203

    ;; Reset game loop
    jmp main


; Interrupts (return to program)

nmi:
    ; Update sprite position with DMA
    lda #$00
    sta OAMADDR
    lda #$02
    sta OAMDMA

    ; Set the frame drawn flag
    lda #$01
    sta frame

    rti

irq:
    rti


; Vector interrupt table
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
