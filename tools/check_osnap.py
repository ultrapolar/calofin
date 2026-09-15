# SPDX-License-Identifier: GPL-3.0-or-later
"""The drafter's object snaps survive every run, including the ones that fail.

OSMODE is the setting a drafter notices last and misses most.  A tool
that mutes running osnap so its own (command ...) picks land exactly
where it computed them -- which is most of the drawing tools here --
has borrowed the setting, and it owes it back on EVERY way out: the
clean one, the cancelled one and the one that throws.  Left at 0 the
failure does not look like this tool's: the drafter finds out two
commands later, when a line they drew by eye refuses to snap to an
endpoint, and nothing on screen says which routine did it.

STANDARDS section 5 puts OSMODE first in the restore table for exactly
that reason.  This script is the referee for that sentence.  Per
command, across the whole tier so a caller in one file reaches its
helper in another (POOLDEMO's restore is POOL's pool:sysrestore):

  1. a command that can change OSMODE restores it before it returns;
  2. and its *error* handler restores it too -- the handler is the only
     code that runs when the drafter hits Esc mid-prompt, and a
     restore that lives only on the success path is a restore the
     cancelled run never reaches.

Two spellings count as a restore, because both are in the tree and
both are correct:

  * DIRECT -- (setvar "OSMODE" oos), the saved value put straight back.
    The variable is a local of the command, so the handler nested
    inside it can see the value the run began with.
  * TABLE-DRIVEN -- (tool:sysrestore), a foreach over the snapshot
    tool:syssave took, whose list names OSMODE.  cal:sysrestore in the
    grouped build is the same shape.

What this cannot see, and does not claim to: whether the save runs
before the mute on every path through a command.  That is an ordering
question a reader answers, and the (if (not tool:*sysold*) ...) guard
in every syssave here is the reason it stays answered -- a second save
mid-run would snapshot the zero and "restore" it forever after.
"""

import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from callib import LISP_DIR, PARTS_DIR, ROOT, decomment, lsp_files  # noqa: E402

OSMODE = "OSMODE"


# ---------------------------------------------------------------------
#  A reader that keeps what is INSIDE a string.
#
#  check_lisp.py's parse() folds every string literal down to the token
#  '"', which is all its rules need and is why it cannot be borrowed
#  here: the whole question below is which sysvar a (setvar "..." ...)
#  names.  So this one keeps the text, as ('str', "OSMODE"), and drops
#  the quote/unquote distinction that one keeps instead -- a quoted
#  '("OSMODE" ...) table and an evaluated one mean the same thing to
#  these rules.
# ---------------------------------------------------------------------

def sexp(text):
    """TEXT as nested lists; a string literal arrives as ('str', body)."""
    top = []
    stack = []
    cur = top
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            j, buf = i + 1, []
            while j < n:
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                if text[j] == '"':
                    break
                buf.append(text[j])
                j += 1
            cur.append(("str", "".join(buf)))
            i = j + 1
        elif ch == "'":
            i += 1
        elif ch == "(":
            stack.append(cur)
            cur = []
            i += 1
        elif ch == ")":
            if stack:
                done, cur = cur, stack.pop()
                cur.append(done)
            i += 1
        elif ch in " \t\r\n":
            i += 1
        else:
            j = i
            while j < n and text[j] not in " \t\r\n()'\"":
                j += 1
            cur.append(text[i:j])
            i = j
    return top


def is_sym(x):
    return isinstance(x, str)


def is_str(x):
    return isinstance(x, tuple) and x[0] == "str"


def head(f):
    return f[0].lower() if f and is_sym(f[0]) else None


def walk(f):
    yield f
    if isinstance(f, list):
        for x in f:
            if isinstance(x, list):
                yield from walk(x)


# ---------------------------------------------------------------------
#  What a body does to OSMODE
# ---------------------------------------------------------------------

def os_writes(body):
    """Every (setvar "OSMODE" X) in BODY, as the list of X."""
    out = []
    for f in walk(body):
        if isinstance(f, list) and head(f) == "setvar" and len(f) >= 3:
            if is_str(f[1]) and f[1][1].upper() == OSMODE:
                out.append(f[2])
    return out


def mutes(body):
    """A (setvar "OSMODE" 0) -- the borrow."""
    return any(is_sym(v) and v == "0" for v in os_writes(body))


def restores_direct(body):
    """A (setvar "OSMODE" <anything but the literal 0>) -- the return."""
    return any(not (is_sym(v) and v == "0") for v in os_writes(body))


def restores_by_table(body):
    """A (setvar V ...) whose name is computed -- a sysrestore foreach."""
    for f in walk(body):
        if isinstance(f, list) and head(f) == "setvar" and len(f) >= 3:
            if not is_str(f[1]):
                return True
    return False


def names_osmode(body):
    """"OSMODE" as a table entry -- what a syssave was handed."""
    for f in walk(body):
        if isinstance(f, list):
            for x in f:
                if is_str(x) and x[1].upper() == OSMODE:
                    return True
    return False


def called(body):
    return set(f[0].lower() for f in walk(body)
               if isinstance(f, list) and f and is_sym(f[0]))


# ---------------------------------------------------------------------
#  Defuns, handlers, reachability
# ---------------------------------------------------------------------

def defuns(forms):
    """name -> [body], including defuns nested inside another."""
    out = {}
    for form in forms:
        for f in walk(form):
            if isinstance(f, list) and head(f) == "defun" and len(f) >= 2 \
                    and is_sym(f[1]):
                out.setdefault(f[1].lower(), []).append(f)
    return out


def handlers(body):
    """The *error* handlers BODY installs, both spellings STANDARDS allows."""
    out = []
    for f in walk(body):
        if not isinstance(f, list):
            continue
        h = head(f)
        if h == "defun" and len(f) >= 2 and is_sym(f[1]) \
                and f[1].lower() == "*error*":
            out.append(f)
        elif h == "setq":
            for i in range(1, len(f) - 1, 2):
                if is_sym(f[i]) and f[i].lower() == "*error*" \
                        and isinstance(f[i + 1], list):
                    out.append(f[i + 1])
    return out


def without_handlers(body):
    """BODY with its *error* handlers cut out -- the success path alone."""
    drop = [id(h) for h in handlers(body)]

    def prune(f):
        if not isinstance(f, list):
            return f
        if id(f) in drop:
            return []
        if head(f) == "setq":
            out = [f[0]]
            i = 1
            while i + 1 < len(f):
                if is_sym(f[i]) and f[i].lower() == "*error*":
                    i += 2
                    continue
                out += [f[i], prune(f[i + 1])]
                i += 2
            return out + f[i:]
        return [prune(x) for x in f]

    return prune(body)


def reach(names, dmap):
    """NAMES and everything they call, as far as this tier defines it."""
    seen, todo = set(), [n for n in names if n in dmap]
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
        for body in dmap.get(n, []):
            todo += [c for c in called(body) if c in dmap and c not in seen]
    return seen


class Tier:
    """One loadable tier, read once: every defun in it, by name."""

    def __init__(self, paths):
        self.paths = list(paths)
        self.dmap = {}
        self.per_file = {}
        for path in self.paths:
            d = defuns(sexp(decomment(path.read_text(encoding="utf-8",
                                                     errors="replace"))))
            self.per_file[path] = d
            for name, bodies in d.items():
                self.dmap.setdefault(name, []).extend(bodies)
        self.direct = set()
        self.table = set()
        self.tables = set()
        self.muters = set()
        self.risky = set()        # reaches an unwrapped (command ...)
        for name, bodies in self.dmap.items():
            for body in bodies:
                if restores_direct(body):
                    self.direct.add(name)
                if restores_by_table(body):
                    self.table.add(name)
                if names_osmode(body):
                    self.tables.add(name)
                if mutes(body):
                    self.muters.add(name)
                if unwrapped_command(body):
                    self.risky.add(name)
        # a caller of something risky is risky too
        for _ in range(len(self.dmap)):
            grew = False
            for name, bodies in self.dmap.items():
                if name in self.risky:
                    continue
                if any(c in self.risky for b in bodies for c in called(b)):
                    self.risky.add(name)
                    grew = True
            if not grew:
                break
        self.putters = set(self.direct)
        for _ in range(len(self.dmap)):
            grew = False
            for name, bodies in self.dmap.items():
                if name in self.putters:
                    continue
                if any(c in self.putters for b in bodies for c in called(b)) \
                        or (bool(self.tables) and
                            any(restores_by_table(b) for b in bodies)):
                    self.putters.add(name)
                    grew = True
            if not grew:
                break

    def puts_back(self, body, scope):
        """Does BODY restore OSMODE, directly or through the snapshot?

        SCOPE is the command's whole reach: a foreach-over-the-snapshot
        restore only counts when something in the run named OSMODE to
        the matching syssave."""
        names = reach(called(body), self.dmap)
        if restores_direct(body) or (names & self.direct):
            return True
        return bool(names & self.table) and bool(scope & self.tables)


def audit(tier):
    """One row per command that can move OSMODE."""
    rows = []
    for path in tier.paths:
        for cmd in sorted(n for n in tier.per_file[path] if n.startswith("c:")):
            for body in tier.per_file[path][cmd]:
                scope = reach(called(body), tier.dmap) | {cmd}
                if not (scope & tier.muters) and not restores_direct(body) \
                        and not (scope & tier.direct):
                    continue          # never touches OSMODE at all
                if not (scope & tier.muters) and not (scope & tier.tables):
                    continue
                hs = [h for n in scope for b in tier.dmap.get(n, [])
                      for h in handlers(b)]
                rows.append({
                    "path": path,
                    "cmd": cmd,
                    "mutes": bool(scope & tier.muters),
                    "exit": tier.puts_back(without_handlers(body), scope),
                    "handlers": len(hs),
                    "handled": any(tier.puts_back(h, scope) for h in hs),
                })
    return rows


def unwrapped_command(form):
    """A (command ...) / (command-s ...) NOT under vl-catch-all-apply.

    Inside an *error* handler this is the form that can throw.  A bare
    (command) is refused outright by 2015+ engines unless the error mode
    was pushed, and even where it is pushed it is fed to whatever command
    the Esc left PENDING -- so it can fail on the very path a handler
    exists to clean up after."""
    hits = []

    def rec(f, guarded):
        if not isinstance(f, list):
            return
        h = head(f)
        if h in ("vl-catch-all-apply", "vl-catch-all-error-p"):
            guarded = True
        if h in ("command", "command-s", "vl-cmdf") and not guarded:
            hits.append(f)
        for x in f:
            if isinstance(x, list):
                rec(x, guarded)

    rec(form, False)
    return hits


def drops_snapshot(form):
    """(setq tool:*sysold* nil) -- the run letting go of its snapshot."""
    if not isinstance(form, list) or head(form) != "setq":
        return False
    for i in range(1, len(form) - 1, 2):
        if is_sym(form[i]) and "*sys" in form[i].lower() \
                and is_sym(form[i + 1]) and form[i + 1].lower() == "nil":
            return True
    return False


def body_of(form):
    """The statements a defun or a lambda runs, in order."""
    return form[3:] if head(form) == "defun" else form[2:]


def rel(path):
    """PATH as the tree spells it, or as given when it is outside the tree."""
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path


def ordering(tier):
    """Handlers whose OSMODE restore sits BEHIND something that can throw.

    An error raised inside *error* aborts the handler: every form after
    the throwing one is skipped, the OSMODE restore included.  So the
    restore being present in the source is not the same as the restore
    running.  STANDARDS section 5 puts it first for this reason."""
    out, seen = [], set()
    for path, dmap in tier.per_file.items():
        # commands first, so a handler nested in one is reported under
        # the name a drafter types rather than under "*error*"
        for owner in sorted(dmap, key=lambda n: (not n.startswith("c:"),
                                                 n == "*error*", n)):
            bodies = dmap[owner]
            for body in bodies:
                for h in handlers(body):
                    if id(h) in seen:
                        continue
                    seen.add(id(h))
                    risk = put = None
                    for i, st in enumerate(body_of(h)):
                        if not isinstance(st, list):
                            continue
                        if risk is None and (unwrapped_command(st) or
                                             (called(st) & tier.risky)):
                            risk = (i, st)
                        if put is None and (restores_direct(st) or
                                            (called(st) & tier.putters)):
                            put = (i, st)
                    if risk and put and risk[0] < put[0]:
                        name = risk[1][0] if is_sym(risk[1][0]) else "a command"
                        out.append((path, owner, name))
    return out


def stranding(tier):
    """Restore helpers that can be left holding their snapshot.

    Every syssave here refuses to overwrite a snapshot that already
    exists -- it has to, or a second save mid-run would capture the
    ZEROED OSMODE and restore 0 for ever after.  The cost of that guard
    is that a snapshot which is never dropped silences every later run:
    they save nothing and restore the FIRST run's values, quietly undoing
    whatever the drafter has ticked in Drafting Settings since.  So the
    drop must not sit behind a form that can throw."""
    out = []
    for path, dmap in tier.per_file.items():
        for name, bodies in dmap.items():
            for body in bodies:
                put = risk = drop = None
                for i, st in enumerate(body_of(body)):
                    if not isinstance(st, list):
                        continue
                    if put is None and (restores_direct(st) or
                                        restores_by_table(st)):
                        put = i
                    if risk is None and unwrapped_command(st):
                        risk = i
                    if drop is None and drops_snapshot(st):
                        drop = i
                if None not in (put, risk, drop) and put < risk < drop:
                    out.append((path, name))
    return out


def check(tier, label):
    problems = []
    rows = audit(tier)
    for r in rows:
        where = "%s: %s" % (rel(r["path"]), r["cmd"].upper())
        if r["mutes"] and not r["exit"]:
            problems.append(
                "%s mutes OSMODE and never puts it back on the way out -- "
                "a clean run leaves the drafter with object snaps off."
                % where)
        if not r["handlers"]:
            problems.append(
                "%s changes OSMODE with no *error* handler at all: an Esc "
                "at any prompt leaves object snaps as this run set them. "
                "Write one on the STANDARDS section 5 skeleton."
                % where)
        elif not r["handled"]:
            problems.append(
                "%s changes OSMODE but its *error* handler does not restore "
                "it. Esc is the likeliest way out of a prompting command, "
                "and it is the one path the success-path restore never "
                "runs. Save the old value in a local of the command -- the "
                "handler nested inside can see it -- and put it back FIRST "
                "in the handler, or restore through the sysvar snapshot."
                % where)
    for path, owner, risk in ordering(tier):
        problems.append(
            "%s: the *error* handler in %s restores OSMODE only AFTER "
            "(%s ...), which can throw. An error inside *error* aborts the "
            "handler, so on the very path it exists for the restore never "
            "runs and the drafter is left with every object snap unticked. "
            "Move the setvars above it -- putting back a value this run "
            "captured itself cannot throw -- or wrap the risky form in "
            "vl-catch-all-apply."
            % (rel(path), owner, risk))
    for path, name in stranding(tier):
        problems.append(
            "%s: %s drops its snapshot only AFTER a bare command that can "
            "throw, so a throw leaves the snapshot standing. syssave then "
            "refuses to re-save, and every later run in the session "
            "restores THIS run's OSMODE over whatever the drafter has "
            "ticked since. Drop the snapshot before the command, or wrap "
            "the command." % (rel(path), name))
    if not problems:
        print("check_osnap: %s -- %d command%s move OSMODE, every one of "
              "them puts it back on both the clean and the failed path, "
              "ahead of anything that can throw"
              % (label, len(rows), "" if len(rows) == 1 else "s"))
    return problems


def tiers(which):
    out = []
    if which in ("lisp", "both"):
        out.append((Tier(lsp_files(LISP_DIR)), "lisp/"))
    if which in ("shared", "both"):
        out.append((Tier(lsp_files(PARTS_DIR)), "shared/parts/"))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tier", choices=("lisp", "shared", "both"),
                    default="both", help="which tier to read (default both)")
    ap.add_argument("--list", action="store_true",
                    help="print every command that moves OSMODE and how it "
                         "puts it back")
    a = ap.parse_args(argv)

    if a.list:
        for tier, label in tiers(a.tier):
            print(label)
            for r in audit(tier):
                print("  %-22s %-24s mutes=%-3s exit=%-3s handler=%s"
                      % (r["path"].name, r["cmd"].upper(),
                         "yes" if r["mutes"] else "no",
                         "yes" if r["exit"] else "NO",
                         "yes" if r["handled"] else "NO"))
        return 0

    problems = []
    for tier, label in tiers(a.tier):
        problems += check(tier, label)
    for p in problems:
        print("check_osnap: " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
