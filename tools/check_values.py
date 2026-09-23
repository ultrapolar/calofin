#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Values a builtin hands back that AutoCAD does not promise.

The test VM was kinder than AutoCAD in a handful of places, and each one
let a tool pass its suite while a drafter got something else.  This
check names every call site whose meaning depends on one of those
answers and that does not look at it:

  rtos-ftin       feet-inch rtos text that is WRITTEN INTO THE DRAWING
                  -- a TEXT or MTEXT entity, a dimension's text, a
                  leader's note -- whether the mode is 3 or 4, a knob or
                  computed mode nothing on the way in rules 3 and 4 out
                  of, or no mode at all (the drawing's LUNITS).  rtos
                  FOLLOWS DIMZIN: at 0 (acad.dwt), 2 or 8 a whole foot
                  prints 15' -- the notation SPACHECK, COVERCHECK and
                  LINFINCHECK reject -- and UNITMODE 1 respells it
                  again (1'3-1/2").  The same tool writes a different
                  string in every drawing it runs in, and the sheet
                  carries it.  The fix is the tool's own <prefix>:ftin
                  (v mode prec), built by ARITHMETIC (cal:ftin in the
                  library, one swap line in mirror_shared, the way
                  tool:ink works) -- never a DIMZIN bind round rtos,
                  which overrides the current dimension style.  A knob
                  mode goes behind a test that sends 3 and 4 elsewhere:
                      (if (member m '(3 4)) (x:ftin d m p) (rtos d m p))
                  and a mode left to LUNITS behind the same test of
                  (getvar "LUNITS").  Text printed for the drafter to
                  read -- a prompt, a princ, an alert -- is NOT flagged:
                  there the drafter's own DIMZIN chose a valid spelling.
  rtos-shape      rtos of CDATE / DATE, or rtos text read by POSITION
                  (substr, vl-string-search, vl-string-position) or as a
                  value (read), directly or through a local.  DIMZIN 8
                  trims trailing zeros and 4 drops the leading one, so
                  the digits move -- and (read "12") is an INTEGER.
  rtos-bound      a number printed as an INCLUSIVE limit (max, min,
                  between, at most, or less ...) inside a loop that
                  asks again when the answer fails a test that names it
                  -- a comparison, or a helper handed the limit.
                  rtos rounds to nearest, so a max that rounds UP is a
                  max the loop refuses when the drafter types it back.
                  The fix floors a max (ceils a min) at the displayed
                  precision; a value handed over through a helper named
                  *floor* or *ceil* is that fix.  Read at every rtos, at
                  every <prefix>:ftin (it rounds to nearest too), and at
                  every formatter of the file's own that returns one of
                  those on its first argument.
  vl-sort-dedupe  (vl-sort lst '<) where the comment above says the sort
                  drops duplicates.  AutoCAD's vl-sort drops only EQ
                  items -- integers and symbols.  Two equal REALS both
                  stay.  Drop them by hand: skip r when (equal r prev).
  getobject-nil   a vlax-get-object or vlax-create-object result tested
                  with vl-catch-all-error-p alone.  Nothing running (or
                  nothing registered) answers NIL, not an error, and nil
                  passes that test.
  typed-angle     angtos output typed into (command ...) in a file that
                  never borrows ANGBASE, ANGDIR and AUNITS: the command
                  reads those digits through the drafter's settings.

WHERE TEXT GOES (rtos-ftin).  A flow pass over each file, per function
and flow-insensitive: rtos text is followed through strcat, list, cons,
append, car/cdr/nth, setq into locals and globals, foreach/mapcar/apply
and the file's own functions (each one summarised: which argument
reaches its return, which reaches the drawing, itself or through a
global), to a SINK -- an entity list's text groups (1, and MTEXT's 3)
in entmake/entmakex/entmod, vla-addtext/-addmtext/-put-textstring, a
TextString put, a TEXT/MTEXT/LEADER command, or the argument after
"_T" in a DIM command.  A sizing use (strlen, a width estimate) is not
a sink, and neither is princ/prompt/alert, nor a colour, a point or
xdata.  A list is one value to the pass, so the ways a finding names
are the candidates: at least one of them carries this site's text.
Text the command takes away again before it returns -- a preview label
swept on every path out -- is a cue, and goes in the baseline with the
sweep named.

Not here, on purpose: ERRNO read without a clear (check_input owns it)
and a discarded entmod (check_writes owns it).

WHAT IT READS.  The hand-edited sources: every .lsp under lisp/ (the
acady matcher excepted) and the shared/parts files mirror_shared does
not generate -- CALOFIN-LIB, CALOFIN-LOADER and LISPLAB's twin.  Every
other file in shared/ and releases/ is generated from those, and
check_standards fails one that is not a fresh regeneration, so a finding
in a generated tier is a finding here, once.

BASELINE.  tools/values_baseline.txt, the check_back pattern: one line
per flagged site that is FINE, file|defun|rule|excerpt|why.  A site not
in it fails; a line whose site has gone is STALE and fails too, so the
file cannot rot.  Two identical sites take two lines, each with its own
reason, paired in file order.  A reason that is empty or UNREVIEWED is
not a reason.  --update-baseline rewrites the file, keeping every reason,
dropping stale lines, and writing a new site as UNREVIEWED -- which is
not accepted.  A defect is fixed, never baselined.

    python3 tools/check_values.py [FILE ...] [--list] [--rule R]
    python3 tools/check_values.py --update-baseline

Exit 0 when the tree and the baseline agree, 1 otherwise, 2 for
--update-baseline with a FILE or --rule scope.
"""

import argparse
import bisect
import collections
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from callib import (LISP_DIR, NOT_A_TOOL, PARTS_DIR, ROOT,  # noqa: E402
                    decomment, lsp_files, read)
from check_handlers import Str, head, is_sym, read_forms  # noqa: E402
from mirror_shared import TOOLS as MIRRORED  # noqa: E402

BASELINE = HERE / "values_baseline.txt"
UNREVIEWED = "UNREVIEWED"
RULES = ("rtos-ftin", "rtos-shape", "rtos-bound", "vl-sort-dedupe",
         "getobject-nil", "typed-angle")

Hit = collections.namedtuple("Hit", "path line defun rule text note")


def sources():
    """The hand-edited .lsp files, in a stable order."""
    out = [p for p in lsp_files(LISP_DIR) if NOT_A_TOOL not in p.parts]
    generated = {name.lower() + ".lsp" for name in MIRRORED}
    return out + [p for p in lsp_files(PARTS_DIR)
                  if p.name.lower() not in generated]


# ---------------------------------------------------------------------
#  Trees.  check_handlers' reader: lists know their line, a string is a
#  Str with its text kept, a quote is (quote x).
# ---------------------------------------------------------------------

DEFUNS = ("defun", "defun-q")
EMPTY = frozenset()
NUM = re.compile(r"^[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$", re.I)


def walk(f, parents=()):
    """(form, parents) for every list under F, outermost parent first."""
    yield f, parents
    inner = parents + (f,)
    for x in f:
        if isinstance(x, list):
            yield from walk(x, inner)


def walk_own(d):
    """walk(D) without descending into a defun nested inside it -- that
    one is visited as a defun of its own."""
    def rec(f, parents):
        yield f, parents
        inner = parents + (f,)
        for x in f:
            if isinstance(x, list) and head(x) not in DEFUNS:
                yield from rec(x, inner)
    return rec(d, ())


def unquote(x):
    while head(x) in ("quote", "function") and len(x) == 2:
        x = x[1]
    return x


def show(x):
    if isinstance(x, Str):
        return '"' + x + '"'
    if isinstance(x, list):
        if head(x) == "quote" and len(x) == 2:
            return "'" + show(x[1])
        return "(" + " ".join(show(y) for y in x) + ")"
    return str(x)


def excerpt(f, n=72):
    s = show(f)
    return s if len(s) <= n else s[:n - 3] + "..."


def index_of(par, child):
    for i, x in enumerate(par):
        if x is child:
            return i
    return -1


def owner(parents):
    for p in reversed(parents):
        if head(p) in DEFUNS and len(p) > 1 and is_sym(p[1]):
            return p
    return None


def name_of(d):
    return str(d[1]) if d is not None else "<top level>"


def arglist(d):
    """(params, locals) of a defun or lambda, lower-cased."""
    lst = d[2] if head(d) in DEFUNS else d[1]
    params, locs, after = [], [], False
    if isinstance(lst, list):
        for x in lst:
            if not is_sym(x):
                continue
            if x == "/":
                after = True
            else:
                (locs if after else params).append(x.lower())
    return params, locs


def syms(f):
    """Every symbol in F, lower-cased."""
    if is_sym(f):
        return {f.lower()}
    out = set()
    if isinstance(f, list):
        for g, _ in walk(f):
            out.update(x.lower() for x in g if is_sym(x))
    return out


#: symbols that say nothing about WHICH value an expression is
NOISE = {"/", "*", "+", "-", "1+", "1-", "abs", "fix", "float", "max",
         "min", "car", "cadr", "caddr", "cdr", "nth", "if", "cond",
         "and", "or", "not", "null", "t", "nil", "sqrt", "expt", "rem",
         "getvar", "quote", "setq", "=", "<", ">", "<=", ">=", "/="}


def names_in(f):
    return {s for s in syms(f) if s not in NOISE and re.search(r"[a-z]", s)}


def mentions(test, what):
    """Does TEST's text name WHAT (a symbol or a form) as a whole token?"""
    w = re.escape(show(what).lower())
    return re.search(r"(?<![^\s()'\"])" + w + r"(?![^\s()'\"])",
                     show(test).lower()) is not None


def path_conds(node, parents, stop):
    """(test, wanted) for every test that has to come out WANTED (true
    or false) for NODE to be evaluated at all, from STOP (a defun, or
    None for the whole top-level form) down: an if's test (true in the
    then branch, false in the else), a while's, every earlier cond
    clause's test (false) and the clause's own (true), the earlier terms
    of an and (true) or an or (false)."""
    chain = list(parents) + [node]
    out = []
    for i in range(len(chain) - 1, 0, -1):
        child, par = chain[i], chain[i - 1]
        if par is stop:
            break
        idx = index_of(par, child)
        if i >= 2 and head(chain[i - 2]) == "cond" \
                and index_of(chain[i - 2], par) >= 1:
            if idx >= 1:
                out.append((par[0], True))      # the clause's own test
            continue
        h = head(par)
        if h == "if" and idx in (2, 3):
            out.append((par[1], idx == 2))
        elif h == "while" and idx >= 2:
            out.append((par[1], True))
        elif h == "and":
            out.extend((t, True) for t in par[1:idx])
        elif h == "or":
            out.extend((t, False) for t in par[1:idx])
        elif h == "cond":
            out.extend((c[0], False) for c in par[1:idx]
                       if isinstance(c, list) and c)
    return out


def tests_before(node, parents, stop):
    return [t for t, _ in path_conds(node, parents, stop)]


# ---------------------------------------------------------------------
#  rtos modes: which ones a path lets through
# ---------------------------------------------------------------------

LUNITS = "(getvar lunits)"          # the mode rtos takes when given none


def is_lunits(x):
    if head(x) != "getvar" or len(x) != 2:
        return False
    a = unquote(x[1])
    return isinstance(a, str) and a.lower() == "lunits"


def mode_key(x):
    return LUNITS if is_lunits(x) else show(x).lower()


def num_of(x, is_m, k):
    if is_m(x):
        return k
    if is_sym(x) and NUM.match(x):
        return float(x)
    return None


def truth(t, is_m, k):
    """T's value when the mode is K, as True / False, or None when the
    test depends on something else."""
    if is_m(t):
        return True                     # a mode is a number: non-nil
    if is_sym(t):
        s = t.lower()
        return True if s == "t" or NUM.match(s) else \
            False if s == "nil" else None
    if isinstance(t, Str):
        return True
    h, a = head(t), t[1:]
    if h in ("not", "null") and len(a) == 1:
        r = truth(a[0], is_m, k)
        return None if r is None else not r
    if h in ("and", "or"):
        rs = [truth(x, is_m, k) for x in a]
        stop = h == "or"                # the value that settles it
        if stop in rs:
            return stop
        return (not stop) if all(r is not None for r in rs) else None
    if h in ("=", "eq", "equal", "/=", "<", ">", "<=", ">=") \
            and len(a) >= 2:
        if h in ("eq", "equal", "/="):
            a = a[:2]
        vs = [num_of(x, is_m, k) for x in a]
        if None in vs:
            return None
        pairs = list(zip(vs, vs[1:]))
        return {"=": all(x == y for x, y in pairs),
                "eq": vs[0] == vs[1], "equal": vs[0] == vs[1],
                "/=": vs[0] != vs[1],
                "<": all(x < y for x, y in pairs),
                ">": all(x > y for x, y in pairs),
                "<=": all(x <= y for x, y in pairs),
                ">=": all(x >= y for x, y in pairs)}[h]
    if h in ("member", "vl-position") and len(a) == 2:
        v, lst = num_of(a[0], is_m, k), unquote(a[1])
        if head(lst) == "list":
            lst = lst[1:]
        if v is None or not isinstance(lst, list) or \
                not all(is_sym(y) and NUM.match(y) for y in lst):
            return None
        return any(float(y) == v for y in lst)
    return None


def aliases(d, key, cache):
    """Locals of D set straight from the mode expression KEY."""
    ck = (id(d), key)
    if ck not in cache:
        out = set()
        if d is not None:
            for f, _ in walk_own(d):
                if head(f) == "setq":
                    for i in range(1, len(f) - 1, 2):
                        if is_sym(f[i]) and mode_key(f[i + 1]) == key:
                            out.add(f[i].lower())
        cache[ck] = out
    return cache[ck]


def rtos_kind(f, parents, d, cache):
    """How an rtos call can come out feet-inch: 'ftin' (mode 3 or 4
    written), 'knob' (a mode from a variable or a call), 'lunits' (no
    mode: the drawing's), or None when it cannot."""
    m = unquote(f[2]) if len(f) >= 3 else None
    if m is None or (is_sym(m) and m.lower() == "nil"):
        kind, key = "lunits", LUNITS
    elif is_sym(m) and m in ("3", "4"):
        return "ftin"
    elif (is_sym(m) and NUM.match(m)) or isinstance(m, Str):
        return None
    else:
        key = mode_key(m)
        kind = "lunits" if key == LUNITS else "knob"
    names = aliases(d, key, cache)

    def is_m(x):
        return mode_key(x) == key or (is_sym(x) and x.lower() in names)

    conds = path_conds(f, parents, d)
    if all(any(truth(t, is_m, k) is (not want) for t, want in conds)
           for k in (3.0, 4.0)):
        return None                     # 3 and 4 both go elsewhere
    return kind


# ---------------------------------------------------------------------
#  Where text goes
# ---------------------------------------------------------------------

#: builtins whose value carries the text of every argument
PASS = frozenset("""strcat list cons append vl-list* reverse subst car cdr
caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
cadddr nth last member assoc vl-remove strcase substr vl-string-subst
vl-string-trim vl-string-left-trim vl-string-right-trim
vl-string-translate vl-princ-to-string vl-prin1-to-string princ prin1
print acad_strlsort vl-sort vl-remove-if vl-remove-if-not vl-member-if
vl-member-if-not""".split())
#: builtins that write their arguments into the drawing -- an entity
#: list only through its text groups, since (cons 62 c) evaluates to
#: nothing here (see TEXT_GROUPS)
SINKS = frozenset("""entmake entmakex entmod vla-addtext vla-addmtext
vla-put-textstring vla-put-textoverride vla-settext""".split())
PUTS = ("vlax-put-property", "vlax-put", "setpropertyvalue")
INVOKES = ("vlax-invoke", "vlax-invoke-method")
TEXT_PROPS = ("textstring", "textoverride", "addtext", "addmtext",
              "settext")
TEXT_COMMANDS = ("TEXT", "MTEXT", "DTEXT", "LEADER", "QLEADER", "MLEADER")
COMMANDS = ("command", "vl-cmdf", "command-s")
#: the DXF groups an entity shows as text: 1, and 3 for MTEXT's leading
#: chunks.  (cons 62 c), (cons 8 layer), (cons 1000 xdata) carry none.
TEXT_GROUPS = ("1", "3")
#: how many of the ways a site reaches the drawing its finding names
WITNESSES = 3
INT = re.compile(r"^[-+]?\d+$")


def command_name(s):
    return s.lstrip("_.-+'").upper()


class Fn:
    """One function of a file: its bodies and what the flow pass has
    learned about it."""

    def __init__(self, name, params, locs, bodies):
        self.name = name
        self.params = {p: i for i, p in enumerate(params)}
        self.pset = {p: frozenset([("param", i)])
                     for p, i in self.params.items()}
        self.lnames = set(locs) | set(params)
        self.bodies = bodies
        self.env = {}
        self.ret = EMPTY
        self.snk = {}                   # origin -> how it got there
        self.gw = {}                    # global -> origins written in
        self.rint, self.p2r, self.p2s = EMPTY, set(), {}

    def key(self):
        return (self.rint, frozenset(self.p2r), frozenset(self.p2s))


class Flow:
    """Which rtos sites of one file reach drawing text.

    An origin is ("site", id) for a suspect rtos call, ("param", i) for
    the function's own i-th argument, ("G", name) for a global read.
    Each function is summarised -- what reaches its return (p2r: which
    arguments, rint: sites and globals of its own), which argument
    reaches a sink, itself or through a global that does (p2s) -- and
    evaluated again whenever a function it calls learns more, to a
    fixpoint.  A caller takes only what ITS arguments carry back, so a
    helper that returns its argument does not drag every caller's text
    to the one caller that draws it."""

    def __init__(self, forms, sites):
        self.sites = sites
        self.fns = {}
        self.callers = collections.defaultdict(set)
        tops = []
        for top in forms:
            if not isinstance(top, list):
                continue
            for f, _ in walk(top):
                if head(f) in DEFUNS and len(f) > 2 and is_sym(f[1]):
                    n = f[1].lower()
                    params, locs = arglist(f)
                    if n in self.fns:           # defined twice: both
                        g = self.fns[n]
                        g.bodies.append(f[3:])
                        g.lnames.update(locs)
                    else:
                        self.fns[n] = Fn(n, params, locs, [f[3:]])
            if head(top) not in DEFUNS:
                tops.append(top)
        self.fns["<top level>"] = Fn("<top level>", [], [], [tops])
        self.gs = {}                    # globals that reach a sink
        self.grew = False
        self.run()

    # -- evaluation -------------------------------------------------

    def assign(self, F, s, v):
        if s in F.lnames:
            old = F.env.get(s, EMPTY)
            if not v <= old:
                F.env[s] = old | v
                self.grew = True
        elif v:
            F.gw[s] = F.gw.get(s, EMPTY) | v

    def sink(self, F, v, hows):
        if isinstance(hows, str):
            hows = (hows,)
        for o in v:
            got = F.snk.setdefault(o, set())
            for how in hows:
                if len(got) < WITNESSES:
                    got.add(how)

    def call(self, F, n, args, spread=EMPTY):
        G = self.fns[n]
        self.callers[n].add(F.name)

        def arg(i):
            return args[i] if i < len(args) else spread
        r = G.rint
        for i in G.p2r:
            r = r | arg(i)
        for i, hows in G.p2s.items():
            self.sink(F, arg(i), hows)
        return r

    def apply(self, F, fn, args, spread=EMPTY):
        fn = unquote(fn)
        if head(fn) == "lambda":
            params, locs = arglist(fn)
            F.lnames.update(params, locs)
            for i, p in enumerate(params):
                self.assign(F, p, args[i] if i < len(args) else spread)
            r = EMPTY
            for b in fn[2:]:
                r = self.ev(F, b)
            return r
        if is_sym(fn):
            n = fn.lower()
            if n in self.fns:
                return self.call(F, n, args, spread)
            v = spread.union(*args)
            if n in PASS:
                return v
            if n in SINKS:
                self.sink(F, v, "%s in %s" % (n, F.name))
        return EMPTY

    def ev(self, F, x):
        if isinstance(x, Str) or not x:
            return EMPTY
        if is_sym(x):
            s = x.lower()
            if s in F.params:
                return F.pset[s] | F.env.get(s, EMPTY)
            if s in F.lnames:
                return F.env.get(s, EMPTY)
            if s in ("t", "nil", ".") or s[0] == ":" or NUM.match(s):
                return EMPTY
            return frozenset([("G", s)])
        if not isinstance(x, list):
            return EMPTY
        h = head(x)
        if h is None:
            args = [self.ev(F, a) for a in x[1:]]
            if head(x[0]) == "lambda":
                return self.apply(F, x[0], args)
            self.ev(F, x[0])
            return EMPTY
        if h in ("quote", "function") or h in DEFUNS:
            return EMPTY
        if h == "setq":
            v = EMPTY
            for i in range(1, len(x) - 1, 2):
                v = self.ev(F, x[i + 1])
                if is_sym(x[i]):
                    self.assign(F, x[i].lower(), v)
            return v
        if h == "if":
            for t in x[1:2]:
                self.ev(F, t)
            return EMPTY.union(*(self.ev(F, b) for b in x[2:4]))
        if h == "cond":
            r = EMPTY
            for c in x[1:]:
                if isinstance(c, list) and c:
                    vs = [self.ev(F, y) for y in c]
                    r = r | vs[-1]
            return r
        if h in ("progn", "while", "repeat"):
            r = EMPTY
            for y in x[1:]:
                r = self.ev(F, y)
            return r
        if h == "foreach" and len(x) > 2 and is_sym(x[1]):
            v = x[1].lower()
            F.lnames.add(v)
            self.assign(F, v, self.ev(F, x[2]))
            r = EMPTY
            for y in x[3:]:
                r = self.ev(F, y)
            return r
        if h == "lambda":
            self.apply(F, x, [])
            return EMPTY
        if h in ("mapcar", "vl-some", "vl-every") and len(x) > 2:
            r = self.apply(F, x[1], [self.ev(F, a) for a in x[2:]])
            return EMPTY if h == "vl-every" else r
        if h in ("apply", "vl-catch-all-apply") and len(x) > 2:
            lst = x[2]
            if head(lst) == "list":
                return self.apply(F, x[1], [self.ev(F, a) for a in lst[1:]])
            return self.apply(F, x[1], [], self.ev(F, lst))
        args = [self.ev(F, a) for a in x[1:]]
        if h in ("cons", "list") and len(x) >= 3 and is_sym(x[1]) \
                and INT.match(x[1]) and (h == "cons") == (len(x) == 3):
            # a DXF group, (cons 1 s) or (list 10 x y z): only the text
            # groups carry text into an entity
            return EMPTY.union(*args[1:]) if x[1].lstrip("+") in TEXT_GROUPS \
                else EMPTY
        if h == "rtos":
            return frozenset([("site", id(x))]) if id(x) in self.sites \
                else EMPTY
        if h in self.fns:
            return self.call(F, h, args)
        if h in PASS:
            return EMPTY.union(*args)
        if h in SINKS:
            self.sink(F, EMPTY.union(*args), "%s in %s" % (h, F.name))
        elif h in PUTS and len(x) > 3:
            p = unquote(x[2])
            if isinstance(p, str) and p.lower() in TEXT_PROPS:
                self.sink(F, EMPTY.union(*args[2:]),
                          "%s %s in %s" % (h, p, F.name))
        elif h in INVOKES and len(x) > 2:
            p = unquote(x[2])
            if isinstance(p, str) and p.lower() in TEXT_PROPS:
                self.sink(F, EMPTY.union(*args[2:]),
                          "%s %s in %s" % (h, p, F.name))
        elif h in COMMANDS:
            self.command_sink(F, x, args)
        return EMPTY

    def command_sink(self, F, x, args):
        name = next((command_name(a) for a in x[1:] if isinstance(a, Str)),
                    "")
        if name in TEXT_COMMANDS:
            self.sink(F, EMPTY.union(*args),
                      "a %s command in %s" % (name, F.name))
        elif name.startswith("DIM"):
            for i, a in enumerate(x[1:-1]):
                if isinstance(a, Str) and command_name(a) in ("T", "TEXT"):
                    self.sink(F, args[i + 1],
                              "a %s text override in %s" % (name, F.name))

    # -- the fixpoint -----------------------------------------------

    def evaluate(self, F):
        for _ in range(8):
            self.grew = False
            for body in F.bodies:
                r = EMPTY
                for form in body:
                    r = self.ev(F, form)
                F.ret = F.ret | r
            if not self.grew:
                break

    def summarise(self, F):
        F.rint = frozenset(o for o in F.ret if o[0] != "param")
        F.p2r = {o[1] for o in F.ret if o[0] == "param"}
        F.p2s = {o[1]: hows for o, hows in F.snk.items() if o[0] == "param"}
        for g, os in F.gw.items():
            if g in self.gs:
                for o in os:
                    if o[0] == "param":
                        F.p2s.setdefault(o[1], self.gs[g])

    def grow_sinking_globals(self):
        n = len(self.gs)
        for F in self.fns.values():
            for o, hows in F.snk.items():
                if o[0] == "G":
                    self.gs.setdefault(o[1], hows)
        more = True
        while more:
            more = False
            for F in self.fns.values():
                for g, os in F.gw.items():
                    if g in self.gs:
                        for o in os:
                            if o[0] == "G" and o[1] not in self.gs:
                                self.gs[o[1]] = self.gs[g]
                                more = True
        return len(self.gs) != n

    def run(self):
        order = list(self.fns)
        dirty = set(order)
        for _ in range(60):
            if not dirty:
                break
            for n in order:
                if n in dirty:
                    dirty.discard(n)
                    F = self.fns[n]
                    k = F.key()
                    self.evaluate(F)
                    self.summarise(F)
                    if F.key() != k:
                        dirty |= self.callers[n]
            if self.grow_sinking_globals():
                for n in order:
                    F = self.fns[n]
                    k = F.key()
                    self.summarise(F)
                    if F.key() != k:
                        dirty |= self.callers[n]

    def reached(self):
        """{site id: the ways its text reaches the drawing}."""
        out = collections.defaultdict(set)
        for F in self.fns.values():
            for o, hows in F.snk.items():
                if o[0] == "site":
                    out[o[1]] |= hows
            for g, os in F.gw.items():
                if g in self.gs:
                    for o in os:
                        if o[0] == "site":
                            out[o[1]] |= self.gs[g]
        return out


FTIN_NOTE = {
    "ftin": "mode %s follows DIMZIN, and this text is written into the "
            "drawing (%s): a whole foot is 15' at DIMZIN 0/2/8 and "
            "UNITMODE 1 respells it -- spell it with the tool's own :ftin",
    "knob": "mode %s can be 3 or 4 -- nothing on the way here sends those "
            "elsewhere -- and this text is written into the drawing (%s): "
            "feet-inch rtos follows DIMZIN (15' at 0/2/8) -- send 3 and 4 "
            "to the tool's own :ftin",
    "lunits": "mode %s: the drawing's LUNITS, and this text is written "
              "into the drawing (%s): in a feet-inch drawing it follows "
              "DIMZIN (15' at 0/2/8) -- send LUNITS 3 and 4 to the "
              "tool's own :ftin",
}


# ---------------------------------------------------------------------
#  rtos-shape
# ---------------------------------------------------------------------

#: where the TEXT sits in each call that reads a string by position
SLICE_ARG = {"substr": 1, "vl-string-search": 2, "vl-string-position": 2,
             "read": 1}


def is_cdate(x):
    return head(x) == "getvar" and len(x) > 1 and isinstance(x[1], Str) \
        and x[1].upper() in ("CDATE", "DATE")


def rtos_shape(f, parents):
    """(note, the form to show) or None."""
    if len(f) > 1 and is_cdate(f[1]):
        return ("CDATE through rtos: DIMZIN 8 trims its digits -- decode "
                "it arithmetically, as cal:datestr does", f)
    p = parents[-1] if parents else None
    h = head(p)
    if h in SLICE_ARG and index_of(p, f) == SLICE_ARG[h]:
        return ("rtos text read by %s: DIMZIN 8 trims trailing zeros and "
                "4 drops the leading one" % h, p)
    return None


def shape_through_locals(d):
    """rtos-shape through a local of D: (setq s (rtos ...)) and then s
    sliced, or (setq c (getvar "CDATE")) and then (rtos c ...)."""
    fromrtos, dates = {}, set()
    for f, _ in walk_own(d):
        if head(f) == "setq":
            for i in range(1, len(f) - 1, 2):
                if not is_sym(f[i]):
                    continue
                v = f[i + 1]
                if head(v) == "rtos" and not (len(v) > 1 and is_cdate(v[1])):
                    fromrtos[f[i].lower()] = v
                elif is_cdate(v):
                    dates.add(f[i].lower())
    out = []
    for f, _ in walk_own(d):
        h = head(f)
        if h in SLICE_ARG and len(f) > SLICE_ARG[h]:
            tgt = f[SLICE_ARG[h]]
            if is_sym(tgt) and tgt.lower() in fromrtos:
                out.append((f, "slices %s, set from %s"
                            % (tgt, excerpt(fromrtos[tgt.lower()], 30))))
        elif h == "rtos" and len(f) > 1 and is_sym(f[1]) \
                and f[1].lower() in dates:
            out.append((f, "%s holds CDATE: DIMZIN 8 trims its digits -- "
                           "decode it arithmetically" % f[1]))
    return out


# ---------------------------------------------------------------------
#  rtos-bound
# ---------------------------------------------------------------------

#: an INCLUSIVE limit: the number shown is itself allowed, so showing it
#: rounded the wrong way shows a number the loop refuses.  A word that
#: comes BEFORE its number ("max 4'", "between C (..) and D (..)"), and
#: one that comes AFTER it ("24 or less").  A strict bound -- "more
#: than", "deeper than" -- is not here: its own number is refused by
#: design, and the next displayed step is taken either way.
BEFORE = re.compile(r"\b(max(imum)?|min(imum)?|at most|at least|up to|"
                    r"no more than|no less than|not more than|"
                    r"not less than|between|limit)\b", re.I)
AFTER = re.compile(r"^\s*(or less|or more|or under|or over|or smaller|"
                   r"or larger|max(imum)?|min(imum)?|at most|at least)\b",
                   re.I)
VALUE = "\x00"                          # a non-literal in the message
#: what may stand between a limit word and its number: nothing, or a
#: short name -- "max ", "between C (" -- but not a clause: in "the
#: biggest jump between them is 4'" the word governs "them", not 4'
SHORT = re.compile(r"^[\s(:=]*(?:\w{1,3}[\s(:=]*)?$")
#: ...and between a "between"'s two numbers: ") and D ("
PAIRED = re.compile(r"^[\s)]*(?:and|to|-)[\s(]*(?:\w{1,3}[\s(:=]*)?$", re.I)
GETS = {"getreal", "getdist", "getint", "getstring", "getkword",
        "getpoint", "getangle", "getorient", "getcorner"}
ROUNDED = re.compile(r"floor|ceil", re.I)
#: the arithmetic feet-inch formatter the rtos-ftin fix introduces: it
#: rounds to nearest as rtos does, so a limit shown through it is read
FTIN_NAME = re.compile(r"[:-]ftin$", re.I)


def asks(form):
    """Does FORM read an answer -- a get* builtin or a tool's ask helper?"""
    for g, _ in walk(form):
        h = head(g)
        if h in GETS or (h and "ask" in h):
            return True
    return False


def message(args):
    """ARGS of a strcat as text, every non-literal one a VALUE mark."""
    return "".join(x if isinstance(x, Str) else VALUE for x in args)


def bound_word(f, parents):
    """The limit word that governs F in the message it is spelled into:
    the word just before it, with at most a short name between them
    (\"between\" may reach across the one other number it pairs with),
    or just after it.  Nothing that ends a sentence -- . ! ? -- ; or a
    \\n -- may stand between a word and its number."""
    chain = list(parents) + [f]
    for j in range(len(chain) - 2, max(-1, len(chain) - 5), -1):
        p = chain[j]
        if head(p) != "strcat":
            continue
        k = index_of(p, chain[j + 1])
        before, after = message(p[1:k]), message(p[k + 1:])
        m = AFTER.match(after)
        if m:
            return m.group(1)
        m = None
        for m in BEFORE.finditer(before):
            pass
        if m:
            gap = before[m.end():].split(VALUE)
            if SHORT.match(gap[0]) and (
                    len(gap) == 1 or (len(gap) == 2 and PAIRED.match(gap[1])
                                      and m.group().lower() == "between")):
                return m.group()
        return None
    return None


def rounds_to_nearest(defs):
    """The file's own formatters: a defun whose return is an rtos, a
    :ftin or another such formatter, of its first argument."""
    def leaves(x):
        h = head(x)
        if h == "if":
            return [y for b in x[2:4] for y in leaves(b)]
        if h == "cond":
            return [y for c in x[1:] if isinstance(c, list) and c
                    for y in leaves(c[-1])]
        if h == "progn" and len(x) > 1:
            return leaves(x[-1])
        return [x]
    out, more = set(), True
    while more:
        more = False
        for d in defs:
            n = d[1].lower()
            params, _ = arglist(d)
            if n in out or not params or len(d) < 4:
                continue
            for x in leaves(d[-1]):
                h = head(x)
                if h and (h == "rtos" or FTIN_NAME.search(h) or h in out) \
                        and len(x) > 1 and mentions(x[1], params[0]):
                    out.add(n)
                    more = True
                    break
    return out


def rtos_bound(f, parents, d):
    if len(f) < 2:
        return None
    word = bound_word(f, parents)
    if not word:
        return None
    val = f[1]
    if isinstance(val, list) and head(val) and ROUNDED.search(head(val)):
        return None                    # floored / ceiled for display
    names = names_in(val)
    loop = next((p for p in reversed(parents) if head(p) == "while"), None)
    if not names or loop is None or not asks(loop):
        return None
    for t in tests_before(f, parents, d):
        if syms(t) & names:
            return ("'%s' limit shown rounded to nearest, in a loop that "
                    "re-asks against it: floor a max / ceil a min at the "
                    "displayed precision" % word)
    return None


# ---------------------------------------------------------------------
#  vl-sort, COM objects, angtos
# ---------------------------------------------------------------------

CLAIM = re.compile(r"\b(?:vl-sort|sort(?:s|ed|ing)?)\W+(?:\w+\W+){0,2}?"
                   r"(?:drops?|dedupes?|removes?|discards?|collapses?)\b",
                   re.I)


def prose_for(comments, d, f):
    """The comment block above D (or above F at top level) and every
    comment inside D up to F, as one string."""
    lines = []
    if d is not None:
        ln = d.line - 1
        while ln in comments and len(lines) < 20:
            lines.append(ln)
            ln -= 1
        lines += [n for n in range(d.line, f.line + 1) if n in comments]
    else:
        lines = [n for n in range(f.line - 8, f.line + 1) if n in comments]
    return " ".join(comments[n] for n in sorted(lines))


def vl_sort_dedupe(f, d, comments):
    if len(f) < 3:
        return None
    cmp_ = unquote(f[2])
    if not (is_sym(cmp_) and cmp_ in ("<", ">")):
        return None
    m = CLAIM.search(" ".join(prose_for(comments, d, f).split()))
    if not m:
        return None
    return ("the comment says '%s', but vl-sort drops only EQ items "
            "(integers, symbols): two equal reals both stay" % m.group())


COM_MAKERS = ("vlax-get-object", "vlax-create-object",
              "vlax-get-or-create-object")


def nil_tested(form, v):
    """Does FORM look at V for nil: (null v), (not v), or v bare as an
    if/cond/while test or an and/or term?"""
    for g, _ in walk(form):
        h = head(g)
        if h in ("null", "not") and len(g) == 2 and is_sym(g[1]) \
                and g[1].lower() == v:
            return True
        if h in ("and", "or", "if", "while"):
            terms = g[1:] if h in ("and", "or") else g[1:2]
            if any(is_sym(x) and x.lower() == v for x in terms):
                return True
        if h == "cond" and any(isinstance(c, list) and c and is_sym(c[0])
                               and c[0].lower() == v for c in g[1:]):
            return True
    return False


def getobject_nil(d):
    """A var set from vlax-get-object / vlax-create-object, tested with
    vl-catch-all-error-p and nothing that would catch nil: not beside it
    in the same and/or, not in the same if's else branch, not in a
    later clause of the same cond."""
    vars_ = {}
    for f, _ in walk_own(d):
        if head(f) == "setq":
            for i in range(1, len(f) - 1, 2):
                v = f[i + 1]
                if head(v) == "vl-catch-all-apply" and len(v) > 1:
                    v = [unquote(v[1])]
                if is_sym(f[i]) and head(v) in COM_MAKERS:
                    vars_.setdefault(f[i].lower(), head(v))
    out = []
    if not vars_:
        return out
    for f, par in walk_own(d):
        if head(f) != "vl-catch-all-error-p" or len(f) < 2 \
                or not is_sym(f[1]) or f[1].lower() not in vars_:
            continue
        v, root, chain = f[1].lower(), f, list(par)
        while chain and head(chain[-1]) in ("or", "and", "not"):
            root = chain.pop()
        if nil_tested(root, v):
            continue
        box = chain[-1] if chain else None
        if head(box) == "if" and index_of(box, root) == 1 \
                and any(nil_tested(b, v) for b in box[3:4]):
            continue
        if len(chain) >= 2 and head(chain[-2]) == "cond" \
                and index_of(box, root) == 0:
            cond = chain[-2]
            later = cond[index_of(cond, box) + 1:]
            if any(isinstance(c, list) and c and
                   (nil_tested(c[0], v) or (is_sym(c[0])
                                            and c[0].lower() == v))
                   for c in later):
                continue
        out.append((f, root, vars_[v]))
    return out


ANGVARS = ("ANGBASE", "ANGDIR", "AUNITS")


def typed_angles(d):
    angvars = set()
    for f, _ in walk_own(d):
        if head(f) == "setq":
            for i in range(1, len(f) - 1, 2):
                if is_sym(f[i]) and head(f[i + 1]) == "angtos":
                    angvars.add(f[i].lower())
    out = []
    for f, _ in walk_own(d):
        if head(f) not in COMMANDS:
            continue
        for x in f[1:]:
            if (isinstance(x, list) and any(head(g) == "angtos"
                                            for g, _ in walk(x))) \
                    or (is_sym(x) and x.lower() in angvars):
                out.append(f)
                break
    return out


# ---------------------------------------------------------------------
#  One file
# ---------------------------------------------------------------------

_COMMENT = re.compile(r'"(?:\\.|[^"\\])*"?|;[^\n]*', re.S)


def comment_lines(text):
    """{line: comment text} for every ; comment in TEXT."""
    starts = [i for i, c in enumerate(text) if c == "\n"]
    out = {}
    for m in _COMMENT.finditer(text):
        if m.group().startswith(";"):
            ln = bisect.bisect_left(starts, m.start()) + 1
            out[ln] = out.get(ln, "") + " " + m.group().lstrip(";")
    return out


def rel(path):
    try:
        return str(pathlib.Path(path).resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def scan_text(text, relpath):
    """Every site in TEXT, as Hits against RELPATH."""
    forms = read_forms(decomment(text))
    comments = comment_lines(text)
    out = []

    def hit(f, d, rule, note, shown=None):
        out.append(Hit(relpath, f.line, name_of(d), rule,
                       excerpt(shown if shown is not None else f), note))

    strs = set()
    defs, calls, suspect, cache = [], [], {}, {}
    for top in forms:
        if not isinstance(top, list):
            continue
        for f, parents in walk(top):
            strs.update(x.upper() for x in f if isinstance(x, Str))
            h = head(f)
            if h == "rtos":
                d = owner(parents)
                kind = rtos_kind(f, parents, d, cache)
                if kind:
                    suspect[id(f)] = (f, d, kind)
                shape = rtos_shape(f, parents)
                if shape:
                    hit(f, d, "rtos-shape", shape[0], shape[1])
            elif h == "vl-sort":
                d = owner(parents)
                note = vl_sort_dedupe(f, d, comments)
                if note:
                    hit(f, d, "vl-sort-dedupe", note)
            elif h in DEFUNS and len(f) > 2 and is_sym(f[1]):
                defs.append(f)
            if h:
                calls.append((f, parents))
    shown = rounds_to_nearest(defs) | {"rtos"}
    for f, parents in calls:
        h = head(f)
        if h in shown or FTIN_NAME.search(h):
            d = owner(parents)
            note = rtos_bound(f, parents, d)
            if note:
                hit(f, d, "rtos-bound", note)
    if suspect:
        for sid, hows in Flow(forms, suspect).reached().items():
            f, d, kind = suspect[sid]
            how = "; ".join(sorted(hows)[:WITNESSES])
            mode = excerpt(unquote(f[2]), 36) if len(f) > 2 else "omitted"
            hit(f, d, "rtos-ftin", FTIN_NOTE[kind] % (mode, how))
    borrowed = all(v in strs for v in ANGVARS)
    for d in defs:
        for f, note in shape_through_locals(d):
            hit(f, d, "rtos-shape", note)
        for f, root, maker in getobject_nil(d):
            hit(f, d, "getobject-nil",
                "%s answers NIL when nothing is running or registered, and "
                "nil passes this test -- add (null %s) beside it"
                % (maker, f[1]), root)
        if not borrowed:
            for f in typed_angles(d):
                hit(f, d, "typed-angle",
                    "an angle typed into a command is read through ANGBASE,"
                    " ANGDIR and AUNITS, which this file never borrows")
    return out


def scan(paths=None):
    hits = []
    for p in (paths if paths is not None else sources()):
        hits += scan_text(read(p), rel(p))
    return sorted(hits, key=lambda h: (h.path, h.line, h.rule, h.text))


# ---------------------------------------------------------------------
#  Baseline
# ---------------------------------------------------------------------

def key(h):
    return (h.path, h.defun, h.rule, h.text)


def load_baseline(path=None):
    """{key: [reason, ...]}, one reason per line in file order."""
    base = collections.defaultdict(list)
    path = pathlib.Path(path or BASELINE)
    if not path.is_file():
        return base
    for ln in path.read_text(encoding="utf-8").splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("|", 3)
        if len(parts) < 4 or "|" not in parts[3]:
            continue
        text, reason = parts[3].rsplit("|", 1)
        base[(parts[0], parts[1], parts[2], text)].append(reason.strip())
    return base


def is_reason(r):
    return bool(r) and r.upper() != UNREVIEWED


def compare(hits, base):
    """(new hits, [(stale key, how many)], ids of the accepted hits).
    The n-th of several identical sites is paired with the n-th line."""
    seen = collections.Counter()
    new, ok = [], set()
    for h in hits:
        k = key(h)
        seen[k] += 1
        reasons = base.get(k, [])
        if seen[k] <= len(reasons) and is_reason(reasons[seen[k] - 1]):
            ok.add(id(h))
        else:
            new.append(h)
    stale = [(k, len(base[k]) - seen[k]) for k in sorted(base)
             if seen[k] < len(base[k])]
    return new, stale, ok


def why_not(h, base, nth):
    """Why a baseline line did not accept H, or ''."""
    reasons = base.get(key(h), [])
    if nth > len(reasons):
        return ""
    r = reasons[nth - 1]
    return "   (its baseline line is %s)" % (
        "UNREVIEWED" if r.upper() == UNREVIEWED else "without a reason")


HEADER = """\
# Sites tools/check_values.py flags that are FINE, and why.
# One line per site: file|defun|rule|excerpt|why.
#
# Only a site that is genuinely right goes here, with the reason it is.
# A defect is fixed, not baselined -- a DIMZIN-proof :ftin, a floored
# max, an explicit dedupe.  --update-baseline keeps every reason, drops
# stale lines and writes a new site as UNREVIEWED, which the check does
# not accept: replace it with the reason, or fix the site.
# Regenerate with: python3 tools/check_values.py --update-baseline
"""


def write_baseline(hits, base, path=None):
    seen = collections.Counter()
    rows, n = [], 0
    for h in hits:
        k = key(h)
        seen[k] += 1
        reasons = base.get(k, [])
        reason = reasons[seen[k] - 1] if seen[k] <= len(reasons) else ""
        if not is_reason(reason):
            reason, n = UNREVIEWED, n + 1
        rows.append("%s|%s|%s|%s|%s" % (k + (reason,)))
    pathlib.Path(path or BASELINE).write_text(
        HEADER + "".join(r + "\n" for r in rows), encoding="utf-8")
    return n


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("files", nargs="*",
                    help="scan only these files (default: every "
                         "hand-edited source)")
    ap.add_argument("--list", action="store_true",
                    help="print every site, baselined ones included")
    ap.add_argument("--rule", choices=RULES)
    ap.add_argument("--update-baseline", action="store_true")
    a = ap.parse_args(argv)

    paths = [pathlib.Path(f) for f in a.files] if a.files else None
    hits = scan(paths)
    base = load_baseline()
    scope = {rel(p) for p in paths} if paths else None
    if scope is not None or a.rule:
        keep = (lambda k: (scope is None or k[0] in scope)
                and (a.rule is None or k[2] == a.rule))
        base = {k: v for k, v in base.items() if keep(k)}
        hits = [h for h in hits if a.rule is None or h.rule == a.rule]

    if a.update_baseline:
        if scope is not None or a.rule:
            print("check_values: --update-baseline rewrites the whole "
                  "file; run it without FILE or --rule")
            return 2
        n = write_baseline(hits, base)
        print("check_values: baseline rewritten - %d site(s), %d of them "
              "UNREVIEWED" % (len(hits), n))
        return 1 if n else 0

    new, stale, ok = compare(hits, base)
    if a.list:
        for h in hits:
            print("%s:%d  %-14s %s  %s%s" % (
                h.path, h.line, h.rule, h.defun, h.text,
                "   [baselined]" if id(h) in ok else ""))
    seen = collections.Counter()
    for h in hits:
        seen[key(h)] += 1
        if id(h) in ok:
            continue
        print("%s:%d: [%s] %s: %s" % (h.path, h.line, h.rule, h.defun, h.text))
        print("    %s%s" % (h.note, why_not(h, base, seen[key(h)])))
    for k, n in stale:
        print("%s: %s - baselined %s site is gone%s: %s"
              % (k[0], k[1], k[2], "" if n == 1 else " (%d of them)" % n,
                 k[3]))
    by_rule = collections.Counter(h.rule for h in new)
    if new or stale:
        print("check_values: %d site(s) flagged (%s), %d stale baseline "
              "line(s) -- fix the site, or say in tools/values_baseline.txt "
              "why it is fine" % (
                  len(new), ", ".join("%s %d" % kv
                                      for kv in sorted(by_rule.items()))
                  or "none", len(stale)))
        return 1
    print("check_values: %d site(s) read against the baseline, every one "
          "accounted for" % len(hits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
