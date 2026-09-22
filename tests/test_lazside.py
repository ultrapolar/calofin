"""LAZSIDE: read the section, type the letters beside it, draw it.

The form is LAZFORM's argument applied to the side view alone -- the
longitudinal section on the left as one whole picture, a labelled box
against every letter it carries, and POOLSIDE run from what was typed.

Seven jobs:

1. The three tables it carries -- the run chain, the depth stations and
   the nominal proportions -- are POOLSIDE's OWN, re-read out of
   POOLSIDE.lsp and compared entry for entry.  A copy is a thing that
   drifts; this is what stops it.
2. The generated section is coherent for every bottom type: keys
   unique, per-mille co-ordinates in bounds, dimensions axis-consistent
   and labelled, the floor closing on both walls.
3. Every key the form can send is a key POOLSIDE actually reads --
   grepped out of POOLSIDE.lsp, so a key nothing reads fails here
   rather than being typed into and dropped.
4. The generated DCL is well formed, with one tile per answer, a tab
   per bottom type, and no image_button.
5. The three-state contract, including the one place it differs from
   LAZFORM's -- a DEPTH has no NA.
6. The state line and the one button it holds back: a box that cannot
   be read, and a depth pair POOLSIDE would refuse.
7. END TO END: fill the form in, press Insert, and the section is
   identical entity for entity to the same run answered at the prompts,
   with nothing asked but the base point.

The dialog cannot run here (the VM has no DCL), so the surface is
stubbed exactly as tests/test_lazstep.py does it.

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
LSP = os.path.join(REPO, 'lisp', 'lazside', 'LAZSIDE.lsp')
POOLSIDE = os.path.join(REPO, 'lisp', 'poolside', 'POOLSIDE.lsp')

SHARED = bool(os.environ.get('CALOFIN_LISP_ROOT'))


def lib(local, shared):
    """The name this tier defines: the file's own, or the library's."""
    return shared if SHARED else local


ANSWER = lib('lzv:answer', 'cal:formanswer')
TRIM = lib('lzv:trim', 'cal:trim')

DX, DY = 640, 400                       # the stub tile's pixel extent
OPENED, POS = [], []
DRAW = {'vec': [], 'fill': []}


def _reset():
    OPENED[:] = []
    POS[:] = []
    DRAW['vec'] = []
    DRAW['fill'] = []


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
_b('start_list')(lambda vm, a: None)
_b('add_list')(lambda vm, a: None)
_b('end_list')(lambda vm, a: None)


@_b('new_dialog')
def _newdlg(vm, a):
    OPENED.append((str(a[0]), len(a)))
    if len(a) > 3:
        POS.append([float(v) for v in a[3]])
    vm.globals[lispvm.Sym('stub:*act*')] = None
    return True


STUB = '''
(setq stub:*rc* 0 stub:*written* nil stub:*mode* nil stub:*tiles* nil)
(defun vl-filename-mktemp (pat dir ext) (strcat "/stub/" pat ext))
(defun open (f mode) f)
(defun write-line (s fh) (setq stub:*written* (cons s stub:*written*)) s)
(defun close (fh) t)
(setq stub:*env* nil)
(defun getenv (key / p) (if (setq p (assoc key stub:*env*)) (cdr p)))
(defun setenv (key v)
  (setq stub:*env* (cons (cons key v)
                         (vl-remove (assoc key stub:*env*) stub:*env*)))
  v)
(defun load_dialog (f) 7)
(defun mode_tile (k m) (setq stub:*mode* (cons (list k m) stub:*mode*)) t)
(defun term_dialog () nil)
(defun done_dialog (status) (setq stub:*done* status) (list 120 340))
(defun unload_dialog (id) t)
(defun vl-file-delete (f) t)
(defun set_tile (k v) (setq stub:*tiles* (cons (list k v) stub:*tiles*)) v)
(defun stub:tile (k / p) (if (setq p (assoc k stub:*tiles*)) (cadr p)))
(defun action_tile (k expr)
  (setq stub:*act* (cons (list k expr) stub:*act*)) t)
(defun start_dialog ( / p k)
  (setq stub:*done* nil)
  (foreach p stub:*type*
    (if (and (not stub:*done*) (setq k (assoc (car p) stub:*act*)))
      (progn (setq $value (cadr p) $key (car p))
             (eval (read (strcat "(progn " (cadr k) ")")))
             (if stub:*done*
               (setq stub:*type* (vl-remove p stub:*type*))))))
  (if stub:*done* stub:*done* stub:*rc*))
(setq stub:*act* nil stub:*type* nil)
'''


def fresh(with_poolside=False):
    _reset()
    vm = VM()
    if with_poolside:
        vm.load(POOLSIDE)
    vm.load(LSP)
    return vm


def stubbed(with_poolside=False):
    vm = fresh(with_poolside)
    vm.loads(STUB)
    return vm


def typed(pairs):
    return "(setq stub:*type* '(%s))" % ' '.join(
        '("%s" "%s")' % (k, v) for k, v in pairs)


def pair(p):
    # (key . nil) comes back from the VM as a one-element list, which is
    # what NA looks like on the wire and the case the form exists to send
    if isinstance(p, Dot):
        return (str(p.a), p.b)
    return (str(p[0]), p[1] if len(p) > 1 else None)


vm = fresh()
vm.loads('(setq t:*t* (mapcar (function car) lzv:*types*))')
TYPES = [str(x) for x in vm.globals['t:*t*']]
assert len(TYPES) == 6, TYPES


print("== the three tables are POOLSIDE's own, not a second opinion ==")
# A lisp/ file has to load alone, so LAZSIDE carries a copy of the run
# chain, the depth stations and the nominal proportions.  A copy is a
# thing that drifts, and this is the bargain that stops it: POOLSIDE is
# loaded here beside it and asked the same three questions.
pv = fresh(with_poolside=True)
for ty in TYPES:
    pv.loads('(setq t:*a* (psd:chain "%s")) (setq t:*b* (lzv:chain "%s"))'
             % (ty, ty))
    theirs = [str(c[0]) for c in pv.globals['t:*a*']]
    ours = [str(c[0]) for c in pv.globals['t:*b*']]
    assert theirs == ours, \
        "%s: POOLSIDE measures %r, the form draws %r" % (ty, theirs, ours)
    ours_letters = list(ours)
    pv.loads('(setq t:*a* (psd:depths "%s")) (setq t:*b* (lzv:depths "%s"))'
             % (ty, ty))
    theirs = [str(c) for c in pv.globals['t:*a*']]
    ours = [str(c) for c in pv.globals['t:*b*']]
    assert theirs == ours, \
        "%s: POOLSIDE's stations are %r, the form's %r" % (ty, theirs, ours)
    pv.loads('(setq t:*a* (psd:nominal "%s")) (setq t:*b* (lzv:nominal "%s"))'
             % (ty, ty))
    theirs = [round(float(c), 6) for c in pv.globals['t:*a*']]
    ours = [round(float(c), 6) for c in pv.globals['t:*b*']]
    assert theirs == ours, \
        "%s: POOLSIDE's proportions are %r, the form's %r" % (ty, theirs, ours)
    # ...and there is one more station than there are runs, or the
    # floor has nowhere to put a corner
    pv.loads('(setq t:*n* (length (lzv:depths "%s")))' % ty)
    assert int(str(pv.globals['t:*n*'])) == len(theirs) + 1, \
        "%s: %d runs but %s stations" % (ty, len(theirs), pv.globals['t:*n*'])
    # the form key a letter is stored under is POOLSIDE's own spelling
    for ltr in ours_letters:
        pv.loads('(setq t:*k* (psd:key "%s")) (setq t:*v* (lzv:key "%s"))'
                 % (ltr, ltr))
        assert str(pv.globals['t:*k*']) == str(pv.globals['t:*v*']), \
            "%s: POOLSIDE stores %s as %r, the form as %r" \
            % (ty, ltr, pv.globals['t:*k*'], pv.globals['t:*v*'])
print("   %d bottom types x chain, stations, proportions and key spelling"
      % len(TYPES))


print("== the section is coherent, for every bottom type ==")
for ty in TYPES:
    vm.loads('(setq t:*c* (lzv:chart "%s"))' % ty)
    c = vm.globals['t:*c*']
    assert str(c[0]) == ty, c[0]
    flat = [int(x) for x in c[2][0]]
    pts = list(zip(flat[0::2], flat[1::2]))
    for x, y in pts:
        assert 0 <= x <= 1000 and 0 <= y <= 1000, \
            "%s: (%d,%d) is outside the picture" % (ty, x, y)
    assert pts[0] == pts[-1], "%s: the section does not close: %r" % (ty, pts)
    # both walls stand at the waterline, and the floor between them only
    # ever goes down
    vm.loads('(setq t:*w* lzv:*water-y*) (setq t:*x0* lzv:*sec-x0*)'
             '(setq t:*x1* lzv:*sec-x1*)')
    wy = int(str(vm.globals['t:*w*']))
    x0, x1 = int(str(vm.globals['t:*x0*'])), int(str(vm.globals['t:*x1*']))
    assert pts[0] == (x0, wy), "%s: the section does not start at the left wall" % ty
    assert (x1, wy) in pts, "%s: no right wall at the waterline" % ty
    for x, y in pts:
        assert y >= wy, "%s: (%d,%d) is above the waterline" % (ty, x, y)
    # the dimensions
    keys, letters = [], []
    for d in c[3]:
        letter, key = str(d[0]), str(d[1])
        x1d, y1d, x2d, y2d, side = (int(d[2]), int(d[3]), int(d[4]),
                                    int(d[5]), str(d[6]))
        keys.append(key)
        letters.append(letter)
        assert side in ('h', 'v'), "%s/%s: side %r" % (ty, key, side)
        if side == 'h':
            assert y1d == y2d and x1d != x2d, "%s/%s is not horizontal" % (ty, key)
        else:
            assert x1d == x2d and y1d != y2d, "%s/%s is not vertical" % (ty, key)
        for v in (x1d, y1d, x2d, y2d):
            assert 0 <= v <= 1000, "%s/%s: %d out of bounds" % (ty, key, v)
        assert str(d[7]).strip(), "%s/%s has no label" % (ty, key)
    assert len(keys) == len(set(keys)), \
        "%s: two dimensions share a key: %r" % (ty, keys)
    assert len(letters) == len(set(letters)), \
        "%s: two dimensions share a letter: %r" % (ty, letters)
    assert 'b' in keys and 'c' in keys and 'd' in keys, keys
    assert ('c2' in keys) == (ty == 'SHallow'), \
        "%s: C2 belongs to the SHallow break alone: %r" % (ty, keys)
    # a depth dimension's FOOT is the floor corner it measures.  Stand
    # it off by a hair and it misses: on a Wedge and a SLope the floor
    # is already climbing one per-mille past the deep station, so the
    # line would hang below the floor it is measuring to.
    floor = set(pts)
    for d in c[3]:
        if str(d[1]) in ('d', 'c2'):
            foot = (int(d[4]), int(d[5]))
            assert foot in floor, \
                "%s: %s measures down to %r, which is not on the floor" \
                % (ty, str(d[0]), foot)
    # the run chain spans the whole section, end to end and gap-free
    vm.loads('(setq t:*ch* (lzv:chain "%s"))' % ty)
    runs = [str(r[0]) for r in vm.globals['t:*ch*']]
    spans = [(int(d[2]), int(d[4])) for d in c[3]
             if str(d[0]) in runs and str(d[6]) == 'h']
    assert len(spans) == len(runs), "%s: %r vs %r" % (ty, spans, runs)
    assert spans[0][0] == x0 and spans[-1][1] == x1, \
        "%s: the chain does not span the section: %r" % (ty, spans)
    for a, b in zip(spans, spans[1:]):
        assert a[1] == b[0], "%s: a gap in the chain at %r" % (ty, a)
    print("   %-8s %d runs, %d dimensions, %d-point section"
          % (ty, len(runs), len(c[3]), len(pts)))


print("== every key the form can send is a key POOLSIDE reads ==")
src = open(POOLSIDE, encoding='utf-8').read()
read_keys = set(re.findall(r"psd:f(?:has|num|kw|take)\s+'([a-z0-9]+)", src))
# the run letters are read through psd:key, off the chain table, so the
# grep above cannot see them -- but the chain table is right there
for m in re.findall(r'\(list\s+"([A-Z][0-9]?)"\s+\'(?:NAX|ZER|REQ)', src):
    read_keys.add(m.lower())
read_keys |= set(re.findall(r"psd:sq ans '([a-z0-9]+)", src))
for ty in TYPES:
    vm.loads('(setq lzv:*type* "%s") (setq lzv:*chart* (lzv:chart "%s"))'
             % (ty, ty))
    vm.loads('(setq lzv:*vals* nil) (setq t:*k* (lzv:keys lzv:*chart*))')
    for k in [str(x) for x in vm.globals['t:*k*']]:
        assert k in read_keys, (
            "%s: the form can send %r, which nothing in POOLSIDE.lsp reads -- "
            "it would be typed into and dropped on the floor" % (ty, k))
assert 'style' in read_keys, "POOLSIDE does not read the bottom type"
print("   %d key(s) read by psd:f*, every form key among them" % len(read_keys))


print("== the generated DCL is well formed, one tile per answer ==")
TILES = {'row', 'column', 'boxed_column', 'button', 'text', 'edit_box',
         'image', 'image_button', 'popup_list', 'spacer'}
dv = fresh()
dv.loads('(setq t:*all* (lzv:dcl-lines))')
ALL = [str(x) for x in dv.globals['t:*all*']]
depth = 0
for line in ALL:
    assert line.count('"') % 2 == 0, "odd quotes: %r" % line
    depth += line.count('{') - line.count('}')
    assert depth >= 0, line
assert depth == 0, "unbalanced braces"
opens = [ln.split(' : ')[0] for ln in ALL if ln.endswith(' : dialog {')]
assert len(opens) == len(TYPES) == len(set(opens)), opens


def slice_dialog(name):
    i = ALL.index(name + ' : dialog {')
    d = 0
    for j in range(i, len(ALL)):
        d += ALL[j].count('{') - ALL[j].count('}')
        if d == 0:
            return ALL[i:j + 1]
    raise AssertionError("%s never closes" % name)


LINE_BUDGET = 96
for ty in TYPES:
    dv.loads('(setq t:*n* (lzv:dlgname "%s"))' % ty)
    page = slice_dialog(str(dv.globals['t:*n*']))
    text = '\n'.join(page)
    assert page[1].strip().startswith('label = '), \
        "%s: the label is not first inside the dialog" % ty
    tk = re.findall(r'key = "([^"]+)"', text)
    assert len(tk) == len(set(tk)), \
        "%s: duplicate tile keys: %r" % (ty, sorted(k for k in tk if tk.count(k) > 1))
    assert text.count('is_cancel = true') == 1, ty
    assert text.count('is_default = true') == 1, ty
    assert ': image_button' not in text, (
        "%s: an image_button -- it repaints on hover and a DCL image tile "
        "is not retained, so the drawing would vanish the first time the "
        "cursor crossed it" % ty)
    assert re.search(r': image \{ key = "chart"', text), \
        "%s: no passive chart image tile" % ty
    for line in page[1:]:
        t = line.strip()
        m = re.match(r': ([a-z_]+) \{', t)
        if m:
            assert m.group(1) in TILES, "%s: unknown tile %r" % (ty, m.group(1))
        for clause in re.findall(r'[a-z_]+ = (?:"[^"]*"|[a-z0-9.\-]+)(;?)', t):
            assert clause == ';', "%s: a DCL clause without its semicolon: %r" % (ty, line)
    # a tab for every bottom type, and this page's own is not a way out
    for other in TYPES:
        assert 'tab_%s' % other in tk, "%s: no tab for %s" % (ty, other)
    assert re.search(r'key = "tab_%s"; label = "[^"]*"; is_enabled = false;' % ty,
                     text), "%s: its own tab is still offered" % ty
    # one box per dimension, each with its letter as a button
    dv.loads('(setq t:*c* (lzv:chart "%s"))' % ty)
    keys = [str(d[1]) for d in dv.globals['t:*c*'][3]]
    for k in keys:
        assert k in tk, "%s: %r has no box" % (ty, k)
        assert 'pick_%s' % k in tk, "%s: %r has no letter button" % (ty, k)
    for extra in ('accept', 'cancel', 'recall', 'state'):
        assert extra in tk, "%s: no %r tile" % (ty, extra)
    # DCL does not scroll: a labelled line wider than the screen is a
    # dialog that will not open
    for line in page:
        t = line.strip()
        m = re.search(r'label = "([^"]*)"', t)
        if not m:
            continue
        mw = re.search(r'(?<![_a-z])width = (\d+);', t)
        if mw:
            assert len(m.group(1)) <= int(mw.group(1)), (
                "%s: a %d-character label in a %s-cell tile: %r"
                % (ty, len(m.group(1)), mw.group(1), t))
            continue
        w = len(m.group(1)) + 4
        m2 = re.search(r'edit_width = (\d+)', t)
        if m2:
            w += int(m2.group(1)) + 4
        assert w <= LINE_BUDGET, (
            "%s: a line about %d cells wide, over the %d budget: %r"
            % (ty, w, LINE_BUDGET, t))
print("   %d dialogs, balanced, one tile per key, %d tabs each"
      % (len(opens), len(TYPES)))


print("== the drawing lands inside the tile, in declared colours ==")
COLS = {}
for name, role in (('line', None), ('back', None), ('dim', 'dim'),
                   ('val', None), ('hi', 'hi')):
    knob = lib('lzv:*col-%s*' % name, 'cal:*imgcol-%s*' % name)
    if role is None:
        dv.loads('(setq t:*v* %s)' % knob)
    else:
        dv.loads('(setq t:*v* (%s %s (quote %s)))'
                 % (lib('lzv:ink', 'cal:ink'), knob, role))
    COLS[name] = int(str(dv.globals['t:*v*']))
for ty in TYPES:
    _reset()
    dv.loads('(setq lzv:*type* "%s" lzv:*vals* nil lzv:*focus* nil)' % ty)
    dv.loads('(setq lzv:*chart* (lzv:chart "%s")) (lzv:redraw)' % ty)
    assert DRAW['vec'], "%s: the section drew nothing" % ty
    for x1, y1, x2, y2, col in DRAW['vec']:
        for v, hi in ((x1, DX), (x2, DX), (y1, DY), (y2, DY)):
            assert 0 <= v <= hi, "%s: a vector at %d, outside 0..%d" % (ty, v, hi)
        assert col in COLS.values(), \
            "%s: a vector in colour %d, which the file does not declare" % (ty, col)
# the value replaces the letter: type a number and the strokes change
_reset()
dv.loads('(setq lzv:*type* "Normal" lzv:*vals* nil lzv:*focus* nil)')
dv.loads('(setq lzv:*chart* (lzv:chart "Normal")) (lzv:redraw)')
plain = len([v for v in DRAW['vec'] if v[4] == COLS['val']])
assert plain == 0, "a value colour was used with nothing typed"
_reset()
dv.loads('(lzv:put "b" "40\'") (lzv:redraw)')
assert [v for v in DRAW['vec'] if v[4] == COLS['val']], \
    "a typed value is not drawn in the value colour"
print("   every vector inside the tile, in a declared colour;")
print("   a typed value replaces its letter on the picture")


print("== the three states, and the one place a DEPTH differs ==")
sv = fresh()
sv.loads('(setq lzv:*type* "SHallow" lzv:*vals* nil)')
sv.loads('(setq lzv:*chart* (lzv:chart "SHallow"))')
sv.loads('(lzv:put "b" "40\'") (lzv:put "h" "NA") (lzv:put "g" "")'
         '(lzv:put "f" "rubbish") (lzv:put "c" "42") (lzv:put "d" "96")'
         '(lzv:put "c2" "NA")')
sv.loads('(setq t:*f* (lzv:form))')
form = dict(pair(p) for p in sv.globals['t:*f*'])
assert str(form['style']) == 'SHallow', "the bottom type must travel"
assert abs(float(form['b']) - 480.0) < 1e-9, form
assert 'h' in form and form['h'] is None, \
    "NA in a RUN must travel as nil -- it means read it back off B"
assert 'g' not in form, "an empty box must not be sent"
assert 'f' not in form, "a typo must not be sent"
assert 'c2' not in form, (
    "NA in a DEPTH must count as an empty box: POOLSIDE has no NA for C, D "
    "or C2, so nil there is an answer it cannot use")
sv.loads('(setq t:*u* (lzv:unreadable))')
BAD = [str(x) for x in sv.globals['t:*u*']]
assert BAD == ['f', 'c2'], BAD
print("   empty asks, NA in a run travels as nil, a typo asks,")
print("   and NA in a depth is an empty box that is named on the line")


print("== the state line, and the one button it holds back ==")
rv = stubbed()
rv.loads('(setq lzv:*type* "Normal" lzv:*vals* nil)')
rv.loads('(setq lzv:*chart* (lzv:chart "Normal"))')


def state(v):
    v.loads('(setq t:*s* (lzv:state))')
    return str(v.globals['t:*s*'])


def accept_mode(v):
    modes = [(str(a[0]), int(a[1])) for a in (v.globals.get('stub:*mode*') or [])]
    hits = [m for k, m in modes if k == 'accept']
    assert hits, "restate never touched the button: %r" % modes
    return hits[0]


rv.loads('(setq t:*l* (lzv:livekeys))')
LIVE = [str(x) for x in rv.globals['t:*l*']]
assert state(rv).startswith('Nothing filled yet'), state(rv)
assert 'base point' in state(rv), \
    "the state line does not say what stays in the drawing: %r" % state(rv)
rv.loads('(lzv:put "b" "480")')
assert state(rv).startswith('1 of %d boxes filled' % len(LIVE)), state(rv)
# a box is named by the LETTER the picture shows, not by its key
rv.loads('(setq t:*t* (lzv:tagof "c2"))')
rv.loads('(lzv:put "h" "nope")')
assert state(rv) == ('H is not a measurement - type a number, or NA, '
                     'or clear it.'), state(rv)
rv.loads('(lzv:put "h" "36") (lzv:put "c" "NA")')
assert state(rv) == ('C is NA, and a depth has no NA - type a number, or '
                     'clear it.'), state(rv)
# ...and a typo in a depth is told the same thing a different way: NA is
# not on offer there, so it is not suggested
rv.loads('(lzv:put "c" "wide")')
assert state(rv) == ('C is not a measurement - a depth takes a number or an '
                     'empty box.'), state(rv)
rv.loads('(lzv:put "c" "42")')

# THE DEPTH PAIR POOLSIDE WOULD REFUSE.  It loops at the prompt until
# they agree, which is the wrong thing to hand a sheet to.
rv.loads('(lzv:put "d" "36")')
assert state(rv).startswith('D must be deeper than C'), state(rv)
rv.loads('(setq stub:*mode* nil) (lzv:restate)')
assert accept_mode(rv) == 1, "Insert was live with D shallower than C"
rv.loads('(lzv:put "d" "96")')
rv.loads('(setq stub:*mode* nil) (lzv:restate)')
assert accept_mode(rv) == 0, "a good depth pair did not let Insert through"
# ...and C2 between them, on the sheet that has one
cv = stubbed()
cv.loads('(setq lzv:*type* "SHallow" lzv:*vals* nil)')
cv.loads('(setq lzv:*chart* (lzv:chart "SHallow"))')
cv.loads('(lzv:put "c" "42") (lzv:put "d" "96") (lzv:put "c2" "120")')
assert state(cv).startswith('C2 must be between C and D'), state(cv)
cv.loads('(lzv:put "c2" "60")')
assert not state(cv).startswith('C2 must'), state(cv)
cv.loads('(setq stub:*mode* nil) (lzv:restate)')
assert accept_mode(cv) == 0, "a break between C and D did not let Insert through"
# ...and NOWHERE ELSE.  lzv:*vals* is keyed across the whole run so a
# letter both floors carry survives a tab, which means C2 -- a letter
# only SHallow carries -- is still in the store after tabbing off it.
# lzv:form sends the live keys alone, so that value cannot reach
# POOLSIDE; weighing it anyway greyed Insert on a Normal over a box the
# page does not show, with nothing on the sheet the drafter could
# change to clear it.
cv.loads('(lzv:put "c2" "20")')
assert state(cv).startswith('C2 must be between C and D'), state(cv)
cv.loads('(setq lzv:*type* "Normal") (setq lzv:*chart* (lzv:chart "Normal"))')
cv.loads('(setq t:*l* (lzv:livekeys))')
assert 'c2' not in [str(x) for x in cv.globals['t:*l*']], \
    "a Normal sheet grew a C2 box"
assert not state(cv).startswith('C2 must'), \
    "a C2 left on the SHallow tab is judged on a sheet with no C2: %r" \
    % state(cv)
cv.loads('(setq stub:*mode* nil) (lzv:restate)')
assert accept_mode(cv) == 0, \
    "Insert stayed grey on a Normal over a C2 the form would never send"
cv.loads('(setq t:*f* (lzv:form))')
assert not [p for p in cv.globals['t:*f*'] if str(p.a) == 'c2'], \
    "c2 travelled off a sheet that has no C2 box"
# a sheet with every box answered says so, and says what is left
for k in LIVE:
    rv.loads('(lzv:put "%s" "24")' % k)
rv.loads('(lzv:put "c" "42") (lzv:put "d" "96")')
full = state(rv)
assert full.startswith('All %d boxes filled' % len(LIVE)), full
assert 'only for the base point' in full, full
print("   %d boxes, named by their letters; the depth pair POOLSIDE would"
      % len(LIVE))
print("   refuse is refused here instead, and it greys Insert -- on the")
print("   sheet in front of you, never on a letter another tab carries")


print("== Recall last: the sheet you just filled in, back in it ==")
rc = stubbed()
rc.loads('(defun vl-registry-write (k v s) (setq t:*wv* v t:*ws* s) s)')
rc.loads('(defun vl-registry-read (k v)'
         ' (if (and t:*ws* (= v t:*wv*)) t:*ws* (exit)))')
rc.loads('(setq t:*ws* nil t:*wv* nil)')
rc.loads('(setq lzv:*type* "Normal" lzv:*vals* nil)')
rc.loads('(setq lzv:*chart* (lzv:chart "Normal"))')
rc.loads('(setq t:*slot* (lzv:recall-slot))')
assert str(rc.globals['t:*slot*']) == 'Normal', rc.globals['t:*slot*']
rc.loads('(lzv:put "b" "480") (lzv:put "h" "NA")')
rc.loads('(setq t:*s* (lzv:recall-save (lzv:recall-slot)))')
STORED = str(rc.globals['t:*s*'])
assert 'b=480' in STORED and 'h=NA' in STORED, STORED
rc.loads('(setq t:*ws* "%s" t:*wv* "Normal")' % STORED)
rc.loads('(setq lzv:*vals* nil) (lzv:put "b" "999")')
rc.loads('(setq t:*n* (lzv:recall))')
assert int(str(rc.globals['t:*n*'])) == 1, rc.globals['t:*n*']
rc.loads('(setq t:*a* (lzv:get "b"))')
assert str(rc.globals['t:*a*']) == '999', \
    "recall overwrote a box that was already typed in: %r" % rc.globals['t:*a*']
rc.loads('(setq t:*n2* (lzv:recall))')
assert int(str(rc.globals['t:*n2*'])) == 0, rc.globals['t:*n2*']
# a different bottom type finds nothing under its own slot: a Sport's
# E2/F2/F1/E1 mean nothing on a Normal's H/G/F/E
rc.loads('(setq lzv:*type* "Sport" lzv:*vals* nil)')
rc.loads('(setq lzv:*chart* (lzv:chart "Sport"))')
rc.loads('(setq t:*had* (lzv:recall-read (lzv:recall-slot)))')
assert rc.globals['t:*had*'] is None, \
    "the Normal sheet came back on a Sport: %r" % rc.globals['t:*had*']
print("   fills the empty boxes, keeps what was typed, idempotent, type-keyed")


print("== the page loop: a tab, and the position round-trip ==")
tv = stubbed(with_poolside=True)
tv.loads(typed([('tab_Sport', 'x'), ('cancel', 'c')]))
tv.loads('(setq lzv:*type* "Normal") (setq t:*f* (lzv:show))')
assert str(tv.globals['lzv:*type*']) == 'Sport', \
    "the tab did not switch the bottom: %r" % tv.globals['lzv:*type*']
assert [n for n, _ in OPENED] == ['lazside_normal', 'lazside_sport'], OPENED
assert [k for _, k in OPENED] == [2, 4], (
    "the reopened page did not carry the dialog's position back: %r" % OPENED)
assert tv.globals['t:*f*'] is None, "Cancel handed a sheet over anyway"
wired = {str(a[0]) for a in (tv.globals.get('stub:*act*') or [])}
assert 'chart' not in wired, (
    "an action is wired to the chart tile: it would be repainted on hover "
    "and a DCL image tile is not retained")
print("   a tab closes the page and reopens it, in place, on the other bottom")


print("== end to end: the form draws what the questions draw ==")
# The whole claim, and the only one that cannot be faked: fill the sheet
# in, press Insert, and the section is identical entity for entity to
# the same run answered at the prompts -- with nothing asked but the
# base point.
BASE = (0.0, 0.0, 0.0)


def snapshot(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for p in vm.entdata[e]:
            if isinstance(p, Dot):
                d.setdefault(p.a, p.b)
        out.append(tuple(sorted((str(k), repr(x)) for k, x in d.items())))
    return out


# "2" on the mirror dropdown is No, the answer the prompt defaults to;
# the last case leaves it on "(ask)" so the fall-through is driven too.
MNO = ('mirror', "2")
MYES = ('mirror', "1")
CASES = [
    # bottom type, the boxes, and the same run answered at the prompts:
    # the type, the base point, B, then the chain and the depths in
    # psd:items order (runs first, then C, D and -- on a SHallow -- C2),
    # then the mirror question
    ('Normal',
     [('b', "480"), ('h', "36"), ('g', "96"), ('f', "228"), ('e', "120"),
      ('c', "42"), ('d', "96"), MNO],
     ["Normal", BASE, 480.0, 36.0, 96.0, 228.0, 120.0, 42.0, 96.0, "No"]),
    ('Wedge',
     [('b', "360"), ('h', "24"), ('f', "336"), ('c', "42"), ('d', "84"), MNO],
     ["Wedge", BASE, 360.0, 24.0, 336.0, 42.0, 84.0, "No"]),
    ('SHallow',
     [('b', "480"), ('h', "36"), ('g', "96"), ('f', "228"), ('e', "120"),
      ('c', "42"), ('d', "96"), ('c2', "60"), MYES],
     ["SHallow", BASE, 480.0, 36.0, 96.0, 228.0, 120.0, 42.0, 96.0, 60.0,
      "Yes"]),
    # ...and a run left NA, which POOLSIDE reads back off B
    ('SLope',
     [('b', "420"), ('h', "24"), ('f', "NA"), ('e', "120"),
      ('c', "42"), ('d', "90"), MNO],
     ["SLope", BASE, 420.0, 24.0, "NA", 120.0, 42.0, 90.0, "No"]),
]

for ty, boxes, prompts in CASES:
    fv = stubbed(with_poolside=True)
    fv.loads(typed(boxes + [('accept', 'a')]))
    fv.loads('(setq lzv:*type* "%s")' % ty)
    try:
        fv.run('c:LAZSIDE', [BASE])
    except LispError as e:
        raise AssertionError("[%s form] %s" % (ty, e)) from None
    a = snapshot(fv)
    assert a, "%s: the form run drew nothing" % ty
    assert not fv.globals.get('psd:*form*'), \
        "%s: psd:*form* survived the run" % ty
    asked = [p for p, _ in fv.prompts]
    for word in ('Bottom type', 'overall length', 'wall height',
                 'deep end depth', 'deep end on the RIGHT'):
        assert not [p for p in asked if word in p], \
            "%s: %r was asked for anyway: %r" % (ty, word, asked)
    assert len(asked) == 1 and 'base point' in asked[0], \
        "%s: the form left more than the base point at the prompt: %r" \
        % (ty, asked)

    pv2 = stubbed(with_poolside=True)
    try:
        pv2.run('c:POOLSIDE', prompts)
    except LispError as e:
        raise AssertionError("[%s prompts] %s" % (ty, e)) from None
    b = snapshot(pv2)
    assert a == b, (
        "%s: the form drew a different section -- %d entities from the sheet, "
        "%d from the prompts; %d only from the sheet"
        % (ty, len(a), len(b), len([x for x in a if x not in b])))
    print("   %-8s %3d entities, identical from the sheet and from the command"
          % (ty, len(a)))
    print("   %-8s line; %d prompts answered by the form"
          % ('', len(pv2.prompts) - len(fv.prompts)))

# A half-filled sheet simply shortens the run: what it does not carry is
# still asked for, in the order the prompts have always come in.
hv = stubbed(with_poolside=True)
hv.loads(typed([('b', "480"), ('c', "42"), ('d', "96"), ('accept', 'a')]))
hv.loads('(setq lzv:*type* "Normal")')
hv.run('c:LAZSIDE', [BASE, 36.0, 96.0, 228.0, 120.0, "No"])
asked = [p for p, _ in hv.prompts]
assert not [p for p in asked if 'overall length' in p], \
    "B was on the sheet and asked for anyway: %r" % asked
assert len([p for p in asked if ' - ' in p]) == 4, \
    "a half-filled sheet did not leave exactly the four runs: %r" % asked
# the dropdown left on "(ask)" is an unanswered question, not a No
assert [p for p in asked if 'deep end on the RIGHT' in p], \
    "a dropdown left on (ask) answered itself: %r" % asked
assert snapshot(hv), "the half-filled sheet drew nothing"
print("   a half-filled sheet asks for the four runs, the mirror question")
print("   it was not told about, and nothing else")

print()
print("ALL LAZSIDE TESTS PASSED (%s)"
      % ('shared (grouped)' if SHARED else 'lisp/ (standalone)'))
