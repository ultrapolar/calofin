"""The shared/ build: everything loads together in ONE session.

Loads CALOFIN-LIB.lsp plus every tool file in shared/ (the same order
CALOFIN-LOADER.lsp uses) into a single lispvm VM and checks the
loaded-together assumptions:

  * every file parses and loads with the others already present
  * no top-level defun is defined by two different files (the per-tool
    prefixes are the collision guard; the library owns cal: alone)
  * every command the lisp/ tree defines exists in the shared build
    (lisp/standards_checker/ excepted - the acady matcher is a
    deprecated project and is not carried into the shared build)
  * the smoke commands run

The behavioral-parity check is separate: run the ordinary VM-driven
tests with CALOFIN_LISP_ROOT=shared (see lispvm.VM._remap_root).
"""
import os
import pathlib
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm
from lispvm import VM, Sym, parse_all

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SHARED = os.path.join(REPO, 'shared')
PARTS = os.path.join(SHARED, 'parts')
LISP = os.path.join(REPO, 'lisp')

# The loader is the single source of truth for both lists, so this test
# cannot drift from the build it is checking.
LOADER = os.path.join(PARTS, 'CALOFIN-LOADER.lsp')
_loader_src = open(LOADER).read()

#: the files compiled into the build, in load order
ORDER = re.findall(r'"([^"]+)"',
                   re.search(r"\(foreach m '\((.*?)\)\s*\n\s*\(cal--load m\)",
                             _loader_src, re.S).group(1))

#: name -> WIP | OMITTED, deliberately left out of the build
HELD = dict(re.findall(r'\("([^"]+)"\s*\.\s*"(WIP|OMITTED)"\)', _loader_src))

#: Not carried into the shared build: the acady drawing-standards
#: matcher is a deprecated project and stays in lisp/ only.
UNMIRRORED_DIRS = {'standards_checker'}


def top_level_defuns(path):
    """Names defined by (defun ...) forms at the top level of the file."""
    out = []
    for form in parse_all(open(path).read()):
        if (isinstance(form, list) and form
                and form[0] == Sym('defun') and len(form) > 1):
            out.append(str(form[1]))
    return out


def fail(msg):
    print('FAIL:', msg)
    sys.exit(1)


held_paths = [os.path.join(PARTS, f) for f in sorted(HELD)
              if os.path.exists(os.path.join(PARTS, f))]
paths = [os.path.join(PARTS, f) for f in ORDER] + held_paths
missing = [p for p in paths if not os.path.exists(p)]
if missing:
    fail('missing shared files: %s' % [os.path.relpath(p, REPO) for p in missing])

print('shared -- every file loads into one session')
vm = VM()
for p in paths:
    try:
        vm.load(p)
    except Exception as e:                      # noqa: BLE001 - report which file
        fail('%s failed to load: %s' % (os.path.relpath(p, REPO), e))
print('  %d files loaded' % len(paths))

print('shared -- no top-level defun collides across files')
owner = {}
collisions = []
for p in paths:
    for name in top_level_defuns(p):
        key = name.lower()                      # AutoLISP symbols fold case
        if key in owner and owner[key] != p:
            collisions.append('%s in %s and %s' % (
                name, os.path.relpath(owner[key], REPO), os.path.relpath(p, REPO)))
        owner.setdefault(key, p)
if collisions:
    fail('duplicate top-level defuns:\n  ' + '\n  '.join(collisions))
lib_owned = [n for n, p in owner.items()
             if n.startswith('cal:') and not p.endswith('CALOFIN-LIB.lsp')]
if lib_owned:
    fail('cal: symbols defined outside the library: %s' % lib_owned)
print('  %d distinct top-level defuns, cal: owned by the library alone' % len(owner))

print('shared -- every lisp/ command exists in the shared build')
lisp_cmds = set()
for root, _dirs, files in os.walk(LISP):
    if set(pathlib.PurePath(root).parts) & UNMIRRORED_DIRS:
        continue
    for f in files:
        if f.lower().endswith('.lsp'):
            src = open(os.path.join(root, f), errors='replace').read()
            for m in re.finditer(r'^\(defun\s+[cC]:([^\s()]+)', src, re.M):
                lisp_cmds.add(m.group(1).lower())
shared_cmds = {n[2:] for n in owner if n.startswith('c:')}
lost = sorted(lisp_cmds - shared_cmds)
if lost:
    fail('commands in lisp/ but not in shared/: %s' % lost)
print('  %d commands present' % len(shared_cmds))

print('shared -- smoke commands run')
for cmd in ('c:CALVER', 'c:POOLVER', 'c:SPAVER'):
    vm.run(cmd, [])
print('  CALVER / POOLVER / SPAVER ok')

print('shared -- the palette roster names only real commands')
# ui/calofin_ui/calofin.lsp lists what the VB palette can show; the
# list sat years behind the tree once, so it is pinned here: every
# non-deprecated name must be a command the grouped build defines.
GLUE = os.path.join(REPO, 'ui', 'calofin_ui', 'calofin.lsp')
roster = re.findall(r'"([A-Z0-9-]+)"',
                    re.search(r"calofin:\*commands\*\s*'\((.*?)\)\)",
                              open(GLUE).read(), re.S).group(1))
DEPRECATED = {'MATCHSTD', 'ACADY-SCAN'}     # acady matcher, lisp/-only
ghost = sorted(n for n in roster
               if n not in DEPRECATED and n.lower() not in shared_cmds)
if ghost:
    fail('calofin.lsp lists commands the build does not define: %s' % ghost)
print('  %d roster names, every one real (%d deprecated allowed)'
      % (len(roster), len(DEPRECATED)))

print('shared -- the one-file bundle carries the whole build')
BUNDLE = os.path.join(SHARED, 'LAZPASS.lsp')
if not os.path.exists(BUNDLE):
    fail('LAZPASS.lsp missing - run python3 tools/build_shared_bundle.py')
bvm = VM()
try:
    bvm.load(BUNDLE)                        # ONE file, nothing beside it
except Exception as e:                      # noqa: BLE001 - report the file
    fail('LAZPASS.lsp failed to load: %s' % e)
bundle_cmds = {str(k)[2:] for k in bvm.globals if str(k).startswith('c:')}

# what the manifest alone should put in the bundle
expected = set()
for f in ORDER:
    for n in top_level_defuns(os.path.join(PARTS, f)):
        if n.lower().startswith('c:'):
            expected.add(n.lower()[2:])
short = sorted(expected - bundle_cmds)
if short:
    fail('commands missing from LAZPASS.lsp: %s (rebuild it with '
         'python3 tools/build_shared_bundle.py)' % short)

# and a held-back tool must NOT have leaked in
leaked = []
for f, why in sorted(HELD.items()):
    fp = os.path.join(PARTS, f)
    if not os.path.exists(fp):
        continue
    for n in top_level_defuns(fp):
        if n.lower().startswith('c:') and n.lower()[2:] in bundle_cmds:
            leaked.append('%s (%s, from %s)' % (n, why, f))
if leaked:
    fail('held-back commands leaked into LAZPASS.lsp: %s' % leaked)
for cmd in ('c:CALVER', 'c:POOLVER', 'c:ABFINDVER'):
    bvm.run(cmd, [])
print('  %d commands from one APPLOAD, %d file(s) held back'
      % (len(bundle_cmds), len(HELD)))

# ONE external button from the whole build.  The panel's, and only the
# panel's: every tool it carries is reached THROUGH the panel, which is
# what a single strip button is for.  A tool that starts adding its own
# toolbar should fail here.
COM = """
(setq stub:*tbs* nil stub:*btns* nil)
(defun vlax-get-acad-object () "ACAD")
(defun vla-get-menugroups (app) "MGS")
(defun vla-get-toolbars (mg) "TBS")
(defun vla-get-preferences (app) "PREFS")
(defun vla-get-files (prefs) "FILES")
(defun vla-get-supportpath (files) "/stub/support")
(defun vla-get-count (obj) (if (= obj "MGS") 1 (length stub:*tbs*)))
(defun vla-get-name (tb) tb)
(defun vla-item (obj i)
  (cond ((= obj "MGS") "MG0")
        ((= obj "TBS") (nth i stub:*tbs*))
        (t (nth i stub:*btns*))))
(defun vla-add (tbs name)
  (setq stub:*tbs* (append stub:*tbs* (list name))) name)
(defun vla-addtoolbarbutton (tb idx name help macro)
  (setq stub:*btns* (append stub:*btns* (list "BTN"))) "BTN")
(defun vla-delete (tb) (setq stub:*tbs* (vl-remove tb stub:*tbs*)) t)
(defun vla-setbitmaps (btn s l) t)
(defun vla-put-largebuttons (tb v) t)
(defun vla-put-visible (tb v) t)
(defun vla-float (tb a b c) t)
(defun vlax-create-object (id) (exit))
"""
tvm = VM()
tvm.loads(COM)                              # the COM surface, then the build
tvm.load(BUNDLE)
raised = [str(x) for x in (tvm.get(Sym('stub:*tbs*')) or [])]
if raised != ['LazPanel']:
    fail('LAZPASS put up %r -- the build raises ONE external button, the '
         "panel's, and everything else is reached through it" % raised)
print('  one external button from the build, the panel\'s')

# The bundle checks its own claim.  The count used to be baked in at
# build time, so a build that half loaded still announced every command
# it was BUILT with -- and a command that never arrived is exactly what
# a greyed button on the panel means.
want = bvm.globals.get('lazpass:*want*')
if not want:
    fail('the bundle does not declare lazpass:*want*, so its load message '
         'is an unchecked claim')
want = set(str(x).lower() for x in want)
if want != bundle_cmds:
    fail('the bundle announces a different command set than it defines: %s'
         % sorted(want ^ bundle_cmds))
if bvm.globals.get('lazpass:*missing*'):
    fail('the bundle reported commands missing on a clean load: %s'
         % bvm.globals.get('lazpass:*missing*'))
# and it must NAME what is missing rather than just counting
mvm = VM()
mvm.load(BUNDLE)
mvm.loads('(setq c:OASIS nil)'
          '(setq lazpass:*missing* nil)'
          '(foreach n lazpass:*want*'
          '  (if (not (eval (read (strcat "C:" n))))'
          '    (setq lazpass:*missing* (cons n lazpass:*missing*))))')
gone = [str(x) for x in (mvm.globals.get('lazpass:*missing*') or [])]
if gone != ['OASIS']:
    fail('the bundle self-check did not notice a missing command: %r' % gone)
print('  and it checks its own claim: %d names declared, missing ones named'
      % len(want))

print('ALL SHARED-BUILD CHECKS PASSED')
