#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Three demos and a profile that drew in the wrong frame under a UCS.

getpoint answers in the drafter's UCS; entmake keeps World; (command ...)
reads the UCS.  Every routine here mixed two of those, and every test it
had ran in World, where the three are one frame and nothing can tell:

  * CORNERSTP, HEMISTEP and NORMIESTEP laid the side profile out in
    World from the pick, then dimensioned each depth with a DIMLINEAR
    forced "_V" -- which AutoCAD reads along the UCS Y.  In a UCS turned
    30 degrees every depth read drop*cos 30: a 7.5 drop was dimensioned
    6.495.  The profile is built in the UCS now, so "down and to the
    left" is the drafter's and the "_V" dims measure the drop;
  * LISPLAB drew its demo circles and notes at the raw UCS numbers of
    the pick, as World -- the lesson landed somewhere else;
  * TUTORIALPADDLE built its sample perimeter at the raw pick too, while
    its ZOOM framed the spot that was picked, and Enter's "0,0" was
    World's 0,0 rather than the UCS origin the prompt names.

Each check sets its own UCS with vm.set_ucs -- the VM models the frames
honestly now (trans, getpoint in UCS numbers, DIMLINEAR measured along
the UCS axes) -- and each FAILS on the file as it was before the fix:
the routines take a path, so the same checks run against HEAD's copy.

Run: python3 tests/test_ucsfix_misc.py
"""

import math
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

from lispvm import VM, Dot, LispError  # noqa: E402

LISP = os.path.join(REPO_DIR, 'lisp')
CORNERSTP = os.path.join(LISP, 'cornerstp', 'CORNERSTP.lsp')
HEMISTEP = os.path.join(LISP, 'cornerstp', 'HEMISTEP.lsp')
NORMIESTEP = os.path.join(LISP, 'cornerstp', 'NORMIESTEP.lsp')
LISPLAB = os.path.join(LISP, 'lisplab', 'LISPLAB.lsp')
PADDLE = os.path.join(LISP, 'paddle', 'PADDLE.lsp')

#: the UCS every check below runs under: moved AND turned, so a frame
#: mixed up shows as a wrong place, a wrong direction or a wrong length
UCS_ORIGIN = (1000.0, 500.0, 0.0)
UCS_TURN = math.radians(30.0)

TOL = 1e-6


def turned_vm():
    vm = VM()
    vm.set_ucs(UCS_ORIGIN, UCS_TURN)
    return vm


def world(vm, p):
    """UCS point P in World numbers, 2D."""
    w = vm.ucs_to_wcs(list(p) + [0.0] * (3 - len(p)))
    return (w[0], w[1])


def dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


def live(vm, kind):
    return [e for e in vm.entities
            if e not in vm.deleted and dxf(vm, e, 0) == kind]


def near(a, b, tol=TOL):
    return math.dist(a[:2], b[:2]) < tol


# ---------------------------------------------------------------------
# The step routines' side profile
# ---------------------------------------------------------------------

#: the pick, in UCS numbers, and the depths/treads the scripts feed
PICK = (500.0, 400.0)
DEPTHS = [7.5, 10.75, 10.75, 10.5]     # 3 steps -> 4 depths
TREADS = [24.0, 24.0, 24.0]
#: *cs-profile-dimgap*, pinned so the fan's standoff is a known number:
#: each depth dim stands the widest tread plus this right of its corner,
#: and the overall this much further out again
GAP = 30.0


def _walls(vm, pair):
    """The geometry the command selects, in World: CORNERSTP wants the
    two walls of a corner, the others one base line."""
    vm.loads('(entmake (list (cons 0 "LINE")'
             ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
    if pair:
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 0.0 0.0) (list 11 0.0 200.0 0.0)))')
    return list(vm.entities)


def _base_pick(vm):
    """HEMISTEP / NORMIESTEP pick the side the steps go: a point that is
    the same spot in the drawing whatever the UCS, so the plan is the
    same plan and only the profile is under test."""
    return list(vm.wcs_to_ucs([100.0, 50.0, 0.0]))


def _cornerstp_script(vm):
    return ([_walls(vm, True), None, "Yes", "No"]
            + [24.0, None] * 3
            + [None, "Yes"] + DEPTHS + [list(PICK)])


def _hemistep_script(vm):
    return ([_walls(vm, False), _base_pick(vm), "Yes", 60.0]
            + [24.0, 60.0] * 3 + [None, None, "Yes"] + DEPTHS
            + [list(PICK)])


def _normiestep_script(vm):
    return ([_walls(vm, False), _base_pick(vm), 60.0, "Square", "Yes",
             24.0, 24.0, 24.0, None, "Yes"] + DEPTHS + [list(PICK)])


STEP_TOOLS = (
    ('CORNERSTP', 'c:CORNERSTP', _cornerstp_script),
    ('HEMISTEP', 'c:HEMISTEP', _hemistep_script),
    ('NORMIESTEP', 'c:NORMIESTEP', _normiestep_script),
)


def _ucs_corners():
    """The high-side corner at every level, in UCS numbers: the pick,
    then the foot of each drop, walking down and to the left."""
    x, y = PICK
    out = [(x, y)]
    for i, d in enumerate(DEPTHS):
        y -= d
        out.append((x, y))
        if i < len(TREADS):
            x -= TREADS[i]
    return out


def _run_step(path, cmd, script):
    vm = turned_vm()
    vm.load(path)
    vm.loads(f'(setq *cs-profile-dimgap* {GAP})')
    for s in ('STANDARD INCHES', 'SIDE STANDARD'):
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48.0
    try:
        vm.run(cmd, [None] + script(vm))
    except LispError as e:
        raise AssertionError(f"[{cmd} under a turned UCS] {e}") from None
    return vm


def _lines(vm):
    out = []
    for e in live(vm, 'LINE'):
        p, q = dxf(vm, e, 10), dxf(vm, e, 11)
        out.append((tuple(p[:2]), tuple(q[:2])))
    return out


def _has_line(ls, a, b):
    return any((near(p, a) and near(q, b)) or (near(p, b) and near(q, a))
               for p, q in ls)


def _profile_dims(vm, corners_w):
    """The profile's dims: the ones whose first origin is a profile
    corner, in the order placed.  (origin1, origin2, measurement, the
    dim line's point in UCS numbers, group 50)."""
    out = []
    for e in live(vm, 'DIMENSION'):
        o1, o2 = dxf(vm, e, 13), dxf(vm, e, 14)
        if o1 is None or o2 is None:
            continue
        if any(near(o1, c) for c in corners_w):
            d10 = dxf(vm, e, 10)
            out.append((tuple(o1[:2]), tuple(o2[:2]), dxf(vm, e, 42),
                        tuple(vm.wcs_to_ucs(list(d10))[:2]),
                        dxf(vm, e, 50)))
    return out


def check_step_profile(paths=None):
    """Under a UCS moved to 1000,500 and turned 30 degrees: every drop
    falls along the UCS -Y and every tread runs along the UCS -X, from
    the World point of the pick -- and every depth dim measures the drop
    it was given, not drop*cos 30."""
    paths = paths or {'CORNERSTP': CORNERSTP, 'HEMISTEP': HEMISTEP,
                      'NORMIESTEP': NORMIESTEP}
    for name, cmd, script in STEP_TOOLS:
        vm = _run_step(paths[name], cmd, script)
        # first what the drafter reads, whatever frame it was drawn in:
        # the profile's dims are the last ones placed, and each says
        # the drop it was given (the old World profile said drop*cos 30)
        last = [dxf(vm, e, 42) for e in live(vm, 'DIMENSION')]
        last = last[-(len(DEPTHS) + 1):]
        for i, (got, d) in enumerate(zip(last, DEPTHS + [sum(DEPTHS)])):
            assert got is not None and abs(got - d) < TOL, \
                f"{name}: profile dim {i + 1} must read {d}, not {got}"
        cu = _ucs_corners()
        cw = [world(vm, c) for c in cu]
        ls = _lines(vm)
        for i in range(len(DEPTHS)):
            top_u, foot_u = cu[i], cu[i + 1]
            assert _has_line(ls, world(vm, (foot_u[0], top_u[1])),
                             cw[i + 1]), \
                f"{name}: drop {i + 1} must fall along the UCS Y from " \
                f"the level above, ending at World {cw[i + 1]}"
            if i < len(TREADS):
                assert _has_line(ls, cw[i + 1],
                                 world(vm, (foot_u[0] - TREADS[i],
                                            foot_u[1]))), \
                    f"{name}: tread {i + 1} must run LEFT along the UCS X"
        pd = _profile_dims(vm, cw)
        assert len(pd) == len(DEPTHS) + 1, \
            f"{name}: expected {len(DEPTHS)} depth dims + 1 overall on " \
            f"the profile's corners, found {len(pd)}"
        # the fan: a depth dim's line stands the widest tread plus the
        # gap to the RIGHT of the corner its drop lands on, along the
        # UCS X -- so the dims climb with the steps as the drafter sees
        # them -- and the overall's stands the gap further out from the
        # pick.  A THRU handed over in World numbers would still read
        # the right drops but hang the fan off somewhere else.
        pfo = max(TREADS) + GAP
        vaxis = (math.pi / 2 + UCS_TURN) % (2 * math.pi)
        for i, d in enumerate(DEPTHS):
            o1, o2, meas, at, rot = pd[i]
            assert near(o1, cw[i]) and near(o2, cw[i + 1]), \
                f"{name}: depth {i + 1} must bind corners {cw[i]} and " \
                f"{cw[i + 1]}, not {o1} {o2}"
            assert abs(meas - d) < TOL, \
                f"{name}: depth {i + 1} must measure the drop {d}, " \
                f"not {meas}"
            assert abs(at[0] - cu[i + 1][0] - pfo) < TOL, \
                f"{name}: depth {i + 1}'s dim line must stand {pfo} " \
                f"right of its corner along the UCS X, not " \
                f"{at[0] - cu[i + 1][0]}"
            assert rot is not None and abs(rot - vaxis) < TOL, \
                f"{name}: depth {i + 1} must be vertical in the UCS " \
                f"(group 50 {vaxis}), not {rot}"
        o1, o2, meas, at, rot = pd[-1]
        assert near(o1, cw[0]) and near(o2, cw[-1]), \
            f"{name}: the overall must bind the top and bottom corners"
        assert abs(meas - sum(DEPTHS)) < TOL, \
            f"{name}: the overall must measure {sum(DEPTHS)}, not {meas}"
        assert abs(at[0] - PICK[0] - (pfo + GAP)) < TOL, \
            f"{name}: the overall's dim line must stand {pfo + GAP} " \
            f"right of the pick along the UCS X, not {at[0] - PICK[0]}"
        assert rot is not None and abs(rot - vaxis) < TOL, \
            f"{name}: the overall must be vertical in the UCS"


# ---------------------------------------------------------------------
# LISPLAB's demo
# ---------------------------------------------------------------------

class _LabTour(VM):
    """Answers LISPLAB's questions by what they ask: the lesson, the
    half, the demo spot, the size unit, a pause is Enter."""

    def __init__(self, point):
        super().__init__()
        self.point = point

    def pop_script(self, prompt, kind):
        if kind == 'getstring':
            ans = ''
        elif kind == 'getpoint':
            ans = self.point
        elif kind == 'getdist':
            ans = 5.0
        elif kind == 'getkword':
            ans = ('Database' if 'Which lesson' in prompt else
                   'Demo' if 'Checks prints' in prompt else
                   'Keep' if 'Keep the demo' in prompt else None)
            if ans is None:
                raise LispError(f"unscripted question: {prompt!r}", self)
        else:
            raise LispError(f"unscripted {kind}: {prompt!r}", self)
        self.script = [ans]
        return super().pop_script(prompt, kind)


def _lab_run(path, point):
    vm = _LabTour(point)
    vm.set_ucs(UCS_ORIGIN, UCS_TURN)
    vm.load(path)
    try:
        vm.run('c:LISPLAB', [])
    except LispError as e:
        raise AssertionError(f"[LISPLAB under a turned UCS] {e}") from None
    return vm


def check_lisplab_demo(path=LISPLAB):
    """The sample row is laid out from the World point of the pick:
    circle i at base + (132 * (i + 0.5), 0) at the 5.0 size unit (the
    step is 2.2 x the 12-unit max radius).  Enter is the UCS origin,
    as the prompt's 0,0 says, not World's."""
    for label, pick in (("a pick", [100.0, 50.0, 0.0]),
                        ("Enter", None)):
        vm = _lab_run(path, pick)
        base = world(vm, pick or [0.0, 0.0, 0.0])
        circ = [e for e in live(vm, 'CIRCLE')
                if dxf(vm, e, 8) in ('LISPLAB-A', 'LISPLAB-B')]
        assert len(circ) == 7, f"{label}: {len(circ)} sample circles"
        got = sorted(tuple(dxf(vm, e, 10)[:2]) for e in circ)
        want = [(base[0] + 132.0 * (i + 0.5), base[1]) for i in range(7)]
        assert all(near(g, w) for g, w in zip(got, want)), \
            f"{label}: the sample must sit at the pick's World point " \
            f"{base}; circles at {got[:2]}..."
        notes = [tuple(dxf(vm, e, 10)[:2]) for e in live(vm, 'TEXT')
                 if dxf(vm, e, 8) == 'LISPLAB-NOTES']
        assert notes and all(abs(n[1] - (base[1] - 1.4 * 60.0)) < TOL
                             for n in notes), \
            f"{label}: every label must sit under its circle, at World " \
            f"y {base[1] - 84.0}: {notes[:2]}..."


# ---------------------------------------------------------------------
# TUTORIALPADDLE's demo
# ---------------------------------------------------------------------

#: the demo perimeter paddle--demo-pline lays out from its base
DEMO_PTS = [(0, 0), (150, 3), (300, 0), (300, 168), (264, 168), (168, 168),
            (132, 168), (132, 120), (84, 120), (84, 168), (0, 168),
            (0, 134), (0, 34)]


def _paddle_run(path, pick, ucs=True):
    vm = VM()
    # World is set, not assumed: a LISPVM_UCS sweep leaves a VM alone
    # only when its test chose the UCS itself
    if ucs:
        vm.set_ucs(UCS_ORIGIN, UCS_TURN)
    else:
        vm.set_ucs()
    vm.load(path)
    # the tour: pause, demo? Yes, the spot, four pauses, erase? No
    try:
        vm.run('c:TUTORIALPADDLE', [None, None, pick, None, None, None,
                                    None, None])
    except LispError as e:
        raise AssertionError(f"[TUTORIALPADDLE] {e}") from None
    return vm


def _demo_pline(vm):
    pl = [e for e in live(vm, 'LWPOLYLINE')
          if dxf(vm, e, 8) == 'PADDLE-DEMO']
    assert len(pl) == 1, f"{len(pl)} demo perimeters"
    return [tuple(g[1:3]) for g in vm.entdata[pl[0]]
            if isinstance(g, list) and g and g[0] == 10]


def _pads(vm):
    return sorted((round(dxf(vm, e, 10)[0], 4), round(dxf(vm, e, 10)[1], 4))
                  for e in live(vm, 'INSERT'))


def check_paddle_demo(path=PADDLE):
    """The sample perimeter is built from the World point of the pick,
    its pads land where they land on a World run shifted by the same
    amount, the ZOOM window holds the whole perimeter as the screen
    shows it, and Enter builds at the UCS origin."""
    ref = _paddle_run(path, None, ucs=False)
    ref_pads = _pads(ref)
    assert len(ref_pads) == 5, f"World run padded {len(ref_pads)}"
    for label, pick in (("a pick", [100.0, 50.0, 0.0]),
                        ("Enter", None)):
        vm = _paddle_run(path, pick)
        base = world(vm, pick or [0.0, 0.0, 0.0])
        verts = _demo_pline(vm)
        want = [(base[0] + x, base[1] + y) for x, y in DEMO_PTS]
        assert all(near(v, w) for v, w in zip(verts, want)) \
            and len(verts) == len(want), \
            f"{label}: the perimeter must start at the pick's World " \
            f"point {base}, not {verts[0]}"
        pads = _pads(vm)
        shifted = sorted((round(x + base[0], 4), round(y + base[1], 4))
                         for x, y in ref_pads)
        assert len(pads) == len(shifted) and \
            all(near(p, s, 1e-3) for p, s in zip(pads, shifted)), \
            f"{label}: the pads must sit on the demo's features: " \
            f"{pads} vs {shifted}"
        zooms = [c for c in vm.commands
                 if c and str(c[0]).upper().lstrip('_.') == 'ZOOM']
        assert zooms, f"{label}: no ZOOM"
        lo, hi = zooms[-1][2], zooms[-1][3]
        # the VM's display is plan to the UCS, so the screen box is the
        # UCS box: every vertex, in UCS numbers, inside the window
        for v in verts:
            u = vm.wcs_to_ucs([v[0], v[1], 0.0])
            assert lo[0] - TOL <= u[0] <= hi[0] + TOL \
                and lo[1] - TOL <= u[1] <= hi[1] + TOL, \
                f"{label}: the ZOOM window {lo}-{hi} cuts off the " \
                f"perimeter at UCS {u[:2]}"


def main():
    check_step_profile()
    print("  ok   the step profiles are built in the UCS and every depth"
          " dim measures its drop")
    check_lisplab_demo()
    print("  ok   LISPLAB's demo is drawn at the pick, and Enter is the"
          " UCS origin")
    check_paddle_demo()
    print("  ok   TUTORIALPADDLE's demo is built and framed at the pick,"
          " and Enter is the UCS origin")
    print("\nall ucsfix misc checks passed")


if __name__ == "__main__":
    main()
