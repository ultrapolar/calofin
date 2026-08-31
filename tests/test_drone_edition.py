#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""editions/TYLERDRONE.lsp -- the whole build, plus one button.

LAZPASS carried whole, with an orange triangle added beside the panel's
hexagon: the hexagon opens the roster as ever, the triangle runs
TYLERDRONESUITE on one click.

What is worth testing is the two claims it makes that LAZPASS does not:

  * BOTH BUTTONS, wherever it lands.  LAZPASS deliberately puts up ONE
    external button -- inside the build the suite rides the panel like
    every other tool -- and that rule is right and unchanged.  This
    edition overrules it for one machine, and has to do so however the
    session got there.

  * IT STATES WHAT IT WANTS.  lzp:*suitebutton* AUTO decides by reading
    cal:*build-loading*, which the bundle this file embeds has just
    raised and nothing ever lowers.  Left to AUTO, this edition would
    conclude it was inside LAZPASS and decline the very button it
    exists for -- which is exactly what an earlier one did.

Usage:  python3 tests/test_drone_edition.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Sym  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
EDITION = os.path.join(REPO, 'editions', 'TYLERDRONE.lsp')
BUNDLE = os.path.join(REPO, 'shared', 'LAZPASS.lsp')

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


#: the COM surface, borrowed from test_lazpanel so the two cannot
#: describe different AutoCADs
_lazpanel = open(os.path.join(os.path.dirname(__file__),
                              'test_lazpanel.py')).read()
STUB = re.search(r"STUB = '''(.*?)'''", _lazpanel, re.S).group(1)

#: TYDRN is ActiveX end to end; the suite touches none of it
EXTRA = r'''
(defun vla-get-activedocument (a) "DOC")
(defun vla-startundomark (d) t)
(defun vla-endundomark (d) t)
'''


def fresh():
    vm = VM()
    vm.loads(STUB)
    lispvm.BUILTINS[Sym('vl-cmdf')] = lispvm.BUILTINS[Sym('command')]
    vm.loads(EXTRA)
    return vm


def load(before=None, setup=None):
    """The edition, optionally onto a session that has already seen
    something else."""
    vm = fresh()
    if before:
        vm.load(before)
    if setup:
        vm.loads(setup)
    vm.load(EDITION)
    return vm


def said(vm):
    return "".join(str(x) for x in vm.printed)


def vis(vm):
    """Toolbar -> the last visibility it was set to."""
    return {str(p[0]): str(p[1])
            for p in (vm.get(Sym('stub:*allvis*')) or [])}


def commands(vm):
    return {str(k)[2:].upper() for k in vm.globals if str(k).startswith('c:')}


def test_both_buttons_go_up():
    print("\nthe hexagon and the triangle, both on the strip")
    vm = load()
    check("both toolbars are shown",
          vis(vm) == {'LazPanel': 'ON', 'TylerDroneSuite': 'ON'})
    check("and it says so on the way in",
          "both buttons are on screen" in said(vm))
    macros = [str(a[-1]) for a in (vm.get(Sym('stub:*allargs*')) or [])]
    check("one runs LAZPANEL", any('_LAZPANEL' in m for m in macros))
    check("the other runs TYLERDRONESUITE",
          any('_TYLERDRONESUITE' in m for m in macros))


def test_the_panel_behind_the_hexagon_actually_works():
    print("\nthe hexagon opens a panel whose tools are really loaded")
    vm = load()
    cmds = commands(vm)
    # the whole point of carrying LAZPASS rather than four files: a
    # hexagon in front of a panel where ten buttons of a hundred and
    # forty-two do anything is a panel that looks broken
    check("the whole roster is here, not a handful (%d commands)"
          % len(cmds), len(cmds) > 100)
    for c in ('TYLERDRONESUITE', 'TYDRN', 'PADDLE', 'AUTODIM',
              'POOL', 'SPA', 'LAZPANEL'):
        check("%s is loaded" % c, c in cmds)
    # lzp:loaded is the roster filtered to what this session really has,
    # so roster == loaded means not one button on the panel is greyed
    vm.loads('(setq t:*all* (lzp:commands)) (setq t:*live* (lzp:loaded))')
    roster = {str(x).upper() for x in (vm.get(Sym('t:*all*')) or [])}
    live = {str(x).upper() for x in (vm.get(Sym('t:*live*')) or [])}
    check("and not one button on the panel is greyed out (%d of %d live)"
          % (len(live), len(roster)), roster and roster == live)


def test_it_states_what_it_wants_rather_than_deducing():
    print("\nAUTO would read the flag its own bundle just raised")
    vm = load()
    check("the bundle did raise it (this is the trap)",
          vm.get(Sym('cal:*build-loading*')) is not None)
    check("but the suite button is stated, not deduced",
          str(vm.get(Sym('lzp:*suitebutton*'))).lower() in ('t', 'true'))
    check("and so is the panel's",
          str(vm.get(Sym('lzp:*panelbutton*'))).lower() in ('t', 'true'))
    # the proof: had it been left to AUTO, there would be no triangle
    vm.loads("(setq lzp:*suitebutton* 'AUTO) (setq t:*w* (lzp:suite-wanted-p))")
    check("AUTO really would have declined it here",
          vm.get(Sym('t:*w*')) is None)


def test_it_lands_right_however_the_session_got_there():
    print("\nboth buttons whatever was loaded before it")
    cases = (("clean machine", None, None),
             ("LAZPASS already loaded", BUNDLE, None),
             ("an older edition left the panel hidden", None,
              '(setq stub:*tbs* (list "LazPanel"))'
              '(setq lzp:*panelbutton* nil)'))
    for label, before, setup in cases:
        got = vis(load(before, setup))
        check("%s: both on screen" % label,
              got.get('LazPanel') == 'ON'
              and got.get('TylerDroneSuite') == 'ON')


def test_lazpass_itself_is_left_alone():
    print("\nLAZPASS still puts up ONE button - this changed nothing there")
    vm = fresh()
    vm.load(BUNDLE)
    check("the bundle raises only the panel's",
          vis(vm) == {'LazPanel': 'ON'})
    check("its suite button is still left to AUTO",
          str(vm.get(Sym('lzp:*suitebutton*'))).upper() == 'AUTO')


def test_it_says_it_is_generated():
    print("\nit is a build, and says so where someone would edit it")
    src = open(EDITION).read()
    check("DO NOT EDIT, and what to edit instead",
          "DO NOT EDIT" in src and "Edit the files under lisp/" in src)
    check("it says what the two buttons do",
          "HEXAGON" in src and "TRIANGLE" in src)
    check("and that LAZPASS's own one-button rule is unchanged",
          "LAZPASS itself puts up" in src)
    check("the footer states both tunables",
          "(setq lzp:*panelbutton* T)" in src
          and "(setq lzp:*suitebutton* T)" in src)


def main():
    print("TYLERDRONE edition tests")
    for fn in (test_both_buttons_go_up,
               test_the_panel_behind_the_hexagon_actually_works,
               test_it_states_what_it_wants_rather_than_deducing,
               test_it_lands_right_however_the_session_got_there,
               test_lazpass_itself_is_left_alone,
               test_it_says_it_is_generated):
        try:
            fn()
        except LispError as e:
            check("%s raised: %s" % (fn.__name__, e), False)

    print("\n%d check(s) failed" % len(failures) if failures
          else "\nall checks passed")
    for f in failures:
        print("  - " + f)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
