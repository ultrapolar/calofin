"""Runtime tests for OSR: the drafter's object snaps put back to the
preset they chose, and the options that choose it.

OSR asks nothing, so what these pin is where the number comes from:

  * a preset saved in the profile (CalofinOsnapPreset) is what lands in
    OSMODE, Object Snap OFF bit included;
  * with none saved, the shipped osr:*default*;
  * a profile value that is not an OSMODE -- a typo, a negative, past
    32767 -- is refused and the shipped one used, because atoi would
    read "12x" as 12 and "red" as 0, and 0 clears every snap.

Then the contract with LAZPANEL, which is what WRITES the key: the key,
the shipped preset and the mode table are the same in both files, so
what LAZSET's Object snaps box shows is what OSR puts back.

Run: python3 tests/test_osr.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_osr.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
OSR = (os.path.join(HERE, '..', 'shared', 'parts', 'OSR.lsp')
       if ROOT == 'shared'
       else os.path.join(HERE, '..', 'lisp', 'osr', 'OSR.lsp'))
PANEL = (os.path.join(HERE, '..', 'shared', 'parts', 'LAZPANEL.lsp')
         if ROOT == 'shared'
         else os.path.join(HERE, '..', 'lisp', 'lazpanel', 'LAZPANEL.lsp'))
LIB = os.path.join(HERE, '..', 'shared', 'parts', 'CALOFIN-LIB.lsp')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def fresh(env=None):
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(OSR)
    vm.env.update(env or {})
    vm.printed = []
    return vm


def said(vm):
    return ' '.join(str(p) for p in vm.printed)


print("== OSR puts back the saved preset ==")
vm = fresh({'CalofinOsnapPreset': '191'})
vm.sysvars['OSMODE'] = 512 + 16384          # Nearest only, F3 off
vm.run('c:OSR', [])
check("the saved preset lands in OSMODE", vm.sysvars['OSMODE'] == 191,
      str(vm.sysvars['OSMODE']))
out = said(vm)
check("it says which modes it put back",
      'Endpoint' in out and 'Perpendicular' in out and 'Object Snap on' in out
      and 'Tangent' not in out, out)
check("a saved preset is not called the shipped one",
      'shipped preset' not in out, out)

vm = fresh({'CalofinOsnapPreset': ' 16387 '})  # End+Mid, F3 OFF, padded
vm.run('c:OSR', [])
check("Object Snap OFF is part of the preset, and padding is trimmed",
      vm.sysvars['OSMODE'] == 16387, str(vm.sysvars['OSMODE']))
check("...and it says the snaps are off", 'Object Snap OFF' in said(vm),
      said(vm))

print("== with no preset saved, the shipped one ==")
vm = fresh()
vm.sysvars['OSMODE'] = 0
vm.run('c:OSR', [])
default = vm.globals['osr:*default*']
check("no preset -> osr:*default*", vm.sysvars['OSMODE'] == default,
      str(vm.sysvars['OSMODE']))
check("the shipped default is the screenshot's set (191)", default == 191,
      str(default))
check("...and it points at where to choose one",
      'LAZSET' in said(vm) and 'shipped preset' in said(vm), said(vm))

print("== a profile value that is not an OSMODE is refused ==")
for bad in ('12x', 'red', '-5', '40000', '1.5'):
    vm = fresh({'CalofinOsnapPreset': bad})
    vm.sysvars['OSMODE'] = 7
    vm.run('c:OSR', [])
    check("%r is not taken for an OSMODE" % bad,
          vm.sysvars['OSMODE'] == 191 and 'not an OSMODE' in said(vm),
          "%s / %s" % (vm.sysvars['OSMODE'], said(vm)))

vm = fresh({'CalofinOsnapPreset': '0'})
vm.sysvars['OSMODE'] = 191
vm.run('c:OSR', [])
check("0 is a real preset (no snaps at all), not a typo",
      vm.sysvars['OSMODE'] == 0, str(vm.sysvars['OSMODE']))

print("== an error mid-run reaches OSR's own handler ==")
vm = fresh()
vm.handle_errors = True
vm.sysvars['OSMODE'] = 47
vm.loads('(defun osr:preset () (osr:no-such-helper))')
vm.run('c:OSR', [])
check("aborted through *error*", len(vm.handled_errors) == 1,
      repr(vm.handled_errors))
check("the handler names the command", 'OSR error' in said(vm), said(vm))
check("a failed run leaves OSMODE alone", vm.sysvars['OSMODE'] == 47)

print("== OSRVER ==")
vm = fresh()
vm.run('c:OSRVER', [])
check("prints the version", vm.globals['*osr-version*'] in said(vm), said(vm))

print("== the contract with LAZPANEL, which writes the key ==")
pv = VM()
if ROOT == 'shared':
    pv.load(LIB)
pv.load(PANEL)
ov = fresh()
check("one profile key",
      pv.globals['lzp:*osrkey*'] == ov.globals['osr:*envkey*'],
      "%s vs %s" % (pv.globals['lzp:*osrkey*'], ov.globals['osr:*envkey*']))
check("one shipped preset",
      pv.globals['lzp:*osrdefault*'] == ov.globals['osr:*default*'])


def modes(vm, sym):
    vm.loads('(setq t:*m* (mapcar (quote (lambda (p) (list (car p) (cdr p))))'
             ' %s))' % sym)
    return [(str(a), int(b)) for a, b in vm.globals['t:*m*']]


check("one mode table, in the same order",
      modes(pv, 'lzp:*osrmodes*') == modes(ov, 'osr:*modes*'))
bits = [b for _, b in modes(ov, 'osr:*modes*')]
check("fourteen modes, each one bit, none repeated, 16384 not among them",
      len(bits) == 14 and len(set(bits)) == 14
      and all(b & (b - 1) == 0 for b in bits) and 16384 not in bits, bits)

if FAILS:
    print("test_osr: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_osr: all checks passed (%s tier)" % ROOT)
