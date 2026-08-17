#!/usr/bin/env python3
"""Cut a release of the lisp files.

Every lisp ships TWICE under two names with byte-identical contents:

    SPA.LSP                 the static name -- the one in the APPLOAD stack
    SPA_MMDDYY_REV##.LSP    the same file, named for its revision

The static name never changes, so an existing autoload keeps working.  The
versioned name says at a glance which revision is sitting in someone's
stack.  Because the two are identical, the version string travels inside
BOTH -- so a session that loaded the static name can still answer SPAVER.

    python3 tools/release.py                 # today's date, next revision
    python3 tools/release.py --rev 3         # force REV03
    python3 tools/release.py --date 081726   # force the date
    python3 tools/release.py --check         # verify, change nothing

Only ONE versioned copy is kept per lisp: cutting a new release renames
it.  Git history is the archive.
"""

import argparse
import datetime
import pathlib
import re
import sys

LISPDIR = pathlib.Path(__file__).resolve().parent.parent / "lisp"

# base file -> the lisp variable holding its version string
BASES = {
    "SPA.LSP": "spa:*version*",
    "TUTORIALSPA.LSP": "tut:*version*",
}

VERSION_RE = r'\(setq\s+{}\s+"([^"]*)"\)'


def stem(base):
    return base[: -len(".LSP")]


def versioned_paths(base):
    """Existing versioned copies of a base file."""
    pat = re.compile(rf"^{re.escape(stem(base))}_\d{{6}}_REV\d\d\.LSP$", re.I)
    return sorted(p for p in LISPDIR.iterdir() if pat.match(p.name))


def read_version(base):
    text = (LISPDIR / base).read_text()
    m = re.search(VERSION_RE.format(re.escape(BASES[base])), text)
    return m.group(1) if m else None


def check():
    """Verify each pair exists, matches byte for byte, and is named for the
    version it carries.  Returns a list of problems."""
    problems = []
    for base in BASES:
        src = LISPDIR / base
        if not src.exists():
            problems.append(f"{base}: missing")
            continue
        ver = read_version(base)
        if not ver:
            problems.append(f"{base}: no {BASES[base]} line")
            continue
        m = re.fullmatch(r"(\d{6}) REV(\d\d)", ver)
        if not m:
            problems.append(f"{base}: version {ver!r} is not 'MMDDYY REV##'")
            continue
        want = LISPDIR / f"{stem(base)}_{m.group(1)}_REV{m.group(2)}.LSP"
        copies = versioned_paths(base)
        if not copies:
            problems.append(f"{base}: no versioned copy (expected {want.name})")
            continue
        if len(copies) > 1:
            problems.append(
                f"{base}: {len(copies)} versioned copies, expected 1 "
                f"({', '.join(p.name for p in copies)})"
            )
        if want not in copies:
            problems.append(
                f"{base}: carries {ver} but its copy is "
                f"{', '.join(p.name for p in copies)}"
            )
        elif want.read_bytes() != src.read_bytes():
            problems.append(f"{base} and {want.name} have DRIFTED apart")
    return problems


def cut(date, rev):
    for base in BASES:
        src = LISPDIR / base
        text = src.read_text()
        ver = f"{date} REV{rev:02d}"
        text, n = re.subn(
            VERSION_RE.format(re.escape(BASES[base])),
            f'(setq {BASES[base]} "{ver}")',
            text,
        )
        if n != 1:
            sys.exit(f"{base}: expected one {BASES[base]} line, found {n}")
        src.write_text(text)
        for old in versioned_paths(base):
            old.unlink()
            print(f"  removed {old.name}")
        dst = LISPDIR / f"{stem(base)}_{date}_REV{rev:02d}.LSP"
        dst.write_bytes(src.read_bytes())
        print(f"  {base} -> {ver}, copied to {dst.name}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="MMDDYY (default: today)")
    ap.add_argument("--rev", type=int, help="revision number (default: next)")
    ap.add_argument("--check", action="store_true", help="verify only")
    args = ap.parse_args()

    if args.check:
        problems = check()
        for p in problems:
            print("FAIL:", p)
        if not problems:
            for base in BASES:
                print(f"ok: {base} == {versioned_paths(base)[0].name} "
                      f"({read_version(base)})")
        return 1 if problems else 0

    date = args.date or datetime.date.today().strftime("%m%d%y")
    if args.rev is not None:
        rev = args.rev
    else:
        cur = read_version("SPA.LSP") or ""
        m = re.fullmatch(r"(\d{6}) REV(\d\d)", cur)
        # same day -> bump the revision, new day -> start again at 01
        rev = int(m.group(2)) + 1 if (m and m.group(1) == date) else 1
    print(f"Cutting {date} REV{rev:02d}")
    cut(date, rev)
    problems = check()
    for p in problems:
        print("FAIL:", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
