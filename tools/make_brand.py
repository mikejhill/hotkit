"""Generate hotkit's font-free README marks, previews, and social preview.

Run ``python tools/make_brand.py`` (requires Pillow), or
``uv run tools/make_brand.py``. The tray generator owns the shared palette.
SVG and PNG outputs use the same geometry; no fonts or source images are read.
"""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass

from make_icon import (
    DARK_BACKGROUND,
    KEY_LAYERS,
    LIGHT_BACKGROUND,
    ROOT,
    SAGE,
    SLATE,
    SOCIAL_BACKGROUND,
    SOCIAL_KEYS,
)
from PIL import Image, ImageDraw

# /// script
# requires-python = ">=3.10"
# dependencies = ["Pillow>=10"]
# ///

WIDTH, HEIGHT = 362, 77
CELL_WIDTH = 46
WORDMARK_LEFT = 87
# Condense 34px stroke-center spans to 24px; the unchanged 8px stroke adds 8px.
INK_X_SCALE = 12 / 17
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

    def paint(self, draw: ImageDraw.ImageDraw, scale: float, offset: Point) -> None:
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


@dataclass(frozen=True, slots=True)
class Glyph:
    """A letter's advance cell and its positioned, round-ended ink strokes."""

    letter: str
    left: float
    right: float
    shapes: tuple[Shape, ...]

    @property
    def advance(self) -> float:
        """Compute the advance from the actual cell boundaries."""
        return self.right - self.left

    @property
    def ink_bounds(self) -> tuple[float, float]:
        """Return horizontal ink bounds including rounded stroke terminals."""
        return (
            min(x - shape.stroke / 2 for shape in self.shapes for x, _ in shape.points),
            max(x + shape.stroke / 2 for shape in self.shapes for x, _ in shape.points),
        )

    @property
    def center_offset(self) -> float:
        """Measure the ink center relative to the advance cell center."""
        return (sum(self.ink_bounds) - self.left - self.right) / 2


class Brand:
    """Four-key tile with a tightly cropped geometric hotkit wordmark."""

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
        # Remove the tray's safety padding: artwork starts at (6, 6), 65px tall.
        unit = 65 / 14
        for (left, top, right, bottom), radius, color in KEY_LAYERS:
            shapes.append(
                cls._box(
                    (
                        6 + (left - 1) * unit,
                        6 + (top - 1) * unit,
                        6 + (right - 1) * unit,
                        6 + (bottom - 1) * unit,
                    ),
                    radius * unit,
                    color,
                )
            )
        shapes.extend(shape for glyph in cls.wordmark(ink) for shape in glyph.shapes)
        return shapes

    @classmethod
    def wordmark(cls, ink: str) -> tuple[Glyph, ...]:
        """Place original stroke drawings in equal cells and verify their metrics."""
        strokes = {
            "h": (
                ((5, 10), (5, 66)),
                (*cls._curve((5, 45), (5, 23), (39, 23), (39, 45)), (39, 66)),
            ),
            "o": (
                (
                    *cls._curve((22, 30), (-2 / 3, 30), (-2 / 3, 67), (22, 67)),
                    *cls._curve((22, 67), (134 / 3, 67), (134 / 3, 30), (22, 30)),
                ),
            ),
            "t": (
                ((18, 18), *cls._curve((18, 55), (18, 67), (25, 69), (35, 64))),
                ((5, 32), (39, 32)),
            ),
            "k": (
                ((5, 10), (5, 66)),
                ((39, 31), (5, 51), (39, 66)),
            ),
            "i": (
                ((5, 33), (22, 33), (22, 66)),
                ((5, 66), (39, 66)),
                ((22, 13), (22, 14)),
            ),
        }
        glyphs = tuple(
            Glyph(
                letter,
                WORDMARK_LEFT + index * CELL_WIDTH,
                WORDMARK_LEFT + (index + 1) * CELL_WIDTH,
                tuple(
                    Shape(
                        tuple(
                            (
                                WORDMARK_LEFT
                                + (index + 0.5) * CELL_WIDTH
                                + (x - 22) * INK_X_SCALE,
                                y,
                            )
                            for x, y in points
                        ),
                        ink,
                        8,
                    )
                    for points in strokes[letter]
                ),
            )
            for index, letter in enumerate("hotkit")
        )
        cls.validate_cells(glyphs)
        return glyphs

    @staticmethod
    def validate_cells(glyphs: tuple[Glyph, ...]) -> None:
        """Reject unequal advances, crowded or off-center ink, and cell gaps."""
        advances = tuple(glyph.advance for glyph in glyphs)
        assert len(set(advances)) == 1, f"Unequal glyph advances: {advances}"
        assert advances[0] > 0, f"Invalid glyph advances: {advances}"
        for previous, current in zip(glyphs, glyphs[1:]):
            assert previous.right == current.left, "Noncontiguous wordmark cells"
        for glyph in glyphs:
            left, right = glyph.ink_bounds
            assert glyph.left <= left < right <= glyph.right, "Ink outside cell"
            assert right - left <= 0.76 * glyph.advance, (
                f"{glyph.letter}: ink width exceeds 76% of advance"
            )
            assert abs(glyph.center_offset) < 1e-9, "Ink not centered in cell"

    @classmethod
    def cell_preview(cls) -> Image.Image:
        """Outline each advance cell over the README lockup at four times size."""
        glyphs = cls.wordmark(SLATE)
        # Include the last sidebearing beyond the tightly cropped production SVG.
        width = math.ceil(max(WIDTH, glyphs[-1].right + 6))
        canvas = Image.new("RGB", (width * 4, HEIGHT * 4), LIGHT_BACKGROUND)
        canvas.paste(
            cls.raster(SLATE, LIGHT_BACKGROUND, size=(WIDTH * 4, HEIGHT * 4), zoom=4)
        )
        draw = ImageDraw.Draw(canvas)
        for glyph in glyphs:
            draw.rectangle(
                (glyph.left * 4, 6 * 4, glyph.right * 4, 71 * 4), outline=SAGE
            )
        return canvas

    @classmethod
    def svg(cls, ink: str) -> str:
        """Return a transparent, accessible SVG with no external dependencies."""
        return "\n".join(
            (
                '<svg xmlns="http://www.w3.org/2000/svg" '
                f'width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" '
                'role="img" aria-labelledby="title desc">',
                '  <title id="title">hotkit</title>',
                '  <desc id="desc">A slate tile with three sage keys and one blue hotkey, '
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
        zoom: float = 1,
        secondary_keys: bool = False,
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
        if secondary_keys:
            # A low-contrast keyboard rhythm anchors the social card's lower band.
            for index in range(13):
                left = 218 + index * 66
                cls._box((left, 510, left + 52, 554), 9, SOCIAL_KEYS).paint(
                    draw, SUPERSAMPLING, (0, 0)
                )
        return canvas.resize(size, Image.Resampling.LANCZOS)

    @classmethod
    def main(cls) -> int:
        """Write both README variants, their previews, and a 1280x640 share card."""
        destination = ROOT / "assets" / "brand"
        previews = ROOT / ".tmp"
        destination.mkdir(parents=True, exist_ok=True)
        previews.mkdir(parents=True, exist_ok=True)
        for name, ink, background in (
            ("light", SLATE, LIGHT_BACKGROUND),
            ("dark", SAGE, DARK_BACKGROUND),
        ):
            (destination / f"logo-{name}.svg").write_text(
                cls.svg(ink), encoding="utf-8", newline="\n"
            )
            cls.raster(ink, background).save(previews / f"v4-brand-{name}.png")
        cls.cell_preview().save(previews / "v4-wordmark-cells.png")
        cls.raster(
            SLATE,
            SOCIAL_BACKGROUND,
            size=(1280, 640),
            zoom=2.5,
            secondary_keys=True,
        ).save(destination / "social-preview.png")
        for glyph in cls.wordmark(SLATE):
            left, right = glyph.ink_bounds
            sys.stdout.write(
                f"{glyph.letter}: advance={glyph.advance:g}px, "
                f"ink width={right - left:g}px, "
                f"center offset={glyph.center_offset:g}px\n"
            )
        sys.stdout.write(
            "wrote assets/brand/ and .tmp/v4-{brand-*,wordmark-cells}.png\n"
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(Brand.main())
