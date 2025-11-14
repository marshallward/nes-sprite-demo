import numpy as np
import matplotlib.pyplot as plt

# Set the bounce height
h = 16
v0 = np.sqrt(2 * h)
t_max = v0

# Number of frames (~1 sec bounce)
n = 60

# Start with a kinematic timeseries
t = np.linspace(0, 2*t_max, n)
v = v0 - t
y = v0 * t - 0.5 * t**2

# build the lookup table

# Positions?
#print(".byte: " + ", ".join(str(int(yp)) for yp in np.round(y)))

# No, displacements are more useful
# Also, down is "up" on the TV screen
print("    .byte " + ", ".join("<"+str(int(-vp)) for vp in np.round(v)))

# verify no total displacement
assert np.sum(np.round(v)) == 0
