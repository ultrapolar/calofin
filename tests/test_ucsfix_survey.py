#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The survey tools' clicks, under a UCS that is not World.

getpoint answers in the drafter's UCS; a survey point's position, read
off its INSERT with entget, is World.  Every tool here measured one
against the other, and every test it had ran in World, where the two
are one frame and nothing can tell:

  * ABHD, ABLOBF, CABHD, FITABHD and LHD share one "pick it or type its
    number" question (<prefix>:askpoint).  It handed the raw click to
    <prefix>:cand-nearest against World candidates, so under a moved
    UCS every click was "No survey point there" -- or, nearer the UCS
    origin, the wrong point -- and a declaration, a break line or an
    omission named something the drafter never clicked;
  * ABFIND / ABMOVE / ABPCREATE did the same at the AB-line pick, the
    stake pick, the point pick and the suggestion pick, read the side
    of the A-B line off the raw click, and entmade the hand-placed note
    at the raw UCS numbers -- as World, somewhere else entirely.

Each check sets its own UCS with vm.set_ucs -- moved AND turned, so a
frame mixed up shows as a wrong point, a wrong side or a wrong place --
clicks in UCS numbers, as AutoCAD hands them back, and FAILS on the
files as they were before the fix (SRC holds the paths, so the same
checks run against HEAD's copies).

Run: python3 tests/test_ucsfix_survey.py
"""

import math
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

from lispvm import VM, Dot, LispError, Sym  # noqa: E402

LISP = os.path.join(REPO_DIR, 'lisp')

#: the file each check loads -- a dict so the same checks can be run
#: against another copy of a file
SRC = {
    'ABHD': os.path.join(LISP, 'abhd', 'abhd.lsp'),
    'ABLOBF': os.path.join(LISP, 'ablobf', 'ABLOBF.lsp'),
    'CABHD': os.path.join(LISP, 'cabhd', 'CABHD.lsp'),
    'FITABHD': os.path.join(LISP, 'fitabhd', 'FITABHD.lsp'),
    'LHD': os.path.join(LISP, 'lhd', 'lhd.lsp'),
    'ABFIND': os.path.join(LISP, 'abfind', 'ABFIND.lsp'),
}

#: the UCS every check below runs under
UCS_ORIGIN = (1000.0, 500.0, 0.0)
UCS_TURN = math.radians(30.0)

FAILS = []


def check(label, cond, detail=''):
    print(('  ok   ' if cond else '  FAIL ') + label
          + (('  -- ' + str(detail)) if (detail and not cond) else ''))
    if not cond:
        FAILS.append(label)


def turned(vm):
    vm.set_ucs(UCS_ORIGIN, UCS_TURN)
    return vm


def click(vm, wpt):
    """What getpoint hands back for a click on the World spot WPT: its
    numbers in the current UCS."""
    return list(vm.wcs_to_ucs([float(wpt[0]), float(wpt[1]), 0.0]))


def run(vm, cmd, script):
    """Drive one command.  A script that falls out of step with the
    questions -- as the old code made it, a selection handed to a
    getpoint and measured -- is returned as the failure it is, not
    raised, so every check below still runs."""
    try:
        vm.run(cmd, list(script))
        return None
    except (LispError, TypeError, ValueError) as e:
        return '%s: %s' % (type(e).__name__, e)


def said(vm):
    return ''.join(vm.printed)


def dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


def live(vm, kind, layer=None):
    return [e for e in vm.entities
            if e not in vm.deleted and dxf(vm, e, 0) == kind
            and (layer is None
                 or str(dxf(vm, e, 8) or '').upper() == layer.upper())]


def near(a, b, tol=1e-6):
    return a is not None and math.dist(list(a)[:2], list(b)[:2]) < tol


# ---------------------------------------------------------------------
# The five fit tools' one survey-point question
# ---------------------------------------------------------------------

def ring(n=12, a=144.0, b=84.0):
    return [(a * math.cos(2.0 * math.pi * i / n),
             b * math.sin(2.0 * math.pi * i / n)) for i in range(n)]


RING = ring()


def add_points(vm, pts, lay='POINTS'):
    """One ab_pt INSERT per point, numbered from 1 by its attribute --
    positions in World, as entget reads them back."""
    for i, p in enumerate(pts, start=1):
        vm.loads('(entmake (list \'(0 . "INSERT") \'(2 . "ab_pt")'
                 ' (cons 8 "%s") (list 10 %.6f %.6f 0.0)))'
                 % (lay, p[0], p[1]))
        vm.loads('(entmake (list \'(0 . "ATTRIB") (cons 8 "%s")'
                 ' \'(2 . "number") (cons 1 "%d")))' % (lay, i))


#: (tool, prefix, the snap it is asked with, the candidates).  FITABHD
#: asks about the points of the fit it already holds, World numbers
#: off the selection; the others collect the drawing's survey points.
ASKPOINT = (
    ('ABHD', 'pf', '*PF-SNAP*', '(pf:collect-points)'),
    ('ABLOBF', 'abl', '*ABL-SNAP*', '(abl:collect-points)'),
    ('CABHD', 'cab', '*CAB-SNAP*', '(cab:collect-points)'),
    ('LHD', 'lh', '*LH-SNAP*', '(lh:collect-points)'),
    ('FITABHD', 'fit', 'fit:*snap*',
     "'(" + ' '.join('((%.6f %.6f) "%d")' % (p[0], p[1], i)
                     for i, p in enumerate(RING, start=1)) + ')'),
)


def asker(vm, pfx):
    """The question as the loaded tier spells it.  A standalone file
    carries its own <prefix>:askpoint; in the grouped build the mirror
    swaps every one of them for the library's cal:askpoint, so under
    CALOFIN_LISP_ROOT=shared the tool's own name is undefined and the
    copy the drafter actually runs is the library's -- which is the one
    this check has to reach there."""
    own = Sym('%s:askpoint' % pfx)
    fn = vm.globals.get(own)
    if isinstance(fn, tuple) and fn and fn[0] == 'defun':
        return str(own)
    return 'cal:askpoint'


def check_askpoint(tool, pfx, snap, cands):
    """A click two inches off Pt.4 names Pt.4.  The typed "9" after it
    is only there for the old code, whose click found nothing: it keeps
    the question from running out of answers, and names a point the
    click did not."""
    vm = VM()
    vm.load(SRC[tool])
    turned(vm)
    add_points(vm, RING)
    p4 = RING[3]
    # asked straight, not through run(): the fixed code leaves the "9"
    # unread, and run() would call that a script out of step
    vm.script = [click(vm, (p4[0] + 2.0, p4[1] - 1.0)), '9']
    vm.prompts = []
    fn = asker(vm, pfx)
    try:
        got, err = vm.loads('(%s "  Survey point - pick it or'
                            ' type its number" nil nil %s %s)'
                            % (fn, cands, snap)), None
    except LispError as e:
        got, err = None, str(e)
    check("%s: a click on Pt.4 under a turned UCS names Pt.4 (%s)"
          % (tool, fn),
          err is None and got and got[1] == '4'
          and 'No survey point there' not in said(vm),
          err or (got, said(vm)[-160:]))


def check_abhd_wall():
    """The whole command: ABHD's straight wall, its two ends clicked
    under a turned UCS.  The old code re-asked each click, took the
    'No' after them as an answer to the wrong question, and fell out of
    step with the script altogether."""
    vm = VM()
    vm.load(SRC['ABHD'])
    turned(vm)
    for nm, col in (('POINTS', 7), ('POOL', 4)):
        vm.loads('(entmake (list \'(0 . "LAYER")'
                 ' \'(100 . "AcDbSymbolTableRecord")'
                 ' \'(100 . "AcDbLayerTableRecord") (cons 2 "%s")'
                 ' \'(70 . 0) (cons 62 %d) \'(6 . "Continuous")))'
                 % (nm, col))
    first = len(vm.entities)
    add_points(vm, RING)
    ents = [e for e in vm.entities[first:] if dxf(vm, e, 0) == 'INSERT']
    err = run(vm, 'c:ABHD',
              [None, None, None, None,
               'Yes', click(vm, RING[0]), click(vm, RING[6]), 'No',
               'No', 'No', ents, None, 'None'])
    check("ABHD: a wall's two ends clicked under a turned UCS are "
          "Pt.1 and Pt.7",
          err is None and 'Wall Pt.1 - Pt.7' in said(vm)
          and '1 straight wall(s) noted' in said(vm)
          and 'No survey point there' not in said(vm),
          err or said(vm)[-300:])


# ---------------------------------------------------------------------
# ABFIND / ABMOVE / ABPCREATE
# ---------------------------------------------------------------------

A = (0.0, 0.0)
B = (240.0, 0.0)


def cross(a, b, north=True):
    """Where a tape of A off stake A meets one of B off stake B."""
    d = B[0] - A[0]
    x = (d * d + a * a - b * b) / (2.0 * d)
    y = math.sqrt(a * a - x * x)
    return (x, y if north else -y)


P17 = cross(253.0, 222.0)            # 21'-1" off A, 18'-6" off B
P200 = cross(200.0, 180.0)

#: a second survey on the same sheet, a hundred feet east
A2 = (1200.0, 0.0)
B2 = (1440.0, 0.0)
L1P1 = (120.0, 100.0)
L2P1 = (1320.0, 150.0)


def abf_vm():
    vm = VM()
    vm.load(SRC['ABFIND'])
    vm.tables['DIMSTYLE'].add('CROSS DIMENSIONS')
    vm.tables['BLOCK'] = {'ab_pt'}
    vm.tables['LAYER'].add('POINTS')
    vm.sysvars['CLAYER'] = '0'
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    return turned(vm)


def ab_pt(vm, p, number):
    vm.loads('(entmake (list \'(0 . "INSERT") \'(8 . "POINTS")'
             ' \'(2 . "ab_pt") (list 10 %.6f %.6f 0.0)))' % (p[0], p[1]))
    vm.loads('(entmake (list \'(0 . "ATTRIB") \'(8 . "POINTS")'
             ' \'(2 . "number") (cons 1 "%s")))' % number)


def dims(vm):
    return live(vm, 'DIMENSION')


def tie_ends(vm):
    """(stake end, point end) of every tie drawn, World."""
    return [(dxf(vm, d, 13), dxf(vm, d, 14)) for d in dims(vm)]


def notes(vm):
    return [(dxf(vm, e, 10), dxf(vm, e, 1)) for e in live(vm, 'TEXT')
            if str(dxf(vm, e, 1) or '').startswith('- ')]


def check_abpcreate_line_pick():
    """Two AB lines: a click along L2's tie takes L2 -- it was measured
    raw against the World ties and took L1."""
    vm = abf_vm()
    for p, n in ((A, 'A'), (B, 'B'), (L1P1, 1), (A2, 'A'), (B2, 'B'),
                 (L2P1, 1)):
        ab_pt(vm, p, n)
    mid = ((A2[0] + B2[0]) * 0.5 + 10.0, 3.0)
    err = run(vm, 'c:ABPCREATE', [click(vm, mid), 160.0, 160.0, '9', None])
    ends = tie_ends(vm)
    check("ABPCREATE: a click along L2's tie ties the new point to A2/B2",
          err is None and len(ends) == 2 and near(ends[0][0], A2)
          and near(ends[1][0], B2), err or ends)


def check_abfind_stake_snap():
    """A stake the drawing does not name is clicked, and a click by a
    survey point takes the point."""
    vm = abf_vm()
    ab_pt(vm, A, 'A')
    ab_pt(vm, B, 'BEE')              # named, but not "B"
    ab_pt(vm, P17, 17)
    err = run(vm, 'c:ABFIND',
              [click(vm, (B[0] + 3.0, B[1] + 2.0)), '17', 'No', None])
    ends = tie_ends(vm)
    check("ABFIND: a stake clicked beside a point under a turned UCS "
          "takes that point",
          err is None and len(ends) == 2 and near(ends[1][0], B),
          err or ends)


def check_abfind_stake_click():
    """...and a click on nothing is the stake itself, where it was
    clicked: the ties used to run to the UCS numbers read as World."""
    vm = abf_vm()
    ab_pt(vm, A, 'A')
    ab_pt(vm, P17, 17)
    spot = (B[0] + 3.0, B[1] + 2.0)
    err = run(vm, 'c:ABFIND', [click(vm, spot), '17', 'No', None])
    ends = tie_ends(vm)
    check("ABFIND: a stake clicked on nothing under a turned UCS is "
          "tied from the spot clicked",
          err is None and len(ends) == 2 and near(ends[1][0], spot),
          err or ends)


def check_abfind_point_pick():
    """The point itself clicked, rather than its number typed."""
    vm = abf_vm()
    for p, n in ((A, 'A'), (B, 'B'), (P17, 17)):
        ab_pt(vm, p, n)
    err = run(vm, 'c:ABFIND',
              [click(vm, (P17[0] - 2.0, P17[1] + 1.0)), 'No', None])
    ends = tie_ends(vm)
    check("ABFIND: a click on Pt.17 under a turned UCS ties Pt.17",
          err is None and len(ends) == 2 and near(ends[0][0], A)
          and near(ends[0][1], P17), err or ends)


def _suggestion(vm, tag):
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   "'(%r %r 0.0))" % (P17[0], P17[1]))
    return {c[6]: c for c in got}[tag][5]


def check_abmove_suggestion_click():
    """ABMOVE's suggestion markers are World; a click on R1B's takes
    R1B."""
    vm = abf_vm()
    for p, n in ((A, 'A'), (B, 'B'), (P17, 17)):
        ab_pt(vm, p, n)
    r1b = _suggestion(vm, 'R1B')
    err = run(vm, 'c:ABMOVE',
              ['17', click(vm, (r1b[0] + 0.15, r1b[1] + 0.15)), None])
    got = [t for _, t in notes(vm)]
    check("ABMOVE: a click on the R1B marker under a turned UCS takes R1B",
          err is None
          and got == ['- Moved Pt.17 B from 18\'-6" to 18\'-5"'],
          err or (got, said(vm)[-200:]))


def check_abmove_note_spot():
    """The note placed by hand lands where it was placed: it is
    entmade, and entmake reads World."""
    vm = abf_vm()
    for p, n in ((A, 'A'), (B, 'B'), (P17, 17)):
        ab_pt(vm, p, n)
    spot = (900.0, 900.0)
    err = run(vm, 'c:ABMOVE', ['17', 'R2B', click(vm, spot)])
    got = notes(vm)
    check("ABMOVE: a note placed by hand under a turned UCS lands on "
          "the spot picked",
          err is None and len(got) == 1 and near(got[0][0], spot),
          err or got)


def check_abpcreate_side_click():
    """Nothing but the stakes plotted: the side of A-B the pool is on
    is clicked.  The spot is north of the line in World and south of
    it in the turned UCS's numbers, so reading the raw click names the
    wrong side and plots the point mirrored across the line."""
    vm = abf_vm()
    ab_pt(vm, A, 'A')
    ab_pt(vm, B, 'B')
    spot = (300.0, 25.0)
    pk = click(vm, spot)
    assert spot[1] > 0.0 > pk[1], "the spot must straddle the two frames"
    err = run(vm, 'c:ABPCREATE', [200.0, 180.0, pk, '1', None])
    ins = live(vm, 'INSERT')
    got = dxf(vm, ins[-1], 10) if ins else None
    check("ABPCREATE: the side clicked under a turned UCS is the side "
          "the point is plotted on",
          err is None and near(got, P200, 1e-4), err or (got, P200))


def main():
    print("the fit tools' survey-point question, under a turned UCS")
    for row in ASKPOINT:
        check_askpoint(*row)
    check_abhd_wall()
    print("\nABFIND / ABMOVE / ABPCREATE, under a turned UCS")
    check_abpcreate_line_pick()
    check_abfind_stake_snap()
    check_abfind_stake_click()
    check_abfind_point_pick()
    check_abmove_suggestion_click()
    check_abmove_note_spot()
    check_abpcreate_side_click()
    if FAILS:
        print("\n%d check(s) FAILED" % len(FAILS))
        return 1
    print("\nall survey UCS checks passed")
    return 0


if __name__ == '__main__':
    sys.exit(main())
