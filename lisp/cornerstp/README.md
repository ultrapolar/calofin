# CORNERSTP / HEMISTEP / NORMIESTEP -- pool step layout routines (AutoLISP / AutoCAD 2018+)

Three step-layout routines, one folder, one release: **`CORNERSTP`**
fans parallel corner steps out of a pool corner, **`HEMISTEP`** draws
steps that act like chords inside a curve and rebuilds the hemisphere
boundary through their ends, and **`NORMIESTEP`** draws the most
normal steps of all -- straight, parallel treads of one constant
width. They share the same settings, the same dimensioning, the same
side profile and the same bead hand-off, so learning one is most of
learning all three.

## What it does

Common to all three:

* **Treads are held exactly**; a step width within the width tolerance
  (1/8" by default) of the opening it lands in is snapped to the
  walls/curve, and any other width is held, centered, breaking away
  equally on both sides.
* **Distances read architectural style**: a bare number is inches
  (drawing units) and feet-inch entry like `1'4` (= 16") works
  whatever the units setting.
* In the tread loop, Enter = done, `Back` removes the step just drawn
  (its lines and its dimensions) and re-asks (`Undo` accepted too),
  and `Same` repeats the previous tread.
* **Optional dimensions** (`Dimension the steps? [Yes/No] <Yes>`):
  treads chained in `STANDARD INCHES`, widths nested in
  `SIDE STANDARD`; a missing style falls back to the current one with
  a note.
* **Optional side profile** (`Add a side profile? [Yes/No] <Yes>`):
  you give the step depths (vertical drops), top step first -- one per
  step plus one more for the drop after the last tread, so 3 steps
  take 4 depths -- then pick the top of the first tread. HEMISTEP's
  flight reads FROM THE WALL: the pick is the top of the wall (the
  curve, in its curve modes), the first depth it asks is the drop AT
  THE WALL, and the first tread it draws is the flat between the wall
  and the first chord, so the flight covers the same distances the
  plan's tread chain does. The flight
  always runs down and to the left; every depth gets its own vertical
  linear dim climbing with the steps, the overall depth sits further
  out, the treads carry no dims.
* **Bead the steps** (`[Yes/No] <Yes>`, then `Which steps have beaded
  side walls? [All/Some/None] <All>`): every tread is beaded -- that
  is the assumption -- **except the last one drawn**, the line that
  closes the run: it has no riser behind it, so it goes over to
  AUTOBEAD as a step line (it still works as a breakline) but is held
  back there unbeaded. `None` at the side-wall question leaves the
  walls bare and beads the step faces only. AUTOBEAD does the work on
  its own rules (2" toward the click, onto its `Bead Track` layer), so
  `AUTOBEAD.lsp` has to be loaded; when it is not, the run says so and
  finishes without beading. The beads are their own undo group, so one
  `U` undoes the beads and the next undoes the steps.

Per routine:

* **CORNERSTP** -- select the two walls forming the corner (a corner
  diagonal or fillet arc may be included). Draw direction keywords
  `Inside Outside` (default inside out); with a diagonal/arc the tread
  origin is `Middle` or `True` (corner), and the tread direction
  `Parallel` or `Equidistant`/`True` (angle bisector). Inside out you
  may add a **bench** along one wall: pick its wall, give its offset,
  name the step it attaches to, and every later step runs to the
  bench's front edge instead of that wall.
* **HEMISTEP** -- what you select decides the measuring axis: a LINE
  only (classic base-line mode, boundary drawn for you), a CURVE plus
  a LINE (treads measured along the line into the curve), or a CURVE
  only (from the middle of the curve). The hemisphere is rebuilt as
  one polyline of arcs through every step end; in the curve modes the
  span over the first step carries the selected curve's own bulge.
* **NORMIESTEP** -- one line (steps centered on it), two lines (a
  corner; you pick the line the steps run off of, and the run sits in
  a recess OUTSIDE the corner -- the two lines run away from it into
  the pool, so the water is the side they span and the steps go the
  other way, out through the wall they come off. Both sides of the
  recess are drawn: the inner one carries the line the treads butt
  against past the corner, the outer one is that line offset by the
  width, and only the outer one takes the back-corner flare), or a
  drawn "U"
  (treads filled in, no width asked -- the arms give it). The
  width is given once. Back corners take the canonical **Treatment**
  question -- `How should ... be treated?
  [Square/Radius/Cut/NotGiven]` (default `Square`; `NG` and the old
  words `90`, `ROUNDED`, `DIAG`/`DIAGONAL` are accepted typed in full,
  unlisted) -- with a `[Offset/Cut]` choice for how a Cut corner's
  size is given. A `NotGiven` corner is drawn square and noted on the
  drawing as never recorded.

## Install & run

1. In AutoCAD run `APPLOAD` and load the file(s) you need -- or load
   the **one bundled release**, `releases/STEPS_MMDDYY_REV##-##-##.lsp`
   (the three REV numbers are each member's own, each source copied in
   verbatim), and all six commands come with it. The shared build
   (`shared/LAZPASS.lsp`) carries all three too.
2. Run one of:

| Command | File | What it does |
| --- | --- | --- |
| `CORNERSTP` | `CORNERSTP.lsp` | Corner steps fanning out of a pool corner |
| `HEMISTEP` | `HEMISTEP.lsp` | Chord steps inside a curve, boundary rebuilt |
| `NORMIESTEP` | `NORMIESTEP.lsp` | Constant-width parallel treads |
| `TUTORIALCORNERSTP` | `CORNERSTP.lsp` | Guided walkthrough with an on-screen demo |
| `TUTORIALHEMISTEP` | `HEMISTEP.lsp` | Same, for HEMISTEP |
| `TUTORIALNORMIESTEP` | `NORMIESTEP.lsp` | Same, for NORMIESTEP |

## Tunables

Shared by all three files (each defines them only if not already set,
so load order does not matter; `setq` them before running to
override):

| Variable | Default | Meaning |
| --- | --- | --- |
| `*cs-width-tol*` | `nil` | Step width tolerance, drawing units; nil = 1/8" converted through `INSUNITS` |
| `*cs-depth-dimstyle*` | `"STANDARD INCHES"` | Style for step-tread dims (the side profile's dims too) |
| `*cs-width-dimstyle*` | `"SIDE STANDARD"` | Style for step-width dims |
| `*cs-dim-layer*` | `nil` | Layer for the dimensions; nil = current layer |
| `*cs-profile-dimgap*` | `nil` | How far the side profile's dims stand off the flight, on top of the clearance the geometry needs; nil = four text heights or 3/4 of a tread, whichever is more |

## Notes & limitations

* Geometry is assumed drawn in plan view; the routines warn when the
  UCS is not World, when selected geometry is not flat, and when the
  current layer is off, frozen or locked. Steps are drawn as LINEs on
  the current layer.
* `DIMSCALE` (or the annotation scale) sets dimension size; slide a
  dim by its grip if it lands awkwardly.
* One `U` reverses a whole run -- except the bead pass, which is its
  own group (AutoCAD does not nest undo groups).
* CORNERSTP's bracketed option text still spells the choices out
  (`[Inside out/Outside in]`, `[Middle of diagonal/True corner]`,
  `[Parallel to diagonal/...]`) while the typed keywords are the bare
  words listed above -- clicking those bracket phrases does not send a
  valid keyword. A known migration item (`STANDARDS.md` section 7.2);
  type the capitalized letters.
* The three routines namespace their helpers apart (`cs-`, `hs-`,
  `ns-`) and guard the settings globals they share, so loading all
  three (or the bundle) in one session is safe.

## Tests

* `python3 tests/test_cornerstp_geometry.py` -- Python mirrors of the
  geometry helpers of all three files (treads held exactly, widths
  centred on the opening, outermost steps wall-to-wall, bulge/arc
  round-trips), the AUTOBEAD hand-off, and a guard that the three
  ship as ONE `releases/STEPS_*.lsp` holding each source verbatim.
* `python3 tests/test_cornerstp_bench.py` -- CORNERSTP's bench,
  end-to-end in the AutoLISP VM.
* `python3 tests/test_cornerstp_profile.py` -- the side profile all
  three draw, in the VM.
* `python3 tests/test_normiestep_corner.py` -- NORMIESTEP's corner
  mode -- the recess outside the corner and both of its sides -- in
  the VM.

Each VM-driven one reruns against the grouped build with
`CALOFIN_LISP_ROOT=shared`.
