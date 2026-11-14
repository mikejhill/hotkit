"""Generate hotkit's quiet four-key hotkey tile using Pillow shapes.

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
BACKGROUNDS = ("#F3F3F3", "#202020")
LIGHT_BACKGROUND = "#FFFFFF"
DARK_BACKGROUND = "#0D1117"
SOCIAL_BACKGROUND = "#E8EEEB"
SOCIAL_KEYS = "#DCE5DF"
PIXEL_SIZE_LIMIT = 32
DESIGN_SIZE = 16
CORNER_RADIUS = 1
# Exclusive bounds, radius, and fill; branding uses this same centered grid.
KEY_LAYERS = (
    ((1, 1, 15, 15), CORNER_RADIUS, SLATE),
    ((2.5, 2.5, 7.5, 7.5), CORNER_RADIUS, SAGE),
    ((8.5, 2.5, 13.5, 7.5), CORNER_RADIUS, SAGE),
    ((2.5, 8.5, 7.5, 13.5), CORNER_RADIUS, SAGE),
    ((8.5, 8.5, 13.5, 13.5), CORNER_RADIUS, BLUE),
)


class TrayIcon:
    """Four composable keys in one tile, with exactly one highlighted hotkey."""

    @classmethod
    def render(cls, size: int) -> Image.Image:
        """Draw a frame with snapped edges and a transparent surrounding canvas."""
        if size not in SIZES:
            raise ValueError(f"Unsupported icon size: {size}; expected one of {SIZES}")
        scale = 1 if size <= PIXEL_SIZE_LIMIT else 4
        canvas = Image.new("RGBA", (size * scale, size * scale))
        draw = ImageDraw.Draw(canvas)
        for bounds, radius, color in KEY_LAYERS:
            cls._layer(draw, size, scale, bounds, radius, color)
        if scale == 1:
            return canvas
        # BOX preserves the snapped silhouette bounds without filter halos.
        return canvas.resize((size, size), Image.Resampling.BOX)

    @staticmethod
    def _layer(
        draw: ImageDraw.ImageDraw,
        size: int,
        scale: int,
        bounds: tuple[float, float, float, float],
        radius: int,
        color: str,
    ) -> None:
        """Draw a snapped rounded rectangle from the shared 16-unit geometry."""
        # Snap before supersampling; bounds are exclusive on the right/bottom.
        left, top, right, bottom = (
            round(value * size / DESIGN_SIZE) * scale for value in bounds
        )
        if size == 16:
            # Hand-hinted 5x5 keys: [2,7) and [8,13), separated by one pixel.
            # The spare lower/right pixel gives the case a shallow visual depth.
            left, top, right, bottom = (int(value) for value in bounds)
        if bounds == KEY_LAYERS[0][0]:
            # Round outer padding down symmetrically: 24px must not shrink to 20px.
            padding = (size // DESIGN_SIZE) * scale
            left = top = padding
            right = bottom = size * scale - padding
        snapped_radius = max(1, round(size * radius / DESIGN_SIZE)) * scale
        draw.rounded_rectangle(
            (left, top, right - 1, bottom - 1), radius=snapped_radius, fill=color
        )
        # Pillow 12 can omit a one-pixel center strip; fill only the flat interior.
        draw.rectangle(
            (left + snapped_radius, top, right - 1 - snapped_radius, bottom - 1),
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
        return 0


if __name__ == "__main__":
    raise SystemExit(TrayIcon.main())
