"""The UCS, pinned against what AutoCAD answers.

A click is a UCS point; the drawing is kept in World numbers.  trans is
how a routine carries one to the other, and a VM whose trans is the
identity -- the old one -- lets a routine that never calls it pass
every test: with the UCS on World the two frames coincide, so a click
compared raw with a survey point, or entmade raw as group 10, lands
exactly where the test expects.  Under a UCS moved onto a pool corner
-- a common setup -- the same routine draws a thousand units off.

Seven suites wrote their own trans to see that: an origin here, an
origin and a turn there, a downward (0 0 -1) plane in a third.  The VM
has one now:

  trans     codes 0 (World), 1 (the current UCS) and 2 (the display --
            the UCS here, VM POLICY: the view is plan to it), an ename
            (its own plane, from its 210, by the DXF reference's
            arbitrary axis algorithm) and a bare extrusion vector.  A
            displacement (disp non-nil) turns and never moves.
  the UCS   is what UCSORG, UCSXDIR and UCSYDIR say, in World numbers,
            as AutoCAD keeps it; WORLDUCS follows it.  All four are
            read-only, and setvar on one is refused.
  command   the points a modelled command (DIMLINEAR, DIMALIGNED,
            DIMTEDIT, DIMRADIUS, FILLET, ROTATE) is handed are read in
            the UCS, and what it leaves in the drawing is World;
            vm.commands keeps the arguments as they were given.  A
            linear DIMENSION keeps its dimension line's angle in group
            50, the UCS's turn included -- the angle the checks project
            13-14 onto to re-measure it.
  the script  a scripted click is the UCS numbers getpoint hands back,
            exactly as before.

Default World.  A World VM draws and logs as it did before, with four
differences, each AutoCAD's: trans answers a 3D point of reals, a 2D
one given its Z (it handed back whatever it was given), getvar answers
UCSORG, UCSXDIR, UCSYDIR and WORLDUCS (it answered nil), setvar on one
of them is refused (it was accepted silently), and a linear DIMENSION
carries group 50 (a vertical one used to read back as angle 0).
LISPVM_UCS="1000,500,0:30" (origin x,y,z : degrees about Z) puts that
UCS on every VM the process makes, and on each again before every
run() -- the whole suite re-run under a moved and turned UCS.  A test
that sets its own UCS keeps it.  LISPVM_UCS_CLICKS=placed makes that
sweep metamorphic: each scripted click is read as the spot on the
drawing the test meant, and handed to the routine as that spot's UCS
numbers (getvar VIEWCTR likewise), and vm.commands logs the points a
command was handed in World numbers again -- so the test's fixture, its
clicks and what it reads back all stay in the one frame it was written
in, and only a routine that mixes the frames fails.

Two kinds of pin.  A T, O, S, C or W pin is AutoCAD behaviour, or
the test API, and names its source.  A V pin is VM POLICY and says so.

Not modelled, and refused rather than guessed (lispvm.NotModelled):
code 3 (paper-space DCS: the VM has no viewports); a 2D polyline VERTEX
of a plane that is not +Z (a vertex carries no 210, and what trans
reads its ECS as is not documented); a float code; and every modelled
command above under a UCS whose Z is not World Z -- the VM does their
arithmetic in the World plan (C6).  An ename whose points DXF keeps in
World (LINE, POINT, MTEXT, ELLIPSE, a 3D polyline ...) is NOT refused:
trans through it is the null operation the reference names, whatever
its 210 (O5).  Not modelled and not refused: a dimension's optional
group 51 (the UCS's turn, negated); a DCS of its own (V1).

The file imports nothing the old VM lacks, so it runs against an older
tests/lispvm.py too and names the pins that VM fails: it sets a UCS
through vm.set_ucs when there is one and by writing the three sysvars
when there is not.

Run: python3 tests/test_lispvm_ucs.py
"""

import math
import os
import sys

# the sweep is the VM's; this file pins the VM itself, so an ambient one
# is taken off for its own VMs and put on only where a pin says so
for _k in ('LISPVM_UCS', 'LISPVM_UCS_CLICKS'):
    os.environ.pop(_k, None)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lispvm  # noqa: E402
from lispvm import VM, Sym, NIL, LispError  # noqa: E402

NOT_MODELLED = getattr(lispvm, 'NotModelled', None)

# ---------------------------------------------------------------- sources
TRANS_DOC = ("AutoLISP Reference, trans: '(trans pt from to [disp])' -- "
             "'Translates a point (or a displacement) from one coordinate "
             "system to another'; from / to: 'An integer code, entity "
             "name, or 3D extrusion vector': 0 World (WCS), 1 User "
             "(current UCS), 2 Display (DCS) of the current viewport when "
             "used with code 0 or 1, 3 Paper space DCS, used only with "
             "code 2; an entity name is that entity's ECS (its OCS); "
             "disp: 'If present and is not nil, pt is treated as a 3D "
             "displacement rather than a 3D point'")
TRANS_RET_DOC = ("AutoLISP Reference, trans, Return Values: 'A 3D point (or "
                 "displacement)'; and 'The trans function can also "
                 "transform 2D points.  It does this by setting the Z "
                 "coordinate to an appropriate value': a displacement "
                 "0.0; a point, by the table 'Converted 2D point Z "
                 "values' -- from WCS 0.0, from UCS the current "
                 "elevation, from OCS 0.0, from DCS projected to the "
                 "current construction plane (UCS XY plane + current "
                 "elevation)")
NULLOP_DOC = ("AutoLISP Reference, trans: 'For some objects, the OCS is "
              "equivalent to the WCS; for these objects, conversion "
              "between OCS and WCS is a null operation'; the extrusion "
              "vector form 'does not work for those objects whose OCS is "
              "equivalent to the WCS'")
DIM50_DOC = ("DXF Reference, DIMENSION, Linear and Rotated Dimension group "
             "codes: 13 / 14 'Definition point for linear and angular "
             "dimensions (in WCS)', 50 'Angle of rotated, horizontal, or "
             "vertical dimensions' -- the dimension line's angle in its "
             "plane, which is the World plan for a plan UCS; aligned "
             "dimensions carry no 50.  And the repo's three readers "
             "(covercheck.lsp cchk:dim-meas, dimcheck.lsp dchk:dim-meas, "
             "linfincheck.lsp lfc:dim-meas) re-measure a linear dim as "
             "|(14 - 13) . (cos 50, sin 50)|, a missing 50 read as 0")
UCSVARS_DOC = ("AutoCAD system variables, all (Read-only): UCSORG 'Stores "
               "the origin point of the current coordinate system ... "
               "This value is always stored as a world coordinate'; "
               "UCSXDIR / UCSYDIR 'Stores the X (Y) direction of the "
               "current UCS'; WORLDUCS 'Indicates whether the UCS is the "
               "same as the WCS': 0 UCS differs from WCS, 1 UCS matches "
               "WCS")
READONLY_DOC = ("AutoCAD: setvar on a read-only system variable is "
                "refused -- '; error: AutoCAD variable setting rejected' "
                "-- and the value stays; UCSORG, UCSXDIR, UCSYDIR and "
                "WORLDUCS are each documented (Read-only)")
AAA_DOC = ("DXF Reference, 'Arbitrary Axis Algorithm': with N the unit "
           "extrusion, if |Nx| < 1/64 and |Ny| < 1/64 then Ax = Wy x N, "
           "else Ax = Wz x N; Ay = N x Ax, both normalised; the OCS point "
           "(x y z) is x*Ax + y*Ay + z*N in the world.  And 'Object "
           "Coordinate Systems (OCS)': ARC, CIRCLE, TEXT, INSERT, "
           "LWPOLYLINE and 2D POLYLINE keep their points in it")
WCS_TYPES_DOC = ("DXF Reference, 'Object Coordinate Systems (OCS)': "
                 "'Points for these entities are expressed in WCS' -- "
                 "LINE, POINT, 3DFACE, 3D polyline, 3D vertex, mesh; "
                 "MTEXT, ELLIPSE and SPLINE keep World points too.  What "
                 "trans reads a 2D polyline's VERTEX (which has no 210 of "
                 "its own) as is not documented")
GETPOINT_DOC = ("AutoLISP Reference, getpoint / getcorner: 'Returns: a 3D "
                "point, expressed in terms of the current UCS'; entsel's "
                "pick point likewise.  lispvm: a scripted click IS that "
                "return -- the UCS numbers")
COMMAND_DOC = ("AutoCAD reads a point handed to (command ...) as a typed "
               "coordinate, in the current UCS, and keeps the object it "
               "makes in World numbers (AutoLISP Developer's Guide, "
               "'Coordinate System Transformations': trans exists to "
               "hand entity data to a command); the repo's own fakes said "
               "so: tests/test_fix_annot_a_ucs.py '(command ...) still "
               "takes its points as given, which is how AutoCAD reads "
               "them -- in the UCS', tests/test_fix_review_b.py "
               "ShiftedUCS '(command ...) reads every point it is handed "
               "as a UCS point, as AutoCAD's does'")
ENTMAKE_DOC = ("AutoLISP Reference, entmake: the list is DXF group codes, "
               "and DXF keeps a LINE's 10/11 in World numbers whatever the "
               "UCS -- entmake transforms nothing")
DCS_POLICY = ("VM POLICY, not AutoCAD fact: AutoCAD's DCS has its origin "
              "at TARGET and its Z along VIEWDIR, neither modelled; the "
              "VM takes the view to be plan to the current UCS, so code 2 "
              "is the UCS.  In a real drawing the more common state is "
              "the other one -- UCSFOLLOW is 0 by default, so a drafter "
              "who moves the UCS keeps the World plan view, and the DCS "
              "is World's.  Nothing in lisp/ trans'es to or from 2 or 3 "
              "today, so the choice is inert; a faithful DCS replaces "
              "this pin")
VIEWCTR_DOC = ("AutoCAD VIEWCTR: 'Stores the center of view in the "
               "current viewport.  Expressed as a UCS coordinate'")
CONTRACT = "lispvm test API, kept"

# the UCS the pins use: World (1000, 500, 0), turned 30 degrees
O = (1000.0, 500.0, 0.0)
DEG = 30.0
C, S = math.cos(math.radians(DEG)), math.sin(math.radians(DEG))


def u2w(p, disp=False):
    x, y = p[0], p[1]
    z = p[2] if len(p) > 2 else 0.0
    w = [x * C - y * S, x * S + y * C, z]
    return w if disp else [w[0] + O[0], w[1] + O[1], w[2] + O[2]]


def w2u(p, disp=False):
    x, y = p[0], p[1]
    z = p[2] if len(p) > 2 else 0.0
    if not disp:
        x, y, z = x - O[0], y - O[1], z - O[2]
    return [x * C + y * S, -x * S + y * C, z]


def near(p, q, eps=1e-9):
    return (isinstance(p, list) and len(p) == len(q)
            and all(abs(a - b) <= eps for a, b in zip(p, q)))


def put_ucs(vm, origin=O, deg=DEG):
    """The UCS on VM: through set_ucs when the VM has one, else the
    three sysvars written straight -- which an old VM keeps and ignores,
    so its pins fail on what trans answers, not on a missing name."""
    if hasattr(vm, 'set_ucs'):
        vm.set_ucs(origin, math.radians(deg))
        return vm
    r = math.radians(deg)
    vm.sysvars['UCSORG'] = [float(c) for c in origin]
    vm.sysvars['UCSXDIR'] = [math.cos(r), math.sin(r), 0.0]
    vm.sysvars['UCSYDIR'] = [-math.sin(r), math.cos(r), 0.0]
    vm.sysvars['WORLDUCS'] = 0
    return vm


def moved():
    return put_ucs(VM())


def ev(vm, src):
    return vm.loads(src)


def refused(fn, cls):
    """What FN raised when it was refused with CLS, else None."""
    try:
        fn()
    except Exception as x:              # noqa: BLE001 -- sorted below
        if cls is not None and isinstance(x, cls):
            return x
        raise
    return None


def need(x, name):
    if x is None:
        raise AssertionError('this lispvm has no %s' % name)
    return x


def ent(vm, src):
    vm.loads(src)
    return vm.entities[-1]


def grp(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, lispvm.Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else [float(v) for v in g[1:]]
    return None


def lisp_pt(p):
    return "'(%s)" % ' '.join(repr(float(c)) for c in p)


PINS = []


def pin(pid, rule, source):
    def wrap(fn):
        PINS.append((pid, rule, source, fn))
        return fn
    return wrap


# ================================================================ World
@pin('T1', "with the UCS on World, trans between 0, 1 and 2 moves "
     "nothing, and still answers a 3D point of reals: integers come back "
     "real, a 2D point gets its Z by the table (from World 0.0, from the "
     "UCS the current ELEVATION)", TRANS_RET_DOC)
def _t1():
    vm = VM()
    got = [ev(vm, "(trans '(10 20 3) 1 0)"), ev(vm, "(trans '(10 20) 0 1)"),
           ev(vm, "(trans '(1.5 2.5 0.0) 2 0)"),
           ev(vm, "(trans '(1.5 2.5 0.0) 0 1 T)")]
    vm.sysvars['ELEVATION'] = 5.0
    got += [ev(vm, "(trans '(10 20) 1 0)"), ev(vm, "(trans '(10 20) 0 1)"),
            ev(vm, "(trans '(10 20) 1 0 T)")]
    want = [[10.0, 20.0, 3.0], [10.0, 20.0, 0.0], [1.5, 2.5, 0.0],
            [1.5, 2.5, 0.0], [10.0, 20.0, 5.0], [10.0, 20.0, 0.0],
            [10.0, 20.0, 0.0]]
    return (got == want
            and all(isinstance(c, float) for p in got for c in p)), got


@pin('T2', "a new drawing's UCS is World: UCSORG (0 0 0), UCSXDIR "
     "(1 0 0), UCSYDIR (0 1 0), WORLDUCS 1", UCSVARS_DOC)
def _t2():
    vm = VM()
    got = [ev(vm, '(getvar "%s")' % v)
           for v in ('UCSORG', 'UCSXDIR', 'UCSYDIR', 'WORLDUCS')]
    return got == [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0],
                   1], got


# ============================================================ the UCS
@pin('T3', "UCS -> World: (trans u 1 0) is UCSORG plus u turned onto "
     "UCSXDIR / UCSYDIR", TRANS_DOC + '; ' + UCSVARS_DOC)
def _t3():
    vm = moved()
    got = [ev(vm, "(trans '(10.0 20.0 0.0) 1 0)"),
           ev(vm, "(trans '(0.0 0.0 0.0) 1 0)"),
           ev(vm, "(trans '(100.0 0.0 5.0) 1 0)")]
    want = [u2w([10.0, 20.0, 0.0]), list(O), u2w([100.0, 0.0, 5.0])]
    return all(near(g, w) for g, w in zip(got, want)), (got, want)


@pin('T4', "World -> UCS is the inverse: (trans w 0 1), and a round trip "
     "comes home", TRANS_DOC + '; ' + UCSVARS_DOC)
def _t4():
    vm = moved()
    w = [1234.5, -67.0, 2.0]
    got = ev(vm, "(trans %s 0 1)" % lisp_pt(w))
    back = ev(vm, "(trans (trans %s 0 1) 1 0)" % lisp_pt(w))
    return near(got, w2u(w)) and near(back, w), (got, w2u(w), back)


@pin('T5', "a displacement (disp non-nil) is turned and never moved: "
     "(trans v 1 0 T) has no origin in it", TRANS_DOC)
def _t5():
    vm = moved()
    got = [ev(vm, "(trans '(10.0 0.0 0.0) 1 0 T)"),
           ev(vm, "(trans '(10.0 0.0 0.0) 0 1 T)"),
           ev(vm, "(trans '(0.0 0.0 1.0) 1 0 T)")]
    want = [u2w([10.0, 0.0, 0.0], True), w2u([10.0, 0.0, 0.0], True),
            [0.0, 0.0, 1.0]]
    return all(near(g, w) for g, w in zip(got, want)), (got, want)


@pin('T6', "WORLDUCS follows the UCS: 0 once it is moved, and UCSORG / "
     "UCSXDIR / UCSYDIR report it in World numbers; back on World it is "
     "1 again", UCSVARS_DOC)
def _t6():
    vm = moved()
    got = [ev(vm, '(getvar "%s")' % v)
           for v in ('WORLDUCS', 'UCSORG', 'UCSXDIR', 'UCSYDIR')]
    ok = (got[0] == 0 and near(got[1], list(O)) and near(got[2], [C, S, 0.0])
          and near(got[3], [-S, C, 0.0]))
    need(getattr(vm, 'set_ucs', None), 'set_ucs')
    vm.set_ucs()
    again = ev(vm, '(list (getvar "WORLDUCS") (trans \'(1.0 2.0 0.0) 1 0))')
    return ok and again == [1, [1.0, 2.0, 0.0]], (got, again)


@pin('T7', "UCSORG, UCSXDIR, UCSYDIR and WORLDUCS are read-only: setvar "
     "is refused and the value stays", READONLY_DOC + '; ' + UCSVARS_DOC)
def _t7():
    bad = []
    for var, val in (('UCSORG', "'(5.0 5.0 0.0)"),
                     ('UCSXDIR', "'(0.0 1.0 0.0)"),
                     ('UCSYDIR', "'(-1.0 0.0 0.0)"), ('WORLDUCS', '0')):
        vm = VM()
        before = ev(vm, '(getvar "%s")' % var)
        try:
            ev(vm, '(setvar "%s" %s)' % (var, val))
            bad.append((var, 'accepted'))
        except LispError:
            pass
        after = ev(vm, '(getvar "%s")' % var)
        if after != before:
            bad.append((var, before, after))
    return not bad, bad


@pin('V1', "VM POLICY -- the display is plan to the UCS: code 2 is the "
     "UCS", DCS_POLICY)
def _v1():
    vm = moved()
    got = [ev(vm, "(trans '(10.0 20.0 0.0) 2 0)"),
           ev(vm, "(trans '(10.0 20.0 0.0) 1 2)"),
           ev(vm, "(trans %s 0 2)" % lisp_pt(u2w([3.0, 4.0, 0.0])))]
    want = [u2w([10.0, 20.0, 0.0]), [10.0, 20.0, 0.0], [3.0, 4.0, 0.0]]
    return all(near(g, w) for g, w in zip(got, want)), (got, want)


@pin('T8', "code 3, paper-space DCS, is refused as unmodelled -- the VM "
     "has no viewports", TRANS_DOC)
def _t8():
    need(NOT_MODELLED, 'NotModelled')
    vm = VM()
    x = refused(lambda: ev(vm, "(trans '(1.0 2.0 0.0) 2 3)"), NOT_MODELLED)
    return x is not None, x


@pin('T9', "nil for the point, or a code that is none of 0-3, is an "
     "error", TRANS_DOC)
def _t9():
    bad = []
    for src in ("(trans nil 1 0)", "(trans '(1.0 2.0 0.0) 7 0)",
                "(trans '(1.0 2.0 0.0) 0 \"UCS\")"):
        try:
            got = ev(moved(), src)
            bad.append((src, got))
        except LispError:
            pass
    return not bad, bad


@pin('T10', "a 2D point that moves comes back 3D, with the Z the "
     "reference's table fills in: from the UCS the current ELEVATION, "
     "from World or an OCS 0.0, a displacement 0.0", TRANS_RET_DOC)
def _t10():
    vm = moved()
    vm.sysvars['ELEVATION'] = 5.0
    vm.globals[Sym('t:v')] = [0.0, 0.0, -1.0]
    got = [ev(vm, "(trans '(10.0 20.0) 1 0)"),
           ev(vm, "(trans '(10.0 20.0) 0 1)"),
           ev(vm, "(trans '(10.0 20.0) 1 0 T)"),
           ev(vm, "(trans '(10.0 20.0) t:v 0)")]
    want = [u2w([10.0, 20.0, 5.0]), w2u([10.0, 20.0, 0.0]),
            u2w([10.0, 20.0, 0.0], True), [-10.0, 20.0, 0.0]]
    return all(near(g, w) for g, w in zip(got, want)), (got, want)


# ============================================================ the OCS
DOWN_ARC = ('(entmake (list \'(0 . "ARC") \'(8 . "0") (list 10 100.0 20.0 '
            '0.0) \'(40 . 30.0) \'(50 . 0.0) \'(51 . 1.0) '
            '(list 210 0.0 0.0 -1.0)))')


@pin('O1', "an ename is its own plane: an ARC whose 210 is (0 0 -1) has "
     "X the other way round and Z down -- (100 20 3) in it is (-100 20 -3) "
     "in the world, and back", AAA_DOC + '; ' + TRANS_DOC)
def _o1():
    vm = VM()
    arc = ent(vm, DOWN_ARC)
    vm.globals[Sym('t:e')] = arc
    got = [ev(vm, "(trans '(100.0 20.0 3.0) t:e 0)"),
           ev(vm, "(trans '(-100.0 20.0 -3.0) 0 t:e)")]
    want = [[-100.0, 20.0, -3.0], [100.0, 20.0, 3.0]]
    return all(near(g, w) for g, w in zip(got, want)), (got, want)


@pin('O2', "an ename with no 210, or 210 (0 0 1), is the world plane: "
     "(trans p e 0) is p even under a moved UCS, and (trans p e 1) is "
     "World -> UCS", AAA_DOC + '; ' + TRANS_DOC)
def _o2():
    vm = moved()
    flat = ent(vm, '(entmake (list \'(0 . "CIRCLE") \'(8 . "0") '
               '\'(10 5.0 6.0 0.0) \'(40 . 2.0)))')
    up = ent(vm, '(entmake (list \'(0 . "ARC") \'(8 . "0") '
             '\'(10 5.0 6.0 0.0) \'(40 . 2.0) \'(50 . 0.0) \'(51 . 1.0) '
             '\'(210 0.0 0.0 1.0)))')
    vm.globals[Sym('t:a')] = flat
    vm.globals[Sym('t:b')] = up
    w = [1100.0, 600.0, 0.0]
    got = [ev(vm, "(trans %s t:a 0)" % lisp_pt(w)),
           ev(vm, "(trans %s t:b 0)" % lisp_pt(w)),
           ev(vm, "(trans %s t:a 1)" % lisp_pt(w))]
    want = [w, w, w2u(w)]
    return all(near(g, x) for g, x in zip(got, want)), (got, want)


@pin('O3', "a bare extrusion vector is that plane: (1 0 0)'s OCS has "
     "X along world Y, Y along world Z, Z along world X -- (x y z) is "
     "(z x y) -- and (0 0 -1)'s is the downward plane of O1", AAA_DOC)
def _o3():
    vm = VM()
    got = [ev(vm, "(trans '(1.0 2.0 3.0) '(1.0 0.0 0.0) 0)"),
           ev(vm, "(trans '(3.0 1.0 2.0) 0 '(1.0 0.0 0.0))"),
           ev(vm, "(trans '(1.0 2.0 3.0) '(0.0 0.0 -1.0) 0)"),
           ev(vm, "(trans '(1.0 2.0 3.0) '(0.0 0.0 5.0) 0)")]
    want = [[3.0, 1.0, 2.0], [1.0, 2.0, 3.0], [-1.0, 2.0, -3.0],
            [1.0, 2.0, 3.0]]
    return all(near(g, w) for g, w in zip(got, want)), (got, want)


@pin('O4', "a tilted plane off the 1/64 test, (0 -0.6 0.8): Ax = Wz x N "
     "normalised is (1 0 0), Ay = N x Ax is (0 0.8 0.6) -- and the round "
     "trip comes home", AAA_DOC)
def _o4():
    vm = VM()
    got = ev(vm, "(trans '(2.0 5.0 10.0) '(0.0 -0.6 0.8) 0)")
    # 2*(1 0 0) + 5*(0 .8 .6) + 10*(0 -.6 .8)
    want = [2.0, 4.0 - 6.0, 3.0 + 8.0]
    back = ev(vm, "(trans (trans '(2.0 5.0 10.0) '(0.0 -0.6 0.8) 0) "
                  "0 '(0.0 -0.6 0.8))")
    return near(got, want) and near(back, [2.0, 5.0, 10.0]), (got, back)


@pin('O5', "an ename whose points DXF keeps in World (LINE, POINT, "
     "MTEXT, ELLIPSE, a 3D polyline) is the World frame whatever its 210: "
     "trans through it hands the point back; a VERTEX of a 2D polyline "
     "off +Z is refused as unmodelled",
     NULLOP_DOC + '; ' + WCS_TYPES_DOC)
def _o5():
    need(NOT_MODELLED, 'NotModelled')
    bad = []
    for typ, extra in (('LINE', " '(11 1.0 0.0 0.0)"), ('POINT', ''),
                       ('MTEXT', " '(1 . \"x\")"),
                       ('ELLIPSE', " '(11 5.0 0.0 0.0) '(40 . 0.5)")):
        vm = moved()
        e = ent(vm, '(entmake (list \'(0 . "%s") \'(8 . "0") '
                '\'(10 1.0 2.0 0.0)%s \'(210 0.0 0.0 -1.0)))' % (typ, extra))
        vm.globals[Sym('t:e')] = e
        w = [1.0, 2.0, 3.0]
        try:
            got = [ev(vm, "(trans %s t:e 0)" % lisp_pt(w)),
                   ev(vm, "(trans %s 0 t:e)" % lisp_pt(w)),
                   ev(vm, "(trans %s t:e 1)" % lisp_pt(w))]
        except Exception as x:          # noqa: BLE001 -- a refusal is a miss
            bad.append((typ, type(x).__name__))
            continue
        if not (near(got[0], w) and near(got[1], w)
                and near(got[2], w2u(w))):
            bad.append((typ, got))
    # a 3D polyline (70 bit 8) is World too, even carrying a 210
    vm = VM()
    e = ent(vm, '(entmake (list \'(0 . "POLYLINE") \'(8 . "0") \'(66 . 1) '
            '\'(10 0.0 0.0 0.0) \'(70 . 8) \'(210 0.0 0.0 -1.0)))')
    vm.globals[Sym('t:e')] = e
    if ev(vm, "(trans '(1.0 2.0 3.0) t:e 0)") != [1.0, 2.0, 3.0]:
        bad.append('3D POLYLINE')
    # a 2D polyline's VERTEX carries no 210: its plane is its header's,
    # and what trans reads a vertex's ECS as is not documented
    vm = VM()
    ent(vm, '(entmake (list \'(0 . "POLYLINE") \'(8 . "0") \'(66 . 1) '
        '\'(10 0.0 0.0 0.0) \'(70 . 0) \'(210 0.0 0.0 -1.0)))')
    vm.globals[Sym('t:e')] = ent(vm, '(entmake (list \'(0 . "VERTEX") '
                                 '\'(8 . "0") \'(10 5.0 0.0 0.0)))')
    if refused(lambda: ev(vm, "(trans '(1.0 2.0 0.0) t:e 0)"),
               NOT_MODELLED) is None:
        bad.append('VERTEX')
    return not bad, bad


# ============================================================ the script
@pin('S1', "a scripted click is the UCS numbers getpoint hands back: the "
     "VM moves nothing, and (trans click 1 0) is where it is in the "
     "world", GETPOINT_DOC + '; ' + CONTRACT)
def _s1():
    vm = moved()
    vm.script = [[10.0, 20.0, 0.0], [5.0, 5.0, 0.0]]
    got = ev(vm, '(list (getpoint "\\nPick: ") '
                 '(trans (getpoint "\\nPick: ") 1 0))')
    return (got[0] == [10.0, 20.0, 0.0]
            and near(got[1], u2w([5.0, 5.0, 0.0]))), got


@pin('S2', "entmake transforms nothing: a LINE made under a moved UCS "
     "carries the numbers it was given, which are World", ENTMAKE_DOC)
def _s2():
    vm = moved()
    e = ent(vm, '(entmake (list \'(0 . "LINE") \'(8 . "0") '
            '\'(10 1.0 2.0 0.0) \'(11 3.0 4.0 0.0)))')
    got = (grp(vm, e, 10), grp(vm, e, 11))
    return got == ([1.0, 2.0, 0.0], [3.0, 4.0, 0.0]), got


# ============================================================ command
@pin('C1', "DIMLINEAR under a moved UCS: its 13/14/10 are the World "
     "points of the UCS arguments, it measures along the UCS axes, its "
     "group 50 is the UCS's turn, and vm.commands keeps the arguments "
     "as given", COMMAND_DOC + '; ' + DIM50_DOC)
def _c1():
    vm = moved()
    a, b, loc = [0.0, 0.0, 0.0], [100.0, 40.0, 0.0], [50.0, -20.0, 0.0]
    vm.globals[Sym('t:a')], vm.globals[Sym('t:b')] = a, b
    vm.globals[Sym('t:l')] = loc
    ev(vm, '(command "_.DIMLINEAR" t:a t:b "_H" t:l)')
    d = vm.entities[-1]
    got = [grp(vm, d, 13), grp(vm, d, 14), grp(vm, d, 10), grp(vm, d, 42),
           vm.commands[-1], grp(vm, d, 50)]
    ok = (near(got[0], u2w(a)) and near(got[1], u2w(b))
          and near(got[2], u2w(loc)) and abs(got[3] - 100.0) < 1e-9
          and got[4] == ['_.DIMLINEAR', a, b, '_H', loc]
          and got[5] is not None
          and abs(got[5] - math.radians(DEG)) < 1e-9)
    return ok, got


@pin('C2', "ROTATE's base point is read in the UCS: a LINE turned 90 "
     "degrees about UCS (0 0) turns about UCSORG in the world",
     COMMAND_DOC)
def _c2():
    vm = moved()
    e = ent(vm, '(entmake (list \'(0 . "LINE") \'(8 . "0") '
            '(list 10 1000.0 500.0 0.0) (list 11 1010.0 500.0 0.0)))')
    vm.globals[Sym('t:s')] = ['<ss>', e]
    ev(vm, '(command "_.ROTATE" t:s "" \'(0.0 0.0 0.0) 90.0)')
    got = (grp(vm, e, 10), grp(vm, e, 11))
    return (near(got[0], [1000.0, 500.0, 0.0])
            and near(got[1], [1000.0, 510.0, 0.0])), got


@pin('C3', "FILLET at radius 0 reads its pick points in the UCS: the side "
     "each line keeps is the side of the World point the UCS pick names",
     COMMAND_DOC)
def _c3():
    vm = put_ucs(VM(), (100.0, 0.0, 0.0), 0.0)
    h = ent(vm, '(entmake (list \'(0 . "LINE") \'(8 . "0") '
            '\'(10 0.0 0.0 0.0) \'(11 200.0 0.0 0.0)))')
    v = ent(vm, '(entmake (list \'(0 . "LINE") \'(8 . "0") '
            '\'(10 150.0 -50.0 0.0) \'(11 150.0 50.0 0.0)))')
    vm.globals[Sym('t:h')], vm.globals[Sym('t:v')] = h, v
    # the two cross at World (150, 0).  UCS (60, 0) is World (160, 0),
    # RIGHT of the crossing, so the horizontal keeps its right end --
    # read raw, (60, 0) is left of it and the left end would stay
    ev(vm, '(command "_.FILLET" (list t:h \'(60.0 0.0 0.0)) '
           '(list t:v \'(50.0 40.0 0.0)))')
    got = (grp(vm, h, 10), grp(vm, h, 11), grp(vm, v, 10), grp(vm, v, 11))
    return (near(got[0], [150.0, 0.0, 0.0])
            and near(got[1], [200.0, 0.0, 0.0])
            and near(got[2], [150.0, 0.0, 0.0])
            and near(got[3], [150.0, 50.0, 0.0])), got


@pin('C4', "DIMTEDIT's new text spot and DIMRADIUS's pick and text spot "
     "are read in the UCS", COMMAND_DOC)
def _c4():
    vm = moved()
    arc = ent(vm, '(entmake (list \'(0 . "ARC") \'(8 . "0") '
              '(list 10 1000.0 500.0 0.0) \'(40 . 30.0) \'(50 . 0.0) '
              '\'(51 . 3.0)))')
    vm.globals[Sym('t:arc')] = arc
    on = w2u([1030.0, 500.0, 0.0])
    vm.globals[Sym('t:on')] = on
    ev(vm, '(command "_.DIMRADIUS" (list t:arc t:on) \'(40.0 0.0 0.0))')
    d = vm.entities[-1]
    ok1 = (near(grp(vm, d, 15), [1030.0, 500.0, 0.0])
           and near(grp(vm, d, 11), u2w([40.0, 0.0, 0.0]))
           and abs(grp(vm, d, 40) - 30.0) < 1e-9)
    ev(vm, '(command "_.DIMLINEAR" \'(0.0 0.0 0.0) \'(10.0 0.0 0.0) '
           '\'(5.0 5.0 0.0))')
    lin = vm.entities[-1]
    vm.globals[Sym('t:d')] = lin
    ev(vm, '(command "_.DIMTEDIT" t:d \'(7.0 9.0 0.0))')
    ok2 = near(grp(vm, lin, 11), u2w([7.0, 9.0, 0.0]))
    return ok1 and ok2, (grp(vm, d, 15), grp(vm, d, 11), grp(vm, lin, 11))


# the three checks' own re-measure of a linear dim (cchk:dim-meas and its
# DIMCHECK / LINFINCHECK twins), without the unit formatting
REMEASURE = """
(defun t:meas (e / ed ang v)
  (setq ed (entget e) ang (cdr (assoc 50 ed)))
  (if (null ang) (setq ang 0.0))
  (setq v (mapcar '- (cdr (assoc 14 ed)) (cdr (assoc 13 ed))))
  (abs (+ (* (car v) (cos ang)) (* (cadr v) (sin ang)))))
"""


@pin('C5', "a linear DIMENSION keeps its dimension line's angle in group "
     "50 -- 0 for _H, pi/2 for _V, the _R angle, the axis it picked by "
     "itself -- turned by the UCS it was drawn in, so projecting 13-14 "
     "onto 50 reads back the 42 it measured; an aligned one has no 50",
     DIM50_DOC + '; ' + COMMAND_DOC)
def _c5():
    bad = []
    a, b = "'(0.0 0.0 0.0)", "'(180.0 60.0 0.0)"
    cases = [('"_H" \'(90.0 -40.0 0.0)', 0.0, 180.0),
             ('"_V" \'(-40.0 30.0 0.0)', 90.0, 60.0),
             ('"_R" "30" \'(90.0 -40.0 0.0)', 30.0,
              abs(180.0 * math.cos(math.radians(30.0))
                  + 60.0 * math.sin(math.radians(30.0)))),
             ("'(90.0 -40.0 0.0)", 0.0, 180.0),     # stands off in Y
             ("'(-40.0 30.0 0.0)", 90.0, 60.0)]     # stands off in X
    for world in (True, False):
        vm = VM() if world else moved()
        vm.loads(REMEASURE)
        turn = 0.0 if world else DEG
        for tail, deg, meas in cases:
            ev(vm, '(command "_.DIMLINEAR" %s %s %s)' % (a, b, tail))
            d = vm.entities[-1]
            vm.globals[Sym('t:d')] = d
            g50, g42 = grp(vm, d, 50), grp(vm, d, 42)
            back = ev(vm, '(t:meas t:d)')
            want50 = math.radians(deg + turn) % (2.0 * math.pi)
            if not (g50 is not None and abs(g50 - want50) < 1e-9
                    and abs(g42 - meas) < 1e-9
                    and abs(back - meas) < 1e-9):
                bad.append((world, tail, g50, want50, g42, back, meas))
        ev(vm, '(command "_.DIMALIGNED" %s %s \'(0.0 50.0 0.0))' % (a, b))
        if grp(vm, vm.entities[-1], 50) is not None:
            bad.append((world, 'DIMALIGNED has a 50'))
    return not bad, bad


@pin('C6', "under a UCS whose Z is not World Z every modelled command "
     "that reads points -- DIMLINEAR, DIMALIGNED, DIMRADIUS, DIMTEDIT, "
     "FILLET's picks, ROTATE -- is refused as unmodelled: the VM does "
     "their arithmetic in the World plan", COMMAND_DOC + '; ' + CONTRACT)
def _c6():
    need(NOT_MODELLED, 'NotModelled')
    r = 0.7071067811865476

    def tilted():
        vm = VM()
        need(getattr(vm, 'set_ucs', None), 'set_ucs')
        vm.set_ucs((0.0, 0.0, 0.0), xdir=(1.0, 0.0, 0.0), ydir=(0.0, r, r))
        line = ent(vm, '(entmake (list \'(0 . "LINE") \'(8 . "0") '
                   '\'(10 0.0 0.0 0.0) \'(11 10.0 0.0 0.0)))')
        arc = ent(vm, '(entmake (list \'(0 . "ARC") \'(8 . "0") '
                  '\'(10 0.0 0.0 0.0) \'(40 . 5.0) \'(50 . 0.0) '
                  '\'(51 . 3.0)))')
        vm.globals[Sym('t:l')], vm.globals[Sym('t:a')] = line, arc
        vm.globals[Sym('t:s')] = ['<ss>', line]
        return vm

    bad = []
    srcs = ['(command "_.DIMLINEAR" \'(0.0 0.0 0.0) \'(10.0 0.0 0.0) '
            '\'(5.0 5.0 0.0))',
            '(command "_.DIMALIGNED" \'(0.0 0.0 0.0) \'(10.0 0.0 0.0) '
            '\'(5.0 5.0 0.0))',
            '(command "_.DIMRADIUS" (list t:a \'(5.0 0.0 0.0)) '
            '\'(8.0 0.0 0.0))',
            '(command "_.FILLET" (list t:l \'(1.0 0.0 0.0)) '
            '(list t:l \'(9.0 0.0 0.0)))',
            '(command "_.ROTATE" t:s "" \'(0.0 0.0 0.0) 90.0)']
    for src in srcs:
        vm = tilted()
        if refused(lambda: ev(vm, src), NOT_MODELLED) is None:
            bad.append(src.split('"')[1])
    # a dimension made on World, for DIMTEDIT to move under the tilt
    vm = tilted()
    vm.set_ucs()
    ev(vm, '(command "_.DIMLINEAR" \'(0.0 0.0 0.0) \'(10.0 0.0 0.0) '
           '\'(5.0 5.0 0.0))')
    vm.globals[Sym('t:d')] = vm.entities[-1]
    vm.set_ucs((0.0, 0.0, 0.0), xdir=(1.0, 0.0, 0.0), ydir=(0.0, r, r))
    if refused(lambda: ev(vm, '(command "_.DIMTEDIT" t:d '
                              '\'(7.0 9.0 0.0))'), NOT_MODELLED) is None:
        bad.append('_.DIMTEDIT')
    # a FILLET that only sets the radius reads no point, and runs
    vm = tilted()
    ev(vm, '(command "_.FILLET" "_R" 5.0)')
    return not bad, bad


# ============================================================ the API
@pin('W1', "vm.set_ucs(origin, angle) puts a plan UCS on (angle in "
     "radians about Z), vm.set_ucs() takes it back to World, and "
     "vm.ucs_to_wcs / vm.wcs_to_ucs say where a point is", CONTRACT)
def _w1():
    vm = VM()
    need(getattr(vm, 'set_ucs', None), 'set_ucs')
    vm.set_ucs(O, math.radians(DEG))
    got = [vm.ucs_to_wcs([10.0, 20.0, 0.0]),
           vm.wcs_to_ucs(u2w([10.0, 20.0, 0.0])),
           vm.ucs_to_wcs([10.0, 0.0, 0.0], disp=True)]
    want = [u2w([10.0, 20.0, 0.0]), [10.0, 20.0, 0.0],
            u2w([10.0, 0.0, 0.0], True)]
    vm.set_ucs()
    world = ev(vm, '(getvar "WORLDUCS")')
    return (all(near(g, w) for g, w in zip(got, want)) and world == 1), \
        (got, world)


@pin('W2', "a UCS tilted off the world plan is given by its axes: "
     "(trans '(0 0 1) 1 0 T) is its Z; axes that are not unit and square "
     "are refused", TRANS_DOC + '; ' + CONTRACT)
def _w2():
    vm = VM()
    need(getattr(vm, 'set_ucs', None), 'set_ucs')
    r = 0.7071067811865476
    vm.set_ucs((0.0, 0.0, 0.0), xdir=(1.0, 0.0, 0.0), ydir=(0.0, r, r))
    z = ev(vm, "(trans '(0.0 0.0 1.0) 1 0 T)")
    try:
        vm.set_ucs((0.0, 0.0, 0.0), xdir=(1.0, 0.0, 0.0), ydir=(1.0, 1.0, 0.0))
        refused_bad = False
    except ValueError:
        refused_bad = True
    return near(z, [0.0, -r, r]) and refused_bad, (z, refused_bad)


def sweep(spec, clicks=None):
    """A VM made while LISPVM_UCS (and LISPVM_UCS_CLICKS) say SPEC."""
    saved = {k: os.environ.get(k) for k in ('LISPVM_UCS',
                                            'LISPVM_UCS_CLICKS')}
    try:
        os.environ['LISPVM_UCS'] = spec
        if clicks:
            os.environ['LISPVM_UCS_CLICKS'] = clicks
        else:
            os.environ.pop('LISPVM_UCS_CLICKS', None)
        return VM()
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


@pin('W3', "LISPVM_UCS=\"1000,500,0:30\" puts that UCS on every new VM "
     "and on each again before every run(); a test's own set_ucs wins -- "
     "set_ucs() for World is the opt-out; a spec that does not parse is "
     "refused", CONTRACT)
def _w3():
    vm = sweep('1000,500,0:30')
    got = [ev(vm, '(getvar "WORLDUCS")'),
           ev(vm, "(trans '(10.0 20.0 0.0) 1 0)")]
    ok = got[0] == 0 and near(got[1], u2w([10.0, 20.0, 0.0]))
    # a run that finds the UCS knocked back to World puts it on again
    vm.loads('(defun c:t:org () (getvar "UCSORG"))')
    vm.sysvars['UCSORG'] = [0.0, 0.0, 0.0]
    vm.sysvars['UCSXDIR'] = [1.0, 0.0, 0.0]
    vm.sysvars['UCSYDIR'] = [0.0, 1.0, 0.0]
    ran = vm.run('c:t:org', [])
    ok = ok and near(ran, list(O))
    own = sweep('1000,500,0:30')
    own.set_ucs((5.0, 0.0, 0.0), 0.0)
    own.loads('(defun c:t:org () (getvar "UCSORG"))')
    kept = own.run('c:t:org', [])
    ok = ok and near(kept, [5.0, 0.0, 0.0])
    # ...World included: set_ucs() is how a test that means World opts out
    world = sweep('1000,500,0:30').set_ucs()
    world.loads('(defun c:t:w () (list (getvar "WORLDUCS") '
                '(trans \'(1.0 2.0 0.0) 1 0)))')
    ok = ok and world.run('c:t:w', []) == [1, [1.0, 2.0, 0.0]]
    bad = []
    for spec in ('1000,500', '1000,500,0:thirty', 'x'):
        try:
            sweep(spec)
            bad.append(spec)
        except ValueError:
            pass
    return ok and not bad, (got, ran, kept, bad)


@pin('W4', "LISPVM_UCS_CLICKS=placed: a scripted click is the World spot "
     "the test meant, handed to the routine as its UCS numbers -- "
     "getpoint, getcorner and entsel's point alike -- VIEWCTR is "
     "reported in the UCS, and vm.commands logs a command's points in "
     "World numbers; a test's own set_ucs scripts UCS numbers again",
     GETPOINT_DOC + '; ' + VIEWCTR_DOC + '; ' + CONTRACT)
def _w4():
    vm = sweep('1000,500,0:30', 'placed')
    line = ent(vm, '(entmake (list \'(0 . "LINE") \'(8 . "0") '
               '\'(10 0.0 0.0 0.0) \'(11 1.0 0.0 0.0)))')
    vm.script = [[10.0, 20.0, 0.0], [30.0, 40.0, 0.0],
                 [line, [5.0, 6.0, 0.0]], None]
    got = ev(vm, '(list (getpoint) (getcorner \'(0.0 0.0 0.0)) (entsel) '
                 '(getpoint) (getvar "VIEWCTR"))')
    ok = (near(got[0], w2u([10.0, 20.0, 0.0]))
          and near(got[1], w2u([30.0, 40.0, 0.0]))
          and got[2][0] is line and near(got[2][1], w2u([5.0, 6.0, 0.0]))
          and got[3] is NIL and near(got[4], w2u([0.0, 0.0, 0.0])))
    # the routine hands a command the UCS numbers of a World spot; the
    # test reads the spot back, and the DIMENSION is drawn on it
    vm.globals[Sym('t:p')] = w2u([100.0, 0.0, 0.0])
    ev(vm, '(command "_.DIMALIGNED" \'(0.0 0.0 0.0) t:p)')
    logged = vm.commands[-1]
    dim = vm.entities[-1]
    ok = (ok and near(logged[2], [100.0, 0.0, 0.0])
          and near(logged[1], u2w([0.0, 0.0, 0.0]))
          and near(grp(vm, dim, 14), [100.0, 0.0, 0.0]))
    own = sweep('1000,500,0:30', 'placed')
    own.set_ucs((5.0, 0.0, 0.0), 0.0)
    own.script = [[10.0, 20.0, 0.0]]
    mine = ev(own, '(getpoint)')
    return ok and mine == [10.0, 20.0, 0.0], (got, mine)


def main():
    fails = []
    for pid, rule, source, fn in PINS:
        try:
            ok, detail = fn()
        except Exception as x:          # a pin must report, never crash
            ok, detail = False, 'raised %s: %s' % (
                type(x).__name__, str(x).splitlines()[0])
        print('  %-4s %-4s %s' % ('ok' if ok else 'FAIL', pid, rule))
        if not ok:
            print('            got: %r' % (detail,))
            print('            source: %s' % source)
            fails.append(pid)
    if fails:
        print('\n%d of %d UCS pins FAILED: %s'
              % (len(fails), len(PINS), ' '.join(fails)))
        sys.exit(1)
    print('\nALL %d UCS PINS PASSED' % len(PINS))


if __name__ == '__main__':
    main()
