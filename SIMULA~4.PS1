<#
.SYNOPSIS
    Simulates leftover Windows upgrade log/staging clutter: the
    $WINDOWS.~BT and $WINDOWS.~WS folders and Panther setup logs that
    remain after a feature/version upgrade.

.PARAMETER Root
    Sandbox root to build the fake upgrade artifacts under.
    Default: $env:TEMP\DiskCleanupSim  (NOT a real system path).

.PARAMETER SizeMB
    Approximate total size (MB) of junk data to generate. Default: 250.

.PARAMETER Force
    Required (plus interactive "YES" confirmation) if -Root resolves to a
    real system path. Not recommended.

.EXAMPLE
    .\Simulate-UpgradeLogs.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:TEMP 'DiskCleanupSim'),
    [double]$SizeMB = 250,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$btDir      = Join-Path $Root '$WINDOWS.~BT'
$wsDir      = Join-Path $Root '$WINDOWS.~WS'
$pantherDir = Join-Path $Root 'Windows\Panther'

Assert-SafeTarget -Path $btDir -Force:$Force
Assert-SafeTarget -Path $wsDir -Force:$Force
Assert-SafeTarget -Path $pantherDir -Force:$Force

Write-Host "Building simulated upgrade-log clutter under: $Root"

New-Item -ItemType Directory -Path (Join-Path $btDir 'Sources\Panther') -Force | Out-Null
New-Item -ItemType Directory -Path $wsDir -Force | Out-Null
New-Item -ItemType Directory -Path $pantherDir -Force | Out-Null

# Text log files (small but numerous)
$logNames = @('setupact.log', 'setuperr.log', 'miglog.xml', 'PreGatherPnPList.log')
foreach ($name in $logNames) {
    $content = "Simulated upgrade log entry`r`n" * 2000
    Set-Content -Path (Join-Path $pantherDir $name) -Value $content -Encoding UTF8
    Set-Content -Path (Join-Path $btDir "Sources\Panther\$name") -Value $content -Encoding UTF8
}

# Staged install image / rollback data (the real bulk of $WINDOWS.~BT and ~WS)
New-JunkFile -Path (Join-Path $btDir 'Sources\install.wim') -SizeMB ($SizeMB * 0.6)
New-JunkFile -Path (Join-Path $wsDir 'rollback.dat')         -SizeMB ($SizeMB * 0.35)

Write-ClutterSummary -Root $Root
Write-Host "Done. Point your cleanup script's 'upgrade log' check at: $btDir , $wsDir , $pantherDir"
