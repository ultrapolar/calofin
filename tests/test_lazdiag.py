#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""LAZDIAG: a failed command writes its failure out as a DXF.

Three things have to be true of that file, and this suite is organised
round them:

  IT LOADS.  A report nobody can open is worse than no report, because
  the drafter has already been told to send it.  So the DXF is parsed
  back here -- group code and value, section by section -- and checked
  the way AutoCAD would: AC1009, balanced SECTIONs, an EOF, and every
  layer an entity names present in the LAYER table.

  IT HOLDS THE FAILURE.  The geometry the run drew and the geometry it
  was handed, the prompts and the answers, the error, the sysvars.  The
  flattening to R12 primitives is where this can quietly go wrong -- a
  bulge written into group 30 instead of 42 turns an arc into a straight
  line and nothing complains -- so the shapes are read back coordinate
  by coordinate.

  IT NEVER MAKES THINGS WORSE.  Everything here runs from inside an
  *error* handler.  A reporter that throws, prompts, recurses, or leaves
  an undo group open turns a one-line failure into a broken session, so
  each of those is driven deliberately: the reporter sabotaged, every
  candidate folder made read-only, a cancel that must write nothing at
  all.

Run: python3 tests/test_lazdiag.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_lazdiag.py
"""

import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

from lispvm import VM, LispError  # noqa: E402

LSP = os.path.join(REPO_DIR, "lisp", "lazdiag", "LAZDIAG.lsp")
#: POOL, for the one check that drives a REAL prompt through a REAL
#: tool's ask helper.  The VM remaps the path for CALOFIN_LISP_ROOT, and
#: the helper is renamed by the same mirror that does the remapping, so
#: the name has to follow the tier the way the file does.
ROOT = os.environ.get("CALOFIN_LISP_ROOT", "lisp")
POOL_LSP = os.path.join(REPO_DIR, "lisp", "pool", "POOL.LSP")
ASKTREAT = "cal:asktreat" if ROOT == "shared" else "pool:asktreat"
PROFILE = r"C:\Users\dm"
DOWNLOADS = PROFILE + r"\Downloads"

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def newvm(profile=PROFILE, layers=("POOL", "SPA")):
    vm = VM()
    if profile:
        vm.env["USERPROFILE"] = profile
    vm.tables["LAYER"].update(layers)
    vm.load(LSP)
    vm.printed.clear()
    return vm


def base(path):
    """The file name out of a WINDOWS path.  os.path.basename does not
    split on a backslash when the suite runs on POSIX, so it would hand
    back the whole path and every name check would pass on nothing."""
    return path.replace("/", "\\").rsplit("\\", 1)[-1]


def dxf(vm, ent, code):
    """One group of a VM entity.  entdata holds an AutoLISP alist, so a
    dotted pair for a scalar and a plain list for a point."""
    for pair in vm.entdata[ent]:
        if isinstance(pair, list):
            if pair[0] == code:
                return pair[1:]
        elif pair.a == code:
            return pair.b
    return None


def said(vm):
    return "".join(vm.printed)


def only_file(vm):
    assert len(vm.files) == 1, vm.files
    return list(vm.files.items())[0]


# --------------------------------------------------------------- the DXF

def pairs(body):
    """A DXF read back as (code, value) pairs.  Raises if the file is not
    an even number of lines or a code is not an integer, which is the
    failure mode a hand-written DXF actually has: one stray value line
    and every pair after it is off by one."""
    lines = body.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if len(lines) % 2:
        raise AssertionError("odd number of lines (%d) - a value with no "
                             "code, or a code with no value" % len(lines))
    out = []
    for i in range(0, len(lines), 2):
        code = lines[i].strip()
        if not (code.lstrip("-").isdigit()):
            raise AssertionError("line %d is %r, not a group code - the "
                                 "pairing has slipped" % (i + 1, lines[i]))
        out.append((int(code), lines[i + 1]))
    return out


def sections(pr):
    """{name: [(code, value), ...]} for each SECTION in the file."""
    out, name, buf, depth = {}, None, [], 0
    for code, val in pr:
        if code == 0 and val == "SECTION":
            depth, buf = 1, []
            name = None
            continue
        if code == 0 and val == "ENDSEC":
            out[name] = buf
            depth, name = 0, None
            continue
        if depth and name is None and code == 2:
            name = val
            continue
        if depth:
            buf.append((code, val))
    return out


def entities(sec):
    """The ENTITIES section split into one list per entity."""
    out, cur = [], None
    for code, val in sec:
        if code == 0:
            if cur:
                out.append(cur)
            cur = [(0, val)]
        elif cur is not None:
            cur.append((code, val))
    if cur:
        out.append(cur)
    return out


def g(ent, code):
    for c, v in ent:
        if c == code:
            return v
    return None


# ------------------------------------------------------- a failing run

def failing_run(vm, tool="POOL", ver="v2.7",
                msg="bad argument type: numberp: nil"):
    vm.loads('(lzd:report "%s" "%s" "%s")' % (tool, ver, msg))


print("a failure writes a DXF into Downloads")

vm = newvm()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.loads('''(entmakex (list '(0 . "LINE") '(8 . "POOL")
              '(10 0.0 0.0 0.0) '(11 120.0 0.0 0.0)))''')
failing_run(vm)
path, body = only_file(vm)
check("it lands in the user's Downloads folder",
      path.startswith(DOWNLOADS + "\\"), path)
check("named <tool>-<version>-error-<date>.dxf",
      base(path).startswith("POOL-v2.7-error-")
      and path.endswith(".dxf"), base(path))
check("the user is told, and told to send it",
      "FAILED" in said(vm) and "SEND THAT FILE IN" in said(vm)
      and path in said(vm), said(vm)[:200])
check("and told their own drawing was not touched",
      "has not been touched" in said(vm))
check("nothing was drawn into the drawing being worked on",
      len([e for e in vm.entities]) == 1, "%d entities" % len(vm.entities))

print("the file AutoCAD has to open")

pr = pairs(body)
sec = sections(pr)
check("it is R12 (AC1009), which every AutoCAD since reads",
      ("$ACADVER", "AC1009") == (
          [v for c, v in sec.get("HEADER", []) if c == 9 and v == "$ACADVER"]
          and "$ACADVER" or None,
          g(sec.get("HEADER", []), 1)))
check("HEADER, TABLES and ENTITIES are all there, and balanced",
      set(sec) == {"HEADER", "TABLES", "ENTITIES"}, sorted(sec))
check("the last pair is EOF", pr[-1] == (0, "EOF"), pr[-1])

ents = entities(sec["ENTITIES"])
layers = {v for c, v in sec["TABLES"] if c == 2}
used = {g(e, 8) for e in ents} - {None}
check("every layer an entity names is in the LAYER table",
      used <= layers, "missing %s" % sorted(used - layers))
check("CONTINUOUS is defined before a layer names it",
      "CONTINUOUS" in layers)
check("the report has a layer of its own",
      "CALOFIN-ERROR" in used, sorted(used))

print("the geometry the run drew, copied shape for shape")

vm = newvm()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.loads('''(entmakex (list '(0 . "LINE") '(8 . "POOL")
              '(10 3.0 4.0 0.0) '(11 120.0 40.0 0.0)))''')
vm.loads('''(entmakex (list '(0 . "CIRCLE") '(8 . "SPA")
              '(10 60.0 20.0 0.0) '(40 . 12.5)))''')
vm.loads('''(entmakex (list '(0 . "LWPOLYLINE") '(8 . "POOL") '(90 . 3)
              '(70 . 1) '(10 0.0 0.0) '(42 . 0.5)
              '(10 60.0 40.0) '(10 120.0 0.0)))''')
vm.loads('''(entmakex (list '(0 . "MTEXT") '(8 . "POOL") '(10 5.0 6.0 0.0)
              '(40 . 2.0) '(1 . "{\\\\fArial|b1;25 ft}\\\\Pdeep")))''')
failing_run(vm)
ents = entities(sections(pairs(only_file(vm)[1]))["ENTITIES"])
byty = {}
for e in ents:
    byty.setdefault(g(e, 0), []).append(e)

line = [e for e in byty.get("LINE", []) if g(e, 8) == "POOL"]
check("the LINE keeps both its ends",
      line and (g(line[0], 10), g(line[0], 11)) == ("3.00000000",
                                                    "120.00000000")
      and (g(line[0], 20), g(line[0], 21)) == ("4.00000000", "40.00000000"),
      line[:1])
circ = byty.get("CIRCLE", [])
check("the CIRCLE keeps its centre and radius",
      circ and g(circ[0], 40) == "12.50000000"
      and g(circ[0], 10) == "60.00000000", circ[:1])

poly = byty.get("POLYLINE", [])
verts = byty.get("VERTEX", [])
check("the LWPOLYLINE became an R12 POLYLINE, closed",
      poly and g(poly[0], 70) == "1" and g(poly[0], 66) == "1", poly[:1])
check("with one VERTEX each and a SEQEND",
      len(verts) == 3 and byty.get("SEQEND"), "%d vertices" % len(verts))
# the bug this line exists for: a vertex is (x y bulge), and handing the
# whole triple to the point writer put the bulge in group 30
check("the bulge is in group 42, not in the vertex Z",
      verts and g(verts[0], 42) == "0.50000000"
      and g(verts[0], 30) == "0.00000000",
      "42=%r 30=%r" % (g(verts[0], 42) if verts else None,
                       g(verts[0], 30) if verts else None))

mt = [e for e in byty.get("TEXT", []) if g(e, 8) == "POOL"]
check("the MTEXT became TEXT with its formatting codes stripped",
      mt and g(mt[0], 1) == "25 ft deep", mt and g(mt[0], 1))

print("an entity with no R12 spelling is labelled, never dropped")

vm = newvm()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.loads('''(entmakex (list '(0 . "ELLIPSE") '(8 . "POOL")
              '(10 10.0 20.0 0.0) '(11 8.0 0.0 0.0) '(40 . 0.5)))''')
failing_run(vm)
ents = entities(sections(pairs(only_file(vm)[1]))["ENTITIES"])
labels = [g(e, 1) for e in ents if g(e, 0) == "TEXT"]
check("the report says what was there and that it was not copied",
      any("ELLIPSE" in (l or "") and "not copied" in (l or "")
          for l in labels),
      "an unconvertible entity vanished from the report without a word")

vm = newvm()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.loads('''(entmakex (list '(0 . "LINE") '(8 . "POOL")
              '(10 0.0 0.0 0.0) '(11 9.0 0.0 0.0)))''')
vm.loads('''(entmakex (list '(0 . "ELLIPSE") '(8 . "POOL")
              '(10 10.0 20.0 0.0) '(11 8.0 0.0 0.0) '(40 . 0.5)))''')
vm.loads("(defun lzd:flatten (e) (car 1))")     # every entity unreadable
vm.printed.clear()
failing_run(vm)
check("an entity this cannot read costs its own shape and no more",
      len(vm.files) == 1, "the whole report was lost to one entity")
if vm.files:
    body = only_file(vm)[1]
    check("...the report still carries the transcript and the error",
          "bad argument type" in body and "THE DRAWING" in body)
    check("...and says which entities it could not read",
          "not readable" in body, "no note of what was skipped")

print("what the run was handed, and where it was clicked")

vm = newvm()
vm.loads('''(setq before (entmakex (list '(0 . "CIRCLE") '(8 . "SPA")
              '(10 1.0 1.0 0.0) '(40 . 9.0))))''')
vm.loads('(lzd:begin "SPA" "v1.4")')
vm.loads('''(entmakex (list '(0 . "LINE") '(8 . "SPA")
              '(10 0.0 0.0 0.0) '(11 1.0 1.0 0.0)))''')
failing_run(vm, "SPA", "v1.4")
ents = entities(sections(pairs(only_file(vm)[1]))["ENTITIES"])
check("geometry that was there BEFORE the run is left out",
      not [e for e in ents if g(e, 0) == "CIRCLE"],
      "a circle drawn before lzd:begin was copied anyway")

vm = newvm()
vm.loads('''(setq before (entmakex (list '(0 . "CIRCLE") '(8 . "SPA")
              '(10 1.0 1.0 0.0) '(40 . 9.0))))''')
vm.loads('(lzd:begin "SPA" "v1.4")')
vm.loads("(lzd:watch before)")
vm.loads('(lzd:pt "north-east corner" (list 120.0 40.0))')
failing_run(vm, "SPA", "v1.4")
ents = entities(sections(pairs(only_file(vm)[1]))["ENTITIES"])
check("...unless the tool registered it as its input",
      [e for e in ents if g(e, 0) == "CIRCLE"],
      "lzd:watch geometry did not reach the report")
picks = [e for e in ents if g(e, 8) == "CALOFIN-PICKS"]
check("every point picked is a POINT on its own layer",
      [e for e in picks if g(e, 0) == "POINT"], picks[:1])
check("...labelled with the prompt it answered",
      any("north-east corner" in (g(e, 1) or "") for e in picks),
      [g(e, 1) for e in picks])

print("the transcript: which question it died on")

vm = newvm()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.loads('(lzd:ask "Pool length" "25\'-0\\"")')
vm.loads('(lzd:ask "How should the deep end be treated?" "Radius")')
failing_run(vm)
body = only_file(vm)[1]
check("both prompts and both answers are in the report",
      "Pool length" in body and "25'-0" in body
      and "deep end" in body and "Radius" in body)
check("the last prompt is named as the last step reached",
      "deep end" in [l for l in body.split("\n")
                     if "last step" in l][0], "no last-step line")
check("and the report says what it CANNOT tell you",
      "no line number" in body,
      "the report should be explicit that AutoLISP gives no line number")

print("the ask helpers fill the transcript on their own")

vm = newvm()
vm.load(POOL_LSP)
vm.printed.clear()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.script = ["Radius"]
vm.loads('(setq treat (%s "the deep end" nil nil))' % ASKTREAT)
treat = vm.loads("treat")
check("the helper still answers exactly what it always did",
      treat == "Radius", repr(treat))
failing_run(vm)
body = only_file(vm)[1]
check("a question asked through a tool's own ask helper is recorded",
      "deep end" in body and "Radius" in body,
      "the helper did not record itself")

print("a very long run keeps the end of its transcript, not the start")

vm = newvm()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.loads('(setq i 0)')
vm.loads('(while (< i 260) (lzd:ask (strcat "question " (itoa i))'
         ' (itoa i)) (setq i (1+ i)))')
failing_run(vm)
body = only_file(vm)[1]
check("the prompts just before the failure are the ones kept",
      "question 259" in body and "question 200" in body,
      "the cap threw away the newest lines instead of the oldest")
check("...and the ancient ones are the ones dropped",
      "question 0 " not in body and "question 5 " not in body,
      "the transcript is not capped at all")

print("a cancel is not a failure")

vm = newvm()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.loads('(lzd:report "POOL" "v2.7" "Function cancelled")')
check("Esc writes no file", not vm.files, list(vm.files))
check("...and says nothing", not said(vm).strip(), said(vm))

print("a transcript is never handed to the wrong tool")

vm = newvm()
vm.loads('(lzd:begin "POOL" "v2.7")')
vm.loads('(lzd:ask "Pool length" "25 ft")')
failing_run(vm, "ABCDEF", "v1.1")
path, body = only_file(vm)
check("a stale context is dropped, not re-labelled",
      "ABCDEF" in base(path) and "Pool length" not in body,
      "POOL's prompts were reported as ABCDEF's")

print("a tool with a handler in two places keeps one transcript")

vm = newvm()
vm.loads('(lzd:begin "COVERCHECK" "v1.0")')
vm.loads('(lzd:ask "Which sheet?" "A-1")')
vm.loads('''(entmakex (list '(0 . "LINE") '(8 . "POOL")
              '(10 0.0 0.0 0.0) '(11 9.0 0.0 0.0)))''')
vm.loads('(lzd:begin "COVERCHECK" "v1.0")')     # the helper's own begin
vm.loads('(lzd:ask "Start where?" "the deep end")')
failing_run(vm, "COVERCHECK", "v1.0")
body = only_file(vm)[1]
check("the first phase's prompts survive the second phase's begin",
      "Which sheet?" in body and "Start where?" in body,
      "the second lzd:begin threw the first phase away")
ents = entities(sections(pairs(body))["ENTITIES"])
check("...and so does the geometry the first phase drew",
      [e for e in ents if g(e, 0) == "LINE" and g(e, 8) == "POOL"],
      "the mark moved past phase one")

print("when no folder will take the file")

vm = newvm(profile=None)
vm.sysvars["DWGPREFIX"] = r"C:\jobs"
vm.readonly_dirs.update({r"C:\jobs", r"C:\Temp"})
failing_run(vm, "SPA", "v1.4")
check("nothing is written", not vm.files, list(vm.files))
check("the user is still told the command failed",
      "SPA v1.4 has FAILED" in said(vm), said(vm)[:160])
check("...which folders were tried",
      r"C:\jobs" in said(vm) and r"C:\Temp" in said(vm))
check("...and to type LAZDIAG next", "LAZDIAG" in said(vm))
check("the drawing is NOT written into behind their back",
      not vm.entities, "%d entities" % len(vm.entities))

# its own VM: the block below deliberately carries on with the one that
# has SPA's failure stored in it, and re-binding vm here would hand that
# block a session with nothing to report
vmc = newvm(profile=None)
vmc.sysvars["DWGPREFIX"] = ""          # a drawing that was never saved
vmc.sysvars["TEMPPREFIX"] = r"C:\Temp"
cands = vmc.loads("(lzd:candidates)")
check("an unsaved drawing's empty DWGPREFIX is not a folder",
      "" not in cands, cands)
vmc.env["USERPROFILE"] = PROFILE
vmc.env["HOMEDRIVE"] = "C:"
vmc.env["HOMEPATH"] = r"\Users\dm"
cands = vmc.loads("(lzd:candidates)")
check("...and the two spellings of the profile are one folder, tried once",
      len(cands) == len(set(cands)), cands)

print("LAZDIAG writes it once a folder works")

vm.readonly_dirs.clear()
vm.printed.clear()
vm.run("c:LAZDIAG", [])
check("the report is written on the second try", len(vm.files) == 1,
      list(vm.files))
check("...under the name the failure earned it",
      "SPA-v1.4-error-" in base(only_file(vm)[0]),
      only_file(vm)[0])
check("...and it is a DXF that parses",
      sections(pairs(only_file(vm)[1])).get("ENTITIES") is not None)

print("the LAST RESORT: into the drawing, and only when asked")

vm = newvm(profile=None)
vm.sysvars["DWGPREFIX"] = r"C:\jobs"
vm.readonly_dirs.update({r"C:\jobs", r"C:\Temp"})
vm.loads('(lzd:begin "SPA" "v1.4")')
vm.loads('(lzd:ask "Which corner?" "the north-east one")')
failing_run(vm, "SPA", "v1.4")
before = len(vm.entities)
vm.printed.clear()
vm.run("c:LAZDIAG", [(4000.0, 4000.0, 0.0)])
check("it says plainly that this is the last resort",
      "LAST RESORT" in said(vm), said(vm)[:160])
check("...and asks for a spot well clear of the work",
      "clear of your work" in said(vm))
placed = [e for e in vm.entities[before:]]
check("the report is placed as TEXT where it was clicked",
      placed and all(dxf(vm, e, 0) == "TEXT" for e in placed),
      "%d new entities" % len(placed))
check("...on the report's own layer, not the user's",
      placed and {dxf(vm, e, 8) for e in placed} == {"CALOFIN-ERROR"},
      placed and {dxf(vm, e, 8) for e in placed})
text = " ".join(dxf(vm, e, 1) or "" for e in placed)
check("...and it is the whole report, transcript included",
      "CALOFIN ERROR REPORT" in text and "Which corner?" in text
      and "north-east one" in text)
check("...with a word about erasing it afterwards",
      "erase them" in said(vm), said(vm)[-200:])

vm2 = newvm(profile=None)
vm2.sysvars["DWGPREFIX"] = r"C:\jobs"
vm2.readonly_dirs.update({r"C:\jobs", r"C:\Temp"})
failing_run(vm2, "SPA", "v1.4")
vm2.printed.clear()
vm2.run("c:LAZDIAG", [None])          # Esc at the placement prompt
check("Esc at the placement prompt writes nothing into the drawing",
      not vm2.entities and "Nothing placed" in said(vm2),
      "%d entities" % len(vm2.entities))

print("LAZDIAG with nothing to report proves the path works")

vm = newvm()
vm.run("c:LAZDIAG", [])
path = only_file(vm)[0]
check("a self test lands where a real report would",
      path.startswith(DOWNLOADS + "\\"), path)
check("...and is not named like a failure",
      "selftest" in base(path)
      and "-error-" not in base(path), base(path))
check("...and says reports will reach you",
      "will reach you" in said(vm), said(vm)[-160:])

print("the reporter never makes the failure worse")

vm = newvm()
vm.loads("(defun lzd:build-prims (a b c) (car 1))")     # sabotage
vm.printed.clear()
vm.loads('(lzd:report "POOL" "v2.7" "the original error")')
check("a reporter that throws does not throw at its caller",
      True, "it returned")
check("...the user is told the command failed anyway",
      "POOL v2.7 has FAILED: the original error" in said(vm), said(vm)[:200])
check("...and why no file appeared",
      "could NOT be written" in said(vm))

vm = newvm()
vm.loads("(defun lzd:write (n p) (car 1))")
vm.printed.clear()
vm.loads('(lzd:report "POOL" "v2.7" "the original error")')
check("a write that throws is caught the same way",
      "could NOT be written" in said(vm), said(vm)[:200])

vm = newvm()
vm.loads("""(defun lzd:build-prims (a b c)
              (lzd:report "POOL" "v2.7" "a second error"))""")
vm.printed.clear()
vm.loads('(lzd:report "POOL" "v2.7" "the first error")')
check("an error raised INSIDE the reporter does not recurse",
      "reporter failed while reporting" in said(vm), said(vm)[:240])

print("the session is handed back the way it was found")

vm = newvm()
before = dict(vm.sysvars)
vm.loads('(lzd:begin "POOL" "v2.7")')
failing_run(vm)
changed = {k: (before.get(k), v) for k, v in vm.sysvars.items()
           if before.get(k) != v}
check("no system variable is touched by a report", not changed, changed)
check("no undo group is opened", vm.undo_groups == 0, vm.undo_groups)
check("no error mode is pushed", vm.error_mode_depth == 0,
      vm.error_mode_depth)
check("no (command ...) is driven from inside the handler",
      not vm.commands, vm.commands[:3])

print("a real command, failing for real")

vm = newvm()
vm.loads("(defun lzd:selftest ( / prims path d) (car 1))")
vm.handle_errors = True
vm.printed.clear()
vm.run("c:LAZDIAG", [])
check("c:LAZDIAG's own wired handler writes a report",
      any("LAZDIAG-" in p and "-error-" in p for p in vm.files),
      list(vm.files))

if failures:
    print("\n%d LAZDIAG check(s) FAILED" % len(failures))
    sys.exit(1)
print("\nall LAZDIAG checks passed")
