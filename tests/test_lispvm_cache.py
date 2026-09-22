"""The VM's parse cache hands out COPIES, never the tree it keeps.

tests/lispvm.py parses a large source once per process and serves every
later load of the same text from that tree.  What makes that safe is
that no two callers ever share a list: running code holds parse-tree
lists as its own data -- (quote ...) returns one, ssdel edits a list in
place, entmake keeps the (10 x y z) lists it was handed -- so a shared
tree would let one test case's run edit the program the next case loads.
The dotted pair matters as much as the list: its car can itself be a
list, so a Dot shared between copies would carry the alias across.

These pins are what keep the cache an optimisation and not a change of
meaning:

  * a hit returns a tree EQUAL to a fresh parse and sharing no list or
    Dot with it, or with the tree a previous caller was handed;
  * mutating a returned tree -- a list, a Dot's car, the Dot itself --
    changes nothing a later parse of the same text sees;
  * every literal is still its own object, within one parse and across
    two loads of one source, so (eq 1.5 1.5) is nil exactly as it is in
    AutoLISP;
  * short text is not kept at all.

Run: python3 tests/test_lispvm_cache.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, Dot, Sym, NIL, parse_all  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def nodes(tree, kinds=(list, Dot)):
    """Every list and Dot in TREE, depth first."""
    out, todo = [], [tree]
    while todo:
        x = todo.pop()
        if type(x) in kinds:
            out.append(x)
        if type(x) is list:
            todo.extend(x)
        elif type(x) is Dot:
            todo.extend((x.a, x.b))
    return out


# A source over the size gate: a defun handing back a quoted list with a
# dotted pair whose car is a list, a float literal twice, and enough
# filler defuns to clear _PARSE_CACHE_MIN.
FILLER = "".join(
    "(defun cache-filler-%d (a b / c) (setq c (+ a b 1.25)) (list c \"s%d\"))\n"
    % (i, i) for i in range(80))
SRC = ("(defun cache-data () '((1 2) ((3 4) . 5) (6 . 7.5)))\n"
       "(defun cache-eq () (eq 1.5 1.5))\n" + FILLER)
check("the test source is over the size gate",
      len(SRC) >= lispvm._PARSE_CACHE_MIN,
      f"{len(SRC)} < {lispvm._PARSE_CACHE_MIN}")

lispvm._PARSED.clear()
first = parse_all(SRC)
check("a large source is cached on its first parse",
      SRC in lispvm._PARSED)
kept = lispvm._PARSED[SRC]
second = parse_all(SRC)
uncached = lispvm._parse_all(SRC)

check("a hit equals a fresh parse", second == uncached)
check("the first parse equals a fresh parse too", first == uncached)
check("the cached tree itself is never handed out",
      first is not kept and second is not kept
      and all(a is not b for a, b in zip(first, kept))
      and all(a is not b for a, b in zip(second, kept)))

ids_kept = {id(x) for x in nodes(kept)}
for label, tree in (("first", first), ("second", second)):
    shared = [x for x in nodes(tree) if id(x) in ids_kept]
    check(f"the {label} copy shares no list or Dot with the cache",
          not shared, f"{len(shared)} shared, e.g. {repr(shared[-1])[:60]}"
          if shared else '')
shared = {id(x) for x in nodes(first)} & {id(x) for x in nodes(second)}
check("two copies share no list or Dot with each other", not shared)

dots = [x for x in nodes(second) if type(x) is Dot]
check("the Dots were copied, not only the lists",
      len(dots) == 2 and all(id(d) not in ids_kept for d in dots))

# Mutate everything the first copy holds: its lists, its Dots' cars and
# cdrs.  A later parse of the same text must not see any of it.
for x in nodes(first):
    if type(x) is Dot:
        if type(x.a) is list:
            x.a.append('mutated')
        x.b = 'mutated'
    else:
        x.append('mutated')
third = parse_all(SRC)
check("mutating a returned tree does not reach a later parse",
      third == uncached)
check("...nor the cached tree", kept == uncached)

# The same, through the VM: one VM edits the list its defun returns,
# and a second VM loading the same text gets the original back.
a = VM()
a.loads(SRC)
data = a.loads("(cache-data)")
data[0].append(99)
data[1].a.append(99)
b = VM()
b.loads(SRC)
check("a VM that edits a quoted list leaves the next VM's copy alone",
      b.loads("(cache-data)") == [[1, 2], Dot([3, 4], 5), Dot(6, 7.5)],
      repr(b.loads("(cache-data)")))
check("(eq 1.5 1.5) is still nil inside one cached source",
      b.loads("(cache-eq)") is NIL)

# Across two loads of one cached source into ONE VM, a literal is two
# objects, exactly as two fresh parses make it: eq between them is nil
# for a string, a float and an int past CPython's small-int cache.
ACROSS = ('(setq *cur* "abc" *curf* 1.5 *curi* 123456789)'
          '(setq *same* (list (eq *prev* *cur*) (eq *prevf* *curf*)'
          ' (eq *previ* *curi*)))'
          '(setq *prev* *cur* *prevf* *curf* *previ* *curi*)'
          '(defun cache-across-pad () nil)\n' + FILLER)
c = VM()
c.loads(ACROSS)
c.loads(ACROSS)
check("a literal read by two loads of one source is two objects",
      c.loads("*same*") == [NIL, NIL, NIL], repr(c.loads("*same*")))

# Short text is parsed every time and never kept.
before = len(lispvm._PARSED)
small = "(setq cache-small '(1 . 2))"
p1, p2 = parse_all(small), parse_all(small)
check("short text is not cached", len(lispvm._PARSED) == before
      and small not in lispvm._PARSED)
check("short text still parses the same", p1 == p2 == [
    [Sym('setq'), Sym('cache-small'), [Sym('quote'), Dot(1, 2)]]])

# A malformed large source raises as it always did and is not kept.
bad = SRC + "(defun cache-broken ("
try:
    parse_all(bad)
    raised = False
except (IndexError, lispvm.LispError):
    raised = True
check("a malformed large source still raises", raised)
check("...and is not cached", bad not in lispvm._PARSED)

if FAILS:
    print("test_lispvm_cache: %d FAILURE(S): %s"
          % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_lispvm_cache: all checks passed")
