"""Runtime tests: load the real CDCALLOUT.lsp into the AutoLISP VM and
drive c:CDCALLOUT with scripted typing.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (distance ...) has to die.

Script values answer the interactive calls in order: the "_X" point
sweep (ssget), then per round a FROM number and a TO number (both
getstring) -- the dimension line is placed automatically, right
inbetween, so nothing is ever picked; None at the FROM prompt is the
Enter that ends the loop.  Typed 'b'/'undo' answers exercise the
shared Back convention.  Run: python3 tests/test_cdcallout.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot, Sym, BUILTINS, NIL  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'cdcallout', 'CDCALLOUT.lsp')


def _distof(vm, a):
    try:
        return float(a[0])
    except (TypeError, ValueError):
        return NIL


BUILTINS[Sym('distof')] = _distof


def newvm(styles=("CROSS DIMENSIONS",)):
    vm = VM()
    vm.load(LSP)
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['CLAYER'] = '0'
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    return vm


def ab_pt(vm, x, y, number, layer='POINTS'):
    """An ab_pt INSERT followed by its number ATTRIB, as in a drawing."""
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'INSERT'), Dot(8, layer), Dot(2, 'ab_pt'),
                     [10, float(x), float(y), 0.0]]
    if number is not None:
        att = Ent()
        vm.entities.append(att)
        vm.entdata[att] = [Dot(0, 'ATTRIB'), Dot(2, 'number'),
                           Dot(1, str(number))]
    return e


def run(vm, script, label):
    try:
        vm.run('c:CDCALLOUT', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def dims(vm):
    """Every DIMENSION entity, as {code: value} in creation order
    (deleted ones included -- pair with dim_ents to filter)."""
    out = []
    for e in vm.entities:
        d = {}
        for g in vm.entdata[e]:
            if isinstance(g, Dot):
                d[g.a] = g.b
            elif isinstance(g, list) and g:
                d[g[0]] = g[1:]
        if d.get(0) == 'DIMENSION':
            out.append(d)
    return out


def dim_ents(vm):
    """The DIMENSION entity names, in the same order as dims(vm)."""
    return [e for e in vm.entities
            if any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
                   for g in vm.entdata[e])]


# ---- tests -----------------------------------------------------------

def test_one_dim():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 35), ab_pt(vm, 120, 0, 40)]
    run(vm, [pts, '35', '40', None], 'one dim')
    ds = dims(vm)
    assert len(ds) == 1, ds
    d = ds[0]
    assert d[13] == [0.0, 0.0, 0.0], d
    assert d[14] == [120.0, 0.0, 0.0], d
    # the dimension line lands right inbetween -- no pick
    assert d[10] == [60.0, 0.0, 0.0], d
    assert d[8] == 'DIMENSION', d
    assert d[3] == 'CROSS DIMENSIONS', d
    # per-entity overrides must be gone: the dim is ByLayer
    assert 62 not in d and 6 not in d and 370 not in d, d
    # and the drawing is put back the way it was
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD'
    assert vm.sysvars['CLAYER'] == '0'
    print("ok  Pt.35 - Pt.40 -> one dim, CROSS DIMENSIONS on DIMENSION,"
          " state restored")


def test_rinse_repeat():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2),
           ab_pt(vm, 100, 100, 3)]
    run(vm, [pts,
             '1', '2',
             '2', '3',
             '3', '1',
             None], 'rinse repeat')
    ds = dims(vm)
    assert len(ds) == 3, ds
    assert ds[1][13] == [100.0, 0.0, 0.0] and \
        ds[1][14] == [100.0, 100.0, 0.0], ds[1]
    print("ok  three rounds -> three dims, ended by Enter")


def test_number_spellings():
    """'Pt.35', 'PT35', '#035' and '35.0' all name plain '35'."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 35), ab_pt(vm, 100, 0, 40)]
    run(vm, [pts,
             'Pt.35', 'PT40',
             '#035', '40.0',
             None], 'spellings')
    assert len(dims(vm)) == 2, dims(vm)
    print("ok  Pt.35 / PT40 / #035 / 40.0 all resolve")


def test_decimal_point_name():
    """The v1.0-draft bug: canon stripped every dot, so a point
    genuinely named 40.5 read as 405 and could never be asked for."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, '40.5'), ab_pt(vm, 100, 0, 41)]
    run(vm, [pts, 'Pt.40.5', '41', None], 'decimal name')
    assert len(dims(vm)) == 1, dims(vm)
    print("ok  Pt.40.5      -> a decimal point name keeps its decimal")


def test_unknown_number():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    # '99' names nothing: the round dies at the FROM prompt and nothing
    # is asked for or drawn; the next round still works
    run(vm, [pts, '99', '1', '2', None], 'unknown')
    assert len(dims(vm)) == 1, dims(vm)
    print("ok  unknown number -> reported, nothing drawn, loop goes on")


def test_cancelled_rounds():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, [pts,
             '1', None,               # Enter at TO: round skipped
             '1', '1',                # same point both ends: TO re-asked
             None,                    # Enter at the re-asked TO: skipped
             None], 'cancels')
    assert dims(vm) == [], dims(vm)
    print("ok  Enter at TO, same point twice -> no dims")


def test_offset_pushes_dim_line():
    """cdo:*offset* pushes the dimension line perpendicular off the
    tie, CDCREATE-style; 0.0 (the default) keeps it right inbetween."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 120, 0, 2)]
    vm.loads('(setq cdo:*offset* 6.0)')
    run(vm, [pts, '1', '2', None], 'offset')
    assert dims(vm)[0][10] == [60.0, 6.0, 0.0], dims(vm)
    print("ok  offset 6     -> dim line pushed 6 off the tie")


def test_missing_style():
    vm = newvm(styles=())
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, [pts, '1', '2', None], 'missing style')
    ds = dims(vm)
    assert len(ds) == 1, ds
    # the style is NOT invented: the dim stays in the current style,
    # but it still lands on the DIMENSION layer
    assert ds[0][3] == 'STANDARD', ds
    assert ds[0][8] == 'DIMENSION', ds
    print("ok  no CROSS DIMENSIONS style -> current style kept, warned")


def test_back_undraws_last_dim():
    """Back at the FROM prompt (B/BACK/U/UNDO, any case) removes the
    just-drawn dimension, per the shared Back convention."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2),
           ab_pt(vm, 100, 100, 3)]
    run(vm, [pts,
             '1', '2',
             '2', '3',
             'b',                      # un-draw the 2-3 dim
             'undo',                   # un-draw the 1-2 dim
             'B',                      # nothing left: "Already at..."
             '1', '3',
             None], 'back at FROM')
    live = [d for d, e in zip(dims(vm), dim_ents(vm))
            if e not in vm.deleted]
    assert len(live) == 1, live
    assert live[0][13] == [0.0, 0.0, 0.0] and \
        live[0][14] == [100.0, 100.0, 0.0], live
    print("ok  Back at FROM -> last dim un-drawn, twice, then re-drawn")


def test_back_reasks_previous_prompt():
    """B at TO re-asks FROM, so a mis-typed FROM can be swapped."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2),
           ab_pt(vm, 100, 100, 3)]
    run(vm, [pts,
             '1', 'back',              # B at TO: back to FROM
             '2', '1',                 # ...and the round runs 2 -> 1
             None], 'back mid-round')
    ds = [d for d, e in zip(dims(vm), dim_ents(vm))
          if e not in vm.deleted]
    assert len(ds) == 1, ds
    # the round ended up 2 -> 1, not 1 -> anything
    assert ds[0][13] == [100.0, 0.0, 0.0] and \
        ds[0][14] == [0.0, 0.0, 0.0], ds
    print("ok  Back at TO   -> FROM re-asked")


def test_no_points():
    vm = newvm()
    run(vm, [None], 'no points')
    assert dims(vm) == []
    print("ok  no named points -> nothing asked, nothing drawn")


def test_no_local_shadows_a_function():
    """The BPCALLOUT v1.0 lesson: a local named after a function the
    file calls shadows it for the whole call and dies at runtime."""
    import re
    src = open(LSP).read()
    src = re.sub(r';[^\n]*', '', src)            # strip comments
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)  # and string literals
    arglists = re.findall(r'\(defun\s+[^\s()]+\s*\(([^)]*)\)', src)
    bodies = re.sub(r'\(defun\s+[^\s()]+\s*\([^)]*\)', '(defun', src)
    called = set(re.findall(r'\(\s*([a-zA-Z][\w:*<>=+/-]*)', bodies))
    bad = []
    for arglist in arglists:
        for name in arglist.replace('/', ' ').split():
            if name.lower() in called:
                bad.append(name)
    assert not bad, f"locals shadowing functions they call: {sorted(set(bad))}"
    print("ok  no shadow    -> no local hides a function the file calls")


if __name__ == '__main__':
    test_one_dim()
    test_rinse_repeat()
    test_number_spellings()
    test_decimal_point_name()
    test_unknown_number()
    test_cancelled_rounds()
    test_offset_pushes_dim_line()
    test_missing_style()
    test_back_undraws_last_dim()
    test_back_reasks_previous_prompt()
    test_no_points()
    test_no_local_shadows_a_function()
    print("all CDCALLOUT tests passed")
