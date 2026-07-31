# SPA.LSP — spa / hot-tub template layout

AutoLISP command that draws a spa outline from field measurements, built
from the same bones as `POOL.LSP` but cut down to what a spa template
needs.

Load it (`APPLOAD`, or drag the file into the drawing) and type **`SPA`**.

## Shapes

| Shape | What it asks for |
| --- | --- |
| **Rectangle** | overall width (A‑B), overall length (A‑D), then each corner |
| **Octagon** | overalls **B** across and **A** up, then the cut **face S2**, then **T / S / S1 / V** (any of them may be `NA`) |
| **Round** | **B** across and **A** up — a circle when they agree, an ellipse when they do not |

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

## Water's edge vs cover size

The first question is which one is being drawn, and it decides both the
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
`90` corner. By dims, the corner sizes are *offered* at whatever the
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

Every corner is asked for separately, using the order sheet's own corner
legend — `Radius` (sized by its radius), `Diagonal` (a cut, sized by its
face length) or `90`. (`Square` is accepted as a synonym for `90`.)

**Corner A's answer autofills B, C and D** — press Enter at each of them
to accept it, or type a different treatment for that corner, so a cover
with two cut corners and two square ones takes four different answers.
Side lengths are always measured to the *true* (sharp) corner; the
treatment cuts inward from there, and a treatment too big for its walls
is re‑asked.

Callouts sit outside the corner on its 45° line: a radius dimension on a
`Radius` corner (`R12"`), an aligned dimension across a `Diagonal` cut
face (`21"`), and a circled corner point with a `90°` leader on a `90`
corner.

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
drawing for an all-radius or all-diagonal cover, and for a true square
octagon. A plain 90-corner rectangle gets no corner callout at all: the
two overalls *are* the drawing.

**Corners not identical** — each cut corner is called out on its own (no
`Typ.`), the square ones among them share one `90°` mark, and every side
a cut has **shortened** also gets its remaining **flat** dimensioned,
inboard of the overalls. So a cover with one cut at the top-right reads:
overall across, overall up, the top flat, the right flat, the cut face,
and `90° Typ.` on the square corners.

The round spa takes one overall; only an out-of-round one gets the
second. An octagon whose eight sides come out unequal picks up the bottom
and right flats the same way the rectangle does.

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

**2. The "Spa Cover Details" block** — select it and the `GRADE` and
`TAPER` tags are read (`Grade: Standard`, `Taper: 4-2`); Enter types the
taper instead, and a missing grade means **Standard**. Grade + taper give,
from the foam sheets:

| | governs |
| --- | --- |
| foam width | the widest a piece may be = max hinge spacing (48", 49 1/2", 53") |
| foam length | the longest a hinge may run (96" / 144") — exceeded, the hinge is still drawn and the report says so |
| pieces | which piece counts are acceptable (e.g. 3-2 folds in 2 only; 5-3 up to 5+) |

A grade+taper with two foam options (Standard 3-2 / 4-2) carries both;
the solver picks the one needing the fewest hinges.

**3. Placement** — the fewest pieces that fit the foam width, spaced
evenly, then nudged off any spillaway zone. A nudge keeps every piece
inside the foam width; when no nudge works the piece count is bumped, and
failing everything the even layout is kept and the report flags the hinge
in the zone. One hinge prefers dead centre.

**Drawing** — the leftmost hinge is the fold hinge: a **dashed** line on
`COVER` labelled `Hinge`. Any further hinges are **ByLayer** lines on
`COVER` labelled `Velcro Hinge`. Labels go on the `TEXT` layer, vertical,
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
