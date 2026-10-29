; Player movement physics
.include "dash.inc"

; For now take this address from main, but maybe it should be an input?
.importzp pos_x
.importzp pos_y
.importzp camera_x
.importzp ntable
.importzp hit_y
.importzp hit_y_position
.importzp hit_x
.importzp hit_x_position

; Movement reads directly from `buttons`, but we could decouple it.
.importzp buttons

.import apply_platform_collision
.import init_dash, update_dash, finish_dash_move

.export init_move
.export update_move
.exportzp vel_x
.exportzp vel_y
.exportzp next_x
.exportzp next_y

; These variables define movement state, and could be passed as inputs.
.segment "ZEROPAGE"
    ; Signed pixels/frame. Currently fixed to -1, 0, or 1.
    vel_x: .res 1

    ; x_pos precompute, to check if a wall has been crossed.
    next_x: .res 1

    ; 8.8 px resolution
    vel_y: .res 2
    ; 0.8 resolution (acc is never >= 1 px/f)
    acc_y: .res 1

    ; Proposed 8.8 Y, like pos_y: fractional byte first, integer byte second.
    ; Keep pos_y unchanged until collision finishes.
    next_y: .res 2

    ; Set during jump, disables new jumps until landing.
    jump_latch: .res 1

; Jump parameters (positive is downward)
VEL_JUMP_LO = 128
VEL_JUMP_HI = <-4
; All acceleration is sub-pixel
G_UP = 60
G_PRESS = 15
G_DOWN = 60

; Scrolling frame parameters
X_FRAME_MIN = 96
X_FRAME_MAX = 160

.setcpu "6502"
.segment "CODE"

init_move:
    ; Initialize kinematic state
    lda #0
    sta vel_x
    sta vel_y
    sta vel_y+1
    sta acc_y
    sta jump_latch
    sta next_x
    jmp init_dash


update_move:
    jsr update_dash
    cmp #DASH_BURST
    bne @normal_velocity

    ; Dash supplied velocity: skip gravity and prevent a new airborne jump.
    lda #0
    sta acc_y
    lda #1
    sta jump_latch
    jmp @propose

@normal_velocity:
    cmp #DASH_COAST
    beq @vertical_velocity  ; slope launch keeps horizontal momentum until contact
    jsr set_velocity_x
@vertical_velocity:
    jsr set_velocity_y

@propose:
    ; Propose movement using the selected velocities, then resolve contacts.
    jsr update_x
    jsr update_y
    jsr apply_move_collision
    jsr finish_dash_move

    ; Commit the corrected proposal only after collision has used old position.
    lda next_x
    sta pos_x
    lda next_y
    sta pos_y
    lda next_y+1
    sta pos_y+1

    jmp update_camera


set_velocity_x:
    lda #0
    sta vel_x

@check_right:
    lda buttons
    and #%00000001  ; A = buttons && 01
    beq @check_left
    inc vel_x

@check_left:
    lda buttons
    and #%00000010  ; A = buttons && 10
    beq @done
    dec vel_x

    ; NOTE: vel_x is zero if both 01 and 10 are pressed
@done:
    rts

update_x:
    ; Propose X without reading input or changing velocity.
    lda pos_x
    sta next_x

    lda vel_x
    beq @end_x

    clc
    lda next_x
    adc vel_x
    sta next_x
@end_x:
    rts

update_camera:
    ; Catch up toward the frame even when the player is stationary.
    ; Scroll 1 + (distance outside the frame / 4) pixels per update.
    ; Fast movement pushes farther outside, so the camera speeds up to follow.
    lda pos_x
    sec
    sbc camera_x
    cmp #X_FRAME_MAX+1
    bcs @scroll_right

    cmp #X_FRAME_MIN
    bcc @scroll_left

    rts

@scroll_right:
    sec
    sbc #X_FRAME_MAX
    lsr a
    lsr a
    clc
    adc #1
    clc
    adc camera_x
    sta camera_x
    bcc @end_x
    lda ntable
    eor #1
    sta ntable
    rts

@scroll_left:
    ; A is screen X. Compute X_FRAME_MIN - A without a scratch byte.
    eor #$FF
    clc
    adc #X_FRAME_MIN+1
    lsr a
    lsr a
    clc
    adc #1

    ; camera_x -= step. Addition's carry is set when there was no borrow.
    eor #$FF
    sec
    adc camera_x
    sta camera_x
    bcs @end_x
    lda ntable
    eor #1
    sta ntable

@end_x:
    rts

    ;; Jump kinematics

    ; We only start a new jump if the last jump has completed.
    ;
    ; The conditions for completion are
    ; 1. We have reached the ground (y <= GROUND)
    ;   (TODO: ground collision detection)
    ;   (DONE!)
    ; 2. The button has been released (buttons && $40 = 0)
    ;
    ; We then release the latch.
    ; So many conditions, lets just gather them:
    ;   - button (i.e. B is pressed)
    ;   - y > GROUND
    ;   - v > 0
    ;       - are we moving up or down?
    ;       - v = 0 is a concern: ground? top of parabola?
    ;   - latch is set

    ; Pseudocode
    ;
    ; v > 0:
    ;   button:
    ;     g = g_press
    ;   else:
    ;     g = g_up
    ; else (v <= 0):
    ;   g = g_down
    ;   if no latch and no button and y >= 160:
    ;     v = v0
    ;     latch = 1
    ;
    ; @apply_accel

set_velocity_y:
    ; Is velocity upward?
    lda vel_y+1
    bpl @jump_down      ; minus is up!
;@jump_up
    lda buttons
    and #%10000000
    beq @vel_up_release
;@vel_up_press:
    ; NOTE: This can create weird "floaty" effects if pressed multiple times.
    ; You can shoot up to a state with zero velocity and low gravity, which
    ; can feel a bit unnatural.
    ; TODO: We want to "latch" this to only permit a single release.
    lda #G_PRESS
    sta acc_y
    jmp @jump_end
@vel_up_release:
    lda #G_UP
    sta acc_y
    jmp @jump_end

@jump_down:
    lda #G_DOWN
    sta acc_y

    ;; Acceleration is set, but now check for impulse force.

    ; Do not apply impulse if latch is set.
    lda jump_latch
    bne @jump_end

    ; Is the button pressed?
    lda buttons
    and #%10000000
    beq @jump_end

    ; Currently we do not jump if velocity is downward.
    ; But this could be changed here.
    lda vel_y+1
    bne @jump_set_latch

    ; Latch is unset, and button is pressed.  Apply impulse velocity and latch.

    ; If velocity is zero then we're on the ground and apply impulse
    lda #VEL_JUMP_LO
    sta vel_y
    lda #VEL_JUMP_HI
    sta vel_y+1
    ;jmp @jump_set_latch

@jump_set_latch:
    ; set the latch
    lda #1
    sta jump_latch

@jump_end:
    ; Jump acceleration and impulse force complete.

@apply_accel:
    ;; Update velocity
    clc
    ; Subpixel
    lda vel_y
    adc acc_y
    sta vel_y
    ; Pixel (carry bit)
    bcc :+
    inc vel_y+1
:

    rts

update_y:
    ; Propose Y without changing velocity or applying gravity again.
    clc
    ; Subpixel
    lda pos_y
    adc vel_y
    sta next_y
    ; Pixel
    lda pos_y+1
    adc vel_y+1
    sta next_y+1
    rts


apply_move_collision:
    ; Gather floor/wall contacts for the proposed movement.
    jsr apply_platform_collision

    ; NOTE:
    ; If horizontal velocity is nonzero, then a floor-correcting collision
    ; could position the player past a joining wall.  This runs an extra
    ; collision test to account for such a displacement.
    ;
    ; Without correction
    ;
    ;     ● start
    ;      \
    ; ──────\──+     <-- platform
    ;        \ |
    ;         \|
    ;          x     <-- wall collision
    ;          |\
    ;          | ●   <-- non-collision endpoint
    ;
    ; With second correction
    ;
    ;     ● start
    ;      \
    ; ──────●──+  continue horizontally
    ;          |
    ;          |  wall is below the corrected body
    ;
    ; XXX: This should probably be fixed in apply_platform_collision.
    ; XXX: It took frame counting to even notice this issue.  Ignore?

    ; The following attempts to resolve this issue by replacing next_y with the
    ; first collision test result and repeating, but I had issues with its
    ; implementation so I'm leaving it turned off for now.  But we will come
    ; back to it.

    ;; Confirm a (1) floor hit, (2) horizontal displacement, (3) Y correction.
    ;lda hit_y
    ;beq @apply_wall
    ;lda vel_x
    ;beq @apply_wall
    ;lda hit_y_position
    ;cmp next_y+1
    ;beq @apply_wall

    ;; Now replace next_y with the contact point and repeat the collision test.
    ;sta next_y+1
    ;pha
    ;jsr apply_platform_collision
    ;pla
    ;sta hit_y_position
    ;lda #1
    ;sta hit_y

@apply_wall:
    lda hit_x
    beq @check_floor
    lda hit_x_position
    sta next_x
    lda #0
    sta vel_x
@check_floor:
    ; Correct integer Y only; preserve the proposed fractional byte in next_y.
    lda hit_y
    beq @skip_ground

    lda hit_y_position
    sta next_y+1
    lda #0
    sta vel_y
    sta vel_y+1
    sta acc_y
    lda buttons
    and #%10000000
    bne @skip_ground
    lda #0
    sta jump_latch

@skip_ground:
    rts
