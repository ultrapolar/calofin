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

Exit 0 when every command in lisp/ is wired, 1 otherwise.  `make check`
runs it, so a new tool cannot ship unwired.
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
        found = NAMED_FALLBACK.findall(body[enclosing_call(body, i):i])
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
    return 0


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
            end = form_end(src, mask, outer)
            if end > 0:
                begin_at = end
        out.append({
            "name": tool_name(body, owner, path),
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
    calls, risky = {}, {}
    for n, lo, hi in ds:
        body = code_only(src, mask, lo, hi)
        calls[n] = {c for c in names
                    if re.search(r"[(\s']" + re.escape(c) + r"[\s)]", body)} - {n}
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


# ------------------------------------------------------------------ fixing

def wire(path, src, do_fix):
    """Returns (unwired command names, new source)."""
    mask = code_mask(src)
    ver = version_global(src)
    cmds = handlers(src, mask, path)
    missing, edits = [], []
    for c in cmds:
        has_report = "lzd:report" in c["body"]
        # lzd:begin sits in the command body, after the handler form
        has_begin = "lzd:begin" in src[c["begin_at"]:c["cmd_hi"]]
        if has_report and has_begin:
            continue
        missing.append(c["name"])
        if not do_fix:
            continue
        if not has_report:
            at = report_slot(src, mask, c)
            pad = indent_of(src, at)
            edits.append((at, '(if lzd:report (lzd:report "%s" %s %s))\n%s'
                          % (c["name"], ver, c["param"], pad)))
        if not has_begin:
            at = c["begin_at"]
            pad = indent_of(src, c["err_lo"])
            edits.append((at, '\n%s(if lzd:begin (lzd:begin "%s" %s))'
                          % (pad, c["name"], ver)))
    for w in select_sites(src, mask):
        # already wired if the watch call is the next thing after the
        # selection -- which is exactly where this puts it, so a second
        # --fix run is a no-op rather than a second copy
        if "(if lzd:watch" in src[w["at"]:w["at"] + 200]:
            continue
        missing.append("%s <- %s" % (w["var"], w["fn"]))
        if do_fix:
            pad = indent_of(src, w["set_lo"])
            edits.append((w["at"], "\n%s(if lzd:watch (lzd:watch %s))"
                          % (pad, w["var"])))

    for a in ask_helpers(src, mask):
        if "lzd:ask" in src[a["lo"]:a["hi"]]:
            continue
        missing.append(a["fn"])
        if do_fix:
            pad = indent_of(src, a["set_lo"])
            edits.append((a["at"], "\n%s(if lzd:ask (lzd:ask %s %s))"
                          % (pad, a["prompt"], a["var"])))
    # back to front, so an earlier insert cannot move a later offset
    for at, text in sorted(edits, key=lambda e: -e[0]):
        src = src[:at] + text + src[at:]
    return missing, src


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
        for cmd in unprotected(src, code_mask(src), p):
            naked.append((cmd, p.relative_to(REPO)))

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

    if do_fix:
        print("check_lazdiag: wired %d command(s) - now mirror, regenerate "
              "and test:" % fixed)
        print("    python3 tools/mirror_shared.py")
        print("    python3 tools/release_lisp.py")
        print("    python3 tools/build_shared_bundle.py")
        return 1 if naked else 0
    if bad or naked:
        if bad:
            print("check_lazdiag: %d command(s) unwired - repair with "
                  "--fix" % bad)
        return 1
    print("check_lazdiag: every command reports its failures")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
