#!/usr/bin/env python3
"""Air-dash behavior through update_game in the assembled ROM (requires py65)."""
import unittest

import test_baseline_physics as physics


DASH = physics.JUMP
B_BUTTON = 0x40
RIGHT = physics.RIGHT
LEFT = physics.LEFT
JUMP = physics.JUMP


class DashTests(unittest.TestCase):
    def setUp(self):
        self.machine = physics.BaselinePhysicsTests()
        self.machine.setUp()
        self.machine.call("init_game")
        self.speed = self.machine.symbols["DASH_PIXELS"]
        self.duration = self.machine.symbols["DASH_FRAMES"]

    def frame(self, buttons=0):
        self.machine.put("buttons", buttons)
        self.machine.call("update_game")

    def airborne(self, x=48, y=120, fraction=123):
        self.machine.position(x, y, fraction=fraction)
        self.machine.put("hit_y", 0)

    def test_configured_burst_distance_without_vertical_motion(self):
        m = self.machine
        self.airborne()
        m.velocity(-512)
        for frame in range(1, self.duration+1):
            self.frame(DASH | RIGHT)
            self.assertEqual(m.get("pos_x", 1), 48 + self.speed*frame)
            self.assertEqual(m.get("pos_y", 1), 120)
            self.assertEqual(m.get("pos_y"), 123)
            self.assertEqual(m.get("dash_timer"), self.duration-frame)
            self.assertEqual(m.get("dash_used"), 1)
            self.assertEqual(m.get("vel_y"), 0)
            self.assertEqual(m.get("vel_y", 1), 0)
        self.frame()
        self.assertEqual(m.get("pos_x", 1), 48+self.speed*self.duration)
        self.assertEqual(m.get("pos_y"), 183)
        self.assertEqual(m.get("vel_y"), 60)
        self.assertEqual(m.get("dash_timer"), 0)

    def test_burst_continues_after_releasing_or_reversing_input(self):
        m = self.machine
        self.airborne()
        self.frame(DASH | RIGHT)
        for _ in range(self.duration-1):
            self.frame(LEFT)
        self.assertEqual(m.get("pos_x", 1), 48+self.speed*self.duration)
        self.assertEqual(m.get("pos_y", 1), 120)
        self.assertEqual(m.get("dash_timer"), 0)

    def test_dash_requires_airborne_right_and_a_new_a_press(self):
        m = self.machine
        m.position(48, 184)
        self.frame()  # establish standing contact before the initial A jump
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("pos_x", 1), 49)
        self.assertEqual(m.get("dash_timer"), 0)
        self.frame(JUMP | DASH | RIGHT)
        self.assertEqual(m.get("dash_timer"), 0)  # held A is not a new press
        self.frame(RIGHT)
        old_x = m.get("pos_x", 1)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("pos_x", 1), old_x+self.speed)
        self.assertEqual(m.get("dash_timer"), 7)

    def test_no_direction_or_both_directions_do_not_start_dash(self):
        for buttons in (DASH, DASH | RIGHT | LEFT, RIGHT, LEFT):
            with self.subTest(buttons=buttons):
                self.machine.call("init_game")
                self.airborne()
                self.frame(buttons)
                self.assertEqual(self.machine.get("dash_timer"), 0)
                self.assertEqual(self.machine.get("dash_used"), 0)

    def test_release_and_repress_cannot_dash_twice_in_same_airtime(self):
        m = self.machine
        self.airborne()
        for _ in range(8):
            self.frame(DASH | RIGHT)
        self.frame()
        old_x = m.get("pos_x", 1)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("pos_x", 1), old_x+1)

    def test_dash_can_start_near_apex_despite_zero_integer_velocity(self):
        m = self.machine
        self.airborne()
        m.velocity(0)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("dash_timer"), 7)

    def test_wall_stops_dash_at_first_blocked_pixel(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_WALL, 96, 200, 145))
        self.airborne(x=130)
        self.frame(DASH | RIGHT)
        self.frame()
        self.assertEqual(m.get("pos_x", 1), 138)
        self.frame()
        self.assertEqual(m.get("pos_x", 1), 138)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("vel_x", 1), 0)
        self.assertEqual(m.get("dash_used"), 1)

    def test_one_sided_wall_allows_dash_exit(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_WALL_RIGHT, 96, 200, 145))
        self.airborne(x=138)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("pos_x", 1), 138+self.speed)
        self.assertEqual(m.get("dash_timer"), 7)
        self.assertEqual(m.get("hit_x"), 0)

    def test_slope_contact_ends_dash_instead_of_bursting_uphill(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_SLOPE_1_1, 31, 63, 192))
        self.airborne(x=45, y=164, fraction=0)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("pos_x", 1), 47)  # slope first touched at substep 2
        self.assertEqual(m.get("pos_y", 1), 163)
        self.assertEqual(m.get("hit_y"), 1)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("dash_used"), 0)

    def test_spikes_kill_at_intermediate_step_not_end_of_burst(self):
        m = self.machine
        self.airborne(x=200, y=180)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("pos_x", 1), 202)  # first body touch, before X=204
        self.assertEqual(m.get("death_timer"), 45)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("dash_used"), 0)  # death resets dash state

    def test_dash_can_cross_over_spikes_without_falling(self):
        m = self.machine
        self.airborne(x=170, y=170)
        for _ in range(self.duration):
            self.frame(DASH | RIGHT)
            self.assertEqual(m.get("pos_y", 1), 170)
            self.assertEqual(m.get("death_timer"), 0)
        self.assertEqual(m.get("pos_x", 1), 170+self.speed*self.duration)

    def test_landing_recharges_dash_without_held_button_retrigger(self):
        m = self.machine
        self.airborne()
        for _ in range(8):
            self.frame(DASH | RIGHT)
        for _ in range(120):
            self.frame(DASH)
            if m.get("hit_y"):
                break
        self.assertEqual(m.get("hit_y"), 1)
        self.frame(DASH)
        self.assertEqual(m.get("dash_used"), 0)
        self.frame()  # release A on the floor to rearm normal jumping
        self.frame(JUMP)
        self.assertEqual(m.get("dash_timer"), 0)
        self.frame()
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("dash_timer"), 7)

    def test_camera_updates_once_per_dash_update(self):
        m = self.machine
        self.airborne(x=170)
        m.put("camera_x", 0)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("pos_x", 1), 170+self.speed)
        self.assertEqual(m.get("camera_x"), 1)

    def test_dash_stops_at_byte_boundary_instead_of_wrapping(self):
        m = self.machine
        m.platform_records()
        self.airborne(x=254)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("pos_x", 1), 255)
        self.assertEqual(m.get("dash_timer"), 0)

    def test_respawn_clears_all_dash_state(self):
        m = self.machine
        self.airborne(x=200, y=180)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("death_timer"), 45)
        for _ in range(45):
            self.frame()
        self.assertEqual(m.get("pos_x", 1), 124)
        self.assertEqual(m.get("pos_y", 1), 160)
        for name in ("dash_timer", "dash_used", "dash_button_down", "dash_steps",
                     "dash_direction", "hit_y"):
            self.assertEqual(m.get(name), 0)

    def test_left_dash_has_configured_distance_fixed_direction_and_height(self):
        m = self.machine
        self.airborne(x=100)
        m.velocity(512)
        self.frame(DASH | LEFT)
        self.assertEqual(m.get("dash_direction"), 255)
        for step in range(1, self.duration+1):
            if step > 1:
                self.frame(RIGHT)  # cannot steer an active left burst
            self.assertEqual(m.get("pos_x", 1), 100 - self.speed*step)
            self.assertEqual(m.get("pos_y", 1), 120)
            self.assertEqual(m.get("pos_y"), 123)
            self.assertEqual(m.get("dash_timer"), self.duration-step)
        self.frame()
        self.assertEqual(m.get("vel_y"), 60)

    def test_left_dash_stops_at_wall(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_WALL, 96, 200, 145))
        self.airborne(x=153)
        self.frame(DASH | LEFT)
        self.frame()
        self.assertEqual(m.get("pos_x", 1), 145)
        self.frame()
        self.assertEqual(m.get("pos_x", 1), 145)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("vel_x", 1), 0)

    def test_left_dash_obeys_right_facing_wall(self):
        m = self.machine
        m.platform_records((physics.PLATFORM_WALL_RIGHT, 96, 200, 145))
        self.airborne(x=145)
        self.frame(DASH | LEFT)
        self.assertEqual(m.get("pos_x", 1), 145)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("hit_x"), 1)

    def test_left_dash_hits_spikes_at_first_touch(self):
        m = self.machine
        self.airborne(x=225, y=180)
        self.frame(DASH | LEFT)
        self.assertEqual(m.get("pos_x", 1), 222)
        self.assertEqual(m.get("death_timer"), 45)
        self.assertEqual(m.get("dash_timer"), 0)

    def test_dash_recharge_is_shared_between_directions(self):
        m = self.machine
        self.airborne(x=100)
        for _ in range(8):
            self.frame(DASH | LEFT)
        self.frame()
        old_x = m.get("pos_x", 1)
        self.frame(DASH | RIGHT)
        self.assertEqual(m.get("pos_x", 1), old_x+1)
        self.assertEqual(m.get("dash_timer"), 0)

    def test_left_dash_camera_moves_once_per_update(self):
        m = self.machine
        self.airborne(x=80)
        m.put("camera_x", 0)
        self.frame(DASH | LEFT)
        self.assertEqual(m.get("pos_x", 1), 80-self.speed)
        self.assertEqual(m.get("camera_x"), 255)

    def test_left_dash_stops_at_zero_instead_of_wrapping(self):
        m = self.machine
        m.platform_records()
        self.airborne(x=1)
        self.frame(DASH | LEFT)
        self.assertEqual(m.get("pos_x", 1), 0)
        self.assertEqual(m.get("dash_timer"), 0)

    def test_holding_jump_through_ascent_does_not_start_dash(self):
        m = self.machine
        m.platforms((0, 255, 192))
        m.position(80, 184)
        self.frame()  # normal standing contact before the initial jump press
        for step in range(1, 17):
            self.frame(JUMP | RIGHT)
            self.assertEqual(m.get("pos_x", 1), 80+step)
            self.assertEqual(m.get("dash_timer"), 0)
            self.assertEqual(m.get("dash_used"), 0)
        self.assertLess(m.get("pos_y", 1), 184)

    def test_jump_release_repress_dashes_in_either_direction(self):
        m = self.machine
        for direction, sign in ((RIGHT, 1), (LEFT, -1)):
            with self.subTest(direction=direction):
                m.call("init_game")
                m.platforms((0, 255, 192))
                m.position(80, 184)
                self.frame()
                self.frame(JUMP)
                self.assertEqual(m.get("dash_timer"), 0)
                self.frame()  # release A in midair
                x, y, fraction = m.get("pos_x", 1), m.get("pos_y", 1), m.get("pos_y")
                for step in range(1, self.duration+1):
                    self.frame(JUMP | direction)
                    self.assertEqual(m.get("pos_x", 1), x+sign*self.speed*step)
                    self.assertEqual(m.get("pos_y", 1), y)
                    self.assertEqual(m.get("pos_y"), fraction)
                    self.assertEqual(m.get("dash_timer"), self.duration-step)
                self.frame()
                x = m.get("pos_x", 1)
                self.frame(JUMP | direction)
                self.assertEqual(m.get("dash_timer"), 0)
                self.assertEqual(m.get("pos_x", 1), x+sign)

    def test_b_does_not_dash_while_original_jump_press_is_held(self):
        m = self.machine
        m.platforms((0, 255, 192))
        m.position(80, 184)
        self.frame()
        self.frame(JUMP | RIGHT)
        self.assertEqual(m.get("dash_timer"), 0)
        self.frame(JUMP | B_BUTTON | RIGHT)
        self.assertEqual(m.get("pos_x", 1), 82)
        self.assertEqual(m.get("dash_timer"), 0)
        self.assertEqual(m.get("dash_used"), 0)

    def test_b_with_either_direction_never_starts_dash(self):
        m = self.machine
        for direction, sign in ((RIGHT, 1), (LEFT, -1)):
            with self.subTest(direction=direction):
                m.call("init_game")
                self.airborne(x=100)
                self.frame(B_BUTTON | direction)
                self.assertEqual(m.get("pos_x", 1), 100+sign)
                self.assertEqual(m.get("dash_timer"), 0)
                self.assertEqual(m.get("dash_used"), 0)

    def test_a_can_dash_when_b_was_held_without_direction(self):
        m = self.machine
        self.airborne()
        self.frame(B_BUTTON)  # B is unassigned and must not interfere with A
        self.assertEqual(m.get("dash_timer"), 0)
        self.frame(B_BUTTON | JUMP | RIGHT)
        self.assertEqual(m.get("dash_timer"), 7)

    def test_airborne_a_without_horizontal_direction_does_not_dash(self):
        self.airborne()
        self.frame(JUMP)
        self.assertEqual(self.machine.get("dash_timer"), 0)
        self.assertEqual(self.machine.get("dash_used"), 0)

    def test_walk_off_dash_does_not_allow_jump_before_landing(self):
        m = self.machine
        for release_repress in (False, True):
            with self.subTest(release_repress=release_repress):
                m.call("init_game")
                m.position(180, 152)
                for _ in range(40):
                    self.frame(RIGHT)
                    if m.get("pos_x", 1) >= 190 and not m.get("hit_y"):
                        break
                self.assertEqual(m.get("hit_y"), 0)
                self.assertEqual(m.get("jump_latch"), 0)  # walked, did not jump
                self.frame(JUMP | RIGHT)
                self.assertEqual(m.get("jump_latch"), 1)
                for _ in range(self.duration-1):
                    self.frame(JUMP)  # direction already latched for the burst
                self.assertEqual(m.get("dash_timer"), 0)
                old_y = m.get("pos_y", 1)
                if release_repress:
                    self.frame()
                self.frame(JUMP)
                self.assertEqual(m.get("jump_latch"), 1)
                self.assertLess(m.get("vel_y", 1), 128)  # no upward impulse
                self.assertGreaterEqual(m.get("pos_y", 1), old_y)


if __name__ == "__main__":
    unittest.main()
