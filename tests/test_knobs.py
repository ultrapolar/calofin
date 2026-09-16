"""LAZTUNE's knob catalog, against the blocks it is transcribed from.

``lzp:*knobs*`` in LAZPANEL.lsp is written by tools/gen_knobs.py from
every tool's tunables block -- name, the literal as the block spells
it, and the comment beside it -- so a drafter can set a value of their
own for any knob and come back to "Alec's choice".  A generator only
moves the risk: from a table nobody typed to a transcription nobody
read.  So this holds the table on disk to the tree three ways:

1. It is what the generator would write now (the same contract the
   palette's catalog keeps), and every literal in it READS in the VM as
   the data LAZTUNE's own safe parser would accept -- a literal that
   does not read is a knob nobody could ever set back to Alec's choice.
2. A second, independent parse agrees: every knob tests/test_tunables.py
   counts for its own files (its single-line ``(setq ns:*x* ...)`` rule)
   is in the catalog, under the same file, with the same literal.
3. Every knob name is unique across the whole tree.  The override is
   keyed by the name alone -- CalofinKnob-<name> -- so two tools
   sharing one would silently share one drafter's answer.

Run: python3 tests/test_knobs.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from lispvm import VM  # noqa: E402
from callib import ROOT, read  # noqa: E402
import gen_knobs  # noqa: E402
import knobs  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


PANEL = ROOT / 'lisp' / 'lazpanel' / 'LAZPANEL.lsp'

print("== 1. the table on disk is the tree, and every literal reads ==")

problems = gen_knobs.check()
check("gen_knobs --check is happy", not problems, repr(problems))

vm = VM()
vm.load(PANEL)
table = vm.globals.get('lzp:*knobs*') or []
cat = knobs.catalog()
check("%d tools in the table, as in the tree" % len(table),
      len(table) == len(cat), "%d vs %d" % (len(table), len(cat)))
n_table = sum(len(t) - 2 for t in table)
n_cat = sum(len(ks) for _, ks in cat)
check("%d knobs in the table, as in the tree" % n_table,
      n_table == n_cat, "%d vs %d" % (n_table, n_cat))

unreadable = []
for t in table:
    for e in t[2:]:
        vm.loads('(setq t:*v* (lzp:knob-safe (lzp:knob-read %s)))'
                 % gen_knobs.lisp_str(str(e[1])))
        v = vm.globals.get('t:*v*')
        if str(v) == 'LZP-BAD':
            # a form the block computes (a derived knob) is allowed to
            # need its tool; it still has to READ
            vm.loads('(setq t:*r* (lzp:knob-read %s))'
                     % gen_knobs.lisp_str(str(e[1])))
            if str(vm.globals.get('t:*r*')) == 'LZP-BAD':
                unreadable.append((str(t[0]), str(e[0]), str(e[1])[:40]))
check("every literal reads back in the VM", not unreadable,
      repr(unreadable[:5]))

forms = [(str(t[0]), str(e[0])) for t in table for e in t[2:]
         if str(e[1]).startswith('(') and not re.match(r'\((list|cons)\b', str(e[1]))]
print("   %d knobs ship as a computed form (a derived value); those are "
      "evaluated at run time, not read" % len(forms))

print("== 2. a second parse agrees ==")

src = read(ROOT / 'tests' / 'test_tunables.py')
rows = re.findall(r"\('([^']+)', ROOT / 'lisp' / '([^']+)' / "
                  r"'([^']+\.(?:lsp|LSP))', '([a-z0-9]+)'", src)
bytable = {}
for t in table:
    bytable[str(t[1])] = {str(e[0]): str(e[1]) for e in t[2:]}
missing, differing = [], []
for tool, d, f, ns in rows:
    rel = 'lisp/%s/%s' % (d, f)
    block, _ = knobs.block_of(read(ROOT / rel))
    simple = re.findall(r'^\(setq (' + ns + r':\*[a-z0-9-]+\*)\s+(.*?)\)[ \t]*(?:;.*)?$',
                        block or '', re.M)
    have = bytable.get(rel, {})
    for name, lit in simple:
        if name not in have:
            missing.append((rel, name))
        elif lit.count('(') != lit.count(')'):
            continue        # the line rule cut a wrapped list short
        elif ' '.join(lit.split()) != have[name]:
            differing.append((rel, name, lit, have[name]))
check("every knob test_tunables.py counts is in the table (%d files)"
      % len(rows), not missing, repr(missing[:5]))
check("...with the literal the block spells", not differing,
      repr(differing[:3]))

print("== 3. one name, one knob ==")

names = [str(e[0]) for t in table for e in t[2:]]
dupes = sorted({n for n in names if names.count(n) > 1})
check("no knob name repeats across the tree", not dupes, repr(dupes[:10]))
labels = [str(t[0]) for t in table]
check("no tool label repeats", len(labels) == len(set(labels)), repr(labels))

print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL KNOB CATALOG CHECKS PASSED (%d knobs over %d tools)"
      % (n_table, len(table)))
