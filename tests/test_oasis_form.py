"""Form-driven OASIS: prove a filled-in sheet draws what the command
line draws, and that a half-filled one only shortens the run.

OASIS is the third routine to grow the receiving end POOL and SPA
already had -- oasis:*form*, oasis:run-with-answers -- and it is the
one whose questions are not a fixed list: which slots are asked, and
in what order, is the shape's own business (oasis:steps), so the same
store has to serve six rings that ask six different sets.  That is
what most of this file is about.

The reference numbers are the ones test_oasis.py reads off the
drawings: a 40'-0" x 20'-0" centre-bulge pool, the 36'-11" x 28'-8"
top-right one, the two clouds off a 30'-0" x 20'-0" envelope, the two
kidneys off a 388 x 214 one, and the NXT cloud off 40'-0" x 20'-0"
with three 8' lobes.  Run: python3 tests/test_oasis_form.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'oasis', 'OASIS.lsp')

BASE = (0.0, 0.0, 0.0)
#: Enter at "Add the bottom of the pool?", whose default is No
NOBOTTOM = None


def newvm():
    vm = VM()
    vm.tables['DIMSTYLE'].add('CROSS DIMENSIONS')
    vm.load(LSP)
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


def lisp(v):
    if v is None:
        return 'nil'
    if isinstance(v, str):
        return '"%s"' % v
    return '%.10f' % float(v)


def alist(pairs):
    return '(list %s)' % ' '.join("(cons '%s %s)" % (k, lisp(v))
                                  for k, v in pairs)


def by_prompts(script):
    vm = newvm()
    vm.run('c:OASIS', list(script))
    return vm


# The whole documented entry point, not a shortcut into it:
# oasis:run-with-answers takes its alist as an argument, and vm.run
# calls a defun with none -- so it goes through a shim that supplies it.
SHIM = '(defun test:go () (oasis:run-with-answers test:*f*))'


def run_form(pairs, script):
    vm = newvm()
    vm.loads(SHIM)
    vm.loads('(setq test:*f* %s)' % alist(pairs))
    vm.run('test:go', list(script))
    return vm


# ---------------------------------------------------------------------
#: every family, as (label, form pairs, typed script after the base
#: point).  The head of a typed run is the shape, the sub-type where
#: there is one, and simple-or-complex; the form answers all three.
CASES = [
    ("center",
     [('shape', 'Center'), ('detail', 'Simple'),
      ('x', 480.0), ('y', 240.0), ('rl', 96.0), ('rt', 132.0),
      ('rr', 108.0), ('ftl', 72.0), ('ftr', 36.0), ('fbc', 60.0)],
     ['Center', 'Simple', BASE,
      480.0, 240.0, 96.0, 132.0, 108.0, 72.0, 36.0, 60.0]),
    ("top-right",
     [('shape', 'TopRight'), ('detail', 'Simple'),
      ('x', 443.0), ('y', 344.0), ('rl', 108.0), ('rt', 96.0),
      ('rr', 108.0), ('ftl', 96.0), ('ftr', 96.0), ('fbc', 120.0)],
     ['TopRight', 'Simple', BASE,
      443.0, 344.0, 108.0, 96.0, 108.0, 96.0, 96.0, 120.0]),
    ("straight-bottom cloud",
     [('shape', 'Cloud'), ('sub', 'Straight'), ('detail', 'Simple'),
      ('x', 360.0), ('y', 240.0), ('rr', 84.0), ('ftl', 72.0)],
     ['CLoud', 'Straight', 'Simple', BASE, 360.0, 240.0, 84.0, 72.0]),
    ("rounded-bottom cloud",
     [('shape', 'Cloud'), ('sub', 'Rounded'), ('detail', 'Simple'),
      ('x', 360.0), ('y', 240.0), ('rr', 84.0), ('ftl', 72.0),
      ('fbc', 144.0)],
     ['CLoud', 'Rounded', 'Simple', BASE,
      360.0, 240.0, 84.0, 72.0, 144.0]),
    ("true kidney",
     [('shape', 'Kidney'), ('sub', 'True'), ('detail', 'Simple'),
      ('x', 388.0), ('y', 214.0), ('rt', 324.0), ('fbc', 48.0)],
     ['Kidney', 'True', 'Simple', BASE, 388.0, 214.0, 324.0, 48.0]),
    ("asymmetric kidney",
     [('shape', 'Kidney'), ('sub', 'Asymmetric'), ('detail', 'Simple'),
      ('x', 388.0), ('y', 214.0), ('rl', 96.0), ('rr', 72.0),
      ('fbc', 48.0)],
     ['Kidney', 'Asymmetric', 'Simple', BASE,
      388.0, 214.0, 96.0, 72.0, 48.0]),
    ("NXT cloud",
     [('shape', 'NXTcloud'), ('detail', 'Simple'),
      ('x', 480.0), ('y', 240.0), ('rl', 96.0), ('rt', 96.0),
      ('rr', 96.0), ('fbc', 60.0), ('fbr', 60.0), ('ftr', 60.0),
      ('ftl', 60.0)],
     ['NXTcloud', 'Simple', BASE, 480.0, 240.0, 96.0, 96.0, 96.0,
      60.0, 60.0, 60.0, 60.0]),
]

print("== a filled-in sheet draws the pool the prompts draw ==")
for label, pairs, script in CASES:
    a = run_form(pairs, [BASE, NOBOTTOM])
    b = by_prompts(script + [NOBOTTOM])
    sa, sb = snapshot(a), snapshot(b)
    assert sa, "%s: the form run drew nothing" % label
    assert sa == sb, (
        "%s: the form drew a different pool -- %d entities from the sheet, "
        "%d from the prompts" % (label, len(sa), len(sb)))
    asked = [p for p, _ in a.prompts]
    assert len(asked) == 2, (
        "%s: a full sheet should leave only the base point and the "
        "pool-bottom gate, and %d question(s) were asked: %r"
        % (label, len(asked), asked))
    assert not a.globals.get('oasis:*form*'), \
        "%s: oasis:*form* survived the run" % label
    print("   %-22s %3d entities, 2 questions left" % (label, len(sa)))


print("== a half-filled one only shortens the run ==")
# the same centre-bulge pool with the three tangent radii left blank:
# the three that are answered are never asked, the three that are not
# are asked in their usual order, and the pool comes out the same
half = [('shape', 'Center'), ('detail', 'Simple'),
        ('x', 480.0), ('y', 240.0), ('rl', 96.0), ('rt', 132.0),
        ('rr', 108.0)]
vm = run_form(half, [BASE, 72.0, 36.0, 60.0, NOBOTTOM])
assert snapshot(vm) == snapshot(by_prompts(CASES[0][2] + [NOBOTTOM])), \
    "the half-filled sheet drew a different pool"
asked = [p.strip() for p, _ in vm.prompts]
assert len(asked) == 5, asked
for want in ('Top-left tangent radius', 'Top-right tangent radius',
             'Bottom-center tangent radius'):
    assert any(a.startswith(want) for a in asked), (want, asked)
for gone in ('X - overall', 'Y - overall', 'Left bulge', 'Which shape'):
    assert not any(a.startswith(gone) for a in asked), (gone, asked)
print("   3 radii off the sheet, 3 asked for, same pool: %r"
      % [a.split(' [')[0] for a in asked])


print("== what a sheet may not smuggle past a check ==")
# A form answer goes through the very rules initget puts on the prompt,
# and through every range check the ask layer runs -- and the answer is
# CONSUMED as it is read, so the re-ask reaches the user instead of
# being re-fed the same bad number for ever.
bad = [('shape', 'Center'), ('detail', 'Simple'),
       ('x', 480.0), ('y', 240.0), ('rl', 200.0), ('rt', 132.0),
       ('rr', 108.0), ('ftl', 72.0), ('ftr', 36.0), ('fbc', 60.0)]
vm = run_form(bad, [BASE, 96.0, NOBOTTOM])
assert any('breaks out' in str(m) for m in vm.printed), vm.printed[-6:]
assert snapshot(vm) == snapshot(by_prompts(CASES[0][2] + [NOBOTTOM])), \
    "the refused radius was not replaced by the one the user typed"
print("   a bulge too big for the envelope is refused, then asked for")

# NA on a REQUIRED measurement is demoted to an unanswered box.  OASIS
# asks for every measurement as required, so a nil there would reach
# arithmetic rather than a check -- the trap LAZSPA had to handle at
# the other end, closed here instead.
na = [('shape', 'Center'), ('detail', 'Simple'),
      ('x', 480.0), ('y', None), ('rl', 96.0), ('rt', 132.0),
      ('rr', 108.0), ('ftl', 72.0), ('ftr', 36.0), ('fbc', 60.0)]
vm = run_form(na, [BASE, 240.0, NOBOTTOM])
assert any(p.strip().startswith('Y - overall') for p, _ in vm.prompts), \
    [p for p, _ in vm.prompts]
assert snapshot(vm) == snapshot(by_prompts(CASES[0][2] + [NOBOTTOM]))
print("   NA on a required measurement asks rather than reaching arithmetic")

# a keyword the question never offered is not an answer to it
bogus = [('shape', 'Banana'), ('detail', 'Simple'),
         ('x', 480.0), ('y', 240.0), ('rl', 96.0), ('rt', 132.0),
         ('rr', 108.0), ('ftl', 72.0), ('ftr', 36.0), ('fbc', 60.0)]
vm = run_form(bogus, ['Center', BASE, NOBOTTOM])
assert any('Which shape' in p for p, _ in vm.prompts), \
    [p for p, _ in vm.prompts]
assert snapshot(vm) == snapshot(by_prompts(CASES[0][2] + [NOBOTTOM]))
print("   a keyword outside the question's own list is asked for instead")

# and a zero or a negative gets no further than it would at the prompt
for label, v in (("zero", 0.0), ("negative", -96.0)):
    vm = run_form([('shape', 'Center'), ('detail', 'Simple'),
                   ('x', 480.0), ('y', 240.0), ('rl', v), ('rt', 132.0),
                   ('rr', 108.0), ('ftl', 72.0), ('ftr', 36.0),
                   ('fbc', 60.0)],
                  [BASE, 96.0, NOBOTTOM])
    assert snapshot(vm) == snapshot(by_prompts(CASES[0][2] + [NOBOTTOM])), \
        "a %s radius got past the sheet" % label
print("   a zero or a negative radius is refused the same way")


print("== Back does not deadlock on a form-answered question ==")
# An answer is REMOVED as it is used, not marked used.  Step back onto a
# question the form answered and it has to be a real question again --
# otherwise it answers itself instantly, walks forward, and there is no
# key the user can press to get out.
full = CASES[0][1]
vm = run_form(full, ['Back', 'Simple', BASE, NOBOTTOM])
asked = [p.strip() for p, _ in vm.prompts]
assert any(a.startswith('Simple or complex?') for a in asked), asked
assert snapshot(vm) == snapshot(by_prompts(CASES[0][2] + [NOBOTTOM]))
print("   %d questions, and the pool still comes out the same" % len(asked))


print("== the pool bottom is never the sheet's to answer ==")
# The floor is laid out ON the finished outline, and OASIS asks about it
# after the perimeter exists.  oasis:*fkey* is nil by then, so nothing
# in that flow can be fed from the store -- a run whose sheet is
# exhausted must still ask the gate, and a leftover key must not answer
# a question it was never meant for.
vm = run_form(full + [('rl', 96.0)], [BASE, NOBOTTOM])
assert any('Add the bottom of the pool' in p for p, _ in vm.prompts), \
    [p for p, _ in vm.prompts]
assert not vm.globals.get('oasis:*fkey*'), "oasis:*fkey* survived the run"
assert not vm.globals.get('oasis:*form*'), "oasis:*form* survived the run"
print("   the gate is asked, and both globals are clear afterwards")


print("== a complex run off a sheet: Line joiners and a hump off centre ==")
# The two things only a complex run can say.  A joiner answered Line
# comes out as the straight run between its two bulges' tangent points,
# and a Center pool's hump can be moved along X.
runs = [('shape', 'Center'), ('detail', 'Complex'),
        ('x', 480.0), ('y', 240.0), ('off', 0.0),
        ('rl', 96.0), ('rt', 132.0), ('rr', 108.0),
        ('ftl', 'Line'), ('ftr', 36.0), ('fbc', 60.0)]
a = run_form(runs, [BASE, NOBOTTOM])
b = by_prompts(['Center', 'Complex', BASE, 480.0, 240.0, 96.0, 132.0,
                0.0, 108.0, 'Line', 36.0, 60.0, NOBOTTOM])
assert snapshot(a) == snapshot(b), "the Line joiner did not come off the sheet"
lines = [e for e in a.entities
         if e not in a.deleted
         and any(isinstance(p, Dot) and p.a == 0 and p.b == 'LINE'
                 for p in a.entdata[e])]
assert lines, "no straight run was drawn"
print("   a Line joiner and a centred hump, %d entities" % len(snapshot(a)))

hump = [('shape', 'Center'), ('detail', 'Complex'),
        ('x', 480.0), ('y', 240.0), ('off', -36.0),
        ('rl', 96.0), ('rt', 132.0), ('rr', 108.0),
        ('ftl', 72.0), ('ftr', 36.0), ('fbc', 60.0)]
a = run_form(hump, [BASE, NOBOTTOM])
b = by_prompts(['Center', 'Complex', BASE, 480.0, 240.0, 96.0, 132.0,
                -36.0, 108.0, 72.0, 36.0, 60.0, NOBOTTOM])
assert snapshot(a) == snapshot(b), "the hump offset did not come off the sheet"
assert snapshot(a) != snapshot(run_form(runs, [BASE, NOBOTTOM])), \
    "the offset hump drew the same pool as the centred one"
print("   and a hump 36 off to the left, drawn where the sheet put it")


print("== the store does not leak between runs ==")
# An answer nothing asked for must not be waiting for the next run: a
# key for a slot this shape never reaches is dropped with the rest of
# the store on the way out, not left to answer the next pool's question.
vm = newvm()
vm.loads(SHIM)
vm.loads("(setq test:*f* %s)" % alist(CASES[2][1] + [('rt', 999.0)]))
vm.run('test:go', [BASE, NOBOTTOM])
assert not vm.globals.get('oasis:*form*'), \
    "a slot the cloud never asks for was left in the store: %r" \
    % vm.globals.get('oasis:*form*')
print("   a key the shape never reaches goes out with the rest of it")

print("all OASIS form tests passed")
