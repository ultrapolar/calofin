# PERPMARK -- the distance taped at a survey point, marked square off the wall (AutoLISP / AutoCAD 2018+)

A bench, a step, a tanning ledge and a gutter are all measured the same
way in the field: stand at a survey point on the wall, run the tape
square off it, and write the number down beside that point's number.
`PERPMARK` is that, at the keyboard. Name the point -- click it or type
its number -- give the distance, and the point gets a circle of that
radius, the swing of the tape, and a line of that length running square
off the wall into the pool. Name the next point, type the next number,
for as long as the sheet lasts. Then, if the marks are meant to BE
something, it joins them up: one polyline through the far end of every
mark between two named points, the circles cleared away, and each line
replaced by the dimension that says what it measured.

It is `PERPPTS`'s sibling, for the survey that arrives as a list of
points rather than an even spacing. Where `PERPPTS` asks how many points
to divide a run into, `PERPMARK` is told which numbered shots carry a
distance.

The points are the ones the rest of the family reads. The classifier is
`BPCALLOUT`'s, shared with `CDCALLOUT`, `ABFIND` and `LHD`: an `ab_pt`
INSERT wherever it sits, any other INSERT on the `POINTS` layer, and a
plain `POINT` on that layer, numbered by its `number` attribute (or, on
an export that does not use that tag, by the first attribute that reads
as a number). A point whose number cannot be read is carried as `?`: it
can still be clicked, it just cannot be typed.

## What it does

1. **Select the perimeter** -- the wall the distances were taped off.
   Any curve: a polyline (arc segments included), a line, an arc, a
   circle, and anything else AutoCAD can measure along.
2. **Click the centre of the pool.** That is the whole of the direction
   question: a mark runs square off the wall toward the side the centre
   is on, so nothing has to be answered per point. It is the one pick in
   the command that is a place rather than a point. `Back` re-opens the
   selection.
3. **Name a survey point, give the distance, and repeat.**

   ```
   Pick a survey point, or type its number [Back] <Enter = done>:
   Distance from the perimeter at Pt.17 [Back]:
   ```

   - click the point, or type its number: `17`, `Pt.17`, `pt 17`, `#17`
     and `017` all name the same one;
   - a click within `pm:*snap*` of a point picks it; a click on nothing,
     a number nothing carries and a number two points share are all
     re-asked where they stand rather than guessed at;
   - a point that is not ON the perimeter is projected onto it, and the
     mark is drawn from where it landed -- so a shot sitting an inch off
     the fitted wall still marks the wall;
   - naming a point already marked REPLACES its mark. The sheet has one
     distance at a point, so the second answer is a correction;
   - `Back` takes the last mark away again, naming it;
   - `Enter` ends the round.
4. **`Draw a polyline through the marks? [Yes/No/Back] <Yes>`** -- `No`
   leaves every circle and every line exactly where they are, to do with
   as you see fit. `Back` re-opens the round for another mark.
5. **Which point the run starts at, and which it ends at**, named the
   same way. A point that was taped is the mark made at it, so the run
   starts where the tape reached; a point that was NOT taped measures
   zero and the run starts on the wall itself -- which is how a step
   that dies back into the wall is drawn. The two can be named in
   either order: the marks say which way round the run goes (below).
6. **The dimension style**, last, and only when there is a polyline to
   draw:

   ```
   Dimension style - STANDARD INCHES or SIDE STANDARD? [STandard/SIde/Back] <STandard>:
   ```

   `PERPPTS` and `CPERPPTS` ask this in exactly these words -- one
   question, one vocabulary. A pair of ends with nothing between them is
   reported instead of being asked a question it would throw away.
7. The polyline goes in on the perimeter's own layer and properties,
   every circle is erased, and every line becomes a dimension in that
   style on layer `DIMENSION`.

### How the direction is found

Each mark's base point is the point of the perimeter closest to the
survey point. The perimeter's tangent there, turned 90 degrees, gives
the two ways a mark could run; the one whose direction agrees with
"toward the centre click" is the one used. It is worked out per mark
rather than fixed once, so a run of marks round a corner or along a
radius each come off their own piece of wall square.

That makes the centre click a DIRECTION, not a datum: it is never
measured from and it does not have to be the true centroid.

### The order the polyline runs in

Marks are kept with their STATION -- how far along the perimeter,
measured from its start, the base point sits -- so the polyline runs
along the wall in the order the wall does, whatever order the points
were named in. On an open perimeter it is the stretch between the two
ends, read from the start toward the end, so a run named right-to-left
comes out right-to-left.

What decides whether a run end IS one of the marks is the survey point's
own identity, never how close the two landed. That is the whole reason
the pick is a point rather than a place: two shots a quarter inch apart
are still two shots, and the sheet says which one the run starts at.

### Which way round a closed wall, and why it is not asked

Two ends cut a closed perimeter into two arcs, and the run is one of
them. Which one is decided by the MARKS, not by the order the two ends
were named: every mark sits on exactly one arc, so the arc carrying more
of them is the run that was measured. Naming the ends the other way
round therefore gives the same run, read from whichever end was named
first.

> Before v1.2 the run went forward from the start station whatever was
> on the way, so naming the ends the other way round sent it round the
> empty side of the pool and handed back a two-point line straight
> across, with every measurement left off it.

The one case the marks cannot settle is a genuine tie -- the same number
on each arc -- and that is the only time the question is put:

```
The run's two ends cut the wall in half and each half carries the same
number of marks, so which way round it goes is yours to say.
Click a spot the run passes through [Back]:
```

One click, on a spot the run passes through. Like the centre click it is
a DIRECTION and not a datum: it is projected onto the wall only to ask
which arc it fell on. A tie needs at least two marks to be a tie, and
marks that ARE the two ends do not vote (an end sits on both arcs), so
an ordinary run never sees this question.

### A mark the run does not reach

It is NAMED, before the drawing is finished:

```
Pt.7 and Pt.9 sit outside the run - still dimensioned, but not joined.
```

and it keeps its dimension, because the measurement was still taken. A
partial run is a perfectly ordinary thing to want; a measurement going
quietly missing is not.

## Install & run

`APPLOAD` `PERPMARK.lsp` (or the whole build, `shared/LAZPASS.lsp`),
then type `PERPMARK`. `PERPMARKVER` prints the loaded version.

## Tunables

At the top of the file, between the version banner and the first
`defun`.

| Knob | Default | What changing it does |
| --- | --- | --- |
| `pm:*marklayer*` | `"PERPMARK"` | Puts the circles and the perpendicular lines on a different layer -- one a plot style already hides, say |
| `pm:*markcolor*` | `1` | The ACI that layer is CREATED with, on a drawing that lacks it. A number, not `'auto`: these marks are the measurement record and are meant to be seen, not to recede |
| `pm:*dimlayer*` | `"DIMENSION"` | Where the dimensions land |
| `pm:*dimcolor*` | `7` | The ACI that layer is created with |
| `pm:*dimstyle-std*` | `"STANDARD INCHES"` | The style the `STandard` answer draws in -- the Enter answer. The question is built from this name, so renaming it renames what the prompt offers; the KEYWORD stays `STandard`, which is the vocabulary all three perp tools share |
| `pm:*dimstyle-side*` | `"SIDE STANDARD"` | The same for the `SIde` answer. A drawing that has neither style keeps its current one and is told so |
| `pm:*point-block*` | `"ab_pt"` | The block whose INSERTs are survey points wherever they sit. Shared with `BPCALLOUT`, `CDCALLOUT`, `ABFIND` and `LHD` -- change it in all of them or the tools disagree about what the drawing holds |
| `pm:*point-layer*` | `"POINTS"` | The layer whose POINTs and INSERTs are survey points whatever block they are |
| `pm:*pt-tag*` | `"number"` | The attribute tag that names a point. A block without it lends its first attribute that reads as a number instead |
| `pm:*unknown*` | `"?"` | What a point with no readable number is called. It can still be clicked; only a number can be typed |
| `pm:*pt-prefix*` | `"Pt."` | How a point is named in the prompts and the report |
| `pm:*snap*` | `12.0` | How close a CLICK has to land to a survey point to pick it. A typed number never uses it -- a name is exact. `12.0` is what `BPCALLOUT` and `ABFIND` snap at, so a drafter's aim carries between the three |
| `pm:*fuzz*` | `1e-6` | What counts as the same point: it keeps a zero-length segment out of the joined polyline and a zero-length normal out of the direction test |

## Notes & limitations

- **A run cannot pass through marks on both sides of its own ends.**
  Two ends cut the wall in two, so if marks fall on each side no run
  between those ends can reach them all -- the arc with more of them is
  taken and the rest are named. If that is not what you meant, the ends
  are what to change.
- **The centre click has to be unambiguously inside.** Which way a mark
  runs is decided by the sign of one dot product, so on a deeply
  notched shape -- a narrow L, a keyhole -- a centre clicked in one
  lobe can sit on the wrong side of a wall in the other. Click it
  where it is clearly inside the part of the pool being measured, and
  read the marks before answering step 4.
- **The joined polyline is straight-segmented.** The marks are the
  spots the sheet names, not a dense sample, so they are joined with
  straight runs. A curved feature that has to FOLLOW a radiused wall is
  `CPERPPTS`'s job -- it samples the curve and bulges the result.
- **The drawing has to carry the points.** `PERPMARK` marks what the
  survey recorded, so a drawing with no survey points in it says so and
  stops rather than offering to mark places. `ABHD`, `ABCDEF`, `XYPLOT`
  and `ADAB` are what put them there.
- `LINE`, `ARC`, `CIRCLE` and `LWPOLYLINE` perimeters are read from the
  entity itself, which is where the station comes from. Anything else
  (a `SPLINE` traced off a drone photo, an `ELLIPSE`, an old heavy
  `POLYLINE`) is measured through `vlax-curve-*` instead; a curve
  AutoCAD will not answer for re-prompts rather than half-measuring.
- All geometry is worked in WCS and converted at the edges, so the
  command behaves under a rotated or shifted UCS.
- The whole run is one UNDO group: a single `U` reverses all of it,
  marks included. Esc at any prompt restores `OSMODE`, `CMDECHO`,
  `CLAYER` and the dimension style, and closes the group.
- Two picks with fewer than two marks between them draw nothing and
  erase nothing -- the run says so and leaves the marks alone.

## Tests

```
python3 tests/test_perpmark.py
CALOFIN_LISP_ROOT=shared python3 tests/test_perpmark.py
```

Runtime tests: the real file is loaded into `tests/lispvm.py` and
`c:PERPMARK` is driven from a script, so the naming (a click landing on
the right point, a typed number finding it, the five spellings meeting
in the middle, a bad number and a duplicate number re-asked), the
projection, the direction, the stations, the wall order, the seam wrap,
the ends being nameable in either order, the tie click and what it
leaves out, the run ends deciding by identity, the dimension style with
both its answers and its Enter, the seven `Back` steps and the session
the command hands back are all measured against the file that actually
ships.
