"""Runtime tests: load the real BPCALLOUT.lsp into the AutoLISP VM and
drive c:BPCALLOUT with scripted clicks.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (distance ...) has to die.

Script values answer the interactive calls in order: one getpoint per
click (None = Enter, done), then one getpoint for the text location
(None = take the default spot).  The "_X" point sweep takes no scripted
answer: ssget "_X" reads the drawing and never prompts, so the points a
scenario builds with ab_pt are what it finds.  A callable in the script
is called at its prompt -- that is how a scenario presses Esc.
Run: python3 tests/test_bpcallout.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_bpcallout.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'bpcallout', 'BPCALLOUT.lsp')


# ---- drawing scaffolding ---------------------------------------------

def newvm():
    vm = VM()
    vm.load(LSP)
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
        vm.run('c:BPCALLOUT', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def _alist_dict(alist):
    d = {}
    for p in alist:
        if isinstance(p, Dot):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


def made(vm, etype):
    out = []
    for e in vm.entities:
        if e in vm.deleted:        # un-ringed circles are entdel'd
            continue
        d = _alist_dict(vm.entdata[e])
        if d.get(0) == etype and 40 in d:
            out.append(d)
    return out


def centers(circles):
    return sorted((round(c[10][0], 6), round(c[10][1], 6))
                  for c in circles)


def undo_calls(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def layer_rec(vm, name):
    return _alist_dict(vm.recdata[vm.tablerecs['LAYER'][name.upper()]])


def esc(vm):
    """The drafter presses Esc at this prompt."""
    raise LispError('Function cancelled', vm)


# ---- tests -----------------------------------------------------------

def test_three_points():
    vm = newvm()
    ab_pt(vm, 0, 0, 12)
    ab_pt(vm, 100, 0, 15)
    ab_pt(vm, 100, 100, 20)
    # clicks land near, not on, each point: the ring must snap to the
    # point itself
    run(vm, [(3.0, 4.0), (98.0, 2.0), (101.0, 99.0), None,
             (50.0, 50.0)], 'three points')
    circles = made(vm, 'CIRCLE')
    assert len(circles) == 3, circles
    assert all(c[8] == 'FGStep' and c[40] == 5.0 for c in circles), circles
    assert centers(circles) == [(0.0, 0.0), (100.0, 0.0), (100.0, 100.0)]
    texts = made(vm, 'TEXT')
    assert len(texts) == 1, texts
    assert texts[0][1] == 'Pt.12, Pt.15 and Pt.20 are bad', texts
    assert texts[0][8] == 'FGStep' and texts[0][40] == 6.0
    assert texts[0][10][:2] == [50.0, 50.0]
    print("ok  three points -> three rings + 'Pt.12, Pt.15 and Pt.20"
          " are bad'")


def test_one_point():
    vm = newvm()
    ab_pt(vm, 0, 0, 7)
    run(vm, [(1.0, 1.0), None, (10.0, 10.0)], 'one point')
    texts = made(vm, 'TEXT')
    assert texts[0][1] == 'Pt.7 is bad', texts
    print("ok  one point   -> 'Pt.7 is bad'")


def test_two_points():
    vm = newvm()
    ab_pt(vm, 0, 0, 3)
    ab_pt(vm, 50, 0, 4)
    run(vm, [(0.0, 0.0), (50.0, 0.0), None, (25.0, 25.0)], 'two')
    texts = made(vm, 'TEXT')
    assert texts[0][1] == 'Pt.3 and Pt.4 are bad', texts
    print("ok  two points  -> 'Pt.3 and Pt.4 are bad'")


def test_far_click_is_unknown():
    vm = newvm()
    ab_pt(vm, 0, 0, 9)
    # 30 away from the only point: farther than the 12" snap, so the
    # ring goes where clicked and the point reads as "?"
    run(vm, [(30.0, 0.0), None, (10.0, 10.0)], 'far click')
    circles = made(vm, 'CIRCLE')
    assert centers(circles) == [(30.0, 0.0)], circles
    texts = made(vm, 'TEXT')
    assert texts[0][1] == 'Pt.? is bad', texts
    print("ok  far click   -> ring at the pick, 'Pt.? is bad'")


def test_nearest_of_several_within_snap():
    """Two points both within the 12" snap of the pick: the nearer one
    is ringed, and only it."""
    vm = newvm()
    ab_pt(vm, 0, 0, 1)
    ab_pt(vm, 10, 0, 2)
    run(vm, [(6.0, 0.0), None, None], 'nearest')
    assert centers(made(vm, 'CIRCLE')) == [(10.0, 0.0)], made(vm, 'CIRCLE')
    assert made(vm, 'TEXT')[0][1] == 'Pt.2 is bad'
    print("ok  nearest     -> of two points within snap, the nearer is"
          " ringed")


def test_reclick_unrings():
    # clicking a ringed point again removes its ring and drops it from
    # the callout - reselecting a point is how you undo it
    vm = newvm()
    ab_pt(vm, 0, 0, 5)
    ab_pt(vm, 50, 0, 6)
    run(vm, [(1.0, 0.0), (50.0, 0.0), (0.0, 1.0), None,
             (25.0, 25.0)], 'reclick')
    circles = made(vm, 'CIRCLE')
    assert len(circles) == 1, circles
    texts = made(vm, 'TEXT')
    assert texts[0][1] == 'Pt.6 is bad', texts
    print("ok  reclick     -> second click on Pt.5 un-rings it")


def test_unring_then_rering():
    # un-ring, then a third click rings the point again
    vm = newvm()
    ab_pt(vm, 0, 0, 7)
    run(vm, [(0.0, 0.0), (0.0, 0.0), (1.0, 1.0), None,
             (9.0, 9.0)], 'rering')
    assert len(made(vm, 'CIRCLE')) == 1
    assert made(vm, 'TEXT')[0][1] == 'Pt.7 is bad'
    print("ok  re-ring     -> third click rings Pt.7 again")


def test_unring_far_pick_inside_ring():
    # a "Pt.?" ring (no survey point under it) is un-rung by clicking
    # inside the ring, even though the raw picks differ
    vm = newvm()
    ab_pt(vm, 0, 0, 3)
    run(vm, [(30.0, 0.0), (33.0, 0.0), None], 'far unring')
    assert made(vm, 'CIRCLE') == [] and made(vm, 'TEXT') == []
    print("ok  far unring  -> click inside a Pt.? ring removes it")


def test_snap_never_unrings_a_neighbour():
    """The v1.7 bug: two survey points 8" apart under 5" rings.  Ring
    Pt.1, then click 4.5 from it -- nearer Pt.2, so the snap picks
    Pt.2 -- and v1.7 read the raw pick against the rings as well, found
    it inside Pt.1's, and un-ringed Pt.1 instead of ringing Pt.2, so
    two points under 10" apart could never both be ringed.  Only a
    click with NO survey point under it is read against the rings."""
    vm = newvm()
    ab_pt(vm, 0, 0, 1)
    ab_pt(vm, 8, 0, 2)
    run(vm, [(0.0, 0.0), (4.5, 0.0), None, None], 'neighbour')
    assert centers(made(vm, 'CIRCLE')) == [(0.0, 0.0), (8.0, 0.0)], \
        made(vm, 'CIRCLE')
    assert made(vm, 'TEXT')[0][1] == 'Pt.1 and Pt.2 are bad'
    # ...while a click that snaps to Pt.2 itself still un-rings Pt.2
    vm = newvm()
    ab_pt(vm, 0, 0, 1)
    ab_pt(vm, 8, 0, 2)
    run(vm, [(0.0, 0.0), (4.5, 0.0), (7.0, 0.0), None, None],
        'neighbour, then un-ring')
    assert centers(made(vm, 'CIRCLE')) == [(0.0, 0.0)], made(vm, 'CIRCLE')
    assert made(vm, 'TEXT')[0][1] == 'Pt.1 is bad'
    print("ok  neighbour   -> a click that snaps to Pt.2 rings Pt.2 and"
          " never un-rings Pt.1 beside it")


def test_point_kinds():
    """The classifier: an ab_pt INSERT on ANY layer, any other INSERT on
    the POINTS layer, a plain POINT on POINTS -- and nothing else.  A
    block without the number tag lends its first numeric attribute; one
    with no readable number at all rings as Pt.?."""
    vm = newvm()
    ab_pt(vm, 0, 0, 5, layer='SURVEY')                 # ab_pt elsewhere
    ab_pt(vm, 100, 0, 6, block='MON')                  # other block, POINTS
    ab_pt(vm, 200, 0, 7, block='MON', tag='PNT')       # numeric fallback tag
    ab_pt(vm, 300, 0, 'A-1', block='MON', tag='DESC')  # nothing numeric
    ab_pt(vm, 400, 0, 8, layer='OTHER', block='MON')   # not a point at all
    pt = Ent()                                          # plain POINT, POINTS
    vm.entities.append(pt)
    vm.entdata[pt] = [Dot(0, 'POINT'), Dot(8, 'POINTS'),
                      [10, 500.0, 0.0, 0.0]]
    run(vm, [(1.0, 0.0), (101.0, 0.0), (201.0, 0.0), (301.0, 0.0),
             (401.0, 0.0), (501.0, 0.0), None, None], 'kinds')
    # the stray block at 400 is no point, so that click rings the pick
    assert centers(made(vm, 'CIRCLE')) == [
        (0.0, 0.0), (100.0, 0.0), (200.0, 0.0), (300.0, 0.0),
        (401.0, 0.0), (500.0, 0.0)], made(vm, 'CIRCLE')
    assert made(vm, 'TEXT')[0][1] == \
        'Pt.5, Pt.6, Pt.7, Pt.?, Pt.? and Pt.? are bad', made(vm, 'TEXT')
    print("ok  classifier  -> ab_pt anywhere, any INSERT/POINT on POINTS,"
          " numeric fallback tag, Pt.? for the rest")


def test_default_text_spot():
    vm = newvm()
    ab_pt(vm, 0, 0, 2)
    # Enter at the text prompt: the callout tucks beside the last ring
    run(vm, [(0.0, 0.0), None, None], 'default spot')
    texts = made(vm, 'TEXT')
    assert texts[0][10][:2] == [10.0, -10.0], texts
    print("ok  Enter       -> text beside the last ring")


def test_knobs_reach_the_output():
    """Every knob is read at run time, so a startup file can (setq ...)
    them after loading: the wording, the unknown label, the text gap
    and height, the ring radius."""
    vm = newvm()
    vm.loads('(setq bp:*pt-prefix* "Point " bp:*tail-one* " is off"'
             ' bp:*tail-many* " are off" bp:*unknown* "??"'
             ' bp:*text-gap* 3.0 bp:*radius* 2.5 bp:*text-hgt* 4.0)')
    ab_pt(vm, 0, 0, 12)
    run(vm, [(0.0, 0.0), (50.0, 0.0), None, None], 'knobs')
    circles = made(vm, 'CIRCLE')
    assert len(circles) == 2 and all(c[40] == 2.5 for c in circles), circles
    t = made(vm, 'TEXT')[0]
    assert t[1] == 'Point 12 and Point ?? are off', t
    assert t[40] == 4.0 and t[10][:2] == [53.0, -3.0], t
    print("ok  knobs       -> prefix, tails, unknown label, gap, radius and"
          " height all read at run time")


def test_layer_repaired_and_coloured():
    """FGStep frozen, locked and off is thawed, unlocked and switched on
    before the first ring, and the run says so; a missing FGStep is
    created in bp:*layer-color*."""
    vm = newvm()
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "FGStep")'
             ' \'(70 . 5) \'(62 . -3) \'(6 . "Continuous")))')
    ab_pt(vm, 0, 0, 1)
    run(vm, [(0.0, 0.0), None, None], 'repair')
    rec = layer_rec(vm, 'FGStep')
    assert rec[70] == 0 and rec[62] == 3, rec
    assert len(made(vm, 'CIRCLE')) == 1
    assert any('was off, frozen or locked' in p for p in vm.printed), \
        vm.printed
    # created from scratch: the colour knob decides, red by default
    vm = newvm()
    ab_pt(vm, 0, 0, 1)
    run(vm, [(0.0, 0.0), None, None], 'default colour')
    assert layer_rec(vm, 'FGStep')[62] == 1, layer_rec(vm, 'FGStep')
    vm = newvm()
    vm.loads('(setq bp:*layer-color* 4)')
    ab_pt(vm, 0, 0, 1)
    run(vm, [(0.0, 0.0), None, None], 'colour knob')
    assert layer_rec(vm, 'FGStep')[62] == 4, layer_rec(vm, 'FGStep')
    print("ok  layer       -> FGStep repaired when unusable, created in the"
          " knob's colour")


def test_no_clicks():
    vm = newvm()
    ab_pt(vm, 0, 0, 1)
    run(vm, [None], 'no clicks')
    assert made(vm, 'CIRCLE') == [] and made(vm, 'TEXT') == []
    print("ok  no clicks   -> nothing drawn")


def test_empty_drawing():
    vm = newvm()
    run(vm, [(5.0, 5.0), None, (0.0, 0.0)], 'empty drawing')
    circles = made(vm, 'CIRCLE')
    assert centers(circles) == [(5.0, 5.0)], circles
    assert made(vm, 'TEXT')[0][1] == 'Pt.? is bad'
    print("ok  no points   -> ring at the pick, 'Pt.? is bad'")


def test_undo_group_wraps_the_run():
    vm = newvm()
    ab_pt(vm, 0, 0, 1)
    run(vm, [(0.0, 0.0), None, None], 'undo group')
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    print("ok  undo group  -> one _Begin before the rings, one _End after")


def test_undo_off():
    """UNDOCTL with bit 1 clear: no group is opened -- and none is
    closed either.  An _End with no group open is an error in the VM,
    as the stray UNDO prompt is in AutoCAD."""
    vm = newvm()
    vm.sysvars['UNDOCTL'] = 0
    ab_pt(vm, 0, 0, 1)
    run(vm, [(0.0, 0.0), None, None], 'undo off')
    assert undo_calls(vm) == [], vm.commands
    assert len(made(vm, 'CIRCLE')) == 1 and len(made(vm, 'TEXT')) == 1
    print("ok  undo off    -> no _.UNDO at all, the marks still drawn")


def test_esc_mid_run():
    """Esc at the second click with one ring already down, and Esc at
    the text prompt: the handler closes the group it opened (the ring
    stays -- one U takes it), prints nothing about an error, and the
    command hands the session back clean (run() itself refuses to
    return with an undo group open)."""
    vm = newvm()
    vm.handle_errors = True
    ab_pt(vm, 0, 0, 1)
    run(vm, [(0.0, 0.0), esc], 'Esc at a click')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert not any('error' in p.lower() for p in vm.printed), vm.printed
    assert len(made(vm, 'CIRCLE')) == 1 and made(vm, 'TEXT') == []
    vm = newvm()
    vm.handle_errors = True
    ab_pt(vm, 0, 0, 1)
    run(vm, [(0.0, 0.0), None, esc], 'Esc at the text prompt')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert made(vm, 'TEXT') == []
    print("ok  Esc         -> handler closes the group and stays silent, at"
          " a click and at the text prompt")


def test_no_local_shadows_a_function():
    """The bug that shipped in v1.0: c:BPCALLOUT declared a local named
    "last", which in AutoLISP shadows the built-in for the whole call,
    so (last picked) died with "no function definition: LAST" the
    moment a run got as far as placing the text.  Every name any defun
    here declares must stay clear of the functions the file calls."""
    import re
    src = open(LSP).read()
    src = re.sub(r';[^\n]*', '', src)            # strip comments
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)  # and string literals
    arglists = re.findall(r'\(defun\s+[^\s()]+\s*\(([^)]*)\)', src)
    # the arglists themselves are parenthesised, so they have to come
    # out before heads-of-lists are read as the functions being called
    bodies = re.sub(r'\(defun\s+[^\s()]+\s*\([^)]*\)', '(defun', src)
    called = set(re.findall(r'\(\s*([a-zA-Z][\w:*<>=+/-]*)', bodies))
    bad = []
    for arglist in arglists:
        for name in arglist.replace('/', ' ').split():
            if name.lower() in called:
                bad.append(name)
    assert not bad, f"locals shadowing functions they call: {sorted(set(bad))}"
    print("ok  no shadow   -> no local hides a function the file calls")


if __name__ == '__main__':
    test_three_points()
    test_one_point()
    test_two_points()
    test_far_click_is_unknown()
    test_nearest_of_several_within_snap()
    test_reclick_unrings()
    test_unring_then_rering()
    test_unring_far_pick_inside_ring()
    test_snap_never_unrings_a_neighbour()
    test_point_kinds()
    test_default_text_spot()
    test_knobs_reach_the_output()
    test_layer_repaired_and_coloured()
    test_no_clicks()
    test_empty_drawing()
    test_undo_group_wraps_the_run()
    test_undo_off()
    test_esc_mid_run()
    test_no_local_shadows_a_function()
    print("all BPCALLOUT tests passed")
