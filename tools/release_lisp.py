# SPDX-License-Identifier: GPL-3.0-or-later
"""Make dated distribution copies of the AutoLISP routines that carry a
version banner.

  lisp/cornerstp/CORNERSTP.lsp     the current, static-named copy - the
                                   one in the startup suite / APPLOAD
                                   stack, so loading never has to chase
                                   a filename
  releases/CORNERSTP_MMDDYY_REV22.lsp
                                   a dated copy, flat in releases/ (no
                                   per-tool subfolder), whose name says
                                   exactly which iteration someone has
                                   in their stack

The REV number is the file's own version banner with the dot dropped
(v2.2 -> REV22), so the filename, the load banner, and the banner the
command prints at start can never disagree. The date is the day the
snapshot was made.

BUNDLES
-------
A few routines belong together in the field and ship as ONE file rather
than one file each - see BUNDLES below. The step routines are the
standing example: CORNERSTP, HEMISTEP and NORMIESTEP release as a single
releases/STEPS_MMDDYY_REV22-25-14.lsp, with each source concatenated
verbatim in the order its REV appears in that name. Nothing is rewritten
on the way in, so the bundle can be diffed against its sources, and the
members get no separate dated copies of their own.

Run this after any change to a .lsp file:

    python3 tools/release_lisp.py

It re-reads each static file's version, writes the new dated copy into
releases/, and removes the previous dated copy of that routine (git
history keeps the old ones). A .lsp file with no version banner (most
tools don't use this convention) is skipped - that's not an error, just
nothing to release.
"""

import datetime
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
LISP_DIR = ROOT / "lisp"
RELEASES_DIR = ROOT / "releases"
DATED = re.compile(r".*_\d{6}_REV[\d-]+\.lsp$", re.IGNORECASE)
VERSION = re.compile(r'\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"')
COMMAND = re.compile(r"^\(defun\s+c:([^\s()]+)", re.MULTILINE)

#: Groups of sources that release as one file instead of one each.
#: ``members`` is the concatenation order, and the order the REV numbers
#: are listed in the release filename.
BUNDLES = [
    {
        "name": "STEPS",
        "dir": "cornerstp",
        "members": ["CORNERSTP.lsp", "HEMISTEP.lsp", "NORMIESTEP.lsp"],
        "blurb": "the pool-step layout routines",
    },
]

RULE = ";;; " + "=" * 70


def version_of(src):
    """(major, minor) from the file's version banner, or None."""
    m = VERSION.search(src.read_text())
    return (m.group(1), m.group(2)) if m else None


def rev(version):
    """v2.2 -> "22" - the banner with the dot dropped."""
    return "%s%s" % version


def prune(stem, keep):
    """Drop earlier dated copies of ``stem``, keeping ``keep``."""
    for old in RELEASES_DIR.glob("%s_[0-9]*_REV*.lsp" % stem):
        if old != keep:
            old.unlink()
            print("removed %s" % old.relative_to(ROOT))


def bundle_header(bundle, parts, name):
    """The generated preamble that sits above the concatenated sources."""
    rows = []
    for src, version in parts:
        cmds = ", ".join(COMMAND.findall(src.read_text()))
        rows.append(";;;     %-15s v%s.%s -> REV%s   %s"
                    % (src.name, version[0], version[1], rev(version), cmds))
    return "\n".join([
        RULE,
        ";;; %s" % name,
        ";;; " + "-" * 70,
        ";;; GENERATED - do not edit.  Rebuild it with:",
        ";;;     python3 tools/release_lisp.py",
        ";;;",
        ";;; A one-file release of %s.  Each one is" % bundle["blurb"],
        ";;; included below verbatim from its source in lisp/%s/, in the"
        % bundle["dir"],
        ";;; order its REV number appears in the filename above:",
        ";;;",
    ] + rows + [
        ";;;",
        ";;; LOAD:  APPLOAD this one file (or drag it into the drawing",
        ";;;        window) and every command listed above comes with it.",
        ";;;",
        ";;; Each routine keeps its own helper namespace and its own",
        ";;; version banner, and prints that banner as it loads, so this",
        ";;; bundle behaves exactly like loading the sources one after",
        ";;; another - it is only the packaging that differs.",
        RULE,
        "",
        "",
    ])


def release_bundle(bundle, date):
    """Write one dated file holding all of ``bundle``'s members."""
    parts = []
    for member in bundle["members"]:
        src = LISP_DIR / bundle["dir"] / member
        version = version_of(src)
        if version is None:
            print("%s: no version banner - %s bundle not released"
                  % (src.relative_to(ROOT), bundle["name"]))
            return
        parts.append((src, version))

    revs = "-".join(rev(version) for _, version in parts)
    name = "%s_%s_REV%s.lsp" % (bundle["name"], date, revs)
    dst = RELEASES_DIR / name

    text = bundle_header(bundle, parts, name)
    for src, version in parts:
        text += "\n".join([
            RULE,
            ";;; >>> %s (v%s.%s) - verbatim from lisp/%s/%s"
            % (src.name, version[0], version[1], bundle["dir"], src.name),
            RULE,
            "",
        ])
        text += src.read_text()
        text += "\n"

    prune(bundle["name"], dst)
    for src, _ in parts:                # any leftover single-file copies
        prune(src.stem, dst)
    dst.write_text(text)
    print("%s -> %s" % (", ".join("lisp/%s/%s" % (bundle["dir"], s.name)
                                  for s, _ in parts), dst.relative_to(ROOT)))


def main():
    date = datetime.date.today().strftime("%m%d%y")
    RELEASES_DIR.mkdir(parents=True, exist_ok=True)

    bundled = set()
    for bundle in BUNDLES:
        for member in bundle["members"]:
            bundled.add(LISP_DIR / bundle["dir"] / member)

    for src in sorted(LISP_DIR.rglob("*.lsp")):
        if DATED.match(src.name):
            continue
        if src in bundled:
            continue                    # released as part of a bundle
        version = version_of(src)
        if not version:
            print("%s: no version banner - skipped" % src.relative_to(ROOT))
            continue
        dst = RELEASES_DIR / ("%s_%s_REV%s.lsp" % (src.stem, date, rev(version)))
        prune(src.stem, dst)
        shutil.copyfile(src, dst)
        print("%s (v%s.%s) -> %s" % (src.relative_to(ROOT), version[0],
                                     version[1], dst.relative_to(ROOT)))

    for bundle in BUNDLES:
        release_bundle(bundle, date)


if __name__ == "__main__":
    main()
