"""Form-driven steps: prove the palette path draws what the prompts
draw for CORNERSTP, HEMISTEP and NORMIESTEP - the step COUNT included.

The count is the interesting key.  At the command line it is never a
question: the tread loop repeats "Step N - step tread <Enter = done>"
until Enter, so the number of steps is only ever emergent.  A form has
that number as a field, so the stores give it a key of its own -
(steps . 3) - and the loop stops itself after that many steps instead
of waiting for an Enter nobody typed.  This file is what says that
auto-done really is Enter: same geometry, and no "Step 4" prompt ever
shown.

Everything else follows the pool:*form* contract (POOL.LSP, proved by
test_pool_form.py), one store per tool under its own prefix:
*cs-form* / *hs-form* / *ns-form*, three states per key (absent = ask,
nil = what Enter means there, value = the answer), consume-once, and
clear-on-exit so nothing leaks into the next run.

Scenario numbers below:
  1. full form == prompts, entity for entity, per tool
  2. the count rule: (steps . 3) + treads -> exactly 3, no "Step 4"
  3. partial form: treads off the sheet, depths at the keyboard
  4. consume-once / no-leak, and the run-with-answers entry point
  5. NORMIESTEP's treat / treat-sz / cutgiven, aliases included

Run against the grouped tier with:
    CALOFIN_LISP_ROOT=shared python3 tests/test_steps_form.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError, parse_all  # noqa: E402

HERE = os.path.dirname(__file__)
CORNERSTP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'CORNERSTP.lsp')
HEMISTEP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'HEMISTEP.lsp')
NORMIESTEP = os.path.join(HERE, '..', 'lisp', 'cornerstp', 'NORMIESTEP.lsp')

#: the store each command reads, by command name
STORE = {'c:CORNERSTP': '*cs-form*',
         'c:HEMISTEP': '*hs-form*',
         'c:NORMIESTEP': '*ns-form*'}

#: the pick and the numbers, same as test_cornerstp_profile.py
PICK = (500.0, 400.0)
DEPTHS = [7.5, 10.75, 10.75, 10.5]     # 3 steps -> 4 depths
TREADS = [24.0, 24.0, 24.0]


def fresh(path):
    vm = VM()
    vm.load(path)                       # CALOFIN_LISP_ROOT picks the tier
    for s in ('STANDARD INCHES', 'SIDE STANDARD'):
        vm.tables['DIMSTYLE'].add(s)
    vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48.0
    return vm


def walls(vm, pair):
    """The geometry the command selects: two corner walls for CORNERSTP,
    a single base line for the other two."""
    vm.loads('(entmake (list (cons 0 "LINE")'
             ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
    if pair:
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 0.0 0.0) (list 11 0.0 200.0 0.0)))')
    return list(vm.entities)


def drive(path, cmd, pair, script, form=None, label=""):
    """One run: WALLS in the script becomes the selection, FORM (a
    quoted alist as LISP text) arms the tool's store first."""
    vm = fresh(path)
    if form:
        vm.eval(parse_all("(setq %s %s)" % (STORE[cmd], form))[0])
    script = list(script)
    if script and script[0] == 'WALLS':
        script[0] = walls(vm, pair)
    else:
        walls(vm, pair)                # fixture drawn even when reused
    try:
        vm.run(cmd, script)
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None
    return vm


def snapshot(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for p in vm.entdata[e]:
            if isinstance(p, Dot):
                d.setdefault(p.a, p.b)
        out.append(tuple(sorted((str(k), repr(v)) for k, v in d.items())))
    return out


def same(a, b, label):
    sa, sb = snapshot(a), snapshot(b)
    if sa != sb:
        only_a = [x for x in sa if x not in sb]
        only_b = [x for x in sb if x not in sa]
        raise AssertionError(
            "[%s] geometry differs: %d only from the prompts, %d only from "
            "the form\n  prompts: %s\n  form:    %s"
            % (label, len(only_a), len(only_b), only_a[:2], only_b[:2]))
    if not sa:
        raise AssertionError("[%s] nothing was drawn" % label)
    return sa


def new_lines(vm, keep):
    """LINE entities created after the KEEP pre-made fixture ones."""
    out = []
    for e in vm.entities[keep:]:
        if e in vm.deleted:
            continue
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'LINE'
               for g in data):
            pts = {g[0]: tuple(g[1:3]) for g in data
                   if isinstance(g, list) and g and g[0] in (10, 11)}
            out.append((pts.get(10), pts.get(11)))
    return out


def tread_asked(vm):
    return [p for p, _ in vm.prompts if 'step tread' in p]


def depth_asked(vm):
    return [p for p, _ in vm.prompts
            if 'step depth' in p or 'Depth after' in p]


# the prompt-side scripts, verbatim from test_cornerstp_profile.py
def cornerstp_prompts(dims="No"):
    return (['WALLS', None, dims, "No"]
            + [24.0, None] * 3
            + [None, "Yes"] + DEPTHS + [PICK])


def hemistep_prompts(dims="No"):
    return ['WALLS', (100.0, 50.0), dims, 60.0]  \
        + [24.0, 60.0] * 3 + [None, None, "Yes"] + DEPTHS + [PICK]


def normiestep_prompts(dims="No"):
    return ['WALLS', (100.0, 50.0), 60.0, "Square", dims,
            24.0, 24.0, 24.0, None, "Yes"] + DEPTHS + [PICK]


# the same answers as form stores.  Every key the prompt side types is
# here; the scripts keep only the selection and the picks.
CS_FULL = """'((direction . nil) (dims . "No") (bench . "No") (steps . 3)
              (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
              (width1 . nil) (width2 . nil) (width3 . nil)
              (profile . "Yes")
              (depth1 . 7.5) (depth2 . 10.75) (depth3 . 10.75)
              (depthafter . 10.5))"""

HS_FULL = """'((dims . "No") (wallwidth . 60.0) (steps . 3)
              (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
              (width1 . 60.0) (width2 . 60.0) (width3 . 60.0)
              (crown . nil) (profile . "Yes")
              (depth1 . 7.5) (depth2 . 10.75) (depth3 . 10.75)
              (depthafter . 10.5))"""

NS_FULL = """'((width . 60.0) (treat . "Square") (dims . "No") (steps . 3)
              (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
              (profile . "Yes")
              (depth1 . 7.5) (depth2 . 10.75) (depth3 . 10.75)
              (depthafter . 10.5))"""

TOOLS = [
    ('CORNERSTP', CORNERSTP, 'c:CORNERSTP', True,
     cornerstp_prompts, CS_FULL, ['WALLS', PICK]),
    ('HEMISTEP', HEMISTEP, 'c:HEMISTEP', False,
     hemistep_prompts, HS_FULL, ['WALLS', (100.0, 50.0), PICK]),
    ('NORMIESTEP', NORMIESTEP, 'c:NORMIESTEP', False,
     normiestep_prompts, NS_FULL, ['WALLS', (100.0, 50.0), PICK]),
]


# --------------------------------------------------------------------
# 1.  Full form == the command line, per tool: the sheet answers every
#     question and the script keeps only the selection and the picks.
# --------------------------------------------------------------------
print("== 1. full form == prompts, per tool ==")

for name, path, cmd, pair, prompts_of, full, form_script in TOOLS:
    a = drive(path, cmd, pair, prompts_of(), label=name + " prompts")
    b = drive(path, cmd, pair, form_script, form=full,
              label=name + " form")
    ents = same(a, b, name + " full form")
    assert not tread_asked(b), \
        "%s still asked a tread: %r" % (name, tread_asked(b))
    assert not depth_asked(b), \
        "%s still asked a depth: %r" % (name, depth_asked(b))
    print("   %s: %d entities identical; form answered %d of %d questions"
          % (name, len(ents), len(a.prompts) - len(b.prompts),
             len(a.prompts)))

# ...and with the dims on, so the dimension path is equal too
a = drive(CORNERSTP, 'c:CORNERSTP', True, cornerstp_prompts(dims="Yes"),
          label="CORNERSTP dims prompts")
b = drive(CORNERSTP, 'c:CORNERSTP', True, ['WALLS', PICK],
          form=CS_FULL.replace('(dims . "No")', '(dims . "Yes")'),
          label="CORNERSTP dims form")
same(a, b, "CORNERSTP full form, dims on")
print("   CORNERSTP with dims on: dimensions identical too")


# --------------------------------------------------------------------
# 2.  THE COUNT RULE.  (steps . 3) with every tread supplied: exactly
#     three steps land and no "Step 4" prompt is ever shown - the loop
#     answers its own Enter.
# --------------------------------------------------------------------
print("== 2. (steps . 3): three steps, and no Step 4 prompt ==")

COUNT_FORMS = [
    ('CORNERSTP', CORNERSTP, 'c:CORNERSTP', True, ['WALLS'], 2,
     """'((direction . nil) (dims . "No") (bench . "No") (steps . 3)
         (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
         (width1 . nil) (width2 . nil) (width3 . nil)
         (profile . "No"))""",
     lambda ls: ls),                       # every new line is a tread
    ('HEMISTEP', HEMISTEP, 'c:HEMISTEP', False,
     ['WALLS', (100.0, 50.0)], 1,
     """'((dims . "No") (wallwidth . nil) (steps . 3)
         (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
         (width1 . 60.0) (width2 . 60.0) (width3 . 60.0)
         (crown . nil) (profile . "No"))""",
     lambda ls: ls),                       # chords only; boundary is a pline
    ('NORMIESTEP', NORMIESTEP, 'c:NORMIESTEP', False,
     ['WALLS', (100.0, 50.0)], 1,
     """'((width . 60.0) (treat . "Square") (dims . "No") (steps . 3)
         (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
         (profile . "No"))""",
     # the sides run square off the wall; the treads are the level lines
     lambda ls: [s for s in ls if abs(s[0][1] - s[1][1]) < 1e-9]),
]

for name, path, cmd, pair, script, keep, form, treads_of in COUNT_FORMS:
    vm = drive(path, cmd, pair, script, form=form, label=name + " count")
    assert not any('Step 4' in p for p, _ in vm.prompts), \
        "%s asked about a Step 4: %r" % (name, vm.prompts)
    assert not tread_asked(vm), \
        "%s asked a tread despite the count: %r" % (name, tread_asked(vm))
    got = treads_of(new_lines(vm, keep))
    assert len(got) == 3, \
        "%s drew %d treads, wanted exactly 3: %r" % (name, len(got), got)
    print("   %s: exactly 3 treads, zero step prompts" % name)

# outside in, where step 1 is placed by the outermost width and the
# treads walk back in from step 2 - the count still stops the walk
vm = drive(CORNERSTP, 'c:CORNERSTP', True, ['WALLS'],
           form="""'((direction . "Outside") (dims . "No")
                     (outerwidth . 48.0) (steps . 3)
                     (tread2 . 6.0) (tread3 . 6.0)
                     (width2 . nil) (width3 . nil)
                     (profile . "No"))""",
           label="outside-in count")
ref = drive(CORNERSTP, 'c:CORNERSTP', True,
            ['WALLS', "Outside", "No", 48.0,
             6.0, None, 6.0, None, None, "No"],
            label="outside-in prompts")
same(ref, vm, "outside-in count == prompts")
assert not any('Step 4' in p for p, _ in vm.prompts), \
    "outside in asked about a Step 4"
assert len(new_lines(vm, 2)) == 3, "outside in did not draw 3 steps"
print("   CORNERSTP outside in: outermost + 2 walked in, stopped at 3")


# --------------------------------------------------------------------
# 3.  Half-filled sheet: the plan comes off the form, the depths are
#     still read off the section at the keyboard.
# --------------------------------------------------------------------
print("== 3. partial form: treads off the sheet, depths typed ==")

PARTIALS = [
    ('CORNERSTP', CORNERSTP, 'c:CORNERSTP', True, cornerstp_prompts,
     """'((direction . nil) (dims . "No") (bench . "No") (steps . 3)
         (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
         (width1 . nil) (width2 . nil) (width3 . nil)
         (profile . "Yes"))""",
     ['WALLS'] + DEPTHS + [PICK]),
    ('HEMISTEP', HEMISTEP, 'c:HEMISTEP', False, hemistep_prompts,
     """'((dims . "No") (wallwidth . 60.0) (steps . 3)
         (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
         (width1 . 60.0) (width2 . 60.0) (width3 . 60.0)
         (crown . nil) (profile . "Yes"))""",
     ['WALLS', (100.0, 50.0)] + DEPTHS + [PICK]),
    ('NORMIESTEP', NORMIESTEP, 'c:NORMIESTEP', False, normiestep_prompts,
     """'((width . 60.0) (treat . "Square") (dims . "No") (steps . 3)
         (tread1 . 24.0) (tread2 . 24.0) (tread3 . 24.0)
         (profile . "Yes"))""",
     ['WALLS', (100.0, 50.0)] + DEPTHS + [PICK]),
]

for name, path, cmd, pair, prompts_of, form, script in PARTIALS:
    a = drive(path, cmd, pair, prompts_of(), label=name + " prompts")
    c = drive(path, cmd, pair, script, form=form, label=name + " partial")
    same(a, c, name + " partial form")
    assert not tread_asked(c), \
        "%s asked a tread the form supplied: %r" % (name, tread_asked(c))
    assert len(depth_asked(c)) == len(DEPTHS), \
        "%s should have asked all %d depths, asked %d" \
        % (name, len(DEPTHS), len(depth_asked(c)))
    print("   %s: treads silent, %d depths still asked"
          % (name, len(depth_asked(c))))


# --------------------------------------------------------------------
# 4.  Answers must not survive the command - by either entry point -
#     and the next plain run asks everything again.
# --------------------------------------------------------------------
print("== 4. consume-once: nothing leaks into the next run ==")

RUNNERS = {'c:CORNERSTP': 'cs-run-with-answers',
           'c:HEMISTEP': 'hs-run-with-answers',
           'c:NORMIESTEP': 'ns-run-with-answers'}

for name, path, cmd, pair, prompts_of, full, form_script in TOOLS:
    # the direct path: setq the store, call the command
    vm = fresh(path)
    ws = walls(vm, pair)
    vm.eval(parse_all("(setq %s %s)" % (STORE[cmd], full))[0])
    vm.run(cmd, [ws] + form_script[1:])
    leaked = vm.globals.get(STORE[cmd])
    assert not leaked, \
        "%s: %s still armed after the run: %r" % (name, STORE[cmd], leaked)
    # a second, plain run in the same session prompts everything
    vm.run(cmd, [ws] + prompts_of()[1:])
    assert tread_asked(vm), "%s: the second run never asked a tread" % name
    assert depth_asked(vm), "%s: the second run never asked a depth" % name
    assert any('Dimension the steps?' in p for p, _ in vm.prompts), \
        "%s: the second run never asked about dims" % name

    # the run-with-answers entry point clears too
    g = fresh(path)
    ws = walls(g, pair)
    g.script = [ws] + form_script[1:]
    g.prompts = []
    g.eval(parse_all("(%s %s)" % (RUNNERS[cmd], full))[0])
    assert not g.script, \
        "%s: run-with-answers left script over: %r" % (name, g.script)
    leaked = g.globals.get(STORE[cmd])
    assert not leaked, \
        "%s: run-with-answers left the store armed: %r" % (name, leaked)
    assert snapshot(g), "%s: run-with-answers drew nothing" % name
    print("   %s: store empty after both entry points; plain run re-asks"
          % name)


# --------------------------------------------------------------------
# 5.  NORMIESTEP's corner treatment off the form: treat, its number
#     treat-sz, and cutgiven saying which leg that number is - with
#     the hidden aliases normalized exactly as typing them would be.
# --------------------------------------------------------------------
print("== 5. NORMIESTEP treat / treat-sz / cutgiven from the form ==")

CUTFACE = 9.0 * math.sqrt(2.0)


def ns_corner(script, form=None, label=""):
    """Corner mode on a square corner, like test_normiestep_corner.py:
    base along +X, side along +Y, steps run off the base."""
    vm = fresh(NORMIESTEP)
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 200.0 0.0 0.0)))')
    vm.loads('(entmake (list (cons 0 "LINE") (list 10 0.0 0.0 0.0)'
             ' (list 11 0.0 200.0 0.0)))')
    if form:
        vm.eval(parse_all("(setq *ns-form* %s)" % form)[0])
    try:
        vm.run('c:NORMIESTEP', [list(vm.entities)] + script)
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None
    return vm


BASE_REST = [(100.0, 0.0)]             # pick the base line, then...

# a Cut corner given as its offset, the treatment spelled DIAGONAL
a = ns_corner(BASE_REST + [60.0, "Cut", "Offset", 9.0, "No",
                           12.0, 12.0, None, "No"], label="cut prompts")
b = ns_corner(BASE_REST,
              form="""'((width . 60.0) (treat . "DIAGONAL")
                        (cutgiven . "Offset") (treat-sz . 9.0)
                        (dims . "No") (steps . 2)
                        (tread1 . 12.0) (tread2 . 12.0)
                        (profile . "No"))""",
              label="cut form")
same(a, b, "Cut by offset, treat spelled DIAGONAL")
assert not any('How should' in p for p, _ in b.prompts), \
    "the treatment was asked despite the form answering it"
assert not any('Is the cut given' in p for p, _ in b.prompts), \
    "cutgiven was asked despite the form answering it"
assert not any('Offset back' in p or 'Cut face' in p
               for p, _ in b.prompts), \
    "treat-sz was asked despite the form answering it"
print("   Cut: DIAGONAL normalized, offset 9 taken, nothing asked")

# the same corner given as its cut FACE - cutgiven flips the meaning
c = ns_corner(BASE_REST + [60.0, "Cut", "Cut", CUTFACE, "No",
                           12.0, 12.0, None, "No"], label="face prompts")
d = ns_corner(BASE_REST,
              form="""'((width . 60.0) (treat . "Cut")
                        (cutgiven . "Cut") (treat-sz . %.15f)
                        (dims . "No") (steps . 2)
                        (tread1 . 12.0) (tread2 . 12.0)
                        (profile . "No"))""" % CUTFACE,
              label="face form")
same(c, d, "Cut by face length")
print("   Cut: cutgiven Cut reads treat-sz as the face length")

# a Radius corner, the treatment spelled ROUNDED
e = ns_corner(BASE_REST + [60.0, "Radius", 6.0, "No",
                           12.0, 12.0, None, "No"], label="radius prompts")
f = ns_corner(BASE_REST,
              form="""'((width . 60.0) (treat . "ROUNDED")
                        (treat-sz . 6.0) (dims . "No") (steps . 2)
                        (tread1 . 12.0) (tread2 . 12.0)
                        (profile . "No"))""",
              label="radius form")
same(e, f, "Radius, treat spelled ROUNDED")
assert not any('Radius for' in p for p, _ in f.prompts), \
    "the radius was asked despite treat-sz supplying it"
print("   Radius: ROUNDED normalized, treat-sz is the radius")

# a word the question does not offer falls through to the prompt
g = ns_corner(BASE_REST + ["Square"],
              form="""'((width . 60.0) (treat . "Fancy")
                        (dims . "No") (steps . 2)
                        (tread1 . 12.0) (tread2 . 12.0)
                        (profile . "No"))""",
              label="bad treat")
h = ns_corner(BASE_REST + [60.0, "Square", "No", 12.0, 12.0, None, "No"],
              label="square prompts")
same(h, g, "unknown treat word")
assert any('How should' in p for p, _ in g.prompts), \
    "an unknown treatment should have fallen through to the prompt"
print("   'Fancy' ignored, the treatment asked as usual")


print("\nALL STEPS FORM SCENARIOS PASSED")
