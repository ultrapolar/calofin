# HONEFILLET — The sizes between the ones SMARTFILLET offers (AutoLISP / AutoCAD 2018+)

`SMARTFILLET` draws the corner at every 6-inch radius that fits and cuts
the one you click. Most of the time one of those **is** the answer.
Sometimes it is not — the corner wants something between two of them,
and a 6-inch step is the wrong ruler for that job.

HONEFILLET is that second look. It is SMARTFILLET as far as the fan, and
then instead of cutting the one you click it asks for **two**, either
side of the size you want, and redraws just that range in half inches.
Click one of those and it is cut and dimensioned exactly as SMARTFILLET
would have cut a round one — `R13.5` lettered as `R13.5`, not rounded to
suit the tool that drew it.

## What it does

1. **Select the two lines that make the corner.** Click each one on the
   side you want **kept**, exactly how `FILLET` reads a pick: what lies
   beyond the corner is trimmed away. Only straight `LINE`s — a
   polyline is refused with a line saying so, and the prompt comes back.
2. **The coarse fan is drawn** — `6` up in `6`s plus the `3` and the `9`
   in `hn:*extras*`, every radius that leaves both legs something to
   stand on. This is the menu to **bracket from**, not the menu to cut
   from; nothing here gets cut, and the routine says so.
3. **Click the two the answer sits between.** Either order. They have to
   be *neighbours*: the range has to be short enough to draw at half
   inches, and a pair too far apart is told so and asked again rather
   than quietly truncated halfway or honed at a coarser step. Clicking
   one corner twice is no range at all and is asked again too.
4. **That range comes back in half-inch steps**, both ends included — so
   settling back on the round number is still one click, and the second
   look never takes the first look's answer away. The **whole inches are
   solid and the halves dashed**, which is the fan saying which of them
   is a size nobody will have to think twice about.
5. **Click the one you want.** The previews go, the corner is filleted
   for real at that radius, and the arc gets a **radius dimension** —
   leader out along the line from the arc's centre through the corner,
   the one direction clear of both legs, on the `DIMENSION` layer.
6. **It then offers the same radius for the rest of the corners**: two
   lines per corner until `Done`. A corner too short for that radius is
   named and left alone rather than filleted at something else. As soon
   as one repeat is cut the single callout is re-lettered
   **`R13.5 Typ.`**, which is how the radius would be lettered by hand —
   one number on the sheet, not one per corner.

Telling one preview from the next is the whole job of both fans, and it
matters more here than it does in SMARTFILLET: half an inch of radius is
a hair's difference on screen. So three things do it at once. Each fan
is graded **light green to dark green** with the radius (`hn:*shade-lo*`
→ `hn:*shade-hi*`, true colours). Every arc is **part transparent**
(`hn:*trans*`), so the ones crossing underneath still read. And each
label is drawn in **its own arc's shade**, then set one rung further off
the leg than the label before it on that side — at half an inch a step
there is no room side to side at all, so the labels climb instead of
colliding.

The whole run is one undo group: a single `U` puts every corner back and
takes the dimension away.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `HONEFILLET.lsp`. Add it to the *Startup Suite* to have it in
   every drawing. It is self-contained — SMARTFILLET does not have to be
   loaded for it to work.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `HONEFILLET` | Preview the radii that fit a corner, bracket two of them, redraw between them at half inches, cut the one clicked and dimension it |
   | `HONEFILLETVER` | Print the version |

   It is also on the LazPanel launcher, under **Layout**.

## Tunables

`setq` these after loading (in a startup file, say) when a drawing works
at a different size:

| Variable | Default | Meaning |
| --- | --- | --- |
| `hn:*first*` | `6.0` | Smallest radius in the **coarse** fan — the one that is only there to bracket from |
| `hn:*step*` | `6.0` | Step between those. SMARTFILLET's own, because bracketing from a different set of sizes than the one just looked at is a trap |
| `hn:*extras*` | `'(3.0 9.0)` | Radii offered **besides** that series, drawn dashed. `nil` = the series alone |
| `hn:*maxshown*` | `10` | Most coarse previews on screen at once. `nil` = every radius that fits |
| `hn:*fine*` | `0.5` | **The honing step** — what the range between the two bracketed sizes is redrawn at. Half an inch is where a radius stops being a size somebody could have meant and starts being a number |
| `hn:*maxfine*` | `14` | Most honed previews at once, and so also what *neighbouring* means here: a full 6" bracket comes to 13 half-inch steps, so 14 admits any two neighbours and turns away a pair with a whole size between them. Raising it widens what may be bracketed; it does not make the result any more readable |
| `hn:*fit*` | `0.98` | How much of the shorter leg a fillet may use up. `1.0` would put the tangent point exactly on the far end and leave a zero-length line behind |
| `hn:*layer*` | `"HONE FILLET PREVIEW"` | Layer the previews are drawn on |
| `hn:*color*` | `3` | The layer's colour, and the fallback index on every preview, so a preview reads as a preview even where a true colour cannot be shown |
| `hn:*shade-lo*` | `'(190 255 190)` | RGB of the **smallest** preview… |
| `hn:*shade-hi*` | `'(0 110 0)` | …and of the largest. Both stay green on black; a light-background drawing wants the pair swapped round |
| `hn:*trans*` | `40` | Per cent transparency on every preview, so an arc crossing another still reads. `0` or `nil` = solid |
| `hn:*ltype*` | `"DASHED"` | The dashed previews' linetype, created at pool scale when the drawing has none by that name |
| `hn:*ltscale*` | `0.25` | Per-arc linetype scale on those. The stock `DASHED` pattern is 18 units long, so a short fillet arc would come out as one unbroken dash. `nil` leaves the arcs at the drawing's own `LTSCALE` |
| `hn:*label*` | `T` | Letter each preview `R12`, `R13.5`… |
| `hn:*txthgt*` | `3.0` | Height of those labels — smaller than SMARTFILLET's, because `R13.5` is two characters longer than `R12` and the honed fan sets them half an inch apart |
| `hn:*rung*` | `1.4` | How many text heights further off its leg each label sits than the one before it on that side. This is what carries the honed fan; side to side there is no room at all |
| `hn:*dimlayer*` | `"DIMENSION"` | Layer the radius dimension goes on |
| `hn:*smalldim*` | `24.0` | Radii under this are dimensioned in… |
| `hn:*smallstyle*` | `"STANDARD INCHES"` | …this dimension style, when the drawing has it — POOL's small-dimension rule, so a fillet callout matches the dims beside it |
| `hn:*dimoff*` | `nil` | How far past the arc the dimension text sits. `nil` = one radius, and never less than 12 |
| `hn:*dimrepeat*` | `nil` | Dimension every repeat corner too. The default is one callout plus `Typ.`, which is how the sheet reads |
| `hn:*typ*` | `T` | Re-letter that one callout `<> Typ.` once a repeat has been cut at the same radius |
| `hn:*minang*` | `0.02` | How far off straight (radians) two legs must be before there is a corner at all |

## Notes & limitations

* **Two straight `LINE`s only.** A polyline corner is not filleted —
  explode it first. Arcs, splines and blocks are refused the same way.
* **Which side survives comes from where you clicked**, as in `FILLET`.
  The two lines need not touch: where they cross is worked out from the
  lines extended, so a corner that has to be reached for is previewed
  and cut like any other.
* **"Neighbouring" is a number, not a judgement.** It is
  `hn:*maxfine*` — how many honed previews can be on screen at once —
  and the message says which pair failed it and by how much. Widening
  `hn:*maxfine*` widens what may be bracketed, but a fan of forty arcs
  half an inch apart is not more information, it is less.
* **Both ends of the bracket are drawn.** Honing between `R12` and `R18`
  still lets you cut `R12`: the round numbers are not taken off the
  table by asking to look between them.
* **A corner that takes only one size is turned away at the top.** Legs
  short enough for `R3` and nothing else have no second size to hone
  between, so the routine says so and names `SMARTFILLET` rather than
  drawing a one-arc fan and asking a bracket question that could never
  be answered.
* **The previews are real entities** on their own layer, and they are
  erased on the way out — on a clean finish, on `Cancel`, on Esc, and on
  an error. The empty layer is left behind; a `PURGE` clears it. It is
  HONEFILLET's own layer, not SMARTFILLET's, so a drawing that ran both
  has one to purge per tool and neither can erase the other's work.
* **Enter means different things by design.** At the line prompts it
  takes the offered `Cancel` / `Done` — nothing has been drawn yet, so
  there is nothing to lose. At the three picks it re-asks instead: those
  arcs are thin and half an inch apart, and the near miss that would
  throw a whole fan away is exactly the click those prompts invite.
  `Cancel` is in the bracket, so a mouse-only way out is always there.
* **A missing `STANDARD INCHES` style is not invented.** The callout is
  drawn in whatever style is current and the routine says so once.
* `OSMODE`, `CMDECHO`, `CLAYER`, `FILLETRAD`, `TRIMMODE` and the current
  dimension style are all put back the way they were, whether the run
  finishes, errors, or is cancelled with Esc.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  **AutoCAD LT has no LISP engine and cannot run this file.**

## Tests

`python3 tests/test_honefillet.py` loads the real `HONEFILLET.lsp` into
the repo's AutoLISP VM (`tests/lispvm.py`) and drives `c:HONEFILLET`
with scripted picks: the half-inch arithmetic against numbers worked out
by hand (both ends included, counted rather than accumulated so the last
step is the bracket's own top exactly), the whole-inch/half-inch dashing
rule, the full run through coarse fan → bracket → honed fan → click →
fillet → dimension → clean-up, the bracket picked in either order, both
ends still on offer, the two pairs that get asked again (one corner
twice, and a pair too far apart), `Cancel`, repeats at the honed radius
with the `Typ.` re-lettering, a corner with only one size on offer,
parallel lines, a corner too small to round, and the sysvars going
back.

Add `CALOFIN_LISP_ROOT=shared` to run the same tests against the grouped
build's twin.
