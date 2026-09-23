"""The VM's two *error* modes, pinned against what AutoCAD does.

A handler is the only code that runs on Esc, and the VM used to run
every handler the kind way: with every frame of the failing command
still live, whatever mode the command had put in force.  So a handler
that read a local of its command, or called a helper the command had
defined in its arglist, passed here and died in AutoCAD.  SPA's did,
and eleven others (STANDARDS.md section 5).  The model now:

  PUSHED   after (*push-error-using-command*) AutoCAD resets the
           evaluator BEFORE *error* runs.  The handler it calls is the
           one in force at the failure -- a (defun *error* ...) the
           command declared local included -- but every other binding
           on the call stack is gone: a local reads its GLOBAL value, a
           local helper is undefined, a setq writes the global.
           (command) is what the mode is for; command-s is refused past
           vl-catch-all-apply.
  DEFAULT  no push (or after the pop): the stack is live, command-s is
           the way to drive a command, and a bare (command) is refused
           -- "Cannot invoke (command) from *error* without prior call
           to (*push-error-using-command*)".

and in either mode an error INSIDE the handler ends it at that form:
nothing after it runs, it is not run a second time, and the command
comes back raising (lispvm.HandlerDeath) -- what the drafter sees is a
raw error line and no report.  A pop with nothing pushed fails run()
the way an open undo group does.

Each pin names the source it relies on.  Where AutoCAD's behaviour is
not documented the VM does not model it and nothing here pins it:
whether AutoCAD re-enters *error* for an error raised inside *error*,
and whether vl-catch-all-apply catches the default-mode (command)
refusal (the VM lets it, and P13 pins only that the command is not
sent).

The file imports nothing the old VM lacks, so it runs against an older
tests/lispvm.py too and names the pins that VM fails.

Run: python3 tests/test_lispvm_errmode.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Sym, NIL, T  # noqa: E402

# ---------------------------------------------------------------- sources
PUSH_RESET = ("AutoLISP Reference, *push-error-using-command*: 'all local "
              "symbols on the AutoLISP call stack are pushed out of scope "
              "because the AutoLISP evaluator is reset before entering the "
              "*error* handler' (quoted, STANDARDS.md section 5)")
PUSH_HELPER = ("STANDARDS.md section 5: 'a helper defun declared in the "
               "command's arglist is undefined' under a push")
PUSH_FOUND = ("SPA's LOCAL handler ran under its push and died at command-s "
              "(test_handler_error_mode.py): the handler called is the one "
              "in force at the failure")
PUSH_CMD = ("AutoLISP Reference, *push-error-using-command*: 'Indicates "
            "the use of the command function in a custom *error* handler'")
PUSH_CMDS = ("STANDARDS.md section 5 / test_handler_error_mode.py: "
             "command-s 'is refused under a push, uncatchably' -- SPA's "
             "handler died on it")
DEFAULT_LIVE = ("STANDARDS.md section 5: 'The default mode is the reverse: "
                "locals are visible, command-s works, a bare (command) is "
                "refused'")
DEFAULT_CMD = ("AutoCAD 2015+: 'Cannot invoke (command) from *error* without "
               "prior call to (*push-error-using-command*)' (STANDARDS.md "
               "section 5, check_handlers.py H4)")
AFTER_POP = ("the repo's reading, not Autodesk's words: check_handlers.py "
             "'default (no push, or after *pop-error-mode*)', and "
             "test_handler_error_mode.py 'command-s after the pop is legal'")
DEATH = ("STANDARDS.md section 5: 'An error raised inside *error* aborts "
         "the handler: every form after the throwing one is skipped'")
UNDERFLOW = ("a *pop-error-mode* with nothing pushed pops a mode this "
             "command never pushed (check_handlers.py H6; lispvm's own "
             "error_mode_underflow count)")
CONTRACT = "lispvm test API, kept"

POP = '(if *pop-error-mode* (*pop-error-mode*))'
PUSH = '(if *push-error-using-command* (*push-error-using-command*))'


# ---------------------------------------------------------------- driving
def esc(vm):
    raise LispError('Function cancelled', vm)


def drive(src, script=None, setup='', handle=True):
    """Load SRC (which defines c:T) and run it; (vm, the LispError run()
    raised or None)."""
    vm = VM()
    vm.handle_errors = handle
    if setup:
        vm.loads(setup)
    vm.loads(src)
    try:
        vm.run('c:T', [esc] if script is None else script)
        return vm, None
    except LispError as e:
        return vm, e


def g(vm, name):
    return vm.globals.get(Sym(name), NIL)


def sent(vm, name):
    return any(c and c[0] == name for c in vm.commands)


def first(e):
    return str(e).splitlines()[0] if e is not None else None


def died(e):
    """run() came back raising a handler death -- by class where the VM
    has one, else by the message the refusal or the death carries."""
    if e is None:
        return False
    death = getattr(lispvm, 'HandlerDeath', None)
    if death is not None:
        return isinstance(e, death)
    return isinstance(e, getattr(lispvm, 'HandlerAbort', ()))


def cmd(handler, body='(setq flag "LOCAL") (getpoint "\\nPick: ")',
        push=True, locals_='flag'):
    """c:T with HANDLER as its local *error*, pushing first when PUSH,
    and popping again on its clean exit."""
    return '''
      (defun c:T ( / *error* %s)
        (defun *error* (msg) %s (princ))
        %s
        %s
        %s
        (princ))''' % (locals_, handler, PUSH if push else '', body,
                       POP if push else '')


# ---------------------------------------------------------------- the pins
PINS = []


def pin(pid, rule, source):
    def wrap(fn):
        PINS.append((pid, rule, source, fn))
        return fn
    return wrap


@pin('P1', 'pushed: a command local reads nil in *error*', PUSH_RESET)
def _p1():
    vm, e = drive(cmd('(setq t:*saw* (list flag)) ' + POP))
    return e is None and g(vm, 't:*saw*') == [NIL], (first(e), g(vm, 't:*saw*'))


@pin('P1b', "pushed: ...and a global of the same name is what it reads",
     PUSH_RESET)
def _p1b():
    vm, e = drive(cmd('(setq t:*saw* (list flag)) ' + POP),
                  setup='(setq flag "GLOBAL")')
    return (e is None and g(vm, 't:*saw*') == ["GLOBAL"],
            (first(e), g(vm, 't:*saw*')))


@pin('P2', 'pushed: a helper defined in the command arglist is undefined; '
     'the handler dies at that call and nothing after it runs',
     PUSH_HELPER)
def _p2():
    vm, e = drive('''
      (defun c:T ( / *error* t:finish)
        (defun t:finish () (setq t:*finished* T))
        (defun *error* (msg)
          (setq t:*entered* T) (t:finish) (setq t:*after* T) %s (princ))
        %s
        (getpoint "\\nPick: ")
        %s)''' % (POP, PUSH, POP))
    ok = (died(e) and g(vm, 't:*entered*') is T
          and g(vm, 't:*finished*') is NIL and g(vm, 't:*after*') is NIL
          and vm.error_mode_depth == 1)
    return ok, (first(e), g(vm, 't:*finished*'), g(vm, 't:*after*'),
                vm.error_mode_depth)


@pin('P3', 'pushed: the handler run is the command\'s LOCAL *error*, '
     'not the global one', PUSH_FOUND)
def _p3():
    vm, e = drive(cmd('(setq t:*local-ran* T) ' + POP),
                  setup='(defun *error* (msg) (setq t:*global-ran* T))')
    ok = (e is None and g(vm, 't:*local-ran*') is T
          and g(vm, 't:*global-ran*') is NIL)
    return ok, (first(e), g(vm, 't:*local-ran*'), g(vm, 't:*global-ran*'))


@pin('P4', 'pushed: a failure two calls deep -- no frame on the stack is '
     'visible, the helper\'s own locals included', PUSH_RESET)
def _p4():
    vm, e = drive(cmd('(setq t:*saw* (list flag x)) ' + POP,
                      body='(setq flag "LOCAL") (t:outer)'),
                  setup='''
      (defun t:inner ( / x) (setq x "INNER") (getpoint "\\nPick: "))
      (defun t:outer () (t:inner))''')
    return (e is None and g(vm, 't:*saw*') == [NIL, NIL],
            (first(e), g(vm, 't:*saw*')))


@pin('P5', 'pushed: a setq of a command local in *error* writes the GLOBAL',
     PUSH_RESET)
def _p5():
    vm, e = drive(cmd('(setq flag "SET-IN-HANDLER") ' + POP))
    return (e is None and g(vm, 'flag') == "SET-IN-HANDLER",
            (first(e), g(vm, 'flag')))


@pin('P5b', 'pushed: (setq *error* olderr) writes the global *error* from '
     'the GLOBAL olderr -- the swap idiom clobbers the session\'s handler',
     PUSH_RESET)
def _p5b():
    vm, e = drive('''
      (defun c:T ( / *error* olderr)
        (setq olderr *error*)
        (defun *error* (msg) (setq *error* olderr) %s (princ))
        %s
        (getpoint "\\nPick: ")
        %s
        (setq *error* olderr))''' % (POP, PUSH, POP),
                  setup='(defun *error* (msg) (princ "session handler"))')
    return e is None and g(vm, '*error*') is NIL, (first(e), g(vm, '*error*'))


@pin('P6', 'pushed: a GLOBAL helper the handler calls reads the command\'s '
     'local free -- and gets the global', PUSH_RESET)
def _p6():
    vm, e = drive(cmd('(t:restore) ' + POP),
                  setup='(defun t:restore () (setq t:*saw* (list flag)))')
    return (e is None and g(vm, 't:*saw*') == [NIL],
            (first(e), g(vm, 't:*saw*')))


@pin('P7', 'pushed: popping inside *error* does not bring the locals back '
     '(the reset came before the handler was entered)', PUSH_RESET)
def _p7():
    vm, e = drive(cmd(POP + ' (setq t:*saw* (list flag))'))
    return (e is None and g(vm, 't:*saw*') == [NIL],
            (first(e), g(vm, 't:*saw*')))


@pin('P8', 'pushed: a bare (command) in *error* is allowed and sent',
     PUSH_CMD)
def _p8():
    vm, e = drive(cmd('(command "_.REGEN") (setq t:*after* T) ' + POP))
    ok = e is None and sent(vm, '_.REGEN') and g(vm, 't:*after*') is T
    return ok, (first(e), vm.commands, g(vm, 't:*after*'))


@pin('P9', 'pushed: command-s in *error* is refused past '
     'vl-catch-all-apply -- the handler dies there', PUSH_CMDS)
def _p9():
    vm, e = drive(cmd('(vl-catch-all-apply (quote command-s) '
                      '(list "_.REGEN")) (setq t:*after* T) ' + POP))
    ok = (isinstance(e, getattr(lispvm, 'HandlerAbort', ()))
          and not sent(vm, '_.REGEN') and g(vm, 't:*after*') is NIL)
    return ok, (first(e), vm.commands, g(vm, 't:*after*'))


@pin('P10', 'default: *error* sees the command\'s locals (the stack is live)',
     DEFAULT_LIVE)
def _p10():
    vm, e = drive(cmd('(setq t:*saw* (list flag))', push=False))
    return (e is None and g(vm, 't:*saw*') == ["LOCAL"],
            (first(e), g(vm, 't:*saw*')))


@pin('P11', 'default: a bare (command) in *error* is refused -- not sent, '
     'the handler dies there, run() raises', DEFAULT_CMD)
def _p11():
    vm, e = drive(cmd('(setq t:*entered* T) (command "_.REGEN") '
                      '(setq t:*after* T)', push=False))
    ok = (died(e) and 'Cannot invoke (command) from *error*' in str(e)
          and not sent(vm, '_.REGEN') and g(vm, 't:*entered*') is T
          and g(vm, 't:*after*') is NIL)
    return ok, (first(e), vm.commands, g(vm, 't:*after*'))


@pin('P12', 'default: ...through a helper the handler calls, too',
     DEFAULT_CMD)
def _p12():
    vm, e = drive(cmd('(t:close) (setq t:*after* T)', push=False),
                  setup='(defun t:close () (command "_.REGEN"))')
    ok = died(e) and not sent(vm, '_.REGEN') and g(vm, 't:*after*') is NIL
    return ok, (first(e), vm.commands, g(vm, 't:*after*'))


@pin('P13', 'default: a refused (command) wrapped in vl-catch-all-apply is '
     'still never sent (whichever spelling)', DEFAULT_CMD)
def _p13():
    out = []
    for call in ('(vl-catch-all-apply (quote command) (list "_.REGEN"))',
                 '(vl-catch-all-apply (function (lambda () '
                 '(command "_.REGEN"))) nil)'):
        vm, e = drive(cmd(call, push=False))
        out.append(not sent(vm, '_.REGEN'))
    return all(out), out


@pin('P14', 'default: command-s in *error* is allowed and sent',
     DEFAULT_LIVE)
def _p14():
    vm, e = drive(cmd('(command-s "_.REGEN") (setq t:*after* T)',
                      push=False))
    ok = e is None and sent(vm, '_.REGEN') and g(vm, 't:*after*') is T
    return ok, (first(e), vm.commands, g(vm, 't:*after*'))


@pin('P15', 'pushed then popped inside *error*: command-s is legal again, '
     'a bare (command) is refused', AFTER_POP)
def _p15():
    vm1, e1 = drive(cmd(POP + ' (vl-catch-all-apply (quote command-s) '
                        '(list "_.REGEN")) (setq t:*after* T)'))
    vm2, e2 = drive(cmd(POP + ' (command "_.REDRAW") (setq t:*after* T)'))
    ok = (e1 is None and sent(vm1, '_.REGEN') and g(vm1, 't:*after*') is T
          and died(e2) and not sent(vm2, '_.REDRAW')
          and g(vm2, 't:*after*') is NIL)
    return ok, (first(e1), first(e2), vm2.commands)


DEEP = '''
  (defun t:b () (getpoint "\\nPick: "))
  (defun t:a () (t:b))'''


@pin('P16', 'an error inside *error* ends it at that form: it runs ONCE, '
     'nothing after the throw runs, run() raises', DEATH)
def _p16():
    vm, e = drive(cmd('(setq t:*runs* (1+ (cond (t:*runs*) (0)))) '
                      '(t:no-such-function) (setq t:*after* T)',
                      body='(t:a)', push=False), setup=DEEP)
    ok = (died(e) and g(vm, 't:*runs*') == 1 and g(vm, 't:*after*') is NIL
          and vm.handled_errors == ['Function cancelled'])
    return ok, (first(e), g(vm, 't:*runs*'), g(vm, 't:*after*'),
                vm.handled_errors)


@pin('P16b', '...so a handler that dies only on its first run is not '
     'rescued by a second one', DEATH)
def _p16b():
    vm, e = drive(cmd('(if (not t:*once*) (progn (setq t:*once* T) '
                      '(t:no-such-function))) (setq t:*after* T)',
                      body='(t:a)', push=False), setup=DEEP)
    return died(e) and g(vm, 't:*after*') is NIL, (first(e),
                                                    g(vm, 't:*after*'))


@pin('P17', 'a pop with nothing pushed fails run(), as an open undo group '
     'does', UNDERFLOW)
def _p17():
    vm, e = drive('(defun c:T () %s (princ))' % POP, script=[])
    ok = e is not None and 'nothing pushed' in str(e)
    return ok, (first(e), vm.error_mode_underflow)


@pin('P17b', '...a handler that pops a mode an Esc BEFORE the push never '
     'pushed fails it too', UNDERFLOW)
def _p17b():
    vm, e = drive('''
      (defun c:T ( / *error*)
        (defun *error* (msg) %s (princ))
        (getpoint "\\nPick: ")
        %s
        %s)''' % (POP, PUSH, POP))
    ok = e is not None and 'nothing pushed' in str(e)
    return ok, (first(e), vm.error_mode_underflow)


@pin('P18', 'pushed: a (setq *error* (lambda ...)) handler sees globals only '
     'too', PUSH_RESET)
def _p18():
    vm, e = drive('''
      (defun c:T ( / *error* flag)
        (setq *error* (lambda (msg) (setq t:*saw* (list flag)) %s (princ)))
        %s
        (setq flag "LOCAL")
        (getpoint "\\nPick: ")
        %s)''' % (POP, PUSH, POP))
    return (e is None and g(vm, 't:*saw*') == [NIL],
            (first(e), g(vm, 't:*saw*')))


@pin('P19', 'pushed: the handler\'s own argument and locals are its own',
     PUSH_RESET)
def _p19():
    vm, e = drive('''
      (defun c:T ( / *error*)
        (defun *error* (msg / tmp)
          (setq tmp msg t:*saw* (list msg tmp)) %s (princ))
        %s
        (getpoint "\\nPick: ")
        %s)''' % (POP, PUSH, POP))
    want = ['Function cancelled', 'Function cancelled']
    return e is None and g(vm, 't:*saw*') == want, (first(e),
                                                    g(vm, 't:*saw*'))


@pin('C1', 'handle_errors off: the error propagates, no handler runs',
     CONTRACT)
def _c1():
    vm, e = drive(cmd('(setq t:*ran* T) ' + POP), handle=False)
    ok = (e is not None and first(e) == 'Function cancelled'
          and g(vm, 't:*ran*') is NIL and vm.handled_errors == [])
    return ok, (first(e), g(vm, 't:*ran*'))


@pin('C2', 'a handler that never pops still fails run() (mode left pushed)',
     CONTRACT)
def _c2():
    vm, e = drive(cmd('(setq t:*ran* T)'))
    return (e is not None and 'still pushed' in str(e)
            and g(vm, 't:*ran*') is T, first(e))


@pin('C3', 'an underflow is charged to the run that made it, not to the '
     'clean run after it on the same VM', CONTRACT)
def _c3():
    vm, e = drive('(defun c:T () %s (princ))' % POP, script=[])
    vm.loads('(defun c:U () (princ))')
    try:
        vm.run('c:U', [])
        e2 = None
    except LispError as x:
        e2 = x
    return e is not None and e2 is None, (first(e), first(e2))


def main():
    fails = []
    for pid, rule, source, fn in PINS:
        try:
            ok, detail = fn()
        except Exception as x:          # a pin must report, never crash
            ok, detail = False, 'raised %s: %s' % (
                type(x).__name__, str(x).splitlines()[0])
        print('  %-4s %-4s %s' % ('ok' if ok else 'FAIL', pid, rule))
        if not ok:
            print('            got: %r' % (detail,))
            print('            source: %s' % source)
            fails.append(pid)
    if fails:
        print('\n%d of %d errmode pins FAILED: %s'
              % (len(fails), len(PINS), ' '.join(fails)))
        sys.exit(1)
    print('\nALL %d ERRMODE PINS PASSED' % len(PINS))


if __name__ == '__main__':
    main()
