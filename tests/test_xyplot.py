#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for XYPLOT.lsp -- an X/Y sheet drawn twice.

The whole of c:XYPLOT is driven in the AutoLISP VM.  Unlike ABCDEF there
is nothing to solve here, so what these tests are about is that the
drawing says exactly what the sheet said, and that the two graphs stay
the two different things they are meant to be:

  * THE COORDINATES.  Every point lands at its own X/Y off the picked
    origin, in both graphs, negatives included.

  * THE CHAINS.  A chain is the gaps between consecutive offsets along an
    axis, with the origin as a stop wherever it falls among them.  Points
    sharing an offset share a stop -- and, crucially, are not LOST doing
    it: the sort is written longhand because vl-sort drops elements its
    comparison calls equal, which would quietly delete one of two points
    on the same X.  That is the failure this file exists to catch.

  * THE SPLIT BETWEEN THE GRAPHS.  Only graph 1 carries ab_pt blocks.
    Two ab_pt copies of one survey would hand ABHD the same pool twice,
    so graph 2's markers must be plain POINTs on their own layer, and the
    handoff must pre-select graph 1's points and only those.

  * THE SKIPPED ROWS.  A row missing a coordinate is named, not guessed.

Usage:  python3 tests/test_xyplot.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_xyplot.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Sym  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LSP = os.path.join(REPO, 'lisp', 'xyplot', 'XYPLOT.lsp')

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


STUBS = r'''
(defun vl-string-search (pat s / n m i found)
  (setq n (strlen pat) m (strlen s) i 1 found nil)
  (while (and (null found) (<= i (1+ (- m n))))
    (if (= (substr s i n) pat) (setq found (1- i)))
    (setq i (1+ i)))
  found)
(defun getfiled (title dflt ext flags) "C:\\jobs\\xy.csv")
(defun alert (s) (setq *alert* s))
(defun sssetfirst (a b) (setq *preselect* b))
(defun open (path mode) (setq *rpt-path* path *rpt* '()) 'FP)
(defun write-line (s fp) (setq *rpt* (cons s *rpt*)) s)
(defun close (fp) nil)
'''

#: a survey with the awkward bits in it on purpose: the origin itself, two
#: points sharing an X, two sharing a Y, and one in negative X
SHEET = [("1", 0.0, 0.0), ("2", 120.0, 18.5), ("3", 240.25, 96.0),
         ("4", 240.25, 180.0), ("5", 96.0, 210.75), ("6", -36.0, 120.0),
         ("7", -36.0, 50.0)]


def run(pts=SHEET, answer="No", with_abhd=True, origin=(0.0, 0.0)):
    vm = VM()
    lispvm.BUILTINS[Sym('vl-cmdf')] = lispvm.BUILTINS[Sym('command')]
    vm.loads(STUBS)
    vm.load(LSP)
    if with_abhd:
        vm.loads('(defun c:ABHD () nil)')
    body = " ".join('(list "%s" %s %s)'
                    % (nm, 'nil' if x is None else repr(x),
                       'nil' if y is None else repr(y)) for nm, x, y in pts)
    # the sheet reader is Excel COM and file I/O; the rows go in directly
    vm.loads("(defun xyp:read-file (file) (list %s))" % body)
    vm.run('c:XYPLOT', [[origin[0], origin[1], 0.0], answer])
    return vm


def report(vm):
    return list(reversed(vm.globals.get(Sym('*rpt*')) or []))


def kind_of(vm, e):
    return next((p.b for p in vm.entdata[e] if getattr(p, 'a', None) == 0),
                None)


def xy_of(vm, e):
    return next((tuple(p[1:3]) for p in vm.entdata[e]
                 if isinstance(p, list) and p[0] == 10), None)


def survey_points(vm):
    """{label: (x, y)} off graph 1's ab_pt blocks."""
    out, pending = {}, None
    for e in vm.entities:
        k = kind_of(vm, e)
        if k == 'INSERT':
            pending = xy_of(vm, e)
        elif k == 'ATTRIB' and pending:
            label = next((p.b for p in vm.entdata[e]
                          if getattr(p, 'a', None) == 1), '')
            out[label] = pending
            pending = None
    return out


def graph2_points(vm):
    return [xy_of(vm, e) for e in vm.entities
            if kind_of(vm, e) == 'POINT' and vm.layer_of(e) == 'XYPLOT-POINTS']


def dims(vm):
    """Every dimension as (p13, p14, rotation)."""
    out = []
    for e in vm.entities:
        if kind_of(vm, e) != 'DIMENSION':
            continue
        d = vm.entdata[e]
        p13 = next(tuple(p[1:3]) for p in d if isinstance(p, list) and p[0] == 13)
        p14 = next(tuple(p[1:3]) for p in d if isinstance(p, list) and p[0] == 14)
        rot = next(p.b for p in d if getattr(p, 'a', None) == 50)
        out.append((p13, p14, rot))
    return out


# ------------------------------------------------------- the coordinates --

def test_graph1_is_the_sheet():
    print("\ngraph 1 puts every point at its own X/Y off the origin")
    vm = run()
    got = survey_points(vm)
    check("every row is drawn", len(got) == len(SHEET))
    for nm, x, y in SHEET:
        check("%s at (%g, %g)" % (nm, x, y),
              nm in got and abs(got[nm][0] - x) < 1e-6
              and abs(got[nm][1] - y) < 1e-6)


def test_the_origin_is_where_it_was_picked():
    print("\nthe origin lands where it was picked, and carries the plot")
    vm = run(origin=(1000.0, -500.0))
    got = survey_points(vm)
    for nm, x, y in SHEET:
        check("%s offset from the picked origin" % nm,
              abs(got[nm][0] - (1000.0 + x)) < 1e-6
              and abs(got[nm][1] - (-500.0 + y)) < 1e-6)


def test_graph2_is_the_same_points_moved_aside():
    print("\ngraph 2 is the same points, one clear gutter to the right")
    vm = run()
    g1 = survey_points(vm)
    g2 = graph2_points(vm)
    check("graph 2 has the same number of points", len(g2) == len(g1))
    shifts = set()
    for nm, x, y in SHEET:
        near = [p for p in g2 if abs(p[1] - g1[nm][1]) < 1e-6]
        check("%s has a twin at the same height" % nm, bool(near))
        if near:
            shifts.add(round(near[0][0] - g1[nm][0], 6))
    check("all shifted by one constant X offset (%s)" % sorted(shifts),
          len(shifts) == 1)
    check("...and the shift clears graph 1 entirely",
          shifts and list(shifts)[0] > 240.25 - -36.0)


# ------------------------------------------------------------ the chains --

def test_chains_span_every_distinct_offset():
    print("\nthe chains run through every distinct offset, plus the origin")
    vm = run()
    xs = sorted({0.0} | {round(p[1], 4) for p in SHEET})
    ys = sorted({0.0} | {round(p[2], 4) for p in SHEET})
    horizontal = [d for d in dims(vm) if abs(d[2]) < 1e-9]
    vertical = [d for d in dims(vm) if abs(d[2]) > 1e-9]
    check("X chain has one rung per gap (%d, want %d)"
          % (len(horizontal), len(xs) - 1), len(horizontal) == len(xs) - 1)
    check("Y chain has one rung per gap (%d, want %d)"
          % (len(vertical), len(ys) - 1), len(vertical) == len(ys) - 1)
    # the rungs, laid end to end, must cover the full spread of the data
    if horizontal:
        span = sum(abs(b[0] - a[0]) for a, b, _ in horizontal)
        check("X rungs add up to the full X spread (%.2f)" % span,
              abs(span - (max(xs) - min(xs))) < 1e-6)
    if vertical:
        span = sum(abs(b[1] - a[1]) for a, b, _ in vertical)
        check("Y rungs add up to the full Y spread (%.2f)" % span,
              abs(span - (max(ys) - min(ys))) < 1e-6)


def test_points_sharing_an_offset_are_not_lost():
    print("\ntwo points on one offset share a rung and neither disappears")
    # 3 and 4 share X=240.25; 6 and 7 share X=-36.0.  A vl-sort here would
    # drop one of each pair on the way past.
    vm = run()
    got = survey_points(vm)
    for nm in ("3", "4", "6", "7"):
        check("%s survived the chain sort" % nm, nm in got)
    horizontal = [d for d in dims(vm) if abs(d[2]) < 1e-9]
    starts = [round(a[0], 4) for a, b, _ in horizontal]
    ends = [round(b[0], 4) for a, b, _ in horizontal]
    for shared in (240.25, -36.0):
        check("X=%g is one stop, not two" % shared,
              (starts + ends).count(shared) <= 2)
    # and a shared offset must never produce a rung that spans nothing
    check("no rung measures zero",
          all(abs(b[0] - a[0]) > 1e-9 for a, b, _ in horizontal))


def test_chain_rungs_tie_back_to_real_points():
    print("\nevery rung's extension lines grow from points, not thin air")
    vm = run()
    anchors = set()
    for p in graph2_points(vm):
        anchors.add((round(p[0], 4), round(p[1], 4)))
    # the graph 2 origin is an anchor too
    g1 = survey_points(vm)
    shift = graph2_points(vm)[0][0] - g1["1"][0]
    anchors.add((round(shift, 4), 0.0))
    for a, b, _ in dims(vm):
        for pt in (a, b):
            check("rung end (%.2f, %.2f) sits on a point" % pt,
                  (round(pt[0], 4), round(pt[1], 4)) in anchors)


def test_a_single_point_sheet_still_draws():
    print("\na sheet with one point still produces both graphs")
    vm = run(pts=[("only", 48.0, 24.0)])
    check("the point is drawn", len(survey_points(vm)) == 1)
    check("it has a graph 2 twin", len(graph2_points(vm)) == 1)
    check("and both chains have exactly one rung", len(dims(vm)) == 2)


# ------------------------------------------------------- the graph split --

def test_only_graph1_is_a_survey():
    print("\nonly graph 1 carries ab_pt blocks")
    vm = run()
    on_points = [kind_of(vm, e) for e in vm.entities
                 if vm.layer_of(e) == 'POINTS']
    check("the POINTS layer holds only the block insert and its parts",
          set(on_points) <= {'INSERT', 'ATTRIB', 'SEQEND'})
    check("one insert per row, not two",
          on_points.count('INSERT') == len(SHEET))
    check("graph 2's markers are plain POINTs on their own layer",
          len(graph2_points(vm)) == len(SHEET))
    blocks = [next(p.b for p in vm.entdata[e] if getattr(p, 'a', None) == 2)
              for e in vm.entities if kind_of(vm, e) == 'INSERT']
    check("and every insert is ab_pt", set(blocks) == {'ab_pt'})


def test_labels_come_from_the_sheet():
    print("\npoints are labelled with the sheet's names, in both graphs")
    vm = run()
    attrs = [next(p.b for p in vm.entdata[e] if getattr(p, 'a', None) == 1)
             for e in vm.entities if kind_of(vm, e) == 'ATTRIB']
    check("graph 1 numbers match the sheet",
          attrs == [nm for nm, _, _ in SHEET])
    texts = [next(p.b for p in vm.entdata[e] if getattr(p, 'a', None) == 1)
             for e in vm.entities
             if kind_of(vm, e) == 'TEXT' and vm.layer_of(e) == 'XYPLOT-LABELS']
    check("graph 2 labels match the sheet",
          texts == [nm for nm, _, _ in SHEET])


def test_rows_missing_a_coordinate_are_named_not_guessed():
    print("\na row missing a coordinate is skipped and named")
    vm = run(pts=[("ok", 10.0, 20.0), ("nox", None, 30.0),
                  ("noy", 40.0, None), ("neither", None, None)])
    got = survey_points(vm)
    check("only the complete row is drawn", list(got) == ["ok"])
    text = "\n".join(report(vm))
    check("the report counts the skips", '3 row(s) skipped' in text)
    for nm, want in (("nox", "no X"), ("noy", "no Y"),
                     ("neither", "no X and Y")):
        check("%s is named as missing %s" % (nm, want),
              any(nm in l and want in l for l in report(vm)))


def test_report_carries_both_readings_of_every_value():
    print("\nthe report gives every offset in feet-inches and in inches")
    vm = run()
    text = "\n".join(report(vm))
    check("feet-inches are printed", "20'-0 1/4\"" in text)
    check("decimal inches are printed", "240.250" in text)
    check("a negative offset survives both ways",
          "-3'-0\"" in text and "-36.000" in text)
    check("the chain counts are reported", "X rungs" in text)
    path = vm.globals.get(Sym('*rpt-path*'))
    check("the report is written beside the sheet (%s)" % path,
          path == r'C:\jobs\xy_XYPLOT_report.txt')


# ------------------------------------------------------------ the handoff --

def test_abhd_handoff_takes_graph1_only():
    print("\nthe handoff offers ABHD graph 1's points, and only those")
    vm = run(answer="Yes")
    check("ABHD is started", ['_.ABHD'] in vm.commands)
    ss = vm.globals.get(Sym('*preselect*'))
    check("with graph 1's points and no others (%s of %d)"
          % (len(ss) - 1 if ss else None, len(SHEET)),
          ss is not None and len(ss) - 1 == len(SHEET))

    vm = run(answer="No")
    check("answering No starts nothing", ['_.ABHD'] not in vm.commands)

    vm = run(answer="Yes", with_abhd=False)
    check("ABHD not loaded: nothing is started",
          ['_.ABHD'] not in vm.commands)


def test_the_view_reset_runs():
    print("\nthe closing view reset runs instead of raising")
    vm = run()
    check("plan and zoom both ran",
          ['_.plan', '_World'] in vm.commands
          and ['_.zoom', '_Extents'] in vm.commands)


def main():
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print("XYPLOT.lsp runtime tests -- tier: %s" % tier)
    for fn in (test_graph1_is_the_sheet,
               test_the_origin_is_where_it_was_picked,
               test_graph2_is_the_same_points_moved_aside,
               test_chains_span_every_distinct_offset,
               test_points_sharing_an_offset_are_not_lost,
               test_chain_rungs_tie_back_to_real_points,
               test_a_single_point_sheet_still_draws,
               test_only_graph1_is_a_survey,
               test_labels_come_from_the_sheet,
               test_rows_missing_a_coordinate_are_named_not_guessed,
               test_report_carries_both_readings_of_every_value,
               test_abhd_handoff_takes_graph1_only,
               test_the_view_reset_runs):
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
