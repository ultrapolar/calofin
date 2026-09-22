#!/bin/bash
# Regenerate every tier below lisp/, after a lisp/ edit.
#
# CLAUDE.md asks for the mirror and the two regenerations in the SAME
# commit as the edit, and by hand is how twins drift -- shared/parts/SPA.lsp
# sat two revisions behind while every one-file check stayed green.  So
# this is the whole of step 3 and step 4, in order, as one command.
#
#     retier.sh SQUAREUP                 # mirror that tool, regenerate all
#     retier.sh POOL SPA                 # several
#     retier.sh                          # mirror everything (slower)
#
# It does NOT bump the version banner (editorial -- you decide the
# number) and it does NOT run the checks; `precheck.sh` is those.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}" || exit 1

fail=0
run () {
  echo "+ $*"
  "$@" || { echo "   ^ FAILED"; fail=1; }
}

if [ $# -gt 0 ]; then
  for t in "$@"; do run python3 tools/mirror_shared.py "$t"; done
else
  run python3 tools/mirror_shared.py
fi

# releases/ first: it reads the version banner off lisp/, and the bundle
# reads shared/parts/, so this order is the order the tiers depend on.
run python3 tools/release_lisp.py
run python3 tools/build_shared_bundle.py

# The generated UI tiers.  All four are sub-second and are no-ops when
# nothing they read has moved, so running them unconditionally is
# cheaper than working out whether this edit touched a caption, a knob,
# a chart table or a featured glyph.
run python3 tools/gen_knobs.py
run python3 tools/gen_ui_data.py
run python3 tools/gen_ui_charts.py
run python3 tools/gen_ribbon_icons.py

# Not a tier below lisp/ at all: AGENTS.md is generated from the SKILLS,
# so a lisp/ edit never makes it stale.  It is here anyway because it is
# sub-second and because "run retier and everything generated is
# current" is a rule worth being able to state without a footnote.
run python3 tools/gen_agents_md.py

echo
if [ "$fail" != 0 ]; then
  echo "retier: something above failed -- fix it before committing."
  exit 1
fi
echo "retier: every generated tier is current.  Now: precheck.sh <file>"
