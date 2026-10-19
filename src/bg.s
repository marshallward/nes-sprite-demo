.include "ppu.inc"

.export init_bg

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
    .repeat 16*1
        .byte 0
    .endrepeat
    .byte 5, 5
    .repeat 14*1
        .byte 0
    .endrepeat

    ; Below us only sky
    .repeat 32*3
        .byte 0
    .endrepeat

    ; The platform!
    .repeat 16*1
        .byte 0
    .endrepeat
    .byte 5, 5
    .repeat 14*1
        .byte 0
    .endrepeat

    ; One sky row below the lower floating platform (row 19).
    .repeat 32
        .byte 0
    .endrepeat

    ; Rows 20..23: 1:1 ramp in columns 4..7, 2:1 in 12..13, ledge in 20..23.
    ; Diagonal pixels run (32,191)..(63,160); platform_7 also includes the
    ; joining ground pixel (31,192), drawn by the ground row below.
    .repeat 4, row
        .repeat 32, col
            .if col < 7-row
                .byte 0
            .elseif col = 7-row
                .byte 6         ; diagonal grass/dirt tile
            .elseif col <= 7
                .byte 2         ; dirt below the diagonal
            .elseif col < 12
                .byte 0
            .elseif col <= 13
                .if col < 13-(row/2)
                    .byte 0
                .elseif col = 13-(row/2)
                    .if (row & 1) = 0
                        .byte 7 ; upper half of a steep diagonal
                    .else
                        .byte 8 ; lower half, with dirt to its right
                    .endif
                .else
                    .byte 2
                .endif
            .elseif col < 20
                .byte 0
            .elseif col < 24
                .if row = 0
                    .byte 5     ; original ledge top
                .else
                    .byte 2
                .endif
            .else
                .byte 0
            .endif
        .endrepeat
    .endrepeat

    ; Row 24 (Y=192): lower ground, with dirt under both ramps and the ledge.
    .repeat 4
        .byte 5
    .endrepeat
    .repeat 4
        .byte 2
    .endrepeat
    .repeat 4
        .byte 5
    .endrepeat
    .repeat 2
        .byte 2
    .endrepeat
    .repeat 6
        .byte 5
    .endrepeat
    .repeat 4
        .byte 2
    .endrepeat
    .repeat 8
        .byte 5
    .endrepeat

    ; All dirt
    .repeat 32*5
        .byte 2
    .endrepeat
bg0_end:
.assert bg0_end - bg0 = 32*30, error, "Background must contain 30 rows of 32 tiles"


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
