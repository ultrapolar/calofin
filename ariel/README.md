# Ariel anchor placer (`ariel/`)

A Windows helper for the part of the Ariel (Fisherlea) workflow that is
pure repetition: digitising the deck markers in a rectified drone photo.
The markers are already in the picture — the coloured dots taped to the
deck before the flight — so the program finds them, walks them in order,
clicks each one, and magnifies it so you can say yes.

**This is not an AutoLISP tool.** It is a Python program that drives the
mouse and the screen. It is not in `LAZPASS.lsp`, it has no
`shared/parts/` twin, it is not on the LAZPANEL palette and it is not in
`releases/` — there is no AutoCAD anywhere near the point in the job
where it runs. It lives in this repository because it is the same job as
`DroneDistortion`, one step earlier. See "Where it does not belong",
below.

## Running it

Windows, Python 3.8 or newer, nothing to install: `ctypes` and `tkinter`
both ship with Python.

```
python ariel\anchors.py
```

or double-click `ArielAnchors.pyw` (no console; it logs to
`%TEMP%\ariel-anchors.log`).

Have Ariel on screen with the photo where you want it, then:

1. **The screen is captured, once.** Everything after this works on that
   one picture, so nothing can scroll or pop up between what you select
   and what gets searched.
2. **Drag the area with the dots in it.** Enter takes the whole desktop,
   Esc gives up. The picker shows you the captured screenshot rather
   than the live screen, so what you drag out is provably the pixels
   that get searched. `--region X,Y,W,H` and `--full` skip the step
   entirely — worth using on a wall of monitors, where putting the whole
   desktop on screen again costs a second or two.
3. **The dots are found and numbered**, and the numbered picture is laid
   over your screen at 1:1 so it reads as your own photo marked up:

   | | |
   | --- | --- |
   | `Enter` | place them |
   | click a dot | remove it — it is not a marker |
   | click bare deck | add one there — a marker that was missed |
   | right-click a dot | make it number 1 |
   | `o` | cycle perimeter → reading → nearest |
   | `x` | reverse the direction |
   | `c` | move the starting corner |
   | `Esc` | cancel the run |

   `--no-review` goes straight to placing.
4. **Then one anchor at a time**: it clicks, Ariel draws, the magnifier
   opens in the far corner showing the result at 8×, and it waits.

   | | |
   | --- | --- |
   | `Enter` / `Space` | yes — next anchor |
   | arrow keys | nudge one pixel (`Shift`: ten) |
   | `D` | click here again |
   | `S` | skip this one |
   | `Backspace` | back to the previous anchor |
   | `P` | pause — let the keyboard through to Ariel |
   | `Esc` | stop here |

   The keys work **while Ariel has the focus**, which is the point: you
   can reach in and drag an anchor yourself and then press Enter without
   clicking back onto anything. A low-level keyboard hook reads them and
   swallows them so Ariel does not act on them too. Where Windows
   refuses the hook — or you pass `--no-hook` — the magnifier takes the
   keyboard instead and you click it before pressing a key; the first
   line of output says which of the two you got.

   `P` turns the hook off and on without ending the run, for when you
   need to type something in Ariel mid-way.

`--help` lists the rest: `--settle` and `--start-delay` for a slow
machine, `--zoom` and `--view` for the magnifier, `--big` for how far a
Shift+arrow nudges.

## Click first, or confirm first

The default is the order you would do it by hand: **click, then check**.
A nudge then has to move an anchor that already exists, so it is sent as
a drag.

If Ariel will not let a placed anchor be dragged, use `--confirm-first`:
the magnifier opens on bare photo, arrow keys move the pointer, and the
click happens when you press Enter. Nothing needs undoing if the
detector was three pixels out.

`--dry-run` walks the whole sequence and moves the pointer but never
presses a button. Worth doing once on a photo you do not mind.

## When it misses a dot, or finds too many

Detection is two things: a colour test that runs on every pixel, and a
size-and-shape test on what survives. Both are on the command line.

| Symptom | Knob |
| --- | --- |
| pale, washed-out markers missed | `--red-gap 30`, `--blue-gap 30` |
| markers missed in deep shade | `--red-min 80`, `--blue-min 70` |
| tiny markers missed (zoomed out) | `--min-dot 2 --fill 0.3` |
| paint, tile or furniture found as dots | raise `--red-gap` / `--blue-gap`, or `--colors blue` |
| one marker found several times | `--merge 6` |
| big coloured things found | lower `--max-dot` |

`--colors red` and `--colors blue` narrow the hunt to one kind of
marker, which is the quickest fix when only one kind matters.

The pool water and a brick coping are the same colours as the markers
and are not excluded by colour at all — they are thrown out for being
thousands of pixels across. That is why `--max-dot` exists and why
raising it a long way will start finding the pool.

## Working out what went wrong, later

```
python ariel\anchors.py --save-shot deck.png          # keep the picture
python3 ariel/anchors.py --from-shot deck.png \
                        --annotate found.png          # anywhere, no Windows
```

`--from-shot` runs the whole detector on a saved screenshot and prints
the table of what it found; `--annotate` draws the rings and numbers
into a PNG. Neither needs Windows, Ariel or a mouse, so a job that came
out wrong can be diagnosed and the thresholds settled somewhere else
entirely — and it is how the test suite drives the thing.

## Multiple monitors, and scaled displays

The program asks Windows for per-monitor DPI awareness before it asks
how big anything is. Without that, a process on a 150% display is told
the screen is smaller than it is and every coordinate it computes is
wrong by the scale factor — detection finds a dot and the click lands
somewhere else entirely. The first line of output names which awareness
call was accepted; `none` there means the machine is old enough to be
worth checking by hand with `--dry-run`.

The capture covers the whole virtual desktop, monitors to the left of
the primary one (negative coordinates) included.

## The files

| File | What it is |
| --- | --- |
| `anchors.py` | the command line and the run loop |
| `detect.py` | finding the dots: the colour test, the blobs, the filters |
| `ordering.py` | perimeter / reading / nearest, and where number 1 goes |
| `placement.py` | the confirm-every-one state machine, no I/O at all |
| `pixmap.py` | PNG in and out, PPM for Tk, and the annotated picture |
| `winio.py` | the only Windows in the program: screen, mouse, key hook |
| `overlay.py` | the three Tk windows |
| `ArielAnchors.pyw` | double-click launcher |

Five of the seven never touch Windows, which is why
`tests/test_ariel_anchors.py` can drive detection, ordering, the run
loop and the file formats on any machine:

```
python3 tests/test_ariel_anchors.py
```

The fixture is the reference photo in outline — dappled shade on
concrete, cyan water, a brick coping and forty-four markers — because
all three of those are things the detector has to tell apart from a dot.

## Where it does not belong

`check_standards.py`, `check_registry.py` and `build_shared_bundle.py`
read `lisp/`, `shared/` and `releases/`. Nothing in this folder is a
`.lsp`, so none of them look here and none of them should be made to:

* it is **not** in `shared/LAZPASS.lsp` and needs no entry in
  `cal:*held-back*` — held-back is for AutoLISP tools kept out of the
  bundle, and this is not one;
* it has **no** `shared/parts/` twin and no `releases/` REV twin;
* it is **not** a LAZPANEL caption, a palette button or a name in
  `calofin.lsp`'s probe list — those register AutoCAD commands, and
  this program has none.

If it ever needs to hand its points to AutoCAD, the way to do it is a
file the drafting side reads, not a `cal:` symbol in the bundle.
