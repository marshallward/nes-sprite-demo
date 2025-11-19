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

    ; Going to try a version which tracks many states.
    ; After it's working, I'll reduce and consolidate.
    jump_latch: .res 1


; Jump parameters (positive is downward)
VEL_JUMP_LO = 128
VEL_JUMP_HI = <-4
G_UP = 40
G_PRESS = 15
G_DOWN = 60

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
    lda vel_y_hi
    bpl @jump_down      ; minus is up!
;@jump_up
    lda buttons
    and #%01000000
    beq @vel_up_release
;@vel_up_press:
    lda #G_PRESS
    sta acc_y_lo
    jmp @jump_end
@vel_up_release:
    lda #G_UP
    sta acc_y_lo
    jmp @jump_end

@jump_down:
    lda #G_DOWN
    sta acc_y_lo

;@jump_start:
    ; Do not apply impulse if latch is set
    lda jump_latch
    bne @jump_end

    lda buttons
    and #%01000000
    beq @jump_end
    lda pos_y
    cmp #160    ; C = pos_y <= 160
    bcc @jump_end   ; skip if C > 0 ; we are still falling
    ; We're on the ground
    lda #VEL_JUMP_LO
    sta vel_y_lo
    lda #VEL_JUMP_HI
    sta vel_y_hi
    ; set the latch
    lda #1
    sta jump_latch
@jump_end:


@apply_accel:
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

    ;; Stop if pos_y is below ground
    lda pos_y           ; TODO: pos_y is already in A
    cmp #160            ; C = pos_y >= 160
    bcc @skip_ground    ; Jump if pos_y < 160 (above ground)
    lda #160
    sta pos_y
    lda #0
    sta vel_y_lo
    sta vel_y_hi
    sta acc_y_lo
    sta acc_y_hi
    lda buttons
    and #%01000000
    bne @skip_ground
    lda #0
    sta jump_latch
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
