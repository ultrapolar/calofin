# Releasing, versions, and the tutorial

## Two files, identical contents

Every build exists twice:

| File | Purpose |
| --- | --- |
| `dimcheck.lsp` | The **static name**. Your `APPLOAD` / startup suite points here, so it never has to change. |
| `releases/DIMCHECK_MMDDYY_REV##.lsp` | The **same bytes**, named for the build. This is the copy you hand to someone else. |

They are byte-identical on purpose — the release script compares them
and refuses to publish if they ever drift. Both carry the same stamp
*inside* the file:

```lisp
(setq *dchk-version* "DIMCHECK 081726 REV01")
```

so **`DIMCHECKVER`** answers "which build is this?" even if the file was
renamed, copied into someone's stack, or emailed around. The stamp also
prints on load and appears in the header of every DIMCHECK and DIMSCAN
report, so a printed report says which build checked the drawing.

## Cutting a release

```
python3 tools/release.py                # stamp today's next revision + write the twin
python3 tools/release.py --rev 3        # force REV03
python3 tools/release.py --date 090126  # stamp a different MMDDYY
python3 tools/release.py --check        # report the stamp, verify the twin, change nothing
```

`release.py` stamps `dimcheck.lsp` **first** and then copies it, so the
twin can never differ from what you actually load. Revisions
auto-increment per date: the first cut on a day is `REV01`, the next
`REV02`, and tomorrow starts again at `REV01`.

Run `--check` in CI or before handing a file out; it exits non-zero if
the twin is missing or has drifted.

### Workflow

1. Edit `dimcheck.lsp` and test it.
2. `python3 tools/release.py`
3. Commit both files — the `releases/` folder is the history of what
   went out, so old revisions stay exactly as distributed.

Old revisions are **not** re-stamped. `DIMCHECK_081726_REV01.lsp` keeps
saying `REV01` forever, which is what makes it useful for working out
what someone is running.

## Adding another tool

`release.py` is driven by one table:

```python
TOOLS = {
    "dimcheck": ("dimcheck.lsp", "*dchk-version*", "DIMCHECK"),
}
```

Add a row — `"pool": ("pool.lsp", "*pool-version*", "POOL")` — give the
new file a `(setq *pool-version* "POOL 010126 REV01")` line and a
`c:POOLVER`, and `python3 tools/release.py pool` writes
`pool/releases/POOL_MMDDYY_REV##.lsp` the same way.

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
