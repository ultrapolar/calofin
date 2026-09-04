Imports System.Collections.Generic
Imports System.Windows
Imports System.Windows.Controls
Imports Autodesk.AutoCAD.ApplicationServices
Imports Autodesk.AutoCAD.DatabaseServices
Imports Autodesk.AutoCAD.Runtime
Imports Autodesk.AutoCAD.Windows
Imports AcadApp = Autodesk.AutoCAD.ApplicationServices.Application

''' <summary>
''' One dockable palette for the whole toolset.
'''
''' The Commands tab exists because the routines are remembered by what
''' they do, not by what they are called. Nothing here reimplements any of
''' them -- each button sends the command name it always had.
''' </summary>
Public Class CalofinPalette

    Private Shared _ps As PaletteSet

    <CommandMethod("CALOFIN")>
    Public Shared Sub ShowPalette()
        If _ps Is Nothing Then
            _ps = New PaletteSet("Calofin", New Guid("6E9C1E42-0B3A-4E0F-9E7B-2C2A4B9D51A7"))
            _ps.Style = PaletteSetStyles.ShowPropertiesMenu Or
                        PaletteSetStyles.ShowAutoHideButton Or
                        PaletteSetStyles.ShowCloseButton
            _ps.MinimumSize = New Drawing.Size(320, 400)

            _ps.AddVisual("Commands", New CommandsTab())
            ' The plan chart, drawn from LAZFORM's own vectors -- the
            ' sheet the palette never had.  POOL's bottom stays a tab of
            ' its own because it is a different drawing: a section, with
            ' the depths on it, and LAZFORM keeps them apart too.
            _ps.AddVisual("Pool chart", New ChartFormView(
                ChartCatalog.Pool, "pool:run-with-answers",
                RecallStore.PoolKey,
                "Pick the sheet, fill in what you have. Anything left " &
                "blank is asked for at the command line."))
            _ps.AddVisual("Spa", New SpaFormView())
            _ps.AddVisual("Pool bottom", New PoolFormView())
        End If
        _ps.Visible = True
    End Sub

End Class


''' <summary>
''' The catalog lives in Generated\CommandCatalog.g.vb.
'''
''' It used to be typed here, and that is exactly how the palette came
''' to ship 60 of the panel's 67 commands with every caption it DID
''' carry still agreeing -- two copies of one roster, and only the
''' halves anybody checked looked fine.  The table is now written from
''' LAZPANEL's own lzp:*captions* and lzp:*groups* by
''' tools/gen_ui_data.py, so the panel and the palette cannot read
''' differently.  The one piece of editorial text, the tooltip blurb,
''' is hand-written in ui/calofin_net/blurbs.txt and read by the
''' generator; nothing is invented.
'''
''' Adding a tool to the palette is therefore: put it on LAZPANEL,
''' write its blurb, run the generator.
''' </summary>


''' <summary>
''' One hit on the Find list.
'''
''' Carries whether the command is loaded rather than looking it up as
''' it draws: the list is rebuilt on every keystroke, and the probe is
''' a round trip into Lisp.
''' </summary>
Public Class CommandHit

    ' Properties, not fields.  DisplayMemberPath is a PropertyPath and
    ' WPF binding resolves it by reflecting over PROPERTIES; bound to a
    ' public field it finds nothing and every row of the list draws
    ' blank, with no error anywhere to say why.
    Public ReadOnly Property Command As String
    Public ReadOnly Property Text As String
    Public ReadOnly Property Loaded As Boolean

    Public Sub New(entry As CommandCatalog.Entry, loaded As Boolean)
        Me.Command = entry.Command
        Me.Loaded = loaded
        ' lzp:hitline's line, word for word.  The two surfaces list the
        ' same tool the same way or the drafter has to learn both.
        Me.Text = entry.Command & "  -  " & entry.Caption &
                  If(loaded, "", "   (not loaded)")
    End Sub

End Class


''' <summary>
''' The Commands tab: find a tool, or reach for one you have used.
'''
''' <para>It carries what LAZPANEL carries, because the two are the same
''' panel on different plumbing: a search over names AND captions, the
''' tools you pinned, the last few you launched, and the whole tab strip
''' -- the four job pages as well as the four categories. The tables all
''' come from Generated\CommandCatalog.g.vb, which is LAZPANEL's own
''' roster, so neither surface can offer a tool the other does not.
''' </para>
'''
''' <para>Two behaviours are deliberately opposite, and both are
''' LAZPANEL's. On a PAGE, a routine this session has not loaded is
''' greyed: a dead spot in a grid is visible, and reaching for it tells
''' you why. On the FIND list it is listed instead, marked
''' "(not loaded)", and Run refuses it with that reason -- because a
''' search that silently omits what you searched for reads as the tool
''' not existing.</para>
''' </summary>
Public Class CommandsTab
    Inherits UserControl

    ''' <summary>Buttons on the pages: built once, never rebuilt.</summary>
    Private ReadOnly _pageButtons As New List(Of Button)

    ''' <summary>Buttons on the Recent and Pinned rows, which are rebuilt
    ''' every time a tool is launched or pinned.</summary>
    Private ReadOnly _rowButtons As New List(Of Button)

    Private ReadOnly _search As New TextBox() With {
        .Margin = New Thickness(0, 0, 6, 0),
        .Padding = New Thickness(3, 2, 3, 2),
        .ToolTip = "Any part of a command name or of its caption. " &
                   "Taken literally - a * is a star, not a wildcard."}
    Private ReadOnly _message As New TextBlock() With {
        .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
        .Margin = New Thickness(0, 4, 0, 4)}
    Private ReadOnly _hits As New ListBox() With {
        .DisplayMemberPath = "Text",
        .Visibility = Visibility.Collapsed}
    Private ReadOnly _rows As New StackPanel()
    Private ReadOnly _tabs As New TabControl()

    ''' <summary>What (calofin:loaded) said, or Nothing when the probe
    ''' itself is unavailable -- which is read as "assume everything is
    ''' there".</summary>
    Private _loaded As HashSet(Of String)

    Public Sub New()
        Dim root As New DockPanel() With {.Margin = New Thickness(8)}

        Dim searchRow = BuildSearchRow()
        DockPanel.SetDock(searchRow, Dock.Top)
        root.Children.Add(searchRow)
        DockPanel.SetDock(_message, Dock.Top)
        root.Children.Add(_message)
        DockPanel.SetDock(_rows, Dock.Top)
        root.Children.Add(_rows)

        BuildPages()
        ' a single click only moves the highlight -- running the list
        ' down with the mouse is how you read it -- so a launch needs a
        ' double click or Enter, which is lzp:hitpick's rule
        AddHandler _hits.MouseDoubleClick, Sub() RunSelected()
        AddHandler _hits.KeyDown, AddressOf HitKey

        Dim body As New Grid()
        body.Children.Add(_tabs)
        body.Children.Add(_hits)
        root.Children.Add(body)

        Content = root

        RefreshRows()
        UpdateAvailability()
        RestorePage()
    End Sub

    ' ---------------------------------------------------------- building

    Private Function BuildSearchRow() As FrameworkElement
        Dim row As New DockPanel()

        Dim refresh As New Button() With {
            .Content = "Refresh",
            .Padding = New Thickness(8, 2, 8, 2),
            .ToolTip = "Ask this session again which routines are loaded"}
        AddHandler refresh.Click, Sub() UpdateAvailability()
        DockPanel.SetDock(refresh, Dock.Right)
        row.Children.Add(refresh)

        Dim clear As New Button() With {
            .Content = "X", .Padding = New Thickness(6, 2, 6, 2),
            .Margin = New Thickness(0, 0, 4, 0),
            .ToolTip = "Clear the search"}
        AddHandler clear.Click, Sub() _search.Clear()
        DockPanel.SetDock(clear, Dock.Right)
        row.Children.Add(clear)

        AddHandler _search.TextChanged, Sub() Fill()
        AddHandler _search.KeyDown, AddressOf SearchKey
        row.Children.Add(_search)
        Return row
    End Function

    ''' <summary>
    ''' The pages, as tabs -- which is the one place this surface can be
    ''' plainly better than the panel it mirrors. DCL has no tab tile, so
    ''' LAZPANEL's strip is a row of buttons that closes the page and
    ''' reopens the next, and it blinks. Here a page is a page.
    ''' </summary>
    Private Sub BuildPages()
        For Each page In CommandCatalog.Pages
            ' The panel shows the CAPTION on a single-column page and the
            ' NAME on a multi-column one, because four captions side by
            ' side do not fit a DCL dialog.  Mirrored rather than
            ' improved on: a tool should read the same on both surfaces,
            ' and the caption is on the tooltip either way.
            Dim withCaption = page.Columns.Length = 1
            Dim spread As New WrapPanel()
            For Each col In page.Columns
                Dim column As New StackPanel() With {
                    .Margin = New Thickness(0, 0, 12, 8), .MinWidth = 140}
                If col.Heading.Length > 0 Then
                    column.Children.Add(New TextBlock() With {
                        .Text = col.Heading, .FontWeight = FontWeights.Bold,
                        .Margin = New Thickness(0, 6, 0, 4)})
                End If
                For Each cmdName In col.Commands
                    column.Children.Add(
                        MakeButton(EntryFor(cmdName), withCaption,
                                   _pageButtons))
                Next
                spread.Children.Add(column)
            Next

            Dim item As New TabItem() With {
                .Header = page.Title,
                .Content = New ScrollViewer() With {
                    .VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                    .Padding = New Thickness(4),
                    .Content = spread}}
            _tabs.Items.Add(item)
        Next
        AddHandler _tabs.SelectionChanged, Sub() RememberPage()
    End Sub

    ''' <summary>
    ''' The Recent and Pinned rows, rebuilt from what is remembered.
    '''
    ''' A row with nothing in it is not drawn at all -- a first-run
    ''' palette is no taller than it was, which is lzp:recrow's rule for
    ''' the same reason in a place where height was fatal.
    ''' </summary>
    Private Sub RefreshRows()
        _rows.Children.Clear()
        _rowButtons.Clear()
        AddRow("Recent", PaletteMemory.RecentShown())
        AddRow("Pinned", PaletteMemory.Pins())
        ApplyAvailability()
    End Sub

    Private Sub AddRow(title As String, names As List(Of String))
        If names.Count = 0 Then Return
        Dim wrap As New WrapPanel()
        For Each cmdName In names
            wrap.Children.Add(MakeButton(EntryFor(cmdName), False,
                                         _rowButtons))
        Next
        _rows.Children.Add(New GroupBox() With {
            .Header = title, .Content = wrap,
            .Margin = New Thickness(0, 0, 0, 6),
            .Padding = New Thickness(4, 2, 4, 2)})
    End Sub

    ''' <summary>One command button, with the pin toggle on its right
    ''' click. INTO is the list that owns it, so availability can find
    ''' it again.</summary>
    Private Function MakeButton(entry As CommandCatalog.Entry,
                                withCaption As Boolean,
                                into As List(Of Button)) As Button
        Dim cmd = entry.Command
        Dim b As New Button() With {
            .Content = If(withCaption, entry.Caption, cmd),
            .Tag = cmd,
            .ToolTip = cmd & "  -  " & entry.Caption & vbLf & entry.Blurb,
            .Margin = New Thickness(0, 2, 4, 2),
            .Padding = New Thickness(6, 3, 6, 3),
            .HorizontalContentAlignment = HorizontalAlignment.Left}
        AddHandler b.Click, Sub() RunCommand(cmd)

        Dim pin As New MenuItem()
        AddHandler pin.Click,
            Sub()
                PaletteMemory.TogglePin(cmd)
                RefreshRows()
            End Sub
        Dim menu As New ContextMenu()
        menu.Items.Add(pin)
        ' read on opening, never cached: the same command can have a
        ' button on a page, on Recent and on Pinned at once, and a pin
        ' from any of them has to be true of all of them
        AddHandler menu.Opened,
            Sub()
                pin.Header = If(PaletteMemory.Pins().Contains(cmd),
                                "Unpin " & cmd, "Pin " & cmd)
            End Sub
        b.ContextMenu = menu

        into.Add(b)
        Return b
    End Function

    ''' <summary>The catalog entry for a name. Total on purpose: a page
    ''' can only name a command the catalog carries -- they are generated
    ''' from one table -- but a button with no caption is a better answer
    ''' than a crash if that ever stops being true.</summary>
    Private Shared Function EntryFor(command As String) As CommandCatalog.Entry
        For Each e In CommandCatalog.All
            If e.Command = command Then Return e
        Next
        Return New CommandCatalog.Entry(command, command, command)
    End Function

    ' ------------------------------------------------------------- find

    ''' <summary>
    ''' Re-run the search and refill the list.
    '''
    ''' The needle is taken LITERALLY, which is lzp:instr's whole reason
    ''' for being written out rather than handed to wcmatch: the text is
    ''' whatever the user typed, and a pattern matcher would read a "*"
    ''' in it as "everything" and a "." as "nothing".
    ''' </summary>
    Private Sub Fill()
        Dim needle = _search.Text.Trim().ToUpperInvariant()
        Dim hits As New List(Of CommandHit)
        For Each e In CommandCatalog.All
            If needle.Length = 0 OrElse
               e.Command.ToUpperInvariant().Contains(needle) OrElse
               e.Caption.ToUpperInvariant().Contains(needle) Then
                hits.Add(New CommandHit(e, IsLoaded(e.Command)))
            End If
        Next

        _hits.ItemsSource = hits
        ' the top hit is selected for you, so a search and Enter runs
        ' the obvious thing without a click in between
        If hits.Count > 0 Then _hits.SelectedIndex = 0
        _message.Text = FindMessage(needle, hits.Count)

        Dim searching = needle.Length > 0
        _hits.Visibility = If(searching, Visibility.Visible,
                              Visibility.Collapsed)
        _tabs.Visibility = If(searching, Visibility.Collapsed,
                              Visibility.Visible)
        _rows.Visibility = If(searching, Visibility.Collapsed,
                              Visibility.Visible)
    End Sub

    ''' <summary>lzp:findmsg: how much the search left.</summary>
    Private Shared Function FindMessage(needle As String,
                                        found As Integer) As String
        If needle.Length = 0 Then
            Return CommandCatalog.All.Length.ToString() &
                   " tools - type any part of a name or a caption"
        End If
        If found = 0 Then Return "no tool matches """ & needle & """"
        Return found.ToString() & " of " &
               CommandCatalog.All.Length.ToString() & " match """ &
               needle & """"
    End Function

    Private Sub SearchKey(sender As Object, e As Input.KeyEventArgs)
        If e.Key = Input.Key.Enter Then
            RunSelected()
            e.Handled = True
        ElseIf e.Key = Input.Key.Escape Then
            _search.Clear()
            e.Handled = True
        ElseIf e.Key = Input.Key.Down AndAlso _hits.Items.Count > 0 Then
            _hits.Focus()
            e.Handled = True
        End If
    End Sub

    Private Sub HitKey(sender As Object, e As Input.KeyEventArgs)
        If e.Key = Input.Key.Enter Then
            RunSelected()
            e.Handled = True
        End If
    End Sub

    ''' <summary>
    ''' Run what is highlighted. Unlike a button on a page this can
    ''' refuse: the list shows tools this session has not loaded, so the
    ''' check that greys a button happens here instead, and says so on
    ''' the message line.
    ''' </summary>
    Private Sub RunSelected()
        Dim hit = TryCast(_hits.SelectedItem, CommandHit)
        If hit Is Nothing Then
            _message.Text = "nothing highlighted to run"
        ElseIf Not hit.Loaded Then
            _message.Text = hit.Command & " is not loaded in this session"
        Else
            RunCommand(hit.Command)
        End If
    End Sub

    ' -------------------------------------------------------- launching

    ''' <summary>
    ''' A command cannot be started while the palette holds the thread, so
    ''' the name is queued on the document and runs once we yield.
    ''' </summary>
    Private Sub RunCommand(command As String)
        Dim doc = AcadApp.DocumentManager.MdiActiveDocument
        If doc Is Nothing Then Return
        PaletteMemory.Remember(command)
        RefreshRows()
        doc.SendStringToExecute("_." & command & vbLf, True, False, True)
    End Sub

    ' ----------------------------------------------------- availability

    Private Function IsLoaded(command As String) As Boolean
        If _loaded Is Nothing Then Return True
        Return _loaded.Contains(command.ToUpperInvariant())
    End Function

    ''' <summary>
    ''' Asks Lisp which C: functions are actually defined. If the probe
    ''' itself is unavailable -- calofin.lsp not loaded yet -- every button
    ''' is left enabled: a palette that wrongly greys everything out is
    ''' worse than one that lets a command report its own absence.
    ''' </summary>
    Public Sub UpdateAvailability()
        Try
            _loaded = LispProbe.DefinedCommands()
        Catch
            _loaded = Nothing
        End Try
        ApplyAvailability()
        Fill()
    End Sub

    ''' <summary>Grey what is missing, without asking Lisp again. The
    ''' rows are rebuilt on every launch and every pin, and a probe is a
    ''' round trip into the Lisp environment -- one per keystroke-sized
    ''' event is a cost with nothing to show for it, since the answer
    ''' cannot have changed while the palette held the thread.</summary>
    Private Sub ApplyAvailability()
        For Each b In _pageButtons
            b.IsEnabled = IsLoaded(CStr(b.Tag))
        Next
        For Each b In _rowButtons
            b.IsEnabled = IsLoaded(CStr(b.Tag))
        Next
    End Sub

    ' ------------------------------------------------- the page it opens on

    Private Sub RestorePage()
        Dim want = PaletteMemory.Page()
        If want.Length = 0 Then Return
        For Each item As TabItem In _tabs.Items
            If String.Equals(CStr(item.Header), want,
                             StringComparison.OrdinalIgnoreCase) Then
                _tabs.SelectedItem = item
                Return
            End If
        Next
    End Sub

    Private Sub RememberPage()
        Dim item = TryCast(_tabs.SelectedItem, TabItem)
        If item IsNot Nothing Then PaletteMemory.SetPage(CStr(item.Header))
    End Sub

End Class


''' <summary>
''' Asks the running Lisp environment what it has loaded.
''' </summary>
Public NotInheritable Class LispProbe

    Private Sub New()
    End Sub

    ''' <summary>
    ''' Calls (calofin:loaded) from calofin.lsp, which returns the list of
    ''' command names it can find. Returns Nothing when the helper is not
    ''' loaded, which the caller treats as "assume everything is there".
    ''' </summary>
    Public Shared Function DefinedCommands() As HashSet(Of String)
        Dim args As New ResultBuffer(
            New TypedValue(CInt(LispDataType.Text), "calofin:loaded"))

        Dim res As ResultBuffer = AcadApp.Invoke(args)
        If res Is Nothing Then Return Nothing

        Dim out As New HashSet(Of String)
        For Each tv As TypedValue In res
            If tv.TypeCode = CInt(LispDataType.Text) AndAlso tv.Value IsNot Nothing Then
                out.Add(CStr(tv.Value).ToUpperInvariant())
            End If
        Next
        If out.Count = 0 Then Return Nothing
        Return out
    End Function

End Class
