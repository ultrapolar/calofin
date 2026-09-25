#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""LAZDIAG runs the failed tool's self tests and writes them into the report.

A report says what the run did; the tool's own SELF TESTS say whether
its helpers were sound on the machine it ran on (LAZDIAG.lsp, "the
tool's own self tests").  This drives that path with fixture tools and
reads the report back.  What has to hold:

  * a failure runs the failed tool's table and writes one line per
    entry -- ok with the value, FAIL with expected and got, FAIL naming
    the error an entry raised, FAIL for an entry that is not one -- and
    a verdict that counts them;
  * a tool with no table is said to have none, and a table whose
    builder throws is one FAIL line, not a report that could not be
    written;
  * the log's FAIL record carries the count;
  * a command that failed INSIDE another's run gets its own table run
    under the outer tool's report;
  * the LAZDIAG self test, with nothing failed, runs EVERY table loaded
    and names each tool once, with its FAILs under it;
  * a table longer than lzd:*selfmax* is cut and the cut is named;
  * check_lazdiag's half: --fix writes a skeleton registered under
    every name a file reports as, an unsafe call is named, and a full
    table passes.

Run: python3 tests/test_lazdiag_selftests.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_lazdiag_selftests.py
"""

import os
import re
import sys
import tempfile

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

from lispvm import VM  # noqa: E402
import check_lazdiag as cz  # noqa: E402

LAZDIAG = os.path.join(REPO_DIR, "lisp", "lazdiag", "LAZDIAG.lsp")
PROFILE = r"C:\Users\dm"

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def newvm():
    vm = VM()
    vm.load(LAZDIAG)
    vm.env["USERPROFILE"] = PROFILE
    vm.handle_errors = True
    vm.printed = []
    return vm


FX = '''
(setq *fx-version* "v0.1")
(defun fx:double (x) (* 2 x))
(defun fx:selftests ()
  (list (list "double 2" '(fx:double 2) 4)
        (list "double 3 wrong" '(fx:double 3) 7)
        (list "raises" '(car 1) 1)
        (list "predicate" '(fx:double 5))
        (list "predicate nil" '(null 1))
        "junk"))
(foreach c '("FX")
  (setq *calofin-selftests* (cons (cons c 'fx:selftests) *calofin-selftests*)))
(defun c:FX ( / *error* p)
  (defun *error* (m)
    (if lzd:report (lzd:report "FX" *fx-version* m))
    (princ))
  (if lzd:begin (lzd:begin "FX" *fx-version*))
  (setq p (getpoint "\\nPick: "))
  (if lzd:ask (lzd:ask "Pick" p) p)
  (car 1)
  (if lzd:end (lzd:end "FX"))
  (princ))
'''

FY = '''
(setq *fy-version* "v0.2")
(defun c:FY ( / *error*)
  (defun *error* (m)
    (if lzd:report (lzd:report "FY" *fy-version* m))
    (princ))
  (if lzd:begin (lzd:begin "FY" *fy-version*))
  (car 1)
  (if lzd:end (lzd:end "FY"))
  (princ))
'''


def report_text(vm):
    """The report's text lines, top to bottom, out of the one DXF the VM
    wrote: each TEXT entity's group 1."""
    bodies = [v for k, v in vm.files.items() if k.endswith(".dxf")]
    if len(bodies) != 1:
        return None
    lines = bodies[0].split("\n")
    return [lines[i + 1] for i, l in enumerate(lines)
            if l.strip() == "1" and i + 1 < len(lines)]


def logof(vm):
    hits = [v for k, v in vm.files.items() if k.endswith(".log")]
    return hits[0] if hits else ""


# ------------------------------------------------------------ the section
print("a failure runs the tool's table and writes it into the report")
vm = newvm()
vm.loads(FX)
vm.run("c:FX", [[1.0, 2.0, 0.0]])
txt = report_text(vm)
check("one report was written", txt is not None, str(list(vm.files)))
txt = txt or []
check("the section is titled",
      "THE TOOL'S OWN SELF TESTS, RUN HERE AFTER THE FAILURE" in txt)
check("a passing entry is ok with its value",
      "  ok    double 2 = 4" in txt)
check("a failing entry names expected and got",
      "  FAIL  double 3 wrong: expected 7, got 6" in txt)
check("an entry that raises names the error",
      any(l.startswith("  FAIL  raises: raised car: not a list") for l in txt),
      str([l for l in txt if "raises" in l]))
check("a predicate entry writes its value",
      "  ok    predicate = 10" in txt)
check("a nil predicate fails", "  FAIL  predicate nil: nil" in txt)
check("an entry that is not one is named, not died on",
      '  FAIL  (not an entry: "junk")' in txt)
check("the verdict counts them",
      any(l.startswith("  2 of 6 passed.  A FAIL is FX's own code") for l in txt),
      str([l for l in txt if "of 6" in l]))
i_cannot = next((i for i, l in enumerate(txt)
                 if l.startswith("WHAT THIS REPORT CANNOT TELL YOU")), -1)
i_self = next((i for i, l in enumerate(txt)
               if l.startswith("THE TOOL'S OWN SELF TESTS")), -1)
i_inputs = next((i for i, l in enumerate(txt)
                 if l.startswith("THE INPUTS, AND WHAT IS ODD")), -1)
check("the section sits after what the report cannot tell and before "
      "the inputs", 0 <= i_cannot < i_self < i_inputs,
      "%d %d %d" % (i_cannot, i_self, i_inputs))
check("the log's FAIL record carries the count",
      "    self  FX 2/6 passed" in logof(vm), logof(vm))
check("the drawing was not touched and nothing was asked by the tests",
      len(vm.prompts) == 1 and not vm.commands,
      "%r %r" % (vm.prompts, vm.commands))
check("the drafter was told a report was written",
      any("error report has been" in p for p in vm.printed), str(vm.printed[-6:]))

print("a tool with no table, and a table whose builder throws")
vm = newvm()
vm.loads(FY)
vm.run("c:FY", [])
txt = report_text(vm) or []
check("no table: said so, in the section",
      "  (none registered for FY -- the tool predates self tests)" in txt,
      str([l for l in txt if "FY" in l][:4]))
check("no table: the log says none registered",
      "    self  FY no self tests registered" in logof(vm), logof(vm))

vm = newvm()
vm.loads(FY)
vm.loads('''(defun fy:selftests () (car 1))
(setq *calofin-selftests* (cons (cons "FY" 'fy:selftests) *calofin-selftests*))''')
vm.run("c:FY", [])
txt = report_text(vm) or []
check("a throwing builder is one FAIL line and the report still lands",
      any(l.startswith("  FAIL  the table itself raised") for l in txt)
      and any("error report has been" in p for p in vm.printed),
      str([l for l in txt if "table" in l]))
check("a throwing builder counts as 0 of 1",
      "    self  FY 0/1 passed" in logof(vm), logof(vm))

vm = newvm()
vm.loads(FY)
vm.loads('''(defun fy:selftests () "not a list")
(setq *calofin-selftests* (cons (cons "FY" 'fy:selftests) *calofin-selftests*))''')
vm.run("c:FY", [])
txt = report_text(vm) or []
check("a table that is not a list is said to be one",
      '  FAIL  the table is not a list: "not a list"' in txt)

print("the newest registration wins")
vm = newvm()
vm.loads(FX)
vm.loads('''(defun fx:selftests2 () (list (list "new table" '(+ 1 1) 2)))
(setq *calofin-selftests* (cons (cons "fx" 'fx:selftests2) *calofin-selftests*))''')
vm.run("c:FX", [[1.0, 2.0, 0.0]])
txt = report_text(vm) or []
check("a file loaded again runs its new table, looked up case-blind",
      "  ok    new table = 2" in txt and "  ok    double 2 = 4" not in txt)

# ------------------------------------------------- inside another's run
print("a command that failed inside another's run")
vm = newvm()
vm.loads(FX)
vm.loads('''
(setq *fo-version* "v0.3")
(defun fo:selftests () (list (list "outer one" '(+ 2 2) 4)))
(foreach c '("FO")
  (setq *calofin-selftests* (cons (cons c 'fo:selftests) *calofin-selftests*)))
(defun c:FO ( / *error*)
  (defun *error* (m)
    (if lzd:report (lzd:report "FO" *fo-version* m))
    (princ))
  (if lzd:begin (lzd:begin "FO" *fo-version*))
  (c:FX)
  (if lzd:end (lzd:end "FO"))
  (princ))
''')
vm.run("c:FO", [[1.0, 2.0, 0.0]])
txt = report_text(vm) or []
check("the report is the outer tool's",
      any(l.startswith("  tool          FO v0.3") for l in txt),
      str([l for l in txt if l.startswith("  tool")]))
check("both tables ran, the outer first, each under its name",
      "  FO:" in txt and "  FX:" in txt and "  ok    outer one = 4" in txt
      and "  ok    double 2 = 4" in txt
      and txt.index("  FO:") < txt.index("  FX:"),
      str([l for l in txt if l.endswith(":")]))
check("the log carries both counts",
      "    self  FO 1/1 passed" in logof(vm)
      and "    self  FX 2/6 passed" in logof(vm), logof(vm))

# ------------------------------------------------------------- the sweep
print("the LAZDIAG self test runs every table loaded")
vm = newvm()
vm.loads(FX)
vm.loads('''
(defun fz:selftests () (list (list "one" '(+ 1 1) 2) (list "two" '(+ 1 1) 2)))
(foreach c '("FZ" "FZSCAN")
  (setq *calofin-selftests* (cons (cons c 'fz:selftests) *calofin-selftests*)))
''')
vm.run("c:LAZDIAG", [])
txt = report_text(vm) or []
check("the sweep is titled",
      "SELF TESTS OF EVERY TOOL LOADED IN THIS SESSION" in txt)
rows = [l for l in txt if re.match(r"^  [A-Z]+ +\d+ of \d+ passed$", l)]
names = [l.split()[0] for l in rows]
check("every table once, named by its first command, LAZDIAG's included",
      names == ["LAZDIAG", "FX", "FZ"], str(names))
check("a table registered under two commands is run once",
      "FZSCAN" not in names and "  FZ                  2 of 2 passed" in txt)
check("FAILs are listed under their tool, and oks are not",
      "    FAIL  double 3 wrong: expected 7, got 6" in txt
      and not any("double 2" in l for l in txt))
said = [p for p in vm.printed if "Self tests of" in p]
check("the drafter is told the sum at the command line",
      said and "3 loaded tool(s)" in said[0] and "names each FAIL" in said[0],
      str(said))
check("LAZDIAG's own table passes",
      any(re.match(r"^  LAZDIAG +(\d+) of \1 passed$", l) for l in txt),
      str([l for l in txt if l.startswith("  LAZDIAG")]))
check("the self test asked nothing, and ran nothing but its own undo group",
      not vm.prompts and all(c[0] == "_.UNDO" for c in vm.commands),
      "%r %r" % (vm.prompts, vm.commands))

vm = newvm()
vm.run("c:LAZDIAG", [])
said = [p for p in vm.printed if "Self tests of" in p]
check("with only LAZDIAG loaded the sum is all passed",
      said and "1 loaded tool(s)" in said[0] and said[0].endswith("passed."),
      str(said))

# --------------------------------------------------------------- the cap
print("a table longer than lzd:*selfmax* is cut")
vm = newvm()
vm.loads(FY)
vm.loads('''(defun fy:selftests ( / out i)
  (setq i 0)
  (repeat 45 (setq out (cons (list (strcat "n" (itoa i)) '(+ 1 1) 2) out) i (1+ i)))
  out)
(setq *calofin-selftests* (cons (cons "FY" 'fy:selftests) *calofin-selftests*))''')
vm.run("c:FY", [])
txt = report_text(vm) or []
check("40 run and 5 named as not run",
      "  (5 more not run: lzd:*selfmax* is 40)" in txt
      and "    self  FY 40/40 passed" in logof(vm),
      str([l for l in txt if "not run" in l]) + logof(vm))

# ------------------------------------------------------ check_lazdiag's half
print("check_lazdiag: the skeleton, the registration, the unsafe call")
TMP = tempfile.mkdtemp(prefix="calofin-selftests-")
BARE = '''(setq *fb-version* "v0.1")
(defun fb:twice (x) (* 2 x))
(defun c:FB ( / *error*)
  (defun *error* (m)
    (if lzd:report (lzd:report "FB" *fb-version* m))
    (princ))
  (if lzd:begin (lzd:begin "FB" *fb-version*))
  (if lzd:end (lzd:end "FB"))
  (princ))
(defun c:FBSCAN ( / *error*)
  (defun *error* (m)
    (if lzd:report (lzd:report "FBSCAN" *fb-version* m))
    (princ))
  (if lzd:begin (lzd:begin "FBSCAN" *fb-version*))
  (if lzd:end (lzd:end "FBSCAN"))
  (princ))
;; the banner
(if (not *calofin-quiet*)
  (princ (strcat "\\nFB " *fb-version* " loaded.")))
(princ)
'''
path = os.path.join(TMP, "FB.lsp")
findings, edits = cz.selftests(path, BARE, cz.code_mask(BARE), True)
check("a file with no table is named", any("no self-test table" in f for f in findings),
      str(findings))
check("--fix has a skeleton to write", len(edits) == 1)
src = BARE
for e in sorted(edits, key=lambda e: -e[0]):
    src = src[:e[0]] + e[1] + src[e[0]:]
check("the skeleton is named after the file's helper prefix",
      "(defun fb:selftests ()" in src)
check("it is registered under every name the file reports as",
      '(foreach c \'("FB" "FBSCAN")' in src, src)
check("it sits ahead of the banner's comment block",
      src.index("(defun fb:selftests") < src.index(";; the banner"))
findings, _ = cz.selftests(path, src, cz.code_mask(src), False)
check("an empty table is named, with the minimum",
      any("holds 0 entries" in f and str(cz.MIN_TESTS) in f for f in findings),
      str(findings))
vm = VM()
vm.load(LAZDIAG)
vm.loads(src)
check("the skeleton loads and registers an empty table",
      vm.loads('(lzd:tests-of "FBSCAN")') is not None
      and vm.loads('(cadr (lzd:selftest-run "FB"))') == 0)

full = src.replace(
    "    ;; write at least %d:\n" % cz.MIN_TESTS, "").replace(
    "    ;;   (list \"what it checks\" '(fb:helper args) expected)\n",
    '    (list "twice 2" \'(fb:twice 2) 4)\n'
    '    (list "twice 0" \'(fb:twice 0) 0)\n'
    '    (list "twice is even" \'(= 0 (rem (fb:twice 7) 2)))\n')
findings, _ = cz.selftests(path, full, cz.code_mask(full), False)
check("three entries and the check is satisfied", not findings, str(findings))
vm = VM()
vm.load(LAZDIAG)
vm.loads(full)
check("and the table passes", vm.loads('(car (lzd:selftest-run "FB"))') == 3)

bad = full.replace("(list \"twice 0\" '(fb:twice 0) 0)",
                   "(list \"asks\" '(getpoint \"\\\\nWhere: \"))")
findings, _ = cz.selftests(path, bad, cz.code_mask(bad), False)
check("an entry that prompts is refused by name",
      any("calls getpoint" in f for f in findings), str(findings))
bad = full.replace("(list \"twice 0\" '(fb:twice 0) 0)",
                   "(list \"com\" '(vlax-get-acad-object))")
findings, _ = cz.selftests(path, bad, cz.code_mask(bad), False)
check("an entry that reaches COM is refused by prefix",
      any("vlax-get-acad-object" in f for f in findings), str(findings))

wrong = full.replace('(foreach c \'("FB" "FBSCAN")', '(foreach c \'("FB")')
findings, edits = cz.selftests(path, wrong, cz.code_mask(wrong), True)
check("a registration short of a name is named and rewritten",
      any("rewrites" in f for f in findings) and len(edits) == 1,
      str(findings))
src2 = wrong[:edits[0][0]] + edits[0][1] + wrong[edits[0][2]:]
check("the rewrite carries both names",
      '(foreach c \'("FB" "FBSCAN")' in src2)

if failures:
    print("test_lazdiag_selftests: %d FAILURE(S): %s"
          % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("test_lazdiag_selftests: all checks passed")
