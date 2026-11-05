#!/usr/bin/env python3
# brand.py by poligle
#
# NIHIL brand assets, all drawn with LED dots:
#   mark     the NixOS snowflake in LEDs (theme/art/snowflake-19.txt), as the
#            boot splash draws it
#   logo     the mark plus "NIHIL" in a 5x7 dot-matrix face defined below
#   nilo     Nilo's face for its account (its commits' co-author): the two
#            eyes of home/shell/nilo/Eyes.qml, open, on black
#
#   python3 tools/brand.py [--wallpaper PNG] [--mono-font TTF]
# Writes assets/brand/* and the favicons and images of the site in docs/,
# including a preview of the boot splash made from its real frames.
# Needs Pillow; the social image also uses the wallpaper render and Space Mono.

import argparse
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
INK, VOID, SIGNAL, UNLIT_DARK, UNLIT_LIGHT, DARK_INK = "#F2F2F2", "#000000", "#D71921", "#333333", "#D4D4D4", "#0E0E0E"

FACE = {
    "N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
    "I": ["#", "#", "#", "#", "#", "#", "#"],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
}


def word_columns(text):
    cols = []
    for k, ch in enumerate(text):
        glyph = FACE[ch]
        if k:
            cols.append([False] * 7)
        for x in range(len(glyph[0])):
            cols.append([glyph[y][x] == "#" for y in range(7)])
    return cols


def snowflake(cx, cy, size, unlit=False):
    """(x, y, r, colour_key) circles of the mark, in a size x size box: the
    snowflake's grid, bright cells lit, faint ones dim."""
    path = os.path.join(ROOT, "theme", "art", "snowflake-19.txt")
    rows = [line.strip() for line in open(path) if line.strip()]
    pitch = size / len(rows)
    out = []
    for j, row in enumerate(rows):
        for i, cell in enumerate(row):
            x, y = cx - size / 2 + (i + 0.5) * pitch, cy - size / 2 + (j + 0.5) * pitch
            if int(cell) >= 5:
                out.append((x, y, 0.42 * pitch, "ink"))
            elif int(cell) > 0:
                out.append((x, y, 0.42 * pitch, "dim"))
            elif unlit:
                out.append((x, y, 0.12 * pitch, "unlit"))
    return out


def logo_circles(pitch=10.0, unlit=True):
    """Circles of the full logo and its width/height in units of `pitch`."""
    mark = 9 * pitch
    circles = snowflake(mark / 2, mark / 2, mark)
    x0, y0 = mark + 2 * pitch, pitch
    for i, col in enumerate(word_columns("NIHIL")):
        for j, on in enumerate(col):
            x, y = x0 + (i + 0.5) * pitch, y0 + (j + 0.5) * pitch
            if on:
                circles.append((x, y, 0.36 * pitch, "ink"))
            elif unlit:
                circles.append((x, y, 0.12 * pitch, "unlit"))
    width = x0 + len(word_columns("NIHIL")) * pitch + pitch
    return circles, width, mark


def svg(circles, width, height, colours, background=None, radius=0):
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:g} {height:g}" width="{width:g}" height="{height:g}">']
    if background:
        parts.append(f'<rect width="{width:g}" height="{height:g}" rx="{radius:g}" fill="{background}"/>')
    for key in ("unlit", "dim", "ink", "signal"):
        group = [c for c in circles if c[3] == key]
        if not group:
            continue
        parts.append(f'<g fill="{colours[key]}">')
        parts += [f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r:.2f}"/>' for x, y, r, _ in group]
        parts.append("</g>")
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def raster(circles, width, height, colours, scale, background=None, radius=0, supersample=4):
    s = scale * supersample
    img = Image.new("RGBA", (round(width * s), round(height * s)), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    if background:
        draw.rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius * s, fill=background)
    for key in ("unlit", "dim", "ink", "signal"):
        for x, y, r, k in circles:
            if k == key:
                draw.ellipse(((x - r) * s, (y - r) * s, (x + r) * s, (y + r) * s), fill=colours[key])
    return img.resize((round(width * scale), round(height * scale)), Image.LANCZOS)


def nilo_avatar(size=512):
    """(svg text, png image) of Nilo's face: two upright pills in the
    proportions of the eyes in the launcher (30 x 76, 46 apart), on black,
    small enough for a round crop."""
    width, height, gap = 0.125 * size, 0.316 * size, 0.19 * size
    top = (size - height) / 2
    xs = (size / 2 - gap / 2 - width, size / 2 + gap / 2)
    eyes = "".join(f'<rect x="{x:.1f}" y="{top:.1f}" width="{width:.1f}" height="{height:.1f}" rx="{width / 2:.1f}"/>'
                   for x in xs)
    text = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}">\n'
            f'<rect width="{size}" height="{size}" fill="{VOID}"/>\n<g fill="{INK}">{eyes}</g>\n</svg>\n')
    s = 4
    img = Image.new("RGB", (size * s, size * s), VOID)
    draw = ImageDraw.Draw(img)
    for x in xs:
        draw.rounded_rectangle((x * s, top * s, (x + width) * s, (top + height) * s), radius=width / 2 * s, fill=INK)
    return text, img.resize((size, size), Image.LANCZOS)


def favicon_circles():
    return snowflake(16, 16, 30)


def social(path, wallpaper, mono_font):
    W, H = 1280, 640
    img = Image.new("RGB", (W, H), VOID)
    if wallpaper and os.path.exists(wallpaper):
        wall = Image.open(wallpaper).convert("RGB")
        wall = wall.resize((round(wall.width * H / wall.height), H), Image.LANCZOS)
        crop = wall.crop((wall.width - 700, 0, wall.width, H))
        mask = Image.linear_gradient("L").rotate(90).resize((700, H))  # fades into the black on the left
        img.paste(crop, (W - 700, 0), mask)
    circles, width, height = logo_circles(pitch=14)
    logo = raster(circles, width, height, {"ink": INK, "signal": SIGNAL, "unlit": UNLIT_DARK}, scale=1)
    img.paste(logo, (90, 210), logo)
    draw = ImageDraw.Draw(img)
    if mono_font and os.path.exists(mono_font):
        font = ImageFont.truetype(mono_font, 26)
        small = ImageFont.truetype(mono_font, 19)
        draw.text((92, 380), "E X   N I H I L O", font=font, fill="#A3A3A3")
        draw.text((92, 430), "NixOS  ·  Hyprland  ·  Quickshell", font=small, fill="#7A7A7A")
    img.save(path, optimize=True)


def boot_preview(path):
    """The Plymouth animation as an animated WebP: the intro, then the sweep twice.
    The frames are the theme's own (theme/plymouth.py), shown at 25 fps like on boot."""
    import subprocess
    import sys
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([sys.executable, os.path.join(ROOT, "theme", "plymouth.py"),
                        os.path.join(ROOT, "theme", "art", "snowflake-29.txt"), tmp], check=True)
        frames = sorted((f for f in os.listdir(tmp) if f.startswith("frame-")), key=lambda f: int(f[6:-4]))
        intro = [f for f in frames if int(f[6:-4]) < 36]
        loop = [f for f in frames if int(f[6:-4]) >= 36]
        images = []
        for f in intro + loop + loop:
            frame = Image.open(os.path.join(tmp, f)).convert("RGBA")
            canvas = Image.new("RGBA", frame.size, VOID)
            canvas.alpha_composite(frame)
            images.append(canvas.convert("RGB"))
        images[0].save(path, save_all=True, append_images=images[1:], duration=40, loop=0, lossless=True, method=6)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wallpaper", default="")
    ap.add_argument("--mono-font", default="")
    args = ap.parse_args()

    brand = os.path.join(ROOT, "assets", "brand")
    docs = os.path.join(ROOT, "docs")
    site = os.path.join(docs, "assets")
    for d in (brand, site):
        os.makedirs(d, exist_ok=True)

    dark = {"ink": INK, "dim": "#8A8A8A", "signal": SIGNAL, "unlit": UNLIT_DARK}
    light = {"ink": DARK_INK, "dim": "#7A7A7A", "signal": SIGNAL, "unlit": UNLIT_LIGHT}

    circles, width, height = logo_circles()
    for name, colours in (("nihil-logo-dark", dark), ("nihil-logo-light", light)):
        text = svg(circles, width, height, colours)
        for d in (brand, site):
            open(os.path.join(d, f"{name}.svg"), "w").write(text)

    mark = snowflake(45, 45, 90)
    open(os.path.join(brand, "nihil-mark.svg"), "w").write(svg(mark, 90, 90, dark))

    face, picture = nilo_avatar()
    open(os.path.join(brand, "nilo-avatar.svg"), "w").write(face)
    picture.save(os.path.join(brand, "nilo-avatar.png"), optimize=True)
    open(os.path.join(brand, "nihil-mark-light.svg"), "w").write(svg(mark, 90, 90, light))

    fav = favicon_circles()
    open(os.path.join(docs, "favicon.svg"), "w").write(svg(fav, 32, 32, dark, background=VOID, radius=7))
    icon = raster(fav, 32, 32, dark, scale=8, background=VOID, radius=7)  # 256 px master
    icon.save(os.path.join(docs, "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)])
    apple = raster(fav, 32, 32, dark, scale=180 / 32, background=VOID, radius=0)
    apple.convert("RGB").save(os.path.join(docs, "apple-touch-icon.png"), optimize=True)

    for path in (os.path.join(brand, "social-preview.png"), os.path.join(site, "og.png")):
        social(path, args.wallpaper, args.mono_font)

    boot_preview(os.path.join(site, "boot.webp"))

    print("brand assets written")


if __name__ == "__main__":
    main()
