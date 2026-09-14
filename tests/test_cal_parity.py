#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every helper the mirror replaces with a cal: one must ANSWER the same.

CLAUDE.md names this bug class outright: "a cal: helper that subtly
differs from the standalone helper it replaced".  It is not
hypothetical -- shared/parts/SPA.lsp once sat two revisions behind while
every one-file check stayed green, and the grouped build drew loose
lines where the standalone one drew a bounded polyline.

check_standards.py compares version banners, which catches a twin left
behind.  Nothing compared the two helpers' BEHAVIOUR.  That is the gap
here: tools/mirror_shared.py's swap maps say "abp:v+ becomes cal:v+" in
57 tools, and until this file nothing ever called both with the same
arguments and looked at the two answers.  It matters most where the
leverage is highest -- a drift in cal:v+ would reach 18 tools at once,
and one in cal:ensure-layer 29.

The roster is computed, never typed: it comes from mirror_shared.TOOLS
itself, so a swap added tomorrow is checked the day it lands.  A swap
whose target has no inputs here FAILS rather than being skipped
quietly; to excuse one, name it in SKIP with a reason.

The tier makes no difference here and the suite says so: the two
files it reads are always lisp/<tool> and shared/parts/CALOFIN-LIB.lsp,
because "the local helper and the cal: one that replaces it" is only a
question at the standalone tier -- at the grouped tier the local is
already gone, by construction.

Run: python3 tests/test_cal_parity.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_cal_parity.py
"""

import ast
import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

import mirror_shared  # noqa: E402
from lispvm import VM, LispError  # noqa: E402

LIB = os.path.join(REPO_DIR, "shared", "parts", "CALOFIN-LIB.lsp")

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


#: Arguments to call both halves of a swap with, as AutoLISP source.
#: Several sets each where an edge case is worth pinning -- a negative
#: angle, a wrapped one, a zero-length vector, an empty string.
INPUTS = {
    "cal:2d": ["'(1.5 2.5 3.5)", "'(0.0 0.0 0.0)", "'(-4.0 7.25)"],
    "cal:andjoin": ['\'("a" "b" "c") "and"', '\'("only") "and"',
                    '\'("a" "b") "or"', "nil \"and\""],
    "cal:ang-diff": ["0.1 0.2", "6.2 0.1", "0.0 3.14159265",
                     "-0.5 0.5", "3.0 -3.0"],
    "cal:angnorm": ["0.5", "-0.5", "7.0", "-7.0", "0.0", "6.283185307"],
    "cal:axis-pt": ["'(1.0 2.0) '(1.0 0.0) 3.0",
                    "'(0.0 0.0) '(0.0 1.0) -2.5"],
    "cal:back-word-p": ['"Back"', '"back"', '"B"', '"Next"', '""'],
    "cal:ceil": ["1.0", "1.2", "-1.2", "0.0", "5.99"],
    "cal:circumcenter": ["'(0.0 0.0) '(4.0 0.0) '(0.0 4.0)",
                         "'(1.0 1.0) '(3.0 1.0) '(2.0 4.0)",
                         "'(0.0 0.0) '(1.0 1.0) '(2.0 2.0)"],
    "cal:cross": ["'(1.0 0.0) '(0.0 1.0)", "'(2.0 3.0) '(4.0 5.0)",
                  "'(1.0 1.0) '(2.0 2.0)"],
    "cal:d2": ["'(0.0 0.0) '(3.0 4.0)", "'(1.0 1.0) '(1.0 1.0)"],
    "cal:dist": ["'(0.0 0.0) '(3.0 4.0)", "'(1.0 2.0 3.0) '(4.0 6.0 3.0)"],
    "cal:dot": ["'(1.0 2.0) '(3.0 4.0)", "'(1.0 0.0) '(0.0 1.0)"],
    "cal:dotn": ["'(1.0 2.0 3.0) '(4.0 5.0 6.0)",
                 "'(1.0 0.0 0.0) '(0.0 1.0 0.0)"],
    "cal:kvhas": ['"a=1;b=2" "b"', '"a=1" "z"', '"" "a"'],
    "cal:kvpack": ['\'(("a" . "1") ("b" . "2"))', "nil"],
    "cal:kvsplit": ['"a;b;c" ";"', '"a" ";"', '"" ";"'],
    "cal:kvunpack": ['"a=1;b=2"', '""'],
    "cal:mid": ["'(0.0 0.0) '(4.0 6.0)", "'(-2.0 -2.0) '(2.0 2.0)"],
    "cal:midn": ["'(0.0 0.0 0.0) '(4.0 6.0 8.0)"],
    "cal:nthcdr": ["0 '(1 2 3)", "2 '(1 2 3)", "5 '(1 2 3)", "1 nil"],
    "cal:pad": ['"ab" 5', '"abcdef" 3', '"" 2', '"x" 0'],
    "cal:perp": ["'(1.0 0.0)", "'(0.0 1.0)", "'(3.0 4.0)"],
    "cal:plural": ['1 "pad" "pads"', '0 "pad" "pads"', '2 "pad" "pads"'],
    "cal:proj-param": ["'(2.0 2.0) '(0.0 0.0) '(1.0 0.0)",
                       "'(-1.0 5.0) '(0.0 0.0) '(0.0 1.0)"],
    "cal:pt-line-dist": ["'(0.0 3.0) '(0.0 0.0) '(1.0 0.0)",
                         "'(2.0 0.0) '(0.0 0.0) '(1.0 0.0)"],
    "cal:signed-dang": ["0.0 1.0", "1.0 0.0", "0.1 6.2", "6.2 0.1"],
    "cal:sublist": ["'(1 2 3 4 5) 1 2", "'(1 2 3) 0 3", "'(1 2 3) 2 9"],
    "cal:tan": ["0.0", "0.5", "-0.5", "1.0"],
    "cal:trim": ['"  ab  "', '"ab"', '""', '"   "'],
    "cal:unit": ["'(3.0 4.0)", "'(0.0 0.0)", "'(-3.0 0.0)"],
    "cal:unitn": ["'(3.0 4.0 0.0)", "'(0.0 0.0 0.0)"],
    "cal:v*": ["'(1.0 2.0) 3.0", "'(1.0 2.0) 0.0", "'(1.0 2.0) -1.5"],
    "cal:v+": ["'(1.0 2.0) '(3.0 4.0)", "'(0.0 0.0) '(0.0 0.0)"],
    "cal:v-": ["'(1.0 2.0) '(3.0 4.0)", "'(5.0 5.0) '(5.0 5.0)"],
    "cal:vlen": ["'(3.0 4.0)", "'(0.0 0.0)"],
    "cal:zeropad2": ["1", "9", "10", "0", "99"],
    "cal:imgtexth": ["1.0", "2.5"],
    "cal:imgtextw": ['"AB" 1.0', '"" 1.0'],
    "cal:imgglyph": ['"A"', '"0"', '" "'],
    "cal:formanswer": ['"12"', '""', "nil"],
    # The ink table.  Its other input is the THEME, which travels in
    # the profile rather than in an argument, so each case sets it in
    # the first slot: a progn that writes CalofinTheme and then hands
    # over the knob.  Both halves of the pair evaluate their own copy
    # of that, so each sees the same profile -- and eleven tools carry
    # a copy of this body, which is exactly the kind of duplication
    # this file exists to hold together.  The last case leaves the
    # override cleared for whatever runs next.
    "cal:ink": [
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'fade',
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'guide',
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'dim',
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'hi',
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'nosuchrole',
        '(progn (setenv "CalofinTheme" "light") \'auto) \'fade',
        '(progn (setenv "CalofinTheme" "light") \'auto) \'guide',
        '(progn (setenv "CalofinTheme" "light") \'auto) \'dim',
        '(progn (setenv "CalofinTheme" "light") \'auto) \'hi',
        # a number is that number, whatever the theme says
        '(progn (setenv "CalofinTheme" "dark") 8) \'fade',
        '(progn (setenv "CalofinTheme" "light") 5) \'hi',
        # and with nothing measurable and no override, today's numbers
        '(progn (setenv "CalofinTheme" "") \'auto) \'fade',
        '(progn (setenv "CalofinTheme" "") \'auto) \'guide',
        '(progn (setenv "CalofinTheme" "") \'auto) \'dim',
        '(progn (setenv "CalofinTheme" "") \'auto) \'hi',
    ],
}

#: Swaps this file does not call, and why.  Every one needs something a
#: bare VM has not got -- a drawing, a prompt queue, or the session
#: state the command around it sets up -- and each is covered where that
#: context exists (test_calofin_lib.py, and the tool's own suite at both
#: tiers, which is what `make parity` is).
SKIP = {
    "cal:ui": "takes no arguments, so the theme it reads cannot be set\n              up from one; tests/test_theme.py drives both copies\n              through every theme instead",
    "cal:askkw": "asks; driven by every form suite at both tiers",
    "cal:askyn": "asks",
    "cal:askstr": "asks",
    "cal:askdist": "asks",
    "cal:asktreat": "asks",
    "cal:ask-yn": "asks",
    "cal:ask-yn-nav": "asks",
    "cal:pause": "asks",
    "cal:syssave": "session state, and the mirror expands its arity",
    "cal:sysrestore": "session state",
    "cal:dimstysave": "session state",
    "cal:dimstyrestore": "session state",
    "cal:undobegin": "session state",
    "cal:undoend": "session state",
    "cal:osup": "session state",
    "cal:osdown": "session state",
    "cal:datestr": "reads CDATE, not a pure function of its arguments",
    "cal:ensure-layer": "writes the layer table; needs a drawing",
    "cal:layer-usable-p": "reads the layer table; needs a drawing",
    "cal:bbox-ent": "needs an entity",
    "cal:bbox-ss": "needs a selection set",
    "cal:block-number": "needs a block insert, and the mirror widens it",
    "cal:mtext": "draws",
    "cal:text": "draws",
    "cal:imgtext": "draws into a dialog image tile",
    "cal:imgpline": "draws into a dialog image tile",
    "cal:imgflatten": "takes a chart element, not a plain value",
    "cal:imgarcpts": "takes a chart element, not a plain value",
    "cal:error-cancel-p": "reads the error message a handler was given",
    "cal:dedupe": "the mirror widens it with a tolerance argument",
}


def arities(src):
    return {m.group(1).lower(): len(m.group(2).split("/")[0].split())
            for m in re.finditer(r"^\(defun\s+([^\s()]+)\s*\(([^)]*)\)",
                                 src, re.M)}


LIB_SRC = open(LIB, encoding="utf-8", errors="replace").read()
LIB_ARITY = arities(LIB_SRC)

#: (tool, local, cal) for every swap whose local really is a defun in
#: the file the mirror reads it from.  A satellite (TUTORIALSPA and the
#: like) swaps a helper that lives in its sibling, so there is nothing
#: in ITS file to compare against; the sibling's own entry covers it.
PAIRS = []
for _tool in sorted(mirror_shared.TOOLS):
    _d = mirror_shared.TOOLS[_tool]
    _sw = _d.get("swap")
    if not _sw:
        continue
    if isinstance(_sw, str):
        _sw = ast.literal_eval(_sw)
    _p = os.path.join(REPO_DIR, _d["src"])
    if not os.path.isfile(_p):
        continue
    _src = open(_p, encoding="utf-8", errors="replace").read()
    _ta = arities(_src)
    for _local, _cal in sorted(_sw.items()):
        if _local.lower() in _ta and _cal.lower() in LIB_ARITY:
            PAIRS.append((_tool, _d["src"], _local, _cal.lower(),
                          _ta[_local.lower()], LIB_ARITY[_cal.lower()]))

targets = sorted({c for _, _, _, c, _, _ in PAIRS})
print(f"{len(PAIRS)} swap pair(s) over {len(targets)} cal: helper(s)")

unplanned = [c for c in targets if c not in INPUTS and c not in SKIP]
check("every swapped cal: helper is either called here or excused",
      not unplanned,
      "no inputs and no SKIP entry: " + ", ".join(unplanned))

# One VM per source file: the tool's own helpers and the library's, side
# by side.  They cannot collide -- check_standards proves only
# CALOFIN-LIB defines cal: symbols -- so both halves of every swap in
# that file answer in the same session.
_vms = {}


def vm_for(src):
    """The tool's STANDALONE source and the library, side by side.

    Both are read and evaluated directly rather than through vm.load,
    which is what CALOFIN_LISP_ROOT remaps: at the grouped tier that
    remap would hand back the twin, where the local helper has already
    been replaced by the cal: one -- there would be nothing left to
    compare, and the run would die on the local's own name.  This
    comparison only ever means one thing, standalone against library,
    so it reads the same two files whichever tier the suite is run at.
    """
    if src not in _vms:
        vm = VM()
        with open(os.path.join(REPO_DIR, src), encoding="utf-8",
                  errors="replace") as fh:
            vm.loads(fh.read())
        with open(LIB, encoding="utf-8", errors="replace") as fh:
            vm.loads(fh.read())
        _vms[src] = vm
    return _vms[src]


def call(vm, fn, args, n):
    """(fn args...) evaluated, or the error it raised, as a comparable
    value.  An error on one side and an answer on the other is exactly
    the drift worth reporting, so both come back."""
    try:
        vm.loads(f"(setq test:*r* ({fn} {args}))")
        return ("ok", vm.globals.get("test:*r*"))
    except LispError as e:
        return ("err", str(e).split("\n")[0])
    except RecursionError:
        return ("err", "recursion")


def same(a, b):
    """Equal, with floats compared to the precision drafting cares
    about -- 1e-9 of an inch is not a difference, and a helper that
    reassociates its arithmetic would otherwise fail on the last bit."""
    if type(a) is not type(b) and not (isinstance(a, (int, float))
                                       and isinstance(b, (int, float))):
        return False
    if isinstance(a, float) or isinstance(b, float):
        return abs(float(a) - float(b)) < 1e-9
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


tested = skipped = 0
drift = []
for tool, src, local, cal, la, ca in PAIRS:
    if cal in SKIP:
        skipped += 1
        continue
    if cal not in INPUTS:
        continue
    if la != ca:
        drift.append(f"{tool}: {local} takes {la} arg(s) but {cal} takes "
                     f"{ca} -- the mirror must widen the call, and no "
                     f"expand rule covers it")
        continue
    vm = vm_for(src)
    for args in INPUTS[cal]:
        want = call(vm, cal, args, ca)
        got = call(vm, local, args, la)
        tested += 1
        if want[0] != got[0] or (want[0] == "ok" and not same(got[1], want[1])):
            drift.append(f"{tool}: ({local} {args}) -> {got[1]!r} but "
                         f"({cal} {args}) -> {want[1]!r}")

check(f"all {tested} call(s) agree across {len(PAIRS) - skipped} "
      f"compared pair(s)", not drift,
      "\n         ".join(drift[:12]))
print(f"  ({skipped} pair(s) excused by SKIP, {len(_vms)} source file(s) "
      f"loaded beside the library)")

if failures:
    print(f"\n{len(failures)} cal: parity check(s) FAILED")
    sys.exit(1)
print("\nall cal: parity checks passed")
