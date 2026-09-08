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
4. The four helpers copied from `CALOFIN-LIB.lsp` still match it, body
   for body, modulo the namespace -- the same rule `mirror_shared.py
   --check` applies to every other copy in the tree.
5. `calofin:unreadable-str` answers the same question over one packed
   string, which is how the palette asks it: marshalling an alist of
   dotted pairs through a ResultBuffer is the fiddly half of the
   .NET/Lisp boundary, and "key=typed;key=typed" is a format this tree
   already uses for the recall store.
6. `calofin:run` reports a missing entry point instead of erroring, and
   hands the routine one alist when it is there.
7. Contingencies -- the things the palette never sends and the wire has
   to take anyway: a value that is already a number, a packed string
   somebody edited by hand, an entry point named by symbol, and a
   routine that dies, whose error must NOT be swallowed here because
   the routine's own handler is the one that should report it.

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
                     ('calofin:answer', 'cal:formanswer'),
                     ('calofin:kvsplit', 'cal:kvsplit'),
                     ('calofin:kvunpack', 'cal:kvunpack')):
    got = body(GLUE_SRC, mine).replace(mine, 'X')
    want = body(LIB_SRC, theirs).replace(theirs, 'X')
    # calofin:answer calls calofin:trim where the library calls cal:trim
    for a, b in (('calofin:trim', 'T'), ('calofin:kvsplit', 'S')):
        got = got.replace(a, b)
    for a, b in (('cal:trim', 'T'), ('cal:kvsplit', 'S')):
        want = want.replace(a, b)
    check("%s is %s's body, character for character" % (mine, theirs),
          got == want,
          "\n    mine : %s\n    lib  : %s" % (got, want))


print("== 5. the state line asks the wire, over one string ==")

# The palette cannot work out what will be dropped any more -- that is
# the point of moving the reader here -- so it asks.  It asks with one
# STRING because marshalling an alist of dotted pairs through a
# ResultBuffer is the fiddly half of the .NET/Lisp boundary, and
# "key=typed;key=typed" is a format this tree already uses.
vm = fresh()
vm.loads('(setq t:*s* (calofin:unreadable-str "b=84;l=;h=rubbish;g=NA"))')
check("the packed sheet gives back the keys that will not read",
      str(vm.globals['t:*s*']) == 'h', repr(vm.globals['t:*s*']))

vm.loads('(setq t:*s2* (calofin:unreadable-str "b=84;g=NA"))')
check("a sheet with nothing wrong gives an empty string",
      str(vm.globals['t:*s2*']) == '', repr(vm.globals['t:*s2*']))

vm.loads('(setq t:*s3* (calofin:unreadable-str ""))')
check("so does an empty sheet", str(vm.globals['t:*s3*']) == '',
      repr(vm.globals['t:*s3*']))

vm.loads('(setq t:*s4* (calofin:unreadable-str "h=rubbish;f=no number"))')
check("more than one is joined the way it arrived",
      str(vm.globals['t:*s4*']) == 'h;f', repr(vm.globals['t:*s4*']))

# and the two answers agree, because one calls the other
vm.loads('(setq t:*pk* "a=84;b=NA;c=;d=zz")')
vm.loads('(setq t:*viaalist* (calofin:unreadable (calofin:kvunpack t:*pk*)))')
vm.loads('(setq t:*viastr* (calofin:unreadable-str t:*pk*))')
check("the string form and the alist form say the same thing",
      ";".join(str(x) for x in vm.globals['t:*viaalist*'] or [])
      == str(vm.globals['t:*viastr*']),
      "%r vs %r" % (vm.globals['t:*viaalist*'], vm.globals['t:*viastr*']))


print("== 6. running a routine, present or absent ==")

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


print("== 7. contingencies: what the wire does with what it should never get ==")

# The palette never sends any of these -- MeasurePair always quotes, the
# dropdowns send words, the count is the one integer and it is a
# literal -- but the wire is an ENTRY POINT, and an entry point takes
# what it is given.  Each case here is one that made a reader die, or
# would have.
vm = fresh()
vm.loads('(setq t:*n* (calofin:form nil \'((b . 84) (l . "72"))))')
got = [entry(p) for p in vm.globals['t:*n*']]
check("a measure that is already a number travels as itself",
      any(k == 'b' and float(v) == 84.0 for k, v in got), repr(got))
check("beside the text that is read", any(k == 'l' and float(v) == 72.0
                                          for k, v in got), repr(got))

vm.loads('(setq t:*u2* (calofin:unreadable '
         '\'((b . 84) (c . nil) (d . "zz") (e . "  ") (f . 3.5))))')
bad = [str(x) for x in vm.globals['t:*u2*'] or []]
check("a number is never unreadable - only text can be", bad == ['d'],
      repr(bad))
check("nor is nil, which is an empty box, not a bad one", 'c' not in bad)

vm.loads('(setq t:*e1* (calofin:form nil nil))')
vm.loads('(setq t:*e2* (calofin:unreadable nil))')
vm.loads('(setq t:*e3* (calofin:unreadable-str nil))')
check("nothing in gives nothing out, on all three",
      not vm.globals['t:*e1*'] and not vm.globals['t:*e2*']
      and str(vm.globals['t:*e3*'] or '') == '',
      repr((vm.globals['t:*e1*'], vm.globals['t:*e2*'],
            vm.globals['t:*e3*'])))

# a packed string the palette could never write, because RecallStore
# .Pack refuses a value carrying a separator -- but a registry value is
# a registry value, and someone will edit one by hand
for packed, want in (("a==b", ""), (";;", ""), ("=x", ""),
                     ("noequals", ""), ("a=", ""), ("a=zz;;b=84", "a"),
                     (";a=zz;", "a")):
    vm.loads('(setq t:*m* (calofin:unreadable-str "%s"))' % packed)
    check("packed %-12r -> %r" % (packed, want),
          str(vm.globals['t:*m*'] or '') == want, repr(vm.globals['t:*m*']))

# the entry point may be named either way
vm = fresh()
vm.loads('(setq t:*out* nil)')
vm.loads('(defun pool:run-with-answers (form) (setq t:*out* form) t)')
vm.loads("(calofin:run 'pool:run-with-answers nil '((b . \"84\")))")
check("a routine named by SYMBOL is found too",
      [entry(p) for p in vm.globals['t:*out*'] or []] == [('b', 84.0)],
      repr(vm.globals['t:*out*']))

# and one the session has not loaded is REPORTED, by either spelling.
# Naming it in the message is where that used to break: the message was
# built with strcat, which takes strings and nothing else, so the
# symbol spelling died on the line that exists to say the routine is
# missing.  (It reads as fine in a VM where Sym subclasses str, which
# is why tests/lispvm.py's strcat rejects a symbol on purpose.)
for named, how in (('"nope:run"', 'string'), ("'nope:run", 'symbol')):
    vm = fresh()
    vm.printed = []
    vm.loads('(calofin:run %s nil \'((b . "84")))' % named)
    said = "".join(vm.printed)
    check("an unloaded routine named by %-6s reports, and names itself"
          % how, 'nope:run' in said and 'not loaded' in said, repr(said))

# A ROUTINE THAT DIES IS NOT CAUGHT HERE.  That is LAZFORM's design and
# it is the right one: POOL installs its own *error*, and a POOL that
# fails must report as POOL.  A wire that swallowed the error would
# leave the drawing half-done with nothing on the command line to say
# so.  So the error must reach the caller, which in the VM means
# reaching Python.
vm = fresh()
vm.loads('(setq t:*ran* nil)')
vm.loads('(defun pool:run-with-answers (form) (setq t:*ran* t) (strlen 5))')
died = False
try:
    vm.loads('(calofin:run "pool:run-with-answers" nil \'((b . "84")))')
except Exception:                                          # noqa: BLE001
    died = True
check("a routine that errors is NOT swallowed by the wire",
      died and vm.globals['t:*ran*'], "died=%r ran=%r"
      % (died, vm.globals['t:*ran*']))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL PALETTE WIRE CHECKS PASSED")
