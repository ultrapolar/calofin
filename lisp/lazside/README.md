# LAZSIDE -- read the section, type the letters beside it (AutoLISP / AutoCAD 2018+)

## What it does

`LAZSIDE` is `LAZFORM`'s argument applied to the side view alone. The
**longitudinal section stands on the left as one whole picture**, and
every dimension it carries has a labelled box in the column beside it
with its letter as a button in front of it. The picture is read, the
column is typed into, and the letter is what ties the two together.
Press **Insert** and `POOLSIDE` draws it, asking for nothing but the
base point.

Nothing here is a stored picture. `lzv:chart` builds the section from
the bottom type's own run chain, depth stations and nominal
proportions, and everything downstream -- the DCL, the drawing engine,
the state line, the answers -- reads it as data.

## One page per bottom type

Six floors, six chains of letters, six tabs:

| Tab | Type | Runs |
| --- | --- | --- |
| Normal hopper | `Normal` | `H G F E` -- slope down, hopper pad, slope up, shallow flat |
| Sport | `Sport` | `E2 F2 G F1 E1` -- symmetric, a flat at each end |
| Wedge | `Wedge` | `H F` -- a deep line at `H`, floor rising to the far wall |
| Slope | `SLope` | `H F E` -- no pad |
| Mod flat | `MOdflat` | `H G F` -- one pad, no shallow flat |
| Shallow slope | `SHallow` | `H G F E`, and the shallow floor slopes from `C2` up to `C` |

Picking the tab **is** the answer `POOLSIDE`'s first prompt asks for,
so a sheet can never be filled in for one floor and drawn as another.
The tab you are on is disabled rather than offered.

Every page also carries `B`, `C`, `D` -- and `C2` on the Shallow,
because that is the only floor with a break to measure it at -- and one
dropdown, **Put the deep end on the RIGHT**, which is a fact about the
sheet the section is going under rather than a measurement.

## The three tables are POOLSIDE's

A `lisp/` file has to load alone, so this one carries a copy of
`psd:chain`, `psd:depths` and `psd:nominal`. A copy is a thing that
drifts, so `tests/test_lazside.py` re-reads all three out of
`POOLSIDE.lsp` and holds them against these entry by entry -- the same
bargain `LAZFORM` strikes with `OASIS`'s reference outlines. The key a
letter is stored under is checked the same way, against `psd:key`.

## What travels, and what does not

| In a box | On the wire | What POOLSIDE does |
| --- | --- | --- |
| left empty | the key is not sent | asks the question as usual |
| `NA` in a **run** | `(key . nil)` | not measured -- reads it back off `B` |
| `2'6"` or `24` | `(key . 24.0)` | takes the measurement, no prompt |

Two `NA`s split the remainder evenly, which is `POOLSIDE`'s own rule
and the reason a sheet with a hole in it still draws.

**A depth is the exception.** `POOLSIDE` has no `NA` for `C`, `D` or
`C2` -- they are required measurements -- so `NA` in one of them counts
as an empty box instead of being sent as a `nil` the run cannot use.
The state line says so in as many words rather than leaving you to
find out at the prompt.

A typo counts as an empty box too: something that is neither `NA` nor a
distance AutoCAD can read leaves `POOLSIDE` asking rather than quietly
feeding it something that means the wrong thing.

**The base point never comes off the form.** It is picked in the
drawing with your own snaps live, which is the one thing a dialog
cannot do for you.

## The state line, and the one button it holds back

```
Nothing filled yet - POOLSIDE will ask for all 7 boxes, plus the base point.
1 of 7 boxes filled - POOLSIDE will ask for H, G, F and 3 more, plus the base point.
H is not a measurement - type a number, or NA, or clear it.
C is NA, and a depth has no NA - type a number, or clear it.
C is not a measurement - a depth takes a number or an empty box.
D must be deeper than C - the deep end is not deeper than the wall.
C2 must be between C and D - the break cannot sit outside them.
All 7 boxes filled - POOLSIDE will ask only for the base point.
```

Two of those grey `Insert`: a box that would be silently dropped, and a
**depth pair POOLSIDE would refuse**. `POOLSIDE` loops at the prompt
until `D` is deeper than `C` and `C2` sits between them -- which is the
right thing at a prompt and the wrong thing to hand a sheet to, because
the run would draw half a section and then stop to argue. A form can
see both numbers at once, so it says so here instead.

A box is always named by the **letter the picture prints**, never by
its key: a key would send you hunting for something the drawing does
not show.

## Recall last

Puts the answers from the last accepted sheet for *this bottom type*
back into the **empty** boxes only -- safe to press twice, never a
default, greyed when there is nothing stored. The slot is the bottom
type, because a Sport's `E2`/`F2`/`F1`/`E1` mean nothing on a Normal's
`H`/`G`/`F`/`E`.

## Install & run

APPLOAD `LAZSIDE.lsp` **and** `lisp/poolside/POOLSIDE.lsp`, which it
fills in -- or load `shared/LAZPASS.lsp`, which carries both. With
`POOLSIDE` missing, `LAZSIDE` says so plainly and names it, rather than
opening a form whose Insert button could only fail.

```
LAZSIDE      fill the side view in and draw it
LAZSIDEVER   print the loaded version
```

## Tunables

Every one is a plain literal in the tunables block at the top of
`LAZSIDE.lsp`. The frame numbers are in PER-MILLE of the picture, x and
y with y down -- an image tile's own convention, so the only conversion
at draw time is a multiply.

| Global | Default | What it sets |
| --- | --- | --- |
| `lzv:*b-y*` | `120` | the overall `B`, across the top |
| `lzv:*water-y*` | `230` | the waterline: the top of both walls |
| `lzv:*sec-x0*` | `90` | the left wall... |
| `lzv:*sec-x1*` | `910` | ...and the right one |
| `lzv:*shal-y*` | `430` | the floor at depth `C` |
| `lzv:*brk-y*` | `530` | ...at `C2`, the Shallow break |
| `lzv:*deep-y*` | `660` | ...and at `D`, the deep end |
| `lzv:*chain-y*` | `810` | the run chain's baseline |
| `lzv:*c-x*` | `45` | where `C` stands, outside the left wall |
| `lzv:*chart-w*` | `58` | the picture's width, in character cells |
| `lzv:*chart-a*` | `"0.62"` | ...and its height, as a DCL aspect ratio |
| `lzv:*hint-w*` | `92` | how wide the hint and state lines are |
| `lzv:*poskey*` | `"LazSide_Pos"` | where the dialog remembers its position (the AutoCAD profile) |
| `lzv:*recallkey*` | `"HKEY_CURRENT_USER\\Software\\Calofin\\LazSide"` | where a sheet's last accepted answers are kept, one value per bottom type |

**Not tunable here, deliberately:** the stroke font and the image
tile's colours -- the grouped build takes `CALOFIN-LIB.lsp`'s instead.

## Why the picture is not clickable

It cannot be. An `image_button` is repainted on mouse-enter and again
on mouse-leave, and a DCL image tile is **not retained** by AutoCAD: a
repaint clears it to its own colour attribute and there is no expose
callback to redraw from, so the section would vanish the first time the
cursor crossed it. A plain image tile is passive, and the letter at the
front of each box's label is what ties the picture to the column
instead.

## Tests

```
python3 tests/test_lazside.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_lazside.py # grouped tier
```

Seven jobs, ending in the one that cannot be faked: fill the sheet in,
press Insert, and the section is identical **entity for entity** to the
same run answered at the prompts, with nothing asked but the base point.
