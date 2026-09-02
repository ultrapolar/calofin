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

# Per tool: where it lives, and which of its own helpers the library
# already provides.  Only helpers whose behaviour the library reproduces
# exactly belong in a swap map -- anything else stays local.
TOOLS = {
    'SPA': {
        'src': 'lisp/spa/SPA.LSP',
        'swap': {
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
        'expand': {
            '(cal:syssave)':
                ['(cal:syssave \'("OSMODE" "CMDECHO" "CLAYER"))'],
        },
    },
    # POOL is the largest file in the tree and its twin was hand-mirrored
    # until the form-answer work made that a second pass -- exactly the
    # trigger CLAUDE.md names for moving a tool in here.
    'POOL': {
        'src': 'lisp/pool/POOL.LSP',
        'swap': {
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
        # the form asks nothing at the command line -- the tab strip
        # replaced its keyword picker -- so it uses no library helper
        'swap': {},
        'drop_globals': [],
    },
    # The launcher panel uses no library helpers at all -- it draws
    # nothing and asks nothing -- so its twin is the file plus the
    # shared banner.  Listed anyway so the twin can never drift.
    'LAZPANEL': {
        'src': 'lisp/lazpanel/LAZPANEL.lsp',
        'swap': {},
        'drop_globals': [],
    },
    # The spa chart and the step form are LAZFORM's shape applied to
    # SPA and to the three step routines: they draw their own pictures
    # and ask nothing through the library, so each twin is the file
    # plus the shared banner.  Listed for the same reason LAZFORM is --
    # a twin nobody generates is a twin that drifts by hand.
    'LAZSPA': {
        'src': 'lisp/lazspa/LAZSPA.lsp',
        'swap': {},
        'drop_globals': [],
    },
    'LAZSTEP': {
        'src': 'lisp/lazstep/LAZSTEP.lsp',
        'swap': {},
        'drop_globals': [],
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
        },
        'drop_globals': [],
        'expand': {
            '(cal:dedupe pts)':
                ['(cal:dedupe pts *PF-EXACT-EPS*)'],
        },
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
        },
        'drop_globals': [],
        'expand': {
            '(cal:dedupe pts)':
                ['(cal:dedupe pts *CAB-EXACT-EPS*)'],
        },
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
        },
        'drop_globals': [],
        'expand': {
            '(cal:block-number en)':
                ['(cal:block-number en *LH-PT-TAG*)'],
            '(cal:dedupe pts)':
                ['(cal:dedupe pts *LH-EXACT-EPS*)'],
        },
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
    'ABFIND': {
        'src': 'lisp/abfind/ABFIND.lsp',
        'swap': {
            'abf:askkw': 'cal:askkw', 'abf:askyn': 'cal:askyn',
            'abf:back-word-p': 'cal:back-word-p',
            'abf:ensure-layer': 'cal:ensure-layer',
            'abf:block-number': 'cal:block-number', 'abf:2d': 'cal:2d',
            'abf:dist': 'cal:dist', 'abf:angnorm': 'cal:angnorm',
            'abf:signed-dang': 'cal:signed-dang', 'abf:pad': 'cal:pad',
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
    # block-number with its tag argument (*CDO-PT-TAG* stays and is
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
                ['(cal:block-number en *CDO-PT-TAG*)'],
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
    # Layer creator and block-number with *BP-PT-TAG* passed as the
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
                ['(cal:block-number en *BP-PT-TAG*)'],
        },
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
