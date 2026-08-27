"""Drive the REAL dimcheck.lsp end-to-end in the AutoLISP VM.

Covers, against a drawing built by entmake with faults planted in it:
  * DIMSCAN     - the read-only scan: the report names the stray
                  dimension point, the unattached arc ends and the
                  overlapping line pair, and NOTHING in the drawing
                  changes but the report;
  * DIMCHECK    - the guided review: Move and Keep on stray points,
                  the [Yes/No/Back/Skip] navigation (Back re-asks the
                  previous dimension, No flags it red, Skip leaves the
                  rest unreviewed), arc endpoint Move/Keep, and the
                  overlap Merge;
  * DIMCHECKRESCUE - puts back every stashed colour and removes the
                  report and construction markers;
  * DIMCHECKVER.

The VM has no vlax-curve-* surface, so this file shims the handful
dimcheck leans on (closest point, curve ends, point at distance) over
the VM's own entity store - the same BUILTINS-patching siblings like
test_perp_points.py use.  The VM's ssget also cannot evaluate an xdata
(-3 ("APP")) filter, so rescue's sweep is answered by a small wrapper.

Script values: entity lists answer ssget, strings answer keyword
prompts, None is Enter.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Dot, Sym, BUILTINS, NIL  # noqa: E402

HERE = os.path.dirname(__file__)
# lispvm's _remap_root sends this to shared/parts/ when
# CALOFIN_LISP_ROOT=shared, exactly as test_spacheck.py's paths work
CHK = os.path.join(HERE, '..', 'lisp', 'dimcheck', 'dimcheck.lsp')

TWO_PI = 2.0 * math.pi


# ------------------------------------------------------------------
# BUILTINS shims: the vlax-curve surface dimcheck audits with.
# Geometry is read straight off the VM's DXF store.  Entities the
# real functions would reject (SPLINEs, closed curves asked for their
# ends) raise LispError, so the vl-catch-all-apply wrappers in the
# tool behave exactly as they do in AutoCAD.
# ------------------------------------------------------------------

def grp(vm, e, code):
    """First DXF group value on an entity, None when absent."""
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else g[1:]
    return None


def _pts10(vm, e):
    out = []
    for g in vm.entdata.get(e, []):
        if isinstance(g, list) and g and g[0] == 10:
            out.append([float(g[1]), float(g[2])])
        elif isinstance(g, Dot) and g.a == 10:
            out.append([float(g.b[0]), float(g.b[1])])
    return out


def _arc_geo(vm, e):
    c = grp(vm, e, 10)
    r = float(grp(vm, e, 40))
    a0 = float(grp(vm, e, 50) or 0.0)
    a1 = float(grp(vm, e, 51) or 0.0)
    sweep = (a1 - a0) % TWO_PI
    if sweep <= 1e-12:
        sweep = TWO_PI
    return (float(c[0]), float(c[1])), r, a0, sweep


def _arc_pt(c, r, a):
    return [c[0] + r * math.cos(a), c[1] + r * math.sin(a), 0.0]


def _seg_closest(p, a, b):
    ax, ay, bx, by = float(a[0]), float(a[1]), float(b[0]), float(b[1])
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 < 1e-24:
        return [ax, ay, 0.0]
    t = ((p[0] - ax) * dx + (p[1] - ay) * dy) / l2
    t = max(0.0, min(1.0, t))
    return [ax + t * dx, ay + t * dy, 0.0]


def _poly_edges(vm, e):
    vs = _pts10(vm, e)
    flags = grp(vm, e, 70) or 0
    edges = list(zip(vs, vs[1:]))
    if int(flags) & 1 and len(vs) > 2:
        edges.append((vs[-1], vs[0]))
    return edges


def _closest_on(vm, e, p):
    t = grp(vm, e, 0)
    if t == 'LINE':
        return _seg_closest(p, grp(vm, e, 10), grp(vm, e, 11))
    if t == 'ARC':
        c, r, a0, sw = _arc_geo(vm, e)
        dx, dy = p[0] - c[0], p[1] - c[1]
        if dx * dx + dy * dy < 1e-24:
            return _arc_pt(c, r, a0)
        ang = math.atan2(dy, dx)
        if (ang - a0) % TWO_PI <= sw:
            return _arc_pt(c, r, ang)
        p1, p2 = _arc_pt(c, r, a0), _arc_pt(c, r, a0 + sw)
        return p1 if math.dist(p[:2], p1[:2]) <= math.dist(p[:2], p2[:2]) \
            else p2
    if t == 'CIRCLE':
        c, r = grp(vm, e, 10), float(grp(vm, e, 40))
        dx, dy = p[0] - c[0], p[1] - c[1]
        ln = math.hypot(dx, dy)
        if ln < 1e-12:
            return [c[0] + r, c[1], 0.0]
        return [c[0] + dx / ln * r, c[1] + dy / ln * r, 0.0]
    if t == 'LWPOLYLINE':
        # straight edges only - the fixtures draw bulge-free polylines
        best = None
        for a, b in _poly_edges(vm, e):
            q = _seg_closest(p, a, b)
            if best is None or math.dist(p[:2], q[:2]) < \
                    math.dist(p[:2], best[:2]):
                best = q
        if best is None:
            raise LispError('vlax-curve: empty polyline', vm)
        return best
    raise LispError(f'vlax-curve: no curve for {t}', vm)


def _curve_ent(vm, a):
    e = a[0]
    if not isinstance(e, lispvm.Ent) or e in vm.deleted:
        raise LispError('vlax-curve: not an entity', vm)
    return e


def _ends(vm, e):
    t = grp(vm, e, 0)
    if t == 'LINE':
        p1, p2 = grp(vm, e, 10), grp(vm, e, 11)
        return ([float(p1[0]), float(p1[1]), 0.0],
                [float(p2[0]), float(p2[1]), 0.0])
    if t == 'ARC':
        c, r, a0, sw = _arc_geo(vm, e)
        return _arc_pt(c, r, a0), _arc_pt(c, r, a0 + sw)
    if t == 'LWPOLYLINE' and not (int(grp(vm, e, 70) or 0) & 1):
        vs = _pts10(vm, e)
        return ([vs[0][0], vs[0][1], 0.0], [vs[-1][0], vs[-1][1], 0.0])
    raise LispError(f'vlax-curve: no ends on {t}', vm)


def _length(vm, e):
    t = grp(vm, e, 0)
    if t == 'LINE':
        p1, p2 = grp(vm, e, 10), grp(vm, e, 11)
        return math.dist(p1[:2], p2[:2])
    if t == 'ARC':
        _c, r, _a0, sw = _arc_geo(vm, e)
        return r * sw
    if t == 'LWPOLYLINE':
        return sum(math.dist(a, b) for a, b in _poly_edges(vm, e))
    raise LispError(f'vlax-curve: no length on {t}', vm)


def install_curve_shims():
    B = BUILTINS

    B[Sym('vlax-curve-getclosestpointto')] = \
        lambda vm, a: _closest_on(vm, _curve_ent(vm, a), a[1])
    B[Sym('vlax-curve-getstartpoint')] = \
        lambda vm, a: _ends(vm, _curve_ent(vm, a))[0]
    B[Sym('vlax-curve-getendpoint')] = \
        lambda vm, a: _ends(vm, _curve_ent(vm, a))[1]

    def end_param(vm, a):
        e = _curve_ent(vm, a)
        if grp(vm, e, 0) == 'ARC':
            return _arc_geo(vm, e)[3]          # param = swept angle
        return _length(vm, e)                  # param = distance

    def dist_at_param(vm, a):
        e = _curve_ent(vm, a)
        if grp(vm, e, 0) == 'ARC':
            return _arc_geo(vm, e)[1] * float(a[1])
        return float(a[1])

    def point_at_dist(vm, a):
        e, d = _curve_ent(vm, a), float(a[1])
        t = grp(vm, e, 0)
        if t == 'ARC':
            c, r, a0, _sw = _arc_geo(vm, e)
            return _arc_pt(c, r, a0 + d / r)
        if t == 'LINE':
            p1, p2 = grp(vm, e, 10), grp(vm, e, 11)
            ln = math.dist(p1[:2], p2[:2])
            t01 = 0.0 if ln < 1e-12 else max(0.0, min(1.0, d / ln))
            return [p1[0] + (p2[0] - p1[0]) * t01,
                    p1[1] + (p2[1] - p1[1]) * t01, 0.0]
        raise LispError(f'vlax-curve: pointAtDist on {t}', vm)

    B[Sym('vlax-curve-getendparam')] = end_param
    B[Sym('vlax-curve-getdistatparam')] = dist_at_param
    B[Sym('vlax-curve-getpointatdist')] = point_at_dist


# The VM's ssget cannot evaluate an xdata filter, so a "_X" sweep for
# (-3 ("DIMCHECK")) - how clear-old and DIMCHECKRESCUE find their
# marks - is answered here from each entity's stored -3 group.
def install_ssget_xdata():
    base = BUILTINS[Sym('ssget')]

    def apps_of(vm, e):
        out = set()
        for g in vm.entdata.get(e, []):
            if isinstance(g, list) and g and g[0] == -3:
                for sub in g[1:]:
                    if isinstance(sub, list) and sub and \
                            isinstance(sub[0], str):
                        out.add(sub[0].upper())
        return out

    def ssget(vm, a):
        pairs = lispvm._filt_pairs(a) or []
        apps = [w for c, w in pairs if c == -3]
        mode = ' '.join(x for x in a if isinstance(x, str))
        if apps and mode.upper().lstrip('_') in ('X', 'A'):
            want = apps[0][0].upper() if isinstance(apps[0], list) and \
                apps[0] else ''
            rest = [(c, w) for c, w in pairs if c != -3]
            ents = [e for e in vm.entities
                    if e not in vm.deleted and want in apps_of(vm, e)
                    and (not rest or lispvm._filt_hit(vm, e, rest))]
            return ['<ss>'] + ents if ents else NIL
        return base(vm, a)

    BUILTINS[Sym('ssget')] = ssget


install_curve_shims()
install_ssget_xdata()


# ------------------------------------------------------------------
# fixture builders and readers
# ------------------------------------------------------------------

def line(vm, p1, p2, layer='0'):
    vm.loads('(entmakex (list (cons 0 "LINE") (cons 8 "%s")'
             ' (list 10 %r %r 0.0) (list 11 %r %r 0.0)))'
             % (layer, p1[0], p1[1], p2[0], p2[1]))
    return vm.entities[-1]


def dim(vm, p13, p14, p10, layer='0', style='STANDARD'):
    """A rotated/linear DIMENSION straight into the database, the way
    the VM's own _.DIMLINEAR would leave one (70=0, angle 0)."""
    vm.loads('(entmake (list (cons 0 "DIMENSION") (cons 8 "%s")'
             ' (cons 3 "%s") (cons 70 0) (cons 50 0.0)'
             ' (list 13 %r %r 0.0) (list 14 %r %r 0.0)'
             ' (list 10 %r %r 0.0)))'
             % (layer, style, p13[0], p13[1], p14[0], p14[1],
                p10[0], p10[1]))
    return vm.entities[-1]


def arc(vm, c, r, a0, a1, layer='0'):
    vm.loads('(entmake (list (cons 0 "ARC") (cons 8 "%s")'
             ' (list 10 %r %r 0.0) (cons 40 %r) (cons 50 %r)'
             ' (cons 51 %r)))' % (layer, c[0], c[1], r, a0, a1))
    return vm.entities[-1]


def color_of(vm, e):
    c = grp(vm, e, 62)
    return 256 if c is None else c


def layer_of(vm, e):
    return grp(vm, e, 8)


def handle(e):
    return e.handle


def selectable(vm):
    """What a window selection would return - ATTRIB/SEQEND are
    subentities and never land in a selection set."""
    return [e for e in vm.entities
            if e not in vm.deleted
            and grp(vm, e, 0) not in ('ATTRIB', 'SEQEND')]


def mtext_of(vm, e):
    head, tail = [], ''
    for p in vm.entdata[e]:
        if isinstance(p, Dot):
            if p.a == 3:
                head.append(p.b)
            elif p.a == 1 and not tail:
                tail = p.b
    return ''.join(head) + tail


def report_texts(vm, layer='DIMCHECK-REPORT'):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}
        if d.get(0) == 'MTEXT' and d.get(8) == layer:
            out.append(mtext_of(vm, e))
    return out


def freeze(vm):
    """An immutable snapshot of every entity's data, for the
    read-only assertions."""
    def fz(g):
        if isinstance(g, Dot):
            return ('D', g.a, fz(g.b))
        if isinstance(g, list):
            return ('L',) + tuple(fz(x) for x in g)
        return g
    return {e: tuple(fz(g) for g in vm.entdata[e]) for e in vm.entities}


def build_vm():
    vm = VM()
    vm.load(CHK)
    return vm


def seed_faults(vm):
    """The reviewed drawing: two lines to measure, a clean dimension,
    a dimension with a stray point, an arc attached to nothing, and a
    pair of overlapping lines.  Returns the named entities."""
    a = line(vm, (0.0, 0.0), (100.0, 0.0))          # bottom line
    b = line(vm, (0.0, 80.0), (100.0, 80.0))        # top line
    d1 = dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0))   # pt2 10 off B
    d2 = dim(vm, (0.0, 0.0), (100.0, 0.0), (50.0, 30.0))      # clean, on A
    d3 = dim(vm, (0.0, 0.0), (90.0, -10.0), (50.0, -30.0))    # pt2 10 off A
    f = arc(vm, (102.0, 25.0), 25.0, -math.pi / 2.0, math.pi / 2.0)
    c1 = line(vm, (0.0, -60.0), (100.0, -60.0))     # overlap 60..100
    c2 = line(vm, (60.0, -60.0), (180.0, -60.0))
    return dict(a=a, b=b, d1=d1, d2=d2, d3=d3, arc=f, c1=c1, c2=c2)


# ------------------------------------------------------------------
print("== DIMSCAN: read-only, names every planted fault ==")
vm = build_vm()
ents = seed_faults(vm)
before = freeze(vm)
pre = list(vm.entities)
vm.run('c:DIMSCAN', [None])                 # Enter = whole drawing

reports = report_texts(vm)
assert len(reports) == 1, [r[:60] for r in reports]
txt = reports[0]
assert 'DIMSCAN REPORT' in txt, txt[:120]
assert '[DIMCHECK v' in txt, txt[:120]
assert 'Read-only scan - nothing in the drawing was changed.' in txt

# the dashboard counts every fault category
assert 'Dimensions scanned: 3 (2 with a stray definition point)' in txt, txt
assert 'Arcs scanned: 1 (1 with an unattached end)' in txt, txt
assert 'Overlapping line pairs: 1' in txt, txt

# ...and the per-item lines name each offender by handle
h = {k: handle(e) for k, e in ents.items()}
assert ('Dim %s [STANDARD] = 100.0000: NOT attached - point 2 off by 10.0000'
        % h['d1']) in txt, txt
assert 'Dim %s [STANDARD] = 100.0000: OK' % h['d2'] in txt, txt
assert 'Dim %s [STANDARD] = 90.0000: NOT attached - point 2 off by 10.0000' \
    % h['d3'] in txt, txt
assert 'Arc %s: start & end NOT attached to an object end' % h['arc'] in txt
olap_ab = 'Lines %s+%s: OVERLAP of 40.0000 - flagged' % (h['c1'], h['c2'])
olap_ba = 'Lines %s+%s: OVERLAP of 40.0000 - flagged' % (h['c2'], h['c1'])
assert olap_ab in txt or olap_ba in txt, txt
print("   report names the stray point, the loose arc and the overlap")

# read-only: every pre-existing entity byte-identical, nothing deleted,
# and the only additions are the report MTEXT (the layer records the
# report layer needs live in the symbol table, not the drawing)
after = freeze(vm)
assert all(after[e] == before[e] for e in pre), \
    [e for e in pre if after[e] != before[e]]
assert not vm.deleted, vm.deleted
new = [e for e in vm.entities if e not in pre]
assert [grp(vm, e, 0) for e in new] == ['MTEXT'], \
    [(grp(vm, e, 0), layer_of(vm, e)) for e in new]
assert '--- DIMSCAN complete (read-only) ---' in ''.join(vm.printed)
print("   nothing in the drawing changed but the report")


# ------------------------------------------------------------------
print("== DIMCHECK: guided review with Move/Keep, Back, No and Merge ==")
vm = build_vm()
ents = seed_faults(vm)
h = {k: handle(e) for k, e in ents.items()}
sel = selectable(vm)

# review order is D1 (top row), D2, D3, then the arc, then the overlap
vm.run('c:DIMCHECK', [
    sel,            # highlight the drawing
    'Move', 'Yes',  # D1: take the suggested point, dimension correct
    'Back',         # D2: mis-press - go back one
    'Yes',          # D1 again (its point is attached now, no re-ask)
    'No',           # D2: flag it red
    'Keep', 'Yes',  # D3: keep the stray point exactly where drawn
    'Move',         # arc start: snap onto the nearest object end
    'Keep',         # arc end: put the arc back as drawn
    'Merge',        # the overlapping pair: merge into one line
])

# D1's stray point was MOVED onto line B
assert grp(vm, ents['d1'], 14)[:2] == [100.0, 80.0], \
    grp(vm, ents['d1'], 14)
# D3's stray point was KEPT exactly where it was drawn
assert grp(vm, ents['d3'], 14)[:2] == [90.0, -10.0], \
    grp(vm, ents['d3'], 14)
# the No answer left D2 wearing the red flag colour; Yes-dims restored
assert color_of(vm, ents['d2']) == 1, color_of(vm, ents['d2'])
assert color_of(vm, ents['d1']) not in (1, 4, 6, 8)
assert color_of(vm, ents['d3']) not in (1, 4, 6, 8)
print("   Move moved, Keep kept, No flagged red")

# the arc: start snapped to line A's end, end restored by Keep, magenta
sp, ep = _ends(vm, ents['arc'])
assert math.dist(sp[:2], [100.0, 0.0]) < 1e-6, sp
assert math.dist(ep[:2], [102.0, 50.0]) < 1e-6, ep
assert color_of(vm, ents['arc']) == 6, color_of(vm, ents['arc'])
print("   arc start moved (magenta), Keep restored its end exactly")

# the merge: one of the pair is gone, the survivor spans the union in cyan
gone = [e for e in (ents['c1'], ents['c2']) if e in vm.deleted]
kept = [e for e in (ents['c1'], ents['c2']) if e not in vm.deleted]
assert len(gone) == 1 and len(kept) == 1, (gone, kept)
span = sorted([grp(vm, kept[0], 10)[0], grp(vm, kept[0], 11)[0]])
assert span == [0.0, 180.0], span
assert grp(vm, kept[0], 10)[1] == -60.0
assert color_of(vm, kept[0]) == 4, color_of(vm, kept[0])
print("   overlap merged into one cyan line spanning both")

# a construction XLINE through D1's ORIGINAL points, on the check layer;
# D3 was kept, so it gets none
xlines = [e for e in vm.entities if e not in vm.deleted
          and grp(vm, e, 0) == 'XLINE']
assert len(xlines) == 1, xlines
assert layer_of(vm, xlines[0]) == 'DIMCHECK-CONSTRUCTION'
assert grp(vm, xlines[0], 10)[:2] == [0.0, 80.0], grp(vm, xlines[0], 10)
print("   one construction line, through the moved dim's old points")

# the report
reports = report_texts(vm)
assert len(reports) == 1, len(reports)
txt = reports[0]
assert 'DIMCHECK REPORT' in txt, txt[:120]
# NOTE (real quirk, pinned): Back rolls the points-adjusted TALLY back
# but not the move itself, so a moved point re-approved after a Back is
# reported as 0 adjusted even though the XLINE marker proves the move.
assert 'Dimensions checked: 3 (correct: 2, flagged to fix: 1,' \
       ' points adjusted: 0)' in txt, txt
assert 'Arcs checked: 1 (OK: 0, with endpoints moved: 1,' \
       ' endpoints moved in total: 1)' in txt, txt
assert 'Overlapping line pairs: 1 (merged: 1, flagged: 0,' \
       ' left as drawn: 0)' in txt, txt
assert 'Dim %s [STANDARD] = 100.0000: FLAGGED to fix (red)' % h['d2'] in txt
assert 'Dim %s [STANDARD] = 90.0000: OK - 1 point(s) kept where you' \
       ' drew them' % h['d3'] in txt, txt
assert ('Arc %s: 1 endpoint(s) moved (magenta), 1 kept where you drew them'
        % h['arc']) in txt, txt
assert 'merged into one line (cyan)' in txt, txt
assert '(overlap 40.0000)' in txt, txt
print("   report carries the tallies and every reviewed item")


# ------------------------------------------------------------------
print("== DIMCHECKRESCUE: full reset of marks, report and markers ==")
vm.run('c:DIMCHECKRESCUE', [])
assert report_texts(vm) == [], "rescue left the report behind"
assert not [e for e in vm.entities if e not in vm.deleted
            and grp(vm, e, 0) == 'XLINE'], "rescue left the marker line"
for k in ('d1', 'd2', 'd3', 'arc', 'a', 'b'):
    assert color_of(vm, ents[k]) == 256, (k, color_of(vm, ents[k]))
assert color_of(vm, kept[0]) == 256, color_of(vm, kept[0])
print("   every flag colour restored, report and marker removed")


# ------------------------------------------------------------------
print("== the version command ==")
vm = build_vm()
vm.run('c:DIMCHECKVER', [])
assert any('DIMCHECK v' in s for s in vm.printed), vm.printed[-3:]
print("   DIMCHECKVER prints the loaded build")


print("\nALL DIMCHECK SCENARIOS PASSED")
