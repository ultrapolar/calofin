"""Drive the REAL linfincheck.lsp end-to-end in the AutoLISP VM.

The fixture is a liner-finish sheet built by entmake: a staircase side
view (treads + risers at right angles, total rise 36), a Tech Title
block carrying WallHt and Date attributes, a 'Liner Material with
Step' pattern block, a title-block border, dimensions and lines.

Covers:
  * LINFINSCAN     - read-only: the report leads with the liner
                     checks (steps/side view, wall height MISMATCH,
                     the liner pattern's NEEDS WIPING, the SCALED
                     DOWN border) and keeps the DIMCHECK-style
                     findings in the DIMENSION AUDIT column; nothing
                     in the drawing changes but the report;
  * LITELINFINSCAN - the same rules minus the dimension pass: no
                     DIMENSION AUDIT column, no per-dim findings;
  * LINFINCHECK    - the guided review: Move on a stray point, the
                     [Yes/No/Back/Skip] navigation (Back and Skip),
                     the Step Attachment confirmation flagging the
                     block red, and the liner pattern field WIPED
                     clean.

The VM has no vlax-curve-* surface, so this file shims the handful
linfincheck leans on over the VM's own entity store - the same
BUILTINS-patching siblings like test_perp_points.py use.

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
CHK = os.path.join(HERE, '..', 'lisp', 'linfincheck', 'linfincheck.lsp')

TWO_PI = 2.0 * math.pi


# ------------------------------------------------------------------
# BUILTINS shims: the vlax-curve surface the attachment audit uses.
# ------------------------------------------------------------------

def grp(vm, e, code):
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
            return _arc_geo(vm, e)[3]
        return _length(vm, e)

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


install_curve_shims()


# ------------------------------------------------------------------
# fixture builders and readers
# ------------------------------------------------------------------

def line(vm, p1, p2, layer='0'):
    vm.loads('(entmakex (list (cons 0 "LINE") (cons 8 "%s")'
             ' (list 10 %r %r 0.0) (list 11 %r %r 0.0)))'
             % (layer, p1[0], p1[1], p2[0], p2[1]))
    return vm.entities[-1]


def dim(vm, p13, p14, p10, layer='DIMENSION', style='STANDARD'):
    vm.loads('(entmake (list (cons 0 "DIMENSION") (cons 8 "%s")'
             ' (cons 3 "%s") (cons 70 0) (cons 50 0.0)'
             ' (list 13 %r %r 0.0) (list 14 %r %r 0.0)'
             ' (list 10 %r %r 0.0)))'
             % (layer, style, p13[0], p13[1], p14[0], p14[1],
                p10[0], p10[1]))
    return vm.entities[-1]


def poly(vm, pts, layer, closed=True):
    vs = ' '.join('(list 10 %r %r)' % (x, y) for x, y in pts)
    vm.loads('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
             ' (cons 8 "%s") (cons 100 "AcDbPolyline") (cons 90 %d)'
             ' (cons 70 %d) %s))'
             % (layer, len(pts), 1 if closed else 0, vs))
    return vm.entities[-1]


def block(vm, name, at, attrs=()):
    """An INSERT, with its ATTRIB entities and SEQEND trailing it in
    the database exactly as AutoCAD stores an attributed insert."""
    vm.loads('(entmakex (list (cons 0 "INSERT") (cons 8 "0") (cons 2 "%s")'
             ' (list 10 %r %r 0.0)%s))'
             % (name, at[0], at[1], ' (cons 66 1)' if attrs else ''))
    ins = vm.entities[-1]
    for tag, val in attrs:
        esc = val.replace('\\', '\\\\').replace('"', '\\"')
        vm.loads('(entmake (list (cons 0 "ATTRIB") (cons 8 "0")'
                 ' (cons 2 "%s") (cons 1 "%s")))' % (tag, esc))
    if attrs:
        vm.loads('(entmake (list (cons 0 "SEQEND") (cons 8 "0")))')
    return ins


def attrib_value(vm, ins, tag):
    """The value the named ATTRIB after an INSERT carries right now."""
    i = vm.entities.index(ins) + 1
    while i < len(vm.entities):
        e = vm.entities[i]
        if grp(vm, e, 0) != 'ATTRIB':
            break
        if (grp(vm, e, 2) or '').upper() == tag.upper():
            return grp(vm, e, 1)
        i += 1
    return None


def color_of(vm, e):
    c = grp(vm, e, 62)
    return 256 if c is None else c


def selectable(vm):
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


def report_texts(vm, layer='LINFINCHECK-REPORT'):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}
        if d.get(0) == 'MTEXT' and d.get(8) == layer:
            out.append(mtext_of(vm, e))
    return out


def problems(txt):
    """Report lines rendered in the flag colour (red)."""
    return [c for c in txt.split('\\P') if c.startswith('{\\C1;')]


def freeze(vm):
    def fz(g):
        if isinstance(g, Dot):
            return ('D', g.a, fz(g.b))
        if isinstance(g, list):
            return ('L',) + tuple(fz(x) for x in g)
        return g
    return {e: tuple(fz(g) for g in vm.entdata[e]) for e in vm.entities}


def staircase(vm):
    """A side view: three treads and three risers zig-zagging up at
    right angles, total rise 36 (y 100 -> 136)."""
    for p1, p2 in [((100, 100), (112, 100)), ((112, 112), (124, 112)),
                   ((124, 124), (136, 124)),                 # treads
                   ((112, 100), (112, 112)), ((124, 112), (124, 124)),
                   ((136, 124), (136, 136))]:                # risers
        line(vm, (float(p1[0]), float(p1[1])), (float(p2[0]), float(p2[1])))


def today(vm):
    return vm.loads('(lfc:mdy-str (lfc:today-mdy))')


def build_scan_vm():
    """The seeded sheet the scans read: side view rise 36 vs WallHt
    40'' (MISMATCH), no Step Attachment block (MISSING), a liner
    pattern field reading 'Not Selected' (NEEDS WIPING), a border at
    0.6x nominal (SCALED DOWN), a stray dimension point and an
    overlapping line pair (the DIMCHECK-style audit)."""
    vm = VM()
    vm.load(CHK)
    ents = {}
    staircase(vm)
    ents['border'] = poly(vm, [(0.0, 0.0), (422.4, 0.0),
                               (422.4, 326.175), (0.0, 326.175)], 'border')
    ents['l1'] = line(vm, (0.0, -25.0), (120.0, -25.0))
    ents['dok'] = dim(vm, (0.0, -25.0), (120.0, -25.0), (60.0, -5.0))
    ents['dbad'] = dim(vm, (0.0, -25.0), (110.0, -18.0), (55.0, -45.0))
    ents['c1'] = line(vm, (0.0, -160.0), (100.0, -160.0))
    ents['c2'] = line(vm, (60.0, -160.0), (180.0, -160.0))
    ents['title'] = block(vm, 'Tech Title', (300.0, 50.0),
                          [('WallHt', "Finished Wall Ht = 40''"),
                           ('Date', today(vm))])
    ents['liner'] = block(vm, 'Liner Material with Step', (300.0, 150.0),
                          [('PATTERN', 'Not Selected'),
                           ('WALL', 'Bluestone')])
    return vm, ents


# ------------------------------------------------------------------
print("== LINFINSCAN: liner checks lead, dimension audit alongside ==")
vm, ents = build_scan_vm()
before = freeze(vm)
pre = list(vm.entities)
vm.run('c:LINFINSCAN', [None, None])        # no pickfirst; Enter = whole drawing

reports = report_texts(vm)
assert len(reports) == 2, [r[:60] for r in reports]   # main + audit column
txt = '\n'.join(reports)
assert 'LINFINSCAN REPORT' in txt, txt[:200]
assert 'DIMENSION AUDIT' in txt

# the liner-finish verdicts
assert ('Steps: side view detected, rise 36.0000; Step Attachment block'
        ' MISSING - add one') in txt, txt
assert ("Wall height: steps rise 36.0000 but WallHt is 'Finished Wall Ht"
        " = 40''' (40.0000) - MISMATCH") in txt, txt
hl = ents['liner'].handle
assert ('Liner Material (Liner Material with Step) %s: PATTERN carries NOT'
        ' - NEEDS WIPING (run LINFINCHECK)' % hl) in txt, txt
assert 'Liner Material: 1 block(s) found; word NOT found - review' in txt
assert ('is only 0.600x the nominal 704.0000 x 543.6250 - Title block'
        ' should not be SCALED DOWN for Liners') in txt, txt
assert "Date: Date = '%s' - OK" % today(vm) in txt, txt
assert 'Dimension layer: all 2 on DIMENSION' in txt, txt
print("   steps, wall height, liner, border and date all speak up")

# ...and every one of the seeded liner faults renders red
bad = '\n'.join(problems(reports[0]))
assert 'MISSING' in bad and 'MISMATCH' in bad, bad
assert 'NEEDS WIPING' in bad and 'SCALED DOWN' in bad, bad
assert 'Date:' not in bad, bad                  # today's date is no problem
print("   the four seeded liner faults are the red lines")

# the DIMCHECK-style findings sit in the audit column
assert 'Dimensions scanned: 2 (1 with a stray definition point)' in txt
assert ('Dim %s [STANDARD] = 110.0000: NOT attached - point 2 off by'
        ' 7.0000' % ents['dbad'].handle) in txt, txt
assert 'Dim %s [STANDARD] = 120.0000: OK' % ents['dok'].handle in txt
olaps = ('Lines %s+%s: OVERLAP of 40.0000 - flagged'
         % (ents['c1'].handle, ents['c2'].handle),
         'Lines %s+%s: OVERLAP of 40.0000 - flagged'
         % (ents['c2'].handle, ents['c1'].handle))
assert olaps[0] in txt or olaps[1] in txt, txt
assert 'DIMENSION AUDIT' in reports[1] and 'Steps:' not in reports[1]
print("   stray point and overlap named in the DIMENSION AUDIT column")

# read-only: the liner field is REPORTED as needing wiping, not wiped,
# and nothing else changed either
assert attrib_value(vm, ents['liner'], 'PATTERN') == 'Not Selected'
after = freeze(vm)
assert all(after[e] == before[e] for e in pre), \
    [e for e in pre if after[e] != before[e]]
assert not vm.deleted
new = [e for e in vm.entities if e not in pre]
assert [grp(vm, e, 0) for e in new] == ['MTEXT', 'MTEXT'], \
    [grp(vm, e, 0) for e in new]
print("   read-only: the bad pattern field survives, only the report is new")


# ------------------------------------------------------------------
print("== LITELINFINSCAN: liner rules without the dimension pass ==")
vm, ents = build_scan_vm()
vm.run('c:LITELINFINSCAN', [None, None])
reports = report_texts(vm)
assert len(reports) == 1, [r[:60] for r in reports]   # main sheet only
txt = reports[0]
assert 'LITELINFINSCAN REPORT' in txt, txt[:200]
assert 'DIMENSION AUDIT' not in txt
assert 'Dimensions scanned' not in txt
assert 'NOT attached' not in txt and 'OVERLAP of' not in txt
assert 'Lite: dimensions, arcs and overlaps were not audited' in txt
print("   no DIMENSION AUDIT column, no per-dimension findings")

# the liner rules that need no geometry pass still run in full...
assert 'NEEDS WIPING' in txt, txt
assert 'SCALED DOWN' in txt, txt
assert "Date: Date = '%s' - OK" % today(vm) in txt, txt
assert 'Dimension layer: all 2 on DIMENSION' in txt, txt
# ...and so does the STEP / side-view hunt, which is a LINER rule, not
# a DIMCHECK one: the lite scan used to nil the segment list it shares
# with the dimension pass, which took the step rule out with the
# overlaps and lost the wall-height comparison against the rise.
assert 'Steps: no step patterns detected' not in txt, txt
assert 'MISMATCH' in txt, txt
print("   liner block, border, date AND the steps rule still audited")


# ------------------------------------------------------------------
print("== LINFINCHECK: guided review - Move, Back, Skip, wipe, flag ==")
vm = VM()
vm.load(CHK)
ents = {}
staircase(vm)
ents['border'] = poly(vm, [(0.0, 0.0), (704.0, 0.0),
                           (704.0, 543.625), (0.0, 543.625)], 'border')
ents['l1'] = line(vm, (0.0, -25.0), (120.0, -25.0))
ents['l2'] = line(vm, (0.0, -75.0), (120.0, -75.0))
ents['l3'] = line(vm, (0.0, -125.0), (120.0, -125.0))
ents['d1'] = dim(vm, (0.0, -25.0), (110.0, -17.0), (55.0, -5.0))   # 8 off l1
ents['d2'] = dim(vm, (0.0, -75.0), (120.0, -75.0), (60.0, -55.0))
ents['d3'] = dim(vm, (0.0, -125.0), (120.0, -125.0), (60.0, -105.0))
ents['satt'] = block(vm, 'Step Attachment', (500.0, 300.0))
ents['title'] = block(vm, 'Tech Title', (600.0, 50.0),
                      [('WallHt', "Finished Wall Ht = 36''"),
                       ('Date', today(vm))])
ents['liner'] = block(vm, 'Liner Material with Step', (500.0, 200.0),
                      [('PATTERN', 'Not Supplied'),
                       ('WALL', 'Bluestone')])
sel = selectable(vm)

# review order is d1 (top row), d2, d3
vm.run('c:LINFINCHECK', [
    None,           # no pickfirst selection
    sel,            # highlight the drawing
    'Move', 'Yes',  # d1: move the stray point onto l1, correct
    'Back',         # d2: mis-press - go back one
    'Yes',          # d1 again (point now attached, no re-ask)
    'Yes',          # d2: correct
    'Skip',         # d3: skip the rest of the dimensions
    'No',           # Step Attachment: the correct one is NOT placed
])

# the navigation prompt offers exactly the clickable bracket
navs = [p for p, _a in vm.prompts if 'Is this dimension correct?' in str(p)]
assert navs and all('[Yes/No/Back/Skip] <Yes>:' in p for p in navs), navs

# the Move landed the point on the measured line
assert grp(vm, ents['d1'], 14)[:2] == [110.0, -25.0], \
    grp(vm, ents['d1'], 14)
# Skip left d3 unreviewed and unmarked
assert color_of(vm, ents['d3']) not in (1, 4, 6, 8)
# the Step Attachment block was flagged red by the No answer
assert color_of(vm, ents['satt']) == 1, color_of(vm, ents['satt'])
# the liner's bad pattern field was WIPED back to blank
assert attrib_value(vm, ents['liner'], 'PATTERN') == ''
assert attrib_value(vm, ents['liner'], 'WALL') == 'Bluestone'
print("   point moved, block flagged red, bad liner field wiped clean")

# one construction line through d1's ORIGINAL points
xlines = [e for e in vm.entities if e not in vm.deleted
          and grp(vm, e, 0) == 'XLINE']
assert len(xlines) == 1, xlines
assert grp(vm, xlines[0], 8) == 'LINFINCHECK-CONSTRUCTION'
assert grp(vm, xlines[0], 10)[:2] == [0.0, -25.0]
print("   construction line through the moved dim's old points")

reports = report_texts(vm)
assert len(reports) == 2, [r[:80] for r in reports]
txt = '\n'.join(reports)
assert 'LINFINCHECK REPORT' in txt, txt[:200]
assert 'Steps: staircase side view detected (2 step pattern(s))' in txt
assert ('Step Attachment %s: WRONG ONE - flagged to fix (red)'
        % ents['satt'].handle) in txt, txt
assert ('Steps: steps present; side view detected; Step Attachment'
        ' flagged WRONG (red)') in txt, txt
assert ("Wall height: steps rise 36.0000 = WallHt 'Finished Wall Ht ="
        " 36''' - MATCHES") in txt, txt
assert ('Liner Material (Liner Material with Step) %s at (500.0000,'
        ' 200.0000): PATTERN carried NOT - WIPED clean'
        % ents['liner'].handle) in txt, txt
assert '1 pattern field(s) WIPED clean' in txt, txt
assert 'Title block border: 704.0000 x 543.6250 - nominal size, OK' in txt
assert 'Dimensions: 1 left UNREVIEWED (skipped by user)' in txt, txt
assert ('Dimensions checked: 3 (correct: 2, flagged to fix: 0,'
        ' points adjusted: 1)') in txt, txt
# the move survives the Back that re-asked the question
assert 'point(s) moved before you stepped back' in txt, txt
assert 'Dim %s [STANDARD] = 110.0000: OK' % ents['d1'].handle in txt, txt
assert 'Dim %s [STANDARD] = 120.0000: OK' % ents['d2'].handle in txt, txt
print("   report: side view found, MATCHES, WIPED, WRONG ONE, Skip noted")


# ------------------------------------------------------------------
print("== pickfirst: a selection made before LINFINSCAN is used as-is ==")
vm, ents = build_scan_vm()
vm.run('c:LINFINSCAN', [selectable(vm)])    # only the "_I" probe answered
assert vm.prompts[0][0] == 'ssget _I', vm.prompts[0]
assert not any(p[0] == 'ssget' for p in vm.prompts), vm.prompts
assert len(report_texts(vm)) >= 1
print("   the probe took it; the Highlight prompt was never asked")


# ------------------------------------------------------------------
print("== shared anchors: a point two dims meet at is not a stray ==")
# The hypotenuse corner: two runs stopping short of the corner they
# would meet at, and TWO dimensions measuring to that corner - a point
# in space with no geometry through it.  The audit must leave it alone
# WITHOUT asking, and still question a point only one dim measures to.
vm = VM()
vm.load(CHK)
line(vm, (0.0, 0.0), (60.0, 0.0))              # bottom run
line(vm, (100.0, 40.0), (100.0, 100.0))        # right-hand run
dim(vm, (0.0, 0.0), (100.0, 0.0), (50.0, -20.0))       # to the corner
dim(vm, (100.0, 100.0), (100.0, 0.0), (130.0, 50.0))   # and again
dim(vm, (10.0, 0.0), (40.0, 15.0), (20.0, 30.0))       # a real stray

vm.loads('''
  (defun t:parts ( / ss i e et)
    (setq ss (ssget "_X") i 0 t:dims nil t:cands nil)
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            et (cdr (assoc 0 (entget e))))
      (if (= et "DIMENSION") (setq t:dims (cons e t:dims)))
      (if (member et *lfc-curve-types*) (setq t:cands (cons e t:cands))))
    (setq t:dims  (reverse t:dims)
          t:cands (reverse t:cands)
          t:anchors (lfc:shared-anchors t:dims)))
  (defun t:anchored ()
    (t:parts)
    (list (length t:anchors)
          (lfc:audit-dim-point (car t:dims) 14 "dimension point 2"
                             t:cands t:anchors)))
  (defun t:stray ()
    (t:parts)
    (lfc:audit-dim-point (caddr t:dims) 14 "dimension point 2"
                       t:cands t:anchors))
''')

res = vm.run('t:anchored', [])           # an empty script: any question raises
assert res[0] == 1, res                  # one shared spot, the corner
assert str(res[1][2]).lower() == 'anchor', res
assert not [p for p in vm.prompts if 'Move/Keep/Pick' in str(p[0])], vm.prompts
print("   the corner is held as an anchor, with nothing asked")

try:
    vm.run('t:stray', [])                # this one MUST ask, so it runs dry
    raise AssertionError("the lone stray point was not questioned")
except LispError as e:
    assert 'SCRIPT EXHAUSTED' in str(e), e
print("   a point only one dim measures to is still questioned")


print("\nALL LINFINCHECK SCENARIOS PASSED")
