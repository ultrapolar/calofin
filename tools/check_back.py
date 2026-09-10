#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every prompt that offers no Back is one somebody decided about.

STANDARDS.md section 3 and the root README's "Going back a step" say a
question re-asks the one before it, and name the handful of reasons a
prompt legitimately offers no way back: nothing is in front of it, a
selection is (and cannot be typed at), the geometry in front of it is
already drawn, the prompt IS the correction of a failed range check, or
the question would answer itself the same way twice.

Those are decisions, not defaults, and a decision that lives only in
somebody's head is one the next prompt quietly copies.  So the whole set
is written down in tools/back_baseline.txt, and this check compares the
tree against it:

  * a prompt that offers no Back and is not in the baseline FAILS - the
    author either threads it into its chain or records the reason;
  * a baselined prompt that has since gained one, or been reworded or
    deleted, is reported as stale so the file cannot rot.

It is deliberately NOT a judgement about whether the reason is a good
one - tests/test_back_nav.py drives the chains that do exist, and the
reasons are prose in the baseline for a person to read.  What this stops
is a new one-way prompt arriving without anyone noticing.

    python3 tools/check_back.py
    python3 tools/check_back.py --update-baseline

Exit 0 when the tree and the baseline agree, 1 otherwise.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from callib import LISP_DIR, ROOT, lsp_files, read

BASELINE = pathlib.Path(__file__).resolve().parent / "back_baseline.txt"

#: the prompting builtins.  ssget/entsel are left out on purpose: an
#: AutoCAD selection cannot take a keyword at all, so there is no prompt
#: there to offer Back at.
CALLS = ("getkword", "getreal", "getdist", "getstring", "getint",
         "getpoint", "getangle", "getcorner")
CALL_RE = re.compile(r"\((" + "|".join(CALLS) + r")\b")


def uncommented(src):
    """SRC with comment tails dropped, so prose about Back is not read
    as code that offers it."""
    keep = []
    for line in src.splitlines():
        res, instr, i = [], False, 0
        while i < len(line):
            c = line[i]
            if c == '"' and (i == 0 or line[i - 1] != "\\"):
                instr = not instr
            if c == ";" and not instr:
                break
            res.append(c)
            i += 1
        keep.append("".join(res))
    return "\n".join(keep)


def sexp_at(lines, li, col):
    """The s-expression starting at LINES[li][col] == '(', flattened."""
    depth, instr, buf, i, j = 0, False, [], li, col
    while i < len(lines):
        line = lines[i]
        while j < len(line):
            c = line[j]
            buf.append(c)
            if instr:
                if c == '"' and line[j - 1] != "\\":
                    instr = False
            elif c == '"':
                instr = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return "".join(buf)
            j += 1
        buf.append(" ")
        i += 1
        j = 0
    return "".join(buf)


def initget_before(lines, li):
    """The (initget ...) that arms the prompt on LINES[li], if any.

    A prompt takes its keywords from the initget most recently evaluated,
    which in practice is written just above it - usually the line before,
    sometimes two or three up past a (setq or a comment.  Six lines is
    generous and still short enough not to reach the previous prompt's.
    """
    for k in range(li, max(-1, li - 6), -1):
        if "(initget" in lines[k]:
            m = re.search(r"\(initget\b", lines[k])
            return sexp_at(lines, k, m.start())
    return ""


def fingerprint(flat):
    """A prompt site named by what it SAYS, not by where it sits.

    Line numbers rot on the first edit above them; the prompt's own text
    does not, and when it does change that is exactly when the decision
    behind it is worth re-reading.
    """
    lits = re.findall(r'"((?:[^"\\]|\\.)*)"', flat)
    text = " ".join(lits)[:110]
    return " ".join(text.split())


def offers_back(flat, arming, params):
    """T when this site can take Back.

    Three ways it can: the prompt says so, the initget that armed it
    lists the keyword, or the site sits in a helper that takes a BACK
    argument - which is the repo's idiom for "the caller decides", and
    is how every typed prompt takes it (a getstring cannot be armed with
    initget, so its Back is read out of the answer a line or two below).
    """
    both = flat + " " + arming
    if "Back" in both or "back" in both:
        return True
    return "back" in params


#: ``(defun cs-ask-thing (...`` - who a prompt belongs to.  Several
#: prompts build their text out of a MSG argument and so fingerprint to
#: almost nothing; the defun is what tells those apart, and it is also
#: what says a prompt lives in a tutorial rather than in the command.
DEFUN_RE = re.compile(r"^\(defun\s+([^\s()]+)\s*\(([^)]*)\)?")


def survey():
    """Every prompt site in lisp/ that offers no Back, as
    {(file, defun, fingerprint): line}."""
    out = {}
    for p in lsp_files(LISP_DIR):
        rel = str(p.relative_to(ROOT))
        lines = uncommented(read(p)).split("\n")
        owner, params = "(top level)", ""
        for li, line in enumerate(lines):
            m = DEFUN_RE.match(line)
            if m:
                owner = m.group(1)
                # the argument list may wrap; the slash starts the
                # locals, and a BACK past it is a local, not an argument
                params = (m.group(2) or "").split("/")[0]
            for m in CALL_RE.finditer(line):
                flat = " ".join(sexp_at(lines, li, m.start()).split())
                if offers_back(flat, initget_before(lines, li), params):
                    continue
                out.setdefault((rel, owner, fingerprint(flat)), li + 1)
    return out


def load_baseline():
    if not BASELINE.is_file():
        return {}
    out = {}
    for ln in BASELINE.read_text(encoding="utf-8").splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("|")
        if len(parts) >= 4:
            out[(parts[0], parts[1], parts[2])] = parts[3]
    return out


#: What each site's reason is, worked out from what it asks.  Only ever
#: a STARTING POINT: --update-baseline writes it beside a new site so
#: whoever accepts the site has something to correct, and the file is
#: hand-edited from there.
def guess(rel, owner, fp):
    t = fp.lower()
    who = (rel + " " + owner).lower()
    if "tutorial" in who or "tut-" in who or "-tut" in who or "demo" in who:
        return "demo / tutorial"
    if ("press enter" in t or "[enter] to continue" in t
            or "enter to go on" in t or "enter to carry on" in t
            or "next topic" in t):
        return "pause"
    if ("demo" in t or "practice drawing" in t or "clear spot" in t
            or "tutorial" in t or "checklist" in t):
        return "demo / tutorial"
    if "keep which fit" in t:
        return "the fit picker - Redo is its way back"
    if "to omit" in t or "to leave out" in t or "un-rings it" in t:
        return "reselection loop - clicking again undoes it"
    if "move/keep/pick" in t or "flag/leave" in t:
        return "first question about one reviewed item"
    if ("side profile" in t or "bead the steps" in t
            or "bottom of the pool" in t or "reconstructed boundary" in t
            or "repeat on the new polyline" in t
            or "continue from another dimension" in t):
        return "past committed geometry"
    if "step width" in t:
        return "part of the step the next tread prompt takes back"
    if "direction / offset side" in t:
        return "follows a resize already applied to the drawing"
    return "first question of its command or branch"


def main(argv):
    update = "--update-baseline" in argv
    found = survey()
    base = load_baseline()

    new = sorted(k for k in found if k not in base)
    stale = sorted(k for k in base if k not in found)

    if update:
        merged = {k: base.get(k) or guess(*k) for k in found}
        BASELINE.write_text(
            "# Every prompt in lisp/ that offers no Back, and why.\n"
            "# One line per site: file|the defun asking|what it asks|why.\n"
            "#\n"
            "# The reasons are the ones README.md's \"Going back a step\"\n"
            "# sets out.  A NEW line here is a decision: thread the prompt\n"
            "# into its chain, or say here which reason it falls under.\n"
            "# Regenerate with: python3 tools/check_back.py --update-baseline\n"
            + "".join("%s|%s|%s|%s\n" % (f, d, p, merged[(f, d, p)])
                      for f, d, p in sorted(merged)),
            encoding="utf-8")
        print("check_back: baseline updated - %d site(s) accepted" % len(merged))
        return 0

    for f, d, p in new:
        print("%s:%d: %s offers no Back and is not in "
              "tools/back_baseline.txt" % (f, found[(f, d, p)], d))
        print("    asks: %s" % p)
    for f, d, p in stale:
        print("%s: %s - baselined prompt is gone, reworded, or now offers "
              "Back" % (f, d))
        print("    was: %s" % p)

    if new or stale:
        print("check_back: %d new, %d stale - thread the prompt into its "
              "chain, or accept it with --update-baseline"
              % (len(new), len(stale)))
        return 1
    print("check_back: %d prompt(s) offer no Back, every one of them "
          "accounted for" % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
