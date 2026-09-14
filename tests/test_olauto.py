"""Runtime tests: load the real OLAUTO.lsp into the AutoLISP VM and
overlay perimeters with it.  AutoLISP cannot run outside AutoCAD, so
this is where a wrong arity, an unbound function or a local shadowing a
builtin has to die -- and where the fitting maths is pinned down.

The shapes are chosen so the right answer is known in closed form:

  * two CIRCLEs of the same radius have exactly one best overlay and
    zero error at it, whatever pose they start from;
  * a circle of radius R laid over one of radius R+D is D away from it
    at EVERY point once the centres agree - which is the test that the
    fit is rigid, because a fit allowed to scale would report zero and
    hide a pool measured long;
  * a rectangle carries its own corners, so a fit that recovers the
    rotation it was given can be checked to the degree;
  * a shape with two bumps of known size has two known peaks, which is
    what the separation rule has to find instead of dimensioning the
    bigger one twice.

Run: python3 tests/test_olauto.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_olauto.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot, Sym, BUILTINS, NIL  # noqa: E402

ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
HERE = os.path.join(os.path.dirname(__file__), '..')
LSP = (os.path.join(HERE, 'shared', 'parts', 'OLAUTO.lsp')
       if ROOT == 'shared' else
       os.path.join(HERE, 'lisp', 'olauto', 'OLAUTO.lsp'))
LIB = os.path.join(HERE, 'shared', 'parts', 'CALOFIN-LIB.lsp')

# ensure-layer is one of the helpers the mirror swaps onto the library
# (tools/mirror_shared.py), so it answers to a different name in each
# tier.  Everything else this file calls by name stays local to OLAUTO.
ENS = 'cal:ensure-layer' if ROOT == 'shared' else 'ola:ensure-layer'


def mklayer(vm, name, color=7):
    vm.loads(f'({ENS} "{name}" {color})')


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
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(LSP)
    vm.sysvars['CLAYER'] = '0'
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
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


def arc(vm, c, r, a0, a1, layer='POOL'):
    """A0/A1 in DEGREES here; entget hands AutoLISP radians."""
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'ARC'), Dot(8, layer),
                     [10, float(c[0]), float(c[1]), 0.0], Dot(40, float(r)),
                     Dot(50, math.radians(a0)), Dot(51, math.radians(a1))]
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


def pose(pts, deg=0.0, tx=0.0, ty=0.0):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [(c * p[0] - s * p[1] + tx, s * p[0] + c * p[1] + ty) + tuple(p[2:])
            for p in pts]


def rect(w, h):
    return [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)]


def bind(vm, ents):
    for i, e in enumerate(ents):
        vm.set(Sym(f'_e{i}'), e)
    return [f'_e{i}' for i in range(len(ents))]


def segs(vm, ents, var):
    """Read ENTS into VAR as one segment chain, the way ola:collect does."""
    names = bind(vm, ents)
    expr = ' '.join(f'(ola:ent-segs {n})' for n in names)
    if len(ents) > 1:
        expr = f'(ola:chain (append {expr}))'
    vm.loads(f'(setq {var} {expr})')
    return var


def fit(vm, mov='_mov', fix='_fix', out='_x'):
    vm.loads(f'(setq {out} (ola:fit {mov} {fix}))')
    vm.loads(f"(setq _moved (mapcar '(lambda (s) "
             f"(list (ola:xapply {out} (car s)) "
             f"(ola:xapply {out} (cadr s)) (caddr s))) {mov}))")
    return vm.loads(out)


def profile(vm, og='_fix', new='_moved'):
    vm.loads(f'(setq _prof (ola:profile {og} {new}))')
    return vm.loads("(mapcar 'car _prof)")


def stats(ds):
    return (max(ds), sum(ds) / len(ds),
            math.sqrt(sum(d * d for d in ds) / len(ds)))


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


def run(vm, script, label='OLAUTO'):
    try:
        vm.run('c:OLAUTO', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def near(a, b, eps=1e-6):
    return abs(a - b) < eps


# ---- the fit itself ---------------------------------------------------

def test_same_circle_lands_dead_on():
    """Two circles of one radius have one best overlay and no error at
    it -- from wherever the second one started."""
    vm = newvm()
    segs(vm, [circle(vm, (0, 0), 50.0)], '_fix')
    segs(vm, [circle(vm, (742.0, -318.0), 50.0)], '_mov')
    fit(vm)
    worst, mean, rms = stats(profile(vm))
    assert worst < 1e-6, f"worst {worst}"
    print("ok  two equal circles overlay with no error left")


def test_rotation_is_recovered_exactly():
    """A rectangle turned 37 degrees and moved off the sheet comes back
    to the one it was turned from."""
    vm = newvm()
    base = rect(120.0, 80.0)
    segs(vm, [lwpoly(vm, base)], '_fix')
    segs(vm, [lwpoly(vm, pose(base, 37.0, -900.0, 610.0))], '_mov')
    fit(vm)
    worst, mean, rms = stats(profile(vm))
    assert worst < 1e-6, f"worst {worst}"
    print("ok  a rectangle turned 37 deg and moved is recovered exactly")


def test_fit_is_rigid_not_scaled():
    """THE test that matters: a circle of radius 60 laid over one of 50
    sits 10 away all round.  A fit allowed to scale would report zero
    and a pool measured 20% long would ship."""
    vm = newvm()
    segs(vm, [circle(vm, (0, 0), 50.0)], '_fix')
    segs(vm, [circle(vm, (410.0, 260.0), 60.0)], '_mov')
    fit(vm)
    ds = profile(vm)
    worst, mean, rms = stats(ds)
    assert near(worst, 10.0, 1e-3), f"worst {worst}"
    assert near(min(ds), 10.0, 1e-3), f"least {min(ds)}"
    print("ok  a 60 over a 50 reads 10 all round - the fit never scales")


def test_start_pose_does_not_change_the_answer():
    """The phase search is here so that ICP cannot settle into a
    local fit.  Eight poses, one answer."""
    vm = newvm()
    shape = [(0.0, 0.0, 0.3), (200.0, 10.0, 0.2), (210.0, 140.0, 0.35),
             (30.0, 150.0, 0.25)]
    segs(vm, [lwpoly(vm, shape)], '_fix')
    seen = []
    for k in range(8):
        deg = 43.0 * k
        moved = [(p[0], p[1], p[2]) for p in pose(shape, deg, 500.0 * k,
                                                 -300.0 * k)]
        segs(vm, [lwpoly(vm, moved)], '_mov')
        fit(vm)
        seen.append(stats(profile(vm))[0])
    assert max(seen) < 1e-5, f"worst of the eight: {max(seen)}"
    print(f"ok  eight start poses give one answer (worst {max(seen):.2e})")


def test_reversed_winding_still_fits():
    """One outline drawn clockwise and the other counter-clockwise is
    the same pool; the phase search tries both directions.

    This one does NOT come out exact, and the reason is worth knowing.
    Reversed, the two chains start at different points of the same
    curve, so their arc-length sample grids are offset by a fraction of
    a sample -- and the polish matches against the CHORDS between
    samples, not the arcs.  What is left is of the order of that
    chord's sagitta.  It is a hundredth of a percent of the perimeter,
    and against the 20-to-40-unit error a fit with no direction search
    would report it is nothing; the test pins both facts."""
    vm = newvm()
    shape = [(0.0, 0.0, 0.2), (180.0, 0.0, 0.2), (180.0, 120.0, 0.2),
             (0.0, 120.0, 0.2)]
    segs(vm, [lwpoly(vm, shape)], '_fix')
    # reversing a bulged polyline means reversing the vertex order AND
    # moving each bulge back one place, negated
    bs = [-p[2] for p in shape]
    rev = [(shape[i][0], shape[i][1], bs[i - 1])
           for i in range(len(shape) - 1, -1, -1)]
    segs(vm, [lwpoly(vm, pose(rev, 25.0, 700.0, 400.0))], '_mov')
    fit(vm)
    worst = stats(profile(vm))[0]
    per = vm.loads('(ola:chain-len _fix)')
    assert worst < 0.001 * per, f"worst {worst} on a perimeter of {per}"
    # ...and the SAME shape wound the same way comes out exact, which is
    # what says the residue above is the sampling and not the fit
    segs(vm, [lwpoly(vm, pose(shape, 25.0, 700.0, 400.0))], '_mov')
    fit(vm)
    assert stats(profile(vm))[0] < 1e-5
    print(f"ok  a perimeter drawn the other way round fits to "
          f"{worst:.4f} of its {per:.0f} ({100 * worst / per:.3f}%)")


def test_exploded_perimeter_reads_the_same_as_one_polyline():
    """A shape handed over as loose lines and arcs is chained into the
    same ring the polyline would have given."""
    vm = newvm()
    segs(vm, [circle(vm, (0, 0), 50.0)], '_fix')
    # a capsule, exploded: two lines and two semicircular arcs, in a
    # deliberately jumbled order
    ents = [line(vm, (0, 60), (100, 60)),
            arc(vm, (100, 0), 60.0, -90.0, 90.0),
            line(vm, (100, -60), (0, -60)),
            arc(vm, (0, 0), 60.0, 90.0, 270.0)]
    segs(vm, ents, '_cap')
    assert vm.loads('(ola:closed-p _cap)') is not NIL
    got = vm.loads('(ola:chain-len _cap)')
    want = 2 * 100.0 + 2 * math.pi * 60.0
    assert near(got, want, 1e-6), f"{got} vs {want}"
    print("ok  four loose entities chain into a closed ring of the right length")


def test_open_perimeters_fit_too():
    """Not every bead track is a closed loop -- a run that stops at the
    steps is still a perimeter to overlay."""
    vm = newvm()
    shape = [(0.0, 0.0), (150.0, 20.0), (220.0, 130.0), (60.0, 180.0)]
    segs(vm, [lwpoly(vm, shape, closed=False)], '_fix')
    assert vm.loads('(ola:closed-p _fix)') is NIL
    segs(vm, [lwpoly(vm, pose(shape, 62.0, -400.0, 250.0), closed=False)],
         '_mov')
    fit(vm)
    worst = stats(profile(vm))[0]
    assert worst < 1e-5, f"worst {worst}"
    print("ok  two open perimeters fit end to end")


# ---- what gets dimensioned --------------------------------------------

BUMP_RUN = 9


def bumped(w, h, bumps):
    """A rectangle walked out as many short segments, with BUMPS pushing
    a RUN of samples out by a named amount.

    A run rather than a single vertex, deliberately: one displaced
    vertex is a spike, and the nearest point on a spike to the wall
    opposite is somewhere up its slanted side, so the error there is
    not the number the test put in.  A flat-topped plateau makes the
    distance across the middle of it exactly the displacement."""
    pts = []
    per = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)]
    n = 40
    for i in range(4):
        a, b = per[i], per[(i + 1) % 4]
        for k in range(n):
            f = k / float(n)
            pts.append([a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1])])
    for idx, (dx, dy) in bumps.items():
        for k in range(idx, idx + BUMP_RUN):
            pts[k % len(pts)][0] += dx
            pts[k % len(pts)][1] += dy
    return [tuple(p) for p in pts]


def test_peaks_are_spread_around_the_perimeter():
    """Two bumps on two different walls, one bigger than the other: the
    separation rule has to find both rather than dimensioning the
    bigger one twice.

    bumped() walks the rectangle anticlockwise from the origin, 40
    samples a side, so 0-39 is the bottom wall (outward is -y) and
    40-79 the right-hand one (outward is +x)."""
    vm = newvm()
    segs(vm, [lwpoly(vm, bumped(200.0, 200.0, {}))], '_fix')
    segs(vm, [lwpoly(vm, bumped(200.0, 200.0,
                                {20: (0.0, -6.0), 60: (4.0, 0.0)}))], '_mov')
    fit(vm)
    profile(vm)
    pk = vm.loads('(ola:peaks _prof 2 T)')
    assert len(pk) == 2, f"{len(pk)} peaks"
    at = [(p[1][0], p[1][1]) for p in pk]
    bottom = [p for p in at if p[1] < 40.0]
    right = [p for p in at if p[0] > 160.0 and p[1] > 40.0]
    assert len(bottom) == 1 and len(right) == 1, f"peaks bunched: {at}"
    # the deeper bump is reported first
    assert pk[0][0] > pk[1][0], [p[0] for p in pk]
    print("ok  two bumps on two walls get one dimension each, deeper first")


def test_a_clean_fit_draws_nothing():
    """Nothing over the floor means no dimensions, not four dimensions
    of nothing."""
    vm = newvm()
    shape = rect(150.0, 90.0)
    segs(vm, [lwpoly(vm, shape)], '_fix')
    segs(vm, [lwpoly(vm, pose(shape, 12.0, 300.0, 40.0))], '_mov')
    fit(vm)
    profile(vm)
    assert vm.loads('(ola:peaks _prof 4 T)') is NIL
    print("ok  a perfect overlay is dimensioned nowhere")


def test_peak_floor_is_honoured():
    vm = newvm()
    base = bumped(200.0, 200.0, {})
    segs(vm, [lwpoly(vm, base)], '_fix')
    segs(vm, [lwpoly(vm, bumped(200.0, 200.0, {20: (0.0, -3.0)}))], '_mov')
    fit(vm)
    profile(vm)
    vm.loads('(setq ola:*peak-min* 50.0)')
    assert vm.loads('(ola:peaks _prof 4 T)') is NIL
    vm.loads('(setq ola:*peak-min* 0.0625)')
    assert vm.loads('(length (ola:peaks _prof 4 T))') >= 1
    print("ok  ola:*peak-min* decides whether a spot is worth the ink")


# ---- the command ------------------------------------------------------

def two_pools(vm):
    """A perimeter on POOL and the same one, bumped, on Bead Track."""
    new = lwpoly(vm, pose(bumped(200.0, 200.0, {20: (0.0, -5.0)}),
                          33.0, 640.0, -220.0), layer='POOL')
    og = lwpoly(vm, bumped(200.0, 200.0, {}), layer='Bead Track')
    return new, og


def test_command_dimensions_the_worst_spots():
    """The bump is 5 deep on the right-hand wall.  It reads a little
    under 5 and not exactly 5, and that is the fit being honest: a
    least-squares overlay is dragged slightly toward a big local fault,
    which spreads a fraction of it over the rest of the perimeter.  The
    test pins the fault, not an idealisation of it."""
    vm = newvm()
    new, og = two_pools(vm)
    run(vm, [[new], [og], 'First', 'New'])
    dims = live(vm, 'DIMENSION')
    assert dims, "nothing dimensioned"
    assert len(dims) <= 4, f"{len(dims)} dimensions"
    for e, d in dims:
        assert d[8] == 'DIMENSION', d[8]
    worst = max(dims, key=lambda ed: ed[1][42])[1]
    assert 4.0 < worst[42] < 5.0, f"measured {worst[42]}"
    # ...and it is anchored on the wall the bump is in, x = 200
    assert near(worst[13][0], 200.0, 1.0), f"anchored at {worst[13]}"
    print(f"ok  OLAUTO dimensions the bump on the right wall, "
          f"reading {worst[42]:.3f} of its 5")


def test_peak_share_drops_the_fit_residue():
    """One fault and a little spread-out residue: raise the share and
    only the fault is reported."""
    vm = newvm()
    new, og = two_pools(vm)
    vm.loads('(setq ola:*peak-share* 0.5)')
    run(vm, [[new], [og], 'First', 'New'])
    assert len(live(vm, 'DIMENSION')) == 1, len(live(vm, 'DIMENSION'))
    print("ok  ola:*peak-share* keeps the fit's own residue out of the "
          "dimensions")


def test_command_puts_both_onto_the_shop_layers():
    vm = newvm()
    new = lwpoly(vm, pose(bumped(200.0, 200.0, {20: (0.0, -5.0)}),
                          14.0, 300.0, 90.0), layer='SCRATCH')
    og = lwpoly(vm, bumped(200.0, 200.0, {}), layer='OLD STUFF')
    run(vm, [[new], [og], 'First', 'New'])
    assert _alist_dict(vm.entdata[new])[8] == 'POOL'
    assert _alist_dict(vm.entdata[og])[8] == 'Bead Track'
    print("ok  the new goes onto POOL and the original onto Bead Track")


def corners(vm, e):
    d = vm.entdata[e]
    return [(g[1], g[2]) for g in d if isinstance(g, list) and g[0] == 10]


def test_the_one_that_moves_is_the_one_answered():
    """New moves and the original does not; answer OG and it is the
    other way round."""
    for who, moves, stays in (('New', 'new', 'og'), ('OG', 'og', 'new')):
        vm = newvm()
        new, og = two_pools(vm)
        before = {'new': corners(vm, new), 'og': corners(vm, og)}
        run(vm, [[new], [og], 'First', who], label=who)
        after = {'new': corners(vm, new), 'og': corners(vm, og)}
        shift = max(math.dist(a, b)
                    for a, b in zip(before[stays], after[stays]))
        assert shift < 1e-9, f"[{who}] the {stays} moved by {shift}"
        shift = max(math.dist(a, b)
                    for a, b in zip(before[moves], after[moves]))
        assert shift > 1.0, f"[{who}] the {moves} did not move"
    print("ok  only the perimeter named at the prompt is moved")


def test_layers_pre_answer_the_new_question():
    """The selection already on POOL is the new one, so Enter takes
    it -- whichever order the two were picked in."""
    for first, want in (('POOL', 'First'), ('Bead Track', 'Second')):
        vm = newvm()
        a = lwpoly(vm, pose(bumped(200.0, 200.0, {20: (0.0, -5.0)}),
                            9.0, 250.0, 80.0), layer=first)
        b = lwpoly(vm, bumped(200.0, 200.0, {}),
                   layer=('Bead Track' if first == 'POOL' else 'POOL'))
        # None at the keyword prompt is Enter: the default has to stand
        run(vm, [[a], [b], None, 'New'], label=first)
        newent = a if want == 'First' else b
        assert _alist_dict(vm.entdata[newent])[8] == 'POOL'
        ogent = b if want == 'First' else a
        assert _alist_dict(vm.entdata[ogent])[8] == 'Bead Track'
    print("ok  the layers answer the new/original question before it is asked")


def test_back_reopens_the_new_question():
    vm = newvm()
    new, og = two_pools(vm)
    # Back at the move question steps back to the new question
    run(vm, [[new], [og], 'First', 'Back', 'Second', 'New'])
    # answering Second the second time round means OG is the one on POOL
    assert _alist_dict(vm.entdata[og])[8] == 'POOL'
    assert _alist_dict(vm.entdata[new])[8] == 'Bead Track'
    said = ' '.join(vm.printed)
    assert 'Stepping back one question.' in said, said[-200:]
    print("ok  Back at the move question re-asks which one is new")


def test_back_at_the_first_question_reopens_the_selections():
    """A selection cannot be armed with initget, so Back cannot be typed
    at one -- Back at the question straight after them re-opens them,
    and the second pass is picked afresh."""
    vm = newvm()
    new, og = two_pools(vm)
    spare = lwpoly(vm, bumped(200.0, 200.0, {120: (-5.0, 0.0)}),
                   layer='SCRATCH')
    # pick the wrong pair, Back out of it, then pick the right one
    run(vm, [[spare], [og], 'Back', [new], [og], 'First', 'New'])
    # the spare was never touched: still on its own layer, never moved
    assert _alist_dict(vm.entdata[spare])[8] == 'SCRATCH'
    assert _alist_dict(vm.entdata[new])[8] == 'POOL'
    said = ' '.join(vm.printed)
    assert said.count('Select the FIRST perimeter') == 2, said.count(
        'Select the FIRST perimeter')
    print("ok  Back at the first question re-opens both selections")


def test_nothing_selected_is_not_an_error():
    vm = newvm()
    run(vm, [None])
    assert not live(vm, 'DIMENSION')
    print("ok  a cancelled selection leaves the drawing alone")


def test_dimension_count_follows_the_tunable():
    vm = newvm()
    new = lwpoly(vm, pose(bumped(200.0, 200.0,
                                 {10: (0.0, -5.0), 50: (5.0, 0.0),
                                  90: (0.0, 5.0), 130: (-5.0, 0.0)}),
                          21.0, 410.0, -160.0), layer='POOL')
    og = lwpoly(vm, bumped(200.0, 200.0, {}), layer='Bead Track')
    vm.loads('(setq ola:*dimcount* 3)')
    run(vm, [[new], [og], 'First', 'New'])
    assert len(live(vm, 'DIMENSION')) == 3, len(live(vm, 'DIMENSION'))
    print("ok  ola:*dimcount* decides how many dimensions are drawn")


def test_dimension_style_falls_back_and_is_put_back():
    vm = newvm()
    vm.sysvars['DIMSTYLE'] = 'MY HOUSE STYLE'
    vm.tables['DIMSTYLE'].add('MY HOUSE STYLE')
    new, og = two_pools(vm)
    run(vm, [[new], [og], 'First', 'New'])
    said = ' '.join(vm.printed)
    assert 'is not in this drawing' in said, said[-300:]
    assert vm.sysvars['DIMSTYLE'] == 'MY HOUSE STYLE', vm.sysvars['DIMSTYLE']
    print("ok  a missing dimension style is reported, and the drawing's "
          "own is put back")


def test_dimension_style_is_used_when_the_drawing_has_it():
    vm = newvm()
    vm.sysvars['DIMSTYLE'] = 'MY HOUSE STYLE'
    vm.tables['DIMSTYLE'].add('MY HOUSE STYLE')
    vm.tables['DIMSTYLE'].add('STANDARD INCHES')
    new, og = two_pools(vm)
    run(vm, [[new], [og], 'First', 'New'])
    dims = live(vm, 'DIMENSION')
    assert dims and dims[0][1][3] == 'STANDARD INCHES', dims[0][1][3]
    assert vm.sysvars['DIMSTYLE'] == 'MY HOUSE STYLE', vm.sysvars['DIMSTYLE']
    print("ok  the dims are drawn in STANDARD INCHES and the style put back")


def test_settings_come_back():
    vm = newvm()
    mklayer(vm, 'SOMETHING ELSE')
    vm.sysvars['OSMODE'] = 679
    vm.sysvars['CLAYER'] = 'SOMETHING ELSE'
    new, og = two_pools(vm)
    run(vm, [[new], [og], 'First', 'New'])
    assert vm.sysvars['OSMODE'] == 679, vm.sysvars['OSMODE']
    assert vm.sysvars['CLAYER'] == 'SOMETHING ELSE', vm.sysvars['CLAYER']
    print("ok  OSMODE and the current layer come back after a run")


def test_a_frozen_output_layer_is_thawed_and_said_so():
    vm = newvm()
    mklayer(vm, 'DIMENSION')
    rec = vm.layer_records['DIMENSION']
    vm.entdata[rec] = [x if not (isinstance(x, Dot) and x.a == 70)
                       else Dot(70, 1) for x in vm.entdata[rec]]
    new, og = two_pools(vm)
    run(vm, [[new], [og], 'First', 'New'])
    said = ' '.join(vm.printed)
    assert 'was off, frozen or locked' in said, said[-300:]
    print("ok  a frozen output layer is thawed, and the drafter is told")


def test_version_command():
    vm = newvm()
    vm.run('c:OLAUTOVER', [])
    assert 'OLAUTO v' in ' '.join(vm.printed)
    print("ok  OLAUTOVER reports the loaded version")


# ---- run them ----------------------------------------------------------

if __name__ == '__main__':
    fns = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    print(f"OLAUTO runtime tests ({ROOT} tier) -- {len(fns)} cases")
    for fn in fns:
        fn()
    print(f"\nall {len(fns)} OLAUTO tests passed")
