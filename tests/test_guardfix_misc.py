#!/usr/bin/env python3
"""Runtime tests for the second guard-fix wave's miscellany: one fix each
in SMARTFILLET, HONEFILLET, LAZPANEL, XYPLOT, LAZFORM, AUTOBEAD, PADDLE
and OLAUTO, each driven in the AutoLISP VM and each written to FAIL on
the code before the fix.

Where the VM is kinder than AutoCAD, the difference is modelled HERE, for
the length of one test, and put back afterwards:

  * vl-sort drops only EQ duplicates -- integers and symbols.  Two equal
    REALS are not EQ and both stay (the fillet radii).
  * entmod and entdel answer nil, and change nothing, on an object whose
    layer is locked; entmake still builds there (the demo layers,
    OLAUTO's picks).
  * entsel answers nil to a click that lands on nothing, exactly as it
    does to Enter, and sets ERRNO 7 -- which is sticky: nothing but a
    setvar puts it back to 0 (the fillet line prompts).
  * vlax-create-object answers nil, not an error, for a shell that is
    not registered or is blocked (LAZPANEL's certutil route).

Run: python3 tests/test_guardfix_misc.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_guardfix_misc.py
"""

import contextlib
import functools
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import (VM, LispError, Ent, Dot, Sym, NIL,  # noqa: E402
                    BUILTINS, truthy)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def src(*parts):
    """A lisp/ path; vm.load remaps it to the grouped tier (and loads the
    library first) when CALOFIN_LISP_ROOT says so."""
    return os.path.join(REPO, 'lisp', *parts)


SMARTFILLET = src('smartfillet', 'SMARTFILLET.lsp')
HONEFILLET = src('honefillet', 'HONEFILLET.lsp')
LAZPANEL = src('lazpanel', 'LAZPANEL.lsp')
XYPLOT = src('xyplot', 'XYPLOT.lsp')
LAZFORM = src('lazform', 'LAZFORM.lsp')
AUTOBEAD = src('autobead', 'AUTOBEAD.lsp')
PADDLE = src('paddle', 'PADDLE.lsp')
OLAUTO = src('olauto', 'OLAUTO.lsp')

failures = []


def check(label, ok, detail=''):
    print(('  ok   ' if ok else '  FAIL ') + label
          + (f'  -- {detail}' if detail and not ok else ''))
    if not ok:
        failures.append(label)


@contextlib.contextmanager
def builtins(**fns):
    """Swap VM builtins for the length of a block (names with - spelled
    _ here), and put the originals back whatever happens."""
    saved = {}
    for k, fn in fns.items():
        s = Sym(k.replace('_', '-'))
        saved[s] = BUILTINS.get(s)
        BUILTINS[s] = fn
    try:
        yield
    finally:
        for s, fn in saved.items():
            if fn is None:
                BUILTINS.pop(s, None)
            else:
                BUILTINS[s] = fn


def said(vm):
    return ''.join(str(p) for p in vm.printed)


def alive(vm, etype=None, layer=None):
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
        if layer and str(d.get(8, '')).upper() != layer.upper():
            continue
        out.append((e, d))
    return out


def line(vm, p1, p2, layer='POOL'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'LINE'), Dot(8, layer),
                     [10, float(p1[0]), float(p1[1]), 0.0],
                     [11, float(p2[0]), float(p2[1]), 0.0]]
    return e


def circle(vm, c, r, layer='POOL'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'CIRCLE'), Dot(8, layer),
                     [10, float(c[0]), float(c[1]), 0.0], Dot(40, float(r))]
    return e


# ------------------------------------------------------------- the models

def eq_only_vl_sort(vm, a):
    """(vl-sort lst less) as AutoCAD's: sorted, and an item dropped only
    when it is EQ to the one before it -- an integer or a symbol of the
    same value, or the very same object.  Two equal reals both stay."""
    fn = a[1]

    def lt(x, y):
        return truthy(vm.call_value(fn, [x, y]))

    ordered = sorted(list(a[0] or []), key=functools.cmp_to_key(
        lambda x, y: -1 if lt(x, y) else (1 if lt(y, x) else 0)))
    out = []
    for v in ordered:
        if out:
            p = out[-1]
            if p is v or (type(p) is int and type(v) is int and p == v) \
                    or (isinstance(p, Sym) and isinstance(v, Sym)
                        and p == v):
                continue
        out.append(v)
    return out or NIL


def layer_rec(vm, name):
    return vm.tablerecs.get('LAYER', {}).get(str(name).upper())


def layer_flags(vm, name):
    rec = layer_rec(vm, name)
    for g in vm.recdata.get(rec, []) if rec is not None else []:
        if isinstance(g, Dot) and g.a == 70:
            return int(g.b)
    return 0


def make_layer(vm, name, flags=0, color=7):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") (cons 2 "%s") (cons 70 %d)'
             ' (cons 62 %d) \'(6 . "Continuous")))' % (name, flags, color))


def set_lock(vm, name, on=True):
    rec = layer_rec(vm, name)
    data = vm.recdata[rec]
    for i, g in enumerate(data):
        if isinstance(g, Dot) and g.a == 70:
            data[i] = Dot(70, (int(g.b) | 4) if on else (int(g.b) & ~4))
            return
    data.append(Dot(70, 4 if on else 0))


def on_locked_layer(vm, e):
    if not isinstance(e, Ent) or e not in vm.entdata:
        return False              # a table record is not ON a layer
    lay = vm.layer_of(e)
    return bool(layer_flags(vm, '0' if lay is NIL else lay) & 4)


@contextlib.contextmanager
def locks_honoured():
    """entmod and entdel refuse, with nil, on an object on a locked
    layer; vm.refused counts the refusals."""
    base_mod, base_del = BUILTINS[Sym('entmod')], BUILTINS[Sym('entdel')]

    def entmod(vm, a):
        for g in (a[0] or []):
            if isinstance(g, Dot) and g.a == -1:
                if on_locked_layer(vm, g.b):
                    vm.refused = getattr(vm, 'refused', 0) + 1
                    return NIL
                break
        return base_mod(vm, a)

    def entdel(vm, a):
        if a and on_locked_layer(vm, a[0]):
            vm.refused = getattr(vm, 'refused', 0) + 1
            return NIL
        return base_del(vm, a)

    with builtins(entmod=entmod, entdel=entdel):
        yield


def miss(vm):
    """A click that lands on nothing: nil, as Enter is, and ERRNO 7."""
    vm.sysvars['ERRNO'] = 7
    return None


# ================================================================ [1] [2]
print("SMARTFILLET / HONEFILLET -- a re-tuned series offers each radius once")
# sf:*first* re-tuned to 3 puts the series on 3, 9, 15 -- which is
# where the stock extras (3 and 9) already sit.  The comment trusted
# vl-sort to drop the duplicates; it drops only EQ items, and two equal
# reals are not EQ.
for path, pfx in ((SMARTFILLET, 'sf'), (HONEFILLET, 'hn')):
    vm = VM()
    vm.load(path)
    vm.loads('(setq %s:*first* 3.0)' % pfx)
    with builtins(vl_sort=eq_only_vl_sort):
        got = vm.loads('(%s:fitting 20.0)' % pfx)
        shown = vm.loads('(%s:candidates 20.0)' % pfx)
        n = vm.loads('(%s:howmany 20.0)' % pfx)
    got = [float(x) for x in (got or [])]
    check("%s:fitting offers 3, 9 and 15 once each" % pfx,
          got == [3.0, 9.0, 15.0], repr(got))
    check("...so the preview list and the 'how many fit' count agree",
          [float(x) for x in (shown or [])] == [3.0, 9.0, 15.0] and n == 3,
          '%r / %r' % (shown, n))
    # the stock series is untouched: 6s with the 3 and 9 slotted in
    vm = VM()
    vm.load(path)
    with builtins(vl_sort=eq_only_vl_sort):
        got = [float(x) for x in (vm.loads('(%s:fitting 20.0)' % pfx) or [])]
    check("%s:fitting at stock settings is 3 6 9 12 18" % pfx,
          got == [3.0, 6.0, 9.0, 12.0, 18.0], repr(got))


# ================================================================ [10]
print("SMARTFILLET -- a click beside a line is asked again, not taken as Done")
PREV_SF = 'SMART FILLET PREVIEW'


def sf_clicker(radius, layer):
    def pick(vm):
        for e, d in alive(vm, 'ARC', layer):
            if abs(d.get(40, 0) - radius) < 1e-6:
                c = d[10]
                return [e, [c[0] + radius, c[1], 0.0]]
        raise AssertionError(f"no preview arc at R{radius} to click")
    return pick


def fillet_vm(path):
    vm = VM()
    vm.load(path)
    vm.tables['LAYER'].add('POOL')
    vm.sysvars['CLAYER'] = 'POOL'
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    e3 = line(vm, (200, 0), (300, 0))
    e4 = line(vm, (300, 0), (300, 100))
    return vm, e1, e2, e3, e4


def fillets(vm):
    return [c for c in vm.commands if c and c[0] == '_.FILLET']


def drive(vm, cmd, script):
    try:
        vm.run(cmd, script)
        return ''
    except LispError as e:
        return str(e).splitlines()[0]


FIRST = lambda e1, e2: [[e1, [50.0, 0.0, 0.0]], [e2, [0.0, 50.0, 0.0]]]
C3 = lambda e3: [e3, [250.0, 0.0, 0.0]]
C4 = lambda e4: [e4, [300.0, 50.0, 0.0]]

# a miss at the first line of the next corner
vm, e1, e2, e3, e4 = fillet_vm(SMARTFILLET)
err = drive(vm, 'c:SMARTFILLET',
            FIRST(e1, e2) + [sf_clicker(12.0, PREV_SF), 'Yes',
                             miss, C3(e3), C4(e4), None])
check("a miss in the repeat loop says 'nothing there' and asks again",
      not err and 'nothing there' in said(vm), err or said(vm)[-300:])
check("...and the corner picked after it is still cut",
      len(fillets(vm)) == 2 and '2 corners filleted at R12' in said(vm),
      '%d fillets' % len(fillets(vm)))

# a miss at the SECOND line keeps the first one picked
vm, e1, e2, e3, e4 = fillet_vm(SMARTFILLET)
err = drive(vm, 'c:SMARTFILLET',
            FIRST(e1, e2) + [sf_clicker(12.0, PREV_SF), 'Yes',
                             C3(e3), miss, C4(e4), None])
check("a miss at the second line keeps the first line picked",
      not err and len(fillets(vm)) == 2, err or '%d fillets' % len(fillets(vm)))

# Enter after a miss is still Enter: ERRNO is sticky, so it is zeroed
# before every pick or the Enter would read as a second miss for ever
vm, e1, e2, e3, e4 = fillet_vm(SMARTFILLET)
err = drive(vm, 'c:SMARTFILLET',
            FIRST(e1, e2) + [sf_clicker(12.0, PREV_SF), 'Yes', miss, None])
check("Enter after a miss is Done, not a second miss",
      not err and len(fillets(vm)) == 1 and 'nothing there' in said(vm),
      err or said(vm)[-300:])

# and a miss at the very first prompt no longer cancels the command
vm, e1, e2, e3, e4 = fillet_vm(SMARTFILLET)
err = drive(vm, 'c:SMARTFILLET',
            [miss] + FIRST(e1, e2) + [sf_clicker(12.0, PREV_SF), 'No'])
check("a miss at the first prompt is asked again, not Cancel",
      not err and len(fillets(vm)) == 1, err or said(vm)[-300:])


# ================================================================ [9]
print("HONEFILLET -- a click beside a line is asked again, not taken as Done")
PREV_HN = 'HONE FILLET PREVIEW'
HONED = lambda: [sf_clicker(12.0, PREV_HN), sf_clicker(18.0, PREV_HN),
                 sf_clicker(13.5, PREV_HN)]

vm, e1, e2, e3, e4 = fillet_vm(HONEFILLET)
err = drive(vm, 'c:HONEFILLET',
            FIRST(e1, e2) + HONED() + ['Yes', miss, C3(e3), C4(e4), None])
check("a miss in the repeat loop says 'nothing there' and asks again",
      not err and 'nothing there' in said(vm), err or said(vm)[-300:])
check("...and the corner picked after it is still cut",
      len(fillets(vm)) == 2 and '2 corners filleted at R13.5' in said(vm),
      '%d fillets' % len(fillets(vm)))

vm, e1, e2, e3, e4 = fillet_vm(HONEFILLET)
err = drive(vm, 'c:HONEFILLET',
            FIRST(e1, e2) + HONED() + ['Yes', C3(e3), miss, C4(e4), None])
check("a miss at the second line keeps the first line picked",
      not err and len(fillets(vm)) == 2, err or '%d fillets' % len(fillets(vm)))

vm, e1, e2, e3, e4 = fillet_vm(HONEFILLET)
err = drive(vm, 'c:HONEFILLET', FIRST(e1, e2) + HONED() + ['Yes', miss, None])
check("Enter after a miss is Done, not a second miss",
      not err and len(fillets(vm)) == 1 and 'nothing there' in said(vm),
      err or said(vm)[-300:])


# ================================================================ [3]
print("LAZPANEL -- a WScript.Shell that comes back nil is named as such")
vm = VM()
vm.load(LAZPANEL)
vm.loads('(defun vl-file-delete (f) (setq t:*gone* (cons f t:*gone*)) t)'
         '(defun vlax-release-object (o) nil)')
RAN = []


def _invoke(vm, a):
    RAN.append(a[0])
    if a[0] is NIL or a[0] is None:
        raise LispError('bad argument type: VLA-OBJECT nil', vm)
    return 0


with builtins(vlax_create_object=lambda vm, a: NIL,
              vlax_invoke_method=_invoke):
    vm.loads('(setq lzp:*iconerr* "" t:*gone* nil)')
    r = vm.loads('(lzp:bmp-certutil "/stub/x/lazpanel-16-dark.bmp"'
                 ' \'(66 77 0 0 0 0))')
err = str(vm.globals.get(Sym('lzp:*iconerr*')))
check("the route fails", r in (None, NIL) or r == [], repr(r))
check("and says the shell came back nil",
      'WScript.Shell came back nil' in err, repr(err))
check("without handing that nil to Run", not RAN, repr(RAN))
gone = [str(x) for x in (vm.globals.get(Sym('t:*gone*')) or [])]
check("and the base64 scratch file is deleted",
      any(g.endswith('.b64') for g in gone), repr(gone))


# ================================================================ [4]
print("XYPLOT -- a run that plots nothing closes the undo group it opened")
XY_STUBS = r'''
(defun getfiled (title dflt ext flags) "C:\\jobs\\xy.csv")
(defun alert (s) (setq *alert* s))
(defun sssetfirst (a b) (setq *preselect* b))
'''


def xyplot_run(rows_lisp):
    vm = VM()
    vm.loads(XY_STUBS)
    vm.load(XYPLOT)
    vm.loads('(defun xyp:read-file (file) %s)' % rows_lisp)
    with builtins(vl_cmdf=BUILTINS[Sym('command')]):
        err = drive(vm, 'c:XYPLOT', [[0.0, 0.0, 0.0]])
    undo = [c[1] for c in vm.commands if c and c[0] == '_.UNDO']
    return vm, err, undo


for label, rows, says in (
        ("an empty sheet", 'nil', 'No usable rows found'),
        ("a sheet with no X/Y pair", '(list (list "1" nil 5.0))',
         'No row had both an X and a Y')):
    vm, err, undo = xyplot_run(rows)
    check("%s: says nothing was plotted" % label, says in said(vm),
          said(vm)[-200:])
    check("%s: leaves no undo group open" % label,
          not err and vm.undo_groups == 0 and undo == ['_Begin', '_End'],
          err or repr(undo))


# ================================================================ [5]
print("LAZFORM -- LAZTXT is never a cover sheet, whatever a dead run left")
LZ_STUB = '''
(setq stub:*rc* 1 stub:*rcs* nil stub:*act* nil stub:*type* nil stub:*done* nil)
(defun vl-filename-mktemp (pat dir ext) (strcat "/stub/" pat ext))
(defun open (f mode) f)
(defun write-line (s fh) s)
(defun close (fh) t)
(defun load_dialog (f) 7)
(defun new_dialog (name id) t)
(defun unload_dialog (id) t)
(defun vl-file-delete (f) t)
(defun set_tile (k v) v)
(defun mode_tile (k m) t)
(defun done_dialog (status) (setq stub:*done* status) (list 120 340))
(defun action_tile (k expr) (setq stub:*act* (cons (list k expr) stub:*act*)) t)
(defun start_dialog ( / p k)
  (if stub:*rcs* (setq stub:*rc* (car stub:*rcs*) stub:*rcs* (cdr stub:*rcs*)))
  (setq stub:*done* nil)
  (foreach p stub:*type*
    (if (setq k (assoc (car p) stub:*act*))
      (progn (setq $value (cadr p) $key (car p))
             (eval (read (strcat "(progn " (cadr k) ")"))))))
  stub:*rc*)
(defun pool:run-with-answers (form) (setq t:*handed* form) (princ))
'''


def handed(vm):
    out = {}
    for p in vm.globals.get(Sym('t:*handed*')) or []:
        if isinstance(p, Dot):
            out[str(p.a)] = p.b
        else:
            out[str(p[0])] = p[1] if len(p) > 1 else None
    return out


def laztxt(cover_left_up):
    vm = VM()
    vm.load(LAZFORM)
    vm.loads(LZ_STUB)
    # what a LAZFORMCOVER whose POOL died leaves behind: lzf:run raises
    # the flag and only its own tail, never reached, lowers it
    if cover_left_up:
        vm.loads('(setq lzf:*cover* t)')
    vm.loads('(setq stub:*rcs* \'(1))')
    vm.loads('(setq stub:*type* \'(("tp" "480") ("h" "60") ("e" "72")))')
    err = drive(vm, 'c:LAZTXT', [])
    return vm, err, handed(vm)


vm, err, clean = laztxt(False)
vm, err2, after = laztxt(True)
check("LAZTXT runs", not err and not err2, err or err2)
check("a clean session hands POOL the bottom type and the depths",
      all(k in clean for k in ('btype', 'h', 'e')), repr(sorted(clean)))
check("...and so does one after a cover run that died",
      all(k in after for k in ('btype', 'h', 'e')), repr(sorted(after)))
check("...and leaves the flag down",
      vm.globals.get(Sym('lzf:*cover*')) in (None, NIL),
      repr(vm.globals.get(Sym('lzf:*cover*'))))


# ================================================================ [6]
print("AUTOBEAD -- the demo layer is unlocked, so the demo can come down")
vm = VM()
vm.load(AUTOBEAD)
make_layer(vm, 'POOL-TUTORIAL', flags=4, color=4)
vm.loads('(autobead-demo-layer "POOL-TUTORIAL")')
check("an existing POOL-TUTORIAL left locked is unlocked",
      not (layer_flags(vm, 'POOL-TUTORIAL') & 4),
      'flags %d' % layer_flags(vm, 'POOL-TUTORIAL'))
check("and it says so", 'POOL-TUTORIAL was off, frozen or locked'
      in said(vm), said(vm))
vm = VM()
vm.load(AUTOBEAD)
vm.loads('(autobead-demo-layer "POOL-TUTORIAL")')
check("a missing one is still made, unlocked",
      layer_rec(vm, 'POOL-TUTORIAL') is not None
      and layer_flags(vm, 'POOL-TUTORIAL') == 0)

# the whole demo, with the lock honoured: drawn, then taken down
vm = VM()
vm.load(AUTOBEAD)
make_layer(vm, 'POOL-TUTORIAL', flags=4, color=4)
with locks_honoured():
    err = drive(vm, 'c:TUTORIALAUTOBEAD',
                ['Demo', [0.0, 0.0, 0.0], None, None, None, 'Yes'])
left = alive(vm, 'LINE', 'POOL-TUTORIAL')
check("the demo drawn on a layer left locked is erased by its cleanup",
      not err and not left and 'Demo geometry erased.' in said(vm)
      and 'NOT erased' not in said(vm),
      err or '%d left: %s' % (len(left), said(vm)[-200:]))


# ================================================================ [7]
print("PADDLE -- TUTORIALPADDLE's demo layer is unlocked, and a refused "
      "erase is said")


def paddle_vm(locked):
    vm = VM()
    vm.load(PADDLE)
    if locked:
        make_layer(vm, 'PADDLE-DEMO', flags=4, color=3)
    return vm


vm = paddle_vm(True)
with locks_honoured():
    err = drive(vm, 'c:TUTORIALPADDLE', [None] * 7 + ['Yes'])
left = [e for e in vm.entities
        if e not in vm.deleted and vm.layer_of(e) == 'PADDLE-DEMO']
check("a PADDLE-DEMO left locked is unlocked for the demo",
      not err and not (layer_flags(vm, 'PADDLE-DEMO') & 4),
      err or 'flags %d' % layer_flags(vm, 'PADDLE-DEMO'))
check("...so Yes at the erase question takes every demo object away",
      not left and not getattr(vm, 'refused', 0),
      '%d left, %d refused' % (len(left), getattr(vm, 'refused', 0)))


def lock_then_yes(vm):
    set_lock(vm, 'PADDLE-DEMO', True)
    return 'Yes'


vm = paddle_vm(False)
with locks_honoured():
    err = drive(vm, 'c:TUTORIALPADDLE', [None] * 7 + [lock_then_yes])
check("an erase the lock refuses is said, not passed over",
      not err and getattr(vm, 'refused', 0)
      and 'demo object(s) on a locked layer - NOT erased' in said(vm),
      err or said(vm)[-200:])
check("the demo layer keeps its colour", any(
    isinstance(g, Dot) and g.a == 62 and g.b == 3
    for g in vm.recdata[layer_rec(vm, 'PADDLE-DEMO')]))


# ================================================================ [8]
print("OLAUTO -- a pick on a locked layer is refused before anything moves")


def olauto_vm():
    vm = VM()
    vm.load(OLAUTO)
    vm.sysvars['CLAYER'] = '0'
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    make_layer(vm, 'POOL')
    make_layer(vm, 'SURVEY', flags=4)
    return vm


for which in ('SECOND', 'FIRST'):
    vm = olauto_vm()
    new = circle(vm, (0, 0), 100.0, layer='POOL')
    og = circle(vm, (40, 25), 102.0, layer='SURVEY')
    picks = [[new], [og]] if which == 'SECOND' else [[og], [new]]
    before = {e: [list(g) if isinstance(g, list) else g
                  for g in vm.entdata[e]] for e in (new, og)}
    with locks_honoured():
        err = drive(vm, 'c:OLAUTO', picks)
    out = said(vm)
    check("the %s pick on a locked layer is named, and the run stops" % which,
          not err and 'layer "SURVEY" is locked' in out
          and 'Unlock "SURVEY" first, then run OLAUTO again' in out,
          err or out[-300:])
    check("...before a question is asked", not vm.prompts or all(
        'NEW perimeter' not in str(p) for p, _ in vm.prompts),
        repr([p for p, _ in vm.prompts]))
    check("...and nothing was moved, re-layered or dimensioned",
          all(vm.entdata[e] == before[e] for e in (new, og))
          and not alive(vm, 'DIMENSION')
          and not getattr(vm, 'refused', 0))

# the names read as a sentence
vm = VM()
vm.load(OLAUTO)
check("ola:names joins two with 'and', three with commas",
      vm.loads('(ola:names (list "A" "B"))') == '"A" and "B"'
      and vm.loads('(ola:names (list "A" "B" "C"))') == '"A", "B" and "C"',
      repr(vm.loads('(ola:names (list "A" "B" "C"))')))


if failures:
    print(f"\n{len(failures)} check(s) FAILED")
    sys.exit(1)
print("\nall guard-fix checks passed")
