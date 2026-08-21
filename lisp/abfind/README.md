# ABFIND / ABMOVE — tie a point back to the A and B stakes (AutoLISP)

A pool is surveyed off two stakes, **A** and **B**: every point on the
field sheet is two tape readings, one from each stake, and the point is
wherever those two distances cross. These two commands work that way
round.

* **`ABFIND`** — type a point number, get the two ties: an aligned
  dimension from A to the point and one from B to it. Then it asks
  whether that point wants moving, and if you say Yes it runs
  everything `ABMOVE` does before coming back for the next number.
* **`ABMOVE`** — that flow on its own, without the question, for when
  you already know a point is wrong: *if this point is in the wrong
  place, where should it be?* One tape is
  held exactly as it is and the other's reading is walked — a foot at a
  time, ten feet each way, plus every number the reading could have
  been misread as. Each candidate is drawn **yellow** on the POINTS
  layer and tagged by the tape it moves and how far: `1A`, `-3B`.
  Type the tag you believe and the point moves there, renamed, ringed
  and noted — **one point per run**: moving a point is a decision, not
  a sweep, so the command ends as soon as that point is settled.

## What it does

### `ABFIND`

Both stakes are found by name among the survey points, the point by the
number you type, and the two dimensions are drawn the way `CDCALLOUT`
and `CDCREATE` make cross dims:

* dimension style **CROSS DIMENSIONS**,
* layer **DIMENSION** (created if the drawing lacks it),
* ByLayer — any per-entity colour / linetype / lineweight override is
  stripped,
* the dimension line sitting **right on the tie** (nudge
  `abf:*offset*` to push it off).

It prints both readings as it goes:

```
  Pt.17:  A 21'-1"   B 18'-6"  dimensioned.
```

Then it asks:

```
  Move Pt.17 to a different reading? [Yes/No/Back] <No>:
```

**No** (the Enter answer) moves on to the next point number. **Yes**
runs everything under `ABMOVE` below — the readings, the pick, the
move — and then `ABFIND` comes back and asks for the next number.
Either way it keeps going until you press **Enter** at the number.

Nothing is clicked — unless the drawing does not name its stakes (see
below).

### `ABMOVE`

Everything `ABFIND` does, and then the suggestions. One stake's
reading is **held exactly as it is** and the other's is varied; each
pair of distances is crossed back to a position. Two families of
reading are tried:

**The foot sweep.** The moved tape a whole foot out, a foot at a time,
`abf:*foot-steps*` of them **each way** — ten up and ten down as
shipped. A foot is the unit a tape gets miscounted in, so every foot
within reach is worth seeing whether or not the number looks like
another one.

**The look-alikes.** A reading that could be *read* as this one:

| The mistake | `21'-1"` could have been |
| --- | --- |
| the inches lost or gained a leading 1 | `21'-11"` |
| a digit read as a look-alike (`abf:*digit-pairs*`: 1/7, 1/4, 3/8, 3/5, 5/6, 6/8, 0/9, 4/9, 7/9) | `21'-7"`, `21'-4"` |
| two feet digits changed places | `12'-1"` |

Both ways round, as **two groups**: the readings that move **A** (B
held) first, then the ones that move **B**. Nothing further than
`abf:*max-shift*` (10 feet — the reach of the foot sweep) is offered,
and a reading the held tape can no longer reach has no crossing, is
left out, and is counted in a line under the table. A look-alike that
lands on a whole foot (`21'` read as `27'`) is already in the sweep and
is not listed twice.

### Tags

Every suggestion carries a **tag**, which is both its label on screen
and the answer you type. It names the tape that moves and how far:

| Tag | What it is |
| --- | --- |
| `1A`, `2A` … `10A` | A's reading a foot, two feet … ten feet **up** |
| `-1A`, `-2A` … `-10A` | the same **down** |
| `1B` … `-10B` | the same sweep on B |
| `R1A`, `R2A` … | a look-alike reading of A that is not a whole foot out — nearest first, so `R1A` is the closest one |
| `R1B`, `R2B` … | the same for B |

So `-3B` reads "B was three feet less than it says", and `R1A` reads
"A's nearest look-alike". A tag names exactly one place, and it is
what the prompt accepts.

The candidates are drawn on the **POINTS** layer in
`abf:*sug-color*` — **yellow**, as an entity override, so a suggestion
never reads as one of the drawing's own points — each with its tag
beside it, and listed nearest miss first within each group:

```
  Where Pt.17 lands if one tape was read wrong - the ones that move A
  first, then B (nearest miss first):
   tag   held  moved  from          to            the point moves
   ----  ----  -----  -----------   -----------   ---------------
   R1A   B     A      21'-1"        21'-4"        0'-3 7/16" NE
   R2A   B     A      21'-1"        21'-7"        0'-6 15/16" NE
   R3A   B     A      21'-1"        21'-11"       0'-11 5/8" E
   1A    B     A      21'-1"        22'-1"        1'-1 15/16" E
   -1A   B     A      21'-1"        20'-1"        1'-1 11/16" SW
   2A    B     A      21'-1"        23'-1"        2'-4 3/16" E
   -2A   B     A      21'-1"        19'-1"        2'-3 1/8" SW
   ...                                          (out to 10A and -10A)
   -10A  B     A      21'-1"        11'-1"        10'-6 1/2" SW

   R1B   A     B      18'-6"        18'-5"        0'-1 1/8" SE
   R2B   A     B      18'-6"        18'-8"        0'-2 5/16" NW
   1B    A     B      18'-6"        19'-6"        1'-1 15/16" NW
   -1B   A     B      18'-6"        17'-6"        1'-1 3/4" SE
   ...                                          (out to 10B and -10B)
   -10B  A     B      18'-6"        8'-6"         10'-9 15/16" SE
```

Each group also gets **the line it sits on**, dashed and grey. A held
tape is a fixed radius off its stake, so everything that holds it lies
on one arc centred there: the readings that move A all sit on B's arc,
the ones that move B all sit on A's, and the two cross at the point as
it is drawn now. Each arc runs out to the furthest suggestion its
group reaches, either way round. They are scaffolding like the
markers, and go when the round does.

Forty-five rows for this point: twenty sweep steps per moved tape, plus
three look-alike readings of A and two of B, each sitting where its own
miss puts it — an inch out sorts above a foot out, which is why the
`R` tags come first. Fifty readings were generated and five collapsed
into the sweep: `18'` read as `16'` or `13'`, and `21'` read as `24'`,
`27'` or `12'`, are all whole feet the sweep already carries.

The prompt itself stays short — forty-five tags in a bracket would
swamp the command line, so it reads

```
  Move Pt.17 - type a tag from the table [Pick/None/Back] <None>:
```

and every tag in the table is accepted even though it is not listed
there. `Pick` clicks one instead.

Forty-five rows for this point: twenty sweep steps per held stake,
with the look-alike readings (`18'-5"`, `18'-8"`, `21'-4"`, `21'-7"`,
`21'-11"`) sitting where their own miss puts them — at the top of their
group, since an inch out is nearer than a foot. Fifty readings were
generated and five collapsed into the sweep: `18'` read as `16'` or
`13'`, and `21'` read as `24'`, `27'` or `12'`, are all whole feet the
sweep already carries.

Answer with a tag, or `Pick` and click the one you want. `None` (the
Enter answer) leaves the point alone and keeps the two dimensions —
`ABMOVE` has then done exactly what `ABFIND` does.

Either way that is the end of the run. `ABMOVE` settles **one** point
and stops; run it again for the next one. `ABFIND`, which only
measures, keeps asking until you press Enter. Enter at `ABMOVE`'s
point number cancels the run outright.

Pick one and four things happen:

1. a **new point** is made there, numbered `17m` — the original number
   with `abf:*moved-suffix*` on it, so the drawing says plainly that
   this one was moved. It is an `ab_pt` block carrying the new number
   when the drawing has that block, a `POINT` with a text label beside
   it when it does not;
2. the **original point is ringed** with a 5" radius circle on the
   **FGStep** layer, so the spot it came off is still visible — the
   same mark `BPCALLOUT` puts round a bad point;
3. a **note** is written on `FGStep`, naming the tape that moved (the
   one that was *not* held) and both of its readings:

   ```
   Moved Pt.17 B from 18'-6" to 18'-5"
   ```

   Enter tucks it beside the ring; click a spot to put it anywhere
   else;
4. the **two dimensions are redrawn** to where the point now is, so the
   sheet measures the position it is claiming. The old reading is not
   lost — the note carries it.

`Pt.17m` is a survey point like any other once it is made, so the next
`ABFIND` or `ABMOVE` run finds it by its new number.

## Finding the stakes

A and B are looked up by name among the survey points, the same way any
other point is: an `ab_pt` INSERT on any layer or any other INSERT on
the **POINTS** layer, named by its `number` attribute (the classifier
`BPCALLOUT`, `CDCALLOUT` and `LHD` all share). A drawing that does not
name them says so and asks you to **click each one**, once per run,
snapping to the nearest survey point within `abf:*snap*`; a click with
nothing under it is taken as the stake position itself. Enter at that
prompt cancels the run.

## Typing point numbers

Numbers are matched against the same `number` attribute. Type them the
way they read in the drawing — all of these name the same point:

```
35    Pt.35    pt35    PT.35    #35    035    35.0
```

Only the dot right after `Pt` is treated as a prefix — a point
genuinely named `40.5` keeps its decimal. A number that names no point
is reported and the prompt re-asks: **nothing is drawn from a typo**.
When a drawing carries a duplicate number, the first match wins.

## Going back a step

The shared Back convention (see the root README) applies:

* in `ABFIND`, `B`, `BACK`, `U` or `UNDO` (any case) typed at the
  **point number** undoes the whole of the last round — its ties, and,
  if that round moved a point, the moved point, its ring and its note,
  with the original ties put back (`Stepping back one point.`, or
  `Already at the first point.` when there is nothing left);
* `Back` at **`Move Pt.17 to a different reading?`** un-draws that
  point's ties and re-asks the number;
* `Back` at **which suggestion** re-asks the move question — in
  `ABMOVE`, which never asked it, it re-asks the point number instead;
* `Back` at **the note** re-asks which suggestion, with the
  suggestions still on screen.

`ABMOVE`'s first question has nothing to go back to, and once its point
is settled the run is over — to undo that move, `U`.

The whole run is **one undo group**: a single `U` takes it all away.
The dimension style, current layer, `OSMODE` and `CMDECHO` in force
before the command are restored afterwards — on a clean finish, an
error, or Esc.

## Install & run

1. Load `ABFIND.lsp` (`APPLOAD`, or drag it into the drawing). Both
   commands come with the one file.
2. `ABFIND` → `Point number <Enter = done>:` → `17` → the two ties are
   drawn → `Move Pt.17 to a different reading? [Yes/No/Back] <No>:` →
   Enter to move on, or `Yes` to go through step 3 → next number, or
   Enter to finish.
3. `ABMOVE` → `Point number (Enter to cancel):` → `17` → read the table
   (`F2` opens the text window if it runs off the command line) →
   `Move Pt.17 - type a tag from the table [Pick/None/Back] <None>:`
   → a tag such as `-1B`, or `Pick` and click the marker → `Place the
   note for Pt.17 [Auto/Back] <Auto>:` → Enter, and the command is
   done.
4. `ABFINDVER` prints the loaded version.

## Tunables

The constants at the top of `ABFIND.lsp`:

```lisp
(setq abf:*style*        "CROSS DIMENSIONS") ; dimension style
(setq abf:*layer*        "DIMENSION")   ; layer the dims land on
(setq abf:*offset*       0.0)           ; push the dim line off the tie
(setq abf:*point-block*  "ab_pt")       ; the survey point block
(setq abf:*point-layer*  "POINTS")      ; layer whose INSERTs count,
                                        ; and where new points go
(setq abf:*pt-tag*       "number")      ; attribute naming the point
(setq abf:*a-name*       "A")           ; what the two stakes are
(setq abf:*b-name*       "B")           ; numbered in the drawing
(setq abf:*snap*         12.0)          ; click-to-point snap radius
(setq abf:*ring-layer*   "FGStep")      ; ring + note layer
(setq abf:*ring-radius*  5.0)           ; ring RADIUS, inches
(setq abf:*note-hgt*     6.0)           ; note text height
(setq abf:*moved-suffix* "m")           ; Pt.17 -> Pt.17m
(setq abf:*sug-radius*   3.0)           ; suggestion marker radius
(setq abf:*sug-color*    2)             ; suggestion colour: yellow
(setq abf:*sug-hgt*      6.0)           ; suggestion tag height
(setq abf:*locus-color*  8)             ; guide-line colour: grey
(setq abf:*locus-ltype*  "DASHED")      ; and its linetype
(setq abf:*foot-steps*   10)            ; 1-foot steps offered each way
(setq abf:*max-shift*    120.0)         ; furthest a suggestion may sit
(setq abf:*max-sugg*     nil)           ; most per held stake, nil = all
(setq abf:*prec*         4)             ; rtos precision, 4 = 1/16"
(setq abf:*same-eps*     0.125)         ; two suggestions this close
                                        ; are one place
```

`abf:*foot-steps*` and `abf:*max-shift*` work together: the sweep
reaches `12 x foot-steps` inches, and `max-shift` is the hard bound on
*everything*. Shipped they agree at ten feet. Lower `max-shift` to
`24.0` and you get a two-foot list — a foot out either way, the
`1"`/`11"` slip and the look-alike inch digits; the look-alike **feet**
digits (a 3 read as an 8 is five feet, a transposed `21'` → `12'` is
nine) drop out with the rest of the sweep. `abf:*max-sugg*` caps each
**group**, not the pair of them, so shortening the list never costs you
one of the two answers.

## Notes & limitations

* Drawing units are **inches** (architectural), and plan north is `+Y`
  — the compass letter in the table is read off that.
* The two readings `ABMOVE` varies are the distances **as drawn**, not
  what the field sheet says; the routine has no access to the sheet. If
  the point was plotted by least squares (`ABCDEF`) rather than by
  crossing two tapes, the drawn distances are the fitted ones and the
  readings shown will be a hair off what was written down.
* Naming a stake as the point is refused — the ties are measured *from*
  it. Two stakes on the same spot stop the command.
* The original point is **kept** — ringed, not erased. `Pt.17` and
  `Pt.17m` both exist afterwards, which is the point of the ring: the
  drawing shows where it was and where it went.
* A missing `CROSS DIMENSIONS` style is **not** invented: the dims are
  drawn in whatever style is current and the routine says so, so a
  drawing started from the wrong template is obvious.
* Requires the Visual LISP engine (full AutoCAD; LT cannot run this).

## Versioning

`tools/release_lisp.py` reads the `*abfind-version*` banner and stamps
`releases/ABFIND_MMDDYY_REV11.lsp`; run it after any change and bump
the banner.

* **v1.5** — `ABFIND` asks `Move Pt.## to a different reading?` after
  each pair of ties and runs `ABMOVE`'s flow on a Yes, then carries on
  to the next point; Back undoes a moved round whole again.
* **v1.4** — each group of suggestions gets the dashed grey arc it
  lies on (`abf:*locus-color*` / `abf:*locus-ltype*`), created at pool
  scale when the drawing has no linetype by that name.
* **v1.3** — `ABMOVE` settles one point and ends; `ABFIND` still
  loops. Enter at `ABMOVE`'s point number cancels.
* **v1.2** — the suggestions are drawn yellow (`abf:*sug-color*`) and
  tagged by the tape they move and how far (`1A`, `-3B`, `R1A`) rather
  than numbered 1..n; the readings that move A are listed first.
* **v1.1** — `ABMOVE` sweeps the moved tape a foot at a time,
  `abf:*foot-steps*` (10) each way per held stake, with the look-alike
  readings woven in at their own miss distance; the suggestions are
  shown as two groups, A held then B; `abf:*max-shift*` is 10 feet and
  bounds both families; `abf:*max-sugg*` caps each group and defaults
  to no cap.
* **v1.0** — first release.

## Tests

`tests/test_abfind.py` loads the real lisp into the repo's AutoLISP VM
and drives both commands end to end — the tie pair and its style/layer/
ByLayer fixup, number spellings, unknown numbers, stake lookup and the
click fallback, the misreading arithmetic (readings, look-alike digits,
transpositions, the shift cap and the suggestion cap), the circle
crossing, the whole move (new point, ring, note wording, redrawn ties),
the yellow markers and their tags, the dashed grey guide lines and
what they span, the `None` and `Pick` answers, the Back steps, the
one-shot shape and the no-point-block fallback:

```
python3 tests/test_abfind.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_abfind.py # grouped tier
```
