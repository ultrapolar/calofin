"""LAZPANEL: the DCL launcher panel and its screen button, in the VM.

Four jobs:

1. Pin the roster to the tree.  Every headline command defined under
   lisp/ must have a button, so a new tool without one fails here
   instead of being quietly missing (satellites -- TUTORIAL*, *VER /
   *VERSION reporters, *RESCUE companions, -CFG / -SETUP partners, the
   DD* sub-commands, DCE and STOCKLIST -- are exempt).  Held-back tools
   (cal:*held-back* in CALOFIN-LOADER.lsp) and the deprecated acady
   matcher must NOT have buttons.

2. Check the generated DCL is well formed: balanced braces, even
   quotes, one key per button matching the roster, one cancel tile,
   and a grammar pass (trailing semicolons, known tile and attribute
   names) for the errors AutoCAD's DCL parser rejects outright.

3. Drive c:LAZPANEL end-to-end with the DCL surface stubbed (the VM
   has no dialog or file i/o builtins): Close launches nothing, a
   click evaluates the REAL action_tile expression, greyed buttons are
   exactly the missing commands, and the temp .dcl is written and
   deleted -- in order -- either way.

4. Check the screen button, including the load-time creation that IS
   the feature: the stubs go in before the file loads, so deleting that
   call fails here.  The button lands at index 0 of an empty toolbar,
   carries the ^C^C_LAZPANEL macro as raw ASCII 3s, is re-iced and
   re-shown rather than duplicated on a second init, and does not
   survive at all if it cannot get its button.  The icon is checked
   pixel by pixel -- position, not just colour count, because a BMP
   stores its rows bottom-up and an L is not symmetric -- and the
   ADODB.Stream binary write is checked because AutoLISP's own file
   output could not have produced it: over a hundred of these bytes
   are NUL, which write-char has no way to emit.

Runs against either tier: standalone by default, the grouped build with
CALOFIN_LISP_ROOT=shared.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..'))
LSP = os.path.join(REPO, 'lisp', 'lazpanel', 'LAZPANEL.lsp')
LOADER = os.path.join(REPO, 'shared', 'parts', 'CALOFIN-LOADER.lsp')
PARTS = os.path.join(REPO, 'shared', 'parts')

CMD_RE = re.compile(r'^\(defun\s+[cC]:([^\s()]+)', re.M)
HELD_RE = re.compile(r'\("([^"]+)"\s*\.\s*"(?:WIP|OMITTED)"\)')


def fresh():
    vm = VM()
    vm.load(LSP)
    return vm


def roster(vm):
    groups = vm.globals.get('lzp:*groups*') or []
    out = []
    for g in groups:
        for cmd, _caption in g[1:]:
            out.append(str(cmd))
    return out


def census():
    """Every C: command defined under lisp/, standards_checker excluded
    (the deprecated acady matcher is not part of the toolset)."""
    out = set()
    lisp_dir = os.path.join(REPO, 'lisp')
    for dirpath, _dirnames, filenames in os.walk(lisp_dir):
        if 'standards_checker' in dirpath.split(os.sep):
            continue
        for fn in filenames:
            if fn.lower().endswith('.lsp'):
                with open(os.path.join(dirpath, fn)) as fh:
                    out |= {m.upper() for m in CMD_RE.findall(fh.read())}
    return out


def held_commands():
    """Commands of every held-back file, read off the loader's list."""
    with open(LOADER) as fh:
        held_files = HELD_RE.findall(fh.read())
    out = set()
    for name in held_files:
        with open(os.path.join(PARTS, name)) as fh:
            out |= {m.upper() for m in CMD_RE.findall(fh.read())}
    return out


print("== the file loads and announces itself ==")
vm = fresh()
ver = vm.globals.get('*lazpanel-version*')
assert ver and re.fullmatch(r'v\d+\.\d+', str(ver)), ver
assert any('LAZPANEL' in str(p) for p in vm.printed), vm.printed
PANEL = roster(vm)
assert len(PANEL) == len(set(PANEL)), "duplicate buttons: %r" % PANEL
print("   %s, %d buttons, no duplicates" % (ver, len(PANEL)))


print("== roster pin: panel == headline commands under lisp/ ==")
ALL = census()
HELD = held_commands()
missing_from_tree = [c for c in PANEL if c not in ALL]
assert not missing_from_tree, (
    "buttons for commands that do not exist: %r" % missing_from_tree)

satellites = set()
for c in ALL:
    base = None
    if c.startswith('TUTORIAL') or c.startswith('DD'):
        satellites.add(c)
    elif c.endswith('-CFG') or c.endswith('-SETUP'):
        satellites.add(c)
    elif c.endswith('VERSION'):
        base = c[:-len('VERSION')]
    elif c.endswith('VER'):
        base = c[:-len('VER')]
    elif c.endswith('RESCUE'):
        base = c[:-len('RESCUE')]
    if base and base in ALL:
        satellites.add(c)
# DCE is DIMCONTEND's short alias; STOCKLIST is STOCKCOVER's listing
# companion -- both reachable, neither needs its own button.  LAZPANEL
# is the panel itself and LAZBUTTON its toolbar summoner.
satellites |= {'DCE', 'STOCKLIST', 'LAZPANEL', 'LAZBUTTON'}

headline = ALL - satellites - HELD
assert headline == set(PANEL), (
    "panel and tree disagree.\n  needs a button: %r\n  stale button: %r"
    % (sorted(headline - set(PANEL)), sorted(set(PANEL) - headline)))
overlap = set(PANEL) & HELD
assert not overlap, "held-back commands with buttons: %r" % overlap
print("   %d headline commands, all on the panel; %d held back, none on it"
      % (len(headline), len(HELD)))


print("== the generated DCL is well formed ==")
vm.loads('(setq test:*dcl* (lzp:dcl-lines))')
dcl = [str(l) for l in vm.globals.get('test:*dcl*')]
assert dcl[0] == 'lazpanel : dialog {', dcl[0]
assert dcl[-1] == '}', dcl[-1]
depth = 0
for line in dcl:
    assert line.count('"') % 2 == 0, "odd quotes: %r" % line
    for ch in line:
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            assert depth >= 0, "brace closes below zero at %r" % line
assert depth == 0, "unbalanced braces: %d left open" % depth
text = '\n'.join(dcl)
keys = re.findall(r'key = "([^"]+)"', text)
assert len(keys) == len(set(keys)), "duplicate keys"
assert set(keys) == set(PANEL) | {'status', 'cancel'}, (
    set(keys) ^ (set(PANEL) | {'status', 'cancel'}))
assert text.count('is_cancel = true') == 1
for c in PANEL:
    assert re.search(r'label = "%s  -  [^"]+"' % re.escape(c), text), c

# A grammar pass, because AutoCAD's DCL parser rejects what the shape
# checks above cannot see: an attribute clause without its trailing
# semicolon, or a misspelled tile name, kills load_dialog/new_dialog
# outright.  Every line must be one of the five shapes below, every
# tile and attribute name drawn from the known sets.
TILES = {'row', 'boxed_column', 'button', 'text'}
ATTRS = {'label', 'key', 'width', 'alignment',
         'is_default', 'is_cancel', 'fixed_width'}
CLAUSE = r'[a-z_]+ = (?:"[^"]*"|[a-z0-9]+);'
OPEN_RE = re.compile(r': ([a-z_]+) \{$')
INLINE_RE = re.compile(r': ([a-z_]+) \{ ((?:%s )+)\}$' % CLAUSE)
PLAIN_RE = re.compile(r'(?:%s)$' % CLAUSE)


def check_clauses(chunk, line):
    for name in re.findall(r'([a-z_]+) =', chunk):
        assert name in ATTRS, "unknown attribute %r in %r" % (name, line)


for line in dcl[1:]:
    s = line.strip()
    if s in ('}', 'spacer;'):
        continue
    m = OPEN_RE.fullmatch(s)
    if m:
        assert m.group(1) in TILES, "unknown tile %r in %r" % (m.group(1), line)
        continue
    m = INLINE_RE.fullmatch(s)
    if m:
        assert m.group(1) in TILES, "unknown tile %r in %r" % (m.group(1), line)
        check_clauses(m.group(2), line)
        continue
    assert PLAIN_RE.fullmatch(s), "not a valid DCL line: %r" % line
    check_clauses(s, line)
print("   %d lines, %d keys, braces/quotes/clauses/tile names all valid"
      % (len(dcl), len(keys)))



print("== end-to-end with the DCL surface stubbed ==")
# The stubs keep one ORDERED event log (stub:*events*) so the cleanup
# sequence -- handle closed before load_dialog reads the file, dialog
# unloaded and temp file deleted before anything launches -- is pinned,
# not just each call's happening.  A click is simulated faithfully:
# start_dialog looks up the clicked key's REAL action_tile expression,
# binds $key / $value / $reason the way AutoCAD does, and evaluates it,
# so the wiring string in LAZPANEL.lsp is executed here, not assumed.
#
# The vla-* stubs model the menu API: menu group "MG0" whose toolbars
# live in stub:*tbs*, each toolbar's buttons in stub:*btns*.  The
# ADODB.Stream path needs variable arity -- (vlax-invoke st 'Open) takes
# two arguments, (vlax-invoke st 'SaveToFile p 2) takes four -- which a
# defun in this VM cannot express, since it enforces exact arity, so
# that surface goes in as Python builtins instead.
STUB = '''
(setq stub:*written* nil stub:*disabled* nil stub:*action* nil
      stub:*events* nil stub:*click* nil stub:*status* nil
      stub:*ran* nil stub:*dlgname* nil stub:*done* nil
      stub:*tbs* nil stub:*btns* nil stub:*addargs* nil
      stub:*bitmaps* nil stub:*float* nil stub:*visible* nil
      stub:*deleted-tb* nil stub:*addfail* nil)
(defun stub:ev (e) (setq stub:*events* (cons e stub:*events*)) e)
(defun vl-filename-mktemp (pat dir ext) (strcat "/stub/" pat ext))
(defun open (f mode) f)
(defun write-line (s fh)
  (setq stub:*written* (cons s stub:*written*)) s)
(defun close (fh) (stub:ev "close"))
(defun load_dialog (f) (stub:ev "load") 7)
(defun new_dialog (name id)
  (setq stub:*dlgname* name) (stub:ev "new") t)
(defun term_dialog () nil)
(defun set_tile (k v)
  (if (= k "status") (setq stub:*status* v)) v)
(defun action_tile (k expr)
  (setq stub:*action* (cons (list k expr) stub:*action*)) t)
(defun mode_tile (k m)
  (if (= m 1) (setq stub:*disabled* (cons k stub:*disabled*))) t)
(defun done_dialog (status) (setq stub:*done* status) t)
(defun start_dialog ( / pair)
  (stub:ev "start")
  (setq stub:*done* nil)
  (if (setq pair (assoc stub:*click* stub:*action*))
    (progn
      (setq $key (car pair) $value nil $reason 1)
      (eval (read (strcat "(progn " (cadr pair) ")")))))
  (if stub:*done* stub:*done* 0))
(defun unload_dialog (id) (stub:ev "unload"))
(defun vl-file-delete (f) (stub:ev (strcat "delete " f)) t)
(defun vlax-get-acad-object () "ACAD")
(defun vla-get-menugroups (app) "MGS")
(defun vla-get-toolbars (mg) "TBS")
(defun vla-get-count (obj) (if (= obj "MGS") 1 (length stub:*tbs*)))
(defun vla-get-name (tb) tb)
(defun vla-item (obj i)
  (cond ((= obj "MGS") "MG0")
        ((= obj "TBS") (nth i stub:*tbs*))
        (t (nth i stub:*btns*))))
(defun vla-add (tbs name)
  (setq stub:*tbs* (append stub:*tbs* (list name)))
  (stub:ev (strcat "add " name))
  name)
(defun vla-addtoolbarbutton (tb idx name help macro)
  (setq stub:*addargs* (list idx name help macro))
  (if stub:*addfail*
    (exit)
    (progn (setq stub:*btns* (append stub:*btns* (list "BTN")))
           (stub:ev "addbutton")
           "BTN")))
(defun vla-delete (tb)
  (setq stub:*tbs* (vl-remove tb stub:*tbs*)
        stub:*deleted-tb* tb)
  (stub:ev "deletetoolbar") t)
(defun vla-setbitmaps (btn small large)
  (setq stub:*bitmaps* (list small large)) (stub:ev "setbitmaps") t)
(defun vla-put-visible (tb v)
  (setq stub:*visible* v) (stub:ev "visible") t)
(defun vla-float (tb top left rows)
  (setq stub:*float* (list top left rows)) (stub:ev "float") t)
(defun c:SPA ()
  (setq stub:*ran* (cons "SPA" stub:*ran*)) (stub:ev "run SPA") (princ))
'''

# --- the ADODB.Stream surface, as Python builtins (variable arity) ---
import lispvm  # noqa: E402

COM = {}


def _reset_com():
    COM.clear()
    COM.update(created=[], props={}, calls=[], bytes=None, saved=None,
               released=0, fail_at=None)


def _b(name):
    def deco(fn):
        lispvm.BUILTINS[lispvm.Sym(name)] = fn
        return fn
    return deco


@_b('vlax-create-object')
def _create(vm, a):
    COM['created'].append(str(a[0]))
    if COM.get('fail_at') == 'create':
        raise lispvm.LispError('Automation Error', vm)
    return 'STREAM'


@_b('vlax-put')
def _put(vm, a):
    COM['props'][str(a[1]).lower()] = a[2]
    return a[2]


@_b('vlax-make-safearray')
def _mksa(vm, a):
    return ['SAFEARRAY', a[0]]


@_b('vlax-safearray-fill')
def _fill(vm, a):
    COM['bytes'] = [int(x) for x in a[1]]
    return a[0]


@_b('vlax-release-object')
def _rel(vm, a):
    COM['released'] += 1
    return None


@_b('vlax-invoke')
def _invoke(vm, a):
    m = str(a[1]).lower()
    COM['calls'].append(m)
    if COM.get('fail_at') == m:
        raise lispvm.LispError('Automation Error', vm)
    if m == 'savetofile':
        COM['saved'] = (str(a[2]), a[3])
    return None


def stubbed(preload=False):
    """A VM with the stubs in place.  preload=True installs them BEFORE
    the file loads, so the load-time (lzp:button-init) call at the foot
    of LAZPANEL.lsp runs against them -- that call IS the feature, and
    without it the call silently no-ops behind vl-catch-all-apply and
    nothing here would notice it being deleted."""
    _reset_com()
    vm = VM()
    if preload:
        vm.loads(STUB)
        vm.load(LSP)
    else:
        vm.load(LSP)
        vm.loads(STUB)
    return vm


def run(vm, name, label):
    try:
        vm.run(name, [])
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None


def events(vm):
    return [str(e) for e in reversed(vm.globals.get('stub:*events*') or [])]


DIALOG = ['close', 'load', 'new', 'start', 'unload',
          'delete /stub/lazpanel.dcl']

vm = stubbed()
run(vm, 'c:LAZPANEL', 'close')
assert not vm.globals.get('stub:*ran*'), "Close launched something"
written = [str(l) for l in reversed(vm.globals.get('stub:*written*'))]
assert written == dcl, "written DCL differs from lzp:dcl-lines"
assert events(vm) == DIALOG, events(vm)
assert str(vm.globals.get('stub:*dlgname*')) == dcl[0].split(' : ')[0], \
    "new_dialog name does not match the DCL id"
acts = vm.globals.get('stub:*action*')
assert set(str(a[0]) for a in acts) == set(PANEL)
assert '1 of %d' % len(PANEL) in str(vm.globals.get('stub:*status*'))
disabled = set(map(str, vm.globals.get('stub:*disabled*')))
assert disabled == set(PANEL) - {'SPA'}, disabled ^ (set(PANEL) - {'SPA'})
assert vm.globals.get('lzp:*pick*') is None, "pick survived the run"
print("   Close: nothing ran, close->load->new->start->unload->delete,")
print("   dialog id matches, only SPA enabled")

vm = stubbed()
vm.loads('(setq stub:*click* "SPA")')
run(vm, 'c:LAZPANEL', 'click-spa')
assert [str(x) for x in vm.globals.get('stub:*ran*')] == ['SPA']
assert vm.globals.get('lzp:*pick*') is None, "pick not cleared after launch"
assert events(vm) == DIALOG + ['run SPA'], events(vm)
print("   click SPA: the real action expression fires, SPA runs once,")
print("   and only after the dialog is unloaded and the temp file gone")

vm = stubbed()
vm.loads('(setq stub:*click* "POOL")')
run(vm, 'c:LAZPANEL', 'click-missing')
assert not vm.globals.get('stub:*ran*')
assert any('POOL is not loaded' in str(p) for p in vm.printed), vm.printed
print("   click on a missing command reports it instead of erroring")


print("== the screen button goes up as the file loads ==")
vm = stubbed(preload=True)
tbs = [str(x) for x in vm.globals.get('stub:*tbs*') or []]
assert tbs == ['LazPanel'], \
    "loading the file did not create the toolbar: %r" % tbs
ev = events(vm)
for want in ('add LazPanel', 'addbutton', 'setbitmaps', 'visible', 'float'):
    assert want in ev, "%r missing from the load-time sequence %r" % (want, ev)
assert ev.index('add LazPanel') < ev.index('addbutton') < ev.index('setbitmaps')
print("   loading LAZPANEL.lsp creates it, ices it and floats it")

idx, name, help_, macro = vm.globals.get('stub:*addargs*')
assert int(idx) == 0, (
    "button index must be 0 -- the toolbar is created empty, so 1 is past "
    "its end (got %r)" % idx)
assert str(name) == 'LazPanel', name
assert 'LazPanel' in str(help_), help_
assert str(macro) == '\x03\x03_LAZPANEL ', (
    "macro must be raw ASCII-3 cancels + the command, not the ^C^C spelling "
    "a menu FILE would use: %r" % str(macro))
assert [int(x) for x in vm.globals.get('stub:*float*')] == [200, 300, 1], \
    vm.globals.get('stub:*float*')
print("   button at index 0, ^C^C macro as raw ASCII 3, floated at 200,300")


print("== the icon is written as real binary, not text ==")
assert COM['created'] == ['ADODB.Stream'] * 2, COM['created']
assert int(COM['props']['type']) == 1, COM['props']      # adTypeBinary
assert COM['calls'].count('open') == 2 and COM['calls'].count('write') == 2
assert COM['saved'][1] == 2, COM['saved']                # overwrite if present
assert COM['released'] == 2, "the stream object must be released"
bitmaps = [str(x) for x in vm.globals.get('stub:*bitmaps*') or []]
assert len(bitmaps) == 2 and bitmaps[0].endswith('16.bmp') \
    and bitmaps[1].endswith('32.bmp'), bitmaps

grid = [str(r) for r in vm.globals.get('lzp:*icon16*')]
assert len(grid) == 16 and all(len(r) == 16 for r in grid), grid
ORANGE, GREY = [0, 165, 255], [54, 54, 54]


def le(bb):
    n = 0
    for i, b in enumerate(bb):
        n += b << (8 * i)
    return n


def check_bmp(bb, size, grid):
    assert len(bb) == 54 + size * size * 3, (size, len(bb))
    assert bb[0] == 66 and bb[1] == 77, "no BM signature"
    assert le(bb[2:6]) == len(bb), "file size field wrong"
    assert le(bb[10:14]) == 54 and le(bb[14:18]) == 40
    assert le(bb[18:22]) == size and le(bb[22:26]) == size
    assert le(bb[26:28]) == 1 and le(bb[28:30]) == 24
    assert le(bb[34:38]) == size * size * 3
    assert (3 * size) % 4 == 0, "row width must be a multiple of 4"
    px = bb[54:]
    # WHERE the orange is, not just how much of it there is: a BMP with
    # a positive height stores the BOTTOM row of the image first, so an
    # icon written top-down comes out upside down -- and an L is not
    # symmetric, so that is a visible bug a pixel COUNT sails past.
    for gy, row in enumerate(grid):
        fy = size - 1 - gy                      # grid row -> file row
        for gx, ch in enumerate(row):
            i = (fy * size + gx) * 3
            got, want = px[i:i + 3], (ORANGE if ch == 'X' else GREY)
            assert got == want, (
                "pixel (%d,%d) of the %dx%d icon is %r, expected %r -- the "
                "image is scrambled or upside down"
                % (gx, gy, size, size, got, want))


grid32 = [str(r) for r in vm.globals.get('lzp:*icon32*')]
assert len(grid32) == 32 and all(len(r) == 32 for r in grid32), grid32
check_bmp(COM['bytes'], 32, grid32)
print("   ADODB.Stream in binary mode, released; every pixel of the 32x32")
print("   in its right place (bottom-up rows, B G R order)")

_reset_com()
vm.loads('(lzp:bmp-write "/stub/small.bmp" 16 lzp:*icon16*)')
check_bmp(COM['bytes'], 16, grid)
nuls = COM['bytes'].count(0)
assert nuls > 0
print("   and every pixel of the 16x16 -- %d of its bytes are NUL, which is"
      % nuls)
print("   exactly why write-char could never have written this file")


print("== a stable icon path, so a surviving toolbar keeps its picture ==")
vm2 = stubbed(preload=True)
vm2.loads('(setvar "TEMPPREFIX" "/tmp/acad/") (setq t:*p* (lzp:icon-path "16"))')
assert str(vm2.globals['t:*p*']) == '/tmp/acad/lazpanel-16.bmp', \
    vm2.globals['t:*p*']
print("   icons live at a fixed name under TEMPPREFIX, rewritten each load")


print("== reuse: the toolbar is kept, but re-iced and re-shown ==")
vm3 = stubbed(preload=True)
vm3.loads('(setq stub:*events* nil stub:*bitmaps* nil stub:*visible* nil'
          '      stub:*float* nil)'
          '(setq t:*tb* (lzp:button-init))')
tbs = [str(x) for x in vm3.globals.get('stub:*tbs*') or []]
assert tbs == ['LazPanel'], "a second init duplicated the toolbar: %r" % tbs
ev = events(vm3)
assert 'add LazPanel' not in ev, "the existing toolbar was recreated"
assert 'setbitmaps' in ev, "icons were not re-applied to the existing toolbar"
# the CALL is what matters, not the argument: :vlax-true is an AutoCAD
# constant this VM does not define, so it arrives as nil here
assert 'visible' in ev, "a toolbar the user had closed is never re-shown"
assert not vm3.globals.get('stub:*float*'), \
    "a toolbar the user has placed must not be floated out from under them"
print("   reused, icons re-applied, made visible, and NOT re-floated")


print("== a toolbar that cannot get its button does not survive ==")
vm4 = stubbed()
vm4.loads('(setq stub:*addfail* t) (setq t:*tb* (lzp:button-init))')
tbs = [str(x) for x in vm4.globals.get('stub:*tbs*') or []]
assert tbs == [], (
    "an empty LazPanel toolbar was left behind: lzp:toolbar-find would hand "
    "it back for ever, and LAZBUTTON would report success while showing "
    "nothing")
assert str(vm4.globals.get('stub:*deleted-tb*')) == 'LazPanel'
assert vm4.globals.get('t:*tb*') is None, "a failed init must report nil"
print("   the half-made toolbar is deleted and nil reported, so LAZBUTTON")
print("   can try again instead of being defeated for ever")


print("== LAZBUTTON ==")
vm5 = stubbed()
run(vm5, 'c:LAZBUTTON', 'lazbutton')
assert any('on screen' in str(p) for p in vm5.printed), vm5.printed
assert [str(x) for x in vm5.globals.get('stub:*tbs*') or []] == ['LazPanel']
print("   creates it on demand and says where it went")

vm6 = stubbed()
vm6.loads('(setq stub:*addfail* t)')
run(vm6, 'c:LAZBUTTON', 'lazbutton-unavailable')
assert any('menu API is unavailable' in str(p) for p in vm6.printed), \
    "the unavailable branch is unreachable: %r" % vm6.printed
print("   and says so plainly when the menu API will not have it")


print("== LAZPANELVER ==")
vm = fresh()
vm.run('c:LAZPANELVER', [])
out = ''.join(str(p) for p in vm.printed)
assert str(ver) in out and str(len(PANEL)) in out, out
print("   reports %s and the %d-tool roster" % (ver, len(PANEL)))

print("ALL LAZPANEL TESTS PASSED")
