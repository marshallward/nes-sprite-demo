.include "ppu.inc"
.include "apu.inc"

.macro INITIALIZE_NES
    ; Disable maskable CPU interrupts
    sei

    ; Disable BCD arithmetic
    ; NOTE: The 2A03 chip has no D flag, so this does nothing.
    ;cld

    ; Disable APU frame interrupts
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
    ; (The PPU must be disabled before modifying the memory.)
    stx PPUMASK

    ; Disable the sound DMC (delta modulation channel) interrupt and DMA.
    ;
    ; The DMC is the only audio channel that uses interrupts and DMA reads.
    ; (DMA is direct memory access, an automated transfer launched by the CPU.)
    stx APU_DMCFREQ

;; Wait for PPU synchronization
    WAIT_FOR_VBLANK
    WAIT_FOR_VBLANK
.endmacro
