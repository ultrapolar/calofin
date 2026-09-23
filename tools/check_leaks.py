#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""What a run borrows is handed back on EVERY way out -- the early ones
too -- and nothing a dead run left standing is read as this run's own.

A command borrows things that outlive it: an undo group, the pushed
error mode, its LAZDIAG run, a sysvar, and the module globals it keeps
between prompts -- a snapshot like oasis:*odstyle*, a flag like
lzf:*cover*, a handoff like *calofin-handoff*.  Each is an ACQUIRE and
a RELEASE, and every leak here is the same bug: one way out skips the
release, and the NEXT run -- or the next command -- starts from what
this one left.  It never looks like this tool's failure.  OASIS's two
refusals kept a dimension-style snapshot that the next clean OASIS run
put back over the drafter's; a LAZFORMCOVER whose POOL was cancelled
left the cover flag up, and the next LAZTXT quietly dropped a dozen
answers it had been given.

AutoLISP has no early return: a command falls out of the bottom of its
defun, or raises.  So its normal exits are exactly the leaves of its
if/cond/and/or tree, and this reads each command as that tree -- an
abstract interpreter that inlines every helper the tier defines and
tracks, per resource, whether it is free or held and where it was
taken.

RESOURCES
  undo      (command "_.UNDO" "_Begin"/"_End"), vla-Start/EndUndoMark
  errmode   *push-error-using-command* / *pop-error-mode*
  lzd       lzd:begin, released by lzd:end or lzd:report
  sv:NAME   a (setvar "NAME" v) that is not a restore, and a
            (mapcar 'setvar '("NAME" ...) '(literal ...)).  A restore
            puts back a symbol the tier fills from (getvar "NAME") --
            oos, autobead:*oldos* -- a parameter, or a table entry,
            (setvar (car p) (cdr p)).  A local set from anything else
            (perp's srcLtype, off the source entity) is a new value
  g:NAME    run state, read off the code rather than listed: an
            earmuffed global the reached code sets both to a value and,
            unconditionally, to nil.  A nil set opposite a value set in
            one if/cond is a CHOICE (abl:*max-arcs* = none), not a clear

HANDLER SCOPES: any defun that installs an *error*, a command or a
helper (lzf:show, autobead-build).  An error inside a scope runs THAT
scope's handler and unwinds to the command line; no outer handler runs.
So a call into an inner scope is not a place the OUTER handler can be
entered from -- BYPASS covers what it leaves.

A RELEASE UNDER A GUARD counts on both arms only when the guard is one
the tree writes a release under: the acquire's flag, (if undo-open
(command "_.UNDO" "_End")); the value it puts back, (if oe (setvar "X"
oe)); the bound check on the releasing function, (if lzd:end (lzd:end
...)); or a run-state global, whose truth the interpreter follows.
Any other test is a path the release is not on: (if rows (progn ...
close)) leaves the group open when there are no rows, however the arms
are written.

RULES
  EXIT     a command frees undo, the error mode, its LAZDIAG run and
           every sysvar it moved, on every normal exit.  The finding
           names the exits that still hold it -- the arm of the if or
           cond that skips the release its sibling makes.
  HANDLER  a scope's *error*, entered holding whatever was held at a
           point the run can fail at (a prompt, a command, an ActiveX
           call, a tier helper, outside vl-catch-all-apply), frees all
           of it.  A command-s reached with the error mode pushed kills
           the handler there, past any catch: what is still held then
           is reported too.
  BYPASS   a call into an inner scope while holding something, outside
           a catch: an error in there runs only the inner handler.  It
           is simulated against what the caller holds at the inner's
           own risk points -- so a handoff the inner spends on entry is
           not counted -- with the inner's own flags nil.  A stage
           called as (apply (read "c:...")) cannot be simulated: it is
           charged the undo, error mode and sysvars held, never the
           globals, which a stage is written to consume.
  STALE    a run-state global some exit, handler or bypass can leave
           set starts every later run STALE; a command that reads it
           before it writes it reads the dead run's value.  Harmless
           leftovers -- pool:*ruler*, cleared at every run's entry --
           are never reported, because nothing reads them first.
  SIBLING  a module global several tools carry under one suffix, which
           the others clear at run time and this one never does -- the
           shape STALE cannot see, because a global with no run-time
           nil is never run state.  pf:*ruler* sat like that.  Only
           when at least two siblings clear it and they outnumber the
           ones that never do: pool:*smallwarned* (cleared, "once a
           run") against hn: and sf:*smallwarned* (never, "said once")
           is a family split by design, and is not reported.
  ERRNO    (getvar "ERRNO") with no reset before it in the defun or in
           the file's begin hook: ERRNO is sticky, and reports the last
           command's failure as this one's.
  HANDOFF  (command "X") / (vl-cmdf "X") where X is an AutoLISP command
           of this tier: the command processor cannot reach one, so X
           never starts while the caller says it has.

NOT HERE, because another check owns it: a handler that DIES (command-s
under a push, a local read after the unwind) is check_handlers'; a
command with no handler at all is check_lazdiag's; the ORDER of a
handler's restores is check_osnap's and check_color's.

LIMITS -- what this cannot see, each checked against the tree:
  - a leak through a (defun) built at run time, or a callee chosen by
    a string it cannot read;
  - a value correlated with a flag the interpreter does not track;
  - a setvar from a PARAMETER is read as a restore, so a helper that
    mutes with its argument -- hn:dofillet's (setvar "FILLETRAD" r) --
    is not seen as a mute (FILLETRAD is put back by hn:syssave's table
    today, so nothing hides behind it);
  - a setvar whose NAME is computed, (setvar v val), moves a sysvar it
    cannot name: it is neither a mute nor a release.  spa:setv sets
    DIM* sysvars that way;
  - (mapcar 'setvar NAMES VALS) with NAMES not a literal list is read
    as a table restore;
  - ERRNO reset once before a retry loop and read on its second pass
    passes: the rule is lexical, first read after a reset;
  - (command (strcat "_." name)) is not read as a HANDOFF.

An accepted finding goes in tools/leaks_baseline.txt with the reason,
check_back's pattern: file|defun|RULE|resource|reason.  The file is the
tool's basename, so one line covers the three tiers (a releases/ twin's
_MMDDYY_REVnn is dropped).  The defun of a STALE or SIBLING line may be
*, for a global kept between runs on purpose: every reader is then
accepted.  A * on any other rule is malformed -- an exit is one site.

    python3 tools/check_leaks.py [--tier lisp|shared|releases|both|all]
                                 [--all]

The default reads all three tiers, as check_handlers and check_osnap
do: a dated twin in releases/ is what a shop pins to.  --all prints the
baselined findings too.  Exit 1 on any finding outside the baseline, a
baseline line nothing matches (reported when lisp/ and shared/ are both
read), or a malformed one.
"""

import argparse
import collections
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from callib import (LISP_DIR, NOT_A_TOOL, PARTS_DIR,  # noqa: E402
                    RELEASES_DIR, ROOT, decomment, lsp_files, read)
from check_handlers import L, Str, read_forms  # noqa: E402

BASELINE = HERE / "leaks_baseline.txt"

RULES = ("EXIT", "HANDLER", "BYPASS", "STALE", "SIBLING", "ERRNO",
         "HANDOFF")
WILD_RULES = ("STALE", "SIBLING")    # the rules a * defun may stand in


# ---------------------------------------------------------------------
#  The tree: check_handlers' reader (lines, strings and quote kept),
#  with every symbol lower-cased once so the interpreter compares
#  plain strings.  A symbol is a plain str; a string literal is Str.
# ---------------------------------------------------------------------

_TREES = {}


def _norm(x):
    if isinstance(x, list):
        y = L(_norm(e) for e in x)
        y.line = getattr(x, "line", 0)
        return y
    if isinstance(x, Str):
        return x
    return str.lower(x)


def forms_of(text):
    """TEXT decommented, read and normalised -- memoised on the text,
    so a twin byte-identical to its source is read once."""
    t = _TREES.get(text)
    if t is None:
        t = _TREES[text] = [_norm(f) for f in read_forms(decomment(text))]
    return t


def is_str(x):
    return type(x) is Str


def hd(f):
    if type(f) is L and f and type(f[0]) is str:
        return f[0]
    return None


def walk(f):
    yield f
    if type(f) is L:
        for x in f:
            if type(x) is L:
                yield from walk(x)


def atoms(f):
    """Every symbol anywhere in F."""
    if type(f) is L:
        for x in f:
            if type(x) is L:
                yield from atoms(x)
            elif type(x) is str:
                yield x
    elif type(f) is str:
        yield f


def strings(f):
    """Every string literal anywhere in F."""
    if type(f) is Str:
        yield f
    elif type(f) is L:
        for x in f:
            yield from strings(x)


def unquote(x):
    if type(x) is L and len(x) == 2 and x[0] in ("quote", "function"):
        return x[1]
    return None


GLOBAL = re.compile(r"^(?:[a-z0-9_.-]+:)?\*[a-z0-9_.:-]+\*$")
NOT_TRACKED = {"*error*", "*calofin-quiet*", "*push-error-using-command*",
               "*pop-error-mode*"}
NUMBER = re.compile(r"^[-+]?(\d|\.\d)")


def is_global(s):
    return (type(s) is str and s not in NOT_TRACKED
            and not s.startswith("lzd:") and bool(GLOBAL.match(s)))


def is_literal(s):
    return s in ("t", "nil") or bool(NUMBER.match(s))


def literal_list(x):
    """The items of '(...) or (list ...) when every one is a literal --
    a string, a number, t or nil -- else None."""
    q = unquote(x)
    items = q if type(q) is L else (x[1:] if hd(x) == "list" else None)
    if items is None or not all(is_str(i) or (type(i) is str
                                              and is_literal(i))
                                for i in items):
        return None
    return list(items)


RISKY = {"getpoint", "getdist", "getreal", "getint", "getkword", "getstring",
         "getangle", "getorient", "getcorner", "entsel", "nentsel",
         "nentselp", "ssget", "grread", "command", "vl-cmdf", "command-s",
         "exit", "quit", "entmod", "entmake", "entmakex"}
MAYBE_CALL = {"mapcar", "vl-some", "vl-every", "vl-remove-if",
              "vl-remove-if-not", "vl-member-if", "vl-member-if-not",
              "vl-sort", "vlax-for", "vlax-map-collection"}
DEATH = {"exit", "quit", "*error*", "vl-exit-with-error",
         "vl-exit-with-value"}
CMD = ("command", "command-s", "vl-cmdf")

MAX_DEPTH = 40
LOOP_PASSES = 8

# resource states: tags in a frozenset.  "F0" is nil since the run
# began (never touched); "F" is nil because the run let it go; "H@..."
# is held, with where it was taken; "S" is a value a dead run left;
# "X@..." rides along with a held one, naming an arm it came out of
# while a sibling arm let it go (note_split).
F0 = frozenset({"F0"})
FREE = frozenset({"F"})
STALE = frozenset({"S"})
NILS = frozenset({"F", "F0"})
IN = "H@IN"          # a memo summary's "held, as it came in"
PASS = "*"           # in an event's held set: what the caller holds
                     # outside this function's reach


def held(v):
    for t in v:
        if t[0] == "H":
            return True
    return False


def norm_tags(v):
    """V with every origin replaced by IN, and every exit tag dropped --
    the memo key's view.  call_named puts the caller's tags back."""
    if held(v):
        return frozenset(IN if t[0] == "H" else t for t in v
                         if t[0] != "X")
    return v


def status(v):
    return frozenset("H" if t[0] == "H" else t for t in v)


# ---------------------------------------------------------------------
#  The tier: every defun, what it touches, and what it reaches
# ---------------------------------------------------------------------

def params_locals(al):
    if type(al) is not L:
        return (), ()
    toks = [t for t in al if type(t) is str]
    if "/" in toks:
        k = toks.index("/")
        return tuple(toks[:k]), tuple(toks[k + 1:])
    return tuple(toks), ()


def handlers_of(df):
    """(params, body) of each *error* DF installs itself -- not the
    handlers of a helper defined inside it."""
    out = []

    def rec(f, top):
        if type(f) is not L:
            return
        h = hd(f)
        if h == "quote":
            return
        if h == "defun" and len(f) >= 2:
            if f[1] == "*error*":
                out.append((params_locals(f[2])[0], list(f[3:]), f.line))
                return
            if not top:
                return
        if h == "setq":
            for i in range(1, len(f) - 1, 2):
                v = f[i + 1]
                if f[i] == "*error*":
                    if hd(v) == "function" and len(v) == 2:
                        v = v[1]
                    if hd(v) == "lambda":
                        out.append((params_locals(v[1])[0], list(v[2:]),
                                    v.line))
        for x in f:
            rec(x, False)

    rec(df, True)
    return out


class Fn:
    """One defun: where it is, what it binds, what it touches itself."""

    def __init__(self, name, df, path):
        self.name, self.df, self.path = name, df, path
        self.line = df.line
        p, l = params_locals(df[2])
        self.params = p
        self.names = frozenset(p) | frozenset(l)
        self.body = list(df[3:])
        self.handlers = handlers_of(df)
        self.scope = bool(self.handlers)
        self.refs = set()        # names it calls or quotes
        self.syms = set()        # every symbol in it
        self.res = set()         # resources it touches itself
        self.allsv = False       # restores a computed (setvar V ...)
        self.exits = False       # (exit)/(quit)/(*error* ...)
        self.risky = False       # has something that can fail
        self.setvars = set()
        self.snaps = collections.defaultdict(set)  # symbol -> sysvars
        self.flags = set()       # symbols it sets to the literal T
        self.pushes = False      # (*push-error-using-command*)
        for f in walk(df):
            if type(f) is not L or not f:
                continue
            h = hd(f)
            if h is None:
                continue
            self.refs.add(h)
            if h in DEATH:
                self.exits = True
            if h in CMD or h in ("vl-catch-all-apply", "apply"):
                if any(x.upper().lstrip("_.-") == "UNDO"
                       for x in strings(f)):
                    self.res.add("undo")
            if h == "setvar" and len(f) >= 2:
                self.setvar_named(f[1])
            elif len(f) >= 2 and unquote(f[1]) == "setvar":
                # (vl-catch-all-apply 'setvar (list "X" v)) names X;
                # (mapcar 'setvar '("X" "Y") vals) names both
                args = f[2] if len(f) > 2 else None
                names = literal_list(args) if h == "mapcar" else None
                if names is not None:
                    for x in names:
                        self.setvar_named(x)
                else:
                    self.setvar_named(args[1] if hd(args) == "list"
                                      and len(args) > 1 else None)
            if h == "setq":
                for i in range(1, len(f) - 1, 2):
                    s, v = f[i], f[i + 1]
                    if type(s) is str:
                        if v == "t":
                            self.flags.add(s)
                        if hd(v) == "getvar" and len(v) == 2 \
                                and is_str(v[1]):
                            self.snaps[s].add(v[1].upper())
            for x in f:
                if type(x) is str:
                    self.syms.add(x)
                q = unquote(x)
                if type(q) is str:
                    self.refs.add(q)
        self.syms |= self.refs
        # what it touches, whether it CALLS it or hands it to an applier:
        # (vl-catch-all-apply 'command-s ...) and 'vla-EndUndoMark count
        r = self.refs
        if r & {"*push-error-using-command*", "*pop-error-mode*",
                "command-s"}:
            self.res.add("errmode")
        if r & {"lzd:begin", "lzd:end", "lzd:report"}:
            self.res.add("lzd")
        if r & {"vla-startundomark", "vla-endundomark"}:
            self.res.add("undo")
        self.pushes = "*push-error-using-command*" in r
        self.risky = bool(r & RISKY) or any(
            x.startswith(("vla-", "vlax-")) for x in r)

    def setvar_named(self, name):
        if is_str(name):
            nm = name.upper()
            if nm != "ERRNO":
                self.setvars.add(nm)
                self.res.add("sv:" + nm)
        else:
            self.allsv = True


class Rel:
    """What a function's whole reach can touch: the resources a memo
    summary of it depends on, and the symbols its key must carry."""

    __slots__ = ("res", "allsv", "syms", "inert", "risky", "scopes")

    def covers(self, r):
        return r in self.res or (self.allsv and r[:3] == "sv:")


class Tier:
    def __init__(self, paths):
        self.paths = [p for p in paths if NOT_A_TOOL not in p.parts]
        self.fns = []
        self.per_file = {}
        self.dmap = {}
        for p in self.paths:
            d = {}
            for form in forms_of(read(p)):
                for f in walk(form):
                    if hd(f) == "defun" and len(f) >= 3 \
                            and type(f[1]) is str and f[1] != "*error*" \
                            and f[1] not in d:
                        fn = Fn(f[1], f, p)
                        d[f[1]] = fn
                        self.fns.append(fn)
            self.per_file[p] = d
            for k, v in d.items():
                self.dmap.setdefault(k, v)
        # a name resolves in the caller's own file first: a lisp/ tool
        # is loaded alone, and its own copy of a helper is the one run
        for fn in self.fns:
            own = self.per_file[fn.path]
            fn.calls = {}
            for n in fn.refs:
                c = own.get(n) or self.dmap.get(n)
                if c is not None and c is not fn:
                    fn.calls[n] = c
        self.commands = [fn for fn in self.fns if fn.name.startswith("c:")]
        self.scopes = [fn for fn in self.fns if fn.scope]
        # run-state candidates, and getvar snapshots, tier-wide
        self.snaps = collections.defaultdict(set)
        for fn in self.fns:
            for g, vs in fn.snaps.items():
                self.snaps[g] |= vs
            fn.writes = self._writes(fn)
        vals, nils = set(), set()
        for fn in self.fns:
            for g, kinds in fn.writes.items():
                if "val" in kinds:
                    vals.add(g)
                if "nil" in kinds:
                    nils.add(g)
        self.runstate = vals & nils
        # what a run can be read with: run state, and the SIBLING
        # candidates the stale pass will start STALE
        self.siblings = sibling_candidates(self)
        self.watch = self.runstate | {g[2:] for g in self.siblings}
        self.flags = set()
        for fn in self.fns:
            self.flags |= fn.flags
        self._reach = {}
        self._rel = {}
        self._tracked = {}

    # -- writes ---------------------------------------------------------

    def _writes(self, fn):
        w = collections.defaultdict(set)

        def rec(f, branchy):
            if type(f) is not L:
                return
            h = hd(f)
            if h == "setq":
                for i in range(1, len(f) - 1, 2):
                    s = f[i]
                    if is_global(s) and s not in fn.names:
                        if returns_nil(self, fn, f[i + 1]):
                            w[s].add("choice" if sets_value(self, fn,
                                                            branchy, s)
                                     else "nil")
                        else:
                            w[s].add("val")
            nb = f if h in ("if", "cond") else branchy
            for x in f:
                rec(x, nb)

        rec(fn.df, None)
        return w

    # -- reach ------------------------------------------------------------

    def reach(self, fn):
        r = self._reach.get(fn)
        if r is None:
            seen, todo = {fn}, [fn]
            while todo:
                for c in todo.pop().calls.values():
                    if c not in seen:
                        seen.add(c)
                        todo.append(c)
            r = self._reach[fn] = frozenset(seen)
        return r

    def rel(self, fn):
        r = self._rel.get(fn)
        if r is None:
            r = self._rel[fn] = Rel()
            res, syms = set(), set()
            allsv = risky = scopes = exits = False
            for g in self.reach(fn):
                res |= g.res
                syms |= g.syms
                allsv = allsv or g.allsv
                risky = risky or g.risky or bool(g.calls)
                scopes = scopes or g.scope
                exits = exits or g.exits
            res |= {"g:" + s for s in syms if s in self.watch}
            r.res, r.allsv, r.syms = frozenset(res), allsv, frozenset(syms)
            r.risky, r.scopes = risky, scopes
            r.inert = not (res or allsv or scopes or exits)
        return r

    def tracked(self, fn):
        """The resources a run of FN can take: the three fixed ones, the
        sysvars it sets, and the globals its reach both sets and clears."""
        t = self._tracked.get(fn)
        if t is None:
            vals, nils, svs = set(), set(), set()
            for g in self.reach(fn):
                for s, kinds in g.writes.items():
                    if "val" in kinds:
                        vals.add(s)
                    if "nil" in kinds:
                        nils.add(s)
                svs |= g.setvars
            t = self._tracked[fn] = frozenset(
                {"undo", "errmode", "lzd"}
                | {"g:" + s for s in vals & nils}
                | {"sv:" + v for v in svs})
        return t


def returns_nil(tier, fn, v, cx=None):
    """Does setting a global to V clear it?  nil, a local known nil, a
    tier call whose last form is nil, (if known-nil x nil)."""
    if v == "nil":
        return True
    if cx is not None and type(v) is str and v in cx.false:
        return True
    h = hd(v)
    if h == "if" and cx is not None and len(v) >= 3 and type(v[1]) is str:
        if v[1] in cx.false:
            return returns_nil(tier, fn, v[3] if len(v) > 3 else "nil", cx)
        if v[1] in cx.true:
            return returns_nil(tier, fn, v[2], cx)
    if h is None:
        return False
    c = fn.calls.get(h) if fn is not None else tier.dmap.get(h)
    if c is None or not c.body:
        return False
    last = c.body[-1]
    return last == "nil" or (hd(last) == "setq" and last[-1] == "nil")


def sets_value(tier, fn, branchy, s):
    if branchy is None:
        return False
    for f in walk(branchy):
        if hd(f) == "setq":
            for i in range(1, len(f) - 1, 2):
                if f[i] == s and not returns_nil(tier, fn, f[i + 1]):
                    return True
    return False


# ---------------------------------------------------------------------
#  The abstract interpreter
# ---------------------------------------------------------------------

def get(st, r):
    return st.get(r, F0)


def join(a, b):
    if a is None:
        return b
    if b is None:
        return a
    out = dict(a)
    for k, v in b.items():
        out[k] = get(a, k) | v
    for k in a.keys() - b.keys():
        out[k] = a[k] | F0
    return out


def setr(st, r, v):
    if st is None:
        return None
    st = dict(st)
    st[r] = v
    return st


def arm_line(x, parent):
    """Where an arm of a branch leaves: its first form -- the message a
    refusal prints -- or, for the implicit else of a one-armed if, the
    if itself."""
    if hd(x) == "progn" and len(x) > 1:
        x = x[1]
    return getattr(x, "line", 0) or getattr(parent, "line", 0)


def note_split(cx, arms):
    """ARMS are the (state, line) ways out of one branch.  An arm that
    still holds a resource a sibling arm lets go is a way out that skips
    the release: its state is tagged "X@where:line", and a tag that
    reaches the end of the run held names that exit in the EXIT finding
    -- not only where the resource was taken.  Returns the arms' states,
    tagged."""
    live = [s for s, _ in arms if s is not None]
    if len(live) < 2:
        return [s for s, _ in arms]
    keys = set()
    for s in live:
        keys.update(s)
    out = [s for s, _ in arms]
    for r in keys:
        if r[:2] == "g:":
            continue
        vs = [None if s is None else s.get(r, F0) for s, _ in arms]
        if not any(v is not None and "F" in v for v in vs):
            continue
        for i, v in enumerate(vs):
            if v is not None and "F" not in v and held(v):
                out[i] = setr(out[i], r, v | {"X@%s:%s" % (cx.where,
                                                           arms[i][1])})
    return out


def take_releases(out, before, after):
    """A release under a guard counts: the guard is the flag the
    acquire set.  (if undo-open (command "_.UNDO" "_End")) closes the
    group on every path the group was opened on."""
    if out is None or after is None or before is None:
        return out
    out = dict(out)
    for r, v in after.items():
        if not held(v) and held(get(before, r)):
            out[r] = FREE
    return out


def freeze(st):
    if st is None:
        return None
    return frozenset((k, v) for k, v in st.items() if v != F0)


class Ctx:
    def __init__(self, an, tracked, root, in_handler=False):
        self.an, self.tier = an, an.tier
        self.tracked = tracked
        self.tg = frozenset(r[2:] for r in tracked if r[:2] == "g:")
        self.root = root
        self.fn = root
        self.events = {}
        self.shadow = frozenset()
        self.false = frozenset()
        self.true = frozenset()
        self.in_handler = in_handler
        self.catch = 0
        self.hdepth = 0
        self.stack = [root]
        self.where = root.name
        self.line = 0
        self.inpass = False

    def emit(self, kind, a, b=None):
        self.events.setdefault((kind, a, b, self.hdepth, self.where),
                               None)

    def heldset(self, st, skip_lzd=False):
        s = {r for r, v in st.items() if held(v)
             and not (skip_lzd and r == "lzd")}
        if self.inpass:
            s.add(PASS)
        return frozenset(s)


def tracked_global(cx, s):
    return s in cx.tg and s not in cx.shadow


def acquire(cx, st, r, line):
    if st is None or r not in cx.tracked:
        return st
    cx.emit("acq", r, line or cx.line)
    return setr(st, r, frozenset({"H@%s:%s" % (cx.where, line or cx.line)}))


def release(cx, st, r):
    if st is None or r not in cx.tracked:
        return st
    return setr(st, r, FREE)


def refine(cx, test, st, truth):
    if st is None:
        return None
    if type(test) is str:
        if tracked_global(cx, test):
            r = "g:" + test
            cur = get(st, r)
            keep = (cur - NILS) if truth else (cur & NILS)
            return setr(st, r, frozenset(keep)) if keep else None
        if test in cx.false:
            return None if truth else st
        if test in cx.true or test == "t":
            return st if truth else None
        if test == "nil":
            return None if truth else st
        return st
    h = hd(test)
    if h in ("not", "null") and len(test) == 2:
        return refine(cx, test[1], st, not truth)
    if h == "and" and truth:
        for x in test[1:]:
            st = refine(cx, x, st, True)
        return st
    if h == "or" and not truth:
        for x in test[1:]:
            st = refine(cx, x, st, False)
        return st
    return st


def is_flag(cx, test):
    """A bare flag the tier sets to T somewhere -- undo-open, begun --
    or an (and flag ...) led by one: the guard a release sits under."""
    if hd(test) == "and" and len(test) > 1:
        test = test[1]
    return type(test) is str and test in cx.tier.flags


def guards_release(cx, test, body):
    """Is TEST a guard whose false arm holds nothing BODY would free, so
    a release in BODY counts on both arms?  Only the guards the tree
    writes a release under: the acquire's flag (undo-open, begun); a
    run-state global, whose truth refine() already follows; and a
    symbol BODY itself uses -- the value the release puts back, (if oe
    (setvar "X" oe)), or the bound check on the releasing function,
    (if lzd:end (lzd:end ...)), (if *pop-error-mode* (*pop-error-mode*)).
    Any other test -- (if rows (progn ... close)) -- is a path the
    release is NOT on."""
    if hd(test) == "and" and len(test) > 1:
        test = test[1]
    if type(test) is not str or is_literal(test):
        return False
    return test in cx.tier.flags or tracked_global(cx, test) \
        or test in set(atoms(body))


def ev_seq(cx, forms, st):
    for f in forms:
        if st is None:
            return None
        st = ev(cx, f, st)
    return st


def ev(cx, f, st):
    if st is None:
        return None
    if type(f) is not L:
        if type(f) is str and f in cx.tg and f not in cx.shadow:
            cx.emit("read", f, (status(get(st, "g:" + f)), cx.line))
        return st
    if not f:
        return st
    if f.line:
        cx.line = f.line
    h0 = f[0]
    if type(h0) is L:
        if hd(h0) == "lambda":
            st = ev_seq(cx, f[1:], st)
            return inline(cx, h0, st)
        return ev_seq(cx, f, st)
    if type(h0) is not str:
        return st
    n, a = h0, f[1:]
    if n in ("quote", "defun", "lambda", "function", "defun-q"):
        return st
    callee = cx.fn.calls.get(n)
    if not cx.catch and (n in RISKY or n.startswith(("vla-", "vlax-"))
                         or (callee is not None and not callee.scope
                             and not n.startswith("lzd:"))):
        # a point an Esc or an error can leave from: whatever is held
        # here is what the handler owes back.  A call into an inner
        # scope is not one -- an error in there runs ITS handler
        cx.emit("risk", cx.heldset(st))
    if n in ("setq", "set"):
        if n == "set":
            s = unquote(a[0]) if a else None
            if type(s) is not str:
                return ev_seq(cx, a, st)
            pairs = [(s, a[1] if len(a) > 1 else "nil")]
        else:
            pairs = [(a[i], a[i + 1] if i + 1 < len(a) else "nil")
                     for i in range(0, len(a), 2)]
        for s, v in pairs:
            if s == "*error*" or type(s) is not str:
                continue
            st = ev(cx, v, st)
            if st is not None and tracked_global(cx, s):
                r = "g:" + s
                if returns_nil(cx.tier, cx.fn, v, cx):
                    st = release(cx, st, r)
                elif type(v) is str and tracked_global(cx, v):
                    # one run-state global copied into another carries
                    # its state: (setq a:*in-demo* a:*demo-call*)
                    src = get(st, "g:" + v)
                    st = setr(st, r, frozenset(
                        "F" if t == "F0" else t for t in src if t[0] != "H")
                        | (frozenset({"H@%s:%s" % (cx.where, f.line)})
                           if held(src) else frozenset()))
                    if held(src):
                        cx.emit("acq", r, f.line)
                else:
                    st = acquire(cx, st, r, f.line)
        return st
    if n == "progn":
        return ev_seq(cx, a, st)
    if n == "if":
        if not a:
            return st
        st1 = ev(cx, a[0], st)
        t = ev(cx, a[1], refine(cx, a[0], st1, True)) if len(a) > 1 \
            else refine(cx, a[0], st1, True)
        els = refine(cx, a[0], st1, False)
        e = ev_seq(cx, a[2:], els) if len(a) > 2 else els
        if len(a) > 1 and guards_release(cx, a[0], a[1]):
            return take_releases(join(t, e), st1, t)
        t, e = note_split(cx, (
            (t, arm_line(a[1] if len(a) > 1 else None, f)),
            (e, arm_line(a[2] if len(a) > 2 else None, f))))
        return join(t, e)
    if n == "cond":
        cur, outs = st, []
        for cl in a:
            if cur is None:
                break
            if type(cl) is not L or not cl:
                continue
            cur = ev(cx, cl[0], cur)
            outs.append((ev_seq(cx, cl[1:], refine(cx, cl[0], cur, True)),
                         arm_line(cl[1] if len(cl) > 1 else cl[0], cl)))
            if cl[0] == "t":
                cur = None
                break
            cur = refine(cx, cl[0], cur, False)
        outs = note_split(cx, outs + [(cur, f.line or cx.line)])
        cur = outs.pop()
        for o in outs:
            cur = join(cur, o)
        return cur
    if n in ("and", "or"):
        cur, outs = st, []
        for x in a:
            cur = ev(cx, x, cur)
            outs.append((refine(cx, x, cur, n == "or"),
                         getattr(x, "line", 0) or cx.line))
            cur = refine(cx, x, cur, n == "and")
        outs = note_split(cx, outs + [(cur, cx.line)])
        cur = outs.pop()
        for o in outs:
            cur = join(cur, o)
        return cur
    if n in ("while", "repeat", "foreach"):
        if n == "while":
            test, body, shadow = (a[0] if a else "nil"), a[1:], ()
        elif n == "repeat":
            st = ev(cx, a[0], st) if a else st
            test, body, shadow = None, a[1:], ()
        else:
            st = ev(cx, a[1], st) if len(a) > 1 else st
            test, body, shadow = None, a[2:], (a[0],) if a else ()
        old = cx.shadow
        cx.shadow = cx.shadow | frozenset(x for x in shadow
                                          if type(x) is str)
        cur = st
        for _ in range(LOOP_PASSES):
            t = ev(cx, test, cur) if test is not None else cur
            b = ev_seq(cx, body, refine(cx, test, t, True)
                       if test is not None else t)
            new = take_releases(join(cur, b), cur, b)
            if freeze(new) == freeze(cur):
                break
            cur = new
        cx.shadow = old
        if test is not None:
            return refine(cx, test, ev(cx, test, cur), False)
        return cur
    if n in DEATH:
        return None
    if n == "vl-catch-all-apply":
        st = ev_seq(cx, a[1:], st)
        cx.catch += 1
        after = call_value(cx, a[0] if a else None,
                           a[1] if len(a) > 1 else None, st)
        cx.catch -= 1
        return take_releases(join(st, after), st, after)
    if n == "apply":
        st = ev_seq(cx, a[1:], st)
        return call_value(cx, a[0] if a else None,
                          a[1] if len(a) > 1 else None, st)
    if n == "mapcar" and len(a) >= 3 and unquote(a[0]) == "setvar":
        # (mapcar 'setvar '("CMDECHO" "OSMODE") '(0 0)) mutes both; with
        # the values from anywhere else it puts back the ones it names
        st = ev_seq(cx, a[1:], st)
        names = literal_list(a[1])
        if names is None:
            return st if literal_list(a[2]) is not None \
                else table_restore(st)
        mute = literal_list(a[2]) is not None
        for nm in names:
            r = "sv:" + str(nm).upper()
            if r in cx.tracked:
                st = acquire(cx, st, r, f.line) if mute \
                    else release(cx, st, r)
        return st
    if n in MAYBE_CALL:
        fargs = [x for x in a if unquote(x) is not None or hd(x) == "lambda"]
        st = ev_seq(cx, [x for x in a if not (unquote(x) is not None
                                             or hd(x) == "lambda")], st)
        for x in fargs:
            after = call_value(cx, x, None, st)
            st = take_releases(join(st, after), st, after)
        return st
    # ---- resources -------------------------------------------------
    if n == "command-s" and cx.in_handler and held(get(st, "errmode")):
        # AutoCAD refuses command-s inside *error* under a pushed error
        # mode, past any vl-catch-all-apply: the handler dies HERE
        cx.emit("death", cx.heldset(st), f.line or cx.line)
        return None
    if n in CMD:
        return undo_effect(cx, a, ev_seq(cx, a, st), f.line)
    if n == "*push-error-using-command*":
        return acquire(cx, st, "errmode", f.line)
    if n == "*pop-error-mode*":
        return release(cx, st, "errmode")
    if n == "lzd:begin":
        return acquire(cx, ev_seq(cx, a, st), "lzd", f.line)
    if n in ("lzd:end", "lzd:report"):
        return release(cx, ev_seq(cx, a, st), "lzd")
    if n.startswith("lzd:"):
        return ev_seq(cx, a, st)
    if n == "vla-startundomark":
        return acquire(cx, ev_seq(cx, a, st), "undo", f.line)
    if n == "vla-endundomark":
        return release(cx, ev_seq(cx, a, st), "undo")
    if n == "setvar":
        return setvar_effect(cx, a, ev_seq(cx, a, st), f.line)
    st = ev_seq(cx, a, st)
    if callee is not None:
        return call_named(cx, callee, st, f)
    return st


def undo_effect(cx, args, st, line):
    if st is None or len(args) < 2 or not is_str(args[0]) \
            or not is_str(args[1]):
        return st
    if args[0].upper().lstrip("_.-") != "UNDO":
        return st
    opt = args[1].upper().lstrip("_")
    if opt.startswith("BE"):
        return acquire(cx, st, "undo", line)
    if opt.startswith("E"):
        return release(cx, st, "undo")
    return st


TABLE_READ = ("cdr", "cadr", "cdar", "nth", "car")


def table_restore(st):
    out = dict(st)
    for r in list(out):
        if r[:3] == "sv:" and held(out[r]):
            out[r] = FREE
    return out


def setvar_effect(cx, a, st, line):
    if st is None or not a:
        return st
    if not is_str(a[0]):
        # a name computed at run time is a table restore only when the
        # value comes out of the table too -- (setvar (car p) (cdr p));
        # spa:setv's (setvar v val) moves an unnamed sysvar, and frees
        # nothing the run holds
        v = a[1] if len(a) > 1 else None
        if hd(v) in TABLE_READ:
            return table_restore(st)
        return st
    name = a[0].upper()
    r = "sv:" + name
    if r not in cx.tracked:
        return st
    v = a[1] if len(a) > 1 else None
    if type(v) is str:
        # a restore puts back a value the tier took with (getvar "NAME")
        # -- oos, autobead:*oldos* -- or one handed in by a caller; a
        # local set from anything else (perp's srcLtype, off the source
        # entity) is a NEW value, and a mute like any other
        back = (not is_literal(v) and v not in cx.false
                and (v in cx.fn.params or name in cx.tier.snaps.get(v, ())))
    else:
        back = hd(v) in TABLE_READ and not any(
            x in cx.false for x in atoms(v))
    return release(cx, st, r) if back else acquire(cx, st, r, line)


def inline(cx, lam, st):
    """((lambda (v) ...) x) and a funarg lambda: evaluated in place."""
    p, l = params_locals(lam[1] if len(lam) > 1 else None)
    names = frozenset(p) | frozenset(l)
    old = (cx.shadow, cx.false, cx.true)
    cx.shadow = cx.shadow | names
    cx.false = cx.false - names
    cx.true = cx.true - names
    out = ev_seq(cx, lam[2:], st)
    cx.shadow, cx.false, cx.true = old
    return out


def call_value(cx, fn, arglist, st):
    if st is None:
        return None
    q = unquote(fn)
    target = q if q is not None else fn
    if type(target) is str:
        callee = cx.fn.calls.get(target)
        if callee is None:
            if target == "setvar" and hd(arglist) != "list":
                return table_restore(st)
            # a builtin applied to a literal (list ...): read it as the
            # call it is -- (vl-catch-all-apply 'command-s (list ...))
            args = list(arglist[1:]) if hd(arglist) == "list" else []
            call = L([target] + args)
            call.line = cx.line
            return ev(cx, call, st)
        return call_named(cx, callee, st, fn)
    if hd(target) == "lambda":
        return inline(cx, target, st)
    if hd(target) == "read" and any(x.lower().startswith("c:")
                                    for x in strings(target)):
        # (apply (read (strcat "c:" nm))): a stage chosen at run time.
        # Nothing to simulate -- charge it what no stage can put back
        hold = {r for r in cx.heldset(st, True) if r[:2] != "g:"}
        if hold and not cx.catch:
            cx.emit("bypass", "c:<dynamic>", (frozenset(hold), cx.line))
    return st


def arg_flags(cx, fn, form):
    fl, tr = set(), set()
    if type(form) is L and form and form[0] == fn.name:
        for i, p in enumerate(fn.params):
            arg = form[1 + i] if 1 + i < len(form) else "nil"
            if type(arg) is str:
                if arg == "nil" or arg in cx.false:
                    fl.add(p)
                elif arg == "t" or arg in cx.true or NUMBER.match(arg):
                    tr.add(p)
            elif is_str(arg):
                tr.add(p)
    return frozenset(fl), frozenset(tr)


def call_named(cx, fn, st, form):
    """Run FN's body against ST -- through the tier-wide memo.

    A summary is keyed on what FN's reach can see: the state of the
    resources it can touch (origins stripped), the symbols of its reach
    the caller knows to be nil or bound, and whether it runs caught or
    inside a handler.  Everything the caller holds beyond that passes
    through untouched and stands in the summary's events as PASS, so one
    summary of pool:report serves POOL, POOLCOVER, LAZFORM and LAZTXT."""
    if st is None:
        return None
    if len(cx.stack) > MAX_DEPTH or fn in cx.stack:
        return st
    an = cx.an
    rel = cx.tier.rel(fn)
    scope = fn.scope and fn is not cx.root
    if rel.inert:
        if rel.risky and not cx.catch and not scope:
            cx.emit("risk", cx.heldset(st))
        return st
    fl, tr = arg_flags(cx, fn, form)
    sub, passed = {}, []
    for r, v in st.items():
        if rel.covers(r):
            sub[r] = norm_tags(v)
        elif held(v):
            passed.append(r)
    tk = an.trk(cx.tracked, fn, rel)
    key = (fn, cx.catch > 0, cx.in_handler, frozenset(sub.items()), tk,
           cx.false & rel.syms, cx.true & rel.syms, cx.shadow & rel.syms,
           fl, tr)
    memo = an.memo.get(key)
    if memo is None:
        an.misses += 1
        memo = an.memo[key] = evaluate(cx, fn, sub, fl, tr)
    else:
        an.hits += 1
    out, evs = memo
    X = frozenset(passed) | ({PASS} if cx.inpass else frozenset())
    base = cx.hdepth + (1 if scope else 0)
    inner_risk = set()
    for (k, a, b, h, w) in evs:
        if k == "risk":
            a = expand(a, X)
            if scope and h == 0:
                inner_risk |= a
        elif k == "death":
            a = expand(a, X)
        elif k == "bypass":
            leaked = expand(b[0], X)
            if not leaked:
                continue
            b = (leaked, b[1])
        cx.events.setdefault((k, a, b, h + base, w), None)
    if scope:
        bypass(cx, fn, st, inner_risk, rel, form)
    if out is None:
        return None
    new = {r: v for r, v in st.items() if not rel.covers(r)}
    for r, v in out.items():
        if IN in v:
            v = (v - {IN}) | frozenset(t for t in get(st, r)
                                       if t[0] in ("H", "X"))
        new[r] = v
        if scope and held(v) and not held(get(st, r)):
            # what the inner scope hands back held is the caller's now
            cx.emit("acq", r, getattr(form, "line", 0) or cx.line)
    return new


def expand(s, X):
    if PASS in s:
        return (s - {PASS}) | X
    return s


def evaluate(cx, fn, sub, fl, tr):
    saved = (cx.events, cx.hdepth, cx.shadow, cx.false, cx.true,
             cx.inpass, cx.where, cx.fn, cx.line)
    cx.events, cx.hdepth, cx.inpass = {}, 0, True
    cx.shadow = cx.shadow | fn.names
    cx.false = (cx.false - fn.names) | fl
    cx.true = (cx.true - fn.names) | tr
    cx.where, cx.fn = fn.name, fn
    cx.stack.append(fn)
    out = ev_seq(cx, fn.body, sub)
    cx.stack.pop()
    evs = tuple(cx.events)
    (cx.events, cx.hdepth, cx.shadow, cx.false, cx.true, cx.inpass,
     cx.where, cx.fn, cx.line) = saved
    return out, evs


def bypass(cx, fn, st, inner_risk, rel, form):
    """FN is an inner scope, called while the caller holds things.  An
    error in there runs only FN's *error*: whatever the caller still
    holds at FN's own risk points, and FN's handler does not free, is
    left behind."""
    if cx.catch:
        return
    hold = cx.heldset(st, True)
    cand = hold & frozenset(inner_risk)
    if not cand:
        return
    own = {r for r in cand if r != PASS and rel.covers(r)}
    leaked = {r for r in cand if r == PASS or not rel.covers(r)}
    if own:
        leaked |= cx.an.handler_leaks(cx, fn, {r: st[r] for r in own})
    if "errmode" in hold and any(g.pushes for g in cx.tier.reach(fn)):
        leaked.add("errmode")     # its pop is for its own push
    if leaked:
        cx.emit("bypass", fn.name,
                (frozenset(leaked), getattr(form, "line", 0) or cx.line))


# ---------------------------------------------------------------------
#  Per tier: every scope's run, its handlers, and the stale pass
# ---------------------------------------------------------------------

class Analysis:
    def __init__(self, tier):
        self.tier = tier
        self.memo = {}
        self.hits = self.misses = 0
        self._trk = {}
        self._hleak = {}

    def trk(self, tracked, fn, rel):
        k = (tracked, fn)
        t = self._trk.get(k)
        if t is None:
            t = self._trk[k] = frozenset(r for r in tracked if rel.covers(r))
        return t

    def handler_leaks(self, cx, fn, state):
        """What FN's handlers leave held of STATE, run with FN's own
        locals nil (the inner's flags were never set for the caller's
        resources)."""
        rel = self.tier.rel(fn)
        key = (fn, frozenset((r, norm_tags(v)) for r, v in state.items()),
               self.trk(cx.tracked, fn, rel))
        out = self._hleak.get(key)
        if out is None:
            out = set()
            for params, body, _ in fn.handlers:
                hx = Ctx(self, cx.tracked, fn)
                hx.shadow = fn.names | frozenset(params)
                hx.false = fn.names
                hx.where = fn.name
                hout = ev_seq(hx, body, dict(state))
                for (k, a, b, h, w) in hx.events:
                    if k == "death":
                        out |= {r for r in state if r in a}
                if hout is not None:
                    out |= {r for r in state if held(get(hout, r))}
            out = self._hleak[key] = frozenset(out)
        return out

    def run(self, fn, tracked, init):
        cx = Ctx(self, tracked, fn)
        cx.shadow = fn.names
        out = ev_seq(cx, fn.body, dict(init))
        return out, cx.events

    def audit(self, fn):
        tier = self.tier
        tracked = tier.tracked(fn)
        out, evs = self.run(fn, tracked, {})
        origin, at_risk = {}, set()
        bypasses = []
        for (k, a, b, h, w) in evs:
            if k == "acq":
                origin.setdefault(a, "%s:%s" % (w, b))
            elif k == "risk" and h == 0:
                at_risk |= a
            elif k == "bypass" and h == 0:
                bypasses.append((a, b[0], b[1], w))
        res = {"fn": fn, "tracked": tracked, "exit": {}, "handler": {},
               "bypass": bypasses, "ways": {}}
        if out is not None and fn.name.startswith("c:"):
            for r, v in out.items():
                if held(v):
                    res["exit"][r] = sorted(t[2:] for t in v if t[0] == "H")
                    res["ways"][r] = sorted(
                        (tuple(t[2:].rsplit(":", 1))
                         for t in v if t[0] == "X"),
                        key=lambda x: (int(x[1]), x[0]))
        for params, body, hline in fn.handlers:
            hx = Ctx(self, tracked, fn, in_handler=True)
            hx.shadow = fn.names | frozenset(params)
            hx.where = "*error*"
            init = {r: frozenset({"H@" + origin.get(r, fn.name)})
                    for r in at_risk if r != PASS}
            hout = ev_seq(hx, body, init)
            for (k, a, b, h, w) in hx.events:
                if k == "death" and h == 0:
                    where = "%s:%s" % ("*error*" if w == fn.name else w, b)
                    for r in a:
                        if r in init:
                            res["handler"][r] = (init[r], where)
            if hout is not None:
                for r, v in hout.items():
                    if held(v) and r in init:
                        res["handler"].setdefault(r, (v, None))
        return res


def leavers_of(results):
    out = collections.defaultdict(set)
    for r in results:
        name = r["fn"].name.upper()
        for x in r["exit"]:
            if x[:2] == "g:":
                out[x].add((name, "a clean exit"))
        for x in r["handler"]:
            if x[:2] == "g:":
                out[x].add((name, "Esc or an error"))
        for callee, leaked, line, inside in r["bypass"]:
            for x in leaked:
                if x[:2] == "g:":
                    out[x].add((name, "an error inside " + callee.upper()))
    return out


def stale_pass(an, results, leavers):
    """Re-run every command that can read a leftover, with each leftover
    it can see starting STALE: a read of one before this run wrote it is
    the finding.  Only commands whose reach names a leftover are re-run
    -- a STALE value changes a path only where it is read.  LEAVERS maps
    "g:NAME" to what leaves it; the same pass serves SIBLING, whose
    leftovers are the globals nothing ever clears."""
    tier = an.tier
    out = []
    for r in results:
        fn = r["fn"]
        if not fn.name.startswith("c:"):
            continue
        syms = tier.rel(fn).syms
        gs = {g for g in leavers if g[2:] in syms}
        if not gs:
            continue
        tracked = r["tracked"] | frozenset(gs)
        _, evs = an.run(fn, tracked, {g: STALE for g in gs})
        seen = set()
        for (k, a, b, h, w) in evs:
            if k == "read" and "S" in b[0] and a not in seen:
                seen.add(a)
                out.append((fn, "g:" + a, w, b[1], leavers["g:" + a]))
    return out


# ---------------------------------------------------------------------
#  The lexical rules
# ---------------------------------------------------------------------

def resets_errno(f):
    if hd(f) == "setvar" and len(f) >= 3 and is_str(f[1]) \
            and f[1].upper() == "ERRNO":
        return True
    return hd(f) == "vl-catch-all-apply" and len(f) >= 3 \
        and unquote(f[1]) == "setvar" and hd(f[2]) == "list" \
        and len(f[2]) >= 2 and is_str(f[2][1]) \
        and f[2][1].upper() == "ERRNO"


def rule_errno(tier):
    out = []
    for p in tier.paths:
        d = tier.per_file[p]
        begin_resets = any("begin" in n and any(resets_errno(f)
                                                for f in walk(fn.df))
                           for n, fn in d.items())
        if begin_resets:
            continue
        for name, fn in d.items():
            seen = False
            for f in walk(fn.df):
                seen = seen or resets_errno(f)
                if hd(f) == "getvar" and len(f) == 2 and is_str(f[1]) \
                        and f[1].upper() == "ERRNO" and not seen:
                    out.append((fn, f.line))
                    break
    return out


def rule_handoff(tier):
    names = {c.name[2:].upper() for c in tier.commands}
    out = []
    for fn in tier.fns:
        for f in walk(fn.df):
            h, args = hd(f), None
            if h in CMD:
                args = f[1:]
            elif h in ("vl-catch-all-apply", "apply") and len(f) >= 3 \
                    and unquote(f[1]) in CMD and hd(f[2]) == "list":
                args = f[2][1:]
            if args and is_str(args[0]):
                nm = args[0].upper().lstrip("_.-'").strip()
                if nm in names:
                    out.append((fn, f.line, str(args[0])))
    return out


def sibling_candidates(tier):
    """Globals set at run time and NEVER cleared at run time, whose
    suffix siblings in other tools mostly are: {"g:NAME": [siblings]}.
    STALE cannot see one -- with no run-time nil it is not run state --
    so these go through the same re-run, and only a command that reads
    one before it writes it is a finding."""
    val, nil = set(), set()
    for fn in tier.fns:
        for g, kinds in fn.writes.items():
            if "val" in kinds:
                val.add(g)
            if "nil" in kinds:
                nil.add(g)
    by_suffix = collections.defaultdict(dict)
    for g in val:
        if ":" in g:
            by_suffix[g.split(":")[-1]][g] = g in nil
    out = {}
    for suf, gs in by_suffix.items():
        cleared = sorted(g for g, c in gs.items() if c)
        never = sorted(g for g, c in gs.items() if not c)
        if len(cleared) >= 2 and never and len(cleared) > len(never):
            for g in never:
                out["g:" + g] = cleared
    return out


# ---------------------------------------------------------------------
#  Findings, the baseline, and the report
# ---------------------------------------------------------------------

DATED_SUFFIX = re.compile(r"_\d{6}_rev[\d-]+(?=\.lsp$)")


def filekey(path):
    return DATED_SUFFIX.sub("", pathlib.Path(path).name.lower())


def relpath(path):
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path


WHAT = {"undo": "its undo group open",
        "errmode": "the error mode pushed",
        "lzd": "its LAZDIAG run open"}
WHY = {"undo": "everything the drafter does next joins this run's group, "
               "and one U takes the lot back",
       "errmode": "stacked, it refuses command-s inside every later "
                  "handler in the session",
       "lzd": "the next command is joined to it, or logs it 'ok' with "
              "its answers dropped"}


LABEL = {"undo": "the undo group", "errmode": "the pushed error mode",
         "lzd": "the LAZDIAG run"}


def label(r):
    return LABEL.get(r) or (r[3:] if r[:3] == "sv:" else r[2:])


def what(r):
    if r in WHAT:
        return WHAT[r]
    if r[:3] == "sv:":
        return r[3:] + " as the run set it"
    return r[2:] + " set"


class Finding:
    def __init__(self, fn, rule, resource, text, line=None):
        self.fn, self.rule, self.resource = fn, rule, resource
        self.text = text
        self.line = line or fn.line
        bare = resource[2:] if resource[:2] == "g:" else (
            resource[3:] if resource[:3] == "sv:" else resource)
        self.key = (filekey(fn.path), fn.name, rule, bare.lower())

    def show(self):
        return "%s:%d: %s %s -- %s" % (relpath(self.fn.path), self.line,
                                       self.fn.name.upper(), self.rule,
                                       self.text)


def findings(tier):
    """Every finding on TIER, and the analysis that made them."""
    an = Analysis(tier)
    names = sorted(set(tier.commands) | set(tier.scopes),
                   key=lambda f: (str(f.path), f.line))
    results = [an.audit(fn) for fn in names]
    out = []
    for r in results:
        fn = r["fn"]
        own = tier.per_file[fn.path]
        for x, org in sorted(r["exit"].items()):
            if x[:2] == "g:":
                continue
            ways = r["ways"].get(x, ())
            here = [int(ln) for w, ln in ways if w in own]
            out.append(Finding(fn, "EXIT", x, "a clean exit leaves %s "
                               "(taken at %s%s): %s."
                               % (what(x), ", ".join(org),
                                  ("; still held on the way out at %s"
                                   % ", ".join("%s:%s" % s for s in ways))
                                  if ways else "",
                                  WHY.get(x, "the drafter's next command "
                                          "starts from it")),
                               here[0] if here else None))
        for x, (tags, death) in sorted(r["handler"].items()):
            if x[:2] == "g:":
                continue
            org = ", ".join(sorted(t[2:] for t in tags if t[0] == "H"))
            out.append(Finding(fn, "HANDLER", x, "its *error* does not "
                               "free %s, held where the run can fail "
                               "(taken at %s)%s."
                               % (label(x), org, (" -- the handler dies "
                                                  "at %s, "
                                           "command-s under the pushed "
                                           "error mode" % death)
                                  if death else "")))
        seen = set()
        for callee, leaked, line, inside in r["bypass"]:
            leaked = sorted(x for x in leaked if x[:2] != "g:" and x != PASS)
            if not leaked or (callee, tuple(leaked)) in seen:
                continue
            seen.add((callee, tuple(leaked)))
            out.append(Finding(fn, "BYPASS", callee, "calls %s at line %d "
                               "(in %s) holding %s; an error in there runs "
                               "only %s's own *error*, which does not free "
                               "them." % (callee.upper(), line, inside,
                                          ", ".join(label(x) for x in leaked),
                                          callee.upper()),
                               line))
    leavers = {g: sorted(w) for g, w in leavers_of(results).items()}
    for fn, g, inside, line, who in stale_pass(an, results, leavers):
        out.append(Finding(fn, "STALE", g, "reads %s (in %s, line %s) "
                           "before this run sets it, and %s can leave it "
                           "set: a run after that one starts from the dead "
                           "run's value." % (g[2:], inside, line,
                                             "; ".join("%s on %s" % c
                                                       for c in who))))
    sibs = {g: v for g, v in tier.siblings.items() if g not in leavers}
    for fn, g, inside, line, cleared in stale_pass(an, results, sibs):
        out.append(Finding(fn, "SIBLING", g, "reads %s (in %s, line %s) "
                           "before this run sets it, and nothing in the "
                           "tier ever clears it -- while %s, the same "
                           "thing in other tools, are cleared at run time: "
                           "each run starts from whatever the last one "
                           "left." % (g[2:], inside, line,
                                      ", ".join(cleared))))
    for fn, line in rule_errno(tier):
        out.append(Finding(fn, "ERRNO", "ERRNO", "reads ERRNO with no "
                           "reset before it: ERRNO is sticky, so an earlier "
                           "command's failure reads as this one's.", line))
    for fn, line, s in rule_handoff(tier):
        out.append(Finding(fn, "HANDOFF", s.upper().lstrip("_.-'"),
                           "(command \"%s\") names an AutoLISP command of "
                           "this tier: the command processor cannot reach "
                           "one, so it never starts." % s, line))
    return out, an, len(results)


def load_baseline(path=None):
    """{(file, defun, RULE, resource): reason}, and any malformed line."""
    base, bad = {}, []
    path = BASELINE if path is None else path
    if not pathlib.Path(path).is_file():
        return base, bad
    for n, ln in enumerate(pathlib.Path(path).read_text(
            encoding="utf-8").splitlines(), 1):
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("|", 4)
        if len(parts) < 5 or parts[2].strip().upper() not in RULES \
                or not parts[4].strip() \
                or (parts[1].strip() == "*"
                    and parts[2].strip().upper() not in WILD_RULES):
            # * accepts every reader of a global kept between runs on
            # purpose; an exit or a handler is one site, and is named
            bad.append((n, ln))
            continue
        f, d, rule, res, why = (p.strip() for p in parts)
        base[(f.lower(), d.lower(), rule.upper(), res.lower())] = why
    return base, bad


def accepted(f, base):
    if f.key in base:
        return f.key
    if f.rule in WILD_RULES:
        wild = (f.key[0], "*", f.rule, f.key[3])
        if wild in base:
            return wild
    return None


TIERS = {"lisp": (LISP_DIR, "lisp/"), "shared": (PARTS_DIR, "shared/parts/"),
         "releases": (RELEASES_DIR, "releases/")}


def report(paths, base, show_all=False, out=print, label=None):
    """Read PATHS as one tier and print every finding outside BASE; the
    finding count, and the baseline keys it matched."""
    tier = Tier(paths)
    found, an, nscopes = findings(tier)
    used, n = set(), 0
    for f in found:
        k = accepted(f, base)
        if k is not None:
            used.add(k)
            if show_all:
                out("check_leaks: [baselined] " + f.show())
            continue
        n += 1
        out("check_leaks: " + f.show())
    if label:
        out("check_leaks: %s -- %d command(s) and handler scope(s) read, %s"
            % (label, nscopes, ("%d finding(s)" % n) if n else
               "every borrow is given back on every way out"))
    return n, used


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--tier", default="all",
                    choices=("lisp", "shared", "releases", "both", "all"),
                    help="which tier(s) to read (default all three: a "
                         "dated twin in releases/ is what a shop pins "
                         "to; both = lisp/ and shared/parts/ only)")
    ap.add_argument("--all", action="store_true",
                    help="print the baselined findings too")
    a = ap.parse_args(argv)
    want = {"both": ["lisp", "shared"], "all": ["lisp", "shared", "releases"]
            }.get(a.tier, [a.tier])
    base, bad = load_baseline(BASELINE)
    total, used = 0, set()
    for n, ln in bad:
        print("check_leaks: %s:%d is not file|defun|RULE|resource|reason: "
              "%s" % (BASELINE.name, n, ln))
    for t in want:
        d, label = TIERS[t]
        n, u = report(lsp_files(d), base, a.all, label=label)
        total += n
        used |= u
    stale = sorted(k for k in base if k not in used)
    if set(want) >= {"lisp", "shared"}:
        for k in stale:
            print("check_leaks: %s: %s -- nothing matches this line any "
                  "more; drop it" % (BASELINE.name, "|".join(k)))
    else:
        stale = []
    return 1 if (total or stale or bad) else 0


if __name__ == "__main__":
    sys.exit(main())
