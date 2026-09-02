"""The multi-file loader, CALOFIN-LOADER.lsp, run for the first time.

APPLOAD hands AutoCAD a full path but never adds the folder to the
support file search path, so the loader has four ways to find its
siblings: a cal:*dir* set by hand, the support path, a remembered
answer, and -- once -- a file dialog.  The remembered answer used to
live in the registry alone, and vl-registry-write answers a denied
HKCU with nil rather than an error, so on a locked-down machine the
loader asked the same question again on every drawing opened.  It
remembers through the profile (setenv) as well now, which is always
writable.

The whole ActiveX-free surface the loader touches is stubbed here in
Python -- findfile against a set of paths that "exist", a registry that
can be told to refuse, a profile, a file dialog that counts how often
it was opened, and a load that records what it was handed instead of
loading fifty-five files -- so each of the four ways in is driven on
its own, and the two that remember are driven twice.

Run: python3 tests/test_loader.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import lispvm  # noqa: E402
from lispvm import VM, NIL, T, Sym  # noqa: E402
from callib import LOADER, loader_members  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


MEMBERS = loader_members(LOADER)
DIR = 'D:\\Downloads\\calofin'

#: the machine, shared across VMs the way the registry and the profile
#: survive a drawing being closed
MACHINE = {}


def reset(registry_ok=True, on_path=False, dialog=DIR + '\\CALOFIN-LIB.lsp'):
    MACHINE.clear()
    MACHINE.update(registry={}, registry_ok=registry_ok, env={},
                   asked=0, dialog=dialog, loaded=[], on_path=on_path,
                   ondisk={DIR + '\\' + m for m in MEMBERS})


def _b(name):
    def deco(fn):
        lispvm.BUILTINS[Sym(name)] = fn
        return fn
    return deco


@_b('findfile')
def _findfile(vm, a):
    f = str(a[0])
    if f in MACHINE['ondisk']:
        return f
    # a bare name resolves along the support path only when the build
    # folder is on it
    if MACHINE['on_path'] and '\\' not in f and (DIR + '\\' + f) in MACHINE['ondisk']:
        return DIR + '\\' + f
    return NIL


@_b('vl-filename-directory')
def _dirname(vm, a):
    f = str(a[0])
    return f[:f.rfind('\\')] if '\\' in f else ''


@_b('vl-registry-read')
def _regread(vm, a):
    return MACHINE['registry'].get((str(a[0]), str(a[1])), NIL)


@_b('vl-registry-write')
def _regwrite(vm, a):
    if not MACHINE['registry_ok']:
        return NIL                          # denied: nil, no error
    MACHINE['registry'][(str(a[0]), str(a[1]))] = a[2]
    return a[2]


@_b('getenv')
def _getenv(vm, a):
    return MACHINE['env'].get(str(a[0]), NIL)


@_b('setenv')
def _setenv(vm, a):
    MACHINE['env'][str(a[0])] = a[1]
    return a[1]


@_b('getfiled')
def _getfiled(vm, a):
    MACHINE['asked'] += 1
    return MACHINE['dialog'] if MACHINE['dialog'] else NIL


@_b('load')
def _load(vm, a):
    MACHINE['loaded'].append(str(a[0]))
    return T


def load_loader():
    vm = VM()
    vm.load(str(LOADER))
    return vm


def said(vm):
    return ''.join(str(s) for s in vm.printed)


# ----------------------------------------------------------------------
print("statics")
SRC = open(LOADER, encoding='ascii').read()
check("the loader remembers through the profile as well as the registry",
      'setenv' in SRC and 'getenv' in SRC)

# ----------------------------------------------------------------------
print("1. the build folder is on the support path: nothing to ask")
reset(on_path=True)
vm = load_loader()
check("found it without a dialog", MACHINE['asked'] == 0)
check("loaded every member, in the manifest's order",
      [f.rsplit('\\', 1)[-1] for f in MACHINE['loaded']] == MEMBERS,
      repr(MACHINE['loaded'][:3]))
check("announced the folder and the build",
      DIR in said(vm) and 'shared build loaded' in said(vm), said(vm)[-200:])

# ----------------------------------------------------------------------
print("2. off the support path, registry writable: asked once, ever")
reset()
vm = load_loader()
check("the first load asks", MACHINE['asked'] == 1)
check("...and loads the build from the answer",
      len(MACHINE['loaded']) == len(MEMBERS) and 'shared build loaded' in said(vm))
vm = load_loader()
check("the second load remembers and does not ask", MACHINE['asked'] == 1,
      "asked %d times" % MACHINE['asked'])
check("...through the registry", (('HKEY_CURRENT_USER\\Software\\Calofin', 'SharedDir')
                                   in MACHINE['registry']))

# ----------------------------------------------------------------------
print("3. off the support path, registry DENIED: still asked once, ever")
reset(registry_ok=False)
vm = load_loader()
check("the first load asks", MACHINE['asked'] == 1)
check("the registry took nothing", not MACHINE['registry'])
vm = load_loader()
check("the second load remembers through the profile and does not ask",
      MACHINE['asked'] == 1, "asked %d times" % MACHINE['asked'])
check("and still loads the whole build",
      len(MACHINE['loaded']) == 2 * len(MEMBERS))

# ----------------------------------------------------------------------
print("4. nothing reachable and the dialog cancelled: says so, loads nothing")
reset(dialog=None)
vm = load_loader()
check("asked once", MACHINE['asked'] == 1)
check("loaded nothing", MACHINE['loaded'] == [])
check("said how to fix it",
      'Could not locate the build folder' in said(vm)
      and 'Support File Search Path' in said(vm), said(vm)[-300:])

# ----------------------------------------------------------------------
print("5. cal:*dir* set by hand wins over everything")
reset(registry_ok=False, dialog=None)
vm = VM()
vm.loads('(setq cal:*dir* "%s")' % DIR.replace('\\', '\\\\'))
vm.load(str(LOADER))
check("no dialog, every member loaded",
      MACHINE['asked'] == 0 and len(MACHINE['loaded']) == len(MEMBERS))

# ----------------------------------------------------------------------
print("6. a member missing from the folder is counted, not fatal")
reset(on_path=True)
MACHINE['ondisk'].discard(DIR + '\\XYPLOT.lsp')
vm = load_loader()
check("the missing file is named", 'MISSING: XYPLOT.lsp' in said(vm))
check("and the count says the folder is incomplete",
      '1 file(s) missing' in said(vm), said(vm)[-200:])

if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL LOADER TESTS PASSED")
