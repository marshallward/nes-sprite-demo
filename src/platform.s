; Platform data
;
; Current runtime data used by jump.s for horizontal platform collision.
; See platform_dev.s for the more general platform-list sketch.

.export init_platforms
.export apply_platform_collision
.export platform_x0
.export platform_x1
.export platform_y0
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

platform_x0:
    .byte 0, 120, 120
platform_x1:
    .byte 255, 136, 136
platform_y0:
    .byte 185, 137, 105

.setcpu "6502"
.segment "CODE"

init_platforms:
    lda #3
    sta platform_count
    lda #0
    sta platform_hit
    rts


apply_platform_collision:
    lda #0
    sta platform_hit

    ldx #0
@platform_loop:
    cpx platform_count  ; Z set if X = platform_count
    beq @end_platform_loop

    ; Skip if x < x0
    clc
    lda pos_x
    adc #1  ; TODO: OFF BY ONE ERROR!!!
    adc scroll_x
    cmp platform_x0, x  ; C = pos_x + scroll_x >= x0(p)
    bcc @end_platform_check

    ; Skip if x > x0
    ; NOTE: For now, we want checks to be inclusive (pos_x + scroll_x > x1(p)).
    ;   But is because we only have a single 0..255 screen.
    ;   If we ever get a global map, then maybe this can be wiped.
    ; NOTE: Assume A = pos_x + scroll_x
    cmp platform_x1, x  ; C = pos_x + scroll_x >= x1(p)
    beq :+              ; If Z, skip check
    bcs @end_platform_check
:

    ; Have we crossed y0?
    ; NOTE: Load platform_y0, then only need one lda?

    ; Skip if we were already below y0(p) (pos_y > y0(p))
    lda pos_y+1
    cmp platform_y0, x  ; C = pos_y >= y0(p)
    bcs @end_platform_check

    ; Skip if the updated y_pos is still above y0(p) (next_y < y0(p))
    lda next_y
    cmp platform_y0, x  ; C = next_y >= y0(p)
    bcc @end_platform_check

    sec
    lda platform_y0, x
    ; Stay one point above the platform
    ; TODO: Maybe define so that y0 is where you stop, rather than the ground?
    sbc #1

    ; Keep the highest crossed platform so collision does not depend on list
    ; order. Positive y is downward, so smaller y is closer to the start point.
    ldy platform_hit
    beq @store_hit
    cmp platform_hit_y
    bcs @end_platform_check

@store_hit:
    sta platform_hit_y
    lda #1
    sta platform_hit

@end_platform_check:
    inx
    jmp @platform_loop

@end_platform_loop:
    rts
