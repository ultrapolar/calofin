#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The length ruler beside SPA's corner-size prompts.

The same ladder POOL's corners stand on, one size down: a spa is a
small shape and spa:*radius-ladder* is 3" to 1'-6" by 3".  What is
worth pinning separately is the route in -- SPA asks every distance
through spa:askd, which reads a spelling the library does not
("600mm"), and the ladder must not cost the drafter that spelling.
So the ruler prompt is handed spa:mmval as its READER, and mm is
still read at the one prompt that grew a ruler.

Pinned here:

  * a rung clicked at a Radius corner draws what the same number
    typed draws;
  * "300mm" still reads at that prompt, and reads as 300/25.4 inches;
  * the ruler is up at the size prompt, down at the treatment
    question before it and at the questions after it, and gone from
    the drawing when the run ends;
  * every other spa:askd prompt is the plain typed question it was --
    no ruler, and its wording unchanged, which is what keeps
    tests/test_spa_form.py in step with this.

Run: python3 tests/test_spa_ruler.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_spa_ruler.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Dot, LispError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LSP = os.path.join(HERE, '..', 'lisp', 'spa', 'SPA.LSP')

#: the copy under spa: at the standalone tier; the library's at the
#: grouped one, where the mirror has swapped it
PRE = 'cal:' if os.environ.get('CALOFIN_LISP_ROOT') else 'spa:'

RULER_LAYER = "SPA-RULER"
LADDER = "'(3.0 18.0 3.0)"

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + ("  -- " + detail if detail and not ok else ""))
    if not ok:
        failures.append(label)


def fresh():
    vm = VM()
    vm.load(LSP)
    # a run makes the scratch layer itself; a direct call to draw-ruler
    # skips the command that would, so it is made here the same way
    vm.loads('(spa:rulerlayer)')
    return vm


def run(script, label):
    vm = fresh()
    try:
        vm.run('c:SPA', list(script))
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None
    return vm


def ruler_ents(vm, live_only=True):
    out = []
    for e in vm.entities:
        if live_only and e in vm.deleted:
            continue
        for g in vm.entdata.get(e, []):
            if isinstance(g, Dot) and g.a == 8 and g.b == RULER_LAYER:
                out.append(e)
                break
    return out


def geometry(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        kind = None
        pts = []
        for g in vm.entdata.get(e, []):
            if isinstance(g, Dot) and g.a == 0:
                kind = g.b
            elif isinstance(g, list) and g and g[0] in (10, 11):
                pts.append(tuple(round(float(x), 6) for x in g[1:3]))
        out.append((kind, tuple(pts)))
    return out


def row_click(want):
    """A click on the rung offering WANT eighths of the spa ladder."""
    vm = fresh()
    _, box, rows = vm.loads('(%sdraw-ruler nil nil "%s" (spa:ruler-style) %s)'
                            % (PRE, RULER_LAYER, LADDER))
    y = dict((int(v), yy) for v, yy in rows)[want]
    return [(box[0] + box[1]) / 2.0, y, 0.0]


#: a bounded rectangle whose four corners are asked in one round
def rect(size):
    return [None, 'Coversize', 'Rectangle', None,
            84.0, None,
            'Yes', 'Radius', size,
            'No', 'No']


def test_the_spa_ladder_is_one_size_down_from_the_pools():
    vm = fresh()
    rows = vm.loads('(%sladder-rows %s)' % (PRE, LADDER)) or []
    check("the spa radius ladder is 3\" to 1'-6\" by 3\"",
          sorted(int(v) for v, _ in rows) == [24, 48, 72, 96, 120, 144],
          repr(rows))


def test_a_rung_clicked_is_the_number_typed():
    typed = run(rect(12.0), "typed")
    clicked = run(rect(row_click(96)), "clicked")
    check("a rung clicked at a Radius corner draws what 1'-0\" typed draws",
          geometry(typed) == geometry(clicked))
    check("...and it drew something", bool(geometry(typed)))
    check("the ruler stood during the run",
          bool(ruler_ents(clicked, live_only=False)))
    check("and nothing of it is left in the drawing",
          not ruler_ents(clicked) and not ruler_ents(typed))


def test_millimetres_still_read_at_the_prompt_that_grew_a_ruler():
    mm = run(rect("300mm"), "mm")
    inches = run(rect(300.0 / 25.4), "inches")
    check("\"300mm\" reads at the corner-size prompt",
          geometry(mm) == geometry(inches), "the two runs differ")
    # a spelling that is neither is refused and the question asked again
    again = run([None, 'Coversize', 'Rectangle', None, 84.0, None,
                 'Yes', 'Radius', "NOPE", 12.0, 'No', 'No'], "refused")
    check("text that is not a measurement is refused where it stands",
          any("is not a length" in s for s in again.printed)
          or any("Not a measurement" in s for s in again.printed),
          repr([s for s in again.printed if "NOPE" in s]))


def test_the_ruler_is_up_at_the_size_and_nowhere_else():
    seen = {}

    def look(label, answer):
        def probe(vm):
            seen[label] = len(ruler_ents(vm))
            return answer
        return probe

    run([None, 'Coversize', 'Rectangle', None,
         look("width", 84.0), look("length", None),
         look("allsame", 'Yes'), look("treat", 'Radius'),
         look("size", 12.0),
         look("after", 'No'), 'No'],
        "up/down")
    check("no ruler at the size question before the corners",
          seen["width"] == 0 and seen["length"] == 0, seen)
    check("none at the all-same question", seen["allsame"] == 0, seen)
    check("none at the treatment question", seen["treat"] == 0, seen)
    check("a ruler at the size, with nothing given yet", seen["size"] > 5, seen)
    check("and down again at the question after it", seen["after"] == 0, seen)


def test_esc_at_the_size_takes_the_ruler_down():
    vm = fresh()
    vm.handle_errors = True

    def esc(vm_):
        assert ruler_ents(vm_), "the ruler should be up at this prompt"
        raise LispError('Function cancelled', vm_)

    vm.run('c:SPA', [None, 'Coversize', 'Rectangle', None, 84.0, None,
                     'Yes', 'Radius', esc])
    check("the Esc reached SPA's own handler",
          vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
    check("...and it had been up", bool(ruler_ents(vm, live_only=False)))
    check("Esc at a size prompt sweeps the ruler", not ruler_ents(vm),
          repr(len(ruler_ents(vm))))


def main():
    print("SPA's corner-size ruler  [%s]"
          % (os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'))
    test_the_spa_ladder_is_one_size_down_from_the_pools()
    test_a_rung_clicked_is_the_number_typed()
    test_millimetres_still_read_at_the_prompt_that_grew_a_ruler()
    test_the_ruler_is_up_at_the_size_and_nowhere_else()
    test_esc_at_the_size_takes_the_ruler_down()
    print()
    if failures:
        print("%d FAILED: %s" % (len(failures), ", ".join(failures)))
        sys.exit(1)
    print("all SPA ruler tests passed")


if __name__ == '__main__':
    main()
