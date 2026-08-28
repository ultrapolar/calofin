# calofin v3.0

Blender add-ons, AutoLISP routines, and a AutoCAD palette UI for pool/spa
drafting. This branch consolidates what used to be ~29 separate branches,
each with its own single addition on top of a shared base, into one tree
where every tool lives side by side and can be worked on from a single
checkout.

```
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
Load a routine with APPLOAD, or add it to your startup suite.
Prompt wording, keyword sets and file structure follow the shared
standard in [STANDARDS.md](STANDARDS.md) - read it before adding or
changing a routine.

| Command(s) | Folder | What it does |
| --- | --- | --- |
| `POOL`, `POOLCOVER`, `POOLDEMO`, `POOLVER`, `TUTORIALPOOL` | `lisp/pool/` | As-built pool plan generator - Rectangle, Oval, Grecian, L, Lazy L - from field measurements. `POOLCOVER` is the same command for a cover sheet: the pool-bottom question is answered No before it is asked, so the depth chain behind it (C, C2, D, the hopper type and its corner method) never runs |
| `POOLSIDE`, `POOLSIDEVER` | `lisp/poolside/` | POOL's side view (the longitudinal section) on its own: the bottom type, the overall length B, the floor run chain (`H G F E`, or `E2 F2 G F1 E1` for a Sport) and the depths C / D / C2 - no plan, no perimeter, no cross dims. A gray nominal section is on screen while the letters are asked, with the tie being asked for lit red. Any run may be `NA` and is read back off B; a run that resolves negative is floored, its dimension drawn red and a note written under the section |
| `SPA`, `SPAVER`, `TUTORIALSPA` | `lisp/spa/` | Spa/hot-tub template - Rectangle, Octagon, Round |
| `OASIS`, `OASISVER` | `lisp/oasis/` | Continuous-tangent pool - centre bulge, top-right bulge, cloud (straight or rounded bottom), kidney (true or asymmetric) or NXT cloud (three lobes, four fillets) - drawn live as its X/Y envelope and radii are answered, with a centre-to-corner check drawing beside it.  A `Complex` run takes a straight tangent run in place of any joiner and moves the centre hump off centre.  Finishes by offering the pool bottom - shallow and deep breaks, hopper and slope lines, ABHD's flow with the break located by a change of tangency, a nearest point or an offset in from a bound.  Takes a form's answers (`oasis:*form*`), so `LAZFORM`'s oasis sheets drive it |
| `ABHD`, `ABHDCOVER`, `ADAB`, `TUTORIALABHD`, `TUTORIALADAB` | `lisp/abhd/` | Fits a pool perimeter and bottom through surveyed points. `ABHDCOVER` answers the "add the bottom" question No before it is asked, for a cover sheet that stops at the perimeter |
| `ABCURCHECK`, `ABCURCHECKSCAN`, `ABCURCHECKRESCUE`, `ABCURCHECKVER` | `lisp/abcurcheck/` | ABHD's reader turned round: grades how CONTINUOUS a perimeter already drawn is, as one word - `Smooth` / `Fair` / `Rough` / `Broken` - set by the single worst thing found and naming it, with a 0-100 index underneath for comparing two candidates.  Measures gaps, zero-length and doubled segments and crossings (G0); the kink angle at every joint, banded on ABHD's own 8 and 45 degrees, so the 8-45 band a fabricator finds in the bead is the headline; and the noise a traced outline leaves behind - micro-segments, inflections, and the turning excess over the 360 degrees any simple closed loop turns.  Breaks that are MEANT to be there are picked and stamped onto the drawing, so they leave the grade and the next run remembers them; what is left is the undeclared list, ringed on `POOL-CONT`.  Draws the curvature comb on `POOL-COMB` - a tooth per sample, sided by which way the curve turns - where every break is a step in the envelope |
| `CABHD`, `CABHDVER` | `lisp/cabhd/` | ABHD's perimeter half, for a survey that runs past the pool: asks the LAST point number belonging to the pool edge and leaves everything past it out entirely.  No pool bottom |
| `LHD` | `lisp/lhd/` | Fits a top-down 2D outline (closed or open) through laser-scanned points |
| `FITABHD`, `FITABHDCOVER`, `FITABHDVER` | `lisp/fitabhd/` | Fits a TYPED pool template (Rectangle, Grecian, Roman, Oval, L, Lazy L, Round, or an OASIS pool) through surveyed points -- the type says how to READ the survey, the points decide the shape: out-of-square walls, side walls that lean apart on a Roman or Oval, corner sizes, bows, and any curve drawn as one R -- an end, a corner, a bow -- rebuilt as a smooth run of up to a third as many arcs as it has points (ABHD's tangency window) are all measured from the survey and kept only where it proves them, Redo to refit -- then a standard-hopper bottom.  An `OAsis` is fitted with OASIS's own ring solver against OASIS's own five families, and everything OASIS has to ask about a shape is measured instead: the frame is swept right round the pool (an oasis has no walls to vote on it), the envelope falls out of the bounding box, and every joiner is carried as a curvature so a cloud's flat bottom is the one whose radius came out infinite -- found, not declared, as is which way a kidney was given. `FITABHDCOVER` skips that bottom question for a cover sheet |
| `BPCALLOUT` | `lisp/bpcallout/` | Rings clicked bad points with 5" circles on `FGStep` and writes a "Pt.12, Pt.15 and Pt.20 are bad" callout |
| `CDCALLOUT` | `lisp/cdcallout/` | Cross-dimensions from Pt.## to Pt.## by typed number - `CROSS DIMENSIONS` style, `DIMENSION` layer, repeat until Enter |
| `ABFIND`, `ABMOVE`, `ABFINDVER` | `lisp/abfind/` | Ties a point (typed by number or clicked) back to the **A** and **B** survey stakes with a cross dim to each, then asks whether that point wants moving. `ABMOVE` takes one point and also offers every place it lands if one tape was read wrong - the moved tape swept a foot at a time, ten feet each way, plus the look-alike readings (`21'-1"` written as `21'-7"`, the 1"/11" slip, transposed feet) - drawn yellow, tagged by the tape they move (`1A`, `-3B`), each group on the dashed grey arc it sits on - and copies it to `Pt.##m` - the same block, layer, colour, scale and attributes, one number different - rings the old spot with a 5" circle on `FGStep` and writes the `Moved Pt.17 B from 18'-6" to 18'-5"` note |
| `ABCDEF`, `ABCDEFVER` | `lisp/abcdef/` | Locates Excel-measured points inside rectangle corners A/B/C/D, "Z" reading order (A/B top, C/D bottom).  Two tapes place a point, three fix it, four cross-check it; a fourth tape is dropped only when leaving it out settles the other three **and** the runner-up triple is clearly worse, so a point near a diagonal keeps all four rather than discarding a good tape.  Reports per point how many tapes placed it, which, and a measured 1-99% confidence, to the command line and to a text file beside the sheet.  Plots as `ab_pt` blocks on `POINTS` and offers `ABHD` the set |
| `ALTABCDEF` | `lisp/altabcdef/` | Same idea, clockwise A→B→C→D corner order instead - kept separate from `ABCDEF` because the two conventions aren't interchangeable |
| `XYPLOT`, `XYPLOTVER` | `lisp/xyplot/` | `ABCDEF`'s sister for a survey that arrives already reduced: a sheet of X/Y offsets, one picked origin, drawn twice - graph 1 the points as given (`ab_pt` on `POINTS`, ready for `ABHD`), graph 2 the same points with the X and Y offsets dimensioned as two continuous linear chains |
| `ABPCHECK`, `ABPCHECKRESCUE`, `ABPCHECKVER` | `lisp/abpcheck/` | `ABHD`'s measuring half, forked as a checker: highlight the whole drawing, say how far off the line is too far, and every survey point is reported with the distance to the nearest line -- `Pt. 17   closest line is 0'-1 7/8" away` -- worst first, the ones over the limit in red and ringed in the drawing. Measures to the run itself, arcs included, not to its endpoints. `ABPCHECKRESCUE` takes the report and the rings away again |
| `CHECK`, `DIMARCCHECK` | `lisp/check/` | Audits dimension def-points and arc endpoints against real geometry, fixing strays |
| `DIMCHECK`, `DIMSCAN`, `DIMCHECKVER`, ... | `lisp/dimcheck/` | Guided, one-at-a-time review of dimension placement, arc-end attachment and overlapping lines, grouped by dimension style |
| `LINFINCHECK`, `LINFINSCAN`, `LITELINFINSCAN`, ... | `lisp/linfincheck/` | `DIMCHECK`'s checks plus steps & side views, wall height, the liner pattern and the title block border - the full liner-finish drawing QA. The report leads with the liner checks; the `DIMCHECK`-style findings sit in a DIMENSION AUDIT column beside it, and `LITELINFINSCAN` skips them entirely for a drawing `DIMCHECK` already went over |
| `COVERCHECK`, `COVERSCAN`, `LITECOVERSCAN`, ... | `lisp/covercheck/` | Same guided review, rules swapped for pool-cover QA; same split report, with `LITECOVERSCAN` as the cover-rules-only scan |
| `SPACHECK`, `SPACHECKSCAN`, `LITESPACHECKSCAN`, `SPACHECKRESCUE`, `SPACHECKVER`, `TUTORIALSPACHECK` | `lisp/spacheck/` | The same guided review for spa sheets: audits a drawing against what `SPA` draws - bounded outlines, the dimension roster and its notes, hinges against the block's grade/taper and the Hinge Arrangement Chart, and a title block at exactly 0.6x the liner block |
| `CCPRECHECK` | `lisp/ccprecheck/` | Walks the "Tech Flow Chart" product-type decision tree and prints a summary. Renamed from `CHECK` to resolve a name collision with `lisp/check/` |
| `LINCHECK` | `lisp/lincheck/` | Companion checklist routine, shipped alongside the flowchart walker |
| `STOCKCOVER`, `STOCKLIST`, `STOCKCOVER-CFG` | `lisp/stockcover/` | Replaces a highlighted perimeter with a stock cover drawing pulled straight out of the stock DWG folder, lined up on what was highlighted |
| `MATCHSTD`, `MATCHSTD-CFG` | `lisp/standards_checker/` | General-purpose drawing-standards matcher/checker (modular: config, cache, geometry, tolerance, UI) |
| `LINTXTCHK` | `lisp/lintxtchk/` | Places the vinyl-liner QA checklist into the drawing as text |
| `CORNERSTP`, `HEMISTEP`, `NORMIESTEP`, ... | `lisp/cornerstp/` | Corner-step layout routines for pool corners - three files here, one `STEPS` release (see below) |
| `PADDLE`, `TUTORIALPADDLE` | `lisp/paddle/` | Finds concave perimeter features and inserts pad blocks |
| `LINGUTTER`, `LINGUTTERSCAN`, `LINGUTTERVER` | `lisp/lingutter/` | Guts a highlighted area back to the pool and nothing else. Inside the highlight -- and only inside it -- it walks the **outer face** of the lines, arcs and polylines and draws its own perimeter over it: ends closer than a snap tolerance count as one point, and the walk always takes the hardest available right turn, so interior geometry (hopper, steps, a tie line) is never stepped onto and an outward spur is pruned. Three snap tolerances are tried in turn and the result is measured against what was highlighted before it is believed, so an outline with a gap in it can no longer be quietly replaced by a hopper that did close; when no exterior can be walked at all it wraps the highlight in its convex hull and says so. The perimeter is redrawn as one closed polyline on `POOL` (ByLayer, arcs kept as bulges); everything else highlighted is erased, except dimensions in `CROSS DIM*` wherever they sit and `STANDARD` / `SIDE STANDARD` ones whose every attachment point lands on that perimeter. The new perimeter then goes to `PADDLE` as a pickfirst selection, so it pads that loop rather than auto-detecting past it. It reports what it found and what it would drop -- by style, so nothing goes silently -- and asks before erasing, defaulting to `No`; `LINGUTTERSCAN` prints the same report and changes nothing |
| `PERPPTS`, `CPERPPTS`, ... | `lisp/perp_points/` | Perpendicular offset points along a line or curve, joined with straight segments, arcs or a mix of both; asks whether the overall width has been re-measured, and has a repeat-on-the-new-polyline step |
| `AUTOBEAD`, `AUTOBEADVER`, `TUTORIALAUTOBEAD` | `lisp/autobead/` | Offsets ("beads") selected pool lines toward a clicked side |
| `DCE`, `DIMCONTEND` | `lisp/dim_continue/` | Chains `DIMCONTINUE` from a seed dimension out to every remaining feature point |
| `AUTODIM`, `FLOORDIM`, `STAIRDIM`, `AUTODIMSIDEPOV` | `lisp/autodim/` | Auto-dimensions a highlighted plan - perimeter sides and arc radii, stairs, the floor dims it asks about, two overall dims. A size that repeats is called out once and noted `Typ.` (from two equal sides, or four equal radii). Perimeter and stairs `SIDE STANDARD`, floor and overall dims `STANDARD`, anything under 12" `STANDARD INCHES`; a place that is dimensioned already is left alone. Highlight a flight of steps drawn in side view instead and `AUTODIM` recognises it and dimensions the depth of every step down the right in `STANDARD INCHES` |
| `SMARTFILLET`, `SMARTFILLETVER` | `lisp/smartfillet/` | Fillet a corner after showing what each radius would look like: pick the two lines and every radius that fits - 6 up in 6s, tangent points landing on both legs - is drawn as a dashed, lettered arc. Click one and that corner is cut for real and given its radius dimension; it then offers the same radius for the rest of the corners, and the one callout becomes `R12 Typ.` as soon as a repeat is cut |
| `CDCREATE`, `CDCREATEVER` | `lisp/cdcreate/` | Turns every highlighted line into a cross dimension - `CROSS DIMENSIONS` style, `DIMENSION` layer, dim line on the line, text 80% toward the right/bottom end, source line erased. A tie that is dimensioned already is left alone |
| `CUSTBLOCK`, `CUSTBLOCKVER` | `lisp/custblock/` | Draws a custom block in pictorial view from three typed sizes - length (the long axis, receding back-right at 45 degrees and at true length), width across the front face, height up it - based at its front bottom left corner. Nine lines on `COVER`: the front, top and right-hand faces, with the three hidden edges left out so it reads as a solid rather than a wire cage. Dimensioned three times on `DIMENSION` in `STANDARD INCHES` - the length aligned along the top-left receding edge, the height and width linear with their axes forced |
| `DRONE` | `lisp/drone/` | Drawing cleanup: text style/height, pool/spa points onto `POINTS`, spa perimeter onto `POOL`, and more in one pass |
| `TYDRN` | `lisp/tydrn/` | `DRONE`'s pool-only sibling for a drone trace with no spa: the same text and point cleanup with no SPA-point sweep and the `SPA` layer never touched (see `lisp/tydrn/README.md` for the exact split) |
| `WCALST` | `lisp/wcalst/` | Unrolls a curved constant-width band flat, with darts/inserts |
| `XFTCONV`, `XFTCONV-SETUP` | `lisp/xftconv/` | Cleans up Leica XFT/DXF survey imports |
| `DDGPS`, `DDALT`, `DDELEV`, ... | `lisp/drone_height/` | Computes drone height above grade and lens distortion from photo GPS/EXIF |
| `LISPLAB`, `LISPLABVER` | `lisp/lisplab/` | Learn AutoLISP, not a drafting tool: two lessons - getting things out of the drawing databases (`entget`/`ssget`/the symbol tables/dictionaries/xdata), and putting a list in order (`vl-sort` and its duplicate trap, then bubble, selection, insertion, merge and quick sort written out). Each is an outline plus a worked example that draws a sample and sorts what it reads back |
| `LAZFORM`, `LAZFORMCOVER`, `LAZTXT`, `LAZASCII`, `LAZFORMVER` | `lisp/lazform/` | Fill a dimension chart in and draw the pool from it. Thirteen charts, and two routines behind them: eight POOL sheets - Rectangle, True Oval, Roman, both Grecians, True L Left, Round and Octagon - and five OASIS ones - Center, Top-Right, Cloud, Kidney and NXT Cloud - each the one off the paper: outline, hopper, dimension chain with its letters. The picture is one whole passive image and **every dimension has a labelled box in the column beside it**, with its letter as a button in front of it: the picture is read, the column is typed into, and the letter ties the two together. (v1.6 to v2.5 sliced the chart into bands and wedged the across-chains between them; it came apart into strips, the boxes were only ever placed to within a character cell, and a sheet read as two kinds of thing at once.) Corners get a dropdown each - `Square`, `Radius`, `Cut`, `NotGiven` - and the size box beside it un-greys only for `Radius` and `Cut`; Roman carries four rows, the Grecians and the Octagon carry two collective ones (body corners, end-tip corners) that fan out to the eight individual questions when the pool is out of square, and picking any of them arms POOL's own corner-record gate. Cross dims have a mode dropdown and their boxes, out-of-square only. Fill in what you know, leave the rest blank, press Insert: the page's own routine runs and asks only for the gaps. **One rule decides what is live**: the bottom type, the in-square toggle and the mode dropdowns together compute the dead set, `mode_tile` greys exactly it, and exactly it is withheld from POOL - so a greyed box cannot be a value that travels and is never read. The bottom half of that rule is read off POOL's own `pool:btmspec`, so it cannot drift: a Normal hopper draws no side view, so C, D and C2 grey out; a Sport asks a different plan chain, so H, F and E grey out and its own E2-F2-F1-E1 boxes come alive. The oasis sheets read the same way off their own two dropdowns - a cloud's bottom or a kidney's type, and simple-or-complex - and hand their answers to `OASIS` instead: an oasis has no chain and no hopper, so the sheet is the envelope, X across and Y up, with a radius against every arc; a bulge's radius is drawn where it runs and a joiner's gets a leader out to its letter. Those outlines are not artwork either - each is the ring `oasis:solve` builds for that shape's reference drawing, and the test suite re-derives every arc from OASIS and compares. `NA` in a box means not measured and is passed through as such; a blank box just means ask. Drawn with `vector_image` from a table of lines, so there is no artwork file to ship. `LAZFORMCOVER` is the same form for a cover sheet: POOL runs with its pool-bottom gate already closed - `LAZTXT` is the same form drawn out of TILES instead of vectors - the pool is a real boxed cluster with the hopper nested inside it and the fields in the drawing, which buys retention (nothing in it is an image tile, so nothing in it can be wiped by a repaint) at the cost of the outline being a rectangle whatever the pool is. `LAZASCII` is a probe, not a tool: it asks whether this AutoCAD's dialog font is fixed-pitch, which decides whether the chart could be drawn in characters instead of vectors - worth knowing because DCL never retains an image tile but always retains a text one - see `lisp/lazform/README.md` |
| `LAZSPA`, `LAZSPAVER` | `lisp/lazspa/` | `LAZFORM`'s argument applied to `SPA`: fill a chart in, press Insert, and the spa is drawn. Three charts - Rectangle, Octagon, Round - with the boxes wedged into the dimension rows, which is the layout LAZFORM carried at v1.6-v2.5 and has since moved off. The Rectangle carries its four corner dropdowns, labelled the way the sheet legend spells them (`90`, `Radius`, `Diagonal`); SPA itself now asks the canonical `Square`/`Radius`/`Cut`/`NotGiven` and normalises the legend words on the way in, so the chart keeps the drafter's vocabulary and the routine keeps the standard's. Every page also carries the water's-edge/cover-size mode, the second outline (by offset or by dimensions, keyed per shape), the lap gap, auto-hinge, and the grade and taper the Spa Cover Details block would otherwise be read for. Two traps are handled rather than inherited: SPA stores a form's `nil` without validating it, so `NA` on a question that must have an answer is demoted to an empty box instead of reaching arithmetic; and the Round flow only *peeks* at `A`, so filling it is what asks for an out-of-round spa - which is what the label says. The block pick and the base point stay in the drawing - see `lisp/lazspa/README.md` |
| `LAZSTEP`, `LAZSTEPVER` | `lisp/lazstep/` | **Say how many steps, then fill the drawing in.** Page one picks the step type (`CORNERSTP`, `HEMISTEP` or `NORMIESTEP`), takes the count, and asks that type's once-only questions - direction, bench, corner treatment, the width that is the same for every step. Page two is then *built for that count*: the plan with N treads and their widths, and the side profile with N risers and the N+1 drops, every dimension carrying its letter until you type a number over it. Change the count and the drawing is regenerated, keeping what still has a step to belong to. This is what the step routines could never be asked before - they had no count, only a tread prompt you stopped answering - so the stores take one now and the form supplies it. Eight steps is the ceiling, and past four the tread chain staggers onto two rows, because DCL will not scroll a dialog wider than the screen. The walls, the curve, the side to draw toward and the profile's pick all stay in the drawing - see `lisp/lazstep/README.md` |
| `LAZPANEL`, `LAZBUTTON`, `LAZPIN`, `LAZICON`, `LAZPANELVER` | `lisp/lazpanel/` | A clickable button panel with the 66 headline drafting commands above - the zero-install GUI: the dialog is plain DCL that the file writes for itself at run time, so there is no DLL to `NETLOAD` and no second file to ship. Loading it also puts a one-button toolbar ("LazPanel", an orange hexagon it generates itself) on screen that you can drag anywhere or dock - click it to open the panel, or `LAZBUTTON` to re-summon it. Tabs come in two rows: the **jobs** (Pool / Cover / Spa / Rest), each laid out in columns that follow the work - shape, points, steps, dims and check - and the **categories** (Layout / Points / Dimensions / Checking, the same four group names as the VB palette) holding the whole roster filed by what each tool is. A tool that serves two jobs sits on both, so 66 commands make 146 buttons; `Rest` is computed as whatever the three named jobs leave over. A command not loaded in this session is greyed out. A click closes the panel, runs the command exactly as if typed, and the panel then REOPENS itself on the same page at the same position - Close is the way out. A **Pinned** row on every page carries the few tools you run all day, remembered between sessions in the registry; `Pin...` or `LAZPIN` edits it. Off the panel on purpose: the satellites (`TUTORIAL*`, `*VER`, `*RESCUE`, `-CFG`/`-SETUP`, `DCE`, `STOCKLIST`), the `DD*` drone-height toolset, `LISPLAB` and the deprecated matcher - see `lisp/lazpanel/README.md` |

### Going back a step

Interactive tools share one convention for backing out of a mis-typed
answer: the keyword is **Back** (type `B`), it is always shown in the
prompt's bracketed options (`[Back]`, `[Yes/No/Back/Skip rest]`, ...),
and it re-asks the previous question - re-running whatever lookup or
computation sits in between, and backing out of a sub-block (a `POOL`
measurement block, a `CCPRECHECK` branch) into the question that
opened it. **Undo** (`U`) is accepted everywhere Back is, as an
unlisted synonym. Typed prompts - notes, offsets, feet-inch
dimensions - cannot take keywords, so there Back is typed like a
value: `B`, `BACK`, `U` or `UNDO` alone, any case (the prompt says
so). The first question of a command has nothing to go back to, so it
never offers Back.

In loops that draw as they go - `PERPPTS`/`CPERPPTS` offset points,
`CORNERSTP`/`HEMISTEP`/`NORMIESTEP` treads, `ABHD`/`ADAB` slope
waypoints, `CDCALLOUT` dimensions, `ABFIND` ties - Back
also removes the
just-committed point or step (its lines and its dimensions) before
re-asking. `BPCALLOUT` works by
reselection instead: clicking a ringed point again un-rings it.
Feedback wording is shared too: `Stepping back one
<point|step|dimension>.` on the way back, `Already at the first
<point|step|dimension>.` when there is nowhere left to go.

Every interactive multi-step tool supports this, with one boundary:
AutoCAD object selections cannot take keywords, so a command whose
only remaining input is a selection (`PADDLE`, `DIMCONTEND`) has no
prompt left that could offer Back - and Back cannot be *typed at* a
selection either, though several tools (`WCALST`, `XFTCONV`,
`AUTOBEAD`, `AUTODIM`) re-open their selection when you Back at the
prompt after it. New prompts should follow this convention - it is
part of the shared prompt standard in [STANDARDS.md](STANDARDS.md).

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
`shared/CALOFIN-LIB.lsp` holds the shared helpers under the `cal:`
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
| Calofin palette (VB.NET) | `ui/calofin_net/` | Dockable AutoCAD palette: one button per command, plus forms for POOL and SPA |
| Palette LISP glue | `ui/calofin_ui/` | `calofin.lsp` - reports which commands are actually loaded this session, so the palette can grey out the rest |

The palette needs its DLL `NETLOAD`ed on every machine. For a
button panel with nothing to install, see `lisp/lazpanel/` above:
`LAZPANEL` is pure AutoLISP, ships inside `LAZPASS.lsp`, covers the 66
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

## Tools (`tools/`)

| Script | What it does |
| --- | --- |
| `release_lisp.py` | Regenerates every REV twin in `releases/` from its `lisp/<tool>/` source's version banner, and the one-file `STEPS` bundle from its three sources |
| `build_shared_bundle.py` | Concatenates `shared/` into the single-file `shared/LAZPASS.lsp` |
| `mirror_shared.py` | Regenerates a `shared/parts/` twin from its `lisp/` original - drops the helpers the library provides and rewrites the call sites onto `cal:`. Table-driven, one entry per tool |
| `check_standards.py` | Cross-file check: every `lisp/` tool has a `shared/` twin **and that twin carries the same version banner**, only the library owns `cal:`, no grouped-build name collisions, no stale `releases/` twin |
| `check_lisp.py` | Static check: unbalanced parens, undefined functions/globals, unused defuns, and special forms given the wrong number of arguments (a four-argument `(if ...)` parses fine and dies at the command line) |
| `check_scope.py` | Static check: local variables used without being declared in a defun's arglist |

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
python3 tests/test_abcurcheck.py      # ABCURCHECK, run in lispvm
python3 tests/test_cabhd.py           # CABHD, run in lispvm
python3 tests/test_abpcheck.py        # ABPCHECK over drawings with known
                                      #   point-to-line distances
python3 tests/test_laser_fit.py       # LHD
python3 tests/test_fitabhd.py         # FITABHD (engine also run in lispvm)
python3 tests/test_perp_points.py     # PERPPTS / CPERPPTS
python3 tests/test_cdcreate.py        # CDCREATE loaded and run in lispvm
python3 tests/test_custblock.py       # CUSTBLOCK loaded and run in lispvm
python3 tests/test_smartfillet.py     # SMARTFILLET loaded and run in lispvm
python3 tests/test_bpcallout.py       # BPCALLOUT loaded and run in lispvm
python3 tests/test_cdcallout.py       # CDCALLOUT loaded and run in lispvm
python3 tests/test_abfind.py          # ABFIND / ABMOVE, run in lispvm
python3 tests/test_abcdef.py          # ABCDEF, run in lispvm against a known survey
python3 tests/test_xyplot.py          # XYPLOT, run in lispvm
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
python3 tests/test_drone_height_lisp.py
python3 tests/test_addon.py           # UV layout exporter
python3 tests/test_cloud_mesher.py    # point cloud mesher
python3 tests/test_dxf_reader.py      # Merlin import
python3 tests/test_mesh_layers.py     # Merlin layered export
python3 tests/test_dewrangler.py      # mesh dewrangler
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
