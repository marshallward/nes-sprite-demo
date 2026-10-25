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

Hazard/death/respawn tests use the same built ROM and CPU harness::

    python3 tools/test_gameplay.py
