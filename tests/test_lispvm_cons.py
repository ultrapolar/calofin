"""What is a list, pinned against what AutoCAD answers.

The VM answered four questions about conses more kindly than AutoCAD,
and each kind answer hid a tool that would be wrong in a drawing:

  listp    said nil for a dotted pair.  (listp '(8 . "0")) is T: a
           dotted pair is a cons, and every DXF group a tool reads with
           assoc is one.  A (cond ((listp g) ...) ...) took the atom
           branch here for every group pair, and LAZDIAG's encoder, which
           asks listp first, wrote a form store's (key . value) as a
           Python repr no replay could read.  It also said T for a
           SELECTION SET, which is a list in disguise in the VM and an
           atom in AutoCAD.
  type     said OTHER for a dotted pair, a type AutoLISP does not have.
           It is LIST.
  reader   read '(a . nil) as a dotted pair with a nil cdr.  It is the
           one-item list (a) -- what (cons 'a nil) already gave -- and
           a form store's (key . nil), the sheet's NA, is one.
  foreach  walked whatever Python could iterate: a string's characters,
           a selection set's '<ss>' marker and its enames, a dotted
           pair not at all (a Python TypeError, which no *error* in the
           code under test could see).  AutoCAD refuses a non-list, and
           walks a dotted pair's car before it refuses the atom cdr.

atom and vl-consp, which the VM did not have, answer as the complements.

Sources: the AutoLISP reference -- listp: "Returns T if the item is a
list, nil otherwise", with (listp '(a . b)) among the lists, since a
dotted pair is a cons; atom: "anything that is not a list is considered
an atom", nil an atom and a list; vl-consp: "Determines whether or not
a list is nil ... Returns T if list is a list and is not nil"; type:
LIST for a list, PICKSET for a selection set.  The foreach refusal of a
non-list is the reference's "bad argument type"; its dotted-pair
behaviour (car visited, then an error) follows from foreach walking cdr
by cdr, and the VM's message for it ("bad list") is not pinned.

Run: python3 tests/test_lispvm_cons.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, LispError, Sym, T, NIL  # noqa: E402

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def ev(src, vm=None):
    vm = vm or VM()
    try:
        return vm.loads(src)
    except LispError as e:
        return ("ERROR", str(e).splitlines()[0])


print("listp, atom, vl-consp and type on a dotted pair")
check("(listp '(8 . \"0\")) is T", ev("(listp '(8 . \"0\"))") is T)
check("(atom '(8 . \"0\")) is nil", ev("(atom '(8 . \"0\"))") is NIL)
check("(vl-consp '(8 . \"0\")) is T", ev("(vl-consp '(8 . \"0\"))") is T)
check("(type '(8 . \"0\")) is LIST", ev("(type '(8 . \"0\"))") == Sym("list"),
      ev("(type '(8 . \"0\"))"))
check("(listp (cdr '(8 . \"0\"))) is nil: the cdr is the atom",
      ev("(listp (cdr '(8 . \"0\")))") is NIL)

print("\n(a . nil) is the list (a), as the reader reads it")
# a cons whose cdr is nil IS a one-item list; the VM's reader made a
# dotted pair with a nil cdr that foreach would not walk, and a form
# store written with (key . nil) for the sheet's NA broke there
check("(length '(a . nil)) is 1", ev("(length '(a . nil))") == 1)
check("(listp (car '((a . nil)))) and (cdr (car '((a . nil)))) is nil",
      ev("(listp (car '((a . nil))))") is T
      and ev("(cdr (car '((a . nil))))") is NIL)
check("(equal '(a . nil) (cons 'a nil)) is T",
      ev("(equal '(a . nil) (cons 'a nil))") is T)
check("foreach walks '((a . nil) (b . 1)) item by item",
      ev("(setq n 0) (foreach p '((a . nil) (b . 1)) (setq n (1+ n))) n") == 2)

print("\n...on nil, a list and the atoms")
check("(listp nil) is T", ev("(listp nil)") is T)
check("(atom nil) is T", ev("(atom nil)") is T)
check("(vl-consp nil) is nil", ev("(vl-consp nil)") is NIL)
check("(listp '(1 2)) is T, (atom '(1 2)) nil, (vl-consp '(1 2)) T",
      (ev("(listp '(1 2))"), ev("(atom '(1 2))"), ev("(vl-consp '(1 2))"))
      == (T, NIL, T))
check("a string, a number and a symbol are atoms, not lists",
      [ev("(atom %s)" % x) for x in ('"a"', "1", "'a")] == [T, T, T]
      and [ev("(listp %s)" % x) for x in ('"a"', "1", "'a")] == [NIL] * 3)

print("\n...on a selection set")
vm = VM()
vm.loads("""(entmakex (list '(0 . "LINE") '(8 . "0")
                            '(10 0.0 0.0 0.0) '(11 1.0 0.0 0.0)))""")
vm.loads('(setq ss (ssget "_X"))')
check("(type ss) is PICKSET", ev("(type ss)", vm) == Sym("pickset"))
check("(listp ss) is nil: a set is not a list", ev("(listp ss)", vm) is NIL)
check("(atom ss) is T", ev("(atom ss)", vm) is T)
check("(vl-consp ss) is nil", ev("(vl-consp ss)", vm) is NIL)

print("\nforeach walks lists and refuses the rest")
check("over a list it walks every item",
      ev("(setq n 0) (foreach x '(1 2 3) (setq n (+ n x))) n") == 6)
check("over nil it runs no body", ev("(setq n 0) (foreach x nil (setq n 1)) n")
      == 0)
r = ev('(foreach c "abc" c)')
check("over a string it is refused, not walked a character at a time",
      isinstance(r, tuple) and "listp" in r[1], r)
r = ev("(foreach c 12 c)")
check("over a number it is refused", isinstance(r, tuple), r)
r = ev("(foreach e ss e)", vm)
check("over a selection set it is refused, not walked as enames",
      isinstance(r, tuple), r)
vm2 = VM()
r = ev("(setq seen nil) (foreach x '(a . 1) (setq seen x))", vm2)
check("over a dotted pair it visits the car, then is refused -- as a "
      "Lisp error the tool's *error* can see",
      isinstance(r, tuple) and vm2.loads("seen") == Sym("a"), r)

if failures:
    print("\n%d cons check(s) FAILED" % len(failures))
    sys.exit(1)
print("\nall cons checks passed")
