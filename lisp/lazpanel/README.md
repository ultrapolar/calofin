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
ActiveX menu API (no CUI file to install) the first time no toolbar of
that name exists, and its icon -- an orange L, a placeholder until
there is a real logo -- is generated as 16x16 and 32x32 `.bmp` files
in the temp folder. If the toolbar gets closed or lost, `LAZBUTTON`
brings it back. AutoLISP can only write text-mode files, so the
bitmaps are built so that no byte equals 10 (or 13): a newline byte
would be translated in transit and shear the image. The test suite
pins that invariant.

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

- The system temp folder is writable (`vl-filename-mktemp` decides
  where it is). If it is not, the panel reports that it could not write
  the dialog file and leaves the session untouched; the button skips
  its icon.
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
  the file re-creates it (only when missing) on every load: sessions
  that load LAZPANEL.lsp or LAZPASS.lsp always end up with the button,
  and one that somehow lost it can type `LAZBUTTON`.
- The panel changes no system variables and draws nothing, so it takes
  no undo group; whatever it launches manages its own.
- The availability probe is the same one the VB palette uses (evaluate
  `C:<NAME>`; unbound symbols are nil), so commands loaded after the
  panel's file was loaded are still picked up, each time it opens.

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
creation path and both generated bitmaps byte by byte -- including the
no-newline-byte invariant that keeps them writable from AutoLISP.
