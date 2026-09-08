# AUTODIM -- auto-dimension a highlighted plan, stairs and all (AutoLISP / AutoCAD 2018+)

Dimensions a highlighted plan in one pass -- perimeter sides and arc
radii, the stairs, two floor-dim chains it asks about, and the two
overall dims -- picking the right dimension style for each measurement
and never doubling up on a dim that is already there. Highlight a
flight of steps drawn in side view instead and AUTODIM recognises it
and dimensions the depth of every step.

## What it does

`AUTODIM` runs five steps:

1. **Highlight the plan.** Everything else in the drawing is ignored
   from then on -- only the highlighted geometry is dimensioned and
   used to find the perimeter. If the selection turns out to be a
   flight of steps drawn in side view (nothing curved, most segments
   square, two or more risers forming a connected staircase), steps 2
   to 5 are skipped and the side-view flow runs instead: the depth of
   every step down the right of the flight, plus the overall depth
   further right, all in `STANDARD INCHES`.
2. **Perimeter.** From the midpoint of every straight segment a test
   ray is cast perpendicular to each side; a segment with one side
   completely clear of highlighted geometry is on the perimeter, and
   its aligned dimension is placed on that clear side, at least a foot
   out. Arcs, circles and bulged polyline segments get radius dims.
3. **Stairs.** You highlight the stairs; the largest group of parallel
   lines is taken as the treads. Step widths are dimensioned (repeated
   only when the width changes) and the distances between treads are
   chained beside the stair. Enter without selecting skips it.
4. **Floor dims.** `Would you like floor dims? [Yes/No] <Yes>` --
   answer Yes and you draw two lines across the plan; each becomes a
   continued dimension chain that breaks at every highlighted object
   it crosses. A start or end point off the geometry is pulled back to
   the last object before it, so every dim runs object to object.
   `Back` here re-opens the stairs (erasing what they drew); Back at
   the second floor line re-opens the first.
5. **Overall dims**, no input needed: the plan's full width about 2 ft
   above the topmost dimension, its full height about 2 ft left of the
   left-most one.

Every dimension picks its style by what it measures: perimeter and
stairs in `SIDE STANDARD`, floor and overall dims in `STANDARD`, and
anything measuring under 12" in `STANDARD INCHES` whichever of the
three it would otherwise have been. A style the drawing does not have
falls back to the style that was current when the command started, and
that style is restored when it finishes.

**One dim per size.** A measurement that repeats is called out once
with ` Typ.` appended and the rest are left to that note -- from two
equal straight sides up, and from four equal radii up (a pair or trio
of matching curves reads better dimensioned where each one is). Two
lengths within a sixteenth of an inch count as the same measurement.

**One dimension per place.** Every linear, aligned and radius dim
already in model space is read first; a dim is skipped when one is
already there for that place -- same two extension-line origins either
way round with a dimension line within `ad:*band-feet*`, or the same
centre and radius. A second run over a grown plan dimensions the new
geometry only.

The two overall dims are recognised differently, because they are not
placed where the run before placed them: they stand clear of whatever
dims are around the plan, so a second run's would sit `ad:*over-feet*`
further out again and never match on position -- which used to leave a
fresh pair stacked outside the old one on every run. What is looked for
instead is a **linear** dim across the same two corners on the same
side, at any distance. A perimeter dim of a rectangular side spans the
same two corners but is an **aligned** one, so it still gets its own dim
as well.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `AutoDim.lsp`, and load it (add
   it to the *Startup Suite* to have it every session). The shared
   build (`shared/LAZPASS.lsp`) carries it too.
2. Run one of:

| Command | What it does |
| --- | --- |
| `AUTODIM` | The whole five-step pass (or the side-view flow when the selection is a flight of steps) |
| `STAIRDIM` | Just the stairs part again, for another selection |
| `FLOORDIM` | One extra floor-dims chain, breaking at everything in model space |
| `AUTODIMSIDEPOV` | Dimension steps drawn in side view: every riser gets a vertical dim beside its step, plus the overall height, on layer `DIMENSION` in `STANDARD INCHES` -- for a flight AUTODIM's test does not recognise, or to put the dims on the high side |

## Tunables

Everything about the tool a drafter might want different lives in one
`SETTINGS` block at the top of `AutoDim.lsp`, straight after the version
banner -- each with its default and a note on what changing it does.
Nothing below that block repeats a value from it, and
`tests/test_autodim.py` fails if a value creeps back down there.

`(setq ...)` one **after** the file has loaded -- at the command line, or
in `acaddoc.lsp` -- to change it for one drawing or one machine without
editing the file; edit the value here (and bump the version banner) to
change it for everyone.

Every distance is given in **feet** and converted through `INSUNITS`, so
a millimetre drawing gets the same foot as an inch one. The one
tolerance in inches says so in its name; the two in drawing units are
the tiny ones.

### Units

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*foot-when-unitless*` | `12.0` | Drawing units in one foot when `INSUNITS` is 0 or a unit the tool does not know. A drawing whose `INSUNITS` is set is read from that instead |

### Dimension styles

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*style-plan*` | `"SIDE STANDARD"` | Perimeter sides, arc radii and the stairs |
| `ad:*style-floor*` | `"STANDARD"` | The floor-dim chains |
| `ad:*style-over*` | `"STANDARD"` | The two overall dims |
| `ad:*style-short*` | `"STANDARD INCHES"` | Anything measuring under `ad:*short-feet*`, whichever of the three above it would otherwise have been |
| `ad:*style-steps*` | `"STANDARD INCHES"` | Steps drawn in side view -- depths and the overall alike, in `AUTODIM`'s side-view route and in `AUTODIMSIDEPOV` |
| `ad:*short-feet*` | `1.0` | The cut-off for the short style, in feet: a dim measuring *less* than this goes in `ad:*style-short*`. Exactly this much does not. The stairs prompt quotes it in whole inches |

### Layers

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*layer*` | `nil` | Layer `AUTODIM`, `STAIRDIM` and `FLOORDIM` put their dims on. `nil` = whatever layer is current (`DIMLAYER` still wins when the drawing sets it); a name is created -- or thawed, unlocked and switched on -- on the way in, and your layer put back after |
| `ad:*steps-layer*` | `"DIMENSION"` | The same for `AUTODIMSIDEPOV`, whose reference drawing keeps its step dims on a layer of their own; `nil` = the current layer here too |
| `ad:*layer-color*` | `7` | ACI colour a layer gets when it has to be created |

### Where the dims sit

The text offset is `ad:*text-offsets*` x `DIMTXT` x `DIMSCALE`. The feet
figures are floors under it: where the text offset comes out larger, the
text offset is what is used, so a small-scale drawing never has its dims
crammed against the plan.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*text-offsets*` | `2.0` | How many text heights a dim stands off its geometry. The stair dims use exactly this; every other dim uses the larger of this and its feet figure |
| `ad:*perim-feet*` | `1.0` | Perimeter dims sit at least this far outside the plan, heading outwards |
| `ad:*over-feet*` | `2.0` | The overall width sits this far above the topmost dim around the plan, the overall height this far left of the left-most one |
| `ad:*near-feet*` | `4.0` | How far from the plan a dimension may sit and still count as one of the plan's own when the overall dims look for the outermost -- further out it is another plan's, or the title block's. In feet, or in text offsets when those are bigger |
| `ad:*steps-feet*` | `2.0` | Side-view step dims sit this far clear of the flight, and the overall the same again further out |

### What counts as the same

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*same-inches*` | `0.0625` | **Inches.** Two points this close (a sixteenth) are the same place, and two measurements this close are the same size. The already-dimensioned test reads it on extension-line origins, centres and radii; the `Typ.` rule groups sides and radii by it |
| `ad:*band-feet*` | `1.0` | Two dims across the same two points are the same dim when their dimension lines are within this of each other. Keep it under `ad:*over-feet*`, or a rectangle's overall dims read as its sides |
| `ad:*angle-tol*` | `1e-3` | **Radians.** Two lines this close to parallel are parallel (finding the treads), and a line this close to horizontal or vertical is square (the side-view test) |
| `ad:*merge-tol*` | `1e-4` | **Drawing units.** Two points closer than this are one -- break points merged, a pick this close to an object is on it, treads this close together are one tread, step widths within it are equal |

### One dim per size: the `Typ.` rule

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*typ-note*` | `" Typ."` | Suffix on the one dim that stands for its group |
| `ad:*typ-lines*` | `2` | Equal straight sides it takes before one is noted and the rest left to it |
| `ad:*typ-curves*` | `4` | The same for equal radii -- higher on purpose: a pair or a trio of matching curves reads better dimensioned where each one is |

### Recognising steps drawn in side view

`AUTODIM` takes its side-view route only when the step-1 selection passes
every one of these, so loosening them is what could make a plan read as
steps.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*square-share*` | `0.75` | At least this share of the straight segments must run square, so a sloping pool floor at the foot of the flight still passes |
| `ad:*min-risers*` | `2` | Risers it takes to be a flight |
| `ad:*wall-share*` | `0.9` | A vertical at least this share of the profile's full height is the back wall, not a riser -- which is also what stops a rectangular plan reading as a two-step flight |
| `ad:*join-share*` | `0.01` | How far apart, as a share of the profile's height (never less than `ad:*same-inches*`), the foot of one riser and the top of the next may be and still join up into one staircase |

### What the highlights keep

DXF entity-type lists, comma-separated as `ssget` takes them.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*geom-types*` | `LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE,INSERT` | What makes up a plan: the step-1 highlight keeps these, only these block a perimeter ray, and these are what a floor-dims chain breaks at |
| `ad:*stair-types*` | `LINE,LWPOLYLINE` | What the stairs highlight (step 3, `STAIRDIM`) and the side-view highlight (`AUTODIMSIDEPOV`) keep |

The numbers that are *not* settings -- the `1e-8` zero-length guards, the
`1e-6` ray offset -- are numerical epsilons, not knobs.

## Notes & limitations

* All dims go on the **current layer** -- except `AUTODIMSIDEPOV`,
  which creates/sets layer `DIMENSION` and restores your layer after.
  Both are settings (`ad:*layer*`, `ad:*steps-layer*`); a layer that is
  frozen, locked or switched off is repaired on the way in and says so.
* Ellipses and splines have no one radius to call out, so the
  perimeter step passes over them.
* The two floor-dim lines are construction only -- erased once their
  chain is created. A chain breaks where a span is already dimensioned
  and where the style has to change, so a short span still lands in
  inches without dragging the rest of the chain with it.
* Break points closer together than 0.0001 drawing units are merged so
  no zero-length dims are created.
* A vertical as tall as the whole side-view profile is read as the
  back wall, not a step -- which is also what stops a rectangular plan
  reading as a two-step flight. Anything failing the side-view test is
  dimensioned as a plan.
* One foot is computed through `INSUNITS` (inches assumed when
  unitless), so the under-12" rule follows the drawing's units.
* With undo recording switched off (`UNDOCTL` bit 1 clear) no undo group
  is opened -- and none is closed; the run goes ahead without one.
* An error or Esc partway restores the dimension style, the layer and
  `CMDECHO`, and closes the undo group if one was opened.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  AutoCAD LT has no LISP engine and cannot run this file.

## Tests

`python3 tests/test_autodim.py` drives the dimension rules in the
repo's AutoLISP VM: style choice per measurement, the under-12"
override, the already-dimensioned skip (either way round, dim line
within a foot), the overall dims still landing two feet out and a
second run adding none, chain breaks at taken spans and style changes,
and the missing-style fallback.

It also holds the tool to its contingencies: every setting is in the
`SETTINGS` block and each one is wired to what it claims to change, a
drawing in millimetres or unitless gets the right foot, an angular,
ordinate or paper-space dim does not block a place, undo off opens and
closes no group, a run that dies partway puts the style, layer and
`CMDECHO` back, a frozen/locked/switched-off layer is repaired, a
measuring line that cannot be drawn says so once, and an empty highlight
changes nothing.

`CALOFIN_LISP_ROOT=shared python3 tests/test_autodim.py` runs the same
suite against the grouped build.
