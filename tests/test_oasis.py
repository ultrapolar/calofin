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

#: every run ends with the same question, whose default is No
BOTQ = 'Add the bottom of the pool (breaks and hopper)?' 


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


def script(base=(0.0, 0.0), measure=None, variant='Center', detail='Simple',
           bottom=None):
    """A whole run: which shape -- and, for a cloud, which bottom -- then
    simple or complex, then where it goes and the measurements.  bottom
    is the answers to the pool-bottom flow; without it the run takes the
    default No and stops at the perimeter."""
    head = {'StraightBottom': ['CLoud', 'Straight'],
            'RoundedBottom': ['CLoud', 'Rounded'],
            'TrueKidney': ['Kidney', 'True'],
            'AsymKidney': ['Kidney', 'Asymmetric']}.get(variant, [variant])
    return (head + [detail, base]
            + list(REF_MEASURE if measure is None else measure)
            # Enter at "Add the bottom of the pool?", whose default is No
            + ([None] if bottom is None else ['Yes'] + list(bottom)))


#: the drawing the TOP RIGHT BULGE variant was read off: 36'-11" x 28'-8",
#: bulges 9' left / 8' top-right / 9' right, tangents 8' top-left,
#: 8' right-side, 10' bottom-center.  Its third bulge is tucked into the
#: corner, tangent to the top AND the right bound.
TR_X, TR_Y = 443.0, 344.0
TR_MEASURE = [TR_X, TR_Y, 108.0, 96.0, 108.0, 96.0, 96.0, 120.0]

#: the drawing the two CLOUD shapes were read off: 30'-0" x 20'-0", a 7'
#: right bulge, a 6' top tangent and -- on the rounded one -- a 12'
#: bottom.  The left bulge is not in the list: three bounds pin it at
#: half the Y bound, 10'-0" here, and it is never asked for.
CL_X, CL_Y = 360.0, 240.0
CL_RLEFT = CL_Y / 2.0
CL_FLAT = [CL_X, CL_Y, 84.0, 72.0]                 # StraightBottom
CL_ROUND = [CL_X, CL_Y, 84.0, 72.0, 144.0]         # RoundedBottom

#: the drawing the two KIDNEY shapes were read off: a 388 x 214 envelope,
#: a 324 top-center circle and a 48 bottom reverse.  The two matching
#: sides are DERIVED -- tangent to their own side and the bottom, and
#: touching the top circle from inside -- and come out at 95.9166563.
KD_X, KD_Y = 388.0, 214.0
KD_TOP, KD_BOT = 324.0, 48.0
KD_SIDE = 95.9166563301
KD_TRUE = [KD_X, KD_Y, KD_TOP, KD_BOT]
#: an asymmetric case (no reference drawing): 8' left, 6' right -- the
#: top circle is derived, landing at cx=175.029655, R=248.947416
KD_ASYM = [KD_X, KD_Y, 96.0, 72.0, KD_BOT]
#: the true-kidney DXF's four arcs, ring order, centres relative to the
#: envelope's bottom-left corner, angles in degrees
KD_REF = [
    ('left',          (95.916657, 95.916657), 95.9167,
     115.4696486, 312.9632234),
    ('bottom-center', (194.0, -9.400301), 48.0, 47.0367766, 132.9632234),
    ('right',         (292.083344, 95.916657), 95.9167,
     227.0367766, 64.5303514),
    ('top-center',    (194.0, -110.0), 324.0, 64.5303514, 115.4696486),
]

#: what the DXF has for those two, in ring order, centres relative to the
#: envelope's bottom-left corner and angles in degrees
CL_REF = {
    'left':   ((120.0, 120.0), 120.0, 38.6376800, None),
    'right':  ((276.0, 84.0), 84.0, 270.0, 92.2141060),
    'top':    ((269.9731235, 239.8835357), 72.0, 218.6376800, 272.2141060),
    'bottom': ((200.9334869, -131.2882219), 144.0, 70.7774020, 107.8524170),
}


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


def arcs_of(vm, n=6):
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
    return out[:n]


def check_arcs_of(vm, n=6):
    """The check drawing's, which follow the pool's."""
    out = []
    for d in made(vm, 'ARC'):
        c = d[10]
        out.append(((c[0], c[1]), d[40]))
    return out[n:]


def pt_on(c, r, deg):
    a = math.radians(deg)
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def close(a, b, tol=TOL):
    return abs(a - b) <= tol


def solved(vm, w, h, rl, rt, rr, ftl, ftr, fbc, off=0.0):
    """Call oasis:solve inside the VM and hand back what it built."""
    return vm.loads('(oasis:solve %s "Center")'
                    % " ".join("%.10f" % v
                               for v in (w, h, rl, rt, rr, ftl, ftr, fbc,
                                         off)))


def crossing_pairs(vm, *dims, **kw):
    """The pairs of arcs oasis:crossings says run through each other."""
    r = vm.loads('(oasis:crossings (oasis:solve %s "Center"))'
                 % " ".join("%.10f" % v
                            for v in tuple(dims) + (kw.get('off', 0.0),)))
    return set() if r is None else {tuple(sorted(p)) for p in r}


def overruns(vm, w, h, *radii, **kw):
    """What oasis:overruns says reaches past the envelope."""
    r = vm.loads('(oasis:overruns (oasis:solve %s "Center") %.6f %.6f)'
                 % (" ".join("%.6f" % v
                             for v in (w, h) + radii + (kw.get('off', 0.0),)),
                    w, h))
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
    assert len(cmds(vm, '_.DIMALIGNED')) == 21, vm.commands   # check drawing
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
    run(vm, ['Center', 'Simple', (0.0, 0.0), REF_X, 300.0, 'Back', REF_Y]
        + REF_MEASURE[2:] + [None], 'back')
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
    run(vm, ['Center', 'Simple', (0.0, 0.0), REF_X, REF_Y, 150.0, 96.0]
        + REF_MEASURE[3:] + [None], 'oversize bulge')
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
    run(vm, ['Center', 'Simple', (0.0, 0.0), REF_X, REF_Y, 96.0, 480.0, 132.0, 108.0]
        + list(REF_TANGENTS) + [None], 'nested top')
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
    run(vm, ['Center', 'Simple', (0.0, 0.0), REF_X, 800.0, 96.0, 132.0, 384.0, 108.0,
             200.0, 200.0, 60.0] + [None], 'nested right')
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
    run(vm, ['Center', 'Simple', (0.0, 0.0), 200.0, 400.0, 150.0, 60.0, 60.0, 60.0,
             120.0, 120.0, 120.0] + [None], 'wide bulge')
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
    """Six tie each centre to the next one round the ring -- and because
    neighbouring circles are externally tangent, each of those must read
    exactly the two radii added together."""
    vm = newvm()
    run(vm, script(), 'centre ties')
    chk = check_arcs_of(vm)
    ties = cmds(vm, '_.DIMALIGNED')[12:18]
    assert len(ties) == 6, len(ties)
    for i, t in enumerate(ties):
        a, b = chk[i], chk[(i + 1) % 6]
        assert close(math.dist(t[1][:2], a[0]), 0.0, 1e-9), (i, t[1], a[0])
        assert close(math.dist(t[2][:2], b[0]), 0.0, 1e-9), (i, t[2], b[0])
        assert close(math.dist(a[0], b[0]), a[1] + b[1]), (i, a, b)
    print("ok  centre ties -> 6 dims, each reading the two radii added"
          " together")


def test_check_drawing_ties_the_bulges_to_each_other():
    """The lobes are what a pool is read by, so their centres are tied to
    each other as well -- across whatever reverse arc sits between them,
    which the ring ties alone never cross."""
    vm = newvm()
    run(vm, script(), 'bulge ties')
    chk = check_arcs_of(vm)
    bulges = [chk[i] for i in (0, 2, 4)]       # left, right, top
    ties = cmds(vm, '_.DIMALIGNED')[18:]
    assert len(ties) == 3, len(ties)
    got = {tuple(sorted((round(t[1][0], 6), round(t[2][0], 6))))
           for t in ties}
    want = {tuple(sorted((round(bulges[i][0][0], 6),
                          round(bulges[(i + 1) % 3][0][0], 6))))
            for i in range(3)}
    assert got == want, (got, want)
    # and they are NOT the tangency ties: a bulge pair is not tangent
    for t in ties:
        d = math.dist(t[1][:2], t[2][:2])
        assert not any(close(d, a[1] + b[1]) for a in bulges for b in bulges
                       if a is not b), d
    print("ok  bulge ties  -> 3 more, left-right, right-top and top-left")


def test_the_two_drawings_take_their_own_dim_styles():
    """The pool is a plan and is dimensioned in the drawing's ordinary
    style; the check drawing beside it is nothing but tie measurements
    and goes in the cross-dimension style."""
    vm = newvm()
    run(vm, script(), 'dim styles')
    dims = made(vm, 'DIMENSION')
    assert len(dims) == 23, len(dims)
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
    assert len(dims) == 23, len(dims)
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
    assert first == ('\nWhich shape is it? [Center/TopRight/CLoud/Kidney] '
                     '<Center>: '), repr(first)
    assert vm.prompts[1][0] == ('\nSimple or complex? [Simple/Complex/Back]'
                                ' <Simple>: '), repr(vm.prompts[1][0])
    assert '[Back]' in vm.prompts[2][0], vm.prompts[2][0]   # the base point
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
    r = vm.loads('(oasis:crossings (oasis:solve %s 0.0 "TopRight"))'
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
    run(vm, ['TopRight', 'Simple', (0.0, 0.0), 400.0, 200.0, 60.0, 150.0, 80.0, 60.0,
             90.0, 90.0, 90.0] + [None], 'big corner')
    top = arcs_of(vm)[4]
    assert close(top[1], 80.0), top
    # and the centred bulge of the same size is accepted, because there
    # it is trimmed rather than breaking out
    vm = newvm()
    run(vm, ['Center', 'Simple', (0.0, 0.0), 400.0, 200.0, 60.0, 150.0, 60.0,
             90.0, 90.0, 90.0] + [None], 'big centre')
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



def test_straight_bottom_matches_its_reference_drawing():
    """The two-bulge cloud: a left bulge tangent to three bounds at once,
    a right bulge tangent to two, a reverse arc over the top -- and a
    flat run of the bottom bound between them."""
    vm = newvm()
    run(vm, script(measure=CL_FLAT, variant='StraightBottom'), 'flat cloud')
    arcs = arcs_of(vm, 3)
    assert len(arcs) == 3, arcs
    left, right, top = arcs
    for got, name in ((left, 'left'), (right, 'right'), (top, 'top')):
        c, r, a0, a1 = CL_REF[name]
        assert close(got[0][0], c[0]) and close(got[0][1], c[1]), (name, got)
        assert close(got[1], r), (name, got)
        assert close(got[2], a0, 1.0e-6), (name, got[2], a0)
        if a1 is not None:
            assert close(got[3], a1, 1.0e-6), (name, got[3], a1)
    assert close(left[1], CL_RLEFT), left      # Y/2, never asked for
    # the flat bottom, drawn as a LINE between the two bulges' feet
    line = [d for d in made(vm, 'LINE')][0]
    assert [round(v, 6) for v in line[10][:2]] == [120.0, 0.0], line
    assert [round(v, 6) for v in line[11][:2]] == [276.0, 0.0], line
    print("ok  flat cloud  -> three arcs and a flat run, on the drawing")


def test_rounded_bottom_matches_its_reference_drawing():
    """Same cloud with the bottom joined by a reverse arc instead."""
    vm = newvm()
    run(vm, script(measure=CL_ROUND, variant='RoundedBottom'), 'round cloud')
    arcs = arcs_of(vm, 4)
    assert len(arcs) == 4, arcs
    for got, name in zip(arcs, ('left', 'bottom', 'right', 'top')):
        c, r, a0, a1 = CL_REF[name]
        assert close(got[0][0], c[0]) and close(got[0][1], c[1]), (name, got)
        assert close(got[1], r), (name, got)
    # its left bulge runs further round than the flat one's, to meet the
    # bottom arc rather than the bottom bound
    assert close(arcs[0][3], 287.8524170, 1.0e-6), arcs[0]
    assert close(arcs[1][2], 70.7774020, 1.0e-6), arcs[1]
    assert close(arcs[1][3], 107.8524170, 1.0e-6), arcs[1]
    print("ok  round cloud -> four arcs, on the drawing")


def test_both_clouds_fill_their_envelope():
    """The left bulge alone holds three of the four bounds, which is what
    takes its radius out of the questions."""
    for variant, measure, nring in (('StraightBottom', CL_FLAT, 3),
                                    ('RoundedBottom', CL_ROUND, 4)):
        vm = newvm()
        run(vm, script(measure=measure, variant=variant), variant)
        over = vm.loads('(oasis:overruns (oasis:solve %.4f %.4f %.4f 0.0 %.4f'
                        ' %.4f 0.0 %.4f 0.0 "%s") %.4f %.4f)'
                        % (CL_X, CL_Y, CL_RLEFT, measure[2], measure[3],
                           measure[4] if len(measure) > 4 else 0.0, variant,
                           CL_X, CL_Y))
        assert over is None, (variant, over)
        assert len(arcs_of(vm, nring)) == nring
    print("ok  cloud bounds-> both fill 0,0 - %g,%g exactly" % (CL_X, CL_Y))


def test_the_flat_bottom_is_the_bound_itself():
    """It is not a special case bolted on: the straight run comes out of
    the same external-tangent construction every joiner uses, and lands on
    the Y-min bound because both bulges are tangent to it."""
    vm = newvm()
    m = vm.loads('(oasis:extnorm (list 120.0 120.0) 120.0'
                 ' (list 276.0 84.0) 84.0)')
    assert close(m[0], 0.0, 1.0e-12) and close(m[1], -1.0, 1.0e-12), m
    ring = vm.loads('(oasis:solve %.1f %.1f %.1f 0.0 84.0 72.0 0.0 0.0 0.0'
                    ' "StraightBottom")' % (CL_X, CL_Y, CL_RLEFT))
    flat = ring[1]
    assert flat[0] == 'bottom' and flat[5] == 'LINE', flat
    assert close(flat[1][1], 0.0) and close(flat[2][1], 0.0), flat
    assert close(flat[1][0], CL_RLEFT), flat          # under the left centre
    assert close(flat[2][0], CL_X - 84.0), flat       # and the right one
    print("ok  flat run    -> the external tangent lands on the Y-min bound")


def test_the_clouds_ask_four_or_five_measurements():
    """A cloud's left bulge is pinned, and a straight bottom has no radius
    at all, so the two of them ask fewer questions than an oasis."""
    for variant, measure, want in (
            ('StraightBottom', CL_FLAT,
             ['Which shape is it?', 'Cloud bottom?', 'Simple or complex?',
              'Insertion base point',
              'X - overall left-to-right bounds',
              'Y - overall front-to-back bounds',
              'Right bulge radius', 'Top tangent radius', BOTQ]),
            ('RoundedBottom', CL_ROUND,
             ['Which shape is it?', 'Cloud bottom?', 'Simple or complex?',
              'Insertion base point',
              'X - overall left-to-right bounds',
              'Y - overall front-to-back bounds',
              'Right bulge radius', 'Top tangent radius', 'Bottom radius',
              BOTQ])):
        vm = newvm()
        run(vm, script(measure=measure, variant=variant), variant)
        asked = [p.lstrip('\n').split(' [')[0].split(' <')[0].rstrip(': ')
                 for p, _ in vm.prompts]
        assert asked == want, (variant, asked)
        assert not any('Left bulge' in a for a in asked), asked
    print("ok  cloud asks  -> 8 measurements flat, 9 rounded, no left"
          " bulge")


def test_the_flat_run_is_dimensioned_by_length_not_radius():
    """A straight run has no radius to call out, so it takes an aligned
    dimension of its length instead -- and the check drawing has one
    centre fewer to tie."""
    vm = newvm()
    run(vm, script(measure=CL_FLAT, variant='StraightBottom'), 'flat dims')
    assert len(cmds(vm, '_.DIMRADIUS')) == 3, vm.commands   # the three arcs
    aligned = cmds(vm, '_.DIMALIGNED')
    assert len(aligned) == 1 + 9, len(aligned)   # the run, 6 corner, 3 tie
    run_dim = aligned[0]
    assert close(math.dist(run_dim[1][:2], run_dim[2][:2]),
                 CL_X - 84.0 - CL_RLEFT), run_dim
    print("ok  flat dims   -> the run is dimensioned %g\" long, not by radius"
          % (CL_X - 84.0 - CL_RLEFT))


def test_the_cloud_preview_shows_no_circle_behind_the_flat_run():
    """Three bulge circles behind three arcs on a rounded cloud; on a flat
    one the bottom has no circle and no ?, because the envelope box
    already shows the bound it lies on."""
    with at_each_prompt() as p:
        vm = newvm()
        run(vm, script(measure=CL_FLAT, variant='StraightBottom'), 'flat pv')
    # shots are the getdist prompts: 0 = X, 1 = Y, 2 = right bulge, 3 = top
    assert len(p.shot(2, 'ARC')) == 3, p.shot(2, 'ARC')
    assert len(p.shot(2, 'LINE')) == 5, p.shot(2, 'LINE')   # box + the run
    assert len(p.shot(2, 'CIRCLE')) == 3, p.shot(2, 'CIRCLE')
    labels = [d[1] for d in p.shot(2, 'TEXT')]
    assert len(labels) == 3, labels
    assert labels.count('?') == 2, labels     # right bulge and top tangent
    # the left bulge is pinned, so it shows its value from the start
    assert any(t != '?' and close(float(t), CL_RLEFT) for t in labels), labels
    print("ok  cloud pv    -> no circle or ? behind the flat run, and the"
          " pinned bulge reads its value")



def test_a_cloud_is_one_shape_with_two_bottoms():
    """The first question offers three, not four: a cloud is one shape
    and which bottom it has is a question of its own, asked straight
    after -- and it decides whether a bottom radius gets asked for at
    all."""
    vm = newvm()
    run(vm, script(measure=CL_FLAT, variant='StraightBottom'), 'flat ask')
    assert vm.prompts[1][0] == '\nCloud bottom? [Straight/Rounded/Back]' \
        ' <Straight>: ', repr(vm.prompts[1][0])
    assert len(vm.prompts) == 9, len(vm.prompts)
    vm = newvm()
    run(vm, script(measure=CL_ROUND, variant='RoundedBottom'), 'round ask')
    assert len(vm.prompts) == 10, len(vm.prompts)     # plus the bottom radius
    # the two answers together name the ring
    for a, b, want in (('Center', None, 'Center'),
                       ('Cloud', 'Straight', 'StraightBottom'),
                       ('Cloud', 'Rounded', 'RoundedBottom')):
        got = vm.loads('(oasis:variant (list "%s" nil nil nil nil nil nil nil'
                       ' nil nil %s))'
                       % (a, ('"%s"' % b) if b else 'nil'))
        assert got == want, (a, b, got, want)
    # an oasis never reaches the bottom question, a cloud always does
    assert vm.loads('(oasis:steps (list "Center" nil nil nil nil nil nil nil'
                    ' nil nil nil nil nil))') == [0, 11, 1, 2, 3, 4, 5, 6, 7,
                                                 8, 9]
    assert vm.loads('(oasis:steps (list "Cloud" nil nil nil nil nil nil nil'
                    ' nil nil nil nil nil))') == [0, 10, 11, 1, 2, 3, 6, 7]
    assert vm.loads('(oasis:steps (list "Cloud" nil nil nil nil nil nil nil'
                    ' nil nil "Rounded" nil nil))') == [0, 10, 11, 1, 2, 3,
                                                        6, 7, 9]
    print("ok  cloud bottom-> asked after the shape, and it decides the rest")


def test_backing_out_of_the_bottom_reaches_the_shape():
    """Which bottom is the second question, so Back from it lands on the
    shape -- and answering that differently rebuilds every question after
    it."""
    vm = newvm()
    run(vm, ['CLoud', 'Back', 'Center', 'Simple', (0.0, 0.0)] + REF_MEASURE + [None], 'back out')
    assert len(arcs_of(vm)) == 6, arcs_of(vm)       # an oasis, not a cloud
    assert close(arcs_of(vm)[4][1], REF_BULGES[1]), arcs_of(vm)[4]
    asked = [p.lstrip('\n').split(' [')[0] for p, _ in vm.prompts]
    assert asked[:3] == ['Which shape is it?', 'Cloud bottom?',
                         'Which shape is it?'], asked
    assert 'Left bulge radius' in asked, asked   # only an oasis asks this
    print("ok  bottom back -> Back from the bottom re-asks the shape")



def test_true_kidney_matches_its_reference_drawing():
    """Three bulges and one reverse arc.  The user gives only the
    top-center radius and the bottom reverse; the two matching sides are
    derived from having to touch the top circle from inside, and every
    centre and angle must land on the customer drawing."""
    vm = newvm()
    run(vm, script(measure=KD_TRUE, variant='TrueKidney'), 'true kidney')
    arcs = arcs_of(vm, 4)
    assert len(arcs) == 4, arcs
    for (name, c, r, a0, a1), (gc, gr, ga0, ga1) in zip(KD_REF, arcs):
        assert close(gc[0], c[0], 1e-4) and close(gc[1], c[1], 1e-4), (name, gc)
        assert close(gr, r, 1e-4), (name, gr)
        for got_a, want_a in ((ga0, a0), (ga1, a1)):
            d = abs((got_a - want_a + 180.0) % 360.0 - 180.0)
            assert d <= 1e-5, (name, got_a, want_a)
    assert close(arcs[0][1], KD_SIDE, 1e-6), arcs[0]
    print("ok  true kidney -> four arcs on the customer drawing, sides"
          " derived at %.4f" % arcs[0][1])


def test_true_kidney_seams_hand_over_exactly():
    """At an internal tangency both arcs meet the joint at the SAME angle
    -- the side centre sits on the top circle's radius -- so the outline
    hands straight over with nothing drawn between."""
    vm = newvm()
    run(vm, script(measure=KD_TRUE, variant='TrueKidney'), 'seams')
    left, bottom, right, top = arcs_of(vm, 4)
    # right bulge ends where the top starts; top ends where left starts
    assert close(right[3], top[2], 1e-9), (right[3], top[2])
    assert close(top[3], left[2], 1e-9), (top[3], left[2])
    # and the joint really is the internal tangency point of both circles
    for side in (left, right):
        d = math.dist(side[0], top[0])
        assert close(d, top[1] - side[1], 1e-6), (d, top[1] - side[1])
    print("ok  seams       -> arcs hand over at the internal tangency,"
          " nothing between")


def test_true_kidney_fills_its_envelope():
    vm = newvm()
    run(vm, script(measure=KD_TRUE, variant='TrueKidney'), 'kidney bounds')
    over = vm.loads('(oasis:overruns (oasis:solve %.4f %.4f nil %.4f nil nil'
                    ' nil %.4f 0.0 "TrueKidney") %.4f %.4f)'
                    % (KD_X, KD_Y, KD_TOP, KD_BOT, KD_X, KD_Y))
    assert over is None, over
    cross = vm.loads('(oasis:crossings (oasis:solve %.4f %.4f nil %.4f nil'
                     ' nil nil %.4f 0.0 "TrueKidney"))'
                     % (KD_X, KD_Y, KD_TOP, KD_BOT))
    assert cross is None, cross
    print("ok  kd envelope -> fills 0,0 - %g,%g, simple, no crossings"
          % (KD_X, KD_Y))


def test_asym_kidney_derives_its_top_circle():
    """The two sides are given, unequal; the top circle is derived --
    tangent to the top bound and touching both sides from outside them,
    its centre landing wherever those three contacts put it."""
    vm = newvm()
    run(vm, script(measure=KD_ASYM, variant='AsymKidney'), 'asym kidney')
    arcs = arcs_of(vm, 4)
    left, bottom, right, top = arcs
    assert close(left[1], 96.0) and close(right[1], 72.0), (left, right)
    assert close(top[0][0], 175.029655, 1e-4), top
    assert close(top[1], 248.947416, 1e-4), top
    # tangent to the top bound: centre y + R = H
    assert close(top[0][1] + top[1], KD_Y, 1e-6), top
    # internal tangency to both sides
    for side in (left, right):
        assert close(math.dist(side[0], top[0]), top[1] - side[1], 1e-6), side
    # and the whole thing still fills the envelope exactly
    over = vm.loads('(oasis:overruns (oasis:solve %.4f %.4f 96.0 nil 72.0'
                    ' nil nil %.4f 0.0 "AsymKidney") %.4f %.4f)'
                    % (KD_X, KD_Y, KD_BOT, KD_X, KD_Y))
    assert over is None, over
    print("ok  asym kidney -> top circle derived at cx=%.3f R=%.3f,"
          " tangencies exact" % (top[0][0], top[1]))


def test_kidney_asks_its_own_questions():
    for variant, measure, want in (
            ('TrueKidney', KD_TRUE,
             ['Which shape is it?', 'Kidney type?', 'Simple or complex?',
              'Insertion base point',
              'X - overall left-to-right bounds',
              'Y - overall front-to-back bounds',
              'Top-center radius', 'Bottom-center tangent radius', BOTQ]),
            ('AsymKidney', KD_ASYM,
             ['Which shape is it?', 'Kidney type?', 'Simple or complex?',
              'Insertion base point',
              'X - overall left-to-right bounds',
              'Y - overall front-to-back bounds',
              'Left bulge radius', 'Right bulge radius',
              'Bottom-center tangent radius', BOTQ])):
        vm = newvm()
        run(vm, script(measure=measure, variant=variant), variant)
        asked = [p.lstrip('\n').split(' [')[0].split(' <')[0].rstrip(': ')
                 for p, _ in vm.prompts]
        assert asked == want, (variant, asked)
    print("ok  kd asks     -> true 8 measurements, asymmetric 9")


def test_true_kidney_top_radius_is_validated():
    """Below the minimum the top circle cannot reach both sides -- at the
    minimum it passes through the two bottom corners and the sides shrink
    to nothing -- so a too-small radius is re-asked with that minimum
    named."""
    vm = newvm()
    # min for 388 x 214 is 194.9346; 150 cannot work, 324 can
    run(vm, ['Kidney', 'True', 'Simple', (0.0, 0.0), KD_X, KD_Y, 150.0, KD_TOP,
             KD_BOT] + [None], 'small top')
    assert close(arcs_of(vm, 4)[3][1], KD_TOP), arcs_of(vm, 4)[3]
    mn = vm.loads('(oasis:ktrue-min %.4f %.4f)' % (KD_X, KD_Y))
    assert close(mn, KD_Y/2.0 + KD_X*KD_X/(8.0*KD_Y), 1e-9), mn
    print("ok  kd min top  -> a top circle under %.4f is re-asked" % mn)


def test_asym_kidney_unreachable_sides_are_reasked():
    """Within what ask-bulge admits, only one side pair has no top circle
    at all: both sides exactly half the Y bound -- that is a cloud, not a
    kidney, and its top circle degenerates.  The right-bulge hook catches
    it and re-asks, same as a nesting on the oasis."""
    vm = newvm()
    assert vm.loads('(oasis:kidney-top %.4f %.4f %.4f %.4f)'
                    % (KD_X, KD_Y, KD_Y/2.0, KD_Y/2.0)) is None
    run(vm, ['Kidney', 'Asymmetric', 'Simple', (0.0, 0.0), KD_X, KD_Y,
             KD_Y/2.0, KD_Y/2.0, 72.0, KD_BOT] + [None], 'degenerate pair')
    arcs = arcs_of(vm, 4)
    assert len(arcs) == 4, arcs
    assert close(arcs[2][1], 72.0), arcs[2]      # the re-answered right
    print("ok  kd reask    -> the degenerate half-Y side pair is re-asked")


def test_kidney_preview_labels_the_derived_circles():
    """The derived circles read their computed value from the start --
    the true kidney's sides while only the top has been given, the
    asymmetric one's top once the sides are in."""
    with at_each_prompt() as p:
        vm = newvm()
        run(vm, script(measure=KD_TRUE, variant='TrueKidney'), 'kd labels')
    # at the top-radius question everything is provisional: 1 ? (the
    # top), 1 ? (the bottom) -- wait: top is ?, bottom is ?, sides show
    # their derived value
    labels = [d[1] for d in p.shot(2, 'TEXT')]
    assert len(labels) == 4, labels
    assert labels.count('?') == 2, labels          # top + bottom asked
    derived = [t for t in labels if t != '?']
    assert len(derived) == 2 and derived[0] == derived[1], labels
    print("ok  kd labels   -> derived sides show a value, asked circles"
          " show ?")


def test_kidney_check_drawing_counts():
    """Four circles: 8 corner ties, 4 ring ties, and of the three bulge
    ties two duplicate the seams' ring ties, leaving left-right.  13
    dims, all in the cross style."""
    vm = newvm()
    run(vm, script(measure=KD_TRUE, variant='TrueKidney'), 'kd check')
    aligned = cmds(vm, '_.DIMALIGNED')
    assert len(aligned) == 13, len(aligned)
    dims = made(vm, 'DIMENSION')
    assert len(dims) == 15, len(dims)              # 2 pool + 13 check
    assert all(d[3] == 'Standard' for d in dims[:2]), dims[:2]
    assert all(d[3] == 'CROSS DIMENSIONS' for d in dims[2:]), dims[2]
    # the seam ring ties read the DIFFERENCE of the radii -- internal
    # tangency -- where every external pair reads the sum
    chk = check_arcs_of(vm, 4)
    left, bottom, right, top = chk
    assert close(math.dist(right[0], top[0]), top[1] - right[1], 1e-6)
    assert close(math.dist(left[0], bottom[0]), left[1] + bottom[1], 1e-6)
    print("ok  kd check    -> 13 cross dims; seam ties read R-r, external"
          " ties r1+r2")


def test_backing_up_through_a_kidney():
    """Back walks the kidney's own step list, not the oasis one: out of
    the top radius it lands on Y, out of the right bulge on the left, and
    out of the type question on the shape -- where a different answer
    rebuilds every question after it."""
    vm = newvm()
    run(vm, ['Kidney', 'True', 'Simple', (0.0, 0.0), KD_X, 200.0, 'Back', KD_Y,
             KD_TOP, KD_BOT] + [None], 'kd back Y')
    assert close(arcs_of(vm, 4)[3][1], KD_TOP), arcs_of(vm, 4)[3]
    # the re-answered Y is the one the envelope is built on
    assert close(arcs_of(vm, 4)[3][0][1], KD_Y - KD_TOP), arcs_of(vm, 4)[3]

    vm = newvm()
    run(vm, ['Kidney', 'Asymmetric', 'Simple', (0.0, 0.0), KD_X, KD_Y, 84.0, 'Back',
             96.0, 72.0, KD_BOT] + [None], 'kd back left')
    asked = [q.lstrip('\n').split(' [')[0] for q, _ in vm.prompts]
    assert asked[6:10] == ['Left bulge radius', 'Right bulge radius',
                           'Left bulge radius', 'Right bulge radius'], asked
    assert close(arcs_of(vm, 4)[0][1], 96.0), arcs_of(vm, 4)[0]

    vm = newvm()
    run(vm, ['Kidney', 'Back', 'Center', 'Simple', (0.0, 0.0)] + REF_MEASURE + [None],
        'kd back shape')
    assert len(arcs_of(vm)) == 6, arcs_of(vm)      # an oasis, not a kidney
    print("ok  kd back     -> Back walks the kidney's own steps, up to the"
          " shape itself")


def test_the_first_kidney_preview_is_never_blank():
    """The provisionals a kidney starts from have to make a ring.

    Every radius is provisional at the first radius question, and the
    bottom joiner's provisional is the one that can land under its own
    minimum -- below that there is no fillet, oasis:solve gives back nil
    and the user is asked to picture a pool from an empty box.  Sweep the
    envelopes the questions actually admit."""
    vm = newvm()

    def first_preview(w, h, kind):
        tail = '"Asymmetric"' if kind == 'Asym' else '"True"'
        return vm.loads(
            '(progn (setq $a (list "Kidney" (list 0.0 0.0) %.6f %.6f'
            '                      nil nil nil nil nil nil %s)'
            '             $f (oasis:fillin $a))'
            ' (oasis:solve (nth 0 $f) (nth 1 $f) (nth 2 $f) (nth 3 $f)'
            '              (nth 4 $f) (nth 5 $f) (nth 6 $f) (nth 7 $f)'
            '              (nth 8 $f) (oasis:variant $a)))' % (w, h, tail))

    blank, n = [], 0
    for wf in range(8, 68, 2):
        for hf in range(6, 46, 2):
            w, h = wf * 12.0, hf * 12.0
            for kind in ('True', 'Asym'):
                # a true kidney's Y question turns away Y >= X, so those
                # envelopes never reach a preview at all
                if kind == 'True' and h >= w:
                    continue
                n += 1
                if not first_preview(w, h, kind):
                    blank.append((kind, wf, hf))
    assert not blank, f"{len(blank)} of {n} blank, e.g. {blank[:5]}"
    print("ok  kd preview  -> all %d starting kidneys draw a ring" % n)


def test_a_true_kidney_needs_a_y_smaller_than_its_x():
    """Its matching sides are derived, not given: they come out less than
    Y across together whatever top radius they are derived from, so they
    fit inside X only while Y is under X.  No radius rescues a square
    envelope, so the Y question is where it has to be caught."""
    vm = newvm()
    # 240 x 240 is refused, 240 x 216 accepted in its place
    run(vm, ['Kidney', 'True', 'Simple', (0.0, 0.0), 240.0, 240.0, 216.0,
             264.0, 60.0] + [None], 'square Y')
    arcs = arcs_of(vm, 4)
    assert len(arcs) == 4, arcs
    assert close(arcs[3][1], 264.0), arcs[3]        # the re-answered top
    # and the two derived sides really do meet dead centre on the square
    # -- 2r == X exactly, which is why nothing downstream can join them
    for rt in (200.0, 300.0, 1000.0):
        g = vm.loads('(oasis:ktrue-side 240.0 240.0 %.4f)' % rt)
        assert close(g, 120.0, 1e-9), (rt, g)
    print("ok  kd Y < X    -> a Y at or over X is re-asked, not carried"
          " into a shape that cannot close")


#: the complex reference: the same 40' x 20' envelope and the same three
#: bulges, but every joiner answered Line.  A run between two bulges is
#: their common external tangent, so its length is the tangent length
#: sqrt(d^2 - (r1-r2)^2) between the two centres.
CX_RUNS = ['Line', 'Line', 'Line']


def tangent_len(c1, r1, c2, r2):
    return math.sqrt(math.dist(c1, c2) ** 2 - (r1 - r2) ** 2)


def elements(vm, n):
    """The pool's ring as drawn: ('ARC', centre, radius) or
    ('LINE', p1, p2), in creation order."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = _alist_dict(vm.entdata[e])
        if d.get(0) == 'ARC':
            out.append(('ARC', (d[10][0], d[10][1]), d[40]))
        elif d.get(0) == 'LINE' and d.get(8) == 'POOL':
            out.append(('LINE', (d[10][0], d[10][1]), (d[11][0], d[11][1])))
    return out[:n]


def test_complex_is_asked_after_the_shape():
    """Simple is the shape as it has always been, and it is the default,
    so a plain run is one Enter longer and nothing else.  Complex is
    where the straight runs and the off-centre hump live."""
    vm = newvm()
    run(vm, script(), 'simple')
    assert vm.prompts[1][0] == ('\nSimple or complex? [Simple/Complex/Back]'
                                ' <Simple>: '), repr(vm.prompts[1][0])
    # a simple joiner question takes a radius and nothing else
    joiner = [q for q, _ in vm.prompts if 'Top-left tangent' in q][0]
    assert joiner == '\nTop-left tangent radius [Back]: ', repr(joiner)
    assert len(arcs_of(vm)) == 6, arcs_of(vm)
    # a complex one offers Line at the same question, and asks the hump's
    # offset that a simple run never sees
    vm = newvm()
    run(vm, script(detail='Complex',
                   measure=[REF_X, REF_Y, 96.0, 132.0, 0.0, 108.0,
                            72.0, 36.0, 60.0]), 'complex')
    joiner = [q for q, _ in vm.prompts if 'Top-left tangent' in q][0]
    assert joiner == '\nTop-left tangent radius [Line/Back]: ', repr(joiner)
    asked = [q.lstrip('\n').split(' [')[0] for q, _ in vm.prompts]
    assert 'Top bulge off center, left negative' in asked, asked
    assert vm.loads('(oasis:steps (list "Center" nil nil nil nil nil nil nil'
                    ' nil nil nil "Complex" nil))') == [0, 11, 1, 2, 3, 4, 5,
                                                        12, 6, 7, 8, 9]
    print("ok  complex ask -> Simple by default; Complex adds Line and the"
          " hump's offset")


def test_a_straight_run_can_stand_in_for_any_joiner():
    """Line answers a joiner question the way a radius does, and what it
    draws is the common external tangent between the two bulges: from the
    tangent point on one to the tangent point on the other."""
    vm = newvm()
    run(vm, script(detail='Complex',
                   measure=[REF_X, REF_Y, 96.0, 132.0, 0.0, 108.0] + CX_RUNS),
        'all runs')
    ring = elements(vm, 6)
    kinds = [e[0] for e in ring]
    assert kinds == ['ARC', 'LINE', 'ARC', 'LINE', 'ARC', 'LINE'], kinds
    # the three bulges are untouched -- a run changes what joins them,
    # not where they sit
    assert [round(e[2], 6) for e in ring if e[0] == 'ARC'] == [96.0, 108.0,
                                                               132.0], ring
    cen = {r: c for _, c, r in ring if _ == 'ARC'}
    for (a, b), i in (((96.0, 108.0), 1), ((108.0, 132.0), 3),
                      ((132.0, 96.0), 5)):
        _, p, q = ring[i]
        want = tangent_len(cen[a], a, cen[b], b)
        assert close(math.dist(p, q), want), (i, math.dist(p, q), want)
        # and it really is tangent: the run is square to both radii
        for c, r in ((cen[a], a), (cen[b], b)):
            foot = min((p, q), key=lambda t: abs(math.dist(t, c) - r))
            assert close(math.dist(foot, c), r), (c, r, foot)
            v1 = (foot[0] - c[0], foot[1] - c[1])
            v2 = (q[0] - p[0], q[1] - p[1])
            assert abs(v1[0]*v2[0] + v1[1]*v2[1]) / (r * math.dist(p, q)) \
                <= 1.0e-12, (c, r, foot)
    print("ok  runs        -> Line draws the common tangent, square to both"
          " bulges")


def test_a_run_is_the_joiner_with_no_radius_left_to_give():
    """A straight run is not a special case bolted onto the ring: it is
    the reverse arc with an infinite radius.  Grow the radius by ten and
    the arc's ends close on the run's ten times faster."""
    vm = newvm()
    run(vm, script(detail='Complex',
                   measure=[REF_X, REF_Y, 96.0, 132.0, 0.0, 108.0,
                            72.0, 36.0, 'Line']), 'one run')
    _, p, q = elements(vm, 6)[1]
    ends = sorted((p, q))
    errs = []
    for rf in (1.0e4, 1.0e5, 1.0e6):
        a = solved(vm, REF_X, REF_Y, 96.0, 132.0, 108.0, 72.0, 36.0, rf)[1]
        got = sorted(pt_on((a[1][0], a[1][1]), a[2], math.degrees(t))
                     for t in (a[3], a[4]))
        errs.append(max(math.dist(g, e) for g, e in zip(got, ends)))
    for i in range(len(errs) - 1):
        assert 8.0 <= errs[i] / errs[i + 1] <= 12.0, errs
    assert errs[-1] <= 0.02, errs
    print("ok  run = R-inf -> ten times the radius, a tenth of the gap"
          " (%.1e\" at R=1e6)" % errs[-1])


def test_the_hump_moves_off_centre():
    """The offset is signed and moves the top bulge along X by exactly
    that much, left negative -- and the pool still fills its envelope."""
    vm = newvm()
    for off in (-72.0, 0.0, 72.0):
        vm = newvm()
        run(vm, script(detail='Complex',
                       measure=[REF_X, REF_Y, 96.0, 132.0, off, 108.0,
                                72.0, 36.0, 60.0]), 'off %g' % off)
        got = arcs_of(vm)
        top = [a for a in got if close(a[1], 132.0)][0]
        assert close(top[0][0], REF_X / 2.0 + off), (off, top)
        assert close(top[0][1], REF_Y - 132.0), (off, top)
        # the envelope is still absolute
        assert vm.loads('(oasis:overruns (oasis:solve %.1f %.1f 96.0 132.0'
                        ' 108.0 72.0 36.0 60.0 %.1f "Center") %.1f %.1f)'
                        % (REF_X, REF_Y, off, REF_X, REF_Y)) is None, off
    print("ok  hump offset -> the top bulge moves by exactly the offset,"
          " left negative")


def test_an_impossible_offset_is_reasked():
    """Two ways it can be: past either end of the envelope, where the
    hump is no longer over the water, or so far across that it swallows
    the left bulge."""
    vm = newvm()
    run(vm, script(detail='Complex',
                   measure=[REF_X, REF_Y, 96.0, 132.0, -300.0, 60.0, 108.0,
                            72.0, 36.0, 60.0]), 'off the box')
    top = [a for a in arcs_of(vm) if close(a[1], 132.0)][0]
    assert close(top[0][0], REF_X / 2.0 + 60.0), top    # the re-answer won
    vm = newvm()
    run(vm, script(detail='Complex',
                   measure=[REF_X, REF_Y, 96.0, 132.0, -120.0, 48.0, 108.0,
                            72.0, 36.0, 60.0]), 'nesting')
    top = [a for a in arcs_of(vm) if close(a[1], 132.0)][0]
    assert close(top[0][0], REF_X / 2.0 + 48.0), top
    assert vm.loads('(oasis:nested-p (oasis:topcen %.1f %.1f 132.0 "Center"'
                    ' -120.0) 132.0 (list 96.0 96.0) 96.0)'
                    % (REF_X, REF_Y)) is not None
    print("ok  bad offset  -> off the envelope or nesting the left bulge is"
          " re-asked")


def test_every_shape_takes_a_straight_run():
    """The ring does not care which shape it came from, so Line answers a
    joiner on all of them -- including the kidney, whose bottom is its
    only joiner."""
    for variant, measure, want in (
            ('TopRight', [443.0, 344.0, 108.0, 96.0, 108.0,
                          'Line', 'Line', 120.0],
             ['ARC', 'ARC', 'ARC', 'LINE', 'ARC', 'LINE']),
            ('RoundedBottom', [360.0, 240.0, 84.0, 'Line', 'Line'],
             ['ARC', 'LINE', 'ARC', 'LINE']),
            ('TrueKidney', [388.0, 214.0, 324.0, 'Line'],
             ['ARC', 'LINE', 'ARC', 'ARC']),
            ('AsymKidney', [388.0, 214.0, 96.0, 72.0, 'Line'],
             ['ARC', 'LINE', 'ARC', 'ARC'])):
        vm = newvm()
        run(vm, script(detail='Complex', measure=measure, variant=variant),
            variant)
        got = [e[0] for e in elements(vm, len(want))]
        assert got == want, (variant, got, want)
        # every run is dimensioned by length, never by radius
        nline = want.count('LINE')
        assert len(cmds(vm, '_.DIMALIGNED')) >= nline, variant
    print("ok  runs, shapes-> Line answers a joiner on all four families")


def test_a_pinched_bulge_is_left_out_of_the_drawing():
    """Two runs either side of a bulge can touch it at the same point --
    side bulges half the Y bound share the top bound's tangent with the
    hump.  The bulge is then a point on the outline, not an arc of it: it
    is not drawn, and the report says so rather than leaving an ARC whose
    two angles are equal, which AutoCAD would draw as a whole circle."""
    vm = newvm()
    run(vm, script(detail='Complex',
                   measure=[REF_X, REF_Y, 120.0, 200.0, 72.0, 120.0]
                           + CX_RUNS), 'pinched')
    ring = elements(vm, 5)
    assert [e[0] for e in ring] == ['ARC', 'LINE', 'ARC', 'LINE',
                                    'LINE'], ring
    # the two top runs are collinear: the hump's tangent point is the one
    # place both of them touch, and both lie along the Y-max bound
    assert all(close(p[1], REF_Y) for e in ring[3:] for p in e[1:]), ring
    assert vm.loads('(oasis:pinched (oasis:solve %.1f %.1f 120.0 200.0 120.0'
                    ' "LINE" "LINE" "LINE" 72.0 "Center") "Center")'
                    % (REF_X, REF_Y)) == ['top']
    print("ok  pinched     -> a bulge touched at one point is left out, and"
          " named")


def test_a_straight_run_is_crossed_like_any_arc():
    """A simple shape's one run lies along a bound with both its bulges
    tangent to it, so nothing can reach it; a complex one's runs slant
    across the pool and can be run through like anything else.  The test
    is exact -- segment against circle, segment against segment -- so it
    is checked here on elements built for it."""
    vm = newvm()

    def meet(a, b):
        return vm.loads('(oasis:meet-p %s %s)' % (a, b)) is not None

    RUN = '(list "run" (list 0.0 0.0) (list 100.0 0.0) 0.0 nil "LINE" nil)'
    OTHER = '(list "b" (list 40.0 20.0) (list 40.0 -20.0) 0.0 nil "LINE" nil)'
    APART = '(list "b" (list 40.0 20.0) (list 40.0 5.0) 0.0 nil "LINE" nil)'
    def arc(cx, cy, r, a0=0.0, a1=6.2831852):
        return ('(list "a" (list %.4f %.4f) %.4f %.6f %.6f T nil)'
                % (cx, cy, r, a0, a1))
    assert meet(RUN, arc(50.0, 0.0, 20.0))        # straight through it
    assert not meet(RUN, arc(50.0, 40.0, 20.0))   # clear above it
    assert not meet(RUN, arc(150.0, 0.0, 20.0))   # past the segment's end
    # on the circle but outside the drawn sweep
    assert not meet(RUN, arc(50.0, 0.0, 20.0, 1.0, 2.0))
    assert meet(RUN, OTHER)                       # two runs crossing
    assert not meet(RUN, APART)                   # and two that do not
    # and oasis:crossings really does put its runs through that test:
    # element 0 against element 2 is the one pair of a four-element ring
    # that is not two neighbours sharing an end
    far = '(list "%s" (list 0.0 %.1f) 5.0 0.0 1.0 T nil)'
    ring = ('(list %s %s %s %s)'
            % (RUN, far % ('b', 500.0), arc(50.0, 0.0, 20.0),
               far % ('d', -500.0)))
    assert vm.loads('(oasis:crossings %s)' % ring) == [['run', 'a']], \
        vm.loads('(oasis:crossings %s)' % ring)
    # and the reference pool, complex or not, is still simple
    assert vm.loads('(oasis:crossings (oasis:solve %.1f %.1f 96.0 132.0 108.0'
                    ' "LINE" "LINE" "LINE" 0.0 "Center"))'
                    % (REF_X, REF_Y)) is None
    print("ok  run crossed -> segment-against-circle and segment-against-"
          "segment, exact")


def test_a_run_already_answered_still_goes_red_when_re_asked():
    """A joiner answered Line keeps the answer slot it was given, so
    backing up to it picks it out in red like any other arc -- and the
    outline it belongs to is a straight run by then, with no circle and
    no radius behind it."""
    with at_each_prompt() as p:
        vm = newvm()
        run(vm, ['Center', 'Complex', (0.0, 0.0), REF_X, REF_Y, 96.0, 132.0,
                 0.0, 108.0, 'Line', 'Back', 'Line', 36.0, 60.0] + [None], 'red run')
    # shot 8 is the top-left question the second time round, with Line
    # already standing as its answer
    red = [d for d in p.shot(8, 'LINE')
           if d.get(8) == 'POOL' and d.get(62) == 1]
    assert len(red) == 1, [d for d in p.shot(8, 'LINE') if d.get(8) == 'POOL']
    # nothing else on the pool layer is picked out
    assert not [d for d in p.shot(8, 'ARC') if d.get(62) == 1], p.shot(8)
    print("ok  red run     -> a run already answered is still the one picked"
          " out when re-asked")


def test_backing_up_through_the_complex_questions():
    """Back walks the new steps like any other: out of the offset it
    lands on the top bulge, and out of simple-or-complex on the shape."""
    vm = newvm()
    run(vm, ['Center', 'Complex', (0.0, 0.0), REF_X, REF_Y, 96.0, 200.0,
             'Back', 132.0, 48.0, 108.0, 72.0, 36.0, 60.0] + [None], 'back offset')
    top = [a for a in arcs_of(vm) if close(a[1], 132.0)][0]
    assert close(top[0][0], REF_X / 2.0 + 48.0), top
    vm = newvm()
    run(vm, ['Center', 'Back', 'Center', 'Simple', (0.0, 0.0)] + REF_MEASURE + [None],
        'back detail')
    asked = [q.lstrip('\n').split(' [')[0] for q, _ in vm.prompts]
    assert asked[:4] == ['Which shape is it?', 'Simple or complex?',
                         'Which shape is it?', 'Simple or complex?'], asked
    assert len(arcs_of(vm)) == 6, arcs_of(vm)
    print("ok  complex back-> Back walks the offset and the detail question"
          " too")


#: the pool bottom, on the reference pool: shallow and deep breaks both
#: given as an offset in from the left bound, the standard 18" hopper
#: and two straight slope lines.
BOT_OFFSET = [None, 'Left', 120.0, None, 'Left', 300.0, None, None, None]


def pool_ring(vm, *dims, **kw):
    """oasis:solve on the reference pool, as the bottom code sees it."""
    return ('(oasis:solve %s %.4f "%s")'
            % (" ".join("%.6f" % v for v in (dims or (REF_X, REF_Y)
                                             + REF_BULGES + REF_TANGENTS)),
               kw.get('off', 0.0), kw.get('variant', 'Center')))


def bottom_of(vm, sh1, sh2, sd1, sd2, off, call=None):
    """oasis:bottom for one set of breaks, as a Python list."""
    return vm.loads('(oasis:bottom %s %.8f %.8f %.8f %.8f %.4f)'
                    % (call or pool_ring(vm), sh1, sh2, sd1, sd2, off))


def cut_at(vm, x, call=None):
    """Where the outline crosses the vertical line at X -- the two ends
    of a break located the Offset way."""
    return vm.loads('(oasis:ringcut %s (list %.6f 0.0) (list 1.0 0.0))'
                    % (call or pool_ring(vm), x))


def on_pool(vm, etype):
    return [d for d in made(vm, etype) if d.get(8) == 'POOL']


def el_at(e, u):
    """The point at fraction U of one ring element's own walk -- the rule
    oasis:eat follows, in Python, so a chain can be swept cheaply."""
    if e[5] == 'LINE':
        p, q = e[1], e[2]
        return (p[0] + (q[0] - p[0]) * u, p[1] + (q[1] - p[1]) * u)
    c, r, a0, a1 = e[1], e[2], e[3], e[4]
    sw = (a1 - a0) % (2 * math.pi)
    th = a0 + u * sw if e[5] is not None else a1 - u * sw
    return (c[0] + r * math.cos(th), c[1] + r * math.sin(th))


def el_tan(e, u):
    """The direction the walk is heading at that fraction."""
    if e[5] == 'LINE':
        return math.atan2(e[2][1] - e[1][1], e[2][0] - e[1][0])
    a0, a1 = e[3], e[4]
    sw = (a1 - a0) % (2 * math.pi)
    if e[5] is not None:
        return a0 + u * sw + math.pi / 2.0
    return a1 - u * sw - math.pi / 2.0


def ring_inside(vm, call, p):
    """Is P inside the outline?  Cast a ray along +X from it and count the
    crossings -- odd means in the water."""
    hits = vm.loads('(oasis:ringcut %s (list %.8f %.8f) (list 0.0 1.0))'
                    % (call, p[0], p[1])) or []
    n = 0
    for t in hits:
        q = vm.loads('(oasis:ringat %s %.10f)' % (call, t))[0]
        if q[0] > p[0]:
            n += 1
    return n % 2 == 1


def plines(vm, lay='POOL'):
    """Every surviving open polyline's vertices, in creation order.  A
    polyline carries one group 10 per vertex, so the flattened dict of
    _alist_dict only ever shows the first -- they have to be read off the
    entity's own list."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        raw = vm.entdata[e]
        d = _alist_dict(raw)
        if d.get(0) != 'LWPOLYLINE' or d.get(8) != lay:
            continue
        pts = []
        for pr in raw:
            if isinstance(pr, Dot) and pr.a == 10:
                pts.append(pr.b)
            elif isinstance(pr, list) and pr and pr[0] == 10:
                pts.append(pr[1:])
        out.append(pts)
    return out


class at_each_int(object):
    """Snapshot the drawing at every whole-number prompt -- which is only
    the tangency question, so this photographs the marks it puts up."""

    def __enter__(self):
        self.shots = []
        self.saved = BUILTINS[Sym('getint')]

        def _g(vm, a):
            self.shots.append([dict(_alist_dict(vm.entdata[e]))
                               for e in vm.entities if e not in vm.deleted])
            return self.saved(vm, a)

        BUILTINS[Sym('getint')] = _g
        return self

    def __exit__(self, *exc):
        BUILTINS[Sym('getint')] = self.saved
        return False


def test_the_bottom_is_offered_once_the_pool_is_drawn():
    """The perimeter finishes first and reports itself; only then is the
    floor offered, and the default is No, so a run that only wants the
    outline is one Enter longer."""
    vm = newvm()
    run(vm, script(), 'no bottom')
    last = vm.prompts[-1][0]
    assert last == ('\nAdd the bottom of the pool (breaks and hopper)?'
                    ' [Yes/No] <No>: '), repr(last)
    assert len(arcs_of(vm, 99)) == 12, len(arcs_of(vm, 99))   # pool + check
    assert not on_pool(vm, 'LINE'), on_pool(vm, 'LINE')
    print("ok  bottom ask  -> offered last, default No, and No leaves the"
          " pool alone")


def test_a_break_is_located_three_ways():
    """Offset says how far in from a bound and takes both ends of the
    break from where that line crosses the pool; Tangency names a change
    of tangency by its number; Nearest drops a pick onto the outline at
    the nearest point of it.  All three land on the perimeter."""
    vm = newvm()
    call = pool_ring(vm)
    joints = vm.loads('(oasis:joints %s)' % call)

    # -- Offset: 10'-0" in from the left bound is x = 120, both ends
    cuts = vm.loads('(oasis:ringcut %s (list 120.0 0.0) (list 1.0 0.0))'
                    % call)
    assert len(cuts) == 2, cuts
    for c in cuts:
        p = vm.loads('(oasis:ringat %s %.10f)' % (call, c))[0]
        assert close(p[0], 120.0), p

    # -- Tangency: the numbers are the joints, in ring order
    for i, s in enumerate(joints):
        p = vm.loads('(oasis:ringat %s %.10f)' % (call, s))[0]
        q = vm.loads('(car (oasis:eat (nth %d %s) 0.0))' % (i, call))
        assert close(math.dist(p, q), 0.0, 1e-9), (i, p, q)

    # -- Nearest: a pick well off the outline comes back on it
    for pick in ((240.0, -200.0), (0.0, 0.0), (700.0, 500.0),
                 (240.0, 120.0)):
        s = vm.loads('(oasis:ringnear %s (list %.4f %.4f))'
                     % ((call,) + pick))
        p = vm.loads('(oasis:ringat %s %.10f)' % (call, s))[0]
        # it really is the nearest: nothing on the ring is closer
        best = min(math.dist(pick, vm.loads('(oasis:ringat %s %.8f)'
                                            % (call, k * 1265.0 / 180.0))[0])
                   for k in range(180))
        assert math.dist(pick, p) <= best + 1e-6, (pick, p, best)
    print("ok  break where -> offset / tangency / nearest all land on the"
          " outline")


def test_the_tangency_changes_are_numbered_on_screen():
    """They cannot be named if they cannot be seen, so the marks go up
    while the question is -- one per change, numbered from 1 -- and come
    down with the rest of the scaffolding."""
    with at_each_int() as p:
        vm = newvm()
        run(vm, script(bottom=['Tangency', 1, 2, 'Tangency', 3, 4,
                               None, None, None]), 'marks')
    shot = p.shots[0]
    labels = sorted(d[1] for d in shot if d.get(0) == 'TEXT')
    assert labels == ['1', '2', '3', '4', '5', '6'], labels
    marks = [d for d in shot
             if d.get(0) == 'CIRCLE' and d.get(8) == 'POOL-GUIDE']
    assert len(marks) >= 6, len(marks)
    # and every one of them sits on a change of tangency
    call = pool_ring(vm)
    joints = vm.loads('(oasis:joints %s)' % call)
    js = [tuple(vm.loads('(oasis:ringat %s %.10f)' % (call, s))[0])
          for s in joints]
    for d in marks[-6:]:
        assert any(close(math.dist(d[10][:2], j), 0.0, 1e-6) for j in js), d
    # gone by the time the run ends
    assert not [d for d in made(vm, 'TEXT')], made(vm, 'TEXT')
    print("ok  tang marks  -> six numbered marks while the question is up,"
          " none after")


def test_the_hopper_is_the_wall_offset_inward():
    """Offsetting a tangent-continuous ring inward by a constant gives
    another one -- same centres, same angles, every bulge shrunk and
    every reverse arc grown -- so the hopper is arcs and runs, exactly
    the offset in from the wall, and INSIDE it."""
    vm = newvm()
    call = pool_ring(vm)
    # 6' and 20' in from the left: those breaks cut the ring mid-arc at
    # both ends, one of them on a REVERSE arc, so the trimming is real
    sh, sd = cut_at(vm, 72.0, call), cut_at(vm, 240.0, call)
    bot = bottom_of(vm, sh[0], sh[1], sd[0], sd[1], 18.0)
    assert not isinstance(bot, str), bot
    hop, cs, ce, pda, pdb = bot[0], bot[1], bot[2], bot[3], bot[4]
    assert len(hop) >= 2, hop
    assert any(e[5] is None for e in (hop[0], hop[-1])), \
        [e[5] for e in hop]                # a trimmed reverse arc
    worst = 0.0
    for e in hop:
        for u in (0.0, 0.25, 0.5, 0.75, 1.0):
            q = el_at(e, u)
            t = vm.loads('(oasis:ringnear %s (list %.10f %.10f))'
                         % (call, q[0], q[1]))
            w = vm.loads('(oasis:ringat %s %.10f)' % (call, t))[0]
            worst = max(worst, abs(math.dist(q, w) - 18.0))
            # 18" from the wall is two places; the hopper is the one in
            # the water
            assert ring_inside(vm, call, q), q
    assert worst <= 1.0e-8, worst
    # the chain is one curve: consecutive elements meet, and meet smoothly
    for i in range(len(hop) - 1):
        assert close(math.dist(el_at(hop[i], 1.0), el_at(hop[i+1], 0.0)),
                     0.0, 1e-8), i
        d = abs((el_tan(hop[i], 1.0) - el_tan(hop[i+1], 0.0) + math.pi)
                % (2 * math.pi) - math.pi)
        assert d <= 1.0e-9, (i, d)
    # it starts and ends ON the two corners, which are ON the deep break
    assert close(math.dist(el_at(hop[0], 0.0), cs), 0.0, 1e-8) or \
        close(math.dist(el_at(hop[0], 0.0), ce), 0.0, 1e-8), hop[0]
    bx, by = pdb[0] - pda[0], pdb[1] - pda[1]
    bl = math.hypot(bx, by)
    for c, ends in ((cs, (el_at(hop[0], 0.0), el_at(hop[-1], 1.0))),
                    (ce, (el_at(hop[0], 0.0), el_at(hop[-1], 1.0)))):
        assert min(math.dist(c, e) for e in ends) <= 1e-8, c
        assert abs((c[0]-pda[0]) * (-by/bl) + (c[1]-pda[1]) * (bx/bl)) \
            <= 1e-8, c
    # each corner belongs to the wall end it is nearest
    assert math.dist(cs, pda) < math.dist(cs, pdb), (cs, pda, pdb)
    assert math.dist(ce, pdb) < math.dist(ce, pda), (ce, pda, pdb)
    print("ok  hopper      -> the wall offset 18\" inward, exactly (%.1e\"),"
          " inside, corners on the break" % worst)


def test_the_hopper_lies_beyond_the_deep_break():
    """It is the DEEP end: every part of it is on the far side of the
    deep break from the shallow one, and its deepest point is the pool's
    own."""
    vm = newvm()
    call = pool_ring(vm)
    sh, sd = cut_at(vm, 120.0, call), cut_at(vm, 300.0, call)
    bot = bottom_of(vm, sh[0], sh[1], sd[0], sd[1], 18.0)
    assert not isinstance(bot, str), bot
    hop, pda, pdb, qsa, qsb = bot[0], bot[3], bot[4], bot[5], bot[6]
    qm = ((qsa[0] + qsb[0]) / 2.0, (qsa[1] + qsb[1]) / 2.0)
    u = vm.loads('(oasis:deepdir (list %.8f %.8f) (list %.8f %.8f)'
                 ' (list %.8f %.8f))'
                 % (pda[0], pda[1], pdb[0], pdb[1], qm[0], qm[1]))
    mid = ((pda[0] + pdb[0]) / 2.0, (pda[1] + pdb[1]) / 2.0)
    depths = []
    for e in hop:
        for uu in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0):
            q = el_at(e, uu)
            depths.append((q[0]-mid[0]) * u[0] + (q[1]-mid[1]) * u[1])
    assert min(depths) >= -1.0e-8, min(depths)
    assert max(depths) > 1.0, max(depths)
    # and the shallow break really is on the other side of it
    for q in (qsa, qsb):
        assert (q[0]-mid[0]) * u[0] + (q[1]-mid[1]) * u[1] < 0.0, q
    print("ok  hopper side -> all of it beyond the deep break, %.1f\" at the"
          " deepest" % max(depths))


def test_the_deep_break_goes_down_in_three_pieces():
    """A dashed stub from each wall in to its hopper corner and a solid
    run across the hopper between them -- collinear, and carrying the
    K/L/M string of chained dimensions."""
    vm = newvm()
    run(vm, script(bottom=BOT_OFFSET), 'three pieces')
    lines = on_pool(vm, 'LINE')
    # the shallow break, then the deep break's three, then two straight
    # slope lines
    assert len(lines) == 6, len(lines)
    stub1, solid, stub2 = lines[1], lines[2], lines[3]
    assert 6 in stub1 and 6 in stub2, (stub1, stub2)   # dashed
    assert 6 not in solid, solid                        # ByLayer
    # collinear, and joined end to end
    assert close(math.dist(stub1[11][:2], solid[10][:2]), 0.0, 1e-8)
    assert close(math.dist(solid[11][:2], stub2[10][:2]), 0.0, 1e-8)
    v1 = (solid[11][0]-stub1[10][0], solid[11][1]-stub1[10][1])
    for p in (stub1[11], solid[11]):
        v2 = (p[0]-stub1[10][0], p[1]-stub1[10][1])
        assert abs(v1[0]*v2[1] - v1[1]*v2[0]) <= 1e-6, (v1, v2)
    # three chained dims on it, plus the offset at the back
    dims = [d for d in made(vm, 'DIMENSION') if d[3] == 'Standard']
    assert len(dims) == 2 + 4, len(dims)   # the pool's two, then K/L/M + back
    klm = dims[2:5]
    # K, L and M measure the three pieces in order
    for d, piece in zip(klm, (stub1, solid, stub2)):
        assert close(math.dist(d[13][:2], piece[10][:2]), 0.0, 1e-8), d
        assert close(math.dist(d[14][:2], piece[11][:2]), 0.0, 1e-8), d
    # their dimension lines are collinear and stand off on the SHALLOW
    # side -- the string reads from the shallow end, not from over the
    # deep end it measures
    pda, pdb = stub1[10][:2], stub2[11][:2]
    mid = ((pda[0] + pdb[0]) / 2.0, (pda[1] + pdb[1]) / 2.0)
    bx, by = pdb[0] - pda[0], pdb[1] - pda[1]
    bl = math.hypot(bx, by)
    nx, ny = -by / bl, bx / bl
    shal = [d for d in on_pool(vm, 'LINE')][0]            # the shallow break
    smid = ((shal[10][0] + shal[11][0]) / 2.0,
            (shal[10][1] + shal[11][1]) / 2.0)
    towards = (smid[0] - mid[0]) * nx + (smid[1] - mid[1]) * ny
    offs = [(d[10][0] - mid[0]) * nx + (d[10][1] - mid[1]) * ny for d in klm]
    assert all(o * towards > 0.0 for o in offs), offs
    assert max(offs) - min(offs) <= 1e-8, offs
    print("ok  deep break  -> dashed stub / solid run / dashed stub,"
          " collinear, K/L/M dimensioned")


def test_a_guided_slope_follows_the_wall_in():
    """Straight is a clean run from the hopper's corner to the shallow
    break; guided follows the pool's own wall instead, its offset easing
    from the hopper's at the deep break to nothing at the shallow one."""
    vm = newvm()
    run(vm, script(bottom=[None, 'Left', 120.0, None, 'Left', 300.0, None,
                           'Guided', None]), 'guided')
    pls = plines(vm)
    assert len(pls) == 1, len(pls)
    pts = pls[0]
    assert len(on_pool(vm, 'LINE')) == 5, len(on_pool(vm, 'LINE'))
    # the run eases: its first vertex is on the wall, its last is the
    # hopper corner, and in between it stays inside the pool
    call = pool_ring(vm)
    first, last = pts[0], pts[-1]
    s = vm.loads('(oasis:ringnear %s (list %.8f %.8f))'
                 % (call, first[0], first[1]))
    w = vm.loads('(oasis:ringat %s %.10f)' % (call, s))[0]
    assert close(math.dist(first[:2], w), 0.0, 1e-6), (first, w)
    rl = vm.loads('(oasis:ringlen %s)' % call)
    offs = []
    for v in pts:
        s = vm.loads('(oasis:ringnear %s (list %.8f %.8f))' % (call, v[0], v[1]))
        w = vm.loads('(oasis:ringat %s %.10f)' % (call, s))[0]
        offs.append(math.dist(v[:2], w))
    assert offs[0] <= 1e-6, offs[0]
    assert max(offs) <= 18.0 + 1e-6, max(offs)
    assert offs[len(offs)//2] > 1.0, offs
    # every vertex is in the water -- an offset measured the wrong way
    # would put them outside the wall it is easing off
    for v in pts[1:]:
        assert ring_inside(vm, call, v[:2]), v
    # and the last one IS the hopper's corner, on the deep break line
    sh, sd = cut_at(vm, 120.0, call), cut_at(vm, 300.0, call)
    bot = bottom_of(vm, sh[0], sh[1], sd[0], sd[1], 18.0)
    assert min(math.dist(pts[-1][:2], c) for c in (bot[1], bot[2])) \
        <= 1.0e-8, (pts[-1], bot[1], bot[2])
    print("ok  guided slope-> starts on the wall, eases out to the hopper's"
          " 18\" at the deep break")


def test_the_two_slope_lines_never_cross():
    """Each runs from a hopper corner to the shallow break point on its
    OWN side, so the sides have to be paired by walking away from the
    hopper.  Pair them the other way and the two lines cross the pool."""
    vm = newvm()
    run(vm, script(bottom=BOT_OFFSET), 'slopes')
    lines = on_pool(vm, 'LINE')
    a, b = lines[4], lines[5]                 # the two straight slopes
    p1, p2 = a[10][:2], a[11][:2]
    q1, q2 = b[10][:2], b[11][:2]

    def side(u, v, w):
        return ((v[0]-u[0]) * (w[1]-u[1]) - (v[1]-u[1]) * (w[0]-u[0]))

    assert side(p1, p2, q1) * side(p1, p2, q2) > 0.0 or \
        side(q1, q2, p1) * side(q1, q2, p2) > 0.0, (a, b)
    # each ends on a shallow break point, and they are different ones
    shal = lines[0]
    ends = [shal[10][:2], shal[11][:2]]
    got = [min(range(2), key=lambda i: math.dist(x, ends[i]))
           for x in (p2, q2)]
    assert sorted(got) == [0, 1], (p2, q2, ends)
    print("ok  slopes      -> one per side, paired away from the hopper, and"
          " they do not cross")


def test_a_bound_line_that_cuts_four_times_takes_the_break_right_across():
    """A pool whose edge dips is crossed more than twice by one line.
    The break is the full width of it, so the two OUTERMOST crossings are
    the ones taken and the rest are the dip it runs over."""
    vm = newvm()
    call = pool_ring(vm)
    cuts = vm.loads('(oasis:ringcut %s (list 0.0 36.0) (list 0.0 1.0))'
                    % call)
    assert len(cuts) == 4, cuts
    xs = [vm.loads('(oasis:ringat %s %.10f)' % (call, c))[0][0] for c in cuts]
    # the outermost pair spans the pool; the inner two are the dip
    assert min(xs) in (xs[0], xs[-1]) and max(xs) in (xs[0], xs[-1]), xs
    run(vm, script(bottom=[None, 'BOttom', 36.0, None, 'BOttom', 120.0,
                           None, None, None]), 'four cuts')
    shal = on_pool(vm, 'LINE')[0]
    got = sorted((shal[10][0], shal[11][0]))
    assert close(got[0], min(xs)) and close(got[1], max(xs)), (got, xs)
    print("ok  four cuts   -> the break spans the outermost pair, not the"
          " first two")


def test_the_bottom_of_a_pool_with_straight_runs():
    """The hopper and the slopes read the ring, so a straight run in the
    wall is offset and followed like any arc -- across, not out."""
    vm = newvm()
    call = pool_ring(vm, REF_X, REF_Y, 96.0, 132.0, 108.0)
    call = ('(oasis:solve %.1f %.1f 96.0 132.0 108.0 "LINE" "LINE" "LINE"'
            ' 0.0 "Center")' % (REF_X, REF_Y))
    sh, sd = cut_at(vm, 120.0, call), cut_at(vm, 300.0, call)
    bot = bottom_of(vm, sh[0], sh[1], sd[0], sd[1], 18.0, call=call)
    assert not isinstance(bot, str), bot
    hop = bot[0]
    assert any(e[5] == 'LINE' for e in hop), [e[5] for e in hop]
    for e in hop:
        for u in (0.0, 0.5, 1.0):
            q = el_at(e, u)
            t = vm.loads('(oasis:ringnear %s (list %.10f %.10f))'
                         % (call, q[0], q[1]))
            w = vm.loads('(oasis:ringat %s %.10f)' % (call, t))[0]
            assert close(math.dist(q, w), 18.0, 1e-8), (e[0], u, q, w)
            assert ring_inside(vm, call, q), (e[0], u, q)
    # and a guided slope over a run stays in the water too
    pts = vm.loads('(oasis:chordrun %s %.8f %.8f 0.0 18.0 12)'
                   % (call, sh[0], sd[0]))
    for v in pts[1:]:
        assert ring_inside(vm, call, v), v
    print("ok  bottom, runs-> a straight run in the wall is offset across"
          " it, not out through it")


def test_breaks_the_wrong_way_round_are_refused():
    """The shallow break has to be on the shallow side of the deep one.
    Put it past the deep break and the slope lines would have to run
    through the hopper to reach it, so the offset question comes round
    again rather than drawing that."""
    vm = newvm()
    call = pool_ring(vm)
    js = vm.loads('(oasis:joints %s)' % call)
    # 1/2 and 3/4 are the two ends of the pool; 1/3 against 2/4 interleaves
    good = bottom_of(vm, js[0], js[1], js[2], js[3], 18.0)
    assert not isinstance(good, str), good
    swapped = bottom_of(vm, js[0], js[2], js[1], js[3], 18.0)
    assert isinstance(swapped, str) and 'swapped' in swapped, swapped
    print("ok  breaks order-> a shallow break past the deep one is refused")


def test_a_hopper_offset_with_no_room_is_reasked():
    """The offset is only wrong against this pool, so the check is the
    build: past a bulge's own radius there is no wall left inside it to
    draw, and the question comes round again."""
    vm = newvm()
    call = pool_ring(vm)
    assert vm.loads('(oasis:offbad %s 200.0)' % call) == 'left', \
        vm.loads('(oasis:offbad %s 200.0)' % call)
    assert vm.loads('(oasis:offring %s 200.0)' % call) is None
    run(vm, script(bottom=[None, 'Left', 120.0, None, 'Left', 300.0,
                           200.0, 18.0, None, None]), 'too deep')
    # the re-answered 18 is the one that got built
    assert len(on_pool(vm, 'LINE')) == 6, len(on_pool(vm, 'LINE'))
    print("ok  bad hopper  -> an offset wider than a bulge is re-asked")


def test_backing_out_of_the_bottom_leaves_the_pool_alone():
    """Back walks the bottom's own steps, and Back out of the first of
    them adds nothing at all -- the perimeter is already drawn and stays
    exactly as it was."""
    vm = newvm()
    run(vm, script(bottom=['Back']), 'backed out')
    assert not on_pool(vm, 'LINE'), on_pool(vm, 'LINE')
    assert len(arcs_of(vm, 99)) == 12, len(arcs_of(vm, 99))
    vm = newvm()
    run(vm, script(bottom=[None, 'Left', 120.0, None, 'Left', 300.0,
                           'Back', None, 'Left', 300.0, None, None, None]),
        'back one step')
    assert len(on_pool(vm, 'LINE')) == 6, len(on_pool(vm, 'LINE'))
    print("ok  bottom back -> Back out of the first step adds nothing; one"
          " step back re-asks the deep break")


def test_the_bottom_shares_the_pools_undo_group():
    """One U has to take the pool and its floor together, so the flow
    runs inside the group the perimeter opened."""
    vm = newvm()
    run(vm, script(bottom=BOT_OFFSET), 'undo')
    us = [c for c in vm.commands if c and c[0] == '_.UNDO']
    assert [c[1] for c in us] == ['_Begin', '_End'], us
    # the last thing drawn is inside it: no _End before the bottom's lines
    assert on_pool(vm, 'LINE'), 'nothing was drawn'
    print("ok  bottom undo -> one group round the pool and its bottom")


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
    test_check_drawing_ties_the_bulges_to_each_other()
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
    test_straight_bottom_matches_its_reference_drawing()
    test_rounded_bottom_matches_its_reference_drawing()
    test_both_clouds_fill_their_envelope()
    test_the_flat_bottom_is_the_bound_itself()
    test_the_clouds_ask_four_or_five_measurements()
    test_the_flat_run_is_dimensioned_by_length_not_radius()
    test_the_cloud_preview_shows_no_circle_behind_the_flat_run()
    test_a_cloud_is_one_shape_with_two_bottoms()
    test_backing_out_of_the_bottom_reaches_the_shape()
    test_true_kidney_matches_its_reference_drawing()
    test_true_kidney_seams_hand_over_exactly()
    test_true_kidney_fills_its_envelope()
    test_asym_kidney_derives_its_top_circle()
    test_kidney_asks_its_own_questions()
    test_true_kidney_top_radius_is_validated()
    test_asym_kidney_unreachable_sides_are_reasked()
    test_kidney_preview_labels_the_derived_circles()
    test_kidney_check_drawing_counts()
    test_backing_up_through_a_kidney()
    test_the_first_kidney_preview_is_never_blank()
    test_a_true_kidney_needs_a_y_smaller_than_its_x()
    test_complex_is_asked_after_the_shape()
    test_a_straight_run_can_stand_in_for_any_joiner()
    test_a_run_is_the_joiner_with_no_radius_left_to_give()
    test_the_hump_moves_off_centre()
    test_an_impossible_offset_is_reasked()
    test_every_shape_takes_a_straight_run()
    test_a_pinched_bulge_is_left_out_of_the_drawing()
    test_a_straight_run_is_crossed_like_any_arc()
    test_a_run_already_answered_still_goes_red_when_re_asked()
    test_backing_up_through_the_complex_questions()
    test_the_bottom_is_offered_once_the_pool_is_drawn()
    test_a_break_is_located_three_ways()
    test_the_tangency_changes_are_numbered_on_screen()
    test_the_hopper_is_the_wall_offset_inward()
    test_the_hopper_lies_beyond_the_deep_break()
    test_the_deep_break_goes_down_in_three_pieces()
    test_a_guided_slope_follows_the_wall_in()
    test_the_two_slope_lines_never_cross()
    test_a_bound_line_that_cuts_four_times_takes_the_break_right_across()
    test_the_bottom_of_a_pool_with_straight_runs()
    test_breaks_the_wrong_way_round_are_refused()
    test_a_hopper_offset_with_no_room_is_reasked()
    test_backing_out_of_the_bottom_leaves_the_pool_alone()
    test_the_bottom_shares_the_pools_undo_group()
    test_version_command()
    test_no_local_shadows_a_function()
    print("all OASIS tests passed")
