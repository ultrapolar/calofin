# SPDX-License-Identifier: GPL-3.0-or-later
"""The pieces every tools/ script needs, defined once.

Before this module each script carried its own copy of the tree layout,
the banner/command regexes, the held-back parser and a comment/string
stripper -- four hand-rolled AutoLISP readers with four sets of bugs.
A regex fixed in one script stayed broken in the others (release_lisp's
COMMAND regex missed ``(defun C:TYDRN`` for exactly that reason), so the
shared knowledge now lives here and the scripts import it.

Nothing here writes to the tree.
"""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent

WIP_DIR = ROOT / "wip"
LISP_DIR = ROOT / "lisp"
RELEASES_DIR = ROOT / "releases"
SHARED_DIR = ROOT / "shared"
PARTS_DIR = SHARED_DIR / "parts"
LOADER = PARTS_DIR / "CALOFIN-LOADER.lsp"
BUNDLE = SHARED_DIR / "LAZPASS.lsp"

RULE = ";;; " + "=" * 70

#: The two version banner forms release_lisp.py understands.  VERSION is
#: the standard ``(setq *tool-version* "v2.2")``; VERSION2 is the
#: pool/spa ``(setq ns:*version* "MMDDYY REV##")`` style, whose banner
#: names its own date so a re-run is a no-op.
VERSION = re.compile(r'\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"')
VERSION2 = re.compile(r'\*version\*\s+"(\d{6}) REV(\d{2})"')

DEFUN = re.compile(r"^\(defun\s+([^\s()]+)", re.MULTILINE)
#: ``c:`` is conventionally lowercase but AutoLISP does not care, and
#: the tree holds at least one ``(defun C:...`` -- match both.
COMMAND = re.compile(r"^\(defun\s+[cC]:([^\s()]+)", re.MULTILINE)
CAL_SYM = re.compile(r"^\((?:defun|setq)\s+(cal:[^\s()]+)", re.MULTILINE)
HELD = re.compile(r'\("([^"]+)"\s*\.\s*"(WIP|OMITTED)"\)')
DATED = re.compile(r".*_\d{6}_REV[\d-]+\.lsp$", re.IGNORECASE)

#: Groups of sources that release as one file instead of one each.
#: ``members`` is the concatenation order, and the order the REV numbers
#: are listed in the release filename.  check_standards.py derives its
#: bundled-file exemption from this same list, so the two cannot drift.
BUNDLES = [
    {
        "name": "STEPS",
        "dir": "cornerstp",
        "members": ["CORNERSTP.lsp", "HEMISTEP.lsp", "NORMIESTEP.lsp"],
        "blurb": "the pool-step layout routines",
    },
]


def bundled_members():
    """Names of sources released inside a bundle (no twin of their own)."""
    out = set()
    for bundle in BUNDLES:
        out.update(bundle["members"])
    return out


def read(p):
    return pathlib.Path(p).read_text(encoding="utf-8", errors="replace")


def lsp_files(d):
    """Every .lsp under d, in a stable order, whatever the extension case."""
    d = pathlib.Path(d)
    if not d.is_dir():
        return []
    return sorted(p for p in d.rglob("*")
                  if p.is_file() and p.suffix.lower() == ".lsp")


def held_back(loader=LOADER):
    """Files the loader deliberately keeps out of the build, name -> reason."""
    loader = pathlib.Path(loader)
    if not loader.is_file():
        return {}
    return dict(HELD.findall(read(loader)))


def loader_members(loader=LOADER):
    """The loader's own module list, in load order, or None if unreadable."""
    body = read(loader)
    block = re.search(r"\(foreach m '\((.*?)\)\s*\n\s*\(cal--load m\)",
                      body, re.S)
    if not block:
        return None
    return re.findall(r'"([^"]+)"', block.group(1))


#: The deprecated acady matcher is not part of the toolset -- it matches
#: drawing geometry, ships no commands anyone types, and is not carried
#: into shared/.  Every roster reader skips it.
NOT_A_TOOL = "standards_checker"

#: Satellites: real commands that deliberately carry no panel button.
#: The first four are name-shaped rules (a tutorial, the drone-height
#: toolset, a config/setup entry point, or a VER/VERSION/RESCUE sibling
#: of a command that IS on the panel); the set below is named one by one
#: because no rule describes them.  DCE is DIMCONTEND's short alias and
#: STOCKLIST is STOCKCOVER's listing companion -- both reachable without
#: a button.  LAZPANEL is the panel itself, LAZBUTTON summons its
#: toolbar, LAZICON reports where the button's picture came from and
#: LAZPIN edits the pinned row: machinery, not drafting tools.  LAZASCII
#: is LAZFORM's font probe -- it draws nothing and answers nothing.
NAMED_SATELLITES = frozenset({
    "DCE", "STOCKLIST", "LAZPANEL", "LAZBUTTON", "LAZICON", "LAZPIN",
    "LAZASCII",
})


def census(lisp_dir=LISP_DIR):
    """Every C: command defined under lisp/, the matcher excluded."""
    out = set()
    for p in lsp_files(lisp_dir):
        if NOT_A_TOOL in p.parts:
            continue
        out |= {m.upper() for m in COMMAND.findall(read(p))}
    return out


def held_commands(loader=LOADER, parts=PARTS_DIR):
    """Commands of every held-back file, read off the loader's list."""
    out = set()
    for name in held_back(loader):
        p = pathlib.Path(parts) / name
        if p.is_file():
            out |= {m.upper() for m in COMMAND.findall(read(p))}
    return out


def satellites(all_commands):
    """Of ALL_COMMANDS, the ones that deliberately carry no button."""
    out = set(NAMED_SATELLITES) & set(all_commands)
    for c in all_commands:
        base = None
        if c.startswith("TUTORIAL") or c.startswith("DD"):
            out.add(c)
        elif c.endswith("-CFG") or c.endswith("-SETUP"):
            out.add(c)
        elif c.endswith("VERSION"):
            base = c[:-len("VERSION")]
        elif c.endswith("VER"):
            base = c[:-len("VER")]
        elif c.endswith("RESCUE"):
            base = c[:-len("RESCUE")]
        if base and base in all_commands:
            out.add(c)
    return out


def headline_commands(lisp_dir=LISP_DIR, loader=LOADER, parts=PARTS_DIR):
    """The commands that must each carry exactly one panel button.

    Every C: command under lisp/, less the satellites that deliberately
    have none and less whatever the loader holds back.  This is the one
    definition of the panel roster: tests/test_lazpanel.py pins the
    panel against it and tools/check_registry.py repairs against it, so
    the two cannot disagree about what belongs on the panel.
    """
    allc = census(lisp_dir)
    return allc - satellites(allc) - held_commands(loader, parts)


def rev_of(text):
    """The REV a file's own version banner asks to be stamped with."""
    m = VERSION.search(text)
    if m:
        return "REV%s%s" % (m.group(1), m.group(2))
    m = VERSION2.search(text)
    if m:
        return "REV%s" % m.group(2)
    return None


def decomment(src):
    """SRC with ``;`` comments blanked to spaces, everything else --
    string literals included -- left exactly where it was.

    ``strip`` blanks string CONTENTS, which is right for the structural
    readers but wrong for the rules that are ABOUT a string: the load
    banner, ``"_Begin"``, ``ssget "_I"``.  Offsets and line numbers are
    preserved either way, so the two are interchangeable as inputs to a
    span finder."""
    out = list(src)
    i, n = 0, len(src)
    instr = False
    while i < n:
        ch = src[i]
        if instr:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == '"':
                instr = False
            i += 1
            continue
        if ch == '"':
            instr = True
            i += 1
            continue
        if ch == ";":
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
            continue
        i += 1
    return "".join(out)


def top_level_forms(src):
    """(start, end) of every top-level parenthesised form in SRC.

    Comments are blanked first so a ``;`` never unbalances the scan,
    and the offsets returned index into SRC itself."""
    masked = decomment(src)
    depth, start, spans = 0, None, []
    instr = False
    i = 0
    while i < len(masked):
        ch = masked[i]
        if instr:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                instr = False
        elif ch == '"':
            instr = True
        elif ch == "(":
            if depth == 0:
                start = i
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0 and start is not None:
                spans.append((start, i + 1))
                start = None
        i += 1
    return spans


def strip(src, keep_strings=False):
    """SRC with comments removed and (by default) string literals
    blanked, newlines kept so line numbers still line up.

    A string literal never vanishes entirely: its opening quote stays as
    the one-character marker token ``"`` so anything counting a form's
    elements still sees the literal as one argument.  In-string
    newlines stay newlines, so line numbers hold.

    With keep_strings=True the in-string text is dropped instead of
    blanked (the marker still stands for the whole literal) -- the
    compact form the structural readers parse."""
    out = []
    i, n = 0, len(src)
    instr = False
    while i < n:
        ch = src[i]
        if instr:
            if ch == "\\" and i + 1 < n:
                if not keep_strings:
                    out.append("  " if src[i + 1] != "\n" else " \n")
                i += 2
                continue
            if ch == '"':
                instr = False
                i += 1
                continue
            if not keep_strings:
                out.append(ch if ch == "\n" else " ")
            i += 1
            continue
        if ch == '"':
            instr = True
            out.append('"')
            i += 1
            continue
        if ch == ";":
            while i < n and src[i] != "\n":
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out), instr
