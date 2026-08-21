#!/usr/bin/env python3
"""Standards check: does the tree still hold the shape STANDARDS.md describes?

The other two checkers read one .lsp at a time -- parens, scope, names.
This one checks the things that only go wrong BETWEEN files, which is
where the tree drifts:

  * every tool in the single-file tier has a twin in the grouped tier,
  * only the library owns the cal: namespace,
  * nothing in the grouped tier collides when it all loads at once,
  * every command survives the trip from one tier to the other,
  * the loader actually lists what is in its own folder,
  * a versioned file's dated twin in releases/ is not stale.

Run it with no arguments to check the whole tree:

    python3 tools/check_standards.py

Exits 0 when clean, 1 when something drifted, and prints one line per
problem saying what to do about it.  The session-start hook runs it, so
a drift shows up when a session opens rather than in review.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

#: The tiers, in the order a tool moves through them.  wip/ is the
#: bench: files being drafted, no version banner, nothing generated
#: from them yet.  It is optional -- absent until the first draft
#: lands -- so every check below skips it when it does not exist.
WIP_DIR = ROOT / "wip"
LISP_DIR = ROOT / "lisp"
RELEASES_DIR = ROOT / "releases"
SHARED_DIR = ROOT / "shared"
#: the member files; shared/ itself holds only the generated bundle
PARTS_DIR = SHARED_DIR / "parts"

#: Not carried into the grouped tier: the acady drawing-standards
#: matcher is a deprecated project, so lisp/standards_checker/ has no
#: twin and its commands are not expected in shared/.
UNMIRRORED_DIRS = {"standards_checker"}


def mirrored(p):
    """False for a source the grouped tier deliberately does not carry."""
    return not (set(p.parts) & UNMIRRORED_DIRS)

#: Generated, and a copy of everything else here, so the per-file rules
#: below do not apply to it -- it is checked as a whole instead.
GENERATED = {"CALOFIN-ALL.lsp"}

#: Files that may define cal: symbols.  The loader needs a couple of
#: private cal-- helpers and cal:*dir* to find its siblings.
LIBRARY_FILES = {"CALOFIN-LIB.lsp", "CALOFIN-LOADER.lsp"}

#: Released as one concatenated file, so they have no twin of their own.
BUNDLED = {"CORNERSTP.lsp", "HEMISTEP.lsp", "NORMIESTEP.lsp"}

VERSION = re.compile(r'\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"')
VERSION2 = re.compile(r'\*version\*\s+"(\d{6}) REV(\d{2})"')
DEFUN = re.compile(r"^\(defun\s+([^\s()]+)", re.MULTILINE)
COMMAND = re.compile(r"^\(defun\s+[cC]:([^\s()]+)", re.MULTILINE)
CAL_SYM = re.compile(r"^\((?:defun|setq)\s+(cal:[^\s()]+)", re.MULTILINE)
HELD = re.compile(r'\("([^"]+)"\s*\.\s*"(WIP|OMITTED)"\)')


def held_back():
    """Files the loader deliberately keeps out of the build, name -> reason.

    A held file still has to exist and still has to be a clean twin -- it
    is simply not compiled in yet, so the bundle and loader checks skip
    it instead of reporting it as drift."""
    loader = PARTS_DIR / "CALOFIN-LOADER.lsp"
    if not loader.is_file():
        return {}
    return dict(HELD.findall(read(loader)))


def lsp_files(d):
    """Every .lsp under d, in a stable order, whatever the extension case."""
    if not d.is_dir():
        return []
    return sorted(p for p in d.rglob("*")
                  if p.is_file() and p.suffix.lower() == ".lsp")


def shared_members():
    """The hand-written files in shared/parts/."""
    return [p for p in lsp_files(PARTS_DIR) if p.name not in GENERATED]


def read(p):
    return p.read_text(encoding="utf-8", errors="replace")


def rev_of(text):
    """The REV a file's own version banner asks to be stamped with."""
    m = VERSION.search(text)
    if m:
        return "REV%s%s" % (m.group(1), m.group(2))
    m = VERSION2.search(text)
    if m:
        return "REV%s" % m.group(2)
    return None


def check_twins(problems):
    """Every single-file tool is mirrored in the grouped tier."""
    if not SHARED_DIR.is_dir():
        problems.append("shared/ is missing - the grouped tier is gone")
        return
    have = {p.name for p in shared_members()}
    for p in lsp_files(LISP_DIR):
        if not mirrored(p):
            continue
        want = p.stem + ".lsp"
        if want not in have:
            problems.append(
                "%s has no shared twin - add shared/parts/%s calling the "
                "cal: helpers, per CLAUDE.md" % (p.relative_to(ROOT), want))
    for name in ("CALOFIN-LIB.lsp", "CALOFIN-LOADER.lsp"):
        if name not in have:
            problems.append("shared/parts/%s is missing" % name)
    check_twins_current(problems)


def check_twins_current(problems):
    """...and mirrors the version it was mirrored FROM.  Presence alone
    says nothing: a twin left behind while lisp/ moved on still loads,
    still passes every one-file check, and quietly gives the grouped
    build different behaviour from the standalone one."""
    byname = {p.name: p for p in shared_members()}
    for p in lsp_files(LISP_DIR):
        twin = byname.get(p.stem + ".lsp")
        if twin is None:
            continue
        a, b = rev_of(read(p)), rev_of(read(twin))
        if a and b and a != b:
            problems.append(
                "shared/parts/%s is at %s but %s is at %s - mirror the "
                "change into the twin, per CLAUDE.md"
                % (twin.name, b, p.relative_to(ROOT), a))


def check_library_owns_cal(problems):
    """Only the library defines cal: - a tool defining one has forked it."""
    for p in shared_members():
        if p.name in LIBRARY_FILES:
            continue
        for sym in set(CAL_SYM.findall(read(p))):
            problems.append(
                "shared/parts/%s defines %s - the cal: namespace belongs "
                "to CALOFIN-LIB.lsp" % (p.name, sym))


def check_no_collisions(problems):
    """The grouped tier loads as one session, so no name may repeat."""
    owner = {}
    for p in shared_members():
        for name in set(DEFUN.findall(read(p))):
            if name.lower() == "*error*":
                continue          # every command nests its own, localized
            first = owner.get(name.lower())
            if first:
                problems.append(
                    "%s is defined in both shared/parts/%s and "
                    "shared/parts/%s - one wins when they load together"
                    % (name, first, p.name))
            else:
                owner[name.lower()] = p.name


def check_command_parity(problems):
    """No command may be lost on the way into the grouped tier."""
    grouped = set()
    for p in shared_members():
        grouped.update(c.upper() for c in COMMAND.findall(read(p)))
    # a held tool still has its twin, so its commands are counted here
    for p in lisp_files_with_commands():
        for cmd in COMMAND.findall(read(p)):
            if cmd.upper() not in grouped:
                problems.append(
                    "%s defines %s, which no shared/ file does" %
                    (p.relative_to(ROOT), cmd.upper()))


def lisp_files_with_commands():
    return [p for p in lsp_files(LISP_DIR) if mirrored(p)]


def check_loader_lists_everything(problems):
    """A file the loader forgets is a file nobody loads."""
    loader = PARTS_DIR / "CALOFIN-LOADER.lsp"
    if not loader.is_file():
        return
    listed = read(loader)
    held = held_back()
    for p in shared_members():
        if p.name == "CALOFIN-LOADER.lsp" or p.name in held:
            continue
        if ('"%s"' % p.name) not in listed:
            problems.append(
                "shared/parts/%s is not listed in CALOFIN-LOADER.lsp, so "
                "loading the folder skips it" % p.name)


def check_release_twins(problems):
    """A versioned file whose dated twin is behind means a forgotten run."""
    if not RELEASES_DIR.is_dir():
        return
    released = [p.name for p in RELEASES_DIR.iterdir() if p.is_file()]
    for p in lsp_files(LISP_DIR):
        if p.name in BUNDLED:
            continue                       # released as the STEPS bundle
        rev = rev_of(read(p))
        if not rev:
            continue                       # no banner, nothing to release
        stem = p.stem.lower()
        want = "%s.lsp" % rev.lower()
        if not any(r.lower().startswith(stem + "_") and r.lower().endswith(want)
                   for r in released):
            problems.append(
                "%s is at %s with no matching twin in releases/ - run "
                "python3 tools/release_lisp.py" % (p.relative_to(ROOT), rev))


def check_bundle_current(problems):
    """The one-file bundle carries exactly today's members."""
    bundle = SHARED_DIR / "CALOFIN-ALL.lsp"
    if not bundle.is_file():
        problems.append(
            "shared/CALOFIN-ALL.lsp is missing - run "
            "python3 tools/build_shared_bundle.py")
        return
    text = read(bundle)
    held = held_back()
    for p in shared_members():
        if p.name == "CALOFIN-LOADER.lsp" or p.name in held:
            continue                # no loader, and held files are not in
        if (";;; >>> %s" % p.name) not in text:
            problems.append(
                "shared/parts/%s is not in CALOFIN-ALL.lsp - rebuild it with "
                "python3 tools/build_shared_bundle.py" % p.name)


def check_wip(problems):
    """The bench tier, when it exists: drafts only, nothing stamped."""
    for p in lsp_files(WIP_DIR):
        if re.match(r".*_\d{6}_REV[\d-]+\.lsp$", p.name, re.IGNORECASE):
            problems.append(
                "wip/%s looks like a dated release - those belong in "
                "releases/" % p.name)


def main():
    problems = []
    check_twins(problems)
    check_library_owns_cal(problems)
    check_no_collisions(problems)
    check_command_parity(problems)
    check_loader_lists_everything(problems)
    check_release_twins(problems)
    check_bundle_current(problems)
    check_wip(problems)

    tiers = ["lisp/ %d" % len(lsp_files(LISP_DIR)),
             "shared/parts/ %d" % len(shared_members())]
    if WIP_DIR.is_dir():
        tiers.insert(0, "wip/ %d" % len(lsp_files(WIP_DIR)))
    print("standards: " + ", ".join(tiers) + " files")
    held = held_back()
    if held:
        wip = sorted(n for n, w in held.items() if w == "WIP")
        omit = sorted(n for n, w in held.items() if w == "OMITTED")
        if wip:
            print("standards: held back (WIP): " + ", ".join(wip))
        if omit:
            print("standards: held back (OMITTED): " + ", ".join(omit))

    if problems:
        print("\n%d problem(s):" % len(problems))
        for line in problems:
            print("  - " + line)
        return 1
    print("standards: tiers in step, cal: namespace clean, no collisions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
