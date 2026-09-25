#!/usr/bin/env python3
"""Every command reports its failures.  Check it, and repair it.

A tool's *error* handler used to end by printing one line and stopping:

    (princ (strcat "\\nABFIND error: " msg))

which tells a drafter that something broke and tells whoever has to fix
it almost nothing.  LAZDIAG turns that same failure into a DXF in the
user's Downloads folder -- the geometry, the prompts, the sysvars, the
error -- but only for the commands that actually call it.  So the wiring
has to be checked rather than remembered, or the next tool added to the
tree is the one whose failures stay silent.

Two calls per command, and this script owns both:

    (if lzd:begin  (lzd:begin  "TOOL" *tool-version*))   at the top
    (if lzd:report (lzd:report "TOOL" *tool-version* msg))  in the handler

The (if ...) guard is the whole compatibility story: an unbound symbol
evaluates to nil in AutoLISP, so a standalone file APPLOADed on its own
-- with no LAZDIAG beside it -- runs both lines as no-ops and keeps the
behaviour it had before.  Load LAZDIAG.lsp too, or the whole LAZPASS
build, and the same file starts writing reports.  Nothing is conditional
on which tier it is.

    python3 tools/check_lazdiag.py         # report unwired commands
    python3 tools/check_lazdiag.py --fix   # wire them

And a third thing, per FILE rather than per command: a table of SELF
TESTS, which LAZDIAG runs on the drafter's machine after a failure and
writes into the report -- the tool's own helpers on inputs whose
answers are known, so the report says whether the arithmetic was sound
where it ran (LAZDIAG.lsp, "the tool's own self tests").  --fix writes
the table's skeleton and its registration under every command the file
reports as; the entries themselves are editorial and the check names
the file until at least MIN_TESTS of them are written.

Exit 0 when every command in lisp/ is wired and every file carries its
table, 1 otherwise.  `make check` runs it, so a new tool cannot ship
unwired, or without the tests a report of its failure would run.
"""

import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent

#: standards_checker is the deprecated acady matcher: not carried into
#: the shared build, not on the panel, and not wired here either.
SKIP_DIRS = {"standards_checker"}


# ----------------------------------------------------------------- reading

def code_mask(src):
    """A bytearray parallel to SRC: 1 where the character is code, 0
    inside a string literal or a ; comment.  Every paren walk below runs
    over this, so a ")" inside "a string)" or after a ; cannot close a
    form that is still open."""
    mask = bytearray(len(src))
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == ";":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == '"':
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        mask[i] = 1
        i += 1
    return mask


def form_end(src, mask, start):
    """Index just past the ")" closing the form that opens at START."""
    depth = 0
    i = start
    while i < len(src):
        if mask[i]:
            if src[i] == "(":
                depth += 1
            elif src[i] == ")":
                depth -= 1
                if depth == 0:
                    return i + 1
        i += 1
    return -1


def children(src, mask, lo, hi):
    """(start, end) of every form directly inside the span LO..HI --
    the handler's own statements, not the ones nested in them.  Used to
    find the trailing (princ) a report has to go in front of."""
    out = []
    i = lo
    while i < hi:
        if mask[i] and src[i] == "(":
            j = form_end(src, mask, i)
            if j < 0 or j > hi:
                break
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


VERSION_RE = re.compile(
    r"^\(setq\s+(\*[\w-]+-version\*|[a-zA-Z][\w-]*:\*version\*)\s", re.M)


def version_global(src):
    """The file's own version banner, as the symbol to pass to LAZDIAG.
    Two spellings in the tree -- *tool-version* and prefix:*version* --
    and a handful of files carry neither, which is a legitimate state
    (release_lisp.py skips them) and reports as "noversion"."""
    m = VERSION_RE.search(src)
    return m.group(1) if m else "nil"


# ----------------------------------------------------------------- finding

DEFUN_ANY = re.compile(r"\(defun\s+([^\s()]+)\s*\(", re.I)

#: A handler comes in two spellings and BOTH have to be found.  The
#: defun form is what STANDARDS section 5 shows and what most of the
#: tree uses; the lambda form is what abhd, CABHD and lhd use, because
#: they save the previous handler and put it back rather than relying on
#: the local declaration to drop theirs.  Scanning only for the defun
#: form missed three of the largest tools in the tree -- ABHD,
#: ABHDCOVER, ADAB, TUTORIALABHD, CABHD and LHD reported nothing at all
#: while every other command reported everything.
DEFUN_ERR = re.compile(r"\(defun\s+\*error\*\s*\(\s*([\w-]+)")
LAMBDA_ERR = re.compile(r"\*error\*\s*(?:;[^\n]*\n\s*)*\(lambda\s*\(\s*([\w-]+)")

#: the name a handler already prints, as in (princ (strcat "\nPOOL error: "
#: msg)).  Handlers that build the name from a local instead -- ABFIND's
#: (if cmd cmd "ABFIND") -- are read by NAMED_FALLBACK below.
NAMED_LITERAL = re.compile(r'"\\n([A-Za-z][A-Za-z0-9_-]*) error: ?"')
NAMED_FALLBACK = re.compile(r'"([A-Z][A-Z0-9_-]{2,})"')


def indent_of(src, pos):
    bol = src.rfind("\n", 0, pos) + 1
    return src[bol:pos] if src[bol:pos].strip() == "" else "    "


def tool_name(body, owner, path):
    """What to call this tool in its report.

    A LITERAL, and the same literal for both calls, which is what lets
    lzd:mine-p tell a fresh context from a stale one: the two calls run
    at different moments, so an expression that reads a local -- the
    (if cmd cmd "ABFIND") ABFIND's handler prints -- would evaluate to
    nil at the top of the run and to "ABMOVE" in the handler, and the
    transcript would be disowned as somebody else's.

    The enclosing command is the best source, because it is exactly what
    was typed.  Then the name the handler prints, which is what the
    drafter has been reading on the command line -- but only second,
    because a file can print one label for several commands: AutoDim.lsp
    says "AutoDim error:" from both AUTODIM and AUTODIMSIDEPOV, and the
    report should still be able to tell them apart."""
    if owner.lower().startswith("c:"):
        return owner[2:].upper()
    m = NAMED_LITERAL.search(body)
    if m:
        # AutoDim prints its name in mixed case; the report wants the
        # command as a drafter types it
        return m.group(1).upper()
    i = body.find(" error: ")
    if i > 0:
        # A handler that builds the name from a local: take the literal
        # default it falls back to -- ABFIND's (if cmd cmd "ABFIND").
        # Scoped to the strcat that is building the message, because the
        # rest of a handler is full of plausible-looking literals:
        # searching all of it named ABFIND after the (getvar "DIMSTYLE")
        # that restores its dimension style, and covercheck's after the
        # (setvar "CMDECHO" ...) that restores its echo.
        found = NAMED_FALLBACK.findall(
            body[max(0, enclosing_call(body, i)):i])
        if found:
            return found[-1]
    return pathlib.Path(path).stem.upper()


def enclosing_call(body, i, mask=None):
    """Index of the "(" opening the innermost form still open at I --
    the (strcat ...) a message is being built in, or the (setq ...) a
    lambda handler is being assigned by."""
    if mask is None:
        mask = code_mask(body)
    depth, j = 0, i
    while j > 0:
        j -= 1
        if not mask[j]:
            continue
        if body[j] == ")":
            depth += 1
        elif body[j] == "(":
            if depth == 0:
                return j
            depth -= 1
    # -1, not 0: index 0 is a real answer -- a defun can open at the very
    # first byte of a file -- and a caller that read 0 as "nothing found"
    # would skip exactly that form.  It did: misplaced() was silently
    # passing over a top-level defun that started at column 0.
    return -1


class _Hit:
    """The two handler spellings, reduced to what the walk below needs:
    where the handler's form opens, and what it calls its message."""

    def __init__(self, start, param, lam=False):
        self._start, self._param, self.lam = start, param, lam

    def start(self):
        return self._start

    def group(self, n):
        return self._param


def handlers(src, mask, path):
    """Every *error* handler in the file, with the defun that owns it.

    Keyed off the HANDLER and not off (defun c:...): ABFIND's sits in
    abf:run, a helper two commands share, and a scan that only looked
    inside c: defuns found neither of them."""
    spans = []
    for m in DEFUN_ANY.finditer(src):
        if not mask[m.start()]:
            continue
        hi = form_end(src, mask, m.start())
        if hi > 0:
            spans.append((m.start(), hi, m.group(1)))
    out = []
    found = []
    for em in DEFUN_ERR.finditer(src):
        found.append((em.start(), em.group(1), False))
    for em in DEFUN_ERR.finditer(src):
        pass
    for em in LAMBDA_ERR.finditer(src):
        # the form to walk is the (lambda ...), which starts after the
        # *error* the assignment names
        found.append((src.index("(lambda", em.start()), em.group(1), True))
    for start, param, lam in sorted(found):
        em = _Hit(start, param, lam)
        if not mask[em.start()]:
            continue
        err_lo = em.start()
        err_hi = form_end(src, mask, err_lo)
        if err_hi < 0:
            continue
        # the smallest defun that contains the handler and is not it
        owners = [s for s in spans
                  if s[0] < err_lo and s[1] >= err_hi]
        if not owners:
            continue
        lo, hi, owner = min(owners, key=lambda s: s[1] - s[0])
        body = src[err_lo:err_hi]
        # Where lzd:begin goes.  Straight after a defun handler -- but a
        # LAMBDA handler is a value inside a (setq ...), so landing there
        # would make the begin call another setq argument and leave the
        # form with an odd number of them: (setq a nil *error* (lambda
        # ...) (if lzd:begin ...)) assigns the guard to nothing and dies
        # at load.  Out to the end of that setq instead, which is still
        # the top of the run.
        begin_at = err_hi
        if em.lam:
            outer = enclosing_call(src, err_lo, mask)
            end = form_end(src, mask, outer) if outer >= 0 else -1
            if end > 0:
                begin_at = end
        out.append({
            "name": tool_name(body, owner, path),
            "owner": owner,
            "param": em.group(1),            # msg / m
            "cmd_lo": lo, "cmd_hi": hi,
            "err_lo": err_lo, "err_hi": err_hi,
            "begin_at": begin_at,
            "body": body,
        })
    return out


# ------------------------------------------------------- the prompt trail
# The transcript is the half of a report that says WHICH question the run
# died on, and it fills itself: every ask helper records the prompt it
# just put up and the answer that came back.  One insertion per helper,
# straight after the (setq v (getkword ...)) -- not a wrapper round the
# return value, because what the report wants is what the user actually
# typed, before the helper normalises "Undo" to CAL-BACK or an empty
# Enter to the default.
#
# Both tiers, not just the library: a standalone file carries its own
# copy of these helpers, and instrumenting only cal: would make the
# grouped build keep a transcript that the standalone one silently did
# not -- exactly the tier drift shared/ exists to prevent.

ASK_DEFUN = re.compile(r"\(defun\s+([\w-]*[:-]ask[\w-]*)\s*\(([^)]*)\)", re.I)
ASK_GET = re.compile(
    r"\(setq\s+([\w:-]+)\s+\(\s*(getkword|getdist|getstring|getint"
    r"|getreal|getpoint|getangle)\b")

PROMPT_PARAMS = ("msg", "prompt", "subject", "question")


def ask_helpers(src, mask):
    """Every ask helper that puts a prompt up itself, and where its
    answer lands.  The ones that only delegate -- askyn and asktreat
    both go through askkw -- have no get call of their own and are
    skipped here: their askkw records for them, and recording twice
    would put every treatment question in the transcript twice."""
    out = []
    for m in ASK_DEFUN.finditer(src):
        if not mask[m.start()]:
            continue
        hi = form_end(src, mask, m.start())
        if hi < 0:
            continue
        g = ASK_GET.search(src, m.end(), hi)
        if not g or not mask[g.start()]:
            continue
        params = m.group(2).split("/")[0].split()
        prompt = next((p for p in params if p.lower() in PROMPT_PARAMS), None)
        out.append({
            "fn": m.group(1),
            "var": g.group(1),
            "prompt": prompt or '"%s"' % m.group(1),
            "at": form_end(src, mask, g.start()),
            "set_lo": g.start(),
            "lo": m.start(), "hi": hi,
        })
    return out


# ------------------------------------------------- commands with no handler
# Wiring only reaches handlers that EXIST.  A command written without
# one is therefore not "unwired" -- it is invisible, and its failures
# stay exactly as silent as they were before any of this was built.  So
# the roster is checked too: a command that can leave something behind
# has to be able to reach a handler, its own or one in a helper it calls.
#
# What counts as leaving something behind is computed from the body, not
# from the name.  A *VER reporter prints its banner and stops, and
# demanding a handler off it would be noise -- but the moment one grows
# a (command ...) or a prompt it stops being a reporter, and this
# notices without anybody remembering to take it off a list.

RISKY = re.compile(
    r"\((?:command|command-s|setvar|entmake|entmakex|entmod|entdel|entupd"
    r"|getpoint|getdist|getkword|getstring|getint|getreal|getangle"
    r"|getcorner|entsel|nentsel|ssget|getfiled)\b"
    r"|\((?:vla|vlax)-")


def code_only(src, mask, lo, hi):
    """SRC[lo:hi] with every string and comment blanked out.

    Both scans below read this and not the raw text.  A prose comment
    naming a helper would otherwise count as a call to it, and -- the
    one that actually bit -- ABFINDVER prints the line "(commands:
    ABFIND, ABMOVE, ABPCREATE)", whose "(commands:" matched the risky
    "(command" and had a version reporter demanding an error handler."""
    return "".join(src[i] if mask[i] else " " for i in range(lo, hi))


#: a whole token of blanked code, as a call site delimits a name: after
#: "(", whitespace or a quote, before whitespace or ")"
_TOKEN = re.compile(r"(?<=[(\s'])[^\s()']+(?=[\s)])")
#: a character no such token holds
_NOT_A_TOKEN = re.compile(r"[\s()']")


def _defuns(src, mask):
    out = []
    for m in DEFUN_ANY.finditer(src):
        if not mask[m.start()]:
            continue
        hi = form_end(src, mask, m.start())
        if hi > 0:
            out.append((m.group(1), m.start(), hi))
    return out


def unprotected(src, mask, path):
    """Commands in this file that do something and can reach no handler.

    Reachability is within the file and transitive, because the wrapper
    shape is everywhere here: c:ABPCREATE is (abf:run 'CREATE) and
    abf:run is where the handler lives, so ABPCREATE is covered and
    saying otherwise would be a false alarm nobody could act on."""
    ds = _defuns(src, mask)
    names = {n for n, _, _ in ds}
    owners = {h["cmd_lo"] for h in handlers(src, mask, path)}
    handled = {n for n, lo, _ in ds if lo in owners}
    # The whole file blanked ONCE: code[lo:hi] is code_only(src, mask,
    # lo, hi), and a defun's calls are read off its own tokens instead
    # of one regex search per defun name in the file (a square that was
    # most of this script's run).  A delimited name is exactly a whole
    # token, so the two agree -- for a name that could itself hold a
    # delimiter, which DEFUN_ANY allows only for a quote, the old
    # search is kept.
    code = code_only(src, mask, 0, len(src))
    odd = {c for c in names if _NOT_A_TOKEN.search(c)}
    calls, risky = {}, {}
    for n, lo, hi in ds:
        body = code[lo:hi]
        calls[n] = ((names & set(_TOKEN.findall(body))) |
                    {c for c in odd
                     if re.search(r"[(\s']" + re.escape(c) + r"[\s)]",
                                  body)}) - {n}
        risky[n] = bool(RISKY.search(body))

    def walk(n, want, seen):
        if n in seen:
            return False
        seen.add(n)
        if want(n):
            return True
        return any(walk(c, want, seen) for c in calls.get(n, ()))

    out = []
    for n, lo, hi in ds:
        if not n.lower().startswith("c:"):
            continue
        if walk(n, lambda x: x in handled, set()):
            continue
        if walk(n, lambda x: risky.get(x, False), set()):
            out.append(n[2:])
    return out


# ---------------------------------------------------- the input geometry
# A report carries what a run DREW, off the entlast lzd:begin marked.
# What it was handed is the other half, and nothing recorded it: a tool
# that fails while walking a selection produced a report with the
# selection missing, which is the one thing the failure was about.
#
# So the selection calls record themselves, the same way the ask helpers
# record their prompts.  Not every selection call, though:
#
#   (ssget "_X" ...)  is the whole drawing, not an input.  A checking
#                     tool that scans 4000 entities would fill the
#                     report with the drawing and bury the failure in
#                     it, and the cap would then pick an arbitrary 400
#                     of them.  Skipped on purpose.
#   (ssget "_I" ...)  is what the drafter had already selected when they
#                     typed the command.  That IS the input.
#   (ssget) / (ssget "_:L" ...) and the rest are what they selected when
#                     asked.  Also the input.
#   (entsel ...)      one pick; lzd:watch takes the (ename point) list
#                     and keeps the ename.

SELECT_GET = re.compile(
    r"\(setq\s+([\w:-]+)\s+\(\s*(ssget|entsel|nentsel)\b([^\n]*)")

#: the modes that mean "the whole database", not "what the user gave me"
WHOLE_DB = re.compile(r'^\s*"_?[XA]"')


#: every interactive input a routine can take.  ssget is not here: a
#: selection is geometry, and lzd:watch copies it into the report rather
#: than writing it down.
INPUT_CALL = re.compile(
    r"\(\s*(getpoint|getdist|getkword|getstring|getint|getreal|getangle"
    r"|getcorner|entsel|nentsel)\b")

#: how an input is recorded where nothing binds its answer, or where
#: something reads it in place: bound for the length of one lambda and
#: handed straight back, so the wrapped call means what the bare one did
WRAP = "((lambda (v) (if lzd:ask (lzd:ask %s v) v))"
WRAPPED = "((lambda (v) (if lzd:ask (lzd:ask "

#: the bodies whose items are STATEMENTS -- evaluated for effect, their
#: values dropped unless last -- and the index each body starts at
BODY_FROM = {"defun": 3, "defun-q": 3, "lambda": 2, "progn": 1,
             "while": 2, "foreach": 3, "repeat": 2}


def head_of(src, pos):
    """The symbol a form starts with, lowercased -- "" when its first
    item is itself a form, as a cond clause's test is."""
    m = re.match(r"\(\s*([^\s()\"';]+)", src[pos:pos + 80])
    return m.group(1).lower() if m else ""


def item_index(src, mask, parent, lo):
    """(the items of PARENT, the index of the one starting at LO)."""
    kids = items(src, mask, parent + 1, form_end(src, mask, parent) - 1)
    return kids, next((i for i, (a, b) in enumerate(kids) if a == lo), None)


def is_statement(src, mask, lo):
    """True when the form at LO is a body statement: a form dropped in
    after it is evaluated for effect and nothing reads its value --
    unless it lands last, and the watch and ask forms are
    value-transparent for exactly that case."""
    parent = enclosing_call(src, lo, mask)
    if parent < 0:
        return True
    head = head_of(src, parent)
    kids, idx = item_index(src, mask, parent, lo)
    if idx is None:
        return False
    if head in BODY_FROM:
        return idx >= BODY_FROM[head]
    # a cond clause is (test body...): the test is read, the rest is body
    outer = enclosing_call(src, parent, mask)
    return outer >= 0 and head_of(src, outer) == "cond" and idx >= 1


def recorded_after(src, mask, setq_lo):
    """True when the record already follows the setq at SETQ_LO -- as
    the next item of its body, or the one after a watch call."""
    parent = enclosing_call(src, setq_lo, mask)
    if parent < 0:
        return "(if lzd:ask" in src[form_end(src, mask, setq_lo):][:200]
    kids, idx = item_index(src, mask, parent, setq_lo)
    if idx is None:
        return False
    for a, b in kids[idx + 1:idx + 3]:
        if src.startswith("(if lzd:ask", a):
            return True
    return False


def input_sites(src, mask, taken=()):
    """Every input call in the file, and how to record it.

    The ask helpers record themselves already, with their msg argument
    as the label -- that pass stays, because a helper's prompt is built
    at run time and its msg is the best name there is; TAKEN is where
    it is about to write, and those setqs are left to it.  This pass is
    for the OTHER 300: the base point c:POOL asks for directly, the
    stage loops that getkword their own way, every entsel, the getstring
    that only pauses.  A transcript that had a quarter of the inputs
    could be read; one that has all of them can be REPLAYED, which is
    what tools/probe_report.py does.

    Two shapes come back.  "after": the call is the value of a
    (setq v ...) that is itself a body statement, and the record goes in
    after the setq the way the helpers' does.  "wrap": anything else --
    a bare (getstring) that pauses, a getkword inside an (= ...), the
    (setq p (getpoint)) that is a while's test -- and the CALL is
    wrapped, ((lambda (v) (if lzd:ask (lzd:ask label v) v)) (getpoint
    ...)): the answer is bound for the length of the record and handed
    straight back, so the form means what the bare call did wherever it
    sits, and a nil that ends a loop is written down like any other
    answer.  Dropping a record in after a while's test would have run
    it only when the test passed, and the transcript would have been
    short exactly the answer that stopped the loop.

    The label is the prompt when the call names it as one literal, and
    AutoCAD's own LASTPROMPT otherwise -- which after a getpoint is the
    prompt it just showed, built or not."""
    out = []
    for m in INPUT_CALL.finditer(src):
        lo = m.start()
        if not mask[lo]:
            continue
        hi = form_end(src, mask, lo)
        if hi < 0:
            continue
        parent = enclosing_call(src, lo, mask)
        if parent >= 0 and src.startswith(WRAPPED, parent):
            continue                                    # wrapped already
        args = items(src, mask, lo + 1, hi - 1)
        label = '(getvar "LASTPROMPT")'
        if len(args) > 1 and src[args[-1][0]] == '"':
            label = src[args[-1][0]:args[-1][1]]
        site = {"fn": m.group(1), "label": label, "lo": lo, "hi": hi}
        if parent >= 0 and head_of(src, parent) == "setq":
            kids, idx = item_index(src, mask, parent, lo)
            if idx == 2 and is_statement(src, mask, parent):
                s_hi = form_end(src, mask, parent)
                if s_hi in taken or recorded_after(src, mask, parent):
                    continue
                outer = enclosing_call(src, parent, mask)
                okids, oidx = (item_index(src, mask, outer, parent)
                               if outer >= 0 else ([], None))
                if not (len(kids) > 3 and oidx is not None
                        and oidx == len(okids) - 1):
                    # not a multi-pair setq sitting last in its body --
                    # THAT one returned its last pair, and a record after
                    # it would hand back this one instead, so it is
                    # wrapped like the rest
                    site.update(kind="after", at=s_hi, set_lo=parent,
                                var=src[kids[1][0]:kids[1][1]])
                    out.append(site)
                    continue
        site.update(kind="wrap", var="v")
        out.append(site)
    return out


def wrap_text(src, mask, lo, hi, label):
    """The wrapped form of the call at LO..HI, laid out as the lambda on
    the call's old line and the call one line down and two columns in,
    its own continuation lines moved with it."""
    col = lo - (src.rfind("\n", 0, lo) + 1)
    call = "".join("\n  " if src[i] == "\n" and mask[i] else src[i]
                   for i in range(lo, hi))
    return WRAP % label + "\n" + " " * (col + 2) + call + ")"


def select_sites(src, mask):
    out = []
    for m in SELECT_GET.finditer(src):
        if not mask[m.start()]:
            continue
        if m.group(2) == "ssget" and WHOLE_DB.match(m.group(3)):
            continue
        end = form_end(src, mask, m.start())
        if end < 0:
            continue
        out.append({"var": m.group(1), "at": end, "set_lo": m.start(),
                    "fn": m.group(2)})
    return out


# --------------------------------------------- where an injection landed
# Dropping a form into a Lisp body is only free when that body is an
# implicit progn AND the form is not its last.  Land it last and the
# body's value becomes the injected form's value, which for a helper
# that ends in (setq ss (ssget ...)) means the caller gets nil instead
# of a selection.  `check_lisp` cannot see this: every shape involved is
# perfectly legal Lisp.
#
# The watch and ask injections are immune by construction -- they carry
# an else branch so the whole form evaluates to the variable either way.
# begin and report are not, so they are checked here.

INJECTED = re.compile(r"\(if lzd:(watch|ask|report|begin|end|state) ")

#: an atom or a form: a body's last item is often a bare symbol (the
#: `ss` that LINGUTTER's lg:highlight returns), and a scan that counted
#: only parenthesised forms would call the form before it "last"
ITEM = re.compile(r'"(?:[^"\\]|\\.)*"|[()]|[^\s()";]+')


def items(src, mask, lo, hi):
    """Every item directly inside LO..HI -- atoms as well as forms."""
    out, i = [], lo
    while i < hi:
        if src[i].isspace():
            i += 1
            continue
        if not mask[i]:
            # A string literal is masked out whole, quotes included, so
            # the mask alone would skip it and a body ending in a bare
            # "text" would look as if it ended one form earlier.  It is
            # an item: walk to its closing quote by the same escape rule
            # the mask used.
            if src[i] == '"' and (i == lo or not mask[i - 1] is False):
                j = i + 1
                while j < hi:
                    if src[j] == "\\":
                        j += 2
                        continue
                    if src[j] == '"':
                        j += 1
                        break
                    j += 1
                out.append((i, j))
                i = j
            else:
                i += 1
            continue
        if src[i] == "(":
            j = form_end(src, mask, i)
            if j < 0 or j > hi:
                break
            out.append((i, j))
            i = j
            continue
        if src[i] == ")":
            break
        j = i
        while j < hi and mask[j] and not src[j].isspace() and src[j] not in "()":
            j += 1
        out.append((i, j))
        i = j
    return out


#: bodies whose value is their LAST item, so a form dropped at the end
#: of one takes over what it evaluates to
IMPLICIT_PROGN = {"defun", "lambda", "progn", "while", "foreach", "repeat"}


def misplaced(src, mask, path):
    """Injected forms sitting where they change what something means."""
    out = []
    for m in INJECTED.finditer(src):
        if not mask[m.start()]:
            continue
        kind = m.group(1)
        parent = enclosing_call(src, m.start(), mask)
        if kind in ("watch", "ask"):
            # value-transparent by construction -- the else branch
            # returns the variable -- EXCEPT after a setq with more than
            # one pair, whose value was its LAST pair's, not this one.
            # None of the 29 in the tree sit last in a body; this is
            # what keeps that true.
            if parent < 0:
                continue
            phi = form_end(src, mask, parent)
            kids = items(src, mask, parent + 1, phi - 1)
            idx = next((i for i, (a, b) in enumerate(kids)
                        if a == m.start()), None)
            if idx is None or idx == 0 or idx != len(kids) - 1:
                continue
            plo, phi2 = kids[idx - 1]
            prev = items(src, mask, plo + 1, phi2 - 1)
            head = src[plo:plo + 6].lower()
            if head.startswith("(setq") and len(prev) > 3:
                out.append((src[:m.start()].count("\n") + 1, kind,
                            "follows a multi-pair setq and is last in its "
                            "body: it returns %s, the setq returned its "
                            "last pair" % src[prev[1][0]:prev[1][1]]))
            continue
        if parent < 0:
            continue
        phi = form_end(src, mask, parent)
        head = re.match(r"\(\s*([^\s()]+)", src[parent:parent + 60])
        head = head.group(1).lower() if head else "?"
        kids = items(src, mask, parent + 1, phi - 1)
        idx = next((i for i, (a, b) in enumerate(kids) if a == m.start()), None)
        last = idx is not None and idx == len(kids) - 1
        why = None
        if head in ("and", "or"):
            why = "adds a term to an (%s ...)" % head
        elif head == "if" and idx is not None and idx >= 3:
            why = "became the ELSE branch of an (if test then)"
        elif last and head in IMPLICIT_PROGN:
            why = "is the last form of a (%s ...), so its value is now " \
                  "that body's value" % head
        if why:
            out.append((src[:m.start()].count("\n") + 1, kind, why))
    return out


def end_slot(src, mask, c):
    """Where the success hook goes: in front of the COMMAND's trailing
    (princ), the same way the report goes in front of the handler's.

    That one spot catches every clean exit, because AutoLISP has no
    early return -- a command either falls out of the bottom of its
    defun or raises, and raising is the handler's business.  A command
    that ends some other way returns -1 and is left alone: the lazy
    flush in lzd:begin closes its run out at the next command instead,
    and inventing a slot for it would mean changing what it returns."""
    kids = children(src, mask, c["cmd_lo"] + 1, c["cmd_hi"] - 1)
    if kids:
        lo, hi = kids[-1]
        if re.match(r"\(princ\s*\)", src[lo:hi]):
            return lo
    return -1


def report_slot(src, mask, c):
    """Where the report call goes inside the handler: in front of its
    trailing (princ), which is the handler's return value and has to
    stay last.  A handler that does not end that way takes the call at
    the end of its body instead."""
    kids = children(src, mask, c["err_lo"] + 1, c["err_hi"] - 1)
    if kids:
        last_lo, last_hi = kids[-1]
        if re.match(r"\(princ\s*\)", src[last_lo:last_hi]):
            return last_lo
    return c["err_hi"] - 1


# ------------------------------------------------------- what a form hands in
# A form -- LAZFORM, LAZSPA, LAZSTEP, LAZSIDE, the palette -- answers a
# tool's questions by filling the tool's store and calling the command
# through its X:run-with-answers, and the questions it answered are
# never asked.  Those answers are the run's inputs as much as the typed
# ones, so the command writes its store into the transcript at the top
# (lzd:state), or a report from a form-driven run replays a run nobody
# made.  Which store is not a judgement: run-with-answers sets exactly
# one symbol and calls exactly one command, and that is read here.
# More symbols in the list -- POOL's pool:*nobottom* and pool:*hasbottom*
# run flags, which a form also sets -- are the tool's to add by hand.

RUN_WITH = re.compile(
    r"\(defun\s+[^\s()]*run-with-answers\s*\(\s*([\w-]+)\s*\)\s*"
    r"\(setq\s+([^\s()]+)\s+\1\s*\)\s*\((c:[\w-]+)\s*\)", re.I)
STATE_CALL = re.compile(r"\(if lzd:state \(lzd:state '\(([^()]*)\)\)\)")
BEGIN_CALL = re.compile(r"\(if lzd:begin ")


def form_stores(src, mask):
    """{command defun, lower-cased: the store its form entry fills}."""
    return {m.group(3).lower(): m.group(2)
            for m in RUN_WITH.finditer(src) if mask[m.start()]}


def state_edit(src, mask, c, store):
    """None when the command already hands STORE to lzd:state, else the
    edit that makes it: add the store to an lzd:state list the command
    has, or put a new call straight after its lzd:begin."""
    lo, hi = c["begin_at"], c["cmd_hi"]
    m = STATE_CALL.search(src, lo, hi)
    if m:
        names = m.group(1).split()
        if store.lower() in (n.lower() for n in names):
            return None
        return (m.start(1), " ".join(names + [store]), m.end(1))
    b = BEGIN_CALL.search(src, lo, hi)
    if not b:
        return ()          # the begin is missing too: wired with it
    end = form_end(src, mask, b.start())
    return (end, "\n%s(if lzd:state (lzd:state '(%s)))"
            % (indent_of(src, b.start()), store))


# ------------------------------------------------------------------ fixing

def wire(path, src, do_fix):
    """Returns (unwired command names, new source)."""
    mask = code_mask(src)
    ver = version_global(src)
    cmds = handlers(src, mask, path)
    stores = form_stores(src, mask)
    missing, edits = [], []
    for c in cmds:
        has_report = "lzd:report" in c["body"]
        # the success hook lives in the command body, past the handler
        has_end = "lzd:end" in src[c["err_hi"]:c["cmd_hi"]]
        # lzd:begin sits in the command body, after the handler form
        has_begin = "lzd:begin" in src[c["begin_at"]:c["cmd_hi"]]
        if has_report and has_begin and (has_end
                                         or end_slot(src, mask, c) < 0):
            continue
        missing.append(c["name"])
        if not do_fix:
            continue
        if not has_report:
            at = report_slot(src, mask, c)
            pad = indent_of(src, at)
            edits.append((at, '(if lzd:report (lzd:report "%s" %s %s))\n%s'
                          % (c["name"], ver, c["param"], pad)))
        if not has_end and end_slot(src, mask, c) >= 0:
            at = end_slot(src, mask, c)
            pad = indent_of(src, at)
            edits.append((at, '(if lzd:end (lzd:end "%s"))\n%s'
                          % (c["name"], pad)))
        if not has_begin:
            at = c["begin_at"]
            pad = indent_of(src, c["err_lo"])
            store = stores.get(c["owner"].lower())
            edits.append((at, '\n%s(if lzd:begin (lzd:begin "%s" %s))%s'
                          % (pad, c["name"], ver,
                             ("\n%s(if lzd:state (lzd:state '(%s)))"
                              % (pad, store)) if store else "")))
    for c in cmds:
        # the form's answers, written at the top of the run: see
        # form_stores.  A command whose begin was just wired got its
        # state call with it, above.
        store = stores.get(c["owner"].lower())
        if not store:
            continue
        e = state_edit(src, mask, c, store)
        if e is None or e == ():
            continue
        missing.append("%s <- %s (form answers)" % (c["name"], store))
        if do_fix:
            edits.append(e)
    for w in select_sites(src, mask):
        # already wired if the watch call is the next thing after the
        # selection -- which is exactly where this puts it, so a second
        # --fix run is a no-op rather than a second copy
        if "(if lzd:watch" in src[w["at"]:w["at"] + 200]:
            continue
        missing.append("%s <- %s" % (w["var"], w["fn"]))
        if do_fix:
            pad = indent_of(src, w["set_lo"])
            # the else branch is not decoration: it makes the whole
            # form evaluate to the variable whether LAZDIAG is loaded or
            # not, so dropping it after a (setq ss (ssget ...)) cannot
            # change what the enclosing progn or cond clause returns
            edits.append((w["at"], "\n%s(if lzd:watch (lzd:watch %s) %s)"
                          % (pad, w["var"], w["var"])))

    taken = set()
    for a in ask_helpers(src, mask):
        if "lzd:ask" in src[a["lo"]:a["hi"]]:
            continue
        missing.append(a["fn"])
        taken.add(a["at"])
        if do_fix:
            pad = indent_of(src, a["set_lo"])
            edits.append((a["at"], "\n%s(if lzd:ask (lzd:ask %s %s) %s)"
                          % (pad, a["prompt"], a["var"], a["var"])))
    for w in input_sites(src, mask, taken):
        missing.append("%s <- %s" % (w["var"], w["fn"]))
        if not do_fix:
            continue
        if w["kind"] == "after":
            pad = indent_of(src, w["set_lo"])
            edits.append((w["at"], "\n%s(if lzd:ask (lzd:ask %s %s) %s)"
                          % (pad, w["label"], w["var"], w["var"])))
        else:
            edits.append((w["lo"], wrap_text(src, mask, w["lo"], w["hi"],
                                             w["label"]), w["hi"]))

    # back to front, so an earlier edit cannot move a later offset; an
    # edit is (at, text) to insert, or (at, text, end) to replace at..end
    for e in sorted(edits, key=lambda e: -e[0]):
        at, text = e[0], e[1]
        end = e[2] if len(e) > 2 else at
        src = src[:at] + text + src[end:]
    return missing, src


# ------------------------------------------------------------ self tests
#
# The calls above make a report say what a RUN did.  They cannot make it
# say whether the tool's own helpers were sound on the machine it ran on
# -- that takes a table of self tests, which every tool carries and
# registers, and which LAZDIAG runs after a failure.  The table is
# editorial: only the tool's author knows which helpers matter and what
# they answer.  So --fix writes the skeleton and the registration -- the
# mechanical half -- and the check names the file until the entries are
# written, the way it names a command with no handler.

SELFTEST_DEFUN = re.compile(
    r"^\(defun\s+([^\s()'\"]*selftests)\s*\(\s*\)", re.M)
REGISTER = re.compile(
    r"^\(foreach\s+c\s+'\(((?:\s*\"[^\"]+\")*)\s*\)\s*"
    r"\(setq\s+\*calofin-selftests\*\s*"
    r"\(cons\s+\(cons\s+c\s+'([^\s()'\"]+)\)\s+\*calofin-selftests\*\)\)\)",
    re.M)
#: the names a file begins and reports its runs under -- the literals,
#: which is what LAZDIAG looks a table up by.  (AUTOBEAD reports under a
#: variable, but begins under a literal, so the union still names it.)
RUN_NAME = re.compile(r"\(lzd:(?:begin|report)\s+\"([^\"]+)\"")
MIN_TESTS = 3
#: what an entry may not name.  A table is evaluated from inside
#: *error*, where a prompt, a (command) or a write is a second failure
#: with nowhere to go, and a drawing edit breaks the one promise a
#: report makes -- that the drawing was not touched.
UNSAFE = {
    "getpoint", "getcorner", "getdist", "getangle", "getorient", "getint",
    "getreal", "getstring", "getkword", "getfiled", "entsel", "nentsel",
    "nentselp", "ssget", "grread", "initget", "alert",
    "command", "command-s", "vl-cmdf", "entmake", "entmakex", "entmod",
    "entdel", "entupd", "setvar", "redraw", "grdraw", "grtext", "grvecs",
    "open", "write-line", "write-char", "vl-mkdir", "vl-file-delete",
    "vl-file-copy", "vl-file-rename", "load", "vl-load-all",
}
UNSAFE_PREFIX = ("vla-", "vlax-", "acet-")
BANNER = re.compile(r"^\(if \(not \*calofin-quiet\*\)", re.M)


def run_names(src, mask):
    """The command names the file's runs are filed under, in file
    order, once each."""
    out = []
    for m in RUN_NAME.finditer(src):
        if mask[m.start()] and m.group(1).upper() not in out:
            out.append(m.group(1).upper())
    return out


def helper_prefix(src, mask, path):
    """The file's prevailing helper prefix, separator included --
    'pool:', 'cs-', 'paddle--' -- for naming its table.  The most common
    one among its defuns, c: and *error* aside; a file with no prefixed
    helper at all is named after itself."""
    counts = {}
    for name, lo, hi in _defuns(src, mask):
        low = name.lower()
        if low.startswith("c:") or low == "*error*":
            continue
        if ":" in low:
            pre = low[:low.index(":") + 1]
        elif "--" in low:
            pre = low[:low.index("--") + 2]
        elif "-" in low[1:]:
            pre = low[:low.index("-", 1) + 1]
        else:
            continue
        counts[pre] = counts.get(pre, 0) + 1
    if not counts:
        return pathlib.Path(path).stem.lower() + ":"
    return max(counts, key=lambda k: (counts[k], -len(k)))


def table_entries(src, mask, lo, hi):
    """(count, why) for the table defun at LO..HI: how many entries its
    (list ...) holds, or why that could not be read."""
    inner = children(src, mask, lo + 1, hi - 1)
    # the arglist is the first child form; the body follows
    body = inner[1:]
    if len(body) != 1 or not src[body[0][0]:].startswith("(list"):
        return -1, "its body is not one (list ...) form"
    blo, bhi = body[0]
    return len(children(src, mask, blo + 1, bhi - 1)), ""


def unsafe_calls(src, mask, lo, hi):
    """The names an entry may not call, found in the table's code."""
    code = code_only(src, mask, lo, hi)
    hits = set()
    for m in re.finditer(r"\(\s*([^\s()']+)", code):
        name = m.group(1).lower()
        if name in UNSAFE or name.startswith(UNSAFE_PREFIX):
            hits.add(name)
    return sorted(hits)


def skeleton(prefix, names):
    return (
        # a TWO-semicolon rule on purpose: tools/knobs.py reads a tunables
        # block as running to the next ";;; ---" rule, and a file whose
        # own sections are ";; ---" (PADDLE, CABHD, ABLOBF) had none after
        # its header, so a three-semicolon rule here stretched its block
        # over the whole file and into LAZTUNE's catalog
        ";; -------------------- self tests ---------------------------------------\n"
        ";; What LAZDIAG runs on the drafter's machine after this tool fails, and\n"
        ";; writes into the report: the tool's own helpers on inputs whose answers\n"
        ";; are KNOWN, so the report says whether the arithmetic was sound where\n"
        ";; it ran.  (label expression expected) passes when the value is equal\n"
        ";; to expected (to 1e-6); (label expression) passes when it is not nil,\n"
        ";; and the value is written down either way.  Nothing here may prompt,\n"
        ";; draw or (command): it is evaluated from inside *error*.\n"
        ";; tests/test_selftests.py runs every entry in the VM at both tiers.\n"
        "(defun %sselftests ()\n"
        "  (list\n"
        "    ;; write at least %d:\n"
        "    ;;   (list \"what it checks\" '(%shelper args) expected)\n"
        "  ))\n\n" % (prefix, MIN_TESTS, prefix)
        + registration(prefix, names) + "\n")


def registration(prefix, names):
    return ("(foreach c '(%s)\n"
            "  (setq *calofin-selftests*\n"
            "        (cons (cons c '%sselftests) *calofin-selftests*)))\n"
            % (" ".join('"%s"' % n for n in names), prefix))


def skeleton_slot(src, mask):
    """Where a new table goes: ahead of the load banner and the comment
    block sitting on it, so the banner stays the file's last word."""
    hits = [m for m in BANNER.finditer(src) if mask[m.start()]]
    if not hits:
        return len(src)
    at = hits[-1].start()
    # back over the comment lines directly above the banner
    lines = src[:at].split("\n")
    k = len(lines) - 1          # lines[-1] is "" (the banner starts a line)
    while k > 0 and lines[k - 1].startswith(";"):
        k -= 1
    return len("\n".join(lines[:k])) + (1 if k > 0 else 0)


def selftests(path, src, mask, do_fix):
    """(findings, edits) for the file's self-test table.  A finding is
    a string naming what is missing; an edit is what --fix writes for
    it, when the missing thing is mechanical."""
    names = run_names(src, mask)
    if not names:
        return [], []           # nothing reports, so nothing would run it
    findings, edits = [], []
    defs = [m for m in SELFTEST_DEFUN.finditer(src) if mask[m.start()]]
    regs = [m for m in REGISTER.finditer(src) if mask[m.start()]]
    if not defs:
        findings.append("no self-test table: --fix writes the skeleton, "
                        "then write at least %d entries" % MIN_TESTS)
        if do_fix:
            edits.append((skeleton_slot(src, mask),
                          skeleton(helper_prefix(src, mask, path), names)))
        return findings, edits
    if len(defs) > 1:
        findings.append("two self-test tables (%s): keep one"
                        % ", ".join(m.group(1) for m in defs))
        return findings, edits
    d = defs[0]
    lo, hi = d.start(), form_end(src, mask, d.start())
    n, why = table_entries(src, mask, lo, hi)
    if why:
        findings.append("%s: %s" % (d.group(1), why))
    elif n < MIN_TESTS:
        findings.append("%s holds %d entr%s: write at least %d known-answer "
                        "tests of the tool's own helpers"
                        % (d.group(1), n, "y" if n == 1 else "ies", MIN_TESTS))
    bad = unsafe_calls(src, mask, lo, hi)
    if bad:
        findings.append("%s calls %s: a table runs from inside *error* and "
                        "may not prompt, draw, write or run a command"
                        % (d.group(1), ", ".join(bad)))
    want = registration(d.group(1)[:-len("selftests")], names)
    if not regs:
        findings.append("%s is not registered: --fix writes the "
                        "(foreach ...) under every command that reports"
                        % d.group(1))
        if do_fix:
            edits.append((hi, "\n\n" + want.rstrip("\n")))
    else:
        r = regs[-1]
        have = re.findall(r'"([^"]+)"', r.group(1))
        if len(regs) > 1:
            findings.append("registered twice: keep one (foreach ...)")
        elif have != names or r.group(2) != d.group(1):
            findings.append("registered as %s under %s; the file reports as "
                            "%s -- --fix rewrites the (foreach ...)"
                            % (r.group(2), " ".join(have), " ".join(names)))
            if do_fix:
                edits.append((r.start(), want.rstrip("\n"), r.end()))
    return findings, edits


def lisp_files():
    """Every hand-edited .lsp: the standalone tree, plus the library.

    shared/parts/<TOOL>.lsp is NOT here and must not be -- those twins
    are generated by mirror_shared.py from lisp/, so wiring them
    directly would be an edit the next regeneration threw away.
    CALOFIN-LIB.lsp is the exception the mirror does not write, and it
    is where the grouped build's ask helpers actually live."""
    for p in sorted((REPO / "lisp").rglob("*")):
        if p.suffix.lower() != ".lsp":
            continue
        if SKIP_DIRS & set(p.relative_to(REPO).parts):
            continue
        yield p
    yield REPO / "shared" / "parts" / "CALOFIN-LIB.lsp"


def main(argv):
    do_fix = "--fix" in argv
    bad = 0
    fixed = 0
    naked = []
    wrong = []
    untested = []
    for p in lisp_files():
        src = p.read_text()
        missing, new = wire(p, src, do_fix)
        if do_fix and new != src:
            p.write_text(new)
            fixed += len(missing)
            print("wired  %s: %s" % (p.relative_to(REPO), ", ".join(missing)))
            src = new
        elif missing:
            bad += len(missing)
            print("%s: %s does not report failures to LAZDIAG"
                  % (p.relative_to(REPO), ", ".join(missing)))
        mask = code_mask(src)
        for cmd in unprotected(src, mask, p):
            naked.append((cmd, p.relative_to(REPO)))
        for ln, kind, why in misplaced(src, mask, p):
            wrong.append((p.relative_to(REPO), ln, kind, why))
        if p.name == "CALOFIN-LIB.lsp":
            continue            # a library, not a tool: no run is filed under it
        findings, edits = selftests(p, src, mask, do_fix)
        if do_fix and edits:
            for e in sorted(edits, key=lambda e: -e[0]):
                end = e[2] if len(e) > 2 else e[0]
                src = src[:e[0]] + e[1] + src[end:]
            p.write_text(src)
            fixed += len(edits)
            print("table  %s: %s" % (p.relative_to(REPO), "; ".join(findings)))
            # what --fix wrote may still leave the editorial half undone
            findings, _ = selftests(p, src, code_mask(src), False)
        for f in findings:
            untested.append((p.relative_to(REPO), f))

    for rel, ln, kind, why in wrong:
        print("%s:%d: the lzd:%s call %s" % (rel, ln, kind, why))
    if wrong:
        print("\nAn injected call is not free where it lands: move it so it "
              "is not the last")
        print("form of a body, and not a term of an (and ...) or a branch "
              "of an (if ...).\n")

    for cmd, rel in naked:
        print("%s: %s has no *error* handler to report from" % (rel, cmd))
    if naked:
        # deliberately NOT something --fix writes.  What belongs in a
        # handler is the one editorial thing here: which sysvars this
        # command changed, whether it has an undo group open, what it
        # drew that has to be swept.  Guessing that wrong is worse than
        # not writing it -- a handler that restores the wrong thing is a
        # bug the drafter meets in the NEXT command they run.
        print("\nWrite one, on the STANDARDS section 5 skeleton, and put "
              "the two LAZDIAG lines in it;")
        print("--fix will not guess what a handler has to put back.")

    for rel, f in untested:
        print("%s: %s" % (rel, f))
    if untested:
        print("\nA report of a failure runs the tool's own self tests on the "
              "drafter's machine and")
        print("writes the answers in; a tool without a table reports a "
              "failure and nothing about")
        print("whether its helpers were sound where it ran.  --fix writes "
              "the skeleton; the")
        print("entries are yours (LAZDIAG.lsp, \"the tool's own self "
              "tests\").\n")

    if do_fix:
        print("check_lazdiag: wired %d thing(s) - now mirror, regenerate "
              "and test:" % fixed)
        print("    python3 tools/mirror_shared.py")
        print("    python3 tools/release_lisp.py")
        print("    python3 tools/build_shared_bundle.py")
        return 1 if (naked or wrong or untested) else 0
    if bad or naked or wrong or untested:
        if bad:
            print("check_lazdiag: %d command(s) unwired - repair with "
                  "--fix" % bad)
        if untested:
            print("check_lazdiag: %d file(s) without a full self-test table"
                  % len({rel for rel, _ in untested}))
        return 1
    print("check_lazdiag: every command reports its failures, and every "
          "tool carries its self tests")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
