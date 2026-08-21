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
    lines = drawn(vm, 'LINE', 'COVER')
    xs = [p[0] for d in lines for p in (d[10], d[11])]
    ys = [p[1] for d in lines for p in (d[10], d[11])]
    assert abs((max(xs) - min(xs)) - 84.0) < 1e-9
    assert abs((max(ys) - min(ys)) - 84.0) < 1e-9, (max(ys) - min(ys))


def test_rectangle_can_decline_the_suggestion():
    vm = run([None, 'Coversize', 'Rectangle', None,
              84.0, 60.0,      # decline: type a different length
              '90', None, None, None,
              'No', 'No'],
             'rect/decline')
    lines = drawn(vm, 'LINE', 'COVER')
    ys = [p[1] for d in lines for p in (d[10], d[11])]
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
              'Yes', 'Offset',
              'Back',              # back out of the lap
              'Yes', 'Dims',       # ... and switch method
              78.0, None,          # water's edge overalls
              'No'],               # no auto-hinge
             'rect/back-out-of-offset')
    assert drawn(vm, 'LINE', 'POOL'), "the second outline was never drawn"


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


# -------------------------------------------------------------- hinges

def test_five_piece_hinge_arrangement():
    """A cover wide enough for 5 pieces reads H V V H."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              230.0, 60.0,          # 230/48 -> 5 pieces
              '90', None, None, None,
              'No',                 # no second outline
              'Yes',                # auto-hinge
              'No',                 # no spillaway
              None,                 # no details block
              '4-3'],               # taper
             'hinge/5-piece')
    assert hinge_labels(vm) == ['Hinge', 'Velcro Hinge',
                                'Velcro Hinge', 'Hinge'], hinge_labels(vm)


def test_three_piece_hinge_arrangement():
    vm = run([None, 'Coversize', 'Rectangle', None,
              140.0, 60.0,          # 140/48 -> 3 pieces
              '90', None, None, None,
              'No', 'Yes', 'No', None, '4-3'],
             'hinge/3-piece')
    assert hinge_labels(vm) == ['Hinge', 'Velcro Hinge'], hinge_labels(vm)


def test_back_in_the_spillaway_loop():
    """Back at the top of the loop drops the spillaway just committed."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              140.0, 60.0,
              '90', None, None, None,
              'No', 'Yes',
              'Yes', 'Wall', 'Top', 20.0,   # commit one
              'Back',                        # ... and take it back
              'No',
              None, '4-3'],
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
    assert drawn(vm, 'LINE', 'COVER')


def test_thermolight_style_all_velcro():
    """With no block the grade is Standard; the all-velcro path is
    exercised through the taper instead."""
    vm = run([None, 'Coversize', 'Rectangle', None,
              230.0, 60.0,
              '90', None, None, None,
              'No', 'Yes', 'No', None, '1-3/8'],
             'hinge/thermolight-taper')
    assert hinge_labels(vm), "no hinges drawn"


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
