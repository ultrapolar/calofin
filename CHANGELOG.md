# calofin changelog

Per-tool version banners (`POOL 082726 REV17`, `DIMCHECK v1.4`, ...) say
what changed in one file and drive its `releases/` twin. This file says
which set of them shipped together. The release name lives in
`RELEASE` at the top of `tools/build_shared_bundle.py`, so
`shared/LAZPASS.lsp` announces it on load and cannot drift from it.

## v3.7 -- 2026-09-10

One pass, one idea: a question you can answer is a question you should
be able to un-answer. `Back` (with `U` for `Undo` beside it) was already
the repo-wide convention and already worked at most measurement
prompts -- but a lot of the questions that decide what a run even IS
were still one-way. Getting the pool shape wrong meant quitting POOL;
mistyping ABHD's miss percentage meant quitting ABHD; picking the wrong
side to bead meant Escape and a re-selection.

**Every question chain that had a predecessor now has a way back to
it.** ABHD, CABHD and LHD walk their settings chains (seven, eight and
six announced steps) in both directions, declaration loops included --
Back there takes back the wall, corner or held point declared last,
dashed marker and all, and off the first item it re-opens the Yes/No
that started the loop. CORNERSTP's six options do the same, and because
two of them are only asked when the corner has a diagonal, the chain
carries a DIRECTION: a question this run never put is stepped over on
the way back rather than stopped on. POOL, SPA and POOLSIDE open with
their shape and their base point as one chain. PERPPTS and CPERPPTS
grew Back at the width amount, the join and the dimension style;
NORMIESTEP at its corner-treatment sizes; the three step tools at their
bead questions; DIMCHECK, COVERCHECK and LINFINCHECK at the Move/Keep/
Pick pick and their reference sheet; AUTOBEAD at its clicked steps;
ABCURCHECK at its declarations; BPCALLOUT at its callout text;
STOCKCOVER at "which one?".

**What still has no Back has a reason, and the reasons are written
down.** The root `README.md` names three: the prompt straight after a
selection with nothing else in front of it (a selection cannot be
backed into), a question past committed geometry (there the
draw-as-you-go rule applies instead -- Back at the prompt inside the
loop takes the last step back, drawing and all), and a re-ask that is
itself the correction of a failed range check.

**`U` works wherever `B` does**, which was already true and is now
proven rather than trusted: `tests/test_back_nav.py` reads every `.lsp`
in the tier for the invariant the prompt text cannot show you -- Undo
beside every Back in every `initget` list, the typed `B`/`BACK`/`U`/
`UNDO` predicate spelled the same way everywhere and matched case-
folded, and no file that accepts the keyword and then only tests for
`"Back"`. The other half of the same test walks each threaded chain
backwards through the interpreter, at both tiers.

## v3.6 -- 2026-09-08

Two passes that landed together, and they are the same idea twice: a
value somebody has to be able to reach has to be somewhere they can find
it. One pass put every tool's settings in a block at the top of its
file; the other gave every converter a way back that survives a save,
which is the same thing said about a conversion.

Every converter gains a reverter. `XFTCONV`, `SOCONV` and `VSCONV` each
read somebody else's export and turn it into a drawing this office can
work on; until now the only way back was `U`, which is good for as long
as the session lasts and no longer. A conversion is found out to be
wrong the week after -- the survey was converted twice, the wrong file
was opened, the sheet has to go back to whoever exported it -- and by
then `U` is gone.

So each converter now **writes down what it did**, in xdata on the
objects it touched, and each has a command that reads that back:
`XFTRECONV`, `SORECONV`, `VSRECONV`. The record is the whole idea: an
undo that works from the drawing alone cannot survive a save, because
what a conversion destroys (an erased marker, an overwritten property,
a stripped override block) is not in the drawing any more to be read.

Alongside that, the three converters were read through together:
every knob a shop might turn is at the top of its file with an
explanation beside it, under the tunables rule (STANDARDS 5) that
landed in this same release, and the contingencies a survey brings
in run in the VM at both tiers.

`CONSTELLATION` gets the same pass, and joins the tunables rule with
`AUTODIM` and the two point plotters: every knob gathered into a block
at the top and explained, the paths a clean run never takes driven under
test, and the four defects that turned up on the way closed.

### Added

- **`SPA` puts the corner letters on a mini-model, and turns a quarter
  turn to get its hinges clear of a spillway** (`SPA.LSP` 090826 REV16,
  `TUTORIALSPA.LSP` 090826 REV11). Two moves `POOL` had already made,
  written for SPA on the one August branch the consolidation had passed
  over (`spa-mini-version-layout`, 26 August): its corner-vocabulary
  half was re-done on the trunk the next day, and its other half never
  arrived. It is ported here by hand, against the tunables block and
  the form store SPA has grown since.

  The corner letters no longer sit on the corners of the full-size
  drawing, where they crowd the dimensions, the corner callouts and the
  hinge labels. They go on a small copy of the outline beside the
  report table, with the treatments in place -- a radius corner is an
  arc on it, a cut is its face -- so the report's rows still read back
  against a picture of the shape. Rectangle, octagon and round all get
  one; a round spa has no corners, so its carries no letters and is
  there to say which way round it lies. `spa:*map-gap*` and
  `spa:*map-size*` place it, and it lives on `SPA-NOTES` with the rest
  of the annotation.

  Hinges run north-south, so a spillway on the top or the bottom wall
  stands in the way of every one of them, while the same spillway on a
  side wall cannot touch any. When the spa laid out the way the
  long-overall rule wants cannot get a hinge clear and the other way
  round can, the spillway wins and the spa is turned -- scored on the
  same three things the hinge layout is scored on (dodging every zone,
  fitting the foam length, an acceptable piece count), so the turn is
  never taken at the price of a hinge that overruns the foam. The
  drawing says which turn it took and why, and the spillway's report
  row is named as it was measured with where it ended up added:
  `SPILLWAY TOP WALL (DRAWN RIGHT)`.

  That is why the hinge questions -- the offer, the spillaways, the
  grade and taper -- are now asked as soon as the spa is measured,
  BEFORE a line is drawn: nothing already on the screen can be turned.
  The hinges themselves are still drawn at the end, on whichever
  outline they belong to. The form keys are unchanged and keyed, so
  `LAZSPA` and the palette need nothing; the scripted tests answer in
  the new order. A `NotGiven` corner's report row now reads N/A in both
  columns, as `POOL`'s does.

- **`XFTRECONV`** (`lisp/xftconv/`, with `XFTCONV` at v1.14) puts a
  converted survey back: the marker and the name text the swap erased,
  the leftover text the purge took, the `ab_pt` block off again, and
  the x12 undone by one `SCALE` of 1/12 about the base point the
  conversion used.

  Each block carries the record of what it replaced -- the erased
  entities group by group, plus the scale and the WCS base point, which
  are the two numbers no object in the drawing carries. Coordinates go
  in through `rtos` at 8 decimals, so a round trip is exact to 1e-8 of
  a drawing unit (a hundredth of a micron on a survey in inches) rather
  than to the last bit of the float; `tests/test_xftconv.py` measures
  that on the site-trace sample, whose coordinates carry more decimals
  than the record writes.

  **A highlight holding two conversions is refused by name.** They were
  scaled about different base points, and one scale back cannot undo
  both -- so it says so rather than half-reverting one of them.

- **`SORECONV`** (`lisp/soconv/`, with `SOCONV` at v1.2) moves an
  import back onto the export's own layers. The record keeps the layer
  each object came off, that layer's own colour, and -- only when
  `*soconv-force-bylayer*` was on, since that is the only time the
  conversion overwrites anything else -- the colour, linetype and
  lineweight the forcing replaced.

  A source layer `PURGE`d on the tool's own advice is re-created with
  the colour the record kept, so taking that advice does not close the
  way back.

- **`VSRECONV`** (`lisp/vsconv/`, with `VSCONV` at v1.2) does the same
  for a VS export, and undoes **both halves of the dimension step**:
  the style name back in group 3, and the `ACAD`/`DSTYLE` override
  block back on the dimension, kept verbatim as the xdata items it
  already was. A revert that restored the style name and left the
  overrides off would leave the dimensions drawing in a style they
  never had, which is the same trap the conversion itself exists to
  avoid from the other side.

  Its scope carries no layer filter where `VSCONV`'s does: a converted
  object sits on `POOL` / `POINTS` / `DIMENSION`, where this office's
  own drawing lives too, so the record is what says which objects came
  from an export.

### Fixed

- **`XFTCONV`** (v1.14) died in a drawing with undo recording switched
  off (`UNDO` `Control` `None`). The `_.UNDO _Begin` was already behind
  a check of `UNDOCTL`, but the `_End` on the success path was not, so
  the run swapped every point and then errored out through its handler
  on the group it never opened. Both ends of the group sit behind the
  one flag now, as the handler's close always did.
- **`VSCONV`** (v1.2) created every destination layer -- `POOL`,
  `POINTS`, `DIMENSION` -- before it had looked at the selection, so an
  export with nothing dimensioned left an empty `DIMENSION` behind and a
  highlight of the anchors alone created `POOL` for nothing. It plans
  the run first now, the way `SOCONV` always did: only the destinations
  the selection reaches are created, and only the source layers it takes
  from are unlocked. The same plan fixed the done line's `now empty`
  list, which walked every VS layer present rather than the ones the run
  took objects off -- so that already-empty `4 Dimensions` was named as
  something to purge by a run that never touched it.

- **A complex top-right placement can nest the corner bulge**, and
  OASIS drew nothing rather than saying so. The file argued the case
  away: the gap between a corner bulge's centre and a side bulge's is
  never *less* than their radii differ by. Never less -- but it can be
  *equal*, and equal is an internal tangency, the one pair no tangent
  radius bridges. It takes a corner bulge at exactly half the Y bound
  and the two centres sharing an X, both of which the placement is free
  to arrange: a 40' x 20' with a 10' corner bulge and a 9' right bulge
  shifted a foot out. Every question answered, and then "those radii do
  not make a closed outline -- nothing drawn", which is the one thing
  the routine's header promises never happens. It is refused at the
  placement question now, against both side bulges, and a tie reaches
  the same check -- at its own floor a tie stands the corner bulge
  straight above the right one, which is exactly the shared X.

- **Esc inside the pool-bottom flow left its tangency marks behind.**
  They are scaffolding, like the preview, but they were a local of
  `oasis:askbottom`, which the command's own error handler cannot see
  -- so cancelling there left every numbered mark, in red, over a pool
  that was otherwise finished and worth keeping. They are
  `oasis:*marks*` now and the handler clears them beside the preview.

- OASIS's header banner still described **four families** and listed
  four, having never heard about the NXT cloud; the prompt offers five
  and `oasis:names` builds seven rings, not six. The file STANDARDS.md
  calls the source of truth was the one place describing the tool as it
  was two shapes ago.

- **BPCALLOUT could not ring two points closer than twice its ring
  radius.** A click was read against the rings already down even when
  it had snapped to a survey point, so with the 5" default and two
  points 8" apart, clicking the second landed inside the first's ring
  and un-ringed it -- the run reported "nothing picked" and drew
  nothing. Only a click with NO survey point under it is read against
  the rings now; a click that snapped is the point it snapped to.

- **`CDCALLOUT` and `CDCREATE` closed an undo group they had never
  opened.** Both guard the `_.UNDO _Begin` behind the `UNDOCTL` check
  -- `_Begin` with undo off errors out of the command -- and then
  closed unconditionally, so in a drawing with undo switched off the
  run ended on a stray `_End`. Both close only a group they opened,
  which is what the flag was already there to say.

- **`WCALST` closed one it had never opened either** -- the third of
  that pair, found the same week and the same way. It drew both of its
  layouts first, so with undo off the run died on its own last command
  with the drawing already full and no `U` to take it back.

- **A closed ring made `WCALST` walk for four minutes.** The
  straightest continuation round a ring is always the next segment, so
  tracing a long side lapped it until the 5,000-segment backstop and
  reported a developed length of 694,662 -- about a thousand laps of a
  band 1,250 long. The walk stops at a node it has already stood on,
  taking the segment that closes the lap, so a ring develops as itself
  in under half a second. The README claimed rings were unsupported;
  they are handled, cut open at the segment you clicked.

- **A line touching a long side was counted as a rung.** A datum line
  or a cut mark crosses the chain as steeply as a rung does, and
  counted as one it moved the median width, the vote for which side
  the far edge is on, and -- through the middle rung, which is where
  the far side is picked up -- which layer the far side was taken to
  be on, redrawing the whole far side as loose reference marks. Only
  segments leaving on the majority side are rungs now.

- **The median rung was not the median.** `vl-sort` drops items that
  compare equal (LISPLAB's lesson 2, met in production), so a band
  flared at one end read its width off the deduped list: five 20s and
  two 30s sort to `(20 30)`, whose median is the flare -- 50% wide, and
  the width scales every cut, every filter and the whole layout.
  `vl-sort-i` keeps them.

- **With a tile height, a shallow band was cut through.** The apex rule
  is tile + clearance below the straightened edge, but a clearance
  clear of the foot; on a band shallower than the clearance itself both
  halves go negative and the dart was drawn with its apex ABOVE the
  straightened edge -- a V cut clean through the strip. It is held at
  `wc:*apex-min-f*` of the local depth instead, which is what the
  README had always claimed happened.

- **`CONSTELLATION` closed an undo group it never opened** -- the same
  defect `XFTCONV` had above, found independently in the same release.
  With UNDO off (`UNDOCTL` bit 1 clear) `cst:undobegin` rightly opens
  nothing, but the success path called `cst:undoend` unconditionally, so
  every run in such a drawing ended in the error handler. Guarded on
  `undo-open`, the way the handler already was. Two files carrying one
  mistake is the argument for the library idiom, not for two fixes.

- **`CONSTELLATION`'s handler closed the group with plain `command`.**
  STANDARDS section 5: AutoCAD 2015+ rejects `(command)` inside `*error*`
  unless the error mode was pushed, so an Esc could leave the group open.
  The handler now closes it through `command-s` under
  `vl-catch-all-apply`, as SMARTFILLET and CUSTBLOCK do. (The VM treats
  the two alike, so the cancel sweep passed either way; the library's
  own `cal:undoend` idiom still carries the plain form.)

- **Back from the arcs into a full chart bounced straight back out.** A
  full chart closes itself so the walk needs no final `D` -- and did so
  on re-entry too, so the one reason to Back into it (a dim to change)
  was unreachable. A chart that is already full on the way in now waits
  for `D`, like a fix pass; one that fills up under the operator still
  closes itself.

- **A local named `fix` shadowed the AutoLISP builtin of that name.**
  `c:CONSTELLATION` held the answer to "What needs changing?" in a local
  called `fix`; AutoLISP locals are dynamically scoped, so for the whole
  of that command -- and everything it calls -- `(fix ...)` found a
  string where the function should be. Harmless while nothing called it,
  and found the moment something did: the clamp added to `cst:askcount`
  above. The local is `tofix` now, with a comment saying why.

- **`TUTORIALABHD`'s demo never created the layer it drew on.** Its
  captions, its three candidate outlines and their labels all go on
  `POOL-FIT`, and `entmake` onto a layer the drawing does not have
  fails -- so on a first-time drawing, which is exactly who runs a
  tutorial, the tour drew nothing at all. It gates the layer now, the
  way `pf:compare` always has.

- **A swept ABHD demo left a line on the `POOL` layer.** The walk that
  re-registers the bottom's output as scaffolding started *after* the
  two break lines, and `pf:bottom-draw` takes those out of the registry
  along with its own output -- so the shallow break line was dropped
  and never picked back up, and "Swept -- the drawing is as it was" was
  not quite true. The walk starts behind them now.

- **The pool bottom's dimensions were the one thing ABHD drew without
  its own stamp**, against the rule in its own header that everything
  it creates carries one and only stamped objects are ever erased.

### Changed

- **OASIS puts every knob at the top** -- all forty of them, in one
  tunables block with a sentence each on what changing it does, and
  joins `tests/test_tunables.py` so it stays that way. Fourteen were
  already there; the other twenty-six were spelled out where they were
  read, among them the dimension stand-off's `12` and `18` (POOL's own
  rule, and now a knob that says it has to move with POOL's), the
  preview's `0.6` joiners and `1.25` clearance, the `1.7` a radius
  label sits out from its arc, the `1e-8` the check drawing dedupes
  ties with, two loop guards and a bare `48.0` in the middle of the
  kidney provisionals. Values are unchanged throughout: this renames,
  it does not retune, and `test_the_tunables_are_live` sets one knob
  out of each group on a loaded file and makes the drawing follow it.

  **`oasis:*hopoff*` was not a knob.** The hopper question wrote it, so
  an accepted offset became the session's default -- which is wanted,
  but it meant a pool quietly edited the configuration it had been
  given, and an office that set `24` in a startup file would find it
  saying something else an hour later. The setting and the memory are
  two names now: `oasis:*hopoff*` says where a fresh session starts and
  is never written, `oasis:*hopoff-last*` holds what this session last
  accepted. What a user sees is unchanged.

- **`POOL` and `SPA` join the tunables rule** (`POOL.LSP` 090826 REV24,
  `SPA.LSP` 090826 REV15), the two biggest files in the tree and the
  last of the drawing tools outside it. 72 knobs in POOL and 82 in SPA
  by `tests/test_tunables.py`'s count, each written once, grouped by
  topic, each saying what changing it does, each a row in its README's
  Tunables table. Both files are in that test's `FILES` now, so neither
  block can quietly grow a number back beside the code that reads it.

  What moved up: the output layers and the colour each is created with
  (POOL had `"POOL"`, `"POOL-NOTES"` and `"DIMENSION"` spelled out 67
  times between them), the linetype patterns, the `doff`/`th` rules
  every flow sizes its furniture with, the corner-mark proportions, the
  report and mini-model layout, the guide colours and nominal rings,
  the fitting engine's sweep counts and scan steps, and the suggestion
  and fallback rules. In SPA that also brought up the two tables the
  whole hinge pass is built on -- `spa:*foamtab*` and `spa:*hardtab*`,
  the shop's own foam-sheet and hardware data, which sat 1,200 lines
  down.

  `spa:*lay-hinge*` names the layer the hinges are drawn on, which was
  the literal `"COVER"` inside the draw loop (default unchanged), and
  `pool:*lts*` is gone -- a global nothing had read since the
  per-entity linetype scale replaced it.

  Registering the two turned up a real bug in the checker itself: in
  `assigned()` a STRING value did not take a slot, so every name/value
  pair AFTER a string in the same `setq` was read one position out.
  `spa:setmode` is one long `setq` with `"WATER'S EDGE"` in the middle
  of it, so the three knobs past that string -- read there, never
  written -- came back as writes and check 3 called three settings
  state. Strings count like any other atom now, which is what the
  function's own docstring already claimed.

- `vsconv:restyle-dim` strips the `ACAD` application's xdata and leaves
  every other application's where it is. In AutoCAD that is what it
  always did (an `entget` with an application list carries only that
  application), so nothing about a conversion changes; it is now true
  of the repo's VM as well, which is what lets a tool keep a record of
  its own on an object whose xdata it is editing.

- `entdel` in `tests/lispvm.py` takes an attributed `INSERT`'s
  `ATTRIB`s and `SEQEND` with it, as AutoCAD does -- attributes are
  owned by the block reference. Erasing a point block used to leave its
  number attribute behind as a live entity for the next sweep to trip
  over.

- **The three callout/create tools put every knob at the top**, in one
  tunables block with a sentence each on what changing it does, and
  join `tests/test_tunables.py` so it stays that way. Each had kept
  some settings in a block and the rest inline. New knobs, all
  defaulting to today's behaviour: `bp:*layer-color*`, `bp:*text-gap*`
  (the callout's default spot, which used to be twice the ring radius,
  so shrinking the ring moved the text too), the callout's own wording
  (`bp:*pt-prefix*`, `bp:*tail-one*`, `bp:*tail-many*`, `bp:*unknown*`
  -- seven string literals over four functions until now),
  `cdo:*layer-color*`, `cdo:*exact-eps*` and `cdc:*layer-color*`.

  Two renames come with it, both under STANDARDS 8.4's "only if the
  file is otherwise being reworked": BPCALLOUT's `*BP-LAYER*` family
  takes the file's `bp:` prefix, and CDCALLOUT's three point-classifier
  globals take `cdo:` -- that file already spelled its other knobs
  `cdo:*style*` and `cdo:*layer*`, so it had two schemes for its own
  settings. Both READMEs name the old spellings for anyone whose
  startup file sets them.

- **`WCALST` puts its 38 numbers at the top** (v1.8), the same rule
  again on the tool that needed it most: the dart cap lived in the
  emitter, the cut stop line in the drawing loop, the layer names at
  the `entmake`, and the 1% target was written out four times over
  1,240 lines. The prompt default and both variant summaries read the
  knobs now, so retuning `wc:*maxfeat*` or `wc:*target*` cannot leave
  the question or the sheet quoting the old figure, and the tool
  README carries every one of them in a table. It joins
  `tests/test_tunables.py`; `tests/test_wcalst.py` keeps the half that
  file cannot see, retuning three knobs and checking what the run drew.

- **Every knob at the top, explained.** `XFTCONV`'s settings block is
  rewritten one setting per form with a paragraph each -- what it is,
  when to change it, what depends on it -- and three values that were
  buried in the code joined it: `*xft-block-layer-color*` (the `6` that
  a missing `POINTS` was created with, in two places), `*xft-strip-prefix*`
  (the Leica flavour's letter strip, hard-wired `T` where the trace
  flavour had a switch) and `*xft-column-tol*` (the half text height
  that decides "same column" in the name matching). `VSCONV` gained
  `*vsconv-force-bylayer*` (default `T`), the switch `SOCONV` already
  had with the opposite default -- each tool's default is what its
  sample export does, and the two files now say so about each other.
  `SOCONV`'s block, already complete, has the same header and its
  default colour explained. The per-tool READMEs' tables follow.
- The three headers say precisely what happens to a locked layer: a
  locked **source** is unlocked for the run and re-locked, on the error
  path too; a destination is an output layer, repaired for good with a
  line saying so (STANDARDS 5). The READMEs and tests had it right; the
  headers claimed re-locking for both.

- **A corner treatment sized at exactly its cap was refused, and the
  maximum the prompt then printed failed the same test** (`POOL.LSP`,
  `SPA.LSP`). A treatment is capped at half the shorter wall it sits
  on, so two of them can never overlap and fold the perimeter -- but
  the cap is compared against a setback the routine WORKS OUT rather
  than the number that was typed. A radius becomes `r / tan(angle/2)`,
  and at a true 90-degree corner `cos(45)/sin(45)` is
  `1.0000000000000002` in floating point, not `1`.

  So a 120" radius on a 240"-wide pool -- the full-round end a crew
  really does draw -- measured `120.00000000000003` against a cap of
  `120`, was rejected as too large, and the prompt answered with
  `max 120.0000`: type that back and it is rejected again. A question
  that cannot be satisfied by the figure it shows you, on an input a
  shop actually enters.

  Both files gained a `*capfuzz*` of a millionth of an inch on that
  comparison -- float noise and nothing else, orders below the 1/16" a
  tape reads, so no real measurement changes hands and a treatment
  still cannot overrun its wall. `test_pool_runtime.py` R36/R36b and
  two new cases in `test_spa_runtime.py` pin both halves: the exact-cap
  size draws its four arcs, and a genuinely oversized one is still
  refused exactly once and then takes the maximum it printed.

- **BPCALLOUT could not ring two points closer than twice its ring
  radius.** A click was read against the rings already down even when
  it had snapped to a survey point, so with the 5" default and two
  points 8" apart, clicking the second landed inside the first's ring
  and un-ringed it -- the run reported "nothing picked" and drew
  nothing. Only a click with NO survey point under it is read against
  the rings now; a click that snapped is the point it snapped to.

- **`CONSTELLATION` v1.4 joins the tunables rule** (STANDARDS.md
  section 5), with 38 knobs in a block at the top and a row apiece in
  its README. Five layer colours came out of `cst:preview` and
  `cst:draw`, where they were literal ACI numbers; the label and marker
  floors out of `cst:texth` and `cst:dotr`; the Levenberg-Marquardt
  damping factors out of `cst:lm`; the outline default out of
  `cst:ask`; the overhang threshold out of the report. `cst:*maxpts*`
  is read off the label string instead of being a second number to keep
  in step with it, and `cst:*defcount*` is clamped into range at the
  ask, since the README invites setting it after loading. The golden
  angle is named once for its two users and carries a `NOT A KNOB:`
  marker, since spreading the scattered start evenly is what it does
  and no other value does it. The block closes with the other numbers
  that look tunable and are not -- where `A` sits, the `ab_pt`
  geometry, the float guards, the library helpers the grouped build
  swaps away. `tests/test_tunables.py` carries the file now, so the
  next knob cannot land underneath the block.

- **ABHD puts every knob at the top too** (`abhd.lsp` at 090826
  REV15), in one tunables block of 53 settings in three groups --
  drawing setup, fitter tuning, guards -- each with a sentence on what
  moving it does. A dozen were bare numbers in the body: the
  on-the-shape share of the tolerance (`*PF-ON-FRAC*`), the curve cap's
  relaxing refits and their bound (`*PF-CAP-RELAX*`, `*PF-CAP-TRIES*`),
  what a floating arc and a written-off point each have to buy
  (`*PF-FLOAT-GAIN*`, `*PF-DROP-GAIN*`), the bulge clamp
  (`*PF-BULGE-CLAMP*`), the layer colours, the marker linetypes
  (`*PF-MARK-LTYPE*`, `*PF-STUB-LTYPE*`), the pick-warning multiple,
  the label height, the slow-survey note, the default fit and the
  radius past which an arc is straight. Every value is unchanged.

  What a run WRITES is state, not a knob, and moved out of the block
  the way OASIS's hopper offset did: `*PF-TOL*`, `*PF-MAX-ARCS*` and
  `*PF-HOP-OFF*` are the answers a session remembers, and they sit in a
  `session memory and run state` section under it. `*PF-DEFAULT-FIT*`
  is corrected to `"2"` if it is set to anything but 1, 2 or 3 --
  otherwise a slip there would leave Enter keeping no fit at all,
  silently.

  The same constants land in `LHD` (v2.0) and `CABHD` (v1.9) at the
  same values: those two carry ABHD's span fitter word for word and
  `tests/test_laser_fit.py` and `tests/test_cabhd.py` compare it code
  for code, so a fitter knob changed in one has to change in all three.
  ABHD is not in `tests/test_tunables.py` yet: its knobs are spelled
  `*PF-NAME*` rather than `pf:*name*`, and that rename is a coordinated
  pass over three tools and four suites (the block says so, at the top,
  where someone looking for the omission will be).

### Checks and tests

- `tests/test_xftconv.py` honours `CALOFIN_LISP_ROOT` -- its docstring
  promised a shared-tier run from the start, but the path was hard-wired
  to `lisp/`, so the grouped twin was only ever load-checked. `make
  parity` now runs the converter at both tiers like its two siblings.
- `tests/test_converter_tunables.py` holds the tunables rule for these
  three the way `tests/test_tunables.py` holds it for the four GUI
  files. It could not simply extend that one: its parser reads a knob
  as one `setq` per line with a scalar after it, and the converters'
  central knobs are multi-line tables (`*soconv-map*` is seven rows)
  whose default cannot be written in a README cell. So the block is
  walked by parens instead, and the README check asks that every knob
  HAS a row rather than comparing the default in it. It was worth
  writing: it caught `XFTCONV` explaining each knob *below* its `setq`
  where every other file in the tree explains it above.
- Contingency sections in all three suites: undo switched off, an
  import already in inches, a plain `POINT` for a marker, MTEXT and
  justified names, each settings switch in its non-default position, a
  frozen and switched-off destination repaired rather than drawn onto
  blind, the attribute style falling back to `TEXTSTYLE`, an error
  mid-run through `XFTCONV`'s handler, both flavours in one highlight,
  `XFTCONV-SETUP`; `VSCONV`'s and `SOCONV`'s retuned tables and default
  colour, `VSCONV`'s `*vsconv-dim-xdata*` `nil`, an export with nothing
  dimensioned, and a `SOCONV` highlight carrying nothing of the
  export's.

- `tests/test_constellation.py` grows fifteen contingency tests -- 73
  assertions on top of the 113 already there, 186 in all: Esc mid-chart
  and at the last question, Back at every question in the chain and back
  into a full chart, the count floor and ceiling and a clamped default,
  zero and negative measurements at every distance prompt, pair and run
  names that are not ones, a pair given twice, the three-point floor,
  the layer colours and an existing layer keeping its own, a frozen and
  switched-off layer restored, the block made once, UNDO off, an arc
  named out of ring order and one with an impossible radius, and each
  knob at the top moved and shown to move what it says. Both tiers.
- `tests/test_tunables.py` takes `CONSTELLATION` into `FILES`, which is
  what holds its block and its README table together from here on.

- `tests/test_abhd_contingencies.py` drives `ABHD`, `ABHDCOVER` and
  `ADAB` through the paths a bad drawing takes -- no points, two
  points, five duplicates, a gap, a `SPLINE`, a tilted UCS, a distance
  past the ceiling, a percentage over 100, a pick nowhere near a survey
  point, a break picked twice on one point, a bottom cancelled halfway,
  a `Redo` that omits a point and puts it back -- and runs
  `TUTORIALABHD`, which nothing had ever executed. 65 checks in 13
  sections, at both tiers, each reading the message the path prints and
  what it left in the drawing. The last section holds the block itself.

- Two gaps in `tests/lispvm.py` the suite could not have been honest
  without. `ssget` ignored the `-4` grouping operators, so ADAB's
  automatic point sweep -- an `<OR` of three `<AND` groups -- matched
  nothing at all; and `distof` read only the leading number, so `3'6`
  came back as **3** in every feet-and-inches answer in the tree,
  `LAZFORM`'s and `LAZSTEP`'s included, which is the whole reason they
  try mode 4 before mode 2.

### Notes

- Each reverter is on the panel under its converter, in the same
  `Converters` column: a `RECONV` is looked for in exactly one
  situation, and the place it is looked for is where the converter was.
- All three records can be switched off (`*xft-record*`,
  `*soconv-record*`, `*vsconv-record*`). With one off its converter
  runs exactly as it did before, says so in its done line rather than
  promising a revert, and its reverter says there is nothing to work
  from.
- **One thing a revert spells out rather than restores**: an object
  that arrived carrying no colour, linetype or lineweight of its own
  comes back carrying the explicit ByLayer (`256`, `"ByLayer"`, `-1`)
  that means the same thing. It draws and plots identically. Nothing
  else about a round trip is approximate.

- `lisp/lazpanel/README.md`'s page tables are rewritten from the
  panel's own tables. Four of them had drifted: the `Cover` page was
  missing `LINGUTTER` and `LINGUTTERSCAN`, `Layout` was missing
  `POOLSIDE`, `LAZSPA` and `LAZSTEP`, `Points` was missing
  `POINTRENAMER`, `CONSTELLATION` and `TYLERDRONESUITE`, and `Checking`
  was missing `ABPCHECK`.

A pass over the ten live checkers, one at a time: every value a drafter
might want to change moved to a `TUNABLES` block at the top of its file,
each with a comment saying what it controls, its units, and what raising
or lowering it does. Three of them were bugs rather than untidiness.

### Changed -- the ten checkers

- **Every checker now opens with one tunables block** -- `CHECK` (v1.7),
  `DIMCHECK` (v1.13), `LINFINCHECK` (v2.9), `COVERCHECK` (v1.12),
  `SPACHECK` (v1.13), `ABPCHECK` (v1.5), `ABCURCHECK` (v1.4),
  `LINCHECK` (v1.4), `LINTXTCHK` (v1.5), `CCPRECHECK` (v1.4) -- and each
  suite asserts three things about it: no knob is set anywhere else in
  the file, none is missing an explanation, and the README's Tunables
  table names them all. Those tables are generated off the block itself,
  headings and prose included, so the two cannot disagree.

  The block also states the contract the files never used to: every knob
  is read when the command RUNS, so a `setq` typed at the command line
  takes effect on the next run. The suites drive that -- a raised
  tolerance forgiving the gap it used to shift, a renamed report layer,
  feet-and-inches distances, a widened planarity gate auditing a tilted
  arc, a direction bucket narrowed under a pair's 0.2 degrees.

- **`DIMCHECK`, `LINFINCHECK` and `COVERCHECK` share one shape.** The
  three are siblings (~40 helper names and 1,200-1,400 identical lines
  pairwise), so the same values were buried in the same helpers: the
  report-sizing cluster, the reading-order row band, the marker size,
  the overlap direction bucket and entity list, the distance format and
  three numerical guards. The sizing constants were typed twice in each
  file -- once in the review command, once in the scan -- so a report
  that came out the wrong size had to be fixed in two places or in
  neither.

- **Colour words follow the colour knobs.** The reports said "recolored
  red" and "(magenta)" whatever the knobs held. `DIMCHECK`'s attention
  pattern matched on the word MAGENTA, which is what forced it; it
  matches on ENDPOINT(S) MOVED now -- what the line means rather than
  what colour it came out -- so every colour word in the review, the
  report and the tutorial is the colour actually used.

- **`SPACHECK`'s grade, taper and short-name vocabularies are tables.**
  Three `cond`s spelling out words that have to agree with the foam and
  hardware tables above them; a shop whose blocks say "Deluxe FRP" adds
  a row instead of editing a cond.

### Fixed -- three of those were bugs, not untidiness

- **`SPACHECK` could pass a sheet with no border.** The title-block
  finding was decided by looking for the word `OK` in its own sentence,
  and the "NO BORDER found on layer 'X'" sentence names the layer -- so
  a border layer called `TB-OK` read as a pass. `spachk:title-verdict`
  returns a flag beside its sentence now and the audit reads the flag.

- **`ABCURCHECK`'s `Remove` ignored `acc:*snap-dist*`.** It dropped the
  declaration nearest the pick however far away that pick landed, so a
  stray click anywhere in the drawing removed one. It honours the snap
  distance, as the declare pick always did. Its index also prints its
  weights' actual sum rather than a typed `/ 100`.

- **`LINTXTCHK`'s layout parameters could not be changed either way.**
  The README said they were "set near the top of `LINTXTCHK.lsp` and are
  easy to tweak"; they were locals of the command, so editing one meant
  a trip inside the defun and a `setq` typed at the command line was
  overwritten the moment the command started. Height, spacing, indent,
  the bullet and the 26-line checklist are globals now, and the done
  message names the height it actually used.

  Six of the ten join `tests/test_tunables.py`, the repo-wide rule the
  same release introduced, so one test now holds them to it: every knob
  inside its block, none stray outside it, none re-assigned, each saying
  what changing it does, and each a row in its README's table carrying
  the default it really has -- 304 knobs over 13 files. The four that
  cannot join yet are the ones still spelling their globals
  `*tool-name*` rather than `tool:*name*`, which that test's namespace
  pattern cannot see; their own suites carry the same assertions.

  Two knobs had to stop being two things at once to get there.
  `abp:*limit*` was a default the command overwrote with whatever you
  last answered, so it read as a setting while being state; the knob is
  the default now and `abp:*asked*` is the answer. `SPACHECK`'s three
  demo/sysvar globals moved out of the block for the same reason.

### Not changed, on purpose

- The questions `LINCHECK` and `CCPRECHECK` ask. For those two the
  wording, the order and which answer opens which follow-up are one
  thing, held in the code; a table of prompts split from the branching
  that reads them would be two places to keep in step instead of one.
  Their blocks carry how each walk TALKS -- the tick, the separators,
  the report's box, the Back synonyms each file had written out twice.
- The deprecated acady matcher (`lisp/standards_checker/`), which
  `STANDARDS.md` keeps as-is.

## v3.5 -- 2026-09-02

`SOCONV`'s sibling, written the same way: from a before/after the shop
supplied rather than from a description. `vsconv.dxf` holds a VS survey
export and a by-hand conversion of it side by side in one drawing,
labelled "before" and "after", and pairing the two halves on geometry is
what the rules below are.

### Added

- **`VSCONV`** (`lisp/vsconv/`, v1.0) converts a VS survey export onto
  the shop's layers: `1 Perimeter`, `2 Coping` and `3 Features` onto
  `POOL`, `3.1 Anchors` onto `POINTS`, `4 Dimensions` onto `DIMENSION`,
  with color, linetype and lineweight forced BYLAYER so the moved
  geometry takes the destination layer's appearance rather than carrying
  the export's over. The map is a table (`*vsconv-map*`), so an export
  that names its layers differently is retuned in one place.

  **The dimensions need more than the layer move, and that is the half
  worth having.** The export writes text height, arrow size and decimal
  places into every dimension as an `ACAD`/`DSTYLE` xdata block, and an
  override outranks the style it sits on -- so a dimension merely
  renamed to `STANDARD` would still draw itself in the export's
  2.5-unit text. The sample's after-half carries no xdata at all, which
  is what says the overrides go with the rename. Replaying the sample's
  55 before-entities through the routine reproduces its after-half
  exactly: layer, dimension style and xdata, entity for entity.

  Scope is the highlight, or Enter for every VS layer in the drawing;
  only the layers in the table are touched, so a sheet already carrying
  converted work cannot be converted twice, and a drawing with none of
  them is told so rather than prompted over. As in `SOCONV`, the
  emptied source layers are named in the done line rather than purged,
  so one `U` backs the whole run out.

  Where `SOCONV` is a layer remap and only a layer remap -- because that
  is all its sample does -- this one restyles as well, because that is
  what ITS sample does. The two exports are different tools' output and
  the two routines say so.

## v3.4 -- 2026-09-02

One command, written from a before/after the shop supplied rather than
from a description: `SOconv.dxf` holds an SO site-survey export and a
by-hand conversion of it side by side in one drawing, and pairing the
two halves on geometry is what the rules below are.

### Added

- **`SOCONV`** (`lisp/soconv/`, v1.0) puts an SO site-survey export onto
  the shop's layers: `Pool Perimeter` and `Obstacles` onto `POOL`, the
  Leica points and `Existing Anchorss` onto `POINTS`, and the export's
  one `Dimensions` layer split in two -- its notes onto `TEXT`, its
  dimensions and anything else left there onto `DIMENSION`. The rules
  are a table read in order, first match winning, so the split is
  ordering rather than special-casing and a shop whose export names
  things differently retunes in one place.

  **It is a layer remap and only a layer remap** -- no restyle, no
  forced BYLAYER, no rotate, nothing erased and nothing drawn. That is
  what the sample does: pairing its two halves matches 316 objects and
  the only DXF group that differs on all of them is group 8. So the 161
  Leica points keep the explicit magenta they arrive with, and the notes
  keep their height, style and text. `*soconv-force-bylayer*` is the one
  line that turns it into the cleanup `DRONE` and `TYDRN` do.

  Two things the sample shows that are deliberately NOT in the tool: its
  after side is one dimension short (the drafter dropped a linear dim
  while making it -- an edit, not a rule), and the export's now-empty
  layers are left in the drawing for `-PURGE` rather than deleted
  behind the drafter's back. The done-line names them.

## v3.3 -- 2026-09-02

Two commands the trunk had never seen, brought over from the one branch
that shares no history with it. The constellation branch was written
against a base this tree diverged from 222 commits ago, so nothing here
was cherry-picked: the files were taken one by one and fitted to the
trunk's tooling, which is what the mirror map, the loader manifest, the
panel roster and the derived counts all had to be told about.

### Added

- **`CONSTELLATION`** (`lisp/constellation/`, v1.3) places labelled
  survey points when the sheet gives only the distances BETWEEN them and
  never says where any of them is -- the one survey shape no other
  importer here can read. Stress-majorization sweeps find the answer and
  damped Gauss-Newton lands on it exactly, so a set of tape readings
  that cannot all be true still gets the layout that misses by least,
  and the report names the single dim worth re-measuring instead of
  starring nine innocent ones. Arcs, a self-crossing warning, and a
  fix-and-redraw loop, because a number typed wrong is invisible on the
  chart and obvious on the drawing.
- **`TYLERDRONESUITE`** (`lisp/tydrn/`, TYDRN v1.5) runs the whole drone
  trace in one: `TYDRN`, then `PADDLE`, then the shop's own `CDIM`, in
  the order the work has to happen in. One highlight is carried through
  every stage and grows by what each stage draws; each stage keeps its
  own undo group, so a stage that went well is not undone to get at one
  that did not; the calofin stages are checked before any of them runs.

### Fixed on the way in

- **`CONSTELLATION`'s own copies of two library helpers were behind the
  library.** `cst:syssave` skipped the whole save when a snapshot was
  already pending -- the defect v3.1 fixed in `cal:syssave` -- and
  `cst:undobegin` opened its group without the `UNDOCTL` guard, so a
  `_Begin` in a drawing with UNDO off would have errored out of the
  command. Both are the library bodies now, which is what lets the
  mirror map swap all 28 helpers away and leave the twin a rename.
- **`TYLERDRONESUITE` installed its handler by swapping the global
  `*error*`** through a pair of globals, and held PICKFIRST in one of
  them -- the class rule 1b and `handler-free-var` were added to reject
  in v3.1 and v3.2. `*error*` and the saved PICKFIRST are locals of the
  command now. Inside a stage the stage's own handler is still the one
  AutoCAD calls, which is why each stage cleans up after itself; the
  README says so where it used to promise more.

### Checks and tests

- `tests/test_constellation.py` (36 assertions) and
  `tests/test_tydrn_suite.py` run at both tiers; `CONSTELLATION` joins
  the cancel sweep by construction, and `TYLERDRONESUITE` is named in
  its `NO_PROMPT` roster with the reason -- its pre-flight check runs
  before its first question.
- The VM seeds `PICKFIRST` at AutoCAD's own default of 1, so a test that
  watches it come back has to turn it off first to prove anything.

## v3.2 -- 2026-09-02

The second stability pass. It reconciled the branches first, then closed
the classes of defect that only show up in the NEXT command a drafter
runs, and left the tree able to prove every one of them stays closed.

### Branches

- Four branches carried work the trunk had never seen -- LAZPANEL's Find
  page, OASIS's top-right bulge bound to the top wall, POOL's rectangle
  corner questions and its grecian taped-face defaults -- and each was
  ported onto the trunk by cherry-pick with its tiers regenerated. The
  POOLDEMO sample sheet was found calling `pool:muttend` with ten
  arguments where the ported commit wanted twelve; only a test noticed.
- `.claude/hooks/session-start.sh` puts a session on the trunk: a clean
  tree elsewhere is switched, a dirty one or a branch carrying unmerged
  commits stops the session with the commands to land them. CLAUDE.md
  carries the real count of historical branches (some sixty) and the
  end-of-session push that keeps the trunk in step.

### Fixed

- **`LAZPANEL v3.4` stopped re-installing itself on every drawing
  open.** With the build in the Startup Suite, every drawing paid two
  icon writes into the first support-path folder and a walk of the CUI.
  The button work is marked done on the blackboard, the one namespace
  every document shares, and icons already on disk are left alone.
- **Five tools left AutoCAD's error mode stacked after every clean
  run** -- `XFTCONV`, `PERPPTS`, `CPERPPTS`, `AUTOBEAD` (and so the
  three step routines that bead) and `OASIS` pushed it for their handler
  and popped it only from the handler. A stacked mode refuses `command-s`
  inside every later handler, so the next tool's Esc left its undo group
  open without a word. Each pops on every exit now, as POOL always did.
- **Four tools kept their undo-group flag in a global** shared with
  their demo and tutorial -- `POOL`, `SPA`, `POOLSIDE`, `SPACHECK` -- so
  a run that died between its last dim and the close had the next
  command's handler close a group it never opened. The flag is a local
  of the command that opened the group, and the grouped build swaps the
  helper pairs for `cal:undobegin` / `cal:undoend`.
- **Handlers that restored less than the run changed.** The step
  routines put CLAYER back (an Esc mid-dimension left the drafter on
  DIMENSION); the check family's entity cleanup goes through the catch so
  a throw can no longer skip the undo close; the three RESCUE commands,
  TUTORIALCOVERCHECKCLEAN and TUTORIALPADDLE gained the handler and the
  one undo group they never had; LAZTXT and LAZPIN unload their dialog
  from a handler and every dialog file deletes its temp `.dcl` when
  `load_dialog` refuses it; TUTORIALCOVERCHECK holds ATTDIA, ATTREQ and
  FILEDIA itself; AUTOBEAD's command gained a cancel-aware handler.
- **The multi-file loader asked its one-time question on every drawing**
  on a machine whose HKCU is read-only: `vl-registry-write` answers a
  denial with nil, not an error. The answer is kept in the profile
  (`setenv`) as well.

### The checks got stricter

- `check_lisp`: a pushed error mode must be popped outside the handler
  (rule 1c); an undo group opened in a defun is closed on its success
  path and from its handler (rule 5).
- `check_scope`: `handler-free-var` names a variable a handler reads
  that is neither its own nor a local of its command.
- `check_registry`: a test census -- every command is invoked by a suite
  or excused in `UNTESTED` with the reason, and an excused command a
  suite catches up with fails the check.
- The bundle verifies every `cal:` helper the tools call against the
  library at build time and again at load, and clears the build flag it
  set so a later solo library load still warns. `tests/test_shared.py`
  pins the loader's order.
- The VM counts undo groups and the error mode, refuses to return from
  a command that left either behind, runs `prompt` output through the
  same log as `princ`, seeds every system variable the tree touches at
  AutoCAD's default and answers an unknown one with nil. New suites:
  `test_autobead.py`, `test_cancel_paths.py` (every headline command
  cancelled at its first prompt), `test_loader.py`.

## v3.1 -- 2026-09-01

A stability pass over the one-file build. Nothing new to type; what was
there fails less, and two of the ways it could have failed the NEXT tool
in the session are closed.

### Fixed

- **`DRONE v1.3` / `TYDRN v1.3` no longer install their error handler by
  swapping the global `*error*`.** Both saved the global, set their own,
  and put it back on each exit -- so one exit missed (a throw inside the
  handler's own `EndUndoMark`, say) left that tool's cleanup live for
  every command run afterwards in the loaded-together build: closing an
  undo mark it never opened, re-locking layers it never touched. The
  handler is local to the command now, as the skeleton in STANDARDS 5
  has always said, sees the run's state through dynamic scope rather
  than through `*drone-doc*` / `*drone-unlocked*` globals, and closes
  only a mark the run actually opened.
- **`PADDLE v1.9`'s handler closed an undo mark it might never have
  opened.** An Esc at the perimeter prompt comes before
  `StartUndoMark`; the handler's unconditional `EndUndoMark` then threw
  from inside `*error*`, where nothing catches it. It tracks the mark now
  and closes it through `vl-catch-all-apply`.
- **`CALOFIN-LIB v1.5`: the shared sysvar snapshot merges instead of
  skipping.** Every tool in the grouped build shares `cal:*sysold*`, and
  the tools list different variables. After a run cut short, the next
  tool's `cal:syssave` used to save NOTHING -- so a variable the dead run
  never listed (`CLAYER`, `CMDECHO`) was changed and never put back. A
  variable already pending keeps its true value exactly as before; one
  the snapshot lacks is added. `tests/test_calofin_lib.py` pins both
  halves.

### The checks got stricter

- `check_lisp` fails a `(defun *error* ...)` or `(setq *error* ...)`
  whose enclosing command does not declare `*error*` local, and a
  handler at top level. Zero findings tree-wide once the two above were
  fixed; the deprecated acady matcher keeps its swap idiom.
- The VM can now run `*error*` (`vm.handle_errors = True`): a failure
  outside `vl-catch-all-apply` reaches the handler the failing code can
  see, with every frame still live, and the command is then aborted the
  way AutoCAD aborts it. It also carries just enough ActiveX -- the
  document, its undo marks, the layer collection with `Lock`, and the
  entity properties the cleanup tools put -- for `DRONE` and `TYDRN` to
  run under test for the first time: `tests/test_drone.py` drives the
  happy path, an error mid-run and an Esc at the prompt, at both tiers.

## v3.0 -- 2026-08-27

The release that made the whole toolset drivable from a filled-in chart,
and made the tree able to prove it is in step with itself.

### Zero-install GUI: fill the chart in, press Insert

- **`LAZSPA`** (new) -- `LAZFORM`'s argument applied to `SPA`: three
  charts (Rectangle, Octagon, Round), the boxes wedged into the
  dimension rows, and the spa drawn from what you typed.
- **`LAZSTEP`** (new) -- say how many steps, and the drawing is built
  for that count: N treads with their widths, N risers and N+1 drops,
  every dimension carrying its letter until you type over it.
- **`LAZFORM v2.5`** -- one authority decides what is greyed, and the
  letters it was missing are there.
- All three are plain DCL the file writes for itself, so there is no
  DLL to `NETLOAD` and no artwork to ship.

### The routines take answers from a form

`POOL`, `SPA` and the three step routines each carry an answer store the
ask helpers read before they prompt, so a filled-in chart drives the run
and a half-filled one shortens it. One contract everywhere: a key that
is absent is asked for as usual, `(key . nil)` answers NA without a
prompt, `(key . 84.0)` answers the measurement -- and **an answer is
removed as it is used**, which is what stops `Back` deadlocking on a
question the form already answered.

- `pool:*form*`, `spa:*form*`, `*cs-form*` / `*hs-form*` / `*ns-form*`,
  each with its own `run-with-answers`, cleared on both exits.
- POOL's gate questions and the step routines' count take form answers
  too -- the count is a question the step tools never had before.
- The VB palette caught up with what `SPA` actually asks, and its
  catalog with the tree.

### FITABHD fits the oasis pools too

- **`FITABHD v2.0`** -- the type list gains `OAsis`, and the survey of a
  continuous-tangent pool is fitted with **`OASIS`'s own ring solver**,
  carried into `FITABHD.lsp` under its own prefix so the two files
  cannot draw different pools from the same numbers.
  `test_oasis_ring_is_oasis_lsp_s_own` runs both through the VM and
  compares them element by element.
- Step 2, which has no corners to ask about on an oasis, asks which of
  OASIS's five families it is instead -- in OASIS's own words
  (`Center/TopRight/CLoud/Kidney/NXTcloud`). Steps 5 and 6 are skipped
  the way they are for a Round pool: neither shape has a wall to swing
  or to bow.
- **Everything else about the shape is measured.** An oasis has no walls
  for the edge vote to find a rotation from, so the frame is swept right
  round the pool and the best few placements fitted properly; the
  envelope then falls out of the bounding box, because every bulge is
  tangent to a bound.
- **A cloud's flat bottom is found, not declared.** Every joiner is
  carried as `U = h / (h + R)` rather than as a radius, so the straight
  run -- the reverse arc with an infinite radius -- is just `U = 0`,
  with no special case at either end. The report names the shape
  `straight-bottom cloud` or `rounded-bottom cloud` from what came out.
  Which way a kidney was given is settled the same way: both
  parameterisations are fitted and the points choose, with the freer one
  held to the both-ends evidence margin.
- The report prints every fitted radius under OASIS's own question
  wording, and all of them snap under the *feature* rule -- a measured
  radius, never a design dimension.
- An oasis wants at least 12 survey points, and its hopper is square to
  the envelope rather than to a wall, so all four bounds are offered as
  ends.

### Fixed

- **Output layers are repaired, not just created.** `POOL`, `SPA` and
  the four check tools drew onto a frozen or switched-off layer and
  reported success while producing nothing visible.
- **`LITELINFINSCAN` silently dropped the steps rule** -- a sheet with an
  obvious staircase reported "no step patterns detected" and lost its
  rise-vs-wall-height comparison. The one a drafter would have been
  burned by.
- **`Back` un-counted a defpoint move it could not undo**, so the report
  claimed "points adjusted: 0" over a drawing whose points had moved.
- **Scan findings never rendered red**, on the report whose whole job is
  to make problems findable.
- One canonical cancel test repo-wide (a `*break,` typo had already been
  copy-pasted into a second file), and every living tool now has an
  `*error*` handler that puts back what it changed -- including
  `AUTOBEAD`, which closed an undo group it might never have opened, and
  `PADDLE`, whose block import could leave `CMDECHO` and `ATTREQ`
  clobbered.
- `SPA` speaks the canonical `Square / Radius / Cut / NotGiven`
  treatment, with the sheet-legend words (`90`, `Diagonal`) still
  accepted and normalised -- so `LAZSPA`'s dropdown keeps the drafter's
  vocabulary while the routine keeps the standard's.
- Brackets a click can actually send, one tutorial selector, one pause
  spelling, `ROUnd` everywhere.

### The tree can now prove it is in step

- `mirror_shared.py`, `release_lisp.py` and `build_shared_bundle.py`
  each grew a `--check` mode, and `check_standards.py` runs all three:
  a hand-edited generated twin, an orphaned release or a stale bundle
  body now fails a check instead of shipping.
- `check_lisp.py` exited 0 on the unbalanced parens it advertised;
  `check_scope.py` had no exit code at all. Both gate now, with their
  false-positive classes fixed and a baseline so new findings surface.
- **47 of the 51 grouped twins are generated** (was 14), which is what
  stops the drift class that put two defects into `LAZPASS.lsp`.
- `tools/run_tests.py` + a `Makefile`: `make check`, `make test`,
  `make parity`. The canonical test list was prose in four documents and
  two files had already fallen out of it; the runner globs the directory.
- End-to-end tests for `DIMCHECK`, `LINFINCHECK` and `COVERCHECK` -- the
  three largest tools that had none -- plus `LAZSPA`, `LAZSTEP` and the
  step form suites.
- Nothing is expected to fail on a clean checkout: `EXPECTED_FAILURES`
  in `tools/run_tests.py` is empty, and a test that starts passing there
  fails the run until its entry goes.

### Deliberately deferred

Recorded in `STANDARDS.md` section 8 with reasons rather than left as
silent gaps: the uppercase `.LSP` filenames, SPA's spillaway corner-pick
keywords, `cal:askkw`'s signature (pinned by every generated twin at
once), the `prefix-` naming styles, and the VB palette's button catalog
(it cannot be compiled or tested here).
