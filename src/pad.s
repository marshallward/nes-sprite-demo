JOYPAD1 = $4016
JOYPAD2 = $4017

; Setup fast IO in zeropage
.segment "ZEROPAGE"
buttons: .res 1
.exportzp buttons


.setcpu "6502"
.segment "CODE"

read_joypad1:
    ; The NES controller is read in two stages:
    ;
    ; 1. Tell the controller to read the values.
    ;
    ;   - Set bit0 and release the latch
    ;   - Unset bit0 to close the latch
    ; 
    ; 2. Pass the results serially from controller to CPU.
    ;
    ;   - Read bit0 of $4016 eight times.  Buttons are reported in this order:
    ;       A, B, Select, Start, Up, Down, Left, Right
    ;
    ;   - While not necessary, these are typically stored as bitshifts, which
    ;     produce typical bitmasks with A for bit7 and Right for bit0.
    ;
    ; There are a few speedup hacks here, noted in the comments.
    ;
    ; Release JOYPAD1 latch
    lda #$01
    sta JOYPAD1
 
    ; We store $01 to `buttons` so that the eighth bitshift sets the Carry bit.
    ; This lets Carry act as a 8-loop counter.
    sta buttons

    ; Restore JOYPAD1 latch
    lda #$00
    sta JOYPAD1

    ; Read data
@loop:
    lda JOYPAD1
    ; Shift bit0 of JOYPAD1 to Carry
    lsr a
    ; Shift Carry to bit0 of `buttons`, and bit7 to Carry
    rol buttons
    ; Break if Carry is set, which happens after 8 iterations.
    bcc @loop
    ; Return to game
    rts

.export read_joypad1
