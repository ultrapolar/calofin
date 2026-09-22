#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every file that has to move when one tool does.

A tool is not one file.  It is a `lisp/` original, a generated twin in
`shared/parts/`, dated twins in `releases/`, a row in the mirror's own
table, a caption and a placement on the panel, a slot in the loader, a
tooltip, a name in the palette's probe list, and some tests.  Finding
those by hand is six greps over three large files, every time.

    whereis.py SQUAREUP        # by command, tool folder or file stem
    whereis.py pool

Prints paths and the exact line of each registration site, so an Edit
can be anchored without opening LAZPANEL.lsp or the loader.
"""

import os
import pathlib
import re
import signal
import sys

try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):
    pass

ROOT = pathlib.Path(__file__).resolve().parents[4]

# Read the version banner and the command list with the REPO's own
# regexes, so this can never disagree with release_lisp.py about what a
# file's version is.  There are two banner spellings in the tree:
# "vN.N" and the older "DDMMYY REVnn" that abhd.lsp and its family use.
sys.path.insert(0, str(ROOT / "tools"))
try:
    from callib import COMMAND, VERSION, VERSION2
except ImportError:                                  # stand alone anyway
    COMMAND = re.compile(r"^\(defun\s+[cC]:([^\s()]+)", re.M)
    VERSION = re.compile(r'\*[a-z0-9]+-version\*\s+"v(\d+)\.(\d+)"')
    VERSION2 = re.compile(r'\*version\*\s+"(\d{6}) REV(\d{2})"')

#: Where a tool has to be registered.  (label, path, how to spot its line)
SITES = [
    ("panel caption", "lisp/lazpanel/LAZPANEL.lsp", None),
    ("loader slot", "shared/parts/CALOFIN-LOADER.lsp", None),
    ("mirror table", "tools/mirror_shared.py", None),
    ("palette tooltip", "ui/calofin_net/blurbs.txt", None),
    ("palette probe", "ui/calofin_ui/calofin.lsp", None),
    ("README row", "README.md", None),
]


def read(p):
    try:
        return pathlib.Path(p).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def find_sources(name):
    """lisp/ files whose folder, stem or a c: command matches NAME."""
    want = name.upper()
    hits = []
    for p in sorted((ROOT / "lisp").rglob("*")):
        if not (p.is_file() and p.suffix.lower() == ".lsp"):
            continue
        rel = p.relative_to(ROOT)
        if (p.stem.upper() == want or rel.parts[1].upper() == want):
            hits.append(p)
            continue
        if re.search(r"\(defun\s+c:" + re.escape(want) + r"(?=[\s(])",
                     read(p), re.I):
            hits.append(p)
    return hits


def commands_in(p):
    return sorted({m.upper() for m in COMMAND.findall(read(p))})


def version_of(src):
    m = VERSION.search(src)
    if m:
        return "v%s.%s" % (m.group(1), m.group(2))
    m = VERSION2.search(src)
    if m:
        return "%s REV%s  (the older banner spelling)" % (m.group(1),
                                                          m.group(2))
    return "(no banner -- release_lisp.py will skip it)"


def main(argv):
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    name = argv[0]
    srcs = find_sources(name)
    if not srcs:
        print("whereis: nothing under lisp/ matches %r" % name,
              file=sys.stderr)
        return 1

    for src in srcs:
        rel = src.relative_to(ROOT)
        stem = src.stem
        cmds = commands_in(src)
        print("== %s ==" % rel)
        print("  commands : %s" % (", ".join(cmds) or "(none)"))

        print("  version  : %s" % version_of(read(src)))

        # the generated tiers
        twins = sorted((ROOT / "shared" / "parts").glob("*.lsp"))
        twin = [t for t in twins if t.stem.lower() == stem.lower()]
        print("  twin     : %s"
              % (twin[0].relative_to(ROOT) if twin
                 else "(none -- needs a mirror_shared.TOOLS entry)"))
        # releases are <STEM>_<DDMMYY>_REV<nn>.lsp -- glob on the
        # underscore, or POOL* also claims POOLDEMO and POOLSIDE
        rels = sorted(r for r in (ROOT / "releases").iterdir()
                      if r.name.lower().startswith(stem.lower() + "_"))
        print("  releases : %s"
              % (", ".join(r.name for r in rels) or "(none -- no banner?)"))

        # tests that name it
        # A test counts when it DRIVES the command -- `c:NAME`, which is
        # how check_registry.py's own census decides -- or when it is
        # named after the file.  A bare substring match calls every
        # suite in the tree a test of CHECK.
        tests = []
        for t in sorted((ROOT / "tests").glob("test_*.py")):
            low = read(t).lower()
            if (t.name == "test_%s.py" % stem.lower()
                    or any(("c:" + c.lower()) in low for c in cmds)):
                tests.append(t.name)
        print("  tests    : %s" % (", ".join(tests) or "(none)"))
        print()

    # registration sites, searched for any of the commands
    allcmds = sorted({c for s in srcs for c in commands_in(s)})
    print("== registration ==")
    for label, path, _ in SITES:
        body = read(ROOT / path)
        if not body:
            print("  %-16s %s (missing)" % (label, path))
            continue
        lines = []
        for n, line in enumerate(body.split("\n"), 1):
            if any(re.search(r"\b" + re.escape(c) + r"\b", line, re.I)
                   for c in allcmds):
                lines.append((n, line.strip()))
        if lines:
            for n, line in lines[:6]:
                print("  %-16s %s:%d: %s"
                      % (label, path, n, line[:96]))
            if len(lines) > 6:
                print("  %-16s ... and %d more"
                      % ("", len(lines) - 6))
        else:
            print("  %-16s %s: NOT REGISTERED" % (label, path))
    print("\n(check with: python3 tools/check_registry.py)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
