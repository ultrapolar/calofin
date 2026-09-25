# PERPMARKSTAMP -- PERPMARK's round, with the distance stamped beside every mark as it is drawn (AutoLISP / AutoCAD 2018+)

`PERPMARK` marks what the tape read at a survey point -- a circle of
that radius and a line of that length square off the wall -- and only
when the round is joined into a polyline does each line become a
dimension that says the number. A round that is **not** joined (a
bench sketched in for a look, a gutter noted for the next drafter, the
marks of a step kept as marks) leaves a circle and a line at every
point and no number anywhere, so the drafter turned to `DIMSTAMP` and
stamped each distance by hand, reading the sheet a second time to do
it.

`PERPMARKSTAMP` is `PERPMARK` with that stamp folded in. Every
question is `PERPMARK`'s, asked in `PERPMARK`'s words, and after each
mark is drawn there is one more:

```
Click where to stamp 3'-8" for Pt.17 [Skip/Back] <at the mark's end>:
```

It copies nothing of `PERPMARK`: it installs the **hook** `PERPMARK`
v1.13 carries for it (`pm:run-hooked`, see `lisp/perpmark/README.md`)
and hands over. So it needs `PERPMARK` v1.13 or later loaded --
APPLOADed alone without it, it says so and stops; in the `LAZPASS.lsp`
build the two load together.

## What it does

1. **Everything `PERPMARK` does**, in its order: the perimeter, the
   side click on an open wall, then a survey point and its distance,
   for as long as the sheet lasts, then the polyline, its two ends and
   the dimension style.
2. **After each mark, where to stamp it.** The prompt names the
   distance as it will be written and the point it was taped at:
   - **Enter** stamps it at the far end of the mark, where the tape
     reached;
   - **a click** stamps it there instead;
   - **`Skip`** stamps nothing for this mark, which is then a plain
     `PERPMARK` mark;
   - **`Back`** takes the mark away again, exactly as `Back` at the
     next point prompt would -- the distance was typed a moment ago,
     and this is the first place its circle can be seen to be wrong.
3. **The stamp is `DIMSTAMP`'s**: an MTEXT on the `TEXT` layer in the
   `Attributes` style, 6" high, attached top left at the point, ByLayer,
   upright in the current UCS, its fraction stacked the way the shop's
   own dimension text stacks one (`\A1;44{\H1.0000x;\S1/2;}"`). It is
   spelled the way the distance was **typed** -- `44 1/2"` for one
   typed in inches, `3'-8 1/2"` for one typed in feet -- since that is
   what the ruler beside the distance prompt was showing. A distance
   clicked off the ruler or measured between two points takes the
   family of the last one typed (inches, until one is).

### What rides on the mark

A stamp belongs to the mark it was made for. `Back` at the next point
prompt takes the last mark **and** its stamp away; naming a point a
second time replaces the mark and the stamp both; a `Skip` leaves a
mark with no stamp. When the round is joined into a polyline the
circles go and the lines become dimensions, as in `PERPMARK`, and the
stamps **stay**: they are drawing text, not working marks, and the
drafter who placed them meant them to be read. A round answered `No`
to the polyline keeps its marks and its stamps together.

One undo group, `PERPMARK`'s: a single `U` takes the whole round back,
stamps included. Esc anywhere -- the stamp prompt included -- is
`PERPMARK`'s Esc: its settings back, its ruler down, its group closed,
and the failure reported under `PERPMARKSTAMP`, whose LAZDIAG run
`PERPMARK`'s joined, with every answer from both.

## Install & run

`APPLOAD` `PERPMARK.lsp` and then `PERPMARKSTAMP.lsp` (or the whole
build, `shared/LAZPASS.lsp`, which has both), then type
`PERPMARKSTAMP`. `PERPMARKSTAMPVER` prints the loaded version.

## Tunables

At the top of the file, between the version banner and the first
`defun`. They are `DIMSTAMP`'s knobs under this file's prefix -- a
stamp is a stamp whichever command placed it -- so change `DIMSTAMP`'s
to match, or a stamp placed here and one placed there stop looking
alike. `LAZTUNE`'s **Set everywhere** moves both at once.

| Knob | Default | What changing it does |
| --- | --- | --- |
| `pms:*layer*` | `"TEXT"` | Where the stamps land. Created when the drawing lacks it; thawed, unlocked and switched on when it is there but unusable |
| `pms:*layer-color*` | `7` | The ACI that layer is CREATED with, on a drawing that lacks it. A number, never `'auto`: a layer record outlives the command. The stamp itself is ByLayer |
| `pms:*style*` | `"Attributes"` | The text style the stamps are written in. A drawing without it gets a plain variable-height style of that name made, and is told so |
| `pms:*text-hgt*` | `6.0` | MTEXT height of a stamp |
| `pms:*text-width*` | `0.0` | Its wrap width; 0 is no wrap, so a distance never breaks across two lines |
| `pms:*line-space*` | `1.0` | Line space factor, at the "at least" spacing style |

The marks, the layers, the ruler and the dimensions are `PERPMARK`'s
knobs (`pm:*`), and this command reads them exactly as `PERPMARK` does.

## Notes & limitations

- **It stamps the distance and nothing else** -- not the point number,
  not a letter. `DIMSTAMP` is there for a label.
- **A re-mark asks again.** The old stamp goes with the old mark, and
  the new answer is where the new stamp goes; a stamp is never moved.
- **A stamp is not read back.** The dimensions `PERPMARK` draws at the
  join are still the measurement of record; a stamp is the number
  written beside it.
- **The prompt takes a click or a keyword only.** A distance is not
  retyped here -- it was typed at the prompt before, and `Back` is the
  way to change it.
- **It needs `PERPMARK` v1.13 or later.** An older `PERPMARK` loads but
  cannot take the hook, and is told apart from none: the message says
  which version it wants.

## Tests

```
python3 tests/test_perpmarkstamp.py
CALOFIN_LISP_ROOT=shared python3 tests/test_perpmarkstamp.py
```

Runtime tests: `PERPMARK.lsp` and this file are loaded into
`tests/lispvm.py` and `c:PERPMARKSTAMP` is driven from a script, so
Enter's stamp at the mark's end, a click's stamp where it landed,
`Skip`, `Back` at the stamp prompt and at the next point prompt, the
re-mark, the join leaving the stamps standing, the spelling following
the typed family, the MTEXT's properties and the knobs, the missing
style being made, the ruler being down at the stamp prompt, the hook
being consumed so a plain `PERPMARK` run after this one (or after an
Esc inside it) stamps nothing, Esc at the stamp prompt, and the run
without `PERPMARK` loaded are all measured against the files that
ship.
