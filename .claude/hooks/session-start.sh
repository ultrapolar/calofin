#!/bin/bash
# SessionStart hook -- orient a new session in the calofin tree.
#
# There is nothing to install: the tests run on the Python standard
# library alone (tests/lispvm.py is a pure-Python AutoLISP interpreter,
# no pip, no node).  So this hook spends its time on the thing that
# actually goes wrong here -- the three tiers drifting apart -- and on
# telling the session what it needs to know before it edits a .lsp.
#
# It runs in well under a second and touches nothing, so it is not
# gated on CLAUDE_CODE_REMOTE; local sessions get the same guardrail.
# To make it web-only, uncomment the CLAUDE_CODE_REMOTE guard below.

set -euo pipefail

# if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then exit 0; fi

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# ---- environment ----------------------------------------------------
# CALOFIN_LISP_ROOT is deliberately NOT set here.  Unset means the tests
# read lisp/, which is what they must do by default; exporting it would
# silently point every run at the shared build and a standalone
# regression would stop showing up.  Set it per command instead:
#     CALOFIN_LISP_ROOT=shared python3 tests/test_pool_runtime.py
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PYTHONDONTWRITEBYTECODE=1"
    echo "export PYTHONUNBUFFERED=1"
    echo "export CALOFIN_ROOT=$(pwd)"
  } >> "$CLAUDE_ENV_FILE"
fi

python3 --version >/dev/null 2>&1 || {
  echo "session-start: python3 not found - the test suite cannot run" >&2
  exit 1
}

# ---- orientation ----------------------------------------------------
TRUNK="claude/lisp-consolidation-strategy-9nrc7a"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

echo "calofin -- AutoLISP tools for pool/spa drafting (no deps; stdlib Python only)"
echo
echo "Tiers, in the order a tool moves through them:"
echo "  wip/       drafts, no version banner            $([ -d wip ] && echo "$(find wip -iname '*.lsp' | wc -l) files" || echo '(not created yet)')"
echo "  lisp/      standalone, one self-contained file  $(find lisp -iname '*.lsp' | wc -l) files"
echo "  releases/  dated REV twins, generated           $(find releases -iname '*.lsp' | wc -l) files"
echo "  shared/    grouped, all load together on cal:   $(find shared -iname '*.lsp' | wc -l) files"
echo
echo "Rules that bite (STANDARDS.md is the full text):"
echo "  - tool logic lives in lisp/; shared/ is its twin, never where a change starts"
echo "  - mirror a lisp/ change into shared/<FILE>.lsp in the SAME commit, then"
echo "    python3 tools/release_lisp.py && python3 tools/build_shared_bundle.py"
echo "  - never hand-edit releases/ or shared/CALOFIN-ALL.lsp - both are generated"
echo "  - only shared/CALOFIN-LIB.lsp defines cal: symbols"
echo "  - corner treatments are Square/Radius/Cut/NotGiven, nothing else"
if [ "$BRANCH" != "$TRUNK" ]; then
  echo "  - branch is '$BRANCH'; CLAUDE.md pins work to $TRUNK"
fi
echo
echo "Checks:  python3 tools/check_standards.py   (tiers in step)"
echo "         python3 tools/check_lisp.py <f>    python3 tools/check_scope.py <f>"
echo "Tests:   python3 tests/test_shared.py       (whole grouped build in one session)"
echo "         CALOFIN_LISP_ROOT=shared python3 tests/<t>.py   (parity vs standalone)"
echo "Known failing on a clean checkout, not yours: test_pool_form.py, test_spa_form.py"
echo

# ---- the guardrail --------------------------------------------------
if ! python3 tools/check_standards.py; then
  echo
  echo "^ the tiers have drifted - fix before adding to the drift."
fi
