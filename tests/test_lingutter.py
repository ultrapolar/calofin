#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""LINGUTTER: the outermost loop, the keep rules, and the handover.

LINGUTTER erases nearly everything in a drawing, so the two decisions it
makes have to be exactly right: which loop is the perimeter, and which
dimension survives.  Both are worked out by lg:analyze without touching
the drawing, which is what makes them testable here -- the real
LINGUTTER.lsp is loaded into the AutoLISP VM and run against a drawing
built entity by entity.

It also carries a PORT.  LINGUTTER is a standalone file and cannot call
into PADDLE.lsp, so lg:arcdata / lg:area / lg:ent-segs / lg:chain are
copies of paddle--arcdata / --area / --ent-segs / --chain.  A port
drifts silently -- COVERCHECK sat on PADDLE's old corner tolerance for
several revisions -- so both files are loaded into one session and the
two implementations are run on the same geometry.  When PADDLE's
chaining changes, port the change into LINGUTTER.lsp and this goes
green again.

Usage:  python3 tests/test_lingutter.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_lingutter.py
"""

import math
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

LISP_ROOT = os.path.join(REPO_DIR, os.environ.get("CALOFIN_LISP_ROOT", "lisp"))
LINGUTTER = os.path.join(LISP_ROOT, "lingutter", "LINGUTTER.lsp")
PADDLE = os.path.join(LISP_ROOT, "paddle", "PADDLE.lsp")
# the shared tier keeps every file flat in parts/, on the cal: library
if os.path.basename(LISP_ROOT) == "shared":
    PARTS = os.path.join(LISP_ROOT, "parts")
    LIB = os.path.join(PARTS, "CALOFIN-LIB.lsp")
    LINGUTTER = os.path.join(PARTS, "LINGUTTER.lsp")
    PADDLE = os.path.join(PARTS, "PADDLE.lsp")
else:
    LIB = None

from lispvm import VM, NIL, LispError, Ent, Dot, Sym  # noqa: E402

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


# ---------------------------------------------------------------- fixtures

def newvm(layers=("POOL", "DIMENSION", "POINTS", "NOTES", "PADS")):
    vm = VM()
    if LIB:
        vm.load(LIB)
    vm.load(LINGUTTER)
    for lay in layers:
        vm.tables['LAYER'].add(lay)
    for sty in ("STANDARD", "SIDE STANDARD", "STANDARD INCHES",
                "CROSS DIMENSIONS", "CROSS DIM"):
        vm.tables['DIMSTYLE'].add(sty)
    vm.sysvars['CTAB'] = 'Model'
    return vm


def ent(vm, data):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = data
    return e


def line(vm, p1, p2, layer='POOL', tab='Model'):
    return ent(vm, [Dot(0, 'LINE'), Dot(8, layer), Dot(410, tab),
                    [10, float(p1[0]), float(p1[1]), 0.0],
                    [11, float(p2[0]), float(p2[1]), 0.0]])


def arc(vm, cen, r, sa, ea, layer='POOL'):
    return ent(vm, [Dot(0, 'ARC'), Dot(8, layer), Dot(410, 'Model'),
                    [10, float(cen[0]), float(cen[1]), 0.0],
                    Dot(40, float(r)), Dot(50, float(sa)), Dot(51, float(ea))])


def lwpl(vm, verts, closed=True, layer='POOL'):
    """verts as (x, y) or (x, y, bulge)."""
    data = [Dot(0, 'LWPOLYLINE'), Dot(8, layer), Dot(410, 'Model'),
            Dot(90, len(verts)), Dot(70, 1 if closed else 0)]
    for v in verts:
        data.append([10, float(v[0]), float(v[1])])
        if len(v) > 2 and v[2]:
            data.append(Dot(42, float(v[2])))
    return ent(vm, data)


def dim(vm, style, p13, p14, layer='DIMENSION', kind=0):
    return ent(vm, [Dot(0, 'DIMENSION'), Dot(8, layer), Dot(410, 'Model'),
                    Dot(70, kind), Dot(3, style),
                    [13, float(p13[0]), float(p13[1]), 0.0],
                    [14, float(p14[0]), float(p14[1]), 0.0]])


def rdim(vm, style, p10, layer='DIMENSION'):
    """A radius dim: no 13/14 at all, it hangs off group 10."""
    return ent(vm, [Dot(0, 'DIMENSION'), Dot(8, layer), Dot(410, 'Model'),
                    Dot(70, 4), Dot(3, style),
                    [10, float(p10[0]), float(p10[1]), 0.0]])


def other(vm, etype, layer='0', tab='Model'):
    return ent(vm, [Dot(0, etype), Dot(8, layer), Dot(410, tab),
                    [10, 5.0, 5.0, 0.0]])


def rectangle(vm, x0, y0, x1, y1, layer='POOL', gap=0.0):
    """Four loose lines round a rectangle; GAP leaves the bottom open."""
    return [line(vm, (x0 + gap, y0), (x1, y0), layer),
            line(vm, (x1, y0), (x1, y1), layer),
            line(vm, (x1, y1), (x0, y1), layer),
            line(vm, (x0, y1), (x0, y0), layer)]


def alive(vm):
    return [e for e in vm.entities if e not in vm.deleted]


def dxf(vm, e):
    d = {}
    for g in vm.entdata[e]:
        if isinstance(g, Dot):
            d.setdefault(g.a, g.b)
        elif isinstance(g, list) and g:
            d.setdefault(g[0], g[1] if len(g) == 2 else g[1:])
    return d


def alive_of(vm, etype):
    return [e for e in alive(vm) if dxf(vm, e).get(0) == etype]


def analyze(vm, ss='(ssget "_X")'):
    """lg:analyze over a highlighted set, unpacked into a dict.  The
    default hands it everything, which is what most of these checks
    want; the scoping checks pass a set of their own."""
    r = vm.loads("(lg:analyze %s)" % ss)
    return {
        'vts': r[0] if r[0] is not NIL else None,
        'gap': r[1] if r[1] is not NIL else None,
        'kill': list(r[2]) if r[2] is not NIL else [],
        'nany': int(r[3]),
        'nperim': int(r[4]),
        'dropped': dict((d.a, int(d.b)) for d in (r[5] or [])),
        'nother': int(r[6]),
        'nspared': int(r[7]),
    }


def analyze_sel(vm, ents):
    """lg:analyze over exactly ENTS, handed over the way AutoCAD hands a
    pickfirst set to a command."""
    vm.pickfirst = ['<ss>'] + list(ents)
    return analyze(vm, '(ssget "_I")')


def loop_xy(vts):
    return [(round(float(v[0]), 6), round(float(v[1]), 6)) for v in vts]


# ------------------------------------------------- P1. the port vs PADDLE

print("== P1. the chaining port still matches PADDLE's ==")

PARITY = """
(defun tst-segs (fn / ss i out)
  (setq ss (ssget "_X" '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE"))) i 0)
  (repeat (sslength ss)
    (setq out (append out (apply fn (list (ssname ss i))))
          i   (1+ i)))
  out)
(defun tst-pp ( / ) (tst-segs 'lg:ent-segs))
(defun tst-pd ( / ) (tst-segs 'paddle--ent-segs))
(defun tst-pploops ( / ) (car (lg:chain (tst-pp))))
(defun tst-pdloops ( / ) (car (paddle--chain (tst-pd))))
(defun tst-ppopen ( / ) (length (cdr (lg:chain (tst-pp)))))
(defun tst-pdopen ( / ) (cdr (paddle--chain (tst-pd))))
"""


def parity_vm():
    vm = newvm()
    vm.load(PADDLE)
    vm.loads(PARITY)
    return vm


def flat(x):
    """Round every number in a nested list, so float noise cannot fail."""
    if isinstance(x, (int, float)) and not isinstance(x, bool):
        return round(float(x), 9)
    if isinstance(x, list):
        return [flat(i) for i in x]
    return x


for label, build in [
    ("a rectangle of loose lines",
     lambda v: rectangle(v, 0, 0, 300, 200)),
    ("lines and a 90-degree arc",
     lambda v: [line(v, (0, 0), (300, 0)),
                line(v, (300, 0), (300, 150)),
                arc(v, (250, 150), 50.0, 0.0, math.pi / 2),
                line(v, (250, 200), (0, 200)),
                line(v, (0, 200), (0, 0))]),
    ("a closed polyline with a bulge",
     lambda v: [lwpl(v, [(0, 0), (300, 0), (300, 200, -0.4142), (0, 200)])]),
    ("two loops and a stray open chain",
     lambda v: (rectangle(v, 0, 0, 300, 200)
                + rectangle(v, 100, 60, 200, 140)
                + [line(v, (400, 400), (500, 400)),
                   line(v, (500, 400), (500, 500))])),
]:
    vm = parity_vm()
    build(vm)
    mine, theirs = flat(vm.run('tst-pp', [])), flat(vm.run('tst-pd', []))
    check(f"P1 segments agree: {label}", mine == theirs,
          f"{mine} != {theirs}")
    ml, tl = flat(vm.run('tst-pploops', [])), flat(vm.run('tst-pdloops', []))
    check(f"P1 closed loops agree: {label}", ml == tl, f"{ml} != {tl}")
    mo = int(vm.run('tst-ppopen', []))
    to = int(vm.run('tst-pdopen', []))
    check(f"P1 open-chain count agrees: {label}", mo == to, f"{mo} != {to}")

# the areas have to agree too, or "which loop is outermost" would differ
vm = parity_vm()
rectangle(vm, 0, 0, 300, 200)
vm.loads("(setq tst-l (car (tst-pploops)))")
a, b = vm.loads("(lg:area tst-l)"), vm.loads("(paddle--area tst-l)")
check("P1 area agrees", round(float(a), 9) == round(float(b), 9), f"{a} {b}")


# ------------------------------------------------ P2. the outermost loop

print("== P2. the outermost loop is the perimeter ==")

vm = newvm()
rectangle(vm, 0, 0, 300, 200)          # the pool
rectangle(vm, 100, 60, 200, 140)       # the hopper, inside it
res = analyze(vm)
check("P2 a perimeter was found", res['vts'] is not None)
check("P2 it is the outer rectangle, not the hopper",
      res['vts'] is not None
      and sorted(loop_xy(res['vts']))
      == [(0.0, 0.0), (0.0, 200.0), (300.0, 0.0), (300.0, 200.0)],
      loop_xy(res['vts'] or []))
check("P2 it closed on its own", res['gap'] is None, res['gap'])

# the hopper drawn as a closed polyline rather than loose lines: still inside
vm = newvm()
rectangle(vm, 0, 0, 300, 200)
lwpl(vm, [(100, 60), (200, 60), (200, 140), (100, 140)])
res = analyze(vm)
check("P2 a closed inner polyline does not win",
      res['vts'] is not None and len(res['vts']) == 4
      and sorted(loop_xy(res['vts']))[-1] == (300.0, 200.0))

# an arc in the perimeter survives as a bulge, and only the arc has one
vm = newvm()
line(vm, (0, 0), (300, 0))
line(vm, (300, 0), (300, 150))
arc(vm, (250, 150), 50.0, 0.0, math.pi / 2)
line(vm, (250, 200), (0, 200))
line(vm, (0, 200), (0, 0))
res = analyze(vm)
bulges = [float(v[2]) for v in (res['vts'] or [])]
bent = [b for b in bulges if abs(b) > 1e-12]
check("P2 a quarter-round corner keeps its bulge, and only it",
      len(bent) == 1 and abs(bent[0] - math.tan(math.pi / 8)) < 1e-9,
      bulges)

# nothing closed and nothing close to closing
vm = newvm()
line(vm, (0, 0), (300, 0))
line(vm, (300, 0), (300, 200))
res = analyze(vm)
check("P2 an open trace with nowhere to close reports no perimeter",
      res['vts'] is None)
check("P2 ...and nothing is queued for erasing", res['kill'] == [])


# ------------------------------------------------------- P3. closing a gap

print("== P3. an almost-closed trace is shut, and says so ==")

vm = newvm()
rectangle(vm, 0, 0, 300, 200, gap=3.0)   # bottom side 3 short of the corner
res = analyze(vm)
check("P3 a 3-unit gap is closed", res['vts'] is not None)
check("P3 the gap is reported", res['gap'] is not None
      and abs(float(res['gap']) - 3.0) < 1e-9, res['gap'])

vm = newvm()
rectangle(vm, 0, 0, 300, 200, gap=24.0)  # wider than lg:*gap*
res = analyze(vm)
check("P3 a 24-unit gap is left alone", res['vts'] is None)

# a gap that closes must not beat a loop that closed itself
vm = newvm()
rectangle(vm, 0, 0, 300, 200, gap=3.0)
rectangle(vm, 500, 0, 900, 400)          # bigger, and closed
res = analyze(vm)
check("P3 a real closed loop wins over a gap that could be closed",
      res['gap'] is None and res['vts'] is not None
      and (900.0, 400.0) in loop_xy(res['vts']))


# --------------------------------------------------- P4. the keep rules

print("== P4. which dimensions survive ==")


def keepvm():
    """The full sheet: pool, hopper, dims of every style, and clutter."""
    vm = newvm()
    rectangle(vm, 0, 0, 300, 200)
    rectangle(vm, 100, 60, 200, 140)
    d = {
        'cross_long': dim(vm, "CROSS DIMENSIONS", (0, 0), (300, 200)),
        'cross_short': dim(vm, "CROSS DIM", (0, 200), (300, 0)),
        'std_perim': dim(vm, "STANDARD", (0, 0), (300, 0)),
        'std_hopper': dim(vm, "STANDARD", (100, 60), (200, 60)),
        'side_perim': dim(vm, "SIDE STANDARD", (0, 0), (0, 200)),
        'inches_perim': dim(vm, "STANDARD INCHES", (0, 0), (0, 200)),
        'radius_perim': rdim(vm, "SIDE STANDARD", (300, 100)),
        'std_halfway': dim(vm, "STANDARD", (0, 0), (150, 100)),
        'text': other(vm, 'TEXT', 'NOTES'),
        'point': other(vm, 'POINT', 'POINTS'),
        'insert': other(vm, 'INSERT', 'PADS'),
    }
    return vm, d


vm, d = keepvm()
res = analyze(vm)
kill = set(res['kill'])
check("P4 a CROSS DIMENSIONS dim across the pool is kept",
      d['cross_long'] not in kill)
check("P4 'CROSS DIM' matches the same wildcard",
      d['cross_short'] not in kill)
check("P4 STANDARD on a perimeter side is kept", d['std_perim'] not in kill)
check("P4 STANDARD across the hopper goes", d['std_hopper'] in kill)
check("P4 SIDE STANDARD on a perimeter side is kept",
      d['side_perim'] not in kill)
check("P4 STANDARD INCHES on the perimeter goes - not a kept style",
      d['inches_perim'] in kill)
check("P4 a radius dim landing on the perimeter is kept",
      d['radius_perim'] not in kill)
check("P4 a dim with only ONE end on the perimeter goes",
      d['std_halfway'] in kill)
for name in ('text', 'point', 'insert'):
    check(f"P4 the {name} goes", d[name] in kill)
check("P4 the traced geometry goes too", len(kill) == 14, len(kill))
check("P4 two kept for their style", res['nany'] == 2, res['nany'])
check("P4 three kept for sitting on the perimeter",
      res['nperim'] == 3, res['nperim'])
check("P4 eleven non-dimension objects erased",
      res['nother'] == 11, res['nother'])
check("P4 the dropped dims are counted by reason",
      res['dropped'] == {"STANDARD - not on the perimeter": 2,
                         "STANDARD INCHES - style not kept": 1},
      res['dropped'])

# a viewport is never ours to erase
vm, d = keepvm()
vp = other(vm, 'VIEWPORT', '0')
res = analyze(vm)
check("P4 a VIEWPORT is never erased", vp not in set(res['kill']))

# lg:*keeplayers* spares a layer outright
vm, d = keepvm()
vm.loads('(setq lg:*keeplayers* (list "NOTES"))')
res = analyze(vm)
check("P4 lg:*keeplayers* spares the text", d['text'] not in set(res['kill']))
check("P4 ...and counts what it spared", res['nspared'] == 1, res['nspared'])

# the styles are tunable, not baked in
vm, d = keepvm()
vm.loads('(setq lg:*perimstyles* (list "STANDARD" "SIDE STANDARD"'
         ' "STANDARD INCHES"))')
res = analyze(vm)
check("P4 adding STANDARD INCHES to lg:*perimstyles* keeps it",
      d['inches_perim'] not in set(res['kill']))

# the tolerance is what decides "on the perimeter"
vm = newvm()
rectangle(vm, 0, 0, 300, 200)
near = dim(vm, "STANDARD", (0.4, 0.0), (300, 0.0))
far = dim(vm, "STANDARD", (50.0, 4.0), (250.0, 4.0))
res = analyze(vm)
check("P4 a dim a fraction off the line is still on it",
      near not in set(res['kill']))
check("P4 a dim 4 units in from it is not, at either end",
      far in set(res['kill']))


# ------------------------------------------------------ P5. the whole run

print("== P5. the command: strip, redraw, hand over ==")

vm, d = keepvm()
vm.loads('(defun c:PADDLE ( / ) (princ "\\nSTUB-PADDLE-RAN") (princ))')
try:
    vm.run('c:LINGUTTER', [alive(vm), "Yes"])
    ran = True
except LispError as e:
    ran = False
    check("P5 c:LINGUTTER runs", False, str(e))
if ran:
    check("P5 c:LINGUTTER runs", True)
    left = alive(vm)
    check("P5 six objects are left", len(left) == 6, len(left))
    pls = alive_of(vm, 'LWPOLYLINE')
    check("P5 one of them is the new perimeter polyline", len(pls) == 1,
          len(pls))
    if pls:
        pd = dxf(vm, pls[0])
        check("P5 it is closed", pd.get(70) == 1, pd.get(70))
        check("P5 it is on POOL", pd.get(8) == "POOL", pd.get(8))
        check("P5 it is ByLayer - no colour/linetype/lineweight override",
              not any(c in pd for c in (62, 6, 370)))
        check("P5 it has the four perimeter vertices", pd.get(90) == 4,
              pd.get(90))
    kept = sorted(dxf(vm, e).get(3) for e in alive_of(vm, 'DIMENSION'))
    check("P5 the five kept dimensions are the ones analyze named",
          kept == ["CROSS DIM", "CROSS DIMENSIONS", "SIDE STANDARD",
                   "SIDE STANDARD", "STANDARD"], kept)
    out = "".join(str(x) for x in vm.printed)
    check("P5 PADDLE is handed the result", "STUB-PADDLE-RAN" in out)
    check("P5 the run is one undo group",
          [c[:2] for c in vm.commands].count(['_.UNDO', '_Begin']) == 1
          and [c[:2] for c in vm.commands].count(['_.UNDO', '_End']) == 1,
          vm.commands)
    check("P5 the user's OSMODE comes back", vm.sysvars['OSMODE'] == 4133,
          vm.sysvars['OSMODE'])
    check("P5 the report says what it kept and dropped",
          "STANDARD INCHES - style not kept" in out
          and "perimeter traced" in out)

# the redrawn perimeter reads back as the loop it was traced from
vm = newvm()
line(vm, (0, 0), (300, 0))
line(vm, (300, 0), (300, 150))
arc(vm, (250, 150), 50.0, 0.0, math.pi / 2)
line(vm, (250, 200), (0, 200))
line(vm, (0, 200), (0, 0))
vm.loads('(setq lg:*runpaddle* nil)')
before = analyze(vm)['vts']
vm.run('c:LINGUTTER', [alive(vm), "Yes"])
after = vm.loads("(lg:lwverts (ssname (ssget \"_X\" '((0 . \"LWPOLYLINE\")))"
                 " 0))")
check("P5 the redrawn polyline is closed", after[0] is not NIL)
check("P5 ...and carries the same vertices and bulges",
      flat(list(after[1:])) == flat([list(v) for v in before]),
      f"{flat(list(after[1:]))} != {flat([list(v) for v in before])}")


# ---------------------------------------------------- P6. it asks first

print("== P6. it asks before erasing, and No means no ==")

vm, d = keepvm()
vm.loads('(defun c:PADDLE ( / ) (princ "\\nSTUB-PADDLE-RAN") (princ))')
n = len(alive(vm))
vm.run('c:LINGUTTER', [alive(vm), "No"])
out = "".join(str(x) for x in vm.printed)
check("P6 No erases nothing", len(alive(vm)) == n, len(alive(vm)))
check("P6 ...and draws nothing", not alive_of(vm, 'LWPOLYLINE'))
check("P6 ...and does not run PADDLE", "STUB-PADDLE-RAN" not in out)
check("P6 the question defaults to No",
      any("<No>" in str(p[0]) for p in vm.prompts), vm.prompts)
check("P6 the bracket is the keyword list",
      any("[Yes/No]" in str(p[0]) for p in vm.prompts), vm.prompts)

# no perimeter, no question at all
vm = newvm()
line(vm, (0, 0), (300, 0))
n = len(alive(vm))
vm.run('c:LINGUTTER', [alive(vm)])
check("P6 with no perimeter it never asks", len(alive(vm)) == n)


# ------------------------------------------------------ P7. the dry run

print("== P7. LINGUTTERSCAN changes nothing ==")

vm, d = keepvm()
vm.loads('(defun c:PADDLE ( / ) (princ "\\nSTUB-PADDLE-RAN") (princ))')
n = len(alive(vm))
vm.run('c:LINGUTTERSCAN', [alive(vm)])
out = "".join(str(x) for x in vm.printed)
check("P7 nothing is erased", len(alive(vm)) == n, len(alive(vm)))
check("P7 nothing is drawn", not alive_of(vm, 'LWPOLYLINE'))
check("P7 PADDLE is not run", "STUB-PADDLE-RAN" not in out)
check("P7 it still reports the same numbers",
      "perimeter traced" in out and "STANDARD - not on the perimeter" in out)
check("P7 it asks nothing", vm.prompts and all(
    'ssget' in str(p[0]) for p in vm.prompts), vm.prompts)


# ------------------------------------------- P8. PADDLE not in the session

print("== P8. PADDLE missing is reported, not fatal ==")

vm, d = keepvm()
vm.run('c:LINGUTTER', [alive(vm), "Yes"])
out = "".join(str(x) for x in vm.printed)
check("P8 the strip still happens", len(alive_of(vm, 'LWPOLYLINE')) == 1)
check("P8 ...and it says PADDLE is not loaded",
      "PADDLE is not loaded" in out)


# ------------------------------------------- P9. only what was highlighted

print("== P9. nothing outside the highlight is read, kept or erased ==")


def twoareas():
    """The pool, and a bigger rectangle with its own clutter well away
    from it -- a title block border is exactly this shape of problem."""
    vm = newvm()
    inside = rectangle(vm, 0, 0, 300, 200) + rectangle(vm, 100, 60, 200, 140)
    inside.append(dim(vm, "STANDARD", (0, 0), (300, 0)))
    inside.append(dim(vm, "STANDARD", (100, 60), (200, 60)))
    inside.append(other(vm, 'TEXT', 'NOTES'))
    outside = rectangle(vm, 2000, 0, 4000, 3000)
    outside.append(dim(vm, "STANDARD", (2000, 0), (4000, 0)))
    outside.append(other(vm, 'TEXT', 'NOTES'))
    return vm, inside, outside


vm, inside, outside = twoareas()
vm.loads('(defun c:PADDLE ( / ) (princ "\\nSTUB-PADDLE-RAN") (princ))')
n_before = len(alive(vm))
vm.run('c:LINGUTTER', [inside, "Yes"])
left = set(alive(vm))
check("P9 the perimeter is the pool, not the bigger loop outside it",
      len(alive_of(vm, 'LWPOLYLINE')) == 1
      and dxf(vm, alive_of(vm, 'LWPOLYLINE')[0]).get(90) == 4)
if alive_of(vm, 'LWPOLYLINE'):
    xs = [g[1] for g in vm.entdata[alive_of(vm, 'LWPOLYLINE')[0]]
          if isinstance(g, list) and g[0] == 10]
    check("P9 ...and it is drawn on the pool's coordinates", max(xs) == 300.0,
          xs)
check("P9 every object outside the highlight is still there",
      all(e in left for e in outside),
      [e for e in outside if e not in left])
check("P9 the clutter inside it is gone",
      not any(e in left for e in inside if e not in (inside[8],)),
      "something highlighted survived")
# 11 highlighted: 8 traced lines, 2 dims, 1 text.  The perimeter dim
# is kept, so 10 go and the new polyline arrives -- and the 6 objects
# outside the highlight are all still standing.
check("P9 the count adds up", len(alive(vm)) == n_before - 10 + 1,
      f"{len(alive(vm))} left of {n_before}")

# the scan is scoped the same way
vm, inside, outside = twoareas()
res = analyze_sel(vm, inside)
check("P9 nothing outside the highlight is even counted",
      not any(e in set(res['kill']) for e in outside))
vmres = analyze(vm)
check("P9 ...and handed the whole drawing it would have taken the big loop",
      len(vmres['vts'] or []) == 4
      and max(float(v[0]) for v in vmres['vts']) == 4000.0)

# nothing highlighted at all
vm, d = keepvm()
n = len(alive(vm))
vm.run('c:LINGUTTER', [None, None])
out = "".join(str(x) for x in vm.printed)
check("P9 nothing highlighted, nothing gutted", len(alive(vm)) == n)
check("P9 ...and it says so", "nothing highlighted" in out, out[-200:])


# --------------------------------------- P10. the handover to PADDLE

print("== P10. PADDLE is handed the perimeter, not left to guess ==")

vm, inside, outside = twoareas()
vm.loads('(defun c:PADDLE ( / ss)'
         ' (setq ss (ssget "_I" \'((0 . "LWPOLYLINE,POLYLINE,LINE,ARC"))))'
         ' (princ (strcat "\\nSTUB-PADDLE-GOT " (if ss (itoa (sslength ss)) "0")))'
         ' (princ))')
vm.run('c:LINGUTTER', [inside, "Yes"])
out = "".join(str(x) for x in vm.printed)
check("P10 PADDLE's pickfirst probe finds exactly the new perimeter",
      "STUB-PADDLE-GOT 1" in out, out[-300:])
check("P10 ...so it never has to auto-detect past the drawing outside",
      "STUB-PADDLE-GOT 0" not in out)

# and the real PADDLE takes a pickfirst selection the same way
vm = newvm()
vm.load(PADDLE)
rectangle(vm, 0, 0, 300, 200)
vm.loads('(setq tst-ss (ssadd))')
vm.loads('(foreach e (list (ssname (ssget "_X") 0)) (ssadd e tst-ss))')
vm.loads('(sssetfirst nil tst-ss)')
got = vm.loads('(sslength (ssget "_I" \'((0 . "LWPOLYLINE,POLYLINE,LINE,ARC"))))')
check("P10 PADDLE.lsp asks for its selection with an _I probe first",
      '(ssget "_I"' in open(PADDLE).read() and int(got) == 1, got)


print()
if failures:
    print(f"{len(failures)} FAILURE(S):")
    for f in failures:
        print("  - " + f)
    sys.exit(1)
print("all LINGUTTER checks passed")
