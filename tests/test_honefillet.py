"""Runtime tests: load the real HONEFILLET.lsp into the AutoLISP VM and
drive c:HONEFILLET with scripted picks.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function, or a nil
reaching (distance ...) has to die -- and where the half-inch arithmetic
that is the whole point of the tool is checked against numbers worked
out by hand.

HONEFILLET is SMARTFILLET as far as the fan and then asks a different
question: not "which of these" but "between which two".  So the run has
THREE clicks in it where SMARTFILLET has one, and most of what is
tested here is what happens between the second and the third.

Script values answer the interactive calls in order: an entsel pick is
[entity, point] (the point matters -- it is the side of the line the
user wants kept), a getkword is the keyword string, and a callable is
run at the moment the prompt is reached, which is how a test clicks one
of the previews the command has only just drawn.

Run: python3 tests/test_honefillet.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot, Sym, NIL  # noqa: E402

ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
LSP = (os.path.join(os.path.dirname(__file__), '..', 'shared', 'parts',
                    'HONEFILLET.lsp')
       if ROOT == 'shared' else
       os.path.join(os.path.dirname(__file__), '..', 'lisp', 'honefillet',
                    'HONEFILLET.lsp'))
LIB = os.path.join(os.path.dirname(__file__), '..', 'shared', 'parts',
                   'CALOFIN-LIB.lsp')

PREVIEW_LAYER = 'HONE FILLET PREVIEW'


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


def call(vm, name, args):
    """Call one of the tool's helpers directly, with arguments."""
    fn = vm.get(Sym(name.lower()))
    if not (isinstance(fn, tuple) and fn[0] == 'defun'):
        raise AssertionError(f"{name} is not defined")
    return vm.call_defun(Sym(name.lower()), fn, list(args))


def run(vm, script, label):
    try:
        vm.run('c:HONEFILLET', list(script))
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
    resolved when the prompt is reached, because which fan is on screen
    depends on how far through the run the click comes."""
    def pick(vm):
        for e, d in alive(vm, 'ARC', PREVIEW_LAYER):
            if abs(d.get(40, 0) - radius) < 1e-6:
                c = d[10]
                return [e, [c[0] + radius, c[1], 0.0]]
        raise AssertionError(f"no preview arc at R{radius} to click")
    return pick


def watcher(into):
    """A scripted answer that photographs the fan on screen and then
    answers Enter, which every pick prompt re-asks on."""
    def look(vm):
        into['arcs'] = {round(d[40], 6): d
                        for _e, d in alive(vm, 'ARC', PREVIEW_LAYER)}
        into['labels'] = [d for _e, d in alive(vm, 'TEXT', PREVIEW_LAYER)]
        return None
    return look


def corner(vm, size=100):
    return (line(vm, (0, 0), (size, 0)), line(vm, (0, 0), (0, size)))


def picks(e1, e2):
    return [[e1, [50.0, 0.0, 0.0]], [e2, [0.0, 50.0, 0.0]]]


# ------------------------------------------------------------ the range

def test_fine_steps():
    """Half-inch steps, both ends included -- 12 to 18 is thirteen
    previews, and the last of them is 18 exactly."""
    vm = newvm()
    assert call(vm, 'hn:howfine', [12.0, 18.0]) == 13
    assert call(vm, 'hn:howfine', [3.0, 6.0]) == 7
    assert call(vm, 'hn:howfine', [12.0, 12.0]) == 1

    steps = call(vm, 'hn:finesteps', [12.0, 18.0])
    assert len(steps) == 13, steps
    assert steps[0] == 12.0 and steps[-1] == 18.0, steps
    assert steps[1] == 12.5 and steps[11] == 17.5, steps
    # counted, not accumulated: adding 0.5 twelve times is not 6.0
    assert all(abs(v - (12.0 + 0.5 * i)) < 1e-12 for i, v in enumerate(steps))

    assert call(vm, 'hn:finesteps', [9.0, 12.0]) == \
        [9.0, 9.5, 10.0, 10.5, 11.0, 11.5, 12.0]
    print("ok   the honed range: half-inch steps, both ends, no drift")


def test_whole_inches_and_halves():
    vm = newvm()
    assert call(vm, 'hn:halfp', [13.5]) is not NIL
    assert call(vm, 'hn:halfp', [13.0]) is NIL
    # the coarse fan uses a different rule, and hn:dashp picks between
    assert call(vm, 'hn:dashp', [13.5, NIL]) is NIL, \
        "13.5 is not one of the coarse fan's extras"
    assert call(vm, 'hn:dashp', [13.5, True]) is not NIL
    assert call(vm, 'hn:dashp', [9.0, NIL]) is not NIL, \
        "9 IS one of them"
    assert call(vm, 'hn:dashp', [9.0, True]) is NIL, \
        "...and is a whole inch once the fan is honed"
    assert call(vm, 'hn:rlabel', [13.5]) == 'R13.5', \
        "a half inch is lettered as one, not rounded to suit the tool"
    print("ok   whole inches solid, half inches dashed, R13.5 lettered so")


# ------------------------------------------------------------- the run

def test_full_run():
    """Bracket R12 and R18, hone, and cut the R13.5 between them."""
    vm = newvm()
    e1, e2 = corner(vm)
    coarse, fine = {}, {}
    run(vm, picks(e1, e2) + [
        watcher(coarse),
        clicker(12.0), clicker(18.0),
        watcher(fine),
        clicker(13.5),
        'No'], 'full run')

    # the coarse fan is SMARTFILLET's, and nothing is cut from it
    assert sorted(coarse['arcs']) == [3.0, 6.0, 9.0, 12.0, 18.0, 24.0,
                                      30.0, 36.0, 42.0, 48.0], \
        sorted(coarse['arcs'])
    # the honed one replaces it entirely.  watcher() photographs EVERY
    # arc on the preview layer, so this list being exactly the honed
    # range is also the proof that the coarse fan came down first -- an
    # R24 left standing would be in it
    assert sorted(fine['arcs']) == [12.0 + 0.5 * i for i in range(13)], \
        sorted(fine['arcs'])
    assert 24.0 not in fine['arcs'] and 3.0 not in fine['arcs'], \
        "the coarse fan is taken down before the honed one goes up"
    assert [t[1] for t in fine['labels']][:4] == \
        ['R12', 'R12.5', 'R13', 'R13.5'], [t[1] for t in fine['labels']]

    fil = cmds(vm, '_.FILLET')
    assert len(fil) == 1, vm.commands
    arcs = [d for _e, d in alive(vm, 'ARC') if d.get(8) != PREVIEW_LAYER]
    assert len(arcs) == 1 and abs(arcs[0][40] - 13.5) < 1e-9, \
        "the radius clicked is the FILLETRAD that reached AutoCAD"

    dims = alive(vm, 'DIMENSION')
    assert len(dims) == 1 and abs(dims[0][1][42] - 13.5) < 1e-9, dims
    assert dims[0][1][8] == 'DIMENSION'

    assert not alive(vm, layer=PREVIEW_LAYER), \
        "every preview is taken back out of the drawing"
    assert '13 corners between R12 and R18, 0.5" apart' in said(vm), said(vm)
    assert '1 corner filleted at R13.5' in said(vm), said(vm)
    print("ok   full run: coarse fan, bracket, honed fan, cut, dimension")


def test_the_honed_fan_is_drawn_like_the_coarse_one():
    """Same shades, same transparency, same labels in their own arc's
    colour -- but the solid/dashed rule is the honed one."""
    vm = newvm()
    e1, e2 = corner(vm)
    fine = {}
    run(vm, picks(e1, e2) + [clicker(12.0), clicker(18.0),
                             watcher(fine), clicker(12.0), 'No'], 'honed fan')

    rads = sorted(fine['arcs'])
    for r in rads:
        d = fine['arcs'][r]
        assert d[6] == ('DASHED' if r != int(r) else 'Continuous'), (r, d[6])
        assert d[440] == 0x02000000 + 153, (r, d[440])
    cols = [fine['arcs'][r][420] for r in rads]
    assert cols[0] == (190 << 16) + (255 << 8) + 190, cols[0]
    assert cols[-1] == (110 << 8), cols[-1]
    greens = [(c >> 8) & 0xFF for c in cols]
    assert greens == sorted(greens, reverse=True), greens
    for i, r in enumerate(rads):
        assert fine['labels'][i][420] == fine['arcs'][r][420], r

    # half an inch apart along the leg is no room at all side to side,
    # so the ladder is what has to carry this fan
    h = fine['labels'][0][40]
    assert abs(h - 3.0) < 1e-9, "and at the smaller text height"
    off = [abs(t[11][1]) for t in fine['labels'][0::2]]
    assert off == sorted(off), off
    assert min(b - a for a, b in zip(off, off[1:])) >= h, off
    print("ok   the honed fan: shaded, transparent, laddered, halves dashed")


def test_either_order():
    """The two bracket picks may come the other way round."""
    vm = newvm()
    e1, e2 = corner(vm)
    fine = {}
    run(vm, picks(e1, e2) + [clicker(18.0), clicker(12.0),
                             watcher(fine), clicker(15.5), 'No'], 'reversed')
    assert sorted(fine['arcs']) == [12.0 + 0.5 * i for i in range(13)], \
        sorted(fine['arcs'])
    assert '1 corner filleted at R15.5' in said(vm), said(vm)
    print("ok   the bracket reads the same picked high-to-low")


def test_both_ends_are_still_on_offer():
    """A round number is not taken away by the second look -- honing
    between R6 and R12 can still end at R6."""
    vm = newvm()
    e1, e2 = corner(vm)
    run(vm, picks(e1, e2) + [clicker(6.0), clicker(12.0),
                             clicker(6.0), 'No'], 'ends')
    assert '1 corner filleted at R6' in said(vm), said(vm)
    print("ok   both ends of the bracket are drawn, so neither is lost")


def test_the_same_corner_twice_is_reasked():
    vm = newvm()
    e1, e2 = corner(vm)
    run(vm, picks(e1, e2) + [clicker(12.0), clicker(12.0),
                             clicker(12.0), clicker(18.0),
                             clicker(13.0), 'No'], 'same twice')
    assert 'that is R12 twice' in said(vm), said(vm)
    assert len(cmds(vm, '_.FILLET')) == 1
    assert '1 corner filleted at R13' in said(vm), said(vm)
    print("ok   one corner clicked twice is no range, and is asked again")


def test_too_far_apart_is_reasked():
    """Not neighbours: R12 to R48 is 73 half-inch steps, which is not a
    fan anybody can read -- so it is turned down, not truncated."""
    vm = newvm()
    e1, e2 = corner(vm)
    fine = {}
    run(vm, picks(e1, e2) + [clicker(12.0), clicker(48.0),
                             clicker(12.0), clicker(18.0),
                             watcher(fine), clicker(14.0), 'No'], 'too wide')
    assert 'R12 to R48 is 73 steps of 0.5"' in said(vm), said(vm)
    assert 'pick two that sit next to each other' in said(vm), said(vm)
    assert len(fine['arcs']) == 13, "and the pair that IS neighbouring works"
    assert '1 corner filleted at R14' in said(vm), said(vm)
    print("ok   a pair too far apart is turned down rather than truncated")


def test_cancel_at_the_bracket():
    """Either of the two bracket picks abandons the run -- the second as
    much as the first, since half a bracket is no range."""
    for label, script in (('first', ['Cancel']),
                          ('second', [clicker(12.0), 'Cancel'])):
        vm = newvm()
        e1, e2 = corner(vm)
        run(vm, picks(e1, e2) + script, 'cancel at the ' + label)
        assert not cmds(vm, '_.FILLET'), (label, "nothing is cut")
        assert not alive(vm, layer=PREVIEW_LAYER), (label, "no preview left")
        assert 'the corner is as it was' in said(vm), said(vm)
    print("ok   Cancel at either bracket pick: previews go, the corner stays")


def test_repeat_at_the_honed_radius():
    """The repeats take the honed radius, and the one callout becomes
    typical -- R13.5 Typ., which is the point of honing at all."""
    vm = newvm()
    e1, e2 = corner(vm)
    e3 = line(vm, (200, 0), (300, 0))
    e4 = line(vm, (300, 0), (300, 100))
    run(vm, picks(e1, e2) + [clicker(12.0), clicker(18.0), clicker(13.5),
                             'Yes',
                             [e3, [250.0, 0.0, 0.0]],
                             [e4, [300.0, 50.0, 0.0]],
                             None], 'repeat')
    assert len(cmds(vm, '_.FILLET')) == 2, vm.commands
    assert len(alive(vm, 'DIMENSION')) == 1, "one callout for the pair"
    assert alive(vm, 'DIMENSION')[0][1][1] == '<> Typ.'
    assert '2 corners filleted at R13.5' in said(vm), said(vm)
    print("ok   repeats at the honed radius, and the Typ. re-lettering")


def test_one_size_is_nothing_to_hone_between():
    """5" legs take R3 and nothing else.  Honing wants two sizes to hone
    between, so a corner with one is turned away at the top rather than
    at a bracket prompt that could never be answered."""
    vm = newvm()
    a = line(vm, (0, 0), (5, 0))
    b = line(vm, (0, 0), (0, 5))
    run(vm, [[a, [2.0, 0.0, 0.0]], [b, [0.0, 2.0, 0.0]]], 'one size')
    assert 'Only R3 fits that corner' in said(vm), said(vm)
    assert 'no second size to hone between' in said(vm), said(vm)
    assert 'SMARTFILLET cuts it' in said(vm), said(vm)
    assert not cmds(vm, '_.FILLET')
    assert not alive(vm, layer=PREVIEW_LAYER), \
        "and no fan is flashed up to be taken straight down again"
    print("ok   one size that fits is nothing to hone between, and says so")


def test_no_corner_and_no_room():
    vm = newvm()
    e1 = line(vm, (0, 0), (100, 0))
    e2 = line(vm, (0, 20), (100, 20))
    run(vm, [[e1, [50.0, 0.0, 0.0]], [e2, [50.0, 20.0, 0.0]]], 'parallel')
    assert 'make no corner' in said(vm), said(vm)
    assert not cmds(vm, '_.FILLET')

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
    assert 'HONEFILLET cancelled' in said(vm), said(vm)
    print("ok   Enter at the first prompt cancels and says so")


def test_settings_go_back():
    vm = newvm(styles=('STANDARD INCHES',))
    vm.sysvars['OSMODE'] = 39
    vm.sysvars['CLAYER'] = 'POOL'
    vm.sysvars['FILLETRAD'] = 3.0
    vm.sysvars['TRIMMODE'] = 0
    e1, e2 = corner(vm)
    run(vm, picks(e1, e2) + [clicker(18.0), clicker(24.0),
                             clicker(19.5), 'No'], 'sysvars')
    assert vm.sysvars['OSMODE'] == 39, vm.sysvars
    assert vm.sysvars['CLAYER'] == 'POOL', vm.sysvars
    assert vm.sysvars['FILLETRAD'] == 3.0, vm.sysvars
    assert vm.sysvars['TRIMMODE'] == 0, vm.sysvars
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars
    print("ok   OSMODE, CLAYER, FILLETRAD, TRIMMODE and the dim style go back")


def test_version_banner():
    vm = newvm()
    vm.run('c:HONEFILLETVER', [])
    assert 'HONEFILLET v' in said(vm), said(vm)
    print("ok   the version reporter answers")


TESTS = [test_fine_steps, test_whole_inches_and_halves, test_full_run,
         test_the_honed_fan_is_drawn_like_the_coarse_one, test_either_order,
         test_both_ends_are_still_on_offer,
         test_the_same_corner_twice_is_reasked, test_too_far_apart_is_reasked,
         test_cancel_at_the_bracket, test_repeat_at_the_honed_radius,
         test_one_size_is_nothing_to_hone_between,
         test_no_corner_and_no_room, test_first_prompt_can_be_cancelled,
         test_settings_go_back, test_version_banner]


def main():
    print(f"HONEFILLET runtime tests ({ROOT} tier)")
    for t in TESTS:
        t()
    print(f"\nall {len(TESTS)} HONEFILLET tests passed")
    return 0


if __name__ == '__main__':
    sys.exit(main())
