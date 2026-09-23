; Player movement physics

; For now take this address from main, but maybe it should be an input?
.importzp pos_x
.importzp pos_y
.importzp scroll_x
.importzp ntable
.importzp platform_hit
.importzp platform_hit_y

; Movement reads directly from `buttons`, but we could decouple it.
.importzp buttons

.import apply_platform_collision

.export init_move
.export update_move
.exportzp vel_x
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

    ; y_pos precompute, to check if a platform has been crossed.
    ; NOTE: This only need to be 8.0 precision, but I could imagine moving
    ;   platforms be defined as subpixel.
    next_y: .res 1

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
    rts


update_move:
    jsr update_x
    jsr update_jump
    rts


update_x:
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
    beq @apply_x
    dec vel_x

    ; NOTE: vel_x is zero if both 01 and 10 are pressed

@apply_x:
    lda pos_x
    sta next_x

    lda vel_x
    beq @end_x

    clc
    lda next_x
    adc vel_x
    sta next_x
    sta pos_x

@update_camera:
    ; Keep the translated screen position inside the frame.
    lda pos_x
    sec
    sbc scroll_x
    cmp #X_FRAME_MAX+1
    bcs @scroll_right

    cmp #X_FRAME_MIN
    bcc @scroll_left

    rts

@scroll_right:
    clc
    lda scroll_x
    adc #1
    sta scroll_x
    bcc @end_x
    lda ntable
    eor #1
    sta ntable
    rts

@scroll_left:
    sec
    lda scroll_x
    sbc #1
    sta scroll_x
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

update_jump:
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

    ;; Update free-motion position
    clc
    ; Subpixel
    lda pos_y
    adc vel_y
    sta pos_y
    ; Pixel
    lda pos_y+1
    adc vel_y+1
    sta next_y

    ; TODO: We might be able to avoid the need for next_y!
    ;   - We could apply the platform x-tests before computing pos_y+1
    ;   - We could then hold next_y in A for comparison tests.
    ;   ... or maybe not, but this seems plausible.

    ; Apply platform correction to next_y
    jsr apply_platform_collision
    lda platform_hit
    beq @skip_ground

    lda platform_hit_y
    sta next_y
    lda #0
    sta vel_y
    sta vel_y+1
    sta acc_y
    lda buttons
    and #%10000000
    ; TODO: So which is it?
    ;bne @skip_ground
    bne @skip_ground
    lda #0
    sta jump_latch

@skip_ground:
    ; Finalize y_pos
    lda next_y
    sta pos_y+1

    rts
