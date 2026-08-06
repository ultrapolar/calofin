# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for perp_points.lsp (AutoCAD PERPPTS command).

Two kinds of check, both runnable without AutoCAD:

* Structural checks read the real .lsp and assert the properties that
  make it safe to run -- balanced parentheses, no variable leaking to
  the global namespace, and every system variable that is changed also
  being saved and restored.
* Geometry checks exercise a reference port of the arc-length sampling
  helpers, pinning the behaviour the LISP is meant to implement.  Keep
  the port in step with the LISP helpers when either changes.

Usage:  python3 tests/test_perp_points.py
"""

import math
import os
import re

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
LSP_PATH = os.path.join(os.path.dirname(TESTS_DIR), "perp_points.lsp")

# AutoLISP builtins the "undeclared variable" scan should not flag.
BUILTINS = set("""
defun setq if while foreach cond t nil and or not null car cdr cadr caddr
cons list length nth last reverse distance sqrt abs max min float itoa rtos
strcat princ member equal eq type entsel entget entmake entmod entdel entnext
entlast tblobjname trans getvar setvar getint getdist getpoint getkword
initget command exit progn logand zerop subst assoc vl-remove quote 1+ 1-
guard c:PERPPTS
""".split())

KEYWORDS = {"T", "Yes", "No", "Undo", "STR"}


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


def load_code():
    with open(LSP_PATH) as handle:
        return strip_comments(handle.read())


# --- structural checks ------------------------------------------------

def test_parens_balanced():
    code = strip_strings(load_code())
    depth = 0
    for ch in code:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            assert depth >= 0, "closing paren with nothing open"
    assert depth == 0, "unbalanced parentheses: depth %d" % depth
    print("parens balanced")


def test_no_global_leaks():
    """Every variable used in c:PERPPTS must be declared local.

    An undeclared setq in AutoLISP silently creates a global, which then
    survives between runs and can poison a later invocation.
    """
    code = load_code()
    match = re.search(r"\(defun\s+c:PERPPTS\s*\(([^)]*)\)", code)
    assert match, "c:PERPPTS not found"
    declared = set(match.group(1).split("/")[1].split())
    body = strip_strings(code[match.start():])
    called = set(re.findall(r"\(\s*([A-Za-z*][A-Za-z0-9:*_\-]*)", body))
    used = set(re.findall(r"(?<![0-9.])[A-Za-z*][A-Za-z0-9:*_\-]*", body))
    leaked = sorted(
        name for name in used - called
        if name not in declared and name not in BUILTINS and name not in KEYWORDS
    )
    assert not leaked, "undeclared (global) variables: %s" % leaked
    unused = sorted(
        name for name in declared
        if len(re.findall(r"(?<![A-Za-z0-9:*_\-])%s(?![A-Za-z0-9:*_\-])"
                          % re.escape(name), body)) < 2
    )
    assert not unused, "declared but never used: %s" % unused
    print("no global leaks, no unused locals (%d declared)" % len(declared))


def test_sysvars_saved_and_restored():
    """Anything setvar'd must also be read first and restored on cleanup."""
    code = load_code()
    changed = set(re.findall(r'\(setvar\s+"(\w+)"', code))
    saved = set(re.findall(r'\(getvar\s+"(\w+)"', code))
    missing = sorted(changed - saved)
    assert not missing, "changed without saving: %s" % missing
    finish = re.search(r"\(defun\s+perp:finish.*?(?=\n  \(defun|\n  ;; ---)",
                       code, re.S)
    assert finish, "perp:finish not found"
    restored = set(re.findall(r'\(setvar\s+"(\w+)"', finish.group(0)))
    missing = sorted(changed - restored)
    assert not missing, "not restored in perp:finish: %s" % missing
    print("system variables saved and restored: %s" % sorted(changed))


def test_dimension_style_handling():
    """The dim style is changed by a command, so the setvar scan misses it."""
    code = load_code()
    assert '(getvar "DIMSTYLE")' in code, "current dimension style not saved"
    finish = re.search(r"\(defun\s+perp:finish.*?(?=\n  \(defun)", code, re.S)
    assert finish and "-DIMSTYLE" in finish.group(0) and "cdim" in finish.group(0), \
        "the current dimension style must be restored on cleanup"
    for name in ('"STANDARD INCHES"', '"SIDE STANDARD"'):
        assert name in code, "missing dimension style choice %s" % name
    assert '(tblsearch "DIMSTYLE" dimStyle)' in code, \
        "must check the style exists before restoring it"
    # dimensions are drawn once, at the end, not per round
    assert code.count("._DIMALIGNED") == 1, \
        "dimensions should be drawn by a single deferred loop"
    print("dimension style chosen, checked and restored")


def test_output_placement_and_properties():
    """Polylines inherit the source object's look; dims go on DIMENSIONS."""
    code = load_code()
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
    assert '(perp:layer "DIMENSIONS"' in code, \
        "the DIMENSIONS layer must be created if missing"
    print("polylines inherit source properties, dims on DIMENSIONS layer")


def test_error_handler_cleans_up():
    code = load_code()
    handler = re.search(r"\(defun\s+\*error\*.*?\n\n", code, re.S)
    assert handler, "*error* handler not found"
    assert "perp:finish" in handler.group(0), \
        "*error* must route through the shared cleanup"
    assert "_End" in code and "_Begin" in code, \
        "the run must be wrapped in a single UNDO group"
    print("error handler routes through shared cleanup")


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


def main():
    test_parens_balanced()
    test_no_global_leaks()
    test_sysvars_saved_and_restored()
    test_dimension_style_handling()
    test_output_placement_and_properties()
    test_error_handler_cleans_up()
    test_straight_line_spacing()
    test_arc_length_spacing_across_a_corner()
    test_endpoint_never_overshoots()
    test_degenerate_paths()
    test_offsets_stay_perpendicular_to_the_original_line()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
