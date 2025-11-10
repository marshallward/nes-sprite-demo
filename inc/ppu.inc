.ifndef ::PPU_INC
PPU_INC = 1

; PPU control registers
PPUCTRL = $2000
PPUMASK = $2001
PPUSTATUS = $2002
PPUADDR = $2006
PPUDATA = $2007


; Loop until the start of a vertical blank (vblank).
.macro WAIT_FOR_VBLANK
    .local loop
loop:
    ; Read bit 7 of PPUSTATUS to N flag and jump if unset.
    bit PPUSTATUS
    bpl loop

    ; Reading PPUSTATUS also unsets bit 7, even during a vblank.
.endmacro


; Write the upper, then lower, byte of addr to PPUADDR.
.macro SET_PPUADDR addr
    lda #>addr
    sta PPUADDR
    lda #<addr
    sta PPUADDR
.endmacro

; Set PPU "mask" controls.
; After reset, these are ignored until the next pre-render scanline.
.macro SET_PPUMASK value
    ;        1 : Enable grayscale
    ;       1  : Show background leftmost 8 pixels
    ;      1   : Show sprite leftmost 8 pixels
    ;     1    : Enable background
    ;    1     : Enable sprites
    ;   1      : Emphasize red (NTSC) / green (PAL)
    ;  1       : Emphasize green (NTSC) / red (PAL)
    ; 1        : Emphasize blue
    lda value
    sta PPUMASK
.endmacro

.endif
