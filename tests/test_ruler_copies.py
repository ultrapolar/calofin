#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every copy of the length ruler is the library's text, prefix aside.

The ruler beside a length prompt -- DIMSTAMP's, made a helper -- lives
once in shared/parts/CALOFIN-LIB.lsp under cal:, and six standalone
files carry it under their own prefix so each loads alone: PERPPTS,
CPERPPTS, PERPMARK, CORNERSTP, HEMISTEP and NORMIESTEP.  The grouped
build swaps a copy for the library's (tools/mirror_shared.py), and
tests/test_cal_parity.py calls both halves of every pure swap with the
same arguments.  What neither can see is a copy that DRAWS or ASKS
differently -- a row spacing changed in one file, a keyword handled in
another -- because the drawing and asking halves are excused there.

So this holds the TEXT: the block between the two rule lines that fence
the ruler, read out of every copy with its prefix folded back to cal:,
must be the library's block byte for byte.  A change to the ruler is
made in the library and copied out to the six files (the same rule
STANDARDS.md section 4 gives the ask helpers), and a copy edited on its
own fails here.

Also: the mirror swaps every defun in the block, and nothing else in
the block is left for the twin to carry -- a defun added to the block
without a swap entry would leave the grouped build with two copies of
it, one of them dead.

Run: python3 tests/test_ruler_copies.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))
import mirror_shared  # noqa: E402

LIB = os.path.join(REPO, "shared", "parts", "CALOFIN-LIB.lsp")

#: (mirror entry, file, prefix) for every file that carries the block
COPIES = [
    ("perp_points", "lisp/perp_points/perp_points.lsp", "perp:"),
    ("cperp_points", "lisp/perp_points/cperp_points.lsp", "cperp:"),
    ("PERPMARK", "lisp/perpmark/PERPMARK.lsp", "pm:"),
    ("CORNERSTP", "lisp/cornerstp/CORNERSTP.lsp", "cs-"),
    ("HEMISTEP", "lisp/cornerstp/HEMISTEP.lsp", "hs-"),
    ("NORMIESTEP", "lisp/cornerstp/NORMIESTEP.lsp", "ns-"),
]

START = ";;; -------------------- the length ruler"
END = ";;; -------------------- end of the length ruler"


def block(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    i = src.find(START)
    j = src.find(END)
    assert i >= 0 and j > i, "%s: no fenced ruler block" % os.path.relpath(path, REPO)
    j = src.index("\n", j) + 1
    return src[i:j]


failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + ("  -- " + detail if detail and not ok else ""))
    if not ok:
        failures.append(label)


lib = block(LIB)
defuns = re.findall(r"^\(defun (cal:[^\s()]+)", lib, re.M)
check("the library's block defines the ruler (%d defuns)" % len(defuns),
      len(defuns) >= 20)

for tool, rel, prefix in COPIES:
    path = os.path.join(REPO, rel)
    copy = block(path)
    folded = copy.replace(prefix, "cal:")
    if folded != lib:
        a = folded.splitlines()
        b = lib.splitlines()
        where = next((n for n, (x, y) in enumerate(zip(a, b), 1) if x != y),
                     min(len(a), len(b)) + 1)
        check("%s carries the library's ruler under %s" % (rel, prefix), False,
              "first difference at block line %d: %r vs %r"
              % (where, a[where - 1] if where <= len(a) else "<end>",
                 b[where - 1] if where <= len(b) else "<end>"))
    else:
        check("%s carries the library's ruler under %s" % (rel, prefix), True)
    # every defun in the copy is swapped, and only the block's names are
    swap = mirror_shared.TOOLS[tool]["swap"]
    missing = [d.replace("cal:", prefix) for d in defuns
               if d.replace("cal:", prefix) not in swap]
    check("%s: the mirror swaps every ruler defun" % tool, not missing,
          "unswapped: " + ", ".join(missing))
    wrong = [k for k, v in swap.items()
             if v in defuns and k != v.replace("cal:", prefix)]
    check("%s: each swap names the copy's own spelling" % tool, not wrong,
          repr(wrong))
    # the copy's style builder is the one thing outside the block
    src = open(path, encoding="utf-8", errors="replace").read()
    check("%s: %sruler-style stays local" % (tool, prefix),
          ("(defun %sruler-style" % prefix) in src
          and ("%sruler-style" % prefix) not in swap)

print()
if failures:
    print("%d FAILED: %s" % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("all ruler copies match the library")
