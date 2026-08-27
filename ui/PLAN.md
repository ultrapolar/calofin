# The palette and the routines: where this stands

Originally the execution plan for the week of 2026-08-24 ("Making the
palette real"); rewritten 2026-08-27, when the work it planned landed.
The design decisions it argued for are preserved below because they are
now load-bearing code, and the next person to touch the form path
should know why it is shaped the way it is.

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
  reference assemblies).  The Lisp side of the wire is fully tested;
  the VB side is verified only down to the literal it emits.  Whoever
  next opens AutoCAD with a build should run the spa form once with a
  `NotGiven` corner and confirm the `?` mark lands.
- **The button catalog.**  The palette still shows its original button
  set; the newer headline tools have no buttons.  Additions are
  unverifiable here, so the catalog expansion waits for a machine that
  can build the DLL.  `LAZPANEL` (pure AutoLISP, ships inside
  `LAZPASS.lsp`) remains the zero-install surface that already covers
  all 60.
- **Generalising the hook into `cal:`.**  Putting the form store into
  the library would make every grouped tool form-drivable.  Real
  payoff, real design risk; the POOL/SPA pattern is now proven twice,
  which is what the original plan said to wait for.  Still a next
  iteration, deliberately.
