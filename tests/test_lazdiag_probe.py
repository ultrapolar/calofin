#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/probe_report.py: a report replayed, and its inputs varied.

A failure report is a description.  The probe turns it back into a
RUN: the tool at the report's version, the geometry the report copied,
the answers the report wrote down, in the VM the test suite runs the
tools in -- and then the same run with one answer changed at a time.
What has to hold:

  * the control run, on the answers exactly as recorded, fails the way
    the report says it did -- and when it cannot, the probe says so
    instead of varying a failure that is not the one reported;
  * a failure tied to one value is named as that value's;
  * a failure that is the same whatever the inputs are is named as the
    code's, not the inputs';
  * a range the tool never checks is found as a boundary;
  * a tool that selects is handed the report's geometry back at the
    step it selected, and nothing the failed run drew beside it.

The reports here are made the way real ones are: the fixture tools are
wired by check_lazdiag, run beside LAZDIAG, and fail; what they write
into the VM's Downloads is what the probe reads.

Run: python3 tests/test_lazdiag_probe.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_lazdiag_probe.py
"""

import os
import re
import sys
import tempfile

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

from lispvm import VM, LispError  # noqa: E402
import check_lazdiag as cz  # noqa: E402
import probe_report as pr  # noqa: E402

LAZDIAG = os.path.join(REPO_DIR, "lisp", "lazdiag", "LAZDIAG.lsp")
PROFILE = r"C:\Users\dm"
TMP = tempfile.mkdtemp(prefix="calofin-probe-")

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def fixture(name, src):
    """A tool file on disk, wired the way check_lazdiag --fix wires a
    real one, so its report is made by the same calls."""
    missing, wired = cz.wire(name + ".lsp", src, True)
    path = os.path.join(TMP, name + ".lsp")
    with open(path, "w") as f:
        f.write(wired)
    return path


def report_of(tool_path, cmd, script, ents=()):
    """Run CMD beside LAZDIAG with SCRIPT and hand back the path of the
    report it wrote, copied out of the VM's Downloads onto disk."""
    vm = VM()
    vm.load(LAZDIAG)
    vm.load(tool_path)
    vm.loads(pr.STUBS)
    vm.env["USERPROFILE"] = PROFILE
    vm.handle_errors = True
    made = []
    for form in ents:
        vm.loads(form)
        made.append(vm.entities[-1])
    script = [made if s == "SELECTION" else s for s in script]
    vm.run("c:" + cmd, script)
    dxfs = {k: v for k, v in vm.files.items() if k.endswith(".dxf")}
    assert len(dxfs) == 1, sorted(vm.files)
    name, body = list(dxfs.items())[0]
    path = os.path.join(TMP, name.replace("\\", "/").rsplit("/", 1)[-1])
    with open(path, "w") as f:
        f.write(body)
    return path


def boom(_vm):
    raise LispError("bad argument type: numberp: nil", _vm)


# ---------------------------------------------------------- fixtures

DEMOR = fixture("DEMOR", r"""(setq *demor-version* "v1.0")
(defun c:DEMOR ( / *error* base r n k)
  (defun *error* (msg)
    (princ (strcat "\nDEMOR error: " msg))
    (princ))
  (setq base (getpoint "\nCentre: "))
  (setq r (getdist "\nRadius: "))
  (setq n (getint "\nHow many: "))
  (setq k (/ 100.0 r))
  (entmakex (list '(0 . "CIRCLE") '(8 . "0") (cons 10 base) (cons 40 r)))
  (princ))
""")

DEMOB = fixture("DEMOB", r"""(setq *demob-version* "v1.0")
(defun c:DEMOB ( / *error* base r)
  (defun *error* (msg)
    (princ (strcat "\nDEMOB error: " msg))
    (princ))
  (setq base (getpoint "\nCentre: "))
  (setq r (getdist "\nRadius: "))
  (if (< r 5.0) (car 1))
  (entmakex (list '(0 . "CIRCLE") '(8 . "0") (cons 10 base) (cons 40 r)))
  (princ))
""")

DEMOC = fixture("DEMOC", r"""(setq *democ-version* "v1.0")
(defun c:DEMOC ( / *error* base r)
  (defun *error* (msg)
    (princ (strcat "\nDEMOC error: " msg))
    (princ))
  (setq base (getpoint "\nCentre: "))
  (setq r (getdist "\nRadius: "))
  (car 1)
  (princ))
""")

DEMOS = fixture("DEMOS", r"""(setq *demos-version* "v1.0")
(defun c:DEMOS ( / *error* ss lim i e d)
  (defun *error* (msg)
    (princ (strcat "\nDEMOS error: " msg))
    (princ))
  (setq ss (ssget '((0 . "LINE"))))
  (setq lim (getdist "\nLongest allowed: "))
  (setq i 0)
  (while (< i (sslength ss))
    (setq e (entget (ssname ss i))
          d (distance (cdr (assoc 10 e)) (cdr (assoc 11 e))))
    (if (> d lim) (car 1))
    (setq i (1+ i)))
  (princ))
""")

LINES = ["""(entmakex (list '(0 . "LINE") '(8 . "0") '(10 0.0 0.0 0.0)
             '(11 %s 0.0 0.0)))""" % L for L in ("30.0", "80.0", "10.0")]

# ------------------------------------------------------- the reports

print("a report replayed reproduces its failure")

rep = report_of(DEMOR, "DEMOR", [(5.0, 5.0, 0.0), 0.0, 3])
layers, ents = pr.read_dxf(rep)
parsed = pr.parse_report(pr.report_lines(ents))
check("the report's tool and version are read", parsed["tool"] == "DEMOR"
      and parsed["version"] == "v1.0", (parsed["tool"], parsed["version"]))
check("the transcript comes back typed: a point, a real, an int",
      [a.value for a in parsed["answers"]] == [(5.0, 5.0, 0.0), 0.0, 3],
      [a.value for a in parsed["answers"]])
check("...and a real stays a real, whatever rtos did to its zeros",
      isinstance(parsed["answers"][1].value, float))
res = pr.probe(rep, tool_path=DEMOR)
check("the control run fails the way the report says",
      res.data["reproduced"] and res.data["control"]["kind"] == "FAIL"
      and "divide" in res.data["control"]["message"].lower(),
      res.data["control"])
check("...and the text says REPRODUCED", "REPRODUCED:" in res.text)
verdicts = {v["answer"]: v["verdict"] for v in res.data["verdicts"]}
check("the radius is named as THE value: every other one runs clean",
      verdicts.get(2, "").startswith("THIS value"), verdicts.get(2))
check("the centre is cleared: the same failure wherever it is",
      verdicts.get(1, "").startswith("NOT this value"), verdicts.get(1))
check("the count is cleared too", verdicts.get(3, "").startswith("NOT this"),
      verdicts.get(3))
check("no probe changes two answers at once",
      all(p["answer"] in (1, 2, 3) for p in res.data["probes"])
      and len(res.data["probes"]) >= 10, len(res.data["probes"]))

print("\na range the tool never checks is found as a boundary")

rep = report_of(DEMOB, "DEMOB", [(0.0, 0.0, 0.0), 2.0])
res = pr.probe(rep, tool_path=DEMOB)
v = {v["answer"]: v["verdict"] for v in res.data["verdicts"]}.get(2, "")
check("the control reproduces", res.data["reproduced"], res.data["control"])
check("the radius verdict names a lower bound",
      "lower bound" in v and "fails up to 4" in v and "passes from" in v, v)

print("\na failure that is the same whatever the inputs says so")

rep = report_of(DEMOC, "DEMOC", [(1.0, 1.0, 0.0), 7.5])
res = pr.probe(rep, tool_path=DEMOC)
check("every answer is cleared",
      res.data["reproduced"]
      and all(v["verdict"].startswith("NOT this value")
              for v in res.data["verdicts"])
      and len(res.data["verdicts"]) == 2, res.data["verdicts"])

print("\na tool that selects is handed the report's geometry back")

rep = report_of(DEMOS, "DEMOS", ["SELECTION", 50.0], LINES)
layers, ents = pr.read_dxf(rep)
parsed = pr.parse_report(pr.report_lines(ents))
check("the report says which entities were the run's input",
      parsed["selected_known"] and parsed["nsel"] == 3 and parsed["nselp"] == 3,
      (parsed["nsel"], parsed["nselp"]))
check("...and the transcript marks where the selection was taken",
      [a.selection for a in parsed["answers"]] == [True, False],
      parsed["answers"])
res = pr.probe(rep, tool_path=DEMOS)
check("the control reproduces, with the lines handed back at the ssget",
      res.data["reproduced"], res.data["control"])
v = {v["answer"]: v["verdict"] for v in res.data["verdicts"]}.get(1, "")
check("the limit's verdict finds the 80-unit line: passes from 100",
      "passes from 100" in v and "fails up to" in v, v)

print("\nwhen the failure cannot be reproduced, the probe says so")

rep = report_of(DEMOR, "DEMOR", [(5.0, 5.0, 0.0), 3.0, boom])
res = pr.probe(rep, tool_path=DEMOR)
check("an injected failure does not come back, and that is reported",
      not res.data["reproduced"] and "DID NOT REPRODUCE" in res.text,
      res.data["control"])
check("...and nothing is probed on its account", res.data["probes"] == [])
check("...but --anyway still runs them",
      len(pr.probe(rep, tool_path=DEMOR, anyway=True).data["probes"]) > 0)

print("\nthe command line, and the file it leaves beside the report")

rep = report_of(DEMOR, "DEMOR", [(5.0, 5.0, 0.0), 0.0, 3])
import io  # noqa: E402
import contextlib  # noqa: E402
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    code = pr.main([rep, "--tool", DEMOR, "--max", "8", "--json"])
out = rep[:-4] + ".probe.txt"
check("exit 0 when the control reproduced", code == 0, code)
check("the probe text is written beside the report", os.path.exists(out))
check("...and the JSON with --json", os.path.exists(rep[:-4] + ".probe.json"))
check("--max caps the runs", buf.getvalue().count("same failure")
      + buf.getvalue().count("ok") <= 8 + 4
      and "THE PROBES (one answer changed at a time, 8 runs)" in buf.getvalue(),
      buf.getvalue()[:300])

print("\nthe tool is found by the report's command name and version")

path, note = pr.find_tool("POOL", None)
check("POOL's lisp/ file answers to c:POOL", path.name.upper() == "POOL.LSP",
      path)
ver = pr.banner_of(path)
check("...whose banner is the dated REV kind, read as such",
      ver and " REV" in ver, ver)
path2, note2 = pr.find_tool("POOL", ver)
check("...and its current version has a released twin",
      "releases" in path2.parts and note2.startswith("released twin"),
      (path2, note2))
path3, note3 = pr.find_tool("POOL", "v0.1")
check("...while a version with no twin falls back to lisp/, and says so",
      path3 == path and note3.startswith("NOTE:"), note3)
try:
    pr.find_tool("NOSUCHTOOL", None)
    check("an unknown command is an error, not a guess", False)
except LookupError:
    check("an unknown command is an error, not a guess", True)

if failures:
    print("\n%d probe check(s) FAILED" % len(failures))
    sys.exit(1)
print("\nall LAZDIAG probe checks passed")
