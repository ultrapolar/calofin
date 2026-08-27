Imports System.Collections.Generic
Imports System.Collections.ObjectModel
Imports System.ComponentModel
Imports System.Globalization
Imports System.IO
Imports System.Reflection
Imports System.Windows
Imports System.Windows.Controls
Imports System.Windows.Data
Imports System.Windows.Media
Imports System.Windows.Media.Imaging
Imports Autodesk.AutoCAD.ApplicationServices
Imports AcadApp = Autodesk.AutoCAD.ApplicationServices.Application

''' <summary>
''' One measurement. The table cell and the box on the diagram are two
''' views of this same object, so typing in either updates the other with
''' no wiring between them -- that is the whole reason the form is built
''' around a field list rather than around controls.
''' </summary>
Public Class SpaField
    Implements INotifyPropertyChanged

    Public Event PropertyChanged As PropertyChangedEventHandler _
        Implements INotifyPropertyChanged.PropertyChanged

    Public Property Key As String
    Public Property Letter As String
    Public Property Label As String
    Public Property Required As Boolean
    Public Property X As Double
    Public Property Y As Double

    Private _value As String = ""

    ''' <summary>
    ''' Held as text, not a number. Empty is a real answer -- it means the
    ''' measurement was not taken -- and a nullable Double cannot carry the
    ''' difference between "blank" and "0" as the user typed it.
    ''' </summary>
    Public Property Value As String
        Get
            Return _value
        End Get
        Set(v As String)
            If _value = v Then Return
            _value = v
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Value"))
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("IsFilled"))
        End Set
    End Property

    Public ReadOnly Property IsFilled As Boolean
        Get
            Return Not String.IsNullOrWhiteSpace(_value)
        End Get
    End Property

    ''' <summary>
    ''' Parsed for the Lisp call. Nothing when blank, which the bridge
    ''' emits as nil and SPA.LSP reads as NA.
    ''' </summary>
    Public Function AsNumber() As Double?
        If Not IsFilled Then Return Nothing
        Dim d As Double
        If Double.TryParse(_value.Trim(), NumberStyles.Float,
                           CultureInfo.InvariantCulture, d) Then
            Return d
        End If
        ' also accept the operator's own locale, since they typed it
        If Double.TryParse(_value.Trim(), NumberStyles.Float,
                           CultureInfo.CurrentCulture, d) Then
            Return d
        End If
        Return Nothing
    End Function

End Class


''' <summary>A corner: a treatment, and a size when the treatment has one.</summary>
Public Class SpaCorner
    Implements INotifyPropertyChanged

    Public Event PropertyChanged As PropertyChangedEventHandler _
        Implements INotifyPropertyChanged.PropertyChanged

    Public Property Label As String
    Public Property TypeKey As String
    Public Property SizeKey As String
    Public Property X As Double
    Public Property Y As Double

    ' The canonical Treatment words (STANDARDS section 2).  SPA.LSP still
    ' accepts the old wire values 90/Diagonal from an un-rebuilt DLL and
    ' normalises them, so this rename is safe to ship either side first.
    Public ReadOnly Property Treatments As String() =
        {"", "Square", "Radius", "Cut", "NotGiven"}

    Private _treatment As String = ""
    Private _size As String = ""

    ''' <summary>Blank leaves the corner to be asked for at the command line.</summary>
    Public Property Treatment As String
        Get
            Return _treatment
        End Get
        Set(v As String)
            If _treatment = v Then Return
            _treatment = v
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Treatment"))
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("NeedsSize"))
        End Set
    End Property

    Public Property Size As String
        Get
            Return _size
        End Get
        Set(v As String)
            If _size = v Then Return
            _size = v
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Size"))
        End Set
    End Property

    ''' <summary>A 90 corner has no size; radius and diagonal do.</summary>
    Public ReadOnly Property NeedsSize As Boolean
        Get
            Return _treatment = "Radius" OrElse _treatment = "Diagonal"
        End Get
    End Property

End Class


''' <summary>
''' The cover questions that follow the outline: the offer of the second
''' outline, then the auto-hinge details.  One set for the whole form --
''' SPA asks them the same way whatever the shape.
'''
''' Each keyword is tri-state through its blank row: blank sends
''' NOTHING, so the key stays absent and SPA asks at the command line.
''' There is deliberately no explicit-nil state here -- (key . nil)
''' reads as an answered NA, which none of these keyword prompts
''' accepts; the store would consume it and ask anyway.
''' </summary>
Public Class SpaCover
    Implements INotifyPropertyChanged

    Public Event PropertyChanged As PropertyChangedEventHandler _
        Implements INotifyPropertyChanged.PropertyChanged

    ''' <summary>Spelled exactly as the prompts spell them: SPA.LSP
    ''' matches the canonical spelling, so a "yes" would be consumed,
    ''' ignored, and asked all over again.</summary>
    Public ReadOnly Property SecondChoices As String() = {"", "Yes", "No"}
    Public ReadOnly Property MethodChoices As String() = {"", "Offset", "Dims"}
    Public ReadOnly Property AutohingeChoices As String() = {"", "Yes", "No"}
    Public ReadOnly Property GradeChoices As String() =
        {"", "STANDARD", "THERMOLIGHT"}
    Public ReadOnly Property TaperChoices As String() =
        {"", "3-2", "4-2", "4-3", "5-3", "5-4", "3-3", "1-3/8"}

    ''' <summary>The cover's lap past the water's edge -- read when the
    ''' second outline is taken from an Offset.  An ordinary field, so
    ''' blank means not answered exactly as everywhere else.</summary>
    Public Property Gap As New SpaField() With {
        .Key = "gap", .Letter = "",
        .Label = "How far does the cover lap the water's edge (Offset)"}

    Private _second As String = ""
    Private _method As String = ""
    Private _autohinge As String = ""
    Private _grade As String = ""
    Private _taper As String = ""

    ''' <summary>Draw the other outline as well?</summary>
    Public Property Second As String
        Get
            Return _second
        End Get
        Set(v As String)
            If _second = v Then Return
            _second = v
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Second"))
        End Set
    End Property

    ''' <summary>Where the other outline comes from: an Offset of the
    ''' first, or its own Dims.</summary>
    Public Property Method As String
        Get
            Return _method
        End Get
        Set(v As String)
            If _method = v Then Return
            _method = v
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Method"))
        End Set
    End Property

    Public Property Autohinge As String
        Get
            Return _autohinge
        End Get
        Set(v As String)
            If _autohinge = v Then Return
            _autohinge = v
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Autohinge"))
        End Set
    End Property

    ''' <summary>The Spa Cover Details values.  Normally read off the
    ''' block in the drawing; a form answer wins over the block's.</summary>
    Public Property Grade As String
        Get
            Return _grade
        End Get
        Set(v As String)
            If _grade = v Then Return
            _grade = v
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Grade"))
        End Set
    End Property

    Public Property Taper As String
        Get
            Return _taper
        End Get
        Set(v As String)
            If _taper = v Then Return
            _taper = v
            RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs("Taper"))
        End Set
    End Property

End Class


''' <summary>
''' The shape currently on the form: its picture, its fields, its corners.
''' </summary>
Public Class SpaShape
    Public Property Name As String
    Public Property LispShape As String
    Public Property ImageFile As String
    Public Property Fields As New ObservableCollection(Of SpaField)
    Public Property Corners As New ObservableCollection(Of SpaCorner)

    ''' <summary>The second outline's own overalls, asked when the other
    ''' outline is taken from Dims.  Keyed per shape -- the rectangle
    ''' flow says w2/l2 where octagon and round say b2/a2 -- and kept
    ''' off the diagram: the chart has no letters for them.</summary>
    Public Property SecondOutline As New ObservableCollection(Of SpaField)
End Class


''' <summary>
''' Builds the Lisp call from whatever the user filled in.
'''
''' Note what is NOT here: no defaults, no derived sizes, no rules about
''' which measurement implies which. SPA.LSP already does all of that and
''' does it the same way for the command line, so duplicating any of it
''' here would be a second source of truth that could drift.
''' </summary>
Public Class SpaViewModel

    Public Property Shapes As New ObservableCollection(Of SpaShape)
    Public Property Modes As String() = {"Watersedge", "Coversize"}
    Public Property Mode As String = "Watersedge"
    Public Property Current As SpaShape
    Public Property Cover As New SpaCover()

    Public Sub New()
        For Each s In ShapeCatalog.Load()
            Shapes.Add(s)
        Next
        If Shapes.Count > 0 Then Current = Shapes(0)
    End Sub

    ''' <summary>
    ''' Only fields the user actually touched are sent. A key left out is
    ''' asked for at the command line, which is what makes a half-filled
    ''' form legitimate rather than an error.
    ''' </summary>
    Public Function BuildCall() As String
        If Current Is Nothing Then Return String.Empty

        Dim pairs As New List(Of String)
        pairs.Add(LispBridge.StrPair("mode", Mode))
        pairs.Add(LispBridge.StrPair("shape", Current.LispShape))

        For Each f In Current.Fields
            If f.IsFilled Then
                pairs.Add(LispBridge.NumPair(f.Key, f.AsNumber()))
            End If
        Next

        For Each c In Current.Corners
            If Not String.IsNullOrWhiteSpace(c.Treatment) Then
                pairs.Add(LispBridge.StrPair(c.TypeKey, c.Treatment))
                If c.NeedsSize AndAlso Not String.IsNullOrWhiteSpace(c.Size) Then
                    Dim d As Double
                    If Double.TryParse(c.Size.Trim(), NumberStyles.Float,
                                       CultureInfo.InvariantCulture, d) OrElse
                       Double.TryParse(c.Size.Trim(), NumberStyles.Float,
                                       CultureInfo.CurrentCulture, d) Then
                        pairs.Add(LispBridge.NumPair(c.SizeKey, d))
                    End If
                End If
            End If
        Next

        ' The cover questions, in the order the run reaches them.  A
        ' keyword row left on its blank row sends nothing at all -- the
        ' key stays absent and SPA asks -- while a chosen answer goes
        ' out spelled exactly as the prompt would spell it.  Only the
        ' lap and the by-dims overalls are numbers, under the same
        ' filled-or-omitted rule as the fields above.
        If Not String.IsNullOrWhiteSpace(Cover.Second) Then
            pairs.Add(LispBridge.StrPair("second", Cover.Second))
        End If
        If Not String.IsNullOrWhiteSpace(Cover.Method) Then
            pairs.Add(LispBridge.StrPair("method", Cover.Method))
        End If
        If Cover.Gap.IsFilled Then
            pairs.Add(LispBridge.NumPair("gap", Cover.Gap.AsNumber()))
        End If

        For Each f In Current.SecondOutline
            If f.IsFilled Then
                pairs.Add(LispBridge.NumPair(f.Key, f.AsNumber()))
            End If
        Next

        If Not String.IsNullOrWhiteSpace(Cover.Autohinge) Then
            pairs.Add(LispBridge.StrPair("autohinge", Cover.Autohinge))
        End If
        If Not String.IsNullOrWhiteSpace(Cover.Grade) Then
            pairs.Add(LispBridge.StrPair("grade", Cover.Grade))
        End If
        If Not String.IsNullOrWhiteSpace(Cover.Taper) Then
            pairs.Add(LispBridge.StrPair("taper", Cover.Taper))
        End If

        Return LispBridge.BuildCall("spa:run-with-answers", pairs)
    End Function

    Public Sub Run()
        Dim expr = BuildCall()
        If expr = String.Empty Then Return
        LispBridge.Send(AcadApp.DocumentManager.MdiActiveDocument, expr)
    End Sub

    Public Sub Clear()
        If Current Is Nothing Then Return
        For Each f In Current.Fields
            f.Value = ""
        Next
        For Each f In Current.SecondOutline
            f.Value = ""
        Next
        For Each c In Current.Corners
            c.Treatment = ""
            c.Size = ""
        Next
        Cover.Second = ""
        Cover.Method = ""
        Cover.Gap.Value = ""
        Cover.Autohinge = ""
        Cover.Grade = ""
        Cover.Taper = ""
    End Sub

End Class


''' <summary>
''' The shapes and their field positions.
'''
''' Kept in code rather than read from fieldmap.json so the palette has no
''' file dependency at run time; fieldmap.json stays the reference the
''' positions are tuned in, and the two are meant to be kept in step.
''' </summary>
Public NotInheritable Class ShapeCatalog

    Private Sub New()
    End Sub

    Private Shared Function F(key As String, letter As String, label As String,
                              required As Boolean, x As Double, y As Double) As SpaField
        Return New SpaField() With {
            .Key = key, .Letter = letter, .Label = label,
            .Required = required, .X = x, .Y = y}
    End Function

    Private Shared Function C(label As String, tk As String, sk As String,
                              x As Double, y As Double) As SpaCorner
        Return New SpaCorner() With {
            .Label = label, .TypeKey = tk, .SizeKey = sk, .X = x, .Y = y}
    End Function

    Public Shared Function Load() As List(Of SpaShape)
        Dim out As New List(Of SpaShape)

        ' --- Rectangle. Note the overalls are 'w and 'l here, not 'b/'a:
        '     the rectangle flow in SPA.LSP names them differently from
        '     the octagon and round flows.
        Dim rect As New SpaShape() With {
            .Name = "Rectangle", .LispShape = "Rectangle",
            .ImageFile = "rectangle.png"}
        rect.Fields.Add(F("w", "B", "Overall WIDTH across (A-B)", True, 0.5, 0.25))
        rect.Fields.Add(F("l", "A", "Overall LENGTH up (A-D)", True, 0.075, 0.6))
        rect.Corners.Add(C("Corner A", "cornera-ty", "cornera-sz", 0.1, 0.86))
        rect.Corners.Add(C("Corner B", "cornerb-ty", "cornerb-sz", 0.9, 0.86))
        rect.Corners.Add(C("Corner C", "cornerc-ty", "cornerc-sz", 0.9, 0.28))
        rect.Corners.Add(C("Corner D", "cornerd-ty", "cornerd-sz", 0.1, 0.28))
        ' the second outline by dims -- the rectangle flow echoes its
        ' w/l as w2/l2 (b2/a2 here would be silently dropped)
        rect.SecondOutline.Add(F("w2", "", "cover size overall ACROSS",
                                 True, 0.0, 0.0))
        rect.SecondOutline.Add(F("l2", "", "cover size overall UP",
                                 False, 0.0, 0.0))
        out.Add(rect)

        ' --- Octagon. These keys line up with the chart letters exactly,
        '     and the rows run in SPA's own ask order: the cut FACE S2
        '     comes right after the overalls, before the flats.
        Dim oct As New SpaShape() With {
            .Name = "Octagon", .LispShape = "OCtagon",
            .ImageFile = "octagon.png"}
        oct.Fields.Add(F("b", "B", "B - overall size ACROSS", True, 0.53, 0.245))
        oct.Fields.Add(F("a", "A", "A - overall size UP", False, 0.265, 0.63))
        oct.Fields.Add(F("s2", "S2",
                         "S2 - corner cut FACE (the tape across the cut)",
                         False, 0.735, 0.86))
        oct.Fields.Add(F("tt", "T", "T - flat across (top & bottom)", False, 0.545, 0.3))
        oct.Fields.Add(F("ss", "S", "S - corner cut along the side", False, 0.435, 0.3))
        oct.Fields.Add(F("s1", "S1", "S1 - corner cut up the end", False, 0.325, 0.44))
        oct.Fields.Add(F("vv", "V", "V - flat up (left & right)", False, 0.305, 0.63))
        ' the second outline by dims -- b2/a2 echo b/a, f2 the cut face
        oct.SecondOutline.Add(F("b2", "", "Overall ACROSS", True, 0.0, 0.0))
        oct.SecondOutline.Add(F("a2", "", "Overall UP", False, 0.0, 0.0))
        oct.SecondOutline.Add(F("f2", "", "Corner cut FACE", False, 0.0, 0.0))
        out.Add(oct)

        ' --- Round: a circle when the overalls match, an ellipse when not.
        Dim rnd As New SpaShape() With {
            .Name = "Round", .LispShape = "ROUnd",
            .ImageFile = "round.png"}
        rnd.Fields.Add(F("b", "B", "B - overall size ACROSS", True, 0.5, 0.24))
        rnd.Fields.Add(F("a", "A", "A - overall size UP", False, 0.225, 0.6))
        ' the second outline by dims -- the same two keys as the octagon's
        rnd.SecondOutline.Add(F("b2", "", "Overall ACROSS", True, 0.0, 0.0))
        rnd.SecondOutline.Add(F("a2", "", "Overall UP", False, 0.0, 0.0))
        out.Add(rnd)

        Return out
    End Function

    ''' <summary>Shape art sits next to the assembly, under assets\shapes.</summary>
    Public Shared Function ImagePath(file As String) As String
        Dim dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)
        Return Path.Combine(dir, "assets", "shapes", file)
    End Function

End Class


''' <summary>
''' The Spa tab: variable table on the left, diagram on the right with a
''' box sitting where each letter is printed. Both are bound to the same
''' SpaField, so either one can be typed into.
''' </summary>
Public Class SpaFormView
    Inherits UserControl

    Private ReadOnly _vm As New SpaViewModel()
    Private ReadOnly _canvas As New Canvas()
    Private ReadOnly _image As New Image() With {.Stretch = Stretch.Uniform}
    Private ReadOnly _overlay As New List(Of FrameworkElement)

    Public Sub New()
        DataContext = _vm

        Dim root As New Grid()
        root.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(1, GridUnitType.Star)})
        root.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(4)})
        root.ColumnDefinitions.Add(New ColumnDefinition() With {
            .Width = New GridLength(1.4, GridUnitType.Star)})

        root.Children.Add(BuildTable())

        Dim splitter As New GridSplitter() With {
            .Width = 4, .HorizontalAlignment = HorizontalAlignment.Stretch}
        Grid.SetColumn(splitter, 1)
        root.Children.Add(splitter)

        Dim diagram = BuildDiagram()
        Grid.SetColumn(diagram, 2)
        root.Children.Add(diagram)

        Content = root
        ShowShape(_vm.Current)
    End Sub

    ' ---------------------------------------------------------------- table
    Private Function BuildTable() As FrameworkElement
        Dim panel As New DockPanel() With {.Margin = New Thickness(8)}

        Dim head As New StackPanel() With {.Margin = New Thickness(0, 0, 0, 8)}
        head.Children.Add(New TextBlock() With {
            .Text = "Fill in what you have. Anything left blank is asked for " &
                    "at the command line.",
            .TextWrapping = TextWrapping.Wrap,
            .Opacity = 0.75,
            .Margin = New Thickness(0, 0, 0, 8)})

        Dim shapeRow As New StackPanel() With {.Orientation = Orientation.Horizontal}
        shapeRow.Children.Add(New TextBlock() With {
            .Text = "Shape", .Width = 58,
            .VerticalAlignment = VerticalAlignment.Center})
        Dim shapeBox As New ComboBox() With {.Width = 130, .ItemsSource = _vm.Shapes,
                                             .DisplayMemberPath = "Name",
                                             .SelectedItem = _vm.Current}
        AddHandler shapeBox.SelectionChanged,
            Sub()
                _vm.Current = TryCast(shapeBox.SelectedItem, SpaShape)
                ShowShape(_vm.Current)
                BuildFieldRows()
            End Sub
        shapeRow.Children.Add(shapeBox)
        head.Children.Add(shapeRow)

        Dim modeRow As New StackPanel() With {
            .Orientation = Orientation.Horizontal, .Margin = New Thickness(0, 6, 0, 0)}
        modeRow.Children.Add(New TextBlock() With {
            .Text = "Drawing", .Width = 58,
            .VerticalAlignment = VerticalAlignment.Center})
        Dim modeBox As New ComboBox() With {.Width = 130, .ItemsSource = _vm.Modes,
                                            .SelectedItem = _vm.Mode}
        AddHandler modeBox.SelectionChanged,
            Sub() _vm.Mode = CStr(modeBox.SelectedItem)
        modeRow.Children.Add(modeBox)
        head.Children.Add(modeRow)

        DockPanel.SetDock(head, Dock.Top)
        panel.Children.Add(head)

        Dim buttons As New StackPanel() With {
            .Orientation = Orientation.Horizontal,
            .HorizontalAlignment = HorizontalAlignment.Right,
            .Margin = New Thickness(0, 8, 0, 0)}
        Dim draw As New Button() With {
            .Content = "Draw", .Padding = New Thickness(14, 4, 14, 4),
            .IsDefault = True}
        AddHandler draw.Click, Sub() _vm.Run()
        Dim clear As New Button() With {
            .Content = "Clear", .Padding = New Thickness(10, 4, 10, 4),
            .Margin = New Thickness(0, 0, 6, 0)}
        AddHandler clear.Click, Sub() _vm.Clear()
        buttons.Children.Add(clear)
        buttons.Children.Add(draw)
        DockPanel.SetDock(buttons, Dock.Bottom)
        panel.Children.Add(buttons)

        _rows = New StackPanel()
        panel.Children.Add(New ScrollViewer() With {
            .VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            .Content = _rows})

        BuildFieldRows()
        Return panel
    End Function

    Private _rows As StackPanel

    ''' <summary>One row per field: letter, description, value box.</summary>
    Private Sub BuildFieldRows()
        If _rows Is Nothing Then Return
        _rows.Children.Clear()
        If _vm.Current Is Nothing Then Return

        For Each f In _vm.Current.Fields
            AddFieldRow(f)
        Next

        If _vm.Current.Corners.Count > 0 Then
            _rows.Children.Add(New TextBlock() With {
                .Text = "Corners", .FontWeight = FontWeights.Bold,
                .Margin = New Thickness(0, 12, 0, 4)})

            For Each c In _vm.Current.Corners
                Dim row As New DockPanel() With {.Margin = New Thickness(0, 2, 0, 2)}
                row.Children.Add(New TextBlock() With {
                    .Text = c.Label, .Width = 74,
                    .VerticalAlignment = VerticalAlignment.Center})

                Dim size As New TextBox() With {.Width = 56}
                BindText(size, c, "Size")
                BindVisible(size, c, "NeedsSize")
                DockPanel.SetDock(size, Dock.Right)
                row.Children.Add(size)

                Dim ty As New ComboBox() With {
                    .Width = 88, .ItemsSource = c.Treatments,
                    .Margin = New Thickness(0, 0, 6, 0)}
                BindSelected(ty, c, "Treatment")
                DockPanel.SetDock(ty, Dock.Right)
                row.Children.Add(ty)

                _rows.Children.Add(row)
            Next
        End If

        ' ------- the cover: the offer of the other outline, then the
        '         auto-hinge details.  A dropdown left on its blank row
        '         sends nothing, so SPA asks at the command line; the
        '         lap and the by-dims overalls are ordinary fields.
        _rows.Children.Add(New TextBlock() With {
            .Text = "Cover", .FontWeight = FontWeights.Bold,
            .Margin = New Thickness(0, 12, 0, 4)})

        AddCoverRow("Draw the other outline",
                    "second - add the water's edge / cover size as well",
                    "Second", _vm.Cover.SecondChoices)
        AddCoverRow("Take it from",
                    "method - an Offset of the first outline, or its own Dims",
                    "Method", _vm.Cover.MethodChoices)
        AddFieldRow(_vm.Cover.Gap)
        For Each f In _vm.Current.SecondOutline
            AddFieldRow(f)
        Next
        AddCoverRow("Auto-hinge the cover",
                    "autohinge - lay the hinges out automatically",
                    "Autohinge", _vm.Cover.AutohingeChoices)
        AddCoverRow("Grade",
                    "grade - the Spa Cover Details grade; a form answer " &
                    "wins over the block's",
                    "Grade", _vm.Cover.GradeChoices)
        AddCoverRow("Taper",
                    "taper - the foam-sheet taper from the Spa Cover Details",
                    "Taper", _vm.Cover.TaperChoices)
    End Sub

    ''' <summary>One measurement row: letter, description, value box.</summary>
    Private Sub AddFieldRow(f As SpaField)
        Dim row As New DockPanel() With {.Margin = New Thickness(0, 2, 0, 2)}

        Dim letter As New TextBlock() With {
            .Text = f.Letter, .Width = 32, .FontWeight = FontWeights.Bold,
            .VerticalAlignment = VerticalAlignment.Center}
        DockPanel.SetDock(letter, Dock.Left)
        row.Children.Add(letter)

        Dim box As New TextBox() With {.Width = 80, .Tag = f}
        Bind(box, f)
        DockPanel.SetDock(box, Dock.Right)
        row.Children.Add(box)

        row.Children.Add(New TextBlock() With {
            .Text = f.Label, .TextTrimming = TextTrimming.CharacterEllipsis,
            .VerticalAlignment = VerticalAlignment.Center,
            .Margin = New Thickness(0, 0, 8, 0),
            .ToolTip = f.Label})

        _rows.Children.Add(row)
    End Sub

    ''' <summary>One cover question: description, dropdown.  The blank
    ''' row means not answered -- the key is simply never sent.</summary>
    Private Sub AddCoverRow(label As String, tip As String,
                            path As String, choices As String())
        Dim row As New DockPanel() With {.Margin = New Thickness(0, 2, 0, 2)}

        Dim box As New ComboBox() With {
            .Width = 96, .ItemsSource = choices, .ToolTip = tip}
        BindSelected(box, _vm.Cover, path)
        DockPanel.SetDock(box, Dock.Right)
        row.Children.Add(box)

        row.Children.Add(New TextBlock() With {
            .Text = label, .TextTrimming = TextTrimming.CharacterEllipsis,
            .VerticalAlignment = VerticalAlignment.Center,
            .Margin = New Thickness(0, 0, 8, 0),
            .ToolTip = tip})

        _rows.Children.Add(row)
    End Sub

    ' -------------------------------------------------------------- diagram
    Private Function BuildDiagram() As FrameworkElement
        Dim host As New Grid() With {.Margin = New Thickness(4, 8, 8, 8)}
        host.Children.Add(_image)
        host.Children.Add(_canvas)
        AddHandler host.SizeChanged, Sub() PlaceOverlay()
        Return host
    End Function

    Private Sub ShowShape(shape As SpaShape)
        _canvas.Children.Clear()
        _overlay.Clear()
        If shape Is Nothing Then Return

        Try
            Dim p = ShapeCatalog.ImagePath(shape.ImageFile)
            If File.Exists(p) Then
                Dim bmp As New BitmapImage()
                bmp.BeginInit()
                bmp.CacheOption = BitmapCacheOption.OnLoad
                bmp.UriSource = New Uri(p)
                bmp.EndInit()
                _image.Source = bmp
            End If
        Catch
            _image.Source = Nothing
        End Try

        For Each f In shape.Fields
            Dim box As New TextBox() With {
                .Width = 46, .Tag = f, .TextAlignment = TextAlignment.Center,
                .ToolTip = f.Letter & " - " & f.Label,
                .Background = New SolidColorBrush(Color.FromArgb(235, 255, 255, 255))}
            Bind(box, f)
            _canvas.Children.Add(box)
            _overlay.Add(box)
        Next

        For Each c In shape.Corners
            Dim ty As New ComboBox() With {
                .Width = 74, .ItemsSource = c.Treatments, .Tag = c,
                .ToolTip = c.Label,
                .Background = New SolidColorBrush(Color.FromArgb(235, 255, 255, 255))}
            BindSelected(ty, c, "Treatment")
            _canvas.Children.Add(ty)
            _overlay.Add(ty)
        Next

        PlaceOverlay()
    End Sub

    ''' <summary>
    ''' Positions are fractions of the picture, so the boxes stay on their
    ''' letters as the palette is resized. The image is Uniform-stretched,
    ''' so the drawn area has to be recovered from the aspect ratio rather
    ''' than assumed to fill the host.
    ''' </summary>
    Private Sub PlaceOverlay()
        If _image.Source Is Nothing Then Return
        Dim hostW = _canvas.ActualWidth
        Dim hostH = _canvas.ActualHeight
        If hostW <= 0 OrElse hostH <= 0 Then Return

        Dim iw = _image.Source.Width
        Dim ih = _image.Source.Height
        If iw <= 0 OrElse ih <= 0 Then Return

        Dim scale = Math.Min(hostW / iw, hostH / ih)
        Dim drawnW = iw * scale
        Dim drawnH = ih * scale
        Dim offX = (hostW - drawnW) / 2
        Dim offY = (hostH - drawnH) / 2

        For Each el In _overlay
            Dim fx As Double, fy As Double
            Dim f = TryCast(el.Tag, SpaField)
            If f IsNot Nothing Then
                fx = f.X : fy = f.Y
            Else
                Dim c = TryCast(el.Tag, SpaCorner)
                If c Is Nothing Then Continue For
                fx = c.X : fy = c.Y
            End If

            el.Measure(New Size(Double.PositiveInfinity, Double.PositiveInfinity))
            Dim w = If(el.DesiredSize.Width > 0, el.DesiredSize.Width, 46)
            Dim h = If(el.DesiredSize.Height > 0, el.DesiredSize.Height, 22)

            Canvas.SetLeft(el, offX + drawnW * fx - w / 2)
            Canvas.SetTop(el, offY + drawnH * fy - h / 2)
        Next
    End Sub

    ' --------------------------------------------------------------- binding
    Private Shared Sub Bind(box As TextBox, f As SpaField)
        BindText(box, f, "Value")
    End Sub

    Private Shared Sub BindText(box As TextBox, source As Object, path As String)
        Dim b As New Binding(path) With {
            .Source = source, .Mode = BindingMode.TwoWay,
            .UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged}
        box.SetBinding(TextBox.TextProperty, b)
    End Sub

    Private Shared Sub BindSelected(combo As ComboBox, source As Object, path As String)
        Dim b As New Binding(path) With {
            .Source = source, .Mode = BindingMode.TwoWay}
        combo.SetBinding(ComboBox.SelectedItemProperty, b)
    End Sub

    Private Shared Sub BindVisible(el As FrameworkElement, source As Object, path As String)
        Dim b As New Binding(path) With {
            .Source = source, .Mode = BindingMode.OneWay,
            .Converter = New BooleanToVisibilityConverter()}
        el.SetBinding(UIElement.VisibilityProperty, b)
    End Sub

End Class
