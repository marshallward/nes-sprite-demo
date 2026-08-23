.include "ppu.inc"
.include "boot.inc"

.importzp buttons
.import read_joypad1
.import init_jump
.import update_jump
.import init_platforms

; Data
; I am literally importing these things so that I can pass them back to bg.s
; I'm sure this is silly but I just want to get it working for now.
.import render_bg
.import bg0
.import bg1

; Needed by update_jump
; (Though perhaps it should be an input?)
.exportzp pos_x
.exportzp pos_y
.exportzp scroll_x
.exportzp ntable

.exportzp arg0
.exportzp arg1
.exportzp arg2

; Scrolling frame parameters
X_FRAME_MIN = 96
X_FRAME_MAX = 160

; Sprite positions
.segment "ZEROPAGE"
    frame: .res 1

    ; Ball position (relative to origin?  I hope so)
    pos_x: .res 1
    ; 8.8 pixel resolution
    pos_y: .res 2

    ; Map position (I think...)
    scroll_x: .res 1

    ; Current nametable (0 or 1)
    ; NOTE: This almost acts as an upper byte of position.  Look into it...
    ntable: .res 1

    ; Function arguments
    arg0: .res 1
    arg1: .res 1
    arg2: .res 1


.setcpu "6502"
.segment "CODE"

reset:
    INITIALIZE_NES

    ;; Render background background

    ; TODO: Just move this whole thing into bg.s
    lda #<bg0
    sta arg0
    lda #>bg0
    sta arg1
    lda #$20
    sta arg2
    jsr render_bg

    lda #<bg1
    sta arg0
    lda #>bg1
    sta arg1
    lda #$24
    sta arg2
    jsr render_bg

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

    ; Set PPU scroll to zero
    ; (Maybe not so important now that the NMI handles this?)
    lda #0
    sta PPUSCROLL   ; xscroll = 0
    sta PPUSCROLL   ; yscroll = 0

    ; Set current nametable to NT0
    sta ntable  ; ntable = 0

    ; enable background and sprites
    SET_PPUMASK #%00011000

    ;; Game setup

    ; Initialize frame flag
    lda #0
    sta frame

    ; Initialize kinematic state
    ; This is only needed because we don't pass vel_y and acc_y!
    jsr init_jump

    ; Initialize active platform data
    jsr init_platforms

    ; Initialize scrolling
    lda #0
    sta scroll_x

main:
    ; Wait for vblank NMI to complete (defined below)
@wait:
    lda frame
    beq @wait

    ; Unset the frame draw flag
    lda #0
    sta frame


    ;; Update controller

    ; Read controller
    jsr read_joypad1

    ; TODO: Move left-right logic to jump.s
    ;   (And rename jump.s to move or something!)

    ; Check Right
    lda buttons
    and #%00000001
    beq @skip_right
    lda pos_x
    cmp #X_FRAME_MAX    ; C = pos_x >= 160
    bcs @right_scroll   ; scroll if pos_x >= right_bound
;@right_move
    inc pos_x
    jmp @skip_right
@right_scroll:
    clc
    lda scroll_x
    adc #1
    sta scroll_x
    bcc :+
    lda ntable
    eor #1
    sta ntable
@skip_right:

    ; Check Left
    lda buttons
    and #%00000010
    beq @skip_left
    lda pos_x
    cmp #X_FRAME_MIN+1  ; C = pos_x >= 96+1
    bcc @left_scroll    ; scroll if pos_x < left_bound+1
;@left_move
    dec pos_x
    jmp @skip_left
@left_scroll:
    sec
    lda scroll_x
    sbc #1
    sta scroll_x
    bcs :+
    lda ntable
    eor #1
    sta ntable
:
@skip_left:

    jsr update_jump

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

    ; Update scroll
    lda scroll_x
    sta PPUSCROLL
    lda #0
    sta PPUSCROLL

    ; Set the frame drawn flag
    lda #1
    sta frame

    ; Update nametable
    lda #%10000000
    ora ntable
    sta PPUCTRL

    rti

irq:
    rti


; Vector interrupt table
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
