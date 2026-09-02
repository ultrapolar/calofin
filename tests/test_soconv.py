"""Runtime tests for SOCONV: build a site-survey import the way the SO
export drops it, run the REAL command over it, and check that what came
out is the shop's layer scheme -- and ONLY that.

The tool is a layer remap and nothing else, which is the thing worth
pinning: the before/after sample it was written from moves 316 objects
and changes no other property of any of them, so a "cleanup" creeping
in here (a restyle, a forced BYLAYER, an erase) is a regression even
though it would look like an improvement.  So the checks below are as
much about what did NOT change -- the Leica points' explicit magenta,
the notes' height and text, the LINE on layer 0 -- as about what did.

The rest is the shape every command in the build shares and DRONE's
tests pin the same way: an error mid-run and an Esc at the selection
prompt both reach the command's OWN *error*, which has to put back the
locks the run took off and close the mark it opened.

Script values answer the interactive calls in order: None is Enter at
the pickfirst probe and again at the selection prompt, which sends the
tool to the whole drawing.  A function-valued answer runs when its
prompt is reached, which is how the Esc is delivered.

Run: python3 tests/test_soconv.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_soconv.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
SOCONV = (os.path.join(HERE, '..', 'shared', 'parts', 'SOCONV.lsp')
          if ROOT == 'shared'
          else os.path.join(HERE, '..', 'lisp', 'soconv', 'SOCONV.lsp'))
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
# the drawing, as the export drops it
# ----------------------------------------------------------------------

def layer(name, color, flags=0):
    return ('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
            ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
            ' \'(62 . %d) \'(6 . "Continuous")))' % (name, flags, color))


def ent(etype, lay, extra=''):
    return ('(entmake (list \'(0 . "%s") \'(8 . "%s") \'(10 1.0 1.0 0.0)%s))'
            % (etype, lay, (' ' + extra) if extra else ''))


LOCKED = 4

#: the export's layers, with the colours the sample DXF carries
EXPORT_LAYERS = (('Pool Perimeter', 80), ('Obstacles', 51),
                 ('LEICA_DISTO_POINT_ENTITY', 6),
                 ('Existing Anchorss', 30))


def survey(vm):
    """A survey the way SO exports it: pool outline and obstacles on
    their own layers, two kinds of point on two more, and the notes and
    dimensions sharing one `Dimensions`.  POOL and POINTS are in the
    drawing already -- POINTS LOCKED, which is the case the unlock
    exists for -- while TEXT and DIMENSION are not, so the run has to
    create them.  `Dimensions` is locked too: that one is not an output
    layer, so it has to be given its lock back."""
    for name, color in EXPORT_LAYERS:
        vm.loads(layer(name, color))
    vm.loads(layer('Dimensions', 255, LOCKED))
    vm.loads(layer('POOL', 1))
    vm.loads(layer('POINTS', 6, LOCKED))
    vm.loads(ent('ARC', 'Pool Perimeter', "'(40 . 79.0)"))
    vm.loads(ent('LINE', 'Pool Perimeter', "'(11 2.0 2.0 0.0)"))
    vm.loads(ent('ARC', 'Obstacles', "'(40 . 22.8)"))
    vm.loads(ent('LINE', 'Obstacles', "'(11 3.0 3.0 0.0)"))
    # the Leica points arrive carrying an explicit magenta; the anchor
    # points arrive BYLAYER.  Both spellings have to survive the move.
    vm.loads(ent('POINT', 'LEICA_DISTO_POINT_ENTITY', "'(62 . 6)"))
    vm.loads(ent('POINT', 'Existing Anchorss'))
    vm.loads(ent('MTEXT', 'Dimensions', "'(40 . 8.0) '(1 . \"Planter\")"))
    vm.loads(ent('DIMENSION', 'Dimensions', "'(3 . \"STANDARD\")"))
    # a leader the export left on Dimensions: no rule names LINE there,
    # so the catch-all row is what has to take it
    vm.loads(ent('LINE', 'Dimensions', "'(11 4.0 4.0 0.0)"))
    # and two things nothing may touch
    vm.loads(ent('LINE', '0', "'(11 5.0 5.0 0.0)"))
    vm.loads(ent('POINT', 'POINTS'))


def ents(vm, etype=None):
    return [vm.entdata[e] for e in vm.entities
            if e not in vm.deleted
            and (etype is None or grp(vm.entdata[e], 0) == etype)]


def layers_of(vm, etype):
    return sorted(grp(d, 8) for d in ents(vm, etype))


def layer_flags(vm, name):
    rec = vm.tablerecs['LAYER'][name.upper()]
    return grp(vm.recdata[rec], 70) or 0


def error_global(vm):
    """T when a function is left sitting in the GLOBAL *error*."""
    v = vm.globals.get(Sym('*error*'))
    return isinstance(v, tuple) or isinstance(v, list)


def fresh(build=survey):
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(SOCONV)
    build(vm)
    return vm


# ----------------------------------------------------------------------
# statics
# ----------------------------------------------------------------------
print("statics -- the handler is the command's own")
src = open(SOCONV, encoding='ascii').read()
check("no global *error* swap left",
      '-old-error*' not in src and re.search(r"\(setq\s+\*error\*", src) is None)
m = re.search(r"\(defun\s+[cC]:SOCONV\s*\(/([^)]*)\)", src)
check("*error* is a local of the command",
      m is not None and '*error*' in m.group(1).split())
check("the handler closes only a mark the run opened",
      "(if mark-open (vl-catch-all-apply 'vla-EndUndoMark" in src)
check("no run state in globals",
      '*soconv-doc*' not in src and '*soconv-unlocked*' not in src)

# ----------------------------------------------------------------------
# the conversion
# ----------------------------------------------------------------------
print("soconv -- the export's layers become the shop's")
vm = fresh()
vm.run('c:SOCONV', [None, None])

check("the perimeter and the obstacles are on POOL",
      layers_of(vm, 'ARC') == ['POOL', 'POOL']
      and layers_of(vm, 'LINE') == ['0', 'DIMENSION', 'POOL', 'POOL'],
      repr((layers_of(vm, 'ARC'), layers_of(vm, 'LINE'))))
check("both kinds of survey point are on POINTS",
      layers_of(vm, 'POINT') == ['POINTS', 'POINTS', 'POINTS'],
      repr(layers_of(vm, 'POINT')))
check("the note text is on TEXT", layers_of(vm, 'MTEXT') == ['TEXT'])
check("the dimension is on DIMENSION",
      layers_of(vm, 'DIMENSION') == ['DIMENSION'])
check("the leader left on Dimensions followed the dimensions, not the text",
      'DIMENSION' in layers_of(vm, 'LINE'), repr(layers_of(vm, 'LINE')))
check("the line on layer 0 was never anybody's business",
      '0' in layers_of(vm, 'LINE'))

# what did NOT change is the point of the tool
pts = ents(vm, 'POINT')
check("the Leica points keep the explicit magenta they arrived with",
      sorted(str(grp(d, 62)) for d in pts) == ['6', 'None', 'None'],
      repr([grp(d, 62) for d in pts]))
mt = ents(vm, 'MTEXT')[0]
check("the note keeps its height and its text",
      grp(mt, 40) == 8.0 and grp(mt, 1) == 'Planter', repr(mt))
check("nothing was erased and nothing was drawn", len(ents(vm)) == 11,
      repr(len(ents(vm))))
check("the dimension keeps its style", grp(ents(vm, 'DIMENSION')[0], 3)
      == 'STANDARD')

# the layers themselves
check("TEXT and DIMENSION, which the drawing lacked, were created",
      'TEXT' in vm.tables['LAYER'] and 'DIMENSION' in vm.tables['LAYER'])
check("POOL, which it had, was not recoloured",
      grp(vm.recdata[vm.tablerecs['LAYER']['POOL']], 62) == 1)
check("POINTS, an output layer, was repaired and left usable",
      not layer_flags(vm, 'POINTS') & LOCKED and any(
          'POINTS was off, frozen or locked' in s for s in vm.printed))
check("Dimensions, unlocked only for the run, is locked again",
      layer_flags(vm, 'Dimensions') & LOCKED)
check("and it really was unlocked and relocked, once each",
      vm.lock_log == [('DIMENSIONS', False), ('DIMENSIONS', True)],
      repr(vm.lock_log))
check("one undo mark, opened and closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("the global *error* is untouched after the run", not error_global(vm))
check("the summary line names the counts, in destination order", any(
    'SOCONV done: 9 object(s) moved -- 4 -> POOL, 2 -> POINTS, 1 -> TEXT,'
    ' 2 -> DIMENSION.' in s for s in vm.printed), repr(vm.printed[-2:]))
check("and names the layers to purge", any(
    'Pool Perimeter' in s and 'Existing Anchorss' in s and 'PURGE' in s
    for s in vm.printed), repr(vm.printed[-1:]))

# ----------------------------------------------------------------------
# a second run changes nothing
# ----------------------------------------------------------------------
print("soconv -- running it twice is running it once")
before = [(grp(d, 0), grp(d, 8), grp(d, 62)) for d in ents(vm)]
vm.printed = []
vm.run('c:SOCONV', [None, None])
check("nothing moves the second time",
      [(grp(d, 0), grp(d, 8), grp(d, 62)) for d in ents(vm)] == before)
check("and it says so rather than reporting a conversion", any(
    'nothing here is on the export' in s for s in vm.printed)
    and not any('SOCONV done' in s for s in vm.printed), repr(vm.printed))
check("the message names what it does convert", any(
    'Pool Perimeter' in s and 'LEICA_DISTO_POINT_ENTITY' in s
    for s in vm.printed), repr(vm.printed))
check("the mark is still opened and closed on that path",
      vm.undo_marks == 0 and vm.undo_log[-2:] == ['start', 'end'],
      repr(vm.undo_log))
check("a run with nothing to do creates no layers",
      'TEXT' in vm.tables['LAYER'])

# ----------------------------------------------------------------------
# only what is highlighted
# ----------------------------------------------------------------------
print("soconv -- a highlighted selection is what gets converted")
vm = fresh()
picked = [e for e in vm.entities
          if grp(vm.entdata[e], 8) == 'Pool Perimeter']
vm.loads('(sssetfirst nil nil)')
vm.pickfirst = ['<ss>'] + picked
vm.run('c:SOCONV', [])
check("the highlighted perimeter moved", layers_of(vm, 'ARC') == ['Obstacles',
                                                                  'POOL'],
      repr(layers_of(vm, 'ARC')))
check("and nothing outside the highlight did",
      layers_of(vm, 'POINT') == ['Existing Anchorss',
                                 'LEICA_DISTO_POINT_ENTITY', 'POINTS'],
      repr(layers_of(vm, 'POINT')))
check("only the layers that run needed were unlocked",
      vm.lock_log == [], repr(vm.lock_log))

# ----------------------------------------------------------------------
# the BYLAYER tunable
# ----------------------------------------------------------------------
print("soconv -- *soconv-force-bylayer* is the one way to change a property")
vm = fresh()
vm.loads('(setq *soconv-force-bylayer* T)')
vm.run('c:SOCONV', [None, None])
check("with it on, the Leica points' explicit colour goes BYLAYER",
      all(grp(d, 62) == 256 for d in ents(vm, 'POINT')
          if grp(d, 8) == 'POINTS' and grp(d, 62) is not None),
      repr([grp(d, 62) for d in ents(vm, 'POINT')]))
check("and the moves still happened", layers_of(vm, 'ARC') == ['POOL', 'POOL'])

# ----------------------------------------------------------------------
# a drawing that is not an SO export
# ----------------------------------------------------------------------
print("soconv -- a drawing with none of those layers is left alone")


def not_a_survey(vm):
    vm.loads(layer('POOL', 1))
    vm.loads(ent('LINE', 'POOL', "'(11 2.0 2.0 0.0)"))


vm = fresh(not_a_survey)
vm.run('c:SOCONV', [None, None])
check("nothing moved", layers_of(vm, 'LINE') == ['POOL'])
check("it says what it was looking for", any(
    'nothing here is on the export' in s for s in vm.printed), repr(vm.printed))
check("no layer was created for a run with nothing to do",
      'POINTS' not in vm.tables['LAYER'] and 'TEXT' not in vm.tables['LAYER'],
      repr(sorted(vm.tables['LAYER'])))
check("the mark was opened and closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0)

# ----------------------------------------------------------------------
# an error mid-run
# ----------------------------------------------------------------------
print("soconv -- an error mid-run reaches the command's own handler")
vm = fresh()
vm.handle_errors = True
# the move blows up on an unbound function, the way a typo or a missing
# helper dies at the command line
vm.loads('(defun soconv:tally-line (tally) (soconv:no-such-helper tally))')
vm.run('c:SOCONV', [None, None])
check("the run is aborted through *error*, not a crash",
      len(vm.handled_errors) == 1
      and 'undefined function' in vm.handled_errors[0],
      repr(vm.handled_errors))
check("the handler closed the mark it opened",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("the error is reported under the tool's name", any(
    s.startswith('\nSOCONV error:') for s in vm.printed), repr(vm.printed[-3:]))
check("the global *error* is still untouched afterwards", not error_global(vm))
check("no summary line for a run that did not finish", not any(
    'SOCONV done' in s for s in vm.printed))

print("soconv -- an error while the layers are unlocked puts the locks back")
vm = fresh()
vm.handle_errors = True
vm.loads('(defun soconv:force-bylayer (obj) (soconv:no-such-helper obj))')
vm.loads('(setq *soconv-force-bylayer* T)')
vm.run('c:SOCONV', [None, None])
check("aborted through *error*", len(vm.handled_errors) == 1,
      repr(vm.handled_errors))
check("the handler saw the unlocked layer and locked it again",
      layer_flags(vm, 'Dimensions') & LOCKED
      and vm.lock_log == [('DIMENSIONS', False), ('DIMENSIONS', True)],
      repr(vm.lock_log))
check("and closed the mark",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0)

# ----------------------------------------------------------------------
# Esc at the selection prompt
# ----------------------------------------------------------------------
print("soconv -- Esc at the selection prompt is a quiet cancel")
vm = fresh()
vm.handle_errors = True


def esc(vm):
    raise LispError('Function cancelled', vm)


vm.run('c:SOCONV', [None, esc])
check("the cancel went through the handler",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0])
check("nothing was changed",
      layers_of(vm, 'ARC') == ['Obstacles', 'Pool Perimeter'],
      repr(layers_of(vm, 'ARC')))
check("the mark opened before the prompt is closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("a plain cancel prints no error line", not any(
    'SOCONV error' in s for s in vm.printed), repr(vm.printed[-2:]))
check("the layers were never unlocked, so nothing to relock",
      layer_flags(vm, 'Dimensions') & LOCKED and vm.lock_log == [],
      repr(vm.lock_log))

# ----------------------------------------------------------------------
# the version reporter
# ----------------------------------------------------------------------
print("soconv -- the version reporter")
vm = fresh()
vm.run('c:SOCONVVER', [])
check("SOCONVVER prints the loaded version", any(
    re.search(r'SOCONV v\d+\.\d+', s) for s in vm.printed), repr(vm.printed))

# ----------------------------------------------------------------------
if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL SOCONV TESTS PASSED")
