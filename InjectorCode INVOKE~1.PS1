<#
.SYNOPSIS
    Orchestrator: runs all four DiskClutterSim category scripts against one
    shared sandbox root, then prints a combined summary — mirroring the
    "GB reclaimed" style report your cleanup script produces.

.PARAMETER Root
    Sandbox root for all simulated clutter.
    Default: $env:TEMP\DiskCleanupSim  (NOT a real system path).

.PARAMETER Force
    Passed through to each category script. Only needed if -Root resolves
    to a real system path (not recommended — each script will still prompt
    for interactive "YES" confirmation).

.EXAMPLE
    .\Invoke-AllSimulations.ps1
    .\Invoke-AllSimulations.ps1 -Root C:\DiskCleanupSim
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:TEMP 'DiskCleanupSim'),
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Host "=== DiskClutterSim: building all categories under $Root ===" -ForegroundColor Cyan

& (Join-Path $PSScriptRoot 'Simulate-PreviousWindowsInstallation.ps1') -Root $Root -Force:$Force
& (Join-Path $PSScriptRoot 'Simulate-UpdateArtifacts.ps1')             -Root $Root -Force:$Force
& (Join-Path $PSScriptRoot 'Simulate-ErrorDumps.ps1')                  -Root $Root -Force:$Force
& (Join-Path $PSScriptRoot 'Simulate-UpgradeLogs.ps1')                 -Root $Root -Force:$Force

Write-Host "`n=== Combined total ===" -ForegroundColor Cyan
Write-ClutterSummary -Root $Root

Write-Host "`nNext step: point your disk-cleanup automation script at '$Root' (or its subfolders) instead of the real system paths, run it, and confirm it reports the correct GB reclaimed and removes the simulated files." -ForegroundColor Yellow
Write-Host "When finished testing, run Remove-AllSimulations.ps1 to clean up." -ForegroundColor Yellow
