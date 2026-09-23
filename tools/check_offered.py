#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every answer a prompt hands back without the drafter typing it is one
the prompt itself offers.

A getkword can only ever RETURN a keyword of its initget list, spelt the
way the list spells it -- that is the whole of what the list guarantees.
Everything a prompt hands back WITHOUT a keystroke is the code's own
choice, and nothing in AutoCAD checks it: the Enter answer shown in
<...>, the remembered answer a second run offers, a LAZTUNE knob
(applied after the load, re-applied before every panel launch, and
checked for its KIND only), a form's stored answer standing in for the
question.  Code below the prompt then compares with (= v "Kw") or
(member v '(...)) exactly as spelt, so an unoffered default is taken by
no branch -- quietly.  ABHD's "Keep which fit" erased every fit that
way, POINTRENAMER numbered a survey clockwise under <Counterclockwise>,
MOHAMADDLE died on arithmetic with nil and saved the bad default first.

Rules, one tag each.  Every finding fails unless it is in
tools/offered_baseline.txt with a reason (check_back's pattern: a new
site fails, a baselined one that has gone is reported stale):

  E   Enter's answer at a keyword prompt -- the one shown in <...> and
      whatever the Enter branch substitutes: (if v v X), (cond ((null v)
      X)), ((and (null v) dflt) (setq out dflt)), the (T X) a (cond (v
      ...)) falls to, (if dflt dflt (re-ask)) -- traced back through
      locals (the last assignment that can reach the prompt, an (if C a
      b) read against the arm of (if C ...) the prompt sits in), helper
      parameters (to every caller in the tier, the grouped tier's cal:
      library included), (nth k (list ...)) and helper return values:
        * a string literal must be a keyword as the initget spells it;
        * a LAZTUNE knob must be canonicalised on the way -- a lookup
          ((vl-some '(lambda (s) (if TEST s)) TABLE), whose entries are
          traced when the table is spelt out), a *canon* / *fkword*
          helper, or a member / assoc test that REPLACES it on the side
          the test calls bad.  A (member X ...) that only picks a branch
          further down does NOT count, nor does one that replaces X when
          it IS a member, nor a load-time check at top level: LAZTUNE
          writes after the load;
        * a global that is not a knob passes when nothing assigns it
          from getenv / the registry / a file.
      What cannot be traced is advisory (--all), never fatal.
  N   the same trace at a NUMBER prompt that refuses zero or negatives:
      its initget's bit 2 / 4 -- read one value per path, so (+ (if
      dflt 6 7) 128) is 134 or 135, Enter allowed -- or the code's own
      refusal of a typed value that hands the default back instead,
      (if (or (not n) (< n 1)) (setq n knob)).  A knob needs a LOWER
      bound on the way (LAZTUNE checks a knob's kind, never its range):
      (if (> x 0) x 6.0), (if (not (> x 0)) (setq x 6.0)), (max 0.5 x)
      vet it; an upper-only clamp, (if (> x 100) (setq x 100)) or (min
      100 x), does not.  A clamp on what is TYPED -- (cond ((null v)
      dflt) ((> v 100) 1.0) ...) -- does not vet what Enter hands back.
      And what <...> SHOWS must be vetted before the prompt: a knob
      clamped only on the Enter branch shows <1500> and takes 1.0.  An
      Enter branch that KEEPS the value -- ((null v) (setq step 5)) --
      is traced through what the prompt shows; one that HANDS a value
      over -- (setq out dflt) -- through that value.  A literal handed
      back on Enter must be one the initget would take.
  T1  a bit-128 prompt's typed answer compared with a literal word --
      (= v "Whole"), (member v '("Back" "Undo")) -- that the live prompt
      does not offer: never (not in its keyword list nor its bracket),
      or only under a condition the compare is not made under, with a
      caller that can call it without offering the word and never tests
      the sentinel the word comes back as.
  T2  a bit-128 pick or number answer used as a point or a number --
      (car v), (distance v ..), (+ v ..) -- where a typed word can still
      be: it ends the command in a Lisp error.
  S   a form or replay answer standing in for a prompt -- the arm of
      (setq V (if C take ask)) that does not ask -- taken raw from an
      answer store (*ftake* / *fget* / *fpull*) with nothing vetting it.
  I   a prompt re-asked inside a loop whose initget sits outside that
      loop: an initget is spent by the next input call, so from the
      second pass on the bracket shows keywords AutoCAD refuses.

Not here, on purpose: a spaced example ("44 1/2", "1524 MM") shown at a
spacebar-is-Enter prompt is check_input's SPACE rule; the VM half of
this guard (an initget spent per input call, <D> an exact keyword, the
knob mutation sweep) belongs to tests/lispvm.py and a test of its own.

The reader is check_handlers' (it keeps line numbers, string bodies and
quote); which defuns reach a prompt is check_osnap's call graph
(callees), closed backwards.  A tier is read as ONE program -- neither
tier has two top-level defuns of one name -- so a helper's callers in
any file are in view, and in the grouped tier a part's knob is followed
into CALOFIN-LIB's ask helpers and reported in the part, where it
enters.  The knobs are what tools/knobs.py reads off each file's
tunables block (what LAZTUNE offers), so a made file with a block is
checked the way a tool is.

    python3 tools/check_offered.py                 # all three tiers
    python3 tools/check_offered.py --tier shared   # one of them
    python3 tools/check_offered.py --all           # + advisories, baselined

The default reads lisp/, shared/parts/ AND releases/, as check_handlers
and check_osnap do: a dated twin is what a shop pins to, and it only
takes a fix when release_lisp.py is re-run.  A baseline line is keyed
by the defun's lisp/ home, so one line holds a site in every tier, and
only the default run -- every tier read -- can call a line stale.

Exit 0 when every finding is baselined and no baseline line is stale.
"""

import argparse
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_osnap as co  # noqa: E402  (callees: the call graph)
import knobs as knobsmod  # noqa: E402  (the tunables-block reader)
from callib import (DATED, DEFUN, LISP_DIR, PARTS_DIR,  # noqa: E402
                    RELEASES_DIR, ROOT, decomment, lsp_files, read)
from check_handlers import Str, Sym, read_forms  # noqa: E402

BASELINE = HERE / "offered_baseline.txt"
SKIP_DIRS = ("standards_checker",)


# ---------------------------------------------------------------------
#  forms
# ---------------------------------------------------------------------

_FORMS = {}


def forms_of(path):
    """PATH read with check_handlers' reader, memoised by TEXT -- a
    releases/ twin is its lisp/ file until the next banner bump."""
    text = read(path)
    f = _FORMS.get(text)
    if f is None:
        f = _FORMS[text] = read_forms(decomment(text))
    return f


def hd(f):
    return (f[0].lower() if isinstance(f, list) and f
            and isinstance(f[0], Sym) else None)


def unq(x):
    """(quote X) -> X; anything else as it is."""
    return x[1] if hd(x) == "quote" and len(x) == 2 else x


def is_sym(x, name=None):
    return isinstance(x, Sym) and (name is None or x.lower() == name)


NUM = re.compile(r"^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$")


def is_num(x):
    return isinstance(x, Sym) and bool(NUM.match(x))


def walk(f):
    yield f
    if isinstance(f, list):
        for x in f:
            if isinstance(x, list):
                yield from walk(x)


def line_of(x, default=0):
    return getattr(x, "line", default) or default


# ---------------------------------------------------------------------
#  defuns: the body in source order, each form's parent
# ---------------------------------------------------------------------

class Defun:
    """One defun, indexed.  A defun nested in it is its own Defun: its
    body is not part of this one's sequence."""

    def __init__(self, form, path):
        self.form, self.path = form, path
        self.name = form[1].lower()
        al = form[2] if len(form) > 2 and isinstance(form[2], list) else []
        names = [a.lower() for a in al if isinstance(a, Sym)]
        if "/" in names:
            k = names.index("/")
            self.params, self.locals = names[:k], names[k + 1:]
        else:
            self.params, self.locals = names, []
        self.line = form.line
        self.body = form[3:]
        self.seq, self.parent, self.at = [], {}, {}
        self.inner = []
        self.setqs = {}          # name -> [(setq form, value)] in order
        for b in self.body:
            self._index(b, None)

    def _index(self, f, parent):
        if not isinstance(f, list):
            return
        if hd(f) in ("defun", "defun-q") and len(f) > 2 \
                and isinstance(f[1], Sym):
            self.inner.append(f)
            return
        self.at[id(f)] = len(self.seq)
        self.seq.append(f)
        self.parent[id(f)] = parent
        if hd(f) == "setq":
            for i in range(1, len(f) - 1, 2):
                if isinstance(f[i], Sym):
                    self.setqs.setdefault(f[i].lower(), []).append(
                        (f, f[i + 1]))
        for x in f:
            self._index(x, f)

    def pos(self, f):
        return self.at.get(id(f), len(self.seq)) if f is not None \
            else len(self.seq)

    def ancestors(self, f):
        out = []
        p = self.parent.get(id(f))
        while p is not None:
            out.append(p)
            p = self.parent.get(id(p))
        return out

    def bound(self, n):
        return n in self.params or n in self.locals


class Unit:
    """One tier read as one program -- the tier has no two top-level
    defuns of one name (check_standards holds shared/ to that, and lisp/
    has none) -- so a helper's callers in any file, and the grouped
    tier's calls into CALOFIN-LIB, are all in view."""

    def __init__(self, paths, knobs=None):
        self.paths = [p for p in paths
                      if not any(s in p.parts for s in SKIP_DIRS)]
        self.defs = []
        self.top_sets = {}       # global -> [value] set outside any defun
        for p in self.paths:
            for top in forms_of(p):
                self._collect(top, p)
        self.byname = {}
        for d in self.defs:
            if d.name != "*error*":
                self.byname.setdefault(d.name, d)
        self.calls = {}          # name -> [(caller Defun, call form)]
        self.sets = {}           # global -> [(Defun, value)]
        for d in self.defs:
            for f in d.seq:
                h = hd(f)
                if h in self.byname:
                    self.calls.setdefault(h, []).append((d, f))
            for n, lst in d.setqs.items():
                if not d.bound(n):
                    self.sets.setdefault(n, []).extend(
                        (d, v) for _f, v in lst)
        if knobs is None:
            knobs = set()
            for p in self.paths:
                if p.stem.lower() == "lisplab":
                    continue          # the lesson file: not in LAZTUNE
                knobs |= {k[0].lower() for k in knobsmod.knobs_of(p)
                          if not knobsmod.is_state(k[0])}
        self.knobs = knobs
        # which defuns reach an input call, however indirectly: the
        # callers of an asker ask too -- check_osnap's call graph, walked
        # backwards once from the defuns that prompt themselves
        dmap = {}
        for d in self.defs:
            if d.name != "*error*":
                dmap.setdefault(d.name, []).append(d.form)
        callers = {}
        for n, cs in co.callees(dmap).items():
            for c in cs:
                callers.setdefault(c, set()).add(n)
        self.asks = {d.name for d in self.defs if d.name != "*error*"
                     and any(hd(f) in ASK for f in d.seq)}
        todo = list(self.asks)
        while todo:
            for n in callers.get(todo.pop(), ()):
                if n not in self.asks and not n.startswith("c:"):
                    self.asks.add(n)
                    todo.append(n)

    def _collect(self, f, path, in_defun=False):
        if not isinstance(f, list):
            return
        h = hd(f)
        if h in ("defun", "defun-q") and len(f) > 2 and isinstance(f[1], Sym):
            d = Defun(f, path)
            self.defs.append(d)
            for inner in d.inner:
                self._collect(inner, path, True)
            return
        if h == "setq" and not in_defun:
            for i in range(1, len(f) - 1, 2):
                if isinstance(f[i], Sym):
                    self.top_sets.setdefault(f[i].lower(), []).append(
                        f[i + 1])
        for x in f:
            self._collect(x, path, in_defun)


# ---------------------------------------------------------------------
#  prompts
# ---------------------------------------------------------------------

#: the input calls initget governs, and so the ones that SPEND it
GETTERS = {"getkword", "getpoint", "getdist", "getint", "getreal",
           "getcorner", "getangle", "getorient", "entsel", "nentsel",
           "nentselp"}
#: number prompts: bits 2 and 4 refuse zero and negatives
NUMGET = {"getdist", "getint", "getreal", "getangle", "getorient"}
PICKNUM = {"getpoint", "getdist", "getint", "getreal", "getcorner",
           "getangle", "getorient", "entsel"}
#: every call that asks the drafter something
ASK = GETTERS | {"getstring", "ssget", "getfiled"}


def bit_values(a, depth=0):
    """Every value the bits expression A can take, or None when that
    cannot be told.  (if c 6 7) is {6, 7}; (+ (if dflt 6 7) 128) is
    {134, 135} -- each ARM added, never every literal in the form summed,
    which would read {141} and call bit 1 always set; (logior 4 (if z 0
    2)) is {4, 6}.  A keyword string where the bits go sets none."""
    if depth > 8:
        return None
    if isinstance(a, Str) or hd(a) == "strcat":
        return {0}
    if is_num(a):
        return {int(float(a))}
    if is_sym(a, "nil"):
        return {0}
    h = hd(a)
    if h == "if" and len(a) >= 3:
        out = set()
        for y in a[2:4]:
            v = bit_values(y, depth + 1)
            if v is None:
                return None
            out |= v
        return out if len(a) > 3 else out | {0}
    if h == "cond":
        out, has_t = set(), False
        for cl in a[1:]:
            if not isinstance(cl, list) or len(cl) < 2:
                return None
            has_t = has_t or is_sym(cl[0], "t")
            v = bit_values(cl[-1], depth + 1)
            if v is None:
                return None
            out |= v
        return out if has_t else out | {0}
    if h == "progn" and len(a) > 1:
        return bit_values(a[-1], depth + 1)
    if h in ("+", "logior") or (h == "boole" and len(a) > 2
                                and is_num(a[1]) and a[1] == "7"):
        args = a[2:] if h == "boole" else a[1:]
        outs = {0}
        for y in args:
            # an operand that cannot be told adds nothing KNOWN: the
            # bits the literals set are set whatever it is
            v = bit_values(y, depth + 1) or {0}
            outs = {(o + p) if h == "+" else (o | p)
                    for o in outs for p in v}
            if len(outs) > 64:
                return None
        return outs
    return None


def bits_of(initget):
    """The bit values an initget can set, one per path through its first
    argument; empty when they cannot be told."""
    if initget is None or len(initget) < 2:
        return set()
    return bit_values(initget[1]) or set()


def kw_expr(initget):
    """The keyword argument of an initget, or None."""
    if initget is None:
        return None
    for a in reversed(initget[1:]):
        if isinstance(a, Str):
            return a
        if isinstance(a, Sym) and not is_num(a):
            return a
        if isinstance(a, list):
            if hd(a) in ("+", "logior", "boole"):
                continue
            if hd(a) == "if" and not any(isinstance(x, Str)
                                         for x in walk(a)) \
                    and all(is_num(x) or isinstance(x, list)
                            for x in a[2:]):
                continue          # (if c 6 0): the bits, not the words
            return a
    return None


class Site:
    """One input call: the initgets it spends, the variable it lands in."""

    def __init__(self, d, form, inits):
        self.d, self.form, self.inits = d, form, inits
        self.head = hd(form)
        self.var = None
        p = d.parent.get(id(form))
        if hd(p) == "setq":
            for i in range(1, len(p) - 1, 2):
                if p[i + 1] is form and isinstance(p[i], Sym):
                    self.var = p[i].lower()
        self.bits = set()
        for i in inits:
            self.bits |= bits_of(i)
        self.prompt = None
        for a in form[1:]:
            if isinstance(a, Str) or hd(a) in ("strcat", "if", "cond"):
                self.prompt = a
        # what the prompt SHOWS: the same, or a local the text was built
        # in once, above the fork (spa:askd's PROMPT)
        self.shown = self.prompt
        if self.shown is None and len(form) > 1:
            a = form[-1]
            if isinstance(a, Sym) and a.lower() in d.locals:
                self.shown = resolve_local(d, a, form)

    @property
    def line(self):
        return self.form.line

    def bit(self, b):
        return any(x & b for x in self.bits)

    def always(self, b):
        return bool(self.bits) and all(x & b for x in self.bits)


def input_sites(d):
    out, inits = [], []
    for f in d.seq:
        h = hd(f)
        if h == "initget":
            inits.append(f)
        elif h in GETTERS:
            out.append(Site(d, f, inits))
            inits = []
    return out


def flat_prompt(p):
    """The pieces of prompt P in order; an (if C A B) contributes both
    arms, so (if dflt (strcat " <" (rtos dflt) ">") "") shows DFLT."""
    if hd(p) == "strcat":
        out = []
        for x in p[1:]:
            out += flat_prompt(x)
        return out
    if hd(p) == "if" and len(p) >= 3:
        out = []
        for x in p[2:4]:
            out += flat_prompt(x)
        return out
    return [p]


def shown_default(prompt):
    """What the prompt shows as the Enter answer: ('lit', text),
    ('expr', form) or None."""
    if prompt is None:
        return None
    pieces = flat_prompt(prompt)
    for k, x in enumerate(pieces):
        if isinstance(x, Str):
            m = re.search(r"<([^<>]*)>", x)
            if m:
                return ("lit", m.group(1))
            if x.rstrip().endswith("<") and k + 1 < len(pieces):
                return ("expr", pieces[k + 1])
    return None


CMP = {"<", ">", "<=", ">="}


def cmp_dirs(g, name):
    """Which way comparison G bounds NAME when it is TRUE: +1 'NAME is
    big' (a lower bound: (> x 0), (< 0 x), the 0 of (<= 0 x 1)), -1 'NAME
    is small' ((< x 1), (minusp x), (zerop x)); both for a chain that
    bounds it on each side."""
    h = hd(g)
    if h in ("minusp", "zerop") and len(g) == 2 and is_sym(g[1], name):
        return {-1}
    out = set()
    if h in CMP:
        args = g[1:]
        for i, a in enumerate(args):
            if not is_sym(a, name):
                continue
            before, after = i > 0, i < len(args) - 1
            if h in ("<", "<="):
                if before:
                    out.add(1)
                if after:
                    out.add(-1)
            else:
                if after:
                    out.add(1)
                if before:
                    out.add(-1)
    return out


def null_kind(t, var):
    """How test T reads an Enter answer (VAR nil): 'null' for (null v) /
    (not v) or an (and ...) holding one -- the branch runs on Enter, if
    at all -- 'or' for an (or (null v) ...) that also takes a typed value
    the code refuses, else None.  (and (null v) (= 7 (getvar "ERRNO")))
    is a missed CLICK, not Enter."""
    def isnull(x):
        return hd(x) in ("null", "not") and len(x) == 2 and is_sym(x[1], var)
    if isnull(t):
        return "null"
    h = hd(t)
    if h in ("and", "or") and any(isnull(y) for y in t[1:]):
        if any(isinstance(z, Str) and str(z).upper() == "ERRNO"
               for y in walk(t) if isinstance(y, list) for z in y):
            return None
        return "null" if h == "and" else "or"
    return None


def enter_branches(d, var, g):
    """What an Enter answer (VAR nil) is replaced with, read from prompt
    G to the next input call that assigns VAR: [(value, form, kind,
    own)].  KIND is 'null' or 'or' (see null_kind); OWN, for 'or', is
    the comparisons that make the code refuse a typed value below a
    bound of its own -- (or (not n) (< n 1)) -- and hand the default
    back instead, which is then held to that bound as an initget's bits
    would be.  An 'or' branch counts only when it assigns VAR: one that
    prints and loops is a refusal, not an answer."""
    if not var:
        return []
    lo, hi = d.pos(g), len(d.seq)
    for j in range(lo + 1, len(d.seq)):
        f2 = d.seq[j]
        p2 = d.parent.get(id(f2))
        if hd(f2) in GETTERS and hd(p2) == "setq" and any(
                is_sym(p2[i], var) for i in range(1, len(p2) - 1, 2)):
            hi = j
            break
    window = d.seq[lo:hi]

    def setq_vals(form):
        vals = []
        for g2 in walk(form):
            if hd(g2) == "setq":
                for i in range(1, len(g2) - 1, 2):
                    if is_sym(g2[i], var):
                        vals.append((g2[i + 1], g2))
        return vals

    def own_of(t):
        return [y for y in walk(t) if -1 in cmp_dirs(y, var)]

    def branch(t, body, at):
        """BODY (a list of forms) runs when test T is true."""
        k = null_kind(t, var)
        if k is None:
            return []
        vals = []
        for b in body:
            vals += setq_vals(b)
        if k == "or":
            # it counts only when it ASSIGNS the answer: one that prints
            # and loops is a refusal.  OWN may be empty -- (or (null v)
            # (equal v d)) -- and then only the bits make it a number
            # prompt
            return [(x, a, k, own_of(t)) for x, a in vals]
        if vals:
            return [(x, a, k, None) for x, a in vals]
        return [(body[-1], at, k, None)] if body else []

    out = []
    for f in window:
        h = hd(f)
        if h == "if" and len(f) >= 3:
            t = f[1]
            if is_sym(t, var) and len(f) == 4:
                # (if v v X) / (if v (setq out v) (setq out X)): X is
                # what Enter takes -- but only when the typed arm hands
                # V on AS TYPED.  (if v (strcase v) "AUTO") is spelt in
                # the strcased domain, not the keyword list's
                a = f[2]
                if not (is_sym(a, var) or (hd(a) == "setq" and len(a) == 3
                                           and is_sym(a[2], var))):
                    continue
                vals = setq_vals(f[3])
                out += [(x, a, "null", None) for x, a in vals] if vals \
                    else [(f[3], f, "null", None)]
            else:
                out += branch(t, [f[2]], f)
        elif h == "cond":
            after_v = False
            for cl in f[1:]:
                if not isinstance(cl, list) or not cl:
                    continue
                if after_v and is_sym(cl[0], "t"):
                    # (cond (v ...) ... (T X)): X is what Enter reaches
                    body = cl[1:] or [cl[0]]
                    vals = []
                    for b in body:
                        vals += setq_vals(b)
                    out += [(x, a, "null", None) for x, a in vals] if vals \
                        else [(body[-1], cl, "null", None)]
                    break
                if is_sym(cl[0], var):
                    after_v = True
                    continue
                # a clause with no body returns its test's value, and an
                # (and ...) is T -- never the answer
                out += branch(cl[0], cl[1:], cl)
    fixed = []
    for x, at, k, own in out:
        # (if dflt dflt (ask-again ...)) -> dflt
        if hd(x) == "if" and len(x) >= 3 and isinstance(x[1], Sym) \
                and isinstance(x[2], Sym) and x[1].lower() == x[2].lower():
            fixed.append((x[2], at, k, own))
        else:
            fixed.append((x, at, k, own))
    return fixed


# ---------------------------------------------------------------------
#  provenance: where a value handed back on Enter comes from
# ---------------------------------------------------------------------

CANON_FN = re.compile(r"canon|fkword|kwknob|offered|kwpick|kwfix|kwnorm", re.I)
GUARD_FN = {"member", "assoc", "vl-position"}
CONDS = {"if", "cond", "and", "or", "while", "repeat", "foreach",
         "lambda"}
ELEM = {"car": 0, "cadr": 1, "caddr": 2, "cadddr": 3}


def tests_one(g, name):
    """G itself asks whether NAME is one of a list, or canonicalises it."""
    h = hd(g)
    if h in GUARD_FN and len(g) >= 2:
        a = g[1]
        if is_sym(a, name):
            return True
        if hd(a) == "strcase" and len(a) > 1 and is_sym(a[1], name):
            return True
    if h and CANON_FN.search(h):
        return any(is_sym(a, name) for a in g[1:])
    return False


def tests(f, name):
    """Somewhere in F, NAME is asked about as one of a list, or
    canonicalised -- how a KEYWORD is vetted.  A comparison is not one:
    it vets a number, and only one way round (see polar)."""
    return any(tests_one(g, name) for g in walk(f))


def polar(t, name, keep, num):
    """Test T vets NAME for the branch it guards.  KEEP: NAME is used as
    it is when T is TRUE -- (if T name X) -- else it is REPLACED when T
    is true -- (if T (setq name X)).  A member / assoc / canonicaliser
    test is 'NAME is good when true'.  At a number prompt (NUM) a
    comparison counts too, but only as a LOWER bound on the kept side --
    (if (> x 0) x 6.0), (if (not (> x 0)) (setq x 6.0)), (max 0.0 x) --
    because an initget refuses zero and negatives: an upper-only clamp
    such as (if (> x 100) (setq x 100)) lets both through."""
    want = 1 if keep else -1

    def rec(x, neg):
        h = hd(x)
        if h in ("not", "null") and len(x) == 2:
            return rec(x[1], not neg)
        if h in ("and", "or"):
            return any(rec(y, neg) for y in x[1:])
        if h == "setq" and len(x) >= 3:
            return rec(x[-1], neg)
        dirs = set()
        if tests(x, name):
            dirs.add(1)
        if num:
            dirs |= cmp_dirs(x, name)
        return any((-dd if neg else dd) == want for dd in dirs)
    return rec(t, False)


def value_vets(v, name, num):
    """(setq NAME V) makes NAME an answer the prompt offers: V
    canonicalises or looks NAME up, or keeps it only under a test that
    vets it; at a number prompt a (max ...) floor round it counts."""
    if not num:
        return tests(v, name)
    for g in walk(v):
        h = hd(g)
        if tests_one(g, name):
            return True
        if h == "max" and any(name in syms(a) for a in g[1:]):
            return True
        if h == "if" and len(g) >= 3:
            if is_sym(g[2], name) and polar(g[1], name, True, True):
                return True
            if len(g) > 3 and is_sym(g[3], name) \
                    and polar(g[1], name, False, True):
                return True
        if h == "cond":
            for cl in g[1:]:
                if isinstance(cl, list) and len(cl) > 1 \
                        and is_sym(cl[-1], name) \
                        and polar(cl[0], name, True, True):
                    return True
    return False


def cond_vets(ca, child, name, num):
    """An assignment to NAME made inside CHILD of the conditional CA is
    a vetting one: it REPLACES NAME only when CA's test says NAME is bad
    -- (if (not (member x L)) (setq x "Radius")), (or (> x 0) (setq x
    6.0)), (cond ((member x L) nil) (T (setq x "Radius")))."""
    h = hd(ca)
    if h == "if" and len(ca) > 2:
        if child is ca[1]:
            return False
        return polar(ca[1], name, child is not ca[2], num)
    if h == "cond":
        for cl in ca[1:]:
            if cl is child:
                return isinstance(cl, list) and bool(cl) \
                    and polar(cl[0], name, False, num)
            if isinstance(cl, list) and cl and polar(cl[0], name, True, num):
                return True
        return False
    if h in ("and", "or", "while"):
        terms = [ca[1]] if h == "while" else ca[1:]
        before = []
        for y in terms:
            if y is child:
                break
            before.append(y)
        # and / while: CHILD runs when the terms before it are TRUE; or:
        # when they are all FALSE, which keeps NAME when one is true
        return any(polar(y, name, h == "or", num) for y in before)
    return False


def assigns(f, name):
    for g in walk(f):
        if hd(g) == "setq" and any(is_sym(g[i], name)
                                   for i in range(1, len(g) - 1, 2)):
            return True
    return False


def child_toward(d, top, g):
    """The element of TOP on the way down to G (G inside TOP)."""
    chain = [g] + d.ancestors(g)
    for k in range(1, len(chain)):
        if chain[k] is top:
            return chain[k - 1]
    return None


def cond_tests(f):
    h = hd(f)
    if h in ("if", "while") and len(f) > 1:
        return [f[1]]
    if h == "cond":
        return [c[0] for c in f[1:] if isinstance(c, list) and c]
    if h in ("and", "or"):
        return list(f[1:])
    return []


def vets_in(d, f, name, num):
    """F -- a setq, or a conditional holding one -- vets NAME."""
    h = hd(f)
    if h == "setq":
        return any(is_sym(f[i], name) and value_vets(f[i + 1], name, num)
                   for i in range(1, len(f) - 1, 2))
    if h in ("if", "cond", "and", "or", "while") and \
            any(syms(t) & {name} or tests(t, name) for t in cond_tests(f)):
        for g in walk(f):
            if g is not f and hd(g) == "setq" and assigns(g, name) \
                    and cond_vets(f, child_toward(d, f, g), name, num):
                return True
    return False


def guarded(d, name, site, num=False):
    """NAME -- a global -- is made one of the offered answers inside D
    before SITE: a (setq NAME <vetting of NAME>), or a conditional whose
    TEST asks about NAME and whose body reassigns it on the side the
    test calls bad.  A test that only picks a branch is no guard."""
    return any(vets_in(d, f, name, num) for f in d.seq[:d.pos(site)])


class Src:
    """One place a value can come from."""

    def __init__(self, kind, detail, d, at, via, up, near=None):
        self.kind, self.detail = kind, detail
        self.d, self.at = d, at          # the defun it is read in, a form
        self.via, self.up = via, up      # defun names; the call frames
        self.near = near                 # a form round it, for the line

    @property
    def line(self):
        return line_of(self.at) or line_of(self.near) or \
            (self.d.line if self.d else 0)


class Ctx:
    """Where an expression is evaluated: in D, at SITE (None = the end),
    reached UP from a prompt through the frames UP -- ((callee, call
    form, caller) ...), innermost first -- or DOWN into a helper for its
    return value, bound to one call (call form, caller Ctx).  USE is
    where the value is finally consumed in D -- the prompt, or the call
    that carries it on -- which is what an (if C a b) is resolved
    against when the use sits inside an (if C ...) of its own."""

    def __init__(self, d, site, up=(), down=None, use=None):
        self.d, self.site, self.up, self.down = d, site, up, down
        self.use = use if use is not None else site


def lca_split(d, f, site):
    """(reaches, conditional): can the assignment F reach SITE, and is
    it made only under a condition SITE is not also under?"""
    chain_f = [f] + d.ancestors(f)
    anc_s = {id(a) for a in ([site] + d.ancestors(site))} \
        if site is not None else set()
    below = []
    lca = None
    for a in chain_f:
        if id(a) in anc_s:
            lca = a
            break
        below.append(a)
    if lca is f:
        return False, None               # (setq x (... x ...)): read first
    if lca is not None and len(below) and site is not None:
        cf = below[-1]
        chain_s = [site] + d.ancestors(site)
        cs = next((chain_s[k - 1] for k in range(1, len(chain_s))
                   if chain_s[k] is lca), None)
        h = hd(lca)
        if h == "if" and cf is not cs and cs is not None \
                and cf is not lca[1] and cs is not lca[1]:
            return False, None           # the other arm: never reaches
        if h == "cond" and cf is not cs and cs is not None \
                and not (isinstance(cf, list) and cf
                         and any(g is f for g in walk(cf[0]))):
            return False, None           # another clause's body
    # below the LCA, the first conditional form F sits in a part of that
    # does not always run: an if's arms, a loop's body, and/or past the
    # first term, any cond position but the first clause's test
    for k in range(1, len(below)):
        a, child = below[k], below[k - 1]
        h = hd(a)
        first = a[1] if len(a) > 1 else None
        if h == "cond":
            if not (child is first and k >= 2 and isinstance(child, list)
                    and child and below[k - 2] is child[0]):
                return True, (a, child)
        elif h in CONDS and child is not first:
            return True, (a, child)
    return True, None


class Tracer:
    """Where a value comes from.  NUM is set while tracing the answer of
    a NUMBER prompt: what vets a value there is a lower bound, where at
    a keyword prompt it is a membership test or a canonicaliser."""

    def __init__(self, unit):
        self.u = unit
        self.num = False

    def prov(self, x, c, via=(), depth=0, seen=frozenset()):
        d = c.d
        via = via if via and via[-1] == d.name else via + (d.name,)
        if depth > 14:
            return [Src("expr", "too deep", d, x, via, c.up,
                        c.site)]
        if isinstance(x, Str):
            return [Src("lit", str(x), d, x, via, c.up, c.site)]
        if isinstance(x, Sym):
            n = x.lower()
            if n in ("nil", "t"):
                return []
            if is_num(x):
                return [Src("num", n, d, x, via, c.up, c.site)]
            if d.bound(n):
                return self.var(n, x, c, via, depth, seen)
            if n in self.u.knobs:
                if guarded(d, n, c.site, self.num):
                    return [Src("canon", n, d, x, via, c.up, c.site)]
                return [Src("knob", n, d, x, via, c.up, c.site)]
            return [Src("global", n, d, x, via, c.up, c.site)]
        if not isinstance(x, list) or not x:
            return []
        h = hd(x)
        if h == "quote":
            q = x[1] if len(x) > 1 else None
            if isinstance(q, Sym):
                return [Src("sym", q.lower(), d, x, via, c.up)]
            return [Src("expr", "quote", d, x, via, c.up, c.site)]
        if h == "if" and len(x) >= 3:
            b = self.pick_branch(d, c.use, x[1])
            arms = [x[2 + b]] if b is not None and len(x) > 2 + b else x[2:4]
            out = []
            for a in arms:
                if isinstance(a, Sym) and polar(x[1], a.lower(),
                                                a is x[2], self.num):
                    # (if (member X '(...)) X "1"): X only when offered
                    out.append(Src("canon", a.lower(), d, x, via, c.up,
                                   c.site))
                    continue
                out += self.prov(a, c, via, depth + 1, seen)
            return out
        if h == "cond":
            out = []
            for cl in x[1:]:
                if isinstance(cl, list) and cl:
                    last = cl[-1]
                    if len(cl) > 1 and isinstance(last, Sym) \
                            and polar(cl[0], last.lower(), True, self.num):
                        out.append(Src("canon", last.lower(), d, cl, via,
                                       c.up, c.site))
                        continue
                    out += self.prov(last, c, via, depth + 1, seen)
            return out
        if h == "progn" and len(x) > 1:
            return self.prov(x[-1], c, via, depth + 1, seen)
        if self.num and h in ("min", "float", "fix"):
            # a ceiling, or a change of type, keeps a zero or a negative
            # what it was: (min 100.0 knob) is the knob, unfloored.  Any
            # other expression -- a (max 0.5 knob) floor among them --
            # is not followed, and at a number prompt that is silent
            out = []
            for a in x[1:]:
                out += self.prov(a, c, via, depth + 1, seen)
            return out
        if h == "setq" and len(x) >= 3:
            return self.prov(x[-1], c, via, depth + 1, seen)
        if h in ("or", "and", "not", "null", "=", "eq", "equal", "/=",
                 "member", "wcmatch", "<", ">", "<=", ">="):
            if h == "member" and len(x) == 3:
                return [Src("canon", "member", d, x, via, c.up, c.site)]
            return []                    # T or nil, never an answer
        if h in GETTERS or h == "getstring":
            return [Src("kw", h, d, x, via, c.up, c.site)]
        if h == "car" and hd(x[1] if len(x) > 1 else None) in (
                "member", "vl-member-if"):
            return [Src("canon", "car-member", d, x, via, c.up, c.site)]
        if h == "vl-some" and lookup_acc(x) is not None:
            return self.lookup(x, c, via, depth, seen)
        if h and CANON_FN.search(h):
            return [Src("canon", h, d, x, via, c.up, c.site)]
        if (h == "nth" and len(x) == 3 and is_num(x[1])) or \
                (h in ELEM and len(x) == 2):
            k = int(x[1]) if h == "nth" else ELEM[h]
            lst = x[2] if h == "nth" else x[1]
            for lf, lc in self.lists(lst, c, depth + 1, seen):
                if lf == "ANSWER":
                    return [Src("kw", "an ask helper's answer", d, x,
                                via, c.up)]
                if len(lf) > k + 1:
                    return self.prov(lf[k + 1], lc, via, depth + 1, seen)
                return []
            return [Src("expr", h, d, x, via, c.up, c.site)]
        callee = self.u.byname.get(h) if h else None
        if callee is not None and callee.name not in self.u.asks \
                and ("ret", h) not in seen and callee.body:
            return self.prov(callee.body[-1],
                             Ctx(callee, None, (), (x, c)), via,
                             depth + 1, seen | {("ret", h)})
        if callee is not None and callee.name in self.u.asks:
            return [Src("kw", "an ask helper's answer", d, x, via, c.up,
                        c.site)]
        return [Src("expr", h or "?", d, x, via, c.up, c.site)]

    def var(self, n, tok, c, via, depth, seen):
        """A parameter or local of C.d: the assignments that can reach
        C.site, latest first; then the caller(s) for a parameter."""
        d = c.d
        lim = d.pos(c.site)
        cands = [(f, v) for f, v in d.setqs.get(n, ()) if d.pos(f) < lim]
        out = []
        for f, v in reversed(cands):
            if is_sym(v, n):
                continue
            reaches, cond = lca_split(d, f, c.site)
            if not reaches:
                continue
            if value_vets(v, n, self.num):
                return out + [Src("canon", n, d, f, via, c.up, c.site)]
            vals = self.prov(v, Ctx(d, f, c.up, c.down, c.use), via,
                             depth + 1, seen)
            if not cond:
                return out + vals
            ca, child = cond
            out += vals
            if cond_vets(ca, child, n, self.num):
                return out               # the old value was vetted
        if n in d.params:
            k = d.params.index(n)
            if c.down is not None:
                call, cc = c.down
                if len(call) > k + 1:
                    return out + self.prov(call[k + 1], cc, via, depth + 1,
                                           seen)
                return out
            key = (d.name, k)
            if key in seen:
                return out
            seen = seen | {key}
            callers = self.u.calls.get(d.name, [])
            if not callers:
                return out + [Src("uncalled", n, d, tok, via, c.up,
                                  c.site)]
            for cd, form in callers:
                if len(form) > k + 1:
                    out += self.prov(form[k + 1],
                                     Ctx(cd, form, ((d, form, cd),) + c.up),
                                     via, depth + 1, seen)
            return out
        if not cands:
            return out + [Src("unset", n, d, tok, via, c.up, c.site)]
        return out

    def lookup(self, x, c, via, depth, seen):
        """(vl-some '(lambda (s) (if TEST s)) TABLE): an entry of TABLE
        or nil, never the value it was looked up with.  A table spelt
        out in the code is traced entry by entry (so an entry the prompt
        does not offer is still caught); one the code cannot see into
        -- a global table the keywords are built from -- is a lookup."""
        d = c.d
        acc = lookup_acc(x)
        found = self.lists(x[2], c, depth + 1, seen)
        if not found:
            return [Src("canon", "looked up", d, x, via, c.up, c.site)]
        out = []
        for lf, lc in found:
            if lf == "ANSWER":
                return [Src("expr", "vl-some", d, x, via, c.up, c.site)]
            for el in lf[1:]:
                for k in acc:
                    if hd(el) == "list":
                        el = el[k + 1] if len(el) > k + 1 else None
                    elif hd(el) == "quote":
                        q = el[1] if len(el) > 1 else None
                        el = q[k] if isinstance(q, list) and len(q) > k \
                            else None
                    elif isinstance(el, list) and not hd(el):
                        el = el[k] if len(el) > k else None
                    else:
                        el = None
                if el is None:
                    out.append(Src("expr", "vl-some", d, x, via, c.up,
                                   c.site))
                else:
                    out += self.prov(el, lc, via, depth + 1, seen)
        return out

    def lists(self, x, c, depth, seen):
        """The (list ...) forms X can be, each with its Ctx."""
        if depth > 12:
            return []
        if hd(x) == "list":
            return [(x, c)]
        if hd(x) == "quote" and isinstance(x[1] if len(x) > 1 else None,
                                           list):
            return [(["list"] + list(x[1]), c)]
        d = c.d
        if isinstance(x, Sym) and d.bound(x.lower()):
            n = x.lower()
            lim = d.pos(c.site)
            cands = [(f, v) for f, v in d.setqs.get(n, ())
                     if d.pos(f) < lim and not is_sym(v, n)]
            if cands:
                f, v = cands[-1]
                return self.lists(v, Ctx(d, f, c.up, c.down, c.use),
                                  depth + 1, seen)
            if n in d.params:
                k = d.params.index(n)
                if c.down is not None:
                    call, cc = c.down
                    return self.lists(call[k + 1], cc, depth + 1, seen) \
                        if len(call) > k + 1 else []
                out = []
                for cd, form in self.u.calls.get(d.name, []):
                    if len(form) > k + 1:
                        out += self.lists(form[k + 1], Ctx(cd, form),
                                          depth + 1, seen)
                return out
        if isinstance(x, list) and hd(x) in self.u.asks:
            return [("ANSWER", c)]
        return []

    @staticmethod
    def pick_branch(d, site, test):
        """0/1 when SITE sits inside an (if C' then else) with C' == C."""
        if site is None:
            return None
        chain = [site] + d.ancestors(site)
        for k in range(1, len(chain)):
            anc = chain[k]
            if hd(anc) == "if" and len(anc) >= 3 and same(anc[1], test):
                child = chain[k - 1]
                if anc[2] is child:
                    return 0
                if len(anc) > 3 and anc[3] is child:
                    return 1
        return None


def lookup_acc(x):
    """(vl-some '(lambda (s) (if TEST s)) LIST) hands back an ENTRY of
    LIST: the accessors (as ELEM indexes) from the entry to what the
    lambda returns -- () for S itself, (0,) for (car s) -- else None."""
    if hd(x) != "vl-some" or len(x) != 3:
        return None
    fn = x[1]
    if hd(fn) in ("quote", "function") and len(fn) == 2:
        fn = fn[1]
    if hd(fn) != "lambda" or len(fn) < 3 or not isinstance(fn[1], list) \
            or not fn[1] or not isinstance(fn[1][0], Sym):
        return None
    p = fn[1][0].lower()
    ret = fn[-1]
    if hd(ret) == "if" and (len(ret) == 3 or (len(ret) == 4
                                              and is_sym(ret[3], "nil"))):
        ret = ret[2]
    acc = []
    while hd(ret) in ELEM and len(ret) == 2:
        acc.insert(0, ELEM[hd(ret)])
        ret = ret[1]
    return tuple(acc) if is_sym(ret, p) else None


def same(a, b):
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, Sym) and isinstance(b, Sym):
        return a.lower() == b.lower()
    return type(a) is type(b) and a == b


def words_of(u, x, d, up, depth=0):
    """The keyword words expression X (in D) can hold, resolved through
    the call frames UP; None when that cannot be told."""
    if depth > 8:
        return None
    if isinstance(x, Str):
        return set(x.split())
    if isinstance(x, Sym):
        n = x.lower()
        if n in d.params:
            k = d.params.index(n)
            if up and up[0][0] is d and len(up[0][1]) > k + 1:
                return words_of(u, up[0][1][k + 1], up[0][2], up[1:],
                                depth + 1)
            return None
        if n in d.locals:
            vs = [v for _f, v in d.setqs.get(n, ()) if not is_sym(v, n)]
            if len(vs) == 1:
                return words_of(u, vs[0], d, up, depth + 1)
            return None
        vs = u.top_sets.get(n)
        if vs and not u.sets.get(n) and all(isinstance(v, Str) for v in vs):
            out = set()
            for v in vs:
                out |= set(v.split())
            return out
        return None
    h = hd(x)
    if h == "strcat":
        out = set()
        for y in x[1:]:
            w = words_of(u, y, d, up, depth + 1)
            if w is None:
                return None
            out |= w
        return out
    if h == "if" and len(x) >= 3:
        out = set()
        for y in x[2:4]:
            w = words_of(u, y, d, up, depth + 1)
            if w is None:
                return None
            out |= w
        return out
    return None


def global_bad(u, name, words):
    """Why a (non-knob) global handed back on Enter may not be offered."""
    bad = []
    for d, v in u.sets.get(name, []):
        if isinstance(v, Str):
            if words is not None and str(v) not in words:
                bad.append("literal %r" % str(v))
        elif hd(v) in ("getenv", "vl-registry-read", "getcfg", "read-line",
                       "read"):
            bad.append("read back by %s" % hd(v))
    return bad


# ---------------------------------------------------------------------
#  E and N
# ---------------------------------------------------------------------

class Finding:
    def __init__(self, rule, d, line, word, msg, path=None):
        self.rule, self.d, self.line = rule, d, line
        self.word, self.msg = word, msg
        self.path = path or d.path


def rule_e_n(u, sites):
    out = []
    tr = Tracer(u)
    for s in sites:
        d = s.d
        if s.always(1):
            continue                     # Enter refused: nothing handed back
        words, known = set(), True
        for i in s.inits:
            kx = kw_expr(i)
            if kx is not None:
                w = words_of(u, kx, d, ())
                if w is None:
                    known = False
                else:
                    words |= w
        words0 = words if known and words else None
        sd = shown_default(s.shown)
        is_kw = s.head == "getkword"
        branches = enter_branches(d, s.var, s.form)
        own = [g for _e, _a, _k, o in branches if o for g in o]
        numeric = s.head in NUMGET and (s.bit(6) or bool(own))
        if not is_kw:
            # a pick or number prompt counts as a keyword prompt only when
            # what it shows as the Enter answer is one of its keywords
            if sd and sd[0] == "lit" and words0 and sd[1] in words0:
                is_kw = True
        if not (is_kw or numeric):
            continue
        tr.num = not is_kw
        cands = []
        if is_kw and sd and sd[0] == "lit" and words0 is not None \
                and sd[1] not in words0 and s.head == "getkword":
            out.append(Finding("E", d, s.line, sd[1],
                               "shows <%s> as the Enter answer, but the "
                               "keywords are %s"
                               % (sd[1], " ".join(sorted(words0)))))
        shown_vars = sorted(n for n in syms(sd[1]) if d.bound(n)
                            or n in u.knobs) \
            if sd and sd[0] == "expr" else []
        for e, at, k, _o in branches:
            if numeric and k == "null" and kept(e, s.var) and shown_vars:
                # ((null v) (setq step 5)): Enter KEEPS the value shown
                # -- FITABHD's percent, (itoa (fix (* 100.0 pct))) --
                # so what is kept is whatever the shown form reads
                cands += [("Enter", Sym(n), at) for n in shown_vars]
                continue
            cands.append(("Enter", e, at))
        if is_kw and sd and sd[0] == "expr":
            cands.append(("shown", sd[1], s.form))
        if numeric and not is_kw and branches:
            # what the prompt SHOWS in <...> is what the drafter takes on
            # Enter: vetted only on the Enter branch, it shows <1500>
            # and takes 1.0 -- the same defect the other way round
            cands += [("shown", Sym(n), s.form) for n in shown_vars]
        rows = []
        for why, e, at in cands:
            for src in tr.prov(e, Ctx(d, s.form)):
                rows += [(why, r) for r in
                         verdict(u, s, why, src, words0, is_kw, at, own)]
        # a knob Enter hands back raw is one finding, not two: SHOWN is
        # reported only where Enter vets it and <...> still shows it raw
        taken = {r.word for why, r in rows if r.rule == "N"
                 and why == "Enter"}
        out += [r for why, r in rows if not (r.rule == "N" and why == "shown"
                                             and r.word in taken)]
    return out


def is_const(x):
    return isinstance(x, Str) or is_num(x) or is_sym(x, "t") \
        or is_sym(x, "nil") or hd(x) == "quote"


def kept(e, var):
    """Enter branch E moves on without touching the answer -- a message,
    or a (setq step 5) of constants -- so the value the prompt SHOWED is
    the one kept.  A (setq out dflt) hands a value over: it is traced."""
    h = hd(e)
    if h in ("princ", "prompt"):
        return True
    return h == "setq" and not assigns(e, var) and all(
        is_const(e[i + 1]) for i in range(1, len(e) - 1, 2))


def ranged(s, at):
    """Is the knob Enter hands back range-tested before it is used?  A
    test that VETS it on the way -- (if (> x 0) x 6.0), a reassignment
    under (if (not (> x 0)) ...) -- already ended the trace as vetted,
    so what is left is a vetting of the prompt's own variable, which
    counts only when it runs on the SUBSTITUTED value: after the (setq
    var knob), in a place the Enter branch reaches, and bounding it from
    below.  (cond ((null v) dflt) ((> v 100) ...)) clamps what is typed
    and hands the knob back untested."""
    d = s.d
    if s.var and hd(at) == "setq":
        for f in d.seq[d.pos(at) + 1:]:
            if vets_in(d, f, s.var, True) and lca_split(d, at, f)[0]:
                return True
    return False


def where_of(s, src):
    """The prompt, named from where the finding is reported."""
    loc = "line %d" % s.line if s.d.path == src.d.path \
        else "%s:%d" % (pathlib.Path(s.d.path).name, s.line)
    return "%s's %s (%s)" % (s.d.name, s.head, loc)


def verdict(u, s, why, src, words0, is_kw, at=None, own=()):
    d = s.d
    chain = " > ".join(reversed(src.via))
    where = where_of(s, src)
    if src.kind == "knob":
        if is_kw:
            return [Finding("E", src.d, src.line, src.detail,
                            "LAZTUNE knob %s is the %s answer of %s, "
                            "with nothing on the way making it one of the "
                            "keywords: %s" % (src.detail, why, where, chain))]
        if why == "shown":
            return [Finding("N", src.d, src.line, src.detail,
                            "LAZTUNE knob %s is SHOWN as the Enter answer "
                            "of %s, %s -- and nothing before the prompt "
                            "tests its range, so <...> shows a value Enter "
                            "must not take: %s"
                            % (src.detail, where, refused(s, own), chain))]
        if ranged(s, at):
            return []
        return [Finding("N", src.d, src.line, src.detail,
                        "LAZTUNE knob %s is the Enter answer of %s, %s -- "
                        "and nothing on the way tests its range: %s"
                        % (src.detail, where, refused(s, own), chain))]
    if src.kind == "lit" and is_kw:
        w = words0
        if w is None and src.up:
            for i in s.inits:
                kx = kw_expr(i)
                if kx is not None:
                    ww = words_of(u, kx, d, src.up)
                    if ww is None:
                        w = None
                        break
                    w = (w or set()) | ww
        if w is not None and src.detail not in w:
            return [Finding("E", src.d, src.line, src.detail,
                            "%r is the %s answer of %s, but the keywords "
                            "are %s: %s" % (src.detail, why, where,
                                            " ".join(sorted(w)), chain))]
        return []
    if src.kind == "num" and not is_kw and why == "Enter":
        v = float(src.detail)
        if (s.always(2) and v == 0) or (s.always(4) and v < 0):
            return [Finding("N", src.d, src.line, src.detail,
                            "%s is the Enter answer of %s, %s: %s"
                            % (src.detail, where, refused(s, own), chain))]
        return []
    if src.kind == "global" and is_kw:
        bad = global_bad(u, src.detail, words0)
        if bad:
            return [Finding("E", src.d, src.line, src.detail,
                            "global %s is the %s answer of %s, and it is "
                            "set from %s: %s"
                            % (src.detail, why, where,
                               "; ".join(sorted(set(bad))), chain))]
        return []
    if src.kind in ("expr", "uncalled", "unset") and is_kw:
        return [Finding("E?", src.d, src.line, src.detail,
                        "%s answer of %s from %s %s -- not traced: %s"
                        % (why, where, src.kind, src.detail, chain))]
    return []


def text_of(x):
    if isinstance(x, list):
        return "(" + " ".join(text_of(y) for y in x) + ")"
    if isinstance(x, Str):
        return '"%s"' % x
    return str(x)


def refused(s, own=()):
    """What the prompt refuses, as a clause: its initget's bits, or the
    code's own bound on a typed value."""
    r = []
    if s.bit(2):
        r.append("zero")
    if s.bit(4):
        r.append("negatives")
    if r:
        return "whose initget refuses " + " and ".join(r)
    if own:
        return "whose code refuses a typed %s (line %d) and hands the " \
            "default back instead" % (text_of(own[0]), line_of(own[0]))
    return "a number prompt"


# ---------------------------------------------------------------------
#  T1 / T2: what a bit-128 prompt does with a word it never offered
# ---------------------------------------------------------------------

CONSUME = {"car", "cadr", "caddr", "cddr", "cdr", "nth", "distance",
           "polar", "angle", "trans", "inters", "+", "-", "*", "/", "fix",
           "float", "abs", "rtos", "<", ">", "<=", ">=", "min", "max",
           "sqrt", "mapcar", "osnap"}
SYN = {"UNDO": "BACK", "U": "BACK", "B": "BACK"}


def syms(x):
    """Every VARIABLE in X: symbols that are not a form's head, T/nil,
    or quoted."""
    if isinstance(x, Sym):
        return set() if x.lower() in ("t", "nil") or is_num(x) \
            else {x.lower()}
    if not isinstance(x, list) or hd(x) == "quote":
        return set()
    out = set()
    for y in (x[1:] if x and isinstance(x[0], Sym) else x):
        out |= syms(y)
    return out


def split_words(s):
    return str(s).split()


def bracket_words(s):
    out = set()
    for m in re.finditer(r"\[([^\]]*)\]", str(s)):
        out |= {w.strip() for w in m.group(1).split("/") if w.strip()}
    return out


def resolve_local(d, x, site):
    if isinstance(x, Sym) and x.lower() in d.locals:
        cands = [v for f, v in d.setqs.get(x.lower(), ())
                 if d.pos(f) < d.pos(site)]
        return cands[-1] if cands else None
    return x


def offered(d, x, site, depth=0, lit=split_words):
    """(always, any, condvars) for a keyword or prompt expression."""
    x = resolve_local(d, x, site)
    if depth > 6 or x is None:
        return set(), set(), set()
    if isinstance(x, Str):
        w = set(lit(x))
        return w, w, set()
    if isinstance(x, Sym):
        if x.lower() in d.params:
            return set(), set(), {"?param:" + x.lower()}
        return set(), set(), set()
    h = hd(x)
    if h == "strcat":
        al, an, cv = set(), set(), set()
        for y in x[1:]:
            a, b, c = offered(d, y, site, depth + 1, lit)
            al |= a
            an |= b
            cv |= c
        return al, an, cv
    if h == "if":
        tv = syms(x[1]) if len(x) > 1 else set()
        a1, b1, c1 = offered(d, x[2], site, depth + 1, lit) \
            if len(x) > 2 else (set(), set(), set())
        a2, b2, c2 = offered(d, x[3], site, depth + 1, lit) \
            if len(x) > 3 else (set(), set(), set())
        return a1 & a2, b1 | b2, c1 | c2 | tv
    if h == "cond":
        alls, anys, cv, has_t = None, set(), set(), False
        for cl in x[1:]:
            if not isinstance(cl, list) or not cl:
                continue
            if is_sym(cl[0], "t"):
                has_t = True
            else:
                cv |= syms(cl[0])
            a, b, c = offered(d, cl[-1], site, depth + 1, lit)
            alls = a if alls is None else alls & a
            anys |= b
            cv |= c
        return (alls or set()) if has_t else set(), anys, cv
    return set(), set(), set()


def compared_words(f, var):
    """Literal words F compares VAR's value with."""
    h = hd(f)

    def isvar(a):
        return is_sym(a, var) or (hd(a) == "strcase" and len(a) > 1
                                  and is_sym(a[1], var))
    out = []
    if h in ("=", "eq", "equal") and len(f) == 3:
        a, b = f[1], f[2]
        if isvar(a) and isinstance(b, Str):
            out.append(str(b))
        if isvar(b) and isinstance(a, Str):
            out.append(str(a))
    if h == "member" and len(f) == 3 and isvar(f[1]):
        lst = unq(f[2])
        if isinstance(lst, list):
            out += [str(y) for y in lst if isinstance(y, Str)]
    return out


def gated(d, f, condvars):
    """Some ancestor of F tests one of CONDVARS outside F."""
    chain = [f] + d.ancestors(f)
    for k in range(1, len(chain)):
        anc, child = chain[k], chain[k - 1]
        h = hd(anc)
        others = []
        if h in ("and", "or"):
            others = [y for y in anc[1:] if y is not child]
        elif h in ("if", "while"):
            if anc[1] is not child:
                others = [anc[1]]
        elif isinstance(anc, list) and hd(d.parent.get(id(anc))) == "cond":
            if anc[0] is not child:
                others = [anc[0]]
        if any(syms(o) & condvars for o in others):
            return True
    return False


def is_type_pred(t, var, want_str):
    """T tests VAR's type: WANT_STR -> 'it is a string', else 'it is a
    point / number'."""
    h = hd(t)
    if h in ("=", "eq", "equal") and len(t) == 3:
        for x, y in ((t[1], t[2]), (t[2], t[1])):
            if hd(x) == "type" and len(x) > 1 and is_sym(x[1], var):
                y = unq(y)
                ys = str(y).upper() if isinstance(y, Sym) else ""
                if want_str and ys == "STR":
                    return True
                if not want_str and ys in ("LIST", "REAL", "INT"):
                    return True
    if not want_str and h in ("listp", "numberp", "vl-consp") \
            and len(t) > 1 and is_sym(t[1], var):
        return True
    if want_str and h == "not" and len(t) > 1 \
            and hd(t[1]) in ("listp", "numberp", "vl-consp") \
            and len(t[1]) > 1 and is_sym(t[1][1], var):
        return True
    if not want_str and h == "and":
        return any(is_type_pred(y, var, False) for y in t[1:])
    return False


def typed_safe(d, c, var):
    """The consumer C runs only once VAR is known not to be a string."""
    chain = [c] + d.ancestors(c)
    for k in range(1, len(chain)):
        anc, child = chain[k], chain[k - 1]
        h = hd(anc)
        if h == "if" and len(anc) > 2 and anc[2] is child \
                and is_type_pred(anc[1], var, False):
            return True
        if h == "if" and len(anc) > 3 and anc[3] is child \
                and is_type_pred(anc[1], var, True):
            return True
        if h == "and":
            for y in anc[1:]:
                if y is child:
                    break
                if is_type_pred(y, var, False):
                    return True
        if h == "cond":
            for cl in anc[1:]:
                if cl is child:
                    if isinstance(cl, list) and cl \
                            and is_type_pred(cl[0], var, False):
                        return True
                    break
                if isinstance(cl, list) and cl \
                        and is_type_pred(cl[0], var, True):
                    return True
    return False


def sentinel_of(d, g):
    """The quoted symbol the compare's clause hands back ('PF-BACK)."""
    for anc in ([g] + d.ancestors(g))[1:]:
        if isinstance(anc, list) and hd(d.parent.get(id(anc))) == "cond":
            for x in anc[1:]:
                for y in walk(x):
                    if hd(y) == "quote" and len(y) == 2 \
                            and isinstance(y[1], Sym):
                        return y[1].upper()
            return None
    return None


def quoted_names(y):
    out = set()
    for z in y:
        if hd(z) == "quote" and len(z) == 2:
            q = z[1]
            if isinstance(q, Sym):
                out.add(q.upper())
            elif isinstance(q, list):
                out |= {w.upper() for w in q if isinstance(w, Sym)}
    return out


def undefended(u, d, g, condv):
    """Callers of D that can call it WITHOUT offering the word (their
    argument for the condition parameter is not the literal T) and never
    test for the sentinel it comes back as; None when unreadable."""
    sent = sentinel_of(d, g)
    params = [c for c in condv if c in d.params]
    if not sent or not params:
        return None
    bad = []
    for c, f in u.calls.get(d.name, []):
        if all(len(f) > d.params.index(p) + 1
               and is_sym(f[d.params.index(p) + 1], "t") for p in params):
            continue
        par = c.parent.get(id(f))
        rv = None
        if hd(par) == "setq":
            for i in range(1, len(par) - 1, 2):
                if par[i + 1] is f and isinstance(par[i], Sym):
                    rv = par[i].lower()
        scope = [f] + c.ancestors(f)
        loop = next((a for a in scope[1:] if hd(a) == "while"), None)
        window = list(walk(loop)) if loop is not None \
            else c.seq[c.pos(f):]
        handles = False
        for y in window:
            if not isinstance(y, list) or hd(y) not in ("eq", "=", "equal",
                                                        "member"):
                continue
            if sent in quoted_names(y) and (
                    rv is None or any(is_sym(z, rv) for z in y)):
                handles = True
                break
        if not handles:
            bad.append("%s:%d" % (c.name, f.line))
    return bad


def rule_t(u, sites):
    out = []
    for s in sites:
        d, f = s.d, s.form
        if not s.bit(128) or not s.var:
            continue
        var = s.var
        lo, hi = d.pos(f), len(d.seq)
        for j in range(lo + 1, len(d.seq)):
            g2 = d.seq[j]
            p2 = d.parent.get(id(g2))
            if hd(g2) in ASK and hd(p2) == "setq" and any(
                    is_sym(p2[i], var) for i in range(1, len(p2) - 1, 2)):
                hi = j
                break
        window = d.seq[lo + 1:hi]
        always, anyw, condv = None, set(), set()
        for ini in s.inits:
            kx = kw_expr(ini)
            a, b, c = offered(d, kx, f) if kx is not None \
                else (set(), set(), set())
            always = a if always is None else always & a
            anyw |= b
            condv |= c
        if len(s.inits) > 1:
            for anc in d.ancestors(s.inits[0]):
                if hd(anc) in ("if", "cond") and any(
                        any(y is ini for y in walk(anc))
                        for ini in s.inits[1:]):
                    if hd(anc) == "if":
                        condv |= syms(anc[1])
                    break
        always = always or set()
        if s.prompt is not None:
            a, b, c = offered(d, s.prompt, f, lit=bracket_words)
            always |= a
            anyw |= b
            condv |= c
        up_always = {w.upper() for w in always}
        up_any = {w.upper() for w in anyw}
        real = {c for c in condv if not c.startswith("?")}
        for g in window:
            for w in compared_words(g, var):
                W = w.upper()
                if W in up_always or SYN.get(W) in up_always:
                    continue
                if W not in up_any and SYN.get(W) not in up_any:
                    out.append(Finding(
                        "T1", d, g.line, w,
                        "typed answer compared with %r, which the prompt "
                        "(%s, line %d) never offers" % (w, s.head, s.line)))
                elif not gated(d, g, real):
                    bad = undefended(u, d, g, condv)
                    if bad == []:
                        continue
                    out.append(Finding(
                        "T1", d, g.line, w,
                        "typed answer compared with %r unconditionally, but "
                        "the prompt (line %d) offers it only when %s%s"
                        % (w, s.line, "/".join(sorted(real)) or "a caller "
                           "says so", ("; callers that do not offer it and "
                                       "never test for it: " + ", ".join(bad))
                           if bad else "")))
        if s.head in PICKNUM:
            for g in window:
                hg = hd(g)
                if hg in CONSUME and any(is_sym(a, var) for a in g[1:]) \
                        and not typed_safe(d, g, var):
                    out.append(Finding(
                        "T2", d, g.line, "%s %s" % (hg, var),
                        "(%s ... %s ...) uses the answer of the bit-128 %s "
                        "at line %d where a typed word can still be: it "
                        "ends the command in a Lisp error"
                        % (hg, var, s.head, s.line)))
                    break
    return out


# ---------------------------------------------------------------------
#  S: a stored answer standing in for a prompt, taken raw
# ---------------------------------------------------------------------

TAKE = re.compile(r"ftake|fget|fpop|fpull|take$", re.I)


def asks_in(u, x):
    return any(hd(f) in ASK or hd(f) in u.asks for f in walk(x))


def vetted(a, cond):
    if isinstance(a, Str) or a is None:
        return True
    if isinstance(a, Sym):
        n = a.lower()
        if n in ("nil", "t"):
            return True
        # C hands the variable to a check: (ok kind (setq fv ...)) / (ok fv)
        for f in walk(cond):
            h = hd(f)
            if not h or h in ("setq", "and", "or", "not", "null"):
                continue
            for arg in f[1:]:
                if is_sym(arg, n):
                    return True
                if hd(arg) == "setq" and any(is_sym(y, n) for y in arg[1::2]):
                    return True
        return False
    h = hd(a)
    if h and CANON_FN.search(h):
        return True
    return h in ("car", "cadr") and hd(a[1] if len(a) > 1 else None) \
        == "member"


def rule_s(u, d):
    out = []
    for f in d.seq:
        if hd(f) != "setq":
            continue
        for i in range(1, len(f) - 1, 2):
            v = f[i + 1]
            if hd(v) != "if" or len(v) < 4:
                continue
            c, a, b = v[1], v[2], v[3]
            aa, ba = asks_in(u, a), asks_in(u, b)
            if aa == ba or asks_in(u, c):
                continue
            sub = b if aa else a
            raw = False
            if isinstance(sub, list) and TAKE.search(hd(sub) or ""):
                raw = True
            elif isinstance(sub, Sym):
                n = sub.lower()
                for g in walk(c):
                    if hd(g) == "setq":
                        for j in range(1, len(g) - 1, 2):
                            if is_sym(g[j], n) \
                                    and TAKE.search(hd(g[j + 1]) or ""):
                                raw = True
                if not raw:
                    last = None
                    for g, val in d.setqs.get(n, ()):
                        if d.pos(g) < d.pos(v):
                            last = val
                    if isinstance(last, list) \
                            and TAKE.search(hd(last) or "") \
                            and not guarded(d, n, v):
                        raw = True
            if raw and not vetted(sub, c):
                out.append(Finding(
                    "S", d, v.line, str(f[i]).lower(),
                    "(setq %s (if ... %s ...)): a stored answer stands in "
                    "for the prompt's, and nothing vets it the way the "
                    "prompt would" % (f[i], ("(" + hd(sub) + " ...)")
                                      if isinstance(sub, list) else sub)))
    return out


# ---------------------------------------------------------------------
#  I: an initget outside the loop that re-asks its prompt
# ---------------------------------------------------------------------

LOOPS = {"while", "repeat", "foreach"}


def rule_i(sites):
    out = []
    for s in sites:
        if not s.inits:
            continue
        last = s.inits[-1]
        d = s.d
        anc_i = {id(a) for a in d.ancestors(last)}
        for a in d.ancestors(s.form):
            if hd(a) in LOOPS and id(a) not in anc_i:
                out.append(Finding(
                    "I", d, s.line, s.head + (" " + s.var if s.var else ""),
                    "(%s ...) is re-asked by the %s at line %d, but its "
                    "initget (line %d) is outside that loop: the keywords "
                    "and bits hold for the first pass only"
                    % (s.head, hd(a), a.line, last.line)))
                break
    return out


# ---------------------------------------------------------------------
#  the run
# ---------------------------------------------------------------------

def analyse(paths, knobs=None):
    """Every finding over PATHS read as one tier (advisories included,
    rule 'E?')."""
    u = Unit(paths, knobs)
    rows = []
    sites = []
    for d in u.defs:
        ss = input_sites(d)
        sites += ss
        rows += rule_s(u, d)
    rows += rule_e_n(u, sites)
    rows += rule_t(u, sites)
    rows += rule_i(sites)
    seen, out = set(), []
    for r in rows:
        k = (str(r.path), r.line, r.rule, r.word, r.d.name)
        if k not in seen:
            seen.add(k)
            out.append(r)
    out.sort(key=lambda r: (str(r.path), r.line, r.rule, r.word))
    return u, out, len(sites)


#: defun name -> the lisp/ file it lives in, and file name -> the same,
#: so ONE baseline line covers a site in every tier: the grouped twin
#: and the dated release carry the same defun under the same name, in a
#: file of the same name (a release's with its date and REV added)
_HOMES = None
DATED_PART = re.compile(r"_\d{6}_REV[\d-]+(?=\.lsp$)", re.I)


def homes():
    global _HOMES
    if _HOMES is None:
        _HOMES = ({}, {})
        for p in lsp_files(LISP_DIR):
            if any(s in p.parts for s in SKIP_DIRS):
                continue
            _HOMES[1].setdefault(p.name.lower(), p)
            for m in DEFUN.finditer(decomment(read(p))):
                _HOMES[0].setdefault(m.group(1).lower(), p)
    return _HOMES


def rel(p):
    try:
        return str(pathlib.Path(p).resolve().relative_to(ROOT))
    except ValueError:
        return str(p)


def key_of(r):
    """(file, defun, 'RULE word'): the baseline key of finding R."""
    by_name, by_file = homes()
    home = by_name.get(r.d.name) or by_file.get(
        DATED_PART.sub("", pathlib.Path(r.path).name).lower(), r.path)
    return (rel(home), r.d.name, "%s %s" % (r.rule, r.word))


def load_baseline(bfile=None):
    """(file, defun, 'RULE word') -> reason."""
    bfile = pathlib.Path(bfile or BASELINE)
    out = {}
    if bfile.is_file():
        for ln in bfile.read_text(encoding="utf-8").splitlines():
            if ln.strip() and not ln.startswith("#"):
                parts = ln.split("|", 3)
                if len(parts) == 4:
                    out[(parts[0], parts[1].lower(), parts[2])] = parts[3]
    return out


def report(paths, base, show_all=False, out=print, label=None, knobs=None,
           hit=None):
    """Read PATHS as one tier and print every finding; the number that
    fail (baselined ones and advisories do not).  HIT collects the
    baseline keys matched."""
    _u, rows, nsites = analyse(paths, knobs)
    nfail = 0
    for r in rows:
        k = key_of(r)
        loc = "%s:%d" % (rel(r.path), r.line)
        if r.rule == "E?":
            if show_all:
                out("  advisory %s  [E?] %s -- %s" % (loc, r.d.name, r.msg))
            continue
        if k in base:
            if hit is not None:
                hit.add(k)
            if show_all:
                out("  held %s  [%s] %s -- baselined: %s"
                    % (loc, r.rule, r.d.name, base[k]))
            continue
        nfail += 1
        out("%s  [%s] %s -- %s" % (loc, r.rule, r.d.name, r.msg))
    if label:
        out("check_offered: %s -- %d input call(s) read, %s"
            % (label, nsites, ("%d finding(s)" % nfail) if nfail else
               "every answer handed back unasked is one the prompt offers"))
    return nfail


def stale_lines(base, hit, out=print):
    """Baseline lines no tier read matched: the site was fixed, moved or
    renamed, and a line left standing would excuse the next one there."""
    stale = sorted(k for k in base if k not in hit)
    for f, dn, what in stale:
        out("%s: %s %s - baselined, but no longer found (fixed, moved or "
            "renamed): drop the line from tools/offered_baseline.txt"
            % (f, dn, what))
    return len(stale)


TIERS = ("lisp", "shared", "releases")


def tier_paths(which):
    if which == "lisp":
        return lsp_files(LISP_DIR)
    if which == "shared":
        return [p for p in lsp_files(PARTS_DIR)
                if p.name.upper() != "CALOFIN-LOADER.LSP"]
    return [p for p in lsp_files(RELEASES_DIR) if DATED.match(p.name)]


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Every answer a prompt hands back without the drafter "
                    "typing it is one the prompt offers.")
    ap.add_argument("--tier", choices=TIERS,
                    help="one tier; the default reads all three and "
                         "reports stale baseline lines")
    ap.add_argument("--all", action="store_true",
                    help="also list the advisories (what could not be "
                         "traced) and the baselined sites")
    a = ap.parse_args(argv)
    base = load_baseline()
    hit = set()
    total = 0
    for t in ([a.tier] if a.tier else TIERS):
        total += report(tier_paths(t), base, a.all, label=t, hit=hit)
    if not a.tier:
        # a line is keyed by the defun's lisp/ home, so ONE line holds a
        # site in every tier; only a run over all of them can call one
        # stale
        total += stale_lines(base, hit)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
