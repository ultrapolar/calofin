"""Runtime tests for SQUAREUP: build a survey sitting off-square, run the
REAL command over it, and check the drawing came out straight.

The tool is a measurement and one ROTATE, so the measurement is what
these pin: which run of the perimeter is "the longest length", what the
smallest turn that puts it flat actually is, and that the whole of the
highlight went with it.  The VM turns the geometry for real (see
_rotate_ss in lispvm.py) rather than filing the call away, because a
tool whose entire job is the angle it hands ROTATE would otherwise pass
every test it has with the sign backwards.

Three answers this is really about:

  * a LONG SIDE A TRACE SPLIT IN FOUR is one wall.  A survey perimeter
    arrives as whatever the tracer clicked, so a "longest straight run"
    read off single segments would square a pool to a ten-foot fragment
    of its own forty-foot side;
  * THE SMALLEST TURN.  A wall at 176 degrees is put flat by turning 4.
    Turning 176 also puts it flat, and stands the drawing on its head;
  * ROTATE SKIPS AN OBJECT ON A LOCKED OR FROZEN LAYER and says nothing
    about it, so the run frees both bits and puts them back.  Half a
    drawing squared is worse than none: the second is obvious.

Then the shape every command in the build shares: an error mid-run and
an Esc at the selection prompt both reach the command's OWN *error*,
which puts the drafter's OSMODE and the layers it borrowed back and
closes the group it opened.

Script values answer the interactive calls in order: the pickfirst
probe, the highlight, the perimeter, then the Wall/Span keyword and any
confirmation.  A function-valued answer runs when its prompt is
reached, which is how the Esc is delivered.

Run: python3 tests/test_squareup.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_squareup.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
SQUAREUP = (os.path.join(HERE, '..', 'shared', 'parts', 'SQUAREUP.lsp')
            if ROOT == 'shared'
            else os.path.join(HERE, '..', 'lisp', 'squareup', 'SQUAREUP.lsp'))
LIB = os.path.join(HERE, '..', 'shared', 'parts', 'CALOFIN-LIB.lsp')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


# ----------------------------------------------------------------------
# the drawing
# ----------------------------------------------------------------------

LOCKED, FROZEN = 4, 1


def turn(p, deg, about=(0.0, 0.0)):
    a = math.radians(deg)
    dx, dy = p[0] - about[0], p[1] - about[1]
    return (about[0] + dx * math.cos(a) - dy * math.sin(a),
            about[1] + dx * math.sin(a) + dy * math.cos(a))


def layer(vm, name, flags=0):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
             ' \'(62 . 4) \'(6 . "Continuous")))' % (name, flags))


def line(vm, a, b, lay='POOL'):
    vm.loads('(entmake (list \'(0 . "LINE") (cons 8 "%s") (list 10 %r %r 0.0)'
             ' (list 11 %r %r 0.0)))' % (lay, a[0], a[1], b[0], b[1]))


def lwpoly(vm, pts, closed=1, bulges=None, lay='POOL'):
    gs = []
    for i, p in enumerate(pts):
        gs.append('(list 10 %r %r)' % (p[0], p[1]))
        if bulges and bulges[i]:
            gs.append('(cons 42 %r)' % bulges[i])
    vm.loads('(entmake (list \'(0 . "LWPOLYLINE") (cons 8 "%s") (cons 90 %d)'
             ' (cons 70 %d) %s))' % (lay, len(pts), closed, ' '.join(gs)))


def text(vm, p, rot=0.0, lay='TEXT'):
    vm.loads('(entmake (list \'(0 . "TEXT") (cons 8 "%s") (list 10 %r %r 0.0)'
             ' \'(40 . 2.0) \'(1 . "17") (cons 50 %r)))'
             % (lay, p[0], p[1], rot))


def fresh(base_flags=0):
    vm = VM()
    for name in ('POOL', 'TEXT', 'POINTS'):
        layer(vm, name)
    layer(vm, 'BASE', base_flags)
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(SQUAREUP)
    vm.printed = []
    return vm


def ents(vm):
    return [e for e in vm.entities if e not in vm.deleted]


def pts_of(vm, e):
    return [tuple(g[1:3]) for g in vm.entdata[e]
            if isinstance(g, list) and g[0] == 10]


def edge_angles(pts):
    """Every edge of a closed run, in degrees, folded into [0, 180) --
    with the fold done on a tolerance, because a leftward edge comes off
    atan2 a float's width short of pi and 179.999999 % 180 is not 0."""
    out = []
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        a = math.degrees(math.atan2(q[1] - p[1], q[0] - p[0])) % 180.0
        if a > 180.0 - 1e-6:
            a -= 180.0
        out.append(round(a, 6))
    return out


def square_p(pts):
    """T when every edge of a closed run lies along an axis."""
    return all(abs(a) < 1e-6 or abs(a - 90.0) < 1e-6 for a in edge_angles(pts))


def rotate_cmd(vm):
    """The one ROTATE the run issued, or None."""
    for c in vm.commands:
        if c and isinstance(c[0], str) and c[0].upper().lstrip('._') == 'ROTATE':
            return c
    return None


def said(vm, needle):
    return any(needle in s for s in vm.printed)


def layer_flags(vm, name):
    rec = vm.tablerecs['LAYER'][name.upper()]
    return grp(vm.recdata[rec], 70) or 0


def error_global(vm):
    """T when a function is left sitting in the GLOBAL *error*."""
    return vm.globals.get(Sym('*error*')) is not None


def tilted_pool(vm, deg=6.0, w=40.0, h=20.0):
    """A rectangle pool off-square by DEG, with a numbered point label
    beside it -- the two things a survey is made of."""
    lwpoly(vm, [turn(p, deg) for p in
                ((0.0, 0.0), (w, 0.0), (w, h), (0.0, h))])
    text(vm, turn((5.0, 5.0), deg), math.radians(deg))
    return ents(vm)


# ----------------------------------------------------------------------
# statics
# ----------------------------------------------------------------------
print("statics -- the handler is the command's own")
src = open(SQUAREUP, encoding='ascii').read()
check("no global *error* swap left",
      '-old-error*' not in src
      and re.search(r"\(setq\s+\*error\*", src) is None)
m = re.search(r"\(defun\s+[cC]:SQUAREUP\s*\(\s*/([^)]*)\)", src)
check("*error* is a local of the command",
      m is not None and '*error*' in m.group(1).split(), repr(m))
check("the handler closes only a group the run opened",
      "(if undo-open (vl-catch-all-apply 'command-s" in src)
check("the handler puts the borrowed layers back too",
      "(vl-catch-all-apply 'sq:restore-layers" in src)

print("statics -- it borrows only what it moves")
sysvars = re.search(r"\(setq sq:\*sysvars\* '\(([^)]*)\)", src).group(1).split()
sysvars = [v.strip('"') for v in sysvars]
check("OSMODE leads the sysvar list", sysvars[0] == 'OSMODE', repr(sysvars))
for v in sysvars:
    check("%s is written by the run, so it belongs in the list" % v,
          re.search(r'\(setvar "%s"' % v, src) is not None)

# ----------------------------------------------------------------------
# the turn
# ----------------------------------------------------------------------
print("squareup -- a pool six degrees off comes out straight")
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
check("the outline is axis-aligned afterwards",
      square_p(pts_of(vm, es[0])),
      repr(edge_angles(pts_of(vm, es[0]))))
check("it turned by exactly the angle it measured",
      abs(rotate_cmd(vm)[-1] + 6.0) < 1e-9, repr(rotate_cmd(vm)))
check("the label travelled with it", abs(math.degrees(
    grp(vm.entdata[es[1]], 50))) < 1e-9, repr(grp(vm.entdata[es[1]], 50)))
check("nothing was drawn and nothing was erased", len(ents(vm)) == 2)
check("it said which measurement it squared to",
      said(vm, "longest wall") and said(vm, "is horizontal"),
      repr(vm.printed))
check("the whole turn is one undo group",
      vm.undo_groups == 0 and len([c for c in vm.commands
                                   if c[0] == '_.UNDO']) == 2,
      repr(vm.commands))
check("the global *error* is untouched after the run", not error_global(vm))

print("squareup -- the turn is the SMALLEST one, not the first one found")
vm = fresh()
es = tilted_pool(vm, 176.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
check("a wall at 176 degrees turns 4, not 176",
      abs(rotate_cmd(vm)[-1] - 4.0) < 1e-9, repr(rotate_cmd(vm)))
check("and it is flat either way", square_p(pts_of(vm, es[0])),
      repr(edge_angles(pts_of(vm, es[0]))))

print("squareup -- it turns about the perimeter, which stays put")
vm = fresh()
es = tilted_pool(vm, 6.0)
before = pts_of(vm, es[0])
mid = ((min(p[0] for p in before) + max(p[0] for p in before)) / 2.0,
       (min(p[1] for p in before) + max(p[1] for p in before)) / 2.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
after = pts_of(vm, es[0])
mid2 = ((min(p[0] for p in after) + max(p[0] for p in after)) / 2.0,
        (min(p[1] for p in after) + max(p[1] for p in after)) / 2.0)
check("the base point is the middle of the perimeter's extents",
      math.dist(rotate_cmd(vm)[-2][:2], mid) < 1e-9,
      repr((rotate_cmd(vm)[-2], mid)))
check("so the pool is still where it was on screen",
      math.dist(mid, mid2) < 0.5, repr((mid, mid2)))

# ----------------------------------------------------------------------
# what counts as the longest run
# ----------------------------------------------------------------------
print("squareup -- a long side a trace split in four is ONE wall")
vm = fresh()
# 40 long, in four collinear pieces at 6 degrees; and one whole 30-long
# side at 50.  Read piece by piece the longest single segment would be
# the 30, and the pool would come out squared to the wrong side.
for i in range(4):
    line(vm, turn((i * 10.0, 0.0), 6.0), turn(((i + 1) * 10.0, 0.0), 6.0))
line(vm, (0.0, 0.0), turn((30.0, 0.0), 50.0))
es = ents(vm)
vm.run('c:SQUAREUP', [None, es, es, 'Wall'])
check("the four pieces measured as one 40-foot wall",
      said(vm, "the longest wall is 40.0000"), repr(vm.printed[:2]))
check("so the turn squares the long side, not the short one",
      abs(rotate_cmd(vm)[-1] + 6.0) < 1e-9, repr(rotate_cmd(vm)))

print("squareup -- a run that BOWS stops being one wall where it bends")
vm = fresh()
# ten 5-long pieces, each 3 degrees further round: touching end to end,
# but 27 degrees between the first and the last.  Nothing here is a
# 50-long wall, and the longest straight thing really is 5.
p = (0.0, 0.0)
for i in range(10):
    q = (p[0] + 5.0 * math.cos(math.radians(3.0 * i)),
         p[1] + 5.0 * math.sin(math.radians(3.0 * i)))
    line(vm, p, q)
    p = q
es = ents(vm)
vm.run('c:SQUAREUP', [None, es, es, 'Wall'])
check("the bow did not become one long wall",
      said(vm, "the longest wall is 5.0000"), repr(vm.printed[:2]))

print("squareup -- no straight run at all squares to the span, unasked")
vm = fresh()
lwpoly(vm, [turn(p, 20.0) for p in
            ((0.0, 0.0), (50.0, 0.0), (50.0, 20.0), (0.0, 20.0))],
       bulges=[0.6, 0.6, 0.6, 0.6])
es = ents(vm)
# no keyword answer in the script: a question with one answer is not put
vm.run('c:SQUAREUP', [None, es, es])
check("it said there was no wall to square to",
      said(vm, "no straight run"), repr(vm.printed[:2]))
check("and squared to the span instead",
      rotate_cmd(vm) is not None and said(vm, "longest span"),
      repr(vm.printed))
check("the prompt was never put", not any(
    'horizontal?' in p for p, _ in vm.prompts), repr(vm.prompts))

print("squareup -- Span can be chosen over Wall")
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Span'])
# the 40x20 rectangle's diagonal runs 26.565 degrees off its long side,
# so a pool 6 degrees out has its diagonal at 32.565 and turns back by it
check("the diagonal is what ends up horizontal",
      abs(rotate_cmd(vm)[-1] + 6.0 + math.degrees(math.atan2(20.0, 40.0)))
      < 1e-6, repr(rotate_cmd(vm)))
check("and the summary names the span", said(vm, "longest span"),
      repr(vm.printed[-2:]))

print("squareup -- a near tie between two walls is reported")
vm = fresh()
line(vm, (0.0, 0.0), turn((40.0, 0.0), 4.0))
line(vm, (0.0, 0.0), turn((39.6, 0.0), 50.0))
es = ents(vm)
vm.run('c:SQUAREUP', [None, es, es, 'Wall'])
check("it says squaring to one of them was a choice",
      said(vm, "a choice and not a measurement"), repr(vm.printed[:3]))
check("and it still took the longer one",
      abs(rotate_cmd(vm)[-1] + 4.0) < 1e-9, repr(rotate_cmd(vm)))

print("squareup -- a rectangle's two long sides are not a tie worth saying")
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
check("nothing is said about the opposite wall",
      not said(vm, "a choice and not a measurement"), repr(vm.printed[:3]))

# ----------------------------------------------------------------------
# the runs that change nothing
# ----------------------------------------------------------------------
print("squareup -- a drawing already square is left alone")
vm = fresh()
es = tilted_pool(vm, 0.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
check("no ROTATE was issued at all", rotate_cmd(vm) is None,
      repr(vm.commands))
check("and it said why", said(vm, "already horizontal"), repr(vm.printed))
check("the outline is untouched", square_p(pts_of(vm, es[0])))

print("squareup -- no perimeter picked turns nothing")
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, es, None])
check("nothing turned", rotate_cmd(vm) is None, repr(vm.commands))
check("and it said what it wanted", said(vm, "no perimeter picked"),
      repr(vm.printed))

print("squareup -- a perimeter outside the highlight is asked about")
vm = fresh()
es = tilted_pool(vm, 6.0)
line(vm, (100.0, 0.0), turn((40.0, 0.0), 30.0, (100.0, 0.0)))
far = ents(vm)[-1]
vm.run('c:SQUAREUP', [None, es, [far], 'Wall', 'No'])
check("it said the perimeter would stand still",
      said(vm, "not among the objects you highlighted"), repr(vm.printed))
check("No turns nothing", rotate_cmd(vm) is None, repr(vm.commands))

vm = fresh()
es = tilted_pool(vm, 6.0)
line(vm, (100.0, 0.0), turn((40.0, 0.0), 30.0, (100.0, 0.0)))
far = ents(vm)[-1]
vm.run('c:SQUAREUP', [None, es, [far], 'Wall', 'Yes'])
check("Yes goes ahead anyway", rotate_cmd(vm) is not None,
      repr(vm.commands))

print("squareup -- already square settles it before anything is asked")
vm = fresh()
es = tilted_pool(vm, 0.0)
line(vm, (100.0, 0.0), (140.0, 0.0))
far = ents(vm)[-1]
# the perimeter is outside the highlight AND the drawing is square: the
# confirm would be a question whose two answers do the same thing
vm.run('c:SQUAREUP', [None, es, [far], 'Wall'])
check("the outside-the-highlight question was never put", not any(
    'anyway?' in p for p, _ in vm.prompts), repr(vm.prompts))
check("and it said the drawing was already square",
      said(vm, "already horizontal"), repr(vm.printed))
check("nothing turned", rotate_cmd(vm) is None)

# ----------------------------------------------------------------------
# locked and frozen layers
# ----------------------------------------------------------------------
print("squareup -- a locked and frozen base layer is freed and put back")
vm = fresh(base_flags=LOCKED | FROZEN)
es = tilted_pool(vm, 6.0)
lwpoly(vm, [turn(p, 6.0) for p in
            ((0.0, 0.0), (40.0, 0.0), (40.0, 20.0), (0.0, 20.0))],
       lay='BASE')
base = ents(vm)[-1]
check("the base layer really is locked and frozen going in",
      layer_flags(vm, 'BASE') == LOCKED | FROZEN)
vm.run('c:SQUAREUP', [None, ents(vm), [es[0]], 'Wall'])
check("the base plan turned with everything else",
      square_p(pts_of(vm, base)),
      repr(edge_angles(pts_of(vm, base))))
check("the layer went straight back to locked and frozen",
      layer_flags(vm, 'BASE') == LOCKED | FROZEN,
      repr(layer_flags(vm, 'BASE')))
check("and the run said it had borrowed one",
      said(vm, "locked or frozen layer(s) were freed"), repr(vm.printed[-2:]))
check("a layer nothing borrowed is not mentioned",
      layer_flags(vm, 'POOL') == 0)

print("squareup -- a run that changes nothing borrows nothing")
vm = fresh(base_flags=LOCKED)
es = tilted_pool(vm, 0.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
check("no layer was freed for a turn that never happened",
      layer_flags(vm, 'BASE') == LOCKED
      and not said(vm, "were freed"), repr(vm.printed))

# ----------------------------------------------------------------------
# the failed paths
# ----------------------------------------------------------------------
print("squareup -- Esc at the perimeter prompt is a quiet cancel")
vm = fresh()
vm.handle_errors = True
vm.sysvars['OSMODE'] = 47
es = tilted_pool(vm, 6.0)


def esc(vm):
    raise LispError('Function cancelled', vm)


vm.run('c:SQUAREUP', [None, es, esc])
check("the cancel went through the handler",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0],
      repr(vm.handled_errors))
check("the drafter's object snaps came back", vm.sysvars['OSMODE'] == 47,
      repr(vm.sysvars['OSMODE']))
check("the group opened before the prompt is closed", vm.undo_groups == 0)
check("a plain cancel prints no error line",
      not said(vm, 'SQUAREUP error'), repr(vm.printed[-2:]))
check("nothing turned", rotate_cmd(vm) is None)
check("the global *error* is untouched", not error_global(vm))

print("squareup -- a failure with the layers freed puts them back")
vm = fresh(base_flags=LOCKED | FROZEN)
vm.handle_errors = True
vm.sysvars['OSMODE'] = 47
es = tilted_pool(vm, 6.0)
lwpoly(vm, [turn(p, 6.0) for p in
            ((0.0, 0.0), (40.0, 0.0), (40.0, 20.0), (0.0, 20.0))],
       lay='BASE')
# sq:deg is read between freeing the layers and handing ROTATE its angle
vm.loads('(defun sq:deg (a) (sq:no-such-helper a))')
vm.run('c:SQUAREUP', [None, ents(vm), [es[0]], 'Wall'])
check("aborted through *error*",
      len(vm.handled_errors) == 1
      and 'undefined function' in vm.handled_errors[0],
      repr(vm.handled_errors))
check("the handler locked and froze the layer again",
      layer_flags(vm, 'BASE') == LOCKED | FROZEN,
      repr(layer_flags(vm, 'BASE')))
check("the drafter's object snaps came back", vm.sysvars['OSMODE'] == 47)
check("and the group was closed", vm.undo_groups == 0)
check("the error is reported under the tool's name",
      said(vm, '\nSQUAREUP error:'), repr(vm.printed[-3:]))
check("no summary line for a run that did not finish",
      not said(vm, 'SQUAREUP done'))

print("squareup -- every sysvar it borrows comes back, not just OSMODE")
vm = fresh()
# non-defaults on all five, so a restore that writes the WRONG value
# back is as visible as one that writes none: ROTATE reads its angle
# through the last three, which is why they are borrowed at all
before = {'OSMODE': 47, 'CMDECHO': 1, 'AUNITS': 3, 'ANGBASE': 1.5707963,
          'ANGDIR': 1}
vm.sysvars.update(before)
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
check("it really did turn, so the borrow happened",
      rotate_cmd(vm) is not None)
for name, was in before.items():
    check("%s came back as it was" % name, vm.sysvars[name] == was,
          "%r, was %r" % (vm.sysvars[name], was))

print("squareup -- a second run still saves the drafter's real snaps")
vm = fresh()
vm.handle_errors = True
vm.sysvars['OSMODE'] = 47
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
vm.sysvars['OSMODE'] = 35
es2 = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, es2, [es2[0]], 'Wall'])
check("the snapshot was dropped, so the second run restores 35 not 47",
      vm.sysvars['OSMODE'] == 35, repr(vm.sysvars['OSMODE']))

# ----------------------------------------------------------------------
# the selections
# ----------------------------------------------------------------------
print("squareup -- Enter at the highlight takes the whole drawing")
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, None, [es[0]], 'Wall'])
check("everything in the drawing was handed to ROTATE",
      len(rotate_cmd(vm)[1]) - 1 == len(ents(vm)), repr(rotate_cmd(vm)[1]))
check("so the label turned too", abs(math.degrees(
    grp(vm.entdata[es[1]], 50))) < 1e-9)

print("squareup -- Enter takes the space being drawn in, not the sheet")
# A title block on Layout1, on a locked VIEWPORT layer.  A bare "_X"
# swept it in: ROTATE skips an object outside the current space, yet
# the done line counted it turned and the locked layer was reported
# freed for a turn it was never part of.
vm = fresh()
es = tilted_pool(vm, 6.0)
layer(vm, 'VIEWPORT', LOCKED)
vm.loads('(entmake (list \'(0 . "LINE") \'(8 . "VIEWPORT") \'(410 . "Layout1")'
         ' \'(10 0.0 0.0 0.0) \'(11 400.0 0.0 0.0)))')
sheet = ents(vm)[-1]
vm.run('c:SQUAREUP', [None, None, [es[0]], 'Wall'])
handed = rotate_cmd(vm)[1][1:] if rotate_cmd(vm) else []
check("the sheet's line was not handed to ROTATE", sheet not in handed,
      repr(handed))
check("the done line counts the model space objects only",
      said(vm, "SQUAREUP done: %d object(s) turned" % len(es)),
      repr(vm.printed))
check("no locked layer reported freed for the turn",
      not said(vm, "locked or frozen layer(s) were freed"), repr(vm.printed))
check("VIEWPORT stays locked", layer_flags(vm, 'VIEWPORT') == LOCKED)

print("squareup -- Enter from paper space takes that layout")
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.loads('(entmake (list \'(0 . "LINE") \'(8 . "POOL") \'(410 . "Layout1")'
         ' \'(10 0.0 0.0 0.0) (list 11 %r %r 0.0)))' % turn((400.0, 0.0), 6.0))
sheet = ents(vm)[-1]
vm.sysvars['CTAB'], vm.sysvars['CVPORT'] = 'Layout1', 1
vm.run('c:SQUAREUP', [None, None, [sheet], 'Wall'])
handed = rotate_cmd(vm)[1][1:] if rotate_cmd(vm) else []
check("only the layout's own objects were swept", handed == [sheet],
      repr(handed))

print("squareup -- Enter from inside a layout's viewport takes model space")
# The case the (410 . CTAB) sweep gets wrong: on Layout1 CTAB names the
# sheet, but a drafter working through the viewport is drawing in model
# space.  The two cases above both run with CTAB at "Model", where
# CTAB and "Model" are the same answer, so only this one tells them
# apart.
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.loads('(entmake (list \'(0 . "LINE") \'(8 . "POOL") \'(410 . "Layout1")'
         ' \'(10 0.0 0.0 0.0) (list 11 %r %r 0.0)))' % turn((400.0, 0.0), 6.0))
sheet = ents(vm)[-1]
vm.sysvars.update({'TILEMODE': 0, 'CTAB': 'Layout1', 'CVPORT': 2})
try:
    vm.run('c:SQUAREUP', [None, None, [es[0]], 'Wall'])
except LispError as e:
    # a sweep of the sheet leaves the picked wall outside the highlight,
    # and the run stops to ask whether to turn it anyway
    print('    (the run asked more than it should: %s)'
          % str(e).splitlines()[0][:90])
handed = rotate_cmd(vm)[1][1:] if rotate_cmd(vm) else []
check("the model space pool was handed to ROTATE, all of it",
      len(handed) == len(es) and all(e in handed for e in es),
      repr(handed))
check("and the sheet's line was not", sheet not in handed, repr(handed))

print("squareup -- a highlight already made is taken without asking")
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [es, [es[0]], 'Wall'])
check("the pickfirst set was used", rotate_cmd(vm) is not None)
check("and the highlight prompt was never put", not any(
    'Highlight' in p for p, _ in vm.prompts), repr(vm.prompts))

print("squareup -- only curve types are offered for the perimeter")
vm = fresh()
es = tilted_pool(vm, 6.0)
vm.run('c:SQUAREUP', [None, es, es, 'Wall'])
check("the label was filtered out of the perimeter selection",
      rotate_cmd(vm) is not None
      and abs(rotate_cmd(vm)[-1] + 6.0) < 1e-9, repr(rotate_cmd(vm)))

# ----------------------------------------------------------------------
print()
if FAILS:
    print("test_squareup: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_squareup: all checks passed (%s tier)" % ROOT)
