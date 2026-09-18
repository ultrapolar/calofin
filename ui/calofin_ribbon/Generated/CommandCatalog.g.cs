// SPDX-License-Identifier: GPL-3.0-or-later
//
// GENERATED FILE - DO NOT EDIT.  Your change will vanish.
//
//   written by : tools/gen_ui_data.py
//   from       : lisp/lazpanel/LAZPANEL.lsp  (lzp:*captions*,
//                lzp:*groups*) and ui/calofin_net/blurbs.txt
//   regenerate : python3 tools/gen_ui_data.py
//   checked by : python3 tools/gen_ui_data.py --check, which
//                make check runs
//
// The ribbon and the VB palette's Commands tab offer the same
// routines under the same captions and the same categories,
// because both are generated from LAZPANEL's own tables -- this
// file carries only the category table, which is all the ribbon
// needs.  To add a tool: put it on LAZPANEL, write its blurb in
// blurbs.txt, and re-run the generator.

using System.Collections.Generic;

namespace Calofin.Ribbon
{
    /// <summary>
    /// The category panels the ribbon builds, in LAZPANEL's own
    /// words.  lzp:*groups* files every tool into exactly one, so
    /// this is not a second opinion about where a tool belongs --
    /// it is the VB palette's own Groups table, written again in
    /// C# by the same generator so the ribbon needs no reference
    /// to the VB assembly to read it.
    /// </summary>
    public static class CommandCatalog
    {
        /// <summary>One routine: the command, its caption and
        /// its tooltip.</summary>
        public readonly struct Entry
        {
            public readonly string Command;
            public readonly string Caption;
            public readonly string Blurb;

            public Entry(string command, string caption, string blurb)
            {
                Command = command;
                Caption = caption;
                Blurb = blurb;
            }
        }

        /// <summary>The category pages, keyed by LAZPANEL's own
        /// names.</summary>
        public static readonly Dictionary<string, Entry[]> Groups =
            new Dictionary<string, Entry[]>
        {
            { "Layout", new[]
            {
                new Entry("LAZFORM", "Pool from a filled-in chart", "Fill the dimension chart in and draw the pool from it"),
                new Entry("LAZTXT", "The same form, drawn in tiles", "LAZFORM's chart built from DCL tiles instead of vectors"),
                new Entry("LAZFORMCOVER", "Chart to pool, no bottom", "LAZFORM for a cover sheet - the pool-bottom gate closed"),
                new Entry("LAZSIDE", "Side view from a filled-in section", "Read the section, type the letters beside it, and POOLSIDE draws the side view"),
                new Entry("LAZSPA", "Spa from a filled-in chart", "LAZFORM's argument applied to SPA - fill the chart in and the spa is drawn"),
                new Entry("SPA", "Spa template", "Spa / hot-tub template layout"),
                new Entry("SPACOVCREATE", "Spa cover from the spa", "Offsets a selected spa outline into its cover and hinges it to the taper"),
                new Entry("POOL", "Pool layout", "Full pool layout tool"),
                new Entry("POOLCOVER", "Pool layout, no bottom", "POOL for a cover sheet - the bottom question pre-answered No"),
                new Entry("POOLSIDE", "Pool side view", "POOL's longitudinal section on its own, from the floor run chain"),
                new Entry("POOLDEMO", "Worked pool example", "Draws a worked example pool end to end"),
                new Entry("OASIS", "Freeform pool", "Continuous-tangent pool drawn live from envelope and radii"),
                new Entry("FITABHD", "Typed template fit", "Fits a typed pool template through surveyed points"),
                new Entry("FITABHDCOVER", "Typed template fit, no bottom", "FITABHD for a cover sheet - skips the bottom question"),
                new Entry("ABHD", "Survey perimeter + bottom", "Fits a pool perimeter and bottom through surveyed points"),
                new Entry("ABHDCOVER", "Survey perimeter, no bottom", "ABHD for a cover sheet that stops at the perimeter"),
                new Entry("SIMPABHD", "Survey perimeter, no settings", "ABHD with nothing to decide: five ready-made perimeters, keep one"),
                new Entry("ADAB", "Organic shape points", "Freeform perimeter through surveyed points"),
                new Entry("CABHD", "Perimeter-only fit", "ABHD's perimeter half, for a survey that runs past the pool"),
                new Entry("LHD", "Laser outline fit", "Laser-point outline fit, open or closed"),
                new Entry("ABLOBF", "Open best-fit run", "Fits an OPEN run of arcs and lines through points, between two ends you pick"),
                new Entry("LINGUTTER", "Gut to perimeter, then pads", "Guts a highlighted area back to the pool, walking the outer face"),
                new Entry("LINGUTTERSCAN", "Gut scan, changes nothing", "LINGUTTER's report only - reads the drawing, changes nothing"),
                new Entry("PADDLE", "Paddle pads", "Paddle perimeter pads"),
                new Entry("MOHAMADDLE", "Pads, pick a size", "PADDLE's perimeter pads with a size pick first - 24in or 36in"),
                new Entry("UPADOVER", "Pads a run of wall", "Pads a stretch of wall between two points, or the whole of a line or polyline - no overlap, no gap"),
                new Entry("AUTOBEAD", "Bead offsets", "Offsets selected pool lines toward a clicked side"),
                new Entry("LAZSTEP", "Steps from a filled-in drawing", "Type the step count and the drawing follows it - fill it in and the steps are drawn"),
                new Entry("CORNERSTP", "Corner step", "Corner step layout"),
                new Entry("HEMISTEP", "Hemi step", "Hemi step layout"),
                new Entry("NORMIESTEP", "Normie step", "Normie step layout"),
                new Entry("SMARTFILLET", "Corner radius, previewed", "Fillet a corner after previewing every radius that fits"),
                new Entry("HONEFILLET", "Corner radius, honed", "Bracket two of SMARTFILLET's radii and hone between them at half inches"),
                new Entry("STOCKCOVER", "Stock cover placement", "Replaces a highlighted perimeter with a stock cover drawing"),
                new Entry("WCALST", "Unroll curved band", "Unrolls a curved constant-width band flat, with darts"),
                new Entry("CUSTBLOCK", "Block from L/W/H", "Custom block in pictorial view from three typed sizes"),
                new Entry("SQUAREUP", "Square up to the perimeter", "Turns a highlighted drawing until its perimeter's longest wall (or span) is horizontal"),
            } },
            { "Points", new[]
            {
                new Entry("ABCDEF", "Rectangle plot", "Plot rectangle points"),
                new Entry("ALTABCDEF", "Clockwise rectangle plot", "ABCDEF with the clockwise corner order"),
                new Entry("XYPLOT", "X/Y offset plot", "Plot an X/Y sheet, twice: points, and dimensioned"),
                new Entry("CONSTELLATION", "Points from cross dims", "Places points from the distances between them, inside a known box"),
                new Entry("LOBF", "Line of best fit", "Fits a construction line through points that should be on one line"),
                new Entry("ABFIND", "A/B stake ties", "Ties Pt.## back to the A and B survey stakes"),
                new Entry("ABMOVE", "Move mis-taped point", "Moves a point, offering every mis-read tape it could be"),
                new Entry("ABPCREATE", "Create a missing point", "Plots a point that is not there yet from the two readings it was taped at"),
                new Entry("POINTRENAMER", "Renumber points in order", "Hands the survey point numbers back out in perimeter order"),
                new Entry("PERPPTS", "Perpendicular points", "Perpendicular offset points along a line or curve"),
                new Entry("CPERPPTS", "Curved perp points", "PERPPTS for a curved run"),
                new Entry("PERPMARK", "Measured wall offsets", "Name a survey point, type what it measured: circle, perpendicular, dimension"),
                new Entry("DRONE", "Drone cleanup", "Drone cleanup routine"),
                new Entry("TYDRN", "Text + point tidy-up", "Text, pool-point and anchor cleanup in one pass"),
                new Entry("TYLERDRONESUITE", "Drone suite: tidy, pad, CDIM", "The whole drone trace in one - TYDRN, then PADDLE, then CDIM"),
            } },
            { "Dimensions", new[]
            {
                new Entry("AUTODIM", "Auto dimension", "Automatic dimensioning"),
                new Entry("AUTODIMSIDEPOV", "Side-view dims", "Dimensions a side-view flight of steps"),
                new Entry("STAIRDIM", "Stair dims", "Stair dimensioning"),
                new Entry("FLOORDIM", "Floor dims", "Floor dimensioning"),
                new Entry("DIMCONTEND", "Continue dim chains", "Chains a seed dimension out to every feature point"),
                new Entry("CDCREATE", "Lines to cross dims", "Turns every highlighted line into a cross dimension"),
                new Entry("CDCALLOUT", "Point-to-point cross dims", "Cross-dimensions from Pt.## to Pt.## by typed number"),
                new Entry("BPCALLOUT", "Bad point callout", "Rings clicked bad points and writes the callout"),
                new Entry("DIMSTAMP", "Stamp dimension text", "Click a point, type 4'4.5 or 44.5; stamps it canonically, an on-screen ruler picks the next"),
                new Entry("DRONOTE", "Drone photo review note", "Places a canned drone-photo review note - diving board, hidden anchors or slide sketch - at a picked point"),
                new Entry("CLEARDIM", "Clear crowded dim text", "Slides dimension text along its own dimension line until it is readable"),
                new Entry("CLEARDIMSCAN", "Crowded dim text scan", "Names the dimension text CLEARDIM would move, and moves nothing"),
            } },
            { "Converters", new[]
            {
                new Entry("XFTCONV", "Survey import cleanup", "Cleans up a Leica XFT/DXF import or a site trace"),
                new Entry("SOCONV", "SO survey onto our layers", "Puts an SO site-survey export onto the shop's layers in one pass"),
                new Entry("VSCONV", "VS export onto shop layers", "Remaps a VS survey export's numbered layers onto the shop's"),
                new Entry("G2MCONV", "G2M plan onto shop layers", "Puts a G2M architectural pool plan onto the shop's layers and styles"),
                new Entry("XFTRECONV", "Import cleanup, undone", "Undoes an XFTCONV run - the markers and text back, and the scale with them"),
                new Entry("SORECONV", "SO conversion, undone", "Undoes a SOCONV run - every object back on the export's own layers"),
                new Entry("VSRECONV", "VS conversion, undone", "Undoes a VSCONV run - layers, properties and the dimension overrides"),
                new Entry("G2MRECONV", "G2M conversion, undone", "Undoes a G2MCONV run - layers, appearance, text and dimension styles"),
            } },
            { "Checking", new[]
            {
                new Entry("CHECK", "Drawing check", "General drawing check"),
                new Entry("DIMARCCHECK", "Arc endpoint check", "Dim arc endpoint check"),
                new Entry("DIMCHECK", "Dimension review", "Guided, one-at-a-time dimension review"),
                new Entry("DIMSCAN", "Dimension scan", "Scan drawing for dimensions"),
                new Entry("ABCURCHECK", "Perimeter continuity", "Grades how continuous a drawn perimeter is"),
                new Entry("ABCURCHECKSCAN", "Perimeter continuity, no marks", "ABCURCHECK without marking the drawing"),
                new Entry("OLAUTO", "Overlay two perimeters", "Best-fit overlay of a new perimeter on the original, worst error dimensioned"),
                new Entry("ABPCHECK", "Survey point offsets", "ABHD's measuring half as a checker - how far each point is off the line"),
                new Entry("LINCHECK", "Line checklist", "Line / text check"),
                new Entry("LINFINCHECK", "Liner finish review", "Full liner-finish drawing QA, guided"),
                new Entry("LINFINSCAN", "Liner finish scan", "The liner-finish QA as one scan"),
                new Entry("LITELINFINSCAN", "Liner scan, no dims", "Liner rules only - skips the dimension audit"),
                new Entry("COVERCHECK", "Cover review", "Cover check"),
                new Entry("COVERSCAN", "Cover scan", "Scan drawing for covers"),
                new Entry("LITECOVERSCAN", "Cover scan, no dims", "Cover rules only - skips the dimension audit"),
                new Entry("SPACHECK", "Spa sheet review", "Audits a spa sheet against what SPA draws"),
                new Entry("SPACHECKSCAN", "Spa sheet scan", "The spa sheet review as one scan"),
                new Entry("LITESPACHECKSCAN", "Spa scan, no dims", "Spa rules only - skips the dimension audit"),
                new Entry("LINTXTCHK", "Liner checklist text", "Places the vinyl-liner QA checklist as drawing text"),
                new Entry("CCPRECHECK", "Tech flow chart", "Walks the Tech Flow Chart decision tree"),
                new Entry("LAZDIAG", "Error report for the last failure", "Write the last failure out as a DXF to send in - and, with nothing to report, prove that path works"),
                new Entry("LAZLOG", "What every command has done lately", "Every calofin command that finished, was backed out of or FAILED - the log a report's history comes from"),
            } },
        };
    }
}
