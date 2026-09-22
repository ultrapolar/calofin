#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/mirror_shared.py: a hand-typed syssave expand may not drift
from the lisp/ helper it replaces.

The grouped build swaps a tool's own x:syssave for cal:syssave, and where
the tool's list is a literal the mirror's TOOLS table types it a second
time as an 'expand'.  SPACHECK's copy kept CLAYER for ten days after
cd08238 took it out of spachk:syssave, so LAZPASS put the review's
opening layer back over the drafter's -- the bug that commit fixed --
while every twin check was green, because the mirror regenerated its own
stale text faithfully.  check_expand_lists() compares the two; this
shows it firing on a made pair, quiet on a matching one, and clean on
the real table.

Run: python3 tests/test_mirror_expand.py
"""

import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import mirror_shared  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def problems_for(source_list, typed_list):
    src = ('(defun t:syssave ()\n  (if (not t:*sysold*)\n'
           '    (setq t:*sysold* (mapcar \'(lambda (v) (cons v (getvar v)))'
           ' \'(%s)))))\n' % ' '.join('"%s"' % v for v in source_list))
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / 'T.lsp'
        p.write_text(src, encoding='utf-8')
        spec = {'src': str(p),
                'swap': {'t:syssave': 'cal:syssave'},
                'expand': {'(cal:syssave)': [
                    "(cal:syssave '(%s))"
                    % ' '.join('"%s"' % v for v in typed_list)]}}
        real = mirror_shared.TOOLS
        mirror_shared.TOOLS = {'T': spec}
        try:
            return mirror_shared.check_expand_lists()
        finally:
            mirror_shared.TOOLS = real


print("== mirror_shared: syssave expands match their source ==")
p = problems_for(["CMDECHO"], ["CMDECHO", "CLAYER"])
check("an expand that still saves what the source dropped fails",
      p and 'CLAYER' in p[0], p)
p = problems_for(["OSMODE", "CMDECHO"], ["OSMODE", "CMDECHO"])
check("an expand that matches its source passes", not p, p)
p = problems_for(["OSMODE", "CMDECHO"], ["CMDECHO", "OSMODE"])
check("the ORDER counts too: restore order is part of the promise", p, p)
real = mirror_shared.check_expand_lists()
check("the real TOOLS table is in step with lisp/", not real, real)

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall expand checks passed")
