# SPA.LSP — spa / hot-tub template layout

AutoLISP command that draws a spa outline from field measurements, built
from the same bones as `POOL.LSP` but cut down to what a spa template
needs.

Load it (`APPLOAD`, or drag the file into the drawing) and type **`SPA`**.

## Shapes

| Shape | What it asks for |
| --- | --- |
| **Rectangle** | overall width (A‑B), overall length (A‑D), then each corner |
| **Octagon** | overalls **B** across and **A** up, plus the cut letters **T / S / S1 / V / S2** (any of them may be `NA`) |
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

| Answer | Perimeter | Dimension text |
| --- | --- | --- |
| `Watersedge` | **dashed**, on layer `POOL` | `<measurement> Water's Edge` |
| `Coversize` | solid, on layer `COVER` | `<measurement> Cover Size` |

The suffix goes on the **overalls only**. Corner callouts (radii, cut
faces) and the inboard flat dims are left plain, so a corner or a segment
note can never be mistaken for an overall.

The mode is also written under the drawing (`SPA OUTLINE DRAWN AT
WATER'S EDGE`) and in the report table's title.

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
`Radius` corner, an aligned dimension across a `Diagonal` cut face, and a
`90°` leader on a `90` corner — that last **only when the corners are
mixed**, so an all-square rectangle carries no corner notes at all.
Four identical corners are called out **once**, with a `Typ.` suffix.

## Where the dimensions go

Laid out the way the cover order sheet does it:

| Shape | Dimensions drawn |
| --- | --- |
| **Rectangle** | overall across on the bottom, overall up on the left; once corners are cut away, the remaining **flat** runs are dimensioned inboard of them, on the bottom and the right |
| **Octagon** | overall across, overall up, and **one** corner-cut callout (`Typ.`). All eight sides equal → that is all it gets, and the drawing says `OCTAGON - ALL SIDES EQUAL`; unequal flats get their own inboard dims like the rectangle |
| **Round** | one overall. Only an out-of-round spa gets the second one |

## Standard inches

Every dimension is written in standard inches and placed **outside** the
shape, no matter how the host drawing is set up. The dimension variables
are set for the duration of the command and restored afterwards; each
dimension keeps the settings as its own style override, so the numbers
stay in inches once the command is done.

Defaults (constants at the top of the file):

```lisp
(setq spa:*dimlunit* 5)     ; 5 = fractional inches (84-1/2), 2 = decimal (84.50)
(setq spa:*dimprec*  3)     ; 5 -> 1/8", 2 -> 3 decimal places
(setq spa:*dimpost*  "\"")  ; the inch mark appended to every measurement
```

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

Leaving all the octagon cut letters `NA` falls back to a true square
octagon sized off `A` and `B` alone — 45° cuts, all eight sides equal.

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
