# SPDX-License-Identifier: GPL-3.0-or-later
"""Getting an Image in and out of a file, and marking one up.

Two jobs, both small, both here because they are the only places in the
program that care how a pixel is spelled:

* **PNG** in and out.  Out, so a run can save the screenshot it worked
  from -- a detector that missed a dot is a bug report nobody can act on
  without the picture.  In, so that screenshot can be fed straight back
  through the detector on any machine, which is what makes the offline
  ``--from-shot`` mode (and the whole test suite) possible without
  Windows.  Eight-bit, non-interlaced, greyscale/RGB/RGBA: what a
  screen grab is, not what the format allows.

* **PPM**, because Tk's PhotoImage will read one and will not read a
  Python object, and PPM is a nine-byte header in front of the bytes we
  already have.  It is how the picker and the magnifier put a
  screenshot on screen with no imaging library installed.

Plus the handful of drawing primitives the annotated output needs.  A
3x5 bitmap font for the digits is not elegant, but the alternative is a
font file or a dependency, and the numbers only have to be legible
enough to check an order against.
"""

import math
import struct
import zlib

from detect import Image

# ------------------------------------------------------------------- PNG


def write_png(path, img):
    """Write an 8-bit RGB PNG.  Filter 0 on every row: fast, big, plain."""
    raw = bytearray()
    row = img.width * 3
    for y in range(img.height):
        raw.append(0)
        raw += img.rgb[y * row:(y + 1) * row]

    def chunk(kind, payload):
        head = struct.pack(">I", len(payload)) + kind
        return head + payload + struct.pack(
            ">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

    header = struct.pack(">2I5B", img.width, img.height, 8, 2, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", header))
        handle.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        handle.write(chunk(b"IEND", b""))


#: Bytes per pixel for the colour types this reader handles.  Palette
#: (type 3) is missing on purpose: no screen grabber writes one, and
#: half-supporting it would be worse than saying so.
_CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


def _unfilter(raw, width, height, stride):
    """Undo the five PNG row filters in place, one row at a time."""
    out = bytearray(height * stride)
    step = stride // width           # bytes per pixel, for the a/c taps
    at = 0
    for y in range(height):
        kind = raw[at]
        at += 1
        line = bytearray(raw[at:at + stride])
        at += stride
        base = y * stride
        prior = out[base - stride:base] if y else bytearray(stride)
        if kind == 1:
            for i in range(step, stride):
                line[i] = (line[i] + line[i - step]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + prior[i]) & 0xFF
        elif kind == 3:
            for i in range(stride):
                left = line[i - step] if i >= step else 0
                line[i] = (line[i] + ((left + prior[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                left = line[i - step] if i >= step else 0
                up = prior[i]
                upleft = prior[i - step] if i >= step else 0
                guess = left + up - upleft
                da = abs(guess - left)
                db = abs(guess - up)
                dc = abs(guess - upleft)
                if da <= db and da <= dc:
                    pick = left
                elif db <= dc:
                    pick = up
                else:
                    pick = upleft
                line[i] = (line[i] + pick) & 0xFF
        elif kind:
            raise ValueError("PNG row filter %d is not one of 0-4" % kind)
        out[base:base + stride] = line
    return out


def read_png(path):
    """Read an 8-bit non-interlaced PNG into an Image."""
    with open(path, "rb") as handle:
        blob = handle.read()
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path)
    at = 8
    width = height = depth = kind = None
    interlace = 0
    data = bytearray()
    while at + 8 <= len(blob):
        size, name = struct.unpack(">I4s", blob[at:at + 8])
        body = blob[at + 8:at + 8 + size]
        at += 12 + size
        if name == b"IHDR":
            width, height, depth, kind, _, _, interlace = struct.unpack(
                ">2I5B", body)
        elif name == b"IDAT":
            data += body
        elif name == b"IEND":
            break
    if width is None:
        raise ValueError("%s has no IHDR" % path)
    if depth != 8 or interlace or kind not in _CHANNELS:
        raise ValueError(
            "%s is %d-bit colour type %d%s -- this reader handles 8-bit "
            "greyscale, RGB and RGBA, not interlaced"
            % (path, depth, kind, ", interlaced" if interlace else ""))
    step = _CHANNELS[kind]
    rows = _unfilter(zlib.decompress(bytes(data)), width, height,
                     width * step)
    if kind == 2:
        return Image(width, height, bytes(rows))
    rgb = bytearray(width * height * 3)
    if kind == 6:                      # RGBA -> drop alpha
        rgb[0::3] = rows[0::4]
        rgb[1::3] = rows[1::4]
        rgb[2::3] = rows[2::4]
    elif kind == 0:                    # grey -> replicate
        rgb[0::3] = rgb[1::3] = rgb[2::3] = rows
    else:                              # grey + alpha
        grey = rows[0::2]
        rgb[0::3] = rgb[1::3] = rgb[2::3] = grey
    return Image(width, height, bytes(rgb))


# ------------------------------------------------------------------- PPM


def ppm_header(img):
    return b"P6\n%d %d\n255\n" % (img.width, img.height)


def ppm_bytes(img):
    """The image as binary PPM -- the one format Tk reads without help."""
    return ppm_header(img) + bytes(img.rgb)


def write_ppm(path, img):
    """Header, then the pixels, straight out -- never joined up first.

    A screenshot of three 4K monitors is seventy-five megabytes, and
    concatenating a header onto it doubles that for as long as it takes
    to hit the disk.  Two writes cost nothing and peak at one copy.
    """
    with open(path, "wb") as handle:
        handle.write(ppm_header(img))
        handle.write(img.rgb)


# ---------------------------------------------------------------- drawing

#: 3x5, one string per digit, read as rows of "1" = ink.  Big enough to
#: tell 6 from 8 at 3x, small enough to sit beside a four-pixel dot.
_DIGITS = {
    "0": "111101101101111", "1": "010110010010111",
    "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111",
    "6": "111100111101111", "7": "111001001001001",
    "8": "111101111101111", "9": "111101111001111",
}


class Canvas(object):
    """A mutable Image you can draw on.  Clipped, so nothing can escape."""

    def __init__(self, img):
        self.width = img.width
        self.height = img.height
        self.rgb = bytearray(img.rgb)

    def image(self):
        return Image(self.width, self.height, bytes(self.rgb))

    def dot(self, x, y, color):
        if 0 <= x < self.width and 0 <= y < self.height:
            i = (y * self.width + x) * 3
            self.rgb[i], self.rgb[i + 1], self.rgb[i + 2] = color

    def box(self, x, y, width, height, color):
        for j in range(y, y + height):
            for i in range(x, x + width):
                self.dot(i, j, color)

    def circle(self, cx, cy, radius, color):
        """An unfilled ring, sampled densely enough to have no gaps."""
        steps = max(8, int(radius * 8))
        for k in range(steps):
            angle = 2.0 * math.pi * k / steps
            self.dot(int(round(cx + radius * math.cos(angle))),
                     int(round(cy + radius * math.sin(angle))), color)

    def crosshair(self, cx, cy, arm, color, gap=2):
        for d in range(gap, arm + 1):
            self.dot(cx + d, cy, color)
            self.dot(cx - d, cy, color)
            self.dot(cx, cy + d, color)
            self.dot(cx, cy - d, color)

    def number(self, x, y, value, color, scale=2, back=(0, 0, 0)):
        """Draw an integer with its top-left at (x, y).  Returns its width."""
        text = str(value)
        width = (len(text) * 4 - 1) * scale
        if back is not None:
            self.box(x - scale, y - scale, width + 2 * scale,
                     5 * scale + 2 * scale, back)
        for index, char in enumerate(text):
            glyph = _DIGITS.get(char)
            if not glyph:
                continue
            for row in range(5):
                for col in range(3):
                    if glyph[row * 3 + col] == "1":
                        self.box(x + (index * 4 + col) * scale,
                                 y + row * scale, scale, scale, color)
        return width


INK = {"red": (255, 70, 40), "blue": (0, 229, 255)}


def annotate(img, points, colors=None, scale=2):
    """A copy of the image with every point ringed and numbered.

    This is the picture in the operator's own screenshots -- a ring on
    each dot and its place in the order beside it -- and it is the
    fastest way to see whether the detector and the ordering agree with
    what a human would have done.
    """
    canvas = Canvas(img)
    for index, (x, y) in enumerate(points):
        x, y = int(round(x)), int(round(y))
        color = INK.get((colors or {}).get(index, "blue"), INK["blue"])
        canvas.circle(x, y, 6, color)
        canvas.circle(x, y, 7, (0, 0, 0))
        canvas.number(x + 9, y - 5, index + 1, color, scale)
    return canvas.image()
