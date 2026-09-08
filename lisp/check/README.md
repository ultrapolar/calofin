# CHECK — dimension & arc attachment audit (AutoLISP)

An AutoCAD AutoLISP routine (`check_drawing.lsp`) that audits a
drawing for two common drafting errors and fixes them in place,
visually flagging everything it touched.

## Loading & running

1. Load the file: drag `check_drawing.lsp` into the drawing window,
   or use `APPLOAD` (add it to the *Startup Suite* to load it in
   every session).
2. Type `CHECK` (or `DIMARCCHECK`).
3. Highlight the drawing when prompted — window/crossing/`ALL`, any
   normal selection works — and press Enter.

Both audits run over the selection and print a per-entity log plus a
summary on the command line. Everything happens inside a single UNDO
group, so one `U` reverts every change CHECK made.

## Audit 1 — dimensions attached to objects

Every linear/aligned/rotated dimension's two definition points (the
points you actually dimmed) must lie on an object of some kind —
line, arc, circle, polyline, ellipse or spline — **or on an anchor**.
A point two or more dimensions measure to is an anchor: it counts as
an object and is left exactly where it is, geometry under it or not.
Dimensioning twice to the same spot — the pair of dims pinning down a
hypotenuse corner is the everyday case — is how you say that spot is
the object, and CHECK, which shifts without asking, shifts nothing
off it. For a dimension with a point floating in space, CHECK:

* draws a **construction line** (XLINE) through the dimension's two
  original dimmed points on layer `CHECK-CONSTRUCTION` (yellow), so
  you can see what was measured before the fix,
* shifts the stray definition point onto the **closest point of the
  closest object** — or onto a **shared anchor** when one is nearer
  (the measurement text updates unless it is overridden),
* recolors the dimension **red** so you know it has been shifted.

Angular, radial, diameter and ordinate dimensions are not auto-fixed;
they are counted as *skipped* in the summary.

## Audit 2 — arc ends attached to object ends

Every `ARC` entity's endpoints must sit at the **end** of another
object:

| Endpoint situation | Action |
| --- | --- |
| At the end of an object (within tolerance) | OK, untouched |
| On an object, but partway along it | Moved to the **closest end of that object** |
| Not on anything | Moved to the **closest endpoint of any object** in the selection (falls back to the closest point on the closest object when everything nearby is closed, e.g. circles) |
| On a closed object (circle, closed polyline) | Accepted — closed curves have no ends |

A moved arc is re-fitted as the arc through its untouched end, its
old midpoint, and the new endpoint, and recolored **magenta** so you
know it was snapped.

## Colors & cleanup

| Visual | Meaning |
| --- | --- |
| Red dimension | A definition point was shifted onto the nearest object or anchor |
| Yellow XLINE on `CHECK-CONSTRUCTION` | The original points of a shifted dimension |
| Magenta arc | One or both endpoints were snapped |

After reviewing, delete (or freeze) the `CHECK-CONSTRUCTION` layer
and set the flagged entities back to their normal color — or press
`U` once to revert the whole run.

## Tunables

Every value CHECK reads that you might want to change sits in one
`TUNABLES` block at the top of `check_drawing.lsp`, each with a comment
saying what it does, its units, and what raising or lowering it
changes. Edit the value and APPLOAD the file again, or type the `setq`
at the command line to try a value for one session:

```lisp
(setq *cfchk-tol* 0.001)   ; gap size that still counts as "attached"
                           ; (default 0.0001 drawing units)
```

Every knob is read when the command runs, not when the file loads, so
a value set either way is honoured by the next run.

| Global | Default | Meaning |
| --- | --- | --- |
| `*cfchk-tol*` | `1.0e-4` | Gap (drawing units) that still counts as attached; also the smallest shift CHECK bothers to make |
| `*cfchk-anchor-tol*` | `1.0e-4` | How close two definition points must be to count as the same spot |
| `*cfchk-anchor-min*` | `2` | Dimensions meeting at one spot that make it an anchor; 1 or 0 switches the dimension audit off |
| `*cfchk-curve-types*` | `LINE ARC CIRCLE ELLIPSE LWPOLYLINE POLYLINE SPLINE` | Entity types a point or an arc end may attach to |
| `*cfchk-dim-types*` | `(0 1)` | Dimension kinds audited, by DXF 70: 0 rotated, 1 aligned |
| `*cfchk-dim-color*` / `*cfchk-arc-color*` | `1` / `6` | ACI colours for shifted dimensions (red) and snapped arcs (magenta); the report's wording follows them |
| `*cfchk-constr-layer*` / `*cfchk-constr-color*` | `"CHECK-CONSTRUCTION"` / `2` | Where the construction XLINEs go, and the colour the layer is created with (an existing layer keeps its own) |
| `*cfchk-dist-mode*` / `*cfchk-dist-prec*` / `*cfchk-tol-prec*` | `2` / `4` / `6` | `rtos` mode and places for the reported shift distances, and places for the tolerance echoed in the summary |
| `*cfchk-same-pt*` | `1e-8` | Guard: two points closer than this are the same point |
| `*cfchk-planar-eps*` | `1e-9` | Guard: how far an arc's normal may sit off world +Z before it is skipped as non-planar |

Not knobs, on purpose: the collinearity guard inside the circumcenter
helper and the linetype a new layer is created with. Both helpers are
library bodies shared with the grouped build, so they stay literal in
both.

## Limitations

* Works on plan-view (world XY) geometry; arcs drawn in other planes
  are skipped and reported.
* Only entities *in the selection* are used as attachment candidates
  — include the linework, not just the dims/arcs, when highlighting.
* Polyline arc *segments* are not audited (the whole polyline is only
  used as an attachment target); explode a polyline first if its arc
  segments need the endpoint audit.
* A fix can cascade (snapping arc A may slightly move the target arc
  B checks against); run CHECK again until it reports no changes.
