Imports System.Collections.Generic
Imports System.Collections.ObjectModel
Imports System.Globalization
Imports System.IO
Imports System.Reflection
Imports System.Windows
Imports System.Windows.Controls
Imports System.Windows.Media
Imports System.Windows.Media.Imaging
Imports AcadApp = Autodesk.AutoCAD.ApplicationServices.Application

''' <summary>
''' A bottom type from the shape chart.
'''
''' Twelve are listed because twelve are on the chart. Six have a keyword
''' in pool:*btypes* and can be drawn; the rest are shown disabled, so the
''' screen matches the paper and the gap is visible rather than looking
''' like something the operator failed to find.
''' </summary>
Public Class PoolBottom
    Public Property Title As String
    Public Property ImageFile As String
    ''' <summary>The pool:*btypes* keyword, or Nothing when unimplemented.</summary>
    Public Property BType As String
    Public Property Why As String
    Public Property Fields As New ObservableCollection(Of SpaField)

    Public ReadOnly Property Supported As Boolean
        Get
            Return Not String.IsNullOrEmpty(BType)
        End Get
    End Property

    Public ReadOnly Property Display As String
        Get
            Return If(Supported, Title, Title & "  (not implemented)")
        End Get
    End Property
End Class


''' <summary>
''' The twelve bottoms and where their letters sit.
'''
''' Mirrors assets\bottoms\fieldmap.json, which stays the file the
''' positions are tuned in.
''' </summary>
Public NotInheritable Class BottomCatalog

    Private Sub New()
    End Sub

    Private Shared Function F(key As String, letter As String, label As String,
                              x As Double, y As Double) As SpaField
        Return New SpaField() With {
            .Key = key, .Letter = letter, .Label = label, .X = x, .Y = y}
    End Function

    Public Shared Function Load() As List(Of PoolBottom)
        Dim out As New List(Of PoolBottom)

        ' ---- Normal. The only style that draws no side profile, so it
        '      never asks for C or D at all.
        Dim normal As New PoolBottom() With {
            .Title = "Standard Hopper", .BType = "Normal",
            .ImageFile = "standard-hopper.png"}
        normal.Fields.Add(F("h", "H", "H - left end to deep end", 0.17, 0.8))
        normal.Fields.Add(F("g", "G", "G - hopper length", 0.33, 0.8))
        normal.Fields.Add(F("f", "F", "F - hopper to slope break", 0.55, 0.8))
        normal.Fields.Add(F("e", "E", "E - slope break to right end", 0.8, 0.8))
        out.Add(normal)

        ' ---- Sloping shallow end. Chart prints C1 at the right wall;
        '      POOL calls that same measurement C.
        Dim shallow As New PoolBottom() With {
            .Title = "Sloping Shallow End", .BType = "SHallow",
            .ImageFile = "sloping-shallow-end.png"}
        shallow.Fields.Add(F("h", "H", "H - left end to deep end", 0.17, 0.82))
        shallow.Fields.Add(F("g", "G", "G - hopper length", 0.32, 0.82))
        shallow.Fields.Add(F("f", "F", "F - hopper to slope break", 0.53, 0.82))
        shallow.Fields.Add(F("e", "E", "E - slope break to right end", 0.78, 0.82))
        shallow.Fields.Add(F("d", "D", "D - deep end depth", 0.33, 0.5))
        shallow.Fields.Add(F("c2", "C2",
            "C2 - depth where the shallow floor meets the break", 0.63, 0.47))
        shallow.Fields.Add(F("c", "C1", "C - wall height (shallow depth)", 0.9, 0.45))
        out.Add(shallow)

        Dim sport As New PoolBottom() With {
            .Title = "Sport", .BType = "Sport", .ImageFile = "sport.png"}
        sport.Fields.Add(F("e2", "E2", "E2 - left end shallow flat", 0.12, 0.83))
        sport.Fields.Add(F("f2", "F2", "F2 - left slope", 0.27, 0.83))
        sport.Fields.Add(F("g", "G", "G - hopper length", 0.5, 0.83))
        sport.Fields.Add(F("f1", "F1", "F1 - right slope", 0.71, 0.83))
        sport.Fields.Add(F("e1", "E1", "E1 - right end shallow flat", 0.87, 0.83))
        sport.Fields.Add(F("d", "D", "D - deep depth", 0.47, 0.5))
        sport.Fields.Add(F("c", "C", "C - wall height (shallow depth)", 0.92, 0.45))
        out.Add(sport)

        Dim slope As New PoolBottom() With {
            .Title = "Slope Bottom", .BType = "SLope",
            .ImageFile = "slope-bottom.png"}
        slope.Fields.Add(F("h", "H", "H - left end to deep end", 0.14, 0.83))
        slope.Fields.Add(F("f", "F", "F - hopper to slope break", 0.42, 0.83))
        slope.Fields.Add(F("e", "E", "E - slope break to right end", 0.76, 0.83))
        slope.Fields.Add(F("d", "D", "D - deep end depth", 0.25, 0.52))
        slope.Fields.Add(F("c", "C", "C - wall height (shallow depth)", 0.92, 0.45))
        out.Add(slope)

        ' ---- Wedge pins G and E, so only H and F are asked.
        Dim wedge As New PoolBottom() With {
            .Title = "Wedge", .BType = "Wedge", .ImageFile = "wedge.png"}
        wedge.Fields.Add(F("h", "H", "H - left end to deep end", 0.15, 0.87))
        wedge.Fields.Add(F("f", "F", "F - deep end to slope break", 0.52, 0.87))
        wedge.Fields.Add(F("d", "D", "D - deep end depth", 0.24, 0.62))
        wedge.Fields.Add(F("c", "C", "C - wall height (shallow depth)", 0.93, 0.55))
        out.Add(wedge)

        Dim modflat As New PoolBottom() With {
            .Title = "Modified Flat", .BType = "MOdflat",
            .ImageFile = "modified-flat.png"}
        modflat.Fields.Add(F("h", "H", "H - left end to deep end", 0.15, 0.86))
        modflat.Fields.Add(F("g", "G", "G - hopper length", 0.45, 0.86))
        modflat.Fields.Add(F("f", "F", "F - hopper to slope break", 0.78, 0.86))
        modflat.Fields.Add(F("d", "D", "D - deep end depth", 0.45, 0.52))
        modflat.Fields.Add(F("c", "C", "C - wall height (shallow depth)", 0.92, 0.45))
        out.Add(modflat)

        ' ---- On the chart, not in POOL. Shown so the screen matches the
        '      paper; selecting one only displays why it cannot be drawn.
        out.Add(New PoolBottom() With {
            .Title = "Multiple Depth", .ImageFile = "multiple-depth.png",
            .Why = "Needs C4 and the multi-break chain; no keyword in pool:*btypes*."})
        out.Add(New PoolBottom() With {
            .Title = "Sport (Shallow Cove)", .ImageFile = "sport-shallow-cove.png",
            .Why = "Needs F3 and C3; no keyword in pool:*btypes*."})
        out.Add(New PoolBottom() With {
            .Title = "Modified Flat Shallow End",
            .ImageFile = "modified-flat-shallow-end.png",
            .Why = "Needs C1/C2/C3 with F2/F1; no keyword in pool:*btypes*."})
        out.Add(New PoolBottom() With {
            .Title = "Sport (No Hopper Pad)", .ImageFile = "sport-no-hopper-pad.png",
            .Why = "POOL reaches this as Sport with G = 0, not as its own style."})
        out.Add(New PoolBottom() With {
            .Title = "Straight Slope", .ImageFile = "straight-slope.png",
            .Why = "No keyword in pool:*btypes*."})
        out.Add(New PoolBottom() With {
            .Title = "Flat", .ImageFile = "flat.png",
            .Why = "No keyword in pool:*btypes*."})

        Return out
    End Function

    Public Shared Function ImagePath(file As String) As String
        Dim dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)
        Return Path.Combine(dir, "assets", "bottoms", file)
    End Function

End Class


''' <summary>
''' The Pool tab: pick a bottom type, read its section, fill in the
''' depths and chain you have.
'''
''' This form covers the BOTTOM only. The plan view -- shape, corners,
''' cross dims -- is still answered at the command line, so POOL is only
''' partly formed; that is deliberate for a first pass, because the
''' bottom is where the depths live and the depths are what the section
''' drawing is for.
''' </summary>
Public Class PoolFormView
    Inherits UserControl

    Private ReadOnly _bottoms As List(Of PoolBottom) = BottomCatalog.Load()
    Private ReadOnly _canvas As New Canvas()
    Private ReadOnly _image As New Image() With {.Stretch = Stretch.Uniform}
    Private ReadOnly _overlay As New List(Of FrameworkElement)
    Private ReadOnly _rows As New StackPanel()
    Private ReadOnly _warn As New TextBlock() With {
        .TextWrapping = TextWrapping.Wrap,
        .Foreground = Brushes.OrangeRed,
        .Margin = New Thickness(0, 6, 0, 0),
        .Visibility = Visibility.Collapsed}

    Private _current As PoolBottom

    Public Sub New()
        Dim root As New Grid()
        root.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(1, GridUnitType.Star)})
        root.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(1.4, GridUnitType.Star)})

        root.Children.Add(BuildPanel())
        Dim diagram = BuildDiagram()
        Grid.SetColumn(diagram, 1)
        root.Children.Add(diagram)

        Content = root
        Show(_bottoms(0))
    End Sub

    Private Function BuildPanel() As FrameworkElement
        Dim panel As New DockPanel() With {.Margin = New Thickness(8)}

        Dim head As New StackPanel()
        head.Children.Add(New TextBlock() With {
            .Text = "Bottom type. Fill in what you have; anything left blank " &
                    "is asked for at the command line.",
            .TextWrapping = TextWrapping.Wrap, .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 8)})

        Dim combo As New ComboBox() With {
            .ItemsSource = _bottoms, .DisplayMemberPath = "Display",
            .SelectedIndex = 0}
        AddHandler combo.SelectionChanged,
            Sub() Show(TryCast(combo.SelectedItem, PoolBottom))
        head.Children.Add(combo)
        head.Children.Add(_warn)
        DockPanel.SetDock(head, Dock.Top)
        panel.Children.Add(head)

        Dim buttons As New StackPanel() With {
            .Orientation = Orientation.Horizontal,
            .HorizontalAlignment = HorizontalAlignment.Right,
            .Margin = New Thickness(0, 8, 0, 0)}
        Dim draw As New Button() With {
            .Content = "Draw", .Padding = New Thickness(14, 4, 14, 4)}
        AddHandler draw.Click, Sub() Run()
        Dim clear As New Button() With {
            .Content = "Clear", .Padding = New Thickness(10, 4, 10, 4),
            .Margin = New Thickness(0, 0, 6, 0)}
        AddHandler clear.Click,
            Sub()
                If _current IsNot Nothing Then
                    For Each f In _current.Fields
                        f.Value = ""
                    Next
                End If
            End Sub
        buttons.Children.Add(clear)
        buttons.Children.Add(draw)
        DockPanel.SetDock(buttons, Dock.Bottom)
        panel.Children.Add(buttons)

        panel.Children.Add(New ScrollViewer() With {
            .VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            .Content = _rows})
        Return panel
    End Function

    Private Function BuildDiagram() As FrameworkElement
        Dim host As New Grid() With {.Margin = New Thickness(4, 8, 8, 8)}
        host.Children.Add(_image)
        host.Children.Add(_canvas)
        AddHandler host.SizeChanged, Sub() PlaceOverlay()
        Return host
    End Function

    Private Sub Show(b As PoolBottom)
        _current = b
        _rows.Children.Clear()
        _canvas.Children.Clear()
        _overlay.Clear()
        If b Is Nothing Then Return

        If b.Supported Then
            _warn.Visibility = Visibility.Collapsed
        Else
            _warn.Text = b.Why & "  The section is shown for reference; POOL " &
                         "will ask for a bottom type it can draw."
            _warn.Visibility = Visibility.Visible
        End If

        Try
            Dim p = BottomCatalog.ImagePath(b.ImageFile)
            If File.Exists(p) Then
                Dim bmp As New BitmapImage()
                bmp.BeginInit()
                bmp.CacheOption = BitmapCacheOption.OnLoad
                bmp.UriSource = New Uri(p)
                bmp.EndInit()
                _image.Source = bmp
            Else
                _image.Source = Nothing
            End If
        Catch
            _image.Source = Nothing
        End Try

        For Each f In b.Fields
            Dim row As New DockPanel() With {.Margin = New Thickness(0, 2, 0, 2)}
            row.Children.Add(New TextBlock() With {
                .Text = f.Letter, .Width = 34, .FontWeight = FontWeights.Bold,
                .VerticalAlignment = VerticalAlignment.Center})
            Dim tb As New TextBox() With {.Width = 80, .IsEnabled = b.Supported}
            BindTo(tb, f)
            DockPanel.SetDock(tb, Dock.Right)
            row.Children.Add(tb)
            row.Children.Add(New TextBlock() With {
                .Text = f.Label, .ToolTip = f.Label,
                .TextTrimming = TextTrimming.CharacterEllipsis,
                .VerticalAlignment = VerticalAlignment.Center,
                .Margin = New Thickness(0, 0, 8, 0)})
            _rows.Children.Add(row)

            Dim over As New TextBox() With {
                .Width = 46, .Tag = f, .IsEnabled = b.Supported,
                .TextAlignment = TextAlignment.Center,
                .ToolTip = f.Letter & " - " & f.Label,
                .Background = New SolidColorBrush(Color.FromArgb(235, 255, 255, 255))}
            BindTo(over, f)
            _canvas.Children.Add(over)
            _overlay.Add(over)
        Next

        PlaceOverlay()
    End Sub

    Private Shared Sub BindTo(box As TextBox, f As SpaField)
        Dim b As New Data.Binding("Value") With {
            .Source = f, .Mode = Data.BindingMode.TwoWay,
            .UpdateSourceTrigger = Data.UpdateSourceTrigger.PropertyChanged}
        box.SetBinding(TextBox.TextProperty, b)
    End Sub

    ''' <summary>Same fractional placement as the spa form; see SpaFormView.</summary>
    Private Sub PlaceOverlay()
        If _image.Source Is Nothing Then Return
        Dim hostW = _canvas.ActualWidth, hostH = _canvas.ActualHeight
        If hostW <= 0 OrElse hostH <= 0 Then Return
        Dim iw = _image.Source.Width, ih = _image.Source.Height
        If iw <= 0 OrElse ih <= 0 Then Return

        Dim scale = Math.Min(hostW / iw, hostH / ih)
        Dim dw = iw * scale, dh = ih * scale
        Dim ox = (hostW - dw) / 2, oy = (hostH - dh) / 2

        For Each el In _overlay
            Dim f = TryCast(el.Tag, SpaField)
            If f Is Nothing Then Continue For
            el.Measure(New Size(Double.PositiveInfinity, Double.PositiveInfinity))
            Dim w = If(el.DesiredSize.Width > 0, el.DesiredSize.Width, 46)
            Dim h = If(el.DesiredSize.Height > 0, el.DesiredSize.Height, 22)
            Canvas.SetLeft(el, ox + dw * f.X - w / 2)
            Canvas.SetTop(el, oy + dh * f.Y - h / 2)
        Next
    End Sub

    Private Sub Run()
        If _current Is Nothing OrElse Not _current.Supported Then Return

        Dim pairs As New List(Of String)
        pairs.Add(LispBridge.StrPair("btype", _current.BType))
        For Each f In _current.Fields
            If f.IsFilled Then
                pairs.Add(LispBridge.NumPair(f.Key, f.AsNumber()))
            End If
        Next

        LispBridge.Send(AcadApp.DocumentManager.MdiActiveDocument,
                        LispBridge.BuildCall("pool:run-with-answers", pairs))
    End Sub

End Class
