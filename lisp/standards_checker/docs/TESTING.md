# Manual Test Scripts (Windows / AutoCAD 2018)

Run these in order after each milestone. Load the plugin with
`APPLOAD` → `src/acady-loader.lsp` (expect `[acady] loaded.` plus one
"loaded" line per module and no error text).

Setup used throughout:
- **P** = the "pacific" shape: a 240×120 rectangle with ONE corner filleted
  at R=102 (8'-6"). Draw with `RECTANG 0,0 240,120` then
  `FILLET` (R=102) on the corner at (240,120).
- Standards folder with `pacific.dwg` and `atlantic.dwg` (open the shipped
  `test/dxf/*.dxf`, `SAVEAS` DWG into the folder — see AUTHORING.md §5).
- Point the plugin at the folder: `MATCHSTD-CFG`, pick any DWG in it.

## M1 — signature extraction (ACADY-DUMPSIG)

1. Draw **P**. Command: `ACADY-DUMPSIG`, select the polyline.
   - Expect `1 path(s) extracted`, `kind=LOOP elems=5`.
   - Elements: four `L` (lengths 240, 18, 138, 120 in some cyclic order) and
     one `A r=8'-6" sweep=90 (CCW)`.
   - All `turn` values 90° (except the arc's neighbors summing consistently);
     no "turn-sum sanity" warning.
2. `MOVE`, `ROTATE` (37°), then re-run: **identical** ELEMS list.
3. `MIRROR` the shape, re-run: the *mirrored form* printed must equal the
   original shape's primary form.

## M2 — chaining and normalization

1. `EXPLODE` a copy of **P** → 4 lines + 1 arc. Select all 5, `ACADY-DUMPSIG`:
   same 5-element signature as the unexploded polyline.
2. Draw **P** clockwise (or `PEDIT` → `REVERSE`): same signature.
3. Add a collinear vertex mid-edge (PEDIT → Edit vertex → Insert): same
   signature (elements merge back to 5).
4. Select two separate rectangles: `2 path(s) extracted`.
5. Draw a Y of three lines meeting at a point, select all: expect the
   "geometry branches" error message, no crash.

## M3 — ObjectDBX scan (ACADY-SCAN)

1. `ACADY-SCAN`: for each DWG a `parsing <file> ...` line, then per-standard
   signature. PACIFIC must show the same 5 elements as **P** and
   `tolerance source: GEOM`; ATLANTIC shows 4 `L` and `tolerance source: TEXT`.
2. `OPEN` pacific.dwg in the editor, run `ACADY-SCAN` from another drawing:
   still parses (editor-open fallback), no error.
3. Drop a zero-byte `broken.dwg` into the folder: scan reports
   `skipped broken.dwg: ...` and completes.

## M4 — cache

1. `ACADY-SCAN` twice. Second run: no `parsing` lines (all cached), visibly
   instant, and `acady-cache.dat` exists in the standards folder.
2. Open+save pacific.dwg, rescan: only pacific re-parses.
3. Delete `acady-cache.dat`, rescan: full rebuild, no error.
4. Make the folder read-only, delete cache, rescan: works; cache lands in the
   TEMP folder instead.

## M5 — tolerance parsing

1. PACIFIC (two offset outlines) → `tolerance source: GEOM`.
2. Erase one of the two tolerance outlines in pacific.dwg, save → still GEOM
   (symmetric band).
3. Erase both, add TEXT `TOL=0.5` on TOLERANCE, save → `TEXT`.
4. Erase the text too → `GLOBAL`.
5. Add a vertex to a tolerance outline (counts now differ) → warning printed,
   source falls back, scan completes.
   (Restore pacific.dwg from the DXF afterward.)

## M6 — matching (console)

1. Copy **P**, `ROTATE` 37°, `MIRROR`, `MOVE`. `MATCHSTD`, select it:
   `MATCH  PACIFIC  ~100%  all 5 element(s) within tolerance`.
2. `STRETCH` one edge by 1/2" (inside the ±1" drawn band): still MATCH,
   score drops.
3. Stretch the same edge by 3": `CLOSE PACIFIC — 3 of 5 elements ...`
   (a stretch moves TWO edges out of band — that's expected).
4. Draw an unrelated L-shaped outline, `FILLET` one corner R=103, `MATCHSTD`:
   `POSSIBLE PACIFIC — 1 radius match(es): 8'-7"`.
5. Plain 180×90 rectangle: `MATCH ATLANTIC`; plain 100×40 rectangle:
   possibly `POSSIBLE` lines only, and **no** PACIFIC MATCH.

## M7 — dialog

1. `MATCHSTD` on **P**: dialog lists ranked candidates, row 0 pre-selected,
   details pane shows the element comparison table with `OK` per row.
2. Select another row: details update.
3. **Highlight Match**: dialog closes, outline highlights (dashed), for a
   POSSIBLE row a red circle marks the matching arc; Enter returns to the
   dialog with the same row selected; markers gone.
4. **Zoom To**: zooms to the selection, Enter returns.
5. **Rescan Standards**: re-parses all files, list refreshes.
6. Cancel, then `REGEN`: no highlight residue, no leftover marker circles
   (`ERASE` `ALL` `Previous` should find nothing new).
7. Esc mid-dialog: same clean state.

## M8 — hardening spot checks

- All lengths print architectural (`8'-6"`), all percentages 0–100%.
- `MATCHSTD` with nothing selected / empty folder / unset folder: friendly
  message, no LISP backtrace.
- BricsCAD (when the time comes): rerun M1, M3, M7 — the expected results
  are identical.
