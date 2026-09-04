#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""COVERCHECK's pad hunt must stay in step with PADDLE.

COVERCHECK suggests 36" pads along the pool outline using a port of
PADDLE's concave-feature rules, carried in this repo under the
`cchk:pv-` prefix (COVERCHECK is a standalone file, so it cannot call
PADDLE.lsp - it carries the rules instead).  A port drifts silently:
COVERCHECK once sat on PADDLE's original 1-degree corner tolerance for
several PADDLE revisions, so semi-straight kinks were suggested as pad
spots long after PADDLE had stopped flagging them.

This test makes that drift loud.  Both real .lsp files are loaded into
one lispvm session and the two implementations are run against the same
outlines; every pad - position, kind and count, after the collision
pass - has to agree.  When PADDLE's rules change, port the change into
covercheck.lsp and this test goes green again.

Usage:  python3 tests/test_covercheck_pads.py
"""

import math
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

LISP_ROOT = os.path.join(REPO_DIR, os.environ.get("CALOFIN_LISP_ROOT", "lisp"))
PADDLE = os.path.join(LISP_ROOT, "paddle", "PADDLE.lsp")
COVERCHECK = os.path.join(LISP_ROOT, "covercheck", "covercheck.lsp")
# the shared tier keeps both files flat in parts/, on the cal: library
if os.path.basename(LISP_ROOT) == "shared":
    PARTS = os.path.join(LISP_ROOT, "parts")
    LIB = os.path.join(PARTS, "CALOFIN-LIB.lsp")
    PADDLE = os.path.join(PARTS, "PADDLE.lsp")
    COVERCHECK = os.path.join(PARTS, "covercheck.lsp")
else:
    LIB = None

from lispvm import VM, NIL

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label + (f"  {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def build():
    vm = VM()
    if LIB:
        vm.load(LIB)
    vm.load(PADDLE)
    vm.load(COVERCHECK)
    return vm


def vts_src(vts):
    return "(list " + " ".join(f"(list {x} {y} {b})" for x, y, b in vts) + ")"


def pads(res):
    """(center kind) per pad, rounded so float noise cannot fail a match"""
    if res is NIL or res is None:
        return []
    return [(round(float(p[0][0]), 6), round(float(p[0][1]), 6), str(p[2]))
            for p in res]


def both(vm, vts):
    src = vts_src(vts)
    mine = pads(vm.loads(
        f"(paddle--dodge (paddle--features {src} *paddle-padsize*)"
        f" *paddle-padsize*)"))
    theirs = pads(vm.loads(
        f"(cchk:pv-dodge (cchk:pv-features {src} *cchk-pad-size*)"
        f" *cchk-pad-size*)"))
    return mine, theirs


def arc_wall(sweep_deg, r=50.0, concave=True):
    """a pool with one concave arc of the given total bend in its top wall"""
    sweep = math.radians(sweep_deg)
    b = -math.tan(sweep / 4.0) if concave else math.tan(sweep / 4.0)
    chord = 2 * r * math.sin(sweep / 2.0)
    return [(0, 0, 0), (300, 0, 0), (300, 168, 0),
            (150 + chord / 2.0, 168, b), (150 - chord / 2.0, 168, 0), (0, 168, 0)]


def kink_wall(bend_deg, half=150.0, outward=False):
    """a pool whose bottom wall kinks into the interior by the given bend

    The mid vertex is pushed up into the pool, so the wall's direction
    changes by BEND_DEG at that one point - the joint PADDLE has to
    decide is a corner or just a semi-straight kink.  OUTWARD pushes
    it the other way, making the same bend a convex bump.
    """
    rise = half * math.tan(math.radians(bend_deg) / 2.0)
    if outward:
        rise = -rise
    return [(0, 0, 0), (half, rise, 0), (2 * half, 0, 0),
            (2 * half, 168, 0), (0, 168, 0)]


def clockwise(vts):
    """the same loop traced the other way: bulges flip sign and move to
    the segment's other end"""
    n = len(vts)
    return [(vts[(n - i) % n][0], vts[(n - i) % n][1], -vts[(n - i - 1) % n][2])
            for i in range(n)]


def segmented_wall(per_joint_deg, joints, half=150.0):
    """the bottom wall drawn as JOINTS+1 straight pieces, bending
    PER_JOINT_DEG into the pool at every joint - a faceted curve"""
    dirs = [math.radians(per_joint_deg * (joints / 2.0 - j)) for j in range(joints + 1)]
    piece = (2 * half) / sum(math.cos(d) for d in dirs)
    pts, x, y = [(0.0, 0.0, 0)], 0.0, 0.0
    for d in dirs[:-1]:
        x += piece * math.cos(d)
        y += piece * math.sin(d)
        pts.append((x, y, 0))
    return pts + [(2 * half, 0, 0), (2 * half, 168, 0), (0, 168, 0)]


def fillet_corner(r):
    """an L-shaped pool whose 90-degree inside corner is rounded by a
    tangent concave fillet of radius R - both joints bend 0 degrees"""
    b = -math.tan(math.radians(90) / 4.0)
    return [(0, 0, 0), (240, 0, 0), (240, 120, 0), (120 + r, 120, b),
            (120, 120 + r, 0), (120, 240, 0), (0, 240, 0)]


# outline, and what PADDLE is expected to make of it - the second value
# pins the shared behaviour so a change that breaks BOTH files the same
# way still fails here
SHAPES = [
    ("90-degree inside corner",
     [(0, 0, 0), (240, 0, 0), (240, 120, 0), (120, 120, 0), (120, 240, 0), (0, 240, 0)],
     1),
    ("2-degree kink is semi-straight",
     [(0, 0, 0), (150, 3, 0), (300, 0, 0), (300, 168, 0), (0, 168, 0)],
     0),
    # the corner rule is deliberately blunter than the arc rule: a joint
    # has to bend more than 30 degrees before it is a sharp inside
    # corner, so shallow drafting kinks and segmented walls are left
    # alone (a 12-degree kink used to be padded, and should not be)
    ("12-degree inside kink is semi-straight", kink_wall(12), 0),
    ("29-degree inside kink is semi-straight", kink_wall(29), 0),
    ("31-degree inside kink is a corner", kink_wall(31), 1),
    ("40-degree inside kink is a corner", kink_wall(40), 1),
    ("12-degree kink, loop traced clockwise", clockwise(kink_wall(12)), 0),
    ("40-degree kink, loop traced clockwise", clockwise(kink_wall(40)), 1),
    ("40-degree kink OUT of the pool is convex", kink_wall(40, outward=True), 0),
    # a curve faceted into short straight pieces is judged joint by
    # joint - four pieces at 15 degrees a joint bend 45 in total and
    # get nothing, four at 35 a joint get a pad on every joint
    ("faceted wall, 15 degrees a joint", segmented_wall(15, 3), 0),
    ("faceted wall, 35 degrees a joint", segmented_wall(35, 3), 3),
    # a convex alcove's mouths each bend half its sweep: shallow ones
    # used to be padded at the old 10-degree corner rule
    ("shallow alcove - mouths bend 25 each", arc_wall(50, concave=False), 0),
    ("alcove whose mouths bend exactly 30", arc_wall(60, concave=False), 0),
    ("deeper alcove - mouths bend 35 each", arc_wall(70, concave=False), 2),
    # a tangent fillet's two joints bend 0 degrees: the arc earns its
    # row, the joints never earn a corner pad
    ("tangent R2'-6\" fillet - its row only", fillet_corner(30), 1),
    ("tangent R4'-6\" fillet is inside the cap", fillet_corner(54), 3),
    ("tangent R4'-7\" fillet is over the cap", fillet_corner(55), 0),
    ("8-degree concave arc is semi-straight", arc_wall(8), 0),
    ("12-degree concave arc is a feature", arc_wall(12), 1),
    # an arc bulging OUT of the wall is an alcove: the arc itself is convex
    # and gets nothing, but its two ends are real inside corners
    ("convex arc - only its mouth corners", arc_wall(90, concave=False), 2),
    ("R4'-0\" bite gets a flush row",
     [(0, 0, 0), (300, 0, 0), (300, 168, 0), (264, 168, -1.0), (168, 168, 0), (0, 168, 0)],
     3),
    ("R6'-0\" sweep is over the radius cap",
     [(0, 0, 0), (300, 0, 0), (300, 168, 0), (0, 168, 0), (0, 134, -0.4038), (0, 34, 0)],
     0),
    ("20\" slot - the second pad would collide",
     [(0, 0, 0), (240, 0, 0), (240, 240, 0), (120, 240, 0), (120, 120, 0),
      (100, 120, 0), (100, 240, 0), (0, 240, 0)],
     1),
    ("40\" slot - both corners keep a pad",
     [(0, 0, 0), (240, 0, 0), (240, 240, 0), (140, 240, 0), (140, 120, 0),
      (100, 120, 0), (100, 240, 0), (0, 240, 0)],
     2),
    ("one of everything",
     [(0, 0, 0), (150, 3, 0), (300, 0, 0), (300, 168, 0), (264, 168, -1.0),
      (168, 168, 0), (132, 168, 0), (132, 120, 0), (84, 120, 0), (84, 168, 0),
      (0, 168, 0), (0, 134, -0.4038), (0, 34, 0)],
     5),
    ("the same outline drawn clockwise",
     [(0, 240, 0), (120, 240, 0), (120, 120, 0), (240, 120, 0), (240, 0, 0), (0, 0, 0)],
     1),
]


def main():
    vm = build()
    padsize = float(vm.eval_str("*paddle-padsize*")) if hasattr(vm, "eval_str") \
        else float(vm.loads("*paddle-padsize*"))
    cchk_size = float(vm.loads("*cchk-pad-size*"))
    cchk_rad = float(vm.loads("*cchk-pad-maxrad*"))
    paddle_rad = float(vm.loads("*paddle-maxrad*"))
    cchk_corner = float(vm.loads("*cchk-pad-cornertol*"))
    paddle_corner = float(vm.loads("*paddle-cornertol*"))
    cchk_arc = float(vm.loads("*cchk-pad-arctol*"))
    paddle_arc = float(vm.loads("*paddle-arctol*"))

    print("tunables agree")
    check("pad size (36\")", padsize == cchk_size, f"{padsize} vs {cchk_size}")
    check("radius cap (4'-6\")", paddle_rad == cchk_rad, f"{paddle_rad} vs {cchk_rad}")
    check("corner tolerance (30 deg)",
          abs(paddle_corner - cchk_corner) < 1e-12, f"{paddle_corner} vs {cchk_corner}")
    check("corner tolerance really is 30 degrees",
          abs(math.degrees(paddle_corner) - 30.0) < 1e-9,
          f"{math.degrees(paddle_corner)} deg")
    check("arc tolerance (10 deg)",
          abs(paddle_arc - cchk_arc) < 1e-12, f"{paddle_arc} vs {cchk_arc}")
    check("arc tolerance really is 10 degrees",
          abs(math.degrees(paddle_arc) - 10.0) < 1e-9, f"{math.degrees(paddle_arc)} deg")
    check("a corner is judged harder than an arc", paddle_corner > paddle_arc,
          f"{math.degrees(paddle_corner)} vs {math.degrees(paddle_arc)} deg")

    print("COVERCHECK suggests exactly what PADDLE would")
    for label, vts, expected in SHAPES:
        mine, theirs = both(vm, vts)
        check(label + " - same pads", mine == theirs, f"{mine} vs {theirs}")
        check(label + f" - {expected} pad(s)", len(mine) == expected, f"got {len(mine)}")

    print("suggested pads never overlap")
    for label, vts, _ in SHAPES:
        mine, _ = both(vm, vts)
        clear = all(max(abs(a[0] - b[0]), abs(a[1] - b[1])) >= padsize - 1e-6
                    for i, a in enumerate(mine) for b in mine[i + 1:])
        check(label, clear, str(mine))

    print("tangent joints are never corners")
    for r in (30, 54):
        mine, _ = both(vm, fillet_corner(r))
        check(f"R{r} fillet: arc pads only",
              mine and all(p[2] == "arc" for p in mine), str(mine))

    print("the chain pass strips a doubled vertex before the hunt")
    # a polyline with the kink vertex typed twice: the zero-length
    # segment hides the corner from the raw hunt (no direction out of
    # it), and c:PADDLE never calls the hunt raw - the loop goes
    # through paddle--chain first, which drops the sliver
    doubled = [(0, 0, 0), (150, 50, 0), (150, 50, 0), (300, 0, 0),
               (300, 168, 0), (0, 168, 0)]
    raw, _ = both(vm, doubled)
    check("raw hunt misses it (why the chain pass matters)", raw == [], str(raw))
    loop = vm.loads(f"(car (car (paddle--chain (paddle--vts->segs T {vts_src(doubled)}))))")
    chained = [(float(v[0]), float(v[1]), float(v[2])) for v in loop]
    check("chain drops the sliver", len(chained) == 5, str(chained))
    mine, _ = both(vm, chained)
    check("and the 37-degree corner is padded",
          [(p[0], p[1], p[2]) for p in mine] == [(150.0, 50.0, "corner")], str(mine))

    print("loops that enclose no area are dropped before the hunt")
    flat = [(0, 0, 0), (100, 0, 0)]          # a line and itself back
    lens = [(0, 0, 1.0), (100, 0, 1.0)]      # a circle as two bulged vertices
    raw, _ = both(vm, flat)
    check("a flat loop would have earned a spurious pad", len(raw) == 1, str(raw))
    kept = vm.loads(f"(paddle--solid-loops (list {vts_src(flat)} {vts_src(lens)}))")
    kept = [] if kept is NIL else kept
    check("paddle--solid-loops keeps the lens, drops the flat loop",
          len(kept) == 1 and float(kept[0][0][2]) == 1.0, str(kept))

    print("a convex arc contributes no pads of its own")
    mine, theirs = both(vm, arc_wall(90, concave=False))
    check("no arc-kind pad on a convex arc",
          not [p for p in mine if p[2] == "arc"], str(mine))
    check("its mouth corners are on the arc's ends",
          sorted(round(p[0], 3) for p in mine) == [114.645, 185.355], str(mine))

    print("a pad on a sharp point sits dead on it")
    for label, vts, _ in SHAPES:
        mine, _ = both(vm, vts)
        verts = {(round(float(x), 6), round(float(y), 6)) for x, y, _b in vts}
        onpoint = all((x, y) in verts for x, y, kind in mine if kind == "corner")
        check(label, onpoint, str([p for p in mine if p[2] == "corner"]))

    print()
    if failures:
        print(f"{len(failures)} FAILURE(S): " + ", ".join(failures[:6])
              + (" ..." if len(failures) > 6 else ""))
        raise SystemExit(1)
    print("COVERCHECK's pad hunt matches PADDLE")


if __name__ == "__main__":
    main()
