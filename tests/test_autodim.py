"""AUTODIM's dimension rules, driven in the AutoLISP VM.

Covers what AutoDim.lsp promises about the dims it places:

  * every plan dim goes in "SIDE STANDARD", anything measuring under
    12" in "STANDARD INCHES" instead, and the two overall dims in
    "STANDARD"
  * a place that is dimensioned already is left alone - same two
    extension line origins either way round, dim line within a foot
  * the overall dims still go in when a side of the plan measures the
    same thing, because they sit two feet further out
  * a dim chain breaks where a span is taken and where the style has to
    change, instead of dragging a whole DIMCONTINUE run into one style
  * a style the drawing does not have falls back to the one that was
    current when the command started

The VM's (command "_.DIMALIGNED" ...) / "_.DIMLINEAR" stub leaves a
DIMENSION entity behind carrying groups 13, 14 and 10 and the style
that was current - which is exactly what these rules are made of.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'autodim', 'AutoDim.lsp')
STYLES = {'STANDARD', 'SIDE STANDARD', 'STANDARD INCHES'}


def fresh(styles=STYLES):
    """A VM with AutoDim loaded, the named dim styles in the drawing and
    a run already begun on an empty drawing."""
    vm = VM()
    vm.load(LSP)                            # CALOFIN_LISP_ROOT picks the tier
    vm.tables['DIMSTYLE'] = set(styles)
    vm.script = [None]                      # ad:begin's ssget: no dims yet
    vm.loads('(ad:begin)')
    return vm


def dims(vm):
    """Every dimension the run has left behind, as
    (style, origin1, origin2, dimline-point)."""
    out = []
    for e in vm.entities:
        data = vm.entdata.get(e, [])
        if not any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
                   for g in data):
            continue
        sty = next(g.b for g in data if isinstance(g, Dot) and g.a == 3)
        pts = {g[0]: tuple(g[1:3]) for g in data
               if isinstance(g, list) and g and g[0] in (13, 14, 10)}
        out.append((sty, pts.get(13), pts.get(14), pts.get(10)))
    return out


def rescan(vm):
    """Re-read the drawing the way a second command run would.  The VM's
    dim stub does not stamp group 410, so the test supplies the
    model-space mark AutoCAD would report before ad:dimss filters on it."""
    ents = []
    for e in vm.entities:
        data = vm.entdata.get(e, [])
        if any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
               for g in data):
            if not any(isinstance(g, Dot) and g.a == 410 for g in data):
                data.append(Dot(410, 'Model'))
            ents.append(e)
    vm.script = [ents or None]
    vm.loads('(ad:dimscan)')


#: A 10ft x 6ft plan whose dims already reach a foot clear of it on the
#: top and the left.  ad:ssbox is cal:bbox-ss in the grouped build, so
#: both names are stubbed and the test reads the same on either tier.
PLANBOX = """
  (defun ad:ssbox    (ss) (list (list 0.0 0.0 0.0) (list 120.0 72.0 0.0)))
  (defun cal:bbox-ss (ss) (list (list 0.0 0.0 0.0) (list 120.0 72.0 0.0)))
  (defun ad:dimextents (plan) (list (list -15.0 -15.0 0.0)
                                    (list 135.0 87.0 0.0)))"""


def pt(x, y):
    return '(list %.4f %.4f 0.0)' % (x, y)


def aligned(vm, p1, p2, loc, base='ad:*style-plan*'):
    return vm.loads('(ad:putaligned %s %s %s %s)'
                    % (pt(*p1), pt(*p2), pt(*loc), base))


print('== the style follows what the dim measures ==')
vm = fresh()
# a 5' side, then an 8" step riser, both asked for in the plan style
assert aligned(vm, (0, 0), (60, 0), (0, -12)) == 1
assert aligned(vm, (0, 40), (8, 40), (0, 52)) == 1
got = [d[0] for d in dims(vm)]
assert got == ['SIDE STANDARD', 'STANDARD INCHES'], got
print('   60" -> SIDE STANDARD, 8" -> STANDARD INCHES')

# exactly 12" is not "under 12 inches"
assert vm.loads('(ad:styfor 12.0 ad:*style-plan*)') == 'SIDE STANDARD'
assert vm.loads('(ad:styfor 11.999 ad:*style-plan*)') == 'STANDARD INCHES'
print('   the cut is at 12" itself, not below it')


print('== a place that is dimensioned already is left alone ==')
vm = fresh()
assert aligned(vm, (0, 0), (60, 0), (30, -12)) == 1
assert aligned(vm, (0, 0), (60, 0), (30, -12)) == 0        # the same dim
assert aligned(vm, (60, 0), (0, 0), (30, -12)) == 0        # the other way round
assert aligned(vm, (0, 0), (60, 0), (30, -18)) == 0        # nudged 6", same dim
assert len(dims(vm)) == 1, dims(vm)
assert vm.loads('ad:*skipped*') == 3
print('   the same span, reversed, and nudged half a foot: all skipped')

# ...and the drawing's own dims count, not just this run's
rescan(vm)
assert aligned(vm, (0, 0), (60, 0), (30, -12)) == 0
assert len(dims(vm)) == 1
print('   a second run reads them back out of the drawing and skips them')

# a dim of the same span far enough out is its own dim, not a repeat
assert aligned(vm, (0, 0), (60, 0), (30, -36)) == 1
# and the other side of the span is never the same dim
assert aligned(vm, (0, 0), (60, 0), (30, 12)) == 1
assert len(dims(vm)) == 3, dims(vm)
print('   2ft out, and the far side, are dims of their own')


print('== the two overall dims ==')
vm = fresh()
# the plan is 10ft x 6ft; the dims around it already reach a foot
# clear of it on the top and the left
vm.loads(PLANBOX)
assert vm.loads('(ad:overall (list "<ss>"))') == 2
wide, tall = dims(vm)
assert wide[0] == 'STANDARD' and tall[0] == 'STANDARD', dims(vm)
# the width dim spans the plan, 2ft above the topmost dim (87 + 24)
assert wide[1] == (0.0, 72.0) and wide[2] == (120.0, 72.0), wide
assert wide[3] == (60.0, 111.0), wide
# the height dim spans the plan, 2ft left of the left-most dim (-15 - 24)
assert tall[1] == (0.0, 0.0) and tall[2] == (0.0, 72.0), tall
assert tall[3] == (-39.0, 36.0), tall
assert [c[0] for c in vm.commands if c[0].startswith('_.DIM')] == \
    ['_.DIMLINEAR', '_.DIMLINEAR']
assert '_H' in vm.commands[-2] and '_V' in vm.commands[-1]
print('   width 2ft above the topmost dim, height 2ft left of the left-most')
print('   both linear, both in STANDARD')

# a rectangular plan has a perimeter dim measuring the very same span:
# the overall dims still go in, because they are two feet further out
vm = fresh()
vm.loads(PLANBOX)
assert vm.loads('(ad:putlinear %s %s %s "_H" ad:*style-plan*)'
                % (pt(0, 72), pt(120, 72), pt(60, 84))) == 1
assert vm.loads('(ad:overall (list "<ss>"))') == 2
assert [d[0] for d in dims(vm)] == ['SIDE STANDARD', 'STANDARD', 'STANDARD']
print('   a rectangle already dimensioned side-by-side still gets both')

# run it twice and the second time adds nothing
assert vm.loads('(ad:overall (list "<ss>"))') == 0
assert len(dims(vm)) == 3
print('   asking a second time adds nothing')


print('== chains break where a span is taken or the style changes ==')
vm = fresh()
# four spans along one line: 24", 24", 6", 24"
chain = '(list %s %s %s %s %s)' % (pt(0, 0), pt(24, 0), pt(48, 0),
                                   pt(54, 0), pt(78, 0))
assert vm.loads('(ad:dimchain %s %s ad:*style-plan*)' % (chain, pt(39, -12))) == 4
placed = dims(vm)
# DIMCONTINUE leaves no entity in the VM, so the entities are the head
# of each run: 0-24 (chained on to 48), then 48-54, then 54-78
assert [d[0] for d in placed] == ['SIDE STANDARD', 'STANDARD INCHES',
                                  'SIDE STANDARD'], placed
assert [d[1] for d in placed] == [(0.0, 0.0), (48.0, 0.0), (54.0, 0.0)]
cont = [c for c in vm.commands if c and c[0] == '_.DIMCONTINUE']
assert len(cont) == 1, vm.commands            # only the first run continues
assert vm.loads('(ad:samestyle "side standard" "SIDE STANDARD")')
print('   the 6" span splits the run out into STANDARD INCHES')

# the same chain again: every span is taken now, nothing is placed
vm.loads('(setq ad:*skipped* 0)')
assert vm.loads('(ad:dimchain %s %s ad:*style-plan*)' % (chain, pt(39, -12))) == 0
assert vm.loads('ad:*skipped*') == 4
assert len(dims(vm)) == 3
print('   running it again places nothing and counts all four as skipped')

# one span taken in the middle breaks the chain around it
vm = fresh()
assert aligned(vm, (24, 0), (48, 0), (39, -12)) == 1
assert vm.loads('(ad:dimchain %s %s ad:*style-plan*)' % (chain, pt(39, -12))) == 3
assert len(dims(vm)) == 4, dims(vm)
heads = [d[1] for d in dims(vm)]
assert heads == [(24.0, 0.0), (0.0, 0.0), (48.0, 0.0), (54.0, 0.0)], heads
print('   a taken span in the middle leaves the pieces either side')


print('== a missing style falls back, it does not strand the next dim ==')
vm = fresh(styles={'STANDARD', 'STANDARD INCHES'})   # no "SIDE STANDARD"
vm.sysvars['DIMSTYLE'] = 'STANDARD'
vm.script = [None]
vm.loads('(ad:begin)')
assert aligned(vm, (0, 0), (60, 0), (30, -12)) == 1     # wants SIDE STANDARD
assert aligned(vm, (0, 40), (8, 40), (4, 52)) == 1      # wants STANDARD INCHES
assert aligned(vm, (0, 60), (60, 60), (30, 72)) == 1    # wants SIDE STANDARD
got = [d[0] for d in dims(vm)]
assert got == ['STANDARD', 'STANDARD INCHES', 'STANDARD'], got
print('   the long dims keep the style the run started in, both times')


print('ALL AUTODIM CHECKS PASSED')
