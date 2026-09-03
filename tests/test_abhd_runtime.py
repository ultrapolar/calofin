# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime cross-check: the REAL abhd.lsp fitter against its mirror.

tests/test_pool_fit.py is a Python transcription of the ABHD fitter,
and every rule the command promises is tested there - but a
transcription only proves anything while the two agree.  So this file
loads abhd.lsp itself into the AutoLISP VM (tests/lispvm.py), runs
pf:build over the same fixtures, and compares the result segment for
segment: same count, same endpoints, same bulges.

A change made to one side and not the other dies here.  With
CALOFIN_LISP_ROOT=shared the same run drives the grouped twin, so the
two builds are checked against the one mirror.

Usage:  python3 tests/test_abhd_runtime.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Sym                      # noqa: E402
import test_pool_fit as T                       # noqa: E402

LSP = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                   'lisp', 'abhd', 'abhd.lsp')

_VM = None


def vm():
    """One loaded VM for the whole run - loading is the slow part."""
    global _VM
    if _VM is None:
        _VM = VM()
        _VM.load(LSP)
        # the command binds these per run; nothing is declared here
        _VM.loads("(setq pf-walls nil pf-corners nil pf-holds nil"
                  " pf-miss-pct nil)")
    return _VM


def lisp_build(pts, tol, mode, maxarcs=None):
    """pf:build in the VM, as the command calls it (points-driven)."""
    lst = "(list " + " ".join("(list %.17g %.17g)" % (p[0], p[1])
                              for p in pts) + ")"
    # the allowance is worked out here rather than in the LISP: the
    # grouped twin takes its pf:ceil from the shared library under
    # another name, and this driver has to read both builds
    vm().loads(
        '(setq $pts %s)\n'
        '(setq $tour (pf:order-points $pts))\n'
        '(setq *PF-MAX-ARCS* %s)\n'
        '(setq $segs (pf:build $tour nil $pts $pts %.17g %d "%s"))\n'
        % (lst, "nil" if maxarcs is None else str(maxarcs), tol,
           T.pf_ceil(T.MISS_PCT * len(pts)), mode))
    return [((float(s[0][0]), float(s[0][1])),
             (float(s[1][0]), float(s[1][1])), float(s[2]))
            for s in vm().eval(Sym('$segs'))]


def same(a, b):
    """The same closed loop, allowing for where the walk started.

    On a shape whose turns tie - a circle sampled evenly - the walk's
    origin is decided by which of two identical turns rounds larger,
    and AutoLISP's atan2 and Python's need not round alike.  The loop
    they draw is still the same loop, so compare it as a ring."""
    if len(a) != len(b):
        return False
    return any(all(T.dist(x[0], y[0]) < 1.0e-9
                   and T.dist(x[1], y[1]) < 1.0e-9
                   and abs(x[2] - y[2]) < 1.0e-9
                   for x, y in zip(a[k:] + a[:k], b))
               for k in range(len(a)))


# The VM is an interpreter written in Python and the fitter is
# quadratic in the points it covers, so the fixtures here are the
# small ones: enough shape to exercise every branch, few enough points
# that the run stays in seconds.  The full-size versions live in
# test_pool_fit.py, which runs against the mirror.
SHAKY = T.blob_pts(40, 0.6, 7)


def test_fitter_matches_its_mirror():
    # every fixture here has one clearly sharpest turn, so both sides
    # start the walk at the same point: an evenly sampled circle or
    # rectangle ties, and a tie is broken by rounding
    shapes = (("blob", T.blob_pts(40), None),
              ("shaky survey", SHAKY, None),
              ("stray shots", T.spiky_blob_pts(40, 0.3, 7, 2), None),
              ("blob, cap 9", T.blob_pts(40), 9))
    for label, pts, cap in shapes:
        tour = T.order_points(list(pts))
        allowance = T.pf_ceil(T.MISS_PCT * len(pts))
        got = []
        for mode in T.COMPARE_MODES:
            lisp = lisp_build(pts, 1.0, mode, cap)
            py, _ = T.build(tour, 1.0, allowance, mode, maxarcs=cap)
            assert same(lisp, py), (
                "%s / %s: abhd.lsp draws %d segments, the mirror %d"
                % (label, mode, len(lisp), len(py)))
            got.append(len(lisp))
        print("  %-14s %s segments, LISP and mirror agree"
              % (label, "/".join(str(g) for g in got)))


def test_shaky_survey_is_not_spaghetti_in_the_lisp():
    """The complaint itself, run through the real file: a survey with
    scatter must not come back as a chain of loops."""
    pts = SHAKY
    step = T.spacing(pts)
    for mode in T.COMPARE_MODES:
        segs = lisp_build(pts, 1.0, mode)
        sweeps = T.arc_sweeps(segs)
        radii = [T.bulge_radius(*s) for s in segs if abs(s[2]) > 1.0e-9]
        assert max(sweeps) < 150.0, (mode, max(sweeps))
        assert min(radii) >= 0.75 * step, (mode, min(radii))
        assert len(segs) <= 0.75 * len(pts), (mode, len(segs))
    print("  shaky survey: no loops, no hairpins, out of the LISP itself")


def test_the_commands_wrap_the_fitter():
    """c:ABHD and c:ADAB themselves, which nothing had ever run.

    The fitter under them is compared segment-for-segment against its
    mirror above; what was untested is the WRAPPER - the stale-marker
    sweep, the pickfirst probe and where it sits relative to the undo
    group, the bracket itself, and the phase name the error handler
    reports.  These assertions stay at that altitude.
    """
    from lispvm import VM

    def newvm():
        vm = VM()
        vm.load(LSP)
        vm.sysvars['CMDECHO'] = 1
        return vm

    # the seven questions, all taking their Enter default, then Enter at
    # the step-7 selection
    WIZARD = [1.0, None, None, 'No', 'No', 'No', None]

    for cmd in ('c:ABHD', 'c:ADAB'):
        vm = newvm()
        vm.run(cmd, [None] + (WIZARD if cmd == 'c:ABHD' else [None]))
        order = [p for p, _ in vm.prompts]
        assert order and order[0] == 'ssget _I', (cmd, order[:2])
        undo = [c for c in vm.commands if c and c[0] == '_.UNDO']
        assert undo == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']], (cmd, undo)
        assert vm.sysvars['CMDECHO'] == 1, cmd
    print("  both commands probe pickfirst first, then bracket one undo group")

    # a pre-typed survey skips the step-7 selection entirely
    vm = newvm()
    vm.loads('''(entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord") '(2 . "POINTS")
                    '(70 . 0) '(62 . 7) '(6 . "Continuous")))''')
    for x, y in ((0.0, 0.0), (120.0, 0.0), (120.0, 60.0), (0.0, 60.0)):
        vm.loads('(entmake (list \'(0 . "POINT") \'(8 . "POINTS")'
                 ' (list 10 %r %r 0.0)))' % (x, y))
    vm.pickfirst = ['<ss>'] + list(vm.entities)
    # with a real survey the fit completes and offers its three
    # candidates; "None" discards them, which is all this case is about
    vm.run('c:ABHD', WIZARD[:-1] + ['None'])
    assert 'Step 7 of 7' not in ''.join(vm.printed), 'step 7 was still asked'
    assert not any(p == 'ssget' for p, _ in vm.prompts), vm.prompts
    print("  a survey highlighted before ABHD is typed skips step 7")

    # a marker left by an interrupted run is swept, and said out loud
    vm = newvm()
    vm.loads('''(entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 *PF-WALL-LAYER*) '(70 . 0) '(62 . 7)
                    '(6 . "Continuous")))''')
    vm.loads('(entmake (list \'(0 . "LWPOLYLINE") (cons 8 *PF-WALL-LAYER*)'
             ' \'(90 . 2) \'(70 . 0) \'(10 0.0 0.0) \'(10 10.0 0.0)))')
    stale = vm.entities[-1]
    vm.loads('(pf:tag-mine (entlast))')
    vm.run('c:ABHD', [None] + WIZARD)
    assert 'cleared' in ''.join(vm.printed), ''.join(vm.printed)[:300]
    assert stale in vm.deleted, 'the stale marker survived'
    print("  a marker from an interrupted run is swept before the fit")


def main():
    print("ABHD runtime tests (abhd.lsp in the AutoLISP VM)"
          + (" [%s tier]" % os.environ['CALOFIN_LISP_ROOT']
             if os.environ.get('CALOFIN_LISP_ROOT') else ""))
    test_fitter_matches_its_mirror()
    test_shaky_survey_is_not_spaghetti_in_the_lisp()
    test_the_commands_wrap_the_fitter()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
