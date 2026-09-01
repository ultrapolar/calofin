"""Every tool file loads, and every version command answers with its own
banner.

Two things nothing else covered.  Only 12 of the 49 *VER commands were
ever run by a test, and no suite loaded every tool file -- so a file
that stopped parsing, or a VER command that printed the wrong tool's
version, would have reached a user before it reached a test.

The roster is computed, never typed: every .lsp under lisp/ (less the
deprecated matcher, which has no grouped twin), and within each file
every c:*VER / c:*VERSION command whose base name is a real command in
the tree -- callib's own rule, so a tool added tomorrow is covered the
day it lands without editing this file.

One fresh VM per file, deliberately: the standalone tier reuses helper
names across tools on purpose, so one VM loaded with everything would
collide (only the grouped tier is collision-free, which is what
check_standards' no-collisions check is for).  A fresh VM also keeps a
failure pinned to the file that caused it.

Run: python3 tests/test_versions.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_versions.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))

from callib import (COMMAND, LISP_DIR, NOT_A_TOOL, VERSION,  # noqa: E402
                    VERSION2, census, lsp_files, read)
from lispvm import VM, LispError  # noqa: E402

#: Files whose VER command cannot be checked for its banner text, with
#: the reason.  (prompt) is a no-op in the VM -- it records nothing --
#: so a VER command written with it prints nothing a test can read.
#: The command is still RUN here; only the banner assertion is skipped.
BANNER_EXEMPT = {}

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def banner_of(src):
    """The version string the file's banner asks to be printed, in the
    form it prints it -- "v1.5" or the dated "083126 REV12"."""
    m = VERSION.search(src)
    if m:
        return "v%s.%s" % m.groups()
    m = VERSION2.search(src)
    if m:
        return "%s REV%s" % m.groups()
    return None


def ver_commands(src, all_commands):
    """The version reporters this file defines: a *VER or *VERSION
    command whose base is a real command somewhere in the tree."""
    out = set()
    for name in COMMAND.findall(src):
        up = name.upper()
        for suffix in ('VER', 'VERSION'):
            if up.endswith(suffix) and up[:-len(suffix)] in all_commands:
                out.add(up)
    return sorted(out)


ALL = census()
TOOLS = [p for p in lsp_files(LISP_DIR) if NOT_A_TOOL not in p.parts]

print(f"{len(TOOLS)} tool file(s), tier="
      f"{os.environ.get('CALOFIN_LISP_ROOT', 'lisp')}")

nver = 0
for path in TOOLS:
    src = read(path)
    vers = ver_commands(src, ALL)
    if not vers:
        continue                      # a file with no reporter of its own
    banner = banner_of(src)
    exempt = BANNER_EXEMPT.get(path.name)

    vm = VM()
    try:
        vm.load(str(path))            # CALOFIN_LISP_ROOT picks the tier
    except LispError as e:
        check(f"{path.name} loads", False, str(e))
        continue
    check(f"{path.name} loads", True)

    for cmd in vers:
        nver += 1
        mark = len(vm.printed)
        try:
            vm.run('c:' + cmd, [])
        except LispError as e:
            check(f"  {cmd} runs", False, str(e))
            continue
        said = ''.join(vm.printed[mark:])
        if exempt:
            check(f"  {cmd} runs ({exempt})", True)
        else:
            check(f"  {cmd} reports {banner}",
                  banner is not None and banner in said,
                  repr(said[-120:]))

print(f"\n{nver} version command(s) run")
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all VERSION checks passed")
