"""The knobs at the top of the three step files, and what the routines
do when the drawing does not cooperate.

Two halves, and they are here together because they are the same claim:
a setting is only a setting if changing it changes the drawing and
mistyping it does not break the run.

THE KNOBS.  CORNERSTP, HEMISTEP and NORMIESTEP share one set of *cs-
settings, each defined only if it is not already set so load order does
not matter.  Every one of them is initialised in the SETTINGS block at
the top of the file and read through a ...-num guard further down, and
that means the same number is written twice.  So the first three tests
read both copies out of the source and hold them together:

  * every knob the block defines is read somewhere in that file, and
    every *cs- name the file reads is a knob the block defines - a knob
    added to the block and never wired up, or a global read that
    nothing defines (AutoLISP answers nil and the run quietly changes),
    fails here;
  * the fallback in each reader is the value the block sets;
  * the shared knobs carry the same default in all three files.

Then the behaviour: a knob set to nonsense draws exactly what the
default draws, and a knob set to a real value moves the drawing.

THE CONTINGENCIES.  The paths a run takes when something is missing:
UNDO switched off in the drawing, the dim styles absent, a dim layer
that cannot be drawn on, the current layer frozen, AUTOBEAD not loaded,
and selections that cannot be made into a run.  The undo one is why
this file exists: all six commands opened their undo group only when
UNDOCTL said undo was recording, and closed it unconditionally, so in a
drawing with UNDO off every one of them ended on _End with no group
open.

Run against the grouped tier with:
    CALOFIN_LISP_ROOT=shared python3 tests/test_steps_settings.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from callib import strip  # noqa: E402
from lispvm import VM, Dot, LispError, parse_all  # noqa: E402

HERE = os.path.dirname(__file__)
CORNERSTP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'CORNERSTP.lsp')
HEMISTEP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'HEMISTEP.lsp')
NORMIESTEP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'NORMIESTEP.lsp')

FILES = (('CORNERSTP', CORNERSTP, 'cs'),
         ('HEMISTEP', HEMISTEP, 'hs'),
         ('NORMIESTEP', NORMIESTEP, 'ns'))

#: globals under the *cs- name that are not settings
NOT_A_KNOB = {'*cs-version*', '*cs-form*'}

#: the pick and the numbers the profile scripts feed, as in
#: test_cornerstp_profile.py
PICK = (500.0, 400.0)
DEPTHS = [7.5, 10.75, 10.75, 10.5]     # 3 steps -> 4 depths

KNOB = re.compile(r"\(if\s+\(not\s+\(boundp\s+'(\*cs-[\w-]+\*)\)\)\s*"
                  r"\(setq\s+\1\s+([^)]*)\)\)")
READER = re.compile(r"\((?:cs|hs|ns)-num\s+(\*cs-[\w-]+\*)\s+")
REFERENCE = re.compile(r"\*cs-[\w-]+\*")


def argument_at(src, i):
    """The whole second argument of a reader call starting at I - a
    literal, or a form with its parens balanced ((* 4.0 tol), which a
    plain [^)]* would cut in half)."""
    if src[i] != "(":
        j = i
        while j < len(src) and src[j] not in " \t\r\n()":
            j += 1
        return src[i:j]
    depth, j = 0, i
    while j < len(src):
        if src[j] == "(":
            depth += 1
        elif src[j] == ")":
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
        j += 1
    return src[i:]


# ------------------------------------------------------------------ text

def source(path):
    """The file at the tier under test - the shared twin when
    CALOFIN_LISP_ROOT says so, exactly as the VM reads it."""
    root = os.environ.get('CALOFIN_LISP_ROOT')
    if root:
        parts = os.path.abspath(path).split(os.sep)
        repo = os.sep.join(parts[:parts.index('lisp')])
        for base in (os.path.join(repo, root, 'parts'),
                     os.path.join(repo, root)):
            cand = os.path.join(base, os.path.basename(path))
            if os.path.exists(cand):
                path = cand
                break
    with open(path) as fh:
        return fh.read()


def code(path):
    """...with the comments taken out, and string contents blanked -
    for counting what the CODE reads, so a knob named in a comment does
    not read as wired up."""
    clean, _ = strip(source(path))
    return clean


def _isnum(text):
    try:
        float(text)
        return True
    except ValueError:
        return False


def knobs(path):
    """{setting: the value the SETTINGS block initialises it to}."""
    return dict(KNOB.findall(source(path)))


def fallbacks(path):
    """{setting: the default its reader falls back to}, as source text."""
    src = source(path)
    return {m.group(1): argument_at(src, m.end())
            for m in READER.finditer(src)}


def test_every_knob_is_read_and_every_read_is_a_knob():
    for name, path, _pre in FILES:
        src = code(path)
        defined = knobs(path)
        assert defined, "%s: no settings found at all" % name
        for knob in defined:
            # twice in the block itself (boundp + setq); a third
            # mention is the code that reads it
            assert src.count(knob) > 2, \
                "%s: %s is defined at the top and never read" % (name, knob)
        for ref in set(REFERENCE.findall(src)) - NOT_A_KNOB:
            assert ref in defined, \
                ("%s reads %s, which no SETTINGS block in it defines - "
                 "AutoLISP would answer nil and the run would quietly "
                 "change" % (name, ref))
    print("every knob is read, and every *cs- read is a knob")


def test_each_reader_falls_back_to_the_value_the_block_sets():
    seen = 0
    for name, path, _pre in FILES:
        defined = knobs(path)
        for knob, dflt in fallbacks(path).items():
            assert knob in defined, \
                "%s: a reader guards %s, which nothing defines" % (name, knob)
            block = defined[knob]
            if block == "nil":
                # a knob whose default is computed says so by being nil
                # at the top; its reader is what computes it
                assert dflt.startswith("("), \
                    ("%s: %s is nil at the top, which means the reader "
                     "derives it, but the reader just says %s"
                     % (name, knob, dflt))
            else:
                assert _isnum(block), \
                    ("%s: %s is set to %s at the top, which is not a number, "
                     "but its reader guards it as one" % (name, knob, block))
                assert float(dflt) == float(block), \
                    ("%s: %s is set to %s at the top but its reader falls "
                     "back to %s - a mistyped setting would draw neither"
                     % (name, knob, block, dflt))
            seen += 1
    assert seen >= 12, "only %d guarded settings found" % seen
    print("every reader falls back to the value its settings block sets")


def test_the_shared_knobs_agree_across_the_three_files():
    """The three routines share one set of settings, so a knob two of
    them define has to be the same knob."""
    everywhere = {}
    for name, path, _pre in FILES:
        for knob, dflt in knobs(path).items():
            everywhere.setdefault(knob, {})[name] = dflt
    shared = {k: v for k, v in everywhere.items() if len(v) > 1}
    assert len(shared) >= 8, "only %d shared settings" % len(shared)
    for knob, per_file in shared.items():
        assert len(set(per_file.values())) == 1, \
            ("%s defaults differently per file: %s - whichever file loads "
             "first would win" % (knob, per_file))
    print("the %d shared knobs carry one default across the three files"
          % len(shared))


# ------------------------------------------------------------------ runs

def fresh(path, styles=('STANDARD INCHES', 'SIDE STANDARD'), setup=()):
    vm = VM()
    vm.load(path)                       # CALOFIN_LISP_ROOT picks the tier
    for s in styles:
        vm.tables['DIMSTYLE'].add(s)
    # a drawing scaled the way the shop's are: DIMTXT 1/8" at 1/4"=1'
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48.0
    for form in setup:
        vm.loads(form)
    return vm


def walls(vm, pair=True):
    vm.loads('(entmake (list (cons 0 "LINE")'
             ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
    if pair:
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 0.0 0.0) (list 11 0.0 200.0 0.0)))')
    return list(vm.entities)


def run(path, cmd, script, label, setup=(), styles=('STANDARD INCHES',
                                                    'SIDE STANDARD'),
        sysvars=(), loose=False):
    vm = fresh(path, styles, setup)
    for var, val in sysvars:
        vm.sysvars[var] = val
    script = list(script)
    if script and script[0] == 'WALLS':
        script[0] = walls(vm, pair=(cmd == 'c:CORNERSTP'))
    try:
        if loose:
            # the tutorials pause a page at a time and the count is
            # theirs to change; a generous script and the balance check
            # by hand says what run() would, without pinning the pages
            vm.script = script
            vm.prompts = []
            vm.eval(parse_all('(%s)' % cmd)[0])
            assert vm.undo_groups == 0, \
                "[%s] %d undo group(s) left open" % (label, vm.undo_groups)
        else:
            vm.run(cmd, [None] + script)
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None
    return vm


def cornerstp_script(dims="No", tread=24.0, width=None):
    """walls -> inside out -> dims? -> no bench -> three steps -> done
    -> a side profile -> four depths -> the pick."""
    return (['WALLS', None, dims, "No"]
            + [tread, width] * 3
            + [None, "Yes"] + DEPTHS + [PICK])


def hemistep_script(dims="No"):
    return (['WALLS', (100.0, 50.0), dims, 60.0]
            + [24.0, 60.0] * 3 + [None, None, "Yes"] + DEPTHS + [PICK])


def normiestep_script(dims="No"):
    return (['WALLS', (100.0, 50.0), 60.0, "Square", dims,
             24.0, 24.0, 24.0, None, "Yes"] + DEPTHS + [PICK])


SCRIPT = {'c:CORNERSTP': (CORNERSTP, cornerstp_script),
          'c:HEMISTEP': (HEMISTEP, hemistep_script),
          'c:NORMIESTEP': (NORMIESTEP, normiestep_script)}


def said(vm):
    return "".join(str(x) for x in vm.printed)


def geometry(vm):
    """Every line and dimension in the drawing, as comparable tuples."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        kind = None
        for g in data:
            if isinstance(g, Dot) and g.a == 0:
                kind = g.b
        pts = tuple(tuple(round(float(v), 9) for v in g[1:3])
                    for g in data if isinstance(g, list) and g
                    and g[0] in (10, 11, 13, 14))
        out.append((kind, pts))
    return out


def dim_points(vm):
    """The dimension-line point of every dim placed, in order."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        if not any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
                   for g in data):
            continue
        for g in data:
            if isinstance(g, list) and g and g[0] == 10:
                out.append((round(float(g[1]), 9), round(float(g[2]), 9)))
    return out


# ------------------------------------------------- the knobs, at work

def test_a_knob_set_to_nonsense_draws_the_default():
    """The guard is the whole reason a setting can be a plain global: a
    string where a number belongs costs the shipped behaviour and
    nothing else."""
    for cmd, (path, script) in SCRIPT.items():
        base = geometry(run(path, cmd, script("Yes"), cmd + " default"))
        for knob in sorted(knobs(path)):
            junk = run(path, cmd, script("Yes"), "%s %s" % (cmd, knob),
                       setup=('(setq %s "not a number")' % knob,))
            assert geometry(junk) == base, \
                ("%s: %s set to a string changed the drawing - the reader "
                 "is not guarding it" % (cmd, knob))
        # and setting one to the value it already has changes nothing
        explicit = ['(setq %s %s)' % (k, v) for k, v in knobs(path).items()]
        same = run(path, cmd, script("Yes"), cmd + " explicit",
                   setup=tuple(explicit))
        assert geometry(same) == base, \
            "%s: setting every knob to its own default changed the drawing" % cmd
    print("a knob set to nonsense - or to its own default - draws the default")


def test_the_standoff_knobs_move_the_dims():
    for cmd, (path, script) in SCRIPT.items():
        base = dim_points(run(path, cmd, script("Yes"), cmd + " base"))
        wide = dim_points(run(path, cmd, script("Yes"), cmd + " wide",
                              setup=('(setq *cs-dim-offset* 4.0)',)))
        assert len(base) == len(wide) and base != wide, \
            "%s: doubling *cs-dim-offset* left every dim where it was" % cmd
        nested = dim_points(run(path, cmd, script("Yes"), cmd + " nested",
                                setup=('(setq *cs-dim-nest* 6.0)',)))
        assert len(base) == len(nested) and base != nested, \
            "%s: *cs-dim-nest* left every dim where it was" % cmd
    # CORNERSTP's tread chain also clears a fraction of the step's own
    # width, and that fraction is a knob of its own
    fat = dim_points(run(CORNERSTP, 'c:CORNERSTP', cornerstp_script("Yes"),
                         "chain-frac", setup=('(setq *cs-chain-frac* 2.0)',)))
    plain = dim_points(run(CORNERSTP, 'c:CORNERSTP', cornerstp_script("Yes"),
                           "chain-frac base"))
    assert fat != plain, "*cs-chain-frac* left the tread chain where it was"
    print("the standoff knobs move the dims they are named for")


def test_the_tolerance_knob_decides_what_snaps():
    """At 24 along the bisector of a square corner the wall opening is
    48.  A width half an inch off that is held and breaks the walls at
    1/8" tolerance, and snaps to them at a bigger one."""
    held = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(width=48.5),
               "tol default")
    assert "held" in said(held) and "breaks from the walls" in said(held), \
        said(held)[:400]
    snapped = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(width=48.5),
                  "tol raised", setup=('(setq *cs-tol-inch* 1.0)',))
    assert "fitted to walls" in said(snapped), said(snapped)[:400]
    assert geometry(held) != geometry(snapped)
    # the same, said the other way: the tolerance in drawing units wins
    # over the inches it would otherwise be derived from
    direct = run(CORNERSTP, 'c:CORNERSTP', cornerstp_script(width=48.5),
                 "tol direct", setup=('(setq *cs-width-tol* 1.0)',))
    assert geometry(direct) == geometry(snapped)
    print("*cs-tol-inch* and *cs-width-tol* decide what snaps to the walls")


def test_the_parallel_knob_decides_when_it_warns():
    """Two walls half a degree apart: the default warns at one degree,
    and a tighter setting keeps quiet."""
    def near_parallel(setup=()):
        vm = fresh(CORNERSTP, setup=setup)
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
        far = 200.0 * math.tan(math.radians(0.5))
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 20.0 0.0) (list 11 200.0 %r 0.0)))'
                 % (20.0 + far))
        vm.run('c:CORNERSTP', [None, list(vm.entities), None, "No", "No",
                               None])
        return said(vm)
    assert "nearly parallel" in near_parallel(), "no warning at half a degree"
    quiet = near_parallel(('(setq *cs-parallel-tol* 0.1)',))
    assert "nearly parallel" not in quiet, quiet[:400]
    print("*cs-parallel-tol* decides when nearly-parallel walls are called out")


def u_outline(vm, gap=0.0):
    """A U: base (0,0)-(120,0) with an arm up from each end, the second
    arm standing GAP away from the base's end."""
    for a, b in (((0.0, 0.0), (120.0, 0.0)),
                 ((0.0, 0.0), (0.0, 100.0)),
                 ((120.0 + gap, 0.0), (120.0 + gap, 100.0))):
        vm.loads('(entmake (list (cons 0 "LINE") (list 10 %r %r 0.0)'
                 ' (list 11 %r %r 0.0)))' % (a[0], a[1], b[0], b[1]))
    return list(vm.entities)


def test_the_join_fuzz_knob_reads_a_sloppy_u():
    """Ends 0.6 apart are two loose ends at the default fuzz (four
    times the 1/8" tolerance) and one joint at a bigger one."""
    script = ["Square", "No", 24.0, 24.0, None, "No"]

    def u_run(gap, setup=()):
        vm = fresh(NORMIESTEP, setup=setup)
        vm.handle_errors = True         # a refused U exits through *error*
        ents = u_outline(vm, gap)
        vm.run('c:NORMIESTEP', [None, ents] + script)
        return vm

    tight = u_run(0.0)
    assert "step(s) drawn" in said(tight), said(tight)[:400]
    loose = u_run(0.6)
    assert "do not form a U" in said(loose), said(loose)[:400]
    forgiving = u_run(0.6, ('(setq *cs-join-fuzz* 1.0)',))
    assert "do not form a U" not in said(forgiving), said(forgiving)[:400]
    assert "step(s) drawn" in said(forgiving), said(forgiving)[:400]
    print("*cs-join-fuzz* decides whether a hand-traced U reads as one outline")


# ------------------------------------------------- the contingencies

def test_a_drawing_with_undo_off_still_runs():
    """UNDOCTL bit 1 clear is undo switched off for the drawing: no
    group can be opened, so none may be closed.  Every one of the six
    commands opened its group conditionally and closed it flat until
    v4.1/v3.13/v3.7, which ended each run on _End with no group open."""
    off = (('UNDOCTL', 4),)
    for cmd, (path, script) in SCRIPT.items():
        vm = run(path, cmd, script(), cmd + " with undo off", sysvars=off)
        assert "step(s) drawn" in said(vm), said(vm)[:400]
        assert vm.undo_log == [], \
            "%s touched the undo stack with undo off: %s" % (cmd, vm.undo_log)
    for cmd, path in (('c:TUTORIALCORNERSTP', CORNERSTP),
                      ('c:TUTORIALHEMISTEP', HEMISTEP),
                      ('c:TUTORIALNORMIESTEP', NORMIESTEP)):
        vm = run(path, cmd, [None, None, None, "Yes", (0.0, 0.0)] + [None] * 20,
                 cmd + " with undo off", sysvars=off, loose=True)
        assert "Done" in said(vm), said(vm)[-400:]
    # and with undo recording, the group is opened and closed once
    for cmd, (path, script) in SCRIPT.items():
        vm = run(path, cmd, script(), cmd + " with undo on")
        assert vm.commands.count(['_.UNDO', '_Begin']) == 1, cmd
        assert vm.commands.count(['_.UNDO', '_End']) == 1, cmd
    print("a drawing with UNDO off runs to the end, and touches no group")


def test_missing_dim_styles_are_reported_and_the_dims_still_land():
    for cmd, (path, script) in SCRIPT.items():
        vm = run(path, cmd, script("Yes"), cmd + " with no styles", styles=())
        for style in ('STANDARD INCHES', 'SIDE STANDARD'):
            assert '"%s" not found' % style in said(vm), said(vm)[:400]
        assert dim_points(vm), "%s: no dims placed at all" % cmd
        assert vm.dimstyle_log == [], \
            "%s made a style current that the drawing has not got" % cmd
    print("missing dim styles are reported, and the dims land in the current one")


def test_an_unusable_dim_layer_falls_back_to_the_current_one():
    off_layer = ('(entmake (list (cons 0 "LAYER")'
                 ' (cons 100 "AcDbSymbolTableRecord")'
                 ' (cons 100 "AcDbLayerTableRecord") (cons 2 "DIMS-OFF")'
                 ' (cons 70 0) (cons 62 -2) (cons 6 "Continuous")))',)
    for cmd, (path, script) in SCRIPT.items():
        for setup, why in (
                (('(setq *cs-dim-layer* "NO-SUCH-LAYER")',), "missing"),
                (off_layer + ('(setq *cs-dim-layer* "DIMS-OFF")',), "off")):
            vm = run(path, cmd, script("Yes"), "%s dim layer %s" % (cmd, why),
                     setup=setup)
            assert "not drawable" in said(vm), said(vm)[:400]
            for e in vm.entities:
                if any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
                       for g in vm.entdata.get(e, [])):
                    assert vm.layer_of(e) == '0', \
                        "%s put a dim on %r" % (cmd, vm.layer_of(e))
    print("a dim layer that cannot be drawn on is reported and stepped around")


def test_a_frozen_current_layer_is_called_out():
    frozen = ('(entmake (list (cons 0 "LAYER")'
              ' (cons 100 "AcDbSymbolTableRecord")'
              ' (cons 100 "AcDbLayerTableRecord") (cons 2 "ICED")'
              ' (cons 70 1) (cons 62 7) (cons 6 "Continuous")))',
              '(setvar "CLAYER" "ICED")')
    for cmd, (path, script) in SCRIPT.items():
        vm = run(path, cmd, script(), cmd + " on a frozen layer", setup=frozen)
        assert "off, frozen or locked" in said(vm), said(vm)[:400]
    print("a frozen current layer is called out before anything is drawn")


def test_autobead_absent_is_said_not_crashed():
    for cmd, (path, script) in SCRIPT.items():
        vm = run(path, cmd, script(), cmd + " without AUTOBEAD")
        assert "AUTOBEAD is not loaded" in said(vm), said(vm)[-400:]
        assert "step(s) drawn" in said(vm), said(vm)[-400:]
    print("AUTOBEAD absent is a sentence at the end of the run, not a failure")


def test_a_selection_that_cannot_be_a_run_stops_with_a_reason():
    """Each routine's own refusal, through its *error* handler - which
    is also where the settings and any open group are put back."""
    cases = []

    def parallel_walls():
        vm = fresh(CORNERSTP)
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 50.0 0.0) (list 11 200.0 50.0 0.0)))')
        return vm, 'c:CORNERSTP', [None, list(vm.entities)], \
            "no corner found"
    cases.append(parallel_walls)

    def line_that_misses_the_curve():
        vm = fresh(HEMISTEP)
        vm.loads('(entmake (list (cons 0 "ARC") (list 10 0.0 0.0 0.0)'
                 ' (cons 40 100.0) (cons 50 0.0) (cons 51 %r)))' % math.pi)
        vm.loads('(entmake (list (cons 0 "LINE") (list 10 400.0 400.0 0.0)'
                 ' (list 11 500.0 400.0 0.0)))')
        return vm, 'c:HEMISTEP', [None, list(vm.entities)], \
            "does not reach the curve"
    cases.append(line_that_misses_the_curve)

    def four_loose_lines():
        vm = fresh(NORMIESTEP)
        for i in range(4):
            vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 %r 0.0)'
                     ' (list 11 100.0 %r 0.0)))' % (i * 30.0, i * 30.0))
        return vm, 'c:NORMIESTEP', [None, list(vm.entities)], \
            "does not fit"
    cases.append(four_loose_lines)

    for build in cases:
        vm, cmd, script, expected = build()
        vm.handle_errors = True
        before = dict(vm.sysvars)
        vm.run(cmd, script)
        assert expected in said(vm), (cmd, said(vm)[:400])
        assert vm.undo_groups == 0, cmd
        for var in ('CLAYER', 'CMDECHO', 'LUNITS'):
            assert vm.sysvars[var] == before[var], \
                "%s left %s as %r" % (cmd, var, vm.sysvars[var])
        assert "error" not in said(vm).lower(), said(vm)[-300:]
    print("a selection that cannot be a run stops with a reason, and cleans up")


def test_hemistep_reads_a_curve_it_was_handed():
    """The curve modes in the real code: an arc on its own is measured
    from its middle, into the curve, and Enter at a width fits that
    step to the curve exactly."""
    vm = fresh(HEMISTEP)
    vm.loads('(entmake (list (cons 0 "ARC") (list 10 0.0 0.0 0.0)'
             ' (cons 40 100.0) (cons 50 0.0) (cons 51 %r)))' % math.pi)
    arc = list(vm.entities)
    vm.run('c:HEMISTEP', [None, arc, "No", 24.0, None, 24.0, None,
                          None, None, "No"])
    out = said(vm)
    assert "middle of the arc, into the curve" in out, out[:400]
    assert "fitted to the curve" in out, out[:600]
    chords = []
    for e in vm.entities[len(arc):]:
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'LINE'
               for g in data):
            pts = {g[0]: (g[1], g[2]) for g in data
                   if isinstance(g, list) and g and g[0] in (10, 11)}
            chords.append((pts[10], pts[11]))
    assert len(chords) == 2, "%d chords, expected 2" % len(chords)
    for (x1, y1), (x2, y2) in chords:
        assert abs(y1 - y2) < 1e-9, "a chord is not parallel to the tangent"
        assert abs(x1 + x2) < 1e-9, "a chord is not centred on the axis"
        # every end sits on the arc it was fitted to
        for x, y in ((x1, y1), (x2, y2)):
            assert abs(math.hypot(x, y) - 100.0) < 1e-6, (x, y)
    assert any(any(isinstance(g, Dot) and g.a == 0 and g.b == 'LWPOLYLINE'
                   for g in vm.entdata.get(e, []))
               for e in vm.entities), "no boundary polyline was drawn"
    print("HEMISTEP measures a curve from its middle and fits its steps to it")


AUTOBEAD = os.path.join(HERE, '..', 'lisp', 'autobead', 'AUTOBEAD.lsp')

#: Enter at the bead question and at the side question (taking the
#: <Yes> and <All> defaults), then a point well clear of the run for
#: the side to bead toward.
BEAD_TAIL = [None, None, (0.0, -500.0, 0.0)]


def test_the_bead_hand_off_with_autobead_actually_loaded():
    """Sections 11 / 8 / 8 of the three routines are gated on
    (boundp 'autobead-build), and no suite ever loaded AUTOBEAD beside
    them: across the whole of tests/, autobead-build appeared only in
    test_autobead.py, and the only step-routine bead coverage was
    test_autobead_absent_is_said_not_crashed above -- the branch that
    does nothing.  So the hand-off itself was never executed by
    anything, in any of the three routines.

    What is pinned is the CONTRACT: the run reaches the bead flow, asks
    its three questions, and hands over a non-empty selection set, the
    direction as picked, the side keyword, no individually-named treads
    on the All branch, and exactly one tread to hold back -- which is a
    real tread, the midpoint of a line the run drew, and not a stale
    point left over from somewhere else.

    autobead-build is replaced by a recorder rather than wrapped: the
    real one reports through (prompt), which the VM does not record, and
    what is untested here is the hand-off, not AUTOBEAD.
    """
    seen = []
    for cmd, (path, script) in sorted(SCRIPT.items()):
        vm = fresh(path)
        vm.load(AUTOBEAD)
        vm.loads("(setq t:*seen* nil)")
        vm.loads("(defun autobead-build (ss dir side some hold)"
                 " (setq t:*seen* (list (sslength ss) dir side some hold))"
                 " (princ))")
        s = list(script())
        if s and s[0] == 'WALLS':
            s[0] = walls(vm, pair=(cmd == 'c:CORNERSTP'))
        try:
            vm.run(cmd, s + BEAD_TAIL)
        except LispError as e:
            raise AssertionError("[%s bead hand-off] %s" % (cmd, e)) from None

        asked = [p for p, _ in vm.prompts]
        assert any("Bead the steps?" in p for p in asked), \
            "%s never offered to bead with AUTOBEAD loaded" % cmd
        got = vm.globals.get('t:*seen*')
        assert got, "%s never called autobead-build" % cmd
        nss, direction, side, some, hold = got
        assert int(nss) > 0, "%s handed over an empty set" % cmd
        assert [round(float(v), 6) for v in direction] == [0.0, -500.0, 0.0], \
            "%s passed %r, not the point that was picked" % (cmd, direction)
        assert str(side) == "All", "%s passed side %r" % (cmd, side)
        assert not some, \
            "%s named individual treads on the All branch: %r" % (cmd, some)
        assert hold and len(hold) == 1, \
            "%s held back %r tread(s), not exactly one" % (
                cmd, hold and len(hold))
        assert "AUTOBEAD is not loaded" not in said(vm), \
            "%s says AUTOBEAD is absent while it is loaded" % cmd

        # the held-back point is a real tread: the midpoint of one of
        # the lines this run drew, not a leftover from anywhere else
        held = tuple(round(float(v), 6) for v in hold[0])
        mids = set()
        for e in vm.entities:
            if e in vm.deleted:
                continue
            pts = [g[1:3] for g in vm.entdata.get(e, [])
                   if isinstance(g, list) and g and g[0] in (10, 11)]
            if len(pts) == 2:
                mids.add(tuple(round((float(a) + float(b)) / 2.0, 6)
                               for a, b in zip(pts[0], pts[1])))
        assert held[:2] in mids, \
            "%s held back %r, which is no line's midpoint" % (cmd, held)
        seen.append((cmd.split(':')[1], int(nss)))

    print("   %s -- each hands over one held-back tread"
          % ", ".join("%s: %d objects" % t for t in seen))


def test_the_bead_hand_off_in_a_drawing_with_undo_off():
    """autobead-build opens its own undo group conditionally -- _Begin
    errors when recording is off -- and closed it unconditionally, so a
    drafter with undo off got the beads drawn and then an AutoLISP
    error, with the OSMODE and PEDITACCEPT putback behind it never
    reached.  It is a function, not a command, so the command sweep in
    tests/test_undo_off.py cannot reach it: the step routines are what
    call it, and this is the shortest path there.
    """
    for cmd, (path, script) in sorted(SCRIPT.items()):
        vm = fresh(path)
        vm.load(AUTOBEAD)
        vm.sysvars['UNDOCTL'] = 4          # undo on, recording bit clear
        s = list(script())
        if s and s[0] == 'WALLS':
            s[0] = walls(vm, pair=(cmd == 'c:CORNERSTP'))
        try:
            vm.run(cmd, s + BEAD_TAIL)
        except LispError as e:
            raise AssertionError(
                "[%s with undo recording off] %s" % (cmd, e)) from None
        assert any("Bead the steps?" in p for p, _ in vm.prompts), \
            "%s never reached the hand-off, so this proves nothing" % cmd
        assert not [c for c in vm.commands
                    if c and c[0] == '_.UNDO'], \
            "%s sent an UNDO command with recording off: %r" % (
                cmd, [c for c in vm.commands if c and c[0] == '_.UNDO'])
    print("   and with undo recording off none of them sends an UNDO at all")


def main():
    test_every_knob_is_read_and_every_read_is_a_knob()
    test_each_reader_falls_back_to_the_value_the_block_sets()
    test_the_shared_knobs_agree_across_the_three_files()
    test_a_knob_set_to_nonsense_draws_the_default()
    test_the_standoff_knobs_move_the_dims()
    test_the_tolerance_knob_decides_what_snaps()
    test_the_parallel_knob_decides_when_it_warns()
    test_the_join_fuzz_knob_reads_a_sloppy_u()
    test_a_drawing_with_undo_off_still_runs()
    test_missing_dim_styles_are_reported_and_the_dims_still_land()
    test_an_unusable_dim_layer_falls_back_to_the_current_one()
    test_a_frozen_current_layer_is_called_out()
    test_autobead_absent_is_said_not_crashed()
    test_the_bead_hand_off_with_autobead_actually_loaded()
    test_the_bead_hand_off_in_a_drawing_with_undo_off()
    test_a_selection_that_cannot_be_a_run_stops_with_a_reason()
    test_hemistep_reads_a_curve_it_was_handed()
    print("all tests passed")


if __name__ == "__main__":
    main()
