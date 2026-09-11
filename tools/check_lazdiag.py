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
DEFUN_ERR = re.compile(r"\(defun\s+\*error\*\s*\(\s*([\w-]+)")

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


def enclosing_call(body, i):
    """Index of the "(" opening the innermost form still open at I --
    the (strcat ...) the message is being built in."""
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
    for em in DEFUN_ERR.finditer(src):
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
        out.append({
            "name": tool_name(body, owner, path),
            "param": em.group(1),            # msg / m
            "cmd_lo": lo, "cmd_hi": hi,
            "err_lo": err_lo, "err_hi": err_hi,
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
        has_begin = "lzd:begin" in src[c["err_hi"]:c["cmd_hi"]]
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
            at = c["err_hi"]
            pad = indent_of(src, c["err_lo"])
            edits.append((at, '\n%s(if lzd:begin (lzd:begin "%s" %s))'
                          % (pad, c["name"], ver)))
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
    for p in lisp_files():
        src = p.read_text()
        missing, new = wire(p, src, do_fix)
        if not missing:
            continue
        rel = p.relative_to(REPO)
        if do_fix and new != src:
            p.write_text(new)
            fixed += len(missing)
            print("wired  %s: %s" % (rel, ", ".join(missing)))
        else:
            bad += len(missing)
            print("%s: %s does not report failures to LAZDIAG"
                  % (rel, ", ".join(missing)))
    if do_fix:
        print("check_lazdiag: wired %d command(s) - now mirror, regenerate "
              "and test:" % fixed)
        print("    python3 tools/mirror_shared.py")
        print("    python3 tools/release_lisp.py")
        print("    python3 tools/build_shared_bundle.py")
        return 0
    if bad:
        print("check_lazdiag: %d command(s) unwired - repair with "
              "--fix" % bad)
        return 1
    print("check_lazdiag: every command reports its failures")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
