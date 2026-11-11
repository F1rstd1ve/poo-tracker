#!/usr/bin/env python3
"""Generate the launcher icon, map markers and pause menu icons for Gassi-Depot.

Usage: python3 scripts/make_icons.py
Writes PNGs into resources/drawables/. Shapes are drawn 8x oversized and
downsampled for smooth edges.
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "resources" / "drawables"
SS = 8  # supersampling factor

ORANGE = (255, 140, 0, 255)
GREEN = (46, 160, 67, 255)
TEAL = (0, 140, 200, 255)
DARK = (35, 35, 35, 255)
WHITE = (255, 255, 255, 255)


def canvas(size):
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img, size, name):
    img.resize((size, size), Image.LANCZOS).save(OUT / name)


def s(v):
    return int(round(v * SS))


def bag(d, cx, cy, w, h, color):
    """Knotted poop bag: rounded body plus two ears at the top."""
    body_top = cy - h * 0.15
    d.rounded_rectangle(
        [s(cx - w / 2), s(body_top), s(cx + w / 2), s(cy + h / 2)],
        radius=s(w * 0.3),
        fill=color,
    )
    neck_w = w * 0.28
    d.polygon(
        [
            (s(cx - w * 0.38), s(body_top + h * 0.05)),
            (s(cx - neck_w / 2), s(cy - h * 0.28)),
            (s(cx + neck_w / 2), s(cy - h * 0.28)),
            (s(cx + w * 0.38), s(body_top + h * 0.05)),
        ],
        fill=color,
    )
    ear = w * 0.22
    d.ellipse([s(cx - ear * 1.6), s(cy - h / 2), s(cx - ear * 0.1), s(cy - h * 0.22)], fill=color)
    d.ellipse([s(cx + ear * 0.1), s(cy - h / 2), s(cx + ear * 1.6), s(cy - h * 0.22)], fill=color)


def bin_shape(d, cx, cy, w, h, color):
    """Waste bin: lid plus slightly tapered body."""
    lid_h = h * 0.14
    d.rounded_rectangle(
        [s(cx - w / 2), s(cy - h / 2), s(cx + w / 2), s(cy - h / 2 + lid_h)],
        radius=s(lid_h / 2),
        fill=color,
    )
    top = cy - h / 2 + lid_h * 1.4
    d.polygon(
        [
            (s(cx - w * 0.42), s(top)),
            (s(cx + w * 0.42), s(top)),
            (s(cx + w * 0.34), s(cy + h / 2)),
            (s(cx - w * 0.34), s(cy + h / 2)),
        ],
        fill=color,
    )


def round_marker(size, fill, draw_symbol, name):
    img, d = canvas(size)
    d.ellipse([s(0.5), s(0.5), s(size - 0.5), s(size - 0.5)], fill=WHITE)
    d.ellipse([s(2), s(2), s(size - 2), s(size - 2)], fill=fill)
    draw_symbol(d, size)
    finish(img, size, name)


def menu_icons(size=32):
    """White pause menu icons like the native stop screen: play, save, discard."""
    n = size
    img, d = canvas(n)
    d.polygon([(s(n * 0.28), s(n * 0.18)), (s(n * 0.28), s(n * 0.82)), (s(n * 0.82), s(n * 0.5))], fill=WHITE)
    finish(img, n, "icon_resume.png")

    img, d = canvas(n)
    w = n * 0.09
    d.rectangle([s(n / 2 - w), s(n * 0.12), s(n / 2 + w), s(n * 0.55)], fill=WHITE)
    d.polygon([(s(n * 0.24), s(n * 0.45)), (s(n * 0.76), s(n * 0.45)), (s(n / 2), s(n * 0.72))], fill=WHITE)
    d.rectangle([s(n * 0.18), s(n * 0.8), s(n * 0.82), s(n * 0.88)], fill=WHITE)
    finish(img, n, "icon_save.png")

    img, d = canvas(n)
    d.rounded_rectangle([s(n * 0.18), s(n * 0.2), s(n * 0.82), s(n * 0.27)], radius=s(1), fill=WHITE)
    d.rectangle([s(n * 0.4), s(n * 0.12), s(n * 0.6), s(n * 0.2)], fill=WHITE)
    d.polygon([(s(n * 0.25), s(n * 0.32)), (s(n * 0.75), s(n * 0.32)), (s(n * 0.7), s(n * 0.88)), (s(n * 0.3), s(n * 0.88))],
              fill=WHITE)
    for x in (0.41, 0.5, 0.59):
        d.rectangle([s(n * x - 0.8), s(n * 0.42), s(n * x + 0.8), s(n * 0.78)], fill=(0, 0, 0, 0))
    finish(img, n, "icon_discard.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    # Launcher icon (60x60 on the Epix Pro): green disc, white bag, small orange depot dot.
    size = 60
    img, d = canvas(size)
    d.ellipse([s(1), s(1), s(size - 1), s(size - 1)], fill=GREEN)
    bag(d, 30, 32.5, 24, 29, WHITE)
    d.ellipse([s(39.5), s(8.5), s(51.5), s(20.5)], fill=ORANGE, outline=WHITE, width=s(2))
    finish(img, size, "launcher_icon.png")

    round_marker(28, ORANGE, lambda d, n: bag(d, n / 2, n / 2 + 0.5, n * 0.42, n * 0.52, DARK), "marker_depot.png")
    round_marker(24, GREEN, lambda d, n: bin_shape(d, n / 2, n / 2, n * 0.42, n * 0.5, WHITE), "marker_bin.png")

    def dog_bin(d, n):
        bin_shape(d, n / 2, n / 2, n * 0.42, n * 0.5, WHITE)
        r = n * 0.07
        d.ellipse([s(n / 2 - r), s(n / 2 + 1 - r), s(n / 2 + r), s(n / 2 + 1 + r)], fill=TEAL)

    round_marker(24, TEAL, dog_bin, "marker_dogbin.png")
    menu_icons()
    print("Icons written to", OUT)


if __name__ == "__main__":
    main()
