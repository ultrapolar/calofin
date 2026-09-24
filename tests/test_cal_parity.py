#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every helper the mirror replaces with a cal: one must ANSWER the same.

CLAUDE.md names this bug class outright: "a cal: helper that subtly
differs from the standalone helper it replaced".  It is not
hypothetical -- shared/parts/SPA.lsp once sat two revisions behind while
every one-file check stayed green, and the grouped build drew loose
lines where the standalone one drew a bounded polyline.

check_standards.py compares version banners, which catches a twin left
behind.  Nothing compared the two helpers' BEHAVIOUR.  That is the gap
here: tools/mirror_shared.py's swap maps say "abp:v+ becomes cal:v+" in
57 tools, and until this file nothing ever called both with the same
arguments and looked at the two answers.  It matters most where the
leverage is highest -- a drift in cal:v+ would reach 18 tools at once,
and one in cal:ensure-layer 29.

The roster is computed, never typed: it comes from mirror_shared.TOOLS
itself, so a swap added tomorrow is checked the day it lands.  A swap
whose target has no inputs here FAILS rather than being skipped
quietly; to excuse one, name it in SKIP with a reason.

The tier makes no difference here and the suite says so: the two
files it reads are always lisp/<tool> and shared/parts/CALOFIN-LIB.lsp,
because "the local helper and the cal: one that replaces it" is only a
question at the standalone tier -- at the grouped tier the local is
already gone, by construction.

Run: python3 tests/test_cal_parity.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_cal_parity.py
"""

import ast
import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

import mirror_shared  # noqa: E402
from lispvm import VM, LispError  # noqa: E402

LIB = os.path.join(REPO_DIR, "shared", "parts", "CALOFIN-LIB.lsp")

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


#: Arguments to call both halves of a swap with, as AutoLISP source.
#: Several sets each where an edge case is worth pinning -- a negative
#: angle, a wrapped one, a zero-length vector, an empty string.
INPUTS = {
    # feet and inches whatever DIMZIN says: a whole foot, a sub-foot
    # length, decimal inches, a negative, one that rounds to nothing,
    # a carry into the next foot, the 47.8 cap, precision 0 and 8
    "cal:ftin": ["180.0 4 4", "6.5 4 4", "180.5 3 2", "-12.5 4 4",
                 "-0.01 4 4", "0.01 4 4", "95.9999 4 4", "47.8 4 4",
                 "1.0 4 0", "15.0 3 0", "0.3333 4 8", "147.5 4 12"],
    # a shown limit, at the VM's LUNITS/LUPREC: a cap that rounds up,
    # one already on the step, and a minimum just past one
    "cal:floor-shown": ["47.8", "48.0", "0.0", "-2.5", "3.00009"],
    "cal:ceil-shown": ["3.01", "48.0", "0.0", "-2.5", "3.00001"],
    # a shop term: nothing in the profile, a spelling of the shop's
    # (set by the argument itself, so both halves read the same
    # profile), and an empty one that falls back to the shipped text
    "cal:term": ['"typ-note" " Typ."', '"never-set" "Not Given"',
                 '(progn (setenv "CalofinTerm-par" " TYP") "par") " Typ."',
                 '(progn (setenv "CalofinTerm-par" "") "par") " Typ."'],
    "cal:2d": ["'(1.5 2.5 3.5)", "'(0.0 0.0 0.0)", "'(-4.0 7.25)"],
    "cal:andjoin": ['\'("a" "b" "c") "and"', '\'("only") "and"',
                    '\'("a" "b") "or"', "nil \"and\""],
    "cal:ang-diff": ["0.1 0.2", "6.2 0.1", "0.0 3.14159265",
                     "-0.5 0.5", "3.0 -3.0"],
    "cal:angnorm": ["0.5", "-0.5", "7.0", "-7.0", "0.0", "6.283185307"],
    "cal:axis-pt": ["'(1.0 2.0) '(1.0 0.0) 3.0",
                    "'(0.0 0.0) '(0.0 1.0) -2.5"],
    "cal:back-word-p": ['"Back"', '"back"', '"B"', '"Next"', '""'],
    # the length ruler: the reader, the speller and the row geometry are
    # pure; what draws, erases or asks is excused below and driven by
    # every caller's suite at both tiers
    "cal:len-digit-p": ['"0"', '"9"', '"a"', '"."', '" "'],
    "cal:len-num-p": ['"44"', '"44.5"', '".5"', '"4."', '"4.4.4"', '"4a"',
                      '""', '"."'],
    "cal:len-split": ['"4 1/2"', '"4-1/2"', '"  4\t1/2  "', '"Back Undo Max"',
                      '""', '"--"'],
    "cal:len-token": ['"4"', '"4.5"', '"1/2"', '"3/8"', '"1/0"', '"a/2"',
                      '"x"', '""'],
    "cal:len-inches": ['"4"', '"4 1/2"', '"4-1/2"', '"1/2"', '"4.5"', '""',
                       '"4 x"'],
    "cal:parse-len": ['"44"', '"44.5"', '"44 1/2"', '"44-1/2"', "\"4'4.5\"",
                      "\"4'-4 1/2\\\"\"", "\"4'\"", '"52.5\\""', "\"3''\"",
                      '"44.3"', '"abc"', '""', '"-5"', '"0"',
                      "\"1'4-1/2\\\"\""],
    "cal:len-eighths": ['44.0', '44.3', '44.4375', '0.06', '0.0', '10.5'],
    "cal:spell-len": ['352 nil nil', '356 nil nil', '356 nil t', '356 t nil',
                      '356 t t', '96 t nil', '96 nil t', '1 nil t', '2 t t'],
    "cal:len-unread": ['"abc"', '"Max"', '""'],
    "cal:ruler-tier": ['0', '1', '2', '3', '4', '5', '6', '7', '8', '-4',
                       '16', '-3'],
    "cal:ruler-rows": ['352 nil', '352 t', '4 nil', '20 t', '1 nil'],
    # the ladder half: a rung on a foot, a half foot, a quarter foot and
    # none of the three, then the shapes a mistyped knob comes in as --
    # a string, two numbers, a zero step, a negative step, a list of
    # strings, nil -- each of which has to come back with no rungs
    "cal:ladder-tier": ['96', '192', '48', '144', '24', '72', '30', '1',
                        '0'],
    "cal:ladder-rows": ["'(3.0 24.0 3.0)", "'(6.0 36.0 6.0)",
                        "'(6.0 12.0 1.0)", "'(48.0 144.0 12.0)",
                        "'(0.0 12.0 6.0)", "'(3.0 3.0 3.0)",
                        "'(24.0 3.0 3.0)", '"3 to 24"', "'(3.0 24.0)",
                        "'(3.0 24.0 0.0)", "'(3.0 24.0 -3.0)",
                        '\'("a" "b" "c")', 'nil'],
    "cal:ruler-val-lt": ["'(1 a) '(2 b)", "'(2 a) '(1 b)", "'(3 a) '(3 b)"],
    "cal:ruler-view": [''],
    "cal:ruler-dir": ['0.88', '0.12', '0.5', '0.51'],
    "cal:ruler-hgt": ["'jump 4.2 0.5", "'half 4.2 0.5", "'quarter 4.2 0.5",
                      "'eighth 4.2 0.5", "'current 4.2 0.5", "'jump 10.0 0.3"],
    "cal:ruler-tick": ["'jump 4.2 0.6", "'half 4.2 0.6", "'quarter 4.2 0.6",
                       "'eighth 4.2 0.6", "'current 4.2 0.6", "'jump 10.0 0.4"],
    "cal:ruler-hit": ["'(5.0 1.0) '(4.0 6.0 0.5) '((80 0.0) (81 1.0) (82 2.0))",
                      "'(5.0 1.3) '(4.0 6.0 0.5) '((80 0.0) (81 1.0) (82 2.0))",
                      "'(7.0 1.0) '(4.0 6.0 0.5) '((80 0.0) (81 1.0) (82 2.0))",
                      "'(5.0 3.0) '(4.0 6.0 0.5) '((80 0.0) (81 1.0) (82 2.0))",
                      "'(5.0 1.0) nil nil"],
    "cal:ruler-new": ['"L" \'(3 7 0.88 0.042 0.5 0.6 0.26 6.0)'],
    "cal:as-number": ['"17"', '"Pt.17"', '"pt 17"', '"#17"', '"017"',
                      '"40.5"', '"PT.40.5"', '"P"', '""'],
    "cal:canon": ['"17"', '"Pt.17"', '"pt 17"', '"#17"', '"017"',
                  '"40.5"', '"17m"', '""'],
    "cal:cand-matches": [
        '"pt 3" (list (list (list 0.0 0.0) "3") (list (list 1.0 1.0) "03")'
        ' (list (list 2.0 2.0) "4"))',
        '"9" (list (list (list 0.0 0.0) "3"))', '"3" nil'],
    "cal:cand-nearest": [
        '(list 1.0 1.0 0.0) (list (list (list 0.0 0.0) "3")'
        ' (list (list 20.0 20.0) "4")) 12.0',
        '(list 50.0 50.0) (list (list (list 0.0 0.0) "3")) 12.0',
        '(list 5.0 0.0) (list (list (list 0.0 0.0) "3")'
        ' (list (list 8.0 0.0) "4")) 12.0'],
    "cal:ceil": ["1.0", "1.2", "-1.2", "0.0", "5.99"],
    "cal:loop-area": ["'((0.0 0.0) (120.0 0.0) (120.0 60.0) (0.0 60.0))", "'((0.0 0.0) (0.0 60.0) (120.0 60.0) (120.0 0.0))",
                      "'((0.0 0.0) (4.0 0.0) (0.0 3.0))",
                      "'((0.0 0.0) (1.0 1.0) (2.0 2.0))"],
    "cal:inward-sign": ["'((0.0 0.0) (120.0 0.0) (120.0 60.0) (0.0 60.0))", "'((0.0 0.0) (0.0 60.0) (120.0 60.0) (120.0 0.0))", "'((0.0 0.0) (120.0 0.0) (120.0 40.0) (40.0 40.0) (40.0 120.0) (0.0 120.0))",
                        "'((0.0 0.0) (1.0 1.0) (2.0 2.0))",
                        "'((0.0 0.0) (1.0 1.0))"],
    "cal:in-loop-p": ["(list 60.0 30.0) '((0.0 0.0) (120.0 0.0) (120.0 60.0) (0.0 60.0))",
                      "(list 200.0 30.0) '((0.0 0.0) (120.0 0.0) (120.0 60.0) (0.0 60.0))",
                      "(list 60.0 -5.0) '((0.0 0.0) (120.0 0.0) (120.0 60.0) (0.0 60.0))",
                      "(list 20.0 100.0) '((0.0 0.0) (120.0 0.0) (120.0 40.0) (40.0 40.0) (40.0 120.0) (0.0 120.0))",
                      "(list 100.0 100.0) '((0.0 0.0) (120.0 0.0) (120.0 40.0) (40.0 40.0) (40.0 120.0) (0.0 120.0))"],
    "cal:spikes": ["'((0.0 . 40.0) (12.0 . 10.0) (24.0 . 30.0)) 2.0",
                   "'((0.0 . 40.0) (12.0 . 38.0) (24.0 . 30.0)) 2.0",
                   "'((0.0 . 40.0) (12.0 . 42.0) (24.0 . 30.0)) 2.0",
                   "'((0.0 . 10.0) (12.0 . 40.0) (24.0 . 12.0)) 2.0",
                   "'((0.0 . 40.0) (12.0 . 10.0) (24.0 . 30.0)"
                   " (36.0 . 90.0) (48.0 . 32.0)) 2.0",
                   "'((0.0 . 40.0) (12.0 . 10.0)) 2.0",
                   "nil 2.0"],
    "cal:circumcenter": ["'(0.0 0.0) '(4.0 0.0) '(0.0 4.0)",
                         "'(1.0 1.0) '(3.0 1.0) '(2.0 4.0)",
                         "'(0.0 0.0) '(1.0 1.0) '(2.0 2.0)"],
    "cal:cross": ["'(1.0 0.0) '(0.0 1.0)", "'(2.0 3.0) '(4.0 5.0)",
                  "'(1.0 1.0) '(2.0 2.0)"],
    "cal:d2": ["'(0.0 0.0) '(3.0 4.0)", "'(1.0 1.0) '(1.0 1.0)"],
    "cal:dist": ["'(0.0 0.0) '(3.0 4.0)", "'(1.0 2.0 3.0) '(4.0 6.0 3.0)"],
    "cal:dot": ["'(1.0 2.0) '(3.0 4.0)", "'(1.0 0.0) '(0.0 1.0)"],
    "cal:dotn": ["'(1.0 2.0 3.0) '(4.0 5.0 6.0)",
                 "'(1.0 0.0 0.0) '(0.0 1.0 0.0)"],
    "cal:kvhas": ['"a=1;b=2" "b"', '"a=1" "z"', '"" "a"'],
    "cal:kvpack": ['\'(("a" . "1") ("b" . "2"))', "nil"],
    "cal:kvsplit": ['"a;b;c" ";"', '"a" ";"', '"" ";"'],
    "cal:kvunpack": ['"a=1;b=2"', '""'],
    "cal:mid": ["'(0.0 0.0) '(4.0 6.0)", "'(-2.0 -2.0) '(2.0 2.0)"],
    "cal:midn": ["'(0.0 0.0 0.0) '(4.0 6.0 8.0)"],
    "cal:nthcdr": ["0 '(1 2 3)", "2 '(1 2 3)", "5 '(1 2 3)", "1 nil"],
    "cal:pad": ['"ab" 5', '"abcdef" 3', '"" 2', '"x" 0'],
    "cal:perp": ["'(1.0 0.0)", "'(0.0 1.0)", "'(3.0 4.0)"],
    "cal:plural": ['1 "pad" "pads"', '0 "pad" "pads"', '2 "pad" "pads"'],
    "cal:proj-param": ["'(2.0 2.0) '(0.0 0.0) '(1.0 0.0)",
                       "'(-1.0 5.0) '(0.0 0.0) '(0.0 1.0)"],
    "cal:pt-line-dist": ["'(0.0 3.0) '(0.0 0.0) '(1.0 0.0)",
                         "'(2.0 0.0) '(0.0 0.0) '(1.0 0.0)"],
    "cal:signed-dang": ["0.0 1.0", "1.0 0.0", "0.1 6.2", "6.2 0.1"],
    "cal:sublist": ["'(1 2 3 4 5) 1 2", "'(1 2 3) 0 3", "'(1 2 3) 2 9"],
    "cal:tan": ["0.0", "0.5", "-0.5", "1.0"],
    "cal:trim": ['"  ab  "', '"ab"', '""', '"   "'],
    "cal:unit": ["'(3.0 4.0)", "'(0.0 0.0)", "'(-3.0 0.0)"],
    "cal:unitn": ["'(3.0 4.0 0.0)", "'(0.0 0.0 0.0)"],
    "cal:v*": ["'(1.0 2.0) 3.0", "'(1.0 2.0) 0.0", "'(1.0 2.0) -1.5"],
    "cal:v+": ["'(1.0 2.0) '(3.0 4.0)", "'(0.0 0.0) '(0.0 0.0)"],
    "cal:v-": ["'(1.0 2.0) '(3.0 4.0)", "'(5.0 5.0) '(5.0 5.0)"],
    "cal:vlen": ["'(3.0 4.0)", "'(0.0 0.0)"],
    "cal:zeropad2": ["1", "9", "10", "0", "99"],
    "cal:imgtexth": ["1.0", "2.5"],
    "cal:imgtextw": ['"AB" 1.0', '"" 1.0'],
    "cal:imgglyph": ['"A"', '"0"', '" "'],
    "cal:formanswer": ['"12"', '""', "nil"],
    # The ink table.  Its other input is the THEME, which travels in
    # the profile rather than in an argument, so each case sets it in
    # the first slot: a progn that writes CalofinTheme and then hands
    # over the knob.  Both halves of the pair evaluate their own copy
    # of that, so each sees the same profile -- and eleven tools carry
    # a copy of this body, which is exactly the kind of duplication
    # this file exists to hold together.  The last case leaves the
    # override cleared for whatever runs next.
    "cal:ink": [
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'fade',
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'guide',
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'dim',
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'hi',
        '(progn (setenv "CalofinTheme" "dark") \'auto) \'nosuchrole',
        '(progn (setenv "CalofinTheme" "light") \'auto) \'fade',
        '(progn (setenv "CalofinTheme" "light") \'auto) \'guide',
        '(progn (setenv "CalofinTheme" "light") \'auto) \'dim',
        '(progn (setenv "CalofinTheme" "light") \'auto) \'hi',
        # a number is that number, whatever the theme says
        '(progn (setenv "CalofinTheme" "dark") 8) \'fade',
        '(progn (setenv "CalofinTheme" "light") 5) \'hi',
        # and with nothing measurable and no override, today's numbers
        '(progn (setenv "CalofinTheme" "") \'auto) \'fade',
        '(progn (setenv "CalofinTheme" "") \'auto) \'guide',
        '(progn (setenv "CalofinTheme" "") \'auto) \'dim',
        '(progn (setenv "CalofinTheme" "") \'auto) \'hi',
    ],
    # cal:inkoverride reads a profile key that travels via setenv, the
    # same trick cal:ink's own theme cases above use -- each case sets
    # its own CalofinInk-<ROLE> and hands over the role.  'olap is
    # never given a key, so both halves answer nil for it; the last two
    # cases clear the keys they touched for whatever runs next.
    "cal:inkoverride": [
        '(progn (setenv "CalofinInk-FLAG" "42") \'flag)',
        '(progn (setenv "CalofinInk-ARC" "7") \'arc)',
        "'olap",
        '(progn (setenv "CalofinInk-FLAG" "") \'flag)',
        '(progn (setenv "CalofinInk-ARC" "") \'arc)',
    ],
}

#: Swaps this file does not call, and why.  Every one needs something a
#: bare VM has not got -- a drawing, a prompt queue, or the session
#: state the command around it sets up -- and each is covered where that
#: context exists (test_calofin_lib.py, and the tool's own suite at both
#: tiers, which is what `make parity` is).
SKIP = {
    "cal:ui": "takes no arguments, so the theme it reads cannot be set\n              up from one; tests/test_theme.py drives both copies\n              through every theme instead",
    "cal:askkw": "asks; driven by every form suite at both tiers",
    "cal:askyn": "asks",
    "cal:askstr": "asks",
    "cal:askdist": "asks",
    "cal:asktreat": "asks",
    "cal:ask-yn": "asks",
    "cal:ask-yn-nav": "asks",
    "cal:pause": "asks",
    "cal:askpoint": "asks",
    "cal:syssave": "session state, and the mirror expands its arity",
    "cal:sysrestore": "session state",
    "cal:dimstysave": "session state",
    "cal:dimstyrestore": "session state",
    "cal:undobegin": "session state",
    "cal:undoend": "session state",
    "cal:osup": "session state",
    "cal:osdown": "session state",
    "cal:datestr": "reads CDATE, not a pure function of its arguments",
    "cal:shown-step": "takes no arguments and reads LUNITS/LUPREC; its\n              answer is compared through floor-shown and ceil-shown",
    "cal:ensure-layer": "writes the layer table; needs a drawing",
    "cal:layer-usable-p": "reads the layer table; needs a drawing",
    "cal:bbox-ent": "needs an entity",
    "cal:bbox-ss": "needs a selection set",
    "cal:block-number": "needs a block insert, and the mirror widens it",
    "cal:mtext": "draws",
    "cal:text": "draws",
    "cal:imgtext": "draws into a dialog image tile",
    "cal:imgpline": "draws into a dialog image tile",
    "cal:imgflatten": "takes a chart element, not a plain value",
    "cal:imgarcpts": "takes a chart element, not a plain value",
    "cal:error-cancel-p": "reads the error message a handler was given",
    "cal:dedupe": "the mirror widens it with a tolerance argument",
    "cal:ruler-line": "draws",
    "cal:ruler-ring": "draws",
    "cal:ruler-label": "draws",
    "cal:draw-ruler": "draws; tests/test_ruler_copies.py holds the copies to the\n              library text, and every caller's suite clicks the rows",
    "cal:ruler-off": "erases entities; needs a drawing",
    "cal:ruler-show": "draws",
    "cal:ask-len": "asks",
}


def arities(src):
    return {m.group(1).lower(): len(m.group(2).split("/")[0].split())
            for m in re.finditer(r"^\(defun\s+([^\s()]+)\s*\(([^)]*)\)",
                                 src, re.M)}


LIB_SRC = open(LIB, encoding="utf-8", errors="replace").read()
LIB_ARITY = arities(LIB_SRC)

#: (tool, local, cal) for every swap whose local really is a defun in
#: the file the mirror reads it from.  A satellite (TUTORIALSPA and the
#: like) swaps a helper that lives in its sibling, so there is nothing
#: in ITS file to compare against; the sibling's own entry covers it.
PAIRS = []
for _tool in sorted(mirror_shared.TOOLS):
    _d = mirror_shared.TOOLS[_tool]
    _sw = _d.get("swap")
    if not _sw:
        continue
    if isinstance(_sw, str):
        _sw = ast.literal_eval(_sw)
    _p = os.path.join(REPO_DIR, _d["src"])
    if not os.path.isfile(_p):
        continue
    _src = open(_p, encoding="utf-8", errors="replace").read()
    _ta = arities(_src)
    for _local, _cal in sorted(_sw.items()):
        if _local.lower() in _ta and _cal.lower() in LIB_ARITY:
            PAIRS.append((_tool, _d["src"], _local, _cal.lower(),
                          _ta[_local.lower()], LIB_ARITY[_cal.lower()]))

targets = sorted({c for _, _, _, c, _, _ in PAIRS})
print(f"{len(PAIRS)} swap pair(s) over {len(targets)} cal: helper(s)")

unplanned = [c for c in targets if c not in INPUTS and c not in SKIP]
check("every swapped cal: helper is either called here or excused",
      not unplanned,
      "no inputs and no SKIP entry: " + ", ".join(unplanned))

# One VM per source file: the tool's own helpers and the library's, side
# by side.  They cannot collide -- check_standards proves only
# CALOFIN-LIB defines cal: symbols -- so both halves of every swap in
# that file answer in the same session.
_vms = {}


def vm_for(src):
    """The tool's STANDALONE source and the library, side by side.

    Both are read and evaluated directly rather than through vm.load,
    which is what CALOFIN_LISP_ROOT remaps: at the grouped tier that
    remap would hand back the twin, where the local helper has already
    been replaced by the cal: one -- there would be nothing left to
    compare, and the run would die on the local's own name.  This
    comparison only ever means one thing, standalone against library,
    so it reads the same two files whichever tier the suite is run at.
    """
    if src not in _vms:
        vm = VM()
        with open(os.path.join(REPO_DIR, src), encoding="utf-8",
                  errors="replace") as fh:
            vm.loads(fh.read())
        with open(LIB, encoding="utf-8", errors="replace") as fh:
            vm.loads(fh.read())
        _vms[src] = vm
    return _vms[src]


def call(vm, fn, args, n):
    """(fn args...) evaluated, or the error it raised, as a comparable
    value.  An error on one side and an answer on the other is exactly
    the drift worth reporting, so both come back."""
    try:
        vm.loads(f"(setq test:*r* ({fn} {args}))")
        return ("ok", vm.globals.get("test:*r*"))
    except LispError as e:
        return ("err", str(e).split("\n")[0])
    except RecursionError:
        return ("err", "recursion")


def same(a, b):
    """Equal, with floats compared to the precision drafting cares
    about -- 1e-9 of an inch is not a difference, and a helper that
    reassociates its arithmetic would otherwise fail on the last bit."""
    if type(a) is not type(b) and not (isinstance(a, (int, float))
                                       and isinstance(b, (int, float))):
        return False
    if isinstance(a, float) or isinstance(b, float):
        return abs(float(a) - float(b)) < 1e-9
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


tested = skipped = 0
drift = []
for tool, src, local, cal, la, ca in PAIRS:
    if cal in SKIP:
        skipped += 1
        continue
    if cal not in INPUTS:
        continue
    if la != ca:
        drift.append(f"{tool}: {local} takes {la} arg(s) but {cal} takes "
                     f"{ca} -- the mirror must widen the call, and no "
                     f"expand rule covers it")
        continue
    vm = vm_for(src)
    for args in INPUTS[cal]:
        want = call(vm, cal, args, ca)
        got = call(vm, local, args, la)
        tested += 1
        if want[0] != got[0] or (want[0] == "ok" and not same(got[1], want[1])):
            drift.append(f"{tool}: ({local} {args}) -> {got[1]!r} but "
                         f"({cal} {args}) -> {want[1]!r}")

check(f"all {tested} call(s) agree across {len(PAIRS) - skipped} "
      f"compared pair(s)", not drift,
      "\n         ".join(drift[:12]))
print(f"  ({skipped} pair(s) excused by SKIP, {len(_vms)} source file(s) "
      f"loaded beside the library)")

# ---------------------------------------------------- the ones that ask
# A helper that prompts cannot be called here -- there is no drafter to
# answer it -- so SKIP excuses it from the calls above.  That left the
# ask helpers with no parity at all, and they are the ones a UCS fix
# lands in: pf:askpoint and its four siblings took the click to World,
# cal:askpoint did not, and a regeneration would have shipped the bug in
# LAZPASS.lsp while every twin check stayed green.  So each asking pair
# is held to the library's TEXT instead: the same forms once the
# prefix, the Back sentinel, comments, case and the LAZDIAG hooks are
# set aside.  A tool whose askkw takes the HIDDEN keyword list third
# (the mirror's askkw_hidden, which rewrites its call sites) is the one
# shape that differs on purpose, and is excused by that flag.

def _defun_text(src, name):
    m = re.search(r"^\(defun\s+%s\s*\(" % re.escape(name), src, re.M | re.I)
    if not m:
        return None
    depth, i, n, instr = 0, m.start(), len(src), False
    while i < n:
        c = src[i]
        if instr:
            if c == "\\":
                i += 1
            elif c == '"':
                instr = False
        elif c == '"':
            instr = True
        elif c == ";":
            while i < n and src[i] != "\n":
                i += 1
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return src[m.start():i + 1]
        i += 1
    return None


def _norm(text, pfx):
    """The forms, with what legitimately differs between copies taken
    out: comments, the LAZDIAG hooks, the Back sentinel's name, the
    helper prefix, and the case of anything outside a string."""
    parts = re.split(r'("(?:[^"\\]|\\.)*")', text)
    out = []
    for k, part in enumerate(parts):
        if k % 2:
            out.append(part)
            continue
        part = re.sub(r";[^\n]*", "", part)
        part = re.sub(r"'[A-Za-z]+-BACK\b", "'X-BACK", part)
        part = re.sub(r"(?<![\w:*-])" + re.escape(pfx) + r"(?=[\w*-])",
                      "X:", part, flags=re.I)
        out.append(part.lower())
    t = "".join(out)
    t = re.sub(r"\(if lzd:ask \(lzd:ask .*? (\S+)\) \1\)", "", t)
    return " ".join(t.split())


asked = excused = 0
text_drift = []
for tool, src, local, cal, la, ca in PAIRS:
    if SKIP.get(cal, "").split(";")[0] != "asks":
        continue
    d = mirror_shared.TOOLS[tool]
    if d.get("askkw_hidden") and re.search(r"askkw|askyn", cal):
        excused += 1
        continue
    tsrc = open(os.path.join(REPO_DIR, src), encoding="utf-8",
                errors="replace").read()
    lt, ct = _defun_text(tsrc, local), _defun_text(LIB_SRC, cal)
    if not lt or not ct:
        continue
    lp = re.match(r"[^:-]+[:-]", local).group(0)
    asked += 1
    if _norm(lt, lp) != _norm(ct, "cal:"):
        text_drift.append(f"{tool}: {local} does not read as {cal} -- "
                          f"change both, or neither")

check(f"all {asked} asking pair(s) read as the library's text "
      f"({excused} hidden-keyword askkw/askyn excused)", not text_drift,
      "\n         ".join(text_drift[:12]))

if failures:
    print(f"\n{len(failures)} cal: parity check(s) FAILED")
    sys.exit(1)
print("\nall cal: parity checks passed")
