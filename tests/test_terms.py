"""SHOP TERMS: drawing text a shop may spell its own way, end to end.

tools/terms.py names two terms -- typ-note (" Typ.", the suffix on the
one dimension that stands for a group of equal ones) and ng-note ("Not
Given", the note on a corner the order sheet never gave).  Each tool
that writes one reads it into a tunables knob through its term reader,
from the profile's CalofinTerm-<id>; LAZTUNE's Terms page sets that and
moves every loaded member at once.  The defects this exists to catch:

1. A tool that still writes the shipped wording where the shop chose
   another -- POOL, SPA, NORMIESTEP, HONEFILLET, SMARTFILLET and AUTODIM
   are each driven with CalofinTerm-* set before load, and must write
   the shop's words exactly where they wrote the shipped ones.
2. A term that changes the drawing when nobody set one: with an empty
   profile every tool writes exactly what it wrote before.
3. The precedence -- shipped < shop term < a per-tool LAZTUNE knob --
   broken either way: a Terms change that tramples a drafter's own
   knob value, or a knob cleared back PAST the shop's term.
4. A term setter that accepts an empty spelling (a callout whose note
   is gone), or a Terms page that trims the space off " Typ.".
5. The per-tool readers drifting apart: every copy is one text.
6. LAZBACKUP losing the shop's terms (or their leading space).

Both tiers: CALOFIN_LISP_ROOT=shared remaps every load onto the grouped
build, where the reader is cal:term.

Run: python3 tests/test_terms.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_terms.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
from lispvm import VM, Dot, Ent, LispError, Sym  # noqa: E402
import check_terms  # noqa: E402
import terms as termsmod  # noqa: E402

ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
REPO = os.path.join(HERE, '..')


def L(*p):
    return os.path.join(REPO, 'lisp', *p)


POOL = L('pool', 'POOL.LSP')
SPA = L('spa', 'SPA.LSP')
NORMIE = L('cornerstp', 'NORMIESTEP.lsp')
HONE = L('honefillet', 'HONEFILLET.lsp')
SMART = L('smartfillet', 'SMARTFILLET.lsp')
AUTODIM = L('autodim', 'AutoDim.lsp')
PANEL = L('lazpanel', 'LAZPANEL.lsp')

SHOP = {'CalofinTerm-typ-note': ' TYP', 'CalofinTerm-ng-note': 'NOT GIVEN (VERIFY)'}

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + str(detail)) if detail else ''))
        FAILS.append(label)


def fresh(files, env=None, setenv_forms=True):
    """A VM with ENV in the profile BEFORE the FILES load -- written with
    (setenv ...), the way a shop's LAZTUNE left it."""
    vm = VM()
    for k, v in (env or {}).items():
        if setenv_forms:
            vm.loads('(setenv "%s" "%s")'
                     % (k, v.replace('\\', '\\\\').replace('"', '\\"')))
        else:
            vm.env[k] = v
    for f in files:
        vm.load(f)                  # CALOFIN_LISP_ROOT picks the tier
    return vm


def g(vm, name):
    v = vm.globals.get(Sym(name))
    return None if v is None else v


def override(c):
    for i, x in enumerate(c[:-1]):
        if isinstance(x, str) and x.upper() == '_T' and isinstance(c[i + 1], str):
            return c[i + 1]
    return None


def marks(vm):
    return [override(c) for c in vm.commands
            if c and c[0] == '_.DIMRADIUS'
            and str(override(c)).startswith(('90%%d', '?'))]


def notes(vm):
    return [c[-2] for c in vm.commands if c and c[0] == '_.LEADER']


def texts(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = dict((x.a, x.b) for x in vm.entdata[e] if isinstance(x, Dot))
        if d.get(0) == 'TEXT':
            out.append(d.get(1))
    return out


BASE = (0.0, 0.0, 0.0)


def pool_run(vm, script):
    try:
        vm.run('c:POOL', script)
    except LispError as e:
        raise AssertionError("POOL: %s" % e) from None
    return vm


#: every corner NotGiven, in square: ONE boxed "?" mark carrying the Typ.
#: suffix, and its Not Given note on a leader
POOL_NG = ["Insquare", "Rectangle", BASE, 480.0, 240.0, "NotGiven", "No"]
#: out of square, cross dims that fail, Given marks opted into: each
#: NotGiven corner row is marked with the same note in the report
POOL_GIVEN = ["Outofsquare", "Rectangle", BASE, 240.0, 240.0, 120.0, 120.0,
              "NotGiven", None, None, None, 268.0, 400.0, "No", "Yes", None]


#: a lazy L with radius OUTER corners: the one outer Typ. callout that
#: pool:dimtreat1's L caller hands the suffix
POOL_LAZYL = ["Insquare", "LA", BASE, 296.0, 167.6, 167.6, 99.0, 226.0, 168.0,
              "Yes", "Radius", 24.0, "Cut", 18.0, "No", "No"]
#: a grecian, every corner the same radius: pool:dimringcorners' one
#: Typ. callout for the whole ring (the grecflow / ring-shape caller)
POOL_GRECIAN = ["Insquare", "Grecian", BASE, "Overall", 480.0, 200.0,
                "NA", "NA", "NA", "NA", "NA", "Yes", "Radius", 12.0,
                None, None, "No"]


def radcallouts(vm):
    return [override(c) for c in vm.commands
            if c and c[0] == '_.DIMRADIUS' and str(override(c)).startswith('<>')]


def spa_run(vm, script):
    try:
        vm.run('c:SPA', script)
    except LispError as e:
        raise AssertionError("SPA: %s" % e) from None
    return vm


#: all four corners NotGiven, and an all-Diagonal pair of outlines (the
#: cut callout's "<> Typ.")
SPA_NG = [None, 'Coversize', 'Rectangle', None, 84.0, 60.0,
          'Yes', 'NotGiven', 'No', 'No']
SPA_CUT = [None, 'Coversize', 'Rectangle', None, 84.0, 60.0,
           'Yes', 'Diagonal', 10.0, 'No', 'Yes', 'Offset', 3.0]


def spa_vm(env=None):
    vm = fresh([SPA], env)
    return vm


def aligned(vm):
    return [override(c) for c in vm.commands if c and c[0] == '_.DIMALIGNED']


def normie_run(treatment, env=None):
    vm = fresh([NORMIE], env)
    vm.tables['DIMSTYLE'].add('STANDARD INCHES')
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48.0
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 200.0 0.0 0.0)))')
    picked = list(vm.entities)
    script = [None, picked, (100.0, 50.0), 60.0, treatment, "No",
              24.0, 24.0, None, "No"]
    try:
        vm.run('c:NORMIESTEP', script)
    except LispError as e:
        raise AssertionError("NORMIESTEP: %s" % e) from None
    return vm


def typit(path, fn, env=None):
    """HONEFILLET's / SMARTFILLET's re-lettering of the one radius
    callout as typical, on a dimension that reads its measurement."""
    vm = fresh([path], env)
    vm.loads('(setq t:*d* (entmake (list (cons 0 "DIMENSION") (cons 1 "")'
             ' (cons 8 "0"))))')
    vm.loads('(setq t:*d* (entlast))')
    vm.loads('(%s t:*d*)' % fn)
    vm.loads('(setq t:*txt* (cdr (assoc 1 (entget t:*d*))))')
    return str(vm.globals.get(Sym('t:*txt*')))


PERIM = """
  (defun ad:ssbox (ss)    (list (list 0.0 0.0 0.0) (list 240.0 240.0 0.0)))
  (defun cal:bbox-ss (ss) (list (list 0.0 0.0 0.0) (list 240.0 240.0 0.0)))
  (defun ad:perimang (p1 p2 diag eps ss) (* 0.5 pi))
  (defun ad:arcang (centre mid diag eps ss) (angle centre mid))"""


def autodim_notes(env=None):
    """Two equal sides: AUTODIM dimensions one and notes it typical."""
    vm = fresh([AUTODIM], env)
    vm.tables['DIMSTYLE'] = {'STANDARD', 'SIDE STANDARD', 'STANDARD INCHES'}
    vm.script = [None]
    vm.loads('(ad:begin)')
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48
    for (x1, y1), (x2, y2) in (((0, 0), (60, 0)), ((0, 40), (60, 40))):
        vm.loads('(entmake (list (cons 0 "LINE") (cons 10 (list %.1f %.1f 0.0))'
                 ' (cons 11 (list %.1f %.1f 0.0))))' % (x1, y1, x2, y2))
    vm.script = [list(vm.entities)]
    vm.loads('(setq SS (ssget))')
    vm.loads(PERIM)
    vm.loads('(ad:dimperim SS nil)')
    return [c[c.index('_T') + 1] for c in vm.commands
            if c and c[0] == '_.DIMALIGNED' and '_T' in c]


# =====================================================================
print("== 1. no shop term: every tool writes what it always wrote ==")

vm = pool_run(fresh([POOL]), POOL_NG)
check("POOL: one '? Typ.' mark", marks(vm) == ['? Typ.'], marks(vm))
check("POOL: its note reads 'Not Given'", notes(vm) == ['Not Given'], notes(vm))
vm = pool_run(fresh([POOL]), POOL_GIVEN)
check("POOL: the report marks each NotGiven row 'Not Given'",
      texts(vm).count('Not Given') == 4, texts(vm))
for sc, what in ((POOL_LAZYL, "lazy L's outer corners"),
                 (POOL_GRECIAN, "grecian ring")):
    vm = pool_run(fresh([POOL]), sc)
    check("POOL: the %s callout reads '<> Typ.'" % what,
          radcallouts(vm) == ['<> Typ.'], radcallouts(vm))
vm = spa_run(spa_vm(), SPA_NG)
check("SPA: one '? Typ.' mark", marks(vm) == ['? Typ.'], marks(vm))
check("SPA: its note reads 'Not Given'", notes(vm) == ['Not Given'], notes(vm))
vm = spa_run(spa_vm(), SPA_CUT)
check("SPA: one '<> Typ.' cut callout per outline",
      aligned(vm) == ['<> Typ.', '<> Typ.'], aligned(vm))
vm = normie_run("NotGiven")
check("NORMIESTEP: one '? Typ.' mark", marks(vm) == ['? Typ.'], marks(vm))
check("NORMIESTEP: its note reads 'Not Given'", notes(vm) == ['Not Given'], notes(vm))
check("HONEFILLET: the callout reads '<> Typ.'", typit(HONE, 'hn:typit') == '<> Typ.')
check("SMARTFILLET: the callout reads '<> Typ.'", typit(SMART, 'sf:typit') == '<> Typ.')
check("AUTODIM: the one dim reads '<> Typ.'", autodim_notes() == ['<> Typ.'],
      autodim_notes())


# =====================================================================
print("== 2. the shop's terms, set before load, are what each tool writes ==")

vm = pool_run(fresh([POOL], SHOP), POOL_NG)
check("POOL: '? TYP'", marks(vm) == ['? TYP'], marks(vm))
check("POOL: 'NOT GIVEN (VERIFY)' on the leader", notes(vm) == ['NOT GIVEN (VERIFY)'],
      notes(vm))
vm = pool_run(fresh([POOL], SHOP), POOL_GIVEN)
check("POOL: the report's Given marks carry the shop's note",
      texts(vm).count('NOT GIVEN (VERIFY)') == 4 and 'Not Given' not in texts(vm),
      texts(vm))
for sc, what in ((POOL_LAZYL, "lazy L's outer corners"),
                 (POOL_GRECIAN, "grecian ring")):
    vm = pool_run(fresh([POOL], SHOP), sc)
    check("POOL: the %s callout reads '<> TYP'" % what,
          radcallouts(vm) == ['<> TYP'], radcallouts(vm))
vm = spa_run(spa_vm(SHOP), SPA_NG)
check("SPA: '? TYP'", marks(vm) == ['? TYP'], marks(vm))
check("SPA: 'NOT GIVEN (VERIFY)' on the leader", notes(vm) == ['NOT GIVEN (VERIFY)'],
      notes(vm))
vm = spa_run(spa_vm(SHOP), SPA_CUT)
check("SPA: '<> TYP' on both cut callouts", aligned(vm) == ['<> TYP', '<> TYP'],
      aligned(vm))
vm = normie_run("NotGiven", SHOP)
check("NORMIESTEP: '? TYP'", marks(vm) == ['? TYP'], marks(vm))
check("NORMIESTEP: 'NOT GIVEN (VERIFY)'", notes(vm) == ['NOT GIVEN (VERIFY)'], notes(vm))
vm = normie_run("Square", SHOP)
check("NORMIESTEP: '90%%d TYP' on a square run", marks(vm) == ['90%%d TYP'], marks(vm))
check("HONEFILLET: '<> TYP'", typit(HONE, 'hn:typit', SHOP) == '<> TYP')
check("SMARTFILLET: '<> TYP'", typit(SMART, 'sf:typit', SHOP) == '<> TYP')
check("AUTODIM: '<> TYP'", autodim_notes(SHOP) == ['<> TYP'], autodim_notes(SHOP))
# an empty profile value is no spelling at all: the shipped one
vm = pool_run(fresh([POOL], {'CalofinTerm-typ-note': ''}), POOL_NG)
check("an empty CalofinTerm-* is the shipped wording", marks(vm) == ['? Typ.'],
      marks(vm))
# a standalone APPLOAD re-reads the profile
vm = fresh([POOL])
vm.loads('(setenv "CalofinTerm-typ-note" " TYP")')
vm.load(POOL)
check("re-loading POOL reads the profile again", g(vm, 'pool:*typ-note*') == ' TYP',
      g(vm, 'pool:*typ-note*'))
# ...and so does NORMIESTEP, whose term knobs sit under the step
# family's boundp guard: a knob still holding what the last load read
# follows the profile; one holding the drafter's own value is kept
vm = fresh([NORMIE])
vm.loads('(setenv "CalofinTerm-ng-note" "NG2")')
vm.load(NORMIE)
check("re-loading NORMIESTEP reads the profile again", g(vm, '*cs-ng-note*') == 'NG2',
      g(vm, '*cs-ng-note*'))
vm.loads('(setenv "CalofinTerm-ng-note" "")')
vm.load(NORMIE)
check("...and back to the shipped wording when the profile is cleared",
      g(vm, '*cs-ng-note*') == 'Not Given', g(vm, '*cs-ng-note*'))
vm.loads('(setq *cs-ng-note* "MINE") (setenv "CalofinTerm-ng-note" "NG3")')
vm.load(NORMIE)
check("...but a value of the drafter's own survives the re-load",
      g(vm, '*cs-ng-note*') == 'MINE', g(vm, '*cs-ng-note*'))
check("...while the other term still follows", g(vm, '*cs-typ-note*') == ' Typ.',
      g(vm, '*cs-typ-note*'))

# the fillet tools' command-line summary names what the callout reads,
# one space before it whether or not the shop's term starts with one
import test_honefillet as th  # noqa: E402
import test_smartfillet as ts  # noqa: E402


def fillet_said(mod, knob, value, script):
    vm = mod.newvm()
    if value is not None:
        vm.loads('(setq %s "%s")' % (knob, value))
    e1, e2 = mod.corner(vm) if hasattr(mod, 'corner') else (
        mod.line(vm, (0, 0), (100, 0)), mod.line(vm, (0, 0), (0, 100)))
    e3 = mod.line(vm, (200, 0), (300, 0))
    e4 = mod.line(vm, (300, 0), (300, 100))
    mod.run(vm, script(mod, e1, e2, e3, e4), 'terms')
    return mod.said(vm)


def hone_script(mod, e1, e2, e3, e4):
    return ([[e1, [50.0, 0.0, 0.0]], [e2, [0.0, 50.0, 0.0]]]
            + [mod.clicker(12.0), mod.clicker(18.0), mod.clicker(13.5), 'Yes',
               [e3, [250.0, 0.0, 0.0]], [e4, [300.0, 50.0, 0.0]], None])


def smart_script(mod, e1, e2, e3, e4):
    return [[e1, [50.0, 0.0, 0.0]], [e2, [0.0, 50.0, 0.0]], mod.clicker(12.0),
            'Yes', [e3, [250.0, 0.0, 0.0]], [e4, [300.0, 50.0, 0.0]], None]


for mod, knob, script, name in ((th, 'hn:*typ-note*', hone_script, 'HONEFILLET'),
                                (ts, 'sf:*typ-note*', smart_script, 'SMARTFILLET')):
    out = fillet_said(mod, knob, None, script)
    check("%s: the shipped summary is unchanged ('now reads Typ.')" % name,
          'the one dimension now reads Typ.' in out, out[-160:])
    out = fillet_said(mod, knob, 'TYP', script)
    check("%s: a term with no leading space still reads 'now reads TYP'" % name,
          'now reads TYP' in out and 'readsTYP' not in out, out[-160:])


# =====================================================================
print("== 3. LAZTUNE's term setter, in a session that has the tools ==")


def session(env=None):
    return fresh([POOL, SPA, NORMIE, HONE, SMART, AUTODIM, PANEL], env)


MEMBERS = {t['id']: t['members'] for t in termsmod.TERMS}

vm = session()
vm.loads('(setq t:*r* (lzp:term-set "typ-note" " TYP"))')
check("the setter moves all six typ-note members", g(vm, 't:*r*') == 6, g(vm, 't:*r*'))
check("...writing the profile", vm.env.get('CalofinTerm-typ-note') == ' TYP',
      vm.env.get('CalofinTerm-typ-note'))
check("...and every member global", all(g(vm, m) == ' TYP' for m in MEMBERS['typ-note']),
      [(m, g(vm, m)) for m in MEMBERS['typ-note']])
vm.printed = []
pool_run(vm, POOL_NG)
check("the next POOL writes it", marks(vm) == ['? TYP'], marks(vm))
vm.loads('(setq t:*r* (lzp:term-set "ng-note" "N.G."))')
check("ng-note moves its three", g(vm, 't:*r*') == 3
      and all(g(vm, m) == 'N.G.' for m in MEMBERS['ng-note']))
vm.loads('(setq t:*r* (lzp:term-clear "typ-note"))')
check("Alec's choice puts ' Typ.' back everywhere",
      all(g(vm, m) == ' Typ.' for m in MEMBERS['typ-note'])
      and vm.env.get('CalofinTerm-typ-note') == '', vm.env.get('CalofinTerm-typ-note'))

# refused: empty, blank, an unknown term -- and nothing changes
for bad, why in (('""', 'empty'), ('"   "', 'blank'), ('nil', 'not text')):
    vm.loads('(setq t:*r* (lzp:term-set "typ-note" %s))' % bad)
    check("a %s spelling is refused with a reason" % why,
          isinstance(g(vm, 't:*r*'), str) and g(vm, 'pool:*typ-note*') == ' Typ.',
          g(vm, 't:*r*'))
# ...and the characters the two places a term lands read as CODES:
# <> is the measurement again in dimension text, \\ and { } are
# MTEXT formatting a TEXT entity would print as typed
for bad, what in (('"<> Typ."', '<>'), ('"N\\\\PG"', 'backslash'),
                  ('"{N.G.}"', 'braces')):
    vm.loads('(setq t:*r* (lzp:term-set "ng-note" %s))' % bad)
    check("a spelling with %s is refused with a reason" % what,
          isinstance(g(vm, 't:*r*'), str) and g(vm, 'pool:*ng-note*') == 'N.G.',
          (g(vm, 't:*r*'), g(vm, 'pool:*ng-note*')))
vm.loads('(setq t:*r* (lzp:knob-why "pool:*typ-note*" "\\"<> TYP\\""))')
check("...and the same spelling set on one member knob is refused too",
      isinstance(g(vm, 't:*r*'), str) and '<>' in g(vm, 't:*r*'), g(vm, 't:*r*'))
vm.loads('(setq t:*r* (lzp:term-set "no-such" "x"))')
check("an unknown term is refused", g(vm, 't:*r*') == 'not a term this build has',
      g(vm, 't:*r*'))


print("== 4. precedence: shipped < the shop's term < a drafter's knob ==")

vm = session()
vm.loads('(lzp:knob-set "pool:*typ-note*" "\\" TYPICAL\\"")')
vm.loads('(lzp:knobs-apply)')
vm.loads('(lzp:term-set "typ-note" " TYP")')
check("a per-tool knob value wins over a Terms change",
      g(vm, 'pool:*typ-note*') == ' TYPICAL', g(vm, 'pool:*typ-note*'))
check("...and every other member takes the term", g(vm, 'spa:*typ-note*') == ' TYP',
      g(vm, 'spa:*typ-note*'))
vm.loads('(lzp:knob-clear "pool:*typ-note*")')
vm.loads('(lzp:knob-restore "pool:*typ-note*")')
check("clearing the knob hands it back to the SHOP's term, not past it",
      g(vm, 'pool:*typ-note*') == ' TYP', g(vm, 'pool:*typ-note*'))

# at load: LAZPANEL applies the knob over what POOL read from the term
vm = session({'CalofinTerm-typ-note': ' TYP',
              'CalofinKnobs': 'pool:*typ-note*',
              'CalofinKnob-pool.~typ-note~': '" TYPICAL"'})
check("at load the knob beats the term", g(vm, 'pool:*typ-note*') == ' TYPICAL',
      g(vm, 'pool:*typ-note*'))
check("...which still reaches the rest", g(vm, 'ad:*typ-note*') == ' TYP',
      g(vm, 'ad:*typ-note*'))
pool_run(vm, POOL_NG)
check("...and POOL draws the knob's", marks(vm) == ['? TYPICAL'], marks(vm))


# a per-tool value holding a member apart is NAMED, not hidden behind
# "every tool": the Terms page's state line and LAZTUNE's report say so
vm = session()
vm.loads('(lzp:knob-set "pool:*typ-note*" "\\" TYPICAL\\"") (lzp:knobs-apply)')
vm.loads('(setq t:*h* (lzp:term-held "typ-note"))')
check("the term knows POOL holds its own value", g(vm, 't:*h*') == ['POOL'],
      g(vm, 't:*h*'))
vm.printed = []
vm.loads('(lzp:tune-report (list 0 0 1 (lzp:term-held "typ-note")))')
out = ''.join(str(x) for x in vm.printed)
check("...and the report names it instead of claiming every tool",
      'except POOL, which keeps a value set on its own knob' in out, out)


print("== 5. the Terms page of LAZTUNE ==")

vm = session()
vm.loads('(defun start_list (k) k) (defun add_list (s) (setq t:*rows* (cons s t:*rows*)) s)'
         ' (defun end_list () nil) (defun set_tile (k v) (setq t:*tiles* (cons (cons k v) t:*tiles*)) v)'
         ' (defun mode_tile (k m) (if (= m 1) (setq t:*off* (cons k t:*off*))) t)'
         ' (defun done_dialog (s) (setq t:*done* s))')
vm.loads('(setq lzp:*tunetool* (length lzp:*knobs*) lzp:*tunesel* nil t:*rows* nil'
         ' lzp:*termvals* nil)')
vm.loads('(lzp:tune-refill)')
rows = [str(r) for r in reversed(vm.globals.get(Sym('t:*rows*')) or [])]
check("the page lists every term", [r.split('  =  ')[0] for r in rows]
      == [t['id'] for t in termsmod.TERMS], rows)
check("...its value QUOTED, so the leading space shows",
      rows[0].startswith('typ-note  =  " Typ."'), rows[0])


def tile(key):
    for p in vm.globals.get(Sym('t:*tiles*')) or []:
        if str(p.a if hasattr(p, 'a') else p[0]) == key:
            return str(p.b if hasattr(p, 'b') else p[1])
    return None


check("the box holds ' Typ.' with its space", tile('tune_val') == ' Typ.', tile('tune_val'))
check("the meaning line names the tools that write it",
      'POOL' in (tile('tune_meaning') or '') and 'AUTODIM' in (tile('tune_meaning') or ''),
      tile('tune_meaning'))
vm.loads('(setq t:*off* nil) (lzp:tune-state)')
check("Set everywhere is greyed: a term already is everywhere",
      'tune_all' in [str(x) for x in vm.globals.get(Sym('t:*off*')) or []])
# an empty box greys OK and names why
vm.loads('(setq t:*off* nil) (lzp:tune-val "")')
check("an emptied box greys OK", 'accept' in [str(x) for x in vm.globals.get(Sym('t:*off*')) or []])
check("...and says a term cannot be empty", 'cannot be empty' in (tile('state') or ''),
      tile('state'))
vm.loads('(setq t:*done* nil) (lzp:tune-ok)')
check("...and OK will not close on it", vm.globals.get(Sym('t:*done*')) in (None, [])
      or str(vm.globals.get(Sym('t:*done*'))) == 'nil')
# typed with its leading space kept, then OK
vm.loads('(lzp:tune-val " TYP") (setq t:*res* (lzp:tune-write))')
check("OK writes the shop's spelling, space kept", vm.env.get('CalofinTerm-typ-note') == ' TYP',
      vm.env.get('CalofinTerm-typ-note'))
check("...and every loaded member follows at once",
      all(g(vm, m) == ' TYP' for m in MEMBERS['typ-note']))
res = vm.globals.get(Sym('t:*res*'))
check("...counted as one term changed", res and int(res[2]) == 1, res)
# Alec's choice
vm.loads('(setq lzp:*termvals* nil) (lzp:tune-reset) (lzp:tune-write)')
check("the Alec's choice button puts ' Typ.' back",
      vm.env.get('CalofinTerm-typ-note') == '' and g(vm, 'hn:*typ-note*') == ' Typ.',
      (vm.env.get('CalofinTerm-typ-note'), g(vm, 'hn:*typ-note*')))


# the held member on the Terms page's state line
vm.loads('(lzp:knob-set "pool:*typ-note*" "\\" TYPICAL\\"")'
         ' (setq lzp:*termvals* nil lzp:*tunesel* "typ-note") (lzp:tune-state)')
check("the Terms page's state line names the tool that keeps its own value",
      'except POOL' in (tile('state') or ''), tile('state'))

# "Set everywhere" on a MEMBER knob makes the value the shop term --
# it does not write six per-tool values the Terms page can then never
# move again (the precedence) without saying why
vm.loads('(setq lzp:*tunevals* nil lzp:*termvals* nil)')
tools = [str(r[0]) for r in vm.globals.get(Sym('lzp:*knobs*'))]
vm.loads('(setq lzp:*tunetool* %d lzp:*tunesel* "spa:*typ-note*")' % tools.index('SPA'))
vm.loads('(lzp:tune-put "spa:*typ-note*" "\\" TYPICAL\\"") (lzp:tune-all)')
check("...it turns the page to Terms, on the term",
      g(vm, 'lzp:*tunetool*') == len(tools) and g(vm, 'lzp:*tunesel*') == 'typ-note',
      (g(vm, 'lzp:*tunetool*'), g(vm, 'lzp:*tunesel*')))
vm.loads('(setq t:*res* (lzp:tune-write))')
check("...OK writes the term, not per-tool values",
      vm.env.get('CalofinTerm-typ-note') == ' TYPICAL'
      and not any(k.startswith('CalofinKnob-') and v for k, v in vm.env.items()),
      {k: v for k, v in vm.env.items() if k.startswith('Calofin')})
check("...so every member follows, POOL's old value released too",
      all(g(vm, m) == ' TYPICAL' for m in MEMBERS['typ-note']),
      [(m, g(vm, m)) for m in MEMBERS['typ-note']])
vm.loads('(lzp:term-set "typ-note" " TYP")')
check("...and the Terms page moves them all afterwards",
      all(g(vm, m) == ' TYP' for m in MEMBERS['typ-note']),
      [(m, g(vm, m)) for m in MEMBERS['typ-note']])


print("== 6. LAZBACKUP carries the shop's terms, space and all ==")

bv = session({'CalofinTerm-typ-note': ' TYP'})
bv.run('c:LAZBACKUP', ['Export', 'C:\\backup.txt'])
content = bv.files.get('C:\\backup.txt') or ''
check("exported under [Terms]", '[Terms]\ntyp-note= TYP' in content, content[-120:])
check("...and counted", '1 shop term' in ''.join(str(p) for p in bv.printed),
      ''.join(str(p) for p in bv.printed)[-200:])
iv = session()
iv.files['C:\\backup.txt'] = ('[Terms]\ntyp-note= TYP\nng-note=\nzz-note=x\n')
iv.loads('(defun vl-registry-write (k n s) s)')
iv.run('c:LAZBACKUP', ['Import', 'C:\\backup.txt'])
out = ''.join(str(p) for p in iv.printed)
check("imported with the space", iv.env.get('CalofinTerm-typ-note') == ' TYP'
      and g(iv, 'spa:*typ-note*') == ' TYP', iv.env.get('CalofinTerm-typ-note'))
check("an empty term is skipped with its reason", 'ng-note= (a term cannot be empty' in out, out)
check("an unknown term is skipped", 'zz-note=x (not a term this build has)' in out, out)


print("== 7. every reader is one text, and the check agrees ==")

files = check_terms.tree_files()
readers = {}
for rel, src in files.items():
    if not rel.startswith('lisp/'):
        continue
    for m in check_terms.READER_HEAD.finditer(src):
        end = check_terms.knobs.sexp_end(src, m.start())
        readers[rel] = src[m.start():end].replace(m.group(1) + 'term', 'X:term')
check("six tools carry a term reader", len(readers) == 6, sorted(readers))
check("...every one the same text but its prefix", len(set(readers.values())) == 1,
      set(readers.values()))
problems, _hits = check_terms.run()
check("tools/check_terms.py is clean on the tree", not problems, problems[:3])


print()
if FAILS:
    print("test_terms: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_terms: all checks passed (%s tier)" % ROOT)
