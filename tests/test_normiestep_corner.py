"""NORMIESTEP's corner mode: the run's outer side, in the VM.

Two lines make the corner.  You pick the one the steps run OFF OF; the
treads all start on the OTHER one and run outward from it by the step
width.  So the run's outer side is that other line offset by the width -
NOT a line square to the base.  Get that wrong and a corner that is not
a true 90 leans the side wall into the step field, and every tread but
the first ends somewhere other than on it.

Asserted here, on a corner leaning each way and on a square one:

  * the outer side runs from the base out to the last tread's outer end
  * every tread's outer end lands ON that side, not past it or short
  * a square corner is unchanged - the common case cannot regress
  * a Cut or Radius back corner still flares the mouth OUTWARD, away
    from the run, and rejoins the side
  * a step taken Back leaves the side on the tread that survived

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
#: run off it, so they march in +Y along whichever line is given here
SQUARE = (0.0, 200.0)
LEANS_OUT = (100.0, 200.0)      # away from the run
LEANS_IN = (-100.0, 200.0)      # back across the corner


def run(sideend, treatment=("Square",), treads=(12.0, 12.0), extra=()):
    vm = VM()
    vm.load(LSP)                        # CALOFIN_LISP_ROOT picks the tier
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 %r %r 0.0)))' % BASE_END)
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 %r %r 0.0)))' % sideend)
    script = ([None, list(vm.entities), (100.0, 0.0), WID] + list(treatment)
              + ["No"] + list(treads) + list(extra) + [None, "No"])
    try:
        vm.run('c:NORMIESTEP', script)
    except LispError as e:
        raise AssertionError(f"[side {sideend}] {e}") from None
    return vm


def lines(vm):
    """Every LINE the run left behind, the two selected ones dropped."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'LINE'
               for g in data):
            pts = {g[0]: tuple(g[1:3]) for g in data
                   if isinstance(g, list) and g and g[0] in (10, 11)}
            out.append((pts[10], pts[11]))
    return [seg for seg in out
            if seg not in (((0.0, 0.0), BASE_END),) and seg[0] != (0.0, 0.0)]


def treads_of(vm):
    """The treads: level lines above the base, lowest first.  Each runs
    from the line the steps sit against out to the run's outer side."""
    got = [seg for seg in lines(vm)
           if abs(seg[0][1] - seg[1][1]) < 1e-9 and seg[0][1] > 1e-9]
    return sorted((tuple(sorted(s, key=lambda p: p[0])) for s in got),
                  key=lambda s: s[0][1])


def sides_of(vm):
    """Everything that is not a tread: the outer side and any corner
    piece flaring its mouth at the base."""
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


def outer_end(tread):
    """A tread runs from the line it sits against outward, so its outer
    end is the one further along +X."""
    return max(tread, key=lambda p: p[0])


def test_every_tread_ends_on_the_outer_side():
    for label, sideend in (("square", SQUARE),
                           ("leaning out", LEANS_OUT),
                           ("leaning in", LEANS_IN)):
        vm = run(sideend)
        ts, sides = treads_of(vm), sides_of(vm)
        assert len(ts) == 2, f"{label}: expected 2 treads, got {ts}"
        assert len(sides) == 1, f"{label}: expected one outer side: {sides}"
        (sa, sb) = sides[0]
        # the outer side spans the base to the last tread's outer end
        assert min(sa[1], sb[1]) == 0.0, \
            f"{label}: the outer side must start at the base: {sides[0]}"
        top = max((sa, sb), key=lambda p: p[1])
        assert math.dist(top, outer_end(ts[-1])) < 1e-6, \
            f"{label}: the outer side must reach the last tread's end " \
            f"{outer_end(ts[-1])}, not {top}"
        # ...and every tread lands on it, so none pokes through or falls
        # short of the side wall
        bot = min((sa, sb), key=lambda p: p[1])
        for i, t in enumerate(ts):
            e = outer_end(t)
            cross = ((top[0] - bot[0]) * (e[1] - bot[1])
                     - (top[1] - bot[1]) * (e[0] - bot[0]))
            assert abs(cross) < 1e-6, \
                f"{label}: tread {i + 1} ends at {e}, off the outer side"


def test_a_square_corner_is_unchanged():
    vm = run(SQUARE)
    ts = treads_of(vm)
    assert ts[0] == ((0.0, 12.0), (WID, 12.0)), ts[0]
    assert ts[1] == ((0.0, 24.0), (WID, 24.0)), ts[1]
    assert sides_of(vm) == [((WID, 0.0), (WID, 24.0))], sides_of(vm)


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
        assert len(sides) == 2, f"{label}: cut piece + side: {sides}"
        atbase = [p for seg in sides for p in seg if abs(p[1]) < 1e-9]
        assert len(atbase) == 1, f"{label}: one meeting at the base: {atbase}"
        # the mouth opens WIDER than the run, away from the corner - a
        # cut that narrowed it would be biting into the steps instead
        assert atbase[0][0] > WID + 1e-6, \
            f"{label}: the cut must flare outward past {WID}: {atbase[0]}"
        top = max((p for seg in sides for p in seg), key=lambda p: p[1])
        assert math.dist(top, outer_end(treads_of(vm)[-1])) < 1e-6, \
            f"{label}: the side must still reach the last tread: {top}"


def test_a_radius_corner_flares_outwards_too():
    """The fillet is an ARC, so it is the centre that says which way the
    mouth opens: one radius off the base, and one radius past the run."""
    for label, sideend in (("square", SQUARE), ("leaning out", LEANS_OUT)):
        vm = run(sideend, treatment=("Radius", 6.0))
        arcs = arcs_of(vm)
        assert len(arcs) == 1, f"{label}: expected one fillet: {arcs}"
        (cx, cy), r = arcs[0][0], arcs[0][1]
        assert abs(r - 6.0) < 1e-6, f"{label}: radius {r}"
        assert cy > 1e-6, \
            f"{label}: the centre must sit off the base, not {cy}"
        assert cx > WID + 1e-6, \
            f"{label}: the fillet must flare outward past {WID}: {cx}"
        # NOTE: the centre is stepped one offset along each leg, which
        # is a true tangent fillet only where the legs are square to
        # each other.  On a leaning corner the arc is slightly off
        # tangent - a separate gap from the direction this file pins,
        # so it is deliberately not asserted here.
        top = max((p for seg in sides_of(vm) for p in seg),
                  key=lambda p: p[1])
        assert math.dist(top, outer_end(treads_of(vm)[-1])) < 1e-6, \
            f"{label}: the side must still reach the last tread"


def test_back_leaves_the_side_on_the_tread_that_survived():
    # three treads, the third taken Back and re-given shallower
    vm = run(LEANS_OUT, treads=(12.0, 12.0, 12.0), extra=("Back", 6.0))
    ts = treads_of(vm)
    assert len(ts) == 3, f"expected 3 treads, got {ts}"
    assert abs(ts[-1][0][1] - 30.0) < 1e-6, \
        f"the re-given last tread should sit at 30, not {ts[-1][0][1]}"
    top = max((p for seg in sides_of(vm) for p in seg), key=lambda p: p[1])
    assert math.dist(top, outer_end(ts[-1])) < 1e-6, \
        f"the outer side must follow the surviving tread to {outer_end(ts[-1])}"


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
    test_every_tread_ends_on_the_outer_side()
    test_a_square_corner_is_unchanged()
    test_the_run_holds_its_width_whichever_way_the_corner_leans()
    test_a_cut_corner_flares_the_mouth_outwards()
    test_a_radius_corner_flares_outwards_too()
    test_back_leaves_the_side_on_the_tread_that_survived()
    test_clayer_comes_back_when_a_dimension_dies()
    print("all tests passed")


if __name__ == "__main__":
    main()
