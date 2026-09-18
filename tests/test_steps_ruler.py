#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The length ruler at the step tread and step depth prompts.

CORNERSTP, HEMISTEP and NORMIESTEP ask a tread per step and, for the
side profile, a depth per step, and the numbers on a real flight are
near-equal: 24, 24, 24 1/2; 7 1/2, 10 3/4, 10 3/4.  From the second
answer on the ruler DIMSTAMP grew stands beside the prompt -- the
eighths for an inch either side of the last answer -- and a click on a
row IS the answer.  What is pinned here:

  * a row clicked at a tread or a depth prompt draws exactly what the
    same number typed draws, in all three routines;
  * the ruler is up at the tread prompt and down at the width prompt
    that follows it, since that prompt cannot take it;
  * a typed fraction reads (10 3/4 is 10.75), Enter at the first depth
    is refused rather than pushing nothing onto the flight, and nothing
    of the ruler is left in the drawing when the run ends.

The prompt wording does not change, which is what keeps the LAZSTEP
form and tests/test_steps_form.py in step with these.

Run: python3 tests/test_steps_ruler.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_steps_ruler.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError  # noqa: E402

HERE = os.path.dirname(__file__)
CORNERSTP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'CORNERSTP.lsp')
HEMISTEP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'HEMISTEP.lsp')
NORMIESTEP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'NORMIESTEP.lsp')

PICK = (500.0, 400.0)
#: the ruler's own colour, the one knob-free way to tell its scratch
#: from the steps, which are ByLayer
RULER_COLOR = 3


def fresh(path):
    vm = VM()
    vm.load(path)                       # CALOFIN_LISP_ROOT picks the tier
    for s in ('STANDARD INCHES', 'SIDE STANDARD'):
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48.0
    return vm


def walls(vm, pair):
    vm.loads('(entmake (list (cons 0 "LINE")'
             ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
    if pair:
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 0.0 0.0) (list 11 0.0 200.0 0.0)))')
    return list(vm.entities)


def run(path, cmd, pair, script, label):
    vm = fresh(path)
    script = list(script)
    assert script[0] == 'WALLS'
    script[0] = walls(vm, pair)
    try:
        vm.run(cmd, [None] + script)
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None
    return vm


def row_click(path, prefix, eighths, want):
    """A click on the row offering WANT eighths, on the ruler drawn
    round EIGHTHS -- read off the routine itself in a throwaway VM with
    the same view as a run's."""
    vm = fresh(path)
    # the copy under the tool's prefix at the standalone tier; the
    # library's at the grouped one, where the mirror has swapped it
    draw = 'cal:draw-ruler' if os.environ.get('CALOFIN_LISP_ROOT') \
        else prefix + 'draw-ruler'
    _, box, rows = vm.loads('(%s %d nil "0" (%sruler-style))'
                            % (draw, eighths, prefix))
    y = dict((int(v), yy) for v, yy in rows)[want]
    return [(box[0] + box[1]) / 2.0, y, 0.0]


def geometry(vm):
    """Every live entity as (type, points, colour) -- the drawing a run
    leaves behind, ruler scratch excluded by being erased."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        kind = col = None
        for g in data:
            if isinstance(g, Dot) and g.a == 0:
                kind = g.b
            if isinstance(g, Dot) and g.a == 62:
                col = g.b
        pts = tuple(tuple(round(float(v), 9) for v in g[1:3])
                    for g in data if isinstance(g, list) and g
                    and g[0] in (10, 11, 13, 14))
        out.append((kind, pts, col))
    return out


def ruler_live(vm):
    return [e for e in vm.entities if e not in vm.deleted
            and any(isinstance(g, Dot) and g.a == 62 and g.b == RULER_COLOR
                    for g in vm.entdata.get(e, []))]


def ruler_ever(vm):
    return [e for e in vm.entities
            if any(isinstance(g, Dot) and g.a == 62 and g.b == RULER_COLOR
                   for g in vm.entdata.get(e, []))]


def said(vm):
    return "".join(vm.printed)


# ---- the three routines' scripts, treads and depths as parameters -----
# 24" treads round 24 = 192 eighths; 7.5" first depth = 60 eighths, so
# the second depth's ruler offers 52 to 68: 8" is 64.

def cornerstp(treads, depths):
    """walls -> inside out -> no dims -> no bench -> (tread, width Enter)
    per step -> done -> profile Yes -> depths -> the pick."""
    s = ['WALLS', None, "No", "No"]
    for t in treads:
        s += [t, None]
    return s + [None, "Yes"] + list(depths) + [PICK]


def hemistep(treads, depths):
    """base line -> side -> no dims -> 60 at the wall -> (tread, width
    60) per step -> done -> no crown -> profile Yes -> depths -> pick."""
    s = ['WALLS', (100.0, 50.0), "No", 60.0]
    for t in treads:
        s += [t, 60.0]
    return s + [None, None, "Yes"] + list(depths) + [PICK]


def normiestep(treads, depths):
    """base line -> side -> width 60 -> Square -> no dims -> treads ->
    done -> profile Yes -> depths -> pick."""
    return (['WALLS', (100.0, 50.0), 60.0, "Square", "No"] + list(treads)
            + [None, "Yes"] + list(depths) + [PICK])


TOOLS = [
    ('CORNERSTP', CORNERSTP, 'c:CORNERSTP', True, 'cs-', cornerstp),
    ('HEMISTEP', HEMISTEP, 'c:HEMISTEP', False, 'hs-', hemistep),
    ('NORMIESTEP', NORMIESTEP, 'c:NORMIESTEP', False, 'ns-', normiestep),
]


def test_a_row_clicked_is_the_number_typed():
    for name, path, cmd, pair, prefix, script in TOOLS:
        typed = run(path, cmd, pair,
                    script([24.0, 24.5, 24.0], [7.5, 8.0, 10.75, 10.5]),
                    name + " typed")
        clicked = run(path, cmd, pair,
                      script([24.0, row_click(path, prefix, 192, 196), 24.0],
                             [7.5, row_click(path, prefix, 60, 64), 10.75,
                              10.5]),
                      name + " clicked")
        assert geometry(typed) == geometry(clicked), \
            "%s: a clicked row does not draw what the typed number draws" % name
        assert geometry(typed), name
        assert ruler_ever(clicked), "%s never drew a ruler" % name
        assert not ruler_live(clicked), "%s left ruler scratch behind" % name
        assert not ruler_live(typed), name
        assert said(clicked).count("A ruler of nearby lengths") == 1, \
            "the hint is said once a run"
        print("%s: a row clicked at a tread and at a depth is the number"
              " typed, and the ruler is swept" % name)


def test_the_ruler_is_up_at_the_tread_prompt_and_down_at_the_width():
    seen = {}

    def look(label, answer):
        def probe(vm):
            seen[label] = len(ruler_live(vm))
            return answer
        return probe

    # CORNERSTP: tread 1 (no ruler yet), width, tread 2 (ruler), width
    # (down), tread 3 (up again), width, done
    run(CORNERSTP, 'c:CORNERSTP', True,
        ['WALLS', None, "No", "No",
         look("tread1", 24.0), look("width1", None),
         look("tread2", 24.0), look("width2", None),
         look("tread3", 24.0), None,
         look("tread4", None), "No"],
        "CORNERSTP up/down")
    assert seen["tread1"] == 0, seen              # nothing to build one round
    assert seen["width1"] == 0, seen
    assert seen["tread2"] > 20, seen              # a ruler is up
    assert seen["width2"] == 0, seen              # and down again
    assert seen["tread3"] > 20, seen
    assert seen["tread4"] > 20, seen
    seen.clear()
    run(HEMISTEP, 'c:HEMISTEP', False,
        ['WALLS', (100.0, 50.0), "No", 60.0,
         look("tread1", 24.0), look("width1", 60.0),
         look("tread2", 24.0), look("width2", 60.0),
         look("tread3", None), look("crown", None), "No"],
        "HEMISTEP up/down")
    assert seen["tread1"] == 0 and seen["width1"] == 0, seen
    assert seen["tread2"] > 20 and seen["width2"] == 0, seen
    assert seen["tread3"] > 20, seen
    assert seen["crown"] == 0, "the ruler must be down at the crown prompt"
    print("the ruler is up at the tread prompts and down at the width ones")


def test_the_ruler_is_up_through_the_depths_and_down_at_the_pick():
    seen = {}

    def look(label, answer):
        def probe(vm):
            seen[label] = len(ruler_live(vm))
            return answer
        return probe

    run(NORMIESTEP, 'c:NORMIESTEP', False,
        ['WALLS', (100.0, 50.0), 60.0, "Square", "No", 24.0, 24.0, None,
         "Yes", look("d1", 7.5), look("d2", 10.75), look("d3", 10.5),
         look("pick", PICK)],
        "NORMIESTEP depths")
    assert seen["d1"] == 0, seen
    assert seen["d2"] > 20 and seen["d3"] > 20, seen
    assert seen["pick"] == 0, "the ruler must be down before the pick"
    print("the ruler stands through the depths and is down at the pick")


def test_a_fraction_types_and_enter_at_the_first_depth_is_refused():
    for name, path, cmd, pair, prefix, script in TOOLS:
        typed = run(path, cmd, pair,
                    script([24.0, 24.0, 24.0], [7.5, 10.75, 10.75, 10.5]),
                    name + " decimal")
        spelt = run(path, cmd, pair,
                    script(["24", "2'", "24 1/8"], [None, "7 1/2", "10-3/4",
                                                     None, "10.5"]),
                    name + " spelt")
        want = geometry(run(path, cmd, pair,
                            script([24.0, 24.0, 24.125],
                                   [7.5, 10.75, 10.75, 10.5]),
                            name + " check"))
        assert geometry(spelt) == want, \
            "%s: 2' and 24 1/8 and 10-3/4 must read as their numbers" % name
        assert geometry(typed) != want, name   # the check run really differs
        assert "A depth is required." in said(spelt), \
            "%s: Enter at the first depth must be refused" % name
        print("%s: 2', 24 1/8 and 10-3/4 read; Enter at the first depth"
              " is refused" % name)


def test_esc_with_the_ruler_up_leaves_nothing_behind():
    for name, path, cmd, pair, prefix, script in TOOLS:
        vm = fresh(path)
        w = walls(vm, pair)
        vm.handle_errors = True

        def esc(vm):
            assert ruler_live(vm), "the ruler should be up at this prompt"
            raise LispError('Function cancelled', vm)

        head = {'c:CORNERSTP': [None, w, None, "No", "No", 24.0, None, esc],
                'c:HEMISTEP': [None, w, (100.0, 50.0), "No", 60.0, 24.0, 60.0,
                               esc],
                'c:NORMIESTEP': [None, w, (100.0, 50.0), 60.0, "Square", "No",
                                 24.0, esc]}[cmd]
        vm.run(cmd, head)
        assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
        assert ruler_ever(vm), "%s: no ruler was drawn before the Esc" % name
        assert not ruler_live(vm), "%s: Esc left the ruler standing" % name
        print("%s: Esc with the ruler up takes it down" % name)


def main():
    test_a_row_clicked_is_the_number_typed()
    test_the_ruler_is_up_at_the_tread_prompt_and_down_at_the_width()
    test_the_ruler_is_up_through_the_depths_and_down_at_the_pick()
    test_a_fraction_types_and_enter_at_the_first_depth_is_refused()
    test_esc_with_the_ruler_up_leaves_nothing_behind()
    print("\nall step ruler tests passed")


if __name__ == "__main__":
    main()
