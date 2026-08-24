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


STUB = '''
(setq stub:*rc* 1 stub:*written* nil)
(defun vl-filename-mktemp (pat dir ext) (strcat "/stub/" pat ext))
(defun open (f mode) f)
(defun write-line (s fh) (setq stub:*written* (cons s stub:*written*)) s)
(defun close (fh) t)
(defun load_dialog (f) 7)
(defun new_dialog (name id) t)
(defun term_dialog () nil)
(defun unload_dialog (id) t)
(defun vl-file-delete (f) t)
(defun set_tile (k v) v)
(defun get_tile (k) (cond ((= k "insq") stub:*insq*)
                          ((= k "btype") stub:*btype*)
                          (t "")))
(defun action_tile (k expr)
  (setq stub:*act* (cons (list k expr) stub:*act*)) t)
(defun start_dialog ( / p k)
  ;; type into every box the scenario named, the way a user tabbing
  ;; through them would -- through the REAL action expression
  (foreach p stub:*type*
    (if (setq k (assoc (car p) stub:*act*))
      (progn (setq $value (cadr p) $key (car p))
             (eval (read (strcat "(progn " (cadr k) ")"))))))
  stub:*rc*)
(setq stub:*act* nil stub:*type* nil stub:*insq* "0" stub:*btype* "0")
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


print("== the chart's keys are keys POOL actually asks for ==")
# the whole point of the form is that POOL reads these back; a key POOL
# never asks for would be typed into and silently dropped
pool_src = open(POOL).read()
askseq_keys = set(re.findall(r"\(list '([a-z][a-z0-9]*)\s+'(?:REQ|NAX|ZER|SUG)",
                             pool_src))
derived = {'c', 'd', 'c2'}          # the depth asks, keyed off their prompts
wired = {'shape', 'insq', 'btype', 'base'}
vm.loads('(setq t:*keys* (lzf:keys (lzf:chart "rectangle")))')
for k in [str(x) for x in vm.globals['t:*keys*']]:
    assert k in askseq_keys or k in derived, (
        "chart key %r is not asked for anywhere in POOL.LSP -- it would be "
        "typed into and dropped on the floor" % k)
print("   every chart key is a POOL answer key (%d of them)"
      % len(vm.globals['t:*keys*']))


print("== the generated DCL is well formed ==")
vm.loads('(setq lzf:*chart* (lzf:chart "rectangle"))'
         '(setq t:*dcl* (lzf:dcl-lines))')
dcl = [str(x) for x in vm.globals['t:*dcl*']]
assert dcl[0] == 'lazform : dialog {', dcl[0]
assert dcl[-1] == '}', dcl[-1]
depth = 0
for line in dcl:
    assert line.count('"') % 2 == 0, "odd quotes: %r" % line
    depth += line.count('{') - line.count('}')
    assert depth >= 0, line
assert depth == 0, "unbalanced braces"
text = '\n'.join(dcl)
tilekeys = re.findall(r'key = "([^"]+)"', text)
assert len(tilekeys) == len(set(tilekeys)), "duplicate tile keys"
answer_keys = [str(x) for x in vm.globals['t:*keys*']]
assert set(answer_keys) <= set(tilekeys), \
    set(answer_keys) - set(tilekeys)
for extra in ('chart', 'insq', 'btype', 'accept', 'cancel'):
    assert extra in tilekeys, extra
assert text.count('is_cancel = true') == 1
assert text.count('is_default = true') == 1
# every clause ends in a semicolon and every tile is a real DCL tile
TILES = {'row', 'column', 'boxed_column', 'button', 'text', 'edit_box',
         'image_button', 'toggle', 'popup_list'}
for line in dcl[1:]:
    s = line.strip()
    if s in ('}', 'spacer;'):
        continue
    m = re.match(r': ([a-z_]+) \{', s)
    if m:
        assert m.group(1) in TILES, "unknown tile %r" % m.group(1)
    for clause in re.findall(r'[a-z_]+ = (?:"[^"]*"|[a-z0-9.]+)(;?)', s):
        assert clause == ';', "a DCL clause without its semicolon: %r" % line
print("   %d lines, %d tile keys, one Insert and one Cancel"
      % (len(dcl), len(tilekeys)))


print("== the drawing lands inside the tile, in declared colours ==")
COLS = {}
for name in ('line', 'back', 'dim', 'val', 'hi'):
    COLS[name] = int(vm.globals['lzf:*col-%s*' % name])
vm.loads('(lzf:redraw)')
assert DRAW['vec'], "nothing was drawn"
for v in DRAW['vec']:
    x1, y1, x2, y2, c = v
    assert 0 <= x1 <= DX and 0 <= x2 <= DX, "vector off the tile: %r" % v
    assert 0 <= y1 <= DY and 0 <= y2 <= DY, "vector off the tile: %r" % v
    assert c in COLS.values(), "undeclared colour %r in %r" % (c, v)
for f in DRAW['fill']:
    x, y, w, h, c = f
    assert x >= 0 and y >= 0 and x + w <= DX and y + h <= DY, \
        "fill off the tile: %r" % f
blank = len(DRAW['vec'])
print("   %d vectors, %d fills, all inside %dx%d and all in colour"
      % (blank, len(DRAW['fill']), DX, DY))


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


print("== clicking the picture picks the nearest dimension ==")
vm.loads('(setq lzf:*chart* (lzf:chart "rectangle"))')
for frac_x, frac_y, want in (
        (0.50, 0.175, 'tp'),        # on the B chain across the top
        (0.19, 0.58, 'h'),          # on H
        (0.34, 0.58, 'g'),          # on G
        (0.80, 0.58, 'e'),          # on E
        (0.437, 0.36, 'm')):        # on the M stack
    vm.loads('(setq t:*n* (lzf:nearest %d %d))'
             % (int(frac_x * DX), int(frac_y * DY)))
    got = str(vm.globals['t:*n*'])
    assert got == want, "a click at (%.2f,%.2f) picked %r, expected %r" % (
        frac_x, frac_y, got, want)
print("   five clicks across the chart each land on the right dimension")


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
vm.loads('(setq lzf:*vals* nil)'
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
         % ' '.join('("%s" "%s")' % (k, v) for k, v in TYPED))
vm.loads('(setq stub:*insq* "0")')             # out-of-square
vm.loads('(setq stub:*btype* "2")')            # Wedge, third in the list
try:
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
