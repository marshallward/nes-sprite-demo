; Double-tap Left/Right for a surface or air burst. A only jumps; B is unassigned.
.include "dash.inc"
.export init_dash, update_dash
.import apply_move_collision, update_camera, check_hazards, latch_jump
.importzp buttons, pos_x, pos_y, next_x, next_y, vel_x, vel_y, hit_x, hit_y

.segment "BSS"
dash_timer: .res 1
dash_used: .res 1
dash_button_down: .res 1     ; previous A bit
dash_steps: .res 1           ; loop counter; collision/hazard routines use X/Y
dash_direction: .res 1       ; signed step (-1 or +1), fixed for the burst
dash_surface: .res 1         ; ground burst follows contact until leaving an edge
dash_dirs_down: .res 1       ; previous Left/Right bits for distinct tap presses
dash_tap_direction: .res 1   ; direction of the first tap
dash_tap_timer: .res 1

.setcpu "6502"
.segment "CODE"
init_dash:
    lda #0
    sta dash_timer
    sta dash_used
    sta dash_button_down
    sta dash_steps
    sta dash_direction
    sta dash_surface
    sta dash_dirs_down
    sta dash_tap_direction
    sta dash_tap_timer
    rts

update_dash:
    ; hit_y describes the PREVIOUS update's support, including resting contact.
    ; Jump velocity is not a substitute: it is near zero at the jump apex too.
    lda hit_y
    beq :+
    lda dash_timer
    bne :+                  ; don't recharge during an active surface burst
    lda #0
    sta dash_used
:
    ; Newly pressed = current buttons AND NOT previous buttons.
    ; A can interrupt a supported burst to jump, but never starts an air dash.
    ; B stays unassigned.
    lda dash_button_down
    eor #$FF
    and buttons
    and #%10000000
    tax
    lda buttons
    and #%10000000
    sta dash_button_down
    txa
    beq @dash_input
    lda hit_y
    beq @dash_input
    lda dash_surface
    bne @ground_jump        ; A can jump out of a surface burst
    lda dash_timer
    bne @dash_input
@ground_jump:
    lda #0
    sta dash_timer
    sta dash_surface
    sta dash_used           ; jumping from actual support starts a new airtime
    sta dash_tap_timer
    sta dash_tap_direction
    lda #DASH_NONE          ; ordinary movement applies the normal jump impulse
    rts
@dash_input:
    jsr try_dash
    bcc @active
    sta dash_direction
    lda hit_y
    sta dash_surface
    bne @start
    jsr latch_jump          ; dash must not permit an airborne jump afterward
@start:
    lda #DASH_FRAMES
    sta dash_timer
    lda #1
    sta dash_used
    lda #0
    sta vel_y
    sta vel_y+1             ; cancel ascent/fall; gravity resumes from zero
    jmp @active
@active:
    lda dash_timer
    bne @burst
    lda #DASH_NONE
    rts

@burst:
    dec dash_timer
    lda #DASH_PIXELS
    sta dash_steps
@step:
    ; DASH_PIXELS one-pixel proposals, no update_y/gravity. Keep normal collision
    ; response, and test hazards after EVERY committed step, not just the end.
    ; Stop at either byte boundary rather than wrapping across the world page.
    lda dash_direction
    bmi @left_step
    lda pos_x+1
    cmp #255
    beq @blocked
    jmp @propose_x
@left_step:
    lda pos_x+1
    beq @blocked
@propose_x:
    clc
    adc dash_direction
    sta next_x+1
    lda pos_x              ; whole-pixel dash steps retain fractional X
    sta next_x
    lda #0
    sta vel_x
    lda dash_direction
    sta vel_x+1
    lda pos_y
    sta next_y
    lda pos_y+1
    sta next_y+1
    jsr apply_move_collision
    lda next_x
    sta pos_x
    lda next_x+1
    sta pos_x+1
    lda next_y
    sta pos_y
    lda next_y+1
    sta pos_y+1
    jsr check_hazards
    bcs @hazard
    lda hit_x
    bne @blocked
    lda hit_y
    beq @unsupported
    lda dash_surface
    bne @next_step          ; surface contact carries, rather than ends, this dash
    jmp @landed             ; landing still ends an air dash
@unsupported:
    lda dash_surface
    beq @next_step
    lda #0
    sta dash_surface        ; leaving the edge continues the remaining air burst
    jsr latch_jump          ; no free jump after walking/dashing off the edge
@next_step:
    dec dash_steps
    bne @step
    jmp @moved
@landed:
    lda #0
    sta dash_used
@blocked:
    lda #0
    sta dash_timer
    sta vel_x
    sta vel_x+1
    sta dash_surface
@moved:
    lda dash_timer
    bne :+
    lda #0
    sta dash_surface
:
    jsr update_camera      ; one camera update per game update, not per pixel
    lda #DASH_MOVED
    rts
@hazard:
    lda #0
    sta dash_timer
    lda #DASH_HAZARD
    rts


try_dash:
    ; C=1 and A=signed direction on a valid second tap; otherwise C=0.
    ; Track taps across takeoff/landing, but not during a burst or after air use.
    lda dash_dirs_down
    eor #$FF
    and buttons
    and #%00000011
    tax
    lda buttons
    and #%00000011
    sta dash_dirs_down
    cmp #%00000011
    beq @reset
    lda dash_timer
    bne @reset
    lda hit_y
    bne @eligible
    lda dash_used
    bne @reset
@eligible:
    txa
    cmp #1
    beq @tap
    cmp #2
    beq @tap
    lda dash_tap_timer
    beq @none
    dec dash_tap_timer
    jmp @none
@tap:
    cmp dash_tap_direction
    bne @first
    lda dash_tap_timer
    beq @first
    lda #0
    sta dash_tap_timer
    sta dash_tap_direction
    txa
    cmp #2
    beq @left
    lda #1
    sec
    rts
@left:
    lda #$FF
    sec
    rts
@first:
    txa
    sta dash_tap_direction
    lda #DASH_TAP_WINDOW
    sta dash_tap_timer
    jmp @none
@reset:
    lda #0
    sta dash_tap_timer
    sta dash_tap_direction
@none:
    clc
    rts
