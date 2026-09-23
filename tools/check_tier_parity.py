#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The grouped build reads what the standalone one reads -- no more, no less.

tools/mirror_shared.py turns lisp/<tool> into shared/parts/<tool> by a
handful of transforms: SWAP a local helper for a cal: one, EXPAND or
COLLAPSE a call so it passes what the local read for itself, REWRITE a
defun, rename SYMBOLS.  Each one is a claim that the grouped build
behaves like the standalone one at that spot.  tests/test_cal_parity.py
tests that claim for the ARGUMENTS a helper is called with.  What it
cannot see is what a helper reads from AROUND its arguments, and that is
where every drift found so far has lived:

  * a knob the local helper reads and the cal: one hard-codes --
    lin:*back-words* against '("B" "BACK" "U" "UNDO"), *cchk-flat-eps*
    against 1e-12: the drafter's LAZTUNE value tuned one build only
  * a profile key the cal: helper reads and the local copy never did --
    cal:ink's CalofinInk-<ROLE>, missing from eleven local inks, so a
    CALSET colour worked in LAZPASS and nowhere else
  * a sysvar a builtin reads behind the helper's back -- spachk:datestr
    went through rtos, so DIMZIN; cal:datestr does arithmetic
  * a hand-typed argument in the mirror table the source moved away
    from -- SPACHECK's expand kept snapshotting CLAYER
  * a sentinel renamed on one side only -- SPA-BACK against CAL-BACK

So for each transform this builds the FOOTPRINT of both sides -- the
helper and every defun it reaches in its own tier, closed over with
check_osnap's call graph -- as a set of atoms:

  global:NAME     a free variable, read or written (a knob, or state)
  sysvar:NAME     a string literal naming a sysvar, so a hand-typed
                  syssave table counts as much as a (getvar ...)
  implicit:NAME   a sysvar a builtin reads unasked: rtos and angtos
                  read DIMZIN and UNITMODE, and LUNITS/LUPREC or
                  AUNITS/AUPREC when the mode or precision is left out
  env:KEY         a profile or registry key: getenv, setenv,
                  vl-registry-*, and any defun that hands a parameter
                  on to one (cal:setting); (strcat "Pre" ..) is env:Pre*
  sym:NAME        a quoted symbol (a sentinel, a role)
  effect:FN       entmake/entmod/command/command-s/setvar/vla-put-* ...
  fn:NAME         a namespaced function the side calls but its tier does
                  not define (lzd:*, another tool's helper)

-- and compares them once the mirror's own renames are applied: the
symbols map (applied as the mirror applies it, case and all), and the
tool's prefix against cal: for anything that is NOT a knob (spa:*sysold*
is the same slot as cal:*sysold*; pool:*eps* is not the same input as
cal:*eps*, because a drafter tunes the first and nothing tunes the
second).  "A knob" is one of the tool's own tunables OR of the sibling
file a satellite's swapped helper lives in (TUTORIALSPA drives SPA's
spa:syssave, which reads SPA's spa:*dimvars*), and it is judged by the
name BEFORE the symbols map renames it.

A sysvar is a name the tree hands to getvar or setvar as a literal, one
of the dimension variables (DIMTAD, DIMASZ... -- SPA's snapshot table
names them bare), or a literal handed to a wrapper that passes its
argument on to getvar/setvar ((spa:setv "DIMTAD" 0)).

Rules:

  P1  an atom one side of a swap/collapse/rewrite has and the other has
      not.  Pairs that share state (a save and its restore, through
      *sysold*) are compared as one group -- what the save reads is
      what the restore writes -- but the state itself is compared pair
      by pair.  A sentinel counts only where the tool's surviving code
      quotes it.
  P2  a LAZTUNE knob the regenerated twin mentions fewer times than the
      lisp/ file does: some grouped code path stopped honouring it,
      whichever transform did it (a replace or a rewrite included).
  P3  a (cal:X ...) call in a twin, as the mirror writes it NOW, with a
      number of arguments cal:X does not take -- a call inside a quoted
      '(lambda ...) included, since that is how mapcar is written here.
      AutoLISP arity is exact, so the grouped build dies there.  Only a
      twin whose calls can differ from lisp/'s by more than a name is
      read as code: one with an expand, a collapse or a rewrite, a swap
      onto a helper of another arity, or a symbols rename onto a
      library function -- and every hand-kept twin.
  P4  a name the grouped build reads and nothing in it sets: a global
      in drop_globals, or one a swapped-away helper kept (tool:*sysold*),
      that the twin's surviving code still names -- its load-time setq
      aside -- so a reset or a test there touches a dead slot; a
      symbols rename onto a cal: name CALOFIN-LIB never mentions; or a
      LAZTUNE knob of the tool that the mirror drops or renames, so the
      grouped build never reads the value a drafter tunes.
  P5  a hand-kept twin (a shared/parts file mirror_shared.py does not
      write -- LISPLAB) whose CODE differs from its lisp/ file by more
      than its swaps.  Its swap map is derived: every lisp/ helper the
      twin lacks that has a cal: namesake.  Strings are one token, so
      lesson prose may differ; a LAZDIAG hook, a call or a knob may not.
      The same derived map puts the hand twin through P1, P2 and P4.

P1 and P2 differences a person has read and decided are harmless live in
tools/tier_parity_baseline.txt, one per line with the reason -- the
check_back pattern: an unlisted one fails, and a listed one the tree no
longer produces is reported as stale so the file cannot rot.  A line is
keyed by the TOOL's own source file (its mirror entry's src), not the
file the helper lives in: POOL, POOLDEMO and TUTORIALPOOL each type
their own expand over pool:syssave, and accepting one must not accept
the other two.  P3, P4 and P5 take no baseline: none is ever harmless.
P0 is the mirror refusing to write a twin at all; the twin on disk is
read in its place.

It says the tiers disagree, not which one is right.  It does not see a
pure-arithmetic difference with no outside read (test_cal_parity's
inputs do), or a bug both tiers share (test_handler_error_mode and the
cancel sweeps do).

    python3 tools/check_tier_parity.py          # exit 1 on a new difference
    python3 tools/check_tier_parity.py --all    # also the baselined ones
    python3 tools/check_tier_parity.py --list TOOL   # both footprints
"""

import argparse
import collections
import contextlib
import difflib
import functools
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from callib import ROOT, decomment, lsp_files, read  # noqa: E402
from check_handlers import APPLIERS, Str, Sym, read_forms  # noqa: E402
from check_osnap import reach  # noqa: E402
import knobs  # noqa: E402
import mirror_shared  # noqa: E402

BASELINE = HERE / "tier_parity_baseline.txt"
SKIP_DIRS = ("standards_checker",)

# ---------------------------------------------------------------------
#  Reading.  check_handlers' reader, because it keeps the quote: the
#  difference between 'SPA-BACK (a sentinel) and SPA-BACK (a variable),
#  and between (mapcar 'helper ...) and a data list, is the whole point
#  of two of the atom kinds.
# ---------------------------------------------------------------------

_FORMS = {}


def parse(text):
    """TEXT decommented and read, quote kept -- memoised on the text."""
    forms = _FORMS.get(text)
    if forms is None:
        forms = _FORMS[text] = read_forms(decomment(text))
    return forms


def is_sym(x):
    return isinstance(x, Sym)


def is_str(x):
    return isinstance(x, Str)


def head(f):
    return f[0].lower() if isinstance(f, list) and f and is_sym(f[0]) else None


def quoted(f):
    """X of a (quote X), else None."""
    return f[1] if head(f) == "quote" and len(f) > 1 else None


def num_like(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def arglist(form):
    """(params, locals) of a defun or lambda, lower-cased."""
    al = form[2] if head(form) == "defun" else (form[1] if len(form) > 1 else None)
    if not isinstance(al, list):
        return [], []
    toks = [t.lower() for t in al if is_sym(t)]
    if "/" in toks:
        k = toks.index("/")
        return toks[:k], toks[k + 1:]
    return toks, []


def defuns(forms):
    """name -> [defun form], nested ones included, in reading order."""
    out = {}
    stack = list(reversed(forms))
    while stack:
        f = stack.pop()
        if not isinstance(f, list):
            continue
        if head(f) == "defun" and len(f) >= 3 and is_sym(f[1]):
            out.setdefault(f[1].lower(), []).append(f)
        stack.extend(reversed(f))
    return out


# ---------------------------------------------------------------------
#  What one defun reads directly
# ---------------------------------------------------------------------

CONSTS = {"t", "nil", "pi", "/", ".", "*error*"}
#: builtin -> sysvars it reads with no argument naming them; the second
#: pair is (argument count below which the mode is read, sysvar,
#: argument count below which the precision is read, sysvar)
IMPLICIT = {
    "rtos": ({"DIMZIN", "UNITMODE"}, (2, "LUNITS", 3, "LUPREC")),
    "angtos": ({"DIMZIN", "UNITMODE"}, (2, "AUNITS", 3, "AUPREC")),
}
#: a CALL that changes the drawing or the session: a helper that stops
#: making one (a rewrite that loses its tag entmod) has drifted even
#: though it reads nothing new
EFFECTS = {"entmake", "entmakex", "entmod", "entdel", "entupd", "command",
           "command-s", "vl-cmdf", "setvar", "setenv", "vl-registry-write",
           "vl-registry-delete", "regapp", "vlax-put-property",
           "vlax-ldata-put", "dictadd", "dictremove"}
#: the profile/registry readers and writers, and which argument is a key
ENV_FNS = {"getenv": (0,), "setenv": (0,),
           "vl-registry-read": (0, 1), "vl-registry-write": (0, 1),
           "vl-registry-delete": (0, 1)}
SEED_SYSVARS = {"CDATE", "DATE", "DIMZIN", "UNITMODE", "LUNITS", "LUPREC",
                "AUNITS", "AUPREC", "ANGBASE", "ANGDIR", "CLAYER", "CECOLOR",
                "OSMODE", "CMDECHO", "DIMSTYLE", "COLORTHEME", "ERRNO"}
#: the dimension variables, spelled out rather than matched as DIM*: a
#: snapshot table names them bare ('("DIMTAD" "DIMASZ" ...)), and
#: "DIMENSION" is an entity type, not a sysvar
DIMVARS = set("""
DIMADEC DIMALT DIMALTD DIMALTF DIMALTRND DIMALTTD DIMALTTZ DIMALTU DIMALTZ
DIMANNO DIMAPOST DIMARCSYM DIMASO DIMASSOC DIMASZ DIMATFIT DIMAUNIT DIMAZIN
DIMBLK DIMBLK1 DIMBLK2 DIMCEN DIMCLRD DIMCLRE DIMCLRT DIMCONSTRAINTICON
DIMDEC DIMDLE DIMDLI DIMDSEP DIMEXE DIMEXO DIMFRAC DIMFXL DIMFXLON DIMGAP
DIMJOGANG DIMJUST DIMLAYER DIMLDRBLK DIMLFAC DIMLIM DIMLTEX1 DIMLTEX2
DIMLTYPE DIMLUNIT DIMLWD DIMLWE DIMPOST DIMRND DIMSAH DIMSCALE DIMSD1 DIMSD2
DIMSE1 DIMSE2 DIMSHO DIMSOXD DIMSTYLE DIMTAD DIMTDEC DIMTFAC DIMTFILL
DIMTFILLCLR DIMTIH DIMTIX DIMTM DIMTMOVE DIMTOFL DIMTOH DIMTOL DIMTOLJ DIMTP
DIMTSZ DIMTVP DIMTXSTY DIMTXT DIMTXTDIRECTION DIMTXTRULER DIMTZIN DIMUPT
DIMZIN""".split())
SYSVAR_RE = re.compile(r'\((?:getvar|setvar)\s+"([A-Za-z_][A-Za-z0-9_]*)"', re.I)
#: the builtins that take a sysvar name, and which argument it is: the
#: seed of the fixed point that finds (spa:setv "DIMTAD" 0)
SYSVAR_FNS = {"getvar": (0,), "setvar": (0,)}


def env_key(arg):
    if is_str(arg):
        return str(arg)
    if head(arg) == "strcat" and len(arg) > 1 and is_str(arg[1]):
        return str(arg[1]) + "*"
    return None


class Reader:
    """Direct atoms and calls of a defun, memoised on the form.

    SYSVARS is the set of names a string literal is read as a sysvar
    by; FNS every function name the tree defines (a quoted one of those
    is a function handed on, not a sentinel); WRAPPERS the defuns that
    pass a parameter through to a profile read, as name -> key argument
    positions."""

    def __init__(self, sysvars, fns, wrappers):
        self.sysvars = sysvars
        self.fns = fns
        self.wrappers = wrappers
        self.memo = {}

    def of(self, defun):
        key = id(defun)
        if key not in self.memo:
            p, l = arglist(defun)
            atoms, calls = set(), set()
            self.body(defun[3:], set(p) | set(l), atoms, calls)
            self.memo[key] = (atoms, calls)
        return self.memo[key]

    def forms(self, forms):
        """(atoms, calls) of free-standing FORMS -- an expand's text."""
        atoms, calls = set(), set()
        self.body(forms, set(), atoms, calls)
        return atoms, calls

    def body(self, forms, bound, atoms, calls):
        for f in forms:
            self.expr(f, bound, atoms, calls)

    def fnref(self, name, atoms, calls):
        n = name.lower()
        calls.add(n)
        if n in EFFECTS or n.startswith("vla-put-"):
            atoms.add("effect:" + n)

    def data(self, x, bound, atoms, calls):
        """A quoted datum: strings naming sysvars, sentinel symbols, and
        the functions a dispatch table names."""
        if is_str(x):
            if x.upper() in self.sysvars:
                atoms.add("sysvar:" + x.upper())
        elif is_sym(x):
            n = x.lower()
            if n in CONSTS or num_like(n):
                return
            if n in self.fns:
                self.fnref(n, atoms, calls)
            else:
                atoms.add("sym:" + str(x))
        elif isinstance(x, list):
            if head(x) == "lambda":             # '(lambda (v) ...) is code
                self.lam(x, bound, atoms, calls)
                return
            for y in x:
                self.data(y, bound, atoms, calls)

    def lam(self, f, bound, atoms, calls):
        p, l = arglist(f)
        self.body(f[2:], bound | set(p) | set(l), atoms, calls)

    def expr(self, f, bound, atoms, calls):
        if is_str(f):
            if f.upper() in self.sysvars:
                atoms.add("sysvar:" + f.upper())
            return
        if is_sym(f):
            n = f.lower()
            if n in bound or n in CONSTS or num_like(n):
                return
            atoms.add("global:" + str(f))
            return
        if not isinstance(f, list) or not f:
            return
        h = head(f)
        if h is None:
            if head(f[0]) == "lambda":          # ((lambda (x) ...) arg)
                self.lam(f[0], bound, atoms, calls)
                self.body(f[1:], bound, atoms, calls)
            else:
                self.body(f, bound, atoms, calls)
            return
        if h == "quote":
            for x in f[1:]:
                self.data(x, bound, atoms, calls)
            return
        if h == "function":
            for x in f[1:]:
                if is_sym(x):
                    self.fnref(x, atoms, calls)
                elif head(x) == "lambda":
                    self.lam(x, bound, atoms, calls)
                else:
                    self.expr(x, bound, atoms, calls)
            return
        if h == "lambda":
            self.lam(f, bound, atoms, calls)
            return
        if h == "defun":                        # a nested helper, *error*
            p, l = arglist(f)
            self.body(f[3:], bound | set(p) | set(l), atoms, calls)
            return
        if h == "setq":
            for k in range(1, len(f), 2):
                v = f[k]
                if is_sym(v) and v.lower() not in bound \
                        and v.lower() not in CONSTS:
                    atoms.add("global:" + str(v))
                    atoms.add("wglobal:" + str(v))
                if k + 1 < len(f):
                    self.expr(f[k + 1], bound, atoms, calls)
            return
        if h in ("foreach", "vlax-for"):
            if len(f) >= 3 and is_sym(f[1]):
                self.expr(f[2], bound, atoms, calls)
                self.body(f[3:], bound | {f[1].lower()}, atoms, calls)
            return
        if h == "cond":
            for cl in f[1:]:
                if isinstance(cl, list):
                    self.body(cl, bound, atoms, calls)
            return
        # an ordinary call
        self.fnref(h, atoms, calls)
        if h in IMPLICIT:
            always, (mn, mv, pn, pv) = IMPLICIT[h]
            for v in always:
                atoms.add("implicit:" + v)
            nargs = len(f) - 1
            if nargs < mn:
                atoms.add("implicit:" + mv)
            if nargs < pn:
                atoms.add("implicit:" + pv)
        if h in self.wrappers:
            for k in self.wrappers[h]:
                if k + 1 < len(f):
                    key = env_key(f[k + 1])
                    if key is not None:
                        atoms.add("env:" + key)
        if h in APPLIERS:
            # (mapcar 'helper ..), (vl-catch-all-apply 'command-s ..),
            # (vl-sort lst 'cmp): a quoted name here is a function
            for x in f[1:]:
                q = quoted(x)
                if is_sym(q):
                    self.fnref(q, atoms, calls)
                else:
                    self.expr(x, bound, atoms, calls)
            return
        self.body(f[1:], bound, atoms, calls)


def hand_ons(dmaps):
    """[(defun, [(callee, argument position, parameter index)])]: every
    place a defun hands one of its PARAMETERS straight to a call -- read
    once, and closed over by find_wrappers for each seed."""
    passes = []
    for dmap in dmaps:
        for name, forms in dmap.items():
            for d in forms:
                ps, _ = arglist(d)
                if not ps:
                    continue
                hand = []
                stack = list(d[3:])
                while stack:
                    f = stack.pop()
                    if not isinstance(f, list):
                        continue
                    h = head(f)
                    if h:
                        for k, a in enumerate(f[1:]):
                            if isinstance(a, Sym) and a.lower() in ps:
                                hand.append((h, k, ps.index(a.lower())))
                    stack.extend(f)
                if hand:
                    passes.append((name, hand))
    return passes


def find_wrappers(passes, seed=ENV_FNS):
    """name -> key argument positions, for every defun that hands one of
    its PARAMETERS to a SEED function (getenv & co. by default) or to
    another such defun -- found to a fixed point over hand_ons(), which
    is how cal:setting's key reads as a getenv, and spa:setv's first
    argument as a sysvar name."""
    out = {k: set(v) for k, v in seed.items()}
    changed = True
    while changed:
        changed = False
        for name, hand in passes:
            for callee, k, pi in hand:
                if callee in out and k in out[callee] \
                        and pi not in out.setdefault(name, set()):
                    out[name].add(pi)
                    changed = True
    return {k: tuple(sorted(v)) for k, v in out.items() if v}


class Scope:
    """The defuns one side can reach, as check_osnap.reach wants them:
    LAYERS are name -> [form] dicts, and the first that defines a name
    wins -- for the grouped side the twin, then the library, then a
    sibling's lisp/ file."""

    def __init__(self, reader, *layers):
        self.reader = reader
        self.layers = [l for l in layers if l]
        self.dmap = _Layered(self.layers)
        self.calls = _Calls(self)

    def forms_of(self, name):
        for l in self.layers:
            if name in l:
                return l[name]
        return []

    def atoms_calls(self, name):
        atoms, calls = set(), set()
        for d in self.forms_of(name):
            a, c = self.reader.of(d)
            atoms |= a
            calls |= c
        return atoms, calls

    def closure_atoms(self, names, own=frozenset()):
        """Atoms of NAMES and of every defun they reach in this scope;
        a namespaced call nothing here defines is an atom of its own."""
        out = set(own)
        for n in reach(names, self.dmap, self.calls):
            a, c = self.atoms_calls(n)
            out |= a
            out |= {"fn:" + x for x in c if ":" in x and x not in self.dmap}
        return out

    def footprint(self, name):
        return self.closure_atoms({name})

    def of_forms(self, forms):
        a, c = self.reader.forms(forms)
        return self.closure_atoms(c, a | {"fn:" + x for x in c
                                          if ":" in x and x not in self.dmap})


class _Layered:
    def __init__(self, layers):
        self.layers = layers

    def __contains__(self, name):
        return any(name in l for l in self.layers)


class _Calls:
    def __init__(self, scope):
        self.scope = scope
        self.memo = {}

    def __getitem__(self, name):
        if name not in self.memo:
            self.memo[name] = self.scope.atoms_calls(name)[1]
        return self.memo[name]


# ---------------------------------------------------------------------
#  Renames: what the mirror does to a name on the way to the twin
# ---------------------------------------------------------------------

class Names:
    """How one tool's atoms are compared across the two tiers.

    Only the mirror's own statements rename: the symbols map (which is
    how the chart forms' dropped font tables reach cal:*imgfont*), and
    the tool prefix against cal: for what is not a knob.  A table that
    merely has the same VALUE as a library one is not the same input --
    lzf:*col-hi* and cal:*imgcol-dim* are both a small number -- and a
    dropped table the symbols map forgets is P4's, not an alias."""

    def __init__(self, spec, prefixes, knob_names):
        self.symbols = dict(spec.get("symbols") or {})
        self.prefixes = prefixes
        self.knobs = knob_names

    def rename(self, name):
        """NAME through the symbols map, as the mirror's case-sensitive
        text substitution would see it."""
        return self.symbols.get(name, name)

    def norm(self, atom):
        kind, _, name = atom.partition(":")
        if kind == "sym":
            return "sym:" + self.rename(name).upper()
        if kind == "effect":
            return "effect:" + ("entmake" if name == "entmakex" else name)
        if kind in ("global", "wglobal"):
            # a knob is ITS tool's input -- judged before the rename, or
            # a knob the symbols map points at a library global would be
            # folded into the very name that replaced it
            if name.lower() in self.knobs:
                return kind + ":" + name.lower()
            n = self.rename(name).lower()
            if n in self.knobs:
                return kind + ":" + n
            m = re.match(r"^([a-z0-9]+):(.+)$", n)
            if m and (m.group(1) in self.prefixes or m.group(1) == "cal"):
                return kind + ":" + m.group(2)
            return kind + ":" + n
        if kind == "fn":
            n = self.rename(name).lower()
            m = re.match(r"^([a-z0-9]+):(.+)$", n)
            if m and (m.group(1) in self.prefixes or m.group(1) == "cal"):
                return "fn:" + m.group(2)
            return "fn:" + n
        return atom


# ---------------------------------------------------------------------
#  The tree
# ---------------------------------------------------------------------

@contextlib.contextmanager
def mirror_root(root):
    """mirror_shared.generate reads its sources under its own HERE; a
    fixture tree is read by pointing it there for the length of a run."""
    old = mirror_shared.HERE
    mirror_shared.HERE = str(root)
    try:
        yield
    finally:
        mirror_shared.HERE = old


class Tree:
    def __init__(self, root=ROOT, tools=None):
        self.root = pathlib.Path(root)
        self.tools = mirror_shared.TOOLS if tools is None else tools
        self.lib_path = self.root / "shared" / "parts" / "CALOFIN-LIB.lsp"
        self.lisp = {}                 # path -> forms
        for p in lsp_files(self.root / "lisp"):
            if not any(s in p.parts for s in SKIP_DIRS):
                self.lisp[p] = parse(read(p))
        self.lib = parse(read(self.lib_path))
        self.twin_text, self.twin_note = {}, {}
        with mirror_root(self.root):
            for tool, spec in sorted(self.tools.items()):
                try:
                    self.twin_text[tool] = mirror_shared.generate(tool, spec)[1]
                except SystemExit as e:
                    disk = self.root / "shared" / "parts" / (tool + ".lsp")
                    if disk.is_file():
                        self.twin_text[tool] = read(disk)
                    self.twin_note[tool] = str(e)
        self._said, self._twin = {}, {}
        self.lisp_defs = {p: defuns(f) for p, f in self.lisp.items()}
        self.lib_defs = defuns(self.lib)
        passes = hand_ons([self.lib_defs] + list(self.lisp_defs.values()))
        texts = [read(p) for p in self.lisp] + [read(self.lib_path)]
        sysvars = set(SEED_SYSVARS) | DIMVARS
        # a literal handed to getvar/setvar, or to a defun that passes
        # its first argument on to one -- (spa:setv "DIMTAD" 0)
        firsts = sorted(n for n, ks in find_wrappers(passes, SYSVAR_FNS).items()
                        if 0 in ks and n not in SYSVAR_FNS)
        rx = [SYSVAR_RE]
        if firsts:
            rx.append(re.compile(r'\((?:%s)\s+"([A-Za-z_][A-Za-z0-9_]*)"'
                                 % "|".join(map(re.escape, firsts)), re.I))
        for text in texts:
            for r in rx:
                sysvars |= {m.upper() for m in r.findall(text)}
        fns = set(self.lib_defs)
        for d in self.lisp_defs.values():
            fns |= set(d)
        wrappers = find_wrappers(passes)
        self.reader = Reader(sysvars, fns, wrappers)
        # every lisp/ defun, for an expand that calls a SIBLING's helper
        # (TUTORIALSPA's (spa:sysvars) lives in SPA.LSP); the twin carries
        # it verbatim, less the swaps
        self.lisp_all = {}
        for p in sorted(self.lisp_defs):
            for n, fs in self.lisp_defs[p].items():
                self.lisp_all.setdefault(n, fs)
        self.lib_scope = Scope(self.reader, self.lib_defs)
        # the hand-kept twins (LISPLAB): read off disk, and given the
        # swap map their missing helpers imply, so P1/P2/P4 see them too
        self.hand = {}                 # tool -> derived spec
        self.hand_path = {}            # tool -> shared/parts path
        for p in lsp_files(self.root / "shared" / "parts"):
            if p.stem in self.tools or p.name.upper().startswith("CALOFIN-"):
                continue
            self.hand_path[p.stem] = p
            self.twin_text[p.stem] = read(p)
            src = self.hand_src(p)
            if src is None:
                continue
            twin = self.twin_defs(p.stem)
            swap = {n: "cal:" + n.split(":", 1)[1]
                    for n in sorted(self.lisp_defs[src])
                    if n not in twin and ":" in n and not n.startswith("c:")
                    and "cal:" + n.split(":", 1)[1] in self.lib_defs}
            self.hand[p.stem] = {"src": self.rel(src), "swap": swap,
                                 "drop_globals": [], "hand": True}
        #: every spec a rule reads: the mirror's table, then the hand twins
        self.specs = dict(self.tools)
        self.specs.update(self.hand)

    def hand_src(self, part):
        """The lisp/ file a hand twin at PART is kept by hand from."""
        hits = sorted(p for p in self.lisp if p.stem.lower() == part.stem.lower())
        return hits[0] if hits else None

    def rewrites_calls(self, tool):
        """Can the twin's calls differ from lisp/'s by more than a name?
        Only an expand, a collapse, a rewrite, or a swap onto a helper
        of another arity can make one -- so only those twins are read
        as code (P3 and the grouped scope); the rest are the lisp/
        forms renamed."""
        spec = self.specs.get(tool)
        if spec is None or spec.get("hand") or spec.get("expand") \
                or spec.get("collapse") or spec.get("rewrite"):
            # a hand twin is read whole, with its lisp/ file or without
            return True
        swap = {k.lower() for k in spec.get("swap") or {}}
        for old, new in (spec.get("symbols") or {}).items():
            # a symbols rename onto a library FUNCTION is a swap in all
            # but name, and nothing here pairs the two argument lists
            if new.lower() in self.lib_defs and old.lower() not in swap:
                return True
        src = self.root / spec["src"]
        for local, cal in (spec.get("swap") or {}).items():
            local, cal = local.lower(), cal.lower()
            home = src if local in self.lisp_defs.get(src, {}) \
                else self.definer(local, src)
            if home is None or cal not in self.lib_defs:
                continue
            if len(arglist(self.lisp_defs[home][local][0])[0]) != \
                    len(arglist(self.lib_defs[cal][0])[0]):
                return True
        return False

    def twin_defs(self, tool):
        """defuns() of the twin as the mirror writes it now."""
        if tool not in self._twin:
            forms = parse(self.twin_text[tool]) if tool in self.twin_text \
                else []
            self._twin[tool] = (forms, defuns(forms))
        return self._twin[tool][1]

    def twin_forms(self, tool):
        self.twin_defs(tool)
        return self._twin[tool][0]

    def twin_said(self, tool):
        """mentions() of the twin as the mirror writes it now."""
        if tool not in self._said:
            self._said[tool] = mentions(self.twin_text[tool])
        return self._said[tool]

    def rel(self, p):
        try:
            return str(pathlib.Path(p).relative_to(self.root))
        except ValueError:
            return str(p)

    def definer(self, name, near):
        """The lisp/ file that defines NAME, the one beside NEAR first --
        a satellite's swapped helper lives in its sibling."""
        hits = [p for p, d in self.lisp_defs.items() if name in d]
        if not hits:
            return None
        same = [p for p in hits if p.parent == near.parent]
        return sorted(same or hits)[0]


# ---------------------------------------------------------------------
#  P1: the footprints
# ---------------------------------------------------------------------

class UF:
    def __init__(self):
        self.p = {}

    def find(self, a):
        self.p.setdefault(a, a)
        while self.p[a] != a:
            self.p[a] = self.p[self.p[a]]
            a = self.p[a]
        return a

    def union(self, a, b):
        self.p[self.find(a)] = self.find(b)


def quoted_outside(forms, skip):
    """Every symbol QUOTED in FORMS outside the defuns named in SKIP --
    the sentinels the surviving code tests for."""
    out = set()
    stack = [(f, False) for f in forms]
    while stack:
        x, q = stack.pop()
        if isinstance(x, list):
            if head(x) == "defun" and len(x) > 1 and is_sym(x[1]) \
                    and x[1].lower() in skip:
                continue
            if head(x) == "quote":
                stack.extend((y, True) for y in x[1:])
            else:
                stack.extend((y, q) for y in x)
        elif is_sym(x) and q:
            out.add(str(x))
    return out


@functools.lru_cache(maxsize=None)
def tool_knobs(path):
    """The tool's LAZTUNE knobs, lower-cased: its tunables block less
    the run-time state knobs.py refuses to offer."""
    try:
        return frozenset(k[0].lower() for k in knobs.knobs_of(path)
                         if not knobs.is_state(k[0]))
    except OSError:
        return frozenset()


def knobs_for(tree, spec, src):
    """The knobs a tool's swapped helpers may read: its own, and a
    sibling's where a satellite swaps a helper that lives in the sibling
    -- TUTORIALSPA's spa:syssave reads SPA's spa:*dimvars*, and folding
    that onto a library name would hide a knob the library never reads."""
    out = set(tool_knobs(src))
    own = tree.lisp_defs.get(src, {})
    for local in list(spec.get("swap") or {}) + \
            list(spec.get("collapse") or {}) + list(spec.get("rewrite") or {}):
        local = local.lower()
        if local not in own:
            home = tree.definer(local, src)
            if home is not None:
                out |= tool_knobs(home)
    return out


def pairs_of(tree, tool, spec):
    """[(local, file, line, standalone atoms, grouped atoms, label)]."""
    src = tree.root / spec["src"]
    if src not in tree.lisp_defs:
        return [], None
    own = tree.lisp_defs[src]
    own_scope = Scope(tree.reader, own)
    if spec.get("expand") or spec.get("collapse") or spec.get("rewrite"):
        # what the mirror ADDS is resolved as the grouped build would:
        # the twin first, then the library, then a sibling's helper
        twin = tree.twin_defs(tool)
        grp = Scope(tree.reader, twin, tree.lib_defs, tree.lisp_all)
    else:
        twin, grp = {}, None
    out = []

    def local_side(name):
        if name in own:
            return src, own[name][0].line, own_scope.footprint(name)
        home = tree.definer(name, src)
        if home is None:
            return None
        return (home, tree.lisp_defs[home][name][0].line,
                Scope(tree.reader, tree.lisp_defs[home]).footprint(name))

    swap = {k.lower(): v.lower() for k, v in (spec.get("swap") or {}).items()}
    for local, cal in sorted(swap.items()):
        side = local_side(local)
        if side is None or cal not in tree.lib_defs:
            continue
        extra = set()
        for key, repl in (spec.get("expand") or {}).items():
            kl = key.lower()
            if kl.startswith("(" + cal + " ") or kl.startswith("(" + cal + ")"):
                # only what the rule ADDS: the call-site arguments it
                # matched are on both sides already
                extra |= (grp.of_forms(parse("\n".join(repl)))
                          - grp.of_forms(parse(key)))
        out.append((local, side[0], side[1], side[2],
                    tree.lib_scope.footprint(cal) | extra,
                    "%s -> %s" % (local, cal)))
    for local, (cal, xtra) in sorted((spec.get("collapse") or {}).items()):
        local, cal = local.lower(), cal.lower()
        if local not in own or cal not in tree.lib_defs:
            continue
        out.append((local, src, own[local][0].line, own_scope.footprint(local),
                    tree.lib_scope.footprint(cal) | grp.of_forms(parse(xtra)),
                    "%s -> (%s .. %s)" % (local, cal, xtra)))
    for local in sorted(spec.get("rewrite") or {}):
        local = local.lower()
        if local not in own or local not in twin:
            continue
        out.append((local, src, own[local][0].line, own_scope.footprint(local),
                    grp.footprint(local), "%s rewritten" % local))
    return out, src


def names_for(tree, spec, src):
    """The Names a tool's atoms are compared under."""
    own = tree.lisp_defs[src]
    prefixes = {k.split(":")[0].lower()
                for k in list(spec.get("swap") or {}) + list(own)
                if ":" in k and not k.lower().startswith("c:")}
    return Names(spec, prefixes, knobs_for(tree, spec, src))


def compare(tree):
    """[finding dict] for P1, and the number of groups compared."""
    rows, ngroups = [], 0
    for tool, spec in sorted(tree.specs.items()):
        pairs, src = pairs_of(tree, tool, spec)
        if not pairs:
            continue
        names = names_for(tree, spec, src)
        dropped = {k.lower() for k in (spec.get("swap") or {})} | \
                  {k.lower() for k in (spec.get("collapse") or {})}
        live = {names.rename(s).upper()
                for s in quoted_outside(tree.lisp[src], dropped)}

        # pairs that share STATE -- a global some side writes, *sysold* --
        # are one mechanism: what the save puts in, the restore takes out
        n = [({names.norm(a) for a in l}, {names.norm(a) for a in g})
             for _, _, _, l, g, _ in pairs]
        uf, owner = UF(), {}
        for i, (l, g) in enumerate(n):
            uf.find(i)
            for a in l | g:
                if a.startswith("wglobal:"):
                    w = a[1:]
                    if w in owner:
                        uf.union(i, owner[w])
                    owner.setdefault(w, i)
        for i, (l, g) in enumerate(n):
            for a in l | g:
                if a in owner:
                    uf.union(i, owner[a])
        groups = {}
        for i in range(len(pairs)):
            groups.setdefault(uf.find(i), []).append(i)
        for idxs in groups.values():
            ngroups += 1
            state = {a[1:] for i in idxs for a in n[i][0] | n[i][1]
                     if a.startswith("wglobal:")}
            ln = {a for i in idxs for a in n[i][0]
                  if not a.startswith("wglobal:")} - state
            gn = {a for i in idxs for a in n[i][1]
                  if not a.startswith("wglobal:")} - state
            diffs = []
            for a in sorted(ln - gn):
                diffs.append(("standalone-only", a,
                              [i for i in idxs if a in n[i][0]]))
            for a in sorted(gn - ln):
                diffs.append(("grouped-only", a,
                              [i for i in idxs if a in n[i][1]]))
            # the state itself, pair by pair: a restore that stops
            # reading the saved style is drift even while the save
            # beside it still writes it
            for i in idxs:
                pl, pg = n[i][0] & state, n[i][1] & state
                diffs += [("standalone-only", a, [i]) for a in sorted(pl - pg)]
                diffs += [("grouped-only", a, [i]) for a in sorted(pg - pl)]
            for side, a, where in diffs:
                if a.startswith("sym:") and a[4:] not in live:
                    continue              # a sentinel nobody tests for
                i = where[0]
                local, path, line, _, _, label = pairs[i]
                rows.append({
                    "rule": "P1", "tool": tool, "src": spec["src"],
                    "file": tree.rel(path), "line": line, "subject": local,
                    "what": "%s %s" % (side, a),
                    "label": " + ".join(pairs[j][5] for j in idxs),
                })
    return rows, ngroups


# ---------------------------------------------------------------------
#  P2: knob mentions.  P3: cal: arity.
# ---------------------------------------------------------------------

TOKEN = re.compile(r"[^\s()'\";]+")
STRING = re.compile(r'"(?:\\.|[^"\\])*"?', re.S)


def mentions(text):
    """name -> how often TEXT's code (not its comments or strings) says it."""
    return collections.Counter(
        w.lower() for w in TOKEN.findall(STRING.sub('""', decomment(text))))


def setq_line(text, name):
    """The line TEXT sets NAME on at the top level, or 0."""
    m = re.search(r"^\(setq\s+" + re.escape(name) + r"(?=[\s)])", text,
                  re.M | re.I)
    return text.count("\n", 0, m.start()) + 1 if m else 0


def knob_counts(tree):
    rows = []
    for tool, spec in sorted(tree.specs.items()):
        src = tree.root / spec["src"]
        if tool not in tree.twin_text or not src.is_file():
            continue
        # a knob the mirror drops or renames is P4's, and never read at
        # all: counting its mentions as well would say it twice
        declared = {g.lower() for g in spec.get("drop_globals") or []} | \
                   {g.lower() for g in spec.get("symbols") or {}}
        names = sorted(knobs_for(tree, spec, src) - declared)
        if not names:
            continue
        a, b = mentions(read(src)), tree.twin_said(tool)
        for k in names:
            if b.get(k, 0) < a.get(k, 0):
                rows.append({
                    "rule": "P2", "tool": tool, "src": spec["src"],
                    "file": tree.rel(src),
                    "line": setq_line(read(src), k), "subject": k,
                    "what": "knob mentioned less often in the twin",
                    "label": "lisp/ %d, twin %d" % (a.get(k, 0), b.get(k, 0)),
                })
    return rows


def without_inits(text, names):
    """TEXT less each top-level (setq NAME ...) of NAMES -- the load-time
    initialisation a twin keeps of a slot it no longer uses is inert."""
    for n in names:
        while True:
            span = mirror_shared.top_span(text, "setq", n)
            if span is None:
                break
            text = text[:span[0]] + text[span[1]:]
    return text


def orphans(tree):
    """P4: a name the grouped build reads and nothing in it sets, or one
    it sets and nothing in it reads.

    The mirror drops a table (drop_globals) because the library carries
    it, swaps away the helpers that kept a slot (tool:*sysold*) because
    the library keeps its own, and renames what pointed at either
    (symbols).  A twin whose surviving code still names the old slot --
    a reset at the top of a run, a test in the handler -- touches a
    global nothing in the grouped build writes; a rename onto a cal:
    name the library never mentions points at nothing; and a KNOB the
    mirror drops or renames is one LAZTUNE still offers (gen_knobs reads
    lisp/) while nothing in the grouped build reads what it writes."""
    lib_said = mentions(read(tree.lib_path))
    rows = []
    for tool, spec in sorted(tree.specs.items()):
        if tool not in tree.twin_text:
            continue
        src = tree.root / spec["src"]
        text = read(src) if src.is_file() else ""

        def row(subject, what, label=""):
            rows.append({"rule": "P4", "tool": tool, "src": spec["src"],
                         "file": spec["src"], "line": setq_line(text, subject),
                         "subject": subject, "what": what, "label": label})

        renamed = set(spec.get("symbols") or {})
        own_knobs = tool_knobs(src) if src.is_file() else frozenset()
        for g in sorted(set(spec.get("drop_globals") or []) | renamed):
            if g.lower() in own_knobs:
                row(g, "a LAZTUNE knob the mirror %s: the grouped build "
                       "never reads the drafter's value"
                    % ("renames to %s" % spec["symbols"][g] if g in renamed
                       else "drops"))
        slots = {g.lower(): "dropped by the mirror"
                 for g in spec.get("drop_globals") or []}
        own = tree.lisp_defs.get(src, {})
        for local in list(spec.get("swap") or {}) + \
                list(spec.get("collapse") or {}):
            for d in own.get(local.lower(), []):
                for a in tree.reader.of(d)[0]:
                    if a.startswith("wglobal:") and a[8:] not in renamed:
                        slots.setdefault(a[8:].lower(),
                                         "kept by %s, which the mirror swaps "
                                         "away" % local.lower())
        if slots:
            said = mentions(without_inits(tree.twin_text[tool], sorted(slots)))
            for g, why in sorted(slots.items()):
                if said.get(g):
                    row(g, "%s but still named in the twin" % why,
                        "%d mention(s)" % said[g])
        for old, new in sorted((spec.get("symbols") or {}).items()):
            if new.lower().startswith("cal:") and not lib_said.get(new.lower()):
                row(old, "renamed to %s, which CALOFIN-LIB never names" % new)
    return rows


def _lambdas(data):
    """Every (lambda ...) list inside quoted DATA -- '(lambda (p) ..) is
    code however it is spelled."""
    out, stack = [], list(data)
    while stack:
        x = stack.pop()
        if isinstance(x, list):
            if head(x) == "lambda":
                out.append(x)
            else:
                stack.extend(x)
    return out


def evaluated_calls(forms):
    """Every call form in FORMS outside a quote -- '(cal:x 1) is data,
    but the body of a quoted '(lambda ...) is code, and is walked."""
    stack = list(forms)
    while stack:
        f = stack.pop()
        if not isinstance(f, list):
            continue
        if head(f) == "quote":
            stack.extend(_lambdas(f[1:]))
            continue
        yield f
        stack.extend(f)


def cal_arity(tree):
    want = {}
    for n, ds in tree.lib_defs.items():
        if n.startswith("cal:"):
            want[n] = len(arglist(ds[0])[0])
    rows = []
    for tool in sorted(tree.twin_text):
        if not tree.rewrites_calls(tool):
            continue
        seen = set()
        for f in evaluated_calls(tree.twin_forms(tool)):
            h = head(f)
            if h in want and len(f) - 1 != want[h]:
                key = (h, len(f) - 1, f.line)
                if key in seen:
                    continue
                seen.add(key)
                rows.append({
                    "rule": "P3", "tool": tool,
                    "src": tree.specs[tool]["src"] if tool in tree.specs
                    else "shared/parts/%s.lsp" % tool,
                    "file": "shared/parts/%s.lsp" % tool, "line": f.line,
                    "subject": h,
                    "what": "given %d argument%s, takes %d"
                            % (len(f) - 1, "" if len(f) == 2 else "s", want[h]),
                    "label": "",
                })
    return rows


# ---------------------------------------------------------------------
#  P5: a hand-kept twin, token for token
# ---------------------------------------------------------------------

CODE_TOKEN = re.compile(r'"(?:\\.|[^"\\])*"?|[()\']|[^\s()\'";]+', re.S)


def code_tokens(text):
    """[(token, line, enclosing defun)] of TEXT's code: comments gone,
    every string one '""' token (a hand twin's prose may differ), names
    lower-cased."""
    t = decomment(text)
    out, line, pos = [], 1, 0
    stack = []                         # [(depth, defun name)]
    depth, prev = 0, None
    toks = [(m.group(), m.start()) for m in CODE_TOKEN.finditer(t)]
    for k, (w, at) in enumerate(toks):
        line += t.count("\n", pos, at)
        pos = at
        if w.startswith('"'):
            w = '""'
        else:
            w = w.lower()
        if w == "(":
            depth += 1
        elif w == ")":
            depth -= 1
            while stack and stack[-1][0] > depth:
                stack.pop()
        elif w == "defun" and prev == "(" and k + 1 < len(toks):
            stack.append((depth, toks[k + 1][0].lower()))
        out.append((w, line, stack[-1][1] if stack else "top level"))
        prev = w
    return out


def _whole(seq, i1, i2):
    """Where a pure insertion or deletion SEQ[i1:i2] reads as whole
    forms: the same hunk slid left or right over tokens equal to its own
    ends (a diff's usual freedom), at the first offset where it opens
    with "(" and balances.  Returns the new start; i1 when none does."""
    n = i2 - i1
    lo = i1
    while lo > 0 and seq[lo - 1][0] == seq[lo - 1 + n][0]:
        lo -= 1
    hi = i1
    while hi + n < len(seq) and seq[hi][0] == seq[hi + n][0]:
        hi += 1
    for s in range(lo, hi + 1):
        depth, ok = 0, seq[s][0] == "("
        for w, _, _ in seq[s:s + n]:
            depth += (w == "(") - (w == ")")
            if depth < 0:
                ok = False
                break
        if ok and depth == 0:
            return s
    return i1


def hand_diff(tree):
    """P5 over every hand twin with a lisp/ source."""
    rows = []
    for tool, spec in sorted(tree.hand.items()):
        src = tree.root / spec["src"]
        text = read(src)
        for local in spec["swap"]:
            span = mirror_shared.top_span(text, "defun", local)
            if span is not None:
                # blank, not cut: the lines stay where the file has them
                text = text[:span[0]] + re.sub(r"[^\n]", " ",
                                               text[span[0]:span[1]]) \
                    + text[span[1]:]
        a = [(spec["swap"].get(w, w), ln, d) for w, ln, d in code_tokens(text)]
        b = code_tokens(tree.twin_text[tool])
        sm = difflib.SequenceMatcher(None, [w for w, _, _ in a],
                                     [w for w, _, _ in b], autojunk=False)
        for op, i1, i2, j1, j2 in sm.get_opcodes():
            if op == "equal":
                continue
            # a hunk the matcher could have placed a few tokens either
            # way is placed where it is whole forms: "(if lzd:end ...)"
            # rather than "if lzd:end ...) ("
            if op == "delete":
                d = _whole(a, i1, i2) - i1
                i1, i2, j1, j2 = i1 + d, i2 + d, j1 + d, j2 + d
            elif op == "insert":
                d = _whole(b, j1, j2) - j1
                i1, i2, j1, j2 = i1 + d, i2 + d, j1 + d, j2 + d
            lhs = " ".join(w for w, _, _ in a[i1:i2])
            rhs = " ".join(w for w, _, _ in b[j1:j2])
            at = a[i1] if i1 < len(a) else a[-1]
            what = ("standalone-only code: %s" % lhs if op == "delete" else
                    "grouped-only code: %s" % rhs if op == "insert" else
                    "code differs: %s | twin: %s" % (lhs, rhs))
            rows.append({
                "rule": "P5", "tool": tool, "src": spec["src"],
                "file": spec["src"], "line": at[1],
                "subject": (b[j1][2] if op == "insert" and j1 < len(b)
                            else at[2]),
                "what": what if len(what) <= 110 else what[:107] + "...",
                "label": "shared/parts/%s:%d" % (
                    tree.hand_path[tool].name,
                    b[j1][1] if j1 < len(b) else b[-1][1])})
    return rows


# ---------------------------------------------------------------------
#  Baseline and report
# ---------------------------------------------------------------------

class BaselineError(ValueError):
    """A line of the baseline that is not file|subject|what|reason."""


def load_baseline(path=BASELINE):
    """(tool's src, subject, what) -> reason, for every accepted
    difference.  A line without all four fields, or with no reason, is
    an error: a site accepted without saying why is the rot the file
    exists to prevent."""
    out = {}
    path = pathlib.Path(path)
    if not path.is_file():
        return out
    for n, ln in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        parts = [x.strip() for x in ln.split("|", 3)]
        if len(parts) != 4 or not all(parts):
            raise BaselineError(
                "%s:%d: not file|subject|what|reason, or no reason given: %s"
                % (path.name, n, ln.strip()))
        out[tuple(parts[:3])] = parts[3]
    return out


def key_of(r):
    """The baseline key of a finding: the TOOL's source file, so two
    tools driving one sibling helper are two keys."""
    return (r["src"], r["subject"], r["what"])


#: per atom kind: what the difference means, and the usual way out
EXPLAIN = {
    "global": ("a free variable -- a knob or state -- only one build reads: "
               "a drafter's LAZTUNE value reaches one build and not the other",
               "keep the helper local (drop the swap), or collapse it onto a "
               "library helper that takes the knob as an argument"),
    "env": ("a profile/registry key only one build reads: a CALSET setting "
            "that works in one build and not the other",
            "give the local copy the same read -- the library's body is the "
            "one to copy"),
    "sysvar": ("a sysvar only one build names -- a snapshot table, a getvar "
               "-- so one build saves, restores or reads what the other does "
               "not",
               "make the mirror's hand-typed expand list match the local "
               "helper's (better: expand to (tool:sysvars) so it is typed "
               "once)"),
    "implicit": ("a sysvar a builtin (rtos/angtos) reads unasked in one build "
                 "only: the two print the same value differently",
                 "give the local copy the library's body, or stop swapping it"),
    "sym": ("a sentinel only one build hands back while the tool's own code "
            "tests for it",
            "add the rename to the tool's 'symbols' map in mirror_shared.py"),
    "effect": ("an effect on the drawing or the session only one build makes",
               "make the two bodies do the same thing, or keep the helper "
               "local"),
    "fn": ("a function only one build calls -- a LAZDIAG hook, another "
           "tool's helper",
           "make the two bodies call the same thing, or keep the helper "
           "local"),
}

FIX = {
    "P0": "fix the mirror table so mirror_shared.py writes the twin",
    "P2": "a transform dropped a use of the knob: pass it through a "
          "collapse/expand or keep the helper that reads it local",
    "P3": "fix the expand/collapse that built the call, or the swap whose "
          "local helper took a different argument list",
    "P4": "add the name to the tool's symbols map (the library's name for "
          "the same slot), or stop dropping it; a KNOB is never dropped or "
          "renamed -- keep the helper that reads it local, or collapse it "
          "onto one that takes the knob",
    "P5": "make the hand twin's code match its lisp/ file (the LAZDIAG "
          "hooks check_lazdiag --fix writes into lisp/ are not carried "
          "into a hand twin by anything); only string prose may differ",
}


def audit(root=ROOT, tools=None):
    """(findings, groups compared) over the tree at ROOT."""
    tree = Tree(root, tools)
    rows, ngroups = compare(tree)
    rows += knob_counts(tree)
    rows += cal_arity(tree)
    rows += orphans(tree)
    rows += hand_diff(tree)
    for tool, note in sorted(tree.twin_note.items()):
        src = tree.tools[tool]["src"]
        rows.append({"rule": "P0", "tool": tool, "src": src, "file": src,
                     "line": 0, "subject": tool,
                     "what": "the mirror refused to generate the twin",
                     "label": note})
    return rows, ngroups, tree


def report(rows, base, show_all=False, out=print):
    """Print the findings; (new, stale, accepted) counts.  A P1/P2 row
    in BASE is accepted; P0, P3, P4 and P5 never are."""
    new, old = [], []
    produced = set()
    for r in rows:
        key = key_of(r)
        produced.add(key)
        if r["rule"] in ("P1", "P2") and key in base:
            old.append((r, base[key]))
        else:
            new.append(r)
    for r in new:
        kind = r["what"].split()[-1].partition(":")[0] if r["rule"] == "P1" \
            else ""
        out("%s:%d: %s %s %s: %s%s" % (
            r["file"], r["line"], r["rule"], r["tool"], r["subject"],
            r["what"], ("  [%s]" % r["label"]) if r["label"] else ""))
        if kind in EXPLAIN:
            out("    %s" % EXPLAIN[kind][0])
            out("    fix: %s; then bash .claude/skills/calofin-lisp/scripts/"
                "retier.sh %s" % (EXPLAIN[kind][1], r["tool"]))
        elif r["rule"] in FIX:
            out("    fix: %s" % FIX[r["rule"]])
        if r["rule"] in ("P1", "P2"):
            out("    only if it is genuinely harmless, baseline it with a "
                "reason: %s|<reason>" % "|".join(key_of(r)))
    if show_all:
        for r, why in old:
            out("%s:%d: %s %s %s: %s  (baselined: %s)" % (
                r["file"], r["line"], r["rule"], r["tool"], r["subject"],
                r["what"], why))
    stale = sorted(k for k in base if k not in produced)
    for f, s, w in stale:
        out("%s: %s: %s -- baselined, but the tree no longer produces it; "
            "drop the line from tools/tier_parity_baseline.txt" % (f, s, w))
    return len(new), len(stale), len(old)


def show(tree, tool):
    """Both footprints of every pair of TOOL, as they are compared --
    after the renames, the state marked, one column per side."""
    spec = tree.specs[tool]
    pairs, src = pairs_of(tree, tool, spec)
    if not pairs:
        print("%s: nothing swapped, collapsed or rewritten" % tool)
        return
    names = names_for(tree, spec, src)
    for local, path, line, l, g, label in pairs:
        print("%s:%d  %s" % (tree.rel(path), line, label))
        ln = {names.norm(a) for a in l}
        gn = {names.norm(a) for a in g}
        state = {a[1:] for a in ln | gn if a.startswith("wglobal:")}
        for a in sorted((ln | gn) - {a for a in ln | gn
                                     if a.startswith("wglobal:")}):
            side = "both      " if a in ln and a in gn else (
                "standalone" if a in ln else "grouped   ")
            print("    %s  %s%s" % (side, a, "  (state)" if a in state else ""))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--all", action="store_true",
                    help="also print the baselined differences and why")
    ap.add_argument("--list", metavar="TOOL",
                    help="print both footprints of every pair of one tool")
    a = ap.parse_args(argv)
    if a.list:
        tree = Tree()
        if a.list not in tree.specs:
            print("unknown tool %r" % a.list, file=sys.stderr)
            return 2
        show(tree, a.list)
        return 0
    try:
        base = load_baseline()
    except BaselineError as e:
        print("check_tier_parity: %s" % e)
        return 1
    rows, ngroups, tree = audit()
    nnew, nstale, nold = report(rows, base, a.all)
    if nnew or nstale:
        print("check_tier_parity: %d difference(s) between the tiers, %d "
              "stale baseline line(s) -- %d swap group(s) compared over %d "
              "tool(s)" % (nnew, nstale, ngroups, len(tree.specs)))
        return 1
    print("check_tier_parity: %d swap group(s) over %d tool(s) read the "
          "same knobs, keys and sysvars in both builds; every twin's cal: "
          "calls take the library's arity, and every hand twin matches its "
          "lisp/ file but for its swaps%s"
          % (ngroups, len(tree.specs),
             (" (%d baselined)" % nold) if nold else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
