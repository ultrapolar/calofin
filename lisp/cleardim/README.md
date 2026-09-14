# CLEARDIM -- dimension text slid along its own dimension line until it is readable (AutoLISP / AutoCAD 2018+)

A sheet comes back from `AUTODIM` with every dimension in the right
place and three of the numbers unreadable: one sitting on a wall line,
one on top of the dimension below it, one halfway under the step
detail. Nothing is wrong with the dimensions -- the text is just in the
wrong spot along them.

`CLEARDIM` slides it. A dimension's text has one **track**, the
dimension line it belongs to, and moving along that track is free: the
dimension still measures what it measured, the extension lines still
say between which two points, and nothing about the drawing changes.
Moving the text **off** the line is not free -- it stops sitting on the
thing it measures, and AutoCAD draws a leader to explain where it went
-- so `CLEARDIM` never does it. The across-the-track offset a text goes
in with is the one it comes out with, to the last decimal.

**The one that is already good does not move.** That is the whole
policy. A text that is clear of everything has earned its spot and
keeps it; the ones that are on something go around it.

## What it does

1. **Highlight the drawing** (Enter takes everything in the space you
   are looking at). A selection made before the command was typed is
   used as it stands, without asking.

2. **Every dimension in the sweep is measured.** The text box comes off
   the dimension itself: group 11 is the middle of the text, the height
   is the style's `DIMTXT` times `DIMSCALE` with the dimension's own
   overrides laid over the top, and the width is the glyph count at
   `cd:*charwidth*` of that height. The track is the dimension line --
   group 50 on a rotated dimension, the run between the two extension
   line origins on an aligned one.

3. **Everything else is reduced to ink.** Lines, polyline edges, arcs,
   circles, `TEXT` and `MTEXT`, plus what every dimension in the sweep
   draws for itself: its dimension line and its two extension lines.
   A text box is tested against all of it by a separating-axis test,
   grown first by `cd:*gap-f*` so "clear" means readable rather than
   merely not crossed.

   Two things are deliberately not ink: anything on `cd:*skip-layers*`
   (`DEFPOINTS`, which does not plot), and a dimension's **own**
   dimension line -- AutoCAD breaks that around the text, which is what
   a dimension is. Its own extension lines *are* ink: they cross the
   track at right angles and are what a text slid too far ends up on.

4. **They are placed in three passes**, and this is where the policy
   lives:

   | Pass | Who | What happens |
   | --- | --- | --- |
   | 1 | text that CANNOT move | placed where it is, and it keeps that spot: a locked layer, a suppressed text, a track that is not a straight dimension line |
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
   one that still works. The two directions are not equal: the one
   that takes the text back toward the middle of its own dimension line
   is tried first, because the middle is where a dimension's text
   belongs.

   A text with nowhere clear inside `cd:*reach-f*` is **left where it
   was** and named in the report. A text parked somewhere arbitrary is
   worse than a text still sitting on a line, because the drafter can
   see the second one.

6. **What moved is marked user-positioned** (group 70 bit 128), which
   is what stops AutoCAD putting it back at the next regen, and the
   report says what happened:

   ```
   CLEARDIM: 14 dimensions.
     9 already clear - left alone.
     3 slid clear along their own dimension lines.
     1 with nowhere clear on the track - left as drawn.
     1 skipped: 1 on a track that is not a straight dimension line.
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

- **Only linear and aligned dimensions are moved.** Angular, radius,
  diameter and ordinate dimensions each have a track -- an arc, a
  radial line, a leader -- and not one of them is the straight
  dimension line this file knows how to walk. They are counted in the
  report by kind, left exactly as drawn, and their text is still ink
  everything else has to clear. Their box is measured as if the text
  were horizontal, which is an approximation for an angular dimension
  whose text follows its arc.
- **The width of a text box is an estimate.** A stroke font's glyphs
  are not all one width, and the text style's own width factor is
  reached through a handle this file does not follow. `cd:*charwidth*`
  is the escape hatch, and over-estimating is the safe direction: a box
  too wide leaves more room, a box too narrow leaves a text crowded.
  A formatted `MTEXT` obstacle is over-measured for the same reason --
  its `{\f...;}` codes are counted as glyphs.
- **A polyline's bulged edge is read as its chord.** The real arc bows
  away from the chord, so a text the chord clears can still be caught
  by the bulge. This is the one place the file is optimistic.
- **A dimension on a locked layer is reported, never written to** --
  `entmod` would be refused, and a run that skipped it silently would
  claim a sheet was cleared when it was not.
- Moving text with group 70 bit 128 set is what a drafter does by
  dragging its grip, so a style whose `DIMTMOVE` adds a leader on a
  moved text will add one here too. Since the move is along the
  dimension line and the across-the-track offset does not change, that
  leader has nowhere to go and does not appear in practice.
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

Runtime tests: the real file is loaded into `tests/lispvm.py` and both
commands are driven from a script against drawings built by `entmake`,
so the box geometry, the separating-axis test (a segment grazing an
edge is not an overlap), the glyph count, the track read off a rotated
and an aligned dimension, the `DIMTXT` override out of xdata, the
three-pass policy (including the case the tool exists for -- one text
on a line and one clear, overlapping each other, and only the first
moves), the reach and gap knobs, what is ink and what is not, Fit text
measured between its own two ends rather than as a justification, the
four skip reasons, a second run doing nothing, the undo group and Esc
are all measured against the file that actually ships.
