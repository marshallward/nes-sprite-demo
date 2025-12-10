; NES header
;
; Archaic iNES: Bytes 0-6
; iNES: 0-9
; NES 2.0: 0-15

.segment "HEADER"
    ; signature: "NES" + MS-DOS EOF (CTRL+Z)
    .byte "N", "E", "S", $1a

    ; Size of PRG ROM in 16 KB units
    .byte 1

    ; Size of CHR ROM in 8kiB units (0 indicates CHR-RAM)
    .byte 1

    ; 7654      Lower 4 bits of mapper
    ;     3     1: Alternative nametable layout (NOTE: mapper-dependent)
    ;      2    1: 512 kiB trainer at $7000-71ff (stored before PRG)
    ;       1   1: battery-backed PRG-RAM ($6000-$7fff) or similar
    ;        0  Nametable arrangement
    ;               0: vertical arrangement ("horizontal mirroring")
    ;               1: horizontal arrangement ("vertical mirroring")
    .byte %00000000

    ; 7654      Upper 4 bits of mapper
    ;     32    2: Use NES 2.0 format
    ;       1   1: PlayChoice-10 (8 kiB hint data stored after CHR)
    ;        0  1: VS Unisystem
    .byte %00000000

    ; iNES:
    ;   PRG RAM size
    ; NES 2.0:
    ;   7654        Highest 4 bits of mapper
    ;       3210    Mapper variant
    .byte 0

    ; iNES:
    ;   7654321     Reserved, set to zero
    ;          0    TV system:
    ;                   0: NTSC
    ;                   1: PAL
    ; NES 2.0:
    ;   TODO
    .byte 0

    .res 6, 0
