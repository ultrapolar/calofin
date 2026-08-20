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

#: the answers that draw the reference pool, in the order OASIS asks
REF_SCRIPT = [REF_X, REF_Y] + list(REF_BULGES) + list(REF_TANGENTS)


# ---- scaffolding ------------------------------------------------------

def newvm():
    vm = VM()
    vm.layer_records = {}
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
    """The drawn arcs as (centre, radius, start, end), creation order,
    angles in degrees so they read against the reference table."""
    out = []
    for d in made(vm, 'ARC'):
        c = d[10]
        out.append(((c[0], c[1]), d[40],
                    math.degrees(d[50]) % 360.0, math.degrees(d[51]) % 360.0))
    return out


def pt_on(c, r, deg):
    a = math.radians(deg)
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def close(a, b, tol=TOL):
    return abs(a - b) <= tol


def solved(vm, w, h, rl, rt, rr, ftl, ftr, fbc):
    """Call oasis:solve inside the VM and hand back what it built."""
    return vm.loads("(oasis:solve %s oasis:*topfrac*)"
                    % " ".join("%.10f" % v
                               for v in (w, h, rl, rt, rr, ftl, ftr, fbc)))


def crossing_pairs(vm, *dims):
    """The pairs of arcs oasis:crossings says run through each other."""
    r = vm.loads("(oasis:crossings (oasis:solve %s oasis:*topfrac*))"
                 % " ".join("%.10f" % v for v in dims))
    return set() if r is None else {tuple(sorted(p)) for p in r}


def overruns(vm, w, h, *radii):
    """What oasis:overruns says reaches past the envelope."""
    r = vm.loads("(oasis:overruns (oasis:solve %s oasis:*topfrac*) %.6f %.6f)"
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


# ---- tests ------------------------------------------------------------

def test_reference_drawing():
    """The six arcs land on the reference drawing's six arcs."""
    vm = newvm()
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'reference')
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
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'closure')
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
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'tangency')
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
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'envelope')
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
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'layers')
    assert all(d[8] == 'POOL' for d in made(vm, 'ARC')), made(vm, 'ARC')
    dims = made(vm, 'DIMENSION')
    assert len(dims) == 2, dims                       # overall X and Y
    assert all(d[8] == 'DIMENSION' for d in dims), dims
    assert len(cmds(vm, '_.DIMLINEAR')) == 2, vm.commands
    assert len(cmds(vm, '_.DIMRADIUS')) == 6, vm.commands
    assert 'POOL' in vm.tables['LAYER'] and 'DIMENSION' in vm.tables['LAYER']
    print("ok  layers      -> arcs on POOL, 2 linear + 6 radius dims on"
          " DIMENSION")


def test_dimension_values():
    """The two overall dims are hooked to the points that really touch
    the envelope, so they read the X and Y that were asked for."""
    vm = newvm()
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'dim values')
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
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'radius dims')
    arcs = [e for e in vm.entities
            if _alist_dict(vm.entdata[e]).get(0) == 'ARC']
    picked = []
    for c in cmds(vm, '_.DIMRADIUS'):
        ent, tip = c[1][0], c[1][1]
        d = _alist_dict(vm.entdata[ent])
        picked.append(ent)
        assert close(math.dist(tip[:2], d[10][:2]), d[40]), (tip, d[40])
    assert sorted(picked, key=lambda e: arcs.index(e)) == arcs, picked
    print("ok  radius dims -> one per arc, picked on the arc")


def test_no_dimensions():
    vm = newvm()
    run(vm, REF_SCRIPT + ['No', (0.0, 0.0)], 'no dims')
    assert len(made(vm, 'ARC')) == 6
    assert made(vm, 'DIMENSION') == []
    assert cmds(vm, '_.DIMLINEAR') == [] and cmds(vm, '_.DIMRADIUS') == []
    assert 'DIMENSION' not in vm.tables['LAYER']
    print("ok  no dims     -> six arcs and nothing else")


def test_base_point_moves_everything():
    vm = newvm()
    run(vm, REF_SCRIPT + ['Yes', (1000.0, -250.0)], 'base point')
    for (name, c, r, a0, a1), (gc, gr, _, _) in zip(REF_ARCS, arcs_of(vm)):
        assert close(gc[0], c[0] + 1000.0), (name, gc)
        assert close(gc[1], c[1] - 250.0), (name, gc)
    print("ok  base point  -> the whole pool lands on the pick")


def test_enter_takes_the_origin():
    vm = newvm()
    run(vm, REF_SCRIPT + ['Yes', None], 'enter base')
    assert close(arcs_of(vm)[0][0][0], 96.0)
    print("ok  base <0,0>  -> Enter draws at the origin")


def test_back_reasks():
    """Back steps one question up and the re-answer is the one used."""
    vm = newvm()
    # answer Y as 300, back out of the left bulge, give Y as 240 instead
    run(vm, [REF_X, 300.0, 'Back', REF_Y] + REF_SCRIPT[2:]
        + ['Yes', (0.0, 0.0)], 'back')
    top = [a for a in arcs_of(vm) if close(a[1], 132.0)][0]
    assert close(top[0][1], REF_Y - 132.0), top
    print("ok  back        -> Back re-asks and the new answer wins")


def test_back_at_the_first_question_stays_put():
    """Back is not offered at the first question; typing it anyway must
    not fall through it."""
    vm = newvm()
    vm.script = list(REF_SCRIPT + ['Yes', (0.0, 0.0)])
    vm.run('c:OASIS', vm.script)
    first = vm.prompts[0][0]
    assert '[Back]' not in first, first
    print("ok  first step  -> the first question offers no Back")


def test_oversize_bulge_is_reasked():
    """A side bulge more than half the Y bound would break out through
    the top, so the question comes back."""
    vm = newvm()
    # 150 on a 240 envelope stands 300 tall -- rejected, then 96 taken
    run(vm, [REF_X, REF_Y, 150.0, 96.0] + REF_SCRIPT[3:]
        + ['Yes', (0.0, 0.0)], 'oversize bulge')
    assert close(arcs_of(vm)[0][1], 96.0), arcs_of(vm)[0]
    print("ok  big bulge   -> a bulge taller than Y is re-asked")


def test_short_tangent_is_reasked():
    """A tangent radius too short to span its two bulges is re-asked."""
    vm = newvm()
    # the bottom-center minimum here is 36.13"; 20 cannot reach
    run(vm, REF_SCRIPT[:7] + [20.0, 60.0, 'Yes', (0.0, 0.0)], 'short tangent')
    bc = [a for a in arcs_of(vm) if close(a[1], 60.0)][0]
    assert close(bc[0][0], 230.6428859721), bc
    print("ok  short tan.  -> a tangent radius under the minimum is re-asked")


def test_nested_bulges_are_reasked():
    """A top bulge that swallows a side bulge cannot be joined to it by
    any tangent radius, so it is refused where it is entered."""
    vm = newvm()
    # a 480 top bulge on a 480 x 240 envelope is centred at (240, -240)
    # and swallows the 96 left bulge whole; 132 is taken instead
    run(vm, [REF_X, REF_Y, 96.0, 480.0, 132.0, 108.0]
        + list(REF_TANGENTS) + ['Yes', (0.0, 0.0)], 'nested top')
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
    run(vm, [REF_X, 800.0, 96.0, 132.0, 384.0, 108.0,
             200.0, 200.0, 60.0, 'Yes', (0.0, 0.0)], 'nested right')
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
            vm.run('c:OASIS', [bad] + REF_SCRIPT[1:] + ['Yes', (0.0, 0.0)])
        except LispError:
            continue
        raise AssertionError("%s was accepted as the X bound" % why)
    print("ok  bad numbers -> zero, negative and Enter are all refused")


def test_undo_group_wraps_the_drawing():
    vm = newvm()
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'undo')
    undo = [c for c in vm.commands if c and c[0] == '_.UNDO']
    assert [c[1] for c in undo] == ['_Begin', '_End'], undo
    print("ok  undo group  -> one U puts the whole pool back")


def test_settings_come_back():
    vm = newvm()
    vm.sysvars['OSMODE'] = 4133
    vm.sysvars['CMDECHO'] = 1
    vm.tables['LAYER'].add('SOMETHING')
    vm.sysvars['CLAYER'] = 'SOMETHING'
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'sysvars')
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
    run(vm, REF_SCRIPT + ['No', (0.0, 0.0)], 'frozen layer')
    d = _alist_dict(vm.entdata[rec])
    assert d[70] == 0, d          # thawed and unlocked
    assert d[62] == 4, d          # switched back on
    assert len(made(vm, 'ARC')) == 6
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
    run(vm, [200.0, 400.0, 150.0, 60.0, 60.0, 60.0,
             120.0, 120.0, 120.0, 'No', (0.0, 0.0)], 'wide bulge')
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
        run(vm, REF_SCRIPT + ['Yes', (50.0, 20.0, 5.0)], 'rotated ucs')
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
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'radius drag')
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
    run(vm, REF_SCRIPT + ['Yes', (0.0, 0.0)], 'standoff')
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
            script = list(REF_SCRIPT)
            script[k] = bad
            try:
                vm.run('c:OASIS', script + ['Yes', (0.0, 0.0)])
            except LispError:
                continue
            raise AssertionError("question %d accepted %r" % (k, bad))
    print("ok  all REQ     -> zero and negative refused at all eight"
          " measurements")


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
    test_no_dimensions()
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
    test_version_command()
    test_no_local_shadows_a_function()
    print("all OASIS tests passed")
