<#
.SYNOPSIS
    Simulates leftover "previous Windows installation" clutter (the kind
    normally found in C:\Windows.old after an in-place upgrade), so a
    disk-cleanup automation script can be tested against a realistic layout.

.PARAMETER Root
    Sandbox root to build the fake Windows.old under.
    Default: $env:TEMP\DiskCleanupSim  (NOT a real system path).

.PARAMETER SizeMB
    Approximate total size (MB) of junk data to generate. Default: 400.

.PARAMETER Force
    Required (plus interactive "YES" confirmation) if -Root resolves to a
    real system path. Not recommended.

.EXAMPLE
    .\Simulate-PreviousWindowsInstallation.ps1
    .\Simulate-PreviousWindowsInstallation.ps1 -Root C:\DiskCleanupSim -SizeMB 800
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:TEMP 'DiskCleanupSim'),
    [double]$SizeMB = 400,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$target = Join-Path $Root 'Windows.old'
Assert-SafeTarget -Path $target -Force:$Force

Write-Host "Building simulated previous-install clutter at: $target"

$subdirs = @(
    'Windows\System32\config',
    'Windows\SysWOW64',
    'Program Files\DummyApp',
    'Users\Public\Documents'
)
foreach ($sub in $subdirs) {
    New-Item -ItemType Directory -Path (Join-Path $target $sub) -Force | Out-Null
}

$perFileMB = [Math]::Max(1, [Math]::Round($SizeMB / 6, 2))
New-JunkFile -Path (Join-Path $target 'Windows\System32\config\SOFTWARE')        -SizeMB $perFileMB
New-JunkFile -Path (Join-Path $target 'Windows\System32\config\SYSTEM')          -SizeMB $perFileMB
New-JunkFile -Path (Join-Path $target 'Windows\SysWOW64\ntdll.dll')              -SizeMB $perFileMB
New-JunkFile -Path (Join-Path $target 'Program Files\DummyApp\dummyapp.bin')     -SizeMB $perFileMB
New-JunkFile -Path (Join-Path $target 'Users\Public\Documents\old-report.docx') -SizeMB $perFileMB
New-JunkFile -Path (Join-Path $target 'Windows\bootstat.dat')                    -SizeMB $perFileMB

Write-ClutterSummary -Root $target
Write-Host "Done. Point your cleanup script's 'previous installation' check at: $target"
