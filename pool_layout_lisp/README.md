# POOL.LSP — swimming-pool as-built layout for AutoCAD

AutoLISP routine that draws a pool plan (**Rectangle**, **Oval**,
**Grecian**, **L**, **Lazy L** or **Roman**) from real-world field
measurements, dimensions it, and writes a target / actual / delta
report next to the drawing.

Written in plain AutoLISP (`entmake` + classic commands only — no
ActiveX/VLA), so it loads in **AutoCAD 2018** and older releases alike
(full versions; AutoCAD LT before 2024 has no LISP support).

## Loading & running

1. `APPLOAD` → pick `POOL.LSP` (or drag the file into the drawing).
2. Type `POOL` and answer the prompts.

Drawing units are assumed to be **inches** — all tolerances below are
in inches. The command switches to Architectural units while it runs
(restored afterwards), so **every distance prompt** accepts feet-inch
entry regardless of the drawing's unit setting: `25'6"`,
`25'-6-1/2"`, `25'6.5`, or plain numbers as inches (`306.5`). Note
that AutoCAD treats a space as Enter, so type fractions with a dash
(`25'-6-1/2"`, not `25'-6 1/2"`).

## What it asks

Corner naming used by every prompt:

```
D ---------- C        sides:  top D-C, bottom A-B
|            |        ends:   left A-D, right B-C
A ---------- B        cross:  A-C and B-D
```

1. **In-square or out-of-square?** An **in-square** pool is built true
   to the side/end measurements — no diagonals are asked for or drawn.
   An **out-of-square** pool takes the full cross-dim route below.
2. Pool shape: `Rectangle` / `Oval` / `Grecian` / `L` / `LAzyl` /
   `ROman` (type `L` for a true L, `LA` for a lazy L, `RO` for a
   Roman).
3. Insertion base point.
4. Side lengths, top then bottom.
5. End lengths, left then right.
6. Cross dimensions A-C and B-D. *(out-of-square only)*
7. **Oval only:** total pool length, left end radius, right end radius.
8. **Grecian only:** a cross-dim detail level (see below), then for
   each end — diagonal top, diagonal bottom, end width — followed by
   the cross dims for the chosen level.

Any **cross dimension** prompt also accepts `NA` when that measurement
wasn't taken in the field: the fitter simply skips it and the report
shows `N/A` for its target/delta (the as-drawn value is still listed).

### Rectangle corners (Square / Rounded / Diag)

Rectangle corners can be **Square**, **Rounded** (a radius) or **Diag**
(a chamfer, sized by its **face length** — the cut itself). Side and
end lengths are always measured to the **true (sharp) corner**; the
treatment cuts inward from there.

* **In-square:** one corner question, applied to all four corners.
  In-square pools also ask each **pair of opposing sides once** —
  side length (top & bottom together), end length (left & right
  together), and on a Grecian each end's two diagonals together —
  since a true pool's opposing sides are equal.
* **Out-of-square:** asked per corner (A, B, C, D); press **Enter** to
  reuse the previous corner's answer, so four identical corners is
  three quick Enters.

When corners are cut/rounded **and** the pool is out-of-square, you're
asked where the cross dims were measured from:

| Reference | Meaning | Cross prompts |
| --- | --- | --- |
| **Corner** | To the true (extended) sharp corner | A-C, B-D |
| **Middle** | To the middle of each chamfer/arc | A-C, B-D |
| **Ends** | To the treatment endpoints — **both** ends of each diagonal | A-C (B-side & D-side), B-D (A-side & C-side) |

The measurements are converted to equivalent true-corner diagonals
(corrected against the fitted corner geometry) so the body still
best-fits correctly, and each cross measurement is dimensioned between
its actual reference points and listed in the report. Square corners
always use the true corner, so no reference question is asked.

**Perimeter dims** (per the reference drawing): a rectangle gets
just **two** perimeter dimensions — the **northern** dim (overall
length) and the **western** dim (overall width) — drawn as rotated
linear dims whose extension lines hook to **points on the object**:
the top endpoints of the two side walls and the left endpoints of the
top/bottom walls (the arc-tangent / chamfer ends when corners are
cut). No floating true-corner extension lines. All four sides still
appear in the report table. Other shapes keep their full dim sets,
which already hook to drawn geometry.

**Corner dimensions**: an **in-square** pool gets a single "Typ."
callout at the bottom-right corner (B) — a radius dimension reading
`R1'-6" Typ.`, a chamfer-face dimension reading `1'-8" Typ.`, or, for
square corners, a leader pointing at the corner reading `90° Typ.`
An **out-of-square** pool dims **every corner individually**: radius
dims on rounded corners, face dims on chamfers, and the **actual
angular dimension** on square corners (showing the true fitted angle,
e.g. `89.6°`).

The **guide updates live**: as soon as the corner answers are in, the
gray guide redraws its corners with the chamfers/fillets (display
sizes capped so oversized inputs can't fold the nominal shape), and
the dashed cross-dim guide lines are re-drawn between the actual
reference points for the chosen mode — in Ends mode each of the four
ties is its own line, highlighted individually as it's prompted.

### Pool bottom / hopper (rectangle, oval, Grecian)

After the perimeter is drawn and dimensioned, the routine offers a
**pool bottom (hopper) phase** (`Yes`/`No`, default Yes). A lettered
field-sheet guide appears inside the fitted pool; each tie **and its
letter** turn red as that letter is prompted. The interior draws on the
**`POOL`** layer. For the rectangle:

```
D ------------------------------ C     H  left end -> hopper
|\      M                       /|     G  hopper length
| +--------+                  /  |     F  hopper -> slope break (CHECK)
|H|G hopper|  \            break |     E  slope break -> right end
| +--------+     \           | E |     M  top side -> hopper
|/      K            \       |   |     L  hopper width (CHECK)
A ------------------------------ B     K  hopper -> bottom side
```

All primary dims are **offsets from the perimeter** (H, E, M, K) plus
the hopper length G, so they anchor the geometry exactly even on an
out-of-square pool (offsets stay perpendicular to each wall).

**Every bottom length accepts `NA`** ("no answer"), and each chain is
reconciled against the pool before drawing:

* one `NA` in a chain → it takes the **remainder**;
* several `NA`s → the remainder is **split evenly** among them;
* everything provided but the chain doesn't close against the pool →
  **G** (horizontal) / **L** (vertical) absorb the difference; the
  no-pad sport bottom has no G, so its residual splits across F2/F1.

The report shows what you *entered* (or `N/A`) against what was
*drawn*, so any fill or absorption is visible in the delta column.

**Dim placement** (per the field sheet): the H/G/F/E chain runs
below the hopper's vertical centre by **12" or L/6** (two-thirds down
from the top of L), whichever is closer to centre. The M/L/K dims
**attach to the hopper lines themselves** — extension-line origins on
the hopper's right-edge corners and the wall points directly
above/below — with only the dimension **line** floating **12" to the
right** of the hopper's right edge. Applies to every shape's hopper
and to the sport deep flat.
The hopper's left corners tie to the pool's left corners — when a
corner is Diag/Rounded, **to both ends of the treatment** (one line
per end) — and its right corners tie to the ends of the slope-break
line. Everything is chain-dimensioned along the two centerlines like
the field sheet, and every letter gets a report row.

**Oval (True Oval sheet):** same phase, prompting the interior letters
only (A, B, R1, R2 come from the perimeter). The hopper is a box with
a radius **R3** left end set out along the pool axis (arc tip to arc
tip): `H` tip→hopper tip, `G` hopper length, `R3` end radius, `E`
break→right tip, `M`/`K` top/bottom offsets, with `W` (flat top,
= G−R3), `F`, `L` and `T` (straight side) reported as checks. No left
ties — the radius is the end; the right corners tie to the break ends.

**Grecian:** first asks **`Hopper type [Square/SIX-sided]`**, interior
letters only (A, B, S, S1, S2, T, V come from the perimeter). Both
anchor `H`/`E` off the end walls and `M`/`K` off the sides. The square
hopper is the rectangle letter set; each hopper left corner ties to
**both ends of its pool corner cut** (to D and LT, and to A and LB).
The 6-sided hopper adds cut left corners — `W` (setback along the
top/bottom edges), `L1` (setback down the left edge), `X` (cut face,
check) — and the pool cut ends tie to the matching hopper cut ends.

### Sport bottoms and the side profile

Rectangle, oval and Grecian pools ask **`Bottom type
[Normal/Sport/NOhopper pad sport]`** (L / Lazy L pools are
standard-hopper only):

* **Sport** — no plan hopper; the bottom is a full-width profile:
  shallow flats `E2`/`E1` at each end, slopes `F2`/`F1`, and a flat
  deep section `G` (reported as a **check** = B − E2 − F2 − F1 − E1).
* **NOhopper (pad)** — same but the two slopes meet at a point; `F1`
  is the check.

Sport bottoms are drawn in the **plan like a standard hopper** (per
the reference drawing): full-width break lines at the outer breaks,
the **deep flat as a rectangle inset M/K from the side walls**, and
corner diagonals tying the outer breaks to the deep-flat corners. The
letters are dimmed **on the pool floor in the plan** with the
standard-hopper placement rules — the E2/F2/G/F1/E1 chain below the
deep flat's centre (12" or L/6), the M/L/K chain 12" right of its
right edge — so sport prompts now include `M`, `L`, `K` (all NA-able;
L absorbs against the width). The **side profile** still draws
underneath, carrying only the `C` and `D` depth dims. The no-pad
sport is identical with **G = 0** (the deep flat collapses to the V
line; G isn't prompted).

Standard (Normal) hoppers are **plan-only** — no heights are asked
and no profile is drawn; the side profile (with `C` wall height and
`D` depth) belongs to the Sport bottoms, whose field sheets are
profiles.

**L / Lazy L pools** get the standard hopper in the **main section**:
the virtual corner D' (where the left side meets the main-top line)
closes the main rectangle A-B-C-D', the usual H/G/F/E/M/L/K letters
anchor off its walls, the slope break spans the main section only,
and the hopper's left corners tie to A and D'.

**Cross dims are drawn dashed** in the final drawing (a linetype
override on the dimension entities, on top of the `CROSS DIMENSION`
style when present), matching the dashed guide convention.

### In-square vs out-of-square

The very first prompt asks whether the pool is in-square. **In-square**
skips every cross dim (and the guide's diagonals): the shape is built
true to the side, end, diagonal and width measurements — a perfect
rectangle, oval, Grecian or L. Use it when the pool was formed square
and you only need the outline dimensioned. **Out-of-square** is the
full workflow: cross dims are prompted, the shape is best-fit to them
within tolerance, and the target/actual/delta report and (for a
rectangle) the exact triangle check figure are produced.

### Roman pools

A Roman (per the reference drawing) is a rectangle body with
**full-length sides T**, vertical **S1 stubs down the end lines** to
the arc springs (`V` apart), and an arc bulging **S** past each end
line: `B`/`A` overalls (required), `T`, `S`, `S1`, `V` — and `R` is
**implied** by S and V (`R = (S² + (V/2)²) / 2S`), so the radius
prompt is a check (`NA`-able); with S unknown, a given R supplies it
(sagitta). Letters close against the overalls exactly like the
Grecian sheet (`S+T+S = B` with **T absorbing**, `S1+V+S1 = A` with
**V absorbing**; `NA` derives from the partners). The guide shows the
sheet with the dashed **tip-to-tip B centerline** through the middle,
matching how B is taped.

* **In-square** pools are **perfect**: one `S`/`S1`/`V` set and a
  single radius `R` apply to both ends.
* **Out-of-square** pools first ask **`Are both ends perfect?`** —
  Yes keeps the single symmetric set; No asks each end's `S`, `S1`,
  `V` and `R1`/`R2` separately. Body cross dims (A-C, B-D, NA-able,
  drawn dashed) fit the out-of-squareness of the T×A body, and the
  ends are built onto the fitted body.

An end whose radius is smaller than `V/2` can't reach its springs;
it's drawn as a semicircle and flagged in the notes. The ends get
radius dimensions, the overalls B (tip to tip) and A are dimensioned
like the sheet, and the interior is the **True Oval hopper / sport
bottom** phase, tips and all.

### Grecian perimeter input (Measured / Overall)

After the cross-dim level, the Grecian asks **`Perimeter input
[Measured/Overall]`**:

* **Measured** — the existing per-edge prompts (body sides, body
  ends, each end's diagonals and width).
* **Overall** — the overall field sheet, with the sides **assumed
  symmetric**: `B` overall length and `A` overall width (required),
  then `T` top side, `S` corner-cut run along the side, `S1`
  corner-cut drop down the end, `V` end width, `S2` cut face — each
  `NA`-able. The letters close against the overalls (`S+T+S = B`,
  `S1+V+S1 = A`): an `NA` is derived from its partners, and when both
  are given but don't close, the middle absorbs (`T` against B, `V`
  against A). `S2` is a check against √(S²+S1²). The derived edge set
  feeds the normal pipeline, so cross dims, fitting, hoppers and the
  report all work as usual, with `OV` report rows showing each sheet
  letter against the fitted shape. The guide shows the sheet's ties
  (B/T/S across the top, A/S1/V down the left, S2 at a cut),
  highlighted as prompted.

### Grecian cross-dim detail (Simple / Center / Complex)

A Grecian has **8 corners**: the body A/B/C/D plus the angled-end tips
**LT/LB** (left-top, left-bottom) and **RT/RB** (right-top,
right-bottom). After choosing Grecian you pick how many cross dims to
supply — the more you give, the more tightly the out-of-square shape
is pinned down. Any cross dim may be answered `NA`.

| Level | Cross dims | What it adds |
| --- | --- | --- |
| **Simple** | A-C, B-D | The two body diagonals (the original behaviour). |
| **Center** | + LB-RT, LT-RB | The two long tip-to-tip diagonals that cross near the pool centre. |
| **Complex** | all 18 diagonals | Every possible diagonal among the 8 corners. Supply what you measured and `NA` the rest. |

All 8 corners are then **best-fit** against every provided cross dim
(sides/ends held within 1", end diagonals within ½", end widths near
exact, cross dims pulled to target within 2"). If the cross dims
can't be met the edges are held true and **`CROSS DIMS FAILED`** is
reported — same policy as the rectangle. Every cross dim is
dimensioned (in the `CROSS DIMENSION` style when present) and listed
in the report table (`X A-C`, `X LB-RT`, …) with target/actual/delta.

### L / Lazy L pools

Both are six-corner pools, drawn in the reference orientation: the
**main section on the left, the wing/bend on the right**. A **true L**
has a full-height right end (B-C), the wing top-right and the notch
top-left. A **lazy L** is a constant-width pool **bent 45°**: main run
A-B/E-F, bend sides B-C and D-E at 45°, far end C-D; it asks its own
side names and **omits the B-E joint diagonal** (8 cross dims instead
of 9).

**Hopper (both variants, per the reference):** the **break line drops
from the inner corner E straight to the bottom side**, and the hopper
sits in the main section bounded by the left end, the bottom, that
break line and the top (`A – breakBottom – E – F`). Its left corners
tie to A and F, its right corners to the break line's ends. `B1` is
the main-section length and `V1` its width.

**E is only asked when it's needed:** give H, G and F and if they sum
to **B1** (within ½"), the break lands on the inner corner and the
`E` prompt is skipped entirely. If any of them is `NA`, or the sum
doesn't reach B1, `E` is prompted and the four-part chain resolves
against B1 as usual (G absorbing, NA taking the remainder).

**Mirroring:** once every dimension is in, the L pools ask
**`Mirror the pool [Yes/No]`** — answering Yes mirrors the finished
pool, its dimensions and its hopper about the pool's vertical
centreline (text stays readable; the report table is written
afterwards, unmirrored).

The true L:

```
F -------- E
|           \\             sides:  A-B, B-C, C-D, D-E (joint),
|            D ------- C           E-F, F-A
|                      |   cross:  A-C, B-D, C-E, D-F, A-E, B-F
A -------------------- B           (any of them may be NA)
```

The routine asks for the six side lengths and up to six cross dims,
then best-fits the six corners the same way as the rectangle: sides
held true first; if the provided cross dims don't land within 2" the
sides may flex inside their ±1" band; and if they still can't be met
the sides are held true and **`CROSS DIMS FAILED`** is reported. The
more cross dims you provide, the better the out-of-square shape is
pinned down — with none at all you simply get the perfect right-angle
(or 45°-jointed) shape. The two-triangle check figure is not drawn
for L pools.

### Guided input

As soon as the shape is chosen, a gray nominal "guide" pool of that
shape (with corner labels) is drawn at the base point and the view
zooms to it. The pool outline is drawn solid in **gray**, while all
**cross dims (and other measuring lines) are WHITE and DOTTED**, so
the diagonals read clearly over the shape even on the L pools where
nine diagonals cross the body. The dot pattern is defined in inches
by the routine itself and scaled to cancel the drawing's `LTSCALE`,
so it looks the same in any drawing (no dependency on `acad.lin`
being found, which used to make the pattern silently fall back to
continuous).

When a prompt names corners — a side "A-B", a cross dim "A-C", or a
rectangle corner treatment — **the corner letters turn red too**,
alongside the line being measured. While each
measurement is prompted for, the matching element of the guide glows
**red** so there is never any doubt which dimension is being asked
for — including the cross diagonals, oval radius/arc and total-length
line, and the Grecian corner diagonals and end widths. Once the last
dimension is entered the guide deletes itself and the true
out-of-square pool is drawn in its place (the guide is also cleaned
up if the command is cancelled part-way).

## What it draws

| Layer | Content |
| --- | --- |
| `POOL` | The full pool **perimeter**, running around the whole shape — including the oval end arcs and Grecian corner cuts (individual lines/arcs, i.e. an exploded polyline). Best-fit body: sides held within **±1"**, cross dims within **±2"** of the given values (field measurements carry human error). |
| `POOL-NOTES` | All non-perimeter reference lines, **dashed** (the body end lines under oval/Grecian ends, the oval radius construction lines), plus corner labels and the report table: one row per measurement with TARGET, ACTUAL and DELTA. The `DASHED` linetype is auto-loaded from `acad.lin`/`acadiso.lin`; falls back to continuous if neither is found. |
| `POOL-TRIANGLES` | Exact as-measured check figure built from two triangles (bottom + right end + cross A-C, and top + left end + cross A-C). **No tolerance** — lengths held exactly. Overlaid on the outline so the two can be compared; freeze one layer to view the other. |
| `DIMENSION` | Aligned dimensions for all sides, cross dims and shape extras. Cross dims are drawn in the **`CROSS DIMENSION`** dimension style when the drawing has one (the current style is restored afterwards); everything else uses the current dimension style. Cross dims answered `NA` are not dimensioned. |

### Fitting logic

1. Sides are first held **exactly** true and the body is skewed
   (four-bar search) to bring the cross dims as close as possible. If
   both cross dims land inside the 2" tolerance, done.
2. Otherwise the sides are allowed to flex inside their ±1" band
   (iterative relaxation) to pull the cross dims in.
3. If the cross dims still cannot be met, the sides are held true, the
   cross dims get as close as possible, and **`CROSS DIMS FAILED`** is
   written in red under the report table.

### Oval ends

A construction line is drawn perpendicular to each end from its
midpoint, with the given end radius as its length; a three-point arc
runs from one end corner, through the tip of that line, to the other
end corner. The total pool length (arc tip to arc tip) is reported
against the given target.

### Grecian ends

Two diagonals project from the end-line corners at a nominal 45°. The
angle is adjusted until the given end width fits between the diagonal
end points; if no angle works, the diagonal lengths are adjusted in
**1/8" increments** (smallest total adjustment first, at most **±1/2"**
from the given lengths) and the angle search repeats. The lengths and
angle actually used are reported; if nothing fits, the end is drawn at
45° with the given lengths and flagged as failed in the report.

## Tolerance constants

At the top of the file, all in drawing units (inches):

```lisp
(setq pool:*side-tol*  1.0)     ; side length tolerance
(setq pool:*cross-tol* 2.0)     ; cross dimension tolerance
(setq pool:*grec-step* 0.125)   ; Grecian diagonal adjustment increment
(setq pool:*grec-max*  4)       ; max increments each way (= 1/2")
```
