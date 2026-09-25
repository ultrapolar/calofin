#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""AGENTS.md, written from the skills in .claude/skills/.

The skills under `.claude/skills/` are the working subset of this
repo's ~260KB of prose, and Claude Code finds them by itself -- a
project skill needs no install.  Nothing else does.  Codex, Jules,
Aider and a growing list read `AGENTS.md` at the repo root instead, and
an agent that reads only that file must still not hand-edit a generated
tier.

So AGENTS.md is a ROUTER, not a second copy.  It carries the handful of
commands and the rules whose cost is highest if missed, and for
everything else it points at the skill that holds it.  Duplicated prose
is prose that drifts, and this tree has the scars: README.md said the
panel covered 62 commands while the panel carried 66.

It is GENERATED, for the same reason every other derived file here is.
A skill renamed, re-described, added or retired, and a script added to
`.claude/skills/calofin-lisp/scripts/`, all change what the router has
to say -- and all of it is read off the tree rather than typed:

    python3 tools/gen_agents_md.py            # write it
    python3 tools/gen_agents_md.py --check    # exit 1 if stale

`tools/check_standards.py` runs the --check, so `make check` fails on a
stale AGENTS.md the way it fails on a stale twin.

ADAPTERS is the seam.  Only AGENTS.md is emitted today; a second format
is two things and nothing else:

    def render_cursor_rule():        # 1. a zero-argument renderer
        ...                          #    returning the whole file
        return text

    ADAPTERS = {                     # 2. one entry, keyed by the path
        "AGENTS.md": render_agents_md,
        ".cursor/rules/calofin.mdc": render_cursor_rule,
    }

check() and write() iterate ADAPTERS, so the staleness check, the
"missing" diagnostic, the nested mkdir and `make check` all pick the new
format up with no other edit.  Render it from skills() and scripts() --
never from a copy of the prose -- and the whole point survives.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILLS = ROOT / ".claude" / "skills"
SCRIPTS = SKILLS / "calofin-lisp" / "scripts"

#: The trunk every session works on.  Read from CLAUDE.md rather than
#: typed, so the two cannot disagree about the branch name.
TRUNK_RE = re.compile(r"\*\*All work in this repository goes on `([^`]+)`")


def read(p):
    return pathlib.Path(p).read_text(encoding="utf-8", errors="replace")


def trunk():
    m = TRUNK_RE.search(read(ROOT / "CLAUDE.md"))
    return m.group(1) if m else "the trunk named in CLAUDE.md"


def frontmatter(path):
    """(name, description) out of a SKILL.md's YAML frontmatter.

    Deliberately not a YAML parser: the frontmatter here is two scalar
    keys, and a dependency for that would be the only one in the tree.
    """
    src = read(path)
    if not src.startswith("---"):
        return None
    end = src.find("\n---", 3)
    if end < 0:
        return None
    block = src[3:end]
    out = {}
    key = None
    for line in block.split("\n"):
        m = re.match(r"^(\w+):\s*(.*)$", line)
        if m:
            key = m.group(1)
            out[key] = m.group(2).strip()
        elif key and line.strip():                  # a wrapped value
            out[key] += " " + line.strip()
    if "name" not in out or "description" not in out:
        return None
    return out["name"], out["description"]


def headline(description):
    """The description's opening clause -- what the skill is FOR, without
    the trigger vocabulary that follows it."""
    head = description.split(" - ", 1)[0]
    head = head.split(". ", 1)[0]
    return head.rstrip(".").strip()


#: Reading order for the router's table -- the order the work actually
#: happens in, not the alphabetical one that puts "a check is red"
#: above "change a tool".  Editorial, so it is typed; a skill NOT named
#: here still appears, after these, so a new one can never be silently
#: dropped from the router.
ORDER = ("calofin-lisp", "calofin-new-tool", "calofin-checks")


def skills():
    """(name, headline, relpath, [reference files]) per skill, in ORDER
    then alphabetical for anything ORDER does not name."""
    out = []
    if not SKILLS.is_dir():
        return out
    for d in sorted(SKILLS.iterdir()):
        sk = d / "SKILL.md"
        if not sk.is_file():
            continue
        fm = frontmatter(sk)
        if not fm:
            continue
        name, desc = fm
        refs = sorted(
            str(p.relative_to(ROOT))
            for p in d.rglob("*")
            if p.is_file() and p.name != "SKILL.md"
            and p.suffix in (".md", ".lsp")
        )
        out.append((name, headline(desc), str(sk.relative_to(ROOT)), refs))
    out.sort(key=lambda s: (ORDER.index(s[0]) if s[0] in ORDER
                            else len(ORDER), s[0]))
    return out


def script_blurb(path):
    """The one-line purpose a script states about itself."""
    src = read(path)
    if path.suffix == ".py":
        m = re.search(r'^"""(.+)$', src, re.M)
        return m.group(1).strip() if m else ""
    for line in src.split("\n"):                    # a shell script
        if line.startswith("#!"):
            continue
        if line.startswith("#"):
            return line.lstrip("# ").strip()
        if line.strip():
            break
    return ""


def script_usage(path):
    """The arguments off the script's own first usage example.

    Every script here documents itself with an indented block of
    example invocations that lead with its own basename.  Taking the
    first of those keeps the router's example and the script's help in
    step without either being typed twice; a script that documents no
    example simply shows as a bare command.
    """
    name = path.name
    for line in read(path).split("\n"):
        s = line.lstrip("# \t")
        if s.startswith(name):
            args = s[len(name):].split("#", 1)[0].strip()
            return args
    return ""


def scripts():
    """(command, blurb) per script, the runner baked into the command."""
    out = []
    if not SCRIPTS.is_dir():
        return out
    for p in sorted(SCRIPTS.iterdir()):
        if p.suffix not in (".py", ".sh") or not p.is_file():
            continue
        runner = "python3" if p.suffix == ".py" else "bash"
        cmd = "%s %s" % (runner, p.relative_to(ROOT))
        usage = script_usage(p)
        out.append(((cmd + " " + usage).rstrip(), script_blurb(p)))
    return out


# ----------------------------------------------------------------------
# the AGENTS.md renderer
# ----------------------------------------------------------------------

HEADER = """<!-- GENERATED by tools/gen_agents_md.py -- do not edit by hand.
     Edit the skills under .claude/skills/ and re-run the generator;
     `make check` fails while this file is stale. -->

# AGENTS.md -- working in calofin

AutoLISP tools for pool/spa drafting, plus Blender add-ons and an
AutoCAD palette.  Python tooling is **stdlib only** -- nothing to
install, no pip, no node.

This file is a ROUTER.  The detail lives in the skill files listed
below; read the one that matches your task rather than this file plus
the 260KB of prose in `CLAUDE.md`, `STANDARDS.md` and `README.md`.
`CLAUDE.md` remains the authority where they disagree.
"""

RULES = """
## The rules whose cost is highest if missed

1. **A tool is four files, not one.**  `lisp/<tool>/<TOOL>.lsp` is the
   source of truth.  `releases/`, `shared/parts/<TOOL>.lsp` and
   `shared/LAZPASS.lsp` are **generated from it** and must be
   regenerated in the SAME commit.
2. **Never hand-edit a generated file.**  Generated:
   everything in `releases/`, `shared/LAZPASS.lsp`, every
   `shared/parts/*.lsp` except `CALOFIN-LIB.lsp`, `CALOFIN-LOADER.lsp`
   and `LISPLAB.lsp`, and everything under `ui/calofin_net/Generated/`,
   `ui/calofin_ribbon/Generated/` and `ui/calofin_ribbon/icons/`.
   Your edit will vanish at the next regeneration, and `make check`
   fails meanwhile.
3. **Only `shared/parts/CALOFIN-LIB.lsp` may define `cal:` symbols.**  A
   `lisp/` file may neither define, call nor set one -- it carries its
   own copies under its own prefix, and the mirror swaps them.
4. **Every command reports its failures.**  Five `lzd:` call sites,
   maintained by `python3 tools/check_lazdiag.py --fix`.  Write the
   `*error*` handler yourself; never hand-write the `lzd:` lines.
   And every file carries a SELF-TEST table -- `X:selftests`, its own
   helpers on known inputs, which a failure report runs on the
   drafter's machine: `--fix` writes the skeleton, you write at least
   three entries, and `python3 tools/run_selftests.py FILE --tier both`
   runs them as a report would.
5. **OSMODE, CECOLOR and CLAYER are borrowed, not taken.**  Restored on
   the clean exit AND from `*error*`, and in the handler they go first,
   ahead of anything that can throw.  Only list a sysvar in a restore
   table if the tool actually moves it.
6. **Corner treatments are `Square/Radius/Cut/NotGiven`** -- nothing
   else, anywhere.
7. **`CALOFIN_LISP_ROOT` is set per command, never exported.**
   Exporting it points the whole suite at `shared/` and hides a
   standalone regression.
8. **Nothing under `tests/` is expected to fail on a clean checkout.**
   `EXPECTED_FAILURES` in `tools/run_tests.py` is the authoritative
   list and it is empty -- so a failure is your change.
"""

PIPELINE = """
## Changing a tool

In order, in one commit:

1. Edit `lisp/<tool>/<TOOL>.lsp`.
2. Bump its version banner if it has one
   (`(setq *<tool>-version* "vN.N")`).
3. Regenerate every tier below `lisp/` (the mirror, the dated twins,
   the bundle, and every UI generator, in dependency order):
   `bash .claude/skills/calofin-lisp/scripts/retier.sh <TOOL>`
4. Check, scoped to what you touched (a third of `make check`):
   `bash .claude/skills/calofin-lisp/scripts/precheck.sh <file>`
5. Test the tier and its twin, then the full run:
   `python3 tests/test_<tool>.py`
   `CALOFIN_LISP_ROOT=shared python3 tests/test_<tool>.py`
   `make check && make test`
"""

FOOTER_CHECKS = """
## Checks and tests

| Command | What it does |
| --- | --- |
| `make check` | every static check + every generated file byte-compared against a fresh regeneration |
| `make test` | the full suite, `lisp/` tier |
| `make parity` | the full suite at BOTH tiers -- the standalone-vs-grouped drift check |
| `make fast` | the suite without the slowest files, for the inner loop |
| `make verify` | just the generated-file staleness checks |

When a check is red, read `.claude/skills/calofin-checks/SKILL.md`: it
maps each message to its cause and its fix.
"""


def render_agents_md():
    sk = skills()
    sc = scripts()
    out = [HEADER]

    out.append("\n## Read this first, by task\n")
    if sk:
        out.append("| Task | Read |")
        out.append("| --- | --- |")
        for name, head, path, _refs in sk:
            out.append("| %s | `%s` |" % (head, path))
        out.append("")
        out.append("Each of those files carries its own `description` "
                   "frontmatter saying")
        out.append("exactly when it applies, and the deeper references "
                   "beside it:")
        out.append("")
        for name, _head, _path, refs in sk:
            if refs:
                out.append("- **%s** -- %s" % (name, ", ".join(
                    "`%s`" % r for r in refs)))
        out.append("")
    else:
        out.append("_No skills found under `.claude/skills/`._\n")

    if sc:
        out.append("\n## Scripts -- run these instead of reading whole "
                   "files\n")
        out.append("Plain CLI, stdlib only, no agent-specific magic.  "
                   "From the repo root:\n")
        out.append("```bash")
        for i, (cmd, blurb) in enumerate(sc):
            if i:
                out.append("")
            out.append("# %s" % blurb)
            out.append("%s" % cmd)
        out.append("```")
        out.append("A tool file here runs past 9,000 lines.  `lspshow.py "
                   "--map FILE` gives you")
        out.append("its shape in one screen, and `lspshow.py SYMBOL "
                   "FILE` gives you the one")
        out.append("form you came for, with its comment block and line "
                   "numbers.")

    out.append(RULES.rstrip())
    out.append(PIPELINE.rstrip())
    out.append(FOOTER_CHECKS.rstrip())

    out.append("\n## Branch\n")
    out.append("All work goes on `%s`." % trunk())
    out.append("`.claude/hooks/session-start.sh` enforces it.  Push it at "
               "the end of a")
    out.append("session; if your setup named another branch, push that "
               "too, at the same")
    out.append("commit.")
    out.append("")

    return "\n".join(out)


#: The seam.  One entry per agent format we emit.  A Cursor rule file or
#: .github/copilot-instructions.md is a new entry and its renderer --
#: check() and write() below iterate this and need no other change.
ADAPTERS = {
    "AGENTS.md": render_agents_md,
}


def check():
    """Problems as a list of strings, empty when every adapter is
    current."""
    problems = []
    for rel, render in sorted(ADAPTERS.items()):
        path = ROOT / rel
        want = render()
        try:
            have = read(path)
        except OSError:
            problems.append(
                "%s is missing - the agent router was never written.  "
                "Regenerate: python3 tools/gen_agents_md.py" % rel)
            continue
        if have != want:
            problems.append(
                "%s is stale - it is not what tools/gen_agents_md.py "
                "would write now (a skill was added, renamed, "
                "re-described or given a new script).  Regenerate: "
                "python3 tools/gen_agents_md.py" % rel)
    return problems


def write():
    written = []
    for rel, render in sorted(ADAPTERS.items()):
        path = ROOT / rel
        want = render()
        path.parent.mkdir(parents=True, exist_ok=True)
        have = read(path) if path.exists() else None
        if have == want:
            print("gen_agents_md: %s unchanged" % rel)
            continue
        path.write_text(want, encoding="utf-8")
        print("gen_agents_md: wrote %s (%d lines)"
              % (rel, want.count("\n") + 1))
        written.append(rel)
    return written


def main(argv):
    ap = argparse.ArgumentParser(
        description="Write AGENTS.md from the skills in .claude/skills/.")
    ap.add_argument("--check", action="store_true",
                    help="write nothing; exit 1 if any adapter is stale")
    a = ap.parse_args(argv)

    if not skills():
        print("gen_agents_md: no skills found under .claude/skills/ - "
              "nothing to route to", file=sys.stderr)
        return 1
    if a.check:
        problems = check()
        for p in problems:
            print(p)
        if not problems:
            print("gen_agents_md: %d adapter(s) current"
                  % len(ADAPTERS))
        return 1 if problems else 0
    write()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
