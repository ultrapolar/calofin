# DRONOTE — canned drone-photo review note (AutoLISP)

`DRONOTE` drops one of three canned notes — the ones that come up over
and over reviewing a job built off a drone photo — wherever you click,
as many times as you like, written the way the shop's own review notes
are: the standing header first, the note bulleted under it.

```
*All listed issues must be resolved to proceed with design*
- Some anchors are not visible in the drone photo provided.
```

| Keyword | Note |
| --- | --- |
| `Board` | How far is the diving board base from water's edge? |
| `Anchors` | Some anchors are not visible in the drone photo provided. |
| `Slide` | Please provide a detailed sketch to locate slide base for proper cover treatment. |

## What it does

1. Asks which of the three notes you want.
2. Places that note as one MTEXT at every point you click — the
   header line, then the note itself bulleted under it — with its
   **top left corner** at the point, Enter when done. It lands on the
   `TEXT` layer (created, or switched on / thawed / unlocked if it is
   there but unusable), ByLayer, in the `Attributes` style at 9.5,
   wrapped at the width the shop's note blocks carry. A drawing
   without that style gets a plain one of the name made from
   `dn:*style-font*`, and is told so; a drawing that has it keeps its
   own font and height.
3. **Back** at the point prompt un-places the last note instead of
   ending the run, so a bad click costs one `Back` rather than a
   manual erase. **Back** with nothing placed yet steps back to the
   note choice, so you can pick a different one before placing
   anything.

Run the command again to place a different note elsewhere in the
drawing.

## Usage

1. Load `DRONOTE.lsp` (`APPLOAD`, or drag it into the drawing).
2. Type `DRONOTE`.
3. Answer `Which note? [Board/Anchors/Slide]`.
4. Click a point for the note; repeat for as many spots as it applies
   to; Enter when done.

The command prints what it did, e.g.:

```
DRONOTE: 2 notes placed on layer TEXT.
```

## Revisions

`DRONOTE.lsp` carries the auto-stamped banner
`(setq *dronote-version* "v1.1")` that `tools/release_lisp.py` reads;
run it after any change and the dated twin
`releases/DRONOTE_MMDDYY_REV11.lsp` regenerates itself. Bump the
banner with every revision.

* **v1.1** — the note is written the way the shop's own is: the
  standing header (`dn:*header*`) on the first line with the note
  bulleted under it, on layer `TEXT` in the `Attributes` style at 9.5,
  wrapped at 440.1875, lines spaced "at least" — the properties read
  off a note out of the drafter's own drawing. The style is created
  from `dn:*style-font*` when the drawing lacks it.
* **v1.0** — first release.

## Tunables

Drawing units are assumed to be **inches** (architectural). Every knob
sits in the tunables block at the top of `DRONOTE.lsp`, each with its
explanation beside it; change a value there, or `setq` it after
loading from a startup file:

| Variable | Default | Meaning |
| --- | --- | --- |
| `dn:*layer*` | `"TEXT"` | Layer every note lands on — the shop's own text layer, the one its note blocks and DIMSTAMP's stamps are already on. Created when missing, thawed / unlocked / switched on when unusable |
| `dn:*layer-color*` | `4` | ACI colour a *created* `TEXT` layer gets (cyan, what the office template carries); an existing layer keeps its own, and the note is ByLayer either way |
| `dn:*style*` | `"Attributes"` | Text style a note is written in — the shop's own |
| `dn:*style-font*` | `"arialbd.ttf"` | Font a *created* style of that name carries; a style already in the drawing keeps its own |
| `dn:*text-hgt*` | `9.5` | MTEXT height of a placed note |
| `dn:*text-width*` | `440.1875` | MTEXT reference width, so a long note wraps instead of running clear across the sheet — the width the shop's own note blocks carry |
| `dn:*line-space*` | `1.0` | Line space factor, at the "at least" spacing style: what sets the note under its header |
| `dn:*header*` | `"*All listed issues must be resolved to proceed with design*"` | The standing first line of every note. `""` writes the note with no header over it |
| `dn:*bullet*` | `"- "` | What the note itself is prefixed with under that header |

The three notes themselves are `dn:*notes*`, keyed by the same words as
`dn:*kws*` (the bracketed choices) — edit the text there to change the
wording, or add a fourth pair and its word to `dn:*kws*` to offer a new
note (bump the version banner and re-run the registration tooling if
you do).

## Tests

`tests/test_dronote.py` loads the real lisp into the repo's AutoLISP
VM and drives `DRONOTE` end to end — each of the three notes, the
header and every MTEXT property the note carries, the `Attributes`
style made when the drawing lacks it and left alone when it has it, an
emptied `dn:*header*`, placing more than one, Back removing the last
placement, Back at the first prompt of a run stepping back to the note
choice, the `TEXT` layer created / frozen / locked / off, and Esc at
both prompts:

```
python3 tests/test_dronote.py
CALOFIN_LISP_ROOT=shared python3 tests/test_dronote.py   # grouped build
```
