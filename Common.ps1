#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for the DiskClutterSim scripts.

.DESCRIPTION
    These scripts generate SAFE, FAKE clutter so you can exercise a disk-cleanup
    automation script (targeting cleanmgr.exe categories: previous Windows
    installations, update artifacts, error dumps, upgrade logs) without touching
    real system files.

    SAFETY MODEL
    - Default target is a sandbox folder (under %TEMP% by default), never a real
      system path.
    - Any attempt to write into a sensitive real path (C:\Windows, Program Files,
      C:\Windows.old, $WINDOWS.~BT, $WINDOWS.~WS, etc.) is blocked unless the
      caller passes -Force AND types "YES" at an interactive confirmation prompt.
    - Nothing here calls cleanmgr.exe, deletes real system data, or auto-executes
      anything. You run each script explicitly and review what it will do first.
#>

function Test-IsSensitivePath {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $sensitiveRoots = @(
        "$env:SystemRoot",
        "$env:SystemDrive\Windows.old",
        "$env:SystemDrive\`$WINDOWS.~BT",
        "$env:SystemDrive\`$WINDOWS.~WS",
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

function Assert-SafeTarget {
    <#
    Dry-run / warn / confirm gate. Throws (aborts) unless the target is a
    sandbox path, or the caller explicitly forces + confirms.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force
    )
    if (Test-IsSensitivePath -Path $Path) {
        Write-Warning "Target resolves to a REAL system path: $Path"
        if (-not $Force) {
            throw "Refusing to write simulated clutter into a real system path. Re-run with -Force to override (not recommended), or point -Root at a sandbox folder instead (default: `$env:TEMP\DiskCleanupSim)."
        }
        Write-Warning "You passed -Force. This will place fake files inside a real Windows system folder."
        $confirm = Read-Host 'Type YES to confirm you understand this modifies a real system path'
        if ($confirm -ne 'YES') {
            throw 'Confirmation not received. Aborting - no files were created.'
        }
    }
}

function New-JunkFile {
    <#
    Creates a file of approximately the requested size filled with
    non-zero pseudo-random bytes, streamed in chunks (does not load the
    whole file into memory).
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][double]$SizeMB
    )
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

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
    } finally {
        $fs.Close()
    }
}

function Write-ClutterSummary {
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-Path $Root)) {
        Write-Host "Nothing found at $Root"
        return
    }
    $items = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue
    $totalBytes = ($items | Measure-Object -Property Length -Sum).Sum
    $gb = if ($totalBytes) { [Math]::Round(($totalBytes / 1GB), 3) } else { 0 }
    Write-Host "Simulated clutter under '$Root': $($items.Count) file(s), $gb GB"
}
