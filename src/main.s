.include "ppu.inc"
.include "boot.inc"

.importzp buttons
.import read_joypad1
.import init_jump
.import update_jump

; Data
.import render_bg
.import bg_table

; Needed by update_jump
; (Though perhaps it should be an input?)
.exportzp pos_x
.exportzp pos_y
.exportzp scroll_x


; Sprite positions
.segment "ZEROPAGE"
    frame: .res 1

    ; Ball position (relative to origin?  I hope so)
    pos_x: .res 1
    ; 8.8 pixel resolution
    pos_y: .res 2

    ; Map position (I think...)
    scroll_x: .res 1


.setcpu "6502"
.segment "CODE"

reset:
    INITIALIZE_NES

    ; Render background background
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
    sta PPUSCROLL
    sta PPUSCROLL

    ; enable background and sprites
    SET_PPUMASK #%00011000


    ;; Game setup

    ; Initialize frame flag
    lda #0
    sta frame

    ; Initialize kinematic state
    ; This is only needed because we don't pass vel_y and acc_y!
    jsr init_jump

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

    ; Check Right
    lda buttons
    and #%00000001
    beq @skip_right
    lda pos_x
    cmp #160    ; C = pos_x >= 160
    bcc @right_move
;@right_scroll:
    inc scroll_x
    jmp @skip_right
@right_move:
    inc pos_x
@skip_right:

    ; Check Left
    lda buttons
    and #%00000010
    beq @skip_left
    lda pos_x
    cmp #96 ; C = pos_x >= 96
    bcc @left_scroll
;@left_move
    dec pos_x
    jmp @skip_left
@left_scroll:
    dec scroll_x
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

    rti

irq:
    rti


; Vector interrupt table
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
