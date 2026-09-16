Imports System.Collections.Generic
Imports System.Windows
Imports System.Windows.Controls
Imports System.Windows.Media
Imports AcadApp = Autodesk.AutoCAD.ApplicationServices.Application

''' <summary>
''' The pool SIDE VIEW: read the section, type the letters beside it,
''' and POOLSIDE draws it.
'''
''' <para>LAZSIDE's argument, on the palette. The longitudinal section
''' stands on one side as a whole picture and every dimension it carries
''' has a box in the column beside it; the picture is read, the column
''' is typed into, and the letter ties the two together.</para>
'''
''' <para><b>One page per bottom type.</b> Six floors are six different
''' chains of letters, so picking the type is not a filter over one
''' sheet -- it is the sheet, and it is also the answer POOLSIDE's first
''' prompt gets. That is lzv:form's rule, spelled as plainly as it is
''' there: "whichever tab is open is the answer POOLSIDE's first prompt
''' gets, so a sheet can never be filled in for one floor and drawn as
''' another". Nothing here builds a section; it picks one generated from
''' lzv:chart.</para>
'''
''' <para><b>One rule is mirrored from lzv:form rather than left to the
''' wire</b>, and it is the same shape as the step sheet's tread: a
''' <b>depth answered NA is withheld</b>. POOLSIDE requires a
''' measurement for C, D and C2 -- an NA in one of them travels as NOT
''' MEASURED and the question is then never asked. WHICH keys those are
''' is lzv:depthkey, a table, and it comes through the catalog with the
''' rest of the sheet, so there is no rule here beyond looking in
''' it.</para>
'''
''' <para><b>What is deliberately not mirrored is lzv:depthbad</b> --
''' that D must be deeper than C and C2 sit between them. The panel can
''' say so because it has read all three numbers; this form has read
''' none of them, which is the whole point of the wire, and a palette
''' that started parsing boxes to answer it would be the bug the wire
''' was built to fix. POOLSIDE loops at its own prompt until the pair is
''' right, exactly as it does for a drafter typing at the command
''' line.</para>
''' </summary>
Public Class SideFormView
    Inherits UserControl

    Private ReadOnly _type As New ComboBox()
    Private ReadOnly _sheet As New ChartSheet()
    Private ReadOnly _rows As New StackPanel()
    Private ReadOnly _picks As New Dictionary(Of String, ComboBox)
    Private ReadOnly _state As New TextBlock() With {
        .TextWrapping = TextWrapping.Wrap,
        .Margin = New Thickness(0, 6, 0, 6)}
    Private ReadOnly _draw As New Button() With {
        .Content = "Draw", .Padding = New Thickness(14, 4, 14, 4)}
    Private ReadOnly _recall As New Button() With {
        .Content = "Recall last", .Padding = New Thickness(10, 4, 10, 4),
        .Margin = New Thickness(0, 0, 6, 0),
        .ToolTip = "Put the last accepted sheet for this bottom type " &
                   "back into the empty boxes"}

    Private ReadOnly _boxes As New List(Of ChartBox)

    ''' <summary>
    ''' What has been typed, BY KEY, kept across a rebuild.
    '''
    ''' <para>Changing the bottom type throws every row away and builds
    ''' another, and without this that took the sheet with it. A drafter
    ''' who fills a Normal in and then reads the survey again as a
    ''' Sport must not lose B, C and D for saying so -- those three are
    ''' on every page and mean the same thing on all of them. A letter
    ''' the new floor does not have simply waits, and comes back if the
    ''' type does.</para>
    ''' </summary>
    Private ReadOnly _typed As New Dictionary(Of String, String)

    ''' <summary>Which word each dropdown was left on, kept across a
    ''' rebuild for the same reason the boxes are.</summary>
    Private ReadOnly _picked As New Dictionary(Of String, String)

    Private _current As ChartCatalog.SideChart

    Public Sub New()
        Dim root As New DockPanel() With {.Margin = New Thickness(8)}

        Dim head As New StackPanel()
        head.Children.Add(New TextBlock() With {
            .Text = "Pick the bottom type, then read the section and " &
                    "fill in the letters beside it. The type is the " &
                    "sheet AND the answer to POOLSIDE's first question.",
            .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 6)})
        head.Children.Add(New TextBlock() With {
            .Text = "A box takes 24, or a feet-and-inches spelling - " &
                    "both read. NA in a RUN says it was not measured " &
                    "and is read back off B; a DEPTH has no NA.",
            .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 6)})

        For Each t In ChartCatalog.SideTypes
            _type.Items.Add(t.Title)
        Next
        AddHandler _type.SelectionChanged, Sub() ShowSheet()
        head.Children.Add(_type)
        DockPanel.SetDock(head, Dock.Top)
        root.Children.Add(head)

        Dim foot As New StackPanel()
        foot.Children.Add(_state)
        Dim buttons As New StackPanel() With {
            .Orientation = Orientation.Horizontal,
            .HorizontalAlignment = HorizontalAlignment.Right}
        Dim clear As New Button() With {
            .Content = "Clear", .Padding = New Thickness(10, 4, 10, 4),
            .Margin = New Thickness(0, 0, 6, 0)}
        AddHandler clear.Click, Sub() ClearSheet()
        AddHandler _recall.Click, Sub() Recall()
        AddHandler _draw.Click, Sub() Run()
        buttons.Children.Add(clear)
        buttons.Children.Add(_recall)
        buttons.Children.Add(_draw)
        foot.Children.Add(buttons)
        DockPanel.SetDock(foot, Dock.Bottom)
        root.Children.Add(foot)

        ' The section is a wide, shallow thing -- lzv:*chart-a* draws it
        ' at 0.62 of its width -- so it gets the larger share of the
        ' split, the other way round from the plan sheets.
        Dim split As New Grid()
        split.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(1, GridUnitType.Star)})
        split.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(1.6, GridUnitType.Star)})
        split.Children.Add(New ScrollViewer() With {
            .VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            .Content = _rows})
        Grid.SetColumn(_sheet, 1)
        split.Children.Add(_sheet)
        root.Children.Add(split)

        AddHandler _sheet.BoxChanged, Sub() Restate()

        Content = root
        If ChartCatalog.SideTypes.Length > 0 Then _type.SelectedIndex = 0
    End Sub

    ''' <summary>The bottom type the picker is on. Named SelectedType
    ''' rather than Style because UserControl already has a Style and a
    ''' second one here would shadow it.</summary>
    Private ReadOnly Property SelectedType As ChartCatalog.SideType
        Get
            Dim i = _type.SelectedIndex
            If i < 0 OrElse i >= ChartCatalog.SideTypes.Length Then
                Return Nothing
            End If
            Return ChartCatalog.SideTypes(i)
        End Get
    End Property

    ''' <summary>The slot a sheet is remembered under: lzv:recall-slot,
    ''' which is the bottom type itself. A Sport's E2/F2/F1/E1 mean
    ''' nothing on a Normal, so one type's sheet must never come back on
    ''' another's.</summary>
    Private ReadOnly Property Slot As String
        Get
            Return SelectedType.Keyword
        End Get
    End Property

    Private Sub ShowSheet()
        If SelectedType.Keyword Is Nothing Then Return
        ' before a single row is thrown away
        Remember()
        _current = ChartCatalog.SideChartFor(SelectedType.Keyword)
        _boxes.Clear()
        _rows.Children.Clear()
        _picks.Clear()
        If _current.Style Is Nothing Then
            _sheet.Show(Nothing, Nothing, _boxes)
            _state.Text = "No section for that bottom type."
            _draw.IsEnabled = False
            _recall.IsEnabled = False
            Return
        End If

        For Each d In _current.Dims
            _boxes.Add(New ChartBox(d))
        Next
        _building = True
        Try
            For Each b In _boxes
                _rows.Children.Add(MakeRow(b))
            Next
            For Each q In ChartCatalog.SideAsks
                AddPick(q)
            Next
            Restore()
        Finally
            _building = False
        End Try
        _sheet.Show(_current.Strokes, New ChartCatalog.Mark() {}, _boxes)
        Restate()
    End Sub

    ''' <summary>One question that is not a letter. Left on "(ask)" it
    ''' sends nothing at all and POOLSIDE asks, which is the same answer
    ''' as an empty box and is why the first option is never a
    ''' value.</summary>
    Private Sub AddPick(q As ChartCatalog.SideAsk)
        Dim combo As New ComboBox() With {.Width = 120, .SelectedIndex = 0}
        For Each o In q.Choices
            combo.Items.Add(o)
        Next
        Dim was As String = Nothing
        If _picked.TryGetValue(q.Key, was) AndAlso
           Not String.IsNullOrEmpty(was) Then
            Dim i = combo.Items.IndexOf(was)
            If i > 0 Then combo.SelectedIndex = i
        End If
        AddHandler combo.SelectionChanged, Sub() Restate()
        _picks(q.Key) = combo

        Dim row As New DockPanel() With {.Margin = New Thickness(0, 6, 0, 2)}
        DockPanel.SetDock(combo, Dock.Right)
        row.Children.Add(combo)
        row.Children.Add(New TextBlock() With {
            .Text = q.Label, .ToolTip = q.Label,
            .TextTrimming = TextTrimming.CharacterEllipsis,
            .VerticalAlignment = VerticalAlignment.Center,
            .Margin = New Thickness(34, 0, 8, 0)})
        _rows.Children.Add(row)
    End Sub

    ''' <summary>Keep what is typed before the rows are rebuilt. An
    ''' emptied box is FORGOTTEN rather than kept at "", so clearing one
    ''' and coming back does not bring it back.</summary>
    Private Sub Remember()
        For Each b In _boxes
            If b.IsFilled Then
                _typed(b.Key) = b.Text
            Else
                _typed.Remove(b.Key)
            End If
        Next
        For Each kv In _picks
            _picked(kv.Key) = Picked(kv.Key)
        Next
    End Sub

    ''' <summary>Put back what this section carries a box for. B, C and
    ''' D are on every floor and come straight across; a run letter the
    ''' new type does not have waits rather than being lost.</summary>
    Private Sub Restore()
        For Each b In _boxes
            Dim v As String = Nothing
            If _typed.TryGetValue(b.Key, v) Then b.Text = v
        Next
    End Sub

    Private Function MakeRow(box As ChartBox) As FrameworkElement
        Dim row As New DockPanel() With {.Margin = New Thickness(0, 2, 0, 2)}
        row.Children.Add(New TextBlock() With {
            .Text = box.Letter, .Width = 34, .FontWeight = FontWeights.Bold,
            .VerticalAlignment = VerticalAlignment.Center})
        Dim editor As New TextBox() With {.Width = 80}
        ChartSheet.Bind(editor, box)
        AddHandler editor.TextChanged, Sub() Restate()
        DockPanel.SetDock(editor, Dock.Right)
        row.Children.Add(editor)
        row.Children.Add(New TextBlock() With {
            .Text = box.Label, .ToolTip = box.Label,
            .TextTrimming = TextTrimming.CharacterEllipsis,
            .VerticalAlignment = VerticalAlignment.Center,
            .Margin = New Thickness(0, 0, 8, 0)})
        Return row
    End Function

    ''' <summary>True while the rows are being built. Each binding fires
    ''' TextChanged as it first fills its editor, and restating on every
    ''' one of those asks Lisp about a sheet nobody has typed in
    ''' yet.</summary>
    Private _building As Boolean

    Private Sub Restate()
        If _building Then Return
        If _current.Style Is Nothing Then Return
        Dim state = FormWire.Line(_boxes, NaBad())
        _state.Text = state.Text
        _state.Foreground = If(state.Ready, SystemColors.GrayTextBrush,
                               Brushes.OrangeRed)
        _draw.IsEnabled = state.Ready
        _recall.IsEnabled = HasStored()
    End Sub

    Private Shared Function IsNa(b As ChartBox) As Boolean
        Return String.Equals(b.Text.Trim(), "NA",
                             StringComparison.OrdinalIgnoreCase)
    End Function

    ''' <summary>
    ''' The boxes reading NA on a key POOLSIDE has no NA for.
    '''
    ''' <para>lzv:whybad calls this "the sharp one, because NA is a word
    ''' the form itself tells you to type -- just not there". In a RUN,
    ''' NA means "not measured" and POOLSIDE reads it back off B; in a
    ''' DEPTH there is nothing to read it back from, so the answer would
    ''' travel as NOT MEASURED against a measurement POOLSIDE requires
    ''' and the question would never be asked.</para>
    '''
    ''' <para>WHICH keys those are is lzv:depthkey, a table, and it
    ''' arrives through the catalog -- there is no rule here beyond
    ''' looking in it.</para>
    ''' </summary>
    Private Function NaBad() As List(Of ChartBox)
        Dim out As New List(Of ChartBox)
        For Each b In _boxes
            If IsNa(b) AndAlso ChartCatalog.IsSideDepth(b.Key) Then
                out.Add(b)
            End If
        Next
        Return out
    End Function

    ''' <summary>What is chosen on a dropdown, or "" while it is on
    ''' "(ask)" -- which sends nothing, so POOLSIDE asks.</summary>
    Private Function Picked(key As String) As String
        Dim combo As ComboBox = Nothing
        If Not _picks.TryGetValue(key, combo) Then Return ""
        If combo.SelectedIndex <= 0 Then Return ""
        Return CStr(combo.SelectedItem)
    End Function

    ''' <summary>Clear means clear: what is remembered across a rebuild
    ''' goes with the boxes, or the next bottom type would put it all
    ''' back.</summary>
    Private Sub ClearSheet()
        For Each b In _boxes
            b.Text = ""
        Next
        _typed.Clear()
        _picked.Clear()
        For Each kv In _picks
            kv.Value.SelectedIndex = 0
        Next
        Restate()
    End Sub

    Private Function HasStored() As Boolean
        If _current.Style Is Nothing Then Return False
        Return RecallStore.Read(RecallStore.SideKey, Slot).Count > 0
    End Function

    Private Sub Recall()
        If _current.Style Is Nothing Then Return
        Dim had = RecallStore.Read(RecallStore.SideKey, Slot)
        For Each b In _boxes
            If b.IsFilled Then Continue For
            Dim v As String = Nothing
            If had.TryGetValue(b.Key, v) Then b.Text = v
        Next
        Restate()
    End Sub

    ''' <summary>
    ''' Hand the sheet to POOLSIDE.
    '''
    ''' The BOTTOM TYPE is a literal and always travels -- lzv:form puts
    ''' it first and calls it "the page itself". Then the dropdowns, and
    ''' then the letters in the order the drawing carries them. A depth
    ''' answered NA is withheld: the state line has already named it and
    ''' held Draw back, and this is the same table at the wire so the
    ''' two cannot disagree.
    ''' </summary>
    Private Sub Run()
        If _current.Style Is Nothing Then Return

        Dim literals As New List(Of String)
        Dim measures As New List(Of String)
        literals.Add(LispBridge.StrPair("style", _current.Style))
        For Each q In ChartCatalog.SideAsks
            Dim v = Picked(q.Key)
            If v.Length > 0 Then literals.Add(LispBridge.StrPair(q.Key, v))
        Next

        For Each b In _boxes
            If Not b.IsFilled Then Continue For
            If IsNa(b) AndAlso ChartCatalog.IsSideDepth(b.Key) Then Continue For
            measures.Add(LispBridge.MeasurePair(b.Key, b.Text))
        Next

        RecallStore.Save(RecallStore.SideKey, Slot, _boxes)
        LispBridge.Send(AcadApp.DocumentManager.MdiActiveDocument,
                        LispBridge.BuildFormCall(ChartCatalog.SideEntryPoint,
                                                 literals, measures))
    End Sub

End Class
