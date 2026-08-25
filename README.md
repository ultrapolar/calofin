# calofin

Blender add-ons, AutoLISP routines, and a AutoCAD palette UI for pool/spa
drafting. This branch consolidates what used to be ~29 separate branches,
each with its own single addition on top of a shared base, into one tree
where every tool lives side by side and can be worked on from a single
checkout.

```
blender/    Blender add-ons (DXF import/export, mesh tools)
lisp/       AutoLISP tools, one self-contained file each - the source of truth
releases/   Dated REV-stamped twins of the lisp/ files, flat, GENERATED
shared/     The loaded-together build on CALOFIN-LIB.lsp (bundle GENERATED)
ui/         The Calofin AutoCAD palette (VB.NET) and its LISP glue
tools/      Dev tooling (release stamping, bundle building, static checks)
tests/      Python test suite - stdlib only, no AutoCAD or Blender needed
```

## Working in this repo

A tool exists at up to four levels of packaging, and they have to stay
in step:

| Tier | Folder | What it is | Hand-edited? |
| --- | --- | --- | --- |
| draft | `wip/` | being drafted, no version banner yet. Optional - absent until a first draft lands. | yes |
| standalone | `lisp/<tool>/` | one self-contained file, loads alone with APPLOAD. **All tool logic starts here.** | yes |
| released | `releases/` | dated `REV`-stamped twin, so a loaded routine never changes underfoot | no - generated |
| grouped | `shared/parts/` | the same tools on one helper library (`cal:`); `shared/LAZPASS.lsp` is the generated one-file build | generated for the tools in `tools/mirror_shared.py`, by hand otherwise; bundle generated |

Change a tool in `lisp/`, mirror it into `shared/parts/<FILE>.lsp` in the same
commit, then regenerate both artifacts:

```
python3 tools/mirror_shared.py <TOOL>  # the shared/parts/ twin, where generated
python3 tools/release_lisp.py          # releases/ dated twins
python3 tools/build_shared_bundle.py   # shared/LAZPASS.lsp
python3 tools/check_standards.py       # did anything drift?
```

Never hand-edit `releases/` or `shared/LAZPASS.lsp`.

A tool can be in `lisp/` and `shared/parts/` yet deliberately kept out of
the compiled bundle while it is being reworked (or for good, if it never
belonged in calofin). `cal:*held-back*` in
`shared/parts/CALOFIN-LOADER.lsp` is the list, with a reason on each
entry; the bundle header repeats it.

### Running the tests

No dependencies - `tests/lispvm.py` is a pure-Python AutoLISP
interpreter, so the suite needs only the standard library. One
environment variable matters:

| Variable | Meaning |
| --- | --- |
| `CALOFIN_LISP_ROOT` | which tier the VM tests read. **Unset means `lisp/`**, which is the default every test must keep. Set it per command, never globally - exported globally it points the whole suite at `shared/` and hides a standalone regression. |

```
python3 tests/test_pool_runtime.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_pool_runtime.py # grouped tier
python3 tests/test_shared.py     # whole grouped build + the one-file bundle
```

Running a test both ways is the parity check that keeps the two builds
honest. `CLAUDE.md` is the same contract written for Claude Code
sessions; `.claude/README.md` covers the hook and the cloud environment
panels.

## Blender add-ons (`blender/`)

Blender 4.2+ (including 5.0). Install as an extension or legacy add-on -
see each folder's own README for the exact steps.

| Add-on | Folder | What it does |
| --- | --- | --- |
| Merlin Import/Export | `blender/merlin_import_export/` | Imports AutoCAD DXFs (one object per layer, auto parent/scale/position) and exports mesh edges as a layered CAD DXF (FLOOR/WALL/STEPS objects by material) |
| Export UV Layout to DXF | `blender/uv_layout_dxf/` | Exports UV island outlines as an AutoCAD-compatible DXF, with orientation fixing and Freestyle-edge auto scaling |
| DXF Point Cloud Mesher | `blender/dxf_cloud_mesher/` | Fills imported DXF point-cloud objects with n-gon or Delaunay-triangulated faces |
| Mesh Dewrangler | `blender/mesh_dewrangler/` | Mesh simplification / topology cleanup |

## AutoLISP routines (`lisp/`)

Each tool lives under `lisp/<name>/`, with the identically-named,
dated copy of any versioned file living flat in `releases/` (see
below) - except the step routines, which release as one bundled file.
Load a routine with APPLOAD, or add it to your startup suite.
Prompt wording, keyword sets and file structure follow the shared
standard in [STANDARDS.md](STANDARDS.md) - read it before adding or
changing a routine.

| Command(s) | Folder | What it does |
| --- | --- | --- |
| `POOL`, `POOLDEMO`, `POOLVER`, `TUTORIALPOOL` | `lisp/pool/` | As-built pool plan generator - Rectangle, Oval, Grecian, L, Lazy L - from field measurements |
| `SPA`, `SPAVER`, `TUTORIALSPA` | `lisp/spa/` | Spa/hot-tub template - Rectangle, Octagon, Round |
| `OASIS`, `OASISVER` | `lisp/oasis/` | Continuous-tangent pool - centre bulge, top-right bulge, cloud (straight or rounded bottom) or kidney (true or asymmetric) - drawn live as its X/Y envelope and radii are answered, with a centre-to-corner check drawing beside it.  A `Complex` run takes a straight tangent run in place of any joiner and moves the centre hump off centre.  Finishes by offering the pool bottom - shallow and deep breaks, hopper and slope lines, ABHD's flow with the break located by a change of tangency, a nearest point or an offset in from a bound |
| `ABHD`, `ADAB`, `TUTORIALABHD`, `TUTORIALADAB` | `lisp/abhd/` | Fits a pool perimeter and bottom through surveyed points |
| `CABHD`, `CABHDVER` | `lisp/cabhd/` | ABHD's perimeter half, for a survey that runs past the pool: asks the LAST point number belonging to the pool edge and leaves everything past it out entirely.  No pool bottom |
| `LHD` | `lisp/lhd/` | Fits a top-down 2D outline (closed or open) through laser-scanned points |
| `FITABHD`, `FITABHDVER` | `lisp/fitabhd/` | Fits a TYPED pool template (Rectangle, Grecian, Roman, Oval, L, Lazy L, Round) through surveyed points -- the type says how to READ the survey, the points decide the shape: out-of-square walls, side walls that lean apart on a Roman or Oval, corner sizes, bows and caved-in arcs are all measured from the survey and kept only where it proves them, Redo to refit -- then a standard-hopper bottom |
| `BPCALLOUT` | `lisp/bpcallout/` | Rings clicked bad points with 5" circles on `FGStep` and writes a "Pt.12, Pt.15 and Pt.20 are bad" callout |
| `CDCALLOUT` | `lisp/cdcallout/` | Cross-dimensions from Pt.## to Pt.## by typed number - `CROSS DIMENSIONS` style, `DIMENSION` layer, repeat until Enter |
| `ABFIND`, `ABMOVE`, `ABFINDVER` | `lisp/abfind/` | Ties `Pt.##` back to the **A** and **B** survey stakes with a cross dim to each, then asks whether that point wants moving. `ABMOVE` takes one point and also offers every place it lands if one tape was read wrong - the moved tape swept a foot at a time, ten feet each way, plus the look-alike readings (`21'-1"` written as `21'-7"`, the 1"/11" slip, transposed feet) - drawn yellow, tagged by the tape they move (`1A`, `-3B`), each group on the dashed grey arc it sits on - and moves it to `Pt.##m`, rings the old spot with a 5" circle on `FGStep` and writes the `Moved Pt.17 B from 18'-6" to 18'-5"` note |
| `ABCDEF`, `ABCDEFVER` | `lisp/abcdef/` | Locates Excel-measured points inside rectangle corners A/B/C/D, "Z" reading order (A/B top, C/D bottom).  Two tapes place a point, three fix it, four cross-check it; a fourth tape is dropped only when leaving it out settles the other three **and** the runner-up triple is clearly worse, so a point near a diagonal keeps all four rather than discarding a good tape.  Reports per point how many tapes placed it, which, and a measured 1-99% confidence, to the command line and to a text file beside the sheet.  Plots as `ab_pt` blocks on `POINTS` and offers `ABHD` the set |
| `ALTABCDEF` | `lisp/altabcdef/` | Same idea, clockwise A→B→C→D corner order instead - kept separate from `ABCDEF` because the two conventions aren't interchangeable |
| `XYPLOT`, `XYPLOTVER` | `lisp/xyplot/` | `ABCDEF`'s sister for a survey that arrives already reduced: a sheet of X/Y offsets, one picked origin, drawn twice - graph 1 the points as given (`ab_pt` on `POINTS`, ready for `ABHD`), graph 2 the same points with the X and Y offsets dimensioned as two continuous linear chains |
| `CHECK`, `DIMARCCHECK` | `lisp/check/` | Audits dimension def-points and arc endpoints against real geometry, fixing strays |
| `DIMCHECK`, `DIMSCAN`, `DIMCHECKVER`, ... | `lisp/dimcheck/` | Guided, one-at-a-time review of dimension placement, arc-end attachment and overlapping lines, grouped by dimension style |
| `LINFINCHECK`, `LINFINSCAN`, `LITELINFINSCAN`, ... | `lisp/linfincheck/` | `DIMCHECK`'s checks plus steps & side views, wall height, the liner pattern and the title block border - the full liner-finish drawing QA. The report leads with the liner checks; the `DIMCHECK`-style findings sit in a DIMENSION AUDIT column beside it, and `LITELINFINSCAN` skips them entirely for a drawing `DIMCHECK` already went over |
| `COVERCHECK`, `COVERSCAN`, `LITECOVERSCAN`, ... | `lisp/covercheck/` | Same guided review, rules swapped for pool-cover QA; same split report, with `LITECOVERSCAN` as the cover-rules-only scan |
| `SPACHECK`, `SPACHECKSCAN`, `LITESPACHECKSCAN`, `SPACHECKRESCUE`, `SPACHECKVER`, `TUTORIALSPACHECK` | `lisp/spacheck/` | The same guided review for spa sheets: audits a drawing against what `SPA` draws - bounded outlines, the dimension roster and its notes, hinges against the block's grade/taper and the Hinge Arrangement Chart, and a title block at exactly 0.6x the liner block |
| `CCPRECHECK` | `lisp/ccprecheck/` | Walks the "Tech Flow Chart" product-type decision tree and prints a summary. Renamed from `CHECK` to resolve a name collision with `lisp/check/` |
| `LINCHECK` | `lisp/lincheck/` | Companion checklist routine, shipped alongside the flowchart walker |
| `STOCKCOVER`, `STOCKLIST`, `STOCKCOVER-CFG` | `lisp/stockcover/` | Replaces a highlighted perimeter with a stock cover drawing pulled straight out of the stock DWG folder, lined up on what was highlighted |
| `MATCHSTD`, `MATCHSTD-CFG` | `lisp/standards_checker/` | General-purpose drawing-standards matcher/checker (modular: config, cache, geometry, tolerance, UI) |
| `LINTXTCHK` | `lisp/lintxtchk/` | Places the vinyl-liner QA checklist into the drawing as text |
| `CORNERSTP`, `HEMISTEP`, `NORMIESTEP`, ... | `lisp/cornerstp/` | Corner-step layout routines for pool corners - three files here, one `STEPS` release (see below) |
| `PADDLE`, `TUTORIALPADDLE` | `lisp/paddle/` | Finds concave perimeter features and inserts pad blocks |
| `PERPPTS`, `CPERPPTS`, ... | `lisp/perp_points/` | Perpendicular offset points along a line or curve, joined with straight segments, arcs or a mix of both; asks whether the overall width has been re-measured, and has a repeat-on-the-new-polyline step |
| `AUTOBEAD`, `AUTOBEADVER`, `TUTORIALAUTOBEAD` | `lisp/autobead/` | Offsets ("beads") selected pool lines toward a clicked side |
| `DCE`, `DIMCONTEND` | `lisp/dim_continue/` | Chains `DIMCONTINUE` from a seed dimension out to every remaining feature point |
| `AUTODIM`, `FLOORDIM`, `STAIRDIM`, `AUTODIMSIDEPOV` | `lisp/autodim/` | Auto-dimensions a highlighted plan - perimeter sides and arc radii, stairs, the floor dims it asks about, two overall dims. A size that repeats is called out once and noted `Typ.` (from two equal sides, or four equal radii). Perimeter and stairs `SIDE STANDARD`, floor and overall dims `STANDARD`, anything under 12" `STANDARD INCHES`; a place that is dimensioned already is left alone. Highlight a flight of steps drawn in side view instead and `AUTODIM` recognises it and dimensions the depth of every step down the right in `STANDARD INCHES` |
| `CDCREATE`, `CDCREATEVER` | `lisp/cdcreate/` | Turns every highlighted line into a cross dimension - `CROSS DIMENSIONS` style, `DIMENSION` layer, dim line on the line, text 80% toward the right/bottom end, source line erased. A tie that is dimensioned already is left alone |
| `DRONE` | `lisp/drone/` | Drawing cleanup: text style/height, pool/spa points onto `POINTS`, spa perimeter onto `POOL`, and more in one pass |
| `WCALST` | `lisp/wcalst/` | Unrolls a curved constant-width band flat, with darts/inserts |
| `XFTCONV`, `XFTCONV-SETUP` | `lisp/xftconv/` | Cleans up Leica XFT/DXF survey imports |
| `DDGPS`, `DDALT`, `DDELEV`, ... | `lisp/drone_height/` | Computes drone height above grade and lens distortion from photo GPS/EXIF |
| `LISPLAB`, `LISPLABVER` | `lisp/lisplab/` | Learn AutoLISP, not a drafting tool: two lessons - getting things out of the drawing databases (`entget`/`ssget`/the symbol tables/dictionaries/xdata), and putting a list in order (`vl-sort` and its duplicate trap, then bubble, selection, insertion, merge and quick sort written out). Each is an outline plus a worked example that draws a sample and sorts what it reads back |
| `LAZFORM`, `LAZFORMVER` | `lisp/lazform/` | Fill a dimension chart in and draw the pool from it. Six charts - Rectangle, True Oval, Roman, both Grecians and True L Left - each the one off the paper: outline, hopper, dimension chain with its letters. The chart is the background: it is sliced into horizontal bands and each dimension's box is wedged into the band its letter sits on, so you type the number where the letter is on the paper. Corners get a dropdown each - `Square`, `Radius`, `Cut`, `NotGiven` - and the size box beside it un-greys only for `Radius` and `Cut`. Fill in what you know, leave the rest blank, press Insert: `POOL` runs and asks only for the gaps. `NA` in a box means not measured and is passed through as such; a blank box just means ask. Drawn with `vector_image` from a table of lines, so there is no artwork file to ship - see `lisp/lazform/README.md` |
| `LAZPANEL`, `LAZBUTTON`, `LAZICON`, `LAZPANELVER` | `lisp/lazpanel/` | A clickable button panel with the 51 headline drafting commands above - the zero-install GUI: the dialog is plain DCL that the file writes for itself at run time, so there is no DLL to `NETLOAD` and no second file to ship. Loading it also puts a one-button toolbar ("LazPanel", an orange hexagon it generates itself) on screen that you can drag anywhere or dock - click it to open the panel, or `LAZBUTTON` to re-summon it. Buttons are grouped Layout / Points / Dimensions / Checking (the same four group names as the VB palette); a command not loaded in this session is greyed out. A click closes the panel and runs the command exactly as if typed. Off the panel on purpose: the satellites (`TUTORIAL*`, `*VER`, `*RESCUE`, `-CFG`/`-SETUP`, `DCE`, `STOCKLIST`), the `DD*` drone-height toolset, `LISPLAB` and the deprecated matcher - see `lisp/lazpanel/README.md` |

### Going back a step

Interactive tools share one convention for backing out of a mis-typed
answer: the keyword is **Back** (type `B`), it is always shown in the
prompt's bracketed options (`[Back]`, `[Yes/No/Back/Skip rest]`, ...),
and it re-asks the previous question - re-running whatever lookup or
computation sits in between, and backing out of a sub-block (a `POOL`
measurement block, a `CCPRECHECK` branch) into the question that
opened it. **Undo** (`U`) is accepted everywhere Back is, as an
unlisted synonym. Typed prompts - notes, offsets, feet-inch
dimensions - cannot take keywords, so there Back is typed like a
value: `B`, `BACK`, `U` or `UNDO` alone, any case (the prompt says
so). The first question of a command has nothing to go back to, so it
never offers Back.

In loops that draw as they go - `PERPPTS`/`CPERPPTS` offset points,
`CORNERSTP`/`HEMISTEP`/`NORMIESTEP` treads, `ABHD`/`ADAB` slope
waypoints, `CDCALLOUT` dimensions, `ABFIND` ties - Back
also removes the
just-committed point or step (its lines and its dimensions) before
re-asking. `BPCALLOUT` works by
reselection instead: clicking a ringed point again un-rings it.
Feedback wording is shared too: `Stepping back one
<point|step|dimension>.` on the way back, `Already at the first
<point|step|dimension>.` when there is nowhere left to go.

Every interactive multi-step tool supports this, with one boundary:
AutoCAD object selections cannot take keywords, so a command whose
only remaining input is a selection (`PADDLE`, `DIMCONTEND`) has no
prompt left that could offer Back - and Back cannot be *typed at* a
selection either, though several tools (`WCALST`, `XFTCONV`,
`AUTOBEAD`, `AUTODIM`) re-open their selection when you Back at the
prompt after it. New prompts should follow this convention - it is
part of the shared prompt standard in [STANDARDS.md](STANDARDS.md).

### `ABCDEF` vs `ALTABCDEF`, and `CHECK` vs `CCPRECHECK`

Two pairs of tools collided on the same command name during
consolidation:

* **`ABCDEF`** read rectangle corners in two incompatible conventions
  depending on which branch it came from. The newer branch kept the
  name; the older, clockwise-reading version is now `ALTABCDEF`
  (including its `altabcdef:` helper namespace and `ALTABCDEF-*`
  layers, so loading both in one session is safe).
  `XYPLOT` is a third member of the family rather than a fourth
  convention: it takes X/Y offsets instead of corner distances, so
  there are no corners to disagree about.
* **`CHECK`** named two unrelated tools: a dimension/arc geometry audit
  (with `DIMCHECK`, `LINFINCHECK` and `COVERCHECK` already built
  against it) and a product-type flowchart walker. The audit kept
  `CHECK`; the flowchart walker is now `CCPRECHECK`.

### The stock cover folder

`STOCKCOVER` reads finished cover drawings out of a shared folder -
`F:\TechTeam\2022 StockCoverTech` as shipped. Set that folder before
handing the file out, by editing `*stock-folder*` at the top of
`lisp/stockcover/STOCKCOVER.lsp`; anyone can override it on their own
machine with `STOCKCOVER-CFG`, which is remembered in their AutoCAD
profile and wins over the value in the file.

You highlight the perimeter to be replaced and type the stock drawing's
short name - `5M` finds `5M_Tech.dwg`, `20M` finds `20M_Tech.dwg`
(`*stock-suffixes*` holds the `_Tech` part). Alignment is by the anchor
POINTs both sides carry - one at the bottom left, one at the top right,
in the highlighted area and in every stock drawing. The stock lands in
one move, bottom-left anchor onto bottom-left anchor, and stays exactly
there: no fit prompt, no scaling, no shuffling afterwards. A side
without anchor points falls back to its bounding-box corners, and
`STOCKCOVER` says so. If the two anchor spans disagree (the wrong file
was probably named) it prints how far off the stock is, loudly, but
still places anchored - nothing is erased until the new geometry is
placed, and the whole run is one `U`.

## Shared build (`shared/`)

The same tools built against one common helper library instead of each
embedding its own copies. APPLOAD `shared/LAZPASS.lsp` - the whole
build concatenated into one file, so there is nothing for it to find on
disk - and every command loads in one go. (`CALOFIN-LOADER.lsp` is the
multi-file alternative for when you are editing the files; it has to
locate its own folder first. Never APPLOAD `CALOFIN-LIB.lsp` alone: it
is the helper library and brings no tools with it.) The folder assumes
everything is loaded together, so a shared tool file is not loadable on
its own.
`shared/CALOFIN-LIB.lsp` holds the shared helpers under the `cal:`
prefix; the per-tool files are twins of their `lisp/` sources minus
the helpers the library now provides. See `shared/README.md` for the
helper roster and `STANDARDS.md` section 6 for the rules (including
how `lisp/` changes get mirrored here). The standalone files in
`lisp/` are unchanged and still load alone, one file at a time. The
deprecated acady matcher (`lisp/standards_checker/`) is not part of
this build and still loads on its own.

## Releases (`releases/`)

Some tools distribute a dated, REV-numbered twin of their static file
(`lisp/dimcheck/dimcheck.lsp` alongside
`releases/dimcheck_081926_REV11.lsp`) so a loaded routine never
silently changes underfoot, and a version banner in the file, its
filename, and what the command prints at startup can never disagree.
Every tool's twins live flat in `releases/` - no per-tool subfolders,
just the file itself - instead of next to the static file. Regenerate
them after any change with:

```
python3 tools/release_lisp.py
```

Not every tool uses this convention - the script says so per file
(`no version banner - skipped`) rather than guessing.

### The step bundle

The three step routines go out together, so they release as **one**
file rather than one each:

| Release | Holds |
| --- | --- |
| `releases/STEPS_081926_REV23-26-16.lsp` | `CORNERSTP.lsp` (REV23), `HEMISTEP.lsp` (REV26), `NORMIESTEP.lsp` (REV16) |

APPLOAD that single file and all six commands (`CORNERSTP`,
`HEMISTEP`, `NORMIESTEP` and their three `TUTORIAL...` walkthroughs)
come with it. The REV numbers in the filename are each member's own, in
the same order the file concatenates them, and each source is copied in
**verbatim** - so the bundle still diffs cleanly against
`lisp/cornerstp/`, and each routine prints its own version banner as it
loads. The three routines already namespace their helpers apart (`cs-`,
`hs-`, `ns-`) and guard the settings globals they share, so loading the
bundle is the same as loading the three files back to back. Members of
a bundle get no separate dated twin of their own.

Bundles are declared in `BUNDLES` at the top of `tools/release_lisp.py`;
everything else releases one file per source.

## Palette UI (`ui/`)

| | Folder | |
| --- | --- | --- |
| Calofin palette (VB.NET) | `ui/calofin_net/` | Dockable AutoCAD palette: one button per command, plus forms for POOL and SPA |
| Palette LISP glue | `ui/calofin_ui/` | `calofin.lsp` - reports which commands are actually loaded this session, so the palette can grey out the rest |

The palette needs its DLL `NETLOAD`ed on every machine. For a
button panel with nothing to install, see `lisp/lazpanel/` above:
`LAZPANEL` is pure AutoLISP, ships inside `LAZPASS.lsp`, covers the 51
headline drafting commands, and puts its own one-button toolbar on
screen to open it; the VB palette remains the richer surface (docks,
stays open while a tool runs, POOL/SPA forms).

**Status:** `lisp/pool/POOL.LSP` and `lisp/spa/SPA.LSP` are the
canonical, actively-developed versions of those tools. The receiving
end a form needs - an answer store the ask helpers read before they
prompt - now exists in POOL: `pool:*form*`, `pool:run-with-answers`,
and the hooks described under `LAZFORM` above. `tests/test_pool_form.py`
passes at both tiers because of it.

SPA has no such store yet, so `tests/test_spa_form.py` still fails on a
clean checkout - a known, open gap (the same work again on the smaller
surface), not a bug in either side.

`ui/PLAN.md` is the execution plan for closing it - what is built, what
is missing, and the day-by-day for making the forms actually drive the
routines.

## Tools (`tools/`)

| Script | What it does |
| --- | --- |
| `release_lisp.py` | Regenerates every REV twin in `releases/` from its `lisp/<tool>/` source's version banner, and the one-file `STEPS` bundle from its three sources |
| `build_shared_bundle.py` | Concatenates `shared/` into the single-file `shared/LAZPASS.lsp` |
| `mirror_shared.py` | Regenerates a `shared/parts/` twin from its `lisp/` original - drops the helpers the library provides and rewrites the call sites onto `cal:`. Table-driven, one entry per tool |
| `check_standards.py` | Cross-file check: every `lisp/` tool has a `shared/` twin **and that twin carries the same version banner**, only the library owns `cal:`, no grouped-build name collisions, no stale `releases/` twin |
| `check_lisp.py` | Static check: unbalanced parens, undefined functions/globals, unused defuns, and special forms given the wrong number of arguments (a four-argument `(if ...)` parses fine and dies at the command line) |
| `check_scope.py` | Static check: local variables used without being declared in a defun's arglist |

`tests/test_pool_runtime.py` and `tests/test_spa_runtime.py` load the
real `POOL.LSP` / `SPA.LSP` into the AutoLISP VM in `tests/lispvm.py`
and drive the commands end-to-end with scripted answers, so a change
that would die at the AutoCAD command line dies there first.

## Tests (`tests/`)

Runs without AutoCAD or Blender installed - `lispvm.py` is a pure-Python
AutoLISP interpreter good enough to execute the real `.lsp` files, and
the Blender add-ons' geometry logic lives in `bpy`-free modules so it's
unit-testable directly:

```
python3 tests/test_pool_lisp.py       # POOL geometry
python3 tests/test_pool_runtime.py    # POOL loaded and run in lispvm
python3 tests/test_tutorialpool.py    # TUTORIALPOOL, run in lispvm
python3 tests/test_oasis.py           # OASIS loaded and run in lispvm
python3 tests/test_pool_fit.py        # ABHD
python3 tests/test_cabhd.py           # CABHD, run in lispvm
python3 tests/test_laser_fit.py       # LHD
python3 tests/test_fitabhd.py         # FITABHD (engine also run in lispvm)
python3 tests/test_perp_points.py     # PERPPTS / CPERPPTS
python3 tests/test_cdcreate.py        # CDCREATE loaded and run in lispvm
python3 tests/test_bpcallout.py       # BPCALLOUT loaded and run in lispvm
python3 tests/test_cdcallout.py       # CDCALLOUT loaded and run in lispvm
python3 tests/test_abfind.py          # ABFIND / ABMOVE, run in lispvm
python3 tests/test_abcdef.py          # ABCDEF, run in lispvm against a known survey
python3 tests/test_xyplot.py          # XYPLOT, run in lispvm
python3 tests/test_autodim.py         # AUTODIM styles, dedupe, overall/step/floor dims
python3 tests/test_lisplab.py         # LISPLAB - the sorts against Python's
                                      # own sorted(), then the whole tour
python3 tests/test_stockcover.py      # STOCKCOVER, run in lispvm
python3 tests/test_covercheck_pads.py # COVERCHECK's pad hunt vs PADDLE's,
                                      # both real .lsp files in one lispvm
python3 tests/test_spacheck.py        # SPACHECK over a drawing the real SPA
                                      # just made, in the same lispvm
python3 tests/test_lazform.py         # LAZFORM - the chart drawn and checked,
                                      # and the pool it draws vs the prompts
python3 tests/test_lazpanel.py        # LAZPANEL - roster pinned to lisp/,
                                      # DCL well-formed, run with stubs,
                                      # toolbar + generated icon bytes
python3 tests/test_cornerstp_geometry.py
python3 tests/test_cornerstp_bench.py   # CORNERSTP's bench, run in lispvm
python3 tests/test_cornerstp_profile.py # the side profile all three draw
python3 tests/test_drone_height_lisp.py
python3 tests/test_addon.py           # UV layout exporter
python3 tests/test_cloud_mesher.py    # point cloud mesher
python3 tests/test_dxf_reader.py      # Merlin import
python3 tests/test_mesh_layers.py     # Merlin layered export
python3 tests/test_dewrangler.py      # mesh dewrangler
python3 tests/test_pool_form.py       # a form drives POOL and draws what
                                      # the command line draws
python3 tests/test_spa_form.py        # palette <-> SPA (currently failing, see above)
python3 tests/test_shared.py          # shared/ build - everything loads together
```

Setting `CALOFIN_LISP_ROOT=shared` reruns any VM-driven test above
against the `shared/` build instead of `lisp/`, as a behavioral-parity
check.

## License

GPL-3.0-or-later (as required for Blender add-ons).
