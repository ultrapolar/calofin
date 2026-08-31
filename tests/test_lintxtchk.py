"""Runtime tests for LINTXTCHK: place the liner checklist and check the
column that lands -- one TEXT entity per line, 12" high, sub-items
indented, the whole column one undo group.

The command has exactly one interaction (the top-left getpoint), so the
scripts are one answer long: a point places the checklist, None (Enter/
Esc) is the cancel path.  There is no ssget anywhere in the file, so no
pickfirst probe and no leading None.

Run: python3 tests/test_lintxtchk.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_lintxtchk.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
LSP = os.path.join(HERE, '..', 'lisp', 'lintxtchk', 'LINTXTCHK.lsp')
RELEASES = os.path.join(HERE, '..', 'releases')

HEIGHT = 12.0
SPACING = HEIGHT * 1.6          # vertical step between lines
INDENT = HEIGHT * 1.5           # horizontal shift per sub-level

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


def texts(vm):
    """[(x, y, height, string)] for every TEXT entity, in creation
    order."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'TEXT':
            ins = grp(d, 10)
            out.append((ins[0], ins[1], grp(d, 40), grp(d, 1)))
    return out


# ----------------------------------------------------------------------
# statics: pure ASCII, banner, releases/ twin
# ----------------------------------------------------------------------
print("statics")

SRC = open(LSP, encoding="ascii").read()   # also asserts pure ASCII

m = re.search(r'\*lintxtchk-version\*\s+"v(\d+)\.(\d+)"', SRC)
check("version banner present", m is not None)
if m:
    rev = f"{m.group(1)}{m.group(2)}"
    twins = [n for n in os.listdir(RELEASES)
             if re.match(rf"LINTXTCHK_\d{{6}}_REV{rev}\.lsp$", n)]
    check(f"releases/ twin at REV{rev} exists", len(twins) == 1, repr(twins))
    if len(twins) == 1:
        twin = open(os.path.join(RELEASES, twins[0]),
                    encoding="ascii").read()
        check("releases/ twin is identical", twin == SRC)

for cmd in ("c:LINTXTCHK", "c:LINTXTCHKVER"):
    check(f"{cmd} defined", f"(defun {cmd} " in SRC)

# ----------------------------------------------------------------------
# 1. the happy path: pick a point, get the whole column
# ----------------------------------------------------------------------
print("the checklist lands")

vm = VM()
vm.load(LSP)
vm.sysvars['OSMODE'] = 4133
vm.run('c:LINTXTCHK', [(100.0, 200.0, 0.0)])

placed = texts(vm)
check("26 lines placed, matching the announced count",
      len(placed) == 26 and
      '26 checklist lines placed at 12" text.' in ''.join(vm.printed),
      f"{len(placed)} placed")
check("every line is 12\" text",
      all(h == HEIGHT for _x, _y, h, _s in placed))
check("every line is its own entity prefixed \"- \"",
      all(s.startswith('- ') for _x, _y, _h, s in placed))
check("first and last lines are the checklist's",
      placed[0][3].startswith('- Read all WSN') and
      placed[-1][3] == '- Did you scale the titleblock? REDVIEW!',
      repr((placed[0][3], placed[-1][3])))

ys = [y for _x, y, _h, _s in placed]
check("lines step down one spacing apart",
      all(abs((ys[i] - ys[i + 1]) - SPACING) < 1e-9
          for i in range(len(ys) - 1)),
      repr(ys[:3]))
check("the column starts at the picked point",
      placed[0][0] == 100.0 and placed[0][1] == 200.0)

mains = [x for x, _y, _h, _s in placed if x == 100.0]
subs = [x for x, _y, _h, _s in placed if x == 100.0 + INDENT]
check("sub-items sit one indent right of their parents, nothing else",
      len(mains) + len(subs) == 26 and len(subs) == 12,
      f"{len(mains)} main / {len(subs)} sub")

# the escaped quotes and inch marks must survive into the entities
bodies = [s for _x, _y, _h, s in placed]
check("escaped double quotes survive",
      '- Finished Wall Ht should be a single value, or "Varies"'
      ' if needed' in bodies)
check("escaped inch marks survive",
      any('(37" Deep)' in s for s in bodies))

check("the run is one undo group",
      [c for c in vm.commands if c] ==
      [['_.UNDO', '_Begin'], ['_.UNDO', '_End']],
      repr(vm.commands))
check("OSMODE is restored", vm.sysvars['OSMODE'] == 4133)

# ----------------------------------------------------------------------
# 2. the cancel path: Enter at the point prompt
# ----------------------------------------------------------------------
print("cancelling")

vm = VM()
vm.load(LSP)
vm.sysvars['OSMODE'] = 4133
vm.run('c:LINTXTCHK', [None])
check("nothing is placed and it says so",
      not texts(vm) and 'LINTXTCHK cancelled.' in ''.join(vm.printed))
check("no undo group was opened",
      not [c for c in vm.commands if c], repr(vm.commands))
check("OSMODE untouched on the cancel path",
      vm.sysvars['OSMODE'] == 4133)

# ----------------------------------------------------------------------
# 3. the VER command
# ----------------------------------------------------------------------
print("version command")

vm = VM()
vm.load(LSP)
vm.run('c:LINTXTCHKVER', [])
check("LINTXTCHKVER prints the banner",
      f"LINTXTCHK v{m.group(1)}.{m.group(2)}" in ''.join(vm.printed),
      ''.join(vm.printed)[-120:])

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all LINTXTCHK checks passed")
