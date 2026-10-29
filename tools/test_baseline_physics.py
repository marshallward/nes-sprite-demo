#!/usr/bin/env python3
"""Regression tests for the active two-height physics, including known gaps.

Build the current ROM first, install py65, then run this file. Tests execute
the assembled 6502 routines without emulating the PPU, NMI, or joypad.
Expected failures retain desired behavior for deferred collision-resolution work;
an unexpected success is a test failure so those markers get reviewed after fixes.
"""
from pathlib import Path
import re
import unittest

from py65.devices.mpu6502 import MPU


ROOT = Path(__file__).resolve().parents[1]
JUMP, LEFT, RIGHT = 0x80, 0x02, 0x01
PLATFORM_FLAT = 0x7F
PLATFORM_WALL = 0x80
PLATFORM_WALL_RIGHT = 0x81
PLATFORM_SLOPE_1_1 = 0
PLATFORM_SLOPE_2_1 = 1


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
        self.put("buttons_prev", self.get("buttons"))
        self.put("buttons", buttons)
        self.call("update_move")

    def platforms(self, *records):
        """Encode flat platforms from (start, end, map surface Y) test tuples."""
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

    def test_flat_and_slope_share_surface_height_helper(self):
        for kind, samples in (
            (PLATFORM_FLAT, ((20, 191), (32, 191), (48, 191), (90, 191))),
            (PLATFORM_SLOPE_1_1, ((20, 191), (32, 191), (40, 183),
                                  (53, 170), (63, 160), (90, 160))),
            (PLATFORM_SLOPE_2_1, ((20, 191), (32, 191), (40, 175),
                                  (53, 149), (63, 129), (90, 129))),
        ):
            self.platform_records((kind, 32, 63, 191))
            for x, expected_y in samples:
                with self.subTest(kind=kind, x=x):
                    self.cpu.a = x
                    self.cpu.x = 123
                    self.cpu.y = 0
                    self.call("surface_y_at_x")
                    self.assertEqual(self.cpu.a, expected_y)
                    self.assertEqual(self.cpu.x, 123)
                    self.assertEqual(self.cpu.y, 0)

    def test_slope_landing_at_several_horizontal_positions(self):
        self.platform_records((PLATFORM_SLOPE_1_1, 32, 63, 191))
        for x, resting_y in ((27, 183), (35, 175), (48, 162), (58, 152), (61, 152)):
            with self.subTest(x=x):
                self.assertEqual(self.collision(x, resting_y-2, resting_y+3), 1)
                self.assertEqual(self.get("hit_y_position"), resting_y)

    def test_default_slope_can_be_walked_onto_from_ground(self):
        self.position(20, 184)
        for step in range(1, 31):
            self.frame(RIGHT)
            x = 20 + step
            self.assertEqual(self.get("pos_x"), x)
            right_foot = x + 5
            surface = 192 if right_foot <= 31 else 192 - (right_foot - 31)
            self.assertEqual(self.get("pos_y", 1), surface - 8)
            self.assertEqual(self.get("hit_y"), 1)

    def test_slope_follow_downhill_stays_in_contact_and_joins_ground(self):
        for fraction in range(0, 256, 16):
            with self.subTest(fraction=fraction):
                self.call("init_move")
                self.position(56, 154, fraction=fraction)
                for step in range(1, 41):
                    self.frame(LEFT)
                    x = 56 - step
                    right_foot = x + 5
                    surface = 192 if right_foot <= 31 else 223 - right_foot
                    self.assertEqual(self.get("pos_x"), x)
                    self.assertEqual(self.get("pos_y", 1), surface - 8)
                    self.assertEqual(self.get("hit_y"), 1)
                    self.assertEqual(self.get("hit_x"), 0)
                    self.assertEqual(self.get("vel_y"), 0)
                    self.assertEqual(self.get("vel_y", 1), 0)

    def test_slope_follow_does_not_snap_an_airborne_player_down(self):
        self.platform_records((PLATFORM_SLOPE_1_1, 32, 63, 191))
        self.position(48, 160)  # two pixels above the standing height
        self.frame(LEFT)
        self.assertEqual(self.get("pos_x"), 47)
        self.assertEqual(self.get("pos_y", 1), 160)
        self.assertEqual(self.get("hit_y"), 0)

    def test_slope_follow_detaches_when_jumping_downhill(self):
        self.platform_records((PLATFORM_SLOPE_1_1, 32, 63, 191))
        self.position(48, 162)
        self.frame(JUMP | LEFT)
        self.assertEqual(self.get("pos_x"), 47)
        self.assertLess(self.get("pos_y", 1), 162)
        self.assertEqual(self.get("hit_y"), 0)
        self.assertGreaterEqual(self.get("vel_y", 1), 128)

    def test_slope_follow_releases_at_either_span_endpoint(self):
        self.platform_records((PLATFORM_SLOPE_1_1, 32, 63, 191))
        for x, y, direction, expected_x in ((27, 183, LEFT, 26),
                                           (61, 152, RIGHT, 62)):
            with self.subTest(x=x, direction=direction):
                self.call("init_move")
                self.position(x, y, fraction=250)
                self.frame(direction)
                self.assertEqual(self.get("pos_x"), expected_x)
                self.assertGreater(self.get("pos_y", 1), y)
                self.assertEqual(self.get("hit_y"), 0)

    def test_default_slope_right_wall_blocks_ground_approach(self):
        self.position(80, 184)
        for _ in range(30):
            self.frame(LEFT)
        self.assertEqual(self.get("pos_x"), 63)
        self.assertEqual(self.get("pos_x") + 1, 64)
        self.assertEqual(self.get("hit_x"), 1)
        self.assertEqual(self.get("vel_x"), 0)

    def test_default_slope_right_wall_can_be_passed_above(self):
        self.position(63, 140)
        self.frame(LEFT)
        self.assertEqual(self.get("pos_x"), 62)
        self.assertEqual(self.get("hit_x"), 0)

    def test_right_facing_wall_blocks_only_leftward_crossing(self):
        self.platform_records((PLATFORM_WALL_RIGHT, 96, 185, 145))
        for x, buttons, expected_x, hit in ((138, RIGHT, 139, 0),
                                           (145, LEFT, 145, 1)):
            with self.subTest(buttons=buttons):
                self.call("init_move")
                self.position(x, 120)
                self.frame(buttons)
                self.assertEqual(self.get("pos_x"), expected_x)
                self.assertEqual(self.get("hit_x"), hit)
                self.assertEqual(self.get("vel_x"), 0 if hit else 1)

    def test_default_slope_can_be_run_up_and_off_crest(self):
        for fraction in range(0, 256, 16):
            with self.subTest(fraction=fraction):
                self.call("init_move")
                self.position(20, 184, fraction=fraction)
                for step in range(1, 71):
                    self.frame(RIGHT)
                    self.assertEqual(self.get("pos_x"), 20 + step)
                    self.assertEqual(self.get("hit_x"), 0)
                self.assertEqual(self.get("pos_y", 1), 184)

    def test_steep_slope_follows_two_pixels_per_horizontal_step(self):
        for fraction in (0, 128, 240):
            with self.subTest(fraction=fraction):
                self.call("init_move")
                self.position(84, 184, fraction=fraction)
                for direction in (RIGHT, LEFT):
                    for _ in range(25):
                        old_x = self.get("pos_x")
                        self.frame(direction)
                        x = old_x + (1 if direction == RIGHT else -1)
                        foot = min(111, max(95, x+5))
                        surface = 192 - 2*(foot-95)
                        self.assertEqual(self.get("pos_x"), x)
                        self.assertEqual(self.get("pos_y", 1), surface-8)
                        self.assertEqual(self.get("hit_y"), 1)
                        self.assertEqual(self.get("hit_x"), 0)

    def test_steep_slope_landing_span_and_one_way_contact(self):
        self.platform_records((PLATFORM_SLOPE_2_1, 95, 111, 192))
        for x, resting_y in ((90, 184), (95, 174), (100, 164),
                             (106, 152), (109, 152)):
            with self.subTest(x=x):
                self.assertEqual(self.collision(x, resting_y-3, resting_y+4), 1)
                self.assertEqual(self.get("hit_y_position"), resting_y)
        for x in (89, 110):
            with self.subTest(outside_x=x):
                self.assertEqual(self.collision(x, 130, 200), 0)
        self.assertEqual(self.collision(100, 166, 180), 0)
        self.assertEqual(self.collision(100, 180, 150), 0)

    def test_steep_slope_jump_detaches_and_lands_again(self):
        self.platform_records((PLATFORM_SLOPE_2_1, 95, 111, 192))
        self.position(100, 164)
        self.frame(JUMP | LEFT)
        self.assertEqual(self.get("pos_x"), 99)
        self.assertLess(self.get("pos_y", 1), 164)
        self.assertEqual(self.get("hit_y"), 0)
        for _ in range(120):
            self.frame()
        self.assertEqual(self.get("pos_y", 1), 166)
        self.assertEqual(self.get("hit_y"), 1)

    def test_steep_slope_right_wall_blocks_entry_but_allows_exit(self):
        self.position(124, 184)
        for _ in range(30):
            self.frame(LEFT)
        self.assertEqual(self.get("pos_x"), 111)
        self.assertEqual(self.get("hit_x"), 1)
        self.call("init_move")
        self.position(84, 184)
        for step in range(1, 51):
            self.frame(RIGHT)
            self.assertEqual(self.get("pos_x"), 84+step)
            self.assertEqual(self.get("hit_x"), 0)
        self.assertEqual(self.get("pos_y", 1), 184)

    def test_slope_crossing_uses_old_and_proposed_surface_heights(self):
        self.platform_records((PLATFORM_SLOPE_1_1, 32, 63, 191))
        self.position(47, 163)
        self.put("next_x", 48)
        self.put("next_y", 163, 1)
        self.call("apply_platform_collision")
        # Surface Y decreases from 171 to 170 as the right foot moves 52 -> 53.
        self.assertEqual(self.get("hit_y"), 1)
        self.assertEqual(self.get("hit_y_position"), 162)
        self.assertEqual(self.get("pos_x"), 47)
        self.assertEqual(self.get("pos_y", 1), 163)
        self.assertEqual(self.get("next_x"), 48)
        self.assertEqual(self.get("next_y", 1), 163)

    def test_slope_span_endpoints_and_one_way_crossing(self):
        self.platform_records((PLATFORM_SLOPE_1_1, 32, 63, 191))
        for x in (26, 62):
            with self.subTest(outside_x=x):
                self.assertEqual(self.collision(x, 140, 200), 0)
        for old_y, proposed_y in ((163, 170), (170, 155)):
            with self.subTest(old_y=old_y, proposed_y=proposed_y):
                self.assertEqual(self.collision(48, old_y, proposed_y), 0)

    def test_slope_stationary_contact_and_jump_detachment(self):
        self.platform_records((PLATFORM_SLOPE_1_1, 32, 63, 191))
        self.position(48, 162)
        for _ in range(60):
            self.frame()
            self.assertEqual(self.get("pos_y", 1), 162)
            self.assertEqual(self.get("hit_y"), 1)
        self.frame(JUMP)
        self.assertLess(self.get("pos_y", 1), 162)
        self.assertEqual(self.get("hit_y"), 0)
        for _ in range(120):
            self.frame()
        self.assertEqual(self.get("pos_y", 1), 162)
        self.assertEqual(self.get("hit_y"), 1)

    def test_flat_and_slope_keep_highest_landing_in_either_order(self):
        floor = (PLATFORM_FLAT, 0, 255, 192)
        slope = (PLATFORM_SLOPE_1_1, 32, 63, 191)
        for records in ((floor, slope), (slope, floor)):
            with self.subTest(records=records):
                self.platform_records(*records)
                self.assertEqual(self.collision(48, 150, 195), 1)
                self.assertEqual(self.get("hit_y_position"), 162)

    def test_flat_slope_and_wall_share_list(self):
        self.platform_records((PLATFORM_FLAT, 0, 255, 192),
                              (PLATFORM_SLOPE_1_1, 32, 63, 191),
                              (PLATFORM_WALL, 96, 200, 145))
        self.assertEqual(self.collision(48, 150, 180), 1)
        self.assertEqual(self.get("hit_y_position"), 162)
        self.position(138, 120)
        self.frame(RIGHT)
        self.assertEqual(self.get("hit_x"), 1)
        self.assertEqual(self.get("hit_y"), 0)
        self.assertEqual(self.get("pos_x"), 138)

    def test_drawn_slope_matches_surface_and_original_tiles_are_unchanged(self):
        rom = (ROOT / "build/jump.nes").read_bytes()
        chr_data = rom[16+0x4000:16+0x4000+0x2000]
        self.assertEqual(len(chr_data), 8192)
        self.assertEqual(chr_data[:96], (ROOT / "assets/ball.bin").read_bytes())
        map_address = self.symbols["bg0"]
        for label, expected_kind in (("platform_7", PLATFORM_SLOPE_1_1),
                                     ("platform_9", PLATFORM_SLOPE_2_1)):
            record = self.symbols[label]
            kind, x0, x1, y0 = self.cpu.memory[record:record+4]
            self.assertEqual(kind, expected_kind)
            for x in range(x0, x1+1):
                for y in range(193):
                    tile = self.cpu.memory[map_address + (y//8)*32 + x//8]
                    bit = 7 - x%8
                    lo = (chr_data[tile*16 + y%8] >> bit) & 1
                    hi = (chr_data[tile*16 + 8 + y%8] >> bit) & 1
                    if lo | hi:
                        break
                self.assertEqual(y, y0 - ((x-x0) << kind), f"drawn slope at X={x}")
                self.cpu.a = x
                self.cpu.y = record - self.symbols["platform_data"]
                self.call("surface_y_at_x")
                self.assertEqual(self.cpu.a, y)

    def test_wall_blocks_from_both_sides_and_clears_horizontal_velocity(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        for x, buttons in ((138, RIGHT), (145, LEFT)):
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
                self.position(138, y)
                self.velocity(0)
                self.frame(RIGHT)
                self.assertEqual(self.get("hit_x"), hit)
                self.assertEqual(self.get("pos_x"), 138 if hit else 139)

    def test_wall_overlap_uses_proposed_vertical_position(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        self.position(138, 87, fraction=250)
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_y", 1), 88)
        self.assertEqual(self.get("hit_x"), 1)
        self.assertEqual(self.get("pos_x"), 138)

    def test_moving_away_from_wall_is_not_blocked(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        for x, buttons, expected in ((138, LEFT, 137), (145, RIGHT, 146)):
            with self.subTest(x=x, buttons=buttons):
                self.position(x, 120)
                self.frame(buttons)
                self.assertEqual(self.get("hit_x"), 0)
                self.assertEqual(self.get("pos_x"), expected)

    def test_wall_hit_clears_on_stationary_update(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        self.position(138, 120)
        self.frame(RIGHT)
        self.assertEqual(self.get("hit_x"), 1)
        self.frame()
        self.assertEqual(self.get("hit_x"), 0)

    def test_nearest_wall_candidate_is_independent_of_record_order(self):
        for walls in ((145, 150), (150, 145)):
            for old_x, proposed_x, velocity, corrected_x in (
                (130, 155, 1, 138),
                (160, 130, 255, 150),
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
        floor = (PLATFORM_FLAT, 0, 255, 192)
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
                self.position(138, 120)
                self.velocity(0)
                self.frame(RIGHT)
                self.assertEqual(self.get("pos_x"), 138)
                self.assertEqual(self.get("hit_x"), 1)
                self.assertEqual(self.get("hit_y"), 0)

    def test_default_ledge_left_side_blocks_rightward_walk(self):
        for _ in range(40):
            self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 153)
        self.assertEqual(self.get("pos_x") + 6, 159)  # opaque edge before wall X=160
        self.assertEqual(self.get("hit_x"), 1)

    def test_default_ledge_right_side_blocks_leftward_walk(self):
        self.position(210, 160)
        for _ in range(40):
            self.frame(LEFT)
        self.assertEqual(self.get("pos_x"), 191)
        self.assertEqual(self.get("pos_x") + 1, 192)  # opaque edge after wall X=191
        self.assertEqual(self.get("hit_x"), 1)

    def test_default_ledge_top_lands_above_drawn_surface(self):
        self.position(172, 130)
        for _ in range(30):
            self.frame()
        self.assertEqual(self.get("pos_y", 1), 152)
        self.assertEqual(self.get("pos_y", 1) + 7, 159)

    @unittest.expectedFailure
    def test_default_ledge_top_can_be_walked_off(self):
        # Known snag: free proposed Y causes a false wall hit before floor
        # correction. The heuristic rescan was deliberately disabled.
        for direction, expected_x in ((RIGHT, 210), (LEFT, 150)):
            for fraction in range(0, 256, 16):
                with self.subTest(direction=direction, fraction=fraction):
                    self.call("init_move")
                    self.position(180, 152, fraction=fraction)
                    for _ in range(30):
                        self.frame(direction)
                    self.assertEqual(self.get("pos_x"), expected_x)
                    self.assertEqual(self.get("hit_x"), 0)
                    self.assertGreater(self.get("pos_y", 1), 152)

    @unittest.expectedFailure
    def test_floor_correction_rejects_false_corner_wall_hit_in_either_order(self):
        # Deferred: floor and wall results are selected independently.
        floor = (PLATFORM_FLAT, 160, 191, 160)
        wall = (PLATFORM_WALL, 161, 200, 191)
        for records in ((floor, wall), (wall, floor)):
            with self.subTest(records=records):
                self.call("init_move")
                self.platform_records(*records)
                self.position(184, 152, fraction=240)
                self.frame(RIGHT)
                self.assertEqual(self.get("pos_x"), 185)
                self.assertEqual(self.get("pos_y", 1), 152)
                self.assertEqual(self.get("pos_y"), 44)
                self.assertEqual(self.get("hit_x"), 0)
                self.assertEqual(self.get("hit_y"), 1)
                self.assertEqual(self.get("vel_x"), 1)

    def test_real_wall_still_blocks_during_floor_correction(self):
        floor = (PLATFORM_FLAT, 0, 255, 192)
        wall = (PLATFORM_WALL, 96, 200, 145)
        for records in ((floor, wall), (wall, floor)):
            with self.subTest(records=records):
                self.call("init_move")
                self.platform_records(*records)
                self.position(138, 183, fraction=200)
                self.velocity(256)
                self.frame(RIGHT)
                self.assertEqual(self.get("pos_x"), 138)
                self.assertEqual(self.get("pos_y", 1), 184)
                self.assertEqual(self.get("hit_x"), 1)
                self.assertEqual(self.get("hit_y"), 1)
                self.assertEqual(self.get("vel_x"), 0)

    @unittest.expectedFailure
    def test_recheck_finds_farther_wall_after_rejecting_false_near_wall(self):
        # Deferred mixed-contact selection; do not re-enable the old rescan
        # merely to make this pass.
        floor = (PLATFORM_FLAT, 0, 255, 160)
        near = (PLATFORM_WALL, 161, 200, 145)
        far = (PLATFORM_WALL, 96, 200, 150)
        for records in ((floor, near, far), (far, near, floor), (near, floor, far)):
            with self.subTest(records=records):
                self.call("init_move")
                self.platform_records(*records)
                self.position(130, 151)
                self.put("next_x", 155)
                self.put("next_y", 155, 1)
                self.put("next_y", 99)
                self.put("vel_x", 1)
                self.call("apply_move_collision")
                self.assertEqual(self.get("next_x"), 143)
                self.assertEqual(self.get("hit_x_position"), 143)
                self.assertEqual(self.get("hit_x"), 1)
                self.assertEqual(self.get("next_y", 1), 152)
                self.assertEqual(self.get("next_y"), 99)
                self.assertEqual(self.get("hit_y"), 1)
                self.assertEqual(self.get("pos_x"), 130)
                self.assertEqual(self.get("pos_y", 1), 151)

    @unittest.expectedFailure
    def test_floor_correction_can_reveal_wall_missed_by_free_proposal(self):
        # Deferred: correcting Y can expose a wall absent from the free proposal.
        self.platform_records((PLATFORM_FLAT, 0, 255, 160),
                              (PLATFORM_WALL, 96, 160, 145))
        self.position(138, 151)
        self.put("next_x", 139)
        self.put("next_y", 161, 1)
        self.put("vel_x", 1)
        self.call("apply_move_collision")
        self.assertEqual(self.get("next_x"), 138)
        self.assertEqual(self.get("next_y", 1), 152)
        self.assertEqual(self.get("hit_x"), 1)
        self.assertEqual(self.get("hit_y"), 1)

    def test_walk_off_either_corner_and_reverse_cannot_enter_ledge(self):
        # Reverse at each edge across several fractional-Y phases and delays.
        # Move to the edge rather than assuming the old buggy travel timing.
        for outward, inward, edge in ((RIGHT, LEFT, 190), (LEFT, RIGHT, 154)):
            for fraction in range(0, 256, 16):
                for delay in (0, 1, 2):
                    with self.subTest(outward=outward, fraction=fraction, delay=delay):
                        self.call("init_move")
                        self.position(180, 152, fraction=fraction)
                        for _ in range(40):
                            self.frame(outward)
                            if self.get("pos_x") == edge:
                                break
                        self.assertEqual(self.get("pos_x"), edge)
                        for _ in range(delay):
                            self.frame()
                        for _ in range(40):
                            self.frame(inward)
                            x, y = self.get("pos_x"), self.get("pos_y", 1)
                            # Opaque bounding box must not be inside the ledge.
                            inside = (160 <= x+1 and x+6 <= 191 and
                                      160 <= y+2 and y+7 <= 191)
                            self.assertFalse(inside,
                                             f"ball entered ledge at X={x}, Y={y}")

    def test_wall_contact_includes_old_edge_exactly_on_boundary(self):
        self.platform_records((PLATFORM_WALL, 96, 185, 145))
        for x, buttons, corrected_x in ((139, RIGHT, 138), (144, LEFT, 145)):
            with self.subTest(x=x, buttons=buttons):
                self.position(x, 120)
                self.velocity(0)
                self.frame(buttons)
                self.assertEqual(self.get("hit_x"), 1)
                self.assertEqual(self.get("pos_x"), corrected_x)
                self.assertEqual(self.get("vel_x"), 0)

    def test_player_can_jump_from_lower_floor_onto_ledge(self):
        self.position(146, 184)
        for _ in range(20):
            self.frame(JUMP | RIGHT)
        self.assertGreaterEqual(self.get("pos_x") + 2, 160)
        self.assertLessEqual(self.get("pos_x") + 5, 191)
        for _ in range(60):
            self.frame()
        self.assertEqual(self.get("pos_y", 1), 152)

    def test_default_map_has_ledge_and_test_slope(self):
        address = self.symbols["platform_data"]
        count = self.get("platform_count")
        records = [tuple(self.cpu.memory[address+i*4:address+(i+1)*4]) for i in range(count)]
        self.assertEqual(records, [
            (PLATFORM_FLAT, 0, 255, 192),
            (PLATFORM_FLAT, 128, 143, 144),
            (PLATFORM_FLAT, 128, 143, 112),
            (PLATFORM_WALL, 161, 200, 160),
            (PLATFORM_FLAT, 160, 191, 160),
            (PLATFORM_WALL_RIGHT, 161, 200, 191),
            (PLATFORM_SLOPE_1_1, 31, 63, 192),
            (PLATFORM_WALL_RIGHT, 161, 200, 63),
            (PLATFORM_SLOPE_2_1, 95, 111, 192),
            (PLATFORM_WALL_RIGHT, 161, 200, 111),
        ])

    def test_background_tiles_draw_ledge_and_preserve_floating_platforms(self):
        address = self.symbols["bg0"]
        self.assertEqual(self.symbols["bg0_end"] - address, 32 * 30)
        for row in range(30):
            for col in range(32):
                tile = 0
                if row in (14, 18) and col in (16, 17):
                    tile = 5
                elif 20 <= row <= 23:
                    diagonal_col = 27 - row
                    if col == diagonal_col:
                        tile = 6
                    elif diagonal_col < col <= 7:
                        tile = 2
                    elif col == 13 - (row-20)//2:
                        tile = 7 if row % 2 == 0 else 8
                    elif 13 - (row-20)//2 < col <= 13:
                        tile = 2
                    elif 20 <= col <= 23:
                        tile = 5 if row == 20 else 2
                elif row == 24:
                    tile = 2 if (4 <= col <= 7 or 12 <= col <= 13 or
                                 20 <= col <= 23) else 5
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
        self.platforms((120, 135, 144))
        for x, hit in ((114, 0), (115, 1), (133, 1), (134, 0)):
            with self.subTest(x=x):
                self.assertEqual(self.collision(x, 136, 137), hit)
                if hit:
                    self.assertEqual(self.get("hit_y_position"), 136)

    @unittest.skip("Floor overflow guards were removed; boundary policy is deferred.")
    def test_floor_rejects_wrapped_foot_coordinates(self):
        self.platforms((0, 255, 144))
        # X=250 gives a right foot at 255: valid, without overflow.
        self.assertEqual(self.collision(250, 136, 137), 1)
        for x in range(251, 256):
            with self.subTest(x=x):
                self.assertEqual(self.collision(x, 136, 137), 0)
        # Wrapping both feet must not look like contact near the left edge.
        self.platforms((0, 3, 144))
        self.assertEqual(self.collision(254, 136, 137), 0)

    def test_floor_accepts_downward_crossing_or_resting_contact(self):
        self.platforms((120, 135, 144))
        for old, new, hit in (
            (135, 135, 0),
            (135, 136, 0),
            (136, 136, 1),
            (136, 137, 1),
            (136, 145, 1),
            (137, 145, 0),
            (140, 136, 0),
        ):
            with self.subTest(old=old, new=new):
                self.assertEqual(self.collision(124, old, new), hit)

    def test_upward_subpixel_motion_does_not_attach_to_floor(self):
        self.platforms((120, 135, 144))
        self.velocity(-1)
        self.assertEqual(self.collision(124, 136, 136), 0)

    def test_floor_surface_y_uses_explicit_player_bottom_offset(self):
        for surface in (112, 144, 160, 192):
            with self.subTest(surface=surface):
                self.platforms((0, 255, surface))
                # The body bottom is OAM Y+7: move it from surface-1 to surface.
                self.assertEqual(self.collision(124, surface-8, surface-7), 1)
                corrected_y = self.get("hit_y_position")
                self.assertEqual(corrected_y, surface-8)
                self.assertEqual(corrected_y + 7, surface-1)

    def test_highest_crossed_platform_wins_in_either_order(self):
        for heights in ((192, 144, 112), (112, 144, 192)):
            with self.subTest(heights=heights):
                self.platforms(*[(0, 255, y) for y in heights])
                self.assertEqual(self.collision(124, 100, 190), 1)
                self.assertEqual(self.get("hit_y_position"), 104)

    def test_collision_uses_world_x_not_camera_x(self):
        self.platforms((120, 135, 144))
        self.put("camera_x", 100)
        self.assertEqual(self.collision(124, 136, 137), 1)

    def test_empty_list_clears_hit(self):
        self.platforms()
        self.put("hit_y", 1)
        self.assertEqual(self.collision(124, 136, 137), 0)

    def test_landing_corrects_integer_y_but_preserves_fraction(self):
        self.platforms((0, 255, 192))
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

    def test_stationary_body_bottom_stays_one_pixel_above_ground(self):
        self.platforms((0, 255, 192))
        self.position(124, 184)
        for _ in range(120):
            self.frame()
            self.assertEqual(self.get("pos_y", 1), 184)
            self.assertEqual(self.get("pos_y", 1) + 7, 191)
            self.assertEqual(self.get("hit_y"), 1)
            self.assertEqual(self.get("vel_y"), 0)
            self.assertEqual(self.get("vel_y", 1), 0)
        # Fractional Y is preserved, but resting contact resets velocity each update.

    def test_platform_overlap_uses_proposed_horizontal_position(self):
        self.platforms((120, 135, 144))
        self.position(114, 136, fraction=250)
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 115)
        self.assertEqual(self.get("hit_y"), 1)
        self.assertEqual(self.get("pos_y", 1), 136)

    def test_proposals_and_collision_preserve_original_position(self):
        self.platforms((0, 255, 192))
        self.position(124, 183, fraction=200)
        self.velocity(256)
        self.put("buttons", RIGHT)
        self.call("set_velocity_x")
        self.call("set_velocity_y")
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

    def test_velocity_selection_does_not_propose_or_commit_position(self):
        self.position(124, 120, fraction=200)
        self.put("next_x", 17)
        self.put("next_y", 18)
        self.put("next_y", 19, 1)
        self.put("buttons", RIGHT)
        self.velocity(256)
        self.call("set_velocity_x")
        self.call("set_velocity_y")
        self.assertEqual(self.get("vel_x"), 1)
        self.assertEqual(self.get("vel_y"), 60)
        self.assertEqual(self.get("vel_y", 1), 1)
        self.assertEqual(self.get("next_x"), 17)
        self.assertEqual(self.get("next_y"), 18)
        self.assertEqual(self.get("next_y", 1), 19)
        self.assertEqual(self.get("pos_x"), 124)
        self.assertEqual(self.get("pos_y"), 200)
        self.assertEqual(self.get("pos_y", 1), 120)

    def test_position_proposals_use_velocity_not_buttons(self):
        for velocity_x in (-8, 0, 8):
            with self.subTest(velocity_x=velocity_x):
                self.position(124, 120, fraction=200)
                self.put("buttons", JUMP | LEFT)
                self.put("vel_x", velocity_x)
                self.velocity(0)
                self.call("update_x")
                self.call("update_y")
                self.assertEqual(self.get("next_x"), 124+velocity_x)
                self.assertEqual(self.get("next_y"), 200)
                self.assertEqual(self.get("next_y", 1), 120)
                self.assertEqual(self.get("vel_x"), velocity_x & 255)
                self.assertEqual(self.get("vel_y"), 0)
                self.assertEqual(self.get("vel_y", 1), 0)

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
                self.call("init_move")  # each camera fixture starts without pending taps
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
        self.platforms((120, 135, 144))
        self.position(133, 136, fraction=250)
        self.frame(RIGHT)
        self.assertEqual(self.get("pos_x"), 134)
        self.assertEqual(self.get("hit_y"), 0)
        self.assertEqual(self.get("pos_y", 1), 137)

    def test_initial_jump_frame_uses_downward_gravity_constant(self):
        self.platforms((0, 255, 192))
        self.position(124, 184)
        self.frame(JUMP)
        # -3.5 impulse + 60/256 gravity, not held-ascent gravity (15/256).
        self.assertEqual(self.jump_state(), (180, 188, 252, 188, 1))

    def test_release_and_repress_changes_ascent_gravity(self):
        self.platforms((0, 255, 192))
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
                self.platforms((0, 255, 192))
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

    def test_release_on_ground_clears_latch_in_one_update(self):
        self.platforms((0, 255, 192))
        self.position(124, 184)
        self.put("jump_latch", 1)
        self.frame()
        self.assertEqual(self.get("hit_y"), 1)
        self.assertEqual(self.get("jump_latch"), 0)
        self.frame(JUMP)
        self.assertGreaterEqual(self.get("vel_y", 1), 128)
        self.assertLess(self.get("pos_y", 1), 184)

    def test_turbo_has_no_latch_delay_after_grounded_release(self):
        for pulse in (1, 2, 3, 4, 6, 8):
            for phase in range(2*pulse):
                with self.subTest(pulse=pulse, phase=phase):
                    self.call("init_move")
                    self.platforms((0, 255, 192))
                    self.position(48, 184)
                    launches = 0
                    for frame in range(600):
                        pressed = (frame + phase) % (2*pulse) < pulse
                        old_y = self.get("pos_y", 1)
                        old_latch = self.get("jump_latch")
                        self.frame(JUMP if pressed else 0)
                        if old_y == 184 and pressed and not old_latch:
                            self.assertLess(self.get("pos_y", 1), 184)
                            self.assertGreaterEqual(self.get("vel_y", 1), 128)
                            launches += 1
                        if old_y == 184 and self.get("pos_y", 1) == 184 and not pressed:
                            self.assertEqual(self.get("hit_y"), 1)
                            self.assertEqual(self.get("jump_latch"), 0)
                    self.assertGreater(launches, 5)

    def test_airborne_release_and_repress_do_not_apply_another_impulse(self):
        self.platforms((0, 255, 192))
        self.position(48, 184)
        self.frame(JUMP)
        landed = False
        for frame in range(120):
            pressed = frame % 2 == 1
            old_v = self.get("vel_y") | (self.get("vel_y", 1) << 8)
            gravity = 15 if old_v >= 0x8000 and pressed else 60
            self.frame(JUMP if pressed else 0)
            if self.get("hit_y"):
                landed = True
                break
            self.assertEqual(self.get("jump_latch"), 1)
            new_v = self.get("vel_y") | (self.get("vel_y", 1) << 8)
            self.assertEqual(new_v, (old_v + gravity) & 0xFFFF)
        self.assertTrue(landed)

    def test_held_jump_does_not_bounce_and_ground_release_rearms(self):
        self.platforms((0, 255, 192))
        self.position(124, 184)
        self.frame(JUMP)
        for _ in range(150):
            self.frame(JUMP)
        self.assertEqual(self.get("pos_y", 1), 184)
        self.assertEqual(self.get("jump_latch"), 1)
        self.frame()
        # Resting contact now allows release to rearm immediately.
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
