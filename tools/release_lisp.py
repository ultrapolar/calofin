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
than one file each - see BUNDLES in callib.py. The step routines are the
standing example: CORNERSTP, HEMISTEP and NORMIESTEP release as a single
releases/STEPS_MMDDYY_REV22-25-14.lsp, with each source concatenated
verbatim in the order its REV appears in that name. Nothing is rewritten
on the way in, so the bundle can be diffed against its sources, and the
members get no separate dated copies of their own.

Run this after any change to a .lsp file:

    python3 tools/release_lisp.py            # write / prune
    python3 tools/release_lisp.py --check    # write nothing; exit 1 if
                                             # releases/ is stale, has an
                                             # orphan, or misses a twin

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
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from callib import (BUNDLES, COMMAND, DATED, LISP_DIR, RELEASES_DIR, ROOT,
                    RULE, VERSION, VERSION2, lsp_files, read)


def sources():
    """Every static .lsp/.LSP under lisp/, in a stable order."""
    return lsp_files(LISP_DIR)


def version_of(src):
    """(major, minor) from the file's vN.N banner, or None."""
    m = VERSION.search(read(src))
    return (m.group(1), m.group(2)) if m else None


def rev(version):
    """v2.2 -> "22" - the banner with the dot dropped."""
    return "%s%s" % version


def twin_regex(stem, revs=None):
    """The dated-twin filename pattern for ``stem``.  With ``revs`` the
    REV part must match exactly; without, any dated copy of the stem."""
    return re.compile(re.escape(stem) + r"_[0-9]{6}_REV"
                      + (re.escape(revs) if revs else r"[\d-]+")
                      + r"\.lsp$", re.IGNORECASE)


def unchanged_twin(stem, revs, text, build=None):
    """An existing dated twin of this exact revision whose contents
    already match.  Its date is the day that snapshot was really made,
    so re-stamping it with today's would rename a file that did not
    change - and churn every release in the tree on any day the tool
    is run.  None when there is no such twin."""
    dated = twin_regex(stem, revs)
    for old in RELEASES_DIR.iterdir():
        if dated.fullmatch(old.name):
            try:
                want = build(old.name) if build else text
                if old.read_text(encoding="utf-8") == want:
                    return old
            except (OSError, UnicodeDecodeError):
                pass
    return None


def prune(stem, keep):
    """Drop other dated copies of ``stem``, keeping ``keep``."""
    dated = twin_regex(stem)
    for old in RELEASES_DIR.iterdir():
        if old != keep and dated.fullmatch(old.name):
            old.unlink()
            print("removed %s" % old.relative_to(ROOT))


def bundle_header(bundle, parts, name):
    """The generated preamble that sits above the concatenated sources."""
    rows = []
    for src, version in parts:
        cmds = ", ".join(COMMAND.findall(read(src)))
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


def bundle_parts(bundle):
    """[(source path, version)] for a bundle, or an error string."""
    parts = []
    for member in bundle["members"]:
        src = LISP_DIR / bundle["dir"] / member
        version = version_of(src) if src.is_file() else None
        if version is None:
            return ("%s: missing or without a version banner - the %s "
                    "bundle cannot be released"
                    % (src.relative_to(ROOT), bundle["name"]))
        parts.append((src, version))
    return parts


def bundle_builder(bundle, parts):
    """A build(as_name) closure for the bundle's full text."""
    def build(as_name):
        # the header names the file it sits in, so an unchanged bundle
        # only compares equal against its own name - not today's
        text = bundle_header(bundle, parts, as_name)
        for src, version in parts:
            text += "\n".join([
                RULE,
                ";;; >>> %s (v%s.%s) - verbatim from lisp/%s/%s"
                % (src.name, version[0], version[1], bundle["dir"],
                   src.name),
                RULE,
                "",
            ])
            text += read(src)
            text += "\n"
        return text
    return build


def release_bundle(bundle, date):
    """Write one dated file holding all of ``bundle``'s members."""
    parts = bundle_parts(bundle)
    if isinstance(parts, str):
        sys.exit(parts)

    revs = "-".join(rev(version) for _, version in parts)
    name = "%s_%s_REV%s.lsp" % (bundle["name"], date, revs)
    dst = RELEASES_DIR / name
    build = bundle_builder(bundle, parts)

    keep = unchanged_twin(bundle["name"], revs, None, build)
    if keep:
        prune(bundle["name"], keep)
        for src, _ in parts:
            prune(src.stem, keep)
        print("%s -> %s (unchanged)"
              % (", ".join("lisp/%s/%s" % (bundle["dir"], s.name)
                           for s, _ in parts), keep.relative_to(ROOT)))
        return
    dst.write_text(build(name), encoding="utf-8")
    prune(bundle["name"], dst)
    for src, _ in parts:                # any leftover single-file copies
        prune(src.stem, dst)
    print("%s -> %s" % (", ".join("lisp/%s/%s" % (bundle["dir"], s.name)
                                  for s, _ in parts), dst.relative_to(ROOT)))


def singles():
    """[(source, stem, revs, text)] for every individually-released file."""
    bundled = set()
    for bundle in BUNDLES:
        for member in bundle["members"]:
            bundled.add(LISP_DIR / bundle["dir"] / member)
    out = []
    for src in sources():
        if DATED.match(src.name) or src in bundled:
            continue
        text = read(src)
        m = VERSION.search(text)
        m2 = VERSION2.search(text) if not m else None
        if not m and not m2:
            continue
        if m:
            revs = rev((m.group(1), m.group(2)))
        else:
            revs = m2.group(2)
        out.append((src, src.stem, revs, text))
    return out


def check():
    """Problems with releases/, without writing anything."""
    problems = []
    if not RELEASES_DIR.is_dir():
        return ["releases/ is missing - run python3 tools/release_lisp.py"]
    expected = []                       # (stem, matcher for a CURRENT twin)
    for src, stem, revs, text in singles():
        keep = unchanged_twin(stem, revs, text)
        if keep is None:
            problems.append(
                "releases/ has no current twin of %s (REV%s) - run "
                "python3 tools/release_lisp.py" % (src.relative_to(ROOT),
                                                   revs))
        expected.append((stem, twin_regex(stem)))
    for bundle in BUNDLES:
        parts = bundle_parts(bundle)
        if isinstance(parts, str):
            problems.append(parts)
            continue
        revs = "-".join(rev(version) for _, version in parts)
        if unchanged_twin(bundle["name"], revs, None,
                          bundle_builder(bundle, parts)) is None:
            problems.append(
                "releases/ has no current %s bundle (REV%s) - run "
                "python3 tools/release_lisp.py" % (bundle["name"], revs))
        expected.append((bundle["name"], twin_regex(bundle["name"])))
    for p in sorted(RELEASES_DIR.iterdir()):
        if not p.is_file() or not DATED.match(p.name):
            if p.is_file():
                problems.append("releases/%s is not a dated twin - releases/ "
                                "holds only generated REV copies" % p.name)
            continue
        owners = [stem for stem, rx in expected if rx.fullmatch(p.name)]
        if not owners:
            problems.append(
                "releases/%s matches no versioned source - an orphan the "
                "tooling can neither regenerate nor prune" % p.name)
        elif len(owners) > 1:
            problems.append("releases/%s is claimed by %s - stems are "
                            "ambiguous" % (p.name, " and ".join(owners)))
    # two dated copies of one stem = a prune that never ran
    seen = {}
    for p in RELEASES_DIR.iterdir():
        for stem, rx in expected:
            if rx.fullmatch(p.name):
                if stem in seen:
                    problems.append(
                        "releases/ holds both %s and %s - run "
                        "python3 tools/release_lisp.py to prune"
                        % (seen[stem], p.name))
                seen[stem] = p.name
    return problems


def main(argv):
    if "--check" in argv:
        problems = check()
        for line in problems:
            print(line)
        print("release_lisp --check: %s"
              % ("%d problem(s)" % len(problems) if problems else "current"))
        return 1 if problems else 0

    date = datetime.date.today().strftime("%m%d%y")
    RELEASES_DIR.mkdir(parents=True, exist_ok=True)

    released = {s for _, s, _, _ in singles()}
    for src in sources():
        if DATED.match(src.name):
            continue
        if src.stem not in released and not any(
                src.name in b["members"] for b in BUNDLES):
            print("%s: no version banner - skipped" % src.relative_to(ROOT))

    for src, stem, revs, text in singles():
        m = VERSION.search(text)
        if m:
            dst = RELEASES_DIR / ("%s_%s_REV%s.lsp" % (stem, date, revs))
            ver = "v%s.%s" % (m.group(1), m.group(2))
        else:
            m2 = VERSION2.search(text)
            # the banner names its own date; reuse it so a re-run is a no-op
            dst = RELEASES_DIR / ("%s_%s_REV%s%s"
                                  % (stem, m2.group(1), m2.group(2),
                                     src.suffix))
            ver = "%s REV%s" % (m2.group(1), m2.group(2))
        keep = unchanged_twin(stem, revs, text)
        if keep:
            prune(stem, keep)
            print("%s (%s) -> %s (unchanged)"
                  % (src.relative_to(ROOT), ver, keep.relative_to(ROOT)))
            continue
        shutil.copyfile(src, dst)
        prune(stem, dst)
        print("%s (%s) -> %s" % (src.relative_to(ROOT), ver,
                                 dst.relative_to(ROOT)))

    for bundle in BUNDLES:
        release_bundle(bundle, date)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
