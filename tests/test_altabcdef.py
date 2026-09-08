#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for ALTABCDEF.lsp -- the clockwise-corner point plotter.

ALTABCDEF is ABCDEF's sister for a sheet whose bottom corners are
labelled the other way round (A top-left, then CLOCKWISE: B top-right,
C bottom-RIGHT, D bottom-left).  The two conventions are not
interchangeable, so the corner order is the first thing this file
checks: the same tape distances placed under the wrong convention land
tens of inches away, which is exactly the failure that split the two
commands in the first place.

Until now no suite drove this command at all -- tests/test_cancel_paths.py
cancelled it in the file dialog and nothing else ran it, so its
arithmetic, its entities and its report were read by eye.  This runs
them, against surveys whose TRUE coordinates are known: points are
chosen inside the rectangle, their distances to the four corners
computed and rounded to the quarter inch a field tape actually reads,
and the command asked to find them again.

What is checked, in the order it matters:

  * THE ARITHMETIC, under the CLOCKWISE corner order.  Clean
    quarter-inch data comes back within rounding from four tapes, from
    three, and from two.  A pair from ADJACENT corners takes the root
    inside the rectangle rather than its mirror; a pair from OPPOSITE
    corners cannot -- both roots are inside and fit identically, so
    that row is plotted and NAMED rather than silently guessed at.

  * THE PARSER, including the repairs a scanned field sheet needs.  A
    fraction split across tokens ("34'-4 1 /4") used to lose its
    fraction here -- ABCDEF fixed that and this file did not, so the
    same sheet read 4 3/4 inches long through this command.  Both
    parsers are now asserted to agree, case for case.

  * THE FRAME IT DRAWS.  A closed polyline in perimeter order (a
    bow-tie is what the wrong order gives), corner letters where the
    corners are, and angles MEASURED off the drawn coordinates rather
    than a printed constant.

  * THE CONTINGENCIES.  Back at every question, Cancel in the dialog,
    a sheet with nothing usable in it, rows too thin to place, a
    frozen/locked/off output layer, UNDO switched off, an Esc
    mid-command, and the corner self-check refusing to plot.

  * THE KNOBS.  Every tunable at the top of the file is asserted to be
    live: change it and the drawing or the report changes to match.

Usage:  python3 tests/test_altabcdef.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_altabcdef.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, Dot, LispError, Sym  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
#: always the lisp/ path -- VM.load remaps it to shared/parts/ when
#: CALOFIN_LISP_ROOT says so, which is how one test covers both tiers.
LSP = os.path.join(REPO, 'lisp', 'altabcdef', 'ALTABCDEF.lsp')

failures = []


def check(label, cond, detail=''):
    print(('  ok   ' if cond else '  FAIL ') + label
          + (('  -- ' + detail) if detail and not cond else ''))
    if not cond:
        failures.append(label)


# ---------------------------------------------------------------- the VM --

#: AutoCAD entry points the VM has no opinion about.  open/read-line/close
#: serve a CSV from a list so the command's OWN reader can be driven --
#: the column matching and the dirty-value log are half of what it does.
STUBS = r'''
(defun vl-string-search (pat s / n m i found)
  (setq n (strlen pat) m (strlen s) i 1 found nil)
  (while (and (null found) (<= i (1+ (- m n))))
    (if (= (substr s i n) pat) (setq found (1- i)))
    (setq i (1+ i)))
  found)
(defun getfiled (title dflt ext flags) (setq *filter* ext) "C:\\jobs\\survey.csv")
(defun alert (s) (setq *alert* s))
(setq *csv* '())
(defun open (path mode) (setq *csv-left* *csv*) 'FP)
(defun read-line (fp / l)
  (if *csv-left*
    (progn (setq l (car *csv-left*) *csv-left* (cdr *csv-left*)) l)))
(defun close (fp) nil)
'''

W = 36 * 12 + 5.25          # 36'-5 1/4"
H = 22 * 12 + 0.25          # 22'-0 1/4"
WSTR, HSTR = "36'-5 1/4", "22'-0 1/4"
#: A B C D, CLOCKWISE from the top-left -- C is bottom-RIGHT here, which
#: is the whole difference between this command and ABCDEF.
CORNERS = [(0.0, 0.0), (W, 0.0), (W, -H), (0.0, -H)]
LOCKED, FROZEN = 4, 1


def quarter(v):
    """What a tape reads: the nearest quarter inch."""
    return round(v * 4.0) / 4.0


def tapes(x, y):
    return [quarter(math.hypot(x - cx, y - cy)) for cx, cy in CORNERS]


def lstr(s):
    """A python string as a LISP string literal."""
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def fresh(pre=''):
    vm = VM()
    lispvm.BUILTINS[Sym('vl-cmdf')] = lispvm.BUILTINS[Sym('command')]
    vm.loads(STUBS)
    if pre:
        vm.loads(pre)
    vm.load(LSP)
    return vm


def rowsrc(rows):
    return " ".join(
        '(list %s %s)' % (lstr(nm),
                          " ".join('nil' if d is None else repr(d) for d in ds))
        for nm, ds in rows)


def run(rows, script=None, pre='', post='', csv=None):
    """Drive c:ALTABCDEF over ROWS -- (name, [dA,dB,dC,dD]) with None for
    a blank cell -- and hand back the VM for inspection.  With CSV given,
    the command's own reader is left in place and fed those lines."""
    vm = fresh(pre)
    if csv is None:
        # the sheet reader is Excel COM and file I/O, neither of which is
        # what most of these tests are about; the rows go in directly
        vm.loads("(defun altabcdef:read-file (file maxd) (list %s))"
                 % rowsrc(rows))
    else:
        vm.loads("(setq *csv* '(%s))" % " ".join(lstr(l) for l in csv))
    if post:
        vm.loads(post)
    vm.run('c:ALTABCDEF',
           script if script is not None else [WSTR, HSTR, [0.0, 0.0, 0.0]])
    return vm


def said(vm):
    return "".join(vm.printed)


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


def ents(vm, etype):
    return [vm.entdata[e] for e in vm.entities
            if e not in vm.deleted and grp(vm.entdata[e], 0) == etype]


def points(vm):
    """Every plotted POINT node, in order."""
    return [tuple(grp(d, 10)[:2]) for d in ents(vm, 'POINT')]


def labels(vm):
    """{label text: (x, y)} off the TEXT entities on the label layer."""
    out = {}
    for d in ents(vm, 'TEXT'):
        if grp(d, 8) == 'ALTABCDEF-LABELS':
            out[grp(d, 1)] = tuple(grp(d, 10)[:2])
    return out


def report_rows(vm):
    """{name: (x, y, ndims, rms)} off the printed results table."""
    out = {}
    for ln in said(vm).splitlines():
        m = re.match(r'\s+(\S+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d)\s+'
                     r'([\d.]+)"', ln)
        if m:
            out[m.group(1)] = (float(m.group(2)), float(m.group(3)),
                               int(m.group(4)), float(m.group(5)))
    return out


def layer_flags(vm, name):
    rec = vm.tablerecs['LAYER'][name.upper()]
    return grp(vm.recdata[rec], 70) or 0


def layer_color(vm, name):
    rec = vm.tablerecs['LAYER'][name.upper()]
    return grp(vm.recdata[rec], 62)


def layer_src(name, color, flags=0):
    return ('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
            ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
            ' \'(62 . %d) \'(6 . "Continuous")))' % (name, flags, color))


# ------------------------------------------------------- the arithmetic --

def test_clean_tapes_under_the_clockwise_order():
    print("\nfour clean tapes: every point comes back where it started")
    truth = [("P1", 120.0, -60.0), ("P2", 300.0, -40.0), ("P3", 200.0, -150.0),
             ("P4", 60.0, -200.0), ("P5", 400.0, -220.0), ("P6", 30.0, -30.0)]
    vm = run([(nm, tapes(x, y)) for nm, x, y in truth])
    got = labels(vm)
    check("all six points drawn", len(points(vm)) == 6)
    worst = 0.0
    table = report_rows(vm)
    for nm, x, y in truth:
        rx, ry, ndims, rms = table[nm]
        worst = max(worst, math.hypot(rx - x, ry - y))
        check("%s used all four distances" % nm, ndims == 4)
        check("%s fits under 0.10\" (%.4f\")" % (nm, rms), rms < 0.10)
    # a quarter-inch tape cannot do better than an eighth of an inch of
    # rounding per reading; a fifth of an inch overall is the honest bar
    check("worst point within 0.20\" of truth (%.3f\")" % worst, worst < 0.20)
    check("every point carries its sheet label", set(got) == {n for n, _, _ in truth})


def test_the_corner_order_is_the_clockwise_one():
    print("\nC is bottom-RIGHT here, and the tapes prove it")
    # a point far into the bottom-right quadrant is CLOSE to C under this
    # command's order and FAR from it under ABCDEF's; solving these
    # distances the other way round would put it tens of inches out
    x, y = 380.0, -230.0
    vm = run([("P", tapes(x, y))])
    px, py = points(vm)[0]
    check("the point lands where the clockwise order puts it (%.2f, %.2f)"
          % (px, py), math.hypot(px - x, py - y) < 0.20)
    # the SAME distances read under ABCDEF's order (C bottom-left,
    # D bottom-right) describe a different point entirely -- which is why
    # the two conventions are two commands and not a keyword
    d = tapes(x, y)
    zres = min(sum((math.hypot(gx - cx, gy - cy) - dd) ** 2
                   for (cx, cy), dd in zip([(0.0, 0.0), (W, 0.0),
                                            (0.0, -H), (W, -H)], d))
               for gx in (px,) for gy in (py,))
    check("the same sheet read the other way round does NOT fit here"
          " (%.0f sq in)" % zres, zres > 100.0)


def test_three_and_two_tapes():
    print("\nthree distances and two: fewer readings, same answer")
    x, y = 300.0, -40.0
    d = tapes(x, y)
    # AB, BC, CD and DA are ADJACENT pairs -- their mirror answer falls
    # outside the rectangle, so the point is fixed.  A DIAGONAL pair is a
    # different animal and has a test of its own below.
    for label, given, n in (("ABC", [d[0], d[1], d[2], None], 3),
                            ("ABD", [d[0], d[1], None, d[3]], 3),
                            ("AB",  [d[0], d[1], None, None], 2),
                            ("BC",  [None, d[1], d[2], None], 2),
                            ("CD",  [None, None, d[2], d[3]], 2),
                            ("AD",  [d[0], None, None, d[3]], 2)):
        vm = run([("P", given)])
        px, py = points(vm)[0]
        off = math.hypot(px - x, py - y)
        check("%s places P within 0.5\" (%.3f\")" % (label, off), off < 0.5)
        check("%s reports how many it used" % label,
              report_rows(vm)["P"][2] == n)


def test_two_tapes_take_the_inside_root():
    print("\ntwo distances: the root inside the rectangle wins")
    # measured from the two TOP corners the mirror root sits above the top
    # edge -- outside the pool, and wrong by twice the depth
    for nm, x, y in (("P", 200.0, -40.0), ("Q", 90.0, -220.0),
                     ("R", 380.0, -130.0)):
        d = tapes(x, y)
        vm = run([(nm, [d[0], d[1], None, None])])
        px, py = points(vm)[0]
        check("%s: inside root taken, not the mirror (y=%.2f)" % (nm, py),
              -H - 0.5 <= py <= 0.5)
        check("%s: within 0.5\" of truth" % nm,
              math.hypot(px - x, py - y) < 0.5)


def test_a_diagonal_pair_answers_twice_and_says_so():
    print("\ntwo distances from OPPOSITE corners answer twice, and say so")
    # A and C are opposite corners here.  The mirror of the answer across
    # the A-C line fits the SAME two distances to the same hundredth and
    # lands inside the rectangle too, so the sheet does not say which of
    # the two the point is -- and the frame centre, which is what breaks
    # the tie, sits exactly between them.  Guessing silently is the one
    # thing a survey import must not do.
    x, y = 300.0, -40.0
    d = tapes(x, y)
    vm = run([("P", [d[0], None, d[2], None])])
    check("the point is still plotted", len(points(vm)) == 1)
    check("but the row is named on the command line",
          "fit a second point inside the frame" in said(vm), said(vm)[-300:])
    px, py = points(vm)[0]
    # whichever root came back, the other one fits the tapes as well
    ux, uy = W / math.hypot(W, H), -H / math.hypot(W, H)
    t = 2.0 * (px * ux + py * uy)
    mx, my = t * ux - px, t * uy - py
    for nm, (qx, qy) in (("the answer", (px, py)), ("its mirror", (mx, my))):
        ea = abs(math.hypot(qx, qy) - d[0])
        ec = abs(math.hypot(qx - W, qy + H) - d[2])
        check("%s fits both distances to a rounding (%.3f\", %.3f\")"
              % (nm, ea, ec), ea < 0.15 and ec < 0.15)
    check("and the mirror is inside the frame too -- that is the problem",
          0 <= mx <= W and -H <= my <= 0, "(%.1f, %.1f)" % (mx, my))
    # the regression this guards: the seed for a two-distance row is the
    # middle of the frame, which for a pair of opposite corners lies ON
    # the line between them, where both residual gradients point the same
    # way and the normal matrix is singular.  Least-squares therefore
    # stopped on its own seed and returned the frame CENTRE as the answer,
    # 34 inches of fit error and no flag but the RMS column.
    check("the answer is a real root, not the frame centre it seeded from",
          math.hypot(px - W / 2.0, py + H / 2.0) > 1.0,
          "(%.2f, %.2f)" % (px, py))
    check("...so the fit error is a rounding, not tens of inches (%.4f\")"
          % report_rows(vm)["P"][3], report_rows(vm)["P"][3] < 0.15)
    # an ADJACENT pair is not ambiguous and must not be flagged
    quiet = run([("P", [d[0], d[1], None, None])])
    check("an adjacent pair is not flagged",
          "fit a second point" not in said(quiet))


def test_a_bad_reading_shows_up_as_fit_error():
    print("\na bad reading is not hidden: the fit error carries it")
    d = tapes(300.0, -40.0)
    clean = report_rows(run([("P", d)]))["P"][3]
    d[2] += 6.0                       # one tape reads six inches long
    dirty = report_rows(run([("P", d)]))["P"][3]
    check("a clean row fits tightly (%.4f\")" % clean, clean < 0.10)
    check("a six-inch error shows as a large fit (%.3f\")" % dirty,
          dirty > 1.0)


def test_rows_with_too_little_are_skipped_not_guessed():
    print("\na row with fewer than two distances is skipped, not guessed at")
    d = tapes(120.0, -60.0)
    vm = run([("GOOD", d), ("ONE", [d[0], None, None, None]),
              ("NONE", [None, None, None, None])])
    drawn = set(labels(vm))
    check("the complete row is plotted", drawn == {"GOOD"})
    check("both thin rows are named on the command line",
          said(vm).count("distances given - skipped") == 2)
    check("and the total says so", "1 point(s) plotted, 2 skipped" in said(vm))


# ------------------------------------------------------------ the parser --

#: the dirty forms a scanned or re-typed field sheet comes back in.  Both
#: commands read the same handwriting, so both parsers must agree.
PARSER_CASES = [
    ('12\'-3 1/2"', 147.5),
    ("34'-4 1 /4", 412.25),        # fraction split by a stray space
    ('20\'-7 1/ 4"', 247.25),      # ...on the other side of the slash
    ('20\'-7 1 / 4"', 247.25),     # ...both sides
    ("13'-0 1 /4", 156.25),
    ('20\'-7 114"', 247.25),       # "/" scanned as a "1"
    ('28-7"', 343.0),              # missing foot mark
    ('101-10"', 130.0),            # foot mark scanned as a "1"
    ("26' -8\"", 320.0),
    ('1 1\'-IO 1/2"', 142.5),      # split feet, letters for digits
    ("9'", 108.0),
    ('3 1/2"', 3.5),
]


def parse(vm, raw, maxd=514.0):
    return vm.eval(lispvm.parse_all(
        '(altabcdef:ftin->in %s %s)' % (lstr(raw), maxd))[0])


def test_the_parser_reads_a_scanned_sheet():
    print("\nthe feet-inch parser, on the sheets it actually gets")
    vm = fresh()
    for raw, want in PARSER_CASES:
        got = parse(vm, raw)
        check("%-18s -> %s" % (lstr(raw), want),
              isinstance(got, float) and abs(got - want) < 1e-9, repr(got))


def test_both_parsers_agree():
    print("\nABCDEF and ALTABCDEF read the same handwriting the same way")
    # the split-fraction repair was ABCDEF's alone: this file read
    # "20'-7 1 / 4" as 252" -- nearly five inches long, silently
    other = os.path.join(REPO, 'lisp', 'abcdef', 'abcdef.lsp')
    vm = fresh()
    vm.load(other)
    for raw, _ in PARSER_CASES:
        a = vm.eval(lispvm.parse_all(
            '(abcdef:ftin->in %s 514.0)' % lstr(raw))[0])
        b = parse(vm, raw)
        check("%-18s both read %s" % (lstr(raw), a),
              isinstance(a, float) and isinstance(b, float)
              and abs(a - b) < 1e-9, "abcdef=%r alt=%r" % (a, b))


def test_impossible_and_corrupt_values_are_refused():
    print("\na value that cannot be a distance is left blank, not guessed")
    vm = fresh()
    for raw in ('600\'-0"', '-4\'-0"', '', '   ', 'not a number', '0'):
        got = parse(vm, raw)
        check("%-18s is refused" % lstr(raw), got is lispvm.NIL or got is None,
              repr(got))
    # ...and the foot-mark repair only fires when the value is impossible
    check("a plausible reading keeps its digits", parse(vm, '41-10"') == 502.0,
          repr(parse(vm, '41-10"')))


def test_the_correction_log_writes_the_repairs_back():
    print("\nevery risky repair is logged, in feet-inches")
    vm = fresh()
    for v, want in ((476.75, "39'-8 3/4\""), (412.25, "34'-4 1/4\""),
                    (130.0, "10'-10\""), (108.0, "9'-0\"")):
        got = vm.eval(lispvm.parse_all('(altabcdef:in->ftin %r)' % v)[0])
        check("%s -> %s" % (v, want), got == want, repr(got))


# ------------------------------------------------------- the sheet reader --

SHEET = [
    "POINT NAME,DIST FROM A,DIST FROM B,DIST FROM C,DIST FROM D",
    'P1,"10\'-0""","30\'-6 1/4""","28\'-0""","12\'-3"""',
    'P2,20\'-7 1 /4,"18\'-0""","22\'-4 1/2""","20\'-0"""',
    ',,,,',                       # a blank row: no name, no point
    'P3,"6\'-0""",,"31\'-0""",',  # only two distances, still placed
]


def test_the_command_reads_its_own_csv():
    print("\nthe CSV reader: columns by header, blanks, and the fix log")
    vm = run(None, csv=SHEET)
    drawn = set(labels(vm))
    check("every named row was read and placed", drawn == {"P1", "P2", "P3"},
          repr(sorted(drawn)))
    check("the nameless row is not a point", len(points(vm)) == 3)
    check("P3's two distances were enough", report_rows(vm)["P3"][2] == 2)
    check("the split fraction was repaired and logged",
          "dirty values cleaned before import" in said(vm)
          and "20'-7 1/4\"" in said(vm), said(vm)[-400:])


def test_columns_are_found_in_any_order():
    print("\nthe columns are found by their headers, in any order")
    swapped = [
        "DIST FROM D,DIST FROM C,POINT NAME,DIST FROM B,DIST FROM A",
        '"12\'-3""","28\'-0""",P1,"30\'-6 1/4""","10\'-0"""',
    ]
    a = run(None, csv=SHEET[:2])
    b = run(None, csv=swapped)
    pa, pb = points(a)[0], points(b)[0]
    check("the same row placed identically either way (%.3f, %.3f)"
          % (pb[0], pb[1]),
          math.hypot(pa[0] - pb[0], pa[1] - pb[1]) < 1e-6)


def test_a_sheet_with_nothing_usable_draws_nothing():
    print("\na sheet with no rows in it plots nothing and says so")
    vm = run(None, csv=["POINT NAME,DIST FROM A,DIST FROM B,"
                        "DIST FROM C,DIST FROM D"])
    check("no points", not points(vm))
    check("no frame either -- nothing was drawn at all",
          not ents(vm, 'LWPOLYLINE'))
    check("and it says so", "No usable rows found" in said(vm))


# -------------------------------------------------------------- the frame --

def test_the_frame_is_a_rectangle_in_perimeter_order():
    print("\nthe frame is one closed rectangle, not a bow-tie")
    vm = run([("P", tapes(120.0, -60.0))])
    poly = ents(vm, 'LWPOLYLINE')
    check("one closed 4-vertex polyline", len(poly) == 1
          and grp(poly[0], 90) == 4 and grp(poly[0], 70) == 1)
    verts = [tuple(p[1:3]) for p in poly[0]
             if isinstance(p, list) and p[0] == 10]
    check("drawn A -> B -> C -> D, which is the perimeter here",
          verts == [(0.0, 0.0), (W, 0.0), (W, -H), (0.0, -H)], repr(verts))
    # consecutive sides must be perpendicular -- a bow-tie or a
    # parallelogram fails this even when the vertex list looks plausible
    ok = True
    for i in range(4):
        ax, ay = verts[i]
        bx, by = verts[(i + 1) % 4]
        cx, cy = verts[(i + 2) % 4]
        dot = (bx - ax) * (cx - bx) + (by - ay) * (cy - by)
        ok = ok and abs(dot) < 1e-6
    check("every corner of the drawn polyline is a right angle", ok)


def test_the_corner_angles_are_measured_not_asserted():
    print("\nthe corner angles are measured off the drawn coordinates")
    vm = run([("P", tapes(120.0, -60.0))])
    line = [l for l in said(vm).splitlines() if 'measured' in l]
    check("the report says they were measured", len(line) == 1, repr(line))
    nums = re.findall(r'(\d+\.\d+) [/d]', said(vm).split('measured')[-1])
    check("all four corners measure 90 degrees (%s)" % nums,
          len(nums) == 4 and all(abs(float(a) - 90.0) < 0.01 for a in nums))
    # and it really is a measurement: a skewed corner reports as skewed
    got = vm.eval(lispvm.parse_all(
        '(altabcdef:corner-ang 0.0 0.0 10.0 0.0 10.0 10.0)')[0])
    check("a 45-degree corner measures 45 (%.2f)" % got, abs(got - 45.0) < 1e-9)


def test_the_corner_tags_sit_on_their_corners():
    print("\neach corner letter sits at the corner it names")
    vm = run([("P", tapes(120.0, -60.0))])
    tags = {}
    for d in ents(vm, 'TEXT'):
        if grp(d, 8) == 'ALTABCDEF-FRAME':
            tags[grp(d, 1)] = tuple(grp(d, 10)[:2])
    check("all four letters drawn", set(tags) == set("ABCD"), repr(sorted(tags)))
    th = max(W, H) / 120.0
    for letter, (cx, cy) in zip("ABCD", CORNERS):
        x, y = tags[letter]
        check("%s is within a couple of text heights of its corner" % letter,
              math.hypot(x - cx, y - cy) < th * 3.0)


def test_the_self_check_refuses_to_plot_a_bad_frame():
    print("\na frame that is not the entered rectangle stops the run")
    good = fresh()
    ok = good.eval(lispvm.parse_all(
        '(altabcdef:frame-check 0.0 0.0 %r 0.0 %r %r 0.0 %r %r %r)'
        % (W, W, -H, -H, W, H))[0])
    check("the documented corner layout is accepted", ok is lispvm.NIL,
          repr(ok))
    # the parallelogram that took ABCDEF down in the field
    bad = good.eval(lispvm.parse_all(
        '(altabcdef:frame-check 0.0 0.0 %r 0.0 %r %r %r %r %r %r)'
        % (W, 2 * W, -H, W, -H, W, H))[0])
    check("a parallelogram is rejected, and named (%s)" % bad,
          isinstance(bad, str) and bad)
    # end to end: when the check fails, NOTHING is drawn
    vm = run([("P", tapes(120.0, -60.0))],
             post='(defun altabcdef:frame-check (a b c d e f g h w y)'
                  ' "A-B measures 1.00\\" but should be 2.00\\"")')
    check("nothing at all is drawn", not vm.entities, repr(vm.entities[:3]))
    check("the abort is on the command line", "ABORT" in said(vm))
    check("...and in an alert the drafter cannot miss",
          'self-check FAILED' in (vm.globals.get(Sym('*alert*')) or ''))


# ------------------------------------------------- layers and the drawing --

def test_the_output_layers_are_made_and_used():
    print("\nthe three output layers, and what goes on each")
    vm = run([("P", tapes(120.0, -60.0))])
    for name, color in (('ALTABCDEF-FRAME', 1), ('ALTABCDEF-POINTS', 2),
                        ('ALTABCDEF-LABELS', 3)):
        check("%s exists, colour %d" % (name, color),
              name in vm.tables['LAYER'] and layer_color(vm, name) == color)
    check("the point node and its marker circle are on POINTS",
          all(grp(d, 8) == 'ALTABCDEF-POINTS'
              for d in ents(vm, 'POINT') + ents(vm, 'CIRCLE')))
    check("one marker circle per point", len(ents(vm, 'CIRCLE')) == 1)
    check("nothing was put on the shared POINTS layer that ABHD reads",
          'POINTS' not in vm.tables['LAYER'])


def test_a_frozen_or_locked_output_layer_is_repaired():
    print("\nan output layer that is off, frozen or locked is restored")
    vm = run([("P", tapes(120.0, -60.0))],
             pre=layer_src('ALTABCDEF-POINTS', -2, FROZEN | LOCKED))
    check("it is thawed and unlocked",
          not layer_flags(vm, 'ALTABCDEF-POINTS') & (FROZEN | LOCKED))
    check("and switched back on", layer_color(vm, 'ALTABCDEF-POINTS') == 2)
    check("and the drafter is told it had to be",
          'ALTABCDEF-POINTS was off, frozen or locked' in said(vm))
    check("the points really did land on it",
          all(grp(d, 8) == 'ALTABCDEF-POINTS' for d in ents(vm, 'POINT')))


# ----------------------------------------------------- asking and backing --

def test_back_reopens_the_previous_question():
    print("\nBack at any question re-opens the one before it")
    # H -> back to W -> answer again; then the base point -> back to H
    vm = run([("P", tapes(120.0, -60.0))],
             script=[WSTR, "B", WSTR, HSTR, "Back", HSTR, [0.0, 0.0, 0.0]])
    check("the run still finishes and plots", len(points(vm)) == 1)
    asked = [p for p, _ in vm.prompts]
    check("the width was asked twice",
          sum('A-B' in p for p in asked) == 2, repr(asked))
    check("the height was asked three times -- once, backed into, once more",
          sum('A-D' in p for p in asked) == 3, repr(asked))
    check("both typed prompts say how to go back",
          all('B = back' in p for p in asked if 'Dimension' in p))


def test_back_at_the_first_dimension_returns_to_the_file_dialog():
    print("\nBack at the first dimension re-opens the file dialog")
    vm = run([("P", tapes(120.0, -60.0))],
             script=["B", WSTR, HSTR, [0.0, 0.0, 0.0]])
    check("the dialog was opened twice",
          said(vm).count("--- Rectangle A(top-left)") == 2)
    check("and the run completed", len(points(vm)) == 1)


def test_a_bad_dimension_is_re_asked():
    print("\na dimension that is not a positive length is re-asked")
    vm = run([("P", tapes(120.0, -60.0))],
             script=["", "-5'", "0", WSTR, HSTR, [0.0, 0.0, 0.0]])
    check("it kept asking until it got one", len(points(vm)) == 1)
    check("and said why each time",
          said(vm).count("enter a positive dimension") == 3)


def test_enter_at_the_base_point_takes_the_origin():
    print("\nEnter at the insertion point takes 0,0")
    vm = run([("P", tapes(120.0, -60.0))], script=[WSTR, HSTR, None])
    verts = [tuple(p[1:3]) for p in ents(vm, 'LWPOLYLINE')[0]
             if isinstance(p, list) and p[0] == 10]
    check("corner A is at the origin", verts[0] == (0.0, 0.0), repr(verts[0]))


def test_the_base_point_moves_the_whole_plot():
    print("\nthe picked point is where corner A goes")
    off = (1000.0, 500.0, 0.0)
    vm = run([("P", tapes(120.0, -60.0))], script=[WSTR, HSTR, list(off)])
    px, py = points(vm)[0]
    check("the point moved with the frame (%.2f, %.2f)" % (px, py),
          abs(px - (off[0] + 120.0)) < 0.2 and abs(py - (off[1] - 60.0)) < 0.2)


def test_cancel_in_the_dialog_draws_nothing():
    print("\nCancel in the file dialog ends the run, quietly")
    vm = fresh('(defun getfiled (t d e f) nil)')
    vm.loads("(defun altabcdef:read-file (file maxd) nil)")
    vm.run('c:ALTABCDEF', [])
    check("nothing drawn", not vm.entities)
    check("no dimension was asked for", not vm.prompts)
    check("and it says it was cancelled", "Cancelled" in said(vm))


def test_the_file_dialog_offers_the_sheet_types():
    print("\nthe dialog offers exactly the formats the reader handles")
    vm = run([("P", tapes(120.0, -60.0))])
    check("xlsx, xls, xlsm and csv",
          vm.globals.get(Sym('*filter*')) == "xlsx;xls;xlsm;csv",
          repr(vm.globals.get(Sym('*filter*'))))


# ------------------------------------------------------- the run's manners --

def test_one_undo_group_opened_and_closed():
    print("\nthe whole plot is one undo group")
    vm = run([("P", tapes(120.0, -60.0))])
    marks = [c for c in vm.commands if c and c[0] == '_.UNDO']
    check("opened once and closed once",
          marks == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']], repr(marks))


def test_no_undo_group_when_undo_is_off():
    print("\nwith UNDO off, no group is opened -- _Begin would error")
    vm = fresh()
    vm.sysvars['UNDOCTL'] = 4                 # bit 1 clear: undo disabled
    vm.loads("(defun altabcdef:read-file (file maxd) (list %s))"
             % rowsrc([("P", tapes(120.0, -60.0))]))
    vm.run('c:ALTABCDEF', [WSTR, HSTR, [0.0, 0.0, 0.0]])
    check("no undo command was issued",
          not [c for c in vm.commands if c and c[0] == '_.UNDO'])
    check("but the point was still plotted", len(points(vm)) == 1)


def test_esc_partway_through_goes_through_the_handler():
    print("\nEsc partway through is handled, and closes the group")
    def esc(vm):
        raise LispError('Function cancelled', vm)
    vm = fresh()
    vm.handle_errors = True
    vm.loads("(defun altabcdef:read-file (file maxd) (list %s))"
             % rowsrc([("P", tapes(120.0, -60.0))]))
    before = dict(vm.sysvars)
    vm.run('c:ALTABCDEF', [WSTR, HSTR, esc])
    check("the cancel reached the command's own handler, once",
          list(vm.handled_errors) == ['Function cancelled'],
          repr(vm.handled_errors))
    check("no setting was left changed",
          {k: v for k, v in vm.sysvars.items() if before.get(k) != v} == {})
    check("nothing said 'error' -- a plain cancel is silent",
          not re.search(r'\berror\b', said(vm), re.I))
    # run() itself refuses to return with a group still open, so reaching
    # here at all is the assertion that the handler closed it


def test_the_view_reset_survives_its_own_catch():
    print("\nthe closing view reset runs instead of raising")
    vm = run([("P", tapes(120.0, -60.0))])
    check("plan and zoom both ran",
          ['_.plan', '_World'] in vm.commands
          and ['_.zoom', '_Extents'] in vm.commands)


def test_the_version_is_announced():
    print("\nthe command says which build it is")
    vm = run([("P", tapes(120.0, -60.0))])
    ver = vm.globals.get(Sym('*altabcdef-version*'))
    check("on load", ("ALTABCDEF %s loaded" % ver) in said(vm))
    check("and at the top of the run", ("\nALTABCDEF %s\n" % ver) in said(vm))
    vm2 = fresh()
    vm2.run('c:ALTABCDEFVER', [])
    check("ALTABCDEFVER prints it too", ver in said(vm2))


# -------------------------------------------------------------- the knobs --

def test_every_knob_is_live():
    print("\nthe tunables at the top of the file really are the knobs")
    d = tapes(120.0, -60.0)

    vm = run([("P", d)], pre='', post='(setq altabcdef:*frame-layer* "F2"'
                              ' altabcdef:*point-layer* "P2"'
                              ' altabcdef:*label-layer* "L2"'
                              ' altabcdef:*frame-color* 5'
                              ' altabcdef:*point-color* 6'
                              ' altabcdef:*label-color* 7)')
    check("the layer names are knobs",
          {'F2', 'P2', 'L2'} <= vm.tables['LAYER'],
          repr(sorted(vm.tables['LAYER'])))
    check("so are the colours they are created with",
          (layer_color(vm, 'F2'), layer_color(vm, 'P2'),
           layer_color(vm, 'L2')) == (5, 6, 7))
    check("and the entities follow them",
          all(grp(e, 8) == 'P2' for e in ents(vm, 'POINT')))

    base = run([("P", d)])
    big = run([("P", d)], post='(setq altabcdef:*text-div* 30.0)')
    hb = grp(ents(base, 'TEXT')[0], 40)
    hg = grp(ents(big, 'TEXT')[0], 40)
    check("*text-div* sets the text height (%.2f -> %.2f)" % (hb, hg),
          hg > hb * 3.0)

    tiny = run([("P", d)], post='(setq altabcdef:*text-div* 1.0e6'
                                ' altabcdef:*text-min* 3.0)')
    lab = [t for t in ents(tiny, 'TEXT') if grp(t, 8) == 'ALTABCDEF-LABELS']
    check("*text-min* is the floor under it",
          abs(grp(lab[0], 40) - 3.0) < 1e-9, repr(grp(lab[0], 40)))

    wide = run([("P", d)], post='(setq altabcdef:*marker-scale* 2.0)')
    check("*marker-scale* sets the marker radius",
          grp(ents(wide, 'CIRCLE')[0], 40)
          > grp(ents(base, 'CIRCLE')[0], 40) * 4.0)

    strict = run([("P", [d[0], d[1], None, None])],
                 post='(setq altabcdef:*min-tapes* 3)')
    check("*min-tapes* decides what is too thin to place",
          not points(strict) and "fewer than 3 distances" in said(strict))

    vm = fresh('(setq altabcdef:*fractions* (list 2 4))')
    check("*fractions* bounds the fraction rebuild: 1/4 still reads",
          abs(parse(vm, '20\'-7 114"') - 247.25) < 1e-9)
    vm = fresh()
    vm.loads('(setq altabcdef:*fractions* (list 2))')
    check("...and a denominator not listed is never invented",
          abs(parse(vm, '20\'-7 114"') - (20 * 12 + 7 + 114)) < 1e-9,
          repr(parse(vm, '20\'-7 114"')))

    vm = fresh()
    vm.loads('(setq altabcdef:*log-denom* 4)')
    check("*log-denom* rounds the correction log",
          vm.eval(lispvm.parse_all('(altabcdef:in->ftin 476.78)')[0])
          == "39'-8 3/4\"")

    vm = fresh()
    vm.loads('(setq altabcdef:*hdr-dist* (list "OFF A" "OFF B" "OFF C"'
             ' "OFF D") altabcdef:*hdr-name* (list "STATION"))')
    kinds = [vm.eval(lispvm.parse_all('(altabcdef:col-of %s)' % lstr(h))[0])
             for h in ("OFF A", "STATION", "DIST FROM A")]
    check("*hdr-dist* / *hdr-name* name the columns",
          [str(k) for k in kinds[:2]] == ['a', 'name'] and kinds[2] is lispvm.NIL,
          repr(kinds))

    vm = fresh()
    vm.loads('(setq altabcdef:*file-types* "csv")')
    vm.loads("(defun altabcdef:read-file (file maxd) (list %s))"
             % rowsrc([("P", d)]))
    vm.run('c:ALTABCDEF', [WSTR, HSTR, [0.0, 0.0, 0.0]])
    check("*file-types* is what the dialog offers",
          vm.globals.get(Sym('*filter*')) == "csv")

    loose = run([("P", d)], post='(setq altabcdef:*frame-tol* 1.0e-9)')
    check("*frame-tol* is the self-check's tolerance, and passes at 1e-9",
          len(points(loose)) == 1)


def main():
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print("ALTABCDEF.lsp runtime tests -- tier: %s" % tier)
    for fn in (test_clean_tapes_under_the_clockwise_order,
               test_the_corner_order_is_the_clockwise_one,
               test_three_and_two_tapes,
               test_two_tapes_take_the_inside_root,
               test_a_diagonal_pair_answers_twice_and_says_so,
               test_a_bad_reading_shows_up_as_fit_error,
               test_rows_with_too_little_are_skipped_not_guessed,
               test_the_parser_reads_a_scanned_sheet,
               test_both_parsers_agree,
               test_impossible_and_corrupt_values_are_refused,
               test_the_correction_log_writes_the_repairs_back,
               test_the_command_reads_its_own_csv,
               test_columns_are_found_in_any_order,
               test_a_sheet_with_nothing_usable_draws_nothing,
               test_the_frame_is_a_rectangle_in_perimeter_order,
               test_the_corner_angles_are_measured_not_asserted,
               test_the_corner_tags_sit_on_their_corners,
               test_the_self_check_refuses_to_plot_a_bad_frame,
               test_the_output_layers_are_made_and_used,
               test_a_frozen_or_locked_output_layer_is_repaired,
               test_back_reopens_the_previous_question,
               test_back_at_the_first_dimension_returns_to_the_file_dialog,
               test_a_bad_dimension_is_re_asked,
               test_enter_at_the_base_point_takes_the_origin,
               test_the_base_point_moves_the_whole_plot,
               test_cancel_in_the_dialog_draws_nothing,
               test_the_file_dialog_offers_the_sheet_types,
               test_one_undo_group_opened_and_closed,
               test_no_undo_group_when_undo_is_off,
               test_esc_partway_through_goes_through_the_handler,
               test_the_view_reset_survives_its_own_catch,
               test_the_version_is_announced,
               test_every_knob_is_live):
        try:
            fn()
        except LispError as e:
            check("%s raised: %s" % (fn.__name__, e), False)

    print("\n%d check(s) failed" % len(failures) if failures
          else "\nall checks passed")
    for f in failures:
        print("  - " + f)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
