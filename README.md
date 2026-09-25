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

Working with an AI coding agent? Start at `AGENTS.md` in this folder --
a short router into `.claude/skills/`, which holds the task-scoped
working subset of `CLAUDE.md`, `STANDARDS.md` and this file, plus
scripts that beat reading a 9,000-line tool file. Claude Code picks the
skills up by itself; `AGENTS.md` is generated from them for every other
agent.

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
| `POOL`, `POOLCOVER`, `POOLDEMO`, `POOLDEMOVER`, `POOLVER`, `TUTORIALPOOL` | `lisp/pool/` | As-built pool plan generator - Rectangle, Oval, Grecian, L, Lazy L - from field measurements. `POOLCOVER` is the same command for a cover sheet: the pool-bottom question is answered No before it is asked, so the depth chain behind it (C, C2, D, the hopper type and its corner method) never runs. Once the pool is in it offers **steps at the shallow end**: with a hopper, `Hemi`/`Normie`/`Corner` hands the shallow wall to `HEMISTEP`/`NORMIESTEP`/`CORNERSTP` (and NORMIESTEP steps into the pool move E down to the bottom wall in SIDE STANDARD, with a new break-to-first-step dim); `FGstep` places the shop's 4x6/4x8 fiberglass step blocks and their label where picked; with none, a 4x6, 4x8 or custom box step outside the wall, the wall broken round it, dimensioned and padded by `PADDLE`. Every corner SIZE and every DEPTH stands beside `DIMSTAMP`'s **ruler**, drawn as a LADDER: `Radius for <corner>` and `Cut face length for <corner>` offer 3" to 2'-0" in 3" steps, C offers 36"-54" by 3", D 60"-96" by 6", C2 the span of the two, and the two HOPPER OFFSETS M and K -- the gap the hopper leaves to each side -- 2' to 6' by 6", and clicking a rung IS the size -- a corner radius is picked out of the short list a shop builds to, not taped off the sheet. The WALL dims, the diagonals, the cross dims, the stations ALONG the pool (H, G, F, E) and the hopper's own width L are measured, so they stay the plain typed questions they were |
| `POOLSIDE`, `POOLSIDEVER` | `lisp/poolside/` | POOL's side view (the longitudinal section) on its own: the bottom type, the overall length B, the floor run chain (`H G F E`, or `E2 F2 G F1 E1` for a Sport) and the depths C / D / C2 - no plan, no perimeter, no cross dims. A gray nominal section is on screen while the letters are asked, with the tie being asked for lit red. Any run may be `NA` and is read back off B; a run that resolves negative is floored, its dimension drawn red and a note written under the section. **It takes a form now**, in the shape POOL and the step routines already had - `psd:*form*`, keyed by the letters themselves, with the bottom type and the mirror question alongside them - so `LAZSIDE` can hand the whole section over and leave nothing at the command line but the base point. An answer is spent as it is read, which is what keeps `Back` working and what gives the two range checks their way out; an answer the prompt itself would have refused is spent and then asked for properly. C, D and C2 stand beside `DIMSTAMP`'s **ruler** on POOL's own numbers -- 36"-54" by 3", 60"-96" by 6", and the span of the two -- since the two tools draw the same pool and a depth offered one way here and another there would be two vocabularies for one question; the floor RUNS beside them are taped, so they stay plain |
| `SPA`, `SPAVER`, `TUTORIALSPA` | `lisp/spa/` | Spa/hot-tub template - Rectangle, Octagon, Round. The corner SIZE question stands beside `DIMSTAMP`'s **ruler**, offering 3" to 1'-6" in 3" steps -- one size down from POOL's, a spa being the smaller shape -- and `600mm` still reads there, the one spelling the library does not know being handed in by the tool that does |
| `SPACOVCREATE`, `SPACOVCREATEVER` | `lisp/spacovcreate/` | The COVER for a spa that is already drawn, where there are no measurements to type and only geometry to point at: select the spa (one closed polyline, a circle, or loose walls and arcs chained end to end -- the biggest loop in the selection wins), give the lap (6" by default) and click the Spa Cover Details block for the taper.  The offset keeps the ARCS: only the vertex moves, out along the corner bisector, so a radius corner offsets to a radius corner on the same centre and a circle to a circle, and the cover comes out as one closed polyline.  Then hinges it to SPA's own foam sheet, piece counts and Hinge Arrangement Chart, dividing the longer overall because nothing here can be turned.  Type the taper or skip it entirely and a STANDARD 4-2 is assumed AND written into the report beside the drawing, in red, with everything else out of spec |
| `OASIS`, `OASISVER` | `lisp/oasis/` | Continuous-tangent pool - centre bulge, top-right bulge, cloud (straight or rounded bottom), kidney (true or asymmetric) or NXT cloud (three lobes, four fillets) - drawn live as its X/Y envelope and radii are answered, with a centre-to-corner check drawing beside it.  A `Complex` run takes a straight tangent run in place of any joiner and places the third bulge along X: the centre hump off centre, or the top-right bulge in off the right-hand bound so that the top wall alone holds it - given as a signed shift, or as the centre-to-centre `Tie` back to the right bulge that the drawing carries and the check drawing prints.  Finishes by offering the pool bottom - shallow and deep breaks, hopper and slope lines, ABHD's flow with the break located by a change of tangency, a nearest point or an offset in from a bound.  Takes a form's answers (`oasis:*form*`), so `LAZFORM`'s oasis sheets drive it. Every RADIUS -- three bulges and three tangents, one after another -- stands beside `DIMSTAMP`'s **ruler** offering 4' to 12' by a foot, since they come off a plan in whole feet; the two BOUNDS and the corner tie are taped across the pool and stay plain |
| `ABHD`, `ABHDVER`, `ABHDCOVER`, `SIMPABHD`, `ADAB`, `TUTORIALABHD`, `TUTORIALADAB` | `lisp/abhd/` | Fits a pool perimeter and bottom through surveyed points. Up to 20% of them may sit an inch off, the curve count is capped at a third of them unless you say otherwise, and a point numbered with an `m` -- ABFIND's mark for one it DEDUCED rather than one somebody shot -- is left out of the fit entirely. `SIMPABHD` is the same fit with none of the three numbers asked: five ready-made perimeters are drawn -- the least error there is, the fewest curves that hold an inch, and three answers in between -- and you keep the one that looks like the pool. A slope-line waypoint offset that fights both its neighbours by more than 2in is named with the number the wall between them puts there, and the line is still drawn through exactly what was typed. `ABHDCOVER` answers the "add the bottom" question No before it is asked, for a cover sheet that stops at the perimeter. With the whole survey selected, **step 8 asks which of those points to leave OUT** - the shot on the coping, the double-shot, the rod held crooked - which is the first moment anybody can see which one is bad; until then the omit list was only reachable from a `Redo`, so the first fit was always drawn round a point the drafter could already see was wrong. Nothing is thrown away: a point left out is still MEASURED against the line that is kept, ringed on `FGStep` beside the points the fit missed and listed with how far off it landed, and under that list goes one line naming every bad point - `- Pt.12, Pt.15 and Pt.20 are bad.` - in `BPCALLOUT`'s wording, so a sheet reads the same sentence whichever tool wrote it. Every point it asks about - a wall end, a corner, a held point, a break end, a slope waypoint, a point to leave out - is NAMED the way `PERPMARK` names one: click it, or type its number, and a click on nothing is re-asked rather than snapped to whatever was nearest. The three HOPPER OFFSETS stand beside `DIMSTAMP`'s **ruler** offering 2' to 6' by 6" -- the range `POOL` and `FITABHD` offer at the same question, a hopper offset being one number whichever tool asks; the slope waypoint offset beside them admits ZERO, which no length on a ruler is, so it keeps the plain typed question |
| `ABCURCHECK`, `ABCURCHECKSCAN`, `ABCURCHECKRESCUE`, `ABCURCHECKVER` | `lisp/abcurcheck/` | ABHD's reader turned round: grades how CONTINUOUS a perimeter already drawn is, as one word - `Smooth` / `Fair` / `Rough` / `Broken` - set by the single worst thing found and naming it, with a 0-100 index underneath for comparing two candidates.  Measures gaps, zero-length and doubled segments and crossings (G0); the kink angle at every joint, banded on ABHD's own 8 and 45 degrees, so the 8-45 band a fabricator finds in the bead is the headline; and the noise a traced outline leaves behind - micro-segments, inflections, and the turning excess over the 360 degrees any simple closed loop turns.  Breaks that are MEANT to be there are picked and stamped onto the drawing, so they leave the grade and the next run remembers them; what is left is the undeclared list, ringed on `POOL-CONT`.  Draws the curvature comb on `POOL-COMB` - a tooth per sample, sided by which way the curve turns - where every break is a step in the envelope |
| `OLAUTO`, `OLAUTOVER` | `lisp/olauto/` | Lays a NEW pool perimeter over the ORIGINAL (the bead track) at the one position where the disagreement between them is as small as it can be made, and dimensions what is left.  The fit is RIGID - turned and slid, never scaled, because a fit allowed to stretch would absorb a pool measured 2% long into itself and report a clean overlay.  Found in two stages: a phase search over every arc-length alignment and both directions, each scored in closed form, and then an ICP polish.  The first stage is what stops the second settling into a local fit - on the drawing it was written from, plain ICP started between 90 and 270 degrees converged to an RMS of 20 to 48 against the right answer's 1.36.  Asks which selection is the new one (the layers answer that before it is asked) and which of the two should move; puts the new onto `POOL` and the original onto `Bead Track`; dimensions the four worst spots, forced apart around the perimeter so four dimensions describe four problems |
| `CABHD`, `CABHDVER` | `lisp/cabhd/` | ABHD's perimeter half, for a survey that runs past the pool: asks the LAST point number belonging to the pool edge and leaves everything past it out entirely.  No pool bottom.  Step 9 then asks which of the pool's OWN shots to leave out, and those are ringed and measured against the kept line with the points it missed, under one line naming them all; what the CUTOFF dropped is in none of that, a bench shot not being a bad pool-edge shot.  Its walls, corners, held points, the cutoff's `Pick` and its omits name a point `PERPMARK`'s way - click it or type its number - and a declaration on a point the cutoff drops is named and dropped, never snapped onto another |
| `LHD` | `lisp/lhd/` | Fits a top-down 2D outline (closed or open) through laser-scanned points |
| `ABLOBF`, `ABLOBFVER` | `lisp/ablobf/` | `LOBF`'s bigger sibling, and `ABHD`'s fitter walked in a straight line instead of round a loop: the line of best fit as a POLYLINE, and OPEN. Arcs and lines threaded through the points the way `ABHD` threads a perimeter - a wall that bows, a coping run round one end, a bench, a step nose. A loop needs no ends; a run that does not close has two, and nothing in a cloud of points says which - so it asks. Click the point the run STARTS at and the one it ENDS at, or type the survey numbers they already carry; Enter takes the farthest-apart pair, which is right for a run that does not double back and wrong exactly when it does. Everything else is ordered BETWEEN them - nearest-neighbour from the start, the end forced last, then 2-opt uncrossing with both ends pinned, because the closed 2-opt prices a closing edge an open run does not have. Naming one point for both ends is refused rather than fitted. Which points to leave OUT is asked BEFORE the two ends, since a point about to be left out has no business being offered as the one the run starts at; each is still measured against the run that is kept and ringed with the points it missed, under one line naming them all. Keeps ABHD's declarations (dead-straight stretches, sharp corners, points held ABSOLUTELY), its miss allowance, its curve cap and nice radii, and its three candidates - tight / as asked / few - drawn side by side with a table of segments, curves, worst and average deviation to pick from. The kept run lands on the `POOL` layer as an OPEN polyline, so the rest of the toolset can read it. Reads no drawn geometry at all: a window over the whole sheet takes the survey and leaves the drawing alone |
| `FITABHD`, `FITABHDCOVER`, `FITABHDVER` | `lisp/fitabhd/` | Fits a TYPED pool template (Rectangle, Grecian, Roman, Oval, L, Lazy L, Round, or an OASIS pool) through surveyed points -- the type says how to READ the survey, the points decide the shape: out-of-square walls, side walls that lean apart on a Roman or Oval, corner sizes, bows, and any curve drawn as one R -- an end, a corner, a bow -- rebuilt as a smooth run of up to a third as many arcs as it has points (ABHD's tangency window) are all measured from the survey and kept only where it proves them, Redo to refit -- then a standard-hopper bottom.  Step 8 asks which points to leave OUT of the fit once the survey is selected, rather than only after one has already been pulled out of square by a bad shot; each one left out is still measured against the outline fitted without it, ringed with the strays, and named on one line under them.  An `OAsis` is fitted with OASIS's own ring solver against OASIS's own five families, and everything OASIS has to ask about a shape is measured instead: the frame is swept right round the pool (an oasis has no walls to vote on it), the envelope falls out of the bounding box, and every joiner is carried as a curvature so a cloud's flat bottom is the one whose radius came out infinite -- found, not declared, as is which way a kidney was given. `FITABHDCOVER` skips that bottom question for a cover sheet. The two BREAK stations, the two hopper OFFSETS (2' to 6' by 6", as in `POOL` and `ABHD`) and the fit TOLERANCE each stand beside `DIMSTAMP`'s **ruler** on a ladder of their own -- those are the numbers a hopper is laid out to, and a job's pools share them, which is why the tool already remembers each between runs |
| `BPCALLOUT` | `lisp/bpcallout/` | Rings clicked bad points with 5" circles on `FGStep` and writes a "Pt.12, Pt.15 and Pt.20 are bad" callout |
| `CDCALLOUT` | `lisp/cdcallout/` | Cross-dimensions from Pt.## to Pt.## by typed number - `CROSS DIMENSIONS` style, `DIMENSION` layer, repeat until Enter. **Every tie is its own pair**: a drawn dimension goes back to the FROM prompt, so the next one names both of its points and nothing carries over between runs. v1.7 chained off the last TO point instead, which is not what cross dims are - they are whichever two points the drafter wants tied, in whatever order the sheet needs them.  A number the drawing carries TWICE -- two surveys merged onto one sheet -- rings every point that carries it, labels them `P1`, `P2`, and asks which, with the length of the dimension each would draw beside it; a number only one point carries is taken unasked, as it always was |
| `DRONOTE`, `DRONOTEVER` | `lisp/dronote/` | Asks which of three canned drone-photo review notes you want - `Board` (how far the diving board base is from water's edge), `Anchors` (some anchors not visible in the drone photo) or `Slide` (a detailed sketch is needed to locate the slide base) - then drops that note as MTEXT at as many picked points as you like, Enter when done - the standing header (`*All listed issues must be resolved to proceed with design*`) on the first line with the note bulleted under it, top left corner at the point, on the `TEXT` layer in the `Attributes` style at 9.5. `Back` at the point prompt un-places the last note instead of ending the run; `Back` with nothing placed yet steps back to the note choice |
| `ABFIND`, `ABMOVE`, `ABFINDVER` | `lisp/abfind/` | Ties a point (typed by number or clicked) back to the **A** and **B** survey stakes with a cross dim to each, then asks whether that point wants moving. `ABMOVE` takes one point and also offers every place it lands if one tape was read wrong - the moved tape swept a foot at a time, ten feet each way, plus the look-alike readings (`21'-1"` written as `21'-7"`, the 1"/11" slip, transposed feet) - drawn yellow, tagged by the tape they move (`1A`, `-3B`), each tag hung off the arc on a leader so it can be read and clicked where the markers crowd, each group on the dashed grey arc it sits on; a click takes the nearest marker or tag, and asks which when the zoom cannot tell two apart - and copies it to `Pt.##m` - the same block, layer, colour, scale and attributes, one number different - rings the old spot with a 5" circle on `FGStep` and writes the `- Moved Pt.17 B from 18'-6" to 18'-5"` note (every note this file writes leads with `abf:*note-prefix*`, one per line, so a run that settles several points leaves a column that reads as a list).  `ABPCREATE` plots a point the drawing has not got, from the two readings it was taped at.  A sheet carrying TWO surveys carries two `A`s, two `B`s and two of every `Pt.##`: the stakes are paired into **AB lines** (`L1`, `L2`, shortest tie first) and the run is on one of them -- `ABFIND` and `ABMOVE` read it off the first point they are given, ringing every point a doubled number names and printing what each was taped at off its OWN stakes, and `ABPCREATE`, which has no point to read it off, picks between the lines themselves.  The answer then stands for the rest of the run, so a later doubled number is answered from it and only reported.  One pair of stakes never sees any of it |
| `ABCDEF`, `ABCDEFVER` | `lisp/abcdef/` | Locates Excel-measured points inside rectangle corners A/B/C/D, "Z" reading order (A/B top, C/D bottom).  Two tapes place a point, three fix it, four cross-check it; a fourth tape is dropped only when leaving it out settles the other three **and** the runner-up triple is clearly worse, so a point near a diagonal keeps all four rather than discarding a good tape.  Reports per point how many tapes placed it, which, and a measured 1-99% confidence, to the command line and to a text file beside the sheet.  Plots as `ab_pt` blocks on `POINTS` and offers `ABHD` the set |
| `ALTABCDEF`, `ALTABCDEFVER` | `lisp/altabcdef/` | Same idea, clockwise A→B→C→D corner order instead - kept separate from `ABCDEF` because the two conventions aren't interchangeable.  Two distances are crossed exactly and a pair from *opposite* corners, which fits two points equally well, is named rather than guessed at; the frame is measured against the dimensions entered before anything is plotted |
| `XYPLOT`, `XYPLOTVER` | `lisp/xyplot/` | `ABCDEF`'s sister for a survey that arrives already reduced: a sheet of X/Y offsets, one picked origin, drawn twice - graph 1 the points as given (`ab_pt` on `POINTS`, ready for `ABHD`), graph 2 the same points with the X and Y offsets dimensioned as two continuous linear chains |
| `CONSTELLATION`, `CONSTELLATIONVER` | `lisp/constellation/` | For the sheet that gives distances BETWEEN points and never says where any of them is. Define a rectangle of known X and Y the points have to sit in, say how many there are - `A` to `Z` - and they are shown clockwise from the top left, evenly spaced round the oval inside it, so you can see which letter is which. Then every pair (`A-B`, `A-C` ...) is on offer and none is compulsory: give the ones the sheet carries, in any order, Enter to walk the chart or type `A-C` to jump. Two dims on every point, and a chain reaching all of them, is the one thing required - short of that the chart is refused by name rather than solved into a plausible-looking wrong answer. Solves in two stages - stress-majorization sweeps to find the right answer, then damped Gauss-Newton to land on it EXACTLY, because sweeps alone converge linearly and a barely-rigid chart (a ring plus two diagonals, an ordinary field sheet) left a given dim 0.19in out after 400 of them and then blamed a tape for it; the same job is now exact in seven Gauss-Newton iterations - so a set of tape readings that cannot all be true still gets the layout that misses by least and the misses get STARRED in the report - and because least squares SPREADS a bad tape over every dim touching it, the worst one is then left out and the chart re-solved, so when that settles the rest the report names the single dim to go and re-measure instead of starring nine innocent ones. Nothing is dropped from the drawing. Distances say nothing about handedness or rotation, so both come off the preview: the mirror that reads clockwise, turned to fit the space and centred in it. A run of points that lies on ONE radius can be declared too, named CLOCKWISE (`A-C`, `ABC` or the wrap `Z-B` = Z A B) - to the solver that is just another point, the arc's centre, a dim of R from every point on it, and it pins what cross dims leave loose: six dims on five points settle the radius end at R139.6 with every dim exact, and declaring the arc lands it on R150.0000. Two points and a radius leave two centres, so that one run alone is asked which way it bows. Draws `ab_pt` points on `POINTS` ready for `ABHD`, an aligned dim per dim given - perimeter dims standing off, cross dims down the chord - and the outline if asked, bending round any arc declared. It then asks whether the drawing looks right, because a number typed wrong is invisible on the chart and obvious on the sheet: `No` reopens the dims, the arcs or both, takes the wrong drawing away and puts the corrected one down. The `Radius for <run>` question stands beside `DIMSTAMP`'s **ruler** offering 2' to 20' by a foot, a curved wall coming off a plan in whole feet; the space bounds and the chart's own dims are measured and stay plain |
| `ABPCHECK`, `ABPCHECKRESCUE`, `ABPCHECKVER` | `lisp/abpcheck/` | `ABHD`'s measuring half, forked as a checker: highlight the whole drawing, say how far off the line is too far, and every survey point is reported with the distance to the nearest line -- `Pt. 17   closest line is 0'-1 7/8" away` -- worst first, the ones over the limit in red and ringed in the drawing. Measures to the run itself, arcs included, not to its endpoints. `ABPCHECKRESCUE` takes the report and the rings away again |
| `POINTRENAMER`, `POINTRENAMERVER` | `lisp/pointrenamer/` | Hands the survey point numbers back out in the order the perimeter runs: highlight the area, Enter takes the closed `POOL` polyline it finds (or pick any polyline, circle, line or arc), click where the count starts, say `Clockwise` or `COunterclockwise` -- meaning on the sheet, whichever way the polyline was drawn -- and how far off the perimeter still counts as on it. Every point within that band is renumbered sequentially sweeping from the pick; whatever sits beyond it continues the count after the loop is closed, swept in the same direction by where each sits against the perimeter, so the leftovers read round the sheet too. Shows the split and asks before writing, prints the old-to-new table so a callout can be chased, counts out loud what carries no number to rewrite (plain `POINT`s, attribute-less blocks) and warns when a point outside the highlight already holds a number in the handed-out range. A number that could not be written -- a locked layer, usually -- is marked `NOT WRITTEN` on its row and counted, rather than reported as a rename that happened. Every knob it has sits in one explained block at the top of the file. One `U` undoes the lot |
| `LOBF`, `LOBFVER` | `lisp/lobf/` | The line of best fit through points that are all meant to be on ONE line - a wall shot at eight stations, a row of deck anchors. Draws three construction lines at once, each in its own colour and numbered on screen on a stalk so no label can be read against the wrong line, and you keep one: **1** least squares on the perpendicular distances, every point pulling on it (not the `y`-on-`x` a spreadsheet gives, so a wall running north-south fits as well as one running east-west); **2** the same fit with a single point set aside - every point tried as the one to drop, the drop that leaves the REST tightest winning - so the error stops being shared and piles onto one point, which is ringed and named for re-measuring; **3** the least-MAX fit, the narrowest band that still holds every point with the line down its middle, tried against the edges of the points' convex hull because that is where the narrowest band always sits. Enter takes fit 2 when the point it set aside is DRASTICALLY worse than the ones it kept - four times the worst of them and at least 1/2" off in its own right, both halves, so a survey that is all inside a sixty-fourth does not get one of its points blamed for noise - and fit 1 when no point stands out that way. The table prints the numbers that decided it either way. Two points make exactly one line, so the picker is skipped; a cloud whose worst point is more than a fifth of the run off the line is called out as maybe not one line at all |
| `CHECK`, `DIMARCCHECK` | `lisp/check/` | Audits dimension def-points and arc endpoints against real geometry, fixing strays |
| `DIMCHECK`, `DIMSCAN`, `DIMCHECKVER`, ... | `lisp/dimcheck/` | Guided, one-at-a-time review of dimension placement, arc-end attachment and overlapping lines, grouped by dimension style |
| `LINFINCHECK`, `LINFINSCAN`, `LITELINFINSCAN`, ... | `lisp/linfincheck/` | `DIMCHECK`'s checks plus steps & side views, wall height, the liner pattern and the title block border - the full liner-finish drawing QA. The report leads with the liner checks; the `DIMCHECK`-style findings sit in a DIMENSION AUDIT column beside it, and `LITELINFINSCAN` skips them entirely for a drawing `DIMCHECK` already went over. The two things it does not just report it FIXES: a pattern field reading `Not Supplied` or `#ERROR` has that phrase - and only that phrase - taken out of it, so `Pattern: Not Supplied` reads `Pattern:` and `Blue Granite - Not Supplied` reads `Blue Granite`; and a `Tech Title` date that is missing, malformed or simply not today is rewritten to today as `MM/DD/YYYY`, label and all. The scans say NEEDS WIPING / NEEDS UPDATING and write nothing |
| `COVERCHECK`, `COVERSCAN`, `LITECOVERSCAN`, ... | `lisp/covercheck/` | Same guided review, rules swapped for pool-cover QA; same split report, with `LITECOVERSCAN` as the cover-rules-only scan. The cover rules only ever SUGGEST, with one exception: a wrong `Tech Title` date is rewritten to today as `MM/DD/YYYY`, keeping any `Date =` label - `COVERSCAN` says NEEDS UPDATING instead |
| `SPACHECK`, `SPACHECKSCAN`, `LITESPACHECKSCAN`, `SPACHECKRESCUE`, `SPACHECKVER`, `TUTORIALSPACHECK` | `lisp/spacheck/` | The same guided review for spa sheets: audits a drawing against what `SPA` draws - bounded outlines, the dimension roster and its notes, hinges against the block's grade/taper and the Hinge Arrangement Chart, and a title block at exactly 0.6x the liner block. A wrong `Tech Title` date is rewritten to today as `MM/DD/YYYY` rather than left to be noticed; the scans say NEEDS UPDATING and write nothing |
| `CCPRECHECK` | `lisp/ccprecheck/` | Walks the "Tech Flow Chart" product-type decision tree and prints a summary. Renamed from `CHECK` to resolve a name collision with `lisp/check/` |
| `LAZDIAG`, `LAZLOG`, `LAZLAST`, `LAZDIAGVER` | `lisp/lazdiag/` | When any calofin command fails, the drafter is told so in as many words and the whole failure is written out as a DXF in their Downloads folder - `POOL-v2.7-error-2026-09-11-143207.dxf` - to send in for diagnosis. The file holds a copy of the geometry the run drew and of whatever it was working on, every point that was clicked labelled with the prompt it answered, the transcript prompt by prompt, the error text, the last step reached, and AutoCAD's own `ERRNO` / `CMDNAMES` / `LASTPROMPT` and sysvars. Every answer the drafter gave is in that transcript, typed, and read against the others - THE INPUTS, AND WHAT IS ODD ABOUT THEM flags a zero, a negative, two lengths that are the same number, two picks on one spot, and says when nothing stands out - and `tools/probe_report.py` replays the report in the test VM, one answer changed at a time, to say which one the failure is tied to. The report also runs the failed tool's OWN SELF TESTS - every tool carries a table of its helpers on inputs whose answers are known - on that machine, after the failure, and writes one line per entry and a verdict: a FAIL there is the tool's arithmetic answering differently on that machine (a knob LAZTUNE moved, a shop term, LUNITS or DIMZIN, the AutoCAD version) before any answer of the run was typed, which no transcript could show. Every report also writes THE MACHINE down - the AutoCAD version, platform and locale, the units family, the selection and dialog switches, with the ones known to break an AutoLISP tool flagged `!!` and the reason beside each (ANGDIR clockwise, PICKFIRST off, ATTDIA on, EXPERT up, OSNAPCOORD overriding typed points, a REFEDIT or Block Editor session) - the state of every layer the run touched (a LOCKED one refuses every write without a word), WHAT THIS MACHINE HAS CHANGED FROM SHIPPED (every LAZTUNE override as typed, with the value the session holds now, the shop terms, the theme, the folders) and every calofin file loaded with its version, so a mixed install shows; THE INPUTS flags a pick far from the geometry and one off the plane too. Nothing is asked and the open drawing is not touched. `LAZDIAG` typed by hand writes the last failure's report again - useful when the folder was read-only the first time - and, with nothing to report, writes a self test instead, which is how you find out reports will reach you BEFORE you need one - and that self test runs every loaded tool's own self-test table and names each tool's count, so a helper gone wrong on a machine is found before it fails a run. `LAZLOG` is the other half: every calofin command writes one line when it finishes, is backed out of, or FAILS - `ok`, `quit` or `FAIL` - into a monthly log beside the profile, and `LAZLOG` shows it and names the file. That is what turns a failure from an event into a rate, tells you which prompt drafters quietly give up at, and puts the runs either side of a crash into the report itself. A crash itself is caught too: every run writes one line into a journal beside the log as it begins and clears it as it ends, so a run AutoCAD closed, crashed or was killed inside is logged `LOST`, with its drawing, by the next run's begin. And `LAZLAST` covers the failure no handler ever sees - the run that finished and drew the wrong thing: typed straight after it, it writes that run out as a RUN report (`TOOL-ver-lastrun-date.dxf`, titled as no failure) with its transcript, everything drawn since it began, the machine and the tool's self tests, to send in with a note saying what came out wrong. Only if no folder at all will take the file does it offer the last resort: pick a spot well clear of your work and the report is placed in the current drawing as text |
| `LINCHECK` | `lisp/lincheck/` | Companion checklist routine, shipped alongside the flowchart walker |
| `STOCKCOVER`, `STOCKCOVERVER`, `STOCKLIST`, `STOCKCOVER-CFG` | `lisp/stockcover/` | Replaces a highlighted perimeter with a stock cover drawing pulled straight out of the stock DWG folder, lined up on what was highlighted |
| `MATCHSTD`, `MATCHSTD-CFG` | `lisp/standards_checker/` | General-purpose drawing-standards matcher/checker (modular: config, cache, geometry, tolerance, UI) |
| `LINTXTCHK` | `lisp/lintxtchk/` | Places the vinyl-liner QA checklist into the drawing as text |
| `CORNERSTP`, `HEMISTEP`, `NORMIESTEP`, ... | `lisp/cornerstp/` | Corner-step layout routines for pool corners - three files here, one `STEPS` release (see below). Where a run sits is read off the geometry, never guessed: NORMIESTEP's corner mode puts the steps in a recess OUTSIDE the corner, because the two lines you select run away from it into the pool, and it draws both sides of that recess; HEMISTEP's side profile reads FROM THE WALL, so the first depth it asks is the drop at the wall and the first tread the flat against it. Every step tread and every step depth after the first is asked beside `DIMSTAMP`'s **ruler** -- the eighths for an inch either side of the last answer -- and clicking a row is the answer, so a flight of near-equal treads or risers is clicked rather than retyped; `24-1/8`, `2'` and `10-3/4` all read as they say (fractions dashed: at a click-or-type prompt the spacebar is Enter, so `24 1/8` would enter 24 and hand `1/8` to the next question) |
| `PADDLE`, `TUTORIALPADDLE` | `lisp/paddle/` | Finds concave perimeter features and inserts pad blocks. Geometry that chains into a perimeter except for a drafting gap is recognised as one rather than reported as loose lines: the chains and the gaps between them are walked, and when they go round once and come back it draws a red arrow at every open joint and offers to close it with a zero-radius `FILLET`. Yes closes it and the run carries on into the perimeter that leaves; No leaves the arrow standing to work from. A gap whose two ends are on ONE open polyline is joined in place instead of being handed to `FILLET` (two picks on one polyline would throw away every segment between them): its first vertex moves to where the end segments cross, its last goes, and the closed flag goes on. What the fillet did is read back off the drawing, never assumed, so a pair `FILLET` refuses is said so. The arrows are `PADDLE`'s own marks on layer `PADDLE-GAP` -- every run clears them and re-marks whatever is still open |
| `MOHAMADDLE` | `lisp/mohamaddle/` | `PADDLE`'s own engine with one thing added in front: it asks which pad size to place (24" or 36", both shipped in `PADDLE`'s `24inpad.dwg`) before it scans anything, and remembers the pick as the next default for the rest of the session. `PADDLE`'s gap pass came over with the engine, so a perimeter that closes except for a drafting gap is arrowed and offered the same zero fillet here, after the size pick; the arrows go on `PADDLE`'s own `PADDLE-GAP` layer, the way the two already share `PADS` |
| `UPADOVER` | `lisp/upadover/` | Pads a named STRETCH of perimeter rather than the features on it. Click the wall -- or the line or polyline that already IS the stretch, and answer `Whole` for all of it end to end, which is the whole flow for a run somebody has already drawn. Otherwise say where the pads start and where they end -- a click anywhere on the wall, or a survey point's number the way `ABHD` and `PERPMARK` take one ("17", "Pt.17", "#17", "017" are one point); a pick that sits off the wall is projected onto it and told how far it had to come. Of the two ways round a closed perimeter the SHORTER stretch is taken and both lengths are reported -- but when the two come within 30% of each other (`upad:*evenpct*`) calling one shorter is a coin toss, so the question is put instead: one click on a spot the run passes through, which is `PERPMARK`'s own wording for the same question. A pad then goes down wherever the run comes out from under the pads already there, ONE PAD ACROSS from the pad it came out of along the axis it came out through: two pads offset by exactly their own width on one axis meet on that line and cannot lie over each other whatever the other axis does, so the other axis is left free and FOLLOWS THE WALL. It is laid holding two things -- that it covers the point the run crossed the seam at, and that it shares at least `upad:*mincontact*` of that edge rather than touching at a corner -- and what it actually covers is walked again rather than assumed. (v1.1 laid them on a fixed grid instead, which stair-steps whatever the wall is doing: on the drafter's comparison drawing the same run took 18 pads that way, 14 by hand, and 12 this way.) The one thing that stops a cover is a run coming back within a pad's width of itself -- a slot narrower than a pad, or a loop closing on its own first pad -- and those stretches are left bare, measured and named rather than doubled up. The start is straddled by half a pad and the far end carried past rather than stopped on, which is the safe direction to err in. `PADDLE`'s block and `PADDLE`'s layer: 36" `Pad36x36` on `PADS` |
| `LINGUTTER`, `LINGUTTERSCAN`, `LINGUTTERVER` | `lisp/lingutter/` | Guts a highlighted area back to the pool and nothing else. Inside the highlight -- and only inside it -- it walks the **outer face** of the lines, arcs and polylines and draws its own perimeter over it: ends closer than a snap tolerance count as one point, and the walk always takes the hardest available right turn, so interior geometry (hopper, steps, a tie line) is never stepped onto and an outward spur is pruned. Three snap tolerances are tried in turn and the result is measured against what was highlighted before it is believed, so an outline with a gap in it can no longer be quietly replaced by a hopper that did close; when no exterior can be walked at all it wraps the highlight in its convex hull and says so. The perimeter is redrawn as one closed polyline on `POOL` (ByLayer, arcs kept as bulges); everything else highlighted is erased, except a radius or diameter dimension whose one attachment point lands on that perimeter (regardless of style -- a corner radius under a foot lands in `STANDARD INCHES` like any other short measurement, and that call-out is not the thing to erase), `STANDARD` / `SIDE STANDARD` dims whose every attachment point lands on that perimeter, and -- only when "Keep CROSS DIMENSIONS?" is answered Yes -- a `CROSS DIM*` dim that reads as a genuine cross measurement of the pool: both points belong to the perimeter at all, and either span at least `lg:*crossspan*` of its width or height ("goes full X" / "goes full Y") or sit at two of its own vertices (corner to corner along one whole edge, however short); a dim whose two points sit on the SAME single edge without being that edge's own two endpoints -- the start of a line to a random point in the middle of it -- is never kept this way, whatever it spans. The new perimeter then goes to `PADDLE` through `*calofin-handoff*` -- a global PADDLE reads and clears before its own pickfirst probe -- so it pads that loop rather than auto-detecting past it, whatever the drafter's PICKFIRST (a pickfirst set is only read with PICKFIRST at 1, and a drafter at 0 used to get PADDLE's prompt, where Enter auto-detected the title block border). It asks that one CROSS DIMENSIONS question and nothing else -- never a confirmation to erase -- then reports what it found and what it would drop -- by style, so nothing goes silently; `LINGUTTERSCAN` asks the same question and prints the same report, and changes nothing |
| `PERPPTS`, `CPERPPTS`, ... | `lisp/perp_points/` | Perpendicular offset points along a line or curve, joined with straight segments, arcs or a mix of both; asks whether the overall width has been re-measured, and has a repeat-on-the-new-polyline step. That width question is asked of **every** line the command draws, not just the one selected: a course built from typed offsets comes out only as wide as they add up to, and the next round is spaced along it, so each one is offered the same correction the moment it appears. A change is split evenly, half at each end, unless you say otherwise -- then it asks how much of it is at the START end, the one the red arrow marks, and the rest goes on at FINISH; the resize is one scale about a point on the line through the ends, so the shape is carried along whatever the split. Both take an optional **boundary**: any curve already drawn -- a property line, a house wall, a deck edge -- and then ask whether the offsets STOP at it (`Limit`: the maximum every offset may reach, measured per point along that point's own normal, since a boundary at an angle to the run is nearer at one end than the other; the length prompt names the distance, `Max` takes it exactly, and a longer length is brought back to it and said so) or RUN OUT TO MEET it (`Meet`: every point with the boundary ahead of it lands on the boundary, no length asked). From the second length on, `DIMSTAMP`'s **ruler** stands beside the drawing at every length prompt -- the eighths for an inch either side of the last length, graded like a tape -- and clicking a row IS the length, so a run of near-equal offsets is clicked rather than typed over; a typed one reads the way `DIMSTAMP` reads (`44-1/2`, `4'4.5` -- dashed, since the spacebar is Enter there) |
| `PERPMARK`, `PERPMARKVER` | `lisp/perpmark/` | `PERPPTS` for the survey that arrives as a list of POINTS rather than an even spacing - a bench, a ledge, a gutter, anything taped square off the wall at the numbered shots. Select the perimeter, then name a survey point and type what it measured, for as long as the sheet lasts. Which way a mark runs is read off the wall itself: a CLOSED wall defines its own inside - the direction it was drawn in turns the tangent into the water at every point of it, so a notched shape marks inward on every arm and nothing is clicked. Only an OPEN wall, which has no inside, still asks which side the water is on. When the round ends it reads its own numbers back: a distance sitting against BOTH its neighbours along the wall by more than 2in is named with the number they put there (40, 10 and 30 in a row is a digit, and the wall between a 40 and a 30 is about 35), and so is a tape that reached past the far wall - nothing is changed, because naming that point again already replaces its distance. The point is clicked or typed at one prompt - `17`, `Pt.17`, `#17` and `017` all name the same one - and it is the family's own point, the `ab_pt` classifier `BPCALLOUT`, `CDCALLOUT`, `ABFIND` and `LHD` share; a number nothing carries, a number two points share and a click on nothing are re-asked rather than guessed at. Each named point gets a circle of that radius - the swing of the tape - and a line of that length running square off the wall; a shot sitting off the fitted perimeter is projected onto it, so it still marks the wall. Naming a point twice REPLACES its mark, because the sheet has one distance at a point. `Back` takes the last mark away again by name, `Enter` ends the round. Then, if the marks are meant to BE something, it joins them: name the point the run starts at and the one it ends at, and one polyline goes through the far end of every mark between them, in the order the WALL runs rather than the order they were named. Two ends cut a closed wall into two arcs and it is the MARKS that say which arc the run is - the one carrying more of them - so the ends can be named in either order and the run comes out the same, read from whichever was named first; only a genuine tie, the same number on each arc, asks anything, and then it is one click on a spot the run passes through. A mark the run does not reach is named before the drawing is finished (`Pt.7 and Pt.9 sit outside the run`) and keeps its dimension, because a partial run is ordinary and a measurement going quietly missing is not. A run end at a point that was taped takes that mark's distance; one at a point that was not measures zero, which is how a step that dies back into the wall is drawn - and it is the point's own identity that decides which, never how close the two landed. The circles then go and every line becomes a dimension in the style you pick - `STANDARD INCHES` or `SIDE STANDARD`, the question `PERPPTS` and `CPERPPTS` ask in the same words, and only asked when there is a polyline to draw. Answered `No` at the join, every circle and every line is left exactly where it is. From the second distance on, `DIMSTAMP`'s **ruler** stands beside the distance prompt -- the eighths for an inch either side of the last distance, graded like a tape -- and clicking a row IS the distance; a typed one reads the way `DIMSTAMP` reads (`44-1/2`, `3'8` -- dashed, since the spacebar is Enter there) |
| `AUTOBEAD`, `AUTOBEADVER`, `TUTORIALAUTOBEAD` | `lisp/autobead/` | Offsets ("beads") selected pool lines toward a clicked side |
| `DCE`, `DIMCONTEND` | `lisp/dim_continue/` | Chains `DIMCONTINUE` from a seed dimension out to every remaining feature point |
| `DIMSTAMP`, `DIMSTAMPVER` | `lisp/dimstamp/` | Click a point, type a feet/inch/fraction dimension text **or a letter label**, and it lands there as an `MTEXT` written the way the shop's dimension text already is: the `TEXT` layer, the `Attributes` style, 6" high, attached TOP LEFT at the click, unwrapped, upright, ByLayer - each of those a knob, and a drawing missing the style gets a plain one made and is told. Down a strip of the SCREEN near its RIGHT edge a scratch RULER appears - a vertical column of nearby values, each a tick and a label graded like a real tape measure: eighth-inch steps are the smallest text and shortest ticks, quarters and halves step up from there, and the whole-inch jumps (1"/2"/3" either way) are tallest and boldest; the row that is the CURRENT value is not one of the options, so it is drawn as a stamp rather than as a ruler - tick, label and a RING round the spine all on the stamp's own layer at the stamp's own colour (ByLayer), which is what makes the row you are on stand out from the rows you can click, and read as the thing it would stamp. It is pinned to the VIEW and sized as a fraction of it, so it holds the same place and the same size on screen whether the drawing is zoomed to a whole pool or to one step; that strip is reserved, so stamps land outside it. The right edge is where it sits over the least drawing, and its ticks and labels reach INWARD from the spine - hung the other way they would be drawn past the edge of the very screen the ruler is pinned to. That direction is derived rather than set: `ds:*ruler-screen-x*` is still the whole placement knob, and a value under 0.5 puts the ruler back on the left with its rows turned round to reach right. From there one prompt does three jobs: click empty space to stamp the current text again, click a row on the ruler to adopt that value without stamping, or type a new value outright - Enter ends the run. The ruler is scratch, on its own layer, swept away as it redraws and for good when the run ends; only the stamped `MTEXT` survives. What it WRITES is one of four forms - `34"`, `3'-4"`, `34 1/2"` or `4'-1 1/2"` - and a fraction in a DRAWN one is STACKED, through AutoCAD's `\S` code and with no space in front of it (`\A1;4'-1{\H1.0000x;\S1/2;}"`, which draws as `4'-1` and a stacked half): the stack is the separation, so a space there would only push the inch mark off the number. It carries its own HEIGHT and ALIGNMENT codes because the shop's dimension text does - an `MTEXT` out of one of these drawings reads `\A1;33'-2{\H1x;\S1/2;}"`, not a bare stack - and both are there for one reason: left to size itself AutoCAD draws a stack at 70% of the text around it (its `TSTACKSIZE` default), so the half came out a size down from the number it belongs to, and a stack sized back up has to sit on the line rather than tower over it. `ds:*stack-hgt*` is `1.0`, the size of the whole inches beside it, and the braces close that height where the fraction ends so the inch mark after it is back at the stamp's own size; `ds:*stack-align*` is `1`, centred (0 bottom, 2 top). Either knob set to `nil` writes that code out of the spelling altogether. The plain spelling is what a prompt offers and what the command line echoes, since nothing stacks on a command line and `4'-11/2"` there would read as eleven halves; `ds:drawn` is the one door between the two, so no call site can forget it. **Letters** are the other thing it stamps, because the survey points are named in them: type a letter rather than a measurement and the tool turns over to labelling - `A` is 1, `Z` 26, `AA` 27, a spreadsheet's columns, which is the sequence a shop whose points arrive in Excel already reads - and the ruler offers the letters either side instead of the eighths, since what is near `A` is `B` and not 1/8". The one real difference is what a stamp leaves behind: a measurement STAYS, because dimensioning is stamping `34"` in three places, while a letter MOVES ON, because a run of labels is A, B, C and never A, A, A - so click, click, click lands `A`, `B`, `C`, the line back names the next one, and `ds:*letter-advance*` turns that off for a drawing that wants the same label twice. A label is one or two letters (`ds:*letter-max*`), A through `ZZ`; a longer run of them is a word typed by mistake and is refused rather than stamped. Nothing in a label stacks, so its drawn spelling and its plain one are the same string. What it READS is far looser, because nobody types a dimension carefully twice: the inch mark is optional (or two apostrophes), the dash after the feet mark is optional, inches may be decimal, a fraction may be spaced or dashed, so `4'4.5`, `4'4-1/2` and `4'-4-1/2"` all mean the same thing and all get STAMPED as `4'-4 1/2"`, rounded to the nearest eighth. A SPACE only works at the first text prompt, which reads a whole line; the click-or-type prompt after it is a `getpoint`, where the spacebar is Enter, so type the dashed spelling there. A lazy answer is echoed back as what it was taken to mean (`read as 4'-4 1/2"`), which is where a mis-type is caught by eye rather than in the drawing. The ruler offers every eighth for a whole inch EITHER SIDE - `44"` offers `43"` through `45"`, since a measurement is read back off the tape as often downward as up - with quarters and eighths on the one ruler told apart by tier, and a value with feet in it gets 2" and 3" jumps beyond that inch as well |
| `CLEARDIM`, `CLEARDIMSCAN`, `CLEARDIMVER` | `lisp/cleardim/` | Slides dimension text along its own dimension until it is readable, and leaves the readable ones exactly where they are. Every dimension's text has one **track**, and it is made of the dimension itself: the dimension line for a linear or aligned one, the dimension ARC about the vertex for an angular one (2-line and 3-point both), the radial line for a radius or diameter, and the leader for an ordinate. Moving along it is free; moving off it stops the text sitting on the thing it measures and has AutoCAD draw a leader to explain where it went - so a linear text keeps its offset above the dimension line to the last decimal and an angular one keeps the RADIUS it rides at. The track's parameter is a DISTANCE in every case, an arc length round an arc rather than an angle, which is what lets one pair of step and reach knobs mean the same thing on both. Hard to read is anything under the letters: another dimension's text, any line, polyline edge, arc, circle, `TEXT` or `MTEXT`, the dimension lines, arcs, radial lines and leaders of the OTHER dimensions in the sweep, and its OWN extension lines, which cross its track at right angles. The one thing that is not ink is the piece of itself the text RIDES, because AutoCAD breaks that around the text. **The one that is already good does not move**: text that cannot move goes down first and keeps its spot, then text already clear of everything fixed keeps its spot too, and only then is the text that is on something routed around all of it - each pass in reading order, so two texts clear of the drawing but not of each other resolve the same way every run and nothing moves that did not have to. A text that must move goes to the NEAREST clear spot, stepped outward and then bisected back so the move is the smallest one that works, trying first the way back toward where its family says it belongs - the middle of the dimension line, the middle of the arc's sweep, the circle a radius measures to, and for an ordinate simply further out, because a leader is made longer to get its text clear and never shorter back onto the work. An ordinate's leader end travels with its text; the feature point never moves. A text with nowhere clear inside `cd:*reach-f*` is left where it was and named in the report, because a text parked somewhere arbitrary is worse than one the drafter can still see on a line. A track that CANNOT be read is never guessed at - two parallel lines cross at no vertex, an ordinate with no leader has no axis, and a vertex the measured angle in group 42 disagrees with is refused - and nor is a dimension on a locked layer or with its text suppressed; all of them are still ink. `CLEARDIMSCAN` is the same analysis with the writing left out  **A line of dimensions is one dimension**: where several dimension lines are the same straight line - what `DIMCONTINUE` lays down by the handful and `AUTODIM` lays whole perimeters out as - they are a RUN, one continuous dimension with breaks. A run's text stays in its OWN segment (one shuffled past its own extension lines reads as the dimension for the span next door); a run's dimension line and extension lines are its OWN, because a continued chain SHARES them; and when one member has to stand further off the work they ALL go, so the line of them stays a line. A run that crowds ITSELF - four segments 30 wide with text 40 wide, nowhere along the track to go - is STAGGERED instead: every other dimension stands a row further off the work, its own dimension line with it, and every text stays centred where it belongs. Which of the two happens is decided by who is in the way: run-mates alone means stagger, anything else means the whole run goes. Only linear and aligned dimensions join a run - the others keep a centre or a feature in group 10, not a dimension line location |
| `AUTODIM`, `FLOORDIM`, `STAIRDIM`, `AUTODIMSIDEPOV` | `lisp/autodim/` | Auto-dimensions a highlighted plan - perimeter sides and arc radii, stairs, the floor dims it asks about, two overall dims. Turn the floor dims down and it offers `PADDLE`'s pads instead - the two are alternatives, and the plan you highlighted is handed straight over, so nothing is picked twice; the pads go in last, after this command's own state is back, so one `U` backs them out and the next one the dims. Step 2 asks what to do about a size that repeats - `[All/Typ] <Typ>`: `Typ` calls one out, notes it `Typ.` and leaves the rest to that note (from two equal sides, or four equal radii), `All` dimensions every one of them where it is. It is the first question the command puts, so `Back` there re-opens the step-1 highlight, and it is asked before the undo group opens, so backing out of it leaves nothing behind; `ad:*typ-default*` moves the Enter answer for a shop that wants the other one every time. Perimeter and stairs `SIDE STANDARD`, floor and overall dims `STANDARD`, anything under 12" `STANDARD INCHES`; a place that is dimensioned already is left alone. Highlight a flight of steps drawn in side view instead and `AUTODIM` recognises it and dimensions the depth of every step down the right in `STANDARD INCHES` |
| `SMARTFILLET`, `SMARTFILLETVER` | `lisp/smartfillet/` | Fillet a corner after showing what each radius would look like: pick the two lines and every radius that fits - 6 up in 6s plus the 3 and the 9 that turn up but are not the step, tangent points landing on both legs - is drawn as a lettered arc. The fan is graded light green to dark green with the radius, each arc part transparent so the ones crossing underneath still read, each label in its own arc's shade and one rung further off the leg than the label before it; the odd sizes are dashed where the sixes are solid. Two lines that stop short of where they meet get a dashed run from each leg's own end out to the corner FILLET would extend them to, so the fan is not a set of arcs floating round a point on neither line. Click the arc **or the R-number lettered beside it** - both are that size, and on a tight fan the label is much the bigger target - and that corner is cut for real and given its radius dimension; it then offers the same radius for the rest of the corners, and the one callout becomes `R12 Typ.` as soon as a repeat is cut |
| `HONEFILLET`, `HONEFILLETVER` | `lisp/honefillet/` | SMARTFILLET's spinoff for the sizes BETWEEN its radii, for a corner that wants something the 6-inch step cannot say. The same corner picks and the same fan, and then instead of cutting the one clicked it asks for **two**, either side of the size wanted, and redraws just that range in half-inch steps - both ends included, so settling back on the round number is still one click, and the whole inches solid against the halves dashed. Every pick in the run - both bracket picks and the cut - takes the arc or the R-number lettered beside it, which on a fan half an inch apart is much the bigger target of the two; a corner the two lines stop short of gets SMARTFILLET's dashed runs out to it, redrawn with the honed fan. Click one of those and it is cut, dimensioned `R13.5` rather than rounded to suit the tool, and offered for the rest of the corners exactly as SMARTFILLET offers a round one. Two picks that are not neighbours are turned down and asked again rather than truncated: what counts as neighbouring is `hn:*maxfine*`, how many honed previews can be read at once |
| `CDCREATE`, `CDCREATEVER` | `lisp/cdcreate/` | Turns every highlighted line into a cross dimension - `CROSS DIMENSIONS` style, `DIMENSION` layer, dim line on the line, text 80% toward the right/bottom end, source line erased. A tie that is dimensioned already is left alone |
| `CUSTBLOCK`, `CUSTBLOCKVER` | `lisp/custblock/` | Draws a custom block in pictorial view from three typed sizes - length (the long axis, receding back-right at 45 degrees and at true length), width across the front face, height up it - based at its front bottom left corner. Nine lines on `COVER`: the front, top and right-hand faces, with the three hidden edges left out so it reads as a solid rather than a wire cage. Dimensioned three times on `DIMENSION` in `STANDARD INCHES` - the length aligned along the top-left receding edge, the height and width linear with their axes forced |
| `DRONE` | `lisp/drone/` | Drawing cleanup: text style/height, pool/spa points onto `POINTS`, spa perimeter onto `POOL`, and more in one pass |
| `TYDRN`, `TYLERDRONESUITE` | `lisp/tydrn/` | `DRONE`'s pool-only sibling for a drone trace with no spa: the same text and point cleanup with no SPA-point sweep and the `SPA` layer never touched (see `lisp/tydrn/README.md` for the exact split). `TYLERDRONESUITE` is the whole drone trace in one: `TYDRN`, then `PADDLE`, then the shop's own `CDIM`, in the order the work has to happen in - the points have to be on the right layer before `PADDLE` can find the features to pad, and `CDIM` finishes over whatever dimensioning the drawing carries (`AUTODIM` sat in this flow once; its operator wants it out, and `*tydrn-suite*` puts it back). The trace is highlighted ONCE and carried: the calofin stages want the same thing picked and AutoCAD clears the pickfirst set as soon as a command consumes it, so the suite reads it at the start and hands it to each stage through `*calofin-handoff*` (the stage's name and the set, read and cleared by that stage alone) - grown by what each stage drew, so a later stage opens with the earlier ones' work. It no longer switches PICKFIRST on round the stages: that left a drafter who works at 0 at 1 whenever a stage failed or was Esc'd. CDIM gets a cleared selection, since the dimensioning it tidies is in nobody's original pick. Nothing is reworded: each stage is the command itself, asking its own questions, and each keeps its OWN undo group, so one U per stage backs the suite out and a stage that went well is not undone to get at one that did not. The calofin stages are checked before any of them runs - half a suite is worse than none; `CDIM` is not (`boundp` cannot see a .NET or PGP command); each calofin stage is its `c:` function called directly - the command processor does not know AutoLISP commands, so `command`/`vl-cmdf` would say Unknown command - and `CDIM` is queued on the command line verbatim via `SendCommand`, the one door .NET, ARX and PGP aliases all answer to, unless AutoLISP defines it here. `*tydrn-finish-cmd*` renames it or turns it off |
| `SQUAREUP`, `SQUAREUPVER` | `lisp/squareup/` | A survey does not arrive square: the tape is walked round the pool whichever way the deck allowed and the drone photo is taken from wherever the operator stood, so what lands in the drawing sits four or five degrees off - close enough to look deliberate, far enough that every horizontal dimension is a hair long. Highlight the work (Enter = the whole drawing), pick the one outline that says which way is along, and the whole highlight turns about the middle of that outline by the SMALLEST angle that squares it - a wall lying at 176 degrees is put flat by turning 4, not by turning 176 and standing the drawing on its head. **Two things can be "the longest length"** and both are measured before the question is put, so the choice is between two numbers rather than two words: `Wall` is the longest STRAIGHT RUN, which is a rectangle pool's long side - a run a trace split into five collinear pieces is one wall, and a run that BOWS stops being one where it has bent `sq:*collinear-deg*` from its own start direction - and `Span` is the longest distance ACROSS the outline, which is the only answer a kidney or a freeform pool has. `Wall` is the default and `Span` the fallback: a perimeter with no straight run in it is squared to its span and says so rather than asking a question with one answer. Nothing is scaled, mirrored, moved, drawn or erased and no layer, colour or style is touched - the drawing that comes out is the one that went in, turned, in one undo group. Two things it refuses to do quietly: a drawing already square (under `sq:*square-deg*`) is left alone rather than turned by a millionth of a degree onto the drafter's undo stack, and an outline picked from OUTSIDE the highlight - which would stand still while everything else swung round it - is asked about before anything moves. Because ROTATE SKIPS an object on a locked or frozen layer without saying so, both bits are cleared for the length of the turn and put straight back, on the failed path too: half a drawing squared is worse than none, because the second is obvious and the first is not. Horizontal means horizontal on the SCREEN - the current UCS's X axis - so a drafter working under a rotated UCS gets the direction they can see |
| `OSR`, `OSRVER` | `lisp/osr/` | Object Snap Restore. Running object snaps drift - Tangent ticked for one arc, Nearest for one leader, F3 turned off to click in open space - and the way back is fourteen tick boxes from memory. `OSR` sets OSMODE to a preset the drafter chose once and says which modes it put back; nothing is asked. The preset is chosen in the panel's Options (`LAZSET`, the **Object snaps** box: the same fourteen modes as AutoCAD's Drafting Settings, Object Snap On, **Use current** and **Default**) or with `CALSET` -> `Osnaps`, and lives in the profile under `CalofinOsnapPreset`. With none saved it puts back Endpoint, Midpoint, Center, Node, Quadrant, Intersection and Perpendicular (`osr:*default*` = 191), Object Snap on. Object Snap Tracking (AUTOSNAP) and 3D snaps are not touched |
| `VSCONV`, `VSRECONV`, `VSCONVVER` | `lisp/vsconv/` | Converts a VS survey export onto the shop layers in one pass: the exporter's numbered layers are remapped by `*vsconv-map*` -- `1 Perimeter`, `2 Coping` and `3 Features` onto `POOL`, `3.1 Anchors` onto `POINTS`, `4 Dimensions` onto `DIMENSION` -- with color, linetype and lineweight forced BYLAYER (`*vsconv-force-bylayer*`, on by default; `SOCONV` carries the same switch off, each for what its sample does) so the moved geometry takes the destination layer's appearance rather than the export's. The dimensions are then put on `STANDARD` **and stripped of their style overrides**: the export writes text height, arrow size and decimals into each dimension as `ACAD`/`DSTYLE` xdata, and an override outranks the style it sits on, so a dimension merely renamed would still draw in the export's 2.5-unit text. Scope is the highlight, or Enter for every VS layer in the drawing; a drawing carrying none of them is reported as such instead of prompting. The emptied source layers are named in the done line rather than purged, so one `U` backs the whole run out. **`VSRECONV` undoes the whole thing**, and not only while the session lasts: every object the conversion moves carries a record of what it was in its own xdata -- the layer it came off and that layer's colour, the colour, linetype and lineweight the BYLAYER forcing overwrote, and for a dimension the style name AND the `ACAD`/`DSTYLE` override block kept verbatim -- so a drawing saved, closed and reopened a week later still goes back exactly as it arrived, overrides and all. `*vsconv-record*` is the one line that turns the record off |
| `WCALST` | `lisp/wcalst/` | Unrolls a curved constant-width band flat, with darts/inserts |
| `XFTCONV`, `XFTRECONV`, `XFTCONV-SETUP` | `lisp/xftconv/` | Cleans up a survey import in one pass: scale it ×12 (feet → inches) about the middle of the highlight, then swap every point marker for an `ab_pt` block on `POINTS` with its number in the `number` attribute. Two exports are read, whichever is in the selection: a **Leica XFT** import, whose marker is an X of two `LINE`s on `LEICA_POINT` with the name stacked above it on `LEICA_POINT_NAME` (`P22` → `22`), and a **site trace**, whose marker is a small `CIRCLE` on `POOL_POINTS`, `BREAK_LINES` or `CROSS_MEASUREMENTS` with the name sitting on the centre. A trace draws each corner twice - once as a pool point, once as the end of a diagonal - and the pair collapses into one block; its labels keep their family letter (`C1`, `S1`, `D1` would all strip to `1`). Leftover text is swept for the Leica flavour, whose text is nothing but point names, and kept for the trace, which captions its own break lines and diagonals. **`XFTRECONV` puts the survey back** -- markers, name text, swept text and the ×12 -- because each block it inserts carries a record of what it replaced in its own xdata, so the undo survives the drawing being saved and reopened where `U` does not. A highlight holding two conversions is refused by name rather than half-reverted: they were scaled about different base points, and one scale back cannot undo both |
| `SOCONV`, `SORECONV`, `SOCONVVER` | `lisp/soconv/` | Puts an SO site-survey export onto the shop's layers in one pass: `Pool Perimeter` and `Obstacles` onto `POOL`, the Leica points and `Existing Anchorss` onto `POINTS`, and the export's one `Dimensions` layer split in two - its notes onto `TEXT`, its dimensions (and anything else left there) onto `DIMENSION`. It is a layer remap and ONLY a layer remap: no restyle, no forced BYLAYER, no rotate, nothing erased and nothing drawn - which is what the before/after sample it was written from does, pair for pair over 316 objects, and `*soconv-force-bylayer*` is the one line that changes its mind. The rules are a table (`*soconv-map*`), read in order with the first match winning, so a shop whose export names things differently retunes there and nowhere else; only the destination layers a run actually reaches are created. It converts the whole drawing unless something is highlighted, reports the counts per destination, and names the emptied export layers for you to `-PURGE` - it will not purge them itself. **`SORECONV` moves it all back**, from a record each moved object carries in its own xdata (the layer it came off, that layer's colour, and - only when `*soconv-force-bylayer*` was on - the three properties the forcing overwrote), so the undo outlives the session `U` is good for; a source layer purged on the tool's own advice is re-created with the colour the record kept |
| `G2MCONV`, `G2MRECONV`, `G2MCONVVER` | `lisp/g2mconv/` | Converts a G2M architectural pool plan - AIA layer names with a Spanish half after them (`A-STAIRS - GRADAS`), the architect's own text and dimension styles, an annotative flag on every dimension - onto the shop's layers AND styles in one pass. Five rules in a table (`*g2mconv-map*`), first match winning: the pool wall and the stairs onto `POOL`, the architect's text layer onto `TEXT`, and his one annotation layer split in two - its notes and leaders onto `TEXT`, its dimensions (and anything else left there) onto `DIMENSION`. Where `SOCONV` is a layer remap and nothing else, this one also removes the three overrides that would otherwise outrank the layer or style the object now sits on, because that is what the before/after sample does object for object: the explicit `Continuous` comes off the geometry and the linetype scale goes to the drawing's own `CELTSCALE`, the notes take the shop text style and height (both or neither - a height is measured for the style it is set in), and the dimensions take `STANDARD`, lose their `ACAD`/`DSTYLE` block and stop being annotative. The stairs are the exception the table exists for: they arrive in the architect's `HIDDEN2` and land on `POOL` in the shop's `DASHED2` rather than going ByLayer, because a stair drawn solid on `POOL` is a wall. **`G2MRECONV` puts all of it back** from a record each moved object carries in its own xdata - the layer and its colour, the four appearance properties, the text style and height, the annotative flag, and for a dimension the style name and the whole override block verbatim - so the undo outlives the session `U` is good for; a linetype or style the record names that the drawing no longer has leaves that object's record in place and is named in the report, so restoring it and running again finishes the job |
| `DDGPS`, `DDALT`, `DDELEV`, ... | `lisp/drone_height/` | Drone height above the deck from the photo's own metadata (barometric RelativeAltitude; GPS + ground elevation as the fallback) and the scale correction for raised / sunken features |
| `LISPLAB`, `LISPLABVER` | `lisp/lisplab/` | Learn AutoLISP, not a drafting tool: two lessons - getting things out of the drawing databases (`entget`/`ssget`/the symbol tables/dictionaries/xdata), and putting a list in order (`vl-sort` and its duplicate trap, then bubble, selection, insertion, merge and quick sort written out). Each is an outline plus a worked example that draws a sample and sorts what it reads back |
| `LAZFORM`, `LAZFORMCOVER`, `LAZTXT`, `LAZASCII`, `LAZFORMVER` | `lisp/lazform/` | Fill a dimension chart in and draw the pool from it. Thirteen charts, and two routines behind them: eight POOL sheets - Rectangle, True Oval, Roman, both Grecians, True L Left, Round and Octagon - and five OASIS ones - Center, Top-Right, Cloud, Kidney and NXT Cloud - each the one off the paper: outline, hopper, dimension chain with its letters. The picture is one whole passive image and **every dimension has a labelled box in the column beside it**, with its letter as a button in front of it: the picture is read, the column is typed into, and the letter ties the two together. (v1.6 to v2.5 sliced the chart into bands and wedged the across-chains between them; it came apart into strips, the boxes were only ever placed to within a character cell, and a sheet read as two kinds of thing at once.) Corners get a dropdown each - `Square`, `Radius`, `Cut`, `NotGiven` - and the size box beside it un-greys only for `Radius` and `Cut`; Roman carries four rows, the Grecians and the Octagon carry two collective ones (body corners, end-tip corners) that fan out to the eight individual questions when the pool is out of square, and picking any of them arms POOL's own corner-record gate. Cross dims have a mode dropdown and their boxes, out-of-square only. **Insert draws the pool.** It used to hand over whatever had been typed and leave POOL to ask for the rest a question at a time, which is the interview a form exists to replace; now the sheet carries the whole run or it does not go. Press Insert on an unfinished one and the page does not close: every letter with nothing usable against it is struck **twice, a pixel apart, in red** - what a stroke font has instead of a bold weight - the line under the form names them, and the marks come off one at a time as the boxes are answered. Press it again and it draws, leaving POOL nothing but the point to place it at. Everything that used to be re-asked is answered from the sheet: the pool-bottom gate (a run flag, `pool:*hasbottom*`, because five shape paths reach that one question and the store is consume-once - `LAZFORMCOVER` sets its opposite and greys everything behind it), the Roman's "are both ends perfect", the hopper's straight-side check under its own key now that a Roman asks a perimeter `T` as well, and the `R3` a round pool's hopper asks that the round sheet had no box for at all. `NA` answers any box but a depth - `pool:askh` takes a form answer only when it is a number - and `D` deeper than `C` with `C2` between them is checked here rather than looped on at the prompt. **One rule decides what is live**: the bottom type, the in-square toggle and the mode dropdowns together compute the dead set, `mode_tile` greys exactly it, and exactly it is withheld from POOL - so a greyed box cannot be a value that travels and is never read. The bottom half of that rule is read off POOL's own `pool:btmspec`, so it cannot drift: a Normal hopper draws no side view, so C, D and C2 grey out; a Sport asks a different plan chain, so H, F and E grey out and its own E2-F2-F1-E1 boxes come alive. The oasis sheets read the same way off their own two dropdowns - a cloud's bottom or a kidney's type, and simple-or-complex - and hand their answers to `OASIS` instead: an oasis has no chain and no hopper, so the sheet is the envelope, X across and Y up, with a radius against every arc; a bulge's radius is drawn where it runs and a joiner's gets a leader out to its letter. Those outlines are not artwork either - each is the ring `oasis:solve` builds for that shape's reference drawing, and the test suite re-derives every arc from OASIS and compares. `NA` in a box means not measured and is passed through as such; a blank box just means ask. **A state line under the form says what it is about to do**: `lzf:answer` turns anything it cannot read into not-answered, so a typo used to be dropped in silence while the chart went on showing it - the chart draws the string - and POOL asked again with no reason given. The line names any box in that position by the letter the sheet prints, and `Insert` stays greyed until it is fixed (a depth pair POOL would refuse holds it the same way); otherwise it counts the sheet down - the live boxes **and** the dropdowns that are live with them, because a corner row left on `(ask)` is POOL asking exactly as an empty box is - and says what a finished sheet still leaves at the command line, which on a POOL page is the base point and on an oasis one the floor `OASIS` asks about only once the outline exists. It reports `lzf:form` rather than second-guessing it, and the test partitions every live box into sent, still-owed and unreadable, so the line, the bold letters and the alist cannot drift. **`Recall last`** puts the last accepted sheet for this chart back into the EMPTY boxes only - safe to press twice, never a default, greyed when there is nothing stored - and the static hint now says what a box takes (`24`, or a feet-and-inches spelling). Drawn with `vector_image` from a table of lines, so there is no artwork file to ship. `LAZFORMCOVER` is the same form for a cover sheet: POOL runs with its pool-bottom gate already closed - `LAZTXT` is the same form drawn out of TILES instead of vectors - the pool is a real boxed cluster with the hopper nested inside it and the fields in the drawing, which buys retention (nothing in it is an image tile, so nothing in it can be wiped by a repaint) at the cost of the outline being a rectangle whatever the pool is. `LAZASCII` is a probe, not a tool: it asks whether this AutoCAD's dialog font is fixed-pitch, which decides whether the chart could be drawn in characters instead of vectors - worth knowing because DCL never retains an image tile but always retains a text one - see `lisp/lazform/README.md` |
| `LAZSPA`, `LAZSPAVER` | `lisp/lazspa/` | `LAZFORM`'s argument applied to `SPA`: fill a chart in, press Insert, and the spa is drawn. Three charts - Rectangle, Octagon, Round - with the boxes wedged into the dimension rows, which is the layout LAZFORM carried at v1.6-v2.5 and has since moved off. The Rectangle carries its four corner dropdowns, labelled the way the sheet legend spells them (`90`, `Radius`, `Diagonal`); SPA itself now asks the canonical `Square`/`Radius`/`Cut`/`NotGiven` and normalises the legend words on the way in, so the chart keeps the drafter's vocabulary and the routine keeps the standard's. Every page also carries the water's-edge/cover-size mode, the second outline (by offset or by dimensions, keyed per shape), the lap gap, auto-hinge, and the grade and taper the Spa Cover Details block would otherwise be read for. Two traps are handled rather than inherited: SPA stores a form's `nil` without validating it, so `NA` on a question that must have an answer is demoted to an empty box instead of reaching arithmetic; and the Round flow only *peeks* at `A`, so filling it is what asks for an out-of-round spa - which is what the label says. The block pick and the base point stay in the drawing. **Its state line has a third thing to say**: SPA drops a box unread two ways - `lzs:answer` cannot read it, or `lzs:keyanswer` demotes an `NA` on a key SPA has no NA for, which is the sharper one because `NA` is a word the form itself tells you to type. Both are named on the line and both grey `Insert`. **`Recall last`** puts the last accepted sheet for this chart back into the EMPTY boxes only - safe to press twice, never a default, greyed when there is nothing stored - and the static hint now says what a box takes (`24`, or a feet-and-inches spelling). - see `lisp/lazspa/README.md` |
| `LAZSTEP`, `LAZSTEPVER` | `lisp/lazstep/` | **Type the step count and the drawing follows it.** One page: the drawing on the left, and beside it the step type (`CORNERSTP`, `HEMISTEP` or `NORMIESTEP`), the count, that type's once-only questions - direction, bench, corner treatment, beading - and a box against every dimension the count implies. The picture is *built for that count*: the plan with N treads and their widths, and the side profile with N risers and the N+1 drops, every dimension carrying its letter until you type a number over it. **The count is a field on the page it redraws**, which is the whole of the change: it used to be a page of its own, so the picture the number describes was the one thing you could not see while typing it, and going from 5 to 6 meant Back, retype, Next. DCL cannot add a tile to a dialog that is up, so a new count still closes the page and reopens it - in the same place, with everything typed still in it, which is what makes it read as a field rather than a page boundary - and a count that matches the drawing already on screen rebuilds nothing and simply brings its boxes alive. Until a count is given the picture is a NOMINAL one and every dimension box on it is greyed: a box with no step to belong to is not a box anybody should type into, and nothing typed in one travels. Eight steps is the ceiling, past four the tread chain staggers onto two rows, and the answer column splits in two once it is taller than the budget - all three because DCL will not scroll a dialog past the screen. **Beading is three questions now, not one**: bead at all, which steps carry the bead along their side walls, and which numbers when that answer is Some. All three used to be a chain of live prompts with only the first form-answerable, so a sheet that said Yes still stopped twice at the command line after the drawing was finished; `CORNERSTP`, `HEMISTEP` and `NORMIESTEP` take `beadsides` and `beadnums` off the sheet as well. The walls, the curve, the side to draw toward, the profile's pick and the side to bead toward all stay in the drawing. **Two state lines, and Insert is held back by either**: the run line reads a measurement with `lzt:answer` and the count and bench step with `lzt:int` - `3.5` is the case that separates them, a fine measurement and not a step number - and `lzt:countwhy` is the one rule the live warning, the redraw and the refusal at the gate all read, so they cannot disagree; the hand-off line is named by the letters the drawing shows. **`Recall last`** puts the last accepted sheet for this chart back into the EMPTY boxes only - safe to press twice, never a default, greyed when there is nothing stored - and its slot carries the count, so a three-step sheet cannot land on a five-step drawing. - see `lisp/lazstep/README.md` |
| `LAZSIDE`, `LAZSIDEVER` | `lisp/lazside/` | **`LAZFORM`'s argument applied to the side view alone.** The longitudinal section stands on the left as one whole picture and every dimension it carries has a labelled box in the column beside it, its letter a button in front of it: the picture is read, the column is typed into, and the letter ties the two together. Press Insert and `POOLSIDE` draws it, asking for nothing but the base point. One page per bottom type on a tab strip - Normal, Sport, Wedge, SLope, MOdflat, SHallow - because six floors are six chains of letters, and **the tab you are on IS the answer** `POOLSIDE`'s first prompt asks for, so a sheet cannot be filled in for one floor and drawn as another. `C2` appears only on the SHallow, which is the only floor with a break to measure it at. Nothing here is a stored picture: the section is built from the type's own run chain, depth stations and nominal proportions - `POOLSIDE`'s three tables, carried across because a `lisp/` file has to load alone, and re-read out of `POOLSIDE.lsp` and compared entry for entry by the test suite so the copy cannot drift. `NA` in a RUN means not measured and is read back off B, two of them splitting what is left; **a depth is the exception** - `POOLSIDE` has no `NA` for C, D or C2, so an `NA` there is demoted to an empty box and the line says so rather than leaving you to find out at the prompt. **The state line holds Insert back two ways**: a box that would be silently dropped, and a DEPTH PAIR `POOLSIDE` would refuse - D deeper than C, C2 between them. `POOLSIDE` loops at the prompt until they agree, which is right at a prompt and wrong to hand a sheet to, because the run would draw half a section and then stop to argue; a form can see both numbers at once, so it says so first. One dropdown that is not a letter: whether to put the deep end on the right, which is a fact about the sheet the section goes under rather than a measurement. **`Recall last`** is keyed by bottom type, because a Sport's `E2`/`F2`/`F1`/`E1` mean nothing on a Normal's `H`/`G`/`F`/`E`. The base point stays a pick in the drawing. - see `lisp/lazside/README.md` |
| `LAZPANEL`, `LAZBUTTON`, `LAZPIN`, `LAZHIDE`, `LAZSET`, `LAZNAME`, `LAZTUNE`, `LAZBACKUP`, `LAZICON`, `CALHELP`, `CALSET`, `LAZPANELVER` | `lisp/lazpanel/` | A clickable button panel with the 96 headline drafting commands above - the zero-install GUI: the dialog is plain DCL that the file writes for itself at run time, so there is no DLL to `NETLOAD` and no second file to ship. Loading it also puts a one-button toolbar ("LazPanel", an orange hexagon it generates itself) on screen that you can drag anywhere or dock - click it to open the panel, or `LAZBUTTON` to re-summon it. A **Find** page leads: type any part of a name **or of its caption** and the list narrows to what matches, with the top hit selected so Enter runs it - searching the captions is what makes `survey` find `ABHD`, which says nothing about surveys in its name, and the needle is taken literally rather than handed to `wcmatch`, so a typed `*` searches for a star. Tabs then come in two rows: the **jobs** (Pool / Cover / Spa / Rest), each laid out in columns that follow the work - shape, points, steps, convert what somebody sent you, dims and check. **Pool and Cover carry a Converters column second to last** (one column carrying two labelled runs, `Convert` - `XFTCONV`, `SOCONV`, `VSCONV`, `G2MCONV` - and `Revert` beneath it in the same order, so the Nth button under `Revert` undoes the Nth under `Convert`; two columns side by side would not fit, and the run is what a column entry may be instead of a bare command name. `Cover` carries the two `XFT` ones it has always had, flat, since one converter and one reverter is more frame than content): past the drawing work and in front of the dims-and-check column that ends every job, because a job that starts from somebody else's export is the exception rather than the rule. `Spa` is two columns wide, where second to last is the first column, so it is unchanged - and the **categories** (Layout / Points / Dimensions / Converters / Checking, the same five group names as the VB palette) hold the whole roster filed by what each tool is, `Converters` being the eight that used to be filed under Points. A tool that serves two jobs sits on both, so 96 commands make 216 buttons; `Rest` is computed as whatever the three named jobs leave over. A command not loaded in this session is greyed out - except on Find, which lists it marked `(not loaded)` and refuses to run it with that reason, because a search that omits what you searched for reads as the tool not existing. A click closes the panel, runs the command exactly as if typed, and the panel then REOPENS itself on the same page at the same position - Close is the way out. Beside it, on every page including Find, an **Options** button opens `LAZSET`, the settings as a DIALOG - the theme on a dropdown, a family dropdown plus a hex box for each of the eight item colours, the two folders and a way into the hidden list, all in front of you at once, where `CALSET` asks the same questions one prompt at a time. Nothing is written until `OK`, and `OK` stays greyed while a hex box holds something that is not a hex colour - the same bargain `LAZFORM`'s `Insert` strikes. It is wired like a grid button (the same full teardown before anything runs) but is not a roster launch, so it never lands in Recent. A **Pinned** row on every page carries the few tools you run all day, remembered between sessions in the registry; `Pin...` or `LAZPIN` edits it. Above it a **Recent** row carries the last five you launched, newest first, kept without being asked - minus anything already pinned, since Pinned is by definition the tools you run most and showing them twice would leave Recent saying nothing new; it appears only once there is something in it, so a first-run panel is no taller than it ever was. A tool can also be put out of sight altogether - `LAZHIDE` (or `CALSET`, `Hidden`) opens the same kind of checklist `LAZPIN` does, and a ticked tool stops appearing anywhere the panel shows itself: no grid button, no Pinned or Recent chip, no Find hit, not counted in the status line's total. It is not deleted or disabled - typing its name still runs it, and `LAZHIDE` always offers the whole roster, so a hidden tool can always be found again and un-hidden. Off the panel on purpose: the satellites (`TUTORIAL*`, `*VER`, `*RESCUE`, `-CFG`/`-SETUP`, `DCE`, `STOCKLIST`), the `DD*` drone-height toolset, `LISPLAB` and the deprecated matcher - and `CALHELP`, `CALSET`, `LAZHIDE`, `LAZSET`, `LAZNAME` and `LAZBACKUP`, which are this file's own machinery wearing a command name: `CALHELP` reads the captions out at the command line, where until now the only way to read one was to open the panel and find the page the tool was filed on, `CALSET` shows the settings calofin keeps in the AutoCAD profile, `LAZBACKUP` exports or imports a drafter's names, settings and defaults as one plain text file, for a machine or a profile the registry does not reach, and `LAZTUNE` (`Defaults...` in `LAZSET`) lets a drafter set their own value for any tool's tunable -- the dimension style `AUTODIM` uses, the fraction `POOL` offers for a width -- over the shipped "Alec's choice", from a catalog `tools/gen_knobs.py` transcribes out of every tunables block in the tree. Its last dropdown entry, **Terms**, is the shop's own wording for text the tools write INTO the drawing -- the `Typ.` after the one dimension that stands for a group, the `Not Given` on a corner the order sheet never gave -- set once and followed at once by every tool that writes it (POOL, SPA, NORMIESTEP, HONEFILLET, SMARTFILLET, AUTODIM; the table is `tools/terms.py`), kept in the profile as `CalofinTerm-<id>` and carried by `LAZBACKUP`; a value set on one tool's own knob still wins. Keywords and prompt wording are never terms: forms, the palette and LAZDIAG's replays answer them by their exact spelling. The button's icon follows the AutoCAD theme now: a `.bmp` has no transparency, so the square around the hexagon is painted, and painting it dark-theme grey put a dark tile in every light-themed toolbar from the day it shipped - `LAZICON` reports which grey it used and why. See `lisp/lazpanel/README.md` |

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
  command whose only remaining input is a selection (`DIMCONTEND`, and
  `PADDLE` on geometry that closes) has no prompt left that could offer
  Back - and Back cannot be *typed at* a selection either.  (`PADDLE`
  asks one question when it finds a gap in a perimeter, and there the
  arrow is drawn already and `No` is itself the way past it.) Where a question sits
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

### Which way your screen reads

Every colour a tool draws in is an ACI number, and a number is only
right against one background. `8` is the case that proved it: the
review tools used it to make everything not under review **recede**,
which it does on the stock near-black model space and the exact
opposite of on a white one, and `OASIS`, `POOLSIDE`, `POOL`, `SPA`,
`LOBF`, `ABFIND` and `CONSTELLATION` used the same number for guide
geometry that has to be **read** while it is answered - which works on
white and very nearly disappears on the stock dark grey. One number,
two intents, each correct on one background.

Those knobs now say `'auto`, and the colour is picked per role:

| Role | What it is | Dark | Light | Cannot tell |
| --- | --- | --- | --- | --- |
| `fade` | the review tools' grey-out | 251 | 254 | 8 |
| `guide` | preview and guide geometry | 253 | 8 | 8 |
| `dim` | a chart tile's dimension arrows | 253 | 8 | 8 |
| `hi` | a chart tile's active box | 4 | 5 | 5 |

`fade` and `guide` are drawn into the DRAWING, so they measure its
background; `dim` and `hi` are drawn inside a dialog, where `-15` and
`-16` already follow AutoCAD's interface theme, so they follow that
instead. The two are different questions - a light-themed AutoCAD over
the stock near-black model space is an ordinary way to work. The
toolbar button's icon is the same question again: a `.bmp` has no
transparency, so the square around the hexagon is painted, and it was
painted dark-theme grey for everybody.

**A knob that is a number still means that number**, so a shop that
has picked its own colours keeps them. And the last column is what the
tree drew before any of this: a session that cannot measure is not a
session that behaves differently.

If a measurement comes out wrong - or you simply want the other one -
`CALSET` writes `CalofinTheme` (`Dark` / `Light` / `Auto`) into your
AutoCAD profile, where it beats both probes and survives a rebuild.
The VB palette reads the same answer out of `LAZPANEL`'s registry key,
beside the pins.

### What is loaded, and what a command does

Three commands answer the questions that used to need the panel open
or seventy-two `*VER`s typed:

| Command | Answers |
| --- | --- |
| `CALVER` | every calofin file this session is carrying, and at which version. There is no table of them: each tool sets its own banner global as it loads, so the session IS the table and `atoms-family` reads it - which means a single file APPLOADed over the top of the build shows its own newer number, the mix a support call is usually trying to untangle |
| `CALHELP` | what a command IS. Type any part of a name **or of its caption** and it prints the matches with their captions, the same search the panel's Find page runs; Enter lists every tool. A name in brackets is not loaded in this session. Find itself carries two more buttons over the highlighted hit: **How it works**, the fuller step-by-step explanation (`lzp:*howto*`, copied from `ui/calofin_net/howto.txt` the same way the blurb is), and **Run tutorial**, which launches the command's interactive `TUTORIAL*` walkthrough where one exists (`lzp:*tutorials*` - most commands have none) - the VB palette's Find tab carries the same two buttons over its own selection |
| `CALSET` | the settings calofin keeps in your AutoCAD profile - the theme above, `CalofinErrorDir` (where `LAZDIAG` writes its report) and `StockCover_Folder` - what each does, and one prompt to change it. Each key is the one the tool that reads it actually reads: `tests/test_lazpanel.py` checks them against `LAZDIAG.lsp` and `STOCKCOVER.lsp`, because a settings command that writes a key nothing reads is worse than none. A `Hidden` option routes to `LAZHIDE`, the checklist of tools put out of sight - not a profile key itself, a name list in the registry beside the pins |
| `LAZSET` | the same settings as a DIALOG, which is what the panel's `Options` button opens: the theme on a dropdown, a family dropdown of recommended presets plus a hex box for each of the eight `CalofinInk-<ROLE>` item colours `cal:ink` resolves, the two folders, and `Hidden...` into the checklist. A hex code snaps to the nearest preset's ACI number, the same mapping `CALSET`'s own Itemcolors prompt now uses. Nothing reaches the profile until `OK`, and `OK` stays greyed while a hex box holds something that is not a hex colour, so a value nothing can read is never stored and then silently ignored. `CALSET` stays the typed way in, and the one a support call reaches for - it PRINTS every setting before it asks anything |
| `LAZNAME` | **names of your own.** Pick a tool and give it the name YOU type to run it and the words YOU want its button to say. An alias is a real wrapper `defun` - the shape `DCE` already is - built at run time and re-applied in every drawing, so it works exactly as a typed command does and the panel greys it correctly. A name the session already answers to is REFUSED rather than allowed to shadow it: `(defun c:CHECK ...)` would retarget the real `CHECK` for the whole session and `DIMARCCHECK` with it. A renamed caption reaches the grid, `Find` and `CALHELP` through the one accessor they all ask, while `lzp:*captions*` stays the file's single truth - so it is a Lisp-side rename, and the VB palette keeps the shipped words until it learns to read the same key. Removing a name stops it being remembered, but the name it already defined answers until the drawing closes: AutoLISP cannot take a `defun` back, and the dialog says so |

### The load is one line now

A Startup Suite entry runs in every drawing you open, and every tool
announcing itself was **83 lines and 6,681 characters** of scrollback
before the drafter had done anything. `LAZPASS.lsp` and
`CALOFIN-LOADER.lsp` set `*calofin-quiet*` while they load their
members, so the whole build says one line:

```
LAZPASS: calofin v3.12 loaded - 185 commands in one session.
```

APPLOAD a tool on its own and the flag is nil, so it greets you as it
always did - that is the one time being told is useful. `CALVER` reads
the whole roster back whenever it is asked. `tools/check_lisp.py`
holds the rule, so a new tool cannot reintroduce the wall.

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
| Calofin palette (VB.NET) | `ui/calofin_net/` | Dockable AutoCAD palette: Find over names and captions, Recent and Pinned rows sharing `LAZPANEL`'s own registry key, the panel's whole tab strip as real tabs, and the `LAZFORM`, `LAZSPA`, `LAZSTEP` and `LAZSIDE` sheets **drawn from their own vectors** - a box on every dimension line, a state line that holds Draw back, and Recall-last sharing the DCL forms' store. Only the pool-bottom tab is still a photograph. Its catalog is no longer typed - `Generated/CommandCatalog.g.vb` is written from `LAZPANEL`'s own tables by `tools/gen_ui_data.py`, so the two surfaces cannot part again the way they had (the palette shipped 60 of 67). The tooltips are the palette's own words and stay hand-written, in `blurbs.txt` |
| Calofin ribbon (C#) | `ui/calofin_ribbon/` | A native ribbon tab, one panel per LAZPANEL category (Layout/Points/Dimensions/Converters/Checking) with its own generated icon. **A routine's variants ride on its dropdown** - POOLCOVER and POOLDEMO under POOL, the four RECONVs under their CONVs, each scan under its check - which fits 94 commands onto 67 buttons with none of them out of reach; which is a variant of which is derived from the roster by `gen_ui_data.variant_of`, guarded by the roster AND by the category, never typed. A second surface, not a replacement - different assembly, different command (`CALOFINRIBBON`), no reference to the VB palette. Its catalog is the same generator's second output, `Generated/CommandCatalog.g.cs`, carrying each button's PICTURE and SIZE as well: **36 FEATURED routines have a glyph of their own and the other 31 are plain text buttons**, because a picture for all 67 is 67 pictures nobody can tell apart. Size is the second, separate decision - 22 wear the glyph at 32 on a full-height button, and Checking's 14 wear it at 16 beside the name, which took that panel from 1120px to 554px without giving up the shapes. Panels are three rows tall, large buttons leading and the rest in columns of three, and the face says the COMMAND - LAZPANEL's captions are sentences and a ribbon button is a word wide, so the caption is the tooltip's title. The tab puts itself back after a workspace switch, which takes an API-added tab away without anything looking broken. The icons are drawn by `tools/gen_ribbon_icons.py`, pure stdlib |
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
`LAZPANEL` is pure AutoLISP, ships inside `LAZPASS.lsp`, covers the 96
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
| `gen_ui_data.py` | Writes the palette's `Generated/CommandCatalog.g.vb` **and** the ribbon's `Generated/CommandCatalog.g.cs` from `lzp:*captions*` / `lzp:*groups*` / `lzp:*tutorials*` plus `ui/calofin_net/blurbs.txt` and `ui/calofin_net/howto.txt` - one generator, two languages, the same source tables. The C# half also folds each routine's VARIANTS onto that routine's dropdown (`variant_of`: affix rules over the roster, every one guarded by the base being a real command in the SAME category, plus a short editorial table for the handful no affix describes). `--check` fails when either file on disk is not what a fresh run would write, the same contract `releases/` is held to |
| `gen_ribbon_icons.py` | Writes all 82 of the ribbon's icons in `ui/calofin_ribbon/icons/` with nothing but `zlib` and `struct` - no imaging library for blocky glyphs on a 32-unit grid. Two kinds: one per LAZPANEL category for the panel header, one per `gen_ui_data.FEATURED` routine, in that routine's category colours. **Two sizes**, because the ribbon has two slots - 32 for the `LargeImage` on a large button's face, 16 for the `Image` a small button wears beside its name and a collapsed panel's drop-down shows - and each is RENDERED from the design grid rather than resampled, since hard-edged pixel art is the worst thing there is to downscale; six subjects too detailed for 13 pixels say it again in fewer strokes at 16. A corner badge says what KIND of tool it is (a tick for a review pass, chasing arrows for a converter) and the four converters wear their own initials in a 3x5 font, read off the command name. `--check` fails on a missing, stale or ORPHANED file - a routine dropped from `FEATURED` otherwise leaves its picture to be bundled for ever - and `check_standards.py` runs it alongside the mirror, the releases, the bundle and the two catalogs: the only entry in that list that is not text, and there for the same reason as the rest: `zlib` over a fixed input is deterministic, so "is this current" is a byte comparison either way |
| `gen_ui_charts.py` | Writes the palette's `Generated/ChartCatalog.g.vb` - the vector charts `LAZFORM`, `LAZSPA`, `LAZSTEP` and `LAZSIDE` draw, plus the tables that are not geometry: LAZFORM's cross dims, mode dropdowns, corner rows, bottom types and in-square keywords, and LAZSPA's corner rows, second-outline keys, dropdowns and treatments - out of `lzf:*charts*`, `lzs:*charts*`, `lzt:chart`, `lzv:chart` and the four `lzs:*` tables, read through `tests/lispvm.py`. Arcs are flattened by the Lisp's own helper, so the palette draws the same oval the panel does with no arc arithmetic of its own |
| `check_vb.py` | Static check over the VB palette, for a tree with no VB compiler: blocks opened and closed by the right closer, quotes and parens balanced per logical line, and every member and constructor arity of the assembly's OWN types resolved - which is what holds the hand-written palette to the generated catalog |
| `check_netapi.py` | The two .NET surfaces against **AutoCAD's own assemblies**, which `check_vb.py` cannot see: it reads the PE header, the CLI header and the ECMA-335 `#~` tables far enough to answer "does type T define, or inherit, a member called M". Pure stdlib. **Opt-in** - point `--refs` at an AutoCAD install directory or an unpacked `AutoCAD.NET` lib folder; with none given it prints what it would check and exits 0, which is why `make check` does not run it (a check that cannot run here must not fail the build, and one that silently passes is worse than none). It earned its place immediately: the ribbon was hanging the category icon on `RibbonPanelSource.Image`, a property that type does not have, and NEITHER project referenced `AutoCAD.NET.Model` - the package carrying `AcDbMgd.dll`, and with it `IExtensionApplication` and all of `DatabaseServices`. `make check` was green and 121 tests passed throughout |
| `check_dcl.py` | Every generated dialog still fits the screen. DCL does not scroll: one wider or taller than the display does not clip, AutoCAD refuses to open it. Each generator is driven to its tallest reachable state - pins and recents full, every chart, every step count - and measured by `dclsize.py`, whose constants are fitted to the one real AutoCAD report there is; `--list` prints every dialog, tallest first |
| `check_registry.py` | Every place a tool has to be registered - panel caption and placement, loader slot, README counts, the palette catalog and its probe list - with every count computed rather than typed; `--fix` repairs what is not editorial |
| `check_lazdiag.py` | Every command reports its failures. Five call sites: `lzd:begin` at the top, `lzd:report` in the `*error*` handler, `lzd:end` before the command's `(princ)` for the run log, `lzd:watch` after a selection so the report carries the geometry the run was *handed* and not only what it drew, and `lzd:ask` at **every** input site - after a `(setq v (getX ...))` that is a body statement, and wrapped as `((lambda (v) (if lzd:ask (lzd:ask "prompt" v) v)) (getX ...))` where the answer is read in place - so the transcript holds every answer, typed, and can be replayed. `--fix` wires all five. It also names a command that can reach **no** handler at all - computed from what the body does, so a `*VER` reporter is exempt until the day it grows a prompt - but it will not write the handler, because what one has to put back is the editorial part. Both handler spellings are read, `(defun *error* ...)` and the `(setq *error* (lambda ...))` that `abhd`, `CABHD` and `lhd` use. And every file carries a **self-test table** - `X:selftests`, a `(list ...)` of `(label expr expected)` / `(label expr)` entries of the tool's own helpers on known inputs, registered in `*calofin-selftests*` under every command the file begins or reports as - which a failure report runs on the drafter's machine. `--fix` writes the skeleton and the registration; the entries are editorial and the check names the file until at least three are written, and refuses an entry that names a prompt, a draw, a command, `setvar`, a file write, `load` or a `vla-`/`vlax-` call, since a table runs from inside `*error*` |
| `check_osnap.py` | The drafter's object snaps survive every run, including the ones that fail. A command that mutes running osnap so its own `(command ...)` picks land where it computed them has borrowed `OSMODE`, and owes it back on the clean exit, the cancelled one and the one that throws - so the check is per command, across the whole tier (POOLDEMO's restore is POOL's `pool:sysrestore`), and it wants the restore in the `*error*` handler as well as on the way out: Esc is the likeliest way out of a prompting command and the one path the success-path restore never runs. Both spellings count, the direct `(setvar "OSMODE" oos)` from a local of the command and the table-driven `(tool:sysrestore)` over a snapshot whose list names `OSMODE`. Two ordering rules on top of that, because a restore that is present is not a restore that runs: an error inside `*error*` aborts the handler, so nothing that can throw - a bare `(command ...)`, a drain loop, an unwrapped `-DIMSTYLE` - may sit in front of the OSMODE line; and a restore helper may not drop its snapshot behind such a form, since `syssave` refuses to re-save over a snapshot that is still standing and every later run then restores the stale value. A fourth rule catches the one a drafter meets with nothing going wrong: a command that snapshots `OSMODE` must actually move it, or it writes its opening value back over a snap ticked on mid-run. `--list` prints every command that moves it and how it puts it back |
| `package.py` | The one artefact here a drafter can install: an Autodesk **ApplicationPlugins bundle**, zipped. Two lanes, and only one needs a compiler - the AutoLISP half is `LAZPASS.lsp` plus the glue and is finished the moment it is copied, and the two .NET surfaces (palette and ribbon) ship as SOURCES with a Windows `build-net.cmd` that builds both DLLs into the slots the manifest already points at. The manifest names them either way, on purpose: writing a different one depending on whether a DLL happened to be lying around would mean the thing you tested is not the thing you shipped. The two load differently and that is the one asymmetry - the palette is `LoadOnCommandInvocation` (nothing opens until `CALOFIN` is typed), the ribbon is `LoadOnAutoCADStartup`, because a tab you have to summon by name is a palette with extra steps. `--check` reports what would travel and writes nothing |
| `probe_report.py` | Not a check: a diagnosis. Replays a LAZDIAG failure report in the test VM - the tool at the report's version (its `releases/` twin when there is one), the geometry the report copied, the answers it recorded - and confirms the failure comes back. Then it changes one answer at a time - 1, 0, half, double, a step either side, ten times, a thousand; a point moved - and says which answer the failure is tied to, which it is not, and where a range the tool never checks begins. When the control run does not reproduce (a whole-drawing sweep the report could not carry, a file dialog) it says so rather than probing. The report's own self-test lines come first, because a FAIL among them - the tool's helper answering differently on the drafter's machine - is the one thing a replay here cannot see; and the replay runs under the report's MACHINE - its units family, angle frame and PICKFIRST put on the VM, every LAZTUNE override the report lists set on the tool's globals after it loads - so a failure a knob or a unit setting caused reproduces here too. Writes `REPORT.probe.txt` beside the report, and `.probe.json` with `--json` |
| `run_selftests.py` | Not a check: runs a tool's self-test table in the VM exactly as a failure report would - `python3 tools/run_selftests.py lisp/pool/POOL.LSP --tier both` - one line per entry and the verdict, and exits 1 on a FAIL, a prompt, a draw, a command, a file written or a sysvar moved. No file runs every tool. The one-file loop while a table is being written; `tests/test_selftests.py` is the same over the whole tree |

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
python3 tests/test_lazdiag_sweep.py   # every headline command failed
                                      #   for REAL, not statically: 63
                                      #   of them driven to their first
                                      #   prompt and handed an error
                                      #   instead of an answer, each one
                                      #   checked for a report that
                                      #   parses and carries its message
python3 tests/test_lazdiag_selftests.py # the self-test section of a report,
                                      # the log's count, the LAZDIAG sweep
python3 tests/test_lazdiag_machine.py # THE MACHINE and its hazard flags, the
                                      # layers touched, the LAZTUNE overrides,
                                      # the loaded roster, LOST runs, LAZLAST
python3 tests/test_selftests.py       # every tool's self-test table passes
                                      # at this tier, nothing prompted/drawn
python3 tests/test_lazdiag_probe.py   # a report replayed in the VM and
                                      #   its inputs varied: the control
                                      #   reproduces, a value-tied failure
                                      #   is named, a boundary found, a
                                      #   selection handed back at its step
python3 tests/test_pool_lisp.py       # POOL geometry
python3 tests/test_pool_runtime.py    # POOL loaded and run in lispvm
python3 tests/test_pool_steps.py      # POOL's steps: the hand-over to the step
                                      #   routines, the moved E dim, the step outside
python3 tests/test_tutorialpool.py    # TUTORIALPOOL, run in lispvm
python3 tests/test_poolside.py         # POOLSIDE, run in lispvm
python3 tests/test_lingutter.py       # LINGUTTER - the exterior walk, the
                                      #   snap ladder and the hull, the keep
                                      #   rules, and the gut scoped to the
                                      #   highlight
python3 tests/test_upadover.py        # UPADOVER - the cover from one
                                      #   point to another: no overlap,
                                      #   no gap, nothing of the run
                                      #   left bare, on a straight
                                      #   wall, round a corner, at 45
                                      #   degrees and along an arc
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
python3 tests/test_olauto.py          # OLAUTO - two equal circles overlay
                                      #   with no error left, a 60 over a
                                      #   50 reads 10 all round (the fit
                                      #   never scales), eight start poses
                                      #   give one answer, and the worst
                                      #   spots are dimensioned apart
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
python3 tests/test_perpmark.py        # PERPMARK, the survey-point
                                      #   sibling of the two above
python3 tests/test_cdcreate.py        # CDCREATE loaded and run in lispvm
python3 tests/test_custblock.py       # CUSTBLOCK loaded and run in lispvm
python3 tests/test_smartfillet.py     # SMARTFILLET loaded and run in lispvm
python3 tests/test_honefillet.py      # HONEFILLET, its half-inch spinoff
python3 tests/test_bpcallout.py       # BPCALLOUT loaded and run in lispvm
python3 tests/test_cdcallout.py       # CDCALLOUT loaded and run in lispvm
python3 tests/test_dronote.py         # DRONOTE loaded and run in lispvm
python3 tests/test_abfind.py          # ABFIND / ABMOVE, run in lispvm
python3 tests/test_abcdef.py          # ABCDEF, run in lispvm against a known survey
python3 tests/test_altabcdef.py       # ALTABCDEF, the same under the
                                      #   clockwise corner order
python3 tests/test_xyplot.py          # XYPLOT, run in lispvm
python3 tests/test_constellation.py   # CONSTELLATION - a known shape
                                      # back from its distances, a
                                      # partial chart, what is refused,
                                      # arcs, and the fix-and-redraw loop
python3 tests/test_autodim.py         # AUTODIM styles, dedupe, overall/step/floor dims, the pad branch
python3 tests/test_lisplab.py         # LISPLAB - the sorts against Python's
                                      # own sorted(), then the whole tour
python3 tests/test_lincheck.py        # LINCHECK, run in lispvm
python3 tests/test_ccprecheck.py      # CCPRECHECK branch walks and Back
python3 tests/test_stockcover.py      # STOCKCOVER, run in lispvm
python3 tests/test_covercheck_pads.py # COVERCHECK's pad hunt vs PADDLE's,
                                      # both real .lsp files in one lispvm
python3 tests/test_spacovcreate.py    # SPACOVCREATE: the offset that keeps its
                                      # arcs, the tables it copies from SPA, and
                                      # the whole command in lispvm
python3 tests/test_spacheck.py        # SPACHECK over a drawing the real SPA
                                      # just made, in the same lispvm
python3 tests/test_dimcheck.py        # DIMSCAN read-only, then the guided
                                      # review: Move/Keep/Back/No, merge,
                                      # DIMCHECKRESCUE
python3 tests/test_cleardim.py        # CLEARDIM - the box, the clash test,
                                      # the track, and the policy: one text
                                      # on a line and one clear, overlapping
                                      # each other, and only the first moves
python3 tests/test_linfincheck.py     # the liner rules over a real staircase
                                      # side view, LITELINFINSCAN, the
                                      # guided review incl. Skip
python3 tests/test_covercheck.py      # the cover rules over an L-pool, the
                                      # pad suggestion, LITECOVERSCAN, and a
                                      # perimeter that hands over to CABLE
python3 tests/test_lazform.py         # LAZFORM - the chart drawn and checked,
                                      # and the pool it draws vs the prompts
python3 tests/test_lazpanel.py        # LAZPANEL - roster pinned to lisp/,
                                      # DCL well-formed, run with stubs,
                                      # toolbar + generated icon bytes
python3 tests/test_dcl_size.py        # every generated dialog FITS: the
                                      # model reproduces the size AutoCAD
                                      # refused, the pages that overflowed
                                      # wrap and keep their captions, and
                                      # Pinned/Recent are capped
python3 tests/test_cornerstp_geometry.py
python3 tests/test_cornerstp_bench.py   # CORNERSTP's bench, run in lispvm
python3 tests/test_cornerstp_profile.py # the side profile all three draw
python3 tests/test_normiestep_corner.py # NORMIESTEP corner mode, run in lispvm
python3 tests/test_step_corner_mark.py  # the step corners' own MARK: the
                                      # circled 90 and the boxed "?" with
                                      # its Not Given note, in the smaller
                                      # of the sample sheet's two sizes,
                                      # and drawn only where 90 is true
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
                                      # including the step count and the
                                      # whole bead chain
python3 tests/test_lazspa.py          # LAZSPA - the spa chart drawn and
                                      # checked, and the spa it draws
python3 tests/test_lazstep.py         # LAZSTEP - the drawing generated for
                                      # every step count, and the steps it draws
python3 tests/test_lazside.py         # LAZSIDE - the section generated for
                                      # every bottom type, its three tables
                                      # held against POOLSIDE's own, and the
                                      # side view it draws
python3 tests/test_dialog_actions.py  # every action_tile expression on every
                                      # DCL page, EVALUATED - a callback is a
                                      # string, so a typo'd or moved helper is
                                      # dead until somebody clicks that tile
python3 tests/test_ui_data.py         # the palette's generated catalog read
                                      # back and held to LAZPANEL's roster -
                                      # captions, categories, the whole tab
                                      # strip, and the blurbs it must not invent
python3 tests/test_ribbon_catalog.py  # the ribbon's generated C# catalog, the
                                      # same generator's second output, held to
                                      # the same panel and blurbs - and every
                                      # command reachable exactly once, on a
                                      # button face or in a dropdown, every glyph
                                      # and size FEATURED's own, and no large
                                      # button asking for a picture nobody drew
python3 tests/test_ribbon_icons.py    # the ribbon's 82 icons: the set the ribbon
                                      # asks for and no orphans, FEATURED and the
                                      # glyph table naming the same routines,
                                      # well-formed PNGs at the size they claim,
                                      # current - and NO TWO THE SAME PICTURE,
                                      # which is the whole argument for drawing 36
python3 tests/test_check_vb.py        # the VB linter itself, driven against VB
                                      # that is wrong on purpose: a checker
                                      # that has stopped checking is worse
                                      # than none
python3 tests/test_palette_shell.py   # the palette's Find/Recent/Pinned against
                                      # LAZPANEL's: one registry key, one cap,
                                      # and every Find message lifted out of the
                                      # Lisp rather than typed
python3 tests/test_ui_charts.py       # the palette's generated chart geometry
                                      # read back and held to lzf:/lzs:/lzt:/
                                      # lzv:'s own tables - every dimension,
                                      # every outline point, arcs included
python3 tests/test_side_form.py       # the palette's side-view tab: the bottom
                                      # type travels as the ANSWER it is, an NA
                                      # in a depth is withheld and an NA in a
                                      # run is not, and no table is spelled in
                                      # the VB
python3 tests/test_package.py         # the installable bundle: every module the
                                      # manifest names travelled, the one that
                                      # did not is the DLL and cannot be reached
                                      # before it is built, and the zip is what
                                      # was assembled
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
python3 tests/test_osnap_restore.py    # the three check tutorials, killed PAST
                                      # the point that muted OSMODE: the
                                      # handler runs and the drafter's object
                                      # snaps read as they did before.  The
                                      # deeper half of the cancel sweep above,
                                      # where a restore at the bottom of the
                                      # command never runs
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
