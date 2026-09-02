#!/usr/bin/env python3
"""Concatenate the shared build into one APPLOAD-able file.

shared/parts/CALOFIN-LOADER.lsp has to find its several dozen siblings
on disk, and AutoCAD only lets it look along the support file search
path -- which is not where APPLOAD's file dialog just sent you.  A
single file has nothing to find, so this is the build to hand someone:

    python3 tools/build_shared_bundle.py            ->  shared/LAZPASS.lsp
    python3 tools/build_shared_bundle.py --check    #  write nothing;
                                                    #  exit 1 if stale

Same idea as the STEPS bundle in release_lisp.py: members are included
verbatim, in the loader's own order, library first.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from callib import (BUNDLE, CAL_SYM, COMMAND, HELD, LOADER,
                    PARTS_DIR as PARTS, ROOT, RULE, decomment, loader_members,
                    read)

#: The calofin release this build belongs to.  Per-tool banners keep
#: their own REVs -- they say what changed in one file; this says which
#: set of them shipped together.  Bump it here and nowhere else: the
#: bundle header and its load announcement are both generated from it.
RELEASE = "v3.4"


def held_back():
    """(file, reason) pairs the loader deliberately leaves out of the build."""
    return HELD.findall(read(LOADER))


def members():
    """The loader's own list, so the two can never disagree."""
    names = loader_members(LOADER)
    if names is None:
        sys.exit("could not read the module list out of CALOFIN-LOADER.lsp")
    return names


def build():
    """The bundle's full text, or an error message via sys.exit."""
    names = members()
    missing = [n for n in names if not (PARTS / n).is_file()]
    if missing:
        sys.exit("missing from shared/parts/: %s" % missing)

    commands = []
    for n in names:
        cmds = COMMAND.findall(read(PARTS / n))
        for c in cmds:
            if c.upper() in {x.upper() for x in commands}:
                sys.exit("command %s is defined by more than one member - "
                         "the bundle would claim it twice" % c.upper())
        commands.extend(cmds)

    # Every cal: helper the members call is one the library defines --
    # a helper renamed in CALOFIN-LIB.lsp without re-mirroring passed
    # every check and died on the first click -- and the footer checks
    # the same list at load, the way it checks the commands.
    lib_defs = {m for m in CAL_SYM.findall(read(PARTS / names[0]))
                if not m.startswith("cal:*")}
    # a call is a cal: name in head position or quoted; the globals are
    # the earmuffed cal:*name* and are not calls (comments are blanked
    # first: the prose names helpers too)
    helpers = sorted({m.group(1) for n in names[1:]
                      for m in re.finditer(r"[('](cal:[^\s()'*][^\s()']*)",
                                           decomment(read(PARTS / n)))})
    unknown = [h for h in helpers if h not in lib_defs]
    if unknown:
        sys.exit("members call cal: helpers the library does not define: %s"
                 % unknown)

    out = [
        RULE,
        ";;; LAZPASS.lsp  --  calofin %s, the whole shared build in one file"
        % RELEASE,
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
    ordered = sorted(commands)
    for i in range(0, len(ordered), 6):
        out.append(";;;   " + "  ".join(ordered[i:i + 6]))
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
        out.append(read(PARTS / n))

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
        '  (princ (strcat "\\nLAZPASS: calofin %s loaded - "' % RELEASE,
        '                 (itoa (length lazpass:*want*))',
        '                 " commands in one session.")))',
        "",
        ";; ...and every library helper the tools above call, checked the",
        ";; same way: a tool that calls one the library lacks looks fine",
        ";; until its first click",
        "(setq lazpass:*helpers* '(",
    ] + ["  " + " ".join(helpers[i:i + 5])
         for i in range(0, len(helpers), 5)] + [
        "))",
        "(setq lazpass:*nohelper* nil)",
        "(foreach n lazpass:*helpers*",
        "  (if (not (eval n))",
        "    (setq lazpass:*nohelper* (cons n lazpass:*nohelper*))))",
        "(if lazpass:*nohelper*",
        "  (progn",
        '    (princ "\\nLAZPASS: library helpers the tools call but the build lacks:")',
        "    (foreach n (reverse lazpass:*nohelper*)",
        '      (princ (strcat " " (vl-symbol-name n))))))',
        "",
        ";; the flag the header set for the library: cleared, so a later",
        ";; APPLOAD of CALOFIN-LIB.lsp on its own in this drawing still says",
        ";; what it is",
        "(setq cal:*build-loading* nil)",
        "(princ)",
        "",
    ]
    return "\n".join(out), names, commands


def check():
    """Problems with shared/LAZPASS.lsp, without writing anything."""
    text, _, _ = build()
    if not BUNDLE.is_file():
        return ["shared/LAZPASS.lsp is missing - run "
                "python3 tools/build_shared_bundle.py"]
    if BUNDLE.read_text(encoding="utf-8") != text:
        return ["shared/LAZPASS.lsp differs from what today's members "
                "build - run python3 tools/build_shared_bundle.py"]
    return []


def main(argv):
    if "--check" in argv:
        problems = check()
        for line in problems:
            print(line)
        print("build_shared_bundle --check: %s"
              % ("%d problem(s)" % len(problems) if problems else "current"))
        return 1 if problems else 0

    text, names, commands = build()
    BUNDLE.write_text(text, encoding="utf-8")
    print("wrote %s (%d files, %d commands, %.0f KB)" %
          (BUNDLE.relative_to(ROOT), len(names), len(commands),
           BUNDLE.stat().st_size / 1024))
    for name, why in held_back():
        print("  held back (%s): %s" % (why, name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
