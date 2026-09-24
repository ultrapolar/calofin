#!/bin/bash
# The inner loop: the checks that can see THIS edit, in seconds.
#
# `make check` is slow because most of its checks read every tier.
# Most of that has nothing to say about the file you just
# changed.  This runs the per-file checks on the files you name and the
# tier-scoped ones on lisp/ only -- about a third of the time -- so the slow full run is
# something you do once, before committing, instead of every iteration.
#
#     precheck.sh lisp/squareup/SQUAREUP.lsp
#     precheck.sh $(git diff --name-only | grep '\.lsp$')
#     precheck.sh                       # whatever git says changed
#
# It is NOT a substitute for `make check`: check_dcl and check_vb are
# not run, osnap/color/perf see lisp/ only, and releases/ is covered by
# the full run alone.  Finish with `make check && make test`.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}" || exit 1

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  # changed AND untracked: a brand-new tool is untracked until its first
  # commit, and it is exactly the file this is most wanted for
  mapfile -t files < <( { git diff --name-only HEAD -- '*.lsp' '*.LSP'
                          git ls-files --others --exclude-standard \
                            -- '*.lsp' '*.LSP'; } \
                        | grep -E '^(lisp|wip)/' | sort -u || true)
fi

if [ ${#files[@]} -eq 0 ]; then
  echo "precheck: no lisp/ file named or changed -- nothing to scope to."
  echo "          run 'make check' for the whole tree."
  exit 0
fi

fail=0
run () { echo "+ $*"; "$@" || fail=1; }

echo "precheck: ${#files[@]} file(s)"
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  run python3 tools/check_lisp.py "$f"
  run python3 tools/check_scope.py "$f"
done

# These take no file argument -- only a tier.  lisp/ is where the edit
# is; releases/ and shared/ are regenerated from it, so a fault there
# is a fault here, and the full run will catch the tier drift anyway.
run python3 tools/check_osnap.py --tier lisp
run python3 tools/check_color.py --tier lisp
run python3 tools/check_perf.py --tier lisp

# Whole-tree only (it takes no file or tier) -- and worth it: a new
# (setq v (getX ...)) with no lzd:ask after it is the likeliest thing an
# edit breaks, and nothing else here would say so before make check.
run python3 tools/check_lazdiag.py

# Whole-tree but quick, and both are easy to break from a single edit:
# a new prompt with no Back, a shop term spelt around its knob, and a
# tier left behind.
run python3 tools/check_back.py
run python3 tools/check_terms.py
run python3 tools/check_standards.py

echo
if [ "$fail" != 0 ]; then
  echo "precheck: FAILED -- see above."
  echo "          the decoder for each check is in the calofin-checks skill."
  exit 1
fi
echo "precheck: clean.  Before committing, the full run:"
echo "    make check && make test"
