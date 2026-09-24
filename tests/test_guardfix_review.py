"""The review tools' guard-fix wave: feet-and-inches text written into
the drawing, and writes a locked layer refused while the tool said
they were done.  Every scenario drives the REAL lisp/ file in the VM.

  * FEET AND INCHES.  DIMCHECK, COVERCHECK, LINFINCHECK and SPACHECK
    wrote measurements into their report MTEXT through a bare (rtos v),
    or a knob-mode (rtos d 4 4).  AutoCAD's rtos spells feet and inches
    after DIMZIN: at 0 (acad.dwt), 2 or 8 a whole foot is 15' and not
    15'-0" -- the notation the same review tools reject as feet with no
    inches.  Each tool now spells LUNITS 3/4 (and a knob tuned to 3/4)
    by arithmetic, through its own copy of cal:ftin.
  * RESCUE.  DIMCHECKRESCUE, COVERCHECKRESCUE and LINFINCHECKRESCUE
    counted every entdel and every colour put back whatever the write
    answered, and said "restored or removed N" over a flag still red on
    a locked layer.  A colour that would not go back now keeps its
    stash for the rerun the message asks for.
  * CLEAR-OLD.  A rerun's sweep of the last run's markers counted a
    marker on a locked construction layer as removed.
  * THE TUTORIAL DEMOS.  DIMCHECK's and LINFINCHECK's practice drawing
    went on layer 0 and the current layer, its erase threw every answer
    away and said "Practice drawing erased."; TUTORIALCOVERCHECKCLEAN
    counted demo items on a locked pool layer as removed; SPACHECK's
    demo erased EVERY report on its report layer -- the drafter's own
    earlier ones too -- and said "erased" over a refused one.

The VM's rtos, and its entmod/entdel over a locked layer, are being
made honest in tests/lispvm.py in parallel; this file does not lean on
either.  It installs AutoCAD's rtos (DIMZIN-following, LUNITS/LUPREC
defaults) for the feet-inch scenarios only, and its own lock model --
entmod and entdel answer nil for an entity whose layer record carries
bit 4 -- for the whole file.

Run: python3 tests/test_guardfix_review.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_guardfix_review.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Dot, Sym, BUILTINS, NIL  # noqa: E402

HERE = os.path.dirname(__file__)
# lispvm's _remap_root sends these to shared/parts/ when
# CALOFIN_LISP_ROOT=shared, as test_fix_review_a.py's paths work
LISP = os.path.join(HERE, '..', 'lisp')
PATHS = {
    'DIMCHECK': os.path.join(LISP, 'dimcheck', 'dimcheck.lsp'),
    'COVERCHECK': os.path.join(LISP, 'covercheck', 'covercheck.lsp'),
    'LINFINCHECK': os.path.join(LISP, 'linfincheck', 'linfincheck.lsp'),
    'SPACHECK': os.path.join(LISP, 'spacheck', 'SPACHECK.lsp'),
}
ROOT = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp'

TWO_PI = 2.0 * math.pi

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   " + label)
    else:
        print("  FAIL " + label
              + (('  -- ' + str(detail)[:700]) if detail else ''))
        FAILS.append(label)


# ------------------------------------------------------------------
# the vlax-curve surface the attachment audits use, read off the VM's
# own entity store, and the xdata sweep (-3 ("APP")) the VM's ssget
# cannot evaluate -- the same shims test_fix_review_a.py installs
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
# refuses for an entity whose layer record carries bit 4 -- the layer
# the entity is ON, which is what AutoCAD reads.  A table record stays
# writable (that is how a layer is unlocked); entmake is not touched,
# because AutoCAD creates on a locked layer.  entdel also refuses an
# ATTRIB, a SEQEND or a VERTEX on its own ("attributes and polyline
# vertices cannot be deleted independently of their parent entities",
# the entdel reference): they go with the INSERT or POLYLINE they
# belong to.  STUBBORN names entities that refuse an erase whatever
# their layer says, for the one path a lifted lock cannot reach.
# ------------------------------------------------------------------

_BASE_ENTMOD = BUILTINS[Sym('entmod')]
_BASE_ENTDEL = BUILTINS[Sym('entdel')]
STUBBORN = set()


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
    if ename is None or ename in vm.recdata or ename not in vm.entdata:
        return _BASE_ENTMOD(vm, a)
    if layer_locked(vm, grp(vm, ename, 8) or '0'):
        return NIL
    return _BASE_ENTMOD(vm, a)


def _entdel_locked(vm, a):
    e = a[0]
    if isinstance(e, lispvm.Ent) and e in vm.entdata \
            and e not in vm.deleted \
            and (e in STUBBORN
                 or grp(vm, e, 0) in ('ATTRIB', 'SEQEND', 'VERTEX')
                 or layer_locked(vm, grp(vm, e, 8) or '0')):
        return NIL
    return _BASE_ENTDEL(vm, a)


BUILTINS[Sym('entmod')] = _entmod_locked
BUILTINS[Sym('entdel')] = _entdel_locked
BUILTINS.setdefault(Sym('~'), lambda vm, a: ~int(a[0]))


# ------------------------------------------------------------------
# AutoCAD's rtos, installed only round the feet-inch scenarios: the
# mode and precision default to LUNITS / LUPREC, and feet and inches
# follow DIMZIN's two low bits -- 0 (acad.dwt) drops zero feet and zero
# inches, so a whole foot is 15' and six inches 6".  (The DIMZIN
# reference: '0 Suppresses zero feet and precisely zero inches'.)
# ------------------------------------------------------------------

def _dec(v, prec, dz):
    s = f"{v:.{prec}f}"
    if s.startswith("-") and float(s) == 0.0:
        s = s[1:]
    if dz & 8 and "." in s:
        s = s.rstrip("0").rstrip(".")
    if dz & 4:
        if s.startswith("0."):
            s = s[1:]
        elif s.startswith("-0."):
            s = "-" + s[2:]
    return s


def honest_rtos(vm, a):
    v = lispvm.num(a[0])
    lun = vm.sysvars.get('LUNITS', 2)
    lup = vm.sysvars.get('LUPREC', 4)
    mode = int(a[1]) if len(a) > 1 and a[1] is not NIL else int(lun or 2)
    prec = int(a[2]) if len(a) > 2 and a[2] is not NIL else int(
        4 if lup is None else lup)
    dz = int(vm.sysvars.get('DIMZIN', 0) or 0)
    low = dz & 3
    keep_feet = low in (1, 2)
    keep_inch = low in (1, 3)
    if mode == 1:
        return f"{v:.{prec}E}"
    if mode in (3, 4):
        neg = v < 0
        v = abs(v)
        if mode == 4:
            den = 2 ** prec
            total = round(v * den)
            inches, frac = divmod(total, den)
            feet, whole = divmod(inches, 12)
            zero_in = (whole == 0 and frac == 0)
            if frac:
                g = math.gcd(frac, den)
                fr = f"{frac // g}/{den // g}"
                ins = (f"{whole} {fr}" if (whole or feet or keep_feet)
                       else fr)
            else:
                ins = f"{whole}"
            ins += '"'
        else:
            feet = int(v // 12)
            rem = v - 12 * feet
            ins_s = _dec(rem, prec, dz)
            if float(ins_s or 0) >= 12.0:
                feet += 1
                ins_s = _dec(0.0, prec, dz)
            zero_in = float(ins_s or 0) == 0.0
            ins = ins_s + '"'
        if feet == 0 and not keep_feet:
            s = ins
        elif zero_in and not keep_inch and feet != 0:
            s = f"{feet}'"
        else:
            s = f"{feet}'-{ins}"
        return ("-" if neg and s not in ('0"',) else "") + s
    return _dec(v, prec, dz)


class FeetInchDrawing:
    """A drawing in architectural units at acad.dwt's DIMZIN 0, with
    AutoCAD's rtos in force for as long as the block runs."""

    def __init__(self, vm):
        self.vm = vm

    def __enter__(self):
        self.saved = BUILTINS[Sym('rtos')]
        BUILTINS[Sym('rtos')] = honest_rtos
        self.vm.sysvars.update({'LUNITS': 4, 'LUPREC': 4, 'DIMZIN': 0})
        return self.vm

    def __exit__(self, *exc):
        BUILTINS[Sym('rtos')] = self.saved
        return False


#: a length spelled as whole feet with no inches after it -- 15' where
#: the drawing's own notation is 15'-0".  A digit run standing on its own
#: (after a space, an opening bracket or '='), then the feet mark, then
#: anything but the dash that carries the inches.  A second apostrophe
#: (40'' is the drafter's own inch mark) and a space before more digits
#: (3' 4 1/2'', a spelling LINFINCHECK's sheet lists as one it reads)
#: are inches too.
FEET_ONLY = re.compile(r"(?:^|[\s(=])(\d+)'(?!-|'|\s?\d)")


def feet_only(txt):
    return [m.group(0).strip() for m in FEET_ONLY.finditer(txt)]


# ------------------------------------------------------------------
# fixture builders and readers
# ------------------------------------------------------------------

def load(tool):
    vm = VM()
    vm.load(PATHS[tool])
    vm.printed = []
    return vm


def layer(vm, name, locked=False, color=7):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
             ' \'(62 . %d) \'(6 . "Continuous")))'
             % (name, 4 if locked else 0, color))


def set_lock(vm, name, locked=True):
    """Lock or unlock a layer's record in place -- made on demand, as
    tblobjname makes one, for a layer the drawing has by name alone."""
    vm.tables['LAYER'].add(name)
    rec = BUILTINS[Sym('tblobjname')](vm, ['LAYER', name])
    data = vm.recdata[rec]
    for i, g in enumerate(data):
        if isinstance(g, Dot) and g.a == 70:
            flags = int(g.b)
            data[i] = Dot(70, (flags | 4) if locked else (flags & ~4))
            return
    data.append(Dot(70, 4 if locked else 0))


def line(vm, p1, p2, lay='0'):
    vm.loads('(entmakex (list (cons 0 "LINE") (cons 8 "%s")'
             ' (list 10 %r %r 0.0) (list 11 %r %r 0.0)))'
             % (lay, p1[0], p1[1], p2[0], p2[1]))
    return vm.entities[-1]


def dim(vm, p13, p14, p10, lay='0', style='STANDARD', ang=0.0):
    vm.loads('(entmake (list (cons 0 "DIMENSION") (cons 8 "%s")'
             ' (cons 3 "%s") (cons 70 0) (cons 50 %r)'
             ' (list 13 %r %r 0.0) (list 14 %r %r 0.0)'
             ' (list 10 %r %r 0.0)))'
             % (lay, style, ang, p13[0], p13[1], p14[0], p14[1],
                p10[0], p10[1]))
    return vm.entities[-1]


def poly(vm, pts, lay, closed=True):
    vs = ' '.join('(list 10 %r %r)' % (x, y) for x, y in pts)
    vm.loads('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
             ' (cons 8 "%s") (cons 100 "AcDbPolyline") (cons 90 %d)'
             ' (cons 70 %d) %s))'
             % (lay, len(pts), 1 if closed else 0, vs))
    return vm.entities[-1]


def block(vm, name, at, attrs=(), lay='0'):
    """An INSERT with its ATTRIBs and SEQEND trailing it."""
    vm.loads('(entmakex (list (cons 0 "INSERT") (cons 8 "%s") (cons 2 "%s")'
             ' (list 10 %r %r 0.0)%s))'
             % (lay, name, at[0], at[1], ' (cons 66 1)' if attrs else ''))
    ins = vm.entities[-1]
    for tag, val in attrs:
        esc = val.replace('\\', '\\\\').replace('"', '\\"')
        vm.loads('(entmake (list (cons 0 "ATTRIB") (cons 8 "%s")'
                 ' (cons 2 "%s") (cons 1 "%s")))' % (lay, tag, esc))
    if attrs:
        vm.loads('(entmake (list (cons 0 "SEQEND") (cons 8 "%s")))' % lay)
    return ins


def tagged(vm, app, kind, lay, color=None, stash=None):
    """A LINE carrying APP's xdata (1000 . KIND), and a stashed colour
    (1071 . STASH) when one is given -- what a run of the review tool
    leaves behind for RESCUE and the rerun sweep to find."""
    vm.loads('(regapp "%s")' % app)
    xd = '(cons 1000 "%s")' % kind
    if stash is not None:
        xd += ' (cons 1071 %d)' % stash
    vm.loads('(entmake (list (cons 0 "LINE") (cons 8 "%s")%s'
             ' (list 10 0.0 0.0 0.0) (list 11 10.0 0.0 0.0)'
             ' (list -3 (list "%s" %s))))'
             % (lay, ' (cons 62 %d)' % color if color is not None else '',
                app, xd))
    return vm.entities[-1]


def xdata_of(vm, e, app):
    for g in vm.entdata.get(e, []):
        if isinstance(g, list) and g and g[0] == -3:
            for sub in g[1:]:
                if isinstance(sub, list) and len(sub) > 1 and sub[0] == app:
                    return sub[1:]
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


def strings(x):
    """Every string in a lisp value -- a list, a dotted pair, nested."""
    if isinstance(x, str):
        return [x]
    if isinstance(x, Dot):
        return strings(x.a) + strings(x.b)
    if isinstance(x, (list, tuple)):
        return [s for y in x for s in strings(y)]
    return []


def printed(vm):
    return ''.join(vm.printed)


def responder(table):
    """One scripted answer that reads the prompt it was reached at:
    TABLE is [(substring, answer), ...]; an answer that is a callable is
    called with the VM (how a layer gets locked between two prompts),
    anything else -- a point list included -- is the answer itself."""
    def r(vm):
        p = vm.lastprompt
        for key, val in table:
            if key in p:
                return val(vm) if callable(val) else val
        raise AssertionError('unexpected prompt %r' % p)
    return r


def run(vm, cmd, fixed, table=None, n=60):
    script = list(fixed) + ([responder(table)] * n if table else [])
    try:
        vm.run(cmd, script)
    except LispError as e:
        if 'scripted answers left over' not in str(e):
            raise


PFX = {'DIMCHECK': 'dchk', 'COVERCHECK': 'cchk', 'LINFINCHECK': 'lfc'}
SCAN = {'DIMCHECK': 'c:DIMSCAN', 'COVERCHECK': 'c:COVERSCAN',
        'LINFINCHECK': 'c:LINFINSCAN'}


def knob(vm, name):
    return vm.loads(name)


def report_layer(vm, tool):
    return knob(vm, '*%s-report-layer*' % PFX[tool])


# the answers every review asks for that these scenarios do not study
REVIEW = [('Is this dimension correct?', 'Yes'),
          ('[Merge/Flag/Leave]', 'Flag'),
          ('[Move/Keep/Pick]', 'Keep'),
          ('is this drawing a replacement?', 'No'),
          ('is the correct one placed?', 'Yes'),
          ('Are these lines steps?', 'Yes'),
          ('Unlock for this run?', 'Yes')]


# ==================================================================
#  1. feet and inches in the text the tools write into the drawing
# ==================================================================

def scans_spell_feet_and_inches():
    print("== DIMSCAN / COVERSCAN / LINFINSCAN: a whole foot is 10'-0\", "
          "not 10' ==")
    # A clean 120" dimension (10'-0"), a 90" one whose second point
    # sits 12" off the line (7'-6", off by 1'-0"), and two lines that
    # overlap over 48" (4'-0").  The distance knob is tuned to 4, as
    # LAZTUNE offers, so dchk:dist and its siblings are read too.
    for tool in ('DIMCHECK', 'COVERCHECK', 'LINFINCHECK'):
        vm = load(tool)
        vm.loads('(setq *%s-dist-mode* 4)' % PFX[tool])
        line(vm, (0.0, 0.0), (120.0, 0.0))
        dim(vm, (0.0, 0.0), (120.0, 0.0), (60.0, 20.0))
        dim(vm, (0.0, 0.0), (90.0, 12.0), (45.0, 40.0))
        line(vm, (0.0, -60.0), (100.0, -60.0))
        line(vm, (52.0, -60.0), (180.0, -60.0))
        with FeetInchDrawing(vm):
            run(vm, SCAN[tool], [None, selectable(vm)])
        txt = report(vm, report_layer(vm, tool))
        check(f"{tool}: the measurement reads 10'-0\" [dim-meas]",
              '= 10\'-0":' in txt, txt[-600:])
        check(f"{tool}: the overlap reads 4'-0\" [scan]",
              'OVERLAP of 4\'-0"' in txt, txt[-300:])
        check(f"{tool}: a tuned distance knob reads 1'-0\" [dist]",
              'off by 1\'-0"' in txt, txt[-600:])
        check(f"{tool}: no length in the report is feet with no inches",
              txt and not feet_only(txt), feet_only(txt))


def reviews_spell_the_overlap():
    print("== DIMCHECK / COVERCHECK / LINFINCHECK: the overlap label ==")
    for tool in ('DIMCHECK', 'COVERCHECK', 'LINFINCHECK'):
        vm = load(tool)
        line(vm, (0.0, -60.0), (100.0, -60.0))
        line(vm, (52.0, -60.0), (180.0, -60.0))
        with FeetInchDrawing(vm):
            run(vm, 'c:' + tool, [None, selectable(vm)], REVIEW)
        txt = report(vm, report_layer(vm, tool))
        check(f"{tool}: the flagged pair reads (overlap 4'-0\") "
              "[review-olap]",
              '(overlap 4\'-0")' in txt, txt[-400:])
        check(f"{tool}: ...and nothing in its report is feet alone",
              txt and not feet_only(txt), feet_only(txt))


def covercheck_points_and_pads():
    print("== COVERSCAN over the tutorial scene: a pad spot is "
          "(9'-0\", 6'-0\") ==")
    vm = load('COVERCHECK')
    vm.run('c:TUTORIALCOVERCHECK', [None, [0.0, 0.0, 0.0]])
    with FeetInchDrawing(vm):
        run(vm, 'c:COVERSCAN', [None, selectable(vm)])
    txt = report(vm, 'COVERCHECK-REPORT')
    check("the suggested pad's point reads (9'-0\", 6'-0\") [ptstr]",
          'Pad SUGGESTED at (9\'-0", 6\'-0")' in txt, txt[-900:])
    check("the demo dimension reads 15'-0\" [dim-meas]",
          '= 15\'-0":' in txt, txt[-900:])
    check("...and nothing in the report is feet alone",
          txt and not feet_only(txt), feet_only(txt))


def staircase(vm):
    """LINFINCHECK's side view: three treads and three risers at right
    angles, total rise 36 (y 100 -> 136)."""
    for p1, p2 in [((100, 100), (112, 100)), ((112, 112), (124, 112)),
                   ((124, 124), (136, 124)), ((112, 100), (112, 112)),
                   ((124, 112), (124, 124)), ((136, 124), (136, 136))]:
        line(vm, (float(p1[0]), float(p1[1])), (float(p2[0]), float(p2[1])))


def liner_sheet(vm, wallht, border=(1440.0, 1112.0), hdim=False):
    """The sheet LINFINCHECK reads: the side view, a border at a whole
    number of feet (120'-0" wide), a Tech Title carrying WallHt, and an
    overlapping pair for the audit column."""
    layer(vm, 'border')
    layer(vm, 'DIMENSION')
    staircase(vm)
    if hdim:
        # the overall height, spanning the whole rise
        dim(vm, (100.0, 100.0), (136.0, 136.0), (150.0, 118.0),
            lay='DIMENSION', ang=math.pi / 2.0)
    w, h = border
    poly(vm, [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)], 'border')
    line(vm, (0.0, -160.0), (100.0, -160.0))
    line(vm, (52.0, -160.0), (180.0, -160.0))
    block(vm, 'Step Attachment', (500.0, 300.0))
    block(vm, 'Tech Title', (600.0, 50.0),
          [('WallHt', "Finished Wall Ht = %s''" % wallht),
           ('Date', vm.loads('(lfc:mdy-str (lfc:today-mdy))'))])


def linfincheck_steps_and_border():
    print("== LINFINCHECK: steps rise 3'-0\", a 120'-0\" border ==")
    vm = load('LINFINCHECK')
    liner_sheet(vm, '40')
    with FeetInchDrawing(vm):
        run(vm, 'c:LINFINSCAN', [None, None])
    txt = report(vm, 'LINFINCHECK-REPORT')
    check("LINFINSCAN: the side view's rise reads 3'-0\" [scan-core]",
          'side view detected, rise 3\'-0";' in txt, txt[:900])
    check("LINFINSCAN: steps rise 3'-0\" against WallHt 3'-4\"",
          'steps rise 3\'-0" but WallHt is' in txt
          and '(3\'-4") - MISMATCH' in txt, txt[:1200])
    check("LINFINSCAN: the border reads 120'-0\" [border-verdict]",
          'Title block border: 120\'-0" x 92\'-8" - 2.045x the nominal'
          ' size, OK' in txt, txt[:1200])
    check("LINFINSCAN: ...and nothing in the report is feet alone",
          txt and not feet_only(txt), feet_only(txt))

    for wall, want in (('36', 'steps rise 3\'-0" = WallHt'),
                       ('40', 'steps rise 3\'-0" but WallHt is')):
        vm = load('LINFINCHECK')
        liner_sheet(vm, wall, hdim=True)
        with FeetInchDrawing(vm):
            run(vm, 'c:LINFINCHECK', [None, selectable(vm)], REVIEW)
        txt = report(vm, 'LINFINCHECK-REPORT')
        check(f"LINFINCHECK, WallHt {wall}'': {want} ...",
              want in txt, txt[:1500])
        if wall == '40':
            check("LINFINCHECK: the height dim states 3'-0\"",
                  re.search(r"Height dim \w+ states 3'-0\" but WallHt",
                            txt), txt[:1500])
            check("LINFINCHECK: ...and WallHt reads (3'-4\")",
                  '(3\'-4") - MISMATCH' in txt, txt[:1500])
        check(f"LINFINCHECK, WallHt {wall}'': the dimension reads 3'-0\"",
              '= 3\'-0": OK' in txt, txt[-900:])
        check(f"LINFINCHECK, WallHt {wall}'': nothing is feet alone",
              txt and not feet_only(txt), feet_only(txt))


def linfincheck_reference_sheet():
    print("== TUTORIALLINFINCHECK: the reference sheet in the drawing ==")
    vm = load('LINFINCHECK')
    # a shop that tuned the step gap and the bead distance to a foot
    # and two: the sheet quotes both
    vm.loads('(setq *lfc-step-maxgap* 12.0 *lfc-bead-dist* 24.0)')
    with FeetInchDrawing(vm):
        run(vm, 'c:TUTORIALLINFINCHECK', ['Checks'],
            [('reference sheet?', 'Yes'),
             ('top-left corner', [0.0, 0.0, 0.0]),
             ('Text height', None)])
    txt = report(vm, 'LINFINCHECK-REPORT')
    check("the sheet says 1'-0\" apart [tut-checklist]",
          '1\'-0" apart' in txt, txt[:600])
    check("the sheet says within 2'-0\"",
          'within 2\'-0"' in txt, txt[:1500])
    check("...and nothing on the sheet is feet alone",
          txt and not feet_only(txt), feet_only(txt))


def spacheck_report_spells_feet_and_inches():
    print("== SPACHECK: the demo's report in a feet-inch drawing ==")
    vm = load('SPACHECK')
    with FeetInchDrawing(vm):
        vm.run('c:TUTORIALSPACHECK',
               ['Demo', [0.0, 0.0, 0.0], '', '', '',
                'Yes', None, None, 'No'])
    txt = report(vm, 'SPACHECK-REPORT')
    for want, where in [
            ('cover 7\'-0" x 5\'-0" contains water\'s edge 6\'-6" x 4\'-6"',
             'audit-nesting'),
            ('reads 6\'-8" but the cover measures 7\'-0" x 5\'-0"',
             'audit-roster'),
            ('Overlap: 0\'-3", OK', 'audit-roster'),
            ('longest hinge 5\'-0" within 12\'-0"', 'audit-hinges'),
            ('widest piece 3\'-6" within 4\'-0"', 'audit-hinges'),
            ('liner block 58\'-8" x 45\'-3 5/8"', 'title-verdict')]:
        check(f"SPACHECK report: {want} [{where}]", want in txt, txt[:1500])
    check("...and nothing in the report is feet alone",
          txt and not feet_only(txt), feet_only(txt))

    # the two audits the demo does not trip, called over a dimension
    # built to trip them: it READS 60 (5'-0") across points 48 apart,
    # and stands 36 (3'-0") above a cover whose top is at y 0
    vm = load('SPACHECK')
    layer(vm, 'DIMENSION')
    vm.loads('(entmake (list (cons 0 "DIMENSION") (cons 8 "DIMENSION")'
             ' (cons 3 "SPA") (cons 70 1) (cons 42 60.0)'
             ' (list 13 0.0 0.0 0.0) (list 14 48.0 0.0 0.0)'
             ' (list 10 24.0 36.0 0.0)))')
    with FeetInchDrawing(vm):
        rows = vm.loads('(list (spachk:audit-dims (list (entlast)) nil nil)'
                        ' (spachk:audit-standoff (list (entlast))'
                        ' (list (list -10.0 -60.0) (list 60.0 0.0)))'
                        ' (spachk:title-verdict'
                        ' (list (list 0.0 0.0) (list 480.0 240.0))))')
    flat = '\n'.join(strings(rows))
    check("title-verdict: a 40'-0\" x 20'-0\" border is STRETCHED",
          '40\'-0" x 20\'-0" - STRETCHED' in flat, flat[:600])
    check("audit-dims: reads 5'-0\" but spans 4'-0\"",
          'reads 5\'-0" but spans 4\'-0"' in flat, flat[:600])
    check("audit-standoff: stands 3'-0\" above, SPA puts it 2'-0\"",
          'stands 3\'-0" above the cover, SPA puts it 2\'-0"' in flat,
          flat[:600])


# ==================================================================
#  2. writes a locked layer refused, counted as done
# ==================================================================

def rescue_counts_only_what_took():
    print("== DIMCHECKRESCUE / COVERCHECKRESCUE / LINFINCHECKRESCUE on a "
          "locked layer ==")
    for tool in ('DIMCHECK', 'COVERCHECK', 'LINFINCHECK'):
        vm = load(tool)
        layer(vm, 'FREE')
        layer(vm, 'HELD', locked=True)
        # a flag on each layer, its own colour (ByLayer) stashed, and a
        # report line and a marker line left by an interrupted run
        free = tagged(vm, tool, 'COLOR', 'FREE', color=1, stash=256)
        held = tagged(vm, tool, 'COLOR', 'HELD', color=1, stash=256)
        rep = tagged(vm, tool, 'REPORT', 'HELD')
        mark = tagged(vm, tool, 'XLINE', 'FREE')
        vm.run('c:%sRESCUE' % tool, [])
        out = printed(vm)
        check(f"{tool}RESCUE: the free flag's colour is back, its stash "
              "dropped",
              color_of(vm, free) == 256 and not xdata_of(vm, free, tool),
              (color_of(vm, free), xdata_of(vm, free, tool)))
        check(f"{tool}RESCUE: the free marker is erased",
              mark in vm.deleted)
        check(f"{tool}RESCUE: the locked flag is still red and KEEPS its "
              "stash for the rerun",
              color_of(vm, held) == 1
              and any(isinstance(g, Dot) and g.a == 1071
                      for g in (xdata_of(vm, held, tool) or [])),
              (color_of(vm, held), xdata_of(vm, held, tool)))
        check(f"{tool}RESCUE: the locked report is still there",
              rep not in vm.deleted)
        check(f"{tool}RESCUE: it counts the 2 that took, not all 4",
              'restored or removed 2 item(s).' in out, out[-400:])
        check(f"{tool}RESCUE: ...and names the 2 a lock kept",
              '2 item(s) on locked layer(s) NOT restored' in out
              and 'run %sRESCUE again' % tool in out, out[-400:])

    # every mark on a locked layer: nothing is restored, and the line
    # says so instead of "nothing to restore"
    vm = load('DIMCHECK')
    layer(vm, 'HELD', locked=True)
    tagged(vm, 'DIMCHECK', 'COLOR', 'HELD', color=1, stash=256)
    vm.run('c:DIMCHECKRESCUE', [])
    out = printed(vm)
    check("DIMCHECKRESCUE: all of it locked -- neither 'restored' nor "
          "'nothing to restore'",
          'restored or removed' not in out
          and 'nothing to restore' not in out
          and '1 item(s) on locked layer(s) NOT restored' in out, out[-300:])


def clear_old_counts_only_what_took():
    print("== the rerun sweep: a marker on a locked construction layer ==")
    for tool in ('DIMCHECK', 'COVERCHECK', 'LINFINCHECK'):
        vm = load(tool)
        constr = knob(vm, '*%s-constr-layer*' % PFX[tool])
        rlay = report_layer(vm, tool)
        layer(vm, constr, locked=True)
        layer(vm, rlay)
        old_mark = tagged(vm, tool, 'XLINE', constr)
        old_rep = tagged(vm, tool, 'REPORT', rlay)
        line(vm, (0.0, 0.0), (120.0, 0.0))
        run(vm, SCAN[tool], [None, selectable(vm)])
        out = printed(vm)
        check(f"{tool}: the scan still sweeps the old report",
              old_rep in vm.deleted
              and '(Removed 1 report/marker item(s)' in out, out[-500:])
        check(f"{tool}: the locked marker stays, and is not counted "
              "as removed",
              old_mark not in vm.deleted
              and '(Removed 2' not in out, out[-500:])
        check(f"{tool}: ...it is named as left on a locked layer",
              '(1 report/marker item(s) from an earlier %s run are on a '
              'locked layer - NOT removed.)' % tool in out, out[-500:])


def practice_drawings_on_their_own_layer():
    print("== TUTORIALDIMCHECK / TUTORIALLINFINCHECK: the practice "
          "drawing ==")
    for tool in ('DIMCHECK', 'LINFINCHECK'):
        # layer 0 -- where the practice drawing used to go, and the
        # current layer the DIMLINEAR drew on -- is locked
        vm = load(tool)
        set_lock(vm, '0')
        mark = len(vm.entities)
        run(vm, 'c:TUTORIAL' + tool, ['Demo'],
            [('Pick an empty spot', [0.0, 0.0, 0.0]),
             ('press Enter to continue', ''),
             ('Write a read-only', 'No'),
             ('Erase the practice drawing?', 'Yes')])
        made = [e for e in vm.entities[mark:]]
        left = [e for e in made if e not in vm.deleted]
        out = printed(vm)
        check(f"TUTORIAL{tool}: with layer 0 locked, every practice "
              "object is erased",
              made and not left,
              (len(made), [(grp(vm, e, 0), grp(vm, e, 8)) for e in left]))
        check(f"TUTORIAL{tool}: ...and it says so",
              'Practice drawing erased.' in out, out[-300:])
        check(f"TUTORIAL{tool}: the current layer is 0 again, still locked",
              vm.sysvars.get('CLAYER') == '0' and layer_locked(vm, '0'),
              (vm.sysvars.get('CLAYER'), layer_locked(vm, '0')))

        # locked between the drawing and the erase: the erase is
        # refused, and the line that follows does not call it erased
        def lock_then_yes(vm):
            for name in ('0', '%s-TUTORIAL' % tool):
                if name.upper() in vm.tablerecs.get('LAYER', {}):
                    set_lock(vm, name)
            return 'Yes'

        vm = load(tool)
        mark = len(vm.entities)
        run(vm, 'c:TUTORIAL' + tool, ['Demo'],
            [('Pick an empty spot', [0.0, 0.0, 0.0]),
             ('press Enter to continue', ''),
             ('Write a read-only', 'No'),
             ('Erase the practice drawing?', lock_then_yes)])
        left = [e for e in vm.entities[mark:] if e not in vm.deleted]
        out = printed(vm)
        check(f"TUTORIAL{tool}: a refused erase is not 'Practice drawing "
              "erased.'",
              left and 'Practice drawing erased.' not in out,
              (len(left), out[-300:]))
        check(f"TUTORIAL{tool}: ...it counts what stayed, and why",
              ('%d object(s) of the practice run on a locked layer NOT erased'
               % len(left)) in out, (len(left), out[-300:]))


def covercheck_clean_lifts_the_pool_lock():
    print("== TUTORIALCOVERCHECKCLEAN: demo items on a locked pool layer ==")
    vm = load('COVERCHECK')
    vm.run('c:TUTORIALCOVERCHECK', [None, [0.0, 0.0, 0.0]])
    pool = knob(vm, '*cchk-pool-layer*')
    demo = [e for e in live(vm)
            if any(isinstance(g, Dot) and g.a == 1000 and g.b == 'TUTORIAL'
                   for g in (xdata_of(vm, e, 'COVERCHECK') or []))]
    on_pool = [e for e in demo if grp(vm, e, 8) == pool]
    set_lock(vm, pool)
    vm.printed = []
    vm.run('c:TUTORIALCOVERCHECKCLEAN', [])
    out = printed(vm)
    check("the demo put something on the pool layer to begin with",
          on_pool, [grp(vm, e, 8) for e in demo])
    check("every demo item is erased, the pool layer's included",
          demo and all(e in vm.deleted for e in demo),
          [(grp(vm, e, 0), grp(vm, e, 8)) for e in demo
           if e not in vm.deleted])
    check("...and counted: 'removed %d demo item(s)'" % len(demo),
          ('removed %d demo item(s)' % len(demo)) in out, out[-300:])
    check("the drafter's pool layer is locked again afterwards",
          layer_locked(vm, pool))

    # an item that refuses the erase whatever its layer says: counted
    # as left, named by layer, never as removed
    vm = load('COVERCHECK')
    vm.run('c:TUTORIALCOVERCHECK', [None, [0.0, 0.0, 0.0]])
    demo = [e for e in live(vm)
            if any(isinstance(g, Dot) and g.a == 1000 and g.b == 'TUTORIAL'
                   for g in (xdata_of(vm, e, 'COVERCHECK') or []))]
    stuck = next(e for e in demo if grp(vm, e, 8) == pool)
    STUBBORN.add(stuck)
    try:
        vm.printed = []
        vm.run('c:TUTORIALCOVERCHECKCLEAN', [])
    finally:
        STUBBORN.discard(stuck)
    out = printed(vm)
    check("a refused demo item is not counted as removed",
          ('removed %d demo item(s)' % (len(demo) - 1)) in out, out[-300:])
    check("...it is named, with its layer",
          ('1 demo item(s) could NOT be erased, on layer(s) '
           + pool) in out, out[-300:])


def spacheck_demo_erases_only_its_own_report():
    print("== TUTORIALSPACHECK: the erase takes the demo's report only ==")
    demo = ['Demo', [0.0, 0.0, 0.0], '', '', '']

    def drafters_report(vm):
        layer(vm, 'SPACHECK-REPORT')
        vm.loads('(entmakex (list (cons 0 "MTEXT") (cons 8 "SPACHECK-REPORT")'
                 ' (list 10 -500.0 0.0 0.0) (cons 40 5.0)'
                 ' (cons 1 "the drafter\'s own report")))')
        return vm.entities[-1]

    vm = load('SPACHECK')
    mine = drafters_report(vm)
    vm.run('c:TUTORIALSPACHECK', demo + ['Yes', None, None, 'Yes'])
    left = [e for e in live(vm) if e is not mine]
    out = printed(vm)
    check("the drafter's earlier report survives the demo's erase",
          mine not in vm.deleted)
    check("...while the demo and its own report are gone",
          not left, [(grp(vm, e, 0), grp(vm, e, 8)) for e in left])
    check("...and it says so", 'Practice drawing erased.' in out,
          out[-300:])

    vm = load('SPACHECK')
    mine = drafters_report(vm)
    vm.run('c:TUTORIALSPACHECK', demo + ['No', 'Yes'])
    check("no scan run: nothing on the report layer is swept at all",
          mine not in vm.deleted)

    def lock_then_yes(vm):
        set_lock(vm, 'SPACHECK-REPORT')
        return 'Yes'

    vm = load('SPACHECK')
    vm.run('c:TUTORIALSPACHECK', demo + ['Yes', None, None, lock_then_yes])
    out = printed(vm)
    left = [e for e in live(vm) if grp(vm, e, 8) == 'SPACHECK-REPORT']
    check("a report the lock kept is not 'Practice drawing erased.'",
          left and 'Practice drawing erased.' not in out,
          (len(left), out[-300:]))
    check("...it is counted, and the lock named",
          ('%d object(s) of the practice run on a locked layer NOT erased' % len(left))
          in out, out[-300:])


SECTIONS = [
    scans_spell_feet_and_inches, reviews_spell_the_overlap,
    covercheck_points_and_pads, linfincheck_steps_and_border,
    linfincheck_reference_sheet, spacheck_report_spells_feet_and_inches,
    rescue_counts_only_what_took, clear_old_counts_only_what_took,
    practice_drawings_on_their_own_layer,
    covercheck_clean_lifts_the_pool_lock,
    spacheck_demo_erases_only_its_own_report,
]


def main():
    for section in SECTIONS:
        # a scenario that crashes (the old code asking a question the new
        # one does not, say) is a failure of that scenario, not the file
        try:
            section()
        except (LispError, AssertionError, TypeError, KeyError,
                IndexError, StopIteration) as e:
            check(section.__name__ + ' ran to the end', False,
                  str(e).split('\n')[0])
    if FAILS:
        print("test_guardfix_review: %d FAILURE(S): %s"
              % (len(FAILS), ", ".join(FAILS)))
        return 1
    print("test_guardfix_review: all checks passed (%s tier)" % ROOT)
    return 0


if __name__ == '__main__':
    sys.exit(main())
