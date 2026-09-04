Imports System.Collections.Generic
Imports Microsoft.Win32

''' <summary>
''' What the palette remembers between sessions: pins, recents, and the
''' page it was last on.
'''
''' <para>It remembers them in LAZPANEL's OWN registry key, in
''' LAZPANEL's own format, and that is the point rather than a
''' convenience. A drafter has one set of pins; which surface they
''' happened to pin from -- the DCL panel that ships inside
''' LAZPASS.lsp, or this palette -- is an implementation detail they
''' should never have to think about. Pin CORNERSTP on the panel and
''' it is pinned here.</para>
'''
''' <para>The format is lzp:pins-write's: names joined with ";",
''' uppercase, newest-first for Recent. Anything that is not on the
''' catalog's roster is dropped as it is read, exactly as
''' lzp:pins-read does -- a pin left over from an older build must not
''' put a dead button on screen, and the roster is the only thing that
''' says what is real.</para>
'''
''' <para>Every read and write is wrapped: HKCU can be denied by policy
''' and <c>Registry.SetValue</c> throws where AutoLISP's
''' <c>vl-registry-write</c> merely answers nil. A palette that cannot
''' remember must still open.</para>
''' </summary>
Public NotInheritable Class PaletteMemory

    Private Sub New()
    End Sub

    ''' <summary>lzp:*pinkey* in lisp/lazpanel/LAZPANEL.lsp. Change one
    ''' and change the other, or the two surfaces stop sharing.</summary>
    Private Const KeyPath As String =
        "HKEY_CURRENT_USER\Software\Calofin\LazPanel"

    Private Const PinsValue As String = "Pins"
    Private Const RecentValue As String = "Recent"

    ''' <summary>The palette's own page memory. LAZPANEL keeps its page
    ''' for the session only (lzp:*page*), and its tab strip is not this
    ''' one's, so this is a value of ours under a key we share.</summary>
    Private Const PageValue As String = "PalettePage"

    ''' <summary>lzp:*reclimit*.</summary>
    Public Const RecentLimit As Integer = 5

    Private Shared Function ReadValue(name As String) As String
        Try
            Dim v = TryCast(Registry.GetValue(KeyPath, name, Nothing), String)
            If v Is Nothing Then Return ""
            Return v
        Catch
            Return ""
        End Try
    End Function

    Private Shared Sub WriteValue(name As String, value As String)
        Try
            Registry.SetValue(KeyPath, name, value, RegistryValueKind.String)
        Catch
        End Try
    End Sub

    ''' <summary>lzp:split on ";", uppercased, with the duplicates and
    ''' the blanks dropped.</summary>
    Private Shared Function Split(s As String) As List(Of String)
        Dim out As New List(Of String)
        If String.IsNullOrEmpty(s) Then Return out
        For Each part In s.Split(";"c)
            Dim n = part.Trim().ToUpperInvariant()
            If n.Length > 0 AndAlso Not out.Contains(n) Then out.Add(n)
        Next
        Return out
    End Function

    ''' <summary>Every command the catalog carries, uppercase.</summary>
    Public Shared Function Roster() As HashSet(Of String)
        Dim out As New HashSet(Of String)
        For Each e In CommandCatalog.All
            out.Add(e.Command.ToUpperInvariant())
        Next
        Return out
    End Function

    Private Shared Function OnRoster(names As List(Of String)) As List(Of String)
        Dim roster = Roster()
        Dim out As New List(Of String)
        For Each n In names
            If roster.Contains(n) Then out.Add(n)
        Next
        Return out
    End Function

    Public Shared Function Pins() As List(Of String)
        Return OnRoster(Split(ReadValue(PinsValue)))
    End Function

    ''' <summary>Pins the command if it is not pinned, unpins it if it
    ''' is; answers with whether it is pinned now. A new pin goes on the
    ''' END -- pin order is click order, so a newly ticked tool does not
    ''' jump into the middle of a row the hand has already learned.
    ''' </summary>
    Public Shared Function TogglePin(command As String) As Boolean
        Dim c = command.ToUpperInvariant()
        Dim pins = Pins()
        Dim pinned = pins.Contains(c)
        If pinned Then
            pins.Remove(c)
        Else
            pins.Add(c)
        End If
        WriteValue(PinsValue, String.Join(";", pins))
        Return Not pinned
    End Function

    Public Shared Function Recent() As List(Of String)
        Return OnRoster(Split(ReadValue(RecentValue)))
    End Function

    ''' <summary>
    ''' Newest first, once each, capped at RecentLimit.
    '''
    ''' Called when a tool is LAUNCHED rather than when it finishes, for
    ''' lzp:remember's reason: a tool that errored out was still the one
    ''' you reached for, and one you cancelled with Escape even more so
    ''' -- you will want it again in a moment.
    ''' </summary>
    Public Shared Sub Remember(command As String)
        Dim c = command.ToUpperInvariant()
        If Not Roster().Contains(c) Then Return
        Dim rec = Recent()
        rec.Remove(c)
        rec.Insert(0, c)
        While rec.Count > RecentLimit
            rec.RemoveAt(rec.Count - 1)
        End While
        WriteValue(RecentValue, String.Join(";", rec))
    End Sub

    ''' <summary>Everything remembered, minus what Pinned already shows
    ''' -- lzp:recshown. Without this, Recent fills up with the handful
    ''' of tools Pinned is already carrying.</summary>
    Public Shared Function RecentShown() As List(Of String)
        Dim pins = Pins()
        Dim out As New List(Of String)
        For Each n In Recent()
            If Not pins.Contains(n) Then out.Add(n)
        Next
        Return out
    End Function

    ''' <summary>The page to reopen on, or "" when there is nothing
    ''' worth trusting: a page name this build does not have is treated
    ''' as no answer at all.</summary>
    Public Shared Function Page() As String
        Dim want = ReadValue(PageValue)
        For Each p In CommandCatalog.Pages
            If String.Equals(p.Title, want, StringComparison.OrdinalIgnoreCase) Then
                Return p.Title
            End If
        Next
        Return ""
    End Function

    Public Shared Sub SetPage(title As String)
        If Not String.IsNullOrEmpty(title) Then WriteValue(PageValue, title)
    End Sub

End Class
