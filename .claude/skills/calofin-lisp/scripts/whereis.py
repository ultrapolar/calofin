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
    from callib import headline_commands, held_back
except ImportError:                                  # stand alone anyway
    headline_commands = held_back = None
    COMMAND = re.compile(r"^\(defun\s+[cC]:([^\s()]+)", re.M)
    VERSION = re.compile(r'\*[a-z0-9]+-version\*\s+"v(\d+)\.(\d+)"')
    VERSION2 = re.compile(r'\*version\*\s+"(\d{6}) REV(\d{2})"')



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

    # Registration.  Two different keys, and conflating them is how this
    # used to cry wolf: the LOADER and the MIRROR list a tool by its
    # FILE (DroneHeightGPS.lsp), while the panel, the palette tooltip
    # and the probe list name COMMANDS -- and only the commands that
    # carry a button.  A satellite (FOOVER, TUTORIALFOO, DD*, FOO-CFG)
    # has none by design, so its absence there is not a gap.  Which is
    # which comes from callib, the same place check_registry reads it.
    allcmds = sorted({c for s in srcs for c in commands_in(s)})
    heads = headline_commands() if headline_commands else None
    held = held_back() if held_back else {}
    print("== registration ==")

    def hits(path, pred):
        body = read(ROOT / path)
        return [(n, ln.strip()) for n, ln in enumerate(body.split("\n"), 1)
                if pred(ln)]

    def show(label, path, found, empty):
        if found:
            for n, ln in found[:3]:
                print("  %-16s %s:%d: %s" % (label, path, n, ln[:88]))
            if len(found) > 3:
                print("  %-16s ... and %d more" % ("", len(found) - 3))
        else:
            print("  %-16s %s" % (label, empty))

    for src in srcs:
        stem = src.stem
        twin = "%s.lsp" % stem
        tag = " [%s]" % twin if len(srcs) > 1 else ""
        hand = (ROOT / "shared" / "parts" / twin).is_file()
        show("mirror table" + tag, "tools/mirror_shared.py",
             hits("tools/mirror_shared.py",
                  lambda ln: re.match(r"\s*'%s':\s*\{" % re.escape(stem), ln)),
             "not in mirror_shared.TOOLS -- its twin is kept BY HAND "
             "(CLAUDE.md allows that for LISPLAB alone)" if hand else
             "NOT IN mirror_shared.TOOLS -- no twin will be generated")
        if twin in held or stem + ".LSP" in held:
            print("  %-16s held back from the bundle: %s"
                  % ("loader slot" + tag, held.get(twin) or held.get(stem + ".LSP")))
        else:
            show("loader slot" + tag, "shared/parts/CALOFIN-LOADER.lsp",
                 hits("shared/parts/CALOFIN-LOADER.lsp",
                      lambda ln: re.search(r'"%s"' % re.escape(twin), ln, re.I)),
                 "NOT IN THE LOADER -- the folder load and the bundle skip it")

    buttons = sorted(c for c in allcmds if heads is None or c in heads)
    held_srcs = [x for x in srcs
                 if "%s.lsp" % x.stem in held or "%s.LSP" % x.stem in held]
    held_cmds = sorted({c for x in held_srcs for c in commands_in(x)})
    quiet = sorted(c for c in allcmds
                   if c not in buttons and c not in held_cmds)
    if held_cmds:
        print("  %-16s %s: held back, so no button" % ("", ", ".join(held_cmds)))
    if quiet:
        print("  %-16s %s: satellite(s), no button by design"
              % ("", ", ".join(quiet)))
    for c in buttons:
        q = re.escape(c)
        show("panel " + c, "lisp/lazpanel/LAZPANEL.lsp",
             hits("lisp/lazpanel/LAZPANEL.lsp",
                  lambda ln: re.search(r'\("%s"\s+"' % q, ln)),
             "NO CAPTION in lzp:*captions*")
        show("tooltip " + c, "ui/calofin_net/blurbs.txt",
             hits("ui/calofin_net/blurbs.txt",
                  lambda ln: re.match(r"%s\s" % q, ln)),
             "NO TOOLTIP in ui/calofin_net/blurbs.txt")
        show("probe " + c, "ui/calofin_ui/calofin.lsp",
             hits("ui/calofin_ui/calofin.lsp",
                  lambda ln: re.search(r'"%s"' % q, ln)),
             "NOT IN THE PROBE LIST -- its button can never grey out")
    show("README row", "README.md",
         hits("README.md",
              lambda ln: ln.startswith("|") and any(
                  "`%s`" % c in ln for c in allcmds)),
         "NO ROW in README.md's command tables")
    print("\n(check with: python3 tools/check_registry.py)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
