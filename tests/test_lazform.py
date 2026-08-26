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

DX, DY = 520, 376          # a plausible tile size, in pixels
DRAW = {'vec': [], 'fill': [], 'tiles': {}, 'list': [], 'focus': []}


def _reset():
    OPENED.clear()
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


@_b('new_dialog')
def _newdlg(vm, a):
    # 2 args on the first open, 4 once a position is known -- record
    # which, so the position threading is provable
    OPENED.append((str(a[0]), len(a)))
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


def fresh(with_pool=False):
    _reset()
    vm = VM()
    if with_pool:
        vm.load(POOL)
    vm.load(LSP)
    return vm


def stubbed(with_pool=False):
    vm = fresh(with_pool)
    vm.loads(STUB)
    return vm


def lisp_str(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')


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
            assert 0 <= cx - rx and cx + rx <= 1000, \
                "arc of %s leaves the picture sideways: %r" % (key, poly)
            assert 0 <= cy - ry and cy + ry <= 1000, \
                "arc of %s leaves the picture vertically: %r" % (key, poly)
            continue
        pts = [int(v) for v in poly]
        assert len(pts) % 2 == 0 and len(pts) >= 4, poly
        assert all(0 <= v <= 1000 for v in pts), \
            "outline of %s leaves the picture: %r" % (key, poly)
    for d in dims:
        x1, y1, x2, y2 = (int(d[2]), int(d[3]), int(d[4]), int(d[5]))
        assert all(0 <= v <= 1000 for v in (x1, y1, x2, y2)), d
        assert str(d[6]) in ('h', 'v'), d
        assert (y1 == y2) if str(d[6]) == 'h' else (x1 == x2), \
            "%s: a %r dimension must run that way: %r" % (key, str(d[6]), d)
        assert (x1, y1) != (x2, y2), "zero-length dimension: %r" % (d,)
        assert str(d[7]).strip(), "dimension %r has no label" % (d,)
print("   %s, %d chart(s), every dimension keyed, labelled and in bounds"
      % (ver, len(charts)))


print("== the dimension chains close ==")
# POOL resolves H+G+F+E against the pool's overall length and M+L+K
# against its width -- if the drawn chain does not add up to the drawn
# overall, the picture is lying about the measurement it names, and the
# operator reading it off would be misled before POOL ever saw a number.
for c in charts:
    name = str(c[0])
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
# POOL builds its ask items two ways: most flows write
# (list 'key 'KIND "prompt" ...), while the L shapes write
# (list 'key "prompt" 'guide ...) and map the kind on afterwards.  Both
# shapes have to be recognised, or a perfectly good key looks invented.
askseq_keys = set(re.findall(r"\(list '([a-z][a-z0-9]*)\s+'(?:REQ|NAX|ZER|SUG)",
                             pool_src))
askseq_keys |= set(re.findall(r"\(list '([a-z][a-z0-9]*)\s+\"", pool_src))
derived = {'c', 'd', 'c2'}          # the depth asks, keyed off their prompts
wired = {'shape', 'insq', 'btype', 'base'}
total = 0
for c in charts:
    name = str(c[0])
    vm.loads('(setq t:*keys* (lzf:keys (lzf:chart "%s")))' % name)
    ks = [str(x) for x in vm.globals['t:*keys*']]
    for k in ks:
        assert k in askseq_keys or k in derived, (
            "%s: chart key %r is not asked for anywhere in POOL.LSP -- it "
            "would be typed into and dropped on the floor" % (name, k))
    total += len(ks)
    print("   %-10s %2d keys, all of them POOL answer keys" % (name, len(ks)))
print("   %d keys across %d charts" % (total, len(charts)))


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
opens = [o for o in opens if o != 'lazform_ascii : dialog {']
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
    # one image band per stretch between cuts, a wedge row at each cut
    vm.loads('(setq t:*cuts* (lzf:cuts lzf:*chart*))'
             '(setq t:*wk* (lzf:wedge-keys lzf:*chart*))')
    cuts = [int(x) for x in (vm.globals.get('t:*cuts*') or [])]
    wk = [str(x) for x in (vm.globals.get('t:*wk*') or [])]
    for b in range(len(cuts) + 1):
        assert 'chart%d' % b in tilekeys, "%s: no band tile chart%d" % (name, b)
    assert 'chart%d' % (len(cuts) + 1) not in tilekeys, \
        "%s: more band tiles than bands" % name
    # every cut carries at least one wedge box -- a grey strip with
    # nothing in it would cut the drawing for no reason at all
    assert cuts, "%s: no cuts declared" % name
    vm.loads('(setq t:*cd* (mapcar \'(lambda (y) (length (lzf:cutdims '
             'lzf:*chart* y))) (lzf:cuts lzf:*chart*)))')
    for y, n in zip(cuts, [int(x) for x in vm.globals['t:*cd*']]):
        assert n > 0, "%s: cut at %d has no dimension on it" % (name, y)
    # a wedge dim's box is on the chart, so it has NO pick button and
    # NO row in the side column; a column dim has both
    for k in wk:
        assert 'pick_%s' % k not in tilekeys, \
            "%s: wedge dim %s also has a pick button" % (name, k)
    for extra in ('insq', 'btype', 'accept', 'cancel'):
        assert extra in tilekeys, "%s: no %r tile" % (name, extra)
    # a tab for every chart, on every page -- including this one, so the
    # strip does not change width as you move along it
    for c2 in charts:
        assert 'tab_%s' % str(c2[0]) in tilekeys, \
            "%s: no tab for %s" % (name, str(c2[0]))
    # and a letter button for every dimension, keyed off its answer
    for dim in vm.globals['t:*dims*']:
        if str(dim[1]) in wk:
            continue
        assert 'pick_%s' % str(dim[1]) in tilekeys, \
            "%s: dimension %s has no letter button" % (name, str(dim[0]))
    assert text.count('is_cancel = true') == 1
    assert text.count('is_default = true') == 1
    assert ': image_button' not in text, (
        "%s: the chart is an image_button again -- it will be wiped the "
        "first time the mouse crosses it" % name)
    assert re.search(r': image \{ key = "chart0"', text), \
        "%s: no passive chart image tile" % name
    # and the wedge boxes land near their letters: replay the spacer
    # arithmetic and compare each box's centre with its dimension's,
    # in character cells.  Chains pack shoulder to shoulder, so the
    # tolerance is real -- but a box a quarter of the chart away from
    # its letter means the layout maths broke
    vm.loads('(setq t:*alldims* (lzf:dims lzf:*chart*))')
    centers = {str(d[1]): (int(d[2]) + int(d[4])) / 2.0 * 52 / 1000.0
               for d in vm.globals['t:*alldims*']}
    body_lines = d
    pos = None
    expect = False          # a wedge row IMMEDIATELY follows its band
    for line in body_lines:
        t2 = line.strip()
        if re.match(r': image \{ key = "chart\d+"', t2):
            expect = True
            pos = None
        elif expect and t2 == ': row {':
            pos = 0.0
            expect = False
        elif expect:
            expect = False
        elif pos is not None:
            m = re.match(r': spacer \{ width = ([0-9.]+); \}', t2)
            if m:
                pos += float(m.group(1))
                continue
            if t2 == '}':
                pos = None
                continue
            m = re.match(r': edit_box \{ key = "([^"]+)"; label = "([^"]+)"; '
                         r'edit_width = 6', t2)
            if m:
                k, lbl = m.group(1), m.group(2)
                w = len(lbl) + 10.0
                got = pos + w / 2.0
                assert abs(got - centers[k]) <= 6.5, (
                    "%s: wedge box %s centred at %.1f cells, its letter at "
                    "%.1f" % (name, k, got, centers[k]))
                pos += w
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
    wide = sum(len(t) + 6 for t in tabs)
    assert wide <= TAB_BUDGET, (
        "%s: the tab strip is about %d characters wide, over the %d budget "
        "-- a dialog wider than the screen cannot be shown and DCL will not "
        "scroll it: %r" % (str(c[0]), wide, TAB_BUDGET, tabs))
    print("   %-10s %2d lines, %2d tile keys, tab strip ~%d chars"
          % (str(c[0]), len(d), len(tk), wide))

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
# the WEDGE dims draw nothing at all -- their row of the drawing is a
# row of real boxes -- so the value-replaces-letter rule is checked on
# the vertical dims, which still live in the side column and on the
# chart: A ('le') and M ('m')
_reset()
vm.loads('(lzf:put "le" "16\'0\\"") (lzf:put "m" "5\'0\\"") (lzf:redraw)')
vals = [v for v in DRAW['vec'] if v[4] == COLS['val']]
assert vals, "a typed value was not drawn"
# B and H are gone from the picture, replaced by what was typed, so the
# glyph strokes drawn in the outline colour must have gone DOWN even as
# the value strokes appeared
line_now = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
_reset()
vm.loads('(setq lzf:*vals* nil) (lzf:redraw)')
line_blank = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
assert line_now < line_blank, (
    "the letters A and M are still being drawn after being answered "
    "(%d outline strokes vs %d blank)" % (line_now, line_blank))
print("   %d value strokes appear; outline strokes fall %d -> %d"
      % (len(vals), line_blank, line_now))

# and typing into a WEDGE key changes nothing on the chart: its box is
# a real tile sitting on the drawing, not strokes to redraw
_reset()
vm.loads('(setq lzf:*vals* nil) (lzf:redraw)')
base = len(DRAW['vec'])
_reset()
vm.loads('(lzf:put "tp" "240") (lzf:put "h" "48") (lzf:redraw)')
assert len(DRAW['vec']) == base, (
    "typing into a wedge box changed the drawing: %d -> %d strokes"
    % (base, len(DRAW['vec'])))
print("   wedge keys draw nothing -- their boxes are real tiles")


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
vm2.loads('(setq t:*dims* (lzf:dims (lzf:chart "Rectangle")))'
          '(setq t:*wk* (lzf:wedge-keys (lzf:chart "Rectangle")))')
wk2 = {str(x) for x in vm2.globals['t:*wk*']}
for dim in vm2.globals['t:*dims*']:
    k = str(dim[1])
    if k in wk2:
        # a wedge dim's box IS on the drawing -- no pick button at all
        assert 'pick_%s' % k not in wired, \
            "wedge dim %s has a pick callback for a button that " \
            "does not exist" % str(dim[0])
    else:
        assert 'pick_%s' % k in wired, \
            "dimension %s has no letter-button callback" % str(dim[0])
    # but EVERY dim's edit box, wedged or not, harvests what is typed
    assert k in wired, "dimension %s's box has no callback" % str(dim[0])
for c in charts:
    assert 'tab_%s' % str(c[0]) in wired, "no tab callback for %s" % str(c[0])
print("   %d callbacks bound, none on the chart, %d vectors drawn"
      % (len(wired), drew_open))

# clicking a letter must put the caret in that box AND select what is
# there, so the first keystroke replaces rather than appends
# M is a side-column dim (vertical dims cannot be wedged), so it still
# has a letter button to click
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


print("== corners: dropdown, un-greying size box, packing ==")


# an alist pair is a Dot when it has a value and a one-element LIST
# when it does not -- (cons 'g nil) is the list (g)
def pair(p):
    return (str(p.a), p.b) if isinstance(p, Dot) else (str(p[0]), None)


# structure: Rectangle and L carry corner rows, the rest none
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
assert [str(x[0]) for x in vm.globals['lzf:*corners*']] == ['Rectangle', 'L']
print("   Rectangle and L carry corner rows; the others none")

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

# every chart carries the depth rows, or a bottom that asks for them
# would have nowhere to put them -- and the Grecians' gate lists, which
# sit in the same s-expression, must be untouched by that
for ck in [str(c[0]) for c in bv.globals['lzf:*charts*']]:
    bv.loads('(setq test:*e* (lzf:extra (lzf:chart "%s")))' % ck)
    ex = [str(x[0]) for x in bv.globals['test:*e*']]
    for need in ('c', 'd', 'c2'):
        assert need in ex, "%s has no %s box" % (ck, need)
    bv.loads('(setq test:*g* (lzf:gates (lzf:chart "%s")))' % ck)
    g = bv.globals['test:*g*']
    gk = [str(x.a) for x in g] if g else []
    assert not ({'c', 'd', 'c2'} & set(gk)), \
        "%s: a depth leaked into the gates list: %r" % (ck, gk)
print("   all %d charts carry C, D and C2; no gate list disturbed"
      % len(bv.globals['lzf:*charts*']))

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


print("ALL LAZFORM TESTS PASSED")
