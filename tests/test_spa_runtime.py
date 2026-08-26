"""Runtime smoke tests: load the REAL SPA.LSP into the AutoLISP VM and
drive c:SPA end-to-end with scripted answers, one scenario per shape,
plus Back-stress runs.  A regression that would die at the AutoCAD
command line -- an (if ...) with too many arguments, an unbound
function, a SPA-BACK symbol reaching (+ ...) -- dies here instead.

Script values: numbers answer distance prompts, strings answer keyword
prompts (or NA/Back), None is Enter, tuples are picked points.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'spa', 'SPA.LSP')


def run(script, label):
    vm = VM()
    vm.load(LSP)
    try:
        vm.run('c:SPA', script)
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def drawn(vm, etype, layer=None):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for p in vm.entdata[e]:
            if isinstance(p, Dot):
                d.setdefault(p.a, p.b)
            elif isinstance(p, list) and p:
                d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
        if d.get(0) == etype and (layer is None or d.get(8) == layer):
            out.append(d)
    return out


def outline(vm, layer):
    """The single closed polyline that bounds an outline."""
    pls = drawn(vm, 'LWPOLYLINE', layer)
    return pls[0] if len(pls) == 1 else None


def extents(pl):
    """(width height) of a polyline's vertices."""
    xs = [p[0] for p in pl[10]] if isinstance(pl[10][0], list) else None
    return xs


def plverts(vm, layer):
    """Vertices and bulges of an outline polyline, in order."""
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = [p for p in vm.entdata[e]]
        got = {}
        vs, bs = [], []
        for p in d:
            if isinstance(p, Dot):
                if p.a == 0:
                    got['t'] = p.b
                elif p.a == 8:
                    got['l'] = p.b
                elif p.a == 42:
                    bs.append(p.b)
            elif isinstance(p, list) and p and p[0] == 10:
                vs.append(p[1] if len(p) == 2 else p[1:])
            elif isinstance(p, list) and p and p[0] == 42:
                bs.append(p[1])
            elif isinstance(p, list) and p and p[0] == 0:
                got['t'] = p[1]
            elif isinstance(p, list) and p and p[0] == 8:
                got['l'] = p[1]
        if got.get('t') == 'LWPOLYLINE' and got.get('l') == layer:
            return vs, bs
    return None, None


def hinge_labels(vm):
    """The Hinge / Velcro Hinge MTEXTs, west to east."""
    lab = [d for d in drawn(vm, 'MTEXT', 'TEXT')
           if d.get(1) in ('Hinge', 'Velcro Hinge')]
    lab.sort(key=lambda d: d[10][0])
    return [d[1] for d in lab]


# --------------------------------------------------------------- round

def test_round_takes_one_measurement():
    """A round spa asks for the diameter and nothing else."""
    vm = run([None,            # no Spa Cover Details block
              'Coversize',
              'ROund',
              None,            # base point 0,0
              84.0,            # THE one measurement
              'No',            # no second outline
              'No'],           # no auto-hinge
             'round/one-measurement')
    circles = drawn(vm, 'CIRCLE', 'COVER')
    assert len(circles) == 1, circles
    assert abs(circles[0][40] - 42.0) < 1e-9, circles[0][40]
    # exactly one distance prompt was consumed for the body
    dists = [p for p, a in vm.prompts if 'diameter' in p]
    assert len(dists) == 1, [p for p, _ in vm.prompts]
    assert 'Outofround' in dists[0], dists[0]


def test_round_out_of_round_still_available():
    """The keyword opens the two-axis path, so nothing is lost."""
    vm = run([None, 'Coversize', 'ROund', None,
              'Outofround',    # decline the single measurement
              84.0, 80.0,      # B across, A up
              'No', 'No'],
             'round/out-of-round')
    assert not drawn(vm, 'CIRCLE', 'COVER')
    assert len(drawn(vm, 'ELLIPSE', 'COVER')) == 1


# ----------------------------------------------------------- rectangle

def test_rectangle_length_suggests_width():
    """Enter at the length takes the width -- a square spa."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0,            # width
              None,            # Enter -> length takes 84
              '90', None, None, None,   # corner A, then Enter x3
              'No', 'No'],
             'rect/suggest')
    vs, _ = plverts(vm, 'COVER')
    xs = [v[0] for v in vs]
    ys = [v[1] for v in vs]
    assert abs((max(xs) - min(xs)) - 84.0) < 1e-9
    assert abs((max(ys) - min(ys)) - 84.0) < 1e-9, (max(ys) - min(ys))


def test_rectangle_can_decline_the_suggestion():
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,      # decline: type a different length
              '90', None, None, None,
              'No', 'No'],
             'rect/decline')
    vs, _ = plverts(vm, 'COVER')
    ys = [v[1] for v in vs]
    assert abs((max(ys) - min(ys)) - 60.0) < 1e-9


# ---------------------------------------------------------------- Back

def test_back_at_every_measurement():
    """Back unwinds the measurement block without dying."""
    run([None, 'Coversize', 'Rectangle', None,
         84.0, 60.0,
         'Back',            # at corner A -> back into the sides stage
         # a stage is re-asked from ITS first question, so both sides
         # come round again
         62.0, None,
         '90', None, None,  # corners A, B, C
         'Back',            # at corner D -> back to corner C
         None, None,        # re-answer C, then D
         'No', 'No'],
        'rect/back-measurements')


def test_back_at_the_corner_size():
    """Back at a corner's size re-asks its type."""
    run([None, 'Coversize', 'Rectangle', None,
         84.0, None,
         'Radius', 'Back',   # size -> back to the type
         '90', None, None, None,
         'No', 'No'],
        'rect/back-corner-size')


def test_back_out_of_the_offset_reopens_the_offer():
    """Back at the lap re-opens 'draw the other outline', and the
    method can then be changed -- the path that used to hand a
    SPA-BACK symbol to (+ ...)."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              '90', None, None, None,
              'No',                # no auto-hinge (asked before drawing)
              'Yes', 'Offset',
              'Back',              # back out of the lap
              'Yes', 'Dims',       # ... and switch method
              78.0, None],         # water's edge overalls
             'rect/back-out-of-offset')
    assert outline(vm, 'POOL'), "the second outline was never drawn"


def test_back_undo_synonym():
    """Undo is accepted everywhere Back is."""
    run([None, 'Coversize', 'Rectangle', None,
         84.0, 60.0,
         'Undo',            # the unlisted synonym for Back
         # Back out of a stage re-asks that stage from ITS first
         # question, so both sides come round again
         62.0, None,
         '90', None, None, None,
         'No', 'No'],
        'rect/undo-synonym')


# ------------------------------------------------- bounded outlines

def test_each_outline_is_one_closed_entity():
    """Cover and water's edge are each a single closed polyline, not a
    scatter of loose lines."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              '90', None, None, None,
              'No',                # no auto-hinge
              'Yes', 'Offset', 3.0],
             'bounded/two-outlines')
    for layer in ('COVER', 'POOL'):
        pls = drawn(vm, 'LWPOLYLINE', layer)
        assert len(pls) == 1, f"{layer}: {len(pls)} polylines"
        assert pls[0].get(70) == 1, f"{layer} polyline is not closed"
    # and nothing is left drawn as loose perimeter lines
    assert not drawn(vm, 'LINE', 'COVER')
    assert not drawn(vm, 'LINE', 'POOL')


def test_radius_corner_becomes_an_arc_segment():
    """A radius corner is an arc segment of the polyline, with the
    bulge of a quarter-turn fillet: tan(22.5) = 0.41421."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              # corner A: type then size; B/C/D each Enter twice to
              # take the autofilled type AND its size
              'Radius', 12.0, None, None, None, None, None, None,
              'No', 'No'],
             'bounded/radius-bulge')
    vs, bs = plverts(vm, 'COVER')
    assert len(vs) == 8, vs          # 4 corners x 2 tangent points
    arcs = [b for b in bs if abs(b) > 1e-9]
    assert len(arcs) == 4, bs
    for b in arcs:
        assert abs(b - 0.41421356) < 1e-6, b


def test_diagonal_corner_stays_straight():
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              'Diagonal', 21.0,      # corner A: a 21" cut face
              '90', '90', '90',      # B, C, D square
              'No', 'No'],
             'bounded/diagonal')
    vs, bs = plverts(vm, 'COVER')
    assert len(vs) == 5, vs          # one cut corner adds a vertex
    assert all(abs(b) < 1e-12 for b in bs), bs


# ------------------------------------------------------ millimetres

def test_mm_measurement():
    """A measurement typed as ##mm converts to inches."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              '2134mm',        # 2134 mm = 84.0157 in
              '1524mm',        # 1524 mm = 60 in exactly
              '90', None, None, None,
              'No', 'No'],
             'mm/rectangle')
    vs, _ = plverts(vm, 'COVER')
    ys = [v[1] for v in vs]
    assert abs((max(ys) - min(ys)) - 60.0) < 1e-9, max(ys) - min(ys)
    xs = [v[0] for v in vs]
    assert abs((max(xs) - min(xs)) - 2134.0 / 25.4) < 1e-9


def test_mm_is_case_and_space_insensitive():
    vm = run([None, 'Coversize', 'ROund', None,
              '1524 MM',
              'No', 'No'],
             'mm/round-spaced')
    circles = drawn(vm, 'CIRCLE', 'COVER')
    assert abs(circles[0][40] - 30.0) < 1e-9, circles[0][40]


def test_mm_at_a_typed_prompt():
    """The lap, a spa:askd prompt, takes mm too."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              '90', None, None, None,
              'No',                        # no auto-hinge
              'Yes', 'Offset', '76.2mm'],  # 76.2 mm = 3 in
             'mm/lap')
    vs, _ = plverts(vm, 'POOL')
    xs = [v[0] for v in vs]
    assert abs((max(xs) - min(xs)) - 78.0) < 1e-9, max(xs) - min(xs)


def test_junk_is_re_asked_not_accepted():
    """Arbitrary input that is not a measurement re-asks rather than
    slipping through as a number."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              'banana',        # rejected...
              84.0,            # ...then a real answer
              None,
              '90', None, None, None,
              'No', 'No'],
             'mm/junk')
    # the width prompt came round twice: junk did not slip through
    widths = [p for p, _ in vm.prompts if 'WIDTH' in p]
    assert len(widths) == 2, [p for p, _ in vm.prompts]
    vs, _ = plverts(vm, 'COVER')
    xs = [v[0] for v in vs]
    assert abs((max(xs) - min(xs)) - 84.0) < 1e-9


# -------------------------------------------------------------- hinges

def test_five_piece_hinge_arrangement():
    """A cover wide enough for 5 pieces reads H V V H."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              230.0, 60.0,          # 230/48 -> 5 pieces
              '90', None, None, None,
              'Yes',                # auto-hinge -- asked before the draw
              'No',                 # no spillaway
              None,                 # no details block
              '4-3',                # taper
              'No'],                # no second outline
             'hinge/5-piece')
    assert hinge_labels(vm) == ['Hinge', 'Velcro Hinge',
                                'Velcro Hinge', 'Hinge'], hinge_labels(vm)


def test_three_piece_hinge_arrangement():
    vm = run([None, 'Coversize', 'Rectangle', None,
              140.0, 60.0,          # 140/48 -> 3 pieces
              '90', None, None, None,
              'Yes', 'No', None, '4-3', 'No'],
             'hinge/3-piece')
    assert hinge_labels(vm) == ['Hinge', 'Velcro Hinge'], hinge_labels(vm)


def test_back_in_the_spillaway_loop():
    """Back at the top of the loop drops the spillaway just committed."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              140.0, 60.0,
              '90', None, None, None,
              'Yes',
              'Yes', 'Wall', 'Top', 20.0,   # commit one
              'Back',                        # ... and take it back
              'No',
              None, '4-3',
              'No'],                         # no second outline
             'hinge/spillaway-back')
    rows = [p for p, _ in vm.prompts]
    assert any('spillaway' in p.lower() for p in rows)


def test_octagon_runs():
    vm = run([None, 'Coversize', 'OCtagon', None,
              95.0, None,           # B, then Enter -> A takes B
              # the optional letters are declined by typing NA, which is
              # what their prompt offers -- Enter is not accepted there
              'NA', 'NA', 'NA', 'NA', 'NA',   # S2/T/S/S1/V
              'No', 'No'],
             'octagon/basic')
    vs, bs = plverts(vm, 'COVER')
    assert len(vs) == 8, vs
    assert all(abs(b) < 1e-12 for b in bs), bs


def test_thermolight_style_all_velcro():
    """With no block the grade is Standard; the all-velcro path is
    exercised through the taper instead."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              230.0, 60.0,
              '90', None, None, None,
              'Yes', 'No', None, '1-3/8', 'No'],
             'hinge/thermolight-taper')
    assert hinge_labels(vm), "no hinges drawn"


# ---------------------------------------------------------- mini-model

def letters(vm):
    """The corner-letter TEXTs on SPA-NOTES, keyed by letter."""
    out = {}
    for d in drawn(vm, 'TEXT', 'SPA-NOTES'):
        t = str(d.get(1, ''))
        if len(t) == 1 and t.isalpha():
            out.setdefault(t, []).append(d[10])
    return out


def notes_lines(vm):
    return [d for d in drawn(vm, 'LINE', 'SPA-NOTES')]


def test_corner_letters_are_off_the_drawing_and_on_the_mini_model():
    """A B C D are drawn ONCE each, beside the report -- not in the
    corners of the spa itself, where they used to crowd the dimensions
    and the hinge labels."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,
              '90', None, None, None,
              'No', 'No'],
             'mini/rect')
    lb = letters(vm)
    assert sorted(lb) == ['A', 'B', 'C', 'D'], sorted(lb)
    for k, pts in lb.items():
        assert len(pts) == 1, (k, pts)
    # the drawing itself ends at x = 84; the report starts a yard past it
    for k, pts in lb.items():
        assert pts[0][0] > 84.0 + 36.0, (k, pts[0])
    # and the letters sit on a mini outline, not on nothing
    mini = [d for d in notes_lines(vm) if d[10][0] > 84.0 + 36.0]
    assert len(mini) >= 4, len(mini)


def test_the_mini_model_carries_the_corner_treatments():
    """A radius corner is an ARC on the mini-model, so the small copy
    reads as the shape that was drawn."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              'Radius', 12.0, None, None, None, None, None, None,
              'No', 'No'],
             'mini/radius')
    arcs = [d for d in drawn(vm, 'ARC', 'SPA-NOTES')]
    assert len(arcs) == 4, len(arcs)


def test_octagon_letters_are_on_the_mini_model_too():
    vm = run([None, 'Coversize', 'OCtagon', None,
              95.0, None,
              'NA', 'NA', 'NA', 'NA', 'NA',
              'No', 'No'],
             'mini/octagon')
    lb = letters(vm)
    assert sorted(lb) == list('ABCDEFGH'), sorted(lb)
    for k, pts in lb.items():
        assert pts[0][0] > 95.0 + 36.0, (k, pts[0])


def test_round_mini_model_has_a_body_and_no_letters():
    """A round spa has no corners, so its mini-model carries no
    letters -- but it is still drawn, beside the report."""
    vm = run([None, 'Coversize', 'ROund', None, 84.0, 'No', 'No'],
             'mini/round')
    assert letters(vm) == {}, letters(vm)
    minis = [d for d in drawn(vm, 'CIRCLE', 'SPA-NOTES')
             if d[10][0] > 84.0 + 36.0]
    assert len(minis) == 1, len(minis)


# ------------------------------------------- the quarter turn for a spillway

def cover_size(vm):
    vs, _ = plverts(vm, 'COVER')
    xs = [v[0] for v in vs]
    ys = [v[1] for v in vs]
    return (max(xs) - min(xs), max(ys) - min(ys))


def hinge_xs(vm):
    return sorted(d[10][0] for d in drawn(vm, 'MTEXT', 'TEXT')
                  if d.get(1) in ('Hinge', 'Velcro Hinge'))


def test_a_spillway_no_hinge_can_dodge_turns_the_spa():
    """100 x 60 with a 60" spillway across the TOP wall: every hinge
    station lands in the zone whichever count is tried, so the spa is
    turned a quarter turn and the spillway comes to rest on a side wall
    where a north-south hinge cannot meet it."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              100.0, 60.0,
              '90', None, None, None,
              'Yes',                        # auto-hinge
              'Yes', 'Wall', 'Top', 60.0,   # right across the top wall
              'No',
              None, '4-3',
              'No'],
             'turn/top-wall')
    w, l = cover_size(vm)
    assert abs(w - 60.0) < 1e-9 and abs(l - 100.0) < 1e-9, (w, l)
    txt = [d[1] for d in drawn(vm, 'TEXT', 'SPA-NOTES')]
    assert any('CLEAR OF THE SPILLWAY' in t for t in txt), txt
    # the report says where the spillway ended up on the drawing
    assert any('SPILLWAY TOP WALL (DRAWN RIGHT)' in t for t in txt), txt
    # and the hinge that is drawn is nowhere near a zone
    assert hinge_xs(vm), "no hinge drawn"
    assert not any('COULD NOT ALL BE AVOIDED' in t for t in txt), txt


def test_a_side_wall_spillway_leaves_the_spa_alone():
    """The same spillway on the LEFT wall never meets a north-south
    hinge, so there is nothing to turn away from."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              100.0, 60.0,
              '90', None, None, None,
              'Yes',
              'Yes', 'Wall', 'Left', 60.0,
              'No',
              None, '4-3',
              'No'],
             'turn/left-wall')
    w, l = cover_size(vm)
    assert abs(w - 100.0) < 1e-9 and abs(l - 60.0) < 1e-9, (w, l)
    txt = [d[1] for d in drawn(vm, 'TEXT', 'SPA-NOTES')]
    assert not any('QUARTER TURN' in t for t in txt), txt


def test_a_spillway_the_hinges_already_clear_turns_nothing():
    """A 20" spillway centred on the top wall of a 100 x 60 cover sits
    between the two hinge stations, so both ways round lay out perfectly
    and the long-overall rule keeps the drawing."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              100.0, 60.0,
              '90', None, None, None,
              'Yes',
              'Yes', 'Wall', 'Top', 20.0,
              'No',
              None, '4-3',
              'No'],
             'turn/no-need')
    w, l = cover_size(vm)
    assert abs(w - 100.0) < 1e-9 and abs(l - 60.0) < 1e-9, (w, l)
    txt = [d[1] for d in drawn(vm, 'TEXT', 'SPA-NOTES')]
    assert not any('QUARTER TURN' in t for t in txt), txt
    assert not any('COULD NOT ALL BE AVOIDED' in t for t in txt), txt


def test_a_turned_spa_still_reports_its_letters():
    """The letters travel with their corners, so the mini-model of a
    turned spa reads back against the report."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              60.0, 100.0,          # typed the tall way round
              'Radius', 6.0, '90', '90', '90',
              'No', 'No'],
             'turn/letters')
    lb = letters(vm)
    assert sorted(lb) == ['A', 'B', 'C', 'D'], sorted(lb)
    # the turn is a quarter turn CLOCKWISE, so the corner that was
    # bottom-left (A, the radius one) is now top-left on the mini-model
    xs = sorted(v[0][0] for v in lb.values())
    ys = sorted(v[0][1] for v in lb.values())
    assert lb['A'][0][0] == xs[0], lb          # leftmost...
    assert lb['A'][0][1] == ys[-1], lb         # ...and topmost


if __name__ == '__main__':
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            try:
                fn()
                print(f"ok   {name}")
            except AssertionError as e:
                fails += 1
                print(f"FAIL {name}\n     {e}")
    print(f"\n{fails} failure(s)")
    sys.exit(1 if fails else 0)
