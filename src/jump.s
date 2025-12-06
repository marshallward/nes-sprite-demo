; Jump physics

; For now take this address from main, but maybe it should be an input?
.importzp pos_x
.importzp pos_y
.importzp scroll_x

; Jump management reads directly from `buttons`, but we could decouple it.
.importzp buttons

.export init_jump
.export update_jump

; These variables define "jump state", and could be passed as inputs.
.segment "ZEROPAGE"
    ; 8.8 px resolution
    vel_y: .res 2
    ; 0.8 resolution (acc is never >= 1 px/f)
    acc_y: .res 1

    ; y_pos precompute, to check if a platform has been crossed.
    ; NOTE: This only need to be 8.0 precision, but I could imagine moving
    ;   platforms be defined as subpixel.
    next_y: .res 1

    ; Set during jump, disables jump start until landing.
    jump_latch: .res 1


;; This is a temporary platform buffer.  But it could be updated as the player
;; moves through the level.
.segment "RODATA"

;platform_x0:
;    .byte 0, 120, 136
;platform_x1:
;    .byte 120, 136, 255
;platform_y0:
;    .byte 184, 120, 184
;PLATFORM_COUNT = 3
platform_x0:
    .byte 0, 120
platform_x1:
    .byte 255, 136
platform_y0:
    .byte 185, 121
PLATFORM_COUNT = 2


; Jump parameters (positive is downward)
VEL_JUMP_LO = 128
VEL_JUMP_HI = <-4
; All acceleration is sub-pixel
G_UP = 60
G_PRESS = 15
G_DOWN = 60


.setcpu "6502"
.segment "CODE"

init_jump:
    ; Initialize kinematic state
    lda #0
    sta vel_y
    sta vel_y+1
    sta acc_y
    sta jump_latch
    rts

    ;; Jump kinematics

    ; We only start a new jump if the last jump has completed.
    ;
    ; The conditions for completion are
    ; 1. We have reached the ground (y <= GROUND)
    ;   (TODO: ground collision detection)
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
    ; TODO: We may want to "latch" this to only permit a single release.
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

;@jump_start:
    ; Do not apply impulse if latch is set.
    ; This is also an implicit on-the-ground test.
    ; TODO: Except it doesn't account for running off a ledge!
    lda jump_latch
    bne @jump_end

    ; Is the button pressed?
    lda buttons
    and #%10000000
    beq @jump_end

    ; Latch is unset, and button is pressed.  Apply impulse velocity and latch.
    lda #VEL_JUMP_LO
    sta vel_y
    lda #VEL_JUMP_HI
    sta vel_y+1
    ; set the latch
    lda #1
    sta jump_latch
@jump_end:


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

    ;; Update position
    clc
    ; Subpixel
    lda pos_y
    adc vel_y
    sta pos_y
    ; Pixel
    lda pos_y+1
    adc vel_y+1
    ;sta pos_y+1
    sta next_y

    ; TODO: We might be able to avoid the need for next_y!
    ;   - We could apply the platform x-tests before computing pos_y+1
    ;   - We could then hold next_y in A for comparison tests.
    ;   ... or maybe not, but this seems plausible.

    ; This is more generic but still dumb.
    ; It only checks if you're below y0, so it's effectively just ground.
    ; A more advanced method would hold pos_y(n) and pos_y(n+1) and pass that
    ; the player passes through y0.
    ; If we're nitpicking, it also only checks vertically.

    ldx #0
@platform_loop:
    cpx #PLATFORM_COUNT
    beq @skip_ground

    ; Skip if x < x0
    clc
    lda pos_x
    adc scroll_x
    cmp platform_x0, x  ; C = pos_x >= x0(p)
    bcc @end_platform_check

    ; Skip if x > x0
    cmp platform_x1, x  ; C = pos_x >= x1(p)
    bcs @end_platform_check

    ; Have we crossed y0?
    ; NOTE: Load platform_y0, then only need one lda?

    ; Skip if we were already below y0(p) (pos_y > y0(p))
    lda pos_y+1
    cmp platform_y0, x  ; C = pos_y >= y0(p)
    bcs @end_platform_check

    ; Skip if the updated y_pos is still above y0(p) (next_y < y0(p))
    ;lda pos_y+1
    lda next_y
    cmp platform_y0, x  ; C = next_y >= y0(p)
    bcc @end_platform_check

    lda platform_y0, x
    ; Stay one point above the platform
    ; TODO: Maybe define so that y0 is where you stop, rather than the ground?
    sbc #1
    ;sta pos_y+1
    sta next_y
    lda #0
    sta vel_y
    sta vel_y+1
    sta acc_y
    lda buttons
    and #%10000000
    ;bne @skip_ground
    bne @end_platform_iter
    lda #0
    sta jump_latch
@end_platform_check:

    ; Finalize y_pos
    lda next_y
    sta pos_y+1
@end_platform_iter:

    inx ; next platform
    jmp @platform_loop

@skip_ground:

    rts
