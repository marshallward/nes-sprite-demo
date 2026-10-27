#!/usr/bin/env python3
"""8.8 X tests using the actual ROM walking speed, not the legacy 1px fixture."""
import unittest

import test_baseline_physics as physics


LEFT, RIGHT, JUMP = physics.LEFT, physics.RIGHT, physics.JUMP


class SubpixelXTests(unittest.TestCase):
    def setUp(self):
        self.machine = physics.BaselinePhysicsTests()
        self.machine.walk_speed_override = None  # test the shipped $00C0 speed
        self.machine.setUp()
        self.machine.call("init_game")

    def word(self, name, signed=False):
        value = self.machine.get(name) | (self.machine.get(name, 1) << 8)
        return value-65536 if signed and value >= 32768 else value

    def frame(self, buttons=0, gameplay=False):
        self.machine.put("buttons", buttons)
        self.machine.call("update_game" if gameplay else "update_move")

    def test_shipped_speed_and_fractional_carry_to_right(self):
        m = self.machine
        self.assertEqual(self.word("walk_speed"), 192)
        m.position(80, 120)
        for x, fraction in ((80, 192), (81, 128), (82, 64), (83, 0)):
            self.frame(RIGHT)
            self.assertEqual(m.get("pos_x", 1), x)
            self.assertEqual(m.get("pos_x"), fraction)
            self.assertEqual(self.word("vel_x", signed=True), 192)

    def test_fractional_borrow_to_left_and_return_trip(self):
        m = self.machine
        m.position(80, 120)
        for x, fraction in ((79, 64), (78, 128), (77, 192), (77, 0)):
            self.frame(LEFT)
            self.assertEqual(m.get("pos_x", 1), x)
            self.assertEqual(m.get("pos_x"), fraction)
            self.assertEqual(self.word("vel_x", signed=True), -192)
        for _ in range(4):
            self.frame(RIGHT)
        self.assertEqual(self.word("pos_x"), 80*256)

    def test_no_input_and_opposing_directions_preserve_fraction(self):
        m = self.machine
        m.position(80, 120, x_fraction=73)
        for buttons in (0, LEFT | RIGHT):
            self.frame(buttons)
            self.assertEqual(self.word("pos_x"), 80*256+73)
            self.assertEqual(self.word("vel_x"), 0)

    def test_proposal_matches_signed_fixed_point_addition(self):
        m = self.machine
        for fraction in range(0, 256, 17):
            for direction, speed in ((RIGHT, 192), (LEFT, -192)):
                with self.subTest(fraction=fraction, direction=direction):
                    m.position(80, 120, x_fraction=fraction)
                    m.put("buttons", direction)
                    m.call("update_x")
                    self.assertEqual(self.word("pos_x"), 80*256+fraction)
                    self.assertEqual(self.word("next_x"), 80*256+fraction+speed)

    def test_wall_clears_fraction_and_both_velocity_bytes(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_WALL, 96, 200, 145))
        for x, fraction, direction, expected_x in ((138, 192, RIGHT, 138),
                                                  (145, 0, LEFT, 145)):
            with self.subTest(direction=direction):
                m.position(x, 120, x_fraction=fraction)
                self.frame(direction)
                self.assertEqual(m.get("hit_x"), 1)
                self.assertEqual(self.word("pos_x"), expected_x*256)
                self.assertEqual(self.word("next_x"), expected_x*256)
                self.assertEqual(self.word("vel_x"), 0)

    def test_integer_velocity_with_zero_fraction_still_checks_wall(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_WALL, 96, 200, 145))
        m.set_walk_speed(256)
        m.position(138, 120)
        self.frame(RIGHT)
        self.assertEqual(m.get("hit_x"), 1)
        self.assertEqual(self.word("pos_x"), 138*256)

    def test_one_sided_wall_uses_sign_of_full_velocity(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_WALL_RIGHT, 96, 200, 145))
        m.position(138, 120)
        for _ in range(4):
            self.frame(RIGHT)
        self.assertEqual(self.word("pos_x"), 141*256)
        m.position(145, 120)
        self.frame(LEFT)
        self.assertEqual(m.get("hit_x"), 1)
        self.assertEqual(self.word("pos_x"), 145*256)

    def test_default_speed_follows_both_demo_slopes(self):
        m = self.machine
        for start_x, base, end, rise, count in ((20, 31, 63, 1, 40),
                                               (84, 95, 111, 2, 30)):
            with self.subTest(rise=rise):
                m.call("init_move")
                m.position(start_x, 184)
                expected_x = start_x*256
                for direction, sign in ((RIGHT, 1), (LEFT, -1)):
                    for _ in range(count):
                        self.frame(direction)
                        expected_x += sign*192
                        pixel_x = expected_x >> 8
                        surface = 192 - rise*(min(end, max(base, pixel_x+5))-base)
                        self.assertEqual(self.word("pos_x"), expected_x)
                        self.assertEqual(m.get("pos_y", 1), surface-8)
                        self.assertEqual(m.get("hit_y"), 1)
                        self.assertEqual(m.get("hit_x"), 0)

    def test_dash_retains_fractional_x_and_current_speed(self):
        m = self.machine
        m.position(80, 120, fraction=123, x_fraction=192)
        m.put("hit_y", 0)
        speed, duration = m.symbols["DASH_PIXELS"], m.symbols["DASH_FRAMES"]
        for buttons in (RIGHT, 0):
            m.put("buttons", buttons)
            m.call("update_dash")
        for step in range(1, duration+1):
            self.frame(RIGHT, gameplay=True)
            self.assertEqual(self.word("pos_x"), (80+step*speed)*256+192)
            self.assertEqual(m.get("pos_y", 1), 120)
            self.assertEqual(m.get("pos_y"), 123)

    def test_double_tap_surface_dash_after_fractional_first_step(self):
        m = self.machine
        m.platforms((0, 255, 192))
        m.position(80, 184)
        self.frame(gameplay=True)
        self.frame(RIGHT, gameplay=True)
        self.frame(gameplay=True)
        self.frame(RIGHT, gameplay=True)
        self.assertEqual(m.get("dash_timer"), m.symbols["DASH_FRAMES"]-1)
        self.assertEqual(self.word("pos_x"), 80*256+192+m.symbols["DASH_PIXELS"]*256)
        self.assertEqual(m.get("pos_y", 1), 184)

    def test_hazards_read_integer_x_and_respawn_clears_fraction(self):
        m = self.machine
        m.position(201, 184, x_fraction=192)
        self.frame(gameplay=True)
        self.assertEqual(m.get("death_timer"), 0)
        self.frame(RIGHT, gameplay=True)
        self.assertEqual(m.get("pos_x", 1), 202)
        self.assertEqual(m.get("death_timer"), 45)
        for _ in range(45):
            self.frame(gameplay=True)
        self.assertEqual(self.word("pos_x"), 124*256)

    def test_camera_ignores_fraction_until_pixel_threshold_is_crossed(self):
        m = self.machine
        m.position(160, 120)
        m.put("camera_x", 0)
        self.frame(RIGHT)
        self.assertEqual(m.get("camera_x"), 0)
        self.frame(RIGHT)
        self.assertEqual(m.get("camera_x"), 1)
        self.assertEqual(m.get("pos_x", 1), 161)
        self.assertEqual(m.get("pos_x"), 128)

    def test_main_sprite_x_uses_integer_minus_camera(self):
        m = self.machine
        m.position(100, 120, x_fraction=192)
        m.put("camera_x", 4)
        m.put("frame", 1)
        m.cpu.pc = m.symbols["main"]
        for _ in range(10000):
            m.cpu.step()
            if m.cpu.pc == m.symbols["main"]:
                break
        else:
            self.fail("Main loop did not finish")
        self.assertEqual(m.cpu.memory[0x203], 96)
        self.assertEqual(m.get("pos_x"), 192)


if __name__ == "__main__":
    unittest.main()
