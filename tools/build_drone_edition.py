#!/usr/bin/env python3
"""Concatenate the drone edition into one APPLOAD-able file.

    python3 tools/build_drone_edition.py          -> editions/TYLERDRONE.lsp
    python3 tools/build_drone_edition.py --check  #  write nothing;
                                                  #  exit 1 if stale

WHY THIS EXISTS.  TYLERDRONESUITE is TYDRN, then PADDLE, then AUTODIM --
three commands out of three different files -- and its screen button is
drawn by a fourth.  So there is no single file in the tree that can be
handed to someone who wants only the drone job: tydrn.lsp on its own has
no button and refuses to run, correctly, because two of its three stages
are missing.  LAZPASS.lsp has everything, which is the opposite problem.

This is the middle: the four files it really takes, in one download, put
together so that the ONLY thing on the toolbar strip is the drone
button.  LAZPANEL comes along because it owns the bitmap and toolbar
machinery, and its panel still types the same as ever -- it is simply
not on the strip, which is what lzp:*panelbutton* nil says.

It is a build of the STANDALONE tier, not the shared one: those files
carry their own helper copies, so nothing here needs CALOFIN-LIB.  And
it must NOT raise cal:*build-loading*, because that flag is exactly what
tells the suite it arrived inside LAZPASS and should not have a button
of its own -- here it should.
"""

import datetime
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / "editions" / "TYLERDRONE.lsp"

#: The edition, in load order.  LAZPANEL is last for the reason the
#: shared loader puts it last: its load-time button init asks which
#: commands exist, and a command loaded after it would be missed.
MEMBERS = [
    "lisp/autodim/AutoDim.lsp",
    "lisp/paddle/PADDLE.lsp",
    "lisp/tydrn/tydrn.lsp",
    "lisp/lazpanel/LAZPANEL.lsp",
]

#: LAZPANEL puts its buttons up as it loads.  That is too early here --
#: the edition has not said which buttons it wants yet -- so the call is
#: taken out and made again in the footer, after the tunables are set.
#:
#: Anchored to a line of its OWN, because the same call also appears
#: indented inside c:LAZBUTTON, and replacing that one instead cuts the
#: command in half.  A rename in LAZPANEL must not silently stop
#: mattering either, so both the spelling and the count are checked and
#: a surprise is a build failure rather than a shrug.
INIT_CALL = "\n(vl-catch-all-apply 'lzp:buttons-init nil)\n"

RULE = ";;; " + "=" * 70

VERSION_RE = re.compile(r'\*([a-z]+)-version\*\s+"(v\d+\.\d+)"')


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def version_of(text):
    m = VERSION_RE.search(text)
    return m.group(2) if m else "(unversioned)"


def build():
    """The edition's full text, or an error message via sys.exit."""
    parts, stamp = [], datetime.date.today().strftime("%Y-%m-%d")
    versions = []
    bodies = []
    for rel in MEMBERS:
        path = ROOT / rel
        if not path.is_file():
            sys.exit("build_drone_edition: %s is missing" % rel)
        body = read(rel)
        versions.append((pathlib.Path(rel).name, version_of(body)))
        if rel.endswith("LAZPANEL.lsp"):
            found = body.count(INIT_CALL)
            if found != 1:
                sys.exit(
                    "build_drone_edition: expected exactly one top-level\n"
                    "  %s\n"
                    "in LAZPANEL.lsp, found %d.  This build has to defer that\n"
                    "call until after it has set lzp:*panelbutton*.  Find what\n"
                    "changed and teach INIT_CALL the new spelling -- do not\n"
                    "just drop this."
                    % (INIT_CALL.strip(), found))
            body = body.replace(
                INIT_CALL,
                "\n;; The load-time call is TAKEN OUT here and made again in\n"
                ";; the edition's footer, once it has said which buttons it\n"
                ";; wants.  (tools/build_drone_edition.py)\n")
        bodies.append((rel, body))

    parts.append(RULE)
    parts.append(";;; TYLERDRONE.lsp  --  the drone trace in one file")
    parts.append(";;; " + "-" * 70)
    parts.append(";;; Built %s by tools/build_drone_edition.py -- DO NOT EDIT."
                 % stamp)
    parts.append(";;; Edit the files under lisp/ and rebuild.")
    parts.append(";;;")
    parts.append(";;; APPLOAD this one file.  It carries:")
    for name, ver in versions:
        parts.append(";;;     %-18s %s" % (name, ver))
    parts.append(";;;")
    parts.append(";;; Then type TYLERDRONESUITE, or click the orange triangle")
    parts.append(";;; on screen.  That button is the only one this build puts")
    parts.append(";;; up: LAZPANEL is here for the machinery that draws it and")
    parts.append(";;; still types the same as ever, it is just not on the")
    parts.append(";;; strip.  For the whole calofin toolkit, use LAZPASS.lsp")
    parts.append(";;; instead -- there the suite rides the panel like every")
    parts.append(";;; other tool and does not take a button of its own.")
    parts.append(RULE)
    parts.append("")

    for rel, body in bodies:
        parts.append(RULE)
        parts.append(";;; >>> %s" % rel)
        parts.append(RULE)
        parts.append("")
        parts.append(body.rstrip("\n"))
        parts.append("")

    parts.append(RULE)
    parts.append(";;; >>> the edition's own footer")
    parts.append(RULE)
    parts.append("")
    parts.append(";; One button on the strip, and it is the drone's.  The")
    parts.append(";; panel is along for the ride here -- it owns the bitmap")
    parts.append(";; and toolbar machinery -- so it does not take a button of")
    parts.append(";; its own; LAZPANEL still opens it if you type it.")
    parts.append(";;")
    parts.append(";; BOTH are stated outright, and the second one is the")
    parts.append(";; lesson.  lzp:*suitebutton* AUTO works out whether to")
    parts.append(";; give the suite a button by reading cal:*build-loading*,")
    parts.append(";; which LAZPASS raises and nothing ever lowers -- so on a")
    parts.append(";; machine that had loaded LAZPASS earlier in the session")
    parts.append(";; (a startup suite will do it every drawing) this edition")
    parts.append(";; read a flag left by somebody else, decided it was inside")
    parts.append(";; the build, and put up no button at all -- having already")
    parts.append(";; taken the panel's away.  An edition knows exactly which")
    parts.append(";; button it wants.  It should say so, not deduce it.")
    parts.append("(setq lzp:*panelbutton* nil)")
    parts.append("(setq lzp:*suitebutton* T)")
    parts.append("(vl-catch-all-apply 'lzp:buttons-init nil)")
    parts.append("")
    parts.append(";; And say so if it did not work.  A load that silently")
    parts.append(";; leaves nothing on screen is the failure that brought")
    parts.append(";; that bug back.")
    parts.append("(if (vl-catch-all-apply 'lzp:toolbar-find"
                 " (list lzp:*tbsuite*))")
    parts.append('  (princ "\nTYLERDRONE: the orange triangle is on screen -'
                 ' click it to run the suite.")')
    parts.append("  (progn")
    parts.append('    (princ "\nTYLERDRONE: the button could not be put up -'
                 ' the AutoCAD menu API")')
    parts.append('    (princ "\nis unavailable here.  Type TYLERDRONESUITE'
                 ' instead, or LAZBUTTON to retry.")))')
    parts.append("")
    parts.append('(princ "\\nTYLERDRONE edition loaded.  Type TYLERDRONESUITE'
                 ' (or click the orange")')
    parts.append('(princ "\\ntriangle) to run TYDRN, then PADDLE, then'
                 ' AUTODIM.")')
    parts.append("(princ)")
    parts.append("")
    return "\n".join(parts)


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
    print("wrote editions/TYLERDRONE.lsp (%d lines, %d KB, %d files)"
          % (len(text.splitlines()), len(text) // 1024, len(MEMBERS)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
