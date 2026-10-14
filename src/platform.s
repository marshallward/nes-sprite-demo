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
.importzp vel_y

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
contact_y:
    .res 1                  ; player Y at which the bottom reaches this floor

.segment "RODATA"

PLATFORM_FLAT = 0
PLATFORM_WALL = $FF

; Platform records: type, start, end, height.
; - Flat: (start,end) = (x0, x1), height = y
; - Wall: (start,end) = (y0, y1), height = x
platform_data:
platform_1:
    ; Continuous ground, including underneath the raised ledge.
    .byte PLATFORM_FLAT, 0, 255, 192
platform_2:
    .byte PLATFORM_FLAT, 120, 135, 144
platform_3:
    .byte PLATFORM_FLAT, 120, 135, 112
platform_4:
    ; Raised ledge: left side, top, right side.
    ; Its map tiles occupy X=160..191, Y=160..191.
    ; Wall bounds are unchanged pending a separate body-alignment review.
    .byte PLATFORM_WALL, 161, 200, 160
platform_5:
    .byte PLATFORM_FLAT, 160, 191, 160
platform_6:
    .byte PLATFORM_WALL, 161, 200, 191
platform_data_end:

PLATFORM_STRIDE = platform_2 - platform_1
NUM_PLATFORMS = (platform_data_end - platform_data) / PLATFORM_STRIDE

; Pixel-collision: Which pixel (0..7) should we test on the left and right?
; TODO: Define this in the sprite!
PLAYER_FOOT_L_X = 2
PLAYER_FOOT_R_X = 5

; Explicit floor contact geometry relative to OAM Y. Hardware starts the tile
; at OAM Y+1; the ball's lowest opaque row is tile row 6, hence OAM Y+7.
PLAYER_FOOT_BOTTOM_Y = 7

; Wall-only body bounds relative to player Y.
; Wall bounds are separate from floor contact and are unchanged in this patch.
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

    ; Calculate player Y at which the bottom reaches the floor. Equivalent to
    ; comparing player bottom (player Y + PLAYER_FOOT_BOTTOM_Y) with surface Y,
    ; but avoids wrapping a body-offset addition near the bottom of the page.
    sec
    lda platform_data+3, y
    sbc #PLAYER_FOOT_BOTTOM_Y
    sta contact_y

    ; Skip if the old body bottom was already at or below the surface.
    lda pos_y+1
    cmp contact_y
    bcs @end_platform_check

    ; A downward crossing is a floor hit.
    lda next_y+1
    cmp contact_y
    bcs @floor_contact

    ; Standing on the floor also counts as contact, even before gravity moves
    ; a whole pixel. This lets a released jump rearm on any standing update.
    ; Do not attach an upward-moving player or one still above this floor.
    lda vel_y+1
    bmi @end_platform_check
    lda contact_y
    sec
    sbc #1
    cmp pos_y+1
    bne @end_platform_check
    cmp next_y+1
    bne @end_platform_check

@floor_contact:
    sec
    lda platform_data+3, y
    ; Correct player Y so the body bottom is one pixel above the map surface.
    sbc #PLAYER_FOOT_BOTTOM_Y+1

    ; Keep the highest crossed platform so collision does not depend on list
    ; order. Positive y is downward, so smaller y is closer to the start point.
    pha
    lda hit_y               ; Set Z if no recorded collision
    beq @store_first_hit    ; If set, compare y to cached hit_y_position
    pla                     ; A = player Y adjusted to stand on this platform
    cmp hit_y_position      ; C = candidate >= stored corrected Y
    bcs @end_platform_check ; keep the higher/closer floor already recorded
    jmp @store_hit          ; record the closer corrected player Y

@store_first_hit:
    pla

    ; Here, A = player Y adjusted to stand on this platform.

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
