# ABFIND / ABMOVE / ABPCREATE — a point and the A and B stakes (AutoLISP)

A pool is surveyed off two stakes, **A** and **B**: every point on the
field sheet is two tape readings, one from each stake, and the point is
wherever those two distances cross. These three commands work that way
round: two of them start from a point that is drawn and read its
distances back, and the third starts from the distances and draws the
point.

* **`ABFIND`** — name a point (type its number, or click the point
  itself), get the two ties: an aligned dimension from A to the point
  and one from B to it. Then it asks whether that point wants moving,
  and if you say Yes it runs everything `ABMOVE` does before coming
  back for the next point.
* **`ABMOVE`** — that flow on its own, without the question, for when
  you already know a point is wrong: *if this point is in the wrong
  place, where should it be?* One tape is
  held exactly as it is and the other's reading is walked — a foot at a
  time, ten feet each way, plus every number the reading could have
  been misread as. Each candidate is drawn **yellow**, on a scratch
  layer of its own, tagged by the tape it moves and how far: `1A`,
  `-3B`.
  Type the tag you believe and the point is **copied** there, renamed,
  and its old spot ringed and noted — **one point per run**: moving a
  point is a decision, not a sweep, so the command ends as soon as that
  point is settled.
* **`ABPCREATE`** — the other end of the same problem: the field sheet
  has a row and the drawing has nothing. Type the two readings instead
  of a number. Both are drawn **whole**, as the circle of everywhere
  each tape reaches, so the answer is on the sheet either way — they
  cross at one spot, or they visibly cannot. A pair that cannot cross
  is walked exactly as `ABMOVE` walks a move, and every pair that
  *does* cross is offered with **the pair written beside it**
  (`7A  28'-1" / 18'-6"`), because here each candidate stands for a
  different pair of readings and the pair is what you check against the
  sheet. Pick one, name it, and the point is plotted and tied.

`ABFIND` and `ABMOVE` hand over to it: a number that names no point is
offered `Create Pt.23 from its two readings?` rather than only being
reported.

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

Name the point either way round: type its number, or click it. Both
answer the same prompt.

It prints both readings as it goes:

```
  Pt.17:  A 21'-1"   B 18'-6"  dimensioned.
```

Then it asks:

```
  Move Pt.17 to a different reading? [Yes/No/Back] <No>:
```

**No** (the Enter answer) moves on to the next point. **Yes** runs
everything under `ABMOVE` below — the readings, the pick, the move —
and then `ABFIND` comes back and asks for the next one. Either way it
keeps going until you press **Enter** at the prompt.

The stakes themselves are found by name, and are only clicked when the
drawing does not name them (see below).

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

The candidates are drawn on `abf:*sug-layer*` — **`ABMOVE-POINTS`**,
a layer of their own, created when the drawing lacks it — in
`abf:*sug-color*` (**yellow**, both as the layer's colour and as an
entity override). They deliberately do **not** go on `POINTS`: they
are throwaway, they would take that layer's colour, and while they
existed every other tool in the toolset (`BPCALLOUT`, `LHD`, `ABHD`,
`FITABHD` …) would count them as real survey points. The one you
choose is a survey point, and *that* is what lands on `POINTS`.

They are listed nearest miss first within each group:

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

### Where the tags hang

The tags do **not** sit beside their markers. The look-alike readings
land an inch or three apart — `R1B` is 1 1/8" off the point, `R2B`
2 5/16", `R1A` 3 7/16" — and a tag beside each marker piled half a
dozen of them onto one spot, unreadable, which is what made the right
one so hard to pick. So every tag hangs **off** its arc on a short
leader from its marker, in a row `abf:*tag-standoff*` (10") out from
the arc, with `abf:*tag-gap*` of daylight between any two. A tag is
only ever pushed along the row *away* from the point, so the leaders
never cross.

The two arcs cross at the point and cut the sheet into four quarters,
and every marker sits *on* an arc — so the quarters are empty, and
each half of each group takes one: the readings that grew (`1A`,
`R1A`) and the ones that shrank (`-1A`) lie either side of the
crossing, and the group that holds B hangs its grown readings outward
from B and its shrunk ones inward, the group that holds A the other
way about. Within its quarter a tag runs along the quarter's
**bisector**, not straight off its own arc: a quarter is as narrow as
the two ties' crossing angle, and text run straight off one arc walks
into the other where the crossing is sharp, while text run down the
middle draws away from both at once. The narrower the quarter, the
flatter the tags lie to their arc and the further apart along it they
stand for the daylight to hold; that, and how far the first tag keeps
from the crossing (where the other arc's nearest markers are), fall
out of the angle. A tag that would read upside down is turned round
and right-justified on its base, so it still runs away from its leader.

### Choosing one

One prompt, three ways to answer it:

```
  Move Pt.17 - click a marker or its tag, or type a tag [None/Back] <None>:
```

**Click** the marker you want, or its tag — the tag is as good a
target as the marker, and the easier one where the markers crowd. A
click takes the **nearest** marker or tag. (It used to take the first
in the *list* within a foot of the click, which near the crossing was
always `R1A`, whichever marker was under the cursor — `R1B` and `R2B`
could not be clicked at all.) What was taken is read back before the
note is placed:

```
  R2B taken: B 18'-6" -> 18'-8".
```

When two or more markers sit closer together than the pickbox spans
at the current zoom, the click cannot tell them apart, and the routine
says so rather than guess: it lists what is under the click, nearest
first, and asks —

```
  3 markers under that click - zoom in, or say which:
   R1B   B 18'-6" -> 18'-5"
   R1A   A 21'-1" -> 21'-4"
   R2B   B 18'-6" -> 18'-8"
  Which one? [R1B/R1A/R2B/Back] <R1B>:
```

— the nearest being the Enter answer, and `Back` the markers again.
Zoom in and the same click is exact: the pickbox (`PICKBOX` pixels,
read against `VIEWSIZE` and `SCREENSIZE`) shrinks in drawing units,
and the markers come apart.

**Type a tag** from the table, in any case. Every tag is accepted even
though the bracket lists only `None` and `Back` — forty-five tags in a
bracket would swamp the command line — because the prompt is a
`getpoint` under `(initget 128)`, the same one-prompt-two-answers that
names the point. Text that is no tag is reported and the prompt
re-asks. (`Pick`, which earlier versions wanted typed before the
click, is answered with a hint: the prompt takes the click itself.)

**`None`** (the Enter answer) leaves the point alone and keeps the two
dimensions — `ABMOVE` has then done exactly what `ABFIND` does.

Either way that is the end of the run. `ABMOVE` settles **one** point
and stops; run it again for the next one. `ABFIND`, which only
measures, keeps asking until you press Enter. Enter at `ABMOVE`'s
point number cancels the run outright.

Pick one and four things happen:

1. the point is **copied** there and numbered `17m` — the original
   number with `abf:*moved-suffix*` on it, so the drawing says plainly
   that this one was moved. A *copy*: the same block, the same layer,
   colour, linetype, lineweight, scale and rotation, and every
   attribute it carried — same tag, same height, same style, each
   keeping the offset it had from the point. Only the attribute that
   holds the number is written, and only with `17m`. A survey point is
   more than a position — the layer the survey put it on, a block
   scaled to the sheet, an elevation or a description in a second
   attribute — and the moved point is that same point one reading
   further on, so it has to read as one. (A drawing whose point block
   is not in its block table has nothing to insert again; that one
   falls back to a `POINT` on `abf:*point-layer*` with a text label
   beside it.);
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

### `ABPCREATE`

The point is **not** in the drawing. So there is no number to type and
nothing to measure from: the two readings are typed instead, and the
command works forwards.

```
  A to the new point [Back] <Enter = done>: 21'-1"
  B to the new point [Back]: 18'-6"
```

Both are drawn **whole** — one dashed red circle per stake, at the
reading typed, which is everywhere that tape reaches. Two readings
place a point where those two circles cross, and drawing them means the
answer is on the sheet either way instead of only in a sentence.

**They cross.** There is one spot on the field side of the A–B line
(see below), it is marked in yellow, and the only thing left to settle
is what the point is called.

**They cannot cross.** Two circles miss each other two ways round, and
they are different mistakes:

| What is wrong | What it says |
| --- | --- |
| the tapes fall short of each other | `the two arcs fall 3'-4" short of each other` |
| one arc lies wholly inside the other | `B's arc lies 5'-0" inside A's` |

Either way one of the two readings was written down wrong — which is
exactly what `ABMOVE` already knows how to walk. One reading is **held**
and the other swept: a foot at a time, `abf:*foot-steps*` each way, plus
every number it could have been misread as (the table under `ABMOVE`
above). Every pair that *does* cross is offered, in the same two groups
and with the same tags: `1A`, `-3B`, `R1A`.

### The pair beside the marker

`ABMOVE`'s markers all share one pair of readings and differ by where
they sit, so its tag alone names them. `ABPCREATE`'s each stand for a
**different pair**, and the pair — not the position — is what you are
checking against the field sheet. So it is written beside the marker:

```
7A  28'-1" / 18'-6"
```

the tag, then A's reading and B's. The tag is still what you type. The
same pair is in the table on the command line, with the change that
made it:

```
  A 8'-4" and B 8'-4" cannot cross: the two arcs fall 3'-4" short of
  each other - both are drawn whole, so the gap is on screen.

  Where the new point can sit if one of those two was written down
  wrong - the ones that move A first, then B (smallest change first):
  26 of the 40 readings are not offered: they still do not reach the
  other tape.
   tag   moves  by            A             B
   ----  -----  ------------  ------------  ------------
   4A    A      +4'-0"        12'-4"        8'-4"
   5A    A      +5'-0"        13'-4"        8'-4"
   ...
   4B    B      +4'-0"        8'-4"         12'-4"
   ...
```

The labels **radiate** out of the stake that is holding them, like
spokes, rather than filing along the arc the way `ABMOVE`'s tags do.
That is not a style choice: a create label is four or five times the
length of an `ABMOVE` tag, and text runs straight while an arc curves,
so a label that long laid along the arc climbs back through it and lies
across the very markers it labels — and the sideways shoving needed to
separate two of them drags their leaders into long crossing slants.
Two rays out of one centre never meet, so radial labels cannot overlap,
whatever the readings are. Each fan points **away from the other arc**
(outward when that arc lies inside its own, inward otherwise), which
keeps the two groups off each other as well: two tapes that fall short
both point into their own discs, and those two discs do not touch —
that is what falling short means. The nudge that keeps two spokes apart
is a degree or two on a pool-sized arc, so the leaders stay as good as
radial; on a reading barely longer than the label itself it is tens of
degrees and the leaders do slant across each other, which is the right
way round to fail — an untidy leader can be read past, two labels on
top of each other cannot.

### If none of them is right

`None` (the Enter answer) takes no reading and asks for **another
pair** — the way out when the sheet itself has to be re-read. So does a
pair nothing within `abf:*max-shift*` can rescue:

```
  No reading within 10'-0" of either makes the two meet - read the
  sheet again and give another pair.
```

`Enter` at the **A** reading ends the run.

### Naming it, and building it

A point is not created until it is named — the number is what every
tool in this family looks it up by:

```
  Number for the new point <24> (B = back): 23
```

One past the highest number the drawing already carries is offered, and
a number the drawing already uses is **refused**: a number names one
point, and every lookup here takes the first match.

The point itself is built **like the drawing's own**. The survey point
nearest to where it is going is the pattern — its block, layer, colour,
linetype, lineweight, scale, rotation and attribute layout — with the
number written and every **other** attribute left **blank**. A point
that has just been plotted has no elevation and no description, and
copying the neighbour's would be inventing one. Set `abf:*new-atts*` to
`T` for a drawing whose second attribute really is the same on every
point. A drawing with nothing but the two stakes has no pattern, and
that one falls back to `abf:*point-block*` on `abf:*point-layer*` from
this file's own defaults, and says so.

Then the two ties are drawn, the same as `ABFIND` draws them, and it
asks for the next pair. `ABPCREATE` **loops** the way `ABFIND` does;
`Back` at the A reading takes the last point away again, ties and all.

### Which side of the A–B line

Two readings cross **twice**, mirrored across the line joining the
stakes, so a point built from a pair has to be told which of the two is
meant. The survey already says: a pool is taped from two stakes
standing to one side of it, so every point already plotted is on one
side, and their mean is read for the side. Nothing is asked.

Only a drawing carrying nothing but the two stakes says nothing, and
only that one is asked:

```
  Nothing but the stakes is plotted, so the drawing does not say which
  side of A-B the pool is on - and two readings cross on both.
  Click roughly where the new point belongs [Back]:
```

The click picks the **side**, not the spot — the readings place the
point.

### From `ABFIND` and `ABMOVE`

A number typed at either that names no point used to be reported and
re-asked, full stop. It is much more often a point that was never
plotted than a typo, so both now offer the way forward:

```
  No point numbered "23" in the drawing.
  Create Pt.23 from its two readings? [Yes/No/Back] <No>:
```

**Yes** runs everything above with `23` already filled in as the number
to offer. `ABFIND` then carries on to the next point with the new one
plotted and tied; `ABMOVE`, which settles **one** point, is done — the
point it was asked about now exists, at the reading that was asked for.
**No** is the Enter answer and re-asks the number, because a typo is
the other way to get here and Enter must not plot a point from one.
`Back`, and `Enter` at the A reading, both put the number prompt back
with nothing drawn.

## Finding the stakes

A and B are looked up by name among the survey points, the same way any
other point is: an `ab_pt` INSERT on any layer or any other INSERT on
the **POINTS** layer, named by its `number` attribute (the classifier
`BPCALLOUT`, `CDCALLOUT` and `LHD` all share). A drawing that does not
name them says so and asks you to **click each one**, once per run,
snapping to the nearest survey point within `abf:*snap*`; a click with
nothing under it is taken as the stake position itself. Enter at that
prompt cancels the run.

## Naming the point

```
  Pick the point, or type its number <Enter = done>:
```

One prompt, two ways to answer it.

**Type the number.** Numbers are matched against the same `number`
attribute. Type them the way they read in the drawing — all of these
name the same point:

```
35    Pt.35    pt35    PT.35    #35    035    35.0
```

Only the dot right after `Pt` is treated as a prefix — a point
genuinely named `40.5` keeps its decimal. A number that names no point
is reported and the prompt re-asks: **nothing is drawn from a typo**.
When a drawing carries a duplicate number, the first match wins.

**Or click it.** A click is snapped to the survey point within
`abf:*snap*` (12") of it, and from there it is that point's number that
the run works with — the ties, the table, the note and the `m` all read
the same as if you had typed it. A click with **no** survey point under
it names nothing: it is reported and the prompt re-asks, exactly the
way a typo is, and a click on a stake is refused the way naming one is.

The one prompt takes both because it is a `getpoint` under
`(initget 128)`: typed text comes back as the string it is, a click
comes back as the point it is.

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
* `Back` at **`Which one?`** — the tie a click could not settle — is
  the markers again, nothing chosen;
* `Back` at **the note** re-asks which suggestion, with the
  suggestions still on screen;
* in `ABPCREATE`, `Back` at **the A reading** undoes the whole of the
  last round the same way `ABFIND`'s point number does — the point it
  created, its number and its ties — or, when it is `ABFIND` or
  `ABMOVE` that sent you there, re-asks the point number instead;
* `Back` at **the B reading** re-asks the A reading;
* `Back` at **which candidate** re-asks the B reading;
* `Back` at **the number for the new point** re-asks which candidate —
  or, where the pair simply crossed and nothing was chosen, the B
  reading.

`ABMOVE`'s first question has nothing to go back to, and once its point
is settled — moved or created — the run is over; to undo that, `U`.
`ABPCREATE`'s first question is the A reading of its first round, and
that one says `Already at the first point.`

The whole run is **one undo group**: a single `U` takes it all away.
The dimension style, current layer, `OSMODE` and `CMDECHO` in force
before the command are restored afterwards — on a clean finish, an
error, or Esc.

## Install & run

1. Load `ABFIND.lsp` (`APPLOAD`, or drag it into the drawing). All
   three commands come with the one file — which is also why `ABFIND`
   and `ABMOVE` can offer to create a point with nothing else loaded.
2. `ABFIND` → `Pick the point, or type its number <Enter = done>:` →
   `17`, or click the point → the two ties are drawn →
   `Move Pt.17 to a different reading? [Yes/No/Back] <No>:` →
   Enter to move on, or `Yes` to go through step 3 → next point, or
   Enter to finish.
3. `ABMOVE` → `Pick the point, or type its number (Enter to cancel):`
   → `17`, or click the point → read the table
   (`F2` opens the text window if it runs off the command line) →
   `Move Pt.17 - click a marker or its tag, or type a tag [None/Back]
   <None>:` → click the marker or its tag, or type a tag such as
   `-1B` (a click that cannot tell two markers apart asks
   `Which one?`) → `Place the note for Pt.17 [Auto/Back] <Auto>:` →
   Enter, and the command is done.
4. `ABPCREATE` → `A to the new point [Back] <Enter = done>:` → `21'-1"`
   → `B to the new point [Back]:` → `18'-6"` → both arcs are drawn,
   and either the crossing is marked or the pairs it could have been
   are → `The new point - click a marker or its label, or type a tag
   [None/Back] <None>:` → click one, or type a tag such as `7A`, or
   Enter for another pair → `Number for the new point <24> (B = back):`
   → `23` → the point is plotted and tied → next pair, or Enter to
   finish.
5. `ABFINDVER` prints the loaded version.

## Tunables

The constants at the top of `ABFIND.lsp`:

```lisp
(setq abf:*style*        "CROSS DIMENSIONS") ; dimension style
(setq abf:*layer*        "DIMENSION")   ; layer the dims land on
(setq abf:*offset*       0.0)           ; push the dim line off the tie
(setq abf:*point-block*  "ab_pt")       ; the survey point block
(setq abf:*point-layer*  "POINTS")      ; layer whose INSERTs count,
                                        ; and where the moved point goes
(setq abf:*point-color*  6)             ; colour for it if it is missing
(setq abf:*pt-tag*       "number")      ; attribute naming the point
(setq abf:*a-name*       "A")           ; what the two stakes are
(setq abf:*b-name*       "B")           ; numbered in the drawing
(setq abf:*snap*         12.0)          ; click-to-point snap radius
(setq abf:*ring-layer*   "FGStep")      ; ring + note layer
(setq abf:*ring-radius*  5.0)           ; ring RADIUS, inches
(setq abf:*note-hgt*     6.0)           ; note text height
(setq abf:*moved-suffix* "m")           ; Pt.17 -> Pt.17m
(setq abf:*att-height*   4.0)           ; the FALLBACK point's number,
(setq abf:*att-offset*   '(0.87 -3.53)) ; and where it sits: a COPIED
                                        ; point keeps the attribute
                                        ; the point it came from had
(setq abf:*sug-radius*   3.0)           ; suggestion marker radius
(setq abf:*sug-layer*    "ABMOVE-POINTS") ; scratch layer, NOT POINTS
(setq abf:*sug-color*    2)             ; suggestion colour: yellow
(setq abf:*sug-hgt*      5.0)           ; suggestion tag height
(setq abf:*tag-standoff* 10.0)          ; how far off its arc a tag hangs
(setq abf:*tag-gap*      1.5)           ; daylight between tags, and from
                                        ; the other arc's markers
(setq abf:*tag-width*    0.8)           ; a character's width, as a
                                        ; fraction of the tag height, for
                                        ; the strip a click on a tag hits
(setq abf:*locus-color*  8)             ; guide-line colour: grey
(setq abf:*locus-ltype*  "DASHED")      ; and its linetype
(setq abf:*ghost-color*  1)             ; ABPCREATE's two whole reading
                                        ; circles: red, dashed
(setq abf:*new-atts*     nil)           ; T = a created point copies its
                                        ; pattern's OTHER attribute
                                        ; values too; nil leaves them
                                        ; blank
(setq abf:*foot-steps*   10)            ; 1-foot steps offered each way
(setq abf:*max-shift*    120.0)         ; furthest a suggestion may sit
(setq abf:*max-sugg*     nil)           ; most per held stake, nil = all
(setq abf:*prec*         4)             ; rtos precision, 4 = 1/16"
(setq abf:*same-eps*     0.125)         ; two suggestions this close
                                        ; are one place
```

`abf:*tag-gap*` is measured *across* the tags; along the arc they
stand further apart than that, by the angle the quarter's bisector
makes with the arc, so a sharp crossing spreads a group's tags wider
than a square one does. In `ABPCREATE`, whose labels radiate rather
than file along the arc, `abf:*sug-hgt*` + `abf:*tag-gap*` is the
daylight kept between two spokes at the end nearer the stake, where
they are closest. `abf:*snap*` is still the reach of a click on a
**marker**; a click on a **tag** or a **label** has to land on the text
itself, within the pickbox.

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
* `Pt.17m` is a **copy** of `Pt.17`, so it lands wherever `Pt.17`
  lived — its layer, not `abf:*point-layer*`. That layer is turned on,
  thawed and unlocked first, the way every other output layer is.
  `abf:*point-layer*` still names the layer the **fallback** point goes
  on, and the layer whose `INSERT`s count as survey points.
* Everything `entget` reports is copied, extended data included; what
  it does not report — an object-dictionary entry, a reactor, a
  field — is not. If the copy is refused (a block the drawing cannot
  insert again), the fallback point is built instead, so a run never
  ends with the note and the ring but no point.
* A missing `CROSS DIMENSIONS` style is **not** invented: the dims are
  drawn in whatever style is current and the routine says so, so a
  drawing started from the wrong template is obvious.
* `ABMOVE-POINTS` is emptied at the end of every round but the layer
  itself stays in the drawing — `PURGE` clears it when you are done.
  `ABPCREATE`'s markers, labels and reading circles share it.
* `ABPCREATE` needs the stakes, so it needs the drawing to name them or
  you to click them — the same as the other two, and a drawing with no
  named survey point at all stops before it asks anything.
* `ABPCREATE` varies **one** reading at a time, exactly as `ABMOVE`
  does: a pair that only crosses once both were wrong is not offered.
  `None` and another pair is the answer to that, and so is `ABCDEF`,
  which fits a point against three or four tapes rather than two.
* A created point is patterned on its nearest neighbour, so a drawing
  whose points are *not* alike — several surveys merged, two block
  scales — patterns it on whichever one happens to be nearest. It is
  said on the command line each time, and the point is an ordinary
  block reference afterwards: fix it as you would any other.
* Requires the Visual LISP engine (full AutoCAD; LT cannot run this).

## Versioning

`tools/release_lisp.py` reads the `*abfind-version*` banner and stamps
`releases/ABFIND_MMDDYY_REV11.lsp`; run it after any change and bump
the banner.

* **v1.12** — `ABPCREATE`: the point is not in the drawing, so the two
  readings are typed instead of a number. Both are drawn whole, and a
  pair that cannot cross is walked with `ABMOVE`'s own sweep, every
  workable pair offered with **the pair written beside its marker** and
  the labels radiating out of the stake that holds them. Pick one, name
  it — one past the highest number is offered, a number already in use
  refused — and the point is built like the survey point nearest it
  (`abf:*new-atts*`) and tied. `ABFIND` and `ABMOVE` offer the same
  flow when a number names no point.
* **v1.9** — the suggestion is chosen at **one prompt**: click the
  marker or its tag, or type the tag — no `Pick` first. A click takes
  the **nearest** marker or tag (it took the first in the list within
  a foot, which near the crossing was always `R1A`), and a click that
  cannot tell two markers apart at the current zoom lists them and
  asks `Which one?`. The tags hang **off** the arc on leaders, in the
  four empty quarters between the arcs, spaced so they never overlap
  each other or the markers (`abf:*tag-standoff*`, `abf:*tag-gap*`),
  instead of piling up beside markers an inch apart; `abf:*sug-hgt*`
  is 5".
* **v1.7** — the moved point is a **copy** of the point it came from
  (block, layer, colour, linetype, lineweight, scale, rotation and
  every attribute, offsets and all) with only its number rewritten,
  instead of a fresh point built from this file's defaults; and the
  point can be **clicked** as well as typed, at the one prompt.
* **v1.6** — the suggestions and their guide lines get their own
  layer (`abf:*sug-layer*`, `ABMOVE-POINTS`) instead of `POINTS`; only
  the chosen point lands on `POINTS`, which is created in
  `abf:*point-color*` when a drawing lacks it.
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
and drives all three commands end to end — the tie pair and its style/layer/
ByLayer fixup, number spellings, unknown numbers, stake lookup and the
click fallback, the misreading arithmetic (readings, look-alike digits,
transpositions, the shift cap and the suggestion cap), the circle
crossing, the whole move (new point, ring, note wording, redrawn ties),
the yellow markers and their tags, the dashed grey guide lines and
what they span, the `None` answer and the click — nearest marker
or tag, the `Which one?` tie at a coarse zoom, the tags' spacing
and their four quarters — the Back steps, the
one-shot shape and the no-point-block fallback — and, for the two
newest behaviours, that the moved point carries the original's block,
layer, colour, linetype, lineweight, scale, rotation and both of its
attributes with only the number rewritten, that it stays off
`abf:*point-layer*` when its original did, and that a clicked point
ties and moves exactly as a typed one does (with a click on nothing,
and a click on a stake, refused).

For `ABPCREATE` it drives both answers a pair of readings can have: a
pair that crosses (plotted, named, tied, scaffolding swept, and on the
side the rest of the survey is on — either side), and one that cannot
(the gap named, both whole circles drawn dashed at the readings typed,
every workable pair offered with its own tag and its held tape exactly
held, each label reading `tag  A / B` for the distances its marker
really stands at, and the table saying the same). Then the answers to
it: a click on a marker, `None` and a pair nothing reaches both asking
for another pair, the next number offered and a number in use refused,
the point built from its nearest neighbour with the other attributes
blank and `abf:*new-atts*` keeping them, the drawing with nothing but
stakes asking for the side and the click picking only that, the whole
Back chain, the loop and a created round undone whole — and, from the
other end, that `ABFIND` offers to create a number it cannot find and
carries on, that `ABMOVE` creates one and is then done, and that both
Back and Enter at the A reading back out of the offer with nothing
drawn:

```
python3 tests/test_abfind.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_abfind.py # grouped tier
```
