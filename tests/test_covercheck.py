"""Drive the REAL covercheck.lsp end-to-end in the AutoLISP VM.

The fixture is a cover sheet built by entmake: an L-shaped pool
outline on layer POOL (300 sq ft, one inside corner), a Cover Details
block whose Overlap/Spacing disagree with what that pool needs, a
Tech Title block dated today, dimensions and text.

Covers:
  * COVERSCAN     - read-only: the report SUGGESTs the right Overlap
                    and Spacing, demands the dashed outline and the
                    'Pool Size Shown' note, suggests the missing 36"
                    pad on the inside corner (uncircled - the scan
                    draws nothing), and keeps the DIMCHECK-style
                    findings in the DIMENSION AUDIT column; nothing
                    in the drawing changes but the report;
  * LITECOVERSCAN - the same cover rules minus the dimension pass:
                    no DIMENSION AUDIT column, no per-dim findings;
  * COVERCHECK    - the guided review: Move on a stray point, the
                    [Yes/No/Back/Skip] navigation (Back), the live
                    replacement question, and the suggested pad spot
                    circled on the construction layer - while the
                    Cover Details block itself is never touched.

The VM has no vlax-curve-* surface, so this file shims the handful
covercheck leans on over the VM's own entity store - the same
BUILTINS-patching siblings like test_perp_points.py use.  The scans'
whole-drawing fallback filters on CTAB, which the VM cannot answer,
so every ssget here is scripted with an explicit selection.

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
CHK = os.path.join(HERE, '..', 'lisp', 'covercheck', 'covercheck.lsp')

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


def text(vm, s, pos):
    esc = s.replace('\\', '\\\\').replace('"', '\\"')
    vm.loads('(entmakex (list (cons 0 "TEXT") (cons 8 "0")'
             ' (list 10 %r %r 0.0) (cons 40 3.0) (cons 1 "%s")))'
             % (pos[0], pos[1], esc))
    return vm.entities[-1]


def block(vm, name, at, attrs=()):
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


def report_texts(vm, layer='COVERCHECK-REPORT'):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}
        if d.get(0) == 'MTEXT' and d.get(8) == layer:
            out.append(mtext_of(vm, e))
    return out


def problems(txt):
    return [c for c in txt.split('\\P') if c.startswith('{\\C1;')]


def freeze(vm):
    def fz(g):
        if isinstance(g, Dot):
            return ('D', g.a, fz(g.b))
        if isinstance(g, list):
            return ('L',) + tuple(fz(x) for x in g)
        return g
    return {e: tuple(fz(g) for g in vm.entdata[e]) for e in vm.entities}


def today(vm):
    return vm.loads('(cchk:mdy-str (cchk:today-mdy))')


# The L-shaped pool: 300 sq ft, mostly straights, one inside corner at
# (120,120) -> the cover SHOULD be Overlap 12", Spacing 5x5, and one
# 36" pad belongs on the corner.
POOL_PTS = [(0.0, 0.0), (240.0, 0.0), (240.0, 120.0),
            (120.0, 120.0), (120.0, 240.0), (0.0, 240.0)]


def build_fixture(vm, with_text=True):
    ents = {}
    ents['pool'] = poly(vm, POOL_PTS, 'POOL')
    # Overlap/Spacing seeded WRONG for this pool: 15" / 3x3
    ents['details'] = block(vm, 'Cover Details', (400.0, 50.0),
                            [('OVERLAP', "15''"), ('SPACING', '3x3')])
    ents['title'] = block(vm, 'Tech Title', (400.0, 150.0),
                          [('Date', today(vm))])
    ents['dok'] = dim(vm, (0.0, 0.0), (240.0, 0.0), (120.0, -30.0))
    # the stray point, AND parked on the wrong layer for the CDIM check
    ents['dbad'] = dim(vm, (0.0, 0.0), (230.0, 6.0), (115.0, 30.0),
                       layer='0')
    if with_text:
        ents['t_bad'] = text(vm, "Depth 5'", (300.0, -40.0))
        ents['t_ok'] = text(vm, 'Cover 12\'-0"', (300.0, -60.0))
    return ents


def build_vm(with_text=True):
    vm = VM()
    vm.load(CHK)
    return vm, build_fixture(vm, with_text)


# ------------------------------------------------------------------
print("== COVERSCAN: read-only, suggests what the pool really needs ==")
vm, ents = build_vm()
before = freeze(vm)
pre = list(vm.entities)
vm.run('c:COVERSCAN', [None, selectable(vm)])   # no pickfirst, then highlight

reports = report_texts(vm)
assert len(reports) == 2, [r[:60] for r in reports]   # main + audit column
txt = '\n'.join(reports)
assert 'COVERSCAN REPORT' in txt, txt[:200]
assert 'DIMENSION AUDIT' in txt

# the pool is measured and the Cover Details block graded against it
assert ('Pool: 300.0 sq ft - outline 6 straight / 0 arc segment(s),'
        ' mostly straights') in txt, txt
assert 'Cover Details: Overlap 15" - SUGGEST 12" (under 1200 sq ft)' in txt
assert 'Cover Details: Spacing 3x3 - SUGGEST 5x5 (under 1200 sq ft)' in txt
assert ("Cover Details: overlap set but NO DASHED polyline on layer 'POOL'"
        " - draw the cover outline dashed") in txt, txt
assert '- NO DASHED outline; Spacing 3x3 - SUGGEST 5x5' in txt, txt
assert "'Pool Size Shown' note is nowhere in the selection - SUGGEST" \
    " adding it" in txt, txt
assert ("Replacement: no 'Replacement Disclaimer' in the selection - run"
        " COVERCHECK to confirm") in txt, txt
print("   Overlap 15/3x3 graded against the 300 sq ft pool: SUGGEST 12/5x5")

# the pad hunt: the inside corner has no pad, and a scan may only SAY so
assert 'Pads: 1 of 1 36" spot(s) have no pad - SUGGEST adding' in txt, txt
assert '(circled)' not in txt, txt              # circling is COVERCHECK's
assert 'Pad SUGGESTED at (120.0000, 120.0000) (inside corner)' in txt, txt
assert not [e for e in vm.entities if e not in pre
            and grp(vm, e, 0) == 'CIRCLE'], "the scan circled a pad spot"
print("   the missing corner pad is suggested, and nothing was drawn")

# the sheet-level checks that ride along
assert "Tech Title date: Date = '%s' - OK" % today(vm) in txt, txt
assert ('Dimension layer: 1 of 2 NOT on layer DIMENSION (0) - run CDIM'
        ' to move them') in txt, txt
assert ('Text %s: "Depth 5\'" gives feet with NO INCHES'
        % ents['t_bad'].handle) in txt, txt
assert 'Text %s:' % ents['t_ok'].handle not in txt   # good notation passes
assert 'Dimensions scanned: 2 (1 with a stray definition point)' in txt
assert ('Dim %s [STANDARD] = 230.0000: NOT attached - point 2 off by'
        ' 6.0000' % ents['dbad'].handle) in txt, txt
assert 'Dim %s [STANDARD] = 240.0000: OK' % ents['dok'].handle in txt
bad = '\n'.join(problems(reports[0]))
assert 'SUGGEST' in bad and 'run CDIM' in bad and 'NO INCHES' in bad, bad
print("   date, dimension layer, units and the stray point all named")

# read-only: nothing pre-existing changed, only the two report sheets new
after = freeze(vm)
assert all(after[e] == before[e] for e in pre), \
    [e for e in pre if after[e] != before[e]]
assert not vm.deleted
assert attrib_value(vm, ents['details'], 'OVERLAP') == "15''"
new = [e for e in vm.entities if e not in pre]
assert [grp(vm, e, 0) for e in new] == ['MTEXT', 'MTEXT'], \
    [grp(vm, e, 0) for e in new]
print("   read-only: the block still reads 15'', only the report is new")


# ------------------------------------------------------------------
print("== LITECOVERSCAN: cover rules without the dimension pass ==")
vm, ents = build_vm()
vm.run('c:LITECOVERSCAN', [None, selectable(vm)])
reports = report_texts(vm)
assert len(reports) == 1, [r[:60] for r in reports]   # main sheet only
txt = reports[0]
assert 'LITECOVERSCAN REPORT' in txt, txt[:200]
assert 'DIMENSION AUDIT' not in txt
assert 'Dimensions scanned' not in txt
assert 'NOT attached' not in txt and 'OVERLAP of' not in txt
assert 'Lite: dimensions, arcs and overlaps were not audited' in txt
# the cover rules still run in full
assert 'Cover Details: Overlap 15" - SUGGEST 12" (under 1200 sq ft)' in txt
assert 'Pad SUGGESTED at (120.0000, 120.0000) (inside corner)' in txt
assert "Tech Title date: Date = '%s' - OK" % today(vm) in txt
assert 'Dimension layer: 1 of 2 NOT on layer DIMENSION (0)' in txt
print("   no DIMENSION AUDIT column; every cover rule still speaks")


# ------------------------------------------------------------------
print("== COVERCHECK: guided review - Move, Back, replacement, circle ==")
vm, ents = build_vm(with_text=False)
sel = selectable(vm)

# review order is dbad (top row), then dok
vm.run('c:COVERCHECK', [
    None,           # no pickfirst selection
    sel,            # highlight the drawing
    'Move', 'Yes',  # dbad: take the suggested point, correct
    'Back',         # dok: mis-press - go back one
    'Yes',          # dbad again (its point is attached now)
    'Yes',          # dok: correct
    'No',           # no Replacement Disclaimer selected - not a replacement
])

# the navigation prompt offers exactly the clickable bracket
navs = [p for p, _a in vm.prompts if 'Is this dimension correct?' in str(p)]
assert navs and all('[Yes/No/Back/Skip] <Yes>:' in p for p in navs), navs

# the Move landed the stray point back on the pool outline
assert grp(vm, ents['dbad'], 14)[:2] == [230.0, 0.0], \
    grp(vm, ents['dbad'], 14)
assert color_of(vm, ents['dbad']) not in (1, 4, 6, 8)
# the pad spot IS circled by the live review, on the construction layer
circles = [e for e in vm.entities if e not in vm.deleted
           and grp(vm, e, 0) == 'CIRCLE']
assert len(circles) == 1, circles
assert grp(vm, circles[0], 8) == 'COVERCHECK-CONSTRUCTION'
assert grp(vm, circles[0], 10)[:2] == [120.0, 120.0]
assert grp(vm, circles[0], 40) == 18.0
# ...while the Cover Details block is still only advised, never edited
assert attrib_value(vm, ents['details'], 'OVERLAP') == "15''"
assert attrib_value(vm, ents['details'], 'SPACING') == '3x3'
print("   point moved, pad spot circled, Cover Details left untouched")

reports = report_texts(vm)
assert len(reports) == 2, [r[:80] for r in reports]
txt = '\n'.join(reports)
assert 'COVERCHECK REPORT' in txt, txt[:200]
assert ('Pads: 1 of 1 36" spot(s) have no pad - SUGGEST adding'
        ' (circled)') in txt, txt
assert 'Cover Details: Overlap 15" - SUGGEST 12" (under 1200 sq ft)' in txt
assert ("Replacement: not a replacement - 'Replacement Disclaimer' not"
        " needed") in txt, txt
assert ('Dimensions checked: 2 (correct: 2, flagged to fix: 0,'
        ' points adjusted: 1)') in txt, txt
# the move survives the Back that re-asked the question
assert 'point(s) moved before you stepped back' in txt, txt
assert 'Dim %s [STANDARD] = 230.0000: OK' % ents['dbad'].handle in txt, txt
assert 'Dim %s [STANDARD] = 240.0000: OK' % ents['dok'].handle in txt, txt
print("   report: SUGGEST lines, the circled pad and the reviewed dims")


# ------------------------------------------------------------------
print("== pickfirst: a selection made before COVERSCAN is used as-is ==")
vm, ents = build_vm()
vm.run('c:COVERSCAN', [selectable(vm)])     # only the "_I" probe answered
assert vm.prompts[0][0] == 'ssget _I', vm.prompts[0]
assert not any(p[0] == 'ssget' for p in vm.prompts), vm.prompts
assert len(report_texts(vm)) == 2
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
      (if (member et *cchk-curve-types*) (setq t:cands (cons e t:cands))))
    (setq t:dims  (reverse t:dims)
          t:cands (reverse t:cands)
          t:anchors (cchk:shared-anchors t:dims)))
  (defun t:anchored ()
    (t:parts)
    (list (length t:anchors)
          (cchk:audit-dim-point (car t:dims) 14 "dimension point 2"
                             t:cands t:anchors)))
  (defun t:stray ()
    (t:parts)
    (cchk:audit-dim-point (caddr t:dims) 14 "dimension point 2"
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


print("\nALL COVERCHECK SCENARIOS PASSED")
