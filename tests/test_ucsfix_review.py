#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The review tools' tutorial demos under a moved and turned UCS.

TUTORIALCOVERCHECK, TUTORIALDIMCHECK and TUTORIALLINFINCHECK each build
a practice drawing square to World and then dimension it with
DIMLINEAR.  A click answers in the current UCS, entmake writes World,
and a (command ...) reads its points in the UCS again -- three frames
the demos mixed:

  * TUTORIALCOVERCHECK handed its base click, UCS numbers, raw to a
    builder that entmakes it as World.  Under a UCS moved onto a pool
    corner the scene landed a UCS origin away from the spot the drafter
    picked, and COVERSCAN placed its suggested pad at (-84'-0", 11'-7")
    instead of (9'-0", 6'-0").  Its one DIMLINEAR was handed the World
    numbers raw, which the command reads as UCS.
  * DIMCHECK's and LINFINCHECK's tut-dim took their origin to World
    correctly, but handed the World points raw to DIMLINEAR: the
    practice dimensions landed 1000,500 off the line they were planted
    to check.
  * Under a TURNED UCS a DIMLINEAR -- _H, _V or unforced -- measures
    along the UCS axes, so a World-square demo was dimensioned on the
    slant.  Each file now has a <pfx>:world-rot that spells DIMLINEAR's
    Rotated angle along World X or Y, and only when the UCS is turned:
    in World (and under a UCS that is only moved) the command is the
    plain one it always was, because a typed angle is read through
    ANGBASE, ANGDIR and AUNITS and the plain form is not.

Each scenario sets its own UCS with vm.set_ucs, so the LISPVM_UCS sweep
leaves it alone, and reads back what the drawing holds: World numbers.

Run: python3 tests/test_ucsfix_review.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
# lispvm's _remap_root sends these to shared/parts/ when
# CALOFIN_LISP_ROOT=shared
LISP = os.path.join(HERE, '..', 'lisp')
PATHS = {
    'COVERCHECK': os.path.join(LISP, 'covercheck', 'covercheck.lsp'),
    'DIMCHECK': os.path.join(LISP, 'dimcheck', 'dimcheck.lsp'),
    'LINFINCHECK': os.path.join(LISP, 'linfincheck', 'linfincheck.lsp'),
}
TUTORIAL = {'DIMCHECK': 'c:TUTORIALDIMCHECK',
            'LINFINCHECK': 'c:TUTORIALLINFINCHECK'}
PFX = {'COVERCHECK': 'cchk', 'DIMCHECK': 'dchk', 'LINFINCHECK': 'lfc'}
#: the Enter answers the Demo branch takes after its spot, the erase
#: question last (test_tutorials.py's counts)
FAULTS = {'DIMCHECK': 8, 'LINFINCHECK': 9}

ORIGIN = (1000.0, 500.0, 0.0)
UCSES = [('moved to 1000,500', ORIGIN, 0.0),
         ('moved and turned 30', ORIGIN, math.radians(30.0))]
TWO_PI = 2.0 * math.pi

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   " + label)
    else:
        print("  FAIL " + label
              + (('  -- ' + str(detail)[:700]) if detail else ''))
        FAILS.append(label)


def load(tool):
    vm = VM()
    vm.load(PATHS[tool])
    vm.printed = []
    return vm


def live(vm):
    return [e for e in vm.entities if e not in vm.deleted]


def grp(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return [float(v) for v in g[1:]]
    return None


def grps(vm, e, code):
    return [[float(v) for v in g[1:]] for g in vm.entdata.get(e, [])
            if isinstance(g, list) and g and g[0] == code]


def near(p, q, tol=1e-6):
    return p is not None and all(abs(a - b) <= tol for a, b in zip(p, q))


def same_angle(a, b, tol=1e-6):
    if a is None:
        return False
    d = (a - b) % TWO_PI
    return min(d, TWO_PI - d) <= tol


def dims(vm):
    return [e for e in live(vm) if grp(vm, e, 0) == 'DIMENSION']


def dimlinears(vm):
    return [c for c in vm.commands if c and c[0] == '_.DIMLINEAR']


def run(vm, cmd, script):
    try:
        vm.run(cmd, script)
    except LispError as e:
        if 'scripted answers left over' not in str(e):
            check(f"{cmd} ran to its end", False, e)


def the_dim(vm, want, label):
    """WANT is (p13, p14, measurement, axis angle) in World numbers:
    one of the demo's dimensions has to be exactly that."""
    p13, p14, meas, axis = want
    got = [(grp(vm, e, 13), grp(vm, e, 14), grp(vm, e, 42), grp(vm, e, 50))
           for e in dims(vm)]
    hit = [g for g in got
           if near(g[0], p13) and near(g[1], p14)
           and g[2] is not None and abs(g[2] - meas) < 1e-6
           and same_angle(g[3], axis)]
    check(label, hit, got)


# ==================================================================
#  1. TUTORIALCOVERCHECK: the base click, and the demo dimension
# ==================================================================

def covercheck_scene(how, origin, turn):
    print(f"== TUTORIALCOVERCHECK under a UCS {how}: the scene is where "
          "the drafter clicked ==")
    vm = load('COVERCHECK')
    vm.set_ucs(origin, turn)
    # the drafter clicks the spot that is World 0,0 -- its UCS numbers
    # are what getpoint hands back
    run(vm, 'c:TUTORIALCOVERCHECK', [None, vm.wcs_to_ucs([0.0, 0.0, 0.0])])
    outline = [e for e in live(vm)
               if grp(vm, e, 0) == 'LWPOLYLINE' and vm.layer_of(e) == 'POOL'
               and grp(vm, e, 6) is None]
    verts = grps(vm, outline[0], 10) if outline else []
    check("the pool outline starts on the World spot clicked (0,0)",
          verts and near(verts[0][:2], (0.0, 0.0)), verts[:2])
    # point 1 sits 4" under the corner, point 2 on the far corner, and
    # the run between them is 180" along World X
    the_dim(vm, ([0.0, -4.0, 0.0], [180.0, 0.0, 0.0], 180.0, 0.0),
            "the demo dimension is on the pool and measures its 180\" "
            "run along World X")

    # and the drafter-visible end of it: COVERSCAN over the scene
    vm.sysvars.update({'LUNITS': 4, 'LUPREC': 4, 'DIMZIN': 0})
    sel = [e for e in live(vm) if grp(vm, e, 0) not in ('ATTRIB', 'SEQEND')]
    run(vm, 'c:COVERSCAN', [None, sel])
    txt = '\n'.join(''.join(str(g.b) for g in vm.entdata[e]
                            if isinstance(g, Dot) and g.a in (3, 1))
                    for e in live(vm)
                    if grp(vm, e, 0) == 'MTEXT'
                    and vm.layer_of(e) == 'COVERCHECK-REPORT')
    check("COVERSCAN places the suggested pad at (9'-0\", 6'-0\")",
          'Pad SUGGESTED at (9\'-0", 6\'-0")' in txt, txt[-600:])
    check("...and reads the demo dimension as 15'-0\"",
          '= 15\'-0":' in txt, txt[-600:])


# ==================================================================
#  2. DIMCHECK / LINFINCHECK: the practice dimensions
# ==================================================================

SPOT = [500.0, 0.0, 0.0]

#: (p13, p14, measurement, axis) of every practice dimension, in World
#: numbers, for a practice drawing at SPOT
WANT = {
    'DIMCHECK': [([500.0, 80.0, 0.0], [620.0, 88.0, 0.0], 120.0, 0.0)],
    'LINFINCHECK': [([500.0, 80.0, 0.0], [620.0, 88.0, 0.0], 120.0, 0.0),
                    ([500.0, 160.0, 0.0], [536.0, 200.0, 0.0], 40.0,
                     0.5 * math.pi)],
}


def demo(tool, vm):
    """Run the Demo branch with the drafter clicking World SPOT, and
    keep the practice drawing (No at the erase)."""
    click = vm.wcs_to_ucs(SPOT)
    run(vm, TUTORIAL[tool],
        ["Demo", click] + [None] * (FAULTS[tool] - 1) + ["No"])


def practice_dims(tool, how, origin, turn):
    print(f"== {TUTORIAL[tool][2:]} under a UCS {how}: the practice "
          "dimensions sit on their lines ==")
    vm = load(tool)
    vm.set_ucs(origin, turn)
    demo(tool, vm)
    for want in WANT[tool]:
        kind = 'vertical' if want[3] else 'horizontal'
        the_dim(vm, want,
                f"the {kind} practice dimension is on its geometry and "
                f"measures {want[2]:g} along World")
    out = ''.join(vm.printed)
    check("the scan still reports the planted stray point",
          'with a stray point' in out, out[-400:])


# ==================================================================
#  3. World: the command a drafter's settings cannot turn is kept
# ==================================================================

def world_keeps_plain_form():
    print("== World, ANGBASE 90: no Rotated angle is typed, the plain "
          "command is kept ==")
    # a typed angle is read from ANGBASE; _H, _V and an unforced
    # DIMLINEAR are not.  In World the demo dims are already square, so
    # typing "_R 0" would only hand a surveyor's template the chance to
    # turn them a quarter
    for tool in ('COVERCHECK', 'DIMCHECK', 'LINFINCHECK'):
        vm = load(tool)
        vm.set_ucs()
        vm.sysvars.update({'ANGBASE': 0.5 * math.pi, 'ANGDIR': 1})
        if tool == 'COVERCHECK':
            run(vm, 'c:TUTORIALCOVERCHECK', [None, [0.0, 0.0, 0.0]])
        else:
            demo(tool, vm)
        cmds = dimlinears(vm)
        check(f"{tool}: its demo DIMLINEAR(s) type no Rotated angle",
              cmds and not any('_R' in c for c in cmds), cmds)
        if tool != 'COVERCHECK':
            check(f"{tool}: ...and force _H / _V as before",
                  all(('_H' in c) or ('_V' in c) for c in cmds), cmds)
        for want in (WANT.get(tool) or
                     [([0.0, -4.0, 0.0], [180.0, 0.0, 0.0], 180.0, 0.0)]):
            the_dim(vm, want, f"{tool}: the dimension is where it was")


# ==================================================================
#  4. the Rotated angle is typed in the drafter's own settings
# ==================================================================

def typed_angle():
    print("== a turned UCS: the Rotated angle reads back through ANGBASE, "
          "ANGDIR and AUNITS ==")
    # World X, seen from a UCS turned 30 degrees, points at 330.  The
    # command reads a typed angle from ANGBASE, in ANGDIR's sense and in
    # AUNITS, so that is what the text has to be spelt in.  (The VM's
    # DIMLINEAR reads the text as degrees from 0 -- these check the
    # spelling; sections 1 and 2 check what the drawing gets.)
    cases = [({'ANGBASE': 0.0, 'ANGDIR': 0, 'AUNITS': 0}, '330.00000000'),
             ({'ANGBASE': 0.5 * math.pi, 'ANGDIR': 0, 'AUNITS': 0},
              '240.00000000'),
             ({'ANGBASE': 0.5 * math.pi, 'ANGDIR': 1, 'AUNITS': 0},
              '120.00000000'),
             ({'ANGBASE': 0.0, 'ANGDIR': 0, 'AUNITS': 3}, '5.75958653r')]
    for tool in ('COVERCHECK', 'DIMCHECK', 'LINFINCHECK'):
        for sv, want in cases:
            vm = load(tool)
            vm.set_ucs(ORIGIN, math.radians(30.0))
            vm.sysvars.update(sv)
            if tool == 'COVERCHECK':
                run(vm, 'c:TUTORIALCOVERCHECK',
                    [None, vm.wcs_to_ucs([0.0, 0.0, 0.0])])
            else:
                demo(tool, vm)
            cmds = dimlinears(vm)
            typed = [c[c.index('_R') + 1] for c in cmds if '_R' in c]
            # the first dim is compared: LINFINCHECK's second runs along
            # World Y and types 90 more
            ok = bool(cmds) and len(typed) == len(cmds) and typed[0] == want
            check(f"{tool}: ANGBASE {math.degrees(sv['ANGBASE']):g}, "
                  f"ANGDIR {sv['ANGDIR']}, AUNITS {sv['AUNITS']} -> "
                  f"_R {want}", ok, typed)


for how, origin, turn in UCSES:
    covercheck_scene(how, origin, turn)
    for tool in ('DIMCHECK', 'LINFINCHECK'):
        practice_dims(tool, how, origin, turn)
def world_rot_copies_agree():
    """The three tools each carry world-rot under their own prefix, with
    no library twin to swap to -- so nothing but this keeps a fix to
    one copy from leaving the other two behind, the drift the ink
    copies had until test_theme pinned them."""
    import re
    bodies = {}
    for tool, pfx in PFX.items():
        src = open(PATHS[tool]).read()
        m = re.search(r"\(defun %s:world-rot .*?\n\n" % pfx, src, re.S)
        bodies[tool] = (m.group(0).replace(pfx + ":", "X:") if m else None)
    texts = set(bodies.values())
    check("the three world-rot copies are one text under three prefixes",
          None not in texts and len(texts) == 1,
          {t: (b or "")[:60] for t, b in bodies.items()})


world_keeps_plain_form()
typed_angle()
world_rot_copies_agree()

if FAILS:
    print(f"\ntest_ucsfix_review: {len(FAILS)} FAILURE(S): "
          + '; '.join(FAILS))
    sys.exit(1)
print("\ntest_ucsfix_review: all checks passed")
