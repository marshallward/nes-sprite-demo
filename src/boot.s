.setcpu "6502"
.segment "CODE"

.include "ppu.inc"
.include "apu.inc"

;; CPU setup

reset:
    ; Disable maskable CPU interrupts
    ; (This disables IRQs but not NMIs.)
    sei

    ; Disable BCD (decimal) arithmetic
    cld

    ; Disable APU frame IRQs
    ldx #%10000000
    stx APU_FRAMECNT

    ; Initialize CPU stack pointer to 0x01ff
    ldx #$ff
    txs

    ; Set X to zero (by overflow)
    inx

    ; PPUCTRL: Disable vblank NMI (and normalize other data)
    stx PPUCTRL
    
    ; PPUMASK: Disable tiles and sprites, and color emphasis
    ; The PPU must be disabled before modifying the memory.
    stx PPUMASK

    ; Disable the sound DMC (delta modulation channel) interrupt and DMA.
    ;
    ; The DMC is the only audio channel that uses interrupts and DMA reads.
    ; (DMA is direct memory access, an automated transfer launched by the CPU.)
    stx APU_DMCFREQ


;; PPU boot

; The CPU starts before the PPU, whose registers may not yet be reliable.
; Wait two vblank cycles for the PPU to restart.

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
