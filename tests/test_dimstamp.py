"""Runtime tests: load the real DIMSTAMP.lsp into the AutoLISP VM and
drive c:DIMSTAMP with scripted clicks and answers.  AutoLISP cannot run
outside AutoCAD, so this is where a wrong arity, an unbound function or
a parse that silently drifted has to die.

Script values answer the interactive calls in order: one getpoint per
click (None = Enter, done).  After the first click the text is a
getstring (the very first placement).  Every later prompt is ONE
getpoint that stands in for three things at once: a point that is not
on the ruler (a tuple) stamps there; a point that lands on one of the
ruler's rows (read off ds:draw-ruler's own row table) adopts that
row's value instead of stamping; a string answers the same prompt's
typed-text fallback and is parsed as a brand new value.  A callable in
the script is called at its prompt -- that is how a scenario presses
Esc.
Run: python3 tests/test_dimstamp.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_dimstamp.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'dimstamp', 'DIMSTAMP.lsp')


def newvm():
    vm = VM()
    vm.load(LSP)
    return vm


def run(vm, script, label):
    try:
        vm.run('c:DIMSTAMP', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def _alist_dict(alist):
    d = {}
    for p in alist:
        if hasattr(p, 'a'):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


def live_entities(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        out.append(_alist_dict(vm.entdata[e]))
    return out


def texts(vm):
    return [d for d in live_entities(vm) if d.get(0) == 'TEXT']


def by_type(vm):
    from collections import Counter
    c = Counter()
    for d in live_entities(vm):
        c[d.get(0)] += 1
    return c


def undo_calls(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def esc(vm):
    """The drafter presses Esc at this prompt."""
    raise LispError('Function cancelled', vm)


# ---- parsing / formatting / tiering / suggestions, called directly ----

def test_parse_and_format_round_trip():
    vm = newvm()
    cases = [
        ('34"', 272, None),
        ("3'-4\"", 320, 't'),
        ('34 1/2"', 276, None),
        ("3'- 4 1/2\"", 324, 't'),
    ]
    for s, eighths, hasfeet in cases:
        esc_s = s.replace('"', '\\"')
        got = vm.loads(f'(ds:parse "{esc_s}")')
        assert got == [eighths, hasfeet], (s, got)
        back = vm.loads(f'(ds:format {eighths} {"t" if hasfeet else "nil"})')
        assert back == s, (s, back)
    print("ok  parse/format -> all four canonical forms round-trip")


def test_rejects_malformed_text():
    vm = newvm()
    bad = ['34', "3'4\"", '34 1/0"', '"', 'abc"']
    for s in bad:
        esc_s = s.replace('"', '\\"')
        assert vm.loads(f'(ds:parse "{esc_s}")') is None, s
    print("ok  reject       -> malformed text parses to nil")


def test_tier_grading():
    vm = newvm()
    got = [vm.loads(f'(ds:tier {i})') for i in range(1, 9)]
    assert got == ['eighth', 'quarter', 'eighth', 'half',
                   'eighth', 'quarter', 'eighth', 'jump'], got
    # symmetric on the negative side too
    got_neg = [vm.loads(f'(ds:tier {-i})') for i in range(1, 9)]
    assert got_neg == got, got_neg
    print("ok  tier         -> eighth/quarter/half/jump graded by offset")


def test_suggestions_bare_inches():
    """34" suggests every eighth up to the next whole inch, one
    direction -- the literal example in the spec -- each row tagged by
    tier for the ruler to grade.  ds:suggestions itself is unsorted
    (ds:draw-ruler sorts once it also has the current row to place),
    so compare as a set."""
    vm = newvm()
    sugg = vm.loads('(ds:suggestions 272 nil)')
    rendered = {(vm.loads(f'(ds:format {v} nil)'), t) for v, t in sugg}
    assert rendered == {
        ('34 1/8"', 'eighth'), ('34 1/4"', 'quarter'), ('34 3/8"', 'eighth'),
        ('34 1/2"', 'half'), ('34 5/8"', 'eighth'), ('34 3/4"', 'quarter'),
        ('34 7/8"', 'eighth'), ('35"', 'jump')}, rendered
    print("ok  suggest 34\"  -> eighths up to 35\", graded")


def test_suggestions_feet_combine_quarter_and_eighth():
    """3'-4" -- feet involved -- gets BOTH quarter and eighth steps
    together (told apart by tier, not by switching granularity), plus
    the 1/2/3" jumps on each side."""
    vm = newvm()
    sugg = vm.loads("(ds:suggestions 320 t)")
    assert len(sugg) == 20, sugg
    rendered = {vm.loads(f'(ds:format {v} t)'): t for v, t in sugg}
    assert rendered['3\'- 4 1/4"'] == 'quarter', rendered
    assert rendered['3\'- 4 1/8"'] == 'eighth', rendered
    assert rendered['3\'- 4 1/2"'] == 'half', rendered
    assert rendered['3\'-5"'] == 'jump' and rendered['3\'-7"'] == 'jump', \
        rendered
    assert rendered['3\'-1"'] == 'jump', rendered
    print("ok  suggest 3'-4\" -> quarter AND eighth steps together, graded,"
          " plus 1/2/3\" jumps")


def test_suggestions_never_go_non_positive():
    vm = newvm()
    sugg = vm.loads('(ds:suggestions 2 t)')
    assert all(v > 0 for v, t in sugg), sugg
    print("ok  near zero    -> non-positive suggestions dropped")


def test_draw_ruler_geometry():
    """The ruler: a spine, one tick+label row per suggestion plus a
    circled CURRENT row, sizes graded by tier."""
    vm = newvm()
    ents, spx, rows = vm.loads('(ds:draw-ruler (list 0.0 0.0) 272 nil)')
    assert spx == 24.0
    assert len(rows) == 9        # 8 suggestions + the current row
    assert rows[0] == [272, 0.0]  # current sits at the anchor's own row
    assert rows[-1] == [280, 72.0]
    kinds = by_type(vm)
    assert kinds['LINE'] == 10   # 9 ticks + 1 spine
    assert kinds['TEXT'] == 9
    assert kinds['CIRCLE'] == 1
    texts_by_hgt = sorted({d['40'] if False else d.get(40)
                           for d in texts(vm)})
    assert texts_by_hgt[0] < texts_by_hgt[-1], texts_by_hgt
    assert max(texts_by_hgt) == 6.0        # jump/current tier
    print("ok  ruler        -> spine + graded ticks/text + one circled"
          " current row")


# ---- the command, end to end ------------------------------------------

def test_first_placement_has_no_ruler_yet():
    """The very first click has nothing to build a ruler around -- a
    plain validated getstring, no ruler until after it lands."""
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'first only')
    t = texts(vm)
    assert len(t) == 1 and t[0][1] == '34"', t
    assert t[0][8] == 'DIMENSION' and t[0][40] == 6.0, t[0]
    print("ok  first click  -> plain text prompt, ruler drawn only after")


def test_ruler_is_cleaned_up_at_the_end():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'ruler cleanup')
    assert by_type(vm) == {'TEXT': 1}, by_type(vm)
    print("ok  cleanup      -> only the stamped TEXT survives; the ruler"
          " is erased")


def test_click_elsewhere_stamps_the_current_text():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', (200.0, 200.0), None], 'stamp again')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', '34"'], t
    assert t[1][10][:2] == [200.0, 200.0], t[1]
    print("ok  click empty  -> stamps the current text there")


def test_click_a_ruler_row_adopts_without_stamping():
    """34" -> ruler spine at x=24, rows at y=0 (current, 34"), 9 (34
    1/8"), ... 72 (35").  Clicking row y=72 adopts 35" but places
    nothing; the very next stamp click uses it."""
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"',
             (24.0, 72.0),          # ruler row for 35" -- adopt, no stamp
             (100.0, 100.0),        # now stamp with 35"
             None], 'ruler pick')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', '35"'], t
    print("ok  ruler pick   -> adopts the row's value, stamps nothing"
          " until the next click")


def test_typed_text_at_the_unified_prompt_is_adopted():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"',
             "3'-6\"",               # typed at the unified prompt
             (-50.0, -50.0),        # well clear of the ruler -> stamps
             None], 'typed adopt')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', "3'-6\""], t
    print("ok  typed text   -> adopted the same way a ruler pick is")


def test_chained_adoption():
    """Whatever the last click or type landed on becomes what the
    following stamp uses, repeatedly."""
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"',
             (24.0, 72.0),          # adopt 35" off the ruler
             "3'-2\"",               # then type something else entirely
             (10.0, 10.0),          # stamp with 3'-2"
             None], 'chained')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', "3'-2\""], t
    print("ok  chaining     -> a ruler pick or typed value carries"
          " forward to the next stamp")


def test_reprompts_on_malformed_typed_text():
    vm = newvm()
    run(vm, [(0.0, 0.0), 'not a measurement', '34"', None], 'bad first')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"'], t
    assert any('is not one of the four forms' in p for p in vm.printed)

    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', 'nope', "3'-4\"", (5.0, 5.0), None],
        'bad at unified prompt')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', "3'-4\""], t
    print("ok  bad text     -> re-prompts instead of placing garbage")


def test_no_clicks():
    vm = newvm()
    run(vm, [None], 'no clicks')
    assert texts(vm) == []
    print("ok  no clicks    -> nothing drawn")


def test_undo_group_wraps_the_run():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'undo group')
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    print("ok  undo group   -> one _Begin before the stamp, one _End"
          " after")


def test_undo_off():
    vm = newvm()
    vm.sysvars['UNDOCTL'] = 0
    run(vm, [(0.0, 0.0), '34"', None], 'undo off')
    assert undo_calls(vm) == [], vm.commands
    assert len(texts(vm)) == 1
    print("ok  undo off     -> no _.UNDO at all, the stamp still drawn")


def test_esc_mid_run_cleans_up_the_ruler_too():
    vm = newvm()
    vm.handle_errors = True
    run(vm, [(0.0, 0.0), esc], 'Esc at the first text prompt')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert not any('error' in p.lower() for p in vm.printed), vm.printed
    assert texts(vm) == []

    vm = newvm()
    vm.handle_errors = True
    run(vm, [(0.0, 0.0), '34"', esc], 'Esc at the unified prompt')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    # the stamp already placed survives; the ruler scratch does not
    assert by_type(vm) == {'TEXT': 1}, by_type(vm)
    print("ok  Esc          -> handler closes the group, stays silent,"
          " and sweeps the ruler away either way")


def test_layer_repaired_and_coloured():
    vm = newvm()
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "DIMENSION")'
             ' \'(70 . 5) \'(62 . -3) \'(6 . "Continuous")))')
    run(vm, [(0.0, 0.0), '34"', None], 'repair')
    rec = _alist_dict(vm.recdata[vm.tablerecs['LAYER']['DIMENSION']])
    assert rec[70] == 0 and rec[62] == 3, rec
    assert any('was off, frozen or locked' in p for p in vm.printed), \
        vm.printed
    print("ok  layer        -> DIMENSION repaired when unusable")


def test_knobs_reach_the_output():
    vm = newvm()
    vm.loads('(setq ds:*layer* "MyDims" ds:*text-hgt* 9.0)')
    run(vm, [(0.0, 0.0), '34"', None], 'knobs')
    t = texts(vm)[0]
    assert t[8] == 'MyDims' and t[40] == 9.0, t
    print("ok  knobs        -> layer and text height read at run time")


def test_no_local_shadows_a_function():
    import re
    src = open(LSP).read()
    src = re.sub(r';[^\n]*', '', src)
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)
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
    test_parse_and_format_round_trip()
    test_rejects_malformed_text()
    test_tier_grading()
    test_suggestions_bare_inches()
    test_suggestions_feet_combine_quarter_and_eighth()
    test_suggestions_never_go_non_positive()
    test_draw_ruler_geometry()
    test_first_placement_has_no_ruler_yet()
    test_ruler_is_cleaned_up_at_the_end()
    test_click_elsewhere_stamps_the_current_text()
    test_click_a_ruler_row_adopts_without_stamping()
    test_typed_text_at_the_unified_prompt_is_adopted()
    test_chained_adoption()
    test_reprompts_on_malformed_typed_text()
    test_no_clicks()
    test_undo_group_wraps_the_run()
    test_undo_off()
    test_esc_mid_run_cleans_up_the_ruler_too()
    test_layer_repaired_and_coloured()
    test_knobs_reach_the_output()
    test_no_local_shadows_a_function()
    print("all DIMSTAMP tests passed")
