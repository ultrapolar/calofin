# SPDX-License-Identifier: GPL-3.0-or-later
"""The Ariel anchor placer, without Windows, Ariel or a mouse.

ariel/ is a Windows program, but only two of its seven modules touch
Windows.  The rest -- finding the dots, deciding the order, driving the
confirm-every-one loop, reading and writing the pictures -- is ordinary
Python over bytes, and it is checked here the way the AutoLISP tools
are checked in the VM: on a scene built to look like the job.

The scene is the reference photo in outline.  A concrete deck under
dappled tree shadow, a pool of bright cyan water with a dark red brick
coping round it, and forty-four markers on the deck: cyan and navy dots
with four red targets among them.  Every one of those is something the
detector has to tell apart, and three of them are traps:

* the WATER is exactly the colour of a cyan marker and a million times
  the size, so only the size filter separates them;
* the COPING is exactly the colour of a red marker, for the same
  reason;
* the SHADOW is faintly blue -- concrete lit by open sky is -- so a
  detector that asks "is the blue channel high" rather than "does blue
  beat red by a margin" fills the deck with false dots and, worse,
  bridges the real ones into the noise around them and loses those too.

That last one is not hypothetical: the first draft of marker_mask
thresholded each channel on its own, and the dot at the top left of
this very scene came out as a 9x12 smear and failed the roundness test.
Hence _gap, and hence the test below that checks it against arithmetic
done the slow, obvious way.

Run: python3 tests/test_ariel_anchors.py
"""

import colorsys
import math
import struct
import os
import random
import re
import sys
import tempfile
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "ariel"))

import anchors      # noqa: E402
import detect       # noqa: E402
import ordering     # noqa: E402
import pixmap       # noqa: E402
import placement    # noqa: E402

CYAN = (0, 229, 255)
NAVY = (20, 51, 122)
RED = (224, 48, 32)
WATER = (41, 198, 224)
BRICK = (150, 70, 58)


# --------------------------------------------------------------- the scene


class Scene(object):
    """A deck, a pool and forty-four markers, drawn a pixel at a time."""

    def __init__(self, width=520, height=380, seed=11):
        self.width = width
        self.height = height
        self.buf = bytearray(width * height * 3)
        self.rnd = random.Random(seed)
        self.markers = []

    def put(self, x, y, rgb):
        if 0 <= x < self.width and 0 <= y < self.height:
            at = (y * self.width + x) * 3
            self.buf[at], self.buf[at + 1], self.buf[at + 2] = rgb

    def get(self, x, y):
        at = (y * self.width + x) * 3
        return (self.buf[at], self.buf[at + 1], self.buf[at + 2])

    def deck(self):
        for y in range(self.height):
            for x in range(self.width):
                value = 186 + self.rnd.randint(-22, 22)
                self.put(x, y, (value, value, value))

    def shadow(self):
        """Dappled tree shade: darker, and BLUER, like real open-sky shade."""
        for y in range(self.height):
            for x in range(self.width):
                if math.sin(x * 0.21) + math.cos(y * 0.17) > 0.7:
                    value = 96 + self.rnd.randint(-12, 12)
                    self.put(x, y, (value - 7, value - 2, value + 10))

    def pool(self, box, coping=9):
        left, top, right, bottom = box
        for y in range(top - coping, bottom + coping):
            for x in range(left - coping, right + coping):
                inside = left <= x < right and top <= y < bottom
                self.put(x, y, WATER if inside else BRICK)

    def marker(self, cx, cy, rgb, radius=3.0):
        """An anti-aliased disc, because a real one on screen is."""
        span = int(radius) + 2
        for y in range(cy - span, cy + span + 1):
            for x in range(cx - span, cx + span + 1):
                if not (0 <= x < self.width and 0 <= y < self.height):
                    continue
                away = math.hypot(x - cx, y - cy)
                if away <= radius - 0.5:
                    self.put(x, y, rgb)
                elif away <= radius + 0.5:
                    mix = max(0.0, min(1.0, radius + 0.5 - away))
                    back = self.get(x, y)
                    self.put(x, y, tuple(
                        int(back[i] * (1.0 - mix) + rgb[i] * mix)
                        for i in range(3)))
        self.markers.append((cx, cy))

    def image(self):
        return detect.Image(self.width, self.height, bytes(self.buf))


def reference_scene():
    """The whole fixture: 44 markers ringing a pool, in perimeter order."""
    scene = Scene()
    scene.deck()
    scene.shadow()
    scene.pool((110, 110, 410, 280))
    ring = ([(70 + 30 * i, 60) for i in range(12)] +      # along the top
            [(455, 95 + 25 * i) for i in range(10)] +     # down the right
            [(425 - 30 * i, 350) for i in range(12)] +    # back along the base
            [(45, 320 - 25 * i) for i in range(10)])      # up the left
    reds = {0, 11, 22, 33}
    for index, (x, y) in enumerate(ring):
        scene.marker(x, y, RED if index in reds else
                     (NAVY if index % 3 == 1 else CYAN))
    return scene, ring


# ------------------------------------------------------------------ detect


def test_gap_is_exact_channel_arithmetic():
    """_gap must agree with plain subtraction, for every pair of bytes."""
    values = list(range(0, 256, 7)) + [254, 255]
    hot = bytes(a for a in values for _ in values)
    cold = bytes(b for _ in values for b in values)
    for least in (1, 20, 45, 128, 255):
        bits = detect._gap(hot, cold, least).to_bytes(len(hot), "big")
        want = bytes(1 if hot[i] - cold[i] >= least else 0
                     for i in range(len(hot)))
        assert bits == want, "gap >= %d disagrees with subtraction" % least
    print("ok  _gap matches byte subtraction over %d pairs" % len(hot))


def test_mask_matches_the_obvious_implementation():
    """The big-integer mask must equal the same test written pixel by pixel."""
    rnd = random.Random(5)
    width, height = 64, 48
    raw = bytes(rnd.randrange(256) for _ in range(width * height * 3))
    img = detect.Image(width, height, raw)
    tune = detect.Tuning()
    fast = detect.marker_mask(img, tune)
    slow = bytearray(width * height)
    for i in range(width * height):
        r, g, b = raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2]
        red = (r >= tune.red_min and r - g >= tune.red_gap
               and r - b >= tune.red_gap)
        blue = (b >= tune.blue_min and b - r >= tune.blue_gap
                and not r - g >= tune.blue_green_slack)
        slow[i] = 1 if (red or blue) else 0
    assert fast == bytes(slow), "vectorised mask differs from the plain one"
    assert sum(slow), "the fixture must actually light some pixels"
    print("ok  marker_mask matches a per-pixel implementation")


def test_hue_sat_matches_colorsys():
    rnd = random.Random(9)
    for _ in range(400):
        r, g, b = (rnd.randrange(256) for _ in range(3))
        hue, sat, value = detect.hue_sat(r, g, b)
        want_h, want_s, want_v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0,
                                                     b / 255.0)
        assert abs(sat - want_s) < 1e-9, (r, g, b, sat, want_s)
        assert value == round(want_v * 255), (r, g, b)
        if want_s > 0:
            delta = abs(hue - want_h * 360.0) % 360.0
            assert min(delta, 360.0 - delta) < 1e-6, (r, g, b, hue, want_h)
    print("ok  hue_sat agrees with colorsys on 400 colours")


def test_components_are_eight_connected():
    """Diagonal touching joins; a gap does not; area and centroid are exact."""
    #  X.X      two runs on row 0 that meet nothing
    #  .X.      one run on row 1, diagonally between them -> all one blob
    #  ...
    #  X..      a lone pixel, two rows down -> its own blob
    mask = bytes([1, 0, 1,
                  0, 1, 0,
                  0, 0, 0,
                  1, 0, 0])
    blobs = sorted(detect.components(mask, 3, 4), key=lambda b: -b.area)
    assert len(blobs) == 2, [b.area for b in blobs]
    big, lone = blobs
    assert big.area == 3 and (big.width, big.height) == (3, 2)
    assert big.centroid == (1.0, 1.0 / 3.0), big.centroid
    assert lone.area == 1 and lone.centroid == (0.0, 3.0)
    print("ok  components links diagonals and sums runs exactly")


def test_the_pool_and_the_coping_are_too_big_to_be_dots():
    scene, _ring = reference_scene()
    img = scene.image()
    tune = detect.Tuning()
    blobs = detect.components(detect.marker_mask(img, tune),
                              img.width, img.height)
    huge = [b for b in blobs if b.area > 5000]
    assert huge, "the fixture is meant to contain the water and the coping"
    assert not any(detect.plausible(b, tune) for b in huge), \
        "a blob of thousands of pixels passed the dot filter"
    print("ok  water and coping are found, and rejected on size (%d blobs)"
          % len(huge))


def test_every_marker_is_found_and_nothing_else_is():
    scene, ring = reference_scene()
    dots = detect.find_dots(scene.image())
    found = [d.point for d in dots]
    missed = [p for p in ring
              if not any(abs(p[0] - f[0]) <= 1 and abs(p[1] - f[1]) <= 1
                         for f in found)]
    extra = [f for f in found
             if not any(abs(p[0] - f[0]) <= 1 and abs(p[1] - f[1]) <= 1
                        for p in ring)]
    assert not missed, "missed %d of %d markers: %s" % (len(missed),
                                                        len(ring), missed[:6])
    assert not extra, "invented %d dots: %s" % (len(extra), extra[:6])
    reds = sum(1 for d in dots if d.color == "red")
    assert reds == 4, "expected 4 red targets, classified %d" % reds
    print("ok  all %d markers found, none invented, %d read as red"
          % (len(ring), reds))


def test_colors_can_be_narrowed():
    scene, _ring = reference_scene()
    only_red = detect.find_dots(scene.image(),
                               detect.Tuning(colors=("red",)))
    assert len(only_red) == 4, [d.point for d in only_red]
    assert all(d.color == "red" for d in only_red)
    print("ok  --colors red finds the four targets and nothing else")


def test_merge_close_folds_a_split_marker():
    dots = [detect.Dot(100.0, 50.0, 12, 4, 4, "blue"),
            detect.Dot(102.0, 51.0, 5, 3, 3, "blue"),
            detect.Dot(140.0, 50.0, 9, 4, 4, "red")]
    merged = detect.merge_close(dots, 4.0)
    assert len(merged) == 2, merged
    assert merged[0].area == 12, "the bigger fragment must be the survivor"
    assert detect.merge_close(dots, 0) == dots
    print("ok  merge_close folds a split marker and keeps the larger half")


def test_detection_is_quick_enough_to_wait_for():
    scene, _ring = reference_scene()
    img = scene.image()
    import time
    started = time.monotonic()
    detect.find_dots(img)
    elapsed = time.monotonic() - started
    per_megapixel = elapsed / (img.width * img.height / 1e6)
    assert per_megapixel < 4.0, \
        "%.2fs per megapixel is too slow to sit through" % per_megapixel
    print("ok  detection runs at %.2fs per megapixel" % per_megapixel)


# ---------------------------------------------------------------- ordering


def test_perimeter_walks_the_ring_the_way_the_reference_does():
    scene, ring = reference_scene()
    shuffled = list(ring)
    random.Random(3).shuffle(shuffled)
    walked = ordering.sequence(shuffled, "perimeter")
    assert walked[0] == (70, 60), walked[0]     # the dot nearest the corner
    assert walked[1] == (100, 60), "should set off rightwards along the top"
    assert walked[12] == (455, 95), "then turn down the right-hand side"
    assert walked[22] == (425, 350), "then back along the bottom"
    assert walked[34] == (45, 320), "then up the left, closing the ring"
    assert set(walked) == set(ring), "a point was lost or duplicated"
    assert ordering.walk_length(walked) < 0.2 * ordering.walk_length(shuffled)
    print("ok  perimeter starts top-left, runs clockwise, keeps every point")


def test_perimeter_direction_and_corner_and_start_all_bite():
    scene, ring = reference_scene()
    clockwise = ordering.sequence(ring, "perimeter")
    other_way = ordering.sequence(ring, "perimeter", clockwise=False)
    assert other_way[0] == clockwise[0], "both start at the same corner"
    assert other_way[1] == clockwise[-1], "and then go opposite ways"
    top_right = ordering.sequence(ring, "perimeter", corner="top-right")
    assert top_right[0] == (455, 95), top_right[0]
    chosen = ordering.sequence(ring, "perimeter", start=(310, 60))
    assert chosen[0] == (310, 60), chosen[0]
    assert len(set(chosen)) == len(ring)
    print("ok  direction, corner and an explicit start each move number 1")


def test_reading_and_nearest_orders():
    grid = [(x, y) for y in (10, 13, 60) for x in (100, 40, 70)]
    # y = 10 and y = 13 are three apart, so a six-pixel tolerance reads
    # them as ONE row of six -- which is the whole point of it, because a
    # deck in a photo is never level.
    rows = ordering.sequence(grid, "reading", tolerance=6)
    assert rows[:6] == [(40, 10), (40, 13), (70, 10),
                        (70, 13), (100, 10), (100, 13)], rows[:6]
    assert rows[6:] == [(40, 60), (70, 60), (100, 60)]
    tight = ordering.sequence(grid, "reading", tolerance=1)
    assert tight[:3] == [(40, 10), (70, 10), (100, 10)], tight[:3]
    assert tight[3:6] == [(40, 13), (70, 13), (100, 13)], tight[3:6]
    walk = ordering.sequence(grid, "nearest")
    assert walk[0] == (40, 10)
    assert len(set(walk)) == len(grid)
    assert ordering.walk_length(walk) <= ordering.walk_length(grid)
    print("ok  reading groups rows within tolerance, nearest chains greedily")


def test_ordering_handles_the_degenerate_cases():
    assert ordering.sequence([], "perimeter") == []
    assert ordering.sequence([(4, 4)], "perimeter") == [(4, 4)]
    assert ordering.sequence([(4, 4), (9, 9)], "nearest") == [(4, 4), (9, 9)]
    assert ordering.walk_length([(0, 0)]) == 0
    try:
        ordering.sequence([(1, 1)], "spiral")
    except ValueError as problem:
        assert "spiral" in str(problem)
    else:
        raise AssertionError("an unknown order must not be accepted quietly")
    print("ok  empty, single and unknown orders behave")


# --------------------------------------------------------------- placement


def test_click_first_places_then_confirms():
    plan = placement.Plan([(10, 10), (20, 20), (30, 30)])
    assert plan.enter() == [("click", 10, 10)]
    assert plan.current_placed
    assert plan.progress() == (1, 3)
    assert plan.nudge(2, -1) == [("drag", 10, 10, 12, 9)], "a placed anchor drags"
    assert plan.current == (12, 9)
    assert plan.accept() == [], "already placed -- accepting must not re-click"
    assert plan.progress() == (2, 3)
    assert plan.enter() == [("click", 20, 20)]
    plan.skip()
    assert plan.enter() == [("click", 30, 30)]
    plan.accept()
    assert plan.done
    assert plan.summary() == {"total": 3, "placed": 3, "skipped": 0,
                              "untouched": 0, "stopped": False}
    print("ok  click-first clicks on arrival, drags on a nudge, ends clean")


def test_confirm_first_never_clicks_until_told():
    plan = placement.Plan([(5, 5), (8, 8)], click_first=False)
    assert plan.enter() == [("move", 5, 5)]
    assert not plan.current_placed
    assert plan.nudge(1, 1) == [("move", 6, 6)], "nothing placed, so no drag"
    assert plan.accept() == [("click", 6, 6)], "the click happens on accept"
    plan.enter()
    plan.skip()
    assert plan.done
    tally = plan.summary()
    assert tally["placed"] == 1 and tally["skipped"] == 1, tally
    print("ok  confirm-first moves the pointer and clicks only on accept")


def test_back_reopens_but_does_not_undo():
    plan = placement.Plan([(1, 1), (2, 2)])
    plan.enter()
    plan.accept()
    plan.enter()
    plan.back()
    assert plan.progress() == (1, 2)
    assert plan.current_placed, "going back must not pretend the click undid"
    assert plan.enter() == [("move", 1, 1)], "and must not click it again"
    assert plan.place() == [("click", 1, 1)], "D re-clicks on purpose"
    print("ok  back re-opens the previous anchor without rewriting history")


def test_stop_leaves_the_rest_untouched():
    plan = placement.Plan([(1, 1), (2, 2), (3, 3)])
    plan.enter()
    plan.accept()
    plan.stop()
    assert plan.done and plan.current is None
    assert plan.enter() == [] and plan.nudge(1, 1) == [] and plan.accept() == []
    tally = plan.summary()
    assert tally == {"total": 3, "placed": 1, "skipped": 0, "untouched": 2,
                     "stopped": True}, tally
    plan.back()
    assert not plan.done, "back after a stop must be able to resume"
    print("ok  stop freezes the run and reports what was left")


# ------------------------------------------------------------------ pixmap


def test_png_round_trip_and_the_forms_a_grabber_writes():
    scene, _ring = reference_scene()
    img = scene.image()
    folder = tempfile.mkdtemp(prefix="ariel-test-")
    path = os.path.join(folder, "shot.png")
    try:
        pixmap.write_png(path, img)
        back = pixmap.read_png(path)
        assert (back.width, back.height) == (img.width, img.height)
        assert back.rgb == img.rgb, "a PNG round trip changed the pixels"
        assert detect.find_dots(back) and \
            len(detect.find_dots(back)) == len(detect.find_dots(img))
        assert pixmap.ppm_bytes(img).startswith(
            b"P6\n%d %d\n255\n" % (img.width, img.height))
        assert len(pixmap.ppm_bytes(img)) == len(img.rgb) + 15
    finally:
        for name in os.listdir(folder):
            os.unlink(os.path.join(folder, name))
        os.rmdir(folder)
    print("ok  PNG survives a round trip and PPM is the bytes plus a header")


def test_png_reader_rejects_what_it_cannot_read():
    folder = tempfile.mkdtemp(prefix="ariel-test-")
    path = os.path.join(folder, "not.png")
    try:
        with open(path, "wb") as handle:
            handle.write(b"GIF89a nope")
        try:
            pixmap.read_png(path)
        except ValueError as problem:
            assert "not a PNG" in str(problem)
        else:
            raise AssertionError("a GIF was read as a PNG")
    finally:
        os.unlink(path)
        os.rmdir(folder)
    print("ok  the PNG reader says so when it is handed something else")


def _paeth(left, up, upleft):
    guess = left + up - upleft
    da, db, dc = abs(guess - left), abs(guess - up), abs(guess - upleft)
    if da <= db and da <= dc:
        return left
    return up if db <= dc else upleft


def _encode_png(path, width, height, kind, step, rows, filters):
    """Write a PNG using a chosen row filter, to read back with our reader.

    The writer in pixmap.py only ever emits filter 0, so nothing in this
    repository would otherwise execute the Sub/Up/Average/Paeth branches
    of the reader -- and every PNG that arrives from somewhere else uses
    them.
    """
    stride = width * step
    raw = bytearray()
    for y in range(height):
        line = rows[y * stride:(y + 1) * stride]
        prior = rows[(y - 1) * stride:y * stride] if y else bytes(stride)
        pick = filters[y % len(filters)]
        raw.append(pick)
        for i in range(stride):
            left = line[i - step] if i >= step else 0
            up = prior[i]
            upleft = prior[i - step] if i >= step else 0
            if pick == 0:
                out = line[i]
            elif pick == 1:
                out = line[i] - left
            elif pick == 2:
                out = line[i] - up
            elif pick == 3:
                out = line[i] - ((left + up) >> 1)
            else:
                out = line[i] - _paeth(left, up, upleft)
            raw.append(out & 0xFF)

    def chunk(name, body):
        return (struct.pack(">I", len(body)) + name + body
                + struct.pack(">I", zlib.crc32(name + body) & 0xFFFFFFFF))

    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", struct.pack(">2I5B", width, height, 8,
                                                kind, 0, 0, 0)))
        handle.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        handle.write(chunk(b"IEND", b""))


def test_png_reader_handles_every_row_filter_and_colour_type():
    rnd = random.Random(17)
    width, height = 9, 7
    folder = tempfile.mkdtemp(prefix="ariel-test-")
    try:
        for kind, step in ((2, 3), (6, 4), (0, 1), (4, 2)):
            rows = bytes(rnd.randrange(256)
                         for _ in range(width * height * step))
            path = os.path.join(folder, "k%d.png" % kind)
            _encode_png(path, width, height, kind, step, rows,
                        [0, 1, 2, 3, 4, 3, 1])
            back = pixmap.read_png(path)
            assert (back.width, back.height) == (width, height)
            for y in range(height):
                for x in range(width):
                    at = (y * width + x) * step
                    if kind == 2:
                        want = (rows[at], rows[at + 1], rows[at + 2])
                    elif kind == 6:
                        want = (rows[at], rows[at + 1], rows[at + 2])
                    else:
                        grey = rows[at]
                        want = (grey, grey, grey)
                    assert back.pixel(x, y) == want, \
                        "colour type %d, pixel %d,%d" % (kind, x, y)
            os.unlink(path)
        # 16-bit and interlaced are refused rather than half-read.
        path = os.path.join(folder, "deep.png")
        with open(path, "wb") as handle:
            handle.write(b"\x89PNG\r\n\x1a\n")
            body = struct.pack(">2I5B", 4, 4, 16, 2, 0, 0, 0)
            handle.write(struct.pack(">I", len(body)) + b"IHDR" + body
                         + struct.pack(">I", zlib.crc32(b"IHDR" + body)
                                       & 0xFFFFFFFF))
        try:
            pixmap.read_png(path)
        except ValueError as problem:
            assert "16-bit" in str(problem), problem
        else:
            raise AssertionError("a 16-bit PNG was read as if it were 8-bit")
        os.unlink(path)
    finally:
        for name in os.listdir(folder):
            os.unlink(os.path.join(folder, name))
        os.rmdir(folder)
    print("ok  PNG reader unfilters all five row filters, RGB/RGBA/grey alike")

def test_annotate_marks_every_point():
    img = detect.Image(60, 40, bytes(bytearray(60 * 40 * 3)))
    points = [(15, 12), (40, 28)]
    marked = pixmap.annotate(img, points, {0: "red", 1: "blue"})
    assert (marked.width, marked.height) == (60, 40)
    assert marked.rgb != img.rgb, "nothing was drawn"
    ring = [marked.pixel(15 + 6, 12), marked.pixel(15 - 6, 12)]
    assert all(p != (0, 0, 0) for p in ring), ring
    assert marked.pixel(15, 12) == (0, 0, 0), "the centre must stay visible"
    print("ok  annotate rings and numbers every point without filling it in")


# ----------------------------------------------------------------- the CLI


def test_region_parsing_is_strict():
    assert anchors.parse_region("10,20,300,400") == (10, 20, 300, 400)
    assert anchors.parse_region(" 10 , 20 , 30 , 40 ") == (10, 20, 30, 40)
    for bad in ("10,20,30", "10,20,0,40", "a,b,c,d", "10,20,30,-4"):
        try:
            anchors.parse_region(bad)
        except SystemExit:
            continue
        raise AssertionError("%r should not have parsed" % bad)
    print("ok  --region refuses everything that is not X,Y,W,H")


def test_tuning_follows_the_command_line():
    args = anchors.build_parser().parse_args(
        ["--min-dot", "2", "--blue-gap", "30", "--colors", "blue"])
    tune = anchors.tuning_from(args)
    assert tune.min_size == 2 and tune.blue_gap == 30
    assert tune.colors == ("blue",)
    bad = anchors.build_parser().parse_args(["--colors", "green"])
    try:
        anchors.tuning_from(bad)
    except SystemExit as problem:
        assert "green" in str(problem)
    else:
        raise AssertionError("an unknown colour must not be accepted")
    print("ok  the tuning knobs reach the detector, and a bad colour stops")


def test_offline_run_end_to_end():
    """--from-shot, the whole way through, exactly as a user would."""
    scene, ring = reference_scene()
    folder = tempfile.mkdtemp(prefix="ariel-test-")
    shot = os.path.join(folder, "deck.png")
    drawn = os.path.join(folder, "found.png")
    try:
        pixmap.write_png(shot, scene.image())
        code = anchors.main(["--from-shot", shot, "--annotate", drawn,
                             "--quiet"])
        assert code == 0, "offline run returned %r" % code
        assert os.path.getsize(drawn) > 0
        marked = pixmap.read_png(drawn)
        assert (marked.width, marked.height) == (scene.width, scene.height)
        cropped = anchors.main(["--from-shot", shot, "--quiet",
                                "--region", "0,0,%d,60" % scene.width])
        assert cropped == 0
    finally:
        for name in os.listdir(folder):
            os.unlink(os.path.join(folder, name))
        os.rmdir(folder)
    print("ok  --from-shot detects, orders and annotates a whole photo")


def test_windows_modules_are_not_needed_to_get_here():
    """The point of the split: nothing imported above touches Windows."""
    for name in ("winio", "overlay", "tkinter", "ctypes"):
        assert name not in sys.modules or name == "ctypes", \
            "%s was imported by the parts that must not need it" % name
    assert "winio" not in sys.modules
    print("ok  detection, ordering and the run loop import no Windows")


# ------------------------------------------------------------------- winio
#
# winio.py cannot be imported here -- it refuses to load off Windows on
# purpose -- so it is checked as TEXT.  Both of these catch mistakes that
# produce no error at all on Windows, just wrong behaviour, which is the
# worst possible way for an ABI declaration to be wrong.

WINIO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                     "ariel", "winio.py")

#: What each type is on 64-bit Windows -- NOT what ctypes.wintypes says
#: on this machine, where DWORD is c_ulong and c_ulong is eight bytes.
WIN64 = {"DWORD": 4, "LONG": 4, "WORD": 2, "ULONG_PTR": 8}


def _fields_of(source, name):
    body = source.split("class %s(ctypes.Structure):" % name, 1)[1]
    body = body.split("_fields_ = [", 1)[1].split("]", 1)[0]
    return re.findall(r'\("(\w+)",\s*(?:wintypes\.)?(\w+)\)', body)


def _layout(fields, sizes):
    """(size, {field: offset}) by the C rule: each member on its own
    alignment, the whole padded out to the widest one."""
    offset = 0
    widest = 1
    where = {}
    for name, kind in fields:
        size, align = sizes[kind]
        widest = max(widest, align)
        offset = -(-offset // align) * align
        where[name] = offset
        offset += size
    return -(-offset // widest) * widest, where


#: Size, then every field offset.  Size alone is not enough: padding
#: absorbs a wrong type often enough that a struct can be silently
#: rearranged and still measure right.
WIN64_LAYOUT = {
    "MOUSEINPUT": (32, {"dx": 0, "dy": 4, "mouseData": 8, "dwFlags": 12,
                        "time": 16, "dwExtraInfo": 24}),
    "INPUT": (40, {"type": 0, "mi": 8}),
    "KBDLLHOOKSTRUCT": (24, {"vkCode": 0, "scanCode": 4, "flags": 8,
                             "time": 12, "dwExtraInfo": 16}),
    "BITMAPINFOHEADER": (40, {"biSize": 0, "biWidth": 4, "biHeight": 8,
                              "biPlanes": 12, "biBitCount": 14,
                              "biCompression": 16, "biSizeImage": 20,
                              "biXPelsPerMeter": 24, "biYPelsPerMeter": 28,
                              "biClrUsed": 32, "biClrImportant": 36}),
}


def test_the_windows_structs_have_the_layout_windows_expects():
    """A struct one byte out is a call that fails silently, or worse."""
    source = open(WINIO).read()
    sizes = dict((k, (v, v)) for k, v in WIN64.items())
    for name in ("MOUSEINPUT", "INPUT", "KBDLLHOOKSTRUCT",
                 "BITMAPINFOHEADER"):
        want_size, want_where = WIN64_LAYOUT[name]
        got_size, got_where = _layout(_fields_of(source, name), sizes)
        assert got_size == want_size, \
            "%s is %d bytes, Win64 says %d" % (name, got_size, want_size)
        assert got_where == want_where, \
            "%s fields sit at %s, Win64 puts them at %s" % (name, got_where,
                                                            want_where)
        sizes[name] = (got_size, 8)
    # SendInput is handed sizeof(INPUT) and rejects anything else, so it
    # must be asked rather than typed.
    assert "ctypes.sizeof(INPUT)" in source
    print("ok  four Windows structs match Win64 size AND field offsets")


def test_every_handle_returning_call_declares_its_return_type():
    """ctypes truncates an undeclared return to int, and a handle is 64-bit.

    The symptom is not an exception: it is a device context, bitmap or
    module handle whose top half has been thrown away, used against an
    API that then quietly does nothing.  It happened here -- the hook
    was installed with a truncated GetModuleHandleW.
    """
    source = open(WINIO).read()
    returns_a_handle = (
        "GetDC", "CreateCompatibleDC", "CreateDIBSection", "SelectObject",
        "SetWindowsHookExW", "GetForegroundWindow", "GetModuleHandleW",
        "CallNextHookEx",
    )
    called = set(re.findall(r"(?:user32|gdi32|kernel32)\.(\w+)\(", source))
    declared = set(re.findall(r"(?:user32|gdi32|kernel32)\.(\w+)\.restype",
                              source))
    for name in returns_a_handle:
        assert name in called, "%s is no longer called -- update this list" % name
        assert name in declared, \
            "%s returns a handle and has no restype: it will be truncated" % name
    print("ok  all %d handle-returning calls declare a restype"
          % len(returns_a_handle))


def test_the_hook_keeps_its_callback_alive():
    """A HOOKPROC the garbage collector can reach is a crash in waiting."""
    source = open(WINIO).read()
    assert "self._proc = HOOKPROC(self._callback)" in source
    assert "self._proc = None" in source, "and is dropped on removal"
    assert "return 1" in source, "the hook must swallow what it consumes"
    assert "self.always" in source, \
        "the pause key must be heard while the hook is disarmed"
    print("ok  the keyboard hook holds its callback and swallows its keys")


if __name__ == "__main__":
    test_gap_is_exact_channel_arithmetic()
    test_mask_matches_the_obvious_implementation()
    test_hue_sat_matches_colorsys()
    test_components_are_eight_connected()
    test_the_pool_and_the_coping_are_too_big_to_be_dots()
    test_every_marker_is_found_and_nothing_else_is()
    test_colors_can_be_narrowed()
    test_merge_close_folds_a_split_marker()
    test_detection_is_quick_enough_to_wait_for()
    test_perimeter_walks_the_ring_the_way_the_reference_does()
    test_perimeter_direction_and_corner_and_start_all_bite()
    test_reading_and_nearest_orders()
    test_ordering_handles_the_degenerate_cases()
    test_click_first_places_then_confirms()
    test_confirm_first_never_clicks_until_told()
    test_back_reopens_but_does_not_undo()
    test_stop_leaves_the_rest_untouched()
    test_png_round_trip_and_the_forms_a_grabber_writes()
    test_png_reader_rejects_what_it_cannot_read()
    test_png_reader_handles_every_row_filter_and_colour_type()
    test_annotate_marks_every_point()
    test_region_parsing_is_strict()
    test_tuning_follows_the_command_line()
    test_offline_run_end_to_end()
    test_windows_modules_are_not_needed_to_get_here()
    test_the_windows_structs_have_the_layout_windows_expects()
    test_every_handle_returning_call_declares_its_return_type()
    test_the_hook_keeps_its_callback_alive()
    print("\nall ariel anchor tests passed")
