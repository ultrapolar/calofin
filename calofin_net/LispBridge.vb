Imports System.Globalization
Imports System.Text
Imports Autodesk.AutoCAD.ApplicationServices

''' <summary>
''' Turns collected answers into a call on SPA.LSP.
'''
''' This is the ONLY place the assembly talks to Lisp, and it deliberately
''' does nothing but format text. No geometry, no defaults, no rules about
''' what a spa is -- all of that stays in SPA.LSP, which is what keeps this
''' assembly replaceable.
'''
''' The answers travel as a Lisp alist literal rather than a ResultBuffer.
''' A ResultBuffer can carry a list, but expressing an alist of dotted
''' pairs through ListBegin/DottedPair/ListEnd markers is fiddly and fails
''' at runtime in ways that are hard to see; a printed literal is checkable
''' by eye and by test.
''' </summary>
Public NotInheritable Class LispBridge

    Private Sub New()
    End Sub

    ''' <summary>
    ''' A number as AutoLISP will read it. Invariant culture is not
    ''' optional here: on a comma-decimal locale "84,0" would either read
    ''' as a different number or break the expression outright.
    ''' </summary>
    Public Shared Function Num(value As Double) As String
        Dim s = value.ToString("0.0###########", CultureInfo.InvariantCulture)
        Return s
    End Function

    ''' <summary>A Lisp string literal, with backslashes and quotes escaped.</summary>
    Public Shared Function Str(value As String) As String
        Dim sb As New StringBuilder(value.Length + 2)
        sb.Append(""""c)
        For Each ch In value
            If ch = "\"c OrElse ch = """"c Then sb.Append("\"c)
            sb.Append(ch)
        Next
        sb.Append(""""c)
        Return sb.ToString()
    End Function

    ''' <summary>
    ''' One (key . value) pair. A field the user left empty is emitted as
    ''' an explicit nil rather than omitted: SPA.LSP reads a present-but-nil
    ''' key as "left blank", which is the same answer as NA at the prompt,
    ''' whereas an absent key means "not supplied, ask me". Those are
    ''' different intentions and the form must not blur them.
    ''' </summary>
    Public Shared Function Pair(key As String, literal As String) As String
        Return "(" & key & " . " & literal & ")"
    End Function

    ''' <summary>A point rides as a plain list, (base 0.0 0.0), not a dotted pair.</summary>
    Public Shared Function PointPair(key As String, x As Double, y As Double) As String
        Return "(" & key & " " & Num(x) & " " & Num(y) & ")"
    End Function

    Public Shared Function NumPair(key As String, value As Double?) As String
        If Not value.HasValue Then Return Pair(key, "nil")
        Return Pair(key, Num(value.Value))
    End Function

    Public Shared Function StrPair(key As String, value As String) As String
        If String.IsNullOrWhiteSpace(value) Then Return Pair(key, "nil")
        Return Pair(key, Str(value))
    End Function

    ''' <summary>
    ''' Wraps the pairs into the full call. Quoted, so Lisp takes the alist
    ''' as data rather than trying to evaluate it.
    ''' </summary>
    Public Shared Function BuildCall(fn As String, pairs As IEnumerable(Of String)) As String
        Return "(" & fn & " '(" & String.Join(" ", pairs) & "))"
    End Function

    ''' <summary>
    ''' Hands the expression to AutoCAD. SendStringToExecute queues it on
    ''' the document, so it runs after the palette has yielded -- which is
    ''' what we want: the command needs the command line to itself for any
    ''' field the form did not fill in.
    ''' </summary>
    Public Shared Sub Send(doc As Document, expression As String)
        If doc Is Nothing Then Return
        doc.SendStringToExecute(expression & vbLf, True, False, True)
    End Sub

End Class
