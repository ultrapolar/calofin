"""Runtime tests for WCALST: straighten a curved constant-width ladder
band and draw the developed (unrolled) band below it, darts cut where
the far edge carries excess.  First coverage -- the largest previously
untested tool in the tree (the command alone is ~780 lines).

The oracle band is 120 degrees of arc walked in 15-degree chords:
the straightened side at r=200 (8 chords totalling 417.68), the far
side at r=176 (shorter, so the excess shows up as darts), 9 radial
rungs of exactly 24 (the band width is the MEDIAN rung).  Every number
asserted below was worked from that geometry and confirmed against the
real run before being pinned.

Script slots, in order: the pickfirst probe (None), the band ssget,
the entsel side pick as [ent, [x, y, 0.0]] -- the point must be a
LIST, wc:d2 cars it -- then maxfeat getint <20>, tile height getreal
<none>, and the stair-sections ssget (Enter = none).

Run: python3 tests/test_wcalst.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_wcalst.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
LSP = os.path.join(HERE, '..', 'lisp', 'wcalst', 'wcalst.lsp')
RELEASES = os.path.join(HERE, '..', 'releases')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


def layer(n, c):
    return f'''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "{n}") '(70 . 0) '(62 . {c})
                 '(6 . "Continuous")))'''


def line(p, q, lay):
    return f'''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "{lay}")
                 '(100 . "AcDbLine")
                 '(10 {p[0]!r} {p[1]!r} 0.0) '(11 {q[0]!r} {q[1]!r} 0.0)))'''


def band(vm):
    """The oracle band; returns (all entities, the side-pick answer)."""
    ang = [math.radians(30 + 15 * i) for i in range(9)]
    near = [(200.0 * math.cos(a), 200.0 * math.sin(a)) for a in ang]
    far = [(176.0 * math.cos(a), 176.0 * math.sin(a)) for a in ang]
    ents = []

    def mk(src):
        before = len(vm.entities)
        vm.loads(src)
        ents.extend(vm.entities[before:])

    for i in range(8):
        mk(line(near[i], near[i + 1], 'NEAR'))
    for i in range(8):
        mk(line(far[i], far[i + 1], 'FAR'))
    for i in range(9):
        mk(line(near[i], far[i], 'RUNG'))
    mid = [(near[0][0] + near[1][0]) / 2.0,
           (near[0][1] + near[1][1]) / 2.0, 0.0]
    return ents, [ents[0], mid]


def newvm():
    vm = VM()
    vm.load(LSP)
    for L in (layer('NEAR', 1), layer('FAR', 4), layer('RUNG', 2)):
        vm.loads(L)
    vm.sysvars['CLAYER'] = 'NEAR'
    return vm


def label_ys(vm):
    """y of the two variant labels, top first."""
    ys = []
    for e in vm.entities:
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'TEXT' and grp(d, 1) in ('TARGET <1%',
                                                 'MINIMUM DARTS+INSERTS'):
            ys.append(grp(d, 10)[1])
    return ys


# ----------------------------------------------------------------------
# statics: pure ASCII, banner, releases/ twin
# ----------------------------------------------------------------------
print("statics")

SRC = open(LSP, encoding="ascii").read()   # also asserts pure ASCII

m = re.search(r'\*wcalst-version\*\s+"v(\d+)\.(\d+)"', SRC)
check("version banner present", m is not None)
if m:
    rev = f"{m.group(1)}{m.group(2)}"
    twins = [n for n in os.listdir(RELEASES)
             if re.match(rf"wcalst_\d{{6}}_REV{rev}\.lsp$", n)]
    check(f"releases/ twin at REV{rev} exists", len(twins) == 1, repr(twins))
    if len(twins) == 1:
        twin = open(os.path.join(RELEASES, twins[0]),
                    encoding="ascii").read()
        check("releases/ twin is identical", twin == SRC)

# ----------------------------------------------------------------------
# 1. the oracle band, Enter defaults all the way
# ----------------------------------------------------------------------
print("the developed band")

vm = newvm()
ents, pick = band(vm)
vm.run('c:WCALST', [None, ents, pick, None, None, None])
txt = ''.join(vm.printed)

check("developed length is the chord walk of the straightened side",
      'WCALST: developed length 417.68, band width 24.00' in txt,
      txt[-500:])
check("the target variant cuts 8 darts and no inserts",
      'target <1%: 8 dart(s), 0 insert(s) (max 20)' in txt, txt[-500:])
check("the minimum-cuts variant gets there with 7",
      'minimum cuts: 7 dart(s), 0 insert(s)' in txt, txt[-500:])
check("the bottom line's before/after/delta are reported",
      'top line 417.68, bottom before 367.56, bottom after 411.42,'
      ' delta 43.86' in txt, txt[-500:])
check("AIR-B and DIMENSION were created",
      'AIR-B' in vm.tables['LAYER'] and 'DIMENSION' in vm.tables['LAYER'])
ys = label_ys(vm)
check("the two variants are drawn stacked 5 widths apart",
      len(ys) == 2 and abs((ys[0] - ys[1]) - 5 * 24.0) < 1e-6, repr(ys))
check("the band itself is untouched",
      not vm.deleted and all(e in vm.entities for e in ents))
check("the run is one undo group",
      [c for c in vm.commands if c] ==
      [['_.UNDO', '_Begin'], ['_.UNDO', '_End']], repr(vm.commands))
check("CLAYER restored", vm.sysvars['CLAYER'] == 'NEAR')

# ----------------------------------------------------------------------
# 2. the feature cap is honoured
# ----------------------------------------------------------------------
print("the dart cap")

vm = newvm()
ents, pick = band(vm)
vm.run('c:WCALST', [None, ents, pick, 3, None, None])
txt = ''.join(vm.printed)
mm = re.search(r'target <1%: (\d+) dart\(s\), (\d+) insert\(s\) \(max 3\)',
               txt)
check("at most 3 cuts when asked for 3",
      mm is not None and int(mm.group(1)) + int(mm.group(2)) <= 3,
      txt[-400:])

# ----------------------------------------------------------------------
# 3. the Back chain: entsel -> band, maxfeat -> side, tileh -> maxfeat
# ----------------------------------------------------------------------
print("stepping back")

vm = newvm()
ents, pick = band(vm)
vm.run('c:WCALST', [None, ents, "Back",       # side pick -> re-select
                    ents, pick, "Back",       # maxfeat  -> re-pick side
                    pick, None, "Back",       # tileh    -> re-ask maxfeat
                    None, None, None])
asked = [p for p, _ in vm.prompts]
# the band ask princ's its text, so the prompt itself records as a
# bare 'ssget'; the third bare one is the stair-sections ask at the end
check("Back at the side pick re-opens the band selection",
      ''.join(vm.printed).count('Select the band of lines') == 2 and
      sum(p == 'ssget' for p in asked) == 3,
      repr(asked))
check("Back at the cap re-opens the side pick",
      sum('Click the long side' in p for p in asked) == 3, repr(asked))
check("Back at the tile height re-opens the cap",
      sum('Maximum darts + inserts' in p for p in asked) == 3, repr(asked))
check("and the walked-back run still finishes on the oracle",
      'target <1%: 8 dart(s), 0 insert(s)' in ''.join(vm.printed))

# ----------------------------------------------------------------------
# 4. guards: too few segments, a pick outside the selection, Enter
# ----------------------------------------------------------------------
print("the guards")

vm = newvm()
ents, pick = band(vm)
vm.run('c:WCALST', [None, ents[:3], ents, pick, None, None, None])
check("a too-small band asks again",
      'Too few segments to form a band' in ''.join(vm.printed))

vm = newvm()
ents, pick = band(vm)
vm.loads(line((900.0, 900.0), (950.0, 900.0), 'NEAR'))
stray = vm.entities[-1]
vm.run('c:WCALST', [None, ents, [stray, [925.0, 900.0, 0.0]],
                    pick, None, None, None])
check("a side pick outside the selection re-asks",
      'not in the selection' in ''.join(vm.printed))

vm = newvm()
try:
    vm.run('c:WCALST', [None, None])
except LispError:
    pass                                   # (exit) ends the command
check("Enter at the band selection stops the command",
      'Nothing selected.' in ''.join(vm.printed))

# ----------------------------------------------------------------------
# 5. pickfirst: a band highlighted before the command was typed
# ----------------------------------------------------------------------
print("pickfirst")

vm = newvm()
ents, pick = band(vm)
vm.pickfirst = ['<ss>'] + ents
vm.run('c:WCALST', [pick, None, None, None])
# the one bare 'ssget' left is the stair-sections ask; the band ask
# (its princ and its ssget) must never appear
check("the probe took the band; the selection was never asked",
      'Select the band of lines' not in ''.join(vm.printed) and
      sum(p == 'ssget' for p, _ in vm.prompts) == 1 and
      'target <1%: 8 dart(s)' in ''.join(vm.printed),
      repr(vm.prompts))

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all WCALST checks passed")
