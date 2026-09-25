# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for PERPMARKSTAMP.lsp: load PERPMARK.lsp and the real
file into the repo's AutoLISP interpreter and drive c:PERPMARKSTAMP
from a script.

PERPMARKSTAMP copies nothing of PERPMARK -- it installs the hook
PERPMARK v1.13 carries (pm:run-hooked) and hands over -- so what is
worth pinning is the seam: that the stamp prompt comes after every
mark and every answer to it does what it says (Enter at the mark's
end, a click where it landed, Skip nothing, Back the mark gone), that
the stamp RIDES on its mark (Back and a re-mark take it away, the join
leaves it standing), that the stamp is DIMSTAMP's MTEXT spelled the
way the distance was typed, that the ruler is down while the stamp
prompt is up, and that the hook is consumed -- a plain PERPMARK run
after this one, or after an Esc inside it, stamps nothing.

The scripted answers are the prompts in order: the perimeter for
entsel, then point / distance / stamp per mark (a stamp answer is None
for Enter, a point [x, y, 0.0] for a click, or "Skip"/"Back"), nil for
the Enter that ends the round, the Yes/No, the two run ends and the
dimension style.  A callable in the script is called at its prompt,
with the VM -- that is how a scenario looks at the drawing mid-run, or
presses Esc.

Run: python3 tests/test_perpmarkstamp.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_perpmarkstamp.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Ent, Dot, LispError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PERPMARK = os.path.join(HERE, '..', 'lisp', 'perpmark', 'PERPMARK.lsp')
LSP = os.path.join(HERE, '..', 'lisp', 'perpmarkstamp', 'PERPMARKSTAMP.lsp')

#: the dimension-style answer every run that joins has to give
STY = "SIde"

#: the height code every drawn fraction is wrapped in, and the
#: alignment code the line carrying one opens with -- the pair the
#: shop's own dimension text carries (DIMSTAMP's test pins the same)
FULL = '{\\H1.0000x;'
MID = '\\A1;'


# ---- drawing scaffolding (PERPMARK's) ---------------------------------

def newvm(with_perpmark=True, dimstyles=('STANDARD', 'STANDARD INCHES',
                                         'SIDE STANDARD')):
    """The VM remaps both lisp/ paths to the grouped twins under
    CALOFIN_LISP_ROOT=shared, loading the library first."""
    vm = VM()
    if with_perpmark:
        vm.load(PERPMARK)
    vm.load(LSP)
    for s in dimstyles:
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    vm.printed = []
    return vm


def ab_pt(vm, x, y, number):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'INSERT'), Dot(8, 'POINTS'), Dot(2, 'ab_pt'),
                     [10, float(x), float(y), 0.0]]
    att = Ent()
    vm.entities.append(att)
    vm.entdata[att] = [Dot(0, 'ATTRIB'), Dot(2, 'number'), Dot(1, str(number))]
    return e


def rect(vm):
    """The reference pool: 120 x 60, drawn counterclockwise from its
    bottom-left corner, so the bottom wall runs station 0 -> 120 and a
    mark off it runs UP, into the water."""
    e = Ent()
    vm.entities.append(e)
    d = [Dot(0, 'LWPOLYLINE'), Dot(8, 'POOL'), Dot(90, 4), Dot(70, 1)]
    for p in [(0, 0), (120, 0), (120, 60), (0, 60)]:
        d.append([10, float(p[0]), float(p[1])])
    vm.entdata[e] = d
    return e


def bottom_wall_points(vm, *xs):
    return [ab_pt(vm, x, 0, i + 1) for i, x in enumerate(xs)]


def run(vm, script, label='PERPMARKSTAMP'):
    try:
        vm.run('c:PERPMARKSTAMP', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def groups(vm, e):
    d = {}
    for g in vm.entdata[e]:
        if isinstance(g, Dot):
            d.setdefault(g.a, g.b)
        elif isinstance(g, list) and g:
            d.setdefault(g[0], g[1] if len(g) == 2 else g[1:])
    return d


def live(vm, etype):
    return [groups(vm, e) for e in vm.entities
            if e not in vm.deleted and groups(vm, e).get(0) == etype]


def stamps(vm, layer='TEXT'):
    """The MTEXT left on the stamp layer -- what this tool exists to
    add to PERPMARK's run."""
    return [d for d in live(vm, 'MTEXT') if d.get(8) == layer]


def said(vm, text):
    return any(text in s for s in vm.printed)


def near(a, b, eps=1e-6):
    return abs(a - b) < eps


def at(d, x, y):
    p = d[10]
    return near(p[0], x) and near(p[1], y)


def ruler_scratch(vm):
    """The ruler's live entities: its own colour on the marks layer."""
    return [e for e in vm.entities
            if e not in vm.deleted
            and groups(vm, e).get(62) == 3
            and groups(vm, e).get(8) == 'PERPMARK']


def stamp_prompts(vm):
    return [p for p in vm.prompts if 'Click where to stamp' in (p[0] or '')]


# ---- the seam ---------------------------------------------------------

def test_enter_stamps_at_the_end_of_the_mark():
    """Pt.7 at (40,0) taped 9: the mark's far end is (40,9), and Enter
    at the stamp prompt puts the text there."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, None, None, "No"])
    st = stamps(vm)
    assert len(st) == 1, st
    assert at(st[0], 40, 9), st[0][10]
    assert st[0][1] == '9"', st[0][1]
    assert len(live(vm, 'CIRCLE')) == 1 and len(live(vm, 'LINE')) == 1
    assert said(vm, '9" stamped at the end of the mark'), vm.printed
    print("ok  enter       -> 9\" stamped at the far end of the mark")


def test_the_prompt_names_the_distance_and_the_point():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, None, None, "No"])
    ps = stamp_prompts(vm)
    assert len(ps) == 1, vm.prompts
    assert ps[0][0] == ('\nClick where to stamp 9" for Pt.7 [Skip/Back]'
                        " <at the mark's end>: "), ps[0][0]
    print("ok  prompt      -> names the distance and the point, offers Skip/Back")


def test_a_click_stamps_there():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, [55.0, 22.0, 0.0], None, "No"])
    st = stamps(vm)
    assert len(st) == 1 and at(st[0], 55, 22), st
    assert said(vm, '9" stamped.'), vm.printed
    print("ok  click       -> the stamp lands where the click did")


def test_skip_stamps_nothing_and_keeps_the_mark():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, "Skip", None, "No"])
    assert stamps(vm) == [], stamps(vm)
    assert len(live(vm, 'CIRCLE')) == 1 and len(live(vm, 'LINE')) == 1
    assert said(vm, "Pt.7 not stamped"), vm.printed
    print("ok  skip        -> no stamp, the mark stays")


def test_back_at_the_stamp_prompt_takes_the_mark_away():
    """Back here is the same step back as Back at the next point prompt:
    the mark just drawn goes, and the point prompt comes round again."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, "Back", None])
    assert stamps(vm) == []
    assert live(vm, 'CIRCLE') == [] and live(vm, 'LINE') == []
    assert said(vm, "Pt.7 undone"), vm.printed
    assert said(vm, "Nothing marked"), vm.printed
    print("ok  back        -> the mark goes, nothing stamped, nothing marked")


def test_undo_is_back_at_the_stamp_prompt():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, "Undo", None])
    assert stamps(vm) == [] and live(vm, 'CIRCLE') == []
    print("ok  undo        -> the hidden alias of Back")


def test_back_at_the_next_point_takes_the_stamp_with_the_mark():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 80)
    run(vm, [vm.entities[0], "1", 12.0, None, "2", 6.0, None,
             "Back", None, "No"])
    st = stamps(vm)
    assert len(st) == 1 and at(st[0], 20, 12), st
    assert len(live(vm, 'CIRCLE')) == 1
    assert said(vm, "Pt.2 undone"), vm.printed
    print("ok  back later  -> Pt.2's stamp went with Pt.2's mark")


def test_a_re_mark_replaces_the_stamp():
    """Naming Pt.7 again is a correction: the 9 goes, mark and stamp,
    and the 12 is stamped where the new mark's end is."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, None, "7", 12.0, None, None, "No"])
    st = stamps(vm)
    assert len(st) == 1 and at(st[0], 40, 12) and st[0][1] == '12"', st
    circ = live(vm, 'CIRCLE')
    assert len(circ) == 1 and near(circ[0][40], 12.0), circ
    print("ok  re-mark     -> one stamp, the new distance, at the new end")


def test_the_join_leaves_the_stamps_standing():
    """The whole PERPMARK run, stamped: the circles go, the lines become
    dimensions, and every stamp is still there beside its dimension."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 5, 20, 60, 100, 115)
    run(vm, [vm.entities[0],
             "2", 12.0, None,
             "3", 18.0, [62.0, 30.0, 0.0],
             "4", 12.0, None,
             None, "Yes", "1", "5", STY])
    st = stamps(vm)
    assert len(st) == 3, st
    assert sorted((round(d[10][0]), round(d[10][1])) for d in st) == \
        [(20, 12), (62, 30), (100, 12)], [d[10] for d in st]
    assert live(vm, 'CIRCLE') == [] and live(vm, 'LINE') == []
    dims = live(vm, 'DIMENSION')
    assert len(dims) == 3 and all(d[3] == 'SIDE STANDARD' for d in dims)
    polys = live(vm, 'LWPOLYLINE')
    assert len(polys) == 2, "the perimeter and the joined run"
    print("ok  join        -> polyline, 3 dims, and all 3 stamps standing")


def test_no_keeps_marks_and_stamps_together():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 80)
    run(vm, [vm.entities[0], "1", 12.0, None, "2", 6.0, None, None, "No"])
    assert len(stamps(vm)) == 2
    assert len(live(vm, 'CIRCLE')) == 2 and len(live(vm, 'LINE')) == 2
    assert live(vm, 'DIMENSION') == []
    print("ok  no          -> two marks, two stamps, nothing joined")


# ---- what a stamp is --------------------------------------------------

def test_the_spelling_follows_what_was_typed():
    """44-1/2 typed in inches stamps 44 1/2\" with the half stacked;
    3'8 typed in feet stamps 3'-8\"; and a plain 45 typed after the
    feet answer is spelled as IT was typed, in inches -- every typed
    answer picks its own family, as the ruler beside it does."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 60, 100)
    run(vm, [vm.entities[0],
             "1", "44-1/2", None,
             "2", "3'8", None,
             "3", "45", None,
             None, "No"])
    texts = [d[1] for d in stamps(vm)]
    assert MID + '44' + FULL + '\\S1/2;}"' in texts, texts
    assert "3'-8\"" in texts, texts
    assert '45"' in texts, texts
    ps = stamp_prompts(vm)
    assert 'stamp 44 1/2" for Pt.1' in ps[0][0], ps[0][0]
    assert "stamp 3'-8\" for Pt.2" in ps[1][0], ps[1][0]
    print("ok  spelling    -> inches as typed, feet as typed, each answer its own")


def test_a_stamp_carries_the_shop_mtext_properties():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, None, None, "No"])
    d = stamps(vm)[0]
    assert d[8] == 'TEXT', d
    assert d[7] == 'Attributes', d
    assert near(d[40], 6.0), d
    assert near(d[41], 0.0), d          # no wrap
    assert d[71] == 1, d                # top left
    assert d[72] == 5, d                # direction by style
    assert near(d[50], 0.0), d          # upright in the world UCS
    assert 62 not in d, "a stamp is ByLayer"
    assert 'TEXT' in vm.tables['LAYER'], sorted(vm.tables['LAYER'])
    assert 'Attributes' in vm.tables['STYLE'], sorted(vm.tables['STYLE'])
    print("ok  properties  -> DIMSTAMP's MTEXT: TEXT, Attributes, 6\", top left")


def test_a_missing_style_is_made_and_reported():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, None, None, "No"])
    assert said(vm, "text style Attributes was not in this drawing"), vm.printed
    assert 'Attributes' in vm.tables['STYLE']
    print("ok  style       -> made when missing, and said so")


def test_the_knobs_reach_the_output():
    vm = newvm()
    vm.loads('(setq pms:*layer* "NOTES" pms:*layer-color* 4 '
             '      pms:*style* "Plain" pms:*text-hgt* 4.0)')
    vm.tables['STYLE'].add('Plain')
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, None, None, "No"])
    st = stamps(vm, 'NOTES')
    assert len(st) == 1, live(vm, 'MTEXT')
    assert st[0][7] == 'Plain' and near(st[0][40], 4.0), st
    assert 'NOTES' in vm.tables['LAYER']
    assert not said(vm, "was not in this drawing"), vm.printed
    print("ok  knobs       -> layer, colour, style and height")


# ---- the seam with PERPMARK's own machinery ---------------------------

def test_the_ruler_is_down_while_the_stamp_prompt_is_up():
    """From the second distance on PERPMARK's ruler stands beside the
    distance prompt; it is taken down before the stamp prompt, so a
    click there cannot land on a row, and it is back for the next
    distance."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 60, 100)
    seen = []

    def look(_vm):
        seen.append(len(ruler_scratch(_vm)))
        return None

    def at_distance(_vm):
        seen.append(('dist', len(ruler_scratch(_vm))))
        return 12.0

    run(vm, [vm.entities[0], "1", 12.0, look, "2", at_distance, look,
             "3", at_distance, look, None, "No"])
    # stamp prompts: nothing of the ruler up; distance prompts from the
    # second on: the ruler up round the last distance
    assert seen[0] == 0 and seen[2] == 0 and seen[4] == 0, seen
    assert seen[1][0] == 'dist' and seen[1][1] > 0, seen
    assert seen[3][0] == 'dist' and seen[3][1] > 0, seen
    assert ruler_scratch(vm) == [], "nothing of the ruler is left at the end"
    print("ok  ruler       -> down at every stamp prompt, up again for the next distance")


def test_the_hook_is_consumed_by_the_run():
    """A plain PERPMARK run after a stamped one asks no stamp question
    and stamps nothing: the hook was read into the run and cleared."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, None, None, "No"])
    assert len(stamps(vm)) == 1
    vm.run('c:PERPMARK', [vm.entities[0], "7", 12.0, None, "No"])
    assert len(stamps(vm)) == 1, "the plain run must not stamp"
    assert stamp_prompts(vm) == [], vm.prompts
    assert vm.loads('(if (null pm:*after-mark*) 1 0)') == 1, "the hook is still set"
    print("ok  consumed    -> a plain PERPMARK run after it stamps nothing")


def test_esc_at_the_stamp_prompt_is_perpmarks_esc():
    """Esc at the stamp prompt reaches PERPMARK's handler: its settings
    come back, its ruler comes down, its group is closed, the cancel is
    silent -- and the NEXT plain run finds no hook standing."""
    vm = newvm()
    vm.sysvars['CLAYER'] = '0'
    vm.sysvars['OSMODE'] = 33
    vm.handle_errors = True
    rect(vm)
    bottom_wall_points(vm, 20, 60)

    def esc(_vm):
        raise LispError('Function cancelled', _vm)

    vm.run('c:PERPMARKSTAMP', [vm.entities[0], "1", 6.0, None, "2", 9.0, esc])
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert vm.sysvars['CLAYER'] == '0' and vm.sysvars['OSMODE'] == 33
    assert vm.undo_groups == 0
    assert ruler_scratch(vm) == [], "Esc left the ruler standing"
    assert not any('error' in s for s in vm.printed), vm.printed
    assert len(stamps(vm)) == 1, "the first stamp is there, the second never was"
    vm.handle_errors = False
    vm.run('c:PERPMARK', [vm.entities[0], "1", 12.0, None, "No"])
    assert len(stamps(vm)) == 1, "the plain run after the Esc must not stamp"
    print("ok  esc         -> PERPMARK's handler, settings back, hook not left set")


def test_one_undo_group_wraps_the_whole_run():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 80)
    run(vm, [vm.entities[0], "1", 12.0, None, "2", 6.0, [30.0, 30.0, 0.0],
             None, "Yes", "1", "2", STY])
    undo = [c[1] for c in vm.commands if c and c[0] == '_.UNDO']
    assert undo == ['_Begin', '_End'], undo
    assert vm.undo_groups == 0
    print("ok  undo        -> one group, PERPMARK's, round the stamps too")


def test_without_perpmark_it_says_so_and_stops():
    vm = newvm(with_perpmark=False)
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [])
    assert said(vm, "PERPMARK v1.13 or later is not loaded"), vm.printed
    assert vm.prompts == [], vm.prompts
    assert stamps(vm) == [] and live(vm, 'CIRCLE') == []
    print("ok  no perpmark -> says which version it needs, asks nothing")


def test_perpmark_alone_is_unchanged():
    """The hook is PERPMARK's seam, and a plain PERPMARK must not feel
    it: the same run, unhooked, asks no stamp question and draws no
    MTEXT."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 80)
    vm.run('c:PERPMARK', [vm.entities[0], "1", 12.0, "2", 6.0, None, "No"])
    assert stamp_prompts(vm) == [] and live(vm, 'MTEXT') == []
    assert len(live(vm, 'CIRCLE')) == 2
    print("ok  plain       -> PERPMARK on its own is PERPMARK")


def test_the_version_reporter():
    vm = newvm()
    vm.run('c:PERPMARKSTAMPVER', [])
    assert said(vm, "PERPMARKSTAMP v"), vm.printed
    print("ok  version     -> PERPMARKSTAMPVER prints it")


if __name__ == '__main__':
    test_enter_stamps_at_the_end_of_the_mark()
    test_the_prompt_names_the_distance_and_the_point()
    test_a_click_stamps_there()
    test_skip_stamps_nothing_and_keeps_the_mark()
    test_back_at_the_stamp_prompt_takes_the_mark_away()
    test_undo_is_back_at_the_stamp_prompt()
    test_back_at_the_next_point_takes_the_stamp_with_the_mark()
    test_a_re_mark_replaces_the_stamp()
    test_the_join_leaves_the_stamps_standing()
    test_no_keeps_marks_and_stamps_together()
    test_the_spelling_follows_what_was_typed()
    test_a_stamp_carries_the_shop_mtext_properties()
    test_a_missing_style_is_made_and_reported()
    test_the_knobs_reach_the_output()
    test_the_ruler_is_down_while_the_stamp_prompt_is_up()
    test_the_hook_is_consumed_by_the_run()
    test_esc_at_the_stamp_prompt_is_perpmarks_esc()
    test_one_undo_group_wraps_the_whole_run()
    test_without_perpmark_it_says_so_and_stops()
    test_perpmark_alone_is_unchanged()
    test_the_version_reporter()
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print(f"all PERPMARKSTAMP tests passed  [{tier}]")
