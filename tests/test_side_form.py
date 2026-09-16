"""The palette's SIDE VIEW tab, against LAZSIDE and POOLSIDE.

``ui/calofin_net/SideFormView.vb`` is the palette's fourth form: the
longitudinal section, one page per bottom type, handed to POOLSIDE.
``tests/test_ui_charts.py`` holds the GEOMETRY it draws to ``lzv:chart``;
this holds the WIRE -- what the form sends, and what it withholds -- to
the two routines that have to receive it.

That split matters.  A sheet drawn perfectly and handed over with the
wrong keys is a form that looks right and draws nothing, and the
geometry test cannot see it: it never reads the VB that does the
sending.

What is checked here:

1. **The bottom type travels as a literal, and it is the page.**
   ``lzv:form`` puts ``style`` first and calls it "the page itself".
   POOLSIDE reads it with ``psd:fkw 'style psd:*btypes*``, which is a
   KEYWORD list -- so it has to arrive as a word, not as a measurement.
   A style run through the measure reader would come back 'SKIP and the
   sheet would draw a Normal whatever the tab said.
2. **A depth answered NA is withheld**, and the same table decides it in
   both places the form uses it -- the state line and the wire.  This is
   ``lzv:depthkey``, and the reason is ``psd:items``: C, D and C2 are
   ``REQ``, and a REQ item fed a nil is not asked again.
3. **A run answered NA travels**, because NA is a real answer there --
   POOLSIDE reads it back off B.  The two NA rules are opposite on one
   sheet, which is exactly why neither may be a blanket rule about the
   word.
4. **The dropdown's first word sends nothing.**  ``(ask)`` is the form's
   empty box; POOLSIDE's ``mirror`` prompt has a keyboard default of its
   own and must be left to apply it.
5. **The recall slot is the bottom type** (``lzv:recall-slot``) under
   LAZSIDE's own registry key, so a sheet filled in on the DCL panel
   comes back on the palette and the other way round -- and a Sport's
   E2/F2/F1/E1 never land on a Normal.
6. The form reads its tables rather than keeping its own: no bottom
   type, depth key or entry point is spelled in the VB.

Run: python3 tests/test_side_form.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import gen_ui_charts as gen  # noqa: E402
from callib import read  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..'))

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


VIEW = read(os.path.join(REPO, 'ui', 'calofin_net', 'SideFormView.vb'))
PSD = read(os.path.join(REPO, 'lisp', 'poolside', 'POOLSIDE.lsp'))
LZV = read(os.path.join(REPO, 'lisp', 'lazside', 'LAZSIDE.lsp'))

entry, sidetypes, depths, asks, sides = gen.read_sides()


print("== 1. the bottom type is a literal, and it is the page ==")

# StrPair, never MeasurePair.  psd:fkw reads this against an initget
# keyword list; a word put through the measurement reader comes back
# 'SKIP and the style stops travelling altogether.
check("style is sent with StrPair, the literal half of the wire",
      'LispBridge.StrPair("style", _current.Style)' in VIEW)
check("it is not sent as a measure",
      'MeasurePair("style"' not in VIEW)
check("POOLSIDE reads it as a keyword against its own list",
      "(psd:fkw 'style psd:*btypes* \"Normal\")" in PSD)

# and it is the sheet's own word, not the picker's row: _current is the
# chart, so the answer cannot disagree with the drawing on screen.
check("the word sent is the chart's, not the picker's label",
      '_current.Style' in VIEW and 'StrPair("style", SelectedType' not in VIEW)

check("lzv:form sends the same key first",
      "(setq out (list (cons 'style lzv:*type*)))" in LZV)


print("== 2. a depth answered NA is withheld, by the table ==")

check("the wire withholds it",
      'If IsNa(b) AndAlso ChartCatalog.IsSideDepth(b.Key) Then Continue For'
      in VIEW)
check("the state line names the same boxes",
      'If IsNa(b) AndAlso ChartCatalog.IsSideDepth(b.Key) Then' in VIEW
      and 'FormWire.Line(_boxes, NaBad())' in VIEW)

# One table, asked twice -- not two opinions that happen to agree.  A
# form whose Draw drops a box its own line called fine is the failure
# the line exists to prevent.
check("both ask ChartCatalog.IsSideDepth and nothing else",
      VIEW.count('ChartCatalog.IsSideDepth(b.Key)') == 2
      and not re.search(r'"c2"|"c"\s*,\s*"d"', VIEW),
      "a depth key is spelled in the VB")

check("lzv:form demotes it the same way",
      "(if (and (null a) (lzv:depthkey k)) (setq a 'SKIP))" in LZV)
check("POOLSIDE marks every one of them REQ",
      all(("(list '%s 'REQ" % k) in PSD for k in depths), repr(depths))


print("== 3. a run answered NA travels ==")

# The opposite rule on the same sheet, which is why neither may be a
# blanket rule about the word NA.  EVERY place the VB looks at NA asks
# the depth table in the same breath -- the state line's and the wire's,
# and there is no third -- so a run's NA has nothing in the form that
# could stop it.
nas = re.findall(r'If IsNa\(b\)[^\n]*', VIEW)
check("every NA test in the form is the depth one",
      len(nas) == 2 and all('IsSideDepth' in n for n in nas), repr(nas))
check("POOLSIDE reads an NA run back off B",
      'psd:chainfix' in PSD)


print("== 4. the dropdown's first word sends nothing ==")

check("(ask) is index 0 and index 0 sends \"\"",
      'If combo.SelectedIndex <= 0 Then Return ""' in VIEW)
check("only a non-empty pick is added",
      'If v.Length > 0 Then literals.Add(LispBridge.StrPair(q.Key, v))'
      in VIEW)
check("the question comes from the table, not from the VB",
      'For Each q In ChartCatalog.SideAsks' in VIEW
      and '"mirror"' not in VIEW, "mirror is spelled in the VB")
check("lzv:*asks* still puts (ask) first",
      [ch[0] for _k, _l, ch in asks] == ["(ask)"], repr(asks))
check("POOLSIDE's own default applies when nothing is sent",
      '(psd:fkw \'mirror "Yes No" "No")' in PSD)


print("== 5. the recall slot is the bottom type ==")

check("the slot is the type keyword",
      'Return SelectedType.Keyword' in VIEW)
check("it is stored under LAZSIDE's key",
      'RecallStore.SideKey' in VIEW)

store = read(os.path.join(REPO, 'ui', 'calofin_net', 'ChartFormView.vb'))
m = re.search(r'Public Const SideKey As String =\s*\n\s*"([^"]+)"', store)
check("...which is lzv:*recallkey* itself",
      m and m.group(1) == re.search(
          r'\(setq lzv:\*recallkey\* "([^"]+)"\)', LZV).group(1).replace(
              '\\\\', '\\'),
      repr(m.group(1) if m else None))

check("lzv:recall-slot is the same thing",
      '(defun lzv:recall-slot ( ) lzv:*type*)' in LZV)

# Recall fills EMPTY boxes only, so it can never overwrite a number just
# typed and pressing it twice is a no-op -- lzv:recall's own rule.
check("recall fills the empty boxes only",
      re.search(r'Private Sub Recall\(\).*?If b\.IsFilled Then Continue For',
                VIEW, re.S) is not None)


print("== 6. the form keeps no table of its own ==")

check("the entry point comes from the catalog",
      'ChartCatalog.SideEntryPoint' in VIEW
      and 'psd:run-with-answers' not in VIEW)
check("the bottom types come from the catalog",
      'For Each t In ChartCatalog.SideTypes' in VIEW
      and not any(('"%s"' % k) in VIEW for k, _t in sidetypes),
      repr([k for k, _t in sidetypes if ('"%s"' % k) in VIEW]))
check("the catalog's entry point is POOLSIDE's",
      entry == 'psd:run-with-answers', entry)
check("...and POOLSIDE defines it",
      '(defun psd:run-with-answers (answers)' in PSD)


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL SIDE FORM CHECKS PASSED (%d bottom types, %d depth keys)"
      % (len(sidetypes), len(depths)))
