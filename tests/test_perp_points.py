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
* Runtime checks load the real perp_points.lsp and cperp_points.lsp
  into the repo's AutoLISP interpreter and answer c:PERPPTS and
  c:CPERPPTS from a script, so the prompt sequence and the Back chain
  through it, the width split, the Straight/Arcs/Mixed question, the
  bulges that come out the other end and the boundary in both its
  modes are checked against the files that actually ship.

Usage:  python3 tests/test_perp_points.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import (VM, Ent, Dot, Sym, NIL, LispError,  # noqa: E402
                    BUILTINS as VM_BUILTINS)

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
1+ 1- lsh guard getstring vl-catch-all-apply vl-catch-all-error-p command-s
vlax-curve-getEndParam vlax-curve-getDistAtParam vlax-curve-getPointAtDist
vlax-curve-getClosestPointTo vlax-curve-getParamAtPoint
vlax-curve-getParamAtDist vlax-curve-getDistAtPoint vlax-curve-getFirstDeriv
vlax-curve-getStartPoint vlax-curve-getEndPoint
""".split())

# Bare symbols the code compares against rather than reads as
# variables: the initget answers, the type name, and RETRY - the
# sentinel a question sets to send its chain round again.
KEYWORDS = {"T", "Yes", "No", "Undo", "STR", "RETRY", "PERP-BACK", "CPERP-BACK"}

# Version banners: deliberate globals set once at load time and read by
# the load message; tools/release_lisp.py stamps the dated releases/
# twins from them.  Not leaks.
#
# *calofin-quiet* is the same shape from the other side: the load
# message READS it and never sets it.  LAZPASS.lsp and
# CALOFIN-LOADER.lsp set it while they load their members, so the
# whole build says one line instead of sixty-three; APPLOADed alone it
# is unbound, which is nil, and the banner prints.  This check reads
# from the command's defun to the end of the file, so it sees that
# banner -- which is exactly why the version globals are listed here
# too.
VERSION_GLOBALS = {"*perp-version*", "*cperp-version*",
                   "*tutperp-version*", "*tutcperp-version*",
                   "*calofin-quiet*"}

# Tunables the command body reads directly: set once in the file's
# tunables block (LAZTUNE retunes them per drafter) and only READ here.
# The dimension layer is the one the owner made a knob -- "DIMENSION",
# the name every other tool uses -- in place of the old "DIMENSIONS".
KNOB_GLOBALS = {"perp:*dimlayer*", "cperp:*dimlayer*"}


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
    body = code[match.start():]
    # The self-test table and its registration sit after the command by
    # design (check_lazdiag --fix puts them just above the load banner):
    # the table is data the report evaluates, and *calofin-selftests* is
    # the one global a file writes on purpose.  Neither is a leak of the
    # command's, so the scan stops where that block starts.
    cut = re.search(r"\(defun\s+\S*selftests\s*\(", body)
    if cut:
        body = body[:cut.start()]
    body = strip_strings(body)
    called = set(re.findall(r"\(\s*([A-Za-z*][A-Za-z0-9:*_\-]*)", body))
    used = set(re.findall(r"(?<![0-9.])[A-Za-z*][A-Za-z0-9:*_\-]*", body))
    leaked = sorted(
        name for name in used - called
        if name not in declared and name not in BUILTINS
        and name not in KEYWORDS and name not in VERSION_GLOBALS
        and name not in KNOB_GLOBALS
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
    """Polylines inherit the source object's look; dims go on the
    <prefix>:*dimlayer* knob, which ships as DIMENSION."""
    code = load(path)
    # every property copied from the source is applied before PLINE runs
    pline = code.index('(command "._PLINE")')
    setup = code[:pline]
    for var, src in (("CLAYER", "srcLayer"), ("CECOLOR", "srcColor"),
                     ("CELTYPE", "srcLtype"), ("CELWEIGHT", "srcLw"),
                     ("CELTSCALE", "srcLts")):
        assert re.search(r'\(setvar\s+"%s"\s+%s\)' % (var, src), setup), \
            "polyline must inherit %s from the source object" % var
    # the dimension loop runs on the knob's layer, which ships DIMENSION
    knob = "%s:*dimlayer*" % prefix
    assert re.search(r'\(setq\s+%s\s+"DIMENSION"\)' % re.escape(knob),
                     code), "%s must ship as \"DIMENSION\"" % knob
    dim = code.index('._DIMALIGNED')
    assert re.search(r'\(setvar\s+"CLAYER"\s+%s\)' % re.escape(knob),
                     code[:dim]), \
        "dimensions must be created on the %s layer" % knob
    assert ('(%s:layer %s' % (prefix, knob)) in code, \
        "the dimension layer must be created if missing"
    assert '"DIMENSIONS"' not in code, \
        "no DIMENSIONS layer literal may remain"
    print("  polylines inherit source properties, dims on DIMENSION layer")


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


# --- driving the real command through the AutoLISP VM ------------------
# A structural check cannot see a prompt that is never asked, a loop
# that cannot be left, or a bulge that lands on the wrong segment.
# These runs load the real perp_points.lsp and answer c:PERPPTS from a
# script; the VM validates every scripted keyword against the live
# initget list, so a renamed keyword fails here too.

PERP_LSP = os.path.join(LISP_DIR, "perp_points.lsp")
CPERP_LSP = os.path.join(LISP_DIR, "cperp_points.lsp")

#: a bowed profile with no three consecutive points in a line, so every
#: segment has a curvature to take, symmetric about x = 50
BOW = [10.0, 15.0, 22.0, 15.0, 10.0]
BOW_PTS = [(0.0, 10.0), (25.0, 15.0), (50.0, 22.0), (75.0, 15.0),
           (100.0, 10.0)]

#: clicked well above the line, so the offsets run +y
CLICK = [50.0, 30.0, 0.0]

#: Enter at the width question every round asks of the line it just
#: drew: Unchanged, so the round stands exactly as it was drawn
WIDTH_OK = None


def dxf(data, code):
    for g in data:
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


def poly_verts(vm, e):
    return [(float(g[1]), float(g[2]))
            for g in vm.entdata[e] if isinstance(g, list) and g[0] == 10]


def poly_bulges(vm, e):
    """One bulge per SEGMENT.  The trailing vertex carries a 42 as well,
    and on an open polyline that one belongs to no segment."""
    every = [float(g.b) for g in vm.entdata[e]
             if isinstance(g, Dot) and g.a == 42]
    return every[:max(0, len(poly_verts(vm, e)) - 1)]


#: flip on to rehearse a resize the drawing will not take (a locked,
#: frozen or switched-off layer), which is what perp:rescale reports
SCALE_REFUSES = [False]


def install_entity_builtins():
    """The table call perp_points makes that the shared VM does not
    carry, plus the ActiveX scale behind the width question.  Every
    layer the routine touches is created rather than repaired, so the
    lookup guarding the repair branch finds nothing -- which is also
    what a fresh drawing looks like.  The VM has no ActiveX layer of its
    own (an ename stands in for its VLA object), so vla-ScaleEntity
    moves the entity's own DXF points."""
    VM_BUILTINS[Sym('tblobjname')] = lambda vm, a: NIL
    VM_BUILTINS[Sym('vlax-3d-point')] = lambda vm, a: (
        list(a[0]) if len(a) == 1 else [float(v) for v in a])

    def scale_entity(vm, a):
        if SCALE_REFUSES[0]:
            raise LispError("Automation error: entity is on a locked layer",
                            vm)
        e, ctr, k = a[0], a[1], float(a[2])
        vm.entdata[e] = [
            ([g[0], ctr[0] + k * (g[1] - ctr[0]),
              ctr[1] + k * (g[2] - ctr[1])] + list(g[3:]))
            if isinstance(g, list) and g and g[0] in (10, 11) else g
            for g in vm.entdata[e]]
        return NIL

    VM_BUILTINS[Sym('vla-scaleentity')] = scale_entity


def install_command(vm):
    """PLINE and POINT have to leave entities behind: the routine reaches
    for (entlast) straight after both."""
    pending = {'pts': None}

    def command(vm_, a):
        vm_.commands.append(list(a))
        if a and a[0] == '._PLINE':
            pending['pts'] = []
        elif pending['pts'] is not None and a and isinstance(a[0], list):
            pending['pts'].append([float(v) for v in a[0]])
        elif pending['pts'] is not None:
            pts, pending['pts'] = pending['pts'], None
            e = Ent()
            vm_.entities.append(e)
            # AutoCAD writes a 42 alongside every vertex, so perp:arcs
            # has to replace them rather than add a second set
            vm_.entdata[e] = [
                Dot(0, 'LWPOLYLINE'), Dot(100, 'AcDbPolyline'),
                Dot(8, vm_.sysvars.get('CLAYER', '0')),
                Dot(90, len(pts)), Dot(70, 0),
                Dot(38, pts[0][2] if pts and len(pts[0]) > 2 else 0.0),
            ] + [g for p in pts for g in ([10, p[0], p[1]], Dot(42, 0.0))]
        elif a and a[0] == '._POINT':
            e = Ent()
            vm_.entities.append(e)
            vm_.entdata[e] = [Dot(0, 'POINT'),
                              Dot(8, vm_.sysvars.get('CLAYER', '0')),
                              [10] + [float(v) for v in a[1]]]
        elif a and a[0] == '._-DIMSTYLE' and len(a) >= 3:
            vm_.sysvars['DIMSTYLE'] = a[2]
        elif a and a[0] == '._DIMALIGNED':
            vm_.dims.append([list(p) for p in a[1:]])
        return NIL

    vm.dims = []
    VM_BUILTINS[Sym('command')] = command


def segment_shape(a, b, bulge):
    """(length, point-at-fraction) for one polyline segment."""
    chord = math.dist(a, b)
    if chord < 1e-12:
        return 0.0, lambda t: a
    if abs(bulge) < 1e-15:
        return chord, lambda t: (a[0] + (b[0] - a[0]) * t,
                                 a[1] + (b[1] - a[1]) * t)
    delta = 4.0 * math.atan(bulge)               # included angle, signed
    r = (chord / 2.0) / math.sin(delta / 2.0)    # signed radius
    ux, uy = (b[0] - a[0]) / chord, (b[1] - a[1]) / chord
    mx, my = (a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0
    # a positive bulge travels counter-clockwise, so the centre is to
    # the LEFT of the chord and the arc bows to the right of it
    cx = mx - uy * (r * math.cos(delta / 2.0))
    cy = my + ux * (r * math.cos(delta / 2.0))
    rad = math.hypot(a[0] - cx, a[1] - cy)
    phi = math.atan2(a[1] - cy, a[0] - cx)
    return abs(r * delta), (lambda t: (cx + rad * math.cos(phi + delta * t),
                                       cy + rad * math.sin(phi + delta * t)))


def poly_segments(vm, e):
    """(a, b, length, point-at-fraction, bulge) per segment of an
    LWPOLYLINE, or the one segment of a LINE."""
    if not isinstance(e, Ent) or e not in vm.entdata:
        raise LispError('vlax-curve: not an entity', vm)
    data = vm.entdata[e]
    if dxf(data, 0) == 'LINE':
        a, b = tuple(dxf(data, 10)[:2]), tuple(dxf(data, 11)[:2])
        return [(a, b) + segment_shape(a, b, 0.0) + (0.0,)]
    if dxf(data, 0) != 'LWPOLYLINE':
        raise LispError('vlax-curve: no curve for %s' % dxf(data, 0), vm)
    vs, bs = poly_verts(vm, e), poly_bulges(vm, e)
    return [(vs[i], vs[i + 1]) + segment_shape(vs[i], vs[i + 1], bs[i])
            + (bs[i],)
            for i in range(len(vs) - 1)]


def seg_fraction(a, b, bulge, pt):
    """Where along the segment a-b the point PT sits, 0..1, and how far
    off the segment it is.  An arc reads the angle swept from its start;
    a point outside the arc's sweep is put at the nearer end."""
    chord = math.dist(a, b)
    if chord < 1e-12:
        return 0.0, math.dist(a, pt)
    if abs(bulge) < 1e-15:
        ux, uy = (b[0] - a[0]) / chord, (b[1] - a[1]) / chord
        t = ((pt[0] - a[0]) * ux + (pt[1] - a[1]) * uy) / chord
        t = max(0.0, min(1.0, t))
        q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        return t, math.dist(q, pt)
    delta = 4.0 * math.atan(bulge)
    r = (chord / 2.0) / math.sin(delta / 2.0)
    ux, uy = (b[0] - a[0]) / chord, (b[1] - a[1]) / chord
    mx, my = (a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0
    cx = mx - uy * (r * math.cos(delta / 2.0))
    cy = my + ux * (r * math.cos(delta / 2.0))
    rad = math.hypot(a[0] - cx, a[1] - cy)
    phi = math.atan2(a[1] - cy, a[0] - cx)
    ang = math.atan2(pt[1] - cy, pt[0] - cx)
    rel = ang - phi
    rel = rel % (2 * math.pi) if delta > 0 else -((-rel) % (2 * math.pi))
    t = rel / delta
    if t > 1.0:
        t = 0.0 if math.dist(a, pt) <= math.dist(b, pt) else 1.0
    q = (cx + rad * math.cos(phi + delta * t),
         cy + rad * math.sin(phi + delta * t))
    return t, math.dist(q, pt)


def seg_deriv(a, b, bulge, t):
    """d/dt of the segment's point-at-fraction at T: the chord for a
    straight segment, the swept tangent for an arc."""
    chord = math.dist(a, b)
    if chord < 1e-12:
        return (0.0, 0.0)
    if abs(bulge) < 1e-15:
        return (b[0] - a[0], b[1] - a[1])
    delta = 4.0 * math.atan(bulge)
    r = (chord / 2.0) / math.sin(delta / 2.0)
    ux, uy = (b[0] - a[0]) / chord, (b[1] - a[1]) / chord
    mx, my = (a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0
    cx = mx - uy * (r * math.cos(delta / 2.0))
    cy = my + ux * (r * math.cos(delta / 2.0))
    rad = math.hypot(a[0] - cx, a[1] - cy)
    phi = math.atan2(a[1] - cy, a[0] - cx)
    return (-rad * delta * math.sin(phi + delta * t),
            rad * delta * math.cos(phi + delta * t))


def install_curve_builtins():
    """vlax-curve-* over an LWPOLYLINE that may carry bulges -- what
    perp:ent-pts measures a following round along."""
    def end_param(vm, a):
        return float(len(poly_segments(vm, a[0])))

    def dist_at_param(vm, a):
        total, prm = 0.0, float(a[1])
        for i, seg in enumerate(poly_segments(vm, a[0])):
            if prm >= i + 1:
                total += seg[2]
            elif prm > i:
                total += seg[2] * (prm - i)
        return total

    def point_at_dist(vm, a):
        segs, d = poly_segments(vm, a[0]), float(a[1])
        if not segs:
            return NIL
        if d <= 0:
            return [segs[0][0][0], segs[0][0][1], 0.0]
        for seg in segs:
            if d <= seg[2] + 1e-12:
                p = seg[3](d / seg[2] if seg[2] > 1e-12 else 0.0)
                return [p[0], p[1], 0.0]
            d -= seg[2]
        return [segs[-1][1][0], segs[-1][1][1], 0.0]

    # The parameter is the segment index plus the fraction along it,
    # which is what AutoCAD does for a polyline too; the four calls
    # below are what cperp:tangent turns a point into a direction with.
    def param_at_dist(vm, a):
        segs, d = poly_segments(vm, a[0]), float(a[1])
        if d <= 0:
            return 0.0
        for i, seg in enumerate(segs):
            if d <= seg[2] + 1e-12:
                return i + (d / seg[2] if seg[2] > 1e-12 else 0.0)
            d -= seg[2]
        return float(len(segs))

    def locate(vm, e, p):
        """(segment index, fraction, distance off) of the segment P is
        nearest to."""
        best = None
        for i, seg in enumerate(poly_segments(vm, e)):
            t, off = seg_fraction(seg[0], seg[1], seg[4], (p[0], p[1]))
            if best is None or off < best[2]:
                best = (i, t, off)
        return best

    def param_at_point(vm, a):
        hit = locate(vm, a[0], a[1])
        if hit is None or hit[2] > 1e-6:
            return NIL
        return hit[0] + hit[1]

    def dist_at_point(vm, a):
        hit = locate(vm, a[0], a[1])
        if hit is None or hit[2] > 1e-6:
            return NIL
        segs = poly_segments(vm, a[0])
        return sum(seg[2] for seg in segs[:hit[0]]) + hit[1] * segs[hit[0]][2]

    def first_deriv(vm, a):
        segs, prm = poly_segments(vm, a[0]), float(a[1])
        if not segs:
            return NIL
        i = int(math.floor(prm))
        if i >= len(segs):
            i, t = len(segs) - 1, 1.0
        else:
            t = prm - i
        seg = segs[i]
        d = seg_deriv(seg[0], seg[1], seg[4], t)
        return [d[0], d[1], 0.0]

    VM_BUILTINS[Sym('vlax-curve-getendparam')] = end_param
    VM_BUILTINS[Sym('vlax-curve-getdistatparam')] = dist_at_param
    VM_BUILTINS[Sym('vlax-curve-getpointatdist')] = point_at_dist
    VM_BUILTINS[Sym('vlax-curve-getparamatdist')] = param_at_dist
    VM_BUILTINS[Sym('vlax-curve-getparamatpoint')] = param_at_point
    VM_BUILTINS[Sym('vlax-curve-getdistatpoint')] = dist_at_point
    VM_BUILTINS[Sym('vlax-curve-getfirstderiv')] = first_deriv


def seg_hit(p1, p2, q1, q2):
    """Where segment p1-p2 crosses q1-q2, or None.  Endpoints count as
    crossings, which is what AutoCAD's IntersectWith reports too."""
    rx, ry = p2[0] - p1[0], p2[1] - p1[1]
    sx, sy = q2[0] - q1[0], q2[1] - q1[1]
    den = rx * sy - ry * sx
    if abs(den) < 1e-15:
        return None
    t = ((q1[0] - p1[0]) * sy - (q1[1] - p1[1]) * sx) / den
    u = ((q1[0] - p1[0]) * ry - (q1[1] - p1[1]) * rx) / den
    if -1e-12 <= t <= 1 + 1e-12 and -1e-12 <= u <= 1 + 1e-12:
        return (p1[0] + t * rx, p1[1] + t * ry)
    return None


def install_intersect_builtins():
    """vlax-invoke for the one method cperp:capdist calls: IntersectWith
    between the ray it casts and the boundary, over straight segments.
    AutoCAD answers a FLAT list of x y z per crossing and nil when there
    is none, and capdist reads it as triples, so this does the same."""
    def ent_segs(vm, e):
        return [(seg[0], seg[1]) for seg in poly_segments(vm, e)]

    def invoke(vm, a):
        assert str(a[1]) == 'intersectwith', "unexpected method %r" % (a[1],)
        out = []
        for p1, p2 in ent_segs(vm, a[0]):
            for q1, q2 in ent_segs(vm, a[2]):
                hit = seg_hit(p1, p2, q1, q2)
                if hit is not None:
                    out += [hit[0], hit[1], 0.0]
        return out or NIL

    VM_BUILTINS[Sym('vlax-invoke')] = invoke


def boundary_vm(verts, path=None):
    """A VM holding one of the two routines (cperp_points.lsp unless
    PATH says otherwise) and one open polyline to be the boundary, bound
    in the VM as B (an ename is not a literal a script can be written
    with, and capdist makes entities of its own, so (entlast) would not
    stay pointed at it)."""
    install_entity_builtins()
    install_curve_builtins()
    install_intersect_builtins()
    vm = VM()
    vm.load(path or CPERP_LSP)
    vm.script = []
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'LWPOLYLINE'), Dot(100, 'AcDbPolyline'),
                     Dot(8, '0'), Dot(90, len(verts)), Dot(70, 0),
                     Dot(38, 0.0)] + \
        [g for p in verts for g in ([10, p[0], p[1]], Dot(42, 0.0))]
    vm.loads("(setq B (entlast))")
    # the ray capdist casts goes on the guide layer, which the command
    # itself makes before the first round
    vm.tables['LAYER'].add('PERPPTS-TEMP')
    return vm, e


def make_polyline(vm, verts, bulges=None, layer='0', color=None):
    """One open LWPOLYLINE in the VM, as AutoCAD stores it."""
    e = Ent()
    vm.entities.append(e)
    bulges = list(bulges or [0.0] * len(verts))
    vm.entdata[e] = [Dot(0, 'LWPOLYLINE'), Dot(100, 'AcDbPolyline'),
                     Dot(8, layer)] + ([Dot(62, color)] if color else []) + \
        [Dot(90, len(verts)), Dot(70, 0), Dot(38, 0.0)] + \
        [g for p, b in zip(verts, bulges)
         for g in ([10, p[0], p[1]], Dot(42, b))]
    return e


#: placeholders in a RAW script for the boundary polyline and the
#: selected object, which exist only once the VM is built
BND = object()
SRC = object()


def run_routine(path, cmd, script, width=None, source=None, boundary=None,
                mode=None, bulges=None, raw=False):
    """One scripted run of either routine.  The script starts with the
    direction click; width answers the overall-width question that
    follows it (default Enter, i.e. Unchanged); boundary is a vertex
    list for a polyline to hand the boundary question, whose Enter is
    the default, and mode the Limit/Meet answer after it (default
    Enter, i.e. Limit).  source is a vertex list for a polyline to
    select instead of PERPPTS's line (CPERPPTS always selects a
    polyline; bulges bends it).  The selected object is left on
    vm.source and the boundary on vm.boundary.  Returns the VM and the
    polylines the run drew, in order.  raw hands the script over
    verbatim after the selection, BND and SRC substituted, for a run
    that walks the opening chain itself."""
    install_entity_builtins()
    install_curve_builtins()
    install_intersect_builtins()
    vm = VM()
    install_command(vm)
    vm.load(path)
    if source is None and cmd == 'c:PERPPTS':
        src = Ent()
        vm.entities.append(src)
        vm.entdata[src] = [Dot(0, 'LINE'), Dot(8, 'WALLS'), Dot(62, 3),
                           [10, 0.0, 0.0, 0.0], [11, 100.0, 0.0, 0.0]]
    else:
        src = make_polyline(vm, source or [(0.0, 0.0), (100.0, 0.0)],
                            bulges, 'WALLS', 3)
    vm.source = src
    vm.boundary = make_polyline(vm, boundary) if boundary else None
    vm.tables['LAYER'].add('WALLS')
    vm.tables['DIMSTYLE'].add('STANDARD INCHES')
    if raw:
        answers = [src] + [vm.boundary if a is BND else src if a is SRC else a
                           for a in script]
    else:
        answers = [src, script[0]] + list(width or [None])
        if vm.boundary is not None:
            answers += [vm.boundary] + list(mode or [None])
        else:
            answers += [None]
        answers += list(script[1:])
    vm.run(cmd, answers)
    return vm, [e for e in vm.entities
                if e not in vm.deleted and e is not src
                and e is not vm.boundary
                and dxf(vm.entdata[e], 0) == 'LWPOLYLINE']


def run_perppts(script, **kw):
    return run_routine(PERP_LSP, 'c:PERPPTS', script, **kw)


def run_cperppts(script, **kw):
    return run_routine(CPERP_LSP, 'c:CPERPPTS', script, **kw)


def arrows(vm):
    """The START arrows drawn during the run, oldest first, each as its
    three red guide lines' (start, end) pairs -- the shaft's end is the
    arrow tip, i.e. START as it stood when the arrow was drawn."""
    lines = [e for e in vm.entities
             if dxf(vm.entdata[e], 0) == 'LINE'
             and dxf(vm.entdata[e], 8) == 'PERPPTS-TEMP'
             and dxf(vm.entdata[e], 62) == 1]
    return [[(tuple(dxf(vm.entdata[e], 10)[:2]),
              tuple(dxf(vm.entdata[e], 11)[:2])) for e in lines[i:i + 3]]
            for i in range(0, len(lines), 3)]


def source_ends(vm):
    """The two ends of the object PERPPTS was pointed at, as it stands
    in the drawing after the run."""
    data = vm.entdata[vm.source]
    if dxf(data, 0) == 'LINE':
        return (tuple(dxf(data, 10)[:2]), tuple(dxf(data, 11)[:2]))
    vs = poly_verts(vm, vm.source)
    return (vs[0], vs[-1])


def close(a, b, tol=1e-9):
    return all(abs(x - y) < tol for x, y in zip(a, b))


def test_perppts_asks_how_to_join_the_points():
    vm, pl = run_perppts([CLICK, 5] + BOW + ["Straight", WIDTH_OK, "No",
                                             "STandard"])
    assert len(pl) == 1, "one round draws one polyline, got %d" % len(pl)
    assert poly_verts(vm, pl[0]) == BOW_PTS, poly_verts(vm, pl[0])
    assert poly_bulges(vm, pl[0]) == [0.0] * 4, "Straight must not bulge"
    assert dxf(vm.entdata[pl[0]], 8) == 'WALLS', \
        "the polyline still inherits the source object's layer"
    assert len(vm.dims) == 5, "one dimension per point, got %d" % len(vm.dims)
    print("PERPPTS Straight: every segment a line, source layer kept")

    vm, pl = run_perppts([CLICK, 5] + BOW + ["Arcs", WIDTH_OK, "No",
                                             "STandard"])
    b = poly_bulges(vm, pl[0])
    assert len(b) == 4 and all(abs(x) > 1e-6 for x in b), b
    assert poly_verts(vm, pl[0]) == BOW_PTS, \
        "an arc round must not move the measured points"
    # mirroring the profile reverses travel as well as position, so the
    # mirrored pair of segments carries the same bulge
    assert abs(b[0] - b[3]) < 1e-12 and abs(b[1] - b[2]) < 1e-12, b
    print("PERPPTS Arcs: every segment bulged, points unmoved, fit symmetric")

    # 10/14/18/14/10 puts three points in a line twice over, and no
    # circle passes through those, so a segment with a straight run at
    # both ends stays straight; only the turn is rounded
    vm, pl = run_perppts([CLICK, 5, 10.0, 14.0, 18.0, 14.0, 10.0, "Arcs",
                          WIDTH_OK, "No", "STandard"])
    b = poly_bulges(vm, pl[0])
    assert b[0] == 0.0 and b[3] == 0.0, b
    assert abs(b[1]) > 1e-6 and abs(b[1] - b[2]) < 1e-12, b
    print("PERPPTS Arcs: a straight run stays straight, the turn rounds over")

    # two points make one segment with no neighbour to curve to, so the
    # question is skipped: the script has no answer for it
    vm, pl = run_perppts([CLICK, 2, 10.0, 20.0, WIDTH_OK, "No",
                          "STandard"])
    assert poly_verts(vm, pl[0]) == [(0.0, 10.0), (100.0, 20.0)]
    print("PERPPTS: below three points the join question is not asked")


def test_perppts_mixed_takes_a_segment_list():
    vm, pl = run_perppts([CLICK, 5] + BOW + ["Mixed", "2-3", WIDTH_OK,
                                             "No", "STandard"])
    b = poly_bulges(vm, pl[0])
    assert b[0] == 0.0 and b[3] == 0.0, b
    assert abs(b[1]) > 1e-6 and abs(b[2]) > 1e-6, b
    print("PERPPTS Mixed '2-3': segments 2 and 3 arced, 1 and 4 left straight")

    # out of range, then junk, then Back to the join question itself
    vm, pl = run_perppts([CLICK, 5] + BOW +
                         ["Mixed", "9", "zz", "B", "Straight", WIDTH_OK,
                          "No", "STandard"])
    assert poly_bulges(vm, pl[0]) == [0.0] * 4, poly_bulges(vm, pl[0])
    print("PERPPTS Mixed: a bad list re-asks, B returns to the question")


def test_perppts_rounds_follow_the_curve_they_offset_from():
    # Enter on the second round takes the first round's answer
    vm, pl = run_perppts([CLICK, 3, 10.0, 16.0, 10.0, "Arcs", WIDTH_OK,
                          "Yes", 3, 4.0, 4.0, 4.0, None, WIDTH_OK, "No",
                          "STandard"])
    assert len(pl) == 2, len(pl)
    assert all(abs(x) > 1e-6 for x in poly_bulges(vm, pl[1])), \
        "Enter must repeat the previous round's Arcs"
    print("PERPPTS: Enter reuses the previous round's join answer")

    # after an arc round the next round's base points are spaced along
    # the CURVE, not its chords, so each one lands on the polyline it is
    # dimensioned from -- and the offset is still the fixed +y normal of
    # the original line
    vm, pl = run_perppts([CLICK, 3, 10.0, 16.0, 10.0, "Arcs", WIDTH_OK,
                          "Yes", 3, 4.0, 4.0, 4.0, "Straight", WIDTH_OK,
                          "No", "STandard"])
    segs = poly_segments(vm, pl[0])
    total = sum(seg[2] for seg in segs)
    for i, (x, y) in enumerate(poly_verts(vm, pl[1])):
        d, base = total * i / 2.0, None
        for seg in segs:
            if d <= seg[2] + 1e-12:
                base = seg[3](d / seg[2])
                break
            d -= seg[2]
        assert abs(x - base[0]) < 1e-9, (i, x, base[0])
        assert abs(y - base[1] - 4.0) < 1e-9, (i, y, base[1])
    print("PERPPTS: a round after arcs measures along the curve itself")


def test_perppts_asks_whether_the_overall_width_changed():
    # Enter takes Unchanged: the line stays exactly where it was drawn
    vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"])
    assert source_ends(vm) == ((0.0, 0.0), (100.0, 0.0)), source_ends(vm)
    assert poly_verts(vm, pl[0]) == [(0.0, 10.0), (50.0, 10.0),
                                     (100.0, 10.0)], poly_verts(vm, pl[0])
    print("PERPPTS width: Unchanged leaves the line and the offsets alone")

    # Grew by 20: half at each end, and the drawing is resized with it
    vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"], width=["Grew", 20.0, None])
    assert close(source_ends(vm)[0], (-10.0, 0.0)), source_ends(vm)
    assert close(source_ends(vm)[1], (110.0, 0.0)), source_ends(vm)
    assert [round(x, 9) for x, _ in poly_verts(vm, pl[0])] == \
        [-10.0, 50.0, 110.0], poly_verts(vm, pl[0])
    print("PERPPTS width: Grew adds half the difference at each end")

    # Shrank by 20: half comes off each end
    vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"], width=["Shrank", 20.0, None])
    assert close(source_ends(vm)[0], (10.0, 0.0)), source_ends(vm)
    assert close(source_ends(vm)[1], (90.0, 0.0)), source_ends(vm)
    print("PERPPTS width: Shrank takes half the difference off each end")

    # New gives the width itself, not a difference
    vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"], width=["New", 50.0, None])
    assert close(source_ends(vm)[0], (25.0, 0.0)), source_ends(vm)
    assert close(source_ends(vm)[1], (75.0, 0.0)), source_ends(vm)
    print("PERPPTS width: New is the overall width, not the change")

    # shrinking by the whole width would leave nothing, so it re-asks
    vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"], width=["Shrank", 100.0, 20.0, None])
    assert close(source_ends(vm)[0], (10.0, 0.0)), source_ends(vm)
    print("PERPPTS width: shrinking away the whole width re-asks")


def test_perppts_width_is_measured_across_not_along():
    # A tent: 100 across, but 116.6 of polyline to walk.  Doubling the
    # WIDTH must put the ends 200 apart -- not make the path 200 long.
    tent = [(0.0, 0.0), (50.0, 30.0), (100.0, 0.0)]
    vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"], width=["New", 200.0, None],
                         source=tent)
    ends = source_ends(vm)
    assert close(ends[0], (-50.0, 0.0)) and close(ends[1], (150.0, 0.0)), ends
    assert abs(math.dist(ends[0], ends[1]) - 200.0) < 1e-9, ends
    assert close(poly_verts(vm, vm.source)[1], (50.0, 60.0)), \
        "the shape between the ends is carried along by the same scale"
    print("PERPPTS width: the number is the span end to end, not the path")


def test_perppts_dimensions_follow_the_resized_line():
    vm, pl = run_perppts([CLICK, 3, 10.0, 12.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"], width=["Grew", 20.0, None])
    # every dimension runs from a base point on the resized line to the
    # offset point above it, and the three base points span the new width
    bases = [tuple(d[0][:2]) for d in vm.dims]
    heads = [tuple(d[1][:2]) for d in vm.dims]
    assert [round(x, 9) for x, _ in bases] == [-10.0, 50.0, 110.0], bases
    assert all(abs(y) < 1e-9 for _, y in bases), bases
    for (bx, by), (hx, hy), length in zip(bases, heads, (10.0, 12.0, 10.0)):
        assert abs(bx - hx) < 1e-9 and abs(hy - by - length) < 1e-9, \
            "each dimension still runs the offset length, straight up"
    print("PERPPTS width: the dimensions move with the resized line")


def test_perppts_resizes_the_line_it_just_drew():
    """The width question is asked of EVERY line, not just the selected
    one.  A line PERPPTS draws comes out only as wide as the typed
    offsets add up to, so the course it stands for is re-measured the
    same way the first one was -- and the same correction is applied to
    it: half the difference at each end, about the midpoint of the two.
    """
    # Enter (Unchanged) leaves the round exactly as it drew
    vm, pl = run_perppts([CLICK, 3, 10.0, 12.0, 10.0, "Straight",
                          WIDTH_OK, "No", "STandard"])
    assert poly_verts(vm, pl[0]) == [(0.0, 10.0), (50.0, 12.0),
                                     (100.0, 10.0)], poly_verts(vm, pl[0])
    print("PERPPTS new line: Unchanged leaves the round as it drew")

    # Grew by 20: the polyline just drawn is 100 across (10 up at each
    # end), so 10 goes on at each end and the bow scales with it
    vm, pl = run_perppts([CLICK, 3, 10.0, 12.0, 10.0, "Straight",
                          "Grew", 20.0, None, "No", "STandard"])
    assert [tuple(round(v, 9) for v in p) for p in poly_verts(vm, pl[0])] == \
        [(-10.0, 10.0), (50.0, 12.4), (110.0, 10.0)], poly_verts(vm, pl[0])
    # the line it was offset FROM is untouched: this question is about
    # the course just drawn, and step 2 already had its own
    assert source_ends(vm) == ((0.0, 0.0), (100.0, 0.0)), source_ends(vm)
    said = "".join(vm.printed)
    assert "Overall width of the new polyline, end to end" in said, \
        said[-300:]
    assert "added at each end" in said, said[-300:]
    # and the dimensions are recorded after the correction, so every one
    # of them still ends on the polyline as it now stands
    heads = [tuple(round(v, 9) for v in d[1][:2]) for d in vm.dims]
    assert heads == [tuple(round(v, 9) for v in p)
                     for p in poly_verts(vm, pl[0])], heads
    print("PERPPTS new line: Grew adds half the difference at each end")

    # New is the width itself, and Shrank takes it off
    vm, pl = run_perppts([CLICK, 2, 10.0, 10.0, "New", 50.0, None, "No",
                          "STandard"])
    assert [tuple(round(v, 9) for v in p) for p in poly_verts(vm, pl[0])] == \
        [(25.0, 10.0), (75.0, 10.0)], poly_verts(vm, pl[0])
    vm, pl = run_perppts([CLICK, 2, 10.0, 10.0, "Shrank", 20.0, None, "No",
                          "STandard"])
    assert [tuple(round(v, 9) for v in p) for p in poly_verts(vm, pl[0])] == \
        [(10.0, 10.0), (90.0, 10.0)], poly_verts(vm, pl[0])
    print("PERPPTS new line: New and Shrank read as they do at step 2")


def test_perppts_next_round_measures_the_corrected_line():
    """A corrected line is what the next round is spaced along -- which
    is the whole reason the drawing is resized rather than the number
    just remembered.  Round 1 draws arcs here, so round 2 walks the
    polyline ENTITY (perp:ent-pts) and reads the correction straight out
    of the drawing."""
    vm, pl = run_perppts([CLICK, 3, 10.0, 16.0, 10.0, "Arcs",
                          "Grew", 20.0, None, "Yes",
                          3, 4.0, 4.0, 4.0, "Straight", WIDTH_OK, "No",
                          "STandard"])
    assert len(pl) == 2, len(pl)
    ends = poly_verts(vm, pl[0])
    assert close(ends[0], (-10.0, 10.0)) and close(ends[-1], (110.0, 10.0)), \
        ends
    # round 2's three base points are spaced along the corrected round-1
    # polyline, so the outer two ARE its ends
    bases2 = [tuple(d[0][:2]) for d in vm.dims[3:]]
    assert len(bases2) == 3, bases2
    assert close(bases2[0], ends[0]) and close(bases2[-1], ends[-1]), \
        (bases2, ends)
    # and round 2's own polyline is those bases offset by 4
    for base, pt in zip(bases2, poly_verts(vm, pl[1])):
        assert abs(pt[0] - base[0]) < 1e-9, (pt, base)
        assert abs(pt[1] - base[1] - 4.0) < 1e-9, (pt, base)
    print("PERPPTS: the next round is spaced along the corrected line")


def test_perppts_keeps_going_when_the_new_line_will_not_resize():
    """A refused resize stops step 2, where nothing has been drawn yet.
    At a round it must NOT: rounds of typed lengths sit behind it and
    not one dimension has been written.  The line is left at the width
    it drew, the drafter is told, and because nothing was scaled the
    dimensions still land on it."""
    SCALE_REFUSES[0] = True
    try:
        vm, pl = run_perppts([CLICK, 3, 10.0, 12.0, 10.0, "Straight",
                              "Grew", 20.0, None, "No", "STandard"])
    finally:
        SCALE_REFUSES[0] = False
    assert poly_verts(vm, pl[0]) == [(0.0, 10.0), (50.0, 12.0),
                                     (100.0, 10.0)], poly_verts(vm, pl[0])
    said = "".join(vm.printed)
    assert "could not be resized" in said, said[-300:]
    assert len(vm.dims) == 3, "the run must finish and draw its dimensions"
    heads = [tuple(d[1][:2]) for d in vm.dims]
    assert heads == poly_verts(vm, pl[0]), heads
    print("PERPPTS new line: a refused resize is reported, not fatal")


def test_cperppts_asks_the_same_of_the_curve_it_just_drew():
    """CPERPPTS has no runnable curve layer in the VM (the vlax-curve
    calls its rounds make are AutoCAD's own), so its half of the new
    step is pinned structurally: the question is asked of the curve the
    round built, the drawing is resized, the points in hand are scaled
    with it, and only THEN are the dimensions recorded from them."""
    code = load(CPERP_LSP)
    loop = code[code.index('(setq curCrv (entlast)'):]
    ask = loop.index("(cperp:ask-width")
    assert 'cperp:ask-width "Overall width of the new curve"' in loop, \
        "the round must name the curve it is asking about"
    resize = loop.index("(cperp:rescale curCrv")
    scale = loop.index("(cperp:scale-pts newPts")
    dims = loop.index("(setq dimPairs")
    assert ask < resize < scale < dims, (ask, resize, scale, dims)
    # the width asked about is the span end to end, as at step 2 -- not
    # the length of the curve that was drawn
    assert "(car  (last newPts))" in loop and "(cperp:curvelen" not in \
        loop[:resize], "the width is the distance across, end to end"
    print("cperppts: the curve each round draws is offered the same "
          "correction")


def test_the_boundary_probe_caps_an_offset():
    """The cap is measured per point, along that point's own normal: the
    nearest crossing strictly ahead of the base point.  A boundary that
    the ray never reaches leaves the point with no maximum at all, which
    is how a boundary covering only part of a run behaves.  The probe is
    the same code in both routines, so both are driven."""
    for path, pre in ((CPERP_LSP, "cperp"), (PERP_LSP, "perp")):
        name = os.path.basename(path)
        # a boundary straight across the run, 30 above it
        vm, bnd = boundary_vm([(-100.0, 30.0), (100.0, 30.0)], path)
        got = vm.loads("(%s:capdist B (list 0.0 0.0 0.0) (list 0.0 1.0))"
                       % pre)
        assert got is not None and abs(float(got) - 30.0) < 1e-9, got
        # the same boundary from a point already past it, and from one
        # aiming along it: no crossing ahead, so no maximum
        assert vm.loads("(%s:capdist B (list 0.0 0.0 0.0)"
                        " (list 0.0 -1.0))" % pre) is None, \
            "a boundary behind the offset side must not cap it"
        assert vm.loads("(%s:capdist B (list 0.0 0.0 0.0)"
                        " (list 1.0 0.0))" % pre) is None, \
            "a ray that never reaches the boundary must not cap it"
        # a LINE is a boundary too
        line = Ent()
        vm.entities.append(line)
        vm.entdata[line] = [Dot(0, 'LINE'), Dot(8, '0'),
                            [10, -100.0, 45.0, 0.0], [11, 100.0, 45.0, 0.0]]
        vm.loads("(setq L (entlast))")
        got = vm.loads("(%s:capdist L (list 0.0 0.0 0.0) (list 0.0 1.0))"
                       % pre)
        assert abs(float(got) - 45.0) < 1e-9, got
        print("%s boundary: the crossing ahead of the point is its max"
              % name)

        # slanted: nearer at one end of the run than at the other, which
        # is why one number for the whole run could not say where
        vm, bnd = boundary_vm([(-100.0, 20.0), (100.0, 60.0)], path)
        near = vm.loads("(%s:capdist B (list -50.0 0.0 0.0)"
                        " (list 0.0 1.0))" % pre)
        far = vm.loads("(%s:capdist B (list 50.0 0.0 0.0)"
                       " (list 0.0 1.0))" % pre)
        assert abs(float(near) - 30.0) < 1e-9, near
        assert abs(float(far) - 50.0) < 1e-9, far
        print("%s boundary: a slanted boundary caps each point apart" % name)

        # a boundary the ray crosses twice stops at the FIRST one
        vm, bnd = boundary_vm([(-40.0, 60.0), (0.0, 10.0), (40.0, 60.0)],
                              path)
        got = vm.loads("(%s:capdist B (list 0.0 0.0 0.0) (list 0.0 1.0))"
                       % pre)
        assert abs(float(got) - 10.0) < 1e-9, got
        print("%s boundary: the nearest crossing is the one that caps" % name)

        # the ray is a temporary line and has to leave with the probe: a
        # run casts one per point per round, and a drawing full of them
        # is the drafter's to clean up
        before = [e for e in vm.entities if e not in vm.deleted]
        vm.loads("(%s:capdist B (list 0.0 0.0 0.0) (list 0.0 1.0))" % pre)
        assert [e for e in vm.entities if e not in vm.deleted] == before, \
            "the probe must erase the ray it cast"
        print("%s boundary: the ray it casts leaves with it" % name)


def test_the_boundary_counts_points_carried_past_or_off_it():
    """Every length is capped, or run out to the boundary, as it is
    placed, so a point can only end up past a Limit or off a Meet
    through the width correction.  That is the drafter's own measurement
    and is left alone, but the count is reported -- one helper per
    mode, the same in both routines."""
    for path, pre in ((CPERP_LSP, "cperp"), (PERP_LSP, "perp")):
        name = os.path.basename(path)
        vm, bnd = boundary_vm([(-100.0, 30.0), (100.0, 30.0)], path)
        bases = "(list (list -50.0 0.0 0.0) (list 0.0 0.0 0.0)" \
                " (list 50.0 0.0 0.0))"
        inside = "(list (list -50.0 20.0 0.0) (list 0.0 25.0 0.0)" \
                 " (list 50.0 20.0 0.0))"
        past = "(list (list -50.0 40.0 0.0) (list 0.0 25.0 0.0)" \
               " (list 50.0 40.0 0.0))"
        on = "(list (list -50.0 30.0 0.0) (list 0.0 30.0 0.0)" \
             " (list 50.0 30.0 0.0))"
        assert int(vm.loads("(%s:past-bnd B %s %s)" % (pre, bases, inside))) \
            == 0, "points short of the boundary are not past it"
        assert int(vm.loads("(%s:past-bnd B %s %s)" % (pre, bases, past))) \
            == 2, "both scaled-out points must be counted"
        assert int(vm.loads("(%s:off-bnd B %s)" % (pre, on))) == 0, \
            "points on the boundary are not off it"
        assert int(vm.loads("(%s:off-bnd B %s)" % (pre, past))) == 3, \
            "a point short of the boundary is off it as much as one past"
        assert int(vm.loads("(%s:off-bnd B %s)" % (pre, inside))) == 3
        # off the END of the boundary is off it too
        assert int(vm.loads("(%s:off-bnd B (list (list 130.0 30.0 0.0)))"
                            % pre)) == 1
        print("%s boundary: a width correction past or off it is counted"
              % name)


def test_cperppts_boundary_is_optional_and_wired_through():
    """Structural pins for the parts of the boundary the VM cannot run:
    the question is optional and tells Enter from a missed click, the
    cap is taken from the base point along that point's own normal, Max
    is offered only where there is a cap, and a longer length is brought
    back to it before the point is drawn."""
    for path, prefix, own in ((CPERP_LSP, "cperp", "crv"),
                              (PERP_LSP, "perp", "ent")):
        code = load(path)
        ask = code.index("Select a boundary for the offsets")
        assert '[None] <None>: ' in code[ask:ask + 200], \
            "the boundary question must offer None and default to it"
        assert re.search(r'\(initget "None"\)', code[:ask]), \
            "None has to be an initget keyword for a click on it to work"
        assert "(= 7 (getvar \"ERRNO\"))" in code, \
            "a missed click must be told from Enter, or it drops the boundary"
        # the source object is not a boundary for itself
        assert "(eq (car sel) %s)" % own in code, \
            "picking the object being offset from must be refused"
        # the mode question sits right after it, in the standard's words
        assert '(initget "Limit Meet Back Undo")' in code, \
            "the boundary mode is Limit or Meet, with Back to the selection"
        # the Enter answer is a knob now, so the prompt shows the knob's
        # word and the null answer is filled from the same local -- and
        # the shipped word is still Limit, so Enter still means Limit
        assert '[Limit/Meet/Back] <" bdflt ">: ' in code, \
            "the prompt must show the boundary knob's word as its default"
        assert "(if (null bmode) (setq bmode bdflt))" in code, \
            "Enter must be filled from the same word the prompt showed"
        assert re.search(r'\(setq %s:\*bound(?:ary)?-default\* "Limit"\)'
                         % prefix, code), \
            "the boundary knob must still ship Limit"
        loop = code[code.index("(setq newPts '()"):]
        cap = loop.index("(%s:capdist bnd base" % prefix)
        ask2 = loop.index("(%s:ask-len" % prefix)
        draw = loop[ask2:].index("(setq np (list") + ask2
        assert cap < ask2 < draw, (cap, ask2, draw)
        assert '(if cap "Back Undo Max" "Back Undo")' in loop, \
            "Max is only an answer where there is a boundary ahead"
        clip = loop.index("(setq len cap)")
        assert ask2 < clip < draw, \
            "a length past the boundary must be brought back before it draws"
        assert 'boundary at ' in loop[:ask2 + 600], \
            "the prompt must name the distance to the boundary"
        # Meet places the point before any length prompt is reached
        meet = loop.index('(and cap (equal bmode "Meet"))')
        assert meet < ask2, "Meet must place the point without asking"
        assert "(no boundary ahead)" in loop[:ask2 + 600], \
            "Meet says when a point has no boundary to run out to"
        print("%s boundary: optional, per point, Limit or Meet, capped "
              "before it draws" % os.path.basename(path))


def test_scale_pts_moves_points_with_the_resized_object():
    """The points in hand are scaled by the same centre and factor the
    drawing was, so the dimensions recorded from them land on the object
    as it now stands rather than where it was drawn."""
    for path, prefix in ((PERP_LSP, "perp"), (CPERP_LSP, "cperp")):
        vm = VM()
        vm.load(path)
        vm.script = []
        got = vm.loads(
            "(%s:scale-pts (list (list 0.0 10.0 3.0) (list 50.0 12.0 3.0)"
            " (list 100.0 10.0 3.0)) (list 50.0 10.0 3.0) 1.2)" % prefix)
        got = [[float(v) for v in p] for p in got]
        assert close(got[0], (-10.0, 10.0, 3.0)), got
        assert close(got[1], (50.0, 12.4, 3.0)), got
        assert close(got[2], (110.0, 10.0, 3.0)), got
        assert all(p[2] == 3.0 for p in got), "z is carried through untouched"
        print("%s: scale-pts moves the points with the drawing"
              % os.path.basename(path))


def test_perppts_says_so_when_the_drawing_refuses_the_resize():
    SCALE_REFUSES[0] = True
    try:
        raised = None
        try:
            run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", "No",
                         "STandard"], width=["Grew", 20.0, None])
        except LispError as err:
            raised = err
        assert raised is not None, \
            "a resize the drawing will not take must stop the command"
    finally:
        SCALE_REFUSES[0] = False
    print("PERPPTS width: a refused resize stops rather than mismeasures")


# The width question and the resize behind it are the same code in both
# routines, so both are driven here rather than only through the PERPPTS
# runs above.

def ask_width(path, prefix, drawn, answers, back=False):
    """<prefix>:ask-width against one scripted set of answers.  Returns
    (width, START's share of the change), None for "unchanged", or the
    string BACK when the first question was answered Back."""
    vm = VM()
    vm.load(path)
    vm.script, vm.prompts = list(answers), []
    got = vm.loads('(%s:ask-width "Overall width" %r %s)'
                   % (prefix, drawn, "T" if back else "nil"))
    assert not vm.script, "answers left over: %r" % vm.script
    if got is None:
        return None
    if isinstance(got, Sym):
        return "BACK"
    return (float(got[0]), float(got[1]))


def test_the_width_question_reads_the_same_in_both_routines():
    for path, prefix in ((PERP_LSP, "perp"), (CPERP_LSP, "cperp")):
        name, ask = os.path.basename(path), \
            lambda answers: ask_width(path, prefix, 100.0, answers)
        assert ask([None]) is None, "%s: Enter must mean Unchanged" % name
        assert ask(["Unchanged"]) is None, name
        # Enter at the split is Yes: half at each end
        assert ask(["Grew", 20.0, None]) == (120.0, 0.5), name
        assert ask(["Grew", 20.0, "Yes"]) == (120.0, 0.5), name
        assert ask(["G", 20.0, "Y"]) == (120.0, 0.5), \
            "%s: the hotkeys must work" % name
        assert ask(["Shrank", 20.0, None]) == (80.0, 0.5), name
        assert ask(["New", 50.0, None]) == (50.0, 0.5), \
            "%s: New is the width itself, not a difference" % name
        # Enter at New, or typing the width already drawn, is no change
        # -- and then there is nothing to split, so nothing is asked
        assert ask(["New", None]) is None, name
        assert ask(["New", 100.0]) is None, name
        # shrinking by the whole width or more re-asks instead of
        # turning the line inside out
        assert ask(["Shrank", 120.0, 100.0, 20.0, None]) == (80.0, 0.5), name
        print("%s: width question reads Grew/Shrank/New/Unchanged" % name)


def test_the_width_change_can_be_shared_unevenly():
    """No at the split asks how much of the change is at START; the rest
    is FINISH's.  Zero and the whole amount are both answers, more than
    the whole is refused and re-asked, and the share comes back as a
    fraction the resize scales about."""
    for path, prefix in ((PERP_LSP, "perp"), (CPERP_LSP, "cperp")):
        name, ask = os.path.basename(path), \
            lambda answers: ask_width(path, prefix, 100.0, answers)
        got = ask(["Grew", 20.0, "No", 5.0])
        assert got == (120.0, 0.25), (name, got)
        assert ask(["Grew", 20.0, "No", 0.0]) == (120.0, 0.0), \
            "%s: zero at START puts all of it at FINISH" % name
        assert ask(["Grew", 20.0, "No", 20.0]) == (120.0, 1.0), \
            "%s: the whole amount at START holds FINISH still" % name
        # shrinking shares out the same way: 5 of the 20 comes off START
        assert ask(["Shrank", 20.0, "No", 5.0]) == (80.0, 0.25), name
        # New is a difference too once the width is known: 100 -> 50 is
        # 50 off, 10 of it at START
        assert ask(["New", 50.0, "No", 10.0]) == (50.0, 0.2), name
        # more than the whole change would move FINISH the other way
        vm = VM()
        vm.load(path)
        vm.script, vm.prompts = ["Grew", 20.0, "No", 30.0, 5.0], []
        got = vm.loads('(%s:ask-width "Overall width" 100.0 nil)' % prefix)
        assert (float(got[0]), float(got[1])) == (120.0, 0.25), got
        said = "".join(vm.printed)
        assert "more than the whole" in said, said
        assert "The other 15.0000 goes at the FINISH end" in said, said
        asked = [p for p, _v in vm.prompts if "at the START end" in p]
        assert len(asked) == 2, "an amount over the whole must re-ask"
        print("%s: the change is shared out as asked" % name)


def test_the_width_chain_walks_back():
    """Back at each of the four questions re-asks the one before it,
    and Back at the first hands the caller its sentinel -- but only when
    the caller said there is somewhere to go."""
    for path, prefix in ((PERP_LSP, "perp"), (CPERP_LSP, "cperp")):
        name = os.path.basename(path)

        def run(answers, back=False):
            vm = VM()
            vm.load(path)
            vm.script, vm.prompts = list(answers), []
            got = vm.loads('(%s:ask-width "Overall width" 100.0 %s)'
                           % (prefix, "T" if back else "nil"))
            assert not vm.script, "answers left over: %r" % vm.script
            return got, [p for p, _v in vm.prompts]

        # START amount -> split -> amount -> kind
        got, asked = run(["Grew", "Back", "Grew", 20.0, "No", "Back", "No",
                          "B", "U", 20.0, "No", 5.0])
        assert (float(got[0]), float(got[1])) == (120.0, 0.25), got
        assert sum("Has that width changed" in p for p in asked) == 2, asked
        assert sum("How much wider" in p for p in asked) == 3, asked
        assert sum("Split the" in p for p in asked) == 4, asked
        assert sum("at the START end" in p for p in asked) == 3, asked
        # without a caller to go back to, the first question offers no
        # Back at all -- the keyword is not in its list
        got, asked = run([None])
        assert "/Back]" not in asked[0], asked[0]
        # with one, Back there is the sentinel
        got, asked = run(["Back"], back=True)
        assert isinstance(got, Sym) and "BACK" in str(got).upper(), got
        assert "[Grew/Shrank/New/Unchanged/Back] <Unchanged>" in asked[0], \
            asked[0]
        # U is NOT Back at this one prompt: Unchanged is listed first and
        # its hotkey is U, and a hidden synonym never steals a canonical
        # option's hotkey (STANDARDS 1 rule 3) -- so U is Unchanged, and
        # Undo is typed in full
        got, asked = run(["U"], back=True)
        assert got is None, "U at the width question is Unchanged"
        got, asked = run(["Undo"], back=True)
        assert isinstance(got, Sym), "Undo typed in full is Back"
        print("%s: the width chain walks back" % name)


def test_scale_centre_shares_the_change_out():
    """The resize is one scale about a point on the line through the
    ends; where that point sits is what shares the change out.  frac is
    START's share: 0.5 is the midpoint, 0 holds START still, 1 holds
    FINISH still, and any other value lands in proportion."""
    for path, prefix in ((PERP_LSP, "perp"), (CPERP_LSP, "cperp")):
        vm = VM()
        vm.load(path)
        vm.script = []
        ps, pf = "(list 0.0 0.0 2.0)", "(list 100.0 0.0 2.0)"
        for frac, want in ((0.5, (50.0, 0.0, 2.0)), (0.0, (0.0, 0.0, 2.0)),
                           (1.0, (100.0, 0.0, 2.0)), (0.25, (25.0, 0.0, 2.0))):
            got = vm.loads("(%s:scale-ctr %s %s %r)" % (prefix, ps, pf, frac))
            assert close([float(v) for v in got], want), (frac, got)
        # scaling the ends about that centre by wNew/wOld moves START by
        # frac of the change and FINISH by the rest, whichever way the
        # line runs and whether it grows or shrinks
        for frac, wnew, want_s, want_f in (
                (0.25, 120.0, -5.0, 115.0), (0.0, 120.0, 0.0, 120.0),
                (1.0, 120.0, -20.0, 100.0), (0.25, 80.0, 5.0, 85.0),
                (0.5, 80.0, 10.0, 90.0)):
            ctr = vm.loads("(%s:scale-ctr %s %s %r)" % (prefix, ps, pf, frac))
            k = wnew / 100.0
            s = vm.loads("(%s:scale-pt %s (list %r %r %r) %r)"
                         % (prefix, ps, ctr[0], ctr[1], ctr[2], k))
            f = vm.loads("(%s:scale-pt %s (list %r %r %r) %r)"
                         % (prefix, pf, ctr[0], ctr[1], ctr[2], k))
            assert abs(float(s[0]) - want_s) < 1e-9, (frac, wnew, s)
            assert abs(float(f[0]) - want_f) < 1e-9, (frac, wnew, f)
        # and the line that reports it names each end when they differ
        line = vm.loads('(%s:width-line 100.0 120.0 0.5)' % prefix)
        assert "10.0000 added at each end" in line, line
        line = vm.loads('(%s:width-line 100.0 120.0 0.25)' % prefix)
        assert "5.0000 added at the START end, 15.0000 at the FINISH end" \
            in line, line
        line = vm.loads('(%s:width-line 100.0 80.0 0.0)' % prefix)
        assert "0.0000 taken off at the START end, 20.0000 at the FINISH" \
            in line, line
        print("%s: the scale centre shares the change out"
              % os.path.basename(path))


def test_rescale_says_whether_the_drawing_took_it():
    for path, prefix in ((PERP_LSP, "perp"), (CPERP_LSP, "cperp")):
        install_entity_builtins()
        vm = VM()
        vm.load(path)
        vm.script = []
        line = Ent()
        vm.entities.append(line)
        vm.entdata[line] = [Dot(0, 'LINE'), Dot(8, '0'),
                            [10, 0.0, 0.0, 0.0], [11, 100.0, 0.0, 0.0]]
        call = "(%s:rescale (entlast) (list 50.0 0.0 0.0) 1.2)" % prefix
        assert vm.loads(call) is not None, "a scale that works reports T"
        assert close(dxf(vm.entdata[line], 10)[:2], (-10.0, 0.0)), \
            "half the difference at the near end"
        assert close(dxf(vm.entdata[line], 11)[:2], (110.0, 0.0)), \
            "half the difference at the far end"
        SCALE_REFUSES[0] = True
        try:
            refused = vm.loads(call)
        finally:
            SCALE_REFUSES[0] = False
        assert refused is None, \
            "a resize the drawing refuses must report nil, not raise"
        print("%s: rescale reports whether the drawing took the resize"
              % os.path.basename(path))


# --- the opening chain, the split and the boundary, driven ------------

#: clicked near the RIGHT end, above: START is (100, 0)
CLICK_RIGHT = [95.0, 30.0, 0.0]

#: boundaries, as vertex lists for a polyline
FLAT = [(-100.0, 30.0), (200.0, 30.0)]       # straight across, 30 above
SLANT = [(-100.0, 20.0), (100.0, 60.0)]      # 40 above x=0, 50 at 50, 60 at 100
PART = [(30.0, 30.0), (70.0, 30.0)]          # covers the middle of the run only
BENT = [(-100.0, 30.0), (50.0, 30.0), (100.0, 80.0)]   # turns up at x=50
DIP = [(-100.0, 30.0), (50.0, 30.0), (100.0, -20.0)]   # drops toward FINISH


def prompts_of(vm):
    return [p for p, _v in vm.prompts]


def said(vm):
    return "".join(vm.printed)


def rounded(pts):
    return [tuple(round(v, 9) for v in p) for p in pts]


def test_perppts_opening_chain_walks_back():
    """Select, click, width: Back at the click re-opens the selection,
    Back at the width question re-opens the click, and the arrow that
    marks START goes with the click and comes back with it."""
    vm, pl = run_perppts(["Back", SRC, CLICK, None, None, 2, 10.0, 10.0,
                          WIDTH_OK, "No", "STandard"], raw=True)
    asked = prompts_of(vm)
    assert sum("Select a line or polyline" in p for p in asked) == 2, asked
    assert asked[1] == "\nClick to pick direction / offset side [Back]: ", \
        asked[1]
    assert "Stepping back one question" in said(vm)
    assert poly_verts(vm, pl[0]) == [(0.0, 10.0), (100.0, 10.0)]
    print("PERPPTS chain: Back at the click re-opens the selection")

    vm, pl = run_perppts([CLICK, "Back", CLICK, None, None, 2, 10.0, 10.0,
                          WIDTH_OK, "No", "STandard"], raw=True)
    asked = prompts_of(vm)
    assert sum("Click to pick direction" in p for p in asked) == 2, asked
    # twice at the opening, once for the line the round drew
    assert sum("Has that width changed" in p for p in asked) == 3, asked
    assert asked[2].endswith("[Grew/Shrank/New/Unchanged/Back] <Unchanged>: ")
    assert len(arrows(vm)) == 2, "the arrow goes with the click and returns"
    print("PERPPTS chain: Back at the width re-opens the click")

    # B is Back there too (U is Unchanged's hotkey at that prompt), and
    # the second click is the one that counts: near the right end, so
    # START is (100, 0) and the first length lands there
    vm, pl = run_perppts([CLICK, "B", CLICK_RIGHT, None, None, 2, 10.0,
                          12.0, WIDTH_OK, "No", "STandard"], raw=True)
    assert poly_verts(vm, pl[0]) == [(100.0, 10.0), (0.0, 12.0)], \
        poly_verts(vm, pl[0])
    assert close(arrows(vm)[-1][0][1], (100.0, 0.0)), arrows(vm)[-1]
    print("PERPPTS chain: B is Back, and the last click is the one kept")


def test_perppts_arrow_marks_start_and_follows_the_resize():
    """The shaft of the red arrow ends on START.  A resize moves START,
    so the arrow is drawn again where START now is -- it is what the
    width question means by 'the arrowed end'."""
    vm, pl = run_perppts([CLICK, 2, 10.0, 10.0, WIDTH_OK, "No", "STandard"],
                         width=["Grew", 20.0, "No", 5.0])
    ar = arrows(vm)
    assert len(ar) == 2, len(ar)
    assert close(ar[0][0][1], (0.0, 0.0)), ar[0]
    assert close(ar[1][0][1], (-5.0, 0.0)), ar[1]
    assert ar[1][0][0][0] < -5.0, "the shaft comes in from outside the line"
    # every guide is gone at the end, arrows included
    for e in vm.entities:
        if dxf(vm.entdata[e], 8) == 'PERPPTS-TEMP':
            assert e in vm.deleted, "a guide left standing"
    # an unchanged width leaves the one arrow
    vm, pl = run_perppts([CLICK, 2, 10.0, 10.0, WIDTH_OK, "No", "STandard"])
    assert len(arrows(vm)) == 1
    print("PERPPTS: the arrow marks START and follows the resize")


def test_perppts_shares_the_width_change_as_asked():
    """No at the split: the START end -- nearest the click, the arrowed
    one -- moves by the amount given and FINISH by the rest, growing or
    shrinking, and the base points follow the resized line."""
    cases = [
        (["Grew", 20.0, "No", 5.0], (-5.0, 115.0)),
        (["Grew", 20.0, "No", 0.0], (0.0, 120.0)),
        (["Grew", 20.0, "No", 20.0], (-20.0, 100.0)),
        (["Shrank", 20.0, "No", 5.0], (5.0, 85.0)),
        (["New", 50.0, "No", 10.0], (10.0, 60.0)),
        (["Grew", 20.0, "No", 30.0, 5.0], (-5.0, 115.0)),   # over: re-asked
        (["Grew", 20.0, "No", "Back", "Yes"], (-10.0, 110.0)),
    ]
    for width, (xs, xf) in cases:
        vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight",
                              WIDTH_OK, "No", "STandard"], width=width)
        ends = source_ends(vm)
        assert close(ends[0], (xs, 0.0)) and close(ends[1], (xf, 0.0)), \
            (width, ends)
        bases = sorted(round(d[0][0], 9) for d in vm.dims)
        assert bases == [xs, round((xs + xf) / 2.0, 9), xf], (width, bases)
        assert [round(p[1], 9) for p in poly_verts(vm, pl[0])] == [10.0] * 3
    print("PERPPTS split: START moves by the amount given, FINISH by the rest")

    # START is the end nearest the click: click near the right end and
    # the 5 goes on there
    vm, pl = run_perppts([CLICK_RIGHT, 3, 10.0, 10.0, 10.0, "Straight",
                          WIDTH_OK, "No", "STandard"],
                         width=["Grew", 20.0, "No", 5.0])
    ends = source_ends(vm)
    assert close(ends[0], (-15.0, 0.0)) and close(ends[1], (105.0, 0.0)), ends
    assert "5.0000 added at the START end, 15.0000 at the FINISH end" \
        in said(vm), said(vm)[-400:]
    assert "The other 15.0000 goes at the FINISH end" in said(vm)
    print("PERPPTS split: START is the arrowed end, whichever end that is")

    # the shape between the ends is carried along whatever the split:
    # a tent held at START keeps its apex over the same fraction
    tent = [(0.0, 0.0), (50.0, 30.0), (100.0, 0.0)]
    vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"], width=["Grew", 20.0, "No", 0.0],
                         source=tent)
    vs = poly_verts(vm, vm.source)
    assert close(vs[0], (0.0, 0.0)) and close(vs[2], (120.0, 0.0)), vs
    assert close(vs[1], (60.0, 36.0)), vs
    # and an even split is still exactly half at each end
    vm, pl = run_perppts([CLICK, 3, 10.0, 10.0, 10.0, "Straight", WIDTH_OK,
                          "No", "STandard"], width=["Grew", 20.0, "Yes"],
                         source=tent)
    vs = poly_verts(vm, vm.source)
    assert close(vs[0], (-10.0, 0.0)) and close(vs[2], (110.0, 0.0)), vs
    assert close(vs[1], (50.0, 36.0)), vs
    assert "10.0000 added at each end" in said(vm)
    print("PERPPTS split: one scale, the shape carried along")


def test_perppts_shares_a_round_change_as_asked():
    """The round-level question splits the same way, with the polyline's
    first point -- the one at the arrowed end -- as START."""
    vm, pl = run_perppts([CLICK, 3, 10.0, 12.0, 10.0, "Straight",
                          "Grew", 20.0, "No", 5.0, "No", "STandard"])
    # scaled by 1.2 about (25, 10): START out 5, FINISH out 15
    assert rounded(poly_verts(vm, pl[0])) == \
        [(-5.0, 10.0), (55.0, 12.4), (115.0, 10.0)], poly_verts(vm, pl[0])
    heads = [tuple(round(v, 9) for v in d[1][:2]) for d in vm.dims]
    assert heads == rounded(poly_verts(vm, pl[0])), heads
    assert source_ends(vm) == ((0.0, 0.0), (100.0, 0.0)), \
        "the line offset FROM is not touched by the round's question"
    # with the right end as START it is the right end that moves 5
    vm, pl = run_perppts([CLICK_RIGHT, 3, 10.0, 12.0, 10.0, "Straight",
                          "Grew", 20.0, "No", 5.0, "No", "STandard"])
    vs = poly_verts(vm, pl[0])
    assert close(vs[0], (105.0, 10.0)) and close(vs[-1], (-15.0, 10.0)), vs
    # the round question offers no Back at its first question: the line
    # is drawn already
    asked = [p for p in prompts_of(vm) if "Has that width changed" in p]
    assert asked[-1].endswith("[Grew/Shrank/New/Unchanged] <Unchanged>: "), \
        asked[-1]
    # ...but the split chain behind it walks back as at the opening
    vm, pl = run_perppts([CLICK, 2, 10.0, 10.0, "Grew", 20.0, "No", "B",
                          "No", 0.0, "No", "STandard"])
    vs = poly_verts(vm, pl[0])
    assert close(vs[0], (0.0, 10.0)) and close(vs[-1], (120.0, 10.0)), vs
    print("PERPPTS split: a round's line is shared out the same way")


def test_perppts_takes_a_boundary_as_a_limit():
    """PERPPTS caps at a boundary exactly as CPERPPTS does: per point
    along the fixed normal, Max takes it, a longer length is brought
    back to it, and the number typed is what Enter repeats."""
    vm, pl = run_perppts([CLICK, 3, "Max", 40.0, None, "Straight", WIDTH_OK,
                          "No", "STandard"], boundary=FLAT)
    out = said(vm)
    assert "Boundary set: no offset will cross that LWPOLYLINE." in out, out
    assert "40.0000 would cross the boundary - point 2 is capped at 30.0000." \
        in out, out
    assert "point 3 is capped at 30.0000" in out, "Enter repeats the 40"
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 30.0), (50.0, 30.0), (100.0, 30.0)], poly_verts(vm, pl[0])
    asked = prompts_of(vm)
    assert "\nLength for point 1 of 3, boundary at 30.0000 [Back/Max]: " \
        in asked, asked
    # Max is a length like any other for the next point's default...
    assert "\nLength for point 2 of 3, boundary at 30.0000 <30.0000> " \
        "[Back/Max]: " in asked, asked
    # ...but a TYPED length that was capped repeats as typed
    assert "\nLength for point 3 of 3, boundary at 30.0000 <40.0000> " \
        "[Back/Max]: " in asked, "Enter repeats the TYPED 40, not the cap"
    assert "[Limit/Meet/Back] <Limit>: " in asked[4], asked[4]
    assert len(vm.dims) == 3
    heads = [tuple(d[1][:2]) for d in vm.dims]
    assert heads == poly_verts(vm, pl[0]), heads
    print("PERPPTS Limit: capped per point, Max takes it, typed repeats")

    # slanted: each point has its own cap
    vm, pl = run_perppts([CLICK, 3, "Max", "M", "Max", "Straight", WIDTH_OK,
                          "No", "STandard"], boundary=SLANT)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 40.0), (50.0, 50.0), (100.0, 60.0)], poly_verts(vm, pl[0])
    print("PERPPTS Limit: a slanted boundary caps each point apart")

    # covering part of the run: the rest is asked as it always was
    vm, pl = run_perppts([CLICK, 3, 12.0, 45.0, 12.0, "Straight", WIDTH_OK,
                          "No", "STandard"], boundary=PART)
    asked = prompts_of(vm)
    assert "\nLength for point 1 of 3 [Back]: " in asked, asked
    assert "\nLength for point 2 of 3, boundary at 30.0000 <12.0000> " \
        "[Back/Max]: " in asked, asked
    assert "\nLength for point 3 of 3 <45.0000> [Back]: " in asked, asked
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 12.0), (50.0, 30.0), (100.0, 12.0)], poly_verts(vm, pl[0])
    print("PERPPTS Limit: a boundary over part of a run caps that part")

    # Back at a capped point steps back like any other
    vm, pl = run_perppts([CLICK, 3, 12.0, "Max", "Back", 20.0, 12.0,
                          "Straight", WIDTH_OK, "No", "STandard"],
                         boundary=PART)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 12.0), (50.0, 20.0), (100.0, 12.0)], poly_verts(vm, pl[0])
    assert len(vm.dims) == 3, "the point taken back must not leave a dimension"
    print("PERPPTS Limit: Back at a capped point re-asks it")


def test_perppts_runs_out_to_meet_the_boundary():
    """Meet: a point with the boundary ahead of it lands on the boundary
    and no length is asked; where nothing is ahead the length is asked
    and the prompt says why."""
    vm, pl = run_perppts([CLICK, 3, "Straight", WIDTH_OK, "No", "STandard"],
                         boundary=SLANT, mode=["Meet"])
    out = said(vm)
    assert "Boundary set: every offset runs out to that LWPOLYLINE." in out
    assert "Point 1 of 3 runs out to the boundary: 40.0000." in out, out
    assert "Point 2 of 3 runs out to the boundary: 50.0000." in out, out
    assert "Point 3 of 3 runs out to the boundary: 60.0000." in out, out
    assert not any("Length for point" in p for p in prompts_of(vm)), \
        "Meet must not ask a length where the boundary is ahead"
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 40.0), (50.0, 50.0), (100.0, 60.0)], poly_verts(vm, pl[0])
    assert len(vm.dims) == 3
    for d, want in zip(vm.dims, [40.0, 50.0, 60.0]):
        assert abs(d[0][1]) < 1e-9 and abs(d[1][1] - want) < 1e-9, d
    print("PERPPTS Meet: every point lands on the boundary, nothing asked")

    # the hotkey is M
    vm, pl = run_perppts([CLICK, 2, WIDTH_OK, "No", "STandard"],
                         boundary=SLANT, mode=["M"])
    assert rounded(poly_verts(vm, pl[0])) == [(0.0, 40.0), (100.0, 60.0)]
    print("PERPPTS Meet: M is the hotkey")

    # a boundary over part of the run: the uncovered points are asked,
    # and the prompt says there is nothing ahead of them
    vm, pl = run_perppts([CLICK, 3, 12.0, 12.0, "Straight", WIDTH_OK, "No",
                          "STandard"], boundary=PART, mode=["Meet"])
    asked = prompts_of(vm)
    assert "\nLength for point 1 of 3 (no boundary ahead) [Back]: " in asked, \
        asked
    assert "\nLength for point 3 of 3 (no boundary ahead) <12.0000> [Back]: " \
        in asked, asked
    assert "Point 2 of 3 runs out to the boundary: 30.0000." in said(vm)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 12.0), (50.0, 30.0), (100.0, 12.0)], poly_verts(vm, pl[0])
    print("PERPPTS Meet: a point with nothing ahead is asked, and told")

    # arcs through landed points are fitted like any others
    vm, pl = run_perppts([CLICK, 3, "Arcs", WIDTH_OK, "No", "STandard"],
                         boundary=BENT, mode=["Meet"])
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 30.0), (50.0, 30.0), (100.0, 80.0)], poly_verts(vm, pl[0])
    assert all(abs(b) > 1e-6 for b in poly_bulges(vm, pl[0]))
    print("PERPPTS Meet: the join question still applies to landed points")


def test_perppts_meet_walks_back_to_the_last_typed_length():
    """Back at a length re-asks the last length TYPED, taking every point
    that ran out to the boundary in between with it; with nothing typed
    in front of it, the count is re-asked -- and Back at the join does
    the same from the far end."""
    # five points at x = 0, 25, 50, 75, 100; PART covers 30..70, so the
    # third lands and the other four are asked
    vm, pl = run_perppts([CLICK, 5, 10.0, 11.0, "Back", 12.0, 13.0, 14.0,
                          "Straight", WIDTH_OK, "No", "STandard"],
                         boundary=PART, mode=["Meet"])
    asked = prompts_of(vm)
    assert sum("Length for point 2 of 5" in p for p in asked) == 2, asked
    assert sum("Length for point 4 of 5" in p for p in asked) == 2, asked
    assert said(vm).count("Point 3 of 5 runs out to the boundary") == 2, \
        "the landed point between is taken back and lands again"
    assert "Stepping back one point." in said(vm)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 10.0), (25.0, 12.0), (50.0, 30.0), (75.0, 13.0),
         (100.0, 14.0)], poly_verts(vm, pl[0])
    assert len(vm.dims) == 5, "no spare dimension from the points taken back"
    print("PERPPTS Meet: Back goes to the last length typed, past the landed")

    # nothing typed in front of the first asked point: the count
    vm, pl = run_perppts([CLICK, 5, "Back", 3, 10.0, 10.0, "Straight",
                          WIDTH_OK, "No", "STandard"],
                         boundary=PART, mode=["Meet"])
    asked = prompts_of(vm)
    assert sum("how many values" in p for p in asked) == 2, asked
    assert "Stepping back one question." in said(vm)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 10.0), (50.0, 30.0), (100.0, 10.0)], poly_verts(vm, pl[0])
    assert len(vm.dims) == 3
    print("PERPPTS Meet: Back with nothing typed re-asks the count")

    # every point landed: Back at the join goes to the count too, and
    # the points land again
    vm, pl = run_perppts([CLICK, 3, "Back", 3, "Straight", WIDTH_OK, "No",
                          "STandard"], boundary=SLANT, mode=["Meet"])
    asked = prompts_of(vm)
    assert sum("how many values" in p for p in asked) == 2, asked
    assert sum("how should the points be joined" in p for p in asked) == 2
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 40.0), (50.0, 50.0), (100.0, 60.0)], poly_verts(vm, pl[0])
    assert len(vm.dims) == 3
    print("PERPPTS Meet: Back at the join with nothing typed re-asks the count")

    # without a boundary the same rule reads as it always did: Back at
    # the first point is the count, Back at a later one is that point
    vm, pl = run_perppts([CLICK, 3, "Back", 2, 10.0, "Back", 12.0, 14.0,
                          WIDTH_OK, "No", "STandard"])
    asked = prompts_of(vm)
    assert sum("how many values" in p for p in asked) == 2, asked
    assert sum("Length for point 1 of 2" in p for p in asked) == 2, asked
    assert rounded(poly_verts(vm, pl[0])) == [(0.0, 12.0), (100.0, 14.0)]
    print("PERPPTS: Back at the first length re-asks the count")


def test_perppts_mode_question_walks_back_to_the_boundary():
    """Back at Limit/Meet re-opens the boundary selection; Enter there
    is Limit; the line itself is refused as its own boundary; a
    non-curve is refused."""
    vm, pl = run_perppts([CLICK, None, BND, "Back", BND, "Meet", 3,
                          "Straight", WIDTH_OK, "No", "STandard"],
                         raw=True, boundary=SLANT)
    asked = prompts_of(vm)
    assert sum("Select a boundary for the offsets" in p for p in asked) == 2
    assert sum("stop at the boundary, or run out to meet it" in p
               for p in asked) == 2, asked
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 40.0), (50.0, 50.0), (100.0, 60.0)], poly_verts(vm, pl[0])
    print("PERPPTS: Back at Limit/Meet re-opens the boundary selection")

    vm, pl = run_perppts([CLICK, None, SRC, BND, None, 3, "Max", "Max",
                          "Max", "Straight", WIDTH_OK, "No", "STandard"],
                         raw=True, boundary=SLANT)
    assert "cannot be bounded by where it starts" in said(vm), said(vm)[-300:]
    assert "no offset will cross" in said(vm), "Enter at the mode is Limit"
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 40.0), (50.0, 50.0), (100.0, 60.0)], poly_verts(vm, pl[0])
    print("PERPPTS: the line is not its own boundary; Enter is Limit")

    # a thing AutoCAD cannot measure along is refused, and None then
    # runs the command as it was before there were boundaries
    install_entity_builtins()
    install_curve_builtins()
    install_intersect_builtins()
    vm = VM()
    install_command(vm)
    vm.load(PERP_LSP)
    src = Ent()
    vm.entities.append(src)
    vm.entdata[src] = [Dot(0, 'LINE'), Dot(8, 'WALLS'), Dot(62, 3),
                       [10, 0.0, 0.0, 0.0], [11, 100.0, 0.0, 0.0]]
    txt = Ent()
    vm.entities.append(txt)
    vm.entdata[txt] = [Dot(0, 'TEXT'), Dot(8, '0'), [10, 5.0, 5.0, 0.0],
                       Dot(1, 'hello')]
    vm.tables['LAYER'].add('WALLS')
    vm.tables['DIMSTYLE'].add('STANDARD INCHES')
    vm.run('c:PERPPTS', [src, CLICK, None, txt, None, 2, 10.0, 10.0,
                         WIDTH_OK, "No", "STandard"])
    assert "A TEXT cannot be a boundary" in said(vm), said(vm)[-300:]
    assert "Boundary set" not in said(vm)
    assert "\nLength for point 1 of 2 [Back]: " in prompts_of(vm)
    print("PERPPTS: a non-curve is refused, None caps nothing")


def test_perppts_reports_points_moved_off_or_past_the_boundary():
    """The width correction is not re-capped, but a line it moves past a
    Limit boundary or off a Meet one says how many points."""
    # Meet on a boundary that turns up at x=50: (0,30) (50,30) (100,80);
    # holding START and growing 20 carries the other two off it
    vm, pl = run_perppts([CLICK, 3, "Straight", "Grew", 20.0, "No", 0.0,
                          "No", "STandard"], boundary=BENT, mode=["Meet"])
    out = said(vm)
    assert "2 of 3 points no longer sit on the boundary - the width " \
        "correction moved the line off it." in out, out[-400:]
    # an even split of a flat boundary's line keeps every point on it
    vm, pl = run_perppts([CLICK, 3, "Straight", "Grew", 20.0, None,
                          "No", "STandard"], boundary=FLAT, mode=["Meet"])
    assert "no longer sit on the boundary" not in said(vm)
    print("PERPPTS Meet: points a correction moves off the boundary are counted")

    # Limit on a boundary that drops toward FINISH: the middle point,
    # capped at 30, is carried across the drop when START is held
    vm, pl = run_perppts([CLICK, 3, "Max", "Max", 10.0, "Straight",
                          "Grew", 20.0, "No", 0.0, "No", "STandard"],
                         boundary=DIP)
    out = said(vm)
    assert "1 of 3 points now sit past the boundary - the width " \
        "correction carried the line beyond it." in out, out[-400:]
    print("PERPPTS Limit: points a correction carries past the boundary "
          "are counted")


# --- CPERPPTS, driven end to end ----------------------------------------
# The curve calls its rounds make are shimmed above over LWPOLYLINEs
# with bulges, so the real cperp_points.lsp runs the whole way through.

def test_cperppts_runs_end_to_end_in_the_vm():
    """A straight polyline is a curve whose tangent is (1, 0) all along,
    so the run reads exactly as PERPPTS's does -- and the prompt order is
    the same one."""
    vm, pl = run_cperppts([CLICK, 3, 10.0, 12.0, 10.0, WIDTH_OK, "No",
                           "STandard"])
    assert len(pl) == 1, len(pl)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 10.0), (50.0, 12.0), (100.0, 10.0)], poly_verts(vm, pl[0])
    assert dxf(vm.entdata[pl[0]], 8) == 'WALLS'
    assert len(vm.dims) == 3
    asked = prompts_of(vm)
    heads = ["Select a curve", "Click to pick direction / offset side [Back]",
             "Has that width changed? [Grew/Shrank/New/Unchanged/Back]",
             "Select a boundary for the offsets [None] <None>",
             "Round 1 - how many values", "Length for point 1 of 3 [Back]",
             "Length for point 2 of 3 <10.0000> [Back]",
             "Length for point 3 of 3 <12.0000> [Back]",
             "Has that width changed? [Grew/Shrank/New/Unchanged] <Unchanged>",
             "Repeat on the new polyline", "Dimension style"]
    for want, got in zip(heads, asked):
        assert want in got, (want, got)
    assert len(asked) == len(heads), asked
    assert vm.error_mode_depth == 0 and vm.sysvars['OSMODE'] == 4133
    print("CPERPPTS runs end to end in the VM, in PERPPTS's prompt order")


def test_cperppts_offsets_radially_off_an_arc_in_the_vm():
    """A semicircle (one segment, bulge 1, centre (50, 0), bowing below
    its chord) clicked from outside: every offset is radial, every
    dimension measures its length, and the arcs written between the
    offset points reproduce the larger circle exactly."""
    vm, pl = run_cperppts([[50.0, -80.0, 0.0], 5, 10.0, 10.0, 10.0, 10.0,
                           10.0, WIDTH_OK, "No", "STandard"],
                          bulges=[1.0, 0.0])
    vs = poly_verts(vm, pl[0])
    assert len(vs) == 5
    for x, y in vs:
        assert abs(math.hypot(x - 50.0, y) - 60.0) < 1e-6, (x, y)
    for i, (x, y) in enumerate(vs):
        a = math.pi + i * math.pi / 4.0
        assert close((x, y), (50.0 + 60.0 * math.cos(a),
                              60.0 * math.sin(a)), 1e-6), (i, x, y)
    for b in poly_bulges(vm, pl[0]):
        assert abs(b - math.tan(math.pi / 16.0)) < 1e-6, b
    for d in vm.dims:
        assert abs(math.dist(d[0][:2], d[1][:2]) - 10.0) < 1e-6, d
        assert abs(math.hypot(d[0][0] - 50.0, d[0][1]) - 50.0) < 1e-6, d
    print("CPERPPTS: radial offsets off an arc, and the arcs come out right")

    # the click's side: from inside the bend the offsets go inward
    vm, pl = run_cperppts([[50.0, -20.0, 0.0], 3, 10.0, 10.0, 10.0,
                           WIDTH_OK, "No", "STandard"], bulges=[1.0, 0.0])
    for x, y in poly_verts(vm, pl[0]):
        assert abs(math.hypot(x - 50.0, y) - 40.0) < 1e-6, (x, y)
    print("CPERPPTS: the clicked side decides inward or outward")


def test_cperppts_rounds_from_the_newest_curve_in_the_vm():
    """Round 2 samples and offsets from the arc polyline round 1 built:
    its base points sit on that curve and its offsets run along that
    curve's normals, so concentric arcs come out concentric."""
    vm, pl = run_cperppts([[50.0, -80.0, 0.0], 5, 10.0, 10.0, 10.0, 10.0,
                           10.0, WIDTH_OK, "Yes", 4, 5.0, 5.0, 5.0, 5.0,
                           WIDTH_OK, "No", "STandard"], bulges=[1.0, 0.0])
    assert len(pl) == 2, len(pl)
    for x, y in poly_verts(vm, pl[1]):
        assert abs(math.hypot(x - 50.0, y) - 65.0) < 1e-6, (x, y)
    bases2 = [d[0] for d in vm.dims[5:]]
    assert len(bases2) == 4
    for x, y, _z in bases2:
        assert abs(math.hypot(x - 50.0, y) - 60.0) < 1e-6, (x, y)
    # spaced by arc length along the round-1 curve: equal angles
    angs = [math.atan2(y, x - 50.0) % (2 * math.pi) for x, y, _z in bases2]
    gaps = [angs[i + 1] - angs[i] for i in range(3)]
    assert max(gaps) - min(gaps) < 1e-6, gaps
    assert len(vm.dims) == 9
    print("CPERPPTS: the next round works from the newest curve")


def test_cperppts_opening_chain_walks_back():
    vm, pl = run_cperppts(["Back", SRC, CLICK, None, None, 2, 10.0, 10.0,
                           WIDTH_OK, "No", "STandard"], raw=True)
    asked = prompts_of(vm)
    assert sum("Select a curve" in p for p in asked) == 2, asked
    assert rounded(poly_verts(vm, pl[0])) == [(0.0, 10.0), (100.0, 10.0)]
    vm, pl = run_cperppts([CLICK, "Back", CLICK_RIGHT, None, None, 2, 10.0,
                           12.0, WIDTH_OK, "No", "STandard"], raw=True)
    asked = prompts_of(vm)
    assert sum("Click to pick direction" in p for p in asked) == 2, asked
    assert sum("Has that width changed" in p for p in asked) == 3, asked
    assert len(arrows(vm)) == 2
    assert close(arrows(vm)[-1][0][1], (100.0, 0.0)), arrows(vm)[-1]
    # the second click chose the right end as START
    assert rounded(poly_verts(vm, pl[0])) == [(100.0, 10.0), (0.0, 12.0)]
    print("CPERPPTS chain: Back at the click and at the width walk back")


def test_cperppts_shares_the_width_change_as_asked():
    """The same split as PERPPTS, on the curve: START is the clicked
    end, the resize is one scale about a point on the chord, and the
    arrow follows START."""
    for width, (xs, xf) in ((["Grew", 20.0, "No", 5.0], (-5.0, 115.0)),
                            (["Grew", 20.0, None], (-10.0, 110.0)),
                            (["Shrank", 20.0, "No", 0.0], (0.0, 80.0)),
                            (["New", 50.0, "No", 50.0], (50.0, 100.0))):
        vm, pl = run_cperppts([CLICK, 3, 10.0, 10.0, 10.0, WIDTH_OK, "No",
                               "STandard"], width=width)
        vs = poly_verts(vm, vm.source)
        assert close(vs[0], (xs, 0.0)) and close(vs[-1], (xf, 0.0)), \
            (width, vs)
        bases = sorted(round(d[0][0], 9) for d in vm.dims)
        assert bases == [xs, round((xs + xf) / 2.0, 9), xf], (width, bases)
        assert close(arrows(vm)[-1][0][1], (xs, 0.0)), arrows(vm)[-1]
    print("CPERPPTS split: START moves by the amount given, FINISH by the rest")

    # clicked at the right end: START is (100, 0)
    vm, pl = run_cperppts([CLICK_RIGHT, 3, 10.0, 10.0, 10.0, WIDTH_OK, "No",
                           "STandard"], width=["Grew", 20.0, "No", 5.0])
    vs = poly_verts(vm, vm.source)
    assert close(vs[0], (-15.0, 0.0)) and close(vs[-1], (105.0, 0.0)), vs
    assert close(arrows(vm)[-1][0][1], (105.0, 0.0)), arrows(vm)[-1]
    # a semicircle held at START and grown stays a semicircle: the
    # resize is one scale, so the arc keeps its shape
    vm, pl = run_cperppts([[50.0, -80.0, 0.0], 3, 10.0, 10.0, 10.0,
                           WIDTH_OK, "No", "STandard"],
                          width=["Grew", 20.0, "No", 0.0], bulges=[1.0, 0.0])
    vs = poly_verts(vm, vm.source)
    assert close(vs[0], (0.0, 0.0)) and close(vs[-1], (120.0, 0.0)), vs
    assert abs(poly_bulges(vm, vm.source)[0] - 1.0) < 1e-12
    for x, y in poly_verts(vm, pl[0]):
        assert abs(math.hypot(x - 60.0, y) - 70.0) < 1e-6, (x, y)
    print("CPERPPTS split: the curve keeps its shape, scaled")

    # the round-level split, START being the polyline's first point
    vm, pl = run_cperppts([CLICK, 3, 10.0, 12.0, 10.0, "Grew", 20.0, "No",
                           5.0, "No", "STandard"])
    vs = poly_verts(vm, pl[0])
    assert close(vs[0], (-5.0, 10.0)) and close(vs[-1], (115.0, 10.0)), vs
    assert close(vs[1], (55.0, 12.4)), vs
    heads = [tuple(round(v, 9) for v in d[1][:2]) for d in vm.dims]
    assert heads == rounded(vs), heads
    print("CPERPPTS split: a round's curve is shared out the same way")


def test_cperppts_limits_at_or_meets_the_boundary_in_the_vm():
    vm, pl = run_cperppts([CLICK, 3, "Max", 40.0, None, WIDTH_OK, "No",
                           "STandard"], boundary=FLAT)
    assert "40.0000 would cross the boundary - point 2 is capped at 30.0000." \
        in said(vm)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 30.0), (50.0, 30.0), (100.0, 30.0)], poly_verts(vm, pl[0])
    assert "\nLength for point 3 of 3, boundary at 30.0000 <40.0000> " \
        "[Back/Max]: " in prompts_of(vm)
    print("CPERPPTS Limit: capped per point, Max takes it, typed repeats")

    vm, pl = run_cperppts([CLICK, 3, WIDTH_OK, "No", "STandard"],
                          boundary=SLANT, mode=["Meet"])
    assert "Point 2 of 3 runs out to the boundary: 50.0000." in said(vm)
    assert not any("Length for point" in p for p in prompts_of(vm))
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 40.0), (50.0, 50.0), (100.0, 60.0)], poly_verts(vm, pl[0])
    assert len(vm.dims) == 3
    print("CPERPPTS Meet: every point lands on the boundary, nothing asked")

    # on the arc the ray runs along each point's own normal: a flat
    # boundary below the semicircle is met radially -- nearest at the
    # bottom, further out toward the ends -- and the two end points,
    # whose normals run along the chord, never reach it and are asked
    vm, pl = run_cperppts([[50.0, -80.0, 0.0], 5, 10.0, 10.0, WIDTH_OK,
                           "No", "STandard"],
                          boundary=[(-100.0, -70.0), (200.0, -70.0)],
                          mode=["Meet"], bulges=[1.0, 0.0])
    vs = poly_verts(vm, pl[0])
    assert len(vs) == 5, vs
    assert close(vs[0], (-10.0, 0.0), 1e-6) and \
        close(vs[4], (110.0, 0.0), 1e-6), vs
    for i in (1, 2, 3):
        a = math.pi + i * math.pi / 4.0
        assert close(vs[i], (50.0 - 70.0 / math.tan(a), -70.0), 1e-6), \
            (i, vs[i])
    asked = prompts_of(vm)
    assert sum("(no boundary ahead)" in p for p in asked) == 2, asked
    assert said(vm).count("runs out to the boundary") == 3
    print("CPERPPTS Meet: met along each point's own normal")

    # Back walks to the last typed length past the landed ones, and to
    # the count when nothing was typed
    vm, pl = run_cperppts([CLICK, 5, 10.0, 11.0, "Back", 12.0, 13.0, 14.0,
                           WIDTH_OK, "No", "STandard"],
                          boundary=PART, mode=["Meet"])
    asked = prompts_of(vm)
    assert sum("Length for point 2 of 5" in p for p in asked) == 2, asked
    assert sum("Length for point 4 of 5" in p for p in asked) == 2, asked
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 10.0), (25.0, 12.0), (50.0, 30.0), (75.0, 13.0),
         (100.0, 14.0)], poly_verts(vm, pl[0])
    assert len(vm.dims) == 5
    vm, pl = run_cperppts([CLICK, 5, "Back", 3, 10.0, 10.0, WIDTH_OK, "No",
                           "STandard"], boundary=PART, mode=["Meet"])
    assert sum("how many values" in p for p in prompts_of(vm)) == 2
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 10.0), (50.0, 30.0), (100.0, 10.0)], poly_verts(vm, pl[0])
    print("CPERPPTS Meet: Back goes to the last length typed, or the count")

    # the mode question walks back to the selection; Enter is Limit
    vm, pl = run_cperppts([CLICK, None, BND, "Back", BND, None, 3, "Max",
                           "Max", "Max", WIDTH_OK, "No", "STandard"],
                          raw=True, boundary=SLANT)
    assert sum("Select a boundary for the offsets" in p
               for p in prompts_of(vm)) == 2
    assert "no offset will cross" in said(vm)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 40.0), (50.0, 50.0), (100.0, 60.0)], poly_verts(vm, pl[0])
    print("CPERPPTS: Back at Limit/Meet re-opens the boundary selection")

    # and the correction's report, in both modes
    vm, pl = run_cperppts([CLICK, 3, "Grew", 20.0, "No", 0.0, "No",
                           "STandard"], boundary=BENT, mode=["Meet"])
    assert "2 of 3 points no longer sit on the boundary - the width " \
        "correction moved the curve off it." in said(vm), said(vm)[-400:]
    vm, pl = run_cperppts([CLICK, 3, "Max", "Max", 10.0, "Grew", 20.0, "No",
                           0.0, "No", "STandard"], boundary=DIP)
    assert "1 of 3 points now sit past the boundary - the width " \
        "correction carried the curve beyond it." in said(vm), said(vm)[-400:]
    print("CPERPPTS: points a correction moves off or past the boundary "
          "are counted")


def test_both_routines_ask_the_new_questions_in_the_same_words():
    """One vocabulary for one question, repo-wide (STANDARDS 3): the
    split, the START amount and the boundary mode read identically in
    both files, keyword lists included."""
    a, b = load(PERP_LSP), load(CPERP_LSP)
    for text in ('" evenly, half at each end?"',
                 '" [Yes/No/Back] <" sdflt ">: "',
                 '" at the START end (the arrowed end)?"',
                 '(initget 5 "Back Undo")',
                 '(initget "Limit Meet Back Undo")',
                 '"\\nDo the offsets stop at the boundary,"',
                 '" [Limit/Meet/Back] <" bdflt ">: "',
                 '"\\nSelect a boundary for the offsets [None] <None>: "',
                 '"\\nClick to pick direction / offset side [Back]: "',
                 '" runs out to the boundary: "',
                 '" (no boundary ahead)"',
                 '(initget "Back Undo")'):
        assert text in a, ("perp_points.lsp lacks", text)
        assert text in b, ("cperp_points.lsp lacks", text)
    # what those two questions take on Enter is a knob in each file
    # now, and both files still ship the same pair of words
    for code, pre in ((a, "perp"), (b, "cperp")):
        assert '(setq %s:*split-default* "Yes")' % pre in code, \
            "the split question must still ship Yes"
        assert re.search(r'\(setq %s:\*bound(?:ary)?-default\* "Limit"\)'
                         % pre, code), \
            "the boundary question must still ship Limit"
    # the click comes before the width question in both, and the width
    # helper is handed the Back it can offer there and not at a round
    for code, pre in ((a, "perp"), (b, "cperp")):
        click = code.index("Click to pick direction / offset side [Back]")
        width = code.index('(%s:ask-width "Overall width" wOld T)' % pre)
        bnd = code.index("Select a boundary for the offsets")
        assert click < width < bnd, (click, width, bnd)
        assert re.search(r'\(%s:ask-width "Overall width of the new '
                         r'(polyline|curve)" wOld nil\)' % pre, code), \
            "the round's width question offers no Back at its first question"
    print("PERPPTS/CPERPPTS: the new questions read the same in both")


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
    test_perppts_asks_how_to_join_the_points()
    test_perppts_mixed_takes_a_segment_list()
    test_perppts_rounds_follow_the_curve_they_offset_from()
    test_perppts_asks_whether_the_overall_width_changed()
    test_perppts_width_is_measured_across_not_along()
    test_perppts_dimensions_follow_the_resized_line()
    test_perppts_resizes_the_line_it_just_drew()
    test_perppts_next_round_measures_the_corrected_line()
    test_perppts_keeps_going_when_the_new_line_will_not_resize()
    test_cperppts_asks_the_same_of_the_curve_it_just_drew()
    test_the_boundary_probe_caps_an_offset()
    test_the_boundary_counts_points_carried_past_or_off_it()
    test_cperppts_boundary_is_optional_and_wired_through()
    test_scale_pts_moves_points_with_the_resized_object()
    test_perppts_says_so_when_the_drawing_refuses_the_resize()
    test_the_width_question_reads_the_same_in_both_routines()
    test_the_width_change_can_be_shared_unevenly()
    test_the_width_chain_walks_back()
    test_scale_centre_shares_the_change_out()
    test_rescale_says_whether_the_drawing_took_it()
    test_perppts_opening_chain_walks_back()
    test_perppts_arrow_marks_start_and_follows_the_resize()
    test_perppts_shares_the_width_change_as_asked()
    test_perppts_shares_a_round_change_as_asked()
    test_perppts_takes_a_boundary_as_a_limit()
    test_perppts_runs_out_to_meet_the_boundary()
    test_perppts_meet_walks_back_to_the_last_typed_length()
    test_perppts_mode_question_walks_back_to_the_boundary()
    test_perppts_reports_points_moved_off_or_past_the_boundary()
    test_cperppts_runs_end_to_end_in_the_vm()
    test_cperppts_offsets_radially_off_an_arc_in_the_vm()
    test_cperppts_rounds_from_the_newest_curve_in_the_vm()
    test_cperppts_opening_chain_walks_back()
    test_cperppts_shares_the_width_change_as_asked()
    test_cperppts_limits_at_or_meets_the_boundary_in_the_vm()
    test_both_routines_ask_the_new_questions_in_the_same_words()
    test_perppts_walks_its_chains_back()
    test_perppts_leaves_the_error_mode_alone_on_every_exit()
    print("\nall tests passed")
    test_the_length_ruler_hands_a_row_in_as_the_length()
    test_the_length_ruler_is_down_between_rounds()
    test_the_length_prompt_reads_a_measurement_as_dimstamp_does()
    test_a_click_off_the_ruler_measures_between_two_points()
    test_max_and_back_still_work_at_the_ruler_prompt()


def test_perppts_walks_its_chains_back():
    """Back at the three questions that grew one.

    Each is a second question whose answer only makes sense next to the
    first: the amount a width changed by, the way the points are joined,
    and the dimension style asked once the rounds are done.  Back at any
    of them re-opens the one in front of it, and B and U mean the same
    thing there as Back does.
    """
    # the amount re-opens "has that width changed?"
    vm, _pl = run_perppts([CLICK, 3, 10.0, 12.0, 14.0, "Straight",
                           WIDTH_OK, "No", "STandard"],
                          width=["Grew", "Back", None])
    said = "".join(vm.printed)
    asked = [p for p, _v in vm.prompts if "Has that width changed" in p]
    assert len(asked) == 3, \
        "Back at the amount must re-ask the width, and the line just drawn " \
        "is asked about after it"
    assert "Stepping back one question" in said, said[-200:]

    # ...and U is the same answer as Back there
    vm, _pl = run_perppts([CLICK, 2, 10.0, 12.0, WIDTH_OK, "No",
                           "STandard"],
                          width=["New", "U", None])
    asked = [p for p, _v in vm.prompts if "Has that width changed" in p]
    assert len(asked) == 3, \
        "U must be taken as Back at the new width, and the line just drawn " \
        "is asked about too"

    # the join re-opens the LAST length, guide node and all
    vm, pl = run_perppts([CLICK, 3, 10.0, 12.0, 14.0, "Back", 16.0,
                          "Straight", WIDTH_OK, "No", "STandard"])
    said = "".join(vm.printed)
    assert "Stepping back one point." in said, said[-200:]
    lengths = [p for p, _v in vm.prompts if "Length for point 3" in p]
    assert len(lengths) == 2, "Back at the join must re-ask point 3"
    assert poly_verts(vm, pl[0])[2][1] == 16.0, \
        "the re-entered length is the one that gets drawn"
    assert len(vm.dims) == 3, \
        "the point taken back must not leave a spare dimension"

    # the dimension style re-opens "repeat?"
    vm, _pl = run_perppts([CLICK, 2, 10.0, 12.0, WIDTH_OK, "No", "B", "No",
                           "STandard"])
    asked = [p for p, _v in vm.prompts if "Repeat on the new polyline" in p]
    assert len(asked) == 2, "B at the style must re-ask whether to repeat"
    print("  PERPPTS walks its width, join and style questions back")


def test_perppts_leaves_the_error_mode_alone_on_every_exit():
    """PERPPTS used to push AutoCAD's error mode so its handler could
    drain a pending command -- and under a push AutoCAD resets the
    evaluator before *error* runs, so the handler's call to its LOCAL
    perp:finish was a call to nothing (tests/test_fix_perp.py models
    that).  From v0.24 neither routine pushes: both exits leave the
    mode exactly as they found it, and neither pops what it never
    pushed."""
    vm, pl = run_perppts([CLICK, 5] + BOW + ["Straight", WIDTH_OK, "No",
                                             "STandard"])
    assert vm.error_mode_depth == 0 and vm.error_mode_underflow == 0, \
        (vm.error_mode_depth, vm.error_mode_underflow)
    assert vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1, \
        vm.sysvars
    # and the cancel path: Esc at the click
    install_entity_builtins()
    install_curve_builtins()
    vm = VM()
    install_command(vm)
    vm.load(PERP_LSP)
    src = Ent()
    vm.entities.append(src)
    vm.entdata[src] = [Dot(0, 'LINE'), Dot(8, 'WALLS'), Dot(62, 3),
                       [10, 0.0, 0.0, 0.0], [11, 100.0, 0.0, 0.0]]
    vm.tables['LAYER'].add('WALLS')
    vm.handle_errors = True

    def esc(vm):
        raise LispError('Function cancelled', vm)

    vm.run('c:PERPPTS', [src, None, esc])
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert vm.error_mode_depth == 0 and vm.error_mode_underflow == 0, \
        (vm.error_mode_depth, vm.error_mode_underflow)
    assert vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1, \
        vm.sysvars
    # CPERPPTS carries the same finish helper, and pushes nothing either
    for name in ("perp_points.lsp", "cperp_points.lsp"):
        code = strip_comments(open(os.path.join(LISP_DIR, name)).read())
        assert "*push-error-using-command*" not in code \
            and "*pop-error-mode*" not in code, \
            "%s touches the error mode" % name
    print("PERPPTS/CPERPPTS: the error mode is left alone on every exit")


# --- the length ruler ---------------------------------------------------
# DIMSTAMP's ruler beside the length prompt: once a length has been
# given, the nearby eighths are drawn down a strip of the view and a
# click on a row hands that value in as the length.

def ruler_rows(path, prefix, eighths, hasfeet=False):
    """Where the ruler for this value lands, read off the routine
    itself in a throwaway VM with the same view as a run's: (box, rows)
    with rows as (eighths, y) pairs."""
    vm = VM()
    vm.load(path)
    vm.tables['LAYER'].add('PERPPTS-TEMP')
    # the copy under the tool's prefix at the standalone tier; the
    # library's at the grouped one, where the mirror has swapped it
    draw = 'cal:draw-ruler' if os.environ.get('CALOFIN_LISP_ROOT') \
        else prefix + ':draw-ruler'
    # nil ladder: a perpendicular length is taped off a wall, so this
    # prompt stands beside the tape and never a ladder
    _, box, rows = vm.loads('(%s %d %s "PERPPTS-TEMP" (%s:ruler-style) nil)'
                            % (draw, eighths, 't' if hasfeet else 'nil', prefix))
    return box, rows


def row_click(path, prefix, eighths, want, hasfeet=False):
    """A click on the ruler row that offers WANT eighths, on the ruler
    drawn around EIGHTHS."""
    box, rows = ruler_rows(path, prefix, eighths, hasfeet)
    y = dict((int(v), yy) for v, yy in rows)[want]
    return [(box[0] + box[1]) / 2.0, y, 0.0]


def temp_layer_live(vm):
    return [e for e in vm.entities
            if e not in vm.deleted and dxf(vm.entdata[e], 8) == 'PERPPTS-TEMP']


def labels_ever_drawn(vm):
    """Every ruler label the run drew, swept or not."""
    return [dxf(vm.entdata[e], 1) for e in vm.entities
            if dxf(vm.entdata[e], 0) == 'MTEXT'
            and dxf(vm.entdata[e], 8) == 'PERPPTS-TEMP']


def test_the_length_ruler_hands_a_row_in_as_the_length():
    """After the first length the ruler is up, graded round that
    length; a click on one of its rows IS the length for that point,
    and becomes what Enter repeats and what the next ruler is built
    around.  Nothing of it is left behind when the run ends."""
    for path, prefix, run in ((PERP_LSP, "perp", run_perppts),
                              (CPERP_LSP, "cperp", run_cperppts)):
        script = [CLICK, 4, 10.0,
                  row_click(path, prefix, 80, 84),        # 10 1/2"
                  None,                                    # Enter repeats it
                  row_click(path, prefix, 84, 92),        # 11 1/2"
                  WIDTH_OK, "No", "STandard"]
        if prefix == "perp":
            script.insert(6, "Straight")
        vm, pl = run(script)
        ys = [round(v[1], 9) for v in poly_verts(vm, pl[0])]
        assert ys == [10.0, 10.5, 10.5, 11.5], ys
        asked = prompts_of(vm)
        assert any(p.startswith("\nLength for point 3 of 4 <10.5000>")
                   for p in asked), asked
        assert "A ruler of nearby lengths is beside the drawing" in said(vm)
        assert said(vm).count("A ruler of nearby lengths") == 1, \
            "the hint is said once a run, not once a prompt"
        assert not temp_layer_live(vm), "the ruler must be swept with the guides"
        # the labels are the rows' own values, stacked the way DIMSTAMP
        # stacks a fraction; the ringed row is the last length
        drawn = labels_ever_drawn(vm)
        assert '\\A1;10{\\H1.0000x;\\S1/2;}"' in drawn, drawn[:20]
        assert '11"' in drawn, drawn[:20]
        rings = [e for e in vm.entities
                 if dxf(vm.entdata[e], 0) == 'CIRCLE'
                 and dxf(vm.entdata[e], 8) == 'PERPPTS-TEMP']
        # one ruler per DISTINCT last length: 10, then 10 1/2 -- Enter kept
        # it, and the 11 1/2 taken at the last point ends the round
        assert len(rings) == 2, len(rings)
        print("%s: a ruler row is a length, repeats, and is swept away"
              % prefix.upper())


def test_the_length_ruler_is_down_between_rounds():
    """The ruler belongs to the length prompts: at the join question,
    the width question and the next round's count it is not on screen,
    and it comes back at the next length prompt."""
    seen = {}

    def at(label):
        def look(vm):
            seen[label] = len(temp_layer_live(vm))
            return None
        return look

    vm, pl = run_perppts([CLICK, 2, 10.0, 12.0, at("width"), "Yes",
                          at("count"), 12.0, at("length"), WIDTH_OK,
                          "No", "STandard"])
    # the START arrow (three lines) and the guide points are the only
    # guides standing between rounds; a ruler is 2 entities a row plus
    # a spine and a ring, so its presence is unmistakable
    assert seen["width"] < 8 and seen["count"] < 8, seen
    assert seen["length"] > 20, seen
    print("PERPPTS: the ruler is up at the length prompts and nowhere else")


def test_the_length_prompt_reads_a_measurement_as_dimstamp_does():
    """44-1/2, 3'8 and 4'-4-1/2\" all read, feet typed put the ruler in
    the feet family, and what is not a length or is not positive is
    refused and asked again.  The fractions are DASHED because that is
    all this prompt can be typed: it is a getpoint, where AutoCAD takes
    the spacebar for Enter, so "44 1/2" would arrive as 44 and leave the
    1/2 to answer the next question -- which is why the hint asserted
    below no longer offers the spaced spelling."""
    vm, pl = run_perppts([CLICK, 4, "44-1/2", "abc", "3'8", 0, "-5",
                          "4'-4-1/2\"", 44.3, "Straight", WIDTH_OK, "No",
                          "STandard"])
    ys = [round(v[1], 9) for v in poly_verts(vm, pl[0])]
    assert ys == [44.5, 44.0, 52.5, 44.3], ys
    out = said(vm)
    assert '"abc" is not a length - try 44, 44.5, 44-1/2, 4\'4.5 or ' \
        '4\'-4-1/2".' in out, out
    assert out.count("A length must be more than zero.") == 2, out
    drawn = labels_ever_drawn(vm)
    assert '3\'-8"' in drawn, "feet typed means feet on the ruler"
    assert '\\A1;3\'-8{\\H1.0000x;\\S1/8;}"' in drawn, drawn
    # a length off the eighths is kept exactly; the ruler rounds
    assert len(vm.dims) == 4 and abs(vm.dims[3][1][1] - 44.3) < 1e-9, vm.dims
    print("PERPPTS: the length prompt reads what DIMSTAMP reads")


def test_a_click_off_the_ruler_measures_between_two_points():
    """Empty space is not a row: the click is the first of two points
    and the length is the distance between them -- what getdist always
    offered at this prompt."""
    vm, pl = run_perppts([CLICK, 2, 10.0, [300.0, 300.0, 0.0], 25.0,
                          WIDTH_OK, "No", "STandard"])
    ys = [round(v[1], 9) for v in poly_verts(vm, pl[0])]
    assert ys == [10.0, 25.0], ys
    assert "\nSecond point of the length: " in prompts_of(vm)
    print("PERPPTS: a click on empty space starts a two-point length")


def test_max_and_back_still_work_at_the_ruler_prompt():
    """The keywords ride through the ruler prompt unchanged: Max takes
    the boundary, Back steps back a point, and Max typed where no
    boundary is ahead is not a keyword and is refused as text."""
    vm, pl = run_perppts([CLICK, 3, 12.0, "Max", "B", 20.0, 12.0,
                          "Straight", WIDTH_OK, "No", "STandard"],
                         boundary=PART)
    assert rounded(poly_verts(vm, pl[0])) == \
        [(0.0, 12.0), (50.0, 20.0), (100.0, 12.0)], poly_verts(vm, pl[0])
    vm, pl = run_perppts([CLICK, 2, "Max", 12.0, 12.0, WIDTH_OK, "No",
                          "STandard"])
    assert '"Max" is not a length' in said(vm), said(vm)
    print("PERPPTS: Max and Back survive the ruler prompt")


if __name__ == "__main__":
    main()
