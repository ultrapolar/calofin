"""NORMIESTEP marks its step corners the way the sample sheet draws them.

STANDARDS.md section 2: the mark is a small circle on the corner point
with a RADIUS DIMENSION on that circle, its measurement replaced by
what the mark says -- `90%%d` where the corner really is one, a BOXED
`?` with a `Not Given` note on a leader where the sheet never said.
One answer covers both corners of a run, so one mark carries it and
says ` Typ.`; a mode with a single treated corner marks that one alone.

A STEP's corners take the SMALLER of the two sizes the sample carries,
so the mark is drawn in `*cs-mark-dimstyle*` ("STANDARD INCHES") and
the style the drawing was in comes back afterwards.

Asserted here:

  * a square run gets ONE `90%%d Typ.` mark, on a corner of its last
    step, hung on a circle that really does sit on that corner
  * a corner nobody recorded gets the boxed `?` and its `Not Given`
    note instead -- and DIMGAP, which is what draws the box, is handed
    straight back
  * the mark is drawn in the small style, and the style is restored
  * a corner that is NOT 90 -- a run off a wall that leans -- is left
    unmarked rather than told a lie, but `?` is still drawn there
  * a Radius or Cut corner is dimensioned, not marked

Run against the grouped tier with:
    CALOFIN_LISP_ROOT=shared python3 tests/test_step_corner_mark.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, Ent, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'cornerstp', 'NORMIESTEP.lsp')

WID = 60.0                      # step width
TREADS = (24.0, 24.0)           # two of them, so the run is 48" deep
BASE_END = (200.0, 0.0)         # the wall the steps come off, along +X
SIDE = (100.0, 50.0)            # the pick that says which way they go
#: the corner-mode second wall: square to the base, or leaning away
SQUARE_WALL = (0.0, 200.0)
LEANING_WALL = (100.0, 200.0)

#: a drawing scaled the way the shop's are: DIMTXT 1/8" at 1/4"=1'
TXT, SCALE = 0.125, 48.0
TXTH = TXT * SCALE              # 6" of text -> a 3" mark circle
MARKR = 0.5 * TXTH


def run(treatment=("Square",), wall=None, styles=('STANDARD INCHES',),
        setup=(), treads=TREADS, label="run"):
    """One NORMIESTEP run.  WALL None is a centered run off one line
    (LINE mode); a wall makes the corner the recess sits outside of."""
    vm = VM()
    vm.load(LSP)                        # CALOFIN_LISP_ROOT picks the tier
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = TXT, SCALE
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 %r %r 0.0)))' % BASE_END)
    if wall:
        vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
                 ' (list 11 %r %r 0.0)))' % wall)
    picked = list(vm.entities)
    for form in setup:
        vm.loads(form)
    pick = (100.0, 0.0) if wall else SIDE
    script = ([None, picked, pick, WID] + list(treatment)
              + ["No"] + list(treads) + [None, "No"])
    try:
        vm.run('c:NORMIESTEP', script)
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    vm.picked = picked
    return vm


def run_u(arms, treatment=("Square",), treads=TREADS, label="u"):
    """A U already drawn -- two arms and the base between them -- with
    the treads filled in.  ARMS is ((a1, a2), base, (b1, b2))."""
    vm = VM()
    vm.load(LSP)
    vm.tables['DIMSTYLE'].add('STANDARD INCHES')
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = TXT, SCALE
    for a, b in arms:
        vm.loads('(entmake (list (cons 0 "LINE") (list 10 %r %r 0.0)'
                 ' (list 11 %r %r 0.0)))' % (a[0], a[1], b[0], b[1]))
    picked = list(vm.entities)
    try:
        vm.run('c:NORMIESTEP',
               [None, picked] + list(treatment) + ["No"] + list(treads)
               + [None, "No"])
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    vm.picked = picked
    return vm


def entities(vm, etype, skip_picked=True):
    out = []
    for e in vm.entities:
        if e in vm.deleted or (skip_picked and e in getattr(vm, 'picked', ())):
            continue
        d = {}
        for g in vm.entdata.get(e, []):
            if isinstance(g, Dot):
                d.setdefault(g.a, g.b)
            elif isinstance(g, list) and g:
                d.setdefault(g[0], g[1] if len(g) == 2 else g[1:])
        if d.get(0) == etype:
            out.append(d)
    return out


def override(call):
    """The text a dimension command was given after "_T", or None."""
    for i, x in enumerate(call[:-1]):
        if isinstance(x, str) and x.upper() == '_T' \
                and isinstance(call[i + 1], str):
            return call[i + 1]
    return None


def marks(vm):
    """What each corner mark says, in the order they were drawn."""
    return [override(c) for c in vm.commands
            if c and c[0] == '_.DIMRADIUS'
            and str(override(c)).startswith(('90%%d', '?'))]


def markcalls(vm):
    return [c for c in vm.commands if c and c[0] == '_.DIMRADIUS']


def notes(vm, text='Not Given'):
    return [c for c in vm.commands
            if c and c[0] == '_.LEADER' and c[-2] == text]


def picked_on(call):
    """The point the mark's circle was picked at."""
    for x in call[1:]:
        if isinstance(x, list) and len(x) == 2 and isinstance(x[0], Ent):
            return x[1]
    return None


def location(call):
    """Where the mark's text was dragged to: the last point of the call."""
    return [x for x in call if isinstance(x, list) and len(x) >= 2
            and not isinstance(x[0], Ent)][-1]


def test_a_square_run_is_marked_once_on_its_last_step():
    """Both corners of the run share the one answer, so one mark
    carries it and says Typ. -- and it sits on a corner of the last
    step, where a centered run's treatment goes."""
    vm = run(("Square",), label="line/square")
    assert marks(vm) == ['90%%d Typ.'], marks(vm)
    circles = entities(vm, 'CIRCLE')
    assert len(circles) == 1, circles
    # sp is the middle of the wall, the run is 48 deep and 60 wide, so
    # the last step's corners are at (130, 48) and (70, 48)
    cen = tuple(circles[0][10][:2])
    assert math.dist(cen, (130.0, 48.0)) < 1e-6, cen
    assert abs(circles[0][40] - MARKR) < 1e-9, (circles[0][40], MARKR)
    # ... and nothing is noted: a square corner has nothing to explain
    assert not notes(vm), notes(vm)
    print("a square run: one 90 mark, Typ., on the last step's corner")


def test_the_mark_hangs_off_the_circle_and_leads_away_from_the_step():
    vm = run(("Square",), label="line/geometry")
    call = markcalls(vm)[0]
    cen = tuple(entities(vm, 'CIRCLE')[0][10][:2])
    on, loc = picked_on(call), location(call)
    assert on is not None and loc is not None, call
    # picked ON the circle, so the dimension arrow lands on it
    assert abs(math.dist(tuple(on[:2]), cen) - MARKR) < 1e-6, (on, cen)
    # and dragged out along the corner's own diagonal, away from the run
    d = math.dist(tuple(loc[:2]), cen)
    assert abs(d - 6.7 * MARKR) < 1e-6, (d, 6.7 * MARKR)
    assert loc[0] > cen[0] and loc[1] > cen[1], (loc, cen)
    print("the mark is a dim ON the mark circle, led out of the step")


def test_the_step_mark_is_the_smaller_style_and_gives_it_back():
    """A step's corners are a detail inside somebody else's plan, so
    the mark reads one size down -- and the drawing is handed back the
    style it was in."""
    vm = run(("Square",), label="line/style")
    assert vm.dimstyle_log[:1] == ['STANDARD INCHES'], vm.dimstyle_log
    dims = [d for d in entities(vm, 'DIMENSION') if d.get(1) == '90%%d Typ.']
    assert len(dims) == 1, dims
    assert dims[0].get(3) == 'STANDARD INCHES', dims[0].get(3)
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars['DIMSTYLE']
    # a drawing without the style still gets its mark, in the current one
    vm = run(("Square",), styles=(), label="line/no-style")
    assert marks(vm) == ['90%%d Typ.'], marks(vm)
    assert vm.dimstyle_log == [], vm.dimstyle_log
    print("the mark is drawn small, and the style comes back")


def test_a_corner_nobody_gave_is_a_boxed_question_with_its_note():
    vm = run(("NotGiven",), label="line/notgiven")
    assert marks(vm) == ['? Typ.'], marks(vm)
    boxed = [d for d in entities(vm, 'DIMENSION') if d.get(1) == '? Typ.']
    assert len(boxed) == 1, boxed
    assert boxed[0].get(147, 0) < 0, "the ? has to come out in a box"
    # the note is the leader's own annotation, hung off that box
    assert len(notes(vm)) == 1, [c for c in vm.commands if c[0] == '_.LEADER']
    start, end = notes(vm)[0][2], notes(vm)[0][4]
    cen = tuple(entities(vm, 'CIRCLE')[0][10][:2])
    assert math.dist(tuple(start[:2]), cen) < math.dist(tuple(end[:2]), cen), \
        (start, end)
    # the gap that drew the box is handed straight back
    assert vm.sysvars['DIMGAP'] > 0, vm.sysvars['DIMGAP']
    # and the old plain-text note is gone: the mark says it now
    assert not [t for t in entities(vm, 'TEXT')
                if 'NOT GIVEN' in str(t.get(1, '')).upper()], \
        entities(vm, 'TEXT')
    print("a corner never given: a boxed ? and its Not Given note")


def test_a_corner_that_is_not_90_is_not_marked_90():
    """The mark ASSERTS a right angle.  A recess off a wall that leans
    has a back corner that is not one, so it goes unmarked -- but "?"
    asserts nothing about the angle and is drawn there all the same."""
    square = run(("Square",), wall=SQUARE_WALL, label="corner/square")
    assert marks(square) == ['90%%d'], marks(square)   # one corner: no Typ.
    leaning = run(("Square",), wall=LEANING_WALL, label="corner/leaning")
    assert marks(leaning) == [], marks(leaning)
    assert not entities(leaning, 'CIRCLE'), "no mark means no circle either"
    never = run(("NotGiven",), wall=LEANING_WALL, label="corner/leaning-ng")
    assert marks(never) == ['?'], marks(never)
    assert len(notes(never)) == 1, notes(never)
    print("90 only where the corner really is 90; ? at any angle")


def test_a_u_is_marked_at_the_joint_where_its_arm_meets_the_base():
    """A U's back corners are where the arms meet the base, and they
    are at whatever angle the outline was drawn -- so the same rule
    applies there: marked 90 only when they really are."""
    square = run_u((((-80.0, 150.0), (-80.0, 0.0)),
                    ((-80.0, 0.0), (80.0, 0.0)),
                    ((80.0, 0.0), (80.0, 150.0))), label="u/square")
    assert marks(square) == ['90%%d Typ.'], marks(square)
    cen = tuple(entities(square, 'CIRCLE')[0][10][:2])
    assert min(math.dist(cen, j) for j in ((-80.0, 0.0), (80.0, 0.0))) < 1e-6, \
        cen
    # the mark leads AWAY from the U, which opens upward from the base
    assert location(markcalls(square)[0])[1] < 0.0, markcalls(square)[0]
    # splayed arms: neither joint is square, so neither is marked
    splayed = run_u((((-140.0, 150.0), (-80.0, 0.0)),
                     ((-80.0, 0.0), (80.0, 0.0)),
                     ((140.0, 150.0), (80.0, 0.0))), label="u/splayed")
    assert marks(splayed) == [], marks(splayed)
    print("a U is marked at its joints, and only where they are square")


def test_a_treated_corner_is_dimensioned_rather_than_marked():
    for treatment in (("Radius", 9.0), ("Cut", "Offset", 9.0)):
        vm = run(treatment, label="line/%s" % treatment[0])
        assert marks(vm) == [], (treatment, marks(vm))
        assert not entities(vm, 'CIRCLE'), treatment
        assert not notes(vm), treatment
    print("a radius or a cut is drawn, not marked")


def main():
    test_a_square_run_is_marked_once_on_its_last_step()
    test_the_mark_hangs_off_the_circle_and_leads_away_from_the_step()
    test_the_step_mark_is_the_smaller_style_and_gives_it_back()
    test_a_corner_nobody_gave_is_a_boxed_question_with_its_note()
    test_a_corner_that_is_not_90_is_not_marked_90()
    test_a_u_is_marked_at_the_joint_where_its_arm_meets_the_base()
    test_a_treated_corner_is_dimensioned_rather_than_marked()
    print("all step corner mark tests passed")


if __name__ == '__main__':
    main()
