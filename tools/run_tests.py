#!/usr/bin/env python3
"""Run the calofin test suite - every tests/test_*.py, in parallel.

The canonical list of tests used to be prose in four documents, and two
files had already fallen out of it.  This runner globs the directory
instead, so a new test is picked up the day it lands and nothing can be
quietly omitted.

    python3 tools/run_tests.py                 # standalone tier (lisp/)
    python3 tools/run_tests.py --tier shared   # grouped tier
    python3 tools/run_tests.py --tier both     # the full parity check
    python3 tools/run_tests.py --fast          # skip the slowest files
    python3 tools/run_tests.py -k pool         # only files matching

Each test file runs as its own process (several tests patch the VM's
module-global BUILTINS table and are not safe to share an interpreter),
with CALOFIN_LISP_ROOT set per tier - never exported globally, exactly
as CLAUDE.md warns.

EXPECTED_FAILURES holds the known-red files so the difference between
"the tree is broken" and "that gap is still open" is one line of code
instead of folklore: an expected failure failing is reported quietly,
and an expected failure PASSING fails the run until the entry is
removed.

Exit 0 only when every file lands the way the table says it should.
"""

import argparse
import concurrent.futures
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"

#: Known-red on a clean checkout, and WHY.  Remove the entry in the same
#: commit that closes the gap - a passing entry fails the run.
EXPECTED_FAILURES = {
    "test_spa_form.py": "SPA has no answer store yet (spa:*form*) - "
                        "the open half of the palette-forms work",
}

#: Files that dominate the wall clock (over ~20s each); --fast skips
#: them for the inner loop.  The full run still takes everything.
SLOW = {
    "test_fitabhd.py", "test_pool_runtime.py", "test_pool_form.py",
    "test_oasis.py", "test_cabhd.py", "test_lazform.py", "test_pool_fit.py",
}


def discover(pattern):
    files = sorted(p.name for p in TESTS.glob("test_*.py"))
    if pattern:
        files = [f for f in files if pattern in f]
    return files


def run_one(name, tier):
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env.pop("CALOFIN_LISP_ROOT", None)
    if tier == "shared":
        env["CALOFIN_LISP_ROOT"] = "shared"
    t0 = time.monotonic()
    proc = subprocess.run(
        [sys.executable, str(TESTS / name)],
        cwd=str(ROOT), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return name, tier, proc.returncode, time.monotonic() - t0, proc.stdout


def run_tier(files, tier, jobs):
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(run_one, f, tier) for f in files]
        for fut in concurrent.futures.as_completed(futures):
            name, _, code, secs, out = fut.result()
            expected = name in EXPECTED_FAILURES
            if code == 0 and not expected:
                mark = "ok  "
            elif code != 0 and expected:
                mark = "xfail"
            elif code == 0 and expected:
                mark = "XPASS"
            else:
                mark = "FAIL"
            print("  %-5s %-32s %5.1fs  [%s]" % (mark, name, secs, tier))
            results.append((name, tier, code, out))
    return results


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", choices=("lisp", "shared", "both"),
                    default="lisp")
    ap.add_argument("--fast", action="store_true",
                    help="skip the slowest files (%d of them)" % len(SLOW))
    ap.add_argument("-k", metavar="SUBSTR", default="",
                    help="only files whose name contains SUBSTR")
    ap.add_argument("-j", "--jobs", type=int,
                    default=max(2, (os.cpu_count() or 4) - 1))
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args(argv)

    files = discover(args.k)
    if args.fast:
        files = [f for f in files if f not in SLOW]
    if args.list:
        for f in files:
            print(f)
        return 0
    if not files:
        print("no test files match %r" % args.k)
        return 1

    tiers = ("lisp", "shared") if args.tier == "both" else (args.tier,)
    t0 = time.monotonic()
    results = []
    for tier in tiers:
        print("== tier: %s (%d files, %d jobs) ==" %
              (tier, len(files), args.jobs))
        results += run_tier(files, tier, args.jobs)

    bad = []
    for name, tier, code, out in results:
        expected = name in EXPECTED_FAILURES
        if code != 0 and not expected:
            bad.append(("FAIL", name, tier, out))
        elif code == 0 and expected:
            bad.append(("XPASS", name, tier,
                        "expected failure now PASSES - delete its "
                        "EXPECTED_FAILURES entry in tools/run_tests.py "
                        "(and the known-failing prose it is cited in):\n  "
                        + EXPECTED_FAILURES[name]))
    for kind, name, tier, out in bad:
        print("\n---- %s: %s [%s] ----" % (kind, name, tier))
        tail = out.strip().splitlines()[-25:]
        print("\n".join(tail))

    nxfail = sum(1 for n, _, c, _ in results
                 if c != 0 and n in EXPECTED_FAILURES)
    print("\n%d run in %.0fs: %d ok, %d expected-fail, %d bad"
          % (len(results), time.monotonic() - t0,
             len(results) - len(bad) - nxfail, nxfail, len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
