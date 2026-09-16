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

def newvm(txt=TXT, scale=1.0, exe=EXE, tih=0):
    """A VM with CLEARDIM loaded and a DIMSTYLE record that carries a
    real text height.  The record is installed straight into the VM's
    symbol table rather than entmade: entmake has no branch for a
    DIMSTYLE, so an entmade one would land in model space and turn up
    in the next (ssget "_X") -- and tblsearch would still not find its
    140 group."""
    vm = VM()
    vm.load(LSP)
    rec = Ent()
    # 73 is DIMTIH: non-zero holds the text upright instead of setting
    # it along whatever it is dimensioning
    vm.recdata[rec] = [Dot(0, 'DIMSTYLE'), Dot(2, 'STANDARD'),
                       Dot(140, txt), Dot(40, scale), Dot(44, exe),
                       Dot(73, tih)]
    vm.tables.setdefault('DIMSTYLE', set()).add('STANDARD')
    vm.tablerecs.setdefault('DIMSTYLE', {})['STANDARD'] = rec
    return vm


def textstyle(vm, name, height=0.0, wfactor=1.0):
    """A STYLE record.  HEIGHT is its FIXED height: non-zero means every
    text set in it is drawn that tall whatever DIMTXT says."""
    rec = Ent()
    vm.recdata[rec] = [Dot(0, 'STYLE'), Dot(2, name),
                       Dot(40, height), Dot(41, wfactor)]
    vm.tables.setdefault('STYLE', set()).add(name)
    vm.tablerecs.setdefault('STYLE', {})[name.upper()] = rec
    return rec


def dimstyle(vm, name, groups):
    """A DIMSTYLE record with exactly the groups given -- which is how a
    real one comes: DXF leaves out every dimvar sitting at its default,
    so a style that keeps its text height on its text style carries no
    DIMTXT at all."""
    rec = Ent()
    vm.recdata[rec] = ([Dot(0, 'DIMSTYLE'), Dot(2, name)]
                       + [Dot(c, v) for c, v in groups])
    vm.tables.setdefault('DIMSTYLE', set()).add(name)
    vm.tablerecs.setdefault('DIMSTYLE', {})[name.upper()] = rec
    return rec


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


def anydim(vm, groups, flags, layer='0'):
    """A DIMENSION with exactly the groups given, for the families whose
    points do not sit where a linear one's do.  FLAGS is group 70 whole,
    so the ordinate's bit 64 rides in it alongside the type."""
    parts = ['(cons 0 "DIMENSION")', '(cons 8 "%s")' % layer,
             '(cons 3 "STANDARD")', '(cons 70 %d)' % flags]
    for code, v in sorted(groups.items()):
        if isinstance(v, tuple):
            parts.append('(list %d %r %r 0.0)' % (code, v[0], v[1]))
        elif isinstance(v, str):
            parts.append('(cons %d "%s")' % (code, v))
        else:
            parts.append('(cons %d %r)' % (code, v))
    vm.loads('(entmakex (list %s))' % ' '.join(parts))
    return vm.entities[-1]


def angdim(vm, vtx=(0.0, 0.0), a=0.0, b=math.pi / 2, arc=50.0, tang=None,
           trad=None, layer='0'):
    """A 3-point angular dimension: the vertex in group 15, a point down
    each ray in 13 and 14, the arc point in 10, and the text at TANG on
    a circle of TRAD about the vertex."""
    if tang is None:
        tang = 0.5 * (a + b)
    if trad is None:
        trad = arc
    mid = 0.5 * (a + b)
    return anydim(vm, {
        13: (vtx[0] + 80 * math.cos(a), vtx[1] + 80 * math.sin(a)),
        14: (vtx[0] + 80 * math.cos(b), vtx[1] + 80 * math.sin(b)),
        15: vtx,
        10: (vtx[0] + arc * math.cos(mid), vtx[1] + arc * math.sin(mid)),
        11: (vtx[0] + trad * math.cos(tang), vtx[1] + trad * math.sin(tang)),
        42: abs(b - a),
        1: 'ANG',
    }, 5, layer)


def chain(vm, stops, y=0.0, dimy=20.0, texts=None):
    """A run of continued dimensions: one dimension line, one segment
    per gap in STOPS, each text centred in its own segment.  This is
    what AutoCAD's DIMCONTINUE and AUTODIM both lay down."""
    out = []
    for i in range(len(stops) - 1):
        a, b = stops[i], stops[i + 1]
        out.append(dim(vm, (a, y), (b, y), (0, dimy),
                       ((a + b) / 2.0, dimy + 6.0),
                       text=(texts[i] if texts else '')))
    return out


def dimline_y(vm, e):
    return round(grp(vm, e, 10)[1], 6)


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
    vm.loads('(setq RUNS (cd:runs RECS))')
    vm.loads('(setq STATIC (cd:static-obs SS RECS RUNS))')
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
    one = vm.loads('(cd:text-size "ABCD" 4.0 1.0)')
    assert abs(one[0] - 4 * 4.0 * CW) < 1e-9, one
    assert abs(one[1] - 4.0) < 1e-9, one
    two = vm.loads('(cd:text-size "ABCD\\\\PEF" 4.0 1.0)')
    # the widest line decides the width, and a second line is another
    # line and a half of height
    assert abs(two[0] - 4 * 4.0 * CW) < 1e-9, two
    assert abs(two[1] - 4.0 * 2.5) < 1e-9, two
    print("ok  text size    -> widest line wide, one line and a half tall")


# ------------------------------------------------------------------
# reading a dimension
# ------------------------------------------------------------------

def field(vm, name, expr='R'):
    """One field of a record, through the file's own accessor -- the
    record is positional and the tests have no business knowing which
    position."""
    return vm.loads('(cd:r-%s %s)' % (name, expr))


def track(vm, expr='R'):
    """(kind base u-or-rad off-or-rot) of a record's track."""
    return vm.loads('(cd:r-trk %s)' % expr)


def test_track_of_a_rotated_dimension():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert field(vm, 'type') == 0                           # rotated
    kind, base, u, off = track(vm)
    assert str(kind).lower() == 'line', kind
    assert [round(x, 6) for x in u] == [1.0, 0.0], u        # track along X
    assert abs(field(vm, 's0') - 50.0) < 1e-9               # 50 along it
    assert [round(x, 6) for x in off] == [0.0, 6.0], off    # 6 above it
    assert abs(field(vm, 'w') - box_w('A-TEXT')) < 1e-9
    assert abs(field(vm, 'h') - TXT) < 1e-9
    assert field(vm, 'why') is NIL, "a plain linear dimension cannot slide?"
    assert field(vm, 'pins') == [11], field(vm, 'pins')
    print("ok  track        -> a rotated dim's track is its own dim line")


def test_track_of_an_aligned_dimension():
    vm = newvm()
    dim(vm, (0, 0), (100, 100), (0, 20), None, text='DIAG', flags=1)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert field(vm, 'type') == 1
    kind, base, u, off = track(vm)
    assert str(kind).lower() == 'line', kind
    assert [round(x, 6) for x in u] == [round(math.sqrt(0.5), 6)] * 2, u
    # with no stored text point the text sits at the middle of the
    # dimension line, half its own height clear of it
    assert abs(math.hypot(off[0], off[1]) - TXT / 2.0) < 1e-6, off
    print("ok  track        -> an aligned dim's track runs 13 to 14")


def test_own_ink_splits_what_it_rides_from_what_it_merely_draws():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    ridden, other = vm.loads('(cd:r-own (cd:read-dim 0 (entlast)))')
    # RIDDEN is the dimension line: the one thing the dimension never
    # has to clear, because AutoCAD breaks it around the text
    assert len(ridden) == 1, ridden
    assert [round(v, 6) for v in ridden[0][0]] == [0.0, 20.0], ridden
    assert [round(v, 6) for v in ridden[0][1]] == [100.0, 20.0], ridden
    # OTHER is an extension line per definition point, run DIMEXE past
    # the dimension line -- ink to everyone, this dimension included
    assert len(other) == 2, other
    assert [round(v, 6) for v in other[0][1]] == [0.0, 20.0 + EXE], other
    assert [round(v, 6) for v in other[1][1]] == [100.0, 20.0 + EXE], other
    print("ok  own ink      -> the dim line it rides, then the extension "
          "lines it does not")


def test_all_of_an_arc_is_ridden_not_just_its_first_chord():
    """An arc is many polygons.  If only the first chord counted as the
    dimension's own, the other thirty-one would be obstacles it had to
    flee -- so an angular dimension would slide off a clear drawing."""
    vm = newvm()
    angdim(vm)
    ridden, other = vm.loads('(cd:r-own (cd:read-dim 0 (entlast)))')
    # a quarter turn is a quarter of cd:*arcsegs*, and every chord of
    # it is the dimension's own
    assert len(ridden) == 8, "a 90-degree arc at 32 a turn: %d" % len(ridden)
    assert not other, other
    # and it shows: nothing is near this dimension, so nothing moves
    e = vm.entities[-1]
    before = p11(vm, e)
    run(vm, 'c:CLEARDIM', [None, None], 'angular alone')
    assert p11(vm, e) == before, \
        "an angular dimension fled its own arc: %r -> %r" % (before,
                                                             p11(vm, e))
    print("ok  own ink      -> the whole arc is ridden, not its first chord")


def test_text_override_expands_the_measurement_marker():
    vm = newvm()
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='TYP <> LONG')
    vm.loads('(setq ED (entget (entlast))'
             '      STY (tblsearch "DIMSTYLE" "STANDARD"))')
    s = vm.loads('(cd:dim-text ED STY)')
    assert '<>' not in s, s
    assert s.startswith('TYP ') and s.endswith(' LONG'), s
    assert vm.loads('(cd:dim-meas ED STY)') in s, s
    print("ok  text         -> <> in an override becomes the measurement")


def test_text_height_follows_dimscale_and_an_override():
    vm = newvm(txt=4.0, scale=3.0)
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A')
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert abs(field(vm, 'h') - 12.0) < 1e-9, "DIMTXT x DIMSCALE is the height"
    # ... unless the dimension carries its own override of DIMTXT, which
    # is exactly what a drafter does to one loud dimension on a sheet
    vm2 = newvm(txt=4.0, scale=3.0)
    vm2.loads('(entmakex (list (cons 0 "DIMENSION") (cons 8 "0")'
              ' (cons 3 "STANDARD") (cons 70 0) (cons 50 0.0)'
              ' (list 13 0.0 0.0 0.0) (list 14 100.0 0.0 0.0)'
              ' (list 10 0.0 20.0 0.0) (list 11 50.0 26.0 0.0) (cons 1 "A")'
              ' (list -3 (list "ACAD" (cons 1000 "DSTYLE") (cons 1002 "{")'
              ' (cons 1070 140) (cons 1040 2.0) (cons 1002 "}")))))')
    vm2.loads('(setq R (cd:read-dim 0 (entlast)))')
    h2 = field(vm2, 'h')
    assert abs(h2 - 6.0) < 1e-9, ("the dimension's own DIMTXT override "
                                  "wins over the style's: %r" % (h2,))
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
    # a picket fence over the track, and TALL: standing the dimension
    # off the work is a way out now, so a fence the height of the text
    # only proves that rows work
    for x in range(-400, 500, 4):
        line(vm, (x, 10), (x, 90))
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
        line(vm, (x, 10), (x, 90))
    run(vm, 'c:CLEARDIM', [None, None], 'reach default')
    assert p11(vm, a) == (50.0, 26.0), "the default reach found the far gap"

    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    for x in range(-400, 500, 4):
        if 180 <= x <= 230:
            continue
        line(vm, (x, 10), (x, 90))
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


def test_a_fixed_height_text_style_beats_dimtxt():
    """The bug that made CLEARDIM do nothing on a real sheet.

    A dimension style is entitled to leave DIMTXT at its 0.18 DXF
    default and keep the real height on the text style it points at
    through DIMTXSTY (group 340) -- and every style in the drawing this
    was found on did exactly that.  Read DIMTXT alone and a 6-unit text
    measures 0.18: every box a speck, nothing overlapping anything, and
    a sheet with two dimensions printing on top of each other reported
    entirely clear."""
    vm = VM()
    vm.load(LSP)
    romanc = textstyle(vm, 'ROMANC', height=6.0)
    dimstyle(vm, 'STANDARD', [(41, 3.99), (44, 2.0), (147, 2.0), (340, romanc)])
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='ABC')
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert abs(field(vm, 'h') - 6.0) < 1e-9, \
        "the text style's fixed height is the height: %r" % (field(vm, 'h'),)
    assert abs(field(vm, 'w') - 3 * 6.0 * CW) < 1e-9, field(vm, 'w')
    print("ok  height       -> a fixed-height text style beats DIMTXT")


def test_a_fixed_height_is_not_scaled_by_dimscale():
    """DIMSCALE scales the dimension variables; a text style's fixed
    height is not one of them.  The drawing this was checked against
    keeps STANDARD at DIMSCALE 1.5 pointing at an 8-unit style, and the
    MTEXT inside the dimension's own block is 8.0 high, not 12."""
    vm = VM()
    vm.load(LSP)
    title = textstyle(vm, 'TITLE', height=8.0)
    dimstyle(vm, 'STANDARD', [(40, 1.5), (44, 2.25), (147, 2.25), (340, title)])
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='ABC')
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert abs(field(vm, 'h') - 8.0) < 1e-9, \
        "DIMSCALE must not touch a fixed height: %r" % (field(vm, 'h'),)
    print("ok  height       -> DIMSCALE does not scale a fixed height")


def test_dimtxt_still_applies_when_the_style_has_no_fixed_height():
    vm = VM()
    vm.load(LSP)
    variable = textstyle(vm, 'ROMANS', height=0.0)
    dimstyle(vm, 'STANDARD', [(40, 2.0), (140, 3.0), (340, variable)])
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='ABC')
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert abs(field(vm, 'h') - 6.0) < 1e-9, field(vm, 'h')
    print("ok  height       -> a variable-height style leaves DIMTXT in "
          "charge")


def test_a_style_width_factor_widens_the_box():
    vm = VM()
    vm.load(LSP)
    wide = textstyle(vm, 'WIDE', height=6.0, wfactor=2.0)
    dimstyle(vm, 'STANDARD', [(340, wide)])
    dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='ABC')
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert abs(field(vm, 'w') - 3 * 6.0 * CW * 2.0) < 1e-9, field(vm, 'w')
    print("ok  width        -> the text style's width factor is read")


def test_the_measurement_is_spelled_the_way_the_style_says():
    """DIMLUNIT (277) and DIMDEC (271) belong to the dimension style,
    and the drawing this came from reads 1/8" off its styles and 1/16"
    off its header.  The difference is not cosmetic: 33'-3" is half the
    width of 33'-2 15/16"."""
    vm = VM()
    vm.load(LSP)
    vm.sysvars['LUNITS'] = 2          # the drawing says decimal...
    vm.sysvars['LUPREC'] = 4
    textstyle(vm, 'ROMANC', height=6.0)
    # ... and the style says architectural, to the eighth
    dimstyle(vm, 'CROSS DIMENSIONS', [(271, 3), (277, 4)])
    dim(vm, (0, 0), (398.9452192042975, 0), (0, 20), (200, 26))
    vm.loads('(setq ED (entget (entlast))'
             '      STY (tblsearch "DIMSTYLE" "CROSS DIMENSIONS"))')
    # the same string the dimension's own block carries in the drawing
    assert vm.loads('(cd:dim-text ED STY)') == '33\'-3"', \
        vm.loads('(cd:dim-text ED STY)')
    print("ok  text         -> the style's own DIMLUNIT and DIMDEC spell it")


def test_mtext_formatting_codes_are_not_letters():
    """150 of the 152 MTEXTs in the failing drawing carry formatting.
    Counted as letters, markup fills the sheet with obstacles that are
    not there -- which is the opposite of erring on the safe side."""
    vm = newvm()
    cases = [
        (r'\A1;2{\H1.000000x;\S3/4;}"', 3),    # 2 3/4"  -- was 26
        (r'{\fArial|b1|i0|c0|p34;Rod Pockets}', 11),          # was 34
        (r'\A1;R8"', 3),                                      # was 7
        (r'\A1;33\'-2{\H1x;\S1/2;}"', 6),                     # was 24
    ]
    for raw, want in cases:
        esc = raw.replace('\\', '\\\\').replace('"', '\\"')
        got = vm.loads('(cd:glyphs "%s")' % esc)
        assert got == want, '%r -> %d, wanted %d' % (raw, got, want)
    print("ok  glyphs       -> MTEXT markup is not counted as letters")


def test_a_stacked_fraction_is_one_glyph_wide():
    """A stack is two half-height lines one above the other, so "1/2" is
    one glyph wide and not three; "15/16" is two."""
    vm = newvm()
    assert vm.loads(r'(cd:glyphs "\\S1/2;")') == 1
    assert vm.loads(r'(cd:glyphs "\\S15/16;")') == 2
    assert vm.loads(r'(cd:glyphs "\\S1^2;")') == 1
    print("ok  glyphs       -> a stacked fraction is as wide as its "
          "longer half")


def test_a_toggle_code_does_not_swallow_the_line():
    r"""\L, \O and \K take no argument, and \P is a hard break.  Scanning
    one of them for a semicolon would eat everything after it."""
    vm = newvm()
    assert vm.loads(r'(cd:glyphs "\\LUNDER\\l DONE")') == len('UNDER DONE')
    assert vm.loads(r'(cd:glyphs "A\\~B")') == 3
    print("ok  glyphs       -> a toggle takes no argument and eats nothing")


def test_an_mtext_split_across_chunks_is_measured_whole():
    """Anything over 250 characters is split across repeated group 3
    chunks with the remainder in group 1.  Reading group 1 alone
    measures the tail of a paragraph and none of the rest."""
    vm = newvm()
    vm.loads('(entmakex (list (cons 0 "MTEXT") (cons 8 "0")'
             ' (list 10 0.0 0.0 0.0) (cons 40 4.0) (cons 71 1)'
             ' (cons 3 "AAAA") (cons 3 "BBBB") (cons 1 "CC")))')
    poly = vm.loads('(cd:mtext-poly (entget (entlast)))')[0]
    xs = [p[0] for p in poly]
    assert abs((max(xs) - min(xs)) - 10 * 4.0 * CW) < 1e-9, \
        "the two group 3 chunks were not measured: %r" % (max(xs) - min(xs),)
    print("ok  mtext        -> group 3's chunks and group 1 are one string")


def test_an_angular_track_is_an_arc_about_the_vertex():
    vm = newvm()
    angdim(vm)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    kind, centre, rad, rot = track(vm)
    assert str(kind).lower() == 'arc', kind
    assert [round(v, 6) for v in centre] == [0.0, 0.0], centre
    assert abs(rad - 50.0) < 1e-6, rad
    assert rot is not NIL, "text on an arc turns with it unless held upright"
    # the parameter is an ARC LENGTH, not an angle, which is what lets
    # cd:*step-f* and cd:*reach-f* mean the same thing here as on a line
    assert abs(field(vm, 's0') - 50.0 * math.pi / 4) < 1e-6, field(vm, 's0')
    # and the text reads along the tangent: 45 degrees round, plus 90
    assert abs(math.degrees(field(vm, 'ang')) - 135.0) < 1e-6
    print("ok  track        -> an angular dim's track is an arc, "
          "measured in arc length")


def test_a_two_line_angular_finds_its_vertex_by_intersection():
    """A 3-point angular dimension writes its vertex into group 15; a
    2-line one has no vertex stored at all -- it is where the two
    measured lines cross, on the INFINITE lines, not the drawn ones."""
    vm = newvm()
    # two segments that would not cross if the test were bounded: one
    # along X from x=10, one along Y from y=10, meeting back at (0,0)
    anydim(vm, {13: (10.0, 0.0), 14: (100.0, 0.0),
                15: (0.0, 10.0), 10: (0.0, 100.0),
                16: (35.355, 35.355), 11: (35.355, 35.355),
                42: math.pi / 2, 1: 'ANG'}, 2)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    kind, centre, rad, rot = track(vm)
    assert str(kind).lower() == 'arc', kind
    assert [round(v, 6) for v in centre] == [0.0, 0.0], \
        "the vertex is where the two lines cross extended: %r" % (centre,)
    assert field(vm, 'why') is NIL
    print("ok  track        -> a 2-line angular's vertex is the crossing")


def test_angular_text_slides_round_the_arc_at_its_own_radius():
    """The radius the text rides at is the invariant, exactly as the
    offset above the dimension line is for a linear one."""
    vm = newvm()
    e = angdim(vm)
    line(vm, (30.0, 30.0), (42.0, 42.0))     # through the text at 45 deg
    run(vm, 'c:CLEARDIM', [None, None], 'angular slide')
    x, y = p11(vm, e)
    assert abs(math.hypot(x, y) - 50.0) < 1e-3, \
        "it left the arc: radius %r" % (math.hypot(x, y),)
    assert abs(math.degrees(math.atan2(y, x)) - 45.0) > 1.0, \
        "it did not move off the line at all"
    assert 'round its dimension arc' in said(vm), said(vm)
    print("ok  slide        -> round the arc, at the radius it came in on")


def test_the_text_box_turns_as_it_goes_round():
    """Text on a dimension arc is set along the tangent, so the box has
    to turn with it -- one held at the angle it started at would test
    the wrong rectangle everywhere but where it began."""
    vm = newvm()
    angdim(vm)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    s0 = field(vm, 's0')
    a0 = vm.loads('(cd:trk-ang (cd:r-trk R) %r %r (cd:r-ang R))' % (s0, s0))
    # a quarter of the way further round is another 45 degrees of turn
    s1 = s0 + 50.0 * math.pi / 4
    a1 = vm.loads('(cd:trk-ang (cd:r-trk R) %r %r (cd:r-ang R))' % (s1, s0))
    assert abs(math.degrees(a1 - a0) - 45.0) < 1e-6, math.degrees(a1 - a0)
    print("ok  box          -> it turns with the arc as it slides")


def test_upright_text_does_not_turn_with_the_arc():
    """DIMTIH holds the text upright, and then it stays upright all the
    way round."""
    vm = newvm(tih=1)
    angdim(vm)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    kind, centre, rad, rot = track(vm)
    assert rot is NIL, "DIMTIH text was left turning with the arc"
    s0 = field(vm, 's0')
    a1 = vm.loads('(cd:trk-ang (cd:r-trk R) %r %r (cd:r-ang R))'
                  % (s0 + 30.0, s0))
    assert abs(a1 - field(vm, 'ang')) < 1e-12
    print("ok  box          -> upright text stays upright round the arc")


def test_a_radius_track_runs_out_from_the_centre():
    """AutoDim's ad:raddimpts is the repo's own reading of these two
    groups: a radius dimension puts the CENTRE in group 10 and a point
    on the circle in 15."""
    vm = newvm()
    anydim(vm, {10: (0.0, 0.0), 15: (100.0, 0.0), 11: (60.0, 0.0),
                42: 100.0, 1: 'R100'}, 4)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    kind, base, u, off = track(vm)
    assert str(kind).lower() == 'line', kind
    assert [round(v, 6) for v in base] == [0.0, 0.0], base
    assert [round(v, 6) for v in u] == [1.0, 0.0], u
    assert abs(field(vm, 's0') - 60.0) < 1e-9
    # home is the circle it measures to, so a tie sends the text outward
    assert abs(field(vm, 'home') - 100.0) < 1e-9, field(vm, 'home')
    print("ok  track        -> a radius slides out along its own radius")


def test_a_diameter_is_centred_between_its_two_points():
    """A diameter dimension has no centre of its own: groups 10 and 15
    are the two ENDS of the diameter, so the centre is the middle of
    them -- and that is where its text belongs."""
    vm = newvm()
    anydim(vm, {10: (-100.0, 0.0), 15: (100.0, 0.0), 11: (0.0, 0.0),
                42: 200.0, 1: 'D200'}, 3)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    kind, base, u, off = track(vm)
    assert [round(v, 6) for v in base] == [0.0, 0.0], \
        "the centre is the middle of the two ends: %r" % (base,)
    assert abs(field(vm, 's0')) < 1e-9
    assert abs(field(vm, 'home')) < 1e-9, "a diameter's text belongs at the centre"
    print("ok  track        -> a diameter's centre is between its two points")


def test_a_radial_text_slides_and_keeps_its_offset():
    vm = newvm()
    e = anydim(vm, {10: (0.0, 0.0), 15: (100.0, 0.0), 11: (60.0, 3.0),
                    42: 100.0, 1: 'R100'}, 4)
    line(vm, (60.0, -10.0), (60.0, 10.0))
    run(vm, 'c:CLEARDIM', [None, None], 'radius slide')
    x, y = p11(vm, e)
    assert y == 3.0, "it left the radial line: %r" % (y,)
    assert x != 60.0, "it did not move"
    print("ok  slide        -> a radial text slides along its own radius")


def test_an_ordinate_leads_along_the_axis_its_bit_says():
    """Bit 64 of group 70 says which coordinate the ordinate reads, and
    with it which way its leader runs: an X-type reads across and leads
    away in Y, a Y-type the other way about.  The sign comes from the
    leader as drawn."""
    vm = newvm()
    anydim(vm, {13: (50.0, 0.0), 14: (50.0, 40.0), 11: (50.0, 44.0),
                1: '50'}, 6 + 64)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert [round(v, 6) for v in track(vm)[2]] == [0.0, 1.0], track(vm)
    assert field(vm, 'pins') == [11, 14], field(vm, 'pins')

    vm = newvm()
    anydim(vm, {13: (0.0, 50.0), 14: (-40.0, 50.0), 11: (-44.0, 50.0),
                1: '50'}, 6)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert [round(v, 6) for v in track(vm)[2]] == [-1.0, 0.0], track(vm)
    print("ok  track        -> an ordinate leads along the axis its bit "
          "names, the way it was drawn")


def test_an_ordinate_leader_travels_with_its_text():
    """The one family whose text does not move alone: the leader ends
    where the text is, so group 14 moves the same step.  Writing group
    11 by itself would leave the text off the end of its own leader."""
    vm = newvm()
    e = anydim(vm, {13: (50.0, 0.0), 14: (50.0, 40.0), 11: (50.0, 44.0),
                    1: '50'}, 6 + 64)
    line(vm, (40.0, 44.0), (60.0, 44.0))
    before = grp(vm, e, 14)[1]
    run(vm, 'c:CLEARDIM', [None, None], 'ordinate leader')
    moved = p11(vm, e)[1] - 44.0
    assert moved > 0, "it pulled the text back onto the work: %r" % (moved,)
    assert abs((grp(vm, e, 14)[1] - before) - moved) < 1e-9, \
        "the leader end did not travel with the text"
    assert grp(vm, e, 13)[1] == 0.0, "the feature point moved"
    print("ok  write        -> an ordinate's leader end moves with its text")


def test_an_ordinate_never_slides_back_past_its_feature():
    """Slid back past the point it is reading, an ordinate's leader turns
    round and points the other way -- a drawing error rather than a
    crowded one.  The floor stops it, and a text that cannot get clear
    above the floor is left where it was."""
    vm = newvm()
    e = anydim(vm, {13: (50.0, 0.0), 14: (50.0, 30.0), 11: (50.0, 34.0),
                    1: '50'}, 6 + 64)
    # a picket fence over everything from well below the feature to well
    # above the text, so the only way out would be through the feature
    for y in range(-60, 60, 3):
        line(vm, (40.0, float(y)), (60.0, float(y)))
    run(vm, 'c:CLEARDIM', [None, None], 'ordinate floor')
    y = p11(vm, e)[1]
    assert y > 0.0, "the text crossed its own feature point: %r" % (y,)
    assert grp(vm, e, 14)[1] > 0.0, "the leader turned round"
    print("ok  floor        -> an ordinate stops clear of the feature "
          "it reads")


def test_a_radius_text_never_crosses_its_centre():
    """A radius runs OUT from its centre; its text on the far side is
    measuring from nowhere."""
    vm = newvm()
    e = anydim(vm, {10: (0.0, 0.0), 15: (100.0, 0.0), 11: (20.0, 0.0),
                    42: 100.0, 1: 'R100'}, 4)
    for x in range(-120, 120, 3):
        line(vm, (float(x), -60.0), (float(x), 60.0))
    run(vm, 'c:CLEARDIM', [None, None], 'radius floor')
    assert p11(vm, e)[0] >= 0.0, \
        "the text crossed the centre: %r" % (p11(vm, e),)
    print("ok  floor        -> a radius text stays on its own side of "
          "the centre")


def test_a_diameter_has_no_floor_under_it():
    """A diameter's centre is the MIDDLE of its two points, so both
    sides of it are the dimension's own and the text is welcome
    anywhere along it."""
    vm = newvm()
    e = anydim(vm, {10: (-100.0, 0.0), 15: (100.0, 0.0), 11: (0.0, 0.0),
                    42: 200.0, 1: 'D200'}, 3)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert field(vm, 'lo') is NIL, field(vm, 'lo')
    line(vm, (-6.0, -10.0), (6.0, 10.0))        # straight through the text
    run(vm, 'c:CLEARDIM', [None, None], 'diameter both ways')
    assert p11(vm, e)[0] < 0.0, \
        "it was not allowed the near side of the centre: %r" % (p11(vm, e),)
    print("ok  floor        -> a diameter's text may sit either side of "
          "the centre")


def test_an_ordinate_with_no_leader_is_skipped():
    vm = newvm()
    e = anydim(vm, {13: (50.0, 0.0), 11: (50.0, 44.0), 1: '50'}, 6 + 64)
    line(vm, (40.0, 44.0), (60.0, 44.0))
    run(vm, 'c:CLEARDIM', [None, None], 'ordinate with no leader')
    assert p11(vm, e) == (50.0, 44.0)
    assert 'track could not be read' in said(vm), said(vm)
    print("ok  skip         -> an ordinate with no leader has no track")


def test_a_non_linear_dimension_with_no_text_point_is_skipped():
    """Every dimension AutoCAD writes carries group 11.  A linear one
    without it gets AutoCAD's own default computed for it; no other
    family does, because inventing a point on an arc or a leader is
    putting the text somewhere rather than finding where it is."""
    vm = newvm()
    e = anydim(vm, {13: (80.0, 0.0), 14: (0.0, 80.0), 15: (0.0, 0.0),
                    10: (35.0, 35.0), 42: math.pi / 2, 1: 'ANG'}, 5)
    run(vm, 'c:CLEARDIM', [None, None], 'no text point')
    assert grp(vm, e, 11) is None, "it invented a text point on an arc"
    assert 'track could not be read' in said(vm), said(vm)
    print("ok  skip         -> no text point on an arc is not guessed at")


def test_a_line_of_dimensions_is_one_run():
    """Dimensions whose dimension lines are the same straight line read
    as one continuous dimension with breaks, and are treated as one."""
    vm = newvm()
    chain(vm, [0, 100, 200, 300])
    vm.loads('(setq RECS (cd:records (ssget "_X")))')
    runs = vm.loads('(cd:runs RECS)')
    assert len(runs) == 1 and sorted(runs[0]) == [0, 1, 2], runs
    print("ok  run          -> a line of dimensions is one run")


def test_a_parallel_line_further_out_is_a_different_run():
    """Nested chains -- the overall dimension outside the part ones --
    are parallel, not collinear, and moving one must not move the
    other."""
    vm = newvm()
    chain(vm, [0, 100, 200], dimy=20.0)
    chain(vm, [0, 200], dimy=60.0)
    vm.loads('(setq RECS (cd:records (ssget "_X")))')
    runs = vm.loads('(cd:runs RECS)')
    assert len(runs) == 2, runs
    print("ok  run          -> a parallel line further out is its own run")


def test_dimensions_too_far_apart_along_the_line_are_not_one_run():
    """A run is one continuous dimension WITH BREAKS, and a break is
    allowed to be a real one -- but two dimensions at opposite ends of a
    sheet that happen to line up are not a run, or moving one would move
    the other."""
    vm = newvm()
    chain(vm, [0, 100])
    chain(vm, [4000, 4100])
    vm.loads('(setq RECS (cd:records (ssget "_X")))')
    assert len(vm.loads('(cd:runs RECS)')) == 2
    print("ok  run          -> a sheet-wide gap is not a break")


def test_only_a_linear_dimension_joins_a_run():
    """A radius keeps the CENTRE of its circle in group 10 and an
    ordinate its feature, so there is no dimension line there to be
    collinear with -- and pushing one "out" would move the dimension to
    a different circle rather than clear of an obstacle."""
    vm = newvm()
    anydim(vm, {10: (0.0, 0.0), 15: (100.0, 0.0), 11: (60.0, 0.0),
                42: 100.0, 1: 'R100'}, 4)
    vm.loads('(setq R (cd:read-dim 0 (entlast)))')
    assert field(vm, 'out') is NIL, "a radius has no outward side"
    print("ok  run          -> only a dimension with a dimension line "
          "joins a run")


def test_a_run_member_stays_inside_its_own_segment():
    vm = newvm()
    ents = chain(vm, [0, 30, 60, 90], texts=['WIDE-TEXT-A', 'WIDE-TEXT-B',
                                             'WIDE-TEXT-C'])
    run(vm, 'c:CLEARDIM', [None, None], 'inside its segment')
    for i, (lo, hi) in enumerate(((0, 30), (30, 60), (60, 90))):
        x = p11(vm, ents[i])[0]
        assert lo <= x <= hi, \
            "dim %d left its own segment: %r not in %r" % (i, x, (lo, hi))
    print("ok  run          -> a chain's text stays in its own segment")


def test_a_crowded_run_is_staggered_not_shuffled():
    """The headline of this pass.  Four segments 30 wide with text 40
    wide: there is nowhere ALONG the track to go, because every text
    overhangs its own segment whatever it does.  So the run staggers --
    every other dimension stands a row further off the work, its own
    dimension line with it -- and every text stays centred where it
    belongs."""
    vm = newvm()
    ents = chain(vm, [0, 30, 60, 90, 120],
                 texts=['WIDE-TEXT-A', 'WIDE-TEXT-B', 'WIDE-TEXT-C',
                        'WIDE-TEXT-D'])
    before = [p11(vm, e) for e in ents]
    run(vm, 'c:CLEARDIM', [None, None], 'staggered')
    rows = [dimline_y(vm, e) for e in ents]
    assert rows[0] == rows[2] and rows[1] == rows[3] and rows[0] != rows[1], \
        "expected an alternating stagger, got dimension lines at %r" % (rows,)
    assert rows[1] > rows[0], "it staggered toward the work, not away"
    # and nothing shuffled along: every text is still centred in its own
    # segment, which is the whole point of staggering instead
    for i, e in enumerate(ents):
        assert p11(vm, e)[0] == before[i][0], \
            "dim %d shuffled along instead of staggering: %r -> %r" \
            % (i, before[i], p11(vm, e))
    assert 'further off the work' in said(vm), said(vm)
    print("ok  stagger      -> a crowded run staggers, and nothing "
          "shuffles along")


def test_the_whole_run_moves_together_off_an_object():
    """An object across a whole segment cannot be slid round, and moving
    one dimension off it and leaving its neighbours behind would trade a
    crowded dimension for a crooked run.  So the whole run goes."""
    vm = newvm()
    ents = chain(vm, [0, 100, 200, 300, 400],
                 texts=['100', '100', '100', '100'])
    for x in range(95, 210, 3):               # a wall across segment 1
        line(vm, (float(x), 10.0), (float(x), 31.0))
    before = [dimline_y(vm, e) for e in ents]
    run(vm, 'c:CLEARDIM', [None, None], 'whole run out')
    after = [dimline_y(vm, e) for e in ents]
    assert len(set(after)) == 1, \
        "the run came out crooked: dimension lines at %r" % (after,)
    assert after[0] > before[0], "it did not stand off the work at all"
    print("ok  run move     -> an object takes the whole run out with it, "
          "and it stays straight")


def test_a_run_mates_own_skeleton_is_not_in_its_way():
    """A run is one dimension with breaks, so its dimension line and its
    extension lines are ITS OWN -- a continued chain does not merely
    have extension lines near each other, it shares them.  Without this
    a staggered run has nowhere to go: the step of the line and the
    lengthened extension lines land on the neighbour's text."""
    vm = newvm()
    chain(vm, [0, 100, 200])
    vm.loads('(setq RECS (cd:records (ssget "_X")) RUNS (cd:runs RECS))')
    vm.loads('(setq OBS (cd:static-obs (ssget "_X") RECS RUNS))')
    # every tag a run's own ink carries names both members
    tags = [o[0] for o in vm.loads('OBS') if o[0] not in (None, NIL)]
    assert tags, 'no tagged ink at all'
    for t in tags:
        assert isinstance(t, list) and sorted(t) == [0, 1], t
    print("ok  run ink      -> a run's whole skeleton is the run's own")


def test_staggering_can_be_turned_off():
    vm = newvm()
    vm.loads('(setq cd:*stagger* nil)')
    ents = chain(vm, [0, 30, 60, 90],
                 texts=['WIDE-TEXT-A', 'WIDE-TEXT-B', 'WIDE-TEXT-C'])
    run(vm, 'c:CLEARDIM', [None, None], 'no stagger')
    rows = [dimline_y(vm, e) for e in ents]
    assert len(set(rows)) == 1, \
        "cd:*stagger* nil should keep the run dead straight: %r" % (rows,)
    print("ok  knob         -> cd:*stagger* nil keeps a run dead straight")


def test_a_row_is_measured_in_text_heights():
    vm = newvm()
    ents = chain(vm, [0, 30, 60, 90, 120],
                 texts=['WIDE-TEXT-A', 'WIDE-TEXT-B', 'WIDE-TEXT-C',
                        'WIDE-TEXT-D'])
    vm.loads('(setq cd:*row-f* 3.0)')
    before = dimline_y(vm, ents[1])
    run(vm, 'c:CLEARDIM', [None, None], 'row size')
    assert abs((dimline_y(vm, ents[1]) - before) - 3.0 * TXT) < 1e-6, \
        "a row is cd:*row-f* text heights: %r" % (dimline_y(vm, ents[1]),)
    print("ok  knob         -> cd:*row-f* is how far one row out is")


def test_a_lone_dimension_is_not_held_to_its_span():
    """The span bound is a RUN rule.  A dimension on its own puts its
    text outside its extension lines the way AutoCAD does, which is what
    a short dimension with wide text looks like."""
    vm = newvm()
    a = dim(vm, (0, 0), (40, 0), (0, 20), (20, 21), text='A-TEXT')
    for x in range(2, 39, 2):
        line(vm, (x, 18), (x, 24))
    run(vm, 'c:CLEARDIM', [None, None], 'lone dim')
    x = p11(vm, a)[0]
    assert x < 0 or x > 40, \
        "a lone dimension may leave its own span: %r" % (x,)
    print("ok  run          -> a lone dimension is not held to its span")


def test_the_crossing_cross_dims_that_this_tool_failed_on():
    """The regression this whole text-measurement pass exists for.

    Model space of the drawing it came from is one rectangle with six
    dimensions on it: the four sides, and the two diagonals in the
    CROSS DIMENSIONS style whose text printed on top of itself in the
    middle.  Every number below is that drawing's, groups and all.

    CLEARDIM v2.0 answered "6 already clear - left alone".  Neither
    cross dimension's style carries a DIMTXT, so both texts measured
    0.18 units instead of 6.0 and nothing could overlap anything."""
    BL, BR = (993.0041743967485, 428.3052061602902), \
             (1350.004174396749, 428.3052061602902)
    TR, TL = (1350.287140679612, 605.8049806110844), \
             (992.7885390213107, 604.8050744361189)
    vm = VM()
    vm.load(LSP)
    vm.sysvars['LUNITS'] = 4
    vm.sysvars['LUPREC'] = 4
    # both styles keep their height on the text style, not on DIMTXT
    title = textstyle(vm, 'TITLE', height=8.0)
    romanc = textstyle(vm, 'ROMANC', height=6.0)
    dimstyle(vm, 'STANDARD', [(40, 1.5), (41, 3.0), (42, 4.5), (44, 2.25),
                              (147, 2.25), (271, 3), (277, 4), (340, title)])
    dimstyle(vm, 'CROSS DIMENSIONS', [(41, 3.9925), (42, 4.0), (44, 2.0),
                                      (73, 0), (74, 0), (147, 2.0),
                                      (271, 3), (277, 4), (340, romanc)])
    for a, b in ((BL, BR), (BR, TR), (TR, TL), (TL, BL)):
        line(vm, a, b)
    ents = {}
    for h, sty, p10, p11_, p13, p14, meas in (
            ('5B32', 'STANDARD', (1350.2315903, 625.6660140),
             (1171.4822895, 625.1660609), TL, TR, 357.5),
            ('5B33', 'STANDARD', (972.9274427, 604.7808095),
             (973.0352604, 516.5308753), BL, TL, 176.5),
            ('5B37', 'CROSS DIMENSIONS', (1348.5198089, 609.3623796),
             (1169.8783257, 520.6124924), BL, TR, 398.9452192),
            ('5B38', 'CROSS DIMENSIONS', (994.5481389, 608.3663042),
             (1173.1559565, 520.1163700), BR, TL, 398.4409788),
            ('5B3A', 'STANDARD', (1350.0041743, 417.5246032),
             (1171.5041743, 417.5246032), BL, BR, 357.0),
            ('5B3B', 'STANDARD', (1367.3305662, 605.7778103),
             (1367.1890831, 517.0279231), BR, TR, 177.5)):
        ents[h] = anydim(vm, {10: p10, 11: p11_, 13: p13, 14: p14, 42: meas},
                         33, layer='DIMENSION')
        vm.entdata[ents[h]] = ([Dot(3, sty), Dot(5, h)]
                               + [g for g in vm.entdata[ents[h]]
                                  if not (isinstance(g, Dot) and g.a == 3)])

    # the heights and the strings the dimensions' own blocks carry
    vm.loads('(setq SS (ssget "_X") RECS (cd:records SS))')
    heights = [round(vm.loads('(cd:r-h (nth %d RECS))' % i), 4)
               for i in range(6)]
    assert heights == [8.0, 8.0, 6.0, 6.0, 8.0, 8.0], heights

    before = {h: p11(vm, e) for h, e in ents.items()}
    run(vm, 'c:CLEARDIM', [None, None], 'the failing drawing')
    moved = sorted(h for h, e in ents.items() if p11(vm, e) != before[h])
    assert moved == ['5B37', '5B38'], \
        "the two cross dims are the ones that had to move, and only them: %r" \
        % (moved,)
    assert '4 already clear' in said(vm), said(vm)
    # and they came apart: their boxes no longer touch
    a, b = p11(vm, ents['5B37']), p11(vm, ents['5B38'])
    assert math.dist(a, b) > 40.0, \
        "they are still on top of each other: %r %r" % (a, b)
    print("ok  regression   -> the crossing cross dims come apart, and "
          "the four sides stay")


def test_an_unreadable_track_is_skipped_and_still_blocks():
    """A dimension whose track cannot be read off it is left exactly as
    drawn -- a track guessed wrong does not move text along the
    dimension, it moves it off it.  Its text is still ink.

    The angular dimension here carries no vertex and no arc point, which
    is what a hand-built entity looks like; AutoCAD writes both."""
    vm = newvm()
    a = dim(vm, (0, 0), (100, 0), (0, 20), (50, 26), text='A-TEXT')
    g = dim(vm, (0, 50), (100, 50), (0, 36), (50, 28), text='ANGLE', flags=2)
    run(vm, 'c:CLEARDIM', [None, None], 'unreadable track')
    assert p11(vm, g) == (50.0, 28.0), \
        "a dimension whose track could not be read was moved anyway"
    assert p11(vm, a) != (50.0, 26.0), \
        "the unreadable dimension's text did not block the linear one"
    assert 'track could not be read' in said(vm), said(vm)
    print("ok  skip         -> a track that cannot be read is left alone "
          "and still blocks")


def test_two_parallel_lines_have_no_vertex():
    """A 2-line angular dimension's vertex is where its two measured
    lines cross.  Parallel lines cross nowhere, so there is no arc to
    slide round and the dimension is left alone."""
    vm = newvm()
    e = anydim(vm, {13: (0.0, 0.0), 14: (100.0, 0.0),
                    15: (0.0, 50.0), 10: (100.0, 50.0),
                    16: (50.0, 25.0), 11: (50.0, 25.0), 1: 'ANG'}, 2)
    line(vm, (45.0, 20.0), (55.0, 30.0))
    run(vm, 'c:CLEARDIM', [None, None], 'parallel lines')
    assert p11(vm, e) == (50.0, 25.0), "it invented a vertex"
    assert 'track could not be read' in said(vm), said(vm)
    print("ok  skip         -> parallel lines make no vertex, so no arc")


def test_a_vertex_that_does_not_match_the_measured_angle_is_refused():
    """The check that says the vertex really is the vertex: the sweep
    between the two rays IS the angle the dimension measures, and group
    42 is what it measured.  Points read off the wrong groups do not
    survive it."""
    vm = newvm()
    e = angdim(vm)
    # the same dimension with a measurement that its own points cannot
    # produce -- 90 degrees of geometry claiming to be 30
    vm.entdata[e] = [Dot(42, math.pi / 6)
                     if (isinstance(g, Dot) and g.a == 42) else g
                     for g in vm.entdata[e]]
    line(vm, (30.0, 30.0), (42.0, 42.0))
    run(vm, 'c:CLEARDIM', [None, None], 'vertex mismatch')
    assert 'track could not be read' in said(vm), said(vm)
    print("ok  skip         -> a vertex group 42 disagrees with is refused")


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
    # a lambda's parameter list is parenthesised too -- ((lambda (v)
    # ...) (getpoint ...)) is how LAZDIAG records an input read in place
    bodies = re.sub(r'\(lambda\s*\([^)]*\)', '(lambda', bodies)
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
    test_own_ink_splits_what_it_rides_from_what_it_merely_draws()
    test_all_of_an_arc_is_ridden_not_just_its_first_chord()
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
    test_a_fixed_height_text_style_beats_dimtxt()
    test_a_fixed_height_is_not_scaled_by_dimscale()
    test_dimtxt_still_applies_when_the_style_has_no_fixed_height()
    test_a_style_width_factor_widens_the_box()
    test_the_measurement_is_spelled_the_way_the_style_says()
    test_mtext_formatting_codes_are_not_letters()
    test_a_stacked_fraction_is_one_glyph_wide()
    test_a_toggle_code_does_not_swallow_the_line()
    test_an_mtext_split_across_chunks_is_measured_whole()
    test_an_angular_track_is_an_arc_about_the_vertex()
    test_a_two_line_angular_finds_its_vertex_by_intersection()
    test_angular_text_slides_round_the_arc_at_its_own_radius()
    test_the_text_box_turns_as_it_goes_round()
    test_upright_text_does_not_turn_with_the_arc()
    test_a_radius_track_runs_out_from_the_centre()
    test_a_diameter_is_centred_between_its_two_points()
    test_a_radial_text_slides_and_keeps_its_offset()
    test_an_ordinate_leads_along_the_axis_its_bit_says()
    test_an_ordinate_leader_travels_with_its_text()
    test_an_ordinate_never_slides_back_past_its_feature()
    test_a_radius_text_never_crosses_its_centre()
    test_a_diameter_has_no_floor_under_it()
    test_an_ordinate_with_no_leader_is_skipped()
    test_a_non_linear_dimension_with_no_text_point_is_skipped()
    test_a_line_of_dimensions_is_one_run()
    test_a_parallel_line_further_out_is_a_different_run()
    test_dimensions_too_far_apart_along_the_line_are_not_one_run()
    test_only_a_linear_dimension_joins_a_run()
    test_a_run_member_stays_inside_its_own_segment()
    test_a_crowded_run_is_staggered_not_shuffled()
    test_the_whole_run_moves_together_off_an_object()
    test_a_run_mates_own_skeleton_is_not_in_its_way()
    test_staggering_can_be_turned_off()
    test_a_row_is_measured_in_text_heights()
    test_a_lone_dimension_is_not_held_to_its_span()
    test_the_crossing_cross_dims_that_this_tool_failed_on()
    test_an_unreadable_track_is_skipped_and_still_blocks()
    test_two_parallel_lines_have_no_vertex()
    test_a_vertex_that_does_not_match_the_measured_angle_is_refused()
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
