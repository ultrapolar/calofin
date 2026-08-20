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
LISP = os.path.join(REPO, 'lisp')

# Must mirror the foreach lists in shared/CALOFIN-LOADER.lsp.
ORDER = [
    'CALOFIN-LIB.lsp',
    'POOL.lsp', 'POOLDEMO.lsp', 'TUTORIALPOOL.lsp',
    'SPA.lsp', 'TUTORIALSPA.lsp',
    'abcdef.lsp', 'ALTABCDEF.lsp', 'abhd.lsp', 'AUTOBEAD.lsp',
    'AutoDim.lsp', 'BPCALLOUT.lsp', 'ccprecheck.lsp',
    'CDCALLOUT.lsp', 'CDCREATE.lsp', 'check_drawing.lsp',
    'CORNERSTP.lsp', 'HEMISTEP.lsp', 'NORMIESTEP.lsp',
    'covercheck.lsp', 'dimcheck.lsp', 'dim_continue.lsp',
    'DroneDistortion.lsp', 'DroneHeightGPS.lsp',
    'lhd.lsp', 'lincheck.lsp', 'linfincheck.lsp', 'LINTXTCHK.lsp',
    'PADDLE.lsp', 'perp_points.lsp', 'cperp_points.lsp',
    'tutorial_perp_points.lsp', 'tutorial_cperp_points.lsp',
    'STOCKCOVER.lsp', 'tydrn.lsp', 'wcalst.lsp', 'xftconv.lsp',
]
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


paths = [os.path.join(SHARED, f) for f in ORDER]
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

print('ALL SHARED-BUILD CHECKS PASSED')
