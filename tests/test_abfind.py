"""Runtime tests: load the real ABFIND.lsp into the AutoLISP VM and drive
c:ABFIND / c:ABMOVE with scripted typing.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (distance ...) has to die.

Script values answer the interactive calls in order: the "_X" point
sweep (ssget), a click per unnamed stake (getpoint), then a point
number (getstring), and - under ABMOVE - which suggestion (getkword)
and where the note goes (getpoint, None = the Auto default).  ABFIND
loops, so None at its point-number prompt is the Enter that ends it;
ABMOVE settles one point and returns on its own, so its scripts have
nothing after the note.

Run: python3 tests/test_abfind.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_abfind.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot, Sym, BUILTINS, NIL  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'abfind', 'ABFIND.lsp')


# ---- builtins the shared VM does not carry yet ------------------------
# entmakex: entmake that returns the new entity name; tblobjname: the
# entity name of a table record; distof: string -> float.  ensure-layer
# needs the first two, the point-number reader the third.

def _alist_dict(alist):
    d = {}
    for p in alist:
        if isinstance(p, Dot):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


def _entmakex(vm, a):
    alist = a[0]
    d = _alist_dict(alist)
    if d.get(0) in ('LAYER', 'LTYPE'):
        vm.tables[d[0]].add(d[2])
        rec = Ent()
        vm.entdata[rec] = list(alist)
        vm.layer_records[d[2].upper()] = rec
        return rec
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = list(alist)
    return e


def _tblobjname(vm, a):
    return vm.layer_records.get(a[1].upper(), NIL)


def _distof(vm, a):
    try:
        return float(a[0])
    except (TypeError, ValueError):
        return NIL


BUILTINS[Sym('entmakex')] = _entmakex
BUILTINS[Sym('tblobjname')] = _tblobjname
BUILTINS[Sym('distof')] = _distof


# ---- the drawing ------------------------------------------------------
# A and B stakes 20' apart on the x axis; Pt.17 tied 21'-1" off A and
# 18'-6" off B, north of them - the shape of a real survey.

A = (0.0, 0.0)
B = (240.0, 0.0)
PA = 253.0                       # 21'-1"
PB = 222.0                       # 18'-6"


def cross(a, b, near_up=True):
    """Where circle (A a) meets circle (B b), on the north side."""
    d = B[0] - A[0]
    x = (d * d + a * a - b * b) / (2.0 * d)
    y = math.sqrt(a * a - x * x)
    return (x, y if near_up else -y)


P17 = cross(PA, PB)


def add_layer(vm, name, color=7):
    """A layer the drawing already has - table entry AND the record
    tblobjname hands back, which is what ensure-layer reads."""
    vm.tables['LAYER'].add(name)
    rec = Ent()
    vm.entdata[rec] = [Dot(0, 'LAYER'), Dot(2, name), Dot(70, 0),
                       Dot(62, color)]
    vm.layer_records[name.upper()] = rec
    return rec


def newvm(styles=("CROSS DIMENSIONS",), block=True):
    vm = VM()
    vm.layer_records = getattr(vm, 'layer_records', {})
    vm.load(LSP)
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    vm.tables['BLOCK'] = {'ab_pt'} if block else set()
    add_layer(vm, 'POINTS', 2)
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


def survey(vm, stakes=('A', 'B')):
    """The three points every test starts from; returns the sweep list."""
    out = []
    if 'A' in stakes:
        out.append(ab_pt(vm, A[0], A[1], 'A'))
    if 'B' in stakes:
        out.append(ab_pt(vm, B[0], B[1], 'B'))
    out.append(ab_pt(vm, P17[0], P17[1], 17))
    return out


def run(vm, cmd, script, label):
    try:
        vm.run(cmd, list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


# ---- reading the drawing back -----------------------------------------

def live(vm, etype, layer=None):
    """Every live entity of a type (and layer), as {code: value}, in
    creation order, paired with its ename."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = _alist_dict(vm.entdata[e])
        if d.get(0) != etype:
            continue
        if layer is not None and str(d.get(8, '')).upper() != layer.upper():
            continue
        out.append((e, d))
    return out


def ever(vm, etype, layer=None):
    """Every entity of a type ever made, erased ones included."""
    out = []
    for e in vm.entities:
        d = _alist_dict(vm.entdata[e])
        if d.get(0) != etype:
            continue
        if layer is not None and str(d.get(8, '')).upper() != layer.upper():
            continue
        out.append(d)
    return out


def dims(vm):
    return [d for _, d in live(vm, 'DIMENSION')]


def texts(vm, layer=None):
    return [d.get(1) for _, d in live(vm, 'TEXT', layer)]


def pt3(v):
    return (round(v[0], 6), round(v[1], 6))


def near(a, b, eps=1e-6):
    return abs(a - b) < eps


# ---- ABFIND -----------------------------------------------------------

def test_abfind_pair():
    """One number, two dims: A to the point and B to the point."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', [pts, '17', 'No', None], 'abfind pair')
    ds = dims(vm)
    assert len(ds) == 2, ds
    # first from A, second from B; both end on the point
    assert pt3(ds[0][13]) == pt3(A), ds[0]
    assert pt3(ds[0][14]) == pt3(P17), ds[0]
    assert pt3(ds[1][13]) == pt3(B), ds[1]
    assert pt3(ds[1][14]) == pt3(P17), ds[1]
    # the dimension line sits right inbetween -- nothing is picked
    assert pt3(ds[0][10]) == pt3(((A[0] + P17[0]) / 2, (A[1] + P17[1]) / 2))
    for d in ds:
        assert d[8] == 'DIMENSION', d
        assert d[3] == 'CROSS DIMENSIONS', d
        assert 62 not in d and 6 not in d and 370 not in d, d
    # and the drawing is put back the way it was
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD'
    assert vm.sysvars['CLAYER'] == '0'
    print("ok  ABFIND Pt.17 -> A and B ties, CROSS DIMENSIONS on"
          " DIMENSION, state restored")


def test_abfind_spellings_and_repeat():
    """'Pt.17' names the same point, and the loop keeps going."""
    vm = newvm()
    pts = survey(vm)
    ab_pt(vm, 100.0, 300.0, 18)
    pts = [e for e in vm.entities
           if _alist_dict(vm.entdata[e]).get(0) == 'INSERT']
    run(vm, 'c:ABFIND', [pts, 'Pt.17', 'No', '#018', 'No', None],
        'spellings')
    assert len(dims(vm)) == 4, dims(vm)
    print("ok  ABFIND 'Pt.17' / '#018' resolve, and the loop repeats")


def test_abfind_back():
    """Back un-draws the whole of the last round."""
    vm = newvm()
    pts = survey(vm)
    ab_pt(vm, 100.0, 300.0, 18)
    pts = [e for e in vm.entities
           if _alist_dict(vm.entdata[e]).get(0) == 'INSERT']
    run(vm, 'c:ABFIND', [pts, '17', 'No', '18', 'No', 'b', None], 'back')
    ds = dims(vm)
    assert len(ds) == 2, ds
    assert pt3(ds[0][14]) == pt3(P17), ds[0]     # Pt.18's pair is gone
    print("ok  ABFIND Back un-draws the last pair")


def test_abfind_unknown_number():
    """A typo draws nothing and re-asks."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', [pts, '99', '17', 'No', None], 'typo')
    assert len(dims(vm)) == 2, dims(vm)
    print("ok  ABFIND an unknown number draws nothing and re-asks")


def test_abfind_stake_by_click():
    """A drawing that does not name B asks for it, and snaps the click."""
    vm = newvm()
    pts = survey(vm, stakes=('A',))
    run(vm, 'c:ABFIND',
        [pts, (B[0] + 3.0, B[1] + 2.0, 0.0), '17', 'No', None],
        'stake click')
    ds = dims(vm)
    assert len(ds) == 2, ds
    # snapped to nothing (no B point exists) -> the click itself is used
    assert pt3(ds[1][13]) == pt3((B[0] + 3.0, B[1] + 2.0)), ds[1]
    print("ok  ABFIND an unnamed stake is clicked instead")


def test_abfind_stake_snaps_to_point():
    """A click near a survey point takes that point, not the click."""
    vm = newvm()
    e = ab_pt(vm, A[0], A[1], 'A')
    b = ab_pt(vm, B[0], B[1], 'BEE')          # named, but not "B"
    p = ab_pt(vm, P17[0], P17[1], 17)
    run(vm, 'c:ABFIND', [[e, b, p], (B[0] + 3.0, B[1] + 2.0, 0.0), '17',
                         'No', None], 'stake snap')
    ds = dims(vm)
    assert pt3(ds[1][13]) == pt3(B), ds[1]
    print("ok  ABFIND a stake click within the snap takes the point")


def test_abfind_no_style():
    """A drawing without the style still gets its dims, and is told."""
    vm = newvm(styles=())
    pts = survey(vm)
    run(vm, 'c:ABFIND', [pts, '17', 'No', None], 'no style')
    ds = dims(vm)
    assert len(ds) == 2 and ds[0][3] == 'STANDARD', ds
    assert ds[0][8] == 'DIMENSION', ds
    print("ok  ABFIND with no CROSS DIMENSIONS style draws in the current one")


def test_abfind_offers_the_move():
    """ABFIND asks, once the ties are drawn, and defaults to leaving it."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', [pts, '17', None, None], 'offer')   # Enter = No
    asked = [q for q, _ in vm.prompts if 'different reading' in q]
    assert asked == ['\n  Move Pt.17 to a different reading?'
                     ' [Yes/No/Back] <No>: '], asked
    assert len(dims(vm)) == 2, dims(vm)          # Enter left it alone
    assert texts(vm, 'FGStep') == [], texts(vm, 'FGStep')
    print("ok  ABFIND offers the move after the ties, defaulting to No")


def test_abfind_moves_and_carries_on():
    """Yes runs ABMOVE's flow, then ABFIND asks for the next point."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND',
        [pts, '17', 'Yes', 'R1B', None,      # moved to Pt.17m
              '17m', 'No',                   # ... and tied again, same run
              None],
        'move and carry on')
    assert texts(vm, 'FGStep') == ['Moved Pt.17 B from 18\'-6" to 18\'-5"']
    ins = live(vm, 'INSERT', 'POINTS')
    assert len(ins) == 4, ins
    ds = dims(vm)
    assert len(ds) == 4, ds        # the moved point's pair, then 17m's own
    newpt = (ins[-1][1][10][0], ins[-1][1][10][1])
    for d in ds:
        assert pt3(d[14]) == pt3(newpt), d
    assert len([q for q, _ in vm.prompts if 'Point number' in q]) == 3
    print("ok  ABFIND Yes moves the point and then asks for the next one")


def test_abfind_back_at_the_move_question():
    """Back there un-draws that point's ties and re-asks the number."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', [pts, '17', 'Back', None], 'back at the offer')
    assert dims(vm) == [], dims(vm)
    print("ok  ABFIND Back at the move question un-draws the ties")


def test_abfind_back_from_the_suggestions():
    """Back there re-asks the move question, not the point number."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', [pts, '17', 'Yes', 'Back', 'No', None], 'back to ask')
    assert len([q for q, _ in vm.prompts if 'different reading' in q]) == 2
    assert len([q for q, _ in vm.prompts if 'Point number' in q]) == 2
    assert len(dims(vm)) == 2, dims(vm)          # the ties were never lost
    assert sug_positions(vm) == []
    print("ok  ABFIND Back at the suggestions re-asks the move question")


def test_abfind_back_undoes_a_move():
    """Back at the point number puts a whole moved round back."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', [pts, '17', 'Yes', 'R1B', None, 'b', None],
        'undo the move')
    assert texts(vm, 'FGStep') == []
    assert live(vm, 'CIRCLE', 'FGStep') == []
    assert len(live(vm, 'INSERT', 'POINTS')) == 3        # 17m is gone
    ds = dims(vm)
    assert len(ds) == 2, ds
    assert pt3(ds[0][14]) == pt3(P17) and pt3(ds[1][14]) == pt3(P17), ds
    print("ok  ABFIND Back undoes a moved round, ties and all")


def test_abmove_does_not_ask():
    """ABMOVE was typed to move a point, so it goes straight there."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'None'], 'no question')
    assert [q for q, _ in vm.prompts if 'different reading' in q] == []
    print("ok  ABMOVE skips the question and offers the readings at once")


# ---- the misreadings --------------------------------------------------

def test_reading():
    vm = newvm()
    assert vm.loads('(abf:reading 253.0)') == [21, 1]
    assert vm.loads('(abf:reading 253.0625)') == [21, 1]
    assert vm.loads('(abf:reading 251.97)') == [21, 0]      # rounds up
    assert vm.loads('(abf:reading 259.99)') == [21, 8]
    print("ok  a distance reads as feet and whole inches, rounded at 1/16")


def test_digit_swaps():
    vm = newvm()
    assert vm.loads('(abf:digit-swaps 1)') == [7, 4]
    assert vm.loads('(abf:digit-swaps 18)') == [78, 48, 13, 16]
    assert vm.loads('(abf:digit-flips 21)') == [12]
    print("ok  look-alike digits and transpositions")


def test_deltas():
    """The foot sweep, 10 each way, with the look-alikes woven in."""
    vm = newvm()
    # 21'-1": the sweep, plus 21'-4" (1 read as 4), 21'-7" (1 as 7) and
    # 21'-11" (the leading 1).  21'->27' and 21'->12' are look-alikes
    # too, but they land on whole feet the sweep already carries.
    a = vm.loads('(abf:deltas 253.0)')
    assert a[:5] == [3.0, 6.0, 10.0, 12.0, -12.0], a
    assert len(a) == 23, a
    # 18'-6": the sweep, plus 18'-5" (6 read as 5) and 18'-8" (6 as 8)
    b = vm.loads('(abf:deltas 222.0)')
    assert b[:4] == [-1.0, 2.0, 12.0, -12.0], b
    assert len(b) == 22, b
    for d in (a, b):
        # ten feet each way, every one of them
        for k in range(1, 11):
            assert 12.0 * k in d and -12.0 * k in d, (k, d)
        # sorted by how big the miss is, nothing past the cap, and no
        # reading that would come out at or below zero
        assert [abs(v) for v in d] == sorted(abs(v) for v in d), d
        assert max(abs(v) for v in d) <= 120.0, d
    assert all(222.0 + v > 0 for v in b), b
    # a short tape cannot go a foot below zero: only the way up
    assert vm.loads('(abf:deltas 6.0)')[:3] == [-1.0, 2.0, 12.0]
    assert -12.0 not in vm.loads('(abf:deltas 6.0)')
    print("ok  the readings tried: 10 feet each way, plus the look-alikes")


def test_deltas_cap_shortens_both():
    """abf:*max-shift* bounds the sweep and the look-alikes alike."""
    vm = newvm()
    vm.loads('(setq abf:*max-shift* 24.0)')
    assert vm.loads('(abf:deltas 253.0)') == [3.0, 6.0, 10.0, 12.0, -12.0,
                                              24.0, -24.0]
    # with a 2-foot sweep the whole-feet look-alikes are no longer
    # covered by it, so they come back in their own right: 21'->24',
    # 21'->27' and the transposed 21'->12'
    vm.loads('(setq abf:*max-shift* 120.0)')
    vm.loads('(setq abf:*foot-steps* 2)')
    assert vm.loads('(abf:deltas 253.0)') == [3.0, 6.0, 10.0, 12.0, -12.0,
                                              24.0, -24.0, 36.0, 72.0,
                                              -108.0]
    print("ok  the shift cap and the step count each shorten the list")


def test_circint():
    """The crossing nearer the point is the one taken - no flipping."""
    vm = newvm()
    got = vm.loads("(abf:circint '(0.0 0.0) 253.0 '(240.0 0.0) 222.0 "
                   "'(150.0 200.0))")
    assert pt3(got) == pt3(P17), got
    below = vm.loads("(abf:circint '(0.0 0.0) 253.0 '(240.0 0.0) 222.0 "
                     "'(150.0 -200.0))")
    assert pt3(below) == pt3((P17[0], -P17[1])), below
    # circles that never reach each other
    assert vm.loads("(abf:circint '(0.0 0.0) 10.0 '(240.0 0.0) 10.0 "
                    "'(0.0 0.0))") is NIL
    print("ok  the two circles cross on the side the point is already on")


# ---- ABMOVE -----------------------------------------------------------

def sug_positions(vm):
    """Where the suggestion markers are, in list order (their circles)."""
    return [pt3(d[10]) for _, d in live(vm, 'CIRCLE', 'POINTS')]


def test_abmove_suggestions_drawn():
    """Every reading is offered, on the POINTS layer, numbered."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'None'], 'suggestions')
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    assert len(got) == 45, len(got)          # 23 B-held + 22 A-held
    # ... and none of them left in the drawing once the round is over
    assert sug_positions(vm) == [], sug_positions(vm)
    assert texts(vm, 'POINTS') == [], texts(vm, 'POINTS')
    assert len([e for e, _ in live(vm, 'POINT')]) == 0
    # None keeps the two dims: ABMOVE has then done exactly ABFIND's job
    assert len(dims(vm)) == 2, dims(vm)
    print("ok  ABMOVE draws its suggestions on POINTS and sweeps them again")


def test_abmove_two_groups():
    """A held first, then B - and each group holds its own tape exactly."""
    vm = newvm()
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    held = [c[1] for c in got]
    assert held == ['B'] * 23 + ['A'] * 22, held        # grouped, not mixed
    for c in got:
        p = (c[5][0], c[5][1])
        if c[1] == 'A':                                 # A held exactly...
            assert near(math.dist(A, p), PA), c
            assert near(math.dist(B, p), c[4]), c       # ...B is the reading
        else:
            assert near(math.dist(B, p), PB), c
            assert near(math.dist(A, p), c[4]), c
    for g in (got[:23], got[23:]):
        assert [round(c[0], 6) for c in g] == sorted(round(c[0], 6)
                                                    for c in g), g
    print("ok  ABMOVE offers two groups, each holding its own tape exactly")


def test_abmove_reaches_ten_feet_each_way():
    """The whole 1-foot sweep is there, up and down, for both stakes."""
    vm = newvm()
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    for held, was in (('A', PB), ('B', PA)):
        reach = {round(c[4] - was, 6) for c in got if c[1] == held}
        for k in range(1, 11):
            assert 12.0 * k in reach and -12.0 * k in reach, (held, k, reach)
    print("ok  ABMOVE sweeps 10 feet up and 10 down, per held stake")


def test_abmove_tags():
    """Every suggestion is named for the tape it moves and by how far."""
    vm = newvm()
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    tags = [c[6] for c in got]
    assert len(set(tags)) == len(tags), tags          # a tag names one place
    for c in got:
        assert c[6].endswith(c[2]), c                 # ... the tape it MOVES
    # the sweep is named by the feet it moved, up and down
    for letter, was in (('A', PA), ('B', PB)):
        step = {c[6]: round((c[4] - was) / 12.0, 6)
                for c in got if c[2] == letter and not c[6].startswith('R')}
        assert step == {f'{k}{letter}': float(k)
                        for k in list(range(1, 11)) + list(range(-10, 0))}, step
    # a reading that is not a whole foot is R1, R2 ... in the same order
    assert [c[6] for c in got if c[6].startswith('R')] == \
        ['R1A', 'R2A', 'R3A', 'R1B', 'R2B'], tags
    # R1A is 21'-1" read as 21'-4", the nearest look-alike of A
    r1a = [c for c in got if c[6] == 'R1A'][0]
    assert near(r1a[4], PA + 3.0), r1a
    print("ok  tags name the moved tape: 1A -1A 2A ... and R1A for a"
          " look-alike")


def test_abmove_tag_order_is_stable():
    """Up before down at the same miss - never 2B before -2B one run
    and after it the next."""
    vm = newvm()
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    for letter in ('A', 'B'):
        sweep = [c[6] for c in got
                 if c[2] == letter and not c[6].startswith('R')]
        assert sweep == [f'{s}{k}{letter}'
                         for k in range(1, 11) for s in ('', '-')], sweep
    print("ok  the sweep always reads 1, -1, 2, -2 ... in both groups")


def test_abmove_markers_are_yellow():
    """The suggestions are yellow, so they never read as real points."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'None'], 'yellow')
    marks = (ever(vm, 'POINT', 'POINTS') + ever(vm, 'CIRCLE', 'POINTS')
             + ever(vm, 'TEXT', 'POINTS'))
    assert len(marks) == 45 * 3, len(marks)      # a point, a ring, a tag
    assert all(m.get(62) == 2 for m in marks), \
        [m for m in marks if m.get(62) != 2][:2]
    assert sorted(m[1] for m in ever(vm, 'TEXT', 'POINTS'))[:3] == \
        ['-10A', '-10B', '-1A'], ever(vm, 'TEXT', 'POINTS')[:3]
    print("ok  ABMOVE draws its suggestions yellow, tag and all")


def test_abmove_locus_lines():
    """A dashed grey line through each group, on the points layer."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'None'], 'locus')
    arcs = ever(vm, 'ARC', 'POINTS')
    assert len(arcs) == 2, arcs
    # the readings that move A hold B, so their line is B's own reading
    # swung round B; the ones that move B are A's swung round A
    movea, moveb = arcs
    assert pt3(movea[10]) == pt3(B) and near(movea[40], PB), movea
    assert pt3(moveb[10]) == pt3(A) and near(moveb[40], PA), moveb
    for d in arcs:
        assert d.get(8) == 'POINTS', d
        assert d.get(62) == 8, d                   # grey
        assert d.get(6) == 'DASHED', d             # dashed
    assert 'DASHED' in {x.upper() for x in vm.tables['LTYPE']}
    assert live(vm, 'ARC') == []                   # swept with the markers
    print("ok  ABMOVE draws a dashed grey line through each group")


def test_abmove_locus_covers_its_group():
    """The line really does go through all of them - and through the
    point as it is drawn now, which is where the two cross."""
    vm = newvm()
    pts = survey(vm)
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    run(vm, 'c:ABMOVE', [pts, '17', 'None'], 'locus span')
    arcs = ever(vm, 'ARC', 'POINTS')
    for arc, held, ctr, rad in ((arcs[0], 'B', B, PB), (arcs[1], 'A', A, PA)):
        start = arc[50]
        span = (arc[51] - start) % (2 * math.pi)
        for c in got:
            if c[1] != held:
                continue
            p = (c[5][0], c[5][1])
            assert near(math.dist(ctr, p), rad), (c[6], math.dist(ctr, p))
            off = (math.atan2(p[1] - ctr[1], p[0] - ctr[0]) - start) \
                % (2 * math.pi)
            assert off <= span + 1e-9, (c[6], off, span)
        off = (math.atan2(P17[1] - ctr[1], P17[0] - ctr[0]) - start) \
            % (2 * math.pi)
        assert off <= span + 1e-9, (held, off, span)
    print("ok  each line spans its whole group and the point itself")


def test_abmove_locus_linetype_is_tunable():
    """A drawing with its own dashed linetype can be pointed at it."""
    vm = newvm()
    pts = survey(vm)
    vm.loads('(setq abf:*locus-ltype* "PHANTOM2")')
    vm.loads('(setq abf:*locus-color* 9)')
    run(vm, 'c:ABMOVE', [pts, '17', 'None'], 'ltype')
    for d in ever(vm, 'ARC', 'POINTS'):
        assert d.get(6) == 'PHANTOM2' and d.get(62) == 9, d
    assert 'PHANTOM2' in {x.upper() for x in vm.tables['LTYPE']}
    print("ok  the guide line's linetype and colour are tunable")


def test_abmove_the_marks_it_keeps_are_bylayer():
    """What ABMOVE leaves behind is the drawing's own colour, not yellow."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'R1B', None], 'bylayer')
    ring = live(vm, 'CIRCLE', 'FGStep')[0][1]
    note = live(vm, 'TEXT', 'FGStep')[0][1]
    moved = live(vm, 'INSERT', 'POINTS')[-1][1]
    for d in (ring, note, moved):
        assert 62 not in d, d
    print("ok  the ring, the note and the moved point stay ByLayer")


def test_abmove_prompt_stays_short():
    """Forty-five tags would swamp the command line, so the bracket
    shows only the words that are not already in the table."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'None'], 'prompt')
    asked = [q for q, _ in vm.prompts if 'type a tag' in q]
    assert len(asked) == 1, asked
    assert [q for q, _ in vm.prompts if 'Point number' in q] == \
        ['\nPoint number (Enter to cancel): '], vm.prompts
    assert asked[0].endswith('[Pick/None/Back] <None>: '), asked[0]
    assert '1A' not in asked[0], asked[0]
    print("ok  ABMOVE's choice prompt shows Pick/None/Back, not 45 tags")


def test_abmove_moves_the_point():
    """Pick one and the point moves, is renamed, ringed and noted."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'R1B', None], 'move')

    # 1) a new point numbered 17m, on POINTS, where the suggestion was
    ins = [(e, d) for e, d in live(vm, 'INSERT', 'POINTS')]
    assert len(ins) == 4, ins                       # A, B, 17 and now 17m
    moved = ins[-1][1]
    newpt = (moved[10][0], moved[10][1])
    assert near(math.dist(A, newpt), PA), math.dist(A, newpt)
    assert near(math.dist(B, newpt), PB - 1.0), math.dist(B, newpt)
    nums = [d.get(1) for _, d in live(vm, 'ATTRIB')]
    assert nums[-1] == '17m', nums

    # 2) the original point is ringed, 5" radius, on FGStep
    rings = live(vm, 'CIRCLE', 'FGStep')
    assert len(rings) == 1, rings
    assert rings[0][1][40] == 5.0, rings[0][1]
    assert pt3(rings[0][1][10]) == pt3(P17), rings[0][1]

    # 3) the note says what moved and between which two readings
    assert texts(vm, 'FGStep') == ['Moved Pt.17 B from 18\'-6" to 18\'-5"'], \
        texts(vm, 'FGStep')

    # 4) the ties now measure where the point is, not where it was
    ds = dims(vm)
    assert len(ds) == 2, ds
    assert pt3(ds[0][13]) == pt3(A) and pt3(ds[0][14]) == pt3(newpt), ds[0]
    assert pt3(ds[1][13]) == pt3(B) and pt3(ds[1][14]) == pt3(newpt), ds[1]

    # 5) nothing of the suggestion scaffolding is left behind
    assert sug_positions(vm) == []
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD'
    assert vm.sysvars['CLAYER'] == '0'
    print("ok  ABMOVE Pt.17 -> Pt.17m: A held, B 18'-6\" -> 18'-5\","
          " ringed and noted")


def test_abmove_note_placed_by_hand():
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'R2B', (900.0, 900.0, 0.0)], 'note')
    note = [(e, d) for e, d in live(vm, 'TEXT', 'FGStep')]
    assert len(note) == 1 and pt3(note[0][1][10]) == (900.0, 900.0), note
    assert note[0][1][40] == 6.0, note[0][1]
    # #2 is the +2" misreading of B: 18'-6" -> 18'-8"
    assert note[0][1][1] == 'Moved Pt.17 B from 18\'-6" to 18\'-8"', note
    print("ok  ABMOVE the note goes where it is placed")


def test_abmove_pick_on_screen():
    """Clicking a suggestion picks it, the same as typing its number."""
    vm = newvm()
    pts = survey(vm)
    want = vm.loads("(nth 5 (car (abf:candidates '(0.0 0.0) '(240.0 0.0) "
                    f"'({P17[0]} {P17[1]} 0.0))))")
    run(vm, 'c:ABMOVE',
        [pts, '17', 'Pick', (want[0] + 2.0, want[1] - 1.0, 0.0), None],
        'pick')
    ins = live(vm, 'INSERT', 'POINTS')
    assert pt3(ins[-1][1][10]) == pt3(want), ins[-1][1]
    assert texts(vm, 'FGStep') == ['Moved Pt.17 A from 21\'-1" to 21\'-4"']
    print("ok  ABMOVE a click on a suggestion picks it")


def test_abmove_pick_miss():
    """A click nowhere near a suggestion is refused, not guessed at."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE',
        [pts, '17', 'Pick', (9000.0, 9000.0, 0.0), 'None'], 'pick miss')
    assert texts(vm, 'FGStep') == [], texts(vm, 'FGStep')
    assert len(dims(vm)) == 2, dims(vm)
    print("ok  ABMOVE a click that hits nothing re-asks")


def test_abmove_back_from_the_choice():
    """Back at the choice takes the dims away and re-asks the number."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'Back', '17', 'None'], 'back 2')
    assert len(dims(vm)) == 2, dims(vm)          # one pair, not two
    assert sug_positions(vm) == []
    print("ok  ABMOVE Back at the choice re-asks the point number")


def test_abmove_back_from_the_note():
    """Back at the note re-asks the choice, suggestions still up."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'R1B', 'Back', 'None'], 'back 3')
    assert texts(vm, 'FGStep') == []
    assert len(dims(vm)) == 2, dims(vm)
    assert sug_positions(vm) == []
    print("ok  ABMOVE Back at the note re-asks which suggestion")


def test_abmove_ends_after_one_point():
    """One point and the command is over - it never asks for another."""
    vm = newvm()
    pts = survey(vm)
    ab_pt(vm, 100.0, 300.0, 18)
    pts = [e for e in vm.entities
           if _alist_dict(vm.entdata[e]).get(0) == 'INSERT']
    # the script has no answer left for a second round: a rinse-repeat
    # ABMOVE would run off the end of it and the VM would say so
    run(vm, 'c:ABMOVE', [pts, '17', 'R1B', None], 'one shot')
    assert len([q for q, _ in vm.prompts if 'Point number' in q]) == 1
    assert len(dims(vm)) == 2, dims(vm)
    assert len(texts(vm, 'FGStep')) == 1, texts(vm, 'FGStep')
    print("ok  ABMOVE settles one point and ends")


def test_abmove_cancels_on_enter():
    """Enter at the point number is 'never mind', not a bad answer."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, None], 'cancel')
    assert dims(vm) == [], dims(vm)
    assert sug_positions(vm) == []
    assert vm.sysvars['CLAYER'] == '0'
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD'
    print("ok  ABMOVE Enter at the point number cancels cleanly")


def test_abmove_without_the_block():
    """No ab_pt block in the drawing: a POINT and a label instead."""
    vm = newvm(block=False)
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'R1B', None], 'no block')
    pointed = live(vm, 'POINT', 'POINTS')
    assert len(pointed) == 1, pointed
    assert texts(vm, 'POINTS') == ['17m'], texts(vm, 'POINTS')
    assert near(math.dist(A, (pointed[0][1][10][0], pointed[0][1][10][1])),
                PA)
    print("ok  ABMOVE with no point block makes a POINT and labels it 17m")


def test_abfind_a_stake_is_not_a_point():
    """Typing a stake's own name is refused, not dimensioned to itself."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', [pts, 'A', '17', 'No', None], 'stake as point')
    assert len(dims(vm)) == 2, dims(vm)
    print("ok  ABFIND naming a stake ties nothing - it is what ties are from")


def test_moved_point_is_a_point_afterwards():
    """Pt.17m is a real survey point: the next run can tie it."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [pts, '17', 'R1B', None], 'move')
    moved = live(vm, 'INSERT', 'POINTS')[-1][0]
    # a fresh run re-reads the drawing and finds it by its new number
    run(vm, 'c:ABFIND', [pts + [moved], '17m', 'No', None],
        'tie the moved point')
    ds = dims(vm)
    assert len(ds) == 4, ds                  # the move's pair, then 17m's
    assert pt3(ds[2][14]) == pt3(ds[0][14]), ds
    print("ok  Pt.17m can be tied by the next run, like any other point")


def test_abmove_no_suggestions():
    """Nothing believable to offer leaves the point alone."""
    vm = newvm()
    pts = survey(vm)
    vm.loads('(setq abf:*max-shift* 0.5)')
    run(vm, 'c:ABMOVE', [pts, '17'], 'no suggestions')
    assert len(dims(vm)) == 2, dims(vm)
    assert texts(vm, 'FGStep') == []
    print("ok  ABMOVE with nothing to offer just leaves the two dims")


def test_abmove_cap():
    """abf:*max-sugg* caps each group, so both answers survive it."""
    vm = newvm()
    survey(vm)
    vm.loads('(setq abf:*max-sugg* 4)')
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    assert len(got) == 8, got
    assert [c[1] for c in got] == ['B'] * 4 + ['A'] * 4, got
    assert [round(c[0], 3) for c in got[:4]] == sorted(round(c[0], 3)
                                                      for c in got[:4]), got
    print("ok  the suggestion cap applies per held stake, nearest miss first")


def test_no_points_at_all():
    vm = newvm()
    run(vm, 'c:ABFIND', [None], 'empty drawing')
    assert dims(vm) == []
    print("ok  an empty drawing is reported, not crashed on")


TESTS = [v for k, v in sorted(globals().items()) if k.startswith('test_')]

if __name__ == '__main__':
    for t in TESTS:
        t()
    print(f"\n{len(TESTS)} ABFIND/ABMOVE test(s) passed.")
