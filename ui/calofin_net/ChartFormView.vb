Imports System.Collections.Generic
Imports System.ComponentModel
Imports System.Windows
Imports System.Windows.Controls
Imports System.Windows.Media
Imports Autodesk.AutoCAD.DatabaseServices
Imports Autodesk.AutoCAD.Runtime
Imports Microsoft.Win32
Imports AcadApp = Autodesk.AutoCAD.ApplicationServices.Application

''' <summary>
''' One measurement box on a chart.
'''
''' <para>It holds TEXT and never a number. That is the whole of the
''' palette's part in reading a measurement: the text goes to
''' calofin.lsp as typed, and AutoCAD's own distof turns it into a
''' distance. A box that held a Double could not carry the difference
''' between empty, NA and 6'-3", which is the difference the whole form
''' rests on.</para>
''' </summary>
Public Class ChartBox
    Implements INotifyPropertyChanged

    Public Event PropertyChanged As PropertyChangedEventHandler _
        Implements INotifyPropertyChanged.PropertyChanged

    ''' <summary>The key the routine reads this answer under.</summary>
    Public ReadOnly Property Key As String
    ''' <summary>The letter the sheet PRINTS, which is not always the
    ''' key: a rectangle's B is the side and an oval's B is the tip-to-tip
    ''' total. A complaint has to name the letter, or the drafter hunts
    ''' the paper for something that is not on it.</summary>
    Public ReadOnly Property Letter As String
    Public ReadOnly Property Label As String
    ''' <summary>Where the box sits, in the chart's own 0..1000 space.
    ''' Zero for a key with no line on the sheet, which is asked in the
    ''' column instead.</summary>
    Public ReadOnly Property X As Double
    Public ReadOnly Property Y As Double
    Public ReadOnly Property OnChart As Boolean

    Private _text As String = ""

    Public Property Text As String
        Get
            Return _text
        End Get
        Set(v As String)
            If _text = v Then Return
            _text = If(v, "")
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Text"))
        End Set
    End Property

    Public ReadOnly Property IsFilled As Boolean
        Get
            Return Not String.IsNullOrWhiteSpace(_text)
        End Get
    End Property

    Public Sub New(d As ChartCatalog.ChartDim)
        Me.Key = d.Key
        Me.Letter = d.Letter
        Me.Label = d.Label
        Me.X = d.MidX
        Me.Y = d.MidY
        Me.OnChart = True
    End Sub

    Public Sub New(k As ChartCatalog.ListKey)
        Me.Key = k.Key
        Me.Letter = ""
        Me.Label = k.Label
        Me.OnChart = False
    End Sub

End Class


''' <summary>
''' The last accepted sheet for one chart, put back into the EMPTY boxes.
'''
''' <para>Stored where and how the DCL forms store it -- one registry
''' value per chart, "key=typed;key=typed" -- so a sheet filled in on
''' LAZFORM comes back on the palette and the other way round. A value
''' carrying ";" or "=" is dropped rather than written back wrong;
''' nothing a box legitimately holds contains either.</para>
'''
''' <para>Only the empty boxes, so recall can never overwrite a number
''' just typed and pressing it twice does nothing the first press did
''' not. And never a default: pre-filling a sheet on open would put the
''' last pool's numbers on this pool, and a wrong number that looks
''' answered is worse than an empty box, because the state line would
''' then call the sheet finished.</para>
''' </summary>
Public NotInheritable Class RecallStore

    Private Sub New()
    End Sub

    ''' <summary>lzf:*recallkey*, lzs:*recallkey*, lzt:*recallkey*.</summary>
    Public Const PoolKey As String =
        "HKEY_CURRENT_USER\Software\Calofin\LazForm"
    Public Const SpaKey As String =
        "HKEY_CURRENT_USER\Software\Calofin\LazSpa"
    Public Const StepKey As String =
        "HKEY_CURRENT_USER\Software\Calofin\LazStep"

    ''' <summary>A sheet as one string. Anything holding a separator is
    ''' left out rather than written back wrong -- cal:kvpack's rule, and
    ''' silently losing one entry beats a sheet that reads back
    ''' scrambled.</summary>
    Public Shared Function Pack(boxes As IEnumerable(Of ChartBox)) As String
        Dim parts As New List(Of String)
        For Each b In boxes
            Dim v = b.Text
            If String.IsNullOrWhiteSpace(v) Then Continue For
            If v.Contains(";") OrElse v.Contains("=") Then Continue For
            If b.Key.Contains(";") OrElse b.Key.Contains("=") Then Continue For
            parts.Add(b.Key & "=" & v)
        Next
        Return String.Join(";", parts)
    End Function

    Public Shared Function Unpack(s As String) As Dictionary(Of String, String)
        Dim out As New Dictionary(Of String, String)
        If String.IsNullOrEmpty(s) Then Return out
        For Each part In s.Split(";"c)
            Dim cut = part.IndexOf("="c)
            If cut <= 0 Then Continue For
            Dim k = part.Substring(0, cut)
            If Not out.ContainsKey(k) Then out(k) = part.Substring(cut + 1)
        Next
        Return out
    End Function

    Public Shared Function Read(keyPath As String,
                                slot As String) As Dictionary(Of String, String)
        Try
            Dim v = TryCast(Registry.GetValue(keyPath, slot, Nothing), String)
            Return Unpack(If(v, ""))
        Catch
            Return New Dictionary(Of String, String)
        End Try
    End Function

    Public Shared Sub Save(keyPath As String, slot As String,
                           boxes As IEnumerable(Of ChartBox))
        Dim packed = Pack(boxes)
        If packed.Length = 0 Then Return
        Try
            Registry.SetValue(keyPath, slot, packed, RegistryValueKind.String)
        Catch
        End Try
    End Sub

End Class


''' <summary>
''' The state line, and the one question the palette cannot answer.
'''
''' <para>Shared by every chart form, which is phase 4 of ui/UI-PLAN.md
''' ("one form kit") arriving on this surface. The DCL forms had three
''' copies of this reasoning and the mirror's swap map is what made them
''' one; here it is one class two forms call.</para>
''' </summary>
Friend NotInheritable Class FormWire

    Private Sub New()
    End Sub

    ''' <summary>What the line says, and whether the form may run.</summary>
    Friend Structure State
        Friend ReadOnly Text As String
        Friend ReadOnly Ready As Boolean

        Friend Sub New(text As String, ready As Boolean)
            Me.Text = text
            Me.Ready = ready
        End Sub
    End Structure

    ''' <summary>
    ''' The keys the wire will drop, asked of calofin.lsp.
    '''
    ''' The palette cannot answer this itself -- it does not read a
    ''' measurement any more, which is the point -- and it must not
    ''' guess: the line NAMES boxes, and a line that named a box the wire
    ''' would happily accept is worse than no line. When the glue is not
    ''' loaded nothing is reported, which leaves a form exactly as honest
    ''' as it was before the state line existed.
    '''
    ''' The sheet travels as one packed string rather than an alist:
    ''' marshalling dotted pairs through a ResultBuffer is the fiddly,
    ''' fails-at-runtime half of this boundary, and "key=typed;key=typed"
    ''' is a format the recall store already uses.
    ''' </summary>
    Friend Shared Function Unreadable(
            filled As IEnumerable(Of ChartBox)) As HashSet(Of String)
        Dim out As New HashSet(Of String)
        Dim packed = RecallStore.Pack(filled)
        If packed.Length = 0 Then Return out
        Try
            Dim args As New ResultBuffer(
                New TypedValue(CInt(LispDataType.Text),
                               "calofin:unreadable-str"),
                New TypedValue(CInt(LispDataType.Text), packed))
            Dim res = AcadApp.Invoke(args)
            If res Is Nothing Then Return out
            For Each tv As TypedValue In res
                If tv.TypeCode <> CInt(LispDataType.Text) Then Continue For
                Dim s = TryCast(tv.Value, String)
                If String.IsNullOrEmpty(s) Then Continue For
                For Each k In s.Split(";"c)
                    If k.Length > 0 Then out.Add(k)
                Next
            Next
        Catch
            out.Clear()
        End Try
        Return out
    End Function

    ''' <summary>
    ''' The line, for a sheet of boxes.
    '''
    ''' Three states in the order they matter. A box that will not read
    ''' is named FIRST and stops the form, because that is the failure
    ''' the drafter cannot see: the chart goes on showing what was typed
    ''' while the wire drops it. Otherwise the line is the hand-off --
    ''' how much of the sheet is filled and what the routine will still
    ''' ask for.
    ''' </summary>
    Friend Shared Function Line(boxes As IEnumerable(Of ChartBox)) As State
        Dim all As New List(Of ChartBox)
        Dim filled As New List(Of ChartBox)
        For Each b In boxes
            all.Add(b)
            If b.IsFilled Then filled.Add(b)
        Next

        Dim bad = Unreadable(filled)
        If bad.Count > 0 Then
            Dim letters As New List(Of String)
            For Each b In all
                If bad.Contains(b.Key) Then
                    ' the LETTER the sheet prints, never the key: a
                    ' complaint about "c2" sends the drafter hunting the
                    ' paper for something that is not on it
                    letters.Add(If(b.Letter.Length > 0, b.Letter, b.Key))
                End If
            Next
            Return New State(
                Plural(letters.Count, "Box ", "Boxes ") & AndJoin(letters) &
                " cannot be read as a measurement. Fix or clear " &
                Plural(letters.Count, "it", "them") &
                " - as typed, the answer would be dropped and the " &
                "question asked again at the command line.", False)
        End If

        Dim asking = all.Count - filled.Count
        If all.Count = 0 Then Return New State("", False)
        If asking = 0 Then
            Return New State(
                "All " & all.Count.ToString() & " boxes filled in. " &
                "Nothing left to ask but the insertion point.", True)
        End If
        Return New State(
            filled.Count.ToString() & " of " & all.Count.ToString() &
            " filled in. The routine will ask at the command line for " &
            "the other " & asking.ToString() & ".", True)
    End Function

    ''' <summary>cal:plural: a line reading "all 1 boxes" is a bug in the
    ''' form, whatever it is reporting.</summary>
    Friend Shared Function Plural(n As Integer, one As String,
                                  many As String) As String
        Return If(n = 1, one, many)
    End Function

    ''' <summary>cal:andjoin: "B", "B and L", "B, L and H".</summary>
    Friend Shared Function AndJoin(items As List(Of String)) As String
        If items.Count = 0 Then Return ""
        If items.Count = 1 Then Return items(0)
        Dim head = String.Join(", ", items.GetRange(0, items.Count - 1))
        Return head & " and " & items(items.Count - 1)
    End Function

End Class


''' <summary>
''' A chart, drawn from its own vectors, with a box on every dimension.
'''
''' <para>This is what replaces the photograph. The palette used to show
''' a PNG of a chart and float boxes over it at fractions of the image --
''' fractions a human had to nudge against the artwork, and which the
''' READMEs admitted were "seeded estimates". Drawn from
''' ChartCatalog's polylines, a box needs no position of its own: it
''' belongs at the midpoint of the line it measures, which the geometry
''' already knows.</para>
'''
''' <para>The chart's space is 0..1000 with y DOWN, the way an image tile
''' counts pixels, so the transform is one uniform scale and a
''' centring offset. Redrawn on resize, because the whole point of
''' vectors is that they do not blur.</para>
''' </summary>
Public Class ChartSheet
    Inherits Grid

    Private ReadOnly _canvas As New Canvas()
    Private _strokes As ChartCatalog.Stroke() = New ChartCatalog.Stroke() {}
    Private _marks As ChartCatalog.Mark() = New ChartCatalog.Mark() {}
    Private ReadOnly _boxes As New List(Of ChartBox)

    ''' <summary>True while Paint is rebuilding.
    '''
    ''' A binding fires TextChanged when it first sets a box's text, and
    ''' Paint rebuilds every editor on every resize -- so without this,
    ''' dragging the palette's edge would raise BoxChanged once per box
    ''' per frame, and each one of those asks Lisp what the sheet cannot
    ''' read. A resize changes nothing the drafter typed.</summary>
    Private _painting As Boolean

    Public Event BoxChanged As EventHandler

    Public Sub New()
        Children.Add(_canvas)
        ClipToBounds = True
        AddHandler SizeChanged, Sub() Paint()
    End Sub

    Private Sub Changed()
        If _painting Then Return
        RaiseEvent BoxChanged(Me, EventArgs.Empty)
    End Sub

    Public Sub Show(strokes As ChartCatalog.Stroke(),
                    marks As ChartCatalog.Mark(),
                    boxes As IEnumerable(Of ChartBox))
        _strokes = If(strokes, New ChartCatalog.Stroke() {})
        _marks = If(marks, New ChartCatalog.Mark() {})
        _boxes.Clear()
        For Each b In boxes
            If b.OnChart Then _boxes.Add(b)
        Next
        Paint()
    End Sub

    ''' <summary>
    ''' Draw the outline, the corner letters and the boxes.
    '''
    ''' Everything is rebuilt rather than moved: a chart is a few hundred
    ''' segments and a dozen boxes, the palette is resized by hand and
    ''' not per frame, and a rebuild cannot leave a stale line behind
    ''' from the sheet before.
    ''' </summary>
    Private Sub Paint()
        _canvas.Children.Clear()
        Dim w = ActualWidth, h = ActualHeight
        If w <= 0 OrElse h <= 0 Then Return
        _painting = True
        Try
            Repaint(w, h)
        Finally
            _painting = False
        End Try
    End Sub

    ''' <summary>The drawing itself, once Paint has the size and has
    ''' hushed the change notifications.</summary>
    Private Sub Repaint(w As Double, h As Double)
        Dim scale = Math.Min(w, h) / ChartCatalog.Span
        If scale <= 0 Then Return
        Dim ox = (w - ChartCatalog.Span * scale) / 2
        Dim oy = (h - ChartCatalog.Span * scale) / 2

        Dim ink = TryCast(TryFindResource(SystemColors.ControlTextBrushKey),
                          Brush)
        If ink Is Nothing Then ink = Brushes.Black

        For Each s In _strokes
            Dim pts = s.Points
            If pts Is Nothing OrElse pts.Length < 4 Then Continue For
            Dim figure As New PathFigure() With {
                .StartPoint = New Point(ox + pts(0) * scale,
                                        oy + pts(1) * scale)}
            Dim i = 2
            While i + 1 < pts.Length
                figure.Segments.Add(New LineSegment(
                    New Point(ox + pts(i) * scale, oy + pts(i + 1) * scale),
                    True))
                i += 2
            End While
            Dim geo As New PathGeometry()
            geo.Figures.Add(figure)
            ' Shapes.Path, spelled through the namespace: a bare Path
            ' resolves to nothing here, and System.IO has one too.
            _canvas.Children.Add(New Shapes.Path() With {
                .Data = geo, .Stroke = ink, .StrokeThickness = 1.2})
        Next

        For Each m In _marks
            Dim t As New TextBlock() With {
                .Text = m.Letter, .FontWeight = FontWeights.Bold,
                .Foreground = ink}
            Canvas.SetLeft(t, ox + m.X * scale - 5)
            Canvas.SetTop(t, oy + m.Y * scale - 9)
            _canvas.Children.Add(t)
        Next

        For Each b In _boxes
            Dim box = b
            Dim editor As New TextBox() With {
                .Width = 52, .TextAlignment = TextAlignment.Center,
                .Tag = box,
                .ToolTip = box.Letter & " - " & box.Label,
                .Background = New SolidColorBrush(
                    Color.FromArgb(235, 255, 255, 255)),
                .Foreground = Brushes.Black}
            Bind(editor, box)
            ' through a method, not inline: VB does not allow
            ' RaiseEvent inside a lambda expression
            AddHandler editor.TextChanged, Sub() Changed()

            Dim caption As New TextBlock() With {
                .Text = box.Letter, .FontWeight = FontWeights.Bold,
                .Foreground = ink}

            editor.Measure(New Size(Double.PositiveInfinity,
                                    Double.PositiveInfinity))
            Dim bw = If(editor.DesiredSize.Width > 0,
                        editor.DesiredSize.Width, 52.0)
            Dim bh = If(editor.DesiredSize.Height > 0,
                        editor.DesiredSize.Height, 22.0)
            Canvas.SetLeft(editor, ox + box.X * scale - bw / 2)
            Canvas.SetTop(editor, oy + box.Y * scale - bh / 2)
            Canvas.SetLeft(caption, ox + box.X * scale - bw / 2 - 12)
            Canvas.SetTop(caption, oy + box.Y * scale - bh / 2)
            _canvas.Children.Add(caption)
            _canvas.Children.Add(editor)
        Next
    End Sub

    Friend Shared Sub Bind(box As TextBox, source As ChartBox)
        Dim b As New Data.Binding("Text") With {
            .Source = source, .Mode = Data.BindingMode.TwoWay,
            .UpdateSourceTrigger = Data.UpdateSourceTrigger.PropertyChanged}
        box.SetBinding(TextBox.TextProperty, b)
    End Sub

End Class


''' <summary>
''' A whole chart form: pick a sheet, fill it in, draw from it.
'''
''' <para>One class serves POOL and SPA, because ChartCatalog gives them
''' the same shape -- which is phase 4 of ui/UI-PLAN.md ("one form kit")
''' arriving on this surface. What differs is the sheet list, the entry
''' point and where the recall store lives, and those are constructor
''' arguments.</para>
'''
''' <para>The state line is the phase 3 feature, and it holds Draw back
''' the way LAZFORM's holds Insert back. It reports what the WIRE will
''' do rather than second-guessing it: the boxes it calls unreadable are
''' the ones calofin:unreadable names, asked over the same packed string
''' the recall store uses. A state line that disagreed with the wire
''' would be worse than none.</para>
''' </summary>
Public Class ChartFormView
    Inherits UserControl

    Private ReadOnly _charts As ChartCatalog.Chart()
    Private ReadOnly _entryPoint As String
    Private ReadOnly _recallKey As String

    Private ReadOnly _picker As New ComboBox()
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
        .ToolTip = "Put the last accepted sheet for this chart back into " &
                   "the EMPTY boxes"}

    Private ReadOnly _boxes As New List(Of ChartBox)

    ''' <summary>The keyword dropdowns, by the key each answers under,
    ''' and the corner dropdowns by their row's stem. Two dictionaries
    ''' because a corner's answer is fanned out to targets and a pick's
    ''' is not.</summary>
    Private ReadOnly _picks As New Dictionary(Of String, ComboBox)
    Private ReadOnly _corners As New Dictionary(Of String, ComboBox)

    ''' <summary>POOL reads a KEYWORD here, not a yes/no, and the toggle
    ''' also decides which corner rows answer anything and whether the
    ''' cross dims are asked at all.</summary>
    Private ReadOnly _insquare As New CheckBox() With {
        .Content = "In square", .IsChecked = False,
        .VerticalAlignment = VerticalAlignment.Center,
        .Margin = New Thickness(0, 0, 12, 0),
        .ToolTip = "A pool taped square. Out of square, POOL asks for " &
                   "the diagonals and each corner in turn."}

    ''' <summary>The bottom, from lzf:*btypes*. Left on its blank row it
    ''' sends nothing and POOL asks.</summary>
    Private ReadOnly _btype As New ComboBox() With {.Width = 120}

    Private _current As ChartCatalog.Chart
    Private _pool As ChartCatalog.PoolSheet

    Public Sub New(charts As ChartCatalog.Chart(), entryPoint As String,
                   recallKey As String, hint As String)
        _charts = charts
        _entryPoint = entryPoint
        _recallKey = recallKey

        Dim root As New DockPanel() With {.Margin = New Thickness(8)}

        Dim head As New StackPanel()
        head.Children.Add(New TextBlock() With {
            .Text = hint, .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 6)})
        head.Children.Add(New TextBlock() With {
            .Text = "A box takes 24, or a feet-and-inches spelling - both " &
                    "read. NA says the measurement was not taken.",
            .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 6)})
        For Each c In charts
            _picker.Items.Add(c.Title)
        Next
        AddHandler _picker.SelectionChanged, Sub() ShowChart(_picker.SelectedIndex)
        head.Children.Add(_picker)

        ' the two questions that are about the whole sheet rather than
        ' any one box, and which change what the rest of it asks
        Dim gates As New StackPanel() With {
            .Orientation = Orientation.Horizontal,
            .Margin = New Thickness(0, 6, 0, 0)}
        AddHandler _insquare.Checked, Sub() ShowChart(_picker.SelectedIndex)
        AddHandler _insquare.Unchecked, Sub() ShowChart(_picker.SelectedIndex)
        gates.Children.Add(_insquare)
        _btype.Items.Add("")
        For Each b In ChartCatalog.PoolBottomTypes
            _btype.Items.Add(b)
        Next
        _btype.SelectedIndex = 0
        AddHandler _btype.SelectionChanged, Sub() Restate()
        gates.Children.Add(New TextBlock() With {
            .Text = "Bottom", .VerticalAlignment = VerticalAlignment.Center,
            .Margin = New Thickness(0, 0, 6, 0)})
        gates.Children.Add(_btype)
        head.Children.Add(gates)
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
        If charts.Length > 0 Then _picker.SelectedIndex = 0
    End Sub

    ''' <summary>Every box on the sheet, chart dims first and then the
    ''' keys with no line to sit on.</summary>
    Private Sub ShowChart(index As Integer)
        If index < 0 OrElse index >= _charts.Length Then Return
        _current = _charts(index)
        _pool = ChartCatalog.PoolSheetFor(_current.Key)
        _boxes.Clear()
        _picks.Clear()
        _corners.Clear()
        _rows.Children.Clear()

        _building = True
        Try
            For Each d In _current.Dims
                _boxes.Add(New ChartBox(d))
            Next
            For Each e In _current.Extra
                _boxes.Add(New ChartBox(e))
            Next
            For Each b In _boxes
                _rows.Children.Add(MakeRow(b))
            Next

            ' The questions that are not measurements.  A sheet with none
            ' of a given kind gets no heading either: an empty box headed
            ' "Corners" reads as a form that has lost them.
            AddPicks("run")
            If HasCross() Then
                AddGroup("Cross dims (corner to corner)")
                AddPicks("cross")
                For Each k In Cross()
                    AddBoxRow(New ChartBox(k))
                Next
            End If
            If CornerRows().Length > 0 Then
                AddGroup("Corners")
                For Each row In CornerRows()
                    AddCorner(row)
                Next
            End If
        Finally
            _building = False
        End Try

        _sheet.Show(_current.Strokes, _current.Marks, _boxes)
        Restate()
    End Sub

    Private Function PoolExtras() As Boolean
        Return _pool.Key IsNot Nothing
    End Function

    Private Function Cross() As ChartCatalog.ListKey()
        If Not PoolExtras() OrElse _pool.Cross Is Nothing Then
            Return New ChartCatalog.ListKey() {}
        End If
        Return _pool.Cross
    End Function

    ''' <summary>
    ''' Are the cross dims asked for at all?
    '''
    ''' They are not, in square: a cross dim is a tape run corner to
    ''' corner and it is what tells POOL how far OUT of square the pool
    ''' is. lzf:*picks* says the same thing by tying the mode dropdown to
    ''' this section -- in square there are no cross dims, so there is no
    ''' mode to pick either.
    ''' </summary>
    Private Function HasCross() As Boolean
        Return Cross().Length > 0 AndAlso Not _insquare.IsChecked.GetValueOrDefault()
    End Function

    Private Function CornerRows() As ChartCatalog.PoolCornerRow()
        If Not PoolExtras() OrElse _pool.Corners Is Nothing Then
            Return New ChartCatalog.PoolCornerRow() {}
        End If
        Return _pool.Corners
    End Function

    Private Sub AddGroup(title As String)
        _rows.Children.Add(New TextBlock() With {
            .Text = title, .FontWeight = FontWeights.Bold,
            .Margin = New Thickness(0, 10, 0, 4)})
    End Sub

    ''' <summary>A row for a box, adding it to the sheet as well.</summary>
    Private Sub AddBoxRow(box As ChartBox)
        _boxes.Add(box)
        _rows.Children.Add(MakeRow(box))
    End Sub

    ''' <summary>The keyword dropdowns of one section - lzf:*picks*'
    ''' own word for where each belongs.</summary>
    Private Sub AddPicks(section As String)
        If Not PoolExtras() OrElse _pool.Picks Is Nothing Then Return
        For Each p In _pool.Picks
            If p.Section <> section Then Continue For
            Dim combo As New ComboBox() With {.Width = 120, .SelectedIndex = 0}
            For Each o In p.Options
                combo.Items.Add(o)
            Next
            AddHandler combo.SelectionChanged, Sub() Restate()
            _picks(p.Key) = combo
            _rows.Children.Add(PickRow(p.Label, combo))
        Next
    End Sub

    Private Function PickRow(label As String,
                             combo As ComboBox) As FrameworkElement
        Dim row As New DockPanel() With {.Margin = New Thickness(0, 2, 0, 2)}
        DockPanel.SetDock(combo, Dock.Right)
        row.Children.Add(combo)
        row.Children.Add(New TextBlock() With {
            .Text = label, .ToolTip = label,
            .TextTrimming = TextTrimming.CharacterEllipsis,
            .VerticalAlignment = VerticalAlignment.Center,
            .Margin = New Thickness(34, 0, 8, 0)})
        Return row
    End Function

    ''' <summary>
    ''' One corner ROW, which is not always one corner.
    '''
    ''' What it answers depends on the in-square toggle: in square a
    ''' single row covers all four and its siblings answer nothing, out
    ''' of square each is asked for itself. The rows are all shown either
    ''' way -- which one is live is the wire's decision at Draw, and a row
    ''' that vanished as a toggle moved would take whatever was typed in
    ''' it with it.
    ''' </summary>
    Private Sub AddCorner(row As ChartCatalog.PoolCornerRow)
        Dim combo As New ComboBox() With {.Width = 120, .SelectedIndex = 0}
        For Each t In ChartCatalog.PoolTreatments
            combo.Items.Add(t)
        Next
        AddHandler combo.SelectionChanged, Sub() Restate()
        _corners(row.Stem) = combo
        _rows.Children.Add(PickRow(row.Label, combo))
        AddBoxRow(New ChartBox(New ChartCatalog.ListKey(
            row.Stem & "-sz", row.Label & " - size")))
    End Sub

    ''' <summary>One row of the column: the letter, what it measures, and
    ''' a box. Every key gets a row, including the ones with a box on the
    ''' chart -- lzf:*charts*' own decision, and for its reason: a sheet
    ''' read as two kinds of thing at once, some letters answered on the
    ''' drawing and the rest in a list, is harder to check than one
    ''' column you can run your eye down.</summary>
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

    ' ------------------------------------------------------- the state line

    ''' <summary>Refresh the line and the Draw button from what is in the
    ''' boxes. The kit decides what it says; this only shows it.</summary>
    ''' <summary>True while the rows are being built. Each binding
    ''' fires TextChanged as it first fills its editor, and restating on
    ''' every one of those asks Lisp about a sheet nobody has typed in
    ''' yet.</summary>
    Private _building As Boolean

    Private Sub Restate()
        If _building Then Return
        If _current.Key Is Nothing Then Return
        Dim state = FormWire.Line(_boxes)
        _state.Text = state.Text
        _state.Foreground = If(state.Ready, SystemColors.GrayTextBrush,
                               Brushes.OrangeRed)
        _draw.IsEnabled = state.Ready
        _recall.IsEnabled = HasStored()
    End Sub

    ' ------------------------------------------------------------- actions

    Private Sub ClearSheet()
        For Each b In _boxes
            b.Text = ""
        Next
        For Each combo In _picks.Values
            combo.SelectedIndex = 0
        Next
        For Each combo In _corners.Values
            combo.SelectedIndex = 0
        Next
        _btype.SelectedIndex = 0
        Restate()
    End Sub

    Private Function HasStored() As Boolean
        If _current.Key Is Nothing Then Return False
        Return RecallStore.Read(_recallKey, _current.Key).Count > 0
    End Function

    ''' <summary>Fill the EMPTY boxes from the stored sheet. Only the
    ''' empty ones, so this can never overwrite a number just typed and
    ''' pressing it twice does nothing the first press did not.</summary>
    Private Sub Recall()
        If _current.Key Is Nothing Then Return
        Dim had = RecallStore.Read(_recallKey, _current.Key)
        For Each b In _boxes
            If b.IsFilled Then Continue For
            Dim v As String = Nothing
            If had.TryGetValue(b.Key, v) Then b.Text = v
        Next
        Restate()
    End Sub

    ''' <summary>What is chosen on a dropdown, or "" while it is on its
    ''' blank first row -- which sends nothing, so the routine asks.
    ''' </summary>
    Private Shared Function Chosen(combo As ComboBox) As String
        If combo Is Nothing OrElse combo.SelectedIndex <= 0 Then Return ""
        Return CStr(combo.SelectedItem)
    End Function

    ''' <summary>What a corner ROW is set to, or "" when it has no
    ''' dropdown -- which cannot happen while the rows and the
    ''' dictionary are built together, and is still not worth throwing
    ''' over.</summary>
    Private Function CornerPick(stem As String) As String
        Dim combo As ComboBox = Nothing
        If Not _corners.TryGetValue(stem, combo) Then Return ""
        Return Chosen(combo)
    End Function

    ''' <summary>Does this treatment carry a size? lzf:csized, as
    ''' words.</summary>
    Private Shared Function Sized(treatment As String) As Boolean
        For Each t In ChartCatalog.PoolSizedTreatments
            If String.Equals(t, treatment, StringComparison.Ordinal) Then
                Return True
            End If
        Next
        Return False
    End Function

    ''' <summary>
    ''' Hand the sheet to the routine, through calofin.lsp's wire.
    '''
    ''' The shape word is a LITERAL and travels as written -- it is not
    ''' always the chart's key, so sending the key would draw the wrong
    ''' pool on six of the sixteen sheets -- and so is every gate the
    ''' chart implies, the in-square keyword, the bottom type and every
    ''' dropdown. Everything typed is a MEASURE and is read on the other
    ''' side.
    ''' </summary>
    Private Sub Run()
        If _current.Key Is Nothing Then Return

        Dim insquare = _insquare.IsChecked.GetValueOrDefault()
        Dim literals As New List(Of String)
        Dim measures As New List(Of String)
        literals.Add(LispBridge.StrPair("shape", _current.Shape))
        literals.Add(LispBridge.StrPair(
            "insq", If(insquare, ChartCatalog.InSquare,
                       ChartCatalog.OutOfSquare)))
        For Each g In _current.Gates
            literals.Add(LispBridge.StrPair(g.Key, g.Value))
        Next
        Dim bottom = Chosen(_btype)
        If bottom.Length > 0 Then
            literals.Add(LispBridge.StrPair("btype", bottom))
        End If
        For Each key In _picks.Keys
            Dim v = Chosen(_picks(key))
            If v.Length > 0 Then literals.Add(LispBridge.StrPair(key, v))
        Next

        ' A CORNER ROW IS NOT ALWAYS ONE CORNER.  The answer is fanned
        ' out to every target the row names for the toggle as it stands
        ' -- in square one row covers all four and its siblings name
        ' nothing, out of square each corner is asked for itself -- and
        ' a row with no targets in this state sends nothing at all.
        ' lzf:cornerpairs' rule, and the reason the table carries two
        ' target lists rather than one.
        Dim sizedKeys As New HashSet(Of String)
        For Each row In CornerRows()
            Dim ty = CornerPick(row.Stem)
            If ty.Length = 0 Then Continue For
            Dim targets = row.Targets(insquare)
            If targets Is Nothing Then Continue For
            For Each target In targets
                literals.Add(LispBridge.StrPair(target & "-ty", ty))
                If Sized(ty) Then sizedKeys.Add(target & "-sz")
            Next
        Next

        ' the size a row was given rides out under the TARGET's key, not
        ' the row's: the row is where it was typed, the target is what
        ' POOL asks about
        Dim sizeOf As New Dictionary(Of String, String)
        For Each b In _boxes
            If b.Key.EndsWith("-sz", StringComparison.Ordinal) Then
                sizeOf(b.Key) = b.Text
            End If
        Next
        For Each row In CornerRows()
            Dim ty = CornerPick(row.Stem)
            If ty.Length = 0 OrElse Not Sized(ty) Then Continue For
            Dim typed As String = Nothing
            If Not sizeOf.TryGetValue(row.Stem & "-sz", typed) Then Continue For
            If String.IsNullOrWhiteSpace(typed) Then Continue For
            Dim targets = row.Targets(insquare)
            If targets Is Nothing Then Continue For
            For Each target In targets
                measures.Add(LispBridge.MeasurePair(target & "-sz", typed))
            Next
        Next

        For Each b In _boxes
            If Not b.IsFilled Then Continue For
            ' a corner size has already travelled, under its targets
            If b.Key.EndsWith("-sz", StringComparison.Ordinal) Then Continue For
            measures.Add(LispBridge.MeasurePair(b.Key, b.Text))
        Next

        RecallStore.Save(_recallKey, _current.Key, _boxes)
        LispBridge.Send(AcadApp.DocumentManager.MdiActiveDocument,
                        LispBridge.BuildFormCall(_entryPoint, literals,
                                                 measures))
    End Sub

End Class
