Minimal NES ca65 sprite example
===============================

A basic example which draws a square in the middle of the screen, and is moved
around by the controller.  Very Atari 2600!

This is also an example of how to read the controller.

To build the ROM:

* Install the cc65 toolchain: https://cc65.github.io/

* Make the ROM::

    make

The default path of the ROM is ``build/sprite.nes``.

Dash prototype
--------------

Double-tap Left or Right, releasing between presses, to burst in that direction.
The second press must be within 12 updates. A burst moves horizontally at
8 pixels/update for 8 updates. In air it holds height; on a surface it follows
the floor or slope. Dashing off a slope carries its upward/downward velocity
into the air. After that burst expires, gravity resumes while horizontal
momentum continues until landing or wall contact. A new air dash replaces that
momentum with a horizontal burst. A jumps and can interrupt a supported dash.
The one-dash-per-airtime limit is not implemented yet. See ``doc/dash.txt`` for
the incremental changes and current coordinate-boundary limitations.

The camera speeds up as the ball moves farther outside its tracking frame,
then slows back down as it catches up, so it can follow dash-speed movement.

Burst regression tests (requires ``py65``)::

    make
    python3 tools/test_dash.py

Baseline physics tests
----------------------

With ``py65`` installed in your Python environment, rebuild the current
branch and run::

    make -B
    python3 tools/test_baseline_physics.py

The tests execute the assembled movement/collision routines using symbols
from ``build/jump.dbg``. Rebuilding avoids testing stale artifacts after a
branch switch. No PPU, NMI, or controller hardware is emulated.

These are characterization tests: they preserve the current landing,
platform-edge, jump-timing, and latch behavior, including existing quirks.
They do not specify improved physics or change the game's assembly.

Four tests are marked ``expectedFailure`` for deferred mixed floor/wall
resolution (the experimental rescan is disabled). Their assertions remain
intact; an unexpected success prompts review when that behavior is fixed.
One overflow-policy test is skipped because the floor overflow guards were
deliberately removed. Neither category means those issues are resolved.
