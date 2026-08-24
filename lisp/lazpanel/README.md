# LAZPANEL -- clickable button panel that launches the calofin tools (AutoLISP / AutoCAD 2018+)

## What it does

`LAZPANEL` opens a dialog with one button per headline calofin command --
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
across the top says how many tools the session has. `LAZPANELVER`
prints the loaded version.

**The screen button.** Loading the file also puts a one-button toolbar
named "LazPanel" on screen -- drag it anywhere or dock it like any
toolbar; clicking it opens the panel. It is created through the
ActiveX menu API (no CUI file to install) when no toolbar of that name
exists yet, and its icon -- an orange hexagon with a corner facing
north -- is generated as 16x16 and 32x32 `.bmp` files, each drawn at
its own resolution rather than the small one doubled, because a
hexagon doubled from 16 pixels keeps the 16-pixel staircase on its
diagonals and those diagonals are the whole shape. If the
toolbar gets closed or lost, `LAZBUTTON` brings it back; a toolbar
that is merely hidden is re-shown rather than duplicated, and one that
you have docked or moved is left where you put it.

Two details worth knowing, because both were wrong first time round:

- **The icon is written through an `ADODB.Stream` in binary mode, not
  with `write-char`.** AutoLISP writes text-mode files and has no NUL
  in its character model at all -- `(chr 0)` is the empty string --
  while a 24-bit BMP header carries 43 NULs before the first pixel.
  There is no arrangement of this format the language's own file
  output could produce. COM is not a new dependency: the toolbar the
  icon goes on is built through the same ActiveX API, so a session
  that cannot reach COM has no button to decorate.
- **The icon files live at a fixed name under `TEMPPREFIX` and are
  rewritten on every load**, because `SetBitmaps` stores the *path*,
  not the picture, and AutoCAD re-reads it whenever the button
  redraws. A toolbar that survives into a later session would
  otherwise be pointing at a swept temp file.

The point of the design is **zero install**: the dialog is plain DCL,
and LAZPANEL.lsp writes its own `.dcl` into the system temp folder each
time the panel opens (and deletes it when the panel closes). There is no
second file to ship, no support-path entry to add, and no DLL to
`NETLOAD` -- unlike the VB.NET palette in `ui/`, which needs its
assembly loaded on every machine.

## Install & run

APPLOAD `LAZPANEL.lsp` on its own, or load `shared/LAZPASS.lsp`, which
carries it along with every tool it lists. The button toolbar appears
on load; type `LAZPANEL` to open the panel directly, or `LAZBUTTON` to
re-summon the button.

## Assumptions

- The system temp folder is writable -- `vl-filename-mktemp` decides
  where the dialog goes, `TEMPPREFIX` where the icons go. If it is not
  writable, the panel reports that it could not write the dialog file
  and leaves the session untouched; the button simply keeps its
  default face.
- The screen button needs the ActiveX menu API (COM). Where it is
  unavailable or the CUI is locked, the button is quietly skipped --
  the panel itself never depends on it.
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
  tool runs, `LAZPANEL` reopens it. The screen button is the shortcut
  for that reopen.
- A toolbar created through the ActiveX API may or may not survive an
  AutoCAD restart, depending on how the main CUI is saved. That is why
  every load re-creates it when it is missing, and re-ices and re-shows
  it when it is not: sessions that load LAZPANEL.lsp or LAZPASS.lsp
  always end up with a visible button carrying a current icon, and one
  that somehow lost it can type `LAZBUTTON`.
- If the button cannot be added to a freshly created toolbar, that
  toolbar is deleted again rather than left behind. An empty "LazPanel"
  would be found by name for ever afterwards, and `LAZBUTTON` would
  report success while putting nothing on screen.
- The panel changes no system variables and draws nothing, so it takes
  no undo group; whatever it launches manages its own.
- The availability probe is the same one the VB palette uses (evaluate
  `C:<NAME>`; unbound symbols are nil), so commands loaded after the
  panel's file was loaded are still picked up, each time it opens.

## When the button comes up blank

The picture is best effort and fails quietly on purpose -- a missing
icon must never stop the panel working. `LAZICON` is the way to find
out why: it walks the same steps out loud and prints where each one
got to.

```
LAZICON: where the button's picture comes from.
  TEMPPREFIX : C:\Users\you\AppData\Local\Temp\
  small      : C:\Users\you\AppData\Local\Temp\lazpanel-16.bmp
  large      : C:\Users\you\AppData\Local\Temp\lazpanel-32.bmp
  written    : yes, as a VT_UI1 array
  on disk    : found
  SetBitmaps : accepted - the button should show it now
```

The two steps most likely to fail, and what they mean:

- **`written : NO`** -- the bytes never reached the disk. The reason is
  printed after it. The usual cause is the byte array: writing binary
  from AutoLISP needs a `VT_UI1` safearray, and `vlax-make-safearray`'s
  documented type constants stop at `vlax-vbVariant`, so whether type
  17 is accepted is a property of the release rather than of this code.
  A second spelling is tried before giving up, and the line says which
  one worked.
- **`SetBitmaps : <error>`** -- the files were written but AutoCAD would
  not take them for the button.

## Tests

```
python3 tests/test_lazpanel.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_lazpanel.py # grouped tier
```

The test pins the roster to the tree: every headline command defined
under `lisp/` must have a button, held-back commands must not, so a new
tool without a button (or a button whose command does not exist) fails
the suite. It validates the generated DCL with a grammar pass, drives
`c:LAZPANEL` end-to-end in the VM with the dialog surface stubbed
(executing the real button-wiring expression), and checks the toolbar
creation path and both generated bitmaps pixel by pixel -- position,
not just colour count, since a BMP stores its rows bottom-up and an L
is not symmetric.

The stubs go in *before* the file loads, so the load-time toolbar call
is itself under test: delete it and the suite fails rather than
quietly passing.
