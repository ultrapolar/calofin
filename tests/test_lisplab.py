#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for LISPLAB.lsp -- the two-lesson teaching tool.

LISPLAB is a file people are meant to COPY OUT OF, so its six sorting
routines have to be right, not just runnable: every one of them is
driven here against Python's own sorted() on lists that are empty,
single, already ordered, reversed and full of duplicates, with three
different comparators.  A sort that silently drops a duplicate, or
comes out unstable, is the exact bug the lesson warns about -- it must
not be in the lesson itself.

The database half is checked by taking the whole tour: the demo draws a
sample and then reads it back with entnext / assoc / ssget / tblsearch,
so a wrong group code or a nil reaching (distance ...) dies here rather
than at someone's command line.

Usage:  python3 tests/test_lisplab.py
"""

import functools
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import (VM, LispError, Ent, Dot, Sym, BUILTINS, NIL,  # noqa: E402
                    truthy, parse_all)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
#: always the lisp/ path -- VM.load remaps it to shared/parts/ (and
#: loads the library first) when CALOFIN_LISP_ROOT says so, which is
#: how the same tests check both tiers.
LSP = os.path.join(REPO, 'lisp', 'lisplab', 'LISPLAB.lsp')

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


# ---- builtins the shared VM does not carry yet ------------------------
# entmakex / tblobjname: the canonical ensure-layer of STANDARDS.md
# section 5 needs both (same additions test_oasis.py makes).
# vl-sort / vl-sort-i are the VM's own now -- this test used to patch in
# faithful versions, and those bodies moved into lispvm.py, so lesson 2
# teaches against exactly what every other test runs on.

def _alist_dict(alist):
    d = {}
    for p in alist:
        if isinstance(p, Dot):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


def _entmakex(vm, a):
    alist = a[0]
    d = _alist_dict(alist)
    if d.get(0) in ('LAYER', 'LTYPE'):
        vm.tables[d[0]].add(d[2])
        rec = Ent()
        vm.entdata[rec] = list(alist)
        vm.layer_records[d[2].upper()] = rec
        return rec
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = list(alist)
    return e


def _tblobjname(vm, a):
    return vm.layer_records.get(a[1].upper(), NIL)


def _dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else g[1:]
    return NIL


_ssget_scripted = BUILTINS[Sym('ssget')]


def _ssget(vm, a):
    """(ssget "_X" filter) asks the user nothing -- it is a database
    query, not a selection -- so answering it off the input script (as
    the shared VM does for every ssget) would be wrong.  Scan the
    entities and apply the DXF filter for "_X"; hand every interactive
    mode back to the stock builtin."""
    if not any(isinstance(x, str) and '_X' in x.upper() for x in a):
        return _ssget_scripted(vm, a)
    pairs = []
    for x in a:
        if isinstance(x, list) and x and isinstance(x[0], (Dot, list)):
            for g in x:
                if isinstance(g, Dot):
                    pairs.append((g.a, g.b))
                elif isinstance(g, list) and len(g) >= 2:
                    pairs.append((g[0], g[1]))
            break
    ents = [e for e in vm.entities
            if e not in vm.deleted
            and all(_dxf(vm, e, c) == v for c, v in pairs)]
    return ['<ss>'] + ents if ents else NIL


BUILTINS[Sym('entmakex')] = _entmakex
BUILTINS[Sym('tblobjname')] = _tblobjname
BUILTINS[Sym('ssget')] = _ssget


def new_vm():
    vm = VM()
    vm.layer_records = {}
    vm.load(LSP)
    return vm


def call(vm, name, *args):
    return vm.call_value(Sym(name), list(args))


def lam(src):
    """A (lambda ...) form to hand a LISPLAB routine as its comparator."""
    return parse_all(src)[0]


def plain(v):
    """[] for the VM's nil, so an empty result compares equal to []."""
    return [] if v is NIL else list(v)


# =====================================================================
print('LISPLAB -- the file loads and reports its version')
vm = new_vm()
check('version banner is v-dotted', vm.globals[Sym('*lisplab-version*')]
      .startswith('v'))
try:
    vm.run('c:LISPLABVER', [])
except LispError as e:
    raise AssertionError(f'[LISPLABVER] {e}') from None
check('LISPLABVER ran', True)

# =====================================================================
print('LISPLAB -- every sort agrees with Python, on every shape of list')
SORTS = ['lab:bubble', 'lab:selection', 'lab:insertion', 'lab:msort',
         'lab:qsort']
CASES = {
    'the demo list':      [6.0, 3.0, 9.0, 3.0, 12.0, 5.0, 8.0],
    'empty':              NIL,
    'one item':           [7.0],
    'two, wrong way':     [2.0, 1.0],
    'already sorted':     [1.0, 2.0, 3.0, 4.0, 5.0],
    'exactly reversed':   [5.0, 4.0, 3.0, 2.0, 1.0],
    'all the same':       [4.0, 4.0, 4.0, 4.0],
    'negatives and zero': [3.0, -1.0, 0.0, -7.5, 2.0],
}
vm = new_vm()
for fn in SORTS:
    bad = []
    for label, lst in CASES.items():
        want = sorted(plain(lst))
        got = plain(call(vm, fn, plain(lst) or NIL, Sym('<')))
        if got != want:
            bad.append(f'{label}: {got} != {want}')
    check(f'{fn} ascending, {len(CASES)} lists', not bad)
    if bad:
        print('       ' + '\n       '.join(bad))

for fn in SORTS:
    lst = [6.0, 3.0, 9.0, 3.0, 12.0, 5.0, 8.0]
    got = plain(call(vm, fn, list(lst), Sym('>')))
    check(f'{fn} takes a different comparator ( > )',
          got == sorted(lst, reverse=True))

WORDS = ['pool', 'spa', 'deck', 'coping', 'deck']
for fn in SORTS:
    got = plain(call(vm, fn, list(WORDS), Sym('<')))
    check(f'{fn} sorts strings too', got == sorted(WORDS))

# =====================================================================
print('LISPLAB -- the duplicate the lesson is built around')
lst = [6.0, 3.0, 9.0, 3.0, 12.0, 5.0, 8.0]
for fn in SORTS:
    got = plain(call(vm, fn, list(lst), Sym('<')))
    check(f'{fn} keeps both 3s ({len(lst)} in, {len(got)} out)',
          len(got) == len(lst) and got.count(3.0) == 2)
dropped = plain(BUILTINS[Sym('vl-sort')](vm, [list(lst), Sym('<')]))
check('vl-sort really does drop one -- the trap the lesson claims',
      len(dropped) == len(lst) - 1 and dropped.count(3.0) == 1)
keep = plain(BUILTINS[Sym('vl-sort-i')](vm, [list(lst), Sym('<')]))
check('vl-sort-i keeps all seven, as indexes',
      keep == [1, 3, 5, 0, 6, 2, 4])

# =====================================================================
print('LISPLAB -- merge sort is stable, which lesson 2 relies on')
# (radius layer x y) records; sorting by LAYER alone must leave the
# radii inside each layer in the order they went in.
RECS = [[6.0, 'B', 0.0, 0.0], [3.0, 'A', 1.0, 0.0], [9.0, 'B', 2.0, 0.0],
        [3.0, 'A', 3.0, 0.0], [12.0, 'B', 4.0, 0.0], [5.0, 'A', 5.0, 0.0],
        [8.0, 'B', 6.0, 0.0]]
bylay = plain(call(vm, 'lab:msort', [list(r) for r in RECS],
                   lam('(lambda (p q) (< (cadr p) (cadr q)))')))
check('msort by layer keeps the within-layer order',
      [r[0] for r in bylay] == [3.0, 3.0, 5.0, 6.0, 9.0, 12.0, 8.0])

# sort by the LAST key first, then the first -- the trick that only
# works with a stable sort, and the one the demo shows
two_step = plain(call(vm, 'lab:msort',
                      plain(call(vm, 'lab:msort', [list(r) for r in RECS],
                                 Sym('lab:by-radius'))),
                      lam('(lambda (p q) (< (cadr p) (cadr q)))')))
one_pass = plain(call(vm, 'lab:msort', [list(r) for r in RECS],
                      Sym('lab:by-layer-then-radius')))
check('two stable passes == one two-key comparator', two_step == one_pass)
check('and both really are layer-then-radius',
      [(r[1], r[0]) for r in one_pass]
      == [('A', 3.0), ('A', 3.0), ('A', 5.0),
          ('B', 6.0), ('B', 8.0), ('B', 9.0), ('B', 12.0)])

# =====================================================================
print('LISPLAB -- the pieces the algorithms are built from')
check('lab:insert puts an item into a sorted list',
      plain(call(vm, 'lab:insert', 4.0, [1.0, 3.0, 7.0], Sym('<')))
      == [1.0, 3.0, 4.0, 7.0])
check('lab:insert goes AFTER an equal item (that is the stability)',
      plain(call(vm, 'lab:insert', ['x', 2], [['a', 2], ['b', 9]],
                 lam('(lambda (p q) (< (cadr p) (cadr q)))')))
      == [['a', 2], ['x', 2], ['b', 9]])
check('lab:merge merges two sorted lists',
      plain(call(vm, 'lab:merge', [1.0, 4.0, 9.0], [2.0, 3.0], Sym('<')))
      == [1.0, 2.0, 3.0, 4.0, 9.0])
check('lab:merge takes from the LEFT on a tie',
      plain(call(vm, 'lab:merge', [['L', 1]], [['R', 1]],
                 lam('(lambda (p q) (< (cadr p) (cadr q)))')))
      == [['L', 1], ['R', 1]])
halves = call(vm, 'lab:halve', [1.0, 2.0, 3.0, 4.0, 5.0])
check('lab:halve splits front/back, odd item to the back',
      [plain(halves[0]), plain(halves[1])] == [[1.0, 2.0],
                                               [3.0, 4.0, 5.0]])
check('lab:halve survives an empty list',
      [plain(x) for x in call(vm, 'lab:halve', NIL)] == [[], []])
check('lab:select-min finds the smallest',
      call(vm, 'lab:select-min', [6.0, 3.0, 9.0], Sym('<')) == 3.0)
check('lab:remove1 drops the FIRST match only, not every match',
      plain(call(vm, 'lab:remove1', 3.0, [6.0, 3.0, 9.0, 3.0]))
      == [6.0, 9.0, 3.0])
check('lab:bubble-pass moves one item one place',
      plain(call(vm, 'lab:bubble-pass', [3.0, 1.0, 2.0], Sym('<')))
      == [1.0, 2.0, 3.0])

# =====================================================================
print('LISPLAB -- sorting by a computed key')
byrad = plain(call(vm, 'lab:sort-by', [list(r) for r in RECS],
                   Sym('lab:rad'), Sym('<')))
check('lab:sort-by orders by the key and gives the ITEMS back',
      [r[0] for r in byrad] == [3.0, 3.0, 5.0, 6.0, 8.0, 9.0, 12.0])
check('lab:sort-by keeps the whole record, not just the key',
      all(len(r) == 4 for r in byrad))
check('lab:sort-by works on bare atoms as well as lists',
      plain(call(vm, 'lab:sort-by', ['ccc', 'a', 'bb'],
                 lam('(lambda (s) (strlen s))'), Sym('<')))
      == ['a', 'bb', 'ccc'])

# =====================================================================
print('LISPLAB -- the whole tour: both lessons, notes and demos')


class Tour(VM):
    """A VM that answers by PROMPT rather than by position.

    Every other test in this repo scripts answers positionally, which
    is right when a routine asks six measurements in a fixed order.  A
    tutorial asks two questions and then pauses a dozen times, and
    counting those pauses would make the test break every time a
    lesson gains a paragraph -- so here the pauses take Enter, the
    keyword questions are matched on their wording, and an unexpected
    question is an error rather than a silently mis-consumed answer."""

    def __init__(self, kw, point=None, size=None):
        super().__init__()
        self.layer_records = {}
        self.kw = kw
        self.point = point
        self.size = size
        self.asked = []

    def pop_script(self, prompt, kind):
        self.asked.append((kind, prompt))
        if kind == 'getstring':
            return ''                       # a pause
        if kind == 'getpoint':
            return self.point
        if kind == 'getdist':
            return self.size
        if kind == 'getkword':
            for wording, answer in self.kw.items():
                if wording in prompt:
                    return answer
            raise LispError(f'unscripted question: {prompt!r}', self)
        raise LispError(f'unscripted {kind}: {prompt!r}', self)


def drive(lesson, mode, point=None, size=None, ending='Keep'):
    vm = Tour({'Which lesson': lesson,
               'Checks prints': mode,
               'Keep the demo drawing': ending},
              point=point, size=size)
    vm.load(LSP)
    try:
        vm.run('c:LISPLAB', [])
    except LispError as e:
        raise AssertionError(f'[{lesson}/{mode}] {e}') from None
    return vm


def circles(vm, lay):
    return [e for e in vm.entities
            if e not in vm.deleted
            and _dxf(vm, e, 0) == 'CIRCLE' and _dxf(vm, e, 8) == lay]


def drawn(vm):
    return len(circles(vm, 'LISPLAB-A')) + len(circles(vm, 'LISPLAB-B'))


def rows(vm):
    """The demo's circles grouped into the rows they were drawn in, top
    row first, each row read left to right: [[(radius, layer), ...]]."""
    by_y = {}
    for e in circles(vm, 'LISPLAB-A') + circles(vm, 'LISPLAB-B'):
        pt = _dxf(vm, e, 10)
        by_y.setdefault(round(pt[1], 6), []).append(
            (pt[0], _dxf(vm, e, 40), _dxf(vm, e, 8)[-1]))
    return [[c[1:] for c in sorted(v)]
            for _y, v in sorted(by_y.items(), reverse=True)]


#: the sample, at the 5.0 size unit: (6 3 9 3 12 5 8) x 5, on layers
#: A B A A B B A -- see lab:*sample*
SAMPLE = [(30.0, 'A'), (15.0, 'B'), (45.0, 'A'), (15.0, 'A'),
          (60.0, 'B'), (25.0, 'B'), (40.0, 'A')]


def asked_for(vm, kind):
    return [pr for k, pr in vm.asked if k == kind]


BEFORE = dict(VM().sysvars)

vm = drive('Both', 'Both', point=[0.0, 0.0, 0.0], size=5.0)
check('the full tour ran to the end', True)
check('sample + two sorted rows drawn (7 circles x 3)', drawn(vm) == 21)
check('all three demo layers were created',
      {'LISPLAB-A', 'LISPLAB-B', 'LISPLAB-NOTES'} <= vm.tables['LAYER'])
check('every circle got a label on the notes layer',
      len([e for e in vm.entities
           if _dxf(vm, e, 0) == 'TEXT'
           and _dxf(vm, e, 8) == 'LISPLAB-NOTES']) >= 21)
check('every sysvar is back where it started', vm.sysvars == BEFORE)
check('the run is one undo group',
      [c[:2] for c in vm.commands].count(['_.UNDO', '_Begin']) == 1
      and [c[:2] for c in vm.commands].count(['_.UNDO', '_End']) == 1)
check('row 1 is the sample, in the order lab:*sample* lists it',
      rows(vm)[0] == SAMPLE)
check('row 2 is the same seven circles sorted by radius',
      [c[0] for c in rows(vm)[1]] == sorted(c[0] for c in SAMPLE))
check('row 2 is STABLE: the two equal radii kept their drawn order',
      rows(vm)[1] == sorted(SAMPLE, key=lambda c: c[0]))
check('row 3 is sorted by layer, then by radius inside each layer',
      rows(vm)[2] == [(15.0, 'A'), (30.0, 'A'), (40.0, 'A'), (45.0, 'A'),
                      (15.0, 'B'), (25.0, 'B'), (60.0, 'B')])
check('no circle was lost or invented on the way through the sorts',
      sorted(rows(vm)[1]) == sorted(rows(vm)[2]) == sorted(SAMPLE))
check('the demo really did pause its way through',
      len(asked_for(vm, 'getstring')) > 8)

# =====================================================================
print('LISPLAB -- one lesson at a time, and one half at a time')
vm = drive('Database', 'Both', point=[0.0, 0.0, 0.0], size=5.0)
check('Database alone draws the sample and no sorted rows',
      drawn(vm) == 7 and rows(vm) == [SAMPLE])
check('Database alone leaves the sysvars alone', vm.sysvars == BEFORE)

vm = drive('Sorting', 'Both')
check('Sorting alone draws nothing at all', not vm.entities)
check('Sorting alone asks for no insertion point',
      not asked_for(vm, 'getpoint'))
check('Sorting alone leaves the sysvars alone', vm.sysvars == BEFORE)

vm = drive('Both', 'Checks')
check('Checks alone draws nothing and asks for no point',
      not vm.entities and not asked_for(vm, 'getpoint'))
check('Checks alone never offers to erase a drawing',
      not [pr for pr in asked_for(vm, 'getkword') if 'Keep' in pr])

vm = drive('Both', 'Demo', point=[0.0, 0.0, 0.0], size=5.0)
check('Demo alone still draws all three rows', drawn(vm) == 21)
check('Demo alone asks the point and size once each',
      len(asked_for(vm, 'getpoint')) == 1
      and len(asked_for(vm, 'getdist')) == 1)

# =====================================================================
print('LISPLAB -- Erase takes the demo back out again')
vm = drive('Both', 'Both', point=[0.0, 0.0, 0.0], size=5.0, ending='Erase')
check('nothing of the demo is left in the drawing',
      not [e for e in vm.entities
           if e not in vm.deleted
           and _dxf(vm, e, 8) in ('LISPLAB-A', 'LISPLAB-B',
                                  'LISPLAB-NOTES')])
check('erasing still puts every sysvar back', vm.sysvars == BEFORE)

# =====================================================================
print('LISPLAB -- Enter takes the default at every question')
vm = drive(None, None, point=None, size=None, ending=None)
check('Enter/Enter is Both/Both -- all three rows drawn', drawn(vm) == 21)
check('Enter at the point prompt is 0,0, so the demo sits above it',
      min(_dxf(vm, e, 10)[0] for e in circles(vm, 'LISPLAB-A')
          + circles(vm, 'LISPLAB-B')) > 0)
check('Enter at the size prompt takes the 5.0 default',
      rows(vm)[0] == SAMPLE)
check('Enter at the last question KEEPS the drawing', drawn(vm) == 21)
check('every sysvar is back where it started', vm.sysvars == BEFORE)

# =====================================================================
print('LISPLAB -- a frozen demo layer is thawed, not drawn onto blind')
vm = Tour({'Which lesson': 'Database', 'Checks prints': 'Demo',
           'Keep the demo drawing': 'Keep'}, point=[0.0, 0.0, 0.0],
          size=5.0)
vm.load(LSP)
vm.tables['LAYER'].add('LISPLAB-A')
rec = Ent()
vm.entdata[rec] = [Dot(0, 'LAYER'), Dot(2, 'LISPLAB-A'), Dot(70, 1),
                   Dot(62, -1)]           # frozen AND switched off
vm.layer_records['LISPLAB-A'] = rec
try:
    vm.run('c:LISPLAB', [])
except LispError as e:
    raise AssertionError(f'[frozen layer] {e}') from None
check('the frozen, off layer was thawed and switched back on',
      _dxf(vm, rec, 70) == 0 and _dxf(vm, rec, 62) == 1)
check('and the sample was drawn onto it anyway', drawn(vm) == 7)

# =====================================================================
print('LISPLAB -- no local hides a function the file calls')
src = open(VM()._remap_root(LSP)).read()
shadow = []
for form in parse_all(src):
    if not (isinstance(form, list) and form and form[0] == Sym('defun')):
        continue
    args = [str(x) for x in (form[2] or [])]
    if '/' in args:
        args = args[args.index('/') + 1:]
    for a in args:
        if Sym(a.lower()) in BUILTINS:
            shadow.append(f'{form[1]} declares {a}')
check('no builtin name is used as a local', not shadow)
if shadow:
    print('       ' + '\n       '.join(shadow))

# =====================================================================
if failures:
    print(f'\n{len(failures)} LISPLAB test(s) FAILED:')
    for f in failures:
        print('  - ' + f)
    sys.exit(1)
print('\nall LISPLAB tests passed')
