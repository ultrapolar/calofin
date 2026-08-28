#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""editions/TYLERDRONE.lsp -- the drone trace as one download.

TYLERDRONESUITE is three commands out of three different files, and its
screen button is drawn by a fourth.  So there is no single file in the
tree that can be handed to someone who wants only the drone job:
tydrn.lsp on its own has no button and refuses to run, correctly,
because two of its three stages are missing.  This edition is the four
files it really takes, in one APPLOAD.

What is worth testing is the two claims it makes that its members do
not:

  * IT IS COMPLETE.  All three stages are here, so the suite runs
    instead of refusing -- which is the whole reason the file exists.

  * IT PUTS UP ONE BUTTON, AND IT IS THE DRONE'S.  The panel comes
    along because it owns the bitmap and toolbar machinery, but this
    build is not about the panel, so the panel does not take a button.
    LAZPANEL still types the same as ever.

  * IT IS NOT THE LAZPASS BUILD.  cal:*build-loading* is what tells the
    suite it arrived inside the whole toolkit and should NOT have a
    button of its own.  This edition must not raise it, or it would
    suppress the very button it is built around.

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


def load():
    vm = VM()
    vm.loads(STUB)
    lispvm.BUILTINS[Sym('vl-cmdf')] = lispvm.BUILTINS[Sym('command')]
    vm.loads(EXTRA)
    vm.load(EDITION)
    return vm


def said(vm):
    return "".join(str(x) for x in vm.printed)


def test_the_edition_exists_and_loads():
    print("\nthe edition is one file and it loads on its own")
    check("editions/TYLERDRONE.lsp is there", os.path.exists(EDITION))
    vm = load()
    check("it says what it is on the way in",
          "TYLERDRONE edition loaded" in said(vm))


def test_every_stage_is_in_it():
    print("\nall three stages are here, so the suite can actually run")
    vm = load()
    for cmd in ('c:tydrn', 'c:paddle', 'c:autodim', 'c:tylerdronesuite'):
        check("%s is defined" % cmd.upper(), vm.get(Sym(cmd)) is not None)
    check("LAZPANEL came too, for the machinery that draws the button",
          vm.get(Sym('c:lazpanel')) is not None)
    vm.printed = []
    vm.run('c:TYLERDRONESUITE', [])
    out = said(vm)
    check("the suite runs rather than refusing",
          "all three stages ran" in out and "not loaded here" not in out)
    check("and it issues the three commands in order",
          [[str(y) for y in c] for c in vm.commands if c]
          == [['_.TYDRN'], ['_.PADDLE'], ['_.AUTODIM']])


def test_one_button_and_it_is_the_drone_s():
    print("\none thing on the strip, and it is the triangle")
    vm = load()
    tbs = [str(x) for x in (vm.get(Sym('stub:*tbs*')) or [])]
    check("exactly one toolbar", len(tbs) == 1)
    check("and it is the suite's, not the panel's",
          tbs == ['TylerDroneSuite'])
    macro = str((vm.get(Sym('stub:*addargs*')) or ['', '', '', ''])[-1])
    check("its button runs TYLERDRONESUITE", "_TYLERDRONESUITE" in macro)
    check("the panel is off the strip on purpose, not by accident",
          vm.get(Sym('lzp:*panelbutton*')) is None)
    check("and LAZPANEL still types the same as ever",
          vm.get(Sym('c:lazpanel')) is not None)


def test_it_is_not_the_lazpass_build():
    print("\nit must not raise the flag that suppresses its own button")
    vm = load()
    check("cal:*build-loading* is not raised",
          vm.get(Sym('cal:*build-loading*')) is None)
    # which is what leaves the suite wanting a button here
    vm.loads('(setq t:*w* (lzp:suite-wanted-p))')
    check("so the suite wants its button", vm.get(Sym('t:*w*')) is not None)


def test_the_deferred_button_call_really_moved():
    print("\nthe load-time button call is deferred, not duplicated")
    src = open(EDITION).read()
    # LAZPANEL puts its buttons up as it loads, which is too early here:
    # the edition has not said which buttons it wants yet.  The build
    # takes that call out and makes it again in the footer -- and the
    # same call appears INDENTED inside c:LAZBUTTON, which must be left
    # exactly as it was or the command is cut in half.
    top = re.findall(r"^\(vl-catch-all-apply 'lzp:buttons-init nil\)$",
                     src, re.M)
    check("exactly one top-level call, the footer's", len(top) == 1)
    check("it comes after the tunable is set",
          src.index("(setq lzp:*panelbutton* nil)")
          < src.rindex("(vl-catch-all-apply 'lzp:buttons-init nil)"))
    check("c:LAZBUTTON's own call is untouched",
          "(setq tbs (vl-catch-all-apply 'lzp:buttons-init nil))" in src)
    check("and the build says where the moved one went",
          "TAKEN OUT here" in src)


def test_it_says_it_is_generated():
    print("\nit is a build, and says so where someone would edit it")
    src = open(EDITION).read()
    check("DO NOT EDIT, and what to edit instead",
          "DO NOT EDIT" in src and "Edit the files under lisp/" in src)
    check("it lists what it carries, with versions",
          "tydrn.lsp" in src and "LAZPANEL.lsp" in src)
    check("and points at LAZPASS for the whole toolkit",
          "LAZPASS.lsp" in src)


def main():
    print("TYLERDRONE edition tests")
    for fn in (test_the_edition_exists_and_loads,
               test_every_stage_is_in_it,
               test_one_button_and_it_is_the_drone_s,
               test_it_is_not_the_lazpass_build,
               test_the_deferred_button_call_really_moved,
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
