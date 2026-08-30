; Platform data
;
; Current runtime data used by jump.s for horizontal platform collision.
; See platform_dev.s for the more general platform-list sketch.

.export init_platforms
.export apply_platform_collision
.exportzp platform_count
.exportzp platform_hit
.exportzp platform_hit_y

.importzp pos_x
.importzp pos_y
.importzp scroll_x
.importzp next_y

.segment "ZEROPAGE"

platform_count:
    .res 1
platform_hit:
    .res 1
platform_hit_y:
    .res 1

.segment "RODATA"

; Horizontal platform records: x0, x1, y
platform_data:
platform_1:
    .byte 0, 255, 185
platform_2:
    .byte 120, 136, 137
platform_3:
    .byte 120, 136, 105
platform_data_end:

PLATFORM_STRIDE = platform_2 - platform_1
NUM_PLATFORMS = (platform_data_end - platform_data) / PLATFORM_STRIDE


.setcpu "6502"
.segment "CODE"

init_platforms:
    lda #NUM_PLATFORMS
    sta platform_count
    lda #0
    sta platform_hit
    rts


apply_platform_collision:
    lda #0
    sta platform_hit

    ; X tracks number of platforms
    ; Y tracks position in platform list
    ;   They are related, but it may not be easy to combine them
    ldy #0
    ldx platform_count
@platform_loop:
    cpx #0
    beq @end_platform_loop

    ; "Weak" test: Only collide if x0 < pos_x < x1
    ; (The strong test requires a more complicated expression)

    ; Skip if x < x0
    clc
    lda pos_x
    adc #1  ; TODO: OFF BY ONE ERROR!!!
    adc scroll_x
    cmp platform_data, y    ; C = pos_x + scroll_x >= x0(p)
    bcc @end_platform_check

    ; Skip if x > x1
    ; NOTE: For now, we want checks to be inclusive (pos_x + scroll_x > x1(p)).
    ;   But is because we only have a single 0..255 screen.
    ;   If we ever get a global map, then maybe this can be wiped.
    ; NOTE: Assume A = pos_x + scroll_x
    cmp platform_data+1, y  ; C = pos_x + scroll_x >= x1(p)
    beq :+                  ; If Z, skip check
    bcs @end_platform_check
:

    ; Now check if we have crossed y0

    ; Skip if we were already below y0(p) (pos_y > y0(p))
    lda pos_y+1
    cmp platform_data+2, y  ; C = pos_y >= y0(p)
    bcs @end_platform_check

    ; Skip if the updated y_pos is still above y0(p) (next_y < y0(p))
    lda next_y
    cmp platform_data+2, y  ; C = next_y >= y0(p)
    bcc @end_platform_check

    sec
    lda platform_data+2, y
    ; Stay one point above the platform
    ; TODO: Maybe define so that y0 is where you stop, rather than the ground?
    sbc #1

    ; Keep the highest crossed platform so collision does not depend on list
    ; order. Positive y is downward, so smaller y is closer to the start point.
    pha
    lda platform_hit        ; Set Z if no recorded collision
    beq @store_first_hit    ; If set, compare y to cached platform_hit_y
    pla                     ; A = y0
    cmp platform_hit_y      ; C = (A >= y0)
    bcs @end_platform_check ; if A below y0, then use y0 (skip store_hit)
    jmp @store_hit          ; Update platform_hit_y to y0

@store_first_hit:
    pla

    ; Here, A = y regardless of the y-check.

    ; If we're here, then we collide into y (either the first or highest)
@store_hit:
    sta platform_hit_y
    lda #1
    sta platform_hit

    ; Set up the next loop iteration
@end_platform_check:
    tya
    clc
    adc #PLATFORM_STRIDE
    tay
    dex
    jmp @platform_loop

@end_platform_loop:
    rts
