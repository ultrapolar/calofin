# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for PERPMARK.lsp: load the real file into the repo's
AutoLISP interpreter and drive c:PERPMARK from a script.

What the command marks is a SURVEY POINT -- one of the numbered shots
ABHD, CABHD, ABFIND, BPCALLOUT, CDCALLOUT and LHD all read -- so half of
what is worth pinning is the naming: a click landing on the right point,
a typed number finding it, and the spellings ("17", "Pt.17", "#17",
"017") meeting in the middle.  The other half is the geometry: where the
base point landed once the point was projected onto the wall, which way
the perpendicular ran, what STATION each mark got (the polyline's order
depends on nothing else), and which marks a start/end pair encloses --
including the pair that wraps past a closed polyline's own seam.

The scripted answers are the prompts in order: the perimeter for entsel,
a point for the centre, then point/distance per mark (a point is a click
[x, y, 0.0] or a typed string), nil for the Enter that ends the round,
the Yes/No, the two run ends and the dimension style.

Run: python3 tests/test_perpmark.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_perpmark.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Ent, Dot, LispError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LSP = os.path.join(HERE, '..', 'lisp', 'perpmark', 'PERPMARK.lsp')

#: the answer to the dimension-style question, which every run that
#: actually draws has to give.  Its own test drives both answers and the
#: Enter; everywhere else it is scaffolding, so one spelling is enough.
STY = "SIde"


# ---- drawing scaffolding ---------------------------------------------

def newvm(dimstyles=('STANDARD', 'STANDARD INCHES',
                     'SIDE STANDARD')):
    vm = VM()
    vm.load(LSP)
    for s in dimstyles:
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    return vm


def ab_pt(vm, x, y, number, layer='POINTS', block='ab_pt', tag='number'):
    """A survey point: the INSERT and the ATTRIB naming it, as a drawing
    carries them.  number None = a block with no attribute at all."""
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'INSERT'), Dot(8, layer), Dot(2, block),
                     [10, float(x), float(y), 0.0]]
    if number is not None:
        att = Ent()
        vm.entities.append(att)
        vm.entdata[att] = [Dot(0, 'ATTRIB'), Dot(2, tag), Dot(1, str(number))]
    return e


def pline(vm, pts, closed=True, layer='POOL', extra=()):
    """An LWPOLYLINE.  PTS entries are (x, y) or (x, y, bulge)."""
    e = Ent()
    vm.entities.append(e)
    d = [Dot(0, 'LWPOLYLINE'), Dot(8, layer), Dot(90, len(pts)),
         Dot(70, 1 if closed else 0)]
    for p in pts:
        d.append([10, float(p[0]), float(p[1])])
        if len(p) > 2:
            d.append(Dot(42, float(p[2])))
    d.extend(extra)
    vm.entdata[e] = d
    return e


def arc(vm, ctr, r, a0, a1, layer='POOL'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'ARC'), Dot(8, layer),
                     [10, float(ctr[0]), float(ctr[1]), 0.0],
                     Dot(40, float(r)), Dot(50, float(a0)), Dot(51, float(a1))]
    return e


def rect(vm, **kw):
    """The reference pool: 120 x 60, drawn from its bottom-left corner
    counterclockwise, so the bottom wall runs station 0 -> 120."""
    return pline(vm, [(0, 0), (120, 0), (120, 60), (0, 60)], **kw)


def bottom_wall_points(vm, *xs):
    """One survey point per x along the bottom wall, numbered from 1."""
    return [ab_pt(vm, x, 0, i + 1) for i, x in enumerate(xs)]


def run(vm, script, label='PERPMARK'):
    try:
        vm.run('c:PERPMARK', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def groups(vm, e):
    """The entity's DXF groups as {code: value}, first value per code."""
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


def verts(vm, e):
    return [(round(g[1], 6), round(g[2], 6)) for g in vm.entdata[e]
            if isinstance(g, list) and g and g[0] == 10]


def drawn_pline(vm):
    """The polyline the run built: the newest live LWPOLYLINE.  The
    perimeter a scenario hands in is always the first entity, so the one
    the run drew is the last -- and never that."""
    out = [e for e in vm.entities
           if e not in vm.deleted and groups(vm, e).get(0) == 'LWPOLYLINE']
    assert out, "no polyline was drawn"
    assert out[-1] is not vm.entities[0], "only the perimeter is there"
    return out[-1]


def said(vm, text):
    return any(text in s for s in vm.printed)


def near(a, b, eps=1e-6):
    return abs(a - b) <= eps


def pts_near(got, want, eps=1e-6):
    return len(got) == len(want) and all(
        near(g[0], w[0], eps) and near(g[1], w[1], eps)
        for g, w in zip(got, want))


# ---- the pipeline end to end ------------------------------------------

def test_the_whole_run():
    """Three points taped off the bottom wall, joined between two that
    were not: the polyline runs along the wall in order, the circles go,
    and every measured line comes back as a dimension."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 5, 20, 60, 100, 115)   # Pt.1 .. Pt.5
    run(vm, [vm.entities[0],
             "2", 12.0,
             "3", 18.0,
             "4", 12.0,
             None, "Yes", "1", "5", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(5, 0), (20, 12), (60, 18), (100, 12), (115, 0)]), \
        verts(vm, drawn_pline(vm))
    assert live(vm, 'CIRCLE') == [], "every circle should have been erased"
    assert live(vm, 'LINE') == [], "every line should have become a dimension"
    dims = live(vm, 'DIMENSION')
    assert len(dims) == 3, dims
    assert all(d[8] == 'DIMENSION' for d in dims), dims
    assert all(d[3] == 'SIDE STANDARD' for d in dims), dims
    print("ok  whole run   -> polyline, circles gone, 3 SIDE STANDARD dims")


def test_a_mark_is_a_circle_and_a_line_of_the_same_size():
    """The circle is the swing of the tape and the line is the tape: one
    radius, one length, both off the same base point."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 9.0, None, "No"])
    circ = live(vm, 'CIRCLE')
    line = live(vm, 'LINE')
    assert len(circ) == 1 and len(line) == 1, (circ, line)
    assert near(circ[0][40], 9.0), circ
    assert pts_near([circ[0][10][:2]], [(40, 0)]), circ
    assert pts_near([line[0][10][:2], line[0][11][:2]],
                    [(40, 0), (40, 9)]), line
    print("ok  one mark    -> circle r=9 and a 9-long line off the wall")


def test_no_leaves_every_circle_and_line_alone():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 80)
    run(vm, [vm.entities[0], "1", 12.0, "2", 6.0, None, "No"])
    assert len(live(vm, 'CIRCLE')) == 2
    assert len(live(vm, 'LINE')) == 2
    assert len(live(vm, 'DIMENSION')) == 0
    assert len(live(vm, 'LWPOLYLINE')) == 1, "no polyline should be drawn"
    assert all(g[8] == 'PERPMARK' for g in live(vm, 'CIRCLE') + live(vm, 'LINE'))
    assert vm.dimstyle_log == [], \
        "a run that draws no dimension must not touch the dimension style"
    print("ok  autodraw No -> both marks left whole on layer PERPMARK")


def test_nothing_marked():
    """Enter at the first pick: no marks, so there is nothing to join and
    the polyline question is never put."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20)
    run(vm, [vm.entities[0], None])
    assert len(live(vm, 'LWPOLYLINE')) == 1
    assert live(vm, 'CIRCLE') == [] and live(vm, 'LINE') == []
    assert not any('polyline through' in p[0] for p in vm.prompts), vm.prompts
    print("ok  no marks    -> nothing drawn, nothing asked")


def test_a_drawing_with_no_survey_points_says_so():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0]])
    assert said(vm, "No survey points in this drawing"), vm.printed
    assert not any('survey point, or type' in p[0] for p in vm.prompts)
    print("ok  no points   -> says so before asking for one")


# ---- naming a point ---------------------------------------------------

def test_a_point_is_named_by_click_or_by_number():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 20, 0, 2)
    ab_pt(vm, 60, 0, 3)
    run(vm, [vm.entities[0],
             "2", 6.0,                 # typed
             [60., 1., 0.], 18.0,      # clicked, a hair off the point
             None, "No"])
    ends = sorted(round(ln[11][0], 6) for ln in live(vm, 'LINE'))
    assert ends == [20.0, 60.0], ends
    print("ok  click/type  -> one prompt takes both")


def test_the_spellings_of_a_number_all_meet_in_the_middle():
    for typed in ("17", "Pt.17", "pt 17", "#17", "017"):
        vm = newvm()
        rect(vm)
        ab_pt(vm, 40, 0, 17)
        run(vm, [vm.entities[0], typed, 9.0, None, "No"])
        assert len(live(vm, 'LINE')) == 1, (typed, live(vm, 'LINE'))
    print("ok  spellings   -> 17, Pt.17, pt 17, #17 and 017 all name Pt.17")


def test_the_distance_prompt_names_the_point():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 17)
    run(vm, [vm.entities[0], "17", 9.0, None, "No"])
    assert any("Distance from the perimeter at Pt.17" in p[0]
               for p in vm.prompts), vm.prompts
    print("ok  names it    -> 'Distance from the perimeter at Pt.17'")


def test_a_number_nothing_carries_is_re_asked():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 3)
    run(vm, [vm.entities[0],
             "99",                     # nothing is numbered 99
             "3", 9.0, None, "No"])
    assert said(vm, 'No survey point is numbered "99"'), vm.printed
    assert len(live(vm, 'LINE')) == 1
    print("ok  bad number  -> re-asked where it stands, run carries on")


def test_two_points_with_one_number_are_asked_about():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 20, 0, 4)
    ab_pt(vm, 90, 0, 4)               # the sheet numbers two points 4
    run(vm, [vm.entities[0],
             "4",                      # ambiguous -> re-asked
             [90., 0., 0.], 9.0, None, "No"])
    assert said(vm, "2 points are numbered"), vm.printed
    assert pts_near([live(vm, 'LINE')[0][10][:2]], [(90, 0)])
    print("ok  duplicates  -> named rather than guessed at, click decides")


def test_a_click_on_nothing_is_re_asked():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 3)
    run(vm, [vm.entities[0],
             [40., 200., 0.],          # nowhere near a point
             "3", 9.0, None, "No"])
    assert said(vm, "No survey point there"), vm.printed
    assert len(live(vm, 'LINE')) == 1
    print("ok  empty click -> re-asked, nothing marked by accident")


def test_the_snap_is_how_close_a_click_has_to_land():
    vm = newvm()
    vm.loads('(setq pm:*snap* 12.0)')
    rect(vm)
    ab_pt(vm, 40, 0, 3)
    run(vm, [vm.entities[0],
             [40., 13., 0.],           # 13 away: past the snap
             [40., 11., 0.], 9.0,      # 11 away: inside it
             None, "No"])
    assert said(vm, "No survey point there"), vm.printed
    assert len(live(vm, 'LINE')) == 1
    print("ok  snap knob   -> 13 away misses, 11 away picks the point")


def test_a_point_with_no_readable_number_can_still_be_clicked():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, None)            # a block with no attribute at all
    run(vm, [vm.entities[0], [40., 0., 0.], 9.0, None, "No"])
    assert len(live(vm, 'LINE')) == 1
    assert any("at Pt.?" in p[0] for p in vm.prompts), vm.prompts
    print("ok  unnumbered  -> clickable, and called Pt.? in the prompts")


def test_a_plain_point_on_the_points_layer_counts():
    vm = newvm()
    rect(vm)
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'POINT'), Dot(8, 'POINTS'), [10, 40.0, 0.0, 0.0]]
    run(vm, [vm.entities[0], [40., 0., 0.], 9.0, None, "No"])
    assert len(live(vm, 'LINE')) == 1
    print("ok  plain POINT -> the family's classifier, not just ab_pt")


def test_naming_a_point_twice_replaces_its_mark():
    """The sheet has one distance at a point, so the second answer is a
    correction: the first circle and line go with it."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 3)
    run(vm, [vm.entities[0],
             "3", 9.0,
             "3", 21.0,
             None, "No"])
    assert len(live(vm, 'CIRCLE')) == 1 and len(live(vm, 'LINE')) == 1
    assert near(live(vm, 'CIRCLE')[0][40], 21.0), live(vm, 'CIRCLE')
    assert said(vm, "Pt.3 re-marked"), vm.printed
    print("ok  re-mark     -> one mark per point, the newer distance wins")


# ---- projection and direction -----------------------------------------

def test_a_point_off_the_wall_is_projected_onto_it():
    """A shot that sits off the fitted perimeter still marks the wall."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 37, -9, 3)
    run(vm, [vm.entities[0], "3", 12.0, None, "No"])
    assert pts_near([live(vm, 'CIRCLE')[0][10][:2]], [(37, 0)])
    line = live(vm, 'LINE')[0]
    assert pts_near([line[10][:2], line[11][:2]], [(37, 0), (37, 12)]), line
    print("ok  projection  -> a point 9 off the wall marks the wall")


def test_a_closed_wall_marks_inward_whichever_way_it_is_drawn():
    """A closed wall defines its own inside, so nothing is clicked and
    nothing can be answered wrongly: the same pool drawn the other way
    round marks the same way."""
    ends = []
    for pts in ([(0, 0), (120, 0), (120, 60), (0, 60)],          # CCW
                [(0, 0), (0, 60), (120, 60), (120, 0)]):         # CW
        vm = newvm()
        pline(vm, pts)
        ab_pt(vm, 40, 0, 3)
        run(vm, [vm.entities[0], "3", 10.0, None, "No"])
        ends.append(round(live(vm, 'LINE')[0][11][1], 6))
    assert ends == [10.0, 10.0], ends
    assert said(vm, "The wall closes"), vm.printed
    print("ok  inward      -> a closed wall marks into the water, either way")


def test_a_notched_pool_marks_into_the_water_on_every_wall():
    """The shape a clicked centre got wrong.  On this L the arm's wall
    faces -X while the bottom lobe is off to the +X side, so a centre
    clicked in the lobe put the mark at (50, 80) -- out through the wall
    and into the deck.  The wall's own inside puts it at (30, 80)."""
    vm = newvm()
    pline(vm, [(0, 0), (120, 0), (120, 40), (40, 40), (40, 120), (0, 120)])
    ab_pt(vm, 40, 80, 1)                       # on the arm's right wall
    ab_pt(vm, 60, 0, 2)                        # on the lobe's bottom wall
    run(vm, [vm.entities[0], "1", 10.0, "2", 10.0, None, "No"])
    got = sorted(tuple(round(c, 6) for c in ln[11][:2])
                 for ln in live(vm, 'LINE'))
    assert got == [(30.0, 80.0), (60.0, 10.0)], got
    print("ok  notched     -> both walls mark inward, lobe and arm alike")


def test_an_open_wall_still_asks_which_side_the_pool_is_on():
    """A stretch of wall on its own has no inside, so the question
    survives exactly where it is the only answer there is."""
    ends = []
    for side in ([60., 30., 0.], [60., -30., 0.]):
        vm = newvm()
        pline(vm, [(0, 0), (120, 0)], closed=False)
        ab_pt(vm, 40, 0, 3)
        run(vm, [vm.entities[0], side, "3", 10.0, None, "No"])
        ends.append(round(live(vm, 'LINE')[0][11][1], 6))
    assert ends == [10.0, -10.0], ends
    assert said(vm, "does not close"), vm.printed
    print("ok  open wall   -> the side click still decides, both ways")


def test_marks_come_off_an_arc_radially():
    """On a curve the perpendicular is the normal of the tangent, which
    on an arc is the radius -- so the far end sits r - d from the centre."""
    vm = newvm()
    arc(vm, (0, 0), 100.0, 0.0, math.pi)        # the upper half, CCW
    ab_pt(vm, 0, 100, 1)                        # the top of the arc
    ab_pt(vm, 100, 0, 2)                        # its right-hand end
    run(vm, [vm.entities[0], [0., 0., 0.], "1", 10.0, "2", 10.0, None, "No"])
    for ln in live(vm, 'LINE'):
        assert near(math.hypot(*ln[10][:2]), 100.0), ln
        assert near(math.hypot(*ln[11][:2]), 90.0), ln
    print("ok  arc normal  -> both marks run down the radius")


def test_marks_come_off_a_bulged_polyline_segment_radially():
    """A pool wall is one polyline with arc segments in it, so the bulge
    has to be read as an arc and not chorded."""
    b = math.tan(math.radians(90.0) / 4.0)      # a quarter circle
    vm = newvm()
    pline(vm, [(0, 0, b), (100, 0)], closed=False)
    r = 100.0 / (2.0 * math.sin(math.radians(45.0)))
    ab_pt(vm, 50, -25, 1)
    run(vm, [vm.entities[0], [50., 50., 0.], "1", 8.0, None, "No"])
    ln = live(vm, 'LINE')[0]
    assert near(math.dist((50.0, 50.0), ln[10][:2]), r, 1e-9), ln
    assert near(math.dist((50.0, 50.0), ln[11][:2]), r - 8.0, 1e-9), ln
    print("ok  bulge       -> a bulged segment is read as the arc it is")


def test_a_curve_this_file_cannot_read_is_measured_through_vlax_curve():
    """A SPLINE has no segment list here, so the same three numbers come
    from AutoCAD instead.  The shims stand in for a straight spline
    running (0,0) -> (100,0), which is all the fallback needs."""
    vm = newvm()
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'SPLINE'), Dot(8, 'POOL')]
    bottom_wall_points(vm, 10, 30, 70, 90)
    vm.loads('''
      (defun vlax-curve-getClosestPointTo (e p) (list (car p) 0.0))
      (defun vlax-curve-getDistAtPoint (e p) (car p))
      (defun vlax-curve-getParamAtPoint (e p) (car p))
      (defun vlax-curve-getFirstDeriv (e prm) (list 1.0 0.0))
      (defun vlax-curve-getEndParam (e) 100.0)
      (defun vlax-curve-getDistAtParam (e prm) prm)
      (defun vlax-curve-isClosed (e) nil)
    ''')
    run(vm, [e, [50., 40., 0.], "2", 7.0, "3", 4.0, None, "Yes",
             "1", "4", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(10, 0), (30, 7), (70, 4), (90, 0)]), \
        verts(vm, drawn_pline(vm))
    print("ok  vlax fall   -> a SPLINE perimeter measures through COM")


# ---- order along the wall ---------------------------------------------

def test_the_polyline_runs_in_wall_order_not_naming_order():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 0, 20, 60, 100, 120)
    run(vm, [vm.entities[0],
             "4", 12.0,
             "2", 6.0,
             "3", 18.0,
             None, "Yes", "1", "5", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(0, 0), (20, 6), (60, 18), (100, 12), (120, 0)]), \
        verts(vm, drawn_pline(vm))
    print("ok  wall order  -> points named out of order come out in order")


def test_a_run_picked_backwards_comes_out_backwards():
    """On an open wall the run reads from the START point toward the END
    point, whichever way along the wall that is."""
    vm = newvm()
    pline(vm, [(0, 0), (120, 0)], closed=False)
    bottom_wall_points(vm, 10, 20, 60, 100, 110)
    run(vm, [vm.entities[0], [60., 30., 0.],
             "2", 6.0, "3", 18.0, "4", 12.0,
             None, "Yes", "5", "1", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(110, 0), (100, 12), (60, 18), (20, 6), (10, 0)]), \
        verts(vm, drawn_pline(vm))
    print("ok  backwards   -> start -> end, down the wall the other way")


def test_the_marks_decide_which_way_round_a_closed_wall_the_run_goes():
    """The two ends cut a closed wall into two arcs, and the marks are on
    one of them.  Naming the ends in either order has to give the same
    run -- reading from whichever end was named first.  It did not: the
    other order used to send the run round the empty side and hand back a
    two-point line straight across, every mark left off it."""
    wanted = [(5, 0), (20, 12), (60, 18), (100, 12), (115, 0)]
    for ends, want in (("15", wanted), ("51", list(reversed(wanted)))):
        vm = newvm()
        rect(vm)
        bottom_wall_points(vm, 5, 20, 60, 100, 115)
        run(vm, [vm.entities[0],
                 "2", 12.0, "3", 18.0, "4", 12.0,
                 None, "Yes", ends[0], ends[1], STY])
        assert pts_near(verts(vm, drawn_pline(vm)), want), \
            (ends, verts(vm, drawn_pline(vm)))
        assert not said(vm, "outside the run"), vm.printed
    print("ok  either way  -> the ends can be named in either order")


def test_a_tie_asks_which_way_the_run_passes():
    """Two marks on each arc: nothing but the drafter can choose, so one
    click on the side the run passes through settles it -- and the marks
    on the other side are NAMED, never quietly dropped."""
    for click, want, missed in (
            ([60., 2., 0.], [(5, 0), (20, 12), (60, 18), (115, 60)],
             "Pt.5 and Pt.6"),
            ([40., 58., 0.], [(5, 0), (20, 54), (60, 51), (115, 60)],
             "Pt.2 and Pt.3")):
        vm = newvm()
        rect(vm)                       # 120 x 60, so 360 all the way round
        ab_pt(vm, 5, 0, 1)             # station   5 - the run's start
        ab_pt(vm, 20, 0, 2)            # station  20 - the near arc
        ab_pt(vm, 60, 0, 3)            # station  60 - the near arc
        ab_pt(vm, 115, 60, 4)          # station 185 - the run's end
        ab_pt(vm, 60, 60, 5)           # station 240 - the far arc
        ab_pt(vm, 20, 60, 6)           # station 280 - the far arc
        run(vm, [vm.entities[0],
                 "2", 12.0, "3", 18.0, "5", 9.0, "6", 6.0,
                 None, "Yes", "1", "4", click, STY])
        assert pts_near(verts(vm, drawn_pline(vm)), want), \
            (click, verts(vm, drawn_pline(vm)))
        assert said(vm, missed + " sit outside the run"), vm.printed
    print("ok  tie         -> one click says which way, the rest is named")


def test_a_tie_is_only_asked_about_when_it_is_really_a_tie():
    """Every mark on one arc, or every mark AT one of the two ends: the
    question is not put, because nothing is in doubt."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 60)
    run(vm, [vm.entities[0],
             "1", 6.0, "2", 18.0, None, "Yes", "1", "2", STY])
    assert not any('passes through' in p[0] for p in vm.prompts), vm.prompts
    assert pts_near(verts(vm, drawn_pline(vm)), [(20, 6), (60, 18)])
    print("ok  no tie      -> the question is only put when it has to be")


def test_back_at_the_which_way_click_re_opens_the_end():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 5, 0, 1)
    ab_pt(vm, 20, 0, 2)
    ab_pt(vm, 60, 0, 3)
    ab_pt(vm, 115, 60, 4)
    ab_pt(vm, 60, 60, 5)
    ab_pt(vm, 20, 60, 6)
    run(vm, [vm.entities[0],
             "2", 12.0, "3", 18.0, "5", 9.0, "6", 6.0,
             None, "Yes", "1", "4",
             "Back",                   # the tie click -> back to the end
             "5", STY])                     # ending AT Pt.5 breaks the tie: two
                                       # marks near, one far, no question
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(5, 0), (20, 12), (60, 18), (60, 51)]), \
        verts(vm, drawn_pline(vm))
    assert said(vm, "Pt.6 sits outside the run"), vm.printed
    print("ok  back at tie -> the end point is re-asked and replaced")


def test_the_run_stops_at_the_points_that_end_it():
    """A mark outside the two ends keeps its dimension but stays off the
    polyline -- the ends say where the feature is, not where the tape was
    run."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 10, 20, 60, 100, 70)   # Pt.5 is at x=70
    run(vm, [vm.entities[0],
             "2", 6.0, "3", 18.0, "4", 12.0,
             None, "Yes", "1", "5", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(10, 0), (20, 6), (60, 18), (70, 0)]), \
        verts(vm, drawn_pline(vm))
    assert len(live(vm, 'DIMENSION')) == 3, "every mark is still dimensioned"
    assert said(vm, "Pt.4 sits outside the run"), vm.printed
    print("ok  run extent  -> the far mark is dimensioned, not joined, SAID")


def test_a_run_wraps_past_a_closed_polylines_seam():
    """Stations 350 and 20 on a 360-long perimeter are 30 apart forward,
    across the point the polyline was drawn from."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 0, 5, 1)        # station 355, on the left wall
    ab_pt(vm, 10, 0, 2)       # station 10, on the bottom
    ab_pt(vm, 60, 0, 3)       # station 60 - outside the run
    ab_pt(vm, 0, 10, 4)       # station 350, the run's start
    ab_pt(vm, 20, 0, 5)       # station 20, the run's end
    run(vm, [vm.entities[0],
             "1", 8.0, "2", 6.0, "3", 18.0,
             None, "Yes", "4", "5", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(0, 10), (8, 5), (10, 6), (20, 0)]), \
        verts(vm, drawn_pline(vm))
    print("ok  seam        -> the run crosses the polyline's own seam")


# ---- the run ends -----------------------------------------------------

def test_a_run_end_at_a_taped_point_takes_its_distance():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 60)
    run(vm, [vm.entities[0],
             "1", 6.0, "2", 18.0,
             None, "Yes", "1", "2", STY])
    assert pts_near(verts(vm, drawn_pline(vm)), [(20, 6), (60, 18)]), \
        verts(vm, drawn_pline(vm))
    print("ok  end taped   -> the run starts where the tape reached")


def test_a_run_end_at_an_untaped_point_measures_zero():
    """'a point that does not have a distance provided ... assume its
    distance is zero' -- the polyline ties back into the wall."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 30, 60, 90)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "3", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(30, 0), (60, 18), (90, 0)]), verts(vm, drawn_pline(vm))
    print("ok  end at zero -> an untaped point ties back into the wall")


def test_identity_decides_a_run_end_not_nearness():
    """Two shots an inch apart are two shots.  Naming the untaped one
    starts the run on the wall, even with a marked point beside it."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 30, 0, 1)       # untaped, the run's start
    ab_pt(vm, 31, 0, 2)       # taped, an inch away
    ab_pt(vm, 90, 0, 3)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "3", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(30, 0), (31, 18), (90, 0)]), verts(vm, drawn_pline(vm))
    print("ok  identity    -> the point named is the point used, not its "
          "neighbour")


def test_two_ends_with_nothing_between_them_erase_nothing():
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 1)
    ab_pt(vm, 60, 0, 2)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "1"])
    assert len(live(vm, 'LWPOLYLINE')) == 1, "no polyline was drawable"
    assert len(live(vm, 'CIRCLE')) == 1 and len(live(vm, 'LINE')) == 1, \
        "nothing may be erased when nothing was drawn"
    print("ok  empty run   -> says so and leaves the marks alone")


# ---- going back -------------------------------------------------------

def test_back_takes_the_last_mark_away():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 60)
    run(vm, [vm.entities[0],
             "1", 12.0, "2", 18.0,
             "Back",
             None, "No"])
    circ = live(vm, 'CIRCLE')
    assert len(circ) == 1 and pts_near([circ[0][10][:2]], [(20, 0)]), circ
    assert len(live(vm, 'LINE')) == 1
    assert said(vm, "Stepping back one point - Pt.2 undone"), vm.printed
    print("ok  back a mark -> the last circle and line go, named")


def test_back_at_the_first_mark_re_opens_the_side_question():
    """On an open wall the question before the first mark is the side
    click, and Back re-opens it."""
    vm = newvm()
    pline(vm, [(0, 0), (120, 0)], closed=False)
    ab_pt(vm, 40, 0, 1)
    run(vm, [vm.entities[0], [60., 30., 0.],
             "Back",                       # no marks yet -> the side
             [60., -30., 0.],              # answered the other way
             "1", 10.0, None, "No"])
    assert near(live(vm, 'LINE')[0][11][1], -10.0), live(vm, 'LINE')
    assert said(vm, "Stepping back one question"), vm.printed
    print("ok  back to side-> the side question is re-asked and re-used")


def test_back_at_the_first_mark_re_opens_the_selection_on_a_closed_wall():
    """A closed wall is asked nothing, so the question in front of the
    first mark is the selection itself."""
    vm = newvm()
    rect(vm)
    other = pline(vm, [(200, 0), (320, 0)], closed=False, layer='OTHER')
    ab_pt(vm, 240, 0, 1)
    run(vm, [vm.entities[0],
             "Back",                       # no marks yet -> the selection
             other, [260., 30., 0.],       # a different wall, open
             "1", 9.0, None, "No"])
    ln = live(vm, 'LINE')[0]
    assert pts_near([ln[10][:2], ln[11][:2]], [(240, 0), (240, 9)]), ln
    assert said(vm, "Stepping back one question"), vm.printed
    print("ok  back to sel -> a closed wall steps back to the selection")


def test_back_at_the_distance_re_asks_the_point():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 80)
    run(vm, [vm.entities[0],
             "1", "Back",
             "2", 5.0, None, "No"])
    circ = live(vm, 'CIRCLE')
    assert len(circ) == 1 and pts_near([circ[0][10][:2]], [(80, 0)]), circ
    print("ok  back a dist -> no mark is left behind by the abandoned pick")


def test_back_at_the_polyline_question_carries_on_marking():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 60)
    run(vm, [vm.entities[0],
             "1", 6.0,
             None, "Back",                 # not done after all
             "2", 18.0,
             None, "No"])
    assert len(live(vm, 'CIRCLE')) == 2, live(vm, 'CIRCLE')
    print("ok  back at Y/N -> the round re-opens and takes another mark")


def test_back_walks_the_two_run_ends():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 30, 60, 40, 90)
    run(vm, [vm.entities[0],
             "2", 18.0, None, "Yes",
             "1", "Back",                  # back to the start point
             "3", "4", STY])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(40, 0), (60, 18), (90, 0)]), verts(vm, drawn_pline(vm))
    print("ok  back at end -> the start point is re-asked and replaced")


# ---- output placement --------------------------------------------------

def test_the_polyline_inherits_the_perimeter():
    vm = newvm()
    pline(vm, [(0, 0), (120, 0)], closed=False, layer='WALLS',
          extra=[Dot(62, 3), Dot(6, 'HIDDEN'), Dot(370, 25), Dot(48, 2.0)])
    bottom_wall_points(vm, 20, 60, 100)
    run(vm, [vm.entities[0], [60., 30., 0.], "2", 18.0,
             None, "Yes", "1", "3", STY])
    g = groups(vm, drawn_pline(vm))
    assert g[8] == 'WALLS' and g[62] == 3 and g[6] == 'HIDDEN' \
        and g[370] == 25 and g[48] == 2.0, g
    print("ok  inherits    -> layer, colour, linetype, weight and scale")


# ---- what the round says about its own numbers ------------------------

def test_a_distance_that_fights_both_neighbours_is_named():
    """40, 10 and 30 at three points in a row is a digit, not a wall.
    The round names it, says what the neighbours put there, and changes
    nothing: a surveyed number is the drafter's to correct."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 40, 60)
    run(vm, [vm.entities[0], "1", 40.0, "2", 10.0, "3", 30.0, None, "No"])
    assert said(vm, "Pt.2 measures 10.00, against Pt.1 (40.00) and "
                    "Pt.3 (30.00) on both sides - the wall between them "
                    "is about 35.00."), vm.printed
    assert said(vm, "name Pt.2 again and the new distance replaces it"), \
        vm.printed
    assert sorted(round(c[40], 6) for c in live(vm, 'CIRCLE')) \
        == [10.0, 30.0, 40.0], live(vm, 'CIRCLE')
    print("ok  spike       -> the 10 between a 40 and a 30 is named, not moved")


def test_a_wall_that_bends_is_not_second_guessed():
    """40, 38, 30 is a wall bending away: every value sits between its
    neighbours, so nothing is said however far the middle one is off the
    chord between them."""
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 40, 60)
    run(vm, [vm.entities[0], "1", 40.0, "2", 38.0, "3", 30.0, None, "No"])
    assert not said(vm, "on both sides"), vm.printed
    print("ok  real curve  -> a bend is left alone")


def test_a_mark_that_reaches_past_the_far_wall_is_named():
    """The pool is 60 deep and the tape read 84: one of the two is
    wrong.  The mark is drawn anyway and the point is named."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 7)
    run(vm, [vm.entities[0], "7", 84.0, None, "No"])
    assert said(vm, "Pt.7 reaches past the far wall"), vm.printed
    assert len(live(vm, 'LINE')) == 1, live(vm, 'LINE')
    print("ok  off the map -> a tape that left the pool is named")


def test_the_layers_are_created_and_the_settings_come_back():
    vm = newvm()
    vm.sysvars['CLAYER'] = '0'
    vm.sysvars['OSMODE'] = 33
    rect(vm)
    bottom_wall_points(vm, 20, 60, 100)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "3", STY])
    assert 'PERPMARK' in vm.tables['LAYER'], sorted(vm.tables['LAYER'])
    assert 'DIMENSION' in vm.tables['LAYER'], sorted(vm.tables['LAYER'])
    assert vm.sysvars['CLAYER'] == '0', vm.sysvars['CLAYER']
    assert vm.sysvars['OSMODE'] == 33, vm.sysvars['OSMODE']
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars['DIMSTYLE']
    print("ok  settings    -> layers made, CLAYER/OSMODE/DIMSTYLE restored")


def test_a_drawing_without_the_style_is_told_so():
    vm = newvm(dimstyles=('STANDARD',))
    rect(vm)
    bottom_wall_points(vm, 20, 60, 100)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "3", STY])
    assert said(vm, "SIDE STANDARD") and said(vm, "not in this drawing"), \
        vm.printed   # STY answers SIde, and this drawing has no such style
    assert len(live(vm, 'DIMENSION')) == 1, "the dimension still goes in"
    print("ok  no style    -> says so and dimensions in the current style")


def test_the_knobs_reach_the_output():
    vm = newvm(dimstyles=('STANDARD', 'CROSS DIMENSIONS', 'PLAN'))
    vm.loads('(setq pm:*marklayer* "SCRATCH" pm:*markcolor* 5 '
             '       pm:*dimlayer* "DIMS" pm:*dimcolor* 2 '
             '       pm:*dimstyle-std* "PLAN" '
             '       pm:*dimstyle-side* "CROSS DIMENSIONS" '
             '       pm:*pt-prefix* "P")')
    rect(vm)
    bottom_wall_points(vm, 20, 60, 100)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "3", STY])
    assert live(vm, 'DIMENSION')[0][8] == 'DIMS'
    assert live(vm, 'DIMENSION')[0][3] == 'CROSS DIMENSIONS'
    assert 'SCRATCH' in vm.tables['LAYER'] and 'DIMS' in vm.tables['LAYER']
    assert any("at P2" in p[0] for p in vm.prompts), vm.prompts
    # a renamed style renames it in the question too, so the prompt can
    # never offer a style the routine would not draw in
    assert any("Dimension style - PLAN or CROSS DIMENSIONS?" in p[0]
               for p in vm.prompts), vm.prompts
    print("ok  knobs       -> layers, colours, both dim styles and the prefix")


def test_the_dimension_style_is_asked_the_way_perppts_asks_it():
    """PERPPTS and CPERPPTS put this question in exactly these words, and
    one vocabulary repo-wide is the point (STANDARDS section 3)."""
    for answer, want in (("STandard", "STANDARD INCHES"),
                         ("SIde", "SIDE STANDARD"),
                         (None, "STANDARD INCHES")):        # Enter
        vm = newvm()
        rect(vm)
        bottom_wall_points(vm, 20, 60, 100)
        run(vm, [vm.entities[0], "2", 18.0,
                 None, "Yes", "1", "3", answer])
        assert live(vm, 'DIMENSION')[0][3] == want, (answer, live(vm, 'DIMENSION'))
        assert said(vm, 'in "' + want + '"'), vm.printed
    assert any(p[0] == "\nDimension style - STANDARD INCHES or SIDE "
                       "STANDARD? [STandard/SIde/Back] <STandard>: "
               for p in vm.prompts), vm.prompts
    print("ok  style asked -> PERPPTS's words, both answers and the Enter")


def test_the_style_is_not_asked_when_there_is_nothing_to_draw():
    """Two ends with nothing between them: the run is worked out first,
    so the question is never put only to have its answer thrown away."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 40, 0, 1)
    ab_pt(vm, 60, 0, 2)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "1"])
    assert not any('Dimension style' in p[0] for p in vm.prompts), vm.prompts
    print("ok  style skip  -> not asked when there is no polyline to draw")


def test_back_at_the_style_re_opens_the_end():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 20, 60, 100, 110)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "3",
             "Back",                   # the style question -> the end
             "4", STY])
    assert sum(1 for p in vm.prompts if 'run ends at' in p[0]) == 2, vm.prompts
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(20, 0), (60, 18), (110, 0)]), verts(vm, drawn_pline(vm))
    print("ok  back at sty -> the end point is re-asked and replaced")


def test_the_point_classifier_is_the_familys():
    """An ab_pt INSERT counts wherever it sits; any other INSERT counts
    on the POINTS layer; a lone INSERT elsewhere is not a survey point."""
    vm = newvm()
    rect(vm)
    ab_pt(vm, 20, 0, 1, layer='RANDOM')            # ab_pt off POINTS
    ab_pt(vm, 60, 0, 2, block='SOMETHINGELSE')     # other block, on POINTS
    ab_pt(vm, 90, 0, 3, layer='RANDOM', block='TREE')   # neither
    run(vm, [vm.entities[0],
             "1", 6.0, "2", 8.0,
             "3",                                  # not a survey point
             None, "No"])
    assert said(vm, 'No survey point is numbered "3"'), vm.printed
    assert len(live(vm, 'LINE')) == 2
    print("ok  classifier  -> ab_pt anywhere, any INSERT on POINTS, no more")


# ---- the session it hands back ----------------------------------------

def test_one_undo_group_wraps_the_whole_run():
    vm = newvm()
    rect(vm)
    bottom_wall_points(vm, 10, 20, 60, 100)
    run(vm, [vm.entities[0],
             "2", 6.0, "3", 18.0,
             None, "Yes", "1", "4", STY])
    marks = [c[1] for c in vm.commands if c and c[0] == '_.UNDO']
    assert marks == ['_Begin', '_End'], marks
    print("ok  undo group  -> one Begin, one End, the marks inside both")


def test_undo_off():
    """A drawing with UNDO off (bit 1 of UNDOCTL clear) must not be sent
    an _End for a group that was never opened."""
    vm = newvm()
    vm.sysvars['UNDOCTL'] = 0
    rect(vm)
    bottom_wall_points(vm, 20, 60, 100)
    run(vm, [vm.entities[0], "2", 18.0,
             None, "Yes", "1", "3", STY])
    assert not [c for c in vm.commands if c and c[0] == '_.UNDO'], vm.commands
    assert len(live(vm, 'DIMENSION')) == 1, "and the run still finishes"
    print("ok  undo off    -> no group opened, none closed, run completes")


def test_esc_mid_round():
    """Esc at the second distance: the handler runs once, the settings
    come back and the group is closed."""
    vm = newvm()
    vm.sysvars['OSMODE'] = 33
    vm.handle_errors = True
    rect(vm)
    bottom_wall_points(vm, 20, 60)

    def esc(_vm):
        raise LispError('Function cancelled', _vm)

    vm.run('c:PERPMARK', [vm.entities[0],
                          "1", 6.0, "2", esc])
    assert vm.sysvars['OSMODE'] == 33, vm.sysvars['OSMODE']
    assert vm.undo_groups == 0
    assert not any('PERPMARK error' in s for s in vm.printed), vm.printed
    print("ok  esc         -> handled quietly, settings back, group closed")


# ---- what the file itself has to look like ----------------------------

def test_nothing_leaks_out_of_the_command():
    """Every variable c:PERPMARK sets is one of its own locals.  A leak
    here is a value the NEXT run starts with."""
    src = open(LSP).read()
    body = src[src.index('(defun c:PERPMARK '):]
    decl = re.search(r'\(defun c:PERPMARK \(/(.*?)\)\n', body, re.S).group(1)
    known = set(decl.split()) | {'pm:*sysold*'}
    setqs = re.findall(r'\(setq\s+([^\s()]+)', body)
    leaked = sorted({s for s in setqs
                     if s not in known and not s.startswith(';')})
    assert not leaked, f"c:PERPMARK leaks {leaked}"
    print("ok  no leaks    -> every setq in the command is a declared local")


def test_no_local_shadows_a_function_it_calls():
    src = open(LSP).read()
    called = {m.lower() for m in re.findall(r'\((pm:[a-z0-9:*-]+)', src)}
    bad = []
    for arglist in re.findall(r'\(defun [^\s()]+ \(([^)]*)\)', src):
        for name in arglist.replace('/', ' ').split():
            if name.lower() in called:
                bad.append(name)
    assert not bad, f"locals shadowing functions they call: {sorted(set(bad))}"
    print("ok  no shadow   -> no local hides a function the file calls")


if __name__ == '__main__':
    test_the_whole_run()
    test_a_mark_is_a_circle_and_a_line_of_the_same_size()
    test_no_leaves_every_circle_and_line_alone()
    test_nothing_marked()
    test_a_drawing_with_no_survey_points_says_so()
    test_a_point_is_named_by_click_or_by_number()
    test_the_spellings_of_a_number_all_meet_in_the_middle()
    test_the_distance_prompt_names_the_point()
    test_a_number_nothing_carries_is_re_asked()
    test_two_points_with_one_number_are_asked_about()
    test_a_click_on_nothing_is_re_asked()
    test_the_snap_is_how_close_a_click_has_to_land()
    test_a_point_with_no_readable_number_can_still_be_clicked()
    test_a_plain_point_on_the_points_layer_counts()
    test_naming_a_point_twice_replaces_its_mark()
    test_a_point_off_the_wall_is_projected_onto_it()
    test_a_closed_wall_marks_inward_whichever_way_it_is_drawn()
    test_a_notched_pool_marks_into_the_water_on_every_wall()
    test_an_open_wall_still_asks_which_side_the_pool_is_on()
    test_marks_come_off_an_arc_radially()
    test_marks_come_off_a_bulged_polyline_segment_radially()
    test_a_curve_this_file_cannot_read_is_measured_through_vlax_curve()
    test_the_polyline_runs_in_wall_order_not_naming_order()
    test_a_run_picked_backwards_comes_out_backwards()
    test_the_marks_decide_which_way_round_a_closed_wall_the_run_goes()
    test_a_tie_asks_which_way_the_run_passes()
    test_a_tie_is_only_asked_about_when_it_is_really_a_tie()
    test_back_at_the_which_way_click_re_opens_the_end()
    test_the_run_stops_at_the_points_that_end_it()
    test_a_run_wraps_past_a_closed_polylines_seam()
    test_a_run_end_at_a_taped_point_takes_its_distance()
    test_a_run_end_at_an_untaped_point_measures_zero()
    test_identity_decides_a_run_end_not_nearness()
    test_two_ends_with_nothing_between_them_erase_nothing()
    test_back_takes_the_last_mark_away()
    test_back_at_the_first_mark_re_opens_the_side_question()
    test_back_at_the_first_mark_re_opens_the_selection_on_a_closed_wall()
    test_back_at_the_distance_re_asks_the_point()
    test_back_at_the_polyline_question_carries_on_marking()
    test_back_walks_the_two_run_ends()
    test_the_polyline_inherits_the_perimeter()
    test_a_distance_that_fights_both_neighbours_is_named()
    test_a_wall_that_bends_is_not_second_guessed()
    test_a_mark_that_reaches_past_the_far_wall_is_named()
    test_the_layers_are_created_and_the_settings_come_back()
    test_a_drawing_without_the_style_is_told_so()
    test_the_knobs_reach_the_output()
    test_the_dimension_style_is_asked_the_way_perppts_asks_it()
    test_the_style_is_not_asked_when_there_is_nothing_to_draw()
    test_back_at_the_style_re_opens_the_end()
    test_the_point_classifier_is_the_familys()
    test_one_undo_group_wraps_the_whole_run()
    test_undo_off()
    test_esc_mid_round()
    test_nothing_leaks_out_of_the_command()
    test_no_local_shadows_a_function_it_calls()
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print(f"all PERPMARK tests passed  [{tier}]")
