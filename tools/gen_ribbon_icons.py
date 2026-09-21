# SPDX-License-Identifier: GPL-3.0-or-later
"""The ribbon's icons, drawn rather than hand-authored.

Two kinds, and the difference is what the ribbon is for:

* **one per category** (``tools/check_registry.py``'s ``CATEGORIES``) --
  the picture on a panel header, so the row of panels reads as five
  different things before anyone reads a caption;
* **one per FEATURED routine** (``tools/gen_ui_data.py``'s ``FEATURED``)
  -- the large buttons.  A ribbon is only faster than a list where a
  drafter can reach a tool by SHAPE without reading, and that is a thing
  you learn about tools you run often.  Drawing a glyph for all 67
  buttons would spend the distinction it is made of; the rest are text
  buttons, which is what most of AutoCAD's own ribbon is.

**Two sizes, because the ribbon asks for two.**  ``LargeImage`` is the
32x32 on a large button's face; ``Image`` is the 16x16 the same command
wears when the panel is squeezed into its collapsed drop-down.  Handing
one 32x32 to both slots -- which this file used to do -- makes WPF
downscale hard-edged pixel art by half, and hard-edged pixel art is the
worst thing there is to downscale.  So every glyph is drawn on a 32-unit
DESIGN GRID and rendered at each size, never resampled.

Pure stdlib -- ``zlib`` for the PNG deflate stream and ``struct`` for the
chunk framing -- because nothing else in this tree needs an imaging
library and an icon generator should not be the reason it gains one.
The glyphs are blocky, with no anti-aliasing: at 16x16 a smoothed edge is
a handful of pixels of a colour that was never in the palette, and code
that doesn't need to blend is code that can't blend wrong.

    python3 tools/gen_ribbon_icons.py           # write them all
    python3 tools/gen_ribbon_icons.py --check   # is the tree current?

``check_standards.py`` runs ``--check`` alongside the mirror, the
releases, the bundle and the two catalogs, so ``make check`` fails on a
stale icon exactly as it does on a stale twin.  These are the only files
in that list that are not text, and they belong in it for the same
reason as the rest: a deflate stream over a fixed input is
deterministic, so "is this what a fresh render would write" is a byte
comparison either way.  ``--check`` also reports an ORPHAN -- a PNG in
``icons/`` that nothing would write any more -- because a routine
dropped from FEATURED otherwise leaves its picture behind to be copied
into every bundle for ever.
"""

import argparse
import math
import pathlib
import struct
import sys
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from callib import ROOT  # noqa: E402
from check_registry import CATEGORIES  # noqa: E402
from gen_ui_data import featured  # noqa: E402

OUT_DIR = ROOT / "ui" / "calofin_ribbon" / "icons"

#: The ribbon's two slots: Image (small, the collapsed drop-down) and
#: LargeImage (the face of a large button).
SIZES = (16, 32)

#: The grid every glyph is drawn on, whatever size it is rendered at.
GRID = 32

#: One (background, glyph) colour pair per category.  A routine's icon
#: takes its CATEGORY's colours, so a panel reads as one family and the
#: glyph is what distinguishes a tool inside it -- five hues rather than
#: one accent repeated, and the shape carrying the rest.
PALETTE = {
    "Layout": ((0x2E, 0x5E, 0x8C), (0xFF, 0xFF, 0xFF)),
    "Points": ((0x3A, 0x8C, 0x4A), (0xFF, 0xFF, 0xFF)),
    "Dimensions": ((0xB0, 0x6A, 0x1E), (0xFF, 0xFF, 0xFF)),
    "Converters": ((0x7A, 0x3E, 0x9C), (0xFF, 0xFF, 0xFF)),
    "Checking": ((0x1E, 0x8C, 0x7A), (0xFF, 0xFF, 0xFF)),
}


# ------------------------------------------------------------- drawing

class Canvas:
    """A size x size grid of RGBA pixels, addressed in DESIGN units.

    Every primitive takes 0..GRID coordinates and maps them to pixels on
    the way in, so one glyph body renders at 16 and at 32 without being
    written twice and without either being a resample of the other.
    No anti-aliasing: every pixel is the background or the glyph colour
    and nothing in between.
    """

    def __init__(self, size, bg):
        self.size = size
        self.k = size / float(GRID)
        self.px = [[bg + (255,)] * size for _ in range(size)]

    # design units -> pixels.  Round HALF UP, never round(): Python
    # rounds a half to even, so at 16 -- where one design unit is half
    # a pixel and every other boundary lands on a half -- neighbouring
    # cells of the same width round to different widths, and three
    # 3x5 letters come out as a blob and a half.
    def m(self, v):
        return int(v * self.k + 0.5)

    # a design thickness -> pixels, never thinner than the one pixel
    # that is the whole of a stroke at 16
    def w(self, t):
        return max(1, int(t * self.k + 0.5))

    def set_px(self, x, y, rgba):
        if 0 <= x < self.size and 0 <= y < self.size:
            self.px[y][x] = rgba

    def rect(self, x0, y0, x1, y1, rgba, fill=True, thickness=1):
        x0, y0, x1, y1 = self.m(x0), self.m(y0), self.m(x1), self.m(y1)
        if fill:
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    self.set_px(x, y, rgba)
            return
        for t in range(self.w(thickness)):
            for x in range(x0, x1 + 1):
                self.set_px(x, y0 + t, rgba)
                self.set_px(x, y1 - t, rgba)
            for y in range(y0, y1 + 1):
                self.set_px(x0 + t, y, rgba)
                self.set_px(x1 - t, y, rgba)

    def line(self, x0, y0, x1, y1, rgba, thickness=1):
        """Bresenham, thickened by painting a (t x t) square at every
        step -- blocky on purpose, see the module docstring."""
        self._line_px(self.m(x0), self.m(y0), self.m(x1), self.m(y1),
                      rgba, self.w(thickness))

    def _line_px(self, x0, y0, x1, y1, rgba, t):
        dx, dy = abs(x1 - x0), abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        x, y = x0, y0
        half = t // 2
        while True:
            for ox in range(-half, t - half):
                for oy in range(-half, t - half):
                    self.set_px(x + ox, y + oy, rgba)
            if x == x1 and y == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x += sx
            if e2 < dx:
                err += dx
                y += sy

    def disc(self, cx, cy, r, rgba):
        """A filled circle.  The threshold is (r + 1/2)^2 rather than
        r^2: at the two- and three-pixel radii a survey dot actually
        gets, r^2 keeps the four axis pixels and drops the diagonals,
        which draws a four-pointed star where a dot was wanted."""
        cx, cy, r = self.m(cx), self.m(cy), max(1, self.m(r))
        limit = (r + 0.5) ** 2
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                if x * x + y * y <= limit:
                    self.set_px(cx + x, cy + y, rgba)

    def ring(self, cx, cy, r, rgba, thickness=2):
        """An arc's whole circle: every pixel whose distance from the
        centre falls inside the stroke."""
        self.arc(cx, cy, r, 0, 360, rgba, thickness)

    def arc(self, cx, cy, r, a0, a1, rgba, thickness=2):
        """Degrees, measured the way the glyphs read them: 0 at three
        o'clock, growing anticlockwise.  Stepped rather than
        parametrised by pixel, so the step count is a function of the
        rendered radius and the result is identical every run."""
        import math
        cxp, cyp, rp = self.m(cx), self.m(cy), max(1, self.m(r))
        t = self.w(thickness)
        steps = max(12, int(rp * 8))
        half = t // 2
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / float(steps))
            x = int(round(cxp + rp * math.cos(a)))
            y = int(round(cyp - rp * math.sin(a)))
            for ox in range(-half, t - half):
                for oy in range(-half, t - half):
                    self.set_px(x + ox, y + oy, rgba)

    def poly(self, pts, rgba, thickness=2, close=True):
        seq = list(pts) + ([pts[0]] if close else [])
        for (x0, y0), (x1, y1) in zip(seq, seq[1:]):
            self.line(x0, y0, x1, y1, rgba, thickness)

    def scanlines(self):
        """Raw PNG scanline bytes: one filter byte (0 = None) per row,
        then RGBA quadruplets."""
        out = bytearray()
        for row in self.px:
            out.append(0)
            for (r, g, b, a) in row:
                out += bytes((r, g, b, a))
        return bytes(out)


class Pen:
    """A glyph's own 0..100 square, mapped onto a box of the canvas.

    Every glyph below is written in that local square and knows nothing
    about where it lands, which is what lets the same body be drawn
    full-field on a plain icon and shrunk into the top-left when a badge
    has to share the field with it.
    """

    def __init__(self, canvas, fg, box=(0, 0, GRID, GRID)):
        self.c, self.fg = canvas, fg
        self.x0, self.y0, self.x1, self.y1 = box

    def X(self, u):
        return self.x0 + (self.x1 - self.x0) * u / 100.0

    def Y(self, v):
        return self.y0 + (self.y1 - self.y0) * v / 100.0

    def S(self, u):
        """A local length (thickness, radius) in design units."""
        return min(self.x1 - self.x0, self.y1 - self.y0) * u / 100.0

    def line(self, x0, y0, x1, y1, w=7):
        self.c.line(self.X(x0), self.Y(y0), self.X(x1), self.Y(y1),
                    self.fg, self.S(w))

    def rect(self, x0, y0, x1, y1, w=7, fill=False):
        self.c.rect(self.X(x0), self.Y(y0), self.X(x1), self.Y(y1),
                    self.fg, fill=fill, thickness=self.S(w))

    def disc(self, cx, cy, r):
        self.c.disc(self.X(cx), self.Y(cy), self.S(r), self.fg)

    def ring(self, cx, cy, r, w=7):
        self.c.ring(self.X(cx), self.Y(cy), self.S(r), self.fg, self.S(w))

    def arc(self, cx, cy, r, a0, a1, w=7):
        self.c.arc(self.X(cx), self.Y(cy), self.S(r), a0, a1,
                   self.fg, self.S(w))

    def poly(self, pts, w=7, close=True):
        self.c.poly([(self.X(u), self.Y(v)) for (u, v) in pts],
                    self.fg, self.S(w), close=close)


# ------------------------------------------------------------ lettering
#
# Four of the converters are named after the FORMAT they read -- XFT, SO,
# VS, G2M -- and a format is a name rather than a picture.  Four
# variations on "two arrows chasing each other" would be four icons a
# drafter has to read the tooltip to tell apart, which is the whole
# thing an icon is for.  So those wear their own initials, taken off the
# command name rather than typed (XFTCONV -> XFT), over the chasing
# arrows that say what KIND of tool it is.
#
# 3x5 is the smallest cell a letter survives in, and at 16x16 it renders
# one design pixel per cell pixel -- the floor this font exists to sit
# on.  The whole alphabet rather than the nine letters four converters
# happen to need: a table is cheap, and a fifth converter should not
# arrive to find its initials unspellable.

#: Three cells wide unless the letter cannot be drawn in three: an M
#: on a 3x5 cell is an H with a thick middle, which is exactly what
#: G2MCONV's icon read as before this was variable width.  text() walks
#: each row by index, so a five-wide entry needs nothing but the entry.
FONT = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "001", "001", "001"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
    "A": ("111", "101", "111", "101", "101"),
    "B": ("110", "101", "110", "101", "110"),
    "C": ("111", "100", "100", "100", "111"),
    "D": ("110", "101", "101", "101", "110"),
    "E": ("111", "100", "111", "100", "111"),
    "F": ("111", "100", "111", "100", "100"),
    "G": ("111", "100", "101", "101", "111"),
    "H": ("101", "101", "111", "101", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "J": ("001", "001", "001", "101", "111"),
    "K": ("101", "101", "110", "101", "101"),
    "L": ("100", "100", "100", "100", "111"),
    "M": ("10001", "11011", "10101", "10001", "10001"),
    "N": ("110", "101", "101", "101", "101"),
    "O": ("111", "101", "101", "101", "111"),
    "P": ("111", "101", "111", "100", "100"),
    "Q": ("111", "101", "101", "111", "001"),
    "R": ("111", "101", "110", "101", "101"),
    "S": ("111", "100", "111", "001", "111"),
    "T": ("111", "010", "010", "010", "010"),
    "U": ("101", "101", "101", "101", "111"),
    "V": ("101", "101", "101", "101", "010"),
    "W": ("10001", "10001", "10101", "11011", "01010"),
    "X": ("101", "101", "010", "101", "101"),
    "Y": ("101", "101", "010", "010", "010"),
    "Z": ("111", "001", "010", "100", "111"),
}


def text(c, word, cy, fg, cell):
    """WORD centred on the design row CY, CELL design units per font
    pixel.  Drawn onto the canvas directly rather than through a Pen:
    a letter has to land on WHOLE pixels at both sizes, so each cell is
    mapped as a half-open pixel span -- one pixel at 16, two at 32 --
    and never as a proportional rectangle that rounds where it likes.
    """
    def cells(ch):
        rows = FONT.get(ch.upper())
        return len(rows[0]) if rows else 3

    width = sum(cells(ch) + 1 for ch in word) - 1     # one cell of air
    x = (GRID - width * cell) / 2.0
    top = cy - 2.5 * cell
    for ch in word:
        rows = FONT.get(ch.upper())
        if rows:
            for ry, row in enumerate(rows):
                for rx, bit in enumerate(row):
                    if bit != "1":
                        continue
                    px0, px1 = c.m(x + rx * cell), c.m(x + (rx + 1) * cell)
                    py0, py1 = c.m(top + ry * cell), c.m(top + (ry + 1) * cell)
                    for yy in range(py0, max(py1, py0 + 1)):
                        for xx in range(px0, max(px1, px0 + 1)):
                            c.set_px(xx, yy, fg)
        x += (cells(ch) + 1) * cell


# ------------------------------------------------------ category glyphs
#
# The picture on a panel HEADER: what the whole category is, in one
# shape, so the strip reads as five different things before anyone reads
# a caption.

def g_cat_layout(p):
    """A floor plan: an outer wall and one partition -- Layout is the
    tools that draw the shape of the thing."""
    p.rect(8, 14, 92, 86, w=8)
    p.line(50, 14, 50, 86, w=8)


def g_cat_points(p):
    """A scatter of survey points, unevenly placed -- Points is never a
    grid, it is wherever the tape landed."""
    for (u, v) in ((16, 22), (78, 16), (48, 50), (20, 82), (82, 78)):
        p.disc(u, v, 11)


def g_cat_dimensions(p):
    """A dimension line, its extensions and its arrowheads -- the
    drafting symbol the category is named for."""
    p.line(8, 50, 92, 50, w=8)
    p.line(8, 26, 8, 74, w=7)
    p.line(92, 26, 92, 74, w=7)
    p.line(8, 50, 30, 33, w=7)
    p.line(8, 50, 30, 67, w=7)
    p.line(92, 50, 70, 33, w=7)
    p.line(92, 50, 70, 67, w=7)


def g_cat_converters(p):
    """Two arrows chasing each other -- a survey format going onto the
    shop's layers, and back off them."""
    p.line(12, 28, 78, 28, w=8)
    p.line(78, 28, 56, 8, w=8)
    p.line(78, 28, 56, 48, w=8)
    p.line(88, 72, 22, 72, w=8)
    p.line(22, 72, 44, 52, w=8)
    p.line(22, 72, 44, 92, w=8)


def g_cat_checking(p):
    """A checkmark."""
    p.line(10, 52, 38, 84, w=12)
    p.line(38, 84, 90, 14, w=12)


CATEGORY_GLYPHS = {
    "Layout": g_cat_layout,
    "Points": g_cat_points,
    "Dimensions": g_cat_dimensions,
    "Converters": g_cat_converters,
    "Checking": g_cat_checking,
}


# ------------------------------------------------------- subject glyphs
#
# What a tool ACTS ON.  Each is drawn in its Pen's own 0..100 square and
# knows nothing about where that square lands, which is what lets the
# same body be the whole icon at 16 and share the field with a badge at
# 32.

def g_pool(p):
    """A pool in plan, steps in the shallow end."""
    p.rect(4, 22, 96, 78, w=8)
    p.line(22, 22, 22, 78, w=6)
    p.line(36, 22, 36, 78, w=6)


def g_freeform(p):
    """OASIS: a perimeter that is all curve and no corner."""
    p.poly([(10, 44), (28, 16), (60, 10), (90, 32),
            (94, 64), (66, 88), (30, 82), (6, 62)], w=8)


def g_survey_shape(p):
    """ABHD: the same perimeter, but READ OFF the points it runs
    through -- the dots are the tool, the outline is the answer."""
    pts = [(12, 26), (36, 14), (64, 16), (90, 32),
           (88, 66), (58, 86), (26, 78), (8, 54)]
    p.poly(pts, w=4)
    for (u, v) in pts:
        p.disc(u, v, 9)


def g_spa(p):
    """An octagonal spa, with the jets in it."""
    p.poly([(32, 8), (68, 8), (92, 32), (92, 68),
            (68, 92), (32, 92), (8, 68), (8, 32)], w=8)
    p.disc(36, 54, 9)
    p.disc(60, 40, 8)
    p.disc(64, 66, 7)


def g_pads(p):
    """PADDLE: a perimeter with its pads round the outside."""
    p.rect(26, 28, 74, 72, w=7)
    for u in (34, 50, 66):
        p.rect(u - 7, 6, u + 7, 17, fill=True)
        p.rect(u - 7, 83, u + 7, 94, fill=True)
    for v in (40, 60):
        p.rect(6, v - 7, 17, v + 7, fill=True)
        p.rect(83, v - 7, 94, v + 7, fill=True)


def g_cube(p):
    """CUSTBLOCK: length, width and height, so a box in pictorial."""
    p.poly([(16, 34), (50, 14), (84, 34), (84, 70), (50, 90), (16, 70)], w=7)
    p.line(16, 34, 50, 54, w=7)
    p.line(84, 34, 50, 54, w=7)
    p.line(50, 54, 50, 90, w=7)


def g_chart_steps(p):
    """LAZSTEP: a filled-in sheet on the left, the steps it draws on the
    right."""
    p.rect(6, 12, 44, 88, w=7)
    for v in (34, 52, 70):
        p.line(15, v, 35, v, w=6)
    p.poly([(58, 20), (58, 44), (76, 44), (76, 68), (94, 68), (94, 92)],
           w=7, close=False)


def g_corner_steps(p):
    """CORNERSTP: treads turning a corner, so nested Ls."""
    for d in (26, 50, 74):
        p.poly([(6, 100 - d), (100 - d, 100 - d), (100 - d, 6)],
               w=7, close=False)


def g_hemi_steps(p):
    """HEMISTEP: the same treads, round."""
    p.line(4, 88, 96, 88, w=6)
    for r in (26, 46, 66):
        p.arc(50, 88, r, 12, 168, w=7)


def g_straight_steps(p):
    """NORMIESTEP: treads straight across the run."""
    p.rect(10, 14, 90, 86, w=7)
    for v in (32, 50, 68):
        p.line(10, v, 90, v, w=6)


def g_ties(p):
    """ABFIND: two stakes, two tapes, and the point they cross at."""
    p.disc(14, 16, 11)
    p.disc(86, 16, 11)
    p.line(14, 16, 50, 86, w=6)
    p.line(86, 16, 50, 86, w=6)
    p.disc(50, 86, 12)


def g_move_pt(p):
    """ABMOVE: where the point is, and where the tape says it goes."""
    p.ring(16, 74, 13, w=6)
    p.disc(84, 26, 13)
    p.line(30, 64, 66, 40, w=7)
    p.line(66, 40, 48, 40, w=6)
    p.line(66, 40, 62, 58, w=6)


def g_perp(p):
    """PERPPTS: a right angle off a wall, and the point at the end."""
    p.line(4, 80, 96, 80, w=8)
    p.line(50, 80, 50, 18, w=7)
    p.rect(50, 64, 66, 80, w=4)
    p.disc(50, 18, 11)


def g_dim_shape(p):
    """AUTODIM: a shape, with its dimensions put on it."""
    p.rect(8, 10, 68, 60, w=7)
    p.line(8, 82, 68, 82, w=6)
    p.line(8, 72, 8, 92, w=5)
    p.line(68, 72, 68, 92, w=5)
    p.line(90, 10, 90, 60, w=6)
    p.line(80, 10, 100, 10, w=5)
    p.line(80, 60, 100, 60, w=5)


def g_crossdim(p):
    """CDCREATE: two lines, and the cross dimension made between."""
    p.line(12, 6, 12, 94, w=7)
    p.line(72, 6, 72, 94, w=7)
    p.line(12, 50, 72, 50, w=6)
    p.line(12, 50, 30, 40, w=5)
    p.line(12, 50, 30, 60, w=5)
    p.line(72, 50, 54, 40, w=5)
    p.line(72, 50, 54, 60, w=5)


def g_diagdim(p):
    """CDCALLOUT: point to point, on the diagonal."""
    p.disc(14, 84, 12)
    p.disc(86, 16, 12)
    p.line(14, 84, 86, 16, w=6)
    p.line(86, 16, 62, 24, w=5)
    p.line(86, 16, 78, 42, w=5)


def g_badpoint(p):
    """BPCALLOUT: the point that is wrong, and the note about it."""
    p.line(14, 16, 50, 54, w=8)
    p.line(50, 16, 14, 54, w=8)
    p.line(52, 58, 74, 78, w=6)
    p.rect(58, 72, 98, 96, w=6)


def g_dimstamp(p):
    """DIMSTAMP: the dimension, and the label stamped under it."""
    p.line(6, 30, 94, 30, w=6)
    p.line(6, 16, 6, 44, w=5)
    p.line(94, 16, 94, 44, w=5)
    p.rect(28, 56, 72, 92, w=6)
    p.line(40, 74, 60, 74, w=7)


def g_sheet(p):
    """CHECK: the drawing itself."""
    p.rect(10, 6, 90, 94, w=7)
    for v in (30, 50, 70):
        p.line(24, v, 76, v, w=6)


def g_arc(p):
    """DIMARCCHECK: an arc, and the two ends the check is about."""
    p.arc(50, 86, 62, 25, 155, w=8)
    p.disc(6, 60, 11)
    p.disc(94, 60, 11)


def g_dimline(p):
    """DIMCHECK: one dimension, walked."""
    p.line(6, 50, 94, 50, w=8)
    p.line(6, 24, 6, 76, w=6)
    p.line(94, 24, 94, 76, w=6)
    p.line(6, 50, 28, 34, w=6)
    p.line(6, 50, 28, 66, w=6)
    p.line(94, 50, 72, 34, w=6)
    p.line(94, 50, 72, 66, w=6)


def g_gapcurve(p):
    """ABCURCHECK is CONTINUITY, so the glyph is a curve with the gap
    still in it -- what the tool is looking for, not what it leaves."""
    p.arc(50, 94, 70, 28, 74, w=8)
    p.arc(50, 94, 70, 104, 152, w=8)


def g_overlay(p):
    """OLAUTO: two perimeters, laid over each other."""
    p.rect(6, 6, 62, 62, w=7)
    p.rect(38, 38, 94, 94, w=7)


def g_pt_offset(p):
    """ABPCHECK: where the point is against where it should be."""
    p.disc(24, 28, 12)
    p.ring(74, 72, 12, w=6)
    p.line(34, 38, 64, 62, w=5)


def g_checklist(p):
    """LINCHECK: the list, with its items ticked."""
    p.rect(8, 6, 92, 94, w=7)
    for v in (26, 50, 74):
        p.line(20, v, 30, v + 8, w=6)
        p.line(30, v + 8, 44, v - 8, w=6)
        p.line(54, v, 80, v, w=6)


def g_bands(p):
    """LINFINCHECK: the liner, in panels."""
    p.rect(6, 16, 94, 84, w=7)
    p.line(36, 16, 36, 84, w=6)
    p.line(64, 16, 64, 84, w=6)


def g_cover(p):
    """COVERCHECK: the cover, and the roll it comes off."""
    p.rect(26, 10, 94, 90, w=7)
    p.rect(4, 10, 18, 90, fill=True)


def g_textlines(p):
    """LINTXTCHK: the words on the sheet."""
    p.line(8, 22, 92, 22, w=8)
    p.line(8, 50, 68, 50, w=8)
    p.line(8, 78, 84, 78, w=8)


def g_flow(p):
    """CCPRECHECK: the flow chart the tech is walked through."""
    p.rect(30, 4, 70, 28, w=6)
    p.line(50, 28, 50, 40, w=6)
    p.line(14, 40, 86, 40, w=6)
    p.line(14, 40, 14, 52, w=6)
    p.line(86, 40, 86, 52, w=6)
    p.rect(2, 52, 42, 80, w=6)
    p.rect(58, 52, 98, 80, w=6)


def g_report(p):
    """LAZDIAG: the failure report -- a page, and what went wrong on
    it."""
    p.rect(12, 4, 88, 96, w=7)
    p.rect(42, 22, 58, 60, fill=True)
    p.rect(42, 70, 58, 86, fill=True)


def g_log(p):
    """LAZLOG: every run, in the order they happened."""
    p.rect(4, 8, 70, 92, w=7)
    for v in (28, 46, 64):
        p.line(16, v, 58, v, w=6)
    p.ring(78, 74, 20, w=6)
    p.line(78, 74, 78, 60, w=5)
    p.line(78, 74, 90, 74, w=5)


# ------------------------------------------------- the same, at 16x16
#
# Six subjects carry more detail than 13 pixels hold: an octagon with
# three jets in it, a perimeter with eight dots on it, ten pads round a
# rectangle, a box in pictorial, and an exclamation mark inside a page
# all come out of the shrink as one blob.  A small icon is not a small
# picture of the big one -- it is the same IDEA with the detail that
# stopped carrying taken out -- so those six say it again in fewer
# strokes.  Everything not listed here reads at both sizes and is drawn
# once.

def g_spa_small(p):
    """The octagon alone; three jets inside it close up at 13 pixels."""
    p.poly([(34, 4), (66, 4), (96, 34), (96, 66),
            (66, 96), (34, 96), (4, 66), (4, 34)], w=9)


def g_survey_shape_small(p):
    """Four points and the perimeter through them, instead of eight."""
    pts = [(12, 22), (88, 12), (92, 82), (16, 90)]
    p.poly(pts, w=6)
    for (u, v) in pts:
        p.disc(u, v, 9)


def g_pads_small(p):
    """PADDLE said as pads ON a wall.  Ten pads round a rectangle
    shrink into a cross, which is a different drawing."""
    p.line(4, 66, 96, 66, w=11)
    for u in (22, 50, 78):
        p.rect(u - 7, 22, u + 7, 54, fill=True)


def g_cube_small(p):
    """A face and a lid: a full pictorial box loses its edges."""
    p.rect(6, 42, 62, 96, w=9)
    p.poly([(6, 42), (34, 10), (90, 10), (62, 42)], w=8)
    p.line(90, 10, 90, 64, w=8)
    p.line(62, 96, 90, 64, w=8)


def g_report_small(p):
    """LAZDIAG as the mark alone; the page around it closes the gap in
    the exclamation and turns the two into an A."""
    p.rect(38, 4, 62, 58, fill=True)
    p.rect(38, 72, 62, 96, fill=True)


# --------------------------------------------------------------- badges
#
# What KIND of operation, in the corner the subject leaves free.  Only
# at 32: a checkmark in the six pixels a 16x16 icon can spare for a
# corner is noise, and the small icon is only ever seen in the collapsed
# panel drop-down, where the command's name is written beside it.

def b_check(p):
    """This tool REVIEWS the thing its subject draws."""
    p.line(8, 48, 38, 84, w=20)
    p.line(38, 84, 92, 10, w=20)


def b_convert(p):
    """This tool moves a drawing between one format and ours."""
    p.line(6, 28, 72, 28, w=16)
    p.line(72, 28, 46, 4, w=16)
    p.line(72, 28, 46, 52, w=16)
    p.line(94, 72, 28, 72, w=16)
    p.line(28, 72, 54, 48, w=16)
    p.line(28, 72, 54, 96, w=16)


# ---------------------------------------------------------- composition

#: Where a badged subject sits, and where its badge sits, in design
#: units on the 32-unit grid.
SUBJECT_BOX = (0, 0, 21, 21)
BADGE_BOX = (19, 19, 32, 32)
FULL_BOX = (3, 3, GRID - 3, GRID - 3)


def plain(subject, small=None):
    """A glyph with the field to itself.  SMALL, where a subject has
    one, is the body drawn at 16 instead."""
    def draw(c, fg):
        body = small if (small and c.size < 32) else subject
        body(Pen(c, fg, FULL_BOX))
    return draw


def badged(subject, badge, small=None):
    """A subject with a badge in the corner -- at 32 only.  At 16 the
    subject takes the whole field: two shapes in 256 pixels is one
    shape's worth of information and neither one's worth of pixels."""
    def draw(c, fg):
        if c.size < 32:
            (small or subject)(Pen(c, fg, FULL_BOX))
            return
        subject(Pen(c, fg, SUBJECT_BOX))
        badge(Pen(c, fg, BADGE_BOX))
    return draw


def lettered(word):
    """A converter: its own initials over the chasing arrows.  The word
    is read off the command name by DESIGN below, never typed here."""
    def draw(c, fg):
        if c.size < 32:
            text(c, word, GRID / 2.0, fg, 2)
            return
        text(c, word, 10, fg, 2)
        b_convert(Pen(c, fg, (7, 18, 25, 32)))
    return draw


#: command -> how to draw it.  Every FEATURED command has an entry and
#: nothing else does; ``check()`` holds the two lists against each
#: other, so a routine promoted to a large button without a glyph fails
#: ``make check`` rather than shipping a button with no picture on it.
DESIGN = {
    # ---- Layout: the shapes the shop draws
    "POOL": plain(g_pool),
    "OASIS": plain(g_freeform),
    "ABHD": plain(g_survey_shape, g_survey_shape_small),
    "SPA": plain(g_spa, g_spa_small),
    "PADDLE": plain(g_pads, g_pads_small),
    "CUSTBLOCK": plain(g_cube, g_cube_small),
    "LAZSTEP": plain(g_chart_steps),
    "CORNERSTP": plain(g_corner_steps),
    "HEMISTEP": plain(g_hemi_steps),
    "NORMIESTEP": plain(g_straight_steps),
    # ---- Points: the survey work
    "ABFIND": plain(g_ties),
    "ABMOVE": plain(g_move_pt),
    "PERPPTS": plain(g_perp),
    # ---- Dimensions: the callouts and the stamp
    "AUTODIM": plain(g_dim_shape),
    "CDCREATE": plain(g_crossdim),
    "CDCALLOUT": plain(g_diagdim),
    "BPCALLOUT": plain(g_badpoint),
    "DIMSTAMP": plain(g_dimstamp),
    # ---- Converters: initials off the command name, over the arrows
    "XFTCONV": lettered("XFT"),
    "SOCONV": lettered("SO"),
    "VSCONV": lettered("VS"),
    "G2MCONV": lettered("G2M"),
    # ---- Checking: what is reviewed, badged with the tick
    "CHECK": badged(g_sheet, b_check),
    "DIMARCCHECK": badged(g_arc, b_check),
    "DIMCHECK": badged(g_dimline, b_check),
    "ABCURCHECK": badged(g_gapcurve, b_check),
    "ABPCHECK": badged(g_pt_offset, b_check),
    "LINFINCHECK": badged(g_bands, b_check),
    "COVERCHECK": badged(g_cover, b_check),
    "SPACHECK": badged(g_spa, b_check, g_spa_small),
    "LINTXTCHK": badged(g_textlines, b_check),
    # ---- Checking, unbadged: these three are not a review pass
    "OLAUTO": plain(g_overlay),
    "LINCHECK": plain(g_checklist),
    "CCPRECHECK": plain(g_flow),
    "LAZDIAG": plain(g_report, g_report_small),
    "LAZLOG": plain(g_log),
}


# ------------------------------------------------------------------ PNG

def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def encode(canvas):
    ihdr = struct.pack(">IIBBBBB", canvas.size, canvas.size, 8, 6, 0, 0, 0)
    idat = zlib.compress(canvas.scanlines(), 9)
    return (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) +
            _chunk(b"IDAT", idat) + _chunk(b"IEND", b""))


def category_png(category, size):
    bg, fg = PALETTE[category]
    c = Canvas(size, bg)
    CATEGORY_GLYPHS[category](Pen(c, fg + (255,), FULL_BOX))
    return encode(c)


def command_png(command, category, size):
    bg, fg = PALETTE[category]
    c = Canvas(size, bg)
    DESIGN[command](c, fg + (255,))
    return encode(c)


# ------------------------------------------------------------ the files

def category_path(category, size):
    return OUT_DIR / ("cat-%s-%d.png" % (category.lower(), size))


def command_path(command, size):
    return OUT_DIR / ("cmd-%s-%d.png" % (command.lower(), size))


def wanted():
    """{path: bytes}: every icon this tree should carry, and nothing
    else.  One dict rather than two loops, so ``--check``, the writer
    and the orphan sweep can never disagree about what the set IS."""
    out = {}
    for cat in CATEGORIES:
        for size in SIZES:
            out[category_path(cat, size)] = category_png(cat, size)
    for cat, cmd in featured():
        for size in SIZES:
            out[command_path(cmd, size)] = command_png(cmd, cat, size)
    return out


# --------------------------------------------------------------- driver

def check():
    """Problems as a list of strings, empty when the tree is current."""
    problems = []

    missing_glyph = sorted({c for _cat, c in featured()} - set(DESIGN))
    if missing_glyph:
        problems.append(
            "FEATURED names %d routine(s) with no glyph in DESIGN: %s\n"
            "  A large ribbon button with no picture on it is the one "
            "thing this file exists to prevent."
            % (len(missing_glyph), ", ".join(missing_glyph)))
    spare_glyph = sorted(set(DESIGN) - {c for _cat, c in featured()})
    if spare_glyph:
        problems.append(
            "DESIGN draws %d routine(s) that are not FEATURED: %s\n"
            "  Nothing would ever show them; drop the entry or add the "
            "name to gen_ui_data.FEATURED."
            % (len(spare_glyph), ", ".join(spare_glyph)))
    if problems:
        return problems

    want = wanted()
    for path in sorted(want):
        rel = path.relative_to(ROOT)
        if not path.is_file():
            problems.append(
                "%s: missing - run python3 tools/gen_ribbon_icons.py" % rel)
        elif path.read_bytes() != want[path]:
            problems.append(
                "%s: stale - regenerate with "
                "python3 tools/gen_ribbon_icons.py" % rel)

    if OUT_DIR.is_dir():
        for path in sorted(OUT_DIR.iterdir()):
            if path.suffix.lower() == ".png" and path not in want:
                problems.append(
                    "%s: orphan - nothing would write this any more.  A "
                    "routine dropped from FEATURED leaves its picture to "
                    "be copied into every bundle for ever; delete it."
                    % path.relative_to(ROOT))
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="report staleness instead of writing")
    ap.add_argument("--prune", action="store_true",
                    help="also delete orphaned PNGs")
    args = ap.parse_args(argv)

    if args.check:
        problems = check()
        for p in problems:
            print(p)
        if problems:
            return 1
        print("gen_ribbon_icons: %d icons current (%d categories + %d "
              "routines, at %s)"
              % (len(wanted()), len(CATEGORIES), len(DESIGN),
                 " and ".join("%dpx" % s for s in SIZES)))
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    want = wanted()
    changed = 0
    for path in sorted(want):
        blob = want[path]
        if not path.is_file() or path.read_bytes() != blob:
            path.write_bytes(blob)
            changed += 1

    pruned = 0
    for path in sorted(OUT_DIR.iterdir()):
        if path.suffix.lower() == ".png" and path not in want:
            if args.prune:
                path.unlink()
                pruned += 1
            else:
                print("gen_ribbon_icons: %s is an ORPHAN - delete it, or "
                      "re-run with --prune" % path.relative_to(ROOT))

    print("gen_ribbon_icons: %d icons, %d written, %d unchanged%s"
          % (len(want), changed, len(want) - changed,
             (", %d pruned" % pruned) if pruned else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
