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
  brings in geometry of a known size, and SCALE/MOVE/ERASE that really
  move the fake entities.  These assert where the stock lands, that the
  old perimeter is erased only after the new geometry is placed, and
  that a size or shape mismatch stops instead of guessing.

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
from lispvm import VM, Sym, Ent, NIL, T, LispError

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

    def told(self, text):
        return any(text in s for s in self.said)

    # ---- entities
    def make(self, box):
        e = Ent()
        self.vm.entities.append(e)
        self.vm.entdata[e] = []
        self.bbox[e] = list(box)
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
            self.move(self.live(a[1]), a[3], a[4])
        elif c == "_.ERASE":
            for e in self.live(a[1]):
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
        base = path.replace("\\", "/").rsplit("/", 1)[-1]
        box = self.stock.get(base)
        if box is None:
            return NIL
        self.blocks.add(bname.upper())
        self.vm.tables.setdefault("BLOCK", set()).add(bname)
        # one block reference, sized as the file's contents
        return self.make([box[0][0], box[0][1], box[1][0], box[1][1]])

    def explode(self, e):
        b = self.bbox[e]
        self.vm.deleted.add(e)
        mid = (b[0] + b[2]) / 2.0
        self.make([b[0], b[1], mid, b[3]])      # two halves, same union
        self.make([mid, b[1], b[2], b[3]])

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
        if selection is None:
            return NIL
        ss = ["<ss>"]
        for box in selection:
            ss.append(fake.make(list(box[0]) + list(box[1])))
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


def cmd_names(vm):
    return [c[0] for c in vm.commands if c]


def runtime():
    print("runtime -- same size, straight swap")
    # highlighted perimeter: 100x50 centred on (500, 300)
    sel = [((450.0, 275.0), (550.0, 325.0))]
    # the stock file holds the same 100x50 shape, drawn around the origin
    stock = {"5M_Tech.dwg": ((-50.0, -25.0), (50.0, 25.0))}
    vm, fake = build(stock=stock, selection=sel,
                     files=["5M_Tech.dwg", "20M_Tech.dwg"])
    run(vm, ["5M"])

    names = cmd_names(vm)
    check("the stock DWG was inserted", "_.-INSERT" in names)
    check("it was exploded", "_.EXPLODE" in names)
    check("no SCALE when the sizes already agree", "_.SCALE" not in names)
    check("the old perimeter was erased", "_.ERASE" in names)
    check("the scratch block was purged", fake.purged == ["STOCK$0"],
          fake.purged)
    check("the run is one undo group", fake.undo == ["_BEgin", "_End"],
          fake.undo)
    check("erase comes after the new geometry is placed",
          names.index("_.ERASE") > names.index("_.MOVE"))

    placed = [e for e in fake.bbox if e not in vm.deleted]
    box = fake.union(placed)
    eq("stock landed on the highlighted perimeter, left", box[0], 450.0)
    eq("stock landed on the highlighted perimeter, bottom", box[1], 275.0)
    eq("stock landed on the highlighted perimeter, right", box[2], 550.0)
    eq("stock landed on the highlighted perimeter, top", box[3], 325.0)
    eq("the last name is remembered", fake.env.get("StockCover_Last"), "5M")

    print("runtime -- Enter reuses the last name")
    vm, fake = build(stock=stock, selection=sel,
                     files=["5M_Tech.dwg"], env={"StockCover_Last": "5M"})
    run(vm, [""])
    check("Enter alone re-inserted the remembered stock",
          "_.-INSERT" in cmd_names(vm))

    print("runtime -- a whole-drawing unit mismatch, scaled to fit")
    # same shape, but the stock file is drawn in feet: 1/12 the size
    stock12 = {"5M_Tech.dwg": ((-50.0 / 12, -25.0 / 12), (50.0 / 12, 25.0 / 12))}
    vm, fake = build(stock=stock12, selection=sel, files=["5M_Tech.dwg"])
    run(vm, ["5M", "Fit"])
    check("a uniform mismatch offers Fit and takes it",
          "_.SCALE" in cmd_names(vm))
    placed = [e for e in fake.bbox if e not in vm.deleted]
    box = fake.union(placed)
    eq("scaled stock fills the highlighted width", box[2] - box[0], 100.0, 1e-6)
    eq("scaled stock fills the highlighted height", box[3] - box[1], 50.0, 1e-6)
    eq("and is centred on it", (box[0] + box[2]) / 2.0, 500.0, 1e-6)

    print("runtime -- Asis leaves the stock at 1:1")
    vm, fake = build(stock=stock12, selection=sel, files=["5M_Tech.dwg"])
    run(vm, ["5M", "Asis"])
    check("Asis skips the scale", "_.SCALE" not in cmd_names(vm))
    check("Asis still erases the old perimeter", "_.ERASE" in cmd_names(vm))
    placed = [e for e in fake.bbox if e not in vm.deleted]
    box = fake.union(placed)
    eq("1:1 stock keeps its own width", box[2] - box[0], 100.0 / 12, 1e-6)
    eq("but is centred where it was wanted", (box[0] + box[2]) / 2.0, 500.0, 1e-6)

    print("runtime -- Cancel changes nothing")
    vm, fake = build(stock=stock12, selection=sel, files=["5M_Tech.dwg"])
    run(vm, ["5M", "Cancel"])
    erases = [c for c in vm.commands if c and c[0] == "_.ERASE"]
    check("Cancel erases only the stock it brought in", len(erases) == 1,
          erases)
    survivors = [e for e in fake.bbox if e not in vm.deleted]
    check("the highlighted perimeter is still there", len(survivors) == 1)
    eq("untouched", fake.bbox[survivors[0]], [450.0, 275.0, 550.0, 325.0])
    check("and the scratch block definition goes with it",
          fake.purged == ["STOCK$0"], fake.purged)

    print("runtime -- a shape mismatch defaults to leaving it alone")
    # 100x50 highlighted, but this file is 100x80: not the same cover
    wrong = {"5M_Tech.dwg": ((-50.0, -40.0), (50.0, 40.0))}
    vm, fake = build(stock=wrong, selection=sel, files=["5M_Tech.dwg"])
    run(vm, ["5M", "Cancel"])
    prompts = " ".join(str(p) for p, _ in vm.prompts)
    check("the mismatch prompt defaults to Asis, not Fit",
          "<Asis>" in prompts, prompts)
    check("Cancel after a mismatch keeps the old perimeter",
          len([e for e in fake.bbox if e not in vm.deleted]) == 1)

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
    both["5MB_Tech.dwg"] = ((-50.0, -25.0), (50.0, 25.0))
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
    eq("landed in the right place", fake.union(placed),
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


def main():
    structural()
    resolution()
    runtime()
    print()
    if failures:
        print(f"{len(failures)} FAILURE(S): " + ", ".join(failures))
        raise SystemExit(1)
    print("all STOCKCOVER checks passed")


if __name__ == "__main__":
    main()
