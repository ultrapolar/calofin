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
* **The length ruler.** Every step tread -- and, in the side profile,
  every step depth -- is asked beside `DIMSTAMP`'s ruler, drawn down a
  strip near the right edge of the view. From the second answer on it
  is a TAPE: the eighths of an inch for a whole inch either side of
  the last one, graded like a tape with that answer ringed. At the
  FIRST tread and the FIRST depth there is no last answer to build one
  round, so a LADDER stands there instead -- `*cs-tread-ladder*`, half
  feet, and `*cs-drop-ladder*`, whole inches -- and the tape takes
  over the moment it can be built, the finer offer being the better
  one. Click a row and that is the answer; type one and it reads the
  way `DIMSTAMP` reads (`24`, `24.5`, `24 1/8`, `2'`, `1'4-1/2"`, kept
  exactly as typed); click empty space and it is the first of two
  points to measure between, as `getdist` always offered. Enter, `Back`
  and `Same` mean what they always did. The prompt's wording does not
  change, so the `LAZSTEP` form is untouched. The ruler is scratch on
  the current layer, down again before the width prompt (which cannot
  take it) and before the profile's pick, and swept on every way out,
  Esc included. Its eight `*cs-ruler-*` knobs and the three ladders
  are in the table below.
* **NORMIESTEP's corner treatment stands on a ladder too.** Its
  `Radius`, `Cut face length` and `Offset back along each line` are
  sizes off an order sheet, not lengths taped off anything, so they
  are offered `*cs-corner-ladder*` -- 3" to 2'-0" by 3" -- from the
  first prompt: a run treats one corner, so there is never a second
  answer for a tape to be built round.
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
  size is given.

  **The corner is marked, per STANDARDS.md section 2.** A `Square`
  corner gets the mark that sheet draws: a small circle on the corner
  point with a radius dimension on that circle reading `90°` instead
  of measuring anything. A `NotGiven` corner is drawn square but the
  mark asks `?`, boxed, with a `Not Given` note on a leader off the
  box -- the drawing says the treatment was never recorded rather than
  claiming a right angle nobody taped. One answer covers both corners
  of a run, so one mark carries it and says `Typ.`; a corner-mode
  recess has a single treated corner and marks that one alone. A step's
  mark is the SMALLER of the two sizes the sample sheet carries
  (`*cs-mark-dimstyle*`), because a step's corners are a detail inside
  somebody else's plan.

  `90°` asserts a right angle, so it is drawn only where the corner
  really is one: a recess off a wall that leans, or a U with a splayed
  arm, is left unmarked rather than told a lie (`*cs-sq90-deg*` is how
  far off 90 still counts). `?` asserts nothing about the angle and is
  drawn at any.

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
| `*cs-width-tol*` | `nil` | Step width tolerance, drawing units: a width within this of the opening it lands in snaps to the walls (to the curve, in HEMISTEP); nil = derive it from `*cs-tol-inch*` through `INSUNITS` |
| `*cs-tol-inch*` | `0.125` | What that tolerance is in INCHES when it is derived -- 1/8", the way the shop reads it |
| `*cs-depth-dimstyle*` | `"STANDARD INCHES"` | Style for step-tread dims (the side profile's depth dims too) |
| `*cs-width-dimstyle*` | `"SIDE STANDARD"` | Style for step-width dims |
| `*cs-dim-layer*` | `nil` | Layer for the dimensions -- and for the corner mark; nil = current layer |
| `*cs-mark-dimstyle*` | `"STANDARD INCHES"` | Style for the CORNER MARK: the smaller of the two sizes the sample sheet carries |
| `*cs-mark-r*` | `0.5` | Radius of the circle the mark is drawn on, in TEXT HEIGHTS; everything else in the mark is a multiple of it (text at 6.7 r, the `Not Given` leader at 8.4 r, its note at 11.4 r) |
| `*cs-sq90-deg*` | `20.0` | How far off 90, in DEGREES, a corner may sit and still be marked `90°`. POOL's own tolerance, so the two tools read a corner alike |
| `*cs-dim-offset*` | `2.0` | How far the step-tread dim chain stands off the run, in TEXT HEIGHTS -- so it tracks `DIMSCALE`, not the drawing's size |
| `*cs-dim-nest*` | `1.5` | How far a step-width dim sits behind the run, in text heights, on top of half that step's own width (the half-width is what nests the wider steps further out) |
| `*cs-profile-dimgap*` | `nil` | How far the side profile's dims stand off the flight, on top of the clearance the geometry needs; nil = the larger of the two terms below |
| `*cs-profile-gap-txt*` | `4.0` | ...that default's first term, in text heights |
| `*cs-profile-gap-tread*` | `0.75` | ...and its second, as a fraction of the widest tread |
| `*cs-ruler-color*` | `3` | ACI colour of the length ruler's rows -- the ones you can pick |
| `*cs-ruler-current-color*` | `7` | ACI colour of its ringed current row, the last answer, so it reads apart from the options; 7 is AutoCAD's black/white swap |
| `*cs-ruler-screen-x*` | `0.88` | Where the ruler's spine sits across the view, as a fraction of its width in from the left; past 0.5 the rows reach left, short of it right, so the ruler stays inside the view |
| `*cs-ruler-row-frac*` | `0.042` | One row's share of the view's height -- the ruler's size knob |
| `*cs-ruler-txt-frac*` | `0.5` | The biggest row label's height, as a fraction of the row spacing |
| `*cs-ruler-tick-frac*` | `0.6` | The longest tick, same measure |
| `*cs-ruler-ring-frac*` | `0.26` | The ring round the current row, same measure |
| `*cs-ruler-reach*` | `6.0` | How far inboard of the spine, in row spacings, a click still counts as picking a row rather than as the first point of a measured length |
| `*cs-tread-ladder*` | `'(6.0 36.0 6.0)` | The rungs the FIRST step tread stands on, as (LOW HIGH STEP) in inches -- a tape of eighths has to be built round a last answer, and at the first tread there is none. From the second on the finer tape takes over. `nil` leaves that prompt with nothing beside it until the second answer |
| `*cs-drop-ladder*` | `'(6.0 12.0 1.0)` | The same for the first step depth, in whole inches |
| `*cs-corner-ladder*` | `'(3.0 24.0 3.0)` | NORMIESTEP only: the rungs its corner treatment's Radius, Cut face and Offset stand on -- 3" to 2'-0" by 3", the sizes a corner is built to. A run treats ONE corner, so there is never a second answer for a tape, and these stand from the first prompt |
| `*cs-dims-default*` | `"Yes"` | What Enter answers at "Dimension the steps?". `"No"` makes a bare run the quick one and leaves the dims to be asked for by name |
| `*cs-profile-default*` | `"Yes"` | What Enter answers at "Add a side profile?". `"No"` ends a run at the plan, so the step-depth questions behind it are reached only by typing `Yes` |
| `*cs-bead-default*` | `"Yes"` | What Enter answers at "Bead the steps?". `"No"` suits a shop that runs `AUTOBEAD` itself once the drawing is finished |
| `*cs-beadsides-default*` | `"All"` | What Enter answers at the side-wall question once beading is on: `"All"`, `"Some"` (which then asks which step numbers) or `"None"`, which beads the step faces and leaves the walls bare |

The knobs one file keeps to itself:

| Variable | File | Default | Meaning |
| --- | --- | --- | --- |
| `*cs-chain-frac*` | CORNERSTP | `0.2` | The tread chain also clears this fraction of the first step's width, so a wide run does not run its chain through the steps; the larger of it and `*cs-dim-offset*` wins |
| `*cs-parallel-tol*` | CORNERSTP | `1.0` | How close to parallel, in DEGREES, the two selected walls may be before the run says the corner it found is a long way off. It warns and carries on |
| `*cs-join-fuzz*` | NORMIESTEP | `nil` | How far apart two ends may be and still count as JOINED when the parts of a U are chained -- what decides whether a hand-traced U reads as one outline or is refused as parts that do not connect; nil = four times the width tolerance |
| `*cs-direction-default*` | CORNERSTP | `"Inside"` | Which way Enter draws the run: `"Inside"` starts at the corner and builds out toward the pool, `"Outside"` places the outermost step first and walks back in. Only what Enter answers moves -- both words stay on the prompt |
| `*cs-measure-default*` | CORNERSTP | `"Middle"` | Where Enter measures the step treads from when a corner diagonal or fillet arc came in with the walls: `"Middle"` of that diagonal, or the `"True"` corner the two walls would meet at |
| `*cs-treadmode-default*` | CORNERSTP | `"Parallel"` | Which way Enter runs the treads when a diagonal came in with the walls: `"Parallel"` to the diagonal, or square to the true corner -- the answer the outside-in prompt spells `Equidistant` and the inside-out one `True`, so either word sets the same thing whichever way the run goes |
| `*cs-boundary-default*` | HEMISTEP | `"Yes"` | What Enter answers at "Draw the reconstructed boundary through the step ends?". `"No"` leaves the steps standing on their own and rebuilds no hemisphere through them |
| `*cs-treat-default*` | NORMIESTEP | `"Square"` | What the FIRST corner-treatment question offers on Enter -- one of `"Square"`, `"Radius"`, `"Cut"` or `"NotGiven"`, in any case. A re-ask behind a size question still offers the answer before it, as it always has; this only decides where that chain starts |
| `*cs-cut-given-default*` | NORMIESTEP | `"Offset"` | Which of a Cut corner's two sizes Enter asks for: the `"Offset"` back along each line, or the `"Cut"` face across them. Either gives the other, so this is the one the shop's order sheets quote |

Deliberately not settings, in any of the three: the epsilons the
geometry compares against, the temporary vectors a run previews itself
with, the direction the side profile reads (down and to the left, the
way the shop's elevations do), and the bead -- that is `AUTOBEAD`'s
work, on `AUTOBEAD`'s own settings.

A setting that is not a number where a number belongs falls back to the
value it shipped with rather than failing mid-run, and
`tests/test_steps_settings.py` holds the two copies of every default --
the one the settings block sets and the one its reader falls back to --
together.

**What Enter answers.** The nine `...-default*` knobs above are the
reply each prompt takes when you just press Enter -- the shop's habit,
written down once instead of typed every run. Nothing else changes:
the question still offers the same words in the same order. Each is
read back through its file's own canonicaliser (`cs-kwcanon` /
`hs-kwcanon` / `ns-kwcanon`), so any case will do -- `"no"`, `"NO"`
and `"No"` all set the same thing -- and a word that is not one of the
ones listed leaves the shipped default standing rather than reaching a
keyword test unspelled. A drafter sets their own through `LAZTUNE`
without editing this file.

## Notes & limitations

* Geometry is assumed drawn in plan view; the routines warn when the
  UCS is not World, when selected geometry is not flat, and when the
  current layer is off, frozen or locked. Steps are drawn as LINEs on
  the current layer.
* `DIMSCALE` (or the annotation scale) sets dimension size; slide a
  dim by its grip if it lands awkwardly.
* One `U` reverses a whole run -- except the bead pass, which is its
  own group (AutoCAD does not nest undo groups).
* Every bracket shows exactly the keywords its prompt accepts, so a
  click on one sends a word the command takes (`[Inside/Outside]`, not
  the old `[Inside out/Outside in]`); the explanation lives in the
  question text. `tools/check_lisp.py` fails a bracket that drifts.
* A drawing with UNDO switched off (`UNDOCTL` bit 1 clear) is handled:
  no group is opened, and none is closed. One `U` then undoes nothing,
  which is what UNDO off means.
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
* `python3 tests/test_steps_settings.py` -- the tunables above (every
  knob wired up, each reader falling back to the value the settings
  block sets, a knob set to nonsense drawing the default, and each one
  moving the drawing when it is set to something real), and the
  contingencies: UNDO off, the dim styles missing, a dim layer that
  cannot be drawn on, a frozen current layer, AUTOBEAD absent, and
  selections that cannot be made into a run.

Each VM-driven one reruns against the grouped build with
`CALOFIN_LISP_ROOT=shared`.
