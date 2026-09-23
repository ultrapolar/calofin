#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""An *error* handler must be able to
reach its own end -- the undo close, the pop and the lzd:report -- on
the path it exists for.

A handler is the only code that runs on Esc.  When it dies part-way the
drafter sees nothing wrong: no report is written, no log line says FAIL,
the undo group stays open, the error mode stays pushed for the rest of
the session.  SPA did that on every Esc until 03a642a.  This check reads
each handler in EVALUATION ORDER, helpers spliced in where they are
called, under the error MODE the command put in force, and names the
first form that cannot work in that mode.

The mode decides what a handler may touch:

  pushed    (*push-error-using-command*) -- AutoCAD unwinds the stack
            BEFORE *error* runs.  (command) is allowed; command-s is
            refused past any vl-catch-all-apply (the SPA death); and
            NOTHING the command bound is still bound: its locals read
            nil (or a stranger's global of the same name) and its
            local helpers -- (defun x:finish ...) with x:finish in the
            arglist -- are undefined, so calling one kills the handler
            at that form.
  default   (no push, or after *pop-error-mode*) -- the stack is live,
            so locals and local helpers are fine; command-s is fine;
            a (command ...) is refused ("Cannot invoke (command) from
            *error* without prior call to (*push-error-using-command*)"):
            unwrapped it kills the handler, wrapped it silently does
            nothing.

Rules (one finding per handler per rule, the FIRST offending form):

  H1  pushed handler CALLS a command-local function      -> dies there
  H2  pushed handler READS a command local (directly or through a
      global helper that reads it free)                  -> cleanup keyed
                                                            on nil skipped
  H3  pushed handler reaches command-s before its pop    -> dies there
  H4  default-mode handler reaches (command ...) / vl-cmdf -> dies there
      (unwrapped) or does nothing (wrapped)
  H5  a defun that installs its own *error* and calls lzd:begin is
      reachable from a command that did both -- an error inside it runs
      ONLY the inner handler: the command's undo close / sysvar restore
      is skipped.  Editorial (a handoff can restore first on purpose),
      so accepted pairs live in handler_baseline.txt with a reason,
      check_back's pattern.  LOG-MISFILED is the other half: LAZDIAG
      joins an inner begin to the run standing when CMDNAMES still names
      that run's command (lzd:nested-p), so a command that begins under
      its OWN name has its log and report kept whole; one that begins
      under another name cannot be told from a finished run, and the
      inner begin logs it 'ok' and drops its transcript.  A helper that
      joins explicitly -- (if (not lzd:*tool*) (lzd:begin ...)), as
      autobead-build does -- is the outer run's own.
  H6  a pushing command pops (through its finish helper) and then calls
      (exit)/(quit): the exit runs the handler AGAIN, now in default
      mode -- a pop with nothing pushed, the finish twice, "Cancelled."
      printed over the explanation, the run logged as a quit.

Each handler row says whether lzd:report is still reached.
Exit 1 on any finding outside the baseline.
"""

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from callib import LISP_DIR, PARTS_DIR, RELEASES_DIR, decomment, lsp_files  # noqa

SKIP_DIRS = ("standards_checker",)


# ---------------------------------------------------------------------
#  reader: lists that know their line, strings kept, quote kept
# ---------------------------------------------------------------------

class L(list):
    line = 0


class Str(str):
    pass


def read_forms(text):
    top = L()
    stack = []
    cur = top
    quote_pending = []          # per depth: pending quote wrappers
    i, n, line = 0, len(text), 1
    qstack = [[]]

    def emit(x):
        nonlocal cur
        # wrap in quote if one is pending at this depth
        while qstack[-1] and qstack[-1][-1] == len(cur):
            qstack[-1].pop()
            q = L([Sym("quote"), x])
            q.line = getattr(x, "line", line)
            x = q
        cur.append(x)

    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1
            i += 1
        elif ch == '"':
            j, buf = i + 1, []
            while j < n:
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                if text[j] == '"':
                    break
                if text[j] == "\n":
                    line += 1
                buf.append(text[j])
                j += 1
            emit(Str("".join(buf)))
            i = j + 1
        elif ch == "'":
            qstack[-1].append(len(cur))
            i += 1
        elif ch == "(":
            new = L()
            new.line = line
            stack.append(cur)
            qstack.append([])
            cur = new
            i += 1
        elif ch == ")":
            if stack:
                done = cur
                cur = stack.pop()
                qstack.pop()
                emit(done)
            i += 1
        elif ch in " \t\r":
            i += 1
        else:
            j = i
            while j < n and text[j] not in " \t\r\n()'\"":
                j += 1
            tok = text[i:j]
            if tok == ".":
                pass
            sy = Sym(tok)
            sy.line = line
            emit(sy)
            i = j
    return top


class Sym(str):
    """A symbol, lower-cased on comparison."""

    def low(self):
        return self.lower()


def is_sym(x):
    return isinstance(x, Sym)


def head(f):
    return f[0].lower() if isinstance(f, list) and f and is_sym(f[0]) else None


def walk(f):
    yield f
    if isinstance(f, list):
        for x in f:
            if isinstance(x, list):
                yield from walk(x)


def arglist(form):
    """(params, locals) of a defun/lambda, lower-cased."""
    al = form[2] if head(form) == "defun" else form[1]
    if not isinstance(al, list):
        return [], []
    toks = [t.lower() for t in al if is_sym(t)]
    if "/" in toks:
        k = toks.index("/")
        return toks[:k], toks[k + 1:]
    return toks, []


def body_of(form):
    return form[3:] if head(form) == "defun" else form[2:]


CONST = {"t", "nil", "pi", "/", "."}
SPECIAL = {"quote", "function", "setq", "if", "progn", "cond", "and", "or",
           "while", "repeat", "foreach", "defun", "lambda", "defun-q"}
APPLIERS = {"apply", "mapcar", "vl-catch-all-apply", "vl-some", "vl-every",
            "vl-member-if", "vl-member-if-not", "vl-remove-if",
            "vl-remove-if-not", "vl-sort", "vl-sort-i", "function"}


def is_const(s):
    s = s.lower()
    if s in CONST:
        return True
    try:
        float(s)
        return True
    except ValueError:
        return False


# ---------------------------------------------------------------------
#  the tier: every defun, and which ones are LOCAL (die with the stack)
# ---------------------------------------------------------------------

class Tier:
    def __init__(self, paths):
        self.paths = [p for p in paths
                      if not any(d in p.parts for d in SKIP_DIRS)]
        self.glob = {}       # name -> [(form, path)] defined globally
        self.local_defs = {}  # name -> [(form, path, owner)] defined local
        self.forms = {}
        for path in self.paths:
            forms = read_forms(decomment(path.read_text(encoding="utf-8",
                                                        errors="replace")))
            self.forms[path] = forms
            for f in forms:
                self._index(f, path, [])

    def _index(self, f, path, enclosing):
        """enclosing: list of (defun form, declared set)"""
        if not isinstance(f, list):
            return
        h = head(f)
        if h == "defun" and len(f) >= 3 and is_sym(f[1]):
            name = f[1].lower()
            if any(name in decl for _, decl in enclosing):
                owner = [d for d, decl in enclosing if name in decl][-1]
                self.local_defs.setdefault(name, []).append((f, path, owner))
            else:
                self.glob.setdefault(name, []).append((f, path))
            p, l = arglist(f)
            enclosing = enclosing + [(f, set(p) | set(l))]
            for x in f[3:]:
                self._index(x, path, enclosing)
            return
        if h == "lambda":
            p, l = arglist(f)
            enclosing = enclosing + [(f, set(p) | set(l))]
        for x in f:
            self._index(x, path, enclosing)

    def owner_defuns(self):
        """(path, defun form, enclosing chain) for every defun anywhere."""
        out = []

        def rec(f, path, chain):
            if not isinstance(f, list):
                return
            if head(f) in ("defun", "lambda"):
                if head(f) == "defun":
                    out.append((path, f, chain))
                chain = chain + [f]
            for x in f:
                rec(x, path, chain)

        for path, forms in self.forms.items():
            for f in forms:
                rec(f, path, [])
        return out


# ---------------------------------------------------------------------
#  evaluation-order trace of a handler, helpers spliced in
# ---------------------------------------------------------------------

def handlers_in(defun):
    """(handler form, kind) for each *error* installed directly in DEFUN's
    body -- not inside a nested defun other than *error* itself."""
    out = []

    def rec(f):
        if not isinstance(f, list):
            return
        h = head(f)
        if h == "defun" and len(f) >= 2 and is_sym(f[1]):
            if f[1].lower() == "*error*":
                out.append(f)
            return                      # a nested helper's handlers are its own
        if h == "setq":
            for i in range(1, len(f) - 1, 2):
                if is_sym(f[i]) and f[i].lower() == "*error*":
                    v = f[i + 1]
                    if head(v) == "lambda":
                        out.append(v)
                    elif head(v) == "function" and head(v[1]) == "lambda":
                        out.append(v[1])
        for x in f:
            rec(x)

    for x in body_of(defun):
        rec(x)
    return out


def calls_push(defun):
    for f in walk(list(body_of(defun))):
        if head(f) == "*push-error-using-command*":
            # skip the one inside a nested non-handler defun
            return True
    return False


def direct_calls(form):
    return {head(f) for f in walk(form) if head(f)}


class Tracer:
    """Walk a handler in evaluation order and emit events."""

    def __init__(self, tier, dead_names, pushed, own_locals=None):
        self.tier = tier
        self.own = own_locals or {}     # the command's local helpers
        self.dead = dead_names          # command locals (vars + local fns)
        self.pushed = pushed            # the MODE: changes at the pop
        self.unwound = pushed           # the STACK: gone for the whole handler
        self.written = set()            # dead names the handler set itself
        self.events = []                # (kind, detail, via, line)
        self.stopped = False            # a certain death was reached
        self.report_reached = False
        self.seen_helpers = set()

    def ev(self, kind, detail, via, line):
        self.events.append((kind, detail, list(via), line))

    def run(self, handler):
        p, l = arglist(handler)
        bound = set(p) | set(l)
        for st in body_of(handler):
            self.expr(st, bound, [], False)
            if self.stopped:
                break

    def fn_ref(self, name, bound, via, wrapped, line, args=()):
        """a function is CALLED by name"""
        if self.stopped:
            return
        n = name.lower()
        if n == "lzd:report":
            self.report_reached = True
            return
        if n == "*pop-error-mode*":
            self.pushed = False
            return
        if n in ("command-s",):
            if self.pushed:
                self.ev("H3", "command-s while the error mode is pushed",
                        via, line)
                self.stopped = True
            return
        if n in ("command", "vl-cmdf"):
            if not self.pushed:
                if wrapped:
                    self.ev("H4w", "(%s ...) in a default-mode handler, "
                            "caught: it silently does nothing" % n, via, line)
                else:
                    self.ev("H4", "(%s ...) in a default-mode handler: "
                            "refused, the handler dies here" % n, via, line)
                    self.stopped = True
            return
        if self.unwound and n in self.dead and n not in bound:
            if n in self.tier.glob:
                # also defined globally somewhere: not certain death
                self.ev("H1?", "calls %s, a command-local function that "
                        "also has a global definition" % n, via, line)
                return
            self.ev("H1", "calls %s, a local function of the command: "
                    "undefined once the stack is unwound" % n, via, line)
            if not wrapped:
                self.stopped = True
            return
        # splice a helper: the command's own local one while the stack
        # is live, else the global definition
        if not self.unwound and n in self.own and n not in bound:
            forms = [(self.own[n], None)]
        else:
            forms = self.tier.glob.get(n, [])[:1]
        if forms and n not in self.seen_helpers and len(via) < 8:
            self.seen_helpers.add(n)
            for form, path in forms:
                p, l = arglist(form)
                hb = set(p) | set(l)
                for st in body_of(form):
                    self.expr(st, hb, via + [n], wrapped)
                    if self.stopped:
                        return

    def var_ref(self, s, bound, via, line):
        if self.stopped or not self.unwound:
            return
        n = s.lower()
        if n in bound or is_const(n) or n.startswith("*error*") \
                or n in self.written:
            return
        if n in self.dead:
            self.ev("H2", "reads %s, a local of the command: it reads the "
                    "GLOBAL %s once the stack is unwound" % (n, n), via, line)

    def expr(self, f, bound, via, wrapped):
        if self.stopped:
            return
        if is_sym(f):
            self.var_ref(f, bound, via, getattr(f, "line", 0))
            return
        if not isinstance(f, list) or not f:
            return
        line = getattr(f, "line", 0)
        h = head(f)
        if h is None:
            # ((lambda ...) args) or data
            for x in f:
                self.expr(x, bound, via, wrapped)
            return
        if h == "quote":
            return
        if h in ("defun", "defun-q"):
            return                       # defining, not running
        if h == "lambda":
            p, l = arglist(f)
            nb = bound | set(p) | set(l)
            for x in body_of(f):
                self.expr(x, nb, via, wrapped)
            return
        if h == "setq":
            for i in range(1, len(f), 2):
                if i + 1 < len(f):
                    self.expr(f[i + 1], bound, via, wrapped)
                if is_sym(f[i]) and f[i].lower() not in bound:
                    self.written.add(f[i].lower())
            return
        if h == "foreach":
            if len(f) >= 3:
                self.expr(f[2], bound, via, wrapped)
                nb = bound | ({f[1].lower()} if is_sym(f[1]) else set())
                for x in f[3:]:
                    self.expr(x, nb, via, wrapped)
            return
        if h == "function":
            if len(f) > 1:
                if is_sym(f[1]):
                    self.fn_ref(f[1], bound, via, wrapped, line)
                else:
                    self.expr(f[1], bound, via, wrapped)
            return
        if h in SPECIAL:
            for x in f[1:]:
                self.expr(x, bound, via, wrapped)
            return
        # an ordinary call: args first (left to right), then the callee
        w = wrapped or h == "vl-catch-all-apply"
        if h in APPLIERS and len(f) > 1:
            fa = f[1]
            qn = None
            if head(fa) == "quote" and is_sym(fa[1]):
                qn = fa[1]
            elif head(fa) == "function" and is_sym(fa[1]):
                qn = fa[1]
            for x in f[2:]:
                self.expr(x, bound, via, w)
            if qn is not None:
                self.fn_ref(qn, bound, via, w, line)
            else:
                self.expr(fa, bound, via, w)
            return
        for x in f[1:]:
            self.expr(x, bound, via, wrapped)
        # the callee named by a symbol that is bound locally (a funarg)
        if h in bound:
            return
        self.fn_ref(f[0], bound, via, wrapped, line)


def pushed_by_caller(tier):
    """name -> the pushing defun whose run reaches it (before any pop is
    not modelled: reaching is enough to say the mode CAN be pushed)"""
    out = {}
    for path, d, chain in tier.owner_defuns():
        if not (is_sym(d[1]) and calls_push(d)):
            continue
        src = d[1].lower()
        todo = list(direct_calls(list(body_of(d))))
        seen = set()
        while todo:
            c = todo.pop()
            if c in seen or c not in tier.glob:
                continue
            seen.add(c)
            out.setdefault(c, src)
            for f2, _ in tier.glob[c][:1]:
                todo += list(direct_calls(list(body_of(f2))))
    return out


def analyse(tier):
    rows = []
    via_caller = pushed_by_caller(tier)
    for path, d, chain in tier.owner_defuns():
        hs = handlers_in(d)
        if not hs:
            continue
        name = d[1].lower() if is_sym(d[1]) else "?"
        if name == "*error*":
            continue
        pushed = calls_push(d)
        caller = None
        if not pushed and name in via_caller:
            pushed, caller = True, via_caller[name]
        dead = set()
        for enc in chain + [d]:
            p, l = arglist(enc)
            dead |= set(p) | set(l)
        dead.discard("*error*")
        own = {}
        for f in walk(list(body_of(d))):
            if head(f) == "defun" and is_sym(f[1]) and f[1].lower() in dead:
                own[f[1].lower()] = f
        for h in hs:
            t = Tracer(tier, dead, pushed, own)
            t.run(h)
            has_report = any(head(f) == "lzd:report" for f in walk(h))
            rows.append({"path": path, "defun": name, "line": d.line,
                         "hline": getattr(h, "line", 0), "pushed": pushed,
                         "events": t.events, "reported": t.report_reached,
                         "has_report": has_report, "stopped": t.stopped,
                         "caller": caller})
    return rows


def begin_name(form):
    """the tool string a defun's own lzd:begin names, or None"""
    for f in walk(list(body_of(form))):
        if head(f) == "lzd:begin" and len(f) > 1 and isinstance(f[1], Str):
            return f[1].upper()
    return None


def joins(form):
    """does this defun begin only when no run is standing -- the
    (if (and lzd:begin (not lzd:*tool*)) (lzd:begin ...)) of a helper
    that is the tail of a caller's run, and reports under it?"""
    for f in walk(list(body_of(form))):
        if head(f) == "not" and len(f) == 2 and is_sym(f[1]) \
                and f[1].lower() == "lzd:*tool*":
            return True
    return False


def outer_cleanup(form):
    """does this defun's handler do anything beyond print and report?"""
    for h in handlers_in(form):
        for st in body_of(h):
            for f in walk(st):
                hd = head(f)
                if hd in ("setvar", "command", "command-s", "vla-endundomark",
                          "entdel", "*pop-error-mode*") or (
                        hd and hd not in ("if", "and", "or", "not", "princ",
                                          "strcat", "wcmatch", "strcase",
                                          "lzd:report", "prompt", "cond",
                                          "progn", "null", "setq")
                        and not hd.startswith("*")):
                    return True
    return False


def nested_begin(tier):
    """H5: a defun that installs its own *error* AND calls lzd:begin,
    reached (through global calls) from a command that already did both.
    An error inside the helper runs ONLY the helper's handler: the
    command's cleanup is skipped, and when the two begin different tool
    names the command's run is logged 'ok' and its transcript dropped."""
    starters = {}
    for name, defs in tier.glob.items():
        for form, path in defs:
            if handlers_in(form) and begin_name(form):
                starters[name] = (form, path)
    out = []
    for name, defs in tier.glob.items():
        if not name.startswith("c:"):
            continue
        for form, path in defs:
            if not (handlers_in(form) and begin_name(form)):
                continue
            outer = begin_name(form)
            parent = {}
            todo = [(c, name) for c in direct_calls(form)]
            seen = {name}
            while todo:
                c, frm = todo.pop(0)
                if c in seen or c not in tier.glob:
                    continue
                seen.add(c)
                parent[c] = frm
                if c in starters:
                    inner = (outer if joins(starters[c][0])
                             else begin_name(starters[c][0]))
                    chain, x = [c], c
                    while parent.get(x) and parent[x] != name:
                        x = parent[x]
                        chain.append(x)
                    out.append((path, name, " > ".join(reversed(chain)),
                                starters[c][1], outer, inner,
                                outer_cleanup(form)))
                    continue
                for f2, _ in tier.glob[c][:1]:
                    todo += [(x, c) for x in direct_calls(f2)
                             if x not in seen]
    return out



def reaches_pop(form, tier, own, depth=0, seen=None):
    """does evaluating FORM reach (*pop-error-mode*)?"""
    if seen is None:
        seen = set()
    for f in walk(form):
        h = head(f)
        if h == "*pop-error-mode*":
            return True
        if h and h not in seen and depth < 6:
            defs = [own[h]] if h in own else [x for x, _ in tier.glob.get(h, [])[:1]]
            for d in defs:
                seen.add(h)
                if reaches_pop(list(body_of(d)), tier, own, depth + 1, seen):
                    return True
    return False


def double_exit(tier):
    """H6: in a pushing defun, a statement that pops the mode (directly or
    through its finish helper) followed in the same body by (exit)/(quit):
    the exit runs the handler AGAIN, now in default mode -- it pops with
    nothing pushed, and any (command) left in it is refused."""
    out = []
    for path, d, chain in tier.owner_defuns():
        if not (is_sym(d[1]) and calls_push(d)) or d[1].lower() == "*error*":
            continue
        p, l = arglist(d)
        dead = set(p) | set(l)
        own = {}
        for f in walk(list(body_of(d))):
            if head(f) == "defun" and is_sym(f[1]) and f[1].lower() in dead:
                own[f[1].lower()] = f
        hs = {id(h) for h in handlers_in(d)}

        def bodies(f):
            if not isinstance(f, list) or id(f) in hs:
                return
            h = head(f)
            if h == "defun" and f is not d:
                return
            if h in ("progn", "while", "repeat"):
                yield f[1:]
            if h == "cond":
                for cl in f[1:]:
                    if isinstance(cl, list):
                        yield cl
            for x in f:
                if isinstance(x, list):
                    yield from bodies(x)

        stmts_lists = [list(body_of(d))] + list(
            b for x in body_of(d) for b in bodies(x))
        for stl in stmts_lists:
            popped = None
            for st in stl:
                if not isinstance(st, list):
                    continue
                if head(st) in ("exit", "quit") and popped is not None:
                    out.append((path, d[1].upper(), popped, st.line))
                    break
                if head(st) not in ("defun",) and reaches_pop(st, tier, own):
                    popped = st.line
    return out


def load_baseline(bfile=None):
    """(OUTER-COMMAND, inner-defun) pairs a person has read and accepted
    for rule H5, with the reason on the line."""
    base = set()
    bfile = bfile or pathlib.Path(__file__).with_name("handler_baseline.txt")
    if bfile.is_file():
        for ln in bfile.read_text().splitlines():
            if ln.strip() and not ln.startswith("#"):
                o, i, _ = ln.split("|", 2)
                base.add((o.upper(), i.lower()))
    return base


def report(paths, base, show_all=False, out=print):
    """Read PATHS as one tier and print every finding; the count of
    finding lines (H5 pairs in BASE and same-tool nests excepted)."""
    tier = Tier(paths)
    rows = analyse(tier)
    nfind = 0

    def rel(p):
        try:
            return p.relative_to(ROOT)
        except ValueError:
            return p
    for r in rows:
        if not r["events"] and not show_all:
            continue
        out("%s:%d  %s  handler@%d  pushed=%s  report=%s" % (
            rel(r["path"]), r["line"], r["defun"].upper(), r["hline"],
            ("by " + r["caller"]) if r.get("caller") else
            ("Y" if r["pushed"] else "n"),
            ("reached" if r["reported"] else
             ("NEVER" if r["has_report"] else "none"))))
        seen = set()
        for kind, detail, via, line in r["events"]:
            key = (kind, detail)
            if key in seen:
                continue
            seen.add(key)
            nfind += 1
            out("    %-4s line %-5d %s%s" % (
                kind, line, detail,
                ("   [via " + " > ".join(via) + "]") if via else ""))
    for path, cmd, chain, hpath, outer, inner, cleanup in nested_begin(tier):
        leaf = chain.split(" > ")[-1]
        # LAZDIAG joins the inner run to this one when CMDNAMES -- the
        # command's own name -- is the name this command began under
        misfiled = outer != inner and outer != cmd.upper()[2:]
        if not cleanup and not misfiled:
            tag = "H5-ok"   # same run, nothing shadowed
        elif (cmd.upper(), leaf) in base or \
                (cmd.upper(), chain.split(" > ")[0]) in base:
            tag = "H5-baselined"
        else:
            tag = "H5"
        nfind += tag == "H5"
        if tag == "H5" or show_all:
            out("%s  %s  %s [begins %s] reaches %s [begins %s, own *error*]%s%s"
                % (rel(path), tag, cmd.upper(), outer, chain, inner,
                   "  outer-handler-cleanup-SHADOWED" if cleanup else "",
                   "  LOG-MISFILED" if misfiled else ""))
    for path, cmd, pl, xl in double_exit(tier):
        nfind += 1
        out("%s  H6  %s pops at line %d, then (exit) at line %d runs the "
            "handler a second time in default mode"
            % (rel(path), cmd, pl, xl))
    return len(rows), nfind


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", default=None,
                    choices=("lisp", "shared", "releases"),
                    help="one tier; the default reads all three, the way "
                         "check_osnap does -- a dated twin is what a shop "
                         "pins to")
    ap.add_argument("--all", action="store_true",
                    help="list every handler, not only findings")
    a = ap.parse_args(argv)
    tiers = {"lisp": lsp_files(LISP_DIR),
             "shared": lsp_files(PARTS_DIR),
             "releases": lsp_files(RELEASES_DIR)}
    want = [a.tier] if a.tier else ["lisp", "shared", "releases"]
    base = load_baseline()
    total = 0
    for t in want:
        paths = [p for p in tiers[t]
                 if not any(s in p.parts for s in SKIP_DIRS)]
        nrows, nfind = report(paths, base, a.all)
        total += nfind
        print("check_handlers: %s -- %d handler(s) read, %s"
              % (t, nrows, ("%d finding line(s)" % nfind) if nfind else
                 "every one reaches its end in the error mode it runs in"))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
