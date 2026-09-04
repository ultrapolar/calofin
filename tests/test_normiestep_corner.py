"""NORMIESTEP's corner mode: the recess outside the corner, in the VM.

Two lines make the corner, and the corner itself says which way the run
goes: both lines run away from it into the pool, so the water is the
side they span and OUTSIDE is the other one.  The run sits in a recess
on the far side of the wall it comes off - never in the water between
the two lines.  You pick the line the steps run OFF OF; the treads butt
against the OTHER one, carried on past the corner, and run outward from
it by the step width.

Asserted here, on a corner leaning each way and on a square one:

  * the run is outside the corner: every tread on the far side of the
    picked line from the line it butts against
  * BOTH sides of the recess are drawn - the inner one carrying the
    line the treads sit against past the corner, the outer one that
    same line offset by the width - and both start on the wall
  * every tread's inner end lands on the inner side and its outer end
    on the outer side, neither past it nor short of it
  * a square corner comes out square - the common case cannot regress
  * a Cut or Radius back corner flares the mouth outward, away from the
    run, and only on the OUTER side: the inner one runs straight on out
    of the wall it continues, so there is no corner there to treat
  * a step taken Back leaves the sides on the tread that survived

Script values: numbers answer distance prompts, strings answer keyword
prompts, tuples are picked points, None is Enter.

Run against the grouped tier with:
    CALOFIN_LISP_ROOT=shared python3 tests/test_normiestep_corner.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, Dot, LispError, Sym  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'cornerstp', 'NORMIESTEP.lsp')

WID = 60.0          # step width
BASE_END = (200.0, 0.0)
#: the corner sits at the origin; the base runs along +X and the steps
#: run off it, so the recess is at -Y and the line given here - which
#: runs into the pool at +Y - closes it, carried past the corner
SQUARE = (0.0, 200.0)
LEANS_OUT = (100.0, 200.0)      # its extension leans away from the run
LEANS_IN = (-100.0, 200.0)      # ...and back across it


def run(sideend, treatment=("Square",), treads=(12.0, 12.0), extra=()):
    vm = VM()
    vm.load(LSP)                        # CALOFIN_LISP_ROOT picks the tier
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 %r %r 0.0)))' % BASE_END)
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 %r %r 0.0)))' % sideend)
    picked = list(vm.entities)          # the two walls, not the run's own
    script = ([None, picked, (100.0, 0.0), WID] + list(treatment)
              + ["No"] + list(treads) + list(extra) + [None, "No"])
    try:
        vm.run('c:NORMIESTEP', script)
    except LispError as e:
        raise AssertionError(f"[side {sideend}] {e}") from None
    vm.picked = picked
    return vm


def lines(vm):
    """Every LINE the run left behind, the two selected walls dropped."""
    out = []
    for e in vm.entities:
        if e in vm.deleted or e in getattr(vm, 'picked', ()):
            continue
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'LINE'
               for g in data):
            pts = {g[0]: tuple(g[1:3]) for g in data
                   if isinstance(g, list) and g and g[0] in (10, 11)}
            out.append((pts[10], pts[11]))
    return out


def treads_of(vm):
    """The treads: level lines below the base, the one at the wall
    first.  Each runs from the line the steps sit against - carried
    past the corner - out to the run's outer side."""
    got = [seg for seg in lines(vm)
           if abs(seg[0][1] - seg[1][1]) < 1e-9 and seg[0][1] < -1e-9]
    return sorted((tuple(sorted(s, key=lambda p: p[0])) for s in got),
                  key=lambda s: -s[0][1])


def sides_of(vm):
    """Everything that is not a tread: the two sides of the recess and
    any corner piece flaring its mouth at the base."""
    return [seg for seg in lines(vm) if seg not in
            [s for t in treads_of(vm) for s in (t, (t[1], t[0]))]]


def arcs_of(vm):
    """(centre, radius, start, end) for every fillet drawn."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'ARC'
               for g in data):
            c = next(tuple(g[1:3]) for g in data
                     if isinstance(g, list) and g and g[0] == 10)
            d = {g.a: g.b for g in data if isinstance(g, Dot)}
            out.append((c, d.get(40), d.get(50), d.get(51)))
    return out


def inner_end(tread):
    """A tread runs from the line it sits against outward, so its inner
    end is the one nearer the corner along the base - the lower X."""
    return min(tread, key=lambda p: p[0])


def outer_end(tread):
    return max(tread, key=lambda p: p[0])


def on_segment(p, a, b):
    """Signed area of a-b-p: zero when P is on the line through them."""
    return ((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]))


def at_base(segs):
    """Every endpoint sitting on the wall the run comes off."""
    return [p for seg in segs for p in seg if abs(p[1]) < 1e-9]


def reaches(segs, pt):
    """Does any side end on PT - the end of the last tread it closes?"""
    return any(math.dist(p, pt) < 1e-6 for seg in segs for p in seg)


def test_the_run_sits_outside_the_corner():
    """The two lines span the water; the steps go the other way."""
    for label, sideend in (("square", SQUARE),
                           ("leaning out", LEANS_OUT),
                           ("leaning in", LEANS_IN)):
        vm = run(sideend)
        ts = treads_of(vm)
        assert len(ts) == 2, f"{label}: expected 2 treads, got {ts}"
        for i, t in enumerate(ts):
            for p in t:
                assert p[1] < 0.0, \
                    (f"{label}: tread {i + 1} is at {p}, inside the corner - "
                     f"the run belongs on the far side of the base line")
        assert abs(ts[0][0][1] + 12.0) < 1e-6, \
            f"{label}: the first tread sits 12 out from the wall: {ts[0]}"
        assert abs(ts[1][0][1] + 24.0) < 1e-6, \
            f"{label}: the second sits 12 past the first: {ts[1]}"


def test_both_sides_are_drawn_and_every_tread_lands_on_them():
    for label, sideend in (("square", SQUARE),
                           ("leaning out", LEANS_OUT),
                           ("leaning in", LEANS_IN)):
        vm = run(sideend)
        ts, sides = treads_of(vm), sides_of(vm)
        assert len(sides) == 2, \
            f"{label}: the recess needs both its sides: {sides}"
        # the inner side is the one starting at the corner itself
        inner = [s for s in sides if any(math.dist(p, (0.0, 0.0)) < 1e-9
                                         for p in s)]
        assert len(inner) == 1, f"{label}: one side starts at the corner: {sides}"
        inner = inner[0]
        outer = [s for s in sides if s != inner][0]
        for name, seg in (("inner", inner), ("outer", outer)):
            assert abs(max(p[1] for p in seg)) < 1e-9, \
                f"{label}: the {name} side must start on the wall: {seg}"
        # each runs down to its end of the last tread
        assert math.dist(min(inner, key=lambda p: p[1]),
                         inner_end(ts[-1])) < 1e-6, \
            f"{label}: the inner side must reach {inner_end(ts[-1])}: {inner}"
        assert math.dist(min(outer, key=lambda p: p[1]),
                         outer_end(ts[-1])) < 1e-6, \
            f"{label}: the outer side must reach {outer_end(ts[-1])}: {outer}"
        # ...and every tread ends on them, so none pokes through or
        # falls short of either wall of the recess
        for i, t in enumerate(ts):
            assert abs(on_segment(inner_end(t), *inner)) < 1e-6, \
                f"{label}: tread {i + 1} starts off the inner side"
            assert abs(on_segment(outer_end(t), *outer)) < 1e-6, \
                f"{label}: tread {i + 1} ends off the outer side"


def test_a_square_corner_is_square():
    vm = run(SQUARE)
    ts = treads_of(vm)
    assert ts[0] == ((0.0, -12.0), (WID, -12.0)), ts[0]
    assert ts[1] == ((0.0, -24.0), (WID, -24.0)), ts[1]
    assert sorted(sides_of(vm)) == sorted([((0.0, 0.0), (0.0, -24.0)),
                                           ((WID, 0.0), (WID, -24.0))]), \
        sides_of(vm)


def test_the_run_holds_its_width_whichever_way_the_corner_leans():
    for label, sideend in (("leaning out", LEANS_OUT),
                           ("leaning in", LEANS_IN)):
        for i, t in enumerate(treads_of(run(sideend))):
            got = math.dist(*t)
            assert abs(got - WID) < 1e-6, \
                f"{label}: tread {i + 1} is {got} wide, not {WID}"


def test_a_cut_corner_flares_the_mouth_outwards():
    for label, sideend in (("square", SQUARE), ("leaning out", LEANS_OUT),
                           ("leaning in", LEANS_IN)):
        vm = run(sideend, treatment=("Cut", "Offset", 6.0))
        sides = sides_of(vm)
        assert len(sides) == 3, \
            f"{label}: both sides plus the cut piece: {sides}"
        feet = sorted(at_base(sides))
        assert len(feet) == 2, f"{label}: two feet on the wall: {feet}"
        # the inner side runs straight on out of the wall it continues,
        # so it is untreated and still leaves the corner itself
        assert math.dist(feet[0], (0.0, 0.0)) < 1e-9, \
            f"{label}: the inner side must still start at the corner: {feet}"
        # ...and the mouth opens WIDER than the run, away from the
        # steps - a cut that narrowed it would be biting into them
        assert feet[1][0] > WID + 1e-6, \
            f"{label}: the cut must flare outward past {WID}: {feet[1]}"
        last = treads_of(vm)[-1]
        assert reaches(sides, outer_end(last)), \
            f"{label}: the outer side must still reach {outer_end(last)}"
        assert reaches(sides, inner_end(last)), \
            f"{label}: the inner side must still reach {inner_end(last)}"


def test_a_radius_corner_flares_outwards_too():
    """The fillet is an ARC, so it is the centre that says which way the
    mouth opens: one radius off the base, and one radius past the run."""
    for label, sideend in (("square", SQUARE), ("leaning out", LEANS_OUT)):
        vm = run(sideend, treatment=("Radius", 6.0))
        arcs = arcs_of(vm)
        assert len(arcs) == 1, f"{label}: expected one fillet: {arcs}"
        (cx, cy), r = arcs[0][0], arcs[0][1]
        assert abs(r - 6.0) < 1e-6, f"{label}: radius {r}"
        assert cy < -1e-6, \
            f"{label}: the centre must sit off the base, inside the run's"\
            f" own depth, not {cy}"
        assert cx > WID + 1e-6, \
            f"{label}: the fillet must flare outward past {WID}: {cx}"
        # NOTE: the centre is stepped one offset along each leg, which
        # is a true tangent fillet only where the legs are square to
        # each other.  On a leaning corner the arc is slightly off
        # tangent - a separate gap from the direction this file pins,
        # so it is deliberately not asserted here.
        assert reaches(sides_of(vm), outer_end(treads_of(vm)[-1])), \
            f"{label}: the outer side must still reach the last tread"


def test_back_leaves_the_sides_on_the_tread_that_survived():
    # three treads, the third taken Back and re-given shallower
    vm = run(LEANS_OUT, treads=(12.0, 12.0, 12.0), extra=("Back", 6.0))
    ts = treads_of(vm)
    assert len(ts) == 3, f"expected 3 treads, got {ts}"
    assert abs(ts[-1][0][1] + 30.0) < 1e-6, \
        f"the re-given last tread should sit at -30, not {ts[-1][0][1]}"
    assert reaches(sides_of(vm), outer_end(ts[-1])), \
        f"the outer side must follow the surviving tread to {outer_end(ts[-1])}"
    assert reaches(sides_of(vm), inner_end(ts[-1])), \
        f"the inner side must follow it too, to {inner_end(ts[-1])}"


def test_clayer_comes_back_when_a_dimension_dies():
    """ns-dim swaps CLAYER onto the dimension layer around DIMALIGNED and
    puts it back inline; until v3.4 the handler restored CMDECHO and
    LUNITS only, so an Esc while a dimension was drawing left the
    drafter's next lines landing on DIMENSION."""
    vm = VM()
    vm.load(LSP)
    vm.loads('(entmake (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")'
             ' (cons 100 "AcDbLayerTableRecord") (cons 2 "DIMENSION") (cons 70 0)'
             ' (cons 62 2) (cons 6 "Continuous")))')
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 %r %r 0.0)))' % BASE_END)
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 %r %r 0.0)))' % SQUARE)
    # the swap only happens with a dimension layer configured, and the
    # dims only when the run says Yes to them
    vm.loads('(setq *cs-dim-layer* "DIMENSION")')
    vm.handle_errors = True
    orig = lispvm.BUILTINS[Sym('command')]
    at_death = {}

    def dies_at_dimaligned(vm_, a):
        if a and a[0] == '_.DIMALIGNED':
            at_death['clayer'] = vm_.sysvars['CLAYER']
            raise LispError('DIMALIGNED refused', vm_)
        return orig(vm_, a)

    lispvm.BUILTINS[Sym('command')] = dies_at_dimaligned
    try:
        vm.run('c:NORMIESTEP', [None, list(vm.entities), (100.0, 0.0), WID,
                                "Square", "Yes", 12.0, 12.0, None, "No"])
    finally:
        lispvm.BUILTINS[Sym('command')] = orig
    assert vm.handled_errors and 'DIMALIGNED refused' in vm.handled_errors[0], \
        vm.handled_errors
    assert at_death.get('clayer') == 'DIMENSION', \
        "the dimension layer was not current when the dimension died: %r" % at_death
    assert vm.sysvars['CLAYER'] == '0', "CLAYER left on %r" % vm.sysvars['CLAYER']
    assert vm.sysvars['CMDECHO'] == 1 and vm.undo_groups == 0, \
        (vm.sysvars['CMDECHO'], vm.undo_groups)
    print("CLAYER comes back when the run dies inside a dimension")


def main():
    test_the_run_sits_outside_the_corner()
    test_both_sides_are_drawn_and_every_tread_lands_on_them()
    test_a_square_corner_is_square()
    test_the_run_holds_its_width_whichever_way_the_corner_leans()
    test_a_cut_corner_flares_the_mouth_outwards()
    test_a_radius_corner_flares_outwards_too()
    test_back_leaves_the_sides_on_the_tread_that_survived()
    test_clayer_comes_back_when_a_dimension_dies()
    print("all tests passed")


if __name__ == "__main__":
    main()
