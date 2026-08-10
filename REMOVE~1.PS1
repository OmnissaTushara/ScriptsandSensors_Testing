<#
.SYNOPSIS
    Teardown: removes the DiskClutterSim sandbox and reports how much
    space was freed (mirroring the "GB reclaimed" report your real
    cleanup script produces).

.PARAMETER Root
    Sandbox root to remove.
    Default: $env:TEMP\DiskCleanupSim

.PARAMETER Force
    Required (plus interactive "YES" confirmation) if -Root resolves to a
    real system path. Strongly not recommended — this script deletes
    everything under -Root.

.EXAMPLE
    .\Remove-AllSimulations.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:TEMP 'DiskCleanupSim'),
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-SafeTarget -Path $Root -Force:$Force

if (-not (Test-Path $Root)) {
    Write-Host "Nothing to remove — '$Root' does not exist."
    return
}

$items = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue
$totalBytes = ($items | Measure-Object -Property Length -Sum).Sum
$gb = if ($totalBytes) { [Math]::Round(($totalBytes / 1GB), 3) } else { 0 }

Write-Host "About to delete '$Root' ($($items.Count) files, $gb GB)."
$confirm = Read-Host 'Type YES to proceed'
if ($confirm -ne 'YES') {
    Write-Host 'Aborted. Nothing was deleted.'
    return
}

Remove-Item -Path $Root -Recurse -Force
Write-Host "Reclaimed approximately $gb GB by removing simulated clutter at '$Root'."
