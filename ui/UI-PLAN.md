# Making the LazPass UI less primitive

The zero-install GUI that ships inside `LAZPASS.lsp` is four DCL
dialogs: `LAZPANEL` (the launcher) and the three chart forms,
`LAZFORM`, `LAZSPA` and `LAZSTEP`. Everything works and everything is
tested; what it is not is *easy*. This is the plan for that, written
2026-09-01, with phase 1 landed.

The decision behind it: **both surfaces, sharing a data layer.** The
DCL panel stays the zero-install floor, the VB.NET palette in
`calofin_net/` stays the eventual ceiling, and the tables they both
render -- the roster, the captions, the chart geometry, the field maps
-- move to one place so the two stop drifting. `ui/PLAN.md` records how
the palette got here and why the wire is shaped the way it is; this
file is about what is still primitive.

## What "primitive" actually means here

Not the visuals. DCL's look is fixed and nobody is going to change it.
These are the things that cost the drafter time:

| | Where it bites |
| --- | --- |
| **Finding a tool** | 67 commands laid out as 148 buttons over 8 pages, found by eye. The job pages carry the command *name* alone, so the caption that says what a tool IS was on a different page from the button you wanted |
| **Knowing what a tool is** | 67 captions exist, and until now you could only read them by going to a category page |
| **Nothing is remembered** | Pins are hand-picked and that is the whole of it -- no recents, no history |
| **The forms find out too late** | A number that will not do is discovered by `POOL` at the command line, after the dialog has closed and the form is gone |
| **The hand-off is invisible** | Press Insert and the routine asks for the gaps; the form never says which gaps, so you cannot tell a finished sheet from a half one |
| **Three of everything** | `LAZFORM`, `LAZSPA` and `LAZSTEP` carry three stroke fonts, three vector-chart engines and three DCL emitters, ~270 near-identical lines apiece, duplicated *by rule* |
| **The palette has drifted** | *(closed, phase 5a)* `calofin_net/` carried its own typed copy of the roster; the catalog is generated from `LAZPANEL`'s tables now |

## What DCL can and cannot be argued out of

Worth stating once, because half of the above is blamed on DCL and only
some of it is DCL's fault.

**Genuinely fixed:** dialogs are modal, so the panel cannot stay open
while a tool runs. No absolute positioning, no overlap, no z-order, so
a box cannot sit on the artwork. No raster -- an image tile takes
vectors or a slide. No tab tile, so a tab is a button that closes the
page and reopens the next, and it blinks. No per-keystroke callback on
an edit box. A dialog taller than the screen does not open, and nothing
can measure the screen from inside AutoLISP.

**Not DCL's fault, and therefore fixable:** there was no search. There
were no recents. Nothing validated a box before the dialog closed.
Nothing said what would still be asked. Those are all reachable with
tiles DCL has had all along -- `list_box` repopulated through
`start_list` while the dialog is up, `mode_tile` on the OK button, a
`text` tile as a message line.

## Phase 1 -- Find *(done, v3.2)*

A ninth page on `LAZPANEL`, first on the tab strip: a box to type in, a
list of what matched, a message line. Type any part of a name **or of
its caption**, and the list narrows; the top hit is selected as you
type, so Enter runs it.

Searching the captions is the point rather than a bonus -- `survey`
finds `ABHD`, `ABPCHECK` and `ABHDCOVER`, none of which say so in their
names. The needle is taken literally (`lzp:instr`, a written-out
substring search) because the text is whatever the user typed, and
`wcmatch` would read a `*` in it as a pattern.

A tool this session has not loaded is **listed** here, marked `(not
loaded)`, and Run refuses it with that reason rather than launching --
the opposite of the greyed button on every other page, and deliberately:
a greyed button in a grid is a dead spot you can see, but a search that
omits what you searched for reads as the tool not existing.

Find is a page but not a group. It stays out of `lzp:*groups*`, which
is what `Rest` is computed against and what `lzp:commands` folds;
`lzp:pages` flattens the strip and is what the page loop and the tab
wiring read. `tests/test_lazpanel.py` covers the search, the wildcard
literalness, the fill, single click versus double click, the refusal,
and the whole page end to end through its own `action_tile` strings.

## Phase 2 -- what the panel remembers, and how many pages it needs

- **Recents.** *(done, v3.3.)* The last five launched, newest first,
  on a `Recent` row above `Pinned`, stored under its own value in the
  key pins already use. Two decisions worth keeping: a tool is
  remembered when it is **launched**, not when it finishes -- one that
  errored or was escaped was still the one you reached for -- and a tool
  already **pinned** is stored but not shown, or Recent would fill up
  with the handful of tools Pinned already carries. The row is absent
  until there is something in it, so a first-run panel is no taller
  than before; both rows pack through one `lzp:packrow`, so neither can
  be the one that forgets the width budget.
- **Consider dropping the four category pages.** They exist so a tool
  you cannot place in a job is one tab away -- which is exactly what
  Find now does, better, in one page instead of four. 8 pages become 5,
  148 buttons become about 90, and the tab strip fits one row. Against
  it: the four category names are the ones the VB palette groups by, so
  they would have to survive as data even if they stop being pages.
  **Worth doing only after phase 1 has been used in anger** -- if Find
  turns out to be where people live, the case makes itself.
- **Land on Find by default.** One line (`lzp:*page*`'s fallback). Held
  back from phase 1 on purpose: the panel already reopens where you
  left it, so someone who lives on Find stays there without the default
  changing under everyone else.

## Phase 3 -- the forms stop finding out too late *(done, all of it)*

All three forms carry a **state line** now, and it holds `Insert` back.

The failure it closes was worse than "no validation". Each form's
`answer` helper turns anything it cannot read into *not answered*, so
the key is never sent and the routine asks for it again at the command
line -- while the chart goes on showing what was typed, because the
chart draws the **string**. A box that would be silently dropped looked
exactly like a box that was answered.

- **LAZFORM** (v2.8) names any unreadable box by the letter the sheet
  prints -- `lzf:tagof`, not the POOL key, or the drafter hunts for a
  letter that is not on the paper.
- **LAZSPA** (v1.1) has a second silent drop to report: `lzs:keyanswer`
  **demotes** an `NA` on any key SPA has no NA for. That is the sharper
  one, because `NA` is a word the form itself tells you to type.
- **LAZSTEP** (v1.1) has two readers to fail -- `lzt:answer` for a
  measurement, `lzt:int` for the count and the bench step -- and `3.5`
  is the case that separates them: a fine measurement, and not a step
  number at all. Its page-one line is the tile the count refusal has
  always written to, and `lzt:countwhy` is now the one rule both the
  live warning and the refusal at the gate read.

With nothing unreadable the same line is the **hand-off**: how much of
the sheet is filled and what the routine will still ask for. Both halves
count only live boxes -- a greyed box is withheld whatever is in it, so
rubbish in one is neither complained about nor counted.

The anti-drift property is the one that matters: the line **reports
`lzX:form` rather than second-guessing it**, and each suite partitions
every live box into sent / still-to-ask / unreadable (and NA-demoted, on
SPA), failing if any box lands in two groups or in none.

Both of this phase's leftovers landed too:

- **`Recall last`** *(done)* -- a button on every form that puts the
  last accepted sheet for *this chart* back into the **empty** boxes
  only, so it can never overwrite a number just typed and pressing it
  twice is a no-op. Never a default: pre-filling would put the last
  pool's numbers on this pool, and a wrong number that looks answered
  is worse than an empty box, because the state line would then call
  the sheet finished. Nothing stored for a chart simply greys the
  button. Stored as `key=typed;key=typed` under a per-chart value name
  -- `LAZSTEP`'s carries the count (`CORNERSTP-3`), since a three-step
  sheet on a five-step drawing would put numbers against treads they
  were never measured on -- and a value carrying `;` or `=` is dropped
  rather than written back wrong.
- **Say what a box will take** *(done)* -- *"A box takes 24, or a
  feet-and-inches spelling - both read."* on the static hint, not the
  state line, which is carrying two jobs already. The inch mark is
  spelled rather than shown: a bare `"` would end the DCL string it
  sits in, and these files write their own `.dcl`.

## Phase 4 -- one form kit, in the library *(done)*

`LAZFORM`, `LAZSPA` and `LAZSTEP` duplicated the stroke font, the
vector-chart drawing, the arrow and label placement and the DCL
emitters, and they did it *by rule*: only `CALOFIN-LIB.lsp` may define
`cal:` symbols, and a shared tool may not define a name another shared
file defines, so borrowing `lzf:` names would make LAZSPA depend on
LAZFORM being loaded -- which it never is at the standalone tier.

The repo already had the answer to exactly this shape of problem: a
`cal:` helper in the library, a local copy in each standalone file, and
`tools/mirror_shared.py` swapping one for the other. So that is what
the kit is.

**What moved** -- verified byte-identical modulo the namespace before
a line was written, and each twin is ~150 lines shorter for it:

| | |
| --- | --- |
| the stroke font | `cal:*imgfont*` + three `cal:*imgfont-*` metrics |
| the tile palette | `cal:*imgcol-line/-back/-dim/-val/-hi*` |
| the drawing | `cal:imgglyph imgtext imgtextw imgtexth imgpline imgflatten imgarcpts` |
| the form contract | `cal:formanswer` -- STANDARDS.md's three states |
| the state lines' strings | `cal:plural`, `cal:andjoin` |

Named `img*` because that is where they draw. `cal:text` already makes
an AutoCAD TEXT entity and means something else entirely; that
collision is what the prefix exists to avoid.

**What did not move, and why.** `lzX:px`, `lzX:py` and `lzX:pline`
genuinely differ -- LAZSPA and LAZSTEP cut the chart into bands and
clip to the one being drawn, LAZFORM draws it whole -- and everything
touching `*vals*`, `*pos*`, `*chart*` or `*focus*` is per-tool STATE:
lifting `get`/`put` would give the three forms one shared answer store,
which is a footgun rather than a saving.

**Two helpers had to be made identical first**, and both are small
improvements in their own right: `lzX:trim` now trims tabs and is
nil-safe (it is `cal:trim`'s body, so a pasted value with a tab stops
being silently dropped -- which is the phase 3 complaint again), and
`lzX:boxes` became the general `lzX:plural (n one many)`, since
`cal:boxes` in a library that already has `cal:bbox-ent` would read as
a bounding box.

The swap map is the point as much as the saving: it is the written
statement that these copies **are** the same code, and
`mirror_shared.py --check` -- which `make check` runs -- fails the
build if one of them drifts.

## Phase 5 -- the palette stops drifting *(done, as far as it honestly can)*

The VB side cannot be built or run here (`Calofin.vbproj` targets net48
against the AutoCAD.NET reference assemblies), so nothing about the
palette's *behaviour* is verifiable in this repo. What **is** verifiable
is the thing that actually rotted: the two surfaces are text, and text
drifts.

It had. The palette shipped **60** of the panel's **67** -- `LAZSPA`,
`LAZSTEP`, `LINGUTTER`, `LINGUTTERSCAN`, `POOLSIDE`, `POINTRENAMER` and
`ABPCHECK` were on the panel and nowhere in the palette, and five of
those seven were missing from `calofin.lsp`'s probe list too, so their
buttons could never have greyed out. Every caption that *was* there
agreed, and no tool was in the wrong group -- which is exactly why
nobody noticed: the halves that were checked looked fine.

So `tools/check_registry.py` -- already the file that says "every tool
registered everywhere it has to be" -- grew a palette section. It reads
`CommandCatalog.Groups` out of the VB source and `calofin:*commands*`
out of the glue, and holds three things against `LAZPANEL`'s roster:

- the same commands, in the same four groups (the palette's groups
  **are** the panel's category pages),
- the same caption words for each one,
- and a probe-list name for every palette button, since without one the
  button can never grey out.

The seven gaps are closed, and the tool's summary line now counts the
palette alongside the buttons.

**What it deliberately will not do is `--fix` the VB.** A codemod that
wrote VB source would be writing code no test in this repo can run. So
the palette is checked and reported on -- with the exact
`New Entry(...)` line to paste, caption already filled in from
`lzp:*captions*` -- and left to a human.

### Phase 5a -- the catalog stops being typed *(done 2026-09-04)*

Checking the two rosters against each other closed the gap; it did not
close the *class* of gap, because the palette still carried its own
copy of the roster and a copy can always be forgotten. So it stopped
carrying one. `tools/gen_ui_data.py` writes
`ui/calofin_net/Generated/CommandCatalog.g.vb` from `lzp:*captions*`
and `lzp:*groups*`, `--check` fails when the file on disk is not what a
fresh run would write, and `check_standards.py` runs that check
alongside the mirror, the releases and the bundle -- the same contract
every other generated file in this repo is held to.

**Why this is allowed when `check_registry --fix` refuses to write VB.**
That refusal is about *decisions*: a caption is words somebody chose, a
category is a judgement about what a tool IS, and a codemod inventing
either would be writing code no test here can run. Nothing the
generator emits is a decision. Every command, caption, group and page
is transcribed from a table `test_lazpanel.py` already holds to the
tree, and the one piece of editorial text -- the tooltip -- is READ
from `ui/calofin_net/blurbs.txt`, never invented: a command with no
blurb is reported, and falls back to its caption.

Two things came with it:

- **The palette gained the job pages.** `Pages` carries the whole tab
  strip -- `Pool`, `Cover`, `Spa`, `Rest` and the four categories, with
  their columns -- because once the table is generated there is no cost
  to carrying all of it. The palette has only ever had the four
  category groups; the panel's job pages are the ones a drafter
  actually navigates by.
- **The VB is checked as code.** `tools/check_vb.py` -- blocks, quotes,
  parens, and every member and constructor arity of the assembly's own
  types. It is what makes the generated/hand-written seam safe: rename
  `CommandCatalog.Groups` and the call site in `CalofinPalette.vb`
  fails a check rather than somebody's AutoCAD. It is not a compiler
  and does not type-check, and saying so is part of the deal.

`tests/test_ui_data.py` reads the generated VB back and holds it to the
panel -- deliberately not by calling the generator, which would only
agree with itself -- and `tests/test_check_vb.py` drives the linter
against VB that is wrong on purpose.

### Phase 5b -- the palette catches up on phases 1 to 3 *(done 2026-09-04)*

The panel had gained Find, Recents and Pins; the palette was still the
flat list of grouped buttons it shipped as. It now carries all of it,
and the tab strip it never had:

- **Find** over names *and* captions, literal (`String.Contains`, for
  `lzp:instr`'s reason), top hit selected as you type, Enter runs it.
  A tool this session has not loaded is **listed** and refused with the
  reason, while a tool on a page is **greyed** -- the same deliberate
  opposition, and the same words, as the panel.
- **Recent and Pinned rows**, pinned from any button's right click, a
  row drawn only when it has something in it.
- **Every page of the strip**, job pages included, as real tabs. This
  is the one place the palette is plainly better than what it mirrors:
  DCL has no tab tile, so LAZPANEL's strip closes the page and reopens
  the next, and it blinks.

**They share one store.** `PaletteMemory` writes `lzp:*pinkey*` --
LAZPANEL's own registry key, values, `;`-joined format and cap of five
-- so a drafter has one set of pins and cannot tell which surface they
pinned from. That is the phase 5 thesis (*both surfaces, sharing a data
layer*) applied to the half that is state rather than tables.

`tests/test_palette_shell.py` holds the seam: the key, the value names,
the cap, the newest-first rule, the roster filter that stops a stale pin
drawing a dead button, and **every message the Find page can print** --
lifted out of `LAZPANEL.lsp` rather than typed, so re-wording one
surface fails until the other follows.

### Phase 5c -- the chart tables stop being written twice *(done 2026-09-04)*

The open item below said the JSON field maps and `lzf:*charts*` are the
same knowledge written twice, that the JSON positions are seeded
estimates, and that generating them was blocked because nothing here
could look at the result.

The premise was the photograph. While the palette drew a **picture** of
a chart, every box needed a fraction of that picture to sit at, and no
generator can check by eye whether a fraction lands on a letter. Draw
the chart from the **vectors** instead and the question disappears: a
box belongs at the midpoint of the dimension line, in the chart's own
co-ordinates, and there is nothing left to nudge.

So `tools/gen_ui_charts.py` writes `Generated/ChartCatalog.g.vb` from
`lzf:*charts*`, `lzs:*charts*` and `lzt:chart` -- read through
`tests/lispvm.py`, so what is emitted is what the routine itself reads.
13 pool sheets, 3 spa sheets, and 24 step sheets, because LAZSTEP builds
its chart from the count rather than keeping a table and the generator
asked it for every count the dialog accepts.

**Arcs are flattened by the Lisp's own `lzX:flatten`** before they are
written. The palette therefore has no arc arithmetic at all and cannot
round an oval a different way from the panel -- and
`tests/test_ui_charts.py` compares every point of every outline, which
is the check that would catch a re-implementation creeping back in.

What is NOT generated is as deliberate: `lzf:dead`, the cross-dim mode
dropdowns, `lzf:picks` and the corner tables are RULES, and a second
copy of a rule is the drift being closed. A palette form sends what was
typed and lets the routine ask for the rest -- which is what the wire
has always promised.

### Phase 5d -- the palette stops reading measurements *(done 2026-09-04)*

Found while building the form kit, and worse than a missing feature.

The palette parsed a box itself, in VB, with `Double.TryParse`. That
takes a plain decimal and nothing else -- so `6'-3"`, a spelling the DCL
charts read perfectly and whose hint tells the drafter to use it,
produced no number. The pair then went out as `(key . nil)`.

**That is not "ask me".** `nil` is NA. The measurement travelled as *not
taken*, the routine never asked, and the sheet looked answered. It is
phase 3's own failure -- a box silently dropped while the form shows
what was typed -- reappearing on the other surface, where phase 3 never
reached.

So the reading moved to Lisp. `ui/calofin_ui/calofin.lsp`, until now
only a probe list, carries the wire:

```
(calofin:run "spa:run-with-answers" '(literals) '(measures))
```

A **literal** travels as written -- a shape word, a keyword answer, a
point -- and a **measure** is typed text, read by `calofin:answer`,
which is `cal:formanswer`'s body: the same reader, and therefore the
same four states, as the charts. `distof` is AutoCAD's own and knows
every feet-and-inches spelling there is; nothing should be re-deriving
that in another language, which is exactly what the palette was doing.

`LispBridge` has no numeric pair helper left, on purpose: a second way
to send a measurement is a second parser to keep in step.

`tests/test_palette_wire.py` drives it in the VM -- all four states, the
literal/measure split, and `calofin:unreadable` naming exactly the keys
the wire drops, since the state line prints that list and a state line
that disagrees with the wire is a lie. It also holds the two copied
helpers to `CALOFIN-LIB.lsp`'s, body for body.

### Phase 5e -- the palette gets a real chart form *(done 2026-09-04)*

`ChartFormView.vb`: `LAZFORM`'s sheet on the palette, and the first
place the generated geometry earns its keep.

- **Drawn, not photographed.** `ChartSheet` renders ChartCatalog's
  polylines and puts a box at the midpoint of each dimension line. No
  box has a position of its own, so there is nothing left to nudge --
  which is what closed phase 5c's blocked item rather than solving it.
- **The state line**, phase 3's feature, on this surface for the first
  time: a box that will not read is named by the LETTER the sheet
  prints and holds Draw back; otherwise the line is the hand-off. It
  **asks the wire** (`calofin:unreadable-str`) rather than deciding, for
  the phase 5d reason -- the palette cannot read a measurement any more,
  and a line that named a box the wire would accept is worse than none.
- **Recall last**, into the empty boxes only, never a default, from the
  DCL forms' own store -- same registry keys, same format -- so a sheet
  filled in on LAZFORM comes back here.

One class serves any chart table, which is phase 4's "one form kit"
arriving on this surface: the sheet list, the entry point and the recall
key are constructor arguments.

`tests/test_chart_form.py` holds every seam to the file it must agree
with, and was verified to bite by sending the chart's key where the
shape word belongs and by moving the recall key.

### Phase 5f -- the step sheet, and the one rule worth mirroring *(done)*

`StepFormView.vb`. A flight has no fixed chart -- the sheet IS the count
-- so the catalog carries one per routine per count and the palette
offers exactly those counts, because past `lzt:*max-steps*` LAZSTEP
will not draw at all. State line, Recall and the wire come from the
shared `FormWire` kit; the recall slot carries the count as well as the
routine, which is `lzt:recall-slot`'s own rule.

The rule that could NOT be left to the wire, and the only one mirrored
into the palette: **`NA` at a tread counts as an empty box.** `NA` ends
a run, so a tread answered `NA` would stop the flight short of the count
that built the drawing in front of you -- the sheet showing four steps
and the routine drawing three. It is mirrored rather than generated
because it is a rule, and `tests/test_chart_form.py` holds both halves
to `lzt:treadkey` and to `lzt:form`'s own statement of why.

It also puts the last of the generated geometry to work: before this,
24 step sheets sat in `ChartCatalog` that nothing read.

### Phase 5g -- the spa sheet, and the last photograph *(done 2026-09-04)*

`SpaChartView.vb` replaces `SpaFormView.vb`, and the generator carries
the four LAZSPA tables that are not the chart: `lzs:*corners*` for the
corner rows, `lzs:*second*` for the other outline's overalls (keys that
are per shape), `lzs:*lists*` for the six dropdowns and `lzs:*ctreat*`
for the treatments, plus the cover lap lifted out of the dialog builder
where it is a box rather than a table row.

They are kept BESIDE `Chart` rather than folded into it. LAZFORM has a
corner table too and it is a different shape -- four slots, with
collective questions covering several corners at once -- so one
structure for both would be a lie about one of them.

**The corner dropdown speaks the sheet legend** (`90` / `Radius` /
`Diagonal`) and sends those words as written; SPA normalises them onto
the canonical set itself, and a palette that translated would be a
second opinion about a rename the routine already handles. A size
travels only when the treatment takes one -- `lzs:cornerpairs`' rule.

**The last photograph on this surface is the pool bottom.**
`assets/shapes/` and its `fieldmap.json` -- twelve crops and the
"seeded estimates" the README admitted to -- are deleted, because the
sheet is drawn now and a box needs no fraction. `assets/bottoms/` stays,
because `PoolFormView` is still a picture of a section.

`tests/test_spa_form.py` sections 14 and 15 read the generated catalog
where they read the JSON and the view model, and section 15's question
changed with them: not "do two copies agree" but "did the generator
carry every table". Same three counts as before -- 19, 17 and 11 -- which
is the point.

### Phase 5h -- the pool sheet's other questions *(done 2026-09-04)*

The pool chart form asked for measurements and nothing else. It now
asks what `LAZFORM` asks: the in-square toggle (a KEYWORD to POOL, not
a yes/no), the bottom type from `lzf:*btypes*`, the mode dropdowns from
`lzf:*picks*` -- placed by that table's own `section` word -- the cross
dims from `lzf:*cross*`, and the corner rows from `lzf:*corners*`.

Two rules came with them, and both are data rather than logic once the
table is carried properly:

- **The cross dims are not asked in square.** A cross dim is a tape run
  corner to corner and it is what tells POOL how far OUT of square the
  pool is. `lzf:*picks*` says so itself by tying the mode dropdown to
  that section.
- **A corner row is not always one corner.** In square one row answers
  a collective key covering all four and its siblings answer nothing;
  out of square each is asked for itself. So the row carries TWO target
  lists, the toggle picks which, the answer is fanned out to every
  target, and a size rides under the TARGET's key rather than the row's
  -- `lzf:cornerpairs`, transcribed rather than re-derived.

That last one is why the pool corner table is kept apart from the spa
one in `ChartCatalog`: a spa corner row is one corner and nothing else,
and a single structure for both would be a lie about the pool.

**Not there yet**, and named rather than left to be discovered: the
step form offers the chart's boxes but not `lzt:asks`' dropdowns and
counters, which stay command-line questions; `lzf:*oaslive*` is not
carried, so an OASIS sheet shows every box it has rather than the ones
its `sub` dropdown makes live; and `lzf:dead` lives only in Lisp, so a
form shows every box its sheet has and lets the routine ignore what
this page does not ask about. **The pool-bottom tab stays a
photograph on purpose** -- the chart tab asks for the same depths and
the same `btype`, but it cannot show you a SECTION, and choosing a
bottom is the moment you want to look at one.

Still open, and genuinely blocked on a machine with a compiler:

- **The chart tables.** *(closed by phase 5c, by dropping the premise:
  the geometry is generated and the palette draws it, so there are no
  fractions left to land wrongly.* The paragraph below is kept because
  it is the argument that had to be answered.) `assets/*/fieldmap.json`
  and `lzf:*charts*` are the same knowledge written twice, and the
  READMEs already admit the JSON positions are "seeded estimates". The
  Lisp tables are the ones under test, so the JSON should be generated
  from them -- but nothing here can look at the result, and a generated
  field map that lands the boxes in the wrong place is worse than seeded
  estimates somebody nudged by eye. **The half that does not need eyes is now checked**:
  `tests/test_spa_form.py` section 15 holds `LAZSPA`'s charts against
  the palette's whole surface -- the map AND the VB literals, since the
  cover block never appears in the JSON -- so a question one form can
  answer and the other cannot fails the suite. The positions still want
  a human with the artwork in front of them; the KEYS no longer do.
- **Everything behavioural.** Whoever next opens AutoCAD with a build
  should run the spa form once with a `NotGiven` corner and confirm the
  `?` mark lands, per `ui/PLAN.md` -- and now also type `6'-3"` into a
  box, which the palette could not read until phase 5d and can.

## After the plan: what nothing was checking

The five phases added roughly 1,240 `action_tile` callbacks across 37
DCL pages, and **a DCL callback is a string**. Nothing checks a string.
Rename the helper one calls and the file still loads, every other suite
still passes, and the tile is dead until somebody clicks it -- which on
a page with sixty tiles may be weeks. The suites that drive those pages
only ever evaluate the handful each scenario clicks.

`tests/test_dialog_actions.py` opens every page of all four tools with
the dialog surface stubbed and **evaluates every expression
action_tile was handed**, under each `$reason` DCL can deliver (a
callback may read it -- LAZPANEL's list box runs a tool on a double
click and only on a double click).

It asserts nothing about what a callback *does*; that is the business
of the tool's own suite, which knows what the click should achieve.
This one asserts only that every expression is something the VM can run
at all: no typo'd name, no missing paren, no helper moved out from
under a call site. It runs at both tiers, which is where it earns most
-- the grouped build rewrites these strings through the swap map, so a
call site the mirror fails to translate shows up here rather than in
somebody's AutoCAD.

All 1,240 pass. The suite is the deliverable, not the result: it was
verified to bite by renaming one helper a callback names, which failed
13 pages at once.

## The order, and why

1. **Find** -- biggest single win, self-contained, testable end to end. *(done)*
2. **Form validation and the hand-off preview** -- the next thing that
   costs real time, and the one with the highest ratio of relief to
   risk. *(done)*
3. **Recents** -- small, and better judged once Find has been used.
   *(done)*
4. **The form kit** -- structural; it is what makes phase 3 cheap to
   repeat and any new form possible at all. *(done)*
5. **The palette's data layer** -- last, because it is the only part
   this environment cannot prove. *(done to that boundary: the rosters
   are checked, the behaviour is not.)*

Page consolidation sits outside the numbering on purpose: it is an
editorial call about how people navigate, and it should be made from
use rather than from argument.
