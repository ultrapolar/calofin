#!/usr/bin/env python3
"""Concatenate the shared build into one APPLOAD-able file.

shared/parts/CALOFIN-LOADER.lsp has to find its 36 siblings on disk, and
AutoCAD only lets it look along the support file search path -- which
is not where APPLOAD's file dialog just sent you.  A single file has
nothing to find, so this is the build to hand someone:

    python3 tools/build_shared_bundle.py   ->  shared/LAZPASS.lsp

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
BUNDLE = SHARED / "LAZPASS.lsp"

RULE = ";;; " + "=" * 70
COMMAND = re.compile(r"^\(defun\s+[cC]:([^\s()]+)", re.MULTILINE)
HELD = re.compile(r'\("([^"]+)"\s*\.\s*"(WIP|OMITTED)"\)')


def held_back():
    """(file, reason) pairs the loader deliberately leaves out of the build."""
    return HELD.findall(LOADER.read_text(encoding="utf-8"))


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
        ";;; LAZPASS.lsp  --  the whole shared build in one file",
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
    ] + ([";;;", ";;; Deliberately NOT in this build (see cal:*held-back* in",
          ";;; CALOFIN-LOADER.lsp):", ";;;"] +
         [";;;   %-20s %s" % (n, w) for n, w in held_back()]
         if held_back() else []) + [
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
        # The count used to be baked in here, so a build that half
        # loaded still announced every command it was BUILT with.  A
        # command that never arrived is exactly what a greyed button on
        # the panel means, so the footer checks its own claim: an
        # unbound C: name evaluates to nil, and anything missing is
        # named rather than counted over.
        ";;; -------------------- what actually arrived ---------------------------",
        "(setq lazpass:*want* '(",
    ] + ["  " + " ".join('"%s"' % c for c in commands[i:i + 6])
         for i in range(0, len(commands), 6)] + [
        "))",
        "",
        "(setq lazpass:*missing* nil)",
        "(foreach n lazpass:*want*",
        "  (if (not (eval (read (strcat \"C:\" n))))",
        "    (setq lazpass:*missing* (cons n lazpass:*missing*))))",
        "",
        "(if lazpass:*missing*",
        "  (progn",
        '    (princ (strcat "\\nLAZPASS: only " (itoa (- (length lazpass:*want*)',
        "                                             (length lazpass:*missing*)))",
        '                   " of " (itoa (length lazpass:*want*))',
        '                   " commands loaded -- this build is incomplete."))',
        '    (princ "\\nLAZPASS: missing:")',
        "    (foreach n (reverse lazpass:*missing*)",
        '      (princ (strcat " " n))))',
        '  (princ (strcat "\\nLAZPASS: calofin shared build loaded - "',
        '                 (itoa (length lazpass:*want*))',
        '                 " commands in one session.")))',
        "(princ)",
        "",
    ]
    BUNDLE.write_text("\n".join(out), encoding="utf-8")
    print("wrote %s (%d files, %d commands, %.0f KB)" %
          (BUNDLE.relative_to(ROOT), len(names), len(commands),
           BUNDLE.stat().st_size / 1024))
    for name, why in held_back():
        print("  held back (%s): %s" % (why, name))


if __name__ == "__main__":
    main()
