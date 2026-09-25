#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run a tool's self-test table in the VM, exactly as a failure report would.

Every tool carries a table of self tests -- its own helpers on inputs
whose answers are known -- and LAZDIAG runs it on the drafter's machine
after a failure and writes the results into the report (LAZDIAG.lsp,
"the tool's own self tests").  This runs the same table here, through
the same lzd:selftest-run, so what a report will say about a tool can
be read before anything has failed, and a table being written can be
tried as it grows:

    python3 tools/run_selftests.py lisp/pool/POOL.LSP
    python3 tools/run_selftests.py lisp/pool/POOL.LSP --tier shared
    python3 tools/run_selftests.py                     # every tool, lisp/ tier
    python3 tools/run_selftests.py --tier both         # the parity run

One line per entry, as the report writes it, then the verdict.  Exit 1
when any entry fails or raises, when a file registers no table, when
a table holds fewer than the check's minimum, or when running one
PROMPTED, DREW, RAN A COMMAND, WROTE A FILE or MOVED A SYSVAR -- a
table runs from inside *error*, and any of those there is a second
failure with nowhere to go.

tests/test_selftests.py is this over the whole tree, at both tiers;
this is the one-file loop while a table is being written.
"""

import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO / "tests"))
sys.path.insert(0, str(HERE))

from lispvm import VM  # noqa: E402
from callib import LISP_DIR, NOT_A_TOOL, PARTS_DIR, lsp_files  # noqa: E402
import check_lazdiag as cz  # noqa: E402

LAZDIAG = REPO / "lisp" / "lazdiag" / "LAZDIAG.lsp"
LIB = PARTS_DIR / "CALOFIN-LIB.lsp"


def twin_of(path):
    """The shared/parts twin of a lisp/ file, or None when it has none
    (a bundled step member, the deprecated matcher)."""
    p = PARTS_DIR / (pathlib.Path(path).stem + ".lsp")
    if p.is_file():
        return p
    for q in PARTS_DIR.iterdir():
        if q.stem.lower() == pathlib.Path(path).stem.lower():
            return q
    return None


def load(path, tier):
    """A VM with LAZDIAG, the library when the tier wants it, and the
    tool -- the tool LAST, so a table registered at load is the one
    the file on disk carries."""
    vm = VM()
    vm.env["USERPROFILE"] = r"C:\Users\dm"
    if tier == "shared":
        vm.load(str(LIB))
        vm.load(str(twin_of(LAZDIAG)))
        p = twin_of(path)
        if p is None:
            return None
        vm.load(str(p))
    else:
        vm.load(str(LAZDIAG))
        vm.load(str(path))
    vm.printed = []
    return vm


def names_of(path):
    src = pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
    return cz.run_names(src, cz.code_mask(src))


def run_file(path, tier, say=print):
    """(problems, lines) for one file at one tier."""
    problems, lines = [], []
    names = names_of(path)
    if not names:
        return problems, ["  (no command reports a run, so nothing would run a table)"]
    vm = load(path, tier)
    if vm is None:
        return problems, ["  (no %s twin)" % tier]
    before = dict(vm.sysvars)
    nents = len(vm.entities)
    nfiles = len(vm.files)
    # one table per file, registered under several names: the first
    # name is the tool's own, and the others must find the same table
    fn = vm.loads('(lzd:tests-of "%s")' % names[0])
    if fn is None:
        problems.append("no table registered for %s" % names[0])
        return problems, ["  (none registered for %s)" % names[0]]
    for n in names[1:]:
        if vm.loads('(lzd:tests-of "%s")' % n) != fn:
            problems.append("%s is not registered to the same table as %s"
                            % (n, names[0]))
    passed, total, out = vm.loads('(lzd:selftest-run "%s")' % names[0])
    lines.extend(out)
    lines.extend(vm.loads('(lzd:selftest-verdict "%s" %d %d)'
                          % (names[0], passed, total)) or [])
    if total < cz.MIN_TESTS:
        problems.append("%d entr%s, the check wants %d"
                        % (total, "y" if total == 1 else "ies", cz.MIN_TESTS))
    if passed < total:
        problems.append("%d of %d FAILED" % (total - passed, total))
    if vm.prompts:
        problems.append("a table PROMPTED: %r" % (vm.prompts[0][0],))
    if vm.commands:
        problems.append("a table ran a COMMAND: %r" % (vm.commands[0],))
    if len(vm.entities) != nents:
        problems.append("a table DREW %d entit%s"
                        % (len(vm.entities) - nents,
                           "y" if len(vm.entities) - nents == 1 else "ies"))
    if len(vm.files) != nfiles:
        problems.append("a table WROTE a file: %s"
                        % sorted(set(vm.files) - set())[0])
    moved = [k for k in before if vm.sysvars.get(k) != before[k]]
    if moved:
        problems.append("a table MOVED a sysvar: %s" % ", ".join(sorted(moved)))
    return problems, lines


def main(argv):
    tier = "lisp"
    args = []
    i = 0
    while i < len(argv):
        if argv[i] == "--tier":
            tier = argv[i + 1]
            i += 2
            continue
        args.append(argv[i])
        i += 1
    files = [pathlib.Path(a) for a in args] or [
        p for p in lsp_files(LISP_DIR) if NOT_A_TOOL not in p.parts]
    tiers = ["lisp", "shared"] if tier == "both" else [tier]
    bad = 0
    for path in files:
        for t in tiers:
            print("== %s (%s tier)" % (path, t))
            problems, lines = run_file(path, t)
            for l in lines:
                print(l)
            for pr in problems:
                print("  PROBLEM  " + pr)
            bad += len(problems)
    if bad:
        print("run_selftests: %d problem(s)" % bad)
        return 1
    print("run_selftests: every table passed (%s)" % ", ".join(tiers))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
