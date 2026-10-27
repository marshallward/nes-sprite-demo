; First dash prototype: one horizontal burst per airtime.
DASH_FRAMES = 8
DASH_PIXELS = 8
DASH_TAP_WINDOW = 12        ; release and press the same direction again in time

; update_dash returns one of these values in A.
DASH_NONE = 0               ; run ordinary movement this update
DASH_MOVED = 1              ; dash already handled movement and camera
DASH_HAZARD = 2             ; dash touched a hazard; enter the normal death path
