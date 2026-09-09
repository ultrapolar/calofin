#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The guided tours nothing ran: TUTORIALDIMCHECK, TUTORIALDIMSCAN,
TUTORIALLINFINCHECK, TUTORIALLINFINSCAN and TUTORIALCOVERCHECK -- plus a
roster guard so the next tutorial cannot arrive untested.

A tutorial is the first thing a new drafter types and the last thing
anyone re-reads, and these five were executed by no suite at all: they
were named in check_registry's UNTESTED list as "pauses and a demo
drawing, no suite yet".  That is a real exposure, because a tutorial is
not just prose -- these two plant faults in a practice drawing and then
run the read-only scanner over them, so a helper rename or an arity
change anywhere in dimcheck.lsp or linfincheck.lsp breaks the tour at
the command line while every other suite stays green.

What is asserted:

  * each branch of the Checks/Demo/Both selector, including the hidden
    LIST alias that STANDARDS keeps accepting but no longer advertises;
  * the reference sheet lands on the report layer when asked for, and
    nothing is drawn when it is declined;
  * the demo really plants its faults and the scan really finds them --
    the practice drawing is built, DIMSCAN/LINFINSCAN is run over it,
    and the report names the stray dimension point and the unattached
    arc.  A tour that silently drew nothing would still "pass" a test
    that only checked it did not throw, so the count and the findings
    are both asserted;
  * the erase question at the end: Enter takes the practice drawing
    away, No leaves it standing;
  * and every exit restores CMDECHO and every other sysvar and closes
    the undo group -- run() enforces the group, this file the rest.

The SCAN commands are literal aliases ((defun c:TUTORIALDIMSCAN ()
(c:TUTORIALDIMCHECK))), so they are driven through the same scripts and
asserted to behave identically rather than assumed to.

Run: python3 tests/test_tutorials.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_tutorials.py
"""

import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

LISP_ROOT = os.path.join(REPO_DIR, os.environ.get("CALOFIN_LISP_ROOT", "lisp"))
GROUPED = os.path.basename(LISP_ROOT) == "shared"


def tool(folder, name):
    """The file at whichever tier is under test: the grouped build keeps
    every twin flat in parts/, on the cal: library."""
    if GROUPED:
        return os.path.join(LISP_ROOT, "parts", name)
    return os.path.join(LISP_ROOT, folder, name)


DIMCHECK = tool("dimcheck", "dimcheck.lsp")
LINFINCHECK = tool("linfincheck", "linfincheck.lsp")
COVERCHECK = tool("covercheck", "covercheck.lsp")
LIB = os.path.join(LISP_ROOT, "parts", "CALOFIN-LIB.lsp") if GROUPED else None

from callib import COMMAND, LISP_DIR, NOT_A_TOOL, lsp_files, read  # noqa: E402
from lispvm import VM, LispError  # noqa: E402

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def load(path):
    vm = VM()
    if LIB:
        vm.load(LIB)
    vm.load(path)
    return vm


def tour(path, cmd, script):
    """Run one tour and hand back the VM, the live entities and the
    output as one string."""
    vm = load(path)
    before = dict(vm.sysvars)
    try:
        vm.run(cmd, list(script))
    except LispError as e:
        raise AssertionError(f"[{cmd} {script!r}] {e}") from None
    live = [e for e in vm.entities if e not in vm.deleted]
    return vm, live, "".join(vm.printed), before


SPOT = [500.0, 0.0, 0.0]        # where the practice drawing goes
SHEET = [0.0, 0.0, 0.0]         # top-left corner of the reference sheet

#: Checks, then Yes to the sheet, a corner for it, and the default height
CHECKS_SHEET = ["Checks", None, SHEET, None]
#: Checks, then No -- the branch that reads the list and draws nothing
CHECKS_ONLY = ["Checks", "No"]
#: Demo: the spot for the practice drawing, then Enter at every pause,
#: at the report question, at DIMSCAN's selection, and at the erase
DEMO = ["Demo", SPOT]


for label, path, cmd, layer, scan, faults in [
    ("DIMCHECK", DIMCHECK, "c:TUTORIALDIMCHECK", "DIMCHECK-REPORT",
     "DIMSCAN", 8),
    ("LINFINCHECK", LINFINCHECK, "c:TUTORIALLINFINCHECK",
     "LINFINCHECK-REPORT", "LINFINSCAN", 9),
]:
    print(f"TUTORIAL{label} -- Checks reads the list and draws nothing")
    vm, live, out, before = tour(path, cmd, CHECKS_ONLY)
    check(f"{label}: it printed its own banner",
          f"{label} tutorial" in out, out[:120])
    check(f"{label}: declining the sheet draws nothing", not live)
    check(f"{label}: every sysvar is back", vm.sysvars == before)

    print(f"TUTORIAL{label} -- Checks can drop the list in as a sheet")
    vm, live, out, before = tour(path, cmd, CHECKS_SHEET)
    check(f"{label}: one reference sheet was drawn", len(live) == 1,
          f"{len(live)}")
    check(f"{label}: it landed on the report layer",
          live and vm.layer_of(live[0]) == layer,
          live and vm.layer_of(live[0]))
    check(f"{label}: it said so", "Reference sheet placed" in out)
    check(f"{label}: every sysvar is back", vm.sysvars == before)

    print(f"TUTORIAL{label} -- Enter at the sheet's corner skips it")
    vm, live, out, before = tour(path, cmd, ["Checks", None, None])
    check(f"{label}: no point, no sheet", not live)
    check(f"{label}: and it said the sheet was skipped",
          "sheet skipped" in out)

    print(f"TUTORIAL{label} -- LIST is still accepted as a hidden alias")
    vm, live, out, before = tour(path, cmd, ["LIST", "No"])
    check(f"{label}: LIST read the checklist like Checks",
          f"{label} tutorial" in out and not live)

    print(f"TUTORIAL{label} -- the Demo plants faults and the scan finds them")
    vm, live, out, before = tour(path, cmd, DEMO + [None] * faults)
    check(f"{label}: it drew a practice drawing",
          "practice objects drawn" in out)
    check(f"{label}: it ran the read-only scanner",
          f"Running {scan}" in out and f"{scan} complete (read-only)" in out)
    check(f"{label}: the scan reported the stray dimension point",
          "with a stray point" in out)
    check(f"{label}: the scan reported the unattached arc",
          re.search(r"Arcs: \d+ scanned", out) is not None)
    check(f"{label}: Enter at the last question erased the practice drawing",
          not live and "Practice drawing erased" in out, f"{len(live)} left")
    check(f"{label}: every sysvar is back", vm.sysvars == before)

    print(f"TUTORIAL{label} -- No at the last question keeps the drawing")
    vm, live, out, before = tour(path, cmd,
                                 DEMO + [None] * (faults - 1) + ["No"])
    check(f"{label}: the practice objects are still there", len(live) > 1,
          f"{len(live)}")
    check(f"{label}: nothing was erased",
          "Practice drawing erased" not in out)
    check(f"{label}: every sysvar is back", vm.sysvars == before)

    print(f"TUTORIAL{label} -- Enter takes the documented default (Both)")
    vm, live, out, before = tour(path, cmd,
                                 [None, "No", SPOT] + [None] * faults)
    check(f"{label}: Enter read the checks AND ran the demo",
          f"{label} tutorial" in out and "practice objects drawn" in out)
    check(f"{label}: every sysvar is back", vm.sysvars == before)


print("TUTORIALDIMSCAN / TUTORIALLINFINSCAN -- the aliases behave identically")
for label, path, main, alias, faults in [
    ("DIMCHECK", DIMCHECK, "c:TUTORIALDIMCHECK", "c:TUTORIALDIMSCAN", 8),
    ("LINFINCHECK", LINFINCHECK, "c:TUTORIALLINFINCHECK",
     "c:TUTORIALLINFINSCAN", 9),
]:
    script = DEMO + [None] * faults
    a_vm, a_live, a_out, _ = tour(path, main, script)
    b_vm, b_live, b_out, _ = tour(path, alias, script)
    check(f"{alias} asks exactly what {main} asks",
          [p for p, _ in a_vm.prompts] == [p for p, _ in b_vm.prompts])
    check(f"{alias} prints exactly what {main} prints", a_out == b_out)
    check(f"{alias} leaves the same drawing behind",
          len(a_live) == len(b_live))


print("TUTORIALCOVERCHECK -- Yes builds the demo scene")
vm, live, out, before = tour(COVERCHECK, "c:TUTORIALCOVERCHECK",
                             [None, [0.0, 0.0, 0.0]])
layers = {vm.layer_of(e) for e in live}
check("it drew a demo scene", len(live) > 5, f"{len(live)}")
check("on its own demo layer",
      "TUTORIAL-COVERCHECK-DEMO" in layers, f"{layers}")
check("and a pool outline to check against", "POOL" in layers, f"{layers}")
check("every sysvar is back", vm.sysvars == before)

print("TUTORIALCOVERCHECK -- No explains without touching the drawing")
vm, live, out, before = tour(COVERCHECK, "c:TUTORIALCOVERCHECK", ["No"])
check("nothing was drawn", not live, f"{len(live)}")
check("but it still explained itself", len(out) > 200)
check("every sysvar is back", vm.sysvars == before)


print("roster -- every tutorial in the tree is driven by some suite")
TUT = re.compile(r"^\(defun\s+[cC]:(TUTORIAL[A-Z0-9]*)", re.M | re.I)
roster = set()
for _p in lsp_files(LISP_DIR):
    if NOT_A_TOOL in _p.parts:
        continue
    roster |= {m.group(1).upper() for m in TUT.finditer(read(_p))}
suites = {}
for _t in sorted(os.listdir(TESTS_DIR)):
    if _t.startswith("test_") and _t.endswith(".py"):
        suites[_t] = read(os.path.join(TESTS_DIR, _t))
orphans = []
for _c in sorted(roster):
    # either spelling counts: a suite that types the command
    # ("c:TUTORIALPOOL"), or one that names it in a computed roster and
    # prefixes the c: itself -- test_cancel_paths.py drives its QUIET
    # list that way, so matching only the typed form would report
    # TUTORIALCOVERCHECKCLEAN as an orphan while it is in fact run.
    pat = re.compile(r"(c:)?\b%s\b" % re.escape(_c), re.I)
    if not any(pat.search(s) for s in suites.values()):
        orphans.append(_c)
check(f"all {len(roster)} tutorial command(s) are invoked somewhere",
      not orphans, f"never run: {', '.join(orphans)}")


if failures:
    print(f"\n{len(failures)} tutorial check(s) FAILED")
    sys.exit(1)
print("\nall tutorial checks passed")
