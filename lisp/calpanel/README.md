# CALPANEL -- clickable button panel that launches the calofin tools (AutoLISP / AutoCAD 2018+)

## What it does

`CALPANEL` opens a dialog with one button per headline calofin command --
47 of them, grouped the way the drafter thinks about them, under the
same four group names the VB palette uses (a few commands sit in a
different group here than there):

| Group | Buttons |
| --- | --- |
| Layout | SPA, POOL, POOLDEMO, OASIS, FITABHD, ABHD, ADAB, CABHD, LHD, PADDLE, AUTOBEAD, CORNERSTP, HEMISTEP, NORMIESTEP, STOCKCOVER, WCALST |
| Points | ABCDEF, ALTABCDEF, XYPLOT, ABFIND, ABMOVE, PERPPTS, CPERPPTS, XFTCONV, DRONE, TYDRN |
| Dimensions | AUTODIM, AUTODIMSIDEPOV, STAIRDIM, FLOORDIM, DIMCONTEND, CDCREATE, CDCALLOUT, BPCALLOUT |
| Checking | CHECK, DIMARCCHECK, DIMCHECK, DIMSCAN, LINCHECK, LINFINCHECK, LINFINSCAN, COVERCHECK, COVERSCAN, SPACHECK, SPACHECKSCAN, LINTXTCHK, CCPRECHECK |

Clicking a button closes the panel and runs that command exactly as if
its name had been typed -- the panel adds nothing in front of a tool and
nothing behind it. A command that is not loaded in this session shows as
a greyed button instead of one that would fail, and the status line
across the top says how many tools the session has. `CALPANELVER`
prints the loaded version.

The point of the design is **zero install**: the dialog is plain DCL,
and CALPANEL.lsp writes its own `.dcl` into the system temp folder each
time the panel opens (and deletes it when the panel closes). There is no
second file to ship, no support-path entry to add, and no DLL to
`NETLOAD` -- unlike the VB.NET palette in `ui/`, which needs its
assembly loaded on every machine.

## Install & run

APPLOAD `CALPANEL.lsp` on its own, or load `shared/LAZPASS.lsp`, which
carries it along with every tool it lists. Type `CALPANEL`.

## Assumptions

- The system temp folder is writable (`vl-filename-mktemp` decides
  where it is). If it is not, the panel reports that it could not write
  the dialog file and leaves the session untouched.
- Command names on the roster are the headline drafting commands under
  `lisp/`. Satellites stay off the panel on purpose: `TUTORIAL*`
  walkthroughs, `*VER` reporters, `*RESCUE` companions, `-CFG` /
  `-SETUP` partners, `DCE` (DIMCONTEND's alias) and `STOCKLIST`
  (STOCKCOVER's listing companion). The `DD*` drone-height toolset
  stays off as a whole -- eight specialist photo-EXIF commands, not
  part of the drafting flow the panel serves. `LISPLAB` never appears:
  it is held back from the shared build as OMITTED. The deprecated
  acady matcher (`MATCHSTD`, `ACADY-*`) never appears.

## Notes & limitations

- DCL dialogs are modal, so the panel cannot stay docked and open while
  a tool runs the way the VB palette can: click, the panel closes, the
  tool runs, `CALPANEL` reopens it.
- The panel changes no system variables and draws nothing, so it takes
  no undo group; whatever it launches manages its own.
- The availability probe is the same one the VB palette uses (evaluate
  `C:<NAME>`; unbound symbols are nil), so commands loaded after the
  panel's file was loaded are still picked up, each time it opens.

## Tests

```
python3 tests/test_calpanel.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_calpanel.py # grouped tier
```

The test pins the roster to the tree: every headline command defined
under `lisp/` must have a button, held-back commands must not, so a new
tool without a button (or a button whose command does not exist) fails
the suite. It also checks the generated DCL is well formed and drives
`c:CALPANEL` end-to-end in the VM with the dialog surface stubbed.
