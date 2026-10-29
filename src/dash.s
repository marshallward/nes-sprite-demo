; Double-tap input, burst velocity selection, and surface-launch momentum.
.include "dash.inc"
.importzp buttons, buttons_prev
.importzp vel_x, vel_y, hit_x, hit_y, hit_y_slope
.export init_dash, read_dash, update_dash, finish_dash_move

DASH_TAP_WINDOW = 12
DASH_SPEED = 8
DASH_FRAMES = 8

DASH_AIR = 0
DASH_SURFACE = 1
DASH_LAUNCH = 2

.segment "ZEROPAGE"
    dash_tap_direction: .res 1
        ; first tap: Right=1, Left=2
    dash_tap_timer: .res 1
        ; remaining updates for the second press
    dash_timer: .res 1
        ; remaining burst updates (separate from the second-tap window)
    dash_velocity: .res 1
        ; signed horizontal velocity, fixed for the burst
    dash_mode: .res 1
        ; surface bursts can become launches; air-started bursts stay horizontal

.setcpu "6502"
.segment "CODE"

init_dash:
    lda #0
    sta dash_tap_direction
    sta dash_tap_timer
    sta dash_timer
    sta dash_velocity
    sta dash_mode
    rts

update_dash:
    ; Return DASH_NONE, DASH_BURST or DASH_COAST (see dash.inc).
    jsr read_dash
    tax

    ; A fresh supported jump interrupts a surface burst and wins over a tap.
    lda hit_y
    beq @check_burst
    lda buttons_prev
    eor #$FF
    and buttons
    and #%10000000
    beq @check_burst
    lda #0
    sta dash_timer
    sta dash_mode
    sta dash_tap_direction
    sta dash_tap_timer
    rts

@check_burst:
    lda dash_timer
    bne @burst              ; input cannot steer or restart an active burst

    txa
    beq @no_burst
    cmp #$FF
    beq @start_left
    lda #DASH_SPEED
    jmp @start
@start_left:
    lda #<-DASH_SPEED
@start:
    sta dash_velocity
    lda hit_y
    beq @start_air
    lda #DASH_SURFACE
    bne @store_mode
@start_air:
    lda #DASH_AIR
@store_mode:
    sta dash_mode
    lda #DASH_FRAMES
    sta dash_timer

@burst:
    ; Don't queue a double-tap for after the burst.
    lda #0
    sta dash_tap_direction
    sta dash_tap_timer
    lda dash_velocity
    sta vel_x

    lda dash_mode
    cmp #DASH_LAUNCH
    beq @keep_vertical      ; carry the slope-exit velocity during the burst
    lda #0
    sta vel_y
    sta vel_y+1
    lda dash_mode
    cmp #DASH_SURFACE
    bne @keep_vertical      ; an air-started burst is horizontal

    ; Surface velocity follows the supporting gradient (0, -1 or -2).
    lda hit_y_slope
    beq @keep_vertical
    lda dash_velocity
    eor #$FF
    clc
    adc #1                  ; a rightward slope rises: negate horizontal speed
    ldx hit_y_slope
    cpx #$FE
    bne @store_vertical
    asl a                   ; 2:1 slope
@store_vertical:
    sta vel_y+1
@keep_vertical:
    dec dash_timer
    lda #DASH_BURST
    rts
@no_burst:
    lda dash_mode
    cmp #DASH_LAUNCH
    bne @normal
    lda dash_velocity
    sta vel_x
    lda #DASH_COAST
    rts
@normal:
    lda #DASH_AIR
    sta dash_mode
    lda #DASH_NONE
    rts

finish_dash_move:
    ; Called after ordinary collision resolution, before position commit.
    lda hit_x
    bne @stop               ; walls stop bursts and airborne horizontal momentum
    lda hit_y
    beq @unsupported
    lda dash_mode
    cmp #DASH_SURFACE
    beq @done               ; floor contact supports a surface burst
@stop:
    lda #0
    sta dash_timer
    sta dash_mode
    rts
@unsupported:
    lda dash_mode
    cmp #DASH_SURFACE
    bne @done
    lda #DASH_LAUNCH
    sta dash_mode           ; retain the velocity already selected from the slope
@done:
    rts

read_dash:
    ; Return A = $01 (right double-tap)
    ;            $FF (left double-tap)
    ;            $00 (no double-tap)
    lda buttons_prev
    eor #$FF                ; 1 if button was unpressed last frame
    and buttons             ; 1 if button was pressed on this frame
    and #%00000011          ; Restrict to left-right
    tax                     ; Store newly pressed buttons to X

    ; Cancel a double-tap read if both buttons are pressed
    lda buttons
    and #%00000011
    cmp #%00000011
    beq @clear_double_tap

    ; Check for a double-tap

    txa
    ; If no tap, then exit
    beq @no_new_tap

    ; If the direction changed, renew the tap
    cmp dash_tap_direction
    bne @set_first_tap

    ; If the timer expired, renew the tap
    lda dash_tap_timer
    beq @set_first_tap

    lda #0
    sta dash_tap_timer
    sta dash_tap_direction

    ; Double tap achieved: return the direction
    txa
    cmp #%00000010
    beq @return_left
;return_right:
    lda #1
    rts
@return_left:
    lda #$FF
    rts

@set_first_tap:
    ; Store direction and reset timer
    stx dash_tap_direction
    lda #DASH_TAP_WINDOW
    sta dash_tap_timer
    jmp @no_double_tap

@no_new_tap:
    ; Skip the countdown if already empty
    lda dash_tap_timer
    beq @no_double_tap

    ; Countdown timer
    dec dash_tap_timer
    jmp @no_double_tap

@clear_double_tap:
    ; Forget the first tap and its remaining window.
    lda #0
    sta dash_tap_timer
    sta dash_tap_direction
@no_double_tap:
    lda #0
    rts
