"""Generate E6 README logos and a social card with JetBrains Mono Medium.

Run ``uv run --with pillow --with fonttools tools/make_brand.py``.
The bundled variable font is instanced at wght=500 in memory. SVG wordmarks
contain real glyph paths; Pillow previews use that same static font instance.
"""

from __future__ import annotations

import math
import sys
from io import BytesIO

from make_icon import (
    BOLT,
    BOLT_POINTS,
    DARK_BACKGROUND,
    KEY_LAYERS,
    LIGHT_BACKGROUND,
    ROOT,
    SOCIAL_BACKGROUND,
    SOCIAL_KEYS,
    WORDMARK_DARK,
    WORDMARK_LIGHT,
)
from PIL import Image, ImageDraw, ImageFont

try:
    from fontTools.pens.boundsPen import BoundsPen
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont
except ImportError as error:
    raise SystemExit(
        "fontTools is required. Run: "
        "uv run --with pillow --with fonttools tools/make_brand.py"
    ) from error

# /// script
# requires-python = ">=3.10"
# dependencies = ["Pillow==12.3.0", "fonttools==4.68.0"]
# ///

FONT_PATH = ROOT / "assets" / "brand" / "fonts" / "JetBrainsMono[wght].ttf"
FONT_SIZE = 80
FONT_WEIGHT = 500
SUPERSAMPLING = 4
MARGIN = 4
WORD = "hotkit"


class Wordmark:
    """Extract font metrics and outlined glyphs from one Medium instance."""

    def __init__(self) -> None:
        """Instance the bundled font and retain its paths and raster font bytes."""
        with TTFont(FONT_PATH, recalcTimestamp=False) as source:
            font = instantiateVariableFont(source, {"wght": FONT_WEIGHT})
        try:
            glyphs = font.getGlyphSet()
            cmap = font.getBestCmap()
            scale = FONT_SIZE / font["head"].unitsPerEm
            bounds = BoundsPen(glyphs)
            outline = SVGPathPen(glyphs)
            advance = 0
            for letter in WORD:
                glyph = glyphs[cmap[ord(letter)]]
                transform = (scale, 0, 0, -scale, advance, 0)
                glyph.draw(TransformPen(bounds, transform))
                glyph.draw(TransformPen(outline, transform))
                advance += glyph.width * scale
            if bounds.bounds is None:
                raise ValueError("JetBrains Mono wordmark has no glyph outlines")
            self.left, self.top, right, bottom = (
                float(value) for value in bounds.bounds
            )
            self.width = right - self.left
            self.height = bottom - self.top
            self.path = outline.getCommands()
            buffer = BytesIO()
            font.save(buffer)
            self.font_bytes = buffer.getvalue()
        finally:
            font.close()

    def svg(self, x: float, y: float, ink: str) -> str:
        """Position real glyph curves by their visible top-left bounds."""
        return (
            f'  <path fill="{ink}" '
            f'transform="translate({x - self.left:.6f} {y - self.top:.6f})" '
            f'd="{self.path}"/>'
        )

    def raster(self, scale: float, ink: str) -> Image.Image:
        """Render the same Medium instance and fit it to the SVG ink bounds."""
        font = ImageFont.truetype(BytesIO(self.font_bytes), round(FONT_SIZE * scale))
        left, top, right, bottom = (round(value) for value in font.getbbox(WORD))
        canvas = Image.new("RGBA", (right - left, bottom - top))
        ImageDraw.Draw(canvas).text((-left, -top), WORD, font=font, fill=ink)
        return canvas.crop(canvas.getbbox()).resize(
            (round(self.width * scale), round(self.height * scale)),
            Image.Resampling.LANCZOS,
        )


class Brand:
    """Align the E6 mark to the word's ascenders with a 35% gap."""

    def __init__(self) -> None:
        """Derive a tight viewBox from the actual Medium glyph bounds."""
        self.wordmark = Wordmark()
        self.mark_height = self.wordmark.height
        self.gap = self.mark_height * 0.35
        self.width = math.ceil(
            2 * MARGIN + self.mark_height + self.gap + self.wordmark.width
        )
        self.height = math.ceil(2 * MARGIN + self.mark_height)
        self.x = (self.width - self.mark_height - self.gap - self.wordmark.width) / 2
        self.y = (self.height - self.mark_height) / 2
        self.unit = self.mark_height / 14

    def svg(self, ink: str) -> str:
        """Serialize the shared keycap geometry and font-derived wordmark paths."""
        lines = [
            (
                '<svg xmlns="http://www.w3.org/2000/svg" '
                f'width="{self.width}" height="{self.height}" '
                f'viewBox="0 0 {self.width} {self.height}" role="img" '
                'aria-labelledby="title">'
            ),
            '  <title id="title">hotkit</title>',
        ]
        for (left, top, right, bottom), radius, color in KEY_LAYERS:
            lines.append(
                f'  <rect x="{self.x + (left - 1) * self.unit:.6f}" '
                f'y="{self.y + (top - 1) * self.unit:.6f}" '
                f'width="{(right - left) * self.unit:.6f}" '
                f'height="{(bottom - top) * self.unit:.6f}" '
                f'rx="{radius * self.unit:.6f}" fill="{color}"/>'
            )
        vertices = " L ".join(
            f"{self.x + (x - 1) * self.unit:.6f},{self.y + (y - 1) * self.unit:.6f}"
            for x, y in BOLT_POINTS
        )
        lines.append(f'  <path d="M {vertices} Z" fill="{BOLT}"/>')
        lines.append(
            self.wordmark.svg(self.x + self.mark_height + self.gap, self.y, ink)
        )
        return "\n".join([*lines, "</svg>", ""])

    def raster(
        self,
        ink: str,
        background: str,
        *,
        size: tuple[int, int] | None = None,
        zoom: float = 1,
        secondary_keys: bool = False,
    ) -> Image.Image:
        """Render an equivalent Pillow lockup from shared geometry and font data."""
        size = size or (self.width, self.height)
        scale = SUPERSAMPLING * zoom
        canvas = Image.new(
            "RGB", (size[0] * SUPERSAMPLING, size[1] * SUPERSAMPLING), background
        )
        draw = ImageDraw.Draw(canvas)
        x = ((size[0] - self.width * zoom) / 2 + self.x * zoom) * SUPERSAMPLING
        y = ((size[1] - self.height * zoom) / 2 + self.y * zoom) * SUPERSAMPLING
        unit = self.unit * scale
        for (left, top, right, bottom), radius, color in KEY_LAYERS:
            bounds = (
                round(x + (left - 1) * unit),
                round(y + (top - 1) * unit),
                round(x + (right - 1) * unit) - 1,
                round(y + (bottom - 1) * unit) - 1,
            )
            draw.rounded_rectangle(bounds, radius=radius * unit, fill=color)
        draw.polygon(
            [
                (round(x + (px - 1) * unit), round(y + (py - 1) * unit))
                for px, py in BOLT_POINTS
            ],
            fill=BOLT,
        )
        word = self.wordmark.raster(scale, ink)
        canvas.paste(
            word, (round(x + (self.mark_height + self.gap) * scale), round(y)), word
        )
        if secondary_keys:
            for index in range(13):
                left = 218 + index * 66
                draw.rounded_rectangle(
                    tuple(
                        value * SUPERSAMPLING for value in (left, 510, left + 52, 554)
                    ),
                    radius=9 * SUPERSAMPLING,
                    fill=SOCIAL_KEYS,
                )
        return canvas.resize(size, Image.Resampling.LANCZOS)

    @classmethod
    def main(cls) -> int:
        """Write README SVGs, light/dark previews, and a 1280x640 social card."""
        brand = cls()
        destination = ROOT / "assets" / "brand"
        previews = ROOT / ".tmp"
        destination.mkdir(parents=True, exist_ok=True)
        previews.mkdir(parents=True, exist_ok=True)
        for name, ink, background in (
            ("light", WORDMARK_LIGHT, LIGHT_BACKGROUND),
            ("dark", WORDMARK_DARK, DARK_BACKGROUND),
        ):
            (destination / f"logo-{name}.svg").write_text(
                brand.svg(ink), encoding="utf-8", newline="\n"
            )
            brand.raster(ink, background).save(previews / f"v9-brand-{name}.png")
        brand.raster(
            WORDMARK_LIGHT,
            SOCIAL_BACKGROUND,
            size=(1280, 640),
            zoom=2.5,
            secondary_keys=True,
        ).save(destination / "social-preview.png")
        sys.stdout.write(
            f"wrote assets/brand/ and .tmp/v9-brand-*.png\n"
            f"viewBox: 0 0 {brand.width} {brand.height}; "
            f"mark: {brand.mark_height:g}px; gap: {brand.gap:g}px; "
            "JetBrains Mono Medium (wght=500), outlined with fontTools\n"
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(Brand.main())
