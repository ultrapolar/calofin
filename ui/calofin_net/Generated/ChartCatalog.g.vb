' SPDX-License-Identifier: GPL-3.0-or-later
'
' GENERATED FILE - DO NOT EDIT.  Your change will vanish.
'
'   written by : tools/gen_ui_charts.py
'   from       : lisp/lazform/LAZFORM.lsp   (lzf:*charts*)
'                lisp/lazspa/LAZSPA.lsp     (lzs:*charts*)
'                lisp/lazstep/LAZSTEP.lsp   (lzt:chart, per step count)
'   regenerate : python3 tools/gen_ui_charts.py
'   checked by : python3 tools/gen_ui_charts.py --check, which
'                make check runs
'
' The charts are the ones LAZFORM, LAZSPA and LAZSTEP draw, in their own
' co-ordinates: x and y run 0..1000 with y DOWN, the way an image tile
' counts pixels.  Arcs are already flattened to polylines, by the Lisp's
' own lzX:flatten, so the palette draws the same oval the panel does and
' needs no arc arithmetic to do it.
'
' A dimension carries the two ends of its line.  A box belongs at the
' MIDPOINT of that line -- which is why nothing here has a hand-nudged
' position: the geometry places the box.
'
' What is NOT here: which keys a page asks about given the bottom type
' and the in-square toggle (lzf:dead), the cross-dim mode dropdowns and
' the corner tables.  Those are rules rather than data, and a second
' copy of a rule is the drift this file exists to end.

Imports System.Collections.Generic


''' <summary>
''' The dimension charts, as the routines themselves hold them.
''' </summary>
Public NotInheritable Class ChartCatalog

    Private Sub New()
    End Sub

    ''' <summary>The chart's own co-ordinate space: 0..1000 each way,
    ''' y running DOWN.</summary>
    Public Const Span As Double = 1000

    ''' <summary>One run of the outline: a flat x y x y ... polyline.
    ''' Arcs arrive already flattened.</summary>
    Public Structure Stroke
        Public ReadOnly Points As Double()

        Public Sub New(points As Double())
            Me.Points = points
        End Sub
    End Structure

    ''' <summary>One dimension: the letter the sheet prints, the key the
    ''' routine reads it under, the line it measures, and the question it
    ''' stands for.</summary>
    Public Structure ChartDim
        Public ReadOnly Letter As String
        Public ReadOnly Key As String
        Public ReadOnly X1 As Double
        Public ReadOnly Y1 As Double
        Public ReadOnly X2 As Double
        Public ReadOnly Y2 As Double
        Public ReadOnly Horizontal As Boolean
        Public ReadOnly Label As String

        Public Sub New(letter As String, key As String,
                       x1 As Double, y1 As Double,
                       x2 As Double, y2 As Double,
                       horizontal As Boolean, label As String)
            Me.Letter = letter
            Me.Key = key
            Me.X1 = x1
            Me.Y1 = y1
            Me.X2 = x2
            Me.Y2 = y2
            Me.Horizontal = horizontal
            Me.Label = label
        End Sub

        ''' <summary>Where the box goes: the middle of the line it
        ''' measures.</summary>
        Public ReadOnly Property MidX As Double
            Get
                Return (X1 + X2) / 2
            End Get
        End Property

        Public ReadOnly Property MidY As Double
            Get
                Return (Y1 + Y2) / 2
            End Get
        End Property
    End Structure

    ''' <summary>A key with no line on the chart: asked in the column
    ''' beside it instead.</summary>
    Public Structure ListKey
        Public ReadOnly Key As String
        Public ReadOnly Label As String

        Public Sub New(key As String, label As String)
            Me.Key = key
            Me.Label = label
        End Sub
    End Structure

    ''' <summary>An answer the chart IMPLIES rather than asks for --
    ''' lzf:gates. The Grecian letters only exist on the Overall input
    ''' path with the hopper type the chart draws, so the sheet answers
    ''' those questions itself.</summary>
    Public Structure Gate
        Public ReadOnly Key As String
        Public ReadOnly Value As String

        Public Sub New(key As String, value As String)
            Me.Key = key
            Me.Value = value
        End Sub
    End Structure

    ''' <summary>A letter drawn on the chart itself -- the spa sheets
    ''' name their four corners this way.</summary>
    Public Structure Mark
        Public ReadOnly Letter As String
        Public ReadOnly X As Double
        Public ReadOnly Y As Double

        Public Sub New(letter As String, x As Double, y As Double)
            Me.Letter = letter
            Me.X = x
            Me.Y = y
        End Sub
    End Structure

    ''' <summary>One sheet.</summary>
    Public Structure Chart
        ''' <summary>The name the chart is looked up by.</summary>
        Public ReadOnly Key As String
        ''' <summary>What travels as the shape answer -- NOT always the
        ''' key, which is why it is carried separately.</summary>
        Public ReadOnly Shape As String
        Public ReadOnly Title As String
        Public ReadOnly Strokes As Stroke()
        Public ReadOnly Dims As ChartDim()
        Public ReadOnly Extra As ListKey()
        Public ReadOnly Marks As Mark()
        Public ReadOnly Gates As Gate()

        Public Sub New(key As String, shape As String, title As String,
                       strokes As Stroke(), dims As ChartDim(),
                       extra As ListKey(), marks As Mark(),
                       gates As Gate())
            Me.Key = key
            Me.Shape = shape
            Me.Title = title
            Me.Strokes = strokes
            Me.Dims = dims
            Me.Extra = extra
            Me.Marks = marks
            Me.Gates = gates
        End Sub
    End Structure

    ''' <summary>A question answered from a list rather than typed. The
    ''' first option is "(ask)": choosing it sends nothing and the
    ''' routine asks at the command line.</summary>
    Public Structure Choice
        Public ReadOnly Key As String
        Public ReadOnly Label As String
        Public ReadOnly Options As String()

        Public Sub New(key As String, label As String, options As String())
            Me.Key = key
            Me.Label = label
            Me.Options = options
        End Sub
    End Structure

    ''' <summary>One corner of a spa sheet. Its two answers are keyed off
    ''' the stem: cornera-ty for the treatment, cornera-sz for the size
    ''' the treatment carries.</summary>
    Public Structure SpaCornerRow
        Public ReadOnly Stem As String
        Public ReadOnly Label As String

        Public Sub New(stem As String, label As String)
            Me.Stem = stem
            Me.Label = label
        End Sub
    End Structure

    ''' <summary>What a spa sheet has that a pool sheet has not.</summary>
    Public Structure SpaSheet
        ''' <summary>The chart this belongs to.</summary>
        Public ReadOnly Key As String
        Public ReadOnly Hint As String
        Public ReadOnly Corners As SpaCornerRow()
        ''' <summary>The other outline's overalls, under keys that are
        ''' PER SHAPE: the rectangle's pair is w2/l2, the octagon's is
        ''' b2/a2 plus the cut face f2.</summary>
        Public ReadOnly Second As ListKey()

        Public Sub New(key As String, hint As String,
                       corners As SpaCornerRow(), second As ListKey())
            Me.Key = key
            Me.Hint = hint
            Me.Corners = corners
            Me.Second = second
        End Sub
    End Structure

    ''' <summary>One step routine: the command a drafter knows it by,
    ''' its title, and the entry point a form hands its answers to.
    ''' All three come from lzt:*types*.</summary>
    Public Structure StepRoutine
        Public ReadOnly Command As String
        Public ReadOnly Title As String
        Public ReadOnly EntryPoint As String

        Public Sub New(command As String, title As String,
                       entryPoint As String)
            Me.Command = command
            Me.Title = title
            Me.EntryPoint = entryPoint
        End Sub
    End Structure

    ''' <summary>A step sheet, which depends on the count as well as the
    ''' routine.</summary>
    Public Structure StepChart
        Public ReadOnly Routine As String
        Public ReadOnly Title As String
        Public ReadOnly Steps As Integer
        Public ReadOnly Strokes As Stroke()
        Public ReadOnly Dims As ChartDim()
        ''' <summary>The y of each band the sheet is cut into.</summary>
        Public ReadOnly Cuts As Double()

        Public Sub New(routine As String, title As String, steps As Integer,
                       strokes As Stroke(), dims As ChartDim(),
                       cuts As Double())
            Me.Routine = routine
            Me.Title = title
            Me.Steps = steps
            Me.Strokes = strokes
            Me.Dims = dims
            Me.Cuts = cuts
        End Sub
    End Structure


    ''' <summary>LAZFORM's sheets, from lzf:*charts*.</summary>
    Public Shared ReadOnly Pool As Chart() = {
        New Chart("Rectangle", "Rectangle", "Rectangle",
            New Stroke() {
                New Stroke(New Double() {100, 300, 900, 300, 900, 860, 100, 860, 100, 300}),
                New Stroke(New Double() {275, 475, 400, 475, 400, 700, 275, 700, 275, 475}),
                New Stroke(New Double() {100, 300, 275, 475}),
                New Stroke(New Double() {100, 860, 275, 700}),
                New Stroke(New Double() {400, 475, 685, 300}),
                New Stroke(New Double() {400, 700, 685, 860}),
                New Stroke(New Double() {685, 300, 685, 860})
            },
            New ChartDim() {
                New ChartDim("B", "tp", 100, 175, 900, 175, True, "overall across, top side"),
                New ChartDim("A", "le", 45, 300, 45, 860, False, "overall up, left end"),
                New ChartDim("H", "h", 100, 580, 275, 580, True, "left end to the hopper"),
                New ChartDim("G", "g", 275, 580, 400, 580, True, "hopper length (0 = slope bottom)"),
                New ChartDim("F", "f", 400, 580, 685, 580, True, "hopper to the slope break"),
                New ChartDim("E", "e", 685, 580, 900, 580, True, "slope break to the right end"),
                New ChartDim("M", "m", 437, 300, 437, 475, False, "top side to the hopper"),
                New ChartDim("L", "l", 437, 475, 437, 700, False, "hopper width"),
                New ChartDim("K", "k", 437, 700, 437, 860, False, "hopper to the bottom side")
            },
            New ListKey() {
                New ListKey("bo", "overall across, bottom side (out-of-square only)"),
                New ListKey("ri", "overall up, right end (out-of-square only)"),
                New ListKey("c", "C - wall height (shallow depth)"),
                New ListKey("d", "D - deep end depth"),
                New ListKey("c2", "C2 - shallow floor at the break"),
                New ListKey("e2", "E2 - left end shallow flat"),
                New ListKey("f2", "F2 - left slope"),
                New ListKey("f1", "F1 - right slope"),
                New ListKey("e1", "E1 - right end shallow flat")
            },
            New Mark() {},
            New Gate() {}),
        New Chart("Oval", "Oval", "True Oval",
            New Stroke() {
                New Stroke(New Double() {310, 250, 283, 251, 258, 255, 232, 262, 208, 271, 185, 283, 163, 297, 142, 314, 124, 332, 107, 353, 93, 375, 81, 398, 72, 422, 65, 448, 61, 473, 60, 499, 61, 526, 65, 551, 72, 577, 81, 601, 93, 625, 107, 646, 124, 667, 142, 685, 163, 702, 184, 716, 208, 728, 232, 737, 258, 744, 283, 748, 309, 750}),
                New Stroke(New Double() {310, 250, 690, 250}),
                New Stroke(New Double() {690, 250, 716, 251, 741, 255, 767, 262, 791, 271, 815, 283, 836, 297, 857, 314, 875, 332, 892, 353, 906, 375, 918, 398, 927, 422, 934, 448, 938, 473, 940, 500, 938, 526, 934, 551, 927, 577, 918, 601, 906, 625, 892, 646, 875, 667, 857, 685, 836, 702, 815, 716, 791, 728, 767, 737, 741, 744, 716, 748, 690, 750}),
                New Stroke(New Double() {310, 750, 690, 750}),
                New Stroke(New Double() {310, 380, 297, 380, 285, 382, 272, 385, 261, 390, 250, 396, 239, 402, 229, 410, 220, 419, 212, 429, 206, 440, 200, 451, 195, 462, 192, 475, 190, 487, 190, 500, 190, 512, 192, 524, 195, 537, 200, 548, 206, 560, 212, 570, 220, 580, 229, 589, 239, 597, 249, 603, 261, 609, 272, 614, 285, 617, 297, 619, 310, 620}),
                New Stroke(New Double() {310, 380, 400, 380}),
                New Stroke(New Double() {400, 380, 400, 620}),
                New Stroke(New Double() {310, 620, 400, 620}),
                New Stroke(New Double() {400, 380, 690, 250}),
                New Stroke(New Double() {400, 620, 690, 750}),
                New Stroke(New Double() {690, 250, 690, 750})
            },
            New ChartDim() {
                New ChartDim("B", "tot", 60, 130, 940, 130, True, "total length, arc tip to arc tip"),
                New ChartDim("T", "tp", 310, 205, 690, 205, True, "straight side length, top and bottom"),
                New ChartDim("A", "le", 35, 250, 35, 750, False, "end length, left and right"),
                New ChartDim("H", "h", 60, 580, 190, 580, True, "H - pool left tip to hopper tip"),
                New ChartDim("G", "g", 190, 580, 400, 580, True, "G - hopper length, tip to right edge"),
                New ChartDim("F", "f", 400, 580, 690, 580, True, "F - hopper to slope break"),
                New ChartDim("E", "e", 690, 580, 940, 580, True, "E - slope break to pool right tip"),
                New ChartDim("W", "w", 310, 345, 400, 345, True, "W - hopper flat top"),
                New ChartDim("M", "m", 437, 250, 437, 380, False, "M - top side to hopper"),
                New ChartDim("L", "l", 437, 380, 437, 620, False, "L - hopper width"),
                New ChartDim("K", "k", 437, 620, 437, 750, False, "K - hopper to bottom side")
            },
            New ListKey() {
                New ListKey("lr", "R1 - LEFT oval end radius"),
                New ListKey("rr", "R2 - RIGHT oval end radius"),
                New ListKey("r3", "R3 - hopper end radius"),
                New ListKey("bo", "side length BOTTOM (out-of-square only)"),
                New ListKey("ri", "end length RIGHT (out-of-square only)"),
                New ListKey("c", "C - wall height (shallow depth)"),
                New ListKey("d", "D - deep end depth"),
                New ListKey("c2", "C2 - shallow floor at the break"),
                New ListKey("tt", "T - straight side length (check)"),
                New ListKey("e2", "E2 - left end shallow flat"),
                New ListKey("f2", "F2 - left slope"),
                New ListKey("f1", "F1 - right slope"),
                New ListKey("e1", "E1 - right end shallow flat")
            },
            New Mark() {},
            New Gate() {}),
        New Chart("ROman", "ROman", "Roman",
            New Stroke() {
                New Stroke(New Double() {160, 250, 840, 250}),
                New Stroke(New Double() {840, 250, 850, 251, 860, 255, 870, 262, 880, 271, 890, 283, 898, 297, 906, 314, 914, 332, 920, 353, 926, 375, 931, 398, 935, 422, 937, 448, 939, 473, 940, 500, 939, 526, 937, 551, 935, 577, 931, 601, 926, 625, 920, 646, 914, 667, 906, 685, 898, 702, 890, 716, 880, 728, 870, 737, 860, 744, 850, 748, 840, 750}),
                New Stroke(New Double() {840, 750, 160, 750}),
                New Stroke(New Double() {160, 750, 100, 621}),
                New Stroke(New Double() {100, 378, 92, 386, 86, 395, 80, 406, 75, 417, 70, 430, 66, 443, 63, 456, 61, 470, 60, 485, 60, 500, 60, 514, 61, 529, 63, 543, 66, 556, 70, 570, 75, 582, 80, 593, 86, 604, 92, 613, 99, 621}),
                New Stroke(New Double() {160, 250, 100, 379}),
                New Stroke(New Double() {330, 380, 318, 380, 307, 382, 296, 385, 285, 390, 275, 396, 265, 402, 256, 410, 248, 419, 241, 429, 234, 440, 229, 451, 225, 462, 222, 475, 220, 487, 220, 500, 220, 512, 222, 524, 225, 537, 229, 548, 234, 560, 241, 570, 248, 580, 256, 589, 265, 597, 274, 603, 285, 609, 296, 614, 307, 617, 318, 619, 330, 620}),
                New Stroke(New Double() {330, 380, 420, 380}),
                New Stroke(New Double() {420, 380, 420, 620}),
                New Stroke(New Double() {330, 620, 420, 620}),
                New Stroke(New Double() {420, 380, 700, 250}),
                New Stroke(New Double() {420, 620, 700, 750}),
                New Stroke(New Double() {700, 250, 700, 750}),
                New Stroke(New Double() {160, 250, 300, 385}),
                New Stroke(New Double() {160, 750, 300, 615})
            },
            New ChartDim() {
                New ChartDim("B", "b", 60, 130, 940, 130, True, "B - overall length"),
                New ChartDim("T", "tt", 160, 205, 840, 205, True, "T - side length, top and bottom"),
                New ChartDim("A", "a", 35, 250, 35, 750, False, "A - overall width"),
                New ChartDim("S", "sl", 60, 205, 160, 205, True, "S - end setback"),
                New ChartDim("S1", "s1l", 90, 250, 90, 379, False, "S1 - corner drop"),
                New ChartDim("V", "vl", 125, 379, 125, 621, False, "V - end width"),
                New ChartDim("H", "h", 60, 580, 220, 580, True, "H - left end to hopper"),
                New ChartDim("G", "g", 220, 580, 420, 580, True, "G - hopper length"),
                New ChartDim("F", "f", 420, 580, 700, 580, True, "F - hopper to slope break"),
                New ChartDim("E", "e", 700, 580, 940, 580, True, "E - slope break to right end"),
                New ChartDim("W", "w", 330, 345, 420, 345, True, "W - hopper flat top"),
                New ChartDim("M", "m", 455, 250, 455, 380, False, "M - top side to hopper"),
                New ChartDim("L", "l", 455, 380, 455, 620, False, "L - hopper width"),
                New ChartDim("K", "k", 455, 620, 455, 750, False, "K - hopper to bottom side")
            },
            New ListKey() {
                New ListKey("r1", "R1 - LEFT end radius (check)"),
                New ListKey("r2", "R2 - RIGHT end radius (check)"),
                New ListKey("r3", "R3 - hopper end radius"),
                New ListKey("sr", "S - RIGHT end setback (ends not perfect)"),
                New ListKey("s1r", "S1 - RIGHT corner drop (ends not perfect)"),
                New ListKey("vr", "V - RIGHT end width (ends not perfect)"),
                New ListKey("c", "C - wall height (shallow depth)"),
                New ListKey("d", "D - deep end depth"),
                New ListKey("c2", "C2 - shallow floor at the break"),
                New ListKey("e2", "E2 - left end shallow flat"),
                New ListKey("f2", "F2 - left slope"),
                New ListKey("f1", "F1 - right slope"),
                New ListKey("e1", "E1 - right end shallow flat")
            },
            New Mark() {},
            New Gate() {}),
        New Chart("Grecian", "Grecian", "Grecian (6-Sided Hopper)",
            New Stroke() {
                New Stroke(New Double() {190, 250, 780, 250}),
                New Stroke(New Double() {780, 250, 900, 380}),
                New Stroke(New Double() {900, 380, 900, 620}),
                New Stroke(New Double() {900, 620, 780, 750}),
                New Stroke(New Double() {780, 750, 190, 750}),
                New Stroke(New Double() {190, 750, 100, 620}),
                New Stroke(New Double() {100, 620, 100, 380}),
                New Stroke(New Double() {100, 380, 190, 250}),
                New Stroke(New Double() {250, 440, 330, 380}),
                New Stroke(New Double() {330, 380, 420, 380}),
                New Stroke(New Double() {420, 380, 420, 620}),
                New Stroke(New Double() {330, 620, 420, 620}),
                New Stroke(New Double() {250, 560, 330, 620}),
                New Stroke(New Double() {250, 440, 250, 560}),
                New Stroke(New Double() {420, 380, 690, 250}),
                New Stroke(New Double() {420, 620, 690, 750}),
                New Stroke(New Double() {690, 250, 690, 750}),
                New Stroke(New Double() {190, 250, 250, 440}),
                New Stroke(New Double() {190, 750, 250, 560})
            },
            New ChartDim() {
                New ChartDim("B", "b", 100, 120, 900, 120, True, "B - overall length"),
                New ChartDim("S", "ss", 100, 205, 190, 205, True, "S - corner cut along the side"),
                New ChartDim("T", "tt", 190, 205, 780, 205, True, "T - top side length"),
                New ChartDim("S1", "s1", 70, 250, 70, 380, False, "S1 - corner cut down the end"),
                New ChartDim("A", "a", 20, 250, 20, 750, False, "A - overall width"),
                New ChartDim("V", "vv", 55, 380, 55, 620, False, "V - end width"),
                New ChartDim("H", "h", 100, 580, 250, 580, True, "H - left end to hopper"),
                New ChartDim("G", "g", 250, 580, 420, 580, True, "G - hopper length"),
                New ChartDim("W", "w", 270, 330, 350, 330, True, "W - top flat, cut corner to hopper end"),
                New ChartDim("L1", "l1", 225, 440, 225, 560, False, "L1 - hopper left edge length"),
                New ChartDim("M", "m", 455, 250, 455, 380, False, "M - top side to hopper"),
                New ChartDim("L", "l", 455, 380, 455, 620, False, "L - hopper width"),
                New ChartDim("K", "k", 455, 620, 455, 750, False, "K - hopper to bottom side"),
                New ChartDim("F", "f", 420, 580, 690, 580, True, "F - hopper to slope break"),
                New ChartDim("E", "e", 690, 580, 900, 580, True, "E - slope break to right end")
            },
            New ListKey() {
                New ListKey("x", "X - hopper cut face length (check)"),
                New ListKey("s2", "S2 - corner cut face (check, sets NA S/S1)"),
                New ListKey("c", "C - wall height (shallow depth)"),
                New ListKey("d", "D - deep end depth"),
                New ListKey("c2", "C2 - shallow floor at the break"),
                New ListKey("e2", "E2 - left end shallow flat"),
                New ListKey("f2", "F2 - left slope"),
                New ListKey("f1", "F1 - right slope"),
                New ListKey("e1", "E1 - right end shallow flat")
            },
            New Mark() {},
            New Gate() {
                New Gate("imeth", "Overall"),
                New Gate("htype", "SIX"),
                New Gate("hmode", "Letters")
            }),
        New Chart("GRSquare", "Grecian", "Grecian (Square Hopper)",
            New Stroke() {
                New Stroke(New Double() {190, 250, 780, 250}),
                New Stroke(New Double() {780, 250, 900, 380}),
                New Stroke(New Double() {900, 380, 900, 620}),
                New Stroke(New Double() {900, 620, 780, 750}),
                New Stroke(New Double() {780, 750, 190, 750}),
                New Stroke(New Double() {190, 750, 100, 620}),
                New Stroke(New Double() {100, 620, 100, 380}),
                New Stroke(New Double() {100, 380, 190, 250}),
                New Stroke(New Double() {250, 380, 420, 380}),
                New Stroke(New Double() {420, 380, 420, 620}),
                New Stroke(New Double() {250, 620, 420, 620}),
                New Stroke(New Double() {250, 380, 250, 620}),
                New Stroke(New Double() {420, 380, 690, 250}),
                New Stroke(New Double() {420, 620, 690, 750}),
                New Stroke(New Double() {690, 250, 690, 750}),
                New Stroke(New Double() {190, 250, 250, 380}),
                New Stroke(New Double() {190, 750, 250, 620})
            },
            New ChartDim() {
                New ChartDim("B", "b", 100, 120, 900, 120, True, "B - overall length"),
                New ChartDim("S", "ss", 100, 205, 190, 205, True, "S - corner cut along the side"),
                New ChartDim("T", "tt", 190, 205, 780, 205, True, "T - top side length"),
                New ChartDim("S1", "s1", 70, 250, 70, 380, False, "S1 - corner cut down the end"),
                New ChartDim("A", "a", 20, 250, 20, 750, False, "A - overall width"),
                New ChartDim("V", "vv", 55, 380, 55, 620, False, "V - end width"),
                New ChartDim("H", "h", 100, 580, 250, 580, True, "H - left end to hopper"),
                New ChartDim("G", "g", 250, 580, 420, 580, True, "G - hopper length"),
                New ChartDim("M", "m", 455, 250, 455, 380, False, "M - top side to hopper"),
                New ChartDim("L", "l", 455, 380, 455, 620, False, "L - hopper width"),
                New ChartDim("K", "k", 455, 620, 455, 750, False, "K - hopper to bottom side"),
                New ChartDim("F", "f", 420, 580, 690, 580, True, "F - hopper to slope break"),
                New ChartDim("E", "e", 690, 580, 900, 580, True, "E - slope break to right end")
            },
            New ListKey() {
                New ListKey("s2", "S2 - corner cut face (check, sets NA S/S1)"),
                New ListKey("c", "C - wall height (shallow depth)"),
                New ListKey("d", "D - deep end depth"),
                New ListKey("c2", "C2 - shallow floor at the break"),
                New ListKey("e2", "E2 - left end shallow flat"),
                New ListKey("f2", "F2 - left slope"),
                New ListKey("f1", "F1 - right slope"),
                New ListKey("e1", "E1 - right end shallow flat")
            },
            New Mark() {},
            New Gate() {
                New Gate("imeth", "Overall"),
                New Gate("htype", "Square")
            }),
        New Chart("L", "L", "True L Left",
            New Stroke() {
                New Stroke(New Double() {100, 400, 640, 400}),
                New Stroke(New Double() {640, 400, 640, 150}),
                New Stroke(New Double() {640, 150, 900, 150}),
                New Stroke(New Double() {900, 150, 900, 850}),
                New Stroke(New Double() {900, 850, 100, 850}),
                New Stroke(New Double() {100, 850, 100, 400}),
                New Stroke(New Double() {250, 520, 400, 520}),
                New Stroke(New Double() {400, 520, 400, 730}),
                New Stroke(New Double() {250, 730, 400, 730}),
                New Stroke(New Double() {250, 520, 250, 730}),
                New Stroke(New Double() {100, 400, 250, 520}),
                New Stroke(New Double() {100, 850, 250, 730}),
                New Stroke(New Double() {400, 520, 640, 400}),
                New Stroke(New Double() {400, 730, 640, 850}),
                New Stroke(New Double() {640, 400, 640, 850})
            },
            New ChartDim() {
                New ChartDim("B", "ab", 100, 920, 900, 920, True, "side A-B, bottom, full length"),
                New ChartDim("A1", "bc", 960, 150, 960, 850, False, "end B-C, right end, full height"),
                New ChartDim("B2", "cd", 640, 90, 900, 90, True, "side C-D, top of the wing"),
                New ChartDim("A2", "de", 600, 150, 600, 400, False, "step D-E, down to the reverse corner"),
                New ChartDim("B1", "ef", 100, 340, 640, 340, True, "side E-F, top of the main section"),
                New ChartDim("A", "fa", 45, 400, 45, 850, False, "end F-A, left end"),
                New ChartDim("H", "h", 100, 625, 250, 625, True, "H - left end to deep end"),
                New ChartDim("G", "g", 250, 625, 400, 625, True, "G - hopper length"),
                New ChartDim("F", "f", 400, 625, 640, 625, True, "F - hopper to slope break"),
                New ChartDim("E", "e", 640, 625, 900, 625, True, "E - slope break to right end"),
                New ChartDim("M", "m", 430, 400, 430, 520, False, "M - top side to hopper"),
                New ChartDim("L", "l", 430, 520, 430, 730, False, "L - hopper width"),
                New ChartDim("K", "k", 430, 730, 430, 850, False, "K - hopper to bottom side")
            },
            New ListKey() {
                New ListKey("c", "C - wall height (shallow depth)"),
                New ListKey("d", "D - deep end depth"),
                New ListKey("c2", "C2 - shallow floor at the break")
            },
            New Mark() {},
            New Gate() {}),
        New Chart("ROUnd", "ROUnd", "Round",
            New Stroke() {
                New Stroke(New Double() {750, 500, 748, 473, 744, 448, 737, 422, 728, 398, 716, 375, 702, 353, 685, 332, 667, 314, 646, 297, 625, 283, 601, 271, 577, 262, 551, 255, 526, 251, 500, 250, 473, 251, 448, 255, 422, 262, 398, 271, 375, 283, 353, 297, 332, 314, 314, 332, 297, 353, 283, 375, 271, 398, 262, 422, 255, 448, 251, 473, 250, 499, 251, 526, 255, 551, 262, 577, 271, 601, 283, 625, 297, 646, 314, 667, 332, 685, 353, 702, 374, 716, 398, 728, 422, 737, 448, 744, 473, 748, 499, 750, 526, 748, 551, 744, 577, 737, 601, 728, 625, 716, 646, 702, 667, 685, 685, 667, 702, 646, 716, 625, 728, 601, 737, 577, 744, 551, 748, 526, 750, 500}),
                New Stroke(New Double() {390, 430, 382, 430, 375, 431, 368, 433, 361, 436, 355, 439, 348, 443, 343, 447, 337, 453, 333, 458, 329, 465, 326, 471, 323, 478, 321, 485, 320, 492, 320, 500, 320, 507, 321, 514, 323, 521, 326, 528, 329, 535, 333, 541, 337, 546, 343, 552, 348, 556, 355, 560, 361, 563, 368, 566, 375, 568, 382, 569, 390, 570}),
                New Stroke(New Double() {390, 430, 540, 430}),
                New Stroke(New Double() {540, 430, 540, 570}),
                New Stroke(New Double() {390, 570, 540, 570}),
                New Stroke(New Double() {540, 430, 660, 350}),
                New Stroke(New Double() {540, 570, 660, 650}),
                New Stroke(New Double() {660, 350, 660, 650})
            },
            New ChartDim() {
                New ChartDim("B", "b", 250, 150, 750, 150, True, "B - overall length (across)"),
                New ChartDim("A", "a", 175, 250, 175, 750, False, "A - overall width (up)"),
                New ChartDim("H", "h", 250, 600, 320, 600, True, "H - pool left edge to hopper tip"),
                New ChartDim("G", "g", 320, 600, 540, 600, True, "G - hopper length, tip to right edge"),
                New ChartDim("F", "f", 540, 600, 660, 600, True, "F - hopper to slope break"),
                New ChartDim("E", "e", 660, 600, 750, 600, True, "E - slope break to pool right edge"),
                New ChartDim("W", "w", 390, 405, 540, 405, True, "W - hopper flat top"),
                New ChartDim("M", "m", 500, 250, 500, 430, False, "M - top of pool to hopper"),
                New ChartDim("L", "l", 500, 430, 500, 570, False, "L - hopper width"),
                New ChartDim("K", "k", 500, 570, 500, 750, False, "K - hopper to bottom of pool")
            },
            New ListKey() {
                New ListKey("c", "C - wall height (shallow depth)"),
                New ListKey("d", "D - deep end depth"),
                New ListKey("c2", "C2 - shallow floor at the break"),
                New ListKey("tt", "T - straight side length (check)"),
                New ListKey("e2", "E2 - left end shallow flat"),
                New ListKey("f2", "F2 - left slope"),
                New ListKey("f1", "F1 - right slope"),
                New ListKey("e1", "E1 - right end shallow flat")
            },
            New Mark() {},
            New Gate() {}),
        New Chart("OCtagon", "OCtagon", "Octagon",
            New Stroke() {
                New Stroke(New Double() {190, 250, 780, 250}),
                New Stroke(New Double() {780, 250, 900, 380}),
                New Stroke(New Double() {900, 380, 900, 620}),
                New Stroke(New Double() {900, 620, 780, 750}),
                New Stroke(New Double() {780, 750, 190, 750}),
                New Stroke(New Double() {190, 750, 100, 620}),
                New Stroke(New Double() {100, 620, 100, 380}),
                New Stroke(New Double() {100, 380, 190, 250}),
                New Stroke(New Double() {250, 380, 420, 380}),
                New Stroke(New Double() {420, 380, 420, 620}),
                New Stroke(New Double() {250, 620, 420, 620}),
                New Stroke(New Double() {250, 380, 250, 620}),
                New Stroke(New Double() {420, 380, 690, 250}),
                New Stroke(New Double() {420, 620, 690, 750}),
                New Stroke(New Double() {690, 250, 690, 750}),
                New Stroke(New Double() {190, 250, 250, 380}),
                New Stroke(New Double() {190, 750, 250, 620})
            },
            New ChartDim() {
                New ChartDim("B", "b", 100, 120, 900, 120, True, "B - overall length"),
                New ChartDim("S", "ss", 100, 205, 190, 205, True, "S - corner cut along the side"),
                New ChartDim("T", "tt", 190, 205, 780, 205, True, "T - top side length"),
                New ChartDim("S1", "s1", 70, 250, 70, 380, False, "S1 - corner cut down the end"),
                New ChartDim("A", "a", 20, 250, 20, 750, False, "A - overall width"),
                New ChartDim("V", "vv", 55, 380, 55, 620, False, "V - end width"),
                New ChartDim("H", "h", 100, 580, 250, 580, True, "H - left end to hopper"),
                New ChartDim("G", "g", 250, 580, 420, 580, True, "G - hopper length"),
                New ChartDim("M", "m", 455, 250, 455, 380, False, "M - top side to hopper"),
                New ChartDim("L", "l", 455, 380, 455, 620, False, "L - hopper width"),
                New ChartDim("K", "k", 455, 620, 455, 750, False, "K - hopper to bottom side"),
                New ChartDim("F", "f", 420, 580, 690, 580, True, "F - hopper to slope break"),
                New ChartDim("E", "e", 690, 580, 900, 580, True, "E - slope break to right end")
            },
            New ListKey() {
                New ListKey("s2", "S2 - corner cut face (check, sets NA S/S1)"),
                New ListKey("c", "C - wall height (shallow depth)"),
                New ListKey("d", "D - deep end depth"),
                New ListKey("c2", "C2 - shallow floor at the break"),
                New ListKey("e2", "E2 - left end shallow flat"),
                New ListKey("f2", "F2 - left slope"),
                New ListKey("f1", "F1 - right slope"),
                New ListKey("e1", "E1 - right end shallow flat")
            },
            New Mark() {},
            New Gate() {
                New Gate("imeth", "Overall"),
                New Gate("htype", "Square")
            }),
        New Chart("OACenter", "Center", "Oasis - Center Bulge",
            New Stroke() {
                New Stroke(New Double() {271, 436, 254, 436, 237, 438, 220, 442, 204, 449, 188, 459, 174, 470, 160, 484, 147, 500, 136, 517, 126, 536, 117, 557, 110, 578, 105, 601, 101, 624, 100, 647, 100, 671, 102, 694, 105, 717, 111, 740, 118, 761, 127, 781, 137, 800, 149, 817, 161, 833, 175, 846, 190, 858, 206, 867, 222, 873, 239, 878, 256, 879, 273, 879, 290, 875, 306, 870, 322, 862, 338, 851, 352, 839, 365, 824, 377, 807, 388, 789, 398, 770}),
                New Stroke(New Double() {568, 764, 561, 752, 554, 741, 546, 731, 537, 722, 528, 715, 518, 709, 508, 705, 497, 702, 487, 701, 476, 701, 465, 703, 455, 706, 445, 711, 435, 718, 426, 726, 418, 735, 410, 745, 403, 757, 397, 769}),
                New Stroke(New Double() {568, 765, 579, 786, 592, 805, 606, 823, 621, 839, 637, 852, 654, 863, 672, 871, 691, 876, 709, 879, 728, 879, 747, 877, 766, 871, 784, 863, 801, 853, 817, 839, 833, 824, 847, 807, 859, 787, 870, 766, 880, 743, 887, 719, 893, 694, 897, 669, 899, 643, 899, 616, 897, 590, 893, 565, 888, 540, 880, 516, 870, 493, 859, 472, 847, 452, 833, 435, 817, 420, 801, 407, 784, 396, 766, 388, 747, 382, 728, 380, 710, 380, 691, 383, 672, 388}),
                New Stroke(New Double() {623, 376, 628, 381, 634, 385, 640, 387, 647, 389, 653, 390, 659, 390, 666, 389, 672, 388}),
                New Stroke(New Double() {623, 376, 603, 359, 581, 345, 559, 335, 535, 328, 512, 324, 488, 324, 464, 327, 441, 335, 418, 345, 397, 359, 376, 376, 357, 396}),
                New Stroke(New Double() {271, 436, 284, 436, 297, 435, 310, 431, 323, 425, 335, 417, 347, 408, 357, 397})
            },
            New ChartDim() {
                New ChartDim("X", "x", 100, 204, 900, 204, True, "X - overall left-to-right bounds"),
                New ChartDim("Y", "y", 45, 324, 45, 880, False, "Y - overall front-to-back bounds"),
                New ChartDim("L", "rl", 100, 658, 260, 658, True, "L - left bulge radius"),
                New ChartDim("T", "rt", 500, 630, 500, 324, False, "T - top bulge radius"),
                New ChartDim("R", "rr", 720, 630, 900, 630, True, "R - right bulge radius"),
                New ChartDim("TL", "ftl", 317, 428, 256, 380, False, "TL - top-left tangent radius"),
                New ChartDim("TR", "ftr", 647, 390, 696, 333, False, "TR - top-right tangent radius"),
                New ChartDim("BC", "fbc", 482, 701, 467, 770, False, "BC - bottom-center tangent radius")
            },
            New ListKey() {
                New ListKey("off", "Top bulge off center, left negative (complex only)")
            },
            New Mark() {},
            New Gate() {}),
        New Chart("OATopRight", "TopRight", "Oasis - Top-Right Bulge",
            New Stroke() {
                New Stroke(New Double() {387, 485, 372, 480, 357, 478, 341, 478, 326, 480, 311, 484, 296, 491, 282, 499, 269, 510, 256, 523, 245, 537, 234, 553, 225, 570, 218, 589, 212, 608, 207, 629, 204, 650, 203, 671, 203, 693, 205, 714, 208, 735, 213, 755, 220, 774, 228, 792, 237, 809, 248, 825, 260, 839, 273, 851, 286, 861, 301, 869, 315, 875, 331, 878, 346, 879, 361, 879, 377, 875, 392, 870, 406, 862, 420, 853}),
                New Stroke(New Double() {580, 853, 563, 842, 546, 833, 527, 827, 509, 824, 490, 824, 472, 827, 453, 833, 436, 842, 419, 853}),
                New Stroke(New Double() {579, 853, 593, 862, 607, 870, 622, 875, 638, 879, 653, 879, 668, 878, 684, 875, 698, 869, 713, 861, 726, 851, 739, 839, 751, 825, 762, 809, 771, 792, 779, 774, 786, 755, 791, 735, 794, 714, 796, 693, 796, 671, 795, 650, 792, 629, 787, 608}),
                New Stroke(New Double() {787, 482, 782, 503, 780, 524, 779, 546, 779, 567, 782, 588, 787, 609}),
                New Stroke(New Double() {788, 483, 792, 464, 795, 446, 796, 427, 796, 408, 795, 388, 792, 370, 787, 352, 781, 334, 774, 318, 766, 303, 756, 289, 746, 276, 735, 266, 722, 257, 710, 249, 696, 244, 683, 241, 669, 240, 655, 240, 642, 243, 628, 248, 615, 255, 603, 263, 591, 274, 581, 286, 571, 300, 562, 315, 555, 331, 549, 348, 544, 366}),
                New Stroke(New Double() {386, 486, 400, 490, 414, 492, 429, 492, 443, 490, 457, 486, 470, 479, 483, 471, 495, 460, 507, 448, 517, 434, 526, 419, 533, 402, 540, 385, 545, 366})
            },
            New ChartDim() {
                New ChartDim("X", "x", 203, 120, 797, 120, True, "X - overall left-to-right bounds"),
                New ChartDim("Y", "y", 148, 240, 148, 880, False, "Y - overall front-to-back bounds"),
                New ChartDim("L", "rl", 203, 679, 348, 679, True, "L - left bulge radius"),
                New ChartDim("T", "rt", 668, 419, 668, 240, False, "T - top-right bulge radius"),
                New ChartDim("R", "rr", 652, 679, 797, 679, True, "R - right bulge radius"),
                New ChartDim("TL", "ftl", 484, 471, 469, 402, False, "TL - top-left tangent radius"),
                New ChartDim("RS", "ftr", 780, 546, 864, 542, False, "RS - right-side tangent radius"),
                New ChartDim("BC", "fbc", 500, 824, 500, 894, False, "BC - bottom-center tangent radius")
            },
            New ListKey() {
                New ListKey("off", "Top-right bulge off the right bound, left negative (complex only)")
            },
            New Mark() {},
            New Gate() {}),
        New Chart("OACloud", "Cloud", "Oasis - Cloud",
            New Stroke() {
                New Stroke(New Double() {564, 360, 548, 334, 530, 312, 510, 292, 489, 275, 467, 261, 444, 250, 420, 243, 396, 240, 371, 240, 347, 244, 323, 251, 300, 262, 278, 276, 257, 293, 237, 314, 219, 337, 203, 362, 189, 390, 178, 420, 168, 451, 161, 484, 157, 517, 155, 551, 155, 585, 158, 618, 164, 651, 172, 683, 183, 714, 196, 743, 211, 770, 228, 794, 247, 816, 267, 835, 289, 850, 311, 863, 335, 872, 359, 877, 383, 879, 407, 878, 432, 873, 455, 864}),
                New Stroke(New Double() {630, 867, 602, 855, 572, 848, 543, 846, 513, 847, 483, 854, 455, 864}),
                New Stroke(New Double() {631, 867, 647, 874, 664, 878, 681, 879, 698, 879, 715, 875, 732, 869, 748, 861, 763, 850, 778, 837, 791, 822, 803, 806, 814, 787, 823, 767, 831, 746, 837, 723, 841, 700, 844, 677, 844, 653, 843, 629, 840, 606, 836, 583, 829, 561, 821, 540, 812, 520, 801, 502, 788, 485, 775, 471, 760, 458, 744, 448, 728, 440, 711, 435, 694, 432, 677, 432}),
                New Stroke(New Double() {565, 359, 575, 376, 588, 391, 601, 404, 615, 414, 630, 422, 646, 428, 662, 431, 678, 431})
            },
            New ChartDim() {
                New ChartDim("X", "x", 154, 120, 846, 120, True, "X - overall left-to-right bounds"),
                New ChartDim("Y", "y", 99, 240, 99, 880, False, "Y - overall front-to-back bounds"),
                New ChartDim("R", "rr", 684, 656, 846, 656, True, "R - right bulge radius"),
                New ChartDim("T", "ftl", 615, 415, 668, 360, False, "T - top tangent radius"),
                New ChartDim("B", "fbc", 543, 846, 556, 915, False, "B - bottom radius (rounded only)")
            },
            New ListKey() {},
            New Mark() {},
            New Gate() {}),
        New Chart("OAKidney", "Kidney", "Oasis - Kidney",
            New Stroke() {
                New Stroke(New Double() {212, 356, 194, 370, 176, 387, 160, 407, 145, 428, 133, 452, 122, 478, 113, 505, 106, 533, 102, 562, 100, 591, 100, 621, 102, 650, 107, 679, 114, 707, 123, 734, 134, 759, 147, 783, 161, 804, 178, 823, 195, 840, 214, 854, 234, 865, 254, 873, 276, 878, 297, 879, 318, 878, 339, 873, 360, 866, 380, 855, 398, 841, 416, 825, 433, 806}),
                New Stroke(New Double() {567, 806, 559, 797, 550, 789, 541, 782, 531, 777, 521, 773, 510, 770, 500, 770, 489, 770, 478, 773, 468, 777, 458, 782, 449, 789, 440, 797, 432, 806}),
                New Stroke(New Double() {566, 806, 583, 825, 601, 841, 619, 855, 639, 866, 660, 873, 681, 878, 702, 879, 723, 878, 745, 873, 765, 865, 785, 854, 804, 840, 821, 823, 838, 804, 852, 783, 865, 759, 876, 734, 885, 707, 892, 679, 897, 650, 899, 621, 899, 591, 897, 562, 893, 533, 886, 505, 877, 478, 866, 452, 854, 428, 839, 407, 823, 387, 805, 370, 787, 356}),
                New Stroke(New Double() {787, 357, 718, 318, 647, 289, 574, 272, 500, 267, 425, 272, 352, 289, 281, 318, 212, 357})
            },
            New ChartDim() {
                New ChartDim("X", "x", 100, 147, 900, 147, True, "X - overall left-to-right bounds"),
                New ChartDim("Y", "y", 45, 267, 45, 880, False, "Y - overall front-to-back bounds"),
                New ChartDim("L", "rl", 100, 605, 298, 605, True, "L - left bulge radius (asymmetric)"),
                New ChartDim("R", "rr", 702, 605, 900, 605, True, "R - right bulge radius (asymmetric)"),
                New ChartDim("TC", "rt", 500, 267, 500, 197, False, "TC - top-center radius (true kidney)"),
                New ChartDim("BC", "fbc", 500, 769, 500, 839, False, "BC - bottom-center tangent radius")
            },
            New ListKey() {},
            New Mark() {},
            New Gate() {}),
        New Chart("OANXT", "NXTcloud", "Oasis - NXT Cloud",
            New Stroke() {
                New Stroke(New Double() {377, 397, 365, 380, 352, 365, 338, 353, 322, 342, 306, 334, 290, 328, 273, 325, 256, 325, 239, 326, 222, 331, 206, 337, 190, 347, 175, 358, 161, 372, 148, 387, 137, 404, 126, 423, 118, 444, 111, 465, 105, 488, 102, 511, 100, 534, 100, 558, 102, 582, 105, 605, 110, 627, 117, 649, 126, 669, 136, 688, 148, 705, 161, 721, 175, 735, 189, 746, 205, 755, 222, 762, 238, 767, 255, 768, 272, 768, 289, 765}),
                New Stroke(New Double() {381, 808, 373, 797, 364, 787, 355, 779, 344, 772, 334, 767, 323, 764, 311, 763, 300, 763, 289, 765}),
                New Stroke(New Double() {382, 807, 394, 824, 407, 839, 421, 851, 436, 861, 452, 870, 469, 875, 485, 879, 502, 879, 519, 878, 536, 874, 552, 867, 568, 858, 583, 847, 597, 834}),
                New Stroke(New Double() {689, 813, 679, 809, 668, 806, 657, 806, 646, 806, 636, 809, 625, 813, 615, 819, 606, 826, 597, 834}),
                New Stroke(New Double() {689, 812, 705, 818, 722, 822, 739, 823, 756, 822, 772, 819, 789, 813, 804, 804, 819, 794, 834, 781, 847, 766, 859, 750, 869, 732, 878, 712, 886, 691, 892, 669, 896, 646, 899, 623, 899, 600, 898, 576, 896, 553, 891, 531, 885, 509, 877, 488, 868, 469, 857, 451, 845, 434, 832, 420, 817, 408, 802, 397, 786, 389, 770, 384, 753, 380, 736, 380, 720, 381, 703, 385, 687, 392, 671, 401, 656, 412, 642, 425}),
                New Stroke(New Double() {550, 446, 560, 450, 571, 453, 582, 453, 593, 453, 603, 450, 614, 446, 624, 440, 633, 433, 642, 425}),
                New Stroke(New Double() {550, 447, 530, 440, 510, 436, 490, 436, 470, 439}),
                New Stroke(New Double() {378, 396, 386, 407, 395, 417, 404, 425, 415, 432, 425, 437, 436, 440, 448, 441, 459, 441, 470, 439})
            },
            New ChartDim() {
                New ChartDim("X", "x", 100, 204, 900, 204, True, "X - overall left-to-right bounds"),
                New ChartDim("Y", "y", 45, 324, 45, 880, False, "Y - overall front-to-back bounds"),
                New ChartDim("TL", "rl", 100, 547, 260, 547, True, "TL - top-left lobe radius"),
                New ChartDim("CE", "rt", 500, 880, 500, 658, False, "CE - center lobe radius"),
                New ChartDim("RI", "rr", 740, 602, 900, 602, True, "RI - right lobe radius"),
                New ChartDim("LB", "fbc", 340, 770, 281, 820, False, "LB - left-bottom tangent radius"),
                New ChartDim("RB", "fbr", 641, 808, 689, 865, False, "RB - right-bottom tangent radius"),
                New ChartDim("RT", "ftr", 599, 452, 645, 394, False, "RT - right-top tangent radius"),
                New ChartDim("LT", "ftl", 420, 435, 384, 371, False, "LT - left-top tangent radius")
            },
            New ListKey() {},
            New Mark() {},
            New Gate() {})
    }

    ''' <summary>LAZSPA's sheets, from lzs:*charts*.</summary>
    Public Shared ReadOnly Spa As Chart() = {
        New Chart("Rectangle", "Rectangle", "Rectangle",
            New Stroke() {
                New Stroke(New Double() {150, 250, 850, 250, 850, 820, 150, 820, 150, 250})
            },
            New ChartDim() {
                New ChartDim("W", "w", 150, 920, 850, 920, True, "W - overall WIDTH across (A-B)"),
                New ChartDim("L", "l", 75, 250, 75, 820, False, "L - overall LENGTH up (A-D)")
            },
            New ListKey() {},
            New Mark() {
                New Mark("D", 105, 210),
                New Mark("C", 895, 210),
                New Mark("A", 105, 860),
                New Mark("B", 895, 860)
            },
            New Gate() {}),
        New Chart("OCtagon", "OCtagon", "Octagon",
            New Stroke() {
                New Stroke(New Double() {200, 250, 800, 250, 900, 340, 900, 660, 800, 750, 200, 750, 100, 660, 100, 340, 200, 250})
            },
            New ChartDim() {
                New ChartDim("B", "b", 100, 130, 900, 130, True, "B - overall size ACROSS"),
                New ChartDim("S", "ss", 100, 200, 200, 200, True, "S - corner cut along the side"),
                New ChartDim("T", "tt", 200, 200, 800, 200, True, "T - flat across (top & bottom)"),
                New ChartDim("A", "a", 30, 250, 30, 750, False, "A - overall size UP"),
                New ChartDim("S1", "s1", 65, 250, 65, 340, False, "S1 - corner cut up the end"),
                New ChartDim("V", "vv", 65, 340, 65, 660, False, "V - flat up (left & right)")
            },
            New ListKey() {
                New ListKey("s2", "S2 - corner cut FACE (tape across it)")
            },
            New Mark() {},
            New Gate() {}),
        New Chart("ROund", "ROund", "Round",
            New Stroke() {
                New Stroke(New Double() {750, 500, 748, 473, 744, 448, 737, 422, 728, 398, 716, 375, 702, 353, 685, 332, 667, 314, 646, 297, 625, 283, 601, 271, 577, 262, 551, 255, 526, 251, 500, 250, 473, 251, 448, 255, 422, 262, 398, 271, 375, 283, 353, 297, 332, 314, 314, 332, 297, 353, 283, 375, 271, 398, 262, 422, 255, 448, 251, 473, 250, 499, 251, 526, 255, 551, 262, 577, 271, 601, 283, 625, 297, 646, 314, 667, 332, 685, 353, 702, 374, 716, 398, 728, 422, 737, 448, 744, 473, 748, 499, 750, 526, 748, 551, 744, 577, 737, 601, 728, 625, 716, 646, 702, 667, 685, 685, 667, 702, 646, 716, 625, 728, 601, 737, 577, 744, 551, 748, 526, 750, 500})
            },
            New ChartDim() {
                New ChartDim("B", "b", 250, 150, 750, 150, True, "B - overall diameter (across)"),
                New ChartDim("A", "a", 175, 250, 175, 750, False, "A - overall UP (only if out of round)")
            },
            New ListKey() {},
            New Mark() {},
            New Gate() {})
    }

    ''' <summary>The highest count LAZSTEP will draw a sheet
    ''' for - lzt:*max-steps*.  Past it the dialog would be
    ''' taller than the screen and simply not open.</summary>
    Public Const MaxSteps As Integer = 8

    ''' <summary>The three step routines, as lzt:*types* names
    ''' them: the command, its title, and the entry point a form
    ''' hands its answers to.</summary>
    Public Shared ReadOnly StepRoutines As StepRoutine() = {
        New StepRoutine("CORNERSTP", "Corner steps", "cs-run-with-answers"),
        New StepRoutine("HEMISTEP", "Hemi steps", "hs-run-with-answers"),
        New StepRoutine("NORMIESTEP", "Straight steps", "ns-run-with-answers")
    }

    ''' <summary>Every step sheet: one per routine per count.
    ''' LAZSTEP builds these from the count rather than keeping
    ''' a table, so the generator asked for every count the
    ''' dialog accepts.</summary>
    Public Shared ReadOnly StepSheets As StepChart() = {
        New StepChart("CORNERSTP", "Corner steps", 1,
            New Stroke() {
                New Stroke(New Double() {100, 180, 860, 60}),
                New Stroke(New Double() {100, 180, 860, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 765}),
                New Stroke(New Double() {860, 765, 100, 765}),
                New Stroke(New Double() {100, 765, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 860, 385, True, "Step 1 tread"),
                New ChartDim("W1", "width1", 860, 60, 860, 300, False, "Step 1 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 765, False, "Step 1 drop"),
                New ChartDim("DA", "depthafter", 140, 765, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("CORNERSTP", "Corner steps", 2,
            New Stroke() {
                New Stroke(New Double() {100, 180, 860, 60}),
                New Stroke(New Double() {100, 180, 860, 300}),
                New Stroke(New Double() {480, 120, 480, 240}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 690}),
                New Stroke(New Double() {860, 690, 480, 690}),
                New Stroke(New Double() {480, 690, 480, 840}),
                New Stroke(New Double() {480, 840, 100, 840}),
                New Stroke(New Double() {100, 840, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 480, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 480, 385, 860, 385, True, "Step 2 tread"),
                New ChartDim("W1", "width1", 480, 120, 480, 240, False, "Step 1 width"),
                New ChartDim("W2", "width2", 860, 60, 860, 300, False, "Step 2 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 690, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 520, 690, 520, 840, False, "Step 2 drop"),
                New ChartDim("DA", "depthafter", 140, 840, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("CORNERSTP", "Corner steps", 3,
            New Stroke() {
                New Stroke(New Double() {100, 180, 860, 60}),
                New Stroke(New Double() {100, 180, 860, 300}),
                New Stroke(New Double() {353, 141, 353, 219}),
                New Stroke(New Double() {606, 101, 606, 259}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 652}),
                New Stroke(New Double() {860, 652, 607, 652}),
                New Stroke(New Double() {607, 652, 607, 765}),
                New Stroke(New Double() {607, 765, 354, 765}),
                New Stroke(New Double() {354, 765, 354, 877}),
                New Stroke(New Double() {354, 877, 100, 877}),
                New Stroke(New Double() {100, 877, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 353, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 353, 385, 606, 385, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 606, 385, 860, 385, True, "Step 3 tread"),
                New ChartDim("W1", "width1", 353, 141, 353, 219, False, "Step 1 width"),
                New ChartDim("W2", "width2", 606, 101, 606, 259, False, "Step 2 width"),
                New ChartDim("W3", "width3", 860, 60, 860, 300, False, "Step 3 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 652, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 647, 652, 647, 765, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 394, 765, 394, 877, False, "Step 3 drop"),
                New ChartDim("DA", "depthafter", 140, 877, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("CORNERSTP", "Corner steps", 4,
            New Stroke() {
                New Stroke(New Double() {100, 180, 860, 60}),
                New Stroke(New Double() {100, 180, 860, 300}),
                New Stroke(New Double() {290, 150, 290, 210}),
                New Stroke(New Double() {480, 120, 480, 240}),
                New Stroke(New Double() {670, 90, 670, 270}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 630}),
                New Stroke(New Double() {860, 630, 670, 630}),
                New Stroke(New Double() {670, 630, 670, 720}),
                New Stroke(New Double() {670, 720, 480, 720}),
                New Stroke(New Double() {480, 720, 480, 810}),
                New Stroke(New Double() {480, 810, 290, 810}),
                New Stroke(New Double() {290, 810, 290, 900}),
                New Stroke(New Double() {290, 900, 100, 900}),
                New Stroke(New Double() {100, 900, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 290, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 290, 385, 480, 385, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 480, 385, 670, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 670, 385, 860, 385, True, "Step 4 tread"),
                New ChartDim("W1", "width1", 290, 150, 290, 210, False, "Step 1 width"),
                New ChartDim("W2", "width2", 480, 120, 480, 240, False, "Step 2 width"),
                New ChartDim("W3", "width3", 670, 90, 670, 270, False, "Step 3 width"),
                New ChartDim("W4", "width4", 860, 60, 860, 300, False, "Step 4 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 630, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 710, 630, 710, 720, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 520, 720, 520, 810, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 330, 810, 330, 900, False, "Step 4 drop"),
                New ChartDim("DA", "depthafter", 140, 900, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("CORNERSTP", "Corner steps", 5,
            New Stroke() {
                New Stroke(New Double() {100, 180, 860, 60}),
                New Stroke(New Double() {100, 180, 860, 300}),
                New Stroke(New Double() {252, 156, 252, 204}),
                New Stroke(New Double() {404, 132, 404, 228}),
                New Stroke(New Double() {556, 108, 556, 252}),
                New Stroke(New Double() {708, 84, 708, 276}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 615}),
                New Stroke(New Double() {860, 615, 708, 615}),
                New Stroke(New Double() {708, 615, 708, 690}),
                New Stroke(New Double() {708, 690, 556, 690}),
                New Stroke(New Double() {556, 690, 556, 765}),
                New Stroke(New Double() {556, 765, 404, 765}),
                New Stroke(New Double() {404, 765, 404, 840}),
                New Stroke(New Double() {404, 840, 252, 840}),
                New Stroke(New Double() {252, 840, 252, 915}),
                New Stroke(New Double() {252, 915, 100, 915}),
                New Stroke(New Double() {100, 915, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 252, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 252, 445, 404, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 404, 385, 556, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 556, 445, 708, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 708, 385, 860, 385, True, "Step 5 tread"),
                New ChartDim("W1", "width1", 252, 156, 252, 204, False, "Step 1 width"),
                New ChartDim("W2", "width2", 404, 132, 404, 228, False, "Step 2 width"),
                New ChartDim("W3", "width3", 556, 108, 556, 252, False, "Step 3 width"),
                New ChartDim("W4", "width4", 708, 84, 708, 276, False, "Step 4 width"),
                New ChartDim("W5", "width5", 860, 60, 860, 300, False, "Step 5 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 615, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 748, 615, 748, 690, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 596, 690, 596, 765, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 444, 765, 444, 840, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 292, 840, 292, 915, False, "Step 5 drop"),
                New ChartDim("DA", "depthafter", 140, 915, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("CORNERSTP", "Corner steps", 6,
            New Stroke() {
                New Stroke(New Double() {100, 180, 860, 60}),
                New Stroke(New Double() {100, 180, 860, 300}),
                New Stroke(New Double() {226, 161, 226, 199}),
                New Stroke(New Double() {353, 141, 353, 219}),
                New Stroke(New Double() {480, 120, 480, 240}),
                New Stroke(New Double() {606, 101, 606, 259}),
                New Stroke(New Double() {733, 81, 733, 279}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 604}),
                New Stroke(New Double() {860, 604, 734, 604}),
                New Stroke(New Double() {734, 604, 734, 668}),
                New Stroke(New Double() {734, 668, 607, 668}),
                New Stroke(New Double() {607, 668, 607, 732}),
                New Stroke(New Double() {607, 732, 480, 732}),
                New Stroke(New Double() {480, 732, 480, 797}),
                New Stroke(New Double() {480, 797, 354, 797}),
                New Stroke(New Double() {354, 797, 354, 861}),
                New Stroke(New Double() {354, 861, 227, 861}),
                New Stroke(New Double() {227, 861, 227, 925}),
                New Stroke(New Double() {227, 925, 100, 925}),
                New Stroke(New Double() {100, 925, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 226, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 226, 445, 353, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 353, 385, 480, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 480, 445, 606, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 606, 385, 733, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 733, 445, 860, 445, True, "Step 6 tread"),
                New ChartDim("W1", "width1", 226, 161, 226, 199, False, "Step 1 width"),
                New ChartDim("W2", "width2", 353, 141, 353, 219, False, "Step 2 width"),
                New ChartDim("W3", "width3", 480, 120, 480, 240, False, "Step 3 width"),
                New ChartDim("W4", "width4", 606, 101, 606, 259, False, "Step 4 width"),
                New ChartDim("W5", "width5", 733, 81, 733, 279, False, "Step 5 width"),
                New ChartDim("W6", "width6", 860, 60, 860, 300, False, "Step 6 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 604, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 774, 604, 774, 668, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 647, 668, 647, 732, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 520, 732, 520, 797, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 394, 797, 394, 861, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 267, 861, 267, 925, False, "Step 6 drop"),
                New ChartDim("DA", "depthafter", 140, 925, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("CORNERSTP", "Corner steps", 7,
            New Stroke() {
                New Stroke(New Double() {100, 180, 860, 60}),
                New Stroke(New Double() {100, 180, 860, 300}),
                New Stroke(New Double() {208, 163, 208, 197}),
                New Stroke(New Double() {317, 146, 317, 214}),
                New Stroke(New Double() {425, 129, 425, 231}),
                New Stroke(New Double() {534, 112, 534, 248}),
                New Stroke(New Double() {642, 95, 642, 265}),
                New Stroke(New Double() {751, 78, 751, 282}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 596}),
                New Stroke(New Double() {860, 596, 752, 596}),
                New Stroke(New Double() {752, 596, 752, 652}),
                New Stroke(New Double() {752, 652, 643, 652}),
                New Stroke(New Double() {643, 652, 643, 708}),
                New Stroke(New Double() {643, 708, 535, 708}),
                New Stroke(New Double() {535, 708, 535, 765}),
                New Stroke(New Double() {535, 765, 426, 765}),
                New Stroke(New Double() {426, 765, 426, 821}),
                New Stroke(New Double() {426, 821, 318, 821}),
                New Stroke(New Double() {318, 821, 318, 877}),
                New Stroke(New Double() {318, 877, 209, 877}),
                New Stroke(New Double() {209, 877, 209, 933}),
                New Stroke(New Double() {209, 933, 100, 933}),
                New Stroke(New Double() {100, 933, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 208, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 208, 445, 317, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 317, 385, 425, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 425, 445, 534, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 534, 385, 642, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 642, 445, 751, 445, True, "Step 6 tread"),
                New ChartDim("T7", "tread7", 751, 385, 860, 385, True, "Step 7 tread"),
                New ChartDim("W1", "width1", 208, 163, 208, 197, False, "Step 1 width"),
                New ChartDim("W2", "width2", 317, 146, 317, 214, False, "Step 2 width"),
                New ChartDim("W3", "width3", 425, 129, 425, 231, False, "Step 3 width"),
                New ChartDim("W4", "width4", 534, 112, 534, 248, False, "Step 4 width"),
                New ChartDim("W5", "width5", 642, 95, 642, 265, False, "Step 5 width"),
                New ChartDim("W6", "width6", 751, 78, 751, 282, False, "Step 6 width"),
                New ChartDim("W7", "width7", 860, 60, 860, 300, False, "Step 7 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 596, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 792, 596, 792, 652, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 683, 652, 683, 708, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 575, 708, 575, 765, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 466, 765, 466, 821, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 358, 821, 358, 877, False, "Step 6 drop"),
                New ChartDim("D7", "depth7", 249, 877, 249, 933, False, "Step 7 drop"),
                New ChartDim("DA", "depthafter", 140, 933, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("CORNERSTP", "Corner steps", 8,
            New Stroke() {
                New Stroke(New Double() {100, 180, 860, 60}),
                New Stroke(New Double() {100, 180, 860, 300}),
                New Stroke(New Double() {195, 165, 195, 195}),
                New Stroke(New Double() {290, 150, 290, 210}),
                New Stroke(New Double() {385, 135, 385, 225}),
                New Stroke(New Double() {480, 120, 480, 240}),
                New Stroke(New Double() {575, 105, 575, 255}),
                New Stroke(New Double() {670, 90, 670, 270}),
                New Stroke(New Double() {765, 75, 765, 285}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 590}),
                New Stroke(New Double() {860, 590, 765, 590}),
                New Stroke(New Double() {765, 590, 765, 640}),
                New Stroke(New Double() {765, 640, 670, 640}),
                New Stroke(New Double() {670, 640, 670, 690}),
                New Stroke(New Double() {670, 690, 575, 690}),
                New Stroke(New Double() {575, 690, 575, 740}),
                New Stroke(New Double() {575, 740, 480, 740}),
                New Stroke(New Double() {480, 740, 480, 790}),
                New Stroke(New Double() {480, 790, 385, 790}),
                New Stroke(New Double() {385, 790, 385, 840}),
                New Stroke(New Double() {385, 840, 290, 840}),
                New Stroke(New Double() {290, 840, 290, 890}),
                New Stroke(New Double() {290, 890, 195, 890}),
                New Stroke(New Double() {195, 890, 195, 940}),
                New Stroke(New Double() {195, 940, 100, 940}),
                New Stroke(New Double() {100, 940, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 195, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 195, 445, 290, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 290, 385, 385, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 385, 445, 480, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 480, 385, 575, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 575, 445, 670, 445, True, "Step 6 tread"),
                New ChartDim("T7", "tread7", 670, 385, 765, 385, True, "Step 7 tread"),
                New ChartDim("T8", "tread8", 765, 445, 860, 445, True, "Step 8 tread"),
                New ChartDim("W1", "width1", 195, 165, 195, 195, False, "Step 1 width"),
                New ChartDim("W2", "width2", 290, 150, 290, 210, False, "Step 2 width"),
                New ChartDim("W3", "width3", 385, 135, 385, 225, False, "Step 3 width"),
                New ChartDim("W4", "width4", 480, 120, 480, 240, False, "Step 4 width"),
                New ChartDim("W5", "width5", 575, 105, 575, 255, False, "Step 5 width"),
                New ChartDim("W6", "width6", 670, 90, 670, 270, False, "Step 6 width"),
                New ChartDim("W7", "width7", 765, 75, 765, 285, False, "Step 7 width"),
                New ChartDim("W8", "width8", 860, 60, 860, 300, False, "Step 8 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 590, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 805, 590, 805, 640, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 710, 640, 710, 690, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 615, 690, 615, 740, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 520, 740, 520, 790, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 425, 790, 425, 840, False, "Step 6 drop"),
                New ChartDim("D7", "depth7", 330, 840, 330, 890, False, "Step 7 drop"),
                New ChartDim("D8", "depth8", 235, 890, 235, 940, False, "Step 8 drop"),
                New ChartDim("DA", "depthafter", 140, 940, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("HEMISTEP", "Hemi steps", 1,
            New Stroke() {
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {100, 60, 187, 60, 274, 62, 359, 65, 441, 70, 520, 76, 593, 82, 662, 90, 724, 99, 779, 109, 827, 120, 867, 131, 898, 142, 921, 155, 935, 167, 940, 180, 935, 192, 921, 204, 898, 217, 867, 228, 827, 240, 779, 250, 724, 260, 662, 269, 593, 277, 520, 283, 441, 289, 359, 294, 274, 297, 187, 299, 100, 300}),
                New Stroke(New Double() {860, 129, 860, 231}),
                New Stroke(New Double() {860, 540, 860, 765}),
                New Stroke(New Double() {860, 765, 100, 765}),
                New Stroke(New Double() {100, 765, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 860, 385, True, "Step 1 tread"),
                New ChartDim("W1", "width1", 860, 129, 860, 231, False, "Step 1 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 765, False, "Drop at the wall"),
                New ChartDim("DA", "depthafter", 140, 765, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("HEMISTEP", "Hemi steps", 2,
            New Stroke() {
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {100, 60, 187, 60, 274, 62, 359, 65, 441, 70, 520, 76, 593, 82, 662, 90, 724, 99, 779, 109, 827, 120, 867, 131, 898, 142, 921, 155, 935, 167, 940, 180, 935, 192, 921, 204, 898, 217, 867, 228, 827, 240, 779, 250, 724, 260, 662, 269, 593, 277, 520, 283, 441, 289, 359, 294, 274, 297, 187, 299, 100, 300}),
                New Stroke(New Double() {480, 73, 480, 287}),
                New Stroke(New Double() {860, 129, 860, 231}),
                New Stroke(New Double() {860, 540, 860, 690}),
                New Stroke(New Double() {860, 690, 480, 690}),
                New Stroke(New Double() {480, 690, 480, 840}),
                New Stroke(New Double() {480, 840, 100, 840}),
                New Stroke(New Double() {100, 840, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 480, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 480, 385, 860, 385, True, "Step 2 tread"),
                New ChartDim("W1", "width1", 480, 73, 480, 287, False, "Step 1 width"),
                New ChartDim("W2", "width2", 860, 129, 860, 231, False, "Step 2 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 690, False, "Drop at the wall"),
                New ChartDim("D2", "depth2", 520, 690, 520, 840, False, "Step 2 drop"),
                New ChartDim("DA", "depthafter", 140, 840, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("HEMISTEP", "Hemi steps", 3,
            New Stroke() {
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {100, 60, 187, 60, 274, 62, 359, 65, 441, 70, 520, 76, 593, 82, 662, 90, 724, 99, 779, 109, 827, 120, 867, 131, 898, 142, 921, 155, 935, 167, 940, 180, 935, 192, 921, 204, 898, 217, 867, 228, 827, 240, 779, 250, 724, 260, 662, 269, 593, 277, 520, 283, 441, 289, 359, 294, 274, 297, 187, 299, 100, 300}),
                New Stroke(New Double() {353, 66, 353, 294}),
                New Stroke(New Double() {606, 85, 606, 275}),
                New Stroke(New Double() {860, 129, 860, 231}),
                New Stroke(New Double() {860, 540, 860, 652}),
                New Stroke(New Double() {860, 652, 607, 652}),
                New Stroke(New Double() {607, 652, 607, 765}),
                New Stroke(New Double() {607, 765, 354, 765}),
                New Stroke(New Double() {354, 765, 354, 877}),
                New Stroke(New Double() {354, 877, 100, 877}),
                New Stroke(New Double() {100, 877, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 353, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 353, 385, 606, 385, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 606, 385, 860, 385, True, "Step 3 tread"),
                New ChartDim("W1", "width1", 353, 66, 353, 294, False, "Step 1 width"),
                New ChartDim("W2", "width2", 606, 85, 606, 275, False, "Step 2 width"),
                New ChartDim("W3", "width3", 860, 129, 860, 231, False, "Step 3 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 652, False, "Drop at the wall"),
                New ChartDim("D2", "depth2", 647, 652, 647, 765, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 394, 765, 394, 877, False, "Step 3 drop"),
                New ChartDim("DA", "depthafter", 140, 877, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("HEMISTEP", "Hemi steps", 4,
            New Stroke() {
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {100, 60, 187, 60, 274, 62, 359, 65, 441, 70, 520, 76, 593, 82, 662, 90, 724, 99, 779, 109, 827, 120, 867, 131, 898, 142, 921, 155, 935, 167, 940, 180, 935, 192, 921, 204, 898, 217, 867, 228, 827, 240, 779, 250, 724, 260, 662, 269, 593, 277, 520, 283, 441, 289, 359, 294, 274, 297, 187, 299, 100, 300}),
                New Stroke(New Double() {290, 64, 290, 296}),
                New Stroke(New Double() {480, 73, 480, 287}),
                New Stroke(New Double() {670, 92, 670, 268}),
                New Stroke(New Double() {860, 129, 860, 231}),
                New Stroke(New Double() {860, 540, 860, 630}),
                New Stroke(New Double() {860, 630, 670, 630}),
                New Stroke(New Double() {670, 630, 670, 720}),
                New Stroke(New Double() {670, 720, 480, 720}),
                New Stroke(New Double() {480, 720, 480, 810}),
                New Stroke(New Double() {480, 810, 290, 810}),
                New Stroke(New Double() {290, 810, 290, 900}),
                New Stroke(New Double() {290, 900, 100, 900}),
                New Stroke(New Double() {100, 900, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 290, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 290, 385, 480, 385, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 480, 385, 670, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 670, 385, 860, 385, True, "Step 4 tread"),
                New ChartDim("W1", "width1", 290, 64, 290, 296, False, "Step 1 width"),
                New ChartDim("W2", "width2", 480, 73, 480, 287, False, "Step 2 width"),
                New ChartDim("W3", "width3", 670, 92, 670, 268, False, "Step 3 width"),
                New ChartDim("W4", "width4", 860, 129, 860, 231, False, "Step 4 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 630, False, "Drop at the wall"),
                New ChartDim("D2", "depth2", 710, 630, 710, 720, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 520, 720, 520, 810, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 330, 810, 330, 900, False, "Step 4 drop"),
                New ChartDim("DA", "depthafter", 140, 900, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("HEMISTEP", "Hemi steps", 5,
            New Stroke() {
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {100, 60, 187, 60, 274, 62, 359, 65, 441, 70, 520, 76, 593, 82, 662, 90, 724, 99, 779, 109, 827, 120, 867, 131, 898, 142, 921, 155, 935, 167, 940, 180, 935, 192, 921, 204, 898, 217, 867, 228, 827, 240, 779, 250, 724, 260, 662, 269, 593, 277, 520, 283, 441, 289, 359, 294, 274, 297, 187, 299, 100, 300}),
                New Stroke(New Double() {252, 62, 252, 298}),
                New Stroke(New Double() {404, 69, 404, 291}),
                New Stroke(New Double() {556, 80, 556, 280}),
                New Stroke(New Double() {708, 98, 708, 262}),
                New Stroke(New Double() {860, 129, 860, 231}),
                New Stroke(New Double() {860, 540, 860, 615}),
                New Stroke(New Double() {860, 615, 708, 615}),
                New Stroke(New Double() {708, 615, 708, 690}),
                New Stroke(New Double() {708, 690, 556, 690}),
                New Stroke(New Double() {556, 690, 556, 765}),
                New Stroke(New Double() {556, 765, 404, 765}),
                New Stroke(New Double() {404, 765, 404, 840}),
                New Stroke(New Double() {404, 840, 252, 840}),
                New Stroke(New Double() {252, 840, 252, 915}),
                New Stroke(New Double() {252, 915, 100, 915}),
                New Stroke(New Double() {100, 915, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 252, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 252, 445, 404, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 404, 385, 556, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 556, 445, 708, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 708, 385, 860, 385, True, "Step 5 tread"),
                New ChartDim("W1", "width1", 252, 62, 252, 298, False, "Step 1 width"),
                New ChartDim("W2", "width2", 404, 69, 404, 291, False, "Step 2 width"),
                New ChartDim("W3", "width3", 556, 80, 556, 280, False, "Step 3 width"),
                New ChartDim("W4", "width4", 708, 98, 708, 262, False, "Step 4 width"),
                New ChartDim("W5", "width5", 860, 129, 860, 231, False, "Step 5 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 615, False, "Drop at the wall"),
                New ChartDim("D2", "depth2", 748, 615, 748, 690, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 596, 690, 596, 765, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 444, 765, 444, 840, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 292, 840, 292, 915, False, "Step 5 drop"),
                New ChartDim("DA", "depthafter", 140, 915, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("HEMISTEP", "Hemi steps", 6,
            New Stroke() {
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {100, 60, 187, 60, 274, 62, 359, 65, 441, 70, 520, 76, 593, 82, 662, 90, 724, 99, 779, 109, 827, 120, 867, 131, 898, 142, 921, 155, 935, 167, 940, 180, 935, 192, 921, 204, 898, 217, 867, 228, 827, 240, 779, 250, 724, 260, 662, 269, 593, 277, 520, 283, 441, 289, 359, 294, 274, 297, 187, 299, 100, 300}),
                New Stroke(New Double() {226, 62, 226, 298}),
                New Stroke(New Double() {353, 66, 353, 294}),
                New Stroke(New Double() {480, 73, 480, 287}),
                New Stroke(New Double() {606, 85, 606, 275}),
                New Stroke(New Double() {733, 102, 733, 258}),
                New Stroke(New Double() {860, 129, 860, 231}),
                New Stroke(New Double() {860, 540, 860, 604}),
                New Stroke(New Double() {860, 604, 734, 604}),
                New Stroke(New Double() {734, 604, 734, 668}),
                New Stroke(New Double() {734, 668, 607, 668}),
                New Stroke(New Double() {607, 668, 607, 732}),
                New Stroke(New Double() {607, 732, 480, 732}),
                New Stroke(New Double() {480, 732, 480, 797}),
                New Stroke(New Double() {480, 797, 354, 797}),
                New Stroke(New Double() {354, 797, 354, 861}),
                New Stroke(New Double() {354, 861, 227, 861}),
                New Stroke(New Double() {227, 861, 227, 925}),
                New Stroke(New Double() {227, 925, 100, 925}),
                New Stroke(New Double() {100, 925, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 226, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 226, 445, 353, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 353, 385, 480, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 480, 445, 606, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 606, 385, 733, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 733, 445, 860, 445, True, "Step 6 tread"),
                New ChartDim("W1", "width1", 226, 62, 226, 298, False, "Step 1 width"),
                New ChartDim("W2", "width2", 353, 66, 353, 294, False, "Step 2 width"),
                New ChartDim("W3", "width3", 480, 73, 480, 287, False, "Step 3 width"),
                New ChartDim("W4", "width4", 606, 85, 606, 275, False, "Step 4 width"),
                New ChartDim("W5", "width5", 733, 102, 733, 258, False, "Step 5 width"),
                New ChartDim("W6", "width6", 860, 129, 860, 231, False, "Step 6 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 604, False, "Drop at the wall"),
                New ChartDim("D2", "depth2", 774, 604, 774, 668, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 647, 668, 647, 732, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 520, 732, 520, 797, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 394, 797, 394, 861, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 267, 861, 267, 925, False, "Step 6 drop"),
                New ChartDim("DA", "depthafter", 140, 925, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("HEMISTEP", "Hemi steps", 7,
            New Stroke() {
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {100, 60, 187, 60, 274, 62, 359, 65, 441, 70, 520, 76, 593, 82, 662, 90, 724, 99, 779, 109, 827, 120, 867, 131, 898, 142, 921, 155, 935, 167, 940, 180, 935, 192, 921, 204, 898, 217, 867, 228, 827, 240, 779, 250, 724, 260, 662, 269, 593, 277, 520, 283, 441, 289, 359, 294, 274, 297, 187, 299, 100, 300}),
                New Stroke(New Double() {208, 61, 208, 299}),
                New Stroke(New Double() {317, 65, 317, 295}),
                New Stroke(New Double() {425, 70, 425, 290}),
                New Stroke(New Double() {534, 78, 534, 282}),
                New Stroke(New Double() {642, 89, 642, 271}),
                New Stroke(New Double() {751, 105, 751, 255}),
                New Stroke(New Double() {860, 129, 860, 231}),
                New Stroke(New Double() {860, 540, 860, 596}),
                New Stroke(New Double() {860, 596, 752, 596}),
                New Stroke(New Double() {752, 596, 752, 652}),
                New Stroke(New Double() {752, 652, 643, 652}),
                New Stroke(New Double() {643, 652, 643, 708}),
                New Stroke(New Double() {643, 708, 535, 708}),
                New Stroke(New Double() {535, 708, 535, 765}),
                New Stroke(New Double() {535, 765, 426, 765}),
                New Stroke(New Double() {426, 765, 426, 821}),
                New Stroke(New Double() {426, 821, 318, 821}),
                New Stroke(New Double() {318, 821, 318, 877}),
                New Stroke(New Double() {318, 877, 209, 877}),
                New Stroke(New Double() {209, 877, 209, 933}),
                New Stroke(New Double() {209, 933, 100, 933}),
                New Stroke(New Double() {100, 933, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 208, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 208, 445, 317, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 317, 385, 425, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 425, 445, 534, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 534, 385, 642, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 642, 445, 751, 445, True, "Step 6 tread"),
                New ChartDim("T7", "tread7", 751, 385, 860, 385, True, "Step 7 tread"),
                New ChartDim("W1", "width1", 208, 61, 208, 299, False, "Step 1 width"),
                New ChartDim("W2", "width2", 317, 65, 317, 295, False, "Step 2 width"),
                New ChartDim("W3", "width3", 425, 70, 425, 290, False, "Step 3 width"),
                New ChartDim("W4", "width4", 534, 78, 534, 282, False, "Step 4 width"),
                New ChartDim("W5", "width5", 642, 89, 642, 271, False, "Step 5 width"),
                New ChartDim("W6", "width6", 751, 105, 751, 255, False, "Step 6 width"),
                New ChartDim("W7", "width7", 860, 129, 860, 231, False, "Step 7 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 596, False, "Drop at the wall"),
                New ChartDim("D2", "depth2", 792, 596, 792, 652, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 683, 652, 683, 708, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 575, 708, 575, 765, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 466, 765, 466, 821, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 358, 821, 358, 877, False, "Step 6 drop"),
                New ChartDim("D7", "depth7", 249, 877, 249, 933, False, "Step 7 drop"),
                New ChartDim("DA", "depthafter", 140, 933, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("HEMISTEP", "Hemi steps", 8,
            New Stroke() {
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {100, 60, 187, 60, 274, 62, 359, 65, 441, 70, 520, 76, 593, 82, 662, 90, 724, 99, 779, 109, 827, 120, 867, 131, 898, 142, 921, 155, 935, 167, 940, 180, 935, 192, 921, 204, 898, 217, 867, 228, 827, 240, 779, 250, 724, 260, 662, 269, 593, 277, 520, 283, 441, 289, 359, 294, 274, 297, 187, 299, 100, 300}),
                New Stroke(New Double() {195, 61, 195, 299}),
                New Stroke(New Double() {290, 64, 290, 296}),
                New Stroke(New Double() {385, 68, 385, 292}),
                New Stroke(New Double() {480, 73, 480, 287}),
                New Stroke(New Double() {575, 82, 575, 278}),
                New Stroke(New Double() {670, 92, 670, 268}),
                New Stroke(New Double() {765, 107, 765, 253}),
                New Stroke(New Double() {860, 129, 860, 231}),
                New Stroke(New Double() {860, 540, 860, 590}),
                New Stroke(New Double() {860, 590, 765, 590}),
                New Stroke(New Double() {765, 590, 765, 640}),
                New Stroke(New Double() {765, 640, 670, 640}),
                New Stroke(New Double() {670, 640, 670, 690}),
                New Stroke(New Double() {670, 690, 575, 690}),
                New Stroke(New Double() {575, 690, 575, 740}),
                New Stroke(New Double() {575, 740, 480, 740}),
                New Stroke(New Double() {480, 740, 480, 790}),
                New Stroke(New Double() {480, 790, 385, 790}),
                New Stroke(New Double() {385, 790, 385, 840}),
                New Stroke(New Double() {385, 840, 290, 840}),
                New Stroke(New Double() {290, 840, 290, 890}),
                New Stroke(New Double() {290, 890, 195, 890}),
                New Stroke(New Double() {195, 890, 195, 940}),
                New Stroke(New Double() {195, 940, 100, 940}),
                New Stroke(New Double() {100, 940, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 195, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 195, 445, 290, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 290, 385, 385, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 385, 445, 480, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 480, 385, 575, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 575, 445, 670, 445, True, "Step 6 tread"),
                New ChartDim("T7", "tread7", 670, 385, 765, 385, True, "Step 7 tread"),
                New ChartDim("T8", "tread8", 765, 445, 860, 445, True, "Step 8 tread"),
                New ChartDim("W1", "width1", 195, 61, 195, 299, False, "Step 1 width"),
                New ChartDim("W2", "width2", 290, 64, 290, 296, False, "Step 2 width"),
                New ChartDim("W3", "width3", 385, 68, 385, 292, False, "Step 3 width"),
                New ChartDim("W4", "width4", 480, 73, 480, 287, False, "Step 4 width"),
                New ChartDim("W5", "width5", 575, 82, 575, 278, False, "Step 5 width"),
                New ChartDim("W6", "width6", 670, 92, 670, 268, False, "Step 6 width"),
                New ChartDim("W7", "width7", 765, 107, 765, 253, False, "Step 7 width"),
                New ChartDim("W8", "width8", 860, 129, 860, 231, False, "Step 8 width"),
                New ChartDim("D1", "depth1", 900, 540, 900, 590, False, "Drop at the wall"),
                New ChartDim("D2", "depth2", 805, 590, 805, 640, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 710, 640, 710, 690, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 615, 690, 615, 740, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 520, 740, 520, 790, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 425, 790, 425, 840, False, "Step 6 drop"),
                New ChartDim("D7", "depth7", 330, 840, 330, 890, False, "Step 7 drop"),
                New ChartDim("D8", "depth8", 235, 890, 235, 940, False, "Step 8 drop"),
                New ChartDim("DA", "depthafter", 140, 940, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("NORMIESTEP", "Straight steps", 1,
            New Stroke() {
                New Stroke(New Double() {100, 60, 860, 60}),
                New Stroke(New Double() {100, 300, 860, 300}),
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 765}),
                New Stroke(New Double() {860, 765, 100, 765}),
                New Stroke(New Double() {100, 765, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 860, 385, True, "Step 1 tread"),
                New ChartDim("W", "width", 930, 60, 930, 300, False, "One width, the whole run"),
                New ChartDim("D1", "depth1", 900, 540, 900, 765, False, "Step 1 drop"),
                New ChartDim("DA", "depthafter", 140, 765, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("NORMIESTEP", "Straight steps", 2,
            New Stroke() {
                New Stroke(New Double() {100, 60, 860, 60}),
                New Stroke(New Double() {100, 300, 860, 300}),
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {480, 60, 480, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 690}),
                New Stroke(New Double() {860, 690, 480, 690}),
                New Stroke(New Double() {480, 690, 480, 840}),
                New Stroke(New Double() {480, 840, 100, 840}),
                New Stroke(New Double() {100, 840, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 480, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 480, 385, 860, 385, True, "Step 2 tread"),
                New ChartDim("W", "width", 930, 60, 930, 300, False, "One width, the whole run"),
                New ChartDim("D1", "depth1", 900, 540, 900, 690, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 520, 690, 520, 840, False, "Step 2 drop"),
                New ChartDim("DA", "depthafter", 140, 840, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("NORMIESTEP", "Straight steps", 3,
            New Stroke() {
                New Stroke(New Double() {100, 60, 860, 60}),
                New Stroke(New Double() {100, 300, 860, 300}),
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {353, 60, 353, 300}),
                New Stroke(New Double() {606, 60, 606, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 652}),
                New Stroke(New Double() {860, 652, 607, 652}),
                New Stroke(New Double() {607, 652, 607, 765}),
                New Stroke(New Double() {607, 765, 354, 765}),
                New Stroke(New Double() {354, 765, 354, 877}),
                New Stroke(New Double() {354, 877, 100, 877}),
                New Stroke(New Double() {100, 877, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 353, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 353, 385, 606, 385, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 606, 385, 860, 385, True, "Step 3 tread"),
                New ChartDim("W", "width", 930, 60, 930, 300, False, "One width, the whole run"),
                New ChartDim("D1", "depth1", 900, 540, 900, 652, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 647, 652, 647, 765, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 394, 765, 394, 877, False, "Step 3 drop"),
                New ChartDim("DA", "depthafter", 140, 877, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("NORMIESTEP", "Straight steps", 4,
            New Stroke() {
                New Stroke(New Double() {100, 60, 860, 60}),
                New Stroke(New Double() {100, 300, 860, 300}),
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {290, 60, 290, 300}),
                New Stroke(New Double() {480, 60, 480, 300}),
                New Stroke(New Double() {670, 60, 670, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 630}),
                New Stroke(New Double() {860, 630, 670, 630}),
                New Stroke(New Double() {670, 630, 670, 720}),
                New Stroke(New Double() {670, 720, 480, 720}),
                New Stroke(New Double() {480, 720, 480, 810}),
                New Stroke(New Double() {480, 810, 290, 810}),
                New Stroke(New Double() {290, 810, 290, 900}),
                New Stroke(New Double() {290, 900, 100, 900}),
                New Stroke(New Double() {100, 900, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 290, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 290, 385, 480, 385, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 480, 385, 670, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 670, 385, 860, 385, True, "Step 4 tread"),
                New ChartDim("W", "width", 930, 60, 930, 300, False, "One width, the whole run"),
                New ChartDim("D1", "depth1", 900, 540, 900, 630, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 710, 630, 710, 720, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 520, 720, 520, 810, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 330, 810, 330, 900, False, "Step 4 drop"),
                New ChartDim("DA", "depthafter", 140, 900, 140, 990, False, "after the last tread")
            },
            New Double() {385}),
        New StepChart("NORMIESTEP", "Straight steps", 5,
            New Stroke() {
                New Stroke(New Double() {100, 60, 860, 60}),
                New Stroke(New Double() {100, 300, 860, 300}),
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {252, 60, 252, 300}),
                New Stroke(New Double() {404, 60, 404, 300}),
                New Stroke(New Double() {556, 60, 556, 300}),
                New Stroke(New Double() {708, 60, 708, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 615}),
                New Stroke(New Double() {860, 615, 708, 615}),
                New Stroke(New Double() {708, 615, 708, 690}),
                New Stroke(New Double() {708, 690, 556, 690}),
                New Stroke(New Double() {556, 690, 556, 765}),
                New Stroke(New Double() {556, 765, 404, 765}),
                New Stroke(New Double() {404, 765, 404, 840}),
                New Stroke(New Double() {404, 840, 252, 840}),
                New Stroke(New Double() {252, 840, 252, 915}),
                New Stroke(New Double() {252, 915, 100, 915}),
                New Stroke(New Double() {100, 915, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 252, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 252, 445, 404, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 404, 385, 556, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 556, 445, 708, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 708, 385, 860, 385, True, "Step 5 tread"),
                New ChartDim("W", "width", 930, 60, 930, 300, False, "One width, the whole run"),
                New ChartDim("D1", "depth1", 900, 540, 900, 615, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 748, 615, 748, 690, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 596, 690, 596, 765, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 444, 765, 444, 840, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 292, 840, 292, 915, False, "Step 5 drop"),
                New ChartDim("DA", "depthafter", 140, 915, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("NORMIESTEP", "Straight steps", 6,
            New Stroke() {
                New Stroke(New Double() {100, 60, 860, 60}),
                New Stroke(New Double() {100, 300, 860, 300}),
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {226, 60, 226, 300}),
                New Stroke(New Double() {353, 60, 353, 300}),
                New Stroke(New Double() {480, 60, 480, 300}),
                New Stroke(New Double() {606, 60, 606, 300}),
                New Stroke(New Double() {733, 60, 733, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 604}),
                New Stroke(New Double() {860, 604, 734, 604}),
                New Stroke(New Double() {734, 604, 734, 668}),
                New Stroke(New Double() {734, 668, 607, 668}),
                New Stroke(New Double() {607, 668, 607, 732}),
                New Stroke(New Double() {607, 732, 480, 732}),
                New Stroke(New Double() {480, 732, 480, 797}),
                New Stroke(New Double() {480, 797, 354, 797}),
                New Stroke(New Double() {354, 797, 354, 861}),
                New Stroke(New Double() {354, 861, 227, 861}),
                New Stroke(New Double() {227, 861, 227, 925}),
                New Stroke(New Double() {227, 925, 100, 925}),
                New Stroke(New Double() {100, 925, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 226, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 226, 445, 353, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 353, 385, 480, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 480, 445, 606, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 606, 385, 733, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 733, 445, 860, 445, True, "Step 6 tread"),
                New ChartDim("W", "width", 930, 60, 930, 300, False, "One width, the whole run"),
                New ChartDim("D1", "depth1", 900, 540, 900, 604, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 774, 604, 774, 668, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 647, 668, 647, 732, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 520, 732, 520, 797, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 394, 797, 394, 861, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 267, 861, 267, 925, False, "Step 6 drop"),
                New ChartDim("DA", "depthafter", 140, 925, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("NORMIESTEP", "Straight steps", 7,
            New Stroke() {
                New Stroke(New Double() {100, 60, 860, 60}),
                New Stroke(New Double() {100, 300, 860, 300}),
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {208, 60, 208, 300}),
                New Stroke(New Double() {317, 60, 317, 300}),
                New Stroke(New Double() {425, 60, 425, 300}),
                New Stroke(New Double() {534, 60, 534, 300}),
                New Stroke(New Double() {642, 60, 642, 300}),
                New Stroke(New Double() {751, 60, 751, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 596}),
                New Stroke(New Double() {860, 596, 752, 596}),
                New Stroke(New Double() {752, 596, 752, 652}),
                New Stroke(New Double() {752, 652, 643, 652}),
                New Stroke(New Double() {643, 652, 643, 708}),
                New Stroke(New Double() {643, 708, 535, 708}),
                New Stroke(New Double() {535, 708, 535, 765}),
                New Stroke(New Double() {535, 765, 426, 765}),
                New Stroke(New Double() {426, 765, 426, 821}),
                New Stroke(New Double() {426, 821, 318, 821}),
                New Stroke(New Double() {318, 821, 318, 877}),
                New Stroke(New Double() {318, 877, 209, 877}),
                New Stroke(New Double() {209, 877, 209, 933}),
                New Stroke(New Double() {209, 933, 100, 933}),
                New Stroke(New Double() {100, 933, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 208, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 208, 445, 317, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 317, 385, 425, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 425, 445, 534, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 534, 385, 642, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 642, 445, 751, 445, True, "Step 6 tread"),
                New ChartDim("T7", "tread7", 751, 385, 860, 385, True, "Step 7 tread"),
                New ChartDim("W", "width", 930, 60, 930, 300, False, "One width, the whole run"),
                New ChartDim("D1", "depth1", 900, 540, 900, 596, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 792, 596, 792, 652, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 683, 652, 683, 708, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 575, 708, 575, 765, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 466, 765, 466, 821, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 358, 821, 358, 877, False, "Step 6 drop"),
                New ChartDim("D7", "depth7", 249, 877, 249, 933, False, "Step 7 drop"),
                New ChartDim("DA", "depthafter", 140, 933, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445}),
        New StepChart("NORMIESTEP", "Straight steps", 8,
            New Stroke() {
                New Stroke(New Double() {100, 60, 860, 60}),
                New Stroke(New Double() {100, 300, 860, 300}),
                New Stroke(New Double() {100, 60, 100, 300}),
                New Stroke(New Double() {195, 60, 195, 300}),
                New Stroke(New Double() {290, 60, 290, 300}),
                New Stroke(New Double() {385, 60, 385, 300}),
                New Stroke(New Double() {480, 60, 480, 300}),
                New Stroke(New Double() {575, 60, 575, 300}),
                New Stroke(New Double() {670, 60, 670, 300}),
                New Stroke(New Double() {765, 60, 765, 300}),
                New Stroke(New Double() {860, 60, 860, 300}),
                New Stroke(New Double() {860, 540, 860, 590}),
                New Stroke(New Double() {860, 590, 765, 590}),
                New Stroke(New Double() {765, 590, 765, 640}),
                New Stroke(New Double() {765, 640, 670, 640}),
                New Stroke(New Double() {670, 640, 670, 690}),
                New Stroke(New Double() {670, 690, 575, 690}),
                New Stroke(New Double() {575, 690, 575, 740}),
                New Stroke(New Double() {575, 740, 480, 740}),
                New Stroke(New Double() {480, 740, 480, 790}),
                New Stroke(New Double() {480, 790, 385, 790}),
                New Stroke(New Double() {385, 790, 385, 840}),
                New Stroke(New Double() {385, 840, 290, 840}),
                New Stroke(New Double() {290, 840, 290, 890}),
                New Stroke(New Double() {290, 890, 195, 890}),
                New Stroke(New Double() {195, 890, 195, 940}),
                New Stroke(New Double() {195, 940, 100, 940}),
                New Stroke(New Double() {100, 940, 100, 990})
            },
            New ChartDim() {
                New ChartDim("T1", "tread1", 100, 385, 195, 385, True, "Step 1 tread"),
                New ChartDim("T2", "tread2", 195, 445, 290, 445, True, "Step 2 tread"),
                New ChartDim("T3", "tread3", 290, 385, 385, 385, True, "Step 3 tread"),
                New ChartDim("T4", "tread4", 385, 445, 480, 445, True, "Step 4 tread"),
                New ChartDim("T5", "tread5", 480, 385, 575, 385, True, "Step 5 tread"),
                New ChartDim("T6", "tread6", 575, 445, 670, 445, True, "Step 6 tread"),
                New ChartDim("T7", "tread7", 670, 385, 765, 385, True, "Step 7 tread"),
                New ChartDim("T8", "tread8", 765, 445, 860, 445, True, "Step 8 tread"),
                New ChartDim("W", "width", 930, 60, 930, 300, False, "One width, the whole run"),
                New ChartDim("D1", "depth1", 900, 540, 900, 590, False, "Step 1 drop"),
                New ChartDim("D2", "depth2", 805, 590, 805, 640, False, "Step 2 drop"),
                New ChartDim("D3", "depth3", 710, 640, 710, 690, False, "Step 3 drop"),
                New ChartDim("D4", "depth4", 615, 690, 615, 740, False, "Step 4 drop"),
                New ChartDim("D5", "depth5", 520, 740, 520, 790, False, "Step 5 drop"),
                New ChartDim("D6", "depth6", 425, 790, 425, 840, False, "Step 6 drop"),
                New ChartDim("D7", "depth7", 330, 840, 330, 890, False, "Step 7 drop"),
                New ChartDim("D8", "depth8", 235, 890, 235, 940, False, "Step 8 drop"),
                New ChartDim("DA", "depthafter", 140, 940, 140, 990, False, "after the last tread")
            },
            New Double() {385, 445})
    }

    ''' <summary>lzf:*ctreat*: what a pool corner can be. This
    ''' one IS the canonical set -- STANDARDS.md section 2 --
    ''' unlike the spa sheet, which offers the drawing legend and
    ''' lets SPA normalise it.</summary>
    Public Shared ReadOnly PoolTreatments As String() = {"(ask)", "Square", "Radius", "Cut", "NotGiven"}

    ''' <summary>The pool treatments that carry a size, asked of
    ''' lzf:csized.</summary>
    Public Shared ReadOnly PoolSizedTreatments As String() = {"Radius", "Cut"}

    ''' <summary>lzf:*btypes*: the six bottoms POOL draws. The
    ''' shape chart shows twelve; the other six have no keyword
    ''' and are not offered.</summary>
    Public Shared ReadOnly PoolBottomTypes As String() = {"Normal", "Sport", "Wedge", "SLope", "MOdflat", "SHallow"}

    ''' <summary>The two words the in-square toggle sends. It is
    ''' not a yes/no: POOL reads a keyword.</summary>
    Public Const InSquare As String = "Insquare"
    Public Const OutOfSquare As String = "Outofsquare"

    ''' <summary>One keyword dropdown on a pool sheet. SECTION is
    ''' lzf:*picks*' own: "cross" ties the dropdown to the cross
    ''' dims -- in square there are none, so there is no mode to
    ''' pick either -- and "run" is a question in its own
    ''' right.</summary>
    Public Structure PoolPick
        Public ReadOnly Key As String
        Public ReadOnly Label As String
        Public ReadOnly Section As String
        Public ReadOnly Options As String()

        Public Sub New(key As String, label As String,
                       section As String, options As String())
            Me.Key = key
            Me.Label = label
            Me.Section = section
            Me.Options = options
        End Sub
    End Structure

    ''' <summary>One corner ROW on a pool sheet, which is not
    ''' always one corner.
    '''
    ''' <para>The answer is fanned out to every target: each gets
    ''' &lt;target&gt;-ty and, when the treatment carries one,
    ''' &lt;target&gt;-sz. WHICH targets depends on the in-square
    ''' toggle, because in square one answer covers all four
    ''' corners and out of square each is asked for itself -- so a
    ''' row can have targets in one state and NONE in the other,
    ''' and a row with none sends nothing at all.</para></summary>
    Public Structure PoolCornerRow
        Public ReadOnly Stem As String
        Public ReadOnly Label As String
        Public ReadOnly InSquareTargets As String()
        Public ReadOnly OutOfSquareTargets As String()

        Public Sub New(stem As String, label As String,
                       inSquare As String(),
                       outOfSquare As String())
            Me.Stem = stem
            Me.Label = label
            Me.InSquareTargets = inSquare
            Me.OutOfSquareTargets = outOfSquare
        End Sub

        ''' <summary>The targets for the toggle as it stands.
        ''' </summary>
        Public Function Targets(insquare As Boolean) As String()
            Return If(insquare, InSquareTargets, OutOfSquareTargets)
        End Function
    End Structure

    ''' <summary>What a pool sheet has beyond its geometry.
    ''' </summary>
    Public Structure PoolSheet
        Public ReadOnly Key As String
        ''' <summary>The diagonals. They have no line on a chart
        ''' drawn square -- a cross dim runs corner to corner --
        ''' so every one of them is a column box.</summary>
        Public ReadOnly Cross As ListKey()
        Public ReadOnly Picks As PoolPick()
        Public ReadOnly Corners As PoolCornerRow()

        Public Sub New(key As String, cross As ListKey(),
                       picks As PoolPick(),
                       corners As PoolCornerRow())
            Me.Key = key
            Me.Cross = cross
            Me.Picks = picks
            Me.Corners = corners
        End Sub
    End Structure

    Public Shared ReadOnly PoolSheets As PoolSheet() = {
        New PoolSheet("Rectangle",
            New ListKey() {
            New ListKey("x0", "Cross dim 1"),
            New ListKey("x1", "Cross dim 2"),
            New ListKey("x2", "Cross dim 3"),
            New ListKey("x3", "Cross dim 4")
            },
            New PoolPick() {
            New PoolPick("cmode", "Cross dims measured from", "cross", New String() {"(ask)", "Corner", "Middle", "Ends"})
            },
            New PoolCornerRow() {
            New PoolCornerRow("cornera", "Corner A (bottom left)", New String() {"corners"}, New String() {"cornera"}),
            New PoolCornerRow("cornerb", "Corner B (bottom right)", New String() {}, New String() {"cornerb"}),
            New PoolCornerRow("cornerc", "Corner C (top right)", New String() {}, New String() {"cornerc"}),
            New PoolCornerRow("cornerd", "Corner D (top left)", New String() {}, New String() {"cornerd"})
            }),
        New PoolSheet("Oval",
            New ListKey() {
            New ListKey("x0", "Cross dim 1"),
            New ListKey("x1", "Cross dim 2"),
            New ListKey("x2", "Cross dim 3"),
            New ListKey("x3", "Cross dim 4")
            },
            New PoolPick() {
            New PoolPick("cmode", "Cross dims measured from", "cross", New String() {"(ask)", "Corner", "Middle", "Ends"})
            },
            New PoolCornerRow() {}),
        New PoolSheet("ROman",
            New ListKey() {
            New ListKey("ac", "Cross dim body A-C"),
            New ListKey("bd", "Cross dim body B-D")
            },
            New PoolPick() {},
            New PoolCornerRow() {
            New PoolCornerRow("cornera", "Corner A (bottom left)", New String() {"corners"}, New String() {"cornera"}),
            New PoolCornerRow("cornerb", "Corner B (bottom right)", New String() {}, New String() {"cornerb"}),
            New PoolCornerRow("cornerc", "Corner C (top right)", New String() {}, New String() {"cornerc"}),
            New PoolCornerRow("cornerd", "Corner D (top left)", New String() {}, New String() {"cornerd"})
            }),
        New PoolSheet("Grecian",
            New ListKey() {
            New ListKey("x0", "Cross dim 1"),
            New ListKey("x1", "Cross dim 2")
            },
            New PoolPick() {
            New PoolPick("gcross", "Cross-dim detail", "cross", New String() {"(ask)", "Simple", "Center", "Complex"})
            },
            New PoolCornerRow() {
            New PoolCornerRow("bodycorners", "Body corners (all four)", New String() {"bodycorners"}, New String() {"cornera", "cornerb", "cornerc", "cornerd"}),
            New PoolCornerRow("endcorners", "End-tip corners (LT LB RT RB)", New String() {"endcorners"}, New String() {"cornerlt", "cornerlb", "cornerrt", "cornerrb"})
            }),
        New PoolSheet("GRSquare",
            New ListKey() {
            New ListKey("x0", "Cross dim 1"),
            New ListKey("x1", "Cross dim 2")
            },
            New PoolPick() {
            New PoolPick("gcross", "Cross-dim detail", "cross", New String() {"(ask)", "Simple", "Center", "Complex"})
            },
            New PoolCornerRow() {
            New PoolCornerRow("bodycorners", "Body corners (all four)", New String() {"bodycorners"}, New String() {"cornera", "cornerb", "cornerc", "cornerd"}),
            New PoolCornerRow("endcorners", "End-tip corners (LT LB RT RB)", New String() {"endcorners"}, New String() {"cornerlt", "cornerlb", "cornerrt", "cornerrb"})
            }),
        New PoolSheet("L",
            New ListKey() {
            New ListKey("ac", "Cross dim A-C"),
            New ListKey("bd", "Cross dim B-D"),
            New ListKey("ce", "Cross dim C-E"),
            New ListKey("df", "Cross dim D-F"),
            New ListKey("ae", "Cross dim A-E"),
            New ListKey("bf", "Cross dim B-F"),
            New ListKey("ad", "Cross dim A-D"),
            New ListKey("be", "Cross dim B-E"),
            New ListKey("cf", "Cross dim C-F")
            },
            New PoolPick() {
            New PoolPick("mirror", "Mirror the pool (wing swaps sides)", "run", New String() {"(ask)", "Yes", "No"})
            },
            New PoolCornerRow() {
            New PoolCornerRow("outercorners", "Outer corners (all five)", New String() {"outercorners"}, New String() {"outercorners"}),
            New PoolCornerRow("innercorner", "Reverse corner E", New String() {"innercorner"}, New String() {"innercorner"})
            }),
        New PoolSheet("ROUnd",
            New ListKey() {},
            New PoolPick() {},
            New PoolCornerRow() {}),
        New PoolSheet("OCtagon",
            New ListKey() {
            New ListKey("x0", "Cross dim 1"),
            New ListKey("x1", "Cross dim 2")
            },
            New PoolPick() {
            New PoolPick("gcross", "Cross-dim detail", "cross", New String() {"(ask)", "Simple", "Center", "Complex"})
            },
            New PoolCornerRow() {
            New PoolCornerRow("bodycorners", "Body corners (all four)", New String() {"bodycorners"}, New String() {"cornera", "cornerb", "cornerc", "cornerd"}),
            New PoolCornerRow("endcorners", "End-tip corners (LT LB RT RB)", New String() {"endcorners"}, New String() {"cornerlt", "cornerlb", "cornerrt", "cornerrb"})
            }),
        New PoolSheet("OACenter",
            New ListKey() {},
            New PoolPick() {
            New PoolPick("detail", "Simple or complex", "run", New String() {"(ask)", "Simple", "Complex"})
            },
            New PoolCornerRow() {}),
        New PoolSheet("OATopRight",
            New ListKey() {},
            New PoolPick() {
            New PoolPick("detail", "Simple or complex", "run", New String() {"(ask)", "Simple", "Complex"})
            },
            New PoolCornerRow() {}),
        New PoolSheet("OACloud",
            New ListKey() {},
            New PoolPick() {
            New PoolPick("sub", "Cloud bottom", "run", New String() {"(ask)", "Straight", "Rounded"}),
            New PoolPick("detail", "Simple or complex", "run", New String() {"(ask)", "Simple", "Complex"})
            },
            New PoolCornerRow() {}),
        New PoolSheet("OAKidney",
            New ListKey() {},
            New PoolPick() {
            New PoolPick("sub", "Kidney type", "run", New String() {"(ask)", "True", "Asymmetric"}),
            New PoolPick("detail", "Simple or complex", "run", New String() {"(ask)", "Simple", "Complex"})
            },
            New PoolCornerRow() {}),
        New PoolSheet("OANXT",
            New ListKey() {},
            New PoolPick() {
            New PoolPick("detail", "Simple or complex", "run", New String() {"(ask)", "Simple", "Complex"})
            },
            New PoolCornerRow() {})
    }

    ''' <summary>The pool extras for a sheet, or one with a
    ''' Nothing Key when there are none.</summary>
    Public Shared Function PoolSheetFor(key As String) As PoolSheet
        For Each s In PoolSheets
            If String.Equals(s.Key, key, StringComparison.OrdinalIgnoreCase) Then Return s
        Next
        Return Nothing
    End Function

    ''' <summary>The spa questions answered from a LIST rather than
    ''' typed - lzs:*lists*. The first option is always "(ask)",
    ''' and choosing it sends nothing at all: the key stays absent
    ''' and SPA asks at the command line.</summary>
    Public Shared ReadOnly SpaLists As Choice() = {
        New Choice("mode", "Water's edge or cover size", New String() {"(ask)", "Watersedge", "Coversize"}),
        New Choice("second", "Draw the other outline as well", New String() {"(ask)", "Yes", "No"}),
        New Choice("method", "Take the other outline from", New String() {"(ask)", "Offset", "Dims"}),
        New Choice("autohinge", "Auto-hinge the cover", New String() {"(ask)", "Yes", "No"}),
        New Choice("grade", "Cover grade", New String() {"(ask)", "STANDARD", "THERMOLIGHT"}),
        New Choice("taper", "Taper", New String() {"(ask)", "3-2", "4-2", "4-3", "5-3", "5-4", "3-3", "1-3/8"})
    }

    ''' <summary>lzs:*ctreat*: the words the corner dropdown
    ''' offers. They are the SHEET LEGEND's -- 90 / Radius /
    ''' Diagonal -- and SPA normalises them onto the canonical
    ''' Square / Radius / Cut / NotGiven set itself, which is why
    ''' the palette must send them as written and not
    ''' helpfully translate.</summary>
    Public Shared ReadOnly SpaTreatments As String() = {"(ask)", "90", "Radius", "Diagonal"}

    ''' <summary>The treatments that carry a size, asked of
    ''' lzs:sized rather than read off it. 90 sets back nothing
    ''' and asks for no number.</summary>
    Public Shared ReadOnly SpaSizedTreatments As String() = {"Radius", "Diagonal"}

    ''' <summary>The cover lap. A box the dialog builds rather
    ''' than a table row, so it is lifted out of the source.
    ''' </summary>
    Public Shared ReadOnly SpaCoverLap As ListKey = New ListKey("gap", "How far the cover laps the water's edge")

    ''' <summary>What a spa sheet has that a pool sheet has not:
    ''' its corner rows, the other outline's overalls under keys
    ''' that are PER SHAPE, and the line the page prints.
    '''
    ''' <para>Kept beside Chart rather than inside it. LAZFORM has
    ''' a corner table too and it is a different shape -- four
    ''' slots, with collective questions covering several corners
    ''' at once -- so one structure for both would be a lie about
    ''' one of them.</para></summary>
    Public Shared ReadOnly SpaSheets As SpaSheet() = {
        New SpaSheet("Rectangle", "A B C D run from the bottom left, the way SPA numbers them.",
            New SpaCornerRow() {
            New SpaCornerRow("cornera", "Corner A (bottom left)"),
            New SpaCornerRow("cornerb", "Corner B (bottom right)"),
            New SpaCornerRow("cornerc", "Corner C (top right)"),
            New SpaCornerRow("cornerd", "Corner D (top left)")
            },
            New ListKey() {
            New ListKey("w2", "Other outline ACROSS"),
            New ListKey("l2", "Other outline UP")
            }),
        New SpaSheet("OCtagon", "B and A alone draw a true square octagon -- NA the cut letters.",
            New SpaCornerRow() {},
            New ListKey() {
            New ListKey("b2", "Other outline ACROSS"),
            New ListKey("a2", "Other outline UP"),
            New ListKey("f2", "Other outline cut FACE")
            }),
        New SpaSheet("ROund", "Leave A empty for a circle; fill it in and the spa is out of round.",
            New SpaCornerRow() {},
            New ListKey() {
            New ListKey("b2", "Other outline ACROSS"),
            New ListKey("a2", "Other outline UP")
            })
    }

    ''' <summary>The POOL or OASIS sheet of that name, or one with a
    ''' Nothing Key when there is none.</summary>
    Public Shared Function PoolChart(key As String) As Chart
        Return Find(Pool, key)
    End Function

    ''' <summary>The SPA sheet of that name.</summary>
    Public Shared Function SpaChart(key As String) As Chart
        Return Find(Spa, key)
    End Function

    Private Shared Function Find(charts As Chart(), key As String) As Chart
        For Each c In charts
            If String.Equals(c.Key, key, StringComparison.OrdinalIgnoreCase) Then
                Return c
            End If
        Next
        Return Nothing
    End Function

    ''' <summary>The spa extras for a sheet, or one with a Nothing Key
    ''' when there are none.</summary>
    Public Shared Function SpaSheetFor(key As String) As SpaSheet
        For Each s In SpaSheets
            If String.Equals(s.Key, key, StringComparison.OrdinalIgnoreCase) Then
                Return s
            End If
        Next
        Return Nothing
    End Function

    ''' <summary>The step sheet for a routine and a count, or one with a
    ''' Nothing Routine when the count is outside what LAZSTEP will
    ''' draw.</summary>
    Public Shared Function StepChartFor(routine As String,
                                        steps As Integer) As StepChart
        For Each c In StepSheets
            If c.Steps = steps AndAlso
               String.Equals(c.Routine, routine,
                             StringComparison.OrdinalIgnoreCase) Then
                Return c
            End If
        Next
        Return Nothing
    End Function

End Class
