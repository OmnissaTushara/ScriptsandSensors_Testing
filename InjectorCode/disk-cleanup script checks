<#
.SYNOPSIS
    Populates a sandbox folder with junk files that mirror the exact 11
    target paths your disk-cleanup script checks (previous installs,
    update artifacts, delivery-optimization cache, minidumps, MEMORY.DMP,
    WER report queue/archive, Panther, MoSetup logs) — relative to a
    -BasePath instead of the real C:\.

.DESCRIPTION
    Your cleanup script hardcodes absolute paths like C:\Windows.old and
    C:\Windows\SoftwareDistribution\Download. Junk dropped at
    %TEMP%\DiskCleanupSim alone won't be seen by that script, because it
    never looks there. This generator instead recreates the SAME relative
    structure under a sandbox root, so a *parameterized* copy of your
    cleanup script (Invoke-DiskCleanup.SafeTest.ps1) can be pointed at the
    sandbox and actually find + remove something.

.PARAMETER BasePath
    Sandbox root. Default: $env:TEMP\DiskCleanupSim (NOT C:\).

.PARAMETER SizeMB
    Approximate size (MB) of junk to generate per target. Default: 40
    (11 targets => ~440 MB total with default settings).

.PARAMETER Force
    Required (plus interactive "YES" confirmation) if -BasePath resolves
    to a real system path (C:\, C:\Windows, C:\ProgramData, etc.).
    Not recommended — see README.md.

.EXAMPLE
    .\Add-UnwantedTempFiles.ps1
    .\Add-UnwantedTempFiles.ps1 -BasePath C:\DiskCleanupSim -SizeMB 25
#>
[CmdletBinding()]
param(
    [string]$BasePath = (Join-Path $env:TEMP 'DiskCleanupSim'),
    [double]$SizeMB = 40,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Test-IsSensitivePath {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $sensitiveRoots = @(
        "$env:SystemDrive\",
        "$env:SystemRoot",
        "$env:ProgramData",
        "$env:ProgramFiles",
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ }
    foreach ($root in $sensitiveRoots) {
        if ($resolved.StartsWith([System.IO.Path]::GetFullPath($root), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function New-JunkFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][double]$SizeMB)
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bytesTotal = [int64]($SizeMB * 1MB)
    $chunkSize  = [int]1MB
    $rng        = [System.Random]::new()
    $buffer     = New-Object byte[] $chunkSize
    $fs = [System.IO.File]::Open($Path, 'Create', 'Write')
    try {
        $written = 0L
        while ($written -lt $bytesTotal) {
            $toWrite = [Math]::Min($chunkSize, $bytesTotal - $written)
            $rng.NextBytes($buffer)
            $fs.Write($buffer, 0, [int]$toWrite)
            $written += $toWrite
        }
    } finally { $fs.Close() }
}

if (Test-IsSensitivePath -Path $BasePath) {
    Write-Warning "BasePath resolves to a REAL system location: $BasePath"
    if (-not $Force) {
        throw "Refusing to write junk files into a real system path. Re-run with -Force to override (not recommended), or use the default sandbox path."
    }
    Write-Warning "You passed -Force. This will place fake bloat inside real Windows/ProgramData folders."
    if ((Read-Host 'Type YES to confirm') -ne 'YES') { throw 'Confirmation not received. Aborting.' }
}

# Must exactly match the relative form of the targets in the real cleanup script.
$targets = @(
    @{ Rel = 'Windows.old'; Type = 'Dir' },
    @{ Rel = '$WINDOWS.~BT'; Type = 'Dir' },
    @{ Rel = '$Windows.~WS'; Type = 'Dir' },
    @{ Rel = 'Windows\SoftwareDistribution\Download'; Type = 'Dir' },
    @{ Rel = 'ProgramData\Microsoft\Windows\DeliveryOptimization\Cache'; Type = 'Dir' },
    @{ Rel = 'Windows\Minidump'; Type = 'Dir' },
    @{ Rel = 'Windows\MEMORY.DMP'; Type = 'File' },
    @{ Rel = 'ProgramData\Microsoft\Windows\WER\ReportArchive'; Type = 'Dir' },
    @{ Rel = 'ProgramData\Microsoft\Windows\WER\ReportQueue'; Type = 'Dir' },
    @{ Rel = 'Windows\Panther'; Type = 'Dir' },
    @{ Rel = 'Windows\Logs\MoSetup'; Type = 'Dir' }
)

Write-Host "Populating sandbox junk under: $BasePath"
foreach ($t in $targets) {
    $full = Join-Path $BasePath $t.Rel
    if ($t.Type -eq 'File') {
        New-JunkFile -Path $full -SizeMB $SizeMB
        Write-Host "  created file : $full ($SizeMB MB)"
    } else {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
        # a couple of junk files inside so the folder has real weight
        New-JunkFile -Path (Join-Path $full 'data1.bin') -SizeMB ($SizeMB * 0.6)
        New-JunkFile -Path (Join-Path $full 'data2.bin') -SizeMB ($SizeMB * 0.4)
        Write-Host "  created dir  : $full ($SizeMB MB)"
    }
}

$items = Get-ChildItem -Path $BasePath -Recurse -File -ErrorAction SilentlyContinue
$totalGB = [Math]::Round((($items | Measure-Object -Property Length -Sum).Sum / 1GB), 3)
Write-Host "`nDone. $($items.Count) junk file(s), $totalGB GB under $BasePath"
Write-Host "Now run Invoke-DiskCleanup.SafeTest.ps1 -BasePath `"$BasePath`" to test the cleanup logic against this sandbox."
