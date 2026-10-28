#!/usr/bin/env python3
# snowflake.py by poligle
#
# Samples the NixOS snowflake into a square grid of LED intensities, the
# source of the fastfetch logo and the boot splash (theme/art/*.txt). Each
# cell holds how much of it the logo covers, from 0 (empty) to 9 (full).
# The shape is U+F1105 ("nix"), present in every Nerd Font.
#
#   python3 tools/snowflake.py FONT SIZE > theme/art/snowflake-SIZE.txt
#   FONT: e.g. JetBrainsMonoNerdFont-Regular.ttf from nerd-fonts.jetbrains-mono
# Needs Pillow.

import sys

from PIL import Image, ImageDraw, ImageFont

GLYPH = "\U000F1105"
SUB = 32  # pixels per cell when measuring coverage


def grid(font_path, size):
    # Scale the glyph so its longer side fills the grid, then centre it.
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
