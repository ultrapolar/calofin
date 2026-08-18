"""Runtime tests: load the real CDCREATE.lsp into the AutoLISP VM and
drive c:CDCREATE with scripted selections.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (distance ...) has to die.

Script values answer the interactive calls in order: for CDCREATE that
is the pickfirst probe (ssget "_I") and, when it comes back empty, the
highlight prompt.  None means "nothing selected", a list of entities is
the highlighted set.  Run: python3 tests/test_cdcreate.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot, Sym  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'cdcreate', 'CDCREATE.lsp')


def newvm(styles=("CROSS DIMENSIONS",), layers=("POOL",)):
    vm = VM()
    vm.load(LSP)
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    for lay in layers:
        vm.tables['LAYER'].add(lay)
    vm.sysvars['CLAYER'] = layers[0] if layers else '0'
    return vm


def line(vm, p1, p2, layer='0'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'LINE'), Dot(8, layer),
                     [10] + [float(v) for v in p1],
                     [11] + [float(v) for v in p2]]
    return e


def other(vm, etype, layer='0'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, etype), Dot(8, layer), [10, 0.0, 0.0, 0.0]]
    return e


def run(vm, script, label):
    try:
        vm.run('c:CDCREATE', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def dims(vm):
    """Every DIMENSION entity in creation order, as {code: value}."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for g in vm.entdata[e]:
            if isinstance(g, Dot):
                d.setdefault(g.a, g.b)
            elif isinstance(g, list) and g:
                d.setdefault(g[0], g[1] if len(g) == 2 else g[1:])
        if d.get(0) == 'DIMENSION':
            out.append(d)
    return out


def dimcalls(vm):
    return [c for c in vm.commands if c and c[0] == '_.DIMALIGNED']


def alive(vm, etype):
    """Entities of ETYPE still in the drawing (not erased)."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        for g in vm.entdata[e]:
            if isinstance(g, Dot) and g.a == 0 and g.b == etype:
                out.append(e)
    return out


def near(a, b, tol=1e-9):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


print("== C1. three highlighted lines -> three cross dims ==")
vm = newvm()
ls = [line(vm, (0, 0, 0), (10, 0, 0)),
      line(vm, (0, 0, 0), (10, 10, 0)),
      line(vm, (10, 0, 0), (0, 10, 0))]
run(vm, [None, ls], "C1")                 # no pickfirst, then highlight

calls = dimcalls(vm)
assert len(calls) == 3, calls
# each call is DIMALIGNED, first extension point, second, dim line loc
assert near(calls[0][2], [0.0, 0.0, 0.0]), calls[0]
assert near(calls[0][4], [10.0, 0.0, 0.0]), calls[0]
assert near(calls[0][6], [5.0, 0.0, 0.0]), "dim line sits on the line"
assert near(calls[1][6], [5.0, 5.0, 0.0]), "diagonal dim line on the diagonal"
assert all(c[1] == "_non" and c[3] == "_non" and c[5] == "_non"
           for c in calls), "points passed as _non, immune to running osnaps"

made = dims(vm)
assert len(made) == 3, made
assert all(d[8] == "DIMENSION" for d in made), [d[8] for d in made]
assert all(d[3] == "CROSS DIMENSIONS" for d in made), [d[3] for d in made]
assert all(62 not in d and 6 not in d and 370 not in d for d in made), \
    "cross dims are ByLayer -- no per-entity colour/linetype/lineweight"
assert "DIMENSION" in vm.tables['LAYER'], "DIMENSION layer created"
assert alive(vm, 'LINE') == [], "every dimensioned line is erased"
assert all(e in vm.deleted for e in ls)
undo = [c for c in vm.commands if c and c[0] == '_.UNDO']
assert [c[1] for c in undo] == ["_Begin", "_End"], undo
assert vm.commands.index(['_.UNDO', '_Begin']) < \
    vm.commands.index(dimcalls(vm)[0]), "undo group opens before the work"
assert vm.commands[-1] == ['_.UNDO', '_End'], "and closes after it"

# state restored
assert vm.sysvars['CLAYER'] == "POOL", vm.sysvars['CLAYER']
assert vm.sysvars['DIMSTYLE'] == "STANDARD", vm.sysvars['DIMSTYLE']
assert vm.sysvars['CMDECHO'] == 1 and vm.sysvars['OSMODE'] == 4133
assert vm.dimstyle_log == ["CROSS DIMENSIONS", "STANDARD"], vm.dimstyle_log
print("   3 dims, DIMENSION layer, CROSS DIMENSIONS style, lines gone,")
print("   state restored, whole run in one undo group")


print("== C2. a pickfirst selection is used as-is, no second prompt ==")
vm = newvm()
ls = [line(vm, (0, 0, 0), (0, 6, 0))]
run(vm, [ls], "C2")                       # only the "_I" probe is answered
assert len(dimcalls(vm)) == 1
assert len(vm.prompts) == 1, vm.prompts
assert vm.prompts[0][0] == "ssget _I", vm.prompts
print("   highlighted-first selection dimensioned without re-asking")


print("== C3. non-lines and zero-length lines are left alone ==")
vm = newvm()
sel = [line(vm, (0, 0, 0), (4, 0, 0)),
       other(vm, 'LWPOLYLINE'),
       other(vm, 'TEXT'),
       line(vm, (7, 7, 0), (7, 7, 0))]    # degenerate: nothing to measure
run(vm, [None, sel], "C3")
assert len(dimcalls(vm)) == 1, dimcalls(vm)
assert len(dims(vm)) == 1
assert sel[0] in vm.deleted, "the dimensioned line goes"
assert not any(e in vm.deleted for e in sel[1:]), \
    "the polyline, the text and the zero-length line all stay"
print("   1 dim from 4 selected objects; polyline, text, zero-length skipped,")
print("   and only the line that got a dimension was erased")


print("== C4. no lines at all, and nothing highlighted ==")
vm = newvm()
run(vm, [None, [other(vm, 'CIRCLE')]], "C4-nolines")
assert dimcalls(vm) == [] and dims(vm) == []
assert vm.sysvars['CLAYER'] == "POOL" and vm.sysvars['DIMSTYLE'] == "STANDARD"

vm = newvm()
run(vm, [None, None], "C4-empty")
assert dimcalls(vm) == [] and dims(vm) == []
assert vm.dimstyle_log == [], "no style switching when there is nothing to do"
assert not any(c and c[0] == '_.UNDO' for c in vm.commands), \
    "no undo group opened for a run with nothing to do"
assert vm.sysvars['CLAYER'] == "POOL"
assert "DIMENSION" not in vm.tables['LAYER'], \
    "an empty run does not litter the drawing with a layer"
print("   both no-op paths leave the drawing exactly as it was")


print("== C5. drawing without the CROSS DIMENSIONS style ==")
vm = newvm(styles=())
ls = [line(vm, (0, 0, 0), (5, 0, 0))]
run(vm, [None, ls], "C5")
assert len(dimcalls(vm)) == 1, "dims are still drawn"
assert vm.dimstyle_log == [], "no style restore attempted for a missing style"
made = dims(vm)
assert made[0][8] == "DIMENSION", "layer is still honoured"
assert made[0][3] == "STANDARD", "current style used instead"
print("   dims drawn in the current style, layer still DIMENSION")


print("== C6. DIMLAYER does not get the last word ==")
vm = newvm()
vm.tables['LAYER'].add("DEFPOINTS")
vm.sysvars['DIMLAYER'] = "DEFPOINTS"      # AutoCAD would park the dim here
ls = [line(vm, (0, 0, 0), (5, 5, 0))]
run(vm, [None, ls], "C6")
made = dims(vm)
assert len(made) == 1
assert made[0][8] == "DIMENSION", made[0][8]
print("   dim pulled back onto DIMENSION after DIMLAYER placed it elsewhere")


print("== C7. cdc:*offset* pushes the dim line off the line ==")
vm = newvm()
vm.globals[Sym('cdc:*offset*')] = 2.0
ls = [line(vm, (0, 0, 0), (10, 0, 0))]
run(vm, [None, ls], "C7")
loc = dimcalls(vm)[0][6]
assert near(loc, [5.0, 2.0, 0.0]), loc
print("   offset 2.0 puts the horizontal dim line 2.0 above the line")


print("== C8. cdc:*erase* nil keeps the lines ==")
vm = newvm()
vm.globals[Sym('cdc:*erase*')] = None       # nil
ls = [line(vm, (0, 0, 0), (3, 4, 0), layer="POINTS")]
run(vm, [None, ls], "C8")
assert len(dims(vm)) == 1
assert alive(vm, 'LINE') == ls, "the line stays when erasing is switched off"
print("   dim drawn, line left in place")


print("== C9. lines come off POOL / POINTS, dims land on DIMENSION ==")
vm = newvm()
ls = [line(vm, (0, 0, 0), (10, 6, 0), layer="POOL"),
      line(vm, (10, 0, 0), (0, 6, 0), layer="POINTS")]
run(vm, [None, ls], "C9")
assert [d[8] for d in dims(vm)] == ["DIMENSION", "DIMENSION"]
assert all(e in vm.deleted for e in ls), "both source lines erased"
assert alive(vm, 'LINE') == []
print("   both ties dimensioned onto DIMENSION, both source lines erased")


print("== C10. CDCREATEVER prints the version ==")
vm = newvm()
vm.run('c:CDCREATEVER', [])
print("   ok")

print("\nALL CDCREATE RUNTIME TESTS PASSED")
