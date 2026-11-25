param(
    [string]$Only = ''
)

# Run every gate registered in pipeline.json, one by one, printing the verdict.
# Why: some gates need rendering (must NOT pass --headless); this script runs the
# exact cmd from pipeline.json so nobody has to hand-copy arguments.
#
# Usage:
#   powershell -File tools\run_gates.ps1                 # all
#   powershell -File tools\run_gates.ps1 -Only corridor   # name filter
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI,
# which turns CJK text into garbage and breaks parsing (already burned twice).

$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$pipeline = Get-Content (Join-Path $root 'pipeline.json') -Encoding utf8 | ConvertFrom-Json

$steps = @($pipeline.steps | Where-Object { $_.cmd -like '*res://game/tests*' })
if ($Only -ne '') {
    $steps = @($steps | Where-Object { $_.name -like "*$Only*" })
}

Write-Host ("Gates: {0}" -f $steps.Count) -ForegroundColor Cyan
$failed = @()
foreach ($step in $steps) {
    Push-Location $root
    $out = Invoke-Expression $step.cmd 2>&1
    Pop-Location
    $ok = ($out | Select-String -Pattern '_OK' | Select-Object -Last 1)
    $bad = ($out | Select-String -Pattern '_FAIL' | Select-Object -First 1)
    if ($ok -and -not $bad) {
        Write-Host ("[PASS] {0,-18} {1}" -f $step.name, $ok.Line.Trim()) -ForegroundColor Green
    } else {
        $detail = if ($bad) { $bad.Line.Trim() } else { 'no _OK line' }
        Write-Host ("[FAIL] {0,-18} {1}" -f $step.name, $detail) -ForegroundColor Red
        $failed += $step.name
    }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host ("ALL PASS ({0})" -f $steps.Count) -ForegroundColor Green
    exit 0
}
Write-Host ("FAILED: {0}" -f ($failed -join ', ')) -ForegroundColor Red
exit 1
