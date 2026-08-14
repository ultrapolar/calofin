# DIMCHECK test drawings — what each one should report

Regenerate the drawings with `python3 make_test_dxfs.py`, then run
`run_tests.bat` (see it for the `accoreconsole` path) to produce one
report per drawing in `out/`. Check each against the row below.

Every drawing isolates **one** rule so a failure points straight at the
rule that broke. Anything marked **red** in the report is a finding;
green lines are the all-clear (and render at 3/4 height).

| Drawing | Should report | Should NOT report |
| --- | --- | --- |
| `stairs_ok` | side view detected, rise 40; height MATCHES `Finished Wall Ht = 40"`; liner OK | any red line |
| `stairs_height_mismatch` | height **MISMATCH** (rise 40 vs WallHt 45) — under DIMCHECK the height dim is marked red automatically | a match |
| `stairs_polyline` | identical findings to `stairs_ok` — the same profile drawn as one polyline | "no step patterns detected" |
| `bench_two_treads` | side view detected (two treads), rise 60, height MATCHES | missing the bench entirely |
| `wallht_varies` | "height varies, not checked" in **green**; nothing flagged | any red height line |
| `wallht_multi` | **CHECK THE WALL HEIGHT** (3 heights); side view left alone | a MISMATCH |
| `overlap_lines` | exactly **one** overlapping pair (the two collinear lines) | the third, clean line |
| `overlap_touching_ok` | no overlaps | any overlap |
| `dim_stray_point` | one dim with a stray definition point | an attached dim |
| `arc_unattached` | one arc with an unattached end | endpoints OK |
| `liner_missing` | Liner Material block **MISSING** | a liner found |
| `liner_step_without_fg` | steps drawn but liner **MISSING its Step** | the fiberglass warning |
| `fgstep_with_liner_step` | Fiberglass Step present **and** liner HAS a Step → warn, naming the block | "liner missing its Step" (suppressed by design) |
| `bead_missing` | Bead attachment + plan steps, **NOTHING on layer Bead Track** | bead track present |
| `border_nominal` | border 704 x 543.625 — **nominal size, OK** (green) | any error |
| `border_scaled_up` | border at **2x — OK** (a scaled-up multiple is fine) | scaled-down |
| `border_scaled_down` | **"Title block should not be SCALED DOWN for Liners"** (red) | an OK verdict |
| `border_stretched` | **STRETCHED out of proportion** (1.200x wide, 1.000x tall) | scaled-down |
| `border_missing` | **NO BORDER found on layer 'border'** | a size verdict |
| `rectangle_not_sideview` | "no step patterns detected" | a side view (this is the false-positive guard) |

## Notes

- `stairs_ok` vs `stairs_polyline` is the important pair: they must
  produce the **same** findings. If the polyline one regresses to "no
  step patterns", segment decomposition has broken.
- `rectangle_not_sideview` and `overlap_touching_ok` are the two
  false-positive guards. If either starts reporting something, a
  tolerance has been loosened too far.
- `fgstep_with_liner_step` checks the rule interaction: the fiberglass
  warning must *replace* the opposite "missing its Step" warning, not
  appear alongside it.
- The border cases pin the title-block rule: nominal **58'-8" x 45'-3 5/8"**
  (704 x 543.625 units) or any scaled-**up** multiple passes; anything
  smaller is the error, and a border out of proportion is caught
  separately from one that is merely the wrong size.
- Heights are in drawing units where 1 unit = 1 inch, matching
  `*dchk-step-maxgap*` = 18 and `*dchk-bead-dist*` = 18.

## Adding a case

Add a `@case("name")` function to `make_test_dxfs.py` returning a
`dxf(...)` string, regenerate, and add a row here. Keep one rule per
drawing.
