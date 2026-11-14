"""Generate hotkit's quiet, staggered two-key tray icon using Pillow shapes.

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
# dependencies = ["Pillow>=10"]
# ///

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "hotkit.ico"
SIZES = (16, 20, 24, 32, 40, 48, 64, 256)
SLATE = "#52616A"
SAGE = "#B5C5BC"
BLUE = "#A6BAC5"
LIP = "#82969A"
BACKGROUNDS = ("#F3F3F3", "#202020")
PIXEL_SIZE_LIMIT = 32
DESIGN_SIZE = 16


class TrayIcon:
    """Two offset keys representing a chord of small, composable actions."""

    @classmethod
    def render(cls, size: int) -> Image.Image:
        """Draw a frame with snapped edges and a transparent surrounding canvas."""
        if size not in SIZES:
            raise ValueError(f"Unsupported icon size: {size}; expected one of {SIZES}")
        scale = 1 if size <= PIXEL_SIZE_LIMIT else 4
        canvas = Image.new("RGBA", (size * scale, size * scale))
        draw = ImageDraw.Draw(canvas)
        cls._key(draw, size, scale, (1, 1, 11, 7), SAGE)
        cls._key(draw, size, scale, (5, 9, 15, 15), BLUE)
        if scale == 1:
            return canvas
        return canvas.resize((size, size), Image.Resampling.LANCZOS)

    @staticmethod
    def _key(
        draw: ImageDraw.ImageDraw,
        size: int,
        scale: int,
        bounds: tuple[int, int, int, int],
        face: str,
    ) -> None:
        """Draw a flat key face, a shallow lower lip, and a contrasting outline."""
        # Snap before supersampling; bounds are exclusive on the right/bottom.
        left, top, right, bottom = (
            round(value * size / DESIGN_SIZE) * scale for value in bounds
        )
        edge = max(1, size // DESIGN_SIZE) * scale
        corner = 1 if size <= PIXEL_SIZE_LIMIT else 1.5
        radius = max(1, round(size * corner / DESIGN_SIZE)) * scale
        inner_radius = max(0, radius - edge)
        draw.rounded_rectangle(
            (left, top, right - 1, bottom - 1), radius=radius, fill=SLATE
        )
        draw.rounded_rectangle(
            (left + edge, top + edge, right - edge - 1, bottom - edge - 1),
            radius=inner_radius,
            fill=LIP,
        )
        draw.rounded_rectangle(
            (left + edge, top + edge, right - edge - 1, bottom - 2 * edge - 1),
            radius=inner_radius,
            fill=face,
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
        return 0


if __name__ == "__main__":
    raise SystemExit(TrayIcon.main())
