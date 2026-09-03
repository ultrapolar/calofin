"""Runtime tests for VSCONV: build a VS survey export the way it arrives
-- the exporter's numbered layers, a locked one among them, dimensions
carrying the exporter's style AND its DSTYLE overrides -- run the REAL
command over it, and check what came out.

The conversion is a layer rename plus a dimension restyle, so the tests
are about the two things that are easy to get half right:

  * the move itself -- three source layers collapsing onto POOL, the
    anchors onto POINTS, the dimensions onto DIMENSION, everything
    forced BYLAYER, and anything NOT on a source layer left alone;
  * the dimensions -- the style name is only half the job.  The export
    writes text height and arrow size into each dimension as ACAD/DSTYLE
    xdata, and an override outranks the style it sits on, so a dimension
    renamed to STANDARD with its overrides still attached still draws in
    the export's text.  The xdata has to go with the rename.

The cancel paths matter for the same reason they do in DRONE and TYDRN:
the handler is a local of the command, and it is what puts a locked
layer back and closes the mark when a run is cut short.

Script values answer the interactive calls in order: None is Enter at
the pickfirst probe and again at the selection prompt, which sends the
tool to every VS layer in the drawing.  A function-valued answer runs
when its prompt is reached, which is how the Esc is delivered.

Run: python3 tests/test_vsconv.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_vsconv.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
VSCONV = (os.path.join(HERE, '..', 'shared', 'parts', 'VSCONV.lsp')
          if ROOT == 'shared'
          else os.path.join(HERE, '..', 'lisp', 'vsconv', 'VSCONV.lsp'))
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
# the drawing, as the export hands it over
# ----------------------------------------------------------------------

def layer(name, color, flags=0):
    return ('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
            ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
            ' \'(62 . %d) \'(6 . "Continuous")))' % (name, flags, color))


def line(lay, x1, y1, x2, y2):
    """Carrying an explicit colour, linetype and lineweight -- what the
    BYLAYER forcing is there to strip."""
    return ('(entmake (list \'(0 . "LINE") \'(8 . "%s") \'(10 %s %s 0.0)'
            ' \'(11 %s %s 0.0) \'(62 . 2) \'(6 . "DASHED") \'(370 . 35)))'
            % (lay, x1, y1, x2, y2))


def poly(lay, x, y):
    """Two vertices, because AutoCAD hands back nil for fewer -- the
    coping band arrives as polylines where the outline is lines."""
    return ('(entmake (list \'(0 . "LWPOLYLINE") \'(8 . "%s") \'(90 . 2)'
            ' \'(10 %s %s) \'(10 %s %s) \'(62 . 2)))'
            % (lay, x, y, x + 10, y))


def point(lay, x, y):
    return ('(entmake (list \'(0 . "POINT") \'(8 . "%s") \'(10 %s %s 0.0)'
            ' \'(62 . 3)))' % (lay, x, y))


def dim(lay, style, x, y):
    """A dimension the way the export writes one: its own style name in
    group 3, and the style OVERRIDES beside it as ACAD/DSTYLE xdata --
    text height 2.5 and three decimal places, in this one."""
    return ('(entmake (list \'(0 . "DIMENSION") \'(8 . "%s") \'(10 %s %s 0.0)'
            ' \'(3 . "%s") \'(70 . 32) \'(62 . 2)'
            ' (list -3 (list "ACAD" (cons 1000 "DSTYLE") (cons 1002 "{")'
            ' (cons 1070 171) (cons 1070 3) (cons 1070 141) (cons 1040 2.5)'
            ' (cons 1002 "}")))))' % (lay, x, y, style))


def text(lay, s, x, y):
    return ('(entmake (list \'(0 . "TEXT") \'(8 . "%s") \'(10 %s %s 0.0)'
            ' \'(40 . 6.0) \'(1 . "%s") \'(7 . "STANDARD") \'(62 . 1)))'
            % (lay, x, y, s))


LOCKED = 4

SRC = ('1 Perimeter', '2 Coping', '3 Features', '3.1 Anchors', '4 Dimensions')


def survey(vm):
    """The export as it arrives: five numbered layers, "3.1 Anchors"
    LOCKED (the lock the run has to open and put back), POINTS already
    in the drawing and locked too -- that one is a DESTINATION, so it is
    repaired for good -- and POOL and DIMENSION not there at all."""
    for name in SRC:
        vm.loads(layer(name, 7, LOCKED if name == '3.1 Anchors' else 0))
    vm.loads(layer('POINTS', 6, LOCKED))
    vm.loads(layer('TEXT', 4))
    vm.loads(layer('DASHED', 7))
    vm.loads(line('1 Perimeter', 0, 0, 100, 0))     # the outline
    vm.loads(line('1 Perimeter', 100, 0, 100, 50))
    vm.loads(poly('2 Coping', 0, 0))                # the coping band
    vm.loads(line('3 Features', 20, 10, 30, 10))    # a step
    vm.loads(point('3.1 Anchors', 5, 5))            # survey points
    vm.loads(point('3.1 Anchors', 95, 5))
    vm.loads(dim('4 Dimensions', 'QCADDimStyle', 50, -12))
    vm.loads(text('TEXT', 'TITLE BLOCK', 0, 200))   # not the export's


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


def fresh(load=True):
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(VSCONV)
    if load:
        survey(vm)
    return vm


def bylayer(d):
    return (grp(d, 62) == 256 and grp(d, 6) == 'ByLayer'
            and grp(d, 370) == -1)


# ----------------------------------------------------------------------
# statics
# ----------------------------------------------------------------------
print("statics -- the handler is the command's own")
src = open(VSCONV, encoding='ascii').read()
check("no global *error* swap left",
      '-old-error*' not in src and re.search(r"\(setq\s+\*error\*", src) is None)
m = re.search(r"\(defun\s+[cC]:VSCONV\s*\(/([^)]*)\)", src)
check("*error* is a local of the command",
      m is not None and '*error*' in m.group(1).split())
check("the handler closes only a mark the run opened",
      "(if mark-open (vl-catch-all-apply 'vla-EndUndoMark" in src)
check("no run state in globals",
      '*vsconv-doc*' not in src and '*vsconv-unlocked*' not in src)

# ----------------------------------------------------------------------
# the happy path
# ----------------------------------------------------------------------
print("vsconv -- the export converted, on a drawing with locked layers")
vm = fresh()
vm.run('c:VSCONV', [None, None])

lines = ents(vm, 'LINE')
polys = ents(vm, 'LWPOLYLINE')
pts = ents(vm, 'POINT')
dims = ents(vm, 'DIMENSION')
txt = ents(vm, 'TEXT')

check("perimeter, coping and features all land on POOL",
      sorted(grp(d, 8) for d in lines + polys) == ['POOL'] * 4,
      repr([grp(d, 8) for d in lines + polys]))
check("the anchors land on POINTS",
      [grp(d, 8) for d in pts] == ['POINTS'] * 2,
      repr([grp(d, 8) for d in pts]))
check("the dimension lands on DIMENSION",
      [grp(d, 8) for d in dims] == ['DIMENSION'], repr(dims))
check("everything moved is forced BYLAYER",
      all(bylayer(d) for d in lines + polys + pts + dims),
      repr([(grp(d, 8), grp(d, 62), grp(d, 6), grp(d, 370))
            for d in lines + polys + pts + dims]))
check("what was not on a VS layer is left exactly as it was",
      [grp(d, 8) for d in txt] == ['TEXT'] and grp(txt[0], 62) == 1
      and grp(txt[0], 7) == 'STANDARD', repr(txt))
check("POOL and DIMENSION were created for the run",
      'POOL' in vm.tables['LAYER'] and 'DIMENSION' in vm.tables['LAYER'])

# the dimensions: the rename is only half of it
check("the dimension is on the shop style",
      grp(dims[0], 3) == 'STANDARD', repr(grp(dims[0], 3)))
check("and its style overrides went with the rename",
      grp(dims[0], -3) == ['ACAD'], repr(grp(dims[0], -3)))

# locks: a SOURCE layer is unlocked for the run and put back; a
# DESTINATION is an output layer, repaired for good (STANDARDS 5)
check('"3.1 Anchors", unlocked only for the run, is locked again',
      layer_flags(vm, '3.1 Anchors') & LOCKED)
check("POINTS, the output layer, was repaired and left usable",
      not layer_flags(vm, 'POINTS') & LOCKED and any(
          'POINTS was off, frozen or locked' in s for s in vm.printed))
check("and the source lock was opened and closed once each",
      vm.lock_log == [('3.1 ANCHORS', False), ('3.1 ANCHORS', True)],
      repr(vm.lock_log))
check("one undo mark, opened and closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("the global *error* is untouched after the run", not error_global(vm))

check("the summary counts what moved, per source layer", any(
    'VSCONV done: 7 object(s) converted' in s for s in vm.printed)
    and any('1 Perimeter: 2 -> POOL' in s for s in vm.printed)
    and any('2 Coping: 1 -> POOL' in s for s in vm.printed)
    and any('3.1 Anchors: 2 -> POINTS' in s for s in vm.printed),
    repr(vm.printed[-8:]))
check("the dimension line names the style and the overrides", any(
    '1 dimension(s) -> STANDARD, ACAD style overrides removed' in s
    for s in vm.printed), repr(vm.printed[-8:]))
check("the emptied source layers are named, not purged", any(
    'now empty: ' + ', '.join(SRC) in s for s in vm.printed)
    and all(name in vm.tables['LAYER'] for name in SRC),
    repr(vm.printed[-3:]))

# ----------------------------------------------------------------------
# a highlight is the scope when there is one
# ----------------------------------------------------------------------
print("vsconv -- a highlight converts what was highlighted, and no more")
vm = fresh()
picked = [e for e in vm.entities
          if vm.layer_of(e) in ('3.1 Anchors', 'TEXT')]
vm.pickfirst = ['<ss>'] + picked
vm.run('c:VSCONV', [])
check("the highlighted anchors moved",
      [grp(d, 8) for d in ents(vm, 'POINT')] == ['POINTS'] * 2)
check("the outline nobody highlighted stayed on its export layer",
      sorted(grp(d, 8) for d in ents(vm, 'LINE'))
      == ['1 Perimeter', '1 Perimeter', '3 Features'],
      repr([grp(d, 8) for d in ents(vm, 'LINE')]))
check("the highlighted TEXT was still not the export's to convert",
      grp(ents(vm, 'TEXT')[0], 8) == 'TEXT')
check("only the layer the highlight actually emptied is reported empty",
      any('now empty: 3.1 Anchors -' in s for s in vm.printed)
      and not any('1 Perimeter' in s and 'now empty' in s
                  for s in vm.printed), repr(vm.printed[-3:]))

# ----------------------------------------------------------------------
# a drawing that is not a VS export
# ----------------------------------------------------------------------
print("vsconv -- a drawing with none of the export's layers")
vm = fresh(load=False)
vm.loads(layer('POOL', 4))
vm.loads(line('POOL', 0, 0, 10, 0))
vm.run('c:VSCONV', [])          # no prompt is reached: nothing to ask about
check("it says which layers it looked for", any(
    'carries none of the VS layers' in s and '3.1 Anchors' in s
    for s in vm.printed), repr(vm.printed))
check("and points at the table when the export has been renamed", any(
    '*vsconv-map*' in s for s in vm.printed))
check("the mark opened before the check is closed again",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("nothing was converted", grp(ents(vm, 'LINE')[0], 8) == 'POOL'
      and grp(ents(vm, 'LINE')[0], 62) == 2)

# ----------------------------------------------------------------------
# the layers are there but there is nothing on them
# ----------------------------------------------------------------------
print("vsconv -- the VS layers are there, empty")
vm = fresh(load=False)
for name in SRC:
    vm.loads(layer(name, 7))
vm.run('c:VSCONV', [None, None])
check("it does not claim to have emptied layers it never touched",
      not any('now empty' in s for s in vm.printed), repr(vm.printed[-3:]))
check("it says the layers carry nothing", any(
    'carry nothing' in s and 'nothing to convert' in s for s in vm.printed),
    repr(vm.printed[-3:]))
check("and that is not the same message as a drawing without them",
      not any('carries none of the VS layers' in s for s in vm.printed))
check("the mark is closed either way",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0)

# ----------------------------------------------------------------------
# the shop dimension style is missing
# ----------------------------------------------------------------------
print("vsconv -- the drawing has no such dimension style")
vm = fresh()
vm.loads('(setq *vsconv-dim-style* "STANDARD INCHES")')
vm.run('c:VSCONV', [None, None])
d = ents(vm, 'DIMENSION')[0]
check("the dimension still moved layer", grp(d, 8) == 'DIMENSION')
check("but kept the export's style rather than being given a fiction",
      grp(d, 3) == 'QCADDimStyle')
check("its overrides were left on it too, since the style is what would"
      " have replaced them", grp(d, -3)[0] == 'ACAD'
      and len(grp(d, -3)) > 1, repr(grp(d, -3)))
check("and the run says so once, not once per dimension",
      len([s for s in vm.printed
           if 'no "STANDARD INCHES" dimension style' in s]) == 1,
      repr(vm.printed[-4:]))

# ----------------------------------------------------------------------
# an error mid-run
# ----------------------------------------------------------------------
print("vsconv -- an error mid-run reaches the command's own handler")
vm = fresh()
vm.handle_errors = True
vm.loads('(defun vsconv:force-bylayer (obj) (vsconv:no-such-helper obj))')
vm.run('c:VSCONV', [None, None])
check("the run is aborted through *error*, not a crash",
      len(vm.handled_errors) == 1
      and 'undefined function' in vm.handled_errors[0],
      repr(vm.handled_errors))
check("the handler saw the unlocked layer and locked it again",
      layer_flags(vm, '3.1 Anchors') & LOCKED
      and vm.lock_log == [('3.1 ANCHORS', False), ('3.1 ANCHORS', True)],
      repr(vm.lock_log))
check("the handler closed the mark it opened",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("the error is reported under the tool's name", any(
    s.startswith('\nVSCONV error:') for s in vm.printed),
    repr(vm.printed[-3:]))
check("the global *error* is still untouched afterwards", not error_global(vm))
check("no summary line for a run that did not finish",
      not any('VSCONV done' in s for s in vm.printed))

# ----------------------------------------------------------------------
# Esc at the selection prompt
# ----------------------------------------------------------------------
print("vsconv -- Esc at the selection prompt is a quiet cancel")
vm = fresh()
vm.handle_errors = True


def esc(vm):
    raise LispError('Function cancelled', vm)


vm.run('c:VSCONV', [None, esc])
check("the cancel went through the handler",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0])
check("nothing was converted",
      sorted(grp(d, 8) for d in ents(vm, 'POINT')) == ['3.1 Anchors'] * 2)
check("the mark opened before the prompt is closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("a plain cancel prints no error line",
      not any('VSCONV error' in s for s in vm.printed), repr(vm.printed[-2:]))
check("the layers were never unlocked, so nothing to relock",
      layer_flags(vm, '3.1 Anchors') & LOCKED and vm.lock_log == [],
      repr(vm.lock_log))

# ----------------------------------------------------------------------
if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL VSCONV TESTS PASSED")
