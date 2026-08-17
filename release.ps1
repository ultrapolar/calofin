# ==========================================================================
# release.ps1 - stamp a lisp and generate its dated twin  (Windows)
#
#   .\release.ps1 AUTOBEAD 2            -> AUTOBEAD_<today>_REV02.lsp
#   .\release.ps1 AUTOBEAD 2 090126     -> AUTOBEAD_090126_REV02.lsp
#
# Rewrites the revision and date stamps inside <NAME>.lsp, then copies it to
# <NAME>_MMDDYY_REV##.lsp.  Both files end up identical, so <NAME>VER reports
# the same revision no matter which one was loaded.
#
# Always regenerate with this rather than copying by hand -- a hand-copied
# twin drifts from the master the moment either one is edited.
#
# Equivalent to release.sh; use whichever suits your shell.
# ==========================================================================

param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][int]$Rev,
    [string]$Date
)

$ErrorActionPreference = 'Stop'

$src = "$Name.lsp"
if (-not (Test-Path -LiteralPath $src)) {
    Write-Error "$src not found"
    exit 1
}

$revTag = 'REV{0:D2}' -f $Rev
if (-not $Date) { $Date = (Get-Date).ToString('MMddyy') }

if ($Date -notmatch '^\d{6}$') {
    Write-Error "date must be MMDDYY, got '$Date'"
    exit 1
}

$pretty = '{0}/{1}/{2}' -f $Date.Substring(0,2), $Date.Substring(2,2), $Date.Substring(4,2)
$lc     = $Name.ToLower()

# Paren balance, ignoring strings and comments.  Checked before and after the
# stamp so a bad substitution can never ship a file AutoCAD won't load.
function Get-ParenBalance([string]$path) {
    $depth = 0
    foreach ($line in Get-Content -LiteralPath $path) {
        $inStr = $false
        for ($i = 0; $i -lt $line.Length; $i++) {
            $c = $line[$i]
            if ($inStr) {
                if ($c -eq '\') { $i++; continue }
                if ($c -eq '"') { $inStr = $false }
                continue
            }
            if ($c -eq '"') { $inStr = $true; continue }
            if ($c -eq ';') { break }
            if ($c -eq '(') { $depth++ }
            if ($c -eq ')') { $depth-- }
        }
    }
    return $depth
}

$before = Get-ParenBalance $src

# Both patterns are anchored to the start of the line so they can only hit
# the settings block -- an unanchored match also rewrites the variable where
# it is USED, e.g. inside the report string, silently corrupting the code.
$text = Get-Content -LiteralPath $src -Raw
$text = [regex]::Replace($text,
    "(?m)^(\(setq \*$lc-rev\* *"")[^""]*""",  "`${1}$revTag""")
$text = [regex]::Replace($text,
    "(?m)^( *\*$lc-date\* *"")[^""]*""",      "`${1}$pretty""")

Set-Content -LiteralPath $src -Value $text -NoNewline

if (-not (Select-String -LiteralPath $src -SimpleMatch "(setq *$lc-rev*    ""$revTag""" -Quiet)) {
    Write-Error "revision stamp not applied in $src -- check the settings block"
    exit 1
}

$after = Get-ParenBalance $src
if ($before -ne $after -or $after -ne 0) {
    Write-Error "$src has unbalanced parens after stamping (before=$before after=$after) -- not releasing"
    exit 1
}

$out = "{0}_{1}_{2}.lsp" -f $Name, $Date, $revTag
Copy-Item -LiteralPath $src -Destination $out -Force

Write-Host "stamped  $src   -> $revTag ($pretty)"
Write-Host "released $out"
Write-Host ""
Write-Host "Both files are identical. Load either; ${Name}VER reports $revTag."
