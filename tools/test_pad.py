#!/usr/bin/env python3
"""Controller reads preserve the previous held-button state."""
import unittest

import test_baseline_physics as physics


class ControllerMemory(list):
    """Supply the eight serial controller bits when the CPU reads $4016."""

    def __init__(self, memory, buttons):
        super().__init__(memory)
        self.bits = [(buttons >> shift) & 1 for shift in range(7, -1, -1)]
        self.reads = 0

    def __getitem__(self, address):
        if address == 0x4016:
            bit = self.bits[self.reads]
            self.reads += 1
            return bit
        return super().__getitem__(address)


class PadTests(unittest.TestCase):
    def test_previous_buttons_across_controller_reads(self):
        m = physics.BaselinePhysicsTests()
        m.setUp()
        previous = 0
        # First press, hold, added button, release, all buttons, and each bit.
        for buttons in (0, 0x80, 0x80, 0x81, 1, 0, 255, 0,
                        1, 2, 4, 8, 16, 32, 64, 128):
            with self.subTest(previous=previous, buttons=buttons):
                m.cpu.memory = ControllerMemory(m.cpu.memory, buttons)
                m.call("read_joypad1")
                self.assertEqual(m.cpu.memory.reads, 8)
                self.assertEqual(m.get("buttons"), buttons)
                self.assertEqual(m.get("buttons_prev"), previous)
                previous = buttons


if __name__ == "__main__":
    unittest.main()
