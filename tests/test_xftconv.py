"""Runtime tests for XFTCONV: scale the imported survey x12 and swap
each Leica X marker for an ab_pt block carrying the number read off the
name text beside it.  First coverage -- test_shared.py only ever
load-checked the file.

Zero Python stubs: the tblsearch extension makes xft:locked real, and
the bounding boxes ride the VM's own vla-getboundingbox.  Geometry is
NOT rescaled by the VM's command logger, so the x12 is asserted off
vm.commands, exactly as the tool issues it.

CALOFIN_LISP_ROOT=shared runs the same script over the grouped twin in
shared/parts/ (with the library loaded first) -- the docstring said so
from the start, but the path was hard-wired to lisp/, so the twin was
only ever load-checked.  The releases/ twin is compared against the
lisp/ source at either tier, since that is what it is a twin of.

The contingencies at the bottom are the ones a survey brings in: undo
switched off in the drawing, an import already in inches, a plain POINT
where the X should be, MTEXT and justified names, each settings switch
in its non-default position, a frozen POINTS, a missing text style, an
error mid-run and both flavours in one highlight.

After those comes the record XFTCONV writes and XFTRECONV reads back --
the undo that survives a save and reopen, where U does not.

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
from lispvm import VM, Dot, LispError  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
LISP_SRC = os.path.join(HERE, '..', 'lisp', 'xftconv', 'xftconv.lsp')
LSP = (os.path.join(HERE, '..', 'shared', 'parts', 'xftconv.lsp')
       if ROOT == 'shared' else LISP_SRC)
LIB = os.path.join(HERE, '..', 'shared', 'parts', 'CALOFIN-LIB.lsp')
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


DOT_LAYERS = '''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "POOL_POINTS") '(70 . 0) '(62 . 140)
                 '(6 . "Continuous")))
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "BREAK_LINES") '(70 . 0) '(62 . 12)
                 '(6 . "Continuous")))
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "CROSS_MEASUREMENTS") '(70 . 0) '(62 . 9)
                 '(6 . "Continuous")))
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "TEXT") '(70 . 0) '(62 . 4)
                 '(6 . "Continuous")))'''


def circle(layer, cx, cy, r=0.125):
    """The trace's point marker: a 1.5" circle on one of its three
    point layers."""
    return f'''
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 '(8 . "{layer}") '(410 . "Model") '(100 . "AcDbCircle")
                 '(10 {cx} {cy} 0.0) '(40 . {r})))'''


def dot_name(x, y, s, h=0.3333333333333333):
    """The name text, insertion point exactly ON the circle centre and
    unjustified -- which is how the sample export writes it."""
    return f'''
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 '(8 . "TEXT") '(410 . "Model") '(100 . "AcDbText")
                 '(10 {x} {y} 0.0) '(40 . {h}) '(1 . "{s}")))'''


def caption(x, y, s, h=0.4166666666666666):
    """A break-line or diagonal caption: same layer as the names, but
    middle-centre justified onto the line rather than onto a point."""
    return f'''
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 '(8 . "TEXT") '(410 . "Model") '(100 . "AcDbText")
                 '(10 {x - 2.0} {y - 0.2} 0.0) '(11 {x} {y} 0.0)
                 '(40 . {h}) '(72 . 1) '(73 . 2) '(1 . "{s}")))'''


# The sample export, verbatim: a 40' x 20' rectangle in feet.  Each
# corner is drawn TWICE -- once on POOL_POINTS, once on
# CROSS_MEASUREMENTS where a diagonal ends -- and only the POOL_POINTS
# copy carries the name.
X0, X1 = 1080.483901141753, 1120.608901141753
YB, YT = 347.3755944107107, 367.458927744044
XS, XD = 1108.108901141753, 1094.40056780842

SAMPLE_DOTS = [
    ("POOL_POINTS", X0, YB, "C1"),
    ("POOL_POINTS", X0, YT, "C2"),
    ("POOL_POINTS", X1, YT, "C3"),
    ("POOL_POINTS", X1, YB, "C4"),
    ("CROSS_MEASUREMENTS", X0, YB, None),
    ("CROSS_MEASUREMENTS", X1, YT, None),
    ("CROSS_MEASUREMENTS", X0, YT, None),
    ("CROSS_MEASUREMENTS", X1, YB, None),
    ("BREAK_LINES", XS, YT, "S1"),
    ("BREAK_LINES", XS, YB, "S2"),
    ("BREAK_LINES", XD, YT, "D1"),
    ("BREAK_LINES", XD, YB, "D2"),
]

# Captions ride the same TEXT layer.  "Deep End" and "Shallow End" sit
# in their own break line's column, exactly where the same-column rule
# would reward them -- only the reach keeps them out.
SAMPLE_CAPTIONS = [
    (XD, 360.7644832995996, "Deep End"),
    (XS, 354.0700388551552, "Shallow End"),
    (1110.577651141753, 362.4380944107107, "Diagonal 1"),
    (1090.515151141753, 362.4380944107107, "Diagonal 2"),
]


def made(vm, src):
    before = len(vm.entities)
    vm.loads(src)
    return vm.entities[before:]


def newvm(fixtures=()):
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
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

SRC = open(LISP_SRC, encoding="ascii").read()   # also asserts pure ASCII
open(LSP, encoding="ascii").read()              # ...and the tier under test

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
check("the error mode pushed for the handler is popped on the way out",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0,
      repr((vm.error_mode_depth, vm.error_mode_underflow)))

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
check("...and that quiet exit pops the error mode too",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0,
      repr((vm.error_mode_depth, vm.error_mode_underflow)))

# ----------------------------------------------------------------------
# 6. the quiet "nothing to work on" exit, and an Esc at the highlight
# ----------------------------------------------------------------------
print("nothing to work on, and Esc, both leave the session as they found it")

vm = newvm([LAYERS])
vm.sysvars['CTAB'] = 'Model'
vm.run('c:XFTCONV', [None, None])      # Enter, and the sweep finds nothing
check("nothing to work on: said so, mode popped, settings untouched",
      'Nothing to work on' in ''.join(vm.printed)
      and vm.error_mode_depth == 0 and vm.error_mode_underflow == 0
      and vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1)

vm = newvm([LAYERS])
vm.handle_errors = True


def esc(vm):
    raise LispError('Function cancelled', vm)


vm.run('c:XFTCONV', [None, esc])
check("Esc at the highlight went through the handler, once",
      vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
check("...which popped the mode and restored the settings",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0
      and vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1,
      repr((vm.error_mode_depth, vm.sysvars)))
check("a cancel prints no error line", not any(
    'XFTCONV error' in s for s in vm.printed))

# ----------------------------------------------------------------------
# 7. the site-trace flavour: circles for markers, the name text sitting
#    ON the centre, and captions on the same layer that must NOT be
#    read as point numbers.  Geometry is lifted straight off the sample
#    export (a 40' x 20' rectangular pool, in feet).
# ----------------------------------------------------------------------
print("the site-trace flavour")

vm = newvm([DOT_LAYERS])
ents = []
for lay, x, y, nm in SAMPLE_DOTS:
    ents += made(vm, circle(lay, x, y))
    if nm:
        ents += made(vm, dot_name(x, y, nm))
caps = []
for x, y, s in SAMPLE_CAPTIONS:
    caps += made(vm, caption(x, y, s))
vm.run('c:XFTCONV', [None, ents + caps])

got = sorted(inserts(vm), key=lambda t: (t[2], t[0]))
check("eight blocks -- one per location, not one per circle",
      len(got) == 8, repr(got))
check("every point kept its whole label, family letter and all",
      [v for _x, _y, v in got] ==
      ["C1", "C2", "C3", "C4", "D1", "D2", "S1", "S2"], repr(got))
check("a corner's POOL_POINTS and CROSS_MEASUREMENTS circles made ONE block",
      len([t for t in got if t[2].startswith("C")]) == 4 and
      sorted(t[:2] for t in got if t[2].startswith("C")) ==
      [(1080.483901141753, 347.3755944107107),
       (1080.483901141753, 367.458927744044),
       (1120.608901141753, 347.3755944107107),
       (1120.608901141753, 367.458927744044)], repr(got))
check("no marker went in blank -- every circle found its name",
      "had no name text nearby" not in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])
check("every circle and every name text is gone",
      all(e in vm.deleted for e in ents), repr(len(vm.deleted)))

# The captions are the reason the reach is a fraction of a text height.
# "Deep End" sits in D1's and D2's own column -- the rank rule alone
# would hand it to one of them.
caption_txt = [e for e in caps if e in vm.deleted]
check("the break-line and diagonal captions were left alone",
      caption_txt == [], repr(caption_txt))
check("...so no point is called 'Deep End'",
      not [t for t in got if not re.match(r'^[CSD]\d$', t[2])], repr(got))

txt = ''.join(vm.printed)
check("the report says the circle markers came off a site trace",
      '8 point(s) replaced with "ab_pt".' in txt and
      '8 of those were circle markers off a site trace' in txt, txt[-400:])
check("nothing was purged -- the trace's text is not all point names",
      'leftover text object(s) erased' not in txt, txt[-400:])

# ----------------------------------------------------------------------
# 8. a locked trace layer is named the way a locked Leica one is
# ----------------------------------------------------------------------
print("a locked trace layer stops the run and names itself")

LOCKED_BREAK = DOT_LAYERS.replace("'(2 . \"BREAK_LINES\") '(70 . 0)",
                                  "'(2 . \"BREAK_LINES\") '(70 . 4)")
check("the fixture really locked BREAK_LINES", LOCKED_BREAK != DOT_LAYERS)

vm = newvm([LOCKED_BREAK])
ents = made(vm, circle("BREAK_LINES", 1.0, 2.0)) + made(vm, dot_name(1.0, 2.0, "S1"))
vm.run('c:XFTCONV', [None, ents])
check("the message names the locked layer, and nothing ran",
      'Unlock BREAK_LINES' in ''.join(vm.printed) and
      not [c for c in vm.commands if c] and
      not inserts(vm) and not vm.deleted,
      ''.join(vm.printed)[-200:])

# a layer that is locked but carries nothing of ours is not in the way
vm = newvm([LOCKED_BREAK])
ents = made(vm, circle("POOL_POINTS", 1.0, 2.0)) + made(vm, dot_name(1.0, 2.0, "C1"))
vm.run('c:XFTCONV', [None, ents])
check("a locked layer with none of the selection on it does not stop it",
      inserts(vm) == [(1.0, 2.0, "C1")], repr(inserts(vm)))

# ----------------------------------------------------------------------
# 9. undo switched off in the drawing: no group is opened, so none may
#    be closed.  The success path used to close one unconditionally and
#    died on it -- through the handler, after the swap had already run.
# ----------------------------------------------------------------------
print("undo off: the run neither opens nor closes a group")

vm = newvm([LAYERS])
vm.handle_errors = True
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P3"))
vm.sysvars['UNDOCTL'] = 0
vm.run('c:XFTCONV', [None, ents])
check("the swap still happened", inserts(vm) == [(0.0, 0.5, "3")],
      repr(inserts(vm)))
check("no _.UNDO command at all was issued",
      not [c for c in vm.commands if c and c[0] == '_.UNDO'],
      repr(vm.commands))
check("and the run ended clean rather than through the handler",
      vm.handled_errors == [] and vm.error_mode_depth == 0
      and 'XFTCONV error' not in ''.join(vm.printed),
      repr(vm.handled_errors))

# ----------------------------------------------------------------------
# 10. *xft-scale* 1.0: an import already in inches is not scaled
# ----------------------------------------------------------------------
print("*xft-scale* 1.0 skips the SCALE step")

vm = newvm([LAYERS])
vm.loads('(setq *xft-scale* 1.0)')
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P3"))
vm.run('c:XFTCONV', [None, ents])
check("no SCALE was issued",
      not [c for c in vm.commands if c and c[0] == '_.SCALE'],
      repr(vm.commands))
check("but the swap went ahead", inserts(vm) == [(0.0, 0.5, "3")],
      repr(inserts(vm)))

# ----------------------------------------------------------------------
# 11. some exports drop a plain POINT where the X should be
# ----------------------------------------------------------------------
print("a POINT on the marker layer is a marker")

POINT_MARKER = """
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 '(8 . "LEICA_POINT") '(410 . "Model") '(100 . "AcDbPoint")
                 '(10 5.0 5.0 0.0)))"""

vm = newvm([LAYERS])
ents = made(vm, POINT_MARKER) + made(vm, name_text(5.1, 5.5, "P11"))
vm.run('c:XFTCONV', [None, ents])
check("the POINT became a block carrying the number",
      inserts(vm) == [(5.0, 5.0, "11")], repr(inserts(vm)))
check("and the POINT itself is gone", all(e in vm.deleted for e in ents))

# ----------------------------------------------------------------------
# 12. an MTEXT name: formatting codes come off, and it sits at its
#     insertion point (group 11 is a direction on MTEXT, not a point)
# ----------------------------------------------------------------------
print("an MTEXT name is read through its formatting codes")


def mtext_name(x, y, s, h=1.0):
    return f"""
  (entmake (list '(0 . "MTEXT") '(100 . "AcDbEntity")
                 '(8 . "LEICA_POINT_NAME") '(410 . "Model")
                 '(100 . "AcDbMText")
                 '(10 {x} {y} 0.0) '(40 . {h}) '(11 1.0 0.0 0.0)
                 '(1 . "{s}")))"""


vm = newvm([LAYERS])
ents = made(vm, marker(0.0, 0.5))
ents += made(vm, mtext_name(0.2, 1.0, "\\\\A1;{\\\\fArial;P7}"))
vm.run('c:XFTCONV', [None, ents])
check("the number came out from under the codes",
      inserts(vm) == [(0.0, 0.5, "7")], repr(inserts(vm)))

# ----------------------------------------------------------------------
# 13. a justified TEXT really sits at its alignment point (group 11):
#     the insertion point is put 40 units away, out of any reach
# ----------------------------------------------------------------------
print("a justified name is located by its alignment point")


def justified_name(ax, ay, s, h=1.0):
    return f"""
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 '(8 . "LEICA_POINT_NAME") '(410 . "Model") '(100 . "AcDbText")
                 '(10 {ax - 40.0} {ay} 0.0) '(11 {ax} {ay} 0.0)
                 '(40 . {h}) '(72 . 1) '(1 . "{s}")))"""


vm = newvm([LAYERS])
ents = made(vm, marker(0.0, 0.5)) + made(vm, justified_name(0.0, 1.0, "P12"))
vm.run('c:XFTCONV', [None, ents])
check("the name was found through group 11, not group 10",
      inserts(vm) == [(0.0, 0.5, "12")], repr(inserts(vm)))

# ----------------------------------------------------------------------
# 14. *xft-purge-text* nil keeps what the swap did not use
# ----------------------------------------------------------------------
print("*xft-purge-text* nil keeps the leftover text")

vm = newvm([LAYERS])
vm.loads('(setq *xft-purge-text* nil)')
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
stray = made(vm, name_text(50.0, 50.0, "P77"))
vm.run('c:XFTCONV', [None, ents + stray])
check("the name a point used is erased in the swap regardless",
      all(e in vm.deleted for e in ents), repr(vm.deleted))
check("the stray text survives", not any(e in vm.deleted for e in stray))
check("and the report claims no sweep",
      'leftover text' not in ''.join(vm.printed), ''.join(vm.printed)[-200:])

# ----------------------------------------------------------------------
# 15. the letter prefix: one switch per flavour, opposite defaults
# ----------------------------------------------------------------------
print("*xft-strip-prefix* and *xft-dot-strip-prefix*")

vm = newvm([LAYERS])
vm.loads('(setq *xft-strip-prefix* nil)')
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
vm.run('c:XFTCONV', [None, ents])
check("with the Leica switch off the label goes in whole",
      inserts(vm) == [(0.0, 0.5, "P9")], repr(inserts(vm)))

vm = newvm([DOT_LAYERS])
vm.loads('(setq *xft-dot-strip-prefix* T)')
ents = made(vm, circle("POOL_POINTS", 1.0, 2.0))
ents += made(vm, dot_name(1.0, 2.0, "C1"))
vm.run('c:XFTCONV', [None, ents])
check("with the trace switch on the label loses its family letter",
      inserts(vm) == [(1.0, 2.0, "1")], repr(inserts(vm)))

# ----------------------------------------------------------------------
# 16. *xft-column-tol* is how wide "the same column" is.  Section 2 has
#     P9 at dx 0.2 beating the nearer P8 on the column rule; a tolerance
#     of a tenth of a text height puts them both off-column, and then
#     the nearer one wins.
# ----------------------------------------------------------------------
print("*xft-column-tol* is the width of the same-column rule")

vm = newvm([LAYERS])
vm.loads('(setq *xft-column-tol* 0.1)')
ents = made(vm, marker(0.0, 0.5))
ents += made(vm, name_text(0.2, 1.0, "P9"))
ents += made(vm, name_text(0.51, 0.5, "P8"))
vm.run('c:XFTCONV', [None, ents])
check("P9 is off-column now, so the nearer P8 wins",
      [v for _x, _y, v in inserts(vm)] == ["8"], repr(inserts(vm)))

# ----------------------------------------------------------------------
# 17. *xft-block-layer-color*: what a POINTS the drawing lacked is
#     created with -- and never applied to one it already has
# ----------------------------------------------------------------------
print("*xft-block-layer-color* colours a POINTS the drawing lacked")

vm = newvm([LAYERS])
vm.loads('(setq *xft-block-layer-color* 3)')
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
vm.run('c:XFTCONV', [None, ents])
rec = vm.tablerecs['LAYER']['POINTS']
check("POINTS was created in that colour", grp(vm.recdata[rec], 62) == 3,
      repr(vm.recdata[rec]))

POINTS_RED = """
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "POINTS") '(70 . 0) '(62 . 1)
                 '(6 . "Continuous")))"""

vm = newvm([LAYERS, POINTS_RED])
vm.loads('(xft:ensure-block)')           # the template's block, present
vm.printed = []
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
vm.run('c:XFTCONV', [None, ents])
rec = vm.tablerecs['LAYER']['POINTS']
check("an existing POINTS keeps its own colour",
      grp(vm.recdata[rec], 62) == 1, repr(vm.recdata[rec]))
check("and nothing was reported created or repaired",
      'created it' not in ''.join(vm.printed)
      and 'was off, frozen or locked' not in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

# ----------------------------------------------------------------------
# 18. a frozen, switched-off POINTS is an output layer: repaired for
#     the run, with a line saying so (a LOCKED one refuses, section 5)
# ----------------------------------------------------------------------
print("a frozen, switched-off POINTS is repaired for the run")

POINTS_FROZEN_OFF = """
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "POINTS") '(70 . 1) '(62 . -6)
                 '(6 . "Continuous")))"""

vm = newvm([LAYERS, POINTS_FROZEN_OFF])
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
vm.run('c:XFTCONV', [None, ents])
rec = vm.tablerecs['LAYER']['POINTS']
check("POINTS is thawed and switched on",
      not ((grp(vm.recdata[rec], 70) or 0) & 1)
      and grp(vm.recdata[rec], 62) == 6, repr(vm.recdata[rec]))
check("and the run said so",
      'POINTS was off, frozen or locked' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])
check("the swap went ahead onto it", inserts(vm) == [(0.0, 0.5, "9")],
      repr(inserts(vm)))

# ----------------------------------------------------------------------
# 19. the attribute's text style: the named one when the drawing has
#     it, the current TEXTSTYLE when it does not
# ----------------------------------------------------------------------
print("the attribute style falls back to TEXTSTYLE")


def attribs(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'ATTRIB':
            out.append((grp(d, 7), grp(d, 40)))
    return out


vm = newvm([LAYERS])
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
vm.run('c:XFTCONV', [None, ents])
check('no "Attributes" style in the drawing: TEXTSTYLE (STANDARD) is used',
      attribs(vm) == [('STANDARD', 4.0)], repr(attribs(vm)))

STYLE_ATTR = """
  (entmake (list '(0 . "STYLE") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbTextStyleTableRecord")
                 '(2 . "Attributes") '(70 . 0) '(40 . 0.0) '(41 . 1.0)
                 '(50 . 0.0) '(71 . 0) '(3 . "romans.shx") '(4 . "")))"""

vm = newvm([LAYERS, STYLE_ATTR])
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
vm.run('c:XFTCONV', [None, ents])
check("with the style present the attribute is written in it",
      attribs(vm) == [('Attributes', 4.0)], repr(attribs(vm)))

# ----------------------------------------------------------------------
# 20. an error mid-run reaches the command's own handler, which puts
#     the settings back, closes the group it opened and pops the mode
# ----------------------------------------------------------------------
print("an error mid-run: restore, close the group, pop the mode")

vm = newvm([LAYERS])
vm.handle_errors = True
vm.sysvars['OSMODE'] = 4133
vm.sysvars['CMDECHO'] = 1
# the insert blows up on an unbound function, the way a typo or a
# missing helper dies at the command line
vm.loads('(defun xft:insert (pt num) (xft:no-such-helper pt num))')
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
vm.run('c:XFTCONV', [None, ents])
check("aborted through *error*, not a crash",
      len(vm.handled_errors) == 1
      and 'undefined function' in vm.handled_errors[0],
      repr(vm.handled_errors))
check("the group the run opened was closed by the handler",
      [c for c in vm.commands if c and c[0] == '_.UNDO']
      == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']],
      repr(vm.commands))
check("settings restored and the error mode popped",
      vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1
      and vm.error_mode_depth == 0 and vm.error_mode_underflow == 0,
      repr((vm.sysvars['OSMODE'], vm.error_mode_depth)))
check("reported under the tool's name, with the U hint",
      any('XFTCONV error:' in s for s in vm.printed)
      and any('use U to roll the run back' in s for s in vm.printed),
      repr(vm.printed[-3:]))

# ----------------------------------------------------------------------
# 21. both flavours in one highlight -- which no real import does -- is
#     swept, because the Leica half's noise is the reason to sweep
# ----------------------------------------------------------------------
print("a selection holding both flavours is swept")

vm = newvm([LAYERS, DOT_LAYERS])
ents = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P9"))
ents += made(vm, circle("POOL_POINTS", 20.0, 20.0))
ents += made(vm, dot_name(20.0, 20.0, "C1"))
caps = made(vm, caption(20.0, 25.0, "Deep End"))
vm.run('c:XFTCONV', [None, ents + caps])
check("both markers became blocks, each read its own way",
      sorted(v for _x, _y, v in inserts(vm)) == ["9", "C1"],
      repr(inserts(vm)))
check("and the trace caption went with the Leica sweep, as documented",
      all(e in vm.deleted for e in caps), repr(caps))

# ----------------------------------------------------------------------
# 22. the setup and version commands
# ----------------------------------------------------------------------
print("XFTCONV-SETUP and XFTCONVVER")

vm = newvm()
vm.run('c:XFTCONV-SETUP', [])
check("SETUP creates the layer and the block without a conversion",
      'POINTS' in vm.tables['LAYER'] and 'ab_pt' in vm.tables['BLOCK']
      and 'are ready' in ''.join(vm.printed), ''.join(vm.printed)[-200:])
check("and issues no command", not [c for c in vm.commands if c])

vm = newvm()
vm.run('c:XFTCONVVER', [])
check("XFTCONVVER prints the loaded version",
      any(re.search(r'XFTCONV v\d+\.\d+', s) for s in vm.printed),
      repr(vm.printed))

# 23. the record, and XFTRECONV reading it back
# ----------------------------------------------------------------------
# XFTCONV erases things, and an erased entity is gone for good once the
# drawing is saved -- so the undo has to work from what was written
# down, not from the database.  What is written down is xdata on each
# block: the scale and base the run used, and the marker, the name text
# and any leftover text it swept, group by group.
print("the record XFTCONV leaves behind")


def xdata(d, app):
    """The items one application carries, [] when it is there and empty,
    None when it is not there at all."""
    g = grp(d, -3)
    if g is None:
        return None
    apps = [g] if (g and isinstance(g[0], str)) else g
    for a in apps:
        if a and a[0] == app:
            return a[1:]
    return None


def blocks(vm):
    """[(ename, data)] for every live ab_pt INSERT."""
    return [(e, vm.entdata[e]) for e in vm.entities
            if e not in vm.deleted and grp(vm.entdata[e], 0) == 'INSERT'
            and grp(vm.entdata[e], 2) == 'ab_pt']


def ents(vm, *types):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata[e]
        if not types or grp(d, 0) in types:
            out.append(d)
    return out


def shape(d):
    """An entity as the tuple a round trip has to reproduce."""
    return (grp(d, 0), grp(d, 8), grp(d, 10), grp(d, 11), grp(d, 40),
            grp(d, 1), grp(d, 62), grp(d, 72), grp(d, 73))


def near(a, b, tol=1e-6):
    """shape() tuples equal, numbers to TOL -- the record writes a
    coordinate through rtos at 8 decimals, so the round trip is exact
    to 1e-8 of a drawing unit and not to the last bit of the float."""
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(near(x, y, tol) for x, y in zip(a, b))
    if isinstance(a, float) and isinstance(b, (int, float)):
        return abs(a - b) <= tol
    if isinstance(b, float) and isinstance(a, (int, float)):
        return abs(a - b) <= tol
    return a == b


vm = newvm([LAYERS])
ents_in = []
ents_in += made(vm, marker(0.0, 0.5))
ents_in += made(vm, name_text(0.2, 1.0, "P9"))
ents_in += made(vm, marker(100.0, 100.0))
ents_in += made(vm, name_text(60.0, 60.0, "a loose note"))
before = [shape(d) for d in ents(vm)]
vm.run('c:XFTCONV', [None, ents_in])

recs = [xdata(d, 'XFTCONV') for _e, d in blocks(vm)]
check("every block carries a record", len(recs) == 2 and all(recs), repr(recs))
check("...naming the tool and the version that wrote it",
      all(r[0] == Dot(1000, 'XFTCONV') for r in recs)
      and all(re.fullmatch(r'v\d+\.\d+', r[1].b) for r in recs),
      repr(recs[0][:2]))
scales = {r[2].b for r in recs}
bases = {(r[3].b, r[4].b, r[5].b) for r in recs}
check("...and the scale and the base point the run used, as reals",
      scales == {12.0} and bases == {(50.0, 50.25, 0.0)},
      repr((scales, bases)))
check("the base recorded is the one the SCALE was actually about",
      [c for c in vm.commands if c and c[0] == '_.SCALE'][0][-2]
      == [50.0, 50.25, 0.0])
check("the run says the record is there",
      'XFTRECONV puts all of it back' in ''.join(vm.printed),
      ''.join(vm.printed)[-200:])

print("XFTRECONV puts the survey back")
vm.printed, vm.commands = [], []
vm.run('c:XFTRECONV', [None, [e for e in vm.entities if e not in vm.deleted]])

check("every ab_pt block is gone again", blocks(vm) == [], repr(blocks(vm)))
after = [shape(d) for d in ents(vm)]
check("the marker lines, the names and the swept note are all back",
      len(after) == len(before)
      and all(any(near(b, a) for a in after) for b in before),
      "before %r\nafter %r" % (sorted(map(str, before)),
                               sorted(map(str, after))))
check("...including the leftover text the purge erased",
      any(a[5] == 'a loose note' for a in after), repr(after))
scale = [c for c in vm.commands if c and c[0] == '_.SCALE']
check("one SCALE back, by 1/12 about the very base point recorded",
      len(scale) == 1 and abs(scale[0][-1] - 1.0 / 12.0) < 1e-12
      and scale[0][-2] == [50.0, 50.25, 0.0], repr(scale))
check("nothing erased is handed to that SCALE",
      all(e not in vm.deleted for e in scale[0][-3][1:]), repr(scale[0][-3]))
check("the revert is one undo group",
      [c for c in vm.commands if c and c[0] == '_.UNDO'] ==
      [['_.UNDO', '_Begin'], ['_.UNDO', '_End']], repr(vm.commands))
check("the error mode is popped and the settings are back",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0
      and vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1)
check("the report counts both halves of the job",
      '2 "ab_pt" block(s) taken back off the survey.' in ''.join(vm.printed)
      and '6 marker and text object(s) put back.' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

vm.printed = []
vm.run('c:XFTRECONV', [None, [e for e in vm.entities if e not in vm.deleted]])
check("a second revert finds no record and says so",
      'nothing carries an XFTCONV record' in ''.join(vm.printed),
      ''.join(vm.printed)[-200:])

# ----------------------------------------------------------------------
# 24. the site trace round trip: circles, and captions that never move
# ----------------------------------------------------------------------
print("the site trace, converted and put back")

vm = newvm([DOT_LAYERS])
ents_in = []
for lay, x, y, nm in SAMPLE_DOTS:
    ents_in += made(vm, circle(lay, x, y))
    if nm:
        ents_in += made(vm, dot_name(x, y, nm))
caps = []
for x, y, cs in SAMPLE_CAPTIONS:
    caps += made(vm, caption(x, y, cs))
before = [shape(d) for d in ents(vm)]
vm.run('c:XFTCONV', [None, ents_in + caps])
vm.run('c:XFTRECONV', [None, [e for e in vm.entities if e not in vm.deleted]])
after = [shape(d) for d in ents(vm)]

check("all twelve circles come back, both copies of every corner",
      len([a for a in after if a[0] == 'CIRCLE']) == 12,
      repr(len([a for a in after if a[0] == 'CIRCLE'])))
check("every marker and every label is back where it was",
      len(after) == len(before)
      and all(any(near(b, a) for a in after) for b in before),
      "%d before, %d after" % (len(before), len(after)))
check("the captions never moved -- the trace is swept neither way",
      sorted(a[5] for a in after if a[5] and ' ' in a[5]) ==
      ['Deep End', 'Diagonal 1', 'Diagonal 2', 'Shallow End'],
      repr(sorted(a[5] for a in after if a[5])))
check("and no ab_pt survives it", blocks(vm) == [])

# The trace fixture is what measures the precision claim: its
# coordinates carry more decimals than the record writes down.
worst = 0.0
for b in before:
    if not b[2]:
        continue
    a = min((a for a in after if a[0] == b[0] and a[2]),
            key=lambda a: abs(a[2][0] - b[2][0]) + abs(a[2][1] - b[2][1]))
    worst = max(worst, abs(a[2][0] - b[2][0]), abs(a[2][1] - b[2][1]))
check("a coordinate comes back within the 1e-8 the record writes to",
      worst <= 1e-8, "worst %r" % worst)

# ----------------------------------------------------------------------
# 25. the three ways XFTRECONV refuses rather than half-reverting
# ----------------------------------------------------------------------
print("what XFTRECONV will not do")

vm = newvm([LAYERS])
first = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P1"))
vm.run('c:XFTCONV', [None, first])
second = made(vm, marker(900.0, 900.5)) + made(vm, name_text(900.2, 901.0, "P2"))
vm.run('c:XFTCONV', [None, second])
live_all = [e for e in vm.entities if e not in vm.deleted]
was = [shape(d) for d in ents(vm)]
vm.printed, vm.commands = [], []
vm.run('c:XFTRECONV', [None, live_all])
check("two runs in one highlight are refused by name",
      'holds points from 2 different XFTCONV runs' in ''.join(vm.printed),
      ''.join(vm.printed)[-260:])
check("...and nothing at all is touched",
      [shape(d) for d in ents(vm)] == was and not vm.commands,
      repr(vm.commands))
check("...and that exit pops the error mode too",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0)

vm = newvm([LAYERS])
ents_in = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P3"))
vm.run('c:XFTCONV', [None, ents_in])
vm.loads('(setq lk (tblobjname "LAYER" "POINTS"))'
         '(entmod (subst (cons 70 4) (assoc 70 (entget lk)) (entget lk)))')
live_all = [e for e in vm.entities if e not in vm.deleted]
vm.printed, vm.commands = [], []
vm.run('c:XFTRECONV', [None, live_all])
check("a locked block layer is named, and nothing runs",
      'Unlock POINTS' in ''.join(vm.printed) and not vm.commands
      and len(blocks(vm)) == 1, ''.join(vm.printed)[-200:])

vm = newvm([LAYERS])
vm.loads('(setq *xft-record* nil)')
ents_in = made(vm, marker(0.0, 0.5)) + made(vm, name_text(0.2, 1.0, "P4"))
vm.run('c:XFTCONV', [None, ents_in])
check("with *xft-record* off nothing is written down",
      all(xdata(d, 'XFTCONV') is None for _e, d in blocks(vm)))
check("...and the run says so instead of promising a revert",
      '*xft-record* is off' in ''.join(vm.printed), ''.join(vm.printed)[-200:])
vm.printed, vm.commands = [], []
vm.run('c:XFTRECONV', [None, [e for e in vm.entities if e not in vm.deleted]])
check("XFTRECONV then says there is nothing to work from",
      'nothing carries an XFTCONV record' in ''.join(vm.printed)
      and not vm.commands and len(blocks(vm)) == 1,
      ''.join(vm.printed)[-200:])

# ----------------------------------------------------------------------
# 26. the cut-short paths, exactly as XFTCONV's own
# ----------------------------------------------------------------------
print("XFTRECONV, cut short")

vm = newvm([LAYERS])
vm.sysvars['CTAB'] = 'Model'
vm.run('c:XFTRECONV', [None, None])
check("an empty drawing: says so, mode popped, settings untouched",
      'Nothing to work on' in ''.join(vm.printed)
      and vm.error_mode_depth == 0 and vm.error_mode_underflow == 0
      and vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1)

vm = newvm([LAYERS])
vm.handle_errors = True
vm.run('c:XFTRECONV', [None, esc])
check("Esc at the highlight goes through the handler, once",
      vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
check("...which popped the mode and restored the settings",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0
      and vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1)
check("a cancel prints no error line",
      not any('XFTRECONV error' in s for s in vm.printed))

# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all XFTCONV checks passed")
