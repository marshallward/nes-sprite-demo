; Platform data
;
; One typed list and traversal for flat floors and vertical walls.
; See platform_dev.s for the more general platform-list sketch.

.export init_platforms
.export apply_platform_collision
.exportzp platform_count
.exportzp hit_y
.exportzp hit_y_position
.exportzp hit_x
.exportzp hit_x_position

.importzp pos_x
.importzp next_x
.importzp pos_y
.importzp next_y
.importzp vel_x

.segment "ZEROPAGE"

platform_count:
    .res 1
hit_y:
    .res 1
hit_y_position:
    .res 1
hit_x:
    .res 1
hit_x_position:
    .res 1                  ; corrected player X of the nearest wall candidate

.segment "RODATA"

PLATFORM_FLAT = 0
PLATFORM_WALL = $FF

; XXX: There is a bug in platform height which (I think) accounts for the
; sprite offset, rather than the absolute map.  These offsets are baked into
; the numbers right now but need to be fixed.
; e.g. top platform is 105 = 8*13+1, but graphically it appears at 8*14.

; Platform records: type, start, end, height.
; Flat: inclusive x0, x1, y. Wall: inclusive y0, y1, x.
platform_data:
platform_1:
    ; Left lower floor; the raised ledge begins at X=160.
    .byte PLATFORM_FLAT, 0, 255, 185
platform_2:
    .byte PLATFORM_FLAT, 120, 135, 137
platform_3:
    .byte PLATFORM_FLAT, 120, 135, 105
platform_4:
    ; Raised ledge: left side, top, right side, then the right lower floor.
    ; Its map tiles occupy X=160..191, Y=160..191.
    ; Floor checks use OAM Y origin: landing at 152-1 puts the last sprite
    ; row at 159, just above the drawn top. Do not change floor geometry here.
    ; Side bottoms extend below the inherited lower-floor contact convention.
    .byte PLATFORM_WALL, 161, 200, 160
platform_5:
    .byte PLATFORM_FLAT, 160, 191, 153
platform_6:
    .byte PLATFORM_WALL, 161, 200, 191
platform_data_end:

PLATFORM_STRIDE = platform_2 - platform_1
NUM_PLATFORMS = (platform_data_end - platform_data) / PLATFORM_STRIDE

; Pixel-collision: Which pixel (0..7) should we test on the left and right?
; TODO: Define this in the sprite!
PLAYER_FOOT_L_X = 2
PLAYER_FOOT_R_X = 5

; Wall-only body bounds. NES OAM Y is one row above the visible sprite.
; The existing floor Y-origin/foot checks are deliberately unchanged.
PLAYER_BODY_L_X = 2
PLAYER_BODY_R_X = 5
PLAYER_BODY_TOP_Y = 1
PLAYER_BODY_BOTTOM_Y = 8

.setcpu "6502"
.segment "CODE"

init_platforms:
    lda #NUM_PLATFORMS
    sta platform_count
    lda #0
    sta hit_y
    sta hit_x
    rts


apply_platform_collision:
    lda #0
    sta hit_y
    sta hit_x

    ; X tracks number of platforms
    ; Y tracks position in platform list
    ;   They are related, but it may not be easy to combine them
    ldy #0
    ldx platform_count
@platform_loop:
    cpx #0
    beq @end_platform_loop

    lda platform_data, y
    cmp #PLATFORM_WALL
    bne :+
    jsr check_wall
    jmp @end_platform_check
:
    ; Leave other platform types for later steps.
    cmp #PLATFORM_FLAT
    bne @end_platform_check

    ; Collide if x0 <= x <= x1

    ; Pass through if x < x0
    clc
    ; x = proposed x_world + x_foot
    lda next_x
    adc #PLAYER_FOOT_R_X
    cmp platform_data+1, y  ; C = x >= x0(p)
    bcc @end_platform_check

    ; Pass through if x > x1
    clc
    ; x = proposed x_world + x_foot
    lda next_x
    adc #PLAYER_FOOT_L_X
    cmp platform_data+2, y  ; C = x >= x1(p)
    beq :+                  ; If Z, skip check
    bcs @end_platform_check
    ; NOTE: Check if faster to offset + bcs, rather than beq + bcs
:

    ; Now check if we have crossed y0

    ; Skip if we were already below y0(p) (pos_y > y0(p))
    lda pos_y+1
    cmp platform_data+3, y  ; C = pos_y >= y0(p)
    bcs @end_platform_check

    ; Skip if the updated y_pos is still above y0(p) (next_y < y0(p))
    lda next_y+1
    cmp platform_data+3, y  ; C = next_y >= y0(p)
    bcc @end_platform_check

    sec
    lda platform_data+3, y
    ; Stay one point above the platform
    ; TODO: Maybe define so that y0 is where you stop, rather than the ground?
    sbc #1

    ; Keep the highest crossed platform so collision does not depend on list
    ; order. Positive y is downward, so smaller y is closer to the start point.
    pha
    lda hit_y               ; Set Z if no recorded collision
    beq @store_first_hit    ; If set, compare y to cached hit_y_position
    pla                     ; A = y0
    cmp hit_y_position      ; C = (A >= y0)
    bcs @end_platform_check ; if A below y0, then use y0 (skip store_hit)
    jmp @store_hit          ; Update hit_y_position to y0

@store_first_hit:
    pla

    ; Here, A = y regardless of the y-check.

    ; If we're here, then we collide into y (either the first or highest)
@store_hit:
    sta hit_y_position
    lda #1
    sta hit_y

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


check_wall:
    ; Candidate detection only: never alter next_x/next_y or velocity here.
    lda vel_x
    bne :+
    rts
:
    ; Test if the updated y overlaps with the wall bounds (y0, y1)
    ; (Overlap tests for the player body are included, but I am skeptical that
    ; that they are working.)
    ; NOTE: next_y is two-byte; position is next_y+1.

    ; Pass through if y(t+1) < y1
    clc                     ; C = 0, Z = 0
    lda next_y+1            ; A = y(t+1)
    adc #PLAYER_BODY_BOTTOM_Y
    bcs @no_overlap         ; wrapped body coordinates are not supported
    cmp platform_data+1, y  ; C = y >= y1
    bcc @no_overlap         ; Skip if y < y1

    ; Pass if y(n+1) > y1
    clc                     ; C = 0, Z = 0
    lda next_y+1            ; A = y(t+1)
    adc #PLAYER_BODY_TOP_Y
    bcs @no_overlap
    cmp platform_data+2, y  ; C = (y >= y2), Z = (y == y2)
    beq @overlap            ; Collide if y == y2
    bcc @overlap            ; Collide if y < y2
@no_overlap:
    rts
    ; TODO: Rewrite above to resemble the platform structure.

@overlap:
    lda vel_x
    bmi @left

    ; Rightward crossing; ignore world-byte wrap until paging is implemented.

    ; If x(n+1) < x(n) (moving leftward) then skip rightward test
    lda next_x
    cmp pos_x
    bcc @no_right_hit

    ; Check if we are the left of the wall
    clc
    lda pos_x
    adc #PLAYER_BODY_R_X
    bcs @no_right_hit
    cmp platform_data+3, y
    bcs @no_right_hit

    ; Check if x(n+1) is to the right of the wall
    clc
    lda next_x
    adc #PLAYER_BODY_R_X
    bcs @no_right_hit
    cmp platform_data+3, y
    bcc @no_right_hit

    ; This is a potential collision.
    ; Set position to the left (sec + sbc 1)
    ; Accept as the latest collision if it is shorter than last checked.
    lda platform_data+3, y
    sec
    sbc #PLAYER_BODY_R_X+1
    pha
    lda hit_x
    beq @first_hit
    pla
    cmp hit_x_position      ; smaller corrected X is closer moving right
    bcc @store_hit
@no_right_hit:
    rts

@left:
    ; Leftward crossing; ignore world-byte wrap until paging is implemented.

    ; If x(n+1) >= x(n), skip the leftward test.
    lda next_x
    cmp pos_x
    bcs @no_left_hit

    ; Check if our old left body edge is strictly right of the wall.
    clc
    lda pos_x
    adc #PLAYER_BODY_L_X
    bcs @no_left_hit
    cmp platform_data+3, y
    bcc @no_left_hit
    beq @no_left_hit

    ; Check if the left body edge at x(n+1) reaches or passes left of the wall.
    clc
    lda next_x
    adc #PLAYER_BODY_L_X
    bcs @no_left_hit
    cmp platform_data+3, y
    beq @left_hit
    bcs @no_left_hit
@left_hit:
    ; This is a potential collision.
    ; Calculate player X so the left body edge is one pixel right of the wall.
    ; Accept it if this is the first candidate or closer than the last checked.
    lda platform_data+3, y
    sec
    sbc #PLAYER_BODY_L_X-1
    pha
    lda hit_x
    beq @first_hit
    pla
    cmp hit_x_position      ; larger corrected X is closer moving left
    bcs @store_hit
@no_left_hit:
    rts

@first_hit:
    pla
@store_hit:
    sta hit_x_position
    lda #1
    sta hit_x
    rts
