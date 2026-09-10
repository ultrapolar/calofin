#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Back / Undo, the way STANDARDS.md section 3 promises it.

Two halves, and they answer two different questions.

THE INVARIANT, read off every .lsp in the tier.  "Undo is accepted
everywhere Back is" is a promise about a hidden synonym: nothing in the
prompt text says U works, so nothing in the prompt text can catch it
when it stops working.  Here every initget list that offers Back is
checked for Undo beside it, every typed-prompt back predicate is checked
for all four of B/BACK/U/UNDO, and every place that tests an answer
against the string "Back" is checked for testing "Undo" too -- a
keyword list that accepts U while the cond below it only looks for
"Back" would take the keystroke and then ignore it, which is worse than
not offering it at all.

THE BEHAVIOUR, driven through the real routines in the VM.  The
invariant cannot see whether Back actually goes anywhere: that a step
answered Back re-asks the one before it, that a draw-as-you-go loop
takes back what it drew, and that a step re-opened from below drops what
the earlier pass collected there instead of piling the new answer on top
of the old.  Each tool whose chain was threaded is walked backwards here
and read.

Usage:  python3 tests/test_back_nav.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_back_nav.py
"""

import io
import contextlib
import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

LISP_ROOT = os.path.join(REPO_DIR, os.environ.get("CALOFIN_LISP_ROOT", "lisp"))

FAILS = []


def check(label, cond, detail=''):
    print(('  ok   ' if cond else '  FAIL ') + label
          + (('  -- ' + str(detail)) if (detail and not cond) else ''))
    if not cond:
        FAILS.append(label)


# ------------------------------------------------------------- the tier

def lsp_files():
    """Every .lsp under the tier being tested, path and text."""
    out = []
    for root, _dirs, names in os.walk(LISP_ROOT):
        for n in sorted(names):
            if n.lower().endswith('.lsp'):
                p = os.path.join(root, n)
                with open(p, encoding='utf-8', errors='replace') as fh:
                    out.append((os.path.relpath(p, REPO_DIR), fh.read()))
    return sorted(out)


def uncommented(src):
    """SRC with comment tails dropped, so prose about Back is not read
    as code that offers it."""
    keep = []
    for line in src.splitlines():
        res, instr, i = [], False, 0
        while i < len(line):
            c = line[i]
            if c == '"' and (i == 0 or line[i - 1] != '\\'):
                instr = not instr
            if c == ';' and not instr:
                break
            res.append(c)
            i += 1
        keep.append(''.join(res))
    return '\n'.join(keep)


FILES = lsp_files()


# --------------------------------------------- 1. Undo beside every Back

def sexp_from(text, i):
    """The s-expression that starts at TEXT[i] == '(', as a string."""
    depth, instr, j = 0, False, i
    while j < len(text):
        c = text[j]
        if instr:
            if c == '"' and text[j - 1] != '\\':
                instr = False
        elif c == '"':
            instr = True
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
        j += 1
    return text[i:]


def initget_lists(code):
    """Every keyword list an (initget ...) sets, as a list of words.

    The words are gathered from ALL the string literals in the call, not
    just the first: several prompts build the list with strcat, so that
    a keyword only offered sometimes -- HEMISTEP's Same -- is only in
    the list sometimes.
    """
    out = []
    for m in re.finditer(r'\(initget\b', code):
        call = sexp_from(code, m.start())
        words = []
        for lit in re.findall(r'"([^"]*)"', call):
            words.extend(lit.split())
        if words:
            out.append((words, ' '.join(call.split())))
    return out


print("the hidden synonym: U works wherever B does")

bad = []
for path, src_ in FILES:
    for words, call in initget_lists(uncommented(src_)):
        if 'Back' in words and 'Undo' not in words:
            bad.append('%s: %s' % (path, call[:70]))
check("every initget list offering Back offers Undo too", not bad, bad[:4])
check("...and there are some to check",
      sum(1 for p, s in FILES
          for w, _c in initget_lists(uncommented(s)) if 'Back' in w) >= 30)


# ------------------------------------- 2. the typed-prompt back predicate

print("\ntyped prompts: B, BACK, U and UNDO, in any case")

#: '("B" "BACK" "U" "UNDO") -- the shared predicate, copied per file.
#: Typed back words are written in upper case, which is what separates
#: them from '("Back" "Undo"), the KEYWORD answers a getkword hands back.
TYPED = re.compile(r"'\(\s*((?:\"[A-Z]+\"\s*)+)\)")

seen, bad, unfolded = 0, [], []
for path, src_ in FILES:
    code = uncommented(src_)
    for m in TYPED.finditer(code):
        words = re.findall(r'"([A-Z]+)"', m.group(1))
        if 'BACK' not in words and 'UNDO' not in words:
            continue
        seen += 1
        if set(words) != {'B', 'BACK', 'U', 'UNDO'}:
            bad.append('%s: %r' % (path, words))
        # the answer has to be folded before it is looked up, or a
        # lower-case "b" is taken as a note rather than as Back.  The
        # fold may sit at the list (member (strcase s) '(...)) or at the
        # variable the list was stashed in, so the whole file is asked.
        if 'strcase' not in code:
            unfolded.append(path)
check("every typed back-word list is exactly B/BACK/U/UNDO", not bad, bad[:4])
check("...and there are some to check", seen >= 10, "%d found" % seen)
check("...and every file holding one folds case", not unfolded, unfolded[:4])


# ------------------------------- 3. a Back keyword the code then ignores

print("\nno prompt takes Back and then drops it")

#: A file whose prompts accept Back as a KEYWORD has to recognise the
#: answer.  getkword hands back the keyword as written, so the code
#: reads it as the string "Back" -- and, since Undo is a separate
#: keyword rather than an alias AutoCAD resolves, as "Undo" beside it.
bad = []
for path, src_ in FILES:
    code = uncommented(src_)
    offers = any('Back' in w for w, _c in initget_lists(code))
    if not offers:
        continue
    reads_back = '"Back"' in code
    reads_undo = '"Undo"' in code
    if reads_back and not reads_undo:
        bad.append(path)
check("every file that offers the keyword reads Undo as well as Back",
      not bad, bad[:4])


# --------------------------------------------------- 4. ABHD walks back

print("\nABHD: the seven-step chain, walked backwards")

with contextlib.redirect_stdout(io.StringIO()):
    import test_abhd_contingencies as A       # noqa: E402  (runs its own suite)

vm, ents = A.survey_vm()
A.run(vm, 'c:ABHD',
      [None,                        # the pickfirst probe
       None,                        # step 1  tolerance      Enter
       30,                          # step 2  percent
       'Back',                      # step 3  cap      -> step 2
       None,                        # step 2  percent        Enter
       25,                          # step 3  cap
       'B',                         # step 4  walls    -> step 3   (short form)
       40,                          # step 3  cap
       None,                        # step 4  walls          Enter = No
       'U',                         # step 5  corners  -> step 4   (synonym)
       'Yes',                       # step 4  walls
       A.RING[0], A.RING[6],        #         a declared wall
       'Back',                      #         "Another?" -> take it back
       A.RING[1], A.RING[7], 'No',  #         declare a different one
       'Back',                      # step 5  corners  -> step 4
       'No', 'No', 'No',            # steps 4, 5, 6
       ents, 'None'])
said = A.said(vm)

check("Back at step 3 re-asks step 2", said.count("Step 2 of 7") >= 2)
check("B is taken as Back at a numeric prompt", said.count("Step 3 of 7") >= 3)
check("U is taken as Back at a keyword prompt", said.count("Step 4 of 7") >= 3)
check("the chain says which way it moved", "Stepping back one question" in said)
check("Back in the wall loop takes back that wall",
      "Stepping back one wall" in said)
check("a step re-opened from below drops what it collected",
      "straight wall(s) noted" not in said.split("Step 5 of 7")[-1])
check("...markers included",
      not A.live(vm, lay='POOL-WALLS'),
      "%d left" % len(A.live(vm, lay='POOL-WALLS')))

vm, ents = A.survey_vm()
A.run(vm, 'c:ABHD',
      [None, None, None, None,      # pickfirst + steps 1-3
       'Yes',                       # step 4: yes, there are walls
       'Back',                      #   ...at the first end: nothing to undo
       'No',                        # so step 4 asks again, and is answered No
       'No', 'No',                  # steps 5, 6
       ents, 'None'])
said = A.said(vm)
check("Back at the first item of a loop says so",
      "Already at the first wall" in said)
check("...and re-opens the question that started the loop",
      said.count("Step 4 of 7") >= 2)
check("...leaving nothing declared", "straight wall(s) noted" not in said)


# ------------------------------------------------------------------ done

print()
if FAILS:
    print("FAILED: " + "; ".join(FAILS))
    sys.exit(1)
print("ALL BACK-NAVIGATION CHECKS PASSED")
