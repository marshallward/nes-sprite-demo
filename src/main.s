.include "ppu.inc"
.include "boot.inc"

.importzp buttons
.import read_joypad1


; TODO: This should be in a separate file!
background_table:
    ; blank
    .repeat 32*21
        .byte 0
    .endrepeat

    ; Ground
    .repeat 32*1
        .byte 5
    .endrepeat

    ; More blank
    .repeat 32*8
        .byte 0
    .endrepeat


; Sprite positions
.segment "ZEROPAGE"
    frame: .res 1
    pos_x: .res 1
    ; 8.8 pixel resolution
    pos_y: .res 2
    vel_y: .res 2
    acc_y: .res 2

    ; Set during jump, disables jump start until landing.
    jump_latch: .res 1

    ; bg table pointer
    bg_ptr_lo: .res 1
    bg_ptr_hi: .res 1


; Jump parameters (positive is downward)
VEL_JUMP_LO = 128
VEL_JUMP_HI = <-4
G_UP = 60
G_PRESS = 15
G_DOWN = 60

.setcpu "6502"
.segment "CODE"


reset:
    INITIALIZE_NES

    ;; Render background background

    ; Reset PPU latch
    lda PPUSTATUS

    ; Set the BG palette
    SET_PPUADDR BG_PALETTE
    lda #$0f
    sta PPUDATA
    lda #$0c
    sta PPUDATA
    lda #$21
    sta PPUDATA
    lda #$32
    sta PPUDATA

    ;; Create a simple background nametable
    ;; TODO: Move to file!!
    SET_PPUADDR $2000

    ; Set up pointer
    lda #<background_table
    sta bg_ptr_lo
    lda #>background_table
    sta bg_ptr_hi

    ldx #30
bg_row_loop:
    ldy #0
bg_col_loop:
    lda (bg_ptr_lo),y
    sta PPUDATA
    iny
    cpy #32
    bne bg_col_loop

    ; advance pointer to next row
    clc
    lda bg_ptr_lo
    adc #32
    sta bg_ptr_lo
    bcc :+
    inc bg_ptr_hi
:
    dex
    bne bg_row_loop

    ; Set nametable attributes
    ldx #64
bg_attr_loop:
    lda #0
    sta PPUDATA
    dex
    bne bg_attr_loop


    ;; Render a single sprite

    ; Set up the sprite palette
    ; NOTE: The first color is unused
    SET_PPUADDR SPRITE_PALETTE+1

    lda #$0c
    sta PPUDATA
    lda #$21
    sta PPUDATA
    lda #$32
    sta PPUDATA

    ;; Setup the Object Attribute Memory (OAM) buffer

    ; Y position
    lda #0
    sta pos_y
    lda #160
    sta $0200
    sta pos_y+1

    ; Tile 4
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

    ; Re-enable NMI, use nametable 0
    lda #%10000000
    sta PPUCTRL

    ; The NMI now runs when bit7 of PPUSTATUS is set.

    ; Now that NMI is enabled, do not check PPUSTATUS, and do not use
    ; WAIT_FOR_VBLANK.  It will unset bit7 and cause the NMI skipping.

    ; Set scroll (?)
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL

    ; enable background and sprites
    SET_PPUMASK #%00011000


    ;; Jump setup

    ; Initialize frame flag
    lda #0
    sta frame

    ; Initialize kinematic state
    lda #0
    sta vel_y
    sta vel_y+1
    sta acc_y
    sta acc_y+1

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

    ;; Jump kinematics

    ; We only start a new jump if the last jump has completed.
    ;
    ; The conditions for completion are
    ; 1. We have reached the ground (y <= GROUND)
    ;   (TODO: ground collision detection)
    ; 2. The button has been released (buttons && $40 = 0)
    ;
    ; We then release the latch.
    ; So many conditions, lets just gather them:
    ;   - button (i.e. B is pressed)
    ;   - y > GROUND
    ;   - v > 0
    ;       - are we moving up or down?
    ;       - v = 0 is a concern: ground? top of parabola?
    ;   - latch is set

    ; Version 1: outer button test
    ;
    ; Button?
    ;   latch?
    ;     v > 0?
    ;       g = g_press
    ;     else
    ;       g = g_down
    ;   else
    ;     v = v0
    ; else
    ;   y > 0?
    ;     latch = 0
    ;   else
    ;     v > 0?
    ;       g = g_up
    ;     else
    ;       g = g_down


    ; Version 2: v > 0 outer
    ;
    ; v > 0? (up)
    ;   button?
    ;     g = g_press
    ;   else
    ;     g = g_up
    ; else
    ;   latch?
    ;     g = g_down
    ;   else
    ;     button and y = GROUND?
    ;       v = v0
    ;       latch = 1

    ;; Jump mechanics

    ;; Apply impulse velocity and compute acceleration

    ; Is velocity upward?
    lda vel_y+1
    bpl @jump_down      ; minus is up!
;@jump_up
    lda buttons
    and #%01000000
    beq @vel_up_release
;@vel_up_press:
    lda #G_PRESS
    sta acc_y
    jmp @jump_end
@vel_up_release:
    lda #G_UP
    sta acc_y
    jmp @jump_end

@jump_down:
    lda #G_DOWN
    sta acc_y

;@jump_start:
    ; Do not apply impulse if latch is set
    lda jump_latch
    bne @jump_end

    lda buttons
    and #%01000000
    beq @jump_end
    lda pos_y+1
    cmp #160    ; C = pos_y <= 160
    bcc @jump_end   ; skip if C > 0 ; we are still falling
    ; We're on the ground
    lda #VEL_JUMP_LO
    sta vel_y
    lda #VEL_JUMP_HI
    sta vel_y+1
    ; set the latch
    lda #1
    sta jump_latch
@jump_end:


@apply_accel:
    ; Update velocity
    lda vel_y
    clc
    adc acc_y
    sta vel_y
    ; Keep the carry bit this time
    lda vel_y+1
    adc acc_y+1
    sta vel_y+1

    ; Update position
    lda pos_y
    clc
    adc vel_y
    sta pos_y
    lda pos_y+1
    adc vel_y+1
    sta pos_y+1

    ;; Stop if pos_y is below ground
    lda pos_y+1         ; TODO: pos_y is already in A
    cmp #160            ; C = pos_y >= 160
    bcc @skip_ground    ; Jump if pos_y < 160 (above ground)
    lda #160
    sta pos_y+1
    lda #0
    sta vel_y
    sta vel_y+1
    sta acc_y
    sta acc_y+1
    lda buttons
    and #%01000000
    bne @skip_ground
    lda #0
    sta jump_latch
@skip_ground:

    ;; Transfer positions to OAM buffer
    lda pos_y+1
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
