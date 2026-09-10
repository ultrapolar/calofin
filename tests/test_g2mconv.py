"""Runtime tests for G2MCONV: build a plan the way the G2M architect
exports it, run the REAL command over it, and check that what came out
is the shop's drawing.

Unlike SOCONV, which is a layer remap and nothing else, this tool
CHANGES things on the way past -- and each change is there because a
layer move alone would leave an override outranking the layer or style
it now sits on.  So the checks below are as much about the four
overrides as about the layers:

  * the explicit "Continuous" comes off the geometry, and the stairs'
    HIDDEN2 becomes the shop's DASHED2 rather than going ByLayer with
    everything else -- a stair drawn solid on POOL is a wall;
  * the notes take the shop text style AND height, or neither;
  * the dimensions take the shop dimension style, lose their ACAD /
    DSTYLE override block, and stop being annotative;
  * an MTEXT's OWN "ACAD" xdata (ACAD_MTEXT_DEFINED_HEIGHT) is not the
    dimension override block and must survive -- deleting a whole
    application by name is how the dimension step works, so the test
    that it never reaches a note is the test that the step is aimed.

Then the shape every command in the build shares and DRONE's and
SOCONV's tests pin the same way: an error mid-run and an Esc at the
selection prompt both reach the command's OWN *error*, which has to put
back the locks the run took off and close the mark it opened.

And the round trip, which is the reason the record exists: G2MCONV
changes eight things about an object, so G2MRECONV has to put eight
things back, and a revert that restores the layer and forgets the text
height is worse than no revert at all.

Script values answer the interactive calls in order: None is Enter at
the pickfirst probe and again at the selection prompt, which sends the
tool to the whole drawing.  A function-valued answer runs when its
prompt is reached, which is how the Esc is delivered.

Run: python3 tests/test_g2mconv.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_g2mconv.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
G2MCONV = (os.path.join(HERE, '..', 'shared', 'parts', 'G2MCONV.lsp')
           if ROOT == 'shared'
           else os.path.join(HERE, '..', 'lisp', 'g2mconv', 'G2MCONV.lsp'))
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


# ----------------------------------------------------------------------
# the drawing, as the architect exports it
# ----------------------------------------------------------------------

WALL = '1 A POOL WALL - PARED PISCINA'
STAIRS = 'A-STAIRS - GRADAS'
NOTES = 'A-ANNO-TEXT - TEXTO'
DIMS = 'A-ANNO-DIMS - DIMENSIONES'

LOCKED = 4

#: the export's layers, with the colours the sample DXF carries
EXPORT_LAYERS = ((WALL, 43), (STAIRS, 1), (NOTES, 7))

#: an annotative object's xdata: AnnotativeData { <class> <flag> }
ANNO = ('\'(-3 ("AcadAnnotative" (1000 . "AnnotativeData") (1002 . "{")'
        ' (1070 . 1) (1070 . %d) (1002 . "}")))')

#: what the architect's dimensions carry as well -- the override block
#: that outranks whatever style name they are given
DSTYLE = ('(1001 . "ACAD") (1000 . "DSTYLE") (1002 . "{") (1070 . 70)'
          ' (1070 . 256) (1002 . "}")')


def layer(name, color, flags=0, ltype='CONTINUOUS'):
    return ('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
            ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
            ' \'(62 . %d) \'(6 . "%s")))' % (name, flags, color, ltype))


def style(name):
    return ('(entmake (list \'(0 . "STYLE") \'(100 . "AcDbSymbolTableRecord")'
            ' \'(100 . "AcDbTextStyleTableRecord") \'(2 . "%s") \'(70 . 0)))'
            % name)


def ent(etype, lay, extra=''):
    return ('(entmake (list \'(0 . "%s") \'(8 . "%s") \'(10 1.0 1.0 0.0)%s))'
            % (etype, lay, (' ' + extra) if extra else ''))


def poly(lay, extra=''):
    """AutoCAD refuses a polyline of fewer than two vertices, and so does
    the VM, so these carry the two they need."""
    return ('(entmake (list \'(0 . "LWPOLYLINE") \'(8 . "%s") \'(90 . 2)'
            ' \'(10 1.0 1.0) \'(10 9.0 1.0)%s))'
            % (lay, (' ' + extra) if extra else ''))


def plan(vm):
    """A plan the way G2M exports it: the pool wall drawn solid, the
    stairs in the architect's HIDDEN2, the standalone notes on one
    annotation layer and the dimensions, their leaders and their own
    notes sharing another.  POOL is in the drawing already -- LOCKED,
    which is the case the unlock exists for -- while TEXT and DIMENSION
    are not, so the run has to create them.  The dims layer is locked
    too: that one is not an output layer, so it has to be given its
    lock back."""
    for name, color in EXPORT_LAYERS:
        vm.loads(layer(name, color))
    vm.loads(layer(DIMS, 7, LOCKED))
    vm.loads(layer('POOL', 1, LOCKED))
    vm.loads(style('Attributes'))
    vm.loads(style('Century Gothic'))
    vm.loads(style('AT_Standard Text'))
    # the architect's own linetype and dimension style: they are in the
    # drawing the plan arrives in, and the conversion purges neither, so
    # they are still there when G2MRECONV goes looking for them
    vm.tables['LTYPE'].add('HIDDEN2')
    vm.tables['DIMSTYLE'].add('AT_Standard Dimensions')

    # the wall: solid, with the export's pointless explicit Continuous
    vm.loads(poly(WALL, "'(6 . \"Continuous\")"))
    vm.loads(poly(WALL, "'(6 . \"Continuous\")"))
    # the stairs: the architect's hidden pattern, which has to survive
    # as the shop's dashed one
    vm.loads(poly(STAIRS, "'(6 . \"HIDDEN2\")"))
    for etype in ('ARC', 'LINE'):
        vm.loads(ent(etype, STAIRS, "'(6 . \"HIDDEN2\") '(40 . 12.0)"))
    # the standalone notes
    for txt in ('GRASS', 'PEA GRAVEL'):
        vm.loads(ent('MTEXT', NOTES, '\'(7 . "Century Gothic")'
                     ' \'(40 . 4.384351009381576) \'(41 . 41.33)'
                     ' \'(1 . "%s") %s' % (txt, ANNO % 0)))
    # and what the architect left on the dimension layer: a note, three
    # leaders, an arc no rule names by type, and the dimensions -- each
    # of them annotative and carrying a style override
    vm.loads(ent('MTEXT', DIMS, '\'(7 . "AT_Standard Text") \'(40 . 4.5)'
                 ' \'(1 . "NATURAL FIELDSTONE BOULDERS")'
                 ' \'(-3 ("ACAD" (1000 . "ACAD_MTEXT_DEFINED_HEIGHT_BEGIN")'
                 ' (1070 . 46) (1040 . 0.0)'
                 ' (1000 . "ACAD_MTEXT_DEFINED_HEIGHT_END")))'))
    for _ in range(3):
        vm.loads(ent('MULTILEADER', DIMS, "'(6 . \"Continuous\") '(40 . 48.0)"))
    vm.loads(ent('ARC', DIMS, "'(6 . \"Continuous\") '(40 . 9.0)"))
    for _ in range(2):
        vm.loads(ent('DIMENSION', DIMS,
                     '\'(6 . "Continuous") \'(3 . "AT_Standard Dimensions")'
                     ' \'(-3 ("AcadAnnotative" (1000 . "AnnotativeData")'
                     ' (1002 . "{") (1070 . 1) (1070 . 1) (1002 . "}"))'
                     ' ("ACAD" (1000 . "DSTYLE") (1002 . "{") (1070 . 70)'
                     ' (1070 . 256) (1002 . "}")))'))
    # and two things nothing may touch
    vm.loads(ent('LINE', '0', "'(11 5.0 5.0 0.0)"))
    vm.loads(poly('POOL'))


def ents(vm, etype=None):
    return [vm.entdata[e] for e in vm.entities
            if e not in vm.deleted
            and (etype is None or grp(vm.entdata[e], 0) == etype)]


def layers_of(vm, etype):
    return sorted(grp(d, 8) for d in ents(vm, etype))


def on(vm, lay, etype=None):
    return [d for d in ents(vm, etype) if grp(d, 8) == lay]


def layer_flags(vm, name):
    rec = vm.tablerecs['LAYER'][name.upper()]
    return grp(vm.recdata[rec], 70) or 0


def error_global(vm):
    """T when a function is left sitting in the GLOBAL *error*."""
    v = vm.globals.get(Sym('*error*'))
    return isinstance(v, tuple) or isinstance(v, list)


def fresh(build=plan):
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(G2MCONV)
    build(vm)
    return vm


def state(vm):
    """Every live entity as (type, layer, colour, linetype, lineweight,
    ltscale, style, height, text, annotative flag, ACAD xdata) -- what a
    round trip has to reproduce."""
    return [(grp(d, 0), grp(d, 8), grp(d, 62), grp(d, 6), grp(d, 370),
             grp(d, 48), grp(d, 7), grp(d, 40), grp(d, 1), grp(d, 3),
             xdata(d, 'AcadAnnotative'), xdata(d, 'ACAD')) for d in ents(vm)]


def anno_flag(d):
    """The SECOND 1070 in the AcadAnnotative block -- the flag; the
    first is the block's class number."""
    items = xdata(d, 'AcadAnnotative')
    seen = [p.b for p in (items or []) if isinstance(p, Dot) and p.a == 1070]
    return seen[1] if len(seen) > 1 else None


# ----------------------------------------------------------------------
# statics
# ----------------------------------------------------------------------
print("statics -- the handler is the command's own")
src = open(G2MCONV, encoding='ascii').read()
check("no global *error* swap left",
      '-old-error*' not in src and re.search(r"\(setq\s+\*error\*", src) is None)
for cmd in ('G2MCONV', 'G2MRECONV'):
    m = re.search(r"\(defun\s+[cC]:%s\s*\(/([^)]*)\)" % cmd, src)
    check("*error* is a local of c:%s" % cmd,
          m is not None and '*error*' in m.group(1).split())
check("the handler closes only a mark the run opened",
      "(if mark-open (vl-catch-all-apply 'vla-EndUndoMark" in src)
check("no run state in globals",
      '*g2mconv-doc*' not in src and '*g2mconv-unlocked*' not in src)

# ----------------------------------------------------------------------
# the conversion
# ----------------------------------------------------------------------
print("g2mconv -- the export's layers become the shop's")
vm = fresh()
vm.run('c:G2MCONV', [None, None])

check("the wall and the stairs are one drawing on POOL",
      layers_of(vm, 'LWPOLYLINE') == ['POOL'] * 4
      and layers_of(vm, 'LINE') == ['0', 'POOL'],
      repr((layers_of(vm, 'LWPOLYLINE'), layers_of(vm, 'LINE'))))
check("the standalone notes are on TEXT",
      sorted(grp(d, 1) for d in on(vm, 'TEXT', 'MTEXT'))
      == ['GRASS', 'NATURAL FIELDSTONE BOULDERS', 'PEA GRAVEL'],
      repr(layers_of(vm, 'MTEXT')))
check("the leaders followed the notes onto TEXT, not the dimensions",
      layers_of(vm, 'MULTILEADER') == ['TEXT'] * 3,
      repr(layers_of(vm, 'MULTILEADER')))
check("the dimensions are on DIMENSION",
      layers_of(vm, 'DIMENSION') == ['DIMENSION'] * 2)
check("the arc the architect left on the dimension layer went with them,"
      " because no row names it by type",
      layers_of(vm, 'ARC') == ['DIMENSION', 'POOL'],
      repr(layers_of(vm, 'ARC')))
check("the line on layer 0 was never anybody's business",
      '0' in layers_of(vm, 'LINE'))
check("nothing was erased and nothing was drawn", len(ents(vm)) == 16,
      repr(len(ents(vm))))

# 1. appearance
print("g2mconv -- the appearance follows the layer it moved to")
wall = [d for d in on(vm, 'POOL', 'LWPOLYLINE') if xdata(d, 'G2MCONV')
        and grp(d, 6) != 'DASHED2']
stairs = [d for d in ents(vm) if xdata(d, 'G2MCONV')
          and grp(d, 8) == 'POOL' and d not in wall]
check("the wall's pointless explicit Continuous is gone -- it is ByLayer now",
      all(grp(d, 6) == 'ByLayer' for d in wall) and len(wall) == 2,
      repr([grp(d, 6) for d in wall]))
check("...and carries the shop's linetype scale",
      all(grp(d, 48) == 0.4 for d in wall), repr([grp(d, 48) for d in wall]))
check("the stairs' HIDDEN2 became the shop's DASHED2, not ByLayer",
      len(stairs) == 3 and all(grp(d, 6) == 'DASHED2' for d in stairs),
      repr([grp(d, 6) for d in stairs]))
check("...and kept their own scale, which the shop pattern is already sized"
      " for",
      all(grp(d, 48) is None for d in stairs),
      repr([grp(d, 48) for d in stairs]))
check("DASHED2, which the drawing had not got, was created",
      'DASHED2' in vm.tables['LTYPE'], repr(sorted(vm.tables['LTYPE'])))
check("colour and lineweight went BYLAYER on everything moved",
      all(grp(d, 62) == 256 and grp(d, 370) == -1
          for d in ents(vm) if grp(d, 8) in ('POOL', 'TEXT', 'DIMENSION')
          and xdata(d, 'G2MCONV')),
      repr([(grp(d, 62), grp(d, 370)) for d in on(vm, 'POOL')]))

# 2. the notes
print("g2mconv -- the notes take the shop's text style and height")
notes = on(vm, 'TEXT', 'MTEXT')
check("every note is on the shop text style",
      all(grp(d, 7) == 'Attributes' for d in notes),
      repr([grp(d, 7) for d in notes]))
check("...at the shop text height, not the architect's viewport-scaled one",
      all(grp(d, 40) == 9.5 for d in notes), repr([grp(d, 40) for d in notes]))
check("the MTEXT box is left to AutoCAD rather than guessed at",
      all(grp(d, 41) in (41.33, None) for d in notes),
      repr([grp(d, 41) for d in notes]))
check("a note's OWN ACAD xdata is not the dimension override block, and"
      " survives",
      any(xdata(d, 'ACAD') for d in notes),
      repr([xdata(d, 'ACAD') for d in notes]))

# 3. the dimensions
print("g2mconv -- the dimensions take the shop's style, and lose what"
      " outranked it")
dims = on(vm, 'DIMENSION', 'DIMENSION')
check("every dimension is on the shop dimension style",
      all(grp(d, 3) == 'STANDARD' for d in dims), repr([grp(d, 3) for d in dims]))
check("...with the ACAD / DSTYLE override block removed",
      all(not xdata(d, 'ACAD') for d in dims),
      repr([xdata(d, 'ACAD') for d in dims]))
check("...and no longer annotative",
      all(anno_flag(d) == 0 for d in dims), repr([anno_flag(d) for d in dims]))
check("the block itself is still there, only its flag turned off -- the"
      " first 1070 is its class number, not ours to touch",
      all(len([p for p in xdata(d, 'AcadAnnotative')
               if isinstance(p, Dot) and p.a == 1070]) == 2 for d in dims),
      repr([xdata(d, 'AcadAnnotative') for d in dims]))
check("a note that arrived with the flag already off is left where it is",
      all(anno_flag(d) == 0 for d in notes if xdata(d, 'AcadAnnotative')))

# the layers themselves
print("g2mconv -- the layers, and the locks")
check("TEXT and DIMENSION, which the drawing lacked, were created",
      'TEXT' in vm.tables['LAYER'] and 'DIMENSION' in vm.tables['LAYER'])
check("POOL, which it had, was not recoloured",
      grp(vm.recdata[vm.tablerecs['LAYER']['POOL']], 62) == 1)
check("POOL, an output layer, was repaired and left usable",
      not layer_flags(vm, 'POOL') & LOCKED and any(
          'POOL was off, frozen or locked' in s for s in vm.printed))
check("the dimension layer, unlocked only for the run, is locked again",
      layer_flags(vm, DIMS) & LOCKED)
check("and it really was unlocked and relocked, once each -- POOL is a"
      " DESTINATION, repaired for good before the unlock sweep looks",
      vm.lock_log == [(DIMS.upper(), False), (DIMS.upper(), True)],
      repr(vm.lock_log))
check("one undo mark, opened and closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("the global *error* is untouched after the run", not error_global(vm))
check("the summary line names the counts, in destination order", any(
    'G2MCONV done: 14 object(s) moved -- 5 -> POOL, 6 -> TEXT,'
    ' 3 -> DIMENSION.' in s for s in vm.printed), repr(vm.printed[-5:]))
check("and says what it did to the notes and the dimensions", any(
    'restyled to Attributes at 9.50' in s for s in vm.printed)
    and any('put on STANDARD, style overrides removed' in s
            for s in vm.printed), repr(vm.printed[-5:]))
check("and names the layers to purge", any(
    WALL in s and DIMS in s and 'PURGE' in s for s in vm.printed),
    repr(vm.printed[-2:]))

# ----------------------------------------------------------------------
# a second run changes nothing
# ----------------------------------------------------------------------
print("g2mconv -- running it twice is running it once")
before = state(vm)
vm.printed = []
vm.run('c:G2MCONV', [None, None])
check("nothing moves the second time", state(vm) == before)
check("and it says so rather than reporting a conversion", any(
    'nothing here is on the export' in s for s in vm.printed)
    and not any('G2MCONV done' in s for s in vm.printed), repr(vm.printed))
check("the message names what it does convert", any(
    WALL in s and STAIRS in s for s in vm.printed), repr(vm.printed))

# ----------------------------------------------------------------------
# only what is highlighted
# ----------------------------------------------------------------------
print("g2mconv -- a highlighted selection is what gets converted")
vm = fresh()
picked = [e for e in vm.entities if grp(vm.entdata[e], 8) == WALL]
vm.loads('(sssetfirst nil nil)')
vm.pickfirst = ['<ss>'] + picked
vm.run('c:G2MCONV', [])
check("the highlighted wall moved, and the stairs stayed where they were",
      layers_of(vm, 'LWPOLYLINE') == [STAIRS, 'POOL', 'POOL', 'POOL'],
      repr(layers_of(vm, 'LWPOLYLINE')))
check("and nothing outside the highlight did",
      layers_of(vm, 'MULTILEADER') == [DIMS] * 3,
      repr(layers_of(vm, 'MULTILEADER')))
check("no layer needed unlocking for that run -- POOL is repaired as a"
      " destination and the wall layer was never locked",
      vm.lock_log == [], repr(vm.lock_log))
check("and no layer the run never reached was created",
      'TEXT' not in vm.tables['LAYER'] and 'DIMENSION' not in vm.tables['LAYER'],
      repr(sorted(vm.tables['LAYER'])))

# ----------------------------------------------------------------------
# the tunables
# ----------------------------------------------------------------------
print("g2mconv -- *g2mconv-map* is the whole conversion")
vm = fresh()
vm.loads('(setq *g2mconv-map* (subst \'("%s" "TEXT,MTEXT" "TEXT" "ByLayer" 0.4)'
         ' \'("%s" "TEXT,MTEXT,MULTILEADER" "TEXT" "ByLayer" 0.4)'
         ' *g2mconv-map*))' % (DIMS, DIMS))
vm.run('c:G2MCONV', [None, None])
check("dropping MULTILEADER from the text row sends the leaders to"
      " DIMENSION instead -- the one line that settles the judgement call",
      layers_of(vm, 'MULTILEADER') == ['DIMENSION'] * 3,
      repr(layers_of(vm, 'MULTILEADER')))
check("and the notes on that layer still go to TEXT",
      'TEXT' in layers_of(vm, 'MTEXT'), repr(layers_of(vm, 'MTEXT')))

vm = fresh()
vm.loads('(setq *g2mconv-map* \'(("A-*" "*" "SURVEY" nil nil)))')
vm.run('c:G2MCONV', [None, None])
check("a wildcard row takes both A- layers at once",
      layers_of(vm, 'MULTILEADER') == ['SURVEY'] * 3
      and sorted(set(layers_of(vm, 'MTEXT'))) == ['SURVEY'],
      repr((layers_of(vm, 'MULTILEADER'), layers_of(vm, 'MTEXT'))))
check("its destination, which the colour table does not name, was created"
      " in *g2mconv-default-color*",
      grp(vm.recdata[vm.tablerecs['LAYER']['SURVEY']], 62) == 7,
      repr(vm.recdata[vm.tablerecs['LAYER']['SURVEY']]))
check("a nil linetype column leaves the linetype alone",
      all(grp(d, 6) == 'HIDDEN2' for d in ents(vm) if grp(d, 8) in ('POOL', 'SURVEY', STAIRS)
          and grp(d, 6) in ('HIDDEN2', 'DASHED2')),
      repr([grp(d, 6) for d in ents(vm) if grp(d, 8) in ('POOL', 'SURVEY', STAIRS)
          and grp(d, 6) in ('HIDDEN2', 'DASHED2')]))
check("and a nil scale column writes no scale",
      all(grp(d, 48) is None for d in ents(vm)),
      repr([grp(d, 48) for d in ents(vm)]))
check("rows no longer in the table are no longer rules",
      layers_of(vm, 'LWPOLYLINE') == [WALL, WALL, 'POOL', 'SURVEY'],
      repr(layers_of(vm, 'LWPOLYLINE')))

print("g2mconv -- *g2mconv-force-bylayer* is the switch for the other two")
vm = fresh()
vm.loads(poly(WALL, "'(62 . 5) '(370 . 30)"))
vm.loads('(setq *g2mconv-force-bylayer* nil)')
vm.run('c:G2MCONV', [None, None])
check("with it off, an explicit colour and lineweight come through untouched",
      any(grp(d, 62) == 5 and grp(d, 370) == 30 for d in on(vm, 'POOL')),
      repr([(grp(d, 62), grp(d, 370)) for d in on(vm, 'POOL')]))
check("and the linetype, which is the map's column and not this switch's,"
      " still moved",
      all(grp(d, 6) == 'DASHED2' for d in ents(vm) if grp(d, 8) in ('POOL', 'SURVEY', STAIRS)
          and grp(d, 6) in ('HIDDEN2', 'DASHED2')))

# ----------------------------------------------------------------------
# a drawing whose template is missing the shop's styles
# ----------------------------------------------------------------------
print("g2mconv -- a drawing without the shop styles is told so, not"
      " half-converted")


def bare(vm):
    """The plan in a drawing carrying neither the shop text style nor a
    STANDARD dimension style."""
    plan(vm)
    vm.tables['STYLE'].discard('Attributes')
    vm.tables['DIMSTYLE'].discard('STANDARD')


vm = fresh(bare)
vm.run('c:G2MCONV', [None, None])
notes = on(vm, 'TEXT', 'MTEXT')
dims = on(vm, 'DIMENSION', 'DIMENSION')
check("the notes still moved layer", len(notes) == 3, repr(layers_of(vm, 'MTEXT')))
check("...but kept the architect's style AND height -- a height belongs with"
      " the style it was set in",
      all(grp(d, 7) in ('Century Gothic', 'AT_Standard Text') for d in notes)
      and all(grp(d, 40) in (4.384351009381576, 4.5) for d in notes),
      repr([(grp(d, 7), grp(d, 40)) for d in notes]))
check("the dimensions kept their style and their overrides",
      all(grp(d, 3) == 'AT_Standard Dimensions' for d in dims)
      and all(xdata(d, 'ACAD') for d in dims),
      repr([(grp(d, 3), xdata(d, 'ACAD')) for d in dims]))
check("and the run says so once for each, by name", any(
    'has no "Attributes" style' in s for s in vm.printed)
    and any('has no "STANDARD" dimension style' in s for s in vm.printed),
    repr(vm.printed[-5:]))
check("the appearance step, which needs no table, happened anyway",
      all(grp(d, 48) == 0.4 for d in notes), repr([grp(d, 48) for d in notes]))

print("g2mconv -- a linetype it cannot make is named, not failed on")
vm = fresh()
vm.loads('(setq *g2mconv-make-dashed2* nil)')
vm.run('c:G2MCONV', [None, None])
check("the stairs kept the linetype they arrived with",
      all(grp(d, 6) == 'HIDDEN2' for d in ents(vm) if grp(d, 8) in ('POOL', 'SURVEY', STAIRS)
          and grp(d, 6) in ('HIDDEN2', 'DASHED2')),
      repr([grp(d, 6) for d in ents(vm) if grp(d, 8) in ('POOL', 'SURVEY', STAIRS)
          and grp(d, 6) in ('HIDDEN2', 'DASHED2')]))
check("...and still moved layer", layers_of(vm, 'LWPOLYLINE') == ['POOL'] * 4)
check("and the run names the linetype to load", any(
    'Linetype DASHED2 is not loaded' in s for s in vm.printed),
    repr(vm.printed[-4:]))

# ----------------------------------------------------------------------
# a drawing that is not a G2M export
# ----------------------------------------------------------------------
print("g2mconv -- a drawing with none of those layers is left alone")


def not_a_plan(vm):
    vm.loads(layer('POOL', 1))
    vm.loads(ent('LINE', 'POOL', "'(11 2.0 2.0 0.0)"))


vm = fresh(not_a_plan)
vm.run('c:G2MCONV', [None, None])
check("nothing moved", layers_of(vm, 'LINE') == ['POOL'])
check("it says what it was looking for", any(
    'nothing here is on the export' in s for s in vm.printed), repr(vm.printed))
check("no layer was created for a run with nothing to do",
      'TEXT' not in vm.tables['LAYER'] and 'DIMENSION' not in vm.tables['LAYER'],
      repr(sorted(vm.tables['LAYER'])))
check("the mark was opened and closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0)

# ----------------------------------------------------------------------
# a frozen, switched-off destination
# ----------------------------------------------------------------------
print("g2mconv -- a frozen, switched-off destination is repaired, and says so")


def frozen_text(vm):
    plan(vm)
    vm.loads(layer('TEXT', -4, 1))       # off (negative colour) and frozen


vm = fresh(frozen_text)
vm.run('c:G2MCONV', [None, None])
check("TEXT is thawed and switched on",
      not (layer_flags(vm, 'TEXT') & 1)
      and grp(vm.recdata[vm.tablerecs['LAYER']['TEXT']], 62) == 4,
      repr(vm.recdata[vm.tablerecs['LAYER']['TEXT']]))
check("and the run said so", any(
    'TEXT was off, frozen or locked' in s for s in vm.printed),
    repr(vm.printed[:3]))
check("the notes landed on it", len(on(vm, 'TEXT', 'MTEXT')) == 3)

# ----------------------------------------------------------------------
# an error mid-run
# ----------------------------------------------------------------------
print("g2mconv -- an error mid-run reaches the command's own handler")
vm = fresh()
vm.handle_errors = True
# the report blows up on an unbound function, the way a typo or a
# missing helper dies at the command line
vm.loads('(defun g2m:tally-line (tally) (g2m:no-such-helper tally))')
vm.run('c:G2MCONV', [None, None])
check("the run is aborted through *error*, not a crash",
      len(vm.handled_errors) == 1
      and 'undefined function' in vm.handled_errors[0],
      repr(vm.handled_errors))
check("the handler closed the mark it opened",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("the error is reported under the tool's name", any(
    s.startswith('\nG2MCONV error:') for s in vm.printed), repr(vm.printed[-3:]))
check("the global *error* is still untouched afterwards", not error_global(vm))
check("no summary line for a run that did not finish", not any(
    'G2MCONV done' in s for s in vm.printed))

print("g2mconv -- an error while the layers are unlocked puts the locks back")
vm = fresh()
vm.handle_errors = True
vm.loads('(defun g2m:restyle-dim (ent style app) (g2m:no-such-helper ent))')
vm.run('c:G2MCONV', [None, None])
check("aborted through *error*", len(vm.handled_errors) == 1,
      repr(vm.handled_errors))
check("the handler saw the unlocked layer and locked it again",
      layer_flags(vm, DIMS) & LOCKED
      and vm.lock_log == [(DIMS.upper(), False), (DIMS.upper(), True)],
      repr(vm.lock_log))
check("and closed the mark",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0)

# ----------------------------------------------------------------------
# Esc at the selection prompt
# ----------------------------------------------------------------------
print("g2mconv -- Esc at the selection prompt is a quiet cancel")
vm = fresh()
vm.handle_errors = True


def esc(vm):
    raise LispError('Function cancelled', vm)


was = state(vm)
vm.run('c:G2MCONV', [None, esc])
check("the cancel went through the handler",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0])
check("nothing was changed", state(vm) == was)
check("the mark opened before the prompt is closed",
      vm.undo_log == ['start', 'end'] and vm.undo_marks == 0,
      repr(vm.undo_log))
check("a plain cancel prints no error line", not any(
    'G2MCONV error' in s for s in vm.printed), repr(vm.printed[-2:]))
check("the layers were never unlocked, so nothing to relock",
      layer_flags(vm, DIMS) & LOCKED and vm.lock_log == [], repr(vm.lock_log))

# ----------------------------------------------------------------------
# the record, and G2MRECONV reading it back
# ----------------------------------------------------------------------
print("g2mconv -- every moved object carries a record of what it was")
vm = fresh()
was = state(vm)
vm.run('c:G2MCONV', [None, None])

moved = [d for d in ents(vm) if xdata(d, 'G2MCONV')]
check("every object the run moved carries one, and nothing else does",
      len(moved) == 14, repr(len(moved)))
rec = xdata(on(vm, 'DIMENSION', 'DIMENSION')[0], 'G2MCONV')
check("...naming the tool, the version, and the layer it came off",
      rec[0] == Dot(1000, 'G2MCONV')
      and re.fullmatch(r'v\d+\.\d+', rec[1].b)
      and rec[2] == Dot(1000, DIMS), repr(rec))
check("...the dimension style it had, and its annotative flag",
      rec[4] == Dot(1000, 'AT_Standard Dimensions') and rec[9] == Dot(1070, 1),
      repr(rec))
check("...and the whole override block behind the fixed part, verbatim",
      rec[12] == Dot(1070, 1)
      and [p.b for p in rec[13:] if isinstance(p, Dot)]
      == ['DSTYLE', '{', 70, 256, '}'], repr(rec[12:]))
note = [d for d in on(vm, 'TEXT', 'MTEXT') if grp(d, 1) == 'GRASS'][0]
nrec = xdata(note, 'G2MCONV')
check("a note's record keeps the text style and height it lost",
      nrec[5] == Dot(1000, 'Century Gothic')
      and nrec[11] == Dot(1040, 4.384351009381576), repr(nrec))
check("...and the linetype scale it never had, as the 1.0 that means the"
      " same thing", nrec[10] == Dot(1040, 1.0), repr(nrec))
check("an object with no annotative block at all records -1, not a flag it"
      " has not got",
      xdata([d for d in on(vm, 'POOL', 'ARC')][0], 'G2MCONV')[9]
      == Dot(1070, -1),
      repr(xdata([d for d in on(vm, 'POOL', 'ARC')][0], 'G2MCONV')))

print("g2mreconv -- the round trip, every step of it")
vm.printed = []
vm.run('c:G2MRECONV', [None, None])
now = state(vm)
check("every object is back on the layer it came off",
      [r[1] for r in now] == [r[1] for r in was],
      repr([(a[0], a[1], b[1]) for a, b in zip(was, now) if a[1] != b[1]][:4]))
check("the notes have their style and height back",
      [(r[6], r[7]) for r in now] == [(r[6], r[7]) for r in was],
      repr([(a[6], a[7], b[6], b[7]) for a, b in zip(was, now)
            if a[6] != b[6] or a[7] != b[7]][:4]))
check("the dimensions have their style AND their override block back",
      [(r[9], r[11]) for r in now] == [(r[9], r[11]) for r in was],
      repr([(a[9], a[11], b[9], b[11]) for a, b in zip(was, now)
            if a[9] != b[9] or a[11] != b[11]][:4]))
check("the annotative flags are back on",
      [r[10] for r in now] == [r[10] for r in was],
      repr([(a[10], b[10]) for a, b in zip(was, now) if a[10] != b[10]][:4]))
check("the stairs are drawn in HIDDEN2 again",
      all(grp(d, 6) == 'HIDDEN2' for d in ents(vm) if grp(d, 8) in ('POOL', 'SURVEY', STAIRS)
          and grp(d, 6) in ('HIDDEN2', 'DASHED2')),
      repr([grp(d, 6) for d in ents(vm) if grp(d, 8) in ('POOL', 'SURVEY', STAIRS)
          and grp(d, 6) in ('HIDDEN2', 'DASHED2')]))
check("...and the wall's explicit Continuous is back",
      sorted(grp(d, 6) for d in on(vm, WALL)) == ['Continuous'] * 2,
      repr([grp(d, 6) for d in on(vm, WALL)]))
check("no object still carries a record",
      not any(xdata(d, 'G2MCONV') for d in ents(vm)))
check("it names the count and the layers it went back onto", any(
    'G2MRECONV done: 14 object(s) put back on' in s and WALL in s
    for s in vm.printed), repr(vm.printed[-2:]))
check("one undo mark, opened and closed",
      vm.undo_marks == 0 and vm.undo_log[-2:] == ['start', 'end'])

print("g2mreconv -- what the revert spells out rather than restores")
check("an object that arrived with no colour of its own comes back with the"
      " explicit ByLayer that means the same thing",
      all(r[2] == 256 for r in now if r[1] in (WALL, STAIRS, NOTES, DIMS)),
      repr([r[2] for r in now]))
check("...and the same for its linetype scale, an explicit 1.0",
      all(r[5] == 1.0 for r in now if r[1] in (WALL, STAIRS, NOTES, DIMS)),
      repr([r[5] for r in now]))

print("g2mreconv -- a converted drawing is what it reads, nothing else")
vm = fresh(not_a_plan)
vm.run('c:G2MRECONV', [None, None])
check("a drawing carrying no record is told so rather than moved", any(
    'nothing here carries a G2MCONV record' in s for s in vm.printed),
    repr(vm.printed))
check("and nothing was created for it", 'TEXT' not in vm.tables['LAYER'])

print("g2mreconv -- a source layer PURGEd in the meantime is re-created")
vm = fresh()
vm.run('c:G2MCONV', [None, None])
for name in (WALL, STAIRS, NOTES, DIMS):
    del vm.tablerecs['LAYER'][name.upper()]
    vm.tables['LAYER'].discard(name)
vm.printed = []
vm.run('c:G2MRECONV', [None, None])
check("the layers are back", all(n in vm.tables['LAYER']
                                 for n in (WALL, STAIRS, NOTES, DIMS)),
      repr(sorted(vm.tables['LAYER'])))
check("...in the colour the record kept off the layer itself",
      grp(vm.recdata[vm.tablerecs['LAYER'][WALL.upper()]], 62) == 43,
      repr(vm.recdata[vm.tablerecs['LAYER'][WALL.upper()]]))
check("and the objects are back on them",
      sorted(set(layers_of(vm, 'LWPOLYLINE'))) == sorted([WALL, STAIRS, 'POOL']),
      repr(layers_of(vm, 'LWPOLYLINE')))

print("g2mconv -- *g2mconv-record* off writes nothing down")
vm = fresh()
vm.loads('(setq *g2mconv-record* nil)')
vm.run('c:G2MCONV', [None, None])
check("the conversion still happened", layers_of(vm, 'LWPOLYLINE') == ['POOL'] * 4)
check("but nothing carries a record",
      not any(xdata(d, 'G2MCONV') for d in ents(vm)))
check("and the run says only U undoes it", any(
    'only U undoes this run' in s for s in vm.printed), repr(vm.printed[-2:]))
vm.printed = []
vm.run('c:G2MRECONV', [None, None])
check("so G2MRECONV has nothing to read", any(
    'nothing here carries a G2MCONV record' in s for s in vm.printed))

print("g2mreconv -- an error mid-run, and an Esc")
vm = fresh()
vm.run('c:G2MCONV', [None, None])
was = state(vm)
vm.handle_errors = True
vm.loads('(defun g2m:color-for (lay recs) (g2m:no-such-helper lay))')
vm.run('c:G2MRECONV', [None, None])
check("the run is aborted through the command's own handler",
      len(vm.handled_errors) == 1, repr(vm.handled_errors))
check("the error is reported under the tool's name", any(
    s.startswith('\nG2MRECONV error:') for s in vm.printed),
    repr(vm.printed[-3:]))
check("the mark it opened is closed",
      vm.undo_marks == 0 and vm.undo_log[-1] == 'end', repr(vm.undo_log))

vm = fresh()
vm.run('c:G2MCONV', [None, None])
was = state(vm)
vm.handle_errors = True
vm.printed = []
vm.run('c:G2MRECONV', [None, esc])
check("Esc at the selection prompt is a quiet cancel",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0]
      and not any('G2MRECONV error' in s for s in vm.printed),
      repr(vm.printed[-2:]))
check("nothing was moved back", state(vm) == was)
check("the mark opened before the prompt is closed",
      vm.undo_marks == 0 and vm.undo_log[-1] == 'end', repr(vm.undo_log))

# ----------------------------------------------------------------------
# the version reporter
# ----------------------------------------------------------------------
print("g2mconv -- the version reporter")
vm = fresh()
vm.run('c:G2MCONVVER', [])
check("G2MCONVVER prints the loaded version", any(
    re.search(r'G2MCONV v\d+\.\d+', s) for s in vm.printed), repr(vm.printed))

# ----------------------------------------------------------------------
if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL G2MCONV TESTS PASSED")
