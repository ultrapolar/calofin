#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""An 'auto' colour that costs a COM round trip is resolved OUTSIDE loops.

STANDARDS.md's Colour section says it in one sentence: resolve an
``'auto`` ink colour "once into a local before a loop... the review
tools touch every entity in the drawing."  ``<pfx>:ink``/``cal:ink``
answers a 'fade or 'guide role by measuring the drawing's background
(``cal:bg``, a ``vla-get-GraphicsWinModelBackgrndColor`` call) unless a
CALSET override or a plain numeric knob short-circuits it first -- the
other ten roles (``dim``/``hi``/the eight kind-roles) never reach that
measurement.  A command that calls an ink helper resolving 'fade or
'guide from OUTSIDE any loop pays that cost once per run; one reachable
from INSIDE a loop pays it once per iteration.

DIMCHECK, COVERCHECK and LINFINCHECK each did exactly this: their own
``unstage`` helper re-resolved the grey fade colour on every call
instead of taking the value its caller had already hoisted, turning one
COM round trip per run into one per reviewed entity.  A plain lexical
scan for "an :ink call textually inside a loop" would not have caught
it -- every loop called ``unstage`` by name, and the ink call was one
``defun`` away, inside ``unstage``'s own body.  So this check reuses
check_osnap.py's call-graph machinery (``sexp``/``walk``/``called``/
``reach``, the same technique it uses for its own OSMODE-muter
detection) to close over what a loop calls, as far as the tier defines
it, and asks whether anything in that reach is a function whose body
resolves a COM-cost role.  A narrower, cheaper rule also fires for the
simpler mistake -- a resolving ink call written directly inside a loop.

Syntactic on purpose, matching check_color.py's own layer_ink: it does
not matter what a knob or a role variable holds at runtime, because the
call site is where the intent is readable, and a role passed through a
variable instead of written as ``'fade``/``'guide`` is a case this can
only ever miss leniently, never fail on wrongly.

    python3 tools/check_perf.py [--tier lisp|shared|releases|both|all]
    python3 tools/check_perf.py --list

Exit 0 when no loop-reachable function resolves a COM-cost ink role, 1
otherwise.
"""

import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_color as cc  # noqa: E402  (INK_RE: the <pfx>:ink / cal:ink call shape)
import check_osnap as co  # noqa: E402  (sexp/walk/head/is_sym/called/reach)
from callib import LISP_DIR, PARTS_DIR, RELEASES_DIR, decomment, lsp_files  # noqa: E402

#: the two roles that measure the drawing's background through COM
#: (cal:bg -> vla-get-GraphicsWinModelBackgrndColor) unless a CALSET
#: override or a numeric knob answers first.  'dim'/'hi' read
#: AutoCAD's interface theme instead (a plain getvar); the eight
#: kind-roles (flag/arc/olap/orig/sugg/point/constr/report) are a
#: fixed table.  None of those ten are worth hoisting.
COM_ROLES = {"fade", "guide"}

#: the loop shapes a re-resolution can hide inside
LOOP_HEADS = {"foreach", "repeat", "while"}


def read_tier(paths):
    """name -> [body,...] across every file in PATHS, and a per-file map --
    check_osnap.Tier's own dmap/per_file construction, without the
    OSMODE-specific bookkeeping the rest of that class computes."""
    dmap, per_file = {}, {}
    for path in paths:
        forms = co.sexp(decomment(path.read_text(encoding="utf-8",
                                                 errors="replace")))
        d = co.defuns(forms)
        per_file[path] = d
        for name, bodies in d.items():
            dmap.setdefault(name, []).extend(bodies)
    return dmap, per_file


def ink_calls(body):
    """[(role, form)] -- every :ink call in BODY whose role is a bare
    symbol, e.g. (dchk:ink *dchk-grey-color* 'fade) -> ("fade", form).
    The parser drops the quote mark, so a quoted role and a variable
    reference look the same here; see the module docstring."""
    out = []
    for f in co.walk(body):
        if isinstance(f, list) and len(f) >= 3:
            h = co.head(f)
            if h and cc.INK_RE.match(h) and co.is_sym(f[2]):
                out.append((f[2].lower(), f))
    return out


def com_cost_calls(body):
    """Every ink call in BODY that resolves a COM-cost role."""
    return [f for role, f in ink_calls(body) if role in COM_ROLES]


def com_cost_funcs(dmap):
    """Names whose OWN body resolves a COM-cost role somewhere in it."""
    return {name for name, bodies in dmap.items()
            if any(com_cost_calls(b) for b in bodies)}


def loops_in(body):
    """Every foreach/repeat/while form in BODY, nested ones included."""
    return [f for f in co.walk(body)
            if isinstance(f, list) and co.head(f) in LOOP_HEADS]


def audit(paths):
    """One row per (file, defun) whose body contains a loop at all --
    clean ones included, so a caller can report how much ground was
    covered, not just how many problems turned up.  "direct" names an
    ink call written straight inside the loop; "indirect" names a
    loop-reachable helper whose OWN body resolves a COM-cost role.
    Both empty means the loop is clean."""
    dmap, per_file = read_tier(paths)
    hot = com_cost_funcs(dmap)
    rows = []
    for path, d in per_file.items():
        for name, bodies in d.items():
            for body in bodies:
                loops = loops_in(body)
                if not loops:
                    continue
                direct, indirect = set(), set()
                for loop in loops:
                    for f in com_cost_calls(loop):
                        direct.add(co.head(f))
                    indirect |= co.reach(co.called(loop), dmap) & hot
                rows.append({"path": path, "name": name,
                            "direct": direct, "indirect": indirect})
    return rows


def tiers(which):
    out = []
    if which in ("lisp", "both", "all"):
        out.append((lsp_files(LISP_DIR), "lisp/"))
    if which in ("shared", "both", "all"):
        out.append((lsp_files(PARTS_DIR), "shared/parts/"))
    if which in ("releases", "all"):
        out.append((lsp_files(RELEASES_DIR), "releases/"))
    return out


def check(paths, label):
    rows = audit(paths)
    problems = []
    for r in rows:
        where = "%s: %s" % (co.rel(r["path"]), r["name"].upper())
        for ink in sorted(r["direct"]):
            problems.append(
                "%s calls %s with a 'fade/'guide role directly inside a "
                "loop -- that measures the drawing's background over COM "
                "once per iteration instead of once for the whole run. "
                "Resolve it into a local before the loop."
                % (where, ink))
        for helper in sorted(r["indirect"]):
            problems.append(
                "%s reaches %s from inside a loop, and %s resolves a "
                "'fade/'guide role itself -- so a COM round trip that "
                "should happen once per run happens once per iteration. "
                "Pass the caller's already-hoisted colour into %s as a "
                "parameter instead of letting it re-resolve."
                % (where, helper, helper, helper))
    return rows, problems


def clean_summary(label, rows):
    return ("check_perf: %s -- %d loop-bearing defun%s, none reach a "
            "COM-cost ('fade/'guide) ink resolution"
            % (label, len(rows), "" if len(rows) == 1 else "s"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tier",
                    choices=("lisp", "shared", "releases", "both", "all"),
                    default="all")
    ap.add_argument("--list", action="store_true",
                    help="print every command whose loop reaches a "
                         "COM-cost ink resolution, whether direct or not")
    a = ap.parse_args(argv)

    problems = []
    for paths, label in tiers(a.tier):
        rows, probs = check(paths, label)
        if a.list:
            print(label)
            for r in rows:
                hit = sorted(r["direct"] | r["indirect"])
                print("  %-22s %-24s %s"
                      % (r["path"].name, r["name"].upper(),
                         "via " + ", ".join(hit) if hit else "clean"))
            continue
        if probs:
            problems += probs
        else:
            print(clean_summary(label, rows))
    if not a.list:
        for p in problems:
            print("check_perf: " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
