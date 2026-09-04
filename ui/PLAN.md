# The palette and the routines: where this stands

Originally the execution plan for the week of 2026-08-24 ("Making the
palette real"); rewritten 2026-08-27, when the work it planned landed.
The design decisions it argued for are preserved below because they are
now load-bearing code, and the next person to touch the form path
should know why it is shaped the way it is.

**For what is planned next, see `ui/UI-PLAN.md`** -- the roadmap for the
zero-install DCL surface (`LAZPANEL` and the three chart forms) and for
the data layer the palette is meant to share with it. This file is the
record of how the palette got here; that one is where it goes.

## What is built

| Layer | State |
| --- | --- |
| Palette shell — `CalofinPalette.vb`, `CommandsTab` | **done.** Dockable, grouped buttons, greys out what this session has not loaded |
| Availability glue — `ui/calofin_ui/calofin.lsp` | **done.** `calofin:loaded` reports which `C:` names exist; the roster now mirrors LAZPANEL's 60 headline commands and is pinned by `tests/test_shared.py` |
| Wire format — `LispBridge.vb` | **done.** Alist literal, invariant-culture numbers, three-state nil handling |
| Shape art + field maps — `assets/` | **done.** 12 shapes, 12 bottoms, fractional field positions |
| Form views — `SpaFormView.vb`, `PoolFormView.vb` | **done.** Collect answers, build the call; spa corners offer the canonical `Square/Radius/Cut/NotGiven` |
| **The receiving end in Lisp** | **done, five tools.** `pool:*form*` / `pool:run-with-answers`, `spa:*form*` / `spa:run-with-answers`, and `*cs-form*` / `*hs-form*` / `*ns-form*` for the three step routines - hooks in the ask helpers, consume-once, cleared on both exits |
| Zero-install charts — `LAZFORM`, `LAZSPA`, `LAZSTEP` | **done.** The same argument as this palette, in plain DCL with no DLL to `NETLOAD`: a chart is filled in and the routine runs from it. They drive the stores below through the same three-state contract the wire uses |

`tests/test_pool_form.py` and `tests/test_spa_form.py` pass at both
tiers, and each ends by walking its field map and asserting every key
the form can send is one the routine reads — the audit this document
once recorded as prose is now an assertion that cannot go stale.

## The design decisions that are now code

These were D1–D6 of the original plan; they shipped as designed and the
reasons still matter:

- **One store per tool, an alist, consumed as it is read.**  An answer
  is REMOVED when used, not marked used — otherwise Back deadlocks
  (step back onto a form-answered question and it answers itself
  forward again), and a value a range check rejects would be re-fed
  forever.  `tests/test_spa_form.py` scenario 7 pins the deadlock
  guard.
- **Three states.** Key absent = ask as usual; `(key . nil)` = NA
  without asking; `(key . v)` = v without asking.  `(assoc ...)` tells
  the first two apart; `(cdr (assoc ...))` cannot.  The half-filled
  form is the point of the feature.
- **Cleared on BOTH exits.**  Normal end and `*error*` — a stale store
  surviving a cancel would silently answer the next command-line run
  with last time's numbers.
- **`askkwf` is a wrapper, not a sixth argument.**  The mirror swaps
  `pool:askkw`/`spa:askkw` for the five-argument `cal:askkw`; widening
  the standalone helper would ship a grouped build that loads cleanly
  and dies at the first keyword question.
- **`pool:fkeyof` insists on the exact `"<letter> - "` prompt shape**,
  so "Total pool length (arc tip to arc tip)" can never eat a form
  answer filed under a letter.  (There is no `pool:askh-prompt` and
  never was; consume-once gives the re-ask guarantee that README error
  attributed to it — `ui/calofin_net/README.md` says so now.)
- **Old wire values stay accepted.**  The corner rename to
  `Square/Radius/Cut/NotGiven` moved the VB source and the field map in
  the same commit, and SPA still normalises `90`/`Diagonal` from an
  un-rebuilt DLL exactly like typed legacy input — the rename is safe
  whichever side deploys first.

## What remains palette-side

- **The DLL itself.**  Nothing VB can be compiled or run in this
  environment (`Calofin.vbproj` targets net48 against AutoCAD.NET
  reference assemblies).  The Lisp side of the wire is fully tested,
  `tools/check_vb.py` reads the VB as code -- blocks, quotes, parens,
  its own members and their arities -- and the suites hold every seam
  it has to text that IS testable.  None of that is a compiler.

  **What to do with the first real build**, in order, because each
  answers something nothing here can:

  1. `NETLOAD` and type `CALOFIN`.  Five tabs should open.
  2. On **Commands**, type `survey` into the box: `ABHD`, `ABPCHECK`
     and `ABHDCOVER` should be listed, none of which say so in their
     names.  Enter runs the top hit.  Right-click a button to pin it,
     then open `LAZPANEL` and confirm the pin is there too -- the two
     surfaces share one registry key, and this is the only way to see
     that they really do.
  3. On **Pool chart**, pick Rectangle.  The chart should be DRAWN, with
     a box sitting on each dimension line; resize the palette and it
     should redraw sharp rather than stretch.
  4. Type `6'-3"` into a box.  The state line should count it as filled
     and Draw should stay live -- that spelling used to travel as an NA
     nobody meant.  Then type `rubbish` into another: the line should
     name it BY ITS LETTER and grey Draw out.
  5. Press Draw, let POOL run, reopen the tab and press **Recall last**:
     the numbers should come back into the empty boxes only.
  6. On **Steps**, pick 5 steps and confirm the drawing has five treads.
  7. On **Spa**, run the form once with a `NotGiven` corner and confirm
     the `?` mark lands.
- **The two form surfaces, held together.** *(closed 2026-09-03.)*
  `tests/test_spa_form.py` section 15 now asserts that every question
  `LAZSPA`'s DCL chart asks is answerable on the palette too. It reads
  the palette's surface from BOTH files, because the field map is not
  the whole of it: `fieldmap.json` describes what is anchored to the
  artwork plus the second-outline overalls, while the cover block
  (`mode`, `second`, `method`, `gap`, `autohinge`, `grade`, `taper`)
  and the shape word live in `SpaFormView.vb`'s view model. Reading the
  map alone says the palette cannot ask for the cover lap, which is
  wrong -- and was the first thing this check had to be taught. The VB
  literals are parsed, not listed, so a key it stops sending fails the
  suite. The two surfaces were found to be fully in step: 19, 17 and 11
  questions on the three shapes, all answerable on both.

- **The button catalog.**  *(closed 2026-09-04.)*  It is generated:
  `tools/gen_ui_data.py` writes `Generated/CommandCatalog.g.vb` from
  `lzp:*captions*` and `lzp:*groups*`, so every command on `LAZPANEL`
  has a button here by construction, and the tab strip's job pages come
  with it.  The one thing still typed is the tooltip, in `blurbs.txt`.
  See `ui/UI-PLAN.md` phase 5a for why generating VB is allowed when
  `check_registry --fix` refuses to.
- **The shell.**  *(closed 2026-09-04.)*  Find, Recent, Pinned and the
  panel's whole tab strip, sharing LAZPANEL's own registry key so the
  pins are one set rather than two.  `ui/UI-PLAN.md` phase 5b.

- **Generalising the hook into `cal:`.**  Putting the form store into
  the library would make every grouped tool form-drivable.  Real
  payoff, real design risk; the POOL/SPA pattern is now proven twice,
  which is what the original plan said to wait for.  Still a next
  iteration, deliberately.
