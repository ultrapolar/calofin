# Perpendicular Points — AutoCAD 2018 (AutoLISP)

`perp_points.lsp` adds the **`PERPPTS`** command to AutoCAD 2018.

It divides a line into equally-spaced points, offsets each one
perpendicular to the line by a length you supply, joins the new points
with a polyline, and dimensions each new point back to its point on the
line. Handy for building an offset profile / station-and-offset layout
off a reference line.

## What it does

1. **Select a line.**
2. **Enter how many values (points)** are required — the line is split
   into that many equally-spaced points, both endpoints included
   (minimum 2).
3. **Click a point** to set the direction:
   * the line end nearest your click becomes **START**, the far end
     **FINISH** — this fixes the order the lengths are entered in;
   * the side of the line your click lands on is the side the new
     points are offset toward.
4. **Enter a length for each point**, in order START → FINISH. Each
   division point gets a new point that far perpendicular to the line.

A **red arrow** is drawn pointing at the **START** end when you pick the
direction, so the order is clear at a glance.

The routine then:

* creates a `POINT` node at each new (offset) location,
* draws a `POLYLINE` connecting the new points in order, and
* adds an aligned `DIMENSION` from every new point back to its
  corresponding base point on the line.

## Install / run

* Load once: *Manage → Load Application…* (`APPLOAD`), pick
  `perp_points.lsp`, then type `PERPPTS`.
* To auto-load every session, add it to your `acad.lsp` / Startup Suite.

## Notes

* Works in the current UCS/XY plane; the base points keep the line's
  start Z.
* Object snap is temporarily turned off while the offset points are
  placed and restored afterward.
* Point nodes are easier to see with a visible point style — set one via
  the `PTYPE`/`DDPTYPE` dialog if the points don't show.

## License

GPL-3.0-or-later (matching the rest of this repository).
