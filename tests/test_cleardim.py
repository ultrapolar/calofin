"""Drive the REAL CLEARDIM.lsp in the AutoLISP VM, against drawings
built by entmake with crowded dimension text planted in them.

Three layers of it, because the tool has three:

  * the GEOMETRY -- the rotated text box, the separating-axis clash
    test, the glyph count that sizes a box from a string.  These are
    pure functions and are called directly;
  * the POLICY -- who keeps their spot and who gives way.  Every
    arrangement below is a real drawing rather than a hand-built
    record, because the awkward ones turned out to be buildable: the
    trick is stacking a horizontal dimension over another whose own
    dimension line is far enough away not to be ink in its own right;
  * the COMMANDS -- CLEARDIM and CLEARDIMSCAN end to end, through
    ssget, entmod and the undo group, on drawings entmade here.

Script values answer the interactive calls in order.  cd:asksel asks
ssget four times and only ever reaches one of them: "_I" for a
pickfirst set, the interactive sweep, then two "_X" fallbacks the VM
answers from the database itself.  So a run that takes Enter for the
whole drawing is scripted [None, None] -- nothing pre-picked, Enter at
the sweep -- and one handed a selection is scripted [None, [ents]].

Run: python3 tests/test_cleardim.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_cleardim.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot, Ent, NIL  # noqa: E402

HERE = os.path.dirname(__file__)
# lispvm's _remap_root sends this to shared/parts/ when
# CALOFIN_LISP_ROOT=shared, the way every other runtime suite's path does
LSP = os.path.join(HERE, '..', 'lisp', 'cleardim', 'CLEARDIM.lsp')

TXT = 4.5          # the fixture dimstyle's DIMTXT, at DIMSCALE 1
EXE = 1.5          # and its DIMEXE
CW = 0.75          # cd:*charwidth*, for working out an expected width
GAPF = 0.4         # cd:*gap-f*


# ------------------------------------------------------------------
# fixtures
# ------------------------------------------------------------------

def newvm(txt=TXT, scale=1.0, exe=EXE):
    """A VM with CLEARDIM loaded and a DIMSTYLE record that carries a
    real text height.  The record is installed straight into the VM's
    symbol table rather than entmade: entmake has no branch for a
    DIMSTYLE, so an entmade one would land in model space and turn up
    in the next (ssget "_X") -- and tblsearch would still not find its
    140 group."""
    vm = VM()
    vm.load(LSP)
    rec = Ent()
    vm.recdata[rec] = [Dot(0, 'DIMSTYLE'), Dot(2, 'STANDARD'),
                       Dot(140, txt), Dot(40, scale), Dot(44, exe)]
    vm.tables.setdefault('DIMSTYLE', set()).add('STANDARD')
    vm.tablerecs.setdefault('DIMSTYLE', {})['STANDARD'] = rec
    return vm


def dim(vm, p13, p14, p10, p11=None, text='', layer='0', flags=0, ang=0.0):
    """A DIMENSION straight into the database.  FLAGS is group 70, so 0
    is rotated/linear and 1 aligned; P11 left out is the dimension whose
    text has never been dragged, which is most of them."""
    g11 = '' if p11 is None else ' (list 11 %r %r 0.0)' % (p11[0], p11[1])
    vm.loads('(entmakex (list (cons 0 "DIMENSION") (cons 8 "%s")'
             ' (cons 3 "STANDARD") (cons 70 %d) (cons 50 %r)'
             ' (list 13 %r %r 0.0) (list 14 %r %r 0.0) (list 10 %r %r 0.0)%s'
             ' (cons 1 "%s")))'
             % (layer, flags, ang, p13[0], p13[1], p14[0], p14[1],
                p10[0], p10[1], g11, text))
    return vm.entities[-1]


def line(vm, a, b, layer='0'):
    vm.loads('(entmakex (list (cons 0 "LINE") (cons 8 "%s")'
             ' (list 10 %r %r 0.0) (list 11 %r %r 0.0)))'
             % (layer, a[0], a[1], b[0], b[1]))
    return vm.entities[-1]


def layer(vm, name, flags=0):
    vm.tables['LAYER'].add(name)
    vm.loads('(entmake (list (cons 0 "LAYER") (cons 2 "%s") (cons 70 %d)'
             ' (cons 62 7)))' % (name, flags))


def grp(vm, e, code):
    """First DXF group value on an entity, None when absent."""
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


def p11(vm, e):
    v = grp(vm, e, 11)
    return None if v is None else (round(v[0], 6), round(v[1], 6))


def run(vm, cmd, script, label):
    try:
        vm.run(cmd, list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def said(vm):
    return ''.join(vm.printed)


def plan(vm):
    """The whole analysis over everything in the drawing, as Python."""
    vm.loads('(setq SS (ssget "_X"))')
    vm.loads('(setq RECS (cd:records SS))')
    vm.loads('(setq STATIC (cd:static-obs SS RECS))')
    return vm.loads('(cd:plan RECS STATIC)')


def box_w(text, hgt=TXT):
    return len(text) * hgt * CW


# ------------------------------------------------------------------
# the geometry
# ------------------------------------------------------------------

def test_box_is_centred_on_its_point():
    vm = newvm()
    b = vm.loads('(cd:box (list 10.0 20.0) 0.0 8.0 4.0)')
    xs = sorted(round(p[0], 6) for p in b)
    ys = sorted(round(p[1], 6) for p in b)
    assert xs == [6.0, 6.0, 14.0, 14.0], xs
    assert ys == [18.0, 18.0, 22.0, 22.0], ys
    # turned 90 degrees, width and height trade places
    b = vm.loads('(cd:box (list 0.0 0.0) %r 8.0 4.0)' % (math.pi / 2))
    xs = sorted(round(p[0], 6) for p in b)
    ys = sorted(round(p[1], 6) for p in b)
    assert xs == [-2.0, -2.0, 2.0, 2.0], xs
    assert ys == [-4.0, -4.0, 4.0, 4.0], ys
    print("ok  box          -> centred on its point, turned by its angle")


def test_segment_against_box():
    vm = newvm()
    vm.loads('(setq B (cd:box (list 0.0 0.0) 0.0 10.0 4.0))')

    def hit(a, b):
        return vm.loads('(cd:hit-p B (list (list %r %r) (list %r %r)))'
                        % (a[0], a[1], b[0], b[1])) is not NIL

    assert hit((0, -10), (0, 10)), "a segment straight through it misses?"
    assert hit((-20, 0), (20, 0)), "a segment along its axis misses?"
    assert not hit((0, 3), (20, 3)), "a segment clear above it hits?"
    assert not hit((6, -10), (6, 10)), "a segment clear beside it hits?"
    # touching exactly is not overlapping: that is what lets a text sit
    # flush against the line it has just cleared
    assert not hit((5, -10), (5, 10)), "a segment grazing its edge hits?"
    # the axis a segment contributes is its own: a diagonal that clears
    # both of the box's own axes still has to be caught
    assert hit((-8, 4), (8, -4)), "a diagonal through the middle misses?"
    print("ok  clash        -> segment vs box, touching is not overlapping")


def test_box_against_box():
    vm = newvm()
    vm.loads('(setq A (cd:box (list 0.0 0.0) 0.0 10.0 4.0))')
    assert vm.loads('(cd:hit-p A (cd:box (list 8.0 0.0) 0.0 10.0 4.0))') \
        is not NIL
    assert vm.loads('(cd:hit-p A (cd:box (list 12.0 0.0) 0.0 10.0 4.0))') \
        is NIL
    # one turned: the diagonal reaches where the upright one did not
    assert vm.loads('(cd:hit-p A (cd:box (list 0.0 6.0) %r 10.0 4.0))'
                    % (math.pi / 2)) is not NIL
    print("ok  clash        -> box vs box both ways round")


def test_glyph_count_reads_control_codes():
    vm = newvm()
    assert vm.loads('(cd:glyphs "1234")') == 4
    # "%%d" is one glyph written as three characters; counting the
    # characters would make every box with a degree sign in it two
    # glyphs too wide
    assert vm.loads('(cd:glyphs "90%%d")') == 3
    assert vm.loads('(cd:glyphs "%%c12")') == 3
    # the overscore/underscore toggles draw nothing at all
    assert vm.loads('(cd:glyphs "%%u12%%u")') == 2
    print("ok  glyphs       -> %%d is one glyph, %%u is none")


def test_text_size_splits_hard_line_breaks():
    vm = newvm()
    one = vm.loads('(cd:text-size "ABCD" 4.0)')
    assert abs(one[0] - 4 * 4.0 * CW) < 1e-9, one
    assert abs(one[1] - 4.0) < 1e-9, one
    two = vm.loads('(cd:text-size "ABCD\\\\PEF" 4.0)')
    # the widest line decides the width, and a second line is another
    # line and a half of height
    assert abs(two[0] - 4 * 4.0 * CW) < 1e-9, two
    assert abs(two[1] - 4.0 * 2.5) < 1e-9, two
    print("ok  text size    -> widest line wide, one line and a half tall")


# ------------------------------------------------------------------
# reading a dimension
# ------------------------------------------------------------------

def test_track_of_a_rotated_dimension():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    r = vm.loads('(cd:read-dim 0 (entlast))')
    assert r[2] == 0, r                                   # rotated
    assert [round(x, 6) for x in r[4]] == [1.0, 0.0], r    # track along X
    assert abs(r[5] - 50.0) < 1e-9, r                     # 50 along it
    assert [round(x, 6) for x in r[6]] == [0.0, 6.0], r   # 6 above it
    assert abs(r[8] - box_w('A-TEXT')) < 1e-9, r
    assert abs(r[9] - TXT) < 1e-9, r
    assert r[11] is NIL, "a plain linear dimension cannot slide?"
    print("ok  track        -> a rotated dim's track is its own dim line")


def test_track_of_an_aligned_dimension():
    vm = newvm()
    dim(vm, (0, 0), (100, 100), (0, 20), None, text='DIAG', flags=1)
    r = vm.loads('(cd:read-dim 0 (entlast))')
    assert r[2] == 1, r
    u = [round(x, 6) for x in r[4]]
    assert u == [round(math.sqrt(0.5), 6)] * 2, u
    # with no stored text point the text sits at the middle of the
    # dimension line, half its own height clear of it
    off = math.hypot(r[6][0], r[6][1])
    assert abs(off - TXT / 2.0) < 1e-6, r[6]
    print("ok  track        -> an aligned dim's track runs 13 to 14")


def test_own_segments_are_the_dim_line_then_the_extension_lines():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    own = vm.loads('(cd:r-own (cd:read-dim 0 (entlast)))')
    assert len(own) == 3, own
    # the dimension line first -- it is the one thing the dimension
    # never has to clear, so its place in the list is load-bearing
    assert [round(v, 6) for v in own[0][0]] == [0.0, 20.0], own
    assert [round(v, 6) for v in own[0][1]] == [100.0, 20.0], own
    # then an extension line per definition point, run DIMEXE past the
    # dimension line
    assert [round(v, 6) for v in own[1][1]] == [0.0, 20.0 + EXE], own
    assert [round(v, 6) for v in own[2][1]] == [100.0, 20.0 + EXE], own
    print("ok  own ink      -> dim line first, then the extension lines")


def test_text_override_expands_the_measurement_marker():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='TYP <> LONG')
    ed = vm.loads('(entget (entlast))')
    s = vm.loads('(cd:dim-text (entget (entlast)))')
    assert '<>' not in s, s
    assert s.startswith('TYP ') and s.endswith(' LONG'), s
    assert vm.loads('(cd:dim-meas (entget (entlast)))') in s, s
    assert ed is not None
    print("ok  text         -> <> in an override becomes the measurement")


def test_text_height_follows_dimscale_and_an_override():
    vm = newvm(txt=4.0, scale=3.0)
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A')
    r = vm.loads('(cd:read-dim 0 (entlast))')
    assert abs(r[9] - 12.0) < 1e-9, "DIMTXT x DIMSCALE is the height"
    # ... unless the dimension carries its own override of DIMTXT, which
    # is exactly what a drafter does to one loud dimension on a sheet
    vm2 = newvm(txt=4.0, scale=3.0)
    vm2.loads('(entmakex (list (cons 0 "DIMENSION") (cons 8 "0")'
              ' (cons 3 "STANDARD") (cons 70 0) (cons 50 0.0)'
              ' (list 13 0.0 0.0 0.0) (list 14 100.0 0.0 0.0)'
              ' (list 10 0.0 20.0 0.0) (list 11 50.0 26.0 0.0) (cons 1 "A")'
              ' (list -3 (list "ACAD" (cons 1000 "DSTYLE") (cons 1002 "{")'
              ' (cons 1070 140) (cons 1040 2.0) (cons 1002 "}")))))')
    r2 = vm2.loads('(cd:read-dim 0 (entlast))')
    assert abs(r2[9] - 6.0) < 1e-9, ("the dimension's own DIMTXT override "
                                     "wins over the style's: %r" % (r2[9],))
    print("ok  height       -> DIMTXT x DIMSCALE, and the dim's own override")


# ------------------------------------------------------------------
# the policy: who keeps their spot
# ------------------------------------------------------------------

def test_a_lone_clear_text_does_not_move():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    res = plan(vm)
    assert len(res) == 1
    assert res[0][2] is NIL, "nothing was in the way and it moved anyway?"
    assert res[0][3] is not NIL
    print("ok  stay put     -> a text with nothing near it is left alone")


def test_text_over_a_line_slides_clear_and_stays_on_its_track():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    line(vm, (50, 22), (50, 30))            # straight through the letters
    run(vm, 'c:CLEARDIM', [None, None], 'over a line')
    x, y = p11(vm, a)
    assert y == 26.0, "the across-the-track offset moved: %r" % (y,)
    half = (box_w('A-TEXT') + 2 * GAPF * TXT) / 2.0
    assert abs(x - 50.0) >= half - 1e-6, \
        "it stopped before it was clear: %r" % (x,)
    assert abs(x - 50.0) <= half + TXT * 0.25, \
        "it moved further than it had to: %r" % (x,)
    print("ok  slide        -> along the track only, and no further "
          "than it must")


def test_the_one_that_is_already_good_keeps_its_spot():
    """The headline rule.  A's text is on a line, B's is not, and the two
    texts also overlap each other.  B has earned its spot; A is the one
    that has to go around."""
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    b = dim(vm, (0, 50), (100, 50), (0, 36), (50, 28), text='B-TEXT')
    line(vm, (40, 22), (40, 23.5))          # inside A's box, below B's
    before = (p11(vm, a), p11(vm, b))
    run(vm, 'c:CLEARDIM', [None, None], 'good one keeps its spot')
    assert p11(vm, b) == before[1], \
        "the text that was already clear was moved: %r" % (p11(vm, b),)
    assert p11(vm, a) != before[0], "the text on the line was not moved"
    assert p11(vm, a)[1] == 26.0, "A left its track"
    # and where it landed really is clear of B
    assert 'already clear - left alone' in said(vm)
    assert '1 slid clear' in said(vm), said(vm)
    print("ok  policy       -> the clear one keeps its spot, the other "
          "goes around")


def test_two_clear_texts_that_overlap_move_only_one():
    """Neither is on anything but the other.  Exactly one gives way, and
    it is the second one in reading order -- so the same drawing comes
    out the same way every run."""
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    b = dim(vm, (0, 50), (100, 50), (0, 36), (52, 28), text='B-TEXT')
    before = (p11(vm, a), p11(vm, b))
    run(vm, 'c:CLEARDIM', [None, None], 'two clear texts')
    moved = [p11(vm, a) != before[0], p11(vm, b) != before[1]]
    assert moved.count(True) == 1, \
        "expected exactly one of them to give way, got %r" % (moved,)
    # reading order runs down the sheet, so the higher text is read
    # first and keeps its spot
    assert moved == [True, False], \
        "the lower text kept its spot and the upper one gave way"
    print("ok  policy       -> one of two overlapping texts gives way, "
          "the upper keeps")


def test_a_second_run_moves_nothing():
    """Running it twice on an unchanged drawing is a no-op: the first
    run left everything clear, so the second finds nothing to do.  A
    fixer that shuffled the sheet a little more every time it was run
    would be worse than no fixer at all."""
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    b = dim(vm, (0, 50), (100, 50), (0, 36), (50, 28), text='B-TEXT')
    line(vm, (40, 22), (40, 23.5))
    line(vm, (70, 24), (70, 32))
    run(vm, 'c:CLEARDIM', [None, None], 'first run')
    first = (p11(vm, a), p11(vm, b))
    vm.printed.clear()
    run(vm, 'c:CLEARDIM', [None, None], 'second run')
    assert (p11(vm, a), p11(vm, b)) == first, \
        "the second run shuffled the sheet again: %r -> %r" \
        % (first, (p11(vm, a), p11(vm, b)))
    assert '2 already clear' in said(vm), said(vm)
    print("ok  idempotent   -> a second run on the same drawing does "
          "nothing")


def test_a_text_with_nowhere_clear_is_left_as_drawn():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    for x in range(-400, 500, 4):           # a picket fence over the track
        line(vm, (x, 22), (x, 30))
    run(vm, 'c:CLEARDIM', [None, None], 'nowhere clear')
    assert p11(vm, a) == (50.0, 26.0), \
        "it was parked somewhere arbitrary: %r" % (p11(vm, a),)
    assert 'nowhere clear on the track' in said(vm), said(vm)
    print("ok  hemmed in    -> left where the drafter can see it, and named")


def test_reach_is_a_knob():
    """The same picket fence, with one gap in it just outside the default
    reach.  Widening cd:*reach-f* finds it."""
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    for x in range(-400, 500, 4):
        if 180 <= x <= 230:                 # the gap, ~130 units away
            continue
        line(vm, (x, 22), (x, 30))
    run(vm, 'c:CLEARDIM', [None, None], 'reach default')
    assert p11(vm, a) == (50.0, 26.0), "the default reach found the far gap"

    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    for x in range(-400, 500, 4):
        if 180 <= x <= 230:
            continue
        line(vm, (x, 22), (x, 30))
    vm.loads('(setq cd:*reach-f* 40.0)')
    run(vm, 'c:CLEARDIM', [None, None], 'reach widened')
    assert p11(vm, a) != (50.0, 26.0), "a wider reach still found nothing"
    assert 180 < p11(vm, a)[0] < 230, p11(vm, a)
    print("ok  knob         -> cd:*reach-f* is what the search is capped by")


def test_gap_is_a_knob():
    """A line just outside the letters: readable at gap 0, not at gap 1."""
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='AA')
    edge = box_w('AA') / 2.0
    line(vm, (50 + edge + 0.5, 22), (50 + edge + 0.5, 30))
    vm.loads('(setq cd:*gap-f* 0.0)')
    run(vm, 'c:CLEARDIM', [None, None], 'gap 0')
    assert p11(vm, a) == (50.0, 26.0), "gap 0 moved a text nothing crossed"

    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='AA')
    line(vm, (50 + edge + 0.5, 22), (50 + edge + 0.5, 30))
    vm.loads('(setq cd:*gap-f* 1.0)')
    run(vm, 'c:CLEARDIM', [None, None], 'gap 1')
    assert p11(vm, a) != (50.0, 26.0), \
        "gap 1 left a text crowded against a line"
    print("ok  knob         -> cd:*gap-f* is what 'readable' means here")


# ------------------------------------------------------------------
# what is ink and what is not
# ------------------------------------------------------------------

def test_its_own_dimension_line_is_not_an_obstacle():
    """Text sitting ON its own dimension line is the normal way a
    dimension is drawn -- AutoCAD breaks the line around it.  If it
    counted as ink, every dimension in the drawing would move."""
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 20), text='A-TEXT')
    run(vm, 'c:CLEARDIM', [None, None], 'own dim line')
    assert p11(vm, a) == (50.0, 20.0), \
        "it fled its own dimension line: %r" % (p11(vm, a),)
    print("ok  own ink      -> a dimension does not have to clear its "
          "own dim line")


def test_its_own_extension_line_is_an_obstacle():
    """An extension line crosses the track at right angles, so a text
    slid far enough ends up on one.  It has to stop clear of it.

    The text sits ONE unit off its dimension line here, not six: an
    extension line only runs DIMEXE past the dimension line, so text
    riding higher than that sails over the tip without touching it --
    which is correct, and is why this case needs a low text to show."""
    vm = newvm()
    a = dim(vm, (0, 0), (40, 0), (0, 20), (20, 21), text='A-TEXT')
    # everything between the extension lines is blocked, so the only way
    # out is past one of them
    for x in range(2, 39, 2):
        line(vm, (x, 18), (x, 24))
    run(vm, 'c:CLEARDIM', [None, None], 'own extension line')
    x = p11(vm, a)[0]
    half = (box_w('A-TEXT') + 2 * GAPF * TXT) / 2.0
    assert x < -half or x > 40 + half, \
        "it came to rest on an extension line: %r" % (x,)
    print("ok  own ink      -> a text stops clear of its own "
          "extension lines")


def test_another_dimensions_line_is_ink():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    # B's dimension line runs right through where A's text sits
    dim(vm, (0, 60), (100, 60), (0, 26), (200, 30), text='B')
    run(vm, 'c:CLEARDIM', [None, None], "another dim's line")
    assert p11(vm, a) != (50.0, 26.0), \
        "a text sitting on another dimension's line was called clear"
    print("ok  ink          -> another dimension's line is ink like "
          "any other")


def test_defpoints_is_not_ink():
    vm = newvm()
    layer(vm, 'DEFPOINTS')
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    line(vm, (50, 22), (50, 30), layer='DEFPOINTS')
    run(vm, 'c:CLEARDIM', [None, None], 'defpoints')
    assert p11(vm, a) == (50.0, 26.0), \
        "a DEFPOINTS line, which does not plot, moved a text"
    print("ok  ink          -> nothing on cd:*skip-layers* counts as ink")


def test_a_circle_is_flattened_into_ink():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    vm.loads('(entmakex (list (cons 0 "CIRCLE") (cons 8 "0")'
             ' (list 10 50.0 26.0 0.0) (cons 40 10.0)))')
    run(vm, 'c:CLEARDIM', [None, None], 'circle')
    assert p11(vm, a) != (50.0, 26.0), "a circle around the text is not ink?"
    print("ok  ink          -> arcs and circles are flattened and counted")


def test_a_drawing_text_is_ink():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    vm.loads('(entmakex (list (cons 0 "TEXT") (cons 8 "0")'
             ' (list 10 45.0 25.0 0.0) (cons 40 4.0) (cons 1 "NOTE")))')
    run(vm, 'c:CLEARDIM', [None, None], 'drawing text')
    assert p11(vm, a) != (50.0, 26.0), "plain TEXT under the letters is ink"
    print("ok  ink          -> a TEXT entity under the letters is ink")


# ------------------------------------------------------------------
# what it will not touch
# ------------------------------------------------------------------

def test_fit_text_is_measured_between_its_two_ends():
    """Justification 5 (Fit) is not a justification: the letters are set
    BETWEEN groups 10 and 11, so the glyph count is the wrong width and
    group 11 is not an anchor.  A one-character Fit text stretched
    across 60 units has to cover all 60."""
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    # one glyph, but set across x 20..80 -- far too wide to be read as
    # a justification offset from either end
    vm.loads('(entmakex (list (cons 0 "TEXT") (cons 8 "0")'
             ' (list 10 20.0 25.0 0.0) (list 11 80.0 25.0 0.0)'
             ' (cons 40 4.0) (cons 72 5) (cons 1 "X")))')
    run(vm, 'c:CLEARDIM', [None, None], 'fit text')
    x = p11(vm, a)[0]
    half = (box_w('A-TEXT') + 2 * GAPF * TXT) / 2.0
    assert x < 20 - half + 1e-6 or x > 80 + half - 1e-6, \
        "the dimension text came to rest inside a Fit text's span: %r" % (x,)
    print("ok  ink          -> Fit text is measured between its own ends")


def test_a_curved_track_is_skipped_but_still_blocks():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    g = dim(vm, (0, 50), (100, 50), (0, 36), (50, 28), text='ANGLE', flags=2)
    run(vm, 'c:CLEARDIM', [None, None], 'angular')
    assert p11(vm, g) == (50.0, 28.0), \
        "an angular dimension's text was slid along a straight line"
    assert p11(vm, a) != (50.0, 26.0), \
        "the angular text did not block the linear one"
    assert 'not a straight dimension line' in said(vm), said(vm)
    print("ok  skip         -> a curved track is left alone and still "
          "blocks")


def test_every_curved_kind_is_named_by_kind():
    vm = newvm()
    for flags in (2, 3, 4, 5, 6):
        dim(vm, (0, flags * 200), (100, flags * 200), (0, flags * 200 + 20),
            (50, flags * 200 + 26), text='X')
        e = vm.entities[-1]
        vm.entdata[e] = [Dot(70, flags) if (isinstance(g, Dot) and g.a == 70)
                         else g for g in vm.entdata[e]]
    res = plan(vm)
    whys = [r[0][11] for r in res]
    assert all(str(w).upper() == 'CURVE' for w in whys), whys
    print("ok  skip         -> angular, diameter, radius and ordinate all")


def test_a_locked_layer_is_skipped_and_said_so():
    vm = newvm()
    layer(vm, 'DIMS', flags=4)
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT',
            layer='DIMS')
    line(vm, (50, 22), (50, 30))
    run(vm, 'c:CLEARDIM', [None, None], 'locked layer')
    assert p11(vm, a) == (50.0, 26.0), "entmod on a locked layer would fail"
    assert 'locked layer' in said(vm), said(vm)
    print("ok  skip         -> a locked layer is reported, never written to")


def test_suppressed_text_is_skipped_and_is_not_ink():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text=' ')
    b = dim(vm, (0, 50), (100, 50), (0, 36), (50, 28), text='B-TEXT')
    run(vm, 'c:CLEARDIM', [None, None], 'suppressed text')
    assert 'with no text' in said(vm), said(vm)
    assert p11(vm, b) == (50.0, 28.0), \
        "a dimension with no text still put something in the way"
    print("ok  skip         -> no text is nothing to read and nothing "
          "to clear")


# ------------------------------------------------------------------
# the commands
# ------------------------------------------------------------------

def test_the_scan_changes_nothing():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    line(vm, (50, 22), (50, 30))
    run(vm, 'c:CLEARDIMSCAN', [None, None], 'scan')
    assert p11(vm, a) == (50.0, 26.0), "the read-only scan moved a text"
    assert grp(vm, a, 70) == 0, "the scan set the user-position flag"
    assert 'to slide clear' in said(vm), said(vm)
    assert 'Nothing was moved' in said(vm), said(vm)
    assert 'CLEARDIMSCAN:' in said(vm), "the report named the wrong command"
    print("ok  scan         -> says what CLEARDIM would do, changes nothing")


def test_a_moved_dimension_is_marked_user_positioned():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    b = dim(vm, (0, 200), (100, 200), (0, 220), (50, 226), text='B-TEXT')
    line(vm, (50, 22), (50, 30))
    run(vm, 'c:CLEARDIM', [None, None], 'user flag')
    assert grp(vm, a, 70) == 128, \
        "group 70 bit 128 is what stops AutoCAD re-centring it: %r" \
        % (grp(vm, a, 70),)
    assert grp(vm, b, 70) == 0, "a dimension that did not move was flagged"
    print("ok  write        -> only what moved is marked user-positioned")


def test_a_selection_is_the_only_thing_looked_at():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    ln = line(vm, (50, 22), (50, 30))
    # the sweep is handed the dimension alone, so the line is not ink
    run(vm, 'c:CLEARDIM', [None, [a]], 'selection')
    assert p11(vm, a) == (50.0, 26.0), \
        "an entity outside the selection was treated as ink"
    assert ln is not None
    print("ok  sweep        -> only what was highlighted is read")


def test_a_pickfirst_selection_is_taken_without_asking():
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    line(vm, (50, 22), (50, 30))
    vm.pickfirst = ['<ss>'] + [a]
    run(vm, 'c:CLEARDIM', [], 'pickfirst')
    assert 'Highlight the drawing' not in said(vm), \
        "it asked even though a selection was already made"
    print("ok  sweep        -> a selection made before the command is used")


def test_no_dimensions_is_not_an_error():
    vm = newvm()
    line(vm, (0, 0), (10, 10))
    run(vm, 'c:CLEARDIM', [None, None], 'no dims')
    assert 'no dimensions in the selection' in said(vm), said(vm)
    assert not [c for c in vm.commands if c and c[0] == '_.UNDO'], \
        "an undo group was opened for a run with nothing to do"
    print("ok  empty        -> a drawing with no dimensions says so")


def test_undo_group_wraps_the_run():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    line(vm, (50, 22), (50, 30))
    run(vm, 'c:CLEARDIM', [None, None], 'undo')
    calls = [c[1] for c in vm.commands if c and c[0] == '_.UNDO']
    assert calls == ['_Begin', '_End'], calls
    print("ok  undo         -> one group around the whole run")


def test_undo_off_opens_no_group():
    vm = newvm()
    vm.sysvars['UNDOCTL'] = 0            # undo recording switched off
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    line(vm, (50, 22), (50, 30))
    run(vm, 'c:CLEARDIM', [None, None], 'undo off')
    assert not [c for c in vm.commands if c and c[0] == '_.UNDO'], \
        "_Begin in a drawing with undo off errors out of the command"
    print("ok  undo         -> none opened when undo is not recording")


def test_esc_mid_run_puts_the_settings_back():
    vm = newvm()
    vm.handle_errors = True          # dispatch through the tool's *error*
    vm.sysvars['OSMODE'] = 679
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')

    def esc(*_):
        raise LispError('Function cancelled', vm)

    vm.run('c:CLEARDIM', [None, esc])
    assert vm.sysvars['OSMODE'] == 679, \
        "Esc left object snaps where the command put them"
    assert 'CLEARDIM error' not in said(vm), \
        "a plain cancel was reported as an error"
    print("ok  esc          -> settings back, and a cancel is not an error")


def test_version_command():
    vm = newvm()
    vm.run('c:CLEARDIMVER', [])
    assert 'CLEARDIM v' in said(vm), said(vm)
    print("ok  version      -> CLEARDIMVER reports the loaded build")


# ------------------------------------------------------------------
# the file itself
# ------------------------------------------------------------------

def test_no_local_shadows_a_function():
    """An AutoLISP local SHADOWS the function of the same name for the
    whole call, so a local called "last" turns every (last ...) in the
    body into "no function definition: LAST" at run time."""
    import re
    src = open(vm_path()).read()
    src = re.sub(r';[^\n]*', '', src)
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)
    arglists = re.findall(r'\(defun\s+[^\s()]+\s*\(([^)]*)\)', src)
    bodies = re.sub(r'\(defun\s+[^\s()]+\s*\([^)]*\)', '(defun', src)
    called = set(re.findall(r'\(\s*([a-zA-Z][\w:*<>=+/-]*)', bodies))
    bad = []
    for arglist in arglists:
        for name in arglist.replace('/', ' ').split():
            if name.lower() in called:
                bad.append(name)
    assert not bad, f"locals shadowing functions they call: {sorted(set(bad))}"
    print("ok  no shadow    -> no local hides a function the file calls")


def vm_path():
    vm = VM()
    return vm._remap_root(LSP)


if __name__ == '__main__':
    test_box_is_centred_on_its_point()
    test_segment_against_box()
    test_box_against_box()
    test_glyph_count_reads_control_codes()
    test_text_size_splits_hard_line_breaks()
    test_track_of_a_rotated_dimension()
    test_track_of_an_aligned_dimension()
    test_own_segments_are_the_dim_line_then_the_extension_lines()
    test_text_override_expands_the_measurement_marker()
    test_text_height_follows_dimscale_and_an_override()
    test_a_lone_clear_text_does_not_move()
    test_text_over_a_line_slides_clear_and_stays_on_its_track()
    test_the_one_that_is_already_good_keeps_its_spot()
    test_two_clear_texts_that_overlap_move_only_one()
    test_a_second_run_moves_nothing()
    test_a_text_with_nowhere_clear_is_left_as_drawn()
    test_reach_is_a_knob()
    test_gap_is_a_knob()
    test_its_own_dimension_line_is_not_an_obstacle()
    test_its_own_extension_line_is_an_obstacle()
    test_another_dimensions_line_is_ink()
    test_defpoints_is_not_ink()
    test_a_circle_is_flattened_into_ink()
    test_a_drawing_text_is_ink()
    test_fit_text_is_measured_between_its_two_ends()
    test_a_curved_track_is_skipped_but_still_blocks()
    test_every_curved_kind_is_named_by_kind()
    test_a_locked_layer_is_skipped_and_said_so()
    test_suppressed_text_is_skipped_and_is_not_ink()
    test_the_scan_changes_nothing()
    test_a_moved_dimension_is_marked_user_positioned()
    test_a_selection_is_the_only_thing_looked_at()
    test_a_pickfirst_selection_is_taken_without_asking()
    test_no_dimensions_is_not_an_error()
    test_undo_group_wraps_the_run()
    test_undo_off_opens_no_group()
    test_esc_mid_run_puts_the_settings_back()
    test_version_command()
    test_no_local_shadows_a_function()
    print("all CLEARDIM tests passed")
