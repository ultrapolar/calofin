# SMARTFILLET — Fillet a corner after seeing every radius that fits (AutoLISP / AutoCAD 2018+)

`FILLET` wants the radius **before** it shows you anything, so the answer
gets guessed, looked at, undone, and guessed again. SMARTFILLET turns
that round: pick the two lines and every radius that actually fits the
corner is drawn dashed, all at once, in 6-inch steps. Click the one that
looks right and that is the corner you get — cut for real, with its
radius dimension on it — and the rest disappear.

## What it does

1. **Select the two lines that make the corner.** Click each one on the
   side you want **kept**, exactly how `FILLET` reads a pick: what lies
   beyond the corner is trimmed away. Only straight `LINE`s — a
   polyline is refused with a line saying so, and the prompt comes back.
2. **Every radius that fits is drawn**, from `6` up in `6`s: a dashed
   green arc per radius, lettered `R6`, `R12`, `R18`… A radius makes
   the list only when its tangent point lands on **both** legs (times
   `sf:*fit*`, so a fillet never eats a leg whole), which is what makes
   the fan an answer to *this* corner rather than a fixed menu. At most
   `sf:*maxshown*` are drawn at once; when more fit, the routine says
   how many it left out instead of quietly stopping.
3. **Click the arc you want.** The previews go, the corner is filleted
   for real at that radius, and the arc gets a **radius dimension** —
   leader out along the line from the arc's centre through the corner,
   the one direction clear of both legs, on the `DIMENSION` layer.
4. **It then offers the same radius for the rest of the corners**: two
   lines per corner until `Done`. A corner too short for that radius is
   named and left alone rather than filleted at something else. As soon
   as one repeat is cut the single callout is re-lettered **`R12 Typ.`**,
   which is how the radius would be lettered by hand — one number on the
   sheet, not one per corner.

The whole run is one undo group: a single `U` puts every corner back and
takes the dimension away.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `SMARTFILLET.lsp`. Add it to the *Startup Suite* to have it in
   every drawing.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `SMARTFILLET` | Preview the radii that fit a corner, cut the one clicked, dimension it, then offer the rest at that size |
   | `SMARTFILLETVER` | Print the version |

   It is also on the LazPanel launcher, under **Layout**.

## Tunables

`setq` these after loading (in a startup file, say) when a drawing works
at a different size:

| Variable | Default | Meaning |
| --- | --- | --- |
| `sf:*first*` | `6.0` | Smallest radius previewed |
| `sf:*step*` | `6.0` | Step between previews |
| `sf:*maxshown*` | `8` | Most previews on screen at once. `nil` = every radius that fits, which on a long wall is a great many |
| `sf:*fit*` | `0.98` | How much of the shorter leg a fillet may use up. `1.0` would put the tangent point exactly on the far end and leave a zero-length line behind |
| `sf:*layer*` | `"SMART FILLET PREVIEW"` | Layer the previews are drawn on |
| `sf:*color*` | `3` | Their colour, as an entity override, so a preview reads as a preview whatever the layer was set to by hand |
| `sf:*ltype*` | `"DASHED"` | Their linetype, created at pool scale when the drawing has none by that name |
| `sf:*ltscale*` | `0.25` | Per-arc linetype scale. The stock `DASHED` pattern is 18 units long, so a 6" fillet arc would come out as one unbroken dash. `nil` leaves the arcs at the drawing's own `LTSCALE` |
| `sf:*label*` | `T` | Letter each preview `R6`, `R12`… |
| `sf:*txthgt*` | `6.0` | Height of those labels |
| `sf:*dimlayer*` | `"DIMENSION"` | Layer the radius dimension goes on |
| `sf:*smalldim*` | `24.0` | Radii under this are dimensioned in… |
| `sf:*smallstyle*` | `"STANDARD INCHES"` | …this dimension style, when the drawing has it — POOL's small-dimension rule, so a fillet callout matches the dims beside it |
| `sf:*dimoff*` | `nil` | How far past the arc the dimension text sits. `nil` = one radius, and never less than 12 |
| `sf:*dimrepeat*` | `nil` | Dimension every repeat corner too. The default is one callout plus `Typ.`, which is how the sheet reads |
| `sf:*typ*` | `T` | Re-letter that one callout `<> Typ.` once a repeat has been cut at the same radius |
| `sf:*minang*` | `0.02` | How far off straight (radians) two legs must be before there is a corner at all |

## Notes & limitations

* **Two straight `LINE`s only.** A polyline corner is not filleted —
  explode it first. Arcs, splines and blocks are refused the same way.
* **Which side survives comes from where you clicked**, as in `FILLET`.
  The two lines need not touch: where they cross is worked out from the
  lines extended, so a corner that has to be reached for is previewed
  and cut like any other. What sets the limit is how far each line
  reaches past the crossing point on the side you clicked.
* **The fan is sized to the corner.** A 90° corner between two 100"
  legs takes radii up to 98"; the same legs 45° apart take 12" — the
  shallower the turn, the further back from the corner the arc starts,
  so less of it fits. A corner too short for even `R6` is reported and
  nothing is drawn.
* **The previews are real entities** on their own layer, and they are
  erased on the way out — on a clean finish, on `Cancel`, on Esc, and on
  an error. The empty layer is left behind; a `PURGE` clears it.
* **Enter means different things by design.** At the line prompts it
  takes the offered `Cancel` / `Done` — nothing has been drawn yet, so
  there is nothing to lose. At the pick it re-asks instead: those arcs
  are thin, and the near miss that would throw a whole fan away is
  exactly the click that prompt invites. `Cancel` is in the bracket, so
  a mouse-only way out is always there.
* **A missing `STANDARD INCHES` style is not invented.** The callout is
  drawn in whatever style is current and the routine says so once.
* `OSMODE`, `CMDECHO`, `CLAYER`, `FILLETRAD`, `TRIMMODE` and the current
  dimension style are all put back the way they were, whether the run
  finishes, errors, or is cancelled with Esc.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  **AutoCAD LT has no LISP engine and cannot run this file.**

## Tests

`python3 tests/test_smartfillet.py` loads the real `SMARTFILLET.lsp`
into the repo's AutoLISP VM (`tests/lispvm.py`) and drives
`c:SMARTFILLET` with scripted picks: the corner geometry against
numbers worked out by hand (crossing point, kept sides, half angle, what
the shorter leg and the turn allow), the candidate list and the cap that
must say what it hid, the full run through preview → click → fillet →
dimension → clean-up, repeats at the found radius with the `Typ.`
re-lettering, `Cancel`, a polyline and a doubled pick, parallel lines, a
corner too small to round, and the sysvars going back.

Add `CALOFIN_LISP_ROOT=shared` to run the same tests against the grouped
build's twin.
