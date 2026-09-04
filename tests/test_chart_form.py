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
      'RecallStore.Pack(filled)' in CODE)
check("a box that will not read holds Draw back",
      '_draw.IsEnabled = False' in CODE)
check("and is named by the LETTER the sheet prints, not the key",
      'b.Letter.Length > 0, b.Letter, b.Key' in CODE)
check("when the glue is missing nothing is reported",
      'out.Clear()' in CODE)

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
      'New ChartFormView( ChartCatalog.Pool, "pool:run-with-answers", '
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


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL CHART FORM CHECKS PASSED")
