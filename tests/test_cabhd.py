#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for CABHD.LSP -- ABHD's perimeter half plus the cutoff.

CABHD carries ABHD's fitter over word for word (tests/test_pool_fit.py
covers that maths), so what is checked here is the two things that make
it a different command:

  * THE POINT CUTOFF.  The survey runs past the pool and the perimeter
    must stop where the user says it does.  The whole of c:CABHD is
    driven in the AutoLISP VM against a 30-point survey whose first 18
    points trace a pool and whose last 12 are a step run parked well
    away from it, and the fit is checked to have used the 18 and
    ignored the 12 -- in the loop, in the report, and in the miss
    allowance.  The cutoff is then moved at a Redo, both ways.

  * NO POOL BOTTOM.  ABHD offers the floor once a perimeter is kept and
    CABHD must not: a stray hopper prompt would eat the script and the
    run would end with answers left over, which the VM treats as a
    failure.  The absence is also checked structurally, so a helper
    quietly copied back in gets caught.

Usage:  python3 tests/test_cabhd.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_cabhd.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import (VM, LispError, Ent, Dot, Sym, BUILTINS, NIL,  # noqa: E402
                    parse_all)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
#: always the lisp/ path -- VM.load remaps it to shared/parts/ (and loads
#: the library first) when CALOFIN_LISP_ROOT says so, which is how the
#: same tests check both tiers.
LSP = os.path.join(REPO, 'lisp', 'cabhd', 'CABHD.lsp')

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


# ---- builtins the shared VM does not carry yet ------------------------
# entmakex (entmake returning the new ename) and regapp: CABHD stamps
# every object it draws so it only ever erases its own, and every marker
# it makes goes through one or the other.
# getint: the VM's own pops the script raw, which would let a scripted
# "All" through even if the command forgot to offer it.  This one
# resolves the answer against the live initget list exactly as getdist
# does, so the keywords in the test scripts prove the prompt really
# offers them.

def _alist_dict(alist):
    d = {}
    for pair in alist:
        if isinstance(pair, Dot):
            d.setdefault(pair.a, pair.b)
        elif isinstance(pair, list) and pair:
            d.setdefault(pair[0], pair[1] if len(pair) == 2 else pair[1:])
    return d


def _entmakex(vm, a):
    """(entmakex alist) -- entmake returning the new ename.  A LAYER or
    LTYPE record goes into the symbol table rather than the drawing, so
    tblsearch / tblobjname can find it afterwards."""
    alist = a[0]
    d = _alist_dict(alist)
    if not hasattr(vm, 'layer_records'):
        vm.layer_records = {}
    if d.get(0) in ('LAYER', 'LTYPE'):
        vm.tables[d[0]].add(d[2])
        rec = Ent()
        vm.entdata[rec] = list(alist)
        vm.layer_records[d[2].upper()] = rec
        return rec
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = list(alist)
    return e


def _tblobjname(vm, a):
    return getattr(vm, 'layer_records', {}).get(a[1].upper(), NIL)


def _getint(vm, a):
    prompt = a[0] if a else ""
    v = vm.pop_script(prompt, 'getint')
    if v is None:
        if vm.initget_bits & 1:
            raise LispError("getint: Enter not allowed at %r" % prompt, vm)
        return NIL
    if isinstance(v, str):
        for kw in vm.initget_kws.split():
            caps = ''.join(c for c in kw if c.isupper()) or kw
            if v.upper() in (kw.upper(), caps.upper()):
                return kw
        raise LispError("getint: %r not among %r at %r"
                        % (v, vm.initget_kws, prompt), vm)
    v = int(v)
    if v == 0 and vm.initget_bits & 2:
        raise LispError("getint: zero not allowed at %r" % prompt, vm)
    if v < 0 and vm.initget_bits & 4:
        raise LispError("getint: negative not allowed at %r" % prompt, vm)
    return v


# ssget "_X": a database query, not a prompt.  CABHD makes three of
# them - the leftover-marker sweep, the count of earlier fits on
# POOL-FIT, and the miss-ring purge - and none of them is a question
# the user answers, so they are served from the VM's own entity list
# instead of eating a scripted answer.
_ssget = BUILTINS[Sym('ssget')]


def _ssget_db(vm, a):
    if any(isinstance(x, str) and x.upper() == '_X' for x in a):
        filt = next((x for x in a if isinstance(x, list) and x
                     and isinstance(x[0], (Dot, list))), None)
        ents = [e for e in vm.entities if e not in vm.deleted]
        if filt:
            pairs = [(g.a, g.b) for g in filt if isinstance(g, Dot)]
            ents = [e for e in ents if lispvm._filt_hit(vm, e, pairs)]
        return ['<ss>'] + ents if ents else NIL
    return _ssget(vm, a)


BUILTINS[Sym('ssget')] = _ssget_db
BUILTINS[Sym('entmakex')] = _entmakex
BUILTINS[Sym('tblobjname')] = _tblobjname
BUILTINS[Sym('regapp')] = lambda vm, a: (a[0] if a else NIL)
BUILTINS[Sym('getint')] = _getint


# ---- the survey -------------------------------------------------------
# Points 1-18 ring a 24 x 14 ft pool.  Points 19-30 are the step run:
# a straight row parked 40 ft north of it, far enough that a perimeter
# which swallowed them could not possibly be mistaken for one that did
# not.  Drawing units are inches, as everywhere in this repo.

def pool_points(n=18):
    """N points around an ellipse 24 ft x 14 ft, centred on the origin."""
    out = []
    for i in range(n):
        th = 2.0 * math.pi * i / n
        out.append((144.0 * math.cos(th), 84.0 * math.sin(th)))
    return out


def step_points(n=12):
    """N points in a row well clear of the pool - the shots CABHD's
    cutoff is there to leave out."""
    return [(-100.0 + 20.0 * i, 480.0) for i in range(n)]


POOL = pool_points()
STEPS = step_points()
SURVEY = POOL + STEPS                      # numbered 1..30 in this order


def survey_vm(pts=None):
    """A VM with CABHD loaded and one ab_pt block insert per survey
    point, numbered from 1 in list order.  Returns (vm, [ename, ...])."""
    vm = VM()
    vm.load(LSP)
    ents = []
    for i, p in enumerate(pts if pts is not None else SURVEY, start=1):
        vm.loads('(entmake \'((0 . "INSERT") (2 . "ab_pt") (8 . "POINTS")'
                 ' (10 %.6f %.6f 0.0)))' % (p[0], p[1]))
        en = vm.entities[-1]
        # the number attribute, as an ATTRIB following the insert
        vm.loads('(entmake \'((0 . "ATTRIB") (8 . "POINTS") (2 . "number")'
                 ' (1 . "%d")))' % i)
        ents.append(en)
    return vm, ents


def group(vm, e, code):
    """Every value an entity carries under one DXF group code.  Pairs
    made by (cons 10 pt) come back as lists, not dotted pairs - AutoLISP
    conses an atom onto a list into a list - so both shapes are read."""
    out = []
    for pair in vm.entdata.get(e, []):
        if isinstance(pair, Dot) and pair.a == code:
            out.append(pair.b)
        elif isinstance(pair, list) and pair and pair[0] == code:
            out.append(pair[1] if len(pair) == 2 else pair[1:])
    return out


def kept_polyline(vm):
    """The LWPOLYLINE the run left on the POOL layer, as its vertices."""
    for e in reversed(vm.entities):
        if e in vm.deleted:
            continue
        if (group(vm, e, 0)[:1] == ['LWPOLYLINE']
                and group(vm, e, 8)[:1] == ['POOL']):
            return [list(v) for v in group(vm, e, 10)]
    return None


def answers(vm, kind):
    """Every prompt of one kind the run asked, in order."""
    return [p for p, _v in vm.prompts if kind.lower() in p.lower()]


# The six questions ahead of the selection, answered plainly: 1 inch,
# the standard miss share, no curve cap, no walls, no corners, no holds.
SETTINGS = [None, None, None, "No", "No", "No"]


def run(cut, extra=None, pts=None, keep="2"):
    """Drive c:CABHD once over the survey with CUT as the cutoff answer
    and KEEP as the choice of fit.  EXTRA is appended after the choice
    (a Redo's answers).  Returns the VM."""
    vm, ents = survey_vm(pts)
    script = SETTINGS + [ents, cut, keep] + list(extra or [])
    vm.run('c:CABHD', script)
    return vm


print('CABHD -- the file itself')
src = open(LSP).read()
check('the commands are CABHD and its version banner',
      re.findall(r'^\(defun\s+c:(\S+)', src, re.M) == ['CABHDVER', 'CABHD'])
defuns = re.findall(r'^\(defun\s+(\S+)', src, re.M)
calls = set(re.findall(r'\((cab:[a-z0-9?*!-]+)', src))
check('no helper is named for the bottom, the hopper or a dimension',
      not [n for n in defuns
           if re.search(r'hopper|bottom|slope|dim|off-at|break', n, re.I)])
check('nothing calls a helper this file does not define',
      not (calls - set(defuns)))
check('the version banner is the one release_lisp.py stamps',
      bool(re.search(r'\*cabhd-version\*\s+"v\d+\.\d+"', src)))
check('no exit is silent: the error handler always names the step',
      '" (cancelled)."' in src and 'CABHD done (last step: ' in src)
check('every helper is under one prefix (cab:)',
      all(n.startswith('cab:') or n.startswith('c:')
          for n in re.findall(r'^\(defun\s+(\S+)', src, re.M)))

print('CABHD -- the whole survey, no cutoff')
vm = run(None)
verts = kept_polyline(vm)
check('a closed perimeter was drawn on the POOL layer', bool(verts))
check('with no cutoff it runs right through the step row',
      verts is not None and max(v[1] for v in verts) > 400.0)

print('CABHD -- cut at Pt.18: the pool, not the steps')
vm = run(18)
verts = kept_polyline(vm)
check('a perimeter was drawn', bool(verts))
check('no vertex reaches the step run',
      verts is not None and max(v[1] for v in verts) < 200.0)
check('it spans the pool it was given',
      verts is not None
      and max(v[0] for v in verts) > 130.0
      and min(v[0] for v in verts) < -130.0)
# every span of the fit ends ON a survey point, so each vertex must be
# one of the 18 the cutoff kept - never one of the 12 it dropped
check('every vertex sits on one of the points the cutoff kept',
      verts is not None
      and all(min(math.dist(v[:2], q) for q in POOL) < 1e-6 for v in verts))
check('and none of them sits on a step point',
      verts is not None
      and all(min(math.dist(v[:2], q) for q in STEPS) > 1.0 for v in verts))
print('CABHD -- the cutoff is offered as a keyword, not just a number')
# "A" resolves to All only if the command really put All on the prompt
vm = run("A")
check('All keeps every point (same as Enter)',
      kept_polyline(vm) is not None
      and max(v[1] for v in kept_polyline(vm)) > 400.0)
print('CABHD -- Pick reads a number off the drawing')
vm, ents = survey_vm()
vm.run('c:CABHD', SETTINGS + [ents, "Pick", POOL[17], "2"])
verts = kept_polyline(vm)
check('picking Pt.18 cuts exactly where typing 18 does',
      verts is not None and max(v[1] for v in verts) < 200.0)

print('CABHD -- a cutoff that starves the fit is refused and re-asked')
vm, ents = survey_vm()
vm.run('c:CABHD', SETTINGS + [ents, 2, 18, "2"])
check('the too-small answer was rejected, the second one used',
      len(answers(vm, 'Include points up to')) == 2)
check('and the fit that came out is the pool',
      kept_polyline(vm) is not None
      and max(v[1] for v in kept_polyline(vm)) < 200.0)

print('CABHD -- the cutoff moves at a Redo')
vm, ents = survey_vm()
#            select   cut   Redo   omit:none  cutoff  walls corners holds
#            then the three numbers again, then keep fit 2
vm.run('c:CABHD', SETTINGS + [ents, 18, "Redo",
                              None,            # nothing to omit
                              "All",           # put every point back
                              "Keep", "Keep", "Keep",  # walls/corners/holds
                              None, None, None,  # tol / pct / cap
                              "2"])
verts = kept_polyline(vm)
check('All at the Redo brings the step points back',
      verts is not None and max(v[1] for v in verts) > 400.0)
check('the cutoff was asked twice - once per pass',
      len(answers(vm, 'Include points up to')) == 2)

vm, ents = survey_vm()
vm.run('c:CABHD', SETTINGS + [ents, None, "Redo",
                              None,            # nothing to omit
                              18,              # now cut the steps off
                              "Keep", "Keep", "Keep",
                              None, None, None,
                              "2"])
verts = kept_polyline(vm)
check('a cutoff typed at the Redo drops the step points',
      verts is not None and max(v[1] for v in verts) < 200.0)

print('CABHD -- it stops at the perimeter')
vm = run(18)
asked = ' | '.join(p for p, _v in vm.prompts).lower()
check('no shallow break was asked for', 'shallow' not in asked)
check('no deep break was asked for', 'deep' not in asked)
check('no offset was asked for', 'offset' not in asked)
check('the script ran out exactly at the end of the run', not vm.script)

print('CABHD -- no run ends without saying so')
# The complaint this section exists for: a run that stops after the
# cutoff prompt and leaves nothing on screen must SAY that it stopped,
# and say where.  Every ending is checked, not just the happy one.
vm = run(18)
check('a kept fit signs off naming the step it reached',
      'CABHD done (last step:' in ' '.join(vm.printed))
check('and it reported the cutoff it applied',
      any('Up to Pt.18' in s for s in vm.printed))

vm, ents = survey_vm()
vm.run('c:CABHD', SETTINGS + [ents, 18, "None"])
check('erasing all three still signs off',
      'CABHD done (last step:' in ' '.join(vm.printed))

vm, ents = survey_vm()
vm.run('c:CABHD', SETTINGS + [None])          # nothing selected
said = ' '.join(vm.printed)
check('an empty selection is explained and signed off',
      'Nothing usable selected' in said and 'CABHD done (last step:' in said)

vm, ents = survey_vm(POOL[:2])                # too few to make a shape
vm.run('c:CABHD', SETTINGS + [ents])
said = ' '.join(vm.printed)
check('too few points is explained and signed off',
      'at least 3' in said and 'CABHD done (last step:' in said)
check('and nothing was drawn on the POOL layer', kept_polyline(vm) is None)

print('CABHD -- one candidate failing to draw does not kill the other two')
# The tight fit has to thread every point at *CAB-TIGHT-TOL* with no
# miss allowance, so on a real survey it is the one that can come out
# too degenerate for AutoCAD to accept - and AutoCAD answers entmake
# with nil rather than raising.  Refusing the outline by its preview
# colour reproduces that exactly: the run must carry on with the two
# that did draw, instead of giving up on all three.
_mkx = BUILTINS[Sym('entmakex')]


def refusing(colours):
    """entmakex that hands back nil for an LWPOLYLINE in these colours."""
    def f(vm, a):
        d = _alist_dict(a[0])
        if d.get(0) == 'LWPOLYLINE' and d.get(62) in colours:
            return NIL
        return _mkx(vm, a)
    return f


def with_refusal(colours, script):
    vm, ents = survey_vm()                 # built before anything is refused
    BUILTINS[Sym('entmakex')] = refusing(colours)
    try:
        vm.run('c:CABHD', SETTINGS + script(ents))
    finally:
        BUILTINS[Sym('entmakex')] = _mkx
    return vm


vm = with_refusal({1}, lambda e: [e, 18, "2"])     # 1 = the tight fit
said = ' '.join(vm.printed)
check('the run carries on and keeps a fit that did draw',
      kept_polyline(vm) is not None)
check('the table says which candidate did not draw', 'would not draw' in said)
check('and it does not claim three are on screen',
      '2 candidate fit(s) are now drawn' in said)

vm = with_refusal({1}, lambda e: [e, 18, "1"])     # pick the missing one
said = ' '.join(vm.printed)
check('picking the missing fit says so instead of reporting on it',
      'never drew - there is nothing to keep' in said)
check('and nothing landed on the POOL layer', kept_polyline(vm) is None)

vm = with_refusal({1, 2, 4}, lambda e: [e, 18])    # every one refused
said = ' '.join(vm.printed)
check('no candidate drawing at all is explained, not swallowed',
      'none of the' in said and 'would draw' in said)
check('and that run signs off too', 'CABHD done (last step:' in said)

print('CABHD -- a survey with no numbers falls back to selection order')
vm = VM()
vm.load(LSP)
ents = []
for p in SURVEY:
    vm.loads('(entmake \'((0 . "POINT") (8 . "POINTS")'
             ' (10 %.6f %.6f 0.0)))' % (p[0], p[1]))
    ents.append(vm.entities[-1])
vm.run('c:CABHD', SETTINGS + [ents, 18, "2"])
verts = kept_polyline(vm)
check('the 18th selected point is the cutoff',
      verts is not None and max(v[1] for v in verts) < 200.0)

print('CABHD -- the number is read out of the label, digits first')
vm = VM()
vm.load(LSP)
vm.loads('(defun t:num (s) (if (cab:num-in s) (cab:num-in s) -1))')
for label, want in (("17", 17), ("P17", 17), ("17A", 17), ("PT-8", 8),
                    ("100", 100), ("", -1), ("edge", -1)):
    got = vm.loads('(t:num "%s")' % label)
    check('"%s" reads as %s' % (label, want), got == want)

print()
if failures:
    print('%d FAILURE(S):' % len(failures))
    for f in failures:
        print('  - ' + f)
    sys.exit(1)
print('ALL CABHD CHECKS PASSED')
