# SPDX-License-Identifier: GPL-3.0-or-later
"""What ABHD does when the drawing is not what it hoped for.

tests/test_pool_fit.py proves the fitter's geometry against a Python
mirror and tests/test_abhd_runtime.py proves the LISP agrees with it.
Neither drives the CONTINGENCIES: the selection with nothing usable in
it, the perimeter with a gap, the SPLINE that cannot be read, the
tilted UCS, the percentage over 100, the curve cap of None, the pick
that lands nowhere near a survey point, the break line picked twice on
the same point, the bottom cancelled halfway, the Redo that omits a
point and puts it back.  Those paths are most of the file and every one
of them ends in a message a drafter is meant to act on -- so each is
run here, through c:ABHD / c:ADAB / c:ABHDCOVER themselves, and read.

The rules being held, over and above "it did not crash":

  * a run that cannot proceed SAYS WHY and adds nothing to the drawing;
  * a run that can proceed anyway (a stray SPLINE, a tilted object, a
    pick well off the points) warns and carries on;
  * the answers a command remembers for the session are the three it
    documents (*PF-TOL*, *PF-MAX-ARCS*, *PF-HOP-OFF*) and no others --
    cover mode in particular must never outlive its run;
  * every piece of scaffolding it drew is gone at the end, whichever
    way the run ended, and only ABHD's own objects are ever erased;
  * and, through the VM's own run(), no undo group is left open.

Usage:  python3 tests/test_abhd_contingencies.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_abhd_contingencies.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Dot, LispError, Sym            # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
#: the standalone file; CALOFIN_LISP_ROOT=shared remaps it to the twin
LSP = os.path.join(REPO, 'lisp', 'abhd', 'abhd.lsp')

FAILS = []


def check(label, cond, detail=''):
    print(('  ok   ' if cond else '  FAIL ') + label
          + (('  -- ' + str(detail)) if (detail and not cond) else ''))
    if not cond:
        FAILS.append(label)


# ---------------------------------------------------------------- fixtures

def ring(n=12, a=144.0, b=84.0):
    """N points around an ellipse, drawing units (inches) as everywhere."""
    return [(a * math.cos(2.0 * math.pi * i / n),
             b * math.sin(2.0 * math.pi * i / n)) for i in range(n)]


RING = ring()
#: the ellipse's index 0 is its rightmost point, so the deep break goes
#: across the right-hand end (indices 1 and 11) and the shallow break
#: across the left (5 and 7); the point beyond the deep break -- the
#: back of the hopper ABHD finds for itself -- is index 0.
DEEP = (RING[1], RING[11])
SHALLOW = (RING[5], RING[7])

#: a pool with a flat end, for the one question a closed ring cannot
#: pose: a deep break with no survey point at all beyond it
RECT = [(0.0, 0.0), (60.0, 0.0), (120.0, 0.0), (120.0, 30.0),
        (120.0, 60.0), (60.0, 60.0), (0.0, 60.0), (0.0, 30.0)]


def newvm():
    vm = VM()
    vm.load(LSP)
    return vm


def layer(vm, name, colour=7):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") (cons 2 "%s") \'(70 . 0)'
             ' (cons 62 %d) \'(6 . "Continuous")))' % (name, colour))


def add_points(vm, pts, block=True, lay='POINTS', start=1):
    """One survey point per PTS entry: an ab_pt insert carrying a numbered
    `number` attribute (what a real survey looks like), or a plain POINT
    on the points layer.  Returns their enames."""
    out = []
    for i, p in enumerate(pts, start=start):
        if block:
            vm.loads('(entmake (list \'(0 . "INSERT") \'(2 . "ab_pt")'
                     ' (cons 8 "%s") (list 10 %.6f %.6f 0.0)))'
                     % (lay, p[0], p[1]))
            out.append(vm.entities[-1])
            vm.loads('(entmake (list \'(0 . "ATTRIB") (cons 8 "%s")'
                     ' \'(2 . "number") (cons 1 "%d")))' % (lay, i))
        else:
            vm.loads('(entmake (list \'(0 . "POINT") (cons 8 "%s")'
                     ' (list 10 %.6f %.6f 0.0)))' % (lay, p[0], p[1]))
            out.append(vm.entities[-1])
    return out


def add_pline(vm, pts, lay='POOL', closed=True, bulges=None, ext=None):
    """A polyline through PTS.  BULGES gives it curvature (so ABHD reads
    it as a drawn perimeter rather than an ordering sketch); EXT sets the
    210 extrusion, which is how a tilted UCS reaches the file."""
    items = ['\'(0 . "LWPOLYLINE")', '(cons 8 "%s")' % lay,
             '\'(100 . "AcDbPolyline")', '(cons 90 %d)' % len(pts),
             '(cons 70 %d)' % (1 if closed else 0)]
    for i, p in enumerate(pts):
        items.append('(list 10 %.6f %.6f)' % (p[0], p[1]))
        items.append('(cons 42 %.6f)' % ((bulges or [0.0] * len(pts))[i]))
    if ext:
        items.append('(list 210 %.4f %.4f %.4f)' % ext)
    vm.loads('(entmake (list %s))' % ' '.join(items))
    return vm.entities[-1]


def add_line(vm, p1, p2, lay='POOL'):
    layer(vm, lay)
    vm.loads('(entmake (list \'(0 . "LINE") (cons 8 "%s")'
             ' (list 10 %.6f %.6f 0.0) (list 11 %.6f %.6f 0.0)))'
             % (lay, p1[0], p1[1], p2[0], p2[1]))
    return vm.entities[-1]


def survey_vm(pts=RING, block=True):
    """A VM with ABHD loaded, the two layers it reads, and a survey."""
    vm = newvm()
    layer(vm, 'POINTS')
    layer(vm, 'POOL', 4)
    return vm, add_points(vm, pts, block)


#: the pickfirst probe and the six questions ahead of the selection,
#: all taking their Enter default: 1 inch, the standard share, no cap,
#: no declared walls, corners or held points.
SETTINGS = [None, None, None, None, 'No', 'No', 'No']


def said(vm):
    return ''.join(vm.printed)


def live(vm, etype=None, lay=None):
    """The entities still in the drawing, optionally of one type/layer."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for g in vm.entdata.get(e, []):
            if isinstance(g, Dot):
                d.setdefault(g.a, g.b)
            elif isinstance(g, list) and g:
                d.setdefault(g[0], g[1] if len(g) == 2 else g[1:])
        if etype and d.get(0) != etype:
            continue
        if lay and str(d.get(8, '')).upper() != lay.upper():
            continue
        out.append(e)
    return out


def run(vm, cmd, script):
    """Drive one command; a LispError is the failure, reported by the
    caller as the check it was running."""
    vm.run(cmd, script)
    return vm


# ------------------------------------------------- 1. nothing to work with

print("\nselections ABHD cannot fit -- it says why and adds nothing")

vm, _ = survey_vm()
before = len(live(vm))
run(vm, 'c:ABHD', SETTINGS + [None])
check("nothing selected: says so, draws nothing",
      'Nothing usable selected' in said(vm) and len(live(vm)) == before,
      said(vm)[-120:])

vm, ents = survey_vm(RING[:2])
run(vm, 'c:ABHD', SETTINGS + [ents])
check("two points: names the three-point floor",
      'at least 3 distinct points' in said(vm))

# five inserts on one spot: the fit sees ONE point, not five
vm, ents = survey_vm([RING[0]] * 5)
run(vm, 'c:ABHD', SETTINGS + [ents])
check("five duplicate points count as one",
      'at least 3 distinct points' in said(vm))

vm, _ = survey_vm()
line = add_line(vm, (0.0, 0.0), (10.0, 0.0))
run(vm, 'c:ABHD', SETTINGS + [[line]])
check("POOL geometry but no points: names the layer and the block",
      'No survey points found' in said(vm) and 'ab_pt' in said(vm))

# a perimeter with a hole in it, and one whose ends never meet
vm, ents = survey_vm()
gap = [add_line(vm, RING[0], RING[1]), add_line(vm, RING[2], RING[3])]
run(vm, 'c:ABHD', SETTINGS + [ents + gap])
check("a gap in the perimeter is reported, not fitted",
      'gap in the POOL perimeter' in said(vm))

vm, ents = survey_vm()
open_pl = add_pline(vm, RING[:4], closed=False,
                    bulges=[0.2, 0.2, 0.2, 0.2])
run(vm, 'c:ABHD', SETTINGS + [ents + [open_pl]])
check("a perimeter that does not close is reported",
      'does not close' in said(vm) or 'gap in the POOL' in said(vm),
      said(vm)[-160:])


# --------------------------------------- 2. things it warns about and fits

print("\nselections it fits anyway, with a warning")

vm, ents = survey_vm()
vm.loads('(entmake (list \'(0 . "SPLINE") \'(8 . "POOL")'
         ' (list 10 0.0 0.0 0.0)))')
spline = vm.entities[-1]
run(vm, 'c:ABHD', SETTINGS + [ents + [spline], 'None'])
check("a SPLINE on POOL is named, counted and skipped",
      'SPLINE/ELLIPSE object(s)' in said(vm)
      and 'explode or convert' in said(vm))

vm, ents = survey_vm()
tilted = add_pline(vm, RING, ext=(0.0, 0.7, 0.7))
run(vm, 'c:ABHD', SETTINGS + [ents + [tilted], 'None'])
check("geometry drawn in a tilted UCS is called out",
      'not drawn in the world plane' in said(vm)
      and 'UCS to World' in said(vm))

# a pick nowhere near a survey point still snaps, and says it snapped
vm, ents = survey_vm()
run(vm, 'c:ABHD',
    [None, None, None, None,
     'Yes', (600.0, 300.0), (600.0, -300.0), 'No',  # a wall, picked far off
     'No', 'No', ents, 'None'])
check("a wall end picked well off the survey snaps, and says so",
      'picked well away from any survey point' in said(vm))

vm, ents = survey_vm()
run(vm, 'c:ABHD',
    [None, None, None, None,
     'Yes', (600.0, 300.0), (610.0, 300.0), 'No',   # both ends, one point
     'No', 'No', ents, 'None'])
check("a wall whose ends snap to one point is dropped, not drawn",
      'landed on the same survey point' in said(vm)
      and 'that wall is ignored' in said(vm))


# ------------------------------------------------- 3. the numeric questions

print("\nthe three numbers, at their edges")

vm, ents = survey_vm()
run(vm, 'c:ABHD', [None, 99.0, None, None, 'No', 'No', 'No', ents, 'None'])
check("a distance past the ceiling is pulled back to it, out loud",
      'no longer a trace of the points' in said(vm)
      and abs(vm.get(Sym('*pf-tol*')) - 2.0) < 1e-9,
      vm.get(Sym('*pf-tol*')))

vm, ents = survey_vm()
run(vm, 'c:ABHD', [None, None, 250, None, 'No', 'No', 'No', ents, 'None'])
check("a percentage over 100 is refused with a reason",
      'more than 100 makes no sense' in said(vm))

vm, ents = survey_vm()
run(vm, 'c:ABHD', [None, None, None, 6, 'No', 'No', 'No', ents, 'None'])
check("a curve cap is remembered for the session",
      vm.get(Sym('*pf-max-arcs*')) == 6, vm.get(Sym('*pf-max-arcs*')))

vm, ents = survey_vm()
run(vm, 'c:ABHD', [None, None, None, 'None', 'No', 'No', 'No', ents, 'None'])
check("None removes the cap",
      vm.get(Sym('*pf-max-arcs*')) is None, vm.get(Sym('*pf-max-arcs*')))


# ------------------------------------------------------ 4. the three modes

print("\nthe mode is read off the selection")

vm, ents = survey_vm()
run(vm, 'c:ABHD', SETTINGS + [ents, 'None'])
check("points alone: ordered automatically",
      'ordering the points automatically' in said(vm))

vm, ents = survey_vm()
sketch = add_pline(vm, RING)                       # lines only
run(vm, 'c:ABHD', SETTINGS + [ents + [sketch], 'None'])
check("a lines-only sketch only orders the points",
      'lines only - using it just to order' in said(vm))

vm, ents = survey_vm()
guide = add_pline(vm, RING, bulges=[0.15] * len(RING))
run(vm, 'c:ABHD', SETTINGS + [ents + [guide], 'None'])
check("a drawn perimeter with arcs is used as the guide",
      'drawn POOL perimeter as the guide' in said(vm))


# --------------------------------------------- 5. what the choice leaves

print("\nkeeping, keeping all, keeping none")

vm, ents = survey_vm()
run(vm, 'c:ABHD', SETTINGS + [ents, 'None'])
check("None leaves the drawing as it was",
      'nothing was added to the drawing' in said(vm)
      and not live(vm, 'LWPOLYLINE'),
      [str(e) for e in live(vm, 'LWPOLYLINE')])

vm, ents = survey_vm()
run(vm, 'c:ABHD', SETTINGS + [ents, 'All'])
check("All keeps three outlines, on the preview layer",
      len(live(vm, 'LWPOLYLINE', 'POOL-FIT')) == 3,
      len(live(vm, 'LWPOLYLINE', 'POOL-FIT')))

vm, ents = survey_vm()
run(vm, 'c:ABHD', SETTINGS + [ents, '2', 'No'])
kept = live(vm, 'LWPOLYLINE', 'POOL')
check("keeping one moves it to the POOL layer, alone",
      len(kept) == 1 and not live(vm, 'LWPOLYLINE', 'POOL-FIT'),
      "%d on POOL, %d left on POOL-FIT"
      % (len(kept), len(live(vm, 'LWPOLYLINE', 'POOL-FIT'))))
check("the report names the fit that was kept",
      'Keeping fit 2' in said(vm) and 'ABHD:' in said(vm))

# Enter at the keyword prompt offers a click; a click on nothing keeps
# the standing default, which the file now names once
vm, ents = survey_vm()
run(vm, 'c:ABHD', SETTINGS + [ents, None, None, 'No'])
check("Enter then Enter keeps the default fit",
      'Keeping fit 2' in said(vm), said(vm)[-200:])

# ...and which one that is, is a knob: every place the default is read
# has to read the same one, or Enter would keep a fit nobody chose
vm, ents = survey_vm()
vm.loads('(setq *PF-DEFAULT-FIT* "3")')
run(vm, 'c:ABHD', SETTINGS + [ents, None, None, 'No'])
check("moving *PF-DEFAULT-FIT* moves what Enter keeps",
      'Keeping fit 3' in said(vm), said(vm)[-200:])


# ------------------------------------------------------- 6. the pool bottom

print("\nthe pool bottom, over a perimeter that already exists (ADAB)")


def adab_vm():
    """A closed perimeter with its survey points sitting on it."""
    vm = newvm()
    layer(vm, 'POINTS')
    layer(vm, 'POOL', 4)
    ents = add_points(vm, RING)
    pl = add_pline(vm, RING)
    return vm, ents, pl


BREAKS = [SHALLOW[0], SHALLOW[1], DEEP[0], DEEP[1]]
#: Enter at each of the three offsets (the remembered 18") and at both
#: slope questions (Straight)
BOTTOM = BREAKS + ['', '', '', None, None]

vm, ents, pl = adab_vm()
run(vm, 'c:ADAB', [None, [pl]] + BOTTOM)
check("ADAB finds the perimeter's own points without being handed them",
      'picked up automatically' in said(vm))
check("the back of the hopper is found and named",
      'Back of the hopper: Pt.1' in said(vm), said(vm)[-200:])
check("the bottom lands complete, on the POOL layer",
      'Pool bottom added on layer POOL' in said(vm)
      and len(live(vm, 'DIMENSION')) >= 4,
      "%d dims" % len(live(vm, 'DIMENSION')))

# points that are in the selection but nowhere near the loop are set aside
vm, ents, pl = adab_vm()
stray = add_points(vm, [(0.0, 900.0), (40.0, 900.0)], start=99)
run(vm, 'c:ADAB', [None, [pl] + ents + stray] + BOTTOM)
check("selected points well off the perimeter are set aside",
      'well off the' in said(vm) and 'were set aside' in said(vm))

vm, ents, pl = adab_vm()
run(vm, 'c:ADAB', [None, ents])
check("ADAB without a perimeter says which pieces it needs",
      'No perimeter found in the selection' in said(vm))

# both ends of a break on one point: the pick is re-opened, not aborted
vm, ents, pl = adab_vm()
run(vm, 'c:ADAB',
    [None, [pl], SHALLOW[0], SHALLOW[0], DEEP[0], DEEP[1],   # ends coincide
     SHALLOW[0], SHALLOW[1], DEEP[0], DEEP[1]]               # picked again
    + ['', '', '', None, None])
check("a break picked twice on one point re-opens that pick",
      'landed on the same survey point' in said(vm)
      and 'Pool bottom added' in said(vm))

# a deep break with nothing beyond it: the pool's own flat end, which
# is what the pick looks like when the two break lines are swapped
vm = newvm()
layer(vm, 'POINTS')
layer(vm, 'POOL', 4)
add_points(vm, RECT)
pl = add_pline(vm, RECT)
run(vm, 'c:ADAB',
    [None, [pl], (0.0, 0.0), (0.0, 60.0),          # shallow: the left end
     (120.0, 0.0), (120.0, 60.0),                  # deep: the outer end
     None])                                        # ...and give up there
check("a deep break with nothing beyond it is questioned, and re-asked",
      'no survey point lies beyond' in said(vm) and 'swapped' in said(vm)
      and 'the pool bottom was not added' in said(vm), said(vm)[-200:])

# Enter at a pick cancels the whole bottom and leaves nothing behind
vm, ents, pl = adab_vm()
run(vm, 'c:ADAB', [None, [pl], SHALLOW[0], None])
check("Enter at a break pick cancels the bottom, cleanly",
      'the pool bottom was not added' in said(vm)
      and not live(vm, 'DIMENSION') and not live(vm, 'LINE'),
      "%d lines left" % len(live(vm, 'LINE')))

# Back at the second pick re-opens the first
vm, ents, pl = adab_vm()
run(vm, 'c:ADAB',
    [None, [pl], SHALLOW[0], 'Back', SHALLOW[0], SHALLOW[1],
     DEEP[0], DEEP[1]] + ['', '', '', None, None])
check("Back at a break pick re-opens the previous one",
      'Pool bottom added' in said(vm))

# a typed offset in feet and inches picks the other dimension style
vm, ents, pl = adab_vm()
run(vm, 'c:ADAB', [None, [pl]] + BREAKS
    + ["3'6", '', '', None, None])
check("a feet-and-inches offset asks for the feet-inch dim style",
      'SIDE DIMENSION' in said(vm) and 'not in this drawing' in said(vm))
check("the offset it was given is the one it reports",
      'offsets 42.00' in said(vm), said(vm)[-200:])


# ----------------------------------------------------------- 7. cover mode

print("\ncover mode lasts exactly one run")

vm, ents = survey_vm()
run(vm, 'c:ABHDCOVER', SETTINGS + [ents, '2'])
check("ABHDCOVER answers the bottom question for you",
      'Cover sheet - skipping the bottom' in said(vm))
check("...and clears the flag on the way out",
      vm.get(Sym('abhd:*nobottom*')) is None,
      vm.get(Sym('abhd:*nobottom*')))

# the flag must not survive an error either: an Esc mid-run clears it
vm, ents = survey_vm()
vm.handle_errors = True


def esc(_vm):
    raise LispError('Function cancelled', _vm)


run(vm, 'c:ABHDCOVER', [None, esc])
check("an Esc during a cover run clears it too",
      vm.get(Sym('abhd:*nobottom*')) is None
      and vm.handled_errors == ['Function cancelled'],
      vm.handled_errors)


# --------------------------------------------------- 8. the drawing's state

print("\nwhat it does to the drawing around it")

# UNDO switched off: _Begin would error out of the command, so it is
# not called -- and the run still completes
vm, ents = survey_vm()
vm.sysvars['UNDOCTL'] = 0
run(vm, 'c:ABHD', SETTINGS + [ents, '2', 'No'])
check("with undo off it opens no group and still finishes",
      not [c for c in vm.commands if c and c[0] == '_.UNDO']
      and len(live(vm, 'LWPOLYLINE', 'POOL')) == 1)

# an output layer that is off, frozen and locked is restored
vm, ents = survey_vm()
vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
         ' \'(100 . "AcDbLayerTableRecord") \'(2 . "POOL-FIT") \'(70 . 5)'
         ' \'(62 . -3) \'(6 . "Continuous")))')
run(vm, 'c:ABHD', SETTINGS + [ents, 'None'])
check("an off, frozen or locked output layer is restored, out loud",
      'was off, frozen or locked' in said(vm))

# FGStep is a layer drafters use: only ABHD's own objects go
vm, ents = survey_vm()
layer(vm, 'FGStep', 1)
vm.loads('(entmake (list \'(0 . "CIRCLE") \'(8 . "FGStep")'
         ' (list 10 500.0 500.0 0.0) \'(40 . 4.0)))')
mine = vm.entities[-1]
vm.loads('(pf:tag-mine (entlast))')
vm.loads('(entmake (list \'(0 . "CIRCLE") \'(8 . "FGStep")'
         ' (list 10 600.0 600.0 0.0) \'(40 . 4.0)))')
theirs = vm.entities[-1]
run(vm, 'c:ABHD', SETTINGS + [ents, '2', 'No'])
check("on a shared layer it erases its own marks and nothing else",
      mine in vm.deleted and theirs not in vm.deleted)

# every marker drawn during the questions is scaffolding
vm, ents = survey_vm()
run(vm, 'c:ABHD',
    [None, None, None, None,
     'Yes', RING[0], RING[6], 'No',                # a declared wall
     'Yes', RING[3], None,                         # a declared corner
     'Yes', RING[9], None,                         # a held point
     ents, 'None'])
check("declared walls, corners and holds are noted",
      '1 straight wall(s) noted' in said(vm)
      and '1 corner(s) noted' in said(vm)
      and '1 held point(s) noted' in said(vm))
check("...and their markers sweep themselves at the end",
      not live(vm, lay='POOL-WALLS'),
      "%d left" % len(live(vm, lay='POOL-WALLS')))


# ------------------------------------------------------------ 9. the Redo

print("\nRedo: omit a point, put it back, refit")

vm, ents = survey_vm()
run(vm, 'c:ABHD',
    SETTINGS + [ents, 'Redo',
                     RING[4], None,                # omit one, then done
                     None, None, None,             # walls/corners/holds: Keep
                     None, None, None,             # the three numbers: Enter
                     'None'])                      # and discard the new trio
check("Redo omits the point it was given, by name",
      'omitting Pt.5' in said(vm) and '1 point(s) omitted in total'
      in said(vm), said(vm)[-200:])

vm, ents = survey_vm()
run(vm, 'c:ABHD',
    SETTINGS + [ents, 'Redo',
                     RING[4], RING[4], None,       # omit it, then put it back
                     None, None, None,
                     None, None, None,
                     'None'])
check("picking a ringed point again puts it back in",
      'Pt.5 back in' in said(vm) and '1 point(s) omitted in total'
      not in said(vm))

# a wall anchored on an omitted point cannot survive it
vm, ents = survey_vm()
run(vm, 'c:ABHD',
    [None, None, None, None, 'Yes', RING[0], RING[6], 'No', 'No', 'No',
     ents, 'Redo',
     RING[0], None,                                # omit one of its ends
     None, None, None,
     None, None, None,
     'None'])
check("a declared wall that loses an end is dropped, with a note",
      'a declared wall lost an end' in said(vm))

# omitting down to two points is refused rather than fitted
vm, ents = survey_vm(RING[:4])
run(vm, 'c:ABHD',
    SETTINGS + [ents, 'Redo', RING[0], RING[1], None])
check("omitting below three points stops, and says nothing was redone",
      'Too few points remain' in said(vm))


# ------------------------------------------------------- 10. what it leaves

print("\nthe session, afterwards")

vm, ents = survey_vm()
before = dict(vm.sysvars)
run(vm, 'c:ABHD', SETTINGS + [ents, '2', 'No'])
changed = {k: (before.get(k), v) for k, v in vm.sysvars.items()
           if before.get(k) != v}
check("a complete run changes no system variable", not changed, changed)
check("...and leaves no preview or label behind",
      not live(vm, 'LWPOLYLINE', 'POOL-FIT') and not live(vm, 'TEXT',
                                                          'POOL-FIT'),
      "%d previews, %d labels"
      % (len(live(vm, 'LWPOLYLINE', 'POOL-FIT')),
         len(live(vm, 'TEXT', 'POOL-FIT'))))

# the hopper offset is the third thing a session remembers
vm, ents, pl = adab_vm()
run(vm, 'c:ADAB', [None, [pl]] + BREAKS + ['24', '', '', None, None])
check("the first hopper offset becomes the session default",
      abs(vm.get(Sym('*pf-hop-off*')) - 24.0) < 1e-9,
      vm.get(Sym('*pf-hop-off*')))


# --------------------------------------------------- 11. odds and ends

print("\nthe smaller contingencies")

# an offset must be a positive distance, and has to look like one
vm, ents, pl = adab_vm()
run(vm, 'c:ADAB', [None, [pl]] + BREAKS
    + ['0', 'not a distance', '18', '', '', None, None])
check("a zero offset is refused, with the reason",
      'must be a positive distance' in said(vm))
check("text that is not a distance is refused, with the spelling shown",
      'that is not a distance' in said(vm) and "3'6" in said(vm))

# a survey of plain POINTs carries no numbers, so they are numbered in
# the order they were selected -- and the reports use those numbers
vm = newvm()
layer(vm, 'POINTS')
layer(vm, 'POOL', 4)
ents = add_points(vm, RING, block=False)
run(vm, 'c:ABHD',
    SETTINGS + [ents, 'Redo', RING[4], None,
                None, None, None, None, None, None, 'None'])
check("points with no number attribute are numbered in selection order",
      'omitting Pt.5' in said(vm), said(vm)[-160:])

# ADAB must not read ABHD's own bottom back as perimeter
vm, ents, pl = adab_vm()
own = add_line(vm, (0.0, -20.0), (0.0, 20.0))
vm.loads('(pf:tag-mine (entlast))')
run(vm, 'c:ADAB', [None, [pl, own]] + BOTTOM)
check("ABHD's own geometry in an ADAB selection is skipped, and counted",
      'marker/bottom object(s) in the selection were ignored' in said(vm))

# in guided mode the drawn shape wins over a held point, and says so
vm, ents = survey_vm()
guide = add_pline(vm, RING, bulges=[0.15] * len(RING))
run(vm, 'c:ABHD',
    [None, None, None, None, 'No', 'No',
     'Yes', RING[3], None,                         # a held point
     ents + [guide], 'None'])
check("guided mode says a held point only steers the points-built fit",
      'held points only bind the' in said(vm))


# ------------------------------------------------- 12. the tutorial itself

print("\nTUTORIALABHD, which nothing had ever run")

vm = newvm()
run(vm, 'c:TUTORIALABHD', ['Checks'] + [None] * 8)
check("Checks pages through every rule and names the loaded version",
      'WHAT ABHD NEEDS' in said(vm) and 'THE SEVEN QUESTIONS' in said(vm)
      and 'HOUSEKEEPING' in said(vm)
      and vm.get(Sym('pf:*version*')) in said(vm))
check("...and it draws nothing at all",
      not live(vm), "%d entities" % len(live(vm)))

# the demo on a drawing that has none of ABHD's layers -- which is the
# drawing a first-time user runs it in
vm = newvm()
run(vm, 'c:TUTORIALABHD', ['Demo', (0.0, 0.0)] + [None] * 5 + ['No'])
check("Demo draws the practice pool, the three fits and the bottom",
      'A surveyor shot these points' in said(vm)
      and 'Pool bottom added' in said(vm))
check("...and sweeps every last piece of it when told to",
      not live(vm) and 'Swept' in said(vm),
      "%d left" % len(live(vm)))

vm = newvm()
run(vm, 'c:TUTORIALABHD', ['Demo', (0.0, 0.0)] + [None] * 5 + ['Yes'])
kept_demo = live(vm)
unstamped = [e for e in kept_demo
             if not any((isinstance(g, list) and g and g[0] == -3)
                        for g in vm.entdata.get(e, []))]
check("keeping the demo leaves it in the drawing",
      len(kept_demo) > 20 and 'Kept' in said(vm),
      "%d left" % len(kept_demo))
check("...and every piece of it is stamped, as it promises",
      not unstamped, "%d unstamped" % len(unstamped))

# Both is the default, and TUTORIALADAB is the same tour
vm = newvm()
run(vm, 'c:TUTORIALADAB', [None] + [None] * 8 + [(0.0, 0.0)]
    + [None] * 5 + ['No'])
check("Enter runs both halves, under either name",
      'WHAT ABHD NEEDS' in said(vm) and 'Pool bottom added' in said(vm))


# ------------------------------------------ 13. the knobs and their prose

print("\nevery knob is at the top, and every one is written down")

import re                                              # noqa: E402

#: the file this tier actually loads -- the standalone one, or its
#: generated twin under CALOFIN_LISP_ROOT=shared
_src = open(newvm()._remap_root(LSP)).read()

#: the three answers the file documents as remembered from run to run.
#: Each is WRITTEN by the run that asks it, so none of them is a knob
#: (STANDARDS.md section 5): they live in the state section, and a
#: block advertising one would be offering an initial value as a
#: setting.
REMEMBERED = {'*PF-TOL*', '*PF-MAX-ARCS*', '*PF-HOP-OFF*'}

check("the tunables block is ruled off, and so is the state under it",
      _src.count(';;; -------------------- tunables ') == 1
      and _src.count(';; ---- end of tunables') == 1
      and _src.count(';; ---- end of state') == 1)
_block, _rest = _src.split(';; ---- end of tunables', 1)
_block = _block.split(';;; -------------------- tunables ', 1)[1]
_state, _body = _rest.split(';; ---- end of state', 1)
check("...and both come before the first defun",
      '(defun' not in _block and '(defun' not in _state)

_knobs = set(re.findall(r'\(setq\s+(\*PF-[A-Z0-9-]+\*)', _block))
_written = set(re.findall(r'\(setq\s+(\*PF-[A-Z0-9-]+\*)', _state + _body))
check("every knob in the block is a literal nothing re-assigns",
      not (_knobs & _written), sorted(_knobs & _written))
check("the answers a run writes are state, and are not in the block",
      _written == REMEMBERED and not (_knobs & REMEMBERED),
      sorted(_written ^ REMEMBERED))
check("every knob carries an explanation",
      all(re.search(re.escape(k) + r'\*?[^\n]*\n?[^\n]*;', _block)
          for k in _knobs))

_doc = open(os.path.join(REPO, 'lisp', 'abhd', 'README.md')).read()
_undocumented = sorted(k for k in _knobs if ('`%s`' % k) not in _doc)
check("and the README documents every one of them",
      not _undocumented, _undocumented)
print("  (%d knobs)" % len(_knobs))


# ------------------------------------------------------------ the verdict

print()
if FAILS:
    print("%d FAILED:\n  %s" % (len(FAILS), "\n  ".join(FAILS)))
    sys.exit(1)
print("ALL ABHD CONTINGENCY CHECKS PASSED"
      + (" [%s tier]" % os.environ['CALOFIN_LISP_ROOT']
         if os.environ.get('CALOFIN_LISP_ROOT') else ""))
