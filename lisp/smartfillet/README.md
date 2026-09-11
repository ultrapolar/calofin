# SMARTFILLET — Fillet a corner after seeing every radius that fits (AutoLISP / AutoCAD 2018+)

`FILLET` wants the radius **before** it shows you anything, so the answer
gets guessed, looked at, undone, and guessed again. SMARTFILLET turns
that round: pick the two lines and every radius that actually fits the
corner is drawn at once, in 6-inch steps plus the two odd sizes that
come up. Click the one that looks right and that is the corner you get —
cut for real, with its radius dimension on it — and the rest disappear.

For the sizes *between* those, see **HONEFILLET** (`lisp/honefillet/`):
same corner, same picks, but you bracket two neighbouring previews and
it redraws the range between them in half-inch steps.

## What it does

1. **Select the two lines that make the corner.** Click each one on the
   side you want **kept**, exactly how `FILLET` reads a pick: what lies
   beyond the corner is trimmed away. Only straight `LINE`s — a
   polyline is refused with a line saying so, and the prompt comes back.
2. **Every radius that fits is drawn**, from `6` up in `6`s — plus the
   `3` and the `9` in `sf:*extras*`, which turn up but are not the usual
   step and are drawn **dashed** where the sixes are solid. One green
   arc per radius, lettered `R3`, `R6`, `R9`, `R12`… A radius makes
   the list only when its tangent point lands on **both** legs (times
   `sf:*fit*`, so a fillet never eats a leg whole), which is what makes
   the fan an answer to *this* corner rather than a fixed menu. At most
   `sf:*maxshown*` are drawn at once; when more fit, the routine says
   how many it left out instead of quietly stopping.

   **Telling one arc from the next is the whole job of that drawing**,
   so three things do it at once. The fan is graded light green to dark
   green with the radius (`sf:*shade-lo*` → `sf:*shade-hi*`, true
   colours). Every arc is part transparent (`sf:*trans*`), so the ones
   crossing underneath still read. And each label is drawn in **its own
   arc's shade**, then set one rung further off the leg than the label
   before it on that side — consecutive tangent points sit one step
   apart along a leg, which is not room for two labels side by side, so
   they climb instead of colliding.
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
| `sf:*extras*` | `'(3.0 9.0)` | Radii offered **besides** that series, drawn dashed. A 3 or a 9 turns up, just not often enough to be the step. `nil` = the series alone |
| `sf:*maxshown*` | `10` | Most previews on screen at once — the 8 sixes that used to show, plus the two extras, so nothing was lost to them. `nil` = every radius that fits, which on a long wall is a great many |
| `sf:*fit*` | `0.98` | How much of the shorter leg a fillet may use up. `1.0` would put the tangent point exactly on the far end and leave a zero-length line behind |
| `sf:*layer*` | `"SMART FILLET PREVIEW"` | Layer the previews are drawn on |
| `sf:*color*` | `3` | The layer's colour, and the fallback index on every preview, so a preview reads as a preview even where a true colour cannot be shown |
| `sf:*shade-lo*` | `'(190 255 190)` | RGB of the **smallest** preview… |
| `sf:*shade-hi*` | `'(0 110 0)` | …and of the largest. The fan is graded between the two, so which arc a label belongs to is a matter of shade rather than of tracing it by eye. Both stay green on black; a light-background drawing wants the pair swapped round |
| `sf:*trans*` | `40` | Per cent transparency on every preview, so an arc crossing another still reads. `0` or `nil` = solid |
| `sf:*ltype*` | `"DASHED"` | The **extras'** linetype, created at pool scale when the drawing has none by that name. The sixes are solid |
| `sf:*ltscale*` | `0.25` | Per-arc linetype scale on those. The stock `DASHED` pattern is 18 units long, so a 6" fillet arc would come out as one unbroken dash. `nil` leaves the arcs at the drawing's own `LTSCALE` |
| `sf:*label*` | `T` | Letter each preview `R6`, `R12`… |
| `sf:*txthgt*` | `4.0` | Height of those labels — small enough that two a 6" step apart clear each other side to side |
| `sf:*rung*` | `1.4` | How many text heights further off its leg each label sits than the one before it on that side. This is what stops `R30` landing on `R36` however tight the steps |
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
  so less of it fits. A corner too short for even the smallest size on
  offer (`R3`, with the stock extras) is reported and nothing is drawn.
* **The shades are true colours (DXF 420) and the transparency is DXF
  440**, both per entity. A viewport with transparency display switched
  off (`TRANSPARENCYDISPLAY 0`) draws the fan solid, which costs it
  nothing but the see-through — the shades and the labels still tell the
  arcs apart.
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
the shorter leg and the turn allow), the candidate list with its extras
merged in and the cap that must say what it hid, the shades, the
transparency and the solid-vs-dashed split, the label ladder that keeps
two labels off each other, the full run through preview → click → fillet →
dimension → clean-up, repeats at the found radius with the `Typ.`
re-lettering, `Cancel`, a polyline and a doubled pick, parallel lines, a
corner too small to round, and the sysvars going back.

Add `CALOFIN_LISP_ROOT=shared` to run the same tests against the grouped
build's twin.
