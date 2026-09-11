# calofin v3.6

Blender add-ons, AutoLISP routines, and a AutoCAD palette UI for pool/spa
drafting. This branch consolidates what used to be ~29 separate branches,
each with its own single addition on top of a shared base, into one tree
where every tool lives side by side and can be worked on from a single
checkout.

```
ariel/      Windows helper: places Ariel's deck anchors on the dots in a
            drone photo. Python, not AutoLISP - not in LAZPASS, not on the
            palette
blender/    Blender add-ons (DXF import/export, mesh tools)
lisp/       AutoLISP tools, one self-contained file each - the source of truth
releases/   Dated REV-stamped twins of the lisp/ files, flat, GENERATED
shared/     The loaded-together build on CALOFIN-LIB.lsp (bundle GENERATED)
ui/         The Calofin AutoCAD palette (VB.NET) and its LISP glue
tools/      Dev tooling (release stamping, bundle building, static checks)
tests/      Python test suite - stdlib only, no AutoCAD or Blender needed
```

## Working in this repo

A tool exists at up to four levels of packaging, and they have to stay
in step:

| Tier | Folder | What it is | Hand-edited? |
| --- | --- | --- | --- |
| draft | `wip/` | being drafted, no version banner yet. Optional - absent until a first draft lands. | yes |
| standalone | `lisp/<tool>/` | one self-contained file, loads alone with APPLOAD. **All tool logic starts here.** | yes |
| released | `releases/` | dated `REV`-stamped twin, so a loaded routine never changes underfoot | no - generated |
| grouped | `shared/parts/` | the same tools on one helper library (`cal:`); `shared/LAZPASS.lsp` is the generated one-file build | generated for the tools in `tools/mirror_shared.py`, by hand otherwise; bundle generated |

Change a tool in `lisp/`, mirror it into `shared/parts/<FILE>.lsp` in the same
commit, then regenerate both artifacts:

```
python3 tools/mirror_shared.py <TOOL>  # the shared/parts/ twin, where generated
python3 tools/release_lisp.py          # releases/ dated twins
python3 tools/build_shared_bundle.py   # shared/LAZPASS.lsp
python3 tools/check_standards.py       # did anything drift?
```

Never hand-edit `releases/` or `shared/LAZPASS.lsp`.

A tool can be in `lisp/` and `shared/parts/` yet deliberately kept out of
the compiled bundle while it is being reworked (or for good, if it never
belonged in calofin). `cal:*held-back*` in
`shared/parts/CALOFIN-LOADER.lsp` is the list, with a reason on each
entry; the bundle header repeats it.

### Running the tests

No dependencies - `tests/lispvm.py` is a pure-Python AutoLISP
interpreter, so the suite needs only the standard library. One
environment variable matters:

| Variable | Meaning |
| --- | --- |
| `CALOFIN_LISP_ROOT` | which tier the VM tests read. **Unset means `lisp/`**, which is the default every test must keep. Set it per command, never globally - exported globally it points the whole suite at `shared/` and hides a standalone regression. |

```
python3 tests/test_pool_runtime.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_pool_runtime.py # grouped tier
python3 tests/test_shared.py     # whole grouped build + the one-file bundle
```

Running a test both ways is the parity check that keeps the two builds
honest. `CLAUDE.md` is the same contract written for Claude Code
sessions; `.claude/README.md` covers the hook and the cloud environment
panels.

## Blender add-ons (`blender/`)

Blender 4.2+ (including 5.0). Install as an extension or legacy add-on -
see each folder's own README for the exact steps.

| Add-on | Folder | What it does |
| --- | --- | --- |
| Merlin Import/Export | `blender/merlin_import_export/` | Imports AutoCAD DXFs (one object per layer, auto parent/scale/position) and exports mesh edges as a layered CAD DXF (FLOOR/WALL/STEPS objects by material) |
| Export UV Layout to DXF | `blender/uv_layout_dxf/` | Exports UV island outlines as an AutoCAD-compatible DXF, with orientation fixing and Freestyle-edge auto scaling |
| DXF Point Cloud Mesher | `blender/dxf_cloud_mesher/` | Fills imported DXF point-cloud objects with n-gon or Delaunay-triangulated faces |
| Mesh Dewrangler | `blender/mesh_dewrangler/` | Mesh simplification / topology cleanup |

## AutoLISP routines (`lisp/`)

Each tool lives under `lisp/<name>/`, with the identically-named,
dated copy of any versioned file living flat in `releases/` (see
below) - except the step routines, which release as one bundled file.
Load a routine with APPLOAD, or add it to your startup suite. A
Startup Suite entry runs in every drawing you open: each tool prints
its one-line banner again (about seventy lines for the whole of
`LAZPASS.lsp`), and the panel's toolbar work runs once per session,
not once per drawing.
Prompt wording, keyword sets and file structure follow the shared
standard in [STANDARDS.md](STANDARDS.md) - read it before adding or
changing a routine.

| Command(s) | Folder | What it does |
| --- | --- | --- |
| `POOL`, `POOLCOVER`, `POOLDEMO`, `POOLDEMOVER`, `POOLVER`, `TUTORIALPOOL` | `lisp/pool/` | As-built pool plan generator - Rectangle, Oval, Grecian, L, Lazy L - from field measurements. `POOLCOVER` is the same command for a cover sheet: the pool-bottom question is answered No before it is asked, so the depth chain behind it (C, C2, D, the hopper type and its corner method) never runs |
| `POOLSIDE`, `POOLSIDEVER` | `lisp/poolside/` | POOL's side view (the longitudinal section) on its own: the bottom type, the overall length B, the floor run chain (`H G F E`, or `E2 F2 G F1 E1` for a Sport) and the depths C / D / C2 - no plan, no perimeter, no cross dims. A gray nominal section is on screen while the letters are asked, with the tie being asked for lit red. Any run may be `NA` and is read back off B; a run that resolves negative is floored, its dimension drawn red and a note written under the section |
| `SPA`, `SPAVER`, `TUTORIALSPA` | `lisp/spa/` | Spa/hot-tub template - Rectangle, Octagon, Round |
| `OASIS`, `OASISVER` | `lisp/oasis/` | Continuous-tangent pool - centre bulge, top-right bulge, cloud (straight or rounded bottom), kidney (true or asymmetric) or NXT cloud (three lobes, four fillets) - drawn live as its X/Y envelope and radii are answered, with a centre-to-corner check drawing beside it.  A `Complex` run takes a straight tangent run in place of any joiner and places the third bulge along X: the centre hump off centre, or the top-right bulge in off the right-hand bound so that the top wall alone holds it - given as a signed shift, or as the centre-to-centre `Tie` back to the right bulge that the drawing carries and the check drawing prints.  Finishes by offering the pool bottom - shallow and deep breaks, hopper and slope lines, ABHD's flow with the break located by a change of tangency, a nearest point or an offset in from a bound.  Takes a form's answers (`oasis:*form*`), so `LAZFORM`'s oasis sheets drive it |
| `ABHD`, `ABHDVER`, `ABHDCOVER`, `ADAB`, `TUTORIALABHD`, `TUTORIALADAB` | `lisp/abhd/` | Fits a pool perimeter and bottom through surveyed points. `ABHDCOVER` answers the "add the bottom" question No before it is asked, for a cover sheet that stops at the perimeter |
| `ABCURCHECK`, `ABCURCHECKSCAN`, `ABCURCHECKRESCUE`, `ABCURCHECKVER` | `lisp/abcurcheck/` | ABHD's reader turned round: grades how CONTINUOUS a perimeter already drawn is, as one word - `Smooth` / `Fair` / `Rough` / `Broken` - set by the single worst thing found and naming it, with a 0-100 index underneath for comparing two candidates.  Measures gaps, zero-length and doubled segments and crossings (G0); the kink angle at every joint, banded on ABHD's own 8 and 45 degrees, so the 8-45 band a fabricator finds in the bead is the headline; and the noise a traced outline leaves behind - micro-segments, inflections, and the turning excess over the 360 degrees any simple closed loop turns.  Breaks that are MEANT to be there are picked and stamped onto the drawing, so they leave the grade and the next run remembers them; what is left is the undeclared list, ringed on `POOL-CONT`.  Draws the curvature comb on `POOL-COMB` - a tooth per sample, sided by which way the curve turns - where every break is a step in the envelope |
| `CABHD`, `CABHDVER` | `lisp/cabhd/` | ABHD's perimeter half, for a survey that runs past the pool: asks the LAST point number belonging to the pool edge and leaves everything past it out entirely.  No pool bottom |
| `LHD` | `lisp/lhd/` | Fits a top-down 2D outline (closed or open) through laser-scanned points |
| `FITABHD`, `FITABHDCOVER`, `FITABHDVER` | `lisp/fitabhd/` | Fits a TYPED pool template (Rectangle, Grecian, Roman, Oval, L, Lazy L, Round, or an OASIS pool) through surveyed points -- the type says how to READ the survey, the points decide the shape: out-of-square walls, side walls that lean apart on a Roman or Oval, corner sizes, bows, and any curve drawn as one R -- an end, a corner, a bow -- rebuilt as a smooth run of up to a third as many arcs as it has points (ABHD's tangency window) are all measured from the survey and kept only where it proves them, Redo to refit -- then a standard-hopper bottom.  An `OAsis` is fitted with OASIS's own ring solver against OASIS's own five families, and everything OASIS has to ask about a shape is measured instead: the frame is swept right round the pool (an oasis has no walls to vote on it), the envelope falls out of the bounding box, and every joiner is carried as a curvature so a cloud's flat bottom is the one whose radius came out infinite -- found, not declared, as is which way a kidney was given. `FITABHDCOVER` skips that bottom question for a cover sheet |
| `BPCALLOUT` | `lisp/bpcallout/` | Rings clicked bad points with 5" circles on `FGStep` and writes a "Pt.12, Pt.15 and Pt.20 are bad" callout |
| `CDCALLOUT` | `lisp/cdcallout/` | Cross-dimensions from Pt.## to Pt.## by typed number - `CROSS DIMENSIONS` style, `DIMENSION` layer, repeat until Enter. **Every tie is its own pair**: a drawn dimension goes back to the FROM prompt, so the next one names both of its points and nothing carries over between runs. v1.7 chained off the last TO point instead, which is not what cross dims are - they are whichever two points the drafter wants tied, in whatever order the sheet needs them |
| `ABFIND`, `ABMOVE`, `ABFINDVER` | `lisp/abfind/` | Ties a point (typed by number or clicked) back to the **A** and **B** survey stakes with a cross dim to each, then asks whether that point wants moving. `ABMOVE` takes one point and also offers every place it lands if one tape was read wrong - the moved tape swept a foot at a time, ten feet each way, plus the look-alike readings (`21'-1"` written as `21'-7"`, the 1"/11" slip, transposed feet) - drawn yellow, tagged by the tape they move (`1A`, `-3B`), each tag hung off the arc on a leader so it can be read and clicked where the markers crowd, each group on the dashed grey arc it sits on; a click takes the nearest marker or tag, and asks which when the zoom cannot tell two apart - and copies it to `Pt.##m` - the same block, layer, colour, scale and attributes, one number different - rings the old spot with a 5" circle on `FGStep` and writes the `Moved Pt.17 B from 18'-6" to 18'-5"` note |
| `ABCDEF`, `ABCDEFVER` | `lisp/abcdef/` | Locates Excel-measured points inside rectangle corners A/B/C/D, "Z" reading order (A/B top, C/D bottom).  Two tapes place a point, three fix it, four cross-check it; a fourth tape is dropped only when leaving it out settles the other three **and** the runner-up triple is clearly worse, so a point near a diagonal keeps all four rather than discarding a good tape.  Reports per point how many tapes placed it, which, and a measured 1-99% confidence, to the command line and to a text file beside the sheet.  Plots as `ab_pt` blocks on `POINTS` and offers `ABHD` the set |
| `ALTABCDEF`, `ALTABCDEFVER` | `lisp/altabcdef/` | Same idea, clockwise A→B→C→D corner order instead - kept separate from `ABCDEF` because the two conventions aren't interchangeable.  Two distances are crossed exactly and a pair from *opposite* corners, which fits two points equally well, is named rather than guessed at; the frame is measured against the dimensions entered before anything is plotted |
| `XYPLOT`, `XYPLOTVER` | `lisp/xyplot/` | `ABCDEF`'s sister for a survey that arrives already reduced: a sheet of X/Y offsets, one picked origin, drawn twice - graph 1 the points as given (`ab_pt` on `POINTS`, ready for `ABHD`), graph 2 the same points with the X and Y offsets dimensioned as two continuous linear chains |
| `CONSTELLATION`, `CONSTELLATIONVER` | `lisp/constellation/` | For the sheet that gives distances BETWEEN points and never says where any of them is. Define a rectangle of known X and Y the points have to sit in, say how many there are - `A` to `Z` - and they are shown clockwise from the top left, evenly spaced round the oval inside it, so you can see which letter is which. Then every pair (`A-B`, `A-C` ...) is on offer and none is compulsory: give the ones the sheet carries, in any order, Enter to walk the chart or type `A-C` to jump. Two dims on every point, and a chain reaching all of them, is the one thing required - short of that the chart is refused by name rather than solved into a plausible-looking wrong answer. Solves in two stages - stress-majorization sweeps to find the right answer, then damped Gauss-Newton to land on it EXACTLY, because sweeps alone converge linearly and a barely-rigid chart (a ring plus two diagonals, an ordinary field sheet) left a given dim 0.19in out after 400 of them and then blamed a tape for it; the same job is now exact in seven Gauss-Newton iterations - so a set of tape readings that cannot all be true still gets the layout that misses by least and the misses get STARRED in the report - and because least squares SPREADS a bad tape over every dim touching it, the worst one is then left out and the chart re-solved, so when that settles the rest the report names the single dim to go and re-measure instead of starring nine innocent ones. Nothing is dropped from the drawing. Distances say nothing about handedness or rotation, so both come off the preview: the mirror that reads clockwise, turned to fit the space and centred in it. A run of points that lies on ONE radius can be declared too, named CLOCKWISE (`A-C`, `ABC` or the wrap `Z-B` = Z A B) - to the solver that is just another point, the arc's centre, a dim of R from every point on it, and it pins what cross dims leave loose: six dims on five points settle the radius end at R139.6 with every dim exact, and declaring the arc lands it on R150.0000. Two points and a radius leave two centres, so that one run alone is asked which way it bows. Draws `ab_pt` points on `POINTS` ready for `ABHD`, an aligned dim per dim given - perimeter dims standing off, cross dims down the chord - and the outline if asked, bending round any arc declared. It then asks whether the drawing looks right, because a number typed wrong is invisible on the chart and obvious on the sheet: `No` reopens the dims, the arcs or both, takes the wrong drawing away and puts the corrected one down |
| `ABPCHECK`, `ABPCHECKRESCUE`, `ABPCHECKVER` | `lisp/abpcheck/` | `ABHD`'s measuring half, forked as a checker: highlight the whole drawing, say how far off the line is too far, and every survey point is reported with the distance to the nearest line -- `Pt. 17   closest line is 0'-1 7/8" away` -- worst first, the ones over the limit in red and ringed in the drawing. Measures to the run itself, arcs included, not to its endpoints. `ABPCHECKRESCUE` takes the report and the rings away again |
| `POINTRENAMER`, `POINTRENAMERVER` | `lisp/pointrenamer/` | Hands the survey point numbers back out in the order the perimeter runs: highlight the area, Enter takes the closed `POOL` polyline it finds (or pick any polyline, circle, line or arc), click where the count starts, say `Clockwise` or `COunterclockwise` -- meaning on the sheet, whichever way the polyline was drawn -- and how far off the perimeter still counts as on it. Every point within that band is renumbered sequentially sweeping from the pick; whatever sits beyond it continues the count after the loop is closed, swept in the same direction by where each sits against the perimeter, so the leftovers read round the sheet too. Shows the split and asks before writing, prints the old-to-new table so a callout can be chased, counts out loud what carries no number to rewrite (plain `POINT`s, attribute-less blocks) and warns when a point outside the highlight already holds a number in the handed-out range. A number that could not be written -- a locked layer, usually -- is marked `NOT WRITTEN` on its row and counted, rather than reported as a rename that happened. Every knob it has sits in one explained block at the top of the file. One `U` undoes the lot |
| `LOBF`, `LOBFVER` | `lisp/lobf/` | The line of best fit through points that are all meant to be on ONE line - a wall shot at eight stations, a row of deck anchors. Draws three construction lines at once, each in its own colour and numbered on screen on a stalk so no label can be read against the wrong line, and you keep one: **1** least squares on the perpendicular distances, every point pulling on it (not the `y`-on-`x` a spreadsheet gives, so a wall running north-south fits as well as one running east-west); **2** the same fit with a single point set aside - every point tried as the one to drop, the drop that leaves the REST tightest winning - so the error stops being shared and piles onto one point, which is ringed and named for re-measuring; **3** the least-MAX fit, the narrowest band that still holds every point with the line down its middle, tried against the edges of the points' convex hull because that is where the narrowest band always sits. Enter takes fit 2 when the point it set aside is DRASTICALLY worse than the ones it kept - four times the worst of them and at least 1/2" off in its own right, both halves, so a survey that is all inside a sixty-fourth does not get one of its points blamed for noise - and fit 1 when no point stands out that way. The table prints the numbers that decided it either way. Two points make exactly one line, so the picker is skipped; a cloud whose worst point is more than a fifth of the run off the line is called out as maybe not one line at all |
| `CHECK`, `DIMARCCHECK` | `lisp/check/` | Audits dimension def-points and arc endpoints against real geometry, fixing strays |
| `DIMCHECK`, `DIMSCAN`, `DIMCHECKVER`, ... | `lisp/dimcheck/` | Guided, one-at-a-time review of dimension placement, arc-end attachment and overlapping lines, grouped by dimension style |
| `LINFINCHECK`, `LINFINSCAN`, `LITELINFINSCAN`, ... | `lisp/linfincheck/` | `DIMCHECK`'s checks plus steps & side views, wall height, the liner pattern and the title block border - the full liner-finish drawing QA. The report leads with the liner checks; the `DIMCHECK`-style findings sit in a DIMENSION AUDIT column beside it, and `LITELINFINSCAN` skips them entirely for a drawing `DIMCHECK` already went over. The two things it does not just report it FIXES: a pattern field reading `Not Supplied` or `#ERROR` has that phrase - and only that phrase - taken out of it, so `Pattern: Not Supplied` reads `Pattern:` and `Blue Granite - Not Supplied` reads `Blue Granite`; and a `Tech Title` date that is missing, malformed or simply not today is rewritten to today as `MM/DD/YYYY`, label and all. The scans say NEEDS WIPING / NEEDS UPDATING and write nothing |
| `COVERCHECK`, `COVERSCAN`, `LITECOVERSCAN`, ... | `lisp/covercheck/` | Same guided review, rules swapped for pool-cover QA; same split report, with `LITECOVERSCAN` as the cover-rules-only scan. The cover rules only ever SUGGEST, with one exception: a wrong `Tech Title` date is rewritten to today as `MM/DD/YYYY`, keeping any `Date =` label - `COVERSCAN` says NEEDS UPDATING instead |
| `SPACHECK`, `SPACHECKSCAN`, `LITESPACHECKSCAN`, `SPACHECKRESCUE`, `SPACHECKVER`, `TUTORIALSPACHECK` | `lisp/spacheck/` | The same guided review for spa sheets: audits a drawing against what `SPA` draws - bounded outlines, the dimension roster and its notes, hinges against the block's grade/taper and the Hinge Arrangement Chart, and a title block at exactly 0.6x the liner block. A wrong `Tech Title` date is rewritten to today as `MM/DD/YYYY` rather than left to be noticed; the scans say NEEDS UPDATING and write nothing |
| `CCPRECHECK` | `lisp/ccprecheck/` | Walks the "Tech Flow Chart" product-type decision tree and prints a summary. Renamed from `CHECK` to resolve a name collision with `lisp/check/` |
| `LAZDIAG`, `LAZDIAGVER` | `lisp/lazdiag/` | When any calofin command fails, the drafter is told so in as many words and the whole failure is written out as a DXF in their Downloads folder - `POOL-v2.7-error-2026-09-11-143207.dxf` - to send in for diagnosis. The file holds a copy of the geometry the run drew and of whatever it was working on, every point that was clicked labelled with the prompt it answered, the transcript prompt by prompt, the error text, the last step reached, and AutoCAD's own `ERRNO` / `CMDNAMES` / `LASTPROMPT` and sysvars. Nothing is asked and the open drawing is not touched. `LAZDIAG` typed by hand writes the last failure's report again - useful when the folder was read-only the first time - and, with nothing to report, writes a self test instead, which is how you find out reports will reach you BEFORE you need one. Only if no folder at all will take the file does it offer the last resort: pick a spot well clear of your work and the report is placed in the current drawing as text |
| `LINCHECK` | `lisp/lincheck/` | Companion checklist routine, shipped alongside the flowchart walker |
| `STOCKCOVER`, `STOCKCOVERVER`, `STOCKLIST`, `STOCKCOVER-CFG` | `lisp/stockcover/` | Replaces a highlighted perimeter with a stock cover drawing pulled straight out of the stock DWG folder, lined up on what was highlighted |
| `MATCHSTD`, `MATCHSTD-CFG` | `lisp/standards_checker/` | General-purpose drawing-standards matcher/checker (modular: config, cache, geometry, tolerance, UI) |
| `LINTXTCHK` | `lisp/lintxtchk/` | Places the vinyl-liner QA checklist into the drawing as text |
| `CORNERSTP`, `HEMISTEP`, `NORMIESTEP`, ... | `lisp/cornerstp/` | Corner-step layout routines for pool corners - three files here, one `STEPS` release (see below). Where a run sits is read off the geometry, never guessed: NORMIESTEP's corner mode puts the steps in a recess OUTSIDE the corner, because the two lines you select run away from it into the pool, and it draws both sides of that recess; HEMISTEP's side profile reads FROM THE WALL, so the first depth it asks is the drop at the wall and the first tread the flat against it |
| `PADDLE`, `TUTORIALPADDLE` | `lisp/paddle/` | Finds concave perimeter features and inserts pad blocks |
| `LINGUTTER`, `LINGUTTERSCAN`, `LINGUTTERVER` | `lisp/lingutter/` | Guts a highlighted area back to the pool and nothing else. Inside the highlight -- and only inside it -- it walks the **outer face** of the lines, arcs and polylines and draws its own perimeter over it: ends closer than a snap tolerance count as one point, and the walk always takes the hardest available right turn, so interior geometry (hopper, steps, a tie line) is never stepped onto and an outward spur is pruned. Three snap tolerances are tried in turn and the result is measured against what was highlighted before it is believed, so an outline with a gap in it can no longer be quietly replaced by a hopper that did close; when no exterior can be walked at all it wraps the highlight in its convex hull and says so. The perimeter is redrawn as one closed polyline on `POOL` (ByLayer, arcs kept as bulges); everything else highlighted is erased, except dimensions in `CROSS DIM*` wherever they sit and `STANDARD` / `SIDE STANDARD` ones whose every attachment point lands on that perimeter. The new perimeter then goes to `PADDLE` as a pickfirst selection, so it pads that loop rather than auto-detecting past it. It reports what it found and what it would drop -- by style, so nothing goes silently -- and asks before erasing, defaulting to `No`; `LINGUTTERSCAN` prints the same report and changes nothing |
| `PERPPTS`, `CPERPPTS`, ... | `lisp/perp_points/` | Perpendicular offset points along a line or curve, joined with straight segments, arcs or a mix of both; asks whether the overall width has been re-measured, and has a repeat-on-the-new-polyline step |
| `AUTOBEAD`, `AUTOBEADVER`, `TUTORIALAUTOBEAD` | `lisp/autobead/` | Offsets ("beads") selected pool lines toward a clicked side |
| `DCE`, `DIMCONTEND` | `lisp/dim_continue/` | Chains `DIMCONTINUE` from a seed dimension out to every remaining feature point |
| `AUTODIM`, `FLOORDIM`, `STAIRDIM`, `AUTODIMSIDEPOV` | `lisp/autodim/` | Auto-dimensions a highlighted plan - perimeter sides and arc radii, stairs, the floor dims it asks about, two overall dims. A size that repeats is called out once and noted `Typ.` (from two equal sides, or four equal radii). Perimeter and stairs `SIDE STANDARD`, floor and overall dims `STANDARD`, anything under 12" `STANDARD INCHES`; a place that is dimensioned already is left alone. Highlight a flight of steps drawn in side view instead and `AUTODIM` recognises it and dimensions the depth of every step down the right in `STANDARD INCHES` |
| `SMARTFILLET`, `SMARTFILLETVER` | `lisp/smartfillet/` | Fillet a corner after showing what each radius would look like: pick the two lines and every radius that fits - 6 up in 6s plus the 3 and the 9 that turn up but are not the step, tangent points landing on both legs - is drawn as a lettered arc. The fan is graded light green to dark green with the radius, each arc part transparent so the ones crossing underneath still read, each label in its own arc's shade and one rung further off the leg than the label before it; the odd sizes are dashed where the sixes are solid. Click one and that corner is cut for real and given its radius dimension; it then offers the same radius for the rest of the corners, and the one callout becomes `R12 Typ.` as soon as a repeat is cut |
| `HONEFILLET`, `HONEFILLETVER` | `lisp/honefillet/` | SMARTFILLET's spinoff for the sizes BETWEEN its radii, for a corner that wants something the 6-inch step cannot say. The same corner picks and the same fan, and then instead of cutting the one clicked it asks for **two**, either side of the size wanted, and redraws just that range in half-inch steps - both ends included, so settling back on the round number is still one click, and the whole inches solid against the halves dashed. Click one of those and it is cut, dimensioned `R13.5` rather than rounded to suit the tool, and offered for the rest of the corners exactly as SMARTFILLET offers a round one. Two picks that are not neighbours are turned down and asked again rather than truncated: what counts as neighbouring is `hn:*maxfine*`, how many honed previews can be read at once |
| `CDCREATE`, `CDCREATEVER` | `lisp/cdcreate/` | Turns every highlighted line into a cross dimension - `CROSS DIMENSIONS` style, `DIMENSION` layer, dim line on the line, text 80% toward the right/bottom end, source line erased. A tie that is dimensioned already is left alone |
| `CUSTBLOCK`, `CUSTBLOCKVER` | `lisp/custblock/` | Draws a custom block in pictorial view from three typed sizes - length (the long axis, receding back-right at 45 degrees and at true length), width across the front face, height up it - based at its front bottom left corner. Nine lines on `COVER`: the front, top and right-hand faces, with the three hidden edges left out so it reads as a solid rather than a wire cage. Dimensioned three times on `DIMENSION` in `STANDARD INCHES` - the length aligned along the top-left receding edge, the height and width linear with their axes forced |
| `DRONE` | `lisp/drone/` | Drawing cleanup: text style/height, pool/spa points onto `POINTS`, spa perimeter onto `POOL`, and more in one pass |
| `TYDRN`, `TYLERDRONESUITE` | `lisp/tydrn/` | `DRONE`'s pool-only sibling for a drone trace with no spa: the same text and point cleanup with no SPA-point sweep and the `SPA` layer never touched (see `lisp/tydrn/README.md` for the exact split). `TYLERDRONESUITE` is the whole drone trace in one: `TYDRN`, then `PADDLE`, then the shop's own `CDIM`, in the order the work has to happen in - the points have to be on the right layer before `PADDLE` can find the features to pad, and `CDIM` finishes over whatever dimensioning the drawing carries (`AUTODIM` sat in this flow once; its operator wants it out, and `*tydrn-suite*` puts it back). The trace is highlighted ONCE and carried: the calofin stages want the same thing picked and AutoCAD clears the pickfirst set as soon as a command consumes it, so the suite reads it at the start and puts it back before each stage - grown by what each stage drew, so a later stage opens with the earlier ones' work. CDIM gets a cleared selection, since the dimensioning it tidies is in nobody's original pick. Nothing is reworded: each stage is the command itself, asking its own questions, and each keeps its OWN undo group, so one U per stage backs the suite out and a stage that went well is not undone to get at one that did not. The calofin stages are checked before any of them runs - half a suite is worse than none; `CDIM` is not (`boundp` cannot see a .NET or PGP command); each calofin stage is its `c:` function called directly - the command processor does not know AutoLISP commands, so `command`/`vl-cmdf` would say Unknown command - and `CDIM` is queued on the command line verbatim via `SendCommand`, the one door .NET, ARX and PGP aliases all answer to, unless AutoLISP defines it here. `*tydrn-finish-cmd*` renames it or turns it off |
| `VSCONV`, `VSRECONV`, `VSCONVVER` | `lisp/vsconv/` | Converts a VS survey export onto the shop layers in one pass: the exporter's numbered layers are remapped by `*vsconv-map*` -- `1 Perimeter`, `2 Coping` and `3 Features` onto `POOL`, `3.1 Anchors` onto `POINTS`, `4 Dimensions` onto `DIMENSION` -- with color, linetype and lineweight forced BYLAYER (`*vsconv-force-bylayer*`, on by default; `SOCONV` carries the same switch off, each for what its sample does) so the moved geometry takes the destination layer's appearance rather than the export's. The dimensions are then put on `STANDARD` **and stripped of their style overrides**: the export writes text height, arrow size and decimals into each dimension as `ACAD`/`DSTYLE` xdata, and an override outranks the style it sits on, so a dimension merely renamed would still draw in the export's 2.5-unit text. Scope is the highlight, or Enter for every VS layer in the drawing; a drawing carrying none of them is reported as such instead of prompting. The emptied source layers are named in the done line rather than purged, so one `U` backs the whole run out. **`VSRECONV` undoes the whole thing**, and not only while the session lasts: every object the conversion moves carries a record of what it was in its own xdata -- the layer it came off and that layer's colour, the colour, linetype and lineweight the BYLAYER forcing overwrote, and for a dimension the style name AND the `ACAD`/`DSTYLE` override block kept verbatim -- so a drawing saved, closed and reopened a week later still goes back exactly as it arrived, overrides and all. `*vsconv-record*` is the one line that turns the record off |
| `WCALST` | `lisp/wcalst/` | Unrolls a curved constant-width band flat, with darts/inserts |
| `XFTCONV`, `XFTRECONV`, `XFTCONV-SETUP` | `lisp/xftconv/` | Cleans up a survey import in one pass: scale it ×12 (feet → inches) about the middle of the highlight, then swap every point marker for an `ab_pt` block on `POINTS` with its number in the `number` attribute. Two exports are read, whichever is in the selection: a **Leica XFT** import, whose marker is an X of two `LINE`s on `LEICA_POINT` with the name stacked above it on `LEICA_POINT_NAME` (`P22` → `22`), and a **site trace**, whose marker is a small `CIRCLE` on `POOL_POINTS`, `BREAK_LINES` or `CROSS_MEASUREMENTS` with the name sitting on the centre. A trace draws each corner twice - once as a pool point, once as the end of a diagonal - and the pair collapses into one block; its labels keep their family letter (`C1`, `S1`, `D1` would all strip to `1`). Leftover text is swept for the Leica flavour, whose text is nothing but point names, and kept for the trace, which captions its own break lines and diagonals. **`XFTRECONV` puts the survey back** -- markers, name text, swept text and the ×12 -- because each block it inserts carries a record of what it replaced in its own xdata, so the undo survives the drawing being saved and reopened where `U` does not. A highlight holding two conversions is refused by name rather than half-reverted: they were scaled about different base points, and one scale back cannot undo both |
| `SOCONV`, `SORECONV`, `SOCONVVER` | `lisp/soconv/` | Puts an SO site-survey export onto the shop's layers in one pass: `Pool Perimeter` and `Obstacles` onto `POOL`, the Leica points and `Existing Anchorss` onto `POINTS`, and the export's one `Dimensions` layer split in two - its notes onto `TEXT`, its dimensions (and anything else left there) onto `DIMENSION`. It is a layer remap and ONLY a layer remap: no restyle, no forced BYLAYER, no rotate, nothing erased and nothing drawn - which is what the before/after sample it was written from does, pair for pair over 316 objects, and `*soconv-force-bylayer*` is the one line that changes its mind. The rules are a table (`*soconv-map*`), read in order with the first match winning, so a shop whose export names things differently retunes there and nowhere else; only the destination layers a run actually reaches are created. It converts the whole drawing unless something is highlighted, reports the counts per destination, and names the emptied export layers for you to `-PURGE` - it will not purge them itself. **`SORECONV` moves it all back**, from a record each moved object carries in its own xdata (the layer it came off, that layer's colour, and - only when `*soconv-force-bylayer*` was on - the three properties the forcing overwrote), so the undo outlives the session `U` is good for; a source layer purged on the tool's own advice is re-created with the colour the record kept |
| `G2MCONV`, `G2MRECONV`, `G2MCONVVER` | `lisp/g2mconv/` | Converts a G2M architectural pool plan - AIA layer names with a Spanish half after them (`A-STAIRS - GRADAS`), the architect's own text and dimension styles, an annotative flag on every dimension - onto the shop's layers AND styles in one pass. Five rules in a table (`*g2mconv-map*`), first match winning: the pool wall and the stairs onto `POOL`, the architect's text layer onto `TEXT`, and his one annotation layer split in two - its notes and leaders onto `TEXT`, its dimensions (and anything else left there) onto `DIMENSION`. Where `SOCONV` is a layer remap and nothing else, this one also removes the three overrides that would otherwise outrank the layer or style the object now sits on, because that is what the before/after sample does object for object: the explicit `Continuous` comes off the geometry and the linetype scale goes to the drawing's own `CELTSCALE`, the notes take the shop text style and height (both or neither - a height is measured for the style it is set in), and the dimensions take `STANDARD`, lose their `ACAD`/`DSTYLE` block and stop being annotative. The stairs are the exception the table exists for: they arrive in the architect's `HIDDEN2` and land on `POOL` in the shop's `DASHED2` rather than going ByLayer, because a stair drawn solid on `POOL` is a wall. **`G2MRECONV` puts all of it back** from a record each moved object carries in its own xdata - the layer and its colour, the four appearance properties, the text style and height, the annotative flag, and for a dimension the style name and the whole override block verbatim - so the undo outlives the session `U` is good for; a linetype or style the record names that the drawing no longer has leaves that object's record in place and is named in the report, so restoring it and running again finishes the job |
| `DDGPS`, `DDALT`, `DDELEV`, ... | `lisp/drone_height/` | Computes drone height above grade and lens distortion from photo GPS/EXIF |
| `LISPLAB`, `LISPLABVER` | `lisp/lisplab/` | Learn AutoLISP, not a drafting tool: two lessons - getting things out of the drawing databases (`entget`/`ssget`/the symbol tables/dictionaries/xdata), and putting a list in order (`vl-sort` and its duplicate trap, then bubble, selection, insertion, merge and quick sort written out). Each is an outline plus a worked example that draws a sample and sorts what it reads back |
| `LAZFORM`, `LAZFORMCOVER`, `LAZTXT`, `LAZASCII`, `LAZFORMVER` | `lisp/lazform/` | Fill a dimension chart in and draw the pool from it. Thirteen charts, and two routines behind them: eight POOL sheets - Rectangle, True Oval, Roman, both Grecians, True L Left, Round and Octagon - and five OASIS ones - Center, Top-Right, Cloud, Kidney and NXT Cloud - each the one off the paper: outline, hopper, dimension chain with its letters. The picture is one whole passive image and **every dimension has a labelled box in the column beside it**, with its letter as a button in front of it: the picture is read, the column is typed into, and the letter ties the two together. (v1.6 to v2.5 sliced the chart into bands and wedged the across-chains between them; it came apart into strips, the boxes were only ever placed to within a character cell, and a sheet read as two kinds of thing at once.) Corners get a dropdown each - `Square`, `Radius`, `Cut`, `NotGiven` - and the size box beside it un-greys only for `Radius` and `Cut`; Roman carries four rows, the Grecians and the Octagon carry two collective ones (body corners, end-tip corners) that fan out to the eight individual questions when the pool is out of square, and picking any of them arms POOL's own corner-record gate. Cross dims have a mode dropdown and their boxes, out-of-square only. Fill in what you know, leave the rest blank, press Insert: the page's own routine runs and asks only for the gaps. **One rule decides what is live**: the bottom type, the in-square toggle and the mode dropdowns together compute the dead set, `mode_tile` greys exactly it, and exactly it is withheld from POOL - so a greyed box cannot be a value that travels and is never read. The bottom half of that rule is read off POOL's own `pool:btmspec`, so it cannot drift: a Normal hopper draws no side view, so C, D and C2 grey out; a Sport asks a different plan chain, so H, F and E grey out and its own E2-F2-F1-E1 boxes come alive. The oasis sheets read the same way off their own two dropdowns - a cloud's bottom or a kidney's type, and simple-or-complex - and hand their answers to `OASIS` instead: an oasis has no chain and no hopper, so the sheet is the envelope, X across and Y up, with a radius against every arc; a bulge's radius is drawn where it runs and a joiner's gets a leader out to its letter. Those outlines are not artwork either - each is the ring `oasis:solve` builds for that shape's reference drawing, and the test suite re-derives every arc from OASIS and compares. `NA` in a box means not measured and is passed through as such; a blank box just means ask. **A state line under the form says what it is about to do**: `lzf:answer` turns anything it cannot read into not-answered, so a typo used to be dropped in silence while the chart went on showing it - the chart draws the string - and POOL asked again with no reason given. The line names any box in that position by the letter the sheet prints, and `Insert` stays greyed until it is fixed; with none, the same line is the hand-off - how much is filled and which letters POOL will still ask for. It reports `lzf:form` rather than second-guessing it, and the test partitions every live box into sent, still-to-ask and unreadable, so the line and the alist cannot drift. **`Recall last`** puts the last accepted sheet for this chart back into the EMPTY boxes only - safe to press twice, never a default, greyed when there is nothing stored - and the static hint now says what a box takes (`24`, or a feet-and-inches spelling). Drawn with `vector_image` from a table of lines, so there is no artwork file to ship. `LAZFORMCOVER` is the same form for a cover sheet: POOL runs with its pool-bottom gate already closed - `LAZTXT` is the same form drawn out of TILES instead of vectors - the pool is a real boxed cluster with the hopper nested inside it and the fields in the drawing, which buys retention (nothing in it is an image tile, so nothing in it can be wiped by a repaint) at the cost of the outline being a rectangle whatever the pool is. `LAZASCII` is a probe, not a tool: it asks whether this AutoCAD's dialog font is fixed-pitch, which decides whether the chart could be drawn in characters instead of vectors - worth knowing because DCL never retains an image tile but always retains a text one - see `lisp/lazform/README.md` |
| `LAZSPA`, `LAZSPAVER` | `lisp/lazspa/` | `LAZFORM`'s argument applied to `SPA`: fill a chart in, press Insert, and the spa is drawn. Three charts - Rectangle, Octagon, Round - with the boxes wedged into the dimension rows, which is the layout LAZFORM carried at v1.6-v2.5 and has since moved off. The Rectangle carries its four corner dropdowns, labelled the way the sheet legend spells them (`90`, `Radius`, `Diagonal`); SPA itself now asks the canonical `Square`/`Radius`/`Cut`/`NotGiven` and normalises the legend words on the way in, so the chart keeps the drafter's vocabulary and the routine keeps the standard's. Every page also carries the water's-edge/cover-size mode, the second outline (by offset or by dimensions, keyed per shape), the lap gap, auto-hinge, and the grade and taper the Spa Cover Details block would otherwise be read for. Two traps are handled rather than inherited: SPA stores a form's `nil` without validating it, so `NA` on a question that must have an answer is demoted to an empty box instead of reaching arithmetic; and the Round flow only *peeks* at `A`, so filling it is what asks for an out-of-round spa - which is what the label says. The block pick and the base point stay in the drawing. **Its state line has a third thing to say**: SPA drops a box unread two ways - `lzs:answer` cannot read it, or `lzs:keyanswer` demotes an `NA` on a key SPA has no NA for, which is the sharper one because `NA` is a word the form itself tells you to type. Both are named on the line and both grey `Insert`. **`Recall last`** puts the last accepted sheet for this chart back into the EMPTY boxes only - safe to press twice, never a default, greyed when there is nothing stored - and the static hint now says what a box takes (`24`, or a feet-and-inches spelling). - see `lisp/lazspa/README.md` |
| `LAZSTEP`, `LAZSTEPVER` | `lisp/lazstep/` | **Say how many steps, then fill the drawing in.** Page one picks the step type (`CORNERSTP`, `HEMISTEP` or `NORMIESTEP`), takes the count, and asks that type's once-only questions - direction, bench, corner treatment, the width that is the same for every step. Page two is then *built for that count*: the plan with N treads and their widths, and the side profile with N risers and the N+1 drops, every dimension carrying its letter until you type a number over it. Change the count and the drawing is regenerated, keeping what still has a step to belong to. This is what the step routines could never be asked before - they had no count, only a tread prompt you stopped answering - so the stores take one now and the form supplies it. Eight steps is the ceiling, and past four the tread chain staggers onto two rows, because DCL will not scroll a dialog wider than the screen. The walls, the curve, the side to draw toward and the profile's pick all stay in the drawing. **Each page states itself and holds its own button back**: page one reads a measurement with `lzt:answer` and the count and bench step with `lzt:int` - `3.5` is the case that separates them, a fine measurement and not a step number - and `lzt:countwhy` is the one rule both the live warning and the refusal at the gate read, so they cannot disagree; page two's line is the hand-off, named by the letters the drawing shows. **`Recall last`** puts the last accepted sheet for this chart back into the EMPTY boxes only - safe to press twice, never a default, greyed when there is nothing stored - and the static hint now says what a box takes (`24`, or a feet-and-inches spelling). - see `lisp/lazstep/README.md` |
| `LAZPANEL`, `LAZBUTTON`, `LAZPIN`, `LAZICON`, `LAZPANELVER` | `lisp/lazpanel/` | A clickable button panel with the 80 headline drafting commands above - the zero-install GUI: the dialog is plain DCL that the file writes for itself at run time, so there is no DLL to `NETLOAD` and no second file to ship. Loading it also puts a one-button toolbar ("LazPanel", an orange hexagon it generates itself) on screen that you can drag anywhere or dock - click it to open the panel, or `LAZBUTTON` to re-summon it. A **Find** page leads: type any part of a name **or of its caption** and the list narrows to what matches, with the top hit selected so Enter runs it - searching the captions is what makes `survey` find `ABHD`, which says nothing about surveys in its name, and the needle is taken literally rather than handed to `wcmatch`, so a typed `*` searches for a star. Tabs then come in two rows: the **jobs** (Pool / Cover / Spa / Rest), each laid out in columns that follow the work - read somebody's export in, shape, points, steps, dims and check. **Pool and Spa lead with a Converters column** (`XFTCONV`, `SOCONV`, `VSCONV`, `G2MCONV`, with the four matching `RECONV`s in the same order in a run beneath them, so the Nth button below undoes the Nth above): that is where reading somebody else's drawing falls in the work, and it is where they were hardest to find - two of the first three were reachable only from `Rest`, and `XFTCONV` sat under Shape, which it never was - and the **categories** (Layout / Points / Dimensions / Checking, the same four group names as the VB palette) holding the whole roster filed by what each tool is. A tool that serves two jobs sits on both, so 80 commands make 184 buttons; `Rest` is computed as whatever the three named jobs leave over. A command not loaded in this session is greyed out - except on Find, which lists it marked `(not loaded)` and refuses to run it with that reason, because a search that omits what you searched for reads as the tool not existing. A click closes the panel, runs the command exactly as if typed, and the panel then REOPENS itself on the same page at the same position - Close is the way out. A **Pinned** row on every page carries the few tools you run all day, remembered between sessions in the registry; `Pin...` or `LAZPIN` edits it. Above it a **Recent** row carries the last five you launched, newest first, kept without being asked - minus anything already pinned, since Pinned is by definition the tools you run most and showing them twice would leave Recent saying nothing new; it appears only once there is something in it, so a first-run panel is no taller than it ever was. Off the panel on purpose: the satellites (`TUTORIAL*`, `*VER`, `*RESCUE`, `-CFG`/`-SETUP`, `DCE`, `STOCKLIST`), the `DD*` drone-height toolset, `LISPLAB` and the deprecated matcher - see `lisp/lazpanel/README.md` |

### Going back a step

Interactive tools share one convention for backing out of a mis-typed
answer: the keyword is **Back** (type `B`), it is always shown in the
prompt's bracketed options (`[Back]`, `[Yes/No/Back/Skip]`, ...),
and it re-asks the previous question - re-running whatever lookup or
computation sits in between, and backing out of a sub-block (a `POOL`
measurement block, a `CCPRECHECK` branch) into the question that
opened it. **Undo** (`U`) is accepted everywhere Back is, as an
unlisted synonym. Typed prompts - notes, offsets, feet-inch
dimensions - cannot take keywords, so there Back is typed like a
value: `B`, `BACK`, `U` or `UNDO` alone, any case (the prompt says
so). The first question of a command has nothing to go back to, so it
never offers Back.

A question that is only asked on some runs is stepped OVER on the way
back rather than stopped on, so Back always lands on the last question
you were actually asked. `CORNERSTP` announces six settings but puts
two of them only when the corner has a diagonal; Back at the third
lands on the first when it does not. Answers a form supplied are spent
as they are read, so backing into one of those asks it at the keyboard
instead of answering it again and walking straight forward.

In loops that draw as they go - `PERPPTS`/`CPERPPTS` offset points,
`CORNERSTP`/`HEMISTEP`/`NORMIESTEP` treads, `ABHD`/`ADAB` slope
waypoints and declared walls, corners and held points, `LHD`
declarations, `CDCALLOUT` dimensions, `ABFIND` ties, `AUTOBEAD`
beaded steps, `ABCURCHECK` discontinuities - Back
also removes the
just-committed point or step (its lines and its dimensions) before
re-asking. At the FIRST item there is nothing left to remove, so the
question that opened the loop is asked again - which is how a wrong
Yes gets undone. `BPCALLOUT` works by
reselection instead: clicking a ringed point again un-rings it, and
Back at its callout text re-opens the picking.
Feedback wording is shared too: `Stepping back one
<point|step|dimension|question>.` on the way back, `Already at the
first <point|step|dimension>.` when there is nowhere left to go.

Every interactive multi-step tool supports this, with three
boundaries:

* **Selections.** AutoCAD object selections cannot take keywords, so a
  command whose only remaining input is a selection (`PADDLE`,
  `DIMCONTEND`) has no prompt left that could offer Back - and Back
  cannot be *typed at* a selection either. Where a question sits
  straight after a selection with nothing else in front of it, Back
  there **re-opens the selection**: `WCALST`, `XFTCONV`, `AUTOBEAD` and
  `AUTODIM` have always done this, and `CABHD`'s point cutoff and
  `LHD`'s output height do it now. Nothing has been drawn at that
  point, and the classifier rebuilds every list it fills, so the second
  pass starts clean.
* **Past the drawing.** Once a run has committed geometry, Back at the
  next question would have to erase rather than re-ask, so it is the
  draw-as-you-go rule that applies instead: Back at the prompt *inside*
  the loop takes the last step back, drawing and all. That is why
  `CORNERSTP`'s step WIDTH offers no Back (the tread prompt for the
  next step takes the whole step back), and why the side-profile and
  bead questions that follow a finished run do not. A question asked
  once the undo group is open is the same case - which is why
  `HEMISTEP` now asks its width at the wall BEFORE opening one, so it
  can re-open the dimension question in front of it.
* **A re-ask that is already a correction.** `pool:ask` and `psd:ask`
  re-ask a measurement that failed a range check; Back there would step
  out of the check rather than back a question, so they do not offer it.

One more rule decides whether Back is *offered* at all: a question the
run would answer the same way twice cannot be gone back to. `ABFIND`
asks for its B stake with Back only when the A stake was CLICKED - when
the drawing numbers a point with A's own name, ABFIND finds it instead
of asking, and re-asking would find the same point again and walk
straight forward. That is a deadlock, not a way back, and it is the
same reason a form-supplied answer is spent as it is read.

Everything else in the tree either offers Back today or is written down
in `tools/back_baseline.txt` with the reason it does not - one line per
prompt, and `make check` fails on a new one-way prompt that is not
there. `tests/test_back_nav.py` walks the threaded chains themselves,
at both tiers.

New prompts should follow this convention - it is
part of the shared prompt standard in [STANDARDS.md](STANDARDS.md), and
`tests/test_back_nav.py` holds it: the static half reads every `.lsp`
for the invariant the prompt text cannot show you (Undo beside every
Back, the typed `B`/`BACK`/`U`/`UNDO` predicate, case folded, and no
file that takes the keyword and then ignores it), and the driven half
walks the threaded chains backwards through the interpreter.

### Repeating the last number

A measurement asked once per item — a step tread, a step width — can be
repeated with **Same**, typed `S`. It sits beside `Back` in the bracket
and the prompt names the number it would repeat, so there is nothing to
remember:

```
Step 2 - step tread [Back/Same] <Enter = done, Same = 24>:
Step 2 - step width [Same] <Enter = fit to walls, Same = 30>:
```

`Same` is offered only where it earns its place: where a previous value
of that kind exists **and** `Enter` is already spoken for by something
else. At `CORNERSTP`'s tread prompt Enter means *done*; at its width
prompt Enter means *fit to the walls* — neither can also mean "the last
one", so `Same` is what does. Where `Enter` already repeats the last
value (`PERPPTS`' point lengths, the side-profile depths, `HEMISTEP`'s
widths in base-line mode) `Same` would be a second word for one answer,
so it is not offered.

Only a number you gave is one `Same` repeats. A step fitted to the
walls has no typed width behind it, so `Same` after one goes back to
the last width you actually entered — and the prompt says which.

### `ABCDEF` vs `ALTABCDEF`, and `CHECK` vs `CCPRECHECK`

Two pairs of tools collided on the same command name during
consolidation:

* **`ABCDEF`** read rectangle corners in two incompatible conventions
  depending on which branch it came from. The newer branch kept the
  name; the older, clockwise-reading version is now `ALTABCDEF`
  (including its `altabcdef:` helper namespace and `ALTABCDEF-*`
  layers, so loading both in one session is safe).
  `XYPLOT` is a third member of the family rather than a fourth
  convention: it takes X/Y offsets instead of corner distances, so
  there are no corners to disagree about.
* **`CHECK`** named two unrelated tools: a dimension/arc geometry audit
  (with `DIMCHECK`, `LINFINCHECK` and `COVERCHECK` already built
  against it) and a product-type flowchart walker. The audit kept
  `CHECK`; the flowchart walker is now `CCPRECHECK`.

### The stock cover folder

`STOCKCOVER` reads finished cover drawings out of a shared folder -
`F:\TechTeam\2022 StockCoverTech` as shipped. Set that folder before
handing the file out, by editing `*stock-folder*` at the top of
`lisp/stockcover/STOCKCOVER.lsp`; anyone can override it on their own
machine with `STOCKCOVER-CFG`, which is remembered in their AutoCAD
profile and wins over the value in the file.

You highlight the perimeter to be replaced and type the stock drawing's
short name - `5M` finds `5M_Tech.dwg`, `20M` finds `20M_Tech.dwg`
(`*stock-suffixes*` holds the `_Tech` part). Alignment is by the anchor
POINTs both sides carry - one at the bottom left, one at the top right,
in the highlighted area and in every stock drawing. The stock lands in
one move, bottom-left anchor onto bottom-left anchor, and stays exactly
there: no fit prompt, no scaling, no shuffling afterwards. A side
without anchor points falls back to its bounding-box corners, and
`STOCKCOVER` says so. If the two anchor spans disagree (the wrong file
was probably named) it prints how far off the stock is, loudly, but
still places anchored - nothing is erased until the new geometry is
placed, and the whole run is one `U`.

Release history is in [CHANGELOG.md](CHANGELOG.md); the release name
itself lives in `RELEASE` at the top of `tools/build_shared_bundle.py`,
so `shared/LAZPASS.lsp` announces it on load and cannot drift from it.
Per-tool banners keep their own REVs.

## Shared build (`shared/`)

The same tools built against one common helper library instead of each
embedding its own copies. APPLOAD `shared/LAZPASS.lsp` - the whole
build concatenated into one file, so there is nothing for it to find on
disk - and every command loads in one go. (`CALOFIN-LOADER.lsp` is the
multi-file alternative for when you are editing the files; it has to
locate its own folder first. Never APPLOAD `CALOFIN-LIB.lsp` alone: it
is the helper library and brings no tools with it.) The folder assumes
everything is loaded together, so a shared tool file is not loadable on
its own.
`shared/parts/CALOFIN-LIB.lsp` holds the shared helpers under the `cal:`
prefix; the per-tool files are twins of their `lisp/` sources minus
the helpers the library now provides. See `shared/README.md` for the
helper roster and `STANDARDS.md` section 6 for the rules (including
how `lisp/` changes get mirrored here). The standalone files in
`lisp/` are unchanged and still load alone, one file at a time. The
deprecated acady matcher (`lisp/standards_checker/`) is not part of
this build and still loads on its own.

## Releases (`releases/`)

Some tools distribute a dated, REV-numbered twin of their static file
(`lisp/dimcheck/dimcheck.lsp` alongside
its dated `releases/dimcheck_MMDDYY_REV##.lsp`) so a loaded routine never
silently changes underfoot, and a version banner in the file, its
filename, and what the command prints at startup can never disagree.
Every tool's twins live flat in `releases/` - no per-tool subfolders,
just the file itself - instead of next to the static file. Regenerate
them after any change with:

```
python3 tools/release_lisp.py
```

Not every tool uses this convention - the script says so per file
(`no version banner - skipped`) rather than guessing.

### The step bundle

The three step routines go out together, so they release as **one**
file rather than one each:

| Release | Holds |
| --- | --- |
| `releases/STEPS_MMDDYY_REV<cs>-<hs>-<ns>.lsp` | `CORNERSTP.lsp`, `HEMISTEP.lsp`, `NORMIESTEP.lsp` -- each member's own REV, in concatenation order |

APPLOAD that single file and all six commands (`CORNERSTP`,
`HEMISTEP`, `NORMIESTEP` and their three `TUTORIAL...` walkthroughs)
come with it. The REV numbers in the filename are each member's own, in
the same order the file concatenates them, and each source is copied in
**verbatim** - so the bundle still diffs cleanly against
`lisp/cornerstp/`, and each routine prints its own version banner as it
loads. The three routines already namespace their helpers apart (`cs-`,
`hs-`, `ns-`) and guard the settings globals they share, so loading the
bundle is the same as loading the three files back to back. Members of
a bundle get no separate dated twin of their own.

Bundles are declared in `BUNDLES` at the top of `tools/release_lisp.py`;
everything else releases one file per source.

## Palette UI (`ui/`)

| | Folder | |
| --- | --- | --- |
| Calofin palette (VB.NET) | `ui/calofin_net/` | Dockable AutoCAD palette: Find over names and captions, Recent and Pinned rows sharing `LAZPANEL`'s own registry key, the panel's whole tab strip as real tabs, and the `LAZFORM`, `LAZSPA` and `LAZSTEP` sheets **drawn from their own vectors** - a box on every dimension line, a state line that holds Draw back, and Recall-last sharing the DCL forms' store. Only the pool-bottom tab is still a photograph. Its catalog is no longer typed - `Generated/CommandCatalog.g.vb` is written from `LAZPANEL`'s own tables by `tools/gen_ui_data.py`, so the two surfaces cannot part again the way they had (the palette shipped 60 of 67). The tooltips are the palette's own words and stay hand-written, in `blurbs.txt` |
| Palette LISP glue | `ui/calofin_ui/` | `calofin.lsp` - reports which commands are actually loaded this session, so the palette can grey out the rest, and carries the **form wire**: the palette sends a box's text as typed and this reads it, through the same three-state contract the DCL charts use. Checked too: a palette button with no probe-list name could never grey out, which is how five of them shipped |

`ui/PLAN.md` records how the palette got here and why the wire between
it and the routines is shaped the way it is; `ui/UI-PLAN.md` is the
roadmap from here, covering both the zero-install DCL surface and the
tables the two surfaces are meant to share.

`ui/PLAN.md` records how the palette got here and why the wire between
it and the routines is shaped the way it is; `ui/UI-PLAN.md` is the
roadmap from here, covering both the zero-install DCL surface and the
tables the two surfaces are meant to share.

The palette needs its DLL `NETLOAD`ed on every machine. For a
button panel with nothing to install, see `lisp/lazpanel/` above:
`LAZPANEL` is pure AutoLISP, ships inside `LAZPASS.lsp`, covers the 80
headline drafting commands, and puts its own one-button toolbar on
screen to open it; the VB palette remains the richer surface (docks,
stays open while a tool runs, POOL/SPA forms). For forms with nothing
to install, see `LAZFORM`, `LAZSPA` and `LAZSTEP` above.

**Status:** `lisp/pool/POOL.LSP` and `lisp/spa/SPA.LSP` are the
canonical, actively-developed versions of those tools. The receiving
end a form needs - an answer store the ask helpers read before they
prompt - now exists in **both**, and in the three step routines as
well: `pool:*form*` / `pool:run-with-answers`, `spa:*form*` /
`spa:run-with-answers`, and `*cs-form*` / `*hs-form*` / `*ns-form*`
with their own `...-run-with-answers`. `tests/test_pool_form.py`,
`tests/test_spa_form.py` and `tests/test_steps_form.py` all pass at
both tiers because of it, and the POOL and SPA suites each end by
checking the palette's field map sends no key its routine cannot read.

Every store keeps the same three-state contract: a key that is absent
is asked for as usual, `(key . nil)` answers NA without a prompt, and
`(key . 84.0)` answers the measurement. An answer is **removed as it
is used**, which is what stops `Back` deadlocking on a question the
form already answered and lets a value failing a range check be
retyped at the keyboard.

`ui/PLAN.md` was the execution plan for the POOL and SPA halves; the
design it records (D1-D6) is what got built.

## Ariel anchor placer (`ariel/`)

Windows, Python 3.8+, nothing to install. Ariel (Fisherlea) rectifies a
near-nadir drone photo to deck scale and the operator then digitises the
markers taped to the deck - forty-odd of them round a pool - by finding
each one and clicking it. The finding is mechanical; the checking is
not. So this finds them and leaves the checking alone:

```
python ariel\anchors.py           # grab the screen, pick the area, place them
python ariel\anchors.py --dry-run # the same walk, but never press a button
```

One screenshot is taken and everything works from it, so what you select
is provably what gets searched. The dots come back numbered and laid
over your screen at 1:1 - click to add or remove one, right-click to say
which is number 1, `o`/`x`/`c` to change the order - and then it clicks
each anchor and magnifies it at 8x while you say yes, nudge it with the
arrow keys, or drag it yourself in Ariel and press Enter. The keys are
read through a low-level hook so Ariel keeps the focus throughout.

It is not an AutoLISP tool and is deliberately in none of the places one
would be: not in `LAZPASS.lsp`, no `shared/parts/` twin, no `releases/`
REV twin, not a LAZPANEL caption or a palette button. There is no
AutoCAD at the point in the job where it runs. `ariel/README.md` has the
key map, the detection knobs and the reasoning.

Five of its seven modules never touch Windows, so detection, ordering,
the run loop and the file formats are all testable anywhere:

```
python3 tests/test_ariel_anchors.py
python3 ariel/anchors.py --from-shot deck.png --annotate found.png
```

Give it a list of anchors somebody placed by hand and it will say how
far apart the two are - what it missed, what it invented, how far off
each centroid is, and whether its click order is the same loop as
yours, compared as a cycle so a different starting dot is not counted
as forty-four errors. It exits non-zero when anything is missing or
extra, so a threshold change can be re-scored against every photo kept
from a real job:

```
python3 ariel/anchors.py --from-shot deck.png --score placed.txt
```

## Tools (`tools/`)

| Script | What it does |
| --- | --- |
| `release_lisp.py` | Regenerates every REV twin in `releases/` from its `lisp/<tool>/` source's version banner, and the one-file `STEPS` bundle from its three sources |
| `build_shared_bundle.py` | Concatenates `shared/` into the single-file `shared/LAZPASS.lsp` |
| `mirror_shared.py` | Regenerates a `shared/parts/` twin from its `lisp/` original - drops the helpers the library provides and rewrites the call sites onto `cal:`. Table-driven, one entry per tool |
| `check_standards.py` | Cross-file check: every `lisp/` tool has a `shared/` twin **and that twin carries the same version banner**, only the library owns `cal:`, no grouped-build name collisions, no stale `releases/` twin |
| `check_lisp.py` | Static check: unbalanced parens, undefined functions/globals, unused defuns, and special forms given the wrong number of arguments (a four-argument `(if ...)` parses fine and dies at the command line) |
| `check_scope.py` | Static check: local variables used without being declared in a defun's arglist |
| `gen_ui_data.py` | Writes the palette's `Generated/CommandCatalog.g.vb` from `lzp:*captions*` / `lzp:*groups*` plus `ui/calofin_net/blurbs.txt`. `--check` fails when the file on disk is not what a fresh run would write, the same contract `releases/` is held to |
| `gen_ui_charts.py` | Writes the palette's `Generated/ChartCatalog.g.vb` - the vector charts `LAZFORM`, `LAZSPA` and `LAZSTEP` draw, plus the tables that are not geometry: LAZFORM's cross dims, mode dropdowns, corner rows, bottom types and in-square keywords, and LAZSPA's corner rows, second-outline keys, dropdowns and treatments - out of `lzf:*charts*`, `lzs:*charts*`, `lzt:chart` and the four `lzs:*` tables, read through `tests/lispvm.py`. Arcs are flattened by the Lisp's own helper, so the palette draws the same oval the panel does with no arc arithmetic of its own |
| `check_vb.py` | Static check over the VB palette, for a tree with no VB compiler: blocks opened and closed by the right closer, quotes and parens balanced per logical line, and every member and constructor arity of the assembly's OWN types resolved - which is what holds the hand-written palette to the generated catalog |
| `check_registry.py` | Every place a tool has to be registered - panel caption and placement, loader slot, README counts, the palette catalog and its probe list - with every count computed rather than typed; `--fix` repairs what is not editorial |
| `check_lazdiag.py` | Every command reports its failures: the `(if lzd:begin ...)` at the top and the `(if lzd:report ...)` in the `*error*` handler that turn a failure into a DXF report, plus the one line in each ask helper that records the prompt it just put up. `--fix` wires what is missing, so a tool added later cannot be the one whose failures stay silent |

`tests/test_pool_runtime.py` and `tests/test_spa_runtime.py` load the
real `POOL.LSP` / `SPA.LSP` into the AutoLISP VM in `tests/lispvm.py`
and drive the commands end-to-end with scripted answers, so a change
that would die at the AutoCAD command line dies there first.

## Tests (`tests/`)

Runs without AutoCAD or Blender installed - `lispvm.py` is a pure-Python
AutoLISP interpreter good enough to execute the real `.lsp` files, and
the Blender add-ons' geometry logic lives in `bpy`-free modules so it's
unit-testable directly:

```
python3 tests/test_lazdiag.py         # LAZDIAG - the DXF read back
                                      #   group code by group code,
                                      #   the geometry and prompts it
                                      #   carries, and the paths where
                                      #   the reporter itself fails
python3 tests/test_pool_lisp.py       # POOL geometry
python3 tests/test_pool_runtime.py    # POOL loaded and run in lispvm
python3 tests/test_tutorialpool.py    # TUTORIALPOOL, run in lispvm
python3 tests/test_poolside.py         # POOLSIDE, run in lispvm
python3 tests/test_lingutter.py       # LINGUTTER - the exterior walk, the
                                      #   snap ladder and the hull, the keep
                                      #   rules, and the gut scoped to the
                                      #   highlight
python3 tests/test_oasis.py           # OASIS loaded and run in lispvm
python3 tests/test_oasis_form.py      # OASIS driven from a filled-in sheet
python3 tests/test_pool_fit.py        # ABHD
python3 tests/test_abhd_runtime.py    # ABHD's fitter run in lispvm,
                                      #   against the mirror above
python3 tests/test_abhd_contingencies.py
                                      # ABHD and ADAB driven through the
                                      #   paths a bad drawing takes: no
                                      #   points, a gap, a SPLINE, a
                                      #   tilted UCS, a cancelled bottom,
                                      #   a Redo that omits and restores
python3 tests/test_abcurcheck.py      # ABCURCHECK, run in lispvm
python3 tests/test_cabhd.py           # CABHD, run in lispvm
python3 tests/test_abpcheck.py        # ABPCHECK over drawings with known
                                      #   point-to-line distances
python3 tests/test_pointrenamer.py    # POINTRENAMER - both sweeps against
                                      #   hand-worked stations, the band
                                      #   split, arcs, Back, the clash,
                                      #   and the contingencies: a
                                      #   mis-click, a zero-length
                                      #   perimeter, a fitted polyline, a
                                      #   write that cannot land, and
                                      #   every knob followed
python3 tests/test_laser_fit.py       # LHD
python3 tests/test_fitabhd.py         # FITABHD (engine also run in lispvm)
python3 tests/test_perp_points.py     # PERPPTS / CPERPPTS
python3 tests/test_cdcreate.py        # CDCREATE loaded and run in lispvm
python3 tests/test_custblock.py       # CUSTBLOCK loaded and run in lispvm
python3 tests/test_smartfillet.py     # SMARTFILLET loaded and run in lispvm
python3 tests/test_honefillet.py      # HONEFILLET, its half-inch spinoff
python3 tests/test_bpcallout.py       # BPCALLOUT loaded and run in lispvm
python3 tests/test_cdcallout.py       # CDCALLOUT loaded and run in lispvm
python3 tests/test_abfind.py          # ABFIND / ABMOVE, run in lispvm
python3 tests/test_abcdef.py          # ABCDEF, run in lispvm against a known survey
python3 tests/test_altabcdef.py       # ALTABCDEF, the same under the
                                      #   clockwise corner order
python3 tests/test_xyplot.py          # XYPLOT, run in lispvm
python3 tests/test_constellation.py   # CONSTELLATION - a known shape
                                      # back from its distances, a
                                      # partial chart, what is refused,
                                      # arcs, and the fix-and-redraw loop
python3 tests/test_autodim.py         # AUTODIM styles, dedupe, overall/step/floor dims
python3 tests/test_lisplab.py         # LISPLAB - the sorts against Python's
                                      # own sorted(), then the whole tour
python3 tests/test_lincheck.py        # LINCHECK, run in lispvm
python3 tests/test_ccprecheck.py      # CCPRECHECK branch walks and Back
python3 tests/test_stockcover.py      # STOCKCOVER, run in lispvm
python3 tests/test_covercheck_pads.py # COVERCHECK's pad hunt vs PADDLE's,
                                      # both real .lsp files in one lispvm
python3 tests/test_spacheck.py        # SPACHECK over a drawing the real SPA
                                      # just made, in the same lispvm
python3 tests/test_dimcheck.py        # DIMSCAN read-only, then the guided
                                      # review: Move/Keep/Back/No, merge,
                                      # DIMCHECKRESCUE
python3 tests/test_linfincheck.py     # the liner rules over a real staircase
                                      # side view, LITELINFINSCAN, the
                                      # guided review incl. Skip
python3 tests/test_covercheck.py      # the cover rules over an L-pool, the
                                      # pad suggestion, LITECOVERSCAN
python3 tests/test_lazform.py         # LAZFORM - the chart drawn and checked,
                                      # and the pool it draws vs the prompts
python3 tests/test_lazpanel.py        # LAZPANEL - roster pinned to lisp/,
                                      # DCL well-formed, run with stubs,
                                      # toolbar + generated icon bytes
python3 tests/test_cornerstp_geometry.py
python3 tests/test_cornerstp_bench.py   # CORNERSTP's bench, run in lispvm
python3 tests/test_cornerstp_profile.py # the side profile all three draw
python3 tests/test_normiestep_corner.py # NORMIESTEP corner mode, run in lispvm
python3 tests/test_steps_settings.py  # the step routines' tunables - every
                                      # knob wired up and moving the drawing,
                                      # each reader falling back to the value
                                      # its settings block sets - and the
                                      # contingencies: UNDO off, no dim
                                      # styles, an undrawable dim layer, a
                                      # frozen layer, AUTOBEAD absent, and a
                                      # selection that cannot be a run
python3 tests/test_drone_height_lisp.py
python3 tests/test_addon.py           # UV layout exporter
python3 tests/test_cloud_mesher.py    # point cloud mesher
python3 tests/test_dxf_reader.py      # Merlin import
python3 tests/test_mesh_layers.py     # Merlin layered export
python3 tests/test_dewrangler.py      # mesh dewrangler
python3 tests/test_ariel_anchors.py   # the Ariel anchor placer: the dot
                                      # detector against a mock deck - water,
                                      # brick coping and dappled shade all
                                      # the colour of a marker - plus the
                                      # three orderings, the confirm loop,
                                      # the PNG reader, and the score that
                                      # holds a run to hand-placed anchors
python3 tests/test_pool_form.py       # a form drives POOL and draws what
                                      # the command line draws
python3 tests/test_spa_form.py        # the same for SPA, palette wire format
                                      # included
python3 tests/test_steps_form.py      # the same for all three step routines,
                                      # including the step count
python3 tests/test_lazspa.py          # LAZSPA - the spa chart drawn and
                                      # checked, and the spa it draws
python3 tests/test_lazstep.py         # LAZSTEP - the drawing generated for
                                      # every step count, and the steps it draws
python3 tests/test_dialog_actions.py  # every action_tile expression on every
                                      # DCL page, EVALUATED - a callback is a
                                      # string, so a typo'd or moved helper is
                                      # dead until somebody clicks that tile
python3 tests/test_ui_data.py         # the palette's generated catalog read
                                      # back and held to LAZPANEL's roster -
                                      # captions, categories, the whole tab
                                      # strip, and the blurbs it must not invent
python3 tests/test_check_vb.py        # the VB linter itself, driven against VB
                                      # that is wrong on purpose: a checker
                                      # that has stopped checking is worse
                                      # than none
python3 tests/test_palette_shell.py   # the palette's Find/Recent/Pinned against
                                      # LAZPANEL's: one registry key, one cap,
                                      # and every Find message lifted out of the
                                      # Lisp rather than typed
python3 tests/test_ui_charts.py       # the palette's generated chart geometry
                                      # read back and held to lzf:/lzs:/lzt:'s
                                      # own tables - every dimension, every
                                      # outline point, arcs included
python3 tests/test_palette_wire.py    # calofin.lsp's form wire in the VM: the
                                      # three states plus the fourth - text
                                      # nobody can read is NOT NA, it is a
                                      # question the routine still has to ask
python3 tests/test_chart_form.py      # the palette's chart form against what it
                                      # must agree with: the DCL forms' recall
                                      # store, the wire it asks about a bad box,
                                      # and the sheet it draws
python3 tests/test_tunables.py        # the four GUI files' knobs: all in the
                                      # block at the top, each saying what
                                      # changing it does, each a row in the
                                      # README, and the ones the palette shares
                                      # spelled the same on both surfaces
python3 tests/test_cancel_paths.py    # every headline command cancelled at its
                                      # first prompt: the handler runs, settings
                                      # come back, no group or error mode left
python3 tests/test_autobead.py        # AUTOBEAD - the run that finds nothing
                                      # to bead and the run that dies both put
                                      # the settings, the undo group and the
                                      # pushed error mode back; and what the
                                      # run does NOT bead - a held-back step
                                      # line, and None side walls
python3 tests/test_drone.py           # DRONE / TYDRN - the cleanup pass on a
                                      # survey with locked layers, an error
                                      # mid-run and an Esc, both handled by
                                      # the command's own *error*
python3 tests/test_soconv.py          # SOCONV - where the export's layers land
                                      # and, as much, what the move leaves
                                      # untouched; a highlight, a re-run, a
                                      # drawing that is not an export, an
                                      # error and an Esc.  Then SORECONV: the
                                      # round trip, a purged source layer
                                      # re-created, and a linetype it cannot
                                      # load leaving the record in place
python3 tests/test_vsconv.py          # VSCONV - a VS export converted onto the
                                      # shop layers: the move, the dimension
                                      # overrides stripped with the style
                                      # rename, and the cut-short paths.  Then
                                      # VSRECONV: the round trip, overrides
                                      # and all, and what an absent property
                                      # comes back as
python3 tests/test_g2mconv.py         # G2MCONV - a G2M plan converted onto the
                                      # shop layers AND styles: the five rules,
                                      # the appearance forced, the notes and
                                      # the dimensions restyled, the annotative
                                      # flag off, and that a note's own ACAD
                                      # xdata survives a step that deletes an
                                      # application by name.  Then G2MRECONV:
                                      # the whole round trip, and a purged
                                      # style leaving the record in place
python3 tests/test_xftconv.py         # XFTCONV - both export flavours swapped
                                      # for ab_pt blocks, and XFTRECONV
                                      # putting each survey back: the markers,
                                      # the text it swept, the scale, and the
                                      # two-conversions highlight it refuses
python3 tests/test_tydrn_suite.py     # TYLERDRONESUITE - the order, the
                                      # CDIM finisher, the carried
                                      # highlight, and that a missing
                                      # stage stops it before it starts
python3 tests/test_calofin_lib.py     # CALOFIN-LIB - the shared sysvar
                                      # snapshot merges after a run cut short
python3 tests/test_shared.py          # shared/ build - everything loads together
```

Setting `CALOFIN_LISP_ROOT=shared` reruns any VM-driven test above
against the `shared/` build instead of `lisp/`, as a behavioral-parity
check.

Or skip the prose list entirely: `python3 tools/run_tests.py` (or
`make test` / `make parity`) globs every `tests/test_*.py`, runs them
in parallel per tier, and is the authority on what is expected to
fail (`EXPECTED_FAILURES`, currently empty).
`tests/record_prompts.py` prints a command's live prompt script when a
prompt change makes a scripted test stale.

## License

GPL-3.0-or-later (as required for Blender add-ons).
