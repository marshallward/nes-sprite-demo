; iNES header
.segment "HEADER"
    ; signature: "NES" + EOF (CTRL+Z)
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
    ;     32    2: Flags 8-15 are in iNES 2.0 format
    ;       1   1: PlayChoice-10 (8 kiB hint data stored after CHR)
    ;        0  1: VS Unisystem
    .byte %00000000

    ; TODO: Rest of bytes!
    .res 8, 0
