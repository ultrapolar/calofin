Imports System.Collections.Generic
Imports System.Windows
Imports System.Windows.Controls
Imports System.Windows.Media
Imports AcadApp = Autodesk.AutoCAD.ApplicationServices.Application

''' <summary>
''' The step sheet: say how many steps, then fill in the drawing built
''' for that count.
'''
''' <para>LAZSTEP's argument, on the palette. A flight of steps has no
''' fixed chart -- the sheet IS the count -- so ChartCatalog carries one
''' per routine per count, up to the ceiling LAZSTEP itself will draw.
''' Nothing here builds a drawing; it picks one that was generated from
''' lzt:chart.</para>
'''
''' <para>One rule is mirrored from lzt:form rather than left to the
''' wire, and it is the only one: <b>NA at a tread counts as an empty
''' box</b>. NA is what ENDS a run, so a tread answered NA would stop
''' the flight short of the count that built this very drawing -- the
''' sheet would draw four steps and the routine three. Every other
''' answer travels exactly as typed.</para>
''' </summary>
Public Class StepFormView
    Inherits UserControl

    Private ReadOnly _routine As New ComboBox()
    Private ReadOnly _count As New ComboBox()
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
        .ToolTip = "Put the last accepted sheet for this routine AND this " &
                   "step count back into the empty boxes"}

    Private ReadOnly _boxes As New List(Of ChartBox)
    Private _current As ChartCatalog.StepChart

    Public Sub New()
        Dim root As New DockPanel() With {.Margin = New Thickness(8)}

        Dim head As New StackPanel()
        head.Children.Add(New TextBlock() With {
            .Text = "Pick the flight and how many steps it has. The " &
                    "drawing is built for that count; fill in what you " &
                    "have and the routine asks for the rest.",
            .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 6)})
        head.Children.Add(New TextBlock() With {
            .Text = "A box takes 24, or a feet-and-inches spelling - both " &
                    "read. NA says the measurement was not taken - though " &
                    "not on a tread, where it would end the flight early.",
            .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 6)})

        For Each r In ChartCatalog.StepRoutines
            _routine.Items.Add(r.Title)
        Next
        AddHandler _routine.SelectionChanged, Sub() ShowSheet()
        head.Children.Add(_routine)

        ' 1 to lzt:*max-steps*.  Past the ceiling LAZSTEP refuses to draw
        ' at all -- a taller dialog will not open -- so the palette
        ' offers exactly the counts a sheet exists for rather than
        ' letting one be asked for and answered with nothing.
        For n = 1 To ChartCatalog.MaxSteps
            _count.Items.Add(n.ToString() &
                             FormWire.Plural(n, " step", " steps"))
        Next
        AddHandler _count.SelectionChanged, Sub() ShowSheet()
        head.Children.Add(_count)
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
            .Width = New GridLength(1.3, GridUnitType.Star)})
        split.Children.Add(New ScrollViewer() With {
            .VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            .Content = _rows})
        Grid.SetColumn(_sheet, 1)
        split.Children.Add(_sheet)
        root.Children.Add(split)

        AddHandler _sheet.BoxChanged, Sub() Restate()

        Content = root
        _routine.SelectedIndex = 0
        ' three steps is the common flight, but never past the ceiling:
        ' a SelectedIndex the list does not have is -1, and the form
        ' would open with no sheet at all
        _count.SelectedIndex = If(ChartCatalog.MaxSteps >= 3, 2, 0)
    End Sub

    Private ReadOnly Property Routine As ChartCatalog.StepRoutine
        Get
            Dim i = _routine.SelectedIndex
            If i < 0 OrElse i >= ChartCatalog.StepRoutines.Length Then
                Return Nothing
            End If
            Return ChartCatalog.StepRoutines(i)
        End Get
    End Property

    Private ReadOnly Property Steps As Integer
        Get
            Return _count.SelectedIndex + 1
        End Get
    End Property

    ''' <summary>The slot a sheet is remembered under: lzt:recall-slot's
    ''' "TYPE-count". The count is part of it because a three-step sheet
    ''' recalled onto a five-step drawing would put numbers against
    ''' treads they were never measured on.</summary>
    Private ReadOnly Property Slot As String
        Get
            Return Routine.Command & "-" & Steps.ToString()
        End Get
    End Property

    Private Sub ShowSheet()
        If Routine.Command Is Nothing OrElse Steps < 1 Then Return
        _current = ChartCatalog.StepChartFor(Routine.Command, Steps)
        _boxes.Clear()
        _rows.Children.Clear()
        If _current.Routine Is Nothing Then
            _sheet.Show(Nothing, Nothing, _boxes)
            _state.Text = "No sheet for that count."
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
        Finally
            _building = False
        End Try
        _sheet.Show(_current.Strokes, New ChartCatalog.Mark() {}, _boxes)
        Restate()
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

    ''' <summary>True while the rows are being built. Each binding
    ''' fires TextChanged as it first fills its editor, and restating on
    ''' every one of those asks Lisp about a sheet nobody has typed in
    ''' yet.</summary>
    Private _building As Boolean

    Private Sub Restate()
        If _building Then Return
        If _current.Routine Is Nothing Then Return
        Dim state = FormWire.Line(_boxes)
        _state.Text = state.Text
        _state.Foreground = If(state.Ready, SystemColors.GrayTextBrush,
                               Brushes.OrangeRed)
        _draw.IsEnabled = state.Ready
        _recall.IsEnabled = HasStored()
    End Sub

    Private Sub ClearSheet()
        For Each b In _boxes
            b.Text = ""
        Next
        Restate()
    End Sub

    Private Function HasStored() As Boolean
        If _current.Routine Is Nothing Then Return False
        Return RecallStore.Read(RecallStore.StepKey, Slot).Count > 0
    End Function

    Private Sub Recall()
        If _current.Routine Is Nothing Then Return
        Dim had = RecallStore.Read(RecallStore.StepKey, Slot)
        For Each b In _boxes
            If b.IsFilled Then Continue For
            Dim v As String = Nothing
            If had.TryGetValue(b.Key, v) Then b.Text = v
        Next
        Restate()
    End Sub

    ''' <summary>Is this key one of the treads? lzt:treadkey, which
    ''' recognises them by their stem because they are asked in a loop
    ''' and never listed twice.</summary>
    Friend Shared Function IsTread(key As String) As Boolean
        Return key IsNot Nothing AndAlso
               key.StartsWith("tread", StringComparison.Ordinal)
    End Function

    ''' <summary>
    ''' Hand the sheet to the routine.
    '''
    ''' The COUNT is a literal and always travels -- it is the drawing
    ''' this sheet was built for, and the routine has to be told the same
    ''' number. Everything typed is a measure, except a tread answered
    ''' NA, which is withheld: NA is what ends a run, and the flight
    ''' would stop short of the count on the sheet in front of you.
    ''' </summary>
    Private Sub Run()
        If _current.Routine Is Nothing Then Return

        Dim literals As New List(Of String)
        Dim measures As New List(Of String)
        literals.Add(LispBridge.Pair("steps", Steps.ToString()))
        For Each b In _boxes
            If Not b.IsFilled Then Continue For
            If IsTread(b.Key) AndAlso
               b.Text.Trim().ToUpperInvariant() = "NA" Then Continue For
            measures.Add(LispBridge.MeasurePair(b.Key, b.Text))
        Next

        RecallStore.Save(RecallStore.StepKey, Slot, _boxes)
        LispBridge.Send(AcadApp.DocumentManager.MdiActiveDocument,
                        LispBridge.BuildFormCall(Routine.EntryPoint,
                                                 literals, measures))
    End Sub

End Class
