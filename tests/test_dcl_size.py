"""Every generated dialog fits on the screen AutoCAD will give it.

DCL does not scroll.  A dialog taller or wider than the display does
not clip -- AutoCAD refuses to open it and the command dies:

    Dialog too large to fit on screen.
    Requested Size = (436, 1085)   Maximum Size = (1920, 1080)

That is what LAZPANEL's "Rest" page did at 28 tools.  Rest is
COMPUTED -- every tool not on Pool, Cover or Spa lands there -- so the
page that broke is the page every newly registered tool joins, and
"Layout" had already passed the same line at 32 without anyone
clicking it.

The measuring is tools/dclsize.py and the budget is tools/check_dcl.py;
this drives them over the tree so a regression fails `make test` and
not only `make check`.  What it pins down beyond "it fits today":

1. the pages that broke are WRAPPED, not merely under the line;
2. the strips a DRAFTER grows -- Pinned and Recent -- are capped, on
   the way in from the registry as well as at the tick, because a
   stored list from an older build has never been through the cap;
3. the captions survive the wrap, since a category page carrying the
   command name alone would have lost the thing it is for.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', 'tools'))

import check_dcl                                  # noqa: E402
import dclsize                                    # noqa: E402
from lispvm import VM                             # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..'))
PANEL = os.path.join(REPO, 'lisp', 'lazpanel', 'LAZPANEL.lsp')


def panel(*setup):
    vm = VM()
    vm.load(PANEL)
    for form in setup:
        vm.loads(form)
    return vm


def dialogs(vm):
    vm.loads('(setq zz:*d* (lzp:dcl-lines))')
    text = "\n".join(str(l) for l in vm.globals['zz:*d*'])
    return {n: (w, h) for n, w, h in dclsize.measure(text)}


print("== the model reproduces the size AutoCAD reported ==")
# The one real measurement there is: 28 captioned buttons in a single
# boxed column, under the furniture every page carries, came to
# (436, 1085).  Rebuild that page and the model must land on it, or
# every other number here is guesswork.
#
# 28 is the count that was MEASURED, not the count Rest happens to hold:
# Rest is the page every newly registered tool lands on, so reading the
# live roster here would retire the one real number in this file the
# next time anyone added a tool.  So the page is cut back to the 28 that
# were measured, and the anchor keeps meaning what it says.
FIRST_N = '''(defun zz:first (n l / out)
  (while (and l (> n 0))
    (setq out (cons (car l) out) l (cdr l) n (1- n)))
  (reverse out))'''
CUT_REST = '''(setq lzp:*groups*
  (mapcar '(lambda (g)
             (if (= (car g) "Rest")
               (list "Rest" (cons "" (zz:first 28 (cdr (cadr g)))))
               g))
          lzp:*groups*))'''
vm = panel('(setq lzp:*colbudget* 9999)',       # as it was before the fix
           FIRST_N, CUT_REST)
sizes = dialogs(vm)
assert sizes['lazpanel_rest'] == (436, 1085), sizes['lazpanel_rest']
print("   un-wrapped, 28 buttons on Rest is 436x1085"
      " -- exactly what AutoCAD refused")


print("== every dialog in the tree fits, worst case ==")
problems = check_dcl.check()
assert not problems, "\n".join(problems)


print("== the pages that overflowed are wrapped, not just short ==")
vm = panel()
sizes = dialogs(vm)
for page in ('lazpanel_rest', 'lazpanel_layout'):
    w, h = sizes[page]
    assert h <= check_dcl.MAX_H - check_dcl.MARGIN, (page, w, h)
vm.loads('(setq zz:*w* (lzp:wrap (list "A" "B" "C")))')
assert len(vm.globals['zz:*w*']) == 1, "a short page must stay one column"
vm.loads('(setq zz:*w* (lzp:wrap (lzp:commands)))')
cols = vm.globals['zz:*w*']
assert len(cols) > 1, ("%d tools must not come back as one column"
                       % len(vm.globals['zz:*w*']))
lens = [len(c) for c in cols]
assert max(lens) - min(lens) <= 1, "columns must be balanced: %r" % lens
assert max(lens) <= int(vm.globals['lzp:*colbudget*']), lens
print("   Rest %dx%d and Layout %dx%d, balanced columns of at most %s"
      % (sizes['lazpanel_rest'][0], sizes['lazpanel_rest'][1],
         sizes['lazpanel_layout'][0], sizes['lazpanel_layout'][1],
         vm.globals['lzp:*colbudget*']))


print("== a wrapped category page keeps its captions ==")
vm.loads('(setq zz:*d* (lzp:dcl-lines))')
dcl = [str(l) for l in vm.globals['zz:*d*']]
i = dcl.index('lazpanel_rest : dialog {')
body, d = [], 0
for line in dcl[i:]:
    body.append(line)
    d += line.count('{') - line.count('}')
    if d == 0 and len(body) > 1:
        break
vm.loads('(setq zz:*nrest*'
         ' (length (cdr (cadr (assoc "Rest" lzp:*groups*)))))')
nrest = int(vm.globals['zz:*nrest*'])
caps = [l for l in body if '  -  ' in l and ': button' in l]
assert len(caps) == nrest, ("Rest lost its captions: %d of %d left"
                            % (len(caps), nrest))
print("   all %d buttons still read NAME  -  what the tool does" % nrest)


print("== Pinned is capped, at the tick and on the way in ==")
vm = panel()
vm.loads('(setq lzp:*pins* (lzp:commands)) (lzp:pintrim)')
vm.loads('(setq zz:*n* (length lzp:*pins*)) (setq zz:*r* (length (lzp:pinrows)))')
rows, mx = int(vm.globals['zz:*r*']), int(vm.globals['lzp:*pinrowmax*'])
assert rows <= mx, "pintrim left %d rows, cap is %d" % (rows, mx)
# and the tick itself refuses the one that would not fit
vm.loads('(setq zz:*before* (length lzp:*pins*))')
vm.loads('(lzp:pin-toggle "XYPLOT" "1")')
vm.loads('(setq zz:*after* (length lzp:*pins*))')
before, after = int(vm.globals['zz:*before*']), int(vm.globals['zz:*after*'])
assert after == before, "a pin past the cap was taken anyway"
assert int(vm.globals['zz:*r*']) <= mx
vm.loads('(setq zz:*all* (length (lzp:commands)))')
print("   %s pinned trims to %s in %d row(s); one more is refused"
      % (vm.globals['zz:*all*'], vm.globals['zz:*n*'], rows))


print("== Recent is capped on the way in too ==")
vm = panel()
vm.loads('(setq lzp:*recent* (lzp:commands)) (lzp:rectrim)')
vm.loads('(setq zz:*n* (length lzp:*recent*))')
n, lim = int(vm.globals['zz:*n*']), int(vm.globals['lzp:*reclimit*'])
assert n == lim, "rectrim left %d, limit is %d" % (n, lim)
vm.loads('(setq zz:*all* (length (lzp:commands)))')
print("   a stored Recent of %s comes back as %d"
      % (vm.globals['zz:*all*'], n))


print("== the worst page a drafter can build still fits ==")
vm = panel('(setq lzp:*pins* (lzp:commands))', '(lzp:pintrim)',
           '(setq lzp:*recent* (reverse (lzp:commands)))', '(lzp:rectrim)')
sizes = dialogs(vm)
worst = max(sizes.items(), key=lambda kv: kv[1][1])
assert worst[1][1] <= check_dcl.MAX_H - check_dcl.MARGIN, worst
assert worst[1][0] <= check_dcl.MAX_W - check_dcl.MARGIN, worst
print("   pins and recents full, tallest is %s at %dx%d"
      % (worst[0], worst[1][0], worst[1][1]))

print("ALL DCL SIZE TESTS PASSED")
