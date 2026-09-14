# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for PERPMARK.lsp: load the real file into the repo's
AutoLISP interpreter and drive c:PERPMARK from a script.

The command is a geometry pipeline with a loop in the middle, so the
things worth pinning are the numbers that come out of it: where a mark's
base point landed once the pick was projected onto the wall, which way
the perpendicular ran, what STATION each mark got (the polyline's order
depends on nothing else), and which marks a start/end pair encloses --
including the pair that wraps past a closed polyline's own seam.

The scripted answers are the prompts in order: the perimeter for entsel,
then a point for the centre, then point/distance per mark, nil for the
Enter that ends the round, the Yes/No, and the two run ends.

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


# ---- drawing scaffolding ---------------------------------------------

def newvm(dimstyles=('STANDARD', 'SIDE STANDARD')):
    vm = VM()
    vm.load(LSP)
    for s in dimstyles:
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    return vm


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


def near(a, b, eps=1e-6):
    return abs(a - b) <= eps


def pts_near(got, want, eps=1e-6):
    return len(got) == len(want) and all(
        near(g[0], w[0], eps) and near(g[1], w[1], eps)
        for g, w in zip(got, want))


# ---- the pipeline end to end ------------------------------------------

def test_the_whole_run():
    """Three marks off the bottom wall, joined between two picks that are
    not marks themselves: the polyline runs along the wall in order, the
    circles go, and every measured line comes back as a dimension."""
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 12.0,
             [60., 0., 0.], 18.0,
             [100., 0., 0.], 12.0,
             None, "Yes", [5., 0., 0.], [115., 0., 0.]])
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
    run(vm, [vm.entities[0], [60., 30., 0.], [40., 0., 0.], 9.0, None, "No"])
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
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 12.0, [80., 0., 0.], 6.0, None, "No"])
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
    run(vm, [vm.entities[0], [60., 30., 0.], None])
    assert len(live(vm, 'LWPOLYLINE')) == 1
    assert live(vm, 'CIRCLE') == [] and live(vm, 'LINE') == []
    assert not any('polyline through' in p[0] for p in vm.prompts), vm.prompts
    print("ok  no marks    -> nothing drawn, nothing asked")


# ---- projection and direction -----------------------------------------

def test_a_pick_off_the_wall_is_projected_onto_it():
    """'if point is not on the perimeter, use the location on the
    perimeter closest to said point' -- both the circle and the line."""
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.], [37., -9., 0.], 12.0, None, "No"])
    assert pts_near([live(vm, 'CIRCLE')[0][10][:2]], [(37, 0)])
    line = live(vm, 'LINE')[0]
    assert pts_near([line[10][:2], line[11][:2]], [(37, 0), (37, 12)]), line
    print("ok  projection  -> a pick 9 off the wall marks the wall")


def test_the_centre_click_decides_which_way_a_mark_runs():
    """The same pick on the same wall, with the centre on either side."""
    ends = []
    for centre in ([60., 30., 0.], [60., -30., 0.]):
        vm = newvm()
        rect(vm)
        run(vm, [vm.entities[0], centre, [40., 0., 0.], 10.0, None, "No"])
        ends.append(round(live(vm, 'LINE')[0][11][1], 6))
    assert ends == [10.0, -10.0], ends
    print("ok  direction   -> the mark follows the centre click, both ways")


def test_marks_come_off_an_arc_radially():
    """On a curve the perpendicular is the normal of the tangent, which
    on an arc is the radius -- so the far end sits r - d from the centre."""
    vm = newvm()
    arc(vm, (0, 0), 100.0, 0.0, math.pi)        # the upper half, CCW
    run(vm, [vm.entities[0], [0., 0., 0.],
             [0., 100., 0.], 10.0,              # the top of the arc
             [100., 0., 0.], 10.0,              # its right-hand end
             None, "No"])
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
    # centre (50,50), r = 100/(2 sin45) ; the arc bows BELOW the chord
    r = 100.0 / (2.0 * math.sin(math.radians(45.0)))
    run(vm, [vm.entities[0], [50., 50., 0.], [50., -25., 0.], 8.0, None, "No"])
    ln = live(vm, 'LINE')[0]
    assert near(math.dist((50.0, 50.0), ln[10][:2]), r, 1e-9), ln
    assert near(math.dist((50.0, 50.0), ln[11][:2]), r - 8.0, 1e-9), ln
    print("ok  bulge       -> a bulged segment is read as the arc it is")


def test_a_curve_this_file_cannot_read_is_measured_through_vlax_curve():
    """A SPLINE has no segment list here, so the same three numbers come
    from AutoCAD instead.  The shims stand in for a straight spline
    running (0,0) -> (100,0), which is all the fallback needs to be
    driven through."""
    vm = newvm()
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'SPLINE'), Dot(8, 'POOL')]
    vm.loads('''
      (defun vlax-curve-getClosestPointTo (e p) (list (car p) 0.0))
      (defun vlax-curve-getDistAtPoint (e p) (car p))
      (defun vlax-curve-getParamAtPoint (e p) (car p))
      (defun vlax-curve-getFirstDeriv (e prm) (list 1.0 0.0))
      (defun vlax-curve-getEndParam (e) 100.0)
      (defun vlax-curve-getDistAtParam (e prm) prm)
      (defun vlax-curve-isClosed (e) nil)
    ''')
    run(vm, [e, [50., 40., 0.], [30., 5., 0.], 7.0, [70., -3., 0.], 4.0,
             None, "Yes", [10., 1., 0.], [90., 0., 0.]])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(10, 0), (30, 7), (70, 4), (90, 0)]), \
        verts(vm, drawn_pline(vm))
    print("ok  vlax fall   -> a SPLINE perimeter measures through COM")


# ---- order along the wall ---------------------------------------------

def test_the_polyline_runs_in_wall_order_not_click_order():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [100., 0., 0.], 12.0,
             [20., 0., 0.], 6.0,
             [60., 0., 0.], 18.0,
             None, "Yes", [0., 0., 0.], [120., 0., 0.]])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(0, 0), (20, 6), (60, 18), (100, 12), (120, 0)]), \
        verts(vm, drawn_pline(vm))
    print("ok  wall order  -> marks clicked out of order come out in order")


def test_a_run_picked_backwards_comes_out_backwards():
    """On an open wall the run reads from the START pick toward the END
    pick, whichever way along the wall that is."""
    vm = newvm()
    pline(vm, [(0, 0), (120, 0)], closed=False)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 6.0,
             [60., 0., 0.], 18.0,
             [100., 0., 0.], 12.0,
             None, "Yes", [110., 0., 0.], [10., 0., 0.]])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(110, 0), (100, 12), (60, 18), (20, 6), (10, 0)]), \
        verts(vm, drawn_pline(vm))
    print("ok  backwards   -> start -> end, down the wall the other way")


def test_the_run_stops_at_the_picks():
    """A mark outside the two picks keeps its dimension but stays off the
    polyline -- the picks say where the feature is, not where the tape
    was run."""
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 6.0,
             [60., 0., 0.], 18.0,
             [100., 0., 0.], 12.0,
             None, "Yes", [10., 0., 0.], [70., 0., 0.]])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(10, 0), (20, 6), (60, 18), (70, 0)]), \
        verts(vm, drawn_pline(vm))
    assert len(live(vm, 'DIMENSION')) == 3, "every mark is still dimensioned"
    print("ok  run extent  -> the far mark is dimensioned but not joined")


def test_a_run_wraps_past_a_closed_polylines_seam():
    """Stations 350 and 20 on a 360-long perimeter are 30 apart forward,
    across the point the polyline was drawn from."""
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [0., 5., 0.], 8.0,          # station 355, on the left wall
             [10., 0., 0.], 6.0,         # station 10, on the bottom
             [60., 0., 0.], 18.0,        # station 60 - outside the run
             None, "Yes", [0., 10., 0.], [20., 0., 0.]])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(0, 10), (8, 5), (10, 6), (20, 0)]), \
        verts(vm, drawn_pline(vm))
    print("ok  seam        -> the run crosses the polyline's own seam")


# ---- the run ends -----------------------------------------------------

def test_a_run_end_that_lands_on_a_mark_takes_its_distance():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 6.0,
             [60., 0., 0.], 18.0,
             None, "Yes", [21., 0., 0.], [60., 0., 0.]])
    assert pts_near(verts(vm, drawn_pline(vm)), [(20, 6), (60, 18)]), \
        verts(vm, drawn_pline(vm))
    print("ok  end snaps   -> a pick within the snap IS that mark")


def test_a_run_end_with_no_distance_measures_zero():
    """'if they do so, assume its distance from said point is zero' --
    the polyline ties back into the wall."""
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.], [60., 0., 0.], 18.0,
             None, "Yes", [30., 0., 0.], [90., 0., 0.]])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(30, 0), (60, 18), (90, 0)]), verts(vm, drawn_pline(vm))
    print("ok  end at zero -> an unmeasured pick ties back into the wall")


def test_the_snap_is_the_tunable_that_decides_which():
    vm = newvm()
    vm.loads('(setq pm:*snap* 0.0)')
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 6.0,
             [60., 0., 0.], 18.0,
             None, "Yes", [21., 0., 0.], [60., 0., 0.]])
    # the pick is now a station of its own at 21, which puts the mark at
    # 20 behind the start of the run and off the polyline
    assert pts_near(verts(vm, drawn_pline(vm)), [(21, 0), (60, 18)]), \
        verts(vm, drawn_pline(vm))
    print("ok  snap knob   -> pm:*snap* 0 makes the same pick a new station")


def test_two_picks_with_nothing_between_them_erase_nothing():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.], [60., 0., 0.], 18.0,
             None, "Yes", [40., 0., 0.], [40., 0., 0.]])
    assert len(live(vm, 'LWPOLYLINE')) == 1, "no polyline was drawable"
    assert len(live(vm, 'CIRCLE')) == 1 and len(live(vm, 'LINE')) == 1, \
        "nothing may be erased when nothing was drawn"
    print("ok  empty run   -> says so and leaves the marks alone")


# ---- going back -------------------------------------------------------

def test_back_takes_the_last_mark_away():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 12.0,
             [60., 0., 0.], 18.0,
             "Back",
             None, "No"])
    circ = live(vm, 'CIRCLE')
    assert len(circ) == 1 and pts_near([circ[0][10][:2]], [(20, 0)]), circ
    assert len(live(vm, 'LINE')) == 1
    assert any('Stepping back one point' in s for s in vm.printed), vm.printed
    print("ok  back a mark -> the last circle and line go with it")


def test_back_at_the_first_mark_re_opens_the_centre_question():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             "Back",                       # no marks yet -> the centre
             [60., -30., 0.],              # answered the other way
             [40., 0., 0.], 10.0, None, "No"])
    assert near(live(vm, 'LINE')[0][11][1], -10.0), live(vm, 'LINE')
    assert any('Stepping back one question' in s for s in vm.printed), vm.printed
    print("ok  back to ctr -> the centre question is re-asked and re-used")


def test_back_at_the_distance_re_asks_the_point():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], "Back",
             [80., 0., 0.], 5.0, None, "No"])
    circ = live(vm, 'CIRCLE')
    assert len(circ) == 1 and pts_near([circ[0][10][:2]], [(80, 0)]), circ
    print("ok  back a dist -> no mark is left behind by the abandoned pick")


def test_back_at_the_polyline_question_carries_on_marking():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 6.0,
             None, "Back",                 # not done after all
             [60., 0., 0.], 18.0,
             None, "No"])
    assert len(live(vm, 'CIRCLE')) == 2, live(vm, 'CIRCLE')
    print("ok  back at Y/N -> the round re-opens and takes another mark")


def test_back_walks_the_two_run_ends():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [60., 0., 0.], 18.0, None, "Yes",
             [30., 0., 0.], "Back",        # back to the start pick
             [40., 0., 0.], [90., 0., 0.]])
    assert pts_near(verts(vm, drawn_pline(vm)),
                    [(40, 0), (60, 18), (90, 0)]), verts(vm, drawn_pline(vm))
    print("ok  back at end -> the start pick is re-asked and replaced")


def test_back_at_the_centre_re_opens_the_selection():
    vm = newvm()
    rect(vm)
    other = pline(vm, [(200, 0), (320, 0)], closed=False, layer='OTHER')
    run(vm, [vm.entities[0], "Back",
             other, [260., 30., 0.], [240., 0., 0.], 9.0, None, "No"])
    ln = live(vm, 'LINE')[0]
    assert pts_near([ln[10][:2], ln[11][:2]], [(240, 0), (240, 9)]), ln
    print("ok  back to sel -> a second perimeter can be selected instead")


# ---- output placement --------------------------------------------------

def test_the_polyline_inherits_the_perimeter():
    vm = newvm()
    pline(vm, [(0, 0), (120, 0)], closed=False, layer='WALLS',
          extra=[Dot(62, 3), Dot(6, 'HIDDEN'), Dot(370, 25), Dot(48, 2.0)])
    run(vm, [vm.entities[0], [60., 30., 0.], [60., 0., 0.], 18.0,
             None, "Yes", [20., 0., 0.], [100., 0., 0.]])
    g = groups(vm, drawn_pline(vm))
    assert g[8] == 'WALLS' and g[62] == 3 and g[6] == 'HIDDEN' \
        and g[370] == 25 and g[48] == 2.0, g
    print("ok  inherits    -> layer, colour, linetype, weight and scale")


def test_the_layers_are_created_and_the_settings_come_back():
    vm = newvm()
    vm.sysvars['CLAYER'] = '0'
    vm.sysvars['OSMODE'] = 33
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.], [60., 0., 0.], 18.0,
             None, "Yes", [20., 0., 0.], [100., 0., 0.]])
    assert 'PERPMARK' in vm.tables['LAYER'], sorted(vm.tables['LAYER'])
    assert 'DIMENSION' in vm.tables['LAYER'], sorted(vm.tables['LAYER'])
    assert vm.sysvars['CLAYER'] == '0', vm.sysvars['CLAYER']
    assert vm.sysvars['OSMODE'] == 33, vm.sysvars['OSMODE']
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars['DIMSTYLE']
    print("ok  settings    -> layers made, CLAYER/OSMODE/DIMSTYLE restored")


def test_a_drawing_without_the_style_is_told_so():
    vm = newvm(dimstyles=('STANDARD',))
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.], [60., 0., 0.], 18.0,
             None, "Yes", [20., 0., 0.], [100., 0., 0.]])
    assert any('SIDE STANDARD' in s and 'not in this drawing' in s
               for s in vm.printed), vm.printed
    assert len(live(vm, 'DIMENSION')) == 1, "the dimension still goes in"
    print("ok  no style    -> says so and dimensions in the current style")


def test_the_knobs_reach_the_output():
    vm = newvm(dimstyles=('STANDARD', 'CROSS DIMENSIONS'))
    vm.loads('(setq pm:*marklayer* "SCRATCH" pm:*markcolor* 5 '
             '       pm:*dimlayer* "DIMS" pm:*dimcolor* 2 '
             '       pm:*dimstyle* "CROSS DIMENSIONS")')
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.], [60., 0., 0.], 18.0,
             None, "Yes", [20., 0., 0.], [100., 0., 0.]])
    assert live(vm, 'DIMENSION')[0][8] == 'DIMS'
    assert live(vm, 'DIMENSION')[0][3] == 'CROSS DIMENSIONS'
    assert 'SCRATCH' in vm.tables['LAYER'] and 'DIMS' in vm.tables['LAYER']
    print("ok  knobs       -> layers, colours and the dim style all move")


# ---- the session it hands back ----------------------------------------

def test_one_undo_group_wraps_the_whole_run():
    vm = newvm()
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.],
             [20., 0., 0.], 6.0, [60., 0., 0.], 18.0,
             None, "Yes", [10., 0., 0.], [100., 0., 0.]])
    marks = [c[1] for c in vm.commands if c and c[0] == '_.UNDO']
    assert marks == ['_Begin', '_End'], marks
    print("ok  undo group  -> one Begin, one End, the marks inside both")


def test_undo_off():
    """A drawing with UNDO off (bit 1 of UNDOCTL clear) must not be sent
    an _End for a group that was never opened."""
    vm = newvm()
    vm.sysvars['UNDOCTL'] = 0
    rect(vm)
    run(vm, [vm.entities[0], [60., 30., 0.], [60., 0., 0.], 18.0,
             None, "Yes", [20., 0., 0.], [100., 0., 0.]])
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

    def esc(_vm):
        raise LispError('Function cancelled', _vm)

    vm.run('c:PERPMARK', [vm.entities[0], [60., 30., 0.],
                          [20., 0., 0.], 6.0, [60., 0., 0.], esc])
    assert vm.sysvars['OSMODE'] == 33, vm.sysvars['OSMODE']
    assert vm.undo_groups == 0
    assert not any('PERPMARK error' in s for s in vm.printed), vm.printed
    print("ok  esc         -> handled quietly, settings back, group closed")


# ---- what the file itself has to look like ----------------------------

def test_nothing_leaks_out_of_the_command():
    """Every variable c:PERPMARK sets is one of its own locals.  A leak
    here is a value the NEXT run starts with."""
    src = open(os.path.join(HERE, '..', 'lisp', 'perpmark',
                            'PERPMARK.lsp')).read()
    cut = src.index('(defun c:PERPMARK ')
    body = src[cut:]
    decl = re.search(r'\(defun c:PERPMARK \(/(.*?)\)\n', body, re.S).group(1)
    known = set(decl.split()) | {'pm:*sysold*'}
    setqs = re.findall(r'\(setq\s+([^\s()]+)', body)
    leaked = sorted({s for s in setqs
                     if s not in known and not s.startswith(';')})
    assert not leaked, f"c:PERPMARK leaks {leaked}"
    print("ok  no leaks    -> every setq in the command is a declared local")


def test_no_local_shadows_a_function_it_calls():
    src = open(os.path.join(HERE, '..', 'lisp', 'perpmark',
                            'PERPMARK.lsp')).read()
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
    test_a_pick_off_the_wall_is_projected_onto_it()
    test_the_centre_click_decides_which_way_a_mark_runs()
    test_marks_come_off_an_arc_radially()
    test_marks_come_off_a_bulged_polyline_segment_radially()
    test_a_curve_this_file_cannot_read_is_measured_through_vlax_curve()
    test_the_polyline_runs_in_wall_order_not_click_order()
    test_a_run_picked_backwards_comes_out_backwards()
    test_the_run_stops_at_the_picks()
    test_a_run_wraps_past_a_closed_polylines_seam()
    test_a_run_end_that_lands_on_a_mark_takes_its_distance()
    test_a_run_end_with_no_distance_measures_zero()
    test_the_snap_is_the_tunable_that_decides_which()
    test_two_picks_with_nothing_between_them_erase_nothing()
    test_back_takes_the_last_mark_away()
    test_back_at_the_first_mark_re_opens_the_centre_question()
    test_back_at_the_distance_re_asks_the_point()
    test_back_at_the_polyline_question_carries_on_marking()
    test_back_walks_the_two_run_ends()
    test_back_at_the_centre_re_opens_the_selection()
    test_the_polyline_inherits_the_perimeter()
    test_the_layers_are_created_and_the_settings_come_back()
    test_a_drawing_without_the_style_is_told_so()
    test_the_knobs_reach_the_output()
    test_one_undo_group_wraps_the_whole_run()
    test_undo_off()
    test_esc_mid_round()
    test_nothing_leaks_out_of_the_command()
    test_no_local_shadows_a_function_it_calls()
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print(f"all PERPMARK tests passed  [{tier}]")
