Imports System.Collections.Generic
Imports System.Windows
Imports System.Windows.Controls
Imports System.Windows.Media
Imports AcadApp = Autodesk.AutoCAD.ApplicationServices.Application

''' <summary>
''' The spa sheet: `LAZSPA`'s chart, drawn, with everything SPA asks
''' around it.
'''
''' <para>A spa sheet has more on it than a pool one, and the extra is
''' not geometry: six questions answered from a LIST, four corners each
''' carrying a treatment and sometimes a size, the other outline's
''' overalls under keys that are per shape, and the cover lap. All of
''' it comes from LAZSPA's own tables through ChartCatalog, so the
''' palette offers exactly what the chart offers.</para>
'''
''' <para>The corner dropdown speaks the SHEET LEGEND -- 90 / Radius /
''' Diagonal -- and sends those words as written. SPA normalises them
''' onto the canonical Square / Radius / Cut / NotGiven set itself, and
''' a palette that translated helpfully would be a second opinion about
''' a rename the routine already handles.</para>
''' </summary>
Public Class SpaChartView
    Inherits UserControl

    Private ReadOnly _picker As New ComboBox()
    Private ReadOnly _hint As New TextBlock() With {
        .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
        .Margin = New Thickness(0, 4, 0, 4)}
    Private ReadOnly _sheet As New ChartSheet()
    Private ReadOnly _rows As New StackPanel()
    Private ReadOnly _state As New TextBlock() With {
        .TextWrapping = TextWrapping.Wrap,
        .Margin = New Thickness(0, 6, 0, 6)}
    Private ReadOnly _draw As New Button() With {
        .Content = "Draw", .Padding = New Thickness(14, 4, 14, 4)}
    Private ReadOnly _recall As New Button() With {
        .Content = "Recall last", .Padding = New Thickness(10, 4, 10, 4),
        .Margin = New Thickness(0, 0, 6, 0),
        .ToolTip = "Put the last accepted sheet for this shape back into " &
                   "the EMPTY boxes"}

    ''' <summary>Every typed box on the sheet: the chart's dimensions,
    ''' the column-only keys, the corner sizes, the other outline's
    ''' overalls and the cover lap. One list, because the state line
    ''' counts boxes and the recall store packs them.</summary>
    Private ReadOnly _boxes As New List(Of ChartBox)

    ''' <summary>The dropdowns, by the key each answers under.</summary>
    Private ReadOnly _picks As New Dictionary(Of String, ComboBox)

    ''' <summary>
    ''' What has been typed and what has been picked, BY KEY, kept
    ''' across a rebuild.
    '''
    ''' <para>Every row is thrown away and rebuilt when the shape
    ''' changes, and without this that took the sheet with it. LAZSPA
    ''' does not: "everything typed lives in lzs:*vals* and
    ''' lzs:*picks*, keyed, so it survives the switch and is still
    ''' there if you tab back" -- and its tab strip is this
    ''' picker.</para>
    ''' </summary>
    Private ReadOnly _typed As New Dictionary(Of String, String)
    Private ReadOnly _picked As New Dictionary(Of String, String)

    Private _current As ChartCatalog.Chart
    Private _spa As ChartCatalog.SpaSheet
    Private _building As Boolean

    Public Sub New()
        Dim root As New DockPanel() With {.Margin = New Thickness(8)}

        Dim head As New StackPanel()
        head.Children.Add(New TextBlock() With {
            .Text = "Pick the shape, fill in what you have. Anything left " &
                    "blank is asked for at the command line.",
            .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 6)})
        head.Children.Add(New TextBlock() With {
            .Text = "A box takes 24, or a feet-and-inches spelling - both " &
                    "read. NA says the measurement was not taken.",
            .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 6)})
        For Each c In ChartCatalog.Spa
            _picker.Items.Add(c.Title)
        Next
        AddHandler _picker.SelectionChanged, Sub() ShowChart(_picker.SelectedIndex)
        head.Children.Add(_picker)
        head.Children.Add(_hint)
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

        Dim split As New Grid()
        split.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(1, GridUnitType.Star)})
        split.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(1.2, GridUnitType.Star)})
        split.Children.Add(New ScrollViewer() With {
            .VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            .Content = _rows})
        Grid.SetColumn(_sheet, 1)
        split.Children.Add(_sheet)
        root.Children.Add(split)

        AddHandler _sheet.BoxChanged, Sub() Restate()

        Content = root
        If ChartCatalog.Spa.Length > 0 Then _picker.SelectedIndex = 0
    End Sub

    ' ---------------------------------------------------------- building

    Private Sub ShowChart(index As Integer)
        If index < 0 OrElse index >= ChartCatalog.Spa.Length Then Return
        ' before a single row is thrown away
        Remember()
        _current = ChartCatalog.Spa(index)
        _spa = ChartCatalog.SpaSheetFor(_current.Key)
        _hint.Text = If(_spa.Hint, "")

        _boxes.Clear()
        _picks.Clear()
        _rows.Children.Clear()

        _building = True
        Try
            ' the chart's own dimensions, and the keys with no line to
            ' sit on
            For Each d In _current.Dims
                _boxes.Add(New ChartBox(d))
            Next
            For Each e In _current.Extra
                _boxes.Add(New ChartBox(e))
            Next
            For Each b In _boxes
                _rows.Children.Add(MakeRow(b))
            Next

            AddGroup("Corners")
            For Each corner In Corners()
                AddCorner(corner)
            Next

            AddGroup("The other outline, and the cover")
            AddPick("mode")
            AddPick("second")
            AddPick("method")
            AddBoxRow(New ChartBox(ChartCatalog.SpaCoverLap))
            For Each k In Second()
                AddBoxRow(New ChartBox(k))
            Next
            AddPick("autohinge")
            AddPick("grade")
            AddPick("taper")
            Restore()
        Finally
            _building = False
        End Try

        _sheet.Show(_current.Strokes, _current.Marks, _boxes)
        Restate()
    End Sub

    ''' <summary>Keep what is typed and what is picked before the rows
    ''' are rebuilt. An emptied box is FORGOTTEN rather than kept at
    ''' "", so clearing one and coming back does not bring it
    ''' back.</summary>
    Private Sub Remember()
        For Each b In _boxes
            If b.IsFilled Then
                _typed(b.Key) = b.Text
            Else
                _typed.Remove(b.Key)
            End If
        Next
        For Each key In _picks.Keys
            _picked(key) = Picked(key)
        Next
    End Sub

    ''' <summary>Put back what this shape carries a box for. Every
    ''' other key waits: the rectangle's overalls are w2/l2 and the
    ''' octagon's are b2/a2, so a key the next sheet does not have is
    ''' not a key it lost.</summary>
    Private Sub Restore()
        For Each b In _boxes
            Dim v As String = Nothing
            If _typed.TryGetValue(b.Key, v) Then b.Text = v
        Next
    End Sub

    ''' <summary>Put a rebuilt dropdown back on the word it was left
    ''' on -- by the WORD and not the row number, because two shapes
    ''' need not offer the same choices in the same order.</summary>
    Private Sub Reselect(combo As ComboBox, slot As String)
        Dim was As String = Nothing
        If Not _picked.TryGetValue(slot, was) Then Return
        If String.IsNullOrEmpty(was) Then Return
        Dim i = combo.Items.IndexOf(was)
        If i > 0 Then combo.SelectedIndex = i
    End Sub

    Private Function Corners() As ChartCatalog.SpaCornerRow()
        If _spa.Corners Is Nothing Then Return New ChartCatalog.SpaCornerRow() {}
        Return _spa.Corners
    End Function

    Private Function Second() As ChartCatalog.ListKey()
        If _spa.Second Is Nothing Then Return New ChartCatalog.ListKey() {}
        Return _spa.Second
    End Function

    Private Sub AddGroup(title As String)
        _rows.Children.Add(New TextBlock() With {
            .Text = title, .FontWeight = FontWeights.Bold,
            .Margin = New Thickness(0, 10, 0, 4)})
    End Sub

    ''' <summary>A row for a box that is already in the list.</summary>
    Private Sub AddBoxRow(box As ChartBox)
        _boxes.Add(box)
        _rows.Children.Add(MakeRow(box))
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

    ''' <summary>One list question. Left on "(ask)" it sends nothing at
    ''' all and SPA asks, which is the same answer as an empty box and is
    ''' why the first option is never a value.</summary>
    Private Sub AddPick(key As String)
        For Each q In ChartCatalog.SpaLists
            If q.Key <> key Then Continue For
            Dim combo As New ComboBox() With {.Width = 120, .SelectedIndex = 0}
            For Each o In q.Options
                combo.Items.Add(o)
            Next
            Reselect(combo, key)
            AddHandler combo.SelectionChanged, Sub() Restate()
            _picks(key) = combo

            Dim row As New DockPanel() With {
                .Margin = New Thickness(0, 2, 0, 2)}
            DockPanel.SetDock(combo, Dock.Right)
            row.Children.Add(combo)
            row.Children.Add(New TextBlock() With {
                .Text = q.Label, .ToolTip = q.Label,
                .TextTrimming = TextTrimming.CharacterEllipsis,
                .VerticalAlignment = VerticalAlignment.Center,
                .Margin = New Thickness(34, 0, 8, 0)})
            _rows.Children.Add(row)
            Return
        Next
    End Sub

    ''' <summary>
    ''' One corner: a treatment, and the size the treatment carries.
    '''
    ''' The size box is always shown rather than appearing with the
    ''' treatment. A box that comes and goes as a dropdown moves is a box
    ''' whose contents you cannot trust to still be there, and the wire
    ''' withholds a size on a treatment that takes none anyway.
    ''' </summary>
    Private Sub AddCorner(corner As ChartCatalog.SpaCornerRow)
        Dim combo As New ComboBox() With {.Width = 120, .SelectedIndex = 0}
        For Each t In ChartCatalog.SpaTreatments
            combo.Items.Add(t)
        Next
        Reselect(combo, corner.Stem & "-ty")
        AddHandler combo.SelectionChanged, Sub() Restate()
        _picks(corner.Stem & "-ty") = combo

        Dim row As New DockPanel() With {.Margin = New Thickness(0, 2, 0, 2)}
        DockPanel.SetDock(combo, Dock.Right)
        row.Children.Add(combo)
        row.Children.Add(New TextBlock() With {
            .Text = corner.Label, .ToolTip = corner.Label,
            .TextTrimming = TextTrimming.CharacterEllipsis,
            .VerticalAlignment = VerticalAlignment.Center,
            .Margin = New Thickness(34, 0, 8, 0)})
        _rows.Children.Add(row)

        AddBoxRow(New ChartBox(New ChartCatalog.ListKey(
            corner.Stem & "-sz", corner.Label & " - size")))
    End Sub

    ' -------------------------------------------------------- the state

    Private Sub Restate()
        If _building OrElse _current.Key Is Nothing Then Return
        Dim state = FormWire.Line(LiveBoxes(), NaBad())
        _state.Text = state.Text
        _state.Foreground = If(state.Ready, SystemColors.GrayTextBrush,
                               Brushes.OrangeRed)
        _draw.IsEnabled = state.Ready
        _recall.IsEnabled = HasStored()
    End Sub

    ''' <summary>Clear means clear: what is remembered across a
    ''' rebuild goes with the boxes, or the next shape would put it
    ''' all back.</summary>
    Private Sub ClearSheet()
        For Each b In _boxes
            b.Text = ""
        Next
        For Each combo In _picks.Values
            combo.SelectedIndex = 0
        Next
        _typed.Clear()
        _picked.Clear()
        Restate()
    End Sub

    ' -------------------------------------------------------- remembering

    Private Function HasStored() As Boolean
        If _current.Key Is Nothing Then Return False
        Return RecallStore.Read(RecallStore.SpaKey, _current.Key).Count > 0
    End Function

    Private Sub Recall()
        If _current.Key Is Nothing Then Return
        Dim had = RecallStore.Read(RecallStore.SpaKey, _current.Key)
        ' the empty LIVE boxes: lzs:recall's own set
        For Each b In LiveBoxes()
            If b.IsFilled Then Continue For
            Dim v As String = Nothing
            If had.TryGetValue(b.Key, v) Then b.Text = v
        Next
        Restate()
    End Sub

    ' ------------------------------------------------------------- the run

    ''' <summary>What is chosen on a dropdown, or "" while it is on
    ''' "(ask)" -- which sends nothing, so SPA asks.</summary>
    Private Function Picked(key As String) As String
        Dim combo As ComboBox = Nothing
        If Not _picks.TryGetValue(key, combo) Then Return ""
        If combo.SelectedIndex <= 0 Then Return ""
        Return CStr(combo.SelectedItem)
    End Function

    ''' <summary>
    ''' The boxes this run will actually ask about.
    '''
    ''' <para>lzs:livekeys, and the half of it the palette can answer
    ''' without keeping a second copy of a rule: a corner SIZE box is
    ''' live only when its own dropdown takes a size. Counting one
    ''' that is not, or holding Draw back over what is typed in it,
    ''' would both be untrue of a box that cannot travel.</para>
    '''
    ''' <para>The other half is lzs:dead -- what the grade, the second
    ''' outline and the method close off -- which is a rule and stays
    ''' in the Lisp.</para>
    ''' </summary>
    Private Function LiveBoxes() As List(Of ChartBox)
        Dim out As New List(Of ChartBox)
        For Each b In _boxes
            If Not b.Key.EndsWith("-sz", StringComparison.Ordinal) Then
                out.Add(b)
                Continue For
            End If
            Dim stem = b.Key.Substring(0, b.Key.Length - 3)
            If Not _picks.ContainsKey(stem & "-ty") OrElse
               Sized(Picked(stem & "-ty")) Then out.Add(b)
        Next
        Return out
    End Function

    ''' <summary>Is this box answered NA?</summary>
    Private Shared Function IsNa(b As ChartBox) As Boolean
        Return String.Equals(b.Text.Trim(), "NA",
                             StringComparison.OrdinalIgnoreCase)
    End Function

    ''' <summary>
    ''' The live boxes reading NA on a key SPA has no NA for.
    '''
    ''' <para>lzs:nabad, and the one rule on this sheet that could not
    ''' be left to the wire. The wire reads NA as nil, which IS the
    ''' answer on some keys and is a fault on the rest: SPA marks its
    ''' measurement items REQ / SUG / NAX, and "a REQ item fed a nil
    ''' is not asked again -- spa:askseqb stores the nil straight into
    ''' its answers and the flow then does arithmetic on it, which in
    ''' AutoLISP is an error, not a fallback". lzs:keyanswer demotes
    ''' those to an empty box; so does Run, and the state line says
    ''' so rather than dropping them without a word.</para>
    '''
    ''' <para>WHICH keys take one is lzs:*naok*, a table, and it comes
    ''' through the catalog with the rest of the sheet -- there is no
    ''' rule here beyond looking in it.</para>
    ''' </summary>
    Private Function NaBad() As List(Of ChartBox)
        Dim out As New List(Of ChartBox)
        For Each b In LiveBoxes()
            If IsNa(b) AndAlso Not _spa.TakesNa(b.Key) Then out.Add(b)
        Next
        Return out
    End Function

    ''' <summary>Does this treatment carry a size? lzs:sized, as
    ''' words.</summary>
    Private Shared Function Sized(treatment As String) As Boolean
        For Each t In ChartCatalog.SpaSizedTreatments
            If String.Equals(t, treatment, StringComparison.Ordinal) Then
                Return True
            End If
        Next
        Return False
    End Function

    Private Sub Run()
        If _current.Key Is Nothing Then Return

        Dim literals As New List(Of String)
        Dim measures As New List(Of String)
        literals.Add(LispBridge.StrPair("shape", _current.Shape))
        For Each q In ChartCatalog.SpaLists
            Dim v = Picked(q.Key)
            If v.Length > 0 Then literals.Add(LispBridge.StrPair(q.Key, v))
        Next

        ' A corner's SIZE travels only when its treatment takes one --
        ' lzs:cornerpairs' rule.  A size against a 90 would be an answer
        ' to a question SPA never asks.
        Dim sizedStems As New HashSet(Of String)
        For Each corner In Corners()
            Dim ty = Picked(corner.Stem & "-ty")
            If ty.Length = 0 Then Continue For
            literals.Add(LispBridge.StrPair(corner.Stem & "-ty", ty))
            If Sized(ty) Then sizedStems.Add(corner.Stem & "-sz")
        Next

        For Each b In _boxes
            If Not b.IsFilled Then Continue For
            If b.Key.EndsWith("-sz", StringComparison.Ordinal) AndAlso
               Not sizedStems.Contains(b.Key) Then Continue For
            ' lzs:keyanswer: an NA on a key SPA has no NA for is DEMOTED
            ' to an empty box. Sending it would put a nil into a REQ
            ' item, which SPA does not ask again and then does
            ' arithmetic on -- an error rather than a fallback. The
            ' state line has already named it and held Draw back; this
            ' is the same rule at the wire, so the two cannot disagree.
            If IsNa(b) AndAlso Not _spa.TakesNa(b.Key) Then Continue For
            measures.Add(LispBridge.MeasurePair(b.Key, b.Text))
        Next

        RecallStore.Save(RecallStore.SpaKey, _current.Key, _boxes)
        LispBridge.Send(AcadApp.DocumentManager.MdiActiveDocument,
                        LispBridge.BuildFormCall("spa:run-with-answers",
                                                 literals, measures))
    End Sub

End Class
