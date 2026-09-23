"""The step routines' bead pass and AUTOBEAD itself, on the paths that
went wrong without a word.

1. Step numbers.  'Step numbers with beaded sides' read every non-digit
   as a separator, so 1-3 -- the range PERPPTS's segment prompt takes --
   was steps 1 and 3, step 2 was left bare, and nothing read back which
   steps were taken.  An answer that named no drawn step switched the
   run to All and beaded EVERY side wall, the opposite of Some.  Now a
   range is a range, the steps taken are read back, a number the run
   did not draw is named, and an answer that names nothing is asked
   again -- off a LAZSTEP sheet too (STANDARDS 7.5).  An answer the
   reader cannot read is said to be that, not "names no step drawn",
   and an end past three digits is refused rather than expanded a
   step at a time (1-100000 was billions of comparisons).
2. autobead-build's handler under the pushed error mode.  The build
   pushes *push-error-using-command* for its (command) drain, and under
   a push AutoCAD resets the evaluator before *error* runs: the handler
   sees globals only.  It read the build's locals, so a failed or
   cancelled bead left OSMODE 0, PEDITACCEPT 1, CMDECHO 0, the undo
   group open and the working chains in the drawing.  The VM ran every
   handler with the stack live; it models the reset itself now
   (tests/test_lispvm_errmode.py), and this file used to.  Stale
   globals -- what a run that died
   WITHOUT its handler would leave -- are seeded to show each build
   clears them before it acts on any.
3. OFFSET's registry settings.  The build ran OFFSET under whatever
   OFFSETERASE / OFFSETGAPTYPE the drafter's own last OFFSET left; with
   Erase=Yes every working chain was deleted as it was offset.  They
   are muted for the run and put back on both exits.
4. A bead failure inside CORNERSTP / HEMISTEP / NORMIESTEP.  The build's
   own lzd:begin "AUTOBEAD" logged the step run 'ok', dropped its
   transcript and filed the failure as AUTOBEAD's; and because only the
   build's handler runs, the step tool's trailing form-store clear was
   skipped, leaving a sheet key to answer the next typed run.  LAZDIAG
   is a stand-in here with the real contract (a different tool's begin
   logs the open run 'ok' and replaces it; a report is filed under the
   name it is given) -- the real file is not what is under test.
5. The docs said a typed tread reads `24 1/8`.  At that click-or-type
   prompt the spacebar is Enter: 24 is the tread and 1/8 answers the
   next question.  The step READMEs and file headers now show 24-1/8.
6. TUTORIALAUTOBEAD's demo.  Its cleanup erased every entity on Bead
   Track -- the drafter's real beads included -- and it built the demo
   at the raw UCS pick while ZOOM read the same numbers as UCS, so
   under a moved UCS the pool was off screen and the direction click
   was measured against lines that were not where the drafter saw
   them.  An Esc at a demo question left the sample pool standing: the
   command had no handler, and a failure inside the demo's own bead
   build (whose handler is the only one that runs then) left it too.
   A drawing that ended in an attributed block had the block's ATTRIB
   and SEQEND read as the run's own: beaded as chains, and "erased" by
   the demo's cleanup, whose refused entdel was reported as a locked
   layer.  UCS is modelled by patching trans to a translated UCS;
   ERASE and OFFSET by stand-ins that do what the commands do to the
   database; AutoCAD's entlast (the last MAIN entity) and its entdel
   refusing a subentity by patched builtins.

FIX_STEPS_ROOT, when set, loads the lisp files from <root>/lisp/...
instead of the repo -- how the old files were run against these checks.

Run: python3 tests/test_fix_steps.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, Dot, LispError, Sym, NIL, T, BUILTINS  # noqa: E402
import test_steps_settings as SS  # noqa: E402  (scripts only)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get('FIX_STEPS_ROOT') or os.path.join(HERE, '..')


def src(*parts):
    return os.path.join(ROOT, 'lisp', *parts)


AUTOBEAD = src('autobead', 'AUTOBEAD.lsp')
TOOLS = {  # command: (file, prefix, form store, script builder)
    'c:CORNERSTP': (src('cornerstp', 'CORNERSTP.lsp'), 'cs', '*cs-form*',
                    SS.cornerstp_script),
    'c:HEMISTEP': (src('cornerstp', 'HEMISTEP.lsp'), 'hs', '*hs-form*',
                   SS.hemistep_script),
    'c:NORMIESTEP': (src('cornerstp', 'NORMIESTEP.lsp'), 'ns', '*ns-form*',
                     SS.normiestep_script),
}
BEADPICK = (0.0, -500.0, 0.0)

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + str(detail)) if detail else ''))
        FAILS.append(label)


def said(vm):
    return "".join(str(x) for x in vm.printed)


def glob(vm, name):
    return vm.globals.get(Sym(name), NIL)


def alive(vm):
    return [e for e in vm.entities if e not in vm.deleted]


def dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


# ------------------------------------------------------ patching helpers
class patched:
    """Swap BUILTINS for the length of a with-block."""

    def __init__(self, **kw):
        self.kw = kw

    def __enter__(self):
        self.old = {}
        for k, v in self.kw.items():
            self.old[k] = BUILTINS[Sym(k)]
            BUILTINS[Sym(k)] = v
        return self

    def __exit__(self, *a):
        for k, v in self.old.items():
            BUILTINS[Sym(k)] = v


_stock_command = BUILTINS[Sym('command')]


def fake_command(vm, a, fail_offset=False):
    """OFFSET makes the bead: a LINE 2" off the chain, on the chain's
    layer (the build moves it to Bead Track itself).  ERASE erases a
    selection set.  Everything else is the VM's own."""
    if a and a[0] == '._offset':
        vm.offset_env = (vm.sysvars.get('OFFSETERASE'),
                         vm.sysvars.get('OFFSETGAPTYPE'))
        if fail_offset:
            raise LispError('OFFSET: modelled failure mid-build', vm)
        c = a[2]
        p10, p11 = dxf(vm, c, 10), dxf(vm, c, 11)
        if p10 and p11:
            vm.loads('(entmakex (list (quote (0 . "LINE")) (cons 8 "%s")'
                     ' (list 10 %r %r 0.0) (list 11 %r %r 0.0)))'
                     % (dxf(vm, c, 8), float(p10[0]), float(p10[1]) + 2.0,
                        float(p11[0]), float(p11[1]) + 2.0))
    if a and isinstance(a[0], str) and a[0].lower() in ('._erase', '_.erase'):
        ss = a[1]
        for e in list(getattr(ss, 'items', ss) or []):
            if e not in vm.deleted:
                vm.deleted.add(e) if isinstance(vm.deleted, set) \
                    else vm.deleted.append(e)
    return _stock_command(vm, a)


COPY_BY_HAND = '''
  (defun autobead-copy (e / ed)
    (setq ed (entget e))
    (entmakex (list '(0 . "LINE") (cons 8 (cdr (assoc 8 ed)))
                    (assoc 10 ed) (assoc 11 ed))))'''


def layer(vm, name):
    vm.loads('(entmake (list (quote (0 . "LAYER"))'
             ' (quote (100 . "AcDbSymbolTableRecord"))'
             ' (quote (100 . "AcDbLayerTableRecord"))'
             ' (cons 2 "%s") (quote (70 . 0)) (quote (62 . 4))'
             ' (quote (6 . "Continuous"))))' % name)


# ======================================================================
print("== 1. step numbers: a range is a range, and nothing is guessed ==")

CASES = [("1-3", [1, 2, 3]), ("1 3 4", [1, 3, 4]), ("1,3,4", [1, 3, 4]),
         ("1, 3 and 4", [1, 3, 4]), ("2-4, 1", [2, 3, 4, 1]),
         ("1 3 3", [1, 3]), ("10 2", [10, 2]), ("3-1", []), ("none", []),
         ("", []), ("1 thru 3", []), ("-2", []), ("1-", []),
         # no run draws a thousand steps: past three digits an end is
         # refused before the range is expanded a step at a time (the
         # VM would not finish old code's 1-100000, so it is not here)
         ("1000", []), ("998-1000", []), ("5-999", list(range(5, 1000)))]
for cmd, (path, px, store, _s) in TOOLS.items():
    vm = VM()
    vm.load(path)
    got = {}
    for text, want in CASES:
        r = vm.loads('(%s-numlist "%s")' % (px, text))
        got[text] = [int(x) for x in r] if r else []
    bad = {t: g for (t, w), g in zip(CASES, got.values()) if g != w}
    check("%s-numlist reads ranges and refuses what it cannot read" % px,
          not bad, bad)

for cmd, (path, px, store, script) in TOOLS.items():
    tool = cmd[2:]

    def run(tail, form=None):
        vm = VM()
        vm.load(path)
        for st in ('STANDARD INCHES', 'SIDE STANDARD'):
            vm.tables['DIMSTYLE'].add(st)
        vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48.0
        vm.load(AUTOBEAD)
        vm.loads("(setq t:*seen* nil)")
        vm.loads("(defun autobead-build (ss dir side some hold)"
                 " (setq t:*seen* (list side some)) (princ))")
        if form:
            vm.loads("(setq %s %s)" % (store, form))
        s = list(script())
        s[0] = SS.walls(vm, pair=(cmd == 'c:CORNERSTP'))
        try:
            vm.run(cmd, s + tail)
        except LispError as e:
            return vm, str(e).splitlines()[0]
        return vm, None

    vm, err = run(["Yes", "Some", "1-3", BEADPICK])
    seen = glob(vm, 't:*seen*')
    check("%s: 1-3 beads the side walls of steps 1, 2 AND 3" % tool,
          not err and seen and len(seen[1]) == 3,
          err or (seen and len(seen[1])))
    check("%s: ...and reads back which steps it took" % tool,
          "side walls of step 1, 2, 3" in said(vm), said(vm)[-200:])

    vm, err = run(["Yes", "Some", "1 5", BEADPICK])
    seen = glob(vm, 't:*seen*')
    check("%s: a number the run did not draw is named, not dropped" % tool,
          not err and "left out: step 5" in said(vm)
          and seen and len(seen[1]) == 1, err or said(vm)[-200:])

    vm, err = run(["Yes", "Some", "none", "2", BEADPICK])
    seen = glob(vm, 't:*seen*')
    asked = [p for p, _ in vm.prompts if 'Step numbers with' in p]
    check("%s: an answer naming no step is asked again, not read as All"
          % tool,
          not err and len(asked) == 2 and seen and str(seen[0]) == "Some"
          and len(seen[1]) == 1, err or (len(asked), seen))

    vm, err = run(["Yes", "Some", "1 thru 3", "9", "2", BEADPICK])
    seen = glob(vm, 't:*seen*')
    out = said(vm)
    check("%s: an answer it cannot read is said to be unreadable" % tool,
          not err and '"1 thru 3" could not be read as step numbers' in out
          and '"1 thru 3" names no' not in out, err or out[-400:])
    check("%s: ...and numbers read but not drawn are said as that" % tool,
          '"9" names no step drawn here' in out
          and '"9" could not be read' not in out
          and seen and len(seen[1]) == 1, out[-400:])

    vm, err = run(["Yes", "Some", "", "B", "All", BEADPICK])
    seen = glob(vm, 't:*seen*')
    asked = [p for p, _ in vm.prompts if 'Step numbers with' in p]
    check("%s: Enter is asked again too, and B still steps back" % tool,
          not err and len(asked) == 2 and seen and str(seen[0]) == "All"
          and not seen[1], err or (len(asked), seen))

    vm, err = run(["1-3", BEADPICK],
                  form="""'((bead . "Yes") (beadsides . "Some")
                            (beadnums . "none"))""")
    seen = glob(vm, 't:*seen*')
    asked = [p for p, _ in vm.prompts if 'Step numbers with' in p]
    check("%s: an unreadable sheet answer falls through to the prompt"
          % tool,
          not err and len(asked) == 1 and seen and len(seen[1]) == 3,
          err or (len(asked), seen))

    vm, err = run([BEADPICK],
                  form="""'((bead . "Yes") (beadsides . "Some")
                            (beadnums . "2-3"))""")
    seen = glob(vm, 't:*seen*')
    check("%s: a sheet range reads as the typed one, read back too" % tool,
          not err and seen and len(seen[1]) == 2
          and "side walls of step 2, 3" in said(vm), err or seen)


# ======================================================================
print("== 2. a bead that dies mid-build puts everything back, "
      "under the pushed mode's reset ==")

POCKET = '''
  (foreach l (list "POOL-WALLA" "POOL-WALLB" "POOL-STEP1" "POOL-STEP2")
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 l) '(70 . 0) '(62 . 4) '(6 . "Continuous"))))
  (setq ab-wa (entmakex (list '(0 . "LINE") '(8 . "POOL-WALLA")
                              '(10 0.0 0.0 0.0) '(11 240.0 0.0 0.0)))
        ab-wb (entmakex (list '(0 . "LINE") '(8 . "POOL-WALLB")
                              '(10 0.0 120.0 0.0) '(11 240.0 120.0 0.0)))
        ab-s1 (entmakex (list '(0 . "LINE") '(8 . "POOL-STEP1")
                              '(10 60.0 0.0 0.0) '(11 60.0 120.0 0.0)))
        ab-s2 (entmakex (list '(0 . "LINE") '(8 . "POOL-STEP2")
                              '(10 120.0 0.0 0.0) '(11 120.0 120.0 0.0)))
        ab-ss (ssadd))
  (foreach e (list ab-wa ab-wb ab-s1 ab-s2) (ssadd e ab-ss))'''

DRAFTER = {'OSMODE': 4133, 'PEDITACCEPT': 0, 'CMDECHO': 1,
           'OFFSETERASE': 1, 'OFFSETGAPTYPE': 2}


def pocket():
    vm = VM()
    vm.load(AUTOBEAD)
    vm.loads(COPY_BY_HAND)
    vm.loads(POCKET)
    vm.sysvars.update(DRAFTER)
    return vm


def back(vm):
    return {k: vm.sysvars.get(k) for k in DRAFTER}


vm = pocket()
vm.handle_errors = True
originals = set(alive(vm))
err = None
with patched(command=lambda vm, a: fake_command(vm, a, fail_offset=True)):
    try:
        vm.loads('(autobead-build ab-ss (list 120.0 200.0 0.0) "All" nil nil)')
    except LispError as e:
        err = str(e).splitlines()[0]
check("the build failed through its own handler",
      err and len(vm.handled_errors) == 1, (err, vm.handled_errors))
check("OSMODE, PEDITACCEPT, CMDECHO, OFFSETERASE, OFFSETGAPTYPE all back",
      back(vm) == DRAFTER, back(vm))
check("the undo group the build opened is closed",
      vm.undo_groups == 0, vm.undo_groups)
check("the error mode is off the stack", vm.error_mode_depth == 0,
      vm.error_mode_depth)
check("the working chains are swept, the originals untouched",
      set(alive(vm)) == originals,
      [dxf(vm, e, 8) for e in set(alive(vm)) - originals])

vm = pocket()
vm.handle_errors = True
with patched(command=fake_command):
    vm.loads('(autobead-build ab-ss (list 120.0 200.0 0.0) "All" nil nil)')
    vm.loads('(defun autobead-copy (e) (autobead-no-such-helper e))')
    try:
        vm.loads('(autobead-build ab-ss (list 120.0 200.0 0.0) "All" nil nil)')
    except LispError:
        pass
check("a clean build and then a failed one: the second puts back the "
      "drafter's settings, not stale ones", back(vm) == DRAFTER
      and vm.undo_groups == 0 and vm.error_mode_depth == 0,
      (back(vm), vm.undo_groups, vm.error_mode_depth))

# A run that died WITHOUT its handler is the only way a stale global
# exists -- every exit that runs clears them -- so it is seeded here:
# a group "still open", OSMODE 0 and PEDITACCEPT 1 "to put back", one
# of the drafter's own lines as a "working chain", and a tutorial demo
# mark with its build flag standing.  The next build must act on none
# of it.
STALE = ('(setq autobead:*undo-open* T autobead:*oldos* 0'
         ' autobead:*oldpa* 1 autobead:*temps* (list ab-wa)'
         ' autobead:*demo* (list nil) autobead:*in-demo* T)')
_stock_getvar = BUILTINS[Sym('getvar')]


def dead_before_capture(vm, a):
    if str(a[0]).upper() == 'UNDOCTL':
        raise LispError('modelled failure before the build saves anything',
                        vm)
    return _stock_getvar(vm, a)


vm = pocket()
vm.handle_errors = True
vm.sysvars['UNDOCTL'] = 0             # this build opens no group of its own
originals = set(alive(vm))
vm.loads(STALE)
vm.loads('(defun autobead-copy (e) (autobead-no-such-helper e))')
with patched(command=fake_command):
    try:
        vm.loads('(autobead-build ab-ss (list 120.0 200.0 0.0) "All" nil nil)')
    except LispError:
        pass
ends = [c for c in vm.commands if len(c) > 1 and str(c[1]).upper() == '_END']
check("stale globals: no UNDO _End for a group this build never opened",
      not ends and len(vm.handled_errors) == 1, (ends, vm.handled_errors))
check("stale globals: the drafter's line is not swept as a working chain, "
      "nor the drawing as a stale demo", set(alive(vm)) == originals,
      [dxf(vm, e, 8) for e in originals - set(alive(vm))])
check("stale globals: the drafter's settings, not the stale ones",
      back(vm) == DRAFTER, back(vm))

vm = pocket()
vm.handle_errors = True
vm.loads(STALE)
with patched(command=fake_command,
             getvar=dead_before_capture):
    try:
        vm.loads('(autobead-build ab-ss (list 120.0 200.0 0.0) "All" nil nil)')
    except LispError:
        pass
check("stale globals, a failure before anything is saved: OSMODE and "
      "PEDITACCEPT are left as the drafter has them",
      len(vm.handled_errors) == 1 and back(vm) == DRAFTER,
      (vm.handled_errors, back(vm)))


# ======================================================================
print("== 3. OFFSET runs with Erase off and the gap type at extend ==")

vm = pocket()
vm.offset_env = None
with patched(command=fake_command):
    vm.loads('(autobead-build ab-ss (list 120.0 200.0 0.0) "All" nil nil)')
check("OFFSETERASE 0 and OFFSETGAPTYPE 0 while the build offsets",
      vm.offset_env == (0, 0), vm.offset_env)
check("...and the drafter's 1 and 2 back afterwards", back(vm) == DRAFTER,
      back(vm))
check("...and every chain came out a bead on Bead Track",
      len([e for e in alive(vm) if dxf(vm, e, 8) == "Bead Track"]) == 4,
      [dxf(vm, e, 8) for e in alive(vm)])


# ======================================================================
print("== 4. a bead failure stays the step run's, and spends its sheet ==")

FAKE_LZD = '''
  (setq lzd:*tool* nil lzd:*ver* nil t:*log* nil)
  (defun lzd:begin (tool ver)
    (if (and lzd:*tool* (/= (strcase lzd:*tool*) (strcase tool)))
      (setq t:*log* (cons (list "ok" lzd:*tool*) t:*log*)))
    (if (or (null lzd:*tool*) (/= (strcase lzd:*tool*) (strcase tool)))
      (setq lzd:*tool* tool))
    (setq lzd:*ver* ver)
    tool)
  (defun lzd:report (tool ver msg)
    (setq t:*log* (cons (list "FAIL" tool ver) t:*log*)
          lzd:*tool* nil)
    (princ))
  (defun lzd:end (tool)
    (if lzd:*tool* (setq t:*log* (cons (list "ok" lzd:*tool*) t:*log*)))
    (setq lzd:*tool* nil))
  (defun lzd:ask (p v) v)
  (defun lzd:watch (ss) ss)'''

for cmd, (path, px, store, script) in TOOLS.items():
    tool = cmd[2:]
    vm = VM()
    vm.load(path)
    for st in ('STANDARD INCHES', 'SIDE STANDARD'):
        vm.tables['DIMSTYLE'].add(st)
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48.0
    vm.load(AUTOBEAD)
    vm.loads(FAKE_LZD)
    vm.loads('(defun autobead-copy (e) (autobead-no-such-helper e))')
    # a sheet key this run never reaches: the typed script says No to
    # the bench, so the bench offset is never taken
    vm.loads("(setq %s '((benchoffset . 6.0)))" % store)
    vm.handle_errors = True
    s = list(script())
    s[0] = SS.walls(vm, pair=(cmd == 'c:CORNERSTP'))
    err = None
    try:
        vm.run(cmd, s + ["Yes", "All", BEADPICK])
    except LispError as e:
        err = str(e).splitlines()[0]
    log = [tuple(str(x) for x in r) for r in reversed(glob(vm, 't:*log*') or [])]
    fails = [r for r in log if r[0] == "FAIL"]
    check("%s: the bead failure is filed under %s" % (tool, tool),
          not err and fails and fails[0][1] == tool, err or log)
    check("%s: ...and the run is not logged 'ok' before it fails" % tool,
          ("ok", tool) not in log, log)
    check("%s: the sheet is spent before the hand-off, nothing leaks" % tool,
          not glob(vm, store), glob(vm, store))


# ======================================================================
print("== 5. a typed fraction is shown dashed, and why ==")

for rel in (('cornerstp', 'README.md'), ('cornerstp', 'CORNERSTP.lsp'),
            ('cornerstp', 'HEMISTEP.lsp'), ('cornerstp', 'NORMIESTEP.lsp')):
    text = open(src(*rel), encoding='utf-8').read()
    head = text if rel[1] == 'README.md' else \
        text[:text.index(';;; -------------------- the length ruler')]
    check("%s shows 24-1/8, never 24 1/8 as a spelling to type" % rel[1],
          '24-1/8' in head and '`24 1/8`,' not in head
          and '24.5, 24 1/8,' not in head)
    check("%s says the space ends the answer" % rel[1],
          'spacebar is Enter' in head)


# ======================================================================
print("== 6. TUTORIALAUTOBEAD's demo ==")

UCS = (1000.0, 500.0, 0.0)


def fake_trans(vm, a):
    """A UCS moved to WCS (1000,500): 1 -> 0 adds the origin, 0 -> 1
    takes it off; a displacement (4th arg) and any other pair are the
    identity."""
    p = [float(v) for v in lispvm.pt(a[0])]
    frm = a[1] if len(a) > 1 else 0
    to = a[2] if len(a) > 2 else 0
    disp = len(a) > 3 and a[3] is not NIL
    if disp or frm == to:
        return p
    if frm == 1 and to == 0:
        return [p[0] + UCS[0], p[1] + UCS[1], p[2] + UCS[2]]
    if frm == 0 and to == 1:
        return [p[0] - UCS[0], p[1] - UCS[1], p[2] - UCS[2]]
    return p


def demo_vm():
    vm = VM()
    vm.load(AUTOBEAD)
    vm.loads(COPY_BY_HAND)
    layer(vm, "Bead Track")
    # a bead the drafter drew earlier, far from the demo
    vm.mine = vm.loads('(entmakex (list (quote (0 . "LINE"))'
                       ' (quote (8 . "Bead Track"))'
                       ' (list 10 5000.0 5000.0 0.0)'
                       ' (list 11 5200.0 5000.0 0.0)))')
    return vm


# 6a. under a moved UCS the demo is where the drafter clicked
vm = demo_vm()
vm.loads("(setq t:*args* nil)")
vm.loads("(defun autobead-build (ss dir side some hold)"
         " (setq t:*args* (list dir some)) 0)")
with patched(trans=fake_trans, command=fake_command):
    try:
        vm.run('c:TUTORIALAUTOBEAD',
               ["Demo", (10.0, 10.0, 0.0), None, None, (150.0, 80.0, 0.0),
                None, "No"])
        err = None
    except LispError as e:
        err = str(e).splitlines()[0]
demo = [e for e in alive(vm) if dxf(vm, e, 8) == "POOL-TUTORIAL"]
pts = [dxf(vm, e, c) for e in demo for c in (10, 11)]
xs, ys = [float(p[0]) for p in pts], [float(p[1]) for p in pts]
zoom = [c for c in vm.commands if c and c[0] == '._zoom']
check("the demo ran", not err and len(demo) == 5, err or len(demo))
check("the pool is built round the WCS point clicked (UCS 10,10)",
      pts and min(xs) == 1010.0 and min(ys) == 510.0, (min(xs), min(ys)))
if zoom and pts:
    (zx0, zy0), (zx1, zy1) = zoom[0][2][:2], zoom[0][3][:2]
    inside = all(zx0 <= x - UCS[0] <= zx1 and zy0 <= y - UCS[1] <= zy1
                 for x, y in zip(xs, ys))
else:
    inside = False
check("the zoom window (UCS) frames the pool", inside, zoom)
args = glob(vm, 't:*args*')
if args:
    dw = fake_trans(vm, [args[0], 1, 0])
    tp = args[1][0]
    in_dir = min(xs) < dw[0] < max(xs) and min(ys) < dw[1] < max(ys)
    in_tread = min(xs) < float(tp[0]) < max(xs) \
        and min(ys) < float(tp[1]) < max(ys)
else:
    in_dir = in_tread = False
check("the direction click, taken to WCS, lands inside the demo pool",
      in_dir, args and args[0])
check("the clicked tread handed to the build is inside it too (WCS)",
      in_tread, args and args[1])

# 6b. Yes at the cleanup takes the demo and ONLY the demo
vm = demo_vm()
with patched(command=fake_command):
    try:
        vm.run('c:TUTORIALAUTOBEAD',
               ["Demo", (10.0, 10.0, 0.0), None, None, (150.0, 80.0, 0.0),
                None, None])
        err = None
    except LispError as e:
        err = str(e).splitlines()[0]
beads_made = [e for e in vm.entities if dxf(vm, e, 8) == "Bead Track"
              and e != vm.mine]
check("the demo beaded something to clean up", not err and beads_made,
      err or len(beads_made))
check("the drafter's own bead survives the demo's cleanup",
      vm.mine not in vm.deleted)
check("...and everything the demo drew is gone",
      alive(vm) == [vm.mine], [dxf(vm, e, 8) for e in alive(vm)])
check("...and nothing claims a cleanup it did not do",
      "Demo geometry erased." in said(vm)
      and "Undo (U) also removes" not in said(vm), said(vm)[-300:])

# 6c. a locked demo layer is said, not claimed.  The drafter locks
#     POOL-TUTORIAL while the demo's last question is up, so the five
#     sample lines are the ones entdel refuses
#     (entdel refuses on a locked layer in the VM itself now --
#     test_lispvm_values.py -- so the lock is a real one, set on the
#     layer's record the way LAYER's Lock would)
vm = demo_vm()
_stock_entdel = BUILTINS[Sym('entdel')]


def lock_then_enter(vm):
    vm.loads('(setq t:rec (entget (tblobjname "LAYER" "POOL-TUTORIAL")))'
             '(entmod (subst (cons 70 (logior 4 (cdr (assoc 70 t:rec))))'
             ' (assoc 70 t:rec) t:rec))')
    return None


with patched(command=fake_command):
    vm.run('c:TUTORIALAUTOBEAD',
           ["Demo", (10.0, 10.0, 0.0), None, None, (150.0, 80.0, 0.0),
            None, lock_then_enter])
check("objects a locked layer kept are counted and said",
      "except 5 object(s) on a locked layer - NOT erased" in said(vm),
      said(vm)[-200:])

# 6d. Esc at a demo question takes the demo back down
vm = demo_vm()
vm.handle_errors = True


def esc(vm):
    raise LispError('Function cancelled', vm)


try:
    with patched(command=fake_command):
        vm.run('c:TUTORIALAUTOBEAD',
               ["Demo", (10.0, 10.0, 0.0), None, None, esc])
    err = None
except LispError as e:
    err = str(e).splitlines()[0]
check("Esc at the direction click goes through a handler", not err
      and vm.handled_errors == ['Function cancelled'], err)
check("...which takes the demo pool down and leaves the drafter's bead",
      alive(vm) == [vm.mine], [dxf(vm, e, 8) for e in alive(vm)])
check("...and a plain cancel prints no error line",
      "TUTORIALAUTOBEAD error" not in said(vm))


# 6e. the drawing ends in an attributed block.  AutoCAD's entlast is the
#     last MAIN entity -- the INSERT, not its SEQEND, which is what the
#     VM's answers -- so a walk from it starts in the block's ATTRIB and
#     SEQEND.  entdel refuses a subentity, and the cleanup counted them
#     as "on a locked layer" with nothing locked.  Both rules modelled.
SUBENTS = ("ATTRIB", "VERTEX", "SEQEND")
SURVEY = '''
  (entmake (list '(0 . "INSERT") '(8 . "SURVEY") '(2 . "PT") '(66 . 1)
                 (list 10 9000.0 9000.0 0.0)))
  (entmake (list '(0 . "ATTRIB") '(8 . "SURVEY") '(2 . "TAG") '(1 . "101")
                 (list 10 9000.0 9000.0 0.0)))
  (entmake (list '(0 . "SEQEND") '(8 . "SURVEY")))'''


def main_entlast(vm, a):
    for e in reversed(vm.entities):
        if e not in vm.deleted and dxf(vm, e, 0) not in SUBENTS:
            return e
    return NIL


def sub_entdel(vm, a):
    if dxf(vm, a[0], 0) in SUBENTS:
        return NIL                       # AutoCAD: not on its own
    return _stock_entdel(vm, a)


vm = demo_vm()
vm.loads(SURVEY)
block = [e for e in alive(vm) if dxf(vm, e, 8) == "SURVEY"]
with patched(command=fake_command, entlast=main_entlast, entdel=sub_entdel):
    try:
        vm.run('c:TUTORIALAUTOBEAD',
               ["Demo", (10.0, 10.0, 0.0), None, None, (150.0, 80.0, 0.0),
                None, None])
        err = None
    except LispError as e:
        err = str(e).splitlines()[0]
out = said(vm)
check("a survey block last in the drawing: the cleanup claims no "
      "locked layer", not err and "Demo geometry erased." in out
      and "locked layer" not in out, err or out[-200:])
check("...the block, its attribute and its SEQEND are the drafter's and "
      "stay", alive(vm) == [vm.mine] + block,
      [dxf(vm, e, 0) + "/" + str(dxf(vm, e, 8)) for e in alive(vm)])

# 6f. ...and the engine: AUTOBEAD run right after placing that block
#     read its ATTRIB and SEQEND as two more chains to bead and sweep
vm = pocket()
originals = set(alive(vm))
vm.loads(SURVEY)
block = [e for e in alive(vm) if dxf(vm, e, 8) == "SURVEY"]
vm.chained = []


def watch_offset(vm, a):
    if a and a[0] == '._offset':
        vm.chained.append(dxf(vm, a[2], 0))
    return fake_command(vm, a)


with patched(command=watch_offset, entlast=main_entlast, entdel=sub_entdel):
    made = vm.loads('(autobead-build ab-ss (list 120.0 200.0 0.0) "All"'
                    ' nil nil)')
beads = [e for e in alive(vm) if dxf(vm, e, 8) == "Bead Track"]
check("a block placed last is not beaded: only the four pool lines are "
      "offset", sorted(vm.chained) == ["LINE"] * 4, vm.chained)
check("...four beads, and nothing else left over",
      made == 4 and len(beads) == 4
      and set(alive(vm)) == originals | set(block) | set(beads),
      (made, [dxf(vm, e, 0) + "/" + str(dxf(vm, e, 8)) for e in alive(vm)]))

# 6g. the demo's own bead build fails.  Only the BUILD's handler runs
#     then, never the demo's, and the sample pool was left standing on
#     POOL-TUTORIAL with its mark still set.  The build's handler takes
#     it down now -- under the pushed mode's reset, where it sees
#     globals only.
vm = demo_vm()
vm.handle_errors = True
try:
    with patched(command=lambda vm, a: fake_command(vm, a, fail_offset=True)):
        vm.run('c:TUTORIALAUTOBEAD',
               ["Demo", (10.0, 10.0, 0.0), None, None, (150.0, 80.0, 0.0),
                None])
    err = None
except LispError as e:
    err = str(e).splitlines()[0]
check("a failed demo build goes through the build's handler, once",
      not err and len(vm.handled_errors) == 1, err or vm.handled_errors)
check("...which takes the demo pool down and leaves the drafter's bead",
      alive(vm) == [vm.mine], [dxf(vm, e, 8) for e in alive(vm)])
check("...and leaves no demo mark or build flag standing",
      not glob(vm, 'autobead:*demo*') and not glob(vm, 'autobead:*in-demo*')
      and not glob(vm, 'autobead:*demo-call*'),
      [glob(vm, n) for n in ('autobead:*demo*', 'autobead:*in-demo*',
                             'autobead:*demo-call*')])

# 6h. ...but a demo mark some dead run left behind is never swept by a
#     build the demo did not call: a step routine's failed bead, here
vm = pocket()
vm.handle_errors = True
originals = set(alive(vm))
vm.loads('(setq autobead:*demo* (list nil))')
with patched(command=lambda vm, a: fake_command(vm, a, fail_offset=True)):
    try:
        vm.loads('(autobead-build ab-ss (list 120.0 200.0 0.0) "All" nil nil)')
    except LispError:
        pass
check("a stale demo mark: a failed non-demo build sweeps nothing of the "
      "drafter's", len(vm.handled_errors) == 1
      and set(alive(vm)) == originals,
      [dxf(vm, e, 8) for e in originals - set(alive(vm))])


if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), "; ".join(FAILS)))
    sys.exit(1)
print("\nALL FIX-STEPS CHECKS PASSED")
