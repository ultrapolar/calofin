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
//
// A FEATURED routine has a glyph of its own, drawn by
// tools/gen_ribbon_icons.py off this same list, and wears it
// either on a full-height button or on an ordinary row; the
// rest are plain text buttons.  A ribbon is only faster than a
// list where a drafter knows the shape, and that is a thing
// you learn about tools you run -- so the list is short and
// editorial: gen_ui_data.FEATURED.
//
// Variants ride in their primary's dropdown rather than taking a
// button of their own -- POOLCOVER under POOL, XFTRECONV under
// XFTCONV -- which is what fits 94 commands onto five ribbon
// panels without hiding any of them.  Which is a variant of what
// is derived from the roster by gen_ui_data.variant_of; see the
// rules there.

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

        /// <summary>One button on a panel: the routine on its face,
        /// and the variants of that routine behind its dropdown.
        /// No variants means a plain button, not a split one.
        ///
        /// HasIcon says a glyph was drawn for this routine and
        /// sits beside the assembly as cmd-<name>-16/32.png;
        /// IsLarge says it wears it on a full-height button
        /// rather than an ordinary row.  IsLarge implies
        /// HasIcon -- only a routine with a picture can be
        /// large.  Both come off gen_ui_data.FEATURED, which
        /// tools/gen_ribbon_icons.py reads too, so a button can
        /// never be left asking for a picture nobody drew.
        /// </summary>
        public readonly struct Item
        {
            public readonly Entry Primary;
            public readonly Entry[] Variants;
            public readonly bool HasIcon;
            public readonly bool IsLarge;

            public Item(Entry primary, Entry[] variants,
                        bool hasIcon, bool isLarge)
            {
                Primary = primary;
                Variants = variants;
                HasIcon = hasIcon;
                IsLarge = isLarge;
            }
        }

        /// <summary>The category panels, keyed by LAZPANEL's own
        /// names.  Every command in a category appears exactly once
        /// across its Items -- on a face or in a dropdown.</summary>
        public static readonly Dictionary<string, Item[]> Panels =
            new Dictionary<string, Item[]>
        {
            { "Layout", new[]
            {
                new Item(new Entry("LAZFORM", "Pool from a filled-in chart", "Fill the dimension chart in and draw the pool from it"), new[]
                {
                    new Entry("LAZTXT", "The same form, drawn in tiles", "LAZFORM's chart built from DCL tiles instead of vectors"),
                    new Entry("LAZFORMCOVER", "Chart to pool, no bottom", "LAZFORM for a cover sheet - the pool-bottom gate closed"),
                }, false, false),
                new Item(new Entry("LAZSIDE", "Side view from a filled-in section", "Read the section, type the letters beside it, and POOLSIDE draws the side view"), new Entry[0], false, false),
                new Item(new Entry("LAZSPA", "Spa from a filled-in chart", "LAZFORM's argument applied to SPA - fill the chart in and the spa is drawn"), new Entry[0], false, false),
                new Item(new Entry("SPA", "Spa template", "Spa / hot-tub template layout"), new Entry[0], true, true),
                new Item(new Entry("SPACOVCREATE", "Spa cover from the spa", "Offsets a selected spa outline into its cover and hinges it to the taper"), new Entry[0], false, false),
                new Item(new Entry("POOL", "Pool layout", "Full pool layout tool"), new[]
                {
                    new Entry("POOLCOVER", "Pool layout, no bottom", "POOL for a cover sheet - the bottom question pre-answered No"),
                    new Entry("POOLDEMO", "Worked pool example", "Draws a worked example pool end to end"),
                }, true, true),
                new Item(new Entry("POOLSIDE", "Pool side view", "POOL's longitudinal section on its own, from the floor run chain"), new Entry[0], false, false),
                new Item(new Entry("OASIS", "Freeform pool", "Continuous-tangent pool drawn live from envelope and radii"), new Entry[0], true, true),
                new Item(new Entry("FITABHD", "Typed template fit", "Fits a typed pool template through surveyed points"), new[]
                {
                    new Entry("FITABHDCOVER", "Typed template fit, no bottom", "FITABHD for a cover sheet - skips the bottom question"),
                }, false, false),
                new Item(new Entry("ABHD", "Survey perimeter + bottom", "Fits a pool perimeter and bottom through surveyed points"), new[]
                {
                    new Entry("ABHDCOVER", "Survey perimeter, no bottom", "ABHD for a cover sheet that stops at the perimeter"),
                    new Entry("SIMPABHD", "Survey perimeter, no settings", "ABHD with nothing to decide: five ready-made perimeters, keep one"),
                    new Entry("CABHD", "Perimeter-only fit", "ABHD's perimeter half, for a survey that runs past the pool"),
                }, true, true),
                new Item(new Entry("ADAB", "Organic shape points", "Freeform perimeter through surveyed points"), new Entry[0], false, false),
                new Item(new Entry("LHD", "Laser outline fit", "Laser-point outline fit, open or closed"), new Entry[0], false, false),
                new Item(new Entry("ABLOBF", "Open best-fit run", "Fits an OPEN run of arcs and lines through points, between two ends you pick"), new Entry[0], false, false),
                new Item(new Entry("LINGUTTER", "Gut to perimeter, then pads", "Guts a highlighted area back to the pool, walking the outer face"), new[]
                {
                    new Entry("LINGUTTERSCAN", "Gut scan, changes nothing", "LINGUTTER's report only - reads the drawing, changes nothing"),
                }, false, false),
                new Item(new Entry("PADDLE", "Paddle pads", "Paddle perimeter pads"), new[]
                {
                    new Entry("MOHAMADDLE", "Pads, pick a size", "PADDLE's perimeter pads with a size pick first - 24in or 36in"),
                }, true, true),
                new Item(new Entry("UPADOVER", "Pads a run of wall", "Pads a stretch of wall between two points, or the whole of a line or polyline - no overlap, no gap"), new Entry[0], false, false),
                new Item(new Entry("AUTOBEAD", "Bead offsets", "Offsets selected pool lines toward a clicked side"), new Entry[0], false, false),
                new Item(new Entry("LAZSTEP", "Steps from a filled-in drawing", "Type the step count and the drawing follows it - fill it in and the steps are drawn"), new Entry[0], true, true),
                new Item(new Entry("CORNERSTP", "Corner step", "Corner step layout"), new Entry[0], true, true),
                new Item(new Entry("HEMISTEP", "Hemi step", "Hemi step layout"), new Entry[0], true, true),
                new Item(new Entry("NORMIESTEP", "Normie step", "Normie step layout"), new Entry[0], true, true),
                new Item(new Entry("SMARTFILLET", "Corner radius, previewed", "Fillet a corner after previewing every radius that fits"), new[]
                {
                    new Entry("HONEFILLET", "Corner radius, honed", "Bracket two of SMARTFILLET's radii and hone between them at half inches"),
                }, false, false),
                new Item(new Entry("STOCKCOVER", "Stock cover placement", "Replaces a highlighted perimeter with a stock cover drawing"), new Entry[0], false, false),
                new Item(new Entry("WCALST", "Unroll curved band", "Unrolls a curved constant-width band flat, with darts"), new Entry[0], false, false),
                new Item(new Entry("CUSTBLOCK", "Block from L/W/H", "Custom block in pictorial view from three typed sizes"), new Entry[0], true, true),
                new Item(new Entry("SQUAREUP", "Square up to the perimeter", "Turns a highlighted drawing until its perimeter's longest wall (or span) is horizontal"), new Entry[0], false, false),
                new Item(new Entry("OSR", "Restore my object snaps", "Puts your object snaps back to the preset you chose in Options (LAZSET) - one word, no questions"), new Entry[0], false, false),
            } },
            { "Points", new[]
            {
                new Item(new Entry("ABCDEF", "Rectangle plot", "Plot rectangle points"), new[]
                {
                    new Entry("ALTABCDEF", "Clockwise rectangle plot", "ABCDEF with the clockwise corner order"),
                }, false, false),
                new Item(new Entry("XYPLOT", "X/Y offset plot", "Plot an X/Y sheet, twice: points, and dimensioned"), new Entry[0], false, false),
                new Item(new Entry("CONSTELLATION", "Points from cross dims", "Places points from the distances between them, inside a known box"), new Entry[0], false, false),
                new Item(new Entry("LOBF", "Line of best fit", "Fits a construction line through points that should be on one line"), new Entry[0], false, false),
                new Item(new Entry("ABFIND", "A/B stake ties", "Ties Pt.## back to the A and B survey stakes"), new Entry[0], true, true),
                new Item(new Entry("ABMOVE", "Move mis-taped point", "Moves a point, offering every mis-read tape it could be"), new Entry[0], true, true),
                new Item(new Entry("ABPCREATE", "Create a missing point", "Plots a point that is not there yet from the two readings it was taped at"), new Entry[0], false, false),
                new Item(new Entry("POINTRENAMER", "Renumber points in order", "Hands the survey point numbers back out in perimeter order"), new Entry[0], false, false),
                new Item(new Entry("PERPPTS", "Perpendicular points", "Perpendicular offset points along a line or curve"), new[]
                {
                    new Entry("CPERPPTS", "Curved perp points", "PERPPTS for a curved run"),
                }, true, true),
                new Item(new Entry("PERPMARK", "Measured wall offsets", "Name a survey point, type what it measured: circle, perpendicular, dimension"), new Entry[0], false, false),
                new Item(new Entry("DRONE", "Drone cleanup", "Drone cleanup routine"), new Entry[0], false, false),
                new Item(new Entry("TYDRN", "Text + point tidy-up", "Text, pool-point and anchor cleanup in one pass"), new Entry[0], false, false),
                new Item(new Entry("TYLERDRONESUITE", "Drone suite: tidy, pad, CDIM", "The whole drone trace in one - TYDRN, then PADDLE, then CDIM"), new Entry[0], false, false),
            } },
            { "Dimensions", new[]
            {
                new Item(new Entry("AUTODIM", "Auto dimension", "Automatic dimensioning"), new[]
                {
                    new Entry("AUTODIMSIDEPOV", "Side-view dims", "Dimensions a side-view flight of steps"),
                }, true, true),
                new Item(new Entry("STAIRDIM", "Stair dims", "Stair dimensioning"), new Entry[0], false, false),
                new Item(new Entry("FLOORDIM", "Floor dims", "Floor dimensioning"), new Entry[0], false, false),
                new Item(new Entry("DIMCONTEND", "Continue dim chains", "Chains a seed dimension out to every feature point"), new Entry[0], false, false),
                new Item(new Entry("CDCREATE", "Lines to cross dims", "Turns every highlighted line into a cross dimension"), new Entry[0], true, true),
                new Item(new Entry("CDCALLOUT", "Point-to-point cross dims", "Cross-dimensions from Pt.## to Pt.## by typed number"), new Entry[0], true, true),
                new Item(new Entry("BPCALLOUT", "Bad point callout", "Rings clicked bad points and writes the callout"), new Entry[0], true, true),
                new Item(new Entry("DIMSTAMP", "Stamp dimension text", "Click a point, type 4'4.5, 44.5 or a letter; stamps it canonically, a ruler picks the next"), new Entry[0], true, true),
                new Item(new Entry("DRONOTE", "Drone photo review note", "Places a canned drone-photo review note - diving board, hidden anchors or slide sketch - at a picked point"), new Entry[0], false, false),
                new Item(new Entry("CLEARDIM", "Clear crowded dim text", "Slides dimension text along its own dimension line until it is readable"), new[]
                {
                    new Entry("CLEARDIMSCAN", "Crowded dim text scan", "Names the dimension text CLEARDIM would move, and moves nothing"),
                }, false, false),
            } },
            { "Converters", new[]
            {
                new Item(new Entry("XFTCONV", "Survey import cleanup", "Cleans up a Leica XFT/DXF import or a site trace"), new[]
                {
                    new Entry("XFTRECONV", "Import cleanup, undone", "Undoes an XFTCONV run - the markers and text back, and the scale with them"),
                }, true, true),
                new Item(new Entry("SOCONV", "SO survey onto our layers", "Puts an SO site-survey export onto the shop's layers in one pass"), new[]
                {
                    new Entry("SORECONV", "SO conversion, undone", "Undoes a SOCONV run - every object back on the export's own layers"),
                }, true, true),
                new Item(new Entry("VSCONV", "VS export onto shop layers", "Remaps a VS survey export's numbered layers onto the shop's"), new[]
                {
                    new Entry("VSRECONV", "VS conversion, undone", "Undoes a VSCONV run - layers, properties and the dimension overrides"),
                }, true, true),
                new Item(new Entry("G2MCONV", "G2M plan onto shop layers", "Puts a G2M architectural pool plan onto the shop's layers and styles"), new[]
                {
                    new Entry("G2MRECONV", "G2M conversion, undone", "Undoes a G2MCONV run - layers, appearance, text and dimension styles"),
                }, true, true),
            } },
            { "Checking", new[]
            {
                new Item(new Entry("CHECK", "Drawing check", "General drawing check"), new Entry[0], true, false),
                new Item(new Entry("DIMARCCHECK", "Arc endpoint check", "Dim arc endpoint check"), new Entry[0], true, false),
                new Item(new Entry("DIMCHECK", "Dimension review", "Guided, one-at-a-time dimension review"), new[]
                {
                    new Entry("DIMSCAN", "Dimension scan", "Scan drawing for dimensions"),
                }, true, false),
                new Item(new Entry("ABCURCHECK", "Perimeter continuity", "Grades how continuous a drawn perimeter is"), new[]
                {
                    new Entry("ABCURCHECKSCAN", "Perimeter continuity, no marks", "ABCURCHECK without marking the drawing"),
                }, true, false),
                new Item(new Entry("OLAUTO", "Overlay two perimeters", "Best-fit overlay of a new perimeter on the original, worst error dimensioned"), new Entry[0], true, false),
                new Item(new Entry("ABPCHECK", "Survey point offsets", "ABHD's measuring half as a checker - how far each point is off the line"), new Entry[0], true, false),
                new Item(new Entry("LINCHECK", "Line checklist", "Line / text check"), new Entry[0], true, false),
                new Item(new Entry("LINFINCHECK", "Liner finish review", "Full liner-finish drawing QA, guided"), new[]
                {
                    new Entry("LINFINSCAN", "Liner finish scan", "The liner-finish QA as one scan"),
                    new Entry("LITELINFINSCAN", "Liner scan, no dims", "Liner rules only - skips the dimension audit"),
                }, true, false),
                new Item(new Entry("COVERCHECK", "Cover review", "Cover check"), new[]
                {
                    new Entry("COVERSCAN", "Cover scan", "Scan drawing for covers"),
                    new Entry("LITECOVERSCAN", "Cover scan, no dims", "Cover rules only - skips the dimension audit"),
                }, true, false),
                new Item(new Entry("SPACHECK", "Spa sheet review", "Audits a spa sheet against what SPA draws"), new[]
                {
                    new Entry("SPACHECKSCAN", "Spa sheet scan", "The spa sheet review as one scan"),
                    new Entry("LITESPACHECKSCAN", "Spa scan, no dims", "Spa rules only - skips the dimension audit"),
                }, true, false),
                new Item(new Entry("LINTXTCHK", "Liner checklist text", "Places the vinyl-liner QA checklist as drawing text"), new Entry[0], true, false),
                new Item(new Entry("CCPRECHECK", "Tech flow chart", "Walks the Tech Flow Chart decision tree"), new Entry[0], true, false),
                new Item(new Entry("LAZDIAG", "Error report for the last failure", "Write the last failure out as a DXF to send in - and, with nothing to report, prove that path works"), new Entry[0], true, false),
                new Item(new Entry("LAZLOG", "What every command has done lately", "Every calofin command that finished, was backed out of or FAILED - the log a report's history comes from"), new Entry[0], true, false),
            } },
        };
    }
}
