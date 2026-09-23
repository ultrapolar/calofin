#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every input asks for what the drafter can actually give it.

Two AutoCAD input facts that shipped quiet failures past every test,
because until the test VM modelled them (lispvm.MISS, the spacebar
rule) nothing could see them -- and the VM only sees what a test
reaches, so this reads every pick and every prompt in the tree:

  A MISS IS NIL.  A click on empty paper at an entsel answers nil,
        exactly as Enter does.  The only difference is ERRNO: 7 for
        the miss.  ERRNO is STICKY -- a failing call sets it and a
        later answer is not promised to clear it (a keyword, a point,
        a pick that hits all leave it be; what a release writes on a
        null response varies) -- so a read means THIS pick, on every
        release, only when it was zeroed right before the pick.  SPA,
        SPACOVCREATE, COVERCHECK, POOL's Given flip and the five fit
        pickers each took a click just beside the thing as the Enter
        default: a Thermo-Light cover drawn as a Standard one, a
        disclaimer reported MISSING in red a few units from where it
        stood, the fit the drafter reached for erased.

  A SPACE IS ENTER.  At every input but (getstring T ...) the spacebar
        ends the answer.  A prompt, hint or caption that shows a spaced
        answer -- 44 1/2, 4'-4 1/2", 1524 MM -- teaches a keystroke
        sequence that arrives as TWO answers, the second one to the next
        question: CORNERSTP took '24 1/8' as a 24" tread and a 1/8"-wide
        step, and said "3 step(s) drawn".

Three rules, over every tier (a dated twin is what a shop pins to):

  PICK    An entsel / nentsel / nentselp whose nil answer is a DECISION
          -- it ends a loop, takes a default, skips an offer or the
          item, is kept as the value -- without telling the miss from
          Enter.  Safe shapes, which pass:
            * ERRNO zeroed before the pick, in the same pass of its loop
              (or, for a pick that opens a helper with no loop of its
              own, right before EVERY call of that helper), and read
              after it ((= 7 (getvar "ERRNO")) asks again);
            * the nil branch only SPEAKS (princ, prompt, a helper that
              only prints) and the SAME question comes round again: a
              recursive call, or a WHILE that does not move its own
              test on whatever the pick answered (UPADOVER, WCALST,
              PERPMARK).  A foreach, a repeat or a mapcar lambda asks
              about the NEXT item, so a miss there is a skip for good;
              and a while that advances its list, or sets its exit, on
              every pass is the same thing in a while's clothes.
          A decision somebody made on purpose goes in the baseline.
  STICKY  ERRNO read after a pick, but not answering for THAT pick: it
          was not zeroed before the pick in that same pass (a 7 left by
          an earlier miss is read as this one's, and a real Enter is
          taken for a miss), or it was zeroed AGAIN between the pick and
          the read (the miss's 7 is wiped before anyone looks).  Never
          baselined -- zero it right before the pick, wrapped as
          (vl-catch-all-apply 'setvar (list "ERRNO" 0)).
  SPACE   A string literal that shows a spaced mixed fraction
          (\\d['"]? +\\d+/\\d+) anywhere, or a number and a unit word
          (1524 MM) in the prompt of a spacebar-ended input.  Exempt: the
          prompt of a (getstring T ...) -- directly, or through a
          wrapper's parameter, to any depth -- and a hint printed in a
          defun whose only inputs are such prompts (abcdef:getdim).  The
          exemption is WITHDRAWN when the same file also reads free text
          at a spacebar-ended prompt ((initget 128)): that is DIMSTAMP,
          whose first prompt taught a spelling its unified prompt could
          not take.  The generated knob catalog (lzp:*knobs*) is not read:
          it is transcribed from tunables comments that describe a size,
          and the comment is where such a spelling would be fixed.

Sites that are decisions somebody made stay in tools/input_baseline.txt
with the reason, check_back's pattern: file|defun|what it asks|why.  A
NEW site fails, and a baseline line nothing matches any more is
reported as stale.  A line matches its site in every tier: the file is
keyed by its stem, so lisp/pool/POOL.LSP, shared/parts/POOL.lsp and
releases/POOL_092226_REV41.LSP are one site.

What this cannot see: whether the miss is HANDLED well once it is told
apart, and what the VM does with a miss or a space.  That is the VM
half -- lispvm.MISS and a spacebar that splits a typed answer -- which
drives the behaviour as far as the tests reach.  A while is taken to
ask the same question again unless its body moves its own test
unconditionally (a top-level setq of a variable the test reads, not
fed by the pick); a loop that advances through a helper is not seen.
And SPACE reads LITERALS only: computed text -- (rtos x) under LUNITS
4 or 5, a tool's own feet-inch formatter -- can print 3'-8 1/2" too.
Every such value in lisp/ today is a <default> or a 'Same = ...' that
Enter or a keyword takes, never an example to type, which is why a
literal is where the rule looks.

    python3 tools/check_input.py [--tier lisp|shared|releases|all] [--list]
"""

import argparse
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from callib import (BUNDLES, LISP_DIR, PARTS_DIR, RELEASES_DIR,  # noqa: E402
                    ROOT, decomment, lsp_files)
from check_handlers import (Str, Sym, arglist, body_of,  # noqa: E402
                            read_forms)
from check_osnap import callees, defuns, reach  # noqa: E402

BASELINE = HERE / "input_baseline.txt"
SKIP_DIRS = ("standards_checker",)

PICKS = ("entsel", "nentsel", "nentselp")
#: the inputs a space ends.  getstring is one too, unless it is called
#: with its cr flag -- see input_kind.
SPACE_ENDED = frozenset(("getpoint", "getdist", "getreal", "getint",
                         "getkword", "getcorner", "getangle",
                         "getorient") + PICKS)
INPUTS = SPACE_ENDED | {"getstring"}

FRACTION = re.compile(r"\d['\"]? +\d+/\d+")
UNIT = re.compile(r"\d +(?:mm|cm|m|in|ft)\b", re.IGNORECASE)

LOOPS = ("while", "repeat", "foreach")
#: appliers whose lambda argument runs once per element: a loop too
MAPPERS = ("mapcar", "vl-some", "vl-every", "vl-member-if",
           "vl-member-if-not", "vl-remove-if", "vl-remove-if-not")
#: forms that only speak: a nil branch made of these changes nothing, so
#: the loop round the pick asks again.  Pure readers are here because a
#: message is built out of them.
SPEAK = frozenset((
    "princ", "prompt", "print", "prin1", "terpri", "alert", "strcat",
    "itoa", "rtos", "angtos", "strcase", "substr", "strlen", "vl-princ-to-string",
    "vl-prin1-to-string", "if", "progn", "cond", "and", "or", "not", "null",
    "=", "/=", "eq", "equal", "car", "cdr", "cadr", "assoc", "nth", "length",
    "getvar", "grtext", "redraw"))
#: (quote is not one: a branch that is 'SKIP or 'DONE hands back a VALUE,
#: and a value is what a decision looks like)

#: LAZDIAG's hooks stand between every pick and its test; they record,
#: they decide nothing.  lzd:begin also clears ERRNO -- for its own
#: report, once a run, only when LAZDIAG is loaded -- so it is not a
#: pick's clear either.
LZD = "lzd:"
#: top-level data that is not a prompt, a hint or a caption
GENERATED = frozenset(("lzp:*knobs*", "lzp:*knobfam*"))


# ---------------------------------------------------------------------
#  reading: check_handlers' line-keeping reader, memoised by text the
#  way check_osnap.forms_of is -- a releases/ twin is byte-for-byte its
#  lisp/ file, so the three tiers parse little more than one
# ---------------------------------------------------------------------

_FORMS = {}


def forms_of(text):
    forms = _FORMS.get(text)
    if forms is None:
        forms = _FORMS[text] = read_forms(decomment(text))
    return forms


def hd(f):
    """The head symbol of F, lower-cased; None for data and atoms."""
    if isinstance(f, list) and f and isinstance(f[0], Sym):
        return f[0].lower()
    return None


def sym(x):
    return x.lower() if isinstance(x, Sym) else None


def unesc(s):
    """A literal's text as the drafter reads it."""
    return (s.replace("\\n", "\n").replace("\\t", "\t")
            .replace('\\"', '"').replace("\\\\", "\\"))


def flat(s, n=90):
    return " ".join(unesc(s).split())[:n]


def render(x):
    """A prompt expression as its words, computed parts in braces:
    (strcat "\\n" msg " [" kw "]: ") -> '{msg} [{kw}]:'.  What a
    baseline line names a site by, so it survives a move."""
    if isinstance(x, Str):
        return unesc(x)
    if isinstance(x, Sym):
        return "{%s}" % x.lower()
    h = hd(x)
    if h == "strcat":
        return "".join(render(a) for a in x[1:])
    if h == "if" and len(x) > 2:
        return render(x[2])         # the then-branch: the fuller wording
    return "{%s}" % (h or "...")


def fingerprint(x):
    return " ".join(render(x).split())[:90] if x is not None else ""


def names_errno(x):
    if isinstance(x, Str):
        return x.upper() == "ERRNO"
    return hd(x) == "quote" and len(x) > 1 and sym(x[1]) == "errno"


def zero_form(f):
    """(setvar "ERRNO" 0) in either spelling, bare or caught."""
    h = hd(f)
    if h == "setvar" and len(f) > 1 and names_errno(f[1]):
        return True
    if h in ("vl-catch-all-apply", "apply") and len(f) > 2 \
            and hd(f[1]) in ("quote", "function") and len(f[1]) > 1 \
            and sym(f[1][1]) == "setvar":
        a = f[2]
        if hd(a) == "list" and len(a) > 1 and names_errno(a[1]):
            return True
        if hd(a) == "quote" and isinstance(a[1], list) and a[1] \
                and names_errno(a[1][0]):
            return True
    return False


def read_form(f):
    return hd(f) == "getvar" and len(f) > 1 and names_errno(f[1])


def input_kind(f):
    """'space' / 'line' for an input call, None for anything else.
    (getstring T ...) -- any non-nil first argument -- takes a space."""
    h = hd(f)
    if h in SPACE_ENDED:
        return "space"
    if h == "getstring":
        # (getstring T), (getstring T msg), (getstring flag msg): the
        # first of two arguments is the flag.  A lone argument is the
        # prompt -- a string, a (strcat ...) or a variable holding one --
        # unless it is the literal T.
        if len(f) > 2:
            return "space" if sym(f[1]) == "nil" else "line"
        if len(f) == 2 and sym(f[1]) == "t":
            return "line"
        return "space"
    return None


def prompt_arg(f):
    """The prompt argument of an input call, or None: after the base
    point of a (getpoint pt msg) and its kin, after the flag of a
    (getstring T msg)."""
    h = hd(f)
    if h == "getstring":
        if len(f) > 2:
            return f[2]
        return None if len(f) < 2 or sym(f[1]) == "t" else f[1]
    if h in ("getpoint", "getdist", "getangle", "getorient", "getcorner") \
            and len(f) > 2:
        return f[2]
    return f[1] if len(f) > 1 else None


def initget_bits(x):
    """The bits an (initget ...) argument can carry, as far as a literal
    says; both branches of an if."""
    if isinstance(x, Sym):
        try:
            return int(x)
        except ValueError:
            return 0
    h = hd(x)
    if h in ("+", "logior"):
        out = 0
        for a in x[1:]:
            out |= initget_bits(a)
        return out
    if h == "if":
        return initget_bits(x[2] if len(x) > 2 else None) | \
            initget_bits(x[3] if len(x) > 3 else None)
    return 0


def params(d):
    p, _ = arglist(d)
    return p


# ---------------------------------------------------------------------
#  one tier: every defun by name, what each calls, and which of them
#  zero or read ERRNO (through helpers too), and which only speak
# ---------------------------------------------------------------------

_DEFUNS = {}


def _defuns_of(forms):
    """check_osnap.defuns, once per distinct text."""
    d = _DEFUNS.get(id(forms))
    if d is None:
        d = _DEFUNS[id(forms)] = defuns(forms)
    return d


def own_nodes(form):
    """Every list inside FORM, outer first, not entering a nested defun
    (that one is its own owner)."""
    stack = [form]
    while stack:
        f = stack.pop()
        yield f
        for x in reversed(f):
            if isinstance(x, list) and hd(x) != "defun":
                stack.append(x)


class Tier:
    def __init__(self, paths):
        self.paths = [p for p in paths
                      if not any(s in p.parts for s in SKIP_DIRS)]
        self.files = {}
        self.texts = {}
        self.per_file = {}
        self.dmap = {}
        for p in self.paths:
            text = p.read_text(encoding="utf-8", errors="replace")
            forms = forms_of(text)
            self.files[p], self.texts[p] = forms, text
            self.per_file[p] = d = _defuns_of(forms)
            for name, bodies in d.items():
                self.dmap.setdefault(name, []).extend(bodies)
        self.calls = callees(self.dmap)
        direct_zero, direct_read = set(), set()
        for name, bodies in self.dmap.items():
            if name.startswith(LZD):
                continue
            for b in bodies:
                for f in own_nodes(b):
                    if zero_form(f):
                        direct_zero.add(name)
                    if read_form(f):
                        direct_read.add(name)
        self.zero_seed, self.read_seed = direct_zero, direct_read
        self._reach = {}
        self._owners = {}
        self._by_callers = {}
        self.speakers = self._speakers()
        self.pp = self._prompt_params()

    def owner(self, d):
        ow = self._owners.get(id(d))
        if ow is None:
            ow = self._owners[id(d)] = Owner(d)
        return ow

    def first_in(self, ow, a, b, pred, seed):
        """The first position strictly between A and B in OW whose form
        satisfies PRED, or calls a helper that reaches SEED; None."""
        for i in range(a + 1, b):
            f = ow.order[i]
            if pred(f):
                return i
            h = hd(f)
            if h and h not in INPUTS and self.reaches(h, seed):
                return i
        return None

    def zeroed_by_callers(self, name):
        """Every call of NAME in the tier comes after an ERRNO zero in
        the caller's own pass, with no other pick between them -- the
        caller's loop zeroes, then asks the helper that picks.  False
        when nothing calls NAME."""
        got = self._by_callers.get(name)
        if got is not None:
            return got
        self._by_callers[name] = False      # a cycle answers no
        seen = False
        ok = True
        for caller, bodies in self.dmap.items():
            if name not in self.calls.get(caller, ()):
                continue
            for d in bodies:
                ow = self.owner(d)
                sites = [f for f in own_nodes(d) if hd(f) == name]
                bounds = [f for f in own_nodes(d)
                          if hd(f) == name or
                          (hd(f) in PICKS and interactive(f))]
                for c in sites:
                    seen = True
                    w = Window(ow, c, bounds)
                    if self.first_in(ow, w.prev, w.p, zero_form,
                                     self.zero_seed) is None:
                        ok = False
        self._by_callers[name] = got = seen and ok
        return got

    def reaches(self, name, seed):
        """Does calling NAME run a form in SEED (zero or read ERRNO)?"""
        if name not in self.dmap or name.startswith(LZD):
            return False
        r = self._reach.get(name)
        if r is None:
            r = self._reach[name] = {n for n in reach([name], self.dmap,
                                                      self.calls)
                                     if not n.startswith(LZD)}
        return bool(r & seed)

    def _speakers(self):
        """Helpers that only print: every call in them speaks, and every
        setq is to a local of their own."""
        out = set()
        grew = True
        while grew:
            grew = False
            for name, bodies in self.dmap.items():
                if name in out or name.startswith("c:"):
                    continue
                if all(self._speaks_body(b, out) for b in bodies):
                    out.add(name)
                    grew = True
        return out

    def _speaks_body(self, d, speakers):
        p, loc = arglist(d)
        mine = set(p) | set(loc)
        for f in own_nodes(list(body_of(d))):
            h = hd(f)
            if f is not d and h == "setq":
                if not all(sym(f[i]) in mine for i in range(1, len(f), 2)):
                    return False
                continue
            if h is None or h in SPEAK or h in speakers or h in mine \
                    or h.startswith(LZD):
                continue
            return False
        return True

    def _prompt_params(self):
        """name -> {argument index: 'space' | 'line'} for every defun
        that hands a parameter on as the prompt of an input -- directly,
        or into another such defun, to a fixed point.  'space' wins when
        one parameter reaches both kinds."""
        uses = []          # (defun, param index, callee or kind, arg index)
        for name, bodies in self.dmap.items():
            for d in bodies:
                ps = params(d)
                if ps:
                    _param_uses(name, d, ps, self.dmap, uses)
        pp = {}
        changed = True
        while changed:
            changed = False
            for name, pi, callee, ai in uses:
                if ai is None:
                    kind = callee
                else:
                    kind = pp.get(callee, {}).get(ai)
                    if kind is None:
                        continue
                cur = pp.setdefault(name, {})
                new = "space" if "space" in (cur.get(pi), kind) else kind
                if cur.get(pi) != new:
                    cur[pi] = new
                    changed = True
        return pp

    def call_kind(self, f):
        """The input kind of F: an input call, or a call to a prompt
        wrapper -- the most permissive of its prompt parameters."""
        k = input_kind(f)
        if k:
            return k
        h = hd(f)
        if h in self.pp:
            kinds = set(self.pp[h].values())
            return "space" if "space" in kinds else "line"
        return None


def _param_uses(name, d, ps, dmap, uses):
    """Record, bottom-up in one pass over D, every input call and every
    call to a defun of the tier that has one of D's parameters PS in an
    argument, as (NAME, parameter index, kind or callee, argument index)."""
    index = {p: i for i, p in enumerate(ps)}

    def rec(f):
        if isinstance(f, Sym):
            s = f.lower()
            return {s} if s in index else ()
        if not isinstance(f, list) or hd(f) == "defun" and f is not d:
            return ()
        found = set()
        per_arg = []
        for x in f:
            got = rec(x)
            per_arg.append(got)
            found.update(got)
        h = hd(f)
        if found and h and f is not d:
            kind = input_kind(f)
            if kind or h in dmap:
                for i, got in enumerate(per_arg[1:]):
                    for s in got:
                        uses.append((name, index[s], kind or h,
                                     None if kind else i))
        return found

    for x in body_of(d):
        rec(x)


def _atoms(f):
    if isinstance(f, list):
        for x in f:
            yield from _atoms(x)
    elif isinstance(f, Sym):
        yield f


# ---------------------------------------------------------------------
#  PICK and STICKY
# ---------------------------------------------------------------------

class Owner:
    """One defun, indexed in evaluation (pre-)order: every list node's
    position and the position of its last descendant."""

    def __init__(self, d):
        self.d = d
        self.name = sym(d[1]) or "?"
        self.order = []
        self.pos = {}
        self.end = {}

        def rec(f):
            i = len(self.order)
            self.order.append(f)
            self.pos[id(f)] = i
            for x in f:
                if isinstance(x, list) and not (hd(x) == "defun" and
                                                x is not d):
                    rec(x)
            self.end[id(f)] = len(self.order) - 1

        rec(d)


class Window:
    """Where NODE sits in OW: its chain of ancestors, its innermost loop
    (the pass it belongs to), and the positions of the neighbouring
    BOUNDS in that pass -- a zero or a read belongs to this pick only
    between the pick before it and the pick after it."""

    def __init__(self, ow, node, bounds):
        self.chain = ancestors(ow.d, node) or [ow.d]
        self.loop = (loop_of(self.chain[1:]) if len(self.chain) > 1
                     else None)
        scope = self.loop if self.loop is not None else ow.d
        self.p = ow.pos[id(node)]
        self.cend = ow.end[id(node)]
        self.lo, self.hi = ow.pos[id(scope)], ow.end[id(scope)]
        others = sorted(ow.pos[id(c)] for c in bounds
                        if c is not node
                        and self.lo <= ow.pos[id(c)] <= self.hi)
        self.prev = max([q for q in others if q < self.p],
                        default=self.lo - 1)
        self.nxt = min([q for q in others if q > self.p],
                       default=self.hi + 1)


def exclusive(ow, z, r):
    """Z runs only on a branch R is not on: Z is in the body of a cond
    clause that R is not in, or in an if's branch that R is not in.
    Pre-order puts an earlier clause's body before a later clause's
    test, but the two never both run."""
    chain = (ancestors(ow.d, z) or []) + [z]
    for k in range(1, len(chain)):
        f = chain[k]
        if contains(f, r):
            continue
        parent = chain[k - 1]
        h = hd(parent)
        if h == "cond":
            return not (f and contains(f[0], z))
        if h == "if":
            return len(parent) > 1 and f is not parent[1]
        return False
    return False


def ancestors(root, target):
    """The chain of lists from ROOT down to TARGET (exclusive), or None."""
    path = []

    def rec(f):
        if f is target:
            return True
        if not isinstance(f, list):
            return False
        path.append(f)
        for x in f:
            if isinstance(x, list) and (hd(x) != "defun" or x is root) \
                    and rec(x):
                return True
        path.pop()
        return False

    return path if rec(root) else None


def loop_of(chain):
    """The innermost loop in CHAIN (outermost first), or None."""
    for k in range(len(chain) - 1, -1, -1):
        f = chain[k]
        h = hd(f)
        if h in LOOPS:
            return f
        if h == "lambda" and k > 0:
            up = chain[k - 1]
            if hd(up) in ("quote", "function") and k > 1:
                up = chain[k - 2]
            if hd(up) in MAPPERS:
                return f
    return None


def contains(f, target):
    if f is target:
        return True
    if isinstance(f, list):
        return any(contains(x, target) for x in f)
    return False


def nil_value(x, is_target):
    """What X evaluates to when the pick answered nil: True, False or
    None (cannot say)."""
    if is_target(x):
        return False
    if isinstance(x, Str):
        return True
    if isinstance(x, Sym):
        s = x.lower()
        if s == "t":
            return True
        if s == "nil":
            return False
        try:
            float(s)
            return True
        except ValueError:
            return None
    h = hd(x)
    if h in ("null", "not") and len(x) == 2:
        v = nil_value(x[1], is_target)
        return None if v is None else not v
    if h == "and":
        vs = [nil_value(a, is_target) for a in x[1:]]
        if False in vs:
            return False
        return True if all(v is True for v in vs) else None
    if h == "or":
        vs = [nil_value(a, is_target) for a in x[1:]]
        if True in vs:
            return True
        return False if all(v is False for v in vs) else None
    if h == "setq" and len(x) >= 3:
        return nil_value(x[-1], is_target)
    if h in ("car", "cadr", "cdr", "type") and len(x) == 2:
        v = nil_value(x[1], is_target)
        return False if v is False else None
    if h in ("=", "eq", "equal", "member", "wcmatch", "ssmemb") \
            and any(nil_value(a, is_target) is False for a in x[1:]):
        # nil against a literal, a quoted keyword list, a type name
        return False
    if h is None and isinstance(x, list) and x and hd(x[0]) == "lambda" \
            and len(x) == 2:
        # ((lambda (v) (if lzd:ask (lzd:ask "..." v) v)) (entsel ...)):
        # LAZDIAG's wrapper hands its argument straight back
        return nil_value(x[1], is_target)
    return None


def mentions(x, var):
    return var is not None and any(sym(a) == var for a in _atoms(x))


class PickSite:
    def __init__(self, path, owner, call, verdict, why):
        self.path, self.owner, self.call = path, owner, call
        self.verdict, self.why = verdict, why
        self.line = getattr(call, "line", 0)
        self.text = fingerprint(prompt_arg(call))
        self.defun = owner.name


def pick_sites(tier, path, forms):
    out = []
    for name, bodies in tier.per_file[path].items():
        for d in bodies:
            calls = [f for f in own_nodes(d) if hd(f) in PICKS
                     and interactive(f)]
            if not calls:
                continue
            ow = tier.owner(d)
            for c in calls:
                v, why = judge(tier, ow, c, calls)
                out.append(PickSite(path, ow, c, v, why))
    return out


def interactive(f):
    """An entsel or nentsel always asks.  (nentselp pt) with a point is a
    query the drafter never sees; it asks only with no argument or a
    prompt first."""
    if hd(f) != "nentselp" or len(f) == 1:
        return True
    return isinstance(f[1], Str) or hd(f[1]) == "strcat"


def judge(tier, ow, call, calls):
    w = Window(ow, call, calls)
    chain, loop = w.chain, w.loop

    def first(a, b, pred, seed):
        return tier.first_in(ow, a, b, pred, seed)

    r_at = first(w.cend, w.nxt, read_form, tier.read_seed)
    if r_at is not None:
        # a zero between the pick and the read wipes the miss's 7 --
        # unless it sits on a branch the read is not on
        z_at = w.cend
        while True:
            z_at = first(z_at, r_at, zero_form, tier.zero_seed)
            if z_at is None:
                break
            if not exclusive(ow, ow.order[z_at], ow.order[r_at]):
                return "STICKY", ("zeroes ERRNO again between the pick and "
                                  "the read at line %d, so the read "
                                  "answers 0 and never sees the miss's 7"
                                  % getattr(ow.order[r_at], "line", 0))
        if first(w.prev, w.p, zero_form, tier.zero_seed) is not None:
            return "ok-errno", ("zeroes ERRNO before the pick and reads it "
                                "after")
        if loop is None and w.prev == w.lo - 1 and \
                tier.zeroed_by_callers(ow.name):
            return "ok-errno", ("every call of %s zeroes ERRNO right before "
                                "it, and the pick is read after" % ow.name)
        where = ("once before the loop, not before each pick"
                 if loop is not None and first(-1, w.lo, zero_form,
                                               tier.zero_seed) is not None
                 else "never zeroed before it")
        return "STICKY", ("reads ERRNO after the pick, but it was %s: a "
                          "miss at an earlier pick answers 7 here" % where)
    branch, why = nil_branch(ow, call, chain)
    rec = branch is not None and any(
        hd(f) == ow.name for b in branch if isinstance(b, list)
        for f in own_nodes(b))
    if branch is not None and speaks(tier, ow, branch):
        if rec:
            return "ok-reasks", ("a nil only speaks and the defun asks "
                                 "again by calling itself")
        if hd(loop) == "while":
            moved = advances(loop, call, chain)
            if moved is None:
                return "ok-reasks", ("a nil only speaks and the while asks "
                                     "again")
            return "PICK", ("a nil only speaks, but the while moves on "
                            "anyway (the %s at line %d), so the miss is "
                            "taken as a skip" % moved)
        if loop is not None:
            return "PICK", ("a nil only speaks, but the %s it is in goes on "
                            "to the NEXT item, so the miss is taken as a "
                            "skip of this one for good"
                            % (hd(loop) if hd(loop) in LOOPS
                               else "mapper lambda"))
        return "PICK", ("a nil only speaks, and nothing asks the question "
                        "again (%s)" % why)
    return "PICK", why


def advances(loop, call, chain):
    """The setq that moves the while LOOP's own test on every pass,
    whatever the pick answered -- a top-level (setq v ...) in its body
    (through progn) of a variable its test reads, not the variable the
    pick is stored in and not fed by the pick -- as ('setq v', its
    line); None."""
    tvars = {sym(a) for a in _atoms(loop[1])} if len(loop) > 1 else set()
    stored = set()
    for f in chain:
        if hd(f) == "setq":
            for i in range(1, len(f) - 1, 2):
                if contains(f[i + 1], call):
                    stored.add(sym(f[i]))
    body = list(loop[2:])
    while body:
        f = body.pop(0)
        if hd(f) == "progn":
            body[:0] = list(f[1:])
            continue
        if hd(f) != "setq":
            continue
        for i in range(1, len(f) - 1, 2):
            v, val = sym(f[i]), f[i + 1]
            if v in tvars and v not in stored and not contains(val, call) \
                    and not any(mentions(val, s) for s in stored):
                return "setq %s" % v, getattr(f, "line", 0)
    return None


def nil_branch(ow, call, chain):
    """(forms run when the pick answers nil, what that is), or
    (None, why) when it cannot be read."""
    # the pick is itself a test: (while (setq sel (entsel ...)) ...)
    for k in range(len(chain) - 1, -1, -1):
        f = chain[k]
        h = hd(f)
        test = None
        if h in ("while", "if") and len(f) > 1 and contains(f[1], call):
            test = f[1]
        elif k > 0 and hd(chain[k - 1]) == "cond" and f is not chain[k - 1] \
                and isinstance(f, list) and f and contains(f[0], call):
            test = f[0]
        if test is None:
            continue
        v = nil_value(test, lambda x: x is call)
        if h == "while":
            if v is True:
                return list(f[2:]), "a nil keeps the loop going"
            return None, "a nil ends the loop it is the test of"
        if h == "if":
            if v is None:
                return None, "a nil goes where the if test cannot say"
            return (list(f[2:3]) if v else list(f[3:4]),
                    "a nil takes the %s of the if it is the test of"
                    % ("then" if v else "else"))
        # a cond clause: a nil that passes its test takes its body, one
        # that fails it goes on down the clauses in order
        line = getattr(f, "line", 0)
        if v is True:
            return list(f[1:]), "a nil takes the clause at line %d" % line
        if v is None:
            return None, ("a nil meets the cond clause at line %d, whose "
                          "test cannot be read" % line)
        held = {sym(g[i]) for g in own_nodes_all(test) if hd(g) == "setq"
                for i in range(1, len(g) - 1, 2) if contains(g[i + 1], call)}
        held.discard(None)
        cond = chain[k - 1]
        at = next(i for i, c in enumerate(cond) if c is f)
        for c in cond[at + 1:]:
            if not isinstance(c, list) or not c:
                continue
            cv = nil_value(c[0], lambda x: x is call or sym(x) in held)
            cl = getattr(c, "line", line)
            if cv is True:
                return list(c[1:]), ("a nil fails the clause at line %d and "
                                     "takes the one at line %d" % (line, cl))
            if cv is None:
                return None, ("a nil fails the clause at line %d and meets "
                              "one at line %d that cannot be read"
                              % (line, cl))
        return [], "a nil falls through the cond at line %d" % line
    # the pick is stored: follow the first test of that variable
    var = setq = None
    for f in reversed(chain):
        if hd(f) == "setq":
            for i in range(1, len(f) - 1, 2):
                if contains(f[i + 1], call):
                    var, setq = sym(f[i]), f
            break
    if var is None:
        return None, "the nil is used where it stands"
    start = ow.end[id(setq)]
    is_var = (lambda x: sym(x) == var)
    for i in range(start + 1, len(ow.order)):
        f = ow.order[i]
        h = hd(f)
        if h == "setq" and any(sym(f[j]) == var
                               for j in range(1, len(f), 2)) \
                and not contains(f, call):
            return None, "the nil is overwritten before it is tested"
        if h == "if" and len(f) > 2 and mentions(f[1], var):
            v = nil_value(f[1], is_var)
            if v is None:
                continue
            br = list(f[2:3]) if v else list(f[3:4])
            return br, ("a nil takes the %s of the test at line %d"
                        % ("then" if v else "else", f.line))
        if h == "cond" and any(isinstance(c, list) and c and
                               mentions(c[0], var) for c in f[1:]):
            for c in f[1:]:
                if not isinstance(c, list) or not c:
                    continue
                v = nil_value(c[0], is_var)
                if v is True:
                    return list(c[1:]), ("a nil takes the clause at line %d"
                                         % getattr(c, "line", f.line))
                if v is None and mentions(c[0], var):
                    return None, ("a nil meets a cond clause at line %d "
                                  "that cannot be read"
                                  % getattr(c, "line", f.line))
            return [], "a nil falls through the cond at line %d" % f.line
    return None, "a nil is kept as the value"


def speaks(tier, ow, branch):
    """BRANCH only prints (or recurses into its own defun to ask again):
    nothing it does outlives the message."""
    for b in branch:
        if not isinstance(b, list):
            return False
        for f in own_nodes(b):
            h = hd(f)
            if h is None:
                continue
            if h in SPEAK or h in tier.speakers or h == ow.name \
                    or h.startswith(LZD):
                continue
            return False
    return True


# ---------------------------------------------------------------------
#  SPACE
# ---------------------------------------------------------------------

class SpaceSite:
    def __init__(self, path, defun, lit, line, kind, match):
        self.path, self.defun, self.line = path, defun, line
        self.kind, self.match = kind, match
        self.text = flat(lit)
        self.verdict = "SPACE"
        self.why = {
            "prompt": "the prompt of a spacebar-ended input",
            "line-prompt": "a (getstring T ...) prompt, in a file that "
                           "also reads text at an (initget 128) prompt",
            "hint": "a hint",
            "line-hint": "a hint beside a (getstring T ...) prompt, in a "
                         "file that also reads text at an (initget 128) "
                         "prompt",
        }[kind]


def space_sites(tier, path, forms):
    typed = any(hd(f) == "initget" and len(f) > 1
                and initget_bits(f[1]) & 128
                for top in forms if isinstance(top, list)
                for f in own_nodes_all(top))
    out = []
    ctx_cache = {}

    def ctx(owner):
        """'line' when every input OWNER asks is a (getstring T ...)."""
        if owner is None:
            return None
        k = ctx_cache.get(id(owner))
        if k is None:
            kinds = {tier.call_kind(f) for f in own_nodes(owner)} - {None}
            k = ctx_cache[id(owner)] = (
                "line" if kinds == {"line"} else "other")
        return k

    def visit(f, chain, owner, label):
        if isinstance(f, Str):
            check(f, chain, owner, label)
            return
        if not isinstance(f, list):
            return
        h = hd(f)
        if h and h.startswith(LZD):
            return      # LAZDIAG's transcript copy of a prompt: not shown
        if h == "defun" and len(f) > 1:
            owner, label, chain = f, sym(f[1]) or "?", []
        chain.append(f)
        for x in f:
            visit(x, chain, owner, label)
        chain.pop()

    def check(s, chain, owner, label):
        m = FRACTION.search(unesc(s))
        u = UNIT.search(unesc(s))
        if not (m or u):
            return
        kind = None
        for k in range(len(chain) - 1, -1, -1):
            f = chain[k]
            below = chain[k + 1] if k + 1 < len(chain) else s
            ik = input_kind(f)
            if ik:
                # a base point is never a string: any literal inside an
                # input call is its prompt
                kind = ik
                break
            h = hd(f)
            if h in tier.pp:
                idx = next((i - 1 for i, a in enumerate(f)
                            if i and (a is below or a is s)), None)
                if idx in tier.pp[h]:
                    kind = tier.pp[h][idx]
                    break
            if h == "defun":
                break
        if kind == "space":
            what = "prompt"
        elif kind == "line":
            if not typed:
                return
            what = "line-prompt"
        elif ctx(owner) == "line":
            if not typed:
                return
            what = "line-hint"
        else:
            what = "hint"
        hit = m or (u if what == "prompt" else None)
        if hit:
            line = line_of(tier.texts.get(path, ""), s,
                           getattr(chain[-1], "line", 1) if chain else 1)
            out.append(SpaceSite(path, label, s, line, what, hit.group()))

    for top in forms:
        if not isinstance(top, list):
            continue
        label = "(top level)"
        if hd(top) == "setq" and len(top) > 1:
            label = sym(top[1]) or label
            if label in GENERATED:
                continue
        visit(top, [], None, label)
    return out


def line_of(text, lit, from_line):
    """The line the literal LIT starts on, searching TEXT from the line
    of the list it sits in (the reader keeps lines on lists only)."""
    at = 0
    for _ in range(from_line - 1):
        at = text.find("\n", at) + 1
        if at == 0:
            return from_line
    k = text.find('"' + lit + '"', at)
    return from_line if k < 0 else text.count("\n", 0, k) + 1


def own_nodes_all(form):
    stack = [form]
    while stack:
        f = stack.pop()
        yield f
        stack.extend(x for x in f if isinstance(x, list))


# ---------------------------------------------------------------------
#  the baseline, keyed by file STEM so one line covers every tier
# ---------------------------------------------------------------------

DATED = re.compile(r"_\d{6}_REV[\d-]+$", re.IGNORECASE)


def stems(path):
    """The lisp/ stems a file stands for: its own, less a release date;
    every member's for a release bundle."""
    s = DATED.sub("", pathlib.Path(path).stem).lower()
    for b in BUNDLES:
        if s == b["name"].lower():
            return {pathlib.Path(m).stem.lower() for m in b["members"]}
    return {s}


def load_baseline(path=BASELINE):
    """[(stem, defun, text, reason, the line as written)]"""
    out = []
    path = pathlib.Path(path)
    if not path.is_file():
        return out
    for ln in path.read_text(encoding="utf-8").splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("|")
        if len(parts) < 4:
            continue
        f, d, t, why = parts[0], parts[1], "|".join(parts[2:-1]), parts[-1]
        out.append((pathlib.Path(f).stem.lower(), d.lower(),
                    " ".join(t.split()), why, ln))
    return out


def rel(p):
    try:
        return p.relative_to(ROOT).as_posix()
    except ValueError:
        return str(p)


def survey(tier):
    rows = []
    for p in tier.paths:
        forms = tier.files[p]
        rows += pick_sites(tier, p, forms)
        rows += space_sites(tier, p, forms)
    return rows


def report(paths, base, show_all=False, out=print):
    """Read PATHS as one tier and print every finding outside BASE.
    Returns (rows, failing rows, baseline entries matched)."""
    tier = Tier(paths)
    rows = survey(tier)
    used = set()
    bad = []
    for r in rows:
        if r.verdict.startswith("ok"):
            if show_all:
                out("%-9s %s:%d  %s  %r" % (r.verdict, rel(r.path), r.line,
                                            r.defun, r.text))
            continue
        hit = None
        if r.verdict != "STICKY":
            st = stems(r.path)
            for k, (s, d, t, _, _) in enumerate(base):
                if s in st and d == r.defun.lower() and t == r.text:
                    hit = k
                    break
        if hit is not None:
            used.add(hit)
            if show_all:
                out("%-9s %s:%d  %s  %r  [baselined]"
                    % (r.verdict, rel(r.path), r.line, r.defun, r.text))
            continue
        bad.append(r)
        if r.verdict == "SPACE":
            out("%s:%d: SPACE: %s shows %r -- %s teaches a space, and at "
                "every input but (getstring T ...) the spacebar is Enter: "
                "it arrives as two answers, the second to the next "
                "question. Dash it (44-1/2, 4'-4-1/2\") or close the unit "
                "up (1524mm)\n    says: %s"
                % (rel(r.path), r.line, r.defun, r.match, r.why, r.text))
        elif r.verdict == "STICKY":
            out("%s:%d: STICKY: %s %s. Zero it right before the pick, "
                "inside the loop, and nowhere between the pick and the "
                "read: (vl-catch-all-apply 'setvar (list \"ERRNO\" 0))\n"
                "    asks: %s" % (rel(r.path), r.line, r.defun, r.why,
                                  r.text))
        else:
            out("%s:%d: PICK: %s -- a click on nothing answers nil as Enter "
                "does, and %s. Zero ERRNO before the pick and ask again on "
                "7, or say in tools/input_baseline.txt why a miss may "
                "decide it\n    asks: %s"
                % (rel(r.path), r.line, r.defun, r.why, r.text))
    return rows, bad, used


def tiers(which):
    t = {"lisp": lsp_files(LISP_DIR), "shared": lsp_files(PARTS_DIR),
         "releases": lsp_files(RELEASES_DIR)}
    names = ["lisp", "shared", "releases"] if which == "all" else [which]
    return [(n, t[n]) for n in names]


def run(tier_paths, base, show_all=False, out=print):
    """Every tier in TIER_PATHS [(label, paths)] against BASE: the
    failing site count, and the baseline lines nothing matched (only
    those whose file was read -- a --tier lisp run says nothing about
    the library's lines)."""
    used, read_stems, nbad = set(), set(), 0
    for name, paths in tier_paths:
        rows, bad, u = report(paths, base, show_all, out)
        used |= u
        for p in paths:
            read_stems |= stems(p)
        nbad += len(bad)
        npick = sum(1 for r in rows if isinstance(r, PickSite))
        out("check_input: %s -- %d pick(s), %d spaced literal(s); %s"
            % (name, npick, len(rows) - npick,
               ("%d failing" % len(bad)) if bad else
               "every pick tells a miss from Enter or is accounted for, "
               "and nothing teaches a space"))
    stale = [b[4] for k, b in enumerate(base)
             if k not in used and b[0] in read_stems]
    for ln in stale:
        out("check_input: stale baseline line -- its site is gone, "
            "reworded or fixed; delete it: " + ln)
    return nbad, stale


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Every input asks for what the drafter can give it.")
    ap.add_argument("--tier", default="all",
                    choices=("lisp", "shared", "releases", "all"),
                    help="the tier to read (default all three, as "
                         "check_osnap and check_handlers do)")
    ap.add_argument("--list", action="store_true",
                    help="print every pick site and spaced literal, the "
                         "ones that pass and the baselined ones included")
    ap.add_argument("--baseline", default=str(BASELINE))
    a = ap.parse_args(argv)
    nbad, stale = run(tiers(a.tier), load_baseline(a.baseline), a.list)
    return 1 if nbad or stale else 0


if __name__ == "__main__":
    sys.exit(main())
