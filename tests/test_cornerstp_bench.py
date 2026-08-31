"""CORNERSTP's bench, driven end-to-end in the AutoLISP VM.

A bench can ride along one of the two corner walls: the wall is picked
by a point, the bench sits a given offset off it, and it is attached to
a numbered step.  What the code promises, asserted here on a square
corner (walls along +X and +Y, pool up-and-right, treads at 45):

  * steps up to the attachment tread still fit wall to wall
  * every later step fits between the far wall and the bench's front
    edge - on this corner the opening shrinks by offset * sqrt(2)
  * the front edge starts on the attachment tread and runs to the far
    end of its wall, where a cap closes it
  * no side line cuts across the bench - the front edge closes that
    side - and nothing extra appears on the far side either
  * Back across the bench boundary re-asks the step and rebuilds it
    against the same boundary
  * an attachment step that was never drawn means no bench, with the
    step run left standing
  * with dims on, the bench's length and its offset are measured too

Script values: numbers answer distance prompts, strings answer keyword
prompts, tuples are picked points, None is Enter.

Run against the grouped tier with:
    CALOFIN_LISP_ROOT=shared python3 tests/test_cornerstp_bench.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'cornerstp', 'CORNERSTP.lsp')

R2 = math.sqrt(2.0)


def fresh():
    """A VM with CORNERSTP loaded and the two corner walls drawn:
    (0,0)-(200,0) along +X and (0,0)-(0,200) along +Y."""
    vm = VM()
    vm.load(LSP)                            # CALOFIN_LISP_ROOT picks the tier
    vm.loads('(entmake (list (cons 0 "LINE")'
             ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
    vm.loads('(entmake (list (cons 0 "LINE")'
             ' (list 10 0.0 0.0 0.0) (list 11 0.0 200.0 0.0)))')
    return vm


def run(vm, script, label):
    try:
        vm.run('c:CORNERSTP', [None] + list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None


def lines(vm):
    """Every LINE still in the drawing, as ((x1,y1), (x2,y2))."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'LINE'
               for g in data):
            pts = {g[0]: tuple(g[1:3]) for g in data
                   if isinstance(g, list) and g and g[0] in (10, 11)}
            out.append((pts.get(10), pts.get(11)))
    return out


def has_line(ls, a, b, tol=1e-6):
    for p, q in ls:
        if (math.dist(p, a) < tol and math.dist(q, b) < tol) or \
           (math.dist(p, b) < tol and math.dist(q, a) < tol):
            return True
    return False


def measurements(vm):
    """Group 42 of every DIMENSION the run left behind."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
               for g in data):
            out.extend(g.b for g in data
                       if isinstance(g, Dot) and g.a == 42)
    return out


#: walls -> Inside out -> no dims -> bench Yes on the +Y wall, 20 off,
#: attached to step 1 -> three 24" treads fitted to the bounds -> done
#: -> no side profile.  (No bead question: AUTOBEAD is not loaded.)
def bench_script(walls, attach, treads=3):
    return ([walls, None, "No", "Yes", (1.0, 150.0), 20.0, attach]
            + [24.0, None] * treads + [None, "No"])


def test_steps_fit_wall_to_wall_up_to_the_attachment_tread():
    vm = fresh()
    run(vm, bench_script(list(vm.entities), 1), "bench at step 1")
    ls = lines(vm)
    # step 1 is the attachment tread: wall to wall, x+y = 24*sqrt(2)
    assert has_line(ls, (24 * R2, 0.0), (0.0, 24 * R2)), \
        "the attachment tread must still reach the wall"


def test_later_steps_fit_wall_to_bench():
    vm = fresh()
    run(vm, bench_script(list(vm.entities), 1), "bench at step 1")
    ls = lines(vm)
    for n in (2, 3):
        assert has_line(ls, (24 * n * R2, 0.0), (20.0, 24 * n * R2 - 20.0)), \
            f"step {n} must run from the far wall to the bench front"
    # and the fitted opening really is the wall one less offset*sqrt(2)
    got = math.dist((24 * 2 * R2, 0.0), (20.0, 24 * 2 * R2 - 20.0))
    assert abs(got - (96.0 - 20.0 * R2)) < 1e-6


def test_front_edge_spans_attachment_tread_to_wall_end_and_is_capped():
    vm = fresh()
    run(vm, bench_script(list(vm.entities), 1), "bench at step 1")
    ls = lines(vm)
    assert has_line(ls, (20.0, 24 * R2 - 20.0), (20.0, 200.0)), \
        "the front edge must start on the attachment tread and run to" \
        " the far end of its wall"
    assert has_line(ls, (20.0, 200.0), (0.0, 200.0)), \
        "the far end of the bench must be capped back to the wall"


def test_no_side_line_cuts_across_the_bench():
    vm = fresh()
    run(vm, bench_script(list(vm.entities), 1), "bench at step 1")
    # 2 walls + 3 treads + front edge + cap and NOTHING else: on this
    # corner the walls (or the bench) close every step side, so any
    # extra line is a stray riser cutting across the bench
    assert len(lines(vm)) == 7, \
        f"expected 7 lines, found {len(lines(vm))}: {lines(vm)!r}"


def test_back_across_the_bench_boundary_rebuilds_against_it():
    vm = fresh()
    script = ([list(vm.entities), None, "No", "Yes", (1.0, 150.0), 20.0, 1]
              + [24.0, None]              # step 1, fitted
              + [24.0, None]              # step 2, fitted to the bench
              + ["Back", 30.0, None]      # pop step 2, re-give its tread
              + [None, "No"])             # done; no side profile
    run(vm, script, "Back over the bench boundary")
    ls = lines(vm)
    assert has_line(ls, (54 * R2, 0.0), (20.0, 54 * R2 - 20.0)), \
        "the re-given step 2 must fit wall-to-bench at its new tread"
    assert not has_line(ls, (48 * R2, 0.0), (20.0, 48 * R2 - 20.0)), \
        "the popped step 2 must be gone from the drawing"
    # walls + tread 1 + rebuilt tread 2 + front edge + cap
    assert len(lines(vm)) == 6


def test_attachment_step_never_drawn_means_no_bench():
    vm = fresh()
    run(vm, bench_script(list(vm.entities), 5, treads=2),
        "bench at step 5, two steps")
    ls = lines(vm)
    # 2 walls + 2 wall-to-wall treads; no front edge, no cap
    assert len(ls) == 4, f"expected 4 lines, found {len(ls)}: {ls!r}"
    for n in (1, 2):
        assert has_line(ls, (24 * n * R2, 0.0), (0.0, 24 * n * R2)), \
            f"step {n} must still land wall to wall"


def test_dims_measure_the_bench_length_and_offset():
    vm = fresh()
    script = ([list(vm.entities), None, "Yes", "Yes", (1.0, 150.0),
               20.0, 1] + [24.0, None] * 3 + [None, "No"])
    run(vm, script, "bench with dims on")
    meas = measurements(vm)
    blen = 200.0 - (24 * R2 - 20.0)     # front edge, tread 1 to wall end
    assert any(abs(m - blen) < 1e-6 for m in meas), \
        f"no dim measures the bench length {blen}: {meas!r}"
    assert any(abs(m - 20.0) < 1e-6 for m in meas), \
        f"no dim measures the bench offset: {meas!r}"
    # the step dims are still there: 3 treads chained + 3 widths + 2
    assert len(meas) == 8, f"expected 8 dims, found {len(meas)}: {meas!r}"


def main():
    test_steps_fit_wall_to_wall_up_to_the_attachment_tread()
    test_later_steps_fit_wall_to_bench()
    test_front_edge_spans_attachment_tread_to_wall_end_and_is_capped()
    test_no_side_line_cuts_across_the_bench()
    test_back_across_the_bench_boundary_rebuilds_against_it()
    test_attachment_step_never_drawn_means_no_bench()
    test_dims_measure_the_bench_length_and_offset()
    print("all tests passed")


if __name__ == "__main__":
    main()
