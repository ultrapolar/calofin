"""Every generated dialog fits on the screen AutoCAD will give it.

DCL does not scroll.  A dialog wider or taller than the display does
not clip and it does not scroll -- AutoCAD refuses to open it:

    Dialog too large to fit on screen.
    Requested Size = (436, 1085)   Maximum Size = (1920, 1080)

and the command dies there.  Nothing in the tree could see that coming,
because a dialog's size is not written down anywhere: it is the sum of
whatever the generator emitted, and the generators grow every time a
tool is registered.  LAZPANEL's "Rest" page is the clearest case --
every tool that is not on Pool, Cover or Spa lands on it, so the page
that broke is the page each new tool joins.

So the size is computed here, from the DCL the tools really generate,
and checked against a budget.  tools/dclsize.py holds the model and the
note on where its constants come from.

WORST CASE, NOT TYPICAL CASE.  A page is not a fixed height: the panel
grows a row per handful of pinned and recent tools, and LAZSTEP's
second page grows with the step count.  Checking the empty panel would
pass a build that breaks on the first drafter who pins a row, so every
generator here is driven to the tallest state it can actually reach.
"""

import argparse
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "tests"))

import dclsize                                    # noqa: E402
from lispvm import VM                             # noqa: E402

ROOT = HERE.parent
LISP = ROOT / "lisp"

# What AutoCAD reported as its Maximum Size.  A smaller display gives a
# smaller maximum, so fitting here is the floor and not a guarantee for
# every machine; it is the limit we have a real measurement of.
MAX_W = 1920
MAX_H = 1080

# How close to the limit is still a pass.  The model's constants are
# fitted to one report (see dclsize), and a different DPI or dialog font
# moves every one of them, so a dialog that only just fits on paper is
# not one to ship.
MARGIN = 60


def render(path, setup, expr):
    """The DCL text one generator produces, after SETUP has been run."""
    vm = VM()
    vm.load(str(path))
    for form in setup:
        vm.loads(form)
    vm.loads("(setq zz:*d* %s)" % expr)
    return "\n".join(str(l) for l in vm.globals.get("zz:*d*") or [])


def cases():
    """(tool, what, dcl text) for every dialog state worth measuring."""
    out = []

    # LAZPANEL, at its tallest: every tool pinned (the strip trims
    # itself to what fits) and the Recent row full of the longest names
    # on the roster.  Recent drops anything already pinned, so the two
    # rows are filled from opposite ends to get both at once.
    panel = LISP / "lazpanel" / "LAZPANEL.lsp"
    out.append(("LAZPANEL", "empty", render(panel, [], "(lzp:dcl-lines)")))
    out.append(("LAZPANEL", "pins+recent full", render(panel, [
        '(setq lzp:*pins* (lzp:commands))',
        '(lzp:pintrim)',
        '(setq lzp:*recent* (reverse (lzp:commands)))',
        '(lzp:rectrim)',
    ], "(lzp:dcl-lines)")))

    for tool, sub, expr in (
        ("LAZFORM", "lazform", "(lzf:dcl-lines)"),
        ("LAZSPA", "lazspa", "(lzs:dcl-lines)"),
    ):
        p = LISP / sub / (tool + ".lsp")
        out.append((tool, "all charts", render(p, [], expr)))

    # LAZFORM's plain-text view sizes itself from the chart it is
    # handed, and dcl-lines only ever renders it for Rectangle -- which
    # is the SHORTEST of the thirteen, so the one state that gets into
    # the generated file is the one that proves least.
    form = LISP / "lazform" / "LAZFORM.lsp"
    vm = VM()
    vm.load(str(form))
    vm.loads('(setq zz:*k* (mapcar (function car) lzf:*charts*))')
    for k in [str(x) for x in vm.globals["zz:*k*"]]:
        out.append(("LAZFORM", "%s text view" % k,
                    render(form, [], '(lzf:dcl-txt (lzf:chart "%s"))' % k)))

    # LAZSTEP: page one per type, then page two at every step count it
    # will accept -- the chart is a row per step, so the last one is the
    # tall one.
    step = LISP / "lazstep" / "LAZSTEP.lsp"
    out.append(("LAZSTEP", "page 1", render(step, [], "(lzt:dcl-lines)")))
    vm = VM()
    vm.load(str(step))
    vm.loads('(setq zz:*t* (mapcar (function car) lzt:*types*))')
    types = [str(t) for t in vm.globals["zz:*t*"]]
    mx = int(vm.globals["lzt:*max-steps*"])
    for ty in types:
        out.append(("LAZSTEP", "%s page 2, %d steps" % (ty, mx),
                    render(step, [], '(lzt:dcl-p2 (lzt:chart "%s" %d))'
                           % (ty, mx))))
    return out


def check():
    """Problems, as strings, for check_standards to collect."""
    problems, worst = [], (0, 0, "", "")
    for tool, what, text in cases():
        for name, w, h in dclsize.measure(text):
            if h > worst[1]:
                worst = (w, h, name, what)
            if w > MAX_W - MARGIN or h > MAX_H - MARGIN:
                problems.append(
                    "%s: dialog %s (%s) is %dx%d, past the %dx%d a screen "
                    "of %dx%d leaves once the %dpx margin is kept. "
                    "AutoCAD will refuse to open it."
                    % (tool, name, what, w, h, MAX_W - MARGIN,
                       MAX_H - MARGIN, MAX_W, MAX_H, MARGIN))
    if not problems:
        print("check_dcl: every dialog fits; tallest is %s (%s) at %dx%d, "
              "%dpx under the limit"
              % (worst[2], worst[3], worst[0], worst[1], MAX_H - worst[1]))
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list", action="store_true",
                    help="print every dialog measured, tallest first")
    a = ap.parse_args()
    if a.list:
        rows = []
        for tool, what, text in cases():
            for name, w, h in dclsize.measure(text):
                rows.append((h, w, name, tool, what))
        for h, w, name, tool, what in sorted(rows, reverse=True):
            flag = " <-- OVER" if (h > MAX_H - MARGIN or w > MAX_W - MARGIN) else ""
            print("  %-26s %5d x %5d  %-9s %s%s"
                  % (name, w, h, tool, what, flag))
        return 0
    problems = check()
    for p in problems:
        print("check_dcl: " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
