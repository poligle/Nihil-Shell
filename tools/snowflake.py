#!/usr/bin/env python3
# snowflake.py by poligle

import sys

from PIL import Image, ImageDraw, ImageFont

GLYPH = "\U000F1105"
SUB = 32


def grid(font_path, size):
    probe = ImageFont.truetype(font_path, 1000)
    left, top, right, bottom = probe.getbbox(GLYPH)
    font = ImageFont.truetype(font_path, round(1000 * size * SUB / max(right - left, bottom - top)))
    left, top, right, bottom = font.getbbox(GLYPH)

    canvas = Image.new("L", (size * SUB, size * SUB), 0)
    ImageDraw.Draw(canvas).text(((size * SUB - (right - left)) / 2 - left, (size * SUB - (bottom - top)) / 2 - top),
                                GLYPH, font=font, fill=255)
    cells = canvas.resize((size, size), Image.BOX)  # mean coverage of each cell
    return ["".join(str(min(9, round(cells.getpixel((x, y)) / 255 * 9))) for x in range(size)) for y in range(size)]


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: snowflake.py FONT SIZE")
    print("\n".join(grid(sys.argv[1], int(sys.argv[2]))))


if __name__ == "__main__":
    main()
