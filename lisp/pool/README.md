# POOL.LSP — swimming-pool as-built layout for AutoCAD

AutoLISP routine that draws a pool plan (**Rectangle**, **Grecian**,
**Octagon**, **Roman**, **L**, **Lazy L**, **Oval**, **Round** or
**Mutt** — a rectangle body with independently chosen deep/shallow
ends) from real-world field
measurements, dimensions it, and writes a target / actual / delta
report next to the drawing.

Written in plain AutoLISP (`entmake` + classic commands only — no
ActiveX/VLA), so it loads in **AutoCAD 2018** and older releases alike
(full versions; AutoCAD LT before 2024 has no LISP support).

## Loading & running

1. `APPLOAD` → pick `POOL.LSP` (or drag the file into the drawing).
2. Type `POOL` and answer the prompts.

### Checking the install: `POOLDEMO`

`POOLDEMO.LSP` is a separate, optional file. Load it after `POOL.LSP`
and type **`POOLDEMO`** to draw — from hardcoded numbers, with no
prompts — one captioned example of **every shape, every pool bottom,
and every drawing feature** the routine produces: corner treatments,
side sections, the report table, and a deliberately failed bottom
showing the red marking.

It answers in one second whether POOL.LSP loaded, whether the layers
and the dashed/dotted linetypes come out right, whether the dimension
commands work in this drawing's dim style, and whether arcs, text and
the report render as intended. It doubles as a reference sheet of
what the tool can draw.

Run it in a **scratch drawing** — it draws on the same layers `POOL`
uses. It never prompts, so it is safe to re-run any time.

### Learning it: `TUTORIALPOOL`

`TUTORIALPOOL.LSP` is a third optional file. Load it after `POOL.LSP`
and type **`TUTORIALPOOL`** for a paced, captioned walkthrough: nine
topics, each printing a short explanation (guided input, in-square vs
out-of-square, corner treatments, the hopper, validation, dimension
styles, the report and mirroring), drawing a small focused example,
and waiting for Enter before moving on (`X` then Enter stops early).
Where `POOLDEMO` is a side-by-side reference sheet, the tutorial is
one concept at a time with the reasoning spelled out next to each.
Safe in a scratch drawing; it draws on the same layers `POOL` uses.

### Versions: `POOLVER`

All three files carry a `MMDDYY REV##` version banner and ship twice
with identical contents — the static name for the APPLOAD stack, and a
dated twin in `releases/` named for its revision
(`POOL_081926_REV01.LSP`, ...). Type **`POOLVER`** in AutoCAD to see
which revision of each is loaded — handy for comparing stacks between
machines. After changing any of the files, bump its banner and
regenerate the twins with `python3 tools/release_lisp.py`.

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
2. Pool shape: `Rectangle` / `Grecian` / `ROman` / `L` / `LAzyl` /
   `Oval` / `OCtagon` / `ROUnd` / `MUtt` — the six common shapes
   first, then the rarely-used ones (type `L` for a true L, `LA` for
   a lazy L, `RO` for a Roman, `OC` for an octagon, `ROU` for a
   round, `MU` for a mutt).
3. Insertion base point.
4. **Every perimeter measurement first** — side lengths, end lengths,
   and the shape's own perimeter letters (an oval's total length and
   end radii, a Grecian's end diagonals and widths, a Roman's `S`/`S1`
   /`V`/`R`, an octagon's `A`/`B` and cut letters, a round pool's two
   overalls).
5. **Then the cross dimensions** *(out-of-square only)*: A-C and B-D
   on a rectangle/oval/Roman/mutt, nine diagonals on an L, and the
   chosen detail level's set on a Grecian or octagon. A round pool
   has no corners, so it is never asked for any.
6. The pool bottom: `Yes`/`No`, then a bottom type
   (`Normal` / `Sport` / `Wedge` / `SLope` / `MOdflat` / `SHallow`;
   L, Lazy L and mutt take the standard hopper only) and that type's
   letters. A round pool takes the oval's bottoms (its `Normal` is the
   radius-end hopper on the sheet).

Nothing about the cross dims appears until the perimeter is complete —
**the guide draws no diagonals while a side length is being asked
for**, so the line you are measuring is never buried under them. They
are added to the guide the moment the last perimeter answer is in.

Any **cross dimension** prompt also accepts `NA` when that measurement
wasn't taken in the field: the fitter simply skips it and the report
shows `N/A` for its target/delta (the as-drawn value is still listed).
An **oval's side lengths** take `NA` as well — the overall and the
width give them back (see *Oval ends*).

### Corner treatments (Square / Radius / Cut / NotGiven)

Every corner question in POOL is the same one, in the vocabulary
`STANDARDS.md` fixes for the whole repo:

```
How should <subject> be treated? [Square/Radius/Cut/NotGiven] <previous>:
```

| Answer | Meaning | Size question |
| --- | --- | --- |
| `Square` | a true sharp corner, nothing cut | none |
| `Radius` | a filleted corner | `Radius for <subject>` |
| `Cut` | a straight chamfer | `Cut face length for <subject>` |
| `NotGiven` | the order sheet never recorded this corner | none — nothing was measured |

The pre-standard words this tool used to ask for — `ROUNDED`, `DIAG`,
`DIAGONAL`, and SPA's `90` — are still accepted if you type them in
full, unlisted, and are normalised to the canonical word before
anything downstream sees them. `NG` is accepted for `NotGiven`.

A remembered size is only offered back as the default when the new
answer **matches** the previous one: a radius is not a cut face, so
24" does not carry across from one to the other.

**`NotGiven` is built square but never drawn as a 90.** Its geometry is
the plain sharp corner, but the sheet marks it with a circled `?` and a
`Not Given` note, so nobody downstream reads it as a measured right
angle. It takes no size, and it does not count as a cut — the
cross-dim reference-mode question below is not asked for it, because
there are no treatment ends to tape to.

Side and end lengths are always measured to the **true (sharp)
corner**; the treatment cuts inward from there.

The same four treatments are offered on **Grecian/Octagon**, **Roman**
and **L / Lazy L** pools, each behind an `Anything to record about the
corners (radius / cut / not given)?` gate that defaults to **No** — square is
always the assumption. What differs per shape is only how the corners
are **grouped**: see [Grecian corner treatments](#grecian-corner-treatments),
[Roman pools](#roman-pools) and [L / Lazy L pools](#l--lazy-l-pools).
Everywhere, an **out-of-square** pool asks each corner independently
(Enter reusing the previous one) while an **in-square** pool asks once
per family of like corners.

* **In-square:** one corner question, applied to all four corners.
  In-square pools also ask each **pair of opposing sides once** —
  side length (top & bottom together), end length (left & right
  together), an oval's end radius (both ends together), and on a
  Grecian each end's two diagonals together — since a true pool's
  opposing sides are equal.
* **Out-of-square:** asked per corner (A, B, C, D); press **Enter** to
  reuse the previous corner's answer, so four identical corners is
  three quick Enters.

When corners are `Radius` or `Cut` **and** the pool is out-of-square,
you're asked where the cross dims were measured from:

| Reference | Meaning | Cross prompts |
| --- | --- | --- |
| **Corner** | To the true (extended) sharp corner | A-C, B-D |
| **Middle** | To the middle of each cut face/arc | A-C, B-D |
| **Ends** | To the treatment endpoints — **both** ends of each diagonal, **crossing** | A-C (A>B end→C>D end, A>D end→C>B end), B-D likewise |

In **Ends** mode the two ties of a diagonal **cross each other**: each
runs from one end of a corner treatment to the *opposite* end of the
far treatment, the way the tape actually goes. (Pairing the same side
at both corners would give two near-parallel ties, which pin the
out-of-squareness down far less.)

The measurements are converted to equivalent true-corner diagonals
(corrected against the fitted corner geometry) so the body still
best-fits correctly, and each cross measurement is dimensioned between
its actual reference points and listed in the report. `Square` and
`NotGiven` corners always use the true corner, so no reference
question is asked.

**Perimeter dims** (per the reference drawing): a rectangle gets
just **two** perimeter dimensions — the **northern** dim (overall
length) and the **western** dim (overall width) — drawn as rotated
linear dims whose extension lines hook to **points on the object**:
the top endpoints of the two side walls and the left endpoints of the
top/bottom walls (the arc-tangent / cut-face ends when corners are
cut). No floating true-corner extension lines. All four sides still
appear in the report table.

**In-square exterior dims follow the field sheets** for the other
shapes too — each letter is dimensioned exactly where (and exactly as
often as) it appears on the reference sheet, instead of dimensioning
every edge:

* **Grecian / Octagon** — 7 dims: `S` + `T` share a row above the
  top side with `B` (tip-to-tip overall) outboard of them; `S1` + `V`
  share a column left of the pool with `A` (the overall) outboard;
  `S2` reads **once**, on the bottom-right corner cut. In square every
  corner is the same corner, so one of each keeps the sheet clean.
* **Roman** — 8 linear dims: `S + T + S` share the top row (S shows
  at **both** ends, per the sheet) with `B` outboard; `S1 + V + S1`
  share the left column (S1 shows at **both** corners) with `A`
  outboard; plus the two end-radius dims. The bottom side repeats `T`
  and is not dimensioned.
* **True Oval** — 3 linear dims: `T` above the top side, `B`
  (tip-to-tip) outboard above it, `A` outside the left arc; plus the
  two radius dims on the arcs. The bottom side and right chord repeat
  `T`/`A` and are not dimensioned.
* **Round** — `B` across the top, `A` up the left side.
* **Mutt** — each end's letters where its home sheet puts them: `S`
  rows above the top with `B` (tip-to-tip) outboard, `S1`/`V` columns
  beside their own ends, `A` outboard left, `S2` on Grecian cuts, `R`
  on the arcs.

**Out-of-square** pools keep their full dim sets — every edge differs,
so every edge is dimensioned; the report table always lists everything
either way.

**Corner dimensions**: an **in-square** pool gets a single "Typ."
callout at the bottom-right corner (B) — a radius dimension reading
`R1'-6" Typ.`, a cut-face dimension reading `1'-8" Typ.`, or, for
square corners, the circled corner mark with a `90° Typ.` leader —
and, for a `NotGiven` corner, a circled `?` with a `Not Given` note.
An **out-of-square** pool whose four corner answers came back
**identical** (Enter reusing the previous corner, typically) collapses
to that same single "Typ." callout — four copies of the same dim are
noise, per the reference drawings. Only when the corners genuinely
**differ** is every corner dimmed individually: radius dims on filleted
corners, face dims on cuts, and the **circled corner mark** on square
corners (a small circle on the corner point with a `90°` leader) —
and a circled `?` plus a `Not Given` note on any `NotGiven` corner.

The **guide updates live**: as soon as the corner answers are in, the
gray guide redraws its corners with the cuts/fillets at their real
sizes (the guide sits on the live measured quad, so nothing needs
display-capping any more), and the dashed cross-dim guide lines are
drawn between the actual reference points for the chosen mode — in
Ends mode each of the four ties is its own line, highlighted
individually as it's prompted. Each cross dim answered then reshapes
the quad under all of them, corners and ties walking along with it.

### Pool bottom / hopper (every shape)

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
  no-pad sport bottom (G = 0) keeps G at zero, so its residual splits
  across F2/F1 instead.

The report shows what you *entered* (or `N/A`) against what was
*drawn*, so any fill or absorption is visible in the delta column.

**Dim placement** (per the field sheet): the H/G/F/E chain runs
below the hopper's vertical centre by **12" or L/6** (two-thirds down
from the top of L), whichever is closer to centre. The M/L/K dims
**attach to the hopper lines themselves** — extension-line origins on
the hopper's right-edge corners and the wall points directly
above/below — with only the dimension **line** floating **30" to the
right** of the hopper's right edge, clear of the hopper linework
(`pool:*mlkoff*` if you want to retune it). Applies to every shape's
hopper and to the sport deep flat.
The hopper's left corners tie to the pool's left corners — when a
corner is `Cut`/`Radius`, **to both ends of the treatment** (one line
per end) — and its right corners tie to the ends of the slope-break
line. When `E` is 0 there is no separate break line (a modified flat
or a wedge), so the right side ties to the pool's right corners under
the same rule: **both ends of the treatment**, never the sharp corner
behind it. Everything is chain-dimensioned along the two centerlines
like the field sheet, and every letter gets a report row.

**`H`, `M` and `K` suggest each other.** They are usually the same
offset, so once one is entered the next offers it as a default —
press Enter to accept, type a number to override, `NA` as always.
(Sport bottoms do the same between `M` and `K`.)

**Oval (True Oval sheet):** same phase, prompting the interior letters
only (A, B, R1, R2 come from the perimeter). The hopper is a box with
a radius **R3** left end set out along the pool axis (arc tip to arc
tip): `H` tip→hopper tip, `G` hopper length, `R3` end radius, `E`
break→right tip, `M`/`K` top/bottom offsets, with `F`, `L` and `T`
(straight side) reported as checks. No left ties — the radius is the
end; the right corners tie to the break ends.

**`R3` and `W` may both be `NA`.** They close against the hopper
length (`R3 + W = G`):

* **`R3` `NA`** → half the hopper width the `M`/`K` offsets leave
  (`L/2`) — the semicircular end that meets the straight sides on a
  **tangent**, no kink;
* **`W` `NA`** → whatever the geometry gives, `G − R3`, so the flat
  top runs from the arc's tangent point to the hopper's right edge.

Both are reported against what was drawn, so a `W` you did measure
still shows up as a check even when `R3` set the arc.

**Grecian:** first asks **`Hopper type [Square/SIX-sided]`**, interior
letters only (A, B, S, S1, S2, T, V come from the perimeter). Both
anchor `H`/`E` off the end walls and `M`/`K` off the sides. The square
hopper is the rectangle letter set; each hopper left corner ties to
**both ends of its pool corner cut** (to D and LT, and to A and LB).

The **6-sided** hopper cuts the deep pad's left corners, and asks
**`SIX-sided corners measured by [Offsets/Letters]`** — the two ways
the corner detail gets taped in the field:

* **Offsets** — offsets shot from the walls only: the pad's left
  edge sits `H` off the left end, its top/bottom flats `M`/`K` off
  the sides, and the **cut faces are the pool's corner cuts offset
  inward** by one more measurement (`NA` = same as `H`). Every hopper
  line is **parallel to its wall** and the corners land wherever
  adjacent offset lines intersect. The faces are dimensioned square
  off the pool cuts at their offset.
* **Letters** — the field-sheet letters `W`/`X`/`L`/`L1` on top of
  the usual `G`/`M`/`K`: **`W` is the flat**, cut corner to the pad's
  right edge, along the top/bottom lines; **`L1` is the left edge
  length**, centred on the pad (the cut drop per corner is
  `(L − L1)/2`); **`X` is the cut face, a check** against
  `√((G−W)² + ((L−L1)/2)²)` — off by more than ½" flags the rows red
  with a note. The flats and left edge still ride their wall-offset
  lines (parallel), but the **cut faces just connect the corners and
  need not be parallel** to the pool cuts. `W` longer than `G`, or
  `L1` longer than `L`, is floored and flagged.

Either way the pool cut ends tie to the matching hopper corners, and
the report shows each letter (or the cut offset) against what was
drawn.

### Special bottoms: wedge, slope, modified flat, sloping shallow end

Rectangle, oval and Grecian pools ask **`Bottom type
[Normal/Sport/Wedge/SLope/MOdflat/SHallow]`**; **L and Lazy L pools
take the standard hopper only** and are not asked. The four special
bottoms are the **standard hopper's plan language** — the same
`H`/`G`/`F`/`E` + `M`/`L`/`K` chain, deep-end line, slope break and
corner ties — with `G` and/or `E` pinned to zero, plus the side
profile the style implies. They work in square and out of square,
because the chain is measured off the walls the same way either way.

| Style | Plan | Profile |
| --- | --- | --- |
| `Wedge` | `G` = 0, `E` = 0 — a deep **line** at `H`, corner ties to the pool corners, floor rising to the far wall | wall → deep at `H` → straight up to the far wall |
| `SLope` | `G` = 0 — deep line at `H`, rising to a full-width break, then flat | wall → deep at `H` → back to wall depth at the break → flat |
| `MOdflat` | `E` = 0 — one flat pad inset `H` / `G` / `F`, corner ties at **all four** corners, no shallow flat | wall → deep at `H` → flat for `G` → up to the far wall |
| `SHallow` | the full hopper, unchanged | as the hopper, but the shallow floor slopes from `C2` at the break up to `C` at the wall |

`Wedge` and `SLope` prompt `H F M L K`, `MOdflat` prompts `H G F M L
K`, `SHallow` prompts the full `H G F E M L K`; the pinned letters are
not asked, not dimensioned and not reported. The slack member that
absorbs a chain mismatch follows the style: `G` where there is a pad,
`F` where the deep end is a line. `NA` works throughout, as always.

Each of these also asks its depths — `C` wall height and `D` deep
depth, plus `C2` (depth where the shallow floor meets the break) for
`SHallow` — with a nominal section drawn under the plan so the depth
prompts highlight a tie just like the plan letters do. The finished
section is drawn below the pool with its own `C` / `D` / `C2` dims.

**A `Normal` hopper with `G` = 0 becomes a slope bottom automatically**
— the G prompt accepts zero, and when it resolves to nothing you are
asked for `C` and `D` and the side view is drawn. Selecting `SLope`
explicitly does the same thing up front.

The oval's ends are arcs rather than corners, so its special bottoms
skip the left corner ties; a Grecian ties to **both ends of each
corner cut**, the way its own hopper does.

### Sport bottoms and the side profile

A Sport bottom is a symmetric full-width profile: shallow flats
`E2`/`E1` at each end, slopes `F2`/`F1`, and a flat deep section `G`.
**Answering `0` at the G prompt draws the sport with no hopper pad** —
the two slopes meet at a point (the V bottom) — so there is no
separate NOhopper bottom type; it's just a zero G.

Sport bottoms are drawn in the **plan like a standard hopper** (per
the reference drawing): full-width break lines at the outer breaks,
the **deep flat as a rectangle inset M/K from the side walls**, and
corner diagonals tying the outer breaks to the deep-flat corners. The
letters are dimmed **on the pool floor in the plan** with the
standard-hopper placement rules — the E2/F2/G/F1/E1 chain below the
deep flat's centre (12" or L/6), the M/L/K chain 12" right of its
right edge — so sport prompts now include `M`, `L`, `K` (all NA-able;
L absorbs against the width). The **side profile** still draws
underneath, carrying only the `C` and `D` depth dims. With **G = 0**
(typed, or a `NA` G whose remainder comes out to nothing) the deep
flat collapses to the single V line and the G dim/report row are
skipped — the no-pad drawing.

`Normal` hoppers are **plan-only** — no heights are asked and no
profile is drawn (unless `G` comes out at 0, see above). The side
profile belongs to the Sport and special bottoms, whose field sheets
are profiles.

**L / Lazy L pools** get the standard hopper in the **main section**:
the virtual corner D' (where the left side meets the main-top line)
closes the main rectangle A-B-C-D', the usual H/G/F/E/M/L/K letters
anchor off its walls, the slope break spans the main section only,
and the hopper's left corners tie to A and D'.

**Cross dims are drawn in the `CROSS DIMENSIONS` dim style** when the
drawing has one (see *Dimension styles* below) — ByLayer, no
per-entity color/linetype/lineweight override, so their look comes
entirely from that style and the `DIMENSION` layer, same as every
other dim the routine draws.

### In-square vs out-of-square

The very first prompt asks whether the pool is in-square. **In-square**
skips every cross dim (and the guide's diagonals): the shape is built
true to the side, end, diagonal and width measurements — a perfect
rectangle, oval, Grecian or L. Use it when the pool was formed square
and you only need the outline dimensioned. **Out-of-square** is the
full workflow: cross dims are prompted, the shape is best-fit to them
within tolerance, and the target/actual/delta report (including, for a
rectangle, the exact `TRI CHECK B-D` row) is produced.

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

**Corner treatments:** after the letters (and cross dims) are in --
before the floor -- a Roman asks **`Anything to record about the
corners (radius / cut / not given)?`** (default No). Square is the assumption; answering Yes
opens the treatments on the four **true corners A/B/C/D**, where a
side runs into an end line above or below the arc's corner drop. The
arc springs are not offered: a spring is a shallow line-to-arc kink,
not a corner anyone radiuses.

* **In-square** asks **once**, for `all four corners`.
* **Out-of-square** asks **each corner on its own**, A through D, with
  Enter reusing the previous corner's answer.

The `S1` stubs then spring from the **treatment ends** rather than the
sharp corners behind them, so a rounded corner shortens its stub
instead of hanging off it. Sizes are capped at half the side **and at
the `S1` corner drop**, so a treatment can never run past the arc
spring below it. Side dims still read to the TRUE corners; the drawing
gets one `Typ.` callout in square (and out of square too, when Enter
reused one answer all the way round), otherwise a radius or face dim
per treated corner. The report lists the sizes.

### Mutt pools (mixed ends)

Field pools don't always match one sheet — a Roman deep end shows up
on a Grecian shallow end, a Grecian deep end on an oval shallow end,
and so on. The **`MUtt`** shape is a rectangle body whose two ends
are picked **independently**: it first asks the **DEEP end (left)
style** and the **SHALLOW end (right) style**, each one of:

* **`Square`** — a plain wall (the rectangle end);
* **`Grecian`** — corner cuts: `S` setback along the sides, `S1`
  drop down the end, `S2` cut face (check);
* **`ROman`** — `S1` corner stubs with an arc bulging `S` past the
  end line (`V` between the springs, `R` as a check, either derivable
  from the other);
* **`Oval`** — a full-width arc (`R`, `NA` = half round).

The guide redraws itself in the two chosen styles, then asks **`B` —
the tip-to-tip overall** and **`A` — the overall width** followed by
each end's own letters (only the letters its style uses). Every
letter closes against the overalls exactly as on its home sheet
(`S1+V+S1 = A`, an `NA` Roman `S` derived from `R`, an oval `R`
smaller than `A/2` drawn as a half round and flagged), and the body
length is **what's left of `B`** after the end bulges — a Roman or
oval end spends its bulge out of `B`, a Grecian or square end spends
nothing. Ends that can't close positive are adjusted, flagged red in
the report and listed in the notes, same as everywhere else.

Out-of-square mutts take the Roman route: body cross dims `A-C` /
`B-D` (NA-able, drawn dashed) fit the body, and the ends are built
onto the fitted body. The report shows `OV B` / `OV A`, the derived
side length, and one lettered block per end (`DEEP S1`, `SHAL R`, …).

**Bottom:** the standard pipeline (`Normal` / `Sport` / `Wedge` /
`SLope` / `MOdflat` / `SHallow`), anchored **tip to tip** — `H` is
taped from the deep-end extreme and the chain closes against `B`,
exactly like every home sheet. The hopper draws square corners with
no corner ties (the ends are too varied to tie the hopper back to).

### Grecian perimeter input (Measured / Overall)

A Grecian asks **`Perimeter input [Measured/Overall]`** **first** —
before any measurement, so you pick how the pool was taped and then
just answer:

* **Measured** — the existing per-edge prompts (body sides, body
  ends, each end's diagonals and width).
* **Overall** — the overall field sheet, with the sides **assumed
  symmetric**: `B` overall length and `A` overall width (required),
  then `T` top side, `S` corner-cut run along the side, `S1`
  corner-cut drop down the end, `V` end width, `S2` cut face — each
  `NA`-able. The letters close against the overalls (`S+T+S = B`,
  `S1+V+S1 = A`), and an `NA` is derived from its partners. `S2` is a
  check against √(S²+S1²). The derived edge set
  feeds the normal pipeline, so cross dims, fitting, hoppers and the
  report all work as usual, with `OV` report rows showing each sheet
  letter against the fitted shape. The guide shows the sheet's ties
  (B/T/S across the top, A/S1/V down the left, S2 at a cut),
  highlighted as prompted.

**Walls beat corners.** When the letters are given but don't close,
the **wall** measurements are held true and the **corner** ones give
way — `T` wins over `S`, `V` wins over `S1`. The reason is how they
get taped: `T` and `V` run along a wall, so the tape lies flat
against something real and comes back reliable, while `S` and `S1`
only locate the *virtual* sharp corner out past the cut, where there
is nothing to measure to. So a measured `T` is held and
`S = (B − T)/2` is re-derived (likewise `S1 = (A − V)/2` from `V`);
only when the wall is `NA` does the corner letter drive the shape.
The taped `S`/`S1` still appear in the report against what was drawn,
and the routine says at the command line when holding a wall moved
one of them. This usually makes the `S2` check pass too, since a cut
face is itself a wall the crew could tape.

### Grecian cross-dim detail (Simple / Center / Complex)

A Grecian has **8 corners**: the body A/B/C/D plus the angled-end tips
**LT/LB** (left-top, left-bottom) and **RT/RB** (right-top,
right-bottom). **Once the whole perimeter is in**, an out-of-square
Grecian asks how many cross dims you have — the more you give, the
more tightly the shape is pinned down — and only then are those
diagonals drawn on the guide and measured. Any cross dim may be
answered `NA`.

| Level | Cross dims | What it adds |
| --- | --- | --- |
| **Simple** | A-C, B-D | The two body diagonals (the original behaviour). |
| **Center** | 14 ties | Simple plus: the long tip-to-tip diagonals (LB-RT, LT-RB), the tip-to-tip runs down the top and bottom (LT-RT, LB-RB), the **X over each end cut** (D-LB & A-LT on the left, RB-C & B-RT on the right), and each tip to the **far** body corner (B-LT, C-LB, A-RT, RB-D). |
| **Complex** | all 18 diagonals | Every possible diagonal among the 8 corners — everything Center has plus the four remaining long ties (A-RB, B-LB, RB-LT, RT-D). Supply what you measured and `NA` the rest. |

All 8 corners are then **best-fit** against every provided cross dim
(sides/ends held within 1", end diagonals within ½", end widths near
exact, cross dims pulled to target within 2"). The **tip-to-tip
widths `LT-RT` and `LB-RB` are the exception**: they are what `A`/`B`
would be on an ideal Grecian, so when measured they are **held like
walls** (the 1" edge band, wall priority) rather than pulled like
cross dims — exactly as the body-end chords `A-D` and `B-C` already
are. A tip width the walls can't honour within 1" holds the tape and
flags the run instead of silently splitting the difference. `NA`
leaves them free as before, and they keep their `CROSS DIMENSIONS`-
style dim and report row like any tie. If the cross dims
can't be met the edges are held true and **`CROSS DIMS FAILED`** is
reported — same policy as the rectangle. Every cross dim is
dimensioned (in the `CROSS DIMENSIONS` style when present) and listed
in the report table (`X A-C`, `X LB-RT`, …) with target/actual/delta.

### Grecian corner treatments

After the perimeter (and cross dims) are in — before the floor — a
Grecian asks **`Anything to record about the corners (radius / cut / not given)?`**
(default No). Square is the assumption, but plenty of pools round
those corners, so answering Yes opens the same `Square` / `Radius` /
`Cut` / `NotGiven` treatments the rectangle and the L use.

The 8 corners come in **two families**, and that is how the answers
are grouped:

* **BODY corners A/B/C/D** — where a long wall runs into a cut face.
* **END TIPS LT/LB/RT/RB** — where that cut face lands on the end wall.

**In square** each family takes **one answer**: the body corners
first, then the tips, with Enter on the tip question reusing the body
answer (a pool that rounds one usually rounds both). **Out of square**
every corner is asked **on its own**, round the perimeter A → B → RB →
RT → C → D → LT → LB, Enter reusing the previous corner — the same
split the rectangle makes between its in-square and out-of-square
corner questions.

Sizes are capped so treatments can never overlap and fold a wall: the
body answer is budgeted half the shortest wall it touches (which
leaves the other half of every cut face free), and each tip is then
capped by what the body cut actually **left** on the cut face they
share, halving the end wall the two tips on it share with each other.
Because a Grecian's corners are **135°, not 90°**, the shape is fit
*before* the corner questions so those budgets use the real fitted
angles — the same reason the L fits first (see below).

Perimeter walls are drawn between the treatment ends with an arc or
cut face closing each corner; the two dashed **internal end
chords** `A-D` and `B-C` stay on the true corners, since they are
construction lines rather than walls. Edge dims still read to the TRUE
corners. The drawing gets one `Typ.` callout per family in square
(and one for the whole ring when every answer came back the same),
otherwise a radius or face dim per treated corner; the report lists
`BODY CORNER` / `END TIP` sizes in square and per-corner sizes out.

Note the ordering: unlike the rectangle, a Grecian asks its corners
**after** its cross dims (the fit has to come first), so there is no
"cross dims measured from Corner/Middle/Ends" question — its cross
dims always read the true corners. The L pool works the same way.

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

**Corner treatments:** after the perimeter (and cross dims) are in —
before the floor — both L types ask **`Anything to record about the
corners (radius / cut / not given)?`** (default No). Answering Yes asks the
**OUTER corners** once (`Square` / `Radius` / `Cut` / `NotGiven`,
one answer for all five) and then the **INNER corner (E)**
separately, since it is typically different — Enter reuses the outer
answer. Sizes are capped so treatments can never overlap and fold a
wall, the cuts are drawn exactly like the rectangle's (fillet arcs /
cut faces, correct at the 45° bend corners and at the reflex
inner corner), side dims still read to the TRUE corners, and the
drawing gets one `Typ.` callout on an outer corner plus the inner
corner's own radius/face dim. The report lists both sizes.

**Corners that aren't 90°.** How far a treatment eats along its two
walls depends on the corner's actual angle — a `Radius` corner sets
back `r / tan(angle/2)`, so a 60° corner reaches **1.73 × its radius**
while a 135° one reaches only 0.41 ×. On an L that matters in normal
use, not just in pathological cases: a Lazy L bends 135° at B and E
even in-square, and **out of square every corner drifts off 90°**. So
the body is fit *before* the corner questions are asked, and the size
cap is computed from the real fitted angles — against the sharpest of
the five outer corners, since one answer covers them all. The inner
corner E is then capped by what the outer cuts actually **left** on
its two walls. (The rectangle keeps the plain 90° assumption: it asks
its corners before its cross dims, so its true angles aren't known
yet — and a pool still called a rectangle sits within a degree of
square anyway.)

**Hopper vs. the deep-end wall:** A and F — the two corners on the
main section's left (deep-end) wall — are real pool corners, so when
the outer treatment cuts them the hopper's left-corner ties land on
**both ends of that cut**, exactly like the rectangle, instead of the
sharp corner behind it. The inner corner (E) is not touched by this:
the hopper's virtual break frame meets E from a different direction
than E's own real neighbour, so it stays square there regardless of
the inner corner treatment.

**Mirroring — the hopper stays on the left.** Once every dimension is
in, the L pools ask **`Mirror the pool [Yes/No]`**. Answering Yes
flips the finished pool, its dimensions and its hopper **top to
bottom**, about the pool's horizontal centreline.

Top-to-bottom rather than left-to-right, because an L's deep end is
always the end **away from the wing**: flipping left-to-right would
swing the wing across and carry the hopper over to the right-hand side
of the sheet with it. Flipping top-to-bottom swaps which way the wing
points instead — the other of the two L orientations that keep the
deep end on the left — so the hopper stays where the convention wants
it.

Text stays readable (`MIRRTEXT` is forced off and restored), the
report table is written afterwards and so is never mirrored, and the
**side section is deliberately left out of the flip**: it is a
*longitudinal* view, and turning the plan upside down does not change
it. (A section only appears on an L when `G = 0` makes it a slope
bottom.)

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
(or 45°-jointed) shape. The two-triangle check is a rectangle-only
computation and is not made for L pools.

**In-square lazy L — deep end held, the wing gives.** Field side
lengths never quite close, and letting a best-fit absorb that error
would bend the corners, breaking the pairs that must read parallel
(**A-B ∥ E-F** and **B-C ∥ D-E**). So the in-square lazy L is not
relaxed at all, it is **built**:

* the main section — **A-B, E-F and F-A** — is held **exactly** and
  comes out a true rectangle (A-B and E-F dead horizontal, F-A dead
  vertical, square corners at A and F). That is the deep end, and it
  is the frame the **hopper** is measured off, so it is the part that
  has to be right;
* the bends **B-C** and **D-E** stay on the 45° heading, so they stay
  parallel to each other whatever happens;
* the only freedom left is how far C and D slide along those bend
  lines, and it is spent spreading the closure error over the three
  **wing** sides in the least-squares sense — B-C and D-E give up
  half of it each (one grows exactly as much as the other shrinks)
  and C-D takes the rest.

Parallelism is perfect by construction, and the error lands where a
lazy L can carry it. Earlier revisions walked the whole chain
A→B→C→D→E at exact headings and dropped F onto the left wall, which
piled every inch of closure error into **E-F and F-A** — the deep-end
sides, the two that must not move.

**And a tape that misses by feet is an error, not a fit.** Whatever
the fit could not hold to within the 1" side tolerance is called out
rather than absorbed quietly: those sides are **dimensioned in red**,
their report rows are red, and **`SIDES DO NOT CLOSE - <sides> OFF THE
TAPE, RE-MEASURE`** is written under the table (with the same warning
at the command line). Six sides that miss each other by a foot are not
a pool that got drawn slightly small — they are a measurement to go
back and take again.

### Guided input

As soon as the shape is chosen, a gray "guide" pool of that shape
(with corner labels) is drawn at the base point and the view zooms to
it. The pool outline is drawn solid in **gray**, while all
**cross dims (and other measuring lines) are WHITE and DOTTED**, so
the diagonals read clearly over the shape even on the L pools where
nine diagonals cross the body. The dot pattern is defined in inches
by the routine itself and scaled to cancel the drawing's `LTSCALE`,
so it looks the same in any drawing (no dependency on `acad.lin`
being found, which used to make the pattern silently fall back to
continuous).

**The guide is live** (the way an OASIS preview redraws before every
question): it starts at a familiar nominal size, and every accepted
answer reshapes it on the spot — type the bottom side and the box
stretches to it, give an oval end radius and that end's bulge follows,
answer a cross dim on a rectangle and the guide leans out of square
exactly the way the final fit will hold it. Values not yet given are
filled with the same derivations the drawing pass will use (an
unanswered side borrows its partner, a Grecian letter falls back to
the overall sheet's split, an oval end without a radius is a
semicircle), and the view follows the reshaped guide so a pool bigger
than the nominal never grows out of sight. `Back` and re-answer, and
the guide snaps to the corrected number.

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

**The guide is drawn in two passes.** While the perimeter is being
measured it shows the outline and corner letters only — no diagonals
at all. When the last perimeter answer is in, the cross dims join it:
one line per measurement on a rectangle/oval, the nine diagonals on an
L, the chosen level's set on a Grecian, the two body diagonals on a
Roman. A shape whose diagonals all appeared at once used to bury the
side being asked for.

### Back: fix a typo without starting over

**Every question in the drawing process offers `Back`** — not just the
measurements, but the keyword questions too: the corner treatments,
the cross-dim reference mode, the Grecian/Octagon input method and
detail level, the Roman's "both ends perfect", the hopper type, the
bottom type. Type `B`, correct the answer, and it carries on from
there.

`Back` **crosses question and stage boundaries alike**: from the first
cross dim it steps back into the corner questions, from those back
into the side lengths, and so on right to the front of the run. Two
`Back`s go back two questions; keep going and you reach the first
question, which simply re-asks itself.

Auto-answered questions are stepped over on the way back (the L pool's
`E` when `H+G+F` already span the section), and everything else
behaves exactly as before — `NA`, `0` where it's legal, and the
`H`/`M`/`K` suggestions. Backing into a stage re-runs it from scratch,
so the guide always matches the answers you can see.

The one limit: `Back` covers the **input phase**. Once the last
measurement is in and the pool is drawn, the answers are committed —
use `U` to undo the whole command.

### Object snaps stay live while you measure

Your own object snaps are **live during every prompt**, including the
insertion base point — so you can snap the pool onto existing
geometry and pick-measure distances off the drawing. Snaps are
dropped only while the routine is feeding points to AutoCAD commands
(where a stray snap would grab the wrong geometry) and your settings
are restored at the end either way.

### Validation: bad numbers can't fold the pool

Field numbers get sanity-checked at every resolution step, and a
value the routine had to adjust is impossible to miss — it warns on
the command line the moment it happens, the affected **dimensions are
drawn red**, the matching **report rows are red**, and a red note is
written under the report table.

* **A bottom chain member that resolves negative** (letters that
  over-sum, an `NA` whose remainder is already spent) is drawn **1'
  long** instead, and the difference comes out of the largest other
  letter — e.g. a negative `G` is drawn at 1' and `F` gives up the
  rest. Both letters' dims and report rows go red, and the report
  says `BOTTOM LENGTHS FAILED`. The chain still closes against the
  pool, so the drawing stays geometrically sane. (Applies to every
  bottom: hopper `H/G/F/E` + `M/L/K`, sport `E2/F2/G/F1/E1`, oval
  and Grecian hoppers.)
* **Grecian Overall / Roman letters** that don't close positive
  against the overalls (`S+T+S = B`, `S1+V+S1 = A`) are adjusted with
  a warning **before** anything is drawn or the bottom letters are
  asked, and the affected report rows are red.
* **Corner treatments** are capped so two treatments can never
  overlap along a shared wall (setback ≤ half the shorter adjacent
  wall); an oversized radius/cut face is re-asked with the maximum
  shown.
* **Depths**: `D` must be deeper than the wall height `C`, and the
  sloping-shallow `C2` must land between `C` and `D` — out-of-order
  answers are re-asked on the spot.
* **Oval hopper closure**: when both `R3` and `W` are measured they
  must close against `G` within ½"; a mismatch turns both red with a
  note.
* Degenerate geometry can't crash a run: parallel construction lines
  fall back safely, and a flat (bulge-zero) end skips its radius dim
  with a message instead of erroring.
* The undo group opens only when the drawing's UNDO is enabled and is
  only closed if it was opened, so `U` after a run — or after a
  cancel — behaves in every drawing.

### Your settings come back

The command turns object snaps off (`OSMODE 0`) and forces
architectural units while it runs, then puts **your** values back —
`OSMODE`, `LUNITS`, `CMDECHO` and the current layer — whether it
finishes, errors or is cancelled. The snapshot of your settings is
kept globally and only taken when no snapshot is pending, so even if
a run is killed hard (crash, Esc at the worst moment) the *next* run
still restores your original snaps instead of accidentally saving the
zeroed state as your preference.

## What it draws

| Layer | Content |
| --- | --- |
| `POOL` | The full pool **perimeter**, running around the whole shape — including the oval end arcs and Grecian corner cuts (individual lines/arcs, i.e. an exploded polyline). Best-fit body: sides held within **±1"**, cross dims within **±2"** of the given values (field measurements carry human error). |
| `POOL-NOTES` | All non-perimeter reference lines, **dashed** (the body end lines under Grecian ends; ovals draw none — see *Oval ends*), plus the report table and its perimeter mini-model. The `DASHED` linetype is auto-loaded from `acad.lin`/`acadiso.lin`; falls back to continuous if neither is found. |
| `DIMENSION` | Aligned dimensions for all sides, cross dims and shape extras. Cross dims are drawn in the **`CROSS DIMENSIONS`** dimension style when the drawing has one (the current style is restored afterwards), ByLayer with no per-entity override; everything else uses the current dimension style. Cross dims answered `NA` are not dimensioned. |

### Dimension styles

**Linear where linear belongs**: a dimension between two points that
sit on the same horizontal or vertical is drawn as a true **linear**
dimension (`DIMLINEAR`, orientation forced so the placement point
can't flip it) — overalls, sheet letters on straight rows/columns,
hopper chains, profile depths. Only a genuinely skewed edge — an
out-of-square wall, a Grecian corner chord, a cut face — is drawn
**aligned** (`DIMALIGNED`).

Three named styles are used when the drawing defines them, and the
previous style is always restored right afterwards:

* **`CROSS DIMENSIONS`** — every cross dim (the diagonal block, on
  any shape). Drawn **ByLayer** — no per-entity color, linetype or
  lineweight override — so the look (dashed or otherwise) comes
  entirely from that dim style and the `DIMENSION` layer, exactly the
  way any other AutoCAD dimension does.
* **`SIDE STANDARD`** — the **secondary sheet letters**: the dims the
  field sheets stack against an overall. Per the reference drawing
  (`examples_of_fully_properly_dimmed_pools...dxf`) that is `S`, `T`,
  `S1` and `V` on Grecians/octagons/Romans/mutts (and every edge of an
  out-of-square Grecian except the overall chords), the Roman/oval
  **end radii**, an L or Lazy L's **wing/step sides** (`C-D`/`D-E`/
  `E-F` on a true L, the bends `B-C`/`D-E` and top `E-F` on a lazy),
  and the six-sided hopper's `W`/`L1`/`X`. The overalls (`B`, `A`, the
  principal walls), the `S2` cut, the corner-treatment `Typ.` callouts
  and the `H/G/F/E` + `M/L/K` hopper chains stay in the standard
  style. A dim inside a `SIDE STANDARD` block **keeps that style even
  under 24"** — the reference shows a 19" `S1` in `SIDE STANDARD`,
  not in inches.
* **`STANDARD INCHES`** — **every other dimension measuring under 2'
  (24")**: corner radii and cut faces, short hopper offsets,
  profile depths. A dimension of exactly 2' stays in the current
  style (`STANDARD`, or `CROSS DIMENSIONS` inside a cross-dim block) —
  the cutover is *under* 24", not *at or under*. The switch happens
  per dimension, keyed on that dimension's own measurement, so a 96"
  side and an 18" cut face on the same pool each get the right style.
  (POOL draws no angular dimensions: a square corner is marked with a
  circled `90°` leader, not a measured angle.)

If a style is missing from the drawing the dimension is simply drawn
in the current style (the routine says so once per run for
`STANDARD INCHES`, then stays quiet). The styles nest correctly — a
small dimension drawn inside the cross-dim block returns to
`CROSS DIMENSIONS`, not to whatever was current before it — and the
style in effect when `POOL` started is restored even if the command
errors out part-way.

### The report and its mini-model

One row per measurement: **MEASUREMENT / TARGET / ACTUAL / DELTA**.

* **TARGET and ACTUAL follow the units the crew works in**: if the
  drawing was in **architectural or engineering units** when `POOL`
  started, they print as feet-inches (`25'-6 1/2"`, to the nearest
  1/16"); a decimal-units drawing gets plain inches (`306.50`).
  (`getdist` keeps only the value, never the text typed, so the
  drawing's own units are the crew's declared preference — `POOL`
  switches the drawing to architectural during its prompts either
  way, so `25'6"` can always be *typed*.) The columns spread out in
  feet-inches mode so the longer strings never collide.
* **DELTA is always plain signed inches** (`+1.00`, `-0.25`) — a
  delta is a small number and reads best that way whichever units the
  lengths are in.

**The corner letters live on a perimeter mini-model to the right of
the report**, not in the corners of the drawing itself. The
mini-model is the pool's outline (arcs and all — a round pool shows
its circle) at a small fixed size, with each corner letter placed
just outside it; the full-size drawing stays clean, and the letters
still read directly against the report rows that name them. When an
L pool is mirrored, the mini-model flips with it, so it always shows
the pool as built.

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

`R1`/`R2` are **true arc radii**: each end arc springs from that end's
two corners (the chord) and bulges past them by the sagitta
`s = R − √(R² − (c/2)²)`, so the radius dimension on the drawn arc
reads back exactly the radius that was typed. An `R` tighter than half
its end width can't span the end, so it is drawn as a semicircle and
flagged in the report.

**Any one of the three end answers may be `NA`.** They close the chain
`s_left + body + s_right = TOTAL`:

* **both radii `NA`** → the leftover splits evenly, i.e. **both ends
  get the same arc** — which is exactly what an in-square oval is, so
  the overall plus the side length is enough on its own;
* **one radius `NA`** → it takes the remainder of the overall;
* **`TOTAL` `NA`** → it is computed from the two radii and reported as
  `N/A` target.

(The total is re-asked, without `NA`, if a radius is `NA` too —
something has to close the chain.) An **in-square** oval asks for the
end radius **once** and uses it at both ends, so "both radii `NA`" is
a single `NA` there. The radii and the overall each get a report row,
so any derived or clamped value is visible.

**The side lengths may be `NA` too** — the same chain read the other
way. A sheet that gives the overall and the width but never taped the
straight side is still complete: each end spends its own bulge out of
the overall and what is left over is the body.

* a radius that **was** measured spends its own sagitta;
* one that wasn't is taken **tangent to the box the pool sits in** —
  the arc meets the sides square, which is the semicircle a true oval
  has — so the side is simply **overall − width**;
* **both sides `NA`** → the body is that length and the oval comes out
  symmetric;
* **one side `NA`** (out-of-square) → the overall pins the **midline**
  between the two ends, so the missing side is the derived body
  mirrored about the one that was taped: a 40'-0" overall on a 20'-0"
  width with a 20'-4" top gives a 19'-8" bottom.

The overall stops accepting `NA` once a side is `NA` (something has to
close the chain), and a side read back this way reports **`N/A`** as
its target like any other measurement that was never taken — the
`ACTUAL` column shows what it came out at.

Nothing is drawn but the pool: the end chords and the old radius
construction lines are gone, so an oval is two side lines plus the two
end arcs. The radius is dimensioned **on the arc, read from outside**
— no dimension running back to the circle centre.

### Octagon

An octagon is the **same eight-corner shape as a Grecian** — same
corners, same edges, same fitting — with the field sheet's own
proportions: the four corners are cut at **45°** (so `S` = `S1`) and
the short flats match the cut faces, where a Grecian's ends are long
and shallow. It therefore inherits everything the Grecian has: the
cross-dim levels, the best-fit, the hoppers.

Its guide is a **regular octagon** — equal sides all round, the way
the shape actually looks — rather than a stretched one.

It uses the **overall sheet** by default (press Enter at the input
prompt), and **`A` and `B` alone are enough to draw it** — every cut
letter may be `NA`:

* both cut letters `NA` → the cuts come out at 45° with
  `c = min(A,B) / (2 + √2)`, which makes **all eight sides equal** on
  a square octagon (`A` = `B`) and keeps the short flats equal to the
  cut faces on an elongated one;
* any letter you *did* measure still wins and derives its partner
  (`S+T+S = B`, `S1+V+S1 = A`), exactly like the Grecian sheet;
* `S2` (the cut face) is a check against √(S²+S1²).

**In square**, an octagon is square, so `A` and `B` are the same
measurement and the overall is asked **once**. This is an octagon
rule only — a **Grecian is always asked for both overalls**, in square
or not, since its length and width are never equal.

### Round

A round pool is a **circle when it is in square** and an **ellipse**
when the two overalls disagree — `B` across and `A` up, both measured
through the middle. There are no corners to best-fit, so the perimeter
is drawn exactly to the overalls. **In square**, one prompt: `A` and
`B` are the same measurement.

The interior is the **True Oval hopper / sport bottom** set, measured
off the pool's own extremes — `H` from the left edge, `E` to the right
edge, `M`/`K` off the top and bottom — so `H+G+F+E = B` and
`M+L+K = A`, exactly like the field sheet. The hopper's radius end and
its full-width slope break draw the same way they do in an oval.

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
