# SOCONV -- SO survey export onto the shop layers (AutoLISP / AutoCAD 2018+)

Takes a site survey the way the SO export drops it -- pool outline,
obstacles, Leica points, anchors, notes and dimensions each on the
export's own layer -- and puts the whole thing on the layers the rest
of the build looks for, in one command and one undo step.

It is the sibling of `DRONE` and `TYDRN` (`lisp/drone/`, `lisp/tydrn/`)
and does a smaller job than either: **SOCONV moves things between
layers and changes nothing else.** No restyling, no forced BYLAYER, no
rotating, nothing erased and nothing drawn. That is not a shortcut --
it is what the before/after sample the tool was written from actually
does (see *How the rules were arrived at* below), and there is a
tunable for the other behaviour if a job wants it.

## What it does

Six rules, applied in order, first match winning:

| from the export | what is on it | onto |
| --- | --- | --- |
| `Pool Perimeter` | everything | `POOL` |
| `Obstacles` | everything | `POOL` |
| `LEICA_DISTO_POINT_ENTITY` | `POINT` | `POINTS` |
| `Existing Anchorss` | `POINT` | `POINTS` |
| `Dimensions` | `TEXT`, `MTEXT` | `TEXT` |
| `Dimensions` | everything else | `DIMENSION` |

Three things about that table are worth saying out loud:

* **The obstacles really do go onto `POOL`.** Once the survey is in the
  shop's drawing they are part of the same outline, and the sample
  moves all twelve of them there.
* **`Dimensions` splits in two**, which is what the ordering is for:
  the notes (`Up 6"`, `Planter`, `Existing Anchors`) are caught by the
  `TEXT,MTEXT` row, so the catch-all under it takes the dimensions and
  anything else the export chose to leave on that layer -- a leader, a
  witness line. The sample had neither, only nine notes and seven
  dimensions.
* **`Existing Anchorss` is spelled the way the export spells it**,
  doubled `s` and all. The correct spelling is listed after it in the
  map, so an export that fixes the typo keeps working.

Both anchor points and Leica points land on the one `POINTS` layer --
232 of them in the sample, 71 + 161. (`DRONE` keeps anchors on their
own layer and recolours them; this export does not separate them that
way, and neither does the conversion.)

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `SOCONV.lsp`, and load it (add
   it to the *Startup Suite* to have it every session). The shared
   build (`shared/LAZPASS.lsp`) carries it too.
2. Open the export and:

| Command | What it does |
| --- | --- |
| `SOCONV` | Move the import onto `POOL` / `POINTS` / `TEXT` / `DIMENSION` |
| `SOCONVVER` | Print the loaded version |

It is on the LazPanel's `Rest` and `Points` pages, captioned *SO survey
onto our layers*.

The one question is what to convert:

```
Command: SOCONV
Select the survey import to convert <Enter = whole drawing>:
```

An import usually **is** the whole drawing, which is why `Enter` means
that. Highlight first (before typing the command, or at the prompt)
when two surveys share one drawing, or when only part of an import
should move. It reports what it did:

```
SOCONV done: 317 object(s) moved -- 69 -> POOL, 232 -> POINTS, 9 -> TEXT, 7 -> DIMENSION.
  Moved off Pool Perimeter, Obstacles, LEICA_DISTO_POINT_ENTITY, Existing Anchorss, Dimensions - PURGE those layers once the result looks right.
```

and, on a drawing that carries none of those layers, says so and names
what it was looking for rather than reporting a conversion of nothing.
Running it twice is running it once: the second run finds nothing left
on the export's layers.

The whole run is one undo mark, so a single `U` puts the drawing back.

## Tunables

At the top of `SOCONV.lsp`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `*soconv-map*` | the six rules above | The conversion itself: rows of `(source-layer entity-types destination)`, tried in order, first match winning. Both patterns are `wcmatch` patterns, so `,` is alternation and `*` is anything -- a shop whose export names things differently retunes here and nowhere else |
| `*soconv-colors*` | `POOL` 4, `POINTS` 6, `TEXT` 4, `DIMENSION` 141 | Colour to **create** a destination layer with when the drawing has not got it. An existing layer is never recoloured, so these only ever show on a bare drawing; `POOL` is cyan to agree with `POOL.LSP` and `POOLSIDE`, the other two places in the build that create it |
| `*soconv-default-color*` | `7` | For a destination the table above does not name |
| `*soconv-force-bylayer*` | `nil` | `T` also forces colour, linetype and lineweight to BYLAYER on the way past, the way `DRONE` and `TYDRN` do, so the import takes the destination layer's appearance and nothing overrides it later |

Only the destinations a run actually reaches are created: a survey with
no dimensions in it does not leave an empty `DIMENSION` layer behind.

## How the rules were arrived at

From `SOconv.dxf`, the sample the shop supplied: one drawing holding
the export and a by-hand conversion of it side by side, labelled
*Befre* and *After*, the second a copy of the first shifted
`(1080.22, 17.73)`. Pairing the two halves on geometry matches 316
objects, and the only DXF group that differs across every one of those
pairs is group 8, the layer. (Arc angles and one dimension length
differ in their last decimal place -- that is the copy that made the
sample, not a change.) Hence a layer remap and nothing else:

* the 161 Leica points carry an explicit magenta (ACI 6) **into** the
  conversion and still carry it out the other side;
* the 71 anchor points arrive BYLAYER and stay BYLAYER;
* the notes keep height 8.0, their style and their text;
* the dimensions keep their `STANDARD` style and every definition
  point.

Two things in the sample are deliberately **not** in the tool:

* **The after side is one dimension short of the before side.** A
  linear dim (`339.93` long) is in the export and not in the
  conversion -- the drafter dropped it while making the sample. That is
  an edit, not a rule, and SOCONV erases nothing.
* **The two halves sit in one drawing**, so the layer table holds both
  schemes at once and says nothing about what a destination layer
  should be created as when it is missing. `*soconv-colors*` is the
  build's own answer to that, not the sample's.

## Notes & limitations

* It sweeps the **whole drawing** unless you highlight something --
  model space and any layout, since the filter is by layer and not by
  space. The export's layer names are distinctive enough for that to be
  safe; highlight first if your title block borrows one of them.
* Objects **inside a block reference** are not touched. Explode first
  if an export ever nests its survey.
* The export's layers are left in the drawing, empty. `SOCONV` will not
  purge them: deleting layers is not something the sample shows and not
  something to do behind the drafter's back. `-PURGE` `LA` takes them
  when you are happy with the result -- which is what the done-line
  says.
* A locked layer among those touched is unlocked for the run and locked
  again afterwards, on the error path too. The destination layers are
  the exception: they are output layers, so `ensure-layer` thaws,
  unlocks and switches them on for good and says when it had to
  (STANDARDS 5) -- a conversion onto a frozen layer that looks like it
  did nothing is worse than a layer left usable.
* Requires the Visual LISP engine (ActiveX is used throughout), which
  ships with full AutoCAD. AutoCAD LT cannot run this file.

## Tests

```
python3 tests/test_soconv.py
CALOFIN_LISP_ROOT=shared python3 tests/test_soconv.py
```

builds the export in the repo's AutoLISP VM -- both point layers, the
outline, the obstacles, a note and a dimension sharing `Dimensions`,
plus a line on `0` and a point already on `POINTS` that nothing may
touch -- and runs the real command over it. It checks where everything
landed **and what stayed the same**: the explicit magenta, the note's
height and text, the dimension's style, the entity count. Then the
paths around it: a second run that finds nothing to do, a highlight
that scopes the conversion, `*soconv-force-bylayer*`, a drawing that is
not an export at all, an error mid-run and an `Esc` at the selection
prompt -- the last two reaching the command's own `*error*`, which has
to put the locks back and close the mark it opened.

`python3 tests/test_shared.py` loads it with everything else, so a name
collision fails there.
