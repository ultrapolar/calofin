# ABPCHECK -- how far every survey point sits off the drawn lines (AutoLISP / AutoCAD 2018+)

A fork of [ABHD](../abhd/README.md)'s measuring half. ABHD fits a
perimeter **through** the surveyed points and rings the ones it could
not hold; ABPCHECK does no fitting at all. Point it at a drawing that
is already drawn, say how far off is too far, and it reports every
point with the distance to the nearest line -- worst first, the ones
over the limit in red.

## What it does

1. **Reads the points.** Every `POINT` entity in the selection, every
   `ab_pt` block wherever it sits, and any other block dropped on the
   `POINTS` layer. A point block's own surveyed number (its `number`
   attribute) is what the report calls it, so a finding reads
   `Pt. 17` and means point 17 on the survey; a point with no number
   of its own is numbered in the order it was read. Two points closer
   together than `abp:*exact-eps*` are one point -- a double-shot is
   not two findings.

2. **Reads the lines.** Every `LINE`, `ARC`, `CIRCLE`, `LWPOLYLINE`
   and 2D `POLYLINE` in the selection, broken into ABHD's
   `(start end bulge)` segments. Distance is measured to the segment
   **itself**, not to its ends: perpendicular where the foot of the
   perpendicular lands on the run, to the nearer end where it does
   not. A point 2" above the middle of a 20 ft wall measures 2",
   never 10 ft.

3. **Asks the limit.** `How far off the line is too far? <0'-1">`.
   Enter takes the remembered answer; the first run offers 1". Zero
   and negatives are refused.

4. **Writes the report** (MTEXT) to the right of the drawing, sized to
   scale with it, and rings the points that are too far off:

   ```
   ABPCHECK REPORT
   2026-08-26 14:32  -  ABPCHECK v1.0
   2 POINTS MORE THAN 0'-1" OFF THE LINE
   Too far = more than 0'-1" off the nearest line.  ...

   POINTS TOO FAR OFF (2)
     Pt. 4     closest line is 0'-10" away
     Pt. 2     closest line is 0'-2" away
   POINTS ON THE LINE (3)
     Pt. 17    closest line is 0'-0 1/2" away
     Pt. 1     closest line is 0'-0" away
     Pt. 3     closest line is 0'-0" away
   ```

   Rows over the limit are red at full size; the rest are listed
   smaller, still worst first, so the near-misses are visible without
   hunting. Only `abp:*clear-shown*` of them are spelled out -- the
   rest are counted in one tail line, so a 200-point survey does not
   write 200 lines of "checks out".

Nothing but the report and the rings is written, both on their own
layers and both stamped as ABPCHECK's own work, so a re-run replaces
them instead of stacking and `ABPCHECKRESCUE` takes them away without
touching anything you drew.

## Install & run

APPLOAD `ABPCHECK.lsp` (or add it to your startup suite), then:

| Command | What it does |
| --- | --- |
| `ABPCHECK` | Highlight the drawing (Enter = the whole drawing), give the limit, get the report |
| `ABPCHECKRESCUE` | Remove the report and the rings |
| `ABPCHECKVER` | Print the loaded version |

## Tunables

Every value ABPCHECK reads that you might want to change sits in one
`TUNABLES` block at the top of `ABPCHECK.lsp`, each with a comment saying
what it does, its units, and what raising or lowering it changes. Edit
the value and APPLOAD the file again, or type the `setq` at the command
line to try a value for one session -- every knob is read when the
command runs, not when the file loads.

The tables below are the block, read off it:

**Where the survey points are**

| Global | Default | Meaning |
| --- | --- | --- |
| `abp:*pt-layer*` / `abp:*pt-block*` / `abp:*pt-tag*` | `"POINTS"` / `"ab_pt"` / `"number"` | Where the survey points live, and what a point block calls its number -- ABHD's *PF-POINT-LAYER* / *PF-POINT-BLOCK* / *PF-PT-TAG*. An ab_pt block counts as a point wherever it sits, so the layer only matters for bare POINT entities (layer holding the survey points; block name whose INSERTs mark points; the attribute carrying the number) |
| `abp:*filter*` | `'((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE"` | What the highlight is allowed to hand the command: the points, the geometry they are measured against, and the two curve types that are counted rather than measured so the report can say they were left out. A type dropped from here is never seen at all; a type added that abp:ent-segs cannot break into segments is silently ignored |
| `abp:*uncovered-types*` | `'("SPLINE" "ELLIPSE")` | The curve types the segment math does not cover. They are counted and named in the report rather than measured against, because guessing would report a point sitting ON a spline as off the line |

**What counts as too far**

| Global | Default | Meaning |
| --- | --- | --- |
| `abp:*limit*` | `1.0` | How far off the nearest line is too far. The command asks, Enter takes what is here, and the answer is remembered for the session -- so this is the FIRST-RUN default, not a cap (drawing units (1 inch)) |
| `abp:*exact-eps*` | `1.0e-6` | Two points closer than this are the same shot, not two (drawing units) |
| `abp:*plane-min*` | `0.999` | How far an entity's extrusion normal (DXF 210) may lean from world +Z before it is counted as "not in the world plane" and left out of the measurement. 0.999 is about 2.6 degrees of tilt (cosine of the tilt, so nearer 1 is stricter) |

**Marking and report**

| Global | Default | Meaning |
| --- | --- | --- |
| `abp:*miss-layer*` / `abp:*miss-color*` / `abp:*report-layer*` / `abp:*report-color*` / `abp:*appid*` | `"ABPCHECK-MISS"` / `1` / `"ABPCHECK-REPORT"` / `3` / `"ABPCHECK"` | The two layers ABPCHECK writes on, created on first use. It never clears a layer wholesale: everything it draws carries xdata under the APPID below, and only stamped objects are erased again -- so ABPCHECKRESCUE is safe on a layer the drawing already uses (ACI: the points that are too far off (red); ACI (green); renaming this orphans earlier runs) |
| `abp:*flag-color*` / `abp:*advice-color*` / `abp:*green-scale*` / `abp:*report-chars*` / `abp:*ring-scale*` | `1` / `4` / `0.75` / `48.0` / `1.2` | ACI: rows over the limit (red); ACI: advice, not a failure (cyan); height of a row that checked out; report column width, in text heights; ring radius, in report text heights |
| `abp:*clear-shown*` | `10` | How many within-limit points are listed before the rest are summed up in one line, so a 200-point survey does not write 200 rows (rows) |
| `abp:*report-wide*` / `abp:*report-lead*` / `abp:*report-hmax*` / `abp:*report-hmin*` / `abp:*report-hfall*` / `abp:*report-gap*` | `0.25` / `1.66` / `30.0` / `200.0` / `2.5` / `0.05` | The report is scaled to the drawing, as the check family's siblings do it. WIDE: on a wide, short sheet the reference height is at least this fraction of the width. LEAD: MTEXT line pitch as a multiple of text height. HMAX/HMIN: divisors clamping the height -- never taller than reference/HMAX, never shorter than reference/HMIN, so a smaller number is a looser bound. HFALL: the height used when there is nothing to scale against. GAP: space between drawing and report, as a fraction of the drawing's width (drawing units) |
| `abp:*title-scale*` / `abp:*hdg-gap*` / `abp:*head-lines*` / `abp:*hdg-lines*` | `1.5` / `0.4` / `4.5` / `1.4` | The title is written this many times the base height, and a section heading gets this much blank line above it. HEAD-LINES is the allowance for title, date, verdict and legend when guessing how long the sheet will run; HDG-LINES is a heading plus its gap |
| `abp:*row-indent*` | `"  "` | Findings are indented under their heading by this string |
| `abp:*dist-mode*` / `abp:*dist-prec*` | `4` / `4` | Distances in the report go through (rtos d mode prec): mode 4 is architectural (feet-inches), so 1.875 reads 0'-1 7/8"; prec is how many ways the inch is split, as a power of two (4 = sixteenths). This is the shape the report was asked for -- see the header (rtos mode; 2^4 = sixteenths of an inch) |
| `abp:*tiny*` | `1.0e-8` | A bounding box smaller than this has nothing to scale a report to (drawing units) |
## Notes & limitations

* **Splines and ellipses are counted, not measured.** The segment math
  forked from ABHD does not cover them. Rather than guess, the report
  names how many were in the selection and warns that a point sitting
  on one may be listed as off the line.
* **Flat (XY) measurement.** Objects not drawn in the world plane are
  counted and reported as such; set UCS to World and flatten them
  first if the number matters.
* **No geometry, no report.** Points with nothing to measure against,
  or a selection with no points in it, ends with a message saying
  which -- the limit is not even asked for.
* **It fixes nothing.** ABPCHECK reads the drawing and writes its own
  report; moving a stray point onto the line is `CHECK` /
  `LINFINCHECK` / `ABMOVE` territory.
* The grouped twin is generated -- run
  `python3 tools/mirror_shared.py ABPCHECK` after editing this file,
  never hand-edit `shared/parts/ABPCHECK.lsp`.

## Tests

```
python3 tests/test_abpcheck.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_abpcheck.py # grouped tier
```

Builds drawings with points at known distances off a known outline and
checks the number that comes back, who is red at a given limit, that
the rings land on the flagged points and go away again with
`ABPCHECKRESCUE`, and that a ring left over from an earlier run is
never read back as the "nearest line".
