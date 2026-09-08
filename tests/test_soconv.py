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

Then the contingencies the table promises: the correct spelling of the
export's misspelled layer converting too, a wildcard row and an added
row behaving as rules (a destination the colour table does not name is
created in *soconv-default-color*), a frozen, switched-off destination
repaired rather than quietly drawn onto, and a highlight carrying
nothing of the export's being told so rather than converted.

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
# the table is the whole conversion
# ----------------------------------------------------------------------
print("soconv -- *soconv-map* is the whole conversion")


def fixed_export(vm):
    """The survey, plus a point on the CORRECTLY spelled anchor layer
    (an export that fixed its typo) and a note on a layer no rule
    names."""
    survey(vm)
    vm.loads(layer('Existing Anchors', 30))
    vm.loads(ent('POINT', 'Existing Anchors'))
    vm.loads(layer('Site Notes', 2))
    vm.loads(ent('TEXT', 'Site Notes', "'(40 . 6.0) '(1 . \"Gate\")"))


vm = fresh(fixed_export)
vm.run('c:SOCONV', [None, None])
check("the correct spelling, listed after the export's, converts too",
      layers_of(vm, 'POINT') == ['POINTS'] * 4, repr(layers_of(vm, 'POINT')))
check("a layer no row names is nobody's business",
      layers_of(vm, 'TEXT') == ['Site Notes'], repr(layers_of(vm, 'TEXT')))

vm = fresh(fixed_export)
vm.loads('(setq *soconv-map* (append *soconv-map*'
         ' \'(("Site Notes" "*" "SURVEY"))))')
vm.run('c:SOCONV', [None, None])
check("a row added to the table is a rule like any other",
      layers_of(vm, 'TEXT') == ['SURVEY'], repr(layers_of(vm, 'TEXT')))
check("its destination, which the colour table does not name, was created"
      " in *soconv-default-color*",
      grp(vm.recdata[vm.tablerecs['LAYER']['SURVEY']], 62) == 7,
      repr(vm.recdata[vm.tablerecs['LAYER']['SURVEY']]))
check("and it is counted in the done line", any(
    '1 -> SURVEY' in s for s in vm.printed), repr(vm.printed[-2:]))

vm = fresh(fixed_export)
vm.loads('(setq *soconv-map* \'(("Existing Anchor*" "*" "POINTS")))')
vm.run('c:SOCONV', [None, None])
check("a wildcard row takes both spellings at once",
      layers_of(vm, 'POINT')
      == ['LEICA_DISTO_POINT_ENTITY', 'POINTS', 'POINTS', 'POINTS'],
      repr(layers_of(vm, 'POINT')))
check("and rows no longer in the table are no longer rules",
      layers_of(vm, 'ARC') == ['Obstacles', 'Pool Perimeter']
      and layers_of(vm, 'MTEXT') == ['Dimensions'],
      repr((layers_of(vm, 'ARC'), layers_of(vm, 'MTEXT'))))
check("the message names only what the new table converts", any(
    'It converts Existing Anchor*.' in s for s in vm.printed)
    or any('Moved off Existing Anchorss, Existing Anchors' in s
           for s in vm.printed), repr(vm.printed[-2:]))

# ----------------------------------------------------------------------
# a frozen, switched-off destination
# ----------------------------------------------------------------------
print("soconv -- a frozen, switched-off destination is repaired, and says so")


def frozen_text(vm):
    survey(vm)
    vm.loads(layer('TEXT', -4, 1))       # off (negative colour) and frozen


vm = fresh(frozen_text)
vm.run('c:SOCONV', [None, None])
check("TEXT is thawed and switched on",
      not (layer_flags(vm, 'TEXT') & 1)
      and grp(vm.recdata[vm.tablerecs['LAYER']['TEXT']], 62) == 4,
      repr(vm.recdata[vm.tablerecs['LAYER']['TEXT']]))
check("and the run said so", any(
    'TEXT was off, frozen or locked' in s for s in vm.printed),
    repr(vm.printed[:3]))
check("the note landed on it", layers_of(vm, 'MTEXT') == ['TEXT'])

# ----------------------------------------------------------------------
# a highlight with nothing of the export's in it
# ----------------------------------------------------------------------
print("soconv -- a highlight carrying nothing of the export's is told so")
vm = fresh()
picked = [e for e in vm.entities
          if grp(vm.entdata[e], 8) in ('0', 'POINTS')]
vm.pickfirst = ['<ss>'] + picked
vm.run('c:SOCONV', [])
check("nothing moved",
      layers_of(vm, 'ARC') == ['Obstacles', 'Pool Perimeter']
      and layers_of(vm, 'POINT') == ['Existing Anchorss',
                                     'LEICA_DISTO_POINT_ENTITY', 'POINTS'],
      repr(layers_of(vm, 'POINT')))
check("and it says so rather than reporting a conversion of nothing", any(
    'nothing here is on the export' in s for s in vm.printed)
    and not any('SOCONV done' in s for s in vm.printed), repr(vm.printed))
check("no layer was created and nothing was unlocked",
      'TEXT' not in vm.tables['LAYER'] and vm.lock_log == [],
      repr((sorted(vm.tables['LAYER']), vm.lock_log)))

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
# the record, and SORECONV reading it back
# ----------------------------------------------------------------------
# SOCONV moves objects between layers; U undoes that while the session
# lasts, and nothing did once the drawing had been saved and reopened.
# So every object it moves carries a record of where it came from, and
# SORECONV is the other direction.
print("soconv -- every moved object carries a record of where it came from")


def xdata(d, app):
    """The items one application carries, [] when it is there and empty,
    None when it is not there at all."""
    g = grp(d, -3)
    if g is None:
        return None
    apps = [g] if (g and isinstance(g[0], str)) else g
    for a in apps:
        if a and a[0] == app:
            return a[1:]
    return None


def ename_where(vm, code, val):
    """The first live entity whose group CODE reads VAL.

    An ENAME, deliberately: entmod hands the VM a NEW alist for the
    entity, so a data list captured before a run is the state it was in
    then -- which is exactly the trap a record test would fall into,
    since writing the record IS an entmod.
    """
    for e in vm.entities:
        if e not in vm.deleted and grp(vm.entdata[e], code) == val:
            return e
    return None


def state(vm):
    """Every live entity as (type, layer, colour, linetype, lineweight,
    height, text) -- what a round trip has to reproduce."""
    return [(grp(d, 0), grp(d, 8), grp(d, 62), grp(d, 6), grp(d, 370),
             grp(d, 40), grp(d, 1)) for d in ents(vm)]


vm = fresh()
before = state(vm)
vm.run('c:SOCONV', [None, None])

moved = [d for d in ents(vm) if xdata(d, 'SOCONV')]
check("every object the run moved carries one, and nothing else does",
      len(moved) == 9 and len([d for d in ents(vm) if xdata(d, 'SOCONV')])
      == len(moved), repr(len(moved)))
rec = xdata([d for d in ents(vm) if grp(d, 0) == 'MTEXT'][0], 'SOCONV')
check("...naming the tool, the version, and the layer it came off",
      rec[0] == Dot(1000, 'SOCONV')
      and re.fullmatch(r'v\d+\.\d+', rec[1].b)
      and rec[2] == Dot(1000, 'Dimensions'), repr(rec))
check("...and that layer's own colour, for one PURGEd later",
      rec[4] == Dot(1070, 255), repr(rec))
check("with the forcing off it records no properties to put back",
      rec[5] == Dot(1070, 0) and rec[3] == Dot(1000, ''), repr(rec))
check("the done line offers the way back", any(
    'SORECONV moves it all back' in s for s in vm.printed), repr(vm.printed[-2:]))

print("soconv -- SORECONV puts the drawing back on the export's layers")
vm.printed = []
vm.run('c:SORECONV', [None, None])
check("every object is on the layer it arrived on", state(vm) == before,
      "before %r\nafter  %r" % (before, state(vm)))
check("and the record went with the move it described",
      not [d for d in ents(vm) if xdata(d, 'SOCONV')],
      repr([xdata(d, 'SOCONV') for d in ents(vm)]))
check("nothing was erased and nothing was drawn", len(ents(vm)) == 11)
check("the summary names the counts, per source layer", any(
    'SORECONV done: 9 object(s) put back -- 4 -> Pool Perimeter,'
    ' 2 -> POINTS' not in s for s in vm.printed) and any(
    'SORECONV done: 9 object(s) put back' in s for s in vm.printed),
    repr(vm.printed[-3:]))
check("...and says what it came off", any(
    'Off POOL, POINTS, TEXT, DIMENSION' in s for s in vm.printed),
    repr(vm.printed[-2:]))
check("one undo mark, opened and closed",
    vm.undo_log[-2:] == ['start', 'end'] and vm.undo_marks == 0,
    repr(vm.undo_log))
check("Dimensions is an OUTPUT layer for the revert, so it is left usable",
      not layer_flags(vm, 'Dimensions') & LOCKED and any(
          'Dimensions was off, frozen or locked' in s for s in vm.printed),
      repr(vm.printed[-4:]))
check("the global *error* is untouched", not error_global(vm))

vm.printed = []
vm.run('c:SORECONV', [None, None])
check("a second revert finds nothing and says what it undoes", any(
    'nothing here carries a SOCONV record' in s for s in vm.printed)
    and any('*soconv-record* off' in s for s in vm.printed), repr(vm.printed))

# ----------------------------------------------------------------------
# the forced properties, which are the only ones a record carries
# ----------------------------------------------------------------------
print("soconv -- with *soconv-force-bylayer* on, the properties come back too")

vm = fresh()
vm.loads('(entmake \'((0 . "LTYPE") (2 . "DASHED")))')
vm.loads('(entmake (list \'(0 . "LINE") \'(8 . "Obstacles")'
         ' \'(10 1.0 1.0 0.0) \'(11 9.0 9.0 0.0) \'(62 . 2)'
         ' \'(6 . "DASHED") \'(370 . 35)))')
vm.loads('(setq *soconv-force-bylayer* T)')
dashed = ename_where(vm, 6, 'DASHED')
was = (grp(vm.entdata[dashed], 62), grp(vm.entdata[dashed], 6),
       grp(vm.entdata[dashed], 370))
vm.run('c:SOCONV', [None, None])
rec = xdata(vm.entdata[dashed], 'SOCONV')
check("the record says the run forced BYLAYER, and what it overwrote",
      rec[5] == Dot(1070, 1) and rec[3] == Dot(1000, 'DASHED')
      and rec[6] == Dot(1070, 2) and rec[7] == Dot(1070, 35), repr(rec))
check("...and the forcing really did overwrite it",
      (grp(vm.entdata[dashed], 62), grp(vm.entdata[dashed], 6),
       grp(vm.entdata[dashed], 370)) == (256, 'ByLayer', -1),
      repr(vm.entdata[dashed]))
vm.run('c:SORECONV', [None, None])
now = (grp(vm.entdata[dashed], 62), grp(vm.entdata[dashed], 6),
       grp(vm.entdata[dashed], 370))
check("the revert puts the colour, linetype and lineweight back",
      now == was, repr((was, now)))
check("...and the layer with them",
      grp(vm.entdata[dashed], 8) == 'Obstacles')

# An object that arrived with NO colour of its own comes back with the
# explicit ByLayer that means the same thing -- the one thing the
# revert spells out rather than restores, and the header says so.
plain = vm.entdata[ename_where(vm, 0, 'MTEXT')]
check("an absent property comes back as the explicit ByLayer it meant",
      (grp(plain, 62), grp(plain, 6), grp(plain, 370))
      == (256, 'ByLayer', -1), repr(plain))

print("soconv -- a linetype that has been purged since leaves the job open")
vm = fresh()
vm.loads('(entmake (list \'(0 . "LINE") \'(8 . "Obstacles")'
         ' \'(10 1.0 1.0 0.0) \'(11 9.0 9.0 0.0) \'(62 . 2)'
         ' \'(6 . "GONE") \'(370 . 35)))')
vm.loads('(setq *soconv-force-bylayer* T)')
gone = ename_where(vm, 6, 'GONE')
vm.run('c:SOCONV', [None, None])
vm.printed = []
vm.run('c:SORECONV', [None, None])
check("the layer and the colour still come back",
      grp(vm.entdata[gone], 8) == 'Obstacles'
      and grp(vm.entdata[gone], 62) == 2, repr(vm.entdata[gone]))
check("the run names the linetype it could not load", any(
    'Linetype GONE is no longer loaded' in s for s in vm.printed),
    repr(vm.printed[-2:]))
check("and KEEPS that object's record, so running it again can finish it",
      xdata(vm.entdata[gone], 'SOCONV') is not None,
      repr(xdata(vm.entdata[gone], 'SOCONV')))
check("...while every finished object's record is gone",
      len([d for d in ents(vm) if xdata(d, 'SOCONV')]) == 1,
      repr(len([d for d in ents(vm) if xdata(d, 'SOCONV')])))

# ----------------------------------------------------------------------
# a source layer that was PURGEd, as the done line invites
# ----------------------------------------------------------------------
print("soconv -- a source layer purged on the tool's own advice is re-created")

vm = fresh()
vm.run('c:SOCONV', [None, None])
# PURGE, the way the done line says to: the layer records go, the
# objects have already left them
vm.loads('(setq *soconv-record* *soconv-record*)')
for name in ('POOL PERIMETER', 'OBSTACLES', 'DIMENSIONS'):
    vm.tables['LAYER'].discard(
        next(n for n in vm.tables['LAYER'] if n.upper() == name))
    vm.tablerecs['LAYER'].pop(name, None)
check("the fixture really purged them",
      not [n for n in vm.tables['LAYER'] if n.upper() == 'OBSTACLES'])
vm.printed = []
vm.run('c:SORECONV', [None, None])
check("the objects are back on layers the drawing no longer had",
      sorted(layers_of(vm, 'ARC')) == ['Obstacles', 'Pool Perimeter'],
      repr(layers_of(vm, 'ARC')))
check("...re-created with the colour the record kept off the layer",
      grp(vm.recdata[vm.tablerecs['LAYER']['OBSTACLES']], 62) == 51,
      repr(vm.recdata[vm.tablerecs['LAYER']['OBSTACLES']]))
check("...and the notes' layer with them",
      layers_of(vm, 'MTEXT') == ['Dimensions'], repr(layers_of(vm, 'MTEXT')))

# ----------------------------------------------------------------------
# the record can be switched off, and then there is nothing to undo from
# ----------------------------------------------------------------------
print("soconv -- *soconv-record* nil converts and writes nothing down")

vm = fresh()
vm.loads('(setq *soconv-record* nil)')
vm.run('c:SOCONV', [None, None])
check("the conversion still happens", layers_of(vm, 'ARC') == ['POOL', 'POOL'])
check("but nothing carries a record",
      not [d for d in ents(vm) if xdata(d, 'SOCONV')])
check("and the run says so rather than promising a revert", any(
    '*soconv-record* is off' in s for s in vm.printed), repr(vm.printed[-2:]))
vm.printed = []
vm.run('c:SORECONV', [None, None])
check("SORECONV then moves nothing and explains why", any(
    'nothing here carries a SOCONV record' in s for s in vm.printed)
    and layers_of(vm, 'ARC') == ['POOL', 'POOL'], repr(vm.printed))

# ----------------------------------------------------------------------
# the cut-short paths, as SOCONV's own
# ----------------------------------------------------------------------
print("soconv -- SORECONV cut short reaches its own handler")

vm = fresh()
vm.run('c:SOCONV', [None, None])
vm.handle_errors = True
vm.loads('(defun soconv:tally-line (tally) (soconv:no-such-helper tally))')
vm.run('c:SORECONV', [None, None])
check("the run is aborted through *error*, not a crash",
      len(vm.handled_errors) == 1
      and 'undefined function' in vm.handled_errors[0], repr(vm.handled_errors))
check("the handler closed the mark it opened",
      vm.undo_marks == 0 and vm.undo_log[-1] == 'end', repr(vm.undo_log))
check("the error is reported under the reverter's name", any(
    s.startswith('\nSORECONV error:') for s in vm.printed), repr(vm.printed[-3:]))
check("the global *error* is untouched afterwards", not error_global(vm))

vm = fresh()
vm.run('c:SOCONV', [None, None])
vm.handle_errors = True
was = state(vm)
vm.printed = []
vm.run('c:SORECONV', [None, esc])
check("Esc at the selection prompt is a quiet cancel",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0]
      and not any('SORECONV error' in s for s in vm.printed),
      repr(vm.printed[-2:]))
check("nothing was moved back", state(vm) == was)
check("the mark opened before the prompt is closed",
      vm.undo_marks == 0 and vm.undo_log[-1] == 'end', repr(vm.undo_log))

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
