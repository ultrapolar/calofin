"""Regression tests for the review-b findings: CHECK, SPACHECK, CLEARDIM
and LINTXTCHK, each driven through the REAL .lsp in the VM.

The VM has no locked layers, no UCS and one paper space it never
switches to, so each test models what it needs itself:

  * a LOCKED layer is a layer record with bit 4 of group 70 set, and
    entmod is swapped for one that refuses (answers nil, changes
    nothing) for an entity on such a layer -- what AutoCAD does;
  * a SHIFTED UCS is a trans that adds (or takes off) an origin
    offset, and a command wrapper that reads every point it is handed
    as a UCS point -- which is what (command ...) does;
  * a LAYOUT VIEWPORT is CTAB naming a layout while CVPORT is above 1,
    and paper-space ink is an entity carrying (410 . "Layout1").

Every regression test here failed against the file as it stood before
its fix; the guard tests -- an unlocked CHECK, a tutorial run to the
end, a lone Tech Title, a frame whose four lines meet -- pin what the
fix had to leave alone and pass on both.  Run with REVIEW_B_ROOT
pointing at a folder of the old copies to see it: the PATHS below are
rebuilt from it.

Run: python3 tests/test_fix_review_b.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot, Sym, BUILTINS, NIL  # noqa: E402

HERE = os.path.dirname(__file__)
LISP = os.path.join(HERE, '..', 'lisp')
PATHS = {
    'check': os.path.join(LISP, 'check', 'check_drawing.lsp'),
    'spacheck': os.path.join(LISP, 'spacheck', 'SPACHECK.lsp'),
    'cleardim': os.path.join(LISP, 'cleardim', 'CLEARDIM.lsp'),
    'lintxtchk': os.path.join(LISP, 'lintxtchk', 'LINTXTCHK.lsp'),
    'spa': os.path.join(LISP, 'spa', 'SPA.LSP'),
}
_OLD = os.environ.get('REVIEW_B_ROOT')
if _OLD:
    for _k in ('check', 'spacheck', 'cleardim', 'lintxtchk'):
        PATHS[_k] = os.path.join(_OLD, os.path.basename(PATHS[_k]))


# ------------------------------------------------------------------
# models of what the VM leaves out
# ------------------------------------------------------------------

def grp(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


def lock_layer(vm, name):
    """A layer record with the LOCKED bit set."""
    vm.loads('(entmake (list (cons 0 "LAYER") (cons 2 "%s") (cons 70 4)'
             ' (cons 62 7)))' % name)


def _layer_locked(vm, name):
    if not isinstance(name, str):
        return False
    rec = BUILTINS[Sym('tblsearch')](vm, ['LAYER', name])
    if not isinstance(rec, list):
        return False
    for g in rec:
        if isinstance(g, Dot) and g.a == 70:
            return bool(int(g.b) & 4)
    return False


class LockedLayers:
    """entmod refuses -- nil, nothing written -- for an entity on a
    locked layer, exactly as AutoCAD's does."""

    def __enter__(self):
        self.real = BUILTINS[Sym('entmod')]
        real = self.real

        def entmod(vm, a):
            lay = None
            ent = None
            for g in a[0] or []:
                if isinstance(g, Dot) and g.a == 8:
                    lay = g.b
                if isinstance(g, Dot) and g.a == -1:
                    ent = g.b
            if lay is None and ent is not None:
                lay = grp(vm, ent, 8)
            if _layer_locked(vm, lay):
                return NIL
            return real(vm, a)

        BUILTINS[Sym('entmod')] = entmod
        return self

    def __exit__(self, *exc):
        BUILTINS[Sym('entmod')] = self.real
        return False


def said(vm):
    return ''.join(vm.printed)


FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


# ------------------------------------------------------------------
# [1] CHECK: a fix refused on a locked layer is not a clean result
# ------------------------------------------------------------------

def made(vm, src):
    before = len(vm.entities)
    vm.loads(src)
    return vm.entities[before:]


CHK_LINE = '''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity") '(5 . "L1") '(8 . "0")
                 '(100 . "AcDbLine")
                 '(10 0.0 0.0 0.0) '(11 100.0 0.0 0.0)))'''


def test_check_a_stray_point_on_a_locked_layer_is_not_passed_clean():
    """A finished sheet keeps its dimensions on a locked layer.  One of
    them has a definition point 0.5 off the line.  entmod refuses the
    shift, and CHECK used to read that nil as 'already attached' and
    print '1 checked, 0 shifted' over the fault it had found."""
    vm = VM()
    vm.load(PATHS['check'])
    lock_layer(vm, 'DIMS')
    ents = made(vm, CHK_LINE)
    bad = made(vm, '''
  (entmake (list '(0 . "DIMENSION") '(100 . "AcDbEntity") '(5 . "D1")
                 '(8 . "DIMS") '(100 . "AcDbDimension") '(70 . 1)
                 '(13 20.0 0.0 0.0) '(14 60.0 0.5 0.0)))''')
    ents += bad
    with LockedLayers():
        vm.run('c:CHECK', [None, ents])
    txt = said(vm)
    check("[1] the point on the locked layer is left where it was",
          grp(vm, bad[0], 14) == [60.0, 0.5, 0.0], repr(grp(vm, bad[0], 14)))
    check("[1] the summary does not read clean",
          'Dimensions: 1 checked, 0 shifted onto nearest object (red),'
          ' 1 stray on a locked layer - NOT shifted' in txt, txt[-500:])
    check("[1] the dimension is named, with its layer",
          'Dimension D1: a definition point is off every object, but layer'
          ' DIMS is locked - NOT shifted.' in txt, txt[-500:])
    check("[1] and the drafter is told what to do about it",
          'Unlock those layers and run CHECK again' in txt, txt[-300:])


def test_check_a_loose_arc_on_a_locked_layer_is_not_passed_clean():
    """The same for the arc audit: rebuild-arc's refused entmod used to
    come back nil, which fix-arc-end read as 'nothing to do'."""
    import math
    vm = VM()
    vm.load(PATHS['check'])
    lock_layer(vm, 'ARCS')
    ents = made(vm, CHK_LINE)
    c, r = (65.0, -20.0), math.hypot(35.0, 20.0)
    a0 = math.atan2(20.0, -35.0)
    a1 = math.atan2(20.0, 35.0)
    arc = made(vm, '''
  (entmake (list '(0 . "ARC") '(100 . "AcDbEntity") '(5 . "A1")
                 '(8 . "ARCS") '(100 . "AcDbCircle")
                 '(10 %r %r 0.0) '(40 . %r) '(50 . %r) '(51 . %r)))'''
               % (c[0], c[1], r, a0, a1))
    ents += arc
    with LockedLayers():
        vm.run('c:CHECK', [None, ents])
    txt = said(vm)
    check("[1] the arc on the locked layer is untouched",
          grp(vm, arc[0], 40) == r and grp(vm, arc[0], 62) is None)
    check("[1] the arc summary does not read clean",
          'Arcs: 1 checked, 0 with endpoint(s) snapped (magenta),'
          ' 1 loose on a locked layer - NOT snapped' in txt, txt[-500:])


def test_check_an_unlocked_drawing_still_fixes_and_says_nothing_new():
    """The ordinary run is unchanged: shifted, recoloured, no locked
    line in the summary."""
    vm = VM()
    vm.load(PATHS['check'])
    ents = made(vm, CHK_LINE)
    bad = made(vm, '''
  (entmake (list '(0 . "DIMENSION") '(100 . "AcDbEntity") '(5 . "D1")
                 '(8 . "0") '(100 . "AcDbDimension") '(70 . 1)
                 '(13 20.0 0.0 0.0) '(14 60.0 0.5 0.0)))''')
    ents += bad
    with LockedLayers():
        vm.run('c:CHECK', [None, ents])
    txt = said(vm)
    check("[1] an unlocked stray point is still shifted",
          'Dimensions: 1 checked, 1 shifted onto nearest object'
          ' (red)\nArcs' in txt, txt[-500:])
    check("[1] and no locked-layer line appears",
          'locked' not in txt, txt[-500:])


# ------------------------------------------------------------------
# SPACHECK fixtures
# ------------------------------------------------------------------

SPA_RECT = [None, 'Coversize', 'Rectangle', None,
            84.0, None, 'Yes', '90', 'No', 'No']


def spa_vm():
    """A spa drawing SPA itself drew (cover at 0,0 - 84,84), with
    SPACHECK loaded over it."""
    vm = VM()
    vm.load(PATHS['spa'])
    vm.run('c:SPA', list(SPA_RECT))
    vm.load(PATHS['spacheck'])
    return vm


def live(vm):
    return [e for e in vm.entities if e not in vm.deleted]


def ent_dict(vm, e):
    return {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}


def mtext_of(vm, e):
    head, tail = [], ''
    for p in vm.entdata[e]:
        if isinstance(p, Dot):
            if p.a == 3:
                head.append(p.b)
            elif p.a == 1 and not tail:
                tail = p.b
    return ''.join(head) + tail


def report_text(vm):
    for e in live(vm):
        d = ent_dict(vm, e)
        if d.get(0) == 'MTEXT' and d.get(8) == 'SPACHECK-REPORT':
            return mtext_of(vm, e)
    return None


def rows(txt, colour):
    """The report rows drawn in one ACI colour (1 problems, 4 advice)."""
    out = []
    for chunk in (txt or '').split('\\P'):
        tag = '{\\C%d;' % colour
        if chunk.startswith(tag):
            out.append(chunk[len(tag):].rstrip('}'))
    return out


def border_rect(vm, x, y, w, h, extra=''):
    vm.loads(f"""
      (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                     '(8 . "border") '(100 . "AcDbPolyline"){extra}
                     '(90 . 4) '(70 . 1)
                     (list 10 {x} {y}) '(42 . 0.0)
                     (list 10 {x + w} {y}) '(42 . 0.0)
                     (list 10 {x + w} {y + h}) '(42 . 0.0)
                     (list 10 {x} {y + h}) '(42 . 0.0)))""")
    return vm.entities[-1]


def tech_title(vm, x, y, date):
    vm.loads(f"""(progn
      (setq b (entmakex (list '(0 . "INSERT") '(8 . "0") (cons 2 "Tech Title")
                              '(10 {x} {y}) '(66 . 1))))
      (entmake (list '(0 . "ATTRIB") '(8 . "0") '(2 . "Date") (cons 1 "{date}")))
      (entmake (list '(0 . "SEQEND") '(8 . "0"))))""")
    return vm.globals[Sym('b')] if Sym('b') in vm.globals else vm.loads('b')


def title_date(vm, blk):
    e = vm.entities[vm.entities.index(blk) + 1]
    return ent_dict(vm, e).get(1)


def today(vm):
    return vm.loads('(spachk:mdy-str (spachk:today-mdy))')


def first_dim(vm):
    for e in live(vm):
        if ent_dict(vm, e).get(0) == 'DIMENSION':
            return e
    return None


def move_to_layer(vm, e, layer):
    vm.entdata[e] = [Dot(8, layer) if (isinstance(p, Dot) and p.a == 8)
                     else p for p in vm.entdata[e]]


# ------------------------------------------------------------------
# [2] SPACHECK: a recolour refused on a locked layer is not counted
# ------------------------------------------------------------------

def test_spacheck_does_not_count_an_item_it_could_not_recolour():
    """A flagged dimension sits on a locked layer.  The drafter answers
    Yes; both entmods are refused, and the run used to end '1 item
    marked red' over a dimension that never changed colour."""
    vm = spa_vm()
    d = first_dim(vm)
    move_to_layer(vm, d, 'JUNK')
    lock_layer(vm, 'JUNK')
    n = vm.loads('(length (caddr (spachk:audit (ssget "_X") nil nil)))')
    check("[2] the dimension on the wrong layer is flagged", n >= 1, repr(n))
    with LockedLayers():
        vm.run('c:SPACHECK', [None, None] + ['Yes'] * n)
    txt = said(vm)
    red = [e for e in live(vm) if ent_dict(vm, e).get(62) == 1
           and ent_dict(vm, e).get(8) != 'SPACHECK-REPORT']
    check("[2] the locked dimension did not go red",
          ent_dict(vm, d).get(62) is None, repr(ent_dict(vm, d).get(62)))
    marked = '%d item%s marked red' % (len(red), '' if len(red) == 1 else 's')
    check("[2] the count is what really went red",
          marked in txt, marked + ' / ' + txt[-400:])
    check("[2] and the refused one is said",
          '1 NOT recoloured (its layer is locked)' in txt
          and 'On locked layer JUNK - listed in the report, NOT recoloured'
          in txt, txt[-600:])
    check("[2] and it carries no half-written stash for RESCUE",
          not any(isinstance(p, list) and p and p[0] == -3
                  for p in vm.entdata[d]), repr(vm.entdata[d]))


def test_spacheckrescue_does_not_count_a_colour_it_could_not_put_back():
    """A marked item whose layer was locked afterwards: RESCUE's unstash
    used to answer T whatever its entmods said."""
    vm = spa_vm()
    d = first_dim(vm)
    move_to_layer(vm, d, 'JUNK')
    n = vm.loads('(length (caddr (spachk:audit (ssget "_X") nil nil)))')
    vm.run('c:SPACHECK', [None, None] + ['Yes'] * n)
    check("[2] setup: the dimension was marked red",
          ent_dict(vm, d).get(62) == 1, repr(ent_dict(vm, d).get(62)))
    lock_layer(vm, 'JUNK')
    vm.printed.clear()
    with LockedLayers():
        vm.run('c:SPACHECKRESCUE', [])
    txt = said(vm)
    check("[2] the locked one is still red",
          ent_dict(vm, d).get(62) == 1, repr(ent_dict(vm, d).get(62)))
    check("[2] RESCUE says so instead of counting it",
          '1 NOT put back (its layer is locked) - unlock and run'
          ' SPACHECKRESCUE again' in txt, txt[-400:])
    check("[2] the report (on its own, unlocked layer) is still removed",
          txt.rstrip().endswith('report removed.') and report_text(vm) is None,
          txt[-200:])
    vm.globals[Sym('review-b-ent')] = d
    check("[2] and keeps its stash for a run after unlocking",
          vm.loads('(if (assoc -3 (entget review-b-ent \'("SPACHECK"))) T)')
          is not NIL)


class RefusedFor:
    """entmod refuses one entity on an UNLOCKED layer -- AutoCAD answers
    nil for reasons other than a lock too, and a refusal is not blamed
    on a lock the layer table does not show."""

    def __init__(self, ent):
        self.ent = ent

    def __enter__(self):
        self.real = BUILTINS[Sym('entmod')]
        real, ent = self.real, self.ent

        def entmod(vm, a):
            for g in a[0] or []:
                if isinstance(g, Dot) and g.a == -1 and g.b == ent:
                    return NIL
            return real(vm, a)

        BUILTINS[Sym('entmod')] = entmod
        return self

    def __exit__(self, *exc):
        BUILTINS[Sym('entmod')] = self.real
        return False


def test_a_refusal_on_an_unlocked_layer_is_not_blamed_on_a_lock():
    """Review of [2]: every nil from the recolour was reported as 'On
    locked layer X' and counted 'on locked layers', whatever the layer
    table said."""
    vm = spa_vm()
    d = first_dim(vm)
    move_to_layer(vm, d, 'JUNK')
    n = vm.loads('(length (caddr (spachk:audit (ssget "_X") nil nil)))')
    with RefusedFor(d):
        vm.run('c:SPACHECK', [None, None] + ['Yes'] * n)
    txt = said(vm)
    check("[2r] the refusal is said at the item, without a lock",
          'AutoCAD would not recolour it (layer JUNK) - listed in the'
          ' report.' in txt and 'On locked layer' not in txt, txt[-600:])
    check("[2r] and counted as NOT recoloured, not as locked",
          '1 NOT recoloured\n' in txt and 'locked' not in txt, txt[-400:])


def test_the_refused_count_agrees_with_its_number():
    """Review of [2]: '1 on locked layers' -- the tail now agrees with
    the count, and a mixed count says how many of them were locked."""
    tail = lambda n, k, w: vm.loads(
        '(spachk:refused-tail %d %d "%s")' % (n, k, w))
    vm = VM()
    vm.load(PATHS['spacheck'])
    check("[2r] nothing refused, nothing said", tail(0, 0, 'x') == '')
    check("[2r] one, locked",
          tail(1, 1, 'recoloured') == ', 1 NOT recoloured (its layer is locked)',
          repr(tail(1, 1, 'recoloured')))
    check("[2r] two, both locked",
          tail(2, 2, 'put back') == ', 2 NOT put back (their layers are locked)',
          repr(tail(2, 2, 'put back')))
    check("[2r] three, one of them locked",
          tail(3, 1, 'recoloured') == ', 3 NOT recoloured (1 on a locked layer)',
          repr(tail(3, 1, 'recoloured')))
    check("[2r] three, two of them locked",
          tail(3, 2, 'recoloured') == ', 3 NOT recoloured (2 on locked layers)',
          repr(tail(3, 2, 'recoloured')))


def test_spacheckrescue_does_not_blame_a_lock_it_did_not_see():
    vm = spa_vm()
    d = first_dim(vm)
    move_to_layer(vm, d, 'JUNK')
    n = vm.loads('(length (caddr (spachk:audit (ssget "_X") nil nil)))')
    vm.run('c:SPACHECK', [None, None] + ['Yes'] * n)
    vm.printed.clear()
    with RefusedFor(d):
        vm.run('c:SPACHECKRESCUE', [])
    txt = said(vm)
    check("[2r] RESCUE counts the refusal without telling the drafter to"
          " unlock anything",
          '1 NOT put back, report removed.' in txt and 'unlock' not in txt,
          txt[-400:])


# ------------------------------------------------------------------
# [15] TUTORIALSPACHECK: an Esc inside the scan leaves the layer alone
# ------------------------------------------------------------------

def test_an_esc_in_the_tutorials_scan_puts_the_layer_and_echo_back():
    """The demo moves CLAYER to the dimension layer and the tutorial
    turns CMDECHO off; it then hands over to SPACHECKSCAN, whose own
    handler is the only one an Esc there runs."""
    vm = VM()
    vm.load(PATHS['spacheck'])
    vm.handle_errors = True
    vm.sysvars['CMDECHO'] = 1
    vm.sysvars['CLAYER'] = '0'

    def esc(vm):
        raise LispError('Function cancelled', vm)

    vm.run('c:TUTORIALSPACHECK',
           ['Demo', [0.0, 0.0, 0.0], '', '', '',   # the three pauses
            'Yes',                                 # run the scan
            None, esc])                            # no pickfirst; Esc
    check("[15] the Esc reached the scan's handler",
          vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
    check("[15] the drafter's layer is current again",
          vm.sysvars['CLAYER'] == '0', repr(vm.sysvars['CLAYER']))
    check("[15] and CMDECHO is back on",
          vm.sysvars['CMDECHO'] == 1, repr(vm.sysvars['CMDECHO']))
    check("[15] no undo group is left open", vm.undo_groups == 0)


def test_the_tutorial_run_to_the_end_still_restores_everything():
    vm = VM()
    vm.load(PATHS['spacheck'])
    vm.sysvars['CMDECHO'] = 1
    vm.sysvars['CLAYER'] = '0'
    vm.run('c:TUTORIALSPACHECK',
           ['Demo', [0.0, 0.0, 0.0], '', '', '', 'Yes', None, None, 'Yes'])
    check("[15] a clean run ends on the drafter's layer and echo",
          vm.sysvars['CLAYER'] == '0' and vm.sysvars['CMDECHO'] == 1,
          repr((vm.sysvars['CLAYER'], vm.sysvars['CMDECHO'])))


# ------------------------------------------------------------------
# [6] SPACHECK's Enter sweep keeps to the space the drafter is in
# ------------------------------------------------------------------

def test_the_whole_drawing_sweep_leaves_paper_space_out():
    """A paper-space dimension on a layout is not part of the spa: the
    bare (ssget "_X") took it, and the dimension-layer verdict blamed
    the model drawing for it."""
    vm = spa_vm()
    vm.loads("""(entmake (list '(0 . "DIMENSION") '(100 . "AcDbEntity")
                   '(8 . "PAPERDIMS") '(410 . "Layout1")
                   '(100 . "AcDbDimension") '(70 . 1)
                   '(13 0.0 0.0 0.0) '(14 50.0 0.0 0.0)
                   '(10 25.0 10.0 0.0) '(3 . "STANDARD")))""")
    vm.run('c:SPACHECKSCAN', [None, None])
    bad = rows(report_text(vm), 1)
    check("[6] the paper-space dimension is not audited",
          not any('PAPERDIMS' in r for r in bad), repr(bad))


def test_from_a_layout_viewport_the_sweep_is_model_space():
    """Inside a layout viewport CTAB names the layout while the drafter
    is working in model space: the sweep must take the model drawing."""
    vm = spa_vm()
    vm.sysvars['TILEMODE'] = 0
    vm.sysvars['CTAB'] = 'Layout1'
    vm.sysvars['CVPORT'] = 2
    check("[6] the current space from a viewport is Model",
          vm.loads('(spachk:space)') == 'Model')
    vm.sysvars['CVPORT'] = 1
    check("[6] and on the paper itself it is the layout",
          vm.loads('(spachk:space)') == 'Layout1')


def test_spacheckscan_from_a_layout_viewport_audits_the_model_spa():
    """End to end: from inside a layout viewport Enter must audit the
    model-space spa -- a bare "_X" dragged the layout's paper ink in,
    and CTAB alone would have left the spa out."""
    vm = spa_vm()
    vm.loads("""(entmake (list '(0 . "DIMENSION") '(100 . "AcDbEntity")
                   '(8 . "PAPERDIMS") '(410 . "Layout1")
                   '(100 . "AcDbDimension") '(70 . 1)
                   '(13 0.0 0.0 0.0) '(14 50.0 0.0 0.0)
                   '(10 25.0 10.0 0.0) '(3 . "STANDARD")))""")
    vm.sysvars['TILEMODE'] = 0
    vm.sysvars['CTAB'] = 'Layout1'
    vm.sysvars['CVPORT'] = 2
    vm.run('c:SPACHECKSCAN', [None, None])
    txt = report_text(vm) or ''
    check("[6] the model cover is audited from the viewport",
          'Cover outline: one closed LWPOLYLINE, OK' in txt, txt[:600])
    check("[6] and the layout's paper dimension is not",
          'PAPERDIMS' not in txt, repr(rows(txt, 1)))


# ------------------------------------------------------------------
# [7] SPACHECK reads the Tech Title nearest the spa, and writes only one
# ------------------------------------------------------------------

def test_of_two_tech_titles_the_nearest_is_read():
    """Two sheets, two Tech Titles.  The other sheet's (stale, made
    first) used to be read because the database listed it first."""
    vm = spa_vm()
    tech_title(vm, 5000.0, 400.0, '01/02/2020')
    tech_title(vm, 0.0, 400.0, today(vm))
    vm.run('c:SPACHECKSCAN', [None, None])
    txt = report_text(vm)
    check("[7] the spa sheet's own (current) date is read",
          not any('Tech Title' in r for r in rows(txt, 1)), repr(rows(txt, 1)))
    check("[7] and which title was read is said",
          any("2 'Tech Title' blocks in reach - read the one at 0.0,400.0"
              in r for r in rows(txt, 4)), repr(rows(txt, 4)))


def walk_answers(vm):
    """Enter twice (no pickfirst, whole drawing), then No at every item
    the walk will offer."""
    n = vm.loads('(length (caddr (spachk:audit (ssget "_X") nil nil)))')
    return [None, None] + ['No'] * n


def test_with_two_tech_titles_spacheck_writes_neither():
    """SPACHECK wrote today's date into whichever title came back first
    -- another sheet's.  With more than one in reach it now writes none
    and says why."""
    vm = spa_vm()
    far = tech_title(vm, 5000.0, 400.0, '01/02/2020')
    near = tech_title(vm, 0.0, 400.0, '01/03/2020')
    vm.run('c:SPACHECK', walk_answers(vm))
    txt = report_text(vm)
    check("[7] the other sheet's title is untouched",
          title_date(vm, far) == '01/02/2020', repr(title_date(vm, far)))
    check("[7] the spa's is not rewritten on a guess either",
          title_date(vm, near) == '01/03/2020', repr(title_date(vm, near)))
    check("[7] the report reads the nearest and says it was NOT updated",
          any("'01/03/2020' is NOT TODAY'S DATE" in r and 'NOT UPDATED' in r
              for r in rows(txt, 1)), repr(rows(txt, 1)))


def test_one_tech_title_is_still_rewritten():
    vm = spa_vm()
    t = tech_title(vm, 0.0, 400.0, '01/02/2020')
    vm.run('c:SPACHECK', walk_answers(vm))
    check("[7] a lone stale title is still updated",
          title_date(vm, t) == today(vm), repr(title_date(vm, t)))


# ------------------------------------------------------------------
# [10] SPACHECK measures one sheet's border, not every sheet's together
# ------------------------------------------------------------------

def test_two_sheet_borders_are_not_measured_as_one():
    """Two correct 0.6x borders, one around the spa and one 2000 away.
    The highlight holds only the spa, so the whole border layer is
    swept -- and both frames used to be measured as one box, STRETCHED."""
    vm = spa_vm()
    spa = live(vm)
    border_rect(vm, -100.0, -100.0, 422.4, 326.175)
    border_rect(vm, 2000.0, -100.0, 422.4, 326.175)
    vm.run('c:SPACHECKSCAN', [None, spa])
    txt = report_text(vm)
    check("[10] the spa sheet's border reads OK",
          'Title block: 422.4000 x 326.1750 - 0.60x the liner block, OK'
          in txt and not any('Title block' in r for r in rows(txt, 1)),
          repr(rows(txt, 1)))
    check("[10] and the second sheet is mentioned, not measured",
          any("2 separate borders on layer 'border' - the one nearest the"
              " spa was measured" in r for r in rows(txt, 4)),
          repr(rows(txt, 4)))


def test_two_sheet_borders_in_the_highlight_are_told_apart_too():
    vm = spa_vm()
    border_rect(vm, -100.0, -100.0, 422.4, 326.175)
    border_rect(vm, 2000.0, -100.0, 422.4, 326.175)
    vm.run('c:SPACHECKSCAN', [None, None])      # Enter: both in the set
    txt = report_text(vm)
    check("[10] Enter over two sheets still measures the spa's",
          not any('Title block' in r for r in rows(txt, 1)),
          repr(rows(txt, 1)))


def test_a_border_drawn_as_four_lines_is_one_frame():
    vm = spa_vm()
    vm.tables['LAYER'].add('border')
    for a, b in [((-100, -100), (322.4, -100)), ((322.4, -100), (322.4, 226.175)),
                 ((322.4, 226.175), (-100, 226.175)), ((-100, 226.175), (-100, -100))]:
        vm.loads("(entmake (list '(0 . \"LINE\") '(8 . \"border\")"
                 " '(10 %r %r 0.0) '(11 %r %r 0.0)))" % (a + b))
    vm.run('c:SPACHECKSCAN', [None, None])
    txt = report_text(vm)
    check("[10] four touching lines are one frame, measured whole",
          'Title block: 422.4000 x 326.1750 - 0.60x the liner block, OK'
          in txt and not any('separate borders' in r for r in rows(txt, 4)),
          repr(rows(txt, 1) + rows(txt, 4)))


def four_lines(vm, x, y, w, h, gap):
    """A frame drawn as four LINEs, each stopping gap short of the next
    corner -- a hand-drawn frame whose corners never quite close."""
    vm.tables['LAYER'].add('border')
    g = gap
    for a, b in [((x, y), (x + w - g, y)),
                 ((x + w, y), (x + w, y + h - g)),
                 ((x + w, y + h), (x + g, y + h)),
                 ((x, y + h), (x, y + g))]:
        vm.loads("(entmake (list '(0 . \"LINE\") '(8 . \"border\")"
                 " '(10 %r %r 0.0) '(11 %r %r 0.0)))" % (a + b))


OK_ROW = 'Title block: 422.4000 x 326.1750 - 0.60x the liner block, OK'


def test_a_four_line_frame_with_open_corners_is_one_frame():
    """Review of [10]: frames were joined only where boxes met to 1e-4,
    so one correct sheet whose corners were open by a thousandth split
    into four 'borders', and the nearest single line was measured --
    'border has no measurable size' on a correct sheet."""
    for gap in (0.001, 0.05, 0.5):
        vm = spa_vm()
        four_lines(vm, -100.0, -100.0, 422.4, 326.175, gap)
        vm.run('c:SPACHECKSCAN', [None, None])
        txt = report_text(vm)
        check("[10r] corners open by %s: one frame, measured OK" % gap,
              OK_ROW in txt
              and not any('Title block' in r for r in rows(txt, 1))
              and not any('separate borders' in r for r in rows(txt, 4)),
              repr(rows(txt, 1) + rows(txt, 4)))


def test_two_sheets_with_open_corners_are_still_two():
    """The slack joins a frame's own lines, never two sheets."""
    vm = spa_vm()
    spa = live(vm)
    four_lines(vm, -100.0, -100.0, 422.4, 326.175, 0.5)
    four_lines(vm, 2000.0, -100.0, 422.4, 326.175, 0.5)
    vm.run('c:SPACHECKSCAN', [None, spa])
    txt = report_text(vm)
    check("[10r] the spa's own frame reads OK",
          OK_ROW in txt and not any('Title block' in r for r in rows(txt, 1)),
          repr(rows(txt, 1)))
    check("[10r] and the other sheet is counted, not merged",
          any("2 separate borders on layer 'border'" in r
              for r in rows(txt, 4)), repr(rows(txt, 4)))


def test_a_frame_open_wider_than_the_slack_is_measured_whole():
    """A frame whose corners are open wider than the slack still comes
    apart into lines; the nearest has no size, so everything on the
    layer is measured together rather than 'no measurable size'."""
    vm = spa_vm()
    four_lines(vm, -100.0, -100.0, 422.4, 326.175, 20.0)
    vm.run('c:SPACHECKSCAN', [None, None])
    txt = report_text(vm)
    check("[10r] measured whole, OK, with no 'separate borders' row",
          OK_ROW in txt
          and not any('Title block' in r for r in rows(txt, 1))
          and not any('separate borders' in r for r in rows(txt, 4)),
          repr(rows(txt, 1) + rows(txt, 4)))


# ------------------------------------------------------------------
# [9] TUTORIALSPACHECK's practice drawing under a moved UCS
# ------------------------------------------------------------------

class ShiftedUCS:
    """A UCS whose origin sits at WCS (ox, oy): trans adds or takes off
    the offset (not for a displacement), and (command ...) reads every
    point it is handed as a UCS point, as AutoCAD's does.  getpoint's
    scripted answers are UCS points already."""

    def __init__(self, ox, oy):
        self.o = (ox, oy)

    def __enter__(self):
        self.trans = BUILTINS[Sym('trans')]
        self.command = BUILTINS[Sym('command')]
        ox, oy = self.o

        def is_pt(v):
            return (isinstance(v, list) and len(v) in (2, 3)
                    and all(isinstance(c, (int, float)) for c in v))

        def trans(vm, a):
            p = list(a[0])
            disp = len(a) > 3 and a[3] is not NIL
            if disp:
                return p
            frm, to = a[1], a[2]
            k = (1 if (frm == 1 and to == 0) else
                 -1 if (frm == 0 and to == 1) else 0)
            out = [p[0] + k * ox, p[1] + k * oy] + p[2:]
            return out

        real_cmd = self.command

        def command(vm, a):
            a = [[v[0] + ox, v[1] + oy] + list(v[2:]) if is_pt(v) else v
                 for v in a]
            return real_cmd(vm, a)

        BUILTINS[Sym('trans')] = trans
        BUILTINS[Sym('command')] = command
        return self

    def __exit__(self, *exc):
        BUILTINS[Sym('trans')] = self.trans
        BUILTINS[Sym('command')] = self.command
        return False


def test_the_practice_drawing_holds_together_under_a_moved_ucs():
    """UCS origin at WCS (1000,500).  The rectangles were entmade at the
    raw UCS pick while DIMALIGNED read the same numbers as UCS, so every
    practice dim floated 1000 off its rectangle and the scan reported
    faults nobody planted."""
    vm = VM()
    vm.load(PATHS['spacheck'])
    with ShiftedUCS(1000.0, 500.0):
        vm.run('c:TUTORIALSPACHECK',
               ['Demo', [10.0, 20.0, 0.0], '', '', '',
                'Yes', None, None, 'No'])
    txt = report_text(vm)
    bad = rows(txt, 1)
    check("[9] the scan names the three planted faults and nothing else",
          len(bad) == 3, repr(bad))
    covers = [e for e in live(vm) if ent_dict(vm, e).get(0) == 'LWPOLYLINE'
              and ent_dict(vm, e).get(8) == 'COVER']
    first = [p for p in vm.entdata[covers[0]]
             if isinstance(p, list) and p and p[0] == 10][0] if covers else None
    check("[9] the practice cover sits where the drafter clicked",
          first is not None and abs(first[1] - 1010.0) < 1e-9
          and abs(first[2] - 520.0) < 1e-9, repr(first))
    # the first explanation zooms to the cover: its window, read as the
    # UCS points ZOOM takes, has to land around the cover's WORLD box
    zooms = [c for c in vm.commands
             if c and c[0] == '_.ZOOM' and len(c) > 3 and c[1] == '_Window']
    x0, y0 = (first[1], first[2]) if first else (None, None)
    check("[9] the walk's zoom window frames the cover itself",
          bool(zooms) and x0 is not None
          and zooms[0][2][0] <= x0 <= zooms[0][3][0]
          and zooms[0][2][1] <= y0 <= zooms[0][3][1], repr(zooms[:1]))


# ------------------------------------------------------------------
# [8] CLEARDIM from a layout viewport sweeps model space
# ------------------------------------------------------------------

def cleardim_vm():
    """CLEARDIM with a DIMSTYLE record carrying a text height (as
    tests/test_cleardim.py's newvm builds it)."""
    from lispvm import Ent
    vm = VM()
    vm.load(PATHS['cleardim'])
    rec = Ent()
    vm.recdata[rec] = [Dot(0, 'DIMSTYLE'), Dot(2, 'STANDARD'),
                       Dot(140, 4.5), Dot(40, 1.0), Dot(44, 1.5), Dot(73, 0)]
    vm.tables.setdefault('DIMSTYLE', set()).add('STANDARD')
    vm.tablerecs.setdefault('DIMSTYLE', {})['STANDARD'] = rec
    return vm


def test_cleardim_from_a_viewport_finds_the_model_dimensions():
    """Layout1, working inside its viewport: CTAB is 'Layout1', so the
    old (410 . CTAB) sweep took the sheet's paper-space ink, found no
    dimension in it, and said there was nothing to do."""
    vm = cleardim_vm()
    vm.loads('(entmakex (list (cons 0 "DIMENSION") (cons 8 "0")'
             ' (cons 3 "STANDARD") (cons 70 0) (cons 50 0.0)'
             ' (list 13 0.0 0.0 0.0) (list 14 100.0 0.0 0.0)'
             ' (list 10 0.0 20.0 0.0) (list 11 50.0 26.0 0.0)'
             ' (cons 1 "A-TEXT")))')
    vm.loads('(entmakex (list (cons 0 "LINE") (cons 8 "0")'
             ' (list 10 50.0 22.0 0.0) (list 11 50.0 30.0 0.0)))')
    # the sheet's own ink: a title-block line on the layout
    vm.loads('(entmakex (list (cons 0 "LINE") (cons 8 "0")'
             ' (cons 410 "Layout1")'
             ' (list 10 0.0 0.0 0.0) (list 11 1000.0 0.0 0.0)))')
    vm.sysvars['TILEMODE'] = 0
    vm.sysvars['CTAB'] = 'Layout1'
    vm.sysvars['CVPORT'] = 2
    vm.run('c:CLEARDIMSCAN', [None, None])
    txt = said(vm)
    check("[8] the model-space dimension is found from the viewport",
          'no dimensions in the selection' not in txt
          and 'to slide clear' in txt, txt[-400:])


def test_cleardim_on_the_paper_itself_keeps_to_the_layout():
    vm = cleardim_vm()
    vm.sysvars['TILEMODE'] = 0
    vm.sysvars['CTAB'] = 'Layout1'
    vm.sysvars['CVPORT'] = 1
    check("[8] on the paper the space is the layout",
          vm.loads('(cd:space)') == 'Layout1')
    vm.sysvars['TILEMODE'] = 1
    vm.sysvars['CTAB'] = 'Model'
    vm.sysvars['CVPORT'] = 2
    check("[8] on the Model tab it is Model",
          vm.loads('(cd:space)') == 'Model')


# ------------------------------------------------------------------
# [5] LINTXTCHK places the checklist where the drafter clicked
# ------------------------------------------------------------------

def test_lintxtchk_lands_on_the_click_under_a_moved_ucs():
    """UCS origin on a pool corner at WCS (1000,500): the pick is a UCS
    point, entmake takes WCS, and the checklist landed 1000 off."""
    vm = VM()
    vm.load(PATHS['lintxtchk'])
    with ShiftedUCS(1000.0, 500.0):
        vm.run('c:LINTXTCHK', [[10.0, 20.0, 0.0]])
    texts = [e for e in live(vm) if ent_dict(vm, e).get(0) == 'TEXT']
    first = grp(vm, texts[0], 10) if texts else None
    check("[5] the first line sits at the click, in world numbers",
          first is not None and abs(first[0] - 1010.0) < 1e-9
          and abs(first[1] - 520.0) < 1e-9, repr(first))
    check("[5] and the column still steps down from there",
          len(texts) > 1 and abs(grp(vm, texts[1], 10)[1]
                                 - (520.0 - 12.0 * 1.6)) < 1e-9,
          repr(grp(vm, texts[1], 10) if len(texts) > 1 else None))


# ------------------------------------------------------------------

def main():
    tests = [(n, f) for n, f in globals().items()
             if n.startswith('test_') and callable(f)]
    for name, fn in tests:
        print(name)
        try:
            fn()
        except (AssertionError, LispError) as e:
            print(f"  FAIL {name}: {e}")
            FAILS.append(name)
    print()
    if FAILS:
        print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
        sys.exit(1)
    print("all review-b regression checks passed")


if __name__ == '__main__':
    main()
