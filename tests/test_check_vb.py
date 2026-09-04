"""The VB linter, driven against VB that is wrong on purpose.

tools/check_vb.py is the only thing in this repo that reads the palette
as code, and a checker that has quietly stopped checking is worse than
none: the tree goes green and the mistake ships.  Every rule it has is
made to fire here, and -- just as important -- the shapes it must NOT
complain about are pinned too, because a linter nobody can keep green
gets switched off.

The awkward ones, all of which it got wrong first time round:

* ``Return "(" & key & " . " & literal & ")"`` -- blanking the strings
  leaves a line ending in ``&``, which reads as a line continuation and
  swallows the ``End Function`` under it.
* ``If x Then`` -- ``Then`` at the end of a line continues nothing, and
  treating it as a continuation eats the whole block it opens.
* ``<CommandMethod("CALOFIN")>`` on its own line -- an attribute, not
  part of the declaration below it.
* ``Public Property Title As String`` -- an auto-property, no body; the
  block form is spelled identically and is told apart only by the
  ``Get`` that follows.
* ``AddHandler b.Click, Sub() Run()`` versus the same thing with the
  lambda's body on later lines -- one opens a block and one does not.
* ``CommandCatalog.Entry`` -- a nested type IS a member of the type
  around it, and reading it as a missing one fails every call site that
  names it properly.
* ``New Stroke() {...}`` -- an array CREATION, not a no-argument
  constructor call; reading it as one failed every generated chart table
  at once.

Run: python3 tests/test_check_vb.py
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import check_vb  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


def lint(src):
    """check_vb's problems for a scrap of VB."""
    with tempfile.NamedTemporaryFile('w', suffix='.vb', delete=False,
                                     encoding='utf-8') as fh:
        fh.write(src)
        path = fh.name
    try:
        _, problems = check_vb.check([path])
    finally:
        os.unlink(path)
    return problems


def clean(label, src):
    p = lint(src)
    check(label, not p, repr(p[:2]))


def bites(label, src, needle):
    p = lint(src)
    check(label, any(needle in x for x in p),
          "expected %r, got %r" % (needle, p))


WRAP = """Imports System

Public Class Fixture
%s
End Class
"""


print("== the shapes that must stay quiet ==")

clean("a string full of parens and quotes", WRAP % '''
    Public Shared Function Pair(key As String, literal As String) As String
        Return "(" & key & " . " & literal & ")"
    End Function

    Public Shared Function Q() As String
        Return "he said ""no"" ((("
    End Function
''')

clean("If/Then blocks and single-line Ifs", WRAP % '''
    Public Shared Sub Go(n As Integer)
        If n > 1 Then Return
        If n = 0 Then
            Dim s = "zero"
        ElseIf n < 0 Then
            Dim s = "under"
        Else
            Dim s = "over"
        End If
    End Sub
''')

clean("an attribute on its own line", '''Imports System

Public Class Fixture
    <CommandMethod("CALOFIN")>
    Public Shared Sub Show()
        Dim x = 1
    End Sub
End Class
''')

clean("auto-properties beside a block property", WRAP % '''
    Public Property Title As String
    Public Property Fields As New List(Of String)
    Public ReadOnly Property Choices As String() =
        {"Square", "Radius", "Cut", "NotGiven"}

    Public ReadOnly Property Supported As Boolean
        Get
            Return Not String.IsNullOrEmpty(Title)
        End Get
    End Property
''')

clean("single-line and multi-line lambdas", WRAP % '''
    Public Shared Sub Wire(b As Object)
        AddHandler b.Click, Sub() Run("x")
        AddHandler b.Other,
            Sub()
                If b Is Nothing Then
                    Return
                End If
                Run("y")
            End Sub
    End Sub

    Public Shared Sub Run(s As String)
    End Sub
''')

clean("a table written across many lines", WRAP % '''
    Public Structure Entry
        Public ReadOnly Command As String
        Public ReadOnly Caption As String

        Public Sub New(command As String, caption As String)
            Me.Command = command
            Me.Caption = caption
        End Sub
    End Structure

    Public Shared ReadOnly All As Entry() = {
        New Entry("POOL", "Pool layout"),
        New Entry("SPA", "Spa template")
    }
''')

clean("a nested type named through the type around it", WRAP % '''
    Public Structure Entry
        Public ReadOnly Command As String

        Public Sub New(command As String)
            Me.Command = command
        End Sub
    End Structure

    Public Shared Function Make() As Fixture.Entry
        Dim e As Fixture.Entry = New Entry("POOL")
        Return e
    End Function
''')

clean("an array creation spelled with its type", WRAP % '''
    Public Structure Entry
        Public ReadOnly Command As String

        Public Sub New(command As String)
            Me.Command = command
        End Sub
    End Structure

    Public Structure Sheet
        Public ReadOnly Rows As Entry()

        Public Sub New(rows As Entry())
            Me.Rows = rows
        End Sub
    End Structure

    Public Shared ReadOnly One As Sheet = New Sheet(New Entry() {
        New Entry("POOL"),
        New Entry("SPA")
    })

    Public Shared ReadOnly None As Sheet = New Sheet(New Entry() {})
''')

clean("For Each / Try / Select / With / Using", WRAP % '''
    Public Shared Sub Go(items As Object)
        For Each i In CType(items, System.Collections.IEnumerable)
            Select Case CStr(i)
                Case "a"
                    Dim x = 1
                Case Else
                    Dim x = 2
            End Select
        Next
        Try
            Dim n = 0
            Do
                n += 1
            Loop While n < 3
        Catch
        Finally
        End Try
        With items
            Dim s = .ToString()
        End With
    End Sub
''')

clean("a comment carrying an apostrophe and unbalanced parens", WRAP % """
    ' the drafter's sheet ((( "unclosed
    Public Shared Sub Go()
        Dim x = 1   ' another one ))) "
    End Sub
""")


print("== the mistakes it exists to catch ==")

bites("a missing End If", WRAP % '''
    Public Shared Sub Go(n As Integer)
        If n = 0 Then
            Dim s = "zero"
    End Sub
''', "the block open here is the If")

bites("a stray End Sub", WRAP % '''
    Public Shared Sub Go()
        Dim x = 1
    End Sub
    End Sub
''', "closes nothing")

bites("an unterminated string", WRAP % '''
    Public Shared Sub Go()
        Dim s = "open
    End Sub
''', "unterminated string")

bites("an unbalanced paren", WRAP % '''
    Public Shared Sub Go()
        Dim s = Foo((1, 2)
    End Sub
''', "unmatched paren")

bites("a member this assembly does not declare", WRAP % '''
    Public Structure Entry
        Public ReadOnly Command As String

        Public Sub New(command As String)
            Me.Command = command
        End Sub
    End Structure

    Public Shared Sub Go()
        Dim s = Entry.Caption
    End Sub
''', "has no member Caption")

bites("a constructor called with the wrong arity", WRAP % '''
    Public Structure Entry
        Public ReadOnly Command As String

        Public Sub New(command As String)
            Me.Command = command
        End Sub
    End Structure

    Public Shared ReadOnly All As Entry() = {
        New Entry("POOL", "Pool layout")
    }
''', "passes 2 arguments")

bites("Imports below a declaration", '''Imports System

Public Class Fixture
End Class

Imports System.Text
''', "Imports after a declaration")

bites("a Function closed by End Sub", WRAP % '''
    Public Shared Function F() As Integer
        Return 1
    End Sub
''', "closes a Sub")


print("== a problem inside a long table is reported where it is ==")

# One statement, many lines.  Reported at the `= {` above it, the line
# number would be useless on a generated table of seven hundred.
LONG = WRAP % ("""
    Public Structure Entry
        Public ReadOnly Command As String

        Public Sub New(command As String)
            Me.Command = command
        End Sub
    End Structure

    Public Shared ReadOnly All As Entry() = {
        New Entry("A"),
        New Entry("B"),
        New Entry("C"),
        New Entry("D", "and this one is wrong")
    }
""")
problems = lint(LONG)
check("the wrong row is named by ITS line, not the table's",
      any(":17:" in p and "passes 2 arguments" in p for p in problems),
      repr(problems))


print("== it reads the real palette, and the palette is clean ==")

files, problems = check_vb.check()
check("every .vb under ui/calofin_net is read", len(files) >= 5,
      repr([f.name for f in files]))
check("no problems in the tree", not problems, repr(problems[:3]))

types = check_vb.declared(files)
check("the palette's own types are found",
      {'CommandCatalog', 'LispBridge', 'SpaField'} <= set(types),
      repr(sorted(types)[:10]))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL CHECK_VB SCENARIOS PASSED")
