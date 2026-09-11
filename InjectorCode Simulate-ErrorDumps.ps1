<#
.SYNOPSIS
    Simulates leftover crash/error dump artifacts: a full memory dump
    (MEMORY.DMP), kernel minidumps, and per-app crash dumps
    (as Windows Error Reporting / LocalDumps would leave behind).

.PARAMETER Root
    Sandbox root to build the fake dumps under.
    Default: $env:TEMP\DiskCleanupSim  (NOT a real system path).

.PARAMETER SizeMB
    Approximate total size (MB) of junk data to generate. Default: 300.

.PARAMETER Force
    Required (plus interactive "YES" confirmation) if -Root resolves to a
    real system path. Not recommended.

.EXAMPLE
    .\Simulate-ErrorDumps.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:TEMP 'DiskCleanupSim'),
    [double]$SizeMB = 300,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$windowsDir  = Join-Path $Root 'Windows'
$minidumpDir = Join-Path $windowsDir 'Minidump'
$werDir      = Join-Path $Root 'Users\LocalUser\AppData\Local\CrashDumps'

Assert-SafeTarget -Path $windowsDir -Force:$Force
Assert-SafeTarget -Path $werDir -Force:$Force

Write-Host "Building simulated error-dump clutter under: $Root"

New-Item -ItemType Directory -Path $minidumpDir -Force | Out-Null
New-Item -ItemType Directory -Path $werDir -Force | Out-Null

# Full memory dump (usually the single biggest contributor)
New-JunkFile -Path (Join-Path $windowsDir 'MEMORY.DMP') -SizeMB ($SizeMB * 0.5)

# A handful of kernel minidumps
1..3 | ForEach-Object {
    $stamp = (Get-Date).AddDays(-$_).ToString('MMddyy-HHmm')
    New-JunkFile -Path (Join-Path $minidumpDir "$stamp-01.dmp") -SizeMB ($SizeMB * 0.1)
}

# Per-application crash dumps (WER LocalDumps style)
$apps = @('app1.exe', 'app2.exe')
foreach ($app in $apps) {
    New-JunkFile -Path (Join-Path $werDir "$app.$([guid]::NewGuid().ToString('N').Substring(0,8)).dmp") -SizeMB ($SizeMB * 0.1)
}

Write-ClutterSummary -Root $Root
Write-Host "Done. Point your cleanup script's 'error dump' check at: $windowsDir and $werDir"
