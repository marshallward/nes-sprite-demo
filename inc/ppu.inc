.ifndef ::PPU_INC
PPU_INC = 1

; CPU memory map

; PPU control registers
PPUCTRL = $2000
PPUMASK = $2001
PPUSTATUS = $2002
OAMADDR = $2003
PPUSCROLL = $2005
PPUADDR = $2006
PPUDATA = $2007
OAMDMA = $4014

;----------------
; PPU memory map

; Pattern tables
PATTERN_TABLES = $0000
PATTERN_0 = PATTERN_TABLES
PATTERN_1 = PATTERN_TABLES + $1000

; Nametables
; Video map of 32x30(=960) tiles
;   Each byte maps to one of 256 tiles in the assigned pattern table.
NAMETABLES = $2000
NAMETABLE_0 = NAMETABLES + $0000
NAMETABLE_1 = NAMETABLES + $400
NAMETABLE_2 = NAMETABLES + $800
NAMETABLE_3 = NAMETABLES + $c00

; Attribute table
ATTR_TABLE_0 = NAMETABLE_0 + $3c0
ATTR_TABLE_1 = NAMETABLE_1 + $3c0
ATTR_TABLE_2 = NAMETABLE_2 + $3c0
ATTR_TABLE_3 = NAMETABLE_3 + $3c0

; Background
BG_PALETTE = $3f00
BG0_PALETTE = BG_PALETTE
BG1_PALETTE = BG_PALETTE + $04
BG2_PALETTE = BG_PALETTE + $08
BG3_PALETTE = BG_PALETTE + $0c

SPRITE_PALETTE = (BG_PALETTE + $10)
SP0_PALETTE = SPRITE_PALETTE
SP1_PALETTE = SPRITE_PALETTE + $04
SP2_PALETTE = SPRITE_PALETTE + $08
SP3_PALETTE = SPRITE_PALETTE + $0c


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
    lda #>(addr)
    sta PPUADDR
    lda #<(addr)
    sta PPUADDR
.endmacro


; These are unlikely needed but for now serve as documentation.

.macro SET_PPUCTRL value
    ;       11 : Base nametable address (NT0-NT3)
    ;      1   : VRAM address increment per CPU read/write
    ;          :    (0: +1 along row ; 1: +32 along column)
    ;     1    : Sprite pattern table address (8x8 only) (ST0-ST1)
    ;    1     : Background pattern table address (BT0-BT1)
    ;   1      : Sprite size
    ;          :    (0: 8x8 ; 1: 8x16)
    ;  1       : PPU master/slave select
    ;               (0: Read background from EXT; 1: Output color on EXT)
    ; 1        : VBlank NMI enable
    ;          :    (0: off ; 1: enable)
    lda value
    sta PPUCTRL
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
