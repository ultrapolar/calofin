"""CALPANEL: the DCL launcher panel, in the AutoLISP VM.

Three jobs:

1. Pin the roster to the tree.  Every headline command defined under
   lisp/ must have a button, so a new tool without one fails here
   instead of being quietly missing (satellites -- TUTORIAL*, *VER /
   *VERSION reporters, *RESCUE companions, -CFG / -SETUP partners, the
   DD* sub-commands, DCE and STOCKLIST -- are exempt).  Held-back tools
   (cal:*held-back* in CALOFIN-LOADER.lsp) and the deprecated acady
   matcher must NOT have buttons.

2. Check the generated DCL is well formed: balanced braces, even
   quotes, one key per button matching the roster, one cancel tile.

3. Drive c:CALPANEL end-to-end with the DCL surface stubbed (the VM has
   no dialog or file i/o builtins): Close launches nothing, a click
   launches the picked command, greyed buttons are exactly the missing
   commands, and the temp .dcl is written and deleted either way.

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
LSP = os.path.join(REPO, 'lisp', 'calpanel', 'CALPANEL.lsp')
LOADER = os.path.join(REPO, 'shared', 'parts', 'CALOFIN-LOADER.lsp')
PARTS = os.path.join(REPO, 'shared', 'parts')

CMD_RE = re.compile(r'^\(defun\s+[cC]:([^\s()]+)', re.M)
HELD_RE = re.compile(r'\("([^"]+)"\s*\.\s*"(?:WIP|OMITTED)"\)')


def fresh():
    vm = VM()
    vm.load(LSP)
    return vm


def roster(vm):
    groups = vm.globals.get('cpl:*groups*') or []
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
ver = vm.globals.get('*calpanel-version*')
assert ver and re.fullmatch(r'v\d+\.\d+', str(ver)), ver
assert any('CALPANEL' in str(p) for p in vm.printed), vm.printed
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
# companion -- both reachable, neither needs its own button.  CALPANEL
# is the panel itself.
satellites |= {'DCE', 'STOCKLIST', 'CALPANEL'}

headline = ALL - satellites - HELD
assert headline == set(PANEL), (
    "panel and tree disagree.\n  needs a button: %r\n  stale button: %r"
    % (sorted(headline - set(PANEL)), sorted(set(PANEL) - headline)))
overlap = set(PANEL) & HELD
assert not overlap, "held-back commands with buttons: %r" % overlap
print("   %d headline commands, all on the panel; %d held back, none on it"
      % (len(headline), len(HELD)))


print("== the generated DCL is well formed ==")
vm.loads('(setq test:*dcl* (cpl:dcl-lines))')
dcl = [str(l) for l in vm.globals.get('test:*dcl*')]
assert dcl[0] == 'calpanel : dialog {', dcl[0]
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
# so the wiring string in CALPANEL.lsp is executed here, not assumed.
STUB = '''
(setq stub:*written* nil stub:*disabled* nil stub:*action* nil
      stub:*events* nil stub:*click* nil stub:*status* nil
      stub:*ran* nil stub:*dlgname* nil stub:*done* nil)
(defun stub:ev (e) (setq stub:*events* (cons e stub:*events*)) e)
(defun vl-filename-mktemp (pat dir ext) "/stub/calpanel.dcl")
(defun open (f mode) 'FH)
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
(defun c:SPA ()
  (setq stub:*ran* (cons "SPA" stub:*ran*)) (stub:ev "run SPA") (princ))
'''


def stubbed():
    vm = fresh()
    vm.loads(STUB)
    return vm


def run(vm, label):
    try:
        vm.run('c:CALPANEL', [])
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None


def events(vm):
    return [str(e) for e in reversed(vm.globals.get('stub:*events*') or [])]


vm = stubbed()
run(vm, 'close')
assert not vm.globals.get('stub:*ran*'), "Close launched something"
written = [str(l) for l in reversed(vm.globals.get('stub:*written*'))]
assert written == dcl, "written DCL differs from cpl:dcl-lines"
assert events(vm) == ['close', 'load', 'new', 'start', 'unload',
                      'delete /stub/calpanel.dcl'], events(vm)
assert str(vm.globals.get('stub:*dlgname*')) == \
    dcl[0].split(' : ')[0], "new_dialog name does not match the DCL id"
acts = vm.globals.get('stub:*action*')
assert set(str(a[0]) for a in acts) == set(PANEL)
assert '1 of %d' % len(PANEL) in str(vm.globals.get('stub:*status*'))
disabled = set(map(str, vm.globals.get('stub:*disabled*')))
assert disabled == set(PANEL) - {'SPA'}, disabled ^ (set(PANEL) - {'SPA'})
assert vm.globals.get('cpl:*pick*') is None, "pick survived the run"
print("   Close: nothing ran, close->load->new->start->unload->delete,")
print("   dialog id matches, only SPA enabled")

vm = stubbed()
vm.loads('(setq stub:*click* "SPA")')
run(vm, 'click-spa')
assert [str(x) for x in vm.globals.get('stub:*ran*')] == ['SPA']
assert vm.globals.get('cpl:*pick*') is None, "pick not cleared after launch"
assert events(vm) == ['close', 'load', 'new', 'start', 'unload',
                      'delete /stub/calpanel.dcl', 'run SPA'], events(vm)
print("   click SPA: the real action expression fires, SPA runs once,")
print("   and only after the dialog is unloaded and the temp file gone")

vm = stubbed()
vm.loads('(setq stub:*click* "POOL")')
run(vm, 'click-missing')
assert not vm.globals.get('stub:*ran*')
assert any('POOL is not loaded' in str(p) for p in vm.printed), vm.printed
print("   click on a missing command reports it instead of erroring")


print("== CALPANELVER ==")
vm = fresh()
vm.run('c:CALPANELVER', [])
out = ''.join(str(p) for p in vm.printed)
assert str(ver) in out and str(len(PANEL)) in out, out
print("   reports %s and the %d-tool roster" % (ver, len(PANEL)))

print("ALL CALPANEL TESTS PASSED")
