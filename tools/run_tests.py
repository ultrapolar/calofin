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
#: (Empty since the SPA answer store landed - the last entry was
#: test_spa_form.py, closed by spa:*form* and its hooks.)
EXPECTED_FAILURES = {}

#: Files that dominate the wall clock (over SLOW_SECS each), with their
#: rough seconds at -j3 on the 4-CPU session box, measured from a parity
#: run.  --fast skips them for the inner loop.  The full run still takes
#: everything and submits the heaviest FIRST within each tier: handed to
#: the pool in alphabetical order, test_olauto.py (the longest file in
#: the suite) started 78th of 122 and ran on alone while the other
#: workers idled.  The figures only order the queue, so they need not be
#: exact -- but the set is kept by hand, so a run names every file
#: outside it that took longer than SLOW_SECS, and every file inside it
#: that finished in under half that, and those notes are how it stays
#: current.
SLOW_SECS = 20
SLOW = {
    "test_lazdiag_sweep.py": 25,   # 63 reports, each with THE MACHINE and its sections
    "test_olauto.py": 310, "test_fitabhd.py": 215,
    "test_pool_runtime.py": 185, "test_abhd_contingencies.py": 180,
    "test_pool_ruler.py": 150, "test_pool_form.py": 125,
    "test_dialog_actions.py": 80, "test_lazform.py": 75,
    "test_lazpanel.py": 60, "test_constellation.py": 55,
    "test_oasis.py": 45, "test_cabhd.py": 45,
    "test_ucsfix_poolspa.py": 30,
    "test_abhd_runtime.py": 25, "test_ablobf.py": 20,
}

#: A slow file gets longer before it is called hung: test_fitabhd.py ran
#: close to five minutes on a quiet box, within a factor of two of the
#: old 600 s, and a slower runner turned that into a kill.  test_olauto.py
#: ran close to eight minutes, over three quarters of TIMEOUT, before the
#: VM's dispatch got faster; it is about five now.
TIMEOUT = 600
SLOW_TIMEOUT = 1200


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
    try:
        limit = SLOW_TIMEOUT if name in SLOW else TIMEOUT
        proc = subprocess.run(
            [sys.executable, str(TESTS / name)],
            cwd=str(ROOT), env=env, timeout=limit,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        code, out = proc.returncode, proc.stdout
    except subprocess.TimeoutExpired as e:
        # a hang is a failure with a name, not a stuck runner
        code = 124
        # what the child printed before the kill arrives as BYTES even
        # under text=True -- subprocess only decodes a completed run --
        # and bytes + str raised TypeError, so one hung test took the
        # whole run down instead of being reported as the hang it was
        part = e.stdout or ""
        if isinstance(part, bytes):
            part = part.decode("utf-8", "replace")
        out = part + "\n[run_tests] killed after %ds" % limit
    return name, tier, code, time.monotonic() - t0, out


def run_tier(files, tier, jobs, overdue, early):
    """Run FILES at TIER; append (name, tier, secs) to OVERDUE for every
    file outside SLOW that took longer than SLOW_SECS, and to EARLY for
    every file in SLOW that took less than half of it."""
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        # heaviest first, so the longest files are not the last to start
        futures = [pool.submit(run_one, f, tier)
                   for f in sorted(files, key=lambda f: (-SLOW.get(f, 0), f))]
        for fut in concurrent.futures.as_completed(futures):
            name, _, code, secs, out = fut.result()
            if name not in SLOW and secs > SLOW_SECS:
                overdue.append((name, tier, secs))
            elif name in SLOW and secs < SLOW_SECS / 2:
                early.append((name, tier, secs))
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
    results, overdue, early = [], [], []
    for tier in tiers:
        print("== tier: %s (%d files, %d jobs) ==" %
              (tier, len(files), args.jobs))
        results += run_tier(files, tier, args.jobs, overdue, early)

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

    if overdue:
        print("\nnote: over %ds but not in SLOW (tools/run_tests.py): %s"
              % (SLOW_SECS, ", ".join("%s %.0fs [%s]" % (name, secs, tier)
                                      for name, tier, secs
                                      in sorted(overdue))))
    if early:
        print("\nnote: in SLOW but under %ds, so --fast skips it for "
              "nothing (tools/run_tests.py): %s"
              % (SLOW_SECS // 2, ", ".join("%s %.0fs [%s]" % (name, secs, tier)
                                            for name, tier, secs
                                            in sorted(early))))

    nxfail = sum(1 for n, _, c, _ in results
                 if c != 0 and n in EXPECTED_FAILURES)
    print("\n%d run in %.0fs: %d ok, %d expected-fail, %d bad"
          % (len(results), time.monotonic() - t0,
             len(results) - len(bad) - nxfail, nxfail, len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
