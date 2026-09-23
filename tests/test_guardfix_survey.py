#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The survey tools' second guard-fix wave: ABPCHECK, ABFIND, ABHD,
ABLOBF, CABHD, LHD, WCALST, FITABHD and POINTRENAMER, each fix driven
in the AutoLISP VM and each written to FAIL on the code before it.

Two families of fault, both invisible in a VM that is kinder than
AutoCAD:

* FEET AND INCHES WRITTEN INTO THE DRAWING THROUGH rtos.  rtos modes 3
  and 4 read DIMZIN: at 0 -- acad.dwt's -- a whole foot is 15' and a
  sub-foot length 1 7/8", the spelling the review tools reject.  The
  ABPCHECK report, ABFIND's created-point note, the four fitters'
  "Pt.N off by ..." list and WCALST's summary all left that text on the
  sheet.  AutoCAD's rtos is modelled HERE (DIMZIN included), for the
  length of one test, and each site is required to say 15'-0" and
  0'-1 7/8" anyway.  WCALST's summary also read its "8 = eighths" knob
  as rtos's power of two, and wrote 1/256ths.

* A KNOB HANDED BACK ON ENTER UNCHECKED.  initget holds only what is
  TYPED; Enter hands the offered default back as it stands, and on a
  first run that default is a LAZTUNE knob.  ABPCHECK's limit, the four
  fitters' miss share, FITABHD's miss share and its four remembered
  answers, POINTRENAMER's band and first number and WCALST's cut cap
  each came back as an answer the typed prompt would have refused.
  Each is now held to the typed prompt's test where it is offered, and
  falls back to the shipped value.

Run: python3 tests/test_guardfix_survey.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_guardfix_survey.py
"""

import contextlib
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, LispError, Dot, Sym, NIL, BUILTINS  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def src(*parts):
    """A lisp/ path; vm.load remaps it to the grouped tier (and loads the
    library first) when CALOFIN_LISP_ROOT says so."""
    return os.path.join(REPO, 'lisp', *parts)


ABPCHECK = src('abpcheck', 'ABPCHECK.lsp')
ABFIND = src('abfind', 'ABFIND.lsp')
ABHD = src('abhd', 'abhd.lsp')
ABLOBF = src('ablobf', 'ABLOBF.lsp')
CABHD = src('cabhd', 'CABHD.lsp')
LHD = src('lhd', 'lhd.lsp')
WCALST = src('wcalst', 'wcalst.lsp')
FITABHD = src('fitabhd', 'FITABHD.lsp')
POINTRENAMER = src('pointrenamer', 'POINTRENAMER.lsp')

failures = []


def check(label, ok, detail=''):
    print(('  ok   ' if ok else '  FAIL ') + label
          + (f'  -- {detail}' if detail and not ok else ''))
    if not ok:
        failures.append(label)


def grp(d, code):
    for g in d or []:
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else g[1:]
    return None


def texts(vm, layer=None):
    """The group-1 string of every live TEXT (optionally on LAYER)."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'TEXT' and (layer is None or grp(d, 8) == layer):
            out.append(grp(d, 1))
    return out


def asked(vm):
    return ' | '.join(p.replace('\n', ' ') for p, _ in vm.prompts)


# ---------------------------------------------------------------- models

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


def rtos_acad(vm, a):
    """AutoCAD's rtos: mode and precision default to LUNITS / LUPREC, and
    feet-and-inches follow DIMZIN's two low bits -- 0 (acad.dwt's)
    drops a zero foot AND a zero inch, so 180 is 15' and 1.875 is
    1 7/8"."""
    v = float(a[0])
    lun = vm.sysvars.get('LUNITS', 2)
    lup = vm.sysvars.get('LUPREC', 4)
    mode = int(a[1]) if len(a) > 1 and a[1] is not NIL else int(lun or 2)
    prec = int(a[2]) if len(a) > 2 and a[2] is not NIL else int(
        4 if lup is None else lup)
    dz = int(vm.sysvars.get('DIMZIN', 0) or 0)
    low = dz & 3
    keep_feet = low in (1, 2)
    keep_inch = low in (1, 3)
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
    return _dec(v, prec, dz)


@contextlib.contextmanager
def acad_rtos():
    """rtos as AutoCAD spells it, for the length of one test."""
    old = BUILTINS[Sym('rtos')]
    BUILTINS[Sym('rtos')] = rtos_acad
    try:
        yield
    finally:
        BUILTINS[Sym('rtos')] = old


def newvm(path, dimzin=0):
    vm = VM()
    vm.load(path)
    vm.sysvars['DIMZIN'] = dimzin
    vm.sysvars.setdefault('LUPREC', 4)
    return vm


# ======================================================================
# 1. feet and inches written into the drawing
# ======================================================================
print("feet and inches written into the drawing, at DIMZIN 0")

# -- ABPCHECK: the report MTEXT --------------------------------------------
RECT = '''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 240.0 0.0)   '(42 . 0.0)
                 '(10 240.0 120.0) '(42 . 0.0)
                 '(10 0.0 120.0)   '(42 . 0.0)))'''


def abp_point(x, y):
    return f'''
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(100 . "AcDbPoint")
                 (list 10 {x} {y} 0.0)))'''


def abp_report(vm):
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'MTEXT':
            head = ''.join(g.b for g in d if isinstance(g, Dot) and g.a == 3)
            return head + (grp(d, 1) or '')
    return ''


def abp_vm(knob=None):
    vm = newvm(ABPCHECK)
    vm.loads(RECT)
    # on the bottom run; 2" above it; 12" right of the right run; 1 7/8"
    # below the bottom run
    for x, y in ((60, 0), (120, 2), (252, 60), (200, -1.875)):
        vm.loads(abp_point(x, y))
    if knob is not None:
        vm.loads('(setq abp:*limit* %r)' % knob)
    return vm


with acad_rtos():
    vm = abp_vm()
    vm.run('c:ABPCHECK', [None, None, 1.0])
    rep = abp_report(vm)
    check("ABPCHECK: a point a foot off reads 1'-0\" in the report",
          "closest line is 1'-0\" away" in rep, rep[-600:])
    check("ABPCHECK: a sub-foot miss reads 0'-1 7/8\", not 1 7/8\"",
          "closest line is 0'-1 7/8\" away" in rep, rep[-600:])
    check("ABPCHECK: a point on the line reads 0'-0\"",
          "closest line is 0'-0\" away" in rep, rep[-600:])
    check("ABPCHECK: the verdict names the limit as 0'-1\"",
          "3 POINTS MORE THAN 0'-1\" OFF THE LINE" in rep, rep[:500])

# -- ABFIND: the created point's note --------------------------------------
with acad_rtos():
    vm = newvm(ABFIND)
    note = vm.loads('(abf:new-note-text "7" 180.0 7.5 nil)')
    check("ABFIND: a created point's note says 15'-0\" and 0'-7 1/2\"",
          note == 'Created Pt.7 - A 15\'-0", B 0\'-7 1/2"', repr(note))
    note = vm.loads('(abf:new-note-text "8" 150.0 96.0'
                    ' (list nil "A" "B" 90.0 84.0))')
    check("ABFIND: the held/moved note spells every reading in full",
          note == ('Created Pt.8 - A 12\'-6" held, B from 7\'-6"'
                   ' to 7\'-0"'), repr(note))

# -- the four fitters: "Pt.N   off by ..." ---------------------------------
SEG = "(list (list '(0.0 0.0) '(100.0 0.0) 0.0))"
BAD = "(list '(0.0 12.0) '(50.0 1.875))"
BB = "'(0.0 0.0 100.0 50.0)"
for pfx, path, layer, omit in (('pf', ABHD, '*PF-MISS-LAYER*', True),
                               ('abl', ABLOBF, '*ABL-MISS-LAYER*', True),
                               ('cab', CABHD, '*CAB-MISS-LAYER*', True),
                               ('lh', LHD, '*LH-MISS-LAYER*', False)):
    with acad_rtos():
        vm = newvm(path)
        vm.loads('(%s:mark-unheld %s %s%s %s 6.0)'
                 % (pfx, BAD, 'nil ' if omit else '', SEG, BB))
        lay = vm.loads(layer)
        offs = [t for t in texts(vm, lay) if 'off by' in t]
    name = os.path.basename(path).split('.')[0].upper()
    check(f"{name}: the off-by list says 1'-0\" and 0'-1 7/8\"",
          offs == ['Pt.?   off by 1\'-0"', 'Pt.?   off by 0\'-1 7/8"'],
          repr(offs))

# -- WCALST: the summary on the sheet --------------------------------------


def wc_layer(n, c):
    return f'''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "{n}") '(70 . 0) '(62 . {c})
                 '(6 . "Continuous")))'''


def wc_line(p, q, lay):
    return f'''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "{lay}")
                 '(100 . "AcDbLine")
                 '(10 {p[0]!r} {p[1]!r} 0.0) '(11 {q[0]!r} {q[1]!r} 0.0)))'''


def wc_band(vm):
    """test_wcalst's oracle band: (its entities, the side-pick answer)."""
    ang = [math.radians(30 + 15 * i) for i in range(9)]
    near = [(200.0 * math.cos(a), 200.0 * math.sin(a)) for a in ang]
    far = [(176.0 * math.cos(a), 176.0 * math.sin(a)) for a in ang]
    ents = []

    def mk(s):
        before = len(vm.entities)
        vm.loads(s)
        ents.extend(vm.entities[before:])

    for i in range(8):
        mk(wc_line(near[i], near[i + 1], 'NEAR'))
    for i in range(8):
        mk(wc_line(far[i], far[i + 1], 'FAR'))
    for i in range(9):
        mk(wc_line(near[i], far[i], 'RUNG'))
    mid = [(near[0][0] + near[1][0]) / 2.0,
           (near[0][1] + near[1][1]) / 2.0, 0.0]
    return ents, [ents[0], mid]


def wc_vm():
    vm = newvm(WCALST)
    for L in (wc_layer('NEAR', 1), wc_layer('FAR', 4), wc_layer('RUNG', 2),
              wc_layer('MARK', 6)):
        vm.loads(L)
    vm.sysvars['CLAYER'] = 'NEAR'
    return vm


with acad_rtos():
    vm = newvm(WCALST)
    got = [vm.loads('(wc:arch %r)' % v) for v in (180.0, 6.5, 147.3)]
    check("WCALST: a whole foot is 15'-0\" and a sub-foot 0'-6 1/2\"",
          got[:2] == ['15\'-0"', '0\'-6 1/2"'], repr(got))
    check("WCALST: the shipped 8 means eighths, not 1/256ths",
          got[2] == '12\'-3 1/4"', repr(got))
    vm.loads('(setq wc:*arch-frac* 16)')
    check("WCALST: a knob of 16 means sixteenths",
          vm.loads('(wc:arch 147.3)') == '12\'-3 5/16"',
          vm.loads('(wc:arch 147.3)'))
    vm.loads('(setq wc:*arch-frac* 0)')
    check("WCALST: a knob below 1 falls back to the shipped eighths",
          vm.loads('(wc:arch 147.3)') == '12\'-3 1/4"',
          vm.loads('(wc:arch 147.3)'))

    vm = wc_vm()
    ents, pick = wc_band(vm)
    vm.run('c:WCALST', [None, ents, pick, None, None, None])
    summ = [t for t in texts(vm) if t.startswith(('TOP LINE:',
                                                  'BOTTOM BEFORE:',
                                                  'BOTTOM AFTER:'))]
    arch = [re.search(r'\((.*)\)$', t).group(1) for t in summ
            if re.search(r'\((.*)\)$', t)]
    check("WCALST: the summary on the sheet carries three feet-inch twins",
          len(arch) >= 3, repr(summ))
    check("WCALST: every one spelled F'-I[ n/d]\" to eighths at most",
          arch and all(re.fullmatch(r"\d+'-\d+( \d+/[248])?\"", a)
                       for a in arch), repr(arch))


# ======================================================================
# 2. a knob handed back on Enter
# ======================================================================
print("a knob handed back on Enter is one the typed prompt would take")

# -- ABPCHECK's limit -------------------------------------------------------
for knob in (-1.0, 0.0):
    with acad_rtos():
        vm = abp_vm(knob)
        vm.run('c:ABPCHECK', [None, None, None])
        rep = abp_report(vm)
    check(f"ABPCHECK: a limit knob of {knob} is offered as <0'-1\">",
          any("<0'-1\">" in p for p, _ in vm.prompts), asked(vm))
    check(f"ABPCHECK: ...and Enter measures against 1\", not {knob}",
          "3 POINTS MORE THAN 0'-1\" OFF THE LINE" in rep, rep[:500])

# -- the four fitters' miss share ------------------------------------------
for pfx, path, knob, ship in (('pf', ABHD, '*PF-MISS-PCT*', 0.20),
                              ('abl', ABLOBF, '*ABL-MISS-PCT*', 0.15),
                              ('cab', CABHD, '*CAB-MISS-PCT*', 0.20),
                              ('lh', LHD, '*LH-MISS-PCT*', 0.15)):
    name = os.path.basename(path).split('.')[0].upper()
    for bad in (15, -0.1, '"20"'):
        vm = newvm(path)
        vm.loads('(setq %s %s)' % (knob, bad))
        vm.script, vm.prompts = [None], []
        try:
            got = vm.loads('(%s:ask-pct %s T)' % (pfx, knob))
        except LispError as e:
            got = 'died: %s' % e
        shown = '<%d>' % round(ship * 100)
        check(f"{name}: a miss knob of {bad} is offered as {shown}",
              any(shown in p for p, _ in vm.prompts), asked(vm))
        check(f"{name}: ...and Enter takes {ship}",
              isinstance(got, float) and abs(got - ship) < 1e-9, repr(got))
        ms = vm.loads('(%s:misspct)' % pfx)
        check(f"{name}: ...and so does the share no question was asked for",
              isinstance(ms, float) and abs(ms - ship) < 1e-9, repr(ms))
    # a good knob, and a remembered answer, are still offered as they are
    vm = newvm(path)
    vm.loads('(setq %s 0.3)' % knob)
    vm.script, vm.prompts = [None], []
    got = vm.loads('(%s:ask-pct %s T)' % (pfx, knob))
    check(f"{name}: a knob in range is offered and taken unchanged",
          any('<30>' in p for p, _ in vm.prompts)
          and isinstance(got, float) and abs(got - 0.3) < 1e-9,
          f'{got!r} {asked(vm)}')

# the whole command, Enter at every question: the step's own "Press
# Enter for the recommended N percent" line and its prompt agree, and
# both say the shipped share
for cmd, path, knob, word, ship, answers in (
        ('c:ABHD', ABHD, '*PF-MISS-PCT*', 'recommended', 20, 8),
        ('c:ABLOBF', ABLOBF, '*ABL-MISS-PCT*', 'standard', 15, 6),
        ('c:CABHD', CABHD, '*CAB-MISS-PCT*', 'recommended', 20, 8),
        ('c:LHD', LHD, '*LH-MISS-PCT*', 'standard', 15, 7)):
    vm = newvm(path)
    vm.loads('(setq %s 15)' % knob)
    try:
        vm.run(cmd, [None] * answers)
        died = ''
    except LispError as e:
        died = str(e)[:300]
    said = ''.join(vm.printed)
    check(f"{cmd[2:]}: a miss knob of 15 is announced as {ship} percent "
          f"and offered as <{ship}>",
          not died and f'{word} {ship} percent' in said
          and any(f'Percent of points allowed off <{ship}>' in p
                  for p, _ in vm.prompts),
          died or asked(vm))

# -- FITABHD ---------------------------------------------------------------


def fit_settings(sets, script, deflist=None):
    vm = newvm(FITABHD)
    for k, v in sets.items():
        vm.loads('(setq %s %s)' % (k, v))
    vm.script, vm.prompts = list(script), []
    try:
        got = vm.loads('(fit:ask-settings (list %s) 8)' % (
            deflist or 'fit:*ptype* "Square" 1.0 fit:*miss-pct* T T'))
    except LispError as e:
        got = 'died: %s' % e
    return vm, got


# a remembered answer in the wrong case: offered and taken in the
# keyword's own spelling, so the Rectangle and Radius branches take it
vm, got = fit_settings({'fit:*ptype*': '"rectangle"',
                        'fit:*treat*': '"radius"'},
                       [None, None, None, None, None, None])
check("FITABHD: a pool type of \"rectangle\" is offered as <Rectangle>",
      'Pool type [Rectangle/Grecian/ROman/Oval/L/LAzyl/ROUnd] <Rectangle>'
      in asked(vm), asked(vm))
check("FITABHD: ...so the corner question is asked, not skipped",
      'How should the pool corners be treated?' in asked(vm), asked(vm))
check("FITABHD: a treatment of \"radius\" comes back as Radius",
      isinstance(got, list) and got[:2] == ['Rectangle', 'Radius'],
      repr(got))

# a SYMBOL where the answer should be: the prompt's strcat died on it
vm, got = fit_settings({'fit:*gtreat*': "'radius"},
                       ['Grecian', None, None, None, None, None])
check("FITABHD: a cut-corner memory that is a symbol does not kill the "
      "prompt, and Enter takes Radius",
      isinstance(got, list) and got[:2] == ['Grecian', 'Radius'],
      repr(got))

# an unknown treatment falls back to the shipped Radius
vm, got = fit_settings({'fit:*treat*': '"rounded corner"'},
                       ['L', None, None, None, None, None])
check("FITABHD: a treatment that is no keyword is offered as <Radius>",
      isinstance(got, list) and got[1] == 'Radius'
      and '<Radius>' in asked(vm), f'{got!r} {asked(vm)}')

# the oasis family
vm, got = fit_settings({'fit:*oasfam*': '"kidney"'},
                       ['OAsis', None, None, None])
check("FITABHD: an oasis family of \"kidney\" comes back as Kidney",
      isinstance(got, list) and got[:2] == ['OAsis', 'Kidney'], repr(got))
vm, got = fit_settings({'fit:*oasfam*': '"bean"'},
                       ['OAsis', None, None, None])
check("FITABHD: an oasis family that is none of the five is <Center>",
      isinstance(got, list) and got[1] == 'Center'
      and 'NXTcloud/Back] <Center>' in asked(vm), f'{got!r} {asked(vm)}')

# a pool type that is no keyword is not offered at all: step 1 needs an
# answer, and the one typed is taken
vm, got = fit_settings({'fit:*ptype*': '"kidney"'},
                       ['ROUnd', None, None])
check("FITABHD: a pool type that is no keyword is not offered",
      '<kidney>' not in asked(vm) and 'Pool type' in asked(vm)
      and isinstance(got, list) and got[0] == 'ROUnd',
      f'{got!r} {asked(vm)}')

# the miss share
for bad, shown in ((15, '<15>'), (-0.1, '<15>'), (0, '<15>')):
    vm, got = fit_settings({'fit:*miss-pct*': repr(bad)},
                           ['ROUnd', None, None])
    check(f"FITABHD: a miss knob of {bad} is offered as {shown}",
          'Percent of points allowed beyond %s' % shown in asked(vm),
          asked(vm))
    check("FITABHD: ...and Enter takes 0.15",
          isinstance(got, list) and abs(got[3] - 0.15) < 1e-9, repr(got))

# the four remembered answers are not LAZTUNE knobs any more
sys.path.insert(0, os.path.join(REPO, 'tools'))
import knobs  # noqa: E402

names = {k[0] for k in knobs.knobs_of(FITABHD)}
memories = {'fit:*ptype*', 'fit:*treat*', 'fit:*gtreat*', 'fit:*oasfam*'}
check("FITABHD: the four remembered answers are not offered as knobs",
      names and not (names & memories), repr(sorted(names & memories)))
check("FITABHD: ...while the real knobs still are",
      {'fit:*miss-pct*', 'fit:*tol-max*', 'fit:*ruler-layer*'} <= names,
      repr(len(names)))
# ...and a session still starts with them unset, and keeps a run's
vm = newvm(FITABHD)
check("FITABHD: the memories start unset",
      all(vm.loads(m) is NIL or vm.loads(m) is None for m in memories))
vm.loads('(setq fit:*treat* "Cut")')
vm.load(FITABHD)
check("FITABHD: reloading the file keeps what a run remembered",
      vm.loads('fit:*treat*') == 'Cut', repr(vm.loads('fit:*treat*')))

# -- POINTRENAMER ----------------------------------------------------------
for bad in (-6.0, 0.0, '"6"'):
    vm = newvm(POINTRENAMER, dimzin=1)
    vm.script, vm.prompts = [None], []
    try:
        got = vm.loads('(ptr:asklimit "How far off?" %s T)' % bad)
    except LispError as e:
        got = 'died: %s' % e
    check(f"POINTRENAMER: a band knob of {bad} is offered as <0'-6\">",
          any("<0'-6\">" in p for p, _ in vm.prompts), asked(vm))
    check("POINTRENAMER: ...and Enter takes 6.0",
          isinstance(got, float) and abs(got - 6.0) < 1e-9, repr(got))
for bad in (0, -3, 2.5, '"1"'):
    vm = newvm(POINTRENAMER)
    vm.script, vm.prompts = [None], []
    try:
        got = vm.loads('(ptr:asknum "Start the numbering at" %s T)' % bad)
    except LispError as e:
        got = 'died: %s' % e
    check(f"POINTRENAMER: a first-number knob of {bad} is offered as <1>",
          any('<1>' in p for p, _ in vm.prompts), asked(vm))
    check("POINTRENAMER: ...and Enter takes 1", got == 1, repr(got))
vm = newvm(POINTRENAMER)
vm.script, vm.prompts = [None], []
check("POINTRENAMER: a first number of 7 is still offered as it is",
      vm.loads('(ptr:asknum "Start the numbering at" 7 T)') == 7
      and any('<7>' in p for p, _ in vm.prompts), asked(vm))

# -- WCALST's cut cap ------------------------------------------------------
for knob, script in ((0, [None]), (-3, [None]), (0, [0])):
    vm = wc_vm()
    vm.loads('(setq wc:*maxfeat* %d)' % knob)
    ents, pick = wc_band(vm)
    try:
        vm.run('c:WCALST', [None, ents, pick] + script + [None, None])
        died = ''
    except LispError as e:
        died = str(e)
    txt = ''.join(vm.printed)
    how = 'Enter' if script == [None] else 'a typed 0'
    check(f"WCALST: a cap knob of {knob} is offered as <20>",
          any('Maximum darts + inserts [Back] <20>' in p
              for p, _ in vm.prompts), asked(vm))
    check(f"WCALST: ...and {how} runs with 20, to the end",
          not died and 'WCALST error' not in txt
          and 'target <1%: 14 dart(s), 0 insert(s) (max 20)' in txt,
          died or txt[-400:])


print()
if failures:
    print(f"{len(failures)} FAILED:")
    for f in failures:
        print("  - " + f)
    sys.exit(1)
print("all passed")
