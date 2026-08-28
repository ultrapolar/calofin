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

Set at the top of the file; the limit is also asked for on every run
and remembered for the session.

| Global | Default | What it is |
| --- | --- | --- |
| `abp:*limit*` | `1.0` | How far off the nearest line is too far, in drawing units. What the prompt offers |
| `abp:*pt-layer*` | `"POINTS"` | Layer whose blocks count as survey points |
| `abp:*pt-block*` | `"ab_pt"` | Block name that counts as a survey point on any layer |
| `abp:*pt-tag*` | `"number"` | The attribute carrying a point block's surveyed number |
| `abp:*exact-eps*` | `1.0e-6` | Two points closer than this are the same shot |
| `abp:*clear-shown*` | `10` | How many within-limit points the report spells out |
| `abp:*ring-scale*` | `1.2` | Ring radius, in report text heights |
| `abp:*miss-layer*` | `"ABPCHECK-MISS"` | Where the red rings go |
| `abp:*report-layer*` | `"ABPCHECK-REPORT"` | Where the report goes |

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
