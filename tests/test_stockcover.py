#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for STOCKCOVER.lsp -- pasting a stock cover DWG onto a
highlighted perimeter.

Three kinds of check, all runnable without AutoCAD:

* Structural checks read the real .lsp and assert what makes it safe to
  run: balanced parens, pure ASCII, every system variable it changes
  also saved and restored, no variable leaking to the global namespace,
  and a version banner that agrees with the releases/ twin.
* A reference port of the name-resolution ladder ("5M" -> 5M_Tech.dwg)
  pins the matching rules, including the ones that must NOT fire.
* Runtime checks drive the actual LISP through tests/lispvm.py with a
  stub AutoCAD underneath it: a fake stock folder, a fake -INSERT that
  brings in geometry of a known size, and MOVE/ERASE that really move
  the fake entities.  These assert where the stock lands (anchored on
  the shared POINT entities, bottom-left onto bottom-left), that the
  old perimeter is erased only after the new geometry is placed, that
  no prompt fires after the name, and that an anchor-span mismatch is
  shouted about but never silently rescaled.
* The two things the stub AutoCAD models on top: MOVE and ERASE passing
  over a locked layer's objects without a word (a swap that only half
  happened is refused up front, or caught after the move, and never
  reported whole), and a UCS turned to follow the pool (the stock comes
  in square to the World axes and lands on its anchor).

Usage:  python3 tests/test_stockcover.py
"""

import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

LSP = os.path.join(REPO_DIR, "lisp", "stockcover", "STOCKCOVER.lsp")
RELEASES_DIR = os.path.join(REPO_DIR, "releases")

import lispvm
from lispvm import VM, Sym, Ent, Dot, NIL, T, LispError

failures = []


def check(label, cond, detail=""):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        failures.append(label)


def eq(label, got, want, tol=1e-9):
    if isinstance(want, (int, float)) and isinstance(got, (int, float)):
        ok = abs(got - want) <= tol
    else:
        ok = got == want
    check(label, ok, f"(got {got!r}, want {want!r})")


# ================================================================ source ====

SRC = open(LSP, encoding="ascii").read()   # also asserts pure ASCII


def strip(src):
    """Blank out ;-comments and string bodies, keeping line structure."""
    out = []
    i = 0
    in_str = False
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


CLEAN = strip(SRC)


def top_forms(clean):
    forms = []
    depth = 0
    start = None
    for i, ch in enumerate(clean):
        if ch == "(":
            if depth == 0:
                start = i
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                forms.append(clean[start:i + 1])
    return forms


def structural():
    print("structural checks")

    depth = CLEAN.count("(") - CLEAN.count(")")
    eq("parens balanced", depth, 0)

    # every setvar'd system variable is also read back at the top and
    # restored -- a half-restored OSMODE follows the user around all day
    changed = set(re.findall(r'\(setvar\s+"([A-Z]+)"', CLEAN))
    saved = set(re.findall(r'\(getvar\s+"([A-Z]+)"', CLEAN))
    missing = sorted(v for v in changed if v not in saved)
    check("every changed sysvar is also saved", not missing, missing)

    restore = re.search(r"\(defun stock:restore \(\)(.*?)\n\n", CLEAN, re.S)
    check("stock:restore exists", restore is not None)
    if restore:
        restored = set(re.findall(r'\(setvar\s+"([A-Z]+)"', restore.group(1)))
        gap = sorted(v for v in changed if v not in restored)
        check("every changed sysvar is restored", not gap, gap)

    # locals: nothing a defun assigns may escape into the global namespace
    globals_declared = set(re.findall(r"\(setq\s+(\*[\w-]+\*)", CLEAN))
    leaks = []
    for f in top_forms(CLEAN):
        m = re.match(r"\(defun\s+([^\s()]+)\s*\(([^)]*)\)", f, re.S)
        if not m:
            continue
        name, arglist = m.group(1), m.group(2)
        toks = arglist.replace("/", " / ").split()
        declared = set(t for t in toks if t != "/")
        body = f[m.end():]
        for var in re.findall(r"\(foreach\s+([^\s()]+)", body):
            if var not in declared:
                leaks.append(f"{name}: foreach {var}")
        for seg in re.findall(r"\(setq\s+([A-Za-z*][\w:*+/<>=-]*)", body):
            if seg not in declared and seg not in globals_declared:
                leaks.append(f"{name}: setq {seg}")
    check("no variable leaks out of a defun", not leaks, leaks)

    # globals a defun assigns would be a hidden write; state lives in the
    # AutoCAD profile instead, so it survives a restart
    inner_global = []
    for f in top_forms(CLEAN):
        if not f.startswith("(defun"):
            continue
        body = f[f.index("(") + 1:]
        for g in re.findall(r"\(setq\s+(\*[\w-]+\*)", body):
            inner_global.append(g)
    check("no defun writes a global (setenv is used instead)",
          not inner_global, inner_global)

    # the version banner release_lisp.py reads, and its dated twin
    m = re.search(r'\*stockcover-version\*\s+"v(\d+)\.(\d+)"', SRC)
    check("version banner present", m is not None)
    if m:
        rev = f"{m.group(1)}{m.group(2)}"
        twins = [n for n in os.listdir(RELEASES_DIR)
                 if re.match(rf"STOCKCOVER_\d{{6}}_REV{rev}\.lsp$", n)]
        check(f"releases/ twin at REV{rev} exists", len(twins) == 1, twins)
        if len(twins) == 1:
            twin = open(os.path.join(RELEASES_DIR, twins[0]),
                        encoding="ascii").read()
            check("releases/ twin is identical", twin == SRC)

    # the folder the user is told to set, and the commands README lists
    check("default stock folder is the TechTeam share",
          r'"F:\\TechTeam\\2022 StockCoverTech"' in SRC)
    for cmd in ("c:STOCKCOVER", "c:STOCKLIST", "c:STOCKCOVER-CFG"):
        check(f"{cmd} defined", f"(defun {cmd} " in CLEAN)

    # two rules AutoCAD 2015+ enforces at runtime, caught statically:
    # (command ...) may not run inside *error* without a prior
    # *push-error-using-command*, and may not be routed through
    # vl-catch-all-apply at all -- command-s is the replacement for both
    err = re.search(r"\(defun \*error\* \(msg\)(.*?)\n\n", CLEAN, re.S)
    check("*error* exists", err is not None)
    if err:
        check("*error* never calls bare (command)",
              not re.search(r"\(command[\s)]", err.group(1)))
    check("(command) is never routed through vl-catch-all-apply",
          not re.search(r"vl-catch-all-apply\s+'command[\s)]", CLEAN))
    # (command) with no arguments is Esc: the old back-out idiom cancels
    # whatever command is pending.  CLEAN blanks string bodies, which
    # makes every real call look bare, so scan a strings-kept view.
    code = []
    in_str = False
    i = 0
    while i < len(SRC):
        ch = SRC[i]
        if in_str:
            code.append(ch)
            if ch == "\\":
                code.append(SRC[i + 1])
                i += 2
                continue
            if ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
            code.append(ch)
        elif ch == ";":
            while i < len(SRC) and SRC[i] != "\n":
                i += 1
            continue
        else:
            code.append(ch)
        i += 1
    check("no bare (command) cancel loops",
          not re.search(r"\(command\s*\)", "".join(code)))

    # the runtime ssget stub ignores modes, so the pickfirst probe is
    # pinned here: the "_I" ask comes first, the interactive one only
    # inside its empty branch
    check("a pre-typed highlight is probed first (pickfirst)",
          '(ssget "_I")' in SRC
          and SRC.index('(ssget "_I")') < SRC.index("(ssget))"))


# ======================================================= name resolution ====

SUFFIXES = ["_Tech"]


def match_ref(name, files):
    """Reference port of stock:match -- exact stem, then each suffix,
    then a leading-substring sweep; a rung is only tried when the one
    above it came up empty."""
    up = name.upper()
    hit = [f for f in files if os.path.splitext(f)[0].upper() == up]
    if not hit:
        for s in SUFFIXES:
            hit = [f for f in files
                   if os.path.splitext(f)[0].upper() == (name + s).upper()]
            if hit:
                break
    if not hit:
        hit = [f for f in files
               if os.path.splitext(f)[0].upper().startswith(up)]
    return hit


FOLDER = r"F:\TechTeam\2022 StockCoverTech"
FILES = ["5M_Tech.dwg", "20M_Tech.dwg", "5MB_Tech.dwg", "5M.dwg",
         "12L_Tech.dwg", "Grecian_Tech.dwg"]


def resolution():
    print("name resolution")
    eq("exact stem wins over every suffix and prefix",
       match_ref("5M", FILES), ["5M.dwg"])
    eq("the suffix rung finds 20M_Tech",
       match_ref("20M", [f for f in FILES if f != "5M.dwg"]),
       ["20M_Tech.dwg"])
    eq("5M_Tech is reachable by its full stem too",
       match_ref("5M_Tech", FILES), ["5M_Tech.dwg"])
    # the rung order is the whole point: without it "5M" would drag in
    # 5MB_Tech.dwg alongside the file the user actually meant
    eq("an exact hit is never widened by the prefix sweep",
       match_ref("5M", FILES), ["5M.dwg"])
    eq("a suffix hit is never widened by the prefix sweep",
       match_ref("20M", FILES), ["20M_Tech.dwg"])
    eq("lower case works", match_ref("grecian", FILES), ["Grecian_Tech.dwg"])
    eq("an ambiguous prefix returns every candidate",
       sorted(match_ref("5", FILES)),
       sorted(["5M_Tech.dwg", "5MB_Tech.dwg", "5M.dwg"]))
    eq("no match returns nothing", match_ref("99Z", FILES), [])


# ============================================================== runtime =====

class Err:
    """what vl-catch-all-apply hands back on failure"""
    def __init__(self, msg):
        self.msg = msg


class Fake:
    """A stub AutoCAD: a stock folder, entities with bounding boxes, and
    the handful of editor commands STOCKCOVER drives."""

    def __init__(self, vm, files=None, stock=None, env=None):
        self.vm = vm
        self.files = list(files if files is not None else FILES)
        # bare name -> ((minx miny) (maxx maxy)) of what the file holds
        self.stock = dict(stock or {})
        self.env = dict(env or {})
        self.bbox = {}          # Ent -> [minx, miny, maxx, maxy]
        self.blocks = set()
        self.folders = {FOLDER.upper()}
        self.purged = []
        self.undo = []
        self.said = []
        self.insert_broken = False
        self.ref_pts = {}       # block ref -> anchor points inside it
        self.unerasable = set() # entities ERASE skips for its own reasons
        self.piece_layer = None # layer the exploded stock pieces land on

    def locked(self, e):
        lay = None
        for g in self.vm.entdata.get(e, []):
            if isinstance(g, Dot) and g.a == 8:
                lay = g.b
        rec = self.vm.tablerecs.get("LAYER", {}).get((lay or "").upper())
        if rec is None:
            return False
        flags = [g.b for g in self.vm.recdata[rec]
                 if isinstance(g, Dot) and g.a == 70]
        return bool(flags and flags[0] & 4)

    def told(self, text):
        return any(text in s for s in self.said)

    # ---- entities
    def make(self, box):
        e = Ent()
        self.vm.entities.append(e)
        self.vm.entdata[e] = []
        self.bbox[e] = list(box)
        return e

    def make_point(self, x, y):
        e = self.make([x, y, x, y])
        self.vm.entdata[e] = [Dot(0, "POINT"), Dot(10, [x, y, 0.0])]
        return e

    def live(self, ss):
        return [e for e in ss[1:] if e not in self.vm.deleted]

    def union(self, ents):
        bs = [self.bbox[e] for e in ents]
        return [min(b[0] for b in bs), min(b[1] for b in bs),
                max(b[2] for b in bs), max(b[3] for b in bs)]

    # ---- the editor commands STOCKCOVER uses
    def command(self, vm, a):
        vm.commands.append(list(a))
        if not a:
            return NIL
        c = a[0]
        if c == "_.UNDO":
            self.undo.append(a[1])
        elif c == "_.-INSERT":
            self.insert(a[1])
        elif c == "_.EXPLODE":
            self.explode(a[1])
        elif c == "_.SCALE":
            self.scale(self.live(a[1]), a[3], float(a[4]))
        elif c == "_.MOVE":
            # MOVE and ERASE pass over a locked layer's objects without
            # a word under CMDECHO 0 -- modelled, or the tests could not
            # see a swap that only half happened
            self.move([e for e in self.live(a[1]) if not self.locked(e)],
                      a[3], a[4])
        elif c == "_.ERASE":
            for e in self.live(a[1]):
                if not self.locked(e) and e not in self.unerasable:
                    vm.deleted.add(e)
        elif c == "_.-PURGE":
            self.purged.append(a[2])
        return NIL

    def insert(self, spec):
        # "STOCK$0=F:/.../5M_Tech.dwg" -- exactly what the LISP builds
        if self.insert_broken:
            return          # an AutoCAD that will not take the = form
        bname, _, path = spec.partition("=")
        self.read(path.strip('"'), bname)

    def read(self, path, bname):
        # a stock entry is ((min)(max)) or {"box": ..., "pts": [(x,y),..]}
        base = path.replace("\\", "/").rsplit("/", 1)[-1]
        entry = self.stock.get(base)
        if entry is None:
            return NIL
        box = entry["box"] if isinstance(entry, dict) else entry
        pts = entry.get("pts", []) if isinstance(entry, dict) else []
        self.blocks.add(bname.upper())
        self.vm.tables.setdefault("BLOCK", set()).add(bname)
        # one block reference, sized as the file's contents; the anchor
        # POINTs it holds come out when it is exploded
        ref = self.make([box[0][0], box[0][1], box[1][0], box[1][1]])
        self.ref_pts[ref] = list(pts)
        return ref

    def explode(self, e):
        b = self.bbox[e]
        self.vm.deleted.add(e)
        mid = (b[0] + b[2]) / 2.0
        for half in ([b[0], b[1], mid, b[3]], [mid, b[1], b[2], b[3]]):
            h = self.make(half)                 # two halves, same union
            if self.piece_layer:
                self.vm.entdata[h] = [Dot(8, self.piece_layer)]
        for x, y in self.ref_pts.pop(e, []):    # the file's anchor POINTs
            self.make_point(x, y)

    def scale(self, ents, base, f):
        bx, by = base[0], base[1]
        for e in ents:
            b = self.bbox[e]
            self.bbox[e] = [bx + (b[0] - bx) * f, by + (b[1] - by) * f,
                            bx + (b[2] - bx) * f, by + (b[3] - by) * f]

    def move(self, ents, frm, to):
        dx, dy = to[0] - frm[0], to[1] - frm[1]
        for e in ents:
            b = self.bbox[e]
            self.bbox[e] = [b[0] + dx, b[1] + dy, b[2] + dx, b[3] + dy]


def build(files=None, stock=None, env=None, selection=None):
    """A VM with STOCKCOVER.lsp loaded over the stub AutoCAD."""
    vm = VM()
    fake = Fake(vm, files=files, stock=stock, env=env)
    B = lispvm.BUILTINS

    def reg(name, fn):
        # the reader lower-cases symbols, so registrations must match
        B[Sym(name.lower())] = fn

    # princ is silent in the VM; keep what the routine tells the user so
    # the tests can assert on it
    reg("princ", lambda vm, a: (fake.said.append(a[0]) or a[0])
        if a and isinstance(a[0], str) else NIL)

    reg("vl-load-com", lambda vm, a: NIL)
    reg("vl-file-directory-p",
        lambda vm, a: T if a[0].rstrip("\\/").upper() in fake.folders else NIL)
    reg("vl-directory-files",
        lambda vm, a: list(fake.files) if fake.files else NIL)
    reg("vl-filename-base",
        lambda vm, a: os.path.splitext(a[0].replace("\\", "/").rsplit("/", 1)[-1])[0])
    reg("vl-filename-directory",
        lambda vm, a: a[0].replace("/", "\\").rsplit("\\", 1)[0])
    reg("getenv", lambda vm, a: fake.env.get(a[0], NIL))
    reg("setenv", lambda vm, a: (fake.env.__setitem__(a[0], a[1]), a[1])[1])
    reg("getfiled", lambda vm, a: vm.pop_script(a[0], "getfiled") or NIL)

    # the selection the user highlights
    def _ssget(vm, a):
        # a selection entry is ((min)(max)) for geometry, or
        # ("pt", x, y) for an anchor POINT
        if selection is None:
            return NIL
        ss = ["<ss>"]
        for item in selection:
            if item[0] == "pt":
                ss.append(fake.make_point(item[1], item[2]))
            else:
                e = fake.make(list(item[0]) + list(item[1]))
                if len(item) > 2:               # ((min) (max) "LAYER")
                    vm.entdata[e] = [Dot(8, item[2])]
                ss.append(e)
        return ss
    reg("ssget", _ssget)

    reg("vlax-ename->vla-object", lambda vm, a: a[0])
    reg("vlax-safearray->list", lambda vm, a: a[0])
    reg("vlax-3d-point", lambda vm, a: list(a))
    reg("vlax-get-acad-object", lambda vm, a: NIL)
    reg("vla-get-ActiveDocument", lambda vm, a: NIL)
    reg("vla-get-ModelSpace", lambda vm, a: "<modelspace>")
    # ActiveX names the definition after the file, not after a scratch name
    reg("vla-InsertBlock",
        lambda vm, a: fake.read(a[2], os.path.splitext(
            a[2].replace("\\", "/").rsplit("/", 1)[-1])[0]))

    def _bbox(vm, a):
        obj, lls, urs = a[0], a[1], a[2]
        if obj not in fake.bbox:
            raise LispError("no bounding box", vm)
        b = fake.bbox[obj]
        vm.set(lls, [b[0], b[1], 0.0])
        vm.set(urs, [b[2], b[3], 0.0])
        return NIL
    reg("vla-GetBoundingBox", _bbox)

    def _catch(vm, a):
        try:
            return vm.call_value(a[0], list(a[1]) if a[1] is not NIL else [])
        except LispError as exc:
            return Err(str(exc))
    reg("vl-catch-all-apply", _catch)
    reg("vl-catch-all-error-p", lambda vm, a: T if isinstance(a[0], Err) else NIL)

    reg("command", fake.command)
    reg("command-s", fake.command)

    vm.load(LSP)
    return vm, fake


def run(vm, script):
    vm.script = list(script)
    vm.prompts = []
    fn = vm.get(Sym("c:stockcover"))
    vm.call_defun(Sym("c:stockcover"), fn, [])
    return vm


def run_cmd(vm, name, script=()):
    """Drive any command in the file, not just c:STOCKCOVER."""
    vm.script = list(script)
    vm.prompts = []
    fn = vm.get(Sym(name.lower()))
    vm.call_defun(Sym(name.lower()), fn, [])
    return vm


def cmd_names(vm):
    return [c[0] for c in vm.commands if c]


def companions():
    """STOCKLIST and STOCKCOVER-CFG: the two commands beside the
    headline one, neither of which had ever been run."""
    print("companions -- STOCKLIST lists what is there")
    vm, fake = build(files=["5M_Tech.dwg", "20M_Tech.dwg"])
    run_cmd(vm, "c:STOCKLIST")
    said = "".join(fake.said)
    check("it counts the drawings and names the folder",
          "2 stock drawing(s) in " in said, said)
    check("and lists each stem, without the .dwg",
          "5M_Tech" in said and "20M_Tech" in said and ".dwg" not in said,
          said)

    print("companions -- STOCKLIST when the folder is not reachable")
    vm, fake = build(files=["5M_Tech.dwg"])
    fake.folders = set()                    # the share is not mounted
    run_cmd(vm, "c:STOCKLIST")
    said = "".join(fake.said)
    check("it says the folder is unreachable and how to repoint it",
          "not reachable" in said and "STOCKCOVER-CFG" in said, said)

    print("companions -- STOCKLIST when the folder is empty")
    vm, fake = build(files=[])
    run_cmd(vm, "c:STOCKLIST")
    check("it says there are no DWGs", "no DWGs in" in "".join(fake.said),
          "".join(fake.said))

    print("companions -- STOCKCOVER-CFG repoints the folder")
    vm, fake = build(files=["5M_Tech.dwg", "20M_Tech.dwg"])
    fake.folders.add("D:\\NEWSTOCK")
    run_cmd(vm, "c:STOCKCOVER-CFG", ["D:\\NEWSTOCK\\5M_Tech.dwg"])
    said = "".join(fake.said)
    check("the picked file's folder is remembered",
          fake.env.get("StockCover_Folder") == "D:\\NEWSTOCK",
          repr(fake.env))
    check("it reports the new folder and what is in it",
          "set to D:\\NEWSTOCK" in said and "DWG(s) there" in said, said)

    print("companions -- Escape at the file dialog changes nothing")
    vm, fake = build(files=["5M_Tech.dwg"])
    before = dict(fake.env)
    run_cmd(vm, "c:STOCKCOVER-CFG", [None])
    check("it says unchanged", "unchanged." in "".join(fake.said))
    check("and nothing was remembered", fake.env == before, repr(fake.env))


def runtime():
    print("runtime -- anchored swap, same span")
    # highlighted: a 100x50 box centred on (500, 300), plus the two
    # anchor POINTs at its bottom left and top right
    sel = [((450.0, 275.0), (550.0, 325.0)),
           ("pt", 450.0, 275.0), ("pt", 550.0, 325.0)]
    # the stock file: the same 100x50 shape around the origin, with its
    # own anchor points on the matching corners
    stock = {"5M_Tech.dwg": {"box": ((-50.0, -25.0), (50.0, 25.0)),
                             "pts": [(-50.0, -25.0), (50.0, 25.0)]}}
    vm, fake = build(stock=stock, selection=sel,
                     files=["5M_Tech.dwg", "20M_Tech.dwg"])
    run(vm, ["5M"])

    names = cmd_names(vm)
    check("the stock DWG was inserted", "_.-INSERT" in names)
    check("it was exploded", "_.EXPLODE" in names)
    check("nothing is ever rescaled", "_.SCALE" not in names)
    check("the old perimeter was erased", "_.ERASE" in names)
    check("the scratch block was purged", fake.purged == ["STOCK$0"],
          fake.purged)
    check("the run is one undo group", fake.undo == ["_Begin", "_End"],
          fake.undo)
    check("erase comes after the new geometry is placed",
          names.index("_.ERASE") > names.index("_.MOVE"))
    check("only the name prompt fired - no fit questions",
          len(vm.prompts) == 1, vm.prompts)

    placed = [e for e in fake.bbox if e not in vm.deleted]
    box = fake.union(placed)
    eq("stock landed on the highlighted perimeter, left", box[0], 450.0)
    eq("stock landed on the highlighted perimeter, bottom", box[1], 275.0)
    eq("stock landed on the highlighted perimeter, right", box[2], 550.0)
    eq("stock landed on the highlighted perimeter, top", box[3], 325.0)
    check("the stock's anchor points survive in the drawing",
          sorted([fake.bbox[e][0], fake.bbox[e][1]] for e in placed
                 if fake.vm.entdata[e])[0] == [450.0, 275.0])
    eq("the last name is remembered", fake.env.get("StockCover_Last"), "5M")

    print("runtime -- anchoring follows the POINTs, not the box")
    # anchor points sit OUTSIDE the geometry box on both sides, and the
    # highlighted box is deliberately off-centre relative to its
    # anchors: only true point-to-point anchoring lands this right
    sel2 = [((452.0, 275.0), (548.0, 320.0)),
            ("pt", 445.0, 270.0), ("pt", 555.0, 330.0)]
    stock2 = {"5M_Tech.dwg": {"box": ((-48.0, -25.0), (48.0, 20.0)),
                              "pts": [(-55.0, -30.0), (55.0, 30.0)]}}
    vm, fake = build(stock=stock2, selection=sel2, files=["5M_Tech.dwg"])
    run(vm, ["5M"])
    check("matching spans raise no warning",
          not fake.told("ANCHORS DO NOT AGREE"), fake.said)
    # shift = target BL anchor - stock BL anchor = (500, 300)
    placed = [e for e in fake.bbox if e not in vm.deleted
              and not fake.vm.entdata[e]]
    eq("geometry follows the anchor shift", fake.union(placed),
       [452.0, 275.0, 548.0, 320.0])

    print("runtime -- Enter reuses the last name")
    vm, fake = build(stock=stock, selection=sel,
                     files=["5M_Tech.dwg"], env={"StockCover_Last": "5M"})
    run(vm, [""])
    check("Enter alone re-inserted the remembered stock",
          "_.-INSERT" in cmd_names(vm))

    print("runtime -- a span mismatch is shouted about, never rescaled")
    # this stock is half the size: the wrong file for this perimeter
    half = {"5M_Tech.dwg": {"box": ((-25.0, -12.5), (25.0, 12.5)),
                            "pts": [(-25.0, -12.5), (25.0, 12.5)]}}
    vm, fake = build(stock=half, selection=sel, files=["5M_Tech.dwg"])
    run(vm, ["5M"])
    check("the warning names the disagreement",
          fake.told("ANCHORS DO NOT AGREE"), fake.said)
    check("it points at U to roll back", fake.told("one U rolls this back"),
          fake.said)
    check("no prompt fired for it either", len(vm.prompts) == 1, vm.prompts)
    check("and nothing was rescaled", "_.SCALE" not in cmd_names(vm))
    placed = [e for e in fake.bbox if e not in vm.deleted
              and not fake.vm.entdata[e]]
    eq("placed anchored at its own size", fake.union(placed),
       [450.0, 275.0, 500.0, 300.0])

    print("runtime -- no anchor points anywhere falls back to box corners")
    plain_sel = [((450.0, 275.0), (550.0, 325.0))]
    plain_stock = {"5M_Tech.dwg": ((-50.0, -25.0), (50.0, 25.0))}
    vm, fake = build(stock=plain_stock, selection=plain_sel,
                     files=["5M_Tech.dwg"])
    run(vm, ["5M"])
    check("it says the highlight had no anchors",
          fake.told("no anchor points highlighted"), fake.said)
    check("and that the stock had none",
          fake.told("no anchor points in the stock file"), fake.said)
    placed = [e for e in fake.bbox if e not in vm.deleted]
    eq("box-corner fallback still lands it", fake.union(placed),
       [450.0, 275.0, 550.0, 325.0])

    print("runtime -- anchors on one side only")
    vm, fake = build(stock=plain_stock, selection=sel, files=["5M_Tech.dwg"])
    run(vm, ["5M"])
    check("the highlighted anchors are found",
          fake.told("anchor points found"), fake.said)
    check("the stock falls back to its corners",
          fake.told("no anchor points in the stock file"), fake.said)
    placed = [e for e in fake.bbox if e not in vm.deleted
              and not fake.vm.entdata[e]]
    eq("mixed anchoring still lands it", fake.union(placed),
       [450.0, 275.0, 550.0, 325.0])

    print("runtime -- nothing highlighted, nothing touched")
    vm, fake = build(stock=stock, selection=None, files=["5M_Tech.dwg"])
    run(vm, [])
    check("no insert without a selection", "_.-INSERT" not in cmd_names(vm))
    check("no undo group opened either", fake.undo == [], fake.undo)

    print("runtime -- an unknown name stops before touching the drawing")
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    run(vm, ["99Z"])
    check("no insert for a name that matches nothing",
          "_.-INSERT" not in cmd_names(vm))
    check("no undo group opened", fake.undo == [], fake.undo)

    print("runtime -- an ambiguous name asks which one")
    both = dict(stock)
    both["5MB_Tech.dwg"] = stock["5M_Tech.dwg"]
    vm, fake = build(stock=both, selection=sel,
                     files=["5M_Tech.dwg", "5MB_Tech.dwg"])
    run(vm, ["5", 2])
    spec = [c for c in vm.commands if c and c[0] == "_.-INSERT"][0][1]
    check("the picked file is the one inserted", "5MB_Tech.dwg" in spec, spec)
    check("and it is the one that got placed", "_.MOVE" in cmd_names(vm))

    print("runtime -- ActiveX carries the insert when -INSERT will not")
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    fake.insert_broken = True
    run(vm, ["5M"])
    check("the fallback still brought the stock in", "_.MOVE" in cmd_names(vm))
    check("and purged the definition ActiveX actually made",
          fake.purged == ["5M_Tech"], fake.purged)
    placed = [e for e in fake.bbox if e not in vm.deleted]
    eq("landed anchored in the right place", fake.union(placed),
       [450.0, 275.0, 550.0, 325.0])

    print("runtime -- a name collision on the fallback path is refused")
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    fake.insert_broken = True
    vm.tables.setdefault("BLOCK", set()).add("5M_Tech")
    run(vm, ["5M"])
    check("it says which block is in the way",
          fake.told('block named "5M_Tech" is already in this drawing'),
          fake.said)
    check("and places nothing", "_.MOVE" not in cmd_names(vm))

    print("runtime -- the insert path survives the space in the folder name")
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    run(vm, ["5M"])
    spec = [c for c in vm.commands if c and c[0] == "_.-INSERT"][0][1]
    check("the spec is one unquoted token (command strings need none)",
          '"' not in spec, spec)
    check("and slashed forward", "\\" not in spec.split("=", 1)[1], spec)
    check("into a scratch block name, never redefining an existing one",
          spec.startswith("STOCK$0="), spec)
    explode = [c for c in vm.commands if c and c[0] == "_.EXPLODE"][0]
    check("EXPLODE ends its selection with Enter, not Esc",
          explode[-1] == "", explode)

    print("runtime -- an unreachable folder is reported, not crashed through")
    vm, fake = build(stock=stock, selection=sel, files=[])
    fake.folders = set()
    run(vm, [])
    check("no insert when the share is offline",
          "_.-INSERT" not in cmd_names(vm))

    print("runtime -- system variables come back")
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    before = dict(vm.sysvars)
    run(vm, ["5M"])
    diff = {k: (before.get(k), v) for k, v in vm.sysvars.items()
            if before.get(k) != v}
    check("every sysvar is back where it started", not diff, diff)


def lock_layer(vm, name):
    """A locked layer in the drawing, where tblsearch will find it."""
    vm.loads('(entmake (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")'
             ' (cons 100 "AcDbLayerTableRecord") (cons 2 "%s") (cons 70 4)'
             ' (cons 62 7) (cons 6 "Continuous")))' % name)


def locked_layers():
    """A swap that could only half happen used to be reported whole.
    ERASE and MOVE pass over a locked layer's objects without a word
    under CMDECHO 0, and the done line counted the highlight as "out"
    whatever ERASE did."""
    sel = [((450.0, 275.0), (550.0, 325.0), "POOL"),
           ("pt", 450.0, 275.0), ("pt", 550.0, 325.0)]
    stock = {"5M_Tech.dwg": {"box": ((-50.0, -25.0), (50.0, 25.0)),
                             "pts": [(-50.0, -25.0), (50.0, 25.0)]}}

    print("locked -- a perimeter on a locked layer is refused up front")
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    lock_layer(vm, "POOL")
    before = dict(vm.sysvars)
    run(vm, ["5M"])
    check("it names the layer to unlock", fake.told("Unlock POOL first"),
          fake.said)
    check("nothing was inserted", "_.-INSERT" not in cmd_names(vm))
    check("no name was asked for a swap that cannot happen",
          not vm.prompts, vm.prompts)
    check("never 'placed on the anchor'",
          not fake.told("placed on the anchor"), fake.said)
    check("no undo group opened", fake.undo == [], fake.undo)
    check("sysvars untouched", vm.sysvars == before)

    print("locked -- a locked CURRENT layer is refused up front too")
    # -INSERT lands on a locked current layer, then EXPLODE and MOVE
    # refuse it: the cover stayed at 0,0 while ERASE took the perimeter
    sel2 = [((450.0, 275.0), (550.0, 325.0), "POOL"),
            ("pt", 450.0, 275.0), ("pt", 550.0, 325.0)]
    vm, fake = build(stock=stock, selection=sel2, files=["5M_Tech.dwg"])
    lock_layer(vm, "MINE")
    vm.sysvars["CLAYER"] = "MINE"
    run(vm, ["5M"])
    check("it names the current layer", fake.told("Unlock MINE first"),
          fake.said)
    check("nothing was inserted or erased",
          "_.-INSERT" not in cmd_names(vm) and "_.ERASE" not in cmd_names(vm))

    print("locked -- stock pieces landing on a locked layer are not"
          " reported placed, and the old perimeter stays")
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    lock_layer(vm, "COVER")
    fake.piece_layer = "COVER"
    run(vm, ["5M"])
    old = [e for e in fake.bbox if fake.vm.entdata.get(e) == [Dot(8, "POOL")]]
    check("the old perimeter was NOT erased",
          old and all(e not in vm.deleted for e in old))
    check("no ERASE was issued", "_.ERASE" not in cmd_names(vm))
    check("never 'placed on the anchor'",
          not fake.told("placed on the anchor"), fake.said)
    check("it says the stock did not all move, and names the layer",
          fake.told("did NOT all move onto the anchor")
          and fake.told("locked layer(s) COVER"), fake.said)
    check("and points at U", fake.told("one U rolls this back"), fake.said)
    check("the undo group still closed", fake.undo == ["_Begin", "_End"],
          fake.undo)

    print("locked -- the done line counts what ERASE really took")
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    real = fake.command

    def refuse_first(vm, a):
        # ERASE passes over one highlighted object for reasons of its own
        if a and a[0] == "_.ERASE":
            fake.unerasable.add(a[1][1])
        return real(vm, a)
    lispvm.BUILTINS[Sym("command")] = refuse_first
    try:
        run(vm, ["5M"])
    finally:
        lispvm.BUILTINS[Sym("command")] = real
    check("2 out, not the 3 handed to ERASE",
          fake.told("object(s) in, 2 out."), fake.said)
    check("and the one left behind is said",
          fake.told("1 highlighted object(s) could NOT be erased"), fake.said)


def rotated_ucs():
    """Under a UCS turned to follow the pool, -INSERT's 0.0 rotation is
    read in the UCS and the anchors went to MOVE as World points: the
    stock came in turned, its span stopped matching, and the drafter was
    told they had named the wrong stock drawing."""
    import math
    th = math.pi / 2.0                       # UCS turned 90 degrees
    ox, oy = 1000.0, 2000.0                  # and moved off the origin

    def rot(x, y, a):
        c, s_ = round(math.cos(a)), round(math.sin(a))
        return x * c - y * s_, x * s_ + y * c

    sel = [((450.0, 275.0), (550.0, 325.0)),
           ("pt", 450.0, 275.0), ("pt", 550.0, 325.0)]
    stock = {"5M_Tech.dwg": {"box": ((-50.0, -25.0), (50.0, 25.0)),
                             "pts": [(-50.0, -25.0), (50.0, 25.0)]}}
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    # the UCS is the VM's own (tests/test_lispvm_ucs.py), given by its
    # axes so a quarter turn is exact: X along world Y, Y along world -X.
    # A trans that knew it used to be swapped in here.
    vm.set_ucs((ox, oy, 0.0), xdir=(0.0, 1.0, 0.0), ydir=(-1.0, 0.0, 0.0))
    # put back, not deleted: a later run in this file that reaches
    # ROTATE needs the VM's own
    saved_rotate = lispvm.BUILTINS.get(Sym("vla-rotate"))
    frame = {}                               # ref -> (ox, oy, angle)

    def rbox(b, bx, by, a):
        xs, ys = [], []
        for x, y in ((b[0], b[1]), (b[2], b[3])):
            rx, ry = rot(x - bx, y - by, a)
            xs.append(rx + bx)
            ys.append(ry + by)
        return [min(xs), min(ys), max(xs), max(ys)]

    real_read = fake.read

    def read(path, bname):
        # the -INSERT: point (0,0,0) and rotation 0.0 are UCS values
        ref = real_read(path, bname)
        b = fake.bbox[ref]
        fake.bbox[ref] = rbox([b[0] + ox, b[1] + oy, b[2] + ox, b[3] + oy],
                              ox, oy, th)
        frame[ref] = (ox, oy, th)
        vm.entdata[ref] = [Dot(0, "INSERT"), Dot(10, [ox, oy, 0.0]),
                           Dot(50, th)]
        return ref
    fake.read = read

    def vla_rotate(vm, a):
        obj, base, ang = a[0], a[1], a[2]
        if isinstance(base, list) and base and isinstance(base[0], list):
            base = base[0]
        fake.bbox[obj] = rbox(fake.bbox[obj], base[0], base[1], ang)
        fx, fy, fa = frame[obj]
        nx, ny = rot(fx - base[0], fy - base[1], ang)
        frame[obj] = (nx + base[0], ny + base[1], fa + ang)
        vm.entdata[obj] = [Dot(0, "INSERT"),
                           Dot(10, [frame[obj][0], frame[obj][1], 0.0]),
                           Dot(50, frame[obj][2])]
        fake.rotated = True
        return NIL
    lispvm.BUILTINS[Sym("vla-rotate")] = vla_rotate

    real_explode = fake.explode

    def explode(e):
        # the anchor POINTs come out where the reference has them
        fx, fy, fa = frame.get(e, (0.0, 0.0, 0.0))
        fake.ref_pts[e] = [tuple(v + o for v, o in zip(rot(x, y, fa),
                                                       (fx, fy)))
                           for x, y in fake.ref_pts.get(e, [])]
        real_explode(e)
    fake.explode = explode

    def move(ents, frm, to):
        # MOVE reads its two points in the UCS
        w0 = vm.ucs_to_wcs(frm)
        w1 = vm.ucs_to_wcs(to)
        for e in ents:
            b = fake.bbox[e]
            dx, dy = w1[0] - w0[0], w1[1] - w0[1]
            fake.bbox[e] = [b[0] + dx, b[1] + dy, b[2] + dx, b[3] + dy]
    fake.move = move

    print("UCS -- a turned UCS places the stock square and on the anchor")
    try:
        run(vm, ["5M"])
    finally:
        for name, fn in (("vla-rotate", saved_rotate),):
            if fn is None:
                lispvm.BUILTINS.pop(Sym(name), None)
            else:
                lispvm.BUILTINS[Sym(name)] = fn
    check("no 'wrong drawing' warning for the right drawing",
          not fake.told("ANCHORS DO NOT AGREE"), fake.said)
    placed = [e for e in fake.bbox if e not in vm.deleted
              and not fake.vm.entdata[e]]
    eq("the stock lands square on the highlighted perimeter",
       fake.union(placed), [450.0, 275.0, 550.0, 325.0])
    check("and says so", fake.told("placed on the anchor"), fake.said)
    check("the turn was undone as a World-axis rotation of the reference",
          getattr(fake, "rotated", False))


def insert_places_nothing():
    """-INSERT can define the block and still place no reference.  Then
    (entlast) is the drafter's own last object, and it used to be handed
    to the squaring turn and to EXPLODE: a rotated block of theirs came
    back at 0 degrees and in pieces, and the pieces -- new since the
    mark -- were taken for the stock and moved onto the anchor."""
    sel = [((450.0, 275.0), (550.0, 325.0)),
           ("pt", 450.0, 275.0), ("pt", 550.0, 325.0)]
    stock = {"5M_Tech.dwg": {"box": ((-50.0, -25.0), (50.0, 25.0)),
                             "pts": [(-50.0, -25.0), (50.0, 25.0)]}}
    vm, fake = build(stock=stock, selection=sel, files=["5M_Tech.dwg"])
    theirs = []
    real_ssget = lispvm.BUILTINS[Sym("ssget")]

    def ssget(vm, a):
        # the highlight, and then the drafter's own turned block is the
        # last object in the drawing when the insert runs
        ss = real_ssget(vm, a)
        e = fake.make([0.0, 0.0, 10.0, 10.0])
        vm.entdata[e] = [Dot(0, "INSERT"), Dot(10, [5.0, 5.0, 0.0]),
                         Dot(50, 0.5)]
        theirs.append(e)
        return ss
    lispvm.BUILTINS[Sym("ssget")] = ssget

    def insert(spec):
        # the block is defined, but no reference is placed
        bname = spec.partition("=")[0]
        fake.blocks.add(bname.upper())
        vm.tables.setdefault("BLOCK", set()).add(bname)
    fake.insert = insert
    turned = []
    lispvm.BUILTINS[Sym("vla-rotate")] = \
        lambda vm, a: (turned.append(a[0]), NIL)[1]

    print("insert -- a -INSERT that placed nothing touches nothing of theirs")
    run(vm, ["5M"])
    mine = theirs[0]
    check("the drafter's block was not turned", mine not in turned, turned)
    check("nor exploded", "_.EXPLODE" not in cmd_names(vm)
          and mine not in vm.deleted, cmd_names(vm))
    check("nothing was moved as though it were the stock",
          "_.MOVE" not in cmd_names(vm), cmd_names(vm))
    check("and it says the stock brought nothing in",
          fake.told("brought nothing in"), fake.said)
    check("the old perimeter is left standing",
          "_.ERASE" not in cmd_names(vm), cmd_names(vm))


def main():
    structural()
    resolution()
    companions()
    runtime()
    saved = dict(lispvm.BUILTINS)
    try:
        locked_layers()
        rotated_ucs()
        insert_places_nothing()
    finally:
        lispvm.BUILTINS.clear()
        lispvm.BUILTINS.update(saved)
    print()
    if failures:
        print(f"{len(failures)} FAILURE(S): " + ", ".join(failures))
        raise SystemExit(1)
    print("all STOCKCOVER checks passed")


if __name__ == "__main__":
    main()
