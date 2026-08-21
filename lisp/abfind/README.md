# ABFIND / ABMOVE — tie a point back to the A and B stakes (AutoLISP)

A pool is surveyed off two stakes, **A** and **B**: every point on the
field sheet is two tape readings, one from each stake, and the point is
wherever those two distances cross. These two commands work that way
round.

* **`ABFIND`** — type a point number, get the two ties: an aligned
  dimension from A to the point and one from B to it.
* **`ABMOVE`** — the same, and then the question `ABFIND` raises: *if
  this point is in the wrong place, where should it be?* One tape is
  held and the other's reading is varied to every number it could have
  been misread from. Pick the position you believe and the point moves
  there, renamed, ringed and noted.

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

It keeps asking for the next number until you press **Enter**, and
prints both readings as it goes:

```
  Pt.17:  A 21'-1"   B 18'-6"  dimensioned.
```

Nothing is clicked — unless the drawing does not name its stakes (see
below).

### `ABMOVE`

Everything `ABFIND` does, and then the suggestions. A misreading is one
of these, applied to whichever reading is **not** being held:

| The mistake | `21'-1"` could have been |
| --- | --- |
| the feet came out one out | `20'-1"`, `22'-1"` |
| the inches lost or gained a leading 1 | `21'-11"` |
| a digit read as a look-alike (`abf:*digit-pairs*`: 1/7, 1/4, 3/8, 3/5, 5/6, 6/8, 0/9, 4/9, 7/9) | `21'-7"`, `21'-4"` |
| two feet digits changed places | `12'-1"` |

Both ways round: A held while B's reading moves, then B held while A's
does. Each pair of distances is crossed back to a position — the
crossing on the side the point is already on, because a misread tape
does not flip a point across the stakes. Only misses up to
`abf:*max-shift*` (**2 feet** as shipped) are offered, so the
feet-digit and transposed-digit cases only show up at all when that is
raised.

What comes out is drawn on the **POINTS** layer, numbered on screen,
and listed nearest miss first:

```
  Where Pt.17 lands if one tape was written down wrong (nearest miss first):
   #  held  moved  from          to            the point moves
   -  ----  -----  -----------   -----------   ---------------
   1  A     B      18'-6"        18'-5"        0'-1 1/8" SE
   2  A     B      18'-6"        18'-8"        0'-2 5/16" NW
   3  B     A      21'-1"        21'-4"        0'-3 7/16" NE
   4  B     A      21'-1"        21'-7"        0'-6 15/16" NE
   5  B     A      21'-1"        21'-11"       0'-11 5/8" E
   6  A     B      18'-6"        19'-6"        1'-1 15/16" NW
   7  A     B      18'-6"        17'-6"        1'-1 3/4" SE
   8  B     A      21'-1"        22'-1"        1'-1 15/16" E
   9  B     A      21'-1"        20'-1"        1'-1 11/16" SW
  10  A     B      18'-6"        16'-6"        2'-3 1/4" SE
```

Answer with the number, or `Pick` and click the one you want. `None`
(the Enter answer) leaves the point alone and keeps the two
dimensions — `ABMOVE` has then done exactly what `ABFIND` does.

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

`Pt.17m` joins the lookup as it is made, so you can name it in a later
round of the same run — and Back forgets it again along with the rest
of its round.

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

* `B`, `BACK`, `U` or `UNDO` (any case) typed at the **point number**
  un-does the whole of the last round — its dimensions, and, if it
  moved a point, the moved point, the ring and the note, with the
  original dimensions put back (`Stepping back one point.`, or
  `Already at the first point.` when there is nothing left);
* `Back` at **which suggestion** takes that round's dimensions away and
  re-asks the number;
* `Back` at **the note** re-asks which suggestion, with the
  suggestions still on screen.

The whole run is **one undo group**: a single `U` takes it all away.
The dimension style, current layer, `OSMODE` and `CMDECHO` in force
before the command are restored afterwards — on a clean finish, an
error, or Esc.

## Install & run

1. Load `ABFIND.lsp` (`APPLOAD`, or drag it into the drawing). Both
   commands come with the one file.
2. `ABFIND` → `Point number <Enter = done>:` → `17` → the two ties are
   drawn → next number, or Enter to finish.
3. `ABMOVE` → `Point number <Enter = done>:` → `17` → read the table →
   `Move Pt.17 to which? [1/2/3/4/5/6/7/8/9/10/Pick/None/Back] <None>:`
   → `1` → `Place the note for Pt.17 [Auto/Back] <Auto>:` → Enter.
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
(setq abf:*sug-hgt*      6.0)           ; suggestion number height
(setq abf:*max-shift*    24.0)          ; biggest misreading offered
(setq abf:*max-sugg*     12)            ; most suggestions at once
(setq abf:*prec*         4)             ; rtos precision, 4 = 1/16"
(setq abf:*same-eps*     0.125)         ; two suggestions this close
                                        ; are one place
```

Raising `abf:*max-shift*` is the interesting one: at 2 feet you get a
foot out, the 1"/11" slip and the look-alike inch digits. Raise it and
the look-alike **feet** digits arrive too — a 3 read as an 8 is five
feet, and a transposed `21'` → `12'` is nine.

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
`releases/ABFIND_MMDDYY_REV10.lsp`; run it after any change and bump
the banner.

* **v1.0** — first release.

## Tests

`tests/test_abfind.py` loads the real lisp into the repo's AutoLISP VM
and drives both commands end to end — the tie pair and its style/layer/
ByLayer fixup, number spellings, unknown numbers, stake lookup and the
click fallback, the misreading arithmetic (readings, look-alike digits,
transpositions, the shift cap and the suggestion cap), the circle
crossing, the whole move (new point, ring, note wording, redrawn ties),
the `None` and `Pick` answers, all three Back steps and the
no-point-block fallback:

```
python3 tests/test_abfind.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_abfind.py # grouped tier
```
