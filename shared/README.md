# shared/ -- the loaded-together build

Every AutoLISP tool in this repo, built against one common helper
library instead of each embedding its own copies. The assumption in
this folder is that **everything loads together in one AutoCAD
session**: APPLOAD `CALOFIN-LOADER.lsp` and every command from the
whole toolset is available at once.

The standalone builds live in `lisp/` -- one self-contained file per
tool, loadable alone. Do not mix the two in a session; the shared
files deliberately omit helpers the library provides, so a shared tool
without `CALOFIN-LIB.lsp` loaded is broken by design.

## Layout

```
CALOFIN-LOADER.lsp   APPLOAD this one file - loads everything below in order
CALOFIN-LIB.lsp      the shared helpers, namespace cal: (see STANDARDS.md)
<TOOL>.lsp           one file per tool, same basename as its lisp/ source
                     (extension lowercased), minus the helpers now in the lib
```

The acady drawing-standards matcher (`lisp/standards_checker/`) is a
deprecated project and is not carried here. It still loads the old way,
on its own, from `lisp/standards_checker/src/acady-loader.lsp`.

## Loading it

APPLOAD `CALOFIN-LOADER.lsp`. It finds the rest of the folder itself,
trying four things in order and asking for nothing it can work out:

1. `cal:*dir*`, if you set it before loading,
2. the support file search path, if the folder is on it,
3. the folder a previous session found (remembered under
   `HKEY_CURRENT_USER\Software\Calofin`),
4. a one-time file dialog -- pick `CALOFIN-LIB.lsp` out of the folder
   and it is remembered from then on.

It prints the folder it settled on, then either
`shared build loaded - every command in one session` or a count of what
is missing.

**If it says it could not locate the build folder**, the folder is not
somewhere AutoCAD searches and the dialog was cancelled. Either add the
folder to *Options > Files > Support File Search Path* (the permanent
fix -- step 2 then finds it every time), or run

```
(setq cal:*dir* "C:\\path\\to\\shared")
```

before APPLOADing the loader.

Note that `findfile` alone is not enough for this: APPLOAD takes a full
path out of its own file dialog but does not add that folder to the
support path, so a build APPLOADed from, say, a Downloads folder cannot
see its own siblings without one of the four routes above.

## What the library owns

`CALOFIN-LIB.lsp` holds the helpers that used to be duplicated per
tool -- the ask layer (`cal:askkw`, `cal:askyn`, `cal:ask-yn`,
`cal:ask-yn-nav`, `cal:asktreat`, `cal:askstr`, `cal:back-word-p`,
`cal:pause`, sentinel `CAL-BACK`), sysvar save/restore
(`cal:syssave` / `cal:sysrestore` / `cal:osup` / `cal:osdown`,
`cal:dimstysave` / `cal:dimstyrestore`), `cal:ensure-layer` /
`cal:layer-usable-p`, the 2-D vector set (`cal:v+ v- v* dot mid perp
unit vlen d2 cross dist 2d`), the length-preserving set (`cal:unitn
dotn midn proj-param axis-pt pt-line-dist`), angles (`cal:angnorm
signed-dang ang-diff`), `cal:circumcenter`, `cal:bbox-ent` /
`cal:bbox-ss`, lists (`cal:nthcdr sublist dedupe`), numbers
(`cal:ceil tan`), strings (`cal:trim pad zeropad2 datestr`), entity
creation (`cal:text cal:mtext`), and `cal:block-number`. Each
helper's comment names the tool implementation it was lifted from.

Deliberately NOT absorbed (divergent behavior the tools rely on):
POOL/SPA's `unit` (returns `(0.0 0.0)` on a zero vector, not nil),
abhd/lhd's 2-element `circumcenter` and flat `bbox`, abhd's
`pf:block-number` (no numeric fallback), perp_points' consecutive-only
`dedupe`, the cornerstp 3-element vector set, `xft:mid` (3-D), the
tutorials' pauses (they can stop the tour, with opposite polarities),
and every false friend (`report`, `say`, `log`, the non-string
`trim`s, `strip`, `tag`, `restore`, `finish`, `mark-point`).

Known, accepted behavior deltas vs the lisp/ builds:
* the check family's output layers are now created with a linetype
  group and are repaired (thawed/unlocked/switched on, with a message)
  when a stale one is found -- previously a report written onto a
  frozen report layer was silently invisible.
* `cal:ensure-layer`'s repair announcement no longer carries a
  per-tool prefix.

## Tests

```
python3 tests/test_shared.py                                 # loads everything together
CALOFIN_LISP_ROOT=shared python3 tests/test_pool_runtime.py  # any VM test, shared build
```

`CALOFIN_LISP_ROOT=shared` reruns any VM-driven test in `tests/`
against this folder instead of `lisp/` (see `lispvm.VM._remap_root`);
run them plain and they cover `lisp/` exactly as before.

## Keeping it in sync

`lisp/` is still where tool logic is developed first. A change to a
tool's behavior in `lisp/<tool>/` must be mirrored into its shared
twin here -- the diff between the two should only ever be the missing
helpers and the `cal:` call sites. `releases/` stamping does not apply
here (`tools/release_lisp.py` reads `lisp/` only).
