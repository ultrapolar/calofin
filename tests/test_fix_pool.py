#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""POOL, POOLSIDE, TUTORIALPOOL and POOLDEMO: the quiet failures the
2026-09 audit found, each driven the way a drafter meets it.

  * the undo group every one of them opens is closed again when the run
    is cut short, under AutoCAD's PUSHED error mode -- which resets the
    evaluator before *error* runs, so a local of the command reads nil
    in the handler.  The VM keeps every frame live, so that reset is
    modelled here (pushed_mode_unwind) the way the audit modelled it.
  * a ruler drawn onto a LOCKED scratch layer is still taken down: the
    VM has no layer lock, so entdel is made to refuse on one here, as
    AutoCAD's does.
  * a run cut short at the Given-dimension pick leaves nothing for the
    next POOL, TUTORIALPOOL or POOLDEMO to pick up.
  * a click on empty space at that pick is said and asked again rather
    than read as Enter.

Run: python3 tests/test_fix_pool.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_fix_pool.py
"""

import contextlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import lispvm  # noqa: E402
from lispvm import VM, LispError, Sym, Dot, NIL, BUILTINS, Ent  # noqa: E402

POOL = os.path.join(REPO, 'lisp', 'pool', 'POOL.LSP')
TUT = os.path.join(REPO, 'lisp', 'pool', 'TUTORIALPOOL.LSP')
DEMO = os.path.join(REPO, 'lisp', 'pool', 'POOLDEMO.LSP')
SIDE = os.path.join(REPO, 'lisp', 'poolside', 'POOLSIDE.lsp')
BASE = [(0.0, 0.0, 0.0)]

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


def esc(vm):
    raise LispError('Function cancelled', vm)


def attempt(label, fn):
    """Run FN; a LispError out of it is a failed check, not a crash, so
    the file still reports every scenario."""
    try:
        return fn()
    except LispError as e:
        check(label, False, str(e).splitlines()[0])
        return None


# --------------------------------------------------------------------
# the pushed error mode, modelled
# --------------------------------------------------------------------
@contextlib.contextmanager
def pushed_mode_unwind():
    """After (*push-error-using-command*) AutoCAD resets the AutoLISP
    evaluator before it calls *error*: the handler in force at the
    failure runs, but every binding the failing command made is gone,
    so its locals read their GLOBAL value.  The stock VM runs the
    handler with every frame live.  Here the stack is swapped out for
    the handler call and put back after, while a mode is pushed."""
    orig = VM.call_defun

    def call_defun(self, name, fn, args):
        _, params, locals_, body = fn
        if len(args) != len(params):
            raise LispError("%s: expected %d args, got %d"
                            % (name, len(params), len(args)), self)
        frame = dict(zip(params, args))
        for loc in locals_:
            frame[loc] = NIL
        self.stack.append(frame)
        self.calls.append(name)
        try:
            r = NIL
            for form in body:
                r = self.eval(form)
            return r
        except LispError as e:
            if (self.handle_errors and not self._catch_depth
                    and not self._in_handler
                    and not getattr(e, 'handled', False)):
                h = self.get(Sym('*error*'))      # the one in force, BEFORE
                if (isinstance(h, tuple) and h[0] == 'defun') or (
                        isinstance(h, list) and h and h[0] == 'lambda'):
                    e.handled = True
                    msg = str(e).split('\n')[0]
                    self.handled_errors.append(msg)
                    self._in_handler = True
                    unwind = self.error_mode_depth > 0
                    saved = self.stack
                    if unwind:
                        self.stack = []
                    try:
                        if isinstance(h, tuple):
                            self.call_defun(Sym('*error*'), h, [msg])
                        else:
                            self.call_lambda(h, [msg])
                    except LispError as inner:
                        if isinstance(inner, lispvm.HandlerAbort):
                            raise
                        raise LispError("*error* handler died: %s"
                                        % str(inner).splitlines()[0], self)
                    finally:
                        if unwind:
                            self.stack = saved
                        self._in_handler = False
            raise
        finally:
            self.stack.pop()
            self.calls.pop()

    VM.call_defun = call_defun
    try:
        yield
    finally:
        VM.call_defun = orig


# --------------------------------------------------------------------
# a locked layer, modelled
# --------------------------------------------------------------------
@contextlib.contextmanager
def entdel_refuses_on_locked_layers():
    """entmake draws onto a locked layer; entdel refuses there and
    answers nil.  The VM has no lock, so entdel is taught one."""
    orig = BUILTINS[Sym('entdel')]
    tbl = BUILTINS[Sym('tblsearch')]

    def entdel(vm, a):
        e = a[0]
        lay = vm.layer_of(e) if isinstance(e, Ent) else None
        if lay:
            rec = tbl(vm, ['LAYER', lay]) or []
            fl = next((g.b for g in rec
                       if isinstance(g, Dot) and g.a == 70), 0)
            if int(fl) & 4:
                return NIL
        return orig(vm, a)

    BUILTINS[Sym('entdel')] = entdel
    try:
        yield
    finally:
        BUILTINS[Sym('entdel')] = orig


def layer(vm, name, flags=0):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
             ' \'(62 . 7) \'(6 . "Continuous")))' % (name, flags))


def layer_flags(vm, name):
    rec = vm.loads('(tblsearch "LAYER" "%s")' % name) or []
    return next((g.b for g in rec if isinstance(g, Dot) and g.a == 70), None)


def live_on(vm, lay):
    return [e for e in vm.entities
            if e not in vm.deleted and vm.layer_of(e) == lay]


def undo_subs(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def pool_vm(*extra):
    vm = VM()
    vm.load(POOL)
    for p in extra:
        vm.load(p)
    return vm


def glob(vm, name):
    return vm.globals.get(Sym(name), NIL)


# ====================================================================
print("== F3. POOL cut short under the pushed mode closes its undo group ==")
# the handler read undo-open, a local of c:POOL; after the reset it is
# nil, and the group POOL opened stayed open round the drafter's next
# edits -- one U took them back with the pool
for label, script in [
        ("Esc at the first question", [esc]),
        ("Esc at the first wall length (guide up)",
         ["Outofsquare", "Rectangle"] + BASE + [esc])]:
    with pushed_mode_unwind():
        vm = pool_vm()
        vm.handle_errors = True
        attempt(label, lambda: vm.run('c:POOL', script))
    check(label + ": the handler ran",
          vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
    check(label + ": no undo group left open", vm.undo_groups == 0,
          "%d open, sent %r" % (vm.undo_groups, undo_subs(vm)))
    check(label + ": _Begin and _End, once each",
          undo_subs(vm) == ['_Begin', '_End'], repr(undo_subs(vm)))
    check(label + ": the error mode popped", vm.error_mode_depth == 0)
    check(label + ": OSMODE is back", vm.sysvars.get('OSMODE') ==
          VM().sysvars.get('OSMODE'))
    check(label + ": the flag is down after", glob(vm, 'pool:*undo-open*') is NIL)

print("== F3b. a flag a dead run left up is never read by the next ==")
# UNDOCTL off: this run opens nothing, so its handler must close nothing
# -- a stale T from an earlier run must not reach UNDO _End
vm = pool_vm()
vm.handle_errors = True
vm.loads('(setq pool:*undo-open* T)')
vm.sysvars['UNDOCTL'] = 0
attempt("stale flag", lambda: vm.run('c:POOL', [esc]))
check("stale flag: nothing sent to UNDO", undo_subs(vm) == [],
      repr(undo_subs(vm)))
check("stale flag: the handler did not die",
      not any('handler died' in s for s in vm.handled_errors))

# ====================================================================
print("== F4. POOLSIDE cut short under the pushed mode closes its group ==")
with pushed_mode_unwind():
    vm = VM()
    vm.load(SIDE)
    vm.handle_errors = True
    attempt("POOLSIDE Esc", lambda: vm.run('c:POOLSIDE', ["Normal", esc]))
check("POOLSIDE: the handler ran", vm.handled_errors == ['Function cancelled'],
      repr(vm.handled_errors))
check("POOLSIDE: no undo group left open", vm.undo_groups == 0,
      "sent %r" % undo_subs(vm))
check("POOLSIDE: _Begin and _End, once each",
      undo_subs(vm) == ['_Begin', '_End'], repr(undo_subs(vm)))
check("POOLSIDE: the error mode popped", vm.error_mode_depth == 0)

print("== F4b. ...and Esc at a depth, with the ruler standing ==")
with pushed_mode_unwind():
    vm = VM()
    vm.load(SIDE)
    vm.handle_errors = True
    attempt("POOLSIDE Esc at C",
            lambda: vm.run('c:POOLSIDE', ["Normal"] + BASE +
                           [480.0, 60.0, 90.0, 240.0, 90.0, esc]))
check("POOLSIDE at C: no undo group left open", vm.undo_groups == 0,
      "sent %r" % undo_subs(vm))
check("POOLSIDE at C: the ruler came down",
      not live_on(vm, 'POOLSIDE-RULER'))

# ====================================================================
print("== F5. TUTORIALPOOL and POOLDEMO under the pushed mode ==")
with pushed_mode_unwind():
    vm = pool_vm(TUT)
    vm.handle_errors = True
    attempt("TUTORIALPOOL Esc", lambda: vm.run('c:TUTORIALPOOL', ['', esc]))
check("TUTORIALPOOL: the handler ran",
      vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
check("TUTORIALPOOL: no undo group left open", vm.undo_groups == 0,
      "sent %r" % undo_subs(vm))
check("TUTORIALPOOL: _Begin and _End, once each",
      undo_subs(vm) == ['_Begin', '_End'], repr(undo_subs(vm)))

with pushed_mode_unwind():
    vm = pool_vm(DEMO)
    # the VM's (atoms-family 0) is empty, so the POOL-loaded gate is
    # answered the way test_tutorialpool answers it; then one cell fails
    vm.loads("(defun atoms-family (n) (list 'pool:hopcalc))")
    vm.loads("(defun pooldemo:c3 (org) (pooldemo:no-such-helper org))")
    vm.handle_errors = True
    attempt("POOLDEMO failure", lambda: vm.run('c:POOLDEMO', []))
check("POOLDEMO: the handler ran", len(vm.handled_errors) == 1,
      repr(vm.handled_errors))
check("POOLDEMO: no undo group left open", vm.undo_groups == 0,
      "sent %r" % undo_subs(vm))
check("POOLDEMO: _Begin and _End, once each",
      undo_subs(vm) == ['_Begin', '_End'], repr(undo_subs(vm)))

# ====================================================================
print("== F6. a ruler drawn on a LOCKED scratch layer is still taken down ==")
with entdel_refuses_on_locked_layers():
    vm = pool_vm()
    layer(vm, 'POOL-RULER', 4)
    attempt("POOL locked ruler",
            lambda: vm.run('c:POOL', ["Insquare", "Rectangle"] + BASE +
                           [480.0, 240.0, "Radius", 24.0, "No"]))
check("POOL: the ruler was drawn at all",
      any(vm.layer_of(e) == 'POOL-RULER' for e in vm.entities))
check("POOL: nothing is left on POOL-RULER", not live_on(vm, 'POOL-RULER'),
      "%d left" % len(live_on(vm, 'POOL-RULER')))
check("POOL: the layer is unlocked", not (layer_flags(vm, 'POOL-RULER') or 0) & 4)
check("POOL: and the drafter was told",
      any('POOL-RULER was locked' in s for s in vm.printed))

with entdel_refuses_on_locked_layers():
    vm = VM()
    vm.load(SIDE)
    layer(vm, 'POOLSIDE-RULER', 4)
    attempt("POOLSIDE locked ruler",
            lambda: vm.run('c:POOLSIDE', ["Normal"] + BASE +
                           [480.0, 60.0, 90.0, 240.0, 90.0, 42.0, 96.0,
                            "No"]))
check("POOLSIDE: the ruler was drawn at all",
      any(vm.layer_of(e) == 'POOLSIDE-RULER' for e in vm.entities))
check("POOLSIDE: nothing is left on POOLSIDE-RULER",
      not live_on(vm, 'POOLSIDE-RULER'),
      "%d left" % len(live_on(vm, 'POOLSIDE-RULER')))
check("POOLSIDE: and the drafter was told",
      any('POOLSIDE-RULER was locked' in s for s in vm.printed))

# a layer the drafter switched OFF is left off: the ruler has a layer
# of its own so that it CAN be hidden, and only the lock is undone
vm = pool_vm()
vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
         ' \'(100 . "AcDbLayerTableRecord") \'(2 . "POOL-RULER") \'(70 . 4)'
         ' \'(62 . -7) \'(6 . "Continuous")))')
attempt("POOL off+locked ruler",
        lambda: vm.run('c:POOL', ["Insquare", "Rectangle"] + BASE +
                       [480.0, 240.0, "Radius", 24.0, "No"]))
rec = vm.loads('(tblsearch "LAYER" "POOL-RULER")') or []
check("POOL: an OFF ruler layer stays off",
      next((g.b for g in rec if isinstance(g, Dot) and g.a == 62), 0) < 0)

# ====================================================================
# 240 x 120 out of square with crossing diagonals 268 / 400: the cross
# dims fail, so the Given opt-in is offered
GIVEN_RUN = (["Outofsquare", "Rectangle"] + BASE +
             [240.0, 240.0, 120.0, 120.0, "Square", None, None, None,
              268.0, 400.0, "No", "Yes"])
CLEAN_RUN = ["Insquare", "Rectangle"] + BASE + [480.0, 240.0, "Square", "No"]


def given_texts(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = dict((g.a, g.b) for g in vm.entdata[e] if isinstance(g, Dot))
        if d.get(0) == 'TEXT' and 'Given' in str(d.get(1, '')) \
                and 'Not Given' not in str(d.get(1, '')):
            out.append(d.get(1))
    return out


print("== F7. Esc at the Given-dimension pick leaves nothing behind ==")
vm = pool_vm(TUT)
vm.handle_errors = True
attempt("Given run cut short", lambda: vm.run('c:POOL', GIVEN_RUN + [esc]))
check("the cut-short run did mark Given", len(given_texts(vm)) > 0)
check("pool:*giveask* is down after the Esc", glob(vm, 'pool:*giveask*') is NIL)
check("pool:*giventxts* is empty after the Esc",
      glob(vm, 'pool:*giventxts*') is NIL)
vm.printed = []
marks_before = len(given_texts(vm))
attempt("the next, clean POOL", lambda: vm.run('c:POOL', CLEAN_RUN))
check("the next POOL says nothing about Given marks",
      not any('marked Given' in s for s in vm.printed))
check("...and draws none", len(given_texts(vm)) == marks_before,
      "%d -> %d" % (marks_before, len(given_texts(vm))))

# TUTORIALPOOL after a POOL that died at the pick draws its report with
# no Given marks, exactly as it does in a fresh drawing.  The flags are
# forced up directly here as well: that is the state a POOL.LSP loaded
# before this fix (or a crash inside *error*) leaves, and the tutorial
# must not trust it
control = pool_vm(TUT)
attempt("tutorial control", lambda: control.run('c:TUTORIALPOOL', [''] * 8))
vm = pool_vm(TUT)
vm.loads('(setq pool:*giveask* T)')
attempt("tutorial after", lambda: vm.run('c:TUTORIALPOOL', [''] * 8))
check("TUTORIALPOOL draws no Given marks after a stale opt-in",
      len(given_texts(vm)) == len(given_texts(control)),
      "%r vs control %r" % (given_texts(vm), given_texts(control)))

vm = pool_vm(DEMO)
vm.loads("(defun atoms-family (n) (list 'pool:hopcalc))")
vm.loads('(setq pool:*giveask* T)')
control = pool_vm(DEMO)
control.loads("(defun atoms-family (n) (list 'pool:hopcalc))")
attempt("demo control", lambda: control.run('c:POOLDEMO', []))
attempt("demo after", lambda: vm.run('c:POOLDEMO', []))
check("POOLDEMO draws no Given marks after a stale opt-in",
      len(given_texts(vm)) == len(given_texts(control)),
      "%r vs control %r" % (given_texts(vm), given_texts(control)))

# ====================================================================
print("== F11. a missed click at the Given pick is said and asked again ==")


def miss(vm):
    # entsel on empty space: nil, with ERRNO 7 -- Enter leaves ERRNO 0
    vm.sysvars['ERRNO'] = 7
    return None


def pick_first_mark(vm):
    pairs = glob(vm, 'pool:*giventxts*') or []
    en = pairs[-1].a if pairs else None
    return [en, [0.0, 0.0, 0.0]] if en else None


vm = pool_vm()
attempt("miss then pick",
        lambda: vm.run('c:POOL', GIVEN_RUN + [miss, pick_first_mark, None]))
said = ''.join(vm.printed)
check("the miss was named", 'Nothing there - click the dimension text' in said)
check("the pick after it still flipped a mark",
      any("'" in t for t in given_texts(vm))
      and any("'" not in t for t in given_texts(vm)),
      repr(given_texts(vm)))
check("Enter still ends it, and the list is cleared",
      glob(vm, 'pool:*giventxts*') is NIL)

# ====================================================================
print("== F8. the README spells a typed fraction the way the prompt reads it ==")
# the corner-size prompt is a getpoint: the spacebar is Enter there, so
# 1'-4 1/2" is taken as 1'-4 and the 1/2" answers the NEXT question
readme = open(os.path.join(REPO, 'lisp', 'pool', 'README.md'),
              encoding='utf-8').read()
check("the ruler's typed spellings show 1'-4-1/2\"",
      "`1'-4-1/2\"`" in readme and "`1'-4 1/2\"`" not in readme)

if FAILS:
    print("test_fix_pool: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_fix_pool: all checks passed (%s tier)"
      % (os.environ.get('CALOFIN_LISP_ROOT') or 'lisp'))
