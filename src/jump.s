; Jump physics

; For now take this address from main, but maybe it should be an input?
.importzp pos_y

; Jump management reads directly from `buttons`, but we could decouple it.
.importzp buttons

.export init_jump
.export update_jump

; These three variables define "jump state", and could be passed as inputs.
.segment "ZEROPAGE"
    ; 8.8 pixel resolution
    vel_y: .res 2
    acc_y: .res 2

    ; Set during jump, disables jump start until landing.
    jump_latch: .res 1


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
    sta acc_y+1
    sta jump_latch
    rts

    ;; (old jump notes.. clean up)

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

    ; Version 1: outer button test
    ;
    ; Button?
    ;   latch?
    ;     v > 0?
    ;       g = g_press
    ;     else
    ;       g = g_down
    ;   else
    ;     v = v0
    ; else
    ;   y > 0?
    ;     latch = 0
    ;   else
    ;     v > 0?
    ;       g = g_up
    ;     else
    ;       g = g_down


    ; Version 2: v > 0 outer
    ;
    ; v > 0? (up)
    ;   button?
    ;     g = g_press
    ;   else
    ;     g = g_up
    ; else
    ;   latch?
    ;     g = g_down
    ;   else
    ;     button and y = GROUND?
    ;       v = v0
    ;       latch = 1


    ; Version 3?
    ;
    ; v <= 0?
    ;   g = g_down
    ;   if (no latch and no button and y >= 160)
    ;     v = v0
    ;     latch = 1
    ; else ; v > 0
    ;   button?
    ;     g = g_press
    ;   else:
    ;     g = g_up
    ;
    ; @apply_accel
    ;

    ;; Jump mechanics

    ;; Apply impulse velocity and compute acceleration
    ; (This implements version 2, but 3 may be simpler)

update_jump:
    ; Is velocity upward?
    lda vel_y+1
    bpl @jump_down      ; minus is up!
;@jump_up
    lda buttons
    and #%10000000
    beq @vel_up_release
;@vel_up_press:
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
    ; Update velocity
    lda vel_y
    clc
    adc acc_y
    sta vel_y
    ; Keep the carry bit this time
    lda vel_y+1
    adc acc_y+1
    sta vel_y+1

    ; Update position
    lda pos_y
    clc
    adc vel_y
    sta pos_y
    lda pos_y+1
    adc vel_y+1
    sta pos_y+1

    ;; Stop if pos_y is below ground
    ;lda pos_y+1        ; NOTE: pos_y+1 is already in A
    cmp #160            ; C = pos_y >= 160
    bcc @skip_ground    ; Jump if pos_y < 160 (above ground)
    lda #160
    sta pos_y+1
    lda #0
    sta vel_y
    sta vel_y+1
    sta acc_y
    sta acc_y+1
    lda buttons
    and #%10000000
    bne @skip_ground
    lda #0
    sta jump_latch
@skip_ground:

    rts
