#!/usr/bin/env python3
# plymouth.py by poligle

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


def colour(hex):
    return tuple(int(hex[i:i + 2], 16) for i in (0, 2, 4))


def pill(width, height, fill, line, supersample=4):
    s = supersample
    img = Image.new("RGBA", (width * s, height * s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((0, 0, width * s - 1, height * s - 1), radius=height * s / 2, fill=line + (255,))
    draw.rounded_rectangle((s, s, width * s - 1 - s, height * s - 1 - s), radius=height * s / 2 - s, fill=fill + (255,))
    return img.resize((width, height), Image.LANCZOS)


def dot(size, fill, supersample=4):
    s = supersample
    img = Image.new("RGBA", (size * s, size * s), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((0, 0, size * s - 1, size * s - 1), fill=fill + (255,))
    return img.resize((size, size), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("grid")
    ap.add_argument("outdir")
    ap.add_argument("--pitch", type=int, default=9)
    ap.add_argument("--colours", nargs=4, metavar=("VOID", "LINE", "SIGNAL", "INK"), default=("000000", "2A2A2A", "D71921", "F2F2F2"))
    args = ap.parse_args()

    grid = load(args.grid)
    n = len(grid)
    c = (n - 1) / 2
    rng = random.Random(1)
    lit = [[1.0 if v >= 0.45 else (0.42 if v >= 0.18 else 0.0) for v in row] for row in grid]
    raw = [[min(0.95, math.hypot(i - c, j - c) / (c * 1.45) + 0.12 * rng.random()) for i in range(n)] for j in range(n)]
    first = min(raw[j][i] for j in range(n) for i in range(n) if lit[j][i])
    last = max(raw[j][i] for j in range(n) for i in range(n) if lit[j][i])
    start = 1 / (INTRO - 1)
    arrival = [[start + (raw[j][i] - first) / (last - first) * (0.75 - start) for i in range(n)] for j in range(n)]
    os.makedirs(args.outdir, exist_ok=True)

    for f in range(INTRO):
        t = f / (INTRO - 1)

        def levels(i, j):
            if lit[j][i] == 0 or arrival[j][i] > t:
                return 0, 0
            age = (t - arrival[j][i]) * (INTRO - 1)
            flash = max(0.0, 1 - age / 4)
            return min(1.0, lit[j][i] * 0.86 + 0.5 * flash), 0.75 + 0.25 * flash

        render(grid, args.pitch, levels).save(os.path.join(args.outdir, f"frame-{f}.png"))

    for f in range(LOOP):
        pos = -0.35 + 1.7 * f / LOOP

        def levels(i, j):
            if lit[j][i] == 0:
                return 0, 0
            d = (i + j) / (2 * (n - 1)) - pos
            band = math.exp(-(d / 0.09) ** 2)
            return min(1.0, lit[j][i] * 0.86 + 0.14 * band), 0.75 + 0.25 * band

        render(grid, args.pitch, levels).save(os.path.join(args.outdir, f"frame-{INTRO + f}.png"))

    render(grid, args.pitch, lambda i, j: (lit[j][i] * 0.86, 0.75) if lit[j][i] else (0, 0)).save(
        os.path.join(args.outdir, "logo.png"))

    # The disk's password, as the login screen and the lock screen ask: a pill 280 by 46, its
    # edge red after a password that didn't open the disk, dots of 10 and the LED of 6.
    void, line, signal, ink = (colour(c) for c in args.colours)
    pill(280, 46, void, line).save(os.path.join(args.outdir, "field.png"))
    pill(280, 46, void, signal).save(os.path.join(args.outdir, "field-wrong.png"))
    dot(10, ink).save(os.path.join(args.outdir, "dot.png"))
    dot(6, signal).save(os.path.join(args.outdir, "led.png"))


if __name__ == "__main__":
    main()
