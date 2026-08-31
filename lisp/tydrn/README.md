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
| `TYLERDRONESUITE` | `TYDRN`, then `PADDLE`, then `AUTODIM`, then `CDIM` |

## TYLERDRONESUITE — the whole drone trace in one

`TYDRN`, then `PADDLE`, then `AUTODIM`, then `CDIM`, in that order
because that is the order the work has to happen in: the points have to
be on the right layer before `PADDLE` can find the perimeter features to
pad, the pads have to be in before `AUTODIM` dimensions what is there,
and the dimensions have to exist before `CDIM` cleans them up.

**The trace is highlighted once, not once per command.** All three
calofin stages want the same thing picked — `TYDRN` the text in it,
`PADDLE` the perimeter, `AUTODIM` the plan — and AutoCAD clears the
pickfirst set the moment a command consumes it. Run by hand that means
selecting the same trace three times. Here the suite reads the highlight
at the start and puts it back before each stage, so every stage opens
with exactly what you picked and takes from it whatever its own filter
takes. Highlight nothing first and the suite asks once, up front; press
`Enter` there and each stage asks on its own, exactly as it does alone.

**The carried selection grows by what each stage draws**, because a
later stage is meant to see the earlier ones' work — that is the whole
reason for the order. `AUTODIM`'s filter takes `INSERT`s precisely so it
dimensions the pads `PADDLE` just dropped; handing it your original
highlight and nothing else would hide every one of them. Anything a
stage erases drops out of the set the same way, so nothing dead is
handed on.

`CDIM` is handed a **cleared** selection. It tidies the dimensions
`AUTODIM` has just made, and those are in nobody's original pick —
typed by hand after `AUTODIM` it starts with nothing selected too.

`PICKFIRST` is forced to `1` for the run and put back afterwards
(including on `Esc`). At `0`, `sssetfirst` still highlights but
`ssget "_I"` reads nothing, and the whole handoff would go quietly
missing — the one failure mode worth spending a sysvar to rule out.

**Nothing is skipped or reworded.** Each stage is the command itself,
asking its own questions — so `TYDRN` still offers *"Select text to
update <Enter = all text in drawing>"*, and `PADDLE` and `AUTODIM` still
ask for what they need. The suite supplies the order and the highlight.
Anything you know about the four commands stays true here.

**`CDIM` is not calofin's.** It is the dimension-cleanup command the
shop has on its own machines, and calofin has always known its name
without ever running it: `COVERCHECK`, `LINFINCHECK` and `SPACHECK` each
name it in a tunable (`*cchk-dimfix-cmd*` and friends) to *suggest* it
after a check. The suite is the first thing here that actually calls it.
Two consequences, both deliberate:

* It is reached as `_CDIM`, without the dot. Calofin's own stages go
  through `_.` like every other handoff in the tree, because the dot
  means *the built-in command of this name, whatever anyone has
  redefined* — and a shop command is exactly the redefinition we are
  trying to reach.
* It is **not** in the pre-flight check below. `boundp` only sees
  commands AutoLISP defined; `CDIM` may be .NET, ARX or a PGP alias, so
  asking whether it is loaded would report it missing on a machine where
  it works perfectly. It runs last, after everything calofin can do is
  already done, so a shop without it loses only the cleanup.

If your shop calls it something else, or does not have it, one line in
the tunables below retunes or turns it off.

**Each stage keeps its own undo group.** Three `U`s back the suite out,
one per stage — deliberately, and for `XYPLOT`'s reason about its `ABHD`
handoff: a stage that went well should not have to be undone to get at
one that did not.

**The three calofin stages are checked before any of them runs.**
(`CDIM` is not, for the reason above.) `PADDLE` and
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

**It is on the LazPanel.** `TYLERDRONESUITE` has a button on the panel's
`Rest` and `Points` pages, captioned *Drone suite: tidy, pad, dim* — so
the whole job is one click from the panel, and there is nothing to type.
That is what it is for: `LAZPASS.lsp`, open the panel, click it, answer
the three stages' own prompts as they come.

The order lives in `*tydrn-suite*` (the three calofin stages) plus
`*tydrn-finish-cmd*` (the finisher); the `1 of 4` counting in the
messages comes off both together, so it can never disagree with what
actually runs.

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
| `*tydrn-suite*` | `("TYDRN" "PADDLE" "AUTODIM")` | The calofin stages `TYLERDRONESUITE` runs, in order — also the list the pre-flight check reads |
| `*tydrn-finish-cmd*` | `"CDIM"` | Shop command run last, after the stages above. Set to another name for a shop that calls it something else, or to `nil` to stop after `AUTODIM` |

`PADDLE` and `AUTODIM` now use a selection that is already highlighted
when they start, instead of asking for one — the way every native
AutoCAD command behaves, and what lets the suite hand them the same
pick. With nothing highlighted they prompt exactly as they always did,
`Enter` and all, so running either on its own is unchanged.

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
named and stops it before anything runs, that the suite opens no undo
group of its own, and that `CDIM` is reached without the dot while
calofin's own keep it — plus retuning and turning off the finisher, and
the handoff itself: that one highlight reaches all three calofin stages,
that it grows to include the pads `PADDLE` drew, that an erased entity
is not passed on, that `CDIM` gets a cleared selection, and that
`PICKFIRST` is put back.


No dedicated test drives TYDRN yet. `python3 tests/test_shared.py`
loads it (with everything else) into the repo's AutoLISP VM, so a
file that no longer parses, or that collides with another tool's
names, fails there.
