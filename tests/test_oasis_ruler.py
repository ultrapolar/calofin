#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The length ruler beside OASIS's radius prompts.

Every one of these shapes is a ring of bulges, and a run asks six
radii in a row: three bulges and three tangents.  They come off a
sheet in whole feet -- oasis:*radius-ladder* is 4' to 12' by a foot --
rather than being taped off anything, so those six prompts stand
beside DIMSTAMP's ruler drawn as a LADDER and a click on a rung is
the radius.

What is pinned here:

  * the six radius questions stand on the ladder and the two BOUNDS
    do not -- a bound is measured, and there is no short list of what
    it comes to;
  * a rung clicked draws exactly what the same number typed draws;
  * zero, a negative and Enter are refused at a radius exactly as
    initget 7 refused them, and Back still backs out;
  * the ruler is down at the question after each radius, and nothing
    of it is left in the drawing when the run ends or is cancelled.

Run: python3 tests/test_oasis_ruler.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_oasis_ruler.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Dot, LispError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LSP = os.path.join(HERE, '..', 'lisp', 'oasis', 'OASIS.lsp')

PRE = 'cal:' if os.environ.get('CALOFIN_LISP_ROOT') else 'oasis:'
RULER_LAYER = "OASIS-RULER"
LADDER = "'(48.0 144.0 12.0)"

#: the reference drawing the OASIS suite is read off: 40' x 20', side
#: bulges 7'-6", a 10' top and three tangents
REF = [480.0, 240.0, 90.0, 96.0, 90.0, 120.0, 96.0, 108.0]

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + ("  -- " + detail if detail and not ok else ""))
    if not ok:
        failures.append(label)


def fresh():
    vm = VM()
    vm.load(LSP)
    vm.loads('(oasis:rulerlayer)')
    return vm


def script(measure=None):
    """Centre variant, simple, base at the origin, then the eight
    measurements and Enter at the pool-bottom question."""
    return (['Center', 'Simple', (0.0, 0.0)]
            + list(REF if measure is None else measure) + [None])


def run(measure, label):
    vm = fresh()
    try:
        vm.run('c:OASIS', script(measure))
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
    """The pool a run leaves behind: every live entity but the ruler's
    own scratch, which is erased anyway."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        kind = lay = None
        pts = []
        for g in vm.entdata.get(e, []):
            if isinstance(g, Dot) and g.a == 0:
                kind = g.b
            elif isinstance(g, Dot) and g.a == 8:
                lay = g.b
            elif isinstance(g, list) and g and g[0] in (10, 11):
                pts.append(tuple(round(float(x), 6) for x in g[1:3]))
        if lay != RULER_LAYER:
            out.append((kind, lay, tuple(pts)))
    return out


def row_click(want):
    vm = fresh()
    _, box, rows = vm.loads(
        '(%sdraw-ruler nil nil "%s" (oasis:ruler-style) %s)'
        % (PRE, RULER_LAYER, LADDER))
    y = dict((int(v), yy) for v, yy in rows)[want]
    return [(box[0] + box[1]) / 2.0, y, 0.0]


def test_the_ladder_is_the_knobs():
    vm = fresh()
    rows = vm.loads('(%sladder-rows %s)' % (PRE, LADDER)) or []
    got = sorted(int(v) for v, _ in rows)
    check("the radius ladder is 4' to 12' by a foot",
          got == [384, 480, 576, 672, 768, 864, 960, 1056, 1152], repr(got))


def test_the_radii_stand_on_it_and_the_bounds_do_not():
    seen = []

    def look(answer):
        def probe(vm):
            seen.append(len(ruler_ents(vm)))
            return answer
        return probe

    run([look(v) for v in REF], "up/down")
    check("nine questions were seen", len(seen) == 8, repr(seen))
    check("the two bounds are measured, so no ruler",
          seen[0] == 0 and seen[1] == 0, repr(seen))
    check("each of the six radii stands on the ladder",
          all(n == 19 for n in seen[2:]), repr(seen))


def test_a_rung_clicked_is_the_number_typed():
    typed = run(REF, "typed")
    # the left bulge's 7'-6" is not on the ladder; 7'-0" is, and the
    # envelope takes it
    picked = list(REF)
    picked[2] = row_click(672)
    clicked = run(picked, "clicked")
    straight = list(REF)
    straight[2] = 84.0
    check("a rung clicked at the left bulge draws what 7'-0\" typed draws",
          geometry(clicked) == geometry(run(straight, "straight")))
    check("...and that is not the same pool as the 7'-6\" one",
          geometry(clicked) != geometry(typed))
    check("nothing of the ruler is left behind",
          not ruler_ents(clicked) and not ruler_ents(typed))
    check("the ruler stood during the run",
          bool(ruler_ents(clicked, live_only=False)))


def test_zero_a_negative_and_enter_are_still_refused():
    for bad, why in ((0.0, "zero"), (-12.0, "a negative"), (None, "Enter")):
        m = list(REF)
        m[2] = bad
        vm = run(m[:2] + [bad] + REF[2:], "refuse " + why)
        said = "".join(vm.printed)
        check("%s is refused at a radius" % why,
              ("must be more than zero" in said
               or "A measurement is required" in said), said[-90:])


def test_esc_at_a_radius_takes_the_ruler_down():
    vm = fresh()
    vm.handle_errors = True

    def esc(vm_):
        assert ruler_ents(vm_), "the ruler should be up at this prompt"
        raise LispError('Function cancelled', vm_)

    vm.run('c:OASIS', ['Center', 'Simple', (0.0, 0.0), 480.0, 240.0, esc])
    check("the Esc reached OASIS's own handler",
          vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
    check("...and it had been up", bool(ruler_ents(vm, live_only=False)))
    check("Esc at a radius sweeps the ruler", not ruler_ents(vm),
          repr(len(ruler_ents(vm))))


def main():
    print("OASIS's radius ruler  [%s]"
          % (os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'))
    test_the_ladder_is_the_knobs()
    test_the_radii_stand_on_it_and_the_bounds_do_not()
    test_a_rung_clicked_is_the_number_typed()
    test_zero_a_negative_and_enter_are_still_refused()
    test_esc_at_a_radius_takes_the_ruler_down()
    print()
    if failures:
        print("%d FAILED: %s" % (len(failures), ", ".join(failures)))
        sys.exit(1)
    print("all OASIS ruler tests passed")


if __name__ == '__main__':
    main()
