#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Enter never erases the demo -- one question, in all nine tools.

Nine tutorials end by offering to take their demo back out of the
drawing, and they used to ask it three ways with opposite Enter
defaults:

  * "Keep the demo drawing? [Keep/Erase] <Keep>"    LISPLAB,
                                                    TUTORIALPERPPTS,
                                                    TUTORIALCPERPPTS
  * "Keep the demo drawing to poke at? [Yes/No] <No>" TUTORIALABHD --
                                                    Enter ERASED
  * "Erase the demo pool and its bead? [Yes/No] <Yes>" TUTORIALAUTOBEAD --
                                                    Enter erased
  * "Erase the demonstration? [Yes/No] <No>"        TUTORIALPADDLE
  * "Erase the practice drawing now? [Yes/No] <Yes>" TUTORIALDIMCHECK,
  * "Erase the practice drawing [Yes/No] <Yes>"     TUTORIALLINFINCHECK,
                                                    TUTORIALSPACHECK --
                                                    Enter erased

The owner's rule (STANDARDS section 3, "Demo cleanup"): ENTER NEVER
ERASES THE DEMO.  Every one now asks

    Erase the demo drawing? [Yes/No] <No>

-- "practice drawing" in the three check tutorials, which is what they
call the thing -- and only a typed Yes erases.

For each of the nine this file DRIVES THE WHOLE TUTORIAL in the VM to
that question (no cleanup helper is called directly), then:

  * checks the question is asked in exactly the canonical words;
  * answers Enter, and shows the demo's entities are all still there;
  * answers Yes, and shows they are gone.

One stand-in, said here rather than hidden: TUTORIALAUTOBEAD's bead
build runs OFFSET, which the VM does not model, so autobead-build is
replaced by a stub that draws nothing (exactly what test_fix_steps.py
6a does).  The demo's sample pool -- the five lines the cleanup is
there to take away -- is still drawn by the tutorial itself.

Run: python3 tests/test_demo_cleanup.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from lispvm import VM, Dot, LispError, BUILTINS  # noqa: E402

#: the VM's builtins as shipped: the perp tutorials' drivers patch some
#: (command, tblobjname ...) globally, and every tour starts from these
STOCK = dict(BUILTINS)

LISP = os.path.join(REPO, 'lisp')


def path(*p):
    return os.path.join(LISP, *p)


DEMO_Q = "Erase the demo drawing? [Yes/No] <No>: "
PRACTICE_Q = "Erase the practice drawing? [Yes/No] <No>: "

#: what is not a drawing object: table records the run made
TABLES = {'LAYER', 'STYLE', 'DIMSTYLE', 'LTYPE', 'APPID', 'BLOCK_RECORD',
          'UCS', 'VIEW'}

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else g[1:]
    return None


def made(vm, mark):
    """The drawing objects the run added that are still in the drawing."""
    return [e for e in vm.entities[mark:]
            if e not in vm.deleted and dxf(vm, e, 0) not in TABLES]


def asked(vm, question):
    return [p for p, _ in vm.prompts if p and question in p]


# ---------------------------------------------------------------- drivers
# Each takes the answer for the cleanup question (None = Enter) and
# returns (vm, mark): the VM after the tour, and where its drawing began.

class Tour(VM):
    """LISPLAB answers by prompt (as tests/test_lisplab.py does): its
    pause count moves with every paragraph a lesson gains."""

    def __init__(self, ending):
        super().__init__()
        self.layer_records = {}
        self.ending = ending

    def pop_script(self, prompt, kind):
        ans = {'getstring': '', 'getpoint': [0.0, 0.0, 0.0],
               'getdist': 5.0}.get(kind)
        if kind == 'getkword':
            if 'Which lesson' in prompt:
                ans = 'Both'
            elif 'Checks prints' in prompt:
                ans = 'Demo'
            elif 'Erase the demo' in prompt:
                ans = self.ending
            else:
                raise LispError(f'unscripted question: {prompt!r}', self)
        self.script = [ans]
        return super().pop_script(prompt, kind)


def lisplab(ending):
    vm = Tour(ending)
    vm.load(path('lisplab', 'LISPLAB.lsp'))
    vm.run('c:LISPLAB', [])
    return vm, 0


def perp_tutorial(fname, cmd, pauses):
    def drive(ending):
        import test_perp_points as tpp
        tpp.install_entity_builtins()
        tpp.install_curve_builtins()
        vm = VM()
        tpp.install_command(vm)
        vm.load(path('perp_points', fname))
        vm.handle_errors = True
        vm.run(cmd, ['Demo', [0.0, 0.0, 0.0], None] + [None] * pauses
               + [ending])
        return vm, 0
    return drive


def abhd(ending):
    vm = VM()
    vm.load(path('abhd', 'abhd.lsp'))
    vm.run('c:TUTORIALABHD', ['Demo', (0.0, 0.0)] + [None] * 5 + [ending])
    return vm, 0


def autobead(ending):
    vm = VM()
    vm.load(path('autobead', 'AUTOBEAD.lsp'))
    # the stand-in the docstring names: OFFSET is not modelled
    vm.loads("(defun autobead-build (ss dir side some hold) 0)")
    vm.run('c:TUTORIALAUTOBEAD',
           ["Demo", (10.0, 10.0, 0.0), None, None, (150.0, 80.0, 0.0),
            None, ending])
    return vm, 0


def paddle(ending):
    vm = VM()
    vm.load(path('paddle', 'PADDLE.lsp'))
    # pause, demo? Yes, the spot, four pauses, then the cleanup
    vm.run('c:TUTORIALPADDLE', [None, None, [0.0, 0.0, 0.0], None, None,
                                None, None, ending])
    return vm, 0


def check_tutorial(fname, folder, cmd, faults):
    def drive(ending):
        vm = VM()
        vm.load(path(folder, fname))
        vm.run(cmd, ["Demo", [500.0, 0.0, 0.0]] + [None] * (faults - 1)
               + [ending])
        return vm, 0
    return drive


def spacheck(ending):
    vm = VM()
    vm.load(path('spacheck', 'SPACHECK.lsp'))
    vm.run('c:TUTORIALSPACHECK',
           ['Demo', [0.0, 0.0, 0.0], '', '', '',   # the three faults
            'Yes', None, None,                     # scan the whole drawing
            ending])
    return vm, 0


TOOLS = [
    ("LISPLAB", lisplab, DEMO_Q),
    ("TUTORIALPERPPTS",
     perp_tutorial('tutorial_perp_points.lsp', 'c:TUTORIALPERPPTS', 7),
     DEMO_Q),
    ("TUTORIALCPERPPTS",
     perp_tutorial('tutorial_cperp_points.lsp', 'c:TUTORIALCPERPPTS', 4),
     DEMO_Q),
    ("TUTORIALABHD", abhd, DEMO_Q),
    ("TUTORIALAUTOBEAD", autobead, DEMO_Q),
    ("TUTORIALPADDLE", paddle, DEMO_Q),
    ("TUTORIALDIMCHECK",
     check_tutorial('dimcheck.lsp', 'dimcheck', 'c:TUTORIALDIMCHECK', 8),
     PRACTICE_Q),
    ("TUTORIALLINFINCHECK",
     check_tutorial('linfincheck.lsp', 'linfincheck',
                    'c:TUTORIALLINFINCHECK', 9),
     PRACTICE_Q),
    ("TUTORIALSPACHECK", spacheck, PRACTICE_Q),
]


def tour(name, drive, ending):
    BUILTINS.clear()
    BUILTINS.update(STOCK)
    try:
        return drive(ending)
    except LispError as e:
        raise AssertionError(f"[{name} ending={ending!r}] "
                             f"{str(e).splitlines()[0]}") from None


#: every drawing object live in the VM at the moment the cleanup question
#: was asked -- what an Enter must leave standing, all of it, not just some
AT_QUESTION = {}
_POP = VM.pop_script


def _snap(self, prompt, kind):
    q = AT_QUESTION.get('question')
    if q and prompt and q in prompt:
        AT_QUESTION['live'] = [e for e in self.entities
                               if e not in self.deleted
                               and dxf(self, e, 0) not in TABLES]
    return _POP(self, prompt, kind)


VM.pop_script = _snap

for name, drive, question in TOOLS:
    print(f"{name} -- the cleanup question")
    AT_QUESTION.clear()
    AT_QUESTION['question'] = question
    vm, mark = tour(name, drive, None)
    kept = made(vm, mark)
    live = [e for e in AT_QUESTION.get('live', [])
            if e in vm.entities[mark:]]
    gone = [e for e in live if e in vm.deleted]
    check(f"{name}: asks {question.strip()!r}, once",
          len(asked(vm, question)) == 1,
          [p for p, _ in vm.prompts if p and 'rase' in p])
    check(f"{name}: Enter keeps the demo -- all {len(live)} object(s) "
          "on the drawing at the question are still there",
          live and not gone and len(kept) >= len(live),
          (len(live), len(gone), len(kept)))
    AT_QUESTION.clear()

    vm, mark = tour(name, drive, "Yes")
    left = made(vm, mark)
    check(f"{name}: Yes erases it", not left,
          [(dxf(vm, e, 0), dxf(vm, e, 8)) for e in left][:8])

if failures:
    print(f"\n{len(failures)} demo-cleanup check(s) FAILED")
    sys.exit(1)
print("\nall demo-cleanup checks passed")
