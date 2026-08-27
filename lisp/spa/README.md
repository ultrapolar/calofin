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
| `SPA_082026_REV04.LSP` | the same file, named `MMDDYY_REV##` for its revision |
| `TUTORIALSPA.LSP` / `TUTORIALSPA_082026_REV04.LSP` | likewise |

The static name never changes, so an existing autoload keeps working. The
versioned name tells you at a glance which revision is sitting in someone
else's stack. And because the two are identical, **the version string
travels inside both** — so a session that loaded the static name can
still tell you what it is:

```
Command: SPAVER
SPA 082126 REV05
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
| **Rectangle** | overall width (A‑B), then the length (A‑D) — **the width is offered back**, so Enter makes it square — then each corner |
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

Every corner is asked the repo's canonical **Treatment** question
(STANDARDS.md section 2): `How should Corner A be treated?
[Square/Radius/Cut/NotGiven]` — `Square` (a true 90), `Radius` (sized by
its radius), `Cut` (a straight diagonal, sized by its face length) or
`NotGiven` (nothing on the order sheet: drawn square and flagged). The
pre-standard words still work typed in full — `90`, `ROUNDED`, `DIAG` /
`DIAGONAL`, `NG` — and are normalised as they are read; the palette's
old wire values are accepted the same way.

**Corner A's answer autofills B, C and D** — press Enter at each of them
to accept it, or type a different treatment for that corner, so a cover
with two cut corners and two square ones takes four different answers.
Side lengths are always measured to the *true* (sharp) corner; the
treatment cuts inward from there, and a treatment too big for its walls
is re‑asked.

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

* The **spillaway loop** commits as it goes, so Back at the top of it
  *removes the spillaway just committed* — its no-go zone and its
  report row — before re-asking (`Stepping back one spillaway.` /
  `Already at the first spillaway.`).
* The **taper** prompt is a `getstring`, which cannot take keywords, so
  there Back is typed like a value — `B`, `BACK`, `U` or `UNDO`, any
  case — and the prompt says so.

Back cannot cross a point where geometry was committed: once an outline
is drawn, the offer to add the other one is a fresh first question. That
is the same boundary `POOL` has.

## Orientation

**The long overall always runs west to east**, whichever order the two
were typed in. If the length comes in bigger than the width the cover is
drawn a quarter turn over, and the corner treatments and their letters
travel round with it — the corner the user called `B` lands bottom-left
and is still labelled `B`, so the drawing reads back against the report
table. The turn is announced at the command line and noted under the
drawing.

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
`0.41421`. Radius dimensions still work: `DIMRADIUS` takes a polyline
arc segment picked at a point on it exactly as it takes a bare arc. A
round spa was already a single `CIRCLE` (or `ELLIPSE` when out of
round), so it was bounded to begin with.

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

Defaults (constants at the top of the file):

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
| `SPA-NOTES` | corner letters, the mode note, the report table, and the grey input guide |
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

After the cover is dimensioned the command asks **"Auto-hinge the
cover?"**. Hinges run north-south, splitting the cover into side-by-side
pieces along its west-east length.

**1. Spillaways** — places a hinge cannot go, asked in a loop that always
defaults to `No`:

* `Corner` — pick the corner, give the length from the (hypotenuse)
  corner to keep clear; it blocks that far along both walls of the angle.
* `Wall` — give the spillaway's overall length; it is assumed centred on
  its wall. A left/right wall spillaway cannot meet a north-south hinge,
  so it is recorded but blocks nothing.

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

The corner letters, the mode note and the report table all live on
`SPA-NOTES`. Freeze that one layer and what is left is the outline and
its dimensions — the drawing as the order sheet shows it.

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
