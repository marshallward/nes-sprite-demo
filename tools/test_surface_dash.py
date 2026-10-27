#!/usr/bin/env python3
"""Double-tap surface dash regression tests against the assembled ROM."""
import unittest

import test_baseline_physics as physics


LEFT, RIGHT, JUMP = physics.LEFT, physics.RIGHT, physics.JUMP


class SurfaceDashTests(unittest.TestCase):
    def setUp(self):
        self.machine = physics.BaselinePhysicsTests()
        self.machine.setUp()
        self.speed = self.machine.symbols["DASH_PIXELS"]
        self.duration = self.machine.symbols["DASH_FRAMES"]
        self.window = self.machine.symbols["DASH_TAP_WINDOW"]
        self.reset_ground()

    def frame(self, buttons=0):
        self.machine.put("buttons", buttons)
        self.machine.call("update_game")

    def reset_ground(self, x=80, y=184):
        m = self.machine
        m.call("init_game")
        m.platforms((0, 255, 192))
        m.position(x, y)
        self.frame()

    def double_tap(self, direction):
        self.frame(direction)
        self.frame()
        self.frame(direction)

    def test_double_tap_both_directions_runs_full_ground_burst(self):
        m = self.machine
        for direction, sign in ((RIGHT, 1), (LEFT, -1)):
            with self.subTest(direction=direction):
                self.reset_ground()
                self.double_tap(direction)
                start = 80 + sign  # first tap was one normal movement update
                for step in range(1, self.duration+1):
                    if step > 1:
                        self.frame(direction)
                    self.assertEqual(m.get("pos_x", 1), start+sign*self.speed*step)
                    self.assertEqual(m.get("pos_y", 1), 184)
                    self.assertEqual(m.get("hit_y"), 1)
                    self.assertEqual(m.get("dash_timer"), self.duration-step)
                    self.assertEqual(m.get("dash_used"), 1)
                self.frame()
                self.assertEqual(m.get("dash_used"), 0)

    def test_holding_direction_is_not_double_tap(self):
        m = self.machine
        for step in range(1, 25):
            self.frame(RIGHT)
            self.assertEqual(m.get("pos_x", 1), 80+step)
            self.assertEqual(m.get("dash_timer"), 0)

    def test_second_tap_at_window_boundary_and_expiry(self):
        m = self.machine
        for wait, expected_dash in ((self.window-1, True), (self.window, False)):
            with self.subTest(wait=wait):
                self.reset_ground()
                self.frame(RIGHT)
                for _ in range(wait):
                    self.frame()
                self.frame(RIGHT)
                self.assertEqual(bool(m.get("dash_timer")), expected_dash)
                self.assertEqual(m.get("pos_x", 1), 81+(self.speed if expected_dash else 1))

    def test_opposite_or_ambiguous_taps_do_not_form_a_pair(self):
        m = self.machine
        for second in (LEFT, LEFT | RIGHT):
            with self.subTest(second=second):
                self.reset_ground()
                self.frame(RIGHT)
                self.frame()
                self.frame(second)
                self.assertEqual(m.get("dash_timer"), 0)

    def test_direction_double_tap_starts_an_air_dash(self):
        m = self.machine
        m.position(80, 120)
        m.put("hit_y", 0)
        self.double_tap(RIGHT)
        self.assertEqual(m.get("pos_x", 1), 81+self.speed)
        self.assertEqual(m.get("dash_timer"), self.duration-1)

    def test_jump_press_wins_over_second_direction_tap(self):
        m = self.machine
        self.frame(RIGHT)
        self.frame()
        self.frame(JUMP | RIGHT)
        self.assertEqual(m.get("pos_x", 1), 82)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertLess(m.get("pos_y", 1), 184)

    def test_jump_interrupts_surface_dash_and_can_then_air_dash(self):
        m = self.machine
        self.double_tap(RIGHT)
        old_x = m.get("pos_x", 1)
        self.frame(JUMP | RIGHT)
        self.assertEqual(m.get("pos_x", 1), old_x+1)
        self.assertLess(m.get("pos_y", 1), 184)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("dash_surface"), 0)
        self.assertEqual(m.get("dash_used"), 0)
        self.frame()
        self.double_tap(RIGHT)
        self.assertEqual(m.get("dash_timer"), self.duration-1)

    def test_wall_stops_surface_dash(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_FLAT, 0, 255, 192),
                           (physics.PLATFORM_WALL, 96, 200, 145))
        m.position(138, 184)
        self.frame()
        self.double_tap(RIGHT)
        self.assertEqual(m.get("pos_x", 1), 138)
        self.assertEqual(m.get("hit_x"), 1)
        self.assertEqual(m.get("dash_timer"), 0)

    def test_surface_dash_dies_on_spikes_at_first_touch(self):
        m = self.machine
        self.reset_ground(x=196)
        self.double_tap(RIGHT)
        self.assertEqual(m.get("pos_x", 1), 202)
        self.assertEqual(m.get("death_timer"), 45)
        for name in ("dash_timer", "dash_surface", "dash_tap_timer",
                     "dash_dirs_down", "dash_tap_direction"):
            self.assertEqual(m.get(name), 0)

    def test_surface_dash_follows_slope_up_and_down(self):
        m = self.machine
        for x, direction, sign in ((42, RIGHT, 1), (56, LEFT, -1)):
            with self.subTest(direction=direction):
                m.call("init_game")
                m.platform_records((physics.PLATFORM_FLAT, 0, 255, 192),
                                   (physics.PLATFORM_SLOPE_1_1, 31, 63, 192),
                                   (physics.PLATFORM_WALL_RIGHT, 161, 200, 63))
                m.position(x, 210-x)
                self.frame()
                self.double_tap(direction)
                expected_x = x+sign*(1+self.speed)
                self.assertEqual(m.get("pos_x", 1), expected_x)
                self.assertEqual(m.get("pos_y", 1), 210-expected_x)
                self.assertEqual(m.get("dash_timer"), self.duration-1)
                self.assertEqual(m.get("dash_surface"), 1)
                self.assertEqual(m.get("hit_y"), 1)

    def test_leaving_edge_continues_air_burst_without_extra_jump(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_FLAT, 64, 95, 160),
                           (physics.PLATFORM_FLAT, 0, 255, 192),
                           (physics.PLATFORM_WALL_RIGHT, 161, 200, 95))
        m.position(80, 152)
        self.frame()
        self.double_tap(RIGHT)
        for _ in range(self.duration-1):
            self.frame(RIGHT)
            self.assertEqual(m.get("pos_y", 1), 152)
        self.assertEqual(m.get("pos_x", 1), 81+self.speed*self.duration)
        self.assertEqual(m.get("dash_surface"), 0)
        self.assertEqual(m.get("dash_used"), 1)
        self.assertEqual(m.get("jump_latch"), 1)
        self.frame(JUMP | RIGHT)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertLess(m.get("vel_y", 1), 128)


if __name__ == "__main__":
    unittest.main()
