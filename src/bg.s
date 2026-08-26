.include "ppu.inc"

.export init_bg
.export render_bg

; Function arguments
.importzp arg0
.importzp arg1
.importzp arg2

; Alias to inputs
; (All temporary of course!)
bg_ptr_lo = arg0
bg_ptr_hi = arg1


;.segment "ZEROPAGE"
;    ; bg nametable pointer
;    bg_ptr_lo: .res 1
;    bg_ptr_hi: .res 1


.segment "RODATA"

; A simple nametable example
; NOTE: This should probably be done in some graphical form
bg0:
    ; All sky
    .repeat 32*14
        .byte 0
    .endrepeat

    ; The platform!
    .repeat 15*1
        .byte 0
    .endrepeat
    .byte 5, 5
    .repeat 15*1
        .byte 0
    .endrepeat

    ; Below us only sky
    .repeat 32*3
        .byte 0
    .endrepeat

    ; The platform!
    .repeat 15*1
        .byte 0
    .endrepeat
    .byte 5, 5
    .repeat 15*1
        .byte 0
    .endrepeat

    ; Below us only sky
    .repeat 32*5
        .byte 0
    .endrepeat

    ; Top soil
    .repeat 32
        .byte 5
    .endrepeat

    ; All dirt
    .repeat 32*5
        .byte 2
    .endrepeat


; Make a second, simple table
bg1:
    .repeat 32*24
        .byte 0
    .endrepeat

    ;.repeat 32
    ;    .byte 5
    ;.endrepeat
    .repeat 15*1
        .byte 5
    .endrepeat
    .byte 1, 1
    .repeat 15*1
        .byte 5
    .endrepeat

    .repeat 32*5
        .byte 2
    .endrepeat


.setcpu "6502"
.segment "CODE"

init_bg:
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

    rts


render_bg:
    ; Inputs
    ; ======
    ; bg_ptr_lo = arg0
    ; bg_ptr_hi = arg1

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
    ; TODO: This could be refined to write a set of rows/columns
    ;   For now we (crudely) set the nametable
    ;SET_PPUADDR $2000
    lda arg2
    sta PPUADDR
    lda #0
    sta PPUADDR

    ; NOTE: This 16-bit data copy could be its own subroutine.

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

    ; Set nametable attributes
    ldx #64
@bg_attr_loop:
    lda #0
    sta PPUDATA
    dex
    bne @bg_attr_loop

    rts
