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

A second, unrelated set of roles lives in the same table now:
flag/arc/olap/orig/sugg/point/constr/report, the eight ACI numbers
COVERCHECK, DIMCHECK and LINFINCHECK each used to carry as a separate
hardcoded copy.  They do not vary with dark/light the way fade/guide/
dim/hi do, so they get their own section below rather than a column in
TABLE -- and CalofinInk-<ROLE> in the profile (CALSET's Itemcolors
menu) can override any role, old or new, which is tested here too.

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

print('== the edges: what a knob can hold, and what it must never return ==')
# A knob used to be a number and nothing else.  It can hold a SYMBOL
# now, which invites hand-editing, and the failure mode of a mistyped
# one is the worst kind: the symbol travels to entmake as DXF group 62
# and dies there, a long way from the knob that caused it.  So the
# guard is numberp -- a number is used exactly as given, and anything
# else is resolved.
vm = libvm()
ev(vm, '(setenv "CalofinTheme" "dark")')
for bad, why in (("'auot", 'a mistyped auto'),
                 ('nil', 'a knob someone emptied'),
                 ("'AUTO", 'auto in caps -- AutoLISP has no case here'),
                 ("'Auto", 'and mixed case')):
    got = ev(vm, "(cal:ink %s 'fade)" % bad)
    check('%-32s -> %s' % (why, got),
          isinstance(got, int) and got == 251, repr(got))
check('...while a real number still passes through untouched',
      all(ev(vm, "(cal:ink %d 'guide)" % n) == n for n in (0, 1, 8, 256)))

print('== the edges: an override typed by a person ==')
vm = libvm()
for spelling in ('dark', 'DARK', ' dark', 'dark ', '  Dark  ', '\tdark'):
    ev(vm, '(setenv "CalofinTheme" "%s")' % spelling)
    check('%-12r is dark' % spelling, ev(vm, '(cal:bg)') == 'dark',
          repr(ev(vm, '(cal:bg)')))
for spelling in ('drk', '0', 'darkish', ''):
    ev(vm, '(setenv "CalofinTheme" "%s")' % spelling)
    check('%-12r is not an answer, so it measures instead' % spelling,
          ev(vm, '(cal:bg)') in (None, []), repr(ev(vm, '(cal:bg)')))

print('== the edges: CALVER cannot drop a file ==')
# vl-sort REMOVES elements its comparison calls equal.  Sorting the
# roster on the label alone lost one of two files whose banner globals
# reduce to the same name -- and losing one silently is the single
# thing this command exists not to do.
vm = libvm()
vm.loads('(setq *cchk-version* "v1.15") (setq cchk:*version* "v9.9")'
         '(setq *pool-version* "v9.1") (setq spa:*version* "091126 REV19")')
vm.printed.clear()
vm.loads('(c:CALVER)')
out = ''.join(str(x) for x in vm.printed)
check('both files that read CCHK are listed',
      out.count('CCHK') == 2 and 'v1.15' in out and 'v9.9' in out, out)
check('the count agrees with the rows',
      ('%d calofin file(s)' % out.count('\n  ')) in out, out)
check('and the rows are in order',
      out.index('CCHK') < out.index('POOL') < out.index('SPA'), out)

vm = libvm()
vm.loads('(setq *a-version* 1.0) (setq *b-version* nil)')
vm.printed.clear()
vm.loads('(c:CALVER)')
out = ''.join(str(x) for x in vm.printed)
check('a version global that is not a string is left out',
      '\n  A ' not in out and '\n  B ' not in out, out)

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
#: fourteen tools carry the ink table and LAZPANEL carries the
#: interface probe its toolbar icon is painted from
check('the mirror says fifteen copies exist', len(COPIES) == 15,
      '%d: %r' % (len(COPIES), [c[0] for c in COPIES]))
check('fourteen of them are the ink table',
      len([c for c in COPIES if c[3] == 'cal:ink']) == 14)

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
    if cal == 'cal:ink':
        # the drafter's per-role override (CALSET Itemcolors,
        # LAZBACKUP) -- the standalone copies ignored it once, so the
        # same profile coloured a cue one way in LAZPASS and another
        # when the tool was APPLOADed alone.  An out-of-range or
        # non-numeric value is refused by both and falls to the table.
        for val in ('77', '300', '0', 'abc', ''):
            ev(vm, '(setenv "CalofinInk-FADE" "%s")' % val)
            a = ev(vm, "(%s 'auto 'fade)" % local)
            b = ev(vm, "(%s 'auto 'fade)" % cal)
            if a != b:
                ok, detail = False, 'CalofinInk-FADE=%s %r vs %r' % (val,
                                                                     a, b)
        if ok and ev(vm, '(progn (setenv "CalofinInk-FADE" "77") '
                         "(%s 'auto 'fade))" % local) != 77:
            ok, detail = False, 'override not honoured'
        ev(vm, '(setenv "CalofinInk-FADE" "")')
    check('%-14s %-10s == %s' % (tool, local, cal), ok, detail)

print('== the item-type roles: flag/arc/olap/orig/sugg/point/constr/report ==')
#: generalized off the eight numbers COVERCHECK, DIMCHECK and
#: LINFINCHECK each carried as a separate hardcoded copy.  These do
#: not vary with the screen the way fade/guide/dim/hi do -- one number
#: for every theme -- so there is no dark/light column to check, only
#: that cal:ink answers it and that a number still passes through.
ITEM_ROLES = {
    'flag': 1, 'arc': 6, 'olap': 4, 'orig': 1,
    'sugg': 3, 'point': 2, 'constr': 2, 'report': 3,
}
vm = libvm()
ev(vm, '(setenv "CalofinTheme" "dark")')
for role, val in sorted(ITEM_ROLES.items()):
    check('%-6s (any theme) -> %s' % (role, val),
          ev(vm, "(cal:ink 'auto '%s)" % role) == val)
ev(vm, '(setenv "CalofinTheme" "light")')
check('...still the same set under light',
      all(ev(vm, "(cal:ink 'auto '%s)" % r) == v
          for r, v in ITEM_ROLES.items()))
check('a number still passes through untouched for an item-type role',
      all(ev(vm, "(cal:ink %d '%s)" % (n, r)) == n
          for n in (1, 8, 9, 30) for r in ITEM_ROLES))

print('== CalofinInk-<ROLE>: a per-role override, any role ==')
vm = libvm()
ev(vm, '(setenv "CalofinInk-FLAG" "42")')
check('an override on an item-type role beats the table',
      ev(vm, "(cal:ink 'auto 'flag)") == 42)
check('...and does not leak onto a role nobody overrode',
      ev(vm, "(cal:ink 'auto 'arc)") == 6)
ev(vm, '(setenv "CalofinTheme" "dark")')
ev(vm, '(setenv "CalofinInk-FADE" "77")')
check('the same mechanism works on a legacy fade/guide/dim/hi role',
      ev(vm, "(cal:ink 'auto 'fade)") == 77)
check('a numeric knob is used exactly as given, override or not',
      ev(vm, "(cal:ink 1 'flag)") == 1)
ev(vm, '(setenv "CalofinInk-FLAG" "")')
check('clearing the override (empty string) falls back to the table',
      ev(vm, "(cal:ink 'auto 'flag)") == 1)

print('== the item-type roles: the three review tools agree with the library ==')
#: unlike the fifteen-copy check above, this is NOT every tool with an
#: ink table -- POOL, SPA, ABFIND and the rest have no flag/arc/olap
#: knobs and were never asked to grow the item-type table, so holding
#: them to it would fail them for a role they do not use.  Only the
#: three review tools that used to hardcode these numbers by hand.
ITEM_COPIES = [c for c in COPIES if c[0] in ('covercheck', 'dimcheck', 'linfincheck')]
check('all three review tools carry the ink table', len(ITEM_COPIES) == 3,
      [c[0] for c in ITEM_COPIES])
for tool, src, local, cal in ITEM_COPIES:
    vm = VM()
    with open(os.path.join(REPO, src), encoding='utf-8',
              errors='replace') as fh:
        vm.loads(fh.read())
    with open(LIB, encoding='utf-8') as fh:
        vm.loads(fh.read())
    ok, detail = True, ''
    for role in ITEM_ROLES:
        a = ev(vm, "(%s 'auto '%s)" % (local, role))
        b = ev(vm, "(%s 'auto '%s)" % (cal, role))
        if a != b:
            ok, detail = False, '%s %r vs %r' % (role, a, b)
    ev(vm, '(setenv "CalofinInk-OLAP" "77")')
    a = ev(vm, "(%s 'auto 'olap)" % local)
    if a != 77:
        ok, detail = False, 'override not read: %r' % a
    check('%-14s %-10s item colours == %s' % (tool, local, cal), ok, detail)

print()
if FAILS:
    print('%d THEME check(s) FAILED' % len(FAILS))
    sys.exit(1)
print('ALL THEME CHECKS PASSED')
