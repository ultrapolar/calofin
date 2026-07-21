# POOL.LSP — swimming-pool as-built layout for AutoCAD

AutoLISP routine that draws a pool plan (**Rectangle**, **Oval**,
**Grecian**, **L** or **Lazy L**) from real-world field measurements,
dimensions it, and writes a target / actual / delta report next to
the drawing.

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
2. Pool shape: `Rectangle` / `Oval` / `Grecian` / `L` / `LAzyl`
   (type `L` for a true L, `LA` for a lazy L).
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

The **guide updates live**: as soon as the corner answers are in, the
gray guide redraws its corners with the chamfers/fillets (display
sizes capped so oversized inputs can't fold the nominal shape), and
the dashed cross-dim guide lines are re-drawn between the actual
reference points for the chosen mode — in Ends mode each of the four
ties is its own line, highlighted individually as it's prompted.

### Pool bottom / hopper (rectangle, oval, Grecian)

After the perimeter is drawn and dimensioned, the routine offers a
**pool bottom (hopper) phase** (`Yes`/`No`, default Yes). A lettered
field-sheet guide appears inside the fitted pool and each dashed tie
highlights as its letter is prompted. The interior draws on the
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

Sport bottoms draw a full-width **break line in the plan at every
slope change** and the **side profile underneath** the plan, guided by
lettered ties exactly like the sheet (E2/F2/G/F1/E1 along the bottom,
`C` wall height at the right, `D` depth in the middle), with the
profile chain, C and D dimensioned.

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

Six-corner pools with one wing; a **true L** has a square step joint,
a **lazy L** an angled one:

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
zooms to it. The pool outline is drawn solid while all **cross dims
are dashed**, so the shape and the diagonals read apart at a glance
even on the L pools where six diagonals cross the body. While each
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
