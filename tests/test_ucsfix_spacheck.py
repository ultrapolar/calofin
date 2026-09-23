#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""SPACHECK measures a cover in the COVER'S OWN FRAME.

SPA draws along the current UCS, so a spa drawn under a UCS turned 30
degrees has a cover whose edges run at 30 degrees in World.  SPACHECK
used to measure it along World X and Y: the 84 x 60 cover's World box is
102.7 x 94.0, so both overalls "disagreed" with it, the overlap came out
4.1 instead of 3, the left overall "stood 16.2 left of the cover", and a
hinged cover's pieces and runs were measured on the slant.  A drafter
who drew in a turned UCS got a false failure from the review tool.

The frame is read off the drawing alone (spachk:cover-frame).  Its
angle, to a quarter turn: the Cover Size overalls' direction, else the
hinges', made exact by the outline's nearest edge direction (the
longest edge when there is nothing else -- never the heaviest direction,
which an octagon's diagonals can win).  Its QUARTER is not guessed from
where the overalls stand -- that is what the audit judges, and SPA's two
standoffs swapped read as a spa turned a quarter -- but taken from what
the drawing records: a DIMENSION's group 51 is the UCS it was made in
(dragging it does not change it; one made in World has none).  So every
drawing SPA made in World runs exactly HEAD's code, whatever was
dragged, erased or swapped, and the REVIEWER's UCS decides nothing; the
words "above" and "left" are the cover's own.  The Overlap reading is
held against the lap along the way that dimension measures -- SPA's
measures up the cover.  The title-block border is measured in its own
frame, and a cover or border written in a mirrored OCS reads the same.
Every scenario draws with the real SPA under vm.set_ucs (so the
LISPVM_UCS sweep leaves it alone), then runs SPACHECKSCAN under each
reviewer UCS; tests/test_spacheck.py holds the World numbers.

Run: python3 tests/test_ucsfix_spacheck.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402
from test_spacheck import add_block, border, report_text, problems  # noqa: E402

HERE = os.path.dirname(__file__)
# lispvm's _remap_root sends these to shared/parts/ when
# CALOFIN_LISP_ROOT=shared
SPA = os.path.join(HERE, '..', 'lisp', 'spa', 'SPA.LSP')
CHK = os.path.join(HERE, '..', 'lisp', 'spacheck', 'SPACHECK.lsp')

ORIGIN = (1000.0, 500.0, 0.0)
TURN = 30.0
#: the UCS the drafter reviews in: (label, origin, degrees); None = World
REVIEWERS = [('the UCS SPA drew in', ORIGIN, TURN),
             ('World', None, None),
             ('another UCS, turned 120', (-300.0, 800.0, 0.0), 120.0)]

RECT_WATER = [None, 'Coversize', 'Rectangle', None, 84.0, 60.0,
              'Yes', '90', 'No', 'Yes', 'Offset', 3.0]
HINGED = [None, 'Coversize', 'Rectangle', None, 230.0, 60.0,
          'Yes', '90', 'Yes', 'No', 'No', '4-3']
ROUND = [None, 'Coversize', 'ROund', None, 84.0, 'Yes', 'No', 'No', '4-3']
OCTAGON = [None, 'Coversize', 'OCtagon', None, 95.0, None,
           'NA', 'NA', 'NA', 'NA', 'NA', 'Yes', 'No', 'No', '4-3']

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   " + label)
    else:
        print("  FAIL " + label
              + (('  -- ' + str(detail)[:900]) if detail else ''))
        FAILS.append(label)


def put_ucs(vm, origin, deg):
    if origin is None:
        vm.set_ucs()
    else:
        vm.set_ucs(origin, math.radians(deg))


def drawn(script, origin=ORIGIN, deg=TURN, block=False, sheet=False):
    """Run the real SPA under a UCS at ORIGIN turned DEG; the VM holding
    the drawing, with the details block and a border when asked."""
    vm = VM()
    put_ucs(vm, origin, deg)
    vm.load(SPA)
    vm.run('c:SPA', script)
    if block:
        add_block(vm, 'STANDARD', '4-3')
    if sheet:
        border(vm, 422.4, 326.175)
    return vm


def review(vm, origin, deg):
    """SPACHECKSCAN over the whole drawing under the reviewer's UCS."""
    put_ucs(vm, origin, deg)
    vm.load(CHK)
    try:
        vm.run('c:SPACHECKSCAN', [None, None])
    except LispError as e:
        return 'SPACHECK FAILED: %s' % e
    return report_text(vm) or 'NO REPORT'


def data(vm, e):
    return {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}


def cover_dims(vm):
    return [e for e in vm.entities
            if e not in vm.deleted and data(vm, e).get(0) == 'DIMENSION'
            and 'Cover Size' in str(data(vm, e).get(1, ''))]


def the_overall(vm, reads):
    hits = [e for e in cover_dims(vm) if data(vm, e).get(42) == reads]
    assert len(hits) == 1, (reads, hits)
    return hits[0]


def shift_loc(vm, e, along_deg, by):
    """Move dimension E's dimension-line point (group 10) BY along the
    World direction ALONG_DEG."""
    a = math.radians(along_deg)
    for i, p in enumerate(vm.entdata[e]):
        if isinstance(p, list) and p and p[0] == 10:
            vm.entdata[e][i] = [10, p[1] + by * math.cos(a),
                                p[2] + by * math.sin(a)] + p[3:]
            return
    raise AssertionError('no group 10 on the overall')


#: spachk:cover-frame over the whole drawing, as spachk:audit calls it
FRAME_FORM = ('(spachk:cover-frame (car (spachk:outline-ents (ssget "_X") '
              'spachk:*lay-cover*)) (spachk:dims-noted (spachk:dims '
              '(ssget "_X")) spachk:*sfx-cover*) (spachk:dims (ssget "_X")) '
              '(spachk:hinge-lines (ssget "_X")))')


def frame_of(vm, origin, deg):
    """spachk:cover-frame over the drawing, read under the given UCS --
    or the error, as a value, so one broken build fails a check and not
    the run."""
    put_ucs(vm, origin, deg)
    vm.load(CHK)
    try:
        return vm.loads(FRAME_FORM)
    except LispError as e:
        return e


def lines(txt):
    return txt.replace('\\P', '\n')


def no_false_size_or_standoff(tag, txt):
    bad = problems(txt)
    check(f"{tag}: no overall 'disagrees' with the cover",
          not any('but the cover measures' in p for p in bad), bad)
    check(f"{tag}: no overall reported off its standoff",
          not any(' stands ' in p for p in bad), bad)


# ------------------------------------------------ the frame, as a helper

def the_frame_itself():
    """spachk:cover-frame answers nil -- World, every measurement as it
    always was -- for a cover square to World, and the drawing's own
    30 degrees for one SPA drew under the turned UCS, whichever UCS the
    reviewer has on."""
    form = FRAME_FORM
    vm = drawn(RECT_WATER, None, None)
    vm.load(CHK)
    try:
        fr = vm.loads(form)
    except LispError as e:
        fr = e
    check("a cover square to World: the frame is nil (World itself)",
          fr is None, fr)
    for label, origin, deg in REVIEWERS:
        vm = drawn(RECT_WATER)
        put_ucs(vm, origin, deg)
        vm.load(CHK)
        try:
            fr = vm.loads(form)
        except LispError as e:
            fr = e
        want = (math.cos(math.radians(TURN)), math.sin(math.radians(TURN)))
        check(f"drawn turned 30, read under {label}: the frame is 30 deg",
              isinstance(fr, list) and len(fr) == 2
              and abs(fr[0] - want[0]) < 1e-9 and abs(fr[1] - want[1]) < 1e-9,
              fr)


# -------------------------------------- SPA's own output passes, turned

def rectangle_with_water():
    for label, origin, deg in REVIEWERS:
        txt = review(drawn(RECT_WATER), origin, deg)
        tag = f"84 x 60 turned 30, reviewed in {label}"
        check(f"{tag}: the cover measures its true 84 x 60",
              "cover 84.0000 x 60.0000 contains water's edge "
              "78.0000 x 54.0000, OK" in txt, lines(txt))
        check(f"{tag}: the overlap reads the true 3",
              'Overlap: 3.0000, OK' in txt, lines(txt))
        no_false_size_or_standoff(tag, txt)


def hinged_cover():
    for label, origin, deg in REVIEWERS:
        txt = review(drawn(HINGED, block=True), origin, deg)
        tag = f"230 x 60, 4 hinges, turned 30, reviewed in {label}"
        for want in ('Hinges: 4 drawn, so 5 pieces (STD 4-3)',
                     'Arrangement: H V V H, matches',
                     'Foam width: widest piece 46.0000 within 48.0000, OK',
                     'Foam length: longest hinge 60.0000 within '
                     '144.0000, OK'):
            check(f"{tag}: {want}", want in txt, lines(txt))
        no_false_size_or_standoff(tag, txt)


def round_and_octagon_audit_clean():
    """The shapes with no single straight edge to read: a circle (the
    frame comes from its overall) and a regular octagon (square and
    diagonal edges weigh the same, so the overalls decide).  Both audit
    clean under the turned UCS, as they do in World."""
    for shape, script in (('round', ROUND), ('octagon', OCTAGON)):
        for label, origin, deg in REVIEWERS:
            txt = review(drawn(script, block=True, sheet=True), origin, deg)
            check(f"{shape} turned 30, reviewed in {label}: no problems",
                  problems(txt) == [], problems(txt))


def turned_past_45():
    """Drawn under a UCS turned 120: the edges give the angle only to a
    quarter turn, and the overalls say which quarter is up -- the cover
    is 84 across, not 60, reviewed from World too."""
    for label, origin, deg in (('World', None, None),
                               ('the UCS SPA drew in', ORIGIN, 120.0)):
        txt = review(drawn(RECT_WATER, deg=120.0), origin, deg)
        tag = f"84 x 60 turned 120, reviewed in {label}"
        check(f"{tag}: the cover measures 84 x 60, not 60 x 84",
              "cover 84.0000 x 60.0000 contains water's edge "
              "78.0000 x 54.0000, OK" in txt, lines(txt))
        no_false_size_or_standoff(tag, txt)


def no_overalls():
    """With the overalls erased the outline's own edges still give the
    frame."""
    vm = drawn(RECT_WATER)
    for e in cover_dims(vm):
        vm.deleted.add(e)
    txt = review(vm, None, None)
    check("turned 30, overalls erased, reviewed in World: still 84 x 60",
          "cover 84.0000 x 60.0000 contains water's edge "
          "78.0000 x 54.0000, OK" in txt, lines(txt))


# ------------------------------------ real faults are still caught, turned

def a_moved_overall_is_still_caught():
    """Above and left are the cover's own, whatever UCS the reviewer has
    on."""
    up = TURN + 90.0          # the cover's +Y, in World
    for label, origin, deg in REVIEWERS:
        vm = drawn(RECT_WATER)
        shift_loc(vm, the_overall(vm, 84.0), up, 16.0)
        bad = problems(review(vm, origin, deg))
        want = 'stands 40.0000 above the cover, SPA puts it 24.0000'
        check(f"across overall dragged 16 further out, reviewed in {label}:"
              f" '{want}'", any(want in p for p in bad), bad)
        check(f"...and the up overall, untouched, is not flagged ({label})",
              len([p for p in bad if ' stands ' in p]) == 1, bad)

        vm = drawn(RECT_WATER)
        shift_loc(vm, the_overall(vm, 60.0), TURN + 180.0, 12.0)
        bad = problems(review(vm, origin, deg))
        want = 'stands 48.0000 left of the cover, SPA puts it 36.0000'
        check(f"up overall dragged 12 further left, reviewed in {label}:"
              f" '{want}'", any(want in p for p in bad), bad)


def a_wrong_overall_reads_against_the_true_size():
    for label, origin, deg in REVIEWERS:
        vm = drawn(RECT_WATER)
        e = the_overall(vm, 84.0)
        vm.entdata[e] = [Dot(42, 80.0) if isinstance(p, Dot) and p.a == 42
                         else p for p in vm.entdata[e]]
        bad = problems(review(vm, origin, deg))
        check(f"an overall reading 80 on the 84 cover, reviewed in {label}:"
              " reported against the true 84 x 60",
              any('reads 80.0000 but the cover measures 84.0000 x 60.0000'
                  in p for p in bad), bad)


# ------------------------------------ what the frame must NOT listen to

OCT_40 = [None, 'Coversize', 'OCtagon', None, 95.0, None,
          40.0, 'NA', 'NA', 'NA', 'NA', 'Yes', 'No', 'No', '4-3']
OCT_39 = [None, 'Coversize', 'OCtagon', None, 95.0, None,
          39.375, 'NA', 'NA', 'NA', 'NA', 'Yes', 'No', 'No', '4-3']
CUT_30 = [None, 'Coversize', 'Rectangle', None, 84.0, 60.0,
          'Yes', 'Cut', 30.0, 'Yes', 'No', 'No', '4-3']
WATER_DIMS = [None, 'Coversize', 'Rectangle', None, 84.0, 60.0,
              'Yes', '90', 'No', 'Yes', 'Dims', 78.0, 56.0]
RADIUS = [None, 'Coversize', 'Rectangle', None, 84.0, 60.0,
          'Yes', 'Radius', 12.0, 'No', 'No']


def diagonals_do_not_set_the_frame():
    """An octagon whose corner faces are longer than its square faces,
    and a rectangle with 30 inch cuts, have more edge length on the
    diagonals than on the square sides.  The frame follows the overalls,
    not the heavier edge direction -- drawn in World, SPA's output must
    audit clean exactly as it does on HEAD, and the same drawn turned."""
    for shape, script in (('octagon, 40 faces', OCT_40),
                          ('octagon, 39.375 faces', OCT_39),
                          ('84 x 60, corners cut 30', CUT_30)):
        for label, draw, rev in (('drawn in World, reviewed in World',
                                  (None, None), (None, None)),
                                 ('drawn turned 30, reviewed in World',
                                  (ORIGIN, TURN), (None, None)),
                                 ('drawn turned 30, reviewed in its UCS',
                                  (ORIGIN, TURN), (ORIGIN, TURN))):
            txt = review(drawn(script, draw[0], draw[1],
                               block=True, sheet=True), *rev)
            check(f"{shape}, {label}: no problems",
                  problems(txt) == [], problems(txt))


def dragged(turn):
    """Drag the across overall 16 further out and the up overall 12
    further out, along the cover's own axes turned TURN degrees."""
    def go(vm):
        shift_loc(vm, the_overall(vm, 84.0), turn + 90.0, 16.0)
        shift_loc(vm, the_overall(vm, 60.0), turn + 180.0, 12.0)
    return go


def the_reviewers_ucs_decides_nothing():
    """Both overalls dragged off their standoffs: the report must flag
    both, word for word the same, whatever UCS the sheet is reviewed in
    -- and for a cover square to World that is HEAD's report, frame
    nil."""
    for draw in (None, 60.0, 200.0):
        for rev in (None, 0.0, 90.0, 180.0, 270.0):
            if rev == 0.0 and draw is None:
                continue
            vm = drawn(RECT_WATER, None if draw is None else ORIGIN, draw)
            dragged(draw or 0.0)(vm)
            revo = None if rev is None else (-300.0, 800.0, 0.0)
            txt = review(vm, revo, rev)
            bad = problems(txt)
            tag = ("drawn in World" if draw is None
                   else f"drawn turned {draw:g}") + ", both overalls " \
                "dragged, reviewed " + ("in World" if rev is None
                                        else f"in a UCS turned {rev:g}")
            want = ('stands 40.0000 above the cover, SPA puts it 24.0000',
                    'stands 48.0000 left of the cover, SPA puts it 36.0000')
            check(f"{tag}: both standoffs reported, in the cover's words",
                  all(any(w in p for p in bad) for w in want)
                  and len([p for p in bad if ' stands ' in p]) == 2, bad)
            check(f"{tag}: the cover is 84 x 60",
                  "cover 84.0000 x 60.0000 contains" in txt, lines(txt))

    form = FRAME_FORM
    for rev in (90.0, 180.0, 270.0):
        vm = drawn(RECT_WATER, None, None)
        dragged(0.0)(vm)
        fr = frame_of(vm, (-300.0, 800.0, 0.0), rev)
        check(f"drawn in World, dragged, read in a UCS turned {rev:g}: "
              "the frame is nil, World", fr is None, fr)

    # a water's edge that laps 3 across and 2 up, overalls dragged: one
    # Overlap verdict, whoever opens it (SPA's Overlap dim reads the up
    # lap -- the verdict is HEAD's World one, not this change's to settle)
    verdicts = set()
    for draw in (None, 60.0):
        for rev in (None, 60.0, 90.0):
            vm = drawn(WATER_DIMS, None if draw is None else ORIGIN, draw)
            dragged(draw or 0.0)(vm)
            txt = review(vm, None if rev is None else (-300.0, 800.0, 0.0),
                         rev)
            verdicts |= {p.strip() for p in txt.replace('\\P', '\n')
                         .replace('{', ' ').replace('}', ' ').split('\n')
                         if 'Overlap:' in p}
    check("a 78 x 56 water's edge, overalls dragged, gets one Overlap "
          "verdict: drawn in World or turned 60, reviewed in World, its "
          "UCS or one turned 90",
          len(verdicts) == 1, verdicts)


# --------------------------------------- the sheet border, and the OCS

def turned_border(vm, lines_only=False):
    """A 422.4 x 326.175 border around the spa, drawn in the same turned
    UCS -- World numbers, as the drawing holds them."""
    c, s = math.cos(math.radians(TURN)), math.sin(math.radians(TURN))
    corners = []
    for x, y in ((-160.0, -120.0), (262.4, -120.0),
                 (262.4, 206.175), (-160.0, 206.175)):
        corners.append((ORIGIN[0] + x * c - y * s, ORIGIN[1] + x * s + y * c))
    if lines_only:
        # a LINE needs its layer to exist first; the polyline makes it
        vm.loads("(entmake (list '(0 . \"LAYER\") '(2 . \"border\") "
                 "'(70 . 0) '(62 . 7) '(6 . \"Continuous\")))")
        for i in range(4):
            p, q = corners[i], corners[(i + 1) % 4]
            vm.loads(f"(entmake (list '(0 . \"LINE\") '(8 . \"border\") "
                     f"(list 10 {p[0]} {p[1]} 0.0) "
                     f"(list 11 {q[0]} {q[1]} 0.0)))")
    else:
        pts = ' '.join(f"(list 10 {x} {y}) '(42 . 0.0)" for x, y in corners)
        vm.loads("(entmake (list '(0 . \"LWPOLYLINE\") '(100 . \"AcDbEntity\")"
                 " '(8 . \"border\") '(100 . \"AcDbPolyline\") '(90 . 4)"
                 f" '(70 . 1) {pts}))")


def a_turned_sheet_border():
    """A whole sheet drawn in the turned UCS -- spa and title-block
    border both -- is a 0.6x title block, not a STRETCHED 528.9 x 493.7
    World box; as one polyline or as four lines."""
    for how, lines_only in (('one polyline', False), ('four lines', True)):
        for label, origin, deg in REVIEWERS[:2]:
            vm = drawn(ROUND, block=True)
            turned_border(vm, lines_only)
            txt = review(vm, origin, deg)
            check(f"round and border ({how}) turned 30, reviewed in {label}:"
                  " no problems, the title block OK",
                  problems(txt) == [] and '0.60x the liner block, OK' in txt,
                  problems(txt))


def mirror_ocs(vm, e):
    """Rewrite entity E in the OCS of extrusion 0,0,-1 -- the same shape
    in World, X running backwards in its own numbers, bulges reversed."""
    out = []
    for p in vm.entdata[e]:
        if isinstance(p, list) and p and p[0] == 10:
            out.append([10, -p[1], p[2]] + [-z for z in p[3:]])
        elif isinstance(p, Dot) and p.a == 42:
            out.append(Dot(42, -p.b))
        else:
            out.append(p)
    vm.entdata[e] = out + [[210, 0.0, 0.0, -1.0]]


def cover_outline(vm):
    hits = [e for e in vm.entities if e not in vm.deleted
            and data(vm, e).get(8) == 'COVER'
            and data(vm, e).get(0) in ('LWPOLYLINE', 'CIRCLE')]
    assert len(hits) == 1, hits
    return hits[0]


def a_mirrored_ocs_cover():
    """Group 10 of a LWPOLYLINE or CIRCLE is in its OBJECT coordinates:
    under extrusion 0,0,-1 X runs backwards.  The same cover written that
    way measures the same -- radius corners (bulges) included."""
    for shape, script, extra in (('84 x 60 with radius corners', RADIUS,
                                  False),
                                 ('round', ROUND, True)):
        for label, origin, deg in REVIEWERS[:2]:
            vm = drawn(script, block=extra, sheet=extra)
            mirror_ocs(vm, cover_outline(vm))
            txt = review(vm, origin, deg)
            bad = problems(txt)
            check(f"{shape} turned 30, its cover in a mirrored OCS, reviewed"
                  f" in {label}: no false size or standoff",
                  not any('but the cover measures' in p or ' stands ' in p
                          or 'Foam' in p for p in bad), bad)
            if extra:
                check(f"...and the round one audits clean ({label})",
                      bad == [], bad)


# --------------------------- a correct overall is never outvoted (review 2)

def moved_to(vm, reads, turn, along, by):
    """Shift the overall reading READS by BY along the cover's own
    direction TURN + ALONG degrees."""
    shift_loc(vm, the_overall(vm, reads), turn + along, by)


def a_correct_overall_is_never_outvoted():
    """Meeting SPA's standoff decides the quarter; the side at any
    distance only breaks a tie.  Weighting the across double turned
    World drawings a quarter turn whenever the across was not above the
    cover, and flagged the one overall standing where SPA put it.  Each
    of these is silent on HEAD (the moved overall is on no side SPA
    uses) and must stay silent, 84 x 60, drawn in World or turned 30."""
    cases = [
        ('only the up overall (across erased)',
         RECT_WATER, lambda vm, t: vm.deleted.add(the_overall(vm, 84.0))),
        ('across moved 24 below the cover, up at 36 left',
         RECT_WATER, lambda vm, t: moved_to(vm, 84.0, t, -90.0, 108.0)),
        ('the 230 x 60 hinged cover, across moved 24 below',
         HINGED, lambda vm, t: moved_to(vm, 230.0, t, -90.0, 108.0)),
        ('up moved to stand 36 right, across at 24 above',
         RECT_WATER, lambda vm, t: moved_to(vm, 60.0, t, 0.0, 156.0)),
    ]
    for label, script, damage in cases:
        for how, draw, rev in (('drawn in World', (None, None), (None, None)),
                               ('drawn turned 30, reviewed in World',
                                (ORIGIN, TURN), (None, None)),
                               ('drawn turned 30, reviewed in its UCS',
                                (ORIGIN, TURN), (ORIGIN, TURN))):
            vm = drawn(script, *draw, block=script is HINGED)
            damage(vm, draw[1] or 0.0)
            txt = review(vm, *rev)
            bad = problems(txt)
            check(f"{label}, {how}: no standoff or foam row",
                  not any(' stands ' in p or 'Foam width' in p
                          for p in bad), bad)
            if script is RECT_WATER:
                check(f"{label}, {how}: the cover is 84 x 60",
                      "cover 84.0000 x 60.0000 contains" in txt, lines(txt))


def the_far_sides_are_judged_as_head():
    """Overalls at 12 on the FAR sides -- below and right, in the cover's
    own frame -- stand on no side SPA uses, and HEAD says nothing about
    them.  A World drawing still runs HEAD's code whatever was dragged,
    so it says nothing; the same drawn turned 30 is read in ITS frame
    (group 51), not re-imagined as a spa turned round, and says the same
    nothing -- no 'above' or 'left' for a frame it was not drawn in."""
    for how, draw, rev in (('drawn in World', (None, None), (None, None)),
                           ('drawn turned 30, reviewed in World',
                            (ORIGIN, TURN), (None, None)),
                           ('drawn turned 30, reviewed in its UCS',
                            (ORIGIN, TURN), (ORIGIN, TURN))):
        vm = drawn(RECT_WATER, *draw)
        t = draw[1] or 0.0
        moved_to(vm, 84.0, t, -90.0, 96.0)       # 24 above -> 12 below
        moved_to(vm, 60.0, t, 0.0, 132.0)        # 36 left  -> 12 right
        txt = review(vm, *rev)
        bad = problems(txt)
        check(f"far sides, {how}: no standoff row, as HEAD, and 84 x 60",
              not any(' stands ' in p for p in bad)
              and "cover 84.0000 x 60.0000 contains" in txt, bad)


def the_overlap_reads_the_way_it_measures():
    """SPA dimensions the lap at the BOTTOM of the cover -- up it -- so a
    78 x 56 water's edge in an 84 x 60 cover reads 2, the up lap; HEAD
    held it against the across lap, 3, and failed SPA's own drawing."""
    for how, draw, rev in (('drawn in World', (None, None), (None, None)),
                           ('drawn turned 30, reviewed in World',
                            (ORIGIN, TURN), (None, None)),
                           ('drawn turned 30, reviewed in its UCS',
                            (ORIGIN, TURN), (ORIGIN, TURN))):
        txt = review(drawn(WATER_DIMS, *draw), *rev)
        check(f"78 x 56 water's edge, {how}: 'Overlap: 2.0000, OK'",
              'Overlap: 2.0000, OK' in txt
              and not any('Overlap' in p for p in problems(txt)),
              problems(txt))
        vm = drawn(WATER_DIMS, *draw)
        lap = [e for e in vm.entities if e not in vm.deleted
               and 'Overlap' in str(data(vm, e).get(1, ''))]
        vm.entdata[lap[0]] = [Dot(42, 3.0) if isinstance(p, Dot)
                              and p.a == 42 else p
                              for p in vm.entdata[lap[0]]]
        bad = problems(review(vm, *rev))
        check(f"...and one reading 3 is caught ({how})",
              any("Overlap: reads 3.0000 but the cover laps the water's "
                  "edge by 2.0000" in p for p in bad), bad)


# ------------------ the quarter comes from what the drawing records (51)

SQUARE = [None, 'Coversize', 'Rectangle', None, 84.0, 84.0,
          'Yes', '90', 'No', 'Yes', 'Offset', 3.0]
#: where a scenario is drawn and reviewed: (label, draw, review)
RECORDED = [('drawn in World', (None, None), (None, None)),
            ('drawn turned 30, reviewed in World', (ORIGIN, 30.0),
             (None, None)),
            ('drawn turned 30, reviewed in its UCS', (ORIGIN, 30.0),
             (ORIGIN, 30.0)),
            ('drawn turned 60, reviewed in World', (ORIGIN, 60.0),
             (None, None)),
            ('drawn turned 60, reviewed in its UCS', (ORIGIN, 60.0),
             (ORIGIN, 60.0))]


def overall_along(vm, turn, up):
    """The Cover Size overall measuring up (UP) or across the cover drawn
    turned TURN -- for a square cover, whose two both read 84."""
    want = math.radians(turn + (90.0 if up else 0.0))
    hits = []
    for e in cover_dims(vm):
        d = {p[0]: p[1:] for p in vm.entdata[e] if isinstance(p, list)}
        a = math.atan2(d[14][1] - d[13][1], d[14][0] - d[13][0])
        if abs(math.sin(a - want)) < 1e-6:
            hits.append(e)
    assert len(hits) == 1, hits
    return hits[0]




def same_frame(fr, deg):
    return (isinstance(fr, list) and len(fr) == 2
            and abs(fr[0] - math.cos(math.radians(deg))) < 1e-9
            and abs(fr[1] - math.sin(math.radians(deg))) < 1e-9)


def swapped_standoffs_are_both_reported():
    """SPA's two standoffs swapped -- the across 36 above, the up 24 left
    -- is the likeliest misplacement.  Guessing the quarter from where
    the overalls stand read it as a spa turned a quarter, dropped both
    failures and measured the cover 60 x 84.  HEAD reports both, and so
    must a turned drawing."""
    for how, draw, rev in RECORDED:
        vm = drawn(RECT_WATER, *draw)
        t = draw[1] or 0.0
        moved_to(vm, 84.0, t, 90.0, 12.0)        # across 24 -> 36 above
        moved_to(vm, 60.0, t, 0.0, 12.0)         # up 36 -> 24 left
        txt = review(vm, *rev)
        bad = problems(txt)
        for want in ('stands 36.0000 above the cover, SPA puts it 24.0000',
                     'stands 24.0000 left of the cover, SPA puts it 36.0000'):
            check(f"standoffs swapped, {how}: '{want}'",
                  any(want in p for p in bad), bad)
        check(f"standoffs swapped, {how}: the cover is 84 x 60",
              "cover 84.0000 x 60.0000 contains" in txt, lines(txt))


def a_lone_across_near_36_is_reported():
    """The last overall an across dragged to 34-38 above -- the up erased,
    or a round cover's only overall -- is flagged against SPA's 24."""
    for how, draw, rev in RECORDED[:3]:
        t = draw[1] or 0.0
        for at in (34.0, 36.0, 38.0):
            vm = drawn(RECT_WATER, *draw)
            vm.deleted.add(the_overall(vm, 60.0))
            moved_to(vm, 84.0, t, 90.0, at - 24.0)
            txt = review(vm, *rev)
            want = f'stands {at:.4f} above the cover, SPA puts it 24.0000'
            check(f"lone across at {at:g}, {how}: '{want}'",
                  any(want in p for p in problems(txt)), problems(txt))
            check(f"lone across at {at:g}, {how}: the cover is 84 x 60",
                  "cover 84.0000 x 60.0000 contains" in txt, lines(txt))
        vm = drawn(ROUND, *draw, block=True, sheet=True)
        moved_to(vm, 84.0, t, 90.0, 12.0)
        bad = problems(review(vm, *rev))
        want = 'stands 36.0000 above the cover, SPA puts it 24.0000'
        check(f"round's only overall at 36, {how}: '{want}', and nothing else",
              len(bad) == 1 and want in bad[0], bad)


def a_square_covers_up_overall_is_held_to_36():
    """An 84 x 84 cover's two overalls read the same, so nothing but the
    recorded UCS says which is the up one: dragged to 50 left it must be
    held to SPA's 36, not re-read as an across held to 24."""
    for how, draw, rev in RECORDED[1:]:
        t = draw[1]
        vm = drawn(SQUARE, *draw)
        shift_loc(vm, overall_along(vm, t, True), t + 180.0, 14.0)
        bad = problems(review(vm, *rev))
        want = 'stands 50.0000 left of the cover, SPA puts it 36.0000'
        check(f"84 x 84, up overall at 50, {how}: '{want}'",
              any(want in p for p in bad)
              and len([p for p in bad if ' stands ' in p]) == 1, bad)


def all_dims_dragged_and_swapped_still_frame_by_51():
    """Every overall dragged far and onto the other's side: where they
    stand says nothing trustworthy, and the frame is still the UCS the
    dimensions were made in."""
    for how, draw, rev in RECORDED[1:]:
        t = draw[1]
        vm = drawn(RECT_WATER, *draw)
        across, up = the_overall(vm, 84.0), the_overall(vm, 60.0)
        shift_loc(vm, across, t + 180.0, 200.0)   # far out to the left
        shift_loc(vm, across, t - 90.0, 60.0)     # ...and down beside it
        shift_loc(vm, up, t + 90.0, 200.0)        # far out above
        shift_loc(vm, up, t, 70.0)                # ...and over the top
        txt = review(vm, *rev)
        check(f"all overalls dragged and swapped, {how}: 84 x 60, and both"
              " reported",
              "cover 84.0000 x 60.0000 contains" in txt
              and len([p for p in problems(txt) if ' stands ' in p]) == 2,
              problems(txt))
        vm = drawn(RECT_WATER, *draw)
        across, up = the_overall(vm, 84.0), the_overall(vm, 60.0)
        shift_loc(vm, across, t + 180.0, 200.0)
        shift_loc(vm, up, t + 90.0, 200.0)
        fr = frame_of(vm, *rev)
        check(f"all overalls dragged and swapped, {how}: framed at {t:g}",
              same_frame(fr, t), fr)


def a_turned_cover_with_no_dimensions():
    """No dimension at all records the UCS, so the quarter is the one
    nearest World.  Drawn at 30 that is right; drawn at 60 it is the
    quarter at -30, and the cover reads 60 x 84 -- pinned here as the
    known limit: with nothing in the drawing to say it was turned 60
    rather than -30, nothing can."""
    for deg, fdeg, size in ((30.0, 30.0, "cover 84.0000 x 60.0000 contains"
                             " water's edge 78.0000 x 54.0000"),
                            (60.0, -30.0, "cover 60.0000 x 84.0000 contains"
                             " water's edge 54.0000 x 78.0000")):
        vm = drawn(RECT_WATER, ORIGIN, deg)
        for e in list(vm.entities):
            if data(vm, e).get(0) == 'DIMENSION':
                vm.deleted.add(e)
        txt = review(vm, None, None)
        check(f"no dimensions, drawn turned {deg:g}: '{size}'",
              size in txt, lines(txt))
        vm = drawn(RECT_WATER, ORIGIN, deg)
        for e in list(vm.entities):
            if data(vm, e).get(0) == 'DIMENSION':
                vm.deleted.add(e)
        fr = frame_of(vm, None, None)
        check(f"no dimensions, drawn turned {deg:g}: framed at {fdeg:g}",
              same_frame(fr, fdeg), fr)


# ------------------- a tied vote, and hinges with nothing else (review 4)

def remade_in_world(vm, e):
    """Dimension E as if re-made by hand in World: no group 51."""
    vm.entdata[e] = [p for p in vm.entdata[e]
                     if not (isinstance(p, Dot) and p.a == 51)]


def undimensioned(vm):
    for e in list(vm.entities):
        if data(vm, e).get(0) == 'DIMENSION':
            vm.deleted.add(e)


def an_overall_remade_in_world_does_not_win_a_tie():
    """SPA drew it turned; the up overall was then re-made by hand in
    World, so the overalls vote one turned, one World.  The other SPA
    dimensions -- Water's Edge, Overlap, corner marks -- carry the
    drawing's turn and break the tie; a World-made dimension is the edit,
    not the original."""
    for deg in (60.0, 120.0, 200.0):
        vm = drawn(RECT_WATER, ORIGIN, deg)
        remade_in_world(vm, the_overall(vm, 60.0))
        shift_loc(vm, the_overall(vm, 84.0), deg + 90.0, 16.0)
        txt = review(vm, None, None)
        bad = problems(txt)
        check(f"drawn turned {deg:g}, up overall re-made in World: 84 x 60",
              "cover 84.0000 x 60.0000 contains" in txt, lines(txt))
        check(f"...the across dragged 16 is reported, and only it ({deg:g})",
              any('stands 40.0000 above the cover, SPA puts it 24.0000' in p
                  for p in bad)
              and len([p for p in bad if ' stands ' in p]) == 1, bad)
        fr = frame_of(vm, None, None)
        check(f"...framed at {deg:g}", same_frame(fr, deg), fr)
    vm = drawn(HINGED, ORIGIN, 60.0, block=True)
    remade_in_world(vm, the_overall(vm, 60.0))
    txt = review(vm, None, None)
    for want in ('Foam length: longest hinge 60.0000 within 144.0000, OK',
                 'Foam width: widest piece 46.0000 within 48.0000, OK'):
        check(f"hinged, drawn turned 60, up overall re-made in World: "
              f"'{want}'", want in txt, lines(txt))
    check("...and no standoff row (hinged at 60)",
          not any(' stands ' in p for p in problems(txt)), problems(txt))


def hinges_run_up_the_cover_with_no_dimensions():
    """Every dimension erased: nothing records the UCS, but the hinges
    still run up the cover, and the quarter must have them do so -- not
    a longest hinge of 0 and a 60 inch "piece"."""
    for deg in (60.0, 120.0):
        vm = drawn(HINGED, ORIGIN, deg, block=True)
        undimensioned(vm)
        txt = review(vm, None, None)
        for want in ('Hinges: 4 drawn, so 5 pieces (STD 4-3)',
                     'Foam length: longest hinge 60.0000 within 144.0000, OK',
                     'Foam width: widest piece 46.0000 within 48.0000, OK'):
            check(f"hinged, drawn turned {deg:g}, no dimensions: '{want}'",
                  want in txt, lines(txt))


the_frame_itself()
rectangle_with_water()
hinged_cover()
round_and_octagon_audit_clean()
turned_past_45()
no_overalls()
a_moved_overall_is_still_caught()
a_wrong_overall_reads_against_the_true_size()
diagonals_do_not_set_the_frame()
the_reviewers_ucs_decides_nothing()
a_turned_sheet_border()
a_mirrored_ocs_cover()
a_correct_overall_is_never_outvoted()
the_far_sides_are_judged_as_head()
the_overlap_reads_the_way_it_measures()
swapped_standoffs_are_both_reported()
a_lone_across_near_36_is_reported()
a_square_covers_up_overall_is_held_to_36()
all_dims_dragged_and_swapped_still_frame_by_51()
a_turned_cover_with_no_dimensions()
an_overall_remade_in_world_does_not_win_a_tie()
hinges_run_up_the_cover_with_no_dimensions()

if FAILS:
    print(f"\ntest_ucsfix_spacheck: {len(FAILS)} FAILURE(S): "
          + '; '.join(FAILS))
    sys.exit(1)
print("\ntest_ucsfix_spacheck: all checks passed")
