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
''' The four groups mirror LAZPANEL's category pages -- lzp:*groups* in
''' lisp/lazpanel/LAZPANEL.lsp is the source of truth for what belongs
''' where, and the captions are its lzp:*captions* text, so the palette
''' and the DCL panel file every tool the same way. Off the list on
''' purpose: LAZPANEL itself (a panel launcher inside a palette is
''' noise), everything held back from the shared build (cal:*held-back*
''' in CALOFIN-LOADER.lsp -- LISPLAB), the satellites LAZPANEL already
''' leaves off, and the deprecated acady matcher. Adding a routine is a
''' line here -- and a matching line in calofin.lsp's probe list.
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
            New Entry("LAZFORM", "Pool from a filled-in chart", "Fill the dimension chart in and draw the pool from it"),
            New Entry("LAZTXT", "The same form, drawn in tiles", "LAZFORM's chart built from DCL tiles instead of vectors"),
            New Entry("LAZFORMCOVER", "Chart to pool, no bottom", "LAZFORM for a cover sheet - the pool-bottom gate closed"),
            New Entry("LAZSPA", "Spa from a filled-in chart", "LAZFORM's argument applied to SPA - fill the chart in and the spa is drawn"),
            New Entry("LAZSTEP", "Steps from a filled-in drawing", "Say how many steps, then fill in the drawing built for that count"),
            New Entry("SPA", "Spa template", "Spa / hot-tub template layout"),
            New Entry("POOL", "Pool layout", "Full pool layout tool"),
            New Entry("POOLCOVER", "Pool layout, no bottom", "POOL for a cover sheet - the bottom question pre-answered No"),
            New Entry("POOLSIDE", "Pool side view", "POOL's longitudinal section on its own, from the floor run chain"),
            New Entry("POOLDEMO", "Worked pool example", "Draws a worked example pool end to end"),
            New Entry("OASIS", "Freeform pool", "Continuous-tangent pool drawn live from envelope and radii"),
            New Entry("FITABHD", "Typed template fit", "Fits a typed pool template through surveyed points"),
            New Entry("FITABHDCOVER", "Typed template fit, no bottom", "FITABHD for a cover sheet - skips the bottom question"),
            New Entry("ABHD", "Survey perimeter + bottom", "Fits a pool perimeter and bottom through surveyed points"),
            New Entry("ABHDCOVER", "Survey perimeter, no bottom", "ABHD for a cover sheet that stops at the perimeter"),
            New Entry("ADAB", "Organic shape points", "Freeform perimeter through surveyed points"),
            New Entry("CABHD", "Perimeter-only fit", "ABHD's perimeter half, for a survey that runs past the pool"),
            New Entry("LHD", "Laser outline fit", "Laser-point outline fit, open or closed"),
            New Entry("PADDLE", "Paddle pads", "Paddle perimeter pads"),
            New Entry("LINGUTTER", "Gut to perimeter, then pads", "Guts a highlighted area back to the pool, walking the outer face"),
            New Entry("LINGUTTERSCAN", "Gut scan, changes nothing", "LINGUTTER's report only - reads the drawing, changes nothing"),
            New Entry("AUTOBEAD", "Bead offsets", "Offsets selected pool lines toward a clicked side"),
            New Entry("CORNERSTP", "Corner step", "Corner step layout"),
            New Entry("HEMISTEP", "Hemi step", "Hemi step layout"),
            New Entry("NORMIESTEP", "Normie step", "Normie step layout"),
            New Entry("SMARTFILLET", "Corner radius, previewed", "Fillet a corner after previewing every radius that fits"),
            New Entry("STOCKCOVER", "Stock cover placement", "Replaces a highlighted perimeter with a stock cover drawing"),
            New Entry("WCALST", "Unroll curved band", "Unrolls a curved constant-width band flat, with darts"),
            New Entry("CUSTBLOCK", "Block from L/W/H", "Custom block in pictorial view from three typed sizes")
        }},
        {"Checking", {
            New Entry("CHECK", "Drawing check", "General drawing check"),
            New Entry("DIMARCCHECK", "Arc endpoint check", "Dim arc endpoint check"),
            New Entry("DIMCHECK", "Dimension review", "Guided, one-at-a-time dimension review"),
            New Entry("DIMSCAN", "Dimension scan", "Scan drawing for dimensions"),
            New Entry("ABCURCHECK", "Perimeter continuity", "Grades how continuous a drawn perimeter is"),
            New Entry("ABCURCHECKSCAN", "Perimeter continuity, no marks", "ABCURCHECK without marking the drawing"),
            New Entry("ABPCHECK", "Survey point offsets", "ABHD's measuring half as a checker - how far each point is off the line"),
            New Entry("LINCHECK", "Line checklist", "Line / text check"),
            New Entry("LINFINCHECK", "Liner finish review", "Full liner-finish drawing QA, guided"),
            New Entry("LINFINSCAN", "Liner finish scan", "The liner-finish QA as one scan"),
            New Entry("LITELINFINSCAN", "Liner scan, no dims", "Liner rules only - skips the dimension audit"),
            New Entry("COVERCHECK", "Cover review", "Cover check"),
            New Entry("COVERSCAN", "Cover scan", "Scan drawing for covers"),
            New Entry("LITECOVERSCAN", "Cover scan, no dims", "Cover rules only - skips the dimension audit"),
            New Entry("SPACHECK", "Spa sheet review", "Audits a spa sheet against what SPA draws"),
            New Entry("SPACHECKSCAN", "Spa sheet scan", "The spa sheet review as one scan"),
            New Entry("LITESPACHECKSCAN", "Spa scan, no dims", "Spa rules only - skips the dimension audit"),
            New Entry("LINTXTCHK", "Liner checklist text", "Places the vinyl-liner QA checklist as drawing text"),
            New Entry("CCPRECHECK", "Tech flow chart", "Walks the Tech Flow Chart decision tree")
        }},
        {"Dimensions", {
            New Entry("AUTODIM", "Auto dimension", "Automatic dimensioning"),
            New Entry("AUTODIMSIDEPOV", "Side-view dims", "Dimensions a side-view flight of steps"),
            New Entry("STAIRDIM", "Stair dims", "Stair dimensioning"),
            New Entry("FLOORDIM", "Floor dims", "Floor dimensioning"),
            New Entry("DIMCONTEND", "Continue dim chains", "Chains a seed dimension out to every feature point"),
            New Entry("CDCREATE", "Lines to cross dims", "Turns every highlighted line into a cross dimension"),
            New Entry("CDCALLOUT", "Point-to-point cross dims", "Cross-dimensions from Pt.## to Pt.## by typed number"),
            New Entry("BPCALLOUT", "Bad point callout", "Rings clicked bad points and writes the callout")
        }},
        {"Points", {
            New Entry("ABCDEF", "Rectangle plot", "Plot rectangle points"),
            New Entry("ALTABCDEF", "Clockwise rectangle plot", "ABCDEF with the clockwise corner order"),
            New Entry("XYPLOT", "X/Y offset plot", "Plot an X/Y sheet, twice: points, and dimensioned"),
            New Entry("ABFIND", "A/B stake ties", "Ties Pt.## back to the A and B survey stakes"),
            New Entry("ABMOVE", "Move mis-taped point", "Moves a point, offering every mis-read tape it could be"),
            New Entry("PERPPTS", "Perpendicular points", "Perpendicular offset points along a line or curve"),
            New Entry("CPERPPTS", "Curved perp points", "PERPPTS for a curved run"),
            New Entry("POINTRENAMER", "Renumber points in order", "Hands the survey point numbers back out in perimeter order"),
            New Entry("XFTCONV", "Leica import cleanup", "Cleans up Leica XFT/DXF survey imports"),
            New Entry("DRONE", "Drone cleanup", "Drone cleanup routine"),
            New Entry("TYDRN", "Text + point tidy-up", "Text, pool-point and anchor cleanup in one pass")
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
