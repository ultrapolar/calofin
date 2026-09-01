"""LAZFORM: the visual dimension chart, and the pool it produces.

The dialog cannot run here -- the VM has no DCL -- so the surface is
stubbed and the drawing is captured instead. Five jobs:

1. The chart data is coherent: every dimension names a POOL key, keys
   are unique, and every co-ordinate is inside the picture.
2. The generated DCL is well formed, with one tile key per answer.
3. The DRAWING is checked, not assumed: every vector is captured and
   must land inside the tile, in a colour the file declares, and the
   value-replaces-letter rule must actually hold.
4. lzf:answer implements the three-state contract -- empty means ask,
   NA means NA, a measurement means itself, and a typo means ask
   rather than silently meaning NA.
5. End to end: filling the chart in and pressing Insert draws the same
   pool as answering POOL's questions by hand.

Runs at either tier: standalone by default, grouped with
CALOFIN_LISP_ROOT=shared.
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Dot, parse_all  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..'))
LSP = os.path.join(REPO, 'lisp', 'lazform', 'LAZFORM.lsp')
POOL = os.path.join(REPO, 'lisp', 'pool', 'POOL.LSP')
OASIS = os.path.join(REPO, 'lisp', 'oasis', 'OASIS.lsp')

DX, DY = 520, 376          # a plausible tile size, in pixels
DRAW = {'vec': [], 'fill': [], 'tiles': {}, 'list': [], 'focus': []}


def _reset():
    OPENED.clear()
    POS.clear()
    DRAW['vec'] = []
    DRAW['fill'] = []
    DRAW['tiles'] = {}
    DRAW['list'] = []
    DRAW['focus'] = []


def _b(name):
    def deco(fn):
        lispvm.BUILTINS[lispvm.Sym(name)] = fn
        return fn
    return deco


_b('start_image')(lambda vm, a: a[0])
_b('end_image')(lambda vm, a: None)
_b('dimx_tile')(lambda vm, a: DX)
_b('dimy_tile')(lambda vm, a: DY)
_b('vector_image')(lambda vm, a: DRAW['vec'].append(
    [int(x) for x in a[:4]] + [int(a[4])]))
_b('fill_image')(lambda vm, a: DRAW['fill'].append(
    [int(x) for x in a[:4]] + [int(a[4])]))
_b('start_list')(lambda vm, a: DRAW['list'].clear())
_b('add_list')(lambda vm, a: DRAW['list'].append(str(a[0])))
_b('end_list')(lambda vm, a: None)
_b('mode_tile')(lambda vm, a: DRAW['focus'].append(str(a[0])))


OPENED = []
POS = []


@_b('new_dialog')
def _newdlg(vm, a):
    # 2 args on the first open, 4 once a position is known -- record
    # which, so the position threading is provable
    OPENED.append((str(a[0]), len(a)))
    if len(a) > 3:
        POS.append([float(v) for v in a[3]])
    vm.globals[lispvm.Sym('stub:*opened*')] = str(a[0])
    vm.globals[lispvm.Sym('stub:*act*')] = None
    return True


STUB = '''
(setq stub:*rc* 1 stub:*written* nil stub:*rcs* nil
      stub:*opened* nil stub:*mode* nil)
(defun vl-filename-mktemp (pat dir ext) (strcat "/stub/" pat ext))
(defun open (f mode) f)
(defun write-line (s fh) (setq stub:*written* (cons s stub:*written*)) s)
(defun close (fh) t)
;; the AutoCAD profile, as a store the scenario can seed and read back
;; -- a dialog position that outlives a restart is a setenv/getenv
;; round trip and nothing else
(setq stub:*env* nil)
(defun getenv (key / p) (if (setq p (assoc key stub:*env*)) (cdr p)))
(defun setenv (key v)
  (setq stub:*env* (cons (cons key v)
                         (vl-remove (assoc key stub:*env*) stub:*env*)))
  v)
(defun load_dialog (f) 7)
(defun mode_tile (k m) (setq stub:*mode* (cons (list k m) stub:*mode*)) t)
(defun term_dialog () nil)
;; DCL hands back where the dialog was standing when it closed, so the
;; next page can open in the same place instead of wandering
(defun done_dialog (status) (setq stub:*done* status) (list 120 340))
(defun unload_dialog (id) t)
(defun vl-file-delete (f) t)
(defun set_tile (k v) v)
(defun action_tile (k expr)
  (setq stub:*act* (cons (list k expr) stub:*act*)) t)
(defun start_dialog ( / p k)
  (if stub:*rcs*
    (setq stub:*rc* (car stub:*rcs*) stub:*rcs* (cdr stub:*rcs*)))
  (setq stub:*done* nil)          ; each page starts un-closed
  ;; type into every box the scenario named, the way a user tabbing
  ;; through them would -- through the REAL action expression
  (foreach p stub:*type*
    (if (and (not stub:*done*) (setq k (assoc (car p) stub:*act*)))
      (progn (setq $value (cadr p) $key (car p))
             (eval (read (strcat "(progn " (cadr k) ")")))
             ;; an entry that closed the dialog is spent: left in the
             ;; list a tab would re-fire on the page it just opened and
             ;; reopen itself for ever
             (if stub:*done*
               (setq stub:*type* (vl-remove p stub:*type*))))))
  (if stub:*done* stub:*done* stub:*rc*))
(setq stub:*act* nil stub:*type* nil stub:*rcs* nil)
'''


def fresh(with_pool=False, with_oasis=False):
    _reset()
    vm = VM()
    if with_pool:
        vm.load(POOL)
    if with_oasis:
        vm.load(OASIS)
    vm.load(LSP)
    return vm


def stubbed(with_pool=False, with_oasis=False):
    vm = fresh(with_pool, with_oasis)
    vm.loads(STUB)
    return vm


def lisp_str(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')


def arc_pts(poly):
    """A chart arc as the points lzf:arcpts polygonises it into."""
    cx, cy, rx, ry = (float(poly[1]), float(poly[2]),
                      float(poly[3]), float(poly[4]))
    f, to = float(poly[5]), float(poly[6])
    n = max(4, int(abs(to - f) / 6.0))
    return [(cx + rx * math.cos(math.radians(f + (to - f) * i / n)),
             cy - ry * math.sin(math.radians(f + (to - f) * i / n)))
            for i in range(n + 1)]


print("== the file loads and the chart data is coherent ==")
vm = fresh()
ver = vm.globals.get('*lazform-version*')
assert ver and re.fullmatch(r'v\d+\.\d+', str(ver)), ver
charts = vm.globals.get('lzf:*charts*')
assert charts, "no charts"
for c in charts:
    key, shape, title = str(c[0]), str(c[1]), str(c[2])
    outline, dims, extra = c[3], c[4], c[5]
    assert outline and dims, key
    keys = [str(d[1]) for d in dims] + [str(e[0]) for e in extra]
    assert len(keys) == len(set(keys)), "duplicate keys in %s: %r" % (key, keys)
    for poly in outline:
        if str(poly[0]) == 'A':          # ("A" cx cy rx ry from to)
            assert len(poly) == 7, "malformed arc in %s: %r" % (key, poly)
            cx, cy, rx, ry = (int(poly[1]), int(poly[2]),
                              int(poly[3]), int(poly[4]))
            assert rx > 0 and ry > 0, "arc with no radius in %s: %r" % (key, poly)
            # what has to fit the picture is the SWEEP, not the circle
            # it is cut from: a reverse arc is centred outside the pool
            # by construction, so its whole circle never fits and the
            # stretch actually drawn always does.  Walked the way
            # lzf:arcpts walks it.
            for x, y in arc_pts(poly):
                assert 0 <= x <= 1000 and 0 <= y <= 1000, (
                    "arc of %s leaves the picture at (%.1f, %.1f): %r"
                    % (key, x, y, poly))
            continue
        pts = [int(v) for v in poly]
        assert len(pts) % 2 == 0 and len(pts) >= 4, poly
        assert all(0 <= v <= 1000 for v in pts), \
            "outline of %s leaves the picture: %r" % (key, poly)
    for d in dims:
        x1, y1, x2, y2 = (int(d[2]), int(d[3]), int(d[4]), int(d[5]))
        side = str(d[6])
        assert all(0 <= v <= 1000 for v in (x1, y1, x2, y2)), d
        # "h" and "v" run along the drawing and get an arrowhead at each
        # end; "p" is a LEADER, from the point on the outline it names
        # out to where the letter sits, and runs at whatever angle that
        # puts it
        assert side in ('h', 'v', 'p'), d
        if side == 'h':
            assert y1 == y2, "%s: an h dimension must run across: %r" % (key, d)
        elif side == 'v':
            assert x1 == x2, "%s: a v dimension must run up: %r" % (key, d)
        assert (x1, y1) != (x2, y2), "zero-length dimension: %r" % (d,)
        assert str(d[7]).strip(), "dimension %r has no label" % (d,)
vm.loads('(setq t:*oas* (mapcar \'(lambda (c) (if (lzf:oasis-p c) (car c)))'
         '                       lzf:*charts*))')
OASIS_CHARTS = [str(x) for x in vm.globals['t:*oas*'] if x]
POOL_CHARTS = [str(c[0]) for c in charts if str(c[0]) not in OASIS_CHARTS]
assert OASIS_CHARTS and POOL_CHARTS
print("   %s, %d chart(s) -- %d POOL, %d OASIS -- every dimension keyed, "
      "labelled and in bounds"
      % (ver, len(charts), len(POOL_CHARTS), len(OASIS_CHARTS)))


print("== the dimension chains close ==")
# POOL resolves H+G+F+E against the pool's overall length and M+L+K
# against its width -- if the drawn chain does not add up to the drawn
# overall, the picture is lying about the measurement it names, and the
# operator reading it off would be misled before POOL ever saw a number.
for c in charts:
    name = str(c[0])
    if name in OASIS_CHARTS:
        continue                # an oasis has no chain: it is arcs all round
    dims = {str(d[1]): (int(d[2]), int(d[3]), int(d[4]), int(d[5]))
            for d in c[4]}
    letters = {str(d[0]): str(d[1]) for d in c[4]}

    def span(key, horiz):
        if key not in dims:
            return None
        x1, y1, x2, y2 = dims[key]
        return abs(x2 - x1) if horiz else abs(y2 - y1)

    for parts, letter, horiz, what in ((('h', 'g', 'f', 'e'), 'B', True, 'length'),
                                       (('m', 'l', 'k'), 'A', False, 'width')):
        got = [span(k, horiz) for k in parts]
        if not all(v is not None for v in got):
            continue
        overall = span(letters.get(letter, ''), horiz)
        if overall is None:
            continue
        assert abs(sum(got) - overall) <= 2, (
            "%s: %s = %d but %s (the overall %s) is %d -- the chain does "
            "not close" % (name, '+'.join(p.upper() for p in parts),
                           sum(got), letter, what, overall))
    print("   %-10s chains close against the overalls" % name)


print("== the chart's keys are keys POOL actually asks for ==")
# the whole point of the form is that POOL reads these back; a key POOL
# never asks for would be typed into and silently dropped
pool_src = open(POOL).read()
# pool:fckey is the whole roster of corner form-keys: the collective
# questions are spelled out as strings, and the per-corner ones are
# BUILT -- (strcat "corner" (substr s 8)) off the question's subject.
# The corner-row audit further down reads this rather than repeating it.
FCKEY = re.search(r'\(defun pool:fckey .*?\n\n', pool_src, re.S)
assert FCKEY, "pool:fckey has moved or changed shape"
FCKEY = FCKEY.group(0)
assert '(strcat "corner" (substr s 8))' in FCKEY, \
    "pool:fckey no longer builds the per-corner stems as corner<letters>"
# POOL builds its ask items two ways: most flows write
# (list 'key 'KIND "prompt" ...), while the L shapes write
# (list 'key "prompt" 'guide ...) and map the kind on afterwards.  Both
# shapes have to be recognised, or a perfectly good key looks invented.
askseq_keys = set(re.findall(r"\(list '([a-z][a-z0-9]*)\s+'(?:REQ|NAX|ZER|SUG)",
                             pool_src))
askseq_keys |= set(re.findall(r"\(list '([a-z][a-z0-9]*)\s+\"", pool_src))
# The cross-dim keys are BUILT AT RUN TIME, so no literal 'x0 appears
# anywhere in POOL.LSP and a plain scan calls them invented. Both
# callers write the same construction --
#   POOL.LSP:2185  (setq xitems (cons (list (read (strcat "x" (itoa k))) 'NAX
#   POOL.LSP:5869        xitems (cons (list (read (strcat "x" (itoa k))) 'NAX
# -- walking a template list, so how far k counts is the length of the
# longest template either caller can be handed: pool:crosstemplate's
# branches (POOL.LSP:3827) and pool:grecmode's three lists
# (POOL.LSP:1657-1681). Read those rather than whitelisting "x0".
assert re.search(r'\(read \(strcat "x" \(itoa k\)\)\)', pool_src), \
    "POOL no longer builds its cross-dim keys as x<k> -- this audit is stale"
_tmpl = re.search(r'\(defun pool:crosstemplate \(cmode\)(.*?)\n\n',
                  pool_src, re.S)
assert _tmpl, "pool:crosstemplate has moved or changed shape"
_lens = [len(re.findall(r"\(list '[a-z][a-z0-9]* \"", branch))
         for branch in re.split(r'\n    \(', _tmpl.group(1))]
_lens += [len(re.findall(r"'\(\d+ \d+ \"", block))
          for block in re.findall(r'\(setq pool:\*grec-[a-z]+\*(.*?)\n\n',
                                  pool_src, re.S)]
assert max(_lens) >= 4, "the cross-dim templates came back empty: %r" % _lens
askseq_keys |= set('x%d' % i for i in range(max(_lens)))
derived = {'c', 'd', 'c2'}          # the depth asks, keyed off their prompts
wired = {'shape', 'insq', 'btype', 'base'}
total = 0
for name in POOL_CHARTS:
    vm.loads('(setq t:*keys* (lzf:keys (lzf:chart "%s")))' % name)
    ks = [str(x) for x in vm.globals['t:*keys*']]
    for k in ks:
        assert k in askseq_keys or k in derived, (
            "%s: chart key %r is not asked for anywhere in POOL.LSP -- it "
            "would be typed into and dropped on the floor" % (name, k))
    total += len(ks)
    print("   %-10s %2d keys, all of them POOL answer keys" % (name, len(ks)))
print("   %d keys across %d POOL charts" % (total, len(POOL_CHARTS)))


print("== and the oasis charts' are keys OASIS actually asks for ==")
# the same audit, against the other routine.  oasis:*fkeys* is the whole
# roster: one entry per answer slot the run fills, named after the slot.
# A chart key outside it would be typed into and dropped on the floor
# exactly as a bad POOL key would.
ovm = fresh(with_oasis=True)
ovm.loads("(setq t:*fk* (mapcar 'cdr oasis:*fkeys*))")
OAS_KEYS = set(str(x) for x in ovm.globals['t:*fk*'])
assert 'shape' in OAS_KEYS and 'rl' in OAS_KEYS, sorted(OAS_KEYS)
# what a page SENDS rather than what it merely has a box for: the shape
# rides on the chart itself, and the base point is picked in the drawing
sendable = OAS_KEYS - {'shape'}
total = 0
for name in OASIS_CHARTS:
    ovm.loads('(setq t:*keys* (lzf:pagekeys (lzf:chart "%s")))' % name)
    ks = [str(x) for x in ovm.globals['t:*keys*']]
    for k in ks:
        assert k in sendable, (
            "%s: chart key %r is not an OASIS answer slot -- it would be "
            "typed into and dropped on the floor" % (name, k))
    # and every one of them is a slot that shape really reaches: OASIS
    # asks the slots oasis:steps lists and no others
    total += len(ks)
    print("   %-11s %d keys, all of them OASIS answer slots" % (name, len(ks)))
print("   %d keys across %d OASIS charts" % (total, len(OASIS_CHARTS)))


print("== the oasis charts are the outline OASIS itself draws ==")
# The picture on an oasis sheet is not artwork: it is the ring
# oasis:solve builds for that shape's reference drawing, scaled into
# the box.  So it can be re-derived rather than trusted -- run the
# solver on the numbers lzf:*oasart* records and every arc of the chart
# has to come back out of it.  A shape OASIS changes then shows up as a
# failing chart instead of a picture that has quietly stopped being
# true.
ovm.loads("(setq t:*art* lzf:*oasart*)")
ART = {str(r[0]): r for r in ovm.globals['t:*art*']}
assert set(ART) == set(OASIS_CHARTS), (
    "lzf:*oasart* covers %r, the oasis charts are %r"
    % (sorted(ART), sorted(OASIS_CHARTS)))


def ring_of(row):
    """oasis:solve on one chart's reference numbers."""
    def n(v):
        return 'nil' if v is None or v == [] else '%.10f' % float(v)
    args = ' '.join(n(v) for v in row[2:11])
    ring = ovm.loads('(oasis:solve %s 0.0 "%s")' % (args, str(row[1])))
    assert ring, "%s: oasis:solve built nothing from its own numbers" % row[0]
    return ring


def solved_ring(row):
    """That ring, mapped into the picture the way the chart data is."""
    ring = ring_of(row)
    w, h = float(row[2]), float(row[3])
    xl, xr, yt, yb = (float(row[11]), float(row[12]),
                      float(row[13]), float(row[14]))
    sx, sy = (xr - xl) / w, (yb - yt) / h
    out = []
    for e in ring:
        if isinstance(e[5], str) and str(e[5]) == 'LINE':
            out.append(('L', [round(xl + float(e[1][0]) * sx),
                              round(yb - float(e[1][1]) * sy),
                              round(xl + float(e[2][0]) * sx),
                              round(yb - float(e[2][1]) * sy)]))
            continue
        a, b = math.degrees(float(e[3])), math.degrees(float(e[4]))
        if b <= a:
            b += 360.0
        out.append(('A', [round(xl + float(e[1][0]) * sx),
                          round(yb - float(e[1][1]) * sy),
                          round(float(e[2]) * sx), round(float(e[2]) * sy),
                          round(a, 1), round(b, 1)]))
    return out


for ck in OASIS_CHARTS:
    want = solved_ring(ART[ck])
    ovm.loads('(setq t:*ol* (lzf:outline (lzf:chart "%s")))' % ck)
    got = []
    for poly in ovm.globals['t:*ol*']:
        if str(poly[0]) == 'A':
            got.append(('A', [int(poly[1]), int(poly[2]), int(poly[3]),
                              int(poly[4]), round(float(poly[5]), 1),
                              round(float(poly[6]), 1)]))
        else:
            got.append(('L', [int(v) for v in poly]))
    assert len(got) == len(want), (
        "%s: the chart draws %d elements, OASIS builds %d"
        % (ck, len(got), len(want)))
    for i, (g, wnt) in enumerate(zip(got, want)):
        assert g[0] == wnt[0], "%s element %d: %r vs %r" % (ck, i, g, wnt)
        for a, b in zip(g[1], wnt[1]):
            assert abs(a - b) <= 1.0, (
                "%s element %d has drifted from what OASIS draws:\n"
                "     chart %r\n     OASIS %r" % (ck, i, g[1], wnt[1]))
    print("   %-11s %d elements, every one of them off oasis:solve"
          % (ck, len(got)))

# and a bulge's drawn dimension really is that bulge's radius: the line
# from its centre out to the bound it touches, which is the whole
# reason it can be square to the page at all.  Which ring element each
# key names is per shape -- OASIS calls the same slot "top bulge" on
# one and "center lobe" on another.
BULGE_OF = {
    'OACenter':   {'rl': 'left', 'rt': 'top', 'rr': 'right'},
    'OATopRight': {'rl': 'left', 'rt': 'top-right', 'rr': 'right'},
    'OACloud':    {'rr': 'right'},
    'OAKidney':   {'rl': 'left', 'rr': 'right'},
    'OANXT':      {'rl': 'top-left', 'rt': 'center-bottom', 'rr': 'right'},
}
for ck in OASIS_CHARTS:
    row = ART[ck]
    xl, xr = float(row[11]), float(row[12])
    yt, yb = float(row[13]), float(row[14])
    sx, sy = (xr - xl) / float(row[2]), (yb - yt) / float(row[3])
    radii = {str(e[0]): float(e[2]) for e in ring_of(row)
             if not (isinstance(e[5], str) and str(e[5]) == 'LINE')}
    ovm.loads('(setq t:*d* (lzf:dims (lzf:chart "%s")))' % ck)
    seen = 0
    for d in ovm.globals['t:*d*']:
        side, key = str(d[6]), str(d[1])
        if side == 'p' or key not in BULGE_OF[ck]:
            continue
        want = radii[BULGE_OF[ck][key]]
        got = (abs(int(d[4]) - int(d[2])) / sx if side == 'h'
               else abs(int(d[5]) - int(d[3])) / sy)
        assert abs(got - want) <= 1.0, (
            "%s: the %s dimension measures %.1f, but the %s bulge's radius "
            "is %.1f" % (ck, str(d[0]), got, BULGE_OF[ck][key], want))
        seen += 1
    assert seen == len(BULGE_OF[ck]), (
        "%s: %d bulge dimensions drawn, %d expected"
        % (ck, seen, len(BULGE_OF[ck])))
print("   and every drawn bulge dimension is that bulge's own radius")


print("== the generated DCL is well formed, for every chart ==")
TILES = {'row', 'column', 'boxed_column', 'button', 'text', 'edit_box',
         'image', 'image_button', 'toggle', 'popup_list', 'spacer'}

vm.loads('(setq t:*all* (lzf:dcl-lines))')
ALL = [str(x) for x in vm.globals['t:*all*']]

# every chart is its own dialog, all of them in one generated file, so
# the page loop can load_dialog once and switch pages without going back
# to disk
opens = [l for l in ALL if l.endswith(' : dialog {')]
names = [l.split(' : ')[0] for l in opens]
# one dialog per chart, plus the LAZASCII probe
assert 'lazform_ascii : dialog {' in opens, \
    "the LAZASCII probe dialog is not in the generated file"
# the two extra dialogs in the same generated file: the font probe and
# the text view
assert 'lazform_txt : dialog {' in opens, \
    "the LAZTXT text-view dialog is not in the generated file"
opens = [o for o in opens
         if o not in ('lazform_ascii : dialog {', 'lazform_txt : dialog {')]
assert len(opens) == len(charts), (
    "%d dialogs for %d charts" % (len(opens), len(charts)))
assert len(names) == len(set(names)), "duplicate dialog names: %r" % names
depth = 0
for line in ALL:
    assert line.count('"') % 2 == 0, "odd quotes: %r" % line
    depth += line.count('{') - line.count('}')
    assert depth >= 0, line
assert depth == 0, "unbalanced braces across the file"
print("   %d lines, %d dialogs: %s" % (len(ALL), len(opens), ', '.join(names)))


def page(name):
    """One chart's dialog, sliced out of the whole file."""
    vm.loads('(setq t:*n* (lzf:dlgname "%s"))' % name)
    dlg = str(vm.globals['t:*n*'])
    i = ALL.index(dlg + ' : dialog {')
    d = 0
    for j in range(i, len(ALL)):
        d += ALL[j].count('{') - ALL[j].count('}')
        if d == 0:
            return ALL[i:j + 1]
    raise AssertionError("%s never closes" % dlg)


def check_page(name):
    d = page(name)
    # the dialog's own line opens it, and its label belongs INSIDE.  Get
    # these the wrong way round -- easy, since the lines are consed
    # newest-first and reversed once at the end -- and the file carries
    # an attribute before the dialog it belongs to, which is not DCL and
    # which balanced braces do not notice.
    assert d[0].endswith(' : dialog {'), \
        "%s: page does not open with its dialog line: %r" % (name, d[0])
    assert d[1].strip().startswith('label = '), \
        "%s: the dialog's label is not the first thing inside it: %r" % (name, d[1])
    vm.loads('(setq lzf:*chart* (lzf:chart "%s"))'
             '(setq t:*keys* (lzf:keys lzf:*chart*))'
             '(setq t:*dims* (lzf:dims lzf:*chart*))' % name)
    text = '\n'.join(d)
    tilekeys = re.findall(r'key = "([^"]+)"', text)
    assert len(tilekeys) == len(set(tilekeys)), \
        "%s: duplicate tile keys" % name
    answer_keys = [str(x) for x in vm.globals['t:*keys*']]
    assert set(answer_keys) <= set(tilekeys), (
        "%s: answers with no box: %r"
        % (name, sorted(set(answer_keys) - set(tilekeys))))
    # lzf:btgrey calls mode_tile on every page key, and mode_tile on a
    # tile that is not there is an error, not a no-op -- so every one of
    # them has to exist on this page
    vm.loads('(setq t:*pk* (lzf:pagekeys lzf:*chart*))')
    page_keys = [str(x) for x in vm.globals['t:*pk*']]
    assert set(page_keys) <= set(tilekeys), (
        "%s: greyable keys with no tile: %r"
        % (name, sorted(set(page_keys) - set(tilekeys))))
    assert len(page_keys) == len(set(page_keys)), \
        "%s: lzf:pagekeys repeats a key: %r" % (name, page_keys)
    # ONE chart tile, whole, and no strips: the picture is read as a
    # picture and every box is in the column beside it
    assert 'chart' in tilekeys, "%s: no chart image tile" % name
    assert 'chart0' not in tilekeys, (
        "%s: the chart is sliced into bands again -- the picture comes "
        "apart into strips and the boxes go back to being placed by "
        "spacer arithmetic" % name)
    assert not [k for k in tilekeys if re.fullmatch(r'chart\d+', k)], \
        "%s: a band tile survived: %r" % (name, tilekeys)
    # the POOL-only furniture is on the POOL pages and nowhere else:
    # mode_tile on a tile that is not there is an error, and an oasis
    # answers to neither question
    oasis_page = name in OASIS_CHARTS
    for extra in ('insq', 'btype'):
        if oasis_page:
            assert extra not in tilekeys, (
                "%s: an oasis page carries a %r tile -- nothing on an "
                "oasis answers to it" % (name, extra))
        else:
            assert extra in tilekeys, "%s: no %r tile" % (name, extra)
    for extra in ('accept', 'cancel'):
        assert extra in tilekeys, "%s: no %r tile" % (name, extra)
    # a tab for every chart, on every page -- including this one, so the
    # strip does not change width as you move along it
    for c2 in charts:
        assert 'tab_%s' % str(c2[0]) in tilekeys, \
            "%s: no tab for %s" % (name, str(c2[0]))
    # and a letter button and a box for EVERY dimension, keyed off its
    # answer: the whole point of the column is that nothing is missing
    # from it
    for dim in vm.globals['t:*dims*']:
        assert 'pick_%s' % str(dim[1]) in tilekeys, \
            "%s: dimension %s has no letter button" % (name, str(dim[0]))
        assert str(dim[1]) in tilekeys, \
            "%s: dimension %s has no box" % (name, str(dim[0]))
    assert text.count('is_cancel = true') == 1
    assert text.count('is_default = true') == 1
    assert ': image_button' not in text, (
        "%s: the chart is an image_button again -- it will be wiped the "
        "first time the mouse crosses it" % name)
    assert re.search(r': image \{ key = "chart";', text), \
        "%s: no passive chart image tile" % name
    for line in d[1:]:
        t = line.strip()
        if t in ('}', 'spacer;'):
            continue
        m = re.match(r': ([a-z_]+) \{', t)
        if m:
            assert m.group(1) in TILES, "%s: unknown tile %r" % (name, m.group(1))
        for clause in re.findall(r'[a-z_]+ = (?:"[^"]*"|[a-z0-9.]+)(;?)', t):
            assert clause == ';', \
                "%s: a DCL clause without its semicolon: %r" % (name, line)
    return d, tilekeys


# DCL does not scroll and a dialog wider than the screen has nowhere to
# go, so the tab strip gets a width budget.  Six full chart TITLES came
# to 117 characters -- more than twice the chart sitting under them.
TAB_BUDGET = 90
for c in charts:
    d, tk = check_page(str(c[0]))
    body = '\n'.join(d)
    tabs = re.findall(r'key = "tab_[^"]+"; label = "([^"]+)"', body)
    assert len(tabs) == len(charts), "%s: %d tabs" % (str(c[0]), len(tabs))
    # the tabs WRAP now, so what has to fit the screen is the widest
    # single row, not the whole strip: eight keys on one line ran 94
    # against this budget, which is a dialog that does not open
    vm.loads('(setq t:*tr* (lzf:tabrows))')
    rows = [[str(x) for x in r] for r in vm.globals['t:*tr*']]
    assert [t for r in rows for t in r] == tabs, (
        "%s: lzf:tabrows names %r but the page emits %r"
        % (str(c[0]), rows, tabs))
    wide = max(sum(len(t) + 6 for t in r) for r in rows)
    assert wide <= TAB_BUDGET, (
        "%s: the widest tab row is about %d characters, over the %d budget "
        "-- a dialog wider than the screen cannot be shown and DCL will not "
        "scroll it: %r" % (str(c[0]), wide, TAB_BUDGET, rows))
    print("   %-10s %2d lines, %2d tile keys, %d tab row(s), widest ~%d"
          % (str(c[0]), len(d), len(tk), len(rows), wide))

dcl = ALL
vm.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))')


print("== the drawing lands inside the tile, in declared colours ==")
COLS = {}
for name in ('line', 'back', 'dim', 'val', 'hi'):
    COLS[name] = int(vm.globals['lzf:*col-%s*' % name])
for c in charts:
    name = str(c[0])
    _reset()
    vm.loads('(setq lzf:*chart* (lzf:chart "%s")) (setq lzf:*vals* nil)'
             '(setq lzf:*focus* nil) (lzf:redraw)' % name)
    assert DRAW['vec'], "%s drew nothing" % name
    for v in DRAW['vec']:
        x1, y1, x2, y2, col = v
        assert 0 <= x1 <= DX and 0 <= x2 <= DX, \
            "%s: vector off the tile: %r" % (name, v)
        assert 0 <= y1 <= DY and 0 <= y2 <= DY, \
            "%s: vector off the tile: %r" % (name, v)
        assert col in COLS.values(), \
            "%s: undeclared colour %r in %r" % (name, col, v)
    for f in DRAW['fill']:
        x, y, w, h, col = f
        assert x >= 0 and y >= 0 and x + w <= DX and y + h <= DY, \
            "%s: fill off the tile: %r" % (name, f)
    print("   %-10s %3d vectors, %2d fills, all inside %dx%d and in colour"
          % (name, len(DRAW['vec']), len(DRAW['fill']), DX, DY))
_reset()
vm.loads('(setq lzf:*chart* (lzf:chart "Rectangle")) (setq lzf:*vals* nil)'
         '(setq lzf:*focus* nil) (lzf:redraw)')
blank = len(DRAW['vec'])


print("== a typed value replaces its letter on the chart ==")
assert not [v for v in DRAW['vec'] if v[4] == COLS['val']], \
    "nothing has been typed, yet something is drawn as a value"
# EVERY dimension is on the picture now, across and up alike, so the
# rule is checked on one of each: B ('tp') runs across, A ('le') up
_reset()
vm.loads('(lzf:put "tp" "40\'0\\"") (lzf:put "le" "16\'0\\"")'
         ' (lzf:put "m" "5\'0\\"") (lzf:redraw)')
vals = [v for v in DRAW['vec'] if v[4] == COLS['val']]
assert vals, "a typed value was not drawn"
# B, A and M are gone from the picture, replaced by what was typed, so
# the glyph strokes drawn in the outline colour must have gone DOWN even
# as the value strokes appeared
line_now = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
_reset()
vm.loads('(setq lzf:*vals* nil) (lzf:redraw)')
line_blank = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
assert line_now < line_blank, (
    "the letters B, A and M are still being drawn after being answered "
    "(%d outline strokes vs %d blank)" % (line_now, line_blank))
print("   %d value strokes appear; outline strokes fall %d -> %d"
      % (len(vals), line_blank, line_now))

# a LEADER's letter is replaced the same way -- it is the one dimension
# whose line does not run square to the page, and it must not be a
# special case in the drawing either
_reset()
vm.loads('(setq lzf:*chart* (lzf:chart "OACenter")) (setq lzf:*vals* nil)'
         ' (lzf:redraw)')
lead_blank = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
_reset()
vm.loads('(lzf:put "ftl" "6\'0\\"") (lzf:redraw)')
assert [v for v in DRAW['vec'] if v[4] == COLS['val']], \
    "a leader's value was not drawn"
assert len([v for v in DRAW['vec'] if v[4] == COLS['line']]) < lead_blank, \
    "the leader TL is still lettered after being answered"
print("   and a leader's letter goes the same way when it is answered")
_reset()
vm.loads('(setq lzf:*chart* (lzf:chart "Rectangle")) (setq lzf:*vals* nil)'
         ' (lzf:redraw)')


print("== the page loop: tabs, letter buttons, nothing on the chart ==")
vm2 = stubbed()
DRAW['vec'] = []
vm2.loads('(setq t:*f* (lzf:show "Rectangle"))')
# the chart must actually be DRAWN while the dialog is up.  An image tile
# is blank until something strokes into it, and DCL gives no second
# chance -- so a page that opens without a redraw shows an empty box,
# which is exactly what a user reports as "the drawing disappeared".
assert DRAW['vec'], "lzf:show opened a page and drew nothing into the chart"
drew_open = len(DRAW['vec'])
wired = {str(a[0]) for a in (vm2.globals.get('stub:*act*') or [])}
assert not [k for k in wired if k.startswith('chart')], (
    "an action is wired to a chart tile: it would be repainted on hover")
for k in ('btype', 'insq', 'accept', 'cancel'):
    assert k in wired, "%r has no callback" % k
vm2.loads('(setq t:*dims* (lzf:dims (lzf:chart "Rectangle")))')
for dim in vm2.globals['t:*dims*']:
    k = str(dim[1])
    assert 'pick_%s' % k in wired, \
        "dimension %s has no letter-button callback" % str(dim[0])
    assert k in wired, "dimension %s's box has no callback" % str(dim[0])
for c in charts:
    assert 'tab_%s' % str(c[0]) in wired, "no tab callback for %s" % str(c[0])
print("   %d callbacks bound, none on the chart, %d vectors drawn"
      % (len(wired), drew_open))

# clicking a letter must put the caret in that box AND select what is
# there, so the first keystroke replaces rather than appends
vm3 = stubbed()
vm3.loads('(setq stub:*type* \'(("pick_m" "")))'
          '(setq t:*f* (lzf:show "Rectangle"))')
modes = [(str(a[0]), int(a[1])) for a in (vm3.globals.get('stub:*mode*') or [])]
assert ('m', 2) in modes, "clicking M did not move the caret to its box: %r" % modes
assert ('m', 3) in modes, "clicking M did not select the box contents: %r" % modes
assert str(vm3.globals.get('lzf:*focus*')) == 'm', \
    "clicking M did not ring M on the chart"
print("   clicking a letter focuses its box, selects it, and rings the chart")

# a tab click reopens on the other chart, and what was typed survives it
vm4 = stubbed()
DRAW['vec'] = []
vm4.loads('(setq stub:*rcs* \'(4 1))'
          '(setq stub:*type* \'(("tp" "240") ("tab_Oval" "")))'
          '(setq t:*f* (lzf:show "Rectangle"))')
assert str(vm4.globals.get('stub:*opened*')) == 'lazform_oval', (
    "the tab did not reopen on the Oval page: %r"
    % vm4.globals.get('stub:*opened*'))
vm4.loads('(setq t:*v* (lzf:get "tp"))')
assert str(vm4.globals['t:*v*']) == '240', (
    "what was typed did not survive the page switch: %r" % vm4.globals['t:*v*'])
# DCL has no way to ask an open dialog where it is; done_dialog reporting
# its position as it closes is the only chance to find out, and
# new_dialog only accepts one back in its FOUR-argument form.  So the
# first page opens with two arguments and every page after it with four
# -- and if that ever regresses, the dialog jumps back to the middle of
# the screen on every tab click.
assert [n for n, _ in OPENED] == ['lazform_rectangle', 'lazform_oval'], OPENED
assert DRAW['vec'], "the second page opened and drew nothing into its chart"
assert [n for _, n in OPENED] == [2, 4], (
    "the reopened page did not carry the position back: %r" % OPENED)
print("   a tab reopens on the other chart, keeps what was typed,")
print("   and puts the dialog back where the user had dragged it")

print("== where it was left outlives the session, not just the page ==")
# lzf:*pos* is cleared at the top of every run and dies with the file,
# so the second LAZFORM of the day -- and the first one after an AutoCAD
# restart -- used to open back in the middle of the screen.  The
# profile is what closes that.
vmp = stubbed()
vmp.loads('(setq stub:*type* \'(("cancel" "")))'
          '(setq t:*f* (lzf:show "Rectangle"))')
vmp.loads('(setq t:*saved* (getenv lzf:*poskey*))')
assert str(vmp.globals.get('t:*saved*')) == '120,340', (
    "closing the dialog did not write its position to the profile: %r"
    % vmp.globals.get('t:*saved*'))

# a fresh VM is a fresh AutoCAD.  Seed the profile the last one left and
# the FIRST page opens with four arguments, at that point, rather than
# centred -- which is the whole of what was asked for.
vmq = stubbed()
vmq.loads('(setenv "LazForm_Pos" "212,84")')
vmq.loads('(setq stub:*type* \'(("cancel" "")))'
          '(setq t:*f* (lzf:show "Rectangle"))')
assert OPENED and OPENED[0][1] == 4, (
    "the first page of a fresh session ignored the saved position: %r" % OPENED)
assert POS and POS[0] == [212.0, 84.0], (
    "the first page opened somewhere other than where it was left: %r" % POS)
print("   closing writes the point to the profile, and a fresh session")
print("   opens its first page there instead of in the middle")

# What the profile is allowed to hold, and what it may do about it.
# pos-read takes a value back only if it round-trips, so a hand-edited
# or foreign one can do no more than centre the dialog -- which is
# exactly what happened before there was a profile at all.
vmr = stubbed()
for src, want, why in (
        ('"nonsense"', None, 'a value with no comma'),
        ('"12,"', None, 'a half-written value'),
        ('",34"', None, 'a value with no x'),
        ('"12,34x"', None, 'a value that does not round-trip'),
        ('"12,34"', [12, 34], 'a value this build wrote')):
    vmr.loads('(setenv lzf:*poskey* %s) (setq t:*r* (lzf:pos-read))' % src)
    got = vmr.globals.get('t:*r*')
    got = [int(v) for v in got] if got else None
    assert got == want, "%s read back as %r, not %r" % (why, got, want)
# SCREENSIZE is unknown until it is set, and reads 0 -- the clamp has to
# sit that out rather than pinning every dialog to the corner
assert not vmr.sysvars.get('SCREENSIZE'), vmr.sysvars.get('SCREENSIZE')
# a point saved on a second monitor that has since been unplugged is
# dragged back onto the drawing area, not left where the mouse cannot go
vmr.sysvars['SCREENSIZE'] = [1600.0, 900.0]
vmr.loads('(setenv lzf:*poskey* "4000,2000") (setq t:*r* (lzf:pos-read))')
assert [int(v) for v in vmr.globals['t:*r*']] == [1500, 800], (
    "an off-screen point was not clamped back: %r" % vmr.globals['t:*r*'])
vmr.loads('(setenv lzf:*poskey* "300,200") (setq t:*r* (lzf:pos-read))')
assert [int(v) for v in vmr.globals['t:*r*']] == [300, 200], (
    "a point already on screen was moved: %r" % vmr.globals['t:*r*'])
print("   a profile value this build did not write centres the dialog,")
print("   and a point off the current screen is dragged back onto it")


print("== corners: dropdown, un-greying size box, packing ==")


# an alist pair is a Dot when it has a value and a one-element LIST
# when it does not -- (cons 'g nil) is the list (g)
def pair(p):
    return (str(p.a), p.b) if isinstance(p, Dot) else (str(p[0]), None)


# structure: every chart whose POOL flow asks for corner treatments in
# these terms carries rows; the oval and the round pool have no corners
# to treat at all
for c in charts:
    name = str(c[0])
    d = page(name)
    text = '\n'.join(d)
    vm.loads('(setq t:*cor* (lzf:corners (lzf:chart "%s")))' % name)
    cors = [str(x[0]) for x in (vm.globals.get('t:*cor*') or [])]
    for stem in cors:
        assert re.search(r': popup_list \{ key = "%s"' % stem, text), \
            "%s: no dropdown for %s" % (name, stem)
        assert re.search(r': edit_box \{ key = "%s-sz"' % stem, text), \
            "%s: no size box for %s" % (name, stem)
    if not cors:
        assert 'Corners' not in text, \
            "%s: a Corners section with nothing in it" % name
    # a row names the POOL stems it answers in each state, and every
    # one of those has to be a stem pool:fckey really produces -- a row
    # pointed at a name POOL never builds would send treatments into
    # the void exactly the way a wrong dimension key would
    for row in (vm.globals.get('t:*cor*') or []):
        assert len(row) == 4, "%s: corner row %r is not (stem label in out)" % (
            name, [str(x) for x in row])
        for state, targets in (('in-square', row[2]), ('out-of-square', row[3])):
            for u in (targets or []):
                assert re.search(r'"%s"' % str(u), FCKEY) or \
                    re.match(r'^corner[a-z]{1,2}$', str(u)), (
                        "%s: %s corner row %s points at %r, which "
                        "pool:fckey never produces" % (name, state,
                                                       str(row[0]), str(u)))
assert [str(x[0]) for x in vm.globals['lzf:*corners*']] == \
    ['Rectangle', 'ROman', 'Grecian', 'GRSquare', 'OCtagon', 'L'], \
    [str(x[0]) for x in vm.globals['lzf:*corners*']]
print("   6 charts carry corner rows, every stem one pool:fckey builds")

# picking a sized treatment un-greys the size box; picking Square
# greys it again -- driven through the REAL action expression
vmc = stubbed()
vmc.loads('(setq stub:*type* \'(("cornera" "3")))'
          '(setq t:*f* (lzf:show "Rectangle"))')
modes = [(str(a[0]), int(a[1])) for a in (vmc.globals.get('stub:*mode*') or [])]
assert ('cornera-sz', 0) in modes, \
    "picking Cut did not un-grey the size box: %r" % modes
vmc2 = stubbed()
vmc2.loads('(setq stub:*type* \'(("cornera" "1")))'
          '(setq t:*f* (lzf:show "Rectangle"))')
modes = [(str(a[0]), int(a[1])) for a in (vmc2.globals.get('stub:*mode*') or [])]
assert ('cornera-sz', 1) in modes and ('cornera-sz', 0) not in modes, \
    "picking Square should leave the size box greyed: %r" % modes
print("   Cut un-greys its size box; Square keeps it greyed")

# packing: (ask) sends nothing; Square sends the treatment alone;
# Cut sends treatment + size when the size parses
vm.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))'
         '(setq lzf:*vals* nil lzf:*cvals* nil)'
         '(lzf:cput "cornera" 3) (lzf:put "cornera-sz" "24")'
         '(lzf:cput "cornerb" 1)'
         '(lzf:cput "cornerc" 2)'      # Radius, size left empty
         '(setq t:*f* (lzf:form "Rectangle" nil "Normal"))')
form = dict(pair(p2) for p2 in vm.globals['t:*f*'])
assert str(form.get('cornera-ty')) == 'Cut' and \
    abs(float(form['cornera-sz']) - 24.0) < 1e-9, form
assert str(form.get('cornerb-ty')) == 'Square' and 'cornerb-sz' not in form
assert str(form.get('cornerc-ty')) == 'Radius' and 'cornerc-sz' not in form, \
    "an empty size box must send the treatment alone (POOL asks the size)"
assert 'cornerd-ty' not in form, "(ask) sent a corner it should not have"
# in-square: corner A's row speaks for all four, under the one key
vm.loads('(setq t:*f2* (lzf:form "Rectangle" T "Normal"))')
form2 = dict(pair(p2) for p2 in vm.globals['t:*f2*'])
assert str(form2.get('corners-ty')) == 'Cut' and \
    abs(float(form2['corners-sz']) - 24.0) < 1e-9, form2
assert 'cornera-ty' not in form2 and 'cornerc-ty' not in form2, form2
print("   (ask)/Square/Radius/Cut all pack the way POOL reads them")

# a collective row FANS OUT out of square: POOL asks the eight Grecian
# corners individually there, so one row has to answer four of them,
# carrying the same treatment and the same size to each
vm.loads('(setq lzf:*chart* (lzf:chart "Grecian"))'
         '(setq lzf:*vals* nil lzf:*cvals* nil lzf:*pvals* nil)'
         '(lzf:cput "bodycorners" 3) (lzf:put "bodycorners-sz" "12")'
         '(lzf:cput "endcorners" 2) (lzf:put "endcorners-sz" "8")'
         '(setq t:*fi* (lzf:form "Grecian" T "Normal"))'
         '(setq t:*fo* (lzf:form "Grecian" nil "Normal"))')
fi = dict(pair(p2) for p2 in vm.globals['t:*fi*'])
fo = dict(pair(p2) for p2 in vm.globals['t:*fo*'])
assert str(fi.get('bodycorners-ty')) == 'Cut' and \
    abs(float(fi['bodycorners-sz']) - 12.0) < 1e-9, fi
assert str(fi.get('endcorners-ty')) == 'Radius' and \
    abs(float(fi['endcorners-sz']) - 8.0) < 1e-9, fi
assert 'cornera-ty' not in fi, "in square the eight are not asked: %r" % fi
for stem in ('cornera', 'cornerb', 'cornerc', 'cornerd'):
    assert str(fo.get(stem + '-ty')) == 'Cut' and \
        abs(float(fo[stem + '-sz']) - 12.0) < 1e-9, (stem, fo)
for stem in ('cornerlt', 'cornerlb', 'cornerrt', 'cornerrb'):
    assert str(fo.get(stem + '-ty')) == 'Radius' and \
        abs(float(fo[stem + '-sz']) - 8.0) < 1e-9, (stem, fo)
assert 'bodycorners-ty' not in fo and 'endcorners-ty' not in fo, fo
# the gate in front of those questions travels with them, and only with
# them: answer no corner row and POOL asks the gate as it always did
assert str(fi.get('crec')) == 'Yes' and str(fo.get('crec')) == 'Yes', (fi, fo)
vm.loads('(setq lzf:*cvals* nil)'
         '(setq t:*fn* (lzf:form "Grecian" nil "Normal"))')
fn = dict(pair(p2) for p2 in vm.globals['t:*fn*'])
assert 'crec' not in fn, "the corner gate travelled with no corner picked: %r" % fn
# and the rectangle has no such gate to answer
vm.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))'
         '(setq lzf:*cvals* nil) (lzf:cput "cornera" 1)'
         '(setq t:*fr* (lzf:form "Rectangle" nil "Normal"))')
fr = dict(pair(p2) for p2 in vm.globals['t:*fr*'])
assert 'crec' not in fr, \
    "the rectangle flow asks no corner gate -- crec must not be sent: %r" % fr
print("   a collective row answers one question in square and four out")
print("   of it; the corner gate travels only when a row is picked")


print("== cross dims and the mode dropdowns ==")
# every cross box has a box on its page (check_page already proves that
# for every answer key), every dropdown has a popup_list, and every
# dropdown opens on "(ask)" -- the form's version of an empty box
crossed = 0
for c in charts:
    name = str(c[0])
    text = '\n'.join(page(name))
    vm.loads('(setq t:*pi* (lzf:picks (lzf:chart "%s")))'
             '(setq t:*cx* (lzf:cross (lzf:chart "%s")))'
             '(setq t:*cm* (lzf:crossmode (lzf:chart "%s")))'
             % (name, name, name))
    picks = vm.globals.get('t:*pi*') or []
    cross = [str(x[0]) for x in (vm.globals.get('t:*cx*') or [])]
    for d in picks:
        key, sect, choices = str(d[0]), str(d[2]), [str(x) for x in d[3]]
        assert re.search(r': popup_list \{ key = "%s"' % key, text), \
            "%s: no dropdown for %s" % (name, key)
        assert choices[0] == '(ask)', \
            "%s: %s does not open on (ask): %r" % (name, key, choices)
        assert sect in ('cross', 'run'), \
            "%s: %s claims section %r" % (name, key, sect)
        assert len(set(choices)) == len(choices), \
            "%s: %s repeats a choice: %r" % (name, key, choices)
    if cross:
        crossed += 1
    else:
        assert 'Cross dims' not in text, \
            "%s: a Cross dims section with nothing in it" % name
    # a chart with a mode must carry a box for every tape that mode can
    # ask for, or an answer would have nowhere to be typed
    mode = vm.globals.get('t:*cm*')
    if mode:
        d = [p for p in picks if str(p[0]) == str(mode)][0]
        for word in [str(x) for x in d[3]]:
            vm.loads('(setq t:*n* (cadr (assoc "%s" lzf:*crosslive*)))' % word)
            n = vm.globals.get('t:*n*')
            assert n is None or int(n) <= len(cross), (
                "%s: %s = %s maps %d tapes but the chart has %d boxes"
                % (name, str(mode), word, int(n), len(cross)))
print("   %d charts carry cross boxes, every dropdown opening on (ask)"
      % crossed)


print("== the three-state answer contract ==")
# NOTE on the feet-inch case: this VM's distof only takes the leading
# number off a string, where AutoCAD's mode 4 reads the whole
# architectural spelling (12'6" is 150 inches there, 12.0 here). What
# the contract actually requires, and what is asserted, is that such a
# string PARSES rather than being dropped on the floor -- the arithmetic
# is AutoCAD's distof and not this file's to redo.
for typed, expect in (('', 'SKIP'),
                      ('   ', 'SKIP'),
                      ('NA', None),
                      ('na', None),
                      (' na ', None),
                      ('84', 84.0),
                      ("12'6\"", 'NUMBER'),
                      ('not a number', 'SKIP')):
    vm.loads('(setq t:*a* (lzf:answer "%s"))' % lisp_str(typed))
    got = vm.globals['t:*a*']
    if expect == 'SKIP':
        assert str(got).upper() == 'SKIP', \
            "%r gave %r, expected SKIP" % (typed, got)
    elif expect is None:
        assert got is None, "%r gave %r, expected nil (NA)" % (typed, got)
    elif expect == 'NUMBER':
        assert isinstance(got, float) and got > 0, \
            "%r gave %r, expected it to parse as a distance" % (typed, got)
    else:
        assert abs(float(got) - expect) < 1e-9, \
            "%r gave %r, expected %r" % (typed, got, expect)
print("   empty and rubbish both ask; NA means NA; a feet-inch")
print("   spelling parses rather than being dropped")


print("== the alist handed to POOL ==")
vm.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))'
         '(setq lzf:*vals* nil)'
         '(lzf:put "tp" "240") (lzf:put "le" "120")'
         '(lzf:put "g" "NA") (lzf:put "h" "")'
         '(setq t:*f* (lzf:form "Rectangle" T "Wedge"))')
# an alist pair is a Dot when it has a value and a one-element LIST
# when it does not: (cons 'g nil) is the list (g), whose cdr is nil.
# That is the present-but-nil state POOL reads as NA, so both shapes
# have to be understood here.
def pair(p):
    return (str(p.a), p.b) if isinstance(p, Dot) else (str(p[0]), None)


form = dict(pair(p) for p in vm.globals['t:*f*'])
assert str(form['shape']) == 'Rectangle'
assert str(form['insq']) == 'Insquare'
assert str(form['btype']) == 'Wedge'
assert abs(float(form['tp']) - 240.0) < 1e-9
assert 'g' in form and form['g'] is None, "NA must be sent as (g . nil)"
assert 'h' not in form, "an empty box must not be sent at all"
print("   filled keys sent, NA sent as nil, empty boxes left out entirely")


print("== end to end: the form draws what the questions draw ==")


def snapshot(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for p in vm.entdata[e]:
            if isinstance(p, Dot):
                d.setdefault(p.a, p.b)
        out.append(tuple(sorted((str(k), repr(v)) for k, v in d.items())))
    return out


# The same out-of-square rectangle with a wedge bottom, once through
# the chart and once through the prompts.  The chart answers the two
# overalls, H and F and the depths; the corners, the cross dims and
# M/L/K are typed in both runs, so what is being compared is the route
# the answers took, not the answers.
TYPED = [('tp', '240'), ('bo', '240'), ('le', '120'), ('ri', '120'),
         ('h', '30'), ('f', '180'), ('c', '40'), ('d', '60'),
         # the corners through the GUI: every dropdown to Cut (index 3)
         # with 24 in its size box -- what the prompt run types as
         # "Cut", 24 and six Enter-defaults
         ('cornera', '3'), ('cornera-sz', '24'),
         ('cornerb', '3'), ('cornerb-sz', '24'),
         ('cornerc', '3'), ('cornerc-sz', '24'),
         ('cornerd', '3'), ('cornerd-sz', '24')]
CORNERS = ["Cut", 24.0, None, None, None, None, None, None]
CROSS = ["Ends", 260.0, 260.0, 260.0, 260.0]
REST = [None, 60.0, None]                      # M takes its suggestion, L, K

vm = stubbed(with_pool=True)
vm.loads('(setq stub:*type* \'(%s))'
         % ' '.join('("%s" "%s")' % (k, v)
                    for k, v in TYPED + [('insq', '0'), ('btype', '2')]))
# out-of-square, and Wedge (third in the bottom-type list) -- set the
# way a user sets them, through the tiles' own action expressions, so a
# value read back after the dialog closes would not survive this test
try:
    # no chart prompt any more -- the tab strip picks the chart
    # no corner answers in this script: the dropdowns supplied them
    vm.run('c:LAZFORM',
           [(0.0, 0.0, 0.0)] + CROSS + ["Yes"] + REST)
except LispError as e:
    raise AssertionError("form run: %s" % e) from None
a = snapshot(vm)
assert a, "the form run drew nothing"
assert not vm.globals.get('pool:*form*'), "pool:*form* survived the run"
asked = [pr for pr, _ in vm.prompts]
for gone in ('\nPool shape', '\nBottom type', '\nCorner '):
    assert not any(pr.startswith(gone) for pr in asked), \
        "%r was asked even though the chart answered it" % gone
assert not any(pr.startswith('\nH -') or pr.startswith('\nC -')
               for pr in asked), "a charted dimension was asked anyway"

vm2 = stubbed(with_pool=True)
try:
    vm2.run('c:POOL',
            ["Outofsquare", "Rectangle", (0.0, 0.0, 0.0),
             240.0, 240.0, 120.0, 120.0] + CORNERS + CROSS +
            ["Yes", "Wedge", 30.0, 180.0] + REST + [40.0, 60.0])
except LispError as e:
    raise AssertionError("prompt run: %s" % e) from None
b = snapshot(vm2)
assert a == b, (
    "the form drew a different pool: %d entities from the chart, %d from "
    "the prompts" % (len(a), len(b)))
print("   %d entities, identical from the chart and from the command line"
      % len(a))
print("   and the chart's answers -- corners included -- were not")
print("   asked for again")

# ...and the same pool AGAIN, with the cross dims coming off the chart
# too.  The mode dropdown answers which four tapes x0..x3 are, so the
# four boxes mean something; leave it on (ask) and they would not.
print("== end to end: the cross dims off the chart as well ==")
vmx = stubbed(with_pool=True)
vmx.loads('(setq stub:*type* \'(%s))'
          % ' '.join('("%s" "%s")' % (k, v)
                     for k, v in TYPED + [('insq', '0'), ('btype', '2'),
                                          # "Ends", 4th in the dropdown
                                          ('cmode', '3'),
                                          ('x0', '260'), ('x1', '260'),
                                          ('x2', '260'), ('x3', '260')]))
try:
    vmx.run('c:LAZFORM', [(0.0, 0.0, 0.0), "Yes"] + REST)
except LispError as e:
    raise AssertionError("cross-dim form run: %s" % e) from None
x = snapshot(vmx)
assert x == b, (
    "the chart's own cross dims drew a different pool: %d entities against "
    "%d from the prompts" % (len(x), len(b)))
xasked = [pr for pr, _ in vmx.prompts]
for gone in ('\nRadius/Cut corners', '\nCross A-C', '\nCross B-D'):
    assert not any(pr.startswith(gone) for pr in xasked), \
        "%r was asked even though the chart answered it: %r" % (gone, xasked)
assert len(xasked) == 5, (
    "POOL asked %d questions, not the insertion point, the bottom gate and "
    "M/L/K: %r" % (len(xasked), [q.strip() for q in xasked]))
print("   %d entities, identical again; the mode and all four tapes came"
      % len(x))
print("   off the chart, leaving 5 questions")

# --------------------------------------------------------------------
# The Sport chain, end to end.
# --------------------------------------------------------------------
# A sport bottom asks a plan chain of its own -- E2 F2 G F1 E1 M L K --
# and until now the chart had boxes for only three of those eight, so
# five numbers off the sheet had to be retyped at the command line.
print("== a sport bottom, its whole chain off the chart ==")
SPORT = [('tp', '240'), ('le', '120'),
         ('e2', '20'), ('f2', '40'), ('g', '60'), ('f1', '40'),
         ('e1', '80'), ('m', '30'), ('l', '60'), ('k', '30'),
         ('c', '40'), ('d', '60'),
         ('cornera', '1')]              # Square, one answer in square
vs = stubbed(with_pool=True)
vs.loads('(setq stub:*type* \'(%s))'
         % ' '.join('("%s" "%s")' % (k, v)
                    for k, v in SPORT + [('insq', '1'), ('btype', '1')]))
try:
    vs.run('c:LAZFORM', [(0.0, 0.0, 0.0), "Yes"])
except LispError as e:
    raise AssertionError("sport form run: %s" % e) from None
sa = snapshot(vs)
assert sa, "the sport form run drew nothing"
sasked = [pr for pr, _ in vs.prompts]
for lead in ('\nE2 -', '\nF2 -', '\nG -', '\nF1 -', '\nE1 -', '\nM -',
             '\nL -', '\nK -', '\nC -', '\nD -', '\nBottom type'):
    assert not any(pr.startswith(lead) for pr in sasked), \
        "%s was asked even though the chart answered it: %r" % (lead, sasked)
assert len(sasked) == 2, (
    "POOL asked %d questions, not just the insertion point and the bottom "
    "gate: %r" % (len(sasked), [q.strip() for q in sasked]))
vs2 = stubbed(with_pool=True)
try:
    vs2.run('c:POOL',
            ["Insquare", "Rectangle", (0.0, 0.0, 0.0), 240.0, 120.0,
             "Square", "Yes", "Sport",
             20.0, 40.0, 60.0, 40.0, 80.0, 30.0, 60.0, 30.0, 40.0, 60.0])
except LispError as e:
    raise AssertionError("sport prompt run: %s" % e) from None
sb = snapshot(vs2)
assert sa == sb, (
    "the sport chart drew a different pool: %d entities from the chart, %d "
    "from the prompts" % (len(sa), len(sb)))
# and the letters this bottom does NOT ask for stayed behind
vs.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))'
         '(setq lzf:*vals* nil lzf:*cvals* nil lzf:*pvals* nil)'
         '(lzf:put "h" "30") (lzf:put "e2" "20") (lzf:put "c2" "50")'
         '(setq t:*sf* (lzf:form "Rectangle" T "Sport"))')
sf = dict(pair(p2) for p2 in vs.globals['t:*sf*'])
assert 'e2' in sf and 'h' not in sf and 'c2' not in sf, (
    "a Sport must carry E2 and drop H and C2: %r" % sf)
vs.loads('(setq t:*nf* (lzf:form "Rectangle" T "SHallow"))')
nf = dict(pair(p2) for p2 in vs.globals['t:*nf*'])
assert 'h' in nf and 'e2' not in nf, (
    "only a Sport asks the sport chain: %r" % nf)
print("   %d entities, identical from the chart and from the command line;"
      % len(sa))
print("   E2 F2 G F1 E1 M L K C D all off the sheet, 2 questions left")

# --------------------------------------------------------------------
# What the chosen bottom actually asks for.
# --------------------------------------------------------------------
# A bottom type does not reach every letter on the sheet.  The form used
# to offer them all anyway, so a C typed against a Normal hopper went
# nowhere and nothing said so.  lzf:btskip names what to grey -- read
# off POOL's own pool:btmspec, so it cannot drift from the command it
# feeds.  What follows is NOT a second copy of that table: it is derived
# from btmspec here too, and only Sport is stated outright, because
# Sport is the one case btmspec does not describe.
print("== the bottom type decides which boxes are live ==")
bv = stubbed(with_pool=True)

BOTTOMS = ["Normal", "Sport", "Wedge", "SLope", "MOdflat", "SHallow"]


def skip_of(bt):
    bv.loads('(setq test:*s* (lzf:btskip "%s"))' % bt)
    return set(str(x) for x in (bv.globals['test:*s*'] or []))


def spec_of(bt):
    bv.loads('(setq test:*sp* (pool:btmspec "%s"))' % bt)
    return [bool(x) for x in bv.globals['test:*sp*'][:4]]


for bt in BOTTOMS:
    got = skip_of(bt)
    if bt == "Sport":
        # Sport never reaches pool:hopnormal, so btmspec does not
        # describe it: its own path asks C and D, and asks a chain of
        # E2 F2 G F1 E1 M K rather than H G F E.
        want = {"h", "f", "e", "c2"}
    else:
        ask_g, ask_e, profile, ask_c2 = spec_of(bt)
        want = set()
        if not ask_g:
            want.add("g")
        if not ask_e:
            want.add("e")
        if not profile:
            want |= {"c", "d"}
        if not ask_c2:
            want.add("c2")
    assert got == want, "%s: greys %r, POOL's own spec says %r" % (bt, got, want)
    print("   %-8s greys %s" % (bt, sorted(got) or "nothing"))

# the two that would actually mislead someone, stated plainly
assert skip_of("Normal") == {"c", "d", "c2"}, \
    "a Normal hopper draws no side view, so C and D must be greyed"
assert skip_of("SHallow") == set(), \
    "SHallow asks everything including C2 -- nothing should be greyed"
assert "c2" in skip_of("Wedge") and "c2" not in skip_of("SHallow"), \
    "C2 is a SHallow-only question"

# every POOL chart carries the depth rows, or a bottom that asks for
# them would have nowhere to put them -- and the Grecians' gate lists,
# which sit in the same s-expression, must be untouched by that.  An
# oasis has no bottom type and no depth chain: it is asked about its
# floor after the outline is drawn, at the command line.
for ck in POOL_CHARTS:
    bv.loads('(setq test:*e* (lzf:extra (lzf:chart "%s")))' % ck)
    ex = [str(x[0]) for x in bv.globals['test:*e*']]
    for need in ('c', 'd', 'c2'):
        assert need in ex, "%s has no %s box" % (ck, need)
    bv.loads('(setq test:*g* (lzf:gates (lzf:chart "%s")))' % ck)
    g = bv.globals['test:*g*']
    gk = [str(x.a) for x in g] if g else []
    assert not ({'c', 'd', 'c2'} & set(gk)), \
        "%s: a depth leaked into the gates list: %r" % (ck, gk)
print("   all %d POOL charts carry C, D and C2; no gate list disturbed"
      % len(POOL_CHARTS))

# and a value the bottom will not ask for does not travel to POOL
bv.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))')
bv.loads('(setq lzf:*vals* nil)')
bv.loads('(lzf:put "c" "40") (lzf:put "d" "60") (lzf:put "tp" "240")')
bv.loads('(setq test:*f* (lzf:form "Rectangle" nil "Normal"))')
keys = [str(pr.a) for pr in bv.globals['test:*f*']]
assert 'c' not in keys and 'd' not in keys, (
    "a Normal run still carried C/D to POOL, which never asks for them: %r"
    % keys)
assert 'tp' in keys, "the plan dimension was dropped too: %r" % keys
bv.loads('(setq test:*f2* (lzf:form "Rectangle" nil "Wedge"))')
keys2 = [str(pr.a) for pr in bv.globals['test:*f2*']]
assert 'c' in keys2 and 'd' in keys2, \
    "a Wedge DOES ask C and D -- they must travel: %r" % keys2
print("   C and D travel on a Wedge and are dropped on a Normal")


# --------------------------------------------------------------------
# ONE authority: what is greyed and what is sent are the same set.
# --------------------------------------------------------------------
# The bottom type is only one of three things that decide -- the
# in-square toggle and the cross-dim mode dropdown decide too -- and the
# hazard is that the greying and the sending drift apart: a box greyed
# on screen whose contents travel anyway, or a live box quietly dropped.
# lzf:dead is the single answer both callers read, so the property worth
# asserting directly is that identity, over the whole page.
print("== the greying and the sending are one decision ==")
av2 = stubbed(with_pool=True)

# (chart, in-square, bottom type, mode word to pick where it is offered)
STATES = [("Rectangle", False, "Normal",  "Corner"),
          ("Rectangle", False, "Sport",   "Ends"),
          ("Rectangle", True,  "Wedge",   "Ends"),
          ("Rectangle", False, "Wedge",   "Middle"),
          ("Rectangle", False, "SHallow", "Ends"),
          ("Oval",      False, "Sport",   "Ends"),
          ("Oval",      True,  "Normal",  "Corner"),
          ("ROman",     False, "Sport",   None),
          ("ROman",     True,  "MOdflat", None),
          ("Grecian",   False, "Normal",  "Simple"),
          ("Grecian",   False, "Wedge",   "Center"),
          ("Grecian",   True,  "SLope",   "Simple"),
          ("GRSquare",  False, "Sport",   "Complex"),
          ("OCtagon",   True,  "SHallow", "Simple"),
          ("L",         False, "Normal",  None),
          ("L",         True,  "Sport",   None),
          ("ROUnd",     False, "MOdflat", None),
          ("ROUnd",     True,  "Sport",   None),
          # the oasis pages read the same way, off their own dropdowns:
          # the bottom type and the toggle mean nothing there, so they
          # are passed and ignored
          ("OACenter",   False, "Normal", "Simple"),
          ("OACenter",   False, "Normal", "Complex"),
          ("OATopRight", False, "Normal", "Complex"),
          ("OACloud",    False, "Normal", "Straight"),
          ("OACloud",    False, "Normal", "Rounded"),
          ("OAKidney",   False, "Normal", "True"),
          ("OAKidney",   False, "Normal", "Asymmetric"),
          ("OANXT",      False, "Normal", "Complex")]


def state(name, insq, bt, mode):
    """Fill every box and answer every dropdown, then read both sides."""
    av2.loads('(setq lzf:*chart* (lzf:chart "%s"))' % name)
    av2.loads('(setq lzf:*vals* nil lzf:*cvals* nil lzf:*pvals* nil)')
    av2.loads('(foreach k (lzf:keys lzf:*chart*) (lzf:put k "60"))')
    av2.loads('(setq t:*pi* (lzf:picks lzf:*chart*))')
    for d in (av2.globals.get('t:*pi*') or []):
        choices = [str(x) for x in d[3]]
        # every dropdown is answered: an unanswered one is dropped for
        # being empty, which is a different rule and tested elsewhere
        av2.loads('(lzf:pput "%s" %d)'
                  % (str(d[0]),
                     choices.index(mode) if mode in choices else 1))
    av2.loads('(setq t:*pk* (lzf:pagekeys lzf:*chart*))'
              '(setq t:*dead* (lzf:dead lzf:*chart* %s "%s"))'
              '(setq t:*shp* (cadr lzf:*chart*))'
              % ('T' if insq else 'nil', bt))
    av2.loads('(setq t:*ff* (lzf:form t:*shp* %s "%s"))'
              % ('T' if insq else 'nil', bt))
    return (set(str(x) for x in av2.globals['t:*pk*']),
            set(str(x) for x in (av2.globals['t:*dead*'] or [])),
            set(str(p.a) if isinstance(p, Dot) else str(p[0])
                for p in av2.globals['t:*ff*']))


for name, insq, bt, mode in STATES:
    pk, dead, sent = state(name, insq, bt, mode)
    assert dead <= pk, (
        "%s: lzf:dead named %r, which is not on the page -- mode_tile "
        "would error on it" % (name, sorted(dead - pk)))
    assert dead == pk - sent, (
        "%s %s %s %s: greys %r but drops %r -- the two have drifted"
        % (name, 'in-square' if insq else 'out-of-square', bt, mode,
           sorted(dead), sorted(pk - sent)))
    print("   %-9s %-13s %-8s %-8s %2d of %2d keys dead"
          % (name, 'in-square' if insq else 'out-of-square', bt,
             mode or "-", len(dead), len(pk)))

# the rules the table above is there to protect, said outright
pk, dead, sent = state("Rectangle", False, "Wedge", "Corner")
assert {"x2", "x3"} <= dead and not ({"x0", "x1"} & dead), \
    "Corner tapes two diagonals, so x2 and x3 are dead: %r" % sorted(dead)
pk, dead, sent = state("Rectangle", False, "Wedge", "Ends")
assert not ({"x0", "x1", "x2", "x3"} & dead), \
    "Ends tapes four diagonals, so all four boxes are live: %r" % sorted(dead)
pk, dead, sent = state("Rectangle", True, "Wedge", "Ends")
assert {"x0", "x1", "x2", "x3", "cmode", "bo", "ri"} <= dead, \
    "in square there are no cross dims and no second overall: %r" % sorted(dead)
pk, dead, sent = state("Grecian", False, "Wedge", "Center")
assert {"x0", "x1"} <= dead and "gcross" not in dead, (
    "Center answers the gate and asks its 14 diagonals at the command "
    "line, so the boxes are dead and the dropdown is not: %r" % sorted(dead))
pk, dead, sent = state("L", False, "Normal", None)
assert "btype" in dead and "mirror" not in dead, (
    "POOL asks no bottom type on an L, and mirror is not a cross dim: %r"
    % sorted(dead))
assert not ({"ac", "bd", "cf"} & dead), \
    "the L's nine diagonals need no mode -- they are always live"
pk, dead, sent = state("L", True, "Normal", None)
assert {"ac", "bd", "cf"} <= dead, "in square the L squares up to its sides"

# "(ask)" is not a mode.  Which box is which diagonal is undefined until
# one is picked, so every cross box is dead and the dropdown sends
# nothing -- the dropdown's version of an empty box.
av2.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))'
          '(setq lzf:*vals* nil lzf:*cvals* nil lzf:*pvals* nil)'
          '(foreach k (lzf:keys lzf:*chart*) (lzf:put k "60"))'
          '(setq t:*dead* (lzf:dead lzf:*chart* nil "Wedge"))'
          '(setq t:*ff* (lzf:form "Rectangle" nil "Wedge"))')
dead = set(str(x) for x in (av2.globals['t:*dead*'] or []))
sent = set(str(p.a) if isinstance(p, Dot) else str(p[0])
           for p in av2.globals['t:*ff*'])
assert {"x0", "x1", "x2", "x3"} <= dead, \
    "(ask) leaves no cross box mapped: %r" % sorted(dead)
assert not ({"x0", "x1", "x2", "x3", "cmode"} & sent), \
    "(ask) sent a cross dim whose diagonal is not decided: %r" % sorted(sent)
print("   (ask) maps no box, and none of them travels")


# --------------------------------------------------------------------
# The Grecian's collective corner rows, end to end, both ways.
# --------------------------------------------------------------------
# In square POOL asks two questions -- the four body corners, then the
# four end tips -- and out of square it asks all eight individually.
# The sheet has two rows either way, so out of square each one has to
# fan out to the four corners it stands for, carrying one treatment and
# one size to each.
print("== the Grecian's two corner rows, in square and out ==")
GREC = [('b', '360'), ('a', '200'), ('tt', '240'), ('ss', '60'),
        ('s1', '50'), ('vv', '100'), ('s2', '78'),
        ('bodycorners', '3'), ('bodycorners-sz', '12'),
        ('endcorners', '3'), ('endcorners-sz', '8')]


def grecrun(extra, prompts):
    v = stubbed(with_pool=True)
    v.loads('(setq stub:*rcs* \'(4 1))'
            '(setq stub:*type* \'(("tab_Grecian" "") %s))'
            % ' '.join('("%s" "%s")' % (k, val) for k, val in GREC + extra))
    try:
        v.run('c:LAZFORM', prompts)
    except LispError as e:
        raise AssertionError("grecian form run: %s" % e) from None
    return v


gi = grecrun([('insq', '1')], [(0.0, 0.0, 0.0), "No"])
ga = snapshot(gi)
assert ga, "the in-square grecian form run drew nothing"
giasked = [pr for pr, _ in gi.prompts]
for lead in ('\nAnything to record about the corners',
             '\nHow should the body corners',
             '\nHow should the end-tip corners'):
    assert not any(pr.startswith(lead) for pr in giasked), \
        "%s was asked even though the sheet answered it: %r" % (lead, giasked)
gi2 = stubbed(with_pool=True)
gi2.run('c:POOL',
        ["Insquare", "Grecian", (0.0, 0.0, 0.0), "Overall",
         360.0, 200.0, 240.0, 60.0, 50.0, 100.0, 78.0,
         "Yes", "Cut", 12.0, "Cut", 8.0, "No"])
gb = snapshot(gi2)
assert ga == gb, (
    "the in-square grecian sheet drew a different pool: %d entities from "
    "the chart, %d from the prompts" % (len(ga), len(gb)))
print("   in square: %d entities, two rows answering POOL's two questions"
      % len(ga))

go = grecrun([('insq', '0'), ('gcross', '1'),      # Simple
              ('x0', '300'), ('x1', '300')],
             [(0.0, 0.0, 0.0), "No"])
gc = snapshot(go)
goasked = [pr for pr, _ in go.prompts]
for lead in ('\nAnything to record about the corners', '\nHow should Corner',
             '\nGrecian cross-dim detail', '\nCross dim '):
    assert not any(pr.startswith(lead) for pr in goasked), \
        "%s was asked even though the sheet answered it: %r" % (lead, goasked)
assert len(goasked) == 2, (
    "POOL asked %d questions, not just the insertion point and the bottom "
    "gate: %r" % (len(goasked), [q.strip() for q in goasked]))
go2 = stubbed(with_pool=True)
go2.run('c:POOL',
        ["Outofsquare", "Grecian", (0.0, 0.0, 0.0), "Overall",
         360.0, 200.0, 240.0, 60.0, 50.0, 100.0, 78.0,
         "Simple", 300.0, 300.0, "Yes",
         # A B RB RT C D LT LB -- body 12, tips 8, the order POOL asks
         "Cut", 12.0, "Cut", 12.0, "Cut", 8.0, "Cut", 8.0,
         "Cut", 12.0, "Cut", 12.0, "Cut", 8.0, "Cut", 8.0, "No"])
gd = snapshot(go2)
assert gc == gd, (
    "the fanned-out grecian sheet drew a different pool: %d entities from "
    "the chart, %d from the prompts" % (len(gc), len(gd)))
print("   out of square: %d entities, each row fanned out to its four"
      % len(gc))


# --------------------------------------------------------------------
# The True L: no bottom type, a mirror question, and its corner gate.
# --------------------------------------------------------------------
# POOL draws the standard hopper on an L and offers no choice, so the
# bottom popup is greyed on that page and btype is never sent from it.
# The mirror question is the other kind of dropdown -- a keyword answer
# in its own right, asked after everything is drawn.
print("== the True L: mirror off the sheet, no bottom type sent ==")
vl = stubbed(with_pool=True)
vl.loads('(setq stub:*rcs* \'(4 1))'
         '(setq stub:*type* \'(("tab_L" "") %s))'
         % ' '.join('("%s" "%s")' % (k, v) for k, v in
                    [('ab', '480'), ('bc', '180'), ('cd', '240'),
                     ('de', '120'), ('ef', '240'), ('fa', '300'),
                     ('outercorners', '3'), ('outercorners-sz', '12'),
                     ('innercorner', '1'),
                     ('mirror', '2'),          # "No", third in the list
                     ('insq', '1'), ('btype', '2')]))
try:
    vl.run('c:LAZFORM', [(0.0, 0.0, 0.0), "No"])
except LispError as e:
    raise AssertionError("L form run: %s" % e) from None
la = snapshot(vl)
lasked = [pr for pr, _ in vl.prompts]
for lead in ('\nMirror the pool', '\nBottom type',
             '\nAnything to record about the corners',
             '\nHow should the outer corners',
             '\nHow should the inner corner'):
    assert not any(pr.startswith(lead) for pr in lasked), \
        "%s was asked even though the sheet answered it: %r" % (lead, lasked)
assert len(lasked) == 2, (
    "POOL asked %d questions, not just the insertion point and the bottom "
    "gate: %r" % (len(lasked), [q.strip() for q in lasked]))
vl2 = stubbed(with_pool=True)
vl2.run('c:POOL',
        ["Insquare", "L", (0.0, 0.0, 0.0),
         480.0, 180.0, 240.0, 120.0, 240.0, 300.0,
         "Yes", "Cut", 12.0, "Square", "No", "No"])
lb = snapshot(vl2)
assert la == lb, (
    "the L sheet drew a different pool: %d entities from the chart, %d from "
    "the prompts" % (len(la), len(lb)))
# and the bottom type really is withheld, whatever the popup is set to
vl.loads('(setq lzf:*chart* (lzf:chart "L"))'
         '(setq lzf:*vals* nil lzf:*cvals* nil lzf:*pvals* nil)'
         '(setq t:*lf* (lzf:form "L" nil "Wedge"))')
lf = dict(pair(p2) for p2 in vl.globals['t:*lf*'])
assert 'btype' not in lf, \
    "POOL asks no bottom type on an L -- it must not be sent: %r" % lf
vl.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))'
         '(setq t:*rf* (lzf:form "Rectangle" nil "Wedge"))')
rf = dict(pair(p2) for p2 in vl.globals['t:*rf*'])
assert str(rf.get('btype')) == 'Wedge', \
    "every other chart still sends its bottom type: %r" % rf
print("   %d entities, identical from the chart and from the command line;"
      % len(la))
print("   mirror and both corner rows off the sheet, btype withheld")


# --------------------------------------------------------------------
# Round, end to end: the newest chart actually drives POOL.
# --------------------------------------------------------------------
# A chart is only worth having if POOL accepts what it collects.  The
# keys check above says the letters map to real questions; this says
# the whole set drives a drawing and leaves POOL with nothing to ask
# but the two things a form never sends -- where to put it, and whether
# there is a bottom.
print("== a round pool, drawn from the chart's own keys ==")
rv = VM()
rv.load(POOL)
ROUND = """\'((shape . "ROUnd") (insq . "Insquare") (btype . "Wedge")
              (b . 360.0) (h . 40.0) (g . 90.0) (f . 140.0)
              (m . 90.0) (l . 180.0) (k . 90.0)
              (c . 42.0) (d . 72.0))"""
rv.eval(parse_all("(setq pool:*form* %s)" % ROUND)[0])
rv.run('c:POOL', [(0.0, 0.0, 0.0), "Yes"])
drawn = [e for e in rv.entities if e not in rv.deleted]
assert drawn, "a round pool from the form drew nothing"
left = [p.strip() for p, _ in rv.prompts]
assert len(left) == 2, (
    "POOL still had to ask %d questions, not 2: %r" % (len(left), left))
assert 'Insertion base point' in left[0], left
assert 'Add pool bottom' in left[1], left
# and every key the chart offers is one POOL really asks for
rv2 = VM()
rv2.load(LSP)
rv2.loads('(setq test:*rk* (lzf:keys (lzf:chart "ROUnd")))')
rk = [str(x) for x in rv2.globals['test:*rk*']]
for need in ('b', 'a', 'h', 'g', 'f', 'e', 'w', 'm', 'l', 'k', 'c', 'd', 'c2'):
    assert need in rk, "the Round chart lost %s" % need
print("   %d entities; POOL asked only for the insertion point and the"
      % len(drawn))
print("   bottom gate -- the two things a form never sends")


# --------------------------------------------------------------------
# Octagon, end to end.
# --------------------------------------------------------------------
# POOL reaches the octagon through (pool:grecflow t), so its letters are
# the grecian square-hopper set -- and S2 is one POOL really asks for,
# which this found the hard way: the first run of it answered the S2
# prompt with the word meant for the bottom gate.
print("== an octagon, drawn from the chart's own keys ==")
ov = VM()
ov.load(POOL)
OCT = """\'((shape . "OCtagon") (insq . "Insquare") (imeth . "Overall")
            (htype . "Square") (btype . "Wedge")
            (b . 300.0) (a . 300.0) (ss . 60.0) (tt . 180.0) (s1 . 60.0)
            (vv . 180.0) (s2 . 85.0) (h . 40.0) (g . 70.0) (f . 110.0)
            (e . 80.0) (m . 70.0) (l . 160.0) (k . 70.0)
            (c . 42.0) (d . 72.0))"""
ov.eval(parse_all("(setq pool:*form* %s)" % OCT)[0])
ov.run('c:POOL', [(0.0, 0.0, 0.0), "No", "Yes"])
odrawn = [e for e in ov.entities if e not in ov.deleted]
assert odrawn, "an octagon from the form drew nothing"
oleft = [p.strip() for p, _ in ov.prompts]
assert len(oleft) == 3, (
    "POOL still had to ask %d questions, not 3: %r" % (len(oleft), oleft))
assert 'Insertion base point' in oleft[0], oleft
assert 'corners' in oleft[1], oleft
assert 'Add pool bottom' in oleft[2], oleft
# no dimension was re-asked: the chart answered every letter it draws
for lead in ('B -', 'S -', 'T -', 'S1 -', 'A -', 'V -', 'S2 -',
             'H -', 'G -', 'F -', 'E -', 'M -', 'L -', 'K -'):
    assert not any(q.startswith(lead) for q in oleft), \
        "%s was asked again despite being on the chart: %r" % (lead, oleft)
ov2 = VM()
ov2.load(LSP)
ov2.loads('(setq test:*ok* (lzf:keys (lzf:chart "OCtagon")))')
ok = [str(x) for x in ov2.globals['test:*ok*']]
for need in ('b', 'ss', 'tt', 's1', 'a', 'vv', 's2', 'h', 'g', 'f', 'e',
             'm', 'l', 'k', 'c', 'd', 'c2'):
    assert need in ok, "the Octagon chart lost %s" % need
print("   %d entities; POOL asked only for the insertion point, the"
      % len(odrawn))
print("   corners and the bottom gate -- no dimension asked twice")


# --------------------------------------------------------------------
# LAZTXT: the pool drawn out of tiles, with the boxes inside it.
# --------------------------------------------------------------------
# The LAZASCII probe killed character art -- the dialog font is
# proportional -- but showed the half that works: tiles with declared
# widths line up because the alignment comes from the tiles, not the
# glyphs. A boxed cluster goes one better and draws a REAL etched
# border, so the outline is straight by construction.
print("== end to end: an oasis sheet draws what OASIS's questions draw ==")
# The same reference pool -- 40'-0" x 20'-0", 8'/11'/9' bulges and
# 6'/3'/5' tangent radii, the drawing OASIS itself was written from --
# once through the chart and once through the prompts.  A tab takes the
# form to the oasis page, the boxes are typed the way a user types
# them, and Insert has to reach OASIS rather than POOL.
OAS_TYPE = [('tab_OACenter', ''), ('detail', '1'),
            ('x', '480'), ('y', '240'), ('rl', '96'), ('rt', '132'),
            ('rr', '108'), ('ftl', '72'), ('ftr', '36'), ('fbc', '60')]
OAS_TYPED = [480.0, 240.0, 96.0, 132.0, 108.0, 72.0, 36.0, 60.0]

ov = stubbed(with_pool=True, with_oasis=True)
ov.loads("(setq stub:*rcs* '(4 1))")
ov.loads('(setq stub:*type* \'(%s))'
         % ' '.join('("%s" "%s")' % (k, v) for k, v in OAS_TYPE))
try:
    ov.run('c:LAZFORM', [(0.0, 0.0, 0.0), None])
except LispError as e:
    raise AssertionError("oasis form run: %s" % e) from None
a = snapshot(ov)
assert a, "the oasis form run drew nothing"
assert not ov.globals.get('oasis:*form*'), "oasis:*form* survived the run"
assert not ov.globals.get('oasis:*fkey*'), "oasis:*fkey* survived the run"
asked = [pr for pr, _ in ov.prompts]
assert len(asked) == 2, (
    "an oasis sheet should leave only the base point and the pool-bottom "
    "gate, and %d question(s) were asked: %r" % (len(asked), asked))
assert not ov.globals.get('pool:*form*'), \
    "an oasis sheet handed its answers to POOL"

ov2 = stubbed(with_pool=True, with_oasis=True)
try:
    ov2.run('c:OASIS',
            ['Center', 'Simple', (0.0, 0.0, 0.0)] + OAS_TYPED + [None])
except LispError as e:
    raise AssertionError("oasis prompt run: %s" % e) from None
b = snapshot(ov2)
assert a == b, (
    "the oasis sheet drew a different pool: %d entities from the chart, "
    "%d from the prompts" % (len(a), len(b)))
print("   %d entities, identical from the chart and from the command line;"
      % len(a))
print("   only the base point and the bottom gate were asked")

# a dead box does not travel here either: a Simple run is never asked
# how far its hump is off centre, so a number typed into OFF is greyed
# and withheld rather than quietly reaching the solver
ov3 = stubbed(with_pool=True, with_oasis=True)
ov3.loads("(setq stub:*rcs* '(4 1))")
ov3.loads('(setq stub:*type* \'(%s))'
          % ' '.join('("%s" "%s")' % (k, v)
                     for k, v in OAS_TYPE + [('off', '36')]))
ov3.run('c:LAZFORM', [(0.0, 0.0, 0.0), None])
assert snapshot(ov3) == a, \
    "OFF travelled on a Simple run and moved the hump"
print("   and a box the run never asks about is withheld, not sent")

# the same box on the TOP-RIGHT sheet, where the third bulge to place is
# the corner one and the shift brings it in off the right-hand bound,
# leaving it held by the top wall alone
TR_TYPE = [('tab_OATopRight', ''), ('detail', '2'), ('off', '-60'),
           ('x', '443'), ('y', '344'), ('rl', '108'), ('rt', '96'),
           ('rr', '108'), ('ftl', '84'), ('ftr', '90'), ('fbc', '120')]
TR_TYPED = [443.0, 344.0, 108.0, 96.0, 108.0, -60.0, 84.0, 90.0, 120.0]
ov6 = stubbed(with_pool=True, with_oasis=True)
ov6.loads("(setq stub:*rcs* '(4 1))")
ov6.loads('(setq stub:*type* \'(%s))'
          % ' '.join('("%s" "%s")' % (k, v) for k, v in TR_TYPE))
ov6.run('c:LAZFORM', [(0.0, 0.0, 0.0), None])
tr = snapshot(ov6)
assert tr, "the top-right sheet drew nothing"
assert len(ov6.prompts) == 2, (
    "the placement was asked for at the command line even though the sheet "
    "answered it: %r" % [pr for pr, _ in ov6.prompts])
ov7 = stubbed(with_pool=True, with_oasis=True)
ov7.run('c:OASIS', ['TopRight', 'Complex', (0.0, 0.0, 0.0)] + TR_TYPED
        + [None])
assert tr == snapshot(ov7), (
    "the placed corner bulge did not come off the sheet: %d entities from "
    "the chart, %d from the prompts" % (len(tr), len(snapshot(ov7))))
print("   and a corner bulge 60 in off the right bound, off the top-right"
      " sheet, %d entities" % len(tr))

# the routing itself: a POOL page reaches POOL and an oasis page OASIS,
# and neither can reach the other
ov4 = stubbed(with_pool=True, with_oasis=True)
ov4.loads("(setq stub:*rcs* '(4 1))")
ov4.loads('(setq stub:*type* \'(("tab_OAKidney" "") ("sub" "1")'
          ' ("detail" "1") ("x" "388") ("y" "214") ("rt" "324")'
          ' ("fbc" "48")))')
ov4.run('c:LAZFORM', [(0.0, 0.0, 0.0), None])
ov4.loads('(setq t:*ran* lzf:*ranchart*)')
assert str(ov4.globals['t:*ran*']) == 'OAKidney', \
    "the accepted page was not recorded: %r" % ov4.globals['t:*ran*']
kid = [e for e in snapshot(ov4)]
assert kid, "the kidney sheet drew nothing"
ov5 = stubbed(with_pool=True, with_oasis=True)
ov5.run('c:OASIS', ['Kidney', 'True', 'Simple', (0.0, 0.0, 0.0),
                    388.0, 214.0, 324.0, 48.0, None])
assert kid == snapshot(ov5), "the kidney sheet drew a different pool"
print("   a kidney off its own sheet, sub-type and all, %d entities"
      % len(kid))


print("== LAZTXT: a pool made of nested boxes, fields inside it ==")
tv = fresh()
tv.loads('(setq test:*tx* (lzf:dcl-txt (lzf:chart "Rectangle")))')
tx = [str(l) for l in tv.globals['test:*tx*']]
body = '\n'.join(tx)

# it is a dialog, and it balances
assert tx[0] == 'lazform_txt : dialog {', tx[0]
depth = 0
for line in tx:
    assert line.count('"') % 2 == 0, "odd quotes: %r" % line
    depth += line.count('{') - line.count('}')
assert depth == 0, "the text view does not balance"

# the pool is a real box with the hopper nested inside it -- that is
# the whole idea, so it is asserted rather than assumed
assert body.count(': boxed_column {') >= 3, body
assert 'label = "Hopper";' in body, "no hopper box"
i_pool = body.index('label = "Rectangle";')
i_hop = body.index('label = "Hopper";')
assert i_pool < i_hop, "the hopper is not inside the pool box"

# every key the chart offers has a box here too, or the view collects
# less than the chart it claims to mirror
keys = [str(x) for x in
        (tv.loads('(setq test:*k* (lzf:keys (lzf:chart "Rectangle")))')
         or tv.globals['test:*k*'])]
boxed = set(re.findall(r'edit_box \{ key = "([^"]+)"', body))
missing = [k for k in keys if k not in boxed]
assert not missing, "the text view has no box for %r" % missing

# WIDTH.  Same rule as everywhere else in this file: DCL does not
# scroll, so a line wider than the screen is a dialog that will not
# open.  The label plus its edit box is what sets it.
widest = 0
for lb, w in re.findall(r'label = "([^"]*)"; edit_width = (\d+)', body):
    widest = max(widest, len(lb) + int(w) + 8)
for lb in re.findall(r': text \{ label = "([^"]*)"', body):
    widest = max(widest, len(lb) + 4)
assert widest <= 90, (
    "the text view is about %d cells wide, over 90 -- it would not open"
    % widest)
print("   %d boxes, hopper nested in the pool, widest line ~%d cells"
      % (len(boxed), widest))

# and it drives POOL: same alist, same command, no image tile anywhere
assert ': image' not in body, \
    "the text view has an image tile in it -- the point is that it has none"
tv.loads('(setq lzf:*chart* (lzf:chart "Rectangle"))')
tv.loads('(setq lzf:*vals* nil)')
tv.loads('(lzf:put "tp" "240") (lzf:put "le" "120") (lzf:put "h" "30")')
tv.loads('(setq test:*tf* (lzf:form "Rectangle" T "Wedge"))')
tf = dict((str(pr.a), pr.b) for pr in tv.globals['test:*tf*']
          if hasattr(pr, 'a'))
for k in ('tp', 'le', 'h', 'shape', 'insq', 'btype'):
    assert k in tf, "the text view lost %s on the way to POOL: %r" % (k, tf)
print("   what it collects reaches POOL as the same alist LAZFORM sends")


# --------------------------------------------------------------------
# The pool art the probe carries, and the tiles that would show it.
# --------------------------------------------------------------------
# Section 5 of LAZASCII asks the one question sections 1-4 left open: a
# TEXT tile is proportional, but a list_box is a different control, and
# if it happens to be fixed-pitch the pool can be drawn in characters
# after all -- retained, and the real shape rather than a rectangle
# standing in for one.
print("== the probe carries the pool art, intact ==")
av = fresh()
art = [str(l) for l in av.globals['lzf:*poolart*']]
assert len(art) >= 16, "the pool art lost lines: %d" % len(art)
# the backslashes survive the LISP string escaping -- half the slopes
# are drawn with them, and a lost one is a silently broken picture
assert sum(a.count('\\') for a in art) >= 6, \
    "the pool art lost its backslashes: %r" % [a for a in art if '\\' in a]
assert sum(a.count('/') for a in art) >= 6, "the pool art lost its slashes"
# every dimension letter the rectangle chart names is on the picture
# each letter stands alone somewhere on the picture -- H reads as
# "<-H->", B as "--- B ---", so a bare substring test would pass on
# anything and a space-delimited one fails on the arrows
joined = '\n'.join(art)
for letter in ('B', 'A', 'H', 'G', 'F', 'E', 'M', 'L', 'K'):
    assert re.search(r'(?<![A-Za-z])%s(?![A-Za-z])' % letter, joined), \
        "%s is not on the pool art" % letter
widest = max(len(a) for a in art)
av.loads('(setq test:*a* (lzf:dcl-ascii))')
adcl = '\n'.join(str(l) for l in av.globals['test:*a*'])
m = re.search(r'list_box \{ key = "pool"; width = (\d+)', adcl)
assert m, "no pool list box in the probe"
assert int(m.group(1)) >= widest, (
    "the pool list box is %s wide but the art is %d -- it would clip"
    % (m.group(1), widest))
assert 'key = "ruler"' in adcl, "no fixed-pitch ruler beside the pool"
print("   %d lines, widest %d, in a %s-wide list box; letters all present"
      % (len(art), widest, m.group(1)))


print("ALL LAZFORM TESTS PASSED")
