"""The VM's and/or answer the way AutoLISP's do: T or nil, never the
value that decided them.

That is not Common Lisp, and the VM once behaved like Common Lisp --
(or x "Yes") handed back x.  Every test passed on code that could never
have run in AutoCAD: DIMSTAMP v3.6 parsed an answer through
(or (list ...) ...), got T, and died "bad argument type: consp T" on
the first text of every run; the three step routines, SPA, POOLSIDE and
PERPMARK read their keyword defaults as (or (canon knob) "Yes") and
strcat'd the T.  So these pins are what keep the suite honest about a
whole class of bug, not a detail of the interpreter.

Run: python3 tests/test_lispvm_logic.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, T, NIL  # noqa: E402


def check(src, want):
    got = VM().loads(src)
    assert got == want, f"{src} -> {got!r}, AutoLISP gives {want!r}"
    print(f"ok  {src:40s} -> {'T' if got is T else got!r}")


check('(or nil (list 1 2))', T)
check('(or "Yes")', T)
check('(or nil nil)', NIL)
check('(or)', NIL)
check('(and 1 (list 1 2))', T)
check('(and 1 "x")', T)
check('(and 1 nil)', NIL)
check('(and)', T)
# ...and the spellings that DO hand back a value, which is what a
# default or a lookup has to be written as
check('(cond ((list 1 2)) ("Yes"))', [1, 2])
check('(cond (nil) ("Yes"))', "Yes")
check('(if 1 (list 1 2))', [1, 2])
print("all lispvm logic tests passed")
