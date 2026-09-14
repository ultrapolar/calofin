# CLEARDIM -- dimension text slid along its own dimension line until it is readable (AutoLISP / AutoCAD 2018+)

A sheet comes back from `AUTODIM` with every dimension in the right
place and three of the numbers unreadable: one sitting on a wall line,
one on top of the dimension below it, one halfway under the step
detail. Nothing is wrong with the dimensions -- the text is just in the
wrong spot along them.

`CLEARDIM` slides it. Every dimension's text has one **track**, and it
is made of the dimension itself:

| Family | Its track |
| --- | --- |
| linear, aligned | the dimension line, a straight run |
| angular (2-line and 3-point) | the dimension **arc**, about the angle's vertex |
| radius, diameter | the radial line it is measured along |
| ordinate | the leader, along the axis it reads |

Moving along that track is free: the dimension still measures what it
measured, the extension lines still say between which two points, and
nothing about the drawing changes. Moving the text **off** the track is
not free -- it stops sitting on the thing it measures, and AutoCAD draws
a leader to explain where it went -- so `CLEARDIM` never does it. What
staying on means differs by shape and is the same in substance: a linear
text keeps its offset above the dimension line to the last decimal, an
angular one keeps the **radius** it rides at, and both come out of the
run on the track they went in on.

The track's parameter is a **distance** in every case -- an arc length
round an arc rather than an angle. That is what lets `cd:*step-f*` and
`cd:*reach-f*` mean the same thing on a dimension arc as on a straight
dimension line, instead of needing a second pair of knobs kept in step
with the first.

**The one that is already good does not move.** That is the whole
policy. A text that is clear of everything has earned its spot and
keeps it; the ones that are on something go around it.

## What it does

1. **Highlight the drawing** (Enter takes everything in the space you
   are looking at). A selection made before the command was typed is
   used as it stands, without asking.

2. **Every dimension in the sweep is measured.** The text box comes off
   the dimension itself -- its letters live in an anonymous block that
   AutoCAD rebuilds whenever anything about the dimension changes, so
   there is nothing stable to read there. Group 11 is the middle of the
   text; the rest is worked out:

   - **Height.** A text style with a **fixed** height wins outright. The
     dimension style points at one through `DIMTXSTY` (group 340), and
     where that style's height is non-zero it *is* the height --
     `DIMTXT` ignored, `DIMSCALE` not applied. Only a variable-height
     style leaves `DIMTXT` x `DIMSCALE` in charge, with the dimension's
     own xdata overrides laid over both.
   - **Width.** The glyph count at `cd:*charwidth*` of that height,
     times the text style's own width factor. The count is what the
     text **draws**, not what it is spelled with: `%%d` is one glyph of
     three characters, MTEXT markup (`\A1;`,
     `{\fArial|b1|i0|c0|p34;...}`, `\H0.85x;`) is none at all, and a
     stacked `\S1/2;` is as wide as its longer half.
   - **What it says.** A measurement is spelled with the dimension
     style's own `DIMLUNIT` and `DIMDEC`, not the drawing's `LUNITS`
     and `LUPREC`. That is half the width between `33'-3"` and
     `33'-2 15/16"`.

   On an arc the box **turns** as it slides, because text set along a
   dimension arc turns with it unless the style holds it upright
   (`DIMTIH`).

   Then its track, which each family answers for itself:

   - **linear and aligned** -- group 50's direction on a rotated
     dimension, the run between the two extension line origins (13 and
     14) on an aligned one.
   - **angular** -- an arc about the angle's vertex. A 3-point
     dimension writes that vertex into group 15; a 2-line one keeps no
     vertex at all, so it is found where the two measured lines (13-14
     and 15-10) cross, on the *infinite* lines rather than the drawn
     segments.
   - **radius and diameter** -- the line through groups 10 and 15.
     `AutoDim`'s `ad:raddimpts` is the repo's own reading of those two:
     a radius dimension puts the **centre** in 10 and a point on the
     circle in 15, while a diameter writes the two **ends** of the
     diameter and has no centre of its own, so its centre is the middle
     of them.
   - **ordinate** -- the leader. Group 13 is the feature and 14 is where
     the leader ends; bit 64 of group 70 says which coordinate is being
     read and with it which axis the leader runs along, and the sign
     comes from the leader as drawn.

3. **Everything else is reduced to ink.** Lines, polyline edges, arcs,
   circles, `TEXT` and `MTEXT`, plus what every dimension in the sweep
   draws for itself -- its dimension line, arc, radial line or leader,
   and a linear one's two extension lines. A text box is tested against
   all of it by a separating-axis test, grown first by `cd:*gap-f*` so
   "clear" means readable rather than merely not crossed.

   Two things are deliberately not ink: anything on `cd:*skip-layers*`
   (`DEFPOINTS`, which does not plot), and the piece of itself a text
   **rides** -- its own dimension line, its own arc. AutoCAD breaks that
   around the text, which is what a dimension is. Its own extension
   lines *are* ink: they cross the track at right angles and are what a
   text slid too far ends up on.

   An arc is many polygons, so what a dimension rides is kept as its own
   list rather than as the first item of one. Tagging only the first
   chord would have an angular dimension fleeing the other thirty-one.

4. **They are placed in three passes**, and this is where the policy
   lives:

   | Pass | Who | What happens |
   | --- | --- | --- |
   | 1 | text that CANNOT move | placed where it is, and it keeps that spot: a locked layer, a suppressed text, a track that cannot be read (below) |
   | 2 | text already clear of every fixed thing | it keeps its spot too |
   | 3 | everything left | slid to the nearest clear spot, routed around all of the above |

   Inside each pass the order is reading order -- row by row down the
   sheet, left to right along each row -- so two texts that are each
   clear of the drawing but not of each other resolve the same way
   every run: the first one read keeps its spot and the second slides.
   Nothing moves that did not have to.

5. **A text that has to move goes to the nearest clear spot on its
   track**, found by stepping outward in `cd:*step-f*` steps and then
   bisecting back toward where it started, so the move is the smallest
   one that still works. The two directions are not equal: the one that
   takes the text back toward where its family says it belongs is tried
   first -- the middle of the dimension line, the middle of the arc's
   sweep, the circle a radius measures to, and for an ordinate simply
   **further out**, because a leader is made longer to get its text
   clear and never shorter back onto the work.

   A text with nowhere clear inside `cd:*reach-f*` is **left where it
   was** and named in the report. A text parked somewhere arbitrary is
   worse than a text still sitting on a line, because the drafter can
   see the second one.

6. **What moved is marked user-positioned** (group 70 bit 128), which
   is what stops AutoCAD putting it back at the next regen. The ordinate
   is the one family whose text does not travel alone: its leader ends
   where the text is, so group 14 moves the same step and the feature
   point never moves -- writing group 11 by itself would leave the text
   off the end of its own leader.

   Then the report says what happened:

   ```
   CLEARDIM: 14 dimensions.
     9 already clear - left alone.
     3 slid clear without leaving their dimensions.
     1 with nowhere clear on the track - left as drawn.
     1 skipped: 1 whose track could not be read.
   ```

   Each moved, stuck or skipped dimension gets its own line above the
   totals, named by handle -- which is what you type at `SELECT` to go
   and look at it.

`CLEARDIMSCAN` is the same analysis with the writing left out: it says
what `CLEARDIM` would do and changes nothing.

## Install & run

```
APPLOAD lisp/cleardim/CLEARDIM.lsp     (or the whole shared/LAZPASS.lsp)
CLEARDIM        clear the dimension text that is hard to read
CLEARDIMSCAN    the same pass, read-only
CLEARDIMVER     print the loaded version
```

## Tunables

Every knob is read when the command runs, not when the file loads, so a
`setq` typed at the command line changes the next run.

| Knob | Default | What changing it does |
| --- | --- | --- |
| `cd:*charwidth*` | `0.75` | How wide one glyph is taken to be, as a fraction of the text height. The one estimate in the file: raise it and every box gets wider, so more texts are called hard to read and the ones that move end up further clear |
| `cd:*gap-f*` | `0.4` | Breathing room around a text box on every side, as a multiple of the text height. `0.0` asks only that the ink not actually cross the letters, which is not the same as readable |
| `cd:*step-f*` | `0.25` | How far each trial slide steps, as a multiple of the text height. Smaller finds narrower gaps and takes proportionally longer |
| `cd:*reach-f*` | `4.0` | How far a text may slide from where it started, each way, as a multiple of its own width. A text with nothing clear inside this is left alone and reported, not parked |
| `cd:*refine*` | `5` | Halvings used to bisect the found spot back toward the original one, so the move is the smallest that still clears. `0` leaves the moves on whole `cd:*step-f*` boundaries |
| `cd:*rowtol-f*` | `2.0` | How tall a "row" is for reading order, as a multiple of the tallest text in the sweep |
| `cd:*arcsegs*` | `32` | Chords a full circle is flattened into before it is tested against a text box; an arc gets its share of them |
| `cd:*skip-layers*` | `("DEFPOINTS")` | Layers whose entities are not ink |
| `cd:*obstacle-types*` | `LINE LWPOLYLINE POLYLINE ARC CIRCLE TEXT MTEXT` | Entity types read as ink under the text. `DIMENSION` is handled on its own and is not listed. `INSERT` is deliberately absent: a block's bounding box is mostly empty space, so counting it would move texts that read fine |
| `cd:*dimtxt-default*` | `0.18` | `DIMTXT` to assume when the style record carries none -- AutoCAD's own out-of-the-box value |

## Notes & limitations

- **A track that cannot be read is left alone, never guessed at.** A
  2-line angular dimension keeps no vertex -- it is where its two
  measured lines cross, and parallel lines cross nowhere. An ordinate
  with no leader end has no axis to run along. And the vertex an
  angular dimension does yield is checked before it is trusted: the
  sweep between its two rays **is** the angle it measures, so a vertex
  that group 42 disagrees with (by more than 0.02 radians) is refused.
  A track guessed wrong does not move text along the dimension, it
  moves it **off** it, which is the one thing this tool exists not to
  do. Every such dimension is counted in the report and its text is
  still ink everything else has to clear.
- **A dimension's own arc is read from its own groups, not from its
  block.** The arc a text rides is centred on the vertex at the radius
  the text already sits at, so the radius never has to be inferred; the
  arc drawn as *ink* is at its own radius, taken from the arc point
  (group 10 on a 3-point dimension, group 16 on a 2-line one). A
  dimension carrying no arc point still slides -- it simply contributes
  no arc to the obstacle list.
- **Two families have a floor under them.** An ordinate's text slid
  back past the point it is reading turns its leader round the other
  way, and a radius dimension's text on the far side of the centre is
  measuring from nowhere -- so neither is allowed there, and a text that
  cannot get clear above the floor is left where it was. An arc needs no
  floor (a text at a fixed radius can never reach the vertex) and a
  diameter's text is welcome anywhere along the diameter, which is what
  its centre being the **middle** of its two points means.
- **Only a linear dimension gets a default text point.** Every
  dimension AutoCAD writes carries group 11. A linear one without it
  gets AutoCAD's own default computed for it (the middle of the
  dimension line, a gap above); no other family does, because inventing
  a point on an arc or a leader is putting the text somewhere rather
  than finding where it is.
- **`cd:*charwidth*` is the one estimate left.** A stroke font's
  glyphs are not all one width, so a per-glyph average is as close as
  this gets without measuring the font. It is the escape hatch: raise it
  and every box gets wider and the tool more cautious.
- **A per-dimension override of `DIMTXSTY` is not read.** The dimension
  style's is. An xdata `DSTYLE` block overriding the *text style* of one
  dimension (rather than its height, which **is** read) falls back to
  the style's.
- **A polyline's bulged edge is read as its chord.** The real arc bows
  away from the chord, so a text the chord clears can still be caught
  by the bulge. This is the one place the file is optimistic.
- **A dimension on a locked layer is reported, never written to** --
  `entmod` would be refused, and a run that skipped it silently would
  claim a sheet was cleared when it was not.
- Moving text with group 70 bit 128 set is what a drafter does by
  dragging its grip, so a style whose `DIMTMOVE` adds a leader on a
  moved text will add one here too. Since the move is along the track
  and the across-the-track offset (or radius) does not change, that
  leader has nowhere to go and does not appear in practice.
- **Angular text is measured tangent to its arc.** `DIMTIH` is read, so
  a style that holds text upright gets an upright box that does not turn
  as it slides; anything else turns with the arc. `DIMTOH` -- upright
  only when the text is *outside* the extension lines -- is not read,
  so a style that sets those two differently is measured by the first.
- The whole run is one UNDO group: a single `U` puts every text back.
  Esc at the selection prompt restores `OSMODE` and `CMDECHO` and
  closes the group; there is no prompt after the group opens, so there
  is no half-finished state to be left in.
- Running it twice is safe and idempotent on an unchanged drawing: the
  second run finds everything clear and moves nothing.

## Tests

```
python3 tests/test_cleardim.py
CALOFIN_LISP_ROOT=shared python3 tests/test_cleardim.py
```

On top of those there is one **regression from a real drawing**: the
rectangle whose two `CROSS DIMENSIONS` diagonals printed on top of each
other in the middle, with every group, style and number as its DXF has
them. `CLEARDIM` v2.0 reported it "6 already clear - left alone",
because neither style carried a `DIMTXT` and both texts measured 0.18
units instead of 6.0. The test asserts the heights off the styles, that
exactly the two diagonals move, and that they end up more than 40 units
apart.

Runtime tests: the real file is loaded into `tests/lispvm.py` and both
commands are driven from a script against drawings built by `entmake`,
so the box geometry, the separating-axis test (a segment grazing an
edge is not an overlap), the glyph count, the track read off a rotated
and an aligned dimension, the `DIMTXT` override out of xdata, the
three-pass policy (including the case the tool exists for -- one text
on a line and one clear, overlapping each other, and only the first
moves), the reach and gap knobs, what is ink and what is not, Fit text
measured between its own two ends rather than as a justification, a
second run doing nothing, the undo group and Esc are all measured
against the file that actually ships.

The other four families have their own: the angular track read as an arc
in arc length about a vertex found two different ways, the box turning
with the arc and staying upright when `DIMTIH` says so, the whole arc
counting as ridden rather than just its first chord, the radius and
diameter centres, the ordinate's axis read off bit 64 and its leader end
travelling with its text, and every way a track can fail to be read --
parallel lines, a missing leader, a missing text point, and a vertex
group 42 disagrees with.
