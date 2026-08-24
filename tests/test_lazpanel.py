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
# is the panel itself, LAZBUTTON its toolbar summoner and LAZICON the
# diagnostic that reports where the button's picture came from: none of
# the three is a drafting tool, so none belongs on the panel.
satellites |= {'DCE', 'STOCKLIST', 'LAZPANEL', 'LAZBUTTON', 'LAZICON'}

headline = ALL - satellites - HELD
assert headline == set(PANEL), (
    "panel and tree disagree.\n  needs a button: %r\n  stale button: %r"
    % (sorted(headline - set(PANEL)), sorted(set(PANEL) - headline)))
overlap = set(PANEL) & HELD
assert not overlap, "held-back commands with buttons: %r" % overlap
print("   %d headline commands, all on the panel; %d held back, none on it"
      % (len(headline), len(HELD)))


print("== the generated DCL is well formed, one page per group ==")
vm.loads('(setq test:*dcl* (lzp:dcl-lines))')
dcl = [str(l) for l in vm.globals.get('test:*dcl*')]
GROUPS = [str(g[0]) for g in vm.globals['lzp:*groups*']]

opens = [l for l in dcl if l.endswith(' : dialog {')]
assert len(opens) == len(GROUPS), (
    "%d dialogs for %d groups" % (len(opens), len(GROUPS)))
depth = 0
for line in dcl:
    assert line.count('"') % 2 == 0, "odd quotes: %r" % line
    depth += line.count('{') - line.count('}')
    assert depth >= 0, line
assert depth == 0, "unbalanced braces across the file"

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


def page(group):
    vm.loads('(setq test:*n* (lzp:dlgname "%s"))' % group)
    name = str(vm.globals['test:*n*'])
    i = dcl.index(name + ' : dialog {')
    d = 0
    for j in range(i, len(dcl)):
        d += dcl[j].count('{') - dcl[j].count('}')
        if d == 0:
            return dcl[i:j + 1]
    raise AssertionError("%s never closes" % name)


# DCL does not scroll, so a dialog wider than the screen has nowhere to
# go.  The tab strip is on every page and never changes, so it gets a
# budget: full group titles are short, but the check is what stops a
# future rename making the panel unopenable.
TAB_BUDGET = 90
seen_keys = set()
for gname in GROUPS:
    d = page(gname)
    assert d[0].endswith(' : dialog {'), \
        "%s: page does not open with its dialog line: %r" % (gname, d[0])
    assert d[1].strip().startswith('label = '), \
        "%s: the label is not the first thing inside the dialog: %r" % (gname, d[1])
    text = '\n'.join(d)
    keys = re.findall(r'key = "([^"]+)"', text)
    assert len(keys) == len(set(keys)), "%s: duplicate tile keys" % gname
    # a tab for every group, on every page
    tabs = re.findall(r'key = "tab_([^"]+)"; label = "([^"]+)"', text)
    assert [t[0] for t in tabs] == GROUPS, \
        "%s: tab strip is %r, expected %r" % (gname, [t[0] for t in tabs], GROUPS)
    wide = sum(len(t[1]) + 6 for t in tabs)
    assert wide <= TAB_BUDGET, (
        "%s: the tab strip is about %d characters wide, over the %d budget "
        "-- DCL will not scroll a dialog wider than the screen" % (gname, wide, TAB_BUDGET))
    # this page carries exactly its own group's commands
    vm.loads('(setq test:*g* (lzp:group-commands "%s"))' % gname)
    mine = [str(x) for x in vm.globals['test:*g*']]
    assert set(mine) <= set(keys), \
        "%s: commands with no button: %r" % (gname, sorted(set(mine) - set(keys)))
    for other in GROUPS:
        if other == gname:
            continue
        vm.loads('(setq test:*o* (lzp:group-commands "%s"))' % other)
        strays = set(str(x) for x in vm.globals['test:*o*']) & set(keys)
        assert not strays, \
            "%s: carries %s's commands too: %r" % (gname, other, sorted(strays))
    seen_keys |= set(mine)
    assert 'status' in keys and 'cancel' in keys, gname
    assert text.count('is_cancel = true') == 1
    for line in d[1:]:
        s2 = line.strip()
        if s2 in ('}', 'spacer;'):
            continue
        m = OPEN_RE.fullmatch(s2)
        if m:
            assert m.group(1) in TILES, "unknown tile %r in %r" % (m.group(1), line)
            continue
        m = INLINE_RE.fullmatch(s2)
        if m:
            assert m.group(1) in TILES, "unknown tile %r in %r" % (m.group(1), line)
            check_clauses(m.group(2), line)
            continue
        assert PLAIN_RE.fullmatch(s2), "not a valid DCL line: %r" % line
        check_clauses(s2, line)
    print("   %-11s %2d lines, %2d commands, tab strip ~%d chars"
          % (gname, len(d), len(mine), wide))

# every command on the roster lives on exactly one page
assert seen_keys == set(PANEL), (
    "pages and roster disagree: %r" % sorted(seen_keys ^ set(PANEL)))
print("   %d dialogs, %d commands across them, none on two pages"
      % (len(opens), len(seen_keys)))

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
      stub:*deleted-tb* nil stub:*addfail* nil stub:*rcs* nil
      stub:*nosupport* nil)
(defun stub:ev (e) (setq stub:*events* (cons e stub:*events*)) e)
(defun vl-filename-mktemp (pat dir ext) (strcat "/stub/" pat ext))
(defun open (f mode) f)
(defun write-line (s fh)
  (setq stub:*written* (cons s stub:*written*)) s)
(defun close (fh) (stub:ev "close"))
(defun load_dialog (f) (stub:ev "load") 7)
(defun term_dialog () nil)
(defun set_tile (k v)
  (if (= k "status") (setq stub:*status* v)) v)
(defun action_tile (k expr)
  (setq stub:*action* (cons (list k expr) stub:*action*)) t)
(defun mode_tile (k m)
  (if (= m 1) (setq stub:*disabled* (cons k stub:*disabled*))) t)
;; DCL hands back where the dialog was standing, so the next page can
;; open in the same place instead of wandering
(defun done_dialog (status) (setq stub:*done* status) (list 120 340))
(defun start_dialog ( / pair)
  (if stub:*rcs*
    (setq stub:*rc* (car stub:*rcs*) stub:*rcs* (cdr stub:*rcs*)))
  (stub:ev "start")
  (setq stub:*done* nil)
  (if (setq pair (assoc stub:*click* stub:*action*))
    (progn
      (setq $key (car pair) $value nil $reason 1)
      (eval (read (strcat "(progn " (cadr pair) ")")))
      ;; a click happens ONCE -- left armed it re-fires on the page it
      ;; just opened, and a tab would reopen itself for ever
      (setq stub:*click* nil)))
  (if stub:*done* stub:*done* stub:*rc*))
(defun unload_dialog (id) (stub:ev "unload"))
(defun vl-file-delete (f) (stub:ev (strcat "delete " f)) t)
(defun vlax-get-acad-object () "ACAD")
(defun vla-get-menugroups (app) "MGS")
(defun vla-get-toolbars (mg) "TBS")
(defun vla-get-preferences (app) "PREFS")
(defun vla-get-files (prefs) "FILES")
(defun vla-get-supportpath (files)
  (if stub:*nosupport* (exit) "/stub/support;/stub/other"))
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
    OPENED.clear()
    COM.clear()
    COM.update(created=[], props={}, calls=[], bytes=None, saved=None,
               released=0, fail_at=None)


def _b(name):
    def deco(fn):
        lispvm.BUILTINS[lispvm.Sym(name)] = fn
        return fn
    return deco


OPENED = []


@_b('new_dialog')
def _newdlg(vm, a):
    # 2 args on the first open, 4 once a position is known, so the
    # position threading is provable and a fixed-arity stub cannot
    # express it
    OPENED.append((str(a[0]), len(a)))
    vm.globals[lispvm.Sym('stub:*dlgname*')] = str(a[0])
    vm.globals[lispvm.Sym('stub:*action*')] = None
    vm.loads('(stub:ev "new")')
    return True


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
        COM.setdefault('saves', []).append(str(a[2]))
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
vm.loads('(setq test:*n* (lzp:dlgname "%s"))' % GROUPS[0])
assert str(vm.globals.get('stub:*dlgname*')) == str(vm.globals['test:*n*']), \
    "new_dialog opened %r, not the first page" % vm.globals.get('stub:*dlgname*')
# only THIS page's commands are bound now -- that is the point of the
# pages -- plus a tab for every group
vm.loads('(setq test:*g* (lzp:group-commands "%s"))' % GROUPS[0])
first = [str(x) for x in vm.globals['test:*g*']]
acts = {str(a[0]) for a in vm.globals.get('stub:*action*')}
assert set(first) <= acts, sorted(set(first) - acts)
for g in GROUPS:
    assert 'tab_%s' % g in acts, "no tab callback for %s" % g
strays = acts & (set(PANEL) - set(first))
assert not strays, "another page's commands were bound too: %r" % sorted(strays)
# the status line still counts the WHOLE roster, not just this page
assert '1 of %d' % len(PANEL) in str(vm.globals.get('stub:*status*'))
disabled = set(map(str, vm.globals.get('stub:*disabled*')))
assert disabled == set(first) - {'SPA'}, disabled ^ (set(first) - {'SPA'})
assert vm.globals.get('lzp:*pick*') is None, "pick survived the run"
print("   Close: nothing ran, close->load->new->start->unload->delete,")
print("   only the first page's %d commands bound, only SPA enabled"
      % len(first))

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
# The FILES go into the first support-path folder; SetBitmaps is handed
# the bare NAMES.  The CUI resolves a toolbar bitmap by name along the
# support search path, and a full path into the temp folder -- which is
# not on that path -- is exactly the "?" placeholder the button showed.
# the stub folder carries no trailing separator, so the code adds the
# Windows one -- which is the point of the guard
assert COM.get('saves') == ['/stub/support\\lazpanel-16.bmp',
                            '/stub/support\\lazpanel-32.bmp'], COM.get('saves')
bitmaps = [str(x) for x in vm.globals.get('stub:*bitmaps*') or []]
assert bitmaps == ['lazpanel-16.bmp', 'lazpanel-32.bmp'], (
    "SetBitmaps must get support-resolvable NAMES, not paths: %r" % bitmaps)

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


print("== no support folder: full temp paths, the best that is left ==")
vmf = stubbed(preload=True)
vmf.loads('(setq stub:*nosupport* t)'
          '(setvar "TEMPPREFIX" "/tmp/acad/")'
          '(setq t:*b* (lzp:write-bmps))')
fb = [str(x) for x in (vmf.globals.get('t:*b*') or [])]
assert fb == ['/tmp/acad/lazpanel-16.bmp', '/tmp/acad/lazpanel-32.bmp'], fb
assert str(vmf.globals.get('lzp:*iconref*')) == 'path', \
    vmf.globals.get('lzp:*iconref*')
print("   support path unreadable -> temp folder and full paths")


print("== a stable icon path, so a surviving toolbar keeps its picture ==")
vm2 = stubbed(preload=True)
for prefix, want in (
        # the usual shape: AutoCAD hands back a folder with a separator
        ('C:\\Temp\\', 'C:\\Temp\\lazpanel-16.bmp'),
        ('/tmp/acad/', '/tmp/acad/lazpanel-16.bmp'),
        # and the shape the guard exists for: no separator at all, which
        # silently turns a folder called Temp into a file called
        # Templazpanel-16.bmp that SetBitmaps then cannot read
        ('C:\\Temp', 'C:\\Temp\\lazpanel-16.bmp')):
    vm2.loads('(setvar "TEMPPREFIX" "%s") (setq t:*p* (lzp:icon-path "16"))'
              % prefix.replace('\\', '\\\\'))
    got = str(vm2.globals['t:*p*'])
    assert got == want, "TEMPPREFIX %r gave %r, expected %r" % (prefix, got, want)
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


print("== a tab opens the next page ==")
vm7 = stubbed()
vm7.loads('(setq stub:*rcs* \'(4 0))'
          '(setq stub:*click* "tab_%s")'
          '(setq t:*p* (lzp:show))' % GROUPS[1])
vm7.loads('(setq t:*n* (lzp:dlgname "%s"))' % GROUPS[1])
assert str(vm7.globals.get('stub:*dlgname*')) == str(vm7.globals['t:*n*']), (
    "the tab did not reopen on the %s page: %r"
    % (GROUPS[1], vm7.globals.get('stub:*dlgname*')))
assert vm7.globals.get('t:*p*') is None, "a tab click launched something"
ev = events(vm7)
assert ev.count('new') == 2, "the page did not reopen: %r" % ev
print("   a tab closes this page and opens %s, launching nothing"
      % GROUPS[1])


print("== LAZPANELVER ==")
vm = fresh()
vm.run('c:LAZPANELVER', [])
out = ''.join(str(p) for p in vm.printed)
assert str(ver) in out and str(len(PANEL)) in out, out
print("   reports %s and the %d-tool roster" % (ver, len(PANEL)))

print("ALL LAZPANEL TESTS PASSED")
