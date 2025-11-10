.setcpu "6502"
.segment "CODE"

.include "ppu.inc"
.include "boot.inc"

;; CPU setup
reset:
    INITIALIZE_NES

;; Wait for PPU synchronization
    WAIT_FOR_VBLANK
    WAIT_FOR_VBLANK

;; Render pink background

    ; Reset PPU latch and set PPU RAM address
    lda PPUSTATUS
    SET_PPUADDR $3f00

    ; Write color $07 to PPUDATA, which writes to $3f00
    lda #$1a
    sta PPUDATA

    ; Enable background rendering
    SET_PPUMASK #%00001000


;; Main loop

main:
    jmp main


; Interrupts (return to program)

nmi:
    rti

irq:
    rti


; Vector interrupt table
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
