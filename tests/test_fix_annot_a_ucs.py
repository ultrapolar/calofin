"""A UCS moved or turned off the world: every click lands where it was
clicked.

getpoint answers in the CURRENT UCS; entmake reads group 10 as WORLD.
DIMSTAMP, DRONOTE, CONSTELLATION and BPCALLOUT all handed a raw click to
entmake, so with the UCS origin on a pool corner -- a common setup --
the stamp, the note, the whole constellation or the callout landed that
far from the click while the command said it was placed.  BPCALLOUT and
CDCALLOUT also matched the raw click against survey points, which are
world data, so the snap missed (BPCALLOUT) or took whichever point sat
nearest the bare UCS numbers (CDCALLOUT).

The VM's world is flat -- its (trans ...) is the identity -- so a UCS
is modelled HERE, for the length of one test: an origin and a turn,
applied by a trans that moves a point between code 0 (world) and codes
1 and 2 (the UCS; the display is taken to be plan to it).  An ename or
a vector is an OCS, which for flat drafting is the world.  Everything
else in the VM is untouched: (command ...) still takes its points as
given, which is how AutoCAD reads them -- in the UCS.

Run: python3 tests/test_fix_annot_a_ucs.py
"""

import math
import os
import sys
from contextlib import contextmanager

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import (VM, LispError, Ent, Dot, Sym, BUILTINS,  # noqa: E402
                    truthy)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, '..')

#: the files under test -- a table so a scratch runner can point it at
#: an older copy and watch these fail there
SRC = {
    'DIMSTAMP': os.path.join(REPO, 'lisp', 'dimstamp', 'DIMSTAMP.lsp'),
    'DRONOTE': os.path.join(REPO, 'lisp', 'dronote', 'DRONOTE.lsp'),
    'CONSTELLATION': os.path.join(REPO, 'lisp', 'constellation',
                                  'CONSTELLATION.lsp'),
    'BPCALLOUT': os.path.join(REPO, 'lisp', 'bpcallout', 'BPCALLOUT.lsp'),
    'CDCALLOUT': os.path.join(REPO, 'lisp', 'cdcallout', 'CDCALLOUT.lsp'),
}

#: the UCS most of these tests draw in: origin on a pool corner well off
#: the world origin, axes parallel to the world's
CORNER = (1000.0, 500.0)


# ---- the UCS model ----------------------------------------------------

class Ucs:
    """ORIGIN is the UCS origin in world coordinates, ANG the turn of
    its X axis from the world X axis, in radians."""

    def __init__(self, origin=(0.0, 0.0), ang=0.0):
        self.ox, self.oy = float(origin[0]), float(origin[1])
        self.c, self.s = math.cos(ang), math.sin(ang)

    def to_world(self, p, disp):
        x, y, z = p
        wx, wy = x * self.c - y * self.s, x * self.s + y * self.c
        if not disp:
            wx, wy = wx + self.ox, wy + self.oy
        return [wx, wy, z]

    def to_ucs(self, p, disp):
        x, y, z = p
        if not disp:
            x, y = x - self.ox, y - self.oy
        return [x * self.c + y * self.s, -x * self.s + y * self.c, z]


def _is_ucs(code):
    return isinstance(code, int) and not isinstance(code, bool) \
        and code in (1, 2)


@contextmanager
def in_ucs(origin=(0.0, 0.0), ang=0.0):
    u = Ucs(origin, ang)
    orig = BUILTINS[Sym('trans')]

    def _trans(vm, a):
        p = a[0]
        if not isinstance(p, list) or len(p) < 2:
            raise LispError(f"bad argument type: point {p!r}")
        p = [float(p[0]), float(p[1]), float(p[2]) if len(p) > 2 else 0.0]
        disp = len(a) > 3 and truthy(a[3])
        w = u.to_world(p, disp) if _is_ucs(a[1]) else p
        return u.to_ucs(w, disp) if _is_ucs(a[2]) else w

    BUILTINS[Sym('trans')] = _trans
    try:
        yield u
    finally:
        BUILTINS[Sym('trans')] = orig


# ---- reading the drawing back -----------------------------------------

def newvm(tool):
    vm = VM()
    vm.load(SRC[tool])
    return vm


def run(vm, cmd, script, label):
    try:
        vm.run(cmd, list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def as_dict(vm, e):
    d = {}
    for g in vm.entdata[e]:
        if isinstance(g, Dot):
            d.setdefault(g.a, g.b)
        elif isinstance(g, list) and g:
            d.setdefault(g[0], g[1] if len(g) == 2 else list(g[1:]))
    return d


def live(vm, etype=None, layer=None):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = as_dict(vm, e)
        if etype and d.get(0) != etype:
            continue
        if layer and str(d.get(8, '')).upper() != layer.upper():
            continue
        out.append(d)
    return out


def near(p, q, tol=1e-6):
    return all(abs(a - b) <= tol for a, b in zip(p, q))


def said(vm):
    return ''.join(str(x) for x in vm.printed)


# ---- DIMSTAMP ---------------------------------------------------------

def test_dimstamp_stamps_where_it_was_clicked():
    with in_ucs(CORNER):
        vm = newvm('DIMSTAMP')
        run(vm, 'c:DIMSTAMP', [(10.0, 20.0), '44', (300.0, 300.0), None],
            'dimstamp moved ucs')
    t = [d for d in live(vm, 'MTEXT', 'TEXT')]
    assert [d[1] for d in t] == ['44"', '44"'], t
    assert near(t[0][10], [1010.0, 520.0]), t[0][10]
    assert near(t[1][10], [1300.0, 800.0]), t[1][10]
    print("ok  DIMSTAMP      -> a moved UCS: each stamp lands on its click")


def test_dimstamp_ruler_is_drawn_where_its_rows_are_picked():
    """The ruler is laid out from VIEWCTR, a UCS point, and its hit test
    reads a UCS click -- so it has to be DRAWN in the UCS too, or it is
    off the screen while its rows still answer clicks nobody can see."""
    flat = newvm('DIMSTAMP')
    ents0, box0, rows0 = flat.loads('(ds:draw-ruler 352 nil)')
    with in_ucs(CORNER):
        vm = newvm('DIMSTAMP')
        ents, box, rows = vm.loads('(ds:draw-ruler 352 nil)')
    assert box == box0 and rows == rows0, (box, box0)
    assert len(ents) == len(ents0) > 0
    for e, e0 in zip(ents, ents0):
        d, d0 = as_dict(vm, e), as_dict(flat, e0)
        assert d[0] == d0[0]
        for code in (10, 11):
            if code in d0:
                want = [d0[code][0] + CORNER[0], d0[code][1] + CORNER[1]]
                assert near(d[code], want), (d[0], code, d[code], want)
    print("ok  DIMSTAMP      -> the ruler is drawn where its rows are"
          " picked")


def test_dimstamp_turned_ucs_reads_along_it():
    with in_ucs((0.0, 0.0), math.pi / 2):
        vm = newvm('DIMSTAMP')
        run(vm, 'c:DIMSTAMP', [(10.0, 0.0), '44', None], 'dimstamp turned')
    t = live(vm, 'MTEXT', 'TEXT')
    assert near(t[0][10], [0.0, 10.0]), t[0][10]
    assert abs(t[0][50] - math.pi / 2) < 1e-9, t[0][50]
    print("ok  DIMSTAMP      -> a turned UCS: the stamp reads along it")


# ---- DRONOTE ------------------------------------------------------------

def test_dronote_places_the_note_where_it_was_clicked():
    with in_ucs(CORNER):
        vm = newvm('DRONOTE')
        run(vm, 'c:DRONOTE', ['Board', (12.0, 34.0), None], 'dronote')
    t = live(vm, 'MTEXT')
    assert len(t) == 1 and near(t[0][10], [1012.0, 534.0]), t
    with in_ucs((0.0, 0.0), math.pi / 2):
        vm = newvm('DRONOTE')
        run(vm, 'c:DRONOTE', ['Board', (12.0, 0.0), None], 'dronote turned')
    t = live(vm, 'MTEXT')
    assert near(t[0][10], [0.0, 12.0]), t[0][10]
    assert abs(t[0][50] - math.pi / 2) < 1e-9, t[0][50]
    print("ok  DRONOTE       -> the note lands on its click, along the UCS")


# ---- CONSTELLATION ------------------------------------------------------

RECT = [(0.0, 120.0), (240.0, 120.0), (240.0, 0.0), (0.0, 0.0)]


def _cst_script(base, w=360.0, h=240.0):
    """A whole run over RECT's full chart: the space, the count, the
    base point, every pair in reading order (Enter takes the next one),
    no arcs, an outline, and Yes it looks right."""
    n = len(RECT)
    out = [w, h, n, base]
    for i in range(n):
        for j in range(i + 1, n):
            out += ['', math.dist(RECT[i], RECT[j])]
    return out + ['', 'Yes', 'Yes']


def _cst_points(vm):
    out, p = {}, None
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = as_dict(vm, e)
        if d.get(0) == 'INSERT':
            p = d[10]
        elif d.get(0) == 'ATTRIB' and p is not None:
            out[d[1]] = p
            p = None
    return out


def _cst_box(vm):
    boxes = [e for e in vm.entities if e not in vm.deleted
             and as_dict(vm, e).get(0) == 'LWPOLYLINE'
             and as_dict(vm, e).get(8) == 'CONSTELLATION-SPACE']
    assert len(boxes) == 1, boxes
    return [g[1:3] for g in vm.entdata[boxes[0]]
            if isinstance(g, list) and g and g[0] == 10]


def test_constellation_draws_off_the_base_point_clicked():
    for base, label in [([0.0, 0.0, 0.0], 'clicked 0,0'), (None, 'Enter')]:
        with in_ucs(CORNER):
            vm = newvm('CONSTELLATION')
            run(vm, 'c:CONSTELLATION', _cst_script(base), label)
        box = _cst_box(vm)
        assert near(box[0], [1000.0, 500.0]), (label, box)
        assert near(box[2], [1360.0, 740.0]), (label, box)
        pts = _cst_points(vm)
        assert len(pts) == 4, pts
        for p in pts.values():
            assert 1000.0 <= p[0] <= 1360.0 and 500.0 <= p[1] <= 740.0, \
                (label, pts)
        # every dimension measures between two of the points drawn
        for d in live(vm, 'DIMENSION'):
            assert any(near(d[13], p) for p in pts.values()), (d, pts)
            assert any(near(d[14], p) for p in pts.values()), (d, pts)
    print("ok  CONSTELLATION -> a moved UCS: drawn off the base point"
          " clicked, and Enter is the UCS origin")


def test_constellation_turned_ucs_is_square_to_it():
    with in_ucs((0.0, 0.0), math.pi / 2):
        vm = newvm('CONSTELLATION')
        run(vm, 'c:CONSTELLATION', _cst_script([0.0, 0.0, 0.0]), 'turned')
    box = _cst_box(vm)
    want = [[0.0, 0.0], [0.0, 360.0], [-240.0, 360.0], [-240.0, 0.0]]
    assert all(near(b, w) for b, w in zip(box, want)), box
    ins = live(vm, 'INSERT')
    assert ins and all(abs(d[50] - math.pi / 2) < 1e-9 for d in ins), ins
    print("ok  CONSTELLATION -> a turned UCS: the space is square to it")


def test_constellation_preview_is_drawn_off_the_base_point():
    """The starting oval and its letters are the legend the drafter
    names the pairs from -- drawn round the base point clicked, not
    round its bare UCS numbers.  The letters go through cst:text, which
    is cal:text's body in the grouped build, so its caller translates."""
    with in_ucs(CORNER):
        vm = newvm('CONSTELLATION')
        vm.loads('(cst:preview 4 360.0 240.0 (list 0.0 0.0))')
    for kind in ('CIRCLE', 'TEXT'):
        got = live(vm, kind, 'CONSTELLATION-GUIDE')
        assert len(got) == 4, (kind, got)
        for d in got:
            assert 1000.0 <= d[10][0] <= 1360.0, (kind, d[10])
            assert 500.0 <= d[10][1] <= 740.0, (kind, d[10])
    print("ok  CONSTELLATION -> the preview is drawn round the base point"
          " clicked")


# ---- BPCALLOUT ------------------------------------------------------------

def _ab_pt(vm, x, y, number):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'INSERT'), Dot(8, 'POINTS'), Dot(2, 'ab_pt'),
                     [10, float(x), float(y), 0.0]]
    att = Ent()
    vm.entities.append(att)
    vm.entdata[att] = [Dot(0, 'ATTRIB'), Dot(2, 'number'),
                       Dot(1, str(number))]
    return e


def test_bpcallout_snaps_and_rings_under_the_click():
    with in_ucs(CORNER):
        vm = newvm('BPCALLOUT')
        _ab_pt(vm, 1010.0, 520.0, 12)
        run(vm, 'c:BPCALLOUT', [(11.0, 21.0), None, (30.0, 40.0)],
            'bpcallout')
    rings = [d for d in live(vm, 'CIRCLE')]
    assert len(rings) == 1 and near(rings[0][10], [1010.0, 520.0]), rings
    assert 'Pt.12 ringed' in said(vm), said(vm)
    assert 'ringed where clicked' not in said(vm), said(vm)
    txt = live(vm, 'TEXT')
    assert len(txt) == 1 and near(txt[0][10], [1030.0, 540.0]), txt
    assert txt[0][1] == 'Pt.12 is bad', txt
    # a click on nothing is ringed where it was clicked -- in the world
    with in_ucs(CORNER):
        vm = newvm('BPCALLOUT')
        run(vm, 'c:BPCALLOUT', [(50.0, 60.0), None, None], 'bp unsnapped')
    rings = live(vm, 'CIRCLE')
    assert len(rings) == 1 and near(rings[0][10], [1050.0, 560.0]), rings
    print("ok  BPCALLOUT     -> a moved UCS: the snap finds the point, the"
          " ring and the text land under the clicks")


def test_bpcallout_enter_tucks_the_text_lower_right_in_the_ucs():
    """Enter at the text prompt tucks the callout right of and below the
    last ring -- as the drafter sees it, which in a turned UCS is not
    world +X / -Y.  Turned a quarter: the point at world (-20,10) is
    UCS (10,20), lower-right of it is UCS (20,10), world (-10,20).
    Stepped along the world axes it sat at (-10,0), a diagonal off the
    ring while it read along the UCS."""
    with in_ucs((0.0, 0.0), math.pi / 2):
        vm = newvm('BPCALLOUT')
        _ab_pt(vm, -20.0, 10.0, 12)
        run(vm, 'c:BPCALLOUT', [(10.0, 20.0), None, None], 'bp turned')
    rings = live(vm, 'CIRCLE')
    assert len(rings) == 1 and near(rings[0][10], [-20.0, 10.0]), rings
    txt = live(vm, 'TEXT')
    assert len(txt) == 1, txt
    assert near(txt[0][10], [-10.0, 20.0]), txt[0][10]
    assert abs(txt[0][50] - math.pi / 2) < 1e-9, txt[0][50]
    # and in a UCS only moved, Enter is the plain step it always was
    with in_ucs(CORNER):
        vm = newvm('BPCALLOUT')
        _ab_pt(vm, 1010.0, 520.0, 12)
        run(vm, 'c:BPCALLOUT', [(10.0, 20.0), None, None], 'bp moved')
    txt = live(vm, 'TEXT')
    assert len(txt) == 1 and near(txt[0][10], [1020.0, 510.0]), txt
    print("ok  BPCALLOUT     -> Enter tucks the callout lower-right of the"
          " ring in the UCS")


# ---- CDCALLOUT ------------------------------------------------------------

def test_cdcallout_a_click_takes_the_point_under_it():
    """Two points carry "7".  The click is on the one at world
    (1010,520); the other sits at (20,30), near the click's bare UCS
    numbers.  The DIMALIGNED is fed UCS points, as AutoCAD reads them."""
    with in_ucs(CORNER):
        vm = newvm('CDCALLOUT')
        vm.tables['DIMSTYLE'].add('CROSS DIMENSIONS')
        vm.sysvars['CLAYER'] = '0'
        vm.sysvars['DIMSTYLE'] = 'STANDARD'
        _ab_pt(vm, 1010.0, 520.0, 7)
        _ab_pt(vm, 20.0, 30.0, 7)
        _ab_pt(vm, 1100.0, 520.0, 8)
        run(vm, 'c:CDCALLOUT', ['7', [11.0, 21.0, 0.0], '8', None],
            'cdcallout')
    calls = [c for c in vm.commands if c and c[0] == '_.DIMALIGNED']
    assert len(calls) == 1, vm.commands
    first = calls[0][2]                         # "_non" <pt> ...
    assert near(first, [10.0, 20.0]), calls[0]
    print("ok  CDCALLOUT     -> a moved UCS: a click takes the doubled"
          " point under it")


TESTS = [
    test_dimstamp_stamps_where_it_was_clicked,
    test_dimstamp_ruler_is_drawn_where_its_rows_are_picked,
    test_dimstamp_turned_ucs_reads_along_it,
    test_dronote_places_the_note_where_it_was_clicked,
    test_constellation_draws_off_the_base_point_clicked,
    test_constellation_turned_ucs_is_square_to_it,
    test_constellation_preview_is_drawn_off_the_base_point,
    test_bpcallout_snaps_and_rings_under_the_click,
    test_bpcallout_enter_tucks_the_text_lower_right_in_the_ucs,
    test_cdcallout_a_click_takes_the_point_under_it,
]

if __name__ == '__main__':
    for t in TESTS:
        t()
    print("all annot-a UCS tests passed")
