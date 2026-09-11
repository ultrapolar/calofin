"""Runtime tests: load the real SMARTFILLET.lsp into the AutoLISP VM and
drive c:SMARTFILLET with scripted picks.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function, or a nil
reaching (distance ...) has to die -- and where the geometry that
decides which radii fit a corner is checked against numbers worked out
by hand.

Script values answer the interactive calls in order: an entsel pick is
[entity, point] (the point matters -- it is the side of the line the
user wants kept), a getkword is the keyword string, and a callable is
run at the moment the prompt is reached, which is how a test clicks one
of the previews the command has only just drawn.

Run: python3 tests/test_smartfillet.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot, Sym, NIL  # noqa: E402

ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
LSP = (os.path.join(os.path.dirname(__file__), '..', 'shared', 'parts',
                    'SMARTFILLET.lsp')
       if ROOT == 'shared' else
       os.path.join(os.path.dirname(__file__), '..', 'lisp', 'smartfillet',
                    'SMARTFILLET.lsp'))
LIB = os.path.join(os.path.dirname(__file__), '..', 'shared', 'parts',
                   'CALOFIN-LIB.lsp')

PREVIEW_LAYER = 'SMART FILLET PREVIEW'


# ---------------------------------------------------------------- setup

def newvm(styles=(), layers=('POOL',)):
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(LSP)
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    for lay in layers:
        vm.tables['LAYER'].add(lay)
    vm.sysvars['CLAYER'] = layers[0] if layers else '0'
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    return vm


def line(vm, p1, p2, layer='POOL'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'LINE'), Dot(8, layer),
                     [10] + [float(v) for v in p1] + [0.0][:3 - len(p1)],
                     [11] + [float(v) for v in p2] + [0.0][:3 - len(p2)]]
    return e


def pline(vm, layer='POOL'):
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'LWPOLYLINE'), Dot(8, layer), [10, 0.0, 0.0, 0.0]]
    return e


def call(vm, name, args):
    """Call one of the tool's helpers directly, with arguments."""
    fn = vm.get(Sym(name.lower()))
    if not (isinstance(fn, tuple) and fn[0] == 'defun'):
        raise AssertionError(f"{name} is not defined")
    return vm.call_defun(Sym(name.lower()), fn, list(args))


def run(vm, script, label):
    try:
        vm.run('c:SMARTFILLET', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def said(vm):
    return ''.join(vm.printed)


def alive(vm, etype=None, layer=None):
    """Every entity still in the drawing, optionally of one type/layer."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for g in vm.entdata[e]:
            if isinstance(g, Dot):
                d.setdefault(g.a, g.b)
            elif isinstance(g, list) and g:
                d.setdefault(g[0], list(g[1:]))
        if etype and d.get(0) != etype:
            continue
        if layer and d.get(8) != layer:
            continue
        out.append((e, d))
    return out


def cmds(vm, name):
    return [c for c in vm.commands if c and c[0] == name]


def clicker(radius):
    """A scripted answer that clicks the preview arc of that radius --
    resolved when the prompt is reached, because the arc does not exist
    until the command has drawn it."""
    def pick(vm):
        for e, d in alive(vm, 'ARC', PREVIEW_LAYER):
            if abs(d.get(40, 0) - radius) < 1e-6:
                c = d[10]
                return [e, [c[0] + radius, c[1], 0.0]]
        raise AssertionError(f"no preview arc at R{radius} to click")
    return pick


# ------------------------------------------------------------- geometry

def test_corner_geometry():
    """A square corner: both legs 100 long, so a fillet may grow until
    its tangent point runs off the shorter one."""
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    geo = call(vm, 'sf:corner', [e1, [50.0, 0.0], e2, [0.0, 50.0]])
    assert geo, "a right-angle corner has to come back as a corner"
    x, u1, av1, u2, av2, half = geo
    assert abs(x[0]) < 1e-9 and abs(x[1]) < 1e-9, x
    assert abs(u1[0] - 1.0) < 1e-9 and abs(u1[1]) < 1e-9, u1
    assert abs(u2[1] - 1.0) < 1e-9 and abs(u2[0]) < 1e-9, u2
    assert abs(av1 - 100.0) < 1e-9 and abs(av2 - 100.0) < 1e-9, (av1, av2)
    assert abs(half - math.pi / 4) < 1e-9, half
    # tangent length is r/tan(45) = r, so the fillet reaches 98 with
    # sf:*fit* holding it clear of the far end
    assert abs(call(vm, 'sf:rmax', [geo]) - 98.0) < 1e-9

    # the pick decides which half of a crossing line survives
    e3 = line(vm, (-100, 0), (100, 0))
    west = call(vm, 'sf:corner', [e3, [-50.0, 0.0], e2, [0.0, 50.0]])
    assert abs(west[1][0] + 1.0) < 1e-9, "clicking west keeps the west leg"
    east = call(vm, 'sf:corner', [e3, [50.0, 0.0], e2, [0.0, 50.0]])
    assert abs(east[1][0] - 1.0) < 1e-9, "clicking east keeps the east leg"
    print("ok   corner geometry: crossing point, kept sides, half angle")


def test_short_leg_caps_the_radius():
    """The SHORTER leg sets the limit, and a 45-degree corner reaches
    further than a square one for the same leg."""
    vm = newvm()
    e1 = line(vm, (0, 0), (30, 0))
    e2 = line(vm, (0, 0), (0, 100))
    geo = call(vm, 'sf:corner', [e1, [15.0, 0.0], e2, [0.0, 50.0]])
    assert abs(call(vm, 'sf:rmax', [geo]) - 29.4) < 1e-9

    # legs 45 degrees apart: tan(22.5) = 0.41421, so the same 30" leg
    # only carries a 12-and-a-bit radius
    e3 = line(vm, (0, 0), (30 / math.sqrt(2), 30 / math.sqrt(2)))
    geo = call(vm, 'sf:corner', [e1, [15.0, 0.0], e3, [10.0, 10.0]])
    assert abs(call(vm, 'sf:rmax', [geo]) - 0.98 * 30 * 0.4142135) < 1e-4
    print("ok   the shorter leg and the turn between them cap the radius")


def test_candidates_and_arc():
    vm = newvm()
    assert call(vm, 'sf:candidates', [98.0]) == [3.0, 6.0, 9.0, 12.0, 18.0,
                                                 24.0, 30.0, 36.0, 42.0,
                                                 48.0], \
        "10 previews at most: the 6s, with the two extras merged in"
    assert call(vm, 'sf:howmany', [98.0]) == 18, \
        "16 sixes and 2 extras really fit -- the cap must know what it hid"
    assert call(vm, 'sf:candidates', [17.0]) == [3.0, 6.0, 9.0, 12.0]
    assert call(vm, 'sf:candidates', [5.0]) == [3.0], \
        "the 3 is the whole reason a 5-inch corner is not a dead end"
    assert call(vm, 'sf:candidates', [2.0]) is NIL, \
        "nothing fits under 3 -- and nil is the empty list"
    assert abs(call(vm, 'sf:smallest', []) - 3.0) < 1e-9, \
        "the smallest on offer is an extra, not sf:*first*"

    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    geo = call(vm, 'sf:corner', [e1, [50.0, 0.0], e2, [0.0, 50.0]])
    c, t1, t2 = call(vm, 'sf:arcpts', [geo, 24.0])
    assert abs(c[0] - 24.0) < 1e-9 and abs(c[1] - 24.0) < 1e-9, c
    assert abs(t1[0] - 24.0) < 1e-9 and abs(t1[1]) < 1e-9, t1
    assert abs(t2[1] - 24.0) < 1e-9 and abs(t2[0]) < 1e-9, t2
    # the arc really is tangent: centre to either tangent point is r
    assert abs(math.dist(c[:2], t1[:2]) - 24.0) < 1e-9
    assert abs(math.dist(c[:2], t2[:2]) - 24.0) < 1e-9
    print("ok   candidate radii, the cap, and the arc they describe")


# ------------------------------------------------------------- the run

def test_full_run():
    """Two lines, click R24, and the corner is cut and dimensioned."""
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    run(vm, [[e1, [50.0, 0.0, 0.0]],
             [e2, [0.0, 50.0, 0.0]],
             clicker(24.0),
             'No'], 'full run')

    fil = cmds(vm, '_.FILLET')
    assert len(fil) == 1, vm.commands
    assert fil[0][1][0] is e1 and fil[0][2][0] is e2, fil[0]
    arcs = [d for e, d in alive(vm, 'ARC') if d.get(8) != PREVIEW_LAYER]
    assert len(arcs) == 1 and abs(arcs[0][40] - 24.0) < 1e-9, \
        "the radius clicked is the FILLETRAD that reached AutoCAD"

    dims = alive(vm, 'DIMENSION')
    assert len(dims) == 1, "the corner it cut gets its radius dimension"
    d = dims[0][1]
    assert d[8] == 'DIMENSION', "and it goes on the DIMENSION layer"
    assert abs(d[42] - 24.0) < 1e-9
    # The dim is hung off the arc at the point where the bisector
    # leaves it, with the text a radius further out along that same
    # line -- the one direction clear of both legs.  Measured from the
    # centre a 24" fillet really has here, (24,24), not from the arc
    # the VM leaves behind (its centre is a stand-in; see _command).
    ctr = (24.0, 24.0)
    assert abs(math.dist(d[15][:2], ctr) - 24.0) < 1e-6, d[15]
    assert abs(math.dist(d[11][:2], ctr) - 48.0) < 1e-6, d[11]
    assert d[15][0] < ctr[0] and abs(d[15][0] - d[15][1]) < 1e-9, d[15]
    assert d[11][0] < 0.0 and abs(d[11][0] - d[11][1]) < 1e-9, d[11]

    assert not alive(vm, layer=PREVIEW_LAYER), \
        "every preview is taken back out of the drawing"
    assert '1 corner filleted at R24' in said(vm), said(vm)
    assert 'Typ.' not in said(vm), "one corner is not typical of anything"
    print("ok   full run: preview, click, fillet, dimension, clean up")


def watch_fan(vm, e1, e2, extra=(), label='previews'):
    """Run the command over the corner e1/e2 and hand back what the fan
    looked like at the moment the pick prompt was reached: {'arcs': by
    radius, 'labels': in the order they were drawn}.

    The two are kept apart rather than sharing one dict -- a dict of
    float radii with a 'labels' string key beside them cannot be sorted,
    so the one thing a failing assertion needs to print is the one thing
    that would raise instead."""
    seen = {'arcs': {}, 'labels': []}

    def look(vm_):
        seen['arcs'] = {round(d[40], 6): d
                        for _e, d in alive(vm_, 'ARC', PREVIEW_LAYER)}
        seen['labels'] = [d for _e, d in alive(vm_, 'TEXT', PREVIEW_LAYER)]
        return None                      # Enter = re-ask, then the click

    run(vm, [[e1, [50.0, 0.0, 0.0]],
             [e2, [0.0, 50.0, 0.0]],
             look] + list(extra), label)
    return seen


def test_previews_drawn_and_capped():
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    seen = watch_fan(vm, e1, e2, extra=[clicker(6.0), 'No'])

    assert sorted(seen['arcs']) == \
        [3.0, 6.0, 9.0, 12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0], \
        sorted(seen['arcs'])
    assert [t[1] for t in seen['labels']] == \
        ['R3', 'R6', 'R9', 'R12', 'R18', 'R24', 'R30', 'R36', 'R42', 'R48'], \
        [t[1] for t in seen['labels']]
    # every other label goes on the other leg, or consecutive ones would
    # sit on top of each other
    ys = [t[11][1] for t in seen['labels']]
    assert ys[0] < 1.0 and ys[1] > 1.0, ys
    assert '10 corners that fit, light to dark: R3 to R48' in said(vm), said(vm)
    assert 'Dashed: R3 and R9' in said(vm), said(vm)
    assert '8 larger radii also fit' in said(vm), said(vm)
    assert 'nothing there' in said(vm), \
        "Enter at the pick re-asks -- a near miss must not cost the fan"
    print("ok   previews: the whole fan, labelled, alternating, capped out loud")


def test_the_odd_sizes_are_dashed():
    """The 6" series is solid and the two extras are dashed -- which is
    the fan saying which sizes are the usual step."""
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    seen = watch_fan(vm, e1, e2, extra=[clicker(6.0), 'No'], label='dashes')

    arcs = seen['arcs']
    for r in (3.0, 9.0):
        assert arcs[r][6] == 'DASHED', (r, arcs[r][6])
        assert abs(arcs[r].get(48, 0) - 0.25) < 1e-9, \
            "and dashed at a scale that puts real gaps in a short arc"
    for r in (6.0, 12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0):
        assert arcs[r][6] == 'Continuous', (r, arcs[r][6])
        assert 48 not in arcs[r], \
            "a solid arc carries no linetype scale to argue with"
    print("ok   the 3 and the 9 come out dashed, the 6s solid")


def test_shades_and_transparency():
    """Light green at the small end, dark at the big one, every arc part
    transparent, and each label in ITS OWN arc's shade."""
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    seen = watch_fan(vm, e1, e2, extra=[clicker(6.0), 'No'], label='shades')

    arcs = seen['arcs']
    rads = sorted(arcs)
    cols = [arcs[r].get(420) for r in rads]
    assert cols[0] == (190 << 16) + (255 << 8) + 190, cols[0]
    assert cols[-1] == (110 << 8), cols[-1]
    greens = [(c >> 8) & 0xFF for c in cols]
    assert greens == sorted(greens, reverse=True), greens
    assert len(set(cols)) == len(cols), "no two previews share a shade"

    # 40 per cent transparent: 0x02000000 flags the word and the low byte
    # is the ALPHA, so the per cent has to be turned round
    for r in rads:
        assert arcs[r].get(440) == 0x02000000 + 153, (r, arcs[r].get(440))
        assert arcs[r][62] == 3, \
            "and the ACI fallback stays on, for a display without 420"

    # a label is drawn in its own arc's colour -- that is what ties the
    # two together once ten of them are on screen at once
    for i, r in enumerate(rads):
        assert seen['labels'][i].get(420) == arcs[r].get(420), (r, i)
        assert seen['labels'][i].get(440) == arcs[r].get(440), (r, i)
    print("ok   shades run light to dark, transparent, labels matching")


def test_labels_never_overlap():
    """Each label climbs a rung further off its leg than the one before
    it on that side, so no two can land on each other."""
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    seen = watch_fan(vm, e1, e2, extra=[clicker(6.0), 'No'], label='ladder')

    labels = seen['labels']
    h = labels[0][40]
    assert abs(h - 4.0) < 1e-9, "and it is the smaller text height now"
    # "R48" at height h is about 3 * 0.7 * h wide, centre-justified
    def wide(t):
        return 0.7 * h * len(t[1])
    boxes = [(t[11][0], t[11][1], wide(t)) for t in labels]
    for i, a in enumerate(boxes):
        for b in boxes[i + 1:]:
            apart = (abs(a[0] - b[0]) >= 0.5 * (a[2] + b[2])
                     or abs(a[1] - b[1]) >= h)
            assert apart, (labels[i][1], a, b)
    # the ladder is real: consecutive labels on ONE leg step away from it
    off = [abs(t[11][1]) for t in labels[0::2]]        # the x-axis leg
    assert off == sorted(off), off
    assert min(b - a for a, b in zip(off, off[1:])) >= h, off
    print("ok   the label ladder: ten labels, no two touching")


def test_repeat_at_the_same_radius():
    """Yes to the second question fillets more corners at that radius,
    and the one dimension becomes typical."""
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    e3 = line(vm, (200, 0), (300, 0))
    e4 = line(vm, (300, 0), (300, 100))
    short = line(vm, (500, 0), (505, 0))
    short2 = line(vm, (500, 0), (500, 5))

    run(vm, [[e1, [50.0, 0.0, 0.0]],
             [e2, [0.0, 50.0, 0.0]],
             clicker(12.0),
             'Yes',
             [short, [502.0, 0.0, 0.0]],       # too small to take R12
             [short2, [500.0, 2.0, 0.0]],
             [e3, [250.0, 0.0, 0.0]],          # this one fits
             [e4, [300.0, 50.0, 0.0]],
             None], 'repeat')                  # Enter = Done

    assert len(cmds(vm, '_.FILLET')) == 2, "the short corner is left alone"
    assert 'too short a corner for R12' in said(vm), said(vm)
    assert len(alive(vm, 'DIMENSION')) == 1, \
        "one callout for the pair, not one each"
    assert alive(vm, 'DIMENSION')[0][1][1] == '<> Typ.', \
        "and it is re-lettered typical once a repeat is cut"
    assert '2 corners filleted at R12' in said(vm), said(vm)
    print("ok   repeats at the found radius, and the Typ. re-lettering")


def test_cancel_leaves_the_drawing_alone():
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    run(vm, [[e1, [50.0, 0.0, 0.0]],
             [e2, [0.0, 50.0, 0.0]],
             'Cancel'], 'cancel')
    assert not cmds(vm, '_.FILLET'), "nothing is cut"
    assert not alive(vm, layer=PREVIEW_LAYER), "and no preview is left"
    assert 'the corner is as it was' in said(vm), said(vm)
    print("ok   Cancel at the pick: previews go, the corner stays")


def test_bad_picks_reask():
    """A polyline and the same line twice are told about, not filleted."""
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    lw = pline(vm)
    run(vm, [[lw, [1.0, 1.0, 0.0]],
             [e1, [50.0, 0.0, 0.0]],
             [e1, [60.0, 0.0, 0.0]],
             [e2, [0.0, 50.0, 0.0]],
             clicker(6.0),
             'No'], 'bad picks')
    assert 'that is a LWPOLYLINE' in said(vm), said(vm)
    assert 'click the OTHER leg' in said(vm), said(vm)
    assert len(cmds(vm, '_.FILLET')) == 1
    print("ok   a polyline and a repeated pick are re-asked, not filleted")


def test_no_corner_and_no_room():
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 20), (100, 20))
    run(vm, [[e1, [50.0, 0.0, 0.0]], [e2, [50.0, 20.0, 0.0]]], 'parallel')
    assert 'make no corner' in said(vm), said(vm)
    assert not cmds(vm, '_.FILLET')

    # 4" legs would once have been too short; the 3" extra means the
    # floor is R3 now, and a corner is only a dead end under THAT
    vm = newvm()
    a = line(vm, (0, 0), (4, 0))
    b = line(vm, (0, 0), (0, 4))
    run(vm, [[a, [2.0, 0.0, 0.0]], [b, [0.0, 2.0, 0.0]],
             clicker(3.0), 'No'], 'small but not too small')
    assert len(cmds(vm, '_.FILLET')) == 1, "R3 fits a 4-inch leg"

    vm = newvm()
    a = line(vm, (0, 0), (2, 0))
    b = line(vm, (0, 0), (0, 2))
    run(vm, [[a, [1.0, 0.0, 0.0]], [b, [0.0, 1.0, 0.0]]], 'no room')
    assert 'less than the smallest preview (R3)' in said(vm), said(vm)
    assert not alive(vm, layer=PREVIEW_LAYER)
    print("ok   parallel lines and a corner too small to round")


def test_first_prompt_can_be_cancelled():
    vm = newvm()
    line(vm, (0, 0), (100, 0))
    run(vm, [None], 'enter at the first prompt')
    assert 'SMARTFILLET cancelled' in said(vm), said(vm)
    print("ok   Enter at the first prompt cancels and says so")


def test_settings_go_back():
    vm = newvm(styles=('STANDARD INCHES',))
    vm.sysvars['OSMODE'] = 39
    vm.sysvars['CLAYER'] = 'POOL'
    vm.sysvars['FILLETRAD'] = 3.0
    vm.sysvars['TRIMMODE'] = 0
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 0), (0, 100))
    run(vm, [[e1, [50.0, 0.0, 0.0]],
             [e2, [0.0, 50.0, 0.0]],
             clicker(18.0),
             'No'], 'sysvars')
    assert vm.sysvars['OSMODE'] == 39, vm.sysvars
    assert vm.sysvars['CLAYER'] == 'POOL', vm.sysvars
    assert vm.sysvars['FILLETRAD'] == 3.0, vm.sysvars
    assert vm.sysvars['TRIMMODE'] == 0, vm.sysvars
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars
    # under sf:*smalldim* the callout borrows POOL's small-dim style
    assert vm.dimstyle_log[:1] == ['STANDARD INCHES'], vm.dimstyle_log
    assert vm.dimstyle_log[-1] == 'STANDARD', vm.dimstyle_log
    print("ok   OSMODE, CLAYER, FILLETRAD, TRIMMODE and the dim style go back")


def test_version_banner():
    vm = newvm()
    vm.run('c:SMARTFILLETVER', [])
    assert 'SMARTFILLET v' in said(vm), said(vm)
    print("ok   the version reporter answers")


TESTS = [test_corner_geometry, test_short_leg_caps_the_radius,
         test_candidates_and_arc, test_full_run,
         test_previews_drawn_and_capped, test_the_odd_sizes_are_dashed,
         test_shades_and_transparency, test_labels_never_overlap,
         test_repeat_at_the_same_radius,
         test_cancel_leaves_the_drawing_alone, test_bad_picks_reask,
         test_no_corner_and_no_room, test_first_prompt_can_be_cancelled,
         test_settings_go_back, test_version_banner]


def main():
    print(f"SMARTFILLET runtime tests ({ROOT} tier)")
    for t in TESTS:
        t()
    print(f"\nall {len(TESTS)} SMARTFILLET tests passed")
    return 0


if __name__ == '__main__':
    sys.exit(main())
