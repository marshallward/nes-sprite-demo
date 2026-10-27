Minimal NES ca65 sprite example
===============================

A basic example which draws a square in the middle of the screen, and is moved
around by the controller.  Very Atari 2600!

This is also an example of how to read the controller.

To build the ROM:

* Install the cc65 toolchain: https://cc65.github.io/

* Make the ROM::

    make

The default path of the ROM is ``build/jump.nes``.

Spike demo
----------

There is a two-tile spike patch on the ground to the right of the raised ledge
(world X=208..223). Touching its rectangular danger area is lethal. The player
disappears for 45 updates, then respawns at the original safe starting position.
Jump before reaching the tips to clear them. No health, lives, or knockback yet.
Reset after rebuilding instead of loading an old save state.

Air dash
--------

Double-tap Left or Right (release between presses, second press within 12 updates)
to dash, on the ground or in the air. A only jumps; B is unassigned. The player dashes
8 pixels per update for 8 updates, holding height until the burst finishes.
One dash is available per airtime, recharged on landing. Holding a direction
does not retrigger. The selected direction stays fixed for
the burst, and both directions share the one-air-dash limit. Wall or floor contact ends the burst,
and spikes remain lethal. This is a dash through space, not a teleport.

On the ground or a slope, double-tap Left or Right (release between presses,
second press within 12 updates) to start a surface dash at the same speed.
It follows the surface, continues in air after an edge, and can be interrupted
by pressing A to jump. Holding a direction alone does not dash. B remains reserved.

Horizontal movement now uses 8.8 fixed-point like Y. Walking is set to 0.75
pixels/update for testing; dash remains 8 pixels/update. ``walk_speed`` in
``src/move.s`` is a two-byte ROM setting (``$00C0`` = 192/256). This adds fractional
precision, not a wider world; collision and rendering still use whole pixels.

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
The historical suites explicitly use a 1-pixel ROM speed fixture to preserve
their existing timing/position expectations. They execute the same movement
instructions, with only ``walk_speed`` data replaced in emulated memory.

Four tests are marked ``expectedFailure`` for deferred mixed floor/wall
resolution (the experimental rescan is disabled). Their assertions remain
intact; an unexpected success prompts review when that behavior is fixed.
One overflow-policy test is skipped because the floor overflow guards were
deliberately removed. Neither category means those issues are resolved.

Hazard/death/respawn tests use the same built ROM and CPU harness::

    python3 tools/test_gameplay.py

Dash behavior tests::

    python3 tools/test_dash.py

Surface double-tap tests::

    python3 tools/test_surface_dash.py

The subpixel-X suite tests the actual ROM default (no speed override)::

    python3 tools/test_subpixel_x.py
