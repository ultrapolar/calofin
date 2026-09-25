#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every tool's self-test table passes here, and could run from *error*.

A failure report runs the failed tool's table on the drafter's machine
and writes what came back (LAZDIAG.lsp, "the tool's own self tests").
Its FAIL lines are only worth reading if the table passes on a machine
where nothing is wrong -- which is this one.  So every tool is loaded
beside LAZDIAG, at the tier CALOFIN_LISP_ROOT names, and its table is
run through the same lzd:selftest-run a report uses.  What has to
hold, per file:

  * one table, registered under every name the file begins or reports
    a run as -- the name LAZDIAG looks it up by;
  * at least check_lazdiag's minimum of entries;
  * every entry passes: an expectation the tree cannot confirm has no
    business in a report, where it would cry FAIL for nothing;
  * running it PROMPTED nothing, DREW nothing, ran no command, wrote no
    file and moved no sysvar, because a table runs from inside *error*.

The roster is computed from the tree, so a tool added later is swept
by construction, and the twin at the shared tier is the mirror's, so
the same entry there tests the library's helper in the local one's
place -- which is the parity the grouped build promises.

Run: python3 tests/test_selftests.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_selftests.py
"""

import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

from callib import LISP_DIR, NOT_A_TOOL, lsp_files  # noqa: E402
import check_lazdiag as cz  # noqa: E402
import run_selftests as rs  # noqa: E402

ROOT = os.environ.get("CALOFIN_LISP_ROOT", "lisp")

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


files = [p for p in lsp_files(LISP_DIR) if NOT_A_TOOL not in p.parts]
check("the roster is the whole tree, computed", len(files) >= 70,
      "%d files" % len(files))

print("every table, at the %s tier" % ROOT)
entries = 0
for p in files:
    rel = os.path.relpath(str(p), REPO_DIR)
    problems, lines = rs.run_file(p, ROOT)
    if ROOT == "shared" and lines == ["  (no shared twin)"]:
        problems = ["no shared twin to run the table in"]
    fails = [l.strip() for l in lines if l.startswith("  FAIL")]
    ran = [l for l in lines if l.startswith("  ok") or l.startswith("  FAIL")]
    entries += len(ran)
    check("%s: %d entr%s, every one passes, nothing prompted, drawn, "
          "commanded, written or moved"
          % (rel, len(ran), "y" if len(ran) == 1 else "ies"),
          not problems, "; ".join(problems + fails[:3]))

check("the tree carries at least %d entries per tool on average"
      % cz.MIN_TESTS, entries >= cz.MIN_TESTS * len(files),
      "%d entries over %d files" % (entries, len(files)))

if failures:
    print("test_selftests: %d FAILURE(S): %s"
          % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("test_selftests: all checks passed (%s tier, %d entries over %d files)"
      % (ROOT, entries, len(files)))
