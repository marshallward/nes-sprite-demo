; Platform control
;
; Currently static but could be continuously filled from ROM.
; Platform segments are (A0,A1) to (B0,B1).
;
; Proposed models:
;   (A0, A1, B0, B1)
;       Most compact, but slope must be determined, which takes time.
;   (A0, A1, Slope-X, Slope-Y, Length)
;
; Or break it into separate types of platforms:
;       If sloped platforms are rare then this might make the most sense.
;   (A0, A1, X-length)
;   (A0, A1, Y-length)
;   (A0, A1, X-length, SlopeX, SlopeY)
.segment "RODATA"
platform_data:
platform_1:
    .byte 0, 185, 255, 185
platform_2:
    .byte: 120, 136, 120, 185
PLATFORM_STRIDE = platform_2 - platform_1
NUM_PLATFORMS = (platform_2 - platform_data) / PLATFORM_STRIDE

; Assert NUM_PLATFORMS * PLATFORM_STORAGE < 256?

; Platform traversal check

    ldy #0
@platform_loop:
    cpy #NUM_PLATFORMS * #PLATFORM_STORAGE
        ; Z = (Y == #NUM_PLATFORMS)
    beq @end_platform_loop

    ; compute checks...
    clc     ; need?
    ; TODO: A = p1

@end_platform_check:
    iny
    jmp @platform_loop

@end_platform_loop:
    rts
