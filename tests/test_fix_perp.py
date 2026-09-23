#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""PERPPTS, CPERPPTS, their tutorials and PERPMARK, run the way AutoCAD
runs them where the stock VM is kinder than AutoCAD is.

Four things the stock VM could not see.  The first is modelled in
tests/lispvm.py now; the other three are modelled here, inside the
test:

* THE ERROR MODE.  Under *push-error-using-command* AutoCAD resets the
  evaluator before *error* runs: the handler it calls is the one in
  force at the failure, but every binding the command made is gone --
  its locals read nil and its local helpers are undefined.  In the
  default mode the stack is live, command-s is fine and a bare
  (command) from inside *error* is refused.  A pop with nothing pushed
  is AutoCAD's "(*pop-error-mode*) underflow".  The VM kept every
  frame live in both modes, so PERPPTS's handler -- nothing but a
  call to its LOCAL perp:finish, behind a push -- passed every test and
  died at its first form in AutoCAD: OSMODE left at 0, the drafter on
  PERPPTS-TEMP, the guides in the drawing, no report, and the mode left
  pushed for the session.  (tests/test_lispvm_errmode.py pins it.)
* PLINEWID.  The stock VM does not seed it, and its PLINE ignores it.
  PLINE starts every polyline at it, so a width left behind by an
  earlier PLINE made every measured course a heavy band.
* THE UCS.  A click comes back in the current UCS and a survey point
  is read out of entget in WCS.  The stock VM's trans was the identity
  and a UCS was modelled here; vm.set_ucs is the VM's own now.
* THE SPACEBAR.  At a click-or-type prompt it is Enter, so the docs a
  drafter reads must spell a fraction dashed.

Every VM here loads through lispvm's VM.load, which remaps a lisp/ path
to the tier CALOFIN_LISP_ROOT names, so under `make parity` these runs
are runs of the shared twins; the tests that read a file's TEXT resolve
it the same way, through tier_path.

Run: python3 tests/test_fix_perp.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_fix_perp.py
"""

import contextlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from lispvm import VM, Ent, Dot, Sym, LispError, BUILTINS  # noqa: E402
import test_perp_points as tpp  # noqa: E402
import test_perpmark as tpm  # noqa: E402

#: the files under test -- a dict so a check against an older copy can
#: point it somewhere else and run the same tests
PATHS = {
    'perp': os.path.join(REPO, 'lisp', 'perp_points', 'perp_points.lsp'),
    'cperp': os.path.join(REPO, 'lisp', 'perp_points', 'cperp_points.lsp'),
    'tutp': os.path.join(REPO, 'lisp', 'perp_points',
                         'tutorial_perp_points.lsp'),
    'tutc': os.path.join(REPO, 'lisp', 'perp_points',
                         'tutorial_cperp_points.lsp'),
    'pm': os.path.join(REPO, 'lisp', 'perpmark', 'PERPMARK.lsp'),
    'perp_readme': os.path.join(REPO, 'lisp', 'perp_points', 'README.md'),
    'pm_readme': os.path.join(REPO, 'lisp', 'perpmark', 'README.md'),
}

REPORT = Sym('*fixperp-report*')


def tier_path(path):
    """PATH as the tier under test has it -- what VM.load does to a
    lisp/ path under CALOFIN_LISP_ROOT, for a test that reads the text.
    A path outside lisp/ (an older copy in a scratch folder) is left
    alone, as VM.load leaves it."""
    root = os.environ.get('CALOFIN_LISP_ROOT')
    parts = os.path.abspath(path).split(os.sep)
    if not root or 'lisp' not in parts:
        return path
    stem, ext = os.path.splitext(os.path.basename(path))
    name = stem + ext.lower()
    for base in (os.path.join(REPO, root, 'parts'), os.path.join(REPO, root)):
        if os.path.exists(os.path.join(base, name)):
            return os.path.join(base, name)
    # missing: name where it should be, so the open fails loudly rather
    # than quietly reading the lisp/ copy a second time
    return os.path.join(REPO, root, 'parts', name)


# ---- AutoCAD's two error modes ----------------------------------------
# tests/lispvm.py models them itself now (tests/test_lispvm_errmode.py):
# a pushed handler runs with the stack reset, a bare (command) is refused
# in a default-mode one, a pop with nothing pushed fails the run, and a
# handler that dies raises lispvm.HandlerDeath and is named in
# vm.handler_deaths.  What is left here is the undo count the test's own
# (command) stand-in does not keep.

@contextlib.contextmanager
def autocad_error_modes(vm):
    """Run VM with the undo groups counted through the test's (command)
    stand-in, and a group left open failing the run.  Installed AFTER
    the stand-in, which it wraps."""
    orig_check = VM._check_balanced
    inner = BUILTINS[Sym('command')]
    vm.undo_open = 0

    def counted(vm_, a):
        # the test's (command) stand-in does not keep the undo count
        if a and isinstance(a[0], str) and \
                a[0].upper().lstrip('._') == 'UNDO' and len(a) >= 2:
            sub = str(a[1]).upper().lstrip('_')
            if sub == 'BEGIN':
                vm_.undo_open += 1
            elif sub == 'END':
                if vm_.undo_open <= 0:
                    raise LispError('_.UNDO _End with no group open', vm_)
                vm_.undo_open -= 1
        return inner(vm_, a)

    def check_balanced(self, name):
        orig_check(self, name)
        if self.undo_open:
            raise LispError(f"{name} returned with {self.undo_open} undo "
                            f"group(s) still open", self)

    BUILTINS[Sym('command')] = counted
    VM._check_balanced = check_balanced
    try:
        yield vm
    finally:
        BUILTINS[Sym('command')] = inner
        VM._check_balanced = orig_check


def esc(vm):
    raise LispError('Function cancelled', vm)


def perp_vm(key, plinewid=None):
    """A VM holding PERPPTS (key 'perp') or CPERPPTS ('cperp') and the
    object it is pointed at, the way tpp.run_routine builds one, with
    handler dispatch on and a stand-in lzd:report that records what it
    was handed."""
    tpp.install_entity_builtins()
    tpp.install_curve_builtins()
    tpp.install_intersect_builtins()
    vm = VM()
    tpp.install_command(vm)
    vm.load(PATHS[key])
    vm.loads("(defun lzd:report (tool ver msg) "
             "(setq *fixperp-report* (list tool msg)) nil)")
    if key == 'perp':
        src = Ent()
        vm.entities.append(src)
        vm.entdata[src] = [Dot(0, 'LINE'), Dot(8, 'WALLS'), Dot(62, 3),
                           [10, 0.0, 0.0, 0.0], [11, 100.0, 0.0, 0.0]]
    else:
        src = tpp.make_polyline(vm, [(0.0, 0.0), (100.0, 0.0)], None,
                                'WALLS', 3)
    vm.source = src
    vm.tables['LAYER'].add('WALLS')
    vm.tables['DIMSTYLE'].add('STANDARD INCHES')
    vm.handle_errors = True
    if plinewid is not None:
        vm.sysvars['PLINEWID'] = plinewid
    return vm


@contextlib.contextmanager
def watch_pline(vm):
    """Record PLINETYPE and PLINEWID as each PLINE starts, onto
    vm.at_pline; the (command) in force before is back on the way out."""
    inner = BUILTINS[Sym('command')]
    vm.at_pline = []

    def command(vm_, a):
        if a and a[0] == '._PLINE':
            vm_.at_pline.append((vm_.sysvars.get('PLINETYPE'),
                                 vm_.sysvars.get('PLINEWID')))
        return inner(vm_, a)

    BUILTINS[Sym('command')] = command
    try:
        yield vm
    finally:
        BUILTINS[Sym('command')] = inner


def live_temp(vm):
    return [e for e in vm.entities
            if e not in vm.deleted
            and tpp.dxf(vm.entdata[e], 8) == 'PERPPTS-TEMP']


def run_modelled(vm, cmd, answers):
    """vm.run under the modelled error modes; the handler deaths and
    the leftover checks come back as a failed assertion naming them."""
    with autocad_error_modes(vm):
        try:
            vm.run(cmd, answers)
        except LispError as e:
            raise AssertionError("%s: %s (handler deaths: %r)"
                                 % (cmd, str(e).splitlines()[0],
                                    vm.handler_deaths)) from None
    assert not vm.handler_deaths, vm.handler_deaths


# ---- 1, 2: Esc mid-run reaches the end of the handler -----------------

def check_esc_at_the_length(key, cmd, tool):
    vm = perp_vm(key, plinewid=2.0)
    before = dict(vm.sysvars)
    run_modelled(vm, cmd, [vm.source, tpp.CLICK, None, None, 3, esc])
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    # ERRNO is not a setting: the boundary question zeroes it on purpose
    # before its entsel, since it is sticky and 7 is what it reads
    changed = {k: (before.get(k), v) for k, v in vm.sysvars.items()
               if before.get(k) != v and k != 'ERRNO'}
    assert not changed, "settings not put back: %r" % changed
    assert vm.error_mode_depth == 0, vm.error_mode_depth
    assert vm.undo_open == 0, "the undo group was left open"
    assert not live_temp(vm), \
        "%d guide(s) left in the drawing" % len(live_temp(vm))
    rep = vm.globals.get(REPORT)
    assert rep and rep[0] == tool, "no LAZDIAG report was filed: %r" % (rep,)
    assert any("Cancelled." in s for s in vm.printed), vm.printed[-3:]


def test_perppts_esc_at_a_length_reaches_the_end_of_its_handler():
    check_esc_at_the_length('perp', 'c:PERPPTS', 'PERPPTS')
    print("ok  PERPPTS: Esc at a length -- settings, guides, undo and the "
          "report all come back")


def test_cperppts_esc_at_a_length_reaches_the_end_of_its_handler():
    check_esc_at_the_length('cperp', 'c:CPERPPTS', 'CPERPPTS')
    print("ok  CPERPPTS: Esc at a length -- settings, guides, undo and the "
          "report all come back")


def test_neither_routine_pushes_the_error_mode():
    """The handlers read the commands' locals, which only the default
    mode keeps -- so neither routine may push, and nothing the handler
    reaches may be a bare (command)."""
    for key in ('perp', 'cperp'):
        code = tpp.strip_comments(open(tier_path(PATHS[key])).read())
        assert '*push-error-using-command*' not in code, \
            "%s pushes the error mode" % key
        assert '*pop-error-mode*' not in code, "%s pops a mode" % key
        fin = code[code.index('(defun %s:finish' % key):
                   code.index('(defun *error*')]
        assert not re.search(r"\(command[\s)]", fin), \
            "%s:finish drives a bare (command), which the default mode " \
            "refuses from inside *error*" % key
    print("ok  PERPPTS/CPERPPTS: no push, no pop, no bare (command) in the "
          "cleanup")


# ---- 3: finish-then-exit does not pop twice ---------------------------

def refused_resize(key, cmd):
    """One run whose width question is answered with a resize the
    layer will not take (a locked, frozen or switched-off layer), so
    the routine explains itself and stops by (exit)."""
    vm = perp_vm(key)
    tpp.SCALE_REFUSES[0] = True
    try:
        run_modelled(vm, cmd, [vm.source, tpp.CLICK, 'Grew', 20.0, None])
    finally:
        tpp.SCALE_REFUSES[0] = False
    return vm


def test_perppts_exit_after_a_refused_resize_pops_nothing():
    vm = refused_resize('perp', 'c:PERPPTS')
    assert any("could not be resized" in s for s in vm.printed)
    assert len(vm.handled_errors) == 1 and \
        'SCRIPT' not in vm.handled_errors[0], vm.handled_errors
    assert vm.error_mode_underflow == 0 and vm.error_mode_depth == 0
    assert vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CLAYER'] == '0'
    print("ok  PERPPTS: a refused resize exits without an error-mode "
          "underflow")


def test_cperppts_exit_after_a_refused_resize_pops_nothing():
    vm = refused_resize('cperp', 'c:CPERPPTS')
    assert any("could not be resized" in s for s in vm.printed)
    assert len(vm.handled_errors) == 1 and \
        'SCRIPT' not in vm.handled_errors[0], vm.handled_errors
    assert vm.error_mode_underflow == 0 and vm.error_mode_depth == 0
    assert vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CLAYER'] == '0'
    print("ok  CPERPPTS: a refused resize exits without an error-mode "
          "underflow")


# ---- a stop the run explains is not called a cancel ------------------

def check_explained_stop(key, cmd, tool):
    vm = refused_resize(key, cmd)
    said = "".join(vm.printed)
    tail = said[said.rindex("could not be resized"):]
    assert "Cancelled." not in tail and "Error:" not in tail, \
        "%s: after its own reason the run said %r" \
        % (tool, tail[tail.index("again.") + 6:])
    # the finish before the (exit) and the handler's both run: the
    # second may not restore the dimension style again, after the undo
    # group has closed, where the drafter's next U would undo it
    cmds = [c[0].upper().lstrip('._') for c in vm.commands]
    assert cmds.count('-DIMSTYLE') == 1, "%s restored the dimension style " \
        "%d times" % (tool, cmds.count('-DIMSTYLE'))
    assert cmds[-1] == 'UNDO', "%s drove %r after closing its undo group" \
        % (tool, cmds[cmds.index('UNDO', 1) + 1:])
    # it is still filed: as the quit it is, at the prompt it stopped at
    rep = vm.globals.get(REPORT)
    assert rep and rep[0] == tool, "no LAZDIAG call: %r" % (rep,)


def test_perppts_stop_after_a_refused_resize_is_not_a_cancel():
    check_explained_stop('perp', 'c:PERPPTS', 'PERPPTS')
    print("ok  PERPPTS: a refused resize ends on its reason -- no "
          "'Cancelled.', no second DIMSTYLE past the undo group")


def test_cperppts_stop_after_a_refused_resize_is_not_a_cancel():
    check_explained_stop('cperp', 'c:CPERPPTS', 'CPERPPTS')
    print("ok  CPERPPTS: a refused resize ends on its reason -- no "
          "'Cancelled.', no second DIMSTYLE past the undo group")


def test_every_explained_stop_is_flagged():
    """Every (exit) in either routine is a stop the run has just
    explained, and each one sets the flag the handler reads -- the
    zero-length object and CPERPPTS's too-few-points stop included,
    which no drawing the VM builds reaches."""
    for key in ('perp', 'cperp'):
        code = tpp.strip_comments(open(tier_path(PATHS[key])).read())
        exits = len(re.findall(r"\(exit\)", code))
        flagged = len(re.findall(r"\(setq stopped T\)\s*\(exit\)", code))
        assert exits and flagged == exits, \
            "%s: %d of %d (exit)s set the stop flag first" \
            % (key, flagged, exits)
        fin = code[code.index('(defun %s:finish' % key):
                   code.index('(defun *error*')]
        assert re.search(r"\(setq cdim nil\)", fin), \
            "%s:finish restores the dimension style every time it runs" % key
    print("ok  PERPPTS/CPERPPTS: every (exit) is a flagged stop, and the "
          "finish is safe to run twice")


# ---- 5: the course is a hairline whatever PLINE last used -------------

def check_course_width(key, cmd, script):
    vm = perp_vm(key, plinewid=2.0)
    with watch_pline(vm):
        run_modelled(vm, cmd, [vm.source, tpp.CLICK, None, None] + script)
    assert vm.at_pline, "no PLINE was drawn"
    assert all(w == 0.0 for _t, w in vm.at_pline), \
        "PLINE ran at PLINEWID %r" % (vm.at_pline,)
    assert all(t == 2 for t, _w in vm.at_pline), vm.at_pline
    assert vm.sysvars['PLINEWID'] == 2.0, \
        "the drafter's PLINEWID was not put back: %r" % vm.sysvars['PLINEWID']
    # and a drawing already at 0 stays there
    vm = perp_vm(key, plinewid=0.0)
    with watch_pline(vm):
        run_modelled(vm, cmd, [vm.source, tpp.CLICK, None, None] + script)
    assert vm.at_pline and vm.sysvars['PLINEWID'] == 0.0


def test_perppts_draws_its_course_as_a_hairline():
    check_course_width('perp', 'c:PERPPTS',
                       [3, 10.0, 12.0, 14.0, 'Straight', tpp.WIDTH_OK, 'No',
                        'STandard'])
    print("ok  PERPPTS: the course is drawn at PLINEWID 0, the drafter's "
          "width comes back")


def test_cperppts_draws_its_course_as_a_hairline():
    check_course_width('cperp', 'c:CPERPPTS',
                       [3, 10.0, 12.0, 10.0, tpp.WIDTH_OK, 'No',
                        'STandard'])
    print("ok  CPERPPTS: the course is drawn at PLINEWID 0, the drafter's "
          "width comes back")


def tutorial_vm(key):
    tpp.install_entity_builtins()
    tpp.install_curve_builtins()
    vm = VM()
    tpp.install_command(vm)
    vm.load(PATHS[key])
    vm.handle_errors = True
    vm.sysvars['PLINEWID'] = 2.0
    vm.sysvars['PLINETYPE'] = 0
    return vm


def check_tutorial(key, cmd, pauses):
    vm = tutorial_vm(key)
    with watch_pline(vm):
        run_modelled(vm, cmd, ['Demo', [0.0, 0.0, 0.0], None]
                     + [None] * pauses + [None])
    assert vm.at_pline, "the demo drew no PLINE"
    assert all(at == (2, 0.0) for at in vm.at_pline), \
        "the demo's PLINE ran at (PLINETYPE, PLINEWID) %r" % (vm.at_pline,)
    assert vm.sysvars['PLINEWID'] == 2.0 and vm.sysvars['PLINETYPE'] == 0, \
        (vm.sysvars['PLINETYPE'], vm.sysvars['PLINEWID'])


def test_the_tutorials_draw_what_the_commands_draw():
    check_tutorial('tutp', 'c:TUTORIALPERPPTS', 7)
    check_tutorial('tutc', 'c:TUTORIALCPERPPTS', 4)
    print("ok  tutorials: the demo polylines are lightweight hairlines, and "
          "PLINETYPE/PLINEWID come back")


# ---- 6: a survey-point click is carried into WCS ----------------------

#: the UCS origin, in WCS, axes parallel: the VM's own trans honours it
#: (vm.set_ucs; tests/test_lispvm_ucs.py) -- a ucs_trans that added and
#: took off the origin used to be swapped in here for it
UCS_ORIGIN = (100.0, 0.0, 0.0)


def perpmark_vm():
    """tpm.newvm's drawing, built on PATHS['pm'] (so a check against an
    older copy runs on that copy), plus FIXPERPASK: one survey-point
    question over every candidate the drawing offers, the answer left
    in *fixperp-got*."""
    vm = VM()
    vm.load(PATHS['pm'])
    for s in ('STANDARD', 'STANDARD INCHES', 'SIDE STANDARD'):
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    tpm.rect(vm)
    vm.loads('(defun c:FIXPERPASK () '
             '(setq *fixperp-got* (pm:askpoint "Pick a survey point" nil nil'
             ' (pm:collect-points))) (princ))')
    return vm


def test_perpmark_takes_the_point_under_a_ucs_click():
    """Two survey points 100 apart along X, and a UCS whose origin sits
    100 along X: the UCS numbers of a click on Pt.1 are Pt.2's WCS
    numbers.  Compared raw, the click took Pt.2."""
    vm = perpmark_vm()
    pt1 = tpm.ab_pt(vm, 140, 0, 1)     # UCS (40, 0)
    tpm.ab_pt(vm, 40, 0, 2)            # UCS (-60, 0)
    vm.set_ucs(UCS_ORIGIN)
    vm.run('c:FIXPERPASK', [[40.0, 1.0, 0.0]])
    got = vm.globals.get(Sym('*fixperp-got*'))
    assert got and got[2] is pt1, \
        "the click on Pt.1 took %r" % (got[1] if got else got,)
    print("ok  PERPMARK: a click in a moved UCS takes the point under it")


# ---- PERPMARK reads model space only ----------------------------------

def paper_pt(vm, x, y, number):
    """A survey-point block pasted onto a layout -- a key plan, a
    detail -- which is not one of the pool's points."""
    e = tpm.ab_pt(vm, x, y, number)
    vm.entdata[e].append(Dot(410, 'Layout1'))
    return e


def test_perpmark_leaves_a_layouts_survey_points_alone():
    """Pt.4 in model space, and a copy of it on a sheet one unit away.
    A typed 4 is Pt.4, not "two points are numbered 4"; a click on the
    sheet copy's spot is Pt.4, which is within the snap, not the copy."""
    vm = perpmark_vm()
    pt4 = tpm.ab_pt(vm, 20, 0, 4)
    paper_pt(vm, 21, 0, 4)
    try:
        vm.run('c:FIXPERPASK', ["4"])
    except LispError:
        # asked again, with no second answer to give
        pass
    got = vm.globals.get(Sym('*fixperp-got*'))
    assert not tpm.said(vm, "points are numbered"), \
        "a typed 4 found the layout's copy as well: %r" % vm.printed[-1:]
    assert got and got[2] is pt4, got
    vm = perpmark_vm()
    pt4 = tpm.ab_pt(vm, 20, 0, 4)
    paper_pt(vm, 21, 0, 4)
    vm.run('c:FIXPERPASK', [[21.0, 0.0, 0.0]])
    got = vm.globals.get(Sym('*fixperp-got*'))
    assert got and got[2] is pt4, \
        "a click took the layout's copy, not the point in model space"
    print("ok  PERPMARK: a survey point pasted onto a layout is never a "
          "candidate")


# ---- 4: the docs spell a typed fraction dashed ------------------------

RULER_START = ";;; -------------------- the length ruler"
RULER_END = ";;; -------------------- end of the length ruler"


def outside_ruler(src):
    """SRC with the fenced ruler block cut out: that block is the
    library's text, copied, and is corrected there."""
    i = src.find(RULER_START)
    j = src.find(RULER_END)
    if i >= 0 and j > i:
        return src[:i] + src[src.index("\n", j):]
    return src


def test_the_docs_spell_a_typed_fraction_dashed():
    """At a click-or-type length prompt the spacebar is Enter: 44 1/2
    enters 44 and hands 1/2 to the next question.  Every place a drafter
    is told how to type one says 44-1/2."""
    sites = {
        'perp': "type a length",
        'cperp': "type a length",
        'pm': "it reads as DIMSTAMP reads",
        'perp_readme': "| type a length |",
        'pm_readme': "reads the way `DIMSTAMP` reads",
    }
    for key, anchor in sites.items():
        src = outside_ruler(open(PATHS[key], encoding='utf-8').read())
        at = src.find(anchor)
        assert at >= 0, "%s: %r not found" % (key, anchor)
        passage = src[at:at + 400]
        assert "44-1/2" in passage and "4'-4-1/2" in passage, \
            "%s: the dashed spellings are not shown at %r" % (key, anchor)
        # a spaced one in the LIST of spellings -- "44 1/2," or
        # "`44 1/2`," -- or the spaced feet-and-inches one anywhere.  The
        # sentence saying why the space does not work may show it.
        listed = re.findall(r"44 1/2`?,|4'-4 1/2", passage)
        assert not listed, \
            "%s: a typed spelling is shown spaced: %r" % (key, listed)
    print("ok  docs: every typed-length spelling is dashed")


def main():
    test_perppts_esc_at_a_length_reaches_the_end_of_its_handler()
    test_cperppts_esc_at_a_length_reaches_the_end_of_its_handler()
    test_neither_routine_pushes_the_error_mode()
    test_perppts_exit_after_a_refused_resize_pops_nothing()
    test_cperppts_exit_after_a_refused_resize_pops_nothing()
    test_perppts_stop_after_a_refused_resize_is_not_a_cancel()
    test_cperppts_stop_after_a_refused_resize_is_not_a_cancel()
    test_every_explained_stop_is_flagged()
    test_perppts_draws_its_course_as_a_hairline()
    test_cperppts_draws_its_course_as_a_hairline()
    test_the_tutorials_draw_what_the_commands_draw()
    test_perpmark_takes_the_point_under_a_ucs_click()
    test_perpmark_leaves_a_layouts_survey_points_alone()
    test_the_docs_spell_a_typed_fraction_dashed()
    print("\nall PERP fix tests passed")


if __name__ == '__main__':
    main()
