"""The ink table, the two probes that feed it, and the eleven copies.

WHAT THIS IS ABOUT.  A colour knob is a number, and a number is only
right against one background.  ACI 8 was serving two opposite intents
across the tree: the review tools used it to make everything not under
review RECEDE, which it does on the stock near-black model space and
the exact opposite of on a white one; and OASIS, POOLSIDE, POOL, SPA,
LOBF, ABFIND and CONSTELLATION used it for guide geometry that has to
be READ while it is answered, which works on white and very nearly
disappears on the stock dark grey.  One number, two intents, each
correct on one background -- and nothing in the tree had ever asked
which background it was drawing onto (no COLORTHEME, no
GraphicsWinModelBackgrndColor, anywhere, before this).

So a knob may now say 'auto, and cal:ink answers it per ROLE.  Three
things have to hold, and this file holds them:

1. The table itself: every role, every theme, and the unmeasured
   column -- which is deliberately what the tree drew BEFORE the table
   existed, so a session that cannot tell is not a session that
   behaves differently.
2. A knob that is a NUMBER still means that number.  Every existing
   suite that sets one (test_abfind sets abf:*locus-color* to 9,
   test_constellation sets cst:*space-color*) depends on it, and so
   does a shop that has picked its own colours.
3. The eleven standalone copies agree with the library, under every
   theme.  tests/test_cal_parity.py compares them call for call; what
   it cannot do is the zero-argument probes (cal:ui), because there is
   no argument to set the theme up in -- those are here.

Run: python3 tests/test_theme.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_theme.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from lispvm import VM, parse_all  # noqa: E402
import mirror_shared  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
LIB = os.path.join(REPO, 'shared', 'parts', 'CALOFIN-LIB.lsp')

FAILS = []


def check(label, ok, detail=''):
    print(('  ok   ' if ok else '  FAIL ') + label
          + (('  -- ' + detail) if detail and not ok else ''))
    if not ok:
        FAILS.append(label)


def ev(vm, src):
    out = None
    for form in parse_all(src):
        out = vm.eval(form)
    return out


def libvm():
    vm = VM()
    with open(LIB, encoding='utf-8') as fh:
        vm.loads(fh.read())
    return vm


#: role -> (dark, light, unmeasured).  The third column is the number
#: the tree used before any of this, and changing one of those is a
#: behaviour change for every drafter whose session cannot answer.
TABLE = {
    'fade':  (251, 254, 8),
    'guide': (253, 8, 8),
    'dim':   (253, 8, 8),
    'hi':    (4, 5, 5),
}

print('== the table, role by role ==')
for role, (dark, light, unk) in sorted(TABLE.items()):
    vm = libvm()
    ev(vm, '(setenv "CalofinTheme" "dark")')
    check('%-6s dark       -> %s' % (role, dark),
          ev(vm, "(cal:ink 'auto '%s)" % role) == dark,
          repr(ev(vm, "(cal:ink 'auto '%s)" % role)))
    ev(vm, '(setenv "CalofinTheme" "light")')
    check('%-6s light      -> %s' % (role, light),
          ev(vm, "(cal:ink 'auto '%s)" % role) == light)
    ev(vm, '(setenv "CalofinTheme" "")')
    check('%-6s unmeasured -> %s (what it always was)' % (role, unk),
          ev(vm, "(cal:ink 'auto '%s)" % role) == unk)

print('== a number is that number, whatever the screen is doing ==')
vm = libvm()
for theme in ('dark', 'light', ''):
    ev(vm, '(setenv "CalofinTheme" "%s")' % theme)
    check('theme %-6s leaves a numeric knob alone'
          % (theme or 'unset'),
          all(ev(vm, "(cal:ink %d '%s)" % (n, r)) == n
              for n in (1, 8, 9, 30, 256) for r in TABLE))

print('== an unknown role is 7, not nil ==')
vm = libvm()
ev(vm, '(setenv "CalofinTheme" "dark")')
check('a role nobody has defined answers white/black',
      ev(vm, "(cal:ink 'auto 'nosuchrole)") == 7)

print('== the two probes are different questions ==')
vm = libvm()
ev(vm, '(setenv "CalofinTheme" "")')
ev(vm, '(setvar "COLORTHEME" 0)')
check('COLORTHEME 0 makes the INTERFACE dark', ev(vm, '(cal:ui)') == 'dark')
check("...and the drawing's background is still unmeasured here",
      ev(vm, '(cal:bg)') is None or ev(vm, '(cal:bg)') == [])
check('so a dialog role follows it', ev(vm, "(cal:ink 'auto 'dim)") == 253)
check('and a drawing role does not', ev(vm, "(cal:ink 'auto 'guide)") == 8)
ev(vm, '(setvar "COLORTHEME" 1)')
check('COLORTHEME 1 makes it light', ev(vm, '(cal:ui)') == 'light')
check('and the override beats both',
      (ev(vm, '(setenv "CalofinTheme" "dark")'),
       ev(vm, '(cal:ui)'))[1] == 'dark')

print('== cal:setting: the profile wins, the literal is the default ==')
vm = libvm()
check('an unset key gives the default',
      ev(vm, '(cal:setting "NoSuchCalofinKey" "fallback")') == 'fallback')
ev(vm, '(setenv "NoSuchCalofinKey" "")')
check('and so does an empty one -- "" is not an answer',
      ev(vm, '(cal:setting "NoSuchCalofinKey" "fallback")') == 'fallback')
ev(vm, '(setenv "NoSuchCalofinKey" "set")')
check('a set key wins', ev(vm, '(cal:setting "NoSuchCalofinKey" "x")') == 'set')

print('== every standalone copy answers what the library answers ==')
#: the tools whose swap map says their ink/ui helper IS the library's.
#: Read from the mirror, so a tool that gains a copy tomorrow is
#: checked the day it lands rather than when somebody remembers.
COPIES = []
for tool in sorted(mirror_shared.TOOLS):
    swap = mirror_shared.TOOLS[tool].get('swap') or {}
    for local, cal in swap.items():
        if cal in ('cal:ink', 'cal:ui'):
            COPIES.append((tool, mirror_shared.TOOLS[tool]['src'], local, cal))
#: thirteen tools carry the ink table and LAZPANEL carries the
#: interface probe its toolbar icon is painted from
check('the mirror says fourteen copies exist', len(COPIES) == 14,
      '%d: %r' % (len(COPIES), [c[0] for c in COPIES]))
check('thirteen of them are the ink table',
      len([c for c in COPIES if c[3] == 'cal:ink']) == 13)

for tool, src, local, cal in COPIES:
    vm = VM()
    with open(os.path.join(REPO, src), encoding='utf-8',
              errors='replace') as fh:
        vm.loads(fh.read())
    with open(LIB, encoding='utf-8') as fh:
        vm.loads(fh.read())
    ok = True
    detail = ''
    for theme in ('dark', 'light', ''):
        ev(vm, '(setenv "CalofinTheme" "%s")' % theme)
        for ct in (0, 1):
            ev(vm, '(setvar "COLORTHEME" %d)' % ct)
            if cal == 'cal:ui':
                a, b = ev(vm, '(%s)' % local), ev(vm, '(%s)' % cal)
                if a != b:
                    ok, detail = False, '%s %r vs %r' % (theme, a, b)
            else:
                for role in TABLE:
                    a = ev(vm, "(%s 'auto '%s)" % (local, role))
                    b = ev(vm, "(%s 'auto '%s)" % (cal, role))
                    if a != b:
                        ok, detail = False, '%s/%s %r vs %r' % (theme, role,
                                                                a, b)
    check('%-14s %-10s == %s' % (tool, local, cal), ok, detail)

print()
if FAILS:
    print('%d THEME check(s) FAILED' % len(FAILS))
    sys.exit(1)
print('ALL THEME CHECKS PASSED')
