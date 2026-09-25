#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""POOL, SPA and POOLSIDE under a UCS: the drawing stays on its dims.

All three build every point as tool-local numbers plus the base point
the drafter picked -- and a pick is a UCS point.  pool:wp (spa:wp,
psd:wp) handed that one sum both to (command ...), which reads it in
the UCS, and to entmake / entmod, which read it as WORLD numbers.  With
a UCS moved to the site's corner the outline, the section and the
corner-mark circles landed at the raw numbers -- a UCS-origin away from
the dimensions, which went where they belonged -- and with the UCS
turned the outline lay along World X while the dims ran along the UCS.
SPACHECK then found faults in a SPA drawing nobody had planted.

Now the entity data goes through pool:ww / spa:ww / psd:ww, the same
point trans'd from the UCS to the World, and the angles an entity keeps
in World terms (an ARC's 50/51, a TEXT's 50, an ELLIPSE's major axis,
a hinge label's direction) are turned by the UCS too.  The points
handed to (command ...) are untouched: they stay UCS numbers.

The test that says it all is the same run twice -- once in World, once
under a UCS moved to (1000,500) and turned 30 degrees, with the same
answers (clicks are UCS numbers, as getpoint's are).  Carried back into
the UCS, the second drawing has to BE the first, entity by entity and
group by group, dimensions and their measurements included; and the
(command ...) calls have to be word for word the same, because a
command reads the UCS.  Each tool's runs, and the tutorials and demo
that draw through their helpers, are checked that way, and a few facts
are checked by name besides (a corner mark's pick lies on its own
circle, a section's _H dim measures its own waterline).

TUTORIALSPA's reference sheet is here too: it placed its text through
spa:textc, which adds spa:*base* -- and that still held the last SPA
run's insertion point, so the sheet landed that far from the pick.

Only a PLAN UCS can be carried that way -- one whose Z is World +Z, so
it only moves and turns the plan.  An ARC's angles and an LWPOLYLINE's
bulges run counter-clockwise about a 210 left at World +Z, so in a UCS
whose Z points down every corner arc came out mirrored off its corner
(and the labels read backwards), and in a tilted one the entity data
left the plane the dims are on.  All six commands now refuse both, the
way OASIS refuses a tilted one: they say why, ask nothing, draw
nothing, touch no setting, and let go of a form or POOLCOVER's flag.

How the old code was shown to fail: UCSFIX_OLD=<dir> loads POOL.LSP,
POOLDEMO.LSP, TUTORIALPOOL.LSP, SPA.LSP, TUTORIALSPA.LSP and
POOLSIDE.lsp from DIR instead (a directory of `git show HEAD:<path>`
copies).  There every drawing comparison fails, and so does every
named geometry, colour and sheet check, and every refusal check but
one.  Some checks pass on both versions by design.  The command-log
identity checks do, because a command reads the UCS and the command
sites were never changed.  So do the three that read only the dims or
the entity types (the _H dim measures 480, the dims sit on the lifted
plane, the out-of-round pool and its guide are ellipses), and
TUTORIALSPA's settings check, since its old run asked its first
question before it borrowed anything.  The old runs of the refusal
checks go on to ask (the empty script ends them there) or, POOLDEMO's,
die in a DIMLINEAR the VM will not draw off the World plan.  So their
settings and form checks fail there because the run was stopped, not
because AutoCAD would have left those things behind.  What they prove
is the new refusal's own tidiness.

Run: python3 tests/test_ucsfix_poolspa.py
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from lispvm import VM, LispError, Dot, Ent  # noqa: E402

OLD = os.environ.get('UCSFIX_OLD')


def src(*parts):
    """A tool file: the tree's, or the same name under UCSFIX_OLD."""
    if OLD:
        return os.path.join(OLD, parts[-1])
    return os.path.join(REPO, 'lisp', *parts)


POOL = src('pool', 'POOL.LSP')
POOLDEMO = src('pool', 'POOLDEMO.LSP')
TUTPOOL = src('pool', 'TUTORIALPOOL.LSP')
SPA = src('spa', 'SPA.LSP')
TUTSPA = src('spa', 'TUTORIALSPA.LSP')
SIDE = src('poolside', 'POOLSIDE.lsp')

#: the UCS every run below is repeated under: the site's corner moved
#: to (1000,500) and the axes turned 30 degrees, as a drafter lines a
#: UCS up with a lot line
ORG = (1000.0, 500.0, 0.0)
TURN = math.radians(30.0)

BASE = (0.0, 0.0, 0.0)          # the insertion pick, in UCS numbers
TOL = 1e-6

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


# ------------------------------------------------------------ running

def fresh(files, ucs=None):
    """A VM with FILES loaded, on World -- or on UCS (origin, angle).
    vm.set_ucs is called either way, so the LISPVM_UCS sweep leaves the
    frame this test chose alone."""
    vm = VM()
    for f in files:
        vm.load(f)
    if ucs is None:
        vm.set_ucs()
    else:
        vm.set_ucs(ucs[0], ucs[1])
    return vm


def run(files, cmd, script, ucs=None, setup=None):
    vm = fresh(files, ucs)
    if setup:
        setup(vm)
    try:
        vm.run(cmd, list(script))
    except LispError as e:
        where = 'UCS' if ucs else 'World'
        raise AssertionError("[%s %s] %s" % (cmd, where, e)) from None
    return vm


# ------------------------------------------------------------ reading

def _kind(vm, e):
    return next((g.b for g in vm.entdata.get(e, [])
                 if isinstance(g, Dot) and g.a == 0), None)


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


#: groups that hold a DIRECTION rather than a point, by entity type:
#: they turn with the UCS but do not move with its origin
_DIRECTIONS = {'ELLIPSE': {11}, 'MTEXT': {11}}
#: groups that hold an angle measured from World X in the entity's
#: plane, by entity type
_ANGLES = {'ARC': {50, 51}, 'TEXT': {50}, 'MTEXT': {50},
           'DIMENSION': {50}}


def view(vm, turn):
    """Every entity the run made -- the erased guide included, as it was
    last left -- read back in the UCS: points through the UCS, the
    angles above less its turn, everything else as it is.  Two runs of
    one script, one in World and one under a UCS, have to read the
    same."""
    out = []
    for e in vm.entities:
        kind = _kind(vm, e)
        elev = next((g.b for g in vm.entdata[e]
                     if isinstance(g, Dot) and g.a == 38), 0.0)
        row = [kind, e in vm.deleted]
        for g in vm.entdata[e]:
            if isinstance(g, list) and g and isinstance(g[0], int):
                code, p = g[0], [float(c) for c in g[1:]]
                if code == 210:
                    continue            # the plan normal, the same in both
                if kind == 'LWPOLYLINE' and len(p) == 2:
                    p = p + [float(elev)]
                if code in _DIRECTIONS.get(kind, ()):
                    p = vm.wcs_to_ucs(p, disp=True)
                elif 10 <= code <= 16:
                    p = vm.wcs_to_ucs(p)
                row.append((code, tuple(p)))
            elif isinstance(g, Dot):
                if g.a in (5, 38) or isinstance(g.b, Ent):
                    continue            # the handle; the elevation, read above
                v = g.b
                if kind == 'DIMENSION' and g.a == 51 and _num(v):
                    # the UCS the dimension was made in (the negative of
                    # its turn), read in the UCS it is viewed in: 0 when
                    # the two are one, where a World dimension has none
                    v = (v + turn) % (2.0 * math.pi)
                    if min(v, 2.0 * math.pi - v) < TOL:
                        continue
                if g.a in _ANGLES.get(kind, ()) and _num(v):
                    v = (v - turn) % (2.0 * math.pi)
                    if abs(v - 2.0 * math.pi) < TOL:
                        v = 0.0
                row.append((g.a, v))
        out.append(row)
    return out


def _same(a, b):
    if _num(a) and _num(b):
        return abs(a - b) <= TOL * max(1.0, abs(a), abs(b))
    if isinstance(a, (tuple, list)) and isinstance(b, (tuple, list)):
        return len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))
    return a == b


def differences(world, ucs):
    """Where two views part: (index, world row, ucs row), at most three."""
    out = []
    if len(world) != len(ucs):
        out.append(('count', len(world), len(ucs)))
    for i, (a, b) in enumerate(zip(world, ucs)):
        if not _same(a, b):
            out.append((i, a, b))
    return out[:3]


def cmdlog(vm):
    """The (command ...) calls, an entity named by where it stands in
    the drawing's list so two runs can be compared."""
    idx = {e: i for i, e in enumerate(vm.entities)}

    def norm(x):
        if isinstance(x, Ent):
            return ('<ent>', idx.get(x))
        if isinstance(x, list):
            return tuple(norm(y) for y in x)
        return x
    return [norm(c) for c in vm.commands]


def entities(vm, kind, layer=None, live=True):
    out = []
    for e in vm.entities:
        if live and e in vm.deleted:
            continue
        d = {}
        for g in vm.entdata[e]:
            if isinstance(g, Dot):
                d.setdefault(g.a, g.b)
            elif isinstance(g, list) and g:
                d.setdefault(g[0], g[1:])
        if d.get(0) == kind and (layer is None or d.get(8) == layer):
            d['__e'] = e
            out.append(d)
    return out


def same_drawing(label, files, cmd, script, setup=None):
    """The run in World and under the turned UCS: the same drawing read
    in the UCS, and the same (command ...) calls word for word."""
    try:
        w = run(files, cmd, script, None, setup)
        u = run(files, cmd, script, (ORG, TURN), setup)
    except AssertionError as e:
        check(label + ': both runs finish', False, str(e).splitlines()[0])
        return None, None
    diff = differences(view(w, 0.0), view(u, TURN))
    check(label + ': under a turned UCS the drawing is the World one, '
          'carried into the UCS', w.entities and not diff,
          repr(diff) if w.entities else 'nothing was drawn')
    cw, cu = cmdlog(w), cmdlog(u)
    check(label + ': ...and every command is handed the same UCS numbers',
          _same(cw, cu),
          repr(next(((a, b) for a, b in zip(cw, cu) if not _same(a, b)),
                    (len(cw), len(cu)))))
    return w, u


# ============================================================== POOL

POOLF = [POOL]


def pool_scenarios():
    print("POOL -- the plan, its dims and its guide under a UCS")
    # R1: in-square rectangle, square corners (90 marks on their own
    # circles), Normal hopper, the report table
    same_drawing('rectangle, square corners, hopper', POOLF, 'c:POOL',
                 ["Insquare", "Rectangle", BASE,
                  480.0, 240.0, "Square",
                  "Yes", "Normal",
                  60.0, 90.0, 240.0, 90.0,
                  60.0, 120.0, 60.0,
                  None])                  # no steps
    # radius corners: arcs on the outline and on the live guide (moved
    # by entmod as the answers come in), DIMRADIUS picking the arc
    w, u = same_drawing('out of square, radius corners', POOLF, 'c:POOL',
                        ["Outofsquare", "Rectangle", BASE,
                         240.0, 240.0, 240.0, 240.0,
                         "Radius", 24.0,
                         None, None, None, None, None, None,
                         "Ends", 340.0, 340.0, 340.0, 340.0,
                         "No", "No",
                         None])           # no step outside
    if u is not None:
        # the radius dims pick their arc ON it: the pick is a UCS point
        # the command reads, the arc is World data
        ok, bad = 0, []
        for c in u.commands:
            if not (c and c[0] == '_.DIMRADIUS'):
                continue
            ent, pick = [x for x in c if isinstance(x, list)
                         and len(x) == 2 and isinstance(x[0], Ent)][0]
            d = {g.a: g.b for g in u.entdata[ent] if isinstance(g, Dot)}
            cen = next(g[1:] for g in u.entdata[ent]
                       if isinstance(g, list) and g[0] == 10)
            at = u.ucs_to_wcs(pick)
            if abs(math.dist(at[:2], cen[:2]) - d[40]) < 1e-6:
                ok += 1
            else:
                bad.append((at, cen, d[40]))
        check('every radius dim is picked on its own arc', ok and not bad,
              repr(bad[:1]))
    # an oval: arcs whose angles have to turn with the UCS
    same_drawing('oval, radius NA, oval hopper', POOLF, 'c:POOL',
                 ["Insquare", "Oval", BASE,
                  360.0, 240.0, 480.0, "NA",
                  "Yes", "Normal",
                  70.0, 150.0, "NA", "NA", 110.0, 90.0,
                  None, 100.0, None, "NA",
                  None])                  # no steps
    # a step OUTSIDE the shallow end: the wall is read back off the
    # drawing (World data) against the flow's points (UCS), so a turned
    # UCS that lost the step would break the wall in the wrong place
    w, u = same_drawing('rectangle, no bottom, step outside', POOLF, 'c:POOL',
                        ["Insquare", "Rectangle", BASE,
                         480.0, 240.0, "Square",
                         "No",
                         "Yes", "Custom", 96.0, 36.0])
    if u is not None:
        check('the shallow wall is broken round the step',
              len(entities(u, 'LINE', 'POOL')) == 3 + 5,
              repr(len(entities(u, 'LINE', 'POOL'))))
    # round in square: a circle; out of round: an ELLIPSE whose major
    # axis is a World direction, on the plan and on the guide
    same_drawing('round, in square', POOLF, 'c:POOL',
                 ["Insquare", "ROU", BASE, 420.0,
                  "Yes", "Normal",
                  70.0, 150.0, "NA", "NA", 110.0, 90.0,
                  90.0, 240.0, 90.0, "NA",
                  None])                  # no steps
    w, u = same_drawing('round, out of round', POOLF, 'c:POOL',
                        ["Outofsquare", "ROU", BASE, 420.0, 300.0,
                         "No", None])     # no bottom, no step
    if u is not None:
        ells = entities(u, 'ELLIPSE', live=False)
        check('the out-of-round pool and its guide are ellipses',
              len(ells) >= 2, repr(len(ells)))
        axis = [u.wcs_to_ucs(d[11], disp=True) for d in ells]
        check('...each ellipse\'s major axis runs along a UCS axis',
              all(abs(a[0]) < 1e-9 or abs(a[1]) < 1e-9 for a in axis),
              repr(axis))
    # the notes TEXT reads level in the UCS
    if u is not None:
        txt = entities(u, 'TEXT', 'POOL-NOTES')
        check('the report text is turned with the UCS',
              txt and all(abs(d.get(50, 0.0) - TURN) < 1e-9 for d in txt),
              repr(sorted({round(d.get(50, 0.0), 6) for d in txt})))


def pooldemo_scenarios():
    print("POOLDEMO and TUTORIALPOOL -- they draw through POOL's helpers")
    # POOLDEMO's gate looks for pool:hopcalc in (atoms-family 0), which
    # the VM answers empty whatever is loaded (test_tutorialpool.py)
    def gate(vm):
        vm.loads("(defun atoms-family (n) (list 'pool:hopcalc))")
    same_drawing('POOLDEMO', [POOL, POOLDEMO], 'c:POOLDEMO', [],
                 setup=gate)
    w, u = same_drawing('TUTORIALPOOL', [POOL, TUTPOOL], 'c:TUTORIALPOOL',
                        [''] * 8)
    # topic 2's sample guide handed the guide-grey KNOB to setcol as it
    # stands -- 'auto, a role, not a colour -- so three lines carried
    # (62 . AUTO), a DXF group AutoCAD's entmod refuses
    if w is not None:
        bad = [g.b for e in w.entities for g in w.entdata[e]
               if isinstance(g, Dot) and g.a == 62
               and not (isinstance(g.b, int) and not isinstance(g.b, bool))]
        check('TUTORIALPOOL colours its sample guide with a colour number',
              not bad, repr(bad[:3]))
    # ...and a plain one.  Resolved through the guide's ink it was the
    # grey for the screen of whoever ran the tour -- 253 on a dark one
    # -- on three lines that stay in the drawing for everyone after
    def dark(vm):
        vm.env['CalofinTheme'] = 'DARK'
    try:
        d = run([POOL, TUTPOOL], 'c:TUTORIALPOOL', [''] * 8, None, dark)
    except AssertionError as e:
        check('TUTORIALPOOL runs on a dark screen', False,
              str(e).splitlines()[0])
    else:
        greys = [x.get(62) for x in entities(d, 'LINE', 'POOL-NOTES')
                 if x.get(62) not in (None, 1)]
        check('...ACI 8 whatever screen it is drawn on (not the ink grey)',
              greys == [8, 8, 8], repr(greys))


# =============================================================== SPA

SPAF = [SPA]


def spa_scenarios():
    print("SPA -- the outlines, the corner marks and the hinges under a UCS")
    # square corners: the 90 mark is a DIMRADIUS on its own circle
    w, u = same_drawing('square corners, one Typ. mark', SPAF, 'c:SPA',
                        [None, 'Coversize', 'Rectangle', BASE,
                         84.0, 60.0, 'Yes', '90', 'No', 'No'])
    if u is not None:
        circ = entities(u, 'CIRCLE', 'DIMENSION')
        call = [c for c in u.commands if c and c[0] == '_.DIMRADIUS']
        ok = False
        if len(circ) == 1 and call:
            on = [x[1] for x in call[0]
                  if isinstance(x, list) and len(x) == 2
                  and isinstance(x[0], Ent)][0]
            at = u.ucs_to_wcs(on)
            ok = abs(math.dist(at[:2], circ[0][10][:2])
                     - circ[0][40]) < 1e-6
        check('the corner mark is picked on its own circle', ok,
              repr((circ[:1], call[:1])))
        verts = [u.wcs_to_ucs(v + [0.0])
                 for d in entities(u, 'LWPOLYLINE', 'COVER')
                 for v in [g[1:] for g in u.entdata[d['__e']]
                           if isinstance(g, list) and g[0] == 10]]
        check('the cover is 84 x 60 along the UCS axes, at the pick',
              _same(sorted(tuple(round(c, 6) for c in v[:2])
                           for v in verts),
                    [(0.0, 0.0), (0.0, 60.0), (84.0, 0.0), (84.0, 60.0)]),
              repr(verts))
    # NotGiven: the boxed "?" on its circle and the leader
    same_drawing('a NotGiven corner', SPAF, 'c:SPA',
                 [None, 'Coversize', 'Rectangle', BASE,
                  84.0, 60.0,
                  'No', 'NotGiven', '90', '90', '90',
                  'No', 'No'])
    # radius corners on both outlines: bulges, the temporary arcs the
    # DIMRADIUS is hung on, and the overlap note moved by entmod
    same_drawing('radius corners, both outlines', SPAF, 'c:SPA',
                 [None, 'Coversize', 'Rectangle', BASE,
                  84.0, None, 'Yes', 'Radius', 8.0,
                  'No', 'Yes', 'Offset', 3.0])
    # out of round: the ELLIPSE's major axis turns
    same_drawing('round, out of round', SPAF, 'c:SPA',
                 [None, 'Coversize', 'ROund', BASE,
                  'Outofround', 84.0, 80.0, 'No', 'No'])
    # hinges: the MTEXT labels read up the UCS Y axis
    w, u = same_drawing('five-piece hinges', SPAF, 'c:SPA',
                        [None, 'Coversize', 'Rectangle', BASE,
                         230.0, 60.0, 'Yes', '90',
                         'Yes', 'No', 'No', '4-3'])
    if u is not None:
        labels = entities(u, 'MTEXT')
        check('the hinge labels read up the UCS Y axis',
              labels and all(_same(u.wcs_to_ucs(d[11], disp=True),
                                   [0.0, 1.0, 0.0]) for d in labels),
              repr([d.get(11) for d in labels][:2]))


def spa_raised():
    """A UCS whose origin is lifted off the World plan: the outline is
    one LWPOLYLINE, whose vertices are X and Y only -- its Z is the
    elevation, group 38, and it has to be the plane the dims are on."""
    print("SPA -- a UCS lifted 12\" off the World plan")
    try:
        u = run(SPAF, 'c:SPA',
                [None, 'Coversize', 'Rectangle', BASE,
                 84.0, 60.0, 'Yes', '90', 'No', 'No'],
                ((1000.0, 500.0, 12.0), TURN))
    except AssertionError as e:
        check('the run finishes', False, str(e).splitlines()[0])
        return
    pl = entities(u, 'LWPOLYLINE', 'COVER')
    check('the cover outline sits at the UCS plane\'s elevation',
          len(pl) == 1 and abs(pl[0].get(38, 0.0) - 12.0) < 1e-9,
          repr([d.get(38) for d in pl]))
    dims = entities(u, 'DIMENSION')
    check('...the plane its dimensions were drawn on',
          dims and all(abs(d[13][2] - 12.0) < 1e-9 for d in dims
                       if 13 in d),
          repr([d.get(13) for d in dims][:2]))


def tutspa_scenarios():
    print("TUTORIALSPA -- the demo and the reference sheet")
    same_drawing('TUTORIALSPA demo', [SPA, TUTSPA], 'c:TUTORIALSPA',
                 ['Demo', BASE] + [''] * 8)

    # the reference sheet goes where it is put, whatever the last SPA
    # run left in spa:*base*
    def stale(vm):
        vm.loads('(setq spa:*base* (list 500.0 300.0))')
    for ucs, where in ((None, 'World'), ((ORG, TURN), 'a turned UCS')):
        try:
            vm = run([SPA, TUTSPA], 'c:TUTORIALSPA',
                     ['Checks', (100.0, 100.0, 0.0)], ucs, stale)
        except AssertionError as e:
            check('the sheet run finishes (%s)' % where, False,
                  str(e).splitlines()[0])
            continue
        head = [d for d in entities(vm, 'TEXT', 'SPA-NOTES')
                if 'REFERENCE' in str(d.get(1))]
        at = vm.wcs_to_ucs(head[0][10]) if head else None
        check('the reference sheet lands at the pick, not the last '
              'SPA base (%s)' % where,
              at is not None and _same(at[:2], [100.0, 100.0]), repr(at))


# ========================================================== POOLSIDE

SIDEF = [SIDE]


def poolside_scenarios():
    print("POOLSIDE -- the section and its _H / _V dims under a UCS")
    script = ["Normal", BASE,
              480.0,
              60.0, 90.0, 240.0, 90.0,
              42.0, 96.0,
              "No"]
    w, u = same_drawing('Normal hopper section', SIDEF, 'c:POOLSIDE',
                        script)
    if u is not None:
        # the waterline is the section's top edge, B long, along UCS X
        segs = [(u.wcs_to_ucs(d[10]), u.wcs_to_ucs(d[11]))
                for d in entities(u, 'LINE', 'POOL')]
        top = [s for s in segs
               if abs(s[0][1]) < 1e-6 and abs(s[1][1]) < 1e-6
               and abs(abs(s[1][0] - s[0][0]) - 480.0) < 1e-6]
        check('the waterline runs 40\' along the UCS X axis from the pick',
              len(top) == 1, repr(segs[:3]))
        # and the B dimension that measures it reads 480
        meas = [d.get(42) for d in entities(u, 'DIMENSION')]
        check('...and a _H dim measures it 480, as in World',
              any(m is not None and abs(m - 480.0) < 1e-6 for m in meas),
              repr(meas))


# ================================================== not a plan UCS

#: the two kinds of UCS nothing here can be laid out in, both at the
#: site's corner: Y picked clockwise of X (Z points down), and the
#: plan tipped 45 degrees about X
_C, _S = math.cos(TURN), math.sin(TURN)
NOT_PLAN = (
    ('upside-down', dict(xdir=(_C, _S, 0.0), ydir=(_S, -_C, 0.0))),
    ('tilted', dict(xdir=(1.0, 0.0, 0.0),
                    ydir=(0.0, math.sqrt(0.5), math.sqrt(0.5)))),
)
#: what a refused run must leave as it found it
_KEPT = {'OSMODE': 39, 'CLAYER': '0', 'LUNITS': 2, 'CMDECHO': 1,
         'AUNITS': 0, 'ANGBASE': 0.0, 'ANGDIR': 0}


def refused(label, files, cmd, frame, before=None, after=None):
    """CMD under the non-plan UCS FRAME: it finishes, says why, asks
    nothing, calls no command, draws nothing and leaves every setting
    it would have borrowed alone.  BEFORE(vm) arms something the run is
    handed (a form, a flag); AFTER(vm) is (label, ok, detail) for what
    must be let go of."""
    vm = VM()
    for f in files:
        vm.load(f)
    vm.set_ucs(ORG, **frame)
    vm.loads("(defun atoms-family (n) (list 'pool:hopcalc))")  # POOLDEMO
    for k, v in _KEPT.items():
        vm.sysvars[k] = v
    if before:
        before(vm)
    err = None
    try:
        vm.run(cmd, [])
    except Exception as e:              # a NotModelled DIMLINEAR included
        err = '%s: %s' % (type(e).__name__, str(e).splitlines()[0])
    said = ''.join(vm.printed)
    check(label + ': refused -- says why, asks, calls and draws nothing',
          err is None and not vm.entities and not vm.commands
          and not vm.prompts and 'tilted or upside down' in said,
          err or repr((len(vm.entities), vm.commands[:2], vm.prompts[:2])))
    moved = {k: vm.sysvars.get(k) for k in _KEPT
             if vm.sysvars.get(k) != _KEPT[k]}
    check(label + ': ...and every setting is as it was', not moved,
          repr(moved))
    if after:
        what, ok, detail = after(vm)
        check(label + ': ...' + what, ok, detail)


def not_plan_scenarios():
    print("Not a plan UCS -- upside down or tilted, every command refuses")

    def glob(vm, name):
        return vm.globals.get(name)

    def form(name, src):
        return lambda vm: vm.loads('(setq %s %s)' % (name, src))

    for kind, frame in NOT_PLAN:
        refused('POOL, %s' % kind, [POOL], 'c:POOL', frame,
                form('pool:*form*', "(list (cons 'shape \"Oval\"))"),
                lambda vm: ('its form is let go of',
                            not glob(vm, 'pool:*form*'),
                            repr(glob(vm, 'pool:*form*'))))
        refused('POOLCOVER, %s' % kind, [POOL], 'c:POOLCOVER', frame,
                None,
                lambda vm: ('the no-bottom flag does not outlive it',
                            not glob(vm, 'pool:*nobottom*'),
                            repr(glob(vm, 'pool:*nobottom*'))))
        refused('POOLDEMO, %s' % kind, [POOL, POOLDEMO], 'c:POOLDEMO',
                frame)
        refused('TUTORIALPOOL, %s' % kind, [POOL, TUTPOOL],
                'c:TUTORIALPOOL', frame)
        refused('SPA, %s' % kind, [SPA], 'c:SPA', frame,
                form('spa:*form*', "(list (cons 'shape \"ROund\"))"),
                lambda vm: ('its form is let go of',
                            not glob(vm, 'spa:*form*'),
                            repr(glob(vm, 'spa:*form*'))))
        refused('TUTORIALSPA, %s' % kind, [SPA, TUTSPA], 'c:TUTORIALSPA',
                frame)
        refused('POOLSIDE, %s' % kind, [SIDE], 'c:POOLSIDE', frame,
                form('psd:*form*', "(list (cons 'b 480.0))"),
                lambda vm: ('its form is let go of',
                            not glob(vm, 'psd:*form*'),
                            repr(glob(vm, 'psd:*form*'))))


def main():
    print("UCS: POOL, SPA and POOLSIDE draw where their dimensions are%s"
          % ('  [OLD: %s]' % OLD if OLD else ''))
    pool_scenarios()
    pooldemo_scenarios()
    spa_scenarios()
    spa_raised()
    tutspa_scenarios()
    poolside_scenarios()
    not_plan_scenarios()
    print()
    if FAILS:
        print("%d FAILED: %s" % (len(FAILS), "; ".join(FAILS)))
        sys.exit(1)
    print("all UCS checks passed")


if __name__ == '__main__':
    main()
