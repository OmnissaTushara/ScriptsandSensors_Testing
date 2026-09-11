#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workspace ONE / Intelligent Hub - App Installation Remediation
.DESCRIPTION
    Diagnoses and remediates stuck/failed app installs pushed via Workspace ONE
    UEM (Win32 apps, MSI, Appx) through Intelligent Hub.
#>

$LogPath = "$env:ProgramData\WS1Remediation\Logs"
$LogFile = Join-Path $LogPath ("AppInstall_Remediation_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) { Write-Host "ERROR: Run as Administrator." -ForegroundColor Red; return }

Write-Log "==================== App Install Remediation Started ===================="

function Get-PendingHubApps {
    Write-Log "Checking AirWatch app deployment queue / cache..."
    $paths = @(
        "$env:ProgramData\AirWatch\AppDeploymentCache",
        "$env:ProgramData\AirWatch\UnifiedAgent\Apps"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Write-Log "Found cache path: $p"
            Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "  Item: $($_.Name)" }
        } else {
            Write-Log "Path not found: $p" "WARN"
        }
    }
}

function Get-MdmAppInstallLogs {
    Write-Log "Checking Windows MDM app install event logs..."
    try {
        $events = Get-WinEvent -LogName "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin" -MaxEvents 50 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "app|Enterprise" }
        if ($events) {
            $events | Select-Object -First 10 | ForEach-Object { Write-Log "EventId $($_.Id): $($_.Message.Substring(0, [Math]::Min(200,$_.Message.Length)))" }
        } else { Write-Log "No relevant MDM app-install events found." "WARN" }
    }
    catch { Write-Log "Error reading event log: $_" "ERROR" }
}

function Clear-AppInstallCache {
    Write-Log "Clearing stuck app deployment cache..." "WARN"
    $confirm = Read-Host "This clears cached app install packages so Hub re-downloads them. Continue? (Y/N)"
    if ($confirm -notmatch "^[Yy]") { Write-Log "Cancelled by user." "WARN"; return }
    $paths = @(
        "$env:ProgramData\AirWatch\AppDeploymentCache",
        "$env:ProgramData\AirWatch\UnifiedAgent\Apps\Downloads"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try { Remove-Item -Path "$p\*" -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "Cleared: $p" }
            catch { Write-Log "Failed to clear $p : $_" "ERROR" }
        }
    }
}

function Restart-AppDeploymentServices {
    Write-Log "Restarting services responsible for app deployment..."
    foreach ($name in @("AirWatchService", "AwWindowsIpcSvc", "DoSvc")) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            try { Restart-Service -Name $name -Force -ErrorAction Stop; Write-Log "Restarted: $name" }
            catch { Write-Log "Failed to restart $name : $_" "ERROR" }
        } else { Write-Log "Service $name not present." "WARN" }
    }
}

function Invoke-ForceAppSync {
    Write-Log "Forcing app deployment re-sync via MDM scheduled tasks..."
    try {
        $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match "PushLaunch|Schedule #" }
        if ($tasks) {
            $tasks | ForEach-Object { Start-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName; Write-Log "Triggered: $($_.TaskPath)$($_.TaskName)" }
        } else { Write-Log "No MDM sync tasks found." "WARN" }
    }
    catch { Write-Log "Error forcing app sync: $_" "ERROR" }
}

function Test-DiskSpace {
    Write-Log "Checking free disk space (common cause of failed installs)..."
    try {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
            Write-Log "Drive $($_.DeviceID) Free: $freeGB GB"
            if ($freeGB -lt 5) { Write-Log "LOW DISK SPACE on $($_.DeviceID): $freeGB GB" "WARN" }
        }
    }
    catch { Write-Log "Error checking disk space: $_" "ERROR" }
}

function Show-Menu {
    Write-Host "`n===== App Installation Remediation =====" -ForegroundColor Cyan
    Write-Host "1. Check pending/stuck app cache"
    Write-Host "2. Check MDM app-install event logs"
    Write-Host "3. Clear app install cache (forces re-download)"
    Write-Host "4. Restart app deployment services"
    Write-Host "5. Force app sync"
    Write-Host "6. Check disk space"
    Write-Host "7. Run full diagnostic (1,2,6) + force sync"
    Write-Host "0. Exit"
    Write-Host "=========================================="
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" { Get-PendingHubApps }
        "2" { Get-MdmAppInstallLogs }
        "3" { Clear-AppInstallCache }
        "4" { Restart-AppDeploymentServices }
        "5" { Invoke-ForceAppSync }
        "6" { Test-DiskSpace }
        "7" { Get-PendingHubApps; Get-MdmAppInstallLogs; Test-DiskSpace; Invoke-ForceAppSync }
        "0" { Write-Log "Exiting." }
        default { Write-Host "Invalid option." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Log "==================== App Install Remediation Ended ===================="
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Green
