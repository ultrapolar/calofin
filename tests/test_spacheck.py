"""Runtime tests for SPACHECK: build a spa drawing by running the REAL
SPA.LSP in the VM, then run the REAL SPACHECK over that same drawing and
check what it reports.

This is the audit's own end-to-end proof: a drawing SPA produced must
come back clean, and a drawing damaged in a specific way must come back
naming that damage.

Script values: numbers answer distance prompts, strings answer keyword
prompts, None is Enter.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
SPA = os.path.join(HERE, '..', 'lisp', 'spa', 'SPA.LSP')
CHK = os.path.join(HERE, '..', 'lisp', 'spacheck', 'SPACHECK.lsp')


def build(script, label='spa'):
    """Run SPA to produce a drawing; return the VM holding it."""
    vm = VM()
    vm.load(SPA)
    try:
        vm.run('c:SPA', script)
    except LispError as e:
        raise AssertionError(f"[{label}] SPA failed: {e}") from None
    return vm


BLOCK = '''
  (setq blk (entmakex (list '(0 . "INSERT") '(8 . "0")
                            '(2 . "Spa Cover Details")
                            '(10 0.0 300.0) '(66 . 1))))
  (entmake (list '(0 . "ATTRIB") '(8 . "0") '(2 . "GRADE")
                 (cons 1 (strcat "GRADE: " GR))))
  (entmake (list '(0 . "ATTRIB") '(8 . "0") '(2 . "TAPER")
                 (cons 1 (strcat "TAPER: " TP))))
  (entmake (list '(0 . "SEQEND") '(8 . "0")))'''


def add_block(vm, grade, taper):
    """Put a Spa Cover Details block in the drawing, attributes and all,
    and hand back its ename."""
    vm.loads(f'(setq GR "{grade}" TP "{taper}")')
    vm.loads(BLOCK)
    return vm.globals['blk']


def border(vm, w, h):
    """A title-block border rectangle on the border layer."""
    vm.loads(f'''
      (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                     '(8 . "border") '(100 . "AcDbPolyline")
                     '(90 . 4) '(70 . 1)
                     '(10 0.0 0.0) '(42 . 0.0)
                     (list 10 {w} 0.0) '(42 . 0.0)
                     (list 10 {w} {h}) '(42 . 0.0)
                     (list 10 0.0 {h}) '(42 . 0.0)))''')


def mtext_of(vm, e):
    """An MTEXT's full text, reassembled the way AutoCAD stores it: the
    leading 250-character group 3 chunks, then the group 1 tail."""
    head, tail = [], ''
    for p in vm.entdata[e]:
        if isinstance(p, Dot):
            if p.a == 3:
                head.append(p.b)
            elif p.a == 1 and not tail:
                tail = p.b
    return ''.join(head) + tail


def report_text(vm):
    """The SPACHECK report MTEXT in the drawing, or None."""
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}
        if d.get(0) == 'MTEXT' and d.get(8) == 'SPACHECK-REPORT':
            return mtext_of(vm, e)
    return None


def report_of(vm, cmd='c:SPACHECKSCAN', script=None):
    """Load SPACHECK into the same VM and run it; return the report text."""
    vm.load(CHK)
    try:
        vm.run(cmd, script if script is not None else [None])
    except LispError as e:
        raise AssertionError(f"SPACHECK failed: {e}") from None
    txt = report_text(vm)
    if txt is None:
        raise AssertionError("SPACHECK wrote no report")
    return txt


def problems(txt):
    """The report lines SPACHECK marked as problems (colour 1)."""
    out = []
    for chunk in txt.split('\\P'):
        if chunk.startswith('{\\C1;'):
            out.append(chunk[5:].rstrip('}'))
    return out


# ---------------------------------------------------------- the basics

def test_loads_and_reports():
    """SPACHECK runs over a SPA drawing and writes a report."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    assert 'SPACHECKSCAN REPORT' in txt, txt[:200]
    assert 'SPACHECK v' in txt


def test_finds_the_cover_outline():
    """The bounded cover outline SPA draws is recognised as one closed
    entity, not reported as missing or loose."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    assert 'Cover outline: one closed LWPOLYLINE, OK' in txt, txt


def test_round_cover_is_a_bounded_circle():
    vm = build([None, 'Coversize', 'ROund', None, 84.0, 'No', 'No'])
    txt = report_of(vm)
    assert 'Cover outline: one closed CIRCLE, OK' in txt, txt


def test_water_edge_nesting_passes():
    """Both outlines drawn: the water's edge is inside the cover."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None,
                'Yes', 'Offset', 3.0, 'No'])
    txt = report_of(vm)
    assert 'contains water' in txt, txt
    assert not any('NOT INSIDE' in p for p in problems(txt)), problems(txt)


def test_one_outline_is_not_a_problem():
    """A drawing that shows the cover only is legitimate."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    assert "Water's edge: not drawn" in txt, txt
    assert not any("Water's edge" in p and 'NO OUTLINE' in p
                   for p in problems(txt))


# ------------------------------------------------------ the dimensions

def test_radius_corners_still_measure_the_overall():
    """A filleted rectangle is one polyline whose corners are bulged arc
    segments.  Its extents must still come out 84 x 60, or every overall
    on a radiused spa would be reported as disagreeing with its cover."""
    vm = build([None, 'Coversize', 'Rectangle', None, 84.0, 60.0,
                'Radius', 12.0, None, None, None, None, None, None,
                'No', 'No'])
    txt = report_of(vm)
    assert 'Cover outline: one closed LWPOLYLINE, OK' in txt, txt
    bad = problems(txt)
    assert not any('but the cover measures' in p for p in bad), bad


def test_overall_dims_are_found_and_agree():
    """SPA's overalls carry the Cover Size note and read the true size,
    so neither the roster nor the agreement check fires."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, 60.0, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    assert "noted 'Cover Size'" in txt, txt
    bad = problems(txt)
    assert not any('DISAGREES' in p for p in bad), bad
    assert not any('but the cover measures' in p for p in bad), bad


def test_overlap_dim_is_found():
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None,
                'Yes', 'Offset', 3.0, 'No'])
    txt = report_of(vm)
    assert 'Overlap: 3' in txt, txt
    assert not any('NO ' in p and 'Overlap' in p for p in problems(txt))


def test_missing_overlap_is_caught():
    """Delete the Overlap dimension and SPACHECK names it."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None,
                'Yes', 'Offset', 3.0, 'No'])
    # erase every dimension whose text carries the Overlap note
    for e in list(vm.entities):
        if e in vm.deleted:
            continue
        d = {}
        for p in vm.entdata[e]:
            if isinstance(p, Dot):
                d.setdefault(p.a, p.b)
            elif isinstance(p, list) and p:
                d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
        if d.get(0) == 'DIMENSION' and 'Overlap' in str(d.get(1, '')):
            vm.deleted.add(e)
    txt = report_of(vm)
    assert any('Overlap' in p and 'NO' in p for p in problems(txt)), \
        problems(txt)


# ----------------------------------------------------------- the block

def test_missing_details_block_is_reported():
    """No Spa Cover Details block in the drawing -> named, and the hinge
    checks say they could not run."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    bad = problems(txt)
    assert any('NO BLOCK' in p for p in bad), bad
    assert any('no taper' in p for p in bad), bad


# ------------------------------------------------------ the title block

def test_title_block_exact_ratio_passes():
    """A border at exactly 0.6x the liner block passes."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    border(vm, 422.4, 326.175)
    txt = report_of(vm)
    assert '0.60x the liner block, OK' in txt, txt


def test_title_block_at_full_liner_size_is_caught():
    """A border left at the LINER size is the mistake the check exists
    for -- it must be named, with the factor it actually came out at."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    border(vm, 704.0, 543.625)
    txt = report_of(vm)
    bad = problems(txt)
    assert any('Title block' in p and 'exactly 0.60x' in p for p in bad), bad
    assert any('1.000x the liner block' in p for p in bad), bad


def test_title_block_stretched_is_caught():
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    border(vm, 422.4, 500.0)
    txt = report_of(vm)
    assert any('STRETCHED' in p for p in problems(txt)), problems(txt)


def test_no_border_is_reported():
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    assert any('NO BORDER' in p for p in problems(txt)), problems(txt)


def test_standoffs_pass_on_spas_own_output_and_catch_a_moved_dim():
    """SPA stands the top overall 2 ft above the cover.  Its own output
    must not be reported for that, and a dim dragged off it must."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, 60.0, '90', None, None, None, 'No', 'No'])
    assert not any('above the cover' in p for p in problems(report_of(vm)))

    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, 60.0, '90', None, None, None, 'No', 'No'])
    moved = False
    for e in vm.entities:
        d = {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}
        if d.get(0) != 'DIMENSION' or 'Cover Size' not in str(d.get(1, '')):
            continue
        for i, p in enumerate(vm.entdata[e]):
            if isinstance(p, list) and p and p[0] == 10 and p[2] > 60.0:
                vm.entdata[e][i] = [10, p[1], 100.0, 0.0]
                moved = True
    assert moved, "found no top overall to move"
    bad = problems(report_of(vm))
    assert any('stands 40.0000 above the cover' in p for p in bad), bad


# ------------------------------------------------------------ the hinges
#
# These are the checks that only mean something if SPACHECK measures
# against the SAME rules SPA drew to.  Each one runs SPA, then audits
# what SPA produced.

def test_hinges_drawn_by_spa_are_read_back():
    """SPA lays out a 5-piece cover; SPACHECK counts the same 4 hinges,
    reads the same arrangement off the chart, and fits the same foam."""
    vm = build([None, 'Coversize', 'Rectangle', None, 230.0, 60.0,
                '90', None, None, None,
                'No', 'Yes', 'No', None, '4-3'])
    add_block(vm, 'STANDARD', '4-3')
    txt = report_of(vm)
    assert 'Hinges: 4 drawn, so 5 pieces (STD 4-3)' in txt, txt
    assert 'Arrangement: H V V H, matches' in txt, txt
    assert 'Foam width: widest piece 46.0000 within 48.0000, OK' in txt, txt
    assert 'Foam length: longest hinge 60.0000 within 144.0000, OK' in txt


def test_piece_count_off_the_foam_sheet_is_flagged():
    """5 pieces is not an acceptable count for Standard 4-3.  SPA draws
    it anyway and says so; SPACHECK must reach the same verdict, or the
    two tools disagree about the same chart."""
    vm = build([None, 'Coversize', 'Rectangle', None, 230.0, 60.0,
                '90', None, None, None,
                'No', 'Yes', 'No', None, '4-3'])
    add_block(vm, 'STANDARD', '4-3')
    bad = problems(report_of(vm))
    assert any('5 is NOT an acceptable count' in p for p in bad), bad


def test_thermolight_drawn_all_velcro_reads_back_clean():
    """The whole round trip through one block: SPA reads THERMO-LIGHT
    off it and draws velcro-only hinges, and SPACHECK reads the same
    block and confirms the arrangement against the chart."""
    vm = VM()
    vm.load(SPA)
    blk = add_block(vm, 'THERMO-LIGHT', '1-3/8')
    # Thermo-Light reads the block first, so it is the opening answer;
    # the water's-edge question is then skipped (cover size is the same)
    vm.run('c:SPA', [blk, 'Rectangle', None, 140.0, 60.0,
                     '90', None, None, None, 'Yes', 'No'])
    txt = report_of(vm)
    assert 'grade THERMO, taper 1-3/8' in txt, txt
    assert 'Arrangement: V V, matches' in txt, txt
    assert not any('Arrangement' in p for p in problems(txt)), problems(txt)


def test_thermolight_with_a_fold_hinge_is_caught():
    """The same cover drawn as Standard (so it gets a fold hinge) but
    labelled Thermo-Light on the block: SPACHECK must side with the
    block's rule -- Thermo-Light is velcro only."""
    vm = build([None, 'Coversize', 'Rectangle', None, 140.0, 60.0,
                '90', None, None, None,
                'No', 'Yes', 'No', None, '1-3/8'])
    add_block(vm, 'THERMO-LIGHT', '1-3/8')
    bad = problems(report_of(vm))
    assert any('reads H V but the chart says V V' in p for p in bad), bad


def test_hardware_advice_only_speaks_up_when_needed():
    """Thermo-Light always takes velcro hinges; nothing else is called
    for, and the three "no" answers must not be dressed as advice."""
    vm = build([None, 'Coversize', 'Rectangle', None, 140.0, 60.0,
                '90', None, None, None,
                'No', 'Yes', 'No', None, '1-3/8'])
    add_block(vm, 'THERMO-LIGHT', '1-3/8')
    txt = report_of(vm)
    assert 'Velcro hinges: YES - always for this grade' in txt, txt
    for chunk in txt.split('\\P'):
        if 'Double C channel: no' in chunk or 'Hold down kit: no' in chunk:
            assert not chunk.startswith('{\\C'), chunk


def test_hinges_without_a_cover_outline_still_audit():
    """The drawing most in need of an audit -- hinges drawn but the
    cover outline missing -- must not take the audit down with it.  A
    hinge's run is its own length, so the foam-length check and the
    hardware advice still stand; only the piece widths need the cover,
    and their absence is said out loud rather than crashed on."""
    vm = VM()
    vm.load(CHK)
    vm.loads('''
      (entmake (list '(0 . "LAYER") '(2 . "COVER") '(70 . 0) '(62 . 3)
                     '(6 . "Continuous")))
      (entmake (list '(0 . "LINE") '(8 . "COVER")
                     '(10 0.0 0.0 0.0) '(11 0.0 60.0 0.0)))
      (entmake (list '(0 . "LINE") '(8 . "COVER")
                     '(10 40.0 0.0 0.0) '(11 40.0 60.0 0.0)))''')
    add_block(vm, 'STANDARD', '4-3')
    txt = report_of(vm)
    assert 'Foam length: longest hinge 60.0000 within 144.0000, OK' in txt, txt
    assert 'Foam width: not checked' in txt, txt
    assert 'Velcro hinges: no - hinge 60.0 not over 120' in txt, txt
    bad = problems(txt)
    assert any('NO OUTLINE on layer COVER' in p for p in bad), bad


# --------------------------------------------------------- other shapes

def test_octagon_audits_clean():
    vm = build([None, 'Coversize', 'OCtagon', None, 95.0, None,
                'NA', 'NA', 'NA', 'NA', 'NA',
                'No', 'Yes', 'No', None, '4-3'])
    add_block(vm, 'STANDARD', '4-3')
    border(vm, 422.4, 326.175)
    assert problems(report_of(vm)) == []


def test_round_audits_clean():
    vm = build([None, 'Coversize', 'ROund', None, 84.0,
                'No', 'Yes', 'No', None, '4-3'])
    add_block(vm, 'STANDARD', '4-3')
    border(vm, 422.4, 326.175)
    assert problems(report_of(vm)) == []


# ------------------------------------------------------- the other commands

def test_the_guided_walk_marks_and_rescue_puts_it_back():
    """SPACHECK walks what it flagged and recolours what you confirm;
    SPACHECKRESCUE must restore every one of those colours exactly and
    take the report away with it."""
    vm = build([None, 'Coversize', 'Rectangle', None, 140.0, 60.0,
                '90', None, None, None,
                'No', 'Yes', 'No', None, '1-3/8'])
    add_block(vm, 'THERMO-LIGHT', '1-3/8')
    vm.load(CHK)

    def colours():
        out = {}
        for e in vm.entities:
            if e in vm.deleted:
                continue
            for p in vm.entdata[e]:
                if isinstance(p, Dot) and p.a == 62:
                    out[e] = p.b
        return out

    before = colours()
    vm.run('c:SPACHECK', [None, 'Yes', 'Yes'])     # mark both flagged items
    marked = colours()
    changed = [e for e in marked if before.get(e) != marked[e]]
    assert changed, "the walk marked nothing"
    assert all(marked[e] == 1 for e in changed), marked

    vm.run('c:SPACHECKRESCUE', [])
    after = colours()
    assert after == before, (before, after)
    left = [e for e in vm.entities
            if e not in vm.deleted
            and any(isinstance(p, Dot) and p.a == 8
                    and p.b == 'SPACHECK-REPORT' for p in vm.entdata[e])]
    assert left == [], "rescue left the report behind"


def test_version_and_tutorial_run():
    vm = VM()
    vm.load(CHK)
    vm.run('c:SPACHECKVER', [])
    vm.run('c:TUTORIALSPACHECK', [None])


def test_the_demo_reports_its_three_planted_faults_and_nothing_else():
    """The whole point of the demo: it plants three faults, explains
    them, and the scan then names those three and only those three.  A
    demo drawing that reports extra problems teaches the wrong thing."""
    vm = VM()
    vm.load(CHK)
    vm.run('c:TUTORIALSPACHECK',
           ['Demo', [0.0, 0.0, 0.0],   # show me / where to draw it
            '', '', '',                # Enter through the three faults
            'Yes', None,               # scan it, taking the whole drawing
            'No'])                     # keep the drawing so we can read it
    txt = report_text(vm)
    assert txt is not None, "the demo's scan wrote no report"
    bad = problems(txt)
    assert len(bad) == 3, bad
    assert any('reads 80.0000 but the cover measures 84.0000' in p
               for p in bad), bad
    assert any('Hinge 1: NO label' in p for p in bad), bad
    assert any('must be exactly 0.60x' in p for p in bad), bad


def test_the_demo_cleans_up_after_itself():
    vm = VM()
    vm.load(CHK)
    vm.run('c:TUTORIALSPACHECK',
           ['Demo', [0.0, 0.0, 0.0], '', '', '', 'Yes', None, 'Yes'])
    left = [e for e in vm.entities if e not in vm.deleted]
    assert left == [], [vm.entdata[e] for e in left]


# ----------------------------------------------------------- arithmetic

def test_the_report_is_split_the_way_mtext_needs():
    """MTEXT holds 250 characters in group 1 and the rest in leading
    group 3 chunks.  A report is always longer than that, so a report
    written as one group 1 would lose everything past character 250 the
    moment AutoCAD read it back."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, 60.0, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    assert len(txt) > 250, len(txt)
    for e in vm.entities:
        d = {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}
        if d.get(0) == 'MTEXT' and d.get(8) == 'SPACHECK-REPORT':
            chunks = [p.b for p in vm.entdata[e]
                      if isinstance(p, Dot) and p.a == 3]
            assert chunks, "no group 3 chunks on a report this long"
            assert all(len(c) == 250 for c in chunks), \
                [len(c) for c in chunks]
            assert len(d[1]) <= 250, len(d[1])
            return
    raise AssertionError("no report found")


def _move_one_dim(vm, layer):
    """Shove the first dimension in the drawing onto another layer."""
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}
        if d.get(0) == 'DIMENSION':
            vm.entdata[e] = [Dot(8, layer) if (isinstance(p, Dot) and p.a == 8)
                             else p for p in vm.entdata[e]]
            return True
    return False


def test_dimension_layer_verdict_is_clean_on_spas_own_output():
    """Every dimension SPA draws is on DIMENSION, so the roster-wide
    verdict passes and nothing suggests running CDIM."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    assert 'Dimension layer: all ' in txt, txt
    assert 'CDIM' not in txt, txt


def test_a_dim_on_the_wrong_layer_is_caught_and_names_cdim():
    """A dimension dragged onto another layer is counted, the layer it
    landed on is named, and the report says to run CDIM."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    assert _move_one_dim(vm, 'JUNK'), "found no dimension to move"
    bad = problems(report_of(vm))
    assert any('NOT on layer DIMENSION' in p and 'JUNK' in p
               and 'run CDIM' in p for p in bad), bad


def test_the_lite_scan_keeps_the_dimension_layer_check():
    """LITESPACHECKSCAN drops the per-dimension audit but NOT the
    layer verdict -- a sheet whose dims sit on the wrong layer plots
    wrong however sound the dimensions are."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    assert _move_one_dim(vm, 'JUNK')
    txt = report_of(vm, cmd='c:LITESPACHECKSCAN')
    assert 'LITESPACHECKSCAN REPORT' in txt, txt[:120]
    bad = problems(txt)
    assert any('run CDIM' in p for p in bad), bad
    # ...and the per-dimension audit really is gone
    assert 'DIMENSION AUDIT' not in txt, txt


def _add_text(vm, s, handle):
    """Drop a TEXT entity carrying s into the drawing."""
    esc = s.replace('\\', '\\\\').replace('"', '\\"')
    vm.loads('(entmakex (list (cons 0 "TEXT") (cons 8 "TEXT") (cons 5 "%s")'
             ' (list 10 0.0 -50.0) (cons 40 2.0) (cons 1 "%s")))'
             % (handle, esc))


def test_feet_without_inches_is_flagged_and_good_notation_is_not():
    """A text box reading 5' is caught; 5'-0", 3'-2" and 40" pass, and
    so does an apostrophe that is a possessive rather than a feet mark."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    _add_text(vm, "Depth 5'", 'BAD1')
    _add_text(vm, 'Wall 3\'-2"', 'OK1')
    _add_text(vm, 'Skimmer 40"', 'OK2')
    _add_text(vm, "Owner's Manual", 'OK3')
    txt = report_of(vm)
    bad = problems(txt)
    assert any('Text BAD1' in p and 'NO INCHES' in p for p in bad), bad
    for h in ('OK1', 'OK2', 'OK3'):
        assert not any(h in p for p in bad), (h, bad)
    assert any('Feet & inches: 1 of ' in p for p in bad), bad


def test_the_feet_mark_predicate_itself():
    """The rule, case by case: an apostrophe straight after a digit is a
    feet mark and needs an inch mark; anything else is prose."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    vm.load(CHK)
    for src, want in [("5'", True), ("5'-0\"", False), ("3'-2\"", False),
                      ('40"', False), ("5'-0''", False), ("12''", False),
                      ("Water's Edge", False), ("don't", False),
                      ("3' 4 1/2\"", False), ("5' and 7'-0\"", True),
                      ("A 5'x10' pad", True)]:
        esc = src.replace('\\', '\\\\').replace('"', '\\"')
        got = bool(vm.loads('(spachk:feet-open-p "%s")' % esc))
        assert got == want, (src, got, want)


def test_spas_own_text_states_its_inches():
    """Everything SPA writes passes -- the check must not cry wolf on
    the tool's own output."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    txt = report_of(vm)
    assert 'Feet & inches: all ' in txt, txt
    assert not any('NO INCHES' in p for p in problems(txt)), problems(txt)


def test_the_lite_scan_keeps_the_units_check():
    """LITESPACHECKSCAN drops the per-dimension audit but keeps the
    feet-and-inches check -- it is about drawing text, not dimensions."""
    vm = build([None, 'Coversize', 'Rectangle', None,
                84.0, None, '90', None, None, None, 'No', 'No'])
    _add_text(vm, "Depth 5'", 'BAD1')
    bad = problems(report_of(vm, cmd='c:LITESPACHECKSCAN'))
    assert any('Text BAD1' in p and 'NO INCHES' in p for p in bad), bad


def test_the_ratio_itself():
    """0.6 x the liner block is 422.4 x 326.175 -- the numbers the check
    is built on."""
    assert abs(704.0 * 0.6 - 422.4) < 1e-9
    assert abs(543.625 * 0.6 - 326.175) < 1e-9


if __name__ == '__main__':
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            try:
                fn()
                print(f"ok   {name}")
            except AssertionError as e:
                fails += 1
                print(f"FAIL {name}\n     {e}")
    print(f"\n{fails} failure(s)")
    sys.exit(1 if fails else 0)
