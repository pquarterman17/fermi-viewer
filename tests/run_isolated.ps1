# Run each test suite in its own MATLAB process with a hard wall-clock timeout.
#
# Trades startup overhead (~5s/suite) for the ability to actually KILL a hung
# suite -- runAllTests's in-process MaxSeconds is soft (can flag overruns but
# can't interrupt them, so one hung test freezes the entire runner). Use this
# when run_gui_hidden.ps1 hangs and you need to identify the culprit.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tests/run_isolated.ps1 [group] [timeoutSec]
#
#   group        defaults to "fvgui"  (any group runAllTests accepts)
#   timeoutSec   per-suite hard kill, defaults to 180  (3 minutes)
#
# Sets FERMI_VIEWER_HEADLESS=1 and prepends tests/shadows/ so bare dialog
# calls don't block. Each suite runs as: matlab -batch "run(<suitePath>)".

param(
    [string]$Group       = "fvgui",
    [int]   $TimeoutSec  = 180
)

# Locate MATLAB
$matlabExe = Get-ChildItem "C:\Program Files\MATLAB" -Directory |
    Sort-Object Name -Descending |
    Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName "bin\matlab.exe" }
if (-not (Test-Path $matlabExe)) {
    Write-Host "Error: MATLAB not found in C:\Program Files\MATLAB\" -ForegroundColor Red
    exit 1
}

$repoRoot = Split-Path $PSScriptRoot

# -- Phase 1: discover suite list ------------------------------------------
Write-Host "Discovering suites in group '$Group'..." -ForegroundColor Cyan
$listLog = Join-Path $env:TEMP "matlab_suite_list.txt"
if (Test-Path $listLog) { Remove-Item $listLog }
$escapedList = $listLog -replace '\\','/'
$listCmd = "diary('$escapedList'); addpath(pwd); setupToolbox; runAllTests(Group='$Group', ListOnly=true); diary off;"

$listProc = Start-Process -FilePath $matlabExe `
    -ArgumentList "-batch", """$listCmd""" `
    -WindowStyle Hidden `
    -WorkingDirectory $repoRoot `
    -PassThru -Wait

if ($listProc.ExitCode -ne 0 -or -not (Test-Path $listLog)) {
    Write-Host "Failed to enumerate suites (MATLAB exit $($listProc.ExitCode))" -ForegroundColor Red
    if (Test-Path $listLog) { Get-Content $listLog }
    exit 1
}

$suites = Get-Content $listLog | Where-Object { $_ -match '^SUITE\|' } | ForEach-Object {
    $parts = $_ -split '\|'
    [PSCustomObject]@{
        Path  = $parts[1]
        Group = $parts[2]
        Descr = $parts[3]
        Name  = [System.IO.Path]::GetFileNameWithoutExtension($parts[1])
    }
}

if ($suites.Count -eq 0) {
    Write-Host "No suites matched group '$Group'." -ForegroundColor Yellow
    exit 0
}

Write-Host "Running $($suites.Count) suite(s) with $TimeoutSec s per-suite hard timeout`n" -ForegroundColor Cyan

# -- Phase 2: run each suite in isolation ----------------------------------
$env:FERMI_VIEWER_HEADLESS = "1"
$results = @()
$totalStart = Get-Date

foreach ($suite in $suites) {
    Write-Host "-> $($suite.Name) -- $($suite.Descr)"

    $suiteLog = Join-Path $env:TEMP "matlab_suite_$($suite.Name).log"
    if (Test-Path $suiteLog) { Remove-Item $suiteLog }
    $escapedLog = $suiteLog.Replace('\','/')
    $escapedSuitePath = $suite.Path.Replace('\','/')

    $matlabCmd = "diary('$escapedLog'); set(groot,'DefaultFigureVisible','off'); addpath(pwd); setupToolbox; addpath(fullfile(pwd,'tests','shadows'),'-begin'); try; run('$escapedSuitePath'); catch ME; fprintf(2, 'SUITE_ERROR: %s\n', ME.message); diary off; exit(1); end; diary off; exit(0);"

    $p = Start-Process -FilePath $matlabExe `
        -ArgumentList "-batch", """$matlabCmd""" `
        -WindowStyle Hidden `
        -WorkingDirectory $repoRoot `
        -PassThru

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Milliseconds 500
    }

    $status = 'PASS'
    $color = 'Green'
    if (-not $p.HasExited) {
        # Hard kill the hung MATLAB
        try {
            $p.Kill()
            $p.WaitForExit(5000)
        } catch { }
        $status = 'TIMEOUT'
        $color = 'Red'
    } elseif ($p.ExitCode -ne 0) {
        $status = 'FAIL'
        $color = 'Red'
    }

    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host "   $status ($elapsed s)" -ForegroundColor $color

    $results += [PSCustomObject]@{
        Name    = $suite.Name
        Status  = $status
        Elapsed = $elapsed
        LogFile = $suiteLog
    }
}

$totalElapsed = [math]::Round(((Get-Date) - $totalStart).TotalSeconds, 1)

# -- Phase 3: summary ------------------------------------------------------
$nPass    = @($results | Where-Object Status -eq 'PASS').Count
$nFail    = @($results | Where-Object Status -eq 'FAIL').Count
$nTimeout = @($results | Where-Object Status -eq 'TIMEOUT').Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary: $nPass passed, $nFail failed, $nTimeout TIMEOUT  ($totalElapsed s total)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($nFail -gt 0 -or $nTimeout -gt 0) {
    Write-Host ""
    Write-Host "Problem suites:" -ForegroundColor Yellow
    foreach ($r in $results | Where-Object Status -ne 'PASS') {
        Write-Host "  - $($r.Name) [$($r.Status)] log: $($r.LogFile)"
        if ($r.Status -eq 'FAIL' -and (Test-Path $r.LogFile)) {
            Write-Host "    --- last 10 lines ---" -ForegroundColor DarkGray
            Get-Content $r.LogFile -Tail 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
    }
}

# Exit code: 0 if all pass, 1 if any fail or timeout
if ($nFail -gt 0 -or $nTimeout -gt 0) { exit 1 } else { exit 0 }
