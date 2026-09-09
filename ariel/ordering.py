# SPDX-License-Identifier: GPL-3.0-or-later
"""Put the detected dots into the order the operator will click them.

Detection finds a set; digitising needs a sequence, and the sequence is
not a detail.  Ariel numbers the anchors in the order they are entered,
those numbers end up on the drawing, and an operator who has to hunt
back and forth across the pool loses exactly the time this program is
meant to save.

Three orders, because no single one is right for every job:

``perimeter``
    Clockwise around the middle of the point set, which is what the
    reference photos show: 1 at the top left, along the top, down the
    right, back along the bottom, up the left.  The dots sit on a deck
    that goes around a pool, so an angular walk IS the walk around the
    pool, and it is the default.

``reading``
    Rows top to bottom, left to right inside a row.  For dots in a grid
    -- a field of pads rather than a perimeter -- an angular sweep
    zigzags and this does not.

``nearest``
    Greedy nearest-neighbour from the start point.  The fallback when a
    shape is too concave for angles to mean anything: never optimal,
    never absurd.

Every one of them can be started from a corner or from a nominated dot,
because which dot is number 1 is the operator's call and the review
window lets them just click it.

Screen coordinates, so y grows DOWNWARD, and clockwise on screen is
therefore INCREASING atan2(dy, dx).  Right, then down, then left, then
up.  Getting that backwards numbers the pool anticlockwise and looks
right until someone reads the drawing.
"""

import math

MODES = ("perimeter", "reading", "nearest")
CORNERS = ("top-left", "top-right", "bottom-right", "bottom-left")


def _corner_point(points, corner):
    """The (x, y) of one corner of the point set's bounding box."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    left, right = min(xs), max(xs)
    top, bottom = min(ys), max(ys)
    return {
        "top-left": (left, top),
        "top-right": (right, top),
        "bottom-right": (right, bottom),
        "bottom-left": (left, bottom),
    }[corner]


def _nearest_index(points, target):
    best = 0
    best_d = None
    for i, (x, y) in enumerate(points):
        d = (x - target[0]) ** 2 + (y - target[1]) ** 2
        if best_d is None or d < best_d:
            best, best_d = i, d
    return best


def _rotate_to(ordered, target):
    """Spin a closed cycle so the point nearest `target` comes first."""
    if not ordered:
        return ordered
    at = _nearest_index(ordered, target)
    return ordered[at:] + ordered[:at]


def perimeter(points, corner="top-left", clockwise=True, start=None):
    """Points sorted by angle about their centroid, then spun to a start.

    Ties -- two dots on the same ray from the centre -- break on radius,
    inner first, so a doubled marker does not shuffle between runs.
    """
    if len(points) < 3:
        return list(points)
    cx = sum(p[0] for p in points) / float(len(points))
    cy = sum(p[1] for p in points) / float(len(points))

    def key(p):
        dx, dy = p[0] - cx, p[1] - cy
        return (math.atan2(dy, dx), dx * dx + dy * dy)

    ordered = sorted(points, key=key)
    if not clockwise:
        ordered.reverse()
    return _rotate_to(ordered, start or _corner_point(points, corner))


def reading(points, tolerance=12.0, corner="top-left", start=None):
    """Rows top to bottom, left to right within a row.

    A row is a run of dots whose y stays within `tolerance` of the row's
    first: a deck is never level in a photo, so a strict sort on y
    interleaves two rows that are three pixels apart.
    """
    if not points:
        return []
    rows = []
    for point in sorted(points, key=lambda p: (p[1], p[0])):
        if rows and abs(point[1] - rows[-1][0][1]) <= tolerance:
            rows[-1].append(point)
        else:
            rows.append([point])
    right_to_left = (corner or "").endswith("right")
    ordered = []
    for row in rows:
        row.sort(key=lambda p: p[0], reverse=right_to_left)
        ordered.extend(row)
    if (corner or "").startswith("bottom"):
        ordered.reverse()
    if start is not None:
        at = _nearest_index(ordered, start)
        ordered = ordered[at:] + ordered[:at]
    return ordered


def nearest(points, corner="top-left", start=None):
    """Greedy nearest-neighbour walk from the start point."""
    remaining = list(points)
    if not remaining:
        return []
    target = start or _corner_point(points, corner)
    ordered = []
    at = remaining.pop(_nearest_index(remaining, target))
    ordered.append(at)
    while remaining:
        at = remaining.pop(_nearest_index(remaining, at))
        ordered.append(at)
    return ordered


def sequence(points, mode="perimeter", corner="top-left", clockwise=True,
             start=None, tolerance=12.0):
    """Order `points` by name.  `start`, when given, beats `corner`."""
    if mode == "perimeter":
        return perimeter(points, corner, clockwise, start)
    if mode == "reading":
        return reading(points, tolerance, corner, start)
    if mode == "nearest":
        return nearest(points, corner, start)
    raise ValueError("unknown order %r, expected one of %s"
                     % (mode, ", ".join(MODES)))


def walk_length(points):
    """Total travel of a sequence -- how the orders are compared."""
    return sum(math.hypot(points[i + 1][0] - points[i][0],
                          points[i + 1][1] - points[i][1])
               for i in range(len(points) - 1))
