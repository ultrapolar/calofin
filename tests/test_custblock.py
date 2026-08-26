"""Runtime tests: load the real CUSTBLOCK.lsp into the AutoLISP VM and
drive c:CUSTBLOCK with scripted answers.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (distance ...) has to die.

The reference is the sample sheet the command was written from: an
84 x 36 x 4 block, nine lines on COVER, three dimensions on DIMENSION
in "STANDARD INCHES".  Its exact corner coordinates are asserted below,
so a change to how the pictorial is built shows up as a failing number
rather than as a drawing nobody looked at.

Script values answer the interactive calls in order: length, width,
height, then the base point.  Run:

    python3 tests/test_custblock.py
    CALOFIN_LISP_ROOT=shared python3 tests/test_custblock.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'custblock', 'CUSTBLOCK.lsp')

#: the sample's receding offset: 84" of length laid over at 45 degrees
D = 84.0 / math.sqrt(2.0)


def newvm(styles=("STANDARD INCHES",), layers=("POOL",)):
    vm = VM()
    vm.load(LSP)                            # CALOFIN_LISP_ROOT picks the tier
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    for lay in layers:
        vm.tables['LAYER'].add(lay)
    vm.sysvars['CLAYER'] = layers[0] if layers else '0'
    return vm


def run(vm, script, label):
    try:
        vm.run('c:CUSTBLOCK', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def data(vm, e):
    """One entity's group codes as {code: value}."""
    d = {}
    for g in vm.entdata[e]:
        if isinstance(g, Dot):
            d.setdefault(g.a, g.b)
        elif isinstance(g, list) and g:
            d.setdefault(g[0], g[1] if len(g) == 2 else g[1:])
    return d


def ents(vm, etype):
    """Every live entity of ETYPE, in creation order, as dicts."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = data(vm, e)
        if d.get(0) == etype:
            out.append(d)
    return out


def edges(vm):
    """The block's lines as a set of unordered 2-D endpoint pairs,
    rounded so floating point noise cannot fail a comparison."""
    def r(p):
        return (round(p[0], 6), round(p[1], 6))
    out = set()
    for d in ents(vm, 'LINE'):
        out.add(frozenset((r(d[10]), r(d[11]))))
    return out


def want(pairs):
    return {frozenset((tuple(round(v, 6) for v in a),
                       tuple(round(v, 6) for v in b))) for a, b in pairs}


def near(a, b, tol=1e-6):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


#: the nine visible edges of the sample block, local to the base point.
#: pa/pb/pc/pd are the front face anticlockwise from the base point,
#: qa/qb/qc/qd the same four slid back along the receding axis.
PA, PB, PC, PD = (0, 0), (36, 0), (36, 4), (0, 4)
QA, QB, QC, QD = (D, D), (36 + D, D), (36 + D, 4 + D), (D, 4 + D)
SAMPLE = [(PD, PC), (PC, PB), (PB, PA), (PA, PD),      # front face
          (PD, QD), (QD, QC), (PC, QC),                # top face
          (QC, QB), (PB, QB)]                          # right face


print("== B1. 84 x 36 x 4 at the origin is the sample sheet's block ==")
vm = newvm()
run(vm, [84.0, 36.0, 4.0, [0.0, 0.0, 0.0]], "B1")

lines = ents(vm, 'LINE')
assert len(lines) == 9, len(lines)
assert all(d[8] == "COVER" for d in lines), [d[8] for d in lines]
assert edges(vm) == want(SAMPLE), sorted(edges(vm) ^ want(SAMPLE))
assert "COVER" in vm.tables['LAYER'], "COVER layer created"
print("   nine lines on COVER, every corner where the sample has it")


print("== B2. the three hidden edges are not drawn ==")
hidden = want([(PA, QA), (QA, QB), (QA, QD)])
assert not (edges(vm) & hidden), "a hidden edge was drawn"
# and nothing at all reaches the far bottom-left corner
assert all(tuple(round(v, 6) for v in QA) not in e for e in edges(vm)), \
    "the back bottom-left corner is behind the block -- no edge reaches it"
print("   the block reads as a solid, not a wire cage")


print("== B3. three dimensions, right measurements, right style ==")
dims = ents(vm, 'DIMENSION')
assert len(dims) == 3, len(dims)
assert [round(d[42], 6) for d in dims] == [84.0, 4.0, 36.0], \
    [d[42] for d in dims]
assert all(d[8] == "DIMENSION" for d in dims), [d[8] for d in dims]
assert all(d[3] == "STANDARD INCHES" for d in dims), [d[3] for d in dims]
assert all(62 not in d and 6 not in d and 370 not in d for d in dims), \
    "the dims are ByLayer -- no per-entity colour/linetype/lineweight"
assert dims[0][70] == 1, "the length reads along its own edge (aligned)"
assert dims[1][70] == 0 and dims[2][70] == 0, "height and width are linear"
# the length dim sits on the top-left receding edge, the other two on
# the front face's left and bottom edges
assert near(dims[0][13], [0.0, 4.0, 0.0]) and near(dims[0][14], [D, 4 + D, 0])
assert near(dims[1][13], [0.0, 0.0, 0.0]) and near(dims[1][14], [0.0, 4.0, 0])
assert near(dims[2][13], [36.0, 0.0, 0.0]) and near(dims[2][14], [0, 0, 0])
print("   84 aligned on the receding edge, 4 up the side, 36 along the foot")


print("== B4. the axis of a linear dim is forced, not inferred ==")
linear = [c for c in vm.commands if c and c[0] == '_.DIMLINEAR']
assert len(linear) == 2, linear
assert "_V" in linear[0] and "_H" in linear[1], linear
assert all(c.count("_non") == 3 for c in linear), \
    "points passed as _non, immune to running osnaps"
aligned = [c for c in vm.commands if c and c[0] == '_.DIMALIGNED']
assert len(aligned) == 1 and aligned[0].count("_non") == 3, aligned
print("   height held vertical, width held horizontal whatever the offset")


print("== B5. the dimension lines stand cbk:*dimoff* clear of the block ==")
off = 12.0
step = off / math.sqrt(2.0)
assert near(dims[1][10], [-off, 2.0, 0.0]), dims[1][10]
assert near(dims[2][10], [18.0, -off, 0.0]), dims[2][10]
assert near(dims[0][10], [D / 2 - step, 4 + D / 2 + step, 0.0]), dims[0][10]
# ...on the far side of the receding edge, away from the top face
assert dims[0][10][0] < D / 2, "the length dim is pushed off the top face"
print("   12 below, 12 to the left, 12 out from the receding edge")


print("== B6. one undo group round the whole run, state restored ==")
undo = [c for c in vm.commands if c and c[0] == '_.UNDO']
assert [c[1] for c in undo] == ["_Begin", "_End"], undo
assert vm.commands.index(['_.UNDO', '_Begin']) < \
    vm.commands.index(aligned[0]), "undo opens before the work"
assert vm.commands[-1] == ['_.UNDO', '_End'], "and closes after it"
assert vm.sysvars['CLAYER'] == "POOL", vm.sysvars['CLAYER']
assert vm.sysvars['DIMSTYLE'] == "STANDARD", vm.sysvars['DIMSTYLE']
assert vm.sysvars['CMDECHO'] == 1 and vm.sysvars['OSMODE'] == 4133
assert vm.dimstyle_log == ["STANDARD INCHES", "STANDARD"], vm.dimstyle_log
print("   a single U takes the block and its dims away together")


print("== B7. the base point is the front bottom left corner ==")
vm = newvm()
run(vm, [84.0, 36.0, 4.0, [100.0, 250.0, 0.0]], "B7")
moved = want([((a[0] + 100, a[1] + 250), (b[0] + 100, b[1] + 250))
              for a, b in SAMPLE])
assert edges(vm) == moved, sorted(edges(vm) ^ moved)
print("   the whole block moves with it, dims and all")


print("== B8. Enter at the base point takes the origin ==")
vm = newvm()
run(vm, [84.0, 36.0, 4.0, None], "B8")
assert edges(vm) == want(SAMPLE), "Enter drew it at 0,0"
print("   Enter = 0,0, as the prompt says")


print("== B9. an elevated UCS point carries its elevation ==")
vm = newvm()
run(vm, [10.0, 5.0, 2.0, [0.0, 0.0, 7.5]], "B9")
assert all(d[10][2] == 7.5 and d[11][2] == 7.5 for d in ents(vm, 'LINE')), \
    "the block is drawn at the elevation it was based at"
print("   every corner sits at the base point's Z")


print("== B10. Back re-asks the question before ==")
vm = newvm()
run(vm, [84.0, "Back", 60.0, 36.0, 4.0, [0.0, 0.0, 0.0]], "B10-width")
assert round(ents(vm, 'DIMENSION')[0][42], 6) == 60.0, "the length was re-asked"
prompts = [p[0] for p in vm.prompts]
assert prompts[:3] == ["\nBlock length: ", "\nBlock width [Back]: ",
                       "\nBlock length: "], prompts
assert prompts[-1] == "\nInsertion base point [Back] <0,0>: ", prompts[-1]
print("   Back at the width goes back to the length")

vm = newvm()
run(vm, [84.0, 36.0, "Back", 30.0, 4.0, [0.0, 0.0, 0.0]], "B10-height")
assert round(ents(vm, 'DIMENSION')[2][42], 6) == 30.0, "the width was re-asked"
vm = newvm()
run(vm, [84.0, 36.0, 4.0, "Back", 9.0, [0.0, 0.0, 0.0]], "B10-base")
assert round(ents(vm, 'DIMENSION')[1][42], 6) == 9.0, "the height was re-asked"
print("   and at the height, and at the base point")


print("== B11. the first question offers no Back ==")
vm = newvm()
try:
    vm.run('c:CUSTBLOCK', ["Back"])
except LispError as e:
    assert "keyword" in str(e).lower(), e
else:
    raise AssertionError("Back was accepted at the first question")
print("   nothing to go back to, so it is not offered")


print("== B12. Undo is accepted wherever Back is, unlisted ==")
vm = newvm()
run(vm, [84.0, "Undo", 60.0, 36.0, 4.0, [0.0, 0.0, 0.0]], "B12")
assert round(ents(vm, 'DIMENSION')[0][42], 6) == 60.0
assert "Undo" not in vm.prompts[1][0], vm.prompts[1]
print("   Undo backs out; the bracket still says [Back]")


print("== B13. a missing dimension style is reported, not invented ==")
vm = newvm(styles=())
run(vm, [84.0, 36.0, 4.0, [0.0, 0.0, 0.0]], "B13")
assert "STANDARD INCHES" not in vm.tables['DIMSTYLE'], "no style was created"
assert all(d[3] == "STANDARD" for d in ents(vm, 'DIMENSION')), \
    "drawn in whatever style was current"
assert len(ents(vm, 'DIMENSION')) == 3, "and all three are still drawn"
assert any("no \"STANDARD INCHES\" dimension style" in s for s in vm.printed), \
    vm.printed
print("   drawn in the current style, and the routine says so")


print("== B14. a frozen output layer is thawed before it is drawn on ==")
vm = newvm()
e = Ent()
vm.recdata[e] = [Dot(0, 'LAYER'), Dot(2, 'COVER'), Dot(70, 1), Dot(62, -7),
                 Dot(6, 'Continuous')]
vm.tables['LAYER'].add('COVER')
vm.tablerecs.setdefault('LAYER', {})['COVER'] = e
run(vm, [84.0, 36.0, 4.0, [0.0, 0.0, 0.0]], "B14")
rec = {g.a: g.b for g in vm.recdata[e] if isinstance(g, Dot)}
assert rec[70] == 0 and rec[62] == 7, rec
assert len(ents(vm, 'LINE')) == 9
assert any("was off, frozen or locked" in s for s in vm.printed), vm.printed
print("   thawed, switched back on, and the user is told")


print("== B15. a block that is not the sample still closes on itself ==")
vm = newvm()
run(vm, [12.0, 12.0, 12.0, [0.0, 0.0, 0.0]], "B15")
assert len(ents(vm, 'LINE')) == 9
assert [round(d[42], 6) for d in ents(vm, 'DIMENSION')] == [12.0, 12.0, 12.0]
d12 = 12.0 / math.sqrt(2.0)
assert edges(vm) == want([((0, 12), (12, 12)), ((12, 12), (12, 0)),
                          ((12, 0), (0, 0)), ((0, 0), (0, 12)),
                          ((0, 12), (d12, 12 + d12)),
                          ((d12, 12 + d12), (12 + d12, 12 + d12)),
                          ((12, 12), (12 + d12, 12 + d12)),
                          ((12 + d12, 12 + d12), (12 + d12, d12)),
                          ((12, 0), (12 + d12, d12))]), sorted(edges(vm))
print("   a cube reads as a cube")


print("== B16. zero and negative sizes are refused at the prompt ==")
for bad, where in ((0.0, "zero"), (-4.0, "negative")):
    vm = newvm()
    try:
        vm.run('c:CUSTBLOCK', [84.0, 36.0, bad, [0.0, 0.0, 0.0]])
    except LispError as e:
        assert where in str(e), e
    else:
        raise AssertionError(f"a {where} height was accepted")
    assert ents(vm, 'LINE') == [], "and nothing was drawn"
print("   a block has to have all three sizes")


print("== B17. the report names the block and where it went ==")
vm = newvm()
run(vm, [84.0, 36.0, 4.0, [0.0, 0.0, 0.0]], "B17")
said = "".join(vm.printed)
assert "84" in said and "36" in said and "4" in said, said
assert "COVER" in said and "DIMENSION" in said, said
assert "9 lines and 3 dimensions" in said, said
print("   84 x 36 x 4, 9 lines, 3 dimensions, on COVER and DIMENSION")


print("== B18. CUSTBLOCKVER prints the version ==")
vm = newvm()
vm.run('c:CUSTBLOCKVER', [])
assert any("CUSTBLOCK v" in s for s in vm.printed), vm.printed
print("   ok")

tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
print(f"\nALL CUSTBLOCK RUNTIME TESTS PASSED  [{tier}]")
