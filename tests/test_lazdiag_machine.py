#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The report records the MACHINE, and LAZLAST reports a run that did not fail.

The classic field failure is a setting, not a line of code: ANGDIR
turned clockwise, PICKFIRST off, ATTDIA on, a LOCKED layer, a knob
LAZTUNE moved on one machine, an old copy of a tool APPLOADed over the
build -- and none of it can be seen from a transcript.  So a report
writes the machine down (LAZDIAG.lsp, "the machine, and what it has
changed").  What has to hold:

  * THE MACHINE lists the sysvars and FLAGS the ones set the way that
    breaks a tool, with the reason, and says when none is;
  * THE LAYERS THE RUN TOUCHED names each layer's state and flags a
    LOCKED one, the current layer included;
  * WHAT THIS MACHINE HAS CHANGED lists every LAZTUNE override as the
    drafter typed it, with the value the session holds now, the shop
    terms, the theme and the folders -- and says when there is none;
  * CALOFIN FILES LOADED lists every version banner bound;
  * THE INPUTS flags a pick far from the geometry and one off the plane;
  * a run that never ended is logged LOST by the next run's begin, from
    the journal, and a run that ended clears the journal;
  * LAZLAST writes the last finished run as a RUN report -- its
    transcript, what was drawn since it began, its self tests -- and
    says so when there is none; this file's own commands are never it;
  * every section is built under its own catch, so a builder that
    throws costs one line, not the report.

Run: python3 tests/test_lazdiag_machine.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_lazdiag_machine.py
"""

import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

from lispvm import VM, LispError  # noqa: E402

LAZDIAG = os.path.join(REPO_DIR, "lisp", "lazdiag", "LAZDIAG.lsp")
SQUAREUP = os.path.join(REPO_DIR, "lisp", "squareup", "SQUAREUP.lsp")
PROFILE = r"C:\Users\dm"
JOURNAL = PROFILE + r"\calofin\calofin-run.journal"

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def newvm(journal=None):
    vm = VM()
    vm.env["USERPROFILE"] = PROFILE
    if journal is not None:
        vm.files[JOURNAL] = journal
        vm.dirs.add(PROFILE + r"\calofin")
    vm.load(LAZDIAG)
    vm.load(SQUAREUP)
    vm.handle_errors = True
    vm.printed = []
    return vm


FZ = '''
(defun c:FZ ( / *error* p q)
  (defun *error* (m)
    (if lzd:report (lzd:report "FZ" "v0.1" m))
    (princ))
  (if lzd:begin (lzd:begin "FZ" "v0.1"))
  (if lzd:watch (lzd:watch (ssget "_X")) nil)
  (setq p (getpoint "\\nA: "))
  (if lzd:ask (lzd:ask "A" p) p)
  (setq q (getpoint "\\nB: "))
  (if lzd:ask (lzd:ask "B" q) q)
  (car 1)
  (if lzd:end (lzd:end "FZ"))
  (princ))
'''

FY = '''
(defun c:FY ( / *error* p)
  (defun *error* (m)
    (if lzd:report (lzd:report "FY" "v0.2" m))
    (princ))
  (if lzd:begin (lzd:begin "FY" "v0.2"))
  (setq p (getpoint "\\nWhere: "))
  (if lzd:ask (lzd:ask "Where" p) p)
  (entmake (list '(0 . "CIRCLE") (cons 10 p) '(40 . 2.0)))
  (if lzd:end (lzd:end "FY"))
  (princ))
'''


def layer(vm, name, flags=0, color=4):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
             ' \'(62 . %d) \'(6 . "Continuous")))' % (name, flags, color))


def line(vm, a, b, lay):
    vm.loads('(entmake (list \'(0 . "LINE") (cons 8 "%s") (list 10 %r %r 0.0)'
             ' (list 11 %r %r 0.0)))' % (lay, a[0], a[1], b[0], b[1]))


def report(vm, kind="error"):
    hits = [(k, v) for k, v in vm.files.items()
            if k.endswith(".dxf") and ("-%s-" % kind) in k]
    if len(hits) != 1:
        return None, []
    k, body = hits[0]
    lines = body.split("\n")
    return k, [lines[i + 1] for i, l in enumerate(lines)
               if l.strip() == "1" and i + 1 < len(lines)]


def logof(vm):
    hits = [v for k, v in vm.files.items() if k.endswith(".log")]
    return hits[0] if hits else ""


def section(txt, title):
    """The lines of one section, title to the next blank line."""
    if title not in txt:
        return None
    i = txt.index(title) + 1
    out = []
    while i < len(txt) and txt[i] != "":
        out.append(txt[i])
        i += 1
    return out


def boom(v):
    raise LispError("bad argument type: numberp: nil", v)


# ------------------------------------------------------------ the machine
print("THE MACHINE, its hazards flagged")
vm = newvm()
vm.loads(FZ)
vm.sysvars["ANGDIR"] = 1
vm.sysvars["PICKFIRST"] = 0
vm.sysvars["EXPERT"] = 2
vm.sysvars["ATTDIA"] = 1
vm.sysvars["OSNAPCOORD"] = 0
vm.sysvars["REFEDITNAME"] = "TITLEBLOCK"
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
path, txt = report(vm)
check("a report was written", path is not None)
mach = section(txt, "THE MACHINE") or []
check("the sysvars are recorded",
      any(l.startswith("  PICKFIRST") for l in mach)
      and any(l.startswith("  DIMZIN") for l in mach)
      and any(l.startswith("  ATTDIA") for l in mach), str(mach[:5]))
flags = [l for l in mach if l.startswith("  !! ")]
names = sorted(l.split()[1] for l in flags)
check("each setting known to break a tool is flagged, with its value and why",
      names == ["ANGDIR", "ATTDIA", "EXPERT", "OSNAPCOORD", "PICKFIRST",
                "REFEDITNAME"]
      and any("CLOCKWISE" in l for l in flags)
      and any("ANGDIR = 1" in l for l in flags), str(names))
check("a default-valued switch is not flagged",
      not any("PEDITACCEPT" in l or "OFFSETGAPTYPE" in l for l in flags))

vm = newvm()
vm.loads(FZ)
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
path, txt = report(vm)
mach = section(txt, "THE MACHINE") or []
check("on a plain machine the report says nothing is set that way",
      any("none of them is set the way that breaks one" in l for l in mach)
      and not any(l.startswith("  !! ") for l in mach), str(mach[-3:]))

# -------------------------------------------------------------- the layers
print("THE LAYERS THE RUN TOUCHED")
vm = newvm()
vm.loads(FZ)
layer(vm, "POOL", flags=4)          # locked
layer(vm, "DIM", flags=1, color=-3)  # frozen and off
layer(vm, "NOTES")
vm.sysvars["CLAYER"] = "NOTES"
line(vm, (0, 0), (10, 0), "POOL")
line(vm, (0, 1), (10, 1), "DIM")
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
path, txt = report(vm)
lay = section(txt, "THE LAYERS THE RUN TOUCHED") or []
check("the locked layer the run was handed is named LOCKED",
      any(l.startswith("  POOL") and "LOCKED" in l for l in lay), str(lay))
check("a frozen, off layer says both",
      any(l.startswith("  DIM") and "frozen" in l and "off" in l for l in lay))
check("the current layer is named as such, plain",
      any(l.startswith("  NOTES") and "plain" in l and "current layer" in l
          for l in lay))
check("a locked layer draws the warning",
      any("refuses every entmod" in l for l in lay))

vm = newvm()
vm.loads(FZ)
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
path, txt = report(vm)
lay = section(txt, "THE LAYERS THE RUN TOUCHED") or []
check("with nothing locked there is no warning",
      not any("refuses" in l for l in lay) and lay, str(lay))

# --------------------------------------------------- what the machine changed
print("WHAT THIS MACHINE HAS CHANGED FROM SHIPPED")
vm = newvm()
vm.loads(FZ)
vm.env["CalofinKnobs"] = "sq:*tie-frac*;sq:*square-deg*"
vm.env["CalofinKnob-sq.~tie-frac~"] = "0.25"
vm.env["CalofinKnob-sq.~square-deg~"] = "2.0"
vm.env["CalofinTheme"] = "dark"
vm.env["CalofinErrorDir"] = r"C:\shop\reports"
vm.loads("(setq sq:*tie-frac* 0.25)")     # this one applied, the other not
vm.loads('(setq lzp:*terms* \'(("typ-note" " Typ." "x" ("pool:*typ-note*"))))')
vm.env["CalofinTerm-typ-note"] = " TYP"
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
path, txt = report(vm)
ch = section(txt, "WHAT THIS MACHINE HAS CHANGED FROM SHIPPED") or []
check("every override is a = name -> text line, as typed",
      "  = sq:*tie-frac*  -> 0.25" in ch and "  = sq:*square-deg*  -> 2.0" in ch,
      str(ch))
i = ch.index("  = sq:*tie-frac*  -> 0.25") if "  = sq:*tie-frac*  -> 0.25" in ch else -1
j = ch.index("  = sq:*square-deg*  -> 2.0") if "  = sq:*square-deg*  -> 2.0" in ch else -1
check("the session's own value follows each: one in effect, one not",
      i >= 0 and j >= 0 and ch[i + 1].startswith("      now 0.25")
      and ch[j + 1].startswith("      now 0.01"),
      str(ch[i + 1:i + 2] + ch[j + 1:j + 2]))
check("the shop term, the theme and the folder are listed",
      any(l.startswith("  term typ-note") and '" TYP"' in l for l in ch)
      and any(l.startswith("  CalofinTheme") and "dark" in l for l in ch)
      and any(l.startswith("  CalofinErrorDir") for l in ch), str(ch))

vm = newvm()
vm.loads(FZ)
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
path, txt = report(vm)
ch = section(txt, "WHAT THIS MACHINE HAS CHANGED FROM SHIPPED") or []
check("with no override the section says so",
      any("no LAZTUNE knob is overridden" in l for l in ch), str(ch))

# ------------------------------------------------------------- the roster
print("CALOFIN FILES LOADED IN THIS SESSION")
vm = newvm()
vm.loads(FZ)
vm.loads('(setq pool:*version* "092526 REV50")')
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
path, txt = report(vm)
title = next((l for l in txt if l.startswith("CALOFIN FILES LOADED")), "")
ro = section(txt, title) or []
check("both banner spellings are found, with their versions",
      int(title.rsplit("(", 1)[1].rstrip(")")) >= 3   # the library adds one at the shared tier
      and any(l.startswith("  *squareup-version*") and "v1.3" in l for l in ro)
      and any(l.startswith("  pool:*version*") and "REV50" in l for l in ro)
      and any(l.startswith("  *lazdiag-version*") for l in ro),
      title + " " + str(ro))

# ------------------------------------------------------------ the oddities
print("THE INPUTS: a far pick and a pick off the plane")
vm = newvm()
vm.loads(FZ)
line(vm, (0, 0), (10, 0), "0")
vm.run("c:FZ", [[50000.0, 0.0, 0.0], [1.0, 1.0, 3.5]])
path, txt = report(vm)
odd = section(txt, "THE INPUTS, AND WHAT IS ODD ABOUT THEM") or []
check("a pick a long way from the geometry is flagged, with the distance",
      any(l.startswith("  ODD  A") and "far from the geometry" in l
          and "49995" in l for l in odd), str(odd))
check("a pick with a Z is flagged",
      any(l.startswith("  ODD  B") and "off the plane (z = 3.5" in l for l in odd),
      str(odd))
vm = newvm()
vm.loads(FZ)
line(vm, (0, 0), (10, 0), "0")
vm.run("c:FZ", [[12.0, 0.0, 0.0], [1.0, 1.0, 0.0]])
path, txt = report(vm)
odd = section(txt, "THE INPUTS, AND WHAT IS ODD ABOUT THEM") or []
check("a pick beside the geometry is not far",
      not any("far from" in l for l in odd), str(odd))

# ------------------------------------------------------------- the journal
print("the journal: a run that never ended is LOST")
vm = newvm(journal="POOL 092526 REV50  standalone  job.dwg  begun 2026-08-20 09:12\n")
vm.loads(FY)
vm.run("c:FY", [[3.0, 4.0, 0.0]])
log = logof(vm)
check("the next run's begin logs the journal's run as LOST, with the drawing",
      "  LOST   POOL 092526 REV50  standalone  job.dwg  begun 2026-08-20 09:12"
      in log and "never wrote its end" in log, log)
check("and its own line went in, then out again when it ended",
      vm.files.get(JOURNAL, "x").strip() == "", repr(vm.files.get(JOURNAL)))
check("the LOST record comes before the run's own ok",
      log.index("LOST") < log.index("  ok     FY"), log)

vm = newvm()
vm.loads(FY)
vm.run("c:FY", [[3.0, 4.0, 0.0]])
check("no journal, no LOST", "LOST" not in logof(vm), logof(vm))

vm = newvm()
vm.loads(FZ)
vm.loads('''(defun c:FW ( / *error* p)
  (defun *error* (m) (if lzd:report (lzd:report "FW" "v0.3" m)) (princ))
  (if lzd:begin (lzd:begin "FW" "v0.3"))
  (setq p (getpoint "\\nWhere: "))
  (if lzd:ask (lzd:ask "Where" p) p)
  (princ))''')                              # no lzd:end: the lazy path
vm.run("c:FW", [[1.0, 1.0, 0.0]])
journal_after = vm.files.get(JOURNAL, "")
check("a run with no end leaves its line in the journal",
      journal_after.startswith("FW v0.3"), repr(journal_after))
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
log = logof(vm)
check("the next begin, with that context standing, logs it ok and not LOST",
      "  ok     FW v0.3" in log and "LOST" not in log, log)
check("a failure clears the journal too",
      vm.files.get(JOURNAL, "x").strip() == "", repr(vm.files.get(JOURNAL)))

vm = newvm()
vm.loads(FY)
def esc(v):
    raise LispError("Function cancelled", v)
vm.run("c:FY", [esc])
check("a cancel clears the journal",
      vm.files.get(JOURNAL, "x").strip() == "" and "quit" in logof(vm),
      repr(vm.files.get(JOURNAL)) + logof(vm))

# ---------------------------------------------------------------- LAZLAST
print("LAZLAST: the run that did not fail")
vm = newvm()
vm.loads(FY)
vm.run("c:FY", [[3.0, 4.0, 0.0]])
vm.run("c:LAZLOG", [])
vm.run("c:LAZLAST", [])
path, txt = report(vm, "lastrun")
check("a lastrun report was written, named for the tool that ran, not LAZLOG",
      path is not None and "FY-v0.2-lastrun-" in path, str(list(vm.files)))
t0 = next((i for i, l in enumerate(txt) if l.startswith("CALOFIN ")), -1)
check("it is titled as a RUN report and says nothing failed",
      t0 >= 0 and txt[t0].startswith("CALOFIN RUN REPORT -- no failure")
      and txt[t0 + 1] == "=" * len(txt[t0]), str(txt[t0:t0 + 2]))
check("the tool line and the message say whose it is and why it exists",
      any(l.startswith("  tool          FY v0.2") for l in txt)
      and any("asked for this run's report with LAZLAST" in l for l in txt))
check("the transcript of the run is in it",
      any(l.startswith("  ? Where") and "3.0" in l for l in txt), str(txt[-12:]))
check("what was drawn since the run began is in it, and said to be",
      any(l.startswith("  entities      1") for l in txt)
      and any("later commands' work included" in l for l in txt))
check("its self tests are titled for a request, not a failure",
      "THE TOOL'S OWN SELF TESTS, RUN HERE ON REQUEST" in txt
      and "AFTER THE FAILURE" not in "\n".join(txt))
check("the drafter is told where it went and what to add",
      any("The last run, FY v0.2, is written to" in p for p in vm.printed)
      and any("what came out" in p for p in vm.printed))
check("the log carries a NOTE for it, and LAZLAST's own ok",
      "  NOTE   FY v0.2  reported on request (LAZLAST)" in logof(vm)
      and "  ok     LAZLAST" in logof(vm), logof(vm))
check("LAZLAST asked nothing and drew nothing",
      not vm.prompts and not vm.commands)
check("no error report was written by it",
      not any("-error-" in k for k in vm.files))

vm = newvm()
vm.run("c:LAZLAST", [])
check("with no run finished yet it says so and writes nothing",
      any("no run to report" in p for p in vm.printed)
      and not any(k.endswith(".dxf") for k in vm.files), str(vm.printed[-3:]))

vm = newvm()
vm.loads(FY)
vm.run("c:FY", [[3.0, 4.0, 0.0]])
vm.run("c:LAZLAST", [])
vm.run("c:LAZLAST", [])
check("LAZLAST twice reports the same run twice, never itself",
      sum(1 for k in vm.files if "FY-v0.2-lastrun-" in k) == 2
      and not any("LAZLAST-" in k for k in vm.files), str(list(vm.files)))

# ------------------------------------------------- a section that throws
print("a section builder that throws costs one line")
vm = newvm()
vm.loads(FZ)
vm.loads("(defun lzd:loaded-lines () (car 1))")
vm.run("c:FZ", [[1.0, 1.0, 0.0], [2.0, 2.0, 0.0]])
path, txt = report(vm)
check("the report still lands, with the section's failure named",
      path is not None
      and any("this section could not be written" in l for l in txt)
      and "THE MACHINE" in txt and "THE INPUTS, AND WHAT IS ODD ABOUT THEM" in txt,
      str([l for l in txt if "could not" in l]))

# ------------------------------------------ the probe, under that machine
print("probe_report replays under the report's machine and overrides")
import tempfile
import probe_report as pr

TMP = tempfile.mkdtemp(prefix="calofin-machine-")
FK = """(setq *fk-version* "v0.4")
(setq fk:*cap* 1)
(defun fk:selftests () (list (list "cap is a number" '(numberp fk:*cap*))
                             (list "one is one" '(+ 0 1) 1)
                             (list "two is two" '(+ 1 1) 2)))
(foreach c '("FK")
  (setq *calofin-selftests* (cons (cons c 'fk:selftests) *calofin-selftests*)))
(defun c:FK ( / *error* d)
  (defun *error* (m)
    (if lzd:report (lzd:report "FK" *fk-version* m))
    (princ))
  (if lzd:begin (lzd:begin "FK" *fk-version*))
  (setq d (getdist "\\nHow long: "))
  (if lzd:ask (lzd:ask "How long" d) d)
  (if (> fk:*cap* 5) (car 1))
  (if lzd:end (lzd:end "FK"))
  (princ))
"""
fk = os.path.join(TMP, "FK.lsp")
with open(fk, "w") as f:
    f.write(FK)
vm = VM()
vm.env["USERPROFILE"] = PROFILE
vm.load(LAZDIAG)
vm.load(fk)
vm.loads(pr.STUBS)
vm.handle_errors = True
# the drafter's machine: the knob moved to 10 through LAZTUNE, and DIMZIN 8
vm.env["CalofinKnobs"] = "fk:*cap*"
vm.env["CalofinKnob-fk.~cap~"] = "10"
vm.loads("(setq fk:*cap* 10)")
vm.sysvars["DIMZIN"] = 8
vm.sysvars["LUNITS"] = 4
vm.run("c:FK", [12.5])
path, txt = report(vm)
check("the knob-caused failure wrote a report",
      path is not None and any("  = fk:*cap*  -> 10" in l for l in txt))
rep_path = os.path.join(TMP, "FK.dxf")
with open(rep_path, "w") as f:
    f.write(vm.files[path])
res = pr.probe(rep_path, tool_path=fk, cap=4, control_only=True)
check("the probe read the machine and the override out of the report",
      res.data["machine"].get("DIMZIN") == "8"
      and res.data["machine"].get("LUNITS") == "4"
      and res.data["knobs"] == [{"name": "fk:*cap*", "text": "10"}],
      str((res.data["machine"], res.data["knobs"])))
check("and put them on the replay, so the control run REPRODUCES",
      res.data["reproduced"] and res.data["control"]["kind"] == "FAIL",
      str(res.data["control"]))
check("the probe's text says what it put on",
      any(l.startswith("THE MACHINE, PUT ON THE REPLAY") for l in res.lines)
      and any("knob fk:*cap*" in l and "= 10" in l for l in res.lines),
      "\n".join(res.lines[:14]))
# without the override the same run goes clean: that is the finding
vm2 = pr.build_vm(fk, [], [], 0, False, None, (), res.data["machine"], ())
check("without the override the replay runs clean, which is what makes the knob the cause",
      vm2.loads("fk:*cap*") == 1)
vm3 = pr.build_vm(fk, [], [], 0, False, None, (), res.data["machine"],
                  [("fk:*cap*", "10")])
check("with it the knob holds the drafter's value, on top of the shipped one",
      vm3.loads("fk:*cap*") == 10 and vm3.sysvars["DIMZIN"] == 8)

if failures:
    print("test_lazdiag_machine: %d FAILURE(S): %s"
          % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("test_lazdiag_machine: all checks passed")
