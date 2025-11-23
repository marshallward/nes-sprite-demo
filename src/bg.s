.include "ppu.inc"

.export bg_table
.export render_bg


.segment "ZEROPAGE"
    ; bg table pointer
    bg_ptr_lo: .res 1
    bg_ptr_hi: .res 1


.segment "RODATA"

bg_table:
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
        .byte 2
    .endrepeat


.segment "CODE"

render_bg:
    ; Clear the PPU VRAM latch
    lda PPUSTATUS

    ; Set the background palette
    SET_PPUADDR BG_PALETTE
    ; Universal BG color
    lda #$0f
    sta PPUDATA
    
    ; BG0 palette
    lda #$1b
    sta PPUDATA
    lda #$07
    sta PPUDATA
    lda #$27
    sta PPUDATA

    ; Copy the nametable to the PPU
    SET_PPUADDR $2000

    ; NOTE: This 16-bit data copy could be a subroutine, if not a macro.

    ; Assign the nametable starting address
    lda #<bg_table
    sta bg_ptr_lo
    lda #>bg_table
    sta bg_ptr_hi

    ldx #30
@bg_row_loop:
    ; Copy the Xth row to the PPU
    ldy #0
@bg_col_loop:
    ; Copy element (X,Y) to the PPU
    lda (bg_ptr_lo),y
    sta PPUDATA
    iny
    cpy #32
    bne @bg_col_loop

    ; advance pointer to next row
    clc
    lda bg_ptr_lo
    adc #32
    sta bg_ptr_lo
    bcc :+
    inc bg_ptr_hi
:
    dex
    bne @bg_row_loop

    ; Set nametable attributes (mostly just using BG0)
    ldx #64
@bg_attr_loop:
    lda #0
    sta PPUDATA
    dex
    bne @bg_attr_loop

    rts
