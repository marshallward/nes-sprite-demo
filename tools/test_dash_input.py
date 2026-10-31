#!/usr/bin/env python3
"""Double-tap detection and its integration with burst movement."""
import unittest

import test_baseline_physics as physics

LEFT, RIGHT, JUMP = physics.LEFT, physics.RIGHT, physics.JUMP


class DashInputTests(unittest.TestCase):
    def setUp(self):
        self.machine = physics.BaselinePhysicsTests()
        self.machine.setUp()
        self.window = self.machine.symbols["DASH_TAP_WINDOW"]

    def read(self, buttons=0):
        self.machine.put("buttons_prev", self.machine.get("buttons"))
        self.machine.put("buttons", buttons)
        self.machine.call("read_dash")
        return self.machine.cpu.a

    def test_double_tap_in_either_direction(self):
        for direction, expected in ((RIGHT, 1), (LEFT, 255)):
            with self.subTest(direction=direction):
                self.machine.call("init_dash")
                self.assertEqual(self.read(direction), 0)
                self.assertEqual(self.read(), 0)
                self.assertEqual(self.read(direction), expected)

    def test_hold_is_not_a_second_press(self):
        for _ in range(self.window * 2):
            self.assertEqual(self.read(RIGHT), 0)

    def test_window_boundary_and_expiry(self):
        for wait, expected in ((self.window-1, 1), (self.window, 0)):
            with self.subTest(wait=wait):
                self.machine.call("init_dash")
                self.read(RIGHT)
                for _ in range(wait):
                    self.read()
                self.assertEqual(self.read(RIGHT), expected)

    def test_opposite_tap_starts_a_new_pair(self):
        self.read(RIGHT)
        self.read()
        self.assertEqual(self.read(LEFT), 0)
        self.read()
        self.assertEqual(self.read(LEFT), 255)

    def test_both_directions_clear_pending_pair(self):
        self.read(RIGHT)
        self.read()
        self.assertEqual(self.read(LEFT | RIGHT), 0)
        self.read()
        self.assertEqual(self.read(RIGHT), 0)

    def test_pair_is_consumed(self):
        self.read(RIGHT)
        self.read()
        self.assertEqual(self.read(RIGHT), 1)
        self.read()
        self.assertEqual(self.read(RIGHT), 0)

    def test_a_and_b_do_not_trigger_or_interfere(self):
        for other in (JUMP, 0x40, JUMP | 0x40):
            with self.subTest(other=other):
                self.machine.call("init_dash")
                self.assertEqual(self.read(other), 0)
                self.assertEqual(self.read(other | RIGHT), 0)
                self.assertEqual(self.read(other), 0)
                self.assertEqual(self.read(other | RIGHT), 1)

    def test_init_clears_pending_tap_but_preserves_held_input(self):
        self.read(LEFT)
        self.machine.call("init_move")
        for name in ("dash_tap_direction", "dash_tap_timer"):
            self.assertEqual(self.machine.get(name), 0)
        self.assertEqual(self.machine.get("buttons"), LEFT)
        self.assertEqual(self.read(LEFT), 0)
        self.assertEqual(self.machine.get("dash_tap_timer"), 0)

    def test_dash_does_not_change_shared_button_state(self):
        m = self.machine
        m.put("buttons_prev", JUMP)
        m.put("buttons", JUMP | RIGHT)
        m.call("read_dash")
        self.assertEqual(m.get("buttons_prev"), JUMP)
        self.assertEqual(m.get("buttons"), JUMP | RIGHT)

    def test_movement_bursts_on_double_tap(self):
        m = self.machine
        m.platform_records()
        m.position(80, 100)
        speed = m.symbols["DASH_SPEED"]
        for buttons, x in ((RIGHT, 81), (0, 81), (RIGHT, 81+speed)):
            m.frame(buttons)
            self.assertEqual(m.get("pos_x"), x)

    def test_burst_duration_direction_and_gravity_resume(self):
        m = self.machine
        for direction, sign in ((RIGHT, 1), (LEFT, -1)):
            with self.subTest(direction=direction):
                m.call("init_move")
                m.put("buttons", 0)
                m.platform_records()
                m.position(100, 100)
                m.frame(direction)
                m.frame()
                x, y, fraction = m.get("pos_x"), m.get("pos_y", 1), m.get("pos_y")
                m.velocity(-512)
                duration = m.symbols["DASH_FRAMES"]
                for step in range(1, duration+1):
                    m.frame(direction if step == 1 else LEFT | RIGHT | JUMP)
                    self.assertEqual(m.get("pos_x"), x+sign*m.symbols["DASH_SPEED"]*step)
                    self.assertEqual(m.get("pos_y", 1), y)
                    self.assertEqual(m.get("pos_y"), fraction)
                    self.assertEqual(m.get("dash_timer"), duration-step)
                m.frame(JUMP)
                self.assertEqual(m.get("vel_x"), 0)
                self.assertEqual(m.get("vel_y"), 60)
                self.assertEqual(m.get("vel_y", 1), 0)


if __name__ == "__main__":
    unittest.main()
