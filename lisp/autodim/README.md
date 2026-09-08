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
way round with a dimension line within a foot, or the same centre and
radius. A second run over a grown plan dimensions the new geometry
only, while the overall dims (two feet further out) still land.

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

Every setting the tool has is a `(setq ad:*...*)` in the **tunables
block at the top of `AutoDim.lsp`**, each explained beside its default.
Change it there, or `(setq)` it after loading -- in a startup file, say
-- when one drawing needs something different. Nothing below that block
needs editing to change how the tool behaves.

Distances are given in **inches** and are converted to the drawing's own
units through `INSUNITS` (inches assumed when unitless), so a millimetre
drawing gets a real foot rather than 12 mm.

**Dimension styles.** Every dim picks its style by what it measures, not
by which step placed it; a style the drawing does not have falls back to
the one current when the command started.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*style-plan*` | `"SIDE STANDARD"` | The perimeter's sides and arc radii, and the stairs |
| `ad:*style-floor*` | `"STANDARD"` | The floor-dim chains |
| `ad:*style-over*` | `"STANDARD"` | The two overall dims |
| `ad:*style-short*` | `"STANDARD INCHES"` | Anything measuring less than `ad:*short-under*`, whichever of the three it would otherwise have been -- and every dim of a flight of steps in side view |
| `ad:*short-under*` | `12.0` | Inches: a dim measuring **less** than this goes in the short style (exactly 12" stays in the plan style). `nil` = never switch styles by length |

**Where the dims sit.** Automatic dims stand off what they measure by
`ad:*text-gap*` text heights (`DIMTXT` x `DIMSCALE`) and never closer
than the inch minimums below -- so a big drawing scale pushes them out
and a small one cannot pull them onto the plan.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*text-gap*` | `2.0` | Text heights of stand-off. The stairs use this alone; the others take it only when it beats their own minimum |
| `ad:*perim-clear*` | `12.0` | Inches: the least a perimeter dim sits outside the plan |
| `ad:*overall-gap*` | `24.0` | Inches: how far past the outermost dim the overall width (above) and height (left) sit |
| `ad:*near-dims*` | `48.0` | Inches: a dim further than this from the plan belongs to another plan or the title block and does not push the overall dims out. Four text stand-offs when that is larger |
| `ad:*steps-clear*` | `24.0` | Inches: how far clear of a side-view flight its step depths sit, and the overall depth again beyond them |

**Steps drawn in side view** -- what makes a selection read as a flight
rather than a plan, and where its dims go. Anything that fails is
dimensioned as a plan.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*steps-side*` | `1.0` | Which side AUTODIM puts a recognised flight's depths on: `1.0` right, `-1.0` left. AUTODIMSIDEPOV picks the steps' high side itself |
| `ad:*steps-layer*` | `"DIMENSION"` | The layer AUTODIMSIDEPOV draws on -- created if missing, switched on/thawed/unlocked if present. `nil` = the current layer, like everything else |
| `ad:*steps-color*` | `7` | The colour that layer is created with (an existing layer keeps its own) |
| `ad:*steps-min-risers*` | `2` | Fewer risers than this and it is a plan (the back wall not counted) |
| `ad:*steps-square*` | `0.75` | The fraction of straight segments that must run square; the rest may slope, like a pool floor at the foot |
| `ad:*steps-wall*` | `0.9` | A vertical at least this fraction of the profile's height is the back wall, not a riser |
| `ad:*steps-join*` | `0.01` | How far apart, as a fraction of the height, consecutive risers may be and still join up as one staircase; never tighter than `ad:*same-pt*` |

**One dim per size -- the `Typ.` rule.** A measurement that repeats is
called out once, on the first of its size, and the rest are left to that
note.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*typ-note*` | `" Typ."` | What follows the measurement on the dim that stands for its group |
| `ad:*typ-lines*` | `2` | Equal straight sides it takes before that happens. `nil` = never |
| `ad:*typ-curves*` | `4` | Equal radii it takes -- more than the sides, a pair or trio of matching curves reading better dimensioned where each one is. `nil` = never |

**One dimension per place.**

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*same-pt*` | `0.0625` | Inches (a sixteenth): two points closer than this are the same point, and two lengths or radii closer than this the same measurement to the `Typ.` rule |
| `ad:*same-line*` | `12.0` | Inches: two dims across the same points whose dim lines are within this are the same dim. Kept narrower than `ad:*overall-gap*` so the overall dims stay dims of their own |

**Geometry tolerances** -- rarely need changing.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ad:*fuzz*` | `0.0001` | Drawing units: coordinates differing by less than this are the same -- break points merge, a picked end this close to an object is on it, a tread width that changes by less is the same width, a riser shorter than this is not one |
| `ad:*square-tol*` | `0.001` | Radians (~0.06 deg): how far off parallel two lines may be and still be treads of one stair, and how far off vertical/horizontal a segment may be and still count as square |
| `ad:*plan-types*` | `"LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE,INSERT"` | The entity types AUTODIM highlights and FLOORDIM breaks at. Sides come from LINEs and LWPOLYLINEs and radii from ARCs, CIRCLEs and bulges; the rest only block perimeter rays, break a chain, and make a selection a plan rather than a flight |

## Notes & limitations

* All dims go on the **current layer** -- except `AUTODIMSIDEPOV`,
  which creates/sets layer `DIMENSION` and restores your layer after.
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
* Requires the Visual LISP engine, which ships with full AutoCAD.
  AutoCAD LT has no LISP engine and cannot run this file.

## Tests

`python3 tests/test_autodim.py` drives the dimension rules in the
repo's AutoLISP VM: style choice per measurement, the under-12"
override, the already-dimensioned skip (either way round, dim line
within a foot), the overall dims still landing two feet out, chain
breaks at taken spans and style changes, and the missing-style
fallback. `CALOFIN_LISP_ROOT=shared python3 tests/test_autodim.py`
runs the same suite against the grouped build.
