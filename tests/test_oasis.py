"""Runtime tests: load the real OASIS.lsp into the AutoLISP VM and drive
c:OASIS with scripted answers.  AutoLISP cannot run outside AutoCAD, so
this is where a wrong arity, an unbound function or a nil reaching
(distance ...) has to die.

The reference numbers are read off the drawing OASIS was written from
(a 40'-0" x 20'-0" oasis with 8'/11'/9' bulges and 6'/3'/5' tangent
radii, drawing units inches): the six arcs the routine computes must
land on the six arcs that drawing already contains, to 1e-6".

Script values answer the interactive calls in order: eight getdist
measurements, the Yes/No dimension question, then the getpoint base
point.  Run: python3 tests/test_oasis.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import (VM, LispError, Ent, Dot, Sym, BUILTINS, NIL,  # noqa: E402
                    parse_all)

LSP = os.path.join(os.path.dirname(__file__), '..', 'lisp', 'oasis',
                   'OASIS.lsp')

TOL = 1.0e-6


# ---- builtins the shared VM does not carry yet ------------------------
# entmakex: entmake that returns the new entity name; tblobjname: the
# entity name of a table record.  The canonical ensure-layer of
# STANDARDS.md section 5 needs both.

def _alist_dict(alist):
    d = {}
    for p in alist:
        if isinstance(p, Dot):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


def _entmakex(vm, a):
    alist = a[0]
    d = _alist_dict(alist)
    if d.get(0) in ('LAYER', 'LTYPE'):
        vm.tables[d[0]].add(d[2])
        rec = Ent()
        vm.entdata[rec] = list(alist)
        vm.layer_records[d[2].upper()] = rec
        return rec
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = list(alist)
    return e


def _tblobjname(vm, a):
    return vm.layer_records.get(a[1].upper(), NIL)


BUILTINS[Sym('entmakex')] = _entmakex
BUILTINS[Sym('tblobjname')] = _tblobjname


# ---- the reference drawing -------------------------------------------
#: (name, centre, radius, start angle, end angle) of the six arcs, in
#: the counter-clockwise order OASIS draws them.  Centres are relative
#: to the envelope's bottom-left corner and angles are DEGREES, as the
#: DXF stores them; OASIS works in radians, so the test converts.
#: X = 480 (40'), Y = 240 (20'); bulges 96 / 132 / 108 (8' / 11' / 9');
#: tangent radii 72 / 36 / 60 (6' / 3' / 5').
REF_X, REF_Y = 480.0, 240.0
REF_BULGES = (96.0, 132.0, 108.0)          # left, top, right
REF_TANGENTS = (72.0, 36.0, 60.0)          # top-left, top-right, bottom-center
REF_ARCS = [
    ('left',          (96.0000000000, 96.0000000000),  96.0,
     85.8916555993, 329.6659338609),
    ('bottom-center', (230.6428859721, 17.2136226425), 60.0,
     32.7105392913, 149.6659338609),
    ('right',         (372.0000000000, 108.0000000000), 108.0,
     212.7105392913, 105.1509908911),
    ('top-right',     (334.3636363636, 246.9946190765), 36.0,
     235.8273636603, 285.1509908911),
    ('top',           (240.0000000000, 108.0000000000), 132.0,
     55.8273636603, 130.3069641965),
    ('top-left',      (108.0359749648, 263.5683004230), 72.0,
     265.8916555993, 310.3069641965),
]

#: the eight measurements that draw the reference pool, in the order
#: OASIS asks them.  The base point pick comes first, so a whole run is
#: [base] + REF_MEASURE.
REF_MEASURE = [REF_X, REF_Y] + list(REF_BULGES) + list(REF_TANGENTS)


def script(base=(0.0, 0.0), measure=None, variant='Center'):
    """A whole run: which shape, where it goes, then the eight
    measurements."""
    return [variant, base] + list(REF_MEASURE if measure is None else measure)


#: the drawing the TOP RIGHT BULGE variant was read off: 36'-11" x 28'-8",
#: bulges 9' left / 8' top-right / 9' right, tangents 8' top-left,
#: 8' right-side, 10' bottom-center.  Its third bulge is tucked into the
#: corner, tangent to the top AND the right bound.
TR_X, TR_Y = 443.0, 344.0
TR_MEASURE = [TR_X, TR_Y, 108.0, 96.0, 108.0, 96.0, 96.0, 120.0]


# ---- scaffolding ------------------------------------------------------

def newvm(style=True):
    vm = VM()
    vm.layer_records = {}
    if style:
        vm.tables['DIMSTYLE'].add('CROSS DIMENSIONS')
    vm.load(LSP)
    return vm


def run(vm, script, label):
    try:
        vm.run('c:OASIS', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def made(vm, etype):
    """Every surviving entity of one type, as a group-code dict."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = _alist_dict(vm.entdata[e])
        if d.get(0) == etype:
            out.append(d)
    return out


def cmds(vm, name):
    return [c for c in vm.commands if c and c[0] == name]


def arcs_of(vm):
    """The POOL's six arcs as (centre, radius, start, end), in creation
    order, angles in degrees so they read against the reference table.

    Only the surviving arcs count -- every preview is erased -- and the
    pool is drawn before the check drawing beside it, so the first six
    are the pool's."""
    out = []
    for d in made(vm, 'ARC'):
        c = d[10]
        out.append(((c[0], c[1]), d[40],
                    math.degrees(d[50]) % 360.0, math.degrees(d[51]) % 360.0))
    return out[:6]


def check_arcs_of(vm):
    """The check drawing's six, which follow the pool's."""
    out = []
    for d in made(vm, 'ARC'):
        c = d[10]
        out.append(((c[0], c[1]), d[40]))
    return out[6:]


def pt_on(c, r, deg):
    a = math.radians(deg)
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def close(a, b, tol=TOL):
    return abs(a - b) <= tol


def solved(vm, w, h, rl, rt, rr, ftl, ftr, fbc):
    """Call oasis:solve inside the VM and hand back what it built."""
    return vm.loads('(oasis:solve %s "Center")'
                    % " ".join("%.10f" % v
                               for v in (w, h, rl, rt, rr, ftl, ftr, fbc)))


def crossing_pairs(vm, *dims):
    """The pairs of arcs oasis:crossings says run through each other."""
    r = vm.loads('(oasis:crossings (oasis:solve %s "Center"))'
                 % " ".join("%.10f" % v for v in dims))
    return set() if r is None else {tuple(sorted(p)) for p in r}


def overruns(vm, w, h, *radii):
    """What oasis:overruns says reaches past the envelope."""
    r = vm.loads('(oasis:overruns (oasis:solve %s "Center") %.6f %.6f)'
                 % (" ".join("%.6f" % v for v in (w, h) + radii), w, h))
    return [] if r is None else [(x[0], x[2], x[1]) for x in r]


class fake_trans(object):
    """Swap the VM's identity `trans` for a real UCS while a test runs.

    zdir is the UCS Z axis in world terms (tilted when it is not (0,0,1));
    rot turns the UCS about Z and org shifts its origin, so a point coming
    back is what AutoCAD would hand a routine under that UCS."""

    def __init__(self, rot=0.0, org=(0.0, 0.0, 0.0), zdir=(0.0, 0.0, 1.0)):
        self.rot, self.org, self.zdir = rot, org, zdir

    def __enter__(self):
        self.saved = BUILTINS.get(Sym('trans'))
        rot, org, zdir = self.rot, self.org, self.zdir

        def _t(vm, a):
            p = [float(v) for v in a[0]]
            while len(p) < 3:
                p.append(0.0)
            if list(a[1:3]) != [1, 0]:          # only UCS -> WCS is modelled
                return p
            if p[:3] == [0.0, 0.0, 1.0] and len(a) > 3 and a[3] is not NIL:
                return list(zdir)
            c, s = math.cos(rot), math.sin(rot)
            q = [p[0] * c - p[1] * s, p[0] * s + p[1] * c, p[2]]
            if len(a) > 3 and a[3] is not NIL:
                return q                        # a displacement: no origin
            return [q[0] + org[0], q[1] + org[1], q[2] + org[2]]

        BUILTINS[Sym('trans')] = _t
        return self

    def __exit__(self, *exc):
        BUILTINS[Sym('trans')] = self.saved
        return False


class at_each_prompt(object):
    """Snapshot the drawing as it stands at every measurement prompt.

    The preview is redrawn before each question and erased before the
    next, so this is the only way to see it: wrap getdist, and record
    what is on screen at the moment the question is put."""

    def __enter__(self):
        self.shots = []
        self.saved = BUILTINS[Sym('getdist')]

        def _g(vm, a):
            self.shots.append(
                [(e, dict(_alist_dict(vm.entdata[e])))
                 for e in vm.entities if e not in vm.deleted])
            return self.saved(vm, a)

        BUILTINS[Sym('getdist')] = _g
        return self

    def __exit__(self, *exc):
        BUILTINS[Sym('getdist')] = self.saved
        return False

    def shot(self, k, etype=None):
        """Everything alive at question k, optionally of one type."""
        return [d for _, d in self.shots[k]
                if etype is None or d.get(0) == etype]


# ---- tests ------------------------------------------------------------

def test_reference_drawing():
    """The six arcs land on the reference drawing's six arcs."""
    vm = newvm()
    run(vm, script(), 'reference')
    got = arcs_of(vm)
    assert len(got) == 6, got
    for (name, c, r, a0, a1), (gc, gr, ga0, ga1) in zip(REF_ARCS, got):
        assert close(gc[0], c[0]) and close(gc[1], c[1]), (name, gc, c)
        assert close(gr, r), (name, gr, r)
        # the ends may come back at 359.999.. vs 0.0 either side of the
        # wrap, so compare them as angles, not as numbers
        for got_a, want_a in ((ga0, a0), (ga1, a1)):
            d = abs((got_a - want_a + 180.0) % 360.0 - 180.0)
            assert d <= 1.0e-6, (name, got_a, want_a)
    print("ok  reference   -> six arcs match the 40x20 oasis drawing")


def test_outline_closes():
    """Consecutive arcs share an endpoint: the perimeter is one closed
    curve, not six arcs that nearly meet."""
    vm = newvm()
    run(vm, script(), 'closure')
    got = arcs_of(vm)
    # an arc is drawn counter-clockwise from start to end whichever way
    # the walk runs, so a bulge hands over at its END and a reverse arc
    # at its START
    bulge = [n in ('left', 'right', 'top') for n, _, _, _, _ in REF_ARCS]
    worst = 0.0
    for i, (c, r, a0, a1) in enumerate(got):
        leave = pt_on(c, r, a1 if bulge[i] else a0)
        j = (i + 1) % 6
        nc, nr, na0, na1 = got[j]
        arrive = pt_on(nc, nr, na0 if bulge[j] else na1)
        worst = max(worst, math.dist(leave, arrive))
    assert worst <= TOL, worst
    print("ok  closure     -> all six joints meet (worst %.2e\")" % worst)


def test_tangent_continuity():
    """Every joint is smooth: the two arcs share a tangent there, which
    is the whole point of a continuous-tangent pool."""
    vm = newvm()
    run(vm, script(), 'tangency')
    got = arcs_of(vm)
    bulge = [n in ('left', 'right', 'top') for n, _, _, _, _ in REF_ARCS]
    worst = 0.0
    for i, (c, r, a0, a1) in enumerate(got):
        j = (i + 1) % 6
        nc, nr, na0, na1 = got[j]
        joint = pt_on(c, r, a1 if bulge[i] else a0)
        # both centres and the joint are collinear at an external
        # tangency, and the two centres sit on opposite sides of it
        v1 = (c[0] - joint[0], c[1] - joint[1])
        v2 = (nc[0] - joint[0], nc[1] - joint[1])
        cross = abs(v1[0] * v2[1] - v1[1] * v2[0]) / (r * nr)
        worst = max(worst, cross)
    assert worst <= 1.0e-9, worst
    print("ok  tangency    -> every joint is tangent-continuous")


def test_fills_the_envelope():
    """The outline touches all four bounds the user gave and crosses
    none of them -- they are absolute."""
    vm = newvm()
    run(vm, script(), 'envelope')
    xs, ys = [], []
    for c, r, a0, a1 in arcs_of(vm):
        sweep = (a1 - a0) % 360.0
        angs = [a0, a1] + [k for k in (0.0, 90.0, 180.0, 270.0)
                           if (k - a0) % 360.0 <= sweep]
        for a in angs:
            p = pt_on(c, r, a)
            xs.append(p[0])
            ys.append(p[1])
    assert close(min(xs), 0.0), min(xs)
    assert close(min(ys), 0.0), min(ys)
    assert close(max(xs), REF_X), max(xs)
    assert close(max(ys), REF_Y), max(ys)
    print("ok  envelope    -> outline fills 0,0 - %g,%g exactly"
          % (REF_X, REF_Y))


def test_layers_and_dimensions():
    vm = newvm()
    run(vm, script(), 'layers')
    assert all(d[8] == 'POOL' for d in made(vm, 'ARC')), made(vm, 'ARC')
    dims = made(vm, 'DIMENSION')
    assert all(d[8] == 'DIMENSION' for d in dims), dims
    assert len(cmds(vm, '_.DIMLINEAR')) == 2, vm.commands     # overall X, Y
    assert len(cmds(vm, '_.DIMRADIUS')) == 6, vm.commands     # one per arc
    assert len(cmds(vm, '_.DIMALIGNED')) == 18, vm.commands   # check drawing
    for lay in ('POOL', 'DIMENSION', 'POOL-GUIDE'):
        assert lay in vm.tables['LAYER'], vm.tables['LAYER']
    print("ok  layers      -> arcs on POOL, 2 linear + 6 radius + 18 check"
          " dims")


def test_dimension_values():
    """The two overall dims are hooked to the points that really touch
    the envelope, so they read the X and Y that were asked for."""
    vm = newvm()
    run(vm, script(), 'dim values')
    lin = cmds(vm, '_.DIMLINEAR')
    horiz = [c for c in lin if '_H' in c][0]
    vert = [c for c in lin if '_V' in c][0]
    assert close(abs(horiz[1][0] - horiz[2][0]), REF_X), horiz
    assert close(abs(vert[1][1] - vert[2][1]), REF_Y), vert
    print("ok  dim values  -> overall dims measure %g and %g"
          % (REF_X, REF_Y))


def test_radius_dims_hook_the_arcs():
    """Each radius dim picks the arc it belongs to, at a point on that
    arc, and is dragged clear of the water."""
    vm = newvm()
    run(vm, script(), 'radius dims')
    arcs = [e for e in vm.entities
            if e not in vm.deleted
            and _alist_dict(vm.entdata[e]).get(0) == 'ARC'][:6]
    picked = []
    for c in cmds(vm, '_.DIMRADIUS'):
        ent, tip = c[1][0], c[1][1]
        d = _alist_dict(vm.entdata[ent])
        picked.append(ent)
        assert close(math.dist(tip[:2], d[10][:2]), d[40]), (tip, d[40])
    assert sorted(picked, key=lambda e: arcs.index(e)) == arcs, picked
    print("ok  radius dims -> one per arc, picked on the arc")


def test_base_point_moves_everything():
    vm = newvm()
    run(vm, script((1000.0, -250.0)), 'base point')
    for (name, c, r, a0, a1), (gc, gr, _, _) in zip(REF_ARCS, arcs_of(vm)):
        assert close(gc[0], c[0] + 1000.0), (name, gc)
        assert close(gc[1], c[1] - 250.0), (name, gc)
    print("ok  base point  -> the whole pool lands on the pick")


def test_enter_takes_the_origin():
    vm = newvm()
    run(vm, script(None), 'enter base')
    assert close(arcs_of(vm)[0][0][0], 96.0)
    print("ok  base <0,0>  -> Enter draws at the origin")


def test_back_reasks():
    """Back steps one question up and the re-answer is the one used."""
    vm = newvm()
    # answer Y as 300, back out of the left bulge, give Y as 240 instead
    run(vm, ['Center', (0.0, 0.0), REF_X, 300.0, 'Back', REF_Y]
        + REF_MEASURE[2:], 'back')
    top = [a for a in arcs_of(vm) if close(a[1], 132.0)][0]
    assert close(top[0][1], REF_Y - 132.0), top
    print("ok  back        -> Back re-asks and the new answer wins")


def test_back_at_the_first_question_stays_put():
    """Back is not offered at the first question; typing it anyway must
    not fall through it."""
    vm = newvm()
    vm.script = list(script())
    vm.run('c:OASIS', vm.script)
    first = vm.prompts[0][0]
    assert '[Back]' not in first, first
    print("ok  first step  -> the first question offers no Back")


def test_oversize_bulge_is_reasked():
    """A side bulge more than half the Y bound would break out through
    the top, so the question comes back."""
    vm = newvm()
    # 150 on a 240 envelope stands 300 tall -- rejected, then 96 taken
    run(vm, ['Center', (0.0, 0.0), REF_X, REF_Y, 150.0, 96.0]
        + REF_MEASURE[3:], 'oversize bulge')
    assert close(arcs_of(vm)[0][1], 96.0), arcs_of(vm)[0]
    print("ok  big bulge   -> a bulge taller than Y is re-asked")


def test_short_tangent_is_reasked():
    """A tangent radius too short to span its two bulges is re-asked."""
    vm = newvm()
    # the bottom-center minimum here is 36.13"; 20 cannot reach
    run(vm, script(measure=REF_MEASURE[:7] + [20.0, 60.0]), 'short tangent')
    bc = [a for a in arcs_of(vm) if close(a[1], 60.0)][0]
    assert close(bc[0][0], 230.6428859721), bc
    print("ok  short tan.  -> a tangent radius under the minimum is re-asked")


def test_nested_bulges_are_reasked():
    """A top bulge that swallows a side bulge cannot be joined to it by
    any tangent radius, so it is refused where it is entered."""
    vm = newvm()
    # a 480 top bulge on a 480 x 240 envelope is centred at (240, -240)
    # and swallows the 96 left bulge whole; 132 is taken instead
    run(vm, ['Center', (0.0, 0.0), REF_X, REF_Y, 96.0, 480.0, 132.0, 108.0]
        + list(REF_TANGENTS), 'nested top')
    assert close([a for a in arcs_of(vm) if close(a[1], 132.0)][0][0][1],
                 REF_Y - 132.0)
    print("ok  nesting     -> a bulge inside another is re-asked")


def test_right_bulge_nesting_is_caught():
    """The right bulge is the last of the three, so a nesting only it
    can cause sends the run back to that question."""
    vm = newvm()
    # on a 480 x 800 envelope a 384 right bulge is centred at (96, 384)
    # -- directly above the 96 left bulge and swallowing it -- so it is
    # re-asked, and 108 is taken instead
    run(vm, ['Center', (0.0, 0.0), REF_X, 800.0, 96.0, 132.0, 384.0, 108.0,
             200.0, 200.0, 60.0], 'nested right')
    assert close([a for a in arcs_of(vm) if close(a[1], 108.0)][0][0][0],
                 REF_X - 108.0)
    print("ok  right nest  -> a right bulge swallowing the left one is"
          " re-asked")


def test_zero_and_negative_are_rejected():
    """Every measurement is REQ: Enter, zero and a negative are all
    refused by initget before the routine ever sees them."""
    for bad, why in ((0.0, 'zero'), (-10.0, 'negative'), (None, 'Enter')):
        vm = newvm()
        try:
            vm.run('c:OASIS', script(measure=[bad] + REF_MEASURE[1:]))
        except LispError:
            continue
        raise AssertionError("%s was accepted as the X bound" % why)
    print("ok  bad numbers -> zero, negative and Enter are all refused")


def test_undo_group_wraps_the_drawing():
    vm = newvm()
    run(vm, script(), 'undo')
    undo = [c for c in vm.commands if c and c[0] == '_.UNDO']
    assert [c[1] for c in undo] == ['_Begin', '_End'], undo
    print("ok  undo group  -> one U puts the whole pool back")


def test_settings_come_back():
    vm = newvm()
    vm.sysvars['OSMODE'] = 4133
    vm.sysvars['CMDECHO'] = 1
    vm.tables['LAYER'].add('SOMETHING')
    vm.sysvars['CLAYER'] = 'SOMETHING'
    run(vm, script(), 'sysvars')
    assert vm.sysvars['OSMODE'] == 4133, vm.sysvars
    assert vm.sysvars['CMDECHO'] == 1, vm.sysvars
    assert vm.sysvars['CLAYER'] == 'SOMETHING', vm.sysvars
    print("ok  sysvars     -> OSMODE, CMDECHO and CLAYER all restored")


def test_frozen_layer_is_restored():
    """A run onto a switched-off POOL layer must not look like it did
    nothing -- ensure-layer turns it back on and says so."""
    vm = newvm()
    vm.tables['LAYER'].add('POOL')
    rec = Ent()
    vm.entdata[rec] = [Dot(0, 'LAYER'), Dot(2, 'POOL'), Dot(70, 5),
                       Dot(62, -4)]
    vm.layer_records['POOL'] = rec
    run(vm, script(), 'frozen layer')
    d = _alist_dict(vm.entdata[rec])
    assert d[70] == 0, d          # thawed and unlocked
    assert d[62] == 4, d          # switched back on
    assert len(made(vm, 'ARC')) == 12      # the pool and the check drawing
    print("ok  cold layer  -> a frozen, locked, off POOL layer is revived")



def test_reference_outline_does_not_cross_itself():
    vm = newvm()
    assert crossing_pairs(vm, REF_X, REF_Y, *(REF_BULGES + REF_TANGENTS)) == set()
    print("ok  no crossing -> the reference outline is a simple closed curve")


def test_self_crossing_is_detected():
    """Radii wildly out of proportion send one arc clean through another.
    Everything about it is constructible -- all six arcs exist and they
    close -- so only an explicit test catches it."""
    vm = newvm()
    # 10' x 10' with 6" side bulges and a 5' top: the bottom-center arc
    # sweeps up through both top tangent arcs
    assert crossing_pairs(vm, 120.0, 120.0, 6.0, 60.0, 6.0, 5.4, 5.4, 50.4) == {
        ('bottom-center', 'top-left'), ('bottom-center', 'top-right')}
    # 6" bulges all round with 4'-9" tangent radii: the two top tangent
    # arcs reach each other as well
    assert crossing_pairs(vm, 120.0, 120.0, 6.0, 6.0, 6.0, 57.1, 57.1, 50.4) == {
        ('bottom-center', 'top-left'), ('bottom-center', 'top-right'),
        ('top-left', 'top-right')}
    print("ok  crossing    -> an outline that runs through itself is caught")


def test_crossings_ignores_the_tangent_joints():
    """Neighbouring arcs touch at the end they share by construction.
    Counting those would report every pool as self-crossing."""
    vm = newvm()
    arcs = solved(vm, REF_X, REF_Y, *(REF_BULGES + REF_TANGENTS))
    assert len(arcs) == 6, arcs
    # every neighbouring pair really is externally tangent -- the thing
    # the crossing test has to look past
    for i in range(6):
        c1, r1 = arcs[i][1], arcs[i][2]
        c2, r2 = arcs[(i + 1) % 6][1], arcs[(i + 1) % 6][2]
        assert close(math.dist(c1[:2], c2[:2]), r1 + r2, 1.0e-9), (i, c1, c2)
    print("ok  joints      -> the six tangent joints are not counted as"
          " crossings")



def test_wide_bulge_is_reasked():
    """A side bulge is tangent to the bottom edge AND to its own side, so
    it is twice its radius across as well as tall.  More than half the X
    bound and it breaks out through the far side."""
    vm = newvm()
    # 200 wide envelope, 400 deep: a 150 left bulge is 300 across -- it
    # fits the depth easily and still cannot fit the width
    run(vm, ['Center', (0.0, 0.0), 200.0, 400.0, 150.0, 60.0, 60.0, 60.0,
             120.0, 120.0, 120.0], 'wide bulge')
    assert close(arcs_of(vm)[0][1], 60.0), arcs_of(vm)[0]
    print("ok  wide bulge  -> a bulge wider than X is re-asked")


def test_overrun_names_the_arc_that_is_out():
    """When the outline does leave the envelope, the report names the arc
    that takes it there -- which is not always the one you would guess
    from the radii."""
    vm = newvm()
    # a long shallow envelope with an oversized bottom-center tangent:
    # every bulge fits on its own, and yet two arcs swing out
    got = overruns(vm, 589.0477, 62.5513, 19.6315, 154.7235, 23.3675,
                   135.6825, 68.2843, 403.0810)
    assert {(side, name) for side, name, _ in got} == {
        ('the bottom', 'top-right'), ('the top', 'bottom-center')}, got
    assert close(dict((s, a) for s, _, a in got)['the bottom'],
                 29.8396407702, 1.0e-8), got
    # the reference pool leaves nothing hanging out
    assert overruns(vm, REF_X, REF_Y, *(REF_BULGES + REF_TANGENTS)) == []
    print("ok  overrun     -> the arc that leaves the envelope is named")


def test_arcs_follow_a_rotated_ucs():
    """The dimensions are read in the UCS but an ARC's centre is stored in
    world coordinates and its angles measured from the world X axis.  Both
    have to be carried across, or the pool detaches from its own dims."""
    with fake_trans(rot=math.radians(30.0), org=(1000.0, -400.0, 12.0)):
        vm = newvm()
        run(vm, script((50.0, 20.0, 5.0)), 'rotated ucs')
        c, s = math.cos(math.radians(30.0)), math.sin(math.radians(30.0))
        for (name, lc, r, a0, a1), (gc, gr, ga0, ga1) in zip(REF_ARCS,
                                                             arcs_of(vm)):
            # the centre: pool -> UCS -> world
            ux, uy = lc[0] + 50.0, lc[1] + 20.0
            assert close(gc[0], ux * c - uy * s + 1000.0, 1.0e-6), (name, gc)
            assert close(gc[1], ux * s + uy * c - 400.0, 1.0e-6), (name, gc)
            # the angles: turned by the same 30 degrees
            for got_a, want_a in ((ga0, a0 + 30.0), (ga1, a1 + 30.0)):
                d = abs((got_a - want_a + 180.0) % 360.0 - 180.0)
                assert d <= 1.0e-6, (name, got_a, want_a)
        # the dimension points stay in the UCS, untransformed
        horiz = [x for x in cmds(vm, '_.DIMLINEAR') if '_H' in x][0]
        assert close(abs(horiz[1][0] - horiz[2][0]), REF_X), horiz
        assert close(horiz[1][2], 5.0), horiz      # the pick's own elevation
    print("ok  rotated UCS -> arcs go to world, dims stay in the UCS")


def test_tilted_ucs_is_refused():
    """A UCS tilted out of the world plan cannot carry a flat plan pool --
    each arc would need an extrusion of its own -- so nothing is asked and
    nothing is drawn."""
    with fake_trans(zdir=(0.0, 0.7071067811865476, 0.7071067811865476)):
        vm = newvm()
        vm.run('c:OASIS', [])          # not one prompt may be reached
        assert vm.prompts == [], vm.prompts
        assert made(vm, 'ARC') == []
        assert vm.commands == [], vm.commands
    print("ok  tilted UCS  -> refused before a single question is asked")



def test_radius_dim_text_lands_outside_the_water():
    """The leader is dragged away from the centre on a bulge and towards
    it on a reverse arc -- whose own centre is outside the pool -- so
    both put the text clear of the water rather than across it."""
    vm = newvm()
    run(vm, script(), 'radius drag')
    doff = max(12.0, max(REF_X, REF_Y) / 18.0)
    bulge = dict((n, n in ('left', 'right', 'top'))
                 for n, _, _, _, _ in REF_ARCS)
    seen = 0
    for c in cmds(vm, '_.DIMRADIUS'):
        ent, tip, loc = c[1][0], c[1][1], c[2]
        d = _alist_dict(vm.entdata[ent])
        cen, r = d[10][:2], d[40]
        name = [n for n, _, rr, _, _ in REF_ARCS if close(rr, r)][0]
        drag = math.dist(loc[:2], cen) - r
        want = 0.9 * doff * (1.0 if bulge[name] else -1.0)
        assert close(drag, want, 1.0e-6), (name, drag, want)
        # and the pick itself is still on the arc it dimensions
        assert close(math.dist(tip[:2], cen), r), (name, tip)
        seen += 1
    assert seen == 6, seen
    print("ok  dim drag    -> radius text pulled clear of the water on all"
          " six")


def test_overall_dims_hook_the_touch_points_at_the_right_standoff():
    """The extension lines start where the pool really touches the
    envelope, and the dimension line sits at POOL's own stand-off, so an
    oasis reads the same as a rectangle drawn beside it."""
    vm = newvm()
    run(vm, script(), 'standoff')
    doff = max(12.0, max(REF_X, REF_Y) / 18.0)
    horiz = [c for c in cmds(vm, '_.DIMLINEAR') if '_H' in c][0]
    vert = [c for c in cmds(vm, '_.DIMLINEAR') if '_V' in c][0]
    # X: the left bulge's leftmost point to the right bulge's rightmost
    assert [round(v, 9) for v in horiz[1][:2]] == [0.0, REF_BULGES[0]], horiz
    assert [round(v, 9) for v in horiz[2][:2]] == [REF_X, REF_BULGES[2]], horiz
    assert close(horiz[4][1], REF_Y + doff), horiz
    # Y: the top bulge's highest point to the left bulge's lowest
    assert [round(v, 9) for v in vert[1][:2]] == [REF_X / 2.0, REF_Y], vert
    assert [round(v, 9) for v in vert[2][:2]] == [REF_BULGES[0], 0.0], vert
    assert close(vert[4][0], -doff), vert
    print("ok  standoff    -> overall dims hook the touch points at %g\""
          % doff)


def test_every_measurement_rejects_zero_and_negative():
    """Not just the first: all eight are REQ, so initget must reject a
    zero or a negative at each of them."""
    for k in range(8):
        for bad in (0.0, -12.0):
            vm = newvm()
            m = list(REF_MEASURE)
            m[k] = bad
            try:
                vm.run('c:OASIS', script(measure=m))
            except LispError:
                continue
            raise AssertionError("question %d accepted %r" % (k, bad))
    print("ok  all REQ     -> zero and negative refused at all eight"
          " measurements")



def test_preview_shows_the_pool_being_answered():
    """Each question redraws the pool as it stands: the outline solid on
    POOL, the circle behind each arc dashed on POOL-GUIDE, and the
    envelope box.  Nothing before both bounds are known -- there is no
    envelope to draw anything inside yet."""
    with at_each_prompt() as p:
        vm = newvm()
        run(vm, script(), 'preview')
    assert p.shot(0, 'ARC') == [], 'nothing may be drawn before X'
    assert p.shot(1, 'ARC') == [], 'nothing may be drawn before Y'
    for k in range(2, 8):                     # the six radius questions
        assert len(p.shot(k, 'ARC')) == 6, (k, len(p.shot(k, 'ARC')))
        assert len(p.shot(k, 'CIRCLE')) == 6, (k, len(p.shot(k, 'CIRCLE')))
        assert len(p.shot(k, 'LINE')) == 4, (k, len(p.shot(k, 'LINE')))
        assert all(d[8] == 'POOL' for d in p.shot(k, 'ARC'))
        assert all(d[8] == 'POOL-GUIDE' for d in p.shot(k, 'CIRCLE'))
        # each dashed circle really is the one its arc is cut from
        for arc, circ in zip(p.shot(k, 'ARC'), p.shot(k, 'CIRCLE')):
            assert close(arc[40], circ[40]), (k, arc[40], circ[40])
    print("ok  preview     -> outline + dashed circles + box at every"
          " radius question")


def test_preview_marks_the_circle_being_asked_about():
    """The circle the question is about goes red -- its dashed circle,
    its arc and its label -- so there is no doubt which radius is
    wanted."""
    order = {2: 0, 3: 4, 4: 2, 5: 5, 6: 3, 7: 1}   # question -> ring slot
    with at_each_prompt() as p:
        vm = newvm()
        run(vm, script(), 'highlight')
    for k, slot in order.items():
        red = [d for d in p.shot(k) if d.get(62) == 1]
        assert len(red) == 3, (k, len(red))       # arc, circle, label
        assert {d[0] for d in red} == {'ARC', 'CIRCLE', 'TEXT'}, red
        arc = [d for d in red if d[0] == 'ARC'][0]
        assert arc is p.shot(k, 'ARC')[slot], (k, slot)
        circ = [d for d in red if d[0] == 'CIRCLE'][0]
        assert close(arc[40], circ[40]), (k, arc[40], circ[40])
    print("ok  highlight   -> the questioned circle, arc and label are red")


def test_preview_labels_unanswered_radii_with_a_question_mark():
    """A radius that has not been given yet is labelled ?; one that has
    shows what was typed."""
    with at_each_prompt() as p:
        vm = newvm()
        run(vm, script(), 'labels')
    # at the very first radius question nothing has been answered
    assert [d[1] for d in p.shot(2, 'TEXT')].count('?') == 6, p.shot(2, 'TEXT')
    # by the last, only the bottom-center tangent is still unknown
    last = [d[1] for d in p.shot(7, 'TEXT')]
    assert last.count('?') == 1, last
    for r in REF_BULGES + REF_TANGENTS[:2]:
        assert any(close(float(t), r) for t in last if t != '?'), (r, last)
    print("ok  ? labels    -> unanswered radii read ?, answered ones read"
          " their value")


def test_preview_is_gone_when_the_run_finishes():
    """The preview is scaffolding.  What is left is the pool, the check
    drawing and their dimensions -- nothing provisional."""
    vm = newvm()
    run(vm, script(), 'preview cleared')
    assert len(made(vm, 'ARC')) == 12, made(vm, 'ARC')   # pool + check
    assert len(made(vm, 'CIRCLE')) == 6                  # centre marks
    assert len(made(vm, 'LINE')) == 4                    # the check box
    assert made(vm, 'TEXT') == [], made(vm, 'TEXT')      # no ? survives
    assert len(vm.deleted) > 100, len(vm.deleted)
    print("ok  cleared     -> every preview entity erased, %d of them"
          % len(vm.deleted))


def test_check_drawing_sits_clear_to_the_right():
    vm = newvm()
    run(vm, script(), 'check placement')
    pool = arcs_of(vm)
    chk = check_arcs_of(vm)
    assert len(chk) == 6, chk
    gap = chk[0][0][0] - pool[0][0][0]
    assert gap > REF_X, gap            # clear of the pool and its dims
    for (pc, pr), (cc, cr) in zip([(c, r) for c, r, _, _ in pool], chk):
        assert close(cr, pr), (pr, cr)
        assert close(cc[0] - pc[0], gap) and close(cc[1], pc[1]), (pc, cc)
    print("ok  check right -> a second copy %g\" to the right" % gap)


def test_check_drawing_ties_every_centre_to_its_two_nearest_corners():
    vm = newvm()
    run(vm, script(), 'corner ties')
    chk = check_arcs_of(vm)
    ox = chk[0][0][0] - REF_BULGES[0]        # the check envelope's origin
    oy = chk[0][0][1] - REF_BULGES[0]
    corners = [(ox, oy), (ox + REF_X, oy),
               (ox + REF_X, oy + REF_Y), (ox, oy + REF_Y)]
    ties = cmds(vm, '_.DIMALIGNED')[:12]
    assert len(ties) == 12, len(ties)
    for i, (c, _) in enumerate(chk):
        near = sorted(corners, key=lambda k: math.dist(c, k))[:2]
        got = [t for t in ties if close(math.dist(t[1][:2], c), 0.0, 1e-9)]
        assert len(got) == 2, (i, len(got))
        assert sorted(round(math.dist(t[2][:2], c), 6) for t in got) == \
            sorted(round(math.dist(n, c), 6) for n in near), (i, got)
    print("ok  corner ties -> 12 dims, each centre to its two nearest"
          " corners")


def test_check_drawing_ties_neighbouring_centres():
    """The last six tie each centre to the next one round the ring -- and
    because neighbouring circles are externally tangent, each of those
    dimensions must read exactly the two radii added together."""
    vm = newvm()
    run(vm, script(), 'centre ties')
    chk = check_arcs_of(vm)
    ties = cmds(vm, '_.DIMALIGNED')[12:]
    assert len(ties) == 6, len(ties)
    for i, t in enumerate(ties):
        a, b = chk[i], chk[(i + 1) % 6]
        assert close(math.dist(t[1][:2], a[0]), 0.0, 1e-9), (i, t[1], a[0])
        assert close(math.dist(t[2][:2], b[0]), 0.0, 1e-9), (i, t[2], b[0])
        assert close(math.dist(a[0], b[0]), a[1] + b[1]), (i, a, b)
    print("ok  centre ties -> 6 dims, each reading the two radii added"
          " together")


def test_the_two_drawings_take_their_own_dim_styles():
    """The pool is a plan and is dimensioned in the drawing's ordinary
    style; the check drawing beside it is nothing but tie measurements
    and goes in the cross-dimension style."""
    vm = newvm()
    run(vm, script(), 'dim styles')
    dims = made(vm, 'DIMENSION')
    assert len(dims) == 20, len(dims)
    # the pool's two linear dims come first (DIMRADIUS makes no entity
    # in the VM), then the check drawing's eighteen
    assert all(d[3] == 'Standard' for d in dims[:2]), dims[:2]
    assert all(d[3] == 'CROSS DIMENSIONS' for d in dims[2:]), dims[2]
    assert vm.dimstyle_log == ['Standard', 'CROSS DIMENSIONS', 'STANDARD'], \
        vm.dimstyle_log
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars['DIMSTYLE']
    print("ok  dim styles  -> pool in Standard, check drawing in CROSS"
          " DIMENSIONS, old style back")


def test_a_drawing_without_the_cross_style_still_gets_its_pool():
    """A missing style is not invented -- those dims come out in whatever
    is current and the routine says so."""
    vm = newvm(style=False)
    run(vm, script(), 'no style')
    assert len(made(vm, 'ARC')) == 12
    dims = made(vm, 'DIMENSION')
    assert len(dims) == 20, len(dims)
    assert all(d[3] == 'Standard' for d in dims), dims[2]
    print("ok  no style    -> drawn in the current style rather than"
          " refused")



def test_the_preview_starts_from_the_usual_proportions():
    """Before any radius is given the preview has to show SOMETHING, and
    what it shows is the shape an oasis usually comes in -- a side bulge
    three quarters of the way across the short bound, the top bulge half
    way across the long one -- so the first question is already looking
    at a familiar size rather than something to look past."""
    with at_each_prompt() as p:
        vm = newvm()
        run(vm, script(), 'starting shape')
    radii = [r for _, r, _, _ in
             [((d[10][0], d[10][1]), d[40],
               math.degrees(d[50]) % 360, math.degrees(d[51]) % 360)
              for d in p.shot(2, 'ARC')]]
    left, bottom, right, topright, top, topleft = radii
    assert close(2.0 * left, 0.75 * REF_Y), left      # 7'-6" on a 40 x 20
    assert close(2.0 * right, 0.75 * REF_Y), right
    assert close(2.0 * top, 0.5 * REF_X), top         # 10'-0"
    # and the bulges really are the bigger circles, which is the point
    for tangent in (bottom, topright, topleft):
        assert tangent < min(left, right, top), (tangent, radii)
    # every one of them is provisional, so every one is still a ?
    assert [d[1] for d in p.shot(2, 'TEXT')] == ['?'] * 6, p.shot(2, 'TEXT')
    print("ok  start shape -> side bulges %g\" and a %g\" top, all six ?"
          % (left, top))



def test_the_shape_is_the_first_question():
    """Which of the two an oasis is decides everything else, so it is
    asked before anything -- and being first, it offers no Back."""
    vm = newvm()
    run(vm, script(), 'shape question')
    first = vm.prompts[0][0]
    assert first == '\nWhere is the top bulge? [Center/TopRight] <Center>: ', \
        repr(first)
    assert '[Back]' in vm.prompts[1][0], vm.prompts[1][0]   # the base point
    print("ok  shape first -> %r" % first.strip())


def test_top_right_bulge_matches_its_reference_drawing():
    """The corner variant reads off a 36'-11" x 28'-8" drawing with 9'/8'/9'
    bulges and 8'/8'/10' tangents.  The third bulge is tangent to the TOP
    and the RIGHT bound; everything else is the centre variant's logic
    untouched."""
    vm = newvm()
    run(vm, script(measure=TR_MEASURE, variant='TopRight'), 'top right')
    arcs = arcs_of(vm)
    assert len(arcs) == 6, arcs
    left, bottom, right, side, top, upper = arcs
    # the corner bulge really is in the corner
    assert close(top[0][0], TR_X - 96.0) and close(top[0][1], TR_Y - 96.0), top
    # the two side bulges are where they always were
    assert close(left[0][0], 108.0) and close(left[0][1], 108.0), left
    assert close(right[0][0], TR_X - 108.0) and close(right[0][1], 108.0), right
    assert [round(r, 4) for _, r, _, _ in arcs] == \
        [108.0, 120.0, 108.0, 96.0, 96.0, 96.0], arcs
    print("ok  top-right   -> the corner bulge lands at (X-r, Y-r)")


def test_top_right_bulge_fills_its_envelope():
    """Absolute bounds hold for the corner variant too -- and its right
    bound is touched twice, once by each of the two right-hand bulges."""
    vm = newvm()
    run(vm, script(measure=TR_MEASURE, variant='TopRight'), 'tr envelope')
    xs, ys, right_touch = [], [], 0
    for c, r, a0, a1 in arcs_of(vm):
        sweep = (a1 - a0) % 360.0
        for a in [a0, a1] + [k for k in (0.0, 90.0, 180.0, 270.0)
                             if (k - a0) % 360.0 <= sweep]:
            p = pt_on(c, r, a)
            xs.append(p[0])
            ys.append(p[1])
            if close(p[0], TR_X):
                right_touch += 1
    assert close(min(xs), 0.0) and close(min(ys), 0.0), (min(xs), min(ys))
    assert close(max(xs), TR_X) and close(max(ys), TR_Y), (max(xs), max(ys))
    assert right_touch == 2, right_touch      # the corner and the right bulge
    print("ok  tr envelope -> fills 0,0 - %g,%g, right bound touched twice"
          % (TR_X, TR_Y))


def test_top_right_outline_is_still_tangent_continuous_and_simple():
    vm = newvm()
    run(vm, script(measure=TR_MEASURE, variant='TopRight'), 'tr tangency')
    arcs = arcs_of(vm)
    bulge = [True, False, True, False, True, False]
    worst = 0.0
    for i, (c, r, a0, a1) in enumerate(arcs):
        j = (i + 1) % 6
        nc, nr, na0, na1 = arcs[j]
        joint = pt_on(c, r, a1 if bulge[i] else a0)
        arrive = pt_on(nc, nr, na0 if bulge[j] else na1)
        assert close(math.dist(joint, arrive), 0.0), (i, joint, arrive)
        v1 = (c[0] - joint[0], c[1] - joint[1])
        v2 = (nc[0] - joint[0], nc[1] - joint[1])
        worst = max(worst, abs(v1[0] * v2[1] - v1[1] * v2[0]) / (r * nr))
    assert worst <= 1.0e-9, worst
    r = vm.loads('(oasis:crossings (oasis:solve %s "TopRight"))'
                 % " ".join("%.10f" % v for v in TR_MEASURE))
    assert r is None, r
    print("ok  tr tangency -> closed, tangent-continuous and simple")


def test_the_two_shapes_name_their_arcs_apart():
    """"top-right" is the tangent arc on one shape and the bulge itself on
    the other, so the names have to move with the shape -- they are what
    the reports and the ? labels read from."""
    vm = newvm()
    assert vm.loads('(oasis:names "Center")') == \
        ['left', 'bottom-center', 'right', 'top-right', 'top', 'top-left']
    assert vm.loads('(oasis:names "TopRight")') == \
        ['left', 'bottom-center', 'right', 'right-side', 'top-right',
         'top-left']
    print("ok  arc names   -> the two shapes name their six apart")


def test_top_right_asks_its_own_questions():
    vm = newvm()
    run(vm, script(measure=TR_MEASURE, variant='TopRight'), 'tr prompts')
    asked = [p.lstrip('\n').rstrip() for p, _ in vm.prompts]
    assert 'Top-right bulge radius [Back]:' in asked, asked
    assert 'Right-side tangent radius [Back]:' in asked, asked
    assert not any(a.startswith('Top bulge') for a in asked), asked
    assert not any(a.startswith('Top-right tangent') for a in asked), asked
    print("ok  tr prompts  -> asks for a top-right bulge and a right-side"
          " tangent")


def test_a_corner_bulge_too_big_for_the_envelope_is_reasked():
    """The corner bulge is tangent to two bounds, so it is twice its
    radius BOTH ways and can break out of either -- a check the centred
    bulge does not need, because it is trimmed long before it reaches
    anything."""
    vm = newvm()
    # 200 short bound: a 150 corner bulge is 300 both ways
    run(vm, ['TopRight', (0.0, 0.0), 400.0, 200.0, 60.0, 150.0, 80.0, 60.0,
             90.0, 90.0, 90.0], 'big corner')
    top = arcs_of(vm)[4]
    assert close(top[1], 80.0), top
    # and the centred bulge of the same size is accepted, because there
    # it is trimmed rather than breaking out
    vm = newvm()
    run(vm, ['Center', (0.0, 0.0), 400.0, 200.0, 60.0, 150.0, 60.0,
             90.0, 90.0, 90.0], 'big centre')
    assert close(arcs_of(vm)[4][1], 150.0), arcs_of(vm)[4]
    print("ok  big corner  -> a corner bulge over the envelope is re-asked,"
          " a centred one is not")


def test_top_right_preview_starts_from_its_own_proportions():
    """The centred bulge is measured across the long bound; the corner one
    across the short, because it has to fit both ways."""
    with at_each_prompt() as p:
        vm = newvm()
        run(vm, script(measure=TR_MEASURE, variant='TopRight'), 'tr start')
    radii = [d[40] for d in p.shot(2, 'ARC')]
    assert close(2.0 * radii[0], 0.75 * TR_Y), radii      # side bulges
    assert close(2.0 * radii[4], 0.5 * TR_Y), radii       # the corner one
    assert close(2.0 * radii[2], 0.75 * TR_Y), radii
    for tangent in (radii[1], radii[3], radii[5]):
        assert tangent < min(radii[0], radii[2], radii[4]), radii
    print("ok  tr start    -> corner bulge sized off the short bound")


def test_version_command():
    vm = newvm()
    vm.run('c:OASISVER', [])
    assert re.match(r'v\d+\.\d+$', vm.globals[Sym('*oasis-version*')]), \
        vm.globals[Sym('*oasis-version*')]
    print("ok  OASISVER    -> %s" % vm.globals[Sym('*oasis-version*')])


def walk_forms(src):
    """(functions called in head position, defun/lambda local lists).

    Parsed rather than grepped: a name in a cond TEST position, in a
    lambda arg list or inside a quoted list is data, not a call, and a
    regex cannot tell those apart from a real one.
    """
    called, declared = set(), []

    def arglist(x):
        if isinstance(x, list):
            declared.append([str(s) for s in x if isinstance(s, Sym)])

    def walk(x):
        if not isinstance(x, list) or not x:
            return
        head = x[0]
        if isinstance(head, Sym):
            if head == Sym('quote'):
                # data -- except a quoted lambda, which really is called
                if (len(x) > 1 and isinstance(x[1], list) and x[1]
                        and x[1][0] == Sym('lambda')):
                    walk(x[1])
                return
            if head == Sym('defun'):
                called.add(str(head))
                arglist(x[2] if len(x) > 2 else None)
                for f in x[3:]:
                    walk(f)
                return
            if head == Sym('lambda'):
                arglist(x[1] if len(x) > 1 else None)
                for f in x[2:]:
                    walk(f)
                return
            if head == Sym('cond'):
                called.add(str(head))
                for clause in x[1:]:      # every element of a clause is
                    if isinstance(clause, list):   # a form, not a call
                        for f in clause:
                            walk(f)
                return
            called.add(str(head))
        else:
            walk(head)
        for f in x[1:]:
            walk(f)

    for form in parse_all(src):
        walk(form)
    return called, declared


def test_no_local_shadows_a_function():
    """A local declared with the name of a function the file calls makes
    that call 'no function definition' in AutoCAD, even for a builtin."""
    called, declared = walk_forms(open(LSP).read())
    bad = sorted({n for names in declared for n in names
                  if n != '/' and n.lower() in called})
    assert not bad, f"locals shadowing functions they call: {bad}"
    print("ok  no shadow   -> no local hides a function the file calls")


if __name__ == '__main__':
    test_reference_drawing()
    test_outline_closes()
    test_tangent_continuity()
    test_fills_the_envelope()
    test_layers_and_dimensions()
    test_dimension_values()
    test_radius_dims_hook_the_arcs()
    test_base_point_moves_everything()
    test_enter_takes_the_origin()
    test_back_reasks()
    test_back_at_the_first_question_stays_put()
    test_oversize_bulge_is_reasked()
    test_short_tangent_is_reasked()
    test_nested_bulges_are_reasked()
    test_right_bulge_nesting_is_caught()
    test_zero_and_negative_are_rejected()
    test_undo_group_wraps_the_drawing()
    test_settings_come_back()
    test_frozen_layer_is_restored()
    test_reference_outline_does_not_cross_itself()
    test_self_crossing_is_detected()
    test_crossings_ignores_the_tangent_joints()
    test_wide_bulge_is_reasked()
    test_overrun_names_the_arc_that_is_out()
    test_arcs_follow_a_rotated_ucs()
    test_tilted_ucs_is_refused()
    test_radius_dim_text_lands_outside_the_water()
    test_overall_dims_hook_the_touch_points_at_the_right_standoff()
    test_every_measurement_rejects_zero_and_negative()
    test_preview_shows_the_pool_being_answered()
    test_preview_marks_the_circle_being_asked_about()
    test_preview_labels_unanswered_radii_with_a_question_mark()
    test_preview_is_gone_when_the_run_finishes()
    test_check_drawing_sits_clear_to_the_right()
    test_check_drawing_ties_every_centre_to_its_two_nearest_corners()
    test_check_drawing_ties_neighbouring_centres()
    test_the_two_drawings_take_their_own_dim_styles()
    test_a_drawing_without_the_cross_style_still_gets_its_pool()
    test_the_preview_starts_from_the_usual_proportions()
    test_the_shape_is_the_first_question()
    test_top_right_bulge_matches_its_reference_drawing()
    test_top_right_bulge_fills_its_envelope()
    test_top_right_outline_is_still_tangent_continuous_and_simple()
    test_the_two_shapes_name_their_arcs_apart()
    test_top_right_asks_its_own_questions()
    test_a_corner_bulge_too_big_for_the_envelope_is_reasked()
    test_top_right_preview_starts_from_its_own_proportions()
    test_version_command()
    test_no_local_shadows_a_function()
    print("all OASIS tests passed")
