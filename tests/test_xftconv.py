"""Runtime tests for XFTCONV: scale the imported survey x12 and swap
each Leica X marker for an ab_pt block carrying the number read off the
name text beside it.  First coverage -- test_shared.py only ever
load-checked the file.

Zero Python stubs: the tblsearch extension makes xft:locked real, and
the bounding boxes ride the VM's own vla-getboundingbox.  Geometry is
NOT rescaled by the VM's command logger, so the x12 is asserted off
vm.commands, exactly as the tool issues it.

Script shape: [None, [ents]] -- the leading None answers the pickfirst
probe (ssget "_I"), the list answers the interactive highlight.  Enter
there falls back to an (ssget "_X") sweep of the current tab, which
consumes no script slot -- the fixtures carry (410 . "Model") so that
sweep has something to find once CTAB is seeded.

Run: python3 tests/test_xftconv.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_xftconv.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
LSP = os.path.join(HERE, '..', 'lisp', 'xftconv', 'xftconv.lsp')
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


LAYERS = '''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "LEICA_POINT") '(70 . 0) '(62 . 3)
                 '(6 . "Continuous")))
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "LEICA_POINT_NAME") '(70 . 0) '(62 . 2)
                 '(6 . "Continuous")))'''

LOCKED_MARKER_LAYER = '''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "LEICA_POINT") '(70 . 4) '(62 . 3)
                 '(6 . "Continuous")))'''


def marker(cx, cy):
    """The X: two LINEs on LEICA_POINT crossing at (cx, cy) -- both
    midpoints identical, which is how the tool groups them."""
    return f'''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 '(8 . "LEICA_POINT") '(410 . "Model") '(100 . "AcDbLine")
                 '(10 {cx - 1.0} {cy - 0.5} 0.0) '(11 {cx + 1.0} {cy + 0.5} 0.0)))
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 '(8 . "LEICA_POINT") '(410 . "Model") '(100 . "AcDbLine")
                 '(10 {cx - 1.0} {cy + 0.5} 0.0) '(11 {cx + 1.0} {cy - 0.5} 0.0)))'''


def name_text(x, y, s, h=1.0):
    return f'''
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 '(8 . "LEICA_POINT_NAME") '(410 . "Model")
                 '(100 . "AcDbText")
                 '(10 {x} {y} 0.0) '(40 . {h}) '(1 . "{s}")))'''


def made(vm, src):
    before = len(vm.entities)
    vm.loads(src)
    return vm.entities[before:]


def newvm(fixtures=()):
    vm = VM()
    vm.load(LSP)
    for f in fixtures:
        vm.loads(f)
    return vm


def inserts(vm):
    """[(x, y, attrib value)] for every live ab_pt INSERT."""
    out = []
    ents = [e for e in vm.entities if e not in vm.deleted]
    for i, e in enumerate(ents):
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'INSERT' and grp(d, 2) == 'ab_pt':
            ins = grp(d, 10)
            att = vm.entdata.get(ents[i + 1], [])
            out.append((ins[0], ins[1], grp(att, 1)))
    return out


# ----------------------------------------------------------------------
# statics: pure ASCII, banner, releases/ twin
# ----------------------------------------------------------------------
print("statics")

SRC = open(LSP, encoding="ascii").read()   # also asserts pure ASCII

m = re.search(r'\*xft-version\*\s+"v(\d+)\.(\d+)"', SRC)
check("version banner present", m is not None)
if m:
    rev = f"{m.group(1)}{m.group(2)}"
    twins = [n for n in os.listdir(RELEASES)
             if re.match(rf"xftconv_\d{{6}}_REV{rev}\.lsp$", n)]
    check(f"releases/ twin at REV{rev} exists", len(twins) == 1, repr(twins))
    if len(twins) == 1:
        twin = open(os.path.join(RELEASES, twins[0]),
                    encoding="ascii").read()
        check("releases/ twin is identical", twin == SRC)

# ----------------------------------------------------------------------
# 1. the text helpers, straight through
# ----------------------------------------------------------------------
print("the name-to-number helpers")

vm = newvm()
check('xft:number strips the letter prefix',
      vm.loads('(xft:number "P22")') == "22")
check('a bare number passes through',
      vm.loads('(xft:number "22")') == "22")
check('no digits at all comes back whole',
      vm.loads('(xft:number "STA")') == "STA")
check('MTEXT codes are stripped first',
      vm.loads('(xft:number "\\\\A1;P7")') == "7")
check('xft:plain unwraps braces and closed codes',
      vm.loads('(xft:plain "{\\\\fArial;P9}")') == "P9")
check('a paragraph break reads as a space',
      vm.loads('(xft:plain "P8\\\\P2")') == "P8 2")

# ----------------------------------------------------------------------
# 2. the happy path: two markers, one named, one blank
# ----------------------------------------------------------------------
print("the swap")

vm = newvm([LAYERS])
ents = []
ents += made(vm, marker(0.0, 0.5))
ents += made(vm, name_text(0.2, 1.0, "P9"))       # same column: rank 0
ents += made(vm, name_text(0.51, 0.5, "P8"))      # nearer, off-column
ents += made(vm, marker(100.0, 100.0))            # no name in reach
vm.sysvars['OSMODE'] = 4133
vm.sysvars['CMDECHO'] = 1
vm.run('c:XFTCONV', [None, ents])

got = sorted(inserts(vm))
check("two ab_pt blocks landed on the marker centres",
      [(x, y) for x, y, _v in got] == [(0.0, 0.5), (100.0, 100.0)],
      repr(got))
check("the same-column name wins over the nearer off-column one",
      got[0][2] == "9", repr(got))
check("a marker with no name in reach gets a blank number",
      got[1][2] == "", repr(got))

txt = ''.join(vm.printed)
check("the report counts all three outcomes",
      '2 point(s) replaced with "ab_pt".' in txt and
      '1 had no name text nearby' in txt and
      '1 leftover text object(s) erased.' in txt, txt[-400:])

check("the block definition was created on the way",
      'created it' in txt and 'ab_pt' in vm.tables['BLOCK'])
check("the POINTS layer was created on the way",
      'POINTS' in vm.tables['LAYER'])

scale = [c for c in vm.commands if c and c[0] == '_.SCALE']
check("one x12 SCALE about the middle of the selection",
      len(scale) == 1 and scale[0][-1] == 12.0 and
      scale[0][-2] == [50.0, 50.25, 0.0], repr(scale))
check("the run is one undo group",
      [c for c in vm.commands if c and c[0] == '_.UNDO'] ==
      [['_.UNDO', '_Begin'], ['_.UNDO', '_End']])

check("every marker line and every text is gone",
      all(e in vm.deleted for e in ents), repr(vm.deleted))
check("system variables restored",
      vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1)

# ----------------------------------------------------------------------
# 3. Enter = everything in this space (the "_X" sweep)
# ----------------------------------------------------------------------
print("Enter sweeps the current tab")

vm = newvm([LAYERS])
made(vm, marker(0.0, 0.5))
made(vm, name_text(0.2, 1.0, "P4"))
vm.sysvars['CTAB'] = 'Model'
vm.run('c:XFTCONV', [None, None])      # Enter at the highlight
check("the sweep found and swapped the survey",
      inserts(vm) == [(0.0, 0.5, "4")], repr(inserts(vm)))
check("the sweep consumed no script slot beyond the two Enters",
      sum(1 for p, _ in vm.prompts if p.startswith('ssget')) == 2,
      repr(vm.prompts))

# ----------------------------------------------------------------------
# 4. pickfirst: a selection made before the command was typed
# ----------------------------------------------------------------------
print("pickfirst")

vm = newvm([LAYERS])
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P5"))
vm.pickfirst = ['<ss>'] + ents
vm.run('c:XFTCONV', [])                # nothing to answer at all
check("the probe took the pre-typed highlight",
      inserts(vm) == [(0.0, 0.5, "5")], repr(inserts(vm)))
check("no selection prompt ever fired",
      not any(p.startswith('ssget') for p, _ in vm.prompts),
      repr(vm.prompts))

# ----------------------------------------------------------------------
# 5. a locked marker layer stops the run before it touches anything
#    (this is the regression guard for tblsearch carrying group 70)
# ----------------------------------------------------------------------
print("locked layers refuse the swap")

NAME_LAYER = '''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "LEICA_POINT_NAME") '(70 . 0) '(62 . 2)
                 '(6 . "Continuous")))'''

vm = newvm([LOCKED_MARKER_LAYER, NAME_LAYER])
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P6"))
vm.run('c:XFTCONV', [None, ents])
check("the locked layer is named and nothing runs",
      'Unlock LEICA_POINT' in ''.join(vm.printed) and
      not [c for c in vm.commands if c] and
      not inserts(vm) and not vm.deleted,
      ''.join(vm.printed)[-200:])

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all XFTCONV checks passed")
