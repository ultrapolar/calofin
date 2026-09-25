# Testing a calofin tool

`tests/lispvm.py` is a pure-Python AutoLISP interpreter (~3,400 lines,
stdlib only). Tests load the real `.lsp`, run the real command against a
drawing they build, and assert on the geometry that came out. **No
AutoCAD, no pip, no fixtures.**

## Running

```bash
python3 tests/test_squareup.py                           # lisp/ tier
CALOFIN_LISP_ROOT=shared python3 tests/test_squareup.py  # shared/ tier

make test      # everything, lisp/ tier
make parity    # everything, BOTH tiers -- the standalone-vs-grouped drift check
make fast      # skips the slow files, for the inner loop
python3 tools/run_tests.py -k pool                       # only matching files
```

`CALOFIN_LISP_ROOT` is set **per command, never exported.** Exporting it
points the whole suite at `shared/` and hides a standalone regression.

**Nothing under `tests/` is expected to fail on a clean checkout.** The
authoritative known-red list is `EXPECTED_FAILURES` in
`tools/run_tests.py`, and it is currently **empty** — so a failure IS
your change. A test listed there that starts passing also fails the run,
until its entry is removed.

## The shape of a test file

Every test is a plain script — no unittest, no pytest. It prints
`ok`/`FAIL` per check, collects failures in a list, and exits non-zero.

```python
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError, Sym

HERE = os.path.dirname(__file__)
ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
TOOL = (os.path.join(HERE, '..', 'shared', 'parts', 'SQUAREUP.lsp')
        if ROOT == 'shared'
        else os.path.join(HERE, '..', 'lisp', 'squareup', 'SQUAREUP.lsp'))
LIB  = os.path.join(HERE, '..', 'shared', 'parts', 'CALOFIN-LIB.lsp')

FAILS = []

def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)

def fresh():
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)        # the library FIRST -- the twin calls cal:
    vm.load(TOOL)
    vm.printed = []
    return vm

# ... checks ...

if FAILS:
    print("test_squareup: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_squareup: all checks passed (%s tier)" % ROOT)
```

**The tier switch at the top is mandatory** — without it the file tests
one build twice and `make parity` proves nothing.

## Driving a command

```python
vm.run('c:SQUAREUP', [None, es, [es[0]], 'Wall'])
```

The list is the **scripted answers, consumed in prompt order**. One
element per interactive call (`getpoint`, `getkword`, `getdist`,
`getstring`, `ssget`, ...).

- `None` is Enter / nil.
- A selection is a list of `Ent`s; `ssget "_I"` reads `vm.pickfirst`.
- A string answers a keyword or typed prompt; a number answers `getdist`.
- **A callable is invoked when its prompt is reached**, with the VM as
  its argument. That is the only way to answer a prompt about something
  the run itself drew — a preview has no entity name until it exists.

Two ways `run()` fails you on purpose:

- **`SCRIPT EXHAUSTED at <kind> prompt`** — the command asked more than
  you scripted. Usually a prompt you added.
- **`N scripted answers left over`** — it asked fewer. Usually a prompt
  you removed, or a branch not taken.

After every run it also asserts the command **handed the session back**:
no undo group of its own still open, no error mode still pushed. Either
leftover is the class of defect that only shows up in the *next* command
the drafter runs.

## Delivering an Esc

```python
def esc(vm):
    raise LispError('Function cancelled', vm)

vm = fresh()
vm.handle_errors = True          # REQUIRED -- see below
vm.run('c:SQUAREUP', [None, es, esc])
check("the cancel went through the handler",
      vm.handled_errors and 'cancelled' in vm.handled_errors[0])
```

**`*error*` dispatch is opt-in.** With `vm.handle_errors` left at its
default `False`, the raised error propagates straight out of `run()` and
the command's handler **never runs** -- so an assertion that OSMODE came
back is testing nothing, or failing for the wrong reason. Set it, and
assert on `vm.handled_errors` first so the test proves the handler ran
before it checks what the handler did.

This is how you test the `*error*` path — and you should, because Esc at
a prompt is the likeliest way out of a prompting command and the only
one that never reaches the bottom of the defun. Assert afterwards that
OSMODE, CLAYER and CECOLOR came back.

## Building a drawing

Entities are made by evaluating real AutoLISP through `vm.loads(...)`:

```python
def layer(vm, name, flags=0):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
             ' \'(62 . 4) \'(6 . "Continuous")))' % (name, flags))

def line(vm, a, b, lay='POOL'):
    vm.loads('(entmake (list \'(0 . "LINE") (cons 8 "%s") (list 10 %r %r 0.0)'
             ' (list 11 %r %r 0.0)))' % (lay, a[0], a[1], b[0], b[1]))
```

Layer flag bits: `1` frozen, `4` locked; a negative `62` is switched off.

## What to assert on

| You want | Read |
| --- | --- |
| entities that still exist | `[e for e in vm.entities if e not in vm.deleted]` |
| one entity's DXF groups | `vm.entdata[e]` (list of `Dot`/list groups) |
| every `(command ...)` made | `vm.commands` |
| everything `princ`'d | `vm.printed` |
| every prompt and its answer | `vm.prompts` — `[(prompt, answer), ...]` |
| the drafter's settings | `vm.sysvars['OSMODE']`, `['CLAYER']`, `['CECOLOR']` |
| the implied selection | `vm.pickfirst` |
| dimension styles made current | `vm.dimstyle_log` |

A DXF group helper worth copying:

```python
def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None
```

`vm.sysvars` starts at AutoCAD's real defaults (`OSMODE` 4133,
`UNDOCTL` 5, ...). A name not listed there reads as **nil**, exactly as
AutoCAD answers an unknown one — not 0. `CDATE` is fixed, not the wall
clock, so a routine that stamps a date produces the same output on every
run.

## What a good test for this repo pins

Look at what the tree's own suites assert, because these are the defects
that actually happen here:

1. **The measurement, not the call.** A tool whose job is the angle it
   hands `ROTATE` would pass every test it has with the sign backwards
   if the VM only filed the call away. Turn the geometry for real and
   assert the drawing came out straight.
2. **The settings came back** — on the clean path and after an Esc, and
   that a *second* run restores the drafter's value rather than the
   first run's (the dropped-snapshot bug).
3. **The prompts.** That a prompt was never put (`not any('Highlight' in p
   for p, _ in vm.prompts)`), that Back steps where it should, that the
   wording and keyword set are unchanged.
4. **Both tiers.** Parity is the point of the whole `shared/` build.

## The suites that catch a prompt edit

Run these **first** when you touch any prompt's wording, keyword set or
order — and if the form and the canonical routine disagree, **fix the
form, never the routine**:

```
tests/test_pool_form.py   tests/test_spa_form.py   tests/test_steps_form.py
tests/test_lazform.py     tests/test_lazspa.py     tests/test_lazstep.py
tests/test_back_nav.py
```

## Other suites that pin cross-cutting rules

| Test | Holds |
| --- | --- |
| `test_shared.py` | the whole grouped build in one session + the bundle; fails if a held-back command leaks in |
| `test_ruler_copies.py` | every embedded length-ruler copy, byte for byte against the library |
| `test_theme.py` | the `ink` colour table, and every standalone copy against the library |
| `test_terms.py` | the shop terms: every tool writes the shop's `CalofinTerm-*` spelling, LAZTUNE's Terms page, the knob-over-term precedence, LAZBACKUP's `[Terms]` |
| `test_tunables.py` | the tunables block: one block, knobs in it, state out of it |
| `test_back_nav.py` | Undo beside every Back, the typed predicate, threaded chains walked backwards |
| `test_lazpanel.py` | the panel roster against `headline_commands()` |
| `test_versions.py` | version banners |
| `test_lazdiag*.py` | the failure-report wiring, replay and sweep; `test_lazdiag_selftests.py` the self-test section of a report |
| `test_selftests.py` | every tool's self-test table passes at this tier, and prompted, drew, commanded, wrote and moved nothing |
| `test_lazdiag_machine.py` | THE MACHINE and its hazard flags, the layers touched, the LAZTUNE overrides, the loaded roster, the far/off-plane picks, LOST runs, LAZLAST, and the probe replaying under the report's machine |

## Adding a new test

Name it `tests/test_<tool>.py` — `tools/run_tests.py` globs the
directory, so it is picked up the day it lands with no list to update.
Give it the tier switch, the `check()`/`FAILS` shape above, and a
docstring saying **which defects it exists to catch**; that is the house
style and it is what makes the suite readable.

If it is slow (>~20s), add its filename to `SLOW` in
`tools/run_tests.py`, with its rough seconds: `make fast` skips it, and
the full run starts the heaviest first and allows them the longer
timeout. You do not have to time it yourself -- a run that sees a file
outside `SLOW` take longer than 20s names it in a `note:` line just
above the summary, and one that sees a `SLOW` file finish in under 10s
names that too, so it can leave the set.
