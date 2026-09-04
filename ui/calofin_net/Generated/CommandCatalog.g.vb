' SPDX-License-Identifier: GPL-3.0-or-later
'
' GENERATED FILE - DO NOT EDIT.  Your change will vanish.
'
'   written by : tools/gen_ui_data.py
'   from       : lisp/lazpanel/LAZPANEL.lsp  (lzp:*captions*,
'                lzp:*groups*) and ui/calofin_net/blurbs.txt
'   regenerate : python3 tools/gen_ui_data.py
'   checked by : python3 tools/gen_ui_data.py --check, which
'                make check runs
'
' The panel and the palette offer the same routines under the same
' captions because this file is the panel's own tables, transcribed.
' To add a tool: put it on LAZPANEL, write its blurb in blurbs.txt,
' and re-run the generator.

Imports System.Collections.Generic


''' <summary>
''' Every routine the palette offers, in the panel's own words.
'''
''' <para>Four views of one roster: <see cref="All"/> is every
''' command once, <see cref="Groups"/> is the four category
''' pages the Commands tab lists, <see cref="Pages"/> is the
''' whole tab strip including the job pages, and
''' <see cref="CaptionOf"/> resolves one name.</para>
''' </summary>
Public NotInheritable Class CommandCatalog

    Private Sub New()
    End Sub

    ''' <summary>One routine: the command, its caption and its
    ''' tooltip.</summary>
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

    ''' <summary>One column of a page: a heading and the commands
    ''' under it.  A heading of "" means the page is one plain
    ''' column, which is what the four category pages are.</summary>
    Public Structure Column
        Public ReadOnly Heading As String
        Public ReadOnly Commands As String()

        Public Sub New(heading As String, commands As String())
            Me.Heading = heading
            Me.Commands = commands
        End Sub
    End Structure

    ''' <summary>One page of the panel's tab strip.</summary>
    Public Structure Page
        Public ReadOnly Title As String
        Public ReadOnly Columns As Column()

        Public Sub New(title As String, columns As Column())
            Me.Title = title
            Me.Columns = columns
        End Sub
    End Structure

    ''' <summary>Every command once, alphabetically - the list
    ''' Find searches and the list an empty search shows.</summary>
    Public Shared ReadOnly All As Entry() = {
        New Entry("ABCDEF", "Rectangle plot", "Plot rectangle points"),
        New Entry("ABCURCHECK", "Perimeter continuity", "Grades how continuous a drawn perimeter is"),
        New Entry("ABCURCHECKSCAN", "Perimeter continuity, no marks", "ABCURCHECK without marking the drawing"),
        New Entry("ABFIND", "A/B stake ties", "Ties Pt.## back to the A and B survey stakes"),
        New Entry("ABHD", "Survey perimeter + bottom", "Fits a pool perimeter and bottom through surveyed points"),
        New Entry("ABHDCOVER", "Survey perimeter, no bottom", "ABHD for a cover sheet that stops at the perimeter"),
        New Entry("ABMOVE", "Move mis-taped point", "Moves a point, offering every mis-read tape it could be"),
        New Entry("ABPCHECK", "Survey point offsets", "ABHD's measuring half as a checker - how far each point is off the line"),
        New Entry("ADAB", "Organic shape points", "Freeform perimeter through surveyed points"),
        New Entry("ALTABCDEF", "Clockwise rectangle plot", "ABCDEF with the clockwise corner order"),
        New Entry("AUTOBEAD", "Bead offsets", "Offsets selected pool lines toward a clicked side"),
        New Entry("AUTODIM", "Auto dimension", "Automatic dimensioning"),
        New Entry("AUTODIMSIDEPOV", "Side-view dims", "Dimensions a side-view flight of steps"),
        New Entry("BPCALLOUT", "Bad point callout", "Rings clicked bad points and writes the callout"),
        New Entry("CABHD", "Perimeter-only fit", "ABHD's perimeter half, for a survey that runs past the pool"),
        New Entry("CCPRECHECK", "Tech flow chart", "Walks the Tech Flow Chart decision tree"),
        New Entry("CDCALLOUT", "Point-to-point cross dims", "Cross-dimensions from Pt.## to Pt.## by typed number"),
        New Entry("CDCREATE", "Lines to cross dims", "Turns every highlighted line into a cross dimension"),
        New Entry("CHECK", "Drawing check", "General drawing check"),
        New Entry("CONSTELLATION", "Points from cross dims", "Places points from the distances between them, inside a known box"),
        New Entry("CORNERSTP", "Corner step", "Corner step layout"),
        New Entry("COVERCHECK", "Cover review", "Cover check"),
        New Entry("COVERSCAN", "Cover scan", "Scan drawing for covers"),
        New Entry("CPERPPTS", "Curved perp points", "PERPPTS for a curved run"),
        New Entry("CUSTBLOCK", "Block from L/W/H", "Custom block in pictorial view from three typed sizes"),
        New Entry("DIMARCCHECK", "Arc endpoint check", "Dim arc endpoint check"),
        New Entry("DIMCHECK", "Dimension review", "Guided, one-at-a-time dimension review"),
        New Entry("DIMCONTEND", "Continue dim chains", "Chains a seed dimension out to every feature point"),
        New Entry("DIMSCAN", "Dimension scan", "Scan drawing for dimensions"),
        New Entry("DRONE", "Drone cleanup", "Drone cleanup routine"),
        New Entry("FITABHD", "Typed template fit", "Fits a typed pool template through surveyed points"),
        New Entry("FITABHDCOVER", "Typed template fit, no bottom", "FITABHD for a cover sheet - skips the bottom question"),
        New Entry("FLOORDIM", "Floor dims", "Floor dimensioning"),
        New Entry("HEMISTEP", "Hemi step", "Hemi step layout"),
        New Entry("LAZFORM", "Pool from a filled-in chart", "Fill the dimension chart in and draw the pool from it"),
        New Entry("LAZFORMCOVER", "Chart to pool, no bottom", "LAZFORM for a cover sheet - the pool-bottom gate closed"),
        New Entry("LAZSPA", "Spa from a filled-in chart", "LAZFORM's argument applied to SPA - fill the chart in and the spa is drawn"),
        New Entry("LAZSTEP", "Steps from a filled-in drawing", "Say how many steps, then fill in the drawing built for that count"),
        New Entry("LAZTXT", "The same form, drawn in tiles", "LAZFORM's chart built from DCL tiles instead of vectors"),
        New Entry("LHD", "Laser outline fit", "Laser-point outline fit, open or closed"),
        New Entry("LINCHECK", "Line checklist", "Line / text check"),
        New Entry("LINFINCHECK", "Liner finish review", "Full liner-finish drawing QA, guided"),
        New Entry("LINFINSCAN", "Liner finish scan", "The liner-finish QA as one scan"),
        New Entry("LINGUTTER", "Gut to perimeter, then pads", "Guts a highlighted area back to the pool, walking the outer face"),
        New Entry("LINGUTTERSCAN", "Gut scan, changes nothing", "LINGUTTER's report only - reads the drawing, changes nothing"),
        New Entry("LINTXTCHK", "Liner checklist text", "Places the vinyl-liner QA checklist as drawing text"),
        New Entry("LITECOVERSCAN", "Cover scan, no dims", "Cover rules only - skips the dimension audit"),
        New Entry("LITELINFINSCAN", "Liner scan, no dims", "Liner rules only - skips the dimension audit"),
        New Entry("LITESPACHECKSCAN", "Spa scan, no dims", "Spa rules only - skips the dimension audit"),
        New Entry("NORMIESTEP", "Normie step", "Normie step layout"),
        New Entry("OASIS", "Freeform pool", "Continuous-tangent pool drawn live from envelope and radii"),
        New Entry("PADDLE", "Paddle pads", "Paddle perimeter pads"),
        New Entry("PERPPTS", "Perpendicular points", "Perpendicular offset points along a line or curve"),
        New Entry("POINTRENAMER", "Renumber points in order", "Hands the survey point numbers back out in perimeter order"),
        New Entry("POOL", "Pool layout", "Full pool layout tool"),
        New Entry("POOLCOVER", "Pool layout, no bottom", "POOL for a cover sheet - the bottom question pre-answered No"),
        New Entry("POOLDEMO", "Worked pool example", "Draws a worked example pool end to end"),
        New Entry("POOLSIDE", "Pool side view", "POOL's longitudinal section on its own, from the floor run chain"),
        New Entry("SMARTFILLET", "Corner radius, previewed", "Fillet a corner after previewing every radius that fits"),
        New Entry("SOCONV", "SO survey onto our layers", "Puts an SO site-survey export onto the shop's layers in one pass"),
        New Entry("SPA", "Spa template", "Spa / hot-tub template layout"),
        New Entry("SPACHECK", "Spa sheet review", "Audits a spa sheet against what SPA draws"),
        New Entry("SPACHECKSCAN", "Spa sheet scan", "The spa sheet review as one scan"),
        New Entry("STAIRDIM", "Stair dims", "Stair dimensioning"),
        New Entry("STOCKCOVER", "Stock cover placement", "Replaces a highlighted perimeter with a stock cover drawing"),
        New Entry("TYDRN", "Text + point tidy-up", "Text, pool-point and anchor cleanup in one pass"),
        New Entry("TYLERDRONESUITE", "Drone suite: tidy, pad, CDIM", "The whole drone trace in one - TYDRN, then PADDLE, then CDIM"),
        New Entry("VSCONV", "VS export onto shop layers", "Remaps a VS survey export's numbered layers onto the shop's"),
        New Entry("WCALST", "Unroll curved band", "Unrolls a curved constant-width band flat, with darts"),
        New Entry("XFTCONV", "Survey import cleanup", "Cleans up a Leica XFT/DXF import or a site trace"),
        New Entry("XYPLOT", "X/Y offset plot", "Plot an X/Y sheet, twice: points, and dimensioned")
    }

    ''' <summary>The four category pages, which are the palette's
    ''' groups: lzp:*groups* files every tool into exactly one, so
    ''' this is not a second opinion about where a tool
    ''' belongs.</summary>
    Public Shared ReadOnly Groups As New Dictionary(Of String, Entry()) From {
        {"Layout", {
            New Entry("LAZFORM", "Pool from a filled-in chart", "Fill the dimension chart in and draw the pool from it"),
            New Entry("LAZTXT", "The same form, drawn in tiles", "LAZFORM's chart built from DCL tiles instead of vectors"),
            New Entry("LAZFORMCOVER", "Chart to pool, no bottom", "LAZFORM for a cover sheet - the pool-bottom gate closed"),
            New Entry("LAZSPA", "Spa from a filled-in chart", "LAZFORM's argument applied to SPA - fill the chart in and the spa is drawn"),
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
            New Entry("LINGUTTER", "Gut to perimeter, then pads", "Guts a highlighted area back to the pool, walking the outer face"),
            New Entry("LINGUTTERSCAN", "Gut scan, changes nothing", "LINGUTTER's report only - reads the drawing, changes nothing"),
            New Entry("PADDLE", "Paddle pads", "Paddle perimeter pads"),
            New Entry("AUTOBEAD", "Bead offsets", "Offsets selected pool lines toward a clicked side"),
            New Entry("LAZSTEP", "Steps from a filled-in drawing", "Say how many steps, then fill in the drawing built for that count"),
            New Entry("CORNERSTP", "Corner step", "Corner step layout"),
            New Entry("HEMISTEP", "Hemi step", "Hemi step layout"),
            New Entry("NORMIESTEP", "Normie step", "Normie step layout"),
            New Entry("SMARTFILLET", "Corner radius, previewed", "Fillet a corner after previewing every radius that fits"),
            New Entry("STOCKCOVER", "Stock cover placement", "Replaces a highlighted perimeter with a stock cover drawing"),
            New Entry("WCALST", "Unroll curved band", "Unrolls a curved constant-width band flat, with darts"),
            New Entry("CUSTBLOCK", "Block from L/W/H", "Custom block in pictorial view from three typed sizes")
        }},
        {"Points", {
            New Entry("ABCDEF", "Rectangle plot", "Plot rectangle points"),
            New Entry("ALTABCDEF", "Clockwise rectangle plot", "ABCDEF with the clockwise corner order"),
            New Entry("XYPLOT", "X/Y offset plot", "Plot an X/Y sheet, twice: points, and dimensioned"),
            New Entry("CONSTELLATION", "Points from cross dims", "Places points from the distances between them, inside a known box"),
            New Entry("ABFIND", "A/B stake ties", "Ties Pt.## back to the A and B survey stakes"),
            New Entry("ABMOVE", "Move mis-taped point", "Moves a point, offering every mis-read tape it could be"),
            New Entry("POINTRENAMER", "Renumber points in order", "Hands the survey point numbers back out in perimeter order"),
            New Entry("PERPPTS", "Perpendicular points", "Perpendicular offset points along a line or curve"),
            New Entry("CPERPPTS", "Curved perp points", "PERPPTS for a curved run"),
            New Entry("XFTCONV", "Survey import cleanup", "Cleans up a Leica XFT/DXF import or a site trace"),
            New Entry("SOCONV", "SO survey onto our layers", "Puts an SO site-survey export onto the shop's layers in one pass"),
            New Entry("VSCONV", "VS export onto shop layers", "Remaps a VS survey export's numbered layers onto the shop's"),
            New Entry("DRONE", "Drone cleanup", "Drone cleanup routine"),
            New Entry("TYDRN", "Text + point tidy-up", "Text, pool-point and anchor cleanup in one pass"),
            New Entry("TYLERDRONESUITE", "Drone suite: tidy, pad, CDIM", "The whole drone trace in one - TYDRN, then PADDLE, then CDIM")
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
        }}
    }

    ''' <summary>Every page of the panel's tab strip, in its order:
    ''' the job pages first, then the four categories.  A job page
    ''' carries a tool under the work it belongs to; a category
    ''' page answers what a tool IS.</summary>
    Public Shared ReadOnly Pages As Page() = {
        New Page("Pool", {
            New Column("Converters", {"XFTCONV", "SOCONV", "VSCONV"}),
            New Column("Shape", {"POOL", "POOLSIDE", "LAZFORM", "LAZTXT", "OASIS", "ABHD", "ADAB", "FITABHD"}),
            New Column("Points", {"ABFIND", "ABMOVE", "CDCREATE", "CDCALLOUT", "BPCALLOUT"}),
            New Column("Steps", {"LAZSTEP", "CORNERSTP", "HEMISTEP", "NORMIESTEP", "AUTOBEAD", "PERPPTS", "CPERPPTS"}),
            New Column("Dims & check", {"AUTODIM", "LINFINCHECK", "LINFINSCAN", "LITELINFINSCAN", "DIMCHECK", "DIMSCAN"})
        }),
        New Page("Cover", {
            New Column("Shape", {"POOLCOVER", "LAZFORMCOVER", "OASIS", "ABHDCOVER", "FITABHDCOVER", "STOCKCOVER", "CUSTBLOCK", "XFTCONV"}),
            New Column("Points", {"ABFIND", "ABMOVE", "CDCREATE", "CDCALLOUT", "BPCALLOUT"}),
            New Column("Pads, dims & check", {"LINGUTTER", "LINGUTTERSCAN", "PADDLE", "AUTODIM", "COVERCHECK", "COVERSCAN", "LITECOVERSCAN", "DIMCHECK", "DIMSCAN"})
        }),
        New Page("Spa", {
            New Column("Converters", {"XFTCONV", "SOCONV", "VSCONV"}),
            New Column("Shape, dims & check", {"SPA", "LAZSPA", "CUSTBLOCK", "AUTODIM", "SPACHECK", "SPACHECKSCAN", "LITESPACHECKSCAN", "DIMCHECK", "DIMSCAN"})
        }),
        New Page("Rest", {
            New Column("", {"POOLDEMO", "CABHD", "LHD", "SMARTFILLET", "WCALST", "ABCDEF", "ALTABCDEF", "XYPLOT", "DRONE", "TYDRN", "AUTODIMSIDEPOV", "STAIRDIM", "FLOORDIM", "DIMCONTEND", "CHECK", "DIMARCCHECK", "ABCURCHECK", "ABCURCHECKSCAN", "ABPCHECK", "LINCHECK", "LINTXTCHK", "CCPRECHECK", "POINTRENAMER", "CONSTELLATION", "TYLERDRONESUITE"})
        }),
        New Page("Layout", {
            New Column("", {"LAZFORM", "LAZTXT", "LAZFORMCOVER", "LAZSPA", "SPA", "POOL", "POOLCOVER", "POOLSIDE", "POOLDEMO", "OASIS", "FITABHD", "FITABHDCOVER", "ABHD", "ABHDCOVER", "ADAB", "CABHD", "LHD", "LINGUTTER", "LINGUTTERSCAN", "PADDLE", "AUTOBEAD", "LAZSTEP", "CORNERSTP", "HEMISTEP", "NORMIESTEP", "SMARTFILLET", "STOCKCOVER", "WCALST", "CUSTBLOCK"})
        }),
        New Page("Points", {
            New Column("", {"ABCDEF", "ALTABCDEF", "XYPLOT", "CONSTELLATION", "ABFIND", "ABMOVE", "POINTRENAMER", "PERPPTS", "CPERPPTS", "XFTCONV", "SOCONV", "VSCONV", "DRONE", "TYDRN", "TYLERDRONESUITE"})
        }),
        New Page("Dimensions", {
            New Column("", {"AUTODIM", "AUTODIMSIDEPOV", "STAIRDIM", "FLOORDIM", "DIMCONTEND", "CDCREATE", "CDCALLOUT", "BPCALLOUT"})
        }),
        New Page("Checking", {
            New Column("", {"CHECK", "DIMARCCHECK", "DIMCHECK", "DIMSCAN", "ABCURCHECK", "ABCURCHECKSCAN", "ABPCHECK", "LINCHECK", "LINFINCHECK", "LINFINSCAN", "LITELINFINSCAN", "COVERCHECK", "COVERSCAN", "LITECOVERSCAN", "SPACHECK", "SPACHECKSCAN", "LITESPACHECKSCAN", "LINTXTCHK", "CCPRECHECK"})
        })
    }

    ''' <summary>The caption for a command, or "" for a name the
    ''' panel does not carry.</summary>
    Public Shared Function CaptionOf(command As String) As String
        For Each e In All
            If String.Equals(e.Command, command, StringComparison.OrdinalIgnoreCase) Then Return e.Caption
        Next
        Return ""
    End Function

End Class
