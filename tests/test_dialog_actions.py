# SPDX-License-Identifier: GPL-3.0-or-later
"""Every action_tile expression in every DCL page, evaluated.

A DCL callback is a STRING.  Nothing checks a string: rename the helper
it calls and the file still loads, every other suite still passes, and
the tile is dead until somebody clicks it -- which, on a page with sixty
tiles, may be weeks.  The four UI tools wire about 1,240 of them across
33 pages, and the suites that drive those pages only ever evaluate the
handful each scenario clicks.

So this opens every page of every tool with the dialog surface stubbed,
collects what action_tile was handed, and EVALUATES all of it -- under
each $reason DCL can deliver, since a callback may read it (LAZPANEL's
list box runs the tool on a double click and only on a double click).

It asserts nothing about what an expression DOES.  That is the business
of the tool's own suite, which knows what the click should achieve.
This one asserts only that every expression is something the VM can run
at all: no typo'd name, no missing paren, no helper that has moved out
from under a call site the mirror does not rewrite.

    python3 tests/test_dialog_actions.py
    CALOFIN_LISP_ROOT=shared python3 tests/test_dialog_actions.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..'))

# new_dialog takes TWO arguments, or FOUR when a remembered position is
# handed back.  A defun in this VM is exact-arity, so the tile surface
# that varies goes in as a Python builtin instead.
lispvm.BUILTINS[lispvm.Sym('new_dialog')] = lambda vm, a: True

STUB = '''
(setq stub:*act* nil stub:*done* nil)
(defun vl-filename-mktemp (p d e) (strcat "/stub/" p e))
(defun open (f m) f) (defun write-line (s fh) s) (defun close (fh) t)
(defun load_dialog (f) 7) (defun unload_dialog (i) t) (defun term_dialog () nil)
(defun vl-file-delete (f) t)
(defun set_tile (k v) v) (defun mode_tile (k m) t) (defun get_tile (k) "")
(defun start_list (k) k) (defun add_list (s) s) (defun end_list () nil)
(defun start_image (k) k) (defun end_image () nil)
(defun vector_image (a b c d e) nil) (defun fill_image (a b c d e) nil)
(defun dimx_tile (k) 520) (defun dimy_tile (k) 376)
(defun done_dialog (s) (setq stub:*done* s) (list 120 340))
(defun action_tile (k e) (setq stub:*act* (cons (list k e) stub:*act*)) t)
(defun start_dialog () 0)
(defun getenv (n) nil) (defun setenv (n v) v)
;; no stored position, no pins, no recalled sheet: the page has to wire
;; itself from nothing, which is the state a first run is in
(defun vl-registry-read (k v) (exit))
(defun vl-registry-write (k v s) s)
'''

#: What DCL puts in $reason: 1 a plain selection, 2 an edit box left
#: after a change, 4 a double click in a list box.  A callback may read
#: it, so every expression is run under each.
REASONS = (1, 2, 4)


def fresh(*rel):
    vm = VM()
    for r in rel:
        vm.load(os.path.join(REPO, *r.split('/')))
    vm.loads(STUB)
    return vm


TOTAL = [0, 0]


def sweep(vm, label):
    """Evaluate every expression registered since stub:*act* was cleared."""
    acts = [(str(a[0]), str(a[1])) for a in (vm.globals.get('stub:*act*') or [])]
    assert acts, "%s: the page wired nothing at all" % label
    bad = []
    for key, expr in acts:
        for reason in REASONS:
            try:
                vm.loads('(setq $key "%s" $value "1" $reason %d)' % (key, reason))
                vm.loads('(progn %s)' % expr)
            except Exception as exc:                      # noqa: BLE001
                bad.append((key, reason, str(exc).splitlines()[-1][:120]))
                break
    assert not bad, "%s: %d callback(s) will not run:\n%s" % (
        label, len(bad),
        "\n".join("    %-18s $reason=%d  %s" % b for b in bad))
    TOTAL[0] += len(acts)
    TOTAL[1] += 1
    return len(acts)


print("== every callback on every page runs ==")

vm = fresh('lisp/lazform/LAZFORM.lsp')
vm.loads('(setq t:*c* (mapcar (quote car) lzf:*charts*))')
n = 0
for chart in [str(x) for x in vm.globals['t:*c*']]:
    vm.loads('(setq stub:*act* nil) (lzf:show "%s")' % chart)
    n += sweep(vm, 'LAZFORM %s' % chart)
print("   LAZFORM    %2d charts, %4d callbacks"
      % (len(vm.globals['t:*c*']), n))

vm = fresh('lisp/spa/SPA.LSP', 'lisp/lazspa/LAZSPA.lsp')
vm.loads('(setq t:*c* (mapcar (quote car) lzs:*charts*))')
n = 0
for chart in [str(x) for x in vm.globals['t:*c*']]:
    vm.loads('(setq stub:*act* nil) (lzs:show "%s")' % chart)
    n += sweep(vm, 'LAZSPA %s' % chart)
print("   LAZSPA     %2d charts, %4d callbacks"
      % (len(vm.globals['t:*c*']), n))

# page two is BUILT for the count, so its tiles are only as good as the
# count they were built for: one, a middling one, and the ceiling
vm = fresh('lisp/lazstep/LAZSTEP.lsp')
vm.loads('(setq t:*t* (mapcar (quote car) lzt:*types*)) (setq t:*m* lzt:*max-steps*)')
TYPES = [str(x) for x in vm.globals['t:*t*']]
MAX = int(str(vm.globals['t:*m*']))
n = 0
for ty in TYPES:
    vm.loads('(setq lzt:*type* "%s" lzt:*vals* nil lzt:*sel* nil)' % ty)
    vm.loads('(setq stub:*act* nil) (lzt:page1 7)')
    n += sweep(vm, 'LAZSTEP %s page 1' % ty)
    for count in (1, 3, MAX):
        vm.loads('(setq lzt:*steps* %d lzt:*chart* (lzt:chart "%s" %d))'
                 % (count, ty, count))
        vm.loads('(setq stub:*act* nil) (lzt:page2 7)')
        n += sweep(vm, 'LAZSTEP %s page 2, %d step(s)' % (ty, count))
print("   LAZSTEP    %2d types x (page 1 + 3 counts), %4d callbacks"
      % (len(TYPES), n))

# the panel with a pin and a recent tool on the row, so both extra
# button families are wired rather than skipped as empty
vm = fresh('lisp/lazpanel/LAZPANEL.lsp')
vm.loads('(setq t:*p* (lzp:pages))')
vm.loads("(setq lzp:*pins* (list (car (lzp:commands))))")
vm.loads("(setq lzp:*recent* (list (cadr (lzp:commands))))")
PAGES = [str(x) for x in vm.globals['t:*p*']]
n = 0
for page in PAGES:
    vm.loads('(setq lzp:*page* "%s") (setq stub:*act* nil) (lzp:show)' % page)
    n += sweep(vm, 'LAZPANEL %s' % page)
    wired = {str(a[0]) for a in (vm.globals.get('stub:*act*') or [])}
    assert any(k.startswith('pin_') for k in wired), \
        "%s: the pinned row wired nothing" % page
    assert any(k.startswith('rec_') for k in wired), \
        "%s: the recent row wired nothing" % page
print("   LAZPANEL   %2d pages, %4d callbacks, every one with both rows"
      % (len(PAGES), n))

print("\n   %d callbacks over %d pages, each run under $reason %s"
      % (TOTAL[0], TOTAL[1], "/".join(str(r) for r in REASONS)))
print("\nALL DIALOG CALLBACKS RUN")
