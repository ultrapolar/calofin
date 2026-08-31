#!/usr/bin/env python3
"""Concatenate the drone edition into one APPLOAD-able file.

    python3 tools/build_drone_edition.py          -> editions/TYLERDRONE.lsp
    python3 tools/build_drone_edition.py --check  #  write nothing;
                                                  #  exit 1 if stale

WHAT IT IS.  The whole calofin build, plus a button of its own for
TYLERDRONESUITE.  Two things on the toolbar strip: the panel's hexagon,
which opens the full roster the way it always has, and an orange
triangle that runs the drone suite on one click.

WHY IT IS NOT SMALLER.  It was, once: the four files the suite really
takes (AutoDim, PADDLE, tydrn, LAZPANEL).  But a hexagon in front of a
panel where ten buttons of a hundred and forty-two do anything is a
panel that looks broken.  Someone who wants the hexagon wants the tools
behind it, so the edition carries them.

WHY IT IS NOT JUST LAZPASS.  LAZPASS deliberately puts up ONE external
button, the panel's -- inside the build the suite rides the panel like
every other tool.  That rule is right and stays; this is one person's
build, where the suite has earned a button of its own.

The bundle is taken from build_shared_bundle.build() rather than read
off disk, so an edition can never be built from a stale LAZPASS.lsp and
then agree with itself at --check time.

BOTH tunables are stated outright in the footer, and that is the whole
lesson of the bug this file once shipped.  lzp:*suitebutton* AUTO works
out whether to give the suite a button by reading cal:*build-loading*,
which LAZPASS raises and nothing lowers -- so an edition that left the
question to AUTO read a flag from the bundle it had just embedded,
decided it was inside the build, and put up no button at all.  An
edition knows which buttons it wants.  It says so.
"""

import datetime
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import build_shared_bundle  # noqa: E402

OUT = ROOT / "editions" / "TYLERDRONE.lsp"

RULE = ";;; " + "=" * 70

#: The command the extra button runs, and the tool file that defines it.
#: Named here so a rename cannot leave the edition pointing at nothing.
COMMAND = "TYLERDRONESUITE"
DEFINED_BY = "shared/parts/tydrn.lsp"


def build():
    """The edition's full text, or an error message via sys.exit."""
    src = ROOT / DEFINED_BY
    if not src.is_file():
        sys.exit("build_drone_edition: %s is missing" % DEFINED_BY)
    if ("c:" + COMMAND) not in src.read_text(encoding="utf-8"):
        sys.exit("build_drone_edition: %s no longer defines c:%s, so this\n"
                 "edition would put up a button that answers a click with\n"
                 "\"Unknown command\".  Find what it is called now."
                 % (DEFINED_BY, COMMAND))

    # build() hands back (text, member names, command names)
    bundle, _names, commands = build_shared_bundle.build()
    if COMMAND.upper() not in {c.upper() for c in commands}:
        sys.exit("build_drone_edition: %s is not in the bundle, so\n"
                 "this edition would put up a button for a command\n"
                 "that is not there." % COMMAND)
    stamp = datetime.date.today().strftime("%Y-%m-%d")
    head = [
        RULE,
        ";;; TYLERDRONE.lsp  --  the whole calofin build, plus one button",
        ";;; " + "-" * 70,
        ";;; Built %s by tools/build_drone_edition.py -- DO NOT EDIT." % stamp,
        ";;; Edit the files under lisp/ and rebuild.",
        ";;;",
        ";;; APPLOAD this one file.  Two things land on the toolbar strip:",
        ";;;",
        ";;;   the orange HEXAGON   opens the LazPanel roster, as ever",
        ";;;   the orange TRIANGLE  runs %s on one click" % COMMAND,
        ";;;",
        ";;; The triangle is the only thing this build adds to LAZPASS.lsp,",
        ";;; which is otherwise carried here whole.  LAZPASS itself puts up",
        ";;; one external button on purpose -- there the suite rides the",
        ";;; panel like every other tool -- and that is unchanged; this is",
        ";;; the build for someone who runs the drone job all day and wants",
        ";;; it under the cursor.",
        RULE,
        "",
    ]
    foot = [
        "",
        RULE,
        ";;; >>> the edition's own footer",
        RULE,
        "",
        ";; BOTH buttons, and both said outright rather than deduced.",
        ";;",
        ";; lzp:*suitebutton* AUTO would work the second one out by reading",
        ";; cal:*build-loading*, which the bundle above has just raised and",
        ";; nothing ever lowers -- so AUTO would conclude it is inside",
        ";; LAZPASS and decline the very button this file exists for.  That",
        ";; is not a bug in AUTO: AUTO is right for a plain build.  It is",
        ";; the wrong question to ask here, because this edition already",
        ";; knows the answer.",
        "(setq lzp:*panelbutton* T)",
        "(setq lzp:*suitebutton* T)",
        "(vl-catch-all-apply 'lzp:buttons-init nil)",
        "",
        ";; And say how it went.  A load that quietly leaves nothing on",
        ";; screen is what made the last one of these take a bug report.",
        "(if (and (vl-catch-all-apply 'lzp:toolbar-find"
        " (list lzp:*tbname*))",
        "         (vl-catch-all-apply 'lzp:toolbar-find"
        " (list lzp:*tbsuite*)))",
        '  (princ "\\nTYLERDRONE: both buttons are on screen - the hexagon'
        ' opens the panel,")',
        '  (princ "\\nTYLERDRONE: the buttons could not be put up - the'
        ' AutoCAD menu API is")',
        ")",
        "(if (and (vl-catch-all-apply 'lzp:toolbar-find"
        " (list lzp:*tbname*))",
        "         (vl-catch-all-apply 'lzp:toolbar-find"
        " (list lzp:*tbsuite*)))",
        '  (princ "\\nthe triangle runs %s.")' % COMMAND,
        '  (princ "\\nunavailable here.  Type %s instead, or LAZBUTTON'
        ' to retry.")' % COMMAND,
        ")",
        "(princ)",
        "",
    ]
    return "\n".join(head) + bundle.rstrip("\n") + "\n" + "\n".join(foot)


def _undated(text):
    """The text with the build stamp taken out.  The stamp is today's
    date, so an edition built yesterday is not stale for that alone."""
    return re.sub(r";;; Built \d{4}-\d\d-\d\d ", ";;; Built ", text)


def check():
    """A list of problems, for tools/check_standards.py -- empty when the
    edition on disk is what a fresh build would write."""
    text = build()
    if not OUT.is_file():
        return ["editions/TYLERDRONE.lsp is missing - run "
                "python3 tools/build_drone_edition.py"]
    have = OUT.read_text(encoding="utf-8")
    if _undated(have) != _undated(text):
        return ["editions/TYLERDRONE.lsp differs from what "
                "build_drone_edition.py generates - it is GENERATED: edit "
                "the files under lisp/ and rerun "
                "python3 tools/build_drone_edition.py"]
    return []


def main(argv):
    if "--check" in argv:
        problems = check()
        for line in problems:
            print(line)
        print("build_drone_edition --check: %s"
              % ("%d problem(s)" % len(problems) if problems else "current"))
        return 1 if problems else 0
    text = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8")
    print("wrote editions/TYLERDRONE.lsp (%d lines, %d KB) - LAZPASS plus "
          "the %s button" % (len(text.splitlines()), len(text) // 1024,
                             COMMAND))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
