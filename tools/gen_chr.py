#!/usr/bin/env python3
"""Preserve the original six tiles, append uphill-right artwork, pad to 8 KiB."""
from pathlib import Path
import sys


def ramp_tile(rise=1, base=7):
    # Color 0 is sky, 1 grass, 2 dirt. NES stores two eight-byte bitplanes.
    data = bytearray()
    for plane in range(2):
        for y in range(8):
            row = 0
            for x in range(8):
                surface = base - rise*x
                color = 0 if y < surface else 1 if y == surface else 2
                row |= ((color >> plane) & 1) << (7 - x)
            data.append(row)
    return data


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: gen_chr.py INPUT_TILES OUTPUT_CHR")
    original = Path(sys.argv[1]).read_bytes()
    if len(original) != 6 * 16:
        raise SystemExit("Expected six original tiles; the ramp must be tile 6")
    # Tile 6: 1:1. Tiles 7/8: upper/lower halves of a 2:1 diagonal.
    data = original + ramp_tile() + ramp_tile(2, 14) + ramp_tile(2, 6)
    Path(sys.argv[2]).write_bytes(data + bytes(8192 - len(data)))
