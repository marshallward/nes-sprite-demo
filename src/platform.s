; Platform data
;
; One list and traversal for flat/sloped floors and vertical walls.

; Subroutines
.export init_platforms
.export apply_platform_collision

; Platform collision output
.exportzp hit_y
.exportzp hit_y_position
.exportzp hit_x
.exportzp hit_x_position

; Platfomr collision input
.importzp pos_x
.importzp next_x
.importzp pos_y
.importzp next_y
.importzp vel_x
.importzp vel_y

.segment "ZEROPAGE"

platform_count:
    ; Number of platforms
    .res 1

hit_y:
    ; 1 if y-motion triggers a collision
    .res 1
hit_y_position:
    ; Collision-adjusted y position
    .res 1

hit_x:
    ; 1 if x-motion triggers a collision
    .res 1
hit_x_position:
    ; Collision-adjusted x position
    .res 1

old_contact_y:
    ; Sloped platform position at pos_x
    .res 1

contact_y:
    ; Sloped platform position at next_x
    .res 1

surface_offset:
    ; scratch X displacement, used in several calculations
    .res 1

.segment "RODATA"

; Platform types
; TODO: Create a mask-friendly format
PLATFORM_FLAT = $7F
PLATFORM_WALL = $80
PLATFORM_WALL_RIGHT = $81
PLATFORM_SLOPE_1_1 = 0
PLATFORM_SLOPE_2_1 = 1

platform_data:
    ; Platform format: type, start, end, position
    ;
    ; - Flat/sloped: slope, x0, x1, y0
    ; - walls: type, y0, y1, x0

platform_1:
    ; Continuous ground, including underneath ledges.
    .byte PLATFORM_FLAT, 0, 255, 192

    ; Floating platforms
platform_2:
    .byte PLATFORM_FLAT, 128, 143, 144
platform_3:
    .byte PLATFORM_FLAT, 128, 143, 112

    ; Raised ledge
platform_4:
    ; Its map tiles occupy X=160..191, Y=160..191.
    ; Wall bounds are unchanged pending a separate body-alignment review.
    .byte PLATFORM_WALL, 161, 200, 160
platform_5:
    .byte PLATFORM_FLAT, 160, 191, 160
platform_6:
    .byte PLATFORM_WALL_RIGHT, 161, 200, 191

platform_7:
    .byte PLATFORM_SLOPE_1_1, 31, 63, 192
platform_8:
    .byte PLATFORM_WALL_RIGHT, 161, 200, 63

platform_9:
    .byte PLATFORM_SLOPE_2_1, 95, 111, 192
platform_10:
    .byte PLATFORM_WALL_RIGHT, 161, 200, 111

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
PLAYER_BODY_L_X = 1
PLAYER_BODY_R_X = 6
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
    ldy #0
    ldx platform_count
@platform_loop:
    ; Exit after completing platform iteration
    cpx #0
    beq @end_platform_loop

    ; TODO: This checks against various wall types.  In the future:
    ;   - Reduce these checks to a simple masked test
    ;   - Consolidate walls and platforms -> no check at all!

    ; Check if wall
    ;   (Use bne to avoid a redundant jump)
    lda platform_data, y
    cmp #PLATFORM_WALL
    beq @wall
    cmp #PLATFORM_WALL_RIGHT
    bne :+
@wall:
    jsr check_wall
    jmp @end_platform_check
:
    cmp #PLATFORM_FLAT
    beq @surface
    cmp #PLATFORM_SLOPE_1_1
    beq @surface
    cmp #PLATFORM_SLOPE_2_1
    bne @end_platform_check
@surface:
    jsr check_surface

    ; Set up the next loop iteration.
@end_platform_check:
    ; NOTE: 4x iny would be smaller, but platform structure could change.
    tya
    clc
    adc #PLATFORM_STRIDE
    tay
    dex
    jmp @platform_loop

@end_platform_loop:
    rts


check_surface:
    ; Line-based collision has two criteria:
    ; * Line-crossing: Does P-Q cross the line drawn by A-B?
    ; * Segment-range: Does the crossing pass within the segment A-B?
    ;
    ; First do the segment-range test.
    ; TODO: This is the weaker x-only test: x0 <= x <= x1
    ;
    ; It does not consider displacments beyond this range.  The following
    ; passes through:
    ;
    ;  ● P
    ;   ╲
    ;    ╲
    ;   A─×───B
    ;      ╲
    ;       ● Q
    ;
    ; But this requires significantly more arithmetic, so we defer it for now.

    ; Pass through if x < x0
    clc
    lda next_x
    adc #PLAYER_FOOT_R_X    ; A = x(n+1) + x_foot_r
    cmp platform_data+1, y  ; C = A >= x0
    bcc @no_contact

    ; Pass through if x > x1
    clc
    lda next_x
    adc #PLAYER_FOOT_L_X    ; A = x(n+1) + x_foot_l
    cmp platform_data+2, y  ; C = A >= x1
    beq :+                  ; If Z, skip check
    bcs @no_contact
:

    ; TODO: These assume rightward slopes!  Leftward would use FOOT_L.
    ; TODO: We also should not be using this point!  See below.

    ; Compute the contact point at pos_x
    clc
    lda pos_x
    adc #PLAYER_FOOT_R_X    ; A = x(n) + x_foot_r
    jsr surface_y_at_x      ; A = sloped y at x
    sec
    sbc #PLAYER_FOOT_BOTTOM_Y
    sta old_contact_y

    ; Line-crossing test
    ; We use the "two-height" method.
    ;
    ;    ● P
    ;    │╲
    ;    │ ╲
    ;  A─┼──×──┼─B
    ;        ╲ │
    ;         ╲│
    ;          ● Q
    ;
    ; - Find the "contact_y" for P.x and Q.x along A-B
    ; - Compute the height displacements
    ; - If P is "above" AB, then collision is possible
    ; - If Q is "below" AB, then a collision occurs
    ;   (Assuming the segment test has passed)

    ; Skip if we started below the platform.
    lda pos_y+1         ; A = y(n)
    cmp old_contact_y   ; C = A >= old_contact_y
    bcs @no_contact

    ; Compute the contact point at next_x
    clc
    lda next_x
    adc #PLAYER_FOOT_R_X    ; A = x(n+1) + x_foot_r
    jsr surface_y_at_x      ; A = sloped y at x
    sec
    sbc #PLAYER_FOOT_BOTTOM_Y   ; Foot-adjusted bottom
    sta contact_y

    ; If y(n+1) < y(n) then we have crossed the platform and need "contact"
    lda next_y+1
    cmp contact_y
    bcs @floor_contact

    ; This block gives a more robust definition of contact:
    ; - Velocity is not upward
    ; - previous position (pos_y) was not on platform (old_contact_y)
    ;   (where "contact" is one pixel above the platform)
    ;
    ; This test prevents the jitter caused by a slope falling faster than
    ; gravity.  It forces "contact" during any movement.
    lda vel_y+1
    bmi @no_contact     ; If vel_y is upward (negative) then no contact
    lda old_contact_y
    sec
    sbc #1
    cmp pos_y+1
    bne @no_contact

    ; Contact has been established, use contact_y to adjust next_y

@floor_contact:
    ; Set position as one point above contact_y
    ; NOTE: Both are already adjusted for foot-displacement.
    lda contact_y
    sec
    sbc #1

    ; Check if new contact_y is above current highest hit_y_position.

    pha                     ; Store contact_y
    lda hit_y               ; Check for existing hits (Z unset)
    beq @store_first_hit    ; For new hits, skip the comparison

    pla                     ; Restore contact_y
    cmp hit_y_position      ; C = contact_y >= hit_y_position
    bcs @no_contact         ; If contact_y is below (greater), then skip
    jmp @store_hit          ; Otherwise, update hit_y_position
                            ; (and hop around the first-hit stack pop)

@store_first_hit:
    ; First-hit stack restore of contact_y
    pla

@store_hit:
    ; Contact was proven, and the new contact_y is the highest record.
    ; Store the new contact point as the new hit_y_position.
    sta hit_y_position
    lda #1
    sta hit_y

@no_contact:
    rts


surface_y_at_x:
    ; Inputs
    ;   A = position x (typically "foot" shifted)
    ;   Y = Platform offset (indexed)
    ; Return:
    ;   The sloped value of y for a given x
    ; Notes:
    ;   X and Y are preserved.  Scratch is shared, not per-platform
    ; state.
    sta surface_offset
    lda platform_data, y
    cmp #PLATFORM_FLAT
    bne @slope
    lda platform_data+3, y
    rts
@slope:
    ; Clamp surface_offset to x0 <= x <= x1 for the purpose of slope testing.
    ; This handles cases where a foot displacement or pos_x are outside range.
    ; TODO: IMO this feels like some redundancy in work!  Revisit.
    lda surface_offset
    cmp platform_data+1, y  ; C = A >= x0
    bcs :+
    lda platform_data+1, y  ; if x < x0, clamp to x0
:
    cmp platform_data+2, y  ; C = A >= x1
    bcc :+
    lda platform_data+2, y  ; if x >= x1, clamp to x1
:
    ; surface_offset = X - x0, where X is the clamped x.
    sec
    sbc platform_data+1, y
    sta surface_offset

    ; Check for a 1:1 slope or a 2:1 slope.
    ; TODO: This is not general-purpose, each slope needs a dedicated branch.
    ;   - positive slopes need asl loops, negative slopes need lsr.
    ;   - Maybe this was overengineered...
    lda platform_data, y
    cmp #PLATFORM_SLOPE_2_1
    bne @height             ; 1:1 : A = X - x0
    asl surface_offset      ; 2:1 : A = 2*(X - x0)
@height:
    ; Now "subtract" y0 (displacing the slope *upward* on the screen)
    ; (Note that positive is downward!)
    lda platform_data+3, y
    sec
    sbc surface_offset
    ; A is now the slope-displaced value of X
    rts


check_wall:
    ; Candidate detection only: never alter next_x/next_y or velocity here.
    lda vel_x
    bne :+
    rts
:
    ; One-sided right face permits outward/rightward movement from the ramp.
    lda platform_data, y
    cmp #PLATFORM_WALL_RIGHT
    bne @check_overlap
    lda vel_x
    bmi @check_overlap
    rts
@check_overlap:
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

    ; Old right edge must be left of or exactly at the wall.
    clc
    lda pos_x
    adc #PLAYER_BODY_R_X
    bcs @no_right_hit
    cmp platform_data+3, y
    beq :+
    bcs @no_right_hit
:

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

    ; Old left edge must be right of or exactly at the wall.
    clc
    lda pos_x
    adc #PLAYER_BODY_L_X
    bcs @no_left_hit
    cmp platform_data+3, y
    bcc @no_left_hit

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
