"""The order the VM resolves a call's head in, pinned.

VM.eval runs once per call form -- millions of times in the big suites
-- so it looks the head up in one pass instead of the get() and
bound_local() walks it once made.  That pass is only correct while it
keeps the order those two gave between them, and each step of it is a
rule a routine can meet at the AutoCAD command line:

  1. a special form wins outright, whatever else the name is bound to;
  2. otherwise the INNERMOST frame binding the name decides: a defun
     there (a defun-local helper, a (defun *error* ...)) is called, and
     anything else -- a declared local, an argument, a foreach variable,
     a lambda held in a local -- is "no function definition", because
     the local hides the function, built-in or not, for as long as it
     is live.  The error comes before any argument is evaluated;
  3. then a global defun, which may override a built-in;
  4. then the built-ins, then "undefined function".

The special-form method names come from SF_NAME, mangled once at import
with the same chain eval once ran on every call; the pins at the end
hold that chain, so a special form added later with a name like
vl-catch-all-apply lands on the method it always would have.

Run: python3 tests/test_lispvm_dispatch.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Sym, NIL  # noqa: E402

FAILS = []
SHADOW = ("no function definition: %s -- it is declared as a local "
          "variable (or argument) of the defun being run, which shadows "
          "the function")


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def value(src):
    vm = VM()
    return vm, vm.loads(src)


def error(src):
    """(vm, the error's first line), or (vm, None) when nothing raised."""
    vm = VM()
    try:
        vm.loads(src)
    except LispError as e:
        return vm, str(e).split('\n')[0]
    return vm, None


# 1. a special form wins outright
_, got = value("(defun f ( / if) (if T 1 2)) (f)")
check("a special form wins over a local of the same name", got == 1,
      repr(got))
_, got = value("(defun progn (a b) 'mine) (progn 1 2)")
check("a special form wins over a global defun of the same name",
      got == 2, repr(got))

# 2. the innermost frame decides
_, got = value("(defun f ( / helper) (defun helper (x) (* x 2)) (helper 21))"
               "(f)")
check("a defun bound in a frame is called", got == 42, repr(got))
vm, got = value("(defun f ( / helper) (defun helper () 7)"
                "  (foreach x '(1) (setq r (helper))) r)"
                "(f)")
check("...found past an inner frame that does not bind it",
      got == 7, repr(got))
check("...and gone when its frame is", Sym('helper') not in vm.globals)
_, got = value("(defun g () 'global)"
               "(defun f ( / g) (defun g () 'local) (g))"
               "(f)")
check("a frame-bound defun beats a global one", got == 'local', repr(got))
_, msg = error("(defun f ( / last) (last '(1 2))) (f)")
check("a declared local shadows a built-in", msg == SHADOW % 'LAST', msg)
_, msg = error("(defun f (last) (last '(1 2))) (f 5)")
check("an argument shadows a built-in", msg == SHADOW % 'LAST', msg)
_, msg = error("(foreach last '(1) (last '(1 2)))")
check("a foreach variable shadows a built-in", msg == SHADOW % 'LAST', msg)
_, msg = error("(defun g () 'global) (defun f ( / g) (g)) (f)")
check("a local shadows a global defun", msg == SHADOW % 'G', msg)
_, msg = error("(defun f ( / g) (setq g (lambda () 1)) (g)) (f)")
check("a lambda held in a local is not called by name",
      msg == SHADOW % 'G', msg)
_, msg = error("(defun outer ( / h) (defun h () 1) (inner))"
               "(defun inner ( / h) (h))"
               "(outer)")
check("an inner local hides an outer frame's defun",
      msg == SHADOW % 'H', msg)
vm, msg = error("(defun f ( / last) (last (setq side 1))) (f)")
check("the shadow error comes before the arguments are evaluated",
      msg == SHADOW % 'LAST' and vm.globals.get(Sym('side')) is NIL,
      f"{msg!r}, side={vm.globals.get(Sym('side'))!r}")

# 3. a global defun, over a built-in
_, got = value("(defun abs (x) 'mine) (abs -1)")
check("a global defun overrides a built-in", got == 'mine', repr(got))

# 4. the built-ins, then undefined
_, got = value("(abs -3)")
check("a built-in is reached when nothing binds the name", got == 3,
      repr(got))
_, msg = error("(no-such-fn 1)")
check("an unbound head is an undefined function",
      msg == "undefined function: no-such-fn", msg)
_, msg = error("(setq myvar 5) (myvar)")
check("a global that holds a value is not a function",
      msg == "undefined function: myvar", msg)

# the heads that are not symbols
_, got = value("((lambda (x) (* x 2)) 4)")
check("a lambda in the head position is called", got == 8, repr(got))
_, msg = error("(1 2)")
check("a number in the head position is refused",
      msg == "bad function position: 1", msg)

# SF_NAME: every special form has its method, under the old mangling
missing = [s for s in lispvm.SPECIAL
           if not callable(getattr(VM, lispvm.SF_NAME[s], None))]
check("every special form has the method SF_NAME names", not missing,
      repr(missing))
check("SF_NAME covers exactly the special forms",
      set(lispvm.SF_NAME) == lispvm.SPECIAL)
for name, want in (('if', 'sf_if'), ('vl-catch-all-apply',
                                     'sf_vl_catch_all_apply'),
                   ('*error*', 'sf__error_'), ('a:b', 'sf_a_b'),
                   ('1+', 'sf_1plus'), ('/=', 'sf_slasheq'),
                   ('<=', 'sf_lteq'), ('>=', 'sf_gteq')):
    got = lispvm._sf_name(name)
    check(f"{name} dispatches to {want}", got == want, got)


class Traced(VM):
    """A subclass's own special-form method is the one dispatched to."""

    def sf_progn(self, a):
        self.traced = True
        return super().sf_progn(a)


t = Traced()
check("a subclass's special-form override is used",
      t.loads("(progn 1 2)") == 2 and getattr(t, 'traced', False))

if FAILS:
    print("test_lispvm_dispatch: %d FAILURE(S): %s"
          % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_lispvm_dispatch: all checks passed")
