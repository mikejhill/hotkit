"""Renders assets/hotkit.ico, the default tray icon.

The icon is drawn from simple shapes (no fonts or source images) so it can be
regenerated anywhere:  python tools/make_icon.py
Each size is drawn at 16x and downsampled, with the small sizes snapped to the
pixel grid so the glyph stays sharp in the notification area.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "hotkit.ico"
SIZES = [16, 20, 24, 32, 40, 48, 64, 256]
SS = 16  # supersampling factor

TOP = (255, 138, 36)      # tile gradient, top
BOTTOM = (226, 38, 84)    # tile gradient, bottom
CAP = (255, 255, 255)
CAP_EDGE = (255, 214, 196)
GLYPH = (226, 52, 72)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def render(size: int) -> Image.Image:
    s = size * SS
    u = s / 16.0  # one "design pixel" at 16px
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Tile: rounded square with a vertical gradient.
    grad = Image.new("RGBA", (s, s))
    gd = ImageDraw.Draw(grad)
    for y in range(s):
        gd.line([(0, y), (s, y)], fill=lerp(TOP, BOTTOM, y / (s - 1)) + (255,))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=3.5 * u, fill=255)
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)
    # Keycap: lip (depth) then face.
    d.rounded_rectangle([2.5 * u, 3 * u, 13.5 * u, 14 * u], radius=2.2 * u, fill=CAP_EDGE + (255,))
    d.rounded_rectangle([2.5 * u, 2 * u, 13.5 * u, 12.5 * u], radius=2.2 * u, fill=CAP + (255,))

    # "H" glyph on the keycap, built from rectangles on the 16px grid.
    stem = 2 * u
    x0, x1 = 5 * u, 11 * u
    y0, y1 = 4.25 * u, 10.25 * u
    d.rectangle([x0, y0, x0 + stem - 1, y1 - 1], fill=GLYPH + (255,))
    d.rectangle([x1 - stem, y0, x1 - 1, y1 - 1], fill=GLYPH + (255,))
    d.rectangle([x0, 6.5 * u, x1 - 1, 8 * u - 1], fill=GLYPH + (255,))

    return img.resize((size, size), Image.LANCZOS if size >= 32 else Image.BOX)


def main() -> int:
    images = [render(n) for n in SIZES]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    images[-1].save(OUT, format="ICO", sizes=[(n, n) for n in SIZES], append_images=images[:-1])
    if "--preview" in sys.argv:
        scaled = [im.resize((im.width * max(1, 128 // im.width),) * 2, Image.NEAREST) for im in images]
        sheet = Image.new("RGBA", (sum(i.width + 16 for i in scaled) + 16, max(i.height for i in scaled) + 32), (40, 40, 40, 255))
        x = 16
        for im in scaled:
            sheet.alpha_composite(im, (x, 16))
            x += im.width + 16
        sheet.save(sys.argv[sys.argv.index("--preview") + 1])
    print(f"wrote {OUT.relative_to(ROOT)} ({', '.join(map(str, SIZES))})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
