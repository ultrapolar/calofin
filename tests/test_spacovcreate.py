#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for SPACOVCREATE.lsp -- the cover for a spa that is already drawn.

Four kinds of check, all runnable without AutoCAD:

* Structural checks read the real .lsp and assert what makes it safe to
  run: pure ASCII, every system variable it changes also saved and
  restored, every knob inside the tunables block, the four LAZDIAG call
  sites, and a version banner that agrees with the releases/ twin.
* Parity checks hold the shop data it COPIED from SPA to SPA's own: the
  foam sheet table, the hardware table and the Hinge Arrangement Chart
  are read out of both files by the VM and compared, so the copy cannot
  drift into a second set of numbers nobody reconciles.
* Geometry checks drive the offset itself, where every answer is one
  that can be worked out by hand: a square offsets to a square, a
  rectangle with a tangent radius corner offsets to the same rectangle
  with the corner at r + d ON THE SAME CENTRE (the bulge unchanged, which
  is the whole design), a circle offsets to a circle, and a clockwise
  outline comes back counter-clockwise unchanged in shape.
* Runtime checks drive the actual command through tests/lispvm.py: the
  three answers, Back between them, the assumed 4-2 written into the
  report in red, hinges laid out and labelled per the chart, a cover
  taller than it is wide hinged the other way, loose walls chained out
  of order, two loops with the bigger one winning, and the things that
  are flagged rather than fixed.

Usage:  python3 tests/test_spacovcreate.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_spacovcreate.py
"""

import math
import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

import lispvm                                              # noqa: E402
from lispvm import VM, Dot, LispError                      # noqa: E402

ROOT = os.environ.get("CALOFIN_LISP_ROOT", "lisp")
if ROOT == "shared":
    LSP = os.path.join(REPO_DIR, "shared", "parts", "SPACOVCREATE.lsp")
    LIB = os.path.join(REPO_DIR, "shared", "parts", "CALOFIN-LIB.lsp")
    SPA_LSP = os.path.join(REPO_DIR, "shared", "parts", "SPA.lsp")
else:
    LSP = os.path.join(REPO_DIR, "lisp", "spacovcreate", "SPACOVCREATE.lsp")
    LIB = None
    SPA_LSP = os.path.join(REPO_DIR, "lisp", "spa", "SPA.LSP")
RELEASES_DIR = os.path.join(REPO_DIR, "releases")

SRC = open(LSP, encoding="ascii").read()    # also asserts pure ASCII

failures = []


def check(label, cond, detail=""):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        failures.append(label)


def near(label, got, want, tol=1e-6):
    ok = (isinstance(got, (int, float))
          and isinstance(want, (int, float))
          and abs(got - want) <= tol)
    check(label, ok, f"(got {got!r}, want {want!r})")


def pt_near(label, got, want, tol=1e-6):
    ok = (isinstance(got, list) and len(got) >= 2
          and abs(got[0] - want[0]) <= tol and abs(got[1] - want[1]) <= tol)
    check(label, ok, f"(got {got!r}, want {want!r})")


# ================================================================ source ====

def strip(src):
    """Blank out ;-comments and string bodies, keeping line structure."""
    out, i, in_str = [], 0, False
    while i < len(src):
        ch = src[i]
        if ch == "\n":
            out.append(ch)
            i += 1
            continue
        if in_str:
            if ch == "\\":
                out.append("  ")
                i += 2
                continue
            if ch == '"':
                in_str = False
            out.append(" ")
            i += 1
            continue
        if ch == '"':
            in_str = True
            out.append(" ")
            i += 1
            continue
        if ch == ";":
            while i < len(src) and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


CODE = strip(SRC)

print("the file itself")

check("parens balance", CODE.count("(") == CODE.count(")"),
      f"({CODE.count('(')} open, {CODE.count(')')} close)")
check("no tabs", "\t" not in SRC)

# Every sysvar it writes is one it saved.  In the grouped tier the
# sysvar pair and the vector set are the library's, under cal:, so the
# names to look for move with the tier -- which is the point of checking
# the twin at all rather than the original twice.
PFX = "cal" if ROOT == "shared" else "scv"
written = set(re.findall(r'\(setvar\s+"([A-Z]+)"', SRC))
m = re.search(PFX + r":syssave\s+'\(([^)]*)\)", SRC)
saved = set(re.findall(r'"([A-Z]+)"', m.group(1))) if m else set()
check("every sysvar changed is saved", written <= saved,
      f"(changed {sorted(written)}, saved {sorted(saved)})")
check("nothing saved that is never changed", saved <= written,
      f"(saved {sorted(saved)}, changed {sorted(written)})")
check("the command hands them back", f"({PFX}:sysrestore)" in SRC)
if ROOT != "shared":
    check("and sysrestore is what puts them back",
          "(foreach p scv:*sysold* (setvar (car p) (cdr p)))" in SRC)

# the four LAZDIAG call sites
for site in ("(if lzd:begin (lzd:begin \"SPACOVCREATE\"",
             "(if lzd:report (lzd:report \"SPACOVCREATE\"",
             "(if lzd:watch (lzd:watch",
             "(if lzd:ask (lzd:ask"):
    check(f"LAZDIAG site present: {site.split()[1]}", site in SRC)
check("a failure says how to roll the half-drawn cover back",
      "use U to roll the run back" in SRC)
check("lzd:report comes after the sysvar restore",
      SRC.index(f"({PFX}:sysrestore)") < SRC.index("(if lzd:report"))

# knobs live in the tunables block, state lives under its own rule
body = SRC.split("TUNABLES -- every value")[1]
knobs_block = body.split("END OF TUNABLES")[0]
state_block = SRC.split("run state (not tunables)")[1].split(
    ";;; --------------------")[0]
all_globals = set(re.findall(r"^\(setq (scv:\*[a-z-]+\*)", SRC, re.M))
in_knobs = set(re.findall(r"^\(setq (scv:\*[a-z-]+\*)", knobs_block, re.M))
in_state = set(re.findall(r"^\(setq (scv:\*[a-z-]+\*)", state_block, re.M))
check("every global is a knob or declared run state",
      all_globals == in_knobs | in_state,
      f"(loose: {sorted(all_globals - in_knobs - in_state)})")
check("no knob is also run state", not (in_knobs & in_state),
      f"({sorted(in_knobs & in_state)})")
want_state = {"scv:*notes*", "scv:*advice*", "scv:*dashlt*"}
if ROOT != "shared":
    # the grouped twin drops the snapshot global with the sysvar pair
    want_state.add("scv:*sysold*")
check("the run state is only what the command writes",
      in_state == want_state, f"({sorted(in_state)})")

# the banner, and the releases/ twin stamped from it
ver = re.search(r'\(setq \*spacovcreate-version\* "v(\d+)\.(\d+)"\)', SRC)
check("version banner present", ver is not None)
if ver and ROOT != "shared":
    rev = f"REV{ver.group(1)}{ver.group(2)}"
    twins = [f for f in os.listdir(RELEASES_DIR)
             if f.startswith("SPACOVCREATE_") and f.endswith(rev + ".lsp")]
    check(f"releases/ twin at {rev} exists", len(twins) == 1, str(twins))
    if len(twins) == 1:
        twin = open(os.path.join(RELEASES_DIR, twins[0]), encoding="ascii").read()
        check("releases/ twin is identical", twin == SRC)


# =================================================================== vm =====

def fresh(extra=""):
    vm = VM()
    if LIB:
        vm.load(LIB)
    vm.load(LSP)
    # the drawing the spa is handed to us on; the VM refuses an entmake
    # onto a layer that does not exist, exactly as AutoCAD draws nothing
    vm.loads('(entmake (list (cons 0 "LAYER") (cons 2 "POOL") (cons 70 0)'
             ' (cons 62 4) (cons 6 "CONTINUOUS")))')
    if extra:
        vm.loads(extra)
    return vm


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


def live(vm, kind=None, layer=None):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if kind and grp(d, 0) != kind:
            continue
        if layer and grp(d, 8) != layer:
            continue
        out.append(d)
    return out


def rows(vm):
    """The report table, as (colour, text) in drawing order."""
    return [(grp(d, 62), grp(d, 1)) for d in live(vm, "TEXT")]


def red(vm):
    return [t for c, t in rows(vm) if c == 1]


def cyan(vm):
    return [t for c, t in rows(vm) if c == 4]


def row_after(vm, label):
    """The ACTUAL cell of the report row whose ITEM cell is LABEL."""
    cells = [t for _, t in rows(vm)]
    if label in cells:
        i = cells.index(label)
        return cells[i + 2] if i + 2 < len(cells) else None
    return None


def hinges(vm):
    """Every hinge line, as (start end linetype), west to east."""
    out = [(grp(d, 10), grp(d, 11), grp(d, 6))
           for d in live(vm, "LINE", "COVER")]
    return sorted(out, key=lambda h: (h[0][0], h[0][1]))


def labels(vm):
    return [grp(d, 1) for d in live(vm, "MTEXT", "TEXT")]


def cover(vm):
    for d in live(vm, layer="COVER"):
        if grp(d, 0) in ("LWPOLYLINE", "CIRCLE"):
            return grp(d, 0), d
    return None, None


def cover_verts(d):
    return [(p[1], p[2]) for p in d
            if isinstance(p, list) and p and p[0] == 10]


def cover_bulges(d):
    return [p.b if isinstance(p, Dot) else p[1] for p in d
            if (isinstance(p, Dot) and p.a == 42)
            or (isinstance(p, list) and p and p[0] == 42)]


RECT = '''
 (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "POOL")
                '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                (list 10 0.0 0.0) '(42 . 0.0) (list 10 100.0 0.0) '(42 . 0.0)
                (list 10 100.0 60.0) '(42 . 0.0) (list 10 0.0 60.0) '(42 . 0.0)))'''

TALL = '''
 (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "POOL")
                '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                (list 10 0.0 0.0) '(42 . 0.0) (list 10 60.0 0.0) '(42 . 0.0)
                (list 10 60.0 100.0) '(42 . 0.0) (list 10 0.0 100.0) '(42 . 0.0)))'''


def block(grade, taper):
    return f'''
 (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity") '(8 . "POOL")
                '(100 . "AcDbBlockReference") '(2 . "SPA COVER DETAILS")
                (list 10 400.0 400.0 0.0) '(66 . 1)))
 (entmake (list '(0 . "ATTRIB") '(8 . "POOL") '(2 . "GRADE")
                '(1 . "Grade: {grade}")))
 (entmake (list '(0 . "ATTRIB") '(8 . "POOL") '(2 . "TAPER")
                '(1 . "Taper: {taper}")))
 (entmake (list '(0 . "SEQEND") '(8 . "POOL")))'''


def run(vm, script, ss=None):
    """The command, with the leading None that answers the pickfirst
    probe unless the caller supplies a pre-selection."""
    try:
        vm.run("c:SPACOVCREATE", [ss] + list(script))
    except LispError as e:
        raise AssertionError(f"SPACOVCREATE failed: {e}") from None
    return "".join(vm.printed)


# ================================================ 1. the copied shop data ===

print("\nthe shop data copied from SPA")

spa_vm = VM()
if LIB:
    spa_vm.load(LIB)
spa_vm.load(SPA_LSP)
scv_vm = fresh()


def both(spa_expr, scv_expr):
    return spa_vm.loads(spa_expr), scv_vm.loads(scv_expr)


a, b = both("spa:*foamtab*", "scv:*foamtab*")
check("the foam sheet table matches SPA's, row for row", a == b)
a, b = both("spa:*hardtab*", "scv:*hardtab*")
check("the hardware table matches SPA's", a == b)
a, b = both("spa:*hardnames*", "scv:*hardnames*")
check("the hardware column names match SPA's", a == b)
a, b = both("spa:*foamdflt*", "scv:*foamdflt*")
check("the fallback foam sheet matches SPA's", a == b)
a, b = both("spa:*foamdpc*", "scv:*foamdpc*")
check("the fallback piece counts match SPA's", a == b)
a, b = both("spa:*thermotaper*", "scv:*thermotaper*")
check("the Thermo-Light taper matches SPA's", a == b)

same = True
for n in range(2, 13):
    a, b = both(f"(spa:hingetypes {n} nil)", f"(scv:hingetypes {n} nil)")
    if a != b:
        same = False
        print(f"       n={n}: SPA {a}, here {b}")
check("the Hinge Arrangement Chart matches SPA's for 2..12 pieces", same)
check("and Thermo-Light is velcro throughout",
      scv_vm.loads("(scv:hingetypes 5 t)") == ["V", "V", "V", "V"])
check("the chart is the documented 5-piece row",
      scv_vm.loads("(scv:hingetypes 5 nil)") == ["H", "V", "V", "H"])

for taper, want in (("Taper: 4-2", "4-2"), ("4-2 Flat", "4-2"),
                    ("  3-3  ", "3-3"), ("1-3/8", "1-3/8"),
                    ("nonsense", None)):
    got = scv_vm.loads(f'(scv:tapernorm (scv:aftercolon "{taper}"))')
    check(f"taper {taper!r} reads as {want!r}",
          (got or None) == want, f"(got {got!r})")
for grade, want in (("Ultra", "ULTRA"), ("Grade: Economy", "ECONOMY"),
                    ("Thermo-Light", "THERMOLIGHT"), ("", "STANDARD"),
                    ("anything else", "STANDARD")):
    got = scv_vm.loads(f'(scv:gradenorm (scv:aftercolon "{grade}"))')
    check(f"grade {grade!r} reads as {want}", got == want, f"(got {got!r})")


# ====================================================== 2. the offset itself =

print("\nthe offset")

vm = fresh()
SQ = ('(list (cons (list 0.0 0.0) 0.0) (cons (list 10.0 0.0) 0.0)'
      ' (cons (list 10.0 10.0) 0.0) (cons (list 0.0 10.0) 0.0))')

off = vm.loads(f"(scv:offset {SQ} 2.0)")
pt_near("a square offsets to a square: SW", off[0].a, [-2.0, -2.0])
pt_near("  SE", off[1].a, [12.0, -2.0])
pt_near("  NE", off[2].a, [12.0, 12.0])
pt_near("  NW", off[3].a, [-2.0, 12.0])
check("and keeps its straight runs straight",
      all(abs(v.b) < 1e-12 for v in off))

near("a counter-clockwise loop has positive area",
     vm.loads(f"(scv:area2 (scv:flatten {SQ}))"), 200.0)
near("and its mirror image negative",
     vm.loads(f"(scv:area2 (scv:flatten (scv:revclosed {SQ})))"), -200.0)
check("a clockwise loop is turned round before anything else happens",
      vm.loads(f"(cadr (car (scv:pick-loop (list (scv:st t (scv:revclosed {SQ}))))))")
      == vm.loads(SQ)[0])

# a 100 x 60 rectangle with a radius 12 corner at the bottom right, which
# is the shape SPA draws.  Offset 6: the wall runs go out 6, and the
# corner stays on (88 12) with its radius 12 -> 18, which moves its two
# tangent points to (88 -6) and (106 12) -- and its BULGE does not move
# at all, because the arc still sweeps ninety degrees.
B = math.tan(math.pi / 8.0)
FILLET = (f'(list (cons (list 0.0 0.0) 0.0) (cons (list 88.0 0.0) {B})'
          f' (cons (list 100.0 12.0) 0.0) (cons (list 100.0 60.0) 0.0)'
          f' (cons (list 0.0 60.0) 0.0))')
off = vm.loads(f"(scv:offset {FILLET} 6.0)")
pt_near("a tangent radius corner: the wall meets it at", off[1].a,
        [88.0, -6.0], 1e-9)
pt_near("  and it leaves at", off[2].a, [106.0, 12.0], 1e-9)
near("  with the bulge untouched", off[1].b, B, 1e-12)
ai = vm.loads(f"(scv:arcinfo (list 88.0 -6.0) (list 106.0 12.0) {B})")
pt_near("  so the offset arc is on the ORIGINAL centre", ai[0], [88.0, 12.0],
        1e-6)
near("  at r + d", ai[1], 18.0, 1e-6)
near("  sweeping the same ninety degrees", ai[2], math.pi / 2.0, 1e-6)

circ = vm.loads('(scv:circlep (scv:offset (scv:st-verts (scv:circle-strand'
                ' (list (cons 0 "CIRCLE") (cons 10 (list 5.0 5.0 0.0))'
                ' (cons 40 3.0)))) 2.0))')
check("a circle offsets to a circle", circ is not None)
if circ:
    pt_near("  on the same centre", circ[0], [5.0, 5.0])
    near("  at r + d", circ[1], 5.0)

ch = vm.loads(f"(scv:chordpoly (scv:flatten {SQ}) 5.0)")
check("the chord across the middle of a square is the square",
      ch == [0.0, 10.0], f"(got {ch})")
check("and off the end of it there is no chord at all",
      vm.loads(f"(scv:chordpoly (scv:flatten {SQ}) 50.0)") in (None, [], False))

near("ceil does not round a number that is already whole",
     vm.loads("(scv:ceilv (/ 96.0 48.0))"), 2)
near("but does round one that is not", vm.loads("(scv:ceilv 2.05)"), 3)


# ================================================= 3. the command, end to end

print("\nthe command")

vm = fresh(RECT)
spa = list(vm.entities)
said = run(vm, [spa, None, None])

kind, d = cover(vm)
check("Enter, Enter draws the cover as one closed polyline", kind == "LWPOLYLINE")
check("  on layer COVER", grp(d, 8) == "COVER")
check("  closed", grp(d, 70) == 1)
check("  offset 6 all round",
      cover_verts(d) == [(-6.0, -6.0), (106.0, -6.0), (106.0, 66.0),
                         (-6.0, 66.0)], str(cover_verts(d)))
check("the spa itself is left alone",
      any(grp(x, 8) == "POOL" for x in live(vm, "LWPOLYLINE")))

check("THE TAPER NOBODY GAVE IS SAID, IN RED, IN THE REPORT",
      "TAPER NOT GIVEN - STD 4-2 ASSUMED" in red(vm), str(red(vm)))
check("  and the grade/taper row is red with it",
      ("STD 4-2" in red(vm)))
check("  and it says so at the command line too",
      "TAPER NOT GIVEN" in said)
check("the report names the offset it used", row_after(vm, "COVER OFFSET")
      == "6.00")
check("  the cover across", row_after(vm, "COVER ACROSS") == "112.00")
check("  and up", row_after(vm, "COVER UP") == "72.00")
check("  the piece count as a count, not a measurement",
      row_after(vm, "PIECES (STD 4-2)") == "3")

hs = hinges(vm)
check("112 across on a 4-2 sheet is three pieces, so two hinges",
      len(hs) == 2, f"(got {len(hs)})")
if len(hs) == 2:
    near("  the first a third of the way along", hs[0][0][0], -6.0 + 112.0 / 3.0,
         1e-9)
    near("  the second two thirds", hs[1][0][0], -6.0 + 224.0 / 3.0, 1e-9)
    check("  both running the full height of the cover",
          all(abs(h[0][1] - -6.0) < 1e-9 and abs(h[1][1] - 66.0) < 1e-9
              for h in hs))
check("fold first, velcro second, per the chart",
      labels(vm) == ["Hinge", "Velcro Hinge"], str(labels(vm)))
check("  and only the fold hinge is dashed",
      hs[0][2] == "DASHED2" and hs[1][2] is None,
      f"({hs[0][2]!r}, {hs[1][2]!r})")
check("the hardware verdicts are advice, in cyan",
      any(t.startswith("VELCRO HINGES:") for t in cyan(vm)), str(cyan(vm)))

# -- the block
vm = fresh(RECT)
spa = list(vm.entities)
vm.loads(block("Ultra", "4-3 Tapered"))
blk = [e for e in vm.entities if e not in spa][0]
run(vm, [spa, None, [blk, [400.0, 400.0, 0.0]]])
check("clicking the block takes its grade and taper",
      row_after(vm, "GRADE / TAPER") == "ULTRA 4-3")
check("  and nothing is assumed, so nothing is flagged", red(vm) == [],
      str(red(vm)))

vm = fresh(RECT)
spa = list(vm.entities)
vm.loads(block("Standard", "no taper here"))
blk = [e for e in vm.entities if e not in spa][0]
said = run(vm, [spa, None, [blk, [400.0, 400.0, 0.0]]])
check("a block with an unreadable taper falls back and SAYS so",
      "TAPER NOT GIVEN - STD 4-2 ASSUMED" in red(vm), str(red(vm)))
check("  naming the tag it could not read", "No readable TAPER tag" in said)

# -- Thermo-Light: the grade settles the taper, so nothing is assumed
vm = fresh(RECT)
spa = list(vm.entities)
vm.loads(block("Thermo-Light", "no taper here"))
blk = [e for e in vm.entities if e not in spa][0]
run(vm, [spa, None, [blk, [400.0, 400.0, 0.0]]])
check("a Thermo-Light with no taper tag takes the one taper it comes in",
      row_after(vm, "GRADE / TAPER") == "THERMO 1-3/8",
      str(row_after(vm, "GRADE / TAPER")))
check("  which is not an assumption, so it is not flagged red",
      not any("TAPER NOT GIVEN" in t for t in red(vm)), str(red(vm)))
check("  but it IS said, in cyan",
      any("TAPER TAKEN FROM THE GRADE" in t for t in cyan(vm)), str(cyan(vm)))
check("  and every hinge on it is velcro",
      set(labels(vm)) == {"Velcro Hinge"}, str(labels(vm)))

# -- typing it
vm = fresh(RECT)
spa = list(vm.entities)
run(vm, [spa, None, "Type", "5-4"])
check("Type takes a typed taper", row_after(vm, "GRADE / TAPER") == "STD 5-4")
check("  and that is not an assumption either", red(vm) == [], str(red(vm)))

vm = fresh(RECT)
spa = list(vm.entities)
said = run(vm, [spa, None, "Type", "banana", "3-3"])
check("a taper that is not on the sheet is refused and re-asked",
      "Not a taper on the foam sheet" in said)
check("  and the second answer stands",
      row_after(vm, "GRADE / TAPER") == "STD 3-3")

# -- Back
vm = fresh(RECT)
spa = list(vm.entities)
said = run(vm, [spa, None, "Back", 12.0, None])
check("Back at the taper re-opens the offset",
      said.count("Stepping back one question.") == 1)
check("  and the new offset is the one drawn",
      row_after(vm, "COVER OFFSET") == "12.00")
check("  all the way round", row_after(vm, "COVER ACROSS") == "124.00")

vm = fresh(RECT)
spa = list(vm.entities)
said = run(vm, [spa, "Back", spa, 3.0, None])
check("Back at the offset re-opens the selection",
      said.count("Select the geometry that is the spa:") == 2)
check("  and the run carries on from there",
      row_after(vm, "COVER OFFSET") == "3.00")

# -- a pre-selection
vm = fresh(RECT)
spa = list(vm.entities)
said = run(vm, [None, None], ss=spa)
check("a highlight made before the command is the spa",
      "Select the geometry that is the spa:" not in said)
check("  and it is covered", cover(vm)[0] == "LWPOLYLINE")


# ============================================== 4. the shapes and the flags ==

print("\nthe shapes it is handed")

vm = fresh('''(entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity") '(8 . "POOL")
                             '(100 . "AcDbCircle") (list 10 10.0 10.0 0.0)
                             '(40 . 36.0)))''')
spa = list(vm.entities)
run(vm, [spa, 6.0, None])
kind, d = cover(vm)
check("a round spa comes back out as a CIRCLE, not a polygon of one",
      kind == "CIRCLE")
near("  r + d", grp(d, 40), 42.0)
pt_near("  on the same centre", grp(d, 10), [10.0, 10.0])
check("  hinged across its diameter", len(hinges(vm)) == 1)
near("  which is the longest hinge there is",
     float(row_after(vm, "FOAM LENGTH MAX")), 84.0, 1e-6)

vm = fresh(TALL)
spa = list(vm.entities)
run(vm, [spa, None, None])
check("a cover taller than it is wide hinges the OTHER way",
      row_after(vm, "HINGES RUN") == "ACROSS (dividing up)")
hs = hinges(vm)
check("  so the hinges are flat", len(hs) == 2
      and all(abs(h[0][1] - h[1][1]) < 1e-9 for h in hs))
check("  running the full width of the cover",
      all(abs(h[0][0] - -6.0) < 1e-9 and abs(h[1][0] - 66.0) < 1e-9
          for h in hs))
check("  and the labels read along them",
      all(grp(x, 11)[0] == 1.0 for x in live(vm, "MTEXT", "TEXT")))

# loose walls and a fillet arc, drawn out of order and some backwards --
# which is how a traced outline arrives
HP = math.pi / 2.0
LOOSE = "\n".join([
    '(entmake (list (cons 0 "LINE") (cons 100 "AcDbEntity") (cons 8 "POOL")'
    ' (cons 100 "AcDbLine") (list 10 100.0 12.0 0.0) (list 11 100.0 60.0 0.0)))',
    '(entmake (list (cons 0 "LINE") (cons 100 "AcDbEntity") (cons 8 "POOL")'
    ' (cons 100 "AcDbLine") (list 10 0.0 60.0 0.0) (list 11 0.0 0.0 0.0)))',
    f'(entmake (list (cons 0 "ARC") (cons 100 "AcDbEntity") (cons 8 "POOL")'
    f' (cons 100 "AcDbCircle") (list 10 88.0 12.0 0.0) (cons 40 12.0)'
    f' (cons 100 "AcDbArc") (cons 50 {-HP}) (cons 51 0.0)))',
    '(entmake (list (cons 0 "LINE") (cons 100 "AcDbEntity") (cons 8 "POOL")'
    ' (cons 100 "AcDbLine") (list 10 0.0 0.0 0.0) (list 11 88.0 0.0 0.0)))',
    '(entmake (list (cons 0 "LINE") (cons 100 "AcDbEntity") (cons 8 "POOL")'
    ' (cons 100 "AcDbLine") (list 10 100.0 60.0 0.0) (list 11 0.0 60.0 0.0)))',
])
vm = fresh(LOOSE)
spa = list(vm.entities)
said = run(vm, [spa, None, None])
check("five loose walls and an arc chain into one outline",
      "1 closed outline in the selection" in said, said.splitlines()[-6:])
kind, d = cover(vm)
verts = sorted(cover_verts(d))
check("  offset to the same cover the one polyline gave",
      verts == sorted([(-6.0, -6.0), (88.0, -6.0), (106.0, 12.0),
                       (106.0, 66.0), (-6.0, 66.0)]), str(verts))
check("  and the arc it was handed is still an arc",
      any(abs(b - B) < 1e-9 for b in cover_bulges(d)), str(cover_bulges(d)))

TWO = RECT + '''
 (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "POOL")
                '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                (list 10 10.0 10.0) '(42 . 0.0) (list 10 30.0 10.0) '(42 . 0.0)
                (list 10 30.0 30.0) '(42 . 0.0) (list 10 10.0 30.0) '(42 . 0.0)))'''
vm = fresh(TWO)
spa = list(vm.entities)
said = run(vm, [spa, None, None])
check("two loops in the selection: the biggest is the spa",
      "2 closed outlines in the selection" in said)
check("  and the cover is the big one's",
      cover_verts(cover(vm)[1]) == [(-6.0, -6.0), (106.0, -6.0),
                                    (106.0, 66.0), (-6.0, 66.0)])

STRAY = TWO + '''
 (entmake (list (cons 0 "LINE") (cons 100 "AcDbEntity") (cons 8 "POOL")
                (cons 100 "AcDbLine") (list 10 300.0 300.0 0.0)
                (list 11 340.0 300.0 0.0)))'''
vm = fresh(STRAY)
spa = list(vm.entities)
run(vm, [spa, None, None])
check("a run that never closes is ignored, and named for it",
      "1 SELECTED RUN NEVER CLOSED - IGNORED" in red(vm), str(red(vm)))

SPLINED = RECT + '''
 (entmake (list (cons 0 "SPLINE") (cons 100 "AcDbEntity") (cons 8 "POOL")
                (cons 100 "AcDbSpline") (cons 70 8)
                (list 10 200.0 200.0 0.0) (list 10 240.0 220.0 0.0)))'''
vm = fresh(SPLINED)
spa = list(vm.entities)
run(vm, [spa, None, None])
check("a spline is let through the filter so the run can say it was not read",
      any(t.startswith("1 SPLINE NOT READ") for t in red(vm)), str(red(vm)))
check("  and the rest of the selection is still covered",
      cover(vm)[0] == "LWPOLYLINE")

print("\nwhat it flags rather than fixes")

BIG = '''
 (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "POOL")
                '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                (list 10 0.0 0.0) '(42 . 0.0) (list 10 130.0 0.0) '(42 . 0.0)
                (list 10 130.0 120.0) '(42 . 0.0) (list 10 0.0 120.0) '(42 . 0.0)))'''
vm = fresh(BIG)
spa = list(vm.entities)
run(vm, [spa, None, None])
check("a hinge longer than the foam is drawn anyway",
      len(hinges(vm)) >= 1)
check("  and flagged, by number and by how far over",
      any(t.startswith("HINGE 1 EXCEEDS THE FOAM LENGTH") for t in red(vm)),
      str(red(vm)))

vm = fresh(RECT)
spa = list(vm.entities)
run(vm, [spa, None, "Type", "3-2"])
check("a piece count the taper does not allow is flagged",
      any("PIECES NOT ACCEPTABLE" in t for t in red(vm)), str(red(vm)))

vm = fresh()
said = run(vm, [None])
check("nothing selected, nothing drawn",
      "Nothing selected - nothing to cover." in said)
check("  and no cover left behind", cover(vm)[0] is None)

vm = fresh('''(entmake (list (cons 0 "LINE") (cons 100 "AcDbEntity")
                             (cons 8 "POOL") (cons 100 "AcDbLine")
                             (list 10 0.0 0.0 0.0) (list 11 50.0 0.0 0.0)))''')
spa = list(vm.entities)
said = run(vm, [spa, None])
check("geometry that cannot close says what is wrong with it",
      "nothing closes into an outline" in said)
check("  and asks again rather than giving up", said.count(
    "Select the geometry that is the spa:") == 2)

vm2 = fresh()
vm2.run("c:SPACOVCREATEVER", [])
check("SPACOVCREATEVER prints the banner",
      "SPACOVCREATE v" in "".join(vm2.printed))


# ==================================================================== end ====

print()
if failures:
    print(f"FAILED: {len(failures)}")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("test_spacovcreate: all checks passed")
