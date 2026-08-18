@echo off
rem LINFINCHECK regression runner.
rem
rem Loads linfincheck.lsp and runs LINFINSCAN over every drawing in dxf\,
rem writing one report per drawing into out\. Compare those against
rem expected.md (or against a previous out\ folder) after changing a
rem rule to see exactly what moved.
rem
rem Point ACAD at your accoreconsole.exe if it is not on PATH:
rem     set ACAD="C:\Program Files\Autodesk\AutoCAD 2025\accoreconsole.exe"
rem     run_tests.bat

setlocal
if "%ACAD%"=="" set ACAD="C:\Program Files\Autodesk\AutoCAD 2025\accoreconsole.exe"

if not exist out mkdir out
del /q out\*.txt 2>nul

for %%F in (dxf\*.dxf) do (
  echo === %%~nF ===
  %ACAD% /i "%%F" /s run_tests.scr /l en-US
)

echo.
echo Reports written to out\ - diff them against expected.md
endlocal
