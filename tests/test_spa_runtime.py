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
from lispvm import VM, Ent, LispError, Dot, Sym, NIL, MISS  # noqa: E402

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
    """Enter at the width (up) takes the length (across) -- a square spa."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0,            # length, across
              None,            # Enter -> the width takes 84
              'Yes', '90',     # all four the same: one round of questions
              'No', 'No'],
             'rect/suggest')
    vs, _ = plverts(vm, 'COVER')
    xs = [v[0] for v in vs]
    ys = [v[1] for v in vs]
    assert abs((max(xs) - min(xs)) - 84.0) < 1e-9
    assert abs((max(ys) - min(ys)) - 84.0) < 1e-9, (max(ys) - min(ys))


def test_rectangle_can_decline_the_suggestion():
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,      # decline: type a different width
              'Yes', '90',
              'No', 'No'],
             'rect/decline')
    vs, _ = plverts(vm, 'COVER')
    ys = [v[1] for v in vs]
    assert abs((max(ys) - min(ys)) - 60.0) < 1e-9


# ---------------------------------------------------------------- Back

def test_back_at_every_measurement():
    """Back unwinds the measurement block without dying: out of the
    all-same gate into the sides, and out of corner A back to the
    gate -- each question's Back re-asks the one before it."""
    run([None, 'Coversize', 'Rectangle', None,
         84.0, 60.0,
         'Back',            # at the gate -> back into the sides stage
         # a stage is re-asked from ITS first question, so both sides
         # come round again
         62.0, None,
         'No',              # corners one at a time
         'Back',            # at corner A -> back to the gate
         'No',              # ... which is asked again
         '90', None, None,  # corners A, B, C
         'Back',            # at corner D -> back to corner C
         None, None,        # re-answer C, then D
         'No', 'No'],
        'rect/back-measurements')


def test_back_at_the_corner_size():
    """Back at a corner's size re-asks its type."""
    run([None, 'Coversize', 'Rectangle', None,
         84.0, None,
         'Yes',              # one round for all four
         'Radius', 'Back',   # size -> back to the type
         '90',
         'No', 'No'],
        'rect/back-corner-size')


def test_back_out_of_the_offset_reopens_the_offer():
    """Back at the lap re-opens 'draw the other outline', and the
    method can then be changed -- the path that used to hand a
    SPA-BACK symbol to (+ ...)."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              'Yes', '90',
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
         'Yes', '90',
         'No', 'No'],
        'rect/undo-synonym')


# ------------------------------------------------- bounded outlines

def test_each_outline_is_one_closed_entity():
    """Cover and water's edge are each a single closed polyline, not a
    scatter of loose lines."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              'Yes', '90',
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
              # one round: the treatment then its size, taken by all
              # four corners
              'Yes', 'Radius', 12.0,
              'No', 'No'],
             'bounded/radius-bulge')
    vs, bs = plverts(vm, 'COVER')
    assert len(vs) == 8, vs          # 4 corners x 2 tangent points
    arcs = [b for b in bs if abs(b) > 1e-9]
    assert len(arcs) == 4, bs
    for b in arcs:
        assert abs(b - 0.41421356) < 1e-6, b


def dimcalls(vm, name):
    """Every logged `command` call for one dimension verb."""
    return [c for c in vm.commands if c and c[0] == name]


def selected(call):
    """The entity a (list ename point) selection pair names, or None."""
    for x in call[1:]:
        if isinstance(x, list) and len(x) == 2 and isinstance(x[0], Ent):
            return x[0]
    return None


def override(call):
    """The text a dimension command was given after "_T", or None."""
    for i, x in enumerate(call[:-1]):
        if isinstance(x, str) and x.upper() == '_T' \
                and isinstance(call[i + 1], str):
            return call[i + 1]
    return None


def markcalls(vm):
    """The corner MARKS: a radius dim on the little circle that sits on
    the corner point, its measurement replaced by what the mark says
    ("90%%d", "?", either with a " Typ." suffix)."""
    return [c for c in dimcalls(vm, '_.DIMRADIUS')
            if str(override(c)).startswith(('90%%d', '?'))]


def radcalls(vm):
    """Radius dims that MEASURE a corner -- the marks left out."""
    return [c for c in dimcalls(vm, '_.DIMRADIUS')
            if not str(override(c)).startswith(('90%%d', '?'))]


def raddim(vm, mark):
    """The DIMENSION entity a mark left behind (group 70 bit 4 = radial,
    group 1 the text it carries)."""
    return [d for d in drawn(vm, 'DIMENSION')
            if d.get(70) == 4 and d.get(1) == mark]


def dxf0(vm, e):
    for p in vm.entdata.get(e, []):
        if isinstance(p, Dot) and p.a == 0:
            return p.b
        if isinstance(p, list) and p and p[0] == 0:
            return p[1]
    return None


def stray_arcs(vm):
    """ARCs anywhere but the mini-model's layer: a radius callout's
    scaffold arc that was not taken away again."""
    return [d for d in drawn(vm, 'ARC') if d.get(8) != 'SPA-NOTES']


def test_radius_callout_is_handed_an_arc():
    """DIMRADIUS answers "Select arc or circle:", and it means it.

    The outline is one closed polyline and a radius corner is a bulge
    in it, so there is no arc entity to point at.  Handing DIMRADIUS
    the parent polyline's ename is rejected at the AutoCAD command
    line -- "Object selected is not a circle or arc" -- and because the
    Typ. form feeds four arguments, the three that follow are eaten as
    three more bad selections and the command is left stranded.  The
    routine builds the arc it asks for instead, and takes it away
    again, so what is selected must be an ARC and no arc may survive
    the run.
    """
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              'Yes', 'Radius', 8.0,
              'No', 'No'],
             'radius/callout-selection')
    calls = dimcalls(vm, '_.DIMRADIUS')
    assert len(calls) == 1, calls          # four identical corners: one Typ.
    for c in calls:
        e = selected(c)
        assert e is not None, "no (ename point) selection pair: %r" % (c,)
        assert dxf0(vm, e) == 'ARC', (
            "DIMRADIUS was handed a %s, which AutoCAD refuses to dimension"
            % dxf0(vm, e))
    # the mini-model beside the report draws its radius corners as arcs
    # on SPA-NOTES; those are the picture, not the scaffold
    assert not stray_arcs(vm), (
        "the arc built to hang the dimension on was left in the drawing")


def test_square_corner_mark_is_a_dim_on_its_own_circle():
    """STANDARDS section 2, the way the sample sheet draws it: the mark
    is a small circle on the corner point with a RADIUS DIMENSION on
    that circle, its measurement replaced by what the mark says.  Four
    identical corners -> one mark, with the Typ. suffix."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,
              'Yes', '90',           # all four square
              'No', 'No'],
             'mark/square')
    calls = markcalls(vm)
    assert len(calls) == 1, [override(c) for c in calls]
    assert override(calls[0]) == '90%%d Typ.', override(calls[0])
    assert not radcalls(vm), "a square corner measures nothing"
    # it is hung on the mark circle, and picked ON that circle
    e = selected(calls[0])
    assert dxf0(vm, e) == 'CIRCLE', dxf0(vm, e)
    circles = [d for d in drawn(vm, 'CIRCLE', 'DIMENSION')]
    assert len(circles) == 1, circles
    on = [x[1] for x in calls[0][1:]
          if isinstance(x, list) and len(x) == 2 and isinstance(x[0], Ent)][0]
    c, r = circles[0][10], circles[0][40]
    assert abs(((on[0] - c[0]) ** 2 + (on[1] - c[1]) ** 2) ** 0.5 - r) < 1e-6
    # ... and it is NOT boxed: only the "?" of a NotGiven corner is
    d = raddim(vm, '90%%d Typ.')
    assert len(d) == 1 and d[0].get(147, 0) > 0, d


def test_not_given_corner_is_a_boxed_question_with_its_note():
    """A corner the sheet never gave: the same mark asking "?" instead
    of asserting 90, drawn in a BOX (a negative DIMGAP), with the
    "Not Given" note on a leader off that box.  The gap is handed
    straight back, so the next dimension is not boxed too."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,
              'No', 'NotGiven', '90', '90', '90',   # A never given
              'No', 'No'],
             'mark/notgiven')
    assert sorted(override(c) for c in markcalls(vm)) == \
        ['90%%d', '90%%d', '90%%d', '?'], [override(c) for c in markcalls(vm)]
    boxed = raddim(vm, '?')
    assert len(boxed) == 1, boxed
    assert boxed[0].get(147, 0) < 0, "the ? has to come out in a box"
    for d in raddim(vm, '90%%d'):
        assert d.get(147, 0) > 0, "only the ? is boxed"
    # the note is the leader's own annotation, hung off the box
    leaders = [c for c in vm.commands if c and c[0] == '_.LEADER']
    assert len(leaders) == 1 and leaders[0][-2] == 'Not Given', leaders
    # it leaves the mark heading away from the shape, so it cannot read
    # back across itself
    start, end = leaders[0][1], leaders[0][2]
    verts, _ = plverts(vm, 'COVER')
    cen = [sum(v[i] for v in verts) / len(verts) for i in (0, 1)]
    dist = lambda p: ((p[0] - cen[0]) ** 2 + (p[1] - cen[1]) ** 2) ** 0.5
    assert dist(end) > dist(start), (start, end)
    # and the drawing's own gap survived the run
    assert vm.sysvars['DIMGAP'] > 0, vm.sysvars['DIMGAP']


def test_radius_callout_on_both_outlines():
    """Radius corners AND a second outline -- the pairing no script in
    the tree covered, and the one that fires the callout twice."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              'Yes', 'Radius', 8.0,
              'No',                # no auto-hinge
              'Yes', 'Offset', 3.0],
             'radius/two-outlines')
    calls = dimcalls(vm, '_.DIMRADIUS')
    assert len(calls) == 2, calls          # one Typ. callout per outline
    for c in calls:
        assert dxf0(vm, selected(c)) == 'ARC', c
    assert not stray_arcs(vm), "a temporary arc was left behind"
    for layer in ('COVER', 'POOL'):
        assert len(drawn(vm, 'LWPOLYLINE', layer)) == 1, layer


def test_diagonal_corner_stays_straight():
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              'No',                  # not all the same: one at a time
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
              'Yes', '90',
              'No', 'No'],
             'mm/rectangle')
    vs, _ = plverts(vm, 'COVER')
    ys = [v[1] for v in vs]
    assert abs((max(ys) - min(ys)) - 60.0) < 1e-9, max(ys) - min(ys)
    xs = [v[0] for v in vs]
    assert abs((max(xs) - min(xs)) - 2134.0 / 25.4) < 1e-9


def test_mm_is_case_insensitive():
    """MM reads like mm.  The unit touches the number: at a typed
    prompt the spacebar is Enter, so a spaced '1524 MM' cannot reach
    the parser in one piece (see the test below)."""
    vm = run([None, 'Coversize', 'ROund', None,
              '1524MM',
              'No', 'No'],
             'mm/round-upper')
    circles = drawn(vm, 'CIRCLE', 'COVER')
    assert abs(circles[0][40] - 30.0) < 1e-9, circles[0][40]


def test_a_spaced_mm_is_refused_not_taken_as_inches():
    """'1524 mm' typed with the space: getdist returns at the space with
    the NUMBER 1524, and the 'MM' is typed into whatever comes next.
    That 1524 was taken as a 127-ft diameter without a word and the MM
    was refused at the auto-hinge question.  No spa is that big, so it
    is refused with the spelling that works; the stray MM then meets
    the same question again and is refused as not a measurement."""
    vm = run([None, 'Coversize', 'ROund', None,
              1524.0, 'MM',          # what the spacebar makes of 1524 MM
              '1524mm',              # ...and what the hint says to type
              'No', 'No'],
             'mm/round-spaced')
    circles = drawn(vm, 'CIRCLE', 'COVER')
    assert abs(circles[0][40] - 30.0) < 1e-9, circles[0][40]
    said = ''.join(vm.printed)
    assert 'longer than any spa' in said and '1524mm' in said, said
    asked = [p for p, _ in vm.prompts if 'diameter' in p]
    assert len(asked) == 3, asked
    # the measurement sequence (spa:asks) refuses it the same way
    vm = run([None, 'Coversize', 'Rectangle', None,
              2134.0, 'MM', '2134mm',     # the length, spaced then right
              '1524mm',
              'Yes', '90',
              'No', 'No'],
             'mm/rect-spaced')
    vs, _ = plverts(vm, 'COVER')
    xs = [v[0] for v in vs]
    assert abs((max(xs) - min(xs)) - 2134.0 / 25.4) < 1e-9, xs
    assert 'longer than any spa' in ''.join(vm.printed)


def test_mm_at_a_typed_prompt():
    """The lap, a spa:askd prompt, takes mm too."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, None,
              'Yes', '90',
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
              'Yes', '90',
              'No', 'No'],
             'mm/junk')
    # the across overall (the LENGTH) came round twice: junk did not
    # slip through
    widths = [p for p, _ in vm.prompts if 'LENGTH across' in p]
    assert len(widths) == 2, [p for p, _ in vm.prompts]
    vs, _ = plverts(vm, 'COVER')
    xs = [v[0] for v in vs]
    assert abs((max(xs) - min(xs)) - 84.0) < 1e-9


# -------------------------------------------------------------- hinges

def test_five_piece_hinge_arrangement():
    """A cover wide enough for 5 pieces reads H V V H."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              230.0, 60.0,          # 230/48 -> 5 pieces
              'Yes', '90',
              'Yes',                # auto-hinge -- asked before the draw
              'No',                 # no spillway
              'No',                 # no second outline
              '4-3'],               # taper -- asked after (block offered
                                    # up front, but not read here)
             'hinge/5-piece')
    assert hinge_labels(vm) == ['Hinge', 'Velcro Hinge',
                                'Velcro Hinge', 'Hinge'], hinge_labels(vm)


def test_three_piece_hinge_arrangement():
    vm = run([None, 'Coversize', 'Rectangle', None,
              140.0, 60.0,          # 140/48 -> 3 pieces
              'Yes', '90',
              'Yes', 'No', 'No', '4-3'],
             'hinge/3-piece')
    assert hinge_labels(vm) == ['Hinge', 'Velcro Hinge'], hinge_labels(vm)


def test_back_in_the_spillway_loop():
    """Back at the top of the loop drops the spillway just committed."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              140.0, 60.0,
              'Yes', '90',
              'Yes',
              'Yes', 'Wall', 'Top', 20.0,   # commit one
              'Back',                        # ... and take it back
              'No',
              'No',                         # no second outline
              '4-3'],                        # taper -- asked after
             'hinge/spillway-back')
    rows = [p for p, _ in vm.prompts]
    assert any('spillway' in p.lower() for p in rows)


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
              'Yes', '90',
              'Yes', 'No', 'No', '1-3/8'],
             'hinge/thermolight-taper')
    assert hinge_labels(vm), "no hinges drawn"


def test_corner_size_at_exactly_the_cap():
    """A treatment sized at exactly its cap is accepted, not re-asked.

    The cap is half the shorter side; a cut face is capped through its
    setback (face / sqrt 2), so the maximum the prompt prints is a
    division away from the number that is compared.  Typing that
    printed maximum back must be accepted -- a prompt that refuses the
    figure it just told you is one a drafter cannot get out of.
    """
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,
              'Yes', 'Radius', 30.0,    # exactly half the 60" side
              'No', 'No'],
             'corner/radius-at-the-cap')
    assert not [s for s in vm.printed if 'Too large' in s], \
        [s for s in vm.printed if 'Too large' in s]
    _, bulges = plverts(vm, 'COVER')
    assert any(abs(b) > 1e-9 for b in bulges), bulges


def test_corner_size_over_the_cap_is_still_refused():
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,
              'Yes', 'Radius', 45.0,    # will not fit
              30.0,                     # the maximum, typed back
              'No', 'No'],
             'corner/radius-over-the-cap')
    assert len([s for s in vm.printed if 'Too large' in s]) == 1, \
        [s for s in vm.printed if 'Too large' in s]


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
              'Yes', '90',
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
              'Yes', 'Radius', 12.0,
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


def test_not_given_row_reads_na_in_both_columns():
    """Nothing was measured and nothing was built to a size, so the
    row records only that the sheet never said -- as POOL's does."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,
              'No', 'NotGiven', '90', '90', '90',
              'No', 'No'],
             'mini/notgiven-row')
    rows = drawn(vm, 'TEXT', 'SPA-NOTES')
    lbl = [d for d in rows if d.get(1) == 'CORNER A NOTGIVEN']
    assert len(lbl) == 1, [d.get(1) for d in rows]
    y = lbl[0][10][1]
    same_row = sorted(str(d.get(1)) for d in rows
                      if abs(d[10][1] - y) < 1e-9 and d is not lbl[0])
    assert same_row == ['-', 'N/A', 'N/A'], same_row


# ------------------------------------------- the quarter turn for a spillway

def cover_size(vm):
    vs, _ = plverts(vm, 'COVER')
    xs = [v[0] for v in vs]
    ys = [v[1] for v in vs]
    return (max(xs) - min(xs), max(ys) - min(ys))


def hinge_xs(vm):
    return sorted(d[10][0] for d in drawn(vm, 'MTEXT', 'TEXT')
                  if d.get(1) in ('Hinge', 'Velcro Hinge'))


def test_hinge_questions_come_before_the_draw():
    """The auto-hinge offer and the spillways are asked before the
    second-outline offer -- nothing on the screen can be turned, so
    they have to be.  The taper does not turn anything, so it is asked
    the other way round: after the second-outline offer, once the
    cover is on the screen (or the offer to add one is declined)."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              140.0, 60.0,
              'Yes', '90',
              'Yes', 'No',
              'No',
              '4-3'],
             'turn/order')
    ps = [p for p, _ in vm.prompts]
    hinge = next(i for i, p in enumerate(ps) if 'Auto-hinge' in p)
    second = next(i for i, p in enumerate(ps) if 'as well' in p)
    taper = next(i for i, p in enumerate(ps) if 'Taper' in p)
    assert hinge < second, ps
    assert second < taper, ps
    assert hinge_labels(vm) == ['Hinge', 'Velcro Hinge'], hinge_labels(vm)


def test_a_spillway_no_hinge_can_dodge_turns_the_spa():
    """100 x 60 with a 60" spillway across the TOP wall: every hinge
    station lands in the zone whichever count is tried, so the spa is
    turned a quarter turn and the spillway comes to rest on a side wall
    where a north-south hinge cannot meet it."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              100.0, 60.0,
              'Yes', '90',
              'Yes',                        # auto-hinge
              'Yes', 'Wall', 'Top', 60.0,   # right across the top wall
              'No',
              'No',                         # no second outline
              '4-3'],                       # taper -- asked after
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
              'Yes', '90',
              'Yes',
              'Yes', 'Wall', 'Left', 60.0,
              'No',
              'No',
              '4-3'],
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
              'Yes', '90',
              'Yes',
              'Yes', 'Wall', 'Top', 20.0,
              'No',
              'No',
              '4-3'],
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
              'No', 'Radius', 6.0, '90', '90', '90',
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



def test_pickturn_says_which_way_it_actually_went():
    """The spillway can overrule the long-overall rule in BOTH
    directions, and what is announced has to match which one happened.

    spa:pickturn is handed pref -- the way round the long-overall rule
    asks for -- and returns the way round to draw.  When the other way
    round scores better it flips, and until REV17 it announced a
    quarter turn either way.  With pref already T that flip means NOT
    turning, so the command line said the spa was turned when it was
    left as measured, and spa:advise wrote the same claim into the
    report block that is drawn on the sheet.  Nothing read it back, so
    nothing failed: the drawing was right and the note on it was wrong.

    spa:hscore is replaced here rather than driven: the bug is in
    pickturn's own announcement, and scoring a real spillway into a
    tie-break needs the whole hinge pass to say anything about it.
    """
    def probe(pref):
        vm = VM()
        vm.load(LSP)
        vm.loads('(setq spa:*hingeon* t spa:*spills* (list (list 0.0 10.0)))')
        vm.loads('(defun spa:foamopts (g tp)'
                 ' (list (list (cons 48.0 96.0)) (list 2 3 4 5)))')
        # the second call -- the OTHER way round -- always scores better
        vm.loads('(setq t:*n* 0)')
        vm.loads('(defun spa:hscore (c turn opts allowed)'
                 ' (setq t:*n* (1+ t:*n*)) (if (= t:*n* 1) 1 2))')
        vm.loads('(setq spa:*spillturn* nil spa:*advice* nil)')
        vm.loads(f'(setq t:*r* (spa:pickturn {pref} (list "c0") (list "c1")))')
        return (vm.globals['t:*r*'],
                vm.globals.get('spa:*spillturn*'),
                [str(a) for a in (vm.globals.get('spa:*advice*') or [])],
                ''.join(str(p) for p in vm.printed))

    # the rule wanted it left alone; the spillway turns it
    turned, spillturn, advice, out = probe('nil')
    assert turned, "the spillway should have turned it"
    assert spillturn, "spa:*spillturn* must say the spillway did the turning"
    assert advice == ['TURNED A QUARTER TURN TO CLEAR THE SPILLWAY'], advice
    assert 'turned a quarter turn instead' in out, out

    # the rule wanted a quarter turn; the spillway leaves it as measured
    turned, spillturn, advice, out = probe('t')
    assert not turned, "the spillway should have left it as measured"
    assert not spillturn, \
        "spa:*spillturn* claims a turn that did not happen: %r" % spillturn
    assert advice == ['LEFT AS MEASURED TO CLEAR THE SPILLWAY'], \
        "the report block is told the opposite of what was drawn: %r" % advice
    assert 'left as measured instead' in out, out
    assert 'turned a quarter turn' not in out, \
        "the command line announces a turn that did not happen: %r" % out


# ----------------------------------------------- the guide and the block
#
# Two things a drafter meets at the screen rather than in the geometry:
# the Spa Cover Details pick is ONE question, and there is a spa in
# front of them the whole way through.  The two were broken together --
# the second pick arrived just after the guide had been taken away, so
# it asked for a click into a drawing that was no longer on the screen.

BLOCK = '''
  (setq blk (entmakex (list '(0 . "INSERT") '(8 . "0")
                            '(2 . "Spa Cover Details")
                            '(10 0.0 300.0) '(66 . 1))))
  (entmake (list '(0 . "ATTRIB") '(8 . "0") '(2 . "GRADE")
                 '(1 . "GRADE: Standard")))
  (entmake (list '(0 . "ATTRIB") '(8 . "0") '(2 . "TAPER")
                 '(1 . "TAPER: 4-3")))
  (entmake (list '(0 . "SEQEND") '(8 . "0")))'''


def guide_alive(vm):
    """Guide-preview entities still on the screen, at this moment."""
    ents = vm.globals.get(Sym('spa:*pvents*'), NIL)
    if not isinstance(ents, list):
        return 0
    return sum(1 for e in ents if e not in vm.deleted)


def watched(notes, ans):
    """A scripted answer that notes what is on the screen as it is
    reached.  A callable answer is invoked at the prompt itself, which
    is the only way to see a command mid-run."""
    def f(vm):
        notes.append(guide_alive(vm))
        return ans
    return f


def test_the_details_block_is_asked_for_once():
    """Skipping the pick is an answer: the taper is typed instead and
    the block is not asked for again.  It used to come back in the
    hinge pass -- a second click into a drawing the flow had zoomed
    away from by then."""
    vm = run([None,                 # the pick, up front -- skipped
              'Coversize', 'Rectangle', None,
              140.0, 60.0,
              'Yes', '90',
              'Yes',                # auto-hinge
              'No',                 # no spillway
              'No',                 # no second outline
              '4-3'],               # ...so the taper is typed, after
             'block/asked-once')
    picks = [p for p, _ in vm.prompts if 'Spa Cover Details' in p]
    assert len(picks) == 1, [p for p, _ in vm.prompts]
    tapers = [p for p, _ in vm.prompts if 'Taper' in p]
    assert len(tapers) == 1, [p for p, _ in vm.prompts]


def test_a_picked_block_still_answers_the_taper():
    """The pick that DOES read a taper leaves nothing to type, so the
    one offer is the whole question either way."""
    vm = VM()
    vm.load(LSP)
    vm.loads(BLOCK)
    blk = vm.globals['blk']
    vm.run('c:SPA', [blk,           # the pick, reading both tags
                     'Coversize', 'Rectangle', None,
                     140.0, 60.0, 'Yes', '90',
                     'Yes', 'No',   # auto-hinge, no spillway
                     'No'])         # no second outline
    assert not [p for p, _ in vm.prompts if 'Taper' in p], \
        "the taper was asked although the block gave it"
    assert len([p for p, _ in vm.prompts if 'Spa Cover Details' in p]) == 1


def test_the_guide_stays_up_until_the_real_spa_replaces_it():
    """The auto-hinge offer and the spillways are asked before anything
    is drawn, so the guide is the only spa on the screen while they are
    answered.  It used to be taken away as the corners were answered,
    leaving the rest of the run to be answered at a blank screen.  The
    taper is asked later still, once the real spa has already replaced
    the guide -- it turns nothing, so there is nothing gained by making
    the drafter answer it against a guide instead of their own drawing."""
    notes = []
    run([None, 'Coversize', 'Rectangle', None,
         140.0, 60.0,
         'Yes', '90',
         watched(notes, 'Yes'),     # auto-hinge
         watched(notes, 'No'),      # spillway
         watched(notes, 'No'),      # second outline -- after the draw
         watched(notes, '4-3')],    # taper -- after the draw too
        'guide/stays-up')
    assert notes[0] > 0, "the guide was gone by the auto-hinge question"
    assert notes[1] == notes[0], "the guide thinned out: %r" % (notes,)
    assert notes[2] == 0, \
        "the guide outlived the spa that replaced it: %r" % (notes,)
    assert notes[3] == 0, \
        "the taper was asked before the real spa replaced the guide: %r" % (notes,)


def test_the_octagon_and_round_guides_hand_over_the_same_way():
    for shape, body in (('OCtagon', [95.0, None,
                                     'NA', 'NA', 'NA', 'NA', 'NA']),
                        ('ROund', [84.0])):
        notes = []
        run([None, 'Coversize', shape, None] + body
            + [watched(notes, 'Yes'),   # auto-hinge
               watched(notes, 'No'),    # spillway
               watched(notes, 'No'),    # second outline -- after the draw
               watched(notes, '4-3')],  # taper -- after the draw too
            'guide/%s' % shape)
        assert notes[0] > 0 and notes[1] == notes[0], \
            "%s took its guide away mid-question: %r" % (shape, notes)
        assert notes[2] == 0 and notes[3] == 0, \
            "%s left its guide on the screen: %r" % (shape, notes)


# ----------------------------------------- a click that missed the block

THERMO = BLOCK.replace('GRADE: Standard', 'GRADE: Thermo-Light') \
              .replace('TAPER: 4-3', 'TAPER: 1-3/8')


def thermo_run(head):
    vm = VM()
    vm.load(LSP)
    vm.loads(THERMO)
    blk = vm.globals['blk']
    vm.run('c:SPA', head + [blk,              # the block, this time
                            'Rectangle', None, 140.0, 60.0,
                            'Yes', '90',
                            'Yes', 'No'])      # auto-hinge, no spillway
    return vm


def test_a_missed_click_at_the_details_block_is_asked_again():
    """A click just beside the Spa Cover Details block used to be taken
    for Enter: the one offer was spent, its Thermo-Light GRADE never
    read, and a Standard cover drawn -- with the water's-edge question
    and a typed taper put to the drafter instead, and nothing said.
    A miss is asked again now, and the block clicked second time round
    gives exactly the run a first-time hit does."""
    hit = thermo_run([])
    vm = thermo_run([MISS])        # a click that hit nothing
    picks = [p for p, _ in vm.prompts if 'Spa Cover Details' in p]
    assert len(picks) == 2, [p for p, _ in vm.prompts]
    assert 'Nothing there' in ''.join(vm.printed), ''.join(vm.printed)
    for name in ('spa:*grade*', 'spa:*taper*'):
        assert vm.globals.get(Sym(name)) == hit.globals.get(Sym(name)), \
            (name, vm.globals.get(Sym(name)), hit.globals.get(Sym(name)))
    assert vm.globals.get(Sym('spa:*grade*')) == 'THERMOLIGHT'
    assert not [p for p, _ in vm.prompts if "water's edge" in p]
    assert hinge_labels(vm) == hinge_labels(hit), \
        (hinge_labels(vm), hinge_labels(hit))


def test_enter_is_still_the_skip_with_a_stale_errno():
    """ERRNO is sticky: a 7 some earlier call left behind must not turn
    a real Enter into a miss.  It is cleared before the pick."""
    vm = VM()
    vm.load(LSP)
    vm.sysvars['ERRNO'] = 7
    vm.run('c:SPA', [None, 'Coversize', 'Rectangle', None,
                     140.0, 60.0, 'Yes', '90',
                     'Yes', 'No', 'No', '4-3'])
    picks = [p for p, _ in vm.prompts if 'Spa Cover Details' in p]
    assert len(picks) == 1, picks
    assert 'Nothing there' not in ''.join(vm.printed)


# ------------------------------- the second outline, octagon and round

def test_the_octagon_cover_is_the_water_s_edge_offset_by_the_lap():
    """Enter at 'Draw the cover size as well' (Yes), Enter at 'Take it
    from' (Offset), Enter at the lap (6"): every cover edge runs parallel
    to its water's-edge edge, 6" out -- the cut faces included, which
    is the one part of the offset that is not a plain shift."""
    vm = run([None, 'Watersedge', 'OCtagon', None,
              95.0, None, 'NA', 'NA', 'NA', 'NA', 'NA',
              'Yes', 'No',            # auto-hinge, no spillway
              None, None, None,       # as well: Yes, Offset, 6" lap
              '4-3'],                 # the taper the hinges need
             'octagon/second-outline')
    pool, _ = plverts(vm, 'POOL')
    cover, _ = plverts(vm, 'COVER')
    assert len(pool) == 8 and len(cover) == 8, (pool, cover)
    for i in range(8):
        a, b = pool[i], pool[(i + 1) % 8]
        c, d = cover[i], cover[(i + 1) % 8]
        ex, ey = b[0] - a[0], b[1] - a[1]
        el = (ex * ex + ey * ey) ** 0.5
        cross = ex * (d[1] - c[1]) - ey * (d[0] - c[0])
        assert abs(cross) < 1e-6, ("edge %d not parallel" % i, a, b, c, d)
        off = abs(ex * (c[1] - a[1]) - ey * (c[0] - a[0])) / el
        assert abs(off - 6.0) < 1e-6, ("edge %d is %.6f out" % (i, off))
    assert hinge_labels(vm), "no hinges on the second outline's cover"


def test_the_round_cover_is_the_water_s_edge_plus_the_lap():
    vm = run([None, 'Watersedge', 'ROund', None,
              84.0,
              'No',                   # no auto-hinge
              None, None, None],      # as well: Yes, Offset, 6" lap
             'round/second-outline')
    assert [d[40] for d in drawn(vm, 'CIRCLE', 'POOL')] == [42.0]
    assert [d[40] for d in drawn(vm, 'CIRCLE', 'COVER')] == [48.0]


def test_a_corner_spillway_follows_the_quarter_turn():
    """60 x 100 typed the tall way round is turned a quarter turn, and a
    corner spillway turns with it: the report names it as MEASURED and
    says where it was drawn.  Before this no test had a corner spillway
    at all, so the corner half of the turn table was never read."""
    script = ['Yes', 'Corner', 'BottomLeft', 20.0,  # one corner spillway
              'No', 'No', '4-3']
    vm = run([None, 'Coversize', 'Rectangle', None, 60.0, 100.0,
              'Yes', '90', 'Yes'] + script, 'turn/corner-spill')
    w, l = cover_size(vm)
    assert abs(w - 100.0) < 1e-9 and abs(l - 60.0) < 1e-9, (w, l)
    txt = [d[1] for d in drawn(vm, 'TEXT', 'SPA-NOTES')]
    assert 'SPILLWAY BOTTOMLEFT (DRAWN TOPLEFT)' in txt, txt
    assert hinge_labels(vm), "no hinge drawn"
    # the same spillway on a spa that is NOT turned keeps its name
    vm = run([None, 'Coversize', 'Rectangle', None, 100.0, 60.0,
              'Yes', '90', 'Yes'] + script, 'turn/corner-spill-straight')
    txt = [d[1] for d in drawn(vm, 'TEXT', 'SPA-NOTES')]
    assert 'SPILLWAY BOTTOMLEFT' in txt, txt



# ------------------------------------------ corner callouts, POOL's way

MIXED = ['No', 'Radius', 12.0, 'Diagonal', 10.0, '90', 'NotGiven']


def test_mixed_corners_are_called_out_like_a_pool_rectangle():
    """POOL's rectangle rule: the two overalls, as true LINEAR dims, and
    every corner called out on its own -- and nothing else.  SPA used to
    add an inboard FLAT dim on every side a cut had shortened, which
    POOL never draws and which crowded the corner callouts."""
    vm = run([None, 'Coversize', 'Rectangle', None, 84.0, 60.0]
             + MIXED + ['No', 'No'], 'callouts/mixed')
    lin = dimcalls(vm, '_.DIMLINEAR')
    assert len(lin) == 2, lin                      # the overalls, no flats
    assert sorted(c[3] for c in lin) == ['_H', '_V'], lin
    assert all(override(c) == '<>\\XCover Size' for c in lin), lin
    # the cut face is the only aligned dim, and it carries no Typ.
    al = dimcalls(vm, '_.DIMALIGNED')
    assert len(al) == 1 and override(al[0]) is None, al
    assert len(radcalls(vm)) == 1 and override(radcalls(vm)[0]) is None
    assert sorted(override(c) for c in markcalls(vm)) == ['90%%d', '?']


def test_the_second_outline_gets_its_own_callouts_inward():
    """Mixed corners and a water's edge: the water's edge used to get no
    corner callouts at all (only an all-same one earned its Typ.).  It
    is called out corner by corner now, and -- being the INNER outline
    -- its callouts read inward, so they cannot land on the cover's."""
    vm = run([None, 'Coversize', 'Rectangle', None, 84.0, 60.0]
             + MIXED + ['No', 'Yes', 'Offset', 3.0], 'callouts/mixed-two')
    rads = radcalls(vm)
    assert len(rads) == 2, rads                    # A on each outline
    cover, water = rads
    # the cover's reads out past the arc, the water's edge's back in
    # towards the spa's centre (42, 30) -- and short of the arc's own
    # centre, or DIMRADIUS would measure the far side of the circle
    cen = (42.0, 30.0)
    dist = lambda p: ((p[0] - cen[0]) ** 2 + (p[1] - cen[1]) ** 2) ** 0.5
    ctip, cloc = cover[1][1], cover[-1]
    wtip, wloc = water[1][1], water[-1]
    assert dist(cloc) > dist(ctip), cover
    assert dist(wloc) < dist(wtip), water
    assert ((wloc[0] - wtip[0]) ** 2 + (wloc[1] - wtip[1]) ** 2) ** 0.5 \
        < 9.0, water                               # the 9" water radius
    assert sorted(override(c) for c in markcalls(vm)) == \
        ['90%%d', '90%%d', '?', '?'], [override(c) for c in markcalls(vm)]
    assert len([c for c in vm.commands if c and c[0] == '_.LEADER']) == 2
    assert len(dimcalls(vm, '_.DIMALIGNED')) == 2  # a cut face on each
    assert not stray_arcs(vm)


def test_all_same_second_outline_keeps_one_typ_each():
    """Four matching corners: one Typ. per outline, the cover's at the
    bottom-right and the water's edge's at the top-left."""
    vm = run([None, 'Coversize', 'Rectangle', None, 84.0, 60.0,
              'Yes', 'Diagonal', 10.0, 'No', 'Yes', 'Offset', 3.0],
             'callouts/same-two')
    al = dimcalls(vm, '_.DIMALIGNED')
    assert [override(c) for c in al] == ['<> Typ.', '<> Typ.'], al
    assert al[0][1][0] > 42.0 and al[0][1][1] < 30.0, al[0]   # B
    assert al[1][1][0] < 42.0 and al[1][1][1] > 30.0, al[1]   # D


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
