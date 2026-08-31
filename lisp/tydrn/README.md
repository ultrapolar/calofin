# TYDRN -- pool-only cleanup of a drone trace (AutoLISP / AutoCAD 2018+)

Applies the standardizing fixes to a traced drone drawing in one
command: point-label text onto the office style, the pool's survey
points onto `POINTS`, the anchor points recoloured, and every label
rotated to read west to east.

TYDRN is the sibling of `DRONE` (`lisp/drone/`) minus the two spa
steps: it does not sweep POINTs off layer `SPA` and it does not move
a spa outline onto `POOL` -- layer `SPA` is never touched at all. Use
TYDRN on a pool-only trace, or when whatever sits on `SPA` must stay
put; use `DRONE` for a pool + spa job.

## What it does

1. **TEXT** -- every highlighted (pre-selected) text entity is
   switched to style `ROMANC` at height 4.5, with color, linetype and
   lineweight forced to BYLAYER. If nothing is highlighted you are
   prompted to select text; Enter at that prompt processes ALL text in
   the drawing.
2. **POOL POINTS** -- every POINT entity on layer `POOL` (anywhere in
   the drawing) is moved to layer `POINTS`, everything BYLAYER
   (`POINTS` is magenta, so they show pink).
3. **ANCHOR POINTS** -- every POINT on layer `ANCHORS` is given an
   explicit magenta (ACI 6) color -- the same pink as the points --
   but stays on `ANCHORS`.
4. **ORIENT** -- the processed text is rotated flat so it reads west
   to east, right side up (absolute angle 0). Each text pivots about
   its own insertion point -- the labels share that point in space
   with the POINT they belong to -- so every label stays anchored to
   its point.

The `ROMANC` text style and the `POINTS` layer are created if missing.
Locked layers among those touched are unlocked for the run and
re-locked afterwards (on error too). The whole run is one undo mark,
and a done-line reports the counts.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `tydrn.lsp`, and load it (add
   it to the *Startup Suite* to have it every session). The shared
   build (`shared/LAZPASS.lsp`) carries it too.
2. Optionally pre-select the label text, then:

| Command | What it does |
| --- | --- |
| `TYDRN` | Run the fixes in one pass |
| `TYLERDRONESUITE` | `TYDRN`, then `PADDLE`, then `AUTODIM` |

## TYLERDRONESUITE — the whole drone trace in one

`TYDRN`, then `PADDLE`, then `AUTODIM`, in that order because that is the
order the work has to happen in: the points have to be on the right
layer before `PADDLE` can find the perimeter features to pad, and the
pads have to be in before `AUTODIM` dimensions what is there.

**Nothing is skipped or reworded.** Each stage is the command itself,
asking its own questions — so `TYDRN` still offers *"Select text to
update <Enter = all text in drawing>"*, and `PADDLE` and `AUTODIM` still
ask for what they need. The suite only supplies the order. Anything you
know about the three commands stays true here.

**Each stage keeps its own undo group.** Three `U`s back the suite out,
one per stage — deliberately, and for `XYPLOT`'s reason about its `ABHD`
handoff: a stage that went well should not have to be undone to get at
one that did not.

**All three are checked before any of them runs.** `PADDLE` and
`AUTODIM` live in other files, so on a one-file `APPLOAD` of `tydrn.lsp`
they may not be there. Half a suite is worse than none: `TYDRN` would
have moved the points and `PADDLE` dropped the pads, and you would find
out only at the end that the dimensioning you ran it for was never going
to happen. So a missing stage is named and nothing runs at all:

```
TYLERDRONESUITE needs PADDLE and AUTODIM, which are not loaded here.
  APPLOAD the missing file - or LAZPASS.lsp, which is the
  whole build in one - and run it again.  Nothing has been
  changed.
```

`Esc` in any stage stops the suite there — an AutoLISP error unwinds to
the command line, so the stages after it never start. What ran before it
stays run, which is the other reason the check happens first.

**There is a one-file edition for handing to someone.**
`editions/TYLERDRONE.lsp` is the whole `LAZPASS` build plus one button:
the orange hexagon opens the panel as ever, and an orange triangle
beside it runs the suite on one click. That is what to send — this file
on its own has no button and refuses to run, correctly, because two of
its three stages live elsewhere. Rebuild it with
`python3 tools/build_drone_edition.py`.

**It gets a screen button of its own — but only when this file is
loaded on its own.** An orange triangle, point north, on its own
one-button toolbar, drawn by `LAZPANEL.lsp` (which owns the icon
machinery). Inside the `LAZPASS` build it does not get one: the LazPanel
button is already on screen and carries the suite like every other tool,
so the whole build puts up a single external button. See
`lisp/lazpanel/README.md` for the switch, `lzp:*suitebutton*`.

The order lives in `*tydrn-suite*`, a list of three command names; the
`1 of 3` counting in the messages comes off it rather than being written
out again.

## Tunables

At the top of `tydrn.lsp`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `*tydrn-text-style*` | `"ROMANC"` | Style the text is switched to (created from the font below) |
| `*tydrn-text-font*` | `"romanc.shx"` | Font file for that style |
| `*tydrn-text-height*` | `4.5` | Text height applied |
| `*tydrn-pool-layer*` | `"POOL"` | Layer whose POINTs move |
| `*tydrn-dest-layer*` | `"POINTS"` | Where those POINTs go |
| `*tydrn-anch-layer*` | `"ANCHORS"` | Layer of the anchor POINTs |
| `*tydrn-pink*` | `6` (magenta) | Color for anchors and the POINTS layer |
| `*tydrn-orient-angle*` | `0.0` | Absolute text angle in degrees; set to `nil` to only flip upside-down text instead ("Most readable") |

## Notes & limitations

* Only single-line `TEXT` entities are restyled -- MTEXT, attributes
  and dimension text are left alone.
* Steps 2 and 3 sweep the whole drawing (`ssget "_X"`), not just a
  selection -- only the TEXT step is scoped by what you highlight.
* Rotating about the insertion point assumes each label was placed on
  its survey point; a label whose insertion point sits elsewhere
  swings about that spot instead.
* Loading TYDRN and DRONE together is safe -- separate `tydrn:` /
  `drone:` namespaces -- and the shared build carries both.
* Requires the Visual LISP engine (ActiveX is used throughout), which
  ships with full AutoCAD. AutoCAD LT cannot run this file.

## Tests

```
python3 tests/test_tydrn_suite.py
```

covers `TYLERDRONESUITE`: the order, that each stage goes through the
command line rather than being called directly, that a missing stage is
named and stops it before anything runs, and that the suite opens no
undo group of its own.


No dedicated test drives TYDRN yet. `python3 tests/test_shared.py`
loads it (with everything else) into the repo's AutoLISP VM, so a
file that no longer parses, or that collides with another tool's
names, fails there.
