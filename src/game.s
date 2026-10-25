; Minimal play -> death pause -> respawn. No health or knockback system yet.
.export init_game, update_game, death_timer
.import init_move, update_move, check_hazards
.importzp pos_x, pos_y, camera_x, ntable

SPAWN_X = 124
SPAWN_Y = 160
DEATH_FRAMES = 45            ; about 3/4 second at NTSC rate

.segment "BSS"
death_timer: .res 1          ; ordinary RAM, not zero page; zero means alive

.setcpu "6502"
.segment "CODE"
init_game:
    lda #0
    sta death_timer
    jmp respawn_player

update_game:
    lda death_timer
    beq @alive
    dec death_timer
    beq respawn_player
    rts                     ; no movement/input response during death pause
@alive:
    jsr update_move
    jsr check_hazards        ; test the actual position after movement resolves
    bcc @done
    lda #DEATH_FRAMES
    sta death_timer
    jsr init_move           ; stop motion and clear the jump latch
@done:
    rts

respawn_player:
    jsr init_move
    lda #0
    sta pos_y
    sta camera_x
    sta ntable
    lda #SPAWN_X
    sta pos_x
    lda #SPAWN_Y
    sta pos_y+1
    rts
