# SPDX-License-Identifier: GPL-3.0-or-later
"""The ribbon's panel icons, drawn rather than hand-authored.

Five panels, one per LAZPANEL category (``tools/check_registry.py``'s
``CATEGORIES``), and each gets its own icon -- a colour and a glyph
that says something about what the category holds rather than a
generic hexagon repeated five times. Hand-authoring five bitmaps would
be one more thing to keep in step with ``CATEGORIES`` by hand, which is
exactly the kind of copy this tree does not keep: this writes them
instead, so a category renamed or added is a regeneration rather than
someone remembering to draw a sixth icon.

Pure stdlib -- ``zlib`` for the PNG deflate stream and ``struct`` for
the chunk framing -- because nothing else in this tree needs a Pillow
or an image library and one icon generator should not be the reason it
gains one. The glyphs are drawn blocky, at icon size, with no
anti-aliasing: at 32x32 a smoothed edge is a handful of pixels of a
colour that was never in the palette, and code that doesn't need to
blend is code that can't blend wrong.

    python3 tools/gen_ribbon_icons.py           # write the five PNGs
    python3 tools/gen_ribbon_icons.py --check   # is the tree current?

``--check`` is not yet wired into ``check_standards.py`` alongside the
mirror/releases/bundle/catalog/chart checks -- see
``ui/calofin_ribbon/README.md`` for why -- but ``make verify`` runs it.
"""

import argparse
import pathlib
import struct
import sys
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from callib import ROOT  # noqa: E402
from check_registry import CATEGORIES  # noqa: E402

OUT_DIR = ROOT / "ui" / "calofin_ribbon" / "icons"
SIZE = 32

#: One (background, glyph) colour pair per category. Five distinct hues
#: rather than one accent colour repeated, so a row of panels reads as
#: five different things at a glance before anyone reads a caption.
PALETTE = {
    "Layout": ((0x2E, 0x5E, 0x8C), (0xFF, 0xFF, 0xFF)),
    "Points": ((0x3A, 0x8C, 0x4A), (0xFF, 0xFF, 0xFF)),
    "Dimensions": ((0xB0, 0x6A, 0x1E), (0xFF, 0xFF, 0xFF)),
    "Converters": ((0x7A, 0x3E, 0x9C), (0xFF, 0xFF, 0xFF)),
    "Checking": ((0x1E, 0x8C, 0x7A), (0xFF, 0xFF, 0xFF)),
}


# ------------------------------------------------------------- drawing

class Canvas:
    """A SIZE x SIZE grid of RGBA pixels, with just enough primitives
    for blocky icon glyphs: no anti-aliasing, so every pixel is either
    the background or the glyph colour and nothing in between."""

    def __init__(self, size, bg):
        self.size = size
        self.px = [[bg + (255,)] * size for _ in range(size)]

    def set(self, x, y, rgba):
        if 0 <= x < self.size and 0 <= y < self.size:
            self.px[y][x] = rgba

    def rect(self, x0, y0, x1, y1, rgba, fill=True, thickness=1):
        if fill:
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    self.set(x, y, rgba)
            return
        for t in range(thickness):
            for x in range(x0, x1 + 1):
                self.set(x, y0 + t, rgba)
                self.set(x, y1 - t, rgba)
            for y in range(y0, y1 + 1):
                self.set(x0 + t, y, rgba)
                self.set(x1 - t, y, rgba)

    def line(self, x0, y0, x1, y1, rgba, thickness=1):
        """Bresenham, thickened by painting a (thickness x thickness)
        square at every step -- blocky on purpose, see the module
        docstring."""
        dx, dy = abs(x1 - x0), abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        x, y = x0, y0
        half = thickness // 2
        while True:
            for ox in range(-half, thickness - half):
                for oy in range(-half, thickness - half):
                    self.set(x + ox, y + oy, rgba)
            if x == x1 and y == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x += sx
            if e2 < dx:
                err += dx
                y += sy

    def circle(self, cx, cy, r, rgba):
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                if x * x + y * y <= r * r:
                    self.set(cx + x, cy + y, rgba)

    def scanlines(self):
        """Raw PNG scanline bytes: one filter byte (0 = None) per row,
        then RGBA quadruplets."""
        out = bytearray()
        for row in self.px:
            out.append(0)
            for (r, g, b, a) in row:
                out += bytes((r, g, b, a))
        return bytes(out)


# --------------------------------------------------------------- glyphs

def glyph_layout(c, fg):
    """A floor plan: an outer wall and one partition -- Layout is the
    tools that draw the shape of the thing."""
    c.rect(4, 6, 27, 25, fg, fill=False, thickness=2)
    c.line(16, 6, 16, 25, fg, thickness=2)


def glyph_points(c, fg):
    """A scatter of survey points, unevenly placed -- Points is never
    a grid, it is wherever the tape landed."""
    for (x, y) in ((8, 9), (23, 8), (16, 17), (9, 24), (24, 23)):
        c.circle(x, y, 3, fg)


def glyph_dimensions(c, fg):
    """A dimension line, extension lines and arrowheads -- the drafting
    symbol the category is named for."""
    c.line(5, 16, 27, 16, fg, thickness=2)
    c.line(5, 9, 5, 23, fg, thickness=2)
    c.line(27, 9, 27, 23, fg, thickness=2)
    c.line(5, 16, 11, 11, fg, thickness=2)
    c.line(5, 16, 11, 21, fg, thickness=2)
    c.line(27, 16, 21, 11, fg, thickness=2)
    c.line(27, 16, 21, 21, fg, thickness=2)


def glyph_converters(c, fg):
    """Two arrows chasing each other in a loop -- data going from one
    survey format onto the shop's layers, and back."""
    c.line(8, 10, 23, 10, fg, thickness=2)
    c.line(23, 10, 18, 5, fg, thickness=2)
    c.line(23, 10, 18, 15, fg, thickness=2)
    c.line(24, 22, 9, 22, fg, thickness=2)
    c.line(9, 22, 14, 17, fg, thickness=2)
    c.line(9, 22, 14, 27, fg, thickness=2)


def glyph_checking(c, fg):
    """A checkmark."""
    c.line(7, 17, 13, 24, fg, thickness=3)
    c.line(13, 24, 25, 8, fg, thickness=3)


GLYPHS = {
    "Layout": glyph_layout,
    "Points": glyph_points,
    "Dimensions": glyph_dimensions,
    "Converters": glyph_converters,
    "Checking": glyph_checking,
}


# ---------------------------------------------------------------- PNG

def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def png_bytes(category):
    """The category's icon, encoded as a PNG file's bytes."""
    bg, fg = PALETTE[category]
    c = Canvas(SIZE, bg)
    GLYPHS[category](c, fg + (255,))

    ihdr = struct.pack(">IIBBBBB", c.size, c.size, 8, 6, 0, 0, 0)
    idat = zlib.compress(c.scanlines(), 9)
    return (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) +
            _chunk(b"IDAT", idat) + _chunk(b"IEND", b""))


def out_path(category):
    return OUT_DIR / (category.lower() + ".png")


# --------------------------------------------------------------- driver

def check():
    """Problems as a list of strings, empty when every icon is current."""
    problems = []
    for cat in CATEGORIES:
        p = out_path(cat)
        if not p.is_file():
            problems.append(
                "%s: missing - run python3 tools/gen_ribbon_icons.py"
                % p.relative_to(ROOT))
        elif p.read_bytes() != png_bytes(cat):
            problems.append(
                "%s: stale - regenerate with "
                "python3 tools/gen_ribbon_icons.py" % p.relative_to(ROOT))
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="report staleness instead of writing")
    args = ap.parse_args(argv)

    if args.check:
        problems = check()
        for p in problems:
            print(p)
        if problems:
            return 1
        print("gen_ribbon_icons: %d icons current" % len(CATEGORIES))
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    changed = 0
    for cat in CATEGORIES:
        data = png_bytes(cat)
        p = out_path(cat)
        if not p.is_file() or p.read_bytes() != data:
            changed += 1
        p.write_bytes(data)
    print("gen_ribbon_icons: wrote %d icons to %s (%d changed)"
          % (len(CATEGORIES), OUT_DIR.relative_to(ROOT), changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
