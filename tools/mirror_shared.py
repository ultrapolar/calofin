#!/usr/bin/env python3
"""Regenerate a shared/parts/ twin from its lisp/ original.

The grouped build is the same tool calling CALOFIN-LIB.lsp instead of
carrying its own copies of the generic helpers.  CLAUDE.md asks for that
mirroring by hand, in the same commit -- and by hand is how twins drift:
`shared/parts/SPA.lsp` sat two revisions behind its original while every
one-file check still passed, so the grouped build drew loose lines where
the standalone one drew a bounded polyline.

So the swap is written down instead, once per tool, and applied here.

    python3 tools/mirror_shared.py            # every tool listed below
    python3 tools/mirror_shared.py SPA        # just one
    python3 tools/mirror_shared.py --check    # write nothing; exit 1 if
                                              # any generated twin on disk
                                              # differs from a fresh run

`tools/check_standards.py` compares the two version banners, and runs
the --check above, so a generated twin that is hand-edited or left
behind fails the standards check rather than shipping.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BANNER = (";;; SHARED BUILD: requires CALOFIN-LIB.lsp "
          "(load via CALOFIN-LOADER.lsp).\n"
          ";;; Generic helpers live there under cal: - see STANDARDS.md.\n"
          ";;;\n")

# The stroke-font section's prose, byte-identical in all three chart
# forms -- and false in a twin that takes the table from the library.
FONT_PROSE = (
    ";;;  This file carries its own copy because a standalone file has to\n"
    ";;;  load alone.  The grouped build takes the table, its metrics, the\n"
    ";;;  tile palette and the seven drawing helpers from CALOFIN-LIB.lsp\n"
    ";;;  instead -- all three chart forms had the same copy, and the swap\n"
    ";;;  map in tools/mirror_shared.py is what says so and checks it.\n"
    ";;;  DCL has no way to draw text into an image tile -- vector_image draws\n"
    ";;;  line segments and that is the whole of it -- so the letters and the\n"
    ";;;  numbers on the chart are stroked out of segments here.\n"
    ";;;\n"
    ";;;  One entry per character: the glyph as a list of polylines, each a\n"
    ";;;  flat list of x y x y ... in TENTHS of a font unit, on a cell 4 wide\n"
    ";;;  and 6 tall with y running DOWN the way image-tile pixels do.\n"
    ";;;  Integers, so nothing here depends on float formatting.\n")

FONT_PROSE_SHARED = (
    ";;;  THIS build takes the table, its metrics, the tile palette and the\n"
    ";;;  seven drawing helpers from CALOFIN-LIB.lsp -- cal:*imgfont*, the\n"
    ";;;  three cal:*imgfont-* sizes, cal:*imgcol-* and cal:img* -- shared\n"
    ";;;  with the other two chart forms, which carried the same copy.  The\n"
    ";;;  standalone file keeps its own, because it has to load alone.\n"
    ";;;  DCL has no way to draw text into an image tile -- vector_image draws\n"
    ";;;  line segments and that is the whole of it -- so the letters and the\n"
    ";;;  numbers on the chart are stroked out of segments.\n"
    ";;;\n"
    ";;;  One entry per character, in the library: the glyph as a list of\n"
    ";;;  polylines, each a flat list of x y x y ... in TENTHS of a font\n"
    ";;;  unit, on a cell 4 wide and 6 tall with y running DOWN the way\n"
    ";;;  image-tile pixels do.\n")

# Per tool: where it lives, and which of its own helpers the library
# already provides.  Only helpers whose behaviour the library reproduces
# exactly belong in a swap map -- anything else stays local.
TOOLS = {
    'SPA': {
        'src': 'lisp/spa/SPA.LSP',
        'swap': {
            # the ink table: one body, and the library's is it
            'spa:ink': 'cal:ink',
            'spa:v+': 'cal:v+', 'spa:v-': 'cal:v-', 'spa:v*': 'cal:v*',
            'spa:dot': 'cal:dot', 'spa:perp': 'cal:perp',
            'spa:mid': 'cal:mid', 'spa:trim': 'cal:trim',
            'spa:npos': 'cal:angnorm',
            'spa:osup': 'cal:osup', 'spa:osdown': 'cal:osdown',
            'spa:syssave': 'cal:syssave',
            'spa:sysrestore': 'cal:sysrestore',
            'spa:askkw': 'cal:askkw',
            'spa:undobegin': 'cal:undobegin',
            'spa:undoend': 'cal:undoend',
        },
        'drop_globals': ['spa:*sysold*', 'spa:*odstyle*'],
        # cal:syssave takes the sysvars as an argument where spa:syssave
        # baked them in, and the library keeps the dimension-style
        # save/restore in its OWN pair -- so the one call becomes two.
        # Drop that second call and the grouped build quietly stops
        # putting the drawing's dimension style back.
        'expand': {
            '(cal:syssave)': ['(cal:syssave (spa:sysvars))',
                              '(cal:dimstysave)'],
            '(cal:sysrestore)': ['(cal:sysrestore)', '(cal:dimstyrestore)'],
        },
        # spa:askkw already takes the SHOWN bracket third, like the
        # library's -- so no bracket translation is needed here
        'askkw_hidden': False,
        # ...but the two signal Back with different symbols, and every
        # caller tests for it, so the sentinel moves with the helper.
        # Miss this and Back silently stops working in the grouped build
        # while every other check still passes.
        'symbols': {'SPA-BACK': 'CAL-BACK'},
    },
    # Like POOLDEMO: the tutorial defines no state helpers of its own,
    # it drives SPA's cross-file.  Two of those (syssave/sysrestore)
    # are swapped away in the SPA entry above, so without the same swap
    # here the grouped tutorial calls a function the grouped build no
    # longer defines -- and dies at its first statement.  It did:
    # nothing ran c:TUTORIALSPA until tests/test_tutorialspa.py.
    'TUTORIALSPA': {
        'src': 'lisp/spa/TUTORIALSPA.LSP',
        'swap': {
            'spa:syssave': 'cal:syssave',
            'spa:sysrestore': 'cal:sysrestore',
            'spa:undobegin': 'cal:undobegin',
            'spa:undoend': 'cal:undoend',
        },
        'drop_globals': [],
        # the same one-into-two the SPA entry does, and for the same
        # reason: the library keeps the dimension-style pair separate
        'expand': {
            '(cal:syssave)': ['(cal:syssave (spa:sysvars))',
                              '(cal:dimstysave)'],
            '(cal:sysrestore)': ['(cal:sysrestore)', '(cal:dimstyrestore)'],
        },
    },
    # CDCREATE keeps its own dim-style pair -- it restores a style only
    # when the style really moved, which cal:dimstyrestore does not
    # model -- but the sysvar snapshot and ensure-layer are the library
    # helpers verbatim, so those swap out.  Listed here because the twin
    # was being hand-copied, and a hand-copied twin is a twin that drifts.
    'CDCREATE': {
        'src': 'lisp/cdcreate/CDCREATE.lsp',
        'swap': {
            'cdc:syssave': 'cal:syssave',
            'cdc:sysrestore': 'cal:sysrestore',
            'cdc:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': ['cdc:*sysold*'],
    },
    # CUSTBLOCK was written against the library from the start
    # (STANDARDS section 6): its ask helper, sysvar pair and ensure-layer
    # are the CALOFIN-LIB bodies under cbk:, so they all come back out
    # here.  Its dim-style pair stays local for CDCREATE's reason -- it
    # restores a style only when the style really moved, which
    # cal:dimstyrestore does not model.
    'CUSTBLOCK': {
        'src': 'lisp/custblock/CUSTBLOCK.lsp',
        'swap': {
            'cbk:askdist': 'cal:askdist',
            'cbk:askkw': 'cal:askkw',
            'cbk:askyn': 'cal:askyn',
            'cbk:syssave': 'cal:syssave',
            'cbk:sysrestore': 'cal:sysrestore',
            'cbk:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': ['cbk:*sysold*'],
        # the Back sentinel travels with the ask helper, and every
        # question in the run tests for it by name
        'symbols': {'CBK-BACK': 'CAL-BACK'},
    },
    # ABCDEF and XYPLOT carry the same feet-inch parser, so the same two
    # generic helpers come out of both.  Mirrored rather than hand-copied
    # because the twins were drifting: the shared abcdef.lsp still had
    # abcdef:trim spelled out while lisp/ had moved on.
    'abcdef': {
        'src': 'lisp/abcdef/abcdef.lsp',
        'swap': {
            'abcdef:trim': 'cal:trim',
            'abcdef:pad': 'cal:pad',
            'abcdef:askkw': 'cal:askkw',
        },
        'drop_globals': [],
        # abcdef:askkw is cal:askkw to the character bar the sentinel it
        # returns, and it already takes the SHOWN bracket third, so the
        # call sites need no translating -- only the sentinel travels.
        'askkw_hidden': False,
        'symbols': {'AB-BACK': 'CAL-BACK'},
    },
    # CONSTELLATION was written against the library from the start
    # (STANDARDS section 6): its ask layer, sysvar pair, undo pair,
    # ensure-layer, vector set and text maker are the CALOFIN-LIB bodies
    # under cst:, checked byte-for-byte against them, so all of it comes
    # back out here and the twin is a rename and nothing else.  What
    # stays local is the solver, which is the tool.
    'CONSTELLATION': {
        'src': 'lisp/constellation/CONSTELLATION.lsp',
        'swap': {
            # the ink table: one body, and the library's is it
            'cst:ink': 'cal:ink',
            'cst:askkw': 'cal:askkw', 'cst:askyn': 'cal:askyn',
            'cst:askdist': 'cal:askdist',
            'cst:back-word-p': 'cal:back-word-p',
            'cst:trim': 'cal:trim', 'cst:pad': 'cal:pad',
            'cst:syssave': 'cal:syssave',
            'cst:sysrestore': 'cal:sysrestore',
            'cst:error-cancel-p': 'cal:error-cancel-p',
            'cst:undobegin': 'cal:undobegin',
            'cst:undoend': 'cal:undoend',
            'cst:ensure-layer': 'cal:ensure-layer',
            'cst:text': 'cal:text',
            'cst:2d': 'cal:2d', 'cst:v-': 'cal:v-', 'cst:v+': 'cal:v+',
            'cst:v*': 'cal:v*', 'cst:dot': 'cal:dot',
            'cst:mid': 'cal:mid', 'cst:vlen': 'cal:vlen',
            'cst:d2': 'cal:d2', 'cst:unit': 'cal:unit',
            'cst:angnorm': 'cal:angnorm',
            'cst:signed-dang': 'cal:signed-dang',
            'cst:tan': 'cal:tan',
            'cst:nthcdr': 'cal:nthcdr', 'cst:sublist': 'cal:sublist',
            'cst:circumcenter': 'cal:circumcenter',
        },
        'drop_globals': ['cst:*sysold*'],
        # cst:askkw already takes the SHOWN bracket third, like the
        # library's, and cst:syssave already takes its sysvar list
        'askkw_hidden': False,
        # ...but the Back sentinel travels with the ask helpers, and
        # every question in the chain tests for it by name
        'symbols': {'CST-BACK': 'CAL-BACK'},
    },
    # Written against the library from the start (STANDARDS section 4's
    # "a NEW tool starts there"), so the swap map is the whole of its
    # helper layer: the vector set, the two angle helpers, ensure-layer,
    # the ask trio and block-number.  What stays local is what the
    # library has no answer for -- the segment walk over the perimeter,
    # the mark record, the survey-point classifier (BPCALLOUT's and
    # ABFIND's, which are not in the library either) and pm:askpoint,
    # the pick-or-type prompt.  That prompt IS in the library now, as
    # cal:askpoint, lifted from here for ABHD and its family -- but the
    # library's takes the snap radius as an argument where pm:askpoint
    # reads pm:*snap* itself, so PERPMARK keeps its own copy until its
    # arity is moved in a pass of its own.
    'PERPMARK': {
        'src': 'lisp/perpmark/PERPMARK.lsp',
        'swap': {
            'pm:2d': 'cal:2d', 'pm:v-': 'cal:v-', 'pm:v+': 'cal:v+',
            'pm:v*': 'cal:v*', 'pm:dot': 'cal:dot', 'pm:perp': 'cal:perp',
            'pm:vlen': 'cal:vlen', 'pm:unit': 'cal:unit',
            'pm:angnorm': 'cal:angnorm', 'pm:tan': 'cal:tan',
            'pm:ensure-layer': 'cal:ensure-layer',
            'pm:block-number': 'cal:block-number',
            # the inside of a closed wall, and the measurement that
            # fights both its neighbours
            'pm:loop-area': 'cal:loop-area',
            'pm:inward-sign': 'cal:inward-sign',
            'pm:in-loop-p': 'cal:in-loop-p',
            'pm:spikes': 'cal:spikes',
            'pm:askkw': 'cal:askkw', 'pm:askyn': 'cal:askyn',
            'pm:syssave': 'cal:syssave',
            'pm:sysrestore': 'cal:sysrestore',
            'pm:undobegin': 'cal:undobegin',
            'pm:undoend': 'cal:undoend',
            # the length ruler: one block, held to the library by
            # tests/test_ruler_copies.py; the style builder stays local
            'pm:len-digit-p': 'cal:len-digit-p',
            'pm:len-num-p': 'cal:len-num-p',
            'pm:len-split': 'cal:len-split',
            'pm:len-token': 'cal:len-token',
            'pm:len-inches': 'cal:len-inches',
            'pm:parse-len': 'cal:parse-len',
            'pm:len-eighths': 'cal:len-eighths',
            'pm:spell-len': 'cal:spell-len',
            'pm:len-unread': 'cal:len-unread',
            'pm:ruler-tier': 'cal:ruler-tier',
            'pm:ruler-rows': 'cal:ruler-rows',
            'pm:ruler-val-lt': 'cal:ruler-val-lt',
            'pm:ruler-view': 'cal:ruler-view',
            'pm:ruler-dir': 'cal:ruler-dir',
            'pm:ruler-hgt': 'cal:ruler-hgt',
            'pm:ruler-tick': 'cal:ruler-tick',
            'pm:ruler-line': 'cal:ruler-line',
            'pm:ruler-ring': 'cal:ruler-ring',
            'pm:ruler-label': 'cal:ruler-label',
            'pm:draw-ruler': 'cal:draw-ruler',
            'pm:ruler-hit': 'cal:ruler-hit',
            'pm:ruler-new': 'cal:ruler-new',
            'pm:ruler-off': 'cal:ruler-off',
            'pm:ruler-show': 'cal:ruler-show',
            'pm:ask-len': 'cal:ask-len',
        },
        'drop_globals': ['pm:*sysold*'],
        # cal:syssave takes the sysvars as an argument where pm:syssave
        # baked them in, so the list travels with the call and
        # pm:sysvars stays behind to supply it
        'expand': {
            '(cal:syssave)': ['(cal:syssave (pm:sysvars))'],
            # cal:block-number takes the attribute tag as an argument
            # where pm:block-number read the knob itself
            '(cal:block-number en)': ['(cal:block-number en pm:*pt-tag*)'],
        },
        # pm:askkw already takes the SHOWN bracket third, like the
        # library's -- so no bracket translation is needed here
        'askkw_hidden': False,
        # ...but the two signal Back with different symbols, and every
        # caller tests for it, so the sentinel moves with the helper
        'symbols': {'PM-BACK': 'CAL-BACK'},
    },
    'XYPLOT': {
        'src': 'lisp/xyplot/XYPLOT.lsp',
        'swap': {
            'xyp:trim': 'cal:trim',
            'xyp:pad': 'cal:pad',
            'xyp:layer': 'cal:ensure-layer',
            'xyp:text': 'cal:text',
            'xyp:askkw': 'cal:askkw',
        },
        'drop_globals': [],
        # as in abcdef above: identical body, its own Back sentinel
        'askkw_hidden': False,
        'symbols': {'XY-BACK': 'CAL-BACK'},
    },
    'xftconv': {
        'src': 'lisp/xftconv/xftconv.lsp',
        'swap': {
            'xft:trim': 'cal:trim',
            'xft:ensure-layer': 'cal:ensure-layer',
            'xft:d2': 'cal:d2',
        },
        'drop_globals': [],
    },
    'FITABHD': {
        'src': 'lisp/fitabhd/FITABHD.lsp',
        'swap': {
            'fit:askkw': 'cal:askkw', 'fit:askyn': 'cal:askyn',
            'fit:asktreat': 'cal:asktreat',
            'fit:back-word': 'cal:back-word-p',
            # fit:sublist inlines cal:nthcdr's while-loop instead of
            # calling it; same walk, same result
            'fit:sublist': 'cal:sublist',
            'fit:syssave': 'cal:syssave',
            'fit:sysrestore': 'cal:sysrestore',
            'fit:ensure-layer': 'cal:ensure-layer',
            'fit:2d': 'cal:2d', 'fit:dist': 'cal:dist',
            'fit:v-': 'cal:v-', 'fit:v+': 'cal:v+', 'fit:v*': 'cal:v*',
            'fit:dot': 'cal:dot', 'fit:mid': 'cal:mid',
            'fit:perp': 'cal:perp', 'fit:angnorm': 'cal:angnorm',
            'fit:signed-dang': 'cal:signed-dang',
            'fit:dedupe': 'cal:dedupe', 'fit:tan': 'cal:tan',
            'fit:ceil': 'cal:ceil',
            'fit:block-number': 'cal:block-number',
            'fit:as-number': 'cal:as-number', 'fit:canon': 'cal:canon',
            'fit:cand-matches': 'cal:cand-matches',
            'fit:cand-nearest': 'cal:cand-nearest',
            'fit:askpoint': 'cal:askpoint',
        },
        'drop_globals': [],
        # fit:askkw already takes the SHOWN bracket third, like the
        # library's, and fit:syssave already takes its sysvar list
        'askkw_hidden': False,
        # ...but the Back sentinel travels with the ask helpers, and
        # every caller tests for it by name
        'symbols': {'FIT-BACK': 'CAL-BACK'},
    },
    # SMARTFILLET was written against the library from the start: its
    # lisp/ file carries copies of the CALOFIN-LIB helpers under sf:,
    # and every one of them comes straight back out here.  What stays
    # local is the linetype it draws previews with -- the library has no
    # ensure-ltype -- and the corner geometry, which is the tool.
    'SMARTFILLET': {
        'src': 'lisp/smartfillet/SMARTFILLET.lsp',
        'swap': {
            'sf:askkw': 'cal:askkw', 'sf:askyn': 'cal:askyn',
            'sf:syssave': 'cal:syssave',
            'sf:sysrestore': 'cal:sysrestore',
            'sf:ensure-layer': 'cal:ensure-layer',
            'sf:2d': 'cal:2d', 'sf:dist': 'cal:dist',
            'sf:v-': 'cal:v-', 'sf:v+': 'cal:v+', 'sf:v*': 'cal:v*',
            'sf:dot': 'cal:dot', 'sf:vlen': 'cal:vlen',
            'sf:unit': 'cal:unit', 'sf:angnorm': 'cal:angnorm',
            'sf:signed-dang': 'cal:signed-dang', 'sf:tan': 'cal:tan',
        },
        'drop_globals': ['sf:*sysold*'],
        # sf:askkw already takes the SHOWN bracket third, like the
        # library's, and sf:syssave already takes its sysvar list
        'askkw_hidden': False,
        # ...but the Back sentinel travels with the ask helpers
        'symbols': {'SF-BACK': 'CAL-BACK'},
    },
    # HONEFILLET is SMARTFILLET's spinoff and carries the same library
    # copies under hn:, so the same swap map applies word for word.  The
    # corner geometry it shares with SMARTFILLET is NOT in here and is
    # not going to be: two standalone files each have to load alone, so
    # each carries its own, and the library holds generic helpers rather
    # than one tool's fillet math.
    'HONEFILLET': {
        'src': 'lisp/honefillet/HONEFILLET.lsp',
        'swap': {
            'hn:askkw': 'cal:askkw', 'hn:askyn': 'cal:askyn',
            'hn:syssave': 'cal:syssave',
            'hn:sysrestore': 'cal:sysrestore',
            'hn:ensure-layer': 'cal:ensure-layer',
            'hn:2d': 'cal:2d', 'hn:dist': 'cal:dist',
            'hn:v-': 'cal:v-', 'hn:v+': 'cal:v+', 'hn:v*': 'cal:v*',
            'hn:dot': 'cal:dot', 'hn:vlen': 'cal:vlen',
            'hn:unit': 'cal:unit', 'hn:angnorm': 'cal:angnorm',
            'hn:signed-dang': 'cal:signed-dang', 'hn:tan': 'cal:tan',
        },
        'drop_globals': ['hn:*sysold*'],
        # hn:askkw already takes the SHOWN bracket third, like the
        # library's, and hn:syssave already takes its sysvar list
        'askkw_hidden': False,
        # ...but the Back sentinel travels with the ask helpers
        'symbols': {'HN-BACK': 'CAL-BACK'},
    },
    # ABCURCHECK was written against the library from the start
    # (STANDARDS section 6): its ask pair, sysvar pair and vector set
    # already carry the library's shapes, so the twin is a rename and
    # nothing else.  acc:circumcenter is NOT in here -- it is ABHD's
    # 2-element, looser-gated form, which the library deliberately does
    # not carry (see shared/README.md).
    'ABCURCHECK': {
        'src': 'lisp/abcurcheck/ABCURCHECK.lsp',
        'swap': {
            'acc:askkw': 'cal:askkw',
            'acc:syssave': 'cal:syssave',
            'acc:sysrestore': 'cal:sysrestore',
            'acc:ensure-layer': 'cal:ensure-layer',
            'acc:2d': 'cal:2d', 'acc:dist': 'cal:dist',
            'acc:v-': 'cal:v-', 'acc:v+': 'cal:v+', 'acc:v*': 'cal:v*',
            'acc:cross': 'cal:cross', 'acc:angnorm': 'cal:angnorm',
            'acc:signed-dang': 'cal:signed-dang',
            'acc:tan': 'cal:tan', 'acc:ceil': 'cal:ceil',
            'acc:pad': 'cal:pad',
        },
        'drop_globals': ['acc:*sysold*'],
        # acc:askkw already takes the SHOWN bracket third, like the
        # library's, and acc:syssave already takes its sysvar list
        'askkw_hidden': False,
        # ...but the Back sentinel travels with the ask helper, and
        # acc:run tests for it by name
        'symbols': {'ACC-BACK': 'CAL-BACK'},
    },
    # OLAUTO was written against the library from the start (STANDARDS
    # section 6): its ask helper, the sysvar and dim-style pairs,
    # ensure-layer and the vector set are the CALOFIN-LIB bodies under
    # ola:, so all of that comes back out here.  What stays local is the
    # tool: the arc-length walk, the phase search, the ICP polish and
    # the error profile.
    #
    # ola:circumcenter is NOT in here, for the same reason
    # acc:circumcenter is not: it is ABHD's 2-element form, and the
    # library's carries p1's Z through as a third ordinate, so on the
    # 2D points ola:arc-geom hands it the library would return
    # (x y nil) -- which the (angle ...) and (polar ...) right after it
    # cannot read.  tests/test_cal_parity.py is what says so.
    'OLAUTO': {
        'src': 'lisp/olauto/OLAUTO.lsp',
        'swap': {
            'ola:askkw': 'cal:askkw',
            'ola:syssave': 'cal:syssave',
            'ola:sysrestore': 'cal:sysrestore',
            'ola:dimstysave': 'cal:dimstysave',
            'ola:dimstyrestore': 'cal:dimstyrestore',
            'ola:ensure-layer': 'cal:ensure-layer',
            'ola:2d': 'cal:2d', 'ola:dist': 'cal:dist',
            'ola:v-': 'cal:v-', 'ola:v+': 'cal:v+', 'ola:v*': 'cal:v*',
            'ola:dot': 'cal:dot', 'ola:vlen': 'cal:vlen',
            'ola:unit': 'cal:unit', 'ola:angnorm': 'cal:angnorm',
            'ola:tan': 'cal:tan',
        },
        'drop_globals': ['ola:*sysold*', 'ola:*odstyle*'],
        # ola:askkw is the STANDARDS section 4 REFERENCE helper: it takes
        # the hidden-keyword list third and derives the bracket from the
        # keywords.  cal:askkw is the older shape and takes the bracket
        # there, so the call sites are translated rather than renamed.
        'askkw_hidden': True,
        # ...and the Back sentinel travels with the helper, because
        # ola:run tests for it by name.  Miss this and Back silently
        # stops working in the grouped build while every check passes.
        'symbols': {'OLA-BACK': 'CAL-BACK'},
    },
    # SQUAREUP is OLAUTO's neighbour and takes the same shape of helper
    # out of the library: the ask pair, the sysvar pair and the small
    # vector set.  What stays local is the tool -- reading a perimeter
    # into spans, folding collinear pieces into walls, the convex hull
    # behind the span, and the layers it borrows for the turn.
    'SQUAREUP': {
        'src': 'lisp/squareup/SQUAREUP.lsp',
        'swap': {
            'sq:askkw': 'cal:askkw',
            'sq:askyn': 'cal:askyn',
            'sq:syssave': 'cal:syssave',
            'sq:sysrestore': 'cal:sysrestore',
            'sq:2d': 'cal:2d', 'sq:dist': 'cal:dist',
            'sq:angnorm': 'cal:angnorm', 'sq:ang-diff': 'cal:ang-diff',
            'sq:tan': 'cal:tan',
        },
        'drop_globals': ['sq:*sysold*'],
        # sq:askkw is the STANDARDS section 4 REFERENCE helper: it takes
        # the hidden-keyword list third and derives the bracket from the
        # keywords.  cal:askkw is the older shape and takes the bracket
        # there, so the call sites are translated rather than renamed.
        'askkw_hidden': True,
    },
    # ABLOBF is LHD's OPEN half forked onto ABHD's survey classifier, so
    # it takes the same helpers from the library that LHD does -- the
    # vector set, the angle pair, ceil/nthcdr/sublist, dedupe, pad,
    # ensure-layer and the point-block reader.  What stays local is the
    # fitting itself, the open walk, and the two things that are ABLOBF
    # and not LHD: the survey-number reader and the end picker.
    'ABLOBF': {
        'src': 'lisp/ablobf/ABLOBF.lsp',
        'swap': {
            'abl:2d': 'cal:2d', 'abl:dist': 'cal:dist',
            'abl:sub': 'cal:v-', 'abl:add': 'cal:v+', 'abl:scl': 'cal:v*',
            'abl:dot': 'cal:dot', 'abl:mid': 'cal:mid',
            'abl:perp': 'cal:perp', 'abl:tan': 'cal:tan',
            'abl:ceil': 'cal:ceil', 'abl:nthcdr': 'cal:nthcdr',
            'abl:sublist': 'cal:sublist', 'abl:norm-ang': 'cal:angnorm',
            'abl:signed-dang': 'cal:signed-dang',
            'abl:dedupe': 'cal:dedupe',
            'abl:block-number': 'cal:block-number',
            'abl:ensure-layer': 'cal:ensure-layer', 'abl:pad': 'cal:pad',
            'abl:as-number': 'cal:as-number', 'abl:canon': 'cal:canon',
            'abl:cand-matches': 'cal:cand-matches',
            'abl:cand-nearest': 'cal:cand-nearest',
            'abl:askpoint': 'cal:askpoint',
        },
        'drop_globals': [],
        'expand': {
            '(cal:block-number en)':
                ['(cal:block-number en *ABL-PT-TAG*)'],
            '(cal:dedupe pts)':
                ['(cal:dedupe pts *ABL-EXACT-EPS*)'],
        },
        'symbols': {'ABL-BACK': 'CAL-BACK'},
    },
    # LOBF was written against the library from the start (STANDARDS
    # section 6): its vector set, the sysvar pair, ensure-layer, pad,
    # dedupe and the point-block reader are all CALOFIN-LIB bodies under
    # lobf:, so every one of them comes back out here.  What stays local
    # is the fitting itself -- the three fits, the gift-wrapped hull they
    # need, the candidate record and the outlier rule -- which is what
    # the tool IS, plus lobf:label and lobf:line, because cal:text takes
    # no colour and the preview turns on drawing each candidate in its
    # own one.
    'LOBF': {
        'src': 'lisp/lobf/LOBF.lsp',
        'swap': {
            # the ink table: one body, and the library's is it
            'lobf:ink': 'cal:ink',
            'lobf:2d': 'cal:2d', 'lobf:dist': 'cal:dist',
            'lobf:v-': 'cal:v-', 'lobf:v+': 'cal:v+', 'lobf:v*': 'cal:v*',
            'lobf:dot': 'cal:dot', 'lobf:perp': 'cal:perp',
            'lobf:vlen': 'cal:vlen', 'lobf:cross': 'cal:cross',
            'lobf:unit': 'cal:unit', 'lobf:pad': 'cal:pad',
            'lobf:dedupe': 'cal:dedupe',
            'lobf:syssave': 'cal:syssave',
            'lobf:sysrestore': 'cal:sysrestore',
            'lobf:ensure-layer': 'cal:ensure-layer',
            'lobf:block-number': 'cal:block-number',
        },
        # lobf:syssave already takes its sysvar list, like the library's,
        # so there is nothing to expand -- but the snapshot global goes
        # with it, and only the two dropped helpers ever read it
        'drop_globals': ['lobf:*sysold*'],
    },
    # SPACOVCREATE was written against the library from the start: the
    # vector set, the string pair, the sysvar pair and the layer maker
    # are CALOFIN-LIB bodies under its own prefix, so all of them come
    # back out here.  What stays local is scv:unit (the library's
    # returns NIL on a zero vector, and every caller here multiplies the
    # result), scv:ceilv (the library's has no epsilon, and a piece
    # count of 2.0000000001 must not round to 3) and scv:right, which
    # the library has no half of -- cal:perp is the LEFT turn only.
    'SPACOVCREATE': {
        'src': 'lisp/spacovcreate/SPACOVCREATE.lsp',
        'swap': {
            'scv:2d': 'cal:2d',
            'scv:v+': 'cal:v+', 'scv:v-': 'cal:v-', 'scv:v*': 'cal:v*',
            'scv:dot': 'cal:dot', 'scv:cross': 'cal:cross',
            'scv:vlen': 'cal:vlen', 'scv:mid': 'cal:mid',
            'scv:left': 'cal:perp',
            'scv:trim': 'cal:trim', 'scv:plural': 'cal:plural',
            'scv:syssave': 'cal:syssave',
            'scv:sysrestore': 'cal:sysrestore',
            'scv:osup': 'cal:osup', 'scv:osdown': 'cal:osdown',
            'scv:ensure-layer': 'cal:ensure-layer',
        },
        # the snapshot global goes with the sysvar pair, and only those
        # two and cal:osup ever read it
        'drop_globals': ['scv:*sysold*'],
    },
    # ABPCHECK was forked from ABHD and written against the library from
    # the start: everything generic in it -- the vector set, the ask-free
    # helpers, ensure-layer, mtext, the point-block reader -- is a
    # CALOFIN-LIB body under its own prefix, so all of it comes back out
    # here.  What stays local is the segment math it forked (abp:seg-dist
    # and its 2-element abp:circumcenter, which the library's 3-element
    # form would break) and the report.
    'ABPCHECK': {
        'src': 'lisp/abpcheck/ABPCHECK.lsp',
        'swap': {
            'abp:2d': 'cal:2d', 'abp:dist': 'cal:dist',
            'abp:v-': 'cal:v-', 'abp:v+': 'cal:v+', 'abp:v*': 'cal:v*',
            'abp:dot': 'cal:dot', 'abp:mid': 'cal:mid',
            'abp:perp': 'cal:perp', 'abp:angnorm': 'cal:angnorm',
            'abp:tan': 'cal:tan', 'abp:dedupe': 'cal:dedupe',
            'abp:pad': 'cal:pad', 'abp:zeropad2': 'cal:zeropad2',
            'abp:datestr': 'cal:datestr',
            'abp:syssave': 'cal:syssave',
            'abp:sysrestore': 'cal:sysrestore',
            'abp:ensure-layer': 'cal:ensure-layer',
            'abp:mtext': 'cal:mtext',
            'abp:block-number': 'cal:block-number',
        },
        # abp:syssave already takes its sysvar list, like the library's,
        # so there is nothing to expand -- but the snapshot global goes
        # with it, and only the two dropped helpers ever read it
        'drop_globals': ['abp:*sysold*'],
    },
    # POINTRENAMER was written against the library from the start
    # (STANDARDS section 6): its ask pair, sysvar pair, vector set and
    # point-block reader are CALOFIN-LIB bodies under ptr:, so they all
    # come back out here.  What stays local is the walking-order math
    # the tool IS -- station-along-a-segment, the winding test, the
    # order-preserving sort -- plus its 2-element ptr:circumcenter,
    # which the library's 3-element form would break, and the
    # write-side ptr:attr-target, whose 66-flag guard the read-side
    # library helper deliberately does not carry.
    'POINTRENAMER': {
        'src': 'lisp/pointrenamer/POINTRENAMER.lsp',
        'swap': {
            'ptr:askkw': 'cal:askkw', 'ptr:askyn': 'cal:askyn',
            'ptr:syssave': 'cal:syssave',
            'ptr:sysrestore': 'cal:sysrestore',
            'ptr:2d': 'cal:2d', 'ptr:dist': 'cal:dist',
            'ptr:v-': 'cal:v-', 'ptr:v+': 'cal:v+', 'ptr:v*': 'cal:v*',
            'ptr:dot': 'cal:dot', 'ptr:mid': 'cal:mid',
            'ptr:perp': 'cal:perp', 'ptr:angnorm': 'cal:angnorm',
            'ptr:tan': 'cal:tan', 'ptr:pad': 'cal:pad',
            'ptr:block-number': 'cal:block-number',
        },
        # the snapshot global travels with syssave/sysrestore, and only
        # the two dropped helpers ever read it
        'drop_globals': ['ptr:*sysold*'],
        # ptr:askkw already takes the SHOWN bracket third, like the
        # library's, and ptr:syssave already takes its sysvar list
        'askkw_hidden': False,
        # ...but the Back sentinel travels with the ask helpers, and
        # every question in the chain tests for it by name
        'symbols': {'PTR-BACK': 'CAL-BACK'},
    },
    'SPACHECK': {
        'src': 'lisp/spacheck/SPACHECK.lsp',
        'swap': {
            'spachk:trim': 'cal:trim',
            'spachk:datestr': 'cal:datestr',
            'spachk:mtext': 'cal:mtext',
            'spachk:bbox': 'cal:bbox-ent',
            'spachk:ensure-layer': 'cal:ensure-layer',
            'spachk:askkw': 'cal:askkw',
            'spachk:syssave': 'cal:syssave',
            'spachk:sysrestore': 'cal:sysrestore',
        },
        'drop_globals': [],
        # spachk:askkw takes a HIDDEN keyword list third and derives the
        # bracket itself, so its call sites need translating
        'askkw_hidden': True,
        # No OSMODE: SPACHECK changes no snap of its own, and a sysvar
        # list is a promise to write the value back -- it would put this
        # run's opening snapshot over any snap the drafter ticked on
        # during the item-by-item walk.  Kept in step with the table in
        # lisp/spacheck/SPACHECK.lsp by hand, which is why it is typed
        # twice and why check_osnap.py reads both tiers.
        'expand': {
            '(cal:syssave)':
                ['(cal:syssave \'("CMDECHO" "CLAYER"))'],
        },
    },
    # POOL is the largest file in the tree and its twin was hand-mirrored
    # until the form-answer work made that a second pass -- exactly the
    # trigger CLAUDE.md names for moving a tool in here.
    'POOL': {
        'src': 'lisp/pool/POOL.LSP',
        'swap': {
            # the ink table: one body, and the library's is it
            'pool:ink': 'cal:ink',
            'pool:v+': 'cal:v+', 'pool:v-': 'cal:v-', 'pool:v*': 'cal:v*',
            'pool:dot': 'cal:dot', 'pool:perp': 'cal:perp',
            'pool:mid': 'cal:mid', 'pool:npos': 'cal:angnorm',
            'pool:osup': 'cal:osup', 'pool:osdown': 'cal:osdown',
            'pool:syssave': 'cal:syssave',
            'pool:sysrestore': 'cal:sysrestore',
            'pool:askkw': 'cal:askkw', 'pool:askyn': 'cal:askyn',
            'pool:asktreat': 'cal:asktreat',
            'pool:undobegin': 'cal:undobegin',
            'pool:undoend': 'cal:undoend',
        },
        'drop_globals': ['pool:*sysold*'],
        # pool:askkw already takes the SHOWN bracket third, like the
        # library's, so no bracket translation is needed
        'askkw_hidden': False,
        # the Back sentinel travels with the ask helpers, and the sysvar
        # snapshot global travels with syssave/sysrestore: drop_globals
        # removes its declaration, so every remaining READ of it has to
        # point at the library's own.  Miss this and pool:*ftin* reads an
        # unset global, so the grouped build quietly stops recognising
        # feet-inch drawings.
        'symbols': {'POOL-BACK': 'CAL-BACK',
                    'pool:*sysold*': 'cal:*sysold*'},
        # POOL also saves LUNITS -- it switches the drawing to
        # architectural units for the run and must put the user's back
        'expand': {
            '(cal:syssave)':
                ['(cal:syssave \'("OSMODE" "LUNITS" "CMDECHO" "CLAYER"))'],
        },
    },
    # POOLSIDE was written against the library from the start: the whole
    # of its ask layer, its vector helpers and its ensure-layer are
    # CALOFIN-LIB bodies carried under psd:, so they all come back out
    # here.  What stays local is the section itself -- the three bottom
    # tables, the chain resolver and the drawing.
    'POOLSIDE': {
        'src': 'lisp/poolside/POOLSIDE.lsp',
        'swap': {
            # the ink table: one body, and the library's is it
            'psd:ink': 'cal:ink',
            'psd:2d': 'cal:2d', 'psd:v+': 'cal:v+', 'psd:v*': 'cal:v*',
            'psd:mid': 'cal:mid',
            'psd:askkw': 'cal:askkw', 'psd:askyn': 'cal:askyn',
            'psd:osup': 'cal:osup', 'psd:osdown': 'cal:osdown',
            'psd:syssave': 'cal:syssave',
            'psd:sysrestore': 'cal:sysrestore',
            'psd:ensure-layer': 'cal:ensure-layer',
            'psd:undobegin': 'cal:undobegin',
            'psd:undoend': 'cal:undoend',
        },
        'drop_globals': ['psd:*sysold*'],
        # psd:askkw already takes the SHOWN bracket third, like the
        # library's, so no bracket translation is needed
        'askkw_hidden': False,
        # the Back sentinel travels with the ask helpers, and the sysvar
        # snapshot global travels with syssave/sysrestore
        'symbols': {'PSD-BACK': 'CAL-BACK',
                    'psd:*sysold*': 'cal:*sysold*'},
        # POOLSIDE reads architectural units for the run, like POOL, and
        # must put the user's back
        'expand': {
            '(cal:syssave)':
                ['(cal:syssave \'("OSMODE" "LUNITS" "CMDECHO" "CLAYER"))'],
        },
    },
    # LINGUTTER is new work, so it was written against the library from
    # the start: its lisp/ copy embeds the helpers and its twin calls
    # cal: for them.  Generated from day one rather than hand-copied --
    # CLAUDE.md's "if you find yourself doing that twice" is a rule
    # easier to keep than to catch up with.
    'LINGUTTER': {
        'src': 'lisp/lingutter/LINGUTTER.lsp',
        'swap': {
            'lg:askkw': 'cal:askkw', 'lg:askyn': 'cal:askyn',
            'lg:syssave': 'cal:syssave',
            'lg:sysrestore': 'cal:sysrestore',
            'lg:ensure-layer': 'cal:ensure-layer',
            'lg:2d': 'cal:2d', 'lg:v+': 'cal:v+', 'lg:v-': 'cal:v-',
            'lg:v*': 'cal:v*', 'lg:dot': 'cal:dot',
            'lg:angnorm': 'cal:angnorm',
        },
        # the snapshot global travels with syssave/sysrestore
        'drop_globals': ['lg:*sysold*'],
        # pp:askkw takes a HIDDEN keyword list third and derives the
        # bracket itself, the way STANDARDS.md section 4 writes it, so
        # any call site left after the swap needs translating.  Today
        # the only one lives inside pp:askyn, which the swap takes with
        # it -- this is here for the next prompt LINGUTTER grows.
        'askkw_hidden': True,
        # the Back sentinel travels with the ask helpers; nothing tests
        # for it yet, and the day something does it must be the
        # library's symbol, not this file's
        'symbols': {'LG-BACK': 'CAL-BACK'},
    },
    # The chart form is like the panel: it draws its own picture and
    # asks nothing through the library, so its twin is the file plus the
    # shared banner.  Listed so it can never drift.
    'LAZFORM': {
        'src': 'lisp/lazform/LAZFORM.lsp',
        # THE CHART-FORM KIT.  All three forms draw into a DCL image
        # tile, which takes line segments and nothing else, and all
        # three carried a byte-identical copy of the machinery for it.
        # The library has it now; these are the swaps, and the map is
        # also the written statement that the copies are the same code
        # -- let one drift and --check fails on the next regeneration.
        # Verified identical modulo the namespace before it was
        # written; lzX:px, lzX:py and lzX:pline are NOT here, because
        # LAZSPA and LAZSTEP clip to a band where LAZFORM draws whole.
        'swap': {
            # the ink table: one body, and the library's is it
            'lzf:ink': 'cal:ink',
            'lzf:glyph': 'cal:imgglyph',
            'lzf:text': 'cal:imgtext',
            'lzf:textw': 'cal:imgtextw',
            'lzf:texth': 'cal:imgtexth',
            'lzf:plinepx': 'cal:imgpline',
            'lzf:flatten': 'cal:imgflatten',
            'lzf:arcpts': 'cal:imgarcpts',
            'lzf:trim': 'cal:trim',
            'lzf:answer': 'cal:formanswer',
            'lzf:plural': 'cal:plural',
            'lzf:join': 'cal:andjoin',
            # the key=value record a recalled sheet is stored as
            'lzf:kvsplit': 'cal:kvsplit',
            'lzf:kvhas': 'cal:kvhas',
            'lzf:kvpack': 'cal:kvpack',
            'lzf:kvunpack': 'cal:kvunpack',
        },
        # the font, its metrics and the tile palette are constants, so
        # they move as globals: dropped here, renamed at every mention
        # by 'symbols' below (a bare global is never "(name", so the
        # swap map's call-site rewrite would not see it)
        'drop_globals': ['lzf:*font*', 'lzf:*font-w*',
                         'lzf:*font-h*', 'lzf:*font-adv*',
                         'lzf:*col-line*', 'lzf:*col-back*',
                         'lzf:*col-dim*', 'lzf:*col-val*',
                         'lzf:*col-hi*', 'lzf:*col-miss*'],
        'symbols': {
            # the prose names it too, and prose that names a helper the
            # twin does not define is the drift this file exists to stop
            'lzf:answer': 'cal:formanswer',
            'lzf:*font-adv*': 'cal:*imgfont-adv*',
            'lzf:*font-w*': 'cal:*imgfont-w*',
            'lzf:*font-h*': 'cal:*imgfont-h*',
            'lzf:*font*': 'cal:*imgfont*',
            'lzf:*col-line*': 'cal:*imgcol-line*',
            'lzf:*col-back*': 'cal:*imgcol-back*',
            'lzf:*col-dim*': 'cal:*imgcol-dim*',
            'lzf:*col-val*': 'cal:*imgcol-val*',
            'lzf:*col-hi*': 'cal:*imgcol-hi*',
            'lzf:*col-miss*': 'cal:*imgcol-miss*',
        },
        # the section header survives the drop -- top_span stops at a
        # ;;; block -- so the prose under it would be left explaining a
        # table the twin no longer carries
        'replace': [(FONT_PROSE, FONT_PROSE_SHARED)],
    },
    # The launcher panel uses no library helpers at all -- it draws
    # nothing and asks nothing -- so its twin is the file plus the
    # shared banner.  Listed anyway so the twin can never drift.
    'LAZDIAG': {
        'src': 'lisp/lazdiag/LAZDIAG.lsp',
        'swap': {
            'lzd:pad2': 'cal:zeropad2',
            'lzd:datestr': 'cal:datestr',
            'lzd:ensure-layer': 'cal:ensure-layer',
        },
        # lzd:cancel-p deliberately does NOT swap to cal:error-cancel-p.
        # The two differ by one guard -- lzd:cancel-p checks that the
        # message is a string before handing it to strcase -- and that
        # guard is the point: it runs in lzd:report's cond, which is
        # OUTSIDE the vl-catch-all-apply the rest of the reporter sits
        # in, so a throw there would be a throw inside *error* with
        # nowhere to go.  Not behaviour-identical, so not swapped.
        'drop_globals': [],
    },

    'LAZPANEL': {
        'src': 'lisp/lazpanel/LAZPANEL.lsp',
        'swap': {
            # the interface-theme probe: the library's is this body
            'lzp:ui': 'cal:ui',},
        'drop_globals': [],
    },
    # The spa chart and the step form are LAZFORM's shape applied to
    # SPA and to the three step routines: they draw their own pictures
    # and ask nothing through the library, so each twin is the file
    # plus the shared banner.  Listed for the same reason LAZFORM is --
    # a twin nobody generates is a twin that drifts by hand.
    'LAZSPA': {
        'src': 'lisp/lazspa/LAZSPA.lsp',
        # THE CHART-FORM KIT.  All three forms draw into a DCL image
        # tile, which takes line segments and nothing else, and all
        # three carried a byte-identical copy of the machinery for it.
        # The library has it now; these are the swaps, and the map is
        # also the written statement that the copies are the same code
        # -- let one drift and --check fails on the next regeneration.
        # Verified identical modulo the namespace before it was
        # written; lzX:px, lzX:py and lzX:pline are NOT here, because
        # LAZSPA and LAZSTEP clip to a band where LAZFORM draws whole.
        'swap': {
            # the ink table: one body, and the library's is it
            'lzs:ink': 'cal:ink',
            'lzs:glyph': 'cal:imgglyph',
            'lzs:text': 'cal:imgtext',
            'lzs:textw': 'cal:imgtextw',
            'lzs:texth': 'cal:imgtexth',
            'lzs:plinepx': 'cal:imgpline',
            'lzs:flatten': 'cal:imgflatten',
            'lzs:arcpts': 'cal:imgarcpts',
            'lzs:trim': 'cal:trim',
            'lzs:answer': 'cal:formanswer',
            'lzs:plural': 'cal:plural',
            'lzs:join': 'cal:andjoin',
            # the key=value record a recalled sheet is stored as
            'lzs:kvsplit': 'cal:kvsplit',
            'lzs:kvhas': 'cal:kvhas',
            'lzs:kvpack': 'cal:kvpack',
            'lzs:kvunpack': 'cal:kvunpack',
        },
        # the font, its metrics and the tile palette are constants, so
        # they move as globals: dropped here, renamed at every mention
        # by 'symbols' below (a bare global is never "(name", so the
        # swap map's call-site rewrite would not see it)
        'drop_globals': ['lzs:*font*', 'lzs:*font-w*',
                         'lzs:*font-h*', 'lzs:*font-adv*',
                         'lzs:*col-line*', 'lzs:*col-back*',
                         'lzs:*col-dim*', 'lzs:*col-val*',
                         'lzs:*col-hi*'],
        'symbols': {
            # the prose names it too, and prose that names a helper the
            # twin does not define is the drift this file exists to stop
            'lzs:answer': 'cal:formanswer',
            'lzs:*font-adv*': 'cal:*imgfont-adv*',
            'lzs:*font-w*': 'cal:*imgfont-w*',
            'lzs:*font-h*': 'cal:*imgfont-h*',
            'lzs:*font*': 'cal:*imgfont*',
            'lzs:*col-line*': 'cal:*imgcol-line*',
            'lzs:*col-back*': 'cal:*imgcol-back*',
            'lzs:*col-dim*': 'cal:*imgcol-dim*',
            'lzs:*col-val*': 'cal:*imgcol-val*',
            'lzs:*col-hi*': 'cal:*imgcol-hi*',
        },
        # the section header survives the drop -- top_span stops at a
        # ;;; block -- so the prose under it would be left explaining a
        # table the twin no longer carries
        'replace': [(FONT_PROSE, FONT_PROSE_SHARED)],
    },
    'LAZSIDE': {
        'src': 'lisp/lazside/LAZSIDE.lsp',
        # The fourth chart form, and the same kit: it draws into a DCL
        # image tile, which takes line segments and nothing else, so it
        # carries the same copy of the machinery the other three did.
        # The library has it; these are the swaps, and the map is also
        # the written statement that the copies are the same code --
        # let one drift and --check fails on the next regeneration.
        'swap': {
            # the ink table: one body, and the library's is it
            'lzv:ink': 'cal:ink',
            'lzv:glyph': 'cal:imgglyph',
            'lzv:text': 'cal:imgtext',
            'lzv:textw': 'cal:imgtextw',
            'lzv:texth': 'cal:imgtexth',
            'lzv:plinepx': 'cal:imgpline',
            'lzv:flatten': 'cal:imgflatten',
            'lzv:arcpts': 'cal:imgarcpts',
            'lzv:trim': 'cal:trim',
            'lzv:answer': 'cal:formanswer',
            'lzv:plural': 'cal:plural',
            'lzv:join': 'cal:andjoin',
            # the key=value record a recalled sheet is stored as
            'lzv:kvsplit': 'cal:kvsplit',
            'lzv:kvhas': 'cal:kvhas',
            'lzv:kvpack': 'cal:kvpack',
            'lzv:kvunpack': 'cal:kvunpack',
        },
        # the font, its metrics and the tile palette are constants, so
        # they move as globals: dropped here, renamed at every mention
        # by 'symbols' below (a bare global is never "(name", so the
        # swap map's call-site rewrite would not see it)
        'drop_globals': ['lzv:*font*', 'lzv:*font-w*',
                         'lzv:*font-h*', 'lzv:*font-adv*',
                         'lzv:*col-line*', 'lzv:*col-back*',
                         'lzv:*col-dim*', 'lzv:*col-val*',
                         'lzv:*col-hi*'],
        'symbols': {
            # the prose names it too, and prose that names a helper the
            # twin does not define is the drift this file exists to stop
            'lzv:answer': 'cal:formanswer',
            'lzv:*font-adv*': 'cal:*imgfont-adv*',
            'lzv:*font-w*': 'cal:*imgfont-w*',
            'lzv:*font-h*': 'cal:*imgfont-h*',
            'lzv:*font*': 'cal:*imgfont*',
            'lzv:*col-line*': 'cal:*imgcol-line*',
            'lzv:*col-back*': 'cal:*imgcol-back*',
            'lzv:*col-dim*': 'cal:*imgcol-dim*',
            'lzv:*col-val*': 'cal:*imgcol-val*',
            'lzv:*col-hi*': 'cal:*imgcol-hi*',
        },
        # the section header survives the drop -- top_span stops at a
        # ;;; block -- so the prose under it would be left explaining a
        # table the twin no longer carries
        'replace': [(FONT_PROSE, FONT_PROSE_SHARED)],
    },
    'LAZSTEP': {
        'src': 'lisp/lazstep/LAZSTEP.lsp',
        # THE CHART-FORM KIT.  All three forms draw into a DCL image
        # tile, which takes line segments and nothing else, and all
        # three carried a byte-identical copy of the machinery for it.
        # The library has it now; these are the swaps, and the map is
        # also the written statement that the copies are the same code
        # -- let one drift and --check fails on the next regeneration.
        # Verified identical modulo the namespace before it was
        # written; lzX:px, lzX:py and lzX:pline are NOT here, because
        # LAZSPA and LAZSTEP clip to a band where LAZFORM draws whole.
        'swap': {
            # the ink table: one body, and the library's is it
            'lzt:ink': 'cal:ink',
            'lzt:glyph': 'cal:imgglyph',
            'lzt:text': 'cal:imgtext',
            'lzt:textw': 'cal:imgtextw',
            'lzt:texth': 'cal:imgtexth',
            'lzt:plinepx': 'cal:imgpline',
            'lzt:flatten': 'cal:imgflatten',
            'lzt:arcpts': 'cal:imgarcpts',
            'lzt:trim': 'cal:trim',
            'lzt:answer': 'cal:formanswer',
            'lzt:plural': 'cal:plural',
            'lzt:join': 'cal:andjoin',
            # the key=value record a recalled sheet is stored as
            'lzt:kvsplit': 'cal:kvsplit',
            'lzt:kvhas': 'cal:kvhas',
            'lzt:kvpack': 'cal:kvpack',
            'lzt:kvunpack': 'cal:kvunpack',
        },
        # the font, its metrics and the tile palette are constants, so
        # they move as globals: dropped here, renamed at every mention
        # by 'symbols' below (a bare global is never "(name", so the
        # swap map's call-site rewrite would not see it)
        'drop_globals': ['lzt:*font*', 'lzt:*font-w*',
                         'lzt:*font-h*', 'lzt:*font-adv*',
                         'lzt:*col-line*', 'lzt:*col-back*',
                         'lzt:*col-dim*', 'lzt:*col-val*',
                         'lzt:*col-hi*'],
        'symbols': {
            # the prose names it too, and prose that names a helper the
            # twin does not define is the drift this file exists to stop
            'lzt:answer': 'cal:formanswer',
            'lzt:*font-adv*': 'cal:*imgfont-adv*',
            'lzt:*font-w*': 'cal:*imgfont-w*',
            'lzt:*font-h*': 'cal:*imgfont-h*',
            'lzt:*font*': 'cal:*imgfont*',
            'lzt:*col-line*': 'cal:*imgcol-line*',
            'lzt:*col-back*': 'cal:*imgcol-back*',
            'lzt:*col-dim*': 'cal:*imgcol-dim*',
            'lzt:*col-val*': 'cal:*imgcol-val*',
            'lzt:*col-hi*': 'cal:*imgcol-hi*',
        },
        # the section header survives the drop -- top_span stops at a
        # ;;; block -- so the prose under it would be left explaining a
        # table the twin no longer carries
        'replace': [(FONT_PROSE, FONT_PROSE_SHARED)],
    },

    # ---- adopted 2026-08-27 from the hand-mirrored set (the derivation
    # verified each spec's generate() output against the twin then on
    # disk; the remaining diffs were the legacy banner form and
    # comment-only residues, normalised by the first regeneration).
    # ---- adopted from the hand-mirrored set.  The check family's three
    # twins were kept by hand because their grouped-build adaptations --
    # the cal:mtext delegating wrapper and the ask-yn default moving
    # from the prompt into an argument -- are a body rewrite and an
    # arity change, neither of which a swap map can say.  They are
    # `rewrite` and `collapse` now, and the twins are generated.
    # (Derivation: generate() reproduced each hand twin to the character
    # except the legacy banner placement, which the first regeneration
    # normalises.  ensure-layer keeps its accepted delta -- entmake vs
    # entmakex and the per-tool message prefix, see shared/README.md --
    # exactly as the hand twins already had it.)
    #
    # LISPLAB stays hand-mirrored, and NOT because a transform is
    # missing: its twin's only non-swap content is lesson prose naming
    # the library instead of itself.  Expressing that needs a third key
    # whose only user in the tree would be a file with one commit in
    # its history, held OMITTED out of the bundle, whose twin
    # test_lisplab.py already runs at both tiers -- so a drift there
    # fails make parity today.
    'covercheck': {
        'src': 'lisp/covercheck/covercheck.lsp',
        'swap': {
            # the ink table: one body, and the library's is it
            'cchk:ink': 'cal:ink',
            'cchk:inkoverride': 'cal:inkoverride',
            'cchk:ensure-layer': 'cal:ensure-layer',
            'cchk:bbox': 'cal:bbox-ent',
            'cchk:pad2': 'cal:zeropad2',
            'cchk:datestr': 'cal:datestr',
            'cchk:ask-yn-nav': 'cal:ask-yn-nav',
            'cchk:angnorm': 'cal:angnorm',
            'cchk:ang-diff': 'cal:ang-diff',
            'cchk:circumcenter': 'cal:circumcenter',
            'cchk:unit': 'cal:unitn',
            'cchk:proj-param': 'cal:proj-param',
            'cchk:axis-pt': 'cal:axis-pt',
            'cchk:pt-line-dist': 'cal:pt-line-dist',
            # the flat 2-D kit.  NOTE the two different unit
            # vectors: cchk:unit is the length-preserving one over all
            # components (cal:unitn), cchk:pv-unit is the flat 2-D one
            # (cal:unit).  Swapping these the wrong way round loads
            # fine and draws wrong.
            'cchk:pv-sub': 'cal:v-',
            'cchk:pv-add': 'cal:v+',
            'cchk:pv-scl': 'cal:v*',
            'cchk:pv-len': 'cal:vlen',
            'cchk:pv-unit': 'cal:unit',
            'cchk:pv-cross': 'cal:cross',
            'cchk:pv-dot': 'cal:dot',
            'cchk:pv-2d': 'cal:2d',
        },
        'drop_globals': [],
        # cchk:ask-yn and cchk:ask-ny are one library helper with the
        # default baked into the prompt instead of passed.  `expand`
        # cannot reach these: it matches literal call text and every
        # site carries a different multi-line (strcat ...) prompt.
        'collapse': {
            'cchk:ask-yn': ('cal:ask-yn', '"Yes"'),
            'cchk:ask-ny': ('cal:ask-yn', '"No"'),
        },
        # the one thing no swap can say: the grouped build wants a
        # DIFFERENT BODY, a thin wrapper that delegates to the library
        # and then tags what came back as this tool's report line
        'rewrite': {
            'cchk:mtext':
                '(defun cchk:mtext (ins height width text layer / e)\n'
                '  ;; entmake an MTEXT, splitting text into 250-char '
                'DXF chunks\n'
                '  (if (setq e (cal:mtext ins height width text layer))\n'
                '    (cchk:tag e "REPORT")))\n',
        },
    },
    'dimcheck': {
        'src': 'lisp/dimcheck/dimcheck.lsp',
        'swap': {
            # the ink table: one body, and the library's is it
            'dchk:ink': 'cal:ink',
            'dchk:inkoverride': 'cal:inkoverride',
            'dchk:ensure-layer': 'cal:ensure-layer',
            'dchk:bbox': 'cal:bbox-ent',
            'dchk:pad2': 'cal:zeropad2',
            'dchk:datestr': 'cal:datestr',
            'dchk:ask-yn-nav': 'cal:ask-yn-nav',
            'dchk:angnorm': 'cal:angnorm',
            'dchk:ang-diff': 'cal:ang-diff',
            'dchk:circumcenter': 'cal:circumcenter',
            'dchk:unit': 'cal:unitn',
            'dchk:proj-param': 'cal:proj-param',
            'dchk:axis-pt': 'cal:axis-pt',
            'dchk:pt-line-dist': 'cal:pt-line-dist',
        },
        'drop_globals': [],
        # dchk:ask-yn is cal:ask-yn with the default baked in rather
        # than passed; the collapse passes it.  There is no dchk:ask-ny
        # here -- covercheck is the only one of the three with both.
        'collapse': {
            'dchk:ask-yn': ('cal:ask-yn', '"Yes"'),
        },
        # the one thing no swap can say: the grouped build wants a
        # DIFFERENT BODY, a thin wrapper that delegates to the library
        # and then tags what came back as this tool's report line
        'rewrite': {
            'dchk:mtext':
                '(defun dchk:mtext (ins height width text layer / e)\n'
                '  ;; entmake an MTEXT, splitting text into 250-char '
                'DXF chunks\n'
                '  (if (setq e (cal:mtext ins height width text layer))\n'
                '    (dchk:tag e "REPORT")))\n',
        },
    },
    'linfincheck': {
        'src': 'lisp/linfincheck/linfincheck.lsp',
        'swap': {
            # the ink table: one body, and the library's is it
            'lfc:ink': 'cal:ink',
            'lfc:inkoverride': 'cal:inkoverride',
            'lfc:ensure-layer': 'cal:ensure-layer',
            'lfc:bbox': 'cal:bbox-ent',
            'lfc:pad2': 'cal:zeropad2',
            'lfc:datestr': 'cal:datestr',
            'lfc:ask-yn-nav': 'cal:ask-yn-nav',
            'lfc:angnorm': 'cal:angnorm',
            'lfc:ang-diff': 'cal:ang-diff',
            'lfc:circumcenter': 'cal:circumcenter',
            'lfc:unit': 'cal:unitn',
            'lfc:proj-param': 'cal:proj-param',
            'lfc:axis-pt': 'cal:axis-pt',
            'lfc:pt-line-dist': 'cal:pt-line-dist',
        },
        'drop_globals': [],
        # lfc:ask-yn is cal:ask-yn with the default baked in rather
        # than passed; the collapse passes it.  There is no lfc:ask-ny
        # here -- covercheck is the only one of the three with both.
        'collapse': {
            'lfc:ask-yn': ('cal:ask-yn', '"Yes"'),
        },
        # the one thing no swap can say: the grouped build wants a
        # DIFFERENT BODY, a thin wrapper that delegates to the library
        # and then tags what came back as this tool's report line
        'rewrite': {
            'lfc:mtext':
                '(defun lfc:mtext (ins height width text layer / e)\n'
                '  ;; entmake an MTEXT, splitting text into 250-char '
                'DXF chunks\n'
                '  (if (setq e (cal:mtext ins height width text layer))\n'
                '    (lfc:tag e "REPORT")))\n',
        },
    },

    # ABHD carries the whole 2D kit under pf: (sub/add/scl are the
    # library's v-/v+/v*), the list and format helpers, the layer
    # creator and the Back-word test.  cal:dedupe takes the epsilon as
    # an argument where pf:dedupe read *PF-EXACT-EPS* itself, so that
    # call grows the argument.  Regenerating also drops the
    # ';; ---- output helpers' rule the hand twin kept (residue R1).
    # [verified: matches except banner + listed residue vs the twin on disk]
    'abhd': {
        'src': 'lisp/abhd/abhd.lsp',
        'swap': {
            'pf:2d': 'cal:2d', 'pf:dist': 'cal:dist', 'pf:sub': 'cal:v-',
            'pf:add': 'cal:v+', 'pf:scl': 'cal:v*', 'pf:dot': 'cal:dot',
            'pf:mid': 'cal:mid', 'pf:perp': 'cal:perp', 'pf:tan': 'cal:tan',
            'pf:ceil': 'cal:ceil', 'pf:nthcdr': 'cal:nthcdr',
            'pf:sublist': 'cal:sublist', 'pf:norm-ang': 'cal:angnorm',
            'pf:signed-dang': 'cal:signed-dang', 'pf:dedupe': 'cal:dedupe',
            'pf:ensure-layer': 'cal:ensure-layer', 'pf:pad': 'cal:pad',
            'pf:back-word': 'cal:back-word-p', 'pf:unit': 'cal:unit',
            'pf:loop-area': 'cal:loop-area', 'pf:spikes': 'cal:spikes',
            # PERPMARK's survey-point naming, lifted into the library:
            # the spellings, the typed match, the click within a snap
            # radius and the one prompt that takes either
            'pf:as-number': 'cal:as-number', 'pf:canon': 'cal:canon',
            'pf:cand-matches': 'cal:cand-matches',
            'pf:cand-nearest': 'cal:cand-nearest',
            'pf:askpoint': 'cal:askpoint',
        },
        'drop_globals': [],
        'expand': {
            '(cal:dedupe pts)':
                ['(cal:dedupe pts *PF-EXACT-EPS*)'],
        },
        # the Back sentinel travels with cal:askpoint, and every
        # question in the run tests for it by name
        'symbols': {'PF-BACK': 'CAL-BACK'},
    },
    # CABHD is ABHD's perimeter half and carries the same kit under
    # cab:, minus the bottom-only pieces; same dedupe epsilon growth.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'CABHD': {
        'src': 'lisp/cabhd/CABHD.lsp',
        'swap': {
            'cab:2d': 'cal:2d', 'cab:dist': 'cal:dist', 'cab:sub': 'cal:v-',
            'cab:add': 'cal:v+', 'cab:scl': 'cal:v*', 'cab:dot': 'cal:dot',
            'cab:mid': 'cal:mid', 'cab:perp': 'cal:perp',
            'cab:tan': 'cal:tan', 'cab:ceil': 'cal:ceil',
            'cab:nthcdr': 'cal:nthcdr', 'cab:sublist': 'cal:sublist',
            'cab:norm-ang': 'cal:angnorm',
            'cab:signed-dang': 'cal:signed-dang', 'cab:dedupe': 'cal:dedupe',
            'cab:ensure-layer': 'cal:ensure-layer', 'cab:pad': 'cal:pad',
            'cab:as-number': 'cal:as-number', 'cab:canon': 'cal:canon',
            'cab:cand-matches': 'cal:cand-matches',
            'cab:cand-nearest': 'cal:cand-nearest',
            'cab:askpoint': 'cal:askpoint',
        },
        'drop_globals': [],
        'expand': {
            '(cal:dedupe pts)':
                ['(cal:dedupe pts *CAB-EXACT-EPS*)'],
        },
        'symbols': {'CAB-BACK': 'CAL-BACK'},
    },
    # ABHD's kit again under lh:, plus block-number -- the library's
    # takes the attribute tag as an argument where lh: read *LH-PT-TAG*
    # itself, so that call grows the argument like dedupe's epsilon.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'lhd': {
        'src': 'lisp/lhd/lhd.lsp',
        'swap': {
            'lh:2d': 'cal:2d', 'lh:dist': 'cal:dist', 'lh:sub': 'cal:v-',
            'lh:add': 'cal:v+', 'lh:scl': 'cal:v*', 'lh:dot': 'cal:dot',
            'lh:mid': 'cal:mid', 'lh:perp': 'cal:perp', 'lh:tan': 'cal:tan',
            'lh:ceil': 'cal:ceil', 'lh:nthcdr': 'cal:nthcdr',
            'lh:sublist': 'cal:sublist', 'lh:norm-ang': 'cal:angnorm',
            'lh:signed-dang': 'cal:signed-dang', 'lh:dedupe': 'cal:dedupe',
            'lh:block-number': 'cal:block-number',
            'lh:ensure-layer': 'cal:ensure-layer', 'lh:pad': 'cal:pad',
            'lh:as-number': 'cal:as-number', 'lh:canon': 'cal:canon',
            'lh:cand-matches': 'cal:cand-matches',
            'lh:cand-nearest': 'cal:cand-nearest',
            'lh:askpoint': 'cal:askpoint',
        },
        'drop_globals': [],
        'expand': {
            '(cal:block-number en)':
                ['(cal:block-number en *LH-PT-TAG*)'],
            '(cal:dedupe pts)':
                ['(cal:dedupe pts *LH-EXACT-EPS*)'],
        },
        'symbols': {'LH-BACK': 'CAL-BACK'},
    },
    # OASIS asks through askkw/askdist and swaps the sysvar, dimstyle,
    # osnap and layer helpers.  Its Back sentinel rides the SWAP map,
    # not symbols: the hand twin renamed only the quoted call sites and
    # kept the prose that explains OASIS-BACK, which a symbols rename
    # would rewrite.  The one comment pointing at oasis:askdist did
    # move, hence the symbols entry.  cal:syssave takes the sysvars as
    # an argument; unlike SPA nothing splits in two, because OASIS
    # calls its own dimstyle pair explicitly.  Regenerating also keeps
    # two ;;;-section headers the hand twin deleted (residue R2).
    # [verified: matches except banner + listed residue vs the twin on disk]
    # oasis:askkw and oasis:askdist are NOT library bodies any more: at
    # v8.1 each consults the answer store (oasis:fpull / oasis:fkw /
    # oasis:fdist-p) before it asks, so a filled-in oasis sheet is read.
    # Swapping them for the library's plain pair drops that lookup and
    # the grouped build silently ignores the sheet -- the stored answer
    # then reaches getkword raw.  They stay local; the rest still goes.
    'OASIS': {
        'src': 'lisp/oasis/OASIS.lsp',
        'swap': {
            # the ink table: one body, and the library's is it
            'oasis:ink': 'cal:ink',
            'oasis:v+': 'cal:v+', 'oasis:v*': 'cal:v*',
            'oasis:pad': 'cal:pad',
            'oasis:osup': 'cal:osup', 'oasis:osdown': 'cal:osdown',
            'oasis:dimstysave': 'cal:dimstysave',
            'oasis:dimstyrestore': 'cal:dimstyrestore',
            'oasis:ensure-layer': 'cal:ensure-layer',
            'oasis:angnorm': 'cal:angnorm', 'oasis:syssave': 'cal:syssave',
            'oasis:sysrestore': 'cal:sysrestore',
        },
        'drop_globals': ['oasis:*sysold*', 'oasis:*odstyle*'],
        'symbols': {},
        'expand': {
            '(cal:syssave)':
                ['(cal:syssave \'("OSMODE" "CMDECHO" "CLAYER"))'],
        },
    },
    # Ask pair, Back-word test, layer creator and the flat geometry
    # set.  The sentinel moves via symbols like SPA's -- the hand twin
    # renamed the ABF-BACK comment mentions too.  cal:block-number
    # takes the tag as an argument; abf:*pt-tag* stays and is passed.
    # Regenerating keeps a ;;;-block the hand twin deleted (R2).
    # [verified: matches except banner + listed residue vs the twin on disk]
    # VSCONV's one generic helper is the output-layer gate; everything
    # else in it (the unlock/relock pair, the BYLAYER forcing, the
    # layer-name lookups) is either DRONE's shape or this file's own,
    # and the library carries neither.
    'VSCONV': {
        'src': 'lisp/vsconv/VSCONV.lsp',
        'swap': {
            'vsconv:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': [],
    },
    'ABFIND': {
        'src': 'lisp/abfind/ABFIND.lsp',
        'swap': {
            # the ink table: one body, and the library's is it
            'abf:ink': 'cal:ink',
            'abf:askkw': 'cal:askkw', 'abf:askyn': 'cal:askyn',
            'abf:back-word-p': 'cal:back-word-p',
            'abf:ensure-layer': 'cal:ensure-layer',
            'abf:block-number': 'cal:block-number', 'abf:2d': 'cal:2d',
            'abf:dist': 'cal:dist', 'abf:angnorm': 'cal:angnorm',
            'abf:signed-dang': 'cal:signed-dang', 'abf:pad': 'cal:pad',
            'abf:askdist': 'cal:askdist', 'abf:askstr': 'cal:askstr',
            'abf:trim': 'cal:trim',
        },
        'drop_globals': [],
        'symbols': {
            'ABF-BACK': 'CAL-BACK',
        },
        'expand': {
            '(cal:block-number en)':
                ['(cal:block-number en abf:*pt-tag*)'],
        },
    },
    # The 2D vector kit under paddle--.  paddle--len is called only by
    # paddle--unit, so once both are dropped nothing calls it; its
    # library body is cal:vlen.  Regenerating drops the
    # ';; --- 2D vector helpers' rule the hand twin kept (R1).
    # [verified: matches except banner + listed residue vs the twin on disk]
    'PADDLE': {
        'src': 'lisp/paddle/PADDLE.lsp',
        'swap': {
            'paddle--sub': 'cal:v-', 'paddle--add': 'cal:v+',
            'paddle--scl': 'cal:v*', 'paddle--len': 'cal:vlen',
            'paddle--unit': 'cal:unit', 'paddle--cross': 'cal:cross',
            'paddle--dot': 'cal:dot', 'paddle--2d': 'cal:2d',
        },
        'drop_globals': [],
    },
    # MOHAMADDLE ports PADDLE's own 2D vector kit under its own prefix
    # (every lisp/ tool has to load alone), so the same eight names come
    # out here for the same reason.
    'MOHAMADDLE': {
        'src': 'lisp/mohamaddle/MOHAMADDLE.lsp',
        'swap': {
            'mohamaddle--sub': 'cal:v-', 'mohamaddle--add': 'cal:v+',
            'mohamaddle--scl': 'cal:v*', 'mohamaddle--len': 'cal:vlen',
            'mohamaddle--unit': 'cal:unit', 'mohamaddle--cross': 'cal:cross',
            'mohamaddle--dot': 'cal:dot', 'mohamaddle--2d': 'cal:2d',
        },
        'drop_globals': [],
    },
    # UPADOVER lays PADDLE's pads end to end along a named stretch of
    # wall, so it carries PADDLE's block kit AND PERPMARK's segment
    # walk -- and the same generic helpers come out here that come out
    # of both of them.  What does NOT come out is upad:askpoint: the
    # library's question is about a survey POINT and re-asks a click
    # that lands on nothing, where this one takes a place on the wall
    # as readily as a numbered shot.  Swapping it would quietly refuse
    # every end nobody happened to survey.
    'UPADOVER': {
        'src': 'lisp/upadover/UPADOVER.lsp',
        'swap': {
            'upad:2d': 'cal:2d', 'upad:v-': 'cal:v-', 'upad:v+': 'cal:v+',
            'upad:v*': 'cal:v*', 'upad:dot': 'cal:dot',
            'upad:vlen': 'cal:vlen', 'upad:unit': 'cal:unit',
            'upad:angnorm': 'cal:angnorm', 'upad:tan': 'cal:tan',
            'upad:ensure-layer': 'cal:ensure-layer',
            'upad:as-number': 'cal:as-number', 'upad:canon': 'cal:canon',
            'upad:matches': 'cal:cand-matches',
            'upad:syssave': 'cal:syssave',
            'upad:sysrestore': 'cal:sysrestore',
            'upad:undobegin': 'cal:undobegin',
            'upad:undoend': 'cal:undoend',
        },
        'drop_globals': ['upad:*sysold*'],
        # cal:syssave takes the sysvars as an argument where upad:syssave
        # baked them in, so the list travels with the call and
        # upad:sysvars stays behind to supply it
        'expand': {
            '(cal:syssave)': ['(cal:syssave (upad:sysvars))'],
        },
        # ...and these two read a knob the library takes as an argument
        'collapse': {
            'upad:nearest': ('cal:cand-nearest', 'upad:*snap*'),
            'upad:block-number': ('cal:block-number', 'upad:*pt-tag*'),
        },
    },
    # CORNERSTP's one generic helper is the layer gate.  REAL DRIFT in
    # the hand twin: it dropped cs-layerok but renamed only three of
    # the four call sites -- cs-dimv still calls cs-layerok, which
    # nothing in the grouped build defines, so dims onto *cs-dim-layer*
    # die in LAZPASS today.  This entry renames all four: regenerating
    # FIXES that bug (residue R3).
    # [verified: matches except banner + listed residue vs the twin on disk]
    'CORNERSTP': {
        'src': 'lisp/cornerstp/CORNERSTP.lsp',
        'swap': {
            'cs-layerok': 'cal:layer-usable-p',
            'cs-dot': 'cal:dot',
            # the length ruler: one block, held to the library by
            # tests/test_ruler_copies.py; the style builder stays local
            'cs-len-digit-p': 'cal:len-digit-p',
            'cs-len-num-p': 'cal:len-num-p',
            'cs-len-split': 'cal:len-split',
            'cs-len-token': 'cal:len-token',
            'cs-len-inches': 'cal:len-inches',
            'cs-parse-len': 'cal:parse-len',
            'cs-len-eighths': 'cal:len-eighths',
            'cs-spell-len': 'cal:spell-len',
            'cs-len-unread': 'cal:len-unread',
            'cs-ruler-tier': 'cal:ruler-tier',
            'cs-ruler-rows': 'cal:ruler-rows',
            'cs-ruler-val-lt': 'cal:ruler-val-lt',
            'cs-ruler-view': 'cal:ruler-view',
            'cs-ruler-dir': 'cal:ruler-dir',
            'cs-ruler-hgt': 'cal:ruler-hgt',
            'cs-ruler-tick': 'cal:ruler-tick',
            'cs-ruler-line': 'cal:ruler-line',
            'cs-ruler-ring': 'cal:ruler-ring',
            'cs-ruler-label': 'cal:ruler-label',
            'cs-draw-ruler': 'cal:draw-ruler',
            'cs-ruler-hit': 'cal:ruler-hit',
            'cs-ruler-new': 'cal:ruler-new',
            'cs-ruler-off': 'cal:ruler-off',
            'cs-ruler-show': 'cal:ruler-show',
            'cs-ask-len': 'cal:ask-len',
        },
        'drop_globals': [],
    },
    # Same story as CORNERSTP: hs-layerok comes out, and the hand twin
    # left the hs-dimv call site unrenamed -- an undefined function in
    # the grouped build that regenerating fixes (R3).
    # [verified: matches except banner + listed residue vs the twin on disk]
    'HEMISTEP': {
        'src': 'lisp/cornerstp/HEMISTEP.lsp',
        'swap': {
            'hs-layerok': 'cal:layer-usable-p',
            'hs-dot': 'cal:dot',
            'hs-cross': 'cal:cross',
            # the length ruler: one block, held to the library by
            # tests/test_ruler_copies.py; the style builder stays local
            'hs-len-digit-p': 'cal:len-digit-p',
            'hs-len-num-p': 'cal:len-num-p',
            'hs-len-split': 'cal:len-split',
            'hs-len-token': 'cal:len-token',
            'hs-len-inches': 'cal:len-inches',
            'hs-parse-len': 'cal:parse-len',
            'hs-len-eighths': 'cal:len-eighths',
            'hs-spell-len': 'cal:spell-len',
            'hs-len-unread': 'cal:len-unread',
            'hs-ruler-tier': 'cal:ruler-tier',
            'hs-ruler-rows': 'cal:ruler-rows',
            'hs-ruler-val-lt': 'cal:ruler-val-lt',
            'hs-ruler-view': 'cal:ruler-view',
            'hs-ruler-dir': 'cal:ruler-dir',
            'hs-ruler-hgt': 'cal:ruler-hgt',
            'hs-ruler-tick': 'cal:ruler-tick',
            'hs-ruler-line': 'cal:ruler-line',
            'hs-ruler-ring': 'cal:ruler-ring',
            'hs-ruler-label': 'cal:ruler-label',
            'hs-draw-ruler': 'cal:draw-ruler',
            'hs-ruler-hit': 'cal:ruler-hit',
            'hs-ruler-new': 'cal:ruler-new',
            'hs-ruler-off': 'cal:ruler-off',
            'hs-ruler-show': 'cal:ruler-show',
            'hs-ask-len': 'cal:ask-len',
        },
        'drop_globals': [],
    },
    # The step family's third file also asks.  ns-askkw and
    # ns-asktreat now take the Back sentinel exactly as the library
    # pair do (5 and 3 args), so both are swapped - the arity was
    # aligned FIRST, because a near-miss swap once shipped here as an
    # `expand` patching the one call site that existed, and the day a
    # second appeared (ns-ftreat, the form-aware wrapper) the grouped
    # build loaded fine and died at the first corner question.  Only
    # helpers the library reproduces EXACTLY belong in a swap map;
    # ns-ftreat itself stays local, its ask call rewritten like any
    # other call site.  Same layerok drift as its two siblings: the
    # hand twin left ns-dimv calling the dropped ns-layerok (R3, fixed
    # by regenerating), and it deleted the emptied ';;; ask helpers'
    # header that regenerating keeps (R2).
    'NORMIESTEP': {
        'src': 'lisp/cornerstp/NORMIESTEP.lsp',
        'swap': {
            'ns-layerok': 'cal:layer-usable-p',
            'ns-dot': 'cal:dot',
            'ns-askkw': 'cal:askkw',
            'ns-asktreat': 'cal:asktreat',
            # the length ruler: one block, held to the library by
            # tests/test_ruler_copies.py; the style builder stays local
            'ns-len-digit-p': 'cal:len-digit-p',
            'ns-len-num-p': 'cal:len-num-p',
            'ns-len-split': 'cal:len-split',
            'ns-len-token': 'cal:len-token',
            'ns-len-inches': 'cal:len-inches',
            'ns-parse-len': 'cal:parse-len',
            'ns-len-eighths': 'cal:len-eighths',
            'ns-spell-len': 'cal:spell-len',
            'ns-len-unread': 'cal:len-unread',
            'ns-ruler-tier': 'cal:ruler-tier',
            'ns-ruler-rows': 'cal:ruler-rows',
            'ns-ruler-val-lt': 'cal:ruler-val-lt',
            'ns-ruler-view': 'cal:ruler-view',
            'ns-ruler-dir': 'cal:ruler-dir',
            'ns-ruler-hgt': 'cal:ruler-hgt',
            'ns-ruler-tick': 'cal:ruler-tick',
            'ns-ruler-line': 'cal:ruler-line',
            'ns-ruler-ring': 'cal:ruler-ring',
            'ns-ruler-label': 'cal:ruler-label',
            'ns-draw-ruler': 'cal:draw-ruler',
            'ns-ruler-hit': 'cal:ruler-hit',
            'ns-ruler-new': 'cal:ruler-new',
            'ns-ruler-off': 'cal:ruler-off',
            'ns-ruler-show': 'cal:ruler-show',
            'ns-ask-len': 'cal:ask-len',
        },
        'drop_globals': [],
        # ns-askkw takes the SHOWN bracket third, like the library's
        'askkw_hidden': False,
        # ...but the Back sentinel travels with the ask helpers
        'symbols': {'NS-BACK': 'CAL-BACK'},
    },
    # POOLDEMO defines no helpers of its own -- it drives POOL's,
    # cross-file.  The swap renames those call sites (there is nothing
    # to drop), and pool:syssave picks up POOL's sysvar list as the
    # argument, exactly as in the POOL entry above.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'POOLDEMO': {
        'src': 'lisp/pool/POOLDEMO.LSP',
        'swap': {
            'pool:syssave': 'cal:syssave', 'pool:v+': 'cal:v+',
            'pool:mid': 'cal:mid', 'pool:v-': 'cal:v-',
            'pool:sysrestore': 'cal:sysrestore', 'pool:v*': 'cal:v*',
            'pool:undobegin': 'cal:undobegin',
            'pool:undoend': 'cal:undoend',
        },
        'drop_globals': [],
        'expand': {
            '(cal:syssave)':
                ['(cal:syssave \'("OSMODE" "LUNITS" "CMDECHO" "CLAYER"))'],
        },
    },
    # Like POOLDEMO: no helpers of its own, just POOL's called
    # cross-file, renamed at the call sites; pool:syssave picks up the
    # sysvar list.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'TUTORIALPOOL': {
        'src': 'lisp/pool/TUTORIALPOOL.LSP',
        'swap': {
            'pool:syssave': 'cal:syssave', 'pool:v+': 'cal:v+',
            'pool:v-': 'cal:v-', 'pool:mid': 'cal:mid',
            'pool:sysrestore': 'cal:sysrestore', 'pool:v*': 'cal:v*',
            'pool:undobegin': 'cal:undobegin',
            'pool:undoend': 'cal:undoend',
        },
        'drop_globals': [],
        'expand': {
            '(cal:syssave)':
                ['(cal:syssave \'("OSMODE" "LUNITS" "CMDECHO" "CLAYER"))'],
        },
    },
    # DRONE's only generic helper is the layer creator.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'drone': {
        'src': 'lisp/drone/drone.lsp',
        'swap': {
            'drone:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': [],
    },
    # TYDRN's only generic helper is the layer creator.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'tydrn': {
        'src': 'lisp/tydrn/tydrn.lsp',
        'swap': {
            'tydrn:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': [],
    },
    # SOCONV's only generic helper is the layer creator, the same as
    # its two cleanup siblings above.
    'SOCONV': {
        'src': 'lisp/soconv/SOCONV.lsp',
        'swap': {
            'soconv:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': [],
    },
    # The same for the third converter.  Its DASHED2 maker is NOT
    # generic -- ABHD and FITABHD keep their own copies of that one and
    # the library has never carried it -- so the layer creator is again
    # the only swap.
    'G2MCONV': {
        'src': 'lisp/g2mconv/G2MCONV.lsp',
        'swap': {
            'g2m:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': [],
    },
    # Layer creator, angle normalizer, and the strict 3-point
    # circumcenter -- the library form, not ABHD's looser 2-element one
    # (which stays out; see shared/README.md).
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'check_drawing': {
        'src': 'lisp/check/check_drawing.lsp',
        'swap': {
            'cfchk:ensure-layer': 'cal:ensure-layer',
            'cfchk:angnorm': 'cal:angnorm',
            'cfchk:circumcenter': 'cal:circumcenter',
        },
        'drop_globals': [],
    },
    # One helper: the Back-word test, under chk:back-word.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'ccprecheck': {
        'src': 'lisp/ccprecheck/ccprecheck.lsp',
        'swap': {
            'chk:back-word': 'cal:back-word-p',
        },
        'drop_globals': [],
    },
    # One helper: the Back-word test, under lin:back-word.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'lincheck': {
        'src': 'lisp/lincheck/lincheck.lsp',
        'swap': {
            'lin:back-word': 'cal:back-word-p',
        },
        'drop_globals': [],
    },
    # Uses no library helper -- the twin is the file plus the shared
    # banner.  Listed so it can never drift.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'LINTXTCHK': {
        'src': 'lisp/lintxtchk/LINTXTCHK.lsp',
        'swap': {},
        'drop_globals': [],
    },
    # The same feet-inch parser family as abcdef and XYPLOT, so the
    # same two generic helpers come out.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'ALTABCDEF': {
        'src': 'lisp/altabcdef/ALTABCDEF.lsp',
        'swap': {
            'altabcdef:trim': 'cal:trim', 'altabcdef:pad': 'cal:pad',
        },
        'drop_globals': [],
    },
    # The library's n-dimensional pair IS AutoDim's -- CALOFIN-LIB
    # still marks cal:dotn/cal:midn with 'ad:dot'/'ad:mid' -- plus the
    # ask pair and both bounding boxes.  The sentinel moves via symbols:
    # the hand twin renamed the AD-BACK comment mentions too.
    # Regenerating keeps the emptied ';; --- asking' rule the hand twin
    # deleted (R2).
    # [verified: matches except banner + listed residue vs the twin on disk]
    'AutoDim': {
        'src': 'lisp/autodim/AutoDim.lsp',
        'swap': {
            'ad:mid': 'cal:midn', 'ad:dot': 'cal:dotn',
            'ad:askkw': 'cal:askkw', 'ad:askyn': 'cal:askyn',
            'ad:ssbox': 'cal:bbox-ss', 'ad:entbox': 'cal:bbox-ent',
        },
        'drop_globals': [],
        'symbols': {
            'AD-BACK': 'CAL-BACK',
        },
    },
    # Uses no library helper -- file plus banner.  Listed so it can
    # never drift.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'dim_continue': {
        'src': 'lisp/dim_continue/dim_continue.lsp',
        'swap': {},
        'drop_globals': [],
    },
    'DIMSTAMP': {
        'src': 'lisp/dimstamp/DIMSTAMP.lsp',
        'swap': {
            'ds:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': [],
    },
    # One helper: the Back-word test, dash-named dd-back-word.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'DroneDistortion': {
        'src': 'lisp/drone_height/DroneDistortion.lsp',
        'swap': {
            'dd-back-word': 'cal:back-word-p',
        },
        'drop_globals': [],
    },
    # Uses no library helper -- file plus banner.  Listed so it can
    # never drift.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'DroneHeightGPS': {
        'src': 'lisp/drone_height/DroneHeightGPS.lsp',
        'swap': {},
        'drop_globals': [],
    },
    # Distance-squared, the layer creator and the one-line TEXT writer.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'wcalst': {
        'src': 'lisp/wcalst/wcalst.lsp',
        'swap': {
            'wc:d2': 'cal:d2', 'wc:ensure-layer': 'cal:ensure-layer',
            'wc:text': 'cal:text',
        },
        'drop_globals': [],
    },
    # One helper: the selection-set bounding box.  Its ;;;-comment pair
    # stays behind on regeneration -- top_span walks only ;; lines --
    # where the hand twin deleted it (R2).
    # [verified: matches except banner + listed residue vs the twin on disk]
    'STOCKCOVER': {
        'src': 'lisp/stockcover/STOCKCOVER.lsp',
        'swap': {
            'stock:bbox': 'cal:bbox-ss',
        },
        'drop_globals': [],
    },
    # block-number with its tag argument (cdo:*pt-tag* stays and is
    # passed), and the Back-word test under cdo:backp.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'CDCALLOUT': {
        'src': 'lisp/cdcallout/CDCALLOUT.lsp',
        'swap': {
            'cdo:block-number': 'cal:block-number',
            'cdo:backp': 'cal:back-word-p',
        },
        'drop_globals': [],
        'expand': {
            '(cal:block-number en)':
                ['(cal:block-number en cdo:*pt-tag*)'],
        },
    },
    # One helper: the 2D dot product, dash-named autobead-dot.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'AUTOBEAD': {
        'src': 'lisp/autobead/AUTOBEAD.lsp',
        'swap': {
            'autobead-dot': 'cal:dot',
        },
        'drop_globals': [],
    },
    # One helper: the layer creator, under cperp:layer.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'cperp_points': {
        'src': 'lisp/perp_points/cperp_points.lsp',
        'swap': {
            'cperp:layer': 'cal:ensure-layer',
            # the length ruler: one block, held to the library by
            # tests/test_ruler_copies.py; the style builder stays local
            'cperp:len-digit-p': 'cal:len-digit-p',
            'cperp:len-num-p': 'cal:len-num-p',
            'cperp:len-split': 'cal:len-split',
            'cperp:len-token': 'cal:len-token',
            'cperp:len-inches': 'cal:len-inches',
            'cperp:parse-len': 'cal:parse-len',
            'cperp:len-eighths': 'cal:len-eighths',
            'cperp:spell-len': 'cal:spell-len',
            'cperp:len-unread': 'cal:len-unread',
            'cperp:ruler-tier': 'cal:ruler-tier',
            'cperp:ruler-rows': 'cal:ruler-rows',
            'cperp:ruler-val-lt': 'cal:ruler-val-lt',
            'cperp:ruler-view': 'cal:ruler-view',
            'cperp:ruler-dir': 'cal:ruler-dir',
            'cperp:ruler-hgt': 'cal:ruler-hgt',
            'cperp:ruler-tick': 'cal:ruler-tick',
            'cperp:ruler-line': 'cal:ruler-line',
            'cperp:ruler-ring': 'cal:ruler-ring',
            'cperp:ruler-label': 'cal:ruler-label',
            'cperp:draw-ruler': 'cal:draw-ruler',
            'cperp:ruler-hit': 'cal:ruler-hit',
            'cperp:ruler-new': 'cal:ruler-new',
            'cperp:ruler-off': 'cal:ruler-off',
            'cperp:ruler-show': 'cal:ruler-show',
            'cperp:ask-len': 'cal:ask-len',
        },
        'drop_globals': [],
    },
    # The layer creator and the strict 3-point circumcenter.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'perp_points': {
        'src': 'lisp/perp_points/perp_points.lsp',
        'swap': {
            'perp:layer': 'cal:ensure-layer',
            'perp:circumcenter': 'cal:circumcenter',
            # the length ruler: one block, held to the library by
            # tests/test_ruler_copies.py; the style builder stays local
            'perp:len-digit-p': 'cal:len-digit-p',
            'perp:len-num-p': 'cal:len-num-p',
            'perp:len-split': 'cal:len-split',
            'perp:len-token': 'cal:len-token',
            'perp:len-inches': 'cal:len-inches',
            'perp:parse-len': 'cal:parse-len',
            'perp:len-eighths': 'cal:len-eighths',
            'perp:spell-len': 'cal:spell-len',
            'perp:len-unread': 'cal:len-unread',
            'perp:ruler-tier': 'cal:ruler-tier',
            'perp:ruler-rows': 'cal:ruler-rows',
            'perp:ruler-val-lt': 'cal:ruler-val-lt',
            'perp:ruler-view': 'cal:ruler-view',
            'perp:ruler-dir': 'cal:ruler-dir',
            'perp:ruler-hgt': 'cal:ruler-hgt',
            'perp:ruler-tick': 'cal:ruler-tick',
            'perp:ruler-line': 'cal:ruler-line',
            'perp:ruler-ring': 'cal:ruler-ring',
            'perp:ruler-label': 'cal:ruler-label',
            'perp:draw-ruler': 'cal:draw-ruler',
            'perp:ruler-hit': 'cal:ruler-hit',
            'perp:ruler-new': 'cal:ruler-new',
            'perp:ruler-off': 'cal:ruler-off',
            'perp:ruler-show': 'cal:ruler-show',
            'perp:ask-len': 'cal:ask-len',
        },
        'drop_globals': [],
    },
    # Uses no library helper -- file plus banner.  Listed so it can
    # never drift.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'tutorial_perp_points': {
        'src': 'lisp/perp_points/tutorial_perp_points.lsp',
        'swap': {},
        'drop_globals': [],
    },
    # Uses no library helper -- file plus banner.  Listed so it can
    # never drift.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'tutorial_cperp_points': {
        'src': 'lisp/perp_points/tutorial_cperp_points.lsp',
        'swap': {},
        'drop_globals': [],
    },
    # Layer creator and block-number with bp:*pt-tag* passed as the
    # tag argument.
    # [verified: byte-identical except the legacy banner vs the twin on disk]
    'BPCALLOUT': {
        'src': 'lisp/bpcallout/BPCALLOUT.lsp',
        'swap': {
            'bp:ensure-layer': 'cal:ensure-layer',
            'bp:block-number': 'cal:block-number',
            # (distance (list (car a) (cadr a)) ...) is cal:dist spelled
            # out: cal:2d IS (list (car p) (cadr p))
            'bp:dist': 'cal:dist',
        },
        'drop_globals': [],
        'expand': {
            '(cal:block-number en)':
                ['(cal:block-number en bp:*pt-tag*)'],
        },
    },
    # dn:mtext stays local: the library's cal:mtext takes hgt/wid/lay as
    # arguments where dn:mtext bakes them in from the tunables block, so
    # the two do not reproduce the same behaviour at the same arity.
    # Only the layer creator swaps.
    'DRONOTE': {
        'src': 'lisp/dronote/DRONOTE.lsp',
        'swap': {
            'dn:ensure-layer': 'cal:ensure-layer',
        },
        'drop_globals': [],
    },
    # Written against the library from the start, so the swap is a
    # straight rename: the 2-D vector set, the two angle helpers the
    # dimension arc is walked with, cal:plural (whose number-first shape
    # the report was worded around rather than the other way up), and
    # the sysvar pair.  cd:sysvars stays behind to supply the list
    # cal:syssave takes as an argument -- which is why there is no
    # expand rule here where PERPMARK needs one.  cd:on-track,
    # cd:layer-locked-p and the whole separating-axis kit are this
    # tool's own: the library has no convex-polygon overlap test, and
    # cal:layer-usable-p asks a different question (frozen and off as
    # well as locked, which is not what entmod refuses).
    'CLEARDIM': {
        'src': 'lisp/cleardim/CLEARDIM.lsp',
        'swap': {
            'cd:2d': 'cal:2d', 'cd:v-': 'cal:v-', 'cd:v+': 'cal:v+',
            'cd:v*': 'cal:v*', 'cd:dot': 'cal:dot', 'cd:perp': 'cal:perp',
            'cd:vlen': 'cal:vlen', 'cd:unit': 'cal:unit',
            'cd:mid': 'cal:mid', 'cd:cross': 'cal:cross',
            'cd:angnorm': 'cal:angnorm',
            'cd:signed-dang': 'cal:signed-dang',
            'cd:plural': 'cal:plural',
            'cd:syssave': 'cal:syssave',
            'cd:sysrestore': 'cal:sysrestore',
        },
        'drop_globals': [],
        # the heading over a section the swap empties: what is left under
        # it is the one helper that is about a dimension rather than a
        # vector, and "strictly 2-element results" was describing the
        # nine the library now supplies
        'replace': [(
            ";;; -------------------- 2-D vector helpers ---------------"
            "--------------\n"
            ";;; Strictly 2-element results; inputs may be 2- or "
            "3-element.\n",
            ";;; -------------------- 2-D vector helpers ---------------"
            "--------------\n"
            ";;; The set itself is CALOFIN-LIB.lsp's, under cal:.  What is"
            " left\n"
            ";;; here is the one that is about a dimension rather than a"
            " vector.\n")],
    },
}

def expand_calls(src, table):
    """Replace a bare (fn) call with one or more forms, each on its own
    line at the indentation the original sat at."""
    for call, forms in table.items():
        out, i = [], 0
        while True:
            j = src.find(call, i)
            if j < 0:
                out.append(src[i:])
                break
            bol = src.rfind('\n', 0, j) + 1
            indent = src[bol:j]
            out.append(src[i:j])
            sep = '\n' + (indent if not indent.strip() else '  ')
            out.append(sep.join(forms))
            i = j + len(call)
        src = ''.join(out)
    return src


def find_close(src, i):
    """Index just past the ')' closing the '(' at SRC[i].

    String- and comment-aware, like top_span's own walk: a ';' inside a
    prompt is text, and a '(' inside one is not a paren.
    """
    depth, instr, j = 0, False, i
    while j < len(src):
        c = src[j]
        if instr:
            if c == '\\':
                j += 2
                continue
            if c == '"':
                instr = False
        elif c == '"':
            instr = True
        elif c == ';':
            while j < len(src) and src[j] != '\n':
                j += 1
            continue
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return None


def collapse_calls(src, table):
    """Rename a helper to a library one that takes ONE MORE argument.

    `expand` cannot do this: it matches literal call text, and these
    calls carry multi-line (strcat ...) prompts whose text differs at
    every site.  So the call is found structurally and the argument
    appended.

    The formatting rule is read off the hand twins this replaces: a
    call that fits on one line takes the new argument inline; one that
    spans lines takes it on its own line, indented to the column of the
    call's FIRST argument -- which is where a reader looking down the
    argument list expects it, whether that first argument sits beside
    the call or under it.
    """
    for old, (new, extra) in table.items():
        # the local definition goes, like a swapped one
        span = top_span(src, 'defun', old)
        if span:
            src = src[:span[0]] + src[span[1]:]
        while True:
            m = re.search(r'\(' + re.escape(old) + r'(?=[\s)])', src)
            if not m:
                break
            i = m.start()
            end = find_close(src, i)
            if end is None:
                raise SystemExit(
                    "mirror_shared: (%s ... is never closed - the twin "
                    "was NOT written" % old)
            call = src[i:end]
            after = call[1 + len(old):]          # everything after (name
            if '\n' not in call:
                out = '(' + new + after[:-1] + ' ' + extra + ')'
            else:
                bol = src.rfind('\n', 0, i) + 1
                lead = re.match(r'[ \t]*', after).group(0)
                if after[len(lead):len(lead) + 1] == '\n':
                    # the first argument is on the NEXT line: take its
                    # own indentation
                    rest = after[len(lead) + 1:]
                    col = len(rest) - len(rest.lstrip(' '))
                else:
                    # the first argument sits beside the call.  The
                    # column is measured against the NEW name: it is
                    # the one that ends up on the line being aligned to
                    col = (i - bol) + 1 + len(new) + len(lead)
                out = ('(' + new + after[:-1].rstrip('\n')
                       + '\n' + ' ' * col + extra + ')')
            src = src[:i] + out + src[end:]
    return src


def rewrite_defuns(src, table):
    """Replace a whole top-level defun with given text.

    The one transform a swap map genuinely cannot express: the grouped
    build wants a DIFFERENT BODY, not a different name -- a thin
    wrapper that delegates to the library and then does the one
    tool-specific thing the library knows nothing about.  Only the new
    text lives in the table, so the lisp/ body is not duplicated here.
    """
    for name, replacement in table.items():
        span = top_span(src, 'defun', name)
        if span is None:
            raise SystemExit(
                "mirror_shared: rewrite names %s but no such defun - the "
                "twin was NOT written" % name)
        # top_span takes the ;;-comment block above the defun with it;
        # the replacement carries its own, so keep the split explicit
        head = src[span[0]:span[1]]
        lead = head[:len(head) - len(head.lstrip('\n'))]
        # the replaced body ended its paragraph with a blank line; the
        # replacement is shorter but the paragraph break still belongs
        tail = head[len(head.rstrip('\n')):]
        src = (src[:span[0]] + lead + replacement.rstrip('\n') + tail
               + src[span[1]:])
    return src


def top_span(src, opener, name):
    """(start, end) of a top-level (OPENER NAME ...), by paren balance,
    taking any ;;-comment block immediately above it with it."""
    m = re.search(r'^\(' + opener + r'\s+' + re.escape(name) + r'(?=[\s()])',
                  src, re.M)
    if not m:
        return None
    i = m.start()
    depth = 0
    instr = False
    j = i
    while j < len(src):
        c = src[j]
        if instr:
            if c == '\\':
                j += 2
                continue
            if c == '"':
                instr = False
        elif c == '"':
            instr = True
        elif c == ';':
            while j < len(src) and src[j] != '\n':
                j += 1
            continue
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                j += 1
                break
        j += 1
    while j < len(src) and src[j] in ' \t':          # a trailing comment
        j += 1
    if j < len(src) and src[j] == ';':
        while j < len(src) and src[j] != '\n':
            j += 1
    while i > 0:
        nl = src.rfind('\n', 0, i - 1)
        line = src[nl + 1:i]
        s = line.lstrip()
        if s.startswith(';;') and not s.startswith(';;;'):
            i = nl + 1
        else:
            break
    while j < len(src) and src[j] == '\n':
        j += 1
    return i, j


def fix_askkw(src, tool):
    """cal:askkw's third argument is the bracket text SHOWN in the
    prompt; the standalone helpers take a hidden-keyword list there and
    build the bracket themselves.  Renaming alone would pass nil where a
    string is wanted, so the bracket is written out -- the same
    "A/B/C" the standalone one would have derived from the keywords.

    A call site this cannot translate is a hard error: writing the twin
    anyway would ship a truncated call that loads fine and dies at the
    first keyword question."""
    out, n, i = [], 0, 0
    pair = re.compile(r'"(?P<kws>[A-Za-z][A-Za-z ]*)"(?P<gap>\s+)nil')
    while True:
        j = src.find('(cal:askkw', i)
        if j < 0:
            out.append(src[i:])
            break
        out.append(src[i:j])
        m = pair.search(src, j, j + 400)
        if not m:
            raise SystemExit(
                "mirror_shared: could not translate the askkw call at %r "
                "in %s - the twin was NOT written; teach fix_askkw the "
                "call shape first"
                % (src[j:j + 60].splitlines()[0], tool))
        kws = m.group('kws')
        out.append(src[j:m.start()])
        out.append('"%s"%s"%s"' % (kws, m.group('gap'), kws.replace(' ', '/')))
        n += 1
        i = m.end()
    return ''.join(out), n


def generate(tool, spec):
    """(twin path, twin text) for one tool, written nowhere."""
    src_path = os.path.join(HERE, spec['src'])
    dst_path = os.path.join(HERE, 'shared', 'parts', tool + '.lsp')
    if not os.path.exists(src_path):
        raise SystemExit("mirror_shared: %s is in TOOLS but %s does not "
                         "exist - fix the table" % (tool, spec['src']))
    with open(src_path, encoding='utf-8') as f:
        src = f.read()

    # the shared-build note goes under the Command: line of the header
    # the Commands: block may run to several lines; [ \t] not \s, or
    # the continuation creeps across the blank ;;; line into the prose
    m = re.search(r'^;;;\s+Commands?:.*(?:\n;;;[ \t]+\S[^\n]*)*\n;;;\n',
                  src, re.M)
    if m and 'SHARED BUILD' not in src:
        src = src[:m.end()] + BANNER + src[m.end():]
    if 'SHARED BUILD' not in src:
        # no Commands: block to hang it under -- put the banner above
        # the first top-level form so every twin still carries it
        m = re.search(r'^\(', src, re.M)
        if m:
            src = src[:m.start()] + BANNER + '\n' + src[m.start():]

    src = src.replace(
        ';;;  A self-contained file: it carries its own helpers.',
        ';;;  The grouped build: the helpers come from CALOFIN-LIB.lsp.')

    # Prose that stops being TRUE once a swap has emptied the section it
    # describes -- "one entry per character" above a font table that is
    # no longer there.  Required to match: a reworded source must fail
    # here rather than ship a twin explaining code it does not carry.
    for old_text, new_text in spec.get('replace', []):
        if old_text not in src:
            raise SystemExit(
                "mirror_shared: %s has a replace whose text is not in "
                "%s - the twin was NOT written; re-read the source and "
                "update the pair:\n  %r" % (tool, spec['src'], old_text))
        src = src.replace(old_text, new_text, 1)

    dropped = []
    for name in spec['swap']:
        span = top_span(src, 'defun', name)
        if span:
            src = src[:span[0]] + src[span[1]:]
            dropped.append(name)
    for name in spec['drop_globals']:
        span = top_span(src, 'setq', name)
        if span:
            # a dropped global that ended its paragraph takes the blank
            # line with it; put it back so the groups stay apart
            blank = ('\n' if src[span[0]:span[1]].endswith('\n\n') else '')
            src = src[:span[0]] + blank + src[span[1]:]

    for old, new in sorted(spec['swap'].items(), key=lambda kv: -len(kv[0])):
        # a call site is "(name", but a helper handed to mapcar or apply
        # is "'name" - miss the quoted form and the grouped build dies
        # at the first (mapcar 'tool:2d ...) with an undefined function
        src = re.sub(r"([('])" + re.escape(old) + r"(?=[\s)])",
                     lambda m: m.group(1) + new, src)

    src = expand_calls(src, spec.get('expand', {}))
    src = collapse_calls(src, spec.get('collapse', {}))
    src = rewrite_defuns(src, spec.get('rewrite', {}))

    for old, new in spec.get('symbols', {}).items():
        # \b only means anything next to a word character.  A global
        # written with earmuffs ends in '*', so a trailing \b would sit
        # between '*' and ')' -- two non-word characters, never a
        # boundary -- and the rename would silently do nothing.
        pat = (r'\b' if old[:1].isalnum() or old[:1] == '_' else '')
        pat += re.escape(old)
        pat += (r'\b' if old[-1:].isalnum() or old[-1:] == '_' else '')
        src = re.sub(pat, new, src)

    nkw = 0
    if spec.get('askkw_hidden'):
        src, nkw = fix_askkw(src, tool)
    return dst_path, src, len(dropped), nkw


def mirror(tool, spec):
    dst_path, src, ndropped, nkw = generate(tool, spec)
    with open(dst_path, 'w', encoding='utf-8') as f:
        f.write(src)
    print("wrote shared/parts/%s.lsp (%d lines, %d helpers from the "
          "library, %d askkw call sites translated)"
          % (tool, len(src.splitlines()), ndropped, nkw))


def check(tools=None):
    """Tools whose twin on disk differs from a fresh generation."""
    problems = []
    for tool in sorted(tools or TOOLS):
        dst_path, src, _, _ = generate(tool, TOOLS[tool])
        try:
            with open(dst_path, encoding='utf-8') as f:
                have = f.read()
        except OSError:
            problems.append("shared/parts/%s.lsp is missing - run "
                            "python3 tools/mirror_shared.py %s"
                            % (tool, tool))
            continue
        if have != src:
            problems.append(
                "shared/parts/%s.lsp differs from what mirror_shared.py "
                "generates - it is a GENERATED twin: edit %s and rerun "
                "python3 tools/mirror_shared.py %s"
                % (tool, TOOLS[tool]['src'], tool))
    return problems


def main():
    argv = sys.argv[1:]
    if "--check" in argv:
        problems = check([a for a in argv if a != "--check"] or None)
        for line in problems:
            print(line)
        print("mirror_shared --check: %s"
              % ("%d problem(s)" % len(problems) if problems else "current"))
        return 1 if problems else 0
    want = argv or sorted(TOOLS)
    for tool in want:
        if tool not in TOOLS:
            print("unknown tool %r - known: %s"
                  % (tool, ", ".join(sorted(TOOLS))), file=sys.stderr)
            return 1
        mirror(tool, TOOLS[tool])
    return 0


if __name__ == '__main__':
    sys.exit(main())
