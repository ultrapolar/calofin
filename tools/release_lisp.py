# SPDX-License-Identifier: GPL-3.0-or-later
"""Make dated distribution copies of the AutoLISP step routines.

Each routine lives under two names that stay byte-identical:

  CORNERSTP.lsp                 the static name - this is the one in the
                                startup suite / APPLOAD stack, so loading
                                never has to chase a filename
  CORNERSTP_MMDDYY_REV22.lsp    the dated copy - its name says exactly
                                which iteration someone has in their stack

The REV number is the file's own version banner with the dot dropped
(v2.2 -> REV22), so the filename, the load banner, and the banner the
command prints at start can never disagree.  The date is the day the
snapshot was made.

Run this after any change to a .lsp file:

    python3 tools/release_lisp.py

It re-reads each static file's version, writes the new dated copy, and
removes the previous dated copy of that routine (git history keeps the
old ones).
"""

import datetime
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATED = re.compile(r".*_\d{6}_REV\d+\.lsp$")
VERSION = re.compile(r'\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"')


def main():
    date = datetime.date.today().strftime("%m%d%y")
    for src in sorted(ROOT.glob("*.lsp")):
        if DATED.match(src.name):
            continue
        m = VERSION.search(src.read_text())
        if not m:
            print(f"{src.name}: no version banner - skipped")
            continue
        rev = f"{m.group(1)}{m.group(2)}"
        dst = ROOT / f"{src.stem}_{date}_REV{rev}.lsp"
        for old in ROOT.glob(f"{src.stem}_[0-9]*_REV[0-9]*.lsp"):
            if old != dst:
                old.unlink()
                print(f"removed {old.name}")
        shutil.copyfile(src, dst)
        print(f"{src.name} (v{m.group(1)}.{m.group(2)}) -> {dst.name}")


if __name__ == "__main__":
    main()
