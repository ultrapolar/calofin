# STOCKCOVER -- drop a stock cover drawing onto a highlighted perimeter (AutoLISP / AutoCAD 2018+)

Replaces a highlighted perimeter with a finished stock cover drawing
pulled straight out of the stock DWG folder, lined up on what was
highlighted. You highlight, type the stock drawing's short name, and
the stock lands in one move -- no fit prompt, no scaling, no shuffling
afterwards.

## What it does

1. **Highlight the perimeter to be replaced** (any selection).
2. **Type the stock drawing's short name** -- `5M` finds
   `5M_Tech.dwg`, `20M` finds `20M_Tech.dwg`. Enter on its own reuses
   the last name. Matching runs down a ladder -- exact stem, then each
   configured suffix, then a leading-substring sweep -- and each rung
   is tried only when the one above came up empty, so `5M` cannot be
   dragged off its exact file by `5MB_Tech.dwg` also existing.
   Several matches get a numbered pick.
3. The stock DWG is **read straight off disk** into a scratch block
   (`-INSERT` via `command-s`, with an ActiveX fallback), exploded,
   and **aligned by the anchor POINTs both sides carry**: one at the
   bottom left, one at the top right, in the highlighted area and in
   every stock drawing. One `MOVE`, bottom-left anchor onto
   bottom-left anchor, and it stays exactly there. A side without
   anchor points falls back to its bounding-box corners, and
   STOCKCOVER says so.
4. If the two anchor spans disagree by more than the tolerance, the
   wrong file was probably named: STOCKCOVER prints how far off the
   stock is, loudly (`ANCHORS DO NOT AGREE: ...`), but still places
   anchored -- nothing is silently rescaled.
5. The **highlighted entities are erased** -- only after the new
   geometry is placed -- and the scratch block definition is purged.

The whole run is one UNDO step; a single `U` rolls it all back.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `STOCKCOVER.lsp`, and load it
   (add it to the *Startup Suite* to have it every session). The
   shared build (`shared/LAZPASS.lsp`) carries it too.
2. Set the stock folder once (see Tunables, or run
   `STOCKCOVER-CFG`), then:

| Command | What it does |
| --- | --- |
| `STOCKCOVER` | Replace a highlighted perimeter with a stock DWG |
| `STOCKLIST` | List every stock drawing in the stock folder |
| `STOCKCOVER-CFG` | Point the routine at the stock folder by picking any DWG inside it -- remembered in the AutoCAD profile, per machine, and wins over the value in the file |

## Tunables

In the `SETTINGS` block at the top of `STOCKCOVER.lsp`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `*stock-folder*` | `F:\TechTeam\2022 StockCoverTech` | Where the stock DWGs live -- set this before handing the file out; a `STOCKCOVER-CFG` profile override beats it |
| `*stock-suffixes*` | `("_Tech")` | Suffixes tried after an exact stem match (`5M` -> `5M.dwg`, then `5M_Tech.dwg`, then `5M*.dwg`) |
| `*stock-explode*` | `T` | Explode the insert so the stock merges into the drawing; `nil` leaves it as one block reference |
| `*stock-anchor-tol*` | `0.25` | Inches the two anchor spans may differ before STOCKCOVER shouts that the wrong file was named |
| `*stock-env-folder*` / `*stock-env-last*` | `StockCover_Folder` / `StockCover_Last` | AutoCAD profile keys remembering the folder override and the last typed name |

## Notes & limitations

* The anchors are found among the POINT entities in each side: the one
  lowest along x+y is bottom-left, the highest is top-right. A side
  needs at least two POINTs to be anchored; otherwise its bounding-box
  corners stand in (and the message says which happened).
* `INSUNITS` is forced to 0 during the insert so AutoCAD cannot
  silently rescale a stock file with different unit settings; it is
  restored afterwards, along with `CMDECHO`, `OSMODE`, `CLAYER`,
  `ATTREQ` and `ATTDIA` -- on error too.
* If the ActiveX fallback is needed and the drawing already has a
  block named after the stock file's stem, STOCKCOVER says to rename
  it rather than redefining anything.
* An unreachable folder or an unmatched name ends the run with a
  message (try `STOCKLIST`); nothing is erased unless new geometry was
  actually placed.
* Requires the Visual LISP engine (ActiveX for bounding boxes and the
  insert fallback), which ships with full AutoCAD. AutoCAD LT cannot
  run this file.

## Tests

`python3 tests/test_stockcover.py` covers three layers: structural
checks of the real `.lsp` (balanced parens, pure ASCII, every changed
sysvar saved and restored, no leaked globals, version banner agreeing
with the `releases/` twin); a reference port of the name-resolution
ladder pinning the matching rules, including the ones that must NOT
fire; and runtime checks driving the actual LISP in the repo's
AutoLISP VM over a stubbed AutoCAD -- where the stock lands (anchored
bottom-left onto bottom-left), old perimeter erased only after
placement, no prompt after the name, and an anchor-span mismatch
shouted about but never silently rescaled.
`CALOFIN_LISP_ROOT=shared python3 tests/test_stockcover.py` reruns it
against the grouped build.
