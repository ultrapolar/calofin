#!/usr/bin/env python3
"""Cut a release of a LISP tool: stamp a version and write the twin.

Every tool keeps TWO files with identical contents:

    dimcheck.lsp                     the static name your APPLOAD points at
    releases/DIMCHECK_081726_REV01.lsp   the same bytes, named for the build

The static file is what you load. The versioned twin is what you hand
to someone else, so you can tell at a glance which build is in their
stack -- and because both carry the same `*dchk-version*` stamp inside,
DIMCHECKVER answers the same question even if the file gets renamed.

    python3 tools/release.py                  # cut today's next revision
    python3 tools/release.py --rev 3          # force REV03
    python3 tools/release.py --date 090126    # stamp another date
    python3 tools/release.py --check          # verify, change nothing

The two files are compared byte for byte before the script exits, so a
release that drifted can never be published quietly.
"""

import argparse
import datetime
import filecmp
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))          # <tool>/tools
ROOT = os.path.dirname(os.path.dirname(HERE))              # repo root

# tool name -> (source file, version variable, command prefix)
TOOLS = {
    "dimcheck": ("dimcheck.lsp", "*dchk-version*", "DIMCHECK"),
}

VER_RE = r'\(setq\s+{var}\s+"([^"]*)"\)'


def stamp_of(name, mmddyy, rev):
    return f"{name} {mmddyy} REV{rev:02d}"


def read_version(text, var):
    m = re.search(VER_RE.format(var=re.escape(var)), text)
    if not m:
        sys.exit(f"error: no {var} stamp found - is the file the right one?")
    return m.group(1)


def write_version(text, var, stamp):
    return re.sub(VER_RE.format(var=re.escape(var)),
                  f'(setq {var} "{stamp}")', text, count=1)


def next_rev(rel_dir, name, mmddyy):
    """One past the highest revision already cut for this date."""
    if not os.path.isdir(rel_dir):
        return 1
    hi = 0
    pat = re.compile(rf"^{re.escape(name)}_{mmddyy}_REV(\d+)\.lsp$", re.I)
    for fn in os.listdir(rel_dir):
        m = pat.match(fn)
        if m:
            hi = max(hi, int(m.group(1)))
    return hi + 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tool", nargs="?", default="dimcheck", choices=sorted(TOOLS))
    ap.add_argument("--rev", type=int, help="revision number to force")
    ap.add_argument("--date", help="MMDDYY to stamp (default: today)")
    ap.add_argument("--check", action="store_true",
                    help="report the current stamp and verify the twin; write nothing")
    args = ap.parse_args()

    src_rel, var, name = TOOLS[args.tool]
    src = os.path.join(ROOT, args.tool, src_rel)
    if not os.path.isfile(src):
        sys.exit(f"error: {src} not found")
    rel_dir = os.path.join(ROOT, args.tool, "releases")

    text = open(src, encoding="utf-8").read()
    current = read_version(text, var)

    if args.check:
        print(f"{src_rel}: {current}")
        twin = os.path.join(rel_dir, current.replace(" ", "_") + ".lsp")
        if os.path.isfile(twin):
            same = filecmp.cmp(src, twin, shallow=False)
            print(f"twin {os.path.relpath(twin, ROOT)}: "
                  f"{'identical' if same else 'DIFFERS - re-cut the release'}")
            return 0 if same else 1
        print(f"twin for {current} not cut yet "
              f"(run without --check to write it)")
        return 1

    mmddyy = args.date or datetime.date.today().strftime("%m%d%y")
    if not re.fullmatch(r"\d{6}", mmddyy):
        sys.exit("error: --date must be MMDDYY, e.g. 081726")
    rev = args.rev if args.rev else next_rev(rel_dir, name, mmddyy)
    stamp = stamp_of(name, mmddyy, rev)

    # stamp the static file first, then copy it, so the twin cannot
    # differ from what is actually loaded
    open(src, "w", encoding="utf-8", newline="\n").write(
        write_version(text, var, stamp))
    os.makedirs(rel_dir, exist_ok=True)
    twin = os.path.join(rel_dir, stamp.replace(" ", "_") + ".lsp")
    shutil.copyfile(src, twin)

    if not filecmp.cmp(src, twin, shallow=False):
        sys.exit("error: the twin does not match the source - refusing to publish")

    print(f"was: {current}")
    print(f"now: {stamp}")
    print(f"  {os.path.relpath(src, ROOT)}")
    print(f"  {os.path.relpath(twin, ROOT)}   (identical - hand this one out)")
    print(f"\nIn AutoCAD, {name}VER now reports: {stamp}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
