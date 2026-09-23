# PERPPTS / CPERPPTS -- perpendicular offset points along a line or curve (AutoLISP / AutoCAD 2018+)

Builds an offset profile off a measured wall: base points spaced
evenly along a selected line (`PERPPTS`) or curve (`CPERPPTS`), each
offset perpendicular by a typed length, joined into one editable
polyline, and every offset dimensioned back to its base point. A
repeat step runs the same flow again on the polyline just drawn, round
after round. Four files live here: the two commands and a tutorial for
each.

## What it does

**`PERPPTS`** (straight base line):

1. Select a LINE (a polyline is also accepted, so work started
   earlier can be resumed).
2. Click a point to set the direction: the end nearest the click
   becomes START (fixing the order lengths are entered in, and marked
   by a red arrow for the whole run) and the side the click lands on
   is the offset side. `Back` re-opens the selection.
3. `Has that width changed? [Grew/Shrank/New/Unchanged/Back] <Unchanged>` --
   the width meant is the distance straight across, end to end, not
   the developed length. Then, for a change,
   `Split the <amount> evenly, half at each end? [Yes/No/Back] <Yes>`;
   `No` asks `How much of the <amount> at the START end (the arrowed
   end)? [Back]` and the rest goes on at FINISH. The object is scaled
   about a point on the line through its two ends -- the midpoint for
   an even split, nearer START the more of the change goes to FINISH
   -- so the drawing is resized to match before anything is measured
   off it. `Back` at the first question re-opens the click. Step 8
   asks the same of every line the command draws.
4. `Select a boundary for the offsets [None] <None>` takes any curve
   already in the drawing -- a property line, a house wall, a deck
   edge -- and then `Do the offsets stop at the boundary, or run out
   to meet it? [Limit/Meet/Back] <Limit>` says what it is (`Back`
   there re-opens the selection). Enter takes `None`.
5. Enter how many values (points) are required (>= 2).
6. Enter a length per point, START to FINISH. Enter reuses the
   previous length; `B` (Back) steps back to the last length typed and
   re-enters it (`U`/`UNDO` accepted), or to the count when nothing
   was typed yet. Under `Meet`, points with the boundary ahead of them
   are placed on it without a prompt. From the second length on the
   **length ruler** stands beside the drawing (below): click a row and
   that is the length.
7. `How should the points be joined? [Straight/Arcs/Mixed]` -- every
   segment a line, every segment an arc, or `Mixed`, which asks which
   segment numbers are arcs (`1 3-5`) and leaves the rest straight.
   Only asked from three points up; the answer becomes the next
   round's default. Arc segments are bulges on the same LWPOLYLINE --
   never a spline, never a curve-fit heavy polyline -- and each arc
   passes exactly through the two points it joins.
8. `Has that width changed? [Grew/Shrank/New/Unchanged] <Unchanged>`
   again, this time about the polyline just drawn -- it is the next
   course out and it was re-measured too, and a line built from typed
   offsets is only as wide as they add up to. Corrected the same way,
   split the same way, with the polyline's first point as START,
   before anything is measured off it.
9. `Repeat on the new polyline? [Yes/No] <No>` -- a new point count,
   spaced along the new polyline (by true arc length once arcs have
   been drawn), offset again. The offset direction -- and every
   dimension -- stays perpendicular to the ORIGINAL line, so all
   offsets accumulate in one consistent direction.
10. `Dimension style - STANDARD INCHES or SIDE STANDARD?
    [STandard/SIde] <STandard>` -- every dimension is then drawn at
    once, on the `DIMENSIONS` layer.

**`CPERPPTS`** ("C" for curved) is the same pipeline for curved
geometry -- LWPOLYLINE (bulges included), POLYLINE, LINE, ARC, ELLIPSE
and SPLINE, open only. Differences from PERPPTS:

* Offsets are taken perpendicular to the curve's TANGENT under each
  base point, so a different length works at every point, and the
  boundary is met along that point's own normal.
* The width question is asked of every curve the command draws, as it
  is in PERPPTS: right after the arc polyline appears and before the
  repeat question (there is no join question in between here).
* The joined result is always an arc polyline (no
  Straight/Arcs/Mixed question), each arc matched to the curve's
  tangent at its start -- a smooth LWPOLYLINE through every offset
  point.
* Each round offsets from the NEWEST curve, and points are spaced by
  true arc length, so spacing stays even through bends. The offset
  side is still fixed once, from the direction click, relative to the
  direction of travel.

## Install & run

1. In AutoCAD run `APPLOAD` and load the file(s) you need (add them to
   the *Startup Suite* to have them every session). The shared build
   (`shared/LAZPASS.lsp`) carries all four.
2. Run one of:

| Command | File | What it does |
| --- | --- | --- |
| `PERPPTS` | `perp_points.lsp` | Offset points off a straight line |
| `CPERPPTS` | `cperp_points.lsp` | Offset points off a curve, by tangent normals |
| `TUTORIALPERPPTS` | `tutorial_perp_points.lsp` | `[Checks/Demo/Both] <Both>`: the rules up front, a narrated worked example, or both; ends with `Keep the demo drawing? [Keep/Erase] <Keep>` |
| `TUTORIALCPERPPTS` | `tutorial_cperp_points.lsp` | The same, for CPERPPTS |

### The overall width, and how a change is shared out

A wall re-measured as a whole usually grew or shrank a little at both
ends, which is what Enter at the split question means: half at each
end. When the tape says otherwise -- the house end held and the deck
end moved -- answer `No` and give the amount at the START end; the
rest is the FINISH end's. Zero is an answer (all of it at FINISH) and
so is the whole amount (all of it at START). More than the whole
amount is refused, since FINISH would then have to move the other way,
which is a different change from the one just given. Growing and
shrinking are shared out the same way: the amount is what each end
moves by, outward or inward.

The resize is one uniform scale, whatever the split -- about the
midpoint for half-and-half, about a point nearer START the more of the
change goes to FINISH, about an end when that end holds still -- so
the shape between the ends is carried along in proportion either way,
and the START arrow is redrawn where START now is.

`Back` walks the chain: the START amount re-asks the split, the split
re-asks the amount, the amount re-asks Grew/Shrank/New/Unchanged, and
that -- for the selected object -- re-asks the direction click. The
round-level question offers no Back at its first question, because the
polyline it asks about is already drawn. One wrinkle: at
`Grew/Shrank/New/Unchanged/Back` the hotkey `U` is `Unchanged`, so the
hidden `Undo` synonym is typed in full there; `B` is Back as everywhere.

### The boundary

Both commands take one, and both then ask which of two things it is.

**Limit**: the boundary is the most any offset may reach. The cap is
measured **per point**, not once for the run: a ray is cast from each
base point along that point's own offset normal, and the nearest
crossing ahead of it is that point's maximum. A boundary at an angle
to the run is therefore nearer at one end than the other, which one
number could never say.

| At the length prompt | What happens |
| --- | --- |
| a cap exists | the prompt names it -- `Length for point 3 of 5, boundary at 18.375 <12> [Back/Max]` |
| `M` (Max) | takes the boundary exactly; offered only where there is one ahead |
| a longer length | is brought back to the boundary and said so; the number **typed** is still what Enter repeats at the next point, since the tape has not changed -- only how far this one point may reach |
| no crossing ahead | that point has no maximum and the prompt is the one it always was -- a boundary covering part of a run caps only the part it covers |

**Meet**: the boundary is where every offset ends. A point with the
boundary ahead of it is placed on the boundary and dimensioned to it,
and no length is asked -- the command prints
`Point 3 of 5 runs out to the boundary: 18.375.` and moves on. Where
the ray never reaches the boundary the length is asked as usual, with
`(no boundary ahead)` in the prompt so the silence is not mistaken for
a landing. `Back` at a length that is asked steps back to the last
length typed, taking every point that ran out to the boundary in
between with it; with nothing typed in front of it, it re-asks the
count.

Two things neither mode is:

* It holds the measured **points** at or inside the boundary. The
  segments between them are fitted to the points (PERPPTS) or to the
  curve's tangents (CPERPPTS), so where a boundary bends away between
  two points an arc joining them can still bow past it -- the answer
  is a point there, not a different arc.
* It is not re-applied by the width correction, which scales the whole
  line. That is the drafter's own measurement and is not
  second-guessed, but a correction that carries points past a Limit
  boundary, or off a Meet one, reports how many.

## The length ruler

Offsets off one wall are rarely all the same number and rarely far
apart -- 44, 44 1/2, 44 1/4, 45, for twenty points -- and typing each
one over again is what `DIMSTAMP` stopped doing for stamped text. Its
ruler does the same job here, in both commands. Once a first length
has been given, every later length prompt draws a column of nearby
values down a strip near the right edge of the view: every eighth of
an inch for a whole inch either side of the last length, graded like a
tape (whole inches boldest, eighths smallest), the last length ringed
in the middle. The prompt's words do not change; what it takes does:

| At the length prompt | What happens |
| --- | --- |
| click a ruler row | that value is the length for this point, and the ruler re-grades round it for the next |
| type a length | read as `DIMSTAMP` reads -- `44`, `44.5`, `44-1/2`, `4'4.5`, `4'-4-1/2"` -- and kept exactly as typed (`44.3` stays `44.3`; only the ruler rounds to the eighth). A fraction is dashed: the spacebar is Enter at this prompt, so `44 1/2` would enter 44 here and hand the 1/2 to the next point. Feet typed put the ruler in the feet family until plain inches are typed |
| Enter | the last length again, as it always was |
| click empty space | the first of two points to measure the length between -- what `getdist` always offered here |
| `B`, `U`, `M` | unchanged: Back, its synonym, and Max where a boundary is ahead |
| `0`, `-5`, `abc` | refused and asked again, with a line saying why |

The ruler is pinned to the screen, not the drawing, so it reads the
same at any zoom. It is scratch on the guide layer: taken down between
rounds, swept with the other guides on every way out, Esc included.
The hint line saying it is there is printed once a run.

## Tunables

All at the top of each file, one `setq` a line, in the `perp:` /
`cperp:` namespace. The two blocks hold the same knobs, bar the two
rows that name their prefix: the boundary default is spelled
`perp:*bound-default*` on one side and `cperp:*boundary-default*` on
the other, and only PERPPTS asks how the points are joined:

| Knob | Default | What moves when you change it |
| --- | --- | --- |
| `*ruler-color*` | `3` | ACI colour of the rows you can pick |
| `*ruler-current-color*` | `7` | ACI colour of the ringed current row -- the last length -- so it reads apart from the options; 7 is AutoCAD's black/white swap |
| `*ruler-screen-x*` | `0.88` | where the spine sits across the view, as a fraction of its width from the left; past 0.5 the rows reach left, short of it right, so the ruler stays inside the view |
| `*ruler-row-frac*` | `0.042` | one row's share of the view's height -- the ruler's size knob |
| `*ruler-txt-frac*` | `0.5` | the biggest row label's height, as a fraction of the row spacing |
| `*ruler-tick-frac*` | `0.6` | the longest tick, same measure |
| `*ruler-ring-frac*` | `0.26` | the ring round the current row, same measure |
| `*ruler-reach*` | `6.0` | how far inboard of the spine, in row spacings, a click still counts as picking a row rather than as the first point of a measured length |
| `*split-default*` | `"Yes"` | which answer the "Split the ... evenly, half at each end?" question takes on Enter when a width change has to be shared out -- `"Yes"` puts half of the difference at each end, `"No"` goes on to ask how much of it the START end takes. Both words are still offered and either can still be typed; anything that is neither is ignored and `Yes` stands |
| `perp:*bound-default*` / `cperp:*boundary-default*` | `"Limit"` | which answer the boundary's "stop at the boundary, or run out to meet it?" question takes on Enter -- `"Limit"` caps a length that would carry a point past the boundary, `"Meet"` runs every offset out to it without asking a length at all. Both keywords are still offered and either can still be typed; anything that is neither is ignored and `Limit` stands |
| `perp:*join-default*` (PERPPTS only) | `"Straight"` | what the FIRST round's "how should the points be joined?" question offers on Enter, before there is a round behind it to reuse -- `Straight`, `Arcs` or `Mixed`, in any case. Every round after the first offers the answer before it, as it always has; this only decides where that chain starts, and anything that is none of the three is ignored and `Straight` stands |
| `*dimstyle-default*` | `"STandard"` | which of the two dimension styles the closing question takes on Enter -- `STandard` (STANDARD INCHES) or `SIde` (SIDE STANDARD), in any case. A shop whose work is mostly side dimensions stops re-typing SIde at every run; the question is asked in the same words either way and both keywords are still offered, and anything that is neither is ignored and `STandard` stands |

## Assumptions

* Dimensions go on the `DIMENSIONS` layer (created if missing) in the
  style picked at the end -- `STANDARD INCHES` or `SIDE STANDARD`;
  when the drawing lacks the style the current one is used and a note
  is printed.
* The offset polylines take the layer, colour, linetype, lineweight
  and linetype scale of the object they were offset from.
* CPERPPTS needs an OPEN curve -- a closed loop has no two ends to
  span a width between.
* A boundary is only read, never moved or changed, and the ray cast at
  it lives and dies inside the probe -- nothing is left in the drawing.
  The object being offset from cannot be its own boundary.
* Every length is typed (or clicked) per point; no length has a
  default. What a question takes on Enter -- the split, the boundary
  mode, the join and the dimension style -- is a knob in the Tunables
  table above, and so is everything the ruler draws.

## Notes & limitations

* The whole run is one UNDO group -- a single `U` reverses everything,
  the width resizes included. Esc or an error restores every system
  variable changed (`OSMODE`, `CMDECHO`, `PDMODE`, `CLAYER`, the `CE*`
  creation defaults, `PLINETYPE`, `PLINEWID` and the current dimension
  style), erases the temporary guides and closes the group.
* Every offset course is drawn as a hairline lightweight polyline,
  whatever width `PLINE` was last left at in the drawing.
* A resize the drawing will not take -- a locked, frozen or
  switched-off layer -- stops the command before the first round,
  where nothing has been drawn yet. At a round it does not: the line is
  left at the width it drew and that width is printed, because rounds
  of typed lengths sit behind it and no dimension has been written.
  Either way nothing is measured off a width the drawing does not have.
* A round that corrects its width has its new points moved with the
  line, so its dimensions read the corrected drawing rather than the
  lengths typed into it.
* The boundary selection offers no `Back`: the resize the width
  question made is already in the drawing by then.
* Zero and negative lengths are rejected, as is a direction click that
  lands on the line/curve itself (where "which side" would be
  ambiguous). A point count over 100 asks
  `... points means ... dimensions. Continue? [Yes/No] <No>` first, a
  guard against a mistyped count creating thousands of entities.
* All geometry is handled in the current UCS, so the commands work in
  a rotated or shifted UCS.
* On a tight concave bend, normals converge and large offsets can make
  the new curve cross itself -- inherent to offsetting along normals,
  not a fault of the routine.

## Tests

`python3 tests/test_perp_points.py` covers both commands: structural
checks of each real `.lsp` (balanced parens, no leaked globals, every
changed sysvar saved and restored), geometry checks against reference
ports of the arc-length sampling and tangent/normal logic, and runtime
checks that load the real `perp_points.lsp` and `cperp_points.lsp`
into the repo's AutoLISP VM and answer `c:PERPPTS` and `c:CPERPPTS`
from a script -- prompt sequence and the Back chain through it, the
even and uneven width split, the `Straight/Arcs/Mixed` question and
the bulges that come out the other end, and the boundary in both its
modes. `CALOFIN_LISP_ROOT=shared python3 tests/test_perp_points.py`
reruns it against the grouped build.
