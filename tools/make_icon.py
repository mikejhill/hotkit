"""Generate hotkit's E6 steel-blue keycap and soft-amber bolt using Pillow shapes.

Run ``python tools/make_icon.py [--preview .tmp/icon-preview.png]``.
Each ICO frame is drawn independently: native pixel geometry through 32px,
supersampled curves above 32px. The preview shows every frame enlarged with
nearest-neighbour sampling and at actual size on light and dark taskbars.
No fonts, source images, or gradients are used.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw
from PIL.PngImagePlugin import PngInfo

# /// script
# requires-python = ">=3.10"
# dependencies = ["Pillow==12.3.0"]
# ///

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "hotkit.ico"
SIZES = (16, 20, 24, 32, 40, 48, 64, 256)
FACE = "#506F8D"
RIM = "#30475E"
BOLT = "#E3C17C"
WORDMARK_LIGHT = RIM
WORDMARK_DARK = "#D4DEEA"
BACKGROUNDS = ("#F3F3F3", "#202020")
LIGHT_BACKGROUND = "#FFFFFF"
DARK_BACKGROUND = "#0D1117"
SOCIAL_BACKGROUND = "#E8EDF2"
SOCIAL_KEYS = "#DCE3EB"
PIXEL_SIZE_LIMIT = 32
DESIGN_SIZE = 16
RIM_WIDTH = 1
INNER_RADIUS = 2
OUTER_RADIUS = 3
assert OUTER_RADIUS == INNER_RADIUS + RIM_WIDTH, "Keycap radii must be concentric"

# Exclusive bounds, radii, and bolt vertices from concept E6's 16-unit grid.
KEY_LAYERS = (
    ((1, 1, 15, 15), OUTER_RADIUS, RIM),
    ((2, 2, 14, 14), INNER_RADIUS, FACE),
)
BOLT_POINTS = ((8, 3), (11, 3), (9, 7), (12, 7), (6, 13), (7, 9), (4, 9))


class TrayIcon:
    """One concentric keycap with an opaque lightning bolt."""

    @classmethod
    def render(cls, size: int) -> Image.Image:
        """Draw a frame with snapped edges and a transparent surrounding canvas."""
        if size not in SIZES:
            raise ValueError(f"Unsupported icon size: {size}; expected one of {SIZES}")
        scale = 1 if size <= PIXEL_SIZE_LIMIT else 4
        canvas = Image.new("RGBA", (size * scale, size * scale))
        draw = ImageDraw.Draw(canvas)
        units = size * scale / DESIGN_SIZE
        for bounds, radius, color in KEY_LAYERS:
            cls._layer(draw, units, bounds, radius, color)
        draw.polygon(
            [(round(x * units), round(y * units)) for x, y in BOLT_POINTS],
            fill=BOLT,
        )
        if scale == 1:
            return canvas
        # BOX preserves the snapped silhouette bounds without filter halos.
        return canvas.resize((size, size), Image.Resampling.BOX)

    @staticmethod
    def _layer(
        draw: ImageDraw.ImageDraw,
        units: float,
        bounds: tuple[float, float, float, float],
        radius: float,
        color: str,
    ) -> None:
        """Match the concept's snapped bounds and concentric corner radii."""
        left, top, right, bottom = (round(value * units) for value in bounds)
        corners = radius * units
        draw.rounded_rectangle(
            (left, top, right - 1, bottom - 1), radius=corners, fill=color
        )
        # Pillow 12 can omit a one-pixel center strip; fill only the flat interior.
        draw.rectangle(
            (left + corners, top, right - 1 - corners, bottom - 1),
            fill=color,
        )

    @staticmethod
    def preview(images: list[Image.Image], destination: Path) -> None:
        """Show sizes left to right, enlarged then actual, on each taskbar color.

        Each background has two rows in SIZES order. Integer zoom factors are
        8, 6, 5, 4, 3, 2, 2, and 2, respectively; the 256px frame is also enlarged.
        PNG metadata records this legend without introducing fonts.
        """
        zooms = tuple(max(2, 128 // size) for size in SIZES)
        enlarged = [
            frame.resize((frame.width * zoom,) * 2, Image.Resampling.NEAREST)
            for frame, zoom in zip(images, zooms, strict=True)
        ]
        padding = 20
        widths = [frame.width + 2 * padding for frame in enlarged]
        enlarged_height = max(frame.height for frame in enlarged)
        actual_height = max(frame.height for frame in images)
        strip_height = enlarged_height + actual_height + 3 * padding
        sheet = Image.new("RGBA", (sum(widths), 2 * strip_height))
        draw = ImageDraw.Draw(sheet)
        for row, background in enumerate(BACKGROUNDS):
            y = row * strip_height
            draw.rectangle(
                (0, y, sheet.width - 1, y + strip_height - 1), fill=background
            )
            x = 0
            for frame, big, width in zip(images, enlarged, widths, strict=True):
                sheet.alpha_composite(
                    big,
                    (x + padding, y + padding + (enlarged_height - big.height) // 2),
                )
                sheet.alpha_composite(
                    frame,
                    (
                        x + (width - frame.width) // 2,
                        y + enlarged_height + 2 * padding,
                    ),
                )
                x += width
        legend = PngInfo()
        legend.add_text("Sizes", ", ".join(map(str, SIZES)))
        legend.add_text("Zooms", ", ".join(f"{zoom}x" for zoom in zooms))
        legend.add_text(
            "Layout", "Light then dark strip; each has enlarged then actual-size rows."
        )
        destination.parent.mkdir(parents=True, exist_ok=True)
        sheet.convert("RGB").save(destination, pnginfo=legend)

    @classmethod
    def main(cls) -> int:
        """Write all eight independent ICO frames and an optional PNG preview."""
        parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
        parser.add_argument("--preview", type=Path, metavar="PNG", help="preview path")
        args = parser.parse_args()
        preview = Path(args.preview) if args.preview is not None else None
        images = [cls.render(size) for size in SIZES]
        OUT.parent.mkdir(parents=True, exist_ok=True)
        images[-1].save(
            OUT,
            format="ICO",
            sizes=[(size, size) for size in SIZES],
            append_images=images[:-1],
        )
        if preview is not None:
            cls.preview(images, preview)
        sys.stdout.write(
            f"wrote {OUT.relative_to(ROOT)} ({', '.join(map(str, SIZES))})\n"
        )
        sys.stdout.write(
            f"radii (grid units): outer {OUTER_RADIUS} = "
            f"inner {INNER_RADIUS} + rim {RIM_WIDTH}\n"
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(TrayIcon.main())
