# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for perp_points.lsp (PERPPTS) and cperp_points.lsp (CPERPPTS).

Two kinds of check, both runnable without AutoCAD:

* Structural checks read each real .lsp and assert the properties that
  make it safe to run -- balanced parentheses, no variable leaking to
  the global namespace, and every system variable that is changed also
  being saved and restored.
* Geometry checks exercise reference ports of the arc-length sampling
  helpers and of the curve tangent/normal logic, pinning the behaviour
  the LISP is meant to implement.  Keep the ports in step with the LISP
  helpers when either changes.

Usage:  python3 tests/test_perp_points.py
"""

import math
import os
import re

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
LISP_DIR = os.path.join(REPO_DIR, "lisp", "perp_points")
RELEASES_DIR = os.path.join(REPO_DIR, "releases")

# (path, command defun, helper prefix) for each routine under test
ROUTINES = [
    (os.path.join(LISP_DIR, "perp_points.lsp"), "c:PERPPTS", "perp"),
    (os.path.join(LISP_DIR, "cperp_points.lsp"), "c:CPERPPTS", "cperp"),
]

# tutorials get the generic hygiene checks (parens, leaks, sysvars)
# but not the pipeline-specific ones (dim style, output placement)
TUTORIALS = [
    (os.path.join(LISP_DIR, "tutorial_perp_points.lsp"),
     "c:TUTORIALPERPPTS", "tutp"),
    (os.path.join(LISP_DIR, "tutorial_cperp_points.lsp"),
     "c:TUTORIALCPERPPTS", "tutc"),
]

# AutoLISP builtins the "undeclared variable" scan should not flag.
BUILTINS = set("""
defun setq if while foreach cond t nil and or not null car cdr cadr caddr
cons list length nth last reverse distance sqrt abs max min float itoa rtos
strcat princ member equal eq type entsel entget entmake entmod entdel entnext
entlast tblobjname tblsearch trans getvar setvar getint getdist getpoint
getkword initget command exit progn logand zerop subst assoc vl-remove quote
1+ 1- lsh guard getstring vl-catch-all-apply vl-catch-all-error-p
vlax-curve-getEndParam vlax-curve-getDistAtParam vlax-curve-getPointAtDist
vlax-curve-getClosestPointTo vlax-curve-getParamAtPoint
vlax-curve-getParamAtDist vlax-curve-getDistAtPoint vlax-curve-getFirstDeriv
vlax-curve-getStartPoint vlax-curve-getEndPoint
""".split())

KEYWORDS = {"T", "Yes", "No", "Undo", "STR"}

# Version banners: deliberate globals set once at load time and read by
# the load message; tools/release_lisp.py stamps the dated releases/
# twins from them.  Not leaks.
VERSION_GLOBALS = {"*perp-version*", "*cperp-version*",
                   "*tutperp-version*", "*tutcperp-version*"}


def strip_comments(src):
    """Drop ;-comments without being fooled by semicolons inside strings.

    Backslash escapes matter: a LISP string may contain \\" and the
    scanner must not treat that as the end of the string.
    """
    out = []
    for line in src.split("\n"):
        in_string = False
        escaped = False
        kept = ""
        for ch in line:
            if escaped:
                escaped = False
            elif ch == "\\" and in_string:
                escaped = True
            elif ch == '"':
                in_string = not in_string
            elif ch == ";" and not in_string:
                break
            kept += ch
        out.append(kept)
    return "\n".join(out)


def strip_strings(code):
    """Blank out string literals, respecting backslash escapes."""
    out = []
    in_string = False
    escaped = False
    for ch in code:
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
                out.append('""')
            continue
        if ch == '"':
            in_string = True
            continue
        out.append(ch)
    return "".join(out)


# --- structural checks ------------------------------------------------
# Each check runs against every routine in ROUTINES.

def load(path):
    with open(path) as handle:
        return strip_comments(handle.read())


def check_parens_balanced(path, cmd, prefix):
    code = strip_strings(load(path))
    depth = 0
    for ch in code:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            assert depth >= 0, "closing paren with nothing open"
    assert depth == 0, "unbalanced parentheses: depth %d" % depth
    print("  parens balanced")


def check_no_global_leaks(path, cmd, prefix):
    """Every variable used in the command must be declared local.

    An undeclared setq in AutoLISP silently creates a global, which then
    survives between runs and can poison a later invocation.
    """
    code = load(path)
    match = re.search(r"\(defun\s+%s\s*\(([^)]*)\)" % re.escape(cmd), code)
    assert match, "%s not found" % cmd
    declared = set(match.group(1).split("/")[1].split())
    body = strip_strings(code[match.start():])
    called = set(re.findall(r"\(\s*([A-Za-z*][A-Za-z0-9:*_\-]*)", body))
    used = set(re.findall(r"(?<![0-9.])[A-Za-z*][A-Za-z0-9:*_\-]*", body))
    leaked = sorted(
        name for name in used - called
        if name not in declared and name not in BUILTINS
        and name not in KEYWORDS and name not in VERSION_GLOBALS
        and name != cmd
    )
    assert not leaked, "undeclared (global) variables: %s" % leaked
    unused = sorted(
        name for name in declared
        if len(re.findall(r"(?<![A-Za-z0-9:*_\-])%s(?![A-Za-z0-9:*_\-])"
                          % re.escape(name), body)) < 2
    )
    assert not unused, "declared but never used: %s" % unused
    print("  no global leaks, no unused locals (%d declared)" % len(declared))


def check_sysvars_saved_and_restored(path, cmd, prefix):
    """Anything setvar'd must also be read first and restored on cleanup."""
    code = load(path)
    changed = set(re.findall(r'\(setvar\s+"(\w+)"', code))
    saved = set(re.findall(r'\(getvar\s+"(\w+)"', code))
    missing = sorted(changed - saved)
    assert not missing, "changed without saving: %s" % missing
    finish = re.search(r"\(defun\s+%s:finish.*?(?=\n  \(defun|\n  ;; ---)"
                       % re.escape(prefix), code, re.S)
    assert finish, "%s:finish not found" % prefix
    restored = set(re.findall(r'\(setvar\s+"(\w+)"', finish.group(0)))
    missing = sorted(changed - restored)
    assert not missing, "not restored in %s:finish: %s" % (prefix, missing)
    print("  system variables saved and restored: %s" % sorted(changed))


def check_dimension_style_handling(path, cmd, prefix):
    """The dim style is changed by a command, so the setvar scan misses it."""
    code = load(path)
    assert '(getvar "DIMSTYLE")' in code, "current dimension style not saved"
    finish = re.search(r"\(defun\s+%s:finish.*?(?=\n  \(defun)"
                       % re.escape(prefix), code, re.S)
    assert finish and "-DIMSTYLE" in finish.group(0) \
        and "cdim" in finish.group(0), \
        "the current dimension style must be restored on cleanup"
    for name in ('"STANDARD INCHES"', '"SIDE STANDARD"'):
        assert name in code, "missing dimension style choice %s" % name
    assert '(tblsearch "DIMSTYLE" dimStyle)' in code, \
        "must check the style exists before restoring it"
    # dimensions are drawn once, at the end, not per round
    assert code.count("._DIMALIGNED") == 1, \
        "dimensions should be drawn by a single deferred loop"
    print("  dimension style chosen, checked and restored")


def check_output_placement_and_properties(path, cmd, prefix):
    """Polylines inherit the source object's look; dims go on DIMENSIONS."""
    code = load(path)
    # every property copied from the source is applied before PLINE runs
    pline = code.index('(command "._PLINE")')
    setup = code[:pline]
    for var, src in (("CLAYER", "srcLayer"), ("CECOLOR", "srcColor"),
                     ("CELTYPE", "srcLtype"), ("CELWEIGHT", "srcLw"),
                     ("CELTSCALE", "srcLts")):
        assert re.search(r'\(setvar\s+"%s"\s+%s\)' % (var, src), setup), \
            "polyline must inherit %s from the source object" % var
    # the dimension loop runs on the DIMENSIONS layer
    dim = code.index('._DIMALIGNED')
    assert re.search(r'\(setvar\s+"CLAYER"\s+"DIMENSIONS"\)', code[:dim]), \
        "dimensions must be created on the DIMENSIONS layer"
    assert ('(%s:layer "DIMENSIONS"' % prefix) in code, \
        "the DIMENSIONS layer must be created if missing"
    print("  polylines inherit source properties, dims on DIMENSIONS layer")


def check_error_handler_cleans_up(path, cmd, prefix):
    code = load(path)
    handler = re.search(r"\(defun\s+\*error\*.*?\n\n", code, re.S)
    assert handler, "*error* handler not found"
    assert ("%s:finish" % prefix) in handler.group(0), \
        "*error* must route through the shared cleanup"
    assert "_End" in code and "_Begin" in code, \
        "the run must be wrapped in a single UNDO group"
    print("  error handler routes through shared cleanup")


STRUCTURAL_CHECKS = [
    check_parens_balanced,
    check_no_global_leaks,
    check_sysvars_saved_and_restored,
    check_dimension_style_handling,
    check_output_placement_and_properties,
    check_error_handler_cleans_up,
]


HYGIENE_CHECKS = [
    check_parens_balanced,
    check_no_global_leaks,
    check_sysvars_saved_and_restored,
]


def test_structure_of_all_routines():
    for path, cmd, prefix in ROUTINES:
        print("%s:" % os.path.basename(path))
        for check in STRUCTURAL_CHECKS:
            check(path, cmd, prefix)
    for path, cmd, prefix in TUTORIALS:
        print("%s:" % os.path.basename(path))
        for check in HYGIENE_CHECKS:
            check(path, cmd, prefix)


def test_releases_match_their_source():
    """releases/ holds dated copies (NAME_MMDDYY_REV##.lsp);
    the newest release of every lisp/perp_points/*.lsp must be
    byte-identical to it -- the two files stay the same going forward.
    Fix a mismatch by running: python3 tools/release_lisp.py"""
    import glob
    for lsp in sorted(glob.glob(os.path.join(LISP_DIR, "*.lsp"))):
        base = os.path.splitext(os.path.basename(lsp))[0].upper()
        best, best_key = None, None
        for f in os.listdir(RELEASES_DIR):
            m = re.fullmatch(re.escape(base) +
                             r"_(\d{2})(\d{2})(\d{2})_REV(\d+)\.lsp",
                             f, re.IGNORECASE)
            if m:
                mm, dd, yy, rev = (int(g) for g in m.groups())
                key = (yy, mm, dd, rev)
                if best_key is None or key > best_key:
                    best, best_key = f, key
        assert best, "no release found for %s - run tools/release_lisp.py" \
            % os.path.basename(lsp)
        with open(lsp, "rb") as fa, \
             open(os.path.join(RELEASES_DIR, best), "rb") as fb:
            assert fa.read() == fb.read(), \
                "%s differs from its newest release %s - run " \
                "tools/release_lisp.py" % (os.path.basename(lsp), best)
        print("release current: %s == %s" % (os.path.basename(lsp), best))


# --- reference port of the LISP geometry helpers ----------------------

def lerp(a, b, t):
    return [a[i] + t * (b[i] - a[i]) for i in range(3)]


def path_length(points):
    return sum(math.dist(points[i][:3], points[i + 1][:3])
               for i in range(len(points) - 1))


def point_at(points, d):
    if d <= 0.0:
        return points[0]
    i = 0
    while i + 1 < len(points):
        a, b = points[i], points[i + 1]
        seg = math.dist(a[:3], b[:3])
        if d <= seg:
            return lerp(a, b, d / seg if seg > 1e-12 else 0.0)
        d -= seg
        i += 1
    return points[-1]


def sample(points, n):
    total = path_length(points)
    return [point_at(points, (i / (n - 1)) * total if n > 1 else 0.0)
            for i in range(n)]


def dedupe(points):
    out = [points[0]]
    for p in points[1:]:
        if math.dist(p[:3], out[-1][:3]) > 1e-10:
            out.append(p)
    return out


# --- geometry checks --------------------------------------------------

def test_straight_line_spacing():
    pts = sample([[0, 0, 0], [10, 0, 0]], 5)
    assert abs(pts[0][0]) < 1e-9 and abs(pts[-1][0] - 10) < 1e-9, \
        "both endpoints must be included"
    gaps = [math.dist(pts[i][:3], pts[i + 1][:3]) for i in range(4)]
    assert max(gaps) - min(gaps) < 1e-9 and abs(gaps[0] - 2.5) < 1e-9
    print("straight line: equal spacing, endpoints included")


def test_arc_length_spacing_across_a_corner():
    """Repeat rounds sample the jagged polyline by arc length, not chord."""
    poly = [[0, 0, 0], [3, 0, 0], [3, 4, 0]]      # total length 7
    assert abs(path_length(poly) - 7) < 1e-9
    pts = sample(poly, 8)                          # spacing 1.0
    gaps = [math.dist(pts[i][:3], pts[i + 1][:3]) for i in range(7)]
    assert max(abs(g - 1.0) for g in gaps) < 1e-9, "spacing must be uniform"
    assert any(abs(p[0] - 3) < 1e-9 and abs(p[1]) < 1e-9 for p in pts), \
        "a sample should land exactly on the corner"
    assert abs(pts[-1][0] - 3) < 1e-9 and abs(pts[-1][1] - 4) < 1e-9
    print("polyline: uniform arc-length spacing across a corner")


def test_endpoint_never_overshoots():
    poly = [[0, 0, 0], [3, 0, 0], [3, 4, 0]]
    for n in (2, 3, 7, 11, 50, 101):
        last = sample(poly, n)[-1]
        assert abs(last[0] - 3) < 1e-9 and abs(last[1] - 4) < 1e-9, \
            "n=%d overshot the end of the path" % n
    print("endpoint exact for every point count tested")


def test_degenerate_paths():
    zero_seg = sample([[0, 0, 0], [0, 0, 0], [5, 0, 0]], 3)
    assert abs(zero_seg[1][0] - 2.5) < 1e-9 and abs(zero_seg[2][0] - 5) < 1e-9, \
        "a zero-length segment must not break sampling"
    assert len(dedupe([[0, 0, 0], [0, 0, 0], [1, 0, 0],
                       [1, 0, 0], [0, 0, 0]])) == 3
    print("degenerate paths tolerated")


def test_offsets_stay_perpendicular_to_the_original_line():
    """The core invariant: later rounds dimension off the ORIGINAL line.

    Base points move onto a jagged polyline each round, but the offset
    normal is fixed once, so every dimension stays perpendicular to the
    original line and measures exactly the length that was typed.
    """
    ux, uy = 1.0, 0.0                 # original line along +X
    nx, ny = -uy, ux                  # left normal, fixed for the whole run
    jagged = [[0, 3, 0], [4, 5, 0], [9, 2, 0]]   # a round-1 result
    for base in sample(jagged, 4):
        length = 2.0
        new = [base[0] + length * nx, base[1] + length * ny, base[2]]
        vx, vy = new[0] - base[0], new[1] - base[1]
        assert abs(vx * ux + vy * uy) < 1e-12, \
            "offset must be perpendicular to the original line"
        assert abs(math.dist(base[:3], new[:3]) - length) < 1e-12, \
            "dimension must measure the entered length"
    print("offsets stay perpendicular to the original line on repeat rounds")


# --- curve tangent/normal reference (CPERPPTS) ------------------------
# Modelled on a circular arc of radius R about the origin: the closest
# point to any position is its radial projection, and the tangent there
# is the perpendicular of the radius -- so every correct offset must be
# purely radial.  This mirrors cperp:tangent / cperp:normal, which
# project a point onto the original curve and offset along the normal
# of the tangent at the projection.

CURVE_R = 5.0


def curve_tangent(pt):
    a = math.atan2(pt[1], pt[0])          # param of the radial projection
    return (-math.sin(a), math.cos(a))    # CCW first-derivative direction


def curve_normal(pt, side):
    tx, ty = curve_tangent(pt)
    return (side * -ty, side * tx)


def test_curve_side_matches_the_click():
    """The clicked side decides whether offsets go outward or inward."""
    for click, expect_outward in (([7.0, 0.0], True), ([3.0, 0.0], False)):
        a = math.atan2(click[1], click[0])
        proj = [CURVE_R * math.cos(a), CURVE_R * math.sin(a)]
        tx, ty = curve_tangent(click)
        cross = tx * (click[1] - proj[1]) - ty * (click[0] - proj[0])
        side = 1.0 if cross >= 0 else -1.0
        nx, ny = curve_normal(proj, side)
        offset = [proj[0] + nx, proj[1] + ny]
        outward = math.hypot(*offset) > CURVE_R
        assert outward == expect_outward, \
            "offset went to the wrong side for click %s" % click
    print("curve offsets go to the clicked side")


def test_curve_offsets_are_radial():
    """Round 1: every offset from the arc itself must land radially.

    side=-1.0 is the outward side here: on a CCW circle the LEFT of the
    direction of travel (side=+1) faces the centre.
    """
    for a in (0.3, 1.0, 2.0):
        p = [CURVE_R * math.cos(a), CURVE_R * math.sin(a), 0.0]
        nx, ny = curve_normal(p, -1.0)
        new = [p[0] + 2.0 * nx, p[1] + 2.0 * ny]
        assert abs(math.hypot(*new) - (CURVE_R + 2.0)) < 1e-12, \
            "offset from the arc must be radial"
        tx, ty = curve_tangent(p)
        vx, vy = new[0] - p[0], new[1] - p[1]
        assert abs(vx * tx + vy * ty) < 1e-12, \
            "dimension must be perpendicular to the curve tangent"
    print("curve offsets are radial and perpendicular to the tangent")


def test_curve_repeat_rounds_offset_from_the_newest_curve():
    """CPERPPTS repeat rounds work from the NEWEST curve: a round-2 base
    point sits ON the curve round 1 built, and its offset runs along
    THAT curve's normal.  Modelled with concentric circles (a constant
    round-1 offset of a circle is a circle), where the newest curve's
    normal is radial about the same centre -- so the numbers also show
    the rounds chaining consistently outward."""
    for a in (0.3, 1.0, 2.0):
        # round-1 result: circle of radius R+2; the base sits ON it
        base = [(CURVE_R + 2.0) * math.cos(a),
                (CURVE_R + 2.0) * math.sin(a), 0.0]
        # normal of the NEWEST curve under the base (radial for a circle
        # about the same centre, whatever its radius)
        nx, ny = curve_normal(base, -1.0)
        new = [base[0] + 1.5 * nx, base[1] + 1.5 * ny]
        assert abs(math.hypot(*new) - (CURVE_R + 3.5)) < 1e-12, \
            "round-2 offsets must run along the newest curve's normal"
        tx, ty = curve_tangent(base)          # tangent of the newest curve
        vx, vy = new[0] - base[0], new[1] - base[1]
        assert abs(vx * tx + vy * ty) < 1e-12, \
            "round-2 dimension must be perpendicular to the newest curve"
        assert abs(math.dist(base[:3], new[:2] + [0.0]) - 1.5) < 1e-12, \
            "dimension must measure the entered length"
    print("curve repeat rounds offset from the newest curve")


def test_cperppts_uses_newest_curve_and_builds_arc_polylines():
    """Structural pins for the curved-specific behaviours: each round
    samples/offsets from curCrv (the newest curve), and the offset
    points are joined into an LWPOLYLINE whose segments are bulge arcs
    -- built by writing group-42 bulges, never by PEDIT and never as a
    spline."""
    path = os.path.join(LISP_DIR, "cperp_points.lsp")
    code = load(path)
    assert re.search(r"\(cperp:curve-pts\s+curCrv\b", code), \
        "base points must be sampled from the newest curve (curCrv)"
    assert re.search(r"\(cperp:tangent\s+curCrv\b", code), \
        "offset directions must come from the newest curve (curCrv)"
    # the straight polyline is turned into arcs right after it is
    # drawn, and becomes the next round's curve
    pline = code.index('(command "._PLINE")')
    after = code[pline:]
    assert re.search(r"\(cperp:arcs\s+\(entlast\)", after), \
        "the offset polyline must be given arc bulges (cperp:arcs)"
    assert re.search(r"\(setq\s+curCrv\s+\(entlast\)", after), \
        "the arc polyline must become the next round's source"
    # the arcs are written as group-42 bulges via entmod, keeping the
    # entity an LWPOLYLINE
    assert re.search(r"\(cons\s+42\s+b?", code) and "(entmod" in code, \
        "arcs must be written as bulge (42) groups via entmod"
    assert re.search(r'\(setvar\s+"PLINETYPE"\s+2\)', code), \
        "PLINE must be forced to produce a lightweight polyline"
    # never a spline, and never PEDIT (whose Fit turns the entity into
    # a curve-fit heavy polyline that reads as spline-like downstream)
    assert "_Spline" not in code and "._SPLINE" not in code, \
        "output must be a polyline curve, not a spline"
    assert "PEDIT" not in code, \
        "PEDIT must not be used - bulges keep the entity an LWPOLYLINE"
    print("cperppts offsets from the newest curve; output is an arc LWPOLYLINE")


# --- bulge arc reference (CPERPPTS output) ----------------------------

def bulge(tg, a, b):
    """Port of cperp:bulge: tan(alpha/2), alpha = angle tangent->chord."""
    cx, cy = b[0] - a[0], b[1] - a[1]
    if tg is None or math.hypot(cx, cy) < 1e-12:
        return 0.0
    dot = tg[0] * cx + tg[1] * cy
    crs = tg[0] * cy - tg[1] * cx
    alpha = math.atan2(crs, dot)
    alpha = max(-2.98, min(2.98, alpha))
    return math.tan(alpha / 2.0)


def test_bulge_arcs_reproduce_a_circle():
    """Sampling a circle and bulging each segment from the tangent at
    its start must reproduce the circle exactly: bulge == tan(delta/4)
    (the LWPOLYLINE arc convention) and every arc midpoint lies on the
    circle.  A positive bulge is a CCW arc, whose sagitta points to the
    RIGHT of the chord."""
    for npts in (5, 9, 24):
        delta = math.pi / (npts - 1)
        pts = [(CURVE_R * math.cos(i * delta), CURVE_R * math.sin(i * delta))
               for i in range(npts)]
        tgs = [(-math.sin(i * delta), math.cos(i * delta))
               for i in range(npts)]
        for i in range(npts - 1):
            bl = bulge(tgs[i], pts[i], pts[i + 1])
            assert abs(bl - math.tan(delta / 4)) < 1e-12, \
                "bulge must equal tan(included/4)"
            (ax, ay), (bx, by) = pts[i], pts[i + 1]
            cx, cy = bx - ax, by - ay
            clen = math.hypot(cx, cy)
            sag = bl * clen / 2
            arc_mid = ((ax + bx) / 2 + sag * cy / clen,
                       (ay + by) / 2 - sag * cx / clen)
            assert abs(math.hypot(*arc_mid) - CURVE_R) < 1e-9, \
                "every arc must lie exactly on the circle"
    print("bulge arcs reproduce a circle exactly")


def test_bulge_degenerate_cases():
    assert bulge((1, 0), (0, 0), (4, 0)) == 0.0, \
        "tangent parallel to chord must give a straight segment"
    assert bulge(None, (0, 0), (1, 1)) == 0.0, \
        "no tangent must fall back to a straight segment"
    assert bulge((1, 0), (2, 2), (2, 2)) == 0.0, \
        "zero-length chord must give bulge 0"
    assert bulge((0, 1), (0, 0), (0, 5)) == 0.0, \
        "straight travel along +Y must stay straight"
    assert bulge((0.0, -1.0),                       # CW tangent at angle 0
                 (CURVE_R * math.cos(0), CURVE_R * math.sin(0)),
                 (CURVE_R * math.cos(-0.4), CURVE_R * math.sin(-0.4))) < 0, \
        "a clockwise arc must get a negative bulge"
    assert abs(bulge((1, 0), (0, 0), (-5, 1e-6))) < 15, \
        "a folding chord must clamp instead of blowing up"
    print("bulge degenerate cases handled")


def main():
    test_structure_of_all_routines()
    test_releases_match_their_source()
    test_straight_line_spacing()
    test_arc_length_spacing_across_a_corner()
    test_endpoint_never_overshoots()
    test_degenerate_paths()
    test_offsets_stay_perpendicular_to_the_original_line()
    test_curve_side_matches_the_click()
    test_curve_offsets_are_radial()
    test_curve_repeat_rounds_offset_from_the_newest_curve()
    test_cperppts_uses_newest_curve_and_builds_arc_polylines()
    test_bulge_arcs_reproduce_a_circle()
    test_bulge_degenerate_cases()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
