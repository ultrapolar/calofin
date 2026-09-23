#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""LAZPANEL and LAZDIAG: the quiet failures an audit found, each pinned.

Every check here is one a drafter would never have seen fail.  Each of
these used to report success -- or report nothing -- over a wrong
result:

  CALSET Itemcolors stored 300, -3, 12abc and AutoCAD's own 255,0,0 as
  an ACI and said so; the review tools drew in it a run later.

  CALSET and LAZBACKUP each wrote CalofinTheme their own way, so the
  VB palette's registry copy and LAZICON's report could disagree with
  what the Lisp tools were drawing by.

  LAZBACKUP Export replaced whatever file was typed without asking, and
  put a bare name in AutoCAD's working folder, reported back bare.

  The toolbar icon kept the ground it was first written on for good,
  the load-time button put a toolbar the drafter had closed back on
  screen every session, and LAZNAME took native command names and
  acad.pgp shortcuts as aliases.

  LAZTUNE offered, stored and re-applied a tool's run-time state -- the
  sysvar snapshot HONEFILLET restores from -- as if it were a setting.

  LAZDIAG printed a sticky ERRNO from any earlier command as this
  failure's code, logged to a bare file name when CalofinLogDir had
  been cleared with "", placed its last-resort text at an untranslated
  UCS pick, and wrote no record of the coordinate frame at all.

The VM has no UCS (trans is the identity), no command table and no
acad.pgp, so each is modelled here with a defun that shadows the
builtin for this VM only -- a UCS whose origin sits at World
(1000,500), a getcname that knows a handful of AutoCAD commands, an
acad.pgp in the VM's own file store.

Run: python3 tests/test_fix_panel.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from lispvm import VM, LispError, NIL  # noqa: E402

PANEL = os.path.join(REPO, "lisp", "lazpanel", "LAZPANEL.lsp")
DIAG = os.path.join(REPO, "lisp", "lazdiag", "LAZDIAG.lsp")

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def attempt(label, fn):
    """Run FN; a LispError is a failure of LABEL, not a crash, so every
    scenario still reports when the file under test is an older one."""
    try:
        fn()
    except (LispError, AssertionError, KeyError, TypeError) as e:
        check(label, False, str(e).splitlines()[0][:200])


def panel():
    vm = VM()
    vm.load(PANEL)
    # the registry: every write recorded, every read empty
    vm.loads('(setq t:*reg* nil)'
             '(defun vl-registry-write (k n s)'
             '  (setq t:*reg* (cons (list n s) t:*reg*)) s)'
             '(defun vl-registry-read (k n) "")')
    vm.printed.clear()
    return vm


def diag():
    vm = VM()
    vm.env["USERPROFILE"] = r"C:\Users\dm"
    vm.load(DIAG)
    vm.printed.clear()
    return vm


def said(vm):
    return "".join(str(p) for p in vm.printed)


def g(vm, name):
    v = vm.globals.get(name)
    return None if v is NIL else v


def reg(vm):
    return [[str(x) for x in r] for r in reversed(g(vm, "t:*reg*") or [])]


def ucs(vm):
    """A UCS with its origin at World (1000,500): (trans p 1 0) adds
    the offset and (trans p 0 1) takes it away."""
    vm.loads('''(defun trans (p from to / z)
                  (setq z (if (caddr p) (caddr p) 0.0))
                  (cond ((and (= from 1) (= to 0))
                         (list (+ (car p) 1000.0) (+ (cadr p) 500.0) z))
                        ((and (= from 0) (= to 1))
                         (list (- (car p) 1000.0) (- (cadr p) 500.0) z))
                        (t p)))''')


# ------------------------------------------------------------------ [1]
print("CALSET Itemcolors takes an ACI only when it IS one")


def itemcolors():
    for typed in ("300", "-3", "256", "255,0,0", "12abc", "7.5", "0"):
        vm = panel()
        vm.run("c:CALSET", ["Itemcolors", "Orig", typed])
        check("%r is refused, not stored" % typed,
              "CalofinInk-ORIG" not in vm.env
              and "Not a colour number" in said(vm),
              "stored %r; said %r" % (vm.env.get("CalofinInk-ORIG"),
                                      said(vm)[-120:]))
    vm = panel()
    vm.run("c:CALSET", ["Itemcolors", "Orig", " 42 "])
    check("a number with a space either side is still that number",
          vm.env.get("CalofinInk-ORIG") == "42", vm.env)
    vm = panel()
    vm.run("c:CALSET", ["Itemcolors", "Orig", "255"])
    check("255, the top of the range, is taken",
          vm.env.get("CalofinInk-ORIG") == "255", vm.env)


attempt("Itemcolors", itemcolors)


# ----------------------------------------------------------------- [11]
print("CalofinTheme has one writer: profile and palette agree")


def theme():
    vm = panel()
    vm.run("c:CALSET", ["Theme", "Auto"])
    check("CALSET Auto writes the profile EMPTY, not the word AUTO",
          vm.env.get("CalofinTheme") == "", repr(vm.env.get("CalofinTheme")))
    check("...and the palette's registry copy empty too",
          ["Theme", ""] in reg(vm), reg(vm))
    vm = panel()
    vm.run("c:CALSET", ["Theme", "Dark"])
    check("CALSET Dark writes DARK to both",
          vm.env.get("CalofinTheme") == "DARK" and ["Theme", "DARK"] in reg(vm),
          (vm.env.get("CalofinTheme"), reg(vm)))

    vm = panel()
    vm.env["CalofinTheme"] = "DARK"
    vm.files["C:\\b.txt"] = "[Settings]\nCalofinTheme=\n"
    vm.run("c:LAZBACKUP", ["Import", "C:\\b.txt"])
    check("an imported Auto clears the profile",
          vm.env.get("CalofinTheme") == "", repr(vm.env.get("CalofinTheme")))
    check("...AND the palette's copy, which used to stay forced dark",
          ["Theme", ""] in reg(vm), reg(vm))
    vm = panel()
    vm.files["C:\\b.txt"] = "[Settings]\nCalofinTheme=light\n"
    vm.run("c:LAZBACKUP", ["Import", "C:\\b.txt"])
    check("an imported light reaches both as LIGHT",
          vm.env.get("CalofinTheme") == "LIGHT"
          and ["Theme", "LIGHT"] in reg(vm),
          (vm.env.get("CalofinTheme"), reg(vm)))


attempt("theme writers", theme)


# ------------------------------------------------------------------ [7]
print("LAZBACKUP Export asks before it replaces a file")

NOTES = "my notes\n"
TARGET = "C:\\jobs\\1234\\takeoff.txt"


def export():
    vm = panel()
    vm.files[TARGET] = NOTES
    vm.run("c:LAZBACKUP", ["Export", TARGET, None])
    check("Enter at Replace? leaves the file exactly as it was",
          vm.files.get(TARGET) == NOTES, repr(vm.files.get(TARGET))[:80])
    check("...and says nothing was written",
          "Nothing written" in said(vm) and "Wrote" not in said(vm),
          said(vm)[-160:])

    vm = panel()
    vm.files[TARGET] = NOTES
    vm.run("c:LAZBACKUP", ["Export", TARGET, "Yes"])
    check("Yes replaces it, and the success line names the file",
          (vm.files.get(TARGET) or "").startswith("; calofin LAZBACKUP")
          and ("of yours to %s." % TARGET) in said(vm), said(vm)[-160:])

    vm = panel()
    vm.files[TARGET] = NOTES
    vm.run("c:LAZBACKUP", ["Export", TARGET, "Back", ""])
    check("Back at Replace? goes back to the file question",
          vm.files.get(TARGET) == NOTES and "Nothing written." in said(vm),
          said(vm)[-160:])

    vm = panel()
    vm.run("c:LAZBACKUP", ["Export", "C:\\fresh.txt"])
    check("a file that is not there yet is written without a question",
          (vm.files.get("C:\\fresh.txt") or "").startswith("; calofin"),
          sorted(vm.files))


attempt("export over a file that is there", export)


def export_bare():
    # AutoCAD's own spelling: no separator on the end
    docs = "C:\\Users\\dm\\Documents"
    vm = panel()
    vm.sysvars["MYDOCUMENTSPREFIX"] = docs
    vm.run("c:LAZBACKUP", ["Export", "backup.txt"])
    full = docs + "\\backup.txt"
    check("a bare name lands in Documents, not AutoCAD's working folder",
          full in vm.files and "backup.txt" not in vm.files, sorted(vm.files))
    check("...and the line says the whole path",
          ("of yours to %s." % full) in said(vm), said(vm)[-160:])
    vm.printed.clear()
    vm.run("c:LAZBACKUP", ["Import", "backup.txt"])
    check("Import of the same bare name reads it back from there",
          ("applied from %s." % full) in said(vm), said(vm)[-160:])

    vm = panel()
    vm.run("c:LAZBACKUP", ["Export", "backup.txt"])
    check("no Documents folder: a bare name is refused, nothing written",
          "backup.txt" not in vm.files and "Nothing written" in said(vm),
          (sorted(vm.files), said(vm)[-160:]))


attempt("export of a bare name", export_bare)


# ------------------------------------------------------------------ [9]
print("the toolbar icon follows the theme")


def icons():
    vm = panel()
    vm.loads('(setq t:*w* nil)'
             '(defun lzp:support-dir () "C:\\\\Support")'
             '(defun lzp:bmp-write (p size grid / fh)'
             '  (setq fh (open p "w")) (write-line "bmp" fh) (close fh)'
             '  (setq t:*w* (cons p t:*w*)) p)')
    vm.loads('(setq t:*a* (lzp:write-bmps))')
    first = [str(x) for x in g(vm, "t:*a*") or []]
    vm.env["CalofinTheme"] = "LIGHT"
    vm.loads('(setq t:*w* nil t:*b* (lzp:write-bmps))')
    second = [str(x) for x in g(vm, "t:*b*") or []]
    wrote = [str(x) for x in g(vm, "t:*w*") or []]
    check("after a theme change the icons are written again",
          len(wrote) == 2, wrote)
    check("...under a name of their own, so the button is handed a new one",
          second and first != second
          and all("light" in n for n in second), (first, second))
    vm.loads('(setq t:*w* nil t:*c* (lzp:write-bmps))')
    check("...and a pair already on disk for this theme is not rewritten",
          not g(vm, "t:*w*"), g(vm, "t:*w*"))


attempt("icons", icons)


# ----------------------------------------------------------------- [12]
print("the load-time button does not reopen a toolbar the drafter closed")

LOADFORM = re.compile(r"\(vl-catch-all-apply\s*'\(lambda \(\) \(if "
                      r"\(lzp:first-load-p\) \(lzp:button-init[^)]*\)\)\) nil\)")


def button():
    vm = panel()
    # the file the VM loaded, so CALOFIN_LISP_ROOT=shared reads the
    # twin's load-time form and not the lisp/ one
    form = LOADFORM.search(open(vm._remap_root(PANEL)).read())
    check("the load-time call is where it was", form is not None)
    if not form:
        return
    vm.loads('(setq t:*ev* nil)'
             '(defun vl-bb-ref (s) nil) (defun vl-bb-set (s v) v)'
             '(defun lzp:toolbar-find () "TB")'
             '(defun lzp:write-bmps () (list "a.bmp" "b.bmp"))'
             '(defun vla-item (c i) "BTN")'
             '(defun vla-setbitmaps (b s l) (setq t:*ev* (cons "setbitmaps" t:*ev*)))'
             '(defun vla-put-visible (tb v) (setq t:*ev* (cons "visible" t:*ev*)))'
             '(defun vla-float (tb x y n) (setq t:*ev* (cons "float" t:*ev*)))')
    vm.loads(form.group(0))
    ev = [str(x) for x in reversed(g(vm, "t:*ev*") or [])]
    check("a found toolbar is re-iced at load", "setbitmaps" in ev, ev)
    check("...but not made visible again", "visible" not in ev, ev)
    vm.loads('(setq t:*ev* nil)')
    vm.run("c:LAZBUTTON", [])
    ev = [str(x) for x in reversed(g(vm, "t:*ev*") or [])]
    check("LAZBUTTON still brings it back", "visible" in ev, ev)


attempt("button", button)


# ----------------------------------------------------------------- [13]
print("LAZNAME refuses AutoCAD's own command names and acad.pgp shortcuts")

PGP = ("; acad.pgp\n"
       "PL,       *PLINE\n"
       "C,        *CIRCLE\n"
       "  SP,     *SPELL\n"
       "PO,       *POINT\n")


def aliases():
    vm = panel()
    vm.files["acad.pgp"] = PGP
    vm.loads('''(defun getcname (n)
                  (if (member (strcase n)
                              '("LINE" "_LINE" "AREA" "_AREA" "SCALE" "_SCALE"))
                    (strcat "_" n)))''')
    for name in ("LINE", "AREA", "SCALE"):
        vm.loads('(setq t:*why* (lzp:alias-why "%s" "SPA"))' % name)
        check("%s, a native command, is refused" % name,
              g(vm, "t:*why*") is not None, g(vm, "t:*why*"))
    for name in ("PL", "C", "SP", "PO"):
        vm.loads('(setq t:*why* (lzp:alias-why "%s" "POOL"))' % name)
        check("%s, an acad.pgp shortcut, is refused" % name,
              g(vm, "t:*why*") is not None, g(vm, "t:*why*"))
    vm.loads('(setq t:*why* (lzp:alias-why "PX" "POOL"))')
    check("a name nothing else answers to is still taken",
          g(vm, "t:*why*") is None, g(vm, "t:*why*"))
    vm.loads('(setq t:*mk* (lzp:alias-make "PL" "POOL"))')
    vm.loads('(setq t:*f* (car (atoms-family 1 (list "C:PL"))))')
    check("a stored PL is not re-applied over PLINE's shortcut",
          g(vm, "t:*mk*") is None and g(vm, "t:*f*") is None,
          (g(vm, "t:*mk*"), g(vm, "t:*f*")))
    vm.loads('(setq t:*mk* (lzp:alias-make "PX" "POOL"))')
    check("...while PX still is", g(vm, "t:*mk*") is not None)
    # the editor reopened on the alias it just made: its own wrapper
    # must not read as an AutoCAD command, even on a release whose
    # getcname answers for an AutoLISP c: command too
    vm.loads('''(defun getcname (n)
                  (if (member (strcase n) '("LINE" "_LINE" "PX" "_PX"))
                    (strcat "_" n)))
                (setq lzp:*aliasat* (list (cons "POOL" "PX"))
                      t:*why* (lzp:alias-why "PX" "POOL"))''')
    check("the alias a tool already has is still allowed through",
          g(vm, "t:*why*") is None, g(vm, "t:*why*"))


attempt("aliases", aliases)


# ------------------------------------------------------ [13] follow-up
print("a stored name this build will not apply is SAID, not dropped")

STORE = "POOL=PL;SPA=PX"


def drawing():
    """A drawing opening with LAZPANEL in its Startup Suite: the
    drafter's names already in the registry, PL in acad.pgp."""
    vm = VM()
    vm.files["acad.pgp"] = PGP
    vm.loads('(defun vl-registry-read (k n) (if (= n "Alias") "%s" ""))'
             '(defun vl-registry-write (k n s) s)' % STORE)
    vm.load(PANEL)
    return vm


def defined(vm, name):
    vm.loads('(setq t:*f* (car (atoms-family 1 (list "C:%s"))))' % name)
    return g(vm, "t:*f*") is not None


def aliasoff():
    import lispvm
    lispvm.reset_blackboard()           # a new AutoCAD session
    vm = drawing()
    out = said(vm)
    check("PL is not defined over PLINE's shortcut", not defined(vm, "PL"))
    check("...while PX, which nothing else answers to, is",
          defined(vm, "PX"))
    check("the drafter is told at load, with the reason and the way out",
          "PL (your name for POOL) is not applied" in out
          and "acad.pgp" in out and "LAZNAME" in out, out[-300:])
    check("...and PX is not in that notice", "PX (your name" not in out,
          out[-300:])
    vm.loads('(setq t:*r1* (lzp:namerow "POOL") t:*r2* (lzp:namerow "SPA"))')
    check("LAZNAME's row says PL is not applied",
          "(type PL - not applied)" in str(g(vm, "t:*r1*")), g(vm, "t:*r1*"))
    check("...and PX's row is as it was",
          "(type PX)" in str(g(vm, "t:*r2*")), g(vm, "t:*r2*"))

    # the same drafter's next drawing: the same notice, not said again
    vm2 = drawing()
    check("a second drawing in the session does not repeat it",
          "not applied" not in said(vm2), said(vm2)[-200:])
    check("...though it refuses PL there too", not defined(vm2, "PL"))

    # a reload in the SAME drawing: PX's wrapper is still standing, and
    # is this file's own -- it must not read as taken and be reported
    vm.printed.clear()
    vm.load(PANEL)
    off = [str(r[0]) for r in (g(vm, "lzp:*aliasoff*") or [])]
    check("a reload does not count its own PX wrapper as refused",
          off == ["POOL"], off)

    # LAZNAME's closing line counts what ANSWERS, and names the rest
    vm.loads('(setq t:*rows* nil)'
             '(defun lzp:write-dcl () "C:\\t.dcl")'
             '(defun load_dialog (f) 1) (defun unload_dialog (d) nil)'
             '(defun vl-file-delete (f) t) (defun new_dialog (n d) t)'
             '(defun action_tile (k a) t) (defun set_tile (k v) v)'
             '(defun mode_tile (k m) m) (defun start_list (k) k)'
             '(defun add_list (s) (setq t:*rows* (cons s t:*rows*)) s)'
             '(defun end_list () nil) (defun start_dialog () 0)')
    vm.printed.clear()
    vm.run("c:LAZNAME", [])
    out = said(vm)
    rows = [str(r) for r in (g(vm, "t:*rows*") or [])]
    check("the list LAZNAME opens on marks PL",
          any(r.startswith("POOL  (type PL - not applied)") for r in rows),
          [r for r in rows if r.startswith("POOL")])
    check("LAZNAME counts one name that answers, not two",
          "1 tool answer to a name of yours" in out, out[-300:])
    check("...and says which one does not, and why",
          "PL (your name for POOL) is not applied -- PL is an AutoCAD"
          " shortcut in acad.pgp." in out, out[-300:])


attempt("a refused stored alias", aliasoff)


# ----------------------------------------------------------------- [14]
print("LAZTUNE does not offer a tool's run-time state as a setting")


def knobs():
    vm = panel()
    for sym, text in (("hn:*sysold*", '"x"'), ("cbk:*sysold*", "0"),
                      ("psd:*pvents*", "nil"), ("cbk:*last-len*", "12.0")):
        vm.loads('(setq t:*why* (lzp:knob-why "%s" "%s"))'
                 % (sym, text.replace('"', '\\"')))
        check("%s is refused" % sym, g(vm, "t:*why*") is not None,
              g(vm, "t:*why*"))
    vm.loads('(setq t:*why* (lzp:knob-why "cbk:*layer*" "\\"MYCOVER\\""))')
    check("an ordinary knob is still taken", g(vm, "t:*why*") is None,
          g(vm, "t:*why*"))
    # one already stored, from before: never applied at a panel open
    vm.env["CalofinKnobs"] = "hn:*sysold*"
    vm.env["CalofinKnob-hn.~sysold~"] = '"x"'
    vm.loads('(setq hn:*sysold* nil t:*n* (lzp:knobs-apply))')
    check("a stored snapshot override is not applied",
          g(vm, "hn:*sysold*") is None and g(vm, "t:*n*") == 0,
          (g(vm, "hn:*sysold*"), g(vm, "t:*n*")))


attempt("knobs", knobs)


# ------------------------------------------------------------------ [5]
print("a report's ERRNO is this run's")


def errno():
    vm = diag()
    vm.sysvars["ERRNO"] = 7          # a missed pick, some command ago
    vm.loads('(lzd:begin "POOL" "v1")')
    check("lzd:begin clears it for the run", vm.sysvars.get("ERRNO") == 0,
          vm.sysvars.get("ERRNO"))
    vm.sysvars["ERRNO"] = 7          # ...one of this run's own
    vm.loads('(lzd:begin "POOL" "v1")')
    check("...and a second phase of the SAME run keeps it",
          vm.sysvars.get("ERRNO") == 7, vm.sysvars.get("ERRNO"))
    vm.loads('(setq t:*l* (lzd:report-lines "POOL" "v1" "boom" 0 0 0))')
    line = [str(l) for l in g(vm, "t:*l*") if "ERRNO" in str(l)]
    check("the report says what the number covers",
          line and "since this run began" in line[0], line)
    # ...and a begin with nothing to clear writes nothing at all: it is
    # the top of every command, and a sysvar it had no need to move is
    # one more thing a run changes behind the drafter
    for held in (None, 0):
        vm = diag()
        if held is None:
            vm.sysvars.pop("ERRNO", None)
        else:
            vm.sysvars["ERRNO"] = held
        before = dict(vm.sysvars)
        vm.loads('(lzd:begin "POOL" "v1")')
        moved = {k: (before.get(k), v) for k, v in vm.sysvars.items()
                 if before.get(k) != v}
        check("ERRNO %r: lzd:begin leaves every sysvar alone" % held,
              not moved, moved)


attempt("errno", errno)


# ------------------------------------------------------------------ [8]
print("an emptied CalofinLogDir is unset, not a folder")


def logdir():
    for cleared in ("", "   "):
        vm = diag()
        vm.env["CalofinLogDir"] = cleared
        vm.loads('(setq t:*d* (lzd:logfolder) t:*p* (lzd:logpath))')
        check("CalofinLogDir %r falls through to the profile" % cleared,
              g(vm, "t:*d*") == r"C:\Users\dm\calofin", g(vm, "t:*d*"))
        check("...so the log path has a folder in front of it",
              str(g(vm, "t:*p*")).startswith("C:\\Users\\dm\\calofin\\"),
              g(vm, "t:*p*"))
    vm = diag()
    vm.env["USERPROFILE"] = ""
    vm.env["LOCALAPPDATA"] = r"C:\Local"
    vm.loads('(setq t:*d* (lzd:logfolder))')
    check("an empty USERPROFILE falls through too",
          g(vm, "t:*d*") == r"C:\Local\calofin", g(vm, "t:*d*"))


attempt("logdir", logdir)


# ----------------------------------------------------------------- [17]
print("the last-resort report lands where it was clicked, under a UCS")


def paste():
    vm = diag()
    ucs(vm)
    vm.script = [[-800.0, 0.0, 0.0]]
    vm.prompts = []
    before = len(vm.entities)
    vm.loads('(lzd:paste (list "line one" "line two"))')
    placed = vm.entities[before:]
    firsts = [p for p in vm.entdata[placed[0]]
              if isinstance(p, list) and p and p[0] == 10] if placed else []
    at = firsts[0][1:3] if firsts else None
    check("the first line is at the click's WORLD point",
          at == [200.0, 500.0], at)


attempt("paste", paste)


# ----------------------------------------------------------------- [16]
print("a report records the frame its clicks were answered in")


def frame():
    vm = diag()
    vm.loads('(setq t:*l* (lzd:report-lines "POOL" "v1" "boom" 0 0 0))')
    body = "\n".join(str(l) for l in g(vm, "t:*l*"))
    for var in ("WORLDUCS", "UCSORG", "UCSXDIR", "CTAB", "TILEMODE",
                "CVPORT", "AUNITS", "ANGBASE", "ANGDIR"):
        check("THE DRAWING carries %s" % var, ("  %s " % var) in body)
    vm = diag()
    ucs(vm)
    vm.loads('(lzd:begin "POOL" "v1")'
             "(setq t:*r* (lzd:pt \"the corner\" '(10.0 20.0 0.0)))")
    pts = g(vm, "lzd:*pts*") or []
    # (label . point) is (label x y z) once the point is a list
    got = list(pts[0])[1:] if pts else None
    check("a recorded click is kept in World, beside World geometry",
          got == [1010.0, 520.0, 0.0], got)
    check("...and the caller still gets its own point back",
          list(g(vm, "t:*r*") or []) == [10.0, 20.0, 0.0], g(vm, "t:*r*"))


attempt("frame", frame)


print()
if failures:
    print("%d check(s) FAILED" % len(failures))
    for f in failures:
        print("  FAIL " + f)
    sys.exit(1)
print("ALL FIX-PANEL CHECKS PASSED")
