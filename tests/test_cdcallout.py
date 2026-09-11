"""Runtime tests: load the real CDCALLOUT.lsp into the AutoLISP VM and
drive c:CDCALLOUT with scripted typing.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (distance ...) has to die.

Script values answer the interactive calls in order, and EVERY TIE IS
ITS OWN PAIR: a FROM number then a TO number, then FROM and TO again
for the next one -- the dimension line is placed automatically, right
inbetween, so nothing is ever picked.  None at the TO prompt skips that
tie and re-asks FROM; None at the FROM prompt ends the command.
Typed 'b'/'undo' answers
exercise the shared Back convention.  The "_X" point sweep takes no
scripted answer: ssget "_X" reads the drawing and never prompts, so the
points the scenario builds with ab_pt are what it finds.  A callable
in the script is called at its prompt -- that is how a scenario presses
Esc.
Run: python3 tests/test_cdcallout.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_cdcallout.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'cdcallout', 'CDCALLOUT.lsp')


def newvm(styles=("CROSS DIMENSIONS",)):
    vm = VM()
    vm.load(LSP)
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['CLAYER'] = '0'
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    return vm


def ab_pt(vm, x, y, number, layer='POINTS', block='ab_pt', tag='number'):
    """A point-block INSERT followed by its number ATTRIB, as in a
    drawing.  number None = a block carrying no attribute at all."""
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'INSERT'), Dot(8, layer), Dot(2, block),
                     [10, float(x), float(y), 0.0]]
    if number is not None:
        att = Ent()
        vm.entities.append(att)
        vm.entdata[att] = [Dot(0, 'ATTRIB'), Dot(2, tag),
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


def undo_calls(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def layer_rec(vm, name):
    return {g.a: g.b for g in vm.recdata[vm.tablerecs['LAYER'][name.upper()]]
            if isinstance(g, Dot)}


def esc(vm):
    """The drafter presses Esc at this prompt."""
    raise LispError('Function cancelled', vm)


def dim_ents(vm):
    """The DIMENSION entity names, in the same order as dims(vm)."""
    return [e for e in vm.entities
            if any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
                   for g in vm.entdata[e])]


# ---- tests -----------------------------------------------------------

def test_one_dim():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 35), ab_pt(vm, 120, 0, 40)]
    run(vm, ['35', '40', None], 'one dim')
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
    run(vm, [
             '1', '2',                # every tie names both its points
             '2', '3',
             '3', '1',
             None], 'rinse repeat')
    ds = dims(vm)
    assert len(ds) == 3, ds
    assert ds[1][13] == [100.0, 0.0, 0.0] and \
        ds[1][14] == [100.0, 100.0, 0.0], ds[1]
    # the third names 3 -> 1, which a chain could never have produced
    # from those numbers
    assert ds[2][13] == [100.0, 100.0, 0.0] and \
        ds[2][14] == [0.0, 0.0, 0.0], ds[2]
    print("ok  three pairs  -> three dims from six numbers, ended by Enter")


def test_number_spellings():
    """'Pt.35', 'PT35', '#035' and '35.0' all name plain '35'."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 35), ab_pt(vm, 100, 0, 40)]
    run(vm, [
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
    run(vm, ['Pt.40.5', '41', None], 'decimal name')
    assert len(dims(vm)) == 1, dims(vm)
    print("ok  Pt.40.5      -> a decimal point name keeps its decimal")


def test_unknown_number():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    # '99' names nothing: the round dies at the FROM prompt and nothing
    # is asked for or drawn; the next round still works
    run(vm, ['99', '1', '2', None], 'unknown')
    assert len(dims(vm)) == 1, dims(vm)
    print("ok  unknown number -> reported, nothing drawn, loop goes on")


def test_cancelled_rounds():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, [
             '1', None,               # Enter at TO: tie skipped
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
    run(vm, ['1', '2', None], 'offset')
    assert dims(vm)[0][10] == [60.0, 6.0, 0.0], dims(vm)
    print("ok  offset 6     -> dim line pushed 6 off the tie")


def test_missing_style():
    vm = newvm(styles=())
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, ['1', '2', None], 'missing style')
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
    run(vm, [
             '1', '2',                 # two ties, both numbers each
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
    run(vm, [
             '1', 'back',              # B at TO: back to FROM
             '2', '1',                 # ...and the tie runs 2 -> 1
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
    run(vm, [], 'no points')
    assert dims(vm) == []
    print("ok  no named points -> nothing asked, nothing drawn")


def test_no_carry_over_between_runs():
    """v1.7 remembered the last TO point and reopened a later run at the
    TO prompt anchored on it.  Nothing carries over now: a fresh run
    starts at FROM, like the first one did, so the numbers a scenario
    types mean the same thing whenever it is run."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2),
           ab_pt(vm, 100, 100, 3)]
    run(vm, ['1', '2', None], 'first run')
    run(vm, ['2', '3', None], 'second run')
    ds = [d for d, e in zip(dims(vm), dim_ents(vm))
          if e not in vm.deleted]
    assert len(ds) == 2, ds
    assert ds[1][13] == [100.0, 0.0, 0.0] and \
        ds[1][14] == [100.0, 100.0, 0.0], ds[1]
    # the second run opened at FROM, not anchored on the first run's TO
    assert vm.prompts[0][0].startswith('\nFrom point number'), vm.prompts[0]
    print("ok  no carry-over -> a later run opens at FROM, not anchored")


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


def test_esc_restores_state_and_closes_group():
    """Esc at the FROM prompt with one dimension drawn: the handler puts
    DIMSTYLE, CLAYER, OSMODE and CMDECHO back, closes the undo group it
    opened (the dim stays -- one U takes it), and says nothing about an
    error.  No other suite reaches this handler: on an empty drawing
    the command stops before its first prompt."""
    vm = newvm()
    vm.handle_errors = True
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, ['1', '2', esc], 'Esc at FROM')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD'
    assert vm.sysvars['CLAYER'] == '0'
    assert vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert not any('error' in p.lower() for p in vm.printed), vm.printed
    assert len(dims(vm)) == 1
    print("ok  Esc at FROM  -> state restored, group closed, no error text")


def test_undo_off():
    """UNDOCTL with bit 1 clear: no group is opened -- and, the half
    v1.8 got wrong, none is closed either.  An _End with no group open
    is an error in the VM, as the stray UNDO prompt is in AutoCAD."""
    vm = newvm()
    vm.sysvars['UNDOCTL'] = 0
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, ['1', '2', None], 'undo off')
    assert undo_calls(vm) == [], vm.commands
    assert len(dims(vm)) == 1
    assert vm.sysvars['CLAYER'] == '0' and vm.sysvars['DIMSTYLE'] == 'STANDARD'
    print("ok  undo off     -> no _.UNDO at all, the dim still drawn")


def test_undo_group_wraps_the_run():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, ['1', '2', None], 'undo group')
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    print("ok  undo group   -> one _Begin before the dims, one _End after")


# ---- a number the drawing carries twice --------------------------------
# Two surveys merged onto one sheet, each numbered from 1: "7" names two
# different places, and a tie to the wrong one measures nothing anybody
# taped.  Every point that carries the number is ringed and labelled
# P1, P2, ... in drawing order, and the label is what you type.

def rings(vm, live_only=False):
    """The rings and labels drawn on the pick layer."""
    out = []
    for e in vm.entities:
        if live_only and e in vm.deleted:
            continue
        d = {}
        for g in vm.entdata[e]:
            d.setdefault(getattr(g, 'a', g[0] if isinstance(g, list) else None),
                         getattr(g, 'b', g[1:] if isinstance(g, list) else None))
        if str(d.get(8, '')).upper() == 'CDCALLOUT-PICK':
            out.append(d)
    return out


def test_a_doubled_number_is_asked_about():
    """Both Pt.7s are ringed and labelled, and the label picks which."""
    vm = newvm()
    ab_pt(vm, 0, 0, 7), ab_pt(vm, 50, 50, 7), ab_pt(vm, 100, 0, 8)
    run(vm, ['7', 'P2', '8', None], 'duplicate')
    ds = dims(vm)
    assert len(ds) == 1 and ds[0][13] == [50.0, 50.0, 0.0], ds
    marks = rings(vm)
    assert [d.get(1) for d in marks if d.get(0) == 'TEXT'] == ['P1', 'P2'], marks
    assert [d.get(10)[:2] for d in marks if d.get(0) == 'CIRCLE'] \
        == [[0.0, 0.0], [50.0, 50.0]], marks
    # scaffolding, and gone the moment the question is answered
    assert not rings(vm, live_only=True)
    print("ok  duplicate    -> both Pt.7s ringed, the label picks one")


def test_a_doubled_number_can_be_clicked_instead():
    """A click takes the nearest of the ringed points - the same answer."""
    vm = newvm()
    ab_pt(vm, 0, 0, 7), ab_pt(vm, 50, 50, 7), ab_pt(vm, 100, 0, 8)
    run(vm, ['7', [48.0, 52.0, 0.0], '8', None], 'clicked')
    ds = dims(vm)
    assert len(ds) == 1 and ds[0][13] == [50.0, 50.0, 0.0], ds
    print("ok  duplicate    -> a click on one of the rings takes it")


def test_the_to_prompt_asks_the_same_way():
    """And its table says how long the dimension each one would draw is,
    because the other end of the tie is settled by then."""
    vm = newvm()
    ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 7), ab_pt(vm, 0, 240, 7)
    run(vm, ['1', '7', 'P2', None], 'to prompt')
    ds = dims(vm)
    assert len(ds) == 1 and ds[0][14] == [0.0, 240.0, 0.0], ds
    assert any('from Pt.1' in m for m in vm.printed), vm.printed
    assert any("20'-0\"" in m for m in vm.printed), vm.printed
    print("ok  duplicate    -> the TO table measures each candidate's tie")


def test_a_number_only_one_point_carries_is_not_asked_about():
    """The ordinary drawing is never asked anything."""
    vm = newvm()
    ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)
    run(vm, ['1', '2', None], 'unique')
    assert not [q for q, _ in vm.prompts if 'is meant' in q], vm.prompts
    assert not rings(vm)
    assert len(dims(vm)) == 1
    print("ok  duplicate    -> one point per number asks nothing at all")


def test_back_and_enter_at_the_pick():
    """Back re-asks the number; Enter takes none and draws nothing."""
    vm = newvm()
    ab_pt(vm, 0, 0, 7), ab_pt(vm, 50, 50, 7), ab_pt(vm, 100, 0, 8)
    run(vm, ['7', 'b', '8', '7', 'P1', None], 'back')
    assert any('Back to the point number' in m for m in vm.printed), vm.printed
    ds = [d for d in dims(vm) if d.get(13)]
    assert len(ds) == 1 and ds[0][13] == [100.0, 0.0, 0.0] \
        and ds[0][14] == [0.0, 0.0, 0.0], ds

    # and at the TO prompt Back re-asks the TO number, not the FROM one
    vm = newvm()
    ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 7), ab_pt(vm, 0, 240, 7)
    run(vm, ['1', '7', 'b', '7', 'P1', None], 'back at to')
    # the TO number is asked twice and the FROM number only once: Back
    # at the pick stepped back ONE question, not two
    asked = [q for q, _ in vm.prompts]
    assert len([q for q in asked if q.startswith('\nTo point')]) == 2, asked
    assert len([q for q in asked if q.startswith('\nFrom point')]) == 2, asked
    assert asked[-1].startswith('\nFrom point'), asked
    ds = dims(vm)
    assert len(ds) == 1 and ds[0][14] == [100.0, 0.0, 0.0], ds

    vm = newvm()
    ab_pt(vm, 0, 0, 7), ab_pt(vm, 50, 50, 7), ab_pt(vm, 100, 0, 8)
    run(vm, ['7', None, None], 'none')
    assert any('None taken' in m for m in vm.printed), vm.printed
    assert not dims(vm)
    assert not rings(vm, live_only=True)
    print("ok  duplicate    -> Back re-asks the number, Enter takes none")


def test_a_stray_label_is_refused_and_re_asked():
    vm = newvm()
    ab_pt(vm, 0, 0, 7), ab_pt(vm, 50, 50, 7), ab_pt(vm, 100, 0, 8)
    run(vm, ['7', 'P9', 'P1', '8', None], 'stray')
    assert any('is not one of the labels' in m for m in vm.printed), vm.printed
    ds = dims(vm)
    assert len(ds) == 1 and ds[0][13] == [0.0, 0.0, 0.0], ds
    print("ok  duplicate    -> a label that names nothing is re-asked")


def test_layer_repaired_and_coloured():
    """DIMENSION frozen, locked and off is thawed, unlocked and switched
    on before the dim is drawn; a missing DIMENSION is created in
    cdo:*layer-color*, 7 by default."""
    vm = newvm()
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "DIMENSION")'
             ' \'(70 . 5) \'(62 . -7) \'(6 . "Continuous")))')
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, ['1', '2', None], 'repair')
    rec = layer_rec(vm, 'DIMENSION')
    assert rec[70] == 0 and rec[62] == 7, rec
    assert dims(vm)[0][8] == 'DIMENSION'
    assert any('was off, frozen or locked' in p for p in vm.printed), \
        vm.printed
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, ['1', '2', None], 'default colour')
    assert layer_rec(vm, 'DIMENSION')[62] == 7, layer_rec(vm, 'DIMENSION')
    vm = newvm()
    vm.loads('(setq cdo:*layer-color* 3)')
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 100, 0, 2)]
    run(vm, ['1', '2', None], 'colour knob')
    assert layer_rec(vm, 'DIMENSION')[62] == 3, layer_rec(vm, 'DIMENSION')
    print("ok  layer        -> DIMENSION repaired when unusable, created in"
          " the knob's colour")


def test_point_classifier():
    """What counts as a survey point is the cdo:*point-block* /
    cdo:*point-layer* / cdo:*pt-tag* trio: an ab_pt INSERT anywhere,
    any INSERT on POINTS, a block with no number tag lending its first
    numeric attribute -- and a block that is neither is no point, so
    its number names nothing."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1, layer='SURVEY'),               # ab_pt elsewhere
           ab_pt(vm, 100, 0, 2, block='MON'),                 # other block, POINTS
           ab_pt(vm, 100, 100, 3, block='MON', tag='PNT'),    # numeric fallback
           ab_pt(vm, 0, 100, 4, layer='OTHER', block='MON')]  # not a point
    run(vm, ['1', '2', '2', '3', '3', '4', None, None], 'classifier')
    ds = dims(vm)
    assert len(ds) == 2, ds                        # 3 -> 4 named nothing
    assert ds[1][13] == [100.0, 0.0, 0.0] and ds[1][14] == [100.0, 100.0, 0.0]
    assert any('No point numbered "4"' in p for p in vm.printed), vm.printed
    print("ok  classifier   -> ab_pt anywhere, any INSERT on POINTS, numeric"
          " fallback tag; a stray block is not a point")


def test_same_spot_tolerance():
    """Two points within cdo:*exact-eps* of each other sit on the same
    spot: the tie is refused, TO is re-asked, nothing is drawn."""
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1), ab_pt(vm, 0.0005, 0, 2), ab_pt(vm, 100, 0, 3)]
    run(vm, ['1', '2', '3', None], 'same spot')
    ds = dims(vm)
    assert len(ds) == 1 and ds[0][14] == [100.0, 0.0, 0.0], ds
    assert any('sit on the same spot' in p for p in vm.printed), vm.printed
    print("ok  same spot    -> a tie shorter than cdo:*exact-eps* is refused")


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
    test_no_carry_over_between_runs()
    test_esc_restores_state_and_closes_group()
    test_undo_off()
    test_undo_group_wraps_the_run()
    test_a_doubled_number_is_asked_about()
    test_a_doubled_number_can_be_clicked_instead()
    test_the_to_prompt_asks_the_same_way()
    test_a_number_only_one_point_carries_is_not_asked_about()
    test_back_and_enter_at_the_pick()
    test_a_stray_label_is_refused_and_re_asked()
    test_layer_repaired_and_coloured()
    test_point_classifier()
    test_same_spot_tolerance()
    test_no_local_shadows_a_function()
    print("all CDCALLOUT tests passed")
