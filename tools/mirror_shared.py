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
    'TUTORIALSPA': {
        'src': 'lisp/spa/TUTORIALSPA.LSP',
        'swap': {},
        'drop_globals': [],
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
        },
        'drop_globals': [],
    },
    'XYPLOT': {
        'src': 'lisp/xyplot/XYPLOT.lsp',
        'swap': {
            'xyp:trim': 'cal:trim',
            'xyp:pad': 'cal:pad',
            'xyp:layer': 'cal:ensure-layer',
            'xyp:text': 'cal:text',
        },
        'drop_globals': [],
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
