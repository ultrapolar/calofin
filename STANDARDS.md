# Calofin AutoLISP standards

This file is the standard every new or modified routine under `lisp/`
follows: how prompts are worded, which keywords they offer, and how the
files themselves are structured. It exists because the tools grew up on
~29 separate branches and ask the same questions in different words --
the corner question alone shipped in four vocabularies.

> Not to be confused with `lisp/standards_checker/`, which matches
> *drawing geometry* against reference DWGs. This file is about the
> LISP source and its prompts.

Rules for **new work are mandatory**. Existing files are brought in
line by the migration phase (section 7 is its worklist); until a file
is migrated, its old wording stands -- do not half-convert a file in
passing.

---

## 1. Prompt format

Every interactive prompt has one shape:

```
\n<Message> [Option1/Option2/Back] <Default>:
```

concretely, e.g.:

```
How should Corner A be treated? [Square/Radius/Cut/NotGiven] <Radius>:
Dimension the steps? [Yes/No] <Yes>:
B - overall length [Back]:
```

The rules, in order of how often they are currently broken:

1. **The bracket text is exactly the `initget` keyword list.** A click
   on a bracketed option sends that text to the command, so any
   difference (`[Skip rest]` for keyword `Skip`, `[Inside out]` for
   `Inside`) makes the click fail. Build the bracket from the keyword
   string -- `(vl-string-translate " " "/" kws)` -- so the two cannot
   drift; never hand-write it a second time.
2. **Capitals are the hotkey.** The capitalized letters of a keyword
   are its typed abbreviation (`Yes` = `Y`, `SHallow` = `SH`). Every
   keyword in a set must have a unique abbreviation; use a single
   capital unless disambiguation forces more. The same word is
   capitalized the same way in every tool (no `ROUnd` here, `ROund`
   there).
3. **Hidden aliases are allowed but never shown.** `Undo` is accepted
   wherever `Back` is, unlisted. Legacy words (section 2) are accepted
   typed in full, unlisted. Spell hidden aliases ALL-CAPS in the
   `initget` string -- an all-caps keyword must be typed out in full,
   so an alias can never steal a canonical option's hotkey.
4. **The `<default>` is what Enter produces** -- a keyword, a number,
   `0,0` -- rendered after the bracket, immediately before the colon:
   `[...] <Default>: `. Prose inside the angle brackets
   (`<Enter = done>`) is allowed only on typed/numeric loop prompts
   where Enter ends the loop rather than supplying a value.
5. **No default means re-ask.** A prompt with no `<default>` uses
   `initget 1` (or re-asks on nil) -- Enter never silently picks an
   answer the user didn't see.
6. **Terminator is colon-space** (`": "`), always. Leading `\n`,
   always. Main prompts start flush after the `\n`; prompts about a
   sub-item inside a review loop indent two spaces.
7. **Questions read as questions.** If the message is a sentence, it
   ends with `?` before the bracket (`Dimension the steps? [Yes/No]`).
   Short labels (`Bottom type`, `B - overall length`) take no
   punctuation before the bracket.
8. **Compare variable-first, and normalize at the ask site.** Answers
   are tested with `(= ans "Keyword")`; alias-to-canonical mapping
   (`"90"` -> `"Square"`) happens inside the ask helper, never
   downstream where one site will forget it.

## 2. The Treatment question

Anywhere a feature gets a categorical style choice -- today that is
corners -- the question is a **Treatment**:

```
How should <subject> be treated? [Square/Radius/Cut/NotGiven] <previous>:
```

* `<subject>` reads like prose: `Corner A`, `the back corners`,
  `the pool corners`, `the reverse corners`.
* The four answers, stored exactly as spelled; `NotGiven` is always
  listed last:

  | Keyword    | Meaning                              | Hidden aliases     |
  | ---------- | ------------------------------------ | ------------------ |
  | `Square`   | true 90-degree corner                | `90`               |
  | `Radius`   | rounded / filleted corner            | `ROUNDED`          |
  | `Cut`      | straight diagonal (chamfered) corner | `DIAG`, `DIAGONAL` |
  | `NotGiven` | treatment not recorded on the order sheet -- drawn as a square corner and flagged (see below) | `NG` |

  The old words stay accepted typed in full (muscle memory from the
  pre-standard tools) and are normalized to the canonical word inside
  the ask helper. Drawing/sheet output may still print `90%%d` for a
  Square corner -- display text is not the keyword.

  `NotGiven` is one token because keywords cannot contain a space; it
  is typed in full or as `NG`. `NG` rides along as its own ALL-CAPS
  hidden keyword and is normalized like the legacy words, so the short
  form works regardless of how AutoCAD reads the mid-word capital.
* Follow-up size questions are fixed too:

  ```
  Radius for <subject> <default>:
  Cut face length for <subject> <default>:
  ```

  A remembered default is only offered when the new treatment matches
  the previous one -- a radius is not a cut face. `NotGiven` takes no
  size follow-up: nothing was measured.
* When the same question repeats per corner (A, B, C, D), corner A's
  answer becomes the suggested default for the rest.

### How square corners are drawn

The mark for a square corner is a small circle on the corner point
with a leader out along the corner's outward diagonal -- the
`spa:dim90` idiom (`lisp/spa/SPA.LSP`; `pool:dim90` is its port),
which is the reference implementation. What the leader says depends on how many corners
share the treatment (per the approved sample drawing
`square_and_not_given.dxf`):

| Case                              | Marks drawn                          | Leader text  |
| --------------------------------- | ------------------------------------ | ------------ |
| every corner Square (or all same) | one, at the reference corner         | `90%%d Typ.` |
| some corners Square               | one per Square corner                | `90%%d`      |
| corner NotGiven                   | one per NotGiven corner              | `?`          |

A `NotGiven` corner's geometry is drawn square, and next to its `?`
mark a second leader note reads `Not Given` -- the sheet must show the
treatment was never recorded, not silently claim a 90. The `Typ.`
logic applies to NotGiven the same way: if every corner is NotGiven,
one `?` mark with the `Not Given` note carries the `Typ.` suffix.

## 3. Canonical keyword sets and shared wordings

One question, one vocabulary, repo-wide:

| Purpose                    | Keywords (initget)          | Default rule                          |
| -------------------------- | --------------------------- | ------------------------------------- |
| Confirmation               | `Yes No`                    | Always shown; destructive asks default `<No>` |
| Treatment                  | `Square Radius Cut NotGiven` | Previous answer, or none on the first |
| Review navigation          | `Yes No Back Skip`          | `<Yes>` (bracket is `[Yes/No/Back/Skip]`, not `Skip rest`) |
| Fix triage                 | `Merge Flag Leave` / `Flag Leave` | `<Merge>` / `<Flag>`            |
| Defpoint fix               | `Move Keep Pick`            | `<Move>`; explain the choices in the question text, not the bracket |
| Declared-feature edit loop | `Add Remove Keep`           | `<Keep>`                              |
| Tutorial selector          | `Checks Demo Both`          | `<Both>`                              |
| Demo cleanup               | `Keep Erase`                | `<Keep>`                              |
| Multi-fit pick             | `1 2 3 All None Redo`       | `<2>`                                 |

Tool-specific vocabularies (POOL's shape list, SPA's spillaway walls)
are fine -- they just obey section 1, and reuse this table's word
whenever the concept already has one.

**Back / Undo.** The root `README.md` section "Going back a step" is
part of this standard, verbatim: `Back` is shown, `Undo` is its hidden
synonym, typed prompts accept `B`, `BACK`, `U`, `UNDO` alone in any
case (and say so), the first question of a command never offers Back.
Feedback wording on the way back:

```
Stepping back one <point|step|dimension>.
Already at the first <point|step|dimension>.
```

**Pause.** One spelling, everywhere (indent to match a tutorial's
layout if needed; the text never varies):

```
--- press Enter to continue ---
```

**Selection.** `Select` is the verb for picking objects
(`Select the base line...`, `Select a line or polyline: `);
`Highlight` is reserved for window-the-work sweeps
(`Highlight the drawing to DIMCHECK (Enter = whole drawing): `).
When Enter means "everything", the prompt says so in parentheses.

**Placement.** Generated drawings ask
`Insertion base point <0,0>: `; demos ask
`Pick a clear spot for the demo <0,0>: ` (append
`(about 250 x 250 needed)` style guidance when it matters).

**Numeric entry.** Measurement prompts use the POOL/SPA kind system:

| Kind  | Meaning                             | Prompt suffix                 | initget |
| ----- | ----------------------------------- | ----------------------------- | ------- |
| `REQ` | value required                      | none                          | `7`     |
| `NAX` | NA accepted (returns nil)           | ` (or NA if not measured)`    | `7` + `NA` |
| `ZER` | NA accepted, zero accepted          | ` (or NA if not measured)`    | `5` + `NA` |
| `SUG` | suggested default, Enter takes it   | ` <n> (or NA)`                | `6` + `NA` |

Offering Back never loosens what counts as a valid measurement -- a
`REQ` prompt with Back still rejects null/zero/negative numbers.

## 4. Reference ask helpers

The canonical implementations. `tool:` stands for the file's own
namespace prefix and `TOOL` / `TOOLNAME` for its command name. In the
`shared/` build these are exported once by `shared/CALOFIN-LIB.lsp`
under the `cal:` prefix (Back sentinel `CAL-BACK`) and a shared-build
tool calls `cal:` instead of embedding copies -- a NEW tool starts
there. A standalone file in `lisp/` embeds them under its own prefix,
copied from the library so the two never drift. Proven originals (named, not line-numbered -- lines rot):
`pool:askkw` / `pool:asks` in `lisp/pool/POOL.LSP`,
`pf:ensure-layer` in `lisp/abhd/abhd.lsp`,
`pool:syssave` / `pool:sysrestore` in `lisp/pool/POOL.LSP`.

```lisp
;; Keyword question.  kws is the canonical keyword string - it is BOTH
;; the initget list and the bracket text, so the two can never drift.
;; hidden holds extra accepted spellings that are never shown; spell
;; them ALL-CAPS so they must be typed in full and cannot steal a
;; canonical hotkey.  dflt nil = an answer is required.  Returns the
;; keyword, or TOOL-BACK for Back/Undo.
(defun tool:askkw (msg kws hidden dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (strcat kws
                   (if hidden (strcat " " hidden) "")
                   (if back " Back Undo" "")))
  (setq v (getkword (strcat "\n" msg " ["
                            (vl-string-translate " " "/" kws)
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'TOOL-BACK)
        ((null v) (if dflt dflt (tool:askkw msg kws hidden dflt back)))
        (t v)))

;; The Treatment question: "How should <subject> be treated?"
;; subject reads like prose: "Corner A", "the back corners".  Returns
;; "Square", "Radius", "Cut" or "NotGiven" - the old words and NG are
;; accepted typed in full and normalized HERE, never downstream - or
;; TOOL-BACK.
(defun tool:asktreat (subject dflt back / v)
  (setq v (tool:askkw (strcat "How should " subject " be treated?")
                      "Square Radius Cut NotGiven"
                      "NG 90 ROUNDED DIAG DIAGONAL"
                      dflt back))
  (cond ((= v "NG") "NotGiven")
        ((= v "90") "Square")
        ((= v "ROUNDED") "Radius")
        ((member v '("DIAG" "DIAGONAL")) "Cut")
        (t v)))

;; Yes/No.  dflt is "Yes" or "No" and is always shown; destructive
;; actions default "No".  Returns T, nil or TOOL-BACK.
(defun tool:askyn (msg dflt back / v)
  (setq v (tool:askkw msg "Yes No" nil dflt back))
  (if (eq v 'TOOL-BACK) v (= v "Yes")))

;; Distance entry with the kind system of section 3.  Returns the
;; number, nil for NA, or TOOL-BACK.
(defun tool:askdist (kind msg dflt back / v kw)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; REQ always rejects zero - offering Back must not loosen what
  ;; counts as a valid measurement; ZER alone admits 0
  (if kw
      (initget (cond ((eq kind 'ZER) 5)
                     ((and (eq kind 'SUG) dflt) 6)
                     (t 7))
               kw)
      (initget 7))
  (setq v (getdist
            (strcat "\n" msg
                    (cond ((eq kind 'REQ) "")
                          ((eq kind 'SUG)
                           (if dflt (strcat " <" (rtos dflt) "> (or NA)")
                               " (or NA)"))
                          (t " (or NA if not measured)"))
                    (if back " [Back]" "")
                    ": ")))
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'TOOL-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;; Typed prompts cannot take keywords, so Back is typed like a value.
(defun tool:back-word-p (s)
  (member (strcase s) '("B" "BACK" "U" "UNDO")))

;; Free-text entry (notes, feet-inch dimensions).  The prompt says how
;; to back out because nothing else will.  Returns the string (Enter =
;; dflt when one is given) or TOOL-BACK.
(defun tool:askstr (msg dflt back / v)
  (setq v (getstring T (strcat "\n" msg
                               (if dflt (strcat " <" dflt ">") "")
                               (if back " (B = back)" "") ": ")))
  (cond ((and back (tool:back-word-p v)) 'TOOL-BACK)
        ((= v "") (if dflt dflt v))
        (t v)))

;; The one pause wording (section 3).
(defun tool:pause ()
  (getstring "\n--- press Enter to continue ---")
  (princ))
```

## 5. Code structure

**File.** One tool per `lisp/<tool>/` folder; the file is named after
the primary command, uppercase stem, lowercase extension:
`TOOLNAME.lsp`. ASCII only (`--`, not em dashes), spaces not tabs,
2-space base indent, closing parens stacked on the last line of the
form. `;;;` for the header and section rules, `;;` for in-code
comments, `;` only for end-of-line remarks.

**Header banner** -- `;;; ` + 70 `=` rule (74 characters), name and
one-line purpose, platform, commands:

```lisp
;;; ======================================================================
;;; TOOLNAME.lsp  --  one-line purpose of the tool
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  TOOLNAME       what it does
;;;            TOOLNAMEVER    print the loaded version
;;; ======================================================================
```

**Version banner** -- one form only, read by `tools/release_lisp.py`
(regex: `\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"`; lowercase name, `v`,
one dot). Bump it with every change and regenerate `releases/`:

```lisp
(setq *toolname-version* "v1.0")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it
```

**Namespace.** Every helper and global carries the file's unique
prefix, colon-separated: `tool:helper-name`, globals with earmuffs
`tool:*name*`. One prefix per file, no prefix reused across files.
(AutoLISP symbols are case-insensitive -- `sP` IS `sp`; that is why
`tools/check_scope.py` has a case-collision check. Pick one spelling
per name and keep it.)

**Commands.** `(defun c:TOOLNAME ...)` -- `c:` lowercase, name
uppercase. Secondary commands by fixed suffix:

| Role                | Name                  |
| ------------------- | --------------------- |
| version reporter    | `TOOLNAMEVER`         |
| tutorial            | `TUTORIALTOOLNAME`    |
| read-only scan      | `TOOLNAMESCAN`        |
| undo-the-marks      | `TOOLNAMERESCUE`      |
| configuration       | `TOOLNAME-CFG`        |

**Command skeleton** -- localized `*error*`, table-driven sysvar
save/restore, one undo group, `(princ)` exit:

```lisp
(defun tool:syssave ()
  (if (not tool:*sysold*)
    (setq tool:*sysold*
          (mapcar '(lambda (v) (cons v (getvar v)))
                  '("OSMODE" "CMDECHO" "CLAYER")))))  ; list what you change

(defun tool:sysrestore ( / v p)
  ;; OSMODE first -- object snaps are the setting the user misses most
  ;; if a run is ever cut short partway
  (foreach v '("OSMODE" "CMDECHO" "CLAYER")
    (setq p (assoc v tool:*sysold*))
    (if p (setvar v (cdr p))))
  (setq tool:*sysold* nil))

(defun c:TOOLNAME ( / *error* undo-open)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (tool:sysrestore)
    (if undo-open (command "_.UNDO" "_End"))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTOOLNAME error: " msg)))
    (princ))
  (tool:syssave)
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  ;; ... the tool ...
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (tool:sysrestore)
  (princ))
```

The canonical cancel test is exactly
`(wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")` -- ten
variants of it exist today; new code uses this one. Undo grouping is
`(command "_.UNDO" "_Begin")` / `"_End"` in that casing, tracked in a
local `undo-open`. `DIMSTYLE` cannot be `setvar`'d back -- restore it
with `(vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" old))`.

**Locals.** Every variable a defun sets is a parameter or declared
after ` / ` (space each side) in the arglist -- `check_scope.py` is
the referee. `(vl-load-com)` once at the top of the file when ActiveX
is used, not inside command bodies.

**Layers.** Output layers go through the canonical `ensure-layer` --
create, and un-freeze/unlock/switch-on when it already exists, telling
the user when it had to:

```lisp
;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun tool:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
                    '(6 . "Continuous")))
    (progn
      (setq rec   (tblobjname "LAYER" name)
            ed    (entget rec)
            flags (cdr (assoc 70 ed))
            col   (cdr (assoc 62 ed))
            fixed nil)
      (if (/= 0 (logand 5 flags))          ; frozen (1) or locked (4)
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)                        ; layer switched off
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nTOOLNAME: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))
```

**File ending.** A load announcement naming the version and the
command, then a bare `(princ)` as the very last form; every command
defun also ends `(princ)`:

```lisp
(princ (strcat "\nTOOLNAME " *toolname-version*
               " loaded.  Type TOOLNAME to run."))
(princ)
```

**Per-tool README.** `lisp/<tool>/README.md` with the established
sections: `# NAME -- one-line purpose (AutoLISP / AutoCAD 2018+)`,
`## What it does`, `## Install & run`, `## Tunables` (or
`## Assumptions`), `## Notes & limitations`, `## Tests`. Keyword lists
quoted in a README must match the code -- they are part of the
migration checklist when a keyword changes.

## 6. Folder layout

```
wip/         editable sources, one folder per tool, no date stamps
             (today: lisp/ - the rename is still pending)
standalone/  generated, self-contained, dated REV-stamped twins - one
             file per tool, loadable with nothing else present
             (today: releases/ - the rename is still pending)
shared/      BUILT - the loaded-together build: CALOFIN-LIB.lsp (the
             section-4 helpers plus ensure-layer, the vector sets,
             circumcenter, bboxes, trim/pad/datestr, block-number and
             more, all under cal:), CALOFIN-LOADER.lsp (APPLOAD this
             one file), and one <TOOL>.lsp twin per tool with its
             embedded helper copies replaced by cal: calls.  The
             deprecated acady matcher is not carried here.  See
             shared/README.md for the full roster, the deliberately
             NOT-absorbed divergent helpers, and the accepted behavior
             deltas.
```

Rules of the shared build:

* Everything in `shared/` loads together -- `CALOFIN-LOADER.lsp` loads
  the library first, then every tool.  A shared tool file must define
  no `cal:` symbol and no top-level name another file defines
  (`tests/test_shared.py` enforces both).
* `lisp/` stays the development home of tool logic.  A behavior change
  in `lisp/<tool>/` is mirrored into `shared/<TOOL>.lsp` in the same
  commit; the diff between the twins should only ever be the deleted
  helper copies and the `cal:` call sites.
* Parity is testable: `CALOFIN_LISP_ROOT=shared` reruns any VM-driven
  test in `tests/` against the shared build.
* A NEW tool is written against `cal:` in `shared/` first; its
  standalone `lisp/` twin embeds copies of the library helpers it uses
  (same bodies, its own prefix).

When the `wip/` / `standalone/` renames eventually happen, these must
change in lockstep: `tools/release_lisp.py` paths, `tools/check_lisp.py`
/ `check_scope.py` defaults, every `tests/` path, the README tables,
and `CLAUDE.md`'s layout section.

The library exists because the duplication was measured, not
suspected: `ensure-layer` had 12 copies in 4 behavioral families,
`dimcheck`/`linfincheck`/`covercheck` share ~40 helper names and
1,200-1,400 identical lines pairwise, `abhd`/`lhd` share ~1,259 lines,
POOL/SPA duplicated the whole ask layer.

## 7. Migration appendix -- current divergences

The worklist for the modify-the-lisps phase. Line numbers are as of
the commit this file landed on.

### 7.1 Corner treatment -> `Square / Radius / Cut / NotGiven`

| File | Status |
| --- | --- |
| ~~`lisp/spa/SPA.LSP`~~ | **DONE** — `spa:askcorner` asks the canonical Treatment, stores the canonical words (`spa:cutp` carries the is-there-a-cut question), grew the `NotGiven` branch (`spa:dimng`) and the all-same `Typ.` policy; old words and the palette's old wire values normalised at the ask site |
| ~~`lisp/pool/POOL.LSP`~~ | **DONE** — `pool:asktreat`: canonical set + `NotGiven`, legacy words hidden, size asks "Radius for" / "Cut face length for" |
| ~~`lisp/cornerstp/NORMIESTEP.lsp`~~ | **DONE** — `ns-asktreat`, canonical set, legacy hidden.  A step layout carries no corner callouts, so no `?`-mark branch applies |
| ~~`lisp/spa/TUTORIALSPA.LSP`~~ | **DONE** — teaches the canonical question, demo corners speak the new words |
| ~~`lisp/pool/TUTORIALPOOL.LSP`~~ | **DONE** — moved with POOL, and its topic-4 pane now demonstrates all four treatments |
| `lisp/lincheck/lincheck.lsp` | reviewed and KEPT: `"Straight Radius"` is a different axis (step face straight vs curved), not a corner treatment |

Square-corner depiction (section 2 "How square corners are drawn"):
**DONE everywhere it applies.**  `spa:dim90` was the donor; POOL's
port is `pool:dim90` (mark drawn only where the corner really is 90,
the L's reflex inner corner excluded), `pool:dimng` / `spa:dimng` draw
the `NotGiven` mark, and `pool:cutp` / `spa:cutp` keep "is there a cut
here" apart from "is there something to record here".  SPA's old
no-notes-when-all-square policy is gone: all square now gets one
`90%%d Typ.` mark, per the section-2 table.

The downstream moved in the same commit as SPA:
`ui/calofin_net/SpaFormView.vb` and the shapes field map offer
`Square/Radius/Cut/NotGiven`, and SPA still accepts the palette's OLD
wire values (`90`/`Diagonal`) from an un-rebuilt DLL, normalised at
the ask site like typed legacy input.  `lisp/spa/README.md` describes
the canonical words.

### 7.2 Bracket text that a click cannot send

**DONE — the table is empty.**  Every listed site (CORNERSTP's four,
the check family's `Skip rest` and `Move to the green +` triples,
POOL's `SIX-sided`, SPA's `Wall(centred)` — see 7.6 — lhd's
`[...] or [Done]`, ABHD's two-group tutorial prompt) now moves its
explanation into the question text and leaves the bracket as the bare
keyword list, per section 1 rule 1.  `cal:ask-yn-nav` carries the
fixed `[Yes/No/Back/Skip]` for the grouped build.

### 7.3 Keyword spelling conflicts

* ~~`ROUnd` vs `ROund`~~ **DONE** -- `ROUnd` everywhere (POOL needs
  `RO` for `ROman`); SPA's shape list and the palette's field map
  moved together.
* `spa:askkw "BottomLeft BottomRight TopRight TopLeft"` (the spillaway
  corner pick) -- no usable hotkeys (all collide until 7 letters in).
  Reviewed 2026-08-27 and DEFERRED on purpose: it works clicked or
  typed in full, and no replacement scheme was picked.
* ~~Tutorial selectors~~ **DONE** -- `Checks Demo Both`, default
  `<Both>`, everywhere (dimcheck, linfincheck, autobead, abhd,
  TUTORIALSPA, spacheck); the old words stay accepted typed in full,
  hidden.
* ~~Pause~~ **DONE** -- one spelling everywhere (indent allowed).

### 7.4 Structure stragglers

* ~~Version banners the tooling cannot see~~ **DONE** -- abhd's is now
  `pf:*version*` (its releases/ twin regenerates and prunes like any
  other), and every living unversioned tool took a `v1.0` banner
  (altabcdef, autodim, ccprecheck, check_drawing, dim_continue, drone,
  both drone_height files, lincheck, lintxtchk, tydrn, wcalst), so the
  banner-parity and stale-release checks cover the whole tree bar the
  deprecated acady matcher.  The pool/spa `"MMDDYY REV##"` form stays
  supported but new tools use `vN.N`.
* ~~`COVERCHECKVERSION` -> `COVERCHECKVER`~~ **DONE** (old name kept
  as an alias).
* Prefix styles: 15 files use `prefix-`, `paddle--` uses a double
  hyphen; new work uses `tool:`. Existing prefixes migrate only if
  their file is otherwise being reworked -- a rename touches every
  line.  (Still open, on purpose.)
* ~~4 living files with no `*error*` handler~~ **DONE** -- `abcdef`
  and `altabcdef` plot geometry, so they took a handler AND an undo
  group (a cancelled plot is one U now, not one per entity);
  `ccprecheck` and `lincheck` change no setting and open no group, so
  theirs does the only job it has -- keeping a cancel from printing a
  raw AutoLISP message.  The 8 `acady-*` stay as-is, deprecated.
* ~~Handlers that restore nothing~~ **DONE** where there was anything
  to restore.  `bpcallout` gained an undo group and closes it from the
  handler.  `paddle`'s block import clobbered `CMDECHO`/`ATTREQ` and
  restored them on the line after the command, so a throw inside
  `-INSERT` left both clobbered -- and `c:PADDLE`'s handler could not
  help, because those are the import helper's own locals; the command
  is wrapped so the restore always runs.  `DroneHeightGPS` is left
  alone on purpose: it changes no setting and opens no group, so its
  handler already does all there is to do.
* ~~`AUTOBEAD.lsp` closes an undo group unguarded~~ **DONE** -- it
  tracks `undo-open` and closes only a group it opened, in the
  canonical casing (an error before the `_Begin` used to run `_End` on
  nothing, erroring inside the error handler).  ~~BPCALLOUT's `*break,` wildcard typo~~ **DONE** -- and
  the whole cancel test is now ONE canonical spelling repo-wide, with
  `cal:error-cancel-p` / `cal:undobegin` / `cal:undoend` in the
  library so new code has nothing to hand-copy.  ~~XYPLOT's missing
  handler and undo group~~ (post-standard miss, not on the old list)
  **DONE**.
* Uppercase `.LSP` extensions (`POOL.LSP`, `SPA.LSP`, +3 more) --
  reviewed 2026-08-27 and DEFERRED on purpose: zero functional gain
  against churn in tests/tools/startup suites; rename only with a
  coordinated pass of its own.

### 7.5 What breaks when a keyword or prompt changes

Check these before renaming anything -- the tests validate scripted
answers against the live `initget` list
(`tests/lispvm.py` `_match_kw`), so a keyword rename fails loudly, and
several assert prompt text:

* Keyword scripts: `test_pool_runtime.py`, `test_pool_lisp.py`,
  `test_cornerstp_geometry.py`, `test_lincheck.py`,
  `test_ccprecheck.py`, `test_laser_fit.py`,
  `test_perp_points.py`, `test_spa_form.py`, `test_pool_form.py`.
  Changing only capitalization (`SHallow` -> `Shallow`) also breaks
  any script that types the short form.
* Prompt-text asserts: `test_pool_runtime.py` (`"B - overall length"`,
  `"Cross dim body A-C"`, `"corner radius"`...),
  `test_spa_form.py` / `test_pool_form.py` (`'Corner C'`,
  `'Bottom type'`, the `"<letter> - "` prefix contract of
  `pool:fkeyof` per `ui/calofin_net/README.md:110`),
  `test_cdcreate.py:141` (`"ssget _I"`), `test_lincheck.py` /
  `test_ccprecheck.py` (exact report lines).
* Palette wire values: `PoolFormView.vb` +
  `assets/bottoms/fieldmap.json` (the six `pool:*btypes*` keywords),
  `SpaFormView.vb` + `assets/shapes/fieldmap.json` (corners, now the
  canonical `Square/Radius/Cut/NotGiven`; SPA still accepts the old
  `90`/`Diagonal` wire values from an un-rebuilt DLL).  Both form
  tests end by asserting every field-map key is one the routine
  reads.
* Prose: root `README.md` POOL/SPA sections, `lisp/pool/README.md`,
  `lisp/spa/README.md`, `lisp/cdcallout/README.md` (Back),
  `ui/calofin_net/README.md`.

### 7.6 Remaining, reviewed 2026-08-27

The 2026-08-27 streamlining pass closed everything above not
explicitly kept open.  What remains, each a deliberate deferral:

* SPA's spillaway corner-pick keywords (7.3) -- no hotkey scheme
  chosen yet.
* The uppercase `.LSP` renames and the `prefix-` style migrations
  (7.4) -- churn without behaviour.
* `*error*` handlers for `abcdef`, `altabcdef`, `ccprecheck`,
  `lincheck`; restore-nothing handlers in `bpcallout`,
  `DroneHeightGPS`, `paddle`; AUTOBEAD's unguarded undo end (7.4).
* NORMIESTEP's Treatment question offers no Back: `ns-askkw` has no
  back parameter, and adding one is a refactor of the step question
  chain, not a wording fix.
* `cal:askkw`'s signature still takes a hand-written SHOWN bracket
  where section 4's reference derives it from the keyword list.  The
  mirror pins `spa:askkw`/`pool:askkw` to it, so aligning the
  signature is a coordinated pass of its own; until then the 7.2
  class is closed by review, not by construction.
* The VB palette's button catalog still lacks the newer tools --
  additions are unverifiable without a machine that can build the
  DLL, so `ui/calofin_ui/calofin.lsp`'s roster (test-pinned) carries
  the full list and LAZPANEL remains the zero-install surface.
* ~~Tooling gap~~ **DONE, and further**: both checkers take the
  prefix from the file, exit non-zero on findings (with
  `tools/scope_baseline.txt` holding the accepted module globals), and
  the three generators grew `--check` modes that
  `tools/check_standards.py` runs -- a hand-edited generated twin, a
  stale release or a drifted bundle body fails the standards check.
  `make check` / `make parity` (`tools/run_tests.py`) are the entry
  points.
