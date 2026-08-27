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
2. `Has that width changed? [Grew/Shrank/New/Unchanged] <Unchanged>` --
   the width meant is the distance straight across, end to end, not
   the developed length. Half of any difference is added to (or taken
   off) each end by scaling the object about the midpoint of its two
   ends, so the drawing is resized to match before anything is
   measured off it.
3. Click a point to set the direction: the end nearest the click
   becomes START (fixing the order lengths are entered in) and the
   side the click lands on is the offset side.
4. Enter how many values (points) are required (>= 2).
5. Enter a length per point, START to FINISH. Enter reuses the
   previous length; `B` (Back) steps back and re-enters the previous
   point (`U`/`UNDO` accepted).
6. `How should the points be joined? [Straight/Arcs/Mixed]` -- every
   segment a line, every segment an arc, or `Mixed`, which asks which
   segment numbers are arcs (`1 3-5`) and leaves the rest straight.
   Only asked from three points up; the answer becomes the next
   round's default. Arc segments are bulges on the same LWPOLYLINE --
   never a spline, never a curve-fit heavy polyline -- and each arc
   passes exactly through the two points it joins.
7. `Repeat on the new polyline? [Yes/No] <No>` -- a new point count,
   spaced along the new polyline (by true arc length once arcs have
   been drawn), offset again. The offset direction -- and every
   dimension -- stays perpendicular to the ORIGINAL line, so all
   offsets accumulate in one consistent direction.
8. `Dimension style - STANDARD INCHES or SIDE STANDARD?
   [STandard/SIde] <STandard>` -- every dimension is then drawn at
   once, on the `DIMENSIONS` layer.

**`CPERPPTS`** ("C" for curved) is the same pipeline for curved
geometry -- LWPOLYLINE (bulges included), POLYLINE, LINE, ARC, ELLIPSE
and SPLINE, open only. Differences from PERPPTS:

* Offsets are taken perpendicular to the curve's TANGENT under each
  base point, so a different length works at every point.
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

## Assumptions

* Dimensions go on the `DIMENSIONS` layer (created if missing) in the
  style picked at the end -- `STANDARD INCHES` or `SIDE STANDARD`;
  when the drawing lacks the style the current one is used and a note
  is printed.
* The offset polylines take the layer, colour, linetype, lineweight
  and linetype scale of the object they were offset from.
* CPERPPTS needs an OPEN curve -- a closed loop has no two ends to
  span a width between.
* There are no tunable globals; the 2"-style constants of other tools
  have no counterpart here because every length is typed per point.

## Notes & limitations

* The whole run is one UNDO group -- a single `U` reverses everything,
  the width resize included. Esc or an error restores every system
  variable changed (`OSMODE`, `CMDECHO`, `PDMODE`, `CLAYER`, the `CE*`
  creation defaults and the current dimension style), erases the
  temporary guides and closes the group.
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
checks that load the real `perp_points.lsp` into the repo's AutoLISP
VM and answer `c:PERPPTS` from a script -- prompt sequence, the
`Straight/Arcs/Mixed` question and the bulges that come out the other
end. `CALOFIN_LISP_ROOT=shared python3 tests/test_perp_points.py`
reruns it against the grouped build.
