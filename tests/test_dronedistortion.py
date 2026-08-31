"""Runtime tests for the DroneDistortion tool: DDFIX applies the
(H - z) / H correction about the selection's centre, DDSET / DDCAL /
DDINFO manage the remembered drone height.  First runtime coverage for
the drone_height folder -- test_drone_height_lisp.py is a static lint
plus Python re-implementations and never runs a command.

Three builtins the VM does not carry are stubbed here, one process per
suite so the registrations leak nowhere: vlax-ldata-get/-put (the
per-drawing store) and vl-cmdf (logged like command, with a switchable
failure mode for the locked-layer branch).

DDALT is deliberately not covered: its one flow is a getfiled file
pick plus an alert box, neither of which the VM models -- the getfiled
stub precedent lives in test_stockcover.py if it is ever wanted.

Script notes: DDFIX opens with a pickfirst probe (leading None), and
the stage-3 height is a getstring -- never script None there, an empty
string re-asks the same prompt and burns the slot.

Run: python3 tests/test_dronedistortion.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_dronedistortion.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, NIL, T, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
LSP = os.path.join(HERE, '..', 'lisp', 'drone_height', 'DroneDistortion.lsp')
RELEASES = os.path.join(HERE, '..', 'releases')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def reg(name, fn):
    lispvm.BUILTINS[Sym(name.lower())] = fn


# the per-drawing LDATA store, cleared per scenario by newvm()
LDATA = {}
reg('vlax-ldata-get', lambda vm, a: LDATA.get((a[0], a[1]), NIL))
reg('vlax-ldata-put',
    lambda vm, a: (LDATA.__setitem__((a[0], a[1]), a[2]), a[2])[1])

# vl-cmdf: logged like command; CMDF_OK[0] = False exercises the
# locked-layer branch (vl-cmdf returns nil on failure)
CMDF_OK = [True]
reg('vl-cmdf',
    lambda vm, a: (vm.commands.append(list(a)), T if CMDF_OK[0] else NIL)[1])

CIRCLE = '''
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 '(100 . "AcDbCircle")
                 '(10 10.0 10.0 0.0) '(40 . 5.0)))'''


def newvm(fixtures=()):
    LDATA.clear()
    CMDF_OK[0] = True
    vm = VM()
    vm.load(LSP)
    for f in fixtures:
        vm.loads(f)
    return vm


def scale_calls(vm):
    return [c for c in vm.commands if c and c[0] == '_.SCALE']


# ----------------------------------------------------------------------
# statics: pure ASCII, banner, releases/ twin
# ----------------------------------------------------------------------
print("statics")

SRC = open(LSP, encoding="ascii").read()   # also asserts pure ASCII

m = re.search(r'\*dronedistortion-version\*\s+"v(\d+)\.(\d+)"', SRC)
check("version banner present", m is not None)
if m:
    rev = f"{m.group(1)}{m.group(2)}"
    twins = [n for n in os.listdir(RELEASES)
             if re.match(rf"DroneDistortion_\d{{6}}_REV{rev}\.lsp$", n)]
    check(f"releases/ twin at REV{rev} exists", len(twins) == 1, repr(twins))
    if len(twins) == 1:
        twin = open(os.path.join(RELEASES, twins[0]),
                    encoding="ascii").read()
        check("releases/ twin is identical", twin == SRC)

# ----------------------------------------------------------------------
# 1. the height grammar, straight through dd-parse-height
# ----------------------------------------------------------------------
print("the feet-and-inches grammar")


def parse(vm, typed):
    vm.script = [typed]
    return vm.loads('(dd-parse-height "\\nh? " nil)')


vm = newvm()
CASES = [('6"', 0.5), ("2'", 2.0), ("2'6\"", 2.5),
         ("1'6-1/2\"", 1.0 + 6.5 / 12.0), ("18'6.5\"", 18.0 + 6.5 / 12.0),
         ("18", 1.5),                      # a bare number is inches
         ("-3'4\"", -(3.0 + 4.0 / 12.0)),  # leading - = below deck
         ("+2'", 2.0)]
for typed, want in CASES:
    got = parse(vm, typed)
    check(f"{typed!r} -> {want:.4f} ft",
          isinstance(got, float) and abs(got - want) < 1e-9, repr(got))
check("garbage reads as no height", parse(vm, "abc") is NIL or
      parse(vm, "abc") == NIL)
check("blank reads as no height", parse(vm, "") in (NIL, None, []))

# ----------------------------------------------------------------------
# 2. DDFIX happy path: raised spa, remembered H, scale about the centre
# ----------------------------------------------------------------------
print("DDFIX corrects a raised feature")

vm = newvm([CIRCLE])
c = vm.entities[-1]
vm.sysvars['CMDECHO'] = 1
vm.run('c:DDFIX', [None, [c], 60.0, "2'"])

calls = scale_calls(vm)
check("one SCALE about the selection centre",
      len(calls) == 1 and calls[0][-2] == [10.0, 10.0, 0.0],
      repr(calls))
check("factor is (H - z) / H",
      abs(calls[0][-1] - (60.0 - 2.0) / 60.0) < 1e-9, repr(calls))
check("the osnap override rides along", "_non" in calls[0], repr(calls))
txt = ''.join(vm.printed)
check("the applied scale and diagnosis are reported",
      'Applied scale 0.96667' in txt and 'too BIG' in txt, txt[-300:])
check("H is remembered for the drawing",
      LDATA.get(('DRONE_DISTORTION', 'H')) == 60.0, repr(LDATA))
check("CMDECHO restored", vm.sysvars.get('CMDECHO') == 1,
      repr(vm.sysvars.get('CMDECHO')))

print("a second run offers the remembered height")
vm.run('c:DDFIX', [None, [c], None, "-1'"])   # Enter keeps H = 60
asked = '|'.join(p for p, _ in vm.prompts)
check("the H prompt carries <60.000>", '<60.000>' in asked, asked[-300:])
calls = scale_calls(vm)
check("a sunken feature scales up",
      abs(calls[-1][-1] - (60.0 + 1.0) / 60.0) < 1e-9, repr(calls[-1:]))
check("and is diagnosed as traced too SMALL",
      'too SMALL' in ''.join(vm.printed))

# ----------------------------------------------------------------------
# 3. DDFIX guards and Back
# ----------------------------------------------------------------------
print("DDFIX guards")

vm = newvm([CIRCLE])
c = vm.entities[-1]
# Back at the height string re-opens the H question; the re-answered
# H is the one stored and used
vm.run('c:DDFIX', [None, [c], 60.0, "B", 55.0, "2'"])
check("Back at the height re-opens H, which re-stores",
      LDATA.get(('DRONE_DISTORTION', 'H')) == 55.0, repr(LDATA))
check("the factor uses the re-answered H",
      abs(scale_calls(vm)[0][-1] - (55.0 - 2.0) / 55.0) < 1e-9)

vm = newvm([CIRCLE])
c = vm.entities[-1]
# Back at H re-opens the selection; Enter there ends the command
vm.run('c:DDFIX', [None, [c], "Back", None])
check("Back at H re-opens the pick; Enter ends with nothing selected",
      'Nothing selected.' in ''.join(vm.printed) and not scale_calls(vm))

vm = newvm([CIRCLE])
c = vm.entities[-1]
# |z| >= H re-asks instead of aborting; 0 ends with no change
vm.run('c:DDFIX', [None, [c], 10.0, "12'", "2'"])
check("|height| >= H re-asks the height",
      '>= drone height' in ''.join(vm.printed) and
      abs(scale_calls(vm)[0][-1] - 0.8) < 1e-9)

vm = newvm([CIRCLE])
c = vm.entities[-1]
vm.run('c:DDFIX', [None, [c], 60.0, "0\""])
check("a deck-level feature is left alone",
      'no change' in ''.join(vm.printed) and not scale_calls(vm))

vm = newvm([CIRCLE])
c = vm.entities[-1]
CMDF_OK[0] = False
vm.run('c:DDFIX', [None, [c], 60.0, "2'"])
check("a failed SCALE names the locked-layer suspicion",
      'locked layer' in ''.join(vm.printed))

# ----------------------------------------------------------------------
# 4. the siblings: DDSET, DDINFO, DDCAL
# ----------------------------------------------------------------------
print("DDSET / DDINFO / DDCAL")

vm = newvm()
vm.run('c:DDSET', [42.0])
check("DDSET stores H and reports the rate",
      LDATA.get(('DRONE_DISTORTION', 'H')) == 42.0 and
      'Distortion rate' in ''.join(vm.printed))
vm.run('c:DDSET', [None])
check("Enter at DDSET keeps the stored value",
      LDATA.get(('DRONE_DISTORTION', 'H')) == 42.0 and
      '<42.000>' in '|'.join(p for p, _ in vm.prompts))

vm.run('c:DDINFO', [])
check("DDINFO reports the stored height",
      'Drone height above deck (H): 42.000' in ''.join(vm.printed))

vm = newvm()
vm.run('c:DDINFO', [])
check("DDINFO says NOT SET when nothing is stored",
      'NOT SET' in ''.join(vm.printed))

vm = newvm()
# H = Lapp * z / (Lapp - Ltrue); a Back walks stage 2 -> 1
vm.run('c:DDCAL', [100.0, "Back", 120.0, 116.0, "2'"])
check("DDCAL back-solves H from the re-answered sizes",
      abs(LDATA.get(('DRONE_DISTORTION', 'H'), 0) - 60.0) < 1e-9 and
      'Solved drone height  H = 60.000' in ''.join(vm.printed),
      ''.join(vm.printed)[-300:])

vm = newvm()
vm.run('c:DDCAL', [100.0, 100.0, "2'"])
check("sizes too close to solve are refused",
      'too close' in ''.join(vm.printed) and
      ('DRONE_DISTORTION', 'H') not in LDATA)

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all DRONEDISTORTION checks passed")
