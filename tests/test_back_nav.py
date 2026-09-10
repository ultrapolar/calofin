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


# ----------------------------------------------- the driven half's kit
# Each tool's own suite patches lispvm's module-global BUILTINS table,
# so importing two of them into one process leaves the second running on
# the first one's overrides.  These fixtures are therefore built here,
# from the VM alone, rather than borrowed.

from lispvm import VM                                     # noqa: E402


def newvm(rel):
    """A VM with one tool loaded.  The path is always the lisp/ one -
    the VM itself remaps it when CALOFIN_LISP_ROOT names another tier."""
    vm = VM()
    vm.load(os.path.join(REPO_DIR, 'lisp', *rel))
    return vm


def layer(vm, name, colour=7):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") (cons 2 "%s") \'(70 . 0)'
             ' (cons 62 %d) \'(6 . "Continuous")))' % (name, colour))


def survey(vm, pts, lay='POINTS'):
    """One numbered ab_pt insert per point - what a real survey is."""
    out = []
    for i, p in enumerate(pts, start=1):
        vm.loads('(entmake (list \'(0 . "INSERT") \'(2 . "ab_pt")'
                 ' (cons 8 "%s") (list 10 %.6f %.6f 0.0)))'
                 % (lay, p[0], p[1]))
        out.append(vm.entities[-1])
        vm.loads('(entmake (list \'(0 . "ATTRIB") (cons 8 "%s")'
                 ' \'(2 . "number") (cons 1 "%d")))' % (lay, i))
    return out


def plain_points(vm, pts, lay='POINTS'):
    out = []
    for p in pts:
        vm.loads('(entmake (list \'(0 . "POINT") (cons 8 "%s")'
                 ' (list 10 %.6f %.6f 0.0)))' % (lay, p[0], p[1]))
        out.append(vm.entities[-1])
    return out


def ring(n=12, a=144.0, b=84.0):
    import math
    return [(a * math.cos(2.0 * math.pi * i / n),
             b * math.sin(2.0 * math.pi * i / n)) for i in range(n)]


RING = ring()


def said(vm):
    return ''.join(vm.printed)


def live(vm, lay=None):
    """The entities still in the drawing on LAY."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        ed = dict((k, v) for k, v in getattr(e, 'data', []) or [])
        if lay is None or str(ed.get(8, '')).upper() == lay.upper():
            out.append(e)
    return out


# --------------------------------------------------- 4. ABHD walks back

print("\nABHD: the seven-step chain, walked backwards")

vm = newvm(('abhd', 'abhd.lsp'))
layer(vm, 'POINTS')
layer(vm, 'POOL', 4)
ents = survey(vm, RING)
vm.run('c:ABHD',
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
        RING[0], RING[6],            #         a declared wall
        'Back',                      #         "Another?" -> take it back
        RING[1], RING[7], 'No',      #         declare a different one
        'Back',                      # step 5  corners  -> step 4
        'No', 'No', 'No',            # steps 4, 5, 6
        ents, 'None'])
out = said(vm)

check("Back at step 3 re-asks step 2", out.count("Step 2 of 7") >= 2)
check("B is taken as Back at a numeric prompt", out.count("Step 3 of 7") >= 3)
check("U is taken as Back at a keyword prompt", out.count("Step 4 of 7") >= 3)
check("the chain says which way it moved", "Stepping back one question" in out)
check("Back in the wall loop takes back that wall",
      "Stepping back one wall" in out)
check("a step re-opened from below drops what it collected",
      "straight wall(s) noted" not in out.split("Step 5 of 7")[-1])
check("...markers included", not live(vm, lay='POOL-WALLS'),
      "%d left" % len(live(vm, lay='POOL-WALLS')))

vm = newvm(('abhd', 'abhd.lsp'))
layer(vm, 'POINTS')
layer(vm, 'POOL', 4)
ents = survey(vm, RING)
vm.run('c:ABHD',
       [None, None, None, None,      # pickfirst + steps 1-3
        'Yes',                       # step 4: yes, there are walls
        'Back',                      #   ...at the first end: nothing to undo
        'No',                        # so step 4 asks again, answered No
        'No', 'No',                  # steps 5, 6
        ents, 'None'])
out = said(vm)
check("Back at the first item of a loop says so",
      "Already at the first wall" in out)
check("...and re-opens the question that started the loop",
      out.count("Step 4 of 7") >= 2)
check("...leaving nothing declared", "straight wall(s) noted" not in out)


# -------------------------------------------------- 5. CABHD walks back

print("\nCABHD: the same chain, one step longer")

vm = newvm(('cabhd', 'CABHD.lsp'))
layer(vm, 'POINTS')
layer(vm, 'POOL', 4)
ents = survey(vm, RING)
vm.run('c:CABHD',
       [None,                       # the pickfirst probe
        None,                       # step 1  tolerance     Enter
        30,                         # step 2  percent
        'Back',                     # step 3  cap     -> step 2
        None,                       # step 2  percent       Enter
        'U',                        # step 3  cap     -> step 2   (synonym)
        None,                       # step 2  percent       Enter
        None,                       # step 3  cap           Enter
        'B',                        # step 4  walls   -> step 3   (short form)
        None,                       # step 3  cap           Enter
        'No',                       # step 4  walls
        'Back',                     # step 5  corners -> step 4
        'No', 'No', 'No',           # steps 4, 5, 6
        ents, None, 'None'])        # selection, cutoff, keep nothing
out = said(vm)
check("Back at step 3 re-asks step 2", out.count("Step 2 of 8") >= 3)
check("B and U are both taken as Back",
      out.count("Step 3 of 8") >= 3 and out.count("Step 4 of 8") >= 2)
check("the chain says which way it moved", "Stepping back one question" in out)


# ---------------------------------------------------- 6. LHD walks back

print("\nLHD: one declaration loop, one history to walk back")

vm = newvm(('lhd', 'lhd.lsp'))
layer(vm, 'POINTS')
layer(vm, 'POOL', 4)
plain_points(vm, [(0.0, 0.0), (60.0, 0.0), (60.0, 40.0), (0.0, 40.0)])
vm.run('c:LHD',
       [None,                       # the pickfirst probe
        1.0,                        # step 1  tolerance
        20,                         # step 2  percent
        'Back',                     # step 3  cap      -> step 2
        None,                       # step 2  percent        Enter
        'U',                        # step 3  cap      -> step 2   (synonym)
        None,                       # step 2  percent        Enter
        None,                       # step 3  cap            Enter
        'B',                        # step 4  shape    -> step 3   (short form)
        None,                       # step 3  cap            Enter
        'Open',                     # step 4  shape
        'Back',                     # step 5  declarations -> step 4
        'Open',                     # step 4  shape
        'Corner', (0.0, 0.0),       # step 5  declare a corner
        'Back',                     #         ...and take it back
        'Back',                     #         nothing left: -> step 4
        'Open',                     # step 4  shape
        'Done',                     # step 5  nothing to declare
        None])                      # step 6  selection
out = said(vm)
check("Back at step 3 re-asks step 2", out.count("Step 2 of 6") >= 3)
check("B and U are both taken as Back",
      out.count("Step 3 of 6") >= 3 and out.count("Step 4 of 6") >= 3)
check("Back in the one declaration loop names what it took back",
      "Stepping back one corner" in out)
check("...and at the first declaration says so",
      "Already at the first declaration" in out)
check("...then re-opens the question before the loop",
      out.count("Step 4 of 6") >= 3)
check("nothing ends up declared", "corner(s) and" not in out)


# ------------------------------------------ 7. CORNERSTP's option chain

print("\nCORNERSTP: the options, and the questions this run never asked")

vm = newvm(('cornerstp', 'CORNERSTP.lsp'))
vm.loads('(entmake (list (cons 0 "LINE")'
         ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
vm.loads('(entmake (list (cons 0 "LINE")'
         ' (list 10 0.0 0.0 0.0) (list 11 0.0 200.0 0.0)))')
walls = list(vm.entities)
vm.run('c:CORNERSTP',
       [None, walls,                 # pickfirst probe, then the selection
        None,                        # direction: Enter = Inside
        'Back',                      # dims -> back past two unasked questions
        'Outside',                   # direction again
        'B',                         # dims -> back            (short form)
        None,                        # direction: Inside
        'No',                        # dims
        'Back',                      # bench -> back to dims
        'No',                        # dims
        'No',                        # bench
        24.0, None, None,            # one tread, then Enter to stop
        'No'])                       # side profile? (AUTOBEAD is not
                                     # loaded here, so no bead question)
out = said(vm)
asked = [p for p, _v in vm.prompts if 'inside out' in p]
check("Back at the dims question re-asks the direction", len(asked) == 3)
check("...stepping straight over the two this run never put",
      "Measure step treads" not in out and "parallel to the diagonal" not in out)
check("B and Back are the same answer there", out.count("Stepping back one question") == 3)
check("Back at the bench question re-asks the dims",
      len([p for p, _v in vm.prompts if 'Dimension the steps' in p]) == 4)


# ------------------------------------- 8. POOL and SPA: shape and base

print("\nPOOL / SPA: the three questions in front of every measurement")

for tool, cmd, rel, lead, shape, first in (
        ("POOL", 'c:POOL', ('pool', 'POOL.LSP'), [],
         'Rectangle', 'in-square or out-of-square'),
        ("SPA", 'c:SPA', ('spa', 'SPA.LSP'), [None],
         'Rectangle', "water's edge or the cover size")):
    vm = newvm(rel)
    try:
        vm.run(cmd, lead + [
            'Watersedge' if tool == 'SPA' else 'Insquare',
            'Back',                       # shape -> the question before it
            'Coversize' if tool == 'SPA' else 'Outofsquare',
            shape,
            'B',                          # base point -> shape (short form)
            shape,
            (0.0, 0.0)] + [None] * 90)
    except Exception:
        pass                              # the measurements run out; the
                                          # questions under test are done
    out = said(vm)
    firsts = [p for p, _v in vm.prompts if first in p]
    shapes = [p for p, _v in vm.prompts if 'shape [' in p]
    check("%s: Back at the shape re-asks the question before it" % tool,
          len(firsts) == 2, "%d asked" % len(firsts))
    check("%s: B at the base point re-asks the shape" % tool,
          len(shapes) == 3, "%d asked" % len(shapes))
    check("%s: and it says which way it moved" % tool,
          "Stepping back one question" in out)


# ------------------------------ 9. NORMIESTEP's corner-treatment sizes

print("\nNORMIESTEP: the size only means something beside the treatment")

def normiestep(treatment):
    """One NORMIESTEP run off a square corner, with TREATMENT answering
    the corner question and whatever follows it."""
    vm = newvm(('cornerstp', 'NORMIESTEP.lsp'))
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 200.0 0.0 0.0)))')
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 0.0 200.0 0.0)))')
    vm.run('c:NORMIESTEP',
           [None, list(vm.entities), (100.0, 0.0), 60.0]
           + list(treatment)
           + ["No", 12.0, 12.0, None, "No"])
    return vm

vm = normiestep(("Radius", "Back", "Cut", "Offset", 6.0))
out = said(vm)
treats = [p for p, _v in vm.prompts if "treated?" in p]
check("Back at the radius re-asks how the corners are treated",
      len(treats) == 2, "%d asked" % len(treats))
check("...and the answer that replaces it is the one that runs",
      any("Offset back along each line" in p for p, _v in vm.prompts))
check("...saying which way it moved", "Stepping back one question" in out)

vm = normiestep(("Cut", "Back", "Radius", 9.0))
treats = [p for p, _v in vm.prompts if "treated?" in p]
check("Back at the Offset/Cut question re-asks the treatment too",
      len(treats) == 2, "%d asked" % len(treats))
check("...and a Radius answer then asks for a radius",
      any("Radius for" in p for p, _v in vm.prompts))


# ------------------------------------ 10. AUTOBEAD and POOLSIDE

print("\nAUTOBEAD: the clicked steps are a list, so Back pops one")

vm = newvm(('autobead', 'AUTOBEAD.lsp'))
layer(vm, 'POOL', 4)
vm.loads('(entmake (list \'(0 . "LINE") \'(8 . "POOL")'
         ' (list 10 0.0 0.0 0.0) (list 11 96.0 0.0 0.0)))')
wall = vm.entities[-1]
vm.run('c:AUTOBEAD',
       [None, [wall], (0.0, 24.0, 0.0), "Some",
        (0.0, 12.0, 0.0),            # click one step
        'Back',                      # ...take it back
        'Back',                      # ...nothing left: re-open the question
        "All"])
out = said(vm)
check("Back pops the step clicked last", "Stepping back one step" in out)
check("...and off the first it says so", "Already at the first step" in out)
check("...then re-asks which steps have beaded side walls",
      len([p for p, _v in vm.prompts if "beaded side walls" in p]) == 2)

print("\nPOOLSIDE: the bottom type and the base point")

vm = newvm(('poolside', 'POOLSIDE.lsp'))
try:
    vm.run('c:POOLSIDE',
           ['Normal', 'Back', 'Normal', 'U', 'Normal', (0.0, 0.0)]
           + [None] * 60)
except Exception:
    pass                              # the measurements run out past here
types = [p for p, _v in vm.prompts if "Bottom type" in p]
check("Back at the base point re-asks the bottom type",
      len(types) == 3, "%d asked" % len(types))
check("...and U is the same answer as Back there",
      said(vm).count("Stepping back one question") == 2)


# ------------------------------- 11. ABCURCHECK and BPCALLOUT

print("\nABCURCHECK: the declarations are a list too")

vm = newvm(('abcurcheck', 'ABCURCHECK.lsp'))
declared = vm.loads("(setq acc-test-declared nil)")
vm.script = ['Add', (10.0, 10.0), 'Back', 'Back', 'Keep']
vm.loads("(setq acc-test-out (acc:declare-loop nil))")
out = said(vm)
check("Back takes back the discontinuity just declared",
      "Stepping back one discontinuity" in out)
check("...and off the first it re-opens Add/Remove/Keep",
      "Already at the first discontinuity" in out)
check("...leaving nothing declared",
      vm.get(__import__('lispvm').Sym('acc-test-out')) in ([], None, False)
      or not vm.get(__import__('lispvm').Sym('acc-test-out')))

print("\nBPCALLOUT: Back at the text re-opens the picking")

vm = newvm(('bpcallout', 'BPCALLOUT.lsp'))
for x, num in ((0.0, 1), (10.0, 2)):
    vm.loads('(entmake (list \'(0 . "INSERT") \'(8 . "POINTS")'
             ' \'(2 . "ab_pt") (list 10 %r 0.0 0.0)))' % x)
    vm.loads('(entmake (list \'(0 . "ATTRIB") \'(2 . "number")'
             ' (cons 1 "%d")))' % num)
vm.run('c:BPCALLOUT',
       [(0.0, 0.0), None,            # ring one point, then Enter
        'Back',                      # ...at the text: back to the picking
        (10.0, 0.0), None,           # ring the other one too
        (50.0, 50.0)])               # place the text
out = said(vm)
check("Back at the text placement goes back to the picking",
      "Stepping back to the picking" in out)
check("...and the rings already made are still there",
      "2 point(s) ringed" in out, out[-120:])


# ------------------------------------------------------------------ done

print()
if FAILS:
    print("FAILED: " + "; ".join(FAILS))
    sys.exit(1)
print("ALL BACK-NAVIGATION CHECKS PASSED")
