; Dash input: two distinct presses of the same horizontal direction.
.importzp buttons, buttons_prev
.export init_dash, read_dash

DASH_TAP_WINDOW = 12

.segment "ZEROPAGE"
    dash_tap_direction: .res 1
        ; first tap: Right=1, Left=2
    dash_tap_timer: .res 1
        ; remaining updates for the second press

.setcpu "6502"
.segment "CODE"

init_dash:
    lda #0
    sta dash_tap_direction
    sta dash_tap_timer
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
