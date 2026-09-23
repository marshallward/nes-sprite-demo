.include "ppu.inc"
.include "boot.inc"

.importzp buttons
.import read_joypad1
.import init_move
.import update_move
.import init_platforms
.import init_bg

; Needed by update_move
; (Though perhaps it should be an input?)
.exportzp pos_x
.exportzp pos_y
.exportzp scroll_x
.exportzp ntable

.exportzp arg0
.exportzp arg1
.exportzp arg2

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

    ;; Render background
    jsr init_bg

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

    ; Initialize movement state
    jsr init_move

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

    ; Read controller
    jsr read_joypad1

    ; Update position
    jsr update_move

    ; Transfer positions to OAM buffer
    lda pos_y+1
    sta $0200
    sec
    lda pos_x
    sbc scroll_x
    sta $0203

    ; Reset game loop
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
