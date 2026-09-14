# PERPMARK -- measured distances marked square off the pool wall (AutoLISP / AutoCAD 2018+)

A bench, a step, a tanning ledge and a gutter are all measured the same
way in the field: stand at a spot on the wall, run the tape square off
it, and write the number down. `PERPMARK` is that, at the keyboard.
Click the spot, type the number, and the spot gets a circle of that
radius -- the swing of the tape -- and a line of that length running
square off the wall into the pool. Click the next spot, type the next
number, for as long as the sheet lasts. Then, if the marks are meant to
BE something, it joins them up: one polyline through the far end of
every mark between two picked ends, the circles cleared away, and each
line replaced by the dimension that says what it measured.

It is `PERPPTS`'s sibling, for the survey that arrives as a list of
spots rather than an even spacing. Where `PERPPTS` asks how many points
to divide a run into, `PERPMARK` is told where each one is.

## What it does

1. **Select the perimeter** -- the wall the distances were taped off.
   Any curve: a polyline (arc segments included), a line, an arc, a
   circle, and anything else AutoCAD can measure along.
2. **Click the centre of the pool.** That is the whole of the direction
   question: a mark runs square off the wall toward the side the centre
   is on, so nothing has to be answered per point. `Back` re-opens the
   selection.
3. **Pick a point, give the distance, and repeat.**

   ```
   Pick a point on or near the perimeter [Back] <Enter = done>:
   Distance from the perimeter at that point [Back]:
   ```

   - the point may be clicked or typed as a coordinate;
   - a point that is not ON the perimeter is projected onto it, and the
     mark is drawn from where it landed -- so a snap that missed still
     marks the right spot on the wall;
   - `Back` at the point takes the last mark away again (and at the
     first one re-opens the centre click); `Back` at the distance
     re-asks the point;
   - `Enter` ends the round.
4. **`Draw a polyline through the marks? [Yes/No/Back] <Yes>`** -- `No`
   leaves every circle and every line exactly where they are, to do
   with as you see fit. `Back` re-opens the round for another mark.
5. **`Pick where the run starts` / `Pick where the run ends`.** Those
   two picks are stations on the wall like any other: land on a mark
   and the run starts at that mark's measured end, land anywhere else
   and the distance there is taken as zero -- which is how a step that
   dies back into the wall is drawn.
6. The polyline goes in on the perimeter's own layer and properties,
   every circle is erased, and every line becomes a `SIDE STANDARD`
   dimension on layer `DIMENSION`.

### How the direction is found

Each mark's base point is the point of the perimeter closest to the
pick. The perimeter's tangent there, turned 90 degrees, gives the two
ways a mark could run; the one whose direction agrees with "toward the
centre click" is the one used. It is worked out per mark rather than
fixed once, so a run of marks round a corner or along a radius each
come off their own piece of wall square.

That makes the centre click a DIRECTION, not a datum: it is never
measured from and it does not have to be the true centroid.

### The order the polyline runs in

Marks are kept with their STATION -- how far along the perimeter,
measured from its start, the base point sits -- so the polyline runs
along the wall in the order the wall does, whatever order the marks
were clicked in. On a closed perimeter the run goes forward from the
start station to the end station, wrapping past the polyline's own seam
if that is the way round the two picks point. On an open one it is the
stretch between them, read from the start pick toward the end pick, so
a run picked right-to-left comes out right-to-left.

Marks outside the two picks keep their dimension -- the measurement was
still taken -- but stay off the polyline.

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
| `pm:*dimstyle*` | `"SIDE STANDARD"` | The dimension style to draw in. A drawing without it keeps its current style and is told so |
| `pm:*snap*` | `2.0` | How close ALONG THE WALL a start/end click has to land to count as an existing mark rather than as a new station measuring zero. Raise it for a drafter who picks the run's ends by eye; drop it to `0` to make every end pick a new station unless it is snapped exactly |
| `pm:*fuzz*` | `1e-6` | What counts as the same point: it keeps a zero-length segment out of the joined polyline and a zero-length normal out of the direction test |

## Notes & limitations

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
`c:PERPMARK` is driven from a script, so the projection, the direction,
the stations, the wall order, the seam wrap, the five `Back` steps and
the session the command hands back are all measured against the file
that actually ships.
