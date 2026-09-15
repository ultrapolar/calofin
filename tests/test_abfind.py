"""Runtime tests: load the real ABFIND.lsp into the AutoLISP VM and drive
c:ABFIND / c:ABMOVE with scripted typing.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (distance ...) has to die.

Script values answer the interactive calls in order: a click per
unnamed stake (getpoint), then a point number (getstring), and - under
ABMOVE - which suggestion (getpoint under initget 128: a click on a
marker or its tag, or a typed tag) and where the note goes (getpoint,
None = the Auto default).  The "_X" point sweep takes no
scripted answer: ssget "_X" reads the drawing and never prompts, so
the points the scenario builds are what it finds.  ABFIND loops, so
None at its point-number prompt is the Enter that ends it; ABMOVE
settles one point and returns on its own, so its scripts have nothing
after the note.

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


def newvm(styles=("CROSS DIMENSIONS",), block=True, points=True):
    vm = VM()
    vm.layer_records = getattr(vm, 'layer_records', {})
    vm.load(LSP)
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    vm.tables['BLOCK'] = {'ab_pt'} if block else set()
    if points:
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


def rich_pt(vm, x, y, number, layer='SURVEY-PTS'):
    """A survey point with a drawing's own properties on it: its own
    layer, colour, linetype, lineweight, scale and rotation, and a
    second attribute beside the number.  What a moved point has to
    carry over, and what building one from ABFIND's defaults lost."""
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'INSERT'), Dot(8, layer), Dot(2, 'ab_pt'),
                     Dot(62, 3), Dot(6, 'HIDDEN'), Dot(370, 50),
                     Dot(66, 1), [10, float(x), float(y), 0.0],
                     Dot(41, 2.0), Dot(42, 2.0), Dot(43, 2.0),
                     Dot(50, 0.5)]
    for tag, val, off, hgt in (('number', str(number), NUM_OFF, 4.0),
                               ('elev', '104.25', ELEV_OFF, 3.0)):
        att = Ent()
        vm.entities.append(att)
        vm.entdata[att] = [Dot(0, 'ATTRIB'), Dot(8, layer), Dot(62, 3),
                           Dot(2, tag), Dot(1, val), Dot(40, hgt),
                           Dot(7, 'ROMANS'), Dot(50, 0.5),
                           [10, float(x) + off[0], float(y) + off[1], 0.0],
                           [11, float(x) + off[0], float(y) + off[1], 0.0]]
    return e


NUM_OFF = (0.87, -3.53)          # where each attribute sits relative
ELEV_OFF = (0.87, -9.0)          # to the point it belongs to


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
    run(vm, 'c:ABFIND', ['17', 'No', None], 'abfind pair')
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
    run(vm, 'c:ABFIND', ['Pt.17', 'No', '#018', 'No', None],
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
    run(vm, 'c:ABFIND', ['17', 'No', '18', 'No', 'b', None], 'back')
    ds = dims(vm)
    assert len(ds) == 2, ds
    assert pt3(ds[0][14]) == pt3(P17), ds[0]     # Pt.18's pair is gone
    print("ok  ABFIND Back un-draws the last pair")


def test_abfind_unknown_number():
    """A typo draws nothing and re-asks -- once the offer to create the
    point it names has been turned down.  No is the Enter answer there
    for exactly this reason: a typo must not plot a point."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', ['99', 'No', '17', 'No', None], 'typo')
    assert len(dims(vm)) == 2, dims(vm)
    assert len(live(vm, 'INSERT', 'POINTS')) == 3, live(vm, 'INSERT', 'POINTS')
    assert any('No point numbered "99"' in m for m in vm.printed), vm.printed[-6:]
    print("ok  ABFIND an unknown number offers to create it, and No"
          " draws nothing and re-asks")


def test_abfind_stake_by_click():
    """A drawing that does not name B asks for it, and snaps the click."""
    vm = newvm()
    pts = survey(vm, stakes=('A',))
    run(vm, 'c:ABFIND',
        [(B[0] + 3.0, B[1] + 2.0, 0.0), '17', 'No', None],
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
    run(vm, 'c:ABFIND', [(B[0] + 3.0, B[1] + 2.0, 0.0), '17',
                         'No', None], 'stake snap')
    ds = dims(vm)
    assert pt3(ds[1][13]) == pt3(B), ds[1]
    print("ok  ABFIND a stake click within the snap takes the point")


def test_abfind_no_style():
    """A drawing without the style still gets its dims, and is told."""
    vm = newvm(styles=())
    pts = survey(vm)
    run(vm, 'c:ABFIND', ['17', 'No', None], 'no style')
    ds = dims(vm)
    assert len(ds) == 2 and ds[0][3] == 'STANDARD', ds
    assert ds[0][8] == 'DIMENSION', ds
    print("ok  ABFIND with no CROSS DIMENSIONS style draws in the current one")


def test_abfind_offers_the_move():
    """ABFIND asks, once the ties are drawn, and defaults to leaving it."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', ['17', None, None], 'offer')   # Enter = No
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
        ['17', 'Yes', 'R1B', None,      # moved to Pt.17m
              '17m', 'No',                   # ... and tied again, same run
              None],
        'move and carry on')
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 B from 18\'-6" to 18\'-5"']
    ins = live(vm, 'INSERT', 'POINTS')
    assert len(ins) == 4, ins
    ds = dims(vm)
    assert len(ds) == 4, ds        # the moved point's pair, then 17m's own
    newpt = (ins[-1][1][10][0], ins[-1][1][10][1])
    for d in ds:
        assert pt3(d[14]) == pt3(newpt), d
    assert len([q for q, _ in vm.prompts if 'type its number' in q]) == 3
    print("ok  ABFIND Yes moves the point and then asks for the next one")


def test_abfind_back_at_the_move_question():
    """Back there un-draws that point's ties and re-asks the number."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', ['17', 'Back', None], 'back at the offer')
    assert dims(vm) == [], dims(vm)
    print("ok  ABFIND Back at the move question un-draws the ties")


def test_abfind_back_from_the_suggestions():
    """Back there re-asks the move question, not the point number."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', ['17', 'Yes', 'Back', 'No', None], 'back to ask')
    assert len([q for q, _ in vm.prompts if 'different reading' in q]) == 2
    assert len([q for q, _ in vm.prompts if 'type its number' in q]) == 2
    assert len(dims(vm)) == 2, dims(vm)          # the ties were never lost
    assert sug_positions(vm) == []
    print("ok  ABFIND Back at the suggestions re-asks the move question")


def test_abfind_back_undoes_a_move():
    """Back at the point number puts a whole moved round back."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND', ['17', 'Yes', 'R1B', None, 'b', None],
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
    run(vm, 'c:ABMOVE', ['17', 'None'], 'no question')
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

SUGL = 'ABMOVE-POINTS'           # the scratch layer the suggestions use


def sug_positions(vm):
    """Where the suggestion markers are, in list order (their circles)."""
    return [pt3(d[10]) for _, d in live(vm, 'CIRCLE', SUGL)]


def test_abmove_suggestions_drawn():
    """Every reading is offered, on the POINTS layer, numbered."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'None'], 'suggestions')
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    assert len(got) == 45, len(got)          # 23 B-held + 22 A-held
    # ... and none of them left in the drawing once the round is over
    assert sug_positions(vm) == [], sug_positions(vm)
    assert texts(vm, SUGL) == [], texts(vm, SUGL)
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
    run(vm, 'c:ABMOVE', ['17', 'None'], 'yellow')
    marks = (ever(vm, 'POINT', SUGL) + ever(vm, 'CIRCLE', SUGL)
             + ever(vm, 'TEXT', SUGL))
    assert len(marks) == 45 * 3, len(marks)      # a point, a ring, a tag
    assert all(m.get(62) == 2 for m in marks), \
        [m for m in marks if m.get(62) != 2][:2]
    assert sorted(m[1] for m in ever(vm, 'TEXT', SUGL))[:3] == \
        ['-10A', '-10B', '-1A'], ever(vm, 'TEXT', SUGL)[:3]
    print("ok  ABMOVE draws its suggestions yellow, tag and all")


def test_abmove_locus_lines():
    """A dashed grey line through each group, on the points layer."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'None'], 'locus')
    arcs = ever(vm, 'ARC', SUGL)
    assert len(arcs) == 2, arcs
    # the readings that move A hold B, so their line is B's own reading
    # swung round B; the ones that move B are A's swung round A
    movea, moveb = arcs
    assert pt3(movea[10]) == pt3(B) and near(movea[40], PB), movea
    assert pt3(moveb[10]) == pt3(A) and near(moveb[40], PA), moveb
    for d in arcs:
        assert d.get(8) == SUGL, d
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
    run(vm, 'c:ABMOVE', ['17', 'None'], 'locus span')
    arcs = ever(vm, 'ARC', SUGL)
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
    run(vm, 'c:ABMOVE', ['17', 'None'], 'ltype')
    for d in ever(vm, 'ARC', SUGL):
        assert d.get(6) == 'PHANTOM2' and d.get(62) == 9, d
    assert 'PHANTOM2' in {x.upper() for x in vm.tables['LTYPE']}
    print("ok  the guide line's linetype and colour are tunable")


def test_abmove_suggestions_keep_off_the_points_layer():
    """Nothing throwaway lands on POINTS. It is the drawing's own layer
    - it carries a colour, and every other tool in the toolset reads
    survey points off it."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'None'], 'own layer')
    for etype in ('POINT', 'CIRCLE', 'TEXT', 'ARC'):
        assert ever(vm, etype, 'POINTS') == [], \
            (etype, ever(vm, etype, 'POINTS'))
    assert len(ever(vm, 'POINT', SUGL)) == 45
    assert len(ever(vm, 'ARC', SUGL)) == 2
    assert SUGL in {x.upper() for x in vm.tables['LAYER']}
    print("ok  ABMOVE keeps its suggestions off POINTS, on its own layer")


def test_the_chosen_one_lands_on_points():
    """The one that is picked IS a survey point, so that one does."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'chosen')
    assert len(live(vm, 'INSERT', 'POINTS')) == 4, live(vm, 'INSERT', 'POINTS')
    nums = [d.get(1) for _, d in live(vm, 'ATTRIB')]
    assert nums[-1] == '17m', nums
    # ... and the scratch layer is left empty
    for etype in ('POINT', 'CIRCLE', 'TEXT', 'ARC'):
        assert live(vm, etype, SUGL) == [], (etype, live(vm, etype, SUGL))
    print("ok  the chosen suggestion is what goes on POINTS")


def test_points_layer_is_made_when_the_drawing_lacks_it():
    """A drawing with no POINTS layer still gets its moved point."""
    vm = newvm(block=False, points=False)
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'no points layer')
    assert 'POINTS' in {x.upper() for x in vm.tables['LAYER']}
    assert texts(vm, 'POINTS') == ['17m'], texts(vm, 'POINTS')
    print("ok  the points layer is created when the drawing lacks it")


def test_abmove_the_marks_it_keeps_are_bylayer():
    """What ABMOVE leaves behind is the drawing's own colour, not yellow."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'bylayer')
    ring = live(vm, 'CIRCLE', 'FGStep')[0][1]
    note = live(vm, 'TEXT', 'FGStep')[0][1]
    moved = live(vm, 'INSERT', 'POINTS')[-1][1]
    for d in (ring, note, moved):
        assert 62 not in d, d
    print("ok  the ring, the note and the moved point stay ByLayer")


def test_abmove_prompt_stays_short():
    """Forty-five tags would swamp the command line, so the bracket
    shows only the keywords - and the one prompt takes the click too,
    so there is no Pick to type first."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'None'], 'prompt')
    asked = [q for q, _ in vm.prompts if 'type a tag' in q]
    assert len(asked) == 1, asked
    assert [q for q, _ in vm.prompts if 'type its number' in q] == \
        ['\nPick the point, or type its number (Enter to cancel): '], \
        vm.prompts
    assert asked[0] == ('\n  Move Pt.17 - click a marker or its tag, or'
                        ' type a tag [None/Back] <None>: '), asked[0]
    assert '1A' not in asked[0], asked[0]
    print("ok  ABMOVE's choice prompt shows None/Back, not 45 tags")


def test_abmove_moves_the_point():
    """Pick one and the point moves, is renamed, ringed and noted."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'move')

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
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 B from 18\'-6" to 18\'-5"'], \
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
    run(vm, 'c:ABMOVE', ['17', 'R2B', (900.0, 900.0, 0.0)], 'note')
    note = [(e, d) for e, d in live(vm, 'TEXT', 'FGStep')]
    assert len(note) == 1 and pt3(note[0][1][10]) == (900.0, 900.0), note
    assert note[0][1][40] == 6.0, note[0][1]
    # #2 is the +2" misreading of B: 18'-6" -> 18'-8"
    assert note[0][1][1] == '- Moved Pt.17 B from 18\'-6" to 18\'-8"', note
    print("ok  ABMOVE the note goes where it is placed")


def test_the_moved_point_copies_the_one_it_came_from():
    """The moved point IS the point it came from, one reading on: same
    block, layer, colour, linetype, lineweight, scale and rotation, and
    every attribute it carried - only the number is different."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    src = rich_pt(vm, P17[0], P17[1], 17)
    was = dict(_alist_dict(vm.entdata[src]))
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'copy')

    newpt = cross(PA, PB - 1.0)
    moved = [(e, d) for e, d in live(vm, 'INSERT') if e is not src][-1]
    got = moved[1]
    assert pt3(got[10]) == pt3(newpt), got
    for code in (2, 8, 62, 6, 370, 41, 42, 43, 50, 66):
        assert got[code] == was[code], (code, got.get(code), was[code])

    # both attributes travel with it, each keeping its own offset -
    # and only the number's value is written
    atts = [d for _, d in live(vm, 'ATTRIB')][-2:]
    assert [d[2] for d in atts] == ['number', 'elev'], atts
    assert [d[1] for d in atts] == ['17m', '104.25'], atts
    for d, off in zip(atts, (NUM_OFF, ELEV_OFF)):
        assert pt3(d[10]) == pt3((newpt[0] + off[0], newpt[1] + off[1])), d
        assert pt3(d[11]) == pt3((newpt[0] + off[0], newpt[1] + off[1])), d
        assert d[8] == 'SURVEY-PTS' and d[62] == 3, d
        assert d[7] == 'ROMANS' and d[50] == 0.5, d
    assert [d[40] for d in atts] == [4.0, 3.0], atts
    assert len(live(vm, 'SEQEND')) == 1, live(vm, 'SEQEND')

    # the point it came from is untouched - it is ringed, not erased
    assert pt3(_alist_dict(vm.entdata[src])[10]) == pt3(P17)
    assert 'SURVEY-PTS' in {x.upper() for x in vm.tables['LAYER']}
    print("ok  the moved point is a COPY of the old one, number apart")


def test_the_copy_keeps_off_the_default_layer():
    """A point surveyed onto its own layer stays on it when it moves -
    the copy follows the point, not abf:*point-layer*."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    rich_pt(vm, P17[0], P17[1], 17, layer='FIELD-SHOT')
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'own layer copy')
    assert len(live(vm, 'INSERT', 'FIELD-SHOT')) == 2, \
        live(vm, 'INSERT', 'FIELD-SHOT')
    # only the two stakes are on POINTS - the copy never went there
    assert len(live(vm, 'INSERT', 'POINTS')) == 2, \
        live(vm, 'INSERT', 'POINTS')
    print("ok  the copy stays on the layer its point was surveyed onto")


def test_a_copy_that_cannot_be_made_falls_back():
    """No block definition to insert again: the fallback builds one."""
    vm = newvm(block=False)
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    rich_pt(vm, P17[0], P17[1], 17)
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'fallback')
    assert len(live(vm, 'POINT', 'POINTS')) == 1, live(vm, 'POINT', 'POINTS')
    assert texts(vm, 'POINTS') == ['17m'], texts(vm, 'POINTS')
    print("ok  a point block the drawing cannot insert falls back")


def test_abmove_the_point_is_picked():
    """Click the point instead of typing its number."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE',
        [(P17[0] + 4.0, P17[1] - 3.0, 0.0), 'R1B', None], 'pick pt')
    rings = live(vm, 'CIRCLE', 'FGStep')
    assert len(rings) == 1 and pt3(rings[0][1][10]) == pt3(P17), rings
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 B from 18\'-6" to 18\'-5"'], \
        texts(vm, 'FGStep')
    nums = [d.get(1) for _, d in live(vm, 'ATTRIB')]
    assert nums[-1] == '17m', nums
    print("ok  ABMOVE the point itself can be clicked, not typed")


def test_abfind_the_point_is_picked():
    """ABFIND takes a click at the same prompt, and keeps looping."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABFIND',
        [(P17[0] - 2.0, P17[1] + 1.0, 0.0), 'No', None], 'pick pt')
    ds = dims(vm)
    assert len(ds) == 2, ds
    assert pt3(ds[0][13]) == pt3(A) and pt3(ds[0][14]) == pt3(P17), ds[0]
    print("ok  ABFIND ties the point that was clicked")


def test_a_click_on_nothing_names_nothing():
    """A click with no survey point under it draws nothing and re-asks
    - a stray click is a typo."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [(9000.0, 9000.0, 0.0), '17', 'None'], 'pick miss')
    assert len(dims(vm)) == 2, dims(vm)
    assert len([q for q, _ in vm.prompts if 'type its number' in q]) == 2
    print("ok  a click on nothing draws nothing and re-asks")


def test_a_click_on_a_stake_is_refused():
    """Clicking a stake is refused the same way naming one is."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [(A[0] + 1.0, A[1] + 1.0, 0.0), '17', 'None'],
        'pick stake')
    assert len(dims(vm)) == 2, dims(vm)
    print("ok  clicking a stake ties nothing - it is what ties are from")


def candidates(vm):
    """ABMOVE's suggestions for Pt.17, keyed by tag."""
    got = vm.loads("(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0))")
    return {c[6]: c for c in got}


def tag_spots(vm):
    """Where each tag hangs: {tag: (base, angle, width)}."""
    got = vm.loads("(abf:tag-spots '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0) "
                   "(abf:candidates '(0.0 0.0) '(240.0 0.0) "
                   f"'({P17[0]} {P17[1]} 0.0)))")
    return {s[0]: (tuple(s[1]), s[2], s[3]) for s in got}


def test_abmove_pick_on_screen():
    """Clicking a suggestion picks it, the same as typing its tag -
    straight off the one prompt, no Pick first."""
    vm = newvm()
    pts = survey(vm)
    want = candidates(vm)['R1A'][5]
    run(vm, 'c:ABMOVE',
        ['17', (want[0] + 2.0, want[1] - 1.0, 0.0), None], 'pick')
    ins = live(vm, 'INSERT', 'POINTS')
    assert pt3(ins[-1][1][10]) == pt3(want), ins[-1][1]
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 A from 21\'-1" to 21\'-4"']
    # ... and says what it took before the note is placed
    assert any('R1A taken: A 21\'-1" -> 21\'-4"' in m for m in vm.printed), \
        vm.printed[-6:]
    print("ok  ABMOVE a click on a suggestion picks it")


def test_abmove_pick_word_is_a_hint():
    """The Pick that earlier versions wanted first is answered with
    a hint, and the click that follows still lands."""
    vm = newvm()
    pts = survey(vm)
    want = candidates(vm)['R1A'][5]
    run(vm, 'c:ABMOVE',
        ['17', 'Pick', (want[0] + 2.0, want[1] - 1.0, 0.0), None], 'pick')
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 A from 21\'-1" to 21\'-4"']
    assert any('Just click it' in m for m in vm.printed), vm.printed[-8:]
    print("ok  ABMOVE typed Pick is a hint - the prompt takes the click")


def test_abmove_pick_miss():
    """A click nowhere near a suggestion is refused, not guessed at."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE',
        ['17', (9000.0, 9000.0, 0.0), 'None'], 'pick miss')
    assert texts(vm, 'FGStep') == [], texts(vm, 'FGStep')
    assert len(dims(vm)) == 2, dims(vm)
    assert len([q for q, _ in vm.prompts if 'type a tag' in q]) == 2
    print("ok  ABMOVE a click that hits nothing re-asks")


def test_abmove_click_takes_the_nearest():
    """A click takes the marker NEAREST it.  It used to take the first
    in the list within a foot, which near the crossing was always R1A:
    R1B sits an inch off the point with R1A three inches further on,
    and a click dead on R1B moved A."""
    vm = newvm()
    pts = survey(vm)
    r1b = candidates(vm)['R1B'][5]
    run(vm, 'c:ABMOVE', ['17', (r1b[0] + 0.15, r1b[1] + 0.15, 0.0), None],
        'nearest')
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 B from 18\'-6" to 18\'-5"'], \
        texts(vm, 'FGStep')
    print("ok  ABMOVE a click takes the nearest marker, not the first listed")


def test_abmove_click_on_a_tag():
    """The tag is as good a target as its marker - the better one when
    the markers crowd - and a click on its text picks the reading it
    names, whatever marker happens to be nearer."""
    vm = newvm()
    pts = survey(vm)
    base, ang, width = tag_spots(vm)['R2B']
    mid = (base[0] + 0.5 * width * math.cos(ang),
           base[1] + 0.5 * width * math.sin(ang), 0.0)
    run(vm, 'c:ABMOVE', ['17', mid, None], 'tag click')
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 B from 18\'-6" to 18\'-8"'], \
        texts(vm, 'FGStep')
    print("ok  ABMOVE a click on a tag picks the reading it names")


def test_abmove_a_crowded_click_asks():
    """Zoomed out, a click cannot tell R1B from the markers an inch or
    three away, so the routine lists what is under it and asks -
    nearest first, and the nearest is the Enter answer."""
    vm = newvm()
    pts = survey(vm)
    vm.sysvars['VIEWSIZE'] = 2000.0       # 3 px of pickbox = 5.6" now
    r1b = candidates(vm)['R1B'][5]
    click = (r1b[0] + 0.15, r1b[1] + 0.15, 0.0)
    run(vm, 'c:ABMOVE', ['17', click, None, None], 'tie')
    asked = [q for q, _ in vm.prompts if 'Which one?' in q]
    assert len(asked) == 1, asked
    assert asked[0].startswith('\n  Which one? [R1B/'), asked[0]
    assert '/R2B' in asked[0] and '/R1A' in asked[0], asked[0]
    assert asked[0].endswith('/Back] <R1B>: '), asked[0]
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 B from 18\'-6" to 18\'-5"'], \
        texts(vm, 'FGStep')
    # the same click, answered with one of the others, moves that one
    vm = newvm()
    pts = survey(vm)
    vm.sysvars['VIEWSIZE'] = 2000.0
    run(vm, 'c:ABMOVE', ['17', click, 'R1A', None], 'tie answered')
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 A from 21\'-1" to 21\'-4"'], \
        texts(vm, 'FGStep')
    # and Back there is the markers again, nothing moved yet
    vm = newvm()
    pts = survey(vm)
    vm.sysvars['VIEWSIZE'] = 2000.0
    run(vm, 'c:ABMOVE', ['17', click, 'Back', 'None'], 'tie back')
    assert texts(vm, 'FGStep') == [], texts(vm, 'FGStep')
    assert len([q for q, _ in vm.prompts if 'type a tag' in q]) == 2
    print("ok  ABMOVE a click that cannot tell markers apart asks which")


def test_abmove_a_close_zoom_settles_it():
    """The same click zoomed in is exact: the pickbox spans less than
    the markers are apart, so nothing is asked."""
    vm = newvm()
    pts = survey(vm)
    vm.sysvars['VIEWSIZE'] = 100.0        # 3 px = 0.28"
    r1b = candidates(vm)['R1B'][5]
    run(vm, 'c:ABMOVE', ['17', (r1b[0] + 0.15, r1b[1] + 0.15, 0.0), None],
        'close zoom')
    assert [q for q, _ in vm.prompts if 'Which one?' in q] == []
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 B from 18\'-6" to 18\'-5"']
    print("ok  ABMOVE zoomed in, the click needs no asking")


def test_abmove_typed_tag_any_case():
    """A tag typed in lower case is the tag."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'r1b', None], 'lower case')
    assert texts(vm, 'FGStep') == ['- Moved Pt.17 B from 18\'-6" to 18\'-5"']
    print("ok  ABMOVE a tag typed in any case is accepted")


def test_abmove_typed_nonsense_re_asks():
    """Text that is no tag is reported and the prompt re-asks."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'zz', 'None'], 'nonsense')
    assert texts(vm, 'FGStep') == []
    assert len([q for q, _ in vm.prompts if 'type a tag' in q]) == 2
    assert any('"zz" is not one of the tags' in m for m in vm.printed)
    print("ok  ABMOVE a typed non-tag re-asks")


def _seg_samples(base, ang, width, n=12):
    return [(base[0] + width * k / n * math.cos(ang),
             base[1] + width * k / n * math.sin(ang)) for k in range(n + 1)]


def test_abmove_tags_keep_clear():
    """The look-alike markers sit an inch or three apart, and a tag
    beside each piled six onto one spot.  Now every tag hangs off the
    arc on a leader with daylight to the next one, and none lands on
    the other arc's markers."""
    vm = newvm()
    pts = survey(vm)
    cands = candidates(vm)
    spots = tag_spots(vm)
    assert set(spots) == set(cands), set(cands) - set(spots)
    hgt = vm.loads('abf:*sug-hgt*')
    gap = vm.loads('abf:*tag-gap*')
    rad = vm.loads('abf:*sug-radius*')
    # tag to tag: no two text strips closer than the daylight
    tags = sorted(spots)
    for i, a in enumerate(tags):
        sa = _seg_samples(*spots[a])
        for b in tags[i + 1:]:
            sb = _seg_samples(*spots[b])
            d = min(math.dist(p, q) for p in sa for q in sb)
            assert d >= hgt + gap - 1e-6, (a, b, d)
    # tag to marker: no text strip on any marker's ring
    for a in tags:
        sa = _seg_samples(*spots[a])
        for b, c in cands.items():
            d = min(math.dist(p, (c[5][0], c[5][1])) for p in sa)
            assert d >= rad + 0.5 * hgt + gap - 0.5, (a, b, d)
    # every tag hangs off its own arc, a leader's length from its marker
    for a in tags:
        base = spots[a][0]
        assert math.dist(base[:2], cands[a][5][:2]) >= 10.0 - 1e-6, (a, base)
    print("ok  ABMOVE's tags hang clear of each other and of the markers")


def test_abmove_tags_take_four_quarters():
    """The two arcs cut the sheet into four quarters, and each half of
    each group - A grown, A shrunk, B grown, B shrunk - hangs its tags
    in a quarter of its own."""
    vm = newvm()
    pts = survey(vm)
    cands = candidates(vm)
    spots = tag_spots(vm)
    quarters = {}
    for tag, c in cands.items():
        base = spots[tag][0][:2]
        # which side of each ARC the tag hangs: further from the stake
        # than the point is, or nearer - the arcs curve, so a straight
        # line through the point would misjudge the far sweep
        q = (math.dist(base, A) > PA, math.dist(base, B) > PB)
        half = (c[2], c[4] > c[3])           # moved tape, grown?
        quarters.setdefault(half, set()).add(q)
    assert len(quarters) == 4, quarters
    assert all(len(v) == 1 for v in quarters.values()), quarters
    assert len(set().union(*quarters.values())) == 4, quarters
    print("ok  ABMOVE's four half-groups take the four quarters")


def test_abmove_tag_on_a_leader():
    """Each marker gets a leader to its tag, and a tag that would read
    upside down is turned round, right-justified on its base."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'None'], 'leaders')
    leads = ever(vm, 'LINE', SUGL)
    tags = ever(vm, 'TEXT', SUGL)
    assert len(leads) == 45 and len(tags) == 45, (len(leads), len(tags))
    spots = tag_spots(vm)
    for t in tags:
        base, ang, _ = spots[t[1]]
        rot = t.get(50, 0.0)
        assert rot < math.pi / 2 + 1e-9 or rot > 1.5 * math.pi - 1e-9, \
            (t[1], rot)
        if t.get(72) == 2:
            assert pt3(t[11]) == pt3(base), (t[1], t[11], base)
        else:
            assert pt3(t[10]) == pt3(base), (t[1], t[10], base)
    assert all(l.get(62) == 2 for l in leads)
    print("ok  ABMOVE's tags hang on leaders and never read upside down")


def test_abmove_back_from_the_choice():
    """Back at the choice takes the dims away and re-asks the number."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'Back', '17', 'None'], 'back 2')
    assert len(dims(vm)) == 2, dims(vm)          # one pair, not two
    assert sug_positions(vm) == []
    print("ok  ABMOVE Back at the choice re-asks the point number")


def test_abmove_back_from_the_note():
    """Back at the note re-asks the choice, suggestions still up."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'R1B', 'Back', 'None'], 'back 3')
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
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'one shot')
    assert len([q for q, _ in vm.prompts if 'type its number' in q]) == 1
    assert len(dims(vm)) == 2, dims(vm)
    assert len(texts(vm, 'FGStep')) == 1, texts(vm, 'FGStep')
    print("ok  ABMOVE settles one point and ends")


def test_abmove_cancels_on_enter():
    """Enter at the point number is 'never mind', not a bad answer."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', [None], 'cancel')
    assert dims(vm) == [], dims(vm)
    assert sug_positions(vm) == []
    assert vm.sysvars['CLAYER'] == '0'
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD'
    print("ok  ABMOVE Enter at the point number cancels cleanly")


def test_abmove_without_the_block():
    """No ab_pt block in the drawing: a POINT and a label instead."""
    vm = newvm(block=False)
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'no block')
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
    run(vm, 'c:ABFIND', ['A', '17', 'No', None], 'stake as point')
    assert len(dims(vm)) == 2, dims(vm)
    print("ok  ABFIND naming a stake ties nothing - it is what ties are from")


def test_moved_point_is_a_point_afterwards():
    """Pt.17m is a real survey point: the next run can tie it."""
    vm = newvm()
    pts = survey(vm)
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'move')
    moved = live(vm, 'INSERT', 'POINTS')[-1][0]
    # a fresh run re-reads the drawing and finds it by its new number
    run(vm, 'c:ABFIND', ['17m', 'No', None],
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
    run(vm, 'c:ABMOVE', ['17'], 'no suggestions')
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
    run(vm, 'c:ABFIND', [], 'empty drawing')
    assert dims(vm) == []
    print("ok  an empty drawing is reported, not crashed on")



def test_undo_off_is_not_an_error_at_the_end_of_the_run():
    """abf:run opens its undo group conditionally -- _Begin errors when
    UNDOCTL's recording bit is clear -- and closed it unconditionally,
    so a drafter with undo off got the dimensions drawn and then an
    AutoLISP error, with the OSMODE and CMDECHO putback queued behind it
    and never reached.  All three commands run through abf:run, so all
    three carried it.

    The sweep in tests/test_undo_off.py cannot catch this one: ABFIND
    stops before asking anything on an empty drawing (it is in
    test_cancel_paths' NO_PROMPT for that reason), so a bare VM never
    reaches the close.  It takes the survey points below to get there.
    """
    for cmd, script in (('c:ABFIND', ['17', 'No', None]),
                        ('c:ABMOVE', ['17', 'None']),
                        ('c:ABPCREATE', [200.0, 180.0, '23', None])):
        vm = newvm()
        vm.sysvars['UNDOCTL'] = 4        # undo on, recording bit clear
        survey(vm)
        run(vm, cmd, script, cmd + ' with undo recording off')
        sent = [c for c in vm.commands if c and c[0] == '_.UNDO']
        assert sent == [], \
            "%s sent an UNDO command with recording off: %r" % (cmd, sent)
        assert vm.sysvars['CMDECHO'] == 1 and vm.sysvars['OSMODE'] == 4133, \
            "%s did not put the settings back: CMDECHO %r OSMODE %r" % (
                cmd, vm.sysvars['CMDECHO'], vm.sysvars['OSMODE'])

    # and with recording on the bracket is still there, both halves
    for cmd, script in (('c:ABFIND', ['17', 'No', None]),
                        ('c:ABMOVE', ['17', 'None']),
                        ('c:ABPCREATE', [200.0, 180.0, '23', None])):
        vm = newvm()
        survey(vm)
        run(vm, cmd, script, cmd + ' with undo recording on')
        sent = [c for c in vm.commands if c and c[0] == '_.UNDO']
        assert sent == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']], \
            "%s: %r" % (cmd, sent)
    print("ok  undo off is not an error, and undo on still brackets the run")



# ---- ABPCREATE --------------------------------------------------------
# The point is NOT in the drawing: the two readings it was taped at are
# typed instead of a number.  P200 is where 200" off A and 180" off B
# cross on the field side (P17 is north of the stakes, so north is the
# field side); SHORT is a pair that cannot cross at all - two 100"
# tapes across a 240" baseline fall 40" short of each other.

P200 = cross(200.0, 180.0)
SHORT = (100.0, 100.0)


def sugs_for(vm, ra, rb):
    """ABPCREATE's candidates for a pair, keyed by tag."""
    got = vm.loads("(abf:create-candidates '(0.0 0.0) '(240.0 0.0) %r %r "
                   "(abf:field-ref '(0.0 0.0) '(240.0 0.0) "
                   "(abf:collect-points)))" % (ra, rb))
    return {c[6]: c for c in got}


def test_abpcreate_two_readings_that_cross():
    """A pair that crosses is plotted where it crosses, named, and
    tied - and the scaffolding is swept behind it."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'cross')
    ins = live(vm, 'INSERT')
    assert len(ins) == 4, ins
    assert pt3(ins[-1][1][10]) == pt3(P200), ins[-1][1]
    assert [d[1] for _, d in live(vm, 'ATTRIB')][-1] == '23'
    # the two ties measure the readings that were typed
    ds = dims(vm)
    assert len(ds) == 2, ds
    assert pt3(ds[0][13]) == pt3(A) and pt3(ds[0][14]) == pt3(P200), ds[0]
    assert pt3(ds[1][13]) == pt3(B) and pt3(ds[1][14]) == pt3(P200), ds[1]
    # nothing of the working-out is left on the drawing
    assert live(vm, 'CIRCLE', 'ABMOVE-POINTS') == []
    assert live(vm, 'POINT', 'ABMOVE-POINTS') == []
    assert vm.sysvars['CLAYER'] == '0'
    print("ok  ABPCREATE a pair that crosses is plotted, named and tied")


def test_abpcreate_takes_the_side_the_survey_is_on():
    """Two readings cross twice, either side of the A-B line.  The
    points already plotted say which side the pool is on."""
    for sign in (1.0, -1.0):
        vm = newvm()
        ab_pt(vm, A[0], A[1], 'A')
        ab_pt(vm, B[0], B[1], 'B')
        ab_pt(vm, P17[0], sign * P17[1], 17)      # the only field point
        run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'field side')
        got = live(vm, 'INSERT')[-1][1][10]
        assert pt3(got) == pt3((P200[0], sign * P200[1])), (sign, got)
    print("ok  ABPCREATE crosses onto the side the rest of the survey is on")


def test_abpcreate_a_pair_that_cannot_cross_shows_why():
    """Both readings are drawn whole, the gap is named, and the pairs
    they could have been are offered."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [SHORT[0], SHORT[1], 'None', None], 'short')
    said = ' '.join(vm.printed)
    assert 'cannot cross' in said and 'fall 3\'-4" short' in said, said
    # the two whole circles: one per stake, at the reading typed
    ghosts = [d for d in ever(vm, 'CIRCLE', 'ABMOVE-POINTS')
              if d.get(40) == 100.0]
    assert len(ghosts) == 2, ghosts
    assert {pt3(d[10]) for d in ghosts} == {pt3(A), pt3(B)}, ghosts
    assert {d[6] for d in ghosts} == {'DASHED'}, ghosts
    # and nothing was created - None took no reading
    assert len(live(vm, 'INSERT')) == 3, live(vm, 'INSERT')
    assert 'another pair' in said
    print("ok  ABPCREATE a pair that cannot cross draws both arcs and says so")


def test_abpcreate_offers_the_pairs_it_could_have_been():
    """ABMOVE's sweep, with no point to start from: one reading held,
    the other walked, every pair that reaches offered."""
    vm = newvm()
    survey(vm)
    got = sugs_for(vm, SHORT[0], SHORT[1])
    # 40" short, so nothing under 4 feet reaches; 10 feet is the cap
    assert sorted(got) == sorted(['%d%s' % (n, t) for t in 'AB'
                                  for n in range(4, 11)]), sorted(got)
    for tag, c in got.items():
        a = math.hypot(c[5][0] - A[0], c[5][1] - A[1])
        b = math.hypot(c[5][0] - B[0], c[5][1] - B[1])
        held = SHORT[0] if c[1] == 'A' else SHORT[1]
        # the held tape is untouched, the other is the number in the tag
        assert abs((a if c[1] == 'A' else b) - held) < 1e-6, (tag, a, b)
        assert abs(c[4] - (held + 12.0 * int(tag[:-1]))) < 1e-6, (tag, c[4])
        assert c[5][1] > 0.0, (tag, c[5])       # on the field side
    print("ok  ABPCREATE offers every pair a misread tape could have been")


def test_abpcreate_labels_carry_the_two_readings():
    """Each candidate stands for a DIFFERENT pair, so the pair is
    written beside its marker - that is what tells them apart."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [SHORT[0], SHORT[1], 'None', None], 'labels')
    got = sugs_for(vm, SHORT[0], SHORT[1])
    drawn = ever(vm, 'TEXT', 'ABMOVE-POINTS')
    assert len(drawn) == len(got), (len(drawn), len(got))
    for d in drawn:
        tag = d[1].split()[0]
        c = got[tag]
        a = math.hypot(c[5][0] - A[0], c[5][1] - A[1])
        b = math.hypot(c[5][0] - B[0], c[5][1] - B[1])
        assert d[1] == '%s  %s / %s' % (tag, arch(a), arch(b)), d[1]
    # and the table on the command line says the same two numbers
    said = ' '.join(vm.printed)
    assert '   tag   moves  by' in said, said
    c = got['4A']
    assert '4A' in said and arch(c[4]) in said, said
    print("ok  ABPCREATE every marker is labelled with the pair it stands for")


def arch(d):
    """A distance the way abf:fmt writes it: F'-I n/16\"."""
    sixteenths = int(round(d * 16.0))
    feet, rest = divmod(sixteenths, 192)
    inch, frac = divmod(rest, 16)
    out = "%d'-%d" % (feet, inch)
    if frac:
        g = 16
        while frac % 2 == 0:
            frac //= 2
            g //= 2
        out += ' %d/%d' % (frac, g)
    return out + '"'


def test_abpcreate_a_marker_can_be_clicked():
    """The one pick prompt takes a click, exactly as ABMOVE's does."""
    vm = newvm()
    survey(vm)
    want = sugs_for(vm, SHORT[0], SHORT[1])['6B'][5]
    run(vm, 'c:ABPCREATE',
        [SHORT[0], SHORT[1], (want[0] + 2.0, want[1] - 1.0, 0.0),
         '23', None], 'click')
    ins = live(vm, 'INSERT')[-1][1]
    assert pt3(ins[10]) == pt3(want), ins
    assert any('6B taken' in m and 'A held' in m for m in vm.printed), \
        vm.printed[-8:]
    print("ok  ABPCREATE a marker is clicked or its tag typed")


def test_abpcreate_a_label_can_be_clicked():
    """The label is as good a target as the marker, and the easier one:
    it hangs clear of the arc, so a click that is nowhere near any
    marker still takes the pair the label names."""
    vm = newvm()
    survey(vm)
    spots = vm.loads("(abf:create-spots '(0.0 0.0) '(240.0 0.0) %r %r "
                     "(abf:create-candidates '(0.0 0.0) '(240.0 0.0) %r %r "
                     "(abf:field-ref '(0.0 0.0) '(240.0 0.0) "
                     "(abf:collect-points))))"
                     % (SHORT[0], SHORT[1], SHORT[0], SHORT[1]))
    spot = [s for s in spots if s[0] == '7B'][0]
    mid = (spot[1][0] + 0.5 * spot[3] * math.cos(spot[2]),
           spot[1][1] + 0.5 * spot[3] * math.sin(spot[2]), 0.0)
    got = sugs_for(vm, SHORT[0], SHORT[1])
    assert min(math.hypot(mid[0] - c[5][0], mid[1] - c[5][1])
               for c in got.values()) > abf_snap(vm), \
        "the click has to be out of every marker's reach to prove this"
    run(vm, 'c:ABPCREATE', [SHORT[0], SHORT[1], mid, '23', None], 'label')
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == pt3(got['7B'][5])
    print("ok  ABPCREATE a click on the label takes the pair it names")


def abf_snap(vm):
    return vm.loads('abf:*snap*')


def test_abpcreate_none_asks_for_another_pair():
    """The way out of a pair that cannot be made to work is another
    pair - which is what None goes back to."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE',
        [SHORT[0], SHORT[1], 'None', 200.0, 180.0, '23', None], 'retry')
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == pt3(P200)
    print("ok  ABPCREATE None takes no reading and asks for another pair")


def test_abpcreate_a_pair_nothing_reaches():
    """Two tapes that cannot be made to meet inside abf:*max-shift*
    are reported, and the readings are asked again."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [20.0, 20.0, 200.0, 180.0, '23', None], 'hopeless')
    said = ' '.join(vm.printed)
    assert 'makes the two meet' in said, said
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == pt3(P200)
    print("ok  ABPCREATE a pair nothing reaches is reported, not guessed at")


def test_abpcreate_names_the_point():
    """One past the highest number is offered, and a number the drawing
    already uses is refused - a number names ONE point."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '17', '23', None], 'name')
    asked = [q for q, _ in vm.prompts if 'Number for the new point' in q]
    assert len(asked) == 2, asked
    assert '<18>' in asked[0], asked[0]          # 17 is the highest
    assert any('already in the drawing' in m for m in vm.printed), \
        vm.printed[-6:]
    assert [d[1] for _, d in live(vm, 'ATTRIB')][-1] == '23'
    print("ok  ABPCREATE offers the next number and refuses one in use")


def test_abpcreate_builds_the_point_like_its_neighbours():
    """A survey point is more than a position.  The nearest one is the
    pattern - block, layer, colour, linetype, lineweight, scale,
    rotation and attribute layout - and only the number is written: a
    point just plotted has no elevation, and the neighbour's is not
    its own."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    rich_pt(vm, P17[0], P17[1], 17)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'pattern')
    got = live(vm, 'INSERT', 'SURVEY-PTS')[-1][1]
    assert pt3(got[10]) == pt3(P200), got
    for code, want in ((2, 'ab_pt'), (62, 3), (6, 'HIDDEN'), (370, 50),
                       (41, 2.0), (42, 2.0), (43, 2.0), (50, 0.5)):
        assert got[code] == want, (code, got.get(code), want)
    atts = [d for _, d in live(vm, 'ATTRIB')][-2:]
    assert [d[2] for d in atts] == ['number', 'elev'], atts
    assert [d[1] for d in atts] == ['23', ''], atts
    for d, off in zip(atts, (NUM_OFF, ELEV_OFF)):
        assert pt3(d[10]) == pt3((P200[0] + off[0], P200[1] + off[1])), d
    assert any('its other attributes left blank' in m for m in vm.printed), \
        vm.printed[-6:]
    print("ok  ABPCREATE builds the point like its neighbours, other"
          " attributes blank")


def test_abpcreate_new_atts_keeps_them():
    """abf:*new-atts* is for a drawing whose second attribute really is
    the same on every point."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    rich_pt(vm, P17[0], P17[1], 17)
    vm.loads('(setq abf:*new-atts* T)')
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'keep atts')
    atts = [d for _, d in live(vm, 'ATTRIB')][-2:]
    assert [d[1] for d in atts] == ['23', '104.25'], atts
    print("ok  ABPCREATE abf:*new-atts* keeps the pattern's other values")


def test_abpcreate_with_nothing_but_stakes():
    """No point plotted says which side of A-B the pool is on, so that
    one drawing is asked - and the click only picks the SIDE."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    run(vm, 'c:ABPCREATE',
        [200.0, 180.0, (120.0, -150.0, 0.0), '1', None], 'mute drawing')
    said = ' '.join(vm.printed)
    assert 'does not say which side' in said, said
    got = live(vm, 'INSERT')[-1][1]
    assert pt3(got[10]) == pt3((P200[0], -P200[1])), got
    # nothing to pattern it on, so it is built from the file's defaults
    assert got[8] == 'POINTS', got
    assert any("this file's own defaults" in m for m in vm.printed), \
        vm.printed[-6:]
    print("ok  ABPCREATE a drawing with nothing but stakes is asked the side")


def test_abpcreate_back_walks_the_chain():
    """Back at the name re-asks the pick, Back at the pick the B
    reading, Back at B the A reading, and Back at the first A says so."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE',
        [SHORT[0], SHORT[1], '5A', 'b',        # name -> pick
         'Back',                               # pick -> B reading
         SHORT[1], '5A', '23', None], 'back chain')
    # the pick was put twice by the two Backs, and the B reading once
    # again by the second of them
    assert len([q for q, _ in vm.prompts if 'B to the new point' in q]) == 2
    assert len([q for q, _ in vm.prompts
                if 'click a marker or its label' in q]) == 3
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == \
        pt3(sugs_for(vm, SHORT[0], SHORT[1])['5A'][5])

    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, 'b', 180.0, '23', None], 'back name')
    assert any('Already at the first point' not in m for m in vm.printed)
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == pt3(P200)

    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', ['Back', None], 'back at the first')
    assert any('Already at the first point' in m for m in vm.printed), \
        vm.printed[-4:]
    print("ok  ABPCREATE Back walks the chain and stops at the first question")


def test_abpcreate_loops_and_back_undoes_a_whole_round():
    """It keeps asking for pairs, and Back at the A reading takes the
    last point away again - the point, its ties and its number."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE',
        [200.0, 180.0, '23', 210.0, 190.0, '24', 'Back', None], 'loop back')
    assert len(live(vm, 'INSERT')) == 4, live(vm, 'INSERT')
    assert [d[1] for _, d in live(vm, 'ATTRIB')] == ['A', 'B', '17', '23']
    assert len(dims(vm)) == 2, dims(vm)
    assert any('Stepping back one point' in m for m in vm.printed)
    print("ok  ABPCREATE loops, and Back takes a created round away whole")


def test_abfind_back_undoes_a_round_that_created_a_point():
    """A created round is one of ABFIND's rounds like any other, so Back
    at the point number takes it away whole - the point, its number and
    its ties - and puts it back out of the lookup with them."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABFIND',
        ['23', 'Yes', 200.0, 180.0, '', 'b', '17', 'No', None], 'undo new')
    assert len(live(vm, 'INSERT')) == 3, live(vm, 'INSERT')
    assert [d[1] for _, d in live(vm, 'ATTRIB')] == ['A', 'B', '17']
    assert len(dims(vm)) == 2, dims(vm)                 # only Pt.17's
    assert pt3(dims(vm)[0][14]) == pt3(P17), dims(vm)[0]
    # and the summary does not claim the point it took back again
    assert not any('point created' in m for m in vm.printed), vm.printed[-4:]
    print("ok  ABFIND Back takes a round that created a point away whole")


def test_abfind_offers_to_create_a_number_it_cannot_find():
    """A number that names no point is far more often a point that was
    never plotted than a typo - so it is offered, and Yes plots it and
    ABFIND carries on."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABFIND', ['23', 'Yes', 200.0, 180.0, '', '17', 'No', None],
        'find create')
    ins = live(vm, 'INSERT')
    assert len(ins) == 4 and pt3(ins[-1][1][10]) == pt3(P200), ins
    assert [d[1] for _, d in live(vm, 'ATTRIB')][-1] == '23'
    # the new point's ties, and then Pt.17's - it went round again
    assert len(dims(vm)) == 4, dims(vm)
    # the number typed is what the name prompt offers
    assert any('<23>' in q for q, _ in vm.prompts), vm.prompts[-4:]
    print("ok  ABFIND offers to create a number it cannot find, and carries on")


def test_abmove_offers_to_create_and_is_then_done():
    """ABMOVE settles ONE point, and a point that did not exist is
    settled by existing."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABMOVE', ['23', 'Yes', 200.0, 180.0, ''], 'move create')
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == pt3(P200)
    assert any('run ABMOVE again to move it' in m for m in vm.printed), \
        vm.printed[-4:]
    print("ok  ABMOVE creates the point it was asked for and is then done")


def test_the_create_offer_can_be_backed_out_of():
    """Back and Enter at the A reading both put the number prompt back
    without plotting anything."""
    for script in (['23', 'Yes', 'Back', '17', 'No', None],
                   ['23', 'Yes', None, '17', 'No', None]):
        vm = newvm()
        survey(vm)
        run(vm, 'c:ABFIND', script, 'backed out')
        assert len(live(vm, 'INSERT')) == 3, live(vm, 'INSERT')
        assert len(dims(vm)) == 2, dims(vm)
    print("ok  the offer to create is backed out of without plotting")



# ---- ABPCREATE: the edges ---------------------------------------------

def test_abpcreate_tangent_pairs_place_the_point():
    """Two arcs that just touch meet at one spot, and it is on the line
    through the stakes.  Both ways round: tapes that only just reach
    each other, and one arc that just reaches inside the other."""
    for ra, rb, want in ((100.0, 140.0, 100.0),      # d == ra + rb
                         (500.0, 260.0, 500.0),      # d == ra - rb
                         (100.0, 340.0, -100.0)):    # d == rb - ra
        vm = newvm()
        survey(vm)
        run(vm, 'c:ABPCREATE', [ra, rb, '23', None], 'tangent %r' % ra)
        got = live(vm, 'INSERT')[-1][1][10]
        assert pt3(got) == pt3((want, 0.0)), (ra, rb, got)
        assert near(math.hypot(got[0] - A[0], got[1] - A[1]), ra), got
        assert near(math.hypot(got[0] - B[0], got[1] - B[1]), rb), got
    print("ok  ABPCREATE two arcs that just touch meet at one spot")


def test_abpcreate_a_miss_too_small_to_print_is_a_crossing():
    """abf:*touch*.  The arithmetic finds gaps the drawing cannot print,
    and without a band for them a pair of readings that DO meet is
    answered with `the two arcs fall 0" short of each other` and a table
    of readings to replace them with - noise in place of an answer."""
    for gap in (1e-9, 1e-7, 1e-4, 0.01, 0.03):
        vm = newvm()
        survey(vm)
        run(vm, 'c:ABPCREATE', [100.0, 140.0 - gap, '23', None],
            'gap %r' % gap)
        said = ' '.join(vm.printed)
        assert 'cannot cross' not in said, (gap, said)
        assert len(live(vm, 'INSERT')) == 4, (gap, live(vm, 'INSERT'))
    # and a gap it CAN print is still reported
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [100.0, 139.0, 'None', None], 'printable gap')
    assert any('cannot cross' in m and '0\'-1"' in m for m in vm.printed), \
        vm.printed[-6:]
    print("ok  ABPCREATE a miss too small to print is taken as a crossing")


def test_abf_closest_is_where_the_arcs_touch():
    """The crossing abf:circint cannot solve for a pair inside
    abf:*touch* - the square root it takes has gone a hair negative."""
    vm = newvm()
    for ra, rb, want in ((100.0, 140.0, 100.0),
                         (500.0, 260.0, 500.0),
                         (100.0, 340.0, -100.0)):
        got = vm.loads("(abf:closest '(0.0 0.0) '(240.0 0.0) %r %r)"
                       % (ra, rb))
        assert pt3(got) == pt3((want, 0.0)), (ra, rb, got)
    print("ok  abf:closest is the spot both arcs touch, either way round")


def test_abpcreate_cancel_at_every_prompt():
    """Esc anywhere in a creation: the handler runs once, every setting
    is put back, and none of the working-out is left behind."""
    from lispvm import LispError as _LE

    def esc(vm):
        raise _LE('Function cancelled', vm)

    for label, script in (('the A reading', []),
                          ('the B reading', [200.0]),
                          ('the pick', [100.0, 100.0]),
                          ('the name', [100.0, 100.0, '5A']),
                          ('the name, crossed', [200.0, 180.0])):
        vm = newvm()
        vm.handle_errors = True
        survey(vm)
        before = dict(vm.sysvars)
        vm.run('c:ABPCREATE', list(script) + [esc])
        assert len(vm.handled_errors) == 1, (label, vm.handled_errors)
        assert {k: v for k, v in vm.sysvars.items()
                if before.get(k) != v} == {}, label
        assert live(vm, 'CIRCLE', 'ABMOVE-POINTS') == [], label
        assert live(vm, 'TEXT', 'ABMOVE-POINTS') == [], label
        assert live(vm, 'POINT', 'ABMOVE-POINTS') == [], label
        assert not [s for s in vm.printed if 'error' in s.lower()], label
        assert len(live(vm, 'INSERT')) == 3, (label, live(vm, 'INSERT'))
    print("ok  ABPCREATE a cancel at any prompt leaves the drawing as it was")


def test_abpcreate_back_past_the_first_reading():
    """Two created points backed out one at a time, and then a Back with
    nothing left to take back."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE',
        [200.0, 180.0, '23', 210.0, 190.0, '24', 'Back', 'Back', 'Back',
         None], 'back past the end')
    assert len(live(vm, 'INSERT')) == 3, live(vm, 'INSERT')
    assert dims(vm) == [], dims(vm)
    assert [d[1] for _, d in live(vm, 'ATTRIB')] == ['A', 'B', '17']
    assert len([m for m in vm.printed
                if 'Stepping back one point' in m]) == 2, vm.printed
    assert any('Already at the first point' in m for m in vm.printed), \
        vm.printed[-4:]
    print("ok  ABPCREATE Back unwinds every created round and then says so")


def test_abpcreate_with_no_point_block():
    """No block to insert again: the fallback point and its label."""
    vm = newvm(block=False)
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    ab_pt(vm, P17[0], P17[1], 17)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'no block')
    assert len(live(vm, 'POINT', 'POINTS')) == 1, live(vm, 'POINT', 'POINTS')
    assert texts(vm, 'POINTS') == ['23'], texts(vm, 'POINTS')
    print("ok  ABPCREATE with no point block makes a POINT and labels it")


def test_abpcreate_restores_a_frozen_points_layer():
    """A run onto a frozen or switched-off layer looks like the command
    did nothing, so the layer is put back first."""
    vm = newvm()
    rec = add_layer(vm, 'POINTS', 2)
    vm.entdata[rec] = [Dot(0, 'LAYER'), Dot(2, 'POINTS'), Dot(70, 1),
                       Dot(62, -2)]                   # frozen AND off
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    ab_pt(vm, P17[0], P17[1], 17)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'frozen')
    got = _alist_dict(vm.entdata[rec])
    assert got[70] == 0 and got[62] == 2, got
    assert len(live(vm, 'INSERT', 'POINTS')) == 4
    print("ok  ABPCREATE thaws and switches on the layer it plots onto")


def test_a_name_that_strips_to_nothing_is_not_offered():
    """"Pt", "#" and a line of spaces all strip to nothing, and a point
    cannot be created with no number to be looked up by."""
    for typed in ('Pt', 'Pt.', '#', '  '):
        vm = newvm()
        survey(vm)
        run(vm, 'c:ABFIND', [typed, '17', 'No', None], 'strip %r' % typed)
        assert len(dims(vm)) == 2, (typed, dims(vm))
        assert not any('Create Pt.' in m for m in vm.printed), \
            (typed, [m for m in vm.printed if 'Create' in m])
        assert any('names no point' in m for m in vm.printed), \
            (typed, vm.printed[-3:])
    print("ok  a typed name with no number in it is not offered as a point")


def test_abpcreate_two_markers_under_one_click():
    """The click cannot tell them apart at this zoom, so it says so and
    asks - the same tie-break ABMOVE does."""
    vm = newvm()
    survey(vm)
    got = sugs_for(vm, SHORT[0], SHORT[1])
    a, b = got['4A'][5], got['5A'][5]
    vm = newvm()
    survey(vm)
    vm.sysvars['VIEWSIZE'] = math.hypot(a[0] - b[0], a[1] - b[1]) * 400.0
    mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0)
    run(vm, 'c:ABPCREATE', [SHORT[0], SHORT[1], mid, '4A', '23', None],
        'which one')
    assert any('markers under that click' in m for m in vm.printed), \
        vm.printed[-8:]
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == pt3(a)
    print("ok  ABPCREATE a click that cannot tell two apart asks which")


def test_abpcreate_max_sugg_caps_each_group():
    """The cap is per held stake, so shortening the list never costs you
    one of the two answers."""
    vm = newvm()
    survey(vm)
    vm.loads('(setq abf:*max-sugg* 3)')
    got = sugs_for(vm, SHORT[0], SHORT[1])
    assert len(got) == 6, sorted(got)
    assert sorted(t[-1] for t in got) == ['A'] * 3 + ['B'] * 3, sorted(got)
    print("ok  ABPCREATE abf:*max-sugg* caps each group, not the pair")


def test_abpcreate_no_two_candidates_on_one_spot():
    """Two readings that land on the same place are one choice."""
    vm = newvm()
    survey(vm)
    for ra, rb in ((SHORT[0], SHORT[1]), (400.0, 100.0), (60.0, 340.0)):
        pts = [(round(c[5][0], 3), round(c[5][1], 3))
               for c in sugs_for(vm, ra, rb).values()]
        assert len(pts) == len(set(pts)), (ra, rb, pts)
    print("ok  ABPCREATE no two candidates sit on the same spot")


def test_abpcreate_a_number_made_this_run_is_refused():
    """The point it just made is a point like any other from here."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE',
        [200.0, 180.0, '23', 210.0, 190.0, '23', '24', None], 'collide')
    assert any('already in the drawing' in m for m in vm.printed), \
        vm.printed[-6:]
    assert [d[1] for _, d in live(vm, 'ATTRIB')] == \
        ['A', 'B', '17', '23', '24']
    print("ok  ABPCREATE a number made earlier in the same run is refused")


def test_abpcreate_patterns_the_next_point_on_the_last():
    """A created point is a survey point like any other, so it is a
    pattern for the next one - and the blank attribute stays blank."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    rich_pt(vm, P17[0], P17[1], 17)
    run(vm, 'c:ABPCREATE',
        [200.0, 180.0, '23', 202.0, 182.0, '24', None], 'chain')
    ins = live(vm, 'INSERT', 'SURVEY-PTS')
    assert len(ins) == 3, ins
    for _, d in ins[1:]:
        assert d[41] == 2.0 and d[62] == 3 and d[6] == 'HIDDEN', d
    assert [d[1] for _, d in live(vm, 'ATTRIB')] == \
        ['A', 'B', '17', '104.25', '23', '', '24', ''], \
        [d[1] for _, d in live(vm, 'ATTRIB')]
    print("ok  ABPCREATE the point it just made patterns the next one")


def test_abpcreate_the_side_is_read_from_the_mean():
    """Points either side of the A-B line still name a side; a survey
    whose mean lands ON the line does not, and that one is asked."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    ab_pt(vm, 120.0, 300.0, 17)
    ab_pt(vm, 120.0, -20.0, 18)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'straddle')
    assert live(vm, 'INSERT')[-1][1][10][1] > 0, live(vm, 'INSERT')[-1][1]
    assert not any('does not say which side' in m for m in vm.printed)

    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    ab_pt(vm, 120.0, 200.0, 17)
    ab_pt(vm, 120.0, -200.0, 18)          # the mean is dead on the line
    run(vm, 'c:ABPCREATE',
        [200.0, 180.0, (120.0, -150.0, 0.0), '23', None], 'on the line')
    assert any('does not say which side' in m for m in vm.printed), \
        vm.printed[-6:]
    assert live(vm, 'INSERT')[-1][1][10][1] < 0
    print("ok  ABPCREATE the field side is the mean of the points plotted")


def test_abpcreate_clicks_stakes_the_drawing_does_not_name():
    """The stakes come first, the same way they do for the other two -
    found by name, or clicked once per run, with Back at B re-asking A
    because A was clicked rather than found."""
    vm = newvm()
    ab_pt(vm, P17[0], P17[1], 17)                 # one point, no stakes
    run(vm, 'c:ABPCREATE',
        [(A[0], A[1], 0.0), 'Back',               # B -> back to A
         (A[0], A[1], 0.0), (B[0], B[1], 0.0),
         200.0, 180.0, '23', None], 'clicked stakes')
    assert any('Stepping back one stake' in m for m in vm.printed), \
        vm.printed[-6:]
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == pt3(P200)
    print("ok  ABPCREATE clicks stakes the drawing does not name")


def test_abpcreate_back_at_the_side_click():
    """The side is the question after the B reading, so Back there is
    the B reading again."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    run(vm, 'c:ABPCREATE',
        [200.0, 180.0, 'Back', 180.0, (120.0, 200.0, 0.0), '1', None],
        'side back')
    assert len([q for q, _ in vm.prompts if 'B to the new point' in q]) == 2
    assert pt3(live(vm, 'INSERT')[-1][1][10]) == pt3(P200)
    print("ok  ABPCREATE Back at the side click re-asks the B reading")


def test_abpcreate_will_not_name_a_point_after_a_stake():
    """The stakes are survey points like any other to the lookup, so
    naming a new point after one is refused as the duplicate it is -
    which matters, because the ties are measured FROM them."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, 'A', '23', None], 'stake name')
    assert any('already in the drawing' in m for m in vm.printed), \
        vm.printed[-4:]
    assert [d[1] for _, d in live(vm, 'ATTRIB')] == ['A', 'B', '17', '23']
    print("ok  ABPCREATE refuses to name a new point after a stake")


def test_abpcreate_says_nothing_created_rather_than_nothing_dimensioned():
    """A run of ABPCREATE that ends without a point has not failed to
    dimension anything - it has failed to create something."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [None], 'empty run')
    assert any('no point created' in m for m in vm.printed), vm.printed[-3:]
    assert not any('nothing dimensioned' in m for m in vm.printed)
    print("ok  ABPCREATE reports an empty run in its own terms")


def test_abpcreate_a_reading_shorter_than_its_own_label():
    """An inward fan needs room between the arc and the stake for the
    text.  A reading no longer than the label has none, and the spacing
    that would keep the spokes apart at the stake would fling them right
    round the circle - so that fan goes outward instead."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [62.0, 62.0, 'None', None], 'short arcs')
    spots = vm.loads("(abf:create-spots '(0.0 0.0) '(240.0 0.0) 62.0 62.0 "
                     "(abf:create-candidates '(0.0 0.0) '(240.0 0.0) "
                     "62.0 62.0 (abf:field-ref '(0.0 0.0) '(240.0 0.0) "
                     "(abf:collect-points))))")
    assert spots, 'expected a fan to lay out'
    for s in spots:
        ctr = A if s[0].endswith('B') else B
        assert math.hypot(s[1][0] - ctr[0], s[1][1] - ctr[1]) > 62.0, s
    print("ok  ABPCREATE a fan with no room inside its arc hangs outside it")


# ---- more than one AB line on the sheet --------------------------------
# Two surveys merged onto one drawing: each brings its own A and B, and
# each numbers its points from 1, so "1" names two different places.  A2
# and B2 stand 20' apart the same way A and B do, a hundred feet east.

A2 = (1200.0, 0.0)
B2 = (1440.0, 0.0)
L1P1 = (120.0, 100.0)            # the first survey's Pt.1
L2P1 = (1320.0, 150.0)           # the second survey's, off ITS stakes
L1P2 = (60.0, 140.0)
L2P2 = (1260.0, 190.0)


def two_surveys(vm, seconds=True):
    """One sheet, two surveys: A/B/Pt.1/Pt.2 twice over."""
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    ab_pt(vm, L1P1[0], L1P1[1], 1)
    ab_pt(vm, L1P2[0], L1P2[1], 2)
    if seconds:
        ab_pt(vm, A2[0], A2[1], 'A')
        ab_pt(vm, B2[0], B2[1], 'B')
        ab_pt(vm, L2P1[0], L2P1[1], 1)
        ab_pt(vm, L2P2[0], L2P2[1], 2)


def tie_ends(vm):
    """The two ends of every dimension drawn, rounded."""
    return [(pt3(d[13]), pt3(d[14])) for d in dims(vm)]


def test_two_ab_lines_are_found_and_labelled():
    """Two As and two Bs make two lines, paired shortest tie first and
    labelled in the order their A stakes appear in the drawing."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABFIND', ['1', 'L1', 'No', None], 'lines')
    assert any('2 AB lines on this sheet' in m for m in vm.printed), \
        vm.printed[:6]
    # both Pt.1s ringed, on the throwaway layer, one label each
    rings = [d for d in ever(vm, 'CIRCLE', 'ABMOVE-POINTS')
             if d.get(40) == 9.0]
    assert [pt3(d[10]) for d in rings] == [pt3(L1P1), pt3(L2P1)], rings
    assert [d.get(1) for d in ever(vm, 'TEXT', 'ABMOVE-POINTS')] \
        == ['L1', 'L2']
    # and the scaffolding is gone again when the round ends
    assert not live(vm, 'CIRCLE', 'ABMOVE-POINTS')
    assert not live(vm, 'TEXT', 'ABMOVE-POINTS')
    print("ok  two AB lines are paired, labelled L1/L2 and ringed")


def test_the_label_picks_which_pt1_is_meant():
    """The answer settles BOTH which point is meant and which stakes the
    ties are measured from."""
    for tag, pt, stakes in (('L1', L1P1, (A, B)), ('L2', L2P1, (A2, B2))):
        vm = newvm()
        two_surveys(vm)
        run(vm, 'c:ABFIND', ['1', tag, 'No', None], tag)
        assert tie_ends(vm) == [(pt3(stakes[0]), pt3(pt)),
                                (pt3(stakes[1]), pt3(pt))], tie_ends(vm)
    print("ok  the label names the point AND the stakes it is tied to")


def test_a_click_picks_the_duplicate_without_a_label():
    """A click is never ambiguous - it names the point it landed on."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABFIND', ['1', list(L2P1) + [0.0], 'No', None], 'click')
    assert tie_ends(vm) == [(pt3(A2), pt3(L2P1)), (pt3(B2), pt3(L2P1))], \
        tie_ends(vm)
    print("ok  a click on one of the ringed points takes that one")


def test_the_ab_line_is_assumed_from_then_on():
    """Once a line is settled the run stays on it: the next doubled
    number is resolved from it and only reported."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABFIND', ['1', 'L2', 'No', '2', 'No', None], 'stays')
    assert any('the one on L2 taken' in m for m in vm.printed), vm.printed
    assert tie_ends(vm)[2:] == [(pt3(A2), pt3(L2P2)),
                                (pt3(B2), pt3(L2P2))], tie_ends(vm)
    # only the FIRST number was asked about
    asked = [q for q, _ in vm.prompts if 'Which AB line' in q]
    assert len(asked) == 1, asked
    print("ok  the AB line settled by the first point stands for the run")


def test_a_number_only_one_point_carries_is_not_asked_about():
    """"if theres only one point with the name provided, proceed
    normally" - the line is read off it and reported, nothing is asked."""
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, 60.0, 160.0, 7)                    # on the first survey
    run(vm, 'c:ABFIND', ['7', 'No', None], 'unique')
    assert not [q for q, _ in vm.prompts if 'Which AB line' in q], vm.prompts
    assert any('On AB line L1' in m for m in vm.printed), vm.printed
    assert tie_ends(vm) == [(pt3(A), (60.0, 160.0)),
                            (pt3(B), (60.0, 160.0))], tie_ends(vm)
    print("ok  a number only one point carries settles the line unasked")


def test_one_ab_line_asks_nothing_at_all():
    """"if theres only one AB line ... proceed normally" - a sheet with
    one pair of stakes never sees any of it."""
    vm = newvm()
    two_surveys(vm, seconds=False)
    run(vm, 'c:ABFIND', ['1', 'No', None], 'one line')
    assert not [m for m in vm.printed if 'AB line' in m], vm.printed
    assert tie_ends(vm) == [(pt3(A), pt3(L1P1)), (pt3(B), pt3(L1P1))]
    print("ok  one AB line is not mentioned, let alone asked about")


def test_abpcreate_asks_off_the_lines_themselves():
    """There is no point to read the line off yet, so the lines are what
    is picked between: both stakes ringed and the tie between them."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABPCREATE', ['L2', 160.0, 160.0, '9', None], 'create')
    assert [d.get(1) for d in ever(vm, 'TEXT', 'ABMOVE-POINTS')][:2] \
        == ['L1', 'L2']
    # the dashed tie of each line, and the four stake rings
    assert len([d for d in ever(vm, 'LINE', 'ABMOVE-POINTS')]) == 2
    assert len([d for d in ever(vm, 'CIRCLE', 'ABMOVE-POINTS')
                if d.get(40) == 9.0]) == 4
    # and the point it plotted is tied to the line that was chosen
    assert [e[0] for e in tie_ends(vm)] == [pt3(A2), pt3(B2)], tie_ends(vm)
    print("ok  ABPCREATE picks between the AB lines themselves")


def test_abfind_creating_a_point_asks_the_line_first():
    """A number that names no point has no line to read off either."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABFIND', ['23', 'Yes', 'L2', 160.0, 160.0, '23', None],
        'create')
    assert [e[0] for e in tie_ends(vm)] == [pt3(A2), pt3(B2)], tie_ends(vm)
    assert [d[1] for _, d in live(vm, 'ATTRIB')][-1] == '23'
    print("ok  creating a point from ABFIND asks which AB line first")


def test_back_and_enter_at_the_line_pick():
    """Back re-asks the number it came from; Enter takes no line and
    plots nothing."""
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, 60.0, 160.0, 7)
    run(vm, 'c:ABFIND', ['23', 'Yes', 'Back', '7', 'No', None], 'back')
    assert any('Back to the point number' in m for m in vm.printed)
    assert len(dims(vm)) == 2, dims(vm)

    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABPCREATE', [None], 'enter')
    assert any('No AB line taken' in m for m in vm.printed), vm.printed
    assert not dims(vm)
    print("ok  Back and Enter at the AB line pick")


def test_back_and_enter_at_the_duplicate_pick():
    """Back re-asks the number - that is the question in front of it -
    and a declined pick is NOT read as a number that names nothing."""
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, 60.0, 160.0, 7)
    run(vm, 'c:ABFIND', ['1', 'b', '7', 'No', None], 'back')
    assert any('Back to the point number' in m for m in vm.printed), vm.printed
    assert tie_ends(vm) == [(pt3(A), (60.0, 160.0)),
                            (pt3(B), (60.0, 160.0))], tie_ends(vm)

    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABFIND', ['1', None, None], 'none')
    assert any('None taken' in m for m in vm.printed), vm.printed
    # and the offer to CREATE is not raised: the number names two points
    assert not [q for q, _ in vm.prompts if 'Create Pt.' in q], vm.prompts
    assert not dims(vm)
    print("ok  Back and Enter at the duplicate pick")


def test_abmove_on_a_two_line_sheet():
    """ABMOVE asks the same question, and moves the point on the line it
    was told about."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABMOVE', ['1', 'L2', 'None'], 'abmove')
    assert any('Which AB line is Pt.1 on' in q for q, _ in vm.prompts), \
        vm.prompts
    assert tie_ends(vm) == [(pt3(A2), pt3(L2P1)), (pt3(B2), pt3(L2P1))], \
        tie_ends(vm)
    print("ok  ABMOVE settles its one point on the line it was given")


def test_two_points_numbered_the_same_on_one_line():
    """A drawing fault rather than a second survey, and still
    answerable: the second candidate takes a letter after the label."""
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, 100.0, 120.0, 1)                # a THIRD Pt.1, on line 1
    run(vm, 'c:ABFIND', ['1', 'L1b', 'No', None], 'same line')
    # labelled in drawing order, so the third Pt.1 is the one that has
    # to take the letter
    assert [d.get(1) for d in ever(vm, 'TEXT', 'ABMOVE-POINTS')] \
        == ['L1', 'L2', 'L1b'], ever(vm, 'TEXT', 'ABMOVE-POINTS')
    assert tie_ends(vm) == [(pt3(A), (100.0, 120.0)),
                            (pt3(B), (100.0, 120.0))], tie_ends(vm)
    print("ok  two points numbered the same on one line take L1/L1b")


def test_a_spare_stake_is_reported():
    """Three As and two Bs: one survey has no pair to measure from, and
    the run says so rather than quietly pairing it with someone else's."""
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, 2400.0, 0.0, 'A')
    run(vm, 'c:ABFIND', ['1', 'L1', 'No', None], 'spare')
    assert any('pair with nothing' in m for m in vm.printed), vm.printed
    print("ok  a stake that pairs with nothing is reported")


def test_naming_a_stake_is_still_refused():
    """"A" names two stakes on a two-line sheet, so it is asked about
    like any other doubled number - and then refused, because the ties
    are measured FROM a stake."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABFIND', ['A', 'L2', None], 'stake')
    assert any('IS a stake' in m for m in vm.printed), vm.printed
    assert not dims(vm)
    print("ok  a stake named on a two-line sheet is asked about, then refused")


def test_one_stake_named_and_one_clicked_says_nothing_extra():
    """A drawing that names one stake and not the other is asked to
    click the missing one - which says it better than a spare-stake
    count would, so the count is not printed."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, L1P1[0], L1P1[1], 1)
    run(vm, 'c:ABFIND', [list(B) + [0.0], '1', 'No', None], 'half named')
    assert not [m for m in vm.printed if 'pair with nothing' in m], vm.printed
    assert len(dims(vm)) == 2, dims(vm)
    print("ok  a half-named pair is clicked, with no spare-stake count")


def test_the_field_side_is_read_off_one_line_only():
    """A point created on L1 must not be put on the wrong side of it by
    the other survey's points, which sit wherever they sit."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, B[0], B[1], 'B')
    ab_pt(vm, 120.0, 100.0, 1)                 # L1's survey: NORTH
    ab_pt(vm, A2[0], A2[1], 'A')
    ab_pt(vm, B2[0], B2[1], 'B')
    ab_pt(vm, 1320.0, -400.0, 1)               # L2's: well SOUTH
    ab_pt(vm, 1260.0, -440.0, 2)
    run(vm, 'c:ABPCREATE', ['L1', 160.0, 160.0, '9', None], 'side')
    made = pt3(live(vm, 'INSERT')[-1][1][10])
    assert made[1] > 0.0, made        # north, where L1's own survey is
    print("ok  the field side is read off the chosen line's own points")


def test_back_at_the_first_reading_re_asks_the_ab_line():
    """The two features met here: ABPCREATE opens on the AB line when
    the sheet carries more than one, so the line - not "already at the
    first point" - is what stands in front of the first reading.  It
    holds whichever way the run got there, and once every created round
    has been taken back the line is askable again."""
    def sheet():
        vm = newvm()
        for x, nm in ((0.0, 'A'), (240.0, 'B'), (1200.0, 'A'),
                      (1440.0, 'B')):
            ab_pt(vm, x, 0.0, nm)
        ab_pt(vm, 120.0, 100.0, 1)
        ab_pt(vm, 1320.0, 150.0, 1)
        return vm

    vm = sheet()
    run(vm, 'c:ABPCREATE', ['L1', 'Back', 'L2', 200.0, 180.0, '9', None],
        'back to the line')
    assert any('Back to the AB line' in m for m in vm.printed), \
        vm.printed[-6:]
    assert len([q for q, _ in vm.prompts if 'Which AB line' in q]) == 2
    got = live(vm, 'INSERT')[-1][1][10]
    assert near(math.hypot(got[0] - 1200.0, got[1]), 200.0), got

    # and after a round, Back undoes the round first and only then the
    # line question comes back
    vm = sheet()
    run(vm, 'c:ABPCREATE',
        ['L1', 200.0, 180.0, '9', 'Back', 'Back', 'L1', 200.0, 180.0,
         '9', None], 'round first, then the line')
    assert any('Stepping back one point' in m for m in vm.printed)
    assert any('Back to the AB line' in m for m in vm.printed)
    assert len([q for q, _ in vm.prompts if 'Which AB line' in q]) == 2
    assert len(live(vm, 'INSERT')) == 7, live(vm, 'INSERT')

    # and the whole chain walks: ABFIND's number offers to create, the
    # line is asked, the reading is asked - and Back retraces all three
    vm = sheet()
    run(vm, 'c:ABFIND', ['9', 'Yes', 'L1', 'Back', 'Back', None],
        'the chain both ways')
    said = ' '.join(vm.printed)
    assert 'Back to the AB line' in said and 'Back to the point number' \
        in said, [m for m in vm.printed if 'Back to' in m]
    assert len(live(vm, 'INSERT')) == 6, live(vm, 'INSERT')
    print("ok  Back at the first reading re-asks the AB line, not nothing")


# ---- the AB lines: edge cases ------------------------------------------
# Each of these was a live defect once.  The comment on each says which.

def test_a_doubled_number_with_the_stakes_clicked():
    """A drawing that names NO stake still has a pair - the one just
    clicked - and a doubled number there has to be answerable off it.
    It used to ask abf:line-of a question with no lines to answer from
    and hand (distance ...) a nil stake: a hard crash."""
    vm = newvm()
    ab_pt(vm, L1P1[0], L1P1[1], 1)
    ab_pt(vm, L2P1[0], L2P1[1], 1)
    run(vm, 'c:ABFIND',
        [list(A) + [0.0], list(B) + [0.0], '1', 'L1b', 'No', None],
        'clicked stakes')
    # both ringed, and labelled off the ONE line the clicks make
    assert [d.get(1) for d in ever(vm, 'TEXT', 'ABMOVE-POINTS')] \
        == ['L1', 'L1b'], ever(vm, 'TEXT', 'ABMOVE-POINTS')
    assert tie_ends(vm) == [(pt3(A), pt3(L2P1)), (pt3(B), pt3(L2P1))], \
        tie_ends(vm)
    print("ok  a doubled number is answerable with the stakes clicked")


def test_a_point_on_another_line_moves_the_run_to_it():
    """Assuming the settled line is a CONVENIENCE.  Measuring from it
    when the point was taped off the other pair is the wrong answer the
    whole question exists to prevent - it drew Pt.9 a 106-foot tie off
    stakes nobody had a tape on."""
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, L2P2[0], L2P2[1], 9)          # only L2 carries a Pt.9
    run(vm, 'c:ABFIND', ['1', 'L1', 'No', '9', 'No', None], 'moves')
    assert any('is on AB line L2, not L1' in m for m in vm.printed), \
        vm.printed
    # Pt.1 off L1's stakes, Pt.9 off L2's
    assert tie_ends(vm) == [(pt3(A), pt3(L1P1)), (pt3(B), pt3(L1P1)),
                            (pt3(A2), pt3(L2P2)), (pt3(B2), pt3(L2P2))], \
        tie_ends(vm)
    print("ok  a point on another AB line moves the run to that line")


def test_a_click_on_another_line_moves_the_run_too():
    """A click is never asked about - but it still says which line."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABFIND',
        ['1', 'L1', 'No', list(L2P2) + [0.0], 'No', None], 'clicked move')
    assert any('is on AB line L2, not L1' in m for m in vm.printed), \
        vm.printed
    assert tie_ends(vm)[2:] == [(pt3(A2), pt3(L2P2)),
                                (pt3(B2), pt3(L2P2))], tie_ends(vm)
    print("ok  a clicked point on another AB line moves the run too")


def test_the_ties_measure_from_the_PAIRED_stake():
    """Three As and two Bs - or two As and one B - and abf:stake takes
    the FIRST A by name, which is not the A the pairing put with B.  The
    tie then measured 190 feet off a stake the pairing had rejected."""
    vm = newvm()
    ab_pt(vm, 2400.0, 0.0, 'A')              # first in the drawing, far
    ab_pt(vm, A[0], A[1], 'A')               # the one that goes with B
    ab_pt(vm, B[0], B[1], 'B')
    ab_pt(vm, L1P1[0], L1P1[1], 7)
    run(vm, 'c:ABFIND', ['7', 'No', None], 'paired stake')
    assert tie_ends(vm) == [(pt3(A), pt3(L1P1)), (pt3(B), pt3(L1P1))], \
        tie_ends(vm)
    assert any('pair with nothing' in m for m in vm.printed), vm.printed
    print("ok  the ties measure from the stake the pairing chose")


def test_a_doubled_stake_with_no_pair_is_reported():
    """Two As and no B at all: nothing can say which A is meant, so the
    first is taken - and said out loud, rather than every tie in the run
    quietly coming off the wrong stake."""
    vm = newvm()
    ab_pt(vm, 2400.0, 0.0, 'A')
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, L1P1[0], L1P1[1], 7)
    run(vm, 'c:ABFIND', [list(B) + [0.0], '7', 'No', None], 'two As')
    assert any('2 points are numbered "A"' in m and 'the first was taken'
               in m for m in vm.printed), vm.printed
    print("ok  a stake name used twice with no pair says the first was taken")


def test_a_stray_label_at_the_duplicate_pick_is_re_asked():
    """A typo must not cost the round and send the drafter back to the
    number - it re-asks with the rings still up, the way ABPCREATE's
    line pick always did."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABFIND', ['1', 'L9', 'L2', 'No', None], 'stray')
    assert any('is not one of the labels' in m for m in vm.printed), \
        vm.printed
    assert tie_ends(vm) == [(pt3(A2), pt3(L2P1)), (pt3(B2), pt3(L2P1))], \
        tie_ends(vm)
    # asked twice, and the number was never re-asked
    assert len([q for q, _ in vm.prompts if 'Which AB line' in q]) == 2
    assert len([q for q, _ in vm.prompts if 'type its number' in q]) == 2
    print("ok  a stray label at the duplicate pick is re-asked")


def test_a_stray_label_at_the_line_pick_is_re_asked():
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABPCREATE', ['Q1', 'L1', 160.0, 160.0, '9', None], 'stray')
    assert any('is not one of the labels' in m for m in vm.printed), \
        vm.printed
    assert [e[0] for e in tie_ends(vm)] == [pt3(A), pt3(B)], tie_ends(vm)
    print("ok  a stray label at the AB line pick is re-asked")


def test_a_click_along_a_tie_picks_that_line():
    """The lines are picked between by their TIE, not their stakes, so a
    click anywhere along one takes it."""
    vm = newvm()
    two_surveys(vm)
    mid = [(A2[0] + B2[0]) * 0.5 + 10.0, 3.0, 0.0]   # on L2's tie
    run(vm, 'c:ABPCREATE', [mid, 160.0, 160.0, '9', None], 'click tie')
    assert [e[0] for e in tie_ends(vm)] == [pt3(A2), pt3(B2)], tie_ends(vm)
    print("ok  a click anywhere along an AB line's tie picks that line")


def test_three_ab_lines():
    """Nothing in the pairing or the labelling caps out at two."""
    vm = newvm()
    for x in (0.0, 1200.0, 2400.0):
        ab_pt(vm, x, 0.0, 'A')
        ab_pt(vm, x + 240.0, 0.0, 'B')
        ab_pt(vm, x + 120.0, 100.0, 1)
    run(vm, 'c:ABFIND', ['1', 'L3', 'No', None], 'three')
    assert [d.get(1) for d in ever(vm, 'TEXT', 'ABMOVE-POINTS')] \
        == ['L1', 'L2', 'L3'], ever(vm, 'TEXT', 'ABMOVE-POINTS')
    assert tie_ends(vm) == [((2400.0, 0.0), (2520.0, 100.0)),
                            ((2640.0, 0.0), (2520.0, 100.0))], tie_ends(vm)
    print("ok  three AB lines pair, label and pick like two")


def test_the_pairing_does_not_depend_on_drawing_order():
    """Both As drawn before either B, and the Bs drawn in the other
    order: the pairing is by shortest tie, so it still comes out right -
    and the LABELS still run in A-stake drawing order."""
    vm = newvm()
    ab_pt(vm, A[0], A[1], 'A')
    ab_pt(vm, A2[0], A2[1], 'A')
    ab_pt(vm, B2[0], B2[1], 'B')             # the far B first
    ab_pt(vm, B[0], B[1], 'B')
    ab_pt(vm, L1P1[0], L1P1[1], 1)
    ab_pt(vm, L2P1[0], L2P1[1], 1)
    run(vm, 'c:ABFIND', ['1', 'L2', 'No', None], 'order')
    assert tie_ends(vm) == [(pt3(A2), pt3(L2P1)), (pt3(B2), pt3(L2P1))], \
        tie_ends(vm)
    print("ok  the pairing is by shortest tie, not by drawing order")


def test_abmove_moves_a_point_on_the_line_it_was_given():
    """The suggestions are swept off THAT line's stakes, and the moved
    point is tied back to them."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABMOVE', ['1', 'L2', '1B', None], 'abmove L2')
    assert [e[0] for e in tie_ends(vm)] == [pt3(A2), pt3(B2)], tie_ends(vm)
    assert [d[1] for _, d in live(vm, 'ATTRIB')][-1] == '1m'
    print("ok  ABMOVE moves its point off the stakes of the line given")


def test_abpcreate_keeps_the_line_for_every_round():
    """Asked once per run, not once per point."""
    vm = newvm()
    two_surveys(vm)
    run(vm, 'c:ABPCREATE',
        ['L2', 160.0, 160.0, '8', 170.0, 170.0, '9', None], 'two rounds')
    assert len([q for q, _ in vm.prompts if 'Which AB line' in q]) == 1
    assert all(e[0] in (pt3(A2), pt3(B2)) for e in tie_ends(vm)), \
        tie_ends(vm)
    print("ok  ABPCREATE asks the line once and keeps it for every round")


def test_back_undoes_a_round_that_moved_the_line():
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, L2P2[0], L2P2[1], 9)
    run(vm, 'c:ABFIND',
        ['1', 'L1', 'No', '9', 'No', 'b', '9', 'No', None], 'back')
    assert any('Stepping back one point' in m for m in vm.printed)
    assert tie_ends(vm) == [(pt3(A), pt3(L1P1)), (pt3(B), pt3(L1P1)),
                            (pt3(A2), pt3(L2P2)), (pt3(B2), pt3(L2P2))], \
        tie_ends(vm)
    print("ok  Back takes away a round that moved the run's AB line")


def test_none_of_them_is_on_only_when_it_is_true():
    """Two candidates on the SETTLED line say so through their own
    labels (L1, L1b); printing "none of them is on L1" beside a row
    labelled L1 is simply wrong."""
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, L1P1[0] + 1.0, L1P1[1] + 1.0, 1)   # a third Pt.1, on L1
    run(vm, 'c:ABFIND', ['1', 'L1', 'No', None], 'wording')
    assert not any('None of them is on' in m for m in vm.printed), \
        vm.printed
    # and where it IS true it is said
    vm = newvm()
    two_surveys(vm)
    ab_pt(vm, L1P1[0] + 1.0, L1P1[1] + 1.0, 7)
    ab_pt(vm, L2P2[0], L2P2[1], 3)
    ab_pt(vm, L2P2[0] + 1.0, L2P2[1] + 1.0, 3)
    run(vm, 'c:ABFIND', ['7', 'No', '3', 'L2b', 'No', None], 'wording 2')
    assert any('None of them is on L1' in m for m in vm.printed), vm.printed
    print("ok  \"none of them is on L1\" is printed only when it is true")


def test_the_ab_line_helpers_are_nil_safe():
    """Every one of them is reached on a drawing that makes no lines at
    all, so none may assume there is one."""
    vm = newvm()
    for form, want in (
            ('(abf:lines nil)', None),
            ('(abf:spare-stakes nil nil)', 0),
            ('(abf:line-of (list 0.0 0.0 0.0) nil)', None),
            ('(abf:on-line-p (list 0.0 0.0 0.0) nil nil)', None),
            ('(abf:line-pts nil nil nil)', None),
            ('(abf:dupe-tags nil nil)', None),
            ('(abf:line-by-tag "L1" nil)', None),
            ('(abf:dupe-by-tag "L1" nil)', None),
            ('(abf:tag-used-p "L1" nil)', None)):
        got = vm.loads(form)
        assert (got is NIL if want is None else got == want), (form, got)
    # two stakes on one spot make no line, and no line is not an error
    assert vm.loads('(abf:lines (list (list (list 0.0 0.0 0.0) "A" nil)'
                    '                 (list (list 0.0 0.0 0.0) "B" nil)))') \
        in (NIL, None)
    print("ok  every AB line helper answers on a drawing with no lines")


# ---- the note on a created point ---------------------------------------
# A point that was plotted rather than surveyed is not the same thing as
# one the field sheet placed, so the sheet says which it is looking at -
# the way it does for a point that moved.

def test_a_created_point_is_noted_like_a_moved_one():
    """Readings that crossed as they were written down are recorded as
    they stand, on the same layer and at the same height as the note a
    move leaves."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'clean note')
    notes = [d for _, d in live(vm, 'TEXT', 'FGStep')]
    assert len(notes) == 1, notes
    assert notes[0][1] == '- Created Pt.23 - A 16\'-8", B 15\'-0"', notes[0][1]
    assert notes[0][40] == 6.0, notes[0]          # abf:*note-hgt*
    # beside the point, the way BPCALLOUT tucks its callout
    assert pt3(notes[0][10]) == pt3((P200[0] + 10.0, P200[1] - 10.0))
    print("ok  a created point is noted on FGStep, beside itself")


def test_the_note_says_which_tape_was_held_and_which_changed():
    """The pair could not cross, so one reading was held and the other
    changed to make it - which is the half worth writing out."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [SHORT[0], SHORT[1], '7A', '23', None], 'held')
    assert texts(vm, 'FGStep') == \
        ['- Created Pt.23 - B 8\'-4" held, A from 8\'-4" to 15\'-4"'], \
        texts(vm, 'FGStep')
    # the tape named as held is the one the tag does NOT name, and the
    # reading it was held at is the one that was typed
    got = sugs_for(vm, SHORT[0], SHORT[1])['7A']
    assert got[1] == 'B' and got[2] == 'A', got[1:3]
    print("ok  the note names the tape held, and the one from-and-to")


def test_a_clean_round_after_a_changed_one_is_noted_clean():
    """The candidate taken belongs to ONE pair of readings.  A later
    round whose readings cross unaided must not be written up as though
    a tape had been held for it."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE',
        [SHORT[0], SHORT[1], '7A', '23', 200.0, 180.0, '24', None],
        'changed then clean')
    assert texts(vm, 'FGStep') == \
        ['- Created Pt.23 - B 8\'-4" held, A from 8\'-4" to 15\'-4"',
         '- Created Pt.24 - A 16\'-8", B 15\'-0"'], texts(vm, 'FGStep')
    print("ok  a clean round after a changed one is noted clean")


def test_back_takes_the_created_note_with_the_round():
    """The note is part of the round, so Back takes it away with the
    point and its ties."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', 'Back', None], 'back note')
    assert texts(vm, 'FGStep') == [], texts(vm, 'FGStep')
    assert len(live(vm, 'INSERT')) == 3, live(vm, 'INSERT')
    print("ok  Back takes the created point's note away with the round")


def test_abfind_and_abmove_note_the_points_they_create():
    """The note belongs to the creation, not to the command that asked
    for it."""
    for cmd, script in (('c:ABFIND', ['23', 'Yes', 200.0, 180.0, '', None]),
                        ('c:ABMOVE', ['23', 'Yes', 200.0, 180.0, ''])):
        vm = newvm()
        survey(vm)
        run(vm, cmd, script, cmd + ' note')
        assert texts(vm, 'FGStep') == \
            ['- Created Pt.23 - A 16\'-8", B 15\'-0"'], (cmd, texts(vm, 'FGStep'))
    print("ok  ABFIND and ABMOVE note the points they create")


def test_every_note_leads_with_the_bullet():
    """abf:*note-prefix*.  A run that moves or creates several points
    leaves a column of notes on one layer, and the bullet is what makes
    that column read as a list when the sheet is laid out later.  It
    goes on in abf:note, so a note worded anywhere carries it - which is
    what this checks, by driving all three wordings through one run and
    then emptying the knob."""
    vm = newvm()
    survey(vm)
    run(vm, 'c:ABPCREATE',
        [SHORT[0], SHORT[1], '7A', '23', 200.0, 180.0, '24', None],
        'both created wordings')
    run(vm, 'c:ABMOVE', ['17', 'R1B', None], 'and a moved one')
    got = texts(vm, 'FGStep')
    assert len(got) == 3, got
    assert all(t.startswith('- ') for t in got), got

    # the knob is the whole of it: emptied, the notes come out bare
    vm = newvm()
    survey(vm)
    vm.loads('(setq abf:*note-prefix* "")')
    run(vm, 'c:ABPCREATE', [200.0, 180.0, '23', None], 'bare')
    assert texts(vm, 'FGStep') == ['Created Pt.23 - A 16\'-8", B 15\'-0"'], \
        texts(vm, 'FGStep')
    print("ok  every note leads with abf:*note-prefix*, moved and created")


TESTS = [v for k, v in sorted(globals().items()) if k.startswith('test_')]

if __name__ == '__main__':
    for t in TESTS:
        t()
    print(f"\n{len(TESTS)} ABFIND/ABMOVE test(s) passed.")
