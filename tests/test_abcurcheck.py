"""Runtime tests: load the real ABCURCHECK.lsp into the AutoLISP VM and
measure drawings with it.  AutoLISP cannot run outside AutoCAD, so this
is where a wrong arity, an unbound function or a nil reaching (distance
...) has to die -- and where the continuity maths is pinned down.

The shapes are chosen so the answer is known in closed form:

  * a CIRCLE is two tangent semicircles - the smoothest thing there is;
  * a capsule (two lines, two semicircles) is tangent at all four
    joints, so "Smooth" has to survive a shape with straight walls in
    it;
  * a circle split into two arcs whose second bulge is tan((90-t)/2)
    kinks by exactly T degrees at BOTH joints, which lets the band
    edges be tested to the degree;
  * every one of them turns exactly 360 degrees, kinks included, which
    is the identity the noise metrics are built on.

Run: python3 tests/test_abcurcheck.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_abcurcheck.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot, Sym, BUILTINS, NIL  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'abcurcheck', 'ABCURCHECK.lsp')


# ---- builtins the shared VM does not carry yet ------------------------
# entmakex that registers a LAYER record, and tblobjname to read it back:
# between them they are what the canonical ensure-layer needs to thaw a
# layer that is already there.

def _alist_dict(alist):
    d = {}
    for p in alist:
        if isinstance(p, Dot):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


_base_entmakex = BUILTINS[Sym('entmakex')]


def _entmakex(vm, a):
    d = _alist_dict(a[0])
    if d.get(0) in ('LAYER', 'LTYPE'):
        vm.tables[d[0]].add(d[2])
        rec = Ent()
        vm.entdata[rec] = list(a[0])
        vm.layer_records[d[2].upper()] = rec
        return rec
    return _base_entmakex(vm, a)


def _tblobjname(vm, a):
    return vm.layer_records.get(a[1].upper(), NIL)


BUILTINS[Sym('entmakex')] = _entmakex
BUILTINS[Sym('tblobjname')] = _tblobjname


# ---- the drawing ------------------------------------------------------

def newvm():
    vm = VM()
    vm.layer_records = {}
    vm.load(LSP)
    vm.sysvars['CLAYER'] = '0'
    return vm


def circle(vm, c, r, layer='POOL'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'CIRCLE'), Dot(8, layer),
                     [10, float(c[0]), float(c[1]), 0.0], Dot(40, float(r))]
    return e


def line(vm, a, b, layer='POOL'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'LINE'), Dot(8, layer),
                     [10, float(a[0]), float(a[1]), 0.0],
                     [11, float(b[0]), float(b[1]), 0.0]]
    return e


def lwpoly(vm, verts, closed=True, layer='POOL'):
    """VERTS is a list of (x, y) or (x, y, bulge), in order."""
    data = [Dot(0, 'LWPOLYLINE'), Dot(8, layer),
            Dot(90, len(verts)), Dot(70, 1 if closed else 0)]
    for v in verts:
        data.append([10, float(v[0]), float(v[1])])
        data.append(Dot(42, float(v[2]) if len(v) > 2 else 0.0))
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = data
    return e


def bind(vm, ents):
    """Hand the entities to the VM under _e0.._eN, so a LISP expression
    can name them."""
    for i, e in enumerate(ents):
        vm.set(Sym(f'_e{i}'), e)
    return [f'_e{i}' for i in range(len(ents))]


def measure(vm, ents, declared=(), chain=None):
    """Measure the loop those entities make, and leave the result in
    _res so acc:val can be asked for any single number."""
    segs = ' '.join(f'(acc:ent-segs {n})' for n in bind(vm, ents))
    if chain is None:
        chain = len(ents) > 1
    expr = f'(append {segs})' if len(ents) > 1 else segs
    if chain:
        expr = f'(acc:chain {expr})'
    decl = ' '.join(f'({d[0]} {d[1]})' for d in declared)
    vm.loads(f"(setq _res (acc:measure {expr} '({decl})))")
    return vm


def val(vm, key):
    return vm.loads(f'(acc:val "{key}" _res)')


def grade(vm):
    return vm.loads('(car (acc:grade _res))')


def reason(vm):
    return vm.loads('(cadr (acc:grade _res))')


def index(vm):
    return vm.loads('(car (acc:index _res))')


def deg(r):
    return math.degrees(r)


def near(a, b, eps=1e-6):
    return abs(a - b) < eps


def live(vm, etype, layer=None):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = _alist_dict(vm.entdata[e])
        if d.get(0) != etype:
            continue
        if layer is not None and str(d.get(8, '')).upper() != layer.upper():
            continue
        out.append((e, d))
    return out


def run(vm, cmd, script, label):
    # ABCURCHECK and its SCAN go through acc:select, which probes
    # pickfirst first: the leading None answers it (no pre-selection),
    # so the command asks for the perimeter as every scenario expects
    if cmd in ('c:ABCURCHECK', 'c:ABCURCHECKSCAN'):
        script = [None] + list(script)
    try:
        vm.run(cmd, list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


# ---- the smooth end ---------------------------------------------------

def test_circle_is_smooth():
    """A CIRCLE arrives as two tangent semicircles: nothing to fault."""
    vm = newvm()
    measure(vm, [circle(vm, (0, 0), 50.0)])
    assert val(vm, 'n') == 2
    assert near(val(vm, 'perim'), 2 * math.pi * 50.0, 1e-6)
    assert val(vm, 'gaps') is NIL
    assert val(vm, 'tangent-n') == 2
    assert val(vm, 'soft-n') == 0 and val(vm, 'kink-n') == 0
    assert near(deg(val(vm, 'turn-signed')), 360.0, 1e-6)
    assert near(val(vm, 'excess'), 0.0, 1e-9)
    assert val(vm, 'inflect') == 0
    assert grade(vm) == 'Smooth', reason(vm)
    assert index(vm) == 100
    print("ok  a circle grades Smooth, turns 360 deg, excess 0, index 100")


def test_capsule_with_straight_walls_is_smooth():
    """Two straight walls and two end curves, tangent at all four
    joints - a real pool shape, and it must not be penalised for having
    lines in it."""
    vm = newvm()
    measure(vm, [lwpoly(vm, [(0, 0, 0.0), (100, 0, 1.0),
                             (100, 50, 0.0), (0, 50, 1.0)])])
    assert val(vm, 'n') == 4
    assert val(vm, 'tangent-n') == 4, val(vm, 'soft-n')
    assert near(val(vm, 'perim'), 200.0 + 50.0 * math.pi, 1e-6)
    assert near(deg(val(vm, 'turn-signed')), 360.0, 1e-6)
    assert near(val(vm, 'excess'), 0.0, 1e-9)
    assert grade(vm) == 'Smooth', reason(vm)
    print("ok  a capsule of two walls and two end curves grades Smooth")


# ---- the kink bands ---------------------------------------------------

def split_circle(vm, turn_deg, r=50.0):
    """A circle cut into two arcs whose second bulge is off by just
    enough to kink TURN_DEG at each of the two joints."""
    b2 = math.tan(math.radians((90.0 - turn_deg) / 2.0))
    return lwpoly(vm, [(r, 0, 1.0), (-r, 0, b2)])


def test_kink_angle_is_exact():
    """The fixture's whole point: 20 degrees asked for, 20 measured, at
    both joints, with the loop still turning exactly 360."""
    vm = newvm()
    measure(vm, [split_circle(vm, 20.0)])
    angs = sorted(deg(abs(vm.loads(f'(acc:j-ang (nth {i} '
                                   '(acc:val "joints" _res)))')))
                  for i in range(2))
    assert all(near(a, 20.0, 1e-6) for a in angs), angs
    assert near(deg(val(vm, 'turn-signed')), 360.0, 1e-6)
    print("ok  a 20 deg kink measures 20.0 deg at both joints,"
          " and the loop still turns 360")


def test_bands():
    """Each band edge lands on the right side of ABHD's own numbers."""
    for turn, band, want in ((0.2, 'tangent-n', 'Smooth'),
                             (4.0, 'soft-n', 'Fair'),
                             (20.0, 'kink-n', 'Rough'),
                             (60.0, 'corner-n', 'Rough')):
        vm = newvm()
        measure(vm, [split_circle(vm, turn)])
        assert val(vm, band) == 2, (turn, band, val(vm, band))
        assert grade(vm) == want, (turn, grade(vm), reason(vm))
    print("ok  0.2/4/20/60 deg land in tangent/soft/kink/corner"
          " -> Smooth/Fair/Rough/Rough")


def test_kink_costs_the_index():
    """A worse kink scores lower - the index is only worth having if it
    moves in the right direction."""
    scores = []
    for turn in (0.2, 4.0, 20.0, 60.0):
        vm = newvm()
        measure(vm, [split_circle(vm, turn)])
        scores.append(index(vm))
    assert scores == sorted(scores, reverse=True), scores
    assert scores[0] == 100 and scores[-1] < scores[0], scores
    print(f"ok  the index falls as the kink grows: {scores}")


# ---- declarations -----------------------------------------------------

def test_declaring_a_corner_clears_the_grade():
    """A declared break leaves the score and is counted separately."""
    vm = newvm()
    ent = split_circle(vm, 60.0)
    measure(vm, [ent])
    assert grade(vm) == 'Rough' and val(vm, 'corner-n') == 2
    # both joints sit on the x axis at +/-50, which is where the picks go
    measure(vm, [ent], declared=[(50.0, 0.0), (-50.0, 0.0)])
    assert val(vm, 'decl-n') == 2
    assert val(vm, 'corner-n') == 0
    assert grade(vm) == 'Smooth', reason(vm)
    assert index(vm) == 100
    print("ok  declaring both corners takes them out of the grade"
          " (Rough -> Smooth)")


def test_declaration_must_be_near_a_joint():
    """A pick well away from any joint claims nothing, and is reported
    back the other way round."""
    vm = newvm()
    measure(vm, [split_circle(vm, 60.0)], declared=[(0.0, 200.0)])
    assert val(vm, 'decl-n') == 0
    assert val(vm, 'corner-n') == 2
    orph = val(vm, 'orphans')
    assert isinstance(orph, list) and len(orph) == 1, orph
    print("ok  a pick that lands on no joint is reported as an orphan,"
          " not silently honoured")


# ---- G0: the Broken end ----------------------------------------------

def test_gap_between_exploded_lines():
    """Four lines that nearly make a square: the loop is walked anyway
    and the gap is the finding."""
    vm = newvm()
    ents = [line(vm, (0, 0), (100, 0)),
            line(vm, (100, 0), (100, 100)),
            line(vm, (100, 100), (0, 100)),
            line(vm, (0, 100.5), (0, 0))]       # 0.5 short of the corner
    measure(vm, ents)
    assert val(vm, 'n') == 4
    gaps = val(vm, 'gaps')
    assert isinstance(gaps, list) and len(gaps) == 1, gaps
    assert near(vm.loads('(acc:j-gap (car (acc:val "gaps" _res)))'), 0.5, 1e-9)
    assert grade(vm) == 'Broken'
    assert 'gap' in reason(vm), reason(vm)
    assert index(vm) < 100 - 40 + 1
    print("ok  a 0.5 unit gap in exploded geometry grades Broken and"
          " the gap is measured, not bailed on")


def test_open_polyline_shows_as_a_gap():
    """An unclosed polyline is a gap at the seam, not a silent pass."""
    vm = newvm()
    measure(vm, [lwpoly(vm, [(0, 0), (100, 0), (100, 100), (0, 100)],
                        closed=False)])
    assert val(vm, 'n') == 3
    assert len(val(vm, 'gaps')) == 1
    assert grade(vm) == 'Broken', reason(vm)
    print("ok  an open polyline reports the seam as a gap")


def test_crossing_chords():
    """A bowtie: every joint tangent-clean by its own reckoning, and the
    shape still nonsense."""
    vm = newvm()
    measure(vm, [lwpoly(vm, [(0, 0), (100, 0), (0, 100), (100, 100)])])
    assert len(val(vm, 'crosses')) >= 1, val(vm, 'crosses')
    assert grade(vm) == 'Broken', reason(vm)
    print("ok  a bowtie is caught as a crossing")


def test_doubled_segment():
    vm = newvm()
    ents = [line(vm, (0, 0), (100, 0)),
            line(vm, (100, 0), (100, 100)),
            line(vm, (100, 100), (0, 0)),
            line(vm, (0, 0), (100, 0))]         # drawn twice
    measure(vm, ents)
    assert len(val(vm, 'dupes')) == 1, val(vm, 'dupes')
    assert grade(vm) == 'Broken', reason(vm)
    print("ok  a segment drawn twice is caught")


def test_offenders_are_ranked():
    """The list is headed "worst first", so it had better be: a gap
    outranks every kink, and kinks come down in size."""
    vm = newvm()
    ents = [line(vm, (0, 0), (200, 0)),
            line(vm, (200, 0), (100, 60)),      # 149 deg turn
            line(vm, (100, 60), (10, 8)),       # gentler
            line(vm, (0, 2), (0, 0))]           # and a gap at the corner
    measure(vm, ents)
    got = vm.loads('(mapcar (quote acc:severity) (acc:offenders _res))')
    assert got == sorted(got, reverse=True), got
    assert got[0] > 1000.0, got               # the gap leads
    print(f"ok  offenders come out worst first, gap ahead of kinks: "
          f"{[round(g, 1) for g in got]}")


# ---- noise ------------------------------------------------------------

def test_micro_segments():
    """A square whose top edge was traced in 1 inch steps: tangent
    everywhere along that edge, and still the wrong drawing."""
    vm = newvm()
    verts = [(0, 0), (100, 0), (100, 100)]
    verts += [(100 - i, 100) for i in range(1, 101)]
    ent = lwpoly(vm, verts)
    # the four real corners are meant to be there
    measure(vm, [ent], declared=[(0.0, 0.0), (100.0, 0.0),
                                 (100.0, 100.0), (0.0, 100.0)])
    assert val(vm, 'micro-n') == 100, val(vm, 'micro-n')
    assert near(val(vm, 'micro-share'), 100.0 / 400.0, 1e-9)
    assert val(vm, 'kink-n') == 0 and val(vm, 'corner-n') == 0
    assert grade(vm) == 'Rough', reason(vm)
    assert 'micro-segments' in reason(vm), reason(vm)
    print("ok  100 one-inch steps grade Rough on the micro-segment share"
          " alone, with every joint tangent")


def test_inflections_counted():
    """An S of two opposite arcs closed by two more: curvature changes
    sign, and the count says so."""
    vm = newvm()
    measure(vm, [lwpoly(vm, [(0, 0, 0.5), (100, 0, -0.5),
                             (200, 0, 0.5), (100, -60, -0.5)])])
    assert val(vm, 'inflect') == 4, val(vm, 'inflect')
    print("ok  curvature sign changes are counted as inflections")


def test_turning_excess_grows_with_wander():
    """A convex loop has no excess; one that doubles back has some."""
    vm = newvm()
    measure(vm, [circle(vm, (0, 0), 50.0)])
    assert near(val(vm, 'excess'), 0.0, 1e-9)
    vm = newvm()
    measure(vm, [lwpoly(vm, [(0, 0, 0.5), (100, 0, -0.5),
                             (200, 0, 0.5), (100, -60, -0.5)])])
    assert val(vm, 'excess') > 0.0, val(vm, 'excess')
    print("ok  turning excess is 0 for a convex loop and positive for"
          " one that reverses")


# ---- the commands -----------------------------------------------------

def test_pickfirst_selection_is_honored():
    """A perimeter selected before the command answers acc:select's
    probe: only "ssget _I" fires, the Select prompt never asks."""
    vm = newvm()
    ent = split_circle(vm, 20.0)
    try:
        vm.run('c:ABCURCHECKSCAN', [[ent]])   # only the probe answered
    except LispError as e:
        raise AssertionError(f"[pickfirst] {e}") from None
    assert vm.prompts[0][0] == 'ssget _I', vm.prompts[0]
    assert not any(p[0] == 'ssget' for p in vm.prompts), vm.prompts


def test_command_marks_and_combs():
    """The whole flow: select, keep the declarations, report, ring the
    findings, draw the comb."""
    vm = newvm()
    ent = split_circle(vm, 20.0)
    run(vm, 'c:ABCURCHECK', [[ent], 'Keep', 'Yes'], 'full run')
    rings = live(vm, 'CIRCLE', 'POOL-CONT')
    assert len(rings) == 2, rings           # one per undeclared kink
    assert all(d.get(62) == 1 for _, d in rings), rings   # red, the bad band
    assert len(live(vm, 'TEXT', 'POOL-CONT')) == 2
    assert len(live(vm, 'LINE', 'POOL-COMB')) > 0
    assert len(live(vm, 'LWPOLYLINE', 'POOL-COMB')) == 1
    assert vm.sysvars['CLAYER'] == '0'
    print("ok  ABCURCHECK rings both kinks red on POOL-CONT and draws"
          " the comb envelope on POOL-COMB")


def test_command_declares_and_remembers():
    """Picks made in one run come back in the next, off the drawing."""
    vm = newvm()
    ent = split_circle(vm, 60.0)
    run(vm, 'c:ABCURCHECK',
        [[ent], 'Add', (50.0, 0.0), (-50.0, 0.0), None, 'Keep', 'No'],
        'declare')
    decl = [d for _, d in live(vm, 'CIRCLE', 'POOL-CONT')
            if d.get(6) == 'DASHED']
    assert len(decl) == 2, decl
    assert live(vm, 'TEXT', 'POOL-CONT') == []   # nothing left undeclared
    # a second run is told nothing and still knows
    run(vm, 'c:ABCURCHECK', [[ent], 'Keep', 'No'], 'remember')
    assert vm.loads('(length (acc:read-declared))') == 2
    assert live(vm, 'TEXT', 'POOL-CONT') == []
    print("ok  declarations are stamped onto the drawing and a second"
          " run reads them back")


def test_back_reopens_the_declarations():
    """Back at the comb question re-opens the declaration loop, and the
    answer given there lands - the report is measured again, not
    reused."""
    vm = newvm()
    ent = split_circle(vm, 60.0)
    run(vm, 'c:ABCURCHECK',
        [[ent], 'Keep', 'Back',
         'Add', (50.0, 0.0), (-50.0, 0.0), None, 'Keep', 'No'],
        'back')
    assert live(vm, 'TEXT', 'POOL-CONT') == []       # nothing left to flag
    assert vm.loads('(length (acc:read-declared))') == 2
    print("ok  Back at the comb question re-opens the declarations and"
          " the run is measured again")


def test_scan_draws_nothing():
    vm = newvm()
    ent = split_circle(vm, 20.0)
    run(vm, 'c:ABCURCHECKSCAN', [[ent]], 'scan')
    assert live(vm, 'CIRCLE', 'POOL-CONT') == []
    assert live(vm, 'LINE', 'POOL-COMB') == []
    print("ok  ABCURCHECKSCAN reports without touching the drawing")


def test_rescue_keeps_declarations():
    """The marks go, the answers stay - re-picking them is the one
    thing a rescue must never cost."""
    vm = newvm()
    ent = split_circle(vm, 20.0)
    run(vm, 'c:ABCURCHECK',
        [[ent], 'Add', (50.0, 0.0), None, 'Keep', 'Yes'], 'mark')
    assert len(live(vm, 'TEXT', 'POOL-CONT')) == 1
    run(vm, 'c:ABCURCHECKRESCUE', ['Marks'], 'rescue')
    assert live(vm, 'TEXT', 'POOL-CONT') == []
    assert live(vm, 'LINE', 'POOL-COMB') == []
    assert len([d for _, d in live(vm, 'CIRCLE', 'POOL-CONT')
                if d.get(6) == 'DASHED']) == 1
    run(vm, 'c:ABCURCHECKRESCUE', ['All'], 'rescue all')
    assert live(vm, 'CIRCLE', 'POOL-CONT') == []
    print("ok  RESCUE Marks clears the findings and the comb but keeps"
          " the declarations; All clears those too")


def test_one_segment_is_refused():
    vm = newvm()
    run(vm, 'c:ABCURCHECK', [[line(vm, (0, 0), (100, 0))]], 'one segment')
    assert live(vm, 'CIRCLE', 'POOL-CONT') == []
    print("ok  a single segment is refused, not measured")


def test_nothing_selected():
    vm = newvm()
    run(vm, 'c:ABCURCHECK', [None], 'empty')
    print("ok  an empty selection is reported, not crashed on")


# ---- the file itself --------------------------------------------------

def test_bands_match_abhd():
    """ABCURCHECK borrows ABHD's thresholds so the two commands agree on
    what smooth means; if ABHD moves, this fails and says so."""
    import re
    src = open(os.path.join(os.path.dirname(__file__), '..',
                            'lisp', 'abhd', 'abhd.lsp')).read()
    tang = re.search(r'\*PF-TANG-TOL\*\s+\(/\s*pi\s+([\d.]+)\)', src)
    corn = re.search(r'\*PF-CORNER-ANG\*\s+\(/\s*pi\s+([\d.]+)\)', src)
    assert tang and corn, "ABHD's tangent/corner constants moved"
    assert near(180.0 / float(tang.group(1)), 8.0, 1e-9), tang.group(1)
    assert near(180.0 / float(corn.group(1)), 45.0, 1e-9), corn.group(1)
    vm = newvm()
    assert near(vm.loads('acc:*kink-tol*'), 8.0)
    assert near(vm.loads('acc:*corner-ang*'), 45.0)
    print("ok  the kink and corner thresholds are still ABHD's 8 and 45 deg")


TESTS = [v for k, v in sorted(globals().items()) if k.startswith('test_')]

if __name__ == '__main__':
    for t in TESTS:
        t()
    print(f"\n{len(TESTS)} ABCURCHECK test(s) passed.")
