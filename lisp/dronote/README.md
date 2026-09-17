# DRONOTE — canned drone-photo review note (AutoLISP)

`DRONOTE` drops one of three canned notes — the ones that come up over
and over reviewing a job built off a drone photo — wherever you click,
as many times as you like.

| Keyword | Note |
| --- | --- |
| `Board` | How far is the diving board base from water's edge? |
| `Anchors` | Some anchors are not visible in the drone photo provided. |
| `Slide` | Please provide a detailed sketch to locate slide base for proper cover treatment. |

## What it does

1. Asks which of the three notes you want.
2. Places that note as an MTEXT at every point you click, on the
   `NOTES` layer (created, or switched on / thawed / unlocked if it is
   there but unusable) — Enter when done.
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
DRONOTE: 2 notes placed on layer NOTES.
```

## Revisions

`DRONOTE.lsp` carries the auto-stamped banner
`(setq *dronote-version* "v1.0")` that `tools/release_lisp.py` reads;
run it after any change and the dated twin
`releases/DRONOTE_MMDDYY_REV10.lsp` regenerates itself. Bump the
banner with every revision.

* **v1.0** — first release.

## Tunables

Drawing units are assumed to be **inches** (architectural). Every knob
sits in the tunables block at the top of `DRONOTE.lsp`, each with its
explanation beside it; change a value there, or `setq` it after
loading from a startup file:

| Variable | Default | Meaning |
| --- | --- | --- |
| `dn:*layer*` | `"NOTES"` | Layer every note lands on — created when missing, thawed / unlocked / switched on when unusable |
| `dn:*layer-color*` | `2` | ACI colour a *created* `NOTES` layer gets (yellow); an existing layer keeps its own |
| `dn:*text-hgt*` | `6.0` | MTEXT height of a placed note |
| `dn:*text-width*` | `96.0` | MTEXT reference width (8'), so a long note wraps instead of running clear across the sheet |

The three notes themselves are `dn:*notes*`, keyed by the same words as
`dn:*kws*` (the bracketed choices) — edit the text there to change the
wording, or add a fourth pair and its word to `dn:*kws*` to offer a new
note (bump the version banner and re-run the registration tooling if
you do).

## Tests

`tests/test_dronote.py` loads the real lisp into the repo's AutoLISP
VM and drives `DRONOTE` end to end — each of the three notes, placing
more than one, Back removing the last placement, Back at the first
prompt of a run stepping back to the note choice, the `NOTES` layer
created / frozen / locked / off, and Esc at both prompts:

```
python3 tests/test_dronote.py
CALOFIN_LISP_ROOT=shared python3 tests/test_dronote.py   # grouped build
```
