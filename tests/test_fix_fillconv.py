"""The quiet failures in XFTCONV/XFTRECONV, HONEFILLET, SMARTFILLET and
DDFIX that the stock VM could not see, each driven to the point where
the drafter would have been let down.

1. A handler that runs under *push-error-using-command* runs with the
   AutoLISP stack already unwound: every local of the command reads nil
   and every helper defined inside it is undefined.  The stock VM kept
   the frames live, so XFTCONV's handler (which called its own local
   xft:sysback) and HONEFILLET/SMARTFILLET's (which closed the undo
   group through a local flag) passed here and died in AutoCAD.  The
   VM models the error modes itself now (tests/test_lispvm_errmode.py):
   the stack is reset for a pushed handler, a bare (command) is refused
   in a handler that did not push, and a pop with nothing pushed fails
   the run.
2. The U hint XFTCONV printed on every way into its handler, including
   an Esc at the highlight before anything was touched.
3. SCALE, entdel and a sweep of the wrong space: XFTCONV scaling a
   highlight with a locked layer in it and counting what SCALE skipped,
   counting a refused erase as erased, and sweeping the sheet instead of
   the survey from inside a layout viewport; DDFIX scaling half a
   feature about a centre the skipped half still pulled on.
4. HONEFILLET/SMARTFILLET's run-time state sitting in the tunables
   block, where LAZTUNE offered a sysvar snapshot as a setting.
5. What review of those fixes turned up: XFTRECONV checking only its
   own blocks' layers for locks and counting what SCALE skipped as
   scaled back; a refusal whose only advice -- unlock it -- would have
   scaled a locked north arrow with the survey; and *xft-scale*, a
   LAZTUNE knob, reaching SCALE as a 0 or a negative, which SCALE
   refuses and then waits on.

Run: python3 tests/test_fix_fillconv.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_fix_fillconv.py
"""

import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
from lispvm import VM, LispError, Ent, Dot, Sym, NIL, T, BUILTINS  # noqa: E402

ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
LISP = os.path.join(HERE, '..', 'lisp')
PARTS = os.path.join(HERE, '..', 'shared', 'parts')
LIB = os.path.join(PARTS, 'CALOFIN-LIB.lsp')


def src(tool_dir, name):
    if ROOT == 'shared':
        return os.path.join(PARTS, name)
    return os.path.join(LISP, tool_dir, name)


XFT = src('xftconv', 'xftconv.lsp')
HONE = src('honefillet', 'HONEFILLET.lsp')
SMART = src('smartfillet', 'SMARTFILLET.lsp')
DD = src('drone_height', 'DroneDistortion.lsp')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


# ---------------------------------------------------------------------
#  the pushed-mode model
# ---------------------------------------------------------------------
# tests/lispvm.py runs every handler in the error mode its command put
# in force (tests/test_lispvm_errmode.py pins it): under a push the
# stack is reset, a bare (command) is refused in the default mode, a
# pop with nothing pushed fails the run, and a handler that dies raises
# lispvm.HandlerDeath.  This file used to install that model itself.

REPORTER = '''
  (setq tfix:*reported* nil)
  (defun lzd:report (tool ver msg)
    (setq tfix:*reported* (cons tool tfix:*reported*)))'''


def newvm(path, fixtures=()):
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(path)
    vm.loads(REPORTER)
    for f in fixtures:
        vm.loads(f)
    return vm


def said(vm):
    return ''.join(vm.printed)


def esc(vm):
    raise LispError('Function cancelled', vm)


def attempt(vm, name, script):
    """(ok, why): the run came back to the command line with the session
    balanced -- no handler death, no group open, no mode pushed."""
    try:
        vm.run(name, script)
        return True, ''
    except Exception as e:          # a script the run misread fails too
        return False, (str(e).splitlines() or [repr(e)])[0]


def reported(vm):
    v = vm.get(Sym('tfix:*reported*'))
    return list(v) if isinstance(v, list) else []


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


# ---------------------------------------------------------------------
#  XFTCONV / XFTRECONV fixtures
# ---------------------------------------------------------------------

def layer(name, flags=0, color=7):
    return f'''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "{name}") '(70 . {flags}) '(62 . {color})
                 '(6 . "Continuous")))'''


XLAYERS = layer('LEICA_POINT', 0, 3) + layer('LEICA_POINT_NAME', 0, 2)


def marker(cx, cy, space='Model'):
    return f'''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 '(8 . "LEICA_POINT") '(410 . "{space}") '(100 . "AcDbLine")
                 '(10 {cx - 1.0} {cy - 0.5} 0.0) '(11 {cx + 1.0} {cy + 0.5} 0.0)))
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 '(8 . "LEICA_POINT") '(410 . "{space}") '(100 . "AcDbLine")
                 '(10 {cx - 1.0} {cy + 0.5} 0.0) '(11 {cx + 1.0} {cy - 0.5} 0.0)))'''


def text(x, y, s, lay='LEICA_POINT_NAME', space='Model', h=1.0):
    return f'''
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 '(8 . "{lay}") '(410 . "{space}")
                 '(100 . "AcDbText")
                 '(10 {x} {y} 0.0) '(40 . {h}) '(1 . "{s}")))'''


def made(vm, source):
    before = len(vm.entities)
    vm.loads(source)
    return vm.entities[before:]


def inserts(vm):
    out = []
    live = [e for e in vm.entities if e not in vm.deleted]
    for i, e in enumerate(live):
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'INSERT' and grp(d, 2) == 'ab_pt':
            ins = grp(d, 10)
            att = vm.entdata.get(live[i + 1], [])
            out.append((ins[0], ins[1], grp(att, 1)))
    return out


def record_strings(vm):
    """Every string any live INSERT carries in its xdata -- where the
    XFTCONV record keeps what it erased."""
    out = []

    def walk(x):
        if isinstance(x, str):
            out.append(x)
        elif isinstance(x, Dot):
            walk(x.b)
        elif isinstance(x, (list, tuple)):
            for y in x:
                walk(y)
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'INSERT':
            walk(grp(d, -3))
    return out


def xftvm(fixtures=()):
    vm = newvm(XFT, (XLAYERS,) + tuple(fixtures))
    vm.sysvars['OSMODE'] = 4133
    vm.sysvars['CMDECHO'] = 1
    vm.handle_errors = True
    return vm


# ---------------------------------------------------------------------
print("XFTCONV/XFTRECONV: the handler reaches its end (finding 1)")
# ---------------------------------------------------------------------
# an Esc at the one prompt there is: under the old push the handler died
# on its first line (xft:sysback, a local helper) and left the error
# mode pushed for the rest of the session, with nothing reported
for cmd in ('c:XFTCONV', 'c:XFTRECONV'):
    vm = xftvm()
    ok, why = attempt(vm, cmd, [None, esc])
    check(f"{cmd[2:]}: Esc at the highlight comes back balanced", ok, why)
    check(f"{cmd[2:]}: ...settings as they were, the mode not left pushed",
          vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1
          and vm.error_mode_depth == 0,
          repr((vm.sysvars['OSMODE'], vm.sysvars['CMDECHO'],
                vm.error_mode_depth)))
    check(f"{cmd[2:]}: ...and the Esc is filed with LAZDIAG",
          reported(vm) == [cmd[2:]], repr(reported(vm)))

# a throw inside the swap, with the undo group open and OSMODE muted
vm = xftvm()
vm.loads('(defun xft:insert (pt num sty) (xft:no-such-helper pt num))')
ents = made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P9"))
ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
check("XFTCONV: a throw mid-swap comes back balanced (group closed)",
      ok, why)
check("...OSMODE and CMDECHO back, the failure reported",
      vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1
      and reported(vm) == ['XFTCONV'],
      repr((vm.sysvars['OSMODE'], vm.sysvars['CMDECHO'], reported(vm))))
check("...and there IS a group for the U hint to point at",
      [c for c in vm.commands if c and c[0] == '_.UNDO']
      == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']]
      and 'use U to roll the run back' in said(vm), said(vm)[-300:])

# ---------------------------------------------------------------------
print("XFTCONV/XFTRECONV: the U hint only over a group (finding 3)")
# ---------------------------------------------------------------------
# the handler survives the pushed mode now (finding 1), so it is read
# to its end: this is the line the drafter meets
for cmd in ('c:XFTCONV', 'c:XFTRECONV'):
    vm = xftvm()
    attempt(vm, cmd, [None, esc])
    check(f"{cmd[2:]}: an Esc before anything changed says nothing of U",
          'use U' not in said(vm) and 'part-way' not in said(vm),
          said(vm)[-300:])

vm = xftvm()
vm.sysvars['UNDOCTL'] = 4                      # recording off
vm.loads('(defun xft:insert (pt num sty) (xft:no-such-helper pt num))')
ents = made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P9"))
ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
check("undo off, a throw mid-swap: no U hint, and the part-way run said",
      ok and 'use U' not in said(vm)
      and 'stopped part-way with undo recording off' in said(vm),
      why or said(vm)[-300:])

# ---------------------------------------------------------------------
print("XFTCONV: every locked layer in the highlight stops it (finding 5)")
# ---------------------------------------------------------------------
# entdel refuses a locked layer in AutoCAD, and the VM's does too now
# (test_lispvm_values.py) -- this block used to model it by hand
_entdel = BUILTINS[Sym('entdel')]
vm = xftvm([layer('TITLE', 4)])
ents = (made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
        + made(vm, text(40.0, 40.0, "SITE NOTES", lay='TITLE')))
ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
check("a locked TITLE in the highlight is named, the run refused",
      ok and 'Unlock TITLE' in said(vm), why or said(vm)[-300:])
check("...before anything was scaled, swapped or erased",
      not [c for c in vm.commands if c and c[0] == '_.SCALE']
      and not inserts(vm) and not vm.deleted,
      repr((vm.commands, inserts(vm), vm.deleted)))
check("...and no count of text 'erased' that is still there",
      'leftover text object(s) erased' not in said(vm), said(vm)[-300:])

# ---------------------------------------------------------------------
print("XFTCONV: a refused erase is neither counted nor recorded (finding 6)")
# ---------------------------------------------------------------------
REFUSE = []


def refusing_entdel(vm, a):
    if a and a[0] in REFUSE:
        return NIL
    return _entdel(vm, a)


BUILTINS[Sym('entdel')] = refusing_entdel
try:
    vm = xftvm()
    ents = (made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
            + made(vm, text(3.0, 3.0, "KEEPME")))
    REFUSE[:] = [ents[-1]]
    ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
    check("the swap still ran", ok and inserts(vm) == [(0.0, 0.5, "4")],
          why or repr(inserts(vm)))
    check("the text the erase refused is not counted as erased",
          'leftover text object(s) erased' not in said(vm), said(vm)[-300:])
    check("...nor written into a block's record, where XFTRECONV would "
          "rebuild a duplicate of it",
          not any('KEEPME' in s for s in record_strings(vm)),
          repr(record_strings(vm)))
finally:
    BUILTINS[Sym('entdel')] = _entdel

# the ordinary sweep still counts and records what did go
vm = xftvm()
ents = (made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
        + made(vm, text(3.0, 3.0, "NOISE")))
ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
check("a leftover that did go is counted and recorded as before",
      ok and '1 leftover text object(s) erased' in said(vm)
      and any('NOISE' in s for s in record_strings(vm)),
      why or said(vm)[-300:])

# ---------------------------------------------------------------------
print("XFTCONV/XFTRECONV: Enter from a layout viewport means model space "
      "(finding 8)")
# ---------------------------------------------------------------------
vm = xftvm()
made(vm, marker(0.0, 0.5))
made(vm, text(0.2, 1.0, "P7"))
sheet = made(vm, text(5.0, 5.0, "TITLE BLOCK", lay='0', space='Layout1'))
vm.sysvars['CTAB'] = 'Layout1'
vm.sysvars['TILEMODE'] = 0
vm.sysvars['CVPORT'] = 2                       # inside the viewport
ok, why = attempt(vm, 'c:XFTCONV', [None, None])
check("inside a viewport, Enter takes the survey in model space",
      ok and inserts(vm) == [(0.0, 0.5, "7")], why or repr(inserts(vm)))
check("...and leaves the sheet's own text alone",
      sheet[0] not in vm.deleted, repr(vm.deleted))

vm = xftvm()
made(vm, marker(0.0, 0.5))
made(vm, text(0.2, 1.0, "P7"))
vm.sysvars['CTAB'] = 'Layout1'
vm.sysvars['TILEMODE'] = 0
vm.sysvars['CVPORT'] = 1                       # paper space proper
ok, why = attempt(vm, 'c:XFTCONV', [None, None])
check("in paper space proper, Enter takes the layout (nothing here)",
      ok and not inserts(vm) and 'Nothing to work on' in said(vm),
      why or said(vm)[-200:])

vm = xftvm()
ents = made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P7"))
vm.run('c:XFTCONV', [None, ents])
vm.sysvars['CTAB'] = 'Layout1'
vm.sysvars['TILEMODE'] = 0
vm.sysvars['CVPORT'] = 2
ok, why = attempt(vm, 'c:XFTRECONV', [None, None])
check("XFTRECONV from a viewport finds the converted survey too",
      ok and not inserts(vm) and 'taken back off the survey' in said(vm),
      why or said(vm)[-300:])


def border(x, y, lay):
    """A LINE on LAY: a sheet border or north arrow the text sweep
    leaves alone, so it is still in the highlight after the conversion
    (a leftover TEXT on it would have been erased and recorded)."""
    return f'''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 '(8 . "{lay}") '(410 . "Model") '(100 . "AcDbLine")
                 '(10 {x} {y} 0.0) '(11 {x + 10.0} {y} 0.0)))'''


def lock(vm, name):
    vm.loads(f'(setq tfix:lk (tblobjname "LAYER" "{name}"))'
             '(entmod (subst (cons 70 4) (assoc 70 (entget tfix:lk))'
             ' (entget tfix:lk)))')


def scale_calls(vm):
    return [c for c in vm.commands if c and c[0] == '_.SCALE']


def live(vm):
    return [e for e in vm.entities if e not in vm.deleted]


# ---------------------------------------------------------------------
print("XFTRECONV: every locked layer in the highlight stops it "
      "(review follow-up)")
# ---------------------------------------------------------------------
# the revert checked only the layers its own blocks sit on; a border on
# a layer locked since the conversion was skipped by SCALE and counted
# as "scaled back" -- left twelve times too big beside a survey in feet
vm = xftvm([layer('TITLE')])
ents = (made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
        + made(vm, border(40.0, 40.0, 'TITLE')))
vm.run('c:XFTCONV', [None, ents])
check("(the fixture converted, the border scaled with the survey)",
      inserts(vm) == [(0.0, 0.5, "4")] and len(scale_calls(vm)) == 1,
      repr((inserts(vm), vm.commands)))
lock(vm, 'TITLE')
highlight = live(vm)
vm.printed, vm.commands = [], []
ok, why = attempt(vm, 'c:XFTRECONV', [None, highlight])
check("a locked TITLE in the highlight is named, the revert refused",
      ok and 'Unlock TITLE' in said(vm), why or said(vm)[-300:])
check("...before anything was rebuilt, erased or scaled back",
      not vm.commands and live(vm) == highlight
      and 'objects back by' not in said(vm),
      repr((vm.commands, said(vm)[-200:])))

# a layer locked with nothing highlighted on it is not in the way
vm = xftvm([layer('TITLE'), layer('ELSEWHERE')])
ents = made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
vm.run('c:XFTCONV', [None, ents])
lock(vm, 'ELSEWHERE')
vm.printed, vm.commands = [], []
ok, why = attempt(vm, 'c:XFTRECONV', [None, live(vm)])
check("...while a locked layer none of it sits on does not stop it",
      ok and 'Unlock' not in said(vm) and not inserts(vm)
      and len(scale_calls(vm)) == 1, why or said(vm)[-300:])

# ---------------------------------------------------------------------
print("XFTCONV/XFTRECONV: the refusal offers the other way out "
      "(review follow-up)")
# ---------------------------------------------------------------------
# "Unlock X first" over a north arrow Enter-for-everything swept in had
# the drafter unlock it and get it scaled x12 with the survey
vm = xftvm([layer('NORTH', 4)])
ents = (made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
        + made(vm, text(40.0, 40.0, "N", lay='NORTH')))
ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
check("XFTCONV: a locked foreign layer is named, and narrowing offered",
      ok and 'Unlock NORTH' in said(vm)
      and 'highlight only the survey instead' in said(vm),
      why or said(vm)[-300:])

vm = xftvm([layer('POINTS', 4)])
ents = made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
check("...but not for the block layer, which no highlight avoids",
      ok and 'Unlock POINTS' in said(vm)
      and 'highlight only the survey' not in said(vm),
      why or said(vm)[-300:])

vm = xftvm([layer('NORTH')])
ents = (made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
        + made(vm, border(40.0, 40.0, 'NORTH')))
vm.run('c:XFTCONV', [None, ents])
lock(vm, 'NORTH')
vm.printed, vm.commands = [], []
ok, why = attempt(vm, 'c:XFTRECONV', [None, live(vm)])
check("XFTRECONV: the same two lines",
      ok and 'Unlock NORTH' in said(vm)
      and 'highlight only the survey instead' in said(vm),
      why or said(vm)[-300:])

# ---------------------------------------------------------------------
print("XFTCONV: an *xft-scale* SCALE would refuse is read as 12 "
      "(P4, review follow-up)")
# ---------------------------------------------------------------------
# a LAZTUNE knob, type-checked only: a 0 or a negative reached SCALE,
# which refuses it and waits -- and took the UNDO _End as its answer.
# The VM's SCALE does not wait, so what is asserted is the factor
# handed to it, and the factor written into the record.
for bad in ('0', '-12.0', '"12"', 'nil'):
    vm = xftvm()
    vm.loads(f'(setq *xft-scale* {bad})')
    ents = made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
    ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
    calls = scale_calls(vm)
    check(f"*xft-scale* {bad}: one SCALE, by the shipped 12",
          ok and len(calls) == 1 and calls[0][-1] == 12.0,
          why or repr(calls))
    check(f"*xft-scale* {bad}: ...and the run says why",
          'not a positive number - scaling by 12 instead' in said(vm),
          said(vm)[-300:])
    vm.printed, vm.commands = [], []
    ok, why = attempt(vm, 'c:XFTRECONV', [None, live(vm)])
    calls = scale_calls(vm)
    check(f"*xft-scale* {bad}: ...recorded as 12, so the revert takes "
          "1/12 back off",
          ok and len(calls) == 1 and abs(calls[0][-1] - 1.0 / 12.0) < 1e-12,
          why or repr(calls))

vm = xftvm()
vm.loads('(setq *xft-scale* 10)')
ents = made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
ok, why = attempt(vm, 'c:XFTCONV', [None, ents])
calls = scale_calls(vm)
check("a whole-number factor is taken as given, without a note",
      ok and len(calls) == 1 and calls[0][-1] == 10.0
      and 'not a positive number' not in said(vm),
      why or repr(calls))

# a record written by a run whose SCALE refused its factor -- what a
# negative *xft-scale* left behind before the check above -- has
# nothing to scale back, and handing SCALE the inverse would leave it
# waiting in its turn.  Both spellings force it, so the record is the
# same whichever build is loaded.
vm = xftvm()
vm.loads('(setq *xft-scale* -12.0) (defun xft:factor () -12.0)')
ents = made(vm, marker(0.0, 0.5)) + made(vm, text(0.2, 1.0, "P4"))
vm.run('c:XFTCONV', [None, ents])
vm.printed, vm.commands = [], []
ok, why = attempt(vm, 'c:XFTRECONV', [None, live(vm)])
check("XFTRECONV: a record with a negative factor is not scaled back",
      ok and not scale_calls(vm) and not inserts(vm)
      and 'taken back off the survey' in said(vm),
      why or repr(vm.commands))


# ---------------------------------------------------------------------
#  HONEFILLET / SMARTFILLET
# ---------------------------------------------------------------------

def line(vm, p1, p2, lay='POOL'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'LINE'), Dot(8, lay),
                     [10, float(p1[0]), float(p1[1]), 0.0],
                     [11, float(p2[0]), float(p2[1]), 0.0]]
    return e


def alive(vm, etype=None, lay=None):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for g in vm.entdata[e]:
            if isinstance(g, Dot):
                d.setdefault(g.a, g.b)
            elif isinstance(g, list) and g:
                d.setdefault(g[0], list(g[1:]))
        if etype and d.get(0) != etype:
            continue
        if lay and d.get(8) != lay:
            continue
        out.append((e, d))
    return out


def clicker(radius, preview):
    def pick(vm):
        for e, d in alive(vm, 'ARC', preview):
            if abs(d.get(40, 0) - radius) < 1e-6:
                c = d[10]
                return [e, [c[0] + radius, c[1], 0.0]]
        raise AssertionError(f"no preview arc at R{radius} to click")
    return pick


FILLETS = (
    # tool, file, prefix, preview layer, the clicks that reach the cut
    ('HONEFILLET', HONE, 'hn', 'HONE FILLET PREVIEW',
     lambda: [clicker(12.0, 'HONE FILLET PREVIEW'),
              clicker(18.0, 'HONE FILLET PREVIEW'),
              clicker(13.5, 'HONE FILLET PREVIEW')]),
    ('SMARTFILLET', SMART, 'sf', 'SMART FILLET PREVIEW',
     lambda: [clicker(12.0, 'SMART FILLET PREVIEW')]),
)

OTHER_APP = '(defun *error* (m) (princ "\\nanother app\'s handler") (princ))'


def filletvm(path):
    vm = newvm(path, (OTHER_APP,))
    vm.tables['DIMSTYLE'].add('STANDARD INCHES')
    vm.tables['LAYER'].add('POOL')
    vm.sysvars.update({'CLAYER': 'POOL', 'DIMSTYLE': 'STANDARD',
                       'OSMODE': 39, 'CMDECHO': 1, 'FILLETRAD': 3.0,
                       'TRIMMODE': 0, 'UNDOCTL': 5})
    vm.handle_errors = True
    return vm


print("HONEFILLET/SMARTFILLET: the pushed handler reads globals only "
      "(finding 2)")
for tool, path, pre, preview, clicks in FILLETS:
    # a throw inside the cut, with the group open
    vm = filletvm(path)
    other = vm.get(Sym('*error*'))
    e1, e2 = line(vm, (0, 0), (100, 0)), line(vm, (0, 0), (0, 100))
    vm.loads(f'(defun {pre}:dofillet (a b c d r) ({pre}:no-such-helper r))')
    ok, why = attempt(vm, f'c:{tool}',
                      [[e1, [50.0, 0.0, 0.0]], [e2, [0.0, 50.0, 0.0]]]
                      + clicks())
    check(f"{tool}: a throw in the cut closes the group it opened", ok, why)
    check(f"{tool}: ...settings back, previews gone, failure reported",
          vm.sysvars['OSMODE'] == 39 and vm.sysvars['TRIMMODE'] == 0
          and not alive(vm, lay=preview) and reported(vm) == [tool],
          repr((vm.sysvars['OSMODE'], reported(vm))))
    check(f"{tool}: ...and another application's *error* is still there",
          vm.get(Sym('*error*')) is other,
          repr(vm.get(Sym('*error*')))[:80])

    # a throw inside the radius dimension, the small style made current
    vm = filletvm(path)
    e1, e2 = line(vm, (0, 0), (100, 0)), line(vm, (0, 0), (0, 100))
    vm.loads(f'''
      (setq tfix:*dimsbegin* {pre}:dimsbegin)
      (defun {pre}:dimsbegin (d / od)
        (setq od (tfix:*dimsbegin* d))
        ({pre}:no-such-helper od))''')
    ok, why = attempt(vm, f'c:{tool}',
                      [[e1, [50.0, 0.0, 0.0]], [e2, [0.0, 50.0, 0.0]]]
                      + clicks())
    check(f"{tool}: a throw inside the dimension comes back balanced",
          ok, why)
    check(f"{tool}: ...with the drafter's dim style current again, not "
          "the small one",
          vm.sysvars['DIMSTYLE'] == 'STANDARD'
          and 'STANDARD INCHES' in vm.dimstyle_log,
          repr((vm.sysvars['DIMSTYLE'], vm.dimstyle_log)))

    # a stale flag from a run that died without its handler is not acted on
    vm = filletvm(path)
    vm.loads(f'(setq {pre}:*undo-open* T {pre}:*odim* "GONE")')
    ok, why = attempt(vm, f'c:{tool}', [esc])
    check(f"{tool}: a stale undo flag closes no group the run never opened",
          ok and not [c for c in vm.commands if c and c[0] == '_.UNDO'],
          why or repr(vm.commands))


print("HONEFILLET/SMARTFILLET: run-time state is no knob (finding 7, "
      "the part in these files)")
import knobs  # noqa: E402
for tool, path, pre, _preview, _clicks in FILLETS:
    names = {n for n, _lit, _why in knobs.knobs_of(
        os.path.join(LISP, tool.lower(), tool + '.lsp'))}
    state = {f'{pre}:*{n}*' for n in ('sysold', 'preview', 'picks',
                                        'smallwarned', 'odim', 'undo-open')}
    check(f"{tool}: none of its run-time state is in the tunables block",
          not (names & state), repr(sorted(names & state)))
    check(f"{tool}: ...and the real knobs still are",
          f'{pre}:*first*' in names and f'{pre}:*layer*' in names,
          repr(sorted(names))[:120])


# ---------------------------------------------------------------------
#  DDFIX
# ---------------------------------------------------------------------
print("DDFIX: a pick with anything on a locked layer is not scaled "
      "(finding 4)")

LDATA = {}
BUILTINS[Sym('vlax-ldata-get')] = lambda vm, a: LDATA.get((a[0], a[1]), NIL)
BUILTINS[Sym('vlax-ldata-put')] = \
    lambda vm, a: (LDATA.__setitem__((a[0], a[1]), a[2]), a[2])[1]
BUILTINS[Sym('vl-cmdf')] = \
    lambda vm, a: (vm.commands.append(list(a)), T)[1]


def circle(cx, cy, lay):
    return f'''
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity") '(8 . "{lay}")
                 '(100 . "AcDbCircle")
                 '(10 {cx} {cy} 0.0) '(40 . 5.0)))'''


def ddvm():
    LDATA.clear()
    vm = newvm(DD, (layer('SPA'), layer('LABELS', 4)))
    spa = made(vm, circle(10.0, 10.0, 'SPA'))[0]
    label = made(vm, circle(40.0, 10.0, 'LABELS'))[0]
    return vm, spa, label


def scales(vm):
    return [c for c in vm.commands if c and c[0] == '_.SCALE']


vm, spa, label = ddvm()
ok, why = attempt(vm, 'c:DDFIX', [None, [spa, label], [spa], 60.0, "2'"])
check("the locked layer is named at the pick, before any height is asked",
      ok and 'Locked layer LABELS' in said(vm)
      and said(vm).index('Locked layer') < said(vm).index('Applied scale'),
      why or said(vm)[-300:])
calls = scales(vm)
check("the second pick, without it, scales about ITS OWN centre",
      len(calls) == 1 and calls[0][-2] == [10.0, 10.0, 0.0],
      repr(calls))

vm, spa, label = ddvm()
ok, why = attempt(vm, 'c:DDFIX', [None, [spa, label], None])
check("...or Enter leaves with nothing scaled",
      ok and not scales(vm) and 'Nothing selected.' in said(vm),
      why or said(vm)[-300:])

vm, spa, label = ddvm()
vm.pickfirst = ['<ss>', spa, label]
ok, why = attempt(vm, 'c:DDFIX', [[spa], 60.0, "2'"])
check("a pickfirst set with a locked member goes back to the pick",
      ok and 'Locked layer LABELS' in said(vm) and len(scales(vm)) == 1
      and scales(vm)[0][-2] == [10.0, 10.0, 0.0],
      why or repr(scales(vm)))

vm, spa, label = ddvm()
ok, why = attempt(vm, 'c:DDFIX', [None, [spa], 60.0, "2'"])
check("an unlocked pick runs exactly as before",
      ok and 'Locked' not in said(vm) and len(scales(vm)) == 1,
      why or said(vm)[-300:])

# ---------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all fillconv fix checks passed")
