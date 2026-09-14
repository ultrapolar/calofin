"""Runtime tests: load the real DIMSTAMP.lsp into the AutoLISP VM and
drive c:DIMSTAMP with scripted clicks and answers.  AutoLISP cannot run
outside AutoCAD, so this is where a wrong arity, an unbound function or
a parse that silently drifted has to die.

Script values answer the interactive calls in order: one getpoint per
click (None = Enter, done).  After the first click, the text is a
getstring (the very first placement) or a getkword answer (every later
one) -- None = Enter/repeat, a digit string = pick that numbered
suggestion, "New" = branch to a fresh getstring.  A callable in the
script is called at its prompt -- that is how a scenario presses Esc.
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


def texts(vm):
    out = []
    for e in vm.entities:
        d = _alist_dict(vm.entdata[e])
        if d.get(0) == 'TEXT':
            out.append(d)
    return out


def undo_calls(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def esc(vm):
    """The drafter presses Esc at this prompt."""
    raise LispError('Function cancelled', vm)


# ---- parsing / formatting / suggestions, called directly ------------

def test_parse_and_format_round_trip():
    vm = newvm()
    cases = [
        ('34"', 272, None, None),
        ("3'-4\"", 320, 't', None),
        ('34 1/2"', 276, None, 't'),
        ("3'- 4 1/2\"", 324, 't', 't'),
    ]
    for s, eighths, hasfeet, hasfrac in cases:
        got = vm.loads(f'(ds:parse "{s.replace(chr(34), chr(92)+chr(34))}")')
        assert got == [eighths, hasfeet, hasfrac], (s, got)
        back = vm.loads(f'(ds:format {eighths} {"t" if hasfeet else "nil"})')
        assert back == s, (s, back)
    print("ok  parse/format -> all four canonical forms round-trip")


def test_rejects_malformed_text():
    """Strict about the shape (a mandatory dash after the feet mark, a
    real fraction, a trailing quote) but lenient about incidental
    whitespace around that dash -- "3' -4\"" parses like "3'-4\"", the
    same leniency vl-string-trim gives every other join point."""
    vm = newvm()
    bad = ['34', "3'4\"", '34 1/0"', '"', 'abc"']
    for s in bad:
        esc_s = s.replace('"', '\\"')
        assert vm.loads(f'(ds:parse "{esc_s}")') is None, s
    print("ok  reject       -> malformed text parses to nil")


def test_suggestions_bare_inches():
    """34\" suggests every eighth up to the next whole inch, one
    direction, simplified -- the literal example in the spec."""
    vm = newvm()
    sugg = vm.loads('(ds:suggestions 272 nil nil)')
    rendered = [vm.loads(f'(ds:format {e} nil)') for e in sugg]
    assert rendered == ['34 1/8"', '34 1/4"', '34 3/8"', '34 1/2"',
                        '34 5/8"', '34 3/4"', '34 7/8"', '35"'], rendered
    print("ok  suggest 34\"  -> eighths up to 35\", simplified")


def test_suggestions_feet_inches_no_fraction():
    """3'-4\" suggests quarter-inch steps up and down, then whole-inch
    jumps of 1/2/3 on each side."""
    vm = newvm()
    sugg = vm.loads("(ds:suggestions 320 t nil)")
    rendered = [vm.loads(f'(ds:format {e} t)') for e in sugg]
    assert rendered == [
        '3\'-1"', '3\'-2"', '3\'-3"',
        '3\'- 3 1/4"', '3\'- 3 1/2"', '3\'- 3 3/4"',
        '3\'- 4 1/4"', '3\'- 4 1/2"', '3\'- 4 3/4"',
        '3\'-5"', '3\'-6"', '3\'-7"'], rendered
    print("ok  suggest 3'-4\" -> quarter steps, then 1/2/3\" jumps, per side")


def test_suggestions_with_fraction_use_eighths():
    """Once a fraction is already in the text -- feet or not -- the
    near steps switch from quarters to eighths."""
    vm = newvm()
    sugg_feet = vm.loads('(ds:suggestions 324 t t)')
    assert len(sugg_feet) == 20, sugg_feet
    rendered = [vm.loads(f'(ds:format {e} t)') for e in sugg_feet]
    assert '3\'- 4 1/8"' in rendered and '3\'- 3 7/8"' in rendered, rendered
    # +1"/+3" jumps from 3'-4 1/2" land on 3'-5 1/2" and 3'-7 1/2"
    assert '3\'- 5 1/2"' in rendered and '3\'- 7 1/2"' in rendered, rendered

    sugg_noteet = vm.loads('(ds:suggestions 276 nil t)')
    assert len(sugg_noteet) == 20, sugg_noteet
    rendered2 = [vm.loads(f'(ds:format {e} nil)') for e in sugg_noteet]
    assert '34 5/8"' in rendered2 and '34 3/8"' in rendered2, rendered2
    print("ok  suggest w/frac -> eighth-inch steps instead of quarters")


def test_suggestions_never_go_non_positive():
    vm = newvm()
    # 2 eighths = 1/4": quarter-inch-family suggestions going down would
    # cross zero and below -- those are dropped
    sugg = vm.loads('(ds:suggestions 2 t nil)')
    assert all(e > 0 for e in sugg), sugg
    print("ok  near zero    -> non-positive suggestions dropped")


# ---- the command, end to end ------------------------------------------

def test_first_placement_has_no_suggestion_menu():
    """The very first click has nothing to suggest from -- straight to
    a validated getstring, no keyword menu at all."""
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'first only')
    t = texts(vm)
    assert len(t) == 1 and t[0][1] == '34"', t
    assert t[0][8] == 'DIMENSION' and t[0][40] == 6.0, t[0]
    print("ok  first click  -> plain text prompt, no menu yet")


def test_enter_repeats_last_text():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', (10.0, 0.0), None, None], 'repeat')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', '34"'], t
    print("ok  Enter        -> repeats the last text exactly")


def test_pick_a_numbered_suggestion():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', (10.0, 0.0), '4', None], 'pick #4')
    t = texts(vm)
    # suggestion #4 of 34" -> 34 1/2" (see test_suggestions_bare_inches)
    assert [x[1] for x in t] == ['34"', '34 1/2"'], t
    print("ok  pick a #     -> the numbered suggestion is placed")


def test_new_branches_to_fresh_text():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', (10.0, 0.0), 'New', "3'-6\"", None], 'New')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', "3'-6\""], t
    print("ok  New          -> asks fresh, and that becomes the new"
          " default")


def test_new_takes_the_hidden_capital_hotkey():
    """New's capital letter (N) is accepted the way every keyword's
    capital abbreviation is."""
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', (10.0, 0.0), 'N', "35\"", None], 'N hotkey')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', '35"'], t
    print("ok  N hotkey     -> New's capital abbreviation works")


def test_picked_value_becomes_the_new_default():
    """Whatever the last click landed on -- typed, picked, or New -- is
    what Enter repeats and what the NEXT menu is built from."""
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"',
             (10.0, 0.0), '8',            # -> "35\""
             (20.0, 0.0), None,           # repeats "35\""
             None], 'chained default')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"', '35"', '35"'], t
    print("ok  chaining     -> a pick or a New answer becomes the next"
          " default too")


def test_reprompts_on_malformed_text():
    vm = newvm()
    run(vm, [(0.0, 0.0), 'not a measurement', '34"', None], 'bad first')
    t = texts(vm)
    assert [x[1] for x in t] == ['34"'], t
    assert any('is not one of the four forms' in p for p in vm.printed)
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', (10.0, 0.0), 'New', 'nope', "3'-4\"", None],
        'bad New')
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


def test_esc_mid_run():
    vm = newvm()
    vm.handle_errors = True
    run(vm, [(0.0, 0.0), esc], 'Esc at the first text prompt')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert not any('error' in p.lower() for p in vm.printed), vm.printed
    assert texts(vm) == []

    vm = newvm()
    vm.handle_errors = True
    run(vm, [(0.0, 0.0), '34"', (10.0, 0.0), esc], 'Esc at the second click')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert len(texts(vm)) == 1
    print("ok  Esc          -> handler closes the group and stays"
          " silent, first prompt and mid-run alike")


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
    test_suggestions_bare_inches()
    test_suggestions_feet_inches_no_fraction()
    test_suggestions_with_fraction_use_eighths()
    test_suggestions_never_go_non_positive()
    test_first_placement_has_no_suggestion_menu()
    test_enter_repeats_last_text()
    test_pick_a_numbered_suggestion()
    test_new_branches_to_fresh_text()
    test_new_takes_the_hidden_capital_hotkey()
    test_picked_value_becomes_the_new_default()
    test_reprompts_on_malformed_text()
    test_no_clicks()
    test_undo_group_wraps_the_run()
    test_undo_off()
    test_esc_mid_run()
    test_layer_repaired_and_coloured()
    test_knobs_reach_the_output()
    test_no_local_shadows_a_function()
    print("all DIMSTAMP tests passed")
