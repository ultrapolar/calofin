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
DATED = re.compile(r".*_\d{6}_REV\d+\.lsp$")
VERSION = re.compile(r'\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"')


def main():
    date = datetime.date.today().strftime("%m%d%y")
    RELEASES_DIR.mkdir(parents=True, exist_ok=True)
    for src in sorted(LISP_DIR.rglob("*.lsp")):
        if DATED.match(src.name):
            continue
        m = VERSION.search(src.read_text())
        if not m:
            print(f"{src.relative_to(ROOT)}: no version banner - skipped")
            continue
        rev = f"{m.group(1)}{m.group(2)}"
        dst = RELEASES_DIR / f"{src.stem}_{date}_REV{rev}.lsp"
        for old in RELEASES_DIR.glob(f"{src.stem}_[0-9]*_REV[0-9]*.lsp"):
            if old != dst:
                old.unlink()
                print(f"removed {old.relative_to(ROOT)}")
        shutil.copyfile(src, dst)
        print(f"{src.relative_to(ROOT)} (v{m.group(1)}.{m.group(2)}) -> {dst.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
