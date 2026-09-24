#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The length ruler beside POOL's corner-size prompts, and the LADDER
it stands on.

A corner radius is not measured off the sheet the way a wall is.  It
is picked out of the short list a shop builds to -- 3", 6", 9", a
foot, two feet -- so the radius and cut-face prompts stand beside
DIMSTAMP's ruler drawn as a LADDER: the rungs of pool:*radius-ladder*
(3" to 2'-0" by 3") rather than the eighths either side of the last
answer, which is what a length taped off a wall wants and a corner
does not.  A click on a rung IS the size.

What is pinned here:

  * the rungs are the knob's, graded off the VALUE -- the foot marks
    deepest, the half-foot next -- and a rung at or below zero is
    dropped;
  * a malformed ladder knob costs the ruler and not the command;
  * a rung clicked at a Radius corner draws exactly what the same
    number typed draws, and the ruler is up at the size prompt and
    down at the question after it;
  * the size already given is RINGED among the rungs rather than
    drawn twice;
  * nothing of the ruler is left in the drawing when the run ends,
    and nothing is left after an Esc at the size prompt either.

The prompt wording does not change, which is what keeps
tests/test_pool_form.py and the LAZFORM suite in step with this.

Run: python3 tests/test_pool_ruler.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_pool_ruler.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Dot, LispError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LSP = os.path.join(HERE, '..', 'lisp', 'pool', 'POOL.LSP')

#: the copy under pool: at the standalone tier; the library's at the
#: grouped one, where the mirror has swapped it
PRE = 'cal:' if os.environ.get('CALOFIN_LISP_ROOT') else 'pool:'

#: the scratch layer the rows are drawn on -- the knob-free way to tell
#: the ruler apart from the pool
RULER_LAYER = "POOL-RULER"

BASE = [(0.0, 0.0, 0.0)]          # insertion point pick

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
    vm.loads('(pool:rulerlayer)')
    return vm


def run(script, label):
    vm = fresh()
    try:
        # the trailing Enter declines the steps question every finished
        # run ends at -- these runs are about the ruler
        vm.run('c:POOL', list(script) + [None])
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None
    return vm


def ruler_ents(vm, live_only=True):
    """Every entity drawn on the ruler's scratch layer."""
    out = []
    for e in vm.entities:
        if live_only and e in vm.deleted:
            continue
        for g in vm.entdata.get(e, []):
            if isinstance(g, Dot) and g.a == 8 and g.b == RULER_LAYER:
                out.append(e)
                break
    return out


def ruler_values(vm):
    """The values the ruler standing right now is offering, in eighths,
    read off its LABELS: the ruler is scratch, so what it says is the
    only record of what it offered."""
    out = []
    for e in ruler_ents(vm):
        kind = txt = None
        for g in vm.entdata.get(e, []):
            if isinstance(g, Dot) and g.a == 0:
                kind = g.b
            elif isinstance(g, Dot) and g.a == 1:
                txt = g.b
        if kind == 'MTEXT' and txt:
            out.append(eighths_of(txt))
    return [v for v in out if v is not None]


def eighths_of(label):
    """A ruler label back to eighths: 42" is 336, 3'-6" is 336 too."""
    t = label.replace('\\A1;', '').replace('"', '')
    feet = 0
    if "'-" in t:
        f, t = t.split("'-", 1)
        feet = int(f)
    whole, frac = t, 0.0
    if '{' in t:                       # a stacked fraction: {\\H1.0000x;\\S1/2;}
        whole = t[:t.index('{')]
        inner = t[t.index('\\S') + 2:t.index(';}')]
        n, d = inner.split('/')
        frac = float(n) / float(d)
    try:
        return int(round(8 * (feet * 12 + int(whole) + frac)))
    except ValueError:
        return None


def geometry(vm):
    """Every live entity as (type, points) -- the drawing a run leaves
    behind, the ruler's scratch excluded by being erased."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        kind = None
        pts = []
        for g in data:
            if isinstance(g, Dot) and g.a == 0:
                kind = g.b
            elif isinstance(g, list) and g and g[0] in (10, 11):
                pts.append(tuple(round(float(x), 6) for x in g[1:3]))
        out.append((kind, tuple(pts)))
    return out


# ---- the ladder itself -----------------------------------------------

def rungs(vm, ladder):
    """(EIGHTHS TIER) pairs for LADDER, off the routine itself."""
    return [(int(v), str(t)) for v, t in
            (vm.loads('(%sladder-rows %s)' % (PRE, ladder)) or [])]


def test_the_rungs_are_the_knobs():
    vm = fresh()
    got = sorted(rungs(vm, "'(3.0 24.0 3.0)"))
    check("the radius ladder is 3\" to 2'-0\" by 3\"",
          [v for v, _ in got] == [24, 48, 72, 96, 120, 144, 168, 192],
          repr(got))
    tiers = dict(got)
    # graded off the value: the foot marks deepest, the half-foot next
    check("a whole foot is the deepest mark",
          tiers[96] == 'jump' and tiers[192] == 'jump', repr(got))
    check("a half foot is the next", tiers[48] == 'half'
          and tiers[144] == 'half', repr(got))
    check("a quarter foot is a plain rung",
          tiers[24] == 'quarter' and tiers[72] == 'quarter', repr(got))
    # a ladder that would start at or below zero drops those rungs
    low = rungs(vm, "'(0.0 12.0 6.0)")
    check("a rung at or below zero is dropped",
          sorted(v for v, _ in low) == [48, 96], repr(low))


def test_a_ladder_knob_typed_wrong_costs_the_ruler_not_the_command():
    vm = fresh()
    for bad in ('"3 to 24"', "'(3.0 24.0)", "'(3.0 24.0 0.0)",
                "'(3.0 24.0 -3.0)", "'(\"a\" \"b\" \"c\")", "nil"):
        check("a ladder of %s has no rungs" % bad,
              rungs(vm, bad) == [], bad)
    # ...and cal:ruler-show reads no rungs as no ladder, so with no
    # length either there is nothing to draw and the ruler comes down
    st = vm.loads('(%sruler-show (%sruler-new "%s" (pool:ruler-style))'
                  ' nil \'(3.0 24.0 0.0))' % (PRE, PRE, RULER_LAYER))
    check("a ladder with no rungs draws nothing", not ruler_ents(vm),
          repr(st))


def test_the_current_row_is_ringed_among_the_rungs_not_drawn_twice():
    vm = fresh()
    # a size that IS a rung: 12" (96 eighths) is on the radius ladder
    _, _, rows = vm.loads('(%sdraw-ruler 96 nil "%s" (pool:ruler-style)'
                          " '(3.0 24.0 3.0))" % (PRE, RULER_LAYER))
    vals = [int(v) for v, _ in rows]
    check("a size that is a rung appears once",
          vals.count(96) == 1 and len(vals) == 8, repr(vals))
    check("...and the rungs are all still there",
          vals == [24, 48, 72, 96, 120, 144, 168, 192], repr(vals))
    # exactly one ring, and it is the current row's
    circles = [e for e in ruler_ents(vm)
               if any(isinstance(g, Dot) and g.a == 0 and g.b == 'CIRCLE'
                      for g in vm.entdata[e])]
    check("the current row is ringed, once", len(circles) == 1,
          repr(len(circles)))
    # a size that is NOT a rung sits among them as a ninth row
    vm2 = fresh()
    _, _, rows2 = vm2.loads('(%sdraw-ruler 100 nil "%s" (pool:ruler-style)'
                            " '(3.0 24.0 3.0))" % (PRE, RULER_LAYER))
    vals2 = [int(v) for v, _ in rows2]
    check("a size off the ladder is ringed among the rungs",
          vals2 == [24, 48, 72, 96, 100, 120, 144, 168, 192], repr(vals2))


# ---- the ladder at the prompt ----------------------------------------

def row_click(want, current='nil', ladder="'(3.0 24.0 3.0)"):
    """A click on the rung offering WANT eighths, read off the routine
    itself in a throwaway VM with the same view as a run's."""
    vm = fresh()
    _, box, rows = vm.loads('(%sdraw-ruler %s nil "%s" (pool:ruler-style) %s)'
                            % (PRE, current, RULER_LAYER, ladder))
    y = dict((int(v), yy) for v, yy in rows)[want]
    return [(box[0] + box[1]) / 2.0, y, 0.0]


#: a square rectangle whose four corners are asked one after another,
#: answered Radius and then a size.  The four walls are 240 long, so a
#: 2'-0" radius is well inside the cap.
def rect(size):
    return (["Outofsquare", "Rectangle"] + BASE
            + [240.0, 240.0, 240.0, 240.0,
               "Radius", size,
               None, None, None, None, None, None,   # B, C, D reuse
               "Ends", 340.0, 340.0, 340.0, 340.0,
               "No",                                  # no bottom
               "No"])                                 # mark Given? no


def test_a_rung_clicked_is_the_number_typed():
    typed = run(rect(24.0), "typed")
    clicked = run(rect(row_click(192)), "clicked")
    check("a rung clicked at a Radius corner draws what 2'-0\" typed draws",
          geometry(typed) == geometry(clicked))
    check("...and it drew something", bool(geometry(typed)))
    check("the ruler stood during the run",
          bool(ruler_ents(clicked, live_only=False)))
    check("and nothing of it is left in the drawing",
          not ruler_ents(clicked) and not ruler_ents(typed))
    hints = [s for s in clicked.printed if "A ruler of the usual lengths" in s]
    check("the ladder names itself as the usual lengths, once a run",
          len(hints) == 1, repr(len(hints)))


def test_the_ruler_is_up_at_the_size_and_down_at_the_question_after():
    seen = {}

    def look(label, answer):
        def probe(vm):
            seen[label] = len(ruler_ents(vm))
            return answer
        return probe

    run(["Outofsquare", "Rectangle"] + BASE
        + [240.0, 240.0, 240.0, 240.0,
           look("treatA", "Radius"), look("sizeA", 24.0),
           look("treatB", "Radius"), look("sizeB", 12.0),
           None, None, None, None,                    # C, D reuse
           look("cmode", "Ends"), 340.0, 340.0, 340.0, 340.0,
           "No", "No"],
        "up/down")
    check("no ruler at the treatment question", seen["treatA"] == 0, seen)
    check("a ruler at the first size, with nothing given yet",
          seen["sizeA"] > 5, seen)
    check("...and down again at the next treatment question",
          seen["treatB"] == 0, seen)
    check("a ruler at the second size too", seen["sizeB"] > 5, seen)
    check("and down at the cross-dim question", seen["cmode"] == 0, seen)


def test_a_size_over_the_cap_is_refused_and_the_ruler_stands_again():
    seen = {}

    def look(label, answer):
        def probe(vm):
            seen[label] = len(ruler_ents(vm))
            return answer
        return probe

    # the LEFT and RIGHT walls are 60, so half of one is 30: a 2'-0"
    # radius fits and a 4'-0" one does not
    vm = run(["Outofsquare", "Rectangle"] + BASE
             + [240.0, 240.0, 60.0, 60.0,
                "Radius", look("over", 48.0), look("again", 24.0),
                None, None, None, None, None, None,
                "Ends", 250.0, 250.0, 250.0, 250.0,
                "No", "No"],
             "cap")
    check("the oversized radius was refused",
          any("Too large for this corner's walls" in s for s in vm.printed))
    check("the ruler was up at the re-ask", seen["again"] > 5, seen)
    check("and nothing of it is left behind", not ruler_ents(vm))


def test_esc_at_the_size_takes_the_ruler_down():
    vm = fresh()
    vm.handle_errors = True

    def esc(vm_):
        assert ruler_ents(vm_), "the ruler should be up at this prompt"
        raise LispError('Function cancelled', vm_)

    vm.run('c:POOL', ["Outofsquare", "Rectangle"] + BASE
           + [240.0, 240.0, 240.0, 240.0, "Radius", esc])
    check("the Esc reached POOL's own handler",
          vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
    check("...and it had been up", bool(ruler_ents(vm, live_only=False)))
    check("Esc at a size prompt sweeps the ruler", not ruler_ents(vm),
          repr(len(ruler_ents(vm))))




# ---- the depth chain --------------------------------------------------
#
# A pool's depths are as short a list as its corners: a wall is built
# to a handful of heights and a deep end to a handful of depths, so C,
# D and C2 stand on ladders of their own rather than on a tape.

#: a wedge-bottom rectangle, which asks C and D at the end of its run
def wedge(c, d):
    return (["Outofsquare", "Rectangle"] + BASE
            + [240.0, 240.0, 120.0, 120.0,
               "Cut", 24.0, None, None, None, None, None, None,
               "Ends", 260.0, 260.0, 260.0, 260.0,
               "Yes", "Wedge",
               30.0, 180.0,
               None, 60.0, None,
               c, d,
               "No"])


def test_the_depths_stand_on_their_own_ladders():
    seen = {}

    def look(label, answer):
        def probe(vm):
            seen[label] = sorted(
                int(v) for v in ruler_values(vm))
            return answer
        return probe

    run(wedge(look("C", 42.0), look("D", 72.0)), "depths")
    # pool:*wallheight-ladder* is 36" to 54" by 3"
    check("C stands on the wall-height ladder",
          seen["C"] == [288, 312, 336, 360, 384, 408, 432], seen.get("C"))
    # pool:*deepdepth-ladder* is 60" to 96" by 6", with C's answer of
    # 42" nowhere near it -- D is asked with no length of its own yet
    check("D stands on the deep-end ladder",
          seen["D"] == [480, 528, 576, 624, 672, 720, 768], seen.get("D"))


def test_a_depth_rung_clicked_is_the_number_typed():
    typed = run(wedge(42.0, 72.0), "typed")
    clicked = run(wedge(row_click(336, ladder="'(36.0 54.0 3.0)"),
                        row_click(576, ladder="'(60.0 96.0 6.0)")),
                  "clicked")
    check("a rung clicked at C and at D draws what the numbers typed draw",
          geometry(typed) == geometry(clicked))
    check("...and it drew something", bool(geometry(typed)))
    check("nothing of the ruler is left behind",
          not ruler_ents(clicked) and not ruler_ents(typed))


def test_a_wall_length_is_still_the_plain_typed_question():
    seen = {}

    def look(label, answer):
        def probe(vm):
            seen[label] = len(ruler_ents(vm))
            return answer
        return probe

    run(["Outofsquare", "Rectangle"] + BASE
        + [look("top", 240.0), look("bottom", 240.0), 120.0, 120.0,
           "Cut", 24.0, None, None, None, None, None, None,
           look("cross", "Ends"), 260.0, 260.0, 260.0, 260.0,
           "No", "No"],
        "wall lengths")
    check("a wall length is measured, not picked off a list - no ruler",
          seen["top"] == 0 and seen["bottom"] == 0, seen)
    check("...nor is a cross dim", seen["cross"] == 0, seen)




# ---- the hopper offsets -----------------------------------------------
#
# M and K are the gap the hopper leaves to the top side and to the
# bottom side, and a hopper is set in from the walls by 2' to 6' --
# the same range ABHD and FITABHD offer at the same question.  The
# rest of the chain beside them is measured: H, G, F and E are
# stations ALONG the pool and L is the hopper's own width.

HOP_LADDER = "'(24.0 72.0 6.0)"
#: its nine rungs in eighths -- 2' to 6' by 6"
RUNGS = [192, 240, 288, 336, 384, 432, 480, 528, 576]


#: a wedge-bottom rectangle, stopping at the M / L / K chain
def hopper(m, l, k):
    return (["Outofsquare", "Rectangle"] + BASE
            + [240.0, 240.0, 120.0, 120.0,
               "Cut", 24.0, None, None, None, None, None, None,
               "Ends", 260.0, 260.0, 260.0, 260.0,
               "Yes", "Wedge",
               30.0, 180.0,
               m, l, k,
               42.0, 72.0,
               "No"])


def test_the_hopper_offsets_stand_on_the_offset_ladder():
    seen = {}

    def look(label, answer):
        def probe(vm):
            seen[label] = sorted(int(v) for v in ruler_values(vm))
            return answer
        return probe

    # the pool is 120 across, so the M / L / K chain totals 120: with
    # M 36 and L 51 the chain has 33" left for K, which is NOT a rung
    run(hopper(look("M", 36.0), look("L", 51.0), look("K", None)), "hopper")
    check("M stands on the hopper-offset ladder", seen["M"] == RUNGS,
          repr(seen.get("M")))
    check("...and its suggestion, H's own 30\", IS a rung, so it is drawn"
          " once rather than twice",
          seen["M"].count(240) == 1 and len(seen["M"]) == len(RUNGS),
          repr(seen.get("M")))
    check("L is the hopper's own width, not an offset - no ruler",
          seen["L"] == [], repr(seen.get("L")))
    check("K stands on the same ladder, with the chain's own 33\" ringed"
          " among the rungs",
          seen["K"] == sorted(RUNGS + [264]), repr(seen.get("K")))


def test_a_hopper_rung_clicked_is_the_number_typed():
    typed = run(hopper(36.0, 51.0, None), "typed")
    clicked = run(hopper(row_click(288, ladder=HOP_LADDER), 51.0, None),
                  "clicked")
    check("a rung clicked at M draws what 3'-0\" typed draws",
          geometry(typed) == geometry(clicked))
    check("...and it drew something", bool(geometry(typed)))
    check("nothing of the ruler is left behind",
          not ruler_ents(clicked) and not ruler_ents(typed))


def test_enter_at_a_hopper_offset_still_takes_the_chain_s_own_number():
    # K is a SUG question: its suggestion is what the chain has left,
    # and Enter has always taken it.  The ruler must not change that
    entered = run(hopper(36.0, 51.0, None), "entered")
    typed = run(hopper(36.0, 51.0, 33.0), "typed")
    check("Enter at K still takes the chain's remainder",
          geometry(entered) == geometry(typed))
    check("...and that run drew a pool", bool(geometry(entered)))


def test_na_still_answers_a_hopper_offset():
    # M is a SUG question too, so NA is on offer and means "not
    # measured" -- a keyword the ruler prompt hands back untouched
    vm = run(hopper("NA", 51.0, None), "NA at M")
    check("NA still answers M", bool(geometry(vm)))
    check("...and the run said nothing about a bad length",
          not any("is not a length" in t for t in vm.printed),
          repr([t for t in vm.printed if "not a length" in t][:1]))


def main():
    print("POOL's corner-size ruler  [%s]"
          % (os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'))
    test_the_rungs_are_the_knobs()
    test_a_ladder_knob_typed_wrong_costs_the_ruler_not_the_command()
    test_the_current_row_is_ringed_among_the_rungs_not_drawn_twice()
    test_a_rung_clicked_is_the_number_typed()
    test_the_ruler_is_up_at_the_size_and_down_at_the_question_after()
    test_a_size_over_the_cap_is_refused_and_the_ruler_stands_again()
    test_esc_at_the_size_takes_the_ruler_down()
    test_the_depths_stand_on_their_own_ladders()
    test_a_depth_rung_clicked_is_the_number_typed()
    test_a_wall_length_is_still_the_plain_typed_question()
    test_the_hopper_offsets_stand_on_the_offset_ladder()
    test_a_hopper_rung_clicked_is_the_number_typed()
    test_enter_at_a_hopper_offset_still_takes_the_chain_s_own_number()
    test_na_still_answers_a_hopper_offset()
    print()
    if failures:
        print("%d FAILED: %s" % (len(failures), ", ".join(failures)))
        sys.exit(1)
    print("all POOL ruler tests passed")


if __name__ == '__main__':
    main()
