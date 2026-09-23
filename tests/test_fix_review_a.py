#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The review tools -- DIMCHECK, COVERCHECK and LINFINCHECK -- say only
what they did.

Each scenario here is a way one of them used to report a change the
drawing never took, leave the drafter's session in a state the next
command inherits, or read the wrong part of the drawing:

  * a LOCKED layer refuses entmod and entdel, so every write the
    review makes after "Unlock for this run? No" -- the preview of a
    moved dimension point, an arc re-fit, a merge, a flag colour --
    is refused, and each one used to be reported as done ("MOVED onto
    the nearest object", "merged into one line (cyan)", "endpoints
    OK", "flagged to fix (red)");
  * LINFINCHECK's liner-pattern wipe counted a refused ATTRIB write as
    WIPED;
  * the re-lock in each *error* handler shared one catch with the
    colour restore, so a throw there left the layer unlocked;
  * TUTORIALDIMCHECK / TUTORIALLINFINCHECK called the scan COMMAND,
    whose own handler shadowed the tutorial's: an Esc at the scan's
    highlight left the tutorial's UNDO group open and CMDECHO at 0;
  * the scans' Enter fallback swept every layout's paper space, and
    COVERCHECK's pad census and COVERSCAN's fallback read CTAB, which
    names the sheet from inside a layout viewport;
  * COVERCHECK read (and rewrote) whichever Tech Title the database
    returned first when a drawing holds one per sheet;
  * LINFINCHECK measured the UNION of every sheet's border;
  * a missed click at COVERCHECK's Replacement Disclaimer pick wrote
    "block is MISSING" in red;
  * TUTORIALCOVERCHECK's demo -INSERT read its typed rotation through
    ANGBASE, and its -LINETYPE Load left a "Reload it?" prompt open;

plus the passes no suite entered: COVERCHECK's and LINFINCHECK's arc
re-fit and overlap merge, DIMCHECK's unstage, and the RESCUE / CLEAN
sweeps run over real marks instead of an empty drawing.

The VM models none of locked layers, a missed pick's ERRNO, paper
space or a layout viewport, so each is modelled here: entmod/entdel
refuse on a layer whose table record carries the lock bit; entsel
answers a scripted 'MISS' with nil and ERRNO 7; entities carry an
explicit (410 . "Layout1"); and TILEMODE/CVPORT/CTAB are set the way a
viewport on a layout reads.

Run: python3 tests/test_fix_review_a.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_fix_review_a.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Dot, Sym, BUILTINS, NIL  # noqa: E402

HERE = os.path.dirname(__file__)
# lispvm's _remap_root sends these to shared/parts/ when
# CALOFIN_LISP_ROOT=shared, exactly as test_dimcheck.py's paths work
LISP = os.path.join(HERE, '..', 'lisp')
DIMCHECK = os.path.join(LISP, 'dimcheck', 'dimcheck.lsp')
COVERCHECK = os.path.join(LISP, 'covercheck', 'covercheck.lsp')
LINFINCHECK = os.path.join(LISP, 'linfincheck', 'linfincheck.lsp')
ROOT = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp'

TWO_PI = 2.0 * math.pi

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   " + label)
    else:
        print("  FAIL " + label + (('  -- ' + str(detail)[:600]) if detail else ''))
        FAILS.append(label)


# ------------------------------------------------------------------
# the vlax-curve surface the attachment audits use, read off the VM's
# own entity store (the same shims test_dimcheck.py installs)
# ------------------------------------------------------------------

def grp(vm, e, code):
    """First DXF group value on an entity, None when absent."""
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else g[1:]
    return None


def _pts10(vm, e):
    out = []
    for g in vm.entdata.get(e, []):
        if isinstance(g, list) and g and g[0] == 10:
            out.append([float(g[1]), float(g[2])])
        elif isinstance(g, Dot) and g.a == 10:
            out.append([float(g.b[0]), float(g.b[1])])
    return out


def _arc_geo(vm, e):
    c = grp(vm, e, 10)
    r = float(grp(vm, e, 40))
    a0 = float(grp(vm, e, 50) or 0.0)
    a1 = float(grp(vm, e, 51) or 0.0)
    sweep = (a1 - a0) % TWO_PI
    if sweep <= 1e-12:
        sweep = TWO_PI
    return (float(c[0]), float(c[1])), r, a0, sweep


def _arc_pt(c, r, a):
    return [c[0] + r * math.cos(a), c[1] + r * math.sin(a), 0.0]


def _seg_closest(p, a, b):
    ax, ay, bx, by = float(a[0]), float(a[1]), float(b[0]), float(b[1])
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 < 1e-24:
        return [ax, ay, 0.0]
    t = ((p[0] - ax) * dx + (p[1] - ay) * dy) / l2
    t = max(0.0, min(1.0, t))
    return [ax + t * dx, ay + t * dy, 0.0]


def _poly_edges(vm, e):
    vs = _pts10(vm, e)
    flags = grp(vm, e, 70) or 0
    edges = list(zip(vs, vs[1:]))
    if int(flags) & 1 and len(vs) > 2:
        edges.append((vs[-1], vs[0]))
    return edges


def _closest_on(vm, e, p):
    t = grp(vm, e, 0)
    if t == 'LINE':
        return _seg_closest(p, grp(vm, e, 10), grp(vm, e, 11))
    if t == 'ARC':
        c, r, a0, sw = _arc_geo(vm, e)
        dx, dy = p[0] - c[0], p[1] - c[1]
        if dx * dx + dy * dy < 1e-24:
            return _arc_pt(c, r, a0)
        ang = math.atan2(dy, dx)
        if (ang - a0) % TWO_PI <= sw:
            return _arc_pt(c, r, ang)
        p1, p2 = _arc_pt(c, r, a0), _arc_pt(c, r, a0 + sw)
        return p1 if math.dist(p[:2], p1[:2]) <= math.dist(p[:2], p2[:2]) \
            else p2
    if t == 'CIRCLE':
        c, r = grp(vm, e, 10), float(grp(vm, e, 40))
        dx, dy = p[0] - c[0], p[1] - c[1]
        ln = math.hypot(dx, dy)
        if ln < 1e-12:
            return [c[0] + r, c[1], 0.0]
        return [c[0] + dx / ln * r, c[1] + dy / ln * r, 0.0]
    if t == 'LWPOLYLINE':
        # straight edges only - the fixtures draw bulge-free polylines
        best = None
        for a, b in _poly_edges(vm, e):
            q = _seg_closest(p, a, b)
            if best is None or math.dist(p[:2], q[:2]) < \
                    math.dist(p[:2], best[:2]):
                best = q
        if best is None:
            raise LispError('vlax-curve: empty polyline', vm)
        return best
    raise LispError(f'vlax-curve: no curve for {t}', vm)


def _curve_ent(vm, a):
    e = a[0]
    if not isinstance(e, lispvm.Ent) or e in vm.deleted:
        raise LispError('vlax-curve: not an entity', vm)
    return e


def _ends(vm, e):
    t = grp(vm, e, 0)
    if t == 'LINE':
        p1, p2 = grp(vm, e, 10), grp(vm, e, 11)
        return ([float(p1[0]), float(p1[1]), 0.0],
                [float(p2[0]), float(p2[1]), 0.0])
    if t == 'ARC':
        c, r, a0, sw = _arc_geo(vm, e)
        return _arc_pt(c, r, a0), _arc_pt(c, r, a0 + sw)
    if t == 'LWPOLYLINE' and not (int(grp(vm, e, 70) or 0) & 1):
        vs = _pts10(vm, e)
        return ([vs[0][0], vs[0][1], 0.0], [vs[-1][0], vs[-1][1], 0.0])
    raise LispError(f'vlax-curve: no ends on {t}', vm)


def _length(vm, e):
    t = grp(vm, e, 0)
    if t == 'LINE':
        p1, p2 = grp(vm, e, 10), grp(vm, e, 11)
        return math.dist(p1[:2], p2[:2])
    if t == 'ARC':
        _c, r, _a0, sw = _arc_geo(vm, e)
        return r * sw
    if t == 'LWPOLYLINE':
        return sum(math.dist(a, b) for a, b in _poly_edges(vm, e))
    raise LispError(f'vlax-curve: no length on {t}', vm)




def install_curve_shims():
    B = BUILTINS

    B[Sym('vlax-curve-getclosestpointto')] = \
        lambda vm, a: _closest_on(vm, _curve_ent(vm, a), a[1])
    B[Sym('vlax-curve-getstartpoint')] = \
        lambda vm, a: _ends(vm, _curve_ent(vm, a))[0]
    B[Sym('vlax-curve-getendpoint')] = \
        lambda vm, a: _ends(vm, _curve_ent(vm, a))[1]

    def end_param(vm, a):
        e = _curve_ent(vm, a)
        if grp(vm, e, 0) == 'ARC':
            return _arc_geo(vm, e)[3]          # param = swept angle
        return _length(vm, e)                  # param = distance

    def dist_at_param(vm, a):
        e = _curve_ent(vm, a)
        if grp(vm, e, 0) == 'ARC':
            return _arc_geo(vm, e)[1] * float(a[1])
        return float(a[1])

    def point_at_dist(vm, a):
        e, d = _curve_ent(vm, a), float(a[1])
        t = grp(vm, e, 0)
        if t == 'ARC':
            c, r, a0, _sw = _arc_geo(vm, e)
            return _arc_pt(c, r, a0 + d / r)
        if t == 'LINE':
            p1, p2 = grp(vm, e, 10), grp(vm, e, 11)
            ln = math.dist(p1[:2], p2[:2])
            t01 = 0.0 if ln < 1e-12 else max(0.0, min(1.0, d / ln))
            return [p1[0] + (p2[0] - p1[0]) * t01,
                    p1[1] + (p2[1] - p1[1]) * t01, 0.0]
        raise LispError(f'vlax-curve: pointAtDist on {t}', vm)

    B[Sym('vlax-curve-getendparam')] = end_param
    B[Sym('vlax-curve-getdistatparam')] = dist_at_param
    B[Sym('vlax-curve-getpointatdist')] = point_at_dist


# The VM's ssget cannot evaluate an xdata filter, so a "_X" sweep for
# (-3 ("DIMCHECK")) - how clear-old and DIMCHECKRESCUE find their
# marks - is answered here from each entity's stored -3 group.
def install_ssget_xdata():
    base = BUILTINS[Sym('ssget')]

    def apps_of(vm, e):
        out = set()
        for g in vm.entdata.get(e, []):
            if isinstance(g, list) and g and g[0] == -3:
                for sub in g[1:]:
                    if isinstance(sub, list) and sub and \
                            isinstance(sub[0], str):
                        out.add(sub[0].upper())
        return out

    def ssget(vm, a):
        pairs = lispvm._filt_pairs(a) or []
        apps = [w for c, w in pairs if c == -3]
        mode = ' '.join(x for x in a if isinstance(x, str))
        if apps and mode.upper().lstrip('_') in ('X', 'A'):
            want = apps[0][0].upper() if isinstance(apps[0], list) and \
                apps[0] else ''
            rest = [(c, w) for c, w in pairs if c != -3]
            ents = [e for e in vm.entities
                    if e not in vm.deleted and want in apps_of(vm, e)
                    and (not rest or lispvm._filt_hit(vm, e, rest))]
            return ['<ss>'] + ents if ents else NIL
        return base(vm, a)

    BUILTINS[Sym('ssget')] = ssget


install_curve_shims()
install_ssget_xdata()


# ------------------------------------------------------------------
# a LOCKED layer, as AutoCAD enforces it: entmod answers nil and entdel
# refuses for an entity on a layer whose table record carries bit 4.
# The record itself stays writable (that is how a layer is unlocked),
# and entmake is not touched -- AutoCAD creates on a locked layer.
# ------------------------------------------------------------------

_BASE_ENTMOD = BUILTINS[Sym('entmod')]
_BASE_ENTDEL = BUILTINS[Sym('entdel')]
#: set True to make every entity write THROW, the way a future bug in
#: a colour restore would: the handlers must still re-lock
STATE = {'throw': False}


def layer_locked(vm, name):
    rec = vm.tablerecs.get('LAYER', {}).get(str(name).upper())
    if rec is None:
        return False
    for g in vm.recdata.get(rec, []):
        if isinstance(g, Dot) and g.a == 70:
            return bool(int(g.b) & 4)
    return False


def _entmod_locked(vm, a):
    alist = a[0] or []
    ename = next((g.b for g in alist
                  if isinstance(g, Dot) and g.a == -1), None)
    if ename is not None and ename in vm.recdata:
        return _BASE_ENTMOD(vm, a)
    if STATE['throw']:
        raise LispError('entmod: simulated failure inside the handler', vm)
    lay = next((g.b for g in alist if isinstance(g, Dot) and g.a == 8), None)
    if lay is not None and layer_locked(vm, lay):
        return NIL
    return _BASE_ENTMOD(vm, a)


def _entdel_locked(vm, a):
    e = a[0]
    if isinstance(e, lispvm.Ent) and layer_locked(vm, grp(vm, e, 8) or '0'):
        return NIL
    return _BASE_ENTDEL(vm, a)


BUILTINS[Sym('entmod')] = _entmod_locked
BUILTINS[Sym('entdel')] = _entdel_locked
# set-layer-lock clears the bit with (logand old (~ 4))
BUILTINS.setdefault(Sym('~'), lambda vm, a: ~int(a[0]))


# a missed click: entsel answers nil exactly as it does for Enter, and
# only ERRNO (7) tells the two apart
_BASE_ENTSEL = BUILTINS[Sym('entsel')]


def _entsel_miss(vm, a):
    if vm.script and vm.script[0] == 'MISS':
        vm.script[0] = None
        r = _BASE_ENTSEL(vm, a)
        vm.sysvars['ERRNO'] = 7
        return r
    return _BASE_ENTSEL(vm, a)


BUILTINS[Sym('entsel')] = _entsel_miss


# ------------------------------------------------------------------
# fixture builders and readers
# ------------------------------------------------------------------

def load(path):
    vm = VM()
    vm.load(path)
    vm.printed = []
    return vm


def layer(vm, name, locked=False):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
             ' \'(62 . 7) \'(6 . "Continuous")))' % (name, 4 if locked else 0))


def line(vm, p1, p2, lay='0', space=None):
    vm.loads('(entmakex (list (cons 0 "LINE") (cons 8 "%s")%s'
             ' (list 10 %r %r 0.0) (list 11 %r %r 0.0)))'
             % (lay, ' (cons 410 "%s")' % space if space else '',
                p1[0], p1[1], p2[0], p2[1]))
    return vm.entities[-1]


def dim(vm, p13, p14, p10, lay='0', style='STANDARD', ang=0.0):
    vm.loads('(entmake (list (cons 0 "DIMENSION") (cons 8 "%s")'
             ' (cons 3 "%s") (cons 70 0) (cons 50 %r)'
             ' (list 13 %r %r 0.0) (list 14 %r %r 0.0)'
             ' (list 10 %r %r 0.0)))'
             % (lay, style, ang, p13[0], p13[1], p14[0], p14[1],
                p10[0], p10[1]))
    return vm.entities[-1]


def arc(vm, c, r, a0, a1, lay='0'):
    vm.loads('(entmake (list (cons 0 "ARC") (cons 8 "%s")'
             ' (list 10 %r %r 0.0) (cons 40 %r) (cons 50 %r)'
             ' (cons 51 %r)))' % (lay, c[0], c[1], r, a0, a1))
    return vm.entities[-1]


def poly(vm, pts, lay, closed=True):
    vs = ' '.join('(list 10 %r %r)' % (x, y) for x, y in pts)
    vm.loads('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
             ' (cons 8 "%s") (cons 100 "AcDbPolyline") (cons 90 %d)'
             ' (cons 70 %d) %s))'
             % (lay, len(pts), 1 if closed else 0, vs))
    return vm.entities[-1]


def block(vm, name, at, attrs=(), lay='0', attlay='0'):
    """An INSERT with its ATTRIBs and SEQEND trailing it, as AutoCAD
    stores an attributed insert."""
    vm.loads('(entmakex (list (cons 0 "INSERT") (cons 8 "%s") (cons 2 "%s")'
             ' (list 10 %r %r 0.0)%s))'
             % (lay, name, at[0], at[1], ' (cons 66 1)' if attrs else ''))
    ins = vm.entities[-1]
    for tag, val in attrs:
        esc = val.replace('\\', '\\\\').replace('"', '\\"')
        vm.loads('(entmake (list (cons 0 "ATTRIB") (cons 8 "%s")'
                 ' (cons 2 "%s") (cons 1 "%s")))' % (attlay, tag, esc))
    if attrs:
        vm.loads('(entmake (list (cons 0 "SEQEND") (cons 8 "%s")))' % attlay)
    return ins


def attrib_value(vm, ins, tag):
    i = vm.entities.index(ins) + 1
    while i < len(vm.entities):
        e = vm.entities[i]
        if grp(vm, e, 0) != 'ATTRIB':
            break
        if (grp(vm, e, 2) or '').upper() == tag.upper():
            return grp(vm, e, 1)
        i += 1
    return None


def color_of(vm, e):
    c = grp(vm, e, 62)
    return 256 if c is None else c


def selectable(vm):
    return [e for e in vm.entities if e not in vm.deleted
            and grp(vm, e, 0) not in ('ATTRIB', 'SEQEND')]


def live(vm):
    return [e for e in vm.entities if e not in vm.deleted]


def mtext_of(vm, e):
    head, tail = [], ''
    for p in vm.entdata[e]:
        if isinstance(p, Dot):
            if p.a == 3:
                head.append(p.b)
            elif p.a == 1 and not tail:
                tail = p.b
    return ''.join(head) + tail


def report(vm, lay):
    out = []
    for e in live(vm):
        d = {p.a: p.b for p in vm.entdata[e] if isinstance(p, Dot)}
        if d.get(0) == 'MTEXT' and d.get(8) == lay:
            out.append(mtext_of(vm, e))
    return '\n'.join(out)


def printed(vm):
    return ''.join(vm.printed)


def prompts(vm):
    return [str(p) for p, _a in vm.prompts]


def responder(table):
    """One scripted answer that reads the prompt it was reached at:
    TABLE is [(substring, answer-or-list), ...]; a list is consumed one
    answer per matching prompt.  The same script then drives the old
    code and the new, which ask different questions -- that difference
    is what these scenarios are about."""
    table = [(k, list(v) if isinstance(v, list) else v) for k, v in table]

    def r(vm):
        p = vm.lastprompt
        for key, val in table:
            if key in p:
                if isinstance(val, list):
                    val = val.pop(0) if val else None
                # an answer that is a function is called, as the VM
                # calls a scripted one: that is how an Esc is delivered
                return val(vm) if callable(val) else val
        raise AssertionError('unexpected prompt %r' % p)
    return r


def run(vm, cmd, fixed, table=None, n=40):
    """Run CMD: FIXED answers first, then the responder for anything
    else.  Answers the responder is not asked for are left over, which
    is fine here -- the responder is sized for the longest variant."""
    script = list(fixed) + ([responder(table)] * n if table else [])
    try:
        vm.run(cmd, script)
    except LispError as e:
        if 'scripted answers left over' not in str(e):
            raise


def esc(vm):
    raise LispError('Function cancelled', vm)


def staircase(vm):
    """LINFINCHECK's side view: three treads and three risers at right
    angles, total rise 36."""
    for p1, p2 in [((100, 100), (112, 100)), ((112, 112), (124, 112)),
                   ((124, 124), (136, 124)), ((112, 100), (112, 112)),
                   ((124, 112), (124, 124)), ((136, 124), (136, 136))]:
        line(vm, (float(p1[0]), float(p1[1])), (float(p2[0]), float(p2[1])))


# ==================================================================
def liner_wipe_on_locked_attribs():
    print("== LINFINCHECK: a liner field the drawing refused is NOT 'WIPED' ==")
    # The ATTRIBs sit on a locked layer the unlock offer never names (an
    # ATTRIB is never in a selection set).  The title block's date sits
    # there too, and its line already said "NOT updated" -- the pattern
    # field beside it used to say WIPED.
    vm = load(LINFINCHECK)
    layer(vm, 'TB-LOCKED', locked=True)
    staircase(vm)
    poly(vm, [(0.0, 0.0), (704.0, 0.0), (704.0, 543.625), (0.0, 543.625)], 'border')
    title = block(vm, 'Tech Title', (600.0, 50.0),
                  [('WallHt', "Finished Wall Ht = 36''"),
                   ('Date', 'Date = 05/01/2024')], attlay='TB-LOCKED')
    liner = block(vm, 'Liner Material with Step', (500.0, 200.0),
                  [('PATTERN', 'Pattern: Not Supplied'),
                   ('WALL', 'Blue Granite - #ERROR'),
                   ('FLOOR', 'Bluestone')], attlay='TB-LOCKED')
    run(vm, 'c:LINFINCHECK', [None, selectable(vm)])
    txt = report(vm, 'LINFINCHECK-REPORT')
    check("the fields still read what they read",
          attrib_value(vm, liner, 'PATTERN') == 'Pattern: Not Supplied'
          and attrib_value(vm, liner, 'WALL') == 'Blue Granite - #ERROR',
          (attrib_value(vm, liner, 'PATTERN'), attrib_value(vm, liner, 'WALL')))
    check("the report does not call them WIPED",
          'WIPED' not in txt and 'now reads' not in txt, txt)
    check("it says they still need wiping, and why",
          ("PATTERN, WALL carries NOT & ERROR - NEEDS WIPING, could not write"
           " it (locked layer?)") in txt, txt)
    check("the summary counts them as refused, not wiped",
          'NEEDS WIPING: 2 pattern field(s) could not be written' in txt, txt)
    check("...and the console agrees",
          'could NOT wipe PATTERN, WALL' in printed(vm)
          and 'wiped NOT' not in printed(vm), printed(vm)[-800:])
    check("the date beside it was honest already (control)",
          "NOT TODAY'S DATE" in txt and 'fix it in the Tech Title' in txt, txt)




def linfincheck_flags_on_a_locked_layer():
    print("== LINFINCHECK: a flag colour a locked layer refused is not 'red' ==")
    # The Step Attachment the drafter calls wrong, and the side view's
    # height dimension that disagrees with WallHt, are flagged by colour
    # alone -- on a locked layer the colour never goes on, and both the
    # item lines and the summary used to say "red" regardless.
    vm = load(LINFINCHECK)
    layer(vm, 'SA', locked=True)
    staircase(vm)
    poly(vm, [(0.0, 0.0), (704.0, 0.0), (704.0, 543.625), (0.0, 543.625)],
         'border')
    satt = block(vm, 'Step Attachment', (500.0, 300.0), lay='SA')
    today_ = vm.loads('(lfc:mdy-str (lfc:today-mdy))')
    block(vm, 'Tech Title', (600.0, 50.0),
          [('WallHt', "Finished Wall Ht = 40''"), ('Date', today_)])
    hd = dim(vm, (136.0, 100.0), (136.0, 136.0), (150.0, 118.0), 'SA',
             ang=math.pi / 2.0)
    run(vm, 'c:LINFINCHECK', [None, selectable(vm)], [
        ('Unlock for this run?', 'No'),
        ('[Move/Keep/Pick]', 'Keep'),        # the old code asked
        ('Is this dimension correct?', 'Yes'),
        ('is the correct one placed?', 'No'),
    ])
    txt = report(vm, 'LINFINCHECK-REPORT')
    check("the Step Attachment line says the colour did not go on",
          ('Step Attachment %s: WRONG ONE - flagged to fix - layer locked,'
           ' NOT coloured' % satt.handle) in txt
          and color_of(vm, satt) == 256, txt[:1500])
    check("...and so does the Steps summary",
          'Step Attachment flagged WRONG - layer locked, NOT coloured' in txt
          and 'flagged WRONG (red)' not in txt, txt[:1500])
    check("the height dimension is not 'marked red'",
          ('Height dim %s states 36.0000' % hd.handle) in txt
          and 'marked red' not in txt
          and 'dimension on a locked layer - NOT marked' in txt
          and color_of(vm, hd) == 256, txt[:1800])


# ==================================================================
def dimcheck_declined_unlock():
    print("== DIMCHECK: 'Unlock for this run? No' - nothing claimed done ==")
    # Everything on a locked WALLS layer: a dimension 10 off its line, a
    # clean one the drafter answers No to, an arc attached to nothing and
    # an overlapping pair.  Declined, the review still gives its read-only
    # verdicts, but it asks no Move/Keep/Pick it cannot carry out and it
    # reports nothing as moved, merged or coloured.
    vm = load(DIMCHECK)
    layer(vm, 'WALLS', locked=True)
    a = line(vm, (0.0, 0.0), (100.0, 0.0), 'WALLS')
    b = line(vm, (0.0, 80.0), (100.0, 80.0), 'WALLS')
    d1 = dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0), 'WALLS')   # 10 off b
    d2 = dim(vm, (0.0, 0.0), (100.0, 0.0), (50.0, 30.0), 'WALLS')      # clean
    f = arc(vm, (102.0, 25.0), 25.0, -math.pi / 2.0, math.pi / 2.0, 'WALLS')
    c1 = line(vm, (0.0, -60.0), (100.0, -60.0), 'WALLS')
    c2 = line(vm, (60.0, -60.0), (180.0, -60.0), 'WALLS')
    before = {e: list(vm.entdata[e]) for e in (d1, f, c1, c2)}
    run(vm, 'c:DIMCHECK', [None, selectable(vm)], [
        ('Unlock for this run?', 'No'),
        ('[Move/Keep/Pick]', 'Move'),            # the old code asked; Move it
        ('Is this dimension correct?', ['Yes', 'No']),
        ('[Merge/Flag/Leave]', 'Merge'),
    ])
    txt = report(vm, 'DIMCHECK-REPORT')
    out = printed(vm)
    check("no Move/Keep/Pick was put to the drafter",
          not [p for p in prompts(vm) if 'Move/Keep/Pick' in p], prompts(vm))
    check("nothing on the locked layer changed",
          all(vm.entdata[e] == before[e] for e in before)
          and c1 not in vm.deleted and c2 not in vm.deleted)
    check("the console never says MOVED, SNAPPED or Merged",
          'MOVED onto' not in out and 'SNAPPED' not in out
          and 'Merged into one line' not in out, out[-1500:])
    check("the dashboard adjusts no point and counts the locked one",
          'points adjusted: 0, NOT moved (layer locked): 1)' in txt, txt)
    check("the stray dimension's line names it NOT ATTACHED, not moved",
          ('Dim %s [STANDARD] = 100.0000: OK - dimension point 2 off by'
           ' 10.0000 - NOT ATTACHED, layer locked, NOT moved' % d1.handle) in txt,
          txt)
    check("the No is a flag, but not a red one",
          ('Dim %s [STANDARD] = 100.0000: FLAGGED to fix - layer locked, NOT'
           ' coloured' % d2.handle) in txt
          and 'flagged to fix: 1 - 1 NOT coloured, layer locked' in txt, txt)
    check("the detached arc is not 'endpoints OK'",
          ('Arc %s: 2 endpoint(s) NOT ATTACHED - layer locked, NOT moved'
           % f.handle) in txt and 'endpoints OK' not in txt, txt)
    check("the arc dashboard counts it apart from OK and moved",
          ('Arcs checked: 1 (OK: 0, with endpoints moved: 0, endpoints moved'
           ' in total: 0, detached but layer locked: 1)') in txt, txt)
    check("the Merge the layer refused is not reported as merged",
          'could NOT merge - layer locked, left as drawn' in txt
          and ('(merged: 0, flagged: 0, left as drawn: 0, could NOT merge'
               ' (layer locked): 1)') in txt, txt)




def locked_gates_in_sibling_copies():
    print("== the same four gates in COVERCHECK's and LINFINCHECK's copies ==")
    for label, path, pre in [('COVERCHECK', COVERCHECK, 'cchk'),
                             ('LINFINCHECK', LINFINCHECK, 'lfc')]:
        vm = load(path)
        layer(vm, 'WALLS', locked=True)
        b = line(vm, (0.0, 80.0), (100.0, 80.0), 'WALLS')
        d1 = dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0), 'WALLS')
        f = arc(vm, (102.0, 25.0), 25.0, -math.pi / 2.0, math.pi / 2.0, 'WALLS')
        a = line(vm, (0.0, 0.0), (100.0, 0.0), 'WALLS')
        c1 = line(vm, (0.0, -60.0), (100.0, -60.0), 'WALLS')
        c2 = line(vm, (60.0, -60.0), (180.0, -60.0), 'WALLS')
        for k, e in dict(b=b, a=a, d1=d1, f=f, c1=c1, c2=c2).items():
            vm.globals[Sym('t:' + k)] = e
        vm.loads('''
          (defun t:dimpt ()
            (%(p)s:audit-dim-point t:d1 14 "dimension point 2" (list t:b t:a t:c1) nil))
          (defun t:arcend ()
            (%(p)s:review-arc-end t:f 'start "arc start point" (list t:b t:a t:c1)))
          (defun t:merge ( / la lb)
            (setq la (car (%(p)s:ent-segs t:c1))
                  lb (car (%(p)s:ent-segs t:c2)))
            (%(p)s:merge-lines la lb (%(p)s:overlap-info la lb)))
          (defun t:paint () (%(p)s:set-color t:d1 1))
        ''' % {'p': pre})
        r = vm.run('t:dimpt', [])          # an empty script: a question raises
        check(f"{label}: a stray point on a locked layer is reported, not asked",
              isinstance(r, list) and str(r[2]).lower() == 'locked'
              and grp(vm, d1, 14)[:2] == [100.0, 90.0], r)
        r = vm.run('t:arcend', [])
        check(f"{label}: a detached arc end on a locked layer is 'locked'",
              isinstance(r, list) and str(r[2]).lower() == 'locked', r)
        r = vm.run('t:merge', [])
        check(f"{label}: a refused merge erases nothing and says so",
              r in (None, NIL, []) and c2 not in vm.deleted and c1 not in vm.deleted,
              r)
        r = vm.run('t:paint', [])
        check(f"{label}: set-color answers nil when the colour did not go in",
              r in (None, NIL, []) and color_of(vm, d1) == 256, r)




# ==================================================================
def relock_survives_the_handler():
    print("== Unlock Yes, then Esc: the layer is locked again, colours back ==")
    # The re-lock shared one vl-catch-all-apply with the colour restore, so
    # anything that threw in a set-color skipped it and left the drafter's
    # layer unlocked with nothing said.  Driven twice per tool: a plain Esc,
    # and an Esc whose handler finds every entity write throwing.


    def esc_and_throw(vm):
        STATE['throw'] = True
        raise LispError('Function cancelled', vm)


    for label, path in [('DIMCHECK', DIMCHECK), ('COVERCHECK', COVERCHECK),
                        ('LINFINCHECK', LINFINCHECK)]:
        for how, stop in [('a plain Esc', esc),
                          ('an Esc whose colour restore throws', esc_and_throw)]:
            STATE['throw'] = False
            vm = load(path)
            vm.handle_errors = True
            layer(vm, 'WALLS', locked=True)
            b = line(vm, (0.0, 80.0), (100.0, 80.0), 'WALLS')
            d1 = dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0), 'WALLS')
            try:
                run(vm, 'c:' + label, [None, selectable(vm)], [
                    ('Unlock for this run?', 'Yes'),
                    ('[Move/Keep/Pick]', stop),
                ])
            finally:
                STATE['throw'] = False
            check(f"{label}, {how}: the handler ran, for the Esc",
                  len(vm.handled_errors) == 1
                  and 'cancelled' in vm.handled_errors[0], vm.handled_errors)
            check(f"{label}, {how}: WALLS is locked again",
                  layer_locked(vm, 'WALLS'))
            if stop is esc:
                check(f"{label}, {how}: the reviewed items wear their own colour",
                      color_of(vm, b) == 256 and color_of(vm, d1) == 256,
                      (color_of(vm, b), color_of(vm, d1)))




# ==================================================================
def tutorial_scan_esc():
    print("== Esc at the tutorial scan's highlight: the tutorial cleans up ==")
    # The tutorials used to call the scan COMMAND, whose own *error* was then
    # the innermost handler: an Esc at "Highlight the drawing" ran only that,
    # and AutoLISP unwound to the command line with the tutorial's UNDO
    # group open (the drafter's next U swallowed their own later work) and
    # CMDECHO at 0.  run() refuses a return with a group still open.
    SPOT = [500.0, 0.0, 0.0]
    for label, path, cmd, before_highlight in [
            ('DIMCHECK', DIMCHECK, 'c:TUTORIALDIMCHECK', 6),
            ('DIMCHECK (alias)', DIMCHECK, 'c:TUTORIALDIMSCAN', 6),
            ('LINFINCHECK', LINFINCHECK, 'c:TUTORIALLINFINCHECK', 7),
            ('LINFINCHECK (alias)', LINFINCHECK, 'c:TUTORIALLINFINSCAN', 7)]:
        vm = load(path)
        vm.handle_errors = True
        sys0 = dict(vm.sysvars)
        # Demo, the spot, Enter through the pauses and the report question
        # and the "_I" probe, then Esc at the scan's own highlight prompt
        script = ['Demo', SPOT] + [None] * before_highlight + [esc]
        try:
            vm.run(cmd, script)
            err = None
        except LispError as e:
            err = str(e)
        check(f"{label}: the run hands the session back (no group left open)",
              err is None, err)
        check(f"{label}: the Esc landed on the scan's highlight prompt",
              vm.lastprompt == 'ssget' and vm.prompts[-1][0] == 'ssget _I',
              (vm.lastprompt, vm.prompts[-2:]))
        check(f"{label}: exactly one handler ran, for the Esc",
              len(vm.handled_errors) == 1
              and 'cancelled' in vm.handled_errors[0], vm.handled_errors)
        check(f"{label}: CMDECHO is the drafter's again",
              vm.sysvars.get('CMDECHO') == sys0.get('CMDECHO'),
              (sys0.get('CMDECHO'), vm.sysvars.get('CMDECHO')))
        check(f"{label}: the undo group is closed", vm.undo_groups == 0,
              vm.undo_groups)



def scans_keep_their_own_handler():
    print("== DIMSCAN / LINFINSCAN still report on their own ==")
    for label, path, cmd, lay in [
            ('DIMSCAN', DIMCHECK, 'c:DIMSCAN', 'DIMCHECK-REPORT'),
            ('LINFINSCAN', LINFINCHECK, 'c:LINFINSCAN', 'LINFINCHECK-REPORT')]:
        vm = load(path)
        vm.handle_errors = True
        sys0 = dict(vm.sysvars)
        b = line(vm, (0.0, 80.0), (100.0, 80.0))
        dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0))
        vm.run(cmd, [None, esc])
        check(f"{label}: Esc at its own highlight runs its own handler",
              len(vm.handled_errors) == 1
              and vm.sysvars.get('CMDECHO') == sys0.get('CMDECHO'),
              vm.handled_errors)
        vm = load(path)
        b = line(vm, (0.0, 80.0), (100.0, 80.0))
        dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0))
        vm.run(cmd, [None, None])
        check(f"{label}: a clean run still writes its report",
              'NOT attached' in report(vm, lay), report(vm, lay)[:300])




# ==================================================================
def scan_enter_takes_the_drafters_space():
    print("== DIMSCAN / LINFINSCAN: Enter scans the drafter's space only ==")
    # A bare "_X" swept every layout's paper space too.  One paper-space
    # line through a model dimension's stray point was enough to pass that
    # point as attached.
    for label, path, cmd, lay in [
            ('DIMSCAN', DIMCHECK, 'c:DIMSCAN', 'DIMCHECK-REPORT'),
            ('LINFINSCAN', LINFINCHECK, 'c:LINFINSCAN', 'LINFINCHECK-REPORT')]:
        vm = load(path)
        line(vm, (0.0, 80.0), (100.0, 80.0))
        d1 = dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0))   # 10 off
        line(vm, (90.0, 90.0), (110.0, 90.0), space='Layout1')     # sheet ink
        vm.run(cmd, [None, None])
        txt = report(vm, lay)
        check(f"{label}: the stray point is still NOT attached",
              ('Dim %s [STANDARD] = 100.0000: NOT attached' % d1.handle) in txt,
              txt[-700:])
        # ...and from the sheet itself (paper space, no viewport active) the
        # same Enter takes the sheet and leaves the model alone
        vm = load(path)
        line(vm, (0.0, 80.0), (100.0, 80.0))
        d1 = dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0))
        line(vm, (90.0, 90.0), (110.0, 90.0), space='Layout1')
        vm.sysvars.update(TILEMODE=0, CVPORT=1, CTAB='Layout1')
        vm.run(cmd, [None, None])
        txt = report(vm, lay)
        check(f"{label}: from paper space it reads the sheet, not the model",
              'NOT attached' not in txt and d1.handle not in txt, txt[-500:])




# ==================================================================
def covercheck_from_a_viewport():
    print("== COVERCHECK from a layout viewport reads model space ==")
    # Inside a viewport CTAB names the layout while every pick lands in
    # model space: the pad census found no model pad and circled every 36"
    # spot as missing one, and COVERSCAN's Enter found nothing to scan.
    vm = load(COVERCHECK)
    vm.loads('(entmake (list \'(0 . "BLOCK") \'(2 . "Pad36x36") \'(10 0.0 0.0 0.0)'
             ' \'(70 . 0)))')
    vm.loads('(entmake (list \'(0 . "CIRCLE") \'(8 . "0") \'(10 0.0 0.0 0.0)'
             ' \'(40 . 18.0)))')
    vm.loads('(entmake \'((0 . "ENDBLK")))')
    block(vm, 'Pad36x36', (120.0, 120.0), lay='PADS')
    vm.sysvars.update(TILEMODE=0, CVPORT=2, CTAB='Layout1')
    r = vm.loads('(cchk:pad-centers)')
    check("the pad census finds the model-space pad from a viewport",
          isinstance(r, list) and len(r) == 1, r)
    vm = load(COVERCHECK)
    line(vm, (0.0, 80.0), (100.0, 80.0))
    d1 = dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0))
    vm.sysvars.update(TILEMODE=0, CVPORT=2, CTAB='Layout1')
    vm.run('c:COVERSCAN', [None, None])
    txt = report(vm, 'COVERCHECK-REPORT')
    check("COVERSCAN's Enter from a viewport scans the model",
          'Nothing to scan' not in printed(vm)
          and ('Dim %s [STANDARD] = 100.0000: NOT attached' % d1.handle) in txt,
          printed(vm)[-300:])




# ==================================================================
def tech_title_per_sheet():
    print("== COVERCHECK: one Tech Title per sheet, none highlighted ==")
    # The sweep took the FIRST Tech Title the database returned.  Here the
    # other sheet's (stale) one was made first, so the checked sheet's date
    # was never looked at and today's was written into the other sheet.


    def title_vm(near_date, far_date=None):
        vm = load(COVERCHECK)
        far = (block(vm, 'Tech Title', (5000.0, 0.0), [('Date', far_date)])
               if far_date else None)
        layer(vm, 'SEL')
        line(vm, (0.0, 0.0), (100.0, 0.0), 'SEL')
        near = block(vm, 'Tech Title', (150.0, 0.0), [('Date', near_date)])
        vm.loads('(defun t:date () (cchk:audit-date'
                 ' (ssget "_X" \'((8 . "SEL"))) T))')
        return vm, near, far


    today = load(COVERCHECK).loads('(cchk:mdy-str (cchk:today-mdy))')


    def sentence(r):
        """audit-date's (sentence . needs-attention), read either way the VM
        hands a cons back: a Dot when the cdr is T, a list when it is nil."""
        if isinstance(r, Dot):
            return r.a
        return r[0] if isinstance(r, list) and r else ''


    vm, near, far = title_vm(today, '05/01/2024')
    r = vm.run('t:date', [])
    check("the title nearest the checked drawing is the one read",
          "- OK (2 Tech Titles in the drawing" in sentence(r)
          and near.handle in sentence(r), r)
    check("...and the other sheet's date is not rewritten",
          attrib_value(vm, far, 'Date') == '05/01/2024',
          attrib_value(vm, far, 'Date'))
    vm, near, far = title_vm('05/01/2024', today)
    r = vm.run('t:date', [])
    check("a stale date on a best-guess title is named, never written",
          'NEEDS UPDATING, not written' in sentence(r)
          and attrib_value(vm, near, 'Date') == '05/01/2024'
          and attrib_value(vm, far, 'Date') == today, r)
    vm, near, far = title_vm('05/01/2024')
    r = vm.run('t:date', [])
    check("the one Tech Title in the drawing is still updated (control)",
          'UPDATED to' in sentence(r)
          and attrib_value(vm, near, 'Date') == today, r)




# ==================================================================
def border_per_sheet():
    print("== LINFINSCAN: two sheets' borders are two borders ==")
    # The fallback measured the UNION of everything on the border layer; two
    # correct borders read as one STRETCHED 2704 x 543.625 box.
    for label, frame in [('polylines', 'poly'), ('four lines and a polyline',
                                                  'lines')]:
        vm = load(LINFINCHECK)
        staircase(vm)
        stairs = selectable(vm)
        W, H = 704.0, 543.625
        if frame == 'poly':
            poly(vm, [(0.0, 0.0), (W, 0.0), (W, H), (0.0, H)], 'border')
        else:
            layer(vm, 'border')
            for p1, p2 in [((0.0, 0.0), (W, 0.0)), ((W, 0.0), (W, H)),
                           ((W, H), (0.0, H)), ((0.0, H), (0.0, 0.0))]:
                line(vm, p1, p2, 'border')
        poly(vm, [(2000.0, 0.0), (2000.0 + W, 0.0), (2000.0 + W, H),
                  (2000.0, H)], 'border')
        vm.run('c:LINFINSCAN', [None, stairs])
        txt = report(vm, 'LINFINCHECK-REPORT')
        check(f"{label}: the sheet's own border is measured, and the second named",
              ('704.0000 x 543.6250 - nominal size, OK (2 separate borders on'
               " layer 'border' - measured the one nearest the checked drawing)")
              in txt and 'STRETCHED' not in txt, txt[:900])




# ==================================================================
def disclaimer_missed_click():
    print("== COVERCHECK: a missed click at the disclaimer pick asks again ==")
    POOL_PTS = [(0.0, 0.0), (240.0, 0.0), (240.0, 120.0),
                (120.0, 120.0), (120.0, 240.0), (0.0, 240.0)]
    vm = load(COVERCHECK)
    pool = poly(vm, POOL_PTS, 'POOL')
    repl = block(vm, 'Replacement Disclaimer', (500.0, 500.0))
    vm.globals[Sym('t:pool')] = pool
    vm.loads('(defun t:audit ( / ss) (setq ss (ssadd)) (ssadd t:pool ss)'
             ' (cchk:cover-audit ss nil T nil))')
    try:
        r = vm.run('t:audit', ['Yes', 'MISS', repl])
    except LispError as e:
        r = str(e)
    lines_ = '\n'.join(r[0]) if isinstance(r, list) else str(r)
    check("the miss is re-asked, and the block picked next is found",
          "found where you pointed (outside the selection)" in lines_
          and 'MISSING' not in lines_.split('Replacement:')[-1], lines_)
    check("...with a word to say why",
          'Nothing there - click the block' in printed(vm), printed(vm)[-300:])
    vm = load(COVERCHECK)
    pool = poly(vm, POOL_PTS, 'POOL')
    vm.globals[Sym('t:pool')] = pool
    vm.loads('(defun t:audit ( / ss) (setq ss (ssadd)) (ssadd t:pool ss)'
             ' (cchk:cover-audit ss nil T nil))')
    r = vm.run('t:audit', ['Yes', None])
    check("Enter still means 'it is not placed' (control)",
          "block is MISSING - add it" in '\n'.join(r[0]), r)




# ==================================================================
def demo_block_entmade():
    print("== TUTORIALCOVERCHECK's demo block is square whatever the drafter set ==")
    # -INSERT read its typed rotation "0" through ANGBASE/ANGDIR and its
    # point with the drafter's running snaps live.  Entmade, it is exactly
    # where the rest of the (entmade, WCS) demo expects it.
    vm = load(COVERCHECK)
    vm.sysvars.update(ANGBASE=1.0, ANGDIR=1, OSMODE=4133)
    vm.loads('(defun t:ins () (cchk:tut-insert-details (list 210.0 60.0 0.0)'
             ' "15\\"" "3x3"))')
    r = vm.run('t:ins', [])
    check("the demo block is built without a command",
          isinstance(r, lispvm.Ent) and grp(vm, r, 0) == 'INSERT'
          and not [c for c in vm.commands if 'INSERT' in str(c[0]).upper()],
          (r, vm.commands))
    if isinstance(r, lispvm.Ent):
        check("...square, at the demo's own point",
              grp(vm, r, 10)[:2] == [210.0, 60.0]
              and float(grp(vm, r, 50) or 0.0) == 0.0,
              (grp(vm, r, 10), grp(vm, r, 50)))
        check("...carrying the wrong-on-purpose Overlap and Spacing",
              attrib_value(vm, r, 'OVERLAP') == '15"'
              and attrib_value(vm, r, 'SPACING') == '3x3',
              (attrib_value(vm, r, 'OVERLAP'), attrib_value(vm, r, 'SPACING')))
        check("...and tagged, so TUTORIALCOVERCHECKCLEAN finds it",
              any(isinstance(g, list) and g and g[0] == -3
                  for g in vm.entdata[r]), vm.entdata[r])
    check("the drafter's settings were never touched",
          vm.sysvars['ANGBASE'] == 1.0 and vm.sysvars['OSMODE'] == 4133)




def dashed_already_loaded():
    print("== a drawing that already has DASHED keeps its own ==")
    # -LINETYPE Load over a loaded DASHED asks "Reload it?": the "" answered
    # that, the shop's DASHED was replaced with acad.lin's, and the command
    # was left open to eat the next one.
    vm = load(COVERCHECK)
    vm.loads('(entmake (list \'(0 . "LTYPE") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLinetypeTableRecord") \'(2 . "DASHED") \'(70 . 0)'
             ' \'(3 . "the shop\'s own dashed") \'(72 . 65) \'(73 . 0)'
             ' \'(40 . 0.0)))')
    sys0 = dict(vm.sysvars)
    vm.run('c:TUTORIALCOVERCHECK', [None, [0.0, 0.0, 0.0]])
    out = printed(vm)
    check("no -LINETYPE is issued over the loaded DASHED",
          not [c for c in vm.commands if 'LINETYPE' in str(c[0]).upper()],
          [c for c in vm.commands if 'LINETYPE' in str(c[0]).upper()])
    check("the dashed outline and the demo block are both built",
          'Built: dashed cover outline' in out
          and "Built: 'Cover Details' block" in out, out[-900:])
    check("every sysvar is back", vm.sysvars == sys0,
          {k: (sys0.get(k), v) for k, v in vm.sysvars.items()
           if sys0.get(k) != v})




# ==================================================================
def arc_and_overlap_passes():
    print("== COVERCHECK / LINFINCHECK: the arc and overlap passes ==")
    # The only passes that edit the drafter's geometry, and no suite
    # entered them: an arc end re-fitted (Move) and put back (Keep), a
    # same-layer overlap merged, and a cross-layer one offered only
    # Flag/Leave.
    for label, path, lay in [('COVERCHECK', COVERCHECK, 'COVERCHECK-REPORT'),
                             ('LINFINCHECK', LINFINCHECK, 'LINFINCHECK-REPORT')]:
        vm = load(path)
        layer(vm, 'OTHER')
        a = line(vm, (0.0, 0.0), (100.0, 0.0))
        b = line(vm, (0.0, 80.0), (100.0, 80.0))
        f = arc(vm, (102.0, 25.0), 25.0, -math.pi / 2.0, math.pi / 2.0)
        c1 = line(vm, (0.0, -60.0), (100.0, -60.0))
        c2 = line(vm, (60.0, -60.0), (180.0, -60.0))
        x1 = line(vm, (0.0, -120.0), (100.0, -120.0))
        x2 = line(vm, (60.0, -120.0), (180.0, -120.0), 'OTHER')
        l1 = line(vm, (0.0, -180.0), (100.0, -180.0))
        l2 = line(vm, (60.0, -180.0), (180.0, -180.0))

        def merge_or_leave(vm, c1=c1, c2=c2):
            # Merge (c1, c2), Leave (l1, l2): the pair on screen is
            # named in the "Overlap n of m: lines H1 + H2" line
            last = printed(vm).rsplit('Overlap ', 1)[-1]
            return ('Merge' if c1.handle in last and c2.handle in last
                    else 'Leave')

        run(vm, 'c:' + label, [None, selectable(vm)], [
            ('[Move/Keep/Pick]', ['Move', 'Keep']),   # arc start, arc end
            ('[Merge/Flag/Leave]', merge_or_leave),
            ('[Flag/Leave]', 'Flag'),
            ('is this drawing a replacement?', 'No'),
        ])
        sp, ep = _ends(vm, f)
        check(f"{label}: Move re-fitted the arc start onto the line's end",
              math.dist(sp[:2], [100.0, 0.0]) < 1e-6, sp)
        check(f"{label}: Keep put the arc's end back exactly",
              math.dist(ep[:2], [102.0, 50.0]) < 1e-6, ep)
        check(f"{label}: the moved arc wears the arc colour",
              color_of(vm, f) == 6, color_of(vm, f))
        gone = [e for e in (c1, c2) if e in vm.deleted]
        kept = [e for e in (c1, c2) if e not in vm.deleted]
        span = sorted([grp(vm, kept[0], 10)[0], grp(vm, kept[0], 11)[0]]) \
            if len(kept) == 1 else None
        check(f"{label}: Merge left one cyan line spanning both",
              len(gone) == 1 and span == [0.0, 180.0]
              and color_of(vm, kept[0]) == 4, (gone, span))
        check(f"{label}: a cross-layer pair is offered Flag/Leave, never Merge",
              [p for p in prompts(vm) if '[Flag/Leave]' in p
               and 'Merge' not in p], prompts(vm))
        check(f"{label}: Flag left both cross-layer lines standing, cyan",
              x1 not in vm.deleted and x2 not in vm.deleted
              and color_of(vm, x1) == 4 and color_of(vm, x2) == 4,
              (color_of(vm, x1), color_of(vm, x2)))
        txt = report(vm, lay)
        check(f"{label}: the pair left as drawn is back in its own colour",
              l1 not in vm.deleted and l2 not in vm.deleted
              and color_of(vm, l1) == 256 and color_of(vm, l2) == 256,
              (color_of(vm, l1), color_of(vm, l2)))
        check(f"{label}: the report tallies what happened",
              '(merged: 1, flagged: 1, left as drawn: 1)' in txt
              and 'different layers - flagged to fix (cyan)' in txt
              and 'endpoint(s) moved (magenta), 1 kept where you drew them' in txt,
              txt[-1200:])
        check(f"{label}: the untouched lines have their own colour back",
              color_of(vm, a) == 256 and color_of(vm, b) == 256,
              (color_of(vm, a), color_of(vm, b)))




def dimcheck_unstage():
    print("== DIMCHECK: a pair an earlier merge absorbed is unstaged ==")
    # (c1, c2) merge; (c2, c3) then no longer exists and goes back to the
    # grey through dchk:unstage, to be restored with everything else; and a
    # pair left as drawn is unstaged the same way.
    vm = load(DIMCHECK)
    c1 = line(vm, (0.0, -60.0), (100.0, -60.0))
    c2 = line(vm, (60.0, -60.0), (180.0, -60.0))
    c3 = line(vm, (150.0, -60.0), (250.0, -60.0))
    l1 = line(vm, (0.0, -120.0), (100.0, -120.0))
    l2 = line(vm, (60.0, -120.0), (180.0, -120.0))


    def merge_c1_c2(vm):
        """Merge the (c1, c2) pair, leave any other: which pair is on screen
        is read off the "Overlap n of m: lines H1 + H2" line just printed."""
        last = printed(vm).rsplit('Overlap ', 1)[-1]
        return 'Merge' if (c1.handle in last and c2.handle in last) else 'Leave'


    vm.run('c:DIMCHECK', [None, selectable(vm), merge_c1_c2, merge_c1_c2])
    txt = report(vm, 'DIMCHECK-REPORT')
    check("one merge, the absorbed pair skipped, one left as drawn",
          '(merged: 1, flagged: 0, left as drawn: 1)' in txt, txt[-800:])
    check("every line not merged is back in its own colour",
          all(color_of(vm, e) == 256 for e in (c3, l1, l2)),
          [color_of(vm, e) for e in (c3, l1, l2)])
    check("the merged survivor is the cyan one",
          c2 in vm.deleted and color_of(vm, c1) == 4,
          (c2 in vm.deleted, color_of(vm, c1)))




# ==================================================================
def rescue_and_clean_over_real_marks():
    print("== the rerun sweep, RESCUE and CLEAN run over real marks ==")
    # Every one of these finds its marks with (ssget "_X" '((-3 ("APP")))),
    # which the VM's own ssget cannot evaluate -- so every suite that ran
    # them saw an empty drawing and passed on "nothing to restore".  With
    # the xdata sweep installed above, they meet what a real run leaves.


    def tagged(vm, app, kind=None):
        out = []
        for e in live(vm):
            for g in vm.entdata[e]:
                if isinstance(g, list) and g and g[0] == -3:
                    for sub in g[1:]:
                        # (-3 ("APP")) with nothing after the name is how
                        # xdata is REMOVED -- AutoCAD drops the group
                        if isinstance(sub, list) and len(sub) > 1 \
                                and sub[0] == app:
                            vals = [x.b for x in sub[1:] if isinstance(x, Dot)
                                    and x.a == 1000]
                            if kind is None or kind in vals:
                                out.append(e)
        return out


    for label, path, app, lay in [
            ('COVERCHECK', COVERCHECK, 'COVERCHECK', 'COVERCHECK-REPORT'),
            ('LINFINCHECK', LINFINCHECK, 'LINFINCHECK', 'LINFINCHECK-REPORT')]:
        vm = load(path)
        b = line(vm, (0.0, 80.0), (100.0, 80.0))
        d1 = dim(vm, (0.0, 80.0), (100.0, 90.0), (50.0, 120.0))
        table = [('[Move/Keep/Pick]', 'Move'),
                 ('Is this dimension correct?', 'No'),
                 ('is this drawing a replacement?', 'No')]
        run(vm, 'c:' + label, [None, selectable(vm)], table)
        first = tagged(vm, app, 'REPORT')
        check(f"{label}: the run left a red flag and a tagged report",
              color_of(vm, d1) == 1 and first, (color_of(vm, d1), first))
        run(vm, 'c:' + label, [None, selectable(vm)], table)
        check(f"{label}: a rerun replaces the report instead of stacking it",
              all(e in vm.deleted for e in first)
              and len(tagged(vm, app, 'REPORT')) == len(first),
              (len(first), len(tagged(vm, app, 'REPORT'))))
        vm.run('c:' + label + 'RESCUE', [])
        check(f"{label}RESCUE: the flag colour comes off",
              color_of(vm, d1) == 256 and color_of(vm, b) == 256,
              (color_of(vm, d1), color_of(vm, b)))
        check(f"{label}RESCUE: the report and markers are gone",
              not report(vm, lay) and not tagged(vm, app),
              (report(vm, lay)[:100], tagged(vm, app)))
        check(f"{label}RESCUE: and it says what it did",
              'restored or removed' in printed(vm)
              and 'nothing to restore' not in printed(vm), printed(vm)[-300:])

    vm = load(COVERCHECK)
    vm.run('c:TUTORIALCOVERCHECK', [None, [0.0, 0.0, 0.0]])
    demo = tagged(vm, 'COVERCHECK', 'TUTORIAL')
    vm.run('c:TUTORIALCOVERCHECKCLEAN', [])
    check("TUTORIALCOVERCHECKCLEAN: every tagged demo item is erased",
          demo and all(e in vm.deleted for e in demo)
          and ('removed %d demo item(s)' % len(demo)) in printed(vm),
          (len(demo), printed(vm)[-200:]))


SECTIONS = [
    liner_wipe_on_locked_attribs, linfincheck_flags_on_a_locked_layer,
    dimcheck_declined_unlock,
    locked_gates_in_sibling_copies, relock_survives_the_handler,
    tutorial_scan_esc, scans_keep_their_own_handler,
    scan_enter_takes_the_drafters_space, covercheck_from_a_viewport,
    tech_title_per_sheet, border_per_sheet, disclaimer_missed_click,
    demo_block_entmade, dashed_already_loaded, arc_and_overlap_passes,
    dimcheck_unstage, rescue_and_clean_over_real_marks,
]

for _section in SECTIONS:
    # a scenario that crashes (the old code asking a question the new
    # one does not, say) is a failure of that scenario, not the file
    STATE['throw'] = False
    try:
        _section()
    except (LispError, AssertionError, TypeError, KeyError, IndexError) as e:
        check(_section.__name__ + ' ran to the end', False,
              str(e).split('\n')[0])


# ------------------------------------------------------------------
if FAILS:
    print("test_fix_review_a: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_fix_review_a: all checks passed (%s tier)" % ROOT)
