# Releasing, versions, and the tutorial

## Two files, identical contents

Every build exists twice:

| File | Purpose |
| --- | --- |
| `lisp/dimcheck/dimcheck.lsp` | The **static name**. Your `APPLOAD` / startup suite points here, so it never has to change. |
| `releases/dimcheck/DIMCHECK_MMDDYY_REV##.lsp` | The **same bytes**, named for the build. This is the copy you hand to someone else. |

They are byte-identical on purpose. Both carry the same stamp *inside*
the file:

```lisp
(setq *dchk-version* "DIMCHECK 081726 REV01")
```

so **`DIMCHECKVER`** answers "which build is this?" even if the file was
renamed, copied into someone's stack, or emailed around. The stamp also
prints on load and appears in the header of every DIMCHECK and DIMSCAN
report, so a printed report says which build checked the drawing.

## Cutting a release

This tool's own `tools/release.py` (argparse, `--rev`/`--date`/`--check`,
one-table-per-tool) was retired when the repo's release scripts were
consolidated into the shared `python3 tools/release_lisp.py` (see the
top-level README). That script drives off a `*name-version*
"vMAJOR.MINOR"` banner, which is the convention `CORNERSTP`/`HEMISTEP`/
`NORMIESTEP` use — DIMCHECK's own stamp format
(`*dchk-version* "DIMCHECK 081726 REV01"`) isn't one it understands yet.

Until it is extended to read that format too, cut a DIMCHECK release by
hand:

1. Edit `dimcheck.lsp` and test it.
2. Bump the `*dchk-version*` stamp to the new date/REV.
3. Copy the file byte-for-byte to
   `releases/dimcheck/DIMCHECK_MMDDYY_REV##.lsp` (delete the previous
   dated copy for the same tool - old revisions stay in git history).
4. Commit both files.

Old revisions are **not** re-stamped. `DIMCHECK_081726_REV01.lsp` keeps
saying `REV01` forever, which is what makes it useful for working out
what someone is running.

## TUTORIALDIMCHECK

`TUTORIALDIMCHECK` teaches the tool two ways, because people learn
differently. It asks up front:

* **List** — every check spelled out at the command line, grouped by
  what it looks at (dimensions, arcs, overlaps, steps, wall height,
  liner, border, the report). It offers to drop the same list into the
  drawing as an MTEXT reference sheet you can plot or keep on a layout.
  The list is generated from the live tunables, so it always quotes the
  real numbers — the actual tread spacing, layer names and nominal
  border size, not stale documentation.
* **Demo** — draws a small practice drawing in an empty spot you pick,
  with four faults planted in it, and walks you through them one at a
  time, zooming to each and explaining what DIMCHECK sees:
  1. two lines overlapping,
  2. a dimension point sitting off the geometry (this is where the
     red X / green + and Move / Keep / Pick choice are explained),
  3. a step side view with its overall-height dimension,
  4. an arc whose ends attach to nothing.
  It then offers to run DIMSCAN so you see a real report, and to erase
  the practice drawing afterwards.
* **Both** — the list, then the demo.

The whole tutorial runs inside one UNDO group, so a single `U` removes
everything it drew. It never touches existing geometry.
