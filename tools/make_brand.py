"""Generate hotkit's font-free README marks, previews, and social preview.

Run ``python tools/make_brand.py`` (requires Pillow), or
``uv run tools/make_brand.py``. The tray generator owns the shared palette.
SVG and PNG outputs use the same geometry; no fonts or source images are read.
"""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass

from make_icon import BLUE, LIP, ROOT, SAGE, SLATE
from PIL import Image, ImageDraw

# /// script
# requires-python = ">=3.10"
# dependencies = ["Pillow>=10"]
# ///

WIDTH, HEIGHT = 420, 128
SAMPLE_STEPS = 32
SUPERSAMPLING = 4
Point = tuple[float, float]


@dataclass(frozen=True, slots=True)
class Shape:
    """A filled outline or round-ended stroke shared by SVG and Pillow."""

    points: tuple[Point, ...]
    color: str
    stroke: float = 0

    def svg(self) -> str:
        """Serialize geometry as a self-contained SVG path."""
        points = " L ".join(f"{x:.3f},{y:.3f}" for x, y in self.points)
        if self.stroke:
            return (
                f'  <path d="M {points}" fill="none" stroke="{self.color}" '
                f'stroke-width="{self.stroke}" stroke-linecap="round" '
                'stroke-linejoin="round"/>'
            )
        return f'  <path d="M {points} Z" fill="{self.color}"/>'

    def paint(self, draw: ImageDraw.ImageDraw, scale: int, offset: Point) -> None:
        """Draw the same path at preview resolution with rounded stroke ends."""
        points = [
            ((x + offset[0]) * scale, (y + offset[1]) * scale) for x, y in self.points
        ]
        if not self.stroke:
            draw.polygon(points, fill=self.color)
            return
        draw.line(
            points, fill=self.color, width=round(self.stroke * scale), joint="curve"
        )
        radius = self.stroke * scale / 2
        for x, y in points:
            draw.ellipse(
                (x - radius, y - radius, x + radius, y + radius), fill=self.color
            )


class Brand:
    """Quiet two-key mark with a geometric, lowercase hotkit wordmark."""

    @staticmethod
    def _curve(a: Point, b: Point, c: Point, d: Point) -> tuple[Point, ...]:
        """Sample a cubic curve once for both vector and raster output."""
        return tuple(
            (
                (1 - t) ** 3 * a[0]
                + 3 * (1 - t) ** 2 * t * b[0]
                + 3 * (1 - t) * t**2 * c[0]
                + t**3 * d[0],
                (1 - t) ** 3 * a[1]
                + 3 * (1 - t) ** 2 * t * b[1]
                + 3 * (1 - t) * t**2 * c[1]
                + t**3 * d[1],
            )
            for t in (step / SAMPLE_STEPS for step in range(SAMPLE_STEPS + 1))
        )

    @staticmethod
    def _box(
        bounds: tuple[float, float, float, float], radius: float, color: str
    ) -> Shape:
        """Build a rounded key outline from quarter-circle samples."""
        left, top, right, bottom = bounds
        corners = (
            (right - radius, top + radius, -90),
            (right - radius, bottom - radius, 0),
            (left + radius, bottom - radius, 90),
            (left + radius, top + radius, 180),
        )
        return Shape(
            tuple(
                (
                    x
                    + radius * math.cos(math.radians(start + step * 90 / SAMPLE_STEPS)),
                    y
                    + radius * math.sin(math.radians(start + step * 90 / SAMPLE_STEPS)),
                )
                for x, y, start in corners
                for step in range(SAMPLE_STEPS + 1)
            ),
            color,
        )

    @classmethod
    def shapes(cls, ink: str) -> list[Shape]:
        """Compose the tray motif and six hand-drawn letters without a font."""
        shapes = []
        # Match the tray's 16-unit design: 10-by-6 keys, staggered by 4 and 8.
        for x, y, face in ((6, 22, SAGE), (30, 70, BLUE)):
            shapes.extend(
                (
                    cls._box((x, y, x + 60, y + 36), 9, SLATE),
                    cls._box((x + 6, y + 6, x + 54, y + 30), 3, LIP),
                    cls._box((x + 6, y + 6, x + 54, y + 24), 3, face),
                )
            )
        # h, o, t, k, i, t: open counters and softly rounded terminals.
        strokes = [
            ((132, 35), (132, 91)),
            (*cls._curve((132, 70), (132, 48), (166, 48), (166, 70)), (166, 91)),
            (
                *cls._curve((199, 55), (174, 55), (174, 92), (199, 92)),
                *cls._curve((199, 92), (224, 92), (224, 55), (199, 55)),
            ),
            ((282, 35), (282, 91)),
            ((309, 56), (282, 76), (311, 91)),
            ((332, 58), (332, 91)),
            ((332, 38), (332, 39)),
        ]
        for x in (242, 365):
            strokes.extend(
                (
                    (
                        (x, 43),
                        *cls._curve((x, 80), (x, 92), (x + 7, 94), (x + 17, 89)),
                    ),
                    ((x - 10, 57), (x + 13, 57)),
                )
            )
        shapes.extend(Shape(points, ink, 7) for points in strokes)
        return shapes

    @classmethod
    def svg(cls, ink: str) -> str:
        """Return a transparent, accessible SVG with no external dependencies."""
        return "\n".join(
            (
                '<svg xmlns="http://www.w3.org/2000/svg" '
                f'width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" '
                'role="img" aria-labelledby="title desc">',
                '  <title id="title">hotkit</title>',
                '  <desc id="desc">Two staggered blank keys in sage and dusty blue, '
                "beside a lowercase hotkit wordmark.</desc>",
                *(shape.svg() for shape in cls.shapes(ink)),
                "</svg>\n",
            )
        )

    @classmethod
    def raster(
        cls,
        ink: str,
        background: str,
        *,
        size: tuple[int, int] = (WIDTH, HEIGHT),
        zoom: int = 1,
    ) -> Image.Image:
        """Center the mark on a background using the SVG's exact geometry."""
        scale = SUPERSAMPLING * zoom
        canvas = Image.new(
            "RGB", (size[0] * SUPERSAMPLING, size[1] * SUPERSAMPLING), background
        )
        draw = ImageDraw.Draw(canvas)
        offset = ((size[0] / zoom - WIDTH) / 2, (size[1] / zoom - HEIGHT) / 2)
        for shape in cls.shapes(ink):
            shape.paint(draw, scale, offset)
        return canvas.resize(size, Image.Resampling.LANCZOS)

    @classmethod
    def main(cls) -> int:
        """Write both README variants, their previews, and a 1280x640 share card."""
        destination = ROOT / "assets" / "brand"
        previews = ROOT / ".tmp"
        destination.mkdir(parents=True, exist_ok=True)
        previews.mkdir(parents=True, exist_ok=True)
        for name, ink, background in (
            ("light", SLATE, "#FFFFFF"),
            ("dark", SAGE, "#0D1117"),
        ):
            (destination / f"logo-{name}.svg").write_text(
                cls.svg(ink), encoding="utf-8", newline="\n"
            )
            cls.raster(ink, background).save(previews / f"brand-preview-{name}.png")
        cls.raster(SLATE, "#FFFFFF", size=(1280, 640), zoom=2).save(
            destination / "social-preview.png"
        )
        sys.stdout.write(
            "wrote assets/brand/ and .tmp/brand-preview-{light,dark}.png\n"
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(Brand.main())
