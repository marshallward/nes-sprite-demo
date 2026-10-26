; Touch triggers only: these rectangles never correct movement.
.include "body.inc"
.include "spikes.inc"
.export check_hazards
.importzp pos_x, pos_y

.segment "RODATA"
; Inclusive map bounds: x0, x1, y0, y1. No runtime count or scratch RAM.
hazard_data:
    .byte SPIKES_X0, SPIKES_X1, SPIKES_Y0, SPIKES_Y1
hazard_data_end:
HAZARD_STRIDE = 4
NUM_HAZARDS = (hazard_data_end - hazard_data) / HAZARD_STRIDE

.setcpu "6502"
.segment "CODE"
check_hazards:
    ; C=1 if the committed player body touches a hazard; otherwise C=0.
    ldy #0
    ldx #NUM_HAZARDS
@loop:
    cpx #0
    beq @safe
    clc
    lda pos_x+1
    adc #PLAYER_BODY_R_X
    bcs :+                  ; a right edge beyond 255 is beyond every x0
    cmp hazard_data, y
    bcc @next
:
    clc
    lda pos_x+1
    adc #PLAYER_BODY_L_X
    bcs @next
    cmp hazard_data+1, y
    beq :+
    bcs @next
:
    clc
    lda pos_y+1
    adc #PLAYER_BODY_BOTTOM_Y
    bcs :+
    cmp hazard_data+2, y
    bcc @next
:
    clc
    lda pos_y+1
    adc #PLAYER_BODY_TOP_Y
    bcs @next
    cmp hazard_data+3, y
    beq @hit
    bcc @hit
@next:
    tya
    clc
    adc #HAZARD_STRIDE
    tay
    dex
    jmp @loop
@safe:
    clc
    rts
@hit:
    sec
    rts
