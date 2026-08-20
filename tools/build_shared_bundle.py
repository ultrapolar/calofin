#!/usr/bin/env python3
"""Concatenate the shared build into one APPLOAD-able file.

shared/parts/CALOFIN-LOADER.lsp has to find its 36 siblings on disk, and
AutoCAD only lets it look along the support file search path -- which
is not where APPLOAD's file dialog just sent you.  A single file has
nothing to find, so this is the build to hand someone:

    python3 tools/build_shared_bundle.py   ->  shared/CALOFIN-ALL.lsp

Same idea as the STEPS bundle in release_lisp.py: members are included
verbatim, in the loader's own order, library first.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHARED = ROOT / "shared"
PARTS = SHARED / "parts"
LOADER = PARTS / "CALOFIN-LOADER.lsp"
BUNDLE = SHARED / "CALOFIN-ALL.lsp"

RULE = ";;; " + "=" * 70
COMMAND = re.compile(r"^\(defun\s+[cC]:([^\s()]+)", re.MULTILINE)


def members():
    """The loader's own list, so the two can never disagree."""
    body = LOADER.read_text(encoding="utf-8")
    block = re.search(r"\(foreach m '\((.*?)\)\s*\n\s*\(cal--load m\)",
                      body, re.S)
    if not block:
        sys.exit("could not read the module list out of CALOFIN-LOADER.lsp")
    return re.findall(r'"([^"]+)"', block.group(1))


def main():
    names = members()
    missing = [n for n in names if not (PARTS / n).is_file()]
    if missing:
        sys.exit("missing from shared/parts/: %s" % missing)

    commands = []
    for n in names:
        commands.extend(COMMAND.findall((PARTS / n).read_text(
            encoding="utf-8", errors="replace")))

    out = [
        RULE,
        ";;; CALOFIN-ALL.lsp  --  the whole shared build in one file",
        ";;; " + "-" * 70,
        ";;; GENERATED - do not edit.  Rebuild it with:",
        ";;;     python3 tools/build_shared_bundle.py",
        ";;;",
        ";;; APPLOAD this ONE file and every command below comes with it.",
        ";;; Nothing else needs loading, and it does not matter what folder",
        ";;; you run it from - there are no sibling files to find.",
        ";;;",
        ";;; %d files, %d commands:" % (len(names), len(commands)),
        ";;;",
    ]
    for i in range(0, len(sorted(commands)), 6):
        out.append(";;;   " + "  ".join(sorted(commands)[i:i + 6]))
    out += [
        ";;;",
        ";;; Included verbatim, in CALOFIN-LOADER.lsp's order, library first.",
        RULE,
        "",
        ";; tells CALOFIN-LIB.lsp it is arriving as part of the whole build",
        "(setq cal:*build-loading* T)",
        "",
    ]

    for n in names:
        out += ["", RULE, ";;; >>> %s" % n, RULE, ""]
        out.append((PARTS / n).read_text(encoding="utf-8", errors="replace"))

    out += [
        "",
        RULE,
        '(princ (strcat "\\nCALOFIN: shared build loaded - %d commands '
        'in one session."))' % len(commands),
        "(princ)",
        "",
    ]
    BUNDLE.write_text("\n".join(out), encoding="utf-8")
    print("wrote %s (%d files, %d commands, %.0f KB)" %
          (BUNDLE.relative_to(ROOT), len(names), len(commands),
           BUNDLE.stat().st_size / 1024))


if __name__ == "__main__":
    main()
