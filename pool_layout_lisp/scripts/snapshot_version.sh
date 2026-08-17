#!/usr/bin/env bash
# Take a dated, revisioned snapshot of a POOL.LSP-family source file
# for stack-tracking purposes.
#
# POOL.LSP itself stays the single always-current file meant for
# APPLOAD / a startup suite -- its name never changes, so nothing
# breaks for anyone who already has it referenced.  Every snapshot
# under versions/ is an exact byte-for-byte copy of that file at one
# point in time, under a name that encodes WHEN and WHICH ITERATION:
#
#   versions/POOL_MMDDYY_REV##.LSP
#
# so you can tell at a glance -- or by diffing -- what someone else
# has loaded in their stack versus what you're about to push out.
#
# Run this every time POOL.LSP (or POOLDEMO.LSP / TUTORIALPOOL.LSP)
# changes and you're ready to record that as a new iteration.  The
# revision counter is per source file (POOL.REVISION, POOLDEMO.REVISION,
# ...) and only ever goes up.
#
# Usage:
#   scripts/snapshot_version.sh              # snapshots POOL.LSP
#   scripts/snapshot_version.sh POOLDEMO.LSP  # or any other file here

set -euo pipefail
cd "$(dirname "$0")/.."          # -> pool_layout_lisp/

SRC="${1:-POOL.LSP}"
if [ ! -f "$SRC" ]; then
    echo "error: $SRC not found in pool_layout_lisp/" >&2
    exit 1
fi

STEM="$(basename "$SRC" .LSP)"
VERDIR="versions"
REVFILE="$VERDIR/$STEM.REVISION"

mkdir -p "$VERDIR"

if [ -f "$REVFILE" ]; then
    REV=$(( $(cat "$REVFILE") + 1 ))
else
    REV=1
fi
printf '%s' "$REV" > "$REVFILE"

DATE="$(date +%m%d%y)"
REVPAD="$(printf '%02d' "$REV")"
DEST="$VERDIR/${STEM}_${DATE}_REV${REVPAD}.LSP"

# POOL.LSP carries its own version string (checked on demand with the
# POOLVERSION command); keep it in lock-step with the snapshot we're
# about to take, so a loaded copy always self-identifies correctly.
if [ "$STEM" = "POOL" ]; then
    ISODATE="$(date +%Y-%m-%d)"
    sed -E -i.bak \
        "s/\(setq pool:\*version\* \"POOL REV[0-9]+ -- [0-9-]+\"\)/(setq pool:*version* \"POOL REV${REVPAD} -- ${ISODATE}\")/" \
        "$SRC"
    rm -f "${SRC}.bak"
fi

cp "$SRC" "$DEST"
echo "Snapshot written: pool_layout_lisp/$DEST  (revision $REVPAD)"
