#!/usr/bin/env python3
"""Air double-tap dash regressions against the assembled ROM (requires py65)."""
import unittest

import test_baseline_physics as physics

RIGHT, LEFT, JUMP = physics.RIGHT, physics.LEFT, physics.JUMP


class DashTests(unittest.TestCase):
    def setUp(self):
        self.machine = physics.BaselinePhysicsTests()
        self.machine.setUp()
        self.machine.call("init_game")
        self.speed = self.machine.symbols["DASH_PIXELS"]
        self.duration = self.machine.symbols["DASH_FRAMES"]
        self.window = self.machine.symbols["DASH_TAP_WINDOW"]

    def frame(self, buttons=0):
        self.machine.put("buttons", buttons)
        self.machine.call("update_game")

    def airborne(self, x=48, y=120, fraction=123):
        self.machine.position(x, y, fraction=fraction)
        self.machine.put("hit_y", 0)

    def start_dash(self, direction):
        # Prime the detector without moving, so collision fixtures describe the
        # exact start of the burst. Input timing tests below use full game frames.
        for buttons in (direction, 0):
            self.machine.put("buttons", buttons)
            self.machine.call("update_dash")
        self.frame(direction)

    def test_both_directions_hold_height_distance_and_ignore_steering(self):
        m = self.machine
        for direction, sign in ((RIGHT, 1), (LEFT, -1)):
            with self.subTest(direction=direction):
                m.call("init_game")
                self.airborne(x=100)
                m.velocity(-512)
                self.start_dash(direction)
                for step in range(1, self.duration+1):
                    if step > 1:
                        self.frame(LEFT if direction == RIGHT else RIGHT)
                    self.assertEqual(m.get("pos_x", 1), 100+sign*self.speed*step)
                    self.assertEqual(m.get("pos_y", 1), 120)
                    self.assertEqual(m.get("pos_y"), 123)
                    self.assertEqual(m.get("dash_timer"), self.duration-step)
                    self.assertEqual(m.get("dash_used"), 1)
                    self.assertEqual(m.get("vel_y"), 0)
                self.frame()
                self.assertEqual(m.get("vel_y"), 60)

    def test_air_tap_window_expiry_and_both_directions(self):
        m = self.machine
        for direction in (LEFT, RIGHT):
            for wait, expected in ((self.window-1, True), (self.window, False)):
                with self.subTest(direction=direction, wait=wait):
                    m.call("init_game")
                    self.airborne(x=100)
                    self.frame(direction)
                    for _ in range(wait):
                        self.frame()
                    self.frame(direction)
                    self.assertEqual(bool(m.get("dash_timer")), expected)

    def test_held_opposite_and_ambiguous_inputs_do_not_dash(self):
        m = self.machine
        for second in (RIGHT, LEFT, RIGHT | LEFT):
            m.call("init_game")
            self.airborne(x=100)
            self.frame(RIGHT)
            if second != RIGHT:
                self.frame()
            self.frame(second)
            self.assertEqual(m.get("dash_timer"), 0)

    def test_a_repress_and_b_never_dash(self):
        m = self.machine
        for direction in (0, RIGHT, LEFT, RIGHT | LEFT):
            with self.subTest(direction=direction):
                m.call("init_game")
                self.airborne(x=100)
                for buttons in (JUMP | direction, direction, JUMP | direction,
                                0x40 | direction):
                    self.frame(buttons)
                    self.assertEqual(m.get("dash_timer"), 0)
                    self.assertEqual(m.get("dash_used"), 0)

    def test_can_double_tap_while_holding_jump(self):
        m = self.machine
        for direction in (RIGHT, LEFT):
            m.call("init_game")
            m.platforms((0, 255, 192))
            m.position(100, 184)
            self.frame()
            self.frame(JUMP)
            self.frame(JUMP | direction)
            self.frame(JUMP)
            y = (m.get("pos_y", 1), m.get("pos_y"))
            self.frame(JUMP | direction)
            self.assertEqual(m.get("dash_timer"), self.duration-1)
            self.assertEqual((m.get("pos_y", 1), m.get("pos_y")), y)

    def test_ground_jump_has_priority_and_does_not_buffer_a_tap(self):
        m = self.machine
        m.platforms((0, 255, 192))
        m.position(80, 184)
        self.frame()
        self.frame(JUMP | RIGHT)  # jump wins, so this is not a first dash tap
        self.frame()
        self.frame(RIGHT)
        self.assertEqual(m.get("dash_timer"), 0)
        self.frame()
        self.frame(RIGHT)
        self.assertEqual(m.get("dash_timer"), self.duration-1)

    def test_air_charge_shared_and_recharged_on_landing(self):
        m = self.machine
        self.airborne(x=100)
        self.start_dash(LEFT)
        for _ in range(self.duration-1):
            self.frame()
        self.frame(RIGHT)
        self.frame()
        self.frame(RIGHT)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("dash_used"), 1)
        for _ in range(120):
            self.frame()
            if m.get("hit_y"):
                break
        self.frame()
        self.assertEqual(m.get("dash_used"), 0)
        self.frame(JUMP)
        self.frame(RIGHT)
        self.frame()
        self.frame(RIGHT)
        self.assertEqual(m.get("dash_timer"), self.duration-1)

    def test_apex_is_eligible(self):
        self.airborne()
        self.machine.velocity(0)
        self.start_dash(RIGHT)
        self.assertEqual(self.machine.get("dash_timer"), self.duration-1)

    def test_walls_and_one_sided_walls(self):
        m = self.machine
        for kind, x, direction, expected in (
            (physics.PLATFORM_WALL, 130, RIGHT, 138),
            (physics.PLATFORM_WALL, 153, LEFT, 145),
            (physics.PLATFORM_WALL_RIGHT, 145, LEFT, 145),
        ):
            with self.subTest(kind=kind, direction=direction):
                m.call("init_game")
                m.platform_records((kind, 96, 200, 145))
                self.airborne(x=x)
                self.start_dash(direction)
                self.frame()
                self.assertEqual(m.get("pos_x", 1), expected)
                self.assertEqual(m.get("dash_timer"), 0)
                self.assertEqual(m.get("dash_used"), 1)
        m.call("init_game")
        self.airborne(x=138)
        self.start_dash(RIGHT)
        self.assertEqual(m.get("pos_x", 1), 138+self.speed)

    def test_slope_landing_ends_and_recharges_air_dash(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_SLOPE_1_1, 31, 63, 192))
        self.airborne(x=45, y=164, fraction=0)
        self.start_dash(RIGHT)
        self.assertEqual(m.get("pos_x", 1), 47)
        self.assertEqual(m.get("pos_y", 1), 163)
        self.assertEqual(m.get("hit_y"), 1)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("dash_used"), 0)

    def test_spikes_hit_at_first_substep_and_respawn_resets_state(self):
        m = self.machine
        for x, direction, expected in ((200, RIGHT, 202), (225, LEFT, 222)):
            m.call("init_game")
            self.airborne(x=x, y=180)
            self.start_dash(direction)
            self.assertEqual(m.get("pos_x", 1), expected)
            self.assertEqual(m.get("death_timer"), 45)
            for _ in range(45):
                self.frame()
            self.assertEqual(m.get("pos_x", 1), 124)
            for name in ("dash_timer", "dash_used", "dash_button_down", "dash_steps",
                         "dash_direction", "dash_surface", "dash_dirs_down",
                         "dash_tap_direction", "dash_tap_timer", "hit_y"):
                self.assertEqual(m.get(name), 0)

    def test_dash_crosses_above_spikes(self):
        m = self.machine
        self.airborne(x=170, y=170)
        self.start_dash(RIGHT)
        for _ in range(self.duration-1):
            self.frame()
            self.assertEqual(m.get("death_timer"), 0)
            self.assertEqual(m.get("pos_y", 1), 170)
        self.assertEqual(m.get("pos_x", 1), 170+self.speed*self.duration)

    def test_camera_updates_once_in_either_direction(self):
        m = self.machine
        for x, direction, camera in ((170, RIGHT, 1), (80, LEFT, 255)):
            m.call("init_game")
            self.airborne(x=x)
            m.put("camera_x", 0)
            self.start_dash(direction)
            self.assertEqual(m.get("camera_x"), camera)

    def test_world_boundaries_stop_without_wrap(self):
        m = self.machine
        for x, direction, expected in ((254, RIGHT, 255), (1, LEFT, 0)):
            m.call("init_game")
            m.platform_records()
            self.airborne(x=x)
            self.start_dash(direction)
            self.assertEqual(m.get("pos_x", 1), expected)
            self.assertEqual(m.get("dash_timer"), 0)

    def test_walk_off_dash_never_allows_a_midair_jump(self):
        m = self.machine
        for release in (False, True):
            m.call("init_game")
            m.position(180, 152)
            for _ in range(40):
                self.frame(RIGHT)
                if m.get("pos_x", 1) >= 190 and not m.get("hit_y"):
                    break
            self.assertEqual(m.get("jump_latch"), 0)
            self.frame()
            self.frame(RIGHT)
            self.assertEqual(m.get("dash_timer"), self.duration-1)
            self.assertEqual(m.get("jump_latch"), 1)
            for _ in range(self.duration-1):
                self.frame(JUMP)
            if release:
                self.frame()
            self.frame(JUMP)
            self.assertEqual(m.get("jump_latch"), 1)
            self.assertLess(m.get("vel_y", 1), 128)


if __name__ == "__main__":
    unittest.main()
