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


def rev_of(text):
    """The REV a file's own version banner asks to be stamped with."""
    m = VERSION.search(text)
    if m:
        return "REV%s%s" % (m.group(1), m.group(2))
    m = VERSION2.search(text)
    if m:
        return "REV%s" % m.group(2)
    return None


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
