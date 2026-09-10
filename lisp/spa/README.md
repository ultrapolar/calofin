# SPA.LSP — spa / hot-tub template layout

AutoLISP command that draws a spa outline from field measurements, built
from the same bones as `POOL.LSP` but cut down to what a spa template
needs.

Load it (`APPLOAD`, or drag the file into the drawing) and type **`SPA`**.
New to it? Load `TUTORIALSPA.LSP` too and type **`TUTORIALSPA`**.

## The two file names

Every lisp here ships **twice, byte-identical, under two names**:

| | |
| --- | --- |
| `SPA.LSP` | the static name — the one in your `APPLOAD` stack |
| `SPA_082726_REV06.LSP` | the same file, named `MMDDYY_REV##` for its revision |
| `TUTORIALSPA.LSP` / `TUTORIALSPA_082126_REV05.LSP` | likewise |

The static name never changes, so an existing autoload keeps working. The
versioned name tells you at a glance which revision is sitting in someone
else's stack. And because the two are identical, **the version string
travels inside both** — so a session that loaded the static name can
still tell you what it is:

```
Command: SPAVER
SPA 082726 REV06
Tutorial: 082126 REV05
```

Cut a new release with:

```
python3 tools/release.py              # today's date, next revision
python3 tools/release.py --rev 3      # force REV03
python3 tools/release.py --check      # verify, change nothing
```

`--check` catches the three ways this goes wrong: the pair drifting
apart, more than one versioned copy lying around, and a file whose
version string does not match its own filename. Only one versioned copy
is kept per lisp — git history is the archive.

## Tutorial

`TUTORIALSPA` (needs `SPA.LSP` loaded) offers:

* **Checklist** — every question SPA asks in order, every decision it
  makes for you, every check it runs, and what it draws on which layer.
  Written to the text window, and optionally placed in the drawing as a
  reference sheet you can plot.
* **Demo** — draws a worked 140 × 110 cover a step at a time, explaining
  each step *before* it appears: outline, overalls, flats, corner
  callouts, water's edge, overlap, hinges, report. Nothing is asked for;
  the measurements are canned. Enter advances, `X` stops.
* **Both** — the checklist, then the demo.

The demo drives SPA's own drawing functions, so what it shows is what
SPA actually does. Only the *order* of the steps is duplicated — if the
flow in `SPA.LSP` changes, walk `TUTORIALSPA.LSP` through with it.

## Shapes

| Shape | What it asks for |
| --- | --- |
| **Rectangle** | overall width (A‑B), then the length (A‑D) — **the width is offered back**, so Enter makes it square — then the corners, once for all four or one at a time |
| **Octagon** | overalls **B** across and **A** up, then the cut **face S2**, then **T / S / S1 / V** (any of them may be `NA`) |
| **Round** | **one measurement** — the diameter. Type `O` at it for an out-of-round spa and the two axes are asked instead |

Corner naming, plan view:

```
Rectangle          Octagon
D --------- C          F --------- E
|           |         /             \
|           |        G               D
A --------- B        |               |
                     H               C
                      \             /
                       A --------- B
```

## Thermo-Light

Thermo-Light is a special case on two counts, so the **Spa Cover Details
block is read first**, before anything else is asked:

* **Water's edge = cover size.** They are the same thing on a
  Thermo-Light cover, so the water's-edge question is not asked at all —
  the drawing is made as `Cover Size` — and the offer to add the other
  outline is skipped, since there is no other outline.
* **Every hinge is velcro.** There is no dashed fold hinge; all hinges
  are ByLayer lines labelled `Velcro Hinge`, matching the hardware chart
  ("Velcro Hinges: Always").

Both are noted under the report table. Skipping the block up front just
defers it to the hinge pass, where it is asked for again — but then a
Thermo-Light grade arrives too late for the two rules above.

## Water's edge vs cover size

Except on Thermo-Light, the first question is which one is being drawn, and it decides both the
layer and the dimension text:

| Answer | Perimeter | Overall dimension reads |
| --- | --- | --- |
| `Watersedge` | **dashed**, on layer `POOL` | `<measurement>` over `Water's Edge` |
| `Coversize` | solid, on layer `COVER` | `<measurement>` over `Cover Size` |

The note is stacked **under** the measurement, across the dimension line,
the way the order sheet draws it:

```
        95"
  |--------------|
     Cover Size
```

It goes on the **overalls only**. Corner callouts (radii, cut faces) and
the inboard flat dims are left plain, so a corner or a segment note can
never be mistaken for an overall.

The mode is also written under the drawing (`SPA OUTLINE DRAWN AT
WATER'S EDGE`) and in the report table's title.

## Drawing both outlines

Once the first outline is drawn the command offers to add the other one,
either way round. **The cover is always the larger of the two**, which is
what settles the direction of travel:

| Method | What it asks | What it does |
| --- | --- | --- |
| `Offset` | how far the cover laps the water's edge | offsets **outward** if the water's edge was drawn first, **inward** if the cover was |
| `Dims` | the other outline as measured | draws the two **concentric** |

Offsetting is a true parallel offset, so the corners move with it: a
radius grows and shrinks with the offset, a diagonal cut face by
`g × (2√2 − 2)`, and a treatment offset away to nothing falls back to a
`Square` corner. By dims, the corner sizes are *offered* at whatever the
implied lap works out to — Enter walks straight through when the second
outline really is a parallel offset, and a corner measured differently
can be typed over.

With both drawn, the **cover's** overalls go outside and the **water's
edge's** go a third of the way **into** the water's edge — see below. One
more dimension at the **bottom** gives the **overlap**: how far the cover
laps the water's edge. Both outlines end up in the report table.

## Dimension styles

| Outline | Style |
| --- | --- |
| Cover size | `STANDARD INCHES` |
| Water's edge | `STANDARD INCHES 0.5` |

A style the drawing already defines is **used exactly as it stands** —
the office template wins. A missing one is built from the standard-inches
settings below, the water's edge at `spa:*wefactor*` (0.5) of the normal
furniture size. The drawing's own current style is put back when the
command finishes.

## Rectangle corners

The corners open with one gate:

```
Are all four corners the same? [Yes/No] <Yes>:
```

Most covers say one thing about all four, so `Yes` is the default and it
buys **one round of questions** — asked of `the four corners`, applied to
every one of them. `No` walks `Corner A`, `Corner B`, `Corner C` and
`Corner D` one at a time, which is how a cover with two cut corners and
two square ones is given.

Either way the question itself is the repo's canonical **Treatment**
question (STANDARDS.md section 2): `How should the four corners be
treated? [Square/Radius/Cut/NotGiven]` — `Square` (a true 90), `Radius`
(sized by its radius), `Cut` (a straight diagonal, sized by its face
length) or `NotGiven` (nothing on the order sheet: drawn square and
flagged). The pre-standard words still work typed in full — `90`,
`ROUNDED`, `DIAG` / `DIAGONAL`, `NG` — and are normalised as they are
read; the palette's old wire values are accepted the same way.

Asked one at a time, **corner A's answer autofills B, C and D** — press
Enter at each of them to accept it, or type a different treatment for
that corner. Side lengths are always measured to the *true* (sharp)
corner; the treatment cuts inward from there, and a treatment too big
for its walls is re‑asked.

`Back` at the gate leaves the corner stage for the overalls; `Back` at
the round, or at corner A, re‑asks the gate.

Callouts sit outside the corner on its 45° line: a radius dimension on a
`Radius` corner (`R12"`), an aligned dimension across a `Cut` face
(`21"`), a circled corner point with a `90°` leader on a `Square`
corner, and the same circled point with a `?` leader plus a `Not Given`
note on a `NotGiven` one — the sheet shows the treatment was never
recorded rather than silently claiming a 90.

## Going back a step

SPA follows the repo-wide convention: **Back** (`B`), with **Undo**
(`U`) as an unlisted synonym, is offered at every prompt that has a
previous question to return to, and is always shown in the prompt's
brackets. Backing out of a measurement stage re-asks that stage from
its first question.

Two places worth knowing:

* The **three questions before any measuring** — the drawing mode
  (water's edge or cover size), the spa shape, and the insertion base
  point — are one chain like the rest. The shape is the one that shapes
  every question after it, so `Back` at the base point re-asks it and
  `Back` at the shape re-asks the mode. Thermo-Light settles the mode
  without asking, so on the way back that step is stepped over rather
  than stopped on.
* The **spillaway loop** commits as it goes, so Back at the top of it
  *removes the spillaway just committed* — and with it the no-go zone
  and the report row it would have made — before re-asking
  (`Stepping back one spillaway.` / `Already at the first spillaway.`).
* The **taper** prompt is a `getstring`, which cannot take keywords, so
  there Back is typed like a value — `B`, `BACK`, `U` or `UNDO`, any
  case — and the prompt says so.

Back cannot cross a point where geometry was committed: once an outline
is drawn, the offer to add the other one is a fresh first question. That
is the same boundary `POOL` has.

## Form answers

A form — the LAZFORM dialog, or the VB palette — can answer some or all
of SPA's questions before the run starts. It leaves them in `spa:*form*`
as an alist of `(key . value)` and the ask helpers look there first, so
a filled-in sheet drives the whole run and a half-filled one simply
shortens it. `(spa:run-with-answers answers)` sets the store, runs
`SPA`, and clears it; setting `spa:*form*` and calling `SPA` directly
does the same. This is the store `POOL` carries, under the same rules.

Three states, and the difference between the last two is the feature:

| In the form | In the store | SPA does |
| --- | --- | --- |
| left empty | key absent | asks, as usual |
| explicitly cleared | `(key . nil)` | takes `NA` without prompting |
| filled | `(key . 84.0)` | takes the value without prompting |

**An answer is removed from the store as it is used** — consume-once.
That is what keeps `Back` working (stepping back onto a form-answered
question prompts at the keyboard instead of the store instantly
re-answering it and walking forward again) and what stops a rejected
value — a corner size too big for its walls — being re-fed forever: the
re-ask finds the store empty and takes the correction from the
keyboard. An answer a question would not accept is consumed and then
ignored, so the run falls back to asking exactly as if the box had been
left empty. The store is cleared on **both** exits of `SPA`, the error
handler included, so a form can never leak into the next command-line
run.

The key roster:

| Key(s) | Question |
| --- | --- |
| `mode` | `Watersedge` / `Coversize` |
| `shape` | `Rectangle` / `OCtagon` / `ROund` — exact spelling |
| `base` | insertion base point, as a plain list: `(base 0.0 0.0)` |
| `w`, `l` | rectangle overall width / length |
| `samecorners` | `Yes` / `No` — are all four corners the same? A form that names no corner but `cornera` is still asked this at the keyboard; one that fills in any of `cornerb`/`cornerc`/`cornerd` has said `No` by doing so, and is not asked unless it sent this key too — an explicit answer always wins |
| `cornera-ty` … `cornerd-ty` | corner treatment: `Radius` / `Diagonal` / `90` (`Square` accepted as the synonym for `90`, exactly as at the prompt). With `samecorners` = `Yes`, **corner A's pair answers the one round** and B, C and D take it |
| `cornera-sz` … `cornerd-sz` | the radius or cut face length for a sized treatment; `90` needs none |
| `b`, `a` | octagon / round overalls. Round: a stored numeric `b` alone **is the diameter**; storing `a` as well takes the out-of-round path, exactly as typing `O` would |
| `s2`, `tt`, `ss`, `s1`, `vv` | the octagon's cut face and flat letters (any may be an explicit nil = `NA`) |
| `second` | `Yes` / `No` — draw the other outline as well |
| `method` | `Offset` / `Dims` — where the other outline comes from |
| `gap` | how far the cover laps the water's edge |
| `w2`, `l2` | the second outline by dims, rectangle |
| `b2`, `a2`, `f2` | the second outline by dims, octagon (`f2` the cut face); the round one takes `b2`, `a2` |
| `autohinge` | `Yes` / `No` — auto-hinge the cover |
| `grade`, `taper` | the Spa Cover Details values, normalised exactly as the block's tags are — a form grade of Thermo-Light engages the Thermo-Light rules just like the block, and a form answer wins over a block picked in the drawing |

Two prompts stay interactive by design: the **Spa Cover Details block
pick** (an `entsel` — the block is in the drawing, there is nothing for
a form to type) and the **spillaway loop**. `tests/test_spa_form.py`
proves the equivalence — the same spa from the prompts and from a form
— at both tiers.

## Orientation

**The long overall always runs west to east**, whichever order the two
were typed in. If the length comes in bigger than the width the cover is
drawn a quarter turn over, and the corner treatments and their letters
travel round with it — the corner the user called `B` lands bottom-left
and is still labelled `B`, so the drawing reads back against the report
table. The turn is announced at the command line and noted under the
drawing.

The turn is clockwise, and it carries every wall and corner round with
the shape:

| as measured | drawn |
| --- | --- |
| bottom wall | left wall |
| right wall | bottom wall |
| top wall | right wall |
| left wall | top wall |
| `A` (bottom-left) | top-left |
| `B` (bottom-right) | bottom-left |
| `C` (top-right) | bottom-right |
| `D` (top-left) | top-right |

### Turning to clear a spillway

Hinges run north-south, so a spillway on the **top or the bottom** wall
stands in the way of every one of them — while the same spillway on a
**left or right** wall cannot touch any. A quarter turn moves it there.

So when the cover laid out the way the long-overall rule wants cannot
get a hinge clear of a spillway and the other way round can, **the
spillway wins and the spa is turned**. Both ways round are scored on the
same three things the hinge layout itself is scored on — dodging every
zone (4), fitting the foam length (2), an acceptable piece count (1) —
so the turn is never taken to clear a zone at the price of a hinge that
overruns the foam, and a tie always leaves the long overall running
across. The drawing says which way it went and why:

```
TURNED A QUARTER TURN - HINGES CLEAR OF THE SPILLWAY
```

and the spillway's report row is named as it was **measured**, with
where it ended up added: `SPILLWAY TOP WALL (DRAWN RIGHT)`.

This is why the hinge questions are asked **before anything is drawn**
(see [Auto-hinge](#auto-hinge)): nothing already on the screen can be
turned.

## The mini-model

The corner letters are **not** written on the drawing. They go on a
small copy of the outline beside the report table — the same move
`POOL` made — so the drawing itself carries nothing but its geometry and
its dimensions, and the report's rows (`OVERALL ACROSS (A-B)`,
`CORNER C RADIUS`) still read back against a picture of the shape.

The mini-model is drawn to the right of the report box, at a fixed fit
size (`spa:*map-gap*` and `spa:*map-size*` in the tunables), with the
corner treatments in place: a radius corner is an arc on it, a cut is
its face. It lives on `SPA-NOTES` with the rest of the annotation, so
freezing that layer takes it away with the report. A round spa has no
corners, so its mini-model carries no letters — it is still drawn, to
say which way round the spa lies.

## Where the dimensions go

The **cover's** overalls go outside it: the across dim **2 ft above**,
the up dim **3 ft to the left**. A lone outline — whichever it is — is
dimensioned the same way.

When both outlines are drawn, the **water's edge's** overalls go a third
of the way **into** the water's edge: the across dim a third up from its
bottom, the up dim a third in from its left. Both are hooked to points
that sit on the dimension line itself, so the arrows land on the outline
instead of trailing extension lines across the cover.

All dimension text is **centred** on its dimension line as normal.

```lisp
(setq spa:*dimoff*    36.0)   ; 3 ft: cover -> the LEFT overall dim
(setq spa:*topoff*    24.0)   ; 2 ft: cover -> the TOP overall dim
(setq spa:*flatoff*   18.0)   ; outline -> the inboard flat dims
(setq spa:*insetfrac* 0.3333) ; water's edge dims, a third of the way in
(setq spa:*lapoff*    14.0)   ; how far under the cover the lap note sits
```

Corner callouts stay near their corner, scaled to the cover. The water's
edge's flats and corner callouts are still placed relative to its own
outline, so they can land on top of the cover — nudge those by hand.

A round spa is the one exception to the inset rule: its overalls have to
run through the centre to be diameters, so the water's edge pair sits on
the centre lines.

The overall **across** goes on the **top** and the overall **up** on the
**left**, on every shape. What else appears depends on the corners:

**All four corners identical** — the two overalls plus **one** corner
callout with a `Typ.` suffix, at the bottom-right. That is the whole
drawing for an all-radius or all-cut cover, and for a true square
octagon — and, per the standard, an all-`Square` rectangle now gets its
one `90° Typ.` mark too (it used to get no corner note at all).

**Corners not identical** — every corner is called out on its own (no
`Typ.`): each cut with its dimension, each `Square` with its own `90°`
mark, each `NotGiven` with its own `?` mark and note, and every side a
cut has **shortened** also gets its remaining **flat** dimensioned,
inboard of the overalls. So a cover with one cut at the top-right reads:
overall across, overall up, the top flat, the right flat, the cut face,
and a `90°` mark on each square corner.

The round spa takes one overall; only an out-of-round one gets the
second. An octagon whose eight sides come out unequal picks up the bottom
and right flats the same way the rectangle does.

## Bounded outlines

The cover and the water's edge are each drawn as **one closed
`LWPOLYLINE`**, not a scatter of separate lines and arcs. So either
outline picks in a single click, encloses a real area, and can be
offset, hatched, or handed straight to the tools that expect a
highlighted perimeter (`STOCKCOVER`, `PADDLE`, `AUTOBEAD`).

A radius corner becomes a true arc segment of that polyline, carried as
a bulge — `tan(θ/4)`, which for a square corner's quarter-turn fillet is
`0.41421`. A round spa was already a single `CIRCLE` (or `ELLIPSE` when
out of round), so it was bounded to begin with.

A bulge is not an entity, though, and `DIMRADIUS` will not take one
handed to it as an entity name — it answers *“Object selected is not a
circle or arc”* however exactly the pick point sits on the curve. So the
radius callout builds the arc it asks for from the corner's own three
points, dimensions that, and erases it again. The outline stays one
bounded entity and the callout is a real radius dimension; the only
thing given up is associativity, since the arc it was measured against
is gone by the time you see it.

## Millimetres

Any measurement may be typed **in millimetres by putting the unit on the
number** — `600mm`, `1524 MM`, `76.2mm` — and it is converted to inches
(÷ 25.4). This works at every distance prompt: the guided measurements,
the corner sizes, the lap, the spillaway lengths.

Inches and architectural input are unchanged (`84`, `6'10-1/2"`), and
object snaps stay live, so a distance can still be **picked** off
existing geometry rather than typed. That combination is what
`initget`'s bit 128 buys: a value `getdist` understands still comes back
as a number, and anything else comes back as raw text for the mm parser
to look at. Text that is neither re-asks rather than slipping through.

## Standard inches

Every dimension is written in standard inches and placed **outside** the
shape, no matter how the host drawing is set up. The dimension variables
are set for the duration of the command and restored afterwards; each
dimension keeps the settings as its own style override, so the numbers
stay in inches once the command is done.

Defaults (the first group of the `tunables` block at the
top of the file — see **Tunables** below):

```lisp
(setq spa:*dimlunit* 5)     ; 5 = fractional inches (39 3/8), 2 = decimal (39.375)
(setq spa:*dimprec*  3)     ; 5 -> 1/8", 2 -> 3 decimal places
(setq spa:*dimpost*  "\"")  ; the inch mark appended to every measurement
```

Fractions are stacked (`39 3/8"`, `80 1/8"`, `65 1/4"`) to match the
sheet.

Input is a separate matter: measurements may be typed as `6'10"`,
`6'-10-1/2"` or plain inches (`82.5`) — the routine puts the drawing into
architectural units while it is prompting.

## Layers

| Layer | Contents |
| --- | --- |
| `POOL` | the outline at water's edge (dashed) |
| `COVER` | the outline at cover size |
| `DIMENSION` | every dimension |
| `SPA-NOTES` | the mini-model and its corner letters, the mode note, the report table, and the grey input guide |
| `TEXT` | the `Hinge` / `Velcro Hinge` labels |

## While it is asking

A grey nominal spa is drawn as soon as the shape is picked, and the
element being measured turns **red** while its prompt is up. On the
octagon and the round spa the field‑sheet ties (`B`, `A`, `T`, `S`, `S1`,
`V`, `S2`) are drawn and lit the same way. The guide deletes itself once
every measurement is in.

`Back` at any prompt after the first re‑asks the previous question, right
back across the corner questions into the side lengths.

## Report table

A target / actual / delta table is written to the right of the drawing.
For the rectangle and the round spa the shape is built exactly to the
measurements, so the table is a record of what was entered. For the
octagon it earns its keep: the cut letters have to close against the
overalls (`S + T + S = B`, `S1 + V + S1 = A`), and a letter that does not
fit is adjusted, flagged red, and noted under the table.

The octagon's cut is normally measured as its **face** (`S2`) — the tape
run a crew actually takes across the corner — so that is asked first and
resolves to equal legs (`S = S1 = S2 / √2`). Leaving even `S2` as `NA`
falls back to a true square octagon sized off `A` and `B` alone — 45°
cuts, all eight sides equal.

## Auto-hinge

The command asks **"Auto-hinge the cover?"** as soon as the spa is
measured — **before a line is drawn**. That is deliberate: the answers
below can still turn the spa a quarter turn to get a hinge clear of a
spillway (see [Orientation](#orientation)), and nothing already on the
screen can be turned. The hinges themselves are drawn at the end, on
whichever outline they belong to.

Hinges run north-south, splitting the cover into side-by-side pieces
along its west-east length.

**1. Spillaways** — places a hinge cannot go, asked in a loop that always
defaults to `No`:

* `Corner` — pick the corner, give the length from the (hypotenuse)
  corner to keep clear; it blocks that far along both walls of the angle.
* `Wall` — give the spillaway's overall length; it is assumed centred on
  its wall. A left/right wall spillaway cannot meet a north-south hinge,
  so it is recorded but blocks nothing.

Both are answered against the spa **as measured**; the turn, if one is
taken, is applied afterwards when the zones are worked out.

**2. Grade and taper** — from the "Spa Cover Details" block read at the
start, or asked for here if that was skipped. The `GRADE` and
`TAPER` tags are read (`Grade: Standard`, `Taper: 4-2`); Enter types the
taper instead, and a missing grade means **Standard**. Grade + taper give,
from the foam sheets:

| | governs |
| --- | --- |
| foam width | the widest a piece may be = max hinge spacing (48", 49 1/2", 53") |
| foam length | the longest a hinge may run (96" / 144") — exceeded, the hinge is still drawn and the report says so |
| pieces | which piece counts are acceptable (e.g. 3-2 folds in 2 only; 5-3 up to 5+) |

**A grade+taper can carry more than one foam sheet** — Standard 3-2 and
4-2 each come as 48" × 144"/96" *and* 49½" × 102" — and **one can work
where the other will not**: the wider sheet needs fewer hinges, the
longer one lets a hinge run further. Every sheet is solved and scored on
what it satisfies (dodges the spillaways / fits the foam length /
acceptable piece count) before fewest pieces is even considered. When
neither fits the length, the longer sheet wins so the overrun is as small
as it can be. Which sheet was taken is noted under the report.

**3. Placement** — the fewest pieces that fit the foam width, spaced
evenly, then nudged off any spillaway zone. A nudge keeps every piece
inside the foam width; when no nudge works the piece count is bumped, and
failing everything the even layout is kept and the report flags the hinge
in the zone. One hinge prefers dead centre.

**4. Hardware** — the longest hinge in the drawing is checked against the
hinge-length chart and each item recommended in the report:

| Grade | Velcro hinges | Double C channel | Hold down kit |
| --- | --- | --- | --- |
| Economy | upon request only | upon request only | upon request only |
| Standard & Deluxe | over 120" | over 108" | over 120" |
| Ultra | over 108" | never | over 96" |
| Thermo-Light | always | never | never |

These are **advisories**, printed in cyan under the report table rather
than red — they are recommendations, not failures.

**Drawing** — fold vs velcro follows the **Hinge Arrangement Chart**:
the pieces fold up in **pairs from both ends**, with a sewn fold hinge
inside each pair (a **`DASHED2`** line on `COVER`, scaled to a 5" dash
in any drawing) and velcro between bundles (**ByLayer** lines). Labels
match the template sample: vertical **MTEXT** in the `Attributes` style
(`Standard` when the drawing has no such style) at a fixed 5" height,
bottom-centred 3" west of the hinge — `Hinge` on folds, `Velcro Hinge`
on the rest. An odd piece count leaves one flat piece at or beside the
centre:

| pieces | west → east |
| --- | --- |
| 2 | Hinge |
| 3 | Hinge, Velcro |
| 4 | Hinge, Velcro, Hinge |
| 5 | Hinge, Velcro, Velcro, Hinge |
| 6 | Hinge, Velcro, Hinge, Velcro, Hinge |
| 7 | Hinge, Velcro, Hinge, Velcro, Velcro, Hinge |

The leftmost hinge is always a fold, no two folds are ever adjacent, and
Thermo-Light stays all-velcro. Labels go on the `TEXT` layer, vertical,
beside their hinge. The report gains rows for each spillaway, the piece
count (with grade/taper), the worst piece width vs foam width, the worst
hinge length vs foam length, and each hinge's offset from the left edge.

## Getting the clean sheet drawing

The mini-model with its corner letters, the mode note and the report
table all live on `SPA-NOTES`. Freeze that one layer and what is left is
the outline and its dimensions — the drawing as the order sheet shows
it.

## Tunables

**Every knob the routine has is in one block at the top of `SPA.LSP`**,
ruled off as `tunables`. Each one is written *once*: change a
value there and every place that reads it follows. (Numbers still
appear in the code below and a few happen to equal a knob above, so
retune by editing the named constant rather than by searching for its
value.) Each group says what it controls; the map is:

Every knob, its default and what changing it does. `tests/test_tunables.py`
holds this table and the block together, so neither can drift from the other.

| Knob | Default | What changing it does |
| --- | --- | --- |
| `spa:*dimlunit*` | `5` | 5 = fractional (84-1/2), 2 = decimal (84.50) |
| `spa:*dimprec*` | `3` | 5 -> 1/8", 2 -> 3 decimal places |
| `spa:*dimpost*` | `"\""` | Every dimension is written in standard inches whatever the host drawing is set to. Anything but 4 (Architectural) keeps the numbers in inches instead of rolling them up into feet. |
| `spa:*dim-asz*` | `0.8` | arrow size; raise for a bolder dim |
| `spa:*dim-exe*` | `0.6` | extension line past the dim line |
| `spa:*dim-exo*` | `0.6` | extension line offset from the outline |
| `spa:*dim-gap*` | `0.4` | gap round the text |
| `spa:*dimoff*` | `36.0` | 3 ft: cover outline -> the LEFT overall dim |
| `spa:*topoff*` | `24.0` | 2 ft: cover outline -> the TOP overall dim |
| `spa:*flatoff*` | `18.0` | outline -> the inboard flat dims |
| `spa:*insetfrac*` | `0.3333` | water's edge dims, a third of the way in |
| `spa:*lapoff*` | `14.0` | how far under the cover the lap note sits |
| `spa:*mark-r*` | `0.18` | circle radius on the corner point |
| `spa:*mark-lead*` | `1.2` | how far out its leader runs |
| `spa:*ng-txt*` | `0.25` | "Not Given" text height |
| `spa:*ng-off*` | `1.45` | how far out that note sits |
| `spa:*rad-off*` | `0.9` | radius dim, dragged out past the arc |
| `spa:*cut-off*` | `0.6` | cut-face dim, out past the face |
| `spa:*oct-off*` | `0.8` | the octagon's one cut callout |
| `spa:*doff-min*` | `6.0` | never closer than 6" |
| `spa:*doff-div*` | `12.0` | Both flows size their dimension offsets and text off the spa itself, so a 5 ft cover and a 12 ft one both come out readable: doff = max(*doff-min*, longer overall / *doff-div*)... |
| `spa:*th-min*` | `1.0` | never smaller than 1" |
| `spa:*th-div*` | `40.0` | Both flows size their dimension offsets and text off the spa itself, so a 5 ft cover and a 12 ft one both come out readable: doff = max(*doff-min*, longer overall / *doff-div*)... |
| `spa:*hingetxth*` | `5.0` | hinge label height |
| `spa:*hingetxw*` | `60.0` | hinge label MTEXT frame width |
| `spa:*hingestyle*` | `"Attributes"` | label style (Standard when absent) |
| `spa:*hingetxoff*` | `0.6` | label height multiples: line -> label |
| `spa:*hdashmult*` | `20.0` | DASHED2 0.25" dash x 20 = 5" on paper |
| `spa:*sfx-water*` | `"Water's Edge"` |  |
| `spa:*sfx-cover*` | `"Cover Size"` |  |
| `spa:*lay-water*` | `"POOL"` | water's edge perimeter (dashed) |
| `spa:*lay-cover*` | `"COVER"` | cover size perimeter |
| `spa:*lay-dim*` | `"DIMENSION"` | every dimension and corner mark |
| `spa:*lay-notes*` | `"SPA-NOTES"` | corner letters, mode note, report, and the grey input guide |
| `spa:*lay-text*` | `"TEXT"` | the Hinge / Velcro Hinge labels The hinges themselves are cover hardware, so they are drawn on the cover's layer even on a sheet that shows only the water's edge (the report say... |
| `spa:*lay-hinge*` | `"COVER"` | The hinges themselves are cover hardware, so they are drawn on the cover's layer even on a sheet that shows only the water's edge (the report says so). Point this at spa:*lay-wa... |
| `spa:*col-water*` | `4` | cyan, and only when POOL is created |
| `spa:*col-cover*` | `6` | magenta, ditto -- an existing layer keeps the colour the office gave it |
| `spa:*col-dim*` | `2` | yellow, on the same terms |
| `spa:*col-notes*` | `3` | green, on the same terms |
| `spa:*col-text*` | `7` | white or black, whichever the background makes it |
| `spa:*col-bad*` | `1` | red -- a letter the validator adjusted |
| `spa:*col-advice*` | `4` | cyan -- a recommendation, not a failure |
| `spa:*dashname*` | `"SPADASH"` | Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTINUOUS silently. A pattern is (dash gap ...) in inches -- positive draws, negative gap... |
| `spa:*dashpat*` | `'(4.0 -3.0)` | Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTINUOUS silently. A pattern is (dash gap ...) in inches -- positive draws, negative gap... |
| `spa:*dotname*` | `"SPADOT"` | Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTINUOUS silently. A pattern is (dash gap ...) in inches -- positive draws, negative gap... |
| `spa:*dotpat*` | `'(0.0 -3.0)` | Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTINUOUS silently. A pattern is (dash gap ...) in inches -- positive draws, negative gap... |
| `spa:*hdashname*` | `"DASHED2"` | the stock fold-hinge pattern |
| `spa:*hdashpat*` | `'(0.25 -0.125)` | Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTINUOUS silently. A pattern is (dash gap ...) in inches -- positive draws, negative gap... |
| `spa:*ds-cover*` | `"STANDARD INCHES"` | A style the drawing already defines is used exactly as it stands -- the office template wins -- and one that is missing is built from the standard-inches settings above, the wat... |
| `spa:*ds-water*` | `"STANDARD INCHES 0.5"` | A style the drawing already defines is used exactly as it stands -- the office template wins -- and one that is missing is built from the standard-inches settings above, the wat... |
| `spa:*wefactor*` | `0.5` | A style the drawing already defines is used exactly as it stands -- the office template wins -- and one that is missing is built from the standard-inches settings above, the wat... |
| `spa:*gapdflt*` | `6.0` | suggested cover lap over the water's edge |
| `spa:*diagoff*` | `0.82842712` | Offsetting a corner by g is not the same for every treatment: a radius stays concentric (r -> r + g) and a cut face lengthens by g * (2*sqrt2 - 2). That factor, once. |
| `spa:*capfuzz*` | `1.0e-6` | How far a corner treatment may exceed its own setback cap before the size is refused and re-asked. Float noise only -- a millionth of an inch, orders below the 1/16" a tape read... |
| `spa:*octeq*` | `0.125` | How far the eight sides of an octagon may differ and still count as "all equal" -- a rounded-off cut face like 39-3/8" must still read as the regular octagon it is, and get one... |
| `spa:*sameeps*` | `0.0005` | ...and how far two corners' sizes may differ and still be one treatment for the Typ. rule. |
| `spa:*rep-row*` | `2.2` | h multiples: row pitch |
| `spa:*rep-title*` | `1.25` | h multiples: the heading's text height |
| `spa:*rep-note*` | `1.4` | h multiples: a red failure note |
| `spa:*rep-advice*` | `1.15` | h multiples: a cyan recommendation |
| `spa:*rep-c1*` | `20.0` | h multiples: the TARGET column |
| `spa:*rep-c2*` | `29.0` | the ACTUAL column; move it out if a measurement ever runs into it |
| `spa:*rep-c3*` | `38.0` | the DELTA column, on the same terms |
| `spa:*rep-w*` | `46.0` | how wide the ruled box comes out |
| `spa:*map-gap*` | `3.0` | th multiples: table -> the mini-model |
| `spa:*map-size*` | `24.0` | th multiples: the mini-model's fit box |
| `spa:*pv-col*` | `8` | guide outline (dark gray) |
| `spa:*pvx-col*` | `7` | measuring tie (white) |
| `spa:*hi-col*` | `1` | the element being asked for (red) The RECTANGLE guide's nominal box. The octagon and round guides keep their own ring in spa:octpreview / spa:roundpreview rather than reading th... |
| `spa:*pv-w*` | `240.0` | nominal guide width |
| `spa:*pv-l*` | `200.0` | nominal guide length |
| `spa:*pv-th*` | `12.0` | guide corner-letter height |
| `spa:*pv-tie*` | `10.0` | guide tie-letter height |
| `spa:*pv-lbl*` | `22.0` | how far a rectangle corner letter sits out |
| `spa:*pv-olbl*` | `20.0` | ...and an octagon one, which sits tighter |
| `spa:*pv-cap*` | `50.0` | biggest treatment the guide will draw, so one huge corner cannot swallow it |
| `spa:*foamdflt*` | `(list (cons 48.0 96.0))` | assumed when nothing matches |
| `spa:*foamdpc*` | `(list 2 3 4 5)` | and the counts it will accept |
| `spa:*thermotaper*` | `"1-3/8"` | the one taper a Thermo-Light comes in |
| `spa:*hinge-min*` | `2` | a cover is never fewer pieces than this |
| `spa:*hinge-try*` | `3` | how many extra piece counts to try |
| `spa:*hinge-edge*` | `0.01` | keep a hinge this far off the cover's edge |
| `spa:*allcorners*` | `"the four corners"` | The subject the all-same round asks about, spelled ONCE: it is the label the treatment question and its size follow-up both read ("How should the four corners be treated?", "Rad... |

Not in that block, on purpose: run state (the which-outline switch, the
guide's entity list), the octagon's edge table (that is shape
structure, not a setting), and the bare `1.0e-6` float-noise guards.

`spa:*capfuzz*` is a millionth of an inch of slack on the corner-size
cap, so a treatment typed at exactly the maximum the prompt printed is
accepted rather than re-asked with the same number back. (`POOL` needs
the same guard more sharply — its cap is compared against a setback
computed through a cosine.)

## Notes

* Plain AutoLISP (`entmake` plus classic commands, no ActiveX/VLA), so it
  loads on AutoCAD 2018 and older releases.
* The user's object snaps stay live at every measurement prompt and are
  restored on exit — including after an Esc or an error mid‑prompt.
* The whole run is wrapped in a single UNDO group.
* The dash and dot patterns are defined in inches and scaled to cancel
  the drawing's `LTSCALE`, so they look the same in any drawing.
* Not covered: the order sheet's *"Indicate Strap and Handle Placement"*
  and *"You must indicate hinge direction!"* annotations. Those are
  order-entry marks rather than measurements, so they are left to be
  added by hand.
