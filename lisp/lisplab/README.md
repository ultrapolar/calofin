# LISPLAB — reading the drawing databases, and sorting a list (AutoLISP)

A teaching routine for someone learning AutoLISP, not a drafting tool.
It answers the two questions that come up first:

* **How do I get at what is already in the drawing?**
* **How do I put a list in the order I want?**

Each lesson comes in two halves and you pick which you want: **Checks**
prints the written outline — what each call is, what it gives back, and
the trap that goes with it — and **Demo** runs the same thing, drawing a
sample and reading it back with the very calls it just described.

Taken together the two lessons are one story: lesson 1 pulls records out
of the drawing, lesson 2 puts them in order, and the sorted orders are
drawn back into the drawing so they can be looked at instead of read.

## What it does

```
LISPLAB
Which lesson? [Database/Sorting/Both] <Both>:
Checks prints the outline, Demo runs it.  Which? [Checks/Demo/Both] <Both>:
```

### Lesson 1 — the databases

A drawing is not one database, it is several, and the outline says which
call reaches which:

| Where a thing lives | What is in it | How you get at it |
| --- | --- | --- |
| graphical objects | lines, circles, text | `entsel`, `entget`, `entnext`, `ssget` |
| symbol tables | layers, linetypes, blocks, dim styles | `tblsearch`, `tblnext`, `tblobjname` |
| dictionaries | layouts, groups, layer states, your XRECORDs | `namedobjdict`, `dictsearch`, `dictadd` |
| extended data | your own tags riding on someone else's object | `regapp`, `entget` with an app name |
| header variables | `CLAYER`, `OSMODE`, `EXTMIN` | `getvar` / `setvar` |

Group codes worth knowing, the `(cdr (assoc 8 ed))` idiom, `ssget`'s
mode strings and filter lists (including the `-4` `<OR` operators), why
you walk a selection set backwards, and where ActiveX earns its slower
calls — all with the trap attached to each: `assoc` finds only the
*first* `10` group so a polyline gives you one vertex; `entget` hands
back a copy that changes nothing until `entmod`; `ssget` returns `nil`
rather than an empty set; `"_X"` ignores which space you are in.

The demo draws seven circles on two layers, then reads them back with
`entnext`, with `assoc`, and with `ssget "_X"` — and shows the
`(entlast)`-before-you-start idiom for telling *your* objects from
everything else in the drawing.

### Lesson 2 — ordering a list

Six ways to sort the same seven numbers, each with the reason you would
pick it:

| | Cost | Stable? | Why you would use it |
| --- | --- | --- | --- |
| `vl-sort` | built in | — | Ship this one, unless the duplicates matter |
| `lab:bubble` | n² | yes | Easiest to picture; stops early on sorted input |
| `lab:selection` | n² | — | Fewest moves; one per item |
| `lab:insertion` | n² worst, n best | yes | Best on nearly-ordered data; keeps a list sorted as it grows |
| `lab:msort` | n log n | **yes** | No bad case, and stability is what two-key sorting rests on |
| `lab:qsort` | n log n average | yes here | Shorter and usually quicker — until the input is already sorted |

Plus `lab:sort-by` for a key you have to compute (decorate — sort —
undecorate) and two ways to sort on two keys at once.

Three things the lesson is built around, because they are the ones that
actually bite:

* **`vl-sort` drops duplicates.** Seven items go in, six come out. The
  demo runs into this on purpose. `vl-sort-i` (indexes) or sorting
  records rather than bare numbers is the way out.
* **A comparator you were handed is called with `apply`**, never in head
  position — `(less a b)` dies with *no function definition: LESS*,
  because AutoLISP looks a name in head position up as a function.
* **AutoLISP has no closures and its scoping is dynamic.** A lambda sees
  the variables of whoever *calls* it. `lab:sort-by` therefore parks its
  comparator in `lab-keycmp`: a lambda saying `(apply less ...)` would
  be run from inside `lab:merge`, whose own argument is also called
  `less`, find that one — itself — and recurse until it died.

Every routine named above is a real implementation in the file, takes
its comparator as an argument, and leaves its input alone. They are
meant to be copied out.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `LISPLAB.lsp`.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `LISPLAB` | Run the lessons |
   | `LISPLABVER` | Print the version |

The demo asks for a clear spot (about 1000 x 500 drawing units at the
default size) and a size unit, and offers to erase everything it drew on
the way out. The whole run is one undo group either way, and `OSMODE`,
`CMDECHO` and `CLAYER` are restored whether the run finishes, errors, or
is cancelled with Esc.

## Tunables

`setq` these after loading:

| Variable | Default | Meaning |
| --- | --- | --- |
| `lab:*laya*` | `"LISPLAB-A"` | First layer the sample circles go on |
| `lab:*layb*` | `"LISPLAB-B"` | Second layer, so the layer filter has something to find |
| `lab:*laytxt*` | `"LISPLAB-NOTES"` | Layer for the radius labels and row captions |
| `lab:*cola*`, `lab:*colb*`, `lab:*coltxt*` | `1`, `3`, `7` | Colours for the three layers |
| `lab:*sample*` | `((6 0) (3 1) (9 0) (3 0) (12 1) (5 1) (8 0))` | The sample, as `(radius-in-size-units layer-index)`. The repeated `3` is deliberate — it is what makes `vl-sort`'s dropped duplicate visible |

## Notes & limitations

* The three demo layers are **created** if the drawing lacks them, and
  thawed, unlocked and switched back on if it has them in a state that
  would hide the result.
* **Erase** finds the demo the same way lesson 1 finds anything: it
  walks the database with `entnext` and deletes what is on the three
  demo layers. Anything else you happen to have put on those layers goes
  with it — which is why they are named `LISPLAB-*`.
* Run the demo twice without erasing and the second run's `entnext` and
  `ssget` counts include the first run's circles. That is not a bug in
  the demo, it is what those calls do, and it is why the demo builds its
  records from `(entlast)`-onwards rather than from the whole drawing.
* `namedobjdict`, `dictsearch`, `regapp` and the ActiveX calls are
  **described, not run**. The demo sticks to what it can draw and read
  back in one pass; the dictionary and xdata sections are reference.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  **AutoCAD LT has no LISP engine and cannot run this file.**

## Tests

`python3 tests/test_lisplab.py` loads the real `LISPLAB.lsp` into the
repo's AutoLISP VM (`tests/lispvm.py`). Because this is a file people
are meant to copy out of, the sorts are checked hard: every one of them
is driven against Python's own `sorted()` on lists that are empty,
single, already ordered, exactly reversed, all-equal and full of
duplicates, with three different comparators; `lab:msort`'s stability is
checked directly, and against the sort-twice route that depends on it.
The tour is then taken in every lesson/mode combination, with the drawn
rows read back out of the VM's drawing to confirm they really are the
sorted orders, plus a frozen-and-switched-off demo layer, the Erase
path, and an all-Enter run.

`CALOFIN_LISP_ROOT=shared python3 tests/test_lisplab.py` reruns the lot
against the grouped build in `shared/parts/LISPLAB.lsp`.
