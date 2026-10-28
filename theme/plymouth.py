#!/usr/bin/env python3
# plymouth.py by poligle
#
# Frames for the NIHIL boot splash: the NixOS snowflake as an LED matrix.
#   intro  the LEDs switch on from the centre outwards, each with a short flash
#   loop   a diagonal band of light sweeps across the lit snowflake (Glyph-like)
#
#   plymouth.py GRID OUTDIR [--pitch 9]
# GRID is a text file of digits 0-9: the coverage of each cell (theme/art/).

import argparse
import math
import os
import random

from PIL import Image, ImageDraw

INTRO, LOOP = 36, 60


def load(path):
    rows = [line.rstrip("\n") for line in open(path) if line.strip()]
    return [[int(c) / 9 for c in row] for row in rows]


def render(grid, pitch, levels, supersample=4):
    n = len(grid)
    size = n * pitch
    s = supersample
    img = Image.new("RGBA", (size * s, size * s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for j in range(n):
        for i in range(n):
            cx, cy = (i + 0.5) * pitch * s, (j + 0.5) * pitch * s
            level, scale = levels(i, j)
            if level <= 0:
                r = 0.14 * pitch * s
                draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(28, 28, 28, 255))
                continue
            r = (0.22 + 0.2 * scale) * pitch * s
            g = round(40 + 215 * level)
            draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(g, g, g, 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("grid")
    ap.add_argument("outdir")
    ap.add_argument("--pitch", type=int, default=9)
    args = ap.parse_args()

    grid = load(args.grid)
    n = len(grid)
    c = (n - 1) / 2
    rng = random.Random(1)
    # Final brightness of each LED from its coverage: solid, dim or off.
    lit = [[1.0 if v >= 0.45 else (0.42 if v >= 0.18 else 0.0) for v in row] for row in grid]
    # Arrival time of each LED in the intro: distance from the centre plus jitter.
    arrival = [[min(0.95, math.hypot(i - c, j - c) / (c * 1.45) + 0.12 * rng.random()) for i in range(n)] for j in range(n)]
    os.makedirs(args.outdir, exist_ok=True)

    for f in range(INTRO):
        t = f / (INTRO - 1)

        def levels(i, j):
            if lit[j][i] == 0 or arrival[j][i] > t:
                return 0, 0
            age = (t - arrival[j][i]) * (INTRO - 1)
            flash = max(0.0, 1 - age / 4)  # a new LED flashes for ~4 frames
            return min(1.0, lit[j][i] * 0.86 + 0.5 * flash), 0.75 + 0.25 * flash

        render(grid, args.pitch, levels).save(os.path.join(args.outdir, f"frame-{f}.png"))

    for f in range(LOOP):
        pos = -0.35 + 1.7 * f / LOOP  # band centre along the diagonal, in grid units

        def levels(i, j):
            if lit[j][i] == 0:
                return 0, 0
            d = (i + j) / (2 * (n - 1)) - pos
            band = math.exp(-(d / 0.09) ** 2)
            return min(1.0, lit[j][i] * 0.86 + 0.14 * band), 0.75 + 0.25 * band

        render(grid, args.pitch, levels).save(os.path.join(args.outdir, f"frame-{INTRO + f}.png"))

    # Static frame for prompts and the end of the boot.
    render(grid, args.pitch, lambda i, j: (lit[j][i] * 0.86, 0.75) if lit[j][i] else (0, 0)).save(
        os.path.join(args.outdir, "logo.png"))


if __name__ == "__main__":
    main()
