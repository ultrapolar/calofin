# STANDARDS, distilled

The working subset of `STANDARDS.md` (79KB). Section numbers below are
that file's, so `grep -n '^## 4' STANDARDS.md` gets you the full text
when this is not enough.

---

## 1. Prompt format

One shape, everywhere:

```
\n<Message> [Option1/Option2/Back] <Default>:
```

1. **The bracket text IS the `initget` keyword list.** A click on a
   bracketed option sends that literal text to the command, so any
   difference makes the click fail. Derive it:
   `(vl-string-translate " " "/" kws)`. Never hand-write it twice.
2. **Capitals are the hotkey** (`Yes` = `Y`, `SHallow` = `SH`). Unique
   per set; the same word capitalized the same way in every tool.
3. **Hidden aliases are accepted, never shown.** `Undo` wherever `Back`
   is. Spell them ALL-CAPS in the `initget` string so they must be typed
   in full and cannot steal a canonical hotkey.
4. **`<default>` is what Enter produces**, rendered after the bracket,
   immediately before the colon. Prose inside the brackets
   (`<Enter = done>`) only on typed/numeric loop prompts.
5. **No default means re-ask** — `initget 1`, or re-ask on nil. Enter
   never silently picks an answer the user did not see.
6. **Terminator is `": "`, leading `\n`, always.** Sub-item prompts
   inside a review loop indent two spaces.
7. **Questions end in `?`** before the bracket. Short labels
   (`B - overall length`) take no punctuation.
8. **Compare variable-first** — `(= ans "Keyword")` — and normalize
   aliases inside the ask helper, never downstream.

## 2. The Treatment question

```
How should <subject> be treated? [Square/Radius/Cut/NotGiven] <previous>:
```

`<subject>` reads like prose: `Corner A`, `the back corners`.

| Keyword | Meaning | Hidden aliases |
| --- | --- | --- |
| `Square` | true 90-degree corner | `90` |
| `Radius` | rounded / filleted | `ROUNDED` |
| `Cut` | straight diagonal (chamfer) | `DIAG`, `DIAGONAL` |
| `NotGiven` | not on the order sheet — drawn square and flagged | `NG` |

`NotGiven` is always listed last and takes no size follow-up. Follow-ups
are fixed: `Radius for <subject> <default>:` /
`Cut face length for <subject> <default>:`. A remembered default is
offered only when the treatment matches the previous one. Corner A's
answer is the suggested default for B, C, D.

**These four words are the only corner vocabulary in the repo.**

## 3. Canonical keyword sets

| Purpose | Keywords | Default |
| --- | --- | --- |
| Confirmation | `Yes No` | always shown; destructive defaults `<No>` |
| Treatment | `Square Radius Cut NotGiven` | previous answer |
| Review navigation | `Yes No Back Skip` | `<Yes>` |
| Fix triage | `Merge Flag Leave` / `Flag Leave` | `<Merge>` / `<Flag>` |
| Defpoint fix | `Move Keep Pick` | `<Move>` |
| Declared-feature edit | `Add Remove Keep` | `<Keep>` |
| Tutorial selector | `Checks Demo Both` | `<Both>` |
| Demo cleanup | `Keep Erase` | `<Keep>` |
| Repeat last value | `Same` | only where a previous value exists AND Enter is taken |
| Multi-fit pick | `1 2 3 All None Redo` | `<2>` |
| Direction | `Clockwise COunterclockwise` | previous; `CW`/`CCW` hidden |

Tool-specific vocabularies are fine — they just obey section 1 and reuse
this table's word wherever the concept already has one.

### Numeric entry — the kind system

| Kind | Meaning | Prompt suffix | initget |
| --- | --- | --- | --- |
| `REQ` | required | none | `7` |
| `NAX` | NA accepted (returns nil) | ` (or NA if not measured)` | `7` + `NA` |
| `ZER` | NA accepted, zero accepted | ` (or NA if not measured)` | `5` + `NA` |
| `SUG` | suggested default, Enter takes it | ` <n> (or NA)` | `6` + `NA` |
| `SUGR` | the same suggestion on a REQUIRED value | ` <n>` | `6` |

Offering Back never loosens what counts as valid: a `REQ` prompt with
Back still rejects null/zero/negative. A flow that computes a suggestion
for a required question promotes `REQ`→`SUGR` rather than widening it.

### Back / Undo

`Back` is shown, `Undo` is its hidden synonym. Typed prompts accept
`B`, `BACK`, `U`, `UNDO` in any case, and say so (`(B = back)`). **The
first question of a command never offers Back.** Feedback wording:

```
Stepping back one <point|step|dimension|question>.
Already at the first <point|step|dimension>.
```

A chain of questions is walked with a **step counter, not by nesting**:
one `while` over a `cond`, each arm setting the counter to the step it
wants next. Where a question is conditional, carry a DIRECTION too, so a
step that puts no question moves the counter the way the chain was
already going — `c:CORNERSTP`'s `qstep`/`qdir` is the reference. A step
re-entered from below throws away what the earlier pass collected there.

A prompt that offers no Back needs a line in `tools/back_baseline.txt`
with the reason, or `check_back.py` fails.

### Other fixed wordings

- Pause: `--- press Enter to continue ---` (exact, everywhere).
- `Select` picks objects; `Highlight` is for window-the-work sweeps.
  When Enter means "everything", the prompt says so in parentheses.
- Placement: `Insertion base point <0,0>: `; demos ask
  `Pick a clear spot for the demo <0,0>: `.

---

## 4. Ask helpers

In `shared/`, these come from `CALOFIN-LIB.lsp` as `cal:*`. In `lisp/`,
the file embeds them under its own prefix (`tool:`), copied from the
library so the two never drift; `mirror_shared.py` swaps them back.
**A new tool starts from the library's versions, not from a sibling's copy.**

Proven originals (named, not line-numbered — lines rot):
`pool:askkw` / `pool:asks` in `lisp/pool/POOL.LSP`, `pf:ensure-layer` in
`lisp/abhd/abhd.lsp`, `pool:syssave` / `pool:sysrestore` in `POOL.LSP`.
Read one with
`python3 .claude/skills/calofin-lisp/scripts/lspshow.py pool:askkw`.

The roster: `askkw`, `asktreat`, `askyn`, `askdist`, `askstr`, `pause`,
`back-word-p`, `askpoint`, `ask-len`.

**One divergence to know before copying `askkw`.** The STANDARDS
reference takes `hidden` third and derives the bracket from `kws`.
Most of the tree — and `cal:askkw` — instead takes the **shown bracket
text** third and hand-writes it. That is deliberate and is not being
changed piecemeal: the mirror pins the library's arity from every
generated twin at once. So NEW code follows the reference shape;
code calling `cal:askkw` passes `shown` and must keep it equal to `kws`
with spaces turned into slashes. A form-aware question **wraps** the
helper (`pool:askkwf`) rather than growing an argument.

### A question about a survey point NAMES one

Use `askpoint`, never a bare `getpoint` snapped to whatever was nearest.
It takes a click OR a typed number:

- a click must land within the tool's snap radius (12.0 everywhere);
  a typed number never uses the radius — a name is exact;
- `"17"`, `"Pt.17"`, `"pt 17"`, `"#17"`, `"017"` all name the same point;
- a click on nothing, a number nothing carries, and a number two points
  share are all re-asked where they stand — never guessed at;
- the answer is a `(position name)` candidate, and the **position is the
  identity**.

### A LENGTH is asked beside the ruler

`ask-len` draws a column of nearby values near the right edge and takes
a click on a row, a typed measurement in any spelling `parse-len` reads
(`44`, `44.5`, `44 1/2`, `4'4.5`, `4'-4 1/2"`), Enter, a keyword, or two
points to measure between.

Two families, and **the caller picks**:
- **TAPE** — eighths of an inch either side of the LAST answer. Needs a
  last answer, so a prompt asked cold has none. For measurements (a
  wall, a bound, a cross dim): no ladder, because there is no short list
  of what one comes to.
- **LADDER** — a fixed `(LOW HIGH STEP)` of what that prompt is actually
  answered with, offered from the first prompt. For a size picked off an
  order sheet (a radius, a depth, a tread). A ladder is a **knob**.

A prompt that is both hands the ladder in only while there is no last
answer. `nil` for both is a plain typed prompt.

The ruler is **one block, not a pick-and-mix**: the reader, speller, row
geometry and prompt live once in the library between the two rule lines
fencing `the length ruler`, and a standalone file carries that whole
block under its own prefix. `tests/test_ruler_copies.py` holds every
copy to the library byte for byte — **change the library and copy out,
never edit one file.**

Its STATE is run state, not a helper's local: an Esc at a length prompt
runs the COMMAND's `*error*`, and what that handler can take down is
what the command can see. So `pool:*ruler*` sits with the run state, is
cleared at the start of a run, and is taken down by `rulerkill` from the
handler and the clean exit alike.

---

## 5. Code structure

**File.** One tool per `lisp/<tool>/`, named after the primary command:
`TOOLNAME.lsp`. ASCII only (`--`, not em dashes), spaces not tabs,
2-space indent, closing parens stacked on the last line. `;;;` for the
header and section rules, `;;` in-code, `;` end-of-line only.

**Namespace.** Every helper and global carries the file's unique prefix:
`tool:helper-name`, globals `tool:*name*`. One prefix per file, never
reused across files. AutoLISP symbols are **case-insensitive** — `sP` IS
`sp` — so pick one spelling and keep it (`check_scope.py` has a
case-collision check).

**Version banner** — one form, read by `release_lisp.py`
(regex `\*[a-z0-9]+-version\*\s+"v(\d+)\.(\d+)"`; lowercase name, `v`,
one dot). Bump with every change.

**Commands.** `(defun c:TOOLNAME ...)` — `c:` lowercase, name uppercase.
Secondary commands by fixed suffix:

| Role | Name |
| --- | --- |
| version reporter | `TOOLNAMEVER` |
| tutorial | `TUTORIALTOOLNAME` |
| read-only scan | `TOOLNAMESCAN` |
| undo-the-marks | `TOOLNAMERESCUE` |
| configuration | `TOOLNAME-CFG` |

### The command skeleton

```lisp
(defun tool:syssave ()
  (if (not tool:*sysold*)
    (setq tool:*sysold*
          (mapcar '(lambda (v) (cons v (getvar v)))
                  '("OSMODE" "CMDECHO" "CLAYER")))))  ; list what you CHANGE

(defun tool:sysrestore ( / v p)
  ;; OSMODE first -- the setting the drafter misses most
  (foreach v '("OSMODE" "CMDECHO" "CLAYER")
    (setq p (assoc v tool:*sysold*))
    (if p (setvar v (cdr p))))
  (setq tool:*sysold* nil))

(defun c:TOOLNAME ( / *error* undo-open)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (tool:sysrestore)
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTOOLNAME error: " msg)))
    (if lzd:report (lzd:report "TOOLNAME" *toolname-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TOOLNAME" *toolname-version*))
  (tool:syssave)
  (setvar "CMDECHO" 0)
  ;; _Begin in a drawing whose UNDOCTL has bit 1 clear errors out
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") (setq undo-open T)))
  ;; ... the tool ...
  (if undo-open
    (progn (command "_.UNDO" "_End") (setq undo-open nil)))
  (tool:sysrestore)
  (princ))
```

**Both halves of the undo bracket are conditional, on the same fact.**
An `_End` on no group is an error of its own, and it lands at the
*bottom* of a run that has drawn everything, taking the sysvar restore
behind it down too.

### The borrowed settings — OSMODE, CECOLOR, CLAYER

- Restored **on the clean exit AND from `*error*`**. Esc at a prompt is
  the likeliest way out, and the only one that never reaches the bottom.
- In the handler they go **FIRST**. An error inside `*error*` aborts the
  handler — every form after the throwing one is skipped. A bare
  `(command ...)` can throw (the Esc may have left a command PENDING, so
  the call is fed in as answers to it). `setvar` of a captured value
  cannot throw, so it leads and the risky work follows.
- **Drop the snapshot before the risky form, not after.** `syssave`
  refuses to overwrite an existing snapshot, so a snapshot never dropped
  silences every later run — they restore the FIRST run's values over
  whatever the drafter has ticked since.
- The saved value must be where the handler can see it: a **local of the
  command** (the handler is nested inside it) or the `tool:*sysold*`
  snapshot. A helper saving into its own local is out of reach.
- **Borrow only what you move.** A sysvar in the restore table is a
  promise to write it back; listing `OSMODE` without ever muting it
  hands the drafter the OPENING snapshot over any snap they ticked
  mid-run, on a clean exit.

`DIMSTYLE` cannot be `setvar`'d back — restore it with
`(vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" old))`.

A handler that genuinely must drive `(command)` itself declares
`(if *push-error-using-command* (*push-error-using-command*))` after the
handler and pops with `(if *pop-error-mode* (*pop-error-mode*))` as the
handler's last act **AND on every success exit** — the mode is stacked
for the document, not the command.

### Every command reports its failures

Five call sites, all maintained by `tools/check_lazdiag.py --fix`:

```lisp
(if lzd:begin  (lzd:begin  "TOOLNAME" *toolname-version*))      ; top
(if lzd:report (lzd:report "TOOLNAME" *toolname-version* msg))  ; in *error*
(if lzd:end    (lzd:end "TOOLNAME"))                            ; before (princ)
(if lzd:watch  (lzd:watch ss) ss)                               ; after a selection
(if lzd:ask    (lzd:ask msg v) v)                               ; after (setq v (getX ...))
((lambda (v) (if lzd:ask (lzd:ask "prompt" v) v))               ; input read IN PLACE
  (getpoint "prompt"))
```

**The else branch on `watch` and `ask` is load-bearing**: it makes the
form evaluate to the variable whether LAZDIAG is loaded or not, so the
call cannot change what the enclosing `progn` or `cond` clause returns.
The lambda does the same for a value read in place — a `while`'s test, a
keyword inside `(= ...)`, a `getstring` that only pauses — so the `nil`
that ends a loop is recorded like any other answer.

Placement inside the handler: `lzd:report` goes **after** the sysvar
restore and **before** the trailing `(princ)` (which is the return
value). The `(if ...)` guards are what let a standalone file load alone —
an unbound symbol is nil, so with no LAZDIAG every line is a no-op.

**Write the handler yourself; `--fix` will not.** What belongs in one is
editorial: which sysvars this command changed, whether an undo group is
open, what it drew that has to be swept. Both spellings are recognised —
`(defun *error* ...)` and `(setq *error* (lambda (msg) ...))` — prefer
the skeleton in new code.

### Tunables

A global that is a **setting** — a literal nothing re-assigns, that a
person might reasonably want different — goes in one block at the top,
between the version banner and the first `defun`, under a `;;; ---` rule.
One `setq` per line with a sentence saying **what changing it does**.
A knob defined after the code that reads it is nil while that code loads.

- A knob shared by a family is declared under a guard —
  `(if (not (boundp '*cs-tol-inch*)) (setq *cs-tol-inch* 0.125))` — so
  whichever file loads first sets it. The catalog lists a shared name
  ONCE, under the first file that declares it.
- A knob-shaped global that is **not** a setting says `NOT A KNOB:` in
  the comment directly above, **with the reason**.
- State (`nil`-initialized, written as the tool runs) is not a knob. A
  value that is both splits in two: the knob keeps the default and is
  never written; the answer is state under its own name.
- Every knob is also a row in the tool's README `## Tunables` table, and
  is transcribed into `LAZTUNE`'s catalog by `tools/gen_knobs.py` — a
  knob is not on offer to a drafter until that is re-run.

### Colour

A colour that must work on any screen says `'auto` and is resolved at
the point of use through `tool:ink` (`cal:ink` in the grouped build) by
role. Roles that follow the background: `fade`, `guide` (the DRAWING's
background), `dim`, `hi` (AutoCAD's INTERFACE theme). Roles that are
just named ACI constants: `flag`, `arc`, `olap`, `orig`, `sugg`,
`point`, `constr`, `report`.

**Which kind a knob may be is decided by how long what it colours LASTS:**

| What it colours | Knob is | Why |
| --- | --- | --- |
| a CUE the command takes away again — review grey, guide outline, `grdraw` cross, chart tile | `'auto` | one drafter's screen |
| anything still in the drawing when the command returns — a flagged dimension, report text, and above all a **LAYER RECORD** | plain ACI **number** | a drawing is opened by more than one person |

```lisp
(setq tool:*grey-color* 'auto)   ; a cue, put back -- so 'auto
(setq tool:*flag-color* 1)       ; STAYS until RESCUE -- so a number
(setq tool:*report-color* 3)     ; the report LAYER's colour
...
(tool:set-color ent (tool:ink tool:*grey-color* 'fade))
(tool:ensure-layer tool:*report-layer* tool:*report-color*)
```

`check_color.py` fails an `ink` call handed to a layer-making call, and
a layer knob that is not a number. **Resolve once into a local before a
loop** — the measurement is a COM round trip.

### Layers

Output layers go through the canonical `ensure-layer`: create it, or —
when it exists — un-freeze, unlock and switch it on, and say so. Without
that, a successful run onto a frozen layer looks like the command did
nothing. Copy `pf:ensure-layer` from `lisp/abhd/abhd.lsp`.

### The load banner

The last forms in the file, and **quiet inside the build** — sixty-three
greetings was 83 lines in every drawing opened:

```lisp
(if (not *calofin-quiet*)
  (princ (strcat "\nTOOLNAME " *toolname-version*
                 " loaded.  Type TOOLNAME to run.")))
(princ)
```

Several lines share one guard and one `progn`. `*calofin-quiet*` is
deliberately **not** a `cal:` symbol — a `lisp/` file may not touch one.
`check_lisp.py` fails a banner that is missing OR unguarded.

### Locals

Every variable a defun sets is a parameter or declared after ` / `
(space each side). **`*error*` is one of them** — `check_lisp.py` fails a
handler whose enclosing command does not declare it, because a handler
that outlives its command is the handler of whatever runs next.
`(vl-load-com)` once at the top of the file, not inside a command body.

### Per-tool README

`lisp/<tool>/README.md`, sections:
`# NAME -- one-line purpose (AutoLISP / AutoCAD 2018+)`, `## What it does`,
`## Install & run`, `## Tunables` (or `## Assumptions`),
`## Notes & limitations`, `## Tests`. Keyword lists quoted there must
match the code.
