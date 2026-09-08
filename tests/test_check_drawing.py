"""Runtime tests for CHECK (check_drawing.lsp): the attachment audit.
Every linear/aligned dimension's definition points must sit on a
curve, and every ARC endpoint must sit at the END of another object;
CHECK repairs both in place, recolors the offenders and drops an XLINE
through each shifted dimension's original points.  First coverage.

These runs are the canary for the VM's vlax-curve surface: before it
existed, the dimension audit swallowed the undefined-function error
inside its vl-catch-all-apply and reported "0 shifted" as a clean
green while doing nothing.  The "1 shifted" asserts below fail loudly
if that ever regresses.

Angles in the ARC fixtures are radians (entget's unit), computed from
the geometry rather than typed.

Run: python3 tests/test_check_drawing.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_check_drawing.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
LSP = os.path.join(HERE, '..', 'lisp', 'check', 'check_drawing.lsp')
RELEASES = os.path.join(HERE, '..', 'releases')

TOL = 1e-6
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


def near(p, q, tol=TOL):
    return (p is not None and q is not None
            and math.dist(p[:2], q[:2]) <= tol)


LINE = '''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity") '(5 . "L1")
                 '(100 . "AcDbLine")
                 '(10 0.0 0.0 0.0) '(11 100.0 0.0 0.0)))'''


def dim(handle, p13, p14):
    """An aligned DIMENSION (type bits 1) between two def points."""
    return f'''
  (entmake (list '(0 . "DIMENSION") '(100 . "AcDbEntity") '(5 . "{handle}")
                 '(100 . "AcDbDimension") '(70 . 1)
                 '(13 {p13[0]!r} {p13[1]!r} 0.0)
                 '(14 {p14[0]!r} {p14[1]!r} 0.0)))'''


def arc(handle, c, r, p_start, p_end, extra=''):
    """An ARC around centre c through the two given endpoints,
    counter-clockwise from p_start to p_end, angles in radians."""
    a0 = math.atan2(p_start[1] - c[1], p_start[0] - c[0])
    a1 = math.atan2(p_end[1] - c[1], p_end[0] - c[0])
    return f'''
  (entmake (list '(0 . "ARC") '(100 . "AcDbEntity") '(5 . "{handle}")
                 '(100 . "AcDbCircle")
                 '(10 {c[0]!r} {c[1]!r} 0.0) '(40 . {r!r})
                 '(50 . {a0!r}) '(51 . {a1!r}){extra}))'''


def made(vm, src):
    before = len(vm.entities)
    vm.loads(src)
    return vm.entities[before:]


def newvm():
    vm = VM()
    vm.load(LSP)
    return vm


def arc_endpoints(vm, e):
    d = vm.entdata.get(e, [])
    c, r = grp(d, 10), grp(d, 40)
    a0, a1 = grp(d, 50), grp(d, 51)
    return ([c[0] + r * math.cos(a0), c[1] + r * math.sin(a0)],
            [c[0] + r * math.cos(a1), c[1] + r * math.sin(a1)],
            c, r)


def xlines(vm):
    out = []
    for e in vm.entities:
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'XLINE':
            out.append((grp(d, 10), grp(d, 11), grp(d, 8)))
    return out


# ----------------------------------------------------------------------
# statics: pure ASCII, banner, releases/ twin
# ----------------------------------------------------------------------
print("statics")

SRC = open(LSP, encoding="ascii").read()   # also asserts pure ASCII

m = re.search(r'\*checkdrawing-version\*\s+"v(\d+)\.(\d+)"', SRC)
check("version banner present", m is not None)
if m:
    rev = f"{m.group(1)}{m.group(2)}"
    twins = [n for n in os.listdir(RELEASES)
             if re.match(rf"check_drawing_\d{{6}}_REV{rev}\.lsp$", n)]
    check(f"releases/ twin at REV{rev} exists", len(twins) == 1, repr(twins))
    if len(twins) == 1:
        twin = open(os.path.join(RELEASES, twins[0]),
                    encoding="ascii").read()
        check("releases/ twin is identical", twin == SRC)

# ----------------------------------------------------------------------
# 1. the dimension audit: one stray point shifted, one dim left alone
# ----------------------------------------------------------------------
print("dimension attachment")

vm = newvm()
ents = made(vm, LINE)
bad = made(vm, dim("D1", (20.0, 0.0), (60.0, 0.5)))    # 14 floats 0.5 off
good = made(vm, dim("D2", (10.0, 0.0), (90.0, 0.0)))   # both attached
ents += bad + good
vm.sysvars['CMDECHO'] = 1
vm.run('c:CHECK', [None, ents])

d = vm.entdata[bad[0]]
check("the stray point lands on the closest spot of the line",
      near(grp(d, 14), (60.0, 0.0)) and near(grp(d, 13), (20.0, 0.0)),
      repr((grp(d, 13), grp(d, 14))))
check("the shifted dimension is recolored red", grp(d, 62) == 1)
check("the attached dimension is untouched",
      grp(vm.entdata[good[0]], 62) is None and
      near(grp(vm.entdata[good[0]], 14), (90.0, 0.0)))

xl = xlines(vm)
want_dir = [40.0 / math.hypot(40.0, 0.5), 0.5 / math.hypot(40.0, 0.5)]
check("one XLINE through the ORIGINAL points, on the check layer",
      len(xl) == 1 and near(xl[0][0], (20.0, 0.0)) and
      near(xl[0][1], want_dir) and xl[0][2] == 'CHECK-CONSTRUCTION',
      repr(xl))
check("the check layer was created",
      'CHECK-CONSTRUCTION' in vm.tables['LAYER'])

txt = ''.join(vm.printed)
check("the report counts 2 checked, 1 shifted - the silent-green canary",
      'Dimensions: 2 checked, 1 shifted onto nearest object (red)' in txt,
      txt[-400:])
check("the construction-line note names the layer",
      'Construction lines through the shifted' in txt)
check("the run is one undo group with CMDECHO restored",
      [c for c in vm.commands if c] ==
      [['_.UNDO', '_Begin'], ['_.UNDO', '_End']] and
      vm.sysvars['CMDECHO'] == 1)

# ----------------------------------------------------------------------
# 1b. shared anchors: a corner two dims measure to is never shifted
# ----------------------------------------------------------------------
print("shared anchors")

vm = newvm()
ents = made(vm, LINE)
# the hypotenuse corner: 30 above the line, nothing drawn through it,
# and TWO dimensions measuring to it
c1 = made(vm, dim("D3", (10.0, 0.0), (140.0, 30.0)))
c2 = made(vm, dim("D4", (90.0, 0.0), (140.0, 30.0)))
stray = made(vm, dim("D5", (20.0, 0.0), (50.0, 12.0)))    # a real stray
miss = made(vm, dim("D6", (30.0, 0.0), (140.05, 30.02)))  # 0.054 off the
ents += c1 + c2 + stray + miss                            # corner
vm.run('c:CHECK', [None, ents])

check("the shared corner is left exactly where it was drawn",
      near(grp(vm.entdata[c1[0]], 14), (140.0, 30.0)) and
      near(grp(vm.entdata[c2[0]], 14), (140.0, 30.0)),
      repr((grp(vm.entdata[c1[0]], 14), grp(vm.entdata[c2[0]], 14))))
check("neither anchored dimension is recolored",
      grp(vm.entdata[c1[0]], 62) is None and
      grp(vm.entdata[c2[0]], 62) is None)
check("a point only one dim measures to is still shifted onto the line",
      near(grp(vm.entdata[stray[0]], 14), (50.0, 0.0)) and
      grp(vm.entdata[stray[0]], 62) == 1,
      repr(grp(vm.entdata[stray[0]], 14)))
check("a near miss goes to the anchor, not the 30-away line",
      near(grp(vm.entdata[miss[0]], 14), (140.0, 30.0)),
      repr(grp(vm.entdata[miss[0]], 14)))
check("only the two shifted dims leave a construction line",
      len(xlines(vm)) == 2, repr(xlines(vm)))

txt = ''.join(vm.printed)
check("the run says how many points it treated as anchors",
      '1 point(s) carry 2 or more dimensions - treated as anchors'
      ' and left alone.' in txt, txt[-500:])
check("the tally counts 4 checked, 2 shifted",
      'Dimensions: 4 checked, 2 shifted onto nearest object (red)' in txt,
      txt[-400:])

# ----------------------------------------------------------------------
# 2. the arc audit: an end resting mid-line snaps to the line's end
# ----------------------------------------------------------------------
print("arc endpoint attachment")

vm = newvm()
ents = made(vm, LINE)
# starts ON the line at x=30 (mid-object), ends exactly at the line's
# (100, 0) end; bulges below through its circular midpoint
a = made(vm, arc("A1", (65.0, -20.0), math.hypot(35.0, 20.0),
                 (30.0, 0.0), (100.0, 0.0)))
ents += a
vm.run('c:CHECK', [None, ents])

p1, p2, c, r = arc_endpoints(vm, a[0])
endset = sorted([p1, p2])
check("the mid-line end snapped to the line's nearer end",
      near(endset[0], (0.0, 0.0)) and near(endset[1], (100.0, 0.0)),
      repr(endset))
# the OLD arc's circular midpoint: centre (65,-20), r from (30,0),
# swept CCW start->end, so the midpoint hangs at the bottom
r0 = math.hypot(35.0, 20.0)
a0 = math.atan2(20.0, -35.0)
sweep = (math.atan2(20.0, 35.0) - a0) % (2 * math.pi)
old_mid = (65.0 + r0 * math.cos(a0 + sweep / 2),
           -20.0 + r0 * math.sin(a0 + sweep / 2))
check("the arc still passes through its old midpoint",
      abs(math.dist(c[:2], old_mid) - r) < 1e-6,
      repr((c, r, old_mid)))
check("the snapped arc is recolored magenta",
      grp(vm.entdata[a[0]], 62) == 6)
txt = ''.join(vm.printed)
check("the snap distance is reported",
      'start snapped 30.0000' in txt and
      'Arcs: 1 checked, 1 with endpoint(s) snapped (magenta)' in txt,
      txt[-400:])

# ----------------------------------------------------------------------
# 3. a floating arc end goes to the closest end anywhere
# ----------------------------------------------------------------------
print("a floating arc end")

vm = newvm()
ents = made(vm, LINE)
# start floats 5 above the line (past tolerance), end sits at (100, 0)
a = made(vm, arc("A2", (65.0, -15.0), math.hypot(35.0, 15.0),
                 (30.0, 5.0), (100.0, 0.0)))
del ents[:0]
ents += a
vm.run('c:CHECK', [None, ents])
p1, p2, _c, _r = arc_endpoints(vm, a[0])
endset = sorted([p1, p2])
check("the floating end lands on the line's closest end",
      near(endset[0], (0.0, 0.0)) and near(endset[1], (100.0, 0.0)),
      repr(endset))
check("and is reported as snapped",
      'with endpoint(s) snapped' in ''.join(vm.printed))

# ----------------------------------------------------------------------
# 4. a non-planar arc is skipped, said out loud
# ----------------------------------------------------------------------
print("a non-planar arc")

vm = newvm()
ents = made(vm, LINE)
ents += made(vm, arc("A3", (65.0, -20.0), math.hypot(35.0, 20.0),
                     (30.0, 0.0), (100.0, 0.0),
                     extra=" '(210 0.0 0.0 -1.0)"))
vm.run('c:CHECK', [None, ents])
check("the flipped-extrusion arc is skipped, not refit",
      'Arcs: 0 checked, 0 with endpoint(s) snapped (magenta),'
      ' 1 non-planar skipped' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

# ----------------------------------------------------------------------
# 5. a broken check layer is repaired before the report goes on it
# ----------------------------------------------------------------------
print("the check layer is repaired")

vm = newvm()
vm.loads('''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "CHECK-CONSTRUCTION") '(70 . 1) '(62 . -2)
                 '(6 . "Continuous")))''')
ents = made(vm, LINE)
ents += made(vm, dim("D3", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:CHECK', [None, ents])
rec = vm.loads('(tblsearch "LAYER" "CHECK-CONSTRUCTION")')
check("frozen + off comes back on, thawed",
      grp(rec, 70) == 0 and grp(rec, 62) == 2, repr(rec))
check("and the repair is announced",
      'was off, frozen or locked - restored' in ''.join(vm.printed))

# ----------------------------------------------------------------------
# 6. the guards, the alias and the version command
# ----------------------------------------------------------------------
print("guards, alias, version")

# the guard messages go through (prompt), which the VM deliberately
# records nowhere - so the guards are pinned behaviorally: no undo
# group opens and nothing is touched
vm = newvm()
ents = made(vm, LINE)
vm.run('c:CHECK', [None, ents])
check("a selection with no dims or arcs runs nothing",
      not [c for c in vm.commands if c] and
      grp(vm.entdata[ents[0]], 62) is None, repr(vm.commands))

vm = newvm()
ents = made(vm, dim("D4", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:CHECK', [None, ents])
check("a selection with nothing to attach to runs nothing",
      not [c for c in vm.commands if c] and
      near(grp(vm.entdata[ents[0]], 14), (60.0, 0.5)), repr(vm.commands))

vm = newvm()
vm.run('c:CHECK', [None, None])
check("Enter at the highlight cancels without touching anything",
      not [c for c in vm.commands if c] and not vm.entities,
      repr(vm.commands))

vm = newvm()
ents = made(vm, LINE)
ents += made(vm, dim("D5", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:DIMARCCHECK', [None, ents])
check("DIMARCCHECK is the same command",
      '1 shifted onto nearest object' in ''.join(vm.printed))

vm = newvm()
vm.run('c:CHECKVER', [])
check("CHECKVER prints the banner",
      f"CHECK v{m.group(1)}.{m.group(2)}" in ''.join(vm.printed))

# ----------------------------------------------------------------------
# 7. pickfirst: a selection made before the command was typed
# ----------------------------------------------------------------------
print("pickfirst")

vm = newvm()
ents = made(vm, LINE)
ents += made(vm, dim("D6", (20.0, 0.0), (60.0, 0.5)))
vm.pickfirst = ['<ss>'] + ents
vm.run('c:CHECK', [])
check("the probe took it; the highlight was never asked",
      not vm.prompts and
      '1 shifted onto nearest object' in ''.join(vm.printed),
      repr(vm.prompts))

# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# 8. the tunables are honoured after load.  The TUNABLES block promises
#    that every knob is read when the command runs, so a (setq ...) at
#    the command line changes the next run; each knob is exercised
#    here through the behaviour it is supposed to change, and the
#    report's wording is checked to follow the colour knobs rather
#    than say "red" whatever they hold.
# ----------------------------------------------------------------------
print("tunables honoured after load")

vm = newvm()
vm.loads('(setq *cfchk-tol* 1.0)')
ents = made(vm, LINE)
ents += made(vm, dim("K1", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:CHECK', [None, ents])
txt = ''.join(vm.printed)
check("*cfchk-tol* raised to 1.0: the 0.5 gap counts as attached",
      near(grp(vm.entdata[ents[-1]], 14), (60.0, 0.5)) and
      grp(vm.entdata[ents[-1]], 62) is None and
      'Dimensions: 1 checked, 0 shifted' in txt, txt[-300:])
check("and the summary echoes the tolerance it ran with",
      'attachment tolerance 1.000000' in txt, txt[-300:])

vm = newvm()
vm.loads('(setq *cfchk-dim-color* 4 *cfchk-arc-color* 5)')
ents = made(vm, LINE)
ents += made(vm, dim("K2", (20.0, 0.0), (60.0, 0.5)))
ents += made(vm, arc("K3", (65.0, -20.0), math.hypot(35.0, 20.0),
                     (30.0, 0.0), (100.0, 0.0)))
vm.run('c:CHECK', [None, ents])
txt = ''.join(vm.printed)
check("*cfchk-dim-color* / *cfchk-arc-color*: the entities take the new colours",
      grp(vm.entdata[ents[1]], 62) == 4 and grp(vm.entdata[ents[2]], 62) == 5,
      repr((grp(vm.entdata[ents[1]], 62), grp(vm.entdata[ents[2]], 62))))
check("and the report says cyan and blue, never red or magenta",
      'recolored cyan.' in txt and 'recolored blue.' in txt and
      'shifted onto nearest object (cyan)' in txt and
      'snapped (blue)' in txt and
      'recolored red' not in txt and '(red)' not in txt and
      'magenta' not in txt, txt[-600:])

vm = newvm()
vm.loads('(setq *cfchk-dim-color* 41)')
ents = made(vm, LINE)
ents += made(vm, dim("K4", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:CHECK', [None, ents])
check("a colour with no name is reported by its number",
      'recolored colour 41.' in ''.join(vm.printed) and
      grp(vm.entdata[ents[-1]], 62) == 41, ''.join(vm.printed)[-300:])

vm = newvm()
vm.loads('(setq *cfchk-constr-layer* "MY-CHECK" *cfchk-constr-color* 5)')
ents = made(vm, LINE)
ents += made(vm, dim("K5", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:CHECK', [None, ents])
xl = xlines(vm)
rec = vm.loads('(tblsearch "LAYER" "MY-CHECK")')
check("*cfchk-constr-layer* / *cfchk-constr-color*: the XLINE lands on the"
      " renamed layer, created in the new colour, and the note names it",
      len(xl) == 1 and xl[0][2] == 'MY-CHECK' and grp(rec, 62) == 5 and
      'are on layer MY-CHECK.' in ''.join(vm.printed), repr((xl, rec)))

vm = newvm()
vm.loads("(setq *cfchk-dim-types* '(1))")
ents = made(vm, LINE)
# a ROTATED dimension (type 0) with a stray point is no longer audited
ents += made(vm, dim("K6", (20.0, 0.0), (60.0, 0.5))
             .replace("'(70 . 1)", "'(70 . 0)"))
vm.run('c:CHECK', [None, ents])
check("*cfchk-dim-types* without 0: a rotated dimension is skipped, not shifted",
      near(grp(vm.entdata[ents[-1]], 14), (60.0, 0.5)) and
      grp(vm.entdata[ents[-1]], 62) is None and
      'Dimensions: 0 checked, 0 shifted onto nearest object (red),'
      ' 1 unsupported type skipped' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

vm = newvm()
vm.loads('(setq *cfchk-anchor-min* 3)')
ents = made(vm, LINE)
ents += made(vm, dim("K7", (10.0, 0.0), (140.0, 30.0)))
ents += made(vm, dim("K8", (90.0, 0.0), (140.0, 30.0)))
vm.run('c:CHECK', [None, ents])
p7, p8 = grp(vm.entdata[ents[1]], 14), grp(vm.entdata[ents[2]], 14)
check("*cfchk-anchor-min* 3: two dims at a corner no longer make an anchor,"
      " so both are pulled down onto the line",
      abs(p7[1]) < TOL and abs(p8[1]) < TOL and
      'treated as anchors' not in ''.join(vm.printed) and
      'Dimensions: 2 checked, 2 shifted' in ''.join(vm.printed),
      repr((p7, p8)))

vm = newvm()
vm.loads('(setq *cfchk-anchor-tol* 0.2)')
ents = made(vm, LINE)
ents += made(vm, dim("K9", (10.0, 0.0), (140.0, 30.0)))
ents += made(vm, dim("K10", (90.0, 0.0), (140.1, 30.1)))   # 0.14 apart
vm.run('c:CHECK', [None, ents])
check("*cfchk-anchor-tol* 0.2: two corners 0.14 apart count as one anchor",
      near(grp(vm.entdata[ents[1]], 14), (140.0, 30.0)) and
      '1 point(s) carry 2 or more dimensions' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

vm = newvm()
vm.loads('(setq *cfchk-dist-prec* 1 *cfchk-tol-prec* 2)')
ents = made(vm, LINE)
ents += made(vm, dim("K11", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:CHECK', [None, ents])
check("*cfchk-dist-prec* / *cfchk-tol-prec*: distances print at the asked places",
      'point 2 shifted 0.5 ' in ''.join(vm.printed) and
      'attachment tolerance 0.00)' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

vm = newvm()
vm.loads('(setq *cfchk-dist-mode* 4 *cfchk-dist-prec* 4)')
ents = made(vm, LINE)
ents += made(vm, dim("K12", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:CHECK', [None, ents])
check("*cfchk-dist-mode* 4: the shift prints in feet and inches",
      'point 2 shifted 0\'-0 1/2"' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

vm = newvm()
vm.loads("(setq *cfchk-curve-types* '(\"ARC\"))")
ents = made(vm, LINE)
ents += made(vm, dim("K13", (20.0, 0.0), (60.0, 0.5)))
vm.run('c:CHECK', [None, ents])
check("*cfchk-curve-types* without LINE: a line is no longer something to"
      " attach to, so the guard stops the run",
      not [c for c in vm.commands if c] and
      near(grp(vm.entdata[ents[-1]], 14), (60.0, 0.5)), repr(vm.commands))

vm = newvm()
vm.loads('(setq *cfchk-planar-eps* 2.0)')
ents = made(vm, LINE)
ents += made(vm, arc("K14", (65.0, -20.0), math.hypot(35.0, 20.0),
                     (30.0, 0.0), (100.0, 0.0),
                     extra=" '(210 0.5 0.0 1.0)"))
vm.run('c:CHECK', [None, ents])
check("*cfchk-planar-eps* widened: a tilted arc is audited instead of skipped",
      'Arcs: 1 checked, 1 with endpoint(s) snapped' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

# ----------------------------------------------------------------------
# 9. the TUNABLES block is where every knob lives: no *cfchk-* global
#    is set anywhere else at top level, and each one carries a comment
# ----------------------------------------------------------------------
print("the tunables block")

lines = SRC.splitlines()
start = next(i for i, l in enumerate(lines) if l.startswith(';;;  TUNABLES'))
end = next(i for i, l in enumerate(lines) if l.startswith(';;;  END TUNABLES'))
check("the block opens and closes", 0 < start < end)
outside = [l for i, l in enumerate(lines)
           if l.startswith('(setq *cfchk-') and not start < i < end]
check("no *cfchk-* knob is set outside the block", not outside, repr(outside))
def explained(i):
    """A knob is explained by a trailing remark, or by the ;;-prose at
    the head of the paragraph it sits in - knobs that share one
    explanation are grouped under it deliberately."""
    if re.search(r'\)\s*;', lines[i]):
        return True
    j = i - 1
    while j >= 0 and lines[j].strip():
        if lines[j].lstrip().startswith(';;'):
            return True
        j -= 1
    return False


undocumented = [l for i, l in enumerate(lines[start:end], start)
                if l.startswith('(setq *cfchk-') and not explained(i)]
check("every knob carries an explanation", not undocumented, repr(undocumented))
knobs = re.findall(r'^\(setq (\*cfchk-[a-z-]+\*)', SRC, re.M)
vm = newvm()
check("every knob loads bound (a torn edit would leave one nil)",
      all(vm.loads(k) is not None for k in knobs), repr(knobs))
readme = open(os.path.join(HERE, '..', 'lisp', 'check', 'README.md')).read()
missing = [k for k in knobs if k not in readme]
check("and the README's Tunables table names every knob", not missing,
      repr(missing))

print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all CHECK checks passed")
