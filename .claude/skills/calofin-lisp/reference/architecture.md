# How calofin is put together

What the repo *is*, so you can guess where something lives instead of
searching for it.

## The domain

AutoLISP tools for drafting swimming pools and spas in AutoCAD. A job
starts as a **survey** — a taped set of numbered points, or a traced
drone photo — and ends as a dimensioned drawing plus a cover/liner
order. The tools automate the steps between: lay the shape out, tie the
survey points together, build the steps, dimension it, and check the
result against what the fabricator needs.

Two facts explain most of the design:

- **The drafter is the user, and the drawing outlives the command.**
  Hence the rules about giving OSMODE/CLAYER/CECOLOR back, and about a
  layer record taking a plain colour number rather than one drafter's
  theme.
- **The tools ship to shops as files, not as a service.** Hence the
  tiers: a shop pins to a dated `releases/` twin, or APPLOADs the single
  `shared/LAZPASS.lsp`.

## The tree

```
lisp/       one self-contained tool per folder.  THE SOURCE OF TRUTH.
releases/   dated REV-stamped twins of versioned lisp/ files, flat.  GENERATED.
shared/
  LAZPASS.lsp     the whole build in one file -- what you hand a drafter.  GENERATED.
  parts/
    CALOFIN-LIB.lsp     the cal: helper library.  HAND-EDITED.  Only this
                        file may define cal: symbols.  Never APPLOADed alone.
    CALOFIN-LOADER.lsp  the multi-file alternative + cal:*held-back*.  HAND-EDITED.
    <TOOL>.lsp          one twin per tool.  GENERATED (except LISPLAB.lsp).
tools/      dev tooling: the checkers, the generators, the mirror
tests/      stdlib-only Python; tests/lispvm.py is an AutoLISP interpreter
ui/         the AutoCAD palette (VB.NET), the ribbon tab (C#), and their LISP glue
blender/    Blender add-ons (DXF import/export, mesh tools)
ariel/      a Windows mouse/screen helper.  PYTHON, NOT AutoLISP -- outside
            every rule above: no twin, no release, no panel entry, no
            cal:*held-back* row.  Edit, run tests/test_ariel_anchors.py, done.
```

## What is generated from what

Nothing in this graph is hand-edited downstream of its source. Editing a
generated file loses the edit at the next regeneration, and
`check_standards.py` fails on the drift meanwhile.

```
lisp/<tool>/<TOOL>.lsp
   |-- tools/release_lisp.py       --> releases/<TOOL>_<date>_REV<n>.lsp
   |-- tools/mirror_shared.py      --> shared/parts/<TOOL>.lsp
   |                                     (swaps tool: helpers -> cal:)
   |                                   --> shared/LAZPASS.lsp
   |                                     (tools/build_shared_bundle.py)
   |
lisp/lazpanel/LAZPANEL.lsp  (captions + groups; HAND-EDITED)
   |-- tools/gen_ui_data.py    --> ui/calofin_net/Generated/CommandCatalog.g.vb
   |                           --> ui/calofin_ribbon/Generated/CommandCatalog.g.cs
   |-- tools/gen_ribbon_icons.py --> ui/calofin_ribbon/icons/  (82 PNGs)
   |-- tools/gen_knobs.py      --> lzp:*knobs* / lzp:*knobfam* back INTO LAZPANEL.lsp
   |
LAZFORM / LAZSPA / LAZSTEP chart tables
   |-- tools/gen_ui_charts.py  --> ui/calofin_net/Generated/ChartCatalog.g.vb
```

`retier.sh` runs all of these in dependency order.

## Held-back tools

A tool can be finished, have a clean twin, and still be kept **out of**
`LAZPASS.lsp`. `cal:*held-back*` in `shared/parts/CALOFIN-LOADER.lsp` is
the single source of truth, read by both `build_shared_bundle.py` and
`check_standards.py`:

| Reason | Meaning |
| --- | --- |
| `WIP` | still being worked on; moves into the manifest when it settles |
| `OMITTED` | never part of calofin |

Currently `LISPLAB.lsp` is `OMITTED`. Held files still need their twin
and still pass every other check. To ship one, move its name out of
`cal:*held-back*` into the `foreach` manifest above it and rebuild;
`tests/test_shared.py` fails if a held command leaks into the bundle.

`lisp/standards_checker/` (the deprecated acady drawing matcher) is not
carried into `shared/` at all, and is not expected to be.

## The `cal:` library

Over a hundred helpers in `shared/parts/CALOFIN-LIB.lsp`, in families:

| Family | Examples |
| --- | --- |
| asking | `askkw` `askyn` `askdist` `asktreat` `askstr` `askpoint` `ask-len` `pause` `back-word-p` |
| the length ruler | `parse-len` `spell-len` `ruler-new` `ruler-show` `draw-ruler` `ruler-off` (one block — see standards.md) |
| session state | `syssave` `sysrestore` `dimstysave` `dimstyrestore` `undobegin` `undoend` `osup` `osdown` `error-cancel-p` |
| colour & layers | `ink` `inkoverride` `bg` `ui` `themeset` `ensure-layer` `layer-usable-p` `setting` |
| vector / geometry | `v+` `v-` `v*` `dot` `mid` `perp` `unit` `dist` `angnorm` `ang-diff` `circumcenter` `bbox-ent` `bbox-ss` `proj-param` `pt-line-dist` |
| list & string | `nthcdr` `sublist` `dedupe` `trim` `pad` `zeropad2` `plural` `andjoin` `datestr` |
| survey points | `canon` `as-number` `cand-matches` `cand-nearest` |
| loops & areas | `loop-area` `inward-sign` `in-loop-p` `spikes` `block-number` |
| forms | `formanswer` `kvsplit` `kvpack` `kvhas` `kvunpack` |
| stroke font / image tiles | `imgglyph` `imgtext` `imgpline` `imgarcpts` `imgflatten` |
| output | `text` `mtext` `vlabel` `versions` |

List them live:
`grep -o '(defun cal:[a-z0-9:*+-]*' shared/parts/CALOFIN-LIB.lsp`.

**A `lisp/` file may never call, define or set a `cal:` symbol.** It
carries its own copy under its own prefix; the mirror's per-tool `swap`
map turns those into `cal:` calls in the twin.

## The mirror's table

`tools/mirror_shared.py` holds `TOOLS` — one entry per generated
twin, keyed by the **twin's file stem** (`'SQUAREUP'`, `'abhd'`,
`'AutoDim'` — the case follows the parts filename, not the folder).

```python
'SQUAREUP': {
    'src': 'lisp/squareup/SQUAREUP.lsp',
    'swap': {'sq:ink': 'cal:ink', 'sq:2d': 'cal:2d', ...},  # required
    'drop_globals': ['sq:*sysold*'],                        # required
    # optional:
    'expand': {...},      # one call becomes several
    'collapse': {...},    # several become one
    'rewrite': {...},     # rename a defun
    'replace': [...],     # prose that stops being true once a swap
                          # empties the section it describes
    'symbols': {'SQ-BACK': 'CAL-BACK'},   # the Back sentinel moves too
    'askkw_hidden': False,                # bracket-arg translation
},
```

**Only helpers whose behaviour the library reproduces exactly belong in
a swap map** — anything else stays local. Two traps the table's own
comments record:

- a helper handed to `mapcar`/`apply` is written `'name`, not `(name`;
  the swap regex covers both, but a missed one dies at the first call
  with an undefined function;
- a tool's Back sentinel (`SPA-BACK`) must move to `CAL-BACK` with the
  helper, or Back silently stops working in the grouped build while
  every other check passes.

## The panel, palette and ribbon

`lisp/lazpanel/LAZPANEL.lsp` is hand-edited and is the **registry**:
`lzp:*captions*` (command → caption) and `lzp:*groups*` (the pages).
Everything downstream is generated from it, so a tool on the panel is in
the palette and on the ribbon by construction.

Nine pages: four **job** pages — `Pool`, `Cover`, `Spa`, `Rest` — and
five **category** pages — `Layout`, `Points`, `Dimensions`,
`Converters`, `Checking`. `Rest` is *defined* as the complement of
Pool/Cover/Spa, so appending there is arithmetic; moving a tool off it
is judgement. Job pages are multi-column and show the command name
alone; category pages are plain lists and keep the caption on the
button.

DCL does not scroll in either direction — a dialog taller or wider than
the screen makes AutoCAD refuse to open it and the command dies. Pages
wrap into balanced columns at `lzp:*colbudget*`, and
`tools/check_dcl.py` drives every generator to its tallest reachable
state and measures it.

The VB palette sends a box's **TEXT** and `ui/calofin_ui/calofin.lsp`
reads it — there is deliberately **no measurement parser in the VB**.

`tools/check_netapi.py` is the opt-in check that reads AutoCAD's own
assemblies; with no `--refs` it lists what it would check and exits 0,
so `make check` does not run it. Run it on a machine that has AutoCAD.

## Failure reporting — LAZDIAG

`lisp/lazdiag/LAZDIAG.lsp`. Every command is wired to it at six call
sites (see standards.md). What it produces:

- **a report**, when something breaks: a DXF in the user's Downloads
  folder, `TOOL-version-error-date.dxf`, holding the geometry the run
  drew *and* the selection it was handed, every click labelled with the
  prompt it answered, the typed transcript, the error, the last step
  reached, and AutoCAD's `ERRNO`/`CMDNAMES`/`LASTPROMPT` and sysvars.
  Nothing is asked and the open drawing is not touched.
- **a log line from every run** — `ok` / `quit` / `FAIL` — rolling
  monthly into `<profile>\calofin\calofin-YYYY-MM.log`. `LAZLOG` shows
  it. This is what turns a failure from an event into a rate.
- **the failed tool's own self tests, run there and then**: every file
  carries `X:selftests`, a table of its helpers on known inputs,
  registered in `*calofin-selftests*`; the report runs it from inside
  `*error*` and writes one line per entry and a verdict, the log's
  `FAIL` record carries the count, and `LAZDIAG` with nothing failed
  runs every table loaded. This is what tells a wrong helper (a knob,
  a unit setting, the AutoCAD version) from a wrong answer.
- **the machine**: THE MACHINE (version, platform, units, switches,
  the ones known to break a tool flagged `!!` from `lzd:*hazards*`),
  THE LAYERS THE RUN TOUCHED with their state, WHAT THIS MACHINE HAS
  CHANGED FROM SHIPPED (LAZTUNE overrides as `= name -> text`, terms,
  theme, folders) and CALOFIN FILES LOADED with versions. The probe
  puts the units and the overrides on the VM before it replays.
- **LOST runs**: a one-line journal beside the log, written at
  `lzd:begin` and cleared at end, so a run AutoCAD crashed or was
  killed inside is logged `LOST` by the next begin.
- **LAZLAST**: the last finished run's context is kept at `lzd:end`,
  and `LAZLAST` writes it as a RUN report (`-lastrun-`) for the run
  that drew the wrong thing without failing.

Because answers are recorded **typed** (`nil`, `12.5`, `"Yes"`,
`(x y z)`), a transcript is **replayable**:
`python3 tools/probe_report.py REPORT.dxf` loads the tool at the
report's version into the test VM, reproduces the failure, then varies
one answer at a time to say which answer the failure is tied to and
where an unchecked range begins.

Three rules for anything added to LAZDIAG itself: it runs from inside
`*error*`, so **nothing may throw** (the work is under
`vl-catch-all-apply`, and re-entry is refused rather than nested);
**nothing may prompt** (that is `LAZDIAG`'s own job, from a clean
command line); and `lzd:report` goes after the sysvar restore and before
the handler's trailing `(princ)`.

## Tool families

Rough shape of the roster, for guessing where a behaviour lives:

- **Shape** — `POOL`, `SPA`, `POOLSIDE`, `LAZSIDE`, `OASIS`, `ABHD`
  family (`ABHD`/`SIMPABHD`/`ADAB`/`FITABHD`/`CABHD`/`LHD`), `LAZFORM`
- **Steps** — `LAZSTEP`, `CORNERSTP`, `HEMISTEP`, `NORMIESTEP`,
  `AUTOBEAD`, `PERPPTS`/`CPERPPTS`, `PERPMARK`
- **Survey points** — `ABFIND`, `ABMOVE`, `ABPCREATE`, `CDCREATE`,
  `CDCALLOUT`, `BPCALLOUT`, `POINTRENAMER`, `CONSTELLATION`, `LOBF`
- **Dimensions** — `AUTODIM`, `DIMSTAMP`, `CLEARDIM`, `DIMCONTEND`
  (in `lisp/dim_continue/`), `TYDRN`
- **Checking** — `CHECK`, `CCPRECHECK`, `DIMCHECK`, `COVERCHECK`,
  `LINFINCHECK`, `ABCURCHECK`, `ABPCHECK`, `SPACHECK`, `LINCHECK`,
  `LINTXTCHK`, and a `TUTORIAL*` twin for several
- **Converters** — `G2MCONV`, `SOCONV`, `VSCONV`, `XFTCONV`, `WCALST`
- **Drone / survey import** — `DRONE`, `DRONOTE`, and the `DD*` family in
  `lisp/drone_height/` (`DDFIX` `DDSET` `DDCAL` `DDINFO` `DDALT` from
  `DroneDistortion.lsp`; `DDGPS` `DDELEV` `DDTEST` from
  `DroneHeightGPS.lsp`) — note the FILE names and the COMMAND names
  differ here, which `whereis.py` resolves either way
- **Infrastructure** — `LAZPANEL` (the registry + LAZTUNE + LAZSET),
  `LAZDIAG` (failure reports + LAZLOG), `LISPLAB` (held back).
  `CALVER`, which reads the whole version roster back, is defined in
  `CALOFIN-LIB.lsp` — so it exists in the grouped build only

`python3 .claude/skills/calofin-lisp/scripts/whereis.py <NAME>` resolves
any of these to files; `lisp/<tool>/README.md` is the per-tool doc and
is far cheaper than the root `README.md`'s 143KB.
