<#
.SYNOPSIS
    Test-safe wrapper around your Windows disk-cleanup script. Same
    detection/removal logic, but every target path is resolved under a
    -BasePath (default: the DiskCleanupSim sandbox) instead of hardcoded
    against the real C:\. Supports -DryRun to preview without deleting.

.DESCRIPTION
    Your original script always targets:
        C:\Windows.old
        C:\$WINDOWS.~BT
        C:\$Windows.~WS
        C:\Windows\SoftwareDistribution\Download
        C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache
        C:\Windows\Minidump
        C:\Windows\MEMORY.DMP
        C:\ProgramData\Microsoft\Windows\WER\ReportArchive
        C:\ProgramData\Microsoft\Windows\WER\ReportQueue
        C:\Windows\Panther
        C:\Windows\Logs\MoSetup
    and stops/restarts wuauserv, bits, dosvc around the deletion.

    This variant keeps that exact logic but:
      1. Prefixes every target with -BasePath, so pointing it at the
         DiskCleanupSim sandbox lets you verify detection, removal, and
         the reclaimed-GB math without ever touching real system state.
      2. Adds -DryRun: reports what WOULD be removed and how much space
         WOULD be reclaimed, without deleting anything.
      3. Only touches Windows Update/BITS/Delivery Optimization services
         if you explicitly pass -TouchServices — and if -BasePath is not
         the real system drive, service handling is skipped automatically
         regardless, since stopping real services makes no sense for a
         sandbox test.
      4. If -BasePath resolves to the real system drive (i.e. you are
         about to run this for real), it requires an interactive "YES"
         confirmation before deleting anything, unless -DryRun is set.

.PARAMETER BasePath
    Root to resolve all targets under. Default: $env:TEMP\DiskCleanupSim.
    Pass -BasePath 'C:\' to run against the real system (see safety notes
    above and in README.md before doing this).

.PARAMETER DryRun
    Preview mode: computes sizes and lists what would be removed, deletes
    nothing.

.PARAMETER TouchServices
    Actually stop/start wuauserv, bits, dosvc around the run. Only takes
    effect when -BasePath is the real system drive AND this switch is
    passed explicitly.

.EXAMPLE
    # Safe test against the sandbox
    .\Invoke-DiskCleanup.SafeTest.ps1

.EXAMPLE
    # Preview a real run without deleting anything
    .\Invoke-DiskCleanup.SafeTest.ps1 -BasePath 'C:\' -DryRun

.EXAMPLE
    # Real run (after you've reviewed the dry run) — requires typed YES
    .\Invoke-DiskCleanup.SafeTest.ps1 -BasePath 'C:\' -TouchServices
#>
[CmdletBinding()]
param(
    [string]$BasePath = (Join-Path $env:TEMP 'DiskCleanupSim'),
    [switch]$DryRun,
    [switch]$TouchServices
)

$ErrorActionPreference = 'Stop'

$isRealSystemRun = ([System.IO.Path]::GetFullPath($BasePath)).TrimEnd('\') -ieq $env:SystemDrive

function Get-FolderSizeBytes {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        return [int64](Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
    } catch { return 0 }
}

function Remove-PathIfPresent {
    param([Parameter(Mandatory=$true)][string]$Path, [switch]$DryRun)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path = $Path; Removed = $false; Bytes = 0; Note = 'missing' }
    }
    $bytes = Get-FolderSizeBytes -Path $Path
    if ($DryRun) {
        return [pscustomobject]@{ Path = $Path; Removed = $false; Bytes = $bytes; Note = 'would_delete (dry run)' }
    }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return [pscustomobject]@{ Path = $Path; Removed = $true; Bytes = $bytes; Note = 'deleted' }
    } catch {
        return [pscustomobject]@{ Path = $Path; Removed = $false; Bytes = 0; Note = "failed: $($_.Exception.Message)" }
    }
}

# Same 11 targets as the original script, resolved relative to -BasePath.
$relativeTargets = @(
    'Windows.old',
    '$WINDOWS.~BT',
    '$Windows.~WS',
    'Windows\SoftwareDistribution\Download',
    'ProgramData\Microsoft\Windows\DeliveryOptimization\Cache',
    'Windows\Minidump',
    'Windows\MEMORY.DMP',
    'ProgramData\Microsoft\Windows\WER\ReportArchive',
    'ProgramData\Microsoft\Windows\WER\ReportQueue',
    'Windows\Panther',
    'Windows\Logs\MoSetup'
)
$targets = $relativeTargets | ForEach-Object { Join-Path $BasePath $_ }

if ($isRealSystemRun -and -not $DryRun) {
    Write-Warning "BasePath is the REAL system drive ($BasePath). This will permanently delete live Windows Update cache, WER crash report queues, Panther setup logs, and minidumps."
    Write-Warning "Recommended: run with -DryRun first, and prefer testing on a disposable VM rather than a production endpoint."
    if ((Read-Host 'Type YES to proceed with REAL deletion') -ne 'YES') {
        Write-Host 'Aborted. Nothing was deleted.'
        return
    }
}

$doTouchServices = $TouchServices -and $isRealSystemRun -and -not $DryRun
$servicesToStop = @('wuauserv', 'bits', 'dosvc')
$stoppedServices = @()
$startedServices = @()

try {
    if ($doTouchServices) {
        foreach ($svcName in $servicesToStop) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($null -ne $svc -and $svc.Status -eq 'Running') {
                Stop-Service -Name $svcName -Force -ErrorAction Stop
                $stoppedServices += $svcName
            }
        }
    }

    $results = @()
    $reclaimedBytes = [int64]0
    foreach ($target in $targets) {
        $result = Remove-PathIfPresent -Path $target -DryRun:$DryRun
        $results += $result
        if ($result.Removed -or $result.Note -eq 'would_delete (dry run)') { $reclaimedBytes += [int64]$result.Bytes }
    }

    if ($doTouchServices) {
        foreach ($svcName in $stoppedServices) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($null -ne $svc -and $svc.Status -ne 'Running') {
                Start-Service -Name $svcName -ErrorAction Stop
                $startedServices += $svcName
            }
        }
    }

    $reclaimedGB = [math]::Round($reclaimedBytes / 1GB, 2)
    $removedCount = ($results | Where-Object { $_.Removed -or $_.Note -eq 'would_delete (dry run)' }).Count
    $skippedCount = ($results | Where-Object { -not $_.Removed -and $_.Note -ne 'would_delete (dry run)' }).Count

    $mode = if ($DryRun) { 'dry_run' } else { 'real' }
    Write-Output ("cleanup_{0}_complete: base={1}; removed={2}; skipped={3}; reclaimed_gb={4}" -f $mode, $BasePath, $removedCount, $skippedCount, $reclaimedGB)
    foreach ($r in $results) {
        Write-Output ("{0}: {1}" -f $r.Path, $r.Note)
    }
    if ($stoppedServices.Count -gt 0) { Write-Output ("services_stopped: {0}" -f ($stoppedServices -join ', ')) }
    if ($startedServices.Count -gt 0) { Write-Output ("services_started: {0}" -f ($startedServices -join ', ')) }
    exit 0
} catch {
    Write-Error "Cleanup failed: $($_.Exception.Message)"
    exit 1
}
