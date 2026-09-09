"""The palette's chart form, held to the surface it mirrors.

`ChartFormView.vb` is the palette's answer to `LAZFORM`: pick a sheet,
fill it in, draw from it.  Nothing here can run it -- there is no VB
compiler in this tree -- so what is checked is every seam where the
form has to agree with something that IS testable.

1. **The recall store is the DCL forms' own.**  Same three registry
   keys, same `key=typed;key=typed` format, same rule about a value
   carrying a separator.  Fill a sheet in on LAZFORM and Recall on the
   palette brings it back, and the other way round -- which is only true
   if these strings match, and they are strings in two files.
2. **Recall fills the empty boxes only**, and is never a default.  A
   pre-filled sheet would put the last pool's numbers on this pool, and
   the state line would call it finished.
3. **The state line asks the wire.**  It must call
   `calofin:unreadable-str` rather than deciding for itself, because the
   palette no longer reads a measurement at all; a line that named a box
   the wire would happily accept is worse than no line.
4. **The form sends the shape word, not the chart key** -- six of the
   sixteen sheets differ, and sending the key would draw the wrong pool.
   And it sends the gates the sheet implies.
5a. **The step form** offers exactly the counts a sheet exists for,
   uses `lzt:recall-slot`'s per-count slot, and mirrors the ONE rule
   that cannot be left to the wire: NA at a tread is what ends a run,
   so it counts as an empty box rather than travelling.
7. **The pool sheet's other questions**: the in-square keyword, the
   bottom type, the cross dims (not asked in square, because a cross
   dim IS what tells POOL how far out of square it is), the mode
   dropdowns, and the corner rows -- where a row is not always one
   corner, and which targets its answer is fanned out to depends on
   the toggle.
6. **The spa form** offers `lzs:*ctreat*`'s words without translating
   them -- SPA normalises the legend onto the canonical set itself --
   and withholds a corner size on a treatment that takes none.
5. **The boxes are the chart's**: one per dimension and one per
   column-only key, invented from nothing, placed at the midpoint of
   the line each measures.  Whether a chart key is one POOL reads is
   `test_lazform.py`'s audit and stays there -- it does it against
   `pool:fckey` and both spellings of POOL's ask items, which a second
   copy here would only do worse.

Run: python3 tests/test_chart_form.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import check_vb  # noqa: E402
import gen_ui_charts as gen  # noqa: E402
from lispvm import VM  # noqa: E402
from callib import LISP_DIR, ROOT, read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


FORM = ROOT / 'ui' / 'calofin_net' / 'ChartFormView.vb'
PALETTE = ROOT / 'ui' / 'calofin_net' / 'CalofinPalette.vb'
VB = read(FORM)

def code_of(src):
    """SRC with its comment LINES dropped and its strings intact.

    check_vb's lexer would be the obvious tool and is the wrong one
    here: it replaces every string literal with a placeholder, and half
    of what this file has to be held to IS a string literal -- a
    registry path, a separator, the name of a Lisp function.  Dropping
    comment lines is still worth doing, so that a phrase in a doc
    comment can never stand in for the code that should carry it.
    """
    return "\n".join(l for l in src.splitlines()
                     if not l.strip().startswith("'"))


CODE = code_of(VB)


print("== 1. the recall store is the DCL forms' own ==")

for tool, path, const in (('lzf', LISP_DIR / 'lazform' / 'LAZFORM.lsp',
                           'PoolKey'),
                          ('lzs', LISP_DIR / 'lazspa' / 'LAZSPA.lsp',
                           'SpaKey'),
                          ('lzt', LISP_DIR / 'lazstep' / 'LAZSTEP.lsp',
                           'StepKey')):
    vm = VM()
    vm.load(path)
    want = str(vm.globals['%s:*recallkey*' % tool])
    check("%s is %s:*recallkey*" % (const, tool),
          ('%s As String =' % const) in CODE and want in CODE, want)

# the format, from the library rather than typed here
LIB = read(ROOT / 'shared' / 'parts' / 'CALOFIN-LIB.lsp')
check("the panel packs with '=' between and ';' along",
      'k "=" v' in LIB.replace('(strcat out (if (= out "") "" ";") ', ''),
      "cal:kvpack has been reshaped")
check("the palette packs the same way",
      'b.Key & "=" & v' in CODE and 'String.Join(";", parts)' in CODE)
check("and splits the same way",
      's.Split(";"c)' in CODE and 'part.IndexOf("="c)' in CODE)

# cal:kvpack drops a value carrying a separator rather than writing a
# record it cannot read back
check("the panel drops a value carrying a separator",
      'cal:kvhas v ";"' in LIB and 'cal:kvhas v "="' in LIB)
check("so does the palette",
      'v.Contains(";") OrElse v.Contains("=")' in CODE)


print("== 2. recall fills the empty boxes, and is never a default ==")

check("only an empty box is filled",
      re.search(r"If b\.IsFilled Then Continue For", CODE) is not None)
check("recall is a button, not something the form does on open",
      'AddHandler _recall.Click' in CODE
      and 'Recall()' not in CODE.split('Private Sub ShowChart')[1]
          .split('End Sub')[0])
check("the button is disabled when this chart has nothing stored",
      '_recall.IsEnabled = HasStored()' in CODE)
check("the sheet is saved when Draw is pressed, not before",
      'RecallStore.Save(_recallKey, _current.Key, _boxes)' in CODE
      and CODE.index('RecallStore.Save')
          > CODE.index('Private Sub Run()'))


print("== 3. the state line asks the wire ==")

check("it calls calofin:unreadable-str",
      '"calofin:unreadable-str"' in CODE)
check("it packs the sheet the same way the store does",
      'RecallStore.Pack(askable)' in CODE)
# ...but the store's rule about a separator is the store's, not this
# question's.  Pack DROPS an entry holding a ";" or an "=", which is
# right when writing one back and exactly wrong when asking about it:
# a box left out of the question is the one box the line could never
# name, and the line exists to name exactly that box.
check("a box the question cannot carry is named without asking",
      'If CarriesSeparator(b) Then' in CODE
      and 'out.Add(b.Key)' in CODE
      and 'b.Text.Contains(";") OrElse b.Text.Contains("=")' in CODE)
check("a box that will not read holds Draw back",
      '_draw.IsEnabled = state.Ready' in CODE
      and 'Return New State(' in CODE and ', False)' in CODE)
check("and is named by the LETTER the sheet prints, not the key",
      'b.Letter.Length > 0, b.Letter, b.Key' in CODE)
check("when the glue is missing nothing the WIRE would drop is named",
      'wired.Clear()' in CODE and 'out.Clear()' not in CODE)

# the wire's own answer, to be sure the name exists on the other side
glue = VM()
glue.load(ROOT / 'ui' / 'calofin_ui' / 'calofin.lsp')
glue.loads('(setq t:*x* (calofin:unreadable-str "b=84;h=rubbish"))')
check("and the name it calls is a defun in calofin.lsp",
      str(glue.globals['t:*x*']) == 'h', repr(glue.globals['t:*x*']))


print("== 4. what the form sends ==")

check("the SHAPE WORD travels, not the chart's key",
      'LispBridge.StrPair("shape", _current.Shape)' in CODE)
check("every gate the sheet implies travels as a literal",
      'For Each g In _current.Gates' in CODE
      and 'LispBridge.StrPair(g.Key, g.Value)' in CODE)
check("every filled box travels as a measure, unread",
      'LispBridge.MeasurePair(b.Key, b.Text)' in CODE)
check("the form does not read a measurement itself",
      'TryParse' not in CODE, "a parser has come back")
check("it goes through the wire, not straight at the routine",
      'LispBridge.BuildFormCall' in CODE
      and 'LispBridge.BuildCall(' not in CODE)

# the tab the palette actually adds
PAL = " ".join(code_of(read(PALETTE)).split())
check("the palette mounts it on ChartCatalog.Pool",
      'New ChartFormView( ChartCatalog.Pool, ChartCatalog.PoolEntry, '
      'RecallStore.PoolKey,' in PAL,
      PAL[PAL.find('ChartFormView') - 40:][:200])


print("== 5. the sheet's boxes are the chart's, and nothing else ==")

# What this file can check that test_lazform.py cannot: the FORM's box
# set.  Whether a chart key is one POOL reads is already audited there,
# against pool:fckey and both spellings of POOL's ask items, and far
# more carefully than a second copy here would manage -- so this checks
# the half that is new: that the form builds a box for every dimension
# and every column-only key of the chart it is showing, and invents
# none.
check("a box per dimension, then a box per column-only key",
      'For Each d In _current.Dims' in CODE
      and 'New ChartBox(d)' in CODE
      and 'For Each e In _current.Extra' in CODE
      and 'New ChartBox(e)' in CODE)
check("a dimension box knows it sits on the chart, a list key does not",
      'Me.OnChart = True' in CODE and 'Me.OnChart = False' in CODE)
check("the sheet draws only the boxes that are on it",
      'If b.OnChart Then _boxes.Add(b)' in CODE)
check("every box gets a row in the column as well",
      '_rows.Children.Add(MakeRow(b))' in CODE)

# and the box lands on the line, not at a fraction somebody nudged
check("a box is placed at its dimension's MIDPOINT",
      'Me.X = d.MidX' in CODE and 'Me.Y = d.MidY' in CODE)
check("nothing in the form carries a hand-tuned position",
      'fieldmap' not in CODE and '0.8' not in CODE,
      "a fraction has crept back in")

# the counts the catalog actually gives, so an empty table would fail
charts = gen.read_charts(LISP_DIR / 'lazform' / 'LAZFORM.lsp', 'lzf',
                         'lzf:*charts*')
boxes = sum(len(c['dims']) + len(c['extra']) for c in charts)
check("%d sheets to pick from, %d boxes between them"
      % (len(charts), boxes), len(charts) == 13 and boxes > 100,
      "%d sheets, %d boxes" % (len(charts), boxes))
gated = [c['key'] for c in charts if c['gates']]
check("the sheets that imply an answer still do", gated == [
    'Grecian', 'GRSquare', 'OCtagon'], repr(gated))


print("== 6. the step form, and the one rule it mirrors ==")

STEP = code_of(read(ROOT / 'ui' / 'calofin_net' / 'StepFormView.vb'))

# LAZSTEP has no chart table: the sheet IS the count.  The palette must
# offer exactly the counts a sheet was generated for, because past
# lzt:*max-steps* LAZSTEP refuses to draw at all.
vmt = VM()
vmt.load(LISP_DIR / 'lazstep' / 'LAZSTEP.lsp')
top = int(vmt.globals['lzt:*max-steps*'])
check("the count list runs to lzt:*max-steps* and stops",
      'For n = 1 To ChartCatalog.MaxSteps' in STEP, str(top))
check("and MaxSteps really is that number",
      ('Public Const MaxSteps As Integer = %d' % top) in read(gen.OUT))

# THE one mirrored rule, and the reason it is worth mirroring
check("lzt:treadkey recognises a tread by its stem",
      '(defun lzt:treadkey (k) (= (substr k 1 5) "tread"))'
      in read(LISP_DIR / 'lazstep' / 'LAZSTEP.lsp'))
check("so does the palette", 'key.StartsWith("tread"' in STEP)
check("NA on a tread is withheld, not sent",
      'If IsTread(b.Key) AndAlso' in STEP
      and 'b.Text.Trim().ToUpperInvariant() = "NA" Then Continue For'
          in STEP)
# the Lisp's own statement of why, so the two cannot part on the reason
check("because NA is what ends a run - lzt:form says so",
      'NA at a tread is what ENDS the run'
      in read(LISP_DIR / 'lazstep' / 'LAZSTEP.lsp'))

check("the step count itself always travels, as a literal",
      'LispBridge.Pair("steps", Steps.ToString())' in STEP)
check("the entry point comes from lzt:*types*, not from a name typed here",
      'Routine.EntryPoint' in STEP)

runners = [str(t[2]) for t in vmt.globals['lzt:*types*']]
cat = read(gen.OUT)
for r in runners:
    check("%s is in the catalog" % r, ('"%s"' % r) in cat)

check("the recall slot is lzt:recall-slot's TYPE-count",
      'Routine.Command & "-" & Steps.ToString()' in STEP)
check("and it uses the step store, not the pool one",
      'RecallStore.StepKey' in STEP and 'RecallStore.PoolKey' not in STEP)

# A binding fires TextChanged as it first fills an editor, and both the
# sheet and the column rebuild their editors -- the sheet on every
# resize.  Unguarded, dragging the palette's edge asks Lisp what the
# sheet cannot read once per box per frame.
for _name, _src in (('ChartFormView', CODE), ('StepFormView', STEP)):
    check("%s does not restate while it is building rows" % _name,
          '_building = True' in _src and 'If _building Then Return' in _src)
check("the sheet does not raise a change while it is repainting",
      '_painting = True' in CODE and 'If _painting Then Return' in CODE)

# The step sheet has no corner rows, so every box on it is live: what
# lzt:skip withholds is decided by page one's dropdowns -- direction,
# treatment, profile -- and the palette does not carry those at all.
check("the step form shares the state line rather than copying it",
      'FormWire.Line(_boxes, Nothing)' in STEP
      and 'FormWire.Line(LiveBoxes(), Nothing)' in CODE)
# the wording lives in FormWire and nowhere else.  FormWire shares
# ChartFormView.vb's file, so counting per FILE would pass on the wrong
# reason; count across the whole assembly instead.
saidin = [str(f) for f in check_vb.vb_files()
          if 'cannot be read as a measurement' in read(f)]
check("the state line's words are written once, in the kit",
      len(saidin) == 1 and saidin[0].endswith('ChartFormView.vb'),
      repr(saidin))

# every generated step sheet is reachable: 3 routines x every count
_top, _routines, steps = gen.read_steps()
check("%d sheets, and the form can reach each of them"
      % len(steps), len(steps) == len(_routines) * _top,
      "%d sheets" % len(steps))
check("the palette mounts the step form",
      'New StepFormView()' in PAL)


print("== 7. the spa form, and what a spa sheet has that a pool one has not ==")

SPA = code_of(read(ROOT / 'ui' / 'calofin_net' / 'SpaChartView.vb'))
vms = VM()
vms.load(LISP_DIR / 'lazspa' / 'LAZSPA.lsp')

# the corner dropdown speaks the SHEET LEGEND and sends it as written
want = [str(x) for x in vms.globals['lzs:*ctreat*']]
cat = read(gen.OUT)
check("the treatments are lzs:*ctreat*, word for word",
      ("SpaTreatments As String() = {%s}"
       % ", ".join('"%s"' % w for w in want)) in cat, repr(want))
check("the form offers them without translating",
      'For Each t In ChartCatalog.SpaTreatments' in SPA
      and 'Square' not in SPA and 'NotGiven' not in SPA,
      "the palette has started renaming what SPA normalises itself")

# a size travels only when the treatment takes one -- lzs:cornerpairs
sized = []
for i, w in enumerate(want):
    vms.loads('(setq t:*s* (lzs:sized %d))' % i)
    if vms.globals['t:*s*']:
        sized.append(w)
check("lzs:sized names %s" % (" and ".join(sized) or "nothing"),
      ("SpaSizedTreatments As String() = {%s}"
       % ", ".join('"%s"' % w for w in sized)) in cat, repr(sized))
check("and a size on any other treatment is withheld",
      'If Sized(ty) Then sizedStems.Add' in SPA
      and 'Not sizedStems.Contains(b.Key) Then Continue For' in SPA)

# a dropdown left on "(ask)" sends nothing
check("the first option is always (ask)",
      all(str(d[2][0]) == '(ask)' for d in vms.globals['lzs:*lists*']))
check("and choosing it sends nothing at all",
      'If combo.SelectedIndex <= 0 Then Return ""' in SPA)

# every table the form reads is one the generator writes
for table in ('SpaLists', 'SpaTreatments', 'SpaSizedTreatments',
              'SpaCoverLap', 'SpaSheetFor'):
    check("SpaChartView reads ChartCatalog.%s" % table,
          ('ChartCatalog.' + table) in SPA)

# and the spa form is the one the palette mounts
check("the palette mounts the drawn spa sheet, not a photograph",
      'New SpaChartView()' in PAL and 'SpaFormView' not in PAL)
check("the shape art it used to need is gone",
      not (ROOT / 'ui' / 'calofin_net' / 'assets' / 'shapes').exists(),
      "assets/shapes is still there and nothing reads it")
check("the vbproj no longer copies it",
      'assets\\shapes' not in read(ROOT / 'ui' / 'calofin_net' /
                                   'Calofin.vbproj'))
# the bottom tab IS still a photograph, and says so
check("the bottom art stays, because that tab still needs it",
      (ROOT / 'ui' / 'calofin_net' / 'assets' / 'bottoms').exists()
      and 'assets\\bottoms' in read(ROOT / 'ui' / 'calofin_net' /
                                    'Calofin.vbproj'))

check("the spa form shares the state line too",
      'FormWire.Line(LiveBoxes(), NaBad())' in SPA)
check("and does not read a measurement itself", 'TryParse' not in SPA)

# lzs:keyanswer, and the reason it is not a shrug: SPA marks its
# measurement items REQ / SUG / NAX, and a REQ item fed a nil is not
# asked again -- spa:askseqb stores the nil and the flow does
# arithmetic on it.  The palette sent (key . nil) for any NA'd box.
_lzs = read(LISP_DIR / 'lazspa' / 'LAZSPA.lsp')
check("lzs:keyanswer demotes an NA on a key SPA has no NA for",
      '(defun lzs:keyanswer (c key / a)' in _lzs
      and '(not (member key (lzs:naok c)))' in _lzs)
check("...because a REQ item fed a nil is not asked again",
      'is not asked again' in _lzs
      and 'which in AutoLISP is an error, not a fallback' in _lzs)
_naok = {}
for _c in vms.globals['lzs:*charts*']:
    _k = str(_c[0])
    vms.loads('(setq t:*c* (lzs:chart "%s"))' % _k)
    vms.loads('(setq t:*na* (lzs:naok t:*c*))')
    _naok[_k] = [str(x) for x in (vms.globals['t:*na*'] or [])]
check("the catalog carries lzs:*naok* per sheet",
      all(('New String() {%s})'
           % ", ".join('"%s"' % k for k in v)) in cat
          for v in _naok.values() if v), repr(_naok))
check("a rectangle takes NA on l and l2 and nothing else",
      _naok['Rectangle'] == ['l', 'l2'], repr(_naok['Rectangle']))
check("the form withholds an NA anywhere else, as the wire cannot",
      'If IsNa(b) AndAlso Not _spa.TakesNa(b.Key) Then Continue For' in SPA)
check("and the state line names it rather than dropping it silently",
      'Private Function NaBad() As List(Of ChartBox)' in SPA
      and 'cannot be NA - the routine needs a number ' in CODE)
check("Draw is held back for it, as lzs:restate holds Insert back",
      '(mode_tile "accept" (if (or (lzs:unreadable) (lzs:nabad)) 1 0))'
      in _lzs)
# and no such table exists on the other two, so neither form invents one
check("LAZFORM and LAZSTEP have no NA table, so neither form has one",
      'naok' not in read(LISP_DIR / 'lazform' / 'LAZFORM.lsp')
      and 'naok' not in read(LISP_DIR / 'lazstep' / 'LAZSTEP.lsp')
      and 'TakesNa' not in CODE and 'TakesNa' not in STEP)


print("== 8. the pool sheet's questions that are not measurements ==")

vmf = VM()
vmf.load(LISP_DIR / 'lazform' / 'LAZFORM.lsp')
_cat = read(gen.OUT)

# the treatments, and which carry a size
_treat = [str(x) for x in vmf.globals['lzf:*ctreat*']]
check("the pool treatments are lzf:*ctreat*, and ARE the canonical set",
      ("PoolTreatments As String() = {%s}"
       % ", ".join('"%s"' % w for w in _treat)) in _cat
      and 'Square' in _treat and 'NotGiven' in _treat, repr(_treat))
_sized = []
for _i, _w in enumerate(_treat):
    vmf.loads('(setq t:*s* (lzf:csized %d))' % _i)
    if vmf.globals['t:*s*']:
        _sized.append(_w)
check("lzf:csized names %s" % " and ".join(_sized),
      ("PoolSizedTreatments As String() = {%s}"
       % ", ".join('"%s"' % w for w in _sized)) in _cat, repr(_sized))

# the six bottoms POOL draws, and the two in-square words
_bt = [str(x) for x in vmf.globals['lzf:*btypes*']]
check("the bottoms are lzf:*btypes*, all %d" % len(_bt),
      ("PoolBottomTypes As String() = {%s}"
       % ", ".join('"%s"' % w for w in _bt)) in _cat, repr(_bt))
check("the toggle sends a KEYWORD, not a yes/no",
      'InSquare As String = "Insquare"' in _cat
      and 'OutOfSquare As String = "Outofsquare"' in _cat)
check("and the form sends one of them on every POOL sheet",
      'LispBridge.StrPair( "insq", If(insquare, ChartCatalog.InSquare, '
      'ChartCatalog.OutOfSquare))'
      in " ".join(CODE.split()))

# THE RULE: a corner row is not always one corner, and which targets it
# answers depends on the toggle
_rows = {}
for _c in vmf.globals['lzf:*corners*']:
    _rows[str(_c[0])] = [(str(r[0]), [str(x) for x in (r[2] or [])],
                          [str(x) for x in (r[3] or [])]) for r in _c[1:]]
check("a rectangle's corner A answers the COLLECTIVE key in square",
      _rows['Rectangle'][0][1] == ['corners'], repr(_rows['Rectangle'][0]))
check("and its B, C and D answer nothing in square",
      all(r[1] == [] for r in _rows['Rectangle'][1:]),
      repr([r[1] for r in _rows['Rectangle'][1:]]))
check("a Grecian's body row covers all four corners at once",
      _rows['Grecian'][0][2] == ['cornera', 'cornerb', 'cornerc', 'cornerd'],
      repr(_rows['Grecian'][0]))
check("the catalog carries BOTH target lists per row",
      'InSquareTargets As String()' in _cat
      and 'OutOfSquareTargets As String()' in _cat)
check("the form fans the answer out to every target",
      'For Each target In targets' in CODE
      and 'LispBridge.StrPair(target & "-ty", ty)' in CODE)
check("and a row with no targets in this state sends nothing",
      'If targets Is Nothing Then Continue For' in CODE)
check("a corner SIZE rides under the target's key, not the row's",
      'LispBridge.MeasurePair(target & "-sz", typed)' in CODE)
check("so a size is never also sent under the row's own key",
      'If b.Key.EndsWith("-sz", StringComparison.Ordinal) Then Continue For'
      in CODE)

# the cross dims, and why they are not asked in square
check("the cross dims are lzf:*cross*, in the catalog",
      'New ListKey("x0", "Cross dim 1")' in _cat)
check("they are not asked in square - a cross dim IS the out-of-square",
      'Not _insquare.IsChecked.GetValueOrDefault()' in CODE)
_picks_src = read(LISP_DIR / 'lazform' / 'LAZFORM.lsp')
check("which is what lzf:*picks* says by tying the mode to that section",
      'section "cross" puts the dropdown at the head of the cross-dim box'
      in _picks_src and 'in square there are no cross dims' in _picks_src)
check("the form places a pick by lzf:*picks*' own section word",
      'If p.Section <> section Then Continue For' in CODE
      and 'AddPicks("run")' in CODE and 'AddPicks("cross")' in CODE)


print("== 9. which routine a sheet feeds, and what that page carries ==")

# THE FAILURE THIS CLOSES.  ChartCatalog.Pool is LAZFORM's whole tab
# strip -- thirteen sheets, and FIVE of them are OASIS pages.  The
# palette used to mount all thirteen on one hard-coded entry point, so
# picking "Oasis - Cloud" handed OASIS's own shape word to POOL.
# lzf:run reads that off the CHART ("the tab IS the choice"), and now
# so does the form.
_oasis = []
for _c in vmf.globals['lzf:*charts*']:
    _k = str(_c[0])
    vmf.loads('(setq t:*c* (lzf:chart "%s"))' % _k)
    vmf.loads('(setq t:*o* (if (lzf:oasis-p t:*c*) 1 0))')
    if int(vmf.globals['t:*o*']):
        _oasis.append(_k)
check("lzf:*oaslive* names %d of the %d sheets"
      % (len(_oasis), len(vmf.globals['lzf:*charts*'])),
      len(_oasis) == 5, repr(_oasis))
check("the catalog carries which routine each sheet feeds",
      'PoolEntry As String = "pool:run-with-answers"' in _cat
      and 'OasisEntry As String = "oasis:run-with-answers"' in _cat
      and 'Public ReadOnly Property EntryPoint As String' in _cat)
check("every oasis sheet is flagged and no pool sheet is",
      all(('New PoolSheet("%s"' % k) in _cat for k in _oasis)
      and _cat.count('\n            True, False, False)') == len(_oasis),
      "the Oasis/Bottom/CornerGate row is not what lzf says")
check("the form asks the sheet rather than assuming",
      'LispBridge.BuildFormCall(EntryPoint(), literals,' in CODE
      and 'Return _pool.EntryPoint' in CODE)

# and an oasis form is SHORTER by POOL's two page-wide questions:
# lzf:oasform takes neither, and lzf:pagekeys puts no bottom tile on
# an oasis page
_src = read(LISP_DIR / 'lazform' / 'LAZFORM.lsp')
check("lzf:oasform takes no in-square keyword and no bottom type",
      '(defun lzf:oasform (shape /' in _src
      and '(defun lzf:poolform (shape insq btype /' in _src)
check("so the form withholds both on an oasis sheet",
      'If Not oasis Then' in CODE
      and 'Dim insquare = Not oasis AndAlso' in CODE)
check("and the page does not offer them either",
      '_gates.Visibility = If(Oasis(), Visibility.Collapsed,' in CODE)

# lzf:*nobtype*: the L shapes carry the toggle but no bottom popup
_nobt = [str(x) for x in vmf.globals['lzf:*nobtype*']]
check("lzf:*nobtype* takes the bottom popup off %s" % ", ".join(_nobt),
      _nobt == ['L', 'LAzyl'], repr(_nobt))
check("the catalog says so per sheet, from lzf:btlive",
      'New PoolSheet("L",' in _cat
      and '\n            False, False, True)' in _cat)
check("and a page with no popup sends no bottom type",
      'If BottomLive() Then' in CODE)

# lzf:*crecharts*: a corner row answered also answers POOL's gate
_cre = [str(x) for x in vmf.globals['lzf:*crecharts*']]
check("lzf:*crecharts* puts a gate in front of %d sheets' corners"
      % len(_cre), len(_cre) == 6, repr(_cre))
check("the gate is lzf:poolform's own key and answer",
      'CornerGateKey As String = "crec"' in _cat
      and 'CornerGateAnswer As String = "Yes"' in _cat
      and "(cons 'crec \"Yes\")" in _src)
check("the form answers it when a row was picked, and only then",
      'If answered AndAlso PoolExtras() AndAlso _pool.CornerGate Then'
      in CODE
      and 'ChartCatalog.CornerGateKey' in CODE)
check("without it the treatments would be read by nothing",
      'treatments would be read by nothing if it were left on No' in _src)


# A corner SIZE box is live only when its own dropdown takes a size --
# lzf:livekeys and lzs:livekeys both say so, and both say why: "a greyed
# box is withheld from the routine whatever is in it, so neither
# complaining about its contents nor counting it as still to ask would
# be true".  The state line did both, and the complaint half held Draw
# back over a box that was never going to travel.
check("lzf:livekeys makes a corner size live off its own dropdown",
      'what makes one live' in _src
      and 'is its own dropdown taking a size' in _src)
for _name, _src2 in (('the pool chart form', CODE), ('the spa form', SPA)):
    check("%s asks about the LIVE boxes only" % _name,
          'FormWire.Line(LiveBoxes(),' in _src2
          and 'Private Function LiveBoxes() As List(Of ChartBox)' in _src2)
    check("%s recalls into the live boxes only" % _name,
          'For Each b In LiveBoxes()' in _src2)
check("and a size is live exactly when lzf:csized says so",
      'Sized(CornerPick(stem)) Then out.Add(b)' in CODE)
check("...and lzs:sized on the spa sheet",
      'Sized(Picked(stem & "-ty")) Then out.Add(b)' in SPA)


print("== 10. what is typed survives a rebuild, as it does on the panel ==")

# Every DCL form keeps its answers in a keyed store that outlives a
# page switch, and each says so in its own words.  The palette rebuilds
# every row when the sheet, the shape, the count or the in-square
# toggle changes -- so without a keyed carry-over of its own it threw
# the sheet away, which is the one thing the surface it mirrors
# promises not to do.
for _tool, _path, _say in (
        ('lzf', LISP_DIR / 'lazform' / 'LAZFORM.lsp',
         'survives the switch and is still there if you tab back'),
        ('lzs', LISP_DIR / 'lazspa' / 'LAZSPA.lsp',
         'survives the switch and is still there if you tab back'),
        ('lzt', LISP_DIR / 'lazstep' / 'LAZSTEP.lsp',
         'steps that still exist still carry what was typed')):
    check("%s keeps what was typed across a page switch" % _tool,
          _say in read(_path), _say)

STEPV = code_of(read(ROOT / 'ui' / 'calofin_net' / 'StepFormView.vb'))
for _name, _src2 in (('the pool chart form', CODE),
                     ('the spa form', SPA),
                     ('the step form', STEPV)):
    check("%s remembers before it rebuilds" % _name,
          'Remember()' in _src2 and 'Private Sub Remember()' in _src2)
    check("%s puts it back by KEY" % _name,
          '_typed.TryGetValue(b.Key, v)' in _src2)
    check("%s forgets a box that was emptied" % _name,
          '_typed.Remove(b.Key)' in _src2)
    check("%s clears the memory when Clear is pressed" % _name,
          '_typed.Clear()' in _src2)

# a dropdown too, and by the WORD: two sheets need not offer the same
# choices in the same order, so an index would put one on the wrong one
for _name, _src2 in (('the pool chart form', CODE), ('the spa form', SPA)):
    check("%s puts a dropdown back on its word" % _name,
          'Private Sub Reselect(combo As ComboBox, slot As String)' in _src2
          and 'Dim i = combo.Items.IndexOf(was)' in _src2)

# the toggle is the one that used to lose a whole sheet at a stroke
check("the in-square toggle still rebuilds the rows",
      'AddHandler _insquare.Checked, Sub() ShowChart(_picker.SelectedIndex)'
      in CODE)
_show = CODE.split('Private Sub ShowChart')[1].split('End Sub')[0]
check("and no longer takes the sheet with it",
      _show.index('Remember()') < _show.index('_boxes.Clear()')
      and 'Restore()' in _show)


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL CHART FORM CHECKS PASSED")
