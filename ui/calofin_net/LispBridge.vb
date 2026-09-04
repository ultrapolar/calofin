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

    ''' <summary>
    ''' One (key . "typed") pair: a measurement box's text, exactly as it
    ''' was typed.
    '''
    ''' <para>THIS ASSEMBLY DOES NOT READ A MEASUREMENT.  It used to, with
    ''' Double.TryParse, and that accepted a plain decimal and nothing
    ''' else -- so a feet-and-inches spelling, which the DCL charts read
    ''' perfectly and tell the drafter to use, produced no number and the
    ''' palette sent (key . nil).  That is not "ask me": nil is NA, the
    ''' measurement travelled as NOT TAKEN, and the routine never
    ''' asked.</para>
    '''
    ''' <para>calofin.lsp reads it now, through AutoCAD's own distof,
    ''' which knows every feet-and-inches spelling there is.  There is
    ''' deliberately no numeric pair helper left here: a second way to
    ''' send a measurement is a second parser to keep in step, and that
    ''' is the bug above.</para>
    ''' </summary>
    Public Shared Function MeasurePair(key As String, typed As String) As String
        Return Pair(key, Str(If(typed, "")))
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
    ''' A form, through calofin.lsp's wire:
    ''' (calofin:run "fn" '(literals) '(measures)).
    '''
    ''' <para>Two lists, and the split is this assembly's to make. A
    ''' LITERAL travels as it is written -- a shape word, a keyword
    ''' answer, an insertion point -- while a MEASURE is typed text and
    ''' is read on the other side. Run a "Rectangle" through a
    ''' measurement reader and it comes back unreadable, and the shape
    ''' stops travelling; that is why the palette says which is
    ''' which.</para>
    ''' </summary>
    Public Shared Function BuildFormCall(fn As String,
                                         literals As IEnumerable(Of String),
                                         measures As IEnumerable(Of String)) As String
        Return "(calofin:run " & Str(fn) &
               " '(" & String.Join(" ", literals) & ")" &
               " '(" & String.Join(" ", measures) & "))"
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
