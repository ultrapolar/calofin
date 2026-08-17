# SPDX-License-Identifier: GPL-3.0-or-later
"""Create dated, numbered release copies of the root .lsp files.

Every .lsp in the repository root gets a byte-identical copy in
versions/, named NAME_MMDDYY_REV##.lsp (e.g. PERP_POINTS_081726_REV01).
The static root file keeps its stable name -- the one an APPLOAD
startup suite points at -- while the versioned name tells anyone
looking at a loaded stack exactly which iteration they have.

Running the script again on the same day bumps the REV number; a new
day starts at REV01 for that date.  Files whose newest release already
matches are skipped, so the script is safe to run any time.  The test
suite fails whenever a root .lsp differs from its newest release, which
keeps the two copies identical going forward.

Usage:  python3 tools/make_release.py
"""

import datetime
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSIONS = ROOT / "versions"


def release_key(name, base):
    """Sort key (yy, mm, dd, rev) for BASE_MMDDYY_REV##.lsp, else None."""
    m = re.fullmatch(re.escape(base) + r"_(\d{2})(\d{2})(\d{2})_REV(\d+)\.lsp",
                     name, re.IGNORECASE)
    if not m:
        return None
    mm, dd, yy, rev = (int(g) for g in m.groups())
    return (yy, mm, dd, rev)


def newest_release(base):
    """Path of the newest versioned copy of base, or None."""
    best, best_key = None, None
    if VERSIONS.is_dir():
        for f in VERSIONS.iterdir():
            key = release_key(f.name, base)
            if key and (best_key is None or key > best_key):
                best, best_key = f, key
    return best


def main():
    VERSIONS.mkdir(exist_ok=True)
    today = datetime.date.today()
    stamp = today.strftime("%m%d%y")
    for lsp in sorted(ROOT.glob("*.lsp")):
        base = lsp.stem.upper()
        newest = newest_release(base)
        if newest is not None and newest.read_bytes() == lsp.read_bytes():
            print("up to date: %s == %s" % (lsp.name, newest.name))
            continue
        same_day = [
            release_key(f.name, base)[3]
            for f in VERSIONS.iterdir()
            if release_key(f.name, base)
            and release_key(f.name, base)[:3] == (today.year % 100,
                                                  today.month, today.day)
        ]
        rev = max(same_day, default=0) + 1
        dest = VERSIONS / ("%s_%s_REV%02d.lsp" % (base, stamp, rev))
        shutil.copyfile(lsp, dest)
        print("released:   %s -> %s" % (lsp.name, dest.name))


if __name__ == "__main__":
    main()
