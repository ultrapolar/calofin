# calofin

Blender add-ons, AutoLISP routines, and a AutoCAD palette UI for pool/spa
drafting. This branch consolidates what used to be ~29 separate branches,
each with its own single addition on top of a shared base, into one tree
where every tool lives side by side and can be worked on from a single
checkout.

```
blender/    Blender add-ons (DXF import/export, mesh tools)
lisp/       AutoLISP routines, current static-named files
releases/   Dated REV-stamped twins of the lisp/ files, flat (no subfolders)
ui/         The Calofin AutoCAD palette (VB.NET) and its LISP glue
tools/      Shared dev tooling (release stamping, static checks)
tests/      Python test suite - runs without AutoCAD or Blender installed
```

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
below). Load a routine with APPLOAD, or add it to your startup suite.

| Command(s) | Folder | What it does |
| --- | --- | --- |
| `POOL`, `POOLDEMO` | `lisp/pool/` | As-built pool plan generator - Rectangle, Oval, Grecian, L, Lazy L - from field measurements |
| `SPA`, `SPAVER`, `TUTORIALSPA` | `lisp/spa/` | Spa/hot-tub template - Rectangle, Octagon, Round |
| `ABHD`, `ADAB`, `TUTORIALABHD`, `TUTORIALADAB` | `lisp/abhd/` | Fits a pool perimeter and bottom through surveyed points |
| `LHD` | `lisp/lhd/` | Fits a top-down 2D outline (closed or open) through laser-scanned points |
| `ABCDEF` | `lisp/abcdef/` | Plots Excel-measured points into rectangle corners A/B/C/D, "Z" reading order (A/B top, C/D bottom) |
| `ALTABCDEF` | `lisp/altabcdef/` | Same idea, clockwise A→B→C→D corner order instead - kept separate from `ABCDEF` because the two conventions aren't interchangeable |
| `CHECK`, `DIMARCCHECK` | `lisp/check/` | Audits dimension def-points and arc endpoints against real geometry, fixing strays |
| `DIMCHECK`, `DIMSCAN`, `DIMCHECKVER`, ... | `lisp/dimcheck/` | Guided, one-at-a-time dimension/arc QA review, grouped by dimension style |
| `COVERCHECK`, `COVERSCAN`, ... | `lisp/covercheck/` | Same guided review, rules swapped for pool-cover QA |
| `CCPRECHECK` | `lisp/ccprecheck/` | Walks the "Tech Flow Chart" product-type decision tree and prints a summary. Renamed from `CHECK` to resolve a name collision with `lisp/check/` |
| `LINCHECK` | `lisp/lincheck/` | Companion checklist routine, shipped alongside the flowchart walker |
| `STOCKCOVER`, `STOCKLIST`, `STOCKCOVER-CFG` | `lisp/stockcover/` | Replaces a highlighted perimeter with a stock cover drawing pulled straight out of the stock DWG folder, lined up on what was highlighted |
| `MATCHSTD`, `MATCHSTD-CFG` | `lisp/standards_checker/` | General-purpose drawing-standards matcher/checker (modular: config, cache, geometry, tolerance, UI) |
| `LINTXTCHK` | `lisp/lintxtchk/` | Places the vinyl-liner QA checklist into the drawing as text |
| `CORNERSTP`, `HEMISTEP`, `NORMIESTEP`, ... | `lisp/cornerstp/` | Corner-step layout routines for pool corners |
| `PADDLE`, `TUTORIALPADDLE` | `lisp/paddle/` | Finds concave perimeter features and inserts pad blocks |
| `PERPPTS`, `CPERPPTS`, ... | `lisp/perp_points/` | Perpendicular offset points along a line or curve, with a repeat-on-the-new-polyline step |
| `AUTOBEAD`, `AUTOBEADVER`, `TUTORIALAUTOBEAD` | `lisp/autobead/` | Offsets ("beads") selected pool lines toward a clicked side |
| `DCE`, `DIMCONTEND` | `lisp/dim_continue/` | Chains `DIMCONTINUE` from a seed dimension out to every remaining feature point |
| `AUTODIM`, `FLOORDIM`, `STAIRDIM`, `AUTODIMSIDEPOV` | `lisp/autodim/` | Auto-dimensions a highlighted plan, then its stairs |
| `TYDRN` | `lisp/tydrn/` | Drawing cleanup: text style/height, pool-point elevations, and more in one pass |
| `WCALST` | `lisp/wcalst/` | Unrolls a curved constant-width band flat, with darts/inserts |
| `XFTCONV`, `XFTCONV-SETUP` | `lisp/xftconv/` | Cleans up Leica XFT/DXF survey imports |
| `DDGPS`, `DDALT`, `DDELEV`, ... | `lisp/drone_height/` | Computes drone height above grade and lens distortion from photo GPS/EXIF |

### `ABCDEF` vs `ALTABCDEF`, and `CHECK` vs `CCPRECHECK`

Two pairs of tools collided on the same command name during
consolidation:

* **`ABCDEF`** read rectangle corners in two incompatible conventions
  depending on which branch it came from. The newer branch kept the
  name; the older, clockwise-reading version is now `ALTABCDEF`
  (including its `altabcdef:` helper namespace and `ALTABCDEF-*`
  layers, so loading both in one session is safe).
* **`CHECK`** named two unrelated tools: a dimension/arc geometry audit
  (with `DIMCHECK` and `COVERCHECK` already built against it) and a
  product-type flowchart walker. The audit kept `CHECK`; the flowchart
  walker is now `CCPRECHECK`.

### The stock cover folder

`STOCKCOVER` reads finished cover drawings out of a shared folder -
`F:\TechTeam\2022 StockCoverTech` as shipped. Set that folder before
handing the file out, by editing `*stock-folder*` at the top of
`lisp/stockcover/STOCKCOVER.lsp`; anyone can override it on their own
machine with `STOCKCOVER-CFG`, which is remembered in their AutoCAD
profile and wins over the value in the file.

You highlight the perimeter to be replaced and type the stock drawing's
short name - `5M` finds `5M_Tech.dwg`, `20M` finds `20M_Tech.dwg`
(`*stock-suffixes*` holds the `_Tech` part). The stock geometry is
centred on what you highlighted. The two perimeters are meant to be the
same shape and size, so when they are, it is dropped in untouched; when
they are not, `STOCKCOVER` prints both sizes and asks before scaling.
Nothing is erased until the new geometry is placed, and the whole run is
one `U`.

`STOCKCOVER` measures everything a stock DWG contains, so a stock file
is expected to hold the cover geometry and nothing else - no border, no
title block, no notes parked off to one side.

## Releases (`releases/`)

Some tools distribute a dated, REV-numbered twin of their static file
(`lisp/cornerstp/CORNERSTP.lsp` alongside
`releases/CORNERSTP_081726_REV22.lsp`) so a loaded routine never
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

## Palette UI (`ui/`)

| | Folder | |
| --- | --- | --- |
| Calofin palette (VB.NET) | `ui/calofin_net/` | Dockable AutoCAD palette: one button per command, plus forms for POOL and SPA |
| Palette LISP glue | `ui/calofin_ui/` | `calofin.lsp` - reports which commands are actually loaded this session, so the palette can grey out the rest |

**Status:** `lisp/pool/POOL.LSP` and `lisp/spa/SPA.LSP` are the
canonical, actively-developed versions of those tools. The palette's
`PoolFormView`/`SpaFormView` were built against an earlier fork of both
with a different prompt sequence, so `tests/test_pool_form.py` and
`tests/test_spa_form.py` currently fail - that's a known, open gap
(reconciling the palette's `LispBridge` with the canonical POOL/SPA),
not a bug in either side.

## Tools (`tools/`)

| Script | What it does |
| --- | --- |
| `release_lisp.py` | Regenerates every REV twin in `releases/` from its `lisp/<tool>/` source's version banner |
| `check_lisp.py` | Static check: unbalanced parens, undefined functions/globals, unused defuns |
| `check_scope.py` | Static check: local variables used without being declared in a defun's arglist |

## Tests (`tests/`)

Runs without AutoCAD or Blender installed - `lispvm.py` is a pure-Python
AutoLISP interpreter good enough to execute the real `.lsp` files, and
the Blender add-ons' geometry logic lives in `bpy`-free modules so it's
unit-testable directly:

```
python3 tests/test_pool_lisp.py       # POOL geometry
python3 tests/test_pool_runtime.py    # POOL loaded and run in lispvm
python3 tests/test_pool_fit.py        # ABHD
python3 tests/test_laser_fit.py       # LHD
python3 tests/test_perp_points.py     # PERPPTS / CPERPPTS
python3 tests/test_stockcover.py      # STOCKCOVER, run in lispvm
python3 tests/test_cornerstp_geometry.py
python3 tests/test_drone_height_lisp.py
python3 tests/test_addon.py           # UV layout exporter
python3 tests/test_cloud_mesher.py    # point cloud mesher
python3 tests/test_dxf_reader.py      # Merlin import
python3 tests/test_mesh_layers.py     # Merlin layered export
python3 tests/test_dewrangler.py      # mesh dewrangler
python3 tests/test_pool_form.py       # palette <-> POOL (currently failing, see above)
python3 tests/test_spa_form.py        # palette <-> SPA (currently failing, see above)
```

## License

GPL-3.0-or-later (as required for Blender add-ons).
