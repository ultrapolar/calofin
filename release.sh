#!/bin/sh
# ==========================================================================
# release.sh - stamp a lisp and generate its dated twin
#
#   ./release.sh AUTOBEAD 2          -> AUTOBEAD_081726_REV02.lsp
#   ./release.sh AUTOBEAD 2 090126   -> AUTOBEAD_090126_REV02.lsp
#
# Rewrites the revision and date stamps inside <NAME>.lsp, then copies it
# byte-for-byte to <NAME>_MMDDYY_REV##.lsp.  Both files end up identical, so
# AUTOBEADVER reports the same revision no matter which one was loaded.
#
# Always regenerate with this rather than copying by hand -- a hand-copied
# twin drifts from the master the moment either one is edited.
# ==========================================================================

set -e

NAME="$1"
REV="$2"
DATE="$3"

if [ -z "$NAME" ] || [ -z "$REV" ]; then
    echo "usage: $0 <LISPNAME> <rev-number> [MMDDYY]" >&2
    echo "   eg: $0 AUTOBEAD 2" >&2
    exit 1
fi

SRC="${NAME}.lsp"

if [ ! -f "$SRC" ]; then
    echo "error: $SRC not found" >&2
    exit 1
fi

# zero-pad the revision to two digits
REVNUM=$(printf '%02d' "$REV")
REVTAG="REV${REVNUM}"

# default to today
[ -z "$DATE" ] && DATE=$(date +%m%d%y)

# MM/DD/YY for the in-file stamp
PRETTY=$(echo "$DATE" | sed 's/^\(..\)\(..\)\(..\)$/\1\/\2\/\3/')

LC=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')

# Paren balance, ignoring strings and comments.  Run before and after the
# stamp so a bad substitution can never ship a file AutoCAD won't load.
parens() {
    awk '{
        n = length($0); ins = 0
        for (i = 1; i <= n; i++) {
            c = substr($0, i, 1)
            if (ins) {
                if (c == "\\") { i++; continue }
                if (c == "\"") ins = 0
                continue
            }
            if (c == "\"") { ins = 1; continue }
            if (c == ";") break
            if (c == "(") o++
            if (c == ")") o--
        }
    } END { print o+0 }' "$1"
}

BEFORE=$(parens "$SRC")

# Stamp the master in place.  '|' is the sed delimiter because the pretty
# date contains slashes.  Both patterns are anchored to the start of the
# line so they can only ever hit the settings block -- an unanchored match
# also rewrites the variable where it is *used*, e.g. inside the report
# string, silently corrupting the code.
sed -i.bak \
    -e "s|^\((setq \*${LC}-rev\* *\"\)[^\"]*\"|\1${REVTAG}\"|" \
    -e "s|^\( *\*${LC}-date\* *\"\)[^\"]*\"|\1${PRETTY}\"|" \
    "$SRC"

rm -f "${SRC}.bak"

if ! grep -q "^(setq \*${LC}-rev\* *\"${REVTAG}\"" "$SRC"; then
    echo "error: revision stamp not applied in $SRC -- check the settings block" >&2
    exit 1
fi

AFTER=$(parens "$SRC")

if [ "$BEFORE" != "$AFTER" ] || [ "$AFTER" != "0" ]; then
    echo "error: $SRC has unbalanced parens after stamping" >&2
    echo "       (before=$BEFORE after=$AFTER) -- not releasing" >&2
    exit 1
fi

OUT="${NAME}_${DATE}_${REVTAG}.lsp"
cp "$SRC" "$OUT"

echo "stamped  $SRC   -> $REVTAG ($PRETTY)"
echo "released $OUT"
echo
echo "Both files are identical. Load either; AUTOBEADVER reports $REVTAG."
