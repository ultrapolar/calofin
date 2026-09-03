# DIMCHECK test drawings — what each one should report

Regenerate the drawings with `python3 make_test_dxfs.py`, then run
`run_tests.bat` (see it for the `accoreconsole` path) to produce one
report per drawing in `out/`. Check each against the row below.

Every drawing isolates **one** rule so a failure points straight at the
rule that broke. Anything marked **red** in the report is a finding;
green lines are the all-clear (and render at 3/4 height).

| Drawing | Should report | Should NOT report |
| --- | --- | --- |
| `dim_stray_point` | one dim, point 2 **NOT attached** (off by 25.0) | an attached dim |
| `dim_attached_ok` | one dim, **OK** | any "off by" note |
| `dim_shared_anchor` | three dims: the third **NOT attached** (off by 15.0), and two **on a shared anchor** | any finding against the two dims meeting at the corner |
| `arc_unattached` | one arc, **NOT attached** to an object end (both ends) | endpoints OK |
| `arc_attached_ok` | one arc, endpoints **OK** | a NOT-attached note |
| `overlap_lines` | exactly **one** overlapping pair (overlap 40) | the third, clean line |
| `overlap_touching_ok` | no overlaps | any overlap |
| `overlap_polyline_edges` | exactly **one** overlapping pair (a polyline edge + a LINE, overlap 40) | the other three polyline edges |

## Notes

- `overlap_polyline_edges` is the important one: it pins that overlap
  detection decomposes an LWPOLYLINE into its edges and finds an
  overlap through one of them exactly like it would for a separate
  LINE. If this regresses to "no overlaps", segment decomposition has
  broken for this tool.
- `overlap_touching_ok` is the false-positive guard: lines that only
  touch end to end (a normal continuation, not a duplicate) must never
  be reported. If it starts reporting something, the overlap fuzz
  tolerance has been loosened too far.
- `dim_shared_anchor` is the anchor guard: two dims measuring to the
  same point in space (a hypotenuse corner, with no geometry through
  it) make that point an anchor, and neither may be asked to move off
  it. The third dim in the same drawing proves the rule has not gone
  blanket — a point only one dim measures to is still a stray.
- `dim_attached_ok` and `arc_attached_ok` are the two all-clear guards
  — if either starts reporting a finding, the attachment tolerance has
  tightened too far.

## Adding a case

Add a `@case("name")` function to `make_test_dxfs.py` returning a
`dxf(...)` string, regenerate, and add a row here. Keep one rule per
drawing.
