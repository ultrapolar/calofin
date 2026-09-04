# SPDX-License-Identifier: GPL-3.0-or-later
"""The palette's chart geometry, taken from the charts already under test.

``ui/UI-PLAN.md`` phase 5 listed this as blocked: ``assets/*/fieldmap.json``
and ``lzf:*charts*`` are "the same knowledge written twice", the JSON
positions are seeded estimates somebody nudged by eye, and a generated
field map that put the boxes in the wrong place would be worse than the
estimates.

That was true while the palette drew a **photograph** of a chart and
floated boxes over it at fractional positions.  It stops being true if
the palette draws the chart the way LAZFORM does -- from the vectors --
because then a box does not need a position of its own at all: it sits
on the dimension line, in the chart's own co-ordinates, and there is
nothing left for a human eye to nudge.

So this writes ``Generated/ChartCatalog.g.vb`` out of the three chart
tables:

    lzf:*charts*   13 sheets, 8 POOL and 5 OASIS
    lzs:*charts*    3 spa sheets
    lzt:chart      the step sheets, one per routine and step count,
                   because LAZSTEP builds its chart from the count
                   rather than keeping a table of them

Read through ``tests/lispvm.py`` -- the AutoLISP interpreter the suites
already drive these tools with -- rather than by regex, so what is
emitted is what the routine itself would read.

**Arcs are flattened here, by the file's own helper.**  ``lzf:flatten``
turns an arc entry into the polyline DCL draws, and calling it means the
palette needs no arc arithmetic of its own and cannot round an oval a
different way from the panel.  The palette gets polylines and a scale
factor, and that is the whole of its geometry.

What this does NOT carry, and deliberately: ``lzf:dead``, the cross-dim
mode dropdowns, ``lzf:picks`` and the corner tables.  Those are RULES,
not data -- what a page asks about given the bottom type and the
in-square toggle -- and a second copy in VB is the drift this whole
exercise exists to stop.  A palette form sends what was typed and lets
the routine ask for the rest, which is the wire's contract already.
"""

import argparse
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "tests"))

from callib import LISP_DIR, ROOT, read  # noqa: E402
from lispvm import VM, Dot  # noqa: E402

OUT = ROOT / "ui" / "calofin_net" / "Generated" / "ChartCatalog.g.vb"

#: (tool prefix, source, what its charts are called here).  The three
#: files carry the same table shape -- key, shape word, title, outline,
#: dims, extra -- because they are three copies of one form, which is
#: what phase 4 of the UI plan lifted into cal:.
SOURCES = (
    ("lzf", LISP_DIR / "lazform" / "LAZFORM.lsp", "lzf:*charts*"),
    ("lzs", LISP_DIR / "lazspa" / "LAZSPA.lsp", "lzs:*charts*"),
)

STEPS = LISP_DIR / "lazstep" / "LAZSTEP.lsp"


# ------------------------------------------------------------- reading

def vm_for(path):
    """A VM with PATH loaded -- from lisp/, whatever tier is being run.

    tests/lispvm.py remaps a lisp/ path to shared/parts/ whenever
    CALOFIN_LISP_ROOT is set, so that every suite can be re-run against
    the grouped build.  This is not a suite.  It reads the DEVELOPMENT
    HOME, always, because that is where a chart is edited and what the
    generated file is checked against -- and the grouped twin swaps
    lzf:flatten for cal:imgflatten, so a run under the other tier does
    not even find the helper.  `make parity` is how that was found.
    """
    keep = os.environ.pop("CALOFIN_LISP_ROOT", None)
    try:
        vm = VM()
        vm.load(path)
        return vm
    finally:
        if keep is not None:
            os.environ["CALOFIN_LISP_ROOT"] = keep


def num(v):
    """A co-ordinate as VB will read it.  Whole numbers stay whole: an
    Integer literal widens to Double on its own, and 1,200 of them read
    better without a trailing .0 apiece."""
    f = float(v)
    return str(int(f)) if f == int(f) else repr(f)


def strokes(vm, prefix, outline):
    """One chart's outline as flat polylines.

    Each element goes through the FILE'S OWN flatten, so an arc becomes
    exactly the polyline DCL draws it as -- same segment count, same
    rounding -- and the palette inherits that rather than deciding it.
    """
    out = []
    for i in range(len(outline or [])):
        vm.loads("(setq t:*e* (%s:flatten (nth %d t:*outline*)))" % (prefix, i))
        out.append([float(x) for x in vm.globals["t:*e*"]])
    return out


def dims(entries):
    """(letter, key, x1, y1, x2, y2, horizontal, label) per dimension."""
    out = []
    for d in entries or []:
        out.append((str(d[0]), str(d[1]),
                    float(d[2]), float(d[3]), float(d[4]), float(d[5]),
                    str(d[6]).lower() == "h", str(d[7])))
    return out


def pairs(entries):
    """(key, text) per entry -- the column-only keys, and the gates."""
    out = []
    for e in entries or []:
        # a gate is a dotted pair and an extra is a two-item list;
        # both read as "this name, that text", and lispvm spells the
        # first one Dot(a, b)
        if isinstance(e, Dot):
            out.append((str(e.a), str(e.b)))
        else:
            out.append((str(e[0]), str(e[1])))
    return out


def marks(entries):
    """(letter, x, y) per corner label -- the spa charts only."""
    return [(str(m[0]), float(m[1]), float(m[2])) for m in entries or []]


def read_charts(path, prefix, var):
    """One file's charts, as plain Python."""
    vm = vm_for(path)
    vm.loads("(setq t:*charts* %s)" % var)
    out = []
    for i, c in enumerate(vm.globals["t:*charts*"]):
        vm.loads("(setq t:*outline* (nth 3 (nth %d t:*charts*)))" % i)
        slot6 = c[6] if len(c) > 6 else None
        out.append({
            "key": str(c[0]),
            "shape": str(c[1]),
            "title": str(c[2]),
            "strokes": strokes(vm, prefix, c[3]),
            "dims": dims(c[4]),
            "extra": pairs(c[5]),
            # slot 6 is the one place the three tables differ: LAZFORM
            # implies ANSWERS there (lzf:gates), LAZSPA draws corner
            # LETTERS (lzs:marks).  Read per file rather than guessed at
            # from the contents.
            "gates": pairs(slot6) if prefix == "lzf" else [],
            "marks": marks(slot6) if prefix == "lzs" else [],
        })
    return out


def read_steps():
    """Every step sheet: one per routine, one per count up to the max.

    LAZSTEP has no chart table -- lzt:chart BUILDS a sheet for the count
    asked for -- so the generator asks for every count the dialog will
    accept and writes what comes back.  Emitting the sheets rather than
    porting the loop is the point: the rule stays in one language.
    """
    vm = vm_for(STEPS)
    top = int(vm.globals["lzt:*max-steps*"])
    routines = [(str(t[0]), str(t[1]), str(t[2]))
                for t in vm.globals["lzt:*types*"]]
    out = []
    for name, title, runner in routines:
        for n in range(1, top + 1):
            vm.loads('(setq t:*c* (lzt:chart "%s" %d))' % (name, n))
            c = vm.globals["t:*c*"]
            vm.loads("(setq t:*outline* (nth 2 t:*c*))")
            out.append({
                "routine": name,
                "title": str(c[1]),
                "steps": n,
                "strokes": strokes(vm, "lzt", c[2]),
                "dims": dims(c[3]),
                "cuts": [float(y) for y in (c[4] or [])],
            })
    return top, routines, out


def read_spa_extras():
    """LAZSPA's tables that are not the chart: the list questions, the
    corner rows, the other outline's overalls, the per-sheet hint.

    Kept SEPARATE from Chart rather than folded into it.  LAZFORM has a
    corner table too and it is a different shape -- four slots, with
    collective questions covering several corners at once -- so one
    structure for both would be a lie about one of them.  These are
    LAZSPA's, and they are spelled as such.
    """
    vm = vm_for(LISP_DIR / "lazspa" / "LAZSPA.lsp")
    src = read(LISP_DIR / "lazspa" / "LAZSPA.lsp")

    lists = []
    for d in vm.globals["lzs:*lists*"]:
        lists.append((str(d[0]), str(d[1]),
                      [str(v) for v in d[2]]))

    treatments = [str(v) for v in vm.globals["lzs:*ctreat*"]]
    #: which treatment words carry a size, asked of lzs:sized rather
    #: than read off its body -- 2 and 3 are indices into the list above
    sized = []
    for i, word in enumerate(treatments):
        vm.loads("(setq t:*s* (lzs:sized %d))" % i)
        if vm.globals["t:*s*"]:
            sized.append(word)

    #: the cover lap is a box the dialog builds rather than a table row
    m = re.search(r'\(lzs:box "gap" "([^"]+)"', src)
    gap = ("gap", m.group(1) if m else "How far the cover laps")

    sheets = []
    for c in vm.globals["lzs:*charts*"]:
        key = str(c[0])
        vm.loads('(setq t:*c* (lzs:chart "%s"))' % key)
        vm.loads("(setq t:*co* (lzs:corners t:*c*))")
        vm.loads("(setq t:*se* (lzs:second t:*c*))")
        vm.loads("(setq t:*hi* (lzs:hint t:*c*))")
        sheets.append({
            "key": key,
            "hint": str(vm.globals["t:*hi*"] or ""),
            "corners": [(str(d[0]), str(d[1]))
                        for d in (vm.globals["t:*co*"] or [])],
            "second": [(str(d[0]), str(d[1]))
                       for d in (vm.globals["t:*se*"] or [])],
        })
    return lists, treatments, sized, gap, sheets


# ------------------------------------------------------------ emitting

def vbstr(s):
    return '"' + s.replace('"', '""') + '"'


def stroke_lines(items, indent):
    out = []
    for i, pts in enumerate(items):
        tail = "," if i < len(items) - 1 else ""
        out.append("%sNew Stroke(New Double() {%s})%s"
                   % (indent, ", ".join(num(p) for p in pts), tail))
    return out


def dim_lines(items, indent):
    out = []
    for i, d in enumerate(items):
        tail = "," if i < len(items) - 1 else ""
        out.append("%sNew ChartDim(%s, %s, %s, %s, %s, %s, %s, %s)%s"
                   % (indent, vbstr(d[0]), vbstr(d[1]), num(d[2]), num(d[3]),
                      num(d[4]), num(d[5]), "True" if d[6] else "False",
                      vbstr(d[7]), tail))
    return out


def pair_lines(kind, items, indent):
    out = []
    for i, p in enumerate(items):
        tail = "," if i < len(items) - 1 else ""
        out.append("%sNew %s(%s, %s)%s"
                   % (indent, kind, vbstr(p[0]), vbstr(p[1]), tail))
    return out


def mark_lines(items, indent):
    out = []
    for i, m in enumerate(items):
        tail = "," if i < len(items) - 1 else ""
        out.append("%sNew Mark(%s, %s, %s)%s"
                   % (indent, vbstr(m[0]), num(m[1]), num(m[2]), tail))
    return out


def array(kind, lines, indent):
    """An array literal, spelled with its type.

    `New Stroke() {...}` rather than `{...}`: a bare initializer passed
    to a constructor infers Integer() from whole-number literals, and an
    Integer() will not go where a Double() is expected -- array
    covariance does not reach value types.  Spelling the type makes
    every element widen on its own.
    """
    if not lines:
        return ["%sNew %s() {}" % (indent, kind)]
    return (["%sNew %s() {" % (indent, kind)] + lines
            + ["%s}" % indent])


def chart_block(c, indent):
    L = ["%sNew Chart(%s, %s, %s," % (indent, vbstr(c["key"]),
                                      vbstr(c["shape"]), vbstr(c["title"]))]
    inner = indent + "    "
    deep = inner + "    "
    L += array("Stroke", stroke_lines(c["strokes"], deep), inner)
    L[-1] += ","
    L += array("ChartDim", dim_lines(c["dims"], deep), inner)
    L[-1] += ","
    L += array("ListKey", pair_lines("ListKey", c["extra"], deep), inner)
    L[-1] += ","
    L += array("Mark", mark_lines(c["marks"], deep), inner)
    L[-1] += ","
    L += array("Gate", pair_lines("Gate", c["gates"], deep), inner)
    L[-1] += ")"
    return L


def step_block(c, indent):
    L = ["%sNew StepChart(%s, %s, %d," % (indent, vbstr(c["routine"]),
                                          vbstr(c["title"]), c["steps"])]
    inner = indent + "    "
    deep = inner + "    "
    L += array("Stroke", stroke_lines(c["strokes"], deep), inner)
    L[-1] += ","
    L += array("ChartDim", dim_lines(c["dims"], deep), inner)
    L[-1] += ","
    L.append("%sNew Double() {%s})"
             % (inner, ", ".join(num(y) for y in c["cuts"])))
    return L


def spa_block(lists, treatments, sized, gap, sheets):
    """The LAZSPA-only tables."""
    L = []
    add = L.append
    add("")
    add("    ''' <summary>The spa questions answered from a LIST rather than")
    add("    ''' typed - lzs:*lists*. The first option is always \"(ask)\",")
    add("    ''' and choosing it sends nothing at all: the key stays absent")
    add("    ''' and SPA asks at the command line.</summary>")
    add("    Public Shared ReadOnly SpaLists As Choice() = {")
    for i, (key, label, options) in enumerate(lists):
        add("        New Choice(%s, %s, New String() {%s})%s"
            % (vbstr(key), vbstr(label),
               ", ".join(vbstr(o) for o in options),
               "," if i < len(lists) - 1 else ""))
    add("    }")
    add("")
    add("    ''' <summary>lzs:*ctreat*: the words the corner dropdown")
    add("    ''' offers. They are the SHEET LEGEND's -- 90 / Radius /")
    add("    ''' Diagonal -- and SPA normalises them onto the canonical")
    add("    ''' Square / Radius / Cut / NotGiven set itself, which is why")
    add("    ''' the palette must send them as written and not")
    add("    ''' helpfully translate.</summary>")
    add("    Public Shared ReadOnly SpaTreatments As String() = {%s}"
        % ", ".join(vbstr(t) for t in treatments))
    add("")
    add("    ''' <summary>The treatments that carry a size, asked of")
    add("    ''' lzs:sized rather than read off it. 90 sets back nothing")
    add("    ''' and asks for no number.</summary>")
    add("    Public Shared ReadOnly SpaSizedTreatments As String() = {%s}"
        % ", ".join(vbstr(t) for t in sized))
    add("")
    add("    ''' <summary>The cover lap. A box the dialog builds rather")
    add("    ''' than a table row, so it is lifted out of the source.")
    add("    ''' </summary>")
    add("    Public Shared ReadOnly SpaCoverLap As ListKey = "
        "New ListKey(%s, %s)" % (vbstr(gap[0]), vbstr(gap[1])))
    add("")
    add("    ''' <summary>What a spa sheet has that a pool sheet has not:")
    add("    ''' its corner rows, the other outline's overalls under keys")
    add("    ''' that are PER SHAPE, and the line the page prints.")
    add("    '''")
    add("    ''' <para>Kept beside Chart rather than inside it. LAZFORM has")
    add("    ''' a corner table too and it is a different shape -- four")
    add("    ''' slots, with collective questions covering several corners")
    add("    ''' at once -- so one structure for both would be a lie about")
    add("    ''' one of them.</para></summary>")
    add("    Public Shared ReadOnly SpaSheets As SpaSheet() = {")
    for i, sh in enumerate(sheets):
        add("        New SpaSheet(%s, %s," % (vbstr(sh["key"]),
                                              vbstr(sh["hint"])))
        L.extend(array("SpaCornerRow",
                       ["            New SpaCornerRow(%s, %s)%s"
                        % (vbstr(k), vbstr(lb),
                           "," if j < len(sh["corners"]) - 1 else "")
                        for j, (k, lb) in enumerate(sh["corners"])],
                       "            "))
        L[-1] += ","
        L.extend(array("ListKey",
                       ["            New ListKey(%s, %s)%s"
                        % (vbstr(k), vbstr(lb),
                           "," if j < len(sh["second"]) - 1 else "")
                        for j, (k, lb) in enumerate(sh["second"])],
                       "            "))
        L[-1] += ")" + ("," if i < len(sheets) - 1 else "")
    add("    }")
    return L


HEAD = """\
' SPDX-License-Identifier: GPL-3.0-or-later
'
' GENERATED FILE - DO NOT EDIT.  Your change will vanish.
'
'   written by : tools/gen_ui_charts.py
'   from       : lisp/lazform/LAZFORM.lsp   (lzf:*charts*)
'                lisp/lazspa/LAZSPA.lsp     (lzs:*charts*)
'                lisp/lazstep/LAZSTEP.lsp   (lzt:chart, per step count)
'   regenerate : python3 tools/gen_ui_charts.py
'   checked by : python3 tools/gen_ui_charts.py --check, which
'                make check runs
'
' The charts are the ones LAZFORM, LAZSPA and LAZSTEP draw, in their own
' co-ordinates: x and y run 0..1000 with y DOWN, the way an image tile
' counts pixels.  Arcs are already flattened to polylines, by the Lisp's
' own lzX:flatten, so the palette draws the same oval the panel does and
' needs no arc arithmetic to do it.
'
' A dimension carries the two ends of its line.  A box belongs at the
' MIDPOINT of that line -- which is why nothing here has a hand-nudged
' position: the geometry places the box.
'
' What is NOT here: which keys a page asks about given the bottom type
' and the in-square toggle (lzf:dead), the cross-dim mode dropdowns and
' the corner tables.  Those are rules rather than data, and a second
' copy of a rule is the drift this file exists to end.

Imports System.Collections.Generic


''' <summary>
''' The dimension charts, as the routines themselves hold them.
''' </summary>
Public NotInheritable Class ChartCatalog

    Private Sub New()
    End Sub

    ''' <summary>The chart's own co-ordinate space: 0..1000 each way,
    ''' y running DOWN.</summary>
    Public Const Span As Double = 1000

    ''' <summary>One run of the outline: a flat x y x y ... polyline.
    ''' Arcs arrive already flattened.</summary>
    Public Structure Stroke
        Public ReadOnly Points As Double()

        Public Sub New(points As Double())
            Me.Points = points
        End Sub
    End Structure

    ''' <summary>One dimension: the letter the sheet prints, the key the
    ''' routine reads it under, the line it measures, and the question it
    ''' stands for.</summary>
    Public Structure ChartDim
        Public ReadOnly Letter As String
        Public ReadOnly Key As String
        Public ReadOnly X1 As Double
        Public ReadOnly Y1 As Double
        Public ReadOnly X2 As Double
        Public ReadOnly Y2 As Double
        Public ReadOnly Horizontal As Boolean
        Public ReadOnly Label As String

        Public Sub New(letter As String, key As String,
                       x1 As Double, y1 As Double,
                       x2 As Double, y2 As Double,
                       horizontal As Boolean, label As String)
            Me.Letter = letter
            Me.Key = key
            Me.X1 = x1
            Me.Y1 = y1
            Me.X2 = x2
            Me.Y2 = y2
            Me.Horizontal = horizontal
            Me.Label = label
        End Sub

        ''' <summary>Where the box goes: the middle of the line it
        ''' measures.</summary>
        Public ReadOnly Property MidX As Double
            Get
                Return (X1 + X2) / 2
            End Get
        End Property

        Public ReadOnly Property MidY As Double
            Get
                Return (Y1 + Y2) / 2
            End Get
        End Property
    End Structure

    ''' <summary>A key with no line on the chart: asked in the column
    ''' beside it instead.</summary>
    Public Structure ListKey
        Public ReadOnly Key As String
        Public ReadOnly Label As String

        Public Sub New(key As String, label As String)
            Me.Key = key
            Me.Label = label
        End Sub
    End Structure

    ''' <summary>An answer the chart IMPLIES rather than asks for --
    ''' lzf:gates. The Grecian letters only exist on the Overall input
    ''' path with the hopper type the chart draws, so the sheet answers
    ''' those questions itself.</summary>
    Public Structure Gate
        Public ReadOnly Key As String
        Public ReadOnly Value As String

        Public Sub New(key As String, value As String)
            Me.Key = key
            Me.Value = value
        End Sub
    End Structure

    ''' <summary>A letter drawn on the chart itself -- the spa sheets
    ''' name their four corners this way.</summary>
    Public Structure Mark
        Public ReadOnly Letter As String
        Public ReadOnly X As Double
        Public ReadOnly Y As Double

        Public Sub New(letter As String, x As Double, y As Double)
            Me.Letter = letter
            Me.X = x
            Me.Y = y
        End Sub
    End Structure

    ''' <summary>One sheet.</summary>
    Public Structure Chart
        ''' <summary>The name the chart is looked up by.</summary>
        Public ReadOnly Key As String
        ''' <summary>What travels as the shape answer -- NOT always the
        ''' key, which is why it is carried separately.</summary>
        Public ReadOnly Shape As String
        Public ReadOnly Title As String
        Public ReadOnly Strokes As Stroke()
        Public ReadOnly Dims As ChartDim()
        Public ReadOnly Extra As ListKey()
        Public ReadOnly Marks As Mark()
        Public ReadOnly Gates As Gate()

        Public Sub New(key As String, shape As String, title As String,
                       strokes As Stroke(), dims As ChartDim(),
                       extra As ListKey(), marks As Mark(),
                       gates As Gate())
            Me.Key = key
            Me.Shape = shape
            Me.Title = title
            Me.Strokes = strokes
            Me.Dims = dims
            Me.Extra = extra
            Me.Marks = marks
            Me.Gates = gates
        End Sub
    End Structure

    ''' <summary>A question answered from a list rather than typed. The
    ''' first option is "(ask)": choosing it sends nothing and the
    ''' routine asks at the command line.</summary>
    Public Structure Choice
        Public ReadOnly Key As String
        Public ReadOnly Label As String
        Public ReadOnly Options As String()

        Public Sub New(key As String, label As String, options As String())
            Me.Key = key
            Me.Label = label
            Me.Options = options
        End Sub
    End Structure

    ''' <summary>One corner of a spa sheet. Its two answers are keyed off
    ''' the stem: cornera-ty for the treatment, cornera-sz for the size
    ''' the treatment carries.</summary>
    Public Structure SpaCornerRow
        Public ReadOnly Stem As String
        Public ReadOnly Label As String

        Public Sub New(stem As String, label As String)
            Me.Stem = stem
            Me.Label = label
        End Sub
    End Structure

    ''' <summary>What a spa sheet has that a pool sheet has not.</summary>
    Public Structure SpaSheet
        ''' <summary>The chart this belongs to.</summary>
        Public ReadOnly Key As String
        Public ReadOnly Hint As String
        Public ReadOnly Corners As SpaCornerRow()
        ''' <summary>The other outline's overalls, under keys that are
        ''' PER SHAPE: the rectangle's pair is w2/l2, the octagon's is
        ''' b2/a2 plus the cut face f2.</summary>
        Public ReadOnly Second As ListKey()

        Public Sub New(key As String, hint As String,
                       corners As SpaCornerRow(), second As ListKey())
            Me.Key = key
            Me.Hint = hint
            Me.Corners = corners
            Me.Second = second
        End Sub
    End Structure

    ''' <summary>One step routine: the command a drafter knows it by,
    ''' its title, and the entry point a form hands its answers to.
    ''' All three come from lzt:*types*.</summary>
    Public Structure StepRoutine
        Public ReadOnly Command As String
        Public ReadOnly Title As String
        Public ReadOnly EntryPoint As String

        Public Sub New(command As String, title As String,
                       entryPoint As String)
            Me.Command = command
            Me.Title = title
            Me.EntryPoint = entryPoint
        End Sub
    End Structure

    ''' <summary>A step sheet, which depends on the count as well as the
    ''' routine.</summary>
    Public Structure StepChart
        Public ReadOnly Routine As String
        Public ReadOnly Title As String
        Public ReadOnly Steps As Integer
        Public ReadOnly Strokes As Stroke()
        Public ReadOnly Dims As ChartDim()
        ''' <summary>The y of each band the sheet is cut into.</summary>
        Public ReadOnly Cuts As Double()

        Public Sub New(routine As String, title As String, steps As Integer,
                       strokes As Stroke(), dims As ChartDim(),
                       cuts As Double())
            Me.Routine = routine
            Me.Title = title
            Me.Steps = steps
            Me.Strokes = strokes
            Me.Dims = dims
            Me.Cuts = cuts
        End Sub
    End Structure
"""

TAIL = """
    ''' <summary>The POOL or OASIS sheet of that name, or one with a
    ''' Nothing Key when there is none.</summary>
    Public Shared Function PoolChart(key As String) As Chart
        Return Find(Pool, key)
    End Function

    ''' <summary>The SPA sheet of that name.</summary>
    Public Shared Function SpaChart(key As String) As Chart
        Return Find(Spa, key)
    End Function

    Private Shared Function Find(charts As Chart(), key As String) As Chart
        For Each c In charts
            If String.Equals(c.Key, key, StringComparison.OrdinalIgnoreCase) Then
                Return c
            End If
        Next
        Return Nothing
    End Function

    ''' <summary>The spa extras for a sheet, or one with a Nothing Key
    ''' when there are none.</summary>
    Public Shared Function SpaSheetFor(key As String) As SpaSheet
        For Each s In SpaSheets
            If String.Equals(s.Key, key, StringComparison.OrdinalIgnoreCase) Then
                Return s
            End If
        Next
        Return Nothing
    End Function

    ''' <summary>The step sheet for a routine and a count, or one with a
    ''' Nothing Routine when the count is outside what LAZSTEP will
    ''' draw.</summary>
    Public Shared Function StepChartFor(routine As String,
                                        steps As Integer) As StepChart
        For Each c In StepSheets
            If c.Steps = steps AndAlso
               String.Equals(c.Routine, routine,
                             StringComparison.OrdinalIgnoreCase) Then
                Return c
            End If
        Next
        Return Nothing
    End Function

End Class
"""


def build():
    L = [HEAD]
    add = L.append

    for prefix, path, var in SOURCES:
        charts = read_charts(path, prefix, var)
        name = "Pool" if prefix == "lzf" else "Spa"
        add("")
        add("    ''' <summary>%s's sheets, from %s.</summary>"
            % ("LAZFORM" if prefix == "lzf" else "LAZSPA", var))
        add("    Public Shared ReadOnly %s As Chart() = {" % name)
        for i, c in enumerate(charts):
            block = chart_block(c, "        ")
            if i < len(charts) - 1:
                block[-1] += ","
            L.extend(block)
        add("    }")

    top, routines, steps = read_steps()
    add("")
    add("    ''' <summary>The highest count LAZSTEP will draw a sheet")
    add("    ''' for - lzt:*max-steps*.  Past it the dialog would be")
    add("    ''' taller than the screen and simply not open.</summary>")
    add("    Public Const MaxSteps As Integer = %d" % top)
    add("")
    add("    ''' <summary>The three step routines, as lzt:*types* names")
    add("    ''' them: the command, its title, and the entry point a form")
    add("    ''' hands its answers to.</summary>")
    add("    Public Shared ReadOnly StepRoutines As StepRoutine() = {")
    for i, (name, title, runner) in enumerate(routines):
        add("        New StepRoutine(%s, %s, %s)%s"
            % (vbstr(name), vbstr(title), vbstr(runner),
               "," if i < len(routines) - 1 else ""))
    add("    }")
    add("")
    add("    ''' <summary>Every step sheet: one per routine per count.")
    add("    ''' LAZSTEP builds these from the count rather than keeping")
    add("    ''' a table, so the generator asked for every count the")
    add("    ''' dialog accepts.</summary>")
    add("    Public Shared ReadOnly StepSheets As StepChart() = {")
    for i, c in enumerate(steps):
        block = step_block(c, "        ")
        if i < len(steps) - 1:
            block[-1] += ","
        L.extend(block)
    add("    }")

    L.extend(spa_block(*read_spa_extras()))
    add(TAIL)
    return "\n".join(L)


# --------------------------------------------------------------- driver

def check():
    want = build()
    if not OUT.is_file():
        return ["%s: missing - run python3 tools/gen_ui_charts.py"
                % OUT.relative_to(ROOT)]
    if read(OUT) != want:
        return ["%s: stale - it is not what tools/gen_ui_charts.py would "
                "write now.  Regenerate: python3 tools/gen_ui_charts.py"
                % OUT.relative_to(ROOT)]
    return []


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="report staleness instead of writing")
    args = ap.parse_args(argv)

    text = build()
    if args.check:
        problems = check()
        for p in problems:
            print(p)
        if problems:
            return 1
        print("gen_ui_charts: %s current, %d lines"
              % (OUT.relative_to(ROOT), text.count("\n") + 1))
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    changed = not OUT.is_file() or read(OUT) != text
    OUT.write_text(text, encoding="utf-8")
    print("gen_ui_charts: %s %s (%d lines)"
          % (OUT.relative_to(ROOT), "written" if changed else "unchanged",
             text.count("\n") + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
