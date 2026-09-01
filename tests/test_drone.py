"""Runtime tests for DRONE and TYDRN: build a survey drawing with locked
layers, run the REAL cleanup commands over it, and check what came out
-- and, for the first time, what happens when a run is cut short.

Both tools used to install their error handler by swapping the global
*error* and swapping it back on each exit.  In a loaded-together build
that is a handler for EVERY tool the moment one exit is missed, so the
handler is local to the command now (STANDARDS 5) and this file drives
the paths that matter:

  * the happy path -- text restyled, points and outlines moved, anchor
    points coloured, every layer the run unlocked locked again, the undo
    mark closed, and the global *error* untouched afterwards;
  * an error mid-run -- the VM hands it to the command's own *error*
    with every frame still live, so the handler can see what the run
    unlocked and put it back, close the mark it opened, and say so;
  * an Esc at the selection prompt -- the same cleanup, and no "error"
    line for a plain cancel.

Script values answer the interactive calls in order: None is Enter at
the pickfirst probe and again at the selection prompt, which sends the
tool to "all text in the drawing".  A function-valued answer runs when
its prompt is reached, which is how the Esc is delivered.

Run: python3 tests/test_drone.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_drone.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
DRONE = os.path.join(HERE, '..', 'lisp', 'drone', 'drone.lsp')
TYDRN = os.path.join(HERE, '..', 'lisp', 'tydrn', 'tydrn.lsp')

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

def layer(name, color, flags=0):
    return ('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
            ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
            ' \'(62 . %d) \'(6 . "Continuous")))' % (name, flags, color))


def text(lay, s, x, y, rot):
    return ('(entmake (list \'(0 . "TEXT") \'(8 . "%s") \'(10 %s %s 0.0)'
            ' \'(40 . 6.0) \'(1 . "%s") \'(50 . %s) \'(7 . "STANDARD")'
            ' \'(62 . 1) \'(6 . "DASHED") \'(370 . 35)))'
            % (lay, x, y, s, rot))


def point(lay, x, y):
    return ('(entmake (list \'(0 . "POINT") \'(8 . "%s") \'(10 %s %s 0.0)'
            ' \'(62 . 3)))' % (lay, x, y))


def line(lay, x1, y1, x2, y2):
    return ('(entmake (list \'(0 . "LINE") \'(8 . "%s") \'(10 %s %s 0.0)'
            ' \'(11 %s %s 0.0) \'(62 . 2)))' % (lay, x1, y1, x2, y2))


LOCKED = 4


def survey(vm):
    """A pool survey the way it arrives: labels on a locked LABELS
    layer, points on POOL and SPA, the spa outline on SPA, anchors on
    ANCHORS -- and the POINTS layer it all moves to already there and
    LOCKED, which is the case the unlock/relock exists for."""
    vm.loads(layer('POOL', 4))
    vm.loads(layer('SPA', 2))
    vm.loads(layer('ANCHORS', 1))
    vm.loads(layer('POINTS', 6, LOCKED))
    vm.loads(layer('LABELS', 7, LOCKED))
    vm.loads(layer('DASHED', 7))
    vm.loads(text('LABELS', '101', 10, 10, 3.5))     # upside down
    vm.loads(text('LABELS', '102', 20, 10, 0.0))
    vm.loads(point('POOL', 10, 10))
    vm.loads(point('SPA', 20, 10))
    vm.loads(line('SPA', 0, 0, 30, 0))
    vm.loads(point('ANCHORS', 50, 50))


def ents(vm, etype):
    return [vm.entdata[e] for e in vm.entities
            if e not in vm.deleted and grp(vm.entdata[e], 0) == etype]


def layer_flags(vm, name):
    rec = vm.tablerecs['LAYER'][name.upper()]
    return grp(vm.recdata[rec], 70) or 0


def error_global(vm):
    """T when a function is left sitting in the GLOBAL *error*."""
    v = vm.globals.get(Sym('*error*'))
    return isinstance(v, tuple) or isinstance(v, list)


def fresh(path):
    vm = VM()
    vm.load(path)
    survey(vm)
    return vm


# ----------------------------------------------------------------------
# statics
# ----------------------------------------------------------------------
print("statics -- the handler is the command's own")
for name, path in (('drone', DRONE), ('tydrn', TYDRN)):
    src = open(path, encoding='ascii').read()
    check(f"{name}: no global *error* swap left",
          '-old-error*' not in src and re.search(
              r"\(setq\s+\*error\*", src) is None)
    m = re.search(r"\(defun\s+[cC]:%s\s*\(/([^)]*)\)" % name.upper(), src)
    check(f"{name}: *error* is a local of the command",
          m is not None and '*error*' in m.group(1).split())
    check(f"{name}: the handler closes only a mark the run opened",
          "(if mark-open (vl-catch-all-apply 'vla-EndUndoMark" in src)
    check(f"{name}: no run state in globals",
          f'*{name}-doc*' not in src and f'*{name}-unlocked*' not in src)

# ----------------------------------------------------------------------
# DRONE, happy path
# ----------------------------------------------------------------------
print("drone -- the five fixes, on a drawing with locked layers")
vm = fresh(DRONE)
vm.run('c:DRONE', [None, None])

ts = ents(vm, 'TEXT')
check("every text is ROMANC at 4.5", all(
    grp(d, 7) == 'ROMANC' and grp(d, 40) == 4.5 for d in ts), repr(ts))
check("text colour / linetype / lineweight forced BYLAYER", all(
    grp(d, 62) == 256 and grp(d, 6) == 'ByLayer' and grp(d, 370) == -1
    for d in ts), repr(ts))
check("text oriented west -> east", all(
    abs(grp(d, 50)) < 1e-9 for d in ts), repr([grp(d, 50) for d in ts]))
check("ROMANC style was created", 'ROMANC' in vm.tables['STYLE'])

pts = ents(vm, 'POINT')
by_layer = {grp(d, 8): d for d in pts}
check("POOL and SPA points moved to POINTS, BYLAYER",
      sum(1 for d in pts if grp(d, 8) == 'POINTS' and grp(d, 62) == 256) == 2,
      repr(pts))
check("the ANCHORS point stays put and turns pink",
      'ANCHORS' in by_layer and grp(by_layer['ANCHORS'], 62) == 6)
outline = ents(vm, 'LINE')
check("the spa outline moved to POOL, BYLAYER",
      outline and grp(outline[0], 8) == 'POOL' and grp(outline[0], 62) == 256)

# POINTS is an OUTPUT layer: ensure-layer unlocks it for good and says
# so, the way every output layer in the tree is repaired (STANDARDS 5).
# LABELS is not -- it was unlocked only so the text could be restyled,
# and that is the lock the run has to put back.
check("POINTS, the output layer, was repaired and left usable",
      not layer_flags(vm, 'POINTS') & LOCKED and any(
          'POINTS was off, frozen or locked' in s for s in vm.printed))
check("LABELS, unlocked only for the run, is locked again",
      layer_flags(vm, 'LABELS') & LOCKED)
check("and it really was unlocked and relocked, once each",
      vm.lock_log == [('LABELS', False), ('LABELS', True)], repr(vm.lock_log))
check("POOL was never locked and is not now",
      not layer_flags(vm, 'POOL') & LOCKED)
check("one undo mark, opened and closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("the global *error* is untouched after the run", not error_global(vm))
check("the summary line names the counts", any(
    'DRONE done: 2 text' in s and '2 point(s)' in s and '1 perimeter' in s
    and '1 ANCHORS' in s for s in vm.printed), repr(vm.printed[-2:]))

# ----------------------------------------------------------------------
# DRONE, an error mid-run
# ----------------------------------------------------------------------
print("drone -- an error mid-run reaches the command's own handler")
vm = fresh(DRONE)
vm.handle_errors = True
# the first restyle blows up: an unbound function, the way a typo or a
# missing helper dies at the command line
vm.loads('(defun drone:force-bylayer (obj) (drone:no-such-helper obj))')
r = vm.run('c:DRONE', [None, None])
check("the run is aborted through *error*, not a crash",
      len(vm.handled_errors) == 1
      and 'undefined function' in vm.handled_errors[0],
      repr(vm.handled_errors))
check("the handler saw the unlocked layer and locked it again",
      layer_flags(vm, 'LABELS') & LOCKED
      and vm.lock_log == [('LABELS', False), ('LABELS', True)],
      repr(vm.lock_log))
check("the handler closed the mark it opened",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("the error is reported under the tool's name", any(
    s.startswith('\nDRONE error:') for s in vm.printed), repr(vm.printed[-3:]))
check("the global *error* is still untouched afterwards", not error_global(vm))
check("no summary line for a run that did not finish", not any(
    'DRONE done' in s for s in vm.printed))

# ----------------------------------------------------------------------
# DRONE, Esc at the selection prompt
# ----------------------------------------------------------------------
print("drone -- Esc at the selection prompt is a quiet cancel")
vm = fresh(DRONE)
vm.handle_errors = True


def esc(vm):
    raise LispError('Function cancelled', vm)


vm.run('c:DRONE', [None, esc])
check("the cancel went through the handler",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0])
check("nothing was changed", all(grp(d, 7) == 'STANDARD'
                                 for d in ents(vm, 'TEXT')))
check("the mark opened before the prompt is closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("a plain cancel prints no error line", not any(
    'DRONE error' in s for s in vm.printed), repr(vm.printed[-2:]))
check("the layers were never unlocked, so nothing to relock",
      layer_flags(vm, 'LABELS') & LOCKED and vm.lock_log == [],
      repr(vm.lock_log))

# ----------------------------------------------------------------------
# TYDRN
# ----------------------------------------------------------------------
print("tydrn -- the same shape on the tie-down drawing")
vm = fresh(TYDRN)
vm.run('c:TYDRN', [None, None])
ts = ents(vm, 'TEXT')
check("every text is ROMANC at 4.5, flat", all(
    grp(d, 7) == 'ROMANC' and grp(d, 40) == 4.5 and abs(grp(d, 50)) < 1e-9
    for d in ts), repr(ts))
pts = ents(vm, 'POINT')
check("the POOL point moved to POINTS; SPA is not TYDRN's business",
      sorted(grp(d, 8) for d in pts) == ['ANCHORS', 'POINTS', 'SPA'],
      repr([grp(d, 8) for d in pts]))
check("the ANCHORS point turns pink", any(
    grp(d, 8) == 'ANCHORS' and grp(d, 62) == 6 for d in pts))
check("the spa outline is left alone",
      grp(ents(vm, 'LINE')[0], 8) == 'SPA')
check("LABELS is locked again; POINTS, the output layer, stays usable",
      layer_flags(vm, 'LABELS') & LOCKED
      and not layer_flags(vm, 'POINTS') & LOCKED
      and vm.lock_log == [('LABELS', False), ('LABELS', True)],
      repr(vm.lock_log))
check("one undo mark, opened and closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0)
check("the global *error* is untouched after the run", not error_global(vm))

print("tydrn -- an error mid-run")
vm = fresh(TYDRN)
vm.handle_errors = True
vm.loads('(defun tydrn:force-bylayer (obj) (tydrn:no-such-helper obj))')
vm.run('c:TYDRN', [None, None])
check("aborted through *error*", len(vm.handled_errors) == 1)
check("layer locked again, mark closed",
      layer_flags(vm, 'LABELS') & LOCKED
      and vm.lock_log == [('LABELS', False), ('LABELS', True)]
      and vm.undo_marks == 0 and vm.undo_log == ['start', 'end'],
      repr((vm.lock_log, vm.undo_log)))
check("reported under the tool's name", any(
    s.startswith('\nTYDRN error:') for s in vm.printed))
check("the global *error* is still untouched", not error_global(vm))

# ----------------------------------------------------------------------
if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL DRONE / TYDRN TESTS PASSED")
