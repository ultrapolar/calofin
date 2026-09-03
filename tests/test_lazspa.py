"""LAZSPA: the visual spa dimension chart, and the spa it produces.

What tests/test_lazform.py is to LAZFORM and POOL, this is to LAZSPA
and SPA.  The dialog cannot run here -- the VM has no DCL -- so the
surface is stubbed and the drawing is captured instead.  Seven jobs:

1. The chart data is coherent: every dimension names an SPA key, keys
   are unique, every co-ordinate is inside the picture, and the
   octagon's letters close against its overalls the way spa:octov
   resolves them.
2. Every key a chart offers is a key SPA really asks for -- read off
   SPA.LSP itself, not off a copy of its roster kept here.
3. The generated DCL is well formed, one dialog per chart, one tile key
   per answer, braces balanced, and no image_button anywhere.
4. The DRAWING is checked, not assumed: every vector must land inside
   the tile, in a colour the file declares, and the value-replaces-
   letter rule must actually hold.
5. lzs:answer implements the three-state contract -- empty means ask,
   NA means NA, a measurement means itself, a typo means ask -- and an
   NA against a key SPA has no NA for is demoted to "ask" rather than
   crashing the flow it would be fed to.
6. The greying rules, and that a greyed key never travels.
7. End to end, all three shapes: filling the chart in and pressing
   Insert draws the same spa as answering SPA's questions by hand.

Runs at either tier: standalone by default, grouped with
CALOFIN_LISP_ROOT=shared.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Dot, Ent  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..'))
LSP = os.path.join(REPO, 'lisp', 'lazspa', 'LAZSPA.lsp')
SPA = os.path.join(REPO, 'lisp', 'spa', 'SPA.LSP')

# The mirror swaps a handful of this file's helpers for CALOFIN-LIB's,
# so a shared-tier run has to ask for the name that tier actually
# defines.  tools/mirror_shared.py is the authority on the mapping;
# these are the entries the tests below reach for by name.
SHARED = bool(os.environ.get('CALOFIN_LISP_ROOT'))


def lib(local, shared):
    """The name this tier defines: the file's own, or the library's."""
    return shared if SHARED else local

DX, DY = 520, 376          # a plausible tile size, in pixels
DRAW = {'vec': [], 'fill': [], 'list': []}


def _reset():
    OPENED.clear()
    POS.clear()
    DRAW['vec'] = []
    DRAW['fill'] = []
    DRAW['list'] = []


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
_b('mode_tile')(lambda vm, a: None)


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
      stub:*opened* nil stub:*mode* nil stub:*tiles* nil)
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
(defun set_tile (k v)
  (setq stub:*tiles* (cons (list k v) stub:*tiles*)) v)
(defun stub:tile (k / p) (if (setq p (assoc k stub:*tiles*)) (cadr p)))
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


def fresh(with_spa=False):
    _reset()
    vm = VM()
    if with_spa:
        vm.load(SPA)
    vm.load(LSP)
    return vm


def stubbed(with_spa=False):
    vm = fresh(with_spa)
    vm.loads(STUB)
    return vm


def typed(pairs):
    """The stub's typing script, as LISP source."""
    return "'(%s)" % ' '.join('("%s" "%s")' % (k, v) for k, v in pairs)


# an alist pair is a Dot when it has a value and a one-element LIST when
# it does not -- (cons 'tt nil) is the list (tt), whose cdr is nil.  That
# is the present-but-nil state SPA reads as NA, so both shapes have to be
# understood here.
def pair(p):
    return (str(p.a), p.b) if isinstance(p, Dot) else (str(p[0]), None)


def alist(vm, var):
    return dict(pair(p) for p in vm.globals[var])


print("== the file loads and the chart data is coherent ==")
vm = fresh()
ver = vm.globals.get('*lazspa-version*')
assert ver and re.fullmatch(r'v\d+\.\d+', str(ver)), ver
charts = vm.globals.get('lzs:*charts*')
assert charts, "no charts"
# SPA draws three shapes and spells them exactly these three ways.  ROund
# is NOT POOL's ROUnd: the wrong spelling falls through spa:fshape's
# member check, is asked for again, and -- typed by hand -- would fall
# through c:SPA's dispatch cond into the rectangle branch.
assert [str(c[1]) for c in charts] == ['Rectangle', 'OCtagon', 'ROund'], \
    "the charts do not name SPA's three shapes: %r" % [str(c[1]) for c in charts]
for c in charts:
    key, shape, title = str(c[0]), str(c[1]), str(c[2])
    outline, dims, extra = c[3], c[4], (c[5] or [])
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
    for m in (c[6] or []):
        assert 0 <= int(m[1]) <= 1000 and 0 <= int(m[2]) <= 1000, \
            "%s: a mark is outside the picture: %r" % (key, m)
print("   %s, %d chart(s), every dimension keyed, labelled and in bounds"
      % (ver, len(charts)))


print("== the octagon's letters close against its overalls ==")
# spa:octov resolves the sheet letters against the two overalls --
# S + T + S = B across and S1 + V + S1 = A up -- and then re-derives
# whichever was not measured.  If the drawn chain does not add up to the
# drawn overall the picture is lying about the measurement it names, and
# the person reading it off is misled before SPA ever sees a number.
oc = vm.globals['lzs:*charts*'][1]
span = {}
for d in oc[4]:
    span[str(d[1])] = (abs(int(d[4]) - int(d[2])) if str(d[6]) == 'h'
                       else abs(int(d[5]) - int(d[3])))
assert span['ss'] * 2 + span['tt'] == span['b'], \
    "S + T + S = %d but B is %d" % (span['ss'] * 2 + span['tt'], span['b'])
assert span['s1'] * 2 + span['vv'] == span['a'], \
    "S1 + V + S1 = %d but A is %d" % (span['s1'] * 2 + span['vv'], span['a'])
print("   S+T+S = B (%d) and S1+V+S1 = A (%d)" % (span['b'], span['a']))


print("== every chart key is a key SPA actually asks for ==")
# the whole point of the form is that SPA reads these back; a key SPA
# never asks for would be typed into and silently dropped.
spa_src = open(SPA).read()

# 1. the measurement sequences.  SPA writes each item as
#    (list 'key 'KIND "prompt" ents dflt) and spa:askseqb looks the key
#    up in the form store before prompting -- see its (spa:fhas (car it))
#    branch.  This is every plan dimension on every chart, plus the
#    second outline's overalls (w2/l2, b2/a2/f2).
askseq_keys = set(re.findall(r"\(list '([a-z][a-z0-9]*)\s+'(?:REQ|NAX|SUG)",
                             spa_src))
# 2. the keyword questions outside a sequence, asked through spa:askkwf:
#    'mode (c:SPA), 'second and 'method (spa:askother2), 'autohinge
#    (spa:hingeflow).
kwf_keys = set(re.findall(r"askkwf\s+'([a-z][a-z0-9]*)", spa_src))
# 3. the typed distance outside a sequence, asked through spa:askdf:
#    'gap (spa:askgap).
df_keys = set(re.findall(r"askdf\s+'([a-z][a-z0-9]*)", spa_src))
# 4. the keys read by spa:fhas directly: 'shape (spa:fshape), 'grade and
#    'taper (spa:formdetails), 'base (c:SPA), and round's 'a, which
#    spa:roundflow PEEKS at to decide the Outofround branch.
fhas_keys = set(re.findall(r"spa:fhas\s+'?\(?'?([a-z][a-z0-9]*)", spa_src))
# 5. the corner keys, which SPA builds at run time rather than writing
#    out: spa:fckey turns the prompt label "Corner A" into the stem
#    cornera, and spa:askcorner reads <stem>-ty and <stem>-sz off it.
assert '(strcat "corner" (substr s 8))' in spa_src, \
    "spa:fckey no longer builds the corner stem this way"
assert '(strcat fk "-ty")' in spa_src and '(strcat fk "-sz")' in spa_src, \
    "spa:askcorner no longer reads <stem>-ty / <stem>-sz"
assert '(strcat "Corner " (nth i lbls))' in spa_src, \
    "spa:rectflow no longer labels its corners \"Corner <letter>\""
corner_keys = set()
for letter in 'abcd':
    corner_keys |= {'corner%s-ty' % letter, 'corner%s-sz' % letter}

SPA_KEYS = askseq_keys | kwf_keys | df_keys | fhas_keys | corner_keys
for need, where in (('mode', 'kwf'), ('second', 'kwf'), ('method', 'kwf'),
                    ('autohinge', 'kwf'), ('gap', 'df'), ('grade', 'fhas'),
                    ('taper', 'fhas'), ('shape', 'fhas')):
    assert need in SPA_KEYS, "SPA.LSP no longer asks %r (%s)" % (need, where)

vm.loads('(setq t:*lk* (lzs:listkeys))')
LIST_KEYS = [str(x) for x in vm.globals['t:*lk*']]

total = 0
for c in charts:
    name = str(c[0])
    vm.loads('(setq t:*c* (lzs:chart "%s"))'
             '(setq t:*keys* (lzs:boxkeys t:*c*))'
             '(setq t:*cor* (lzs:corners t:*c*))' % name)
    ks = [str(x) for x in vm.globals['t:*keys*']] + LIST_KEYS
    for stem in [str(x[0]) for x in (vm.globals.get('t:*cor*') or [])]:
        ks += [stem + '-ty', stem + '-sz']
    for k in ks:
        assert k in SPA_KEYS, (
            "%s: chart key %r is not asked for anywhere in SPA.LSP -- it "
            "would be typed into and dropped on the floor" % (name, k))
    total += len(ks)
    print("   %-10s %2d keys, all of them SPA answer keys" % (name, len(ks)))
print("   %d keys across %d charts" % (total, len(charts)))
# The dropdown speaks the SHEET LEGEND -- 90 / Radius / Diagonal, the
# words printed on the paper a drafter is copying from.  SPA itself now
# asks the canonical Treatment question (Square / Radius / Cut /
# NotGiven, STANDARDS section 2) and normalises the legend words on the
# way in, so the chart keeps the drafter's vocabulary while the routine
# keeps the standard's.  What this pins is that the bridge still
# exists: every word the dropdown can send must be one spa:askcorner
# accepts, or the corner would be silently re-asked at the keyboard.
treat = [str(x) for x in vm.globals['lzs:*ctreat*']]
assert treat[0] == '(ask)', treat
assert set(treat[1:]) == {'90', 'Radius', 'Diagonal'}, \
    "the corner dropdown does not speak SPA's corner legend: %r" % treat
assert '"Square Radius Cut NotGiven' in spa_src, \
    "spa:askcorner no longer asks the canonical Treatment question"
for word in treat[1:]:
    assert '"%s"' % word in spa_src, \
        ("the chart can send %r but SPA.LSP never names it -- the "
         "legend-to-canonical normalisation has gone" % word)
print("   chart sends the legend (%s); SPA normalises to the canonical set"
      % ', '.join(treat[1:]))


print("== the generated DCL is well formed, for every chart ==")
TILES = {'row', 'column', 'boxed_column', 'boxed_row', 'button', 'text',
         'edit_box', 'image', 'image_button', 'toggle', 'popup_list',
         'spacer'}

vm.loads('(setq t:*all* (lzs:dcl-lines))')
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
    vm.loads('(setq t:*n* (lzs:dlgname "%s"))' % name)
    dlg = str(vm.globals['t:*n*'])
    i = ALL.index(dlg + ' : dialog {')
    d = 0
    for j in range(i, len(ALL)):
        d += ALL[j].count('{') - ALL[j].count('}')
        if d == 0:
            return ALL[i:j + 1]
    raise AssertionError("%s never closes" % dlg)


# DCL does not scroll and a dialog wider than the screen has nowhere to
# go, so both halves of a page get a budget.  The chart column is 52
# cells; 58 for the right-hand column is what LAZFORM's own widest row
# ("S1 - RIGHT corner drop (ends not perfect)" plus its 9-cell box) runs
# at, so this holds LAZSPA to a page the same size.
TAB_BUDGET = 84
SIDE_BUDGET = 58


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
    vm.loads('(setq lzs:*chart* (lzs:chart "%s"))'
             '(setq t:*keys* (lzs:boxkeys lzs:*chart*))'
             '(setq t:*dims* (lzs:dims lzs:*chart*))'
             '(setq t:*cuts* (lzs:cuts lzs:*chart*))'
             '(setq t:*wk* (lzs:wedge-keys lzs:*chart*))'
             '(setq t:*cor* (lzs:corners lzs:*chart*))' % name)
    text = '\n'.join(d)
    tilekeys = re.findall(r'key = "([^"]+)"', text)
    assert len(tilekeys) == len(set(tilekeys)), \
        "%s: duplicate tile keys" % name
    # ONE TILE PER ANSWER: every typed box, every dropdown, every corner
    answer_keys = [str(x) for x in vm.globals['t:*keys*']]
    answer_keys += [str(k[0]) for k in vm.globals['lzs:*lists*']]
    for stem in [str(x[0]) for x in (vm.globals.get('t:*cor*') or [])]:
        answer_keys += [stem, stem + '-sz']
    answer_keys = [str(k) for k in answer_keys]
    assert set(answer_keys) <= set(tilekeys), (
        "%s: answers with no box: %r"
        % (name, sorted(set(answer_keys) - set(tilekeys))))
    # one image band per stretch between cuts, a wedge row at each cut
    cuts = [int(x) for x in (vm.globals.get('t:*cuts*') or [])]
    wk = [str(x) for x in (vm.globals.get('t:*wk*') or [])]
    for b in range(len(cuts) + 1):
        assert 'chart%d' % b in tilekeys, "%s: no band tile chart%d" % (name, b)
    assert 'chart%d' % (len(cuts) + 1) not in tilekeys, \
        "%s: more band tiles than bands" % name
    # every cut carries at least one wedge box -- a grey strip with
    # nothing in it would cut the drawing for no reason at all
    assert cuts, "%s: no cuts declared" % name
    vm.loads('(setq t:*cd* (mapcar \'(lambda (y) (length (lzs:cutdims '
             'lzs:*chart* y))) (lzs:cuts lzs:*chart*)))')
    for y, n in zip(cuts, [int(x) for x in vm.globals['t:*cd*']]):
        assert n > 0, "%s: cut at %d has no dimension on it" % (name, y)
    # a wedge dim's box is on the chart, so it has NO pick button; a
    # column dim has one
    for k in wk:
        assert 'pick_%s' % k not in tilekeys, \
            "%s: wedge dim %s also has a pick button" % (name, k)
    for dim in vm.globals['t:*dims*']:
        if str(dim[1]) in wk:
            continue
        assert 'pick_%s' % str(dim[1]) in tilekeys, \
            "%s: dimension %s has no letter button" % (name, str(dim[0]))
    for extra in ('mode', 'second', 'method', 'gap', 'autohinge', 'grade',
                  'taper', 'accept', 'cancel', 'hint'):
        assert extra in tilekeys, "%s: no %r tile" % (name, extra)
    # a tab for every chart, on every page -- including this one, so the
    # strip does not change width as you move along it
    for c2 in charts:
        assert 'tab_%s' % str(c2[0]) in tilekeys, \
            "%s: no tab for %s" % (name, str(c2[0]))
    assert text.count('is_cancel = true') == 1
    assert text.count('is_default = true') == 1
    # THE PICTURE MUST STAY PASSIVE.  A DCL image tile is not retained:
    # an image_button repaints on mouse-enter and the chart is gone.
    assert ': image_button' not in text, (
        "%s: the chart is an image_button again -- it will be wiped the "
        "first time the mouse crosses it" % name)
    assert re.search(r': image \{ key = "chart0"', text), \
        "%s: no passive chart image tile" % name
    # a boxed section with nothing in it is a labelled empty rectangle
    for i, line in enumerate(d[:-2]):
        if line.strip().startswith(': boxed_column {'):
            assert d[i + 2].strip() != '}', (
                "%s: a boxed section with nothing in it at line %d -- a "
                "labelled empty rectangle" % (name, i))
    # and the wedge boxes land near their letters: replay the spacer
    # arithmetic and compare each box's centre with its dimension's, in
    # character cells
    centers = {str(dd[1]): (int(dd[2]) + int(dd[4])) / 2.0 * 52 / 1000.0
               for dd in vm.globals['t:*dims*']}
    pos = None
    expect = False          # a wedge row IMMEDIATELY follows its band
    widest_row = 0.0
    for line in d:
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
                widest_row = max(widest_row, pos)
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
    assert widest_row <= 52, (
        "%s: a wedge row is about %.1f cells, wider than the %d-cell chart "
        "it sits under" % (name, widest_row, 52))
    # the right-hand column has to fit beside the chart
    side = 0
    for lb, w in re.findall(r'label = "([^"]*)"; edit_width = (\d+)', text):
        side = max(side, len(lb) + int(w) + 8)
    for w, lb in re.findall(r'edit_width = (\d+); label = "([^"]*)"', text):
        side = max(side, len(lb) + int(w) + 8)
    assert side <= SIDE_BUDGET, (
        "%s: the boxes column is about %d cells, over the %d budget -- DCL "
        "will not scroll a dialog wider than the screen"
        % (name, side, SIDE_BUDGET))
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
    return d, tilekeys, side


for c in charts:
    d, tk, side = check_page(str(c[0]))
    body = '\n'.join(d)
    tabs = re.findall(r'key = "tab_[^"]+"; label = "([^"]+)"', body)
    assert len(tabs) == len(charts), "%s: %d tabs" % (str(c[0]), len(tabs))
    vm.loads('(setq t:*tr* (lzs:tabrows))')
    rows = [[str(x) for x in r] for r in vm.globals['t:*tr*']]
    assert [t for r in rows for t in r] == tabs, (
        "%s: lzs:tabrows names %r but the page emits %r"
        % (str(c[0]), rows, tabs))
    wide = max(sum(len(t) + 6 for t in r) for r in rows)
    assert wide <= TAB_BUDGET, (
        "%s: the widest tab row is about %d characters, over the %d budget "
        "-- a dialog wider than the screen cannot be shown and DCL will not "
        "scroll it: %r" % (str(c[0]), wide, TAB_BUDGET, rows))
    print("   %-10s %2d lines, %2d tile keys, tabs ~%d, boxes ~%d cells"
          % (str(c[0]), len(d), len(tk), wide, side))


print("== the drawing lands inside the tile, in declared colours ==")
COLS = {}
for name in ('line', 'back', 'dim', 'val', 'hi'):
    COLS[name] = int(vm.globals[lib('lzs:*col-%s*' % name,
                                   'cal:*imgcol-%s*' % name)])
for c in charts:
    name = str(c[0])
    _reset()
    vm.loads('(setq lzs:*chart* (lzs:chart "%s")) (setq lzs:*vals* nil)'
             '(setq lzs:*focus* nil) (lzs:redraw)' % name)
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


print("== a typed value replaces its letter on the chart ==")
_reset()
vm.loads('(setq lzs:*chart* (lzs:chart "OCtagon")) (setq lzs:*vals* nil)'
         '(setq lzs:*focus* nil) (lzs:redraw)')
assert not [v for v in DRAW['vec'] if v[4] == COLS['val']], \
    "nothing has been typed, yet something is drawn as a value"
line_blank = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
# the WEDGE dims draw nothing at all -- their row of the drawing is a row
# of real boxes -- so the rule is checked on the vertical dims, which
# still live in the side column and on the chart: A and S1
_reset()
vm.loads('(lzs:put "a" "84") (lzs:put "s1" "12") (lzs:redraw)')
vals = [v for v in DRAW['vec'] if v[4] == COLS['val']]
assert vals, "a typed value was not drawn"
line_now = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
assert line_now < line_blank, (
    "the letters A and S1 are still being drawn after being answered "
    "(%d outline strokes vs %d blank)" % (line_now, line_blank))
print("   %d value strokes appear; outline strokes fall %d -> %d"
      % (len(vals), line_blank, line_now))

# typing into a WEDGE key changes nothing on the chart: its box is a real
# tile sitting on the drawing, not strokes to redraw
_reset()
vm.loads('(setq lzs:*vals* nil) (lzs:redraw)')
base = len(DRAW['vec'])
_reset()
vm.loads('(lzs:put "b" "96") (lzs:put "tt" "48") (lzs:redraw)')
assert len(DRAW['vec']) == base, (
    "typing into a wedge box changed the drawing: %d -> %d strokes"
    % (base, len(DRAW['vec'])))
vm.loads('(setq lzs:*vals* nil)')
print("   wedge keys draw nothing -- their boxes are real tiles")

# the rectangle's corner letters are on its picture: SPA names its corner
# questions after them, so the Corners rows and the drawing must agree
_reset()
vm.loads('(setq lzs:*chart* (lzs:chart "Rectangle")) (setq lzs:*vals* nil)'
         '(lzs:redraw)')
marked = len(DRAW['vec'])
vm.loads('(setq t:*m* (lzs:marks (lzs:chart "Rectangle")))')
mk = [str(x[0]) for x in vm.globals['t:*m*']]
assert mk == ['D', 'C', 'A', 'B'], mk
print("   the rectangle carries its corner letters %s on the picture"
      % ' '.join(sorted(mk)))


print("== the page loop: tabs, letter buttons, nothing on the chart ==")
vm2 = stubbed()
DRAW['vec'] = []
vm2.loads('(setq t:*f* (lzs:show "Rectangle"))')
# the chart must actually be DRAWN while the dialog is up.  An image tile
# is blank until something strokes into it, and DCL gives no second
# chance -- so a page that opens without a redraw shows an empty box.
assert DRAW['vec'], "lzs:show opened a page and drew nothing into the chart"
drew_open = len(DRAW['vec'])
wired = {str(a[0]) for a in (vm2.globals.get('stub:*act*') or [])}
assert not [k for k in wired if k.startswith('chart')], (
    "an action is wired to a chart tile: it would be repainted on hover")
for k in ('mode', 'second', 'method', 'gap', 'autohinge', 'grade', 'taper',
          'accept', 'cancel'):
    assert k in wired, "%r has no callback" % k
vm2.loads('(setq t:*dims* (lzs:dims (lzs:chart "Rectangle")))'
          '(setq t:*wk* (lzs:wedge-keys (lzs:chart "Rectangle")))')
wk2 = {str(x) for x in vm2.globals['t:*wk*']}
for dim in vm2.globals['t:*dims*']:
    k = str(dim[1])
    if k in wk2:
        assert 'pick_%s' % k not in wired, \
            "wedge dim %s has a pick callback for a button that does not " \
            "exist" % str(dim[0])
    else:
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
vm3.loads('(setq stub:*type* \'(("pick_l" "")))'
          '(setq t:*f* (lzs:show "Rectangle"))')
modes = [(str(a[0]), int(a[1])) for a in (vm3.globals.get('stub:*mode*') or [])]
assert ('l', 2) in modes, "clicking L did not move the caret to its box: %r" % modes
assert ('l', 3) in modes, "clicking L did not select the box contents: %r" % modes
assert str(vm3.globals.get('lzs:*focus*')) == 'l', \
    "clicking L did not ring L on the chart"
print("   clicking a letter focuses its box, selects it, and rings the chart")

# a tab click reopens on the other chart, and what was typed survives it
vm4 = stubbed()
DRAW['vec'] = []
vm4.loads('(setq stub:*rcs* \'(4 1))'
          '(setq stub:*type* \'(("w" "84") ("mode" "1") ("tab_ROund" "")))'
          '(setq t:*f* (lzs:show "Rectangle"))')
assert str(vm4.globals.get('stub:*opened*')) == 'lazspa_round', (
    "the tab did not reopen on the Round page: %r"
    % vm4.globals.get('stub:*opened*'))
vm4.loads('(setq t:*v* (lzs:get "w")) (setq t:*p* (lzs:pick "mode"))')
assert str(vm4.globals['t:*v*']) == '84', (
    "what was typed did not survive the page switch: %r" % vm4.globals['t:*v*'])
assert str(vm4.globals['t:*p*']) == 'Watersedge', (
    "a dropdown did not survive the page switch: %r" % vm4.globals['t:*p*'])
# DCL has no way to ask an open dialog where it is; done_dialog reporting
# its position as it closes is the only chance to find out, and new_dialog
# only accepts one back in its FOUR-argument form.  So the first page
# opens with two arguments and every page after it with four -- and if
# that regresses, the dialog jumps back to the middle of the screen on
# every tab click.
assert [n for n, _ in OPENED] == ['lazspa_rectangle', 'lazspa_round'], OPENED
assert DRAW['vec'], "the second page opened and drew nothing into its chart"
assert [n for _, n in OPENED] == [2, 4], (
    "the reopened page did not carry the position back: %r" % OPENED)
print("   a tab reopens on the other chart, keeps what was typed,")
print("   and puts the dialog back where the user had dragged it")

print("== where it was left outlives the session, not just the page ==")
# lzs:*pos* is cleared at the top of every run and dies with the file,
# so the second LAZSPA of the day -- and the first one after an AutoCAD
# restart -- used to open back in the middle of the screen.  The
# profile is what closes that.
vmp = stubbed()
vmp.loads('(setq stub:*type* \'(("cancel" "")))'
          '(setq t:*f* (lzs:show "Rectangle"))')
vmp.loads('(setq t:*saved* (getenv lzs:*poskey*))')
assert str(vmp.globals.get('t:*saved*')) == '120,340', (
    "closing the dialog did not write its position to the profile: %r"
    % vmp.globals.get('t:*saved*'))

# a fresh VM is a fresh AutoCAD.  Seed the profile the last one left and
# the FIRST page opens with four arguments, at that point, rather than
# centred -- which is the whole of what was asked for.
vmq = stubbed()
vmq.loads('(setenv "LazSpa_Pos" "212,84")')
vmq.loads('(setq stub:*type* \'(("cancel" "")))'
          '(setq t:*f* (lzs:show "Rectangle"))')
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
    vmr.loads('(setenv lzs:*poskey* %s) (setq t:*r* (lzs:pos-read))' % src)
    got = vmr.globals.get('t:*r*')
    got = [int(v) for v in got] if got else None
    assert got == want, "%s read back as %r, not %r" % (why, got, want)
# SCREENSIZE is unknown on a box AutoCAD cannot size (it reads nil), and
# the clamp has to sit that out rather than pin every dialog to the
# corner.  The VM seeds it like AutoCAD does, so this scenario takes
# it away.
vmr.sysvars.pop('SCREENSIZE', None)
# a point saved on a second monitor that has since been unplugged is
# dragged back onto the drawing area, not left where the mouse cannot go
vmr.sysvars['SCREENSIZE'] = [1600.0, 900.0]
vmr.loads('(setenv lzs:*poskey* "4000,2000") (setq t:*r* (lzs:pos-read))')
assert [int(v) for v in vmr.globals['t:*r*']] == [1500, 800], (
    "an off-screen point was not clamped back: %r" % vmr.globals['t:*r*'])
vmr.loads('(setenv lzs:*poskey* "300,200") (setq t:*r* (lzs:pos-read))')
assert [int(v) for v in vmr.globals['t:*r*']] == [300, 200], (
    "a point already on screen was moved: %r" % vmr.globals['t:*r*'])
print("   a profile value this build did not write centres the dialog,")
print("   and a point off the current screen is dragged back onto it")


print("== corners: dropdown, un-greying size box, packing ==")
# structure: only the Rectangle carries corner rows -- SPA asks corner
# treatments for no other shape
for c in charts:
    name = str(c[0])
    text = '\n'.join(page(name))
    vm.loads('(setq t:*cor* (lzs:corners (lzs:chart "%s")))' % name)
    cors = [str(x[0]) for x in (vm.globals.get('t:*cor*') or [])]
    for stem in cors:
        assert re.search(r': popup_list \{ key = "%s"' % stem, text), \
            "%s: no dropdown for %s" % (name, stem)
        assert re.search(r': edit_box \{ key = "%s-sz"' % stem, text), \
            "%s: no size box for %s" % (name, stem)
    if not cors:
        assert 'Corners' not in text, \
            "%s: a Corners section with nothing in it" % name
assert [str(x[0]) for x in vm.globals['lzs:*corners*']] == ['Rectangle']
print("   only the Rectangle carries corner rows")

# picking a sized treatment un-greys the size box; picking 90 greys it
# again -- driven through the REAL action expression
vmc = stubbed()
vmc.loads('(setq stub:*type* \'(("cornera" "3")))'      # Diagonal
          '(setq t:*f* (lzs:show "Rectangle"))')
modes = [(str(a[0]), int(a[1])) for a in (vmc.globals.get('stub:*mode*') or [])]
assert ('cornera-sz', 0) in modes, \
    "picking Diagonal did not un-grey the size box: %r" % modes
vmc2 = stubbed()
vmc2.loads('(setq stub:*type* \'(("cornera" "1")))'     # 90
           '(setq t:*f* (lzs:show "Rectangle"))')
modes = [(str(a[0]), int(a[1])) for a in (vmc2.globals.get('stub:*mode*') or [])]
assert ('cornera-sz', 1) in modes and ('cornera-sz', 0) not in modes, \
    "picking 90 should leave the size box greyed: %r" % modes
print("   Diagonal un-greys its size box; 90 keeps it greyed")

# packing: (ask) sends nothing; 90 sends the treatment alone; a sized
# treatment sends treatment + size when the size parses
vm.loads('(setq lzs:*chart* (lzs:chart "Rectangle"))'
         '(setq lzs:*vals* nil lzs:*picks* nil)'
         '(lzs:pput "cornera" 3) (lzs:put "cornera-sz" "24")'
         '(lzs:pput "cornerb" 1)'
         '(lzs:pput "cornerc" 2)'      # Radius, size left empty
         '(setq t:*f* (lzs:form))')
form = alist(vm, 't:*f*')
assert str(form.get('cornera-ty')) == 'Diagonal' and \
    abs(float(form['cornera-sz']) - 24.0) < 1e-9, form
assert str(form.get('cornerb-ty')) == '90' and 'cornerb-sz' not in form
assert str(form.get('cornerc-ty')) == 'Radius' and 'cornerc-sz' not in form, \
    "an empty size box must send the treatment alone (SPA asks the size)"
assert 'cornerd-ty' not in form, "(ask) sent a corner it should not have"
print("   (ask)/90/Radius/Diagonal all pack the way SPA reads them")


print("== the three-state answer contract ==")
# NOTE on the feet-inch case: this VM's distof only takes the leading
# number off a string, where AutoCAD's mode 4 reads the whole
# architectural spelling.  What the contract requires, and what is
# asserted, is that such a string PARSES rather than being dropped.
for entry, expect in (('', 'SKIP'),
                      ('   ', 'SKIP'),
                      ('NA', None),
                      ('na', None),
                      (' na ', None),
                      ('84', 84.0),
                      ("6'10\"", 'NUMBER'),
                      ('not a number', 'SKIP')):
    vm.loads('(setq t:*a* (%s "%s"))'
             % (lib('lzs:answer', 'cal:formanswer'),
                entry.replace('\\', '\\\\').replace('"', '\\"')))
    got = vm.globals['t:*a*']
    if expect == 'SKIP':
        assert str(got).upper() == 'SKIP', \
            "%r gave %r, expected SKIP" % (entry, got)
    elif expect is None:
        assert got is None, "%r gave %r, expected nil (NA)" % (entry, got)
    elif expect == 'NUMBER':
        assert isinstance(got, float) and got > 0, \
            "%r gave %r, expected it to parse as a distance" % (entry, got)
    else:
        assert abs(float(got) - expect) < 1e-9, \
            "%r gave %r, expected %r" % (entry, got, expect)
print("   empty and rubbish both ask; NA means NA; a feet-inch")
print("   spelling parses rather than being dropped")

# ...and an NA against a key SPA has no NA for is demoted to "ask".
# spa:askseqb stores a form nil straight into its answers without
# validating it, and a REQ item's nil is then arithmetic on nil, which is
# an error rather than a fallback.  So the demotion is a crash guard, not
# a nicety.
for chart, key, want in (('Rectangle', 'l', None),      # SUG: NA is real
                         ('Rectangle', 'w', 'SKIP'),    # REQ: no NA
                         ('OCtagon', 'tt', None),       # NAX
                         ('OCtagon', 'b', 'SKIP'),      # REQ
                         ('ROund', 'b', 'SKIP'),        # REQ
                         ('ROund', 'a', 'SKIP')):       # the out-of-round gate
    vm.loads('(setq lzs:*chart* (lzs:chart "%s")) (setq lzs:*vals* nil)'
             '(lzs:put "%s" "NA")'
             '(setq t:*a* (lzs:keyanswer lzs:*chart* "%s"))'
             % (chart, key, key))
    got = vm.globals['t:*a*']
    if want == 'SKIP':
        assert str(got).upper() == 'SKIP', \
            "%s/%s: NA gave %r, expected it demoted to SKIP" % (chart, key, got)
    else:
        assert got is None, "%s/%s: NA gave %r, expected nil" % (chart, key, got)
print("   NA is passed on where SPA takes one and demoted to \"ask\" where")
print("   it does not -- including Round's A, whose presence is the gate")


print("== the alist handed to SPA ==")
vm.loads('(setq lzs:*chart* (lzs:chart "OCtagon"))'
         '(setq lzs:*vals* nil lzs:*picks* nil)'
         '(lzs:pput "mode" 1)'
         '(lzs:put "b" "96") (lzs:put "a" "84")'
         '(lzs:put "tt" "NA") (lzs:put "ss" "")'
         '(setq t:*f* (lzs:form))')
form = alist(vm, 't:*f*')
assert str(form['shape']) == 'OCtagon'
assert str(form['mode']) == 'Watersedge'
assert abs(float(form['b']) - 96.0) < 1e-9
assert 'tt' in form and form['tt'] is None, "NA must be sent as (tt . nil)"
assert 'ss' not in form, "an empty box must not be sent at all"
assert 'base' not in form, \
    "the insertion point is picked in the drawing, never sent"
print("   filled keys sent, NA sent as nil, empty boxes left out entirely")


print("== the greying rules, and that a greyed key never travels ==")


def greyed(vm_, picks, chart='Rectangle'):
    """The keys lzs:dead names for this dropdown state."""
    src = ('(setq lzs:*chart* (lzs:chart "%s")) (setq lzs:*picks* nil)'
           % chart)
    for k, i in picks:
        src += '(lzs:pput "%s" %d)' % (k, i)
    src += '(setq t:*d* (lzs:dead lzs:*chart*))'
    vm_.loads(src)
    return set(str(x) for x in (vm_.globals['t:*d*'] or []))


gv = fresh()
SECOND = {'w2', 'l2'}
assert greyed(gv, []) == set(), \
    "nothing is settled yet, so nothing may be greyed"
assert greyed(gv, [('method', 2)]) == {'gap'}, \
    "by Dims the lap is not asked"
assert greyed(gv, [('method', 1)]) == SECOND, \
    "by Offset the second overalls are not asked"
assert greyed(gv, [('second', 2)]) == {'method', 'gap'} | SECOND, \
    "No second outline: nothing about it is asked"
assert greyed(gv, [('second', 1), ('method', 1)]) == SECOND
# Thermo-Light: its water's edge IS its cover size, so c:SPA picks the
# mode itself, spa:askother declines to offer the second outline, and
# spa:askdetails forces the taper to 1-3/8
thermo = greyed(gv, [('grade', 2)])
assert thermo == {'mode', 'second', 'method', 'gap', 'taper'} | SECOND, \
    "Thermo-Light does not close what SPA closes: %r" % sorted(thermo)
assert 'autohinge' not in thermo, \
    "a Thermo-Light cover is still hinged -- in velcro throughout"
# and the octagon's f2 rides with its pair
assert greyed(gv, [('second', 2)], 'OCtagon') == \
    {'method', 'gap', 'b2', 'a2', 'f2'}
print("   (ask) greys nothing; Dims/Offset split the cover block;")
print("   No closes it; Thermo-Light closes mode and the taper too")

# a greyed key does not travel
gv.loads('(setq lzs:*chart* (lzs:chart "Rectangle"))'
         '(setq lzs:*vals* nil lzs:*picks* nil)'
         '(lzs:pput "second" 1) (lzs:pput "method" 1)'
         '(lzs:put "gap" "3") (lzs:put "w2" "90") (lzs:put "l2" "78")'
         '(setq t:*f* (lzs:form))')
f1 = alist(gv, 't:*f*')
assert abs(float(f1['gap']) - 3.0) < 1e-9, f1
assert 'w2' not in f1 and 'l2' not in f1, \
    "by Offset the by-dims overalls must not be sent: %r" % sorted(f1)
gv.loads('(lzs:pput "method" 2) (setq t:*f* (lzs:form))')
f2 = alist(gv, 't:*f*')
assert 'gap' not in f2, "by Dims the lap must not be sent: %r" % sorted(f2)
assert abs(float(f2['w2']) - 90.0) < 1e-9, f2
gv.loads('(lzs:pput "second" 2) (setq t:*f* (lzs:form))')
f3 = alist(gv, 't:*f*')
assert str(f3['second']) == 'No'
for gone in ('method', 'gap', 'w2', 'l2'):
    assert gone not in f3, "%s travelled with second = No: %r" % (gone, sorted(f3))
gv.loads('(setq lzs:*picks* nil) (lzs:pput "grade" 2) (lzs:pput "mode" 1)'
         '(lzs:pput "taper" 1) (setq t:*f* (lzs:form))')
f4 = alist(gv, 't:*f*')
assert str(f4['grade']) == 'THERMOLIGHT'
for gone in ('mode', 'taper', 'gap', 'w2', 'l2'):
    assert gone not in f4, \
        "%s travelled under Thermo-Light: %r" % (gone, sorted(f4))
print("   and nothing greyed is put on the wire")

# the greying is applied to the real tiles when a dropdown changes
vg = stubbed()
vg.loads('(setq stub:*type* \'(("method" "2")))'
         '(setq t:*f* (lzs:show "Rectangle"))')
last = {}
for a in reversed(vg.globals.get('stub:*mode*') or []):
    last[str(a[0])] = int(a[1])
assert last.get('gap') == 1, "picking Dims did not grey the lap box: %r" % last
assert last.get('w2') == 0 and last.get('l2') == 0, last
print("   picking Dims greys the lap on the live dialog")


print("== end to end: the form draws what the questions draw ==")


def snapshot(vm_):
    out = []
    for e in vm_.entities:
        if e in vm_.deleted:
            continue
        d = {}
        for p in vm_.entdata[e]:
            if isinstance(p, Dot):
                d.setdefault(p.a, p.b)
        out.append(tuple(sorted((str(k), repr(v)) for k, v in d.items())))
    return out


def by_prompts(script):
    # Entity ids number a process-wide counter, and a handle can be BAKED
    # into an entity that round-trips through entget/entmod.  Restarting
    # the counter per run makes handles a fact about the drawing rather
    # than about how many runs came before it.
    vm_ = fresh(with_spa=True)
    Ent._n = 0
    vm_.run('c:SPA', script)
    return vm_


def by_chart(chart, typing, script):
    vm_ = stubbed(with_spa=True)
    vm_.loads('(setq stub:*type* %s)' % typed(typing))
    vm_.loads('(setq lzs:*charts* (list (lzs:chart "%s")))' % chart)
    Ent._n = 0
    try:
        vm_.run('c:LAZSPA', script)
    except LispError as e:
        raise AssertionError("%s form run: %s" % (chart, e)) from None
    return vm_


def same(a, b, label):
    sa, sb = snapshot(a), snapshot(b)
    if sa != sb:
        only_a = [x for x in sa if x not in sb]
        only_b = [x for x in sb if x not in sa]
        raise AssertionError(
            "[%s] geometry differs: %d entities only from the prompts, %d "
            "only from the chart\n  prompts: %s\n  chart:   %s"
            % (label, len(only_a), len(only_b), only_a[:2], only_b[:2]))
    assert sa, "[%s] nothing was drawn at all" % label
    return sa


# The scripts below are SPA's real prompt order, the same one
# tests/test_spa_form.py drives: the Spa Cover Details block pick, the
# mode, the shape, the base point, the measurements, the corners, the
# offer of the second outline and the auto-hinge gate.  The form answers
# everything except the block pick and the base point.
CASES = [
    ("Rectangle",
     [("mode", "1"), ("w", "84"), ("l", "72"),
      ("cornera", "1"), ("cornerb", "1"), ("cornerc", "1"), ("cornerd", "1"),
      ("second", "2"), ("autohinge", "2")],
     [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
      "90", "90", "90", "90", "No", "No"],
     ("WIDTH", "LENGTH", "Corner")),
    ("OCtagon",
     [("mode", "1"), ("b", "96"), ("a", "84"), ("s2", "24"),
      ("tt", "NA"), ("ss", "NA"), ("s1", "NA"), ("vv", "NA"),
      ("second", "2"), ("autohinge", "2")],
     [None, "Watersedge", "OCtagon", (0, 0), 96.0, 84.0, 24.0,
      "NA", "NA", "NA", "NA", "No", "No"],
     ("overall size", "flat", "corner cut")),
    ("ROund",
     [("mode", "1"), ("b", "96"),
      ("second", "2"), ("autohinge", "2")],
     [None, "Watersedge", "ROund", (0, 0), 96.0, "No", "No"],
     ("Overall diameter",)),
    ("ROund out of round",
     [("mode", "1"), ("b", "96"), ("a", "84"),
      ("second", "2"), ("autohinge", "2")],
     [None, "Watersedge", "ROund", (0, 0), "Outofround", 96.0, 84.0,
      "No", "No"],
     ("Overall diameter", "overall size")),
]

for label, typing, script, never in CASES:
    chart = label.split()[0]
    a = by_prompts(script)
    b = by_chart(chart, typing, [None, (0, 0)])
    ents = same(a, b, label)
    assert not b.globals.get('spa:*form*'), \
        "[%s] spa:*form* survived the run" % label
    asked = [p for p, _ in b.prompts]
    for gone in never:
        assert not any(gone in p for p in asked), \
            "[%s] %r was asked even though the chart answered it: %r" \
            % (label, gone, asked)
    # only the two things a form can never answer are left: the block
    # pick (an entsel in the drawing) and the insertion base point
    assert len(asked) == 2, \
        "[%s] SPA still had to ask %d questions, not 2: %r" \
        % (label, len(asked), asked)
    assert 'Spa Cover Details' in asked[0], asked
    assert 'base point' in asked[1], asked
    print("   %-20s %3d entities, identical from the chart and the prompts"
          % (label, len(ents)))
    print("   %-20s SPA asked only for the block and the base point"
          % '')


print("== a filled cover block drives both outlines ==")
# the same spa with the cover added by Offset -- second, method and the
# lap all come off the form, and the auto-hinge gate with them
cv_prompts = [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
              "90", "90", "90", "90", "Yes", "Offset", 3.0, "No"]
cv_typing = [("mode", "1"), ("w", "84"), ("l", "72"),
             ("cornera", "1"), ("cornerb", "1"), ("cornerc", "1"),
             ("cornerd", "1"),
             ("second", "1"), ("method", "1"), ("gap", "3"),
             ("autohinge", "2")]
a = by_prompts(cv_prompts)
b = by_chart("Rectangle", cv_typing, [None, (0, 0)])
ents = same(a, b, "cover by offset")
print("   %d entities; both outlines from one chart" % len(ents))

# and by Dims, where the second overalls are the ones that travel
cd_prompts = [None, "Coversize", "Rectangle", (0, 0), 84.0, 72.0,
              "90", "90", "90", "90", "Yes", "Dims", 78.0, 66.0, "No"]
cd_typing = [("mode", "2"), ("w", "84"), ("l", "72"),
             ("cornera", "1"), ("cornerb", "1"), ("cornerc", "1"),
             ("cornerd", "1"),
             ("second", "1"), ("method", "2"), ("w2", "78"), ("l2", "66"),
             ("autohinge", "2")]
a = by_prompts(cd_prompts)
b = by_chart("Rectangle", cd_typing, [None, (0, 0)])
ents = same(a, b, "cover by dims")
print("   %d entities; the by-dims pair travels under w2/l2" % len(ents))


print("== a half-filled chart still leaves SPA asking ==")
# the point of the feature: fill in what was measured, answer the rest at
# the command line.  Only the overalls are typed here, so all four
# corners are still prompted for.
b = by_chart("Rectangle",
             [("mode", "1"), ("w", "84"), ("l", "72"),
              ("second", "2"), ("autohinge", "2")],
             [None, (0, 0), "90", "90", "90", "90"])
a = by_prompts([None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
                "90", "90", "90", "90", "No", "No"])
same(a, b, "half-filled chart")
corners = [p for p, _ in b.prompts if 'Corner' in p]
assert len(corners) == 4, "expected 4 corners asked, got %r" % corners
assert not any('WIDTH' in p or 'LENGTH' in p for p, _ in b.prompts), \
    "a supplied overall was asked for anyway"
print("   overalls taken from the chart, all 4 corners still prompted")


print("== LAZSPA refuses to open without SPA ==")
nv = stubbed()          # LAZSPA alone: no SPA in the session
nv.run('c:LAZSPA', [])
said = ' '.join(str(p) for p in nv.printed)
assert 'not loaded' in said, \
    "LAZSPA opened a form whose Insert button could only fail: %r" % nv.printed
assert 'SPA.LSP' in said and 'LAZPASS' in said, nv.printed
assert not OPENED, "a dialog was opened with nothing to receive its answers"
print("   says so plainly and opens nothing")


print("== the state line: two silent drops, said out loud ==")
sv = fresh()
sv.loads('(setq lzs:*vals* nil lzs:*pvals* nil)'
         '(setq lzs:*chart* (lzs:chart "Rectangle"))')


def state(v):
    v.loads('(setq t:*st* (lzs:statetext))')
    return str(v.globals['t:*st*'])


def livekeys(v):
    v.loads('(setq t:*lk* (lzs:livekeys lzs:*chart*))')
    return [str(x) for x in (v.globals['t:*lk*'] or [])]


# a box is named the way the sheet names it
sv.loads('(setq t:*a* (lzs:tagof lzs:*chart* "w"))'
         '(setq t:*b* (lzs:tagof lzs:*chart* "w2"))'
         '(setq t:*c* (lzs:tagof lzs:*chart* "gap"))'
         '(setq t:*d* (lzs:tagof lzs:*chart* "cornera-sz"))')
assert str(sv.globals['t:*a*']) == 'W', sv.globals['t:*a*']
assert str(sv.globals['t:*b*']) == 'W2', sv.globals['t:*b*']
assert str(sv.globals['t:*c*']) == 'the cover lap', sv.globals['t:*c*']
assert str(sv.globals['t:*d*']) == 'Corner A', sv.globals['t:*d*']

LIVE = livekeys(sv)
assert state(sv).startswith('Nothing filled yet'), state(sv)
sv.loads('(lzs:put "w" "84")')
assert state(sv).startswith('1 of %d boxes filled' % len(LIVE)), state(sv)

# THE DEMOTION, which is the one this form has and LAZFORM does not:
# lzs:keyanswer turns an NA into SKIP on any key SPA has no NA for, so
# NA -- a word the form itself tells you to type -- silently means
# "ask" on the wrong box
sv.loads('(setq t:*ok* (lzs:naok lzs:*chart*))')
NAOK = [str(x) for x in (sv.globals['t:*ok*'] or [])]
assert 'l' in NAOK and 'w' not in NAOK, NAOK
sv.loads('(lzs:put "l" "NA")')
assert 'cannot be NA' not in state(sv), \
    "NA on a key that HAS an NA is being complained about: %r" % state(sv)
sv.loads('(lzs:put "w" "NA")')
na = state(sv)
assert na == 'W cannot be NA - SPA needs a number there.', na
sv.loads('(lzs:put "w2" "NA")')
assert 'cannot be NA - SPA needs a number in each of them.' in state(sv), state(sv)
# and it really would have been dropped
sv.loads('(setq t:*ka* (lzs:keyanswer lzs:*chart* "w"))')
assert str(sv.globals['t:*ka*']).upper() == 'SKIP', \
    "the demotion this line reports is not happening: %r" % sv.globals['t:*ka*']

# rubbish outranks it: it is the coarser failure
sv.loads('(lzs:put "w" "wat")')
assert state(sv).startswith('W is not a measurement'), state(sv)

# a full sheet names what stays in the drawing
sv.loads('(setq lzs:*vals* nil)')
for k in LIVE:
    sv.loads('(lzs:put "%s" "24")' % k)
full = state(sv)
assert full.startswith('All %d boxes filled' % len(LIVE)), full
assert 'the block' in full, "the block pick is not mentioned: %r" % full

# a page with one live box says "1 box", never "1 boxes"
sv.loads('(setq lzs:*vals* nil lzs:*pvals* nil)'
         '(setq lzs:*chart* (lzs:chart "ROUnd"))')
assert len(livekeys(sv)) == 1, livekeys(sv)
assert '1 box,' in state(sv), state(sv)
print("   unreadable, NA-where-NA-is-not-an-answer, and the hand-off")


print("== the SPA state line cannot disagree with what is SENT ==")
iv = fresh()
iv.loads('(setq lzs:*vals* nil lzs:*pvals* nil)'
         '(setq lzs:*chart* (lzs:chart "Rectangle"))')
iv.loads('(lzs:put "w" "84") (lzs:put "l" "NA") (lzs:put "w2" "rubbish")'
         '(lzs:put "gap" "")')
iv.loads('(setq t:*lk* (lzs:livekeys lzs:*chart*))'
         '(setq t:*bad* (lzs:unreadable)) (setq t:*na* (lzs:nabad))'
         '(setq t:*togo* (lzs:togo)) (setq t:*form* (lzs:form))')
LK = set(str(x) for x in iv.globals['t:*lk*'])
BAD = set(str(x) for x in (iv.globals['t:*bad*'] or []))
NA = set(str(x) for x in (iv.globals['t:*na*'] or []))
TOGO = set(str(x) for x in (iv.globals['t:*togo*'] or []))
SENT = {str(q.a) if isinstance(q, Dot) else str(q[0])
        for q in iv.globals['t:*form*']} & LK
assert BAD == {'w2'}, BAD
assert NA == set(), NA
assert SENT | TOGO | BAD | NA == LK, (
    "live boxes in none of sent/to-ask/unreadable/NA: %r"
    % sorted(LK - SENT - TOGO - BAD - NA))
for a, b in ((SENT, TOGO), (SENT, BAD), (TOGO, BAD), (SENT, NA), (TOGO, NA)):
    assert not (a & b), "two groups claim %r" % sorted(a & b)
assert 'w2' not in SENT, "an unreadable box reached SPA after all"
print("   %d live boxes partitioned with no overlap and nothing left over"
      % len(LK))

# a greyed box is in none of them
gv = fresh()
gv.loads('(setq lzs:*vals* nil lzs:*pvals* nil)'
         '(setq lzs:*chart* (lzs:chart "Rectangle"))')
# "second = No" stops spa:askother2 at the Yes/No, so the lap and the
# by-dims overalls are never asked
gv.loads('(setq t:*sv* (lzs:lvals "second"))')
NOAT = [str(x) for x in gv.globals['t:*sv*']].index('No')
gv.loads('(lzs:pput "second" %d) (lzs:put "gap" "rubbish")' % NOAT)
gv.loads('(setq t:*d* (lzs:dead lzs:*chart*))')
assert 'gap' in [str(x) for x in gv.globals['t:*d*']], gv.globals['t:*d*']
assert 'gap' not in livekeys(gv), "a greyed box is being counted as live"
gv.loads('(setq t:*b* (lzs:unreadable))')
assert not (gv.globals['t:*b*'] or []), \
    "rubbish in a greyed box is being complained about"
print("   rubbish in a greyed box is neither complained about nor counted")


print("== Insert is held back while a box would be dropped ==")
rv = stubbed()
rv.loads('(setq lzs:*vals* nil lzs:*pvals* nil)'
         '(setq lzs:*chart* (lzs:chart "Rectangle"))')


def accept_mode(v):
    modes = [(str(a[0]), int(a[1])) for a in (v.globals.get('stub:*mode*') or [])]
    hits = [m for k, m in modes if k == 'accept']
    assert hits, "restate never touched the Insert button: %r" % modes
    return hits[0]


rv.loads('(setq stub:*mode* nil stub:*tiles* nil) (lzs:restate)')
assert accept_mode(rv) == 0, "Insert was greyed on a page with nothing wrong"
rv.loads('(setq stub:*mode* nil) (lzs:put "w" "nonsense") (lzs:restate)')
assert accept_mode(rv) == 1, "Insert stayed live with an unreadable box"
# and the demotion holds it back too -- it is just as silent a drop
rv.loads('(setq stub:*mode* nil) (lzs:put "w" "NA") (lzs:restate)')
assert accept_mode(rv) == 1, \
    "Insert stayed live with an NA that SPA would drop unread"
rv.loads('(setq stub:*mode* nil) (lzs:put "w" "84") (lzs:restate)')
assert accept_mode(rv) == 0, "fixing the box did not let Insert back"
rv.loads('(setq t:*s* (stub:tile "state"))')
assert rv.globals['t:*s*'] is not None, "the state tile was never written"
print("   greyed for both drops, live again the moment either is fixed")

wv = stubbed(with_spa=True)
wv.loads('(setq stub:*rcs* \'(0)) (setq t:*f* (lzs:show "Rectangle"))')
acts = {str(a[0]): str(a[1]) for a in (wv.globals.get('stub:*act*') or [])}
wv.loads('(setq t:*b* (lzs:boxkeys (lzs:chart "Rectangle")))')
for k in [str(x) for x in wv.globals['t:*b*']]:
    assert 'lzs:restate' in acts[k], \
        "box %r changes the page without restating it" % k
wv.loads('(setq t:*l* (lzs:listkeys))')
for k in [str(x) for x in wv.globals['t:*l*']]:
    assert 'lzs:listpick' in acts[k], k
wv.loads('(setq t:*c* (lzs:corners (lzs:chart "Rectangle")))')
for c in wv.globals['t:*c*']:
    stem = str(c[0])
    assert 'lzs:restate' in acts[stem + '-sz'], stem
    assert 'lzs:cornerpick' in acts[stem], stem
wv.loads('(setq t:*st* (stub:tile "state"))')
assert wv.globals['t:*st*'] is not None, \
    "the page opened without ever writing its state line"
print("   %d callbacks restate; the line is written before the page opens"
      % len(acts))


print("ALL LAZSPA TESTS PASSED")
