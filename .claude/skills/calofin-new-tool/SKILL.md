---
name: calofin-new-tool
description: Adding a brand-new AutoLISP tool or a new command to the calofin repo, or removing one - the file skeleton plus the full registration chain (mirror_shared TOOLS entry, shared/parts twin, releases, LAZPANEL caption and page, loader slot, README counts, palette tooltip and probe list, ribbon icon). Use when creating a new .lsp tool, adding a c: command to an existing one, or retiring a command. For editing an existing tool use calofin-lisp; for a failing check use calofin-checks.
---

# Adding a tool to calofin

A tool is not finished when it draws. It has to **report its failures**
and it has to be **registered** — in eight places, four of which are
derived numbers nobody should type. Almost all of it is automated; this
is the order, and the three decisions the automation refuses to make.

Read `../calofin-lisp/reference/standards.md` before writing the file,
and `../calofin-lisp/reference/architecture.md` if you are unsure which
family the tool belongs to.

---

## 1. Write the file

Start from `TEMPLATE.lsp` in this skill directory. It has been built
into a real tool, mirrored and run in the VM at **both tiers** — a clean
run, a Back and an Esc each put OSMODE and CLAYER back — and it passes
`check_lisp`, `check_scope`, `check_lazdiag`, `check_osnap`,
`check_color` and `check_perf` as written. Two checks it cannot pass
until you do something only a real tool can (section 7): `check_back`
wants a baseline line for its first question, and `test_theme` wants
its copy count bumped.

The four helpers the mirror swaps for the library — `ink` with its
`inkoverride`, `ensure-layer`, `syssave`, `sysrestore` — are the
library's own bodies under the `tool:` prefix, **not** look-alikes. That
is what makes the swap safe: the mirror may only swap a helper the
library reproduces exactly, or the two builds stop answering alike.
`ink` in particular is DIMCHECK's complete copy; most of the tree's
other copies (POOL, SPA, LOBF…) lack the per-role override and would
make your standalone build ignore a colour the drafter set in CALSET.

```bash
mkdir -p lisp/<tool>
cp .claude/skills/calofin-new-tool/TEMPLATE.lsp lisp/<tool>/<TOOL>.lsp
```

Then replace `TOOLNAME` with the command name (uppercase) and `tool:`
with the file's own unique namespace prefix — **one prefix per file,
never reused across files.**

Conventions: folder lowercase, file named after the primary command with
an uppercase stem (`lisp/squareup/SQUAREUP.lsp`). ASCII only, spaces not
tabs, 2-space indent.

**A new tool starts from the library, not from a copy of a sibling.**
Read the canonical helper rather than pasting a neighbour's drifted
copy:

```bash
python3 .claude/skills/calofin-lisp/scripts/lspshow.py cal:askkw \
        shared/parts/CALOFIN-LIB.lsp
```

In `lisp/` you embed it under your own prefix — a `lisp/` file may
never call, define or set a `cal:` symbol. The mirror swaps them back.

**Writing `" Typ."` or `"Not Given"` into the drawing?** Those are
shop terms, never literals: copy POOL.LSP's six-line `pool:term` reader
above your tunables block under your prefix, give the wording a knob
(`(setq tool:*typ-note* (tool:term "typ-note" " Typ."))`), add
`'tool:term': 'cal:term'` to your mirror entry's `swap`, add the knob
to the term's `members` in `tools/terms.py`, and re-run
`python3 tools/gen_knobs.py`. `check_terms.py` fails the bare literal.
(`calofin-lisp`'s `reference/standards.md`, "Shop terms".)

Secondary commands take fixed suffixes: `TOOLNAMEVER`,
`TUTORIALTOOLNAME`, `TOOLNAMESCAN`, `TOOLNAMERESCUE`, `TOOLNAME-CFG`.

Also write `lisp/<tool>/README.md` with the house sections:
`# NAME -- one-line purpose (AutoLISP / AutoCAD 2018+)`, `## What it does`,
`## Install & run`, `## Tunables`, `## Notes & limitations`, `## Tests`.

## 2. Add the mirror table entry

**This is the step the docs do not spell out, and nothing else works
until it is done.** Every `shared/parts/` twin except `CALOFIN-LIB.lsp`,
`CALOFIN-LOADER.lsp` and `LISPLAB.lsp` is generated from `TOOLS` in
`tools/mirror_shared.py`. With no entry there is no twin, and
`check_standards.py` fails on a `lisp/` tool that has none.

Add an entry keyed by the **twin's file stem**:

```python
'TOOLNAME': {
    'src': 'lisp/<tool>/<TOOL>.lsp',
    # Only helpers the library reproduces EXACTLY.  Anything else
    # stays local.
    'swap': {
        'tool:askkw': 'cal:askkw',
        'tool:askyn': 'cal:askyn',
        'tool:ink': 'cal:ink',
        'tool:inkoverride': 'cal:inkoverride',
        'tool:ensure-layer': 'cal:ensure-layer',
        'tool:syssave': 'cal:syssave',
        'tool:sysrestore': 'cal:sysrestore',
    },
    'drop_globals': ['tool:*sysold*'],
    # If your Back sentinel is not CAL-BACK, it must move WITH the
    # helper -- every caller tests for it, and missing this makes Back
    # silently stop working in the grouped build while every other
    # check still passes.
    'symbols': {'TOOL-BACK': 'CAL-BACK'},
    # REQUIRED for the template's askkw.  It takes HIDDEN aliases third
    # (the STANDARDS reference shape); cal:askkw takes the SHOWN bracket
    # text third.  Without this the mirror renames the call and passes
    # nil where cal:askkw strcats a string -- the grouped build dies at
    # its first keyword question, and make check stays GREEN.
    'askkw_hidden': True,
},
```

`swap` and `drop_globals` are **required keys**; `expand`, `collapse`,
`rewrite`, `replace`, `symbols` and `askkw_hidden` are optional in
general — but not for a tool built from this template.

**`askkw_hidden` is the one that bites.** Without it, this is what the
grouped build does at the first direct `askkw` call:
`strcat: bad argument type: stringp nil`. The standalone build works,
`check_lisp`, `check_scope` and `check_standards` all pass the broken
twin, and the mirror prints "0 askkw call sites translated" without
complaint. Only a shared-tier test that reaches a keyword question sees
it. With the key set, the mirror writes the bracket out
(`"Yes No"` → `"Yes/No"`) and says "N askkw call sites translated" —
check that N counts your direct `askkw` calls. The translation needs a
literal `nil` in the hidden slot; a call passing hidden aliases stops
the mirror with an error, which is the loud failure you want.

Note `cal:syssave` takes its sysvars as an argument where some tools
baked them in, and the library keeps the dimension-style save/restore in
a separate pair — if that applies, use `expand` to turn one call into
two rather than losing the second.

## 3. Wire the failure reporting

You write the `*error*` handler (the template has it). Everything else
is generated:

```bash
python3 tools/check_lazdiag.py --fix
```

It reports `<CMD> has no *error* handler to report from` if you skipped
the handler, and will not guess one — what belongs in it is editorial:
which sysvars *this* command changed, whether an undo group is open,
what it drew that has to be swept.

It also writes the **self-test table's skeleton** — `X:selftests`, just
above the load banner, registered under every command the file reports
as — and then names the file until you write at least three entries:
the tool's own helpers on known inputs, `(list "label" '(expr) expected)`
or `(list "label" '(expr))`. A failure report runs them on the drafter's
machine. Nothing in one may prompt, draw, `(command)`, `setvar`, write,
reach COM or read the drawing. Try them with
`python3 tools/run_selftests.py lisp/<tool>/<TOOL>.lsp --tier both`.

## 4. Register it

```bash
python3 tools/check_registry.py --fix
```

What `--fix` actually writes: a caption row and a `Rest`-page placement
in `LAZPANEL.lsp`, every derived count in `README.md`, and a bump to
LAZPANEL's own banner. **Everything else it only reports** — it then
lists what is still outstanding, and names the three things it will not
decide for you:

| Decision | Where | Why it is yours |
| --- | --- | --- |
| the **caption text** | `lzp:*captions*` in `lisp/lazpanel/LAZPANEL.lsp` | editorial; `test_lazpanel.py` refuses to go green on an empty one |
| the **category page** | `lzp:*groups*`, one of `Layout`/`Points`/`Dimensions`/`Converters`/`Checking` | a judgement about what the tool IS; a plausible-but-wrong placement nobody reviews is worse than a loud gap |
| the **tooltip blurb** | `ui/calofin_net/blurbs.txt` | the only palette content still typed — a missing one is reported, never invented |

Write those three and re-run `check_registry.py`.

**Three more it reports but does not write**, because they are hand-
edited files it has no codemod for:

- the **loader slot** — your twin's filename in the `foreach` manifest
  in `shared/parts/CALOFIN-LOADER.lsp` (or in `cal:*held-back*`, below);
- the **probe-list name** in `ui/calofin_ui/calofin.lsp`, which is what
  greys the palette button out when the command is not loaded;
- a **test that drives the command**. Every command must be invoked by
  some suite under `tests/`, or be excused in `UNTESTED` in
  `tools/check_registry.py` **with the reason**. Version reporters
  (`*VER`, `*VERSION`) are exempt automatically.

`python3 .claude/skills/calofin-lisp/scripts/whereis.py <TOOL>` prints
every one of these sites with its current line, so you can see at a
glance which are still missing.

`--fix` is a codemod over `LAZPANEL.lsp`, not a build step: it prints
the regeneration commands rather than running them, so it never writes
to a generated tier.

**A `Rest` placement is arithmetic; moving a tool off `Rest` is
judgement.** `Rest` is *defined* as the complement of Pool/Cover/Spa.
The job pages (`Pool`, `Cover`, `Spa`, `Rest`) are separate from the
category pages, and a tool can sit on both.

### Optionally: a ribbon glyph

Every registered tool is on the ribbon by construction, as a plain text
button. For a glyph of its own, add the name to `FEATURED` in
`tools/gen_ui_data.py` with `LARGE` (full height, glyph at 32) or
`SMALL` (an ordinary row, glyph at 16), and a glyph to `DESIGN` in
`tools/gen_ribbon_icons.py`. `make check` fails until it has one — and
fails the other way on an **orphan**, a glyph for a routine no longer
featured.

## 5. Regenerate every tier

```bash
bash .claude/skills/calofin-lisp/scripts/retier.sh TOOLNAME
```

`mirror_shared.py` → `release_lisp.py` → `build_shared_bundle.py` →
`gen_knobs.py` → `gen_ui_data.py` → `gen_ui_charts.py` →
`gen_ribbon_icons.py`, in dependency order.

## 6. Write the test

`tests/test_<tool>.py` — `tools/run_tests.py` globs the directory, so
there is no list to update. See
`../calofin-lisp/reference/testing.md` for the idiom; the tier switch at
the top of the file is mandatory, or `make parity` proves nothing.

**Drive every keyword question at the shared tier.** It is the only
thing that catches a mis-translated `askkw` (section 2). And test the
Esc path with `vm.handle_errors = True` — without it the VM never runs
your `*error*` handler, and a restore test proves nothing.

## 7. Check and test

```bash
bash .claude/skills/calofin-lisp/scripts/precheck.sh lisp/<tool>/<TOOL>.lsp
make check && make parity
```

Two failures here are expected on a new tool, and are yours to settle
rather than bugs:

- **`check_back`** names the command's first question (the template's
  `Insertion base point`). The first question of a command never offers
  Back, so accept it:
  `python3 tools/check_back.py --update-baseline`, then **read the line
  it wrote** in `tools/back_baseline.txt`. For a first question the
  reason it infers — `first question of its command or branch` — is
  already right; for anything else it is only a starting point.
- **`test_theme.py`** counts the tools whose swap map carries
  `cal:ink`, and fails its copy-count check (`the mirror says N copies exist`) the moment
  yours joins them. Bump both counts in its `COPIES` block, and the
  comment above them. The per-copy check below it is the one that
  matters — it must say your `tool:ink == cal:ink`.

`check_dcl.py` is the one to watch on a new tool: every tool not on
Pool, Cover or Spa lands on the `Rest` page, so `Rest` is the page each
new tool grows. DCL does not scroll — a page past the screen makes
AutoCAD refuse to open the dialog and the command dies where it stands.
The pages wrap into balanced columns at `lzp:*colbudget*`.

---

## Holding a new tool back from the bundle

A tool can be finished, have a clean twin, and still be kept out of
`shared/LAZPASS.lsp` — because it is mid-rework, or because it never
belongs in calofin. Add its filename to `cal:*held-back*` in
`shared/parts/CALOFIN-LOADER.lsp` with a reason:

| Reason | Meaning |
| --- | --- |
| `WIP` | still being worked on; moves into the manifest when it settles |
| `OMITTED` | never part of calofin |

Held files still need their twin and still pass every other check — they
are simply not compiled in. To ship one later, move its name out of
`cal:*held-back*` into the `foreach` manifest above it and rebuild.
`tests/test_shared.py` fails if a held command leaks into the bundle,
and reads both lists off the loader so it cannot drift.

## Removing a command

Reverse the chain, in one commit: delete the `lisp/` file (or the
`defun`), drop the `mirror_shared.TOOLS` entry, drop the twin, the
caption, the placement, the loader slot, the blurb and the probe-list
name — then `check_registry.py --fix` for the derived counts, and
`retier.sh` for the tiers. `gen_ribbon_icons.py --check` will fail on
the orphaned glyph until you remove it from `DESIGN` and `FEATURED`.

Leave `releases/` alone: dated twins are what shops pin to, and they are
history, not current state.

## Not a tool: `ariel/`

`ariel/` is a Windows mouse/screen helper in **Python**, outside every
rule above — no twin, no release, no panel caption, no palette button,
and **no `cal:*held-back*` entry either** (that list is for AutoLISP
tools kept out of the bundle; holding back something that was never a
member would claim it is one). Edit it as ordinary Python, run
`python3 tests/test_ariel_anchors.py`, done.
