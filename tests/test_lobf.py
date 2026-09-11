"""Runtime tests for LOBF: put points where the answer is known by hand,
run the REAL command over them, and check which of the three lines comes
back and what it says about the points it could not hold.

The tool is one question -- where does the error go? -- asked three ways,
so the tests are about the three answers being genuinely different and
about the rule that decides which one Enter takes.

Script values: None is Enter, a string is a typed keyword, a callable is
called with the VM when the prompt is reached (the way to click a line
the run itself has just drawn).
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, '..')
SRC = os.path.join(ROOT, 'lisp', 'lobf', 'LOBF.lsp')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


# ---------------------------------------------------------------- fixtures

def point(x, y, layer='POINTS'):
    return f'''
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 '(8 . "{layer}") '(100 . "AcDbPoint")
                 (list 10 {x} {y} 0.0)))'''


def ab_pt(x, y, number):
    """An ab_pt block carrying its surveyed number."""
    return f'''
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(100 . "AcDbBlockReference")
                 '(2 . "ab_pt") (list 10 {x} {y} 0.0) '(66 . 1)))
  (entmake (list '(0 . "ATTRIB") '(8 . "POINTS")
                 '(2 . "number") '(1 . "{number}")))
  (entmake (list '(0 . "SEQEND") '(8 . "POINTS")))'''


def vm_with(extra=''):
    vm = VM()
    vm.load(SRC)
    if extra:
        vm.loads(extra)
    return vm


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


def live(vm, kind=None, layer=None):
    """Every entity still in the drawing, optionally of one type and on
    one layer, as (ename, dxf-data)."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if kind and grp(d, 0) != kind:
            continue
        if layer and grp(d, 8) != layer:
            continue
        out.append((e, d))
    return out


def said(vm):
    return ''.join(vm.printed)


def run(vm, script):
    """The command, with the leading None that answers the pickfirst
    probe -- no pre-selection, so it asks for one."""
    try:
        vm.run('c:LOBF', [None] + list(script))
    except LispError as e:
        raise AssertionError(f"LOBF failed: {e}") from None
    return said(vm)


def call(vm, expr):
    return vm.loads(expr)


def lisp_pts(pts):
    """A LISP list of (x y name) point records."""
    return "'(" + " ".join(f'({x} {y} "{n}")' for x, y, n in pts) + ")"


# ----------------------------------------------------------------------
# 1. the fits themselves
# ----------------------------------------------------------------------
print("the three fits")

vm = vm_with()

# exactly collinear, sloping: the fit is that line, to the last bit
line = call(vm, f'(lobf:tls {lisp_pts([(0, 0, "1"), (10, 5, "2"), (20, 10, "3"), (40, 20, "4")])})')
org, dir_ = line[0], line[1]
check("least squares through collinear points is that line",
      abs(dir_[1] / dir_[0] - 0.5) < 1e-9, repr(line))
worst = max(abs((x - org[0]) * -dir_[1] + (y - org[1]) * dir_[0])
            for x, y in [(0, 0), (10, 5), (20, 10), (40, 20)])
check("...with every point exactly on it", worst < 1e-9, repr(worst))

# a VERTICAL run: the trap that catches a plain y-on-x regression,
# which divides by a zero spread in x
line = call(vm, f'(lobf:tls {lisp_pts([(7, 0, "1"), (7, 30, "2"), (7, 61, "3")])})')
check("a vertical run fits (perpendicular least squares, not y-on-x)",
      line is not None and abs(line[1][0]) < 1e-9, repr(line))

# every point on one spot: there is no direction, and the fit says so
check("points all on one spot have no fit",
      call(vm, f'(lobf:tls {lisp_pts([(5, 5, "1"), (5, 5, "2")])})') in (None, []),
      repr(call(vm, f'(lobf:tls {lisp_pts([(5, 5, "1"), (5, 5, "2")])})')))

# ROW: five on y=0, one 6" up over the middle.  By hand:
#   fit 1  centroid (80,1), horizontal      -> worst 5, mean 10/6
#   fit 2  drops the high one               -> worst 0, ignored 6" off
#   fit 3  narrowest band is 0..6           -> y=3, every point 3" off
ROW = [(0, 0, "1"), (40, 0, "2"), (80, 0, "3"), (120, 0, "4"),
       (160, 0, "5"), (80, 6, "6")]

f1 = call(vm, f'(lobf:cand "a" (lobf:tls {lisp_pts(ROW)}) {lisp_pts(ROW)} nil)')
check("fit 1 spreads the error over all six", abs(f1[4] - 5.0) < 1e-9,
      f"worst={f1[4]}")
check("...and its mean is 10/6", abs(f1[5] - 10.0 / 6.0) < 1e-9, f"mean={f1[5]}")

d1 = call(vm, f'(lobf:drop1 {lisp_pts(ROW)})')
check("fit 2 drops the point that is actually off", d1[2] == 5, repr(d1))

f3 = call(vm, f'(lobf:cand "c" (lobf:minimax {lisp_pts(ROW)}) {lisp_pts(ROW)} nil)')
check("fit 3 halves the band: worst 3in, not 5in", abs(f3[4] - 3.0) < 1e-9,
      f"worst={f3[4]}")
check("...and shares it perfectly - every point the same 3in",
      abs(f3[5] - 3.0) < 1e-9, f"mean={f3[5]}")
check("the three fits are genuinely three",
      len({round(f1[4], 6), round(f3[4], 6)}) == 2)

# ----------------------------------------------------------------------
# 2. the rule that picks the default
# ----------------------------------------------------------------------
print("the outlier rule")

cands = call(vm, f'(lobf:candidates {lisp_pts(ROW)})')
two = cands[1]
check("fit 2 names the point it set aside", two[3][2] == "6", repr(two[3]))
check("...and how far off it is", abs(two[7] - 6.0) < 1e-9, f"off={two[7]}")
check("...while the five it held sit exactly on the line",
      two[4] < 1e-9, f"worst held={two[4]}")
check("one drastic outlier makes fit 2 the default",
      call(vm, '(lobf:outlier-p (cadr (lobf:candidates '
                + lisp_pts(ROW) + ')))') is not None)

# error shared evenly: a gentle bow, nobody to blame
BOW = [(0, 0, "1"), (40, 2, "2"), (80, 3, "3"), (120, 2, "4"), (160, 0, "5")]
check("a shared error does NOT make fit 2 the default",
      call(vm, '(lobf:outlier-p (cadr (lobf:candidates '
                + lisp_pts(BOW) + ')))') is None)

# a tiny outlier: 40 times the rest, but only a sixteenth off -- the
# floor is what stops LOBF blaming a point for noise
TINY = [(0, 0, "1"), (40, 0, "2"), (80, 0, "3"), (120, 0, "4"),
        (160, 0.0625, "5")]
check("a drastic RATIO on a tiny distance is not an outlier (the floor)",
      call(vm, '(lobf:outlier-p (cadr (lobf:candidates '
                + lisp_pts(TINY) + ')))') is None)

check("a fit colour list shorter than the fits falls back, not to nil",
      call(vm, '(progn (setq lobf:*fit-colors* (list 3)) (lobf:fit-color 3))')
      == 7)
call(vm, "(setq lobf:*fit-colors* '(3 2 6))")
check("a nonsense default-fit knob is clamped to a fit that exists",
      call(vm, '(progn (setq lobf:*default-fit* "9") (lobf:fallback-fit))')
      == "1")
call(vm, '(setq lobf:*default-fit* "1")')

# ----------------------------------------------------------------------
# 3. the command, end to end
# ----------------------------------------------------------------------
print("the command")

DRAWING = ''.join(point(x, y) for x, y, _ in ROW[:5]) + ab_pt(80, 6, 7)

vm = vm_with(DRAWING)
txt = run(vm, [None, None, None])      # Enter = whole drawing; Enter, no click
check("three candidate lines are drawn while you choose",
      '3 candidate line(s) are drawn' in txt, txt[:250])
check("the table names the set-aside point",
      'Pt. 7 set aside' in txt, txt)
check("the verdict says fit 2 is what Enter takes",
      'fit 2 is what Enter takes' in txt, txt)
kept = live(vm, 'XLINE')
check("Enter kept exactly one line", len(kept) == 1, repr(len(kept)))
check("...on the LOBF layer", kept and grp(kept[0][1], 8) == 'LOBF',
      repr(kept and grp(kept[0][1], 8)))
check("...drawn ByLayer, not in its preview colour",
      kept and grp(kept[0][1], 62) == 256, repr(kept and grp(kept[0][1], 62)))
xd = grp(kept[0][1], 10) if kept else None
check("...along the five good points, not the average of six",
      xd is not None and abs(xd[1]) < 1e-9, repr(xd))
check("the point it gave up on is ringed",
      len(live(vm, 'CIRCLE', 'LOBF-IGNORED')) == 1,
      repr(live(vm, 'CIRCLE', 'LOBF-IGNORED')))
check("...and the ring drops its candidate colour once it is the only one",
      grp(live(vm, 'CIRCLE', 'LOBF-IGNORED')[0][1], 62) == 256,
      repr(grp(live(vm, 'CIRCLE', 'LOBF-IGNORED')[0][1], 62)))
check("and named on the command line",
      'Pt. 7 is NOT on this line' in txt, txt[-600:])
check("nothing is left on the preview layer",
      live(vm, layer='LOBF-PREVIEW') == [],
      repr([grp(d, 0) for _, d in live(vm, layer='LOBF-PREVIEW')]))

vm = vm_with(DRAWING)
txt = run(vm, [None, "1"])
kept = live(vm, 'XLINE')
xd = grp(kept[0][1], 10) if kept else None
check("typing 1 keeps the balanced fit instead",
      len(kept) == 1 and abs(xd[1] - 1.0) < 1e-9, repr(xd))
check("...and rings nobody, because it gave nobody up",
      live(vm, 'CIRCLE', 'LOBF-IGNORED') == [])

vm = vm_with(DRAWING)
txt = run(vm, [None, "3"])
kept = live(vm, 'XLINE')
xd = grp(kept[0][1], 10) if kept else None
check("typing 3 keeps the centred band",
      len(kept) == 1 and abs(xd[1] - 3.0) < 1e-9, repr(xd))

vm = vm_with(DRAWING)
txt = run(vm, [None, "None"])
check("None leaves the drawing as it was",
      live(vm, 'XLINE') == [] and live(vm, layer='LOBF-PREVIEW') == [],
      repr(live(vm, 'XLINE')))
check("...and says so", 'nothing was added' in txt, txt[-200:])

vm = vm_with(DRAWING)
txt = run(vm, [None, "All"])
check("All keeps all three, in their preview colours",
      len(live(vm, 'XLINE')) == 3, repr(len(live(vm, 'XLINE'))))
check("...each in its own colour",
      len({grp(d, 62) for _, d in live(vm, 'XLINE')}) == 3,
      repr([grp(d, 62) for _, d in live(vm, 'XLINE')]))

# clicking a line beats translating a colour into a number
vm = vm_with(DRAWING)


def click_third(v):
    """The XLINE of fit 3 -- the third one the run drew."""
    return [e for e, _ in live(v, 'XLINE')][2]


txt = run(vm, [None, None, click_third])
kept = live(vm, 'XLINE')
xd = grp(kept[0][1], 10) if kept else None
check("clicking a line keeps that one",
      len(kept) == 1 and abs(xd[1] - 3.0) < 1e-9, repr(xd))

# Redo is the picker's way back
vm = vm_with(DRAWING)
txt = run(vm, [None, "Redo", None, "1"])
check("Redo clears the trio and asks again",
      len(live(vm, 'XLINE')) == 1 and 'highlight the points again' in txt,
      repr(len(live(vm, 'XLINE'))))

# ----------------------------------------------------------------------
# 4. the edges
# ----------------------------------------------------------------------
print("too few points, and points that are not a line")

vm = vm_with(point(0, 0) + point(100, 50))
txt = run(vm, [None])                 # no picker at all: two points, one line
check("two points are drawn without a picker",
      'nothing to choose between' in txt, txt)
check("...as one line on the LOBF layer",
      len(live(vm, 'XLINE', 'LOBF')) == 1, repr(live(vm, 'XLINE')))

vm = vm_with(point(3, 4))
txt = run(vm, [None])
check("one point is refused, by name", 'it takes two to make a line' in txt,
      txt)
check("...and nothing is drawn", live(vm, 'XLINE') == [])

vm = vm_with(point(9, 9) + point(9, 9) + point(9, 9))
txt = run(vm, [None])
check("a triple shot on one spot dedupes to one point, and is refused",
      'it takes two to make a line' in txt, txt)

vm = vm_with(point(0, 0) + point(100, 0) + point(50, 60) + point(50, -60))
txt = run(vm, [None, "None"])
check("a blob is called out before you keep anything",
      'CAUTION' in txt and 'may not be one straight line' in txt, txt)

vm = vm_with(''.join(point(x, y) for x, y, _ in ROW))
txt = run(vm, [None, "None"])
check("a bare POINT run numbers its points in reading order",
      'Pt. 6 set aside' in txt, txt)

# ----------------------------------------------------------------------
# 5. the file's own rules
# ----------------------------------------------------------------------
print("the file's own rules")

src = open(SRC, encoding='utf-8').read()

check("ASCII only", all(ord(c) < 128 for c in src),
      repr([c for c in src if ord(c) >= 128][:5]))
check("the version banner is the shape release_lisp.py reads",
      re.search(r'\(setq \*lobf-version\* "v\d+\.\d+"\)', src) is not None)
check("no tabs", '\t' not in src)


def test_the_tunables_block_holds_every_knob_each_explained():
    """STANDARDS section 5: every setting in one block at the top, each
    with a sentence saying what moves when you change it, and each a row
    in the README."""
    lines = src.splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith(';;;  TUNABLES'))
    end = next(i for i, l in enumerate(lines) if l.startswith(';;;  END TUNABLES'))
    state = set(re.findall(r'^\(setq (lobf:\*[a-z0-9-]+\*)', src[src.index(
        ';;;  END TUNABLES'):], re.M))

    def explained(i):
        j = i - 1
        while j >= 0 and lines[j].strip():
            if lines[j].lstrip().startswith(';;'):
                return True
            j -= 1
        return False

    undoc = [l for i, l in enumerate(lines[start:end], start)
             if l.startswith('(setq lobf:*') and not explained(i)]
    assert not undoc, undoc
    knobs = re.findall(r'^\(setq (lobf:\*[a-z0-9-]+\*)', src, re.M)
    outside = [k for k in knobs if k not in state
               and k not in src[src.index(';;;  TUNABLES'):
                                src.index(';;;  END TUNABLES')]]
    assert not outside, outside
    readme = open(os.path.join(ROOT, 'lisp', 'lobf', 'README.md'),
                  encoding='utf-8').read()
    missing = [k for k in knobs if k not in state and k not in readme]
    assert not missing, missing
    print("  ok   %d knobs, all inside the block, all explained,"
          " all in the README" % len([k for k in knobs if k not in state]))


test_the_tunables_block_holds_every_knob_each_explained()


def test_the_readme_quotes_the_values_the_code_actually_holds():
    """A knob table is only worth having if its middle column is the
    number in the file -- a default documented as 4.0 and set to 8.0 is
    worse than no table, because it is read and believed."""
    readme = open(os.path.join(ROOT, 'lisp', 'lobf', 'README.md'),
                  encoding='utf-8').read()
    block = src[src.index(';;;  TUNABLES'):src.index(';;;  END TUNABLES')]
    wrong = []
    for name, val in re.findall(
            r'^\(setq (lobf:\*[a-z0-9-]+\*)\s+(.+?)\)\s*(?:;.*)?$',
            block, re.M):
        row = re.search(r'^\| `' + re.escape(name) + r'` \| `([^`]*)` \|',
                        readme, re.M)
        if row is None:
            wrong.append(f"{name}: no README row")
        elif row.group(1) != val.strip():
            wrong.append(f"{name}: code {val.strip()!r},"
                         f" README {row.group(1)!r}")
    assert not wrong, wrong
    print("  ok   every knob's README default is the value in the file")


test_the_readme_quotes_the_values_the_code_actually_holds()

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all LOBF checks passed")
