#!/usr/bin/env python3
# dotmatrix.py by poligle
#
# NIHIL wallpaper generator: renders a photo as an LED dot matrix.
#
#   dotmatrix.py SOURCE OUTDIR --output eDP-1:1920x1200 --output DP-1:1080x1920:9
#
# The image is cover-cropped to each output's native size so every dot lands
# on exact pixels (no scaling blur afterwards). Each cell of `pitch` px gets:
#   - an "off" LED (dark grey), so the matrix texture is always visible;
#   - a lit LED whose radius and brightness grow with the cell luminance.
# The black point is raised so the sky stays off, and isolated peaks (stars)
# light their cell even when the cell average is dark.

import argparse
import os

import numpy as np
from PIL import Image, ImageDraw


def cover(img, width, height):
    scale = max(width / img.width, height / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = (img.width - width) // 2
    top = (img.height - height) // 2
    return img.crop((left, top, left + width, top + height))


def luminance(img):
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    low, high = np.percentile(lum, [2.0, 99.7])
    return np.clip((lum - low) / max(high - low, 1e-6), 0.0, 1.0)


def render(source, width, height, pitch, supersample=3, gamma=1.25,
           black=0.10, star=0.55, star_gain=0.9, off_level=0.07):
    lum = luminance(cover(source, width, height))

    cols, rows = width // pitch, height // pitch
    ox, oy = (width - cols * pitch) // 2, (height - rows * pitch) // 2
    cells = lum[oy:oy + rows * pitch, ox:ox + cols * pitch].reshape(rows, pitch, cols, pitch)

    level = np.clip((cells.mean(axis=(1, 3)) - black) / (1.0 - black), 0.0, 1.0) ** gamma
    stars = np.clip((cells.max(axis=(1, 3)) - star) / (1.0 - star), 0.0, 1.0)
    level = np.maximum(level, star_gain * stars)

    s = supersample
    step = pitch * s
    canvas = Image.new("L", (width * s, height * s), 0)
    draw = ImageDraw.Draw(canvas)
    r_max, r_off = 0.44 * step, 0.16 * step
    off = round(255 * off_level)

    for j in range(rows):
        cy = oy * s + j * step + step / 2
        for i in range(cols):
            cx = ox * s + i * step + step / 2
            draw.ellipse((cx - r_off, cy - r_off, cx + r_off, cy + r_off), fill=off)
            v = float(level[j, i])
            if v <= 0.02:
                continue
            radius = r_max * (0.25 + 0.75 * np.sqrt(v))
            grey = round(30 + 206 * v)
            if grey > off:
                draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=grey)

    return canvas.resize((width, height), Image.LANCZOS)


def parse_output(spec, default_pitch):
    name, rest = spec.split(":", 1)
    parts = rest.split(":")
    width, height = (int(v) for v in parts[0].lower().split("x"))
    pitch = int(parts[1]) if len(parts) > 1 else default_pitch
    return name, width, height, pitch


def main():
    parser = argparse.ArgumentParser(description="NIHIL dot-matrix wallpaper generator")
    parser.add_argument("source")
    parser.add_argument("outdir")
    parser.add_argument("--output", action="append", required=True,
                        help="NAME:WIDTHxHEIGHT[:PITCH], repeatable")
    parser.add_argument("--pitch", type=int, default=9)
    args = parser.parse_args()

    source = Image.open(args.source)
    source.load()
    os.makedirs(args.outdir, exist_ok=True)

    for spec in args.output:
        name, width, height, pitch = parse_output(spec, args.pitch)
        image = render(source, width, height, pitch).convert("RGB")
        image.save(os.path.join(args.outdir, f"{name}.png"), optimize=True)


if __name__ == "__main__":
    main()
