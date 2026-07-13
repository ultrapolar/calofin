# POOL.LSP — swimming-pool as-built layout for AutoCAD

AutoLISP routine that draws a pool plan (**Rectangle**, **Oval** or
**Grecian**) from real-world field measurements, dimensions it, and
writes a target / actual / delta report next to the drawing.

Written in plain AutoLISP (`entmake` + classic commands only — no
ActiveX/VLA), so it loads in **AutoCAD 2018** and older releases alike
(full versions; AutoCAD LT before 2024 has no LISP support).

## Loading & running

1. `APPLOAD` → pick `POOL.LSP` (or drag the file into the drawing).
2. Type `POOL` and answer the prompts.

Drawing units are assumed to be **inches** — all tolerances below are
in inches. Values can be typed in the current input format (e.g.
`20'6-1/2"` when units are Architectural).

## What it asks

Corner naming used by every prompt:

```
D ---------- C        sides:  top D-C, bottom A-B
|            |        ends:   left A-D, right B-C
A ---------- B        cross:  A-C and B-D
```

1. Pool shape: `Rectangle` / `Oval` / `Grecian`.
2. Side lengths, top then bottom.
3. End lengths, left then right.
4. Cross dimensions A-C and B-D.
5. **Oval only:** total pool length, left end radius, right end radius.
6. **Grecian only:** for each end — diagonal top, diagonal bottom, end
   width between the diagonal end points.
7. Insertion base point.

## What it draws

| Layer | Content |
| --- | --- |
| `POOL-OUTLINE` | Best-fit "parametric" body: sides held within **±1"**, cross dims within **±2"** of the given values (field measurements carry human error). Plus oval arcs / Grecian ends. |
| `POOL-TRIANGLES` | Exact as-measured check figure built from two triangles (bottom + right end + cross A-C, and top + left end + cross A-C). **No tolerance** — lengths held exactly. Overlaid on the outline so the two can be compared; freeze one layer to view the other. |
| `POOL-DIMS` | Aligned dimensions for all sides, cross dims and shape extras (uses the current dimension style). |
| `POOL-NOTES` | Corner labels and the report table: one row per measurement with TARGET, ACTUAL and DELTA. |

### Fitting logic

1. Sides are first held **exactly** true and the body is skewed
   (four-bar search) to bring the cross dims as close as possible. If
   both cross dims land inside the 2" tolerance, done.
2. Otherwise the sides are allowed to flex inside their ±1" band
   (iterative relaxation) to pull the cross dims in.
3. If the cross dims still cannot be met, the sides are held true, the
   cross dims get as close as possible, and **`CROSS DIMS FAILED`** is
   written in red under the report table.

### Oval ends

A construction line is drawn perpendicular to each end from its
midpoint, with the given end radius as its length; a three-point arc
runs from one end corner, through the tip of that line, to the other
end corner. The total pool length (arc tip to arc tip) is reported
against the given target.

### Grecian ends

Two diagonals project from the end-line corners at a nominal 45°. The
angle is adjusted until the given end width fits between the diagonal
end points; if no angle works, the diagonal lengths are adjusted in
**1/8" increments** (smallest total adjustment first, at most **±1/2"**
from the given lengths) and the angle search repeats. The lengths and
angle actually used are reported; if nothing fits, the end is drawn at
45° with the given lengths and flagged as failed in the report.

## Tolerance constants

At the top of the file, all in drawing units (inches):

```lisp
(setq pool:*side-tol*  1.0)     ; side length tolerance
(setq pool:*cross-tol* 2.0)     ; cross dimension tolerance
(setq pool:*grec-step* 0.125)   ; Grecian diagonal adjustment increment
(setq pool:*grec-max*  4)       ; max increments each way (= 1/2")
```
