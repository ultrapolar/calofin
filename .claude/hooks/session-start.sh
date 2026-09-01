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
  } >> "$CLAUDE_ENV_FILE"
fi

python3 --version >/dev/null 2>&1 || {
  echo "session-start: python3 not found - the test suite cannot run" >&2
  exit 1
}

# ---- orientation ----------------------------------------------------
TRUNK="claude/lisp-consolidation-strategy-9nrc7a"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

# ---- the branch guard -----------------------------------------------
# CLAUDE.md pins every session to the trunk.  A session opened on some
# other branch is switched there when that loses nothing: the tree is
# clean and the branch has no commit the trunk lacks.  Otherwise the
# session stops and says what to do -- switching a dirty tree, or off
# a branch carrying unmerged work, is how the tree re-fragmented
# (five branches carried work the trunk never saw, 2026-09-01).
if [ "$BRANCH" != "$TRUNK" ] && [ "$BRANCH" != "?" ]; then
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "session-start: on '$BRANCH' with uncommitted changes; CLAUDE.md pins work to $TRUNK" >&2
    echo "  commit or stash them, then: git fetch origin $TRUNK && git checkout -B $TRUNK origin/$TRUNK" >&2
    exit 1
  fi
  git fetch -q origin "$TRUNK" 2>/dev/null || true
  if git rev-parse -q --verify "origin/$TRUNK" >/dev/null 2>&1; then
    AHEAD=$(git rev-list --count "origin/$TRUNK..HEAD" 2>/dev/null || echo 0)
    if [ "$AHEAD" != "0" ]; then
      echo "session-start: '$BRANCH' carries $AHEAD commit(s) the trunk lacks; not switching" >&2
      echo "  land them first: git rebase origin/$TRUNK && git push origin HEAD:$TRUNK" >&2
      echo "  then: git checkout -B $TRUNK origin/$TRUNK" >&2
      exit 1
    fi
    if git checkout -q -B "$TRUNK" "origin/$TRUNK" 2>/dev/null; then
      echo "session-start: was on '$BRANCH'; checked out $TRUNK (CLAUDE.md pins all work there)"
      BRANCH="$TRUNK"
    else
      echo "session-start: could not check out $TRUNK from '$BRANCH'" >&2
      exit 1
    fi
  else
    echo "session-start: on '$BRANCH' and origin/$TRUNK is unreachable; CLAUDE.md pins work to $TRUNK" >&2
    exit 1
  fi
fi

echo "calofin -- AutoLISP tools for pool/spa drafting (no deps; stdlib Python only)"
echo
echo "Tiers, in the order a tool moves through them:"
echo "  wip/       drafts, no version banner            $([ -d wip ] && echo "$(find wip -iname '*.lsp' | wc -l) files" || echo '(not created yet)')"
echo "  lisp/      standalone, one self-contained file  $(find lisp -iname '*.lsp' | wc -l) files"
echo "  releases/  dated REV twins, generated           $(find releases -iname '*.lsp' | wc -l) files"
echo "  shared/    grouped: LAZPASS.lsp + parts/       $(find shared/parts -iname '*.lsp' | wc -l) parts"
echo
echo "Rules that bite (STANDARDS.md is the full text):"
echo "  - tool logic lives in lisp/; shared/ is its twin, never where a change starts"
echo "  - mirror a lisp/ change into shared/parts/<FILE>.lsp in the SAME commit, then"
echo "    python3 tools/release_lisp.py && python3 tools/build_shared_bundle.py"
echo "  - never hand-edit releases/ or shared/LAZPASS.lsp - both are generated"
echo "  - only shared/parts/CALOFIN-LIB.lsp defines cal: symbols"
echo "  - some tools are HELD BACK from LAZPASS.lsp on purpose - the list"
echo "    and the reasons are cal:*held-back* in parts/CALOFIN-LOADER.lsp"
echo "  - corner treatments are Square/Radius/Cut/NotGiven, nothing else"
echo "  - branch is '$BRANCH' - the trunk; push it at the end of the session, and"
echo "    if the setup named another branch, push that too (same commit)"
echo
echo "Checks:  make check      (tiers in step + generated tiers current + lint)"
echo "Tests:   make test       (full suite, lisp/ tier - tools/run_tests.py)"
echo "         make parity     (both tiers - the standalone-vs-grouped drift check)"
echo "Known failing on a clean checkout: none - EXPECTED_FAILURES in"
echo "  tools/run_tests.py is the authoritative (empty) list"
echo "Forms:   POOL, SPA and the step routines all take an answer store;"
echo "         a prompt edit shows up in test_*_form.py and the LAZ* suites"
echo

# ---- the guardrail --------------------------------------------------
if ! python3 tools/check_standards.py; then
  echo
  echo "^ the tiers have drifted - fix before adding to the drift."
fi
