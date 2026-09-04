"""The palette's form wire, driven in the VM.

`ui/calofin_ui/calofin.lsp` used to do one thing -- say which commands
were loaded, so the palette could grey the rest.  It now carries the
form wire as well, and that move fixed a real bug rather than tidying
one up.

**The bug.**  The palette parsed the box itself, in VB, with
`Double.TryParse`, and accepted a plain decimal and nothing else.  Type

    6'-3"

-- a spelling the DCL forms read perfectly, and which the form's own
hint tells the drafter to use -- and the parse failed.  The palette then
sent `(key . nil)`.  That is not "ask me": `nil` is NA, the measurement
travels as *not taken*, and the routine never asks.  A wrong answer that
looks answered, which is exactly what phase 3 of `ui/UI-PLAN.md` went
after in the DCL forms.

So the reading moved to Lisp, where `distof` -- AutoCAD's own reader,
which knows every feet-and-inches spelling there is -- already lives.
The palette sends what was typed.

What is checked here:

1. The three states, plus the fourth that matters most: text nobody can
   read is NOT SENT, so the routine asks, and it is never confused with
   NA.
2. Literals pass through untouched.  A shape word run through a
   measurement reader would come back 'SKIP and the shape would stop
   travelling -- which is why the wire takes two lists and not one.
3. `calofin:unreadable` names exactly the keys the wire drops, because
   the palette's state line prints that list and a state line that
   disagrees with the wire is a lie.
4. The two helpers copied from `CALOFIN-LIB.lsp` still match it, body
   for body, modulo the namespace -- the same rule `mirror_shared.py
   --check` applies to every other copy in the tree.
5. `calofin:run` reports a missing entry point instead of erroring, and
   hands the routine one alist when it is there.

Run: python3 tests/test_palette_wire.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from lispvm import VM, Dot, NIL  # noqa: E402
from callib import PARTS_DIR, ROOT, read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


GLUE = ROOT / 'ui' / 'calofin_ui' / 'calofin.lsp'
LIB = PARTS_DIR / 'CALOFIN-LIB.lsp'


def fresh():
    vm = VM()
    vm.load(GLUE)
    return vm


print("== 1. the three states, and the fourth ==")

vm = fresh()
CASES = [
    ('84', 'a plain measurement', 84.0),
    ('  84  ', 'spaces around it', 84.0),
    ('84.5', 'a decimal', 84.5),
    ('NA', 'NA', None),
    ('na', 'na, in any case', None),
    ('  Na ', 'NA with spaces', None),
    ('', 'an empty box', 'SKIP'),
    ('   ', 'a box of spaces', 'SKIP'),
    ('rubbish', 'text nobody can read', 'SKIP'),
]
for text, what, want in CASES:
    vm.loads('(setq t:*a* (calofin:answer "%s"))' % text)
    got = vm.globals['t:*a*']
    if want == 'SKIP':
        ok = str(got).upper() == 'SKIP'
        shown = 'not sent'
    elif want is None:
        ok = got is NIL or got is None
        shown = 'nil (NA)'
    else:
        ok = isinstance(got, float) and abs(got - want) < 1e-9
        shown = repr(want)
    check("%-22s -> %s" % (what, shown), ok, repr(got))

# The distinction the whole feature rests on, stated as one assertion:
# unreadable and NA must NOT be the same answer.
vm.loads('(setq t:*bad* (calofin:answer "no such number"))')
vm.loads('(setq t:*na* (calofin:answer "NA"))')
check("unreadable is not NA - one asks, the other answers",
      str(vm.globals['t:*bad*']).upper() == 'SKIP'
      and vm.globals['t:*na*'] is NIL,
      "%r vs %r" % (vm.globals['t:*bad*'], vm.globals['t:*na*']))


print("== 2. literals travel, measures are read ==")

vm = fresh()
vm.loads('''(setq t:*f* (calofin:form
    '((shape . "Rectangle") (insq . "Insquare") (base 0.0 0.0))
    '((b . "84") (l . "NA") (h . "") (g . "rubbish"))))''')
def entry(p):
    """One alist entry as (key, value).

    Three shapes, all of them right: a Dot for (k . v); a ONE-ELEMENT
    LIST for (k . nil), because that is what a dotted pair with a nil
    cdr IS in Lisp and (cdr (assoc ...)) reads it as nil either way;
    and a longer list for a point, (base 0.0 0.0).
    """
    if isinstance(p, Dot):
        return (str(p.a), p.b)
    if len(p) == 1:
        return (str(p[0]), NIL)
    return (str(p[0]), [float(x) for x in p[1:]])


got = [entry(p) for p in vm.globals['t:*f*']]

keys = [k for k, _ in got]
check("the shape word travels as it was written",
      ('shape', 'Rectangle') in [(k, str(v)) for k, v in got], repr(got))
check("a keyword answer travels too",
      ('insq', 'Insquare') in [(k, str(v)) for k, v in got], repr(got))
check("a point travels as a list",
      ('base', [0.0, 0.0]) in got, repr(got))
check("a measurement is read", ('b', 84.0) in got, repr(got))
check("NA travels as nil - the one-element (l) IS (l . nil)",
      ('l', NIL) in got, repr(got))
check("an empty box does not travel at all", 'h' not in keys, repr(keys))
check("an unreadable box does not travel EITHER - the routine asks",
      'g' not in keys, repr(keys))
check("the literals keep their order", keys[:3] == ['shape', 'insq', 'base'],
      repr(keys))


print("== 3. the state line names exactly what the wire drops ==")

vm = fresh()
# tests/lispvm.py's distof takes any LEADING number, where AutoCAD's
# rejects trailing rubbish outright, so the cases below are ones both
# readers agree on: a measurement, and text with no number in it at all.
vm.loads('''(setq t:*u* (calofin:unreadable
    '((b . "84") (l . "") (h . "rubbish") (g . "NA") (e . "  ")
      (f . "no number here"))))''')
bad = [str(x) for x in vm.globals['t:*u*'] or []]
check("only the boxes that were typed AND cannot be read",
      bad == ['h', 'f'], repr(bad))
check("an empty box is not called unreadable", 'l' not in bad and
      'e' not in bad, repr(bad))
check("NA is not called unreadable", 'g' not in bad, repr(bad))

# the two must agree by construction, so try every case through both
vm.loads('''(setq t:*m* '((a . "84") (b . "NA") (c . "") (d . "zz")))
            (setq t:*sent* (calofin:form nil t:*m*))
            (setq t:*drop* (calofin:unreadable t:*m*))''')
sent = {entry(p)[0] for p in vm.globals['t:*sent*'] or []}
drop = {str(x) for x in vm.globals['t:*drop*'] or []}
check("nothing is both sent and reported dropped", not (sent & drop),
      repr(sorted(sent & drop)))
check("every typed key is sent or reported, never neither",
      sent | drop | {'c'} == {'a', 'b', 'c', 'd'},
      "sent %r dropped %r" % (sorted(sent), sorted(drop)))


print("== 4. the copied helpers still match the library ==")


def body(src, name):
    """One defun's text, from its open paren to the matching close."""
    i = src.index("(defun %s " % name)
    depth, j = 0, i
    while j < len(src):
        if src[j] == '(':
            depth += 1
        elif src[j] == ')':
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
        j += 1
    raise AssertionError(name)


GLUE_SRC = read(GLUE)
LIB_SRC = read(LIB)
for mine, theirs in (('calofin:trim', 'cal:trim'),
                     ('calofin:answer', 'cal:formanswer')):
    got = body(GLUE_SRC, mine).replace(mine, 'X')
    want = body(LIB_SRC, theirs).replace(theirs, 'X')
    # calofin:answer calls calofin:trim where the library calls cal:trim
    got = got.replace('calofin:trim', 'T')
    want = want.replace('cal:trim', 'T')
    check("%s is %s's body, character for character" % (mine, theirs),
          got == want,
          "\n    mine : %s\n    lib  : %s" % (got, want))


print("== 5. running a routine, present or absent ==")

vm = fresh()
vm.loads('(setq t:*out* nil)')
vm.loads('(defun pool:run-with-answers (form) (setq t:*out* form) t)')
vm.loads('''(calofin:run "pool:run-with-answers"
    '((shape . "Rectangle")) '((b . "84") (l . "zz")))''')
got = [(str(p.a), p.b) for p in vm.globals['t:*out*'] or []]
check("the routine is handed one alist, read",
      [(k, str(v) if isinstance(v, str) else v) for k, v in got]
      == [('shape', 'Rectangle'), ('b', 84.0)], repr(got))

vm2 = fresh()
ran, why = True, ''
try:
    vm2.loads('(calofin:run "spa:run-with-answers" nil \'((w . "84")))')
except Exception as exc:                                   # noqa: BLE001
    ran, why = False, repr(exc)
check("a routine that is not loaded is reported, not an error", ran, why)

# and the palette's own probe still works beside the new wire
vm3 = fresh()
vm3.loads('(defun C:POOL () (princ))')
vm3.loads('(setq t:*have* (calofin:loaded))')
have = [str(x) for x in vm3.globals['t:*have*'] or []]
check("calofin:loaded still reports what is defined", have == ['POOL'],
      repr(have))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL PALETTE WIRE CHECKS PASSED")
