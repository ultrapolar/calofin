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

# The manifest's comment names the order that matters -- the library
# first, every tool before the demo, tutorial or form that drives it,
# PADDLE before the LINGUTTER that hands it a drawing, and the panel
# last, after everything its buttons name.  Nothing enforced it: a
# reorder loaded cleanly and this test followed ORDER wherever it went.
print('shared -- the loader lists its members in the order the comment promises')


def before(a, b):
    assert ORDER.index(a) < ORDER.index(b), '%s must load before %s' % (a, b)


assert ORDER[0] == 'CALOFIN-LIB.lsp', ORDER[0]
assert ORDER[-1] == 'LAZPANEL.lsp', ORDER[-1]
for tool, dependants in (('POOL.lsp', ('POOLDEMO.lsp', 'TUTORIALPOOL.lsp', 'LAZFORM.lsp')),
                         ('SPA.lsp', ('TUTORIALSPA.lsp', 'LAZSPA.lsp')),
                         ('PADDLE.lsp', ('LINGUTTER.lsp',)),
                         ('CORNERSTP.lsp', ('LAZSTEP.lsp',))):
    for d in dependants:
        before(tool, d)
print('  library first, panel last, every driver after what it drives')

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
# the same claim about the library helpers the tools call: every one is
# bound, and a build that lost one would name it rather than wait for
# the first click
helpers = bvm.globals.get('lazpass:*helpers*')
if not helpers:
    fail('the bundle does not declare lazpass:*helpers*')
unbound = [str(h) for h in helpers
           if not (isinstance(bvm.globals.get(h), tuple)
                   and bvm.globals.get(h)[0] == 'defun')]
if unbound:
    fail('library helpers the bundle calls but does not define: %s' % unbound)
if bvm.globals.get('lazpass:*nohelper*'):
    fail('the bundle reported helpers missing on a clean load: %s'
         % bvm.globals.get('lazpass:*nohelper*'))
print('  %d library helpers called by the tools, every one bound' % len(helpers))

# the header tells the library it is arriving as part of a build; the
# footer takes that back, so a later solo APPLOAD of CALOFIN-LIB.lsp
# in the same drawing still says what it is
if bvm.globals.get('cal:*build-loading*') not in (None, lispvm.NIL):
    fail('the bundle left cal:*build-loading* set')
bvm.printed.clear()
bvm.load(os.path.join(PARTS, 'CALOFIN-LIB.lsp'))
if not any('helper library ONLY' in str(s) for s in bvm.printed):
    fail('a solo library load after the bundle no longer warns')
print('  and a solo library load afterwards still says it brings no tools')

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
