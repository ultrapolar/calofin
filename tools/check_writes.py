#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A write nobody looks at is a write nobody knows failed.

On a LOCKED layer AutoCAD refuses a change to an existing object and
says nothing a routine would notice:

  entmod / entdel         answer nil and change nothing
  (command "_.ERASE" ...) skip the object ("1 was on a locked layer"),
  MOVE SCALE ROTATE ...   or refuse it outright (FILLET, BREAK, PEDIT);
                          (command) answers nil and vl-cmdf T whatever
                          happened, so the answer cannot be read at all
  (vl-catch-all-apply     the "On locked layer" error becomes a value,
    'vla-put-... )        quiet unless somebody tests it

So a routine learns that a write was refused only by LOOKING: testing
the answer, reading the object again, or keeping the lock out of the
way first (clearing it on its own layer, screening the selection it
edits).  A write whose answer is thrown away and is then COUNTED, or
reported as done, is a false success.  CDCREATE said "2 dimensioned
lines erased" over two lines still in the drawing; ABHD "cleared N
leftover markers" over markers still on screen; SPACHECK "1 item
marked red" over a dimension that never changed colour.  The drafter
believes the report, because that is what a report is for.

Rules:

  W1  THE LAYER HELPER UNLOCKS.  A defun that makes a LAYER record when
      it is missing also clears the lock bit when it is there (the
      logand 5 idiom of the ensure-layer helpers).  It is what lets a
      tool draw and wipe its OWN scratch without testing every entdel:
      entmake draws onto a locked layer, entdel refuses there, so a
      ruler or preview on a layer left locked (LAYISO's lock-and-fade
      locks every other layer) goes up and never comes down.  A layer
      is made by an entmake of a (0 . "LAYER") record, or by vla-Add on
      the Layers collection -- which hands back the layer already there,
      lock and all (TUTORIALPADDLE's demo layer); that one is cleared
      with vla-put-Lock.  No baseline: a layer helper has no reason to
      leave the lock on.

  W2  AN UNOBSERVED WRITE, THEN A CLAIM.  An entmod / entdel / caught
      vla- mutator whose answer is thrown away, on an object this run
      did not make, followed by
        - a COUNT among the next three statements of its body that
          somebody is told: (setq n (1+ n)), (setq l (cons x l)),
          (ssadd x ss), or a (setq done T) the defun hands back.  A
          loop's own index, (+ n (cadddr res)) summing a number worked
          out elsewhere, a report line consed onto a list (its words are
          the claim rule's), and a count every caller drops are not;
        - or a CLAIM among the next four statements: a string saying it
          happened ("erased", "moved", "marked", "restored" ...) that
          does not say it did NOT ("could NOT be erased" is the honest
          report this rule asks for), and does not ASK ("is the correct
          one placed?").  A strcat is read as the sentence it builds;
        - or, for a write inside a loop that keeps no told count of its
          own, a CLAIM among the four statements that run once the loop
          is over -- out through the progn or the loop around it, never
          past a loop that keeps such a count (that count is what the
          report says, and the tally rule's to judge).  dchk:tut-demo
          erased its practice lines in a repeat and then said "Practice
          drawing erased." over lines on a locked layer 0.
      The same for a statement calling a helper that holds such a write,
      and for a helper that ANSWERS its write -- (if (entmod ed) T) in
      its tail -- whose answer a caller drops, or that answers T
      whatever the write did and is trusted.  Also every EDIT COMMAND
      on objects this run did not make and did not screen -- its answer
      cannot be read, so the next line's claim is a guess -- and every
      write to SCRATCH made on the drafter's current layer (an entmake
      with no group 8), which no ensure-layer unlocks.

  W3  (--list only) the other thrown-away writes: nothing counted or
      claimed after them.  Shown for a reader; not failed.  That
      includes a bare discarded entmod -- check_values defers the
      discarded-entmod question here, and the answer is this rule: a
      refused write nobody reports as done misleads nobody; the one
      that is COUNTED or CLAIMED is the defect.

A write is not a finding when its object is:

  TABLE     a symbol-table record (tblobjname): the unlock itself -- a
            lock never refuses a write to a layer record
  FRESH     made by this run (entlast, entmakex, vla-Copy, what entnext
            walks to from an (entlast) mark, a helper or a global list
            that only ever holds such) on a named layer: W1 is what
            keeps that layer writable
  SCREENED  from a selection whose layers were UNLOCKED for the run
            (g2m:unlock-layers, sq:free-layers, lg:unlock) before the
            write and not behind a question; or written in a branch of
            an if/cond that tests a lock reader's own answer about it
            -- (if locked <stop> <write>) -- in this defun, or at every
            call that passes it in.  A lock reader masks group 70 with
            4 or 5, or hands back the answer of one that does, up to
            three helpers deep (xft:locked < xft:ss-locked < the test);
            a helper that calls a reader and answers something else
            (dchk:review-dim) is not one, nor is (logand 7 ...), which
            is a DIMENSION's type.  An offer to unlock that the drafter
            can refuse is NOT a screen: that is DIMCHECK's old No path,
            which carried on and reported every refused move
  GATED     past a TESTED write to the same object, or to one it shares
            a root with ((not (merge-lines la lb)) ... then colour la):
            the layer is known to be writable
  OBSERVED  looked at after: (entget e) straight after a write or
            anywhere after an erase, (entlast) after a FILLET

Where the object came from is a dataflow question, answered to a fixed
point over the whole tier: a local from its assignments, a global from
every assignment in the tier, a helper's value from its tails, and a
parameter from what every caller passes.  A foreach's own variable is
the list's element at the write, whatever else the defun gives a local
of the same name.

Every W2 site is fixed, or read by a person and recorded in
tools/write_baseline.txt -- file|defun|what|needs=TOKEN[@DEFUN]|reason,
check_back's pattern: a new site fails, and a line whose site has gone
is reported stale.  NEEDS names what makes the site honest, as it is
written in the code (DDFIX's dd-locked-say gate, PADDLE's re-read of
the perimeters): when that text leaves the defun it names, the line no
longer excuses its site and is reported stale -- a baseline written
for a gate must not outlive the gate.  A line is matched on the tool
(so one line covers lisp/, shared/ and releases/), the defun, and the
WHOLE write (past 80 characters, as a hash).  A REAL defect is never
baselined; it is fixed.

What this cannot see, and does not claim to: WHICH layers a lock
reader looks at (XFTCONV once screened the marker and name layers and
not the rest of the selection); a stage machine that sends a locked
pick back to the question (DDFIX, baselined); a caller that carries on
from its own in-memory copy of what a blind helper was asked to move
(OLAUTO: listed under --list, not failed); one element of a tuple --
(list arrow gap) is as found as its most found member (PERPMARK's
marks carry the survey point they were taped from, and are
baselined); an object made on a NAMED layer nothing unlocks, such as
"0" -- it passes as the run's own, and dchk:tut-demo is caught only
because its erase walks the set by ssname; a tested write whose
answer is MISREAD; and geometry a (command ...) draws on the current
layer, which (entlast) then hands back as the run's own.
"""

import argparse
import hashlib
import pathlib
import re
import sys
from collections import deque

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from callib import (LISP_DIR, PARTS_DIR, RELEASES_DIR, ROOT,  # noqa: E402
                    decomment, lsp_files)
# The line-keeping reader: lists that know their line, strings kept as
# Str, a quote kept as (quote x).  check_osnap's reader drops lines and
# quotes, which is all its rules need; these rules need both, and the
# baseline and the report both name a line.
import check_handlers as ch  # noqa: E402

BASELINE = HERE / "write_baseline.txt"
SKIP_DIRS = ("standards_checker",)

Str, Sym, L = ch.Str, ch.Sym, ch.L
walk, is_sym = ch.walk, ch.is_sym


def head(f):
    """ch.head, on the hot path: the reader builds only L and Sym, so
    their exact types are asked rather than isinstance"""
    if type(f) is L and f and type(f[0]) is Sym:
        return f[0].lower()
    return None


# ---------------------------------------------------------------------
#  what counts as a write to an existing object
# ---------------------------------------------------------------------

VALUE_WRITES = {"entmod", "entdel"}

#: edit commands: they act on objects already in the drawing and skip
#: (or refuse) the ones on a locked layer without an error
EDIT_CMDS = {"ERASE", "MOVE", "SCALE", "ROTATE", "MIRROR", "EXPLODE",
             "CHPROP", "CHANGE", "STRETCH", "PEDIT", "JOIN", "FILLET",
             "CHAMFER", "TRIM", "EXTEND", "BREAK", "DIMTEDIT", "ALIGN",
             "MATCHPROP", "LENGTHEN", "DRAWORDER", "ATTEDIT", "-ATTEDIT",
             "DDEDIT", "TEXTEDIT", "OFFSET"}

VLA_MUTATOR = re.compile(r"^vla-(delete|put-\w+|move|rotate|scaleentity|"
                         r"mirror|explode|update|offset)$", re.I)

COMMANDS = ("command", "command-s", "vl-cmdf")


def quoted_name(x):
    """'foo / (function foo) -> 'foo', else None."""
    if head(x) in ("quote", "function") and len(x) > 1 and is_sym(x[1]):
        return x[1].lower()
    return None


def cmd_name(f):
    """(command "_.ERASE" ...) -> 'ERASE'."""
    if head(f) in COMMANDS and len(f) > 1 and isinstance(f[1], Str):
        return f[1].upper().lstrip("_.").lstrip("_")
    return None


def write_kind(f, wrappers):
    """None, or what sort of write F is."""
    h = head(f)
    if h in VALUE_WRITES:
        return h
    if h in wrappers:
        return "via " + h
    if h == "vl-catch-all-apply" and len(f) > 1:
        fn = quoted_name(f[1])
        if fn and (fn in VALUE_WRITES or VLA_MUTATOR.match(fn)):
            return "catch " + fn
    if h in ("mapcar", "foreach") and len(f) > 2:
        if quoted_name(f[1]) in VALUE_WRITES:
            return "mapcar " + quoted_name(f[1])
    c = cmd_name(f)
    if c in EDIT_CMDS:
        return "cmd " + c
    return None


def target_of(f, kind):
    """the expression naming what F writes to"""
    if kind.startswith("cmd"):
        # the first argument that is not a keyword; OFFSET's first is
        # its distance, unless it is "_Through"
        args = [x for x in f[2:] if not isinstance(x, Str)]
        if kind == "cmd OFFSET" and len(f) > 2 and not isinstance(f[2], Str):
            args = args[1:]
        return args[0] if args else None
    if kind in VALUE_WRITES or kind.startswith("via "):
        return f[1] if len(f) > 1 else None
    if kind.startswith("mapcar"):
        return f[2] if len(f) > 2 else None
    if kind.startswith("catch"):
        # (vl-catch-all-apply 'fn (list obj ...)) -> obj
        a = f[2] if len(f) > 2 else None
        return a[1] if head(a) == "list" and len(a) > 1 else a
    return None


# ---------------------------------------------------------------------
#  where a value goes: 'use', 'discard', 'return', ('setq', var)
# ---------------------------------------------------------------------

TESTERS = {"and", "or", "not", "null", "vl-some", "vl-every",
           "vl-remove-if", "vl-remove-if-not", "vl-member-if",
           "vl-member-if-not"}
LOOPS = ("foreach", "repeat", "while")


def _body(stmts, last, kind):
    n = len(stmts)
    return [(s, last if i == n - 1 else "discard", stmts, kind)
            for i, s in enumerate(stmts)]


def lambda_of(c):
    """the lambda C stands for: '(lambda ...), (function (lambda ...)),
    or a bare (lambda ...)"""
    if head(c) == "lambda":
        return c
    if head(c) in ("quote", "function") and len(c) > 1 and \
            head(c[1]) == "lambda":
        return c[1]
    return None


def children(f, mode):
    """(child, mode, body, kind) for each evaluated child of F.  BODY is
    the statement list a statement sits in (None for an argument); KIND
    says whose body: 'loop', 'lambda', 'defun' or 'other'."""
    h = head(f)
    if not isinstance(f, list) or h == "quote":
        return []
    if h in ("defun", "defun-q"):
        return _body(f[3:], "return", "defun")
    if h == "lambda":
        return _body(f[2:], mode, "lambda")
    if h == "function":
        return [(c, mode, None, None) for c in f[1:]]
    if h == "progn":
        return _body(f[1:], mode, "other")
    # a test in a defun's tail decides what the defun answers --
    # (if (entmod ed) (progn (entupd e) T)) hands its caller the write's
    # answer as surely as a bare (entmod ed) would: 'rtest'
    test = "rtest" if mode in ("return", "rtest") else "use"
    if h == "if":
        out = [(f[1], test, None, None)] if len(f) > 1 else []
        return out + [(c, mode, None, None) for c in f[2:4]]
    if h == "cond":
        out = []
        for cl in f[1:]:
            if isinstance(cl, list) and cl:
                out.append((cl[0], test, None, None))
                out += _body(cl[1:], mode, "other")
        return out
    if h in ("and", "or") and test == "rtest":
        return [(c, "rtest", None, None) for c in f[1:]]
    if h in LOOPS:
        at = 2 if h == "foreach" else 1
        out = [(f[at], "use", None, None)] if len(f) > at else []
        return out + _body(f[at + 1:], "discard", "loop")
    if h == "setq":
        return [(f[i], ("setq", f[i - 1]), None, None)
                for i in range(2, len(f), 2)]
    if h in ("mapcar", "apply"):
        return [(c, mode if lambda_of(c) is not None else "use", None, None)
                for c in f[1:]]
    if h in TESTERS:
        return [(c, "use", None, None) for c in f[1:]]
    if h == "vl-catch-all-apply":
        return [(c, mode, None, None) for c in f[1:]]
    return [(c, "use", None, None) for c in f[1:] if isinstance(c, list)]


def visit_all(d, fn):
    """FN(form, mode, chain) for every form D evaluates, in D's own body
    (a nested defun is its own).  CHAIN is [(statement, body, kind)]
    from the innermost statement list out to D's body -- where a tally
    or a claim after a site is looked for."""
    def visit(f, mode, chain):
        lam = lambda_of(f) if head(f) in ("quote", "function") else None
        if lam is not None:
            visit(lam, mode, chain)
            return
        if not isinstance(f, list) or head(f) == "quote":
            return
        if head(f) in ("defun", "defun-q") and f is not d:
            return
        fn(f, mode, chain)
        for c, m, body, kind in children(f, mode):
            visit(c, m, ([(c, body, kind)] + chain) if body is not None
                  else chain)
    visit(d, "discard", [])


# ---------------------------------------------------------------------
#  provenance: where did the object being written come from?
# ---------------------------------------------------------------------

TABLE, FRESH, SCREENED, CLAYER, FOUND, UNKNOWN = \
    "TABLE", "FRESH", "SCREENED", "CLAYER", "FOUND", "UNKNOWN"
EXEMPT = (TABLE, FRESH, SCREENED)
#: the lattice: what an object built from several sources is.  One
#: found object in the mix makes it the drafter's; a parameter is a
#: question for the callers.
RANK = {UNKNOWN: 0, SCREENED: 2, FRESH: 3, FOUND: 4, CLAYER: 5, TABLE: 6}

#: the ActiveX calls that hand back a NEW object: a vla-Copy is not
#: its source
FRESH_VLA = re.compile(r"^vla-(copy|add\w*|offset|mirror|mirror3d|"
                       r"explode|arraypolar|arrayrectangular)$", re.I)
FOUND_SRC = {"ssname", "entsel", "nentsel", "nentselp", "handent",
             "ssget"}
#: what an alist handed to entmod is built out of: the spine that leads
#: back to the (entget X) naming the object, and not the (cons 8 lay)
#: beside it
SPINE = {"subst": (3,), "append": (1,), "cons": (2,), "vl-remove": (2,),
         "vl-remove-if": (2,), "vl-remove-if-not": (2,), "reverse": (1,),
         "if": (2, 3), "progn": (-1,)}


#: calls whose answer is a number, a point, a string or a truth -- never
#: an object.  A point read off a found entity is still not the entity:
#: (list pt ring) is the ring's, whatever the point came from
NOT_AN_OBJECT = {
    "quote", "and", "or", "not", "null", "=", "/=", "eq", "equal", "<", ">",
    "<=", ">=", "strcat", "itoa", "rtos", "atoi", "atof", "distof",
    "angtos", "strcase", "substr", "strlen", "vl-string-search",
    "trans", "polar", "distance", "angle", "inters", "+", "-", "*", "/",
    "1+", "1-", "abs", "fix", "float", "sqrt", "expt", "sin", "cos",
    "atan", "min", "max", "rem", "getvar", "boole", "logand", "logior",
    "length", "sslength", "type", "listp", "numberp", "wcmatch",
    "tblsearch", "getpoint", "getreal", "getdist", "getint", "getkword",
    "getstring", "getangle", "getcorner", "osnap", "textbox"}


def _pointer_group(code):
    """-1 is the object itself; 330-369 point at other objects"""
    try:
        n = int(code)
    except ValueError:
        return True
    return n == -1 or 330 <= n <= 369


def rank(v):
    return 1 if isinstance(v, tuple) else RANK[v]


def join(a, b):
    ra, rb = rank(a), rank(b)
    if ra != rb:
        return a if ra > rb else b
    if isinstance(a, tuple):
        return a if a[1] <= b[1] else b
    return a


def combine(rs):
    out = UNKNOWN
    for r in rs:
        out = join(out, r)
    return out


def is_literal(s):
    s = s.lower()
    if s in ("nil", "t", "pi", "/", "."):
        return True
    try:
        float(s)
        return True
    except ValueError:
        return False


def names_layer(alist):
    """does this entmake alist put the object on a named layer (group 8)?
    A symbol -- a dxf list built elsewhere -- is given the benefit."""
    if is_sym(alist):
        return True
    for f in walk(alist):
        if not isinstance(f, list) or not f:
            continue
        if head(f) in ("cons", "list") and len(f) > 1 and is_sym(f[1]) \
                and f[1] == "8":
            return True
        if head(f) == "quote" and isinstance(f[1], list) and f[1] \
                and is_sym(f[1][0]) and f[1][0] == "8":
            return True
    return head(alist) == "append" and any(is_sym(x) for x in alist[1:])


def ch_text(x):
    """a one-line rendering: fingerprints and target comparison"""
    if head(x) == "quote" and len(x) > 1:
        return "'" + ch_text(x[1])
    if isinstance(x, list):
        return "(" + " ".join(ch_text(y) for y in x) + ")"
    if isinstance(x, Str):
        return '"' + x + '"'
    return str(x) if x is not None else ""


class Info:
    """One defun, walked once: its nodes, what it declares (foreach and
    lambda bind their own), what each variable is given, what it reads."""

    def __init__(self, d, idx):
        self.d = d
        self.idx = idx
        self.name = d[1].lower()
        p, loc = ch.arglist(d)
        self.params = p
        self.declared = set(p) | set(loc)
        self.nodes = []
        self.assigns = {}
        self.reads = set()
        self.parent = {}
        # the (a b / c d) lists: declarations, not reads
        self.arglists = {id(f[2]) for f in walk(d)
                         if head(f) in ("defun", "defun-q") and len(f) > 2}
        self.arglists |= {id(f[1]) for f in walk(d)
                          if head(f) == "lambda" and len(f) > 1}
        stack = [d]
        while stack:
            f = stack.pop()
            self.nodes.append(f)
            h = head(f)
            if h == "quote":
                continue
            if h == "setq":
                for i in range(1, len(f) - 1, 2):
                    if is_sym(f[i]):
                        self.assigns.setdefault(f[i].lower(), []).append(
                            f[i + 1])
            elif h == "foreach" and len(f) > 2 and is_sym(f[1]):
                self.declared.add(f[1].lower())
                self.assigns.setdefault(f[1].lower(), []).append(f[2])
            elif h == "lambda" and f is not d:
                lp, ll = ch.arglist(f)
                self.declared |= set(lp) | set(ll)
            elif h == "ssadd" and len(f) > 2 and is_sym(f[2]):
                self.assigns.setdefault(f[2].lower(), []).append(f[1])
            for i, x in enumerate(f):
                if isinstance(x, list):
                    self.parent[id(x)] = f
                    # a nested defun -- the *error* handler, a local
                    # helper -- is a defun of its own, read on its own
                    if head(x) not in ("defun", "defun-q"):
                        stack.append(x)
                elif is_sym(x) and i > 0 and \
                        not (h == "setq" and i % 2 == 1):
                    self.reads.add(x.lower())
        self.nodes.sort(key=lambda n: getattr(n, "line", 0))
        #: the form that makes a LAYER record, if this defun has one
        self.layer_maker = next(
            (f for f in self.nodes
             if (head(f) in ("entmake", "entmakex") and
                 '(0 . "LAYER")' in ch_text(f)) or self._adds_layer(f)),
            None)
        self.makes_layer = self.layer_maker is not None

    def _adds_layer(self, f):
        """(vla-Add (vla-get-Layers doc) name), or the same through a
        local holding the collection: it makes the layer when it is
        missing and hands back the one there, lock and all, when it is
        not -- TUTORIALPADDLE's demo layer, made that way inline"""
        if head(f) != "vla-add" or len(f) < 2:
            return False
        coll = f[1]
        if is_sym(coll) and coll.lower() in self.declared:
            return any(head(e) == "vla-get-layers"
                       for e in self.assigns.get(coll.lower(), []))
        return head(coll) == "vla-get-layers"


def tails(stmts, out):
    """the expressions whose value a body hands back"""
    for st in stmts:
        h = head(st)
        if h == "if":
            tails(st[2:4], out)
        elif h == "progn":
            tails(st[-1:], out)
        elif h == "cond":
            for cl in st[1:]:
                if isinstance(cl, list) and cl:
                    tails(cl[-1:], out)
        elif h == "setq" and len(st) > 2:
            out.append(st[-1])
        elif h not in LOOPS and h not in ("princ", "prompt"):
            out.append(st)
    return out


class Prov:
    """Provenance over one tier, solved to a fixed point by worklist, on
    demand.

    Nodes: ('L', defun, var) a local; ('G', var) a global, over every
    assignment in the tier; ('R', name) what a helper hands back;
    ('P', name, i) what the callers pass as argument i.  A node is
    computed the first time a question reads it, and recomputed when a
    node it read climbs; values only climb the lattice, so the solve
    terminates.  Most of a tier's variables are numbers and strings no
    write ever asks about, and are never computed."""

    def __init__(self, sv):
        self.sv = sv
        self.val = {}
        self.deps = {}
        self.cur = None
        self.seen = set()
        self.work = deque()
        self.inq = set()

    def get(self, node):
        if self.cur is not None:
            self.deps.setdefault(node, set()).add(self.cur)
        if node not in self.seen:
            self.seen.add(node)
            self.inq.add(node)
            self.work.append(node)
        return self.val.get(node, UNKNOWN)

    def drain(self):
        while self.work:
            n = self.work.popleft()
            self.inq.discard(n)
            outer, self.cur = self.cur, n
            new = self.compute(n)
            self.cur = outer
            old = self.val.get(n, UNKNOWN)
            new = join(old, new)
            if new != old:
                self.val[n] = new
                for d in self.deps.get(n, ()):
                    if d not in self.inq:
                        self.inq.add(d)
                        self.work.append(d)

    def answer(self, fn, *args):
        """FN(*ARGS) once every node it reads has settled"""
        while True:
            r = fn(*args)
            if not self.work:
                return r
            self.drain()

    def compute(self, n):
        sv = self.sv
        if n[0] == "L":
            info, v = sv.infos[n[1]], n[2]
            r = ("PARAM", info.params.index(v)) if v in info.params \
                else UNKNOWN
            for e in info.assigns.get(v, []):
                r = join(r, self.ev(e, info))
            return r
        if n[0] == "G":
            r = UNKNOWN
            for e, gi in sv.glob[n[1]]:
                x = self.ev(e, gi)
                if isinstance(x, tuple):
                    x = self.get(("P", gi.name, x[1]))
                r = join(r, x)
            return r
        if n[0] == "R":
            info = sv.byname[n[1]]
            return combine(self.ev(t, info)
                           for t in tails(ch.body_of(info.d)[-1:], []))
        name, i = n[1], n[2]
        r = UNKNOWN
        for call, ci in sv.callsites.get(name, []):
            if i + 1 >= len(call):
                continue
            arg = call[i + 1]
            x = self.ev(arg, ci)
            if isinstance(x, tuple):
                x = self.get(("P", ci.name, x[1]))
            if x not in EXEMPT and sv.screened(arg, ci, call):
                x = SCREENED
            r = join(r, x)
        return UNKNOWN if isinstance(r, tuple) else r

    def ev(self, expr, info, bind=None):
        """the provenance of EXPR evaluated in INFO, from the current
        table: TABLE | FRESH | SCREENED | CLAYER | FOUND | ('PARAM', i)
        | UNKNOWN.  BIND maps a variable the site's own enclosing
        foreach binds to that foreach's list: (foreach e *demo-ents*
        (entdel e)) erases what the list holds, not whatever else the
        defun once put in a local that happens to be called E too."""
        if is_sym(expr):
            v = expr.lower()
            if is_literal(v):
                return UNKNOWN
            if bind and v in bind:
                return self.ev(bind[v], info,
                               {k: x for k, x in bind.items() if k != v})
            if v in info.declared:
                return self.get(("L", info.idx, v))
            return self.get(("G", v)) if v in self.sv.glob else UNKNOWN
        if not isinstance(expr, list) or not expr:
            return UNKNOWN
        h = head(expr)
        if h in NOT_AN_OBJECT or (h or "").startswith("vlax-curve-"):
            return UNKNOWN
        if h == "assoc" and len(expr) > 1 and is_sym(expr[1]) and \
                is_literal(expr[1]) and not _pointer_group(expr[1]):
            return UNKNOWN            # a field of the object, not the object
        if h == "tblobjname":
            return TABLE
        if h in ("entmake", "entmakex"):
            return FRESH if len(expr) > 1 and names_layer(expr[1]) \
                else CLAYER
        if h == "entlast" or FRESH_VLA.match(h or "") or (
                h == "vl-catch-all-apply" and len(expr) > 1 and
                FRESH_VLA.match(quoted_name(expr[1]) or "")):
            return FRESH
        if h == "ssget" and len(expr) > 1 and isinstance(expr[1], Str) \
                and expr[1].upper().lstrip("_") == "L":
            return FRESH
        if h == "entnext":
            # walking on from a mark this run took (entlast) meets only
            # what the run drew since; from anything else, anything.  A
            # bare (entnext) is the first object in the drawing: undecided
            # -- it is how "everything since the mark" starts when the
            # mark is nil because the drawing was empty
            if len(expr) < 2:
                return UNKNOWN
            r = self.ev(expr[1], info, bind)
            return r if r in (FRESH, UNKNOWN) or isinstance(r, tuple) \
                else FOUND
        if h in FOUND_SRC:
            return FOUND
        if h == "if":
            # (if (entmake alist) (entlast)): the entlast is what the
            # entmake made, on the layer the ALIST names -- or on CLAYER
            if len(expr) > 2 and head(expr[1]) in ("entmake", "entmakex") \
                    and head(expr[2]) == "entlast":
                return join(self.ev(expr[1], info, bind),
                            self.ev(expr[3], info, bind) if len(expr) > 3
                            else UNKNOWN)
            return combine(self.ev(x, info, bind) for x in expr[2:4])
        if h == "progn" or h == "setq":
            return self.ev(expr[-1], info, bind) if len(expr) > 1 \
                else UNKNOWN
        if h == "cond":
            return combine(self.ev(cl[-1], info, bind) for cl in expr[1:]
                           if isinstance(cl, list) and cl)
        if h in self.sv.byname and not h.startswith("c:"):
            r = self.get(("R", h))
            if isinstance(r, tuple):
                return self.ev(expr[r[1] + 1], info, bind) \
                    if r[1] + 1 < len(expr) else UNKNOWN
            return r
        return combine(self.ev(x, info, bind) for x in expr[1:]
                       if isinstance(x, list) or is_sym(x))

    def entity(self, alist, info, bind=None, seen=frozenset()):
        """the provenance of the OBJECT an entmod alist names: follow its
        spine back to the (entget X), and ask about X"""
        if is_sym(alist):
            v = alist.lower()
            if bind and v in bind:
                return self.entity(bind[v], info, {
                    k: x for k, x in bind.items() if k != v}, seen)
            if v in seen or v not in info.declared:
                return self.ev(alist, info, bind)
            seen = seen | {v}
            r = combine(self.entity(e, info, bind, seen)
                        for e in info.assigns.get(v, []))
            if r == UNKNOWN and v in info.params:
                return ("PARAM", info.params.index(v))
            return r
        h = head(alist)
        if h == "entget":
            return self.ev(alist[1], info, bind) if len(alist) > 1 \
                else UNKNOWN
        if h in SPINE:
            return combine(self.entity(alist[i], info, bind, seen)
                           for i in SPINE[h] if -len(alist) < i < len(alist))
        return self.ev(alist, info, bind)

    def param(self, info, pv):
        """a ('PARAM', i) settled from the callers; itself if they say
        nothing"""
        if isinstance(pv, tuple):
            r = self.answer(self.get, ("P", info.name, pv[1]))
            return pv if r == UNKNOWN else r
        return pv


def roots(expr, info):
    """every symbol EXPR derives from, through INFO's assignments"""
    out, todo = set(), [expr]
    while todo:
        e = todo.pop()
        if is_sym(e):
            xs = [e]
        elif isinstance(e, list):
            xs = [x for g in walk(e) if isinstance(g, list) for x in g[1:]]
        else:
            continue
        for x in xs:
            if not is_sym(x) or is_literal(x):
                continue
            v = x.lower()
            if v not in out:
                out.add(v)
                if v in info.declared:
                    todo += info.assigns.get(v, [])
    return out


# ---------------------------------------------------------------------
#  tallies, claims, lock readers
# ---------------------------------------------------------------------

#: past-tense words that say a change happened
CLAIM = re.compile(
    r"\b(moved|erased|removed|deleted|cleared|updated|merged|marked|"
    r"flagged|restored|recolou?red|colou?red|wiped|placed|applied|"
    r"scaled|rotated|replaced|renamed|fixed|adjusted|stamped|converted|"
    r"shifted|snapped|attached|swept|purged|mirrored|trimmed|joined|"
    r"exploded|filleted|taken down|put back|now reads)\b", re.I)
#: ...unless the sentence says it did NOT: "could NOT be erased" is the
#: honest report this check is asking for
NEGATED = re.compile(r"\b(not|never|nothing|no|cannot|could ?n.t|"
                     r"would ?n.t|n.t|without|un\w*)\W+(\w+\W+){0,3}$",
                     re.I)


#: where the sentence a claim word sits in ends: a full stop, a bang, a
#: question mark, or a new line
SENTENCE_END = re.compile(r"[.!?\n]")
#: the reader keeps a string's escapes as written, and "\nErased 3" is
#: one word to a regex until the \n is a line break again
ESCAPES = re.compile(r"\\(.)")


def unescape(x):
    return ESCAPES.sub(lambda m: {"n": "\n", "t": " ", "r": "\n"}.get(
        m.group(1).lower(), m.group(1)), x)


def claim_in(st):
    """the first string in ST that says something was done, or None.  A
    strcat is read as the one sentence it builds: "...but not" " joined."
    is two literals and one denial"""
    for f in walk(st):
        if not isinstance(f, list):
            continue
        if head(f) == "strcat":
            texts = ["".join(unescape(x) if isinstance(x, Str) else " _ "
                             for x in f[1:])]
        else:
            texts = [unescape(x) for x in f if isinstance(x, Str)]
        for x in texts:
            for m in CLAIM.finditer(x):
                # "- is the correct one placed?" asks; it does not say
                end = SENTENCE_END.search(x, m.end())
                if end and end.group() == "?":
                    continue
                if not NEGATED.search(x[:m.start()]):
                    # the claim word, a few words either side of it
                    return " ".join(x[:m.start()].split()[-6:] +
                                    x[m.start():].split()[:4])
    return None


def returned_vars(d):
    """the variables D hands back as its value"""
    return {t.lower() for t in tails(ch.body_of(d)[-1:], []) if is_sym(t)}


def index_vars(info):
    """the counters D walks a set or a list by -- (ssname ss i),
    (nth i l), (while (< i n)) -- whose (setq i (1+ i)) is a step, not
    a count of anything done"""
    out = set()
    for f in info.nodes:
        h = head(f)
        if h == "ssname" and len(f) > 2 and is_sym(f[2]):
            out.add(f[2].lower())
        elif h == "nth" and len(f) > 1 and is_sym(f[1]):
            out.add(f[1].lower())
        elif h == "while" and len(f) > 1 and head(f[1]) in (
                "<", "<=", ">", ">=", "/="):
            out |= {x.lower() for x in f[1][1:] if is_sym(x)}
    return out


def tally_of(st, flags, steps=frozenset()):
    """ST is itself a count -- (setq n (1+ n)), (setq n (+ n k)),
    (setq l (cons x l)), (ssadd x ss) -- or sets a success flag the
    defun hands back, (setq done T) ... done.  The variable, else None.
    A (setq stop T) nobody returns is a loop's exit, not a count."""
    if head(st) == "ssadd" and len(st) > 2:
        return "ssadd"
    if head(st) != "setq":
        return None
    for i in range(1, len(st) - 1, 2):
        var, val = st[i], st[i + 1]
        if not is_sym(var):
            continue
        v = var.lower()
        if v in steps or not any(is_sym(x) and x.lower() == v
                                 for x in val[1:] if head(val)):
            pass
        elif head(val) == "1+":
            return v
        elif head(val) in ("cons", "append") and not (
                len(val) > 1 and (head(val[1]) == "strcat" or
                                  isinstance(val[1], Str))):
            # a report line consed on is TEXT: whether it claims
            # anything is the claim rule's question, which reads it
            return v
        elif head(val) == "+" and all(
                (is_sym(x) and (x.lower() == v or is_literal(x)))
                for x in val[1:]):
            # (+ n 1) is one more; (+ n (cadddr res)) adds up a number
            # something else worked out, and counts no write of this one
            return v
        if is_sym(val) and val.lower() == "t" and v in flags:
            return v
    return None


def own_uses(info, var):
    """the forms in INFO that READ VAR other than to bump it -- a count
    that is only ever (1+ n)'d is never said to anyone"""
    out = []
    for f in info.nodes:
        if id(f) in info.arglists:
            continue
        h = head(f)
        if h == "setq":
            for i in range(1, len(f) - 1, 2):
                val = f[i + 1]
                if is_sym(f[i]) and f[i].lower() == var and \
                        head(val) in ("1+", "+", "cons", "append"):
                    continue
                if is_sym(val) and val.lower() == var:
                    out.append(f)
            continue
        if any(is_sym(x) and x.lower() == var for x in f[1:]) and \
                not (h in ("1+", "+", "cons", "append")):
            out.append(f)
    return out


#: how far down its own body a count may sit and still be this write's
REACH = 3


def after(chain, n=None):
    """the statements after the site in its own body (N of them)"""
    if not chain:
        return []
    st, body, _ = chain[0]
    idx = next((i for i, s in enumerate(body) if s is st), None)
    if idx is None:
        return []
    return body[idx + 1: idx + 1 + n] if n else body[idx + 1:]


def tally_after(chain, flags, steps=frozenset()):
    for s in after(chain, REACH):
        t = tally_of(s, flags, steps)
        if t:
            return t
    return None


#: ...and a claim.  The original DIMCHECK shape was entmod, entupd,
#: a princ, the question, then the cond whose branch said "MOVED onto":
#: four statements on.  A command's closing report is further, and is
#: fed by a count the tally rule finds.
CLAIM_REACH = 4


def claim_after(chain):
    """a claim among the next statements of the site's own body, however
    deep the string sits in them.  Not the bodies around it: a report
    after the loop is about all the items, and a count inside the loop
    is what feeds it -- when there IS one (claim_after_loop)."""
    for s in after(chain, CLAIM_REACH):
        c = claim_in(s)
        if c:
            return c
    return None


def next_statements(chain):
    """what runs once the statement CHAIN[0] is done, in order: ('stmt',
    s) for each statement after it in its own body, and -- when that
    body runs out -- after the statement holding it, and so on out, up
    to the defun's (or a lambda's) own body.  Leaving a loop's body is
    ('leave', the statement holding that loop): past it is where the
    loop is over."""
    while chain:
        for s in after(chain):
            yield "stmt", s
        kind = chain[0][2]
        if kind not in ("other", "loop") or len(chain) < 2:
            return
        if kind == "loop":
            yield "leave", chain[1][0]
        chain = chain[1:]


def loop_level(chain):
    """the chain from the innermost loop around the site outward --
    its first entry is the statement holding the loop -- or None"""
    for i, (_, _, kind) in enumerate(chain):
        if kind == "loop":
            return chain[i + 1:] or None
    return None


def reads_again(chain, target):
    """the object is looked at straight after the write -- (entget X) or
    (entlast) in the next statements -- so the write is checked by its
    effect, not its answer"""
    key = ch_text(target)
    for s in after(chain, REACH):
        for f in walk(s):
            if head(f) == "entlast":
                return True
            if head(f) == "entget" and len(f) > 1 and key \
                    and ch_text(f[1]) == key:
                return True
    return False


def reads_lock_bit(nodes):
    """do NODES read or clear a layer's lock bit?"""
    for f in nodes:
        h = head(f)
        if h in ("vla-get-lock", "vla-put-lock"):
            return True
        if h in ("logand", "logior", "boole"):
            # 4 is the lock, 5 the freeze-and-lock of the ensure-layers;
            # (~ 4) and -5 clear it.  Not 7: (logand 7 (cdr (assoc 70
            # ed))) is a DIMENSION's type, and has nothing to do with it
            for x in f[1:]:
                if head(x) == "~" and len(x) > 1 and is_sym(x[1]) and \
                        x[1] in ("4", "5"):
                    return True
                if is_sym(x) and x in ("4", "5", "-5", "-6"):
                    return True
        if h in ("vlax-get", "vlax-get-property", "vlax-put",
                 "vlax-put-property") and any(
                (isinstance(x, Str) and x.lower() == "lock") or
                quoted_name(x) == "lock" for x in f[1:]):
            return True
    return False


ASK_FNS = {"getkword", "getstring", "getint", "getreal", "getpoint",
           "getdist", "getangle", "getcorner", "getorient"}


def clears_lock(nodes):
    """do NODES write a layer's lock bit -- an entmod of a record's 70,
    or vla-put-Lock -- having read it?"""
    if not reads_lock_bit(nodes):
        return False
    if any(head(f) == "vla-put-lock" for f in nodes):
        return True
    # the record's 70 rebuilt -- (subst (cons 70 ...) (assoc 70 ed) ed),
    # often into ED ahead of one entmod for every fix -- and written
    return any(head(f) == "entmod" for f in nodes) and any(
        head(f) == "subst" and len(f) > 1 and
        re.match(r"\(cons 70 |'\(70 \. ", ch_text(f[1]))
        for f in nodes)


def unlocks(nodes):
    """W1: the layer helper CLEARS the lock when the layer exists -- a
    helper that only reads it, to say so, still leaves it on"""
    if clears_lock(nodes):
        return True
    return any(head(f) in COMMANDS and any(
        isinstance(x, Str) and x.upper().lstrip("_") in ("UNLOCK", "U")
        for x in f) for f in nodes)


# ---------------------------------------------------------------------
#  the survey
# ---------------------------------------------------------------------

def rel(path):
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def fmt(pv):
    return "param" if isinstance(pv, tuple) else pv.lower()


class Site:
    def __init__(self, path, d, form, kind, rule, prov, why):
        self.path, self.defun, self.form = path, str(d[1]), form
        self.kind, self.rule, self.prov, self.why = kind, rule, prov, why
        self.line = getattr(form, "line", 0) or d.line

    def rel(self):
        return rel(self.path)

    def what(self):
        """the baseline's fingerprint: the write as written, no line
        number, so an edit elsewhere in the file does not stale it.  The
        WHOLE write: past 80 characters the rest is carried as a hash,
        so two FILLETs that differ only in their tail are two sites"""
        t = " ".join(ch_text(self.form).split())
        shown = t[:80].replace("|", "/")
        if len(t) > 80:
            shown += " #" + hashlib.sha1(t.encode("utf-8")).hexdigest()[:8]
        return shown

    def key(self):
        """what a baseline line is matched on: the tool, the defun and
        the write -- not the tier, so one line covers a tool's lisp/
        file, its shared/ twin and its dated releases/ copy"""
        return (tool_stem(self.path), self.defun.lower(), self.what())


#: a called helper's namespace -- (lab:ensure-layer, (paddle--3d --
#: which the grouped build may spell (cal:ensure-layer
CALL_NS = re.compile(r"\((?:[a-z][a-z0-9]*:|[a-z][a-z0-9]*--)(?=[^\s()])")


def norm_calls(text):
    """TEXT as needs= compares it: one line, lower case, every called
    helper's namespace blanked"""
    return CALL_NS.sub("(*:", " ".join(text.split()).lower())


#: a releases/ twin's date and REV: PADDLE_092326_REV117 is PADDLE
DATED_TAIL = re.compile(r"_\d{6}_REV[\d-]+$", re.I)


def tool_stem(path):
    """lisp/paddle/PADDLE.lsp, shared/parts/PADDLE.lsp and
    releases/PADDLE_092326_REV117.lsp are all 'paddle'"""
    return DATED_TAIL.sub("", pathlib.Path(str(path)).stem).lower()


def target_key(k, target, info):
    """what names the object, for GATED: for an entmod, the X of the
    (entget X) its alist was read from -- two entmods of one dimension
    hand in two different alists -- else the target as written"""
    if k != "entmod":
        return ch_text(target)
    e, seen = target, set()
    while True:
        if head(e) == "entget" and len(e) > 1:
            return ch_text(e[1])
        if head(e) in SPINE:
            picks = [e[i] for i in SPINE[head(e)] if -len(e) < i < len(e)]
            if not picks:
                break
            e = picks[0]
            continue
        if is_sym(e) and e.lower() in info.declared and \
                e.lower() not in seen:
            seen.add(e.lower())
            got = [x for x in info.assigns.get(e.lower(), [])
                   if head(x) == "entget" or head(x) in SPINE]
            if got:
                e = got[0]
                continue
        break
    return ch_text(e)


#: file text -> its forms, as check_osnap keeps them: a releases/ twin
#: is byte-for-byte its lisp/ file until the next banner bump, so the
#: three tiers are mostly one parse.  Nothing changes a tree in place.
_FORMS = {}


def forms_of(text):
    forms = _FORMS.get(text)
    if forms is None:
        forms = _FORMS[text] = ch.read_forms(decomment(text))
    return forms


class Survey:
    """One tier, read once, and every write in it judged."""

    def __init__(self, paths):
        self.infos, self.where = [], []
        for path in paths:
            if any(s in path.parts for s in SKIP_DIRS):
                continue
            forms = forms_of(path.read_text(encoding="utf-8",
                                            errors="replace"))
            for top in forms:
                for f in walk(top):
                    if head(f) in ("defun", "defun-q") and len(f) > 2 \
                            and is_sym(f[1]):
                        self.infos.append(Info(f, len(self.infos)))
                        self.where.append(path)
        self.byname, self.by_file, self._texts = {}, {}, {}
        for info in self.infos:
            self.byname.setdefault(info.name, info)
            self.by_file.setdefault((self.where[info.idx], info.name), info)
        self.callsites = {}         # name -> [(call form, caller Info)]
        self.glob = {}              # global -> [(expression, Info)]
        for info in self.infos:
            for f in info.nodes:
                h = head(f)
                if h in self.byname and f is not info.d:
                    self.callsites.setdefault(h, []).append((f, info))
            for v, exprs in info.assigns.items():
                if v not in info.declared and not is_literal(v):
                    self.glob.setdefault(v, []).extend(
                        (e, info) for e in exprs)
        # three deep: cfchk:fix-arc-end > snap-end > rebuild-arc >
        # locked-p answers 'refused.  What keeps a helper that merely
        # reads a lock somewhere inside from counting is _about: only a
        # test on the reader's OWN answer is a gate
        self.readers = self._reader_closure(
            {i.name for i in self.infos
             if reads_lock_bit(i.nodes) and not i.makes_layer}, depth=3)
        self.unlockers = self._closure(
            {i.name for i in self.infos
             if clears_lock(i.nodes) and not i.makes_layer}, depth=1)
        self.askers = self._closure(
            {i.name for i in self.infos
             if any(head(f) in ASK_FNS for f in i.nodes)}, depth=8)
        # per defun: the lock readers and unlockers it calls -- most call
        # neither, and screened() is then answered without a walk
        self.lock_calls = [[f for f in i.nodes if head(f) in self.readers]
                           for i in self.infos]
        self.unlock_calls = [[f for f in i.nodes
                              if head(f) in self.unlockers]
                             for i in self.infos]
        self._screened = {}
        self._events = {}
        self.prov = Prov(self)
        self.wrappers = self._wrappers()

    def _reader_closure(self, seed, depth):
        """SEED, and the helpers that HAND BACK a reader's answer, DEPTH
        deep: the reader called in the helper's tail, or in what a
        variable the tail returns is given, or in the test that decides
        whether it is given.  cfchk:fix-arc-end answers snap-end's
        'refused and is one; dchk:review-dim reads a lock three calls
        down, answers a review, and is not."""
        out = set(seed)
        for _ in range(depth):
            more = set()
            for n in out:
                for _, ci in self.callsites.get(n, []):
                    if ci.name in out or ci.name.startswith("c:") or \
                            ci.makes_layer:
                        continue
                    if self._hands_back(ci, out):
                        more.add(ci.name)
            if not more:
                break
            out |= more
        return out

    def _hands_back(self, info, readers):
        def calls(e):
            return isinstance(e, list) and any(head(g) in readers
                                               for g in walk(e))

        def syms(e):
            if is_sym(e):
                return {e.lower()}
            return {x.lower() for g in walk(e) if isinstance(g, list)
                    for x in g if is_sym(x)} if isinstance(e, list) else set()
        ts, deciders = [], []
        todo = list(ch.body_of(info.d)[-1:])
        while todo:                  # the tails, and the tests choosing them
            st = todo.pop()
            h = head(st)
            if h == "if":
                deciders.append(st[1] if len(st) > 1 else None)
                todo += st[2:4]
            elif h == "progn":
                todo += st[-1:]
            elif h == "cond":
                for cl in st[1:]:
                    if isinstance(cl, list) and cl:
                        deciders.append(cl[0])
                        todo += cl[-1:]
            elif h == "setq" and len(st) > 2:
                ts.append(st[-1])
            elif h not in LOOPS and h not in ("princ", "prompt"):
                ts.append(st)
        if any(calls(t) for t in ts + deciders):
            return True
        # ...or a variable either one reads -- (setq r (rebuild-arc ...))
        # then (cond ((eq r 'refused) 'refused) ...)
        tv = set().union(*[syms(t) for t in ts + deciders]) & info.declared
        if any(calls(e) for v in tv for e in info.assigns.get(v, [])):
            return True
        for f in info.nodes:
            if head(f) in ("if", "cond"):
                tests = [f[1]] if head(f) == "if" and len(f) > 1 else \
                    [cl[0] for cl in f[1:] if isinstance(cl, list) and cl]
                if any(calls(t) for t in tests) and any(
                        head(g) == "setq" and any(
                            is_sym(x) and x.lower() in tv for x in g[1::2])
                        for g in walk(f)):
                    return True
        return False

    def _closure(self, seed, depth):
        """SEED and the helpers that call into it, DEPTH deep -- not a
        command, and not a layer maker (an ensure-layer reads the bit
        of its own layer, which says nothing about a selection)"""
        out = set(seed)
        for _ in range(depth):
            more = {ci.name for n in out
                    for _, ci in self.callsites.get(n, [])
                    if not ci.name.startswith("c:") and not ci.makes_layer}
            if more <= out:
                break
            out |= more
        return out

    def _reads_lock_of(self, g, rs, info):
        """G is a call of a lock reader about a selection sharing a root
        with RS"""
        return head(g) in self.readers and any(roots(a, info) & rs
                                               for a in g[1:])

    def _about(self, form, rs, info):
        """FORM tests a lock reader's answer about a selection sharing a
        root with RS: the call itself, or a variable set straight from
        one -- (setq locked (xft:locked-layers ss)) ... (if locked ...).
        No further: a value that only passed THROUGH a helper that reads
        a lock somewhere inside is not an answer about the lock."""
        for g in (walk(form) if isinstance(form, list) else [form]):
            if self._reads_lock_of(g, rs, info):
                return True
            for x in (g if isinstance(g, list) else [g]):
                if is_sym(x) and x.lower() in info.declared and any(
                        self._reads_lock_of(e, rs, info)
                        for e in info.assigns.get(x.lower(), [])):
                    return True
        return False

    def _asks(self, form, info):
        """FORM puts a question to the drafter, or reads the answer to
        one -- a variable INFO sets from a get* or an asking helper"""
        for g in walk(form) if isinstance(form, list) else [form]:
            h = head(g)
            if h in ASK_FNS or h in self.askers:
                return True
            for x in (g if isinstance(g, list) else [g]):
                if is_sym(x) and x.lower() in info.declared and any(
                        head(n) in ASK_FNS or head(n) in self.askers
                        for e in info.assigns.get(x.lower(), [])
                        for n in walk(e) if isinstance(e, list)):
                    return True
        return False

    def gates(self, node, info):
        """(test, is-the-node-in-a-branch) for every if/cond around NODE
        in INFO, innermost first: the tests a run passes to reach it"""
        out = []
        child, parent = node, info.parent.get(id(node))
        while parent is not None:
            h = head(parent)
            if h == "if" and len(parent) > 1:
                out.append(([parent[1]], child is not parent[1]))
            elif h == "cond":
                tests = []
                for cl in parent[1:]:
                    if isinstance(cl, list) and cl:
                        tests.append(cl[0])
                        if cl is child:
                            break
                out.append((tests, True))
            child, parent = parent, info.parent.get(id(parent))
        return out

    def gated(self, site, target, info):
        """SITE sits in a branch the run reaches only past a TESTED write
        to a related object -- ((not (dchk:merge-lines la lb info)) ...)
        then ((= ans "Merge") (dchk:set-color ea ...)): the merge took,
        so the layer the pair shares takes the colour too"""
        rs = roots(target, info) if target is not None else set()
        if not rs:
            return False
        for tests, br in self.gates(site, info):
            if not br:
                continue
            for t in tests:
                for g in walk(t):
                    k = write_kind(g, self.wrappers)
                    if k and not k.startswith("cmd") and \
                            roots(target_of(g, k), info) & rs:
                        return True
        return False

    def screened(self, target, info, site=None):
        """Were the object's locks dealt with before SITE writes it?

          (a) an unlock-for-the-run of the layers of a selection the
              object comes from, BEFORE the write and NOT behind a
              question -- an unlock the drafter can refuse is an unlock
              the run goes on without;
          (b) SITE sits in a branch of an if/cond whose test reads a
              lock reader's answer about that selection -- the run was
              stopped, or steered round the lock.

        A reader whose answer is only reported, or an offer to unlock,
        is neither: that is the DIMCHECK shape, where a No at 'Unlock
        for this run?' carried on and reported every refused move as
        made."""
        if target is None or not (self.lock_calls[info.idx] or
                                  self.unlock_calls[info.idx]):
            return False
        key = (id(target), id(site), info.idx)
        if key in self._screened:
            return self._screened[key]
        rs = roots(target, info)
        ok = False
        if rs:
            before = getattr(site, "line", 10 ** 9)
            for f in self.unlock_calls[info.idx]:
                if f.line < before and any(
                        roots(a, info) & rs for a in f[1:]) and not any(
                        br and any(self._asks(t, info) for t in tests)
                        for tests, br in self.gates(f, info)):
                    ok = True
                    break
            if not ok and site is not None and self.lock_calls[info.idx]:
                ok = any(br and any(self._about(t, rs, info) for t in tests)
                         for tests, br in self.gates(site, info))
        self._screened[key] = ok
        return ok

    def binds(self, f, info):
        """{var: list} for each foreach around F in INFO that binds var
        and never setq's it inside -- F sees the list's element there,
        whatever else the defun gives a local of the same name.  A
        lambda between them that binds the name shadows it."""
        out, shadow = {}, set()
        child, p = f, info.parent.get(id(f))
        while p is not None:
            h = head(p)
            if h == "lambda":
                shadow |= set(ch.arglist(p)[0]) | set(ch.arglist(p)[1])
            elif h == "foreach" and len(p) > 3 and is_sym(p[1]) and \
                    child is not p[2]:
                v = p[1].lower()
                if v not in out and v not in shadow and not any(
                        head(g) == "setq" and any(
                            is_sym(x) and x.lower() == v for x in g[1::2])
                        for st in p[3:] for g in walk(st)):
                    out[v] = p[2]
                shadow.add(v)
            child, p = p, info.parent.get(id(p))
        return out

    def resolve(self, f, k, info, wrappers=None):
        """the provenance of what F writes"""
        wrappers = self.wrappers if wrappers is None else wrappers
        bind = self.binds(f, info)
        if k.startswith("via "):
            w = wrappers.get(k[4:], UNKNOWN)
            if not isinstance(w, tuple):
                return w
            return self.prov.answer(self.prov.ev, f[w[1] + 1], info, bind) \
                if w[1] + 1 < len(f) else UNKNOWN
        t = target_of(f, k)
        if t is None:
            return UNKNOWN
        return self.prov.answer(self.prov.entity if k == "entmod"
                                else self.prov.ev, t, info, bind)

    def events(self, info):
        """(form, mode, chain) for every call INFO evaluates, walked once
        and kept: the wrapper passes, the sites and the call modes all
        read the same walk"""
        ev = self._events.get(info.idx)
        if ev is None:
            ev = self._events[info.idx] = []
            visit_all(info.d, lambda f, m, c: ev.append((f, m, c))
                      if head(f) else None)
        return ev

    def _wrappers(self):
        """helpers whose VALUE is a write's answer: their call sites are
        judged as the write, the object resolved through the arguments"""
        wrappers = {}
        for _ in range(8):
            grew = False
            for info in self.infos:
                if info.name in wrappers or info.name.startswith("c:"):
                    continue
                got = []
                for f, mode, chain in self.events(info):
                    if mode not in ("return", "rtest"):
                        continue
                    k = write_kind(f, wrappers)
                    if k and not k.startswith("cmd"):
                        got.append(self.resolve(f, k, info, wrappers))
                if got:
                    wrappers[info.name] = combine(got)
                    grew = True
            if not grew:
                break
        return wrappers

    def reported(self, info, var, flags):
        """is the count VAR ever said?  Read in INFO beyond its own
        bumps, or handed back to a caller that keeps the answer"""
        if var == "ssadd":
            return True
        if [f for f in own_uses(info, var) if f is not info.d]:
            return True
        # handed back bare: said only if some caller keeps the answer
        return var in flags and any(mode != "discard"
                                    for mode in self.call_modes(info.name))

    def claim_after_loop(self, chain, info, flags, steps):
        """a site inside a loop whose body keeps no count anybody is
        told: a claim among the statements that run once the loop is
        done is about what the loop did, and the loop's writes are all
        there is to feed it.  dchk:tut-demo erased the practice drawing
        with (entdel (ssname ss2 i)) in a repeat, then said "Practice
        drawing erased." over lines on a locked layer 0.  When the loop
        DOES keep a count the report says, that count is what the report
        is about, and whether it is honest is the tally rule's question
        -- and the same for each loop around it the search walks out
        of."""
        level = loop_level(chain)
        if level is None or self.keeps_count(level[0][0], info, flags,
                                              steps):
            return None
        seen = 0
        for what, s in next_statements(level):
            if what == "leave":
                if self.keeps_count(s, info, flags, steps):
                    return None
                continue
            c = claim_in(s)
            if c:
                return c
            seen += 1
            if seen >= CLAIM_REACH:
                return None
        return None

    def keeps_count(self, holder, info, flags, steps):
        """the loop in HOLDER keeps a count somebody is told"""
        for g in walk(holder):
            t = tally_of(g, flags, steps) if isinstance(g, list) else None
            if t and self.reported(info, t, flags):
                return True
        return False

    def call_modes(self, name):
        """the mode each call of NAME is evaluated in"""
        if name not in self._modes:
            out = []
            for caller in {id(ci): ci for _, ci in
                           self.callsites.get(name, [])}.values():
                out += [m for f, m, c in self.events(caller)
                        if head(f) == name]
            self._modes[name] = out
        return self._modes[name]

    def run(self):
        """(sites, exempt): every W2/W3 site, and every exempted write
        with the reason it is exempt"""
        self._modes = {}
        sites, exempt, blind = [], [], {}
        for info in self.infos:
            path = self.where[info.idx]
            flags = returned_vars(info.d)
            steps = index_vars(info)
            checked, pending = [], []

            def fn(f, mode, chain):
                k = write_kind(f, self.wrappers)
                if not k:
                    return
                if mode == "return" and not k.startswith("cmd"):
                    return        # a wrapper: judged at its call sites
                target = target_of(f, k)
                w = self.wrappers.get(k[4:]) if k.startswith("via ") else None
                if isinstance(w, tuple):
                    # the argument the wrapper writes, not its first one
                    target = f[w[1] + 1] if w[1] + 1 < len(f) else None
                key = target_key(k, target, info)
                if not k.startswith("cmd") and (
                        mode in ("use", "rtest") or
                        (isinstance(mode, tuple) and
                         mode[1].lower() in info.reads)):
                    checked.append((key, f.line))
                    return
                pending.append((f, k, chain, target, key))
            for f, mode, chain in self.events(info):
                fn(f, mode, chain)

            for f, k, chain, target, key in pending:
                pv = self.prov.param(info, self.resolve(f, k, info))
                why = None
                # the nearest reason first: this write's own test, then
                # this defun's, then the object's history
                if any(kk == key and ln <= f.line for kk, ln in checked) \
                        or self.gated(f, target, info):
                    why = "GATED"
                elif reads_again(chain, target) or (
                        k in ("cmd FILLET", "cmd CHAMFER") and any(
                            head(g) == "entlast" and g.line >= f.line
                            for g in info.nodes)) or (
                        # an erase is looked at by asking, any time
                        # after, whether the object is still there --
                        # ad:scrap answers (not (entget en)) at its end
                        k in ("entdel", "catch entdel") and any(
                            head(g) == "entget" and len(g) > 1 and
                            g.line > f.line and ch_text(g[1]) ==
                            ch_text(target) for g in info.nodes)):
                    why = "OBSERVED"
                elif pv in (TABLE, FRESH):
                    why = pv
                elif self.screened(target, info, f) or pv == SCREENED:
                    why = SCREENED
                if why:
                    exempt.append(Site(path, info.d, f, k, why, fmt(pv), ""))
                    continue
                if k.startswith("cmd"):
                    sites.append(Site(path, info.d, f, k, "W2", fmt(pv),
                                      "an edit command: its answer cannot "
                                      "be read"))
                    continue
                tally = tally_after(chain, flags, steps)
                if tally and not self.reported(info, tally, flags):
                    tally = None      # counted, and never told anyone
                claim = claim_after(chain)
                lclaim = None if tally or claim else \
                    self.claim_after_loop(chain, info, flags, steps)
                if tally or claim or lclaim or pv == CLAYER:
                    sites.append(Site(
                        path, info.d, f, k, "W2", fmt(pv),
                        ("then (%s counted)" % tally) if tally else
                        ("then \"%s\"" % claim) if claim else
                        ("then, after the loop, \"%s\"" % lclaim) if lclaim
                        else "scratch drawn on the drafter's current layer"))
                else:
                    sites.append(Site(path, info.d, f, k, "W3", fmt(pv),
                                      "answer thrown away"))
                    blind.setdefault(info.name, self.resolve(f, k, info))

        # helpers holding such a write whose every answer is a literal T
        liars = {n for n in blind
                 if self.byname.get(n) is not None and
                 all(is_sym(t) and t.lower() == "t" for t in
                     tails(ch.body_of(self.byname[n].d)[-1:], []) or [None])}

        # a statement calling a helper whose write goes unlooked-at,
        # then a count or a claim
        for info in self.infos:
            path = self.where[info.idx]
            flags = returned_vars(info.d)
            steps = index_vars(info)

            def fn2(f, mode, chain):
                h = head(f)
                if h not in blind or h == info.name or h in self.wrappers:
                    return
                # a helper that answers T whatever its write did, tested:
                # (if (spachk:unstash e) (setq n (1+ n))) counted every
                # colour it was refused as put back
                par = info.parent.get(id(f))
                liar = h in liars and head(par) == "if" and \
                    par[1] is f and len(par) > 2 and \
                    tally_of(par[2], flags, steps)
                if not liar and (mode != "discard" or not chain or
                                 chain[0][0] is not f):
                    return
                pv = blind[h]
                if isinstance(pv, tuple):
                    if pv[1] + 1 >= len(f) or \
                            self.screened(f[pv[1] + 1], info, f) or \
                            self.gated(f, f[pv[1] + 1], info):
                        return
                    pv = self.prov.param(info, self.prov.answer(
                        self.prov.ev, f[pv[1] + 1], info,
                        self.binds(f, info)))
                if pv in EXEMPT:
                    return
                if liar:
                    sites.append(Site(
                        path, info.d, f, "calls " + h, "W2", fmt(pv),
                        "which answers T whatever its write did, then "
                        "(%s counted)" % tally_of(par[2], flags, steps)))
                    return
                tally = tally_after(chain, flags, steps)
                if tally and not self.reported(info, tally, flags):
                    tally = None
                claim = claim_after(chain)
                lclaim = None if tally or claim else \
                    self.claim_after_loop(chain, info, flags, steps)
                if tally or claim or lclaim:
                    sites.append(Site(
                        path, info.d, f, "calls " + h, "W2", fmt(pv),
                        ("then (%s counted)" % tally) if tally else
                        ("then \"%s\"" % claim) if claim else
                        ("then, after the loop, \"%s\"" % lclaim)))
            for f, mode, chain in self.events(info):
                fn2(f, mode, chain)
        seen, out = set(), []
        for s in sites:
            key = (s.rel(), s.line, s.rule, s.kind)
            if key not in seen:
                seen.add(key)
                out.append(s)
        return out, exempt

    def missing(self, site, needs):
        """the (token, defun) pairs of a baseline line's needs= that the
        site's file no longer carries: each token is looked for in the
        text of the defun it names -- the site's own when none is named
        -- as read (comments do not count), in the same file.  A called
        helper's namespace is not compared: the grouped build calls
        (cal:ensure-layer lab:*laya* ...) where lisp/ calls
        (lab:ensure-layer lab:*laya* ...), and it is the same promise"""
        gone = []
        for tok, dn in needs:
            name = dn or site.defun.lower()
            info = self.by_file.get((site.path, name))
            if info is None or norm_calls(tok) not in self._text(info):
                gone.append((tok, name))
        return gone

    def _text(self, info):
        t = self._texts.get(info.idx)
        if t is None:
            t = self._texts[info.idx] = norm_calls(ch_text(info.d))
        return t

    def layer_helpers(self):
        """W1: (count of layer makers, [(path, defun, the making form)
        for each that leaves a lock on])"""
        makers = [i for i in self.infos if i.makes_layer]
        return len(makers), [(self.where[i.idx], i.d, i.layer_maker)
                             for i in makers if not unlocks(i.nodes)]


# ---------------------------------------------------------------------
#  baseline, report
# ---------------------------------------------------------------------

def parse_baseline(lines):
    """(base, bad) from baseline LINES.  BASE maps (tool, defun, what)
    to (file, defun, needs, reason); NEEDS is [(token, defun or None)].
    BAD
    holds every line that is not file|defun|what|needs=...|reason with
    a token and a reason: a line that cannot say what it rests on is
    not accepted"""
    base, bad = {}, []
    for ln in lines:
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("|", 4)
        if len(parts) != 5 or not parts[3].startswith("needs=") or \
                not parts[4].strip():
            bad.append(ln)
            continue
        f, d, w, needs, why = parts
        toks = []
        for t in needs[len("needs="):].split(","):
            tok, _, at = t.strip().partition("@")
            if tok.strip():
                toks.append((tok.strip(), at.strip().lower() or None))
        if not toks:
            bad.append(ln)
            continue
        base[(tool_stem(f), d.lower(), w)] = (f, d, toks, why)
    return base, bad


def load_baseline(path=None):
    """parse_baseline over tools/write_baseline.txt"""
    path = pathlib.Path(path or BASELINE)
    if not path.is_file():
        return {}, []
    return parse_baseline(path.read_text(encoding="utf-8").splitlines())


def report(paths, base, out=print, show=False, met=None, broken=None):
    """Survey PATHS as one tier and print every finding; return
    (findings, layer helpers, sites).  MET, when given, collects the
    baseline keys this tier matched and whose needs= still hold, for
    the stale-line report; BROKEN, when given, maps a key whose site
    was met but whose needs= no longer holds to the tokens gone."""
    sv = Survey(paths)
    nlh, w1 = sv.layer_helpers()
    sites, exempt = sv.run()
    nfind = 0
    for path, d, mk in w1:
        nfind += 1
        out("%s:%d: W1 %s makes its layer when it is missing but never "
            "clears the lock when it is there: entmake draws onto a locked "
            "layer and entdel refuses there, so what goes up cannot come "
            "down.  Clear bit 4 of group 70 when the layer exists%s."
            % (rel(path), getattr(mk, "line", 0) or d.line, d[1],
               " (vla-put-Lock ... :vlax-false after the vla-Add)"
               if head(mk) == "vla-add" else ""))
    for s in sorted(sites, key=lambda s: (s.rule, s.rel(), s.line)):
        key = s.key()
        gone = sv.missing(s, base[key][2]) \
            if s.rule == "W2" and key in base else []
        ok = s.rule == "W2" and key in base and not gone
        if ok:
            if met is not None:
                met.add(key)
            if not show:
                continue
        elif s.rule == "W3" and not show:
            continue
        if gone and broken is not None:
            broken.setdefault(key, gone)
        nfind += s.rule == "W2" and not ok
        out("%s:%d: %s%s %s [%s] object=%s %s\n    what: %s%s" % (
            s.rel(), s.line, s.rule, " (baselined)" if ok else "",
            s.defun, s.kind, s.prov, s.why, s.what(),
            ("\n    its baseline line no longer holds: " + ", ".join(
                "%s is gone from %s" % (t, dn) for t, dn in gone))
            if gone else ""))
    if show:
        for s in sorted(exempt, key=lambda s: (s.rel(), s.line)):
            out("%s:%d: exempt %s %s [%s]  %s" % (
                s.rel(), s.line, s.rule, s.defun, s.kind, s.what()))
    return nfind, nlh, len(sites)


def stale(base, met):
    """baseline lines whose write the tree no longer has -- gone,
    reworded, looked at now, or no longer resting on what its needs=
    names -- as (file, defun, what)"""
    return [(f, d, w) for key, (f, d, needs, why) in sorted(base.items())
            if key not in met for w in [key[2]]]


TIERS = {"lisp": LISP_DIR, "shared": PARTS_DIR, "releases": RELEASES_DIR}


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Every write whose answer nobody reads, followed by a "
                    "claim that it happened (see the module docstring).")
    ap.add_argument("--tier", default="all",
                    choices=("lisp", "shared", "releases", "all"),
                    help="one tier; the default reads all three, as "
                         "check_handlers does -- a dated twin is what a "
                         "shop pins to")
    ap.add_argument("--list", action="store_true",
                    help="also list W3 (thrown away, nothing claimed), "
                         "the baselined sites, and every exempt write "
                         "with the reason it is exempt")
    a = ap.parse_args(argv)
    base, bad = load_baseline()
    total = len(bad)
    for ln in bad:
        print("check_writes: malformed baseline line -- every line is "
              "file|defun|what|needs=TOKEN[@DEFUN][,...]|reason: %s" % ln)
    want = ["lisp", "shared", "releases"] if a.tier == "all" else [a.tier]
    met, broken = set(), {}
    for t in want:
        nfind, nlh, nsites = report(
            lsp_files(TIERS[t]), base, show=a.list,
            met=met if t == "lisp" else None,
            broken=broken if t == "lisp" else None)
        total += nfind
        print("check_writes: %s -- %d layer helper(s), %s"
              % (t, nlh, ("%d finding(s)" % nfind) if nfind else
                 "every write that is counted or claimed is looked at"))
    if "lisp" in want:
        for f, d, w in stale(base, met):
            total += 1
            gone = broken.get((tool_stem(f), d.lower(), w))
            print("check_writes: stale baseline line -- %s|%s|%s: %s" % (
                f, d, w, ("what it rests on is gone: " + ", ".join(
                    "%s from %s" % (t, dn) for t, dn in gone)) if gone else
                "the write is gone, reworded, or now looked at"))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
