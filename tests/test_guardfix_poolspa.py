#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The guard-fix wave for POOL, POOLSIDE, SPA, OASIS and SPACOVCREATE.

Three kinds of quiet wrong answer, each found by one of the new guards
(tools/check_values.py, tools/check_offered.py) and each shown here
failing on the code before the fix:

* FEET-INCH TEXT THAT FOLLOWS DIMZIN.  POOL's report table (TARGET and
  ACTUAL) and its "Given" marks were spelled with (rtos v 4 n), which
  reads DIMZIN: at DIMZIN 0 -- acad.dwt's -- a 15-ft length came out
  15' and a 6 1/2" one 6 1/2", the notation the review tools reject as
  "feet with no inches".  They go through pool:ftin now, a copy of
  CALOFIN-LIB's cal:ftin, which says 15'-0" and 0'-6 1/2" whatever
  DIMZIN is.
* A LIMIT SHOWN THAT THE PROMPT THEN REFUSES.  POOL's and SPA's corner
  cap, the C2 "between" range in POOL and POOLSIDE, and OASIS's bulge
  bounds were shown with (rtos limit), which rounds to nearest: a 47.8
  cap read 3'-11 13/16" (47.8125), and the drafter who typed exactly
  what the refusal said was refused again.  Each now shows the limit
  floored (a maximum) or ceiled (a minimum) to the shown step, and each
  test here TYPES THE SHOWN LIMIT BACK and requires it to be taken.
  OASIS's side bulge has two bounds, and the refusal named the first
  one tested rather than the tighter: in a 50 x 60.1 envelope it said
  the Y bound's 2'-6", and 30 typed back was refused on the X bound.
* A KNOB HANDED BACK ON ENTER UNCHECKED.  spa:*gapdflt*,
  scv:*offset-dflt* and oasis:*hopoff* are the Enter answers of prompts
  whose initget refuses zero and negatives -- and Enter skips initget.
  A knob of 0 or -6 came back as the answer: SPA's lap turned inward,
  SPACOVCREATE drew the cover inside the spa, OASIS built its hopper on
  the wall or outside the pool.  Each is held to the typed prompt's test
  now and falls back to the shipped value.  pool:*given-den* is one
  too: a 0 read 20 1/2" as 21", and the feet-inch spelling of a Given
  mark ignored it altogether, so at 16 a mark read 20 1/16" and flipped
  to 1'-8 1/8".

Every check here needs an rtos that follows DIMZIN and defaults its
mode and precision to LUNITS / LUPREC, as AutoCAD's does.  lispvm's own
does once the honest-VM wave has landed; until then it did neither.  So
the file PROBES the VM's rtos first and uses it when it passes, and
only installs its own copy (the prototype the values guard was proved
with) when it does not -- once the wave is in, the copy is never used
and cannot drift from the VM's.  LUPREC is set to 4, acad.dwt's, on
every VM here as well: the shown-step copies read it, and the checks
should not lean on which wave landed first.

How each was confirmed to fail before the fix: the same checks were run
against HEAD's copy of each file (git show HEAD:<path>), and against
the copy each fix was made on, with GUARDFIX_OLD=<dir> pointing this
file at that copy.

Run: python3 tests/test_guardfix_poolspa.py
"""

import math
import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

import lispvm                                         # noqa: E402
from lispvm import VM, BUILTINS, Dot, LispError, Sym, num  # noqa: E402

#: GUARDFIX_OLD=<dir> reads <dir>/POOL.LSP etc. instead of lisp/ -- the
#: way the old code was shown to fail every check below
OLD = os.environ.get('GUARDFIX_OLD')


def src(rel):
    if OLD:
        return os.path.join(OLD, os.path.basename(rel))
    return os.path.join(REPO_DIR, rel)


POOL = src('lisp/pool/POOL.LSP')
POOLSIDE = src('lisp/poolside/POOLSIDE.lsp')
SPA = src('lisp/spa/SPA.LSP')
OASIS = src('lisp/oasis/OASIS.lsp')
SCV = src('lisp/spacovcreate/SPACOVCREATE.lsp')

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + ("  -- " + str(detail) if detail and not ok else ""))
    if not ok:
        failures.append(label)


# ------------------------------------------------------ the honest rtos
# Copied from the values guard's prototype (honest_vm.py): the text
# follows DIMZIN, and mode / precision default to LUNITS / LUPREC.  The
# fallback for a lispvm that predates the honest-VM wave; see below.

def _dec(v, prec, dz):
    s = f"{v:.{prec}f}"
    if s.startswith("-") and float(s) == 0.0:
        s = s[1:]
    if dz & 8 and "." in s:
        s = s.rstrip("0").rstrip(".")
    if dz & 4:
        if s.startswith("0."):
            s = s[1:]
        elif s.startswith("-0."):
            s = "-" + s[2:]
    return s


def honest_rtos(vm, a):
    v = num(a[0])
    lun = vm.sysvars.get('LUNITS', 2)
    lup = vm.sysvars.get('LUPREC', 4)
    mode = int(a[1]) if len(a) > 1 and a[1] is not lispvm.NIL else int(
        lun or 2)
    prec = int(a[2]) if len(a) > 2 and a[2] is not lispvm.NIL else int(
        4 if lup is None else lup)
    dz = int(vm.sysvars.get('DIMZIN', 0) or 0)
    low = dz & 3
    keep_feet = low in (1, 2)          # 0 and 3 suppress zero feet
    keep_inch = low in (1, 3)          # 0 and 2 suppress zero inches
    if mode == 1:
        return f"{v:.{prec}E}"
    if mode in (3, 4):
        neg = v < 0
        v = abs(v)
        if mode == 4:
            den = 2 ** prec
            total = round(v * den)
            inches, frac = divmod(total, den)
            feet, whole = divmod(inches, 12)
            zero_in = (whole == 0 and frac == 0)
            if frac:
                g = math.gcd(frac, den)
                fr = f"{frac // g}/{den // g}"
                ins = (f"{whole} {fr}" if (whole or feet or keep_feet)
                       else fr)
            else:
                ins = f"{whole}"
            ins += '"'
        else:
            feet = int(v // 12)
            rem = v - 12 * feet
            ins_s = _dec(rem, prec, dz)
            if float(ins_s or 0) >= 12.0:
                feet += 1
                ins_s = _dec(0.0, prec, dz)
            zero_in = float(ins_s or 0) == 0.0
            ins = ins_s + '"'
        if feet == 0 and not keep_feet:
            s = ins
        elif zero_in and not keep_inch and feet != 0:
            s = f"{feet}'"
        else:
            s = f"{feet}'-{ins}"
        return ("-" if neg and s not in ('0"',) else "") + s
    if mode == 5:
        den = 2 ** prec
        total = round(abs(v) * den)
        whole, frac = divmod(total, den)
        if frac:
            g = math.gcd(frac, den)
            s = (f"{whole} " if whole else "") + f"{frac // g}/{den // g}"
        else:
            s = f"{whole}"
        return ("-" if v < 0 else "") + s
    return _dec(v, prec, dz)


def _vm_rtos_is_honest():
    """True when lispvm's own rtos already spells what AutoCAD's does:
    DIMZIN 0 drops a whole foot's inches and a sub-foot length's feet,
    and a bare (rtos v) reads LUNITS / LUPREC."""
    vm = VM()
    vm.sysvars.update({'DIMZIN': 0, 'LUNITS': 4, 'LUPREC': 4})
    try:
        return (vm.loads('(rtos 180.0 4 4)') == "15'"
                and vm.loads('(rtos 6.5 4 4)') == '6 1/2"'
                and vm.loads('(rtos 47.75)') == '3\'-11 3/4"')
    except LispError:
        return False


VM_RTOS_HONEST = _vm_rtos_is_honest()
if not VM_RTOS_HONEST:
    BUILTINS[Sym('rtos')] = honest_rtos

#: the rtos every VM below uses -- the text a check expects is spelled
#: through the same function the tool's own text is
rtos = BUILTINS[Sym('rtos')]
print("rtos: " + ("lispvm's own" if VM_RTOS_HONEST
                  else "this file's copy (lispvm predates the honest-VM wave)"))


def length(s):
    """A length as rtos spells it -- 3'-11 3/4", 6", 47.7500 -- in
    inches: what getdist would take back if it were typed."""
    s = s.strip()
    m = re.fullmatch(r"""(-?)(?:(\d+)'-?)?(?:(\d+)(?: (\d+)/(\d+))?"|(\d+)/(\d+)")?""",
                     s)
    if m and (m.group(2) or m.group(3) or m.group(6)):
        ft = int(m.group(2) or 0)
        inch = int(m.group(3) or 0)
        if m.group(4):
            inch += int(m.group(4)) / int(m.group(5))
        if m.group(6):
            inch += int(m.group(6)) / int(m.group(7))
        v = ft * 12 + inch
        return -v if m.group(1) else v
    return float(s)


def vm_for(path, *more):
    Ent = lispvm.Ent
    Ent._n = 0
    vm = VM()
    vm.sysvars['LUPREC'] = 4           # acad.dwt's, whatever lispvm seeds
    vm.load(path)
    for m in more:
        vm.loads(m)
    return vm


def said(vm):
    return ''.join(vm.printed)


def last_said(vm, word):
    hits = [s for s in vm.printed if word in s]
    return hits[-1] if hits else ''


# ================================================ 1. POOL's drawn feet-inches

print("\nPOOL's report and Given marks do not follow DIMZIN")


for dz in (0, 1, 2, 3, 8):
    vm = vm_for(POOL)
    vm.sysvars['DIMZIN'] = dz
    vm.loads('(setq pool:*ftin* T)')
    got = [vm.loads('(pool:fmtlen %s)' % v) for v in ('180.0', '6.5', '186.25')]
    check("DIMZIN %d: the report's feet-inches read 15'-0\", 0'-6 1/2\", "
          "15'-6 1/4\"" % dz,
          got == ["15'-0\"", "0'-6 1/2\"", "15'-6 1/4\""], got)
    got = vm.loads('(pool:fmtgiven 180.0)')
    check("DIMZIN %d: a Given mark at or past the small-dim cut is 15'-0\""
          % dz, got == "15'-0\"", got)

# plain inches stay what they were -- only the feet-inch spelling moved
vm = vm_for(POOL)
vm.loads('(setq pool:*ftin* nil)')
check("with pool:*ftin* off the report is still plain inches",
      vm.loads('(pool:fmtlen 180.0)') == "180.00",
      vm.loads('(pool:fmtlen 180.0)'))

# the flip: a Given mark drawn in inches, clicked, becomes feet-inches
# spelled the same way the mark is first drawn -- and back again
vm = vm_for(POOL)
vm.sysvars['DIMZIN'] = 0
vm.loads('(entmake (list (cons 0 "TEXT") (cons 8 "0") (list 10 0.0 0.0 0.0)'
         ' (cons 40 1.0) (cons 1 "180\\" Given")))')
vm.loads('(setq t:e (entlast) pool:*giventxts* (list (cons t:e 180.0)))')
vm.loads('(pool:flipgiven t:e)')
got = vm.loads('(cdr (assoc 1 (entget t:e)))')
check("a flipped Given mark reads 15'-0\" Given at DIMZIN 0",
      got == "15'-0\" Given", got)
vm.loads('(pool:flipgiven t:e)')
got = vm.loads('(cdr (assoc 1 (entget t:e)))')
check("and flips back to plain inches", got == "180\" Given", got)
# a small one, drawn in inches, still flips to feet-inches and back
vm.loads('(entmake (list (cons 0 "TEXT") (cons 8 "0") (list 10 0.0 0.0 0.0)'
         ' (cons 40 1.0) (cons 1 "6 1/2\\" Given")))')
vm.loads('(setq t:s (entlast) pool:*giventxts* (list (cons t:s 6.5)))')
vm.loads('(pool:flipgiven t:s)')
got = vm.loads('(cdr (assoc 1 (entget t:s)))')
check("a small Given mark flips to 0'-6 1/2\" Given, not 6 1/2\"",
      got == "0'-6 1/2\" Given", got)

# pool:*given-den* is read by BOTH spellings of a Given mark: the flip
# goes inch -> feet-inch -> inch on one value, so the fraction may not
# change on the way.  The feet-inch half was fixed at the eighth, so at
# 16 a mark read 20 1/16" and flipped to 1'-8 1/8".
print("\nPOOL: a Given mark reads to 1/*given-den* both ways it is spelled")


def given(den, v):
    """(inch spelling, feet-inch spelling after one flip) of a Given
    mark of V, with pool:*given-den* set to DEN (a Lisp literal)."""
    vm = vm_for(POOL)
    vm.loads('(setq pool:*given-den* %s)' % den)
    inch = vm.loads('(pool:inchtxt %r)' % v) + '"'
    vm.loads('(entmake (list (cons 0 "TEXT") (cons 8 "0")'
             ' (list 10 0.0 0.0 0.0) (cons 40 1.0)'
             ' (cons 1 (strcat (pool:inchtxt %r) "\\" Given"))))' % v)
    vm.loads('(setq t:e (entlast) pool:*giventxts* (list (cons t:e %r)))' % v)
    vm.loads('(pool:flipgiven t:e)')
    ft = vm.loads('(cdr (assoc 1 (entget t:e)))')
    return inch, ft


def inch_part(ft):
    """1'-8 1/16\" Given -> 8 1/16"""
    m = re.match(r"(\d+)'-(.*?)\" Given$", ft)
    return m.group(2) if m else None


for den, v, want_in, want_ft in (
        ('16', 20.0625, '20 1/16"', "1'-8 1/16\" Given"),
        ('16.0', 20.0625, '20 1/16"', "1'-8 1/16\" Given"),
        ('4', 20.1, '20"', "1'-8\" Given"),
        ('8', 20.1, '20 1/8"', "1'-8 1/8\" Given")):    # the shipped 8
    try:
        inch, ft = given(den, v)
    except LispError as e:
        inch, ft = None, str(e)
    check("given-den %s: %s reads %s and flips to %s"
          % (den, v, want_in, want_ft),
          (inch, ft) == (want_in, want_ft), (inch, ft))
vm = vm_for(POOL)
vm.loads('(setq pool:*given-den* 16)')
got = vm.loads('(pool:fmtgiven 186.0625)')
check("given-den 16: a drawn feet-inch mark reads 15'-6 1/16\"",
      got == "15'-6 1/16\"", got)

# not a power of two: the inches read it, the feet-inches cannot, and
# keep the shipped eighth rather than inventing a spelling
try:
    inch, ft = given('12', 20.5)
except LispError as e:
    inch, ft = None, str(e)
check("given-den 12: 20 1/2\" flips to 1'-8 1/2\" Given",
      (inch, ft) == ('20 1/2"', "1'-8 1/2\" Given"), (inch, ft))

# a knob that is no denominator at all -- LAZTUNE writes whatever is
# typed -- reads as the shipped 8, both ways, instead of rounding every
# fraction up to the next inch (0, -8) or stopping the report ("8")
for den in ('0', '-8', '"8"', '2.5'):
    try:
        inch, ft = given(den, 20.5)
    except LispError as e:
        inch, ft = None, str(e)
    check("given-den %s: 20 1/2\" reads 20 1/2\" and 1'-8 1/2\" Given"
          % den, (inch, ft) == ('20 1/2"', "1'-8 1/2\" Given"), (inch, ft))


# ============================================== 2. POOL's corner cap, typed back

print("\nPOOL: the corner cap a refusal shows is one the prompt takes")


def type_back(word, seen):
    """A scripted answer that reads the last refusal containing WORD and
    types the limit it named straight back."""
    def answer(vm):
        msg = last_said(vm, word)
        m = re.search(r"max (.*?)\.  Re-enter", msg)
        seen['shown'] = m.group(1) if m else None
        seen['value'] = length(m.group(1)) if m else None
        return seen['value']
    return answer


seen = {}
vm = vm_for(POOL, '(pool:rulerlayer)')
try:
    # a 240 x 95.6 rectangle: half the short wall is 47.8, a cap that is
    # not on the 1/16 grid -- rounded to nearest it reads 3'-11 13/16"
    vm.run('c:POOL', ["Outofsquare", "Rectangle", (0.0, 0.0, 0.0),
                      240.0, 240.0, 95.6, 95.6,
                      "Radius", 60.0, type_back("Too large", seen),
                      None, None, None, None, None, None,
                      "Ends", 258.339, 258.339, 258.339, 258.339,
                      "No", "No",
                      None])              # no step outside the shallow end
    ran = None
except LispError as e:
    ran = str(e)
check("the run completes when the shown cap is typed back", ran is None, ran)
check("the cap is shown floored: 3'-11 3/4\"",
      seen.get('shown') == "3'-11 3/4\"", seen)
check("the too-large refusal came once -- the typed-back cap was taken",
      said(vm).count("Too large for this corner's walls") == 1,
      said(vm).count("Too large for this corner's walls"))


# ================================================= 3. C2 between, POOL and POOLSIDE

print("\nPOOL and POOLSIDE: C2's range is shown as the prompt takes it")


def between(msg):
    m = re.search(r"between C \((.*?)\) and D \((.*?)\)", msg)
    return (m.group(1), m.group(2)) if m else (None, None)


# pool:askc2 on its own: C 42.02, D 72.22 -- neither on the 1/16 grid,
# and each rounded to nearest the WRONG way: C reads 3'-6" (42.0, under
# C) and D 6'-0 1/4" (72.25, past D), so either typed back is refused
vm = vm_for(POOL)
vm.sysvars['LUNITS'] = 4                  # POOL's own for the run
vm.loads('(defun c:t-c2 () (setq t:c2 (pool:askc2 "C2 - depth" nil'
         ' 42.02 72.22 nil)))')
shown = {}


def c2_back(which):
    def answer(vm):
        c, d = between(last_said(vm, "C2 must be between"))
        shown['c'], shown['d'] = c, d
        return length(d if which == 'd' else c)
    return answer


try:
    vm.run('c:t-c2', [80.0, c2_back('d')])
    ran = None
except LispError as e:
    ran = str(e)
check("POOL: D as shown, typed back as C2, is taken", ran is None, ran)
check("POOL: D 72.22 is shown floored, 6'-0 3/16\"",
      shown.get('d') == "6'-0 3/16\"", shown)
check("POOL: C 42.02 is shown ceiled, 3'-6 1/16\"",
      shown.get('c') == "3'-6 1/16\"", shown)
vm = vm_for(POOL)
vm.sysvars['LUNITS'] = 4
vm.loads('(defun c:t-c2 () (setq t:c2 (pool:askc2 "C2 - depth" nil'
         ' 42.02 72.22 nil)))')
try:
    vm.run('c:t-c2', [30.0, c2_back('c')])
    ran = None
except LispError as e:
    ran = str(e)
check("POOL: C as shown, typed back as C2, is taken", ran is None, ran)

# POOLSIDE's own copy of the loop, in a whole SHallow run
shown = {}
try:
    Ent = lispvm.Ent
    Ent._n = 0
    vm = VM()
    vm.sysvars['LUPREC'] = 4
    vm.load(POOLSIDE)
    vm.run('c:POOLSIDE', ["SHallow", (0.0, 0.0, 0.0),
                          480.0, 60.0, 90.0, 240.0, 90.0,
                          42.02, 72.22,
                          80.0,              # C2 deeper than D -- refused
                          c2_back('d'),      # D, as the refusal said it
                          "No"])
    ran = None
except LispError as e:
    ran = str(e)
check("POOLSIDE: D as shown, typed back as C2, is taken", ran is None, ran)
check("POOLSIDE: D 72.22 is shown floored, 6'-0 3/16\"",
      shown.get('d') == "6'-0 3/16\"", shown)
check("POOLSIDE: C 42.02 is shown ceiled, 3'-6 1/16\"",
      shown.get('c') == "3'-6 1/16\"", shown)


# ================================================== 4. SPA's corner cap, typed back

print("\nSPA: the corner cap a refusal shows is one the prompt takes")

for ty, cap, want in (("Radius", 47.8, "3'-11 3/4\""),
                      # a Diagonal's cap is the setback over 0.70711:
                      # 33.8 / 0.70711 = 47.800... reads 3'-11 13/16"
                      # rounded, 3'-11 3/4" floored
                      ("Cut", 33.8, "3'-11 3/4\"")):
    seen = {}
    vm = vm_for(SPA, '(spa:rulerlayer)')
    vm.sysvars['LUNITS'] = 4              # SPA's own for the run
    vm.loads('(defun c:t-cor () (setq t:cor (spa:askcorner "Corner A" nil'
             ' nil nil %s nil)))' % cap)
    try:
        vm.run('c:t-cor', [ty, 60.0, type_back("Too large", seen)])
        ran = None
    except LispError as e:
        ran = str(e)
    check("SPA %s: the cap typed back as shown is taken" % ty, ran is None,
          ran)
    check("SPA %s: the cap is shown floored, %s" % (ty, want),
          seen.get('shown') == want, seen)
    got = vm.loads('t:cor')
    check("SPA %s: and the corner comes back at that size" % ty,
          isinstance(got, list) and got[0] == ty
          and abs(got[1] - length(want)) < 1e-9, got)


# ======================================================= 5. OASIS's bulge bounds

print("\nOASIS: a bulge bound a refusal shows is one the prompt takes")


def or_less(vm):
    m = re.search(r"envelope\.  (.*?) or less\.",
                  last_said(vm, "or less"))
    return m.group(1) if m else None


def bound_back(seen):
    def answer(vm):
        seen['shown'] = or_less(vm)
        return length(seen['shown']) if seen['shown'] else None
    return answer


for lun in (4, 2):
    # h 60.1: half is 30.05, off the 1/16 grid (rounded 2'-6 1/16")
    seen = {}
    vm = vm_for(OASIS)
    vm.sysvars['LUNITS'] = lun
    vm.loads('(defun c:t-bul () (setq t:v (oasis:ask-bulge "Left bulge'
             ' radius" "left" 400.0 60.1)))')
    try:
        vm.run('c:t-bul', [40.0, bound_back(seen)])
        ran = None
    except LispError as e:
        ran = str(e)
    check("OASIS LUNITS %d: a side bulge's Y bound typed back is taken"
          % lun, ran is None, ran)
    if lun == 4:
        check("OASIS: the Y bound is shown floored, 2'-6\"",
              seen.get('shown') == "2'-6\"", seen)

    # w 60.1 against a deep envelope: the X bound, the second message
    seen = {}
    vm = vm_for(OASIS)
    vm.sysvars['LUNITS'] = lun
    vm.loads('(defun c:t-bul () (setq t:v (oasis:ask-bulge "Left bulge'
             ' radius" "left" 60.1 400.0)))')
    try:
        vm.run('c:t-bul', [40.0, bound_back(seen)])
        ran = None
    except LispError as e:
        ran = str(e)
    check("OASIS LUNITS %d: a side bulge's X bound typed back is taken"
          % lun, ran is None, ran)

    # the corner (TopRight) bulge: min(w, h) / 2
    seen = {}
    vm = vm_for(OASIS)
    vm.sysvars['LUNITS'] = lun
    vm.loads('(defun c:t-top () (setq t:v (oasis:ask-top "Top bulge radius"'
             ' 60.1 400.0 10.0 "TopRight" 0.0)))')
    try:
        vm.run('c:t-top', [40.0, bound_back(seen)])
        ran = None
    except LispError as e:
        ran = str(e)
    check("OASIS LUNITS %d: the corner bulge's bound typed back is taken"
          % lun, ran is None, ran)

# Both bounds binding: a 40 in a 50 wide x 60.1 tall envelope breaks
# out of both, and the refusal has to name the TIGHTER one.  Picked by
# the first test failed, it said the Y bound's 2'-6" or less, and 30
# typed back was refused again on the X bound.  One refusal, then taken.
for w, h, shown, where in ((50.0, 60.1, "2'-1\"", "far side"),
                           (60.1, 50.0, "2'-1\"", "top")):
    seen = {}
    vm = vm_for(OASIS)
    vm.sysvars['LUNITS'] = 4
    vm.loads('(defun c:t-bul () (setq t:v (oasis:ask-bulge "Left bulge'
             ' radius" "left" %r %r)))' % (w, h))
    try:
        vm.run('c:t-bul', [40.0, bound_back(seen)])
        ran = None
    except LispError as e:
        ran = str(e)
    refusals = [p for p in vm.printed if "or less" in p]
    check("OASIS %g x %g: the tighter bound, %s, is shown and taken back"
          % (w, h, shown),
          ran is None and seen.get('shown') == shown and len(refusals) == 1,
          (ran, seen, refusals))
    check("OASIS %g x %g: ...and it says the bulge breaks the %s"
          % (w, h, where), refusals and where in refusals[0], refusals)


# ================================================ 6. knobs handed back on Enter

print("\nknobs handed back on Enter are held to the typed prompt's test")

# SPA's cover lap: the Watersedge mode signs it outward (+1)
for knob, want in (("0.0", 6.0), ("-6.0", 6.0), ("1524.0", 6.0),
                   ("8.0", 8.0), ('"6"', 6.0)):
    vm = vm_for(SPA, '(setq spa:*mode* "Watersedge")')
    vm.loads('(setq spa:*gapdflt* %s)' % knob)
    vm.loads('(defun c:t-gap () (setq t:g (spa:askgap)))')
    try:
        vm.run('c:t-gap', [None])
        got = vm.loads('t:g')
    except LispError as e:
        got = str(e)
    check("SPA: a lap knob of %s gives %s on Enter" % (knob, want),
          got == want, got)
    shown = [p for p, _ in vm.prompts if "lap the water's edge" in p]
    check("SPA: ...and the prompt offers <%s>" % rtos(vm, [want]),
          shown and ("<%s>" % rtos(vm, [want])) in shown[0], shown)

# SPACOVCREATE's cover offset: a whole run, Enter at the offset
RECT = ('(entmake (list (cons 0 "LAYER") (cons 2 "POOL") (cons 70 0)'
        ' (cons 62 4) (cons 6 "CONTINUOUS")))'
        "(entmake (list '(0 . \"LWPOLYLINE\") '(100 . \"AcDbEntity\")"
        " '(8 . \"POOL\") '(100 . \"AcDbPolyline\") '(90 . 4) '(70 . 1)"
        " (list 10 0.0 0.0) '(42 . 0.0) (list 10 100.0 0.0) '(42 . 0.0)"
        " (list 10 100.0 60.0) '(42 . 0.0) (list 10 0.0 60.0)"
        " '(42 . 0.0)))")


def cover_verts(vm):
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata[e]
        kind = [p.b for p in d if isinstance(p, Dot) and p.a == 0]
        lay = [p.b for p in d if isinstance(p, Dot) and p.a == 8]
        if kind == ["LWPOLYLINE"] and lay == ["COVER"]:
            return [(p[1], p[2]) for p in d
                    if isinstance(p, list) and p and p[0] == 10]
    return None


for knob in ("0.0", "-6.0", "6.0"):
    vm = vm_for(SCV, RECT)
    spa = list(vm.entities)
    vm.loads('(setq scv:*offset-dflt* %s)' % knob)
    try:
        vm.run('c:SPACOVCREATE', [None, spa, None, None])
        got = cover_verts(vm)
    except LispError as e:
        got = str(e)
    check("SPACOVCREATE: an offset knob of %s draws the cover 6 OUTSIDE "
          "the spa on Enter" % knob,
          got == [(-6.0, -6.0), (106.0, -6.0), (106.0, 66.0), (-6.0, 66.0)],
          got)

# OASIS's hopper offset: the build is stubbed to record what it is
# handed, so the check is the Enter answer itself, not the pool
STUB = ('(defun oasis:bottom (arcs sh1 sh2 sd1 sd2 off)'
        ' (setq t:off off) (list (quote hop)))')
for knob, last, want in (("0.0", "nil", 18.0), ("-18.0", "nil", 18.0),
                         ('"18"', "nil", 18.0), ("12.0", "nil", 12.0),
                         ("-5.0", "24.0", 24.0), ("30.0", "-2.0", 30.0)):
    vm = vm_for(OASIS, STUB)
    vm.loads('(setq oasis:*hopoff* %s oasis:*hopoff-last* %s)' % (knob, last))
    vm.loads("(defun c:t-hop () (setq t:r (oasis:askhopoff nil"
             " '(1.0 2.0) '(3.0 4.0))))")
    try:
        vm.run('c:t-hop', [None])
        got = vm.loads('t:off')
    except LispError as e:
        got = str(e)
    check("OASIS: knob %s, last %s -- Enter builds the hopper at %s"
          % (knob, last, want), got == want, got)
    shown = [p for p, _ in vm.prompts if "Hopper offset" in p]
    check("OASIS: ...and the prompt offers <%s>" % rtos(vm, [want]),
          shown and ("<%s>" % rtos(vm, [want])) in shown[0], shown)


print()
if failures:
    print("FAILED: %d" % len(failures))
    for f in failures:
        print("  - " + f)
    sys.exit(1)
print("all guard-fix POOL/SPA tests passed")
