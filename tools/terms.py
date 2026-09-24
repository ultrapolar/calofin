# SPDX-License-Identifier: GPL-3.0-or-later
"""The SHOP TERMS: wording the tools write INTO THE DRAWING that a shop
may spell its own way.

A term is a NAMED GROUP OF KNOBS.  Every tool that writes the wording
carries a knob for it in its own tunables block, read through the
tool's term reader --

    (setq pool:*typ-note* (pool:term "typ-note" " Typ."))

-- so the shop's spelling (the profile value ``CalofinTerm-<id>``)
reaches the knob as the file loads, the literal stays the shipped
default, and LAZTUNE's knob machinery offers the knob like any other.
This table says which knobs are ONE term.  It is hand-kept, like
gen_knobs.SAME and gen_ui_data.FEATURED: that two knobs spell the same
piece of drawing text is a judgement, not something a name can say.

What reads it:

* tools/gen_knobs.py writes ``lzp:*terms*`` into LAZPANEL.lsp from it
  (id, default, meaning, member knobs -- LAZTUNE's Terms page lists
  that), and builds a ``lzp:*knobfam*`` family from each term first,
  so "Set everywhere" on one member reaches the rest.
* tools/check_terms.py holds the tree to it: every member's shipped
  literal is the default, a knob that ships the default but is not a
  member is named ("join term X"), and the default spelled as a bare
  string in drawing code outside a tunables block fails.

ONLY DRAWING TEXT IS EVER A TERM.  A keyword or a prompt's wording is
not: LAZFORM, LAZSPA, LAZSTEP, the palette and LAZDIAG's replays answer
prompts by their exact spelling, and a shop-spelt keyword would break
every one of them.  And only text no tool READS BACK out of a drawing:
a review tool that matched " Typ." in a dimension's text would have to
read the term too, or a shop's spelling would blind it.  Neither of the
first two terms is read back (checked with rg over lisp/ when they
were added).

To add a term: give each tool that writes the wording a knob through
its term reader (``tool:term`` -- copy the six-line reader from
POOL.LSP's "shop terms" section, above the tunables block, and add the
``'tool:term': 'cal:term'`` swap to its tools/mirror_shared.py entry),
add a row here, then ``python3 tools/gen_knobs.py`` and
``python3 tools/check_terms.py``.
"""

#: kind: 'label' -- any non-empty string; the only kind there is so far.
TERMS = [
    dict(id='typ-note', default=' Typ.', kind='label',
         meaning=('the suffix on the one dimension that stands for a '
                  'group of equal ones'),
         members=['pool:*typ-note*', 'spa:*typ-note*', '*cs-typ-note*',
                  'hn:*typ-note*', 'sf:*typ-note*', 'ad:*typ-note*']),
    dict(id='ng-note', default='Not Given', kind='label',
         meaning='the note on a corner the order sheet never gave',
         members=['pool:*ng-note*', 'spa:*ng-note*', '*cs-ng-note*']),
]


def by_id():
    return {t['id']: t for t in TERMS}


def member_of():
    """{knob name: term id}."""
    return {m: t['id'] for t in TERMS for m in t['members']}
