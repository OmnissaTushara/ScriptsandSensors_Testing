<#
.SYNOPSIS
    Simulates leftover Windows Update artifacts (normally found under
    C:\Windows\SoftwareDistribution\Download and the WinSxS backup store).

.PARAMETER Root
    Sandbox root to build the fake update-cache under.
    Default: $env:TEMP\DiskCleanupSim  (NOT a real system path).

.PARAMETER SizeMB
    Approximate total size (MB) of junk data to generate. Default: 600.

.PARAMETER Force
    Required (plus interactive "YES" confirmation) if -Root resolves to a
    real system path. Not recommended.

.EXAMPLE
    .\Simulate-UpdateArtifacts.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:TEMP 'DiskCleanupSim'),
    [double]$SizeMB = 600,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$target = Join-Path $Root 'Windows\SoftwareDistribution\Download'
Assert-SafeTarget -Path $target -Force:$Force

Write-Host "Building simulated Windows Update artifact clutter at: $target"

New-Item -ItemType Directory -Path $target -Force | Out-Null

# Fake per-update download folders, each with a GUID-style name (as Windows Update uses)
$updateIds = 1..5 | ForEach-Object { [guid]::NewGuid().ToString() }
$perFileMB = [Math]::Max(1, [Math]::Round(($SizeMB * 0.8) / $updateIds.Count, 2))

foreach ($id in $updateIds) {
    $dir = Join-Path $target $id
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-JunkFile -Path (Join-Path $dir 'update.cab') -SizeMB $perFileMB
    New-JunkFile -Path (Join-Path $dir 'update.psf') -SizeMB ($perFileMB * 0.2)
}

# Fake WinSxS backup/superseded component store bloat
$winSxSBackup = Join-Path $Root 'Windows\WinSxS\Backup'
New-Item -ItemType Directory -Path $winSxSBackup -Force | Out-Null
New-JunkFile -Path (Join-Path $winSxSBackup 'superseded-components.bak') -SizeMB ($SizeMB * 0.2)

Write-ClutterSummary -Root (Join-Path $Root 'Windows')
Write-Host "Done. Point your cleanup script's 'update artifacts' check at: $target"
