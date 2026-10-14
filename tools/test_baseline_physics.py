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
PLATFORM_FLAT = 0
PLATFORM_WALL = 0xFF


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
        self.platform_capacity = self.get("platform_count")
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
        """Encode flat platforms from (start, end, height) test tuples."""
        self.platform_records(*[(PLATFORM_FLAT, *record) for record in records])

    def platform_records(self, *records):
        """Supply explicit (type, start, end, height) records."""
        # Test-only writes to emulated ROM, not the on-disk game data.
        self.assertLessEqual(len(records), self.platform_capacity)
        address = self.symbols["platform_data"]
        data = [value for record in records for value in record]
        self.cpu.memory[address:address + len(data)] = data
        self.put("platform_count", len(records))

    def collision(self, x, old_y, next_y):
        self.position(x, old_y)
        self.put("next_x", x)
        self.put("next_y", next_y, 1)
        self.call("apply_platform_collision")
        return self.get("hit_y")

    def jump_state(self):
        return (
            self.get("pos_y", 1),
            self.get("pos_y"),
            self.get("vel_y", 1),
            self.get("vel_y"),
            self.get("jump_latch"),
        )

    # Unit tests

    def test_wall_blocks_from_both_sides_and_clears_horizontal_velocity(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        for x, buttons in ((139, RIGHT), (144, LEFT)):
            with self.subTest(x=x, buttons=buttons):
                self.position(x, 120)
                self.frame(buttons)
                self.assertEqual(self.get("pos_x"), x)
                self.assertEqual(self.get("next_x"), x)
                self.assertEqual(self.get("hit_x_position"), x)
                self.assertEqual(self.get("hit_x"), 1)
                self.assertEqual(self.get("vel_x"), 0)
                self.assertEqual(self.get("hit_y"), 0)

    def test_wall_vertical_overlap_includes_endpoints(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        for y, hit in ((87, 0), (88, 1), (184, 1), (185, 0)):
            with self.subTest(y=y):
                self.position(139, y)
                self.velocity(0)
                self.frame(RIGHT)
                self.assertEqual(self.get("hit_x"), hit)
                self.assertEqual(self.get("pos_x"), 139 if hit else 140)

    def test_wall_overlap_uses_proposed_vertical_position(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        self.position(139, 87, fraction=250)
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_y", 1), 88)
        self.assertEqual(self.get("hit_x"), 1)
        self.assertEqual(self.get("pos_x"), 139)

    def test_moving_away_from_wall_is_not_blocked(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        for x, buttons, expected in ((139, LEFT, 138), (144, RIGHT, 145)):
            with self.subTest(x=x, buttons=buttons):
                self.position(x, 120)
                self.frame(buttons)
                self.assertEqual(self.get("hit_x"), 0)
                self.assertEqual(self.get("pos_x"), expected)

    def test_wall_hit_clears_on_stationary_update(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        self.position(139, 120)
        self.frame(RIGHT)
        self.assertEqual(self.get("hit_x"), 1)
        self.frame()
        self.assertEqual(self.get("hit_x"), 0)

    def test_nearest_wall_candidate_is_independent_of_record_order(self):
        for walls in ((145, 150), (150, 145)):
            for old_x, proposed_x, velocity, corrected_x in (
                (130, 155, 1, 139),
                (160, 130, 255, 149),
            ):
                with self.subTest(walls=walls, velocity=velocity):
                    self.platform_records(*[(PLATFORM_WALL, 96, 185, x) for x in walls])
                    self.position(old_x, 120)
                    self.put("next_x", proposed_x)
                    self.put("next_y", 120, 1)
                    self.put("vel_x", velocity)
                    self.call("apply_platform_collision")
                    self.assertEqual(self.get("hit_x"), 1)
                    self.assertEqual(self.get("hit_x_position"), corrected_x)
                    # Gathering candidates must not mutate the movement proposal.
                    self.assertEqual(self.get("next_x"), proposed_x)
                    self.assertEqual(self.get("pos_x"), old_x)
                    self.assertEqual(self.get("vel_x"), velocity)

    def test_floor_and_wall_records_share_one_list_in_either_order(self):
        floor = (PLATFORM_FLAT, 0, 255, 185)
        wall = (PLATFORM_WALL, 96, 185, 145)
        for records in ((floor, wall), (wall, floor)):
            with self.subTest(records=records):
                self.platform_records(*records)
                self.position(124, 183, fraction=200)
                self.velocity(256)
                self.frame()
                self.assertEqual(self.get("pos_y", 1), 184)
                self.assertEqual(self.get("hit_y"), 1)
                self.assertEqual(self.get("hit_x"), 0)
                self.position(139, 120)
                self.velocity(0)
                self.frame(RIGHT)
                self.assertEqual(self.get("pos_x"), 139)
                self.assertEqual(self.get("hit_x"), 1)
                self.assertEqual(self.get("hit_y"), 0)

    def test_default_ledge_left_side_blocks_rightward_walk(self):
        for _ in range(40):
            self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 154)
        self.assertEqual(self.get("hit_x"), 1)

    def test_default_ledge_right_side_blocks_leftward_walk(self):
        self.position(210, 160)
        for _ in range(40):
            self.frame(LEFT)
        self.assertEqual(self.get("pos_x"), 190)
        self.assertEqual(self.get("hit_x"), 1)

    def test_default_ledge_top_lands_above_drawn_surface(self):
        self.position(172, 130)
        for _ in range(30):
            self.frame()
        self.assertEqual(self.get("pos_y", 1), 151)
        self.assertEqual(self.get("pos_y", 1) + 8, 159)

    def test_default_ledge_top_can_be_walked_off(self):
        self.position(180, 151)
        for _ in range(30):
            self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 210)
        self.assertEqual(self.get("hit_x"), 0)
        self.assertGreater(self.get("pos_y", 1), 151)

    def test_player_can_jump_from_lower_floor_onto_ledge(self):
        self.position(146, 184)
        for _ in range(20):
            self.frame(JUMP | RIGHT)
        self.assertGreaterEqual(self.get("pos_x") + 2, 160)
        self.assertLessEqual(self.get("pos_x") + 5, 191)
        for _ in range(60):
            self.frame()
        self.assertEqual(self.get("pos_y", 1), 151)

    def test_default_ledge_has_five_segments_plus_existing_floating_platforms(self):
        address = self.symbols["platform_data"]
        count = self.get("platform_count")
        records = [tuple(self.cpu.memory[address+i*4:address+(i+1)*4]) for i in range(count)]
        self.assertEqual(records, [
            (PLATFORM_FLAT, 0, 159, 185),
            (PLATFORM_FLAT, 120, 135, 137),
            (PLATFORM_FLAT, 120, 135, 105),
            (PLATFORM_WALL, 160, 200, 160),
            (PLATFORM_FLAT, 160, 191, 152),
            (PLATFORM_WALL, 160, 200, 191),
            (PLATFORM_FLAT, 192, 255, 185),
        ])

    def test_background_tiles_draw_ledge_and_preserve_floating_platforms(self):
        address = self.symbols["bg0"]
        self.assertEqual(self.symbols["bg0_end"] - address, 32 * 30)
        for row in range(30):
            for col in range(32):
                tile = 0
                if row in (14, 18) and col in (15, 16):
                    tile = 5
                elif row == 20 and 20 <= col <= 23:
                    tile = 5
                elif 21 <= row <= 23 and 20 <= col <= 23:
                    tile = 2
                elif row == 24:
                    tile = 2 if 20 <= col <= 23 else 5
                elif row >= 25:
                    tile = 2
                self.assertEqual(self.cpu.memory[address + row*32 + col], tile,
                                 f"background row={row}, col={col}")

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
                    self.assertEqual(self.get("hit_y_position"), 136)

    def test_floor_rejects_wrapped_foot_coordinates(self):
        self.platforms((0, 255, 137))
        # X=250 gives a right foot at 255: valid, without overflow.
        self.assertEqual(self.collision(250, 136, 137), 1)
        for x in range(251, 256):
            with self.subTest(x=x):
                self.assertEqual(self.collision(x, 136, 137), 0)
        # Wrapping both feet must not look like contact near the left edge.
        self.platforms((0, 3, 137))
        self.assertEqual(self.collision(254, 136, 137), 0)

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
                self.assertEqual(self.get("hit_y_position"), 104)

    def test_collision_uses_world_x_not_camera_x(self):
        self.platforms((120, 135, 137))
        self.put("camera_x", 100)
        self.assertEqual(self.collision(124, 136, 137), 1)

    def test_empty_list_clears_hit(self):
        self.platforms()
        self.put("hit_y", 1)
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

    def test_platform_overlap_uses_proposed_horizontal_position(self):
        self.platforms((120, 135, 137))
        self.position(114, 136, fraction=250)
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 115)
        self.assertEqual(self.get("hit_y"), 1)
        self.assertEqual(self.get("pos_y", 1), 136)

    def test_proposals_and_collision_preserve_original_position(self):
        self.platforms((0, 255, 185))
        self.position(124, 183, fraction=200)
        self.velocity(256)
        self.put("buttons", RIGHT)
        self.call("update_x")
        self.call("update_y")
        self.assertEqual(self.get("pos_x"), 124)
        self.assertEqual(self.get("pos_y", 1), 183)
        self.assertEqual(self.get("pos_y"), 200)
        self.assertEqual(self.get("next_x"), 125)
        self.assertEqual(self.get("next_y", 1), 185)
        self.assertEqual(self.get("next_y"), 4)
        self.call("apply_move_collision")
        self.assertEqual(self.get("next_y", 1), 184)
        self.assertEqual(self.get("next_y"), 4)
        self.assertEqual(self.get("pos_x"), 124)
        self.assertEqual(self.get("pos_y", 1), 183)
        self.assertEqual(self.get("pos_y"), 200)

    def test_camera_follows_committed_x_with_existing_wrap_rules(self):
        for x, camera, buttons, expected_x, expected_camera, expected_nt in (
            (160, 0, RIGHT, 161, 1, 0),
            (96, 0, LEFT, 95, 255, 1),
            (159, 0, RIGHT, 160, 0, 0),
            (95, 0, 0, 95, 255, 1),
            (161, 0, 0, 161, 1, 0),
            (124, 0, 0, 124, 0, 0),
            (159, 255, RIGHT, 160, 0, 1),
        ):
            with self.subTest(x=x, camera=camera, buttons=buttons):
                self.position(x, 160)
                self.put("camera_x", camera)
                self.put("ntable", 0)
                self.frame(buttons)
                self.assertEqual(self.get("pos_x"), expected_x)
                self.assertEqual(self.get("camera_x"), expected_camera)
                self.assertEqual(self.get("ntable"), expected_nt)

    def test_camera_catches_up_to_stationary_player_then_stops(self):
        for x, expected_camera, expected_nt in ((200, 40, 0), (92, 252, 1)):
            with self.subTest(x=x):
                self.position(x, 160)
                self.put("camera_x", 0)
                self.put("ntable", 0)
                for _ in range(50):
                    self.frame()
                    self.assertEqual(self.get("pos_x"), x)
                self.assertEqual(self.get("camera_x"), expected_camera)
                self.assertEqual(self.get("ntable"), expected_nt)

    def test_walking_off_edge_begins_falling(self):
        self.platforms((120, 135, 137))
        self.position(133, 136, fraction=250)
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 134)
        self.assertEqual(self.get("hit_y"), 0)
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
                    if self.get("hit_y"):
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
            self.assertEqual(self.get("hit_y"), 0)
            self.assertEqual(self.get("jump_latch"), 1)
        self.frame()
        self.assertEqual(self.get("hit_y"), 1)
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
