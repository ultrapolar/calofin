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
from lispvm import VM, LispError, Dot  # noqa: E402

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
  ;; type into every box the scenario named, the way a user tabbing
  ;; through them would -- through the REAL action expression
  (foreach p stub:*type*
    (if (setq k (assoc (car p) stub:*act*))
      (progn (setq $value (cadr p) $key (car p))
             (eval (read (strcat "(progn " (cadr k) ")"))))))
  stub:*rc*)
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
         'image', 'image_button', 'toggle', 'popup_list'}

vm.loads('(setq t:*all* (lzf:dcl-lines))')
ALL = [str(x) for x in vm.globals['t:*all*']]

# every chart is its own dialog, all of them in one generated file, so
# the page loop can load_dialog once and switch pages without going back
# to disk
opens = [l for l in ALL if l.endswith(' : dialog {')]
names = [l.split(' : ')[0] for l in opens]
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
    for extra in ('chart', 'insq', 'btype', 'accept', 'cancel'):
        assert extra in tilekeys, "%s: no %r tile" % (name, extra)
    # a tab for every chart, on every page -- including this one, so the
    # strip does not change width as you move along it
    for c2 in charts:
        assert 'tab_%s' % str(c2[0]) in tilekeys, \
            "%s: no tab for %s" % (name, str(c2[0]))
    # and a letter button for every dimension, keyed off its answer
    for dim in vm.globals['t:*dims*']:
        assert 'pick_%s' % str(dim[1]) in tilekeys, \
            "%s: dimension %s has no letter button" % (name, str(dim[0]))
    assert text.count('is_cancel = true') == 1
    assert text.count('is_default = true') == 1
    assert ': image_button' not in text, (
        "%s: the chart is an image_button again -- it will be wiped the "
        "first time the mouse crosses it" % name)
    assert re.search(r': image \{ key = "chart"', text), \
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


for c in charts:
    d, tk = check_page(str(c[0]))
    print("   %-10s %2d lines, %2d tile keys, tabs + letter buttons"
          % (str(c[0]), len(d), len(tk)))

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
_reset()
vm.loads('(lzf:put "tp" "32\'0\\"") (lzf:put "h" "4\'0\\"") (lzf:redraw)')
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
    "the letters B and H are still being drawn after being answered "
    "(%d outline strokes vs %d blank)" % (line_now, line_blank))
print("   %d value strokes appear; outline strokes fall %d -> %d"
      % (len(vals), line_blank, line_now))


print("== the page loop: tabs, letter buttons, nothing on the chart ==")
vm2 = stubbed()
vm2.loads('(setq t:*f* (lzf:show "Rectangle"))')
wired = {str(a[0]) for a in (vm2.globals.get('stub:*act*') or [])}
assert 'chart' not in wired, \
    "an action is wired to the chart tile: it would be repainted on hover"
for k in ('btype', 'insq', 'accept', 'cancel'):
    assert k in wired, "%r has no callback" % k
vm2.loads('(setq t:*dims* (lzf:dims (lzf:chart "Rectangle")))')
for dim in vm2.globals['t:*dims*']:
    assert 'pick_%s' % str(dim[1]) in wired, \
        "dimension %s has no letter-button callback" % str(dim[0])
for c in charts:
    assert 'tab_%s' % str(c[0]) in wired, "no tab callback for %s" % str(c[0])
print("   %d callbacks bound, none of them on the chart" % len(wired))

# clicking a letter must put the caret in that box AND select what is
# there, so the first keystroke replaces rather than appends
vm3 = stubbed()
vm3.loads('(setq stub:*type* \'(("pick_g" "")))'
          '(setq t:*f* (lzf:show "Rectangle"))')
modes = [(str(a[0]), int(a[1])) for a in (vm3.globals.get('stub:*mode*') or [])]
assert ('g', 2) in modes, "clicking G did not move the caret to its box: %r" % modes
assert ('g', 3) in modes, "clicking G did not select the box contents: %r" % modes
assert str(vm3.globals.get('lzf:*focus*')) == 'g', \
    "clicking G did not ring G on the chart"
print("   clicking a letter focuses its box, selects it, and rings the chart")

# a tab click reopens on the other chart, and what was typed survives it
vm4 = stubbed()
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
assert [n for _, n in OPENED] == [2, 4], (
    "the reopened page did not carry the position back: %r" % OPENED)
print("   a tab reopens on the other chart, keeps what was typed,")
print("   and puts the dialog back where the user had dragged it")


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
         ('h', '30'), ('f', '180'), ('c', '40'), ('d', '60')]
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
    vm.run('c:LAZFORM',
           [(0.0, 0.0, 0.0)] + CORNERS + CROSS + ["Yes"] + REST)
except LispError as e:
    raise AssertionError("form run: %s" % e) from None
a = snapshot(vm)
assert a, "the form run drew nothing"
assert not vm.globals.get('pool:*form*'), "pool:*form* survived the run"
asked = [pr for pr, _ in vm.prompts]
for gone in ('\nPool shape', '\nBottom type'):
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
print("   and the chart's answers were not asked for again")

print("ALL LAZFORM TESTS PASSED")
