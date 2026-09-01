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

- **Recents.** The registry path is already proven by pins
  (`lzp:*pinkey*`). Keep the last N launched commands and put them on a
  `Recent` row above `Pinned`. Pins stay hand-picked; recents cost
  nothing to maintain and are what you actually want most mornings.
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

## Phase 3 -- the forms stop finding out too late

Everything here is inside DCL's ceiling.

- **Validate on the way out of a box.** The chart is already redrawn
  when a box loses focus, so the work is done: parse what was typed,
  and if it will not do, draw that letter in the error colour, put the
  reason on a message line and grey `Insert` until it is fixed. Today
  the same bad number is found by `POOL` after the dialog is gone.
- **Say what will still be asked.** `lzf:dead` and `lzf:form` already
  know exactly which keys are being sent and which are being withheld;
  the routines' own question lists are already pinned by the form
  tests. So the form can end with *"POOL will still ask: 3 dimensions,
  the base point"* -- which is the difference between a finished sheet
  and one you only think is finished.
- **`Recall last`, as a button and never as a default.** Per chart, in
  the registry. Pre-filling silently would put the last pool's numbers
  on this pool, which is worse than typing them.
- **Say what a box will take.** `24` and `2'6"` both work and nothing
  on screen says so.

## Phase 4 -- one form kit, in the library

`LAZFORM`, `LAZSPA` and `LAZSTEP` duplicate the stroke font, the
vector-chart drawing, the arrow and label placement and the DCL
emitters, and they do it *by rule*: only `CALOFIN-LIB.lsp` may define
`cal:` symbols, and a shared tool may not define a name another shared
file defines, so borrowing `lzf:` names would make LAZSPA depend on
LAZFORM being loaded -- which it never is at the standalone tier.

The repo already has the answer to exactly this shape of problem: a
`cal:` helper in the library, a local copy in each standalone file, and
`tools/mirror_shared.py` swapping one for the other. So: a `cal:form-*`
kit in `CALOFIN-LIB.lsp` (font, glyph, `pline`, `arrow`, `label`,
`text`, the px/py mapping, the answer store, the three-state wire).
Each form keeps its own charts and its own idea of what is dead -- that
is the part that is genuinely per-tool -- and stops carrying its own
copy of the engine.

No visible change on its own. What it buys is the next form costing a
chart table instead of 1,500 lines, which is the only way the remaining
62 commands ever get one.

## Phase 5 -- the palette stops drifting

The VB.NET side cannot be built or run in this environment
(`Calofin.vbproj` targets net48 against the AutoCAD.NET reference
assemblies), so nothing here is verifiable until someone opens AutoCAD
with a build. What *is* verifiable here is the data both surfaces read:

- **The roster and captions.** `LAZPANEL` has all 67 with captions;
  `calofin_net`'s `CommandsTab` has its original set. One table, read
  by both -- generated for the VB side out of `lzp:*captions*` the way
  `tools/check_registry.py` already computes every count in the prose.
- **The chart tables.** `assets/*/fieldmap.json` and `lzf:*charts*` are
  the same knowledge written twice, and the READMEs already admit the
  JSON positions are "seeded estimates". The Lisp tables are the ones
  under test.
- **Then the palette's own gaps**, in the order `ui/PLAN.md` left them:
  the button catalog, and generalising the form hook into `cal:`.

## The order, and why

1. **Find** -- biggest single win, self-contained, testable end to end. *(done)*
2. **Form validation and the hand-off preview** -- the next thing that
   costs real time, and the one with the highest ratio of relief to risk.
3. **Recents** -- small, and better judged once Find has been used.
4. **The form kit** -- structural; it is what makes phase 3 cheap to
   repeat and any new form possible at all.
5. **The palette's data layer** -- last, because it is the only part
   this environment cannot prove.

Page consolidation sits outside the numbering on purpose: it is an
editorial call about how people navigate, and it should be made from
use rather than from argument.
