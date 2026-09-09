# SPDX-License-Identifier: GPL-3.0-or-later
"""Find the survey dots in a screenshot of an Ariel photo.

The dots are the physical markers stuck on the deck before the drone
flight -- bright cyan, navy and red discs a few pixels across once the
photo is on screen.  Digitising them is the slow half of the job: the
operator hunts for the next dot, clicks it, checks it, and repeats forty
times.  This module does the hunting.

Nothing here imports anything but the standard library and nothing here
touches the screen, so the whole detector runs (and is tested) on a
machine with no Windows and no Ariel: feed it a PNG.

HOW IT WORKS
------------
Three passes, cheapest first, because a screenshot is two million pixels
and this is pure Python:

1. ``marker_mask`` -- the colour test, over every pixel at once.  A
   Python-level loop over two million pixels costs seconds; the same
   work as bitwise arithmetic on a pair of two-megabyte integers costs
   milliseconds, and CPython's big integers are the only vectoriser the
   standard library has.  ``bytes.translate`` thresholds one channel,
   ``&`` and ``|`` combine them, and ``_gap`` -- see below -- gets the
   comparisons BETWEEN channels that a per-channel threshold cannot
   express.  Those are the ones that matter: a marker is not "bright
   blue", it is blue by a wide margin over its own red, and shadowed
   concrete lit by open sky is bluish too.

2. ``components`` -- 8-connected blobs, built from horizontal RUNS
   rather than pixels.  A run is found with ``bytes.find``, which is C,
   and a run's pixel count, x-sum and y-sum are arithmetic rather than a
   loop, so the cost of this pass is the number of runs and not the
   number of pixels.  That matters because the two things the colour
   test cannot reject are enormous: the pool water is a million cyan
   pixels and the brick coping is a red ring around it.  Both arrive
   here as a handful of runs per row and leave as one over-sized blob
   each, rejected on size before a single pixel of them is examined.

3. ``classify`` -- hue and saturation, per pixel, on the blobs that
   survived the size and roundness filters.  It settles the colour of
   each dot and is the last chance to throw out something dot-shaped
   that is not a dot.

The split is the whole trick.  Pass 1 has to look at everything, so it
may only do what bitwise arithmetic can do; pass 3 can do real
arithmetic, so it may only look at what is left.

WHY THE GAPS ARE COMPUTED THE WAY THEY ARE
------------------------------------------
"Blue minus red is at least 45" is a subtraction, and subtracting one
big integer from another borrows across pixel boundaries, which would
smear every comparison into its neighbour.  ``_gap`` widens both
channels to two bytes per pixel and biases each lane by 0x100 first:
every lane then holds 0x100 + a - b, which stays inside its own two
bytes for any pair of 8-bit values, so nothing borrows.  The high byte
of the lane is 1 exactly when a >= b and the low byte is the difference
itself, and both come back out as strided slices for one more
``translate``.  The result is an exact per-pixel channel comparison at
the cost of two array copies.
"""

# --------------------------------------------------------------------- image


class Image(object):
    """A width x height block of 8-bit RGB, three bytes per pixel.

    Deliberately dumb: the screen grab, the PNG reader and the tests all
    produce one of these and nothing else in the program knows how a
    pixel is stored.
    """

    __slots__ = ("width", "height", "rgb")

    def __init__(self, width, height, rgb):
        if len(rgb) != width * height * 3:
            raise ValueError("rgb is %d bytes, expected %d for %dx%d"
                             % (len(rgb), width * height * 3, width, height))
        self.width = width
        self.height = height
        self.rgb = rgb

    @classmethod
    def from_bgra(cls, width, height, bgra):
        """Wrap the buffer a 32-bit Windows DIB hands back.

        CreateDIBSection gives BGRA with no padding at 32bpp, so the
        three channels come out as strided slices -- C speed -- and go
        back interleaved the same way.
        """
        out = bytearray(width * height * 3)
        out[0::3] = bgra[2::4]
        out[1::3] = bgra[1::4]
        out[2::3] = bgra[0::4]
        return cls(width, height, bytes(out))

    def pixel(self, x, y):
        i = (y * self.width + x) * 3
        return self.rgb[i], self.rgb[i + 1], self.rgb[i + 2]

    def crop(self, x, y, width, height):
        """The sub-image at (x, y), clipped to what actually exists."""
        x = max(0, min(x, self.width))
        y = max(0, min(y, self.height))
        width = max(0, min(width, self.width - x))
        height = max(0, min(height, self.height - y))
        out = bytearray(width * height * 3)
        row = width * 3
        src = self.rgb
        for j in range(height):
            start = ((y + j) * self.width + x) * 3
            out[j * row:(j + 1) * row] = src[start:start + row]
        return Image(width, height, bytes(out))


# -------------------------------------------------------------------- tuning


class Tuning(object):
    """Every threshold the detector has, in one place with its default.

    They are all on the command line because a dot's colour on screen is
    not a constant: it is paint, in sunlight, through a drone camera, at
    whatever zoom the operator happens to be at.  The defaults suit the
    markers in the reference photos; a washed-out job needs looser ones
    and the README says which knob to turn.
    """

    __slots__ = ("red_min", "red_gap", "blue_min", "blue_gap",
                 "blue_green_slack",
                 "min_size", "max_size", "min_area", "fill", "aspect",
                 "min_value", "min_sat", "vote", "merge", "colors")

    def __init__(self, red_min=110, red_gap=45,
                 blue_min=95, blue_gap=45, blue_green_slack=22,
                 min_size=3, max_size=34, min_area=6,
                 fill=0.45, aspect=2.4,
                 min_value=70, min_sat=0.30, vote=0.4,
                 merge=4.0, colors=("red", "blue")):
        self.red_min = red_min              # red dots: R at least this
        self.red_gap = red_gap              #   and this far above G and B
        self.blue_min = blue_min            # blue/cyan dots: B at least this
        self.blue_gap = blue_gap            #   and this far above R
        self.blue_green_slack = blue_green_slack   # R may lead G by this much
        self.min_size = min_size            # bbox, pixels, both axes
        self.max_size = max_size
        self.min_area = min_area            # lit pixels in the blob
        self.fill = fill                    # area / bbox area; a disc is .78
        self.aspect = aspect                # long side / short side
        self.min_value = min_value          # exact test: brightest channel
        self.min_sat = min_sat              # exact test: (max-min)/max
        self.vote = vote                    # share of samples that must agree
        self.merge = merge                  # centroids closer than this are one
        self.colors = tuple(colors)         # which classes to keep


#: Hue windows, in degrees, for the two colours a marker comes in.  The
#: blue window runs from a green-leaning cyan to a violet-leaning navy
#: because the dots in the reference photos are both, and the water --
#: which sits in the middle of it -- is excluded by size, not by hue.
HUE = {
    "red": lambda h: h <= 25.0 or h >= 330.0,
    "blue": lambda h: 170.0 <= h <= 268.0,
}


class Dot(object):
    """One detected marker: where it is, how big, and what colour."""

    __slots__ = ("x", "y", "area", "width", "height", "color")

    def __init__(self, x, y, area, width, height, color):
        self.x = x
        self.y = y
        self.area = area
        self.width = width
        self.height = height
        self.color = color

    @property
    def point(self):
        """The integer pixel to click."""
        return (int(round(self.x)), int(round(self.y)))

    def __repr__(self):
        return ("Dot(%.1f, %.1f, %s, %dx%d, area=%d)"
                % (self.x, self.y, self.color, self.width, self.height,
                   self.area))


# ---------------------------------------------------------------- pass 1

_BANDS = {}
_BIAS = {}
_ONES = {}


def _band(channel, lo, hi):
    """One byte per pixel, 1 where lo <= value <= hi, as a big integer.

    ``translate`` is a C loop over a 256-entry table and
    ``int.from_bytes`` is a memcpy, so a whole-image threshold costs
    about as much as copying the channel once.  The tables are cached
    because a run asks for the same handful of bands over and over.
    """
    table = _BANDS.get((lo, hi))
    if table is None:
        table = bytes(1 if lo <= i <= hi else 0 for i in range(256))
        _BANDS[(lo, hi)] = table
    return int.from_bytes(channel.translate(table), "big")


def _gap(hot, cold, least):
    """1 where hot - cold >= least, per pixel, with no borrow between them.

    See the module docstring: the two channels are widened to a 16-bit
    lane each and the minuend is biased by 0x100, so every lane holds
    0x100 + hot - cold, a value between 1 and 511.  It cannot go
    negative, so no lane can borrow from the one above it, and the two
    halves of the lane answer the question directly -- high byte 1 for
    "hot won", low byte for "by how much".
    """
    count = len(hot)
    bias = _BIAS.get(count)
    if bias is None:
        bias = _BIAS[count] = int.from_bytes(b"\x01\x00" * count, "big")
    wide_hot = bytearray(count * 2)
    wide_hot[1::2] = hot
    wide_cold = bytearray(count * 2)
    wide_cold[1::2] = cold
    lanes = ((int.from_bytes(wide_hot, "big") + bias)
             - int.from_bytes(wide_cold, "big")).to_bytes(count * 2, "big")
    return _band(lanes[0::2], 1, 255) & _band(lanes[1::2], max(1, least), 255)


def _ones_for(count):
    ones = _ONES.get(count)
    if ones is None:
        ones = _ONES[count] = int.from_bytes(b"\x01" * count, "big")
    return ones


def marker_mask(img, tune):
    """One byte per pixel, 1 where the pixel is marker-coloured.

    Red wants a bright red channel that beats BOTH of the others by a
    wide margin; blue wants a blue channel that beats red by one, with
    green not far below red -- that last clause is what keeps purple
    and magenta out of a window that has to stretch from cyan to navy,
    because the markers come in both.

    Grey cannot satisfy either: every gap is zero when the channels are
    equal, and near-grey fails for the same reason at one remove, which
    is the entire reason the test is written as gaps and not as levels.
    """
    count = img.width * img.height
    if count == 0:
        return b""
    red_ch = img.rgb[0::3]
    green_ch = img.rgb[1::3]
    blue_ch = img.rgb[2::3]
    bits = 0
    if "red" in tune.colors:
        bits |= (_band(red_ch, tune.red_min, 255)
                 & _gap(red_ch, green_ch, tune.red_gap)
                 & _gap(red_ch, blue_ch, tune.red_gap))
    if "blue" in tune.colors:
        not_reddish = _ones_for(count) ^ _gap(red_ch, green_ch,
                                              tune.blue_green_slack)
        bits |= (_band(blue_ch, tune.blue_min, 255)
                 & _gap(blue_ch, red_ch, tune.blue_gap)
                 & not_reddish)
    return bits.to_bytes(count, "big")


# ---------------------------------------------------------------- pass 2


def _root(parent, i):
    top = i
    while parent[top] != top:
        top = parent[top]
    while parent[i] != top:
        parent[i], i = top, parent[i]
    return top


def _union(parent, a, b):
    ra, rb = _root(parent, a), _root(parent, b)
    if ra != rb:
        parent[max(ra, rb)] = min(ra, rb)


class Blob(object):
    """An 8-connected group of mask runs, with its box and centroid."""

    __slots__ = ("runs", "area", "x0", "x1", "y0", "y1", "sum_x", "sum_y")

    def __init__(self):
        self.runs = []
        self.area = 0
        self.sum_x = 0
        self.sum_y = 0
        self.x0 = self.y0 = 1 << 30
        self.x1 = self.y1 = -1

    @property
    def width(self):
        return self.x1 - self.x0 + 1

    @property
    def height(self):
        return self.y1 - self.y0 + 1

    @property
    def centroid(self):
        return (self.sum_x / float(self.area), self.sum_y / float(self.area))


def components(mask, width, height):
    """Every 8-connected blob in the mask, found run by run.

    Two pointers walk the current row's runs against the previous row's,
    which is linear in runs; a blob's area and centroid are closed-form
    sums over its runs, so no pixel is visited twice and the water --
    one run per row, a thousand rows -- costs a thousand steps instead
    of a million.
    """
    ys, x0s, x1s, parent = [], [], [], []
    prev_lo = prev_hi = 0
    for y in range(height):
        row_lo = len(ys)
        base = y * width
        end = base + width
        at = base
        while True:
            start = mask.find(1, at, end)
            if start < 0:
                break
            stop = mask.find(0, start + 1, end)
            if stop < 0:
                stop = end
            ys.append(y)
            x0s.append(start - base)
            x1s.append(stop - base)
            parent.append(len(parent))
            at = stop + 1
        # Link this row's runs to the previous row's.  Half-open [x0,x1),
        # so runs that only touch corner-to-corner still overlap here --
        # which is what makes the labelling 8-connected.
        cursor = prev_lo
        for i in range(row_lo, len(ys)):
            a0, a1 = x0s[i], x1s[i]
            while cursor < prev_hi and x1s[cursor] < a0:
                cursor += 1
            k = cursor
            while k < prev_hi and x0s[k] <= a1:
                _union(parent, i, k)
                k += 1
        prev_lo, prev_hi = row_lo, len(ys)

    blobs = {}
    for i in range(len(ys)):
        blob = blobs.get(_root(parent, i))
        if blob is None:
            blob = blobs[_root(parent, i)] = Blob()
        y, x0, x1 = ys[i], x0s[i], x1s[i]
        n = x1 - x0
        blob.runs.append((y, x0, x1))
        blob.area += n
        blob.sum_x += (x0 + x1 - 1) * n // 2
        blob.sum_y += y * n
        if x0 < blob.x0:
            blob.x0 = x0
        if x1 - 1 > blob.x1:
            blob.x1 = x1 - 1
        if y < blob.y0:
            blob.y0 = y
        if y > blob.y1:
            blob.y1 = y
    return list(blobs.values())


def plausible(blob, tune):
    """Is this blob dot-shaped?  Size, then squareness, then fill.

    Cheap and ruthless, and the only thing standing between the exact
    colour test and a million pixels of swimming pool.
    """
    w, h = blob.width, blob.height
    if blob.area < tune.min_area:
        return False
    if min(w, h) < tune.min_size or max(w, h) > tune.max_size:
        return False
    if max(w, h) > tune.aspect * min(w, h):
        return False
    return blob.area >= tune.fill * w * h


# ---------------------------------------------------------------- pass 3


def hue_sat(r, g, b):
    """Hue in degrees, saturation 0..1, and the brightest channel."""
    top = r if r > g else g
    if b > top:
        top = b
    low = r if r < g else g
    if b < low:
        low = b
    if top == 0:
        return 0.0, 0.0, 0
    span = top - low
    if span == 0:
        return 0.0, 0.0, top
    if top == r:
        hue = 60.0 * (((g - b) / float(span)) % 6.0)
    elif top == g:
        hue = 60.0 * ((b - r) / float(span) + 2.0)
    else:
        hue = 60.0 * ((r - g) / float(span) + 4.0)
    return hue, span / float(top), top


def classify(img, blob, tune, limit=64):
    """The colour of a blob, or None if its pixels do not agree on one.

    A vote rather than an average: the edge of an anti-aliased dot is
    half deck, and averaging those in drags a perfectly good marker
    below the saturation floor.  Sampling at a stride keeps the cost
    flat whether the blob is six pixels or six hundred.
    """
    step = max(1, blob.area // limit)
    votes = {"red": 0, "blue": 0}
    taken = 0
    n = 0
    for (y, x0, x1) in blob.runs:
        for x in range(x0, x1):
            n += 1
            if n % step:
                continue
            taken += 1
            r, g, b = img.pixel(x, y)
            hue, sat, value = hue_sat(r, g, b)
            if value < tune.min_value or sat < tune.min_sat:
                continue
            for name in tune.colors:
                if HUE[name](hue):
                    votes[name] += 1
                    break
    if not taken:
        return None
    best = max(votes, key=lambda k: votes[k])
    if votes[best] < tune.vote * taken:
        return None
    return best


# ------------------------------------------------------------------- driver


def merge_close(dots, distance):
    """Fold dots whose centres are within `distance` into one.

    A specular highlight can split one marker into a ring of fragments;
    each fragment passes every filter on its own and the operator gets
    asked to confirm the same dot four times.  Cheap to undo here.
    """
    if distance <= 0 or not dots:
        return dots
    limit = distance * distance
    kept = []
    for dot in sorted(dots, key=lambda d: -d.area):
        for other in kept:
            dx = dot.x - other.x
            dy = dot.y - other.y
            if dx * dx + dy * dy <= limit:
                break
        else:
            kept.append(dot)
    return kept


def find_dots(img, tune=None):
    """Every marker dot in the image, in no particular order.

    Ordering is a separate question with more than one right answer --
    see ordering.py -- so this returns them top-to-bottom and leaves it
    alone.
    """
    tune = tune or Tuning()
    mask = marker_mask(img, tune)
    dots = []
    for blob in components(mask, img.width, img.height):
        if not plausible(blob, tune):
            continue
        color = classify(img, blob, tune)
        if color is None:
            continue
        x, y = blob.centroid
        dots.append(Dot(x, y, blob.area, blob.width, blob.height, color))
    dots = merge_close(dots, tune.merge)
    dots.sort(key=lambda d: (d.y, d.x))
    return dots
