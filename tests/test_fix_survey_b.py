"""Quiet failures in the survey tools: POINTRENAMER, WCALST, ABCDEF,
ALTABCDEF and XYPLOT.

Each of these ran to a clean-looking finish over a wrong answer:

  * POINTRENAMER took its direction knob only in the keyword's exact
    spelling.  A shop's "Counterclockwise" or "ccw" was offered as the
    default and then numbered the survey CLOCKWISE on Enter.
  * POINTRENAMER swept (410 . CTAB), and CTAB names the LAYOUT while
    the drafter works on model space through one of its viewports: the
    clash warning never fired there and Enter = whole drawing found
    nothing at all.
  * POINTRENAMER measured the start pick (UCS) against a perimeter read
    out of entget (world), so a moved UCS started the count elsewhere.
  * WCALST tested its stair windows (UCS corners) against far-side
    segments out of entget (world): under a moved UCS no window caught
    anything and the stairs were cut full of darts.  Its side pick had
    the same mismatch, and on a band drawn as one polyline it seeded
    the trace on the OTHER long side.  A window that caught nothing
    was never mentioned.
  * ABCDEF and ALTABCDEF read the typed rectangle sides through the
    sheet reader's scan repairs, so a plain 214 was taken for a 2/4
    whose slash had been scanned as a 1: a frame half an inch wide.
    Two bare numbers, "20 6", were summed to 26" without a word, and
    the blanks (getstring T) keeps round an answer were never trimmed
    before AutoCAD's distance reader saw it.
  * XYPLOT kept ABCDEF's rule that a reading of 0 or less is
    unreadable, and dropped the origin and every negative offset.
  * ABCDEF and XYPLOT started ABHD with (vl-cmdf "_.ABHD").  The command
    processor does not know AutoLISP commands, so ABHD never ran after
    the tool said it was starting.  With PICKFIRST off they then said
    "Starting ABHD on the N point(s)" and, on the next line, took it
    back.

The VM's world is flat -- its (trans ...) is the identity -- so a UCS
is modelled HERE for the length of one run: an origin and a turn,
applied by a trans that moves a point between code 0 (world) and codes
1 and 2 (the UCS).  Its (command ...) accepts any name, so the refusal
AutoCAD gives a c: name sent through it is modelled here too.  And its
(distof ...) forgives blanks round the text, so a distance reader that
does not is modelled for the padded-answer check.

SRC is a table so a scratch runner can point it at older copies and
watch these fail there: set SURVEY_B_SRC to a folder holding the five
files under their own names.

Run: python3 tests/test_fix_survey_b.py
"""

import math
import os
import sys
from contextlib import contextmanager

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, LispError, Dot, Sym, BUILTINS, truthy  # noqa: E402


def back_of(tool):
    """TOOL's Back sentinel at this tier.  A grouped twin may answer
    the library's CAL-BACK instead (ABCDEF does, ALTABCDEF does not):
    read off mirror_shared.py's symbol map, so the check follows the
    tier rather than failing on a rename made by design."""
    name = 'AB-BACK'
    if os.environ.get('CALOFIN_LISP_ROOT') == 'shared':
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))), 'tools'))
        import mirror_shared
        entry = next(v for k, v in mirror_shared.TOOLS.items()
                     if k.upper() == tool.upper())
        name = entry.get('symbols', {}).get(name, name)
    return Sym(name.lower())

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, '..')

SRC = {
    'POINTRENAMER': os.path.join(REPO, 'lisp', 'pointrenamer',
                                 'POINTRENAMER.lsp'),
    'WCALST': os.path.join(REPO, 'lisp', 'wcalst', 'wcalst.lsp'),
    'ABCDEF': os.path.join(REPO, 'lisp', 'abcdef', 'abcdef.lsp'),
    'ALTABCDEF': os.path.join(REPO, 'lisp', 'altabcdef', 'ALTABCDEF.lsp'),
    'XYPLOT': os.path.join(REPO, 'lisp', 'xyplot', 'XYPLOT.lsp'),
}
if os.environ.get('SURVEY_B_SRC'):
    SRC = {k: os.path.join(os.environ['SURVEY_B_SRC'], os.path.basename(v))
           for k, v in SRC.items()}

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def attempt(label, fn):
    """Run FN; a LispError is a failed check, not a crashed file."""
    try:
        return fn()
    except LispError as e:
        check(label, False, f"died: {e}")
        return None


# ---- the UCS model ----------------------------------------------------

class Ucs:
    """ORIGIN is the UCS origin in world coordinates, ANG the turn of
    its X axis from the world X axis, in radians."""

    def __init__(self, origin=(0.0, 0.0), ang=0.0):
        self.ox, self.oy = float(origin[0]), float(origin[1])
        self.c, self.s = math.cos(ang), math.sin(ang)

    def to_world(self, p, disp=False):
        x, y, z = (list(p) + [0.0])[:3]
        wx, wy = x * self.c - y * self.s, x * self.s + y * self.c
        if not disp:
            wx, wy = wx + self.ox, wy + self.oy
        return [wx, wy, z]

    def to_ucs(self, p, disp=False):
        x, y, z = (list(p) + [0.0])[:3]
        if not disp:
            x, y = x - self.ox, y - self.oy
        return [x * self.c + y * self.s, -x * self.s + y * self.c, z]


@contextmanager
def in_ucs(origin=(0.0, 0.0), ang=0.0):
    u = Ucs(origin, ang)
    orig = BUILTINS[Sym('trans')]

    def is_ucs(code):
        return isinstance(code, int) and not isinstance(code, bool) \
            and code in (1, 2)

    def _trans(vm, a):
        p = a[0]
        if not isinstance(p, list) or len(p) < 2:
            raise LispError(f"bad argument type: point {p!r}", vm)
        p = [float(p[0]), float(p[1]), float(p[2]) if len(p) > 2 else 0.0]
        disp = len(a) > 3 and truthy(a[3])
        w = u.to_world(p, disp) if is_ucs(a[1]) else p
        return u.to_ucs(w, disp) if is_ucs(a[2]) else w

    BUILTINS[Sym('trans')] = _trans
    try:
        yield u
    finally:
        BUILTINS[Sym('trans')] = orig


@contextmanager
def command_knows_no_lisp():
    """AutoCAD's command processor knows native, ARX and .NET commands.
    A name defined by (defun c:NAME ...) is reached only by TYPING it --
    the command line's own c: fallback, which (command) and (vl-cmdf)
    skip -- so sent through them it is Unknown command."""
    orig = BUILTINS[Sym('command')]

    def _command(vm, a):
        if a and isinstance(a[0], str):
            name = 'c:' + a[0].lstrip('._').lower()
            if isinstance(vm.get(Sym(name)), tuple):
                raise LispError(f'Unknown command "{a[0]}" -- an AutoLISP '
                                'command sent to the command processor', vm)
        return orig(vm, a)

    BUILTINS[Sym('command')] = _command
    try:
        yield
    finally:
        BUILTINS[Sym('command')] = orig


@contextmanager
def distof_takes_no_blanks():
    """The VM's distof matches with a pattern that forgives blanks round
    the text.  Whether AutoCAD's does is not something a test here can
    settle, so this is the reader that does NOT: a padded answer is
    nil, as it would be to a reader that wants the distance and
    nothing else."""
    orig = BUILTINS[Sym('distof')]

    def _distof(vm, a):
        if a and isinstance(a[0], str) and a[0] != a[0].strip():
            return None
        return orig(vm, a)

    BUILTINS[Sym('distof')] = _distof
    try:
        yield
    finally:
        BUILTINS[Sym('distof')] = orig


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


# ======================================================================
# POINTRENAMER
# ======================================================================

LAYER_POOL = '''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "POOL") '(70 . 0) '(62 . 4)
                 '(6 . "Continuous")))'''


def rect(tab='Model'):
    """240 x 120, closed, drawn counter-clockwise from the origin."""
    return f'''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(410 . "{tab}") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 240.0 0.0)   '(42 . 0.0)
                 '(10 240.0 120.0) '(42 . 0.0)
                 '(10 0.0 120.0)   '(42 . 0.0)))'''


def ab_pt(x, y, number, tab='Model'):
    return f'''
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(410 . "{tab}")
                 '(100 . "AcDbBlockReference")
                 '(2 . "ab_pt") (list 10 {x} {y} 0.0) '(66 . 1)))
  (entmake (list '(0 . "ATTRIB") '(8 . "POINTS")
                 '(2 . "number") '(1 . "{number}")))
  (entmake (list '(0 . "SEQEND") '(8 . "POINTS")))'''


def made(vm, src):
    before = len(vm.entities)
    vm.loads(src)
    return vm.entities[before:]


def numbers(vm):
    """{(x, y): attribute value} for every attributed ab_pt INSERT."""
    out = {}
    ents = [e for e in vm.entities if e not in vm.deleted]
    for i, e in enumerate(ents):
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'INSERT' and grp(d, 66) == 1:
            ins = grp(d, 10)
            att = vm.entdata.get(ents[i + 1], [])
            out[(ins[0], ins[1])] = grp(att, 1)
    return out


def ptr_vm(fixtures, sysvars=None):
    vm = VM()
    vm.load(SRC['POINTRENAMER'])
    vm.loads(LAYER_POOL)
    for f in fixtures:
        vm.loads(f)
    for k, v in (sysvars or {}).items():
        vm.sysvars[k] = v
    return vm


def ptr_run(vm, script):
    # the leading None answers the pickfirst probe every run starts with
    vm.run('c:POINTRENAMER', [None] + list(script))
    return ''.join(vm.printed)


# ---- the direction knob, in the spellings a shop types --------------
print("POINTRENAMER: the direction knob is read in any spelling")

#: one point on each side of the rectangle; counter-clockwise from the
#: origin corner runs bottom, right, top, left
SIDES = [ab_pt(60, 0, 17), ab_pt(240, 60, 3), ab_pt(120, 118, 8),
         ab_pt(0, 60, 9)]
CCW = ['1', '2', '3', '4']       # bottom, right, top, left
CW = ['4', '3', '2', '1']


def order(got):
    return [got[(60.0, 0.0)], got[(240.0, 60.0)], got[(120.0, 118.0)],
            got[(0.0, 60.0)]]


for knob, want, shown in (("Counterclockwise", CCW, 'COunterclockwise'),
                          ("counterclockwise", CCW, 'COunterclockwise'),
                          ("ccw", CCW, 'COunterclockwise'),
                          ("CCW", CCW, 'COunterclockwise'),
                          ("COunterclockwise", CCW, 'COunterclockwise'),
                          ("clockwise", CW, 'Clockwise'),
                          ("sideways", CW, 'Clockwise')):
    vm = ptr_vm([rect()] + SIDES)
    vm.loads(f'(setq ptr:*dir* "{knob}")')

    def go():
        ptr_run(vm, [None, None, (0.0, 0.0, 0.0), None, 6.0, 1, 'Yes'])
        return vm
    if attempt(f"ptr:*dir* {knob!r}", go) is None:
        continue
    asked = [p for p, _ in vm.prompts if 'which way around' in p]
    check(f"ptr:*dir* {knob!r} is offered as <{shown}>",
          asked and f'<{shown}>' in asked[0], repr(asked))
    check(f"...and Enter numbers the survey that way round",
          order(numbers(vm)) == want, repr(order(numbers(vm))))
    check(f"...and the session remembers the keyword, not the knob",
          vm.globals.get(Sym('ptr:*dir-now*')) == shown,
          repr(vm.globals.get(Sym('ptr:*dir-now*'))))


# ---- the space being worked in, not the tab -------------------------
print("POINTRENAMER: model space through a layout viewport is model space")

VIEWPORT = {'CTAB': 'Layout1', 'CVPORT': 2, 'TILEMODE': 0}
PAPER = {'CTAB': 'Layout1', 'CVPORT': 1, 'TILEMODE': 0}

vm = ptr_vm([rect(), ab_pt(60, 0, 17), ab_pt(0, 60, 9)], VIEWPORT)
txt = attempt("Enter from a viewport",
              lambda: ptr_run(vm, [None, None, (0.0, 0.0, 0.0),
                                   'Clockwise', 6.0, 1, 'Yes']))
if txt is not None:
    check("Enter = whole drawing from a viewport finds the model points",
          '2 point(s) renumbered' in txt, txt[-400:])

vm = ptr_vm([LAYER_POOL], VIEWPORT)
rct = made(vm, rect())
ins = made(vm, ab_pt(60, 0, 17)) + made(vm, ab_pt(0, 60, 9))
made(vm, ab_pt(900, 900, 11))            # outside the highlight, on 11
txt = attempt("the clash sweep from a viewport",
              lambda: ptr_run(vm, [rct + ins, None, (0.0, 0.0, 0.0),
                                   'Clockwise', 6.0, 10, 'Yes']))
if txt is not None:
    check("the clash warning fires from a viewport too",
          'Warning: 1 point(s) OUTSIDE the highlight already carry a'
          ' number between 10 and 11' in txt, txt[-500:])

vm = ptr_vm([rect('Layout1'), ab_pt(60, 0, 17, tab='Layout1'),
             ab_pt(0, 60, 9, tab='Layout1'), ab_pt(120, 118, 5)], PAPER)
txt = attempt("Enter in paper space",
              lambda: ptr_run(vm, [None, None, (0.0, 0.0, 0.0),
                                   'Clockwise', 6.0, 1, 'Yes']))
if txt is not None:
    check("paper space itself still sweeps the layout, not model space",
          '2 point(s) to renumber' in txt
          and numbers(vm)[(120.0, 118.0)] == '5', txt[-400:])


# ---- the start pick under a moved UCS -------------------------------
print("POINTRENAMER: the start pick is taken out of the UCS")

START = [ab_pt(200, 0, 'A'), ab_pt(60, 0, 'B'), ab_pt(0, 60, 'C')]


def start_run(origin):
    vm = ptr_vm([rect()] + START)
    with in_ucs(origin) as u:
        # the drafter snaps to the bottom-right corner, world (240, 0)
        ptr_run(vm, [None, None, u.to_ucs([240.0, 0.0, 0.0]),
                     'Clockwise', 6.0, 1, 'Yes'])
    g = numbers(vm)
    return [g[(200.0, 0.0)], g[(60.0, 0.0)], g[(0.0, 60.0)]]


world = attempt("start pick, World UCS", lambda: start_run((0.0, 0.0)))
moved = attempt("start pick, moved UCS", lambda: start_run((60.0, 0.0)))
check("World UCS: the count runs from the corner that was clicked",
      world == ['1', '2', '3'], repr(world))
check("a UCS moved 60 along X starts the count at the same corner",
      moved == world, repr(moved))


# ======================================================================
# WCALST
# ======================================================================
print("WCALST: the stair window is read in the frame it was drawn in")

ANG = [math.radians(30 + 15 * i) for i in range(9)]
NEAR = [(200.0 * math.cos(a), 200.0 * math.sin(a)) for a in ANG]
FAR = [(176.0 * math.cos(a), 176.0 * math.sin(a)) for a in ANG]
MID = [(NEAR[0][0] + NEAR[1][0]) / 2.0, (NEAR[0][1] + NEAR[1][1]) / 2.0,
       0.0]


def wlayer(n, c):
    return f'''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "{n}") '(70 . 0) '(62 . {c})
                 '(6 . "Continuous")))'''


def wline(p, q, lay):
    return f'''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "{lay}")
                 '(100 . "AcDbLine")
                 '(10 {p[0]!r} {p[1]!r} 0.0) '(11 {q[0]!r} {q[1]!r} 0.0)))'''


def wc_vm():
    vm = VM()
    vm.load(SRC['WCALST'])
    for L in (wlayer('NEAR', 1), wlayer('FAR', 4), wlayer('RUNG', 2)):
        vm.loads(L)
    vm.sysvars['CLAYER'] = 'NEAR'
    return vm


def wc_band(vm):
    """test_wcalst's oracle band, its far side ONE polyline."""
    ents = []
    for i in range(8):
        ents += made(vm, wline(NEAR[i], NEAR[i + 1], 'NEAR'))
    pl = " ".join(f"'(10 {p[0]!r} {p[1]!r})" for p in FAR)
    ents += made(vm, f"""
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "FAR")
                 '(100 . "AcDbPolyline") '(90 . 9) '(70 . 0) {pl}))""")
    for i in range(9):
        ents += made(vm, wline(NEAR[i], FAR[i], 'RUNG'))
    return ents


def wc_stair(origin, ang, corners):
    """Window the world box CORNERS (which holds FAR[3]..FAR[5]) as the
    drafter would see it under the UCS: its corners in UCS terms."""
    vm = wc_vm()
    ents = wc_band(vm)
    with in_ucs(origin, ang) as u:
        a = u.to_ucs(corners[0])
        b = u.to_ucs(corners[1])
        lo = [min(a[0], b[0]), min(a[1], b[1]), 0.0]
        hi = [max(a[0], b[0]), max(a[1], b[1]), 0.0]
        vm.run('c:WCALST', [None, ents, [ents[0], u.to_ucs(MID)], None,
                            None, lo, hi, None])
    return ''.join(vm.printed)


BOX = ([-50.0, 165.0, 0.0], [50.0, 180.0, 0.0])
KEPT = ('target <1%: 8 dart(s), 0 insert(s)',
        '6 dart(s) fall inside the stair section(s)')

for label, origin, ang in (("World UCS", (0.0, 0.0), 0.0),
                           ("a UCS moved 100 along X", (100.0, 0.0), 0.0),
                           ("a UCS turned 90 degrees", (0.0, 0.0),
                            math.pi / 2)):
    txt = attempt(label, lambda: wc_stair(origin, ang, BOX))
    if txt is not None:
        check(f"{label}: the window keeps its stairs clear of darts",
              all(k in txt for k in KEPT), txt[-400:])
        check(f"{label}: and says nothing about an empty window",
              'caught no line' not in txt, txt[-400:])

print("WCALST: a window that caught nothing is said")
txt = attempt("an empty window",
              lambda: wc_stair((0.0, 0.0), 0.0,
                               ([-50.0, 0.0, 0.0], [50.0, 10.0, 0.0])))
if txt is not None:
    check("the run says the window held nothing back",
          '1 stair window(s) caught no line of the far side' in txt,
          txt[-400:])
    check("and the darts are cut as for no window at all",
          'target <1%: 14 dart(s)' in txt, txt[-400:])

print("WCALST: the side pick is taken out of the UCS")


def wc_loop(origin):
    """The band drawn as ONE closed polyline -- both long sides and the
    two ends -- so the pick is all that says which side is straightened.
    The drafter clicks the OUTER side; the UCS is moved one band width
    outward, so the raw pick numbers sit on the inner side."""
    vm = wc_vm()
    pts = NEAR + list(reversed(FAR))
    pl = " ".join(f"'(10 {p[0]!r} {p[1]!r})" for p in pts)
    ents = made(vm, f"""
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "NEAR")
                 '(100 . "AcDbPolyline") '(90 . {len(pts)}) '(70 . 1) {pl}))""")
    for i in range(1, 8):
        ents += made(vm, wline(NEAR[i], FAR[i], 'RUNG'))
    pick = [(NEAR[3][0] + NEAR[4][0]) / 2, (NEAR[3][1] + NEAR[4][1]) / 2,
            0.0]
    with in_ucs(origin) as u:
        vm.run('c:WCALST', [None, ents, [ents[0], u.to_ucs(pick)], None,
                            None, None])
    return ''.join(vm.printed)


out = math.radians(67.5)
for label, origin in (("World UCS", (0.0, 0.0)),
                      ("a UCS moved a band width outward",
                       (24.0 * math.cos(out), 24.0 * math.sin(out)))):
    txt = attempt(label, lambda: wc_loop(origin))
    if txt is not None:
        check(f"{label}: the side clicked is the side straightened",
              'developed length 417.68' in txt, txt[-400:])


# ======================================================================
# ABCDEF / ALTABCDEF: the typed rectangle sides
# ======================================================================
print("ABCDEF / ALTABCDEF: a typed side is read as typed")


def getdim(tool, typed):
    pre = tool.lower()
    vm = VM()
    vm.load(SRC[tool])
    vm.script = list(typed)
    vm.prompts = []
    vm.loads(f'(setq *w* ({pre}:getdim "Dimension A-B (width across the'
             f' top)" T))')
    left = list(vm.script)
    w = vm.globals.get(Sym('*w*'))
    return w, ''.join(vm.printed), left


for tool in ('ABCDEF', 'ALTABCDEF'):
    for typed, want in (("214", 214.0), ("118", 118.0), ("314", 314.0),
                        ("2116", 2116.0), ("20'-6\"", 246.0),
                        ("17'-10 1/4\"", 214.25), ("246.5", 246.5),
                        ('20-6"', 246.0)):
        r = attempt(f"{tool} {typed}", lambda: getdim(tool, [typed]))
        if r is None:
            continue
        w, said, _ = r
        check(f"{tool}: {typed!r} is {want} inches",
              isinstance(w, float) and abs(w - want) < 1e-9, repr(w))
    r = attempt(f"{tool} echo", lambda: getdim(tool, ["214"]))
    if r is not None:
        check(f"{tool}: the reading is echoed back",
              "read as 17'-10\"" in r[1], r[1][-200:])
    # a typed answer only the scan repairs could read -- the slash of
    # 1/4 typed as a 1 -- is refused and asked again, not guessed at
    r = attempt(f"{tool} repair",
                lambda: getdim(tool, ["17'-10 114", "17'-10 1/4"]))
    if r is not None:
        w, said, left = r
        check(f"{tool}: '17'-10 114' is refused and asked again",
              'cannot be read as typed' in said and w == 214.25
              and not left, said[-300:])
    # two bare numbers leave feet and inches to a guess: summed, "20 6"
    # was a 26" side where 20'-6" was almost certainly meant
    for typed in ("20 6", "20 6 1/2", '20 6"'):
        r = attempt(f"{tool} {typed}",
                    lambda: getdim(tool, [typed, "20'-6"]))
        if r is not None:
            w, said, left = r
            check(f"{tool}: {typed!r} is refused and asked again",
                  'cannot be read as typed' in said and w == 246.0
                  and not left, f"{w!r} {said[-300:]!r}")
    # ...while a number and its fraction are still one reading
    for typed, want in (("10 1/2", 10.5), ('6 1/2"', 6.5),
                        ("20'-6 1/2", 246.5)):
        r = attempt(f"{tool} {typed}", lambda: getdim(tool, [typed]))
        if r is not None:
            w, said, left = r
            check(f"{tool}: {typed!r} is still {want} inches",
                  isinstance(w, float) and abs(w - want) < 1e-9
                  and 'cannot be read' not in said, f"{w!r} {said[-200:]!r}")
    # (getstring T) hands over the blanks round an answer: trimmed before
    # the distance reader sees it, a padded 214 is 214 and not refused
    # as a scan repair it never needed
    with distof_takes_no_blanks():
        for typed, want in ((" 214", 214.0), ("214 ", 214.0),
                            ("  20'-6\"  ", 246.0)):
            r = attempt(f"{tool} {typed!r}",
                        lambda: getdim(tool, [typed, "1"]))
            if r is not None:
                w, said, left = r
                check(f"{tool}: {typed!r} reads as {want} under a strict"
                      " distance reader",
                      isinstance(w, float) and abs(w - want) < 1e-9
                      and 'cannot be read' not in said,
                      f"{w!r} {said[-200:]!r}")
        r = attempt(f"{tool} padded back", lambda: getdim(tool, [" b "]))
        if r is not None:
            check(f"{tool}: ' b ' is still Back", r[0] == back_of(tool),
                  repr(r[0]))
    r = attempt(f"{tool} back", lambda: getdim(tool, ["B"]))
    if r is not None:
        check(f"{tool}: B is still Back", r[0] == back_of(tool), repr(r[0]))
    r = attempt(f"{tool} zero", lambda: getdim(tool, ["0", "-5'", "20'"]))
    if r is not None:
        check(f"{tool}: zero and negatives are still refused",
              r[1].count('enter a positive dimension') == 2
              and r[0] == 240.0, r[1][-300:])


# ======================================================================
# XYPLOT: a coordinate of 0 or less is a coordinate
# ======================================================================
print("XYPLOT: the reader takes 0 and negatives, and a lone - is blank")


def xy_parse(raw):
    vm = VM()
    vm.load(SRC['XYPLOT'])
    vm.globals[Sym('*raw*')] = raw
    v = vm.loads('(xyp:parse-log *raw* "P / X" nil)')
    return v, vm.globals.get(Sym('xyp:*fixes*'))


for raw, want in (("0", 0.0), ("0.0", 0.0), ("-36.0", -36.0),
                  ("-4'-0\"", -48.0), ("-0.5", -0.5), ("0'-0\"", 0.0),
                  ("-1'-0 1/2\"", -12.5), ("12'-3 1/2\"", 147.5)):
    r = attempt(f"parse {raw}", lambda: xy_parse(raw))
    if r is not None:
        check(f"{raw!r} reads as {want}",
              isinstance(r[0], float) and abs(r[0] - want) < 1e-9
              and not r[1], repr(r))
for raw in ("-", "--", " - "):
    r = attempt(f"parse {raw}", lambda: xy_parse(raw))
    if r is not None:
        check(f"{raw!r} is not measured: left blank, and said",
              r[0] is None and r[1], repr(r))


# ======================================================================
# ABCDEF / XYPLOT: the handoff reaches ABHD
# ======================================================================
print("ABCDEF / XYPLOT: ABHD is called, not sent to the command processor")

import test_abcdef as ta  # noqa: E402
import test_xyplot as tx  # noqa: E402

ta.LSP = SRC['ABCDEF']
tx.LSP = SRC['XYPLOT']

with command_knows_no_lisp():
    rows = [("1", ta.tapes(120.0, -60.0)), ("2", ta.tapes(300.0, -40.0))]
    vm = attempt("ABCDEF hands off",
                 lambda: ta.run(rows, answer="Yes", with_abhd=True))
    if vm is not None:
        ss = vm.globals.get(Sym('*abhd-saw*'))
        check("ABCDEF: Yes starts ABHD on the two points it plotted",
              ta.abhd_ran(vm) == 1 and ss is not None and len(ss) - 1 == 2,
              repr(ta.abhd_ran(vm)))
        check("ABCDEF: with its own undo group already closed",
              vm.globals.get(Sym('*abhd-undo*')) == 0)

    # with PICKFIRST off ABHD will ask for the points: one line says so,
    # not a "starting on the points" line and a second taking it back
    vm = attempt("ABCDEF, PICKFIRST off",
                 lambda: ta.run(rows, answer="Yes", with_abhd=True,
                                post='(setvar "PICKFIRST" 0)'))
    if vm is not None:
        said = ''.join(vm.printed)
        check("ABCDEF, PICKFIRST off: one line, no promise taken back",
              ta.abhd_ran(vm) == 1
              and 'Starting ABHD on the' not in said
              and 'Starting ABHD - PICKFIRST is off, so window the 2'
                  ' point(s) just plotted when it asks.' in said,
              said[-300:])

    vm = attempt("XYPLOT hands off", lambda: tx.run(answer="Yes"))
    if vm is not None:
        ss = vm.globals.get(Sym('*abhd-saw*'))
        check("XYPLOT: Yes starts ABHD on graph 1's points",
              tx.abhd_ran(vm) == 1 and ss is not None
              and len(ss) - 1 == len(tx.SHEET), repr(tx.abhd_ran(vm)))

    vm = attempt("XYPLOT, PICKFIRST off",
                 lambda: tx.run(answer="Yes",
                                post='(setvar "PICKFIRST" 0)'))
    if vm is not None:
        said = ''.join(vm.printed)
        check("XYPLOT, PICKFIRST off: one line, no promise taken back",
              tx.abhd_ran(vm) == 1
              and 'Starting ABHD on the' not in said
              and "Starting ABHD - PICKFIRST is off, so window graph 1's"
                  f" {len(tx.SHEET)} point(s) when it asks." in said,
              said[-300:])


# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all survey-b checks passed")
