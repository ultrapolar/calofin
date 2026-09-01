"""Tests for the library's sysvar snapshot, cal:syssave / cal:sysrestore.

Every tool in the grouped build shares the ONE snapshot in
cal:*sysold*, and the tools list different variables.  The snapshot is
never re-taken for a variable already in it -- after a run cut short,
the pending entry is the user's true value and the live one is the
zeroed OSMODE the dead run left behind -- but a variable the pending
snapshot lacks has to be ADDED, or the next tool changes CLAYER and
never puts it back because the run that took the snapshot never listed
it.  This file pins both halves of that.

The library is the same file at both tiers, so this test reads it from
shared/parts/ directly and CALOFIN_LISP_ROOT has no effect on it.

Run: python3 tests/test_calofin_lib.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
LIB = os.path.join(HERE, '..', 'shared', 'parts', 'CALOFIN-LIB.lsp')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def snapshot(vm):
    v = vm.globals.get(Sym('cal:*sysold*'))
    return [(p.a, p.b) for p in v] if v else []


def fresh():
    vm = VM()
    vm.load(LIB)
    vm.loads('''(entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord") '(2 . "WORK") '(70 . 0)
                 '(62 . 3) '(6 . "Continuous")))''')
    return vm


print("syssave -- a clean run")
vm = fresh()
vm.loads('(cal:syssave \'("OSMODE" "CMDECHO" "CLAYER"))')
check("captures every listed variable, in order",
      [k for k, _ in snapshot(vm)] == ['OSMODE', 'CMDECHO', 'CLAYER'],
      repr(snapshot(vm)))
vm.loads('(setvar "OSMODE" 0) (setvar "CMDECHO" 0) (setvar "CLAYER" "WORK")')
vm.loads('(cal:sysrestore)')
check("restore puts them back",
      vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1
      and vm.sysvars['CLAYER'] == '0', repr(vm.sysvars))
check("and clears the snapshot", snapshot(vm) == [])

print("syssave -- after a run that died with its snapshot pending")
vm = fresh()
# tool A: lists only OSMODE, zeroes it, and never gets to restore
vm.loads('(cal:syssave \'("OSMODE")) (cal:osdown)')
check("the dead run left OSMODE at 0 with its snapshot pending",
      vm.sysvars['OSMODE'] == 0 and snapshot(vm) == [('OSMODE', 4133)])
# tool B: lists OSMODE and CLAYER, changes both
vm.loads('(cal:syssave \'("OSMODE" "CLAYER"))')
check("OSMODE keeps the TRUE value from the pending snapshot, not the 0",
      dict(snapshot(vm))['OSMODE'] == 4133, repr(snapshot(vm)))
check("CLAYER, which the dead run never listed, is added",
      dict(snapshot(vm)).get('CLAYER') == '0', repr(snapshot(vm)))
check("OSMODE stays first, so it is restored first",
      [k for k, _ in snapshot(vm)] == ['OSMODE', 'CLAYER'])
vm.loads('(setvar "CLAYER" "WORK") (cal:osdown)')
vm.loads('(cal:sysrestore)')
check("tool B's restore puts BOTH back -- CLAYER included",
      vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CLAYER'] == '0',
      repr(vm.sysvars))
check("and the snapshot is clear for the next run", snapshot(vm) == [])

print("osup / osdown -- coupled to the snapshot")
vm = fresh()
vm.loads('(cal:syssave \'("CMDECHO" "OSMODE")) (cal:osdown)')
check("osdown zeroes the snaps", vm.sysvars['OSMODE'] == 0)
vm.loads('(cal:osup)')
check("osup brings the user's snaps back from the snapshot",
      vm.sysvars['OSMODE'] == 4133)
vm.loads('(cal:sysrestore)')

if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL CALOFIN-LIB TESTS PASSED")
