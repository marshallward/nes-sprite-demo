#!/usr/bin/env python3
"""Characterize the existing physics, including quirks; do not fix it here.

Build the current ROM first, install py65, then run this file. Tests execute
the assembled 6502 routines without emulating the PPU, NMI, or joypad.
"""
from pathlib import Path
import re
import unittest

from py65.devices.mpu6502 import MPU


ROOT = Path(__file__).resolve().parents[1]
JUMP, LEFT, RIGHT = 0x80, 0x02, 0x01


class BaselinePhysicsTests(unittest.TestCase):
    def setUp(self):
        self.symbols = {}

        # Fetch and parse the output symbol table
        for line in (ROOT / "build/jump.dbg").read_text().splitlines():
            if not line.startswith("sym\t"):
                continue
            name = re.search(r'name="([^"]+)"', line)
            value = re.search(r'val=(0x[0-9a-fA-F]+)', line)
            if name and value:
                self.symbols[name[1]] = int(value[1], 16)

        # Create a virtual processor
        self.cpu = MPU()

        # Transfer the ROM into memory
        rom = (ROOT / "build/jump.nes").read_bytes()
        self.assertEqual(rom[:4], b"NES\x1a")
        self.assertEqual(rom[4], 1, "Harness expects one 16 KiB PRG bank")
        self.cpu.memory[0xC000:0x10000] = rom[16:16 + 0x4000]

        # Initialize movement and platform setup
        self.call("init_move")
        self.call("init_platforms")
        self.position(124, 160)

    # Support functions

    def get(self, name, offset=0):
        """Read one byte at the symbol address plus offset."""
        return self.cpu.memory[self.symbols[name] + offset]

    def put(self, name, value, offset=0):
        """Write lower byte of value at the symbol address plus offset."""
        self.cpu.memory[self.symbols[name] + offset] = value & 255

    def position(self, x, y, fraction=0):
        """Set player position, including the fractional byte of Y."""
        self.put("pos_x", x)
        self.put("pos_y", fraction)
        self.put("pos_y", y, 1)

    def velocity(self, fixed):
        """Set vertical velocity from a signed 8.8 fixed-point integer."""
        self.put("vel_y", fixed)
        self.put("vel_y", fixed >> 8, 1)

    def call(self, name):
        """Execute an assembly routine with a synthetic return address on the stack."""
        # RTS returns to an unused address, standing in for the game loop.
        self.cpu.sp = 255
        self.cpu.stPushWord(0x7FFF)
        self.cpu.pc = self.symbols[name]
        for _ in range(10000):
            self.cpu.step()
            if self.cpu.pc == 0x8000:
                return
        self.fail(f"{name} did not return")

    def frame(self, buttons=0):
        self.put("buttons", buttons)
        self.call("update_move")

    def platforms(self, *records):
        # Test-only writes to emulated ROM, not the on-disk game data.
        self.assertLessEqual(len(records), 3)
        address = self.symbols["platform_data"]
        data = [value for record in records for value in record]
        self.cpu.memory[address:address + len(data)] = data
        self.put("platform_count", len(records))

    def collision(self, x, old_y, next_y):
        self.position(x, old_y)
        self.put("next_y", next_y)
        self.call("apply_platform_collision")
        return self.get("platform_hit")

    def jump_state(self):
        return (
            self.get("pos_y", 1),
            self.get("pos_y"),
            self.get("vel_y", 1),
            self.get("vel_y"),
            self.get("jump_latch"),
        )

    # Unit tests

    def test_horizontal_input(self):
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 125)
        self.assertEqual(self.get("next_x"), 125)
        self.frame(LEFT)
        self.assertEqual(self.get("pos_x"), 124)
        self.frame(LEFT | RIGHT)
        self.assertEqual(self.get("pos_x"), 124)
        self.assertEqual(self.get("vel_x"), 0)

    def test_platform_edges_use_inclusive_two_foot_overlap(self):
        self.platforms((120, 135, 137))
        for x, hit in ((114, 0), (115, 1), (133, 1), (134, 0)):
            with self.subTest(x=x):
                self.assertEqual(self.collision(x, 136, 137), hit)
                if hit:
                    self.assertEqual(self.get("platform_hit_y"), 136)

    def test_crossing_requires_old_y_above_and_new_y_at_or_below(self):
        self.platforms((120, 135, 137))
        for old, new, hit in (
            (136, 136, 0),
            (136, 137, 1),
            (136, 145, 1),
            (137, 145, 0),
            (140, 136, 0),
        ):
            with self.subTest(old=old, new=new):
                self.assertEqual(self.collision(124, old, new), hit)

    def test_highest_crossed_platform_wins_in_either_order(self):
        for heights in ((185, 137, 105), (105, 137, 185)):
            with self.subTest(heights=heights):
                self.platforms(*[(0, 255, y) for y in heights])
                self.assertEqual(self.collision(124, 100, 190), 1)
                self.assertEqual(self.get("platform_hit_y"), 104)

    def test_collision_uses_world_x_not_camera_x(self):
        self.platforms((120, 135, 137))
        self.put("camera_x", 100)
        self.assertEqual(self.collision(124, 136, 137), 1)

    def test_empty_list_clears_hit(self):
        self.platforms()
        self.put("platform_hit", 1)
        self.assertEqual(self.collision(124, 136, 137), 0)

    def test_landing_corrects_integer_y_but_preserves_fraction(self):
        self.platforms((0, 255, 185))
        self.position(124, 183, fraction=200)
        self.velocity(256)
        self.put("jump_latch", 1)
        self.frame()
        self.assertEqual(self.get("pos_y", 1), 184)
        self.assertEqual(self.get("pos_y"), 4)  # (200 + 256 + 60) & 255
        self.assertEqual(self.get("vel_y"), 0)
        self.assertEqual(self.get("vel_y", 1), 0)
        self.assertEqual(self.get("jump_latch"), 0)

    def test_default_spawn_falls_to_existing_ground(self):
        # Leave the game's actual platform records untouched for this test.
        for _ in range(60):
            self.frame()
        self.assertEqual(self.get("pos_y", 1), 184)
        self.assertEqual(self.get("pos_x"), 124)

    def test_stationary_integer_y_stays_one_pixel_above_ground(self):
        self.platforms((0, 255, 185))
        self.position(124, 184)
        for _ in range(120):
            self.frame()
            self.assertEqual(self.get("pos_y", 1), 184)
        # Fractional Y/velocity need not be zero between collision frames.

    def test_horizontal_commit_precedes_platform_test(self):
        self.platforms((120, 135, 137))
        self.position(114, 136, fraction=250)
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 115)
        self.assertEqual(self.get("platform_hit"), 1)
        self.assertEqual(self.get("pos_y", 1), 136)

    def test_walking_off_edge_begins_falling(self):
        self.platforms((120, 135, 137))
        self.position(133, 136, fraction=250)
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 134)
        self.assertEqual(self.get("platform_hit"), 0)
        self.assertEqual(self.get("pos_y", 1), 137)

    def test_initial_jump_frame_uses_downward_gravity_constant(self):
        self.platforms((0, 255, 185))
        self.position(124, 184)
        self.frame(JUMP)
        # -3.5 impulse + 60/256 gravity, not held-ascent gravity (15/256).
        self.assertEqual(self.jump_state(), (180, 188, 252, 188, 1))

    def test_release_and_repress_changes_ascent_gravity(self):
        self.platforms((0, 255, 185))
        self.position(124, 184)
        self.frame(JUMP)
        self.frame()
        self.assertEqual(self.get("acc_y"), 60)
        self.assertEqual(self.get("jump_latch"), 1)
        self.frame(JUMP)
        self.assertEqual(self.get("acc_y"), 15)
        self.assertEqual(self.get("jump_latch"), 1)

    def test_held_and_released_jump_timing(self):
        # Recorded from the current assembly, starting at Y=184, fraction=0.
        # These snapshots deliberately preserve existing timing/rounding.
        cases = (
            (False, 159, 13, 30, (184, 252, 0, 0, 0)),
            (True, 91, 52, 85, (184, 248, 0, 0, 1)),
        )
        for held, apex_y, apex_frame, landing_frame, landing_state in cases:
            with self.subTest(held=held):
                self.call("init_move")
                self.platforms((0, 255, 185))
                self.position(124, 184)
                minimum, first_minimum, landed = 184, None, None
                for frame in range(1, 121):
                    self.frame(JUMP if held or frame == 1 else 0)
                    y = self.get("pos_y", 1)
                    if y < minimum:
                        minimum, first_minimum = y, frame
                    if self.get("platform_hit"):
                        landed = frame
                        break
                self.assertEqual((minimum, first_minimum), (apex_y, apex_frame))
                self.assertEqual(landed, landing_frame)
                self.assertEqual(self.jump_state(), landing_state)

    def test_release_on_ground_waits_for_collision_to_clear_latch(self):
        self.platforms((0, 255, 185))
        self.position(124, 184)
        self.put("jump_latch", 1)
        for _ in range(2):
            self.frame()
            self.assertEqual(self.get("platform_hit"), 0)
            self.assertEqual(self.get("jump_latch"), 1)
        self.frame()
        self.assertEqual(self.get("platform_hit"), 1)
        self.assertEqual(self.get("jump_latch"), 0)

    def test_jump_latch_rearms_only_on_a_released_landing(self):
        self.platforms((0, 255, 185))
        self.position(124, 184)
        self.frame(JUMP)
        for _ in range(150):
            self.frame(JUMP)
        self.assertEqual(self.get("pos_y", 1), 184)
        self.assertEqual(self.get("jump_latch"), 1)
        self.frame()
        # Release alone need not clear the latch until another collision.
        for _ in range(5):
            self.frame()
        self.assertEqual(self.get("jump_latch"), 0)
        self.frame(JUMP)
        self.assertGreaterEqual(self.get("vel_y", 1), 128)

    def test_current_jump_rule_allows_impulse_during_slow_fall(self):
        # Characterization, not a desired-behavior assertion: integer vel_y
        # zero is currently sufficient, even away from any platform.
        self.platforms()
        self.position(124, 160)
        self.velocity(100)
        self.frame(JUMP)
        self.assertEqual(self.jump_state(), (156, 188, 252, 188, 1))

    def test_downward_integer_velocity_blocks_impulse_and_sets_latch(self):
        self.platforms()
        self.velocity(256)
        self.frame(JUMP)
        self.assertEqual(self.jump_state(), (161, 60, 1, 60, 1))


if __name__ == "__main__":
    unittest.main()
