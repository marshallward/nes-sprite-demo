#!/usr/bin/env python3
"""Execute hazard/death/respawn routines in the built ROM (requires py65)."""
import unittest

import test_baseline_physics as physics


class GameplayTests(unittest.TestCase):
    def setUp(self):
        # Reuse the CPU harness, not its test methods.
        self.machine = physics.BaselinePhysicsTests()
        self.machine.setUp()
        self.machine.call("init_game")

    def frame(self, buttons=0):
        self.machine.put("buttons", buttons)
        self.machine.call("update_game")

    def test_inclusive_body_touch_from_all_sides(self):
        m = self.machine
        for x, y, expected in ((201, 184, False), (202, 184, True),
                                (222, 184, True), (223, 184, False),
                                (210, 175, False), (210, 176, True),
                                (210, 190, True), (210, 191, False),
                                (255, 184, False), (210, 255, False)):
            with self.subTest(x=x, y=y):
                m.position(x, y)
                m.call("check_hazards")
                self.assertEqual(bool(m.cpu.p & 1), expected)
                self.assertEqual(m.get("pos_x", 1), x)
                self.assertEqual(m.get("pos_y", 1), y)

    def test_spawn_is_safe(self):
        m = self.machine
        self.assertEqual(m.get("death_timer"), 0)
        for _ in range(120):
            self.frame()
            self.assertEqual(m.get("death_timer"), 0)
        self.assertEqual(m.get("pos_x", 1), 124)
        self.assertEqual(m.get("pos_y", 1), 184)

    def test_walking_into_spikes_starts_death_pause(self):
        m = self.machine
        m.position(200, 184)
        self.frame(physics.RIGHT)
        self.assertEqual(m.get("death_timer"), 0)
        self.frame(physics.RIGHT)
        self.assertEqual(m.get("pos_x", 1), 202)
        self.assertEqual(m.get("death_timer"), 45)
        self.assertEqual(m.get("vel_x", 1), 0)
        self.assertEqual(m.get("vel_y"), 0)
        self.assertEqual(m.get("vel_y", 1), 0)
        self.assertEqual(m.get("jump_latch"), 0)

    def test_death_freezes_motion_then_respawns_with_state_reset(self):
        m = self.machine
        m.position(210, 184, fraction=200)
        self.frame()
        self.assertEqual(m.get("death_timer"), 45)
        position = (m.get("pos_x", 1), m.get("pos_y", 1), m.get("pos_y"))
        camera = m.get("camera_x")
        for remaining in range(44, 0, -1):
            self.frame(physics.JUMP | physics.RIGHT)
            self.assertEqual(m.get("death_timer"), remaining)
            self.assertEqual((m.get("pos_x", 1), m.get("pos_y", 1), m.get("pos_y")), position)
            self.assertEqual(m.get("camera_x"), camera)
        m.put("ntable", 1)
        self.frame(physics.JUMP | physics.RIGHT)
        self.assertEqual(m.get("death_timer"), 0)
        self.assertEqual(m.get("pos_x", 1), 124)
        self.assertEqual(m.get("pos_y", 1), 160)
        for name in ("pos_y", "camera_x", "ntable", "vel_x", "vel_y", "jump_latch"):
            self.assertEqual(m.get(name), 0)
        self.assertEqual(m.get("vel_y", 1), 0)
        self.frame(physics.RIGHT)
        self.assertEqual(m.get("pos_x", 1), 125)

    def test_jump_can_clear_spike_patch(self):
        m = self.machine
        m.position(196, 184)  # leave enough room for the body to rise above tips
        self.frame()        # establish grounded state, as during ordinary play
        for _ in range(34):
            self.frame(physics.JUMP | physics.RIGHT)
            self.assertEqual(m.get("death_timer"), 0)
        self.assertEqual(m.get("pos_x", 1), 230)

    def test_falling_onto_spikes_kills(self):
        m = self.machine
        m.position(210, 160)
        for _ in range(60):
            self.frame()
            if m.get("death_timer"):
                break
        self.assertEqual(m.get("death_timer"), 45)

    def test_hazards_use_floor_corrected_not_free_position(self):
        m = self.machine
        m.platforms((0, 255, 176))
        m.position(210, 168)
        m.velocity(2048)  # free proposal would touch the spikes at Y184
        self.frame()
        self.assertEqual(m.get("pos_y", 1), 168)
        self.assertEqual(m.get("death_timer"), 0)

    def run_main_iteration(self):
        m = self.machine
        m.put("frame", 1)
        m.cpu.pc = m.symbols["main"]
        for _ in range(10000):
            m.cpu.step()
            if m.cpu.pc == m.symbols["main"]:
                return
        self.fail("Main loop failed to complete one update")

    def test_main_hides_dead_sprite_and_shows_respawn(self):
        m = self.machine
        m.position(210, 184)
        m.cpu.memory[0x201] = 4  # reset normally initializes the sprite tile
        self.frame()
        self.run_main_iteration()
        self.assertEqual(m.cpu.memory[0x200], 0xF0)
        self.assertEqual(m.get("death_timer"), 44)
        self.assertGreaterEqual(m.symbols["death_timer"], 0x300)
        self.assertLess(m.symbols["death_timer"], 0x800)
        m.put("death_timer", 1)
        self.run_main_iteration()
        self.assertEqual(m.cpu.memory[0x200], 160)
        self.assertEqual(m.cpu.memory[0x203], 124)
        self.assertEqual(m.cpu.memory[0x201], 4)

    def test_spike_tile_and_map_match_hazard_rectangle(self):
        m = self.machine
        address = m.symbols["hazard_data"]
        self.assertEqual(m.cpu.memory[address:address+4], [208, 223, 184, 191])
        map_address = m.symbols["bg0"]
        for col in (26, 27):
            self.assertEqual(m.cpu.memory[map_address + 23*32 + col], 9)
            self.assertEqual(m.cpu.memory[map_address + 24*32 + col], 5)
        rom = (physics.ROOT / "build/jump.nes").read_bytes()
        chr_data = rom[16+0x4000:]
        self.assertEqual(chr_data[:96], (physics.ROOT / "assets/ball.bin").read_bytes())
        self.assertEqual(len(chr_data), 8192)
        tile = chr_data[9*16:10*16]
        for y in range(8):
            for x in range(8):
                color = ((tile[y] >> (7-x)) & 1) | (((tile[y+8] >> (7-x)) & 1) << 1)
                self.assertEqual(bool(color), y >= 2*min(abs(x-3), abs(x-4)))


if __name__ == "__main__":
    unittest.main()
