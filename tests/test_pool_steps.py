"""POOL's steps at the shallow end.

With a hopper, POOL hands the shallow wall to HEMISTEP, NORMIESTEP or
CORNERSTP through *calofin-handoff*, once its own run is closed; when
NORMIESTEP's steps face into the pool the E dim moves down near the
bottom wall in SIDE STANDARD and a new dim runs from the slope break to
the first step.  With no hopper, a box step goes OUTSIDE the wall, the
wall is broken round it, it is dimensioned, and PADDLE pads the new
perimeter.

Both tiers: CALOFIN_LISP_ROOT=shared runs the grouped twins on the
library.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
LIB = os.path.join(HERE, '..', 'shared', 'parts', 'CALOFIN-LIB.lsp')


def src(folder, name):
    if ROOT == 'shared':
        return os.path.join(HERE, '..', 'shared', 'parts',
                            name.replace('.LSP', '.lsp'))
    return os.path.join(HERE, '..', 'lisp', folder, name)


POOL = src('pool', 'POOL.LSP')
NORMIE = src('cornerstp', 'NORMIESTEP.lsp')
HEMI = src('cornerstp', 'HEMISTEP.lsp')
CORNER = src('cornerstp', 'CORNERSTP.lsp')
PADDLE = src('paddle', 'PADDLE.lsp')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   " + label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


def fresh(*files):
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
    for f in (POOL,) + files:
        vm.load(f)
    vm.tables['DIMSTYLE'].add('SIDE STANDARD')
    vm.printed = []
    return vm


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1:]
    return None


def live(vm, kind, layer=None):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata[e]
        if grp(d, 0) == kind and (layer is None or grp(d, 8) == layer):
            out.append(e)
    return out


def seg(vm, e):
    d = vm.entdata[e]
    return tuple(grp(d, 10)[:2]), tuple(grp(d, 11)[:2])


def has_line(vm, a, b, layer='POOL', tol=0.01):
    for e in live(vm, 'LINE', layer):
        p, q = seg(vm, e)
        if (math.dist(p, a) < tol and math.dist(q, b) < tol) or \
           (math.dist(p, b) < tol and math.dist(q, a) < tol):
            return True
    return False


def dimcmds(vm):
    return [c for c in vm.commands
            if c and c[0] in ('_.DIMLINEAR', '_.DIMALIGNED')]


def pts(c):
    return [tuple(x[:2]) for x in c if isinstance(x, list)]


def asked(vm, text):
    return [p for p, _ in vm.prompts if p and text in p]


def said(vm):
    return ''.join(vm.printed)


# A 40' x 20' rectangle, in square, square corners, the standard hopper
# H 60 G 90 F 240 E 90: the shallow wall is x = 480, the slope break is
# x = 390, and the H/G/F/E chain line sits at y = 108.
HOPPER = (["Insquare", "Rectangle", (0.0, 0.0, 0.0), 480.0, 240.0,
           "Square", "Yes", "Normal",
           60.0, 90.0, 240.0, 90.0, 60.0, 120.0, 60.0])
NOBOTTOM = (["Insquare", "Rectangle", (0.0, 0.0, 0.0), 480.0, 240.0,
             "Square", "No"])
# NORMIESTEP after the hand-over: the side, width, corners, dims?, two
# 24" treads, done, no profile (AUTOBEAD is not loaded, so no bead)
NORMIE_IN = [(400.0, 120.0, 0.0), 200.0, "Square", "No", 24.0, 24.0,
             None, "No"]


print("== S1. Normie into the pool: the wall is handed over, the dims move ==")
vm = fresh(NORMIE)
vm.run('c:POOL', HOPPER + ["Normie"] + NORMIE_IN)
check("NORMIESTEP never asked for its selection",
      not asked(vm, 'Select the base line'))
check("...it was handed the wall and asked the side", asked(vm, 'side the steps go'))
check("the treads are drawn into the pool from the shallow wall",
      has_line(vm, (432.0, 20.0), (432.0, 220.0), layer=None))
ds = dimcmds(vm)
moved = [c for c in ds if [round(v, 6) for p in pts(c)[:2] for v in p]
         == [390.0, 12.0, 480.0, 12.0]]
check("E is redrawn 12\" in from the bottom wall, break to wall", len(moved) == 1,
      repr([pts(c) for c in ds[-3:]]))
_i = vm.commands.index(moved[0]) if moved else 0
check("...in SIDE STANDARD",
      vm.commands[_i - 1] == ['_.-DIMSTYLE', '_Restore', 'SIDE STANDARD'],
      repr(vm.commands[_i - 1]))
new = [c for c in ds if [round(v, 6) for p in pts(c)[:2] for v in p]
       == [390.0, 108.0, 432.0, 108.0]]
check("a new dim runs from the break to the first step, on the chain line",
      len(new) == 1)
edims = [e for e in vm.entities if grp(vm.entdata[e], 0) == 'DIMENSION']
check("the old E dim was erased", any(e in vm.deleted for e in edims))
check("nothing of the hand-over is left standing",
      not vm.globals.get('*calofin-handoff*'))

print("== S2. Normie facing OUT of the pool: the dims stay put ==")
vm = fresh(NORMIE)
vm.run('c:POOL', HOPPER + ["Normie", (520.0, 120.0, 0.0), 200.0, "Square",
                           "No", 24.0, None, "No"])
check("no E moved, no break-to-step dim",
      not any(pts(c)[:2] and pts(c)[0][1] == 12.0 for c in dimcmds(vm)))
check("...and it says why", 'No steps into the pool' in said(vm))

print("== S3. Hemi takes the same hand-over ==")
vm = fresh(HEMI)
vm.run('c:POOL', HOPPER + ["Hemi", (400.0, 120.0, 0.0), "No", 200.0,
                           24.0, 200.0, None, None, "No"])
check("HEMISTEP never asked for its selection",
      not asked(vm, 'Select the base line'))
check("...and ran on the wall", 'Handing the shallow end to HEMISTEP' in said(vm))

print("== S4. Corner: the corner asked for is the one handed over ==")
# CORNERSTP runs its bisector into the pool from the corner it was
# handed: 225 degrees from the top-right, 135 from the bottom-right
for treat, extra, which, corner in (("Square", [], "Top", 'direction 225'),
                                    ("Square", [], "Bottom", 'direction 135'),
                                    ("Radius", [24.0], "Top", None)):
    vm = fresh(CORNER)
    script = (HOPPER[:5] + [treat] + extra + HOPPER[6:]
              + ["Corner", "Back", "Corner", which])
    try:
        vm.run('c:POOL', script + [None] * 30)
    except LispError as e:
        # CORNERSTP asks more than the None-run needs to answer; what
        # matters is what it was handed
        if 'left over' not in str(e):
            check("%s %s corner runs" % (treat, which), False, str(e)[:200])
    check("%s/%s: CORNERSTP never asked for its walls" % (treat, which),
          not asked(vm, 'Select the two walls'))
    if corner:
        check("%s/%s: it measures from that corner" % (treat, which),
              corner in said(vm), said(vm)[-300:])
    else:
        check("%s/%s: the fillet came with the walls" % (treat, which),
              asked(vm, 'middle of the diagonal'))

print("== S5. a routine that is not loaded is said, and the pool stands ==")
vm = fresh()
vm.run('c:POOL', HOPPER + ["Normie"])
check("NORMIESTEP not loaded is said", 'NORMIESTEP is not loaded' in said(vm))

print("== S6. Enter declines, and asks nothing more ==")
vm = fresh(NORMIE)
vm.run('c:POOL', HOPPER + [None])
check("no steps, no hand-over", 'Handing' not in said(vm))

print("== S7. no bottom: a box step outside the wall, PADDLE after ==")
vm = fresh(PADDLE)
vm.run('c:POOL', NOBOTTOM + ["Yes", None, "Custom", 300.0, 96.0, "Back", 96.0, 36.0,
                                None])       # Center
check("a width wider than the wall is refused",
      'wider than the straight wall' in said(vm))
check("Back from the length re-asks the width",
      len(asked(vm, 'Step width')) == 3, repr(len(asked(vm, 'Step width'))))
check("the wall is broken round the step",
      has_line(vm, (480.0, 0.0), (480.0, 72.0)) and
      has_line(vm, (480.0, 168.0), (480.0, 240.0)) and
      not has_line(vm, (480.0, 0.0), (480.0, 240.0)))
check("the step's three sides are the perimeter now",
      has_line(vm, (480.0, 72.0), (516.0, 72.0)) and
      has_line(vm, (516.0, 72.0), (516.0, 168.0)) and
      has_line(vm, (516.0, 168.0), (480.0, 168.0)))
ds = [sorted(pts(c)[:2]) for c in dimcmds(vm)]
check("its width is dimensioned", [(516.0, 72.0), (516.0, 168.0)] in
      [[tuple(round(v, 6) for v in p) for p in d] for d in ds])
check("...and its length", [(480.0, 168.0), (516.0, 168.0)] in
      [[tuple(round(v, 6) for v in p) for p in d] for d in ds])
pads = sorted(tuple(round(v, 3) for v in grp(vm.entdata[e], 10)[:2])
              for e in live(vm, 'INSERT'))
check("PADDLE padded the step's two inside corners",
      pads == [(480.0, 72.0), (480.0, 168.0)], repr(pads))

print("== S8. no bottom: a full-width step takes the whole wall ==")
vm = fresh()
vm.run('c:POOL', NOBOTTOM + ["Yes", None, "Custom", 240.0, 30.0, None])
check("the step's sides run on from the side walls",
      has_line(vm, (480.0, 0.0), (510.0, 0.0)) and
      has_line(vm, (510.0, 0.0), (510.0, 240.0)) and
      has_line(vm, (510.0, 240.0), (480.0, 240.0)))
check("no stub of wall is left", not any(
    math.dist(*seg(vm, e)) < 0.02 for e in live(vm, 'LINE', 'POOL')))
check("PADDLE not loaded is said", 'PADDLE is not loaded' in said(vm))

print("== S8b. no bottom: the 4x6 and 4x8 sizes, 4x6 on Enter ==")
for answer, wide in ((None, 72.0), ("4x8", 96.0)):
    vm = fresh()
    vm.run('c:POOL', NOBOTTOM + ["Yes", None, answer, None])
    lo, hi = 120.0 - wide / 2, 120.0 + wide / 2
    check("%s: a step 4' out by %d\" along the wall" % (answer or "Enter", wide),
          has_line(vm, (528.0, lo), (528.0, hi)) and
          has_line(vm, (480.0, lo), (528.0, lo)), repr(
              [seg(vm, e) for e in live(vm, 'LINE', 'POOL')]))
    check("%s: no lengths asked" % (answer or "Enter"),
          not asked(vm, 'Step width') and not asked(vm, 'Step length'))
vm = fresh()
vm.run('c:POOL', ["Insquare", "Rectangle", (0.0, 0.0, 0.0), 480.0, 84.0,
                  "Square", "No", "Yes", None, "4x8", "4x6", None])
check("a size wider than the wall is refused and asked again",
      'A 4x8 step is wider' in said(vm) and len(asked(vm, 'Step size')) == 2)
vm = fresh()
vm.run('c:POOL', NOBOTTOM + ["Yes", "Back", "Yes", None, "Back", None,
                            "Custom", "Back", "4x6", None])
check("Back walks wall -> the yes/no, size -> wall, and width -> size",
      len(asked(vm, 'Add a step outside')) == 2
      and len(asked(vm, 'Pick the wall the step goes on')) == 3
      and len(asked(vm, 'Step size')) == 3)

print("== S9. a form run says nothing about steps: nothing is asked ==")
vm = fresh()
vm.loads('(setq pool:*form* (list (cons (quote insq) "Insquare")'
         ' (cons (quote shape) "Rectangle")))')
vm.run('c:POOL', [(0.0, 0.0, 0.0), 480.0, 240.0, "Square", "No"])
check("the step question is never put", not asked(vm, 'shallow end'))
vm = fresh()
vm.loads('(setq pool:*form* (list (cons (quote insq) "Insquare")'
         ' (cons (quote shape) "Rectangle") (cons (quote extstep) "Yes")'
         ' (cons (quote extwidth) 96.0) (cons (quote extlen) 36.0)))')
vm.run('c:POOL', [(0.0, 0.0, 0.0), 480.0, 240.0, "Square", "No"])
check("...and a form that carries the step draws it unasked",
      has_line(vm, (516.0, 72.0), (516.0, 168.0))
      and not asked(vm, 'shallow end'))

print("== S11. FG steps: placed where picked, Back takes one back ==")
vm = fresh()
vm.run('c:POOL', HOPPER + [
    "FGstep",
    "4x6", "Pick", (480.0, 120.0, 0.0), None,                  # Enter: square, inward
    "4x8", "Pick", (480.0, 40.0, 0.0), (400.0, 40.0, 0.0),     # picked direction
    "Back",                                            # ...taken back up
    "4x8", "Pick", "Back",                                     # Back at the point
    "Text", (400.0, 120.0, 0.0),
    "Done"])
ins = [e for e in live(vm, 'INSERT')]
check("one FG step block stands", len(ins) == 1, repr(len(ins)))
d = vm.entdata[ins[0]] if ins else []
check("it is the shop's 4x6 block, on the POOL layer",
      grp(d, 2) == "6' Straight FG Step" and grp(d, 8) == 'POOL')
check("at the picked point, turned to run into the pool",
      tuple(grp(d, 10)[:2]) == (480.0, 120.0)
      and abs(grp(d, 50) - math.pi) < 1e-9, repr((grp(d, 10), grp(d, 50))))
check("the 4x8 taken back is gone",
      not any(grp(vm.entdata[e], 2) == "8' Straight FG Step"
              for e in live(vm, 'INSERT')))
check("a missing block is made: a U 4' deep, open on the wall side",
      vm.loads('(tblsearch "BLOCK" "6\' Straight FG Step")') is not None)
mt = [e for e in live(vm, 'MTEXT', 'FiberglassStep')]
check("the label is on FiberglassStep, where it was picked",
      len(mt) == 1 and tuple(grp(vm.entdata[mt[0]], 10)[:2]) == (400.0, 120.0))
check("...and reads Fiberglass Step",
      mt and 'Fiberglass Step' in grp(vm.entdata[mt[0]], 1))
rec = vm.loads('(tblsearch "LAYER" "FGStep")') or []
check("the FGStep layer is made yellow and dashed",
      next((g.b for g in rec if isinstance(g, Dot) and g.a == 62), 0) == 2
      and next((g.b for g in rec if isinstance(g, Dot) and g.a == 6), '')
      != 'Continuous', repr(rec))
check("no step routine was handed anything", 'Handing' not in said(vm))
vm = fresh()
vm.run('c:POOL', HOPPER + ["FGstep", "Back", "None"])
check("Back at the first FG question re-asks the steps question",
      len(asked(vm, 'Add steps at the shallow end')) == 2)

print("== S12. Offset: a distance from a point picked on the wall ==")
vm = fresh()
# 4x6 (72 wide), 24" from the bottom corner (480, 0): the step runs
# 24..96 up the wall
vm.run('c:POOL', NOBOTTOM + ["Yes", None, None, "Offset", (480.0, 0.0, 0.0), 24.0])
check("the near side is 24\" from the picked point",
      has_line(vm, (480.0, 24.0), (528.0, 24.0))
      and has_line(vm, (480.0, 96.0), (528.0, 96.0)))
check("...and the wall runs on either side of it",
      has_line(vm, (480.0, 0.0), (480.0, 24.0))
      and has_line(vm, (480.0, 96.0), (480.0, 240.0)))
vm = fresh()
# from the TOP corner the step runs down, toward the middle
vm.run('c:POOL', NOBOTTOM + ["Yes", None, None, "Offset", (480.0, 240.0, 0.0), 12.0])
check("from the far end it runs back toward the middle",
      has_line(vm, (480.0, 228.0), (528.0, 228.0))
      and has_line(vm, (480.0, 156.0), (528.0, 156.0)))
vm = fresh()
vm.run('c:POOL', NOBOTTOM + ["Yes", None, None, "Offset", (480.0, 0.0, 0.0), 200.0,
                            "Center"])
check("an offset that runs it off the wall is refused",
      'past the end of the wall' in said(vm)
      and has_line(vm, (480.0, 84.0), (528.0, 84.0)))

print("== S12b. the step goes on the wall the drafter picks ==")
vm = fresh()
# the bottom wall, y = 0: picked near its left third, 4x8, offset 36"
# from the left corner (0, 0) -- the step runs 36..132 and OUT, to y -48
vm.run('c:POOL', NOBOTTOM + ["Yes", (150.0, 2.0, 0.0), "4x8",
                            "Offset", (0.0, 0.0, 0.0), 36.0])
check("it is let into the picked wall, running out of the pool",
      has_line(vm, (36.0, 0.0), (36.0, -48.0))
      and has_line(vm, (36.0, -48.0), (132.0, -48.0))
      and has_line(vm, (132.0, -48.0), (132.0, 0.0)), repr(
          [seg(vm, e) for e in live(vm, 'LINE', 'POOL')]))
check("...and the shallow wall is left whole",
      has_line(vm, (480.0, 0.0), (480.0, 240.0)))
check("the offset asks for the point being offset from",
      asked(vm, 'Pick the point on the wall you are offsetting from'))

print("== S13. an FG block placed on the wall, centered or offset ==")
vm = fresh()
vm.run('c:POOL', HOPPER + ["FGstep", "4x8", None, None,
                           "4x6", "Wall", "Offset", (480.0, 0.0, 0.0), 12.0,
                           "Done"])
ins = sorted((tuple(round(v, 6) for v in grp(vm.entdata[e], 10)[:2]),
              grp(vm.entdata[e], 2)) for e in live(vm, 'INSERT'))
check("Center puts the 4x8 on the wall's middle, the 4x6 12\" off the corner",
      ins == [((480.0, 48.0), "6' Straight FG Step"),
              ((480.0, 120.0), "8' Straight FG Step")], repr(ins))
check("...both turned into the pool",
      all(abs(grp(vm.entdata[e], 50) - math.pi) < 1e-9
          for e in live(vm, 'INSERT')))

print("== S14. the report moves right, clear of a step outside ==")
vm = fresh()
vm.run('c:POOL', NOBOTTOM + ["Yes", None, None, None])
mv = [c for c in vm.commands if c and c[0] == '_.MOVE']
check("the report and mini-model are moved", len(mv) == 1, repr(mv))
if mv:
    dx = mv[0][-1][0] - mv[0][-2][0]
    rep = [e for e in live(vm, 'TEXT', 'POOL-NOTES')]
    x0 = min(grp(vm.entdata[e], 10)[0] for e in rep)
    check("...right, by enough to clear the step's width dim",
          dx > 0 and x0 + dx > 528.0, repr((x0, dx)))
vm = fresh()
vm.run('c:POOL', NOBOTTOM + [None])
check("no step, no move", not any(c and c[0] == '_.MOVE' for c in vm.commands))

print("== S10. Esc inside the step routine: POOL has nothing open ==")


def esc(vm_):
    raise LispError('Function cancelled', vm_)


vm = fresh(NORMIE)
vm.handle_errors = True
os0 = vm.sysvars['OSMODE']
vm.run('c:POOL', HOPPER + ["Normie", esc])
check("the Esc went to NORMIESTEP's handler",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0])
check("OSMODE is the drafter's", vm.sysvars['OSMODE'] == os0)
check("no undo group left open", vm.undo_groups == 0, repr(vm.undo_groups))
check("the hand-over is gone", not vm.globals.get('*calofin-handoff*'))

if FAILS:
    print("test_pool_steps: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_pool_steps: all checks passed (%s tier)" % ROOT)
