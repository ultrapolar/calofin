"""The side profile CORNERSTP, HEMISTEP and NORMIESTEP draw, in the VM.

The flight always runs DOWN AND TO THE LEFT from the picked top of the
first tread, so the steps rise to the right, and the dims rise with
them.  What that means, asserted here:

  * the silhouette alternates drop/tread from the pick, leftward and
    downward, and ends on the last depth (N steps -> N+1 depths)
  * no side is asked for - the one pick places the whole profile
  * every depth gets its own dim, each standing further right than the
    one below it, so the dims climb with the steps instead of stacking
    in a single chain
  * each depth dim is bound to the two step corners bracketing it -
    which run diagonally - as a VERTICAL LINEAR dim, so it measures the
    drop and its extension lines still hook the real corners
  * both extension lines run forward (right), clear of the flight
  * the overall depth binds the whole diagonal, top corner to bottom
    corner, and sits further out than every depth dim
  * the treads carry no dims of their own

Script values: numbers answer distance prompts, strings answer keyword
prompts, tuples are picked points, None is Enter.

Run against the grouped tier with:
    CALOFIN_LISP_ROOT=shared python3 tests/test_cornerstp_profile.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError  # noqa: E402

HERE = os.path.dirname(__file__)
CORNERSTP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'CORNERSTP.lsp')
HEMISTEP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'HEMISTEP.lsp')
NORMIESTEP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'NORMIESTEP.lsp')

#: the pick, and the depths/treads the scripts below feed
PICK = (500.0, 400.0)
DEPTHS = [7.5, 10.75, 10.75, 10.5]     # 3 steps -> 4 depths
TREADS = [24.0, 24.0, 24.0]            # every step tread 24"


def walls(vm, pair=True):
    """The geometry the command selects: CORNERSTP wants the two walls
    of a corner, NORMIESTEP a single base line."""
    vm.loads('(entmake (list (cons 0 "LINE")'
             ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
    if pair:
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 0.0 0.0) (list 11 0.0 200.0 0.0)))')
    return list(vm.entities)


def run(path, cmd, script, label, styles=('STANDARD INCHES', 'SIDE STANDARD')):
    vm = VM()
    vm.load(path)                       # CALOFIN_LISP_ROOT picks the tier
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    script = list(script)
    if script[0] == 'WALLS':
        script[0] = walls(vm, pair=(cmd == 'c:CORNERSTP'))
    try:
        vm.run(cmd, script)
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def cornerstp_script(dims="No"):
    """walls -> inside out -> dims? -> no bench -> three 24" fitted
    steps -> done -> side profile Yes -> four depths -> the pick."""
    return (['WALLS', None, dims, "No"]
            + [24.0, None] * 3
            + [None, "Yes"] + DEPTHS + [PICK])


def normiestep_script(dims="No"):
    """NORMIESTEP: the base line, the side the steps go, width, square
    corners, dims?, three treads, then the profile."""
    return ['WALLS', (100.0, 50.0), 60.0, "Square", dims,
            24.0, 24.0, 24.0, None, "Yes"] + DEPTHS + [PICK]


def hemistep_script(dims="No"):
    """HEMISTEP: the base line, the side, dims?, the width at the wall,
    then tread/width per step, no crown, then the profile."""
    return ['WALLS', (100.0, 50.0), dims, 60.0]  \
        + [24.0, 60.0] * 3 + [None, None, "Yes"] + DEPTHS + [PICK]


def lines(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'LINE' for g in data):
            pts = {g[0]: tuple(g[1:3]) for g in data
                   if isinstance(g, list) and g and g[0] in (10, 11)}
            out.append((pts.get(10), pts.get(11)))
    return out


def dims(vm):
    """(origin1, origin2, dimline-point, measurement, kind) per dim, in
    the order placed.  kind 0 is linear, 1 is aligned."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        if not any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
                   for g in data):
            continue
        pts = {g[0]: tuple(g[1:3]) for g in data
               if isinstance(g, list) and g and g[0] in (13, 14, 10)}
        meas = next((g.b for g in data if isinstance(g, Dot) and g.a == 42),
                    None)
        kind = next((g.b for g in data if isinstance(g, Dot) and g.a == 70), 0)
        out.append((pts.get(13), pts.get(14), pts.get(10), meas, kind))
    return out


def corners():
    """The high-side corner at every level: the pick, then the foot of
    each drop, walking down and to the left."""
    x, y = PICK
    out = [(x, y)]
    for i, d in enumerate(DEPTHS):
        y -= d
        out.append((x, y))
        if i < len(TREADS):
            x -= TREADS[i]
    return out


def profile_dims(vm):
    """Just the profile's dims: the ones placed after the plan's."""
    return [d for d in dims(vm) if d[0] and d[0][1] <= PICK[1] + 1e-6
            and d[0][0] >= PICK[0] - sum(TREADS) - 1e-6
            and d[0][0] <= PICK[0] + 1e-6]


def profile_lines(vm):
    """Only the profile's own lines: it is drawn well clear of the plan,
    so its bounding box separates the two."""
    lo_x, lo_y = PICK[0] - sum(TREADS) - 1.0, PICK[1] - sum(DEPTHS) - 1.0
    return [(p, q) for p, q in lines(vm)
            if min(p[0], q[0]) >= lo_x and min(p[1], q[1]) >= lo_y]


def has_line(ls, a, b, tol=1e-6):
    return any((math.dist(p, a) < tol and math.dist(q, b) < tol) or
               (math.dist(p, b) < tol and math.dist(q, a) < tol)
               for p, q in ls)


def test_silhouette_runs_down_and_to_the_left():
    vm = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(), "silhouette")
    ls = lines(vm)
    cs = corners()
    for i, d in enumerate(DEPTHS):
        top, foot = cs[i], cs[i + 1]
        assert has_line(ls, (foot[0], top[1]), foot), \
            f"drop {i + 1} must fall from the level above at x={foot[0]}"
        if i < len(TREADS):
            assert has_line(ls, foot, (foot[0] - TREADS[i], foot[1])), \
                f"tread {i + 1} must run LEFT from the foot of drop {i + 1}"
    # ends on the last depth: one line per drop and one per tread, and
    # nothing after the final drop
    assert len(profile_lines(vm)) == len(DEPTHS) + len(TREADS), \
        f"expected {len(DEPTHS) + len(TREADS)} profile lines, got " \
        f"{profile_lines(vm)!r}"
    low = cs[-1][1]
    assert all(min(p[1], q[1]) >= low - 1e-6 for p, q in profile_lines(vm)), \
        "nothing may be drawn below the foot of the last depth"


def test_one_pick_places_it_with_no_side_question():
    # the script feeds exactly one point for the profile; a surviving
    # "which side" prompt would eat it and then run the script dry
    vm = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(), "one pick")
    asked = [p for p, _ in vm.prompts if 'side the steps descend' in p]
    assert not asked, f"the side question is gone, but was asked: {asked}"
    picks = [p for p, _ in vm.prompts if 'Pick the top' in p]
    assert len(picks) == 1, f"expected one profile pick prompt: {picks}"
    assert 'first tread' in picks[0], picks[0]


def test_every_depth_is_a_vertical_linear_dim_on_the_diagonal():
    vm = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(dims="Yes"),
             "depth dims")
    pd = profile_dims(vm)
    cs = corners()
    assert len(pd) == len(DEPTHS) + 1, \
        f"expected {len(DEPTHS)} depths + 1 overall, got {len(pd)}"
    for i, d in enumerate(DEPTHS):
        o1, o2, loc, meas, kind = pd[i]
        assert kind == 0, f"depth {i + 1} must be a LINEAR dim, not aligned"
        assert math.dist(o1, cs[i]) < 1e-6 and math.dist(o2, cs[i + 1]) < 1e-6, \
            f"depth {i + 1} must bind the two step corners: {o1} {o2}"
        assert abs(meas - d) < 1e-6, \
            f"depth {i + 1} must measure the drop {d}, not {meas}"
    # the middle ones really do bind a diagonal, not a plain vertical
    assert abs(pd[1][0][0] - pd[1][1][0]) > 1e-6, \
        "a depth below the first binds corners that differ in X"


def test_depth_dims_climb_up_and_to_the_right():
    vm = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(dims="Yes"),
             "climbing dims")
    pd = profile_dims(vm)
    xs = [d[2][0] for d in pd[:len(DEPTHS)]]
    ys = [d[2][1] for d in pd[:len(DEPTHS)]]
    for i in range(1, len(xs)):
        assert xs[i] < xs[i - 1] - 1e-6, \
            f"dim {i + 1} must sit LEFT of dim {i} - they descend: {xs}"
        assert ys[i] < ys[i - 1] - 1e-6, \
            f"dim {i + 1} must sit BELOW dim {i}: {ys}"
    # ...which is the same thing as rising to the right going up
    assert len(set(round(x, 6) for x in xs)) == len(xs), \
        f"no two depth dims may share a dim line: {xs}"


def test_both_extension_lines_run_forward_clear_of_the_flight():
    vm = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(dims="Yes"),
             "forward extensions")
    for o1, o2, loc, meas, kind in profile_dims(vm):
        assert loc[0] > o1[0] + 1e-6 and loc[0] > o2[0] + 1e-6, \
            f"the dim line at {loc} must sit right of both origins"


def test_overall_binds_the_whole_diagonal_and_sits_furthest_out():
    vm = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(dims="Yes"),
             "overall")
    pd = profile_dims(vm)
    cs = corners()
    o1, o2, loc, meas, kind = pd[-1]
    assert kind == 0, "the overall depth must be a LINEAR dim"
    assert math.dist(o1, cs[0]) < 1e-6 and math.dist(o2, cs[-1]) < 1e-6, \
        f"the overall must bind the top and bottom corners: {o1} {o2}"
    assert abs(meas - sum(DEPTHS)) < 1e-6, \
        f"the overall must measure {sum(DEPTHS)}, not {meas}"
    assert loc[0] > max(d[2][0] for d in pd[:-1]) + 1e-6, \
        "the overall must sit further out than every depth dim"


def test_the_treads_carry_no_dims():
    vm = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(dims="Yes"),
             "no tread dims")
    for o1, o2, loc, meas, kind in profile_dims(vm):
        assert abs(o1[1] - o2[1]) > 1e-6, \
            f"a dim across a level is a tread dim: {o1} {o2}"
    for t in set(TREADS):
        assert not any(abs(d[3] - t) < 1e-6 for d in profile_dims(vm)), \
            f"no profile dim may measure the tread run {t}"


def test_the_siblings_draw_the_same_profile():
    """HEMISTEP and NORMIESTEP carry the same profile code - the
    silhouette must land in the same places from the same pick."""
    for path, cmd, script in (
            (HEMISTEP, 'c:HEMISTEP', hemistep_script()),
            (NORMIESTEP, 'c:NORMIESTEP', normiestep_script())):
        vm = run(path, cmd, script, cmd)
        ls = lines(vm)
        cs = corners()
        for i, d in enumerate(DEPTHS):
            foot = cs[i + 1]
            assert has_line(ls, (foot[0], cs[i][1]), foot), \
                f"{cmd} drop {i + 1} must fall to the left like CORNERSTP's"
            if i < len(TREADS):
                assert has_line(ls, foot, (foot[0] - TREADS[i], foot[1])), \
                    f"{cmd} tread {i + 1} must run LEFT"
        asked = [p for p, _ in vm.prompts if 'side the steps descend' in p]
        assert not asked, f"{cmd} still asks which side: {asked}"


def test_the_siblings_dim_the_same_way():
    """...and dim it the same way: vertical linear dims on the step
    corners, climbing right, overall furthest out."""
    for path, cmd, script in (
            (HEMISTEP, 'c:HEMISTEP', hemistep_script(dims="Yes")),
            (NORMIESTEP, 'c:NORMIESTEP', normiestep_script(dims="Yes"))):
        vm = run(path, cmd, script, cmd)
        pd, cs = profile_dims(vm), corners()
        assert len(pd) == len(DEPTHS) + 1, f"{cmd}: {len(pd)} profile dims"
        for i, d in enumerate(DEPTHS):
            o1, o2, loc, meas, kind = pd[i]
            assert kind == 0, f"{cmd} depth {i + 1} must be linear"
            assert math.dist(o1, cs[i]) < 1e-6 and \
                math.dist(o2, cs[i + 1]) < 1e-6, \
                f"{cmd} depth {i + 1} must bind the step corners"
            assert abs(meas - d) < 1e-6, f"{cmd} depth {i + 1} = {meas}"
        xs = [x[2][0] for x in pd[:len(DEPTHS)]]
        assert all(xs[i] < xs[i - 1] - 1e-6 for i in range(1, len(xs))), \
            f"{cmd} dims must climb up and to the right: {xs}"
        assert pd[-1][2][0] > max(xs) + 1e-6, \
            f"{cmd} overall must sit furthest out"
        assert abs(pd[-1][3] - sum(DEPTHS)) < 1e-6, \
            f"{cmd} overall must measure {sum(DEPTHS)}"


def main():
    test_silhouette_runs_down_and_to_the_left()
    test_one_pick_places_it_with_no_side_question()
    test_every_depth_is_a_vertical_linear_dim_on_the_diagonal()
    test_depth_dims_climb_up_and_to_the_right()
    test_both_extension_lines_run_forward_clear_of_the_flight()
    test_overall_binds_the_whole_diagonal_and_sits_furthest_out()
    test_the_treads_carry_no_dims()
    test_the_siblings_draw_the_same_profile()
    test_the_siblings_dim_the_same_way()
    print("all tests passed")


if __name__ == "__main__":
    main()
