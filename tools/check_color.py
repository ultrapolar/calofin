#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A tool's colouring stays inside the tool.

calofin colours what it draws -- review flags, guide geometry, its own
layers -- and a drafter can retune every one of those colours (CALSET,
LAZSET, LAZTUNE).  What none of that may ever touch is the drafter's
OWN drawing environment: the current colour and the current layer
they had set before the command, which are the two settings every
line they draw AFTERWARDS is born with.  A tool that moves CECOLOR or
CLAYER to put its output where it belongs -- and most of the drawing
tools do, a dimension onto DIMENSION, a guide onto its guide layer --
has borrowed them, and the borrow ends the same way an OSMODE borrow
does: put back on the clean exit AND from the *error* handler, ahead
of anything in that handler that can throw, and only ever borrowed at
all by a tool that actually moves it.

This is tools/check_osnap.py's audit run for those two sysvars.  The
machinery is the same by construction -- check_osnap is imported and
told which sysvar to read for -- and only the question of what counts
as a MOVE and what counts as a RESTORE is this file's own.  OSMODE has
a literal 0 for the borrow and anything else for the return; CLAYER
has no such tell.  ``(setvar "CLAYER" pool:*lay-dim*)`` is a move and
``(setvar "CLAYER" oldlay)`` the return, and the difference is that
``oldlay`` was bound from ``(getvar "CLAYER")`` somewhere in the tier.
So: a value that is a symbol bound from the sysvar itself is a restore;
everything else -- a literal, a knob, a call that makes the layer -- is
a move.  The tier-wide set of saved names is an approximation that can
only ever make the check more lenient, never fail a restore that is
really there.

    python3 tools/check_color.py [--tier lisp|shared|releases|both|all]
    python3 tools/check_color.py --list

Exit 0 when every command that moves either sysvar puts it back on
both paths, 1 otherwise.
"""

import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_osnap as co  # noqa: E402
from callib import LISP_DIR, PARTS_DIR, RELEASES_DIR, decomment, lsp_files  # noqa: E402

#: the drafter's own environment: what a line drawn after the command
#: inherits.  CECOLOR is the colour, CLAYER the layer (whose colour it
#: takes when CECOLOR says BYLAYER, which is the default).
VARS = ("CECOLOR", "CLAYER")

WHAT = {"CECOLOR": "the current colour", "CLAYER": "the current layer"}


def saved_symbols(paths, var):
    """Every symbol a (setq SYM (getvar VAR)) binds anywhere in PATHS,
    lowercased -- the names a restore is written with."""
    out = set()
    for path in paths:
        forms = co.sexp(decomment(path.read_text(encoding="utf-8",
                                                 errors="replace")))
        for form in forms:
            for f in co.walk(form):
                if not (isinstance(f, list) and co.head(f) == "setq"):
                    continue
                for i in range(1, len(f) - 1, 2):
                    v = f[i + 1]
                    if co.is_sym(f[i]) and isinstance(v, list) \
                            and co.head(v) == "getvar" and len(v) >= 2 \
                            and co.is_str(v[1]) and v[1][1].upper() == var:
                        out.add(f[i].lower())
    return out


def rules(var, saved):
    """(mutes, restores_direct) for VAR, given the tier's saved names."""

    def writes(body):
        out = []
        for f in co.walk(body):
            if isinstance(f, list) and co.head(f) == "setvar" and len(f) >= 3:
                if co.is_str(f[1]) and f[1][1].upper() == var:
                    out.append(f[2])
        return out

    def is_restore(v):
        return co.is_sym(v) and v.lower() in saved

    def mutes(body):
        return any(not is_restore(v) for v in writes(body))

    def restores_direct(body):
        return any(is_restore(v) for v in writes(body))

    return mutes, restores_direct


def table_names(paths, var):
    """The files whose text carries a sysvar TABLE naming VAR -- a list
    of nothing but strings, '("CMDECHO" "CLAYER"), wherever it sits:
    inside a syssave call, or at top level as acc:*sysvars* is, where
    check_osnap's own borrowed_but_unmoved (which reads defun bodies
    alone) cannot see it."""
    out = set()
    for path in paths:
        forms = co.sexp(decomment(path.read_text(encoding="utf-8",
                                                 errors="replace")))
        for form in forms:
            for f in co.walk(form):
                if isinstance(f, list) and f and all(co.is_str(x) for x in f) \
                        and any(x[1].upper() == var for x in f):
                    out.add(path)
                    break
    return out


def unmoved(tier, var, named):
    """Commands that snapshot VAR and never change it -- check_osnap's
    borrowed_but_unmoved with the table allowed to live at top level.
    A saver is any defun named for the job (syssave / sysvars); a
    command whose reach saves, in a file whose table names VAR, and
    whose reach never moves it, is writing its opening value back over
    the drafter's on every clean exit."""
    out = []
    for path, dmap in tier.per_file.items():
        if path not in named:
            continue
        savers = {n for n in dmap if "syssave" in n or "sysvar" in n}
        if not savers:
            continue
        for cmd in sorted(n for n in dmap if n.startswith("c:")):
            if cmd.endswith("ver"):
                continue
            scope = co.reach(co.called(dmap[cmd][0]), tier.dmap) | {cmd}
            if (scope & savers) and not (scope & tier.muters):
                out.append((path, cmd))
    return out


def read_tier(paths, var):
    """A check_osnap Tier read for VAR: the module is pointed at the
    sysvar and given this file's move/restore rules before the tier is
    built, since Tier classifies every defun as it reads it."""
    saved = saved_symbols(paths, var)
    co.OSMODE = var
    co.mutes, co.restores_direct = rules(var, saved)
    return co.Tier(paths)


def tiers(which):
    out = []
    if which in ("lisp", "both", "all"):
        out.append((lsp_files(LISP_DIR), "lisp/"))
    if which in ("shared", "both", "all"):
        out.append((lsp_files(PARTS_DIR), "shared/parts/"))
    if which in ("releases", "all"):
        out.append((lsp_files(RELEASES_DIR), "releases/"))
    return out


def check(paths, label, var):
    what = WHAT[var]
    tier = read_tier(paths, var)
    problems = []
    rows = co.audit(tier)
    for r in rows:
        where = "%s: %s" % (co.rel(r["path"]), r["cmd"].upper())
        if r["mutes"] and not r["exit"]:
            problems.append(
                "%s moves %s and never puts it back on the way out -- a "
                "clean run leaves the drafter drawing on the tool's %s."
                % (where, var, what.split()[-1]))
        if not r["handlers"]:
            problems.append(
                "%s changes %s with no *error* handler at all: an Esc at "
                "any prompt leaves %s as this run set it. Write one on the "
                "STANDARDS section 5 skeleton." % (where, var, what))
        elif not r["handled"]:
            problems.append(
                "%s changes %s but its *error* handler does not restore it. "
                "Esc is the likeliest way out of a prompting command, and it "
                "is the one path the success-path restore never runs. Save "
                "the old value in a local of the command -- the handler "
                "nested inside can see it -- and put it back FIRST in the "
                "handler, or restore through the sysvar snapshot."
                % (where, var))
    for path, owner, risk in co.ordering(tier):
        problems.append(
            "%s: the *error* handler in %s restores %s only AFTER (%s ...), "
            "which can throw. An error inside *error* aborts the handler, so "
            "on the very path it exists for the restore never runs. Move the "
            "setvars above it, or wrap the risky form in vl-catch-all-apply."
            % (co.rel(path), owner, var, risk))
    for path, name in co.stranding(tier):
        problems.append(
            "%s: %s drops its snapshot only AFTER a bare command that can "
            "throw, so a throw leaves the snapshot standing and every later "
            "run restores THIS run's %s. Drop the snapshot before the "
            "command, or wrap the command." % (co.rel(path), name, var))
    for path, cmd in unmoved(tier, var, table_names(paths, var)):
        problems.append(
            "%s: %s snapshots %s but never changes it, so on the way out it "
            "writes its OPENING value back over whatever the drafter set "
            "while it was running -- on a clean exit, no error needed. "
            "Borrow only what you move: drop \"%s\" from this tool's sysvar "
            "list." % (co.rel(path), cmd.upper(), var, var))
    return rows, problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tier",
                    choices=("lisp", "shared", "releases", "both", "all"),
                    default="all")
    ap.add_argument("--list", action="store_true",
                    help="print every command that moves either sysvar "
                         "and how it puts it back")
    a = ap.parse_args(argv)

    problems = []
    for paths, label in tiers(a.tier):
        moved = 0
        for var in VARS:
            rows, probs = check(paths, label, var)
            problems += probs
            moved += len(rows)
            if a.list:
                print("%s %s" % (label, var))
                for r in rows:
                    print("  %-22s %-24s moves=%-3s exit=%-3s handler=%s"
                          % (r["path"].name, r["cmd"].upper(),
                             "yes" if r["mutes"] else "no",
                             "yes" if r["exit"] else "NO",
                             "yes" if r["handled"] else "NO"))
        if not a.list and not problems:
            print("check_color: %s -- %d command-sysvar pair%s move CECOLOR "
                  "or CLAYER, every one put back on both the clean and the "
                  "failed path, ahead of anything that can throw"
                  % (label, moved, "" if moved == 1 else "s"))
    for p in problems:
        print("check_color: " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
