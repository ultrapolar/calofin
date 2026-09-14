Imports System.Windows.Media
Imports Microsoft.Win32
Imports AcadApp = Autodesk.AutoCAD.ApplicationServices.Application

''' <summary>
''' Which way the host reads, and the brushes that follow from it.
'''
''' <para>The chart views take their ink from
''' <c>SystemColors.ControlTextBrushKey</c>, which follows the theme,
''' and then painted the entry boxes <c>ARGB(235,255,255,255)</c> with
''' black text, which does not. On a dark AutoCAD that is a row of
''' white cards on a dark panel -- legible, and wrong in the way a
''' half-themed page always is: the half that adapts makes the half
''' that does not look like a bug, because it is one.</para>
'''
''' <para>The theme is read the way the panel reads it. First the
''' shared setting <c>CALSET</c> writes -- the same registry key
''' <see cref="PaletteMemory"/> takes pins from, so a drafter who has
''' said "my background is light" once has said it to both surfaces.
''' Then <c>COLORTHEME</c>, AutoCAD's own (0 dark, 1 light). Then the
''' Windows theme, by the luminance of the control colour, which is
''' what <c>SystemColors</c> would have given anyway.</para>
'''
''' <para>Nothing here can be compiled in the repository's environment
''' (see ui/PLAN.md), so it is written to be readable rather than
''' clever, and every host call is wrapped: a palette that cannot work
''' out the theme must still open.</para>
''' </summary>
Public NotInheritable Class PaletteTheme

    Private Sub New()
    End Sub

    ''' <summary>lzp:*pinkey* in lisp/lazpanel/LAZPANEL.lsp, and the
    ''' value CALSET writes beside Pins and Recent. Change one and
    ''' change the other, or the two surfaces stop sharing.</summary>
    Private Const KeyPath As String =
        "HKEY_CURRENT_USER\Software\Calofin\LazPanel"

    Private Const ThemeValue As String = "Theme"

    ''' <summary>The override, lowercased: "dark", "light", or "" for
    ''' "work it out".</summary>
    Public Shared Function Setting() As String
        Try
            Dim v = TryCast(Registry.GetValue(KeyPath, ThemeValue, Nothing),
                            String)
            If v Is Nothing Then Return ""
            Return v.Trim().ToLowerInvariant()
        Catch
            Return ""
        End Try
    End Function

    ''' <summary>True when the host is reading dark.</summary>
    Public Shared Function IsDark() As Boolean
        Dim over = Setting()
        If over = "dark" Then Return True
        If over = "light" Then Return False
        Try
            Dim ct = AcadApp.GetSystemVariable("COLORTHEME")
            If ct IsNot Nothing Then
                Return Convert.ToInt32(ct) = 0
            End If
        Catch
        End Try
        Return IsDarkWindows()
    End Function

    ''' <summary>The last resort: the Windows control colour, dark when
    ''' its luminance is below half. Wrapped, because a themeless host
    ''' process can throw here.</summary>
    Private Shared Function IsDarkWindows() As Boolean
        Try
            Dim c = SystemColors.ControlColor
            Dim lum = (0.3 * CDbl(c.R) + 0.59 * CDbl(c.G) + 0.11 * CDbl(c.B))
            Return lum < 128.0
        Catch
            Return False
        End Try
    End Function

    ''' <summary>What an entry box is painted. Slightly off the panel
    ''' either way round, so a box still reads as a box: the chart is
    ''' drawn UNDER these and they have to sit on top of it.</summary>
    Public Shared Function FieldBackground() As Brush
        If IsDark() Then
            Return New SolidColorBrush(Color.FromArgb(235, 45, 45, 45))
        End If
        Return New SolidColorBrush(Color.FromArgb(235, 255, 255, 255))
    End Function

    ''' <summary>And what is typed into it.</summary>
    Public Shared Function FieldForeground() As Brush
        If IsDark() Then
            Return New SolidColorBrush(Color.FromRgb(240, 240, 240))
        End If
        Return Brushes.Black
    End Function

End Class
