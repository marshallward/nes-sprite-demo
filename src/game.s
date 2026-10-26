; Minimal play -> death pause -> respawn. No health or knockback system yet.
.include "dash.inc"
.export init_game, update_game, death_timer
.import init_move, update_move, check_hazards
.import init_dash, update_dash
.importzp pos_x, pos_y, camera_x, ntable
.importzp hit_y

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
    jsr update_dash
    cmp #DASH_NONE
    beq @normal_move
    cmp #DASH_HAZARD
    beq @die
    rts                     ; dash checked collision and hazards along its path
@normal_move:
    jsr update_move
    jsr check_hazards        ; test the actual position after movement resolves
    bcc @done
@die:
    lda #DEATH_FRAMES
    sta death_timer
    jsr init_move           ; stop motion and clear the jump latch
    jsr init_dash
@done:
    rts

respawn_player:
    jsr init_move
    jsr init_dash
    lda #0
    sta pos_y
    sta pos_x
    sta camera_x
    sta ntable
    sta hit_y              ; the spawn starts in the air, not on the old floor
    lda #SPAWN_X
    sta pos_x+1
    lda #SPAWN_Y
    sta pos_y+1
    rts
