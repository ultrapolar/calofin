"""LAZSTEP: say how many steps, then fill the generated drawing in.

The headline is the second page: it is not a stored chart but one
BUILT from the count typed on page one -- three steps draw three
treads, eight draw eight -- so most of what follows is asserted for a
range of counts rather than for one picture.

The dialog cannot run here (the VM has no DCL), so the surface is
stubbed two ways, exactly as tests/test_lazform.py does it: Python
builtins for vector_image / fill_image / dimx_tile / dimy_tile /
new_dialog, LISP defun stubs for the file I/O and the dialog verbs,
and a start_dialog that replays the file's OWN action_tile expressions
with $key and $value bound. Nothing here reimplements the tool.

Nine jobs:

1. The generated chart is coherent at every count: keys unique,
   per-mille co-ordinates in bounds, dimensions axis-consistent and
   labelled, exactly N treads and N+1 depths.
2. Every key the form can send is a key the routine actually reads --
   grepped out of CORNERSTP.lsp / HEMISTEP.lsp / NORMIESTEP.lsp, so a
   key nothing reads fails here rather than being typed into and
   dropped.
3. The generated DCL is well formed, with one tile key per answer, no
   image_button, and the wedge boxes landing on their letters.
4. The DRAWING is captured and checked: every vector inside the tile,
   in a colour the file declares, and the value-replaces-letter rule
   actually holding.
5. The three-state contract, including the one place it differs from
   LAZFORM's -- NA at a tread would END the run.
6. The count is validated before a page is built for it, and the
   ceiling is real.
7. Changing the count regenerates the drawing and keeps what was typed
   for the steps that still exist.
8. The greying rules.
9. END TO END, all three types: fill the form in for a 3-step run,
   press Insert, and the geometry is identical entity for entity to
   the same run answered at the prompts, with no tread or depth prompt
   shown at all.

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
LSP = os.path.join(REPO, 'lisp', 'lazstep', 'LAZSTEP.lsp')
CORNERSTP = os.path.join(REPO, 'lisp', 'cornerstp', 'CORNERSTP.lsp')
HEMISTEP = os.path.join(REPO, 'lisp', 'cornerstp', 'HEMISTEP.lsp')
NORMIESTEP = os.path.join(REPO, 'lisp', 'cornerstp', 'NORMIESTEP.lsp')

TOOLPATH = {'CORNERSTP': CORNERSTP,
            'HEMISTEP': HEMISTEP,
            'NORMIESTEP': NORMIESTEP}

#: the prefix each tool's store helpers carry
PREFIX = {'CORNERSTP': 'cs', 'HEMISTEP': 'hs', 'NORMIESTEP': 'ns'}

DX, DY = 520, 376          # a plausible tile size, in pixels
DRAW = {'vec': [], 'fill': [], 'list': []}
OPENED = []


def tier(path):
    """The file the VM will actually load, so a grep of "the source"
    greps the tier under test rather than always the standalone one."""
    root = os.environ.get('CALOFIN_LISP_ROOT')
    if not root:
        return path
    stem = os.path.basename(path)
    for base in (os.path.join(REPO, root, 'parts'), os.path.join(REPO, root)):
        cand = os.path.join(base, stem)
        if os.path.exists(cand):
            return cand
    return path


def _reset():
    OPENED[:] = []
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


@_b('new_dialog')
def _newdlg(vm, a):
    # 2 args on the first open, 4 once a position is known -- record
    # which, so the position threading is provable
    OPENED.append((str(a[0]), len(a)))
    vm.globals[lispvm.Sym('stub:*opened*')] = str(a[0])
    vm.globals[lispvm.Sym('stub:*act*')] = None
    return True


STUB = '''
(setq stub:*rc* 0 stub:*written* nil stub:*opened* nil stub:*mode* nil stub:*tiles* nil)
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
(defun set_tile (k v)
  (setq stub:*tiles* (cons (list k v) stub:*tiles*)) v)
(defun stub:tile (k / p) (if (setq p (assoc k stub:*tiles*)) (cadr p)))
(defun action_tile (k expr)
  (setq stub:*act* (cons (list k expr) stub:*act*)) t)
(defun start_dialog ( / p k)
  (setq stub:*done* nil)          ; each page starts un-closed
  ;; type into every box the scenario named, the way a user tabbing
  ;; through them would -- through the REAL action expression
  (foreach p stub:*type*
    (if (and (not stub:*done*) (setq k (assoc (car p) stub:*act*)))
      (progn (setq $value (cadr p) $key (car p))
             (eval (read (strcat "(progn " (cadr k) ")")))
             ;; an entry that closed the dialog is spent: left in the
             ;; list it would re-fire on the page it just opened
             (if stub:*done*
               (setq stub:*type* (vl-remove p stub:*type*))))))
  (if stub:*done* stub:*done* stub:*rc*))
(setq stub:*act* nil stub:*type* nil)
'''


def fresh(tool=None):
    _reset()
    vm = VM()
    if tool:
        vm.load(TOOLPATH[tool])
        for s in ('STANDARD INCHES', 'SIDE STANDARD'):
            vm.tables['DIMSTYLE'].add(s)
        vm.sysvars['DIMTXT'], vm.sysvars['DIMSCALE'] = 0.125, 48.0
    vm.load(LSP)
    return vm


def stubbed(tool=None):
    vm = fresh(tool)
    vm.loads(STUB)
    return vm


def typed(pairs):
    """A stub:*type* script: (key value) fired through the tile's own
    action expression, in order, page after page."""
    return "(setq stub:*type* '(%s))" % ' '.join(
        '("%s" "%s")' % (k, v) for k, v in pairs)


def chart(vm, ty, n):
    vm.loads('(setq t:*c* (lzt:chart "%s" %d))' % (ty, n))
    return vm.globals['t:*c*']


COUNTS = (1, 2, 3, 4, 5, 6, 7, 8)
TYPES = ('CORNERSTP', 'HEMISTEP', 'NORMIESTEP')


print("== the file loads, and the chart is GENERATED for the count ==")
vm = fresh()
ver = vm.globals.get('*lazstep-version*')
assert ver and re.fullmatch(r'v\d+\.\d+', str(ver)), ver
MAX = int(vm.globals['lzt:*max-steps*'])
assert MAX == 8, "the ceiling moved: %r" % MAX
assert [str(t[0]) for t in vm.globals['lzt:*types*']] == list(TYPES), \
    "the three step routines are not the three step routines"

for ty in TYPES:
    seen = []
    for n in COUNTS:
        c = chart(vm, ty, n)
        assert str(c[0]) == ty, c[0]
        outline, dims, cuts = c[2], c[3], [int(x) for x in c[4]]
        assert outline and dims, (ty, n)
        keys = [str(d[1]) for d in dims]
        assert len(keys) == len(set(keys)), \
            "%s/%d: duplicate keys %r" % (ty, n, keys)
        for d in dims:
            x1, y1, x2, y2 = (int(d[2]), int(d[3]), int(d[4]), int(d[5]))
            assert all(0 <= v <= 1000 for v in (x1, y1, x2, y2)), (ty, n, d)
            assert str(d[6]) in ('h', 'v'), d
            assert (y1 == y2) if str(d[6]) == 'h' else (x1 == x2), \
                "%s/%d: a %r dimension must run that way: %r" \
                % (ty, n, str(d[6]), [str(x) for x in d])
            assert (x1, y1) != (x2, y2), \
                "%s/%d: zero-length dimension %r" % (ty, n, str(d[0]))
            assert str(d[7]).strip(), "%s/%d: %r has no label" % (ty, n, d[0])
            assert str(d[0]).strip(), "%s/%d: a dimension with no letter" % (ty, n)
        letters = [str(d[0]) for d in dims]
        assert len(letters) == len(set(letters)), \
            "%s/%d: two dimensions share a letter: %r" % (ty, n, letters)
        # EXACTLY N treads and N+1 depths, whatever the count
        treads = [k for k in keys if k.startswith('tread')]
        depths = [k for k in keys if k.startswith('depth')]
        widths = [k for k in keys if k.startswith('width')]
        assert sorted(treads) == sorted('tread%d' % i for i in range(1, n + 1)), \
            "%s/%d: treads are %r" % (ty, n, treads)
        assert sorted(depths) == sorted(
            ['depthafter'] + ['depth%d' % i for i in range(1, n + 1)]), \
            "%s/%d: depths are %r" % (ty, n, depths)
        if ty == 'NORMIESTEP':
            assert widths == ['width'], \
                "a straight run has ONE width for the whole run: %r" % widths
        else:
            assert sorted(widths) == sorted(
                'width%d' % i for i in range(1, n + 1)), \
                "%s/%d: widths are %r" % (ty, n, widths)
        # every cut lands on a horizontal dimension, and every
        # horizontal dimension lands on a cut
        for y in cuts:
            vm.loads('(setq t:*n* (length (lzt:cutdims t:*c* %d)))' % y)
            assert int(vm.globals['t:*n*']) > 0, \
                "%s/%d: cut at %d has no dimension on it" % (ty, n, y)
        hys = set(int(d[3]) for d in dims if str(d[6]) == 'h')
        assert hys == set(cuts), \
            "%s/%d: horizontal dims at %r but cuts at %r" % (ty, n, hys, cuts)
        seen.append((n, len(dims), len(cuts)))
    print("   %-11s %s" % (ty, ", ".join("%d steps -> %d dims/%d row(s)" % s
                                         for s in seen[:3] + seen[-1:])))


print("== the outline stays inside the picture, arcs included ==")
for ty in TYPES:
    for n in COUNTS:
        vm.loads('(setq t:*c* (lzt:chart "%s" %d))'
                 '(setq t:*o* (mapcar \'lzt:flatten (lzt:c-outline t:*c*)))'
                 % (ty, n))
        for poly in vm.globals['t:*o*']:
            pts = [int(v) for v in poly]
            assert len(pts) % 2 == 0 and len(pts) >= 4, (ty, n, pts)
            assert all(0 <= v <= 1000 for v in pts), \
                "%s/%d: outline leaves the picture: %r" % (ty, n, pts[:8])
print("   every polyline and every flattened arc inside 0..1000, all counts")


print("== the profile reads down and to the LEFT, N risers and N treads ==")
# The three routines all draw the flight that way from the one pick, so
# the picture that illustrates it has to as well -- a profile drawn the
# other way round would have the operator reading the depth chain
# backwards off the sheet.
for ty in TYPES:
    for n in (1, 3, 8):
        vm.loads('(setq t:*c* (lzt:chart "%s" %d))' % (ty, n))
        vm.loads('(setq t:*p* (lzt:profile %d))' % n)
        segs = [[int(v) for v in s] for s in vm.globals['t:*p*']]
        drops = [s for s in segs if s[0] == s[2]]
        runs = [s for s in segs if s[1] == s[3]]
        assert len(drops) == n + 1, "%s/%d: %d drops" % (ty, n, len(drops))
        assert len(runs) == n, "%s/%d: %d treads" % (ty, n, len(runs))
        # down: each drop starts where the one before ended
        for i in range(1, len(drops)):
            assert drops[i][1] == drops[i - 1][3], \
                "%s/%d: the flight does not join up: %r" % (ty, n, drops)
            assert drops[i][3] > drops[i][1], "a drop must go DOWN the page"
        # and to the left: every tread runs left off its own foot
        for s in runs:
            assert s[2] < s[0], \
                "%s/%d: a tread runs right, not left: %r" % (ty, n, s)
        # the depth dims climb with it -- each one further left and
        # lower than the one above, the way the routines place them
        dd = [d for d in vm.globals['t:*c*'][3] if str(d[1]).startswith('depth')]
        xs = [int(d[2]) for d in dd]
        ys = [int(d[3]) for d in dd]
        assert all(xs[i] <= xs[i - 1] for i in range(1, len(xs))), \
            "%s/%d: the depth dims do not march left: %r" % (ty, n, xs)
        assert all(ys[i] > ys[i - 1] for i in range(1, len(ys))), \
            "%s/%d: the depth dims do not descend: %r" % (ty, n, ys)
print("   N+1 drops, N treads, joined up, running down and to the left")


print("== every key the form can send is a key the routine reads ==")
# The whole point of a form is that the routine reads these back; a key
# nothing reads would be typed into and silently dropped.  Read off the
# three sources rather than restated here, per tool, so a renamed key
# fails this instead of going quiet.
#
# Where each is read:
#   plain keys      (cs|hs|ns)-fhas / -ftake / -fnum / -fkw  'key
#                   e.g. CORNERSTP.lsp "(cs-fhas 'steps)" at the top of
#                   c:CORNERSTP, "(cs-fkw 'direction ...)" at step 5
#   numbered keys   (cs|hs|ns)-fnkey "stem" i  -- the tread, width and
#                   depth loops, e.g. "(cs-fnkey \\"tread\\" n)" in the
#                   step loop and "(cs-fnkey \\"depth\\" (1+ ix))" in the
#                   side profile
#   depthafter      named outright beside that last one, as the key for
#                   the drop after the last tread
PLAIN = re.compile(r"\b(?:cs|hs|ns)-f(?:has|take|num|kw)\s+'([a-z0-9-]+)")
STEM = re.compile(r'\b(?:cs|hs|ns)-fnkey\s+"([a-z]+)"')
NUMBERED = re.compile(r'^([a-z]+)(\d+)$')

for ty in TYPES:
    src = open(tier(TOOLPATH[ty])).read()
    plain = set(PLAIN.findall(src))
    stems = set(STEM.findall(src))
    if "'depthafter" in src:
        plain.add('depthafter')
    assert 'steps' in plain, \
        "%s has no step-count key -- the whole two-page flow rests on it" % ty
    vm.loads('(setq lzt:*type* "%s")'
             '(setq t:*a* (mapcar \'car (lzt:asks)))' % ty)
    page1 = [str(x) for x in vm.globals['t:*a*']]
    vm.loads('(setq t:*k* (lzt:keys (lzt:chart "%s" 5)))' % ty)
    page2 = [str(x) for x in vm.globals['t:*k*']]
    for k in page1 + page2:
        if k in plain:
            continue
        m = NUMBERED.match(k)
        assert m and m.group(1) in stems, (
            "%s: the form can send %r, which nothing in %s reads -- it "
            "would be typed into and dropped on the floor"
            % (ty, k, os.path.basename(TOOLPATH[ty])))
    print("   %-11s %2d page-one + %2d drawing keys, every one read by %s"
          % (ty, len(page1), len(page2), PREFIX[ty] + '-f*'))


print("== the generated DCL is well formed, for every type and count ==")
TILES = {'row', 'column', 'boxed_column', 'button', 'text', 'edit_box',
         'image', 'image_button', 'toggle', 'popup_list', 'spacer'}


def pages(vm, ty, n):
    """The whole generated file for one type at one count."""
    vm.loads('(setq lzt:*type* "%s" lzt:*steps* %d'
             '      lzt:*chart* (lzt:chart "%s" %d))' % (ty, n, ty, n))
    vm.loads('(setq t:*all* (lzt:dcl-lines))')
    return [str(x) for x in vm.globals['t:*all*']]


def slice_dialog(all_lines, name):
    i = all_lines.index(name + ' : dialog {')
    d = 0
    for j in range(i, len(all_lines)):
        d += all_lines[j].count('{') - all_lines[j].count('}')
        if d == 0:
            return all_lines[i:j + 1]
    raise AssertionError("%s never closes" % name)


def well_formed(lines, label):
    depth = 0
    for line in lines:
        assert line.count('"') % 2 == 0, "%s: odd quotes: %r" % (label, line)
        depth += line.count('{') - line.count('}')
        assert depth >= 0, "%s: %r" % (label, line)
    assert depth == 0, "%s: unbalanced braces" % label
    for line in lines[1:]:
        t = line.strip()
        if t in ('}', 'spacer;', ''):
            continue
        m = re.match(r': ([a-z_]+) \{', t)
        if m:
            assert m.group(1) in TILES, \
                "%s: unknown tile %r" % (label, m.group(1))
        for clause in re.findall(r'[a-z_]+ = (?:"[^"]*"|[a-z0-9.]+)(;?)', t):
            assert clause == ';', \
                "%s: a DCL clause without its semicolon: %r" % (label, line)


for ty in TYPES:
    for n in COUNTS:
        ALL = pages(vm, ty, n)
        well_formed(ALL, "%s/%d" % (ty, n))
        opens = [ln.split(' : ')[0] for ln in ALL if ln.endswith(' : dialog {')]
        # page one for all three types -- so a tab switch needs nothing
        # from disk -- plus page two for the chart the count generated
        assert len(opens) == 4, "%s/%d: %d dialogs %r" % (ty, n, len(opens), opens)
        assert len(opens) == len(set(opens)), "duplicate dialog names: %r" % opens
        vm.loads('(setq t:*n1* (lzt:dlgname 1 "%s"))'
                 '(setq t:*n2* (lzt:dlgname 2 "%s"))' % (ty, ty))
        p1 = slice_dialog(ALL, str(vm.globals['t:*n1*']))
        p2 = slice_dialog(ALL, str(vm.globals['t:*n2*']))
        for d, label in ((p1, 'page one'), (p2, 'page two')):
            assert d[0].endswith(' : dialog {'), \
                "%s %s: does not open with its dialog line: %r" % (ty, label, d[0])
            assert d[1].strip().startswith('label = '), \
                "%s %s: the label is not first inside the dialog" % (ty, label)
            text = '\n'.join(d)
            tk = re.findall(r'key = "([^"]+)"', text)
            assert len(tk) == len(set(tk)), \
                "%s %s: duplicate tile keys: %r" % (
                    ty, label, sorted(k for k in tk if tk.count(k) > 1))
            assert text.count('is_cancel = true') == 1, "%s %s" % (ty, label)
            assert text.count('is_default = true') == 1, "%s %s" % (ty, label)
            assert ': image_button' not in text, (
                "%s %s: an image_button -- it repaints on hover and a DCL "
                "image tile is not retained, so the drawing would vanish "
                "the first time the cursor crossed it" % (ty, label))

        # --- page one: the count, the tabs, and one tile per question
        t1 = '\n'.join(p1)
        k1 = re.findall(r'key = "([^"]+)"', t1)
        assert 'steps' in k1, "%s: page one has no step-count box" % ty
        for other in TYPES:
            assert 'tab_%s' % other in k1, \
                "%s: page one has no tab for %s" % (ty, other)
        vm.loads('(setq t:*a* (lzt:asks-of "%s"))' % ty)
        for q in vm.globals['t:*a*']:
            stem, kind = str(q[0]), str(q[1])
            assert stem in k1, "%s: page one has no tile for %r" % (ty, stem)
            want = 'popup_list' if kind == 'LIST' else 'edit_box'
            assert re.search(r': %s \{ key = "%s"' % (want, re.escape(stem)), t1), \
                "%s: %r should be a %s" % (ty, stem, want)

        # --- page two: one tile per drawing key, no more, no fewer
        t2 = '\n'.join(p2)
        k2 = re.findall(r'key = "([^"]+)"', t2)
        vm.loads('(setq t:*k* (lzt:keys lzt:*chart*))'
                 '(setq t:*wk* (lzt:wedge-keys lzt:*chart*))')
        keys = [str(x) for x in vm.globals['t:*k*']]
        wk = [str(x) for x in vm.globals['t:*wk*']]
        assert set(keys) <= set(k2), \
            "%s/%d: drawing answers with no box: %r" % (
                ty, n, sorted(set(keys) - set(k2)))
        # a wedge dim's box IS the drawing's own row, so it has no pick
        # button; a column dim has one
        for k in keys:
            if k in wk:
                assert 'pick_%s' % k not in k2, \
                    "%s/%d: wedge dim %s also has a pick button" % (ty, n, k)
            else:
                assert 'pick_%s' % k in k2, \
                    "%s/%d: column dim %s has no letter button" % (ty, n, k)
        # the treads are the wedge row(s); the widths and depths are not
        assert sorted(wk) == sorted(k for k in keys if k.startswith('tread')), \
            "%s/%d: the wedge rows are %r" % (ty, n, wk)
        for b in range(len(vm.globals['lzt:*chart*'][4]) + 1):
            assert 'chart%d' % b in k2, "%s/%d: no band tile chart%d" % (ty, n, b)
        assert 'chart%d' % (len(vm.globals['lzt:*chart*'][4]) + 1) not in k2, \
            "%s/%d: more band tiles than bands" % (ty, n)
        assert re.search(r': image \{ key = "chart0"', t2), \
            "%s/%d: no passive chart image tile" % (ty, n)
        for extra in ('accept', 'cancel', 'back'):
            assert extra in k2, "%s/%d: page two has no %r tile" % (ty, n, extra)
print("   %d type(s) x %d count(s): 4 dialogs each, balanced, one tile per key"
      % (len(TYPES), len(COUNTS)))


print("== the wedge boxes land on their letters, and the rows fit ==")
# DCL does not scroll: a row wider than the chart it sits under drags
# the whole dialog past the screen, which is a dialog that does not
# open.  That is why the tread chain STAGGERS onto two rows past four
# steps rather than growing one row without limit.
CHART_W = int(vm.globals['lzt:*chart-w*'])
for ty in TYPES:
    worst, widest = 0.0, 0.0
    for n in COUNTS:
        ALL = pages(vm, ty, n)
        vm.loads('(setq t:*n2* (lzt:dlgname 2 "%s"))' % ty)
        p2 = slice_dialog(ALL, str(vm.globals['t:*n2*']))
        centers = {str(d[1]): (int(d[2]) + int(d[4])) / 2.0 * CHART_W / 1000.0
                   for d in vm.globals['lzt:*chart*'][3]}
        pos, expect = None, False
        for line in p2:
            t = line.strip()
            if re.match(r': image \{ key = "chart\d+"', t):
                expect, pos = True, None
            elif expect and t == ': row {':
                pos, expect = 0.0, False
            elif expect:
                expect = False
            elif pos is not None:
                m = re.match(r': spacer \{ width = ([0-9.]+); \}', t)
                if m:
                    pos += float(m.group(1))
                    continue
                if t == '}':
                    widest = max(widest, pos)
                    pos = None
                    continue
                m = re.match(r': edit_box \{ key = "([^"]+)"; label = "([^"]+)"; '
                             r'edit_width = (\d+)', t)
                if m:
                    k, lbl, ed = m.group(1), m.group(2), int(m.group(3))
                    w = len(lbl) + 4.0 + ed
                    got = pos + w / 2.0
                    worst = max(worst, abs(got - centers[k]))
                    assert abs(got - centers[k]) <= 3.0, (
                        "%s/%d: wedge box %s centred at %.1f cells, its "
                        "letter at %.1f" % (ty, n, k, got, centers[k]))
                    pos += w
    assert widest <= CHART_W, (
        "%s: the widest wedge row is about %.1f cells against a chart of %d "
        "-- DCL will not scroll it" % (ty, widest, CHART_W))
    print("   %-11s worst drift %.1f cell(s), widest row %.1f of %d"
          % (ty, worst, widest, CHART_W))


print("== nothing is wider than a screen will take ==")
# DCL does not scroll, so a line wider than the screen is a dialog that
# will not open.  Two budgets: any single labelled line, and the SIDE
# COLUMN of page two, which stands beside a chart 58 cells wide.
LINE_BUDGET = 90
COLUMN_BUDGET = 46
for ty in TYPES:
    for n in COUNTS:
        ALL = pages(vm, ty, n)
        vm.loads('(setq t:*n1* (lzt:dlgname 1 "%s"))'
                 '(setq t:*n2* (lzt:dlgname 2 "%s"))' % (ty, ty))
        for name, budget in ((str(vm.globals['t:*n1*']), LINE_BUDGET),
                             (str(vm.globals['t:*n2*']), LINE_BUDGET)):
            d = slice_dialog(ALL, name)
            for line in d:
                t = line.strip()
                m = re.search(r'label = "([^"]*)"', t)
                if not m:
                    continue
                w = len(m.group(1)) + 4
                m2 = re.search(r'edit_width = (\d+)', t)
                if m2:
                    w += int(m2.group(1)) + 4
                assert w <= budget, (
                    "%s/%d: a line about %d cells wide, over the %d budget: %r"
                    % (ty, n, w, budget, t))
        # ...and the side column, row by row: a button plus a box plus
        # its label, which is what stands beside the chart
        d = slice_dialog(ALL, str(vm.globals['t:*n2*']))
        row, wide = None, 0
        for line in d:
            t = line.strip()
            if t == ': row {':
                row = 0.0
            elif t == '}' and row is not None:
                wide = max(wide, row)
                row = None
            elif row is not None:
                m = re.match(r': button \{ key = "pick_', t)
                if m:
                    row += len(re.search(r'label = "([^"]*)"', t).group(1)) + 4
                m = re.match(r': edit_box \{ key = "[^"]+"; edit_width = (\d+); '
                             r'label = "([^"]*)"', t)
                if m:
                    row += int(m.group(1)) + len(m.group(2)) + 4
        assert wide <= COLUMN_BUDGET, (
            "%s/%d: the side column is about %.0f cells wide against a chart "
            "of %d -- together they would run past the screen"
            % (ty, n, wide, CHART_W))
print("   every labelled line under %d cells; the side column under %d"
      % (LINE_BUDGET, COLUMN_BUDGET))


print("== the drawing lands inside the tile, in declared colours ==")
COLS = {}
for name in ('line', 'back', 'dim', 'val', 'hi'):
    COLS[name] = int(vm.globals['lzt:*col-%s*' % name])
for ty in TYPES:
    for n in (1, 3, 8):
        _reset()
        vm.loads('(setq lzt:*vals* nil lzt:*focus* nil'
                 '      lzt:*chart* (lzt:chart "%s" %d)) (lzt:redraw)' % (ty, n))
        assert DRAW['vec'], "%s/%d drew nothing" % (ty, n)
        for v in DRAW['vec']:
            x1, y1, x2, y2, col = v
            assert 0 <= x1 <= DX and 0 <= x2 <= DX, \
                "%s/%d: vector off the tile: %r" % (ty, n, v)
            assert 0 <= y1 <= DY and 0 <= y2 <= DY, \
                "%s/%d: vector off the tile: %r" % (ty, n, v)
            assert col in COLS.values(), \
                "%s/%d: undeclared colour %r in %r" % (ty, n, col, v)
        for f in DRAW['fill']:
            x, y, w, h, col = f
            assert x >= 0 and y >= 0 and x + w <= DX and y + h <= DY, \
                "%s/%d: fill off the tile: %r" % (ty, n, f)
        if n == 8:
            print("   %-11s %3d vectors, %2d fills at 8 steps, all inside %dx%d"
                  % (ty, len(DRAW['vec']), len(DRAW['fill']), DX, DY))


print("== a typed value replaces its letter on the drawing ==")
_reset()
vm.loads('(setq lzt:*vals* nil lzt:*focus* nil'
         '      lzt:*chart* (lzt:chart "CORNERSTP" 3)) (lzt:redraw)')
assert not [v for v in DRAW['vec'] if v[4] == COLS['val']], \
    "nothing has been typed, yet something is drawn as a value"
line_blank = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
# the WEDGE dims draw nothing at all -- their row of the drawing is a
# row of real boxes -- so this is checked on the ones that stay on the
# picture: a width and a depth
_reset()
vm.loads('(lzt:put "width1" "60") (lzt:put "depth1" "7.5") (lzt:redraw)')
vals = [v for v in DRAW['vec'] if v[4] == COLS['val']]
line_now = len([v for v in DRAW['vec'] if v[4] == COLS['line']])
assert vals, "a typed value was not drawn"
assert line_now < line_blank, (
    "W1 and D1 are still being drawn after being answered (%d outline "
    "strokes vs %d blank)" % (line_now, line_blank))
print("   %d value strokes appear; letter strokes fall %d -> %d"
      % (len(vals), line_blank, line_now))

# and typing into a WEDGE key changes nothing: its box is a real tile
_reset()
vm.loads('(setq lzt:*vals* nil) (lzt:redraw)')
base = len(DRAW['vec'])
_reset()
vm.loads('(lzt:put "tread1" "24") (lzt:put "tread2" "24") (lzt:redraw)')
assert len(DRAW['vec']) == base, (
    "typing into a wedge box changed the drawing: %d -> %d strokes"
    % (base, len(DRAW['vec'])))
print("   the tread boxes draw nothing -- they are real tiles on the row")


print("== the three-state contract, and the one place it differs ==")
for t, expect in (('', 'SKIP'),
                  ('   ', 'SKIP'),
                  ('NA', None),
                  ('na', None),
                  (' na ', None),
                  ('24', 24.0),
                  ("2'6\"", 'NUMBER'),
                  ('not a number', 'SKIP')):
    vm.loads('(setq t:*a* (lzt:answer "%s"))'
             % t.replace('\\', '\\\\').replace('"', '\\"'))
    got = vm.globals['t:*a*']
    if expect == 'SKIP':
        assert str(got).upper() == 'SKIP', "%r gave %r" % (t, got)
    elif expect is None:
        assert got is None, "%r gave %r, expected nil (NA)" % (t, got)
    elif expect == 'NUMBER':
        assert isinstance(got, float) and got > 0, "%r gave %r" % (t, got)
    else:
        assert abs(float(got) - expect) < 1e-9, "%r gave %r" % (t, got)
# the whole-number boxes refuse anything that is not one
for t, expect in (('3', 3), ('08', 8), ('', None), ('0', None),
                  ('-2', None), ('2.5', None), ('three', None)):
    vm.loads('(setq t:*i* (lzt:int "%s"))' % t)
    got = vm.globals['t:*i*']
    if expect is None:
        assert got is None, "%r gave %r, expected nil" % (t, got)
    else:
        assert int(got) == expect, "%r gave %r" % (t, got)
print("   empty and rubbish both ask; NA means NA; a whole-number box")
print("   takes whole numbers only")

# NA at a TREAD is the exception, and it is not cosmetic: nil is what
# ends the tread loop, so an NA tread would stop the flight short of
# the very count the drawing was built for.
vm.loads('(setq lzt:*type* "NORMIESTEP" lzt:*steps* 3 lzt:*sel* nil'
         '      lzt:*chart* (lzt:chart "NORMIESTEP" 3))'
         '(setq lzt:*vals* nil)'
         '(lzt:put "tread1" "NA") (lzt:put "tread2" "24")'
         '(lzt:put "width" "NA")'
         '(setq t:*f* (lzt:form))')


def pair(p):
    # an alist pair is a Dot when it has a value and a one-element LIST
    # when it does not: (cons 'g nil) is the list (g)
    return (str(p.a), p.b) if isinstance(p, Dot) else (str(p[0]), None)


form = dict(pair(p) for p in vm.globals['t:*f*'])
assert 'tread1' not in form, (
    "NA at a tread was sent as nil -- that is what ENDS the run, so the "
    "flight would stop short of the count the drawing was built for")
assert abs(float(form['tread2']) - 24.0) < 1e-9, form
assert 'width' in form and form['width'] is None, \
    "NA in a width must travel as nil -- it means fit to the walls"
assert int(form['steps']) == 3, "the count must travel, as an integer"
print("   NA in a width travels as nil; NA at a tread counts as empty")


print("== the count is checked before a page is built for it ==")
for bad, why in (('0', 'zero'), ('-1', 'negative'), ('nine', 'a word'),
                 ('2.5', 'a fraction'), ('', 'empty')):
    v = stubbed()
    v.loads(typed([('steps', bad), ('accept', 'a'), ('cancel', 'x')]))
    v.loads('(setq t:*f* (lzt:show))')
    assert v.globals['t:*f*'] is None, "%s was accepted as a count" % why
    assert not [n for n, _ in OPENED if '_p2_' in n], \
        "%s opened a drawing page: %r" % (why, OPENED)
    assert str(v.globals['lzt:*msg*']).strip(), \
        "%s was refused with no message" % why
v = stubbed()
v.loads(typed([('steps', '9'), ('accept', 'a'), ('cancel', 'x')]))
v.loads('(setq t:*f* (lzt:show))')
assert not [n for n, _ in OPENED if '_p2_' in n], \
    "nine steps opened a page anyway: %r" % OPENED
assert '8' in str(v.globals['lzt:*msg*']), \
    "the ceiling message does not name the ceiling: %r" % v.globals['lzt:*msg*']
print("   0, -1, 2.5, a word and an empty box all refused with a message;")
print("   9 is refused too and the message names the ceiling of 8")


print("== the page loop: tabs, Back, and the position round-trip ==")
v = stubbed()
v.loads(typed([('steps', '3'), ('accept', 'a'),
               ('tread1', '24'), ('tread2', '24'), ('tread3', '24'),
               ('cancel', 'x')]))
v.loads('(setq lzt:*type* "CORNERSTP") (setq t:*f* (lzt:show))')
names = [n for n, _ in OPENED]
assert names[0].endswith('_p1_cornerstp'), names
assert names[1].endswith('_p2_cornerstp'), names
assert DRAW['vec'], "the drawing page opened and drew nothing into its chart"
# DCL has no way to ask an open dialog where it is; done_dialog
# reporting its position as it closes is the only chance to find out,
# and new_dialog only accepts one back in its FOUR-argument form.
assert [k for _, k in OPENED][:2] == [2, 4], (
    "the second page did not carry the dialog's position back: %r" % OPENED)
wired = {str(a[0]) for a in (v.globals.get('stub:*act*') or [])}
assert not [k for k in wired if k.startswith('chart')], (
    "an action is wired to a chart tile: it would be repainted on hover "
    "and a DCL image tile is not retained")
print("   page one -> page two, drawn on open, reopened where it was left")

# a tab switches the routine being filled in, and page one is regenerated
v = stubbed()
v.loads(typed([('tab_HEMISTEP', 'x'), ('cancel', 'c')]))
v.loads('(setq lzt:*type* "CORNERSTP") (setq t:*f* (lzt:show))')
assert str(v.globals['lzt:*type*']) == 'HEMISTEP', \
    "the tab did not switch the routine: %r" % v.globals['lzt:*type*']
assert [n for n, _ in OPENED] == ['lazstep_p1_cornerstp', 'lazstep_p1_hemistep'], \
    OPENED
print("   a tab closes page one and reopens it on the other routine")


print("== changing the count regenerates the drawing, keeping what fits ==")
# five steps, five treads typed, Back, three steps: the drawing is
# built again for three, tread1..3 keep what was typed, and tread4 and
# tread5 are still in the store for a trip back up.
v = stubbed()
v.loads(typed([('steps', '5'), ('accept', 'a'),
               ('tread1', '11'), ('tread2', '12'), ('tread3', '13'),
               ('tread4', '14'), ('tread5', '15'), ('back', 'b'),
               ('steps', '3'), ('accept', 'c'),
               ('accept', 'd')]))
v.loads('(setq lzt:*type* "NORMIESTEP") (setq t:*f* (lzt:show))')
v.loads('(setq t:*n* (length (lzt:treads lzt:*chart*)))')
assert int(v.globals['t:*n*']) == 3, (
    "the drawing was not rebuilt for the new count: %r treads"
    % v.globals['t:*n*'])
form = dict(pair(p) for p in v.globals['t:*f*'])
assert int(form['steps']) == 3, form
assert sorted(k for k in form if k.startswith('tread')) == \
    ['tread1', 'tread2', 'tread3'], \
    "the shrunk run still carries the steps that went away: %r" % sorted(form)
for k, want in (('tread1', 11.0), ('tread2', 12.0), ('tread3', 13.0)):
    assert abs(float(form[k]) - want) < 1e-9, \
        "%s lost what was typed for it: %r" % (k, form.get(k))
for k in ('tread4', 'tread5'):
    v.loads('(setq t:*v* (lzt:get "%s"))' % k)
    assert str(v.globals['t:*v*']) in ('14', '15'), \
        "%s was thrown away rather than kept for a trip back up" % k
assert [n for n, _ in OPENED] == ['lazstep_p1_normiestep',
                                  'lazstep_p2_normiestep',
                                  'lazstep_p1_normiestep',
                                  'lazstep_p2_normiestep'], OPENED
print("   5 -> Back -> 3: three treads sent, all three keep their numbers,")
print("   and 4 and 5 are still in the store")


print("== greying: what a run will never ask is greyed, and does not travel ==")


def modes(v):
    return [(str(a[0]), int(a[1])) for a in (v.globals.get('stub:*mode*') or [])]


# CORNERSTP outside in: the outermost width is the question, and the
# bench (an inside-out feature) and the measuring choice are not
v = stubbed()
v.loads(typed([('direction', '2'), ('cancel', 'x')]))
v.loads('(setq lzt:*type* "CORNERSTP") (setq t:*f* (lzt:show))')
m = modes(v)
assert ('outerwidth', 0) in m, "Outside did not open the outermost width: %r" % m
for k in ('bench', 'benchoffset', 'benchstep', 'measure'):
    assert (k, 1) in m, "Outside should have greyed %s: %r" % (k, m)
# ...and inside out, the bench opens its two boxes and nothing else
v = stubbed()
v.loads(typed([('direction', '1'), ('bench', '1'), ('cancel', 'x')]))
v.loads('(setq lzt:*type* "CORNERSTP") (setq t:*f* (lzt:show))')
m = modes(v)
for k in ('benchoffset', 'benchstep'):
    assert (k, 0) in m, "a bench must open %s: %r" % (k, m)
assert ('outerwidth', 1) in m, "inside out has no outermost step: %r" % m
# NORMIESTEP: only a sized treatment takes a size, only a Cut is given
# as an offset or a face
for pick, sz, cg in (('1', 1, 1), ('2', 0, 1), ('3', 0, 0), ('4', 1, 1)):
    v = stubbed()
    v.loads(typed([('treat', pick), ('cancel', 'x')]))
    v.loads('(setq lzt:*type* "NORMIESTEP") (setq t:*f* (lzt:show))')
    m = modes(v)
    assert ('treat-sz', sz) in m, "treatment %s: treat-sz %r" % (pick, m)
    assert ('cutgiven', cg) in m, "treatment %s: cutgiven %r" % (pick, m)
print("   Outside opens the outermost width and closes the bench;")
print("   Radius and Cut open the size box, only Cut opens cutgiven")

# a greyed answer does not travel, and a run with no side profile
# carries no depths at all
v = stubbed()
v.loads(typed([('steps', '2'), ('treat', '1'), ('treat-sz', '6'),
               ('profile', '2'), ('accept', 'a'),
               ('depth1', '7.5'), ('tread1', '12'), ('tread2', '12'),
               ('width', '60'), ('accept', 'b')]))
v.loads('(setq lzt:*type* "NORMIESTEP") (setq t:*f* (lzt:show))')
form = dict(pair(p) for p in v.globals['t:*f*'])
assert 'treat-sz' not in form, \
    "a Square corner sent a size nothing reads: %r" % sorted(form)
assert not [k for k in form if k.startswith('depth')], \
    "a run with no side profile still carried depths: %r" % sorted(form)
assert str(form['profile']) == 'No' and str(form['treat']) == 'Square', form
m = modes(v)
assert ('depth1', 1) in m, "the depth boxes were not greyed on page two: %r" % m
assert ('tread1', 0) in m, "the tread boxes were greyed too: %r" % m
print("   Square drops treat-sz; profile No greys the depths and drops them")


print("== the gate: a routine that is not in the session ==")
v = stubbed()                                    # LAZSTEP alone
v.run('c:LAZSTEP', [])
said = ' '.join(str(p) for p in v.printed)
assert 'no step routine is loaded' in said, said
for name in ('CORNERSTP', 'HEMISTEP', 'NORMIESTEP'):
    assert name in said, "the message does not name %s: %r" % (name, said)
assert not OPENED, "a form was opened with nothing to receive it: %r" % OPENED
# with only one of the three loaded, that one is what opens and the
# other two tabs are greyed -- their Insert could only fail
v = stubbed('HEMISTEP')
v.loads(typed([('cancel', 'x')]))
v.loads('(setq lzt:*type* "CORNERSTP")')
v.run('c:LAZSTEP', [])
assert [n for n, _ in OPENED] == ['lazstep_p1_hemistep'], (
    "LAZSTEP opened on a routine that is not loaded: %r" % OPENED)
m = modes(v)
assert ('tab_CORNERSTP', 1) in m and ('tab_NORMIESTEP', 1) in m, \
    "the tabs for the missing routines were offered anyway: %r" % m
assert ('tab_HEMISTEP', 1) not in m, "the loaded routine's tab was greyed: %r" % m
print("   none loaded: refused by name; one loaded: it opens, the rest greyed")


# --------------------------------------------------------------------
# END TO END.  The form draws what the questions draw.
# --------------------------------------------------------------------
# The typed side of each pair is verbatim from tests/test_cornerstp_
# profile.py; the form side keeps only the selection and the picks,
# because everything else came off the drawing.
print("== end to end: the form draws what the questions draw ==")

PICK = (500.0, 400.0)
DEPTHS = ['7.5', '10.75', '10.75', '10.5']       # 3 steps -> 4 depths
TREAD = '24'


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


def walls(vm, pair_of_walls):
    vm.loads('(entmake (list (cons 0 "LINE")'
             ' (list 10 0.0 0.0 0.0) (list 11 200.0 0.0 0.0)))')
    if pair_of_walls:
        vm.loads('(entmake (list (cons 0 "LINE")'
                 ' (list 10 0.0 0.0 0.0) (list 11 0.0 200.0 0.0)))')
    return list(vm.entities)


DEPTH_BOXES = [('depth1', DEPTHS[0]), ('depth2', DEPTHS[1]),
               ('depth3', DEPTHS[2]), ('depthafter', DEPTHS[3])]
TREAD_BOXES = [('tread1', TREAD), ('tread2', TREAD), ('tread3', TREAD)]

CASES = [
    # tool, walls?, page-one boxes, page-two boxes, the picks the form
    # never sends, and the same run answered at the prompts
    ('CORNERSTP', True,
     [('steps', '3'), ('direction', '1'), ('dims', '2'), ('bench', '2'),
      ('profile', '1')],
     TREAD_BOXES + [('width1', 'NA'), ('width2', 'NA'), ('width3', 'NA')]
     + DEPTH_BOXES,
     [PICK],
     [None, "No", "No"] + [24.0, None] * 3 + [None, "Yes"]
     + [float(d) for d in DEPTHS] + [PICK]),
    ('HEMISTEP', False,
     [('steps', '3'), ('dims', '2'), ('wallwidth', '60'), ('crown', 'NA'),
      ('profile', '1')],
     TREAD_BOXES + [('width1', '60'), ('width2', '60'), ('width3', '60')]
     + DEPTH_BOXES,
     [(100.0, 50.0), PICK],
     [(100.0, 50.0), "No", 60.0] + [24.0, 60.0] * 3 + [None, None, "Yes"]
     + [float(d) for d in DEPTHS] + [PICK]),
    ('NORMIESTEP', False,
     [('steps', '3'), ('width', '60'), ('treat', '1'), ('dims', '2'),
      ('profile', '1')],
     TREAD_BOXES + DEPTH_BOXES,
     [(100.0, 50.0), PICK],
     [(100.0, 50.0), 60.0, "Square", "No", 24.0, 24.0, 24.0, None, "Yes"]
     + [float(d) for d in DEPTHS] + [PICK]),
]

for tool, pair_of_walls, p1, p2, picks, prompts in CASES:
    # ...through the form
    fv = stubbed(tool)
    fv.loads(typed(p1 + [('accept', 'a')] + p2 + [('accept', 'b')]))
    fv.loads('(setq lzt:*type* "%s")' % tool)
    ws = walls(fv, pair_of_walls)
    try:
        fv.run('c:LAZSTEP', [None, ws] + picks)
    except LispError as e:
        raise AssertionError("[%s form] %s" % (tool, e)) from None
    a = snapshot(fv)
    assert a, "%s: the form run drew nothing" % tool
    store = '*%s-form*' % PREFIX[tool]
    assert not fv.globals.get(store), \
        "%s: %s survived the run" % (tool, store)
    asked = [p for p, _ in fv.prompts]
    assert not [p for p in asked if 'step tread' in p], \
        "%s: a tread was asked for anyway: %r" % (tool, asked)
    assert not [p for p in asked
                if 'step depth' in p or 'Depth after' in p], \
        "%s: a depth was asked for anyway: %r" % (tool, asked)
    assert not [p for p in asked if 'Step 4' in p], \
        "%s: the count did not end the tread loop: %r" % (tool, asked)
    assert not [p for p in asked if 'Dimension the steps?' in p], \
        "%s: the form answered dims and it was asked anyway" % tool

    # ...and at the prompts
    pv = stubbed(tool)
    ws = walls(pv, pair_of_walls)
    try:
        pv.run('c:%s' % tool, [None, ws] + prompts)
    except LispError as e:
        raise AssertionError("[%s prompts] %s" % (tool, e)) from None
    b = snapshot(pv)
    assert a == b, (
        "%s: the form drew a different run -- %d entities from the form, %d "
        "from the prompts; %d only from the form"
        % (tool, len(a), len(b), len([x for x in a if x not in b])))
    print("   %-11s %3d entities, identical from the drawing and from the"
          % (tool, len(a)))
    print("   %-11s command line; %d prompts answered by the form"
          % ('', len(pv.prompts) - len(fv.prompts)))

# ...and with the dimensions on, so the dimension path is equal too
fv = stubbed('CORNERSTP')
fv.loads(typed([('steps', '3'), ('direction', '1'), ('dims', '1'),
                ('bench', '2'), ('profile', '1'), ('accept', 'a')]
               + TREAD_BOXES
               + [('width1', 'NA'), ('width2', 'NA'), ('width3', 'NA')]
               + DEPTH_BOXES + [('accept', 'b')]))
fv.loads('(setq lzt:*type* "CORNERSTP")')
ws = walls(fv, True)
fv.run('c:LAZSTEP', [None, ws, PICK])
pv = stubbed('CORNERSTP')
ws = walls(pv, True)
pv.run('c:CORNERSTP', [None, ws, None, "Yes", "No"] + [24.0, None] * 3
       + [None, "Yes"] + [float(d) for d in DEPTHS] + [PICK])
assert snapshot(fv) == snapshot(pv), \
    "CORNERSTP with dims on: the form drew a different run"
print("   CORNERSTP with the dims on: dimensions identical too")


print("== page one states itself, and holds Next back ==")
sv = fresh()


def p1(v):
    v.loads('(setq t:*s* (lzt:p1state))')
    return str(v.globals['t:*s*'])


sv.loads('(setq lzt:*vals* nil lzt:*sel* nil lzt:*type* "CORNERSTP")')
sv.loads('(setq t:*max* lzt:*max-steps*)')
MAX = int(str(sv.globals['t:*max*']))

# THE COUNT.  countwhy is the one function both the live line and the
# refusal read, so the warning and the refusal cannot disagree.
assert 'How many steps' in p1(sv), p1(sv)
sv.loads('(lzt:put "steps" "%d")' % (MAX + 1))
assert 'is the ceiling' in p1(sv), p1(sv)
sv.loads('(setq t:*ok* (lzt:count-ok)) (setq t:*m* lzt:*msg*)')
assert sv.globals['t:*ok*'] is None, "count-ok accepted a count over the ceiling"
assert str(sv.globals['t:*m*']) == p1(sv), (
    "the live line and the refusal say different things:\n  live: %r\n  msg:  %r"
    % (p1(sv), str(sv.globals['t:*m*'])))
sv.loads('(lzt:put "steps" "notanumber")')
sv.loads('(setq t:*ok* (lzt:count-ok)) (setq t:*m* lzt:*msg*)')
assert sv.globals['t:*ok*'] is None
assert str(sv.globals['t:*m*']) == p1(sv), "the two disagree on a bad count"
sv.loads('(lzt:put "steps" "3")')
assert p1(sv) == '3 steps - Next builds the drawing to fill in.', p1(sv)
sv.loads('(lzt:put "steps" "1")')
assert p1(sv).startswith('1 step -'), "a single step is not '1 steps': %r" % p1(sv)
sv.loads('(lzt:put "steps" "3") (setq t:*ok* (lzt:count-ok)) (setq t:*n* lzt:*steps*)')
assert sv.globals['t:*ok*'] is not None and int(str(sv.globals['t:*n*'])) == 3
print("   the count: one rule, read live and read again at the gate")

# THE TWO READERS.  A DIST box goes through lzt:answer and an INT box
# through lzt:int, and "3.5" is the case that separates them: a fine
# measurement, and not a step number at all.
sv.loads('(lzt:sput "direction" 1) (lzt:sput "bench" 1)')      # Inside, Yes
sv.loads('(setq t:*b* (lzt:p1boxes))')
P1KEYS = [str(d[0]) for d in sv.globals['t:*b*']]
assert 'benchstep' in P1KEYS and 'benchoffset' in P1KEYS, P1KEYS
sv.loads('(lzt:put "benchstep" "3.5")')
bad = p1(sv)
assert bad.startswith('Bench ends on step number:'), bad
assert 'is not a whole number' in bad and '3.5' in bad, bad
sv.loads('(setq t:*a* (lzt:answer "3.5")) (setq t:*i* (lzt:int "3.5"))')
assert sv.globals['t:*a*'] is not None, "3.5 is not a distance after all"
assert sv.globals['t:*i*'] is None, "3.5 passed the whole-number reader"
sv.loads('(lzt:put "benchstep" "2") (lzt:put "benchoffset" "wide")')
bad = p1(sv)
assert bad.startswith('Bench offset off the wall:'), bad
assert 'is not a measurement' in bad, bad
sv.loads('(lzt:put "benchoffset" "12")')
assert p1(sv).endswith('Next builds the drawing to fill in.'), p1(sv)
# a greyed question is not asked, so rubbish in it is not complained
# about: Outside drops the bench questions entirely
sv.loads('(lzt:sput "direction" 2) (lzt:put "benchoffset" "wide")')
sv.loads('(setq t:*sk* (lzt:skip))')
assert 'benchoffset' in [str(x) for x in sv.globals['t:*sk*']]
assert p1(sv).endswith('Next builds the drawing to fill in.'), \
    "rubbish in a greyed question is being complained about: %r" % p1(sv)
print("   a whole-number box and a measurement box, each read its own way")


print("== page two states itself, and holds Insert back ==")
tv = fresh()
tv.loads('(setq lzt:*vals* nil lzt:*sel* nil lzt:*type* "CORNERSTP")')
tv.loads('(setq lzt:*steps* 3 lzt:*chart* (lzt:chart "CORNERSTP" 3))')


def p2(v):
    v.loads('(setq t:*s* (lzt:p2state))')
    return str(v.globals['t:*s*'])


tv.loads('(setq t:*l* (lzt:livekeys))')
LIVE = [str(x) for x in tv.globals['t:*l*']]
assert LIVE, "no live box on a three-step drawing"
assert p2(tv).startswith('Nothing filled yet'), p2(tv)
assert 'CORNERSTP' in p2(tv), "the state line does not name the routine"
tv.loads('(lzt:put "%s" "18")' % LIVE[0])
assert p2(tv).startswith('1 of %d boxes filled' % len(LIVE)), p2(tv)
# a box is named by the letter the DRAWING shows, not by its key
tv.loads('(setq t:*t* (lzt:tagof "%s"))' % LIVE[1])
tv.loads('(setq t:*d* (lzt:c-dims lzt:*chart*))')
letters = {str(d[1]): str(d[0]) for d in tv.globals['t:*d*']}
assert str(tv.globals['t:*t*']) == letters[LIVE[1]], \
    "%r is named %r, but the drawing letters it %r" \
    % (LIVE[1], str(tv.globals['t:*t*']), letters[LIVE[1]])
tv.loads('(lzt:put "%s" "huh")' % LIVE[1])
assert p2(tv) == ('%s is not a measurement - type a number, or NA, or clear it.'
                  % letters[LIVE[1]]), p2(tv)
for k in LIVE:
    tv.loads('(lzt:put "%s" "18")' % k)
full = p2(tv)
assert full.startswith('All %d boxes filled' % len(LIVE)), full
assert 'the picks' in full, "what stays in the drawing is not mentioned: %r" % full
print("   %d dimension boxes, named by the letters the drawing shows"
      % len(LIVE))

# the partition: every live box is sent, still to ask, or unreadable
tv.loads('(setq lzt:*vals* nil)')
tv.loads('(lzt:put "%s" "18") (lzt:put "%s" "huh")' % (LIVE[0], LIVE[1]))
tv.loads('(setq t:*bad* (lzt:unreadable)) (setq t:*togo* (lzt:togo))'
         '(setq t:*form* (lzt:form))')
BAD = set(str(x) for x in (tv.globals['t:*bad*'] or []))
TOGO = set(str(x) for x in (tv.globals['t:*togo*'] or []))
SENT = {str(q.a) if isinstance(q, Dot) else str(q[0])
        for q in tv.globals['t:*form*']} & set(LIVE)
assert BAD == {LIVE[1]}, BAD
assert SENT | TOGO | BAD == set(LIVE), (
    "live boxes in none of sent/to-ask/unreadable: %r"
    % sorted(set(LIVE) - SENT - TOGO - BAD))
for a, b in ((SENT, TOGO), (SENT, BAD), (TOGO, BAD)):
    assert not (a & b), "two groups claim %r" % sorted(a & b)
assert LIVE[1] not in SENT, "an unreadable box reached the routine after all"
print("   %d live boxes: %d sent, %d still to ask, %d unreadable, no overlap"
      % (len(LIVE), len(SENT), len(TOGO), len(BAD)))


print("== both pages wire their state line ==")
rv = stubbed()
rv.loads('(setq lzt:*vals* nil lzt:*sel* nil lzt:*type* "CORNERSTP")')
rv.loads('(setq lzt:*steps* 3 lzt:*chart* (lzt:chart "CORNERSTP" 3))')


def accept_mode(v):
    modes = [(str(a[0]), int(a[1])) for a in (v.globals.get('stub:*mode*') or [])]
    hits = [m for k, m in modes if k == 'accept']
    assert hits, "restate never touched the button: %r" % modes
    return hits[0]


# page one: Next is held back until the count is usable
rv.loads('(setq stub:*mode* nil stub:*tiles* nil) (lzt:p1restate)')
assert accept_mode(rv) == 1, "Next was live with no count typed at all"
rv.loads('(setq t:*m* (stub:tile "msg"))')
assert 'How many steps' in str(rv.globals['t:*m*']), rv.globals['t:*m*']
rv.loads('(setq stub:*mode* nil) (lzt:put "steps" "3") (lzt:p1restate)')
assert accept_mode(rv) == 0, "a good count did not let Next through"
rv.loads('(setq stub:*mode* nil) (lzt:sput "direction" 1) (lzt:sput "bench" 1)'
         '(lzt:put "benchstep" "3.5") (lzt:p1restate)')
assert accept_mode(rv) == 1, "Next stayed live with a box that would be dropped"

# page two: Insert is held back the same way
rv.loads('(setq stub:*mode* nil stub:*tiles* nil) (lzt:p2restate)')
assert accept_mode(rv) == 0, "Insert was greyed on a drawing with nothing wrong"
rv.loads('(setq t:*s* (stub:tile "state"))')
assert rv.globals['t:*s*'] is not None, "the state tile was never written"
rv.loads('(setq stub:*mode* nil) (lzt:put "tread1" "nonsense") (lzt:p2restate)')
assert accept_mode(rv) == 1, "Insert stayed live with an unreadable box"
print("   Next and Insert both held back, both released when it is fixed")

# and the callbacks: every box on either page puts the line back
wv = stubbed('CORNERSTP')
wv.loads('(setq lzt:*type* "CORNERSTP") (setq t:*d* (lzt:dcl-lines))')
wv.loads('(setq stub:*rc* 0) (lzt:page1 7)')
acts = {str(a[0]): str(a[1]) for a in (wv.globals.get('stub:*act*') or [])}
assert 'lzt:p1restate' in acts['steps'], "the count box does not restate"
# EVERY typed question is wired, greyed or not: what is greyed changes
# while the page is open, so a box wired only when it happened to be
# live at open would go dead the moment a dropdown un-greyed it
wv.loads('(setq t:*a* (lzt:asks))')
typed = 0
for d in wv.globals['t:*a*']:
    k = str(d[0])
    if str(d[1]) == 'LIST':
        assert 'lzt:p1pick' in acts[k], "dropdown %r does not re-grey" % k
    else:
        typed += 1
        assert 'lzt:p1restate' in acts[k], "page-one box %r does not restate" % k
assert typed, "no typed question on page one at all"
wv.loads('(setq t:*m* (stub:tile "msg"))')
assert wv.globals['t:*m*'] is not None, \
    "page one opened without ever writing its state line"

wv.loads('(setq stub:*act* nil stub:*tiles* nil)')
wv.loads('(setq lzt:*steps* 3 lzt:*chart* (lzt:chart "CORNERSTP" 3))')
wv.loads('(setq stub:*rc* 0) (lzt:page2 7)')
acts2 = {str(a[0]): str(a[1]) for a in (wv.globals.get('stub:*act*') or [])}
wv.loads('(setq t:*k* (lzt:keys lzt:*chart*))')
for k in [str(x) for x in wv.globals['t:*k*']]:
    assert 'lzt:p2restate' in acts2[k], "page-two box %r does not restate" % k
wv.loads('(setq t:*s* (stub:tile "state"))')
assert wv.globals['t:*s*'] is not None, \
    "page two opened without ever writing its state line"
print("   %d page-one callbacks and %d page-two callbacks, both lines written"
      % (len(acts), len(acts2)))


print("ALL LAZSTEP TESTS PASSED")
