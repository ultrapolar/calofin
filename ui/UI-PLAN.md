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
| **The palette has drifted** | `calofin_net/` still shows its original button set; `LAZPANEL` covers all 67 |

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

Still open, and genuinely blocked on a machine with a compiler:

- **The chart tables.** `assets/*/fieldmap.json` and `lzf:*charts*` are
  the same knowledge written twice, and the READMEs already admit the
  JSON positions are "seeded estimates". The Lisp tables are the ones
  under test, so the JSON should be generated from them -- but nothing
  here can look at the result, and a generated field map that lands the
  boxes in the wrong place is worse than seeded estimates somebody
  nudged by eye. **The half that does not need eyes is now checked**:
  `tests/test_spa_form.py` section 15 holds `LAZSPA`'s charts against
  the palette's whole surface -- the map AND the VB literals, since the
  cover block never appears in the JSON -- so a question one form can
  answer and the other cannot fails the suite. The positions still want
  a human with the artwork in front of them; the KEYS no longer do.
- **Everything behavioural.** Whoever next opens AutoCAD with a build
  should run the spa form once with a `NotGiven` corner and confirm the
  `?` mark lands, per `ui/PLAN.md`.

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
