# XYPLOT.lsp — graph an X/Y sheet, twice

`XYPLOT` is `ABCDEF`'s sister command, for the survey that arrives already
reduced. Where `ABCDEF` is handed four tape distances per point and has to
work out where the point is, `XYPLOT` is handed the answer — an X and a Y
off one origin — and only has to draw it.

Load `XYPLOT.lsp` (APPLOAD), type `XYPLOT`, pick the sheet, then pick where
the origin goes in the drawing. That is the only thing the sheet cannot
say, and it is the only thing the command asks for.

`XYPLOTVER` prints the loaded version.

## Spreadsheet format

CSV is read natively; `.xlsx/.xls/.xlsm` go through Excel COM automation.
Columns are found by header text, in any order:

```
POINT NAME | X | Y
```

Headers may also read `X OFFSET` / `Y OFFSET`, `EASTING` / `NORTHING`, or
`X COORD` / `Y COORD`. A sheet with no recognisable headers at all is still
read as name, X, Y in the first three columns — which is the shape everyone
writes anyway.

Values are architectural feet-inches or plain decimal inches, negatives
included: `12'-3 1/2"`, `-4'-0"`, `37.25`, `3 1/2"` all read. Positive X is
to the right and positive Y is up, from the origin you picked.

The feet-inch parser is `ABCDEF`'s, repairs and all (`O`/`I` for `0`/`1`,
smart quotes, a missing foot mark, a `/` scanned as a `1`, a fraction split
by a stray space) — it is the same handwriting either way. Every repair is
logged so it can be checked.

A row missing either coordinate is skipped and named in the report.

## The two graphs

```
   GRAPH 1                          GRAPH 2
    .P3                              .P3
       .P1                              .P1
    .P2                              .P2
                                 |--4'-2"--|--3'-6"--|
   points as given               the same, dimensioned
```

**Graph 1 — the points as given.** Every point at its X/Y off the origin,
labelled with its name from the sheet, drawn as an **`ab_pt` block on layer
`POINTS`**: the same survey point `XFTCONV` produces from a Leica import,
which is what `ABHD`, `CABHD`, `ADAB`, `ABFIND`, `BPCALLOUT` and `LHD`
already read. Axes through the origin and a frame round the extents come
with it.

**Graph 2 — the same points, dimensioned linearly.** A second copy a clear
gutter to the right, with the X offsets dimensioned as one continuous chain
along the bottom and the Y offsets as another down the left side. Each
dimension's extension lines grow from the two points it spans, so every
rung is visibly tied to the points it measures. Read left to right (or
bottom to top) a chain is the sheet's column of values turned into the gaps
between them — the form a fitter actually lays out from.

Two rules keep the chains readable: offsets closer together than 1/16"
share one stop (a rung a sixteenth wide tells nobody anything), and the
origin is a stop like any other, wherever it falls among the points.

Only graph 1 carries `ab_pt` blocks. Graph 2's markers are plain `POINT`s
on `XYPLOT-POINTS`, deliberately: two `ab_pt` copies of one survey in one
drawing would hand `ABHD` the same pool twice and it would try to fit a
perimeter around both.

The dimensions **measure the drawn geometry** rather than reprinting the
sheet's text, so a value that did not survive the trip shows up as a
dimension that disagrees with its own column in the report. They land on
layer `DIMENSION` in the drawing's current dimension style, the same as
`AUTODIM`'s and `WCALST`'s.

## Layers

| Layer | What is on it |
| --- | --- |
| `POINTS` | graph 1's `ab_pt` survey points — nothing else |
| `XYPLOT-FRAME` | both frames, both sets of axes, the titles |
| `XYPLOT-POINTS` | graph 2's plain point markers |
| `XYPLOT-LABELS` | graph 2's point names |
| `DIMENSION` | both dimension chains |

## The report

Printed to the command line **and** written to `<sheet>_XYPLOT_report.txt`
beside the spreadsheet: every point with its X and Y in both feet-inches
and decimal inches, the overall extents, the rung counts of both chains,
and any row that was skipped, with which coordinate it was missing.

## What happens next

The run ends by offering to fit the pool perimeter straight away: answer
`Yes` and **graph 1's** points are pre-selected and `ABHD` starts on them.
(Loaded on its own rather than as part of the calofin build, `XYPLOT.lsp`
says so and leaves the points ready instead.)

## Verification

AutoLISP only runs inside AutoCAD, so `tests/test_xyplot.py` runs the
actual LISP in the repo's AutoLISP VM (`tests/lispvm.py`) — the whole
command, prompts to report — and checks the coordinate arithmetic, the
chain building (including points sharing a value, which is where a
`vl-sort` would have silently dropped one), the two graphs' separation, the
layer split between them, and the ABHD handoff:

```
python3 tests/test_xyplot.py
CALOFIN_LISP_ROOT=shared python3 tests/test_xyplot.py   # the grouped build
```

`template.csv` in this folder is a small sheet in the expected format.
