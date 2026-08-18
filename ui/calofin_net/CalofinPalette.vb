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
            _ps.AddVisual("Spa", New SpaFormView())
            _ps.AddVisual("Pool bottom", New PoolFormView())
        End If
        _ps.Visible = True
    End Sub

End Class


''' <summary>
''' The catalog of routines the palette offers.
'''
''' Grouped the way the drafter thinks about them rather than by which
''' branch they happen to live on. Adding a routine is a line here.
''' </summary>
Public NotInheritable Class CommandCatalog

    Public Structure Entry
        Public ReadOnly Command As String
        Public ReadOnly Caption As String
        Public ReadOnly Blurb As String

        Public Sub New(command As String, caption As String, blurb As String)
            Me.Command = command
            Me.Caption = caption
            Me.Blurb = blurb
        End Sub
    End Structure

    Public Shared ReadOnly Groups As New Dictionary(Of String, Entry()) From {
        {"Layout", {
            New Entry("SPA", "Spa template", "Spa / hot-tub template layout"),
            New Entry("POOL", "Pool layout", "Full pool layout tool"),
            New Entry("POOLDEMO", "Pool demo", "Worked pool example"),
            New Entry("ABHD", "Pool fit (ABHD)", "Pool perimeter fit"),
            New Entry("LHD", "Laser fit (LHD)", "Laser-point outline fit, open or closed"),
            New Entry("ABCDEF", "Rectangle plot", "Plot rectangle points"),
            New Entry("PADDLE", "Paddle pads", "Paddle perimeter pads"),
            New Entry("AUTOBEAD", "Auto bead", "Bead placement")
        }},
        {"Checking", {
            New Entry("CHECK", "Drawing check", "General drawing check"),
            New Entry("LINCHECK", "Line check", "Line / text check"),
            New Entry("DIMCHECK", "Dim check", "Dimension check"),
            New Entry("DIMSCAN", "Dim scan", "Scan drawing for dimensions"),
            New Entry("COVERCHECK", "Cover check", "Cover check"),
            New Entry("COVERSCAN", "Cover scan", "Scan drawing for covers"),
            New Entry("LINTXTCHK", "Pool checklist", "Line/text pool checklist"),
            New Entry("MATCHSTD", "Match standard", "Match against standards"),
            New Entry("ACADY-SCAN", "Standards scan", "Scan the standards folder")
        }},
        {"Dimensions", {
            New Entry("AUTODIM", "Auto dimension", "Automatic dimensioning"),
            New Entry("STAIRDIM", "Stair dims", "Stair dimensioning"),
            New Entry("FLOORDIM", "Floor dims", "Floor dimensioning"),
            New Entry("DIMCONTEND", "Continue dim", "Continue a dimension"),
            New Entry("DIMARCCHECK", "Arc endpoint check", "Dim arc endpoint check")
        }},
        {"Points", {
            New Entry("PERPPTS", "Perpendicular points", "Perpendicular points"),
            New Entry("TYDRN", "Tydrn", "Tydrn routine"),
            New Entry("CORNERSTP", "Corner step", "Corner step"),
            New Entry("HEMISTEP", "Hemi step", "Hemi step"),
            New Entry("WCALST", "Wcalst", "Wcalst routine"),
            New Entry("ADAB", "Adab", "Organic shape points")
        }}
    }

End Class


''' <summary>
''' The Commands tab: a scrolling column of grouped buttons.
'''
''' Buttons for routines that are not loaded are disabled rather than
''' hidden, so the palette is honest about what this drawing can do and
''' stays useful before every branch has been consolidated.
''' </summary>
Public Class CommandsTab
    Inherits UserControl

    Private ReadOnly _buttons As New List(Of Button)

    Public Sub New()
        Dim root As New DockPanel()

        Dim refresh As New Button() With {
            .Content = "Refresh availability",
            .Margin = New Thickness(8, 8, 8, 4),
            .Padding = New Thickness(6, 3, 6, 3)
        }
        AddHandler refresh.Click, Sub() UpdateAvailability()
        DockPanel.SetDock(refresh, Dock.Top)
        root.Children.Add(refresh)

        Dim stack As New StackPanel() With {.Margin = New Thickness(8, 0, 8, 8)}

        For Each grp In CommandCatalog.Groups
            stack.Children.Add(New TextBlock() With {
                .Text = grp.Key,
                .FontWeight = FontWeights.Bold,
                .Margin = New Thickness(0, 10, 0, 4)
            })

            For Each entry In grp.Value
                Dim cmd = entry.Command
                Dim b As New Button() With {
                    .Content = entry.Caption,
                    .ToolTip = entry.Blurb & "  (" & cmd & ")",
                    .Tag = cmd,
                    .Margin = New Thickness(0, 2, 0, 2),
                    .Padding = New Thickness(6, 4, 6, 4),
                    .HorizontalContentAlignment = HorizontalAlignment.Left
                }
                AddHandler b.Click, Sub() RunCommand(cmd)
                _buttons.Add(b)
                stack.Children.Add(b)
            Next
        Next

        root.Children.Add(New ScrollViewer() With {
            .VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            .Content = stack
        })

        Content = root
        UpdateAvailability()
    End Sub

    ''' <summary>
    ''' A command cannot be started while the palette holds the thread, so
    ''' the name is queued on the document and runs once we yield.
    ''' </summary>
    Private Shared Sub RunCommand(command As String)
        Dim doc = AcadApp.DocumentManager.MdiActiveDocument
        If doc Is Nothing Then Return
        doc.SendStringToExecute("_." & command & vbLf, True, False, True)
    End Sub

    ''' <summary>
    ''' Asks Lisp which C: functions are actually defined. If the probe
    ''' itself is unavailable -- calofin.lsp not loaded yet -- every button
    ''' is left enabled: a palette that wrongly greys everything out is
    ''' worse than one that lets a command report its own absence.
    ''' </summary>
    Public Sub UpdateAvailability()
        Dim known As HashSet(Of String) = Nothing
        Try
            known = LispProbe.DefinedCommands()
        Catch
            known = Nothing
        End Try

        For Each b In _buttons
            If known Is Nothing Then
                b.IsEnabled = True
            Else
                Dim cmd = CStr(b.Tag)
                b.IsEnabled = known.Contains(cmd.ToUpperInvariant())
            End If
        Next
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
