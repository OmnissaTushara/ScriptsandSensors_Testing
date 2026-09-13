#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workspace ONE Intelligent Hub - Application/Service Remediation
.DESCRIPTION
    Diagnoses and remediates Hub app crashes, stuck loading screens, cache
    corruption, and background service issues.
#>

$LogPath = "$env:ProgramData\WS1Remediation\Logs"
$LogFile = Join-Path $LogPath ("Hub_Remediation_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
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

Write-Log "==================== Intelligent Hub Remediation Started ===================="

function Get-HubVersion {
    Write-Log "Checking installed Intelligent Hub version..."
    try {
        $hubApp = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*WorkspaceONEIntelligentHub*" -or $_.Name -like "*AirWatchLLC*" }
        if ($hubApp) { Write-Log "Hub: $($hubApp.Name) v$($hubApp.Version) InstallLocation: $($hubApp.InstallLocation)" }
        else { Write-Log "Intelligent Hub not found." "WARN" }
    }
    catch { Write-Log "Error checking Hub version: $_" "ERROR" }
}

function Get-HubProcesses {
    Write-Log "Checking running Hub processes..."
    $procs = Get-Process | Where-Object { $_.ProcessName -match "AirWatch|Hub|AW\." }
    if ($procs) { $procs | ForEach-Object { Write-Log "Process: $($_.ProcessName) PID:$($_.Id) CPU:$($_.CPU)" } }
    else { Write-Log "No Hub-related processes currently running." "WARN" }
}

function Restart-HubApp {
    Write-Log "Restarting Intelligent Hub app..."
    try {
        Get-Process | Where-Object { $_.ProcessName -match "AirWatch|Hub|AW\." } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $hubApp = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*WorkspaceONEIntelligentHub*" }
        if ($hubApp) {
            $manifest = Get-AppxPackageManifest -Package $hubApp.PackageFullName -ErrorAction SilentlyContinue
            $appId = $manifest.Package.Applications.Application.Id
            if ($appId) {
                Start-Process "shell:AppsFolder\$($hubApp.PackageFamilyName)!$appId"
                Write-Log "Relaunched Intelligent Hub."
            } else {
                Write-Log "Could not resolve AppId to relaunch automatically - launch Hub manually from Start Menu." "WARN"
            }
        }
    }
    catch { Write-Log "Error restarting Hub app: $_" "ERROR" }
}

function Restart-HubBackgroundServices {
    Write-Log "Restarting Hub background services..."
    foreach ($name in @("AirWatchService", "AwWindowsIpcSvc")) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            try { Restart-Service -Name $name -Force -ErrorAction Stop; Write-Log "Restarted: $name" }
            catch { Write-Log "Failed to restart $name : $_" "ERROR" }
        } else { Write-Log "Service $name not present on this device." "WARN" }
    }
}

function Clear-HubCache {
    Write-Log "Clearing Intelligent Hub app cache (fixes stuck/blank screens)..." "WARN"
    $confirm = Read-Host "This clears the Hub app's local cache. Hub may need to re-sync on next launch. Continue? (Y/N)"
    if ($confirm -notmatch "^[Yy]") { Write-Log "Cancelled by user." "WARN"; return }
    try {
        Get-Process | Where-Object { $_.ProcessName -match "AirWatch|Hub|AW\." } | Stop-Process -Force -ErrorAction SilentlyContinue
        $hubApp = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*WorkspaceONEIntelligentHub*" }
        if ($hubApp) {
            $localCache = "$env:LOCALAPPDATA\Packages\$($hubApp.PackageFamilyName)\LocalCache"
            $localState = "$env:LOCALAPPDATA\Packages\$($hubApp.PackageFamilyName)\LocalState"
            foreach ($path in @($localCache, $localState)) {
                if (Test-Path $path) {
                    Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Cleared: $path"
                }
            }
        } else { Write-Log "Hub package not found - cannot resolve cache path." "WARN" }
    }
    catch { Write-Log "Error clearing Hub cache: $_" "ERROR" }
}

function Reinstall-Hub {
    Write-Log "Reinstalling Intelligent Hub..." "WARN"
    $confirm = Read-Host "This removes and reinstalls Hub. Device stays enrolled (enrollment record is separate). Continue? (Y/N)"
    if ($confirm -notmatch "^[Yy]") { Write-Log "Cancelled by user." "WARN"; return }
    try {
        $hubApp = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*WorkspaceONEIntelligentHub*" }
        if ($hubApp) {
            $hubApp | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Write-Log "Removed existing Hub package."
        }
        Write-Log "Now reinstall Hub from the Microsoft Store, or run the AirwatchAgent.msi / WS1_Hub.exe installer provided by your UEM admin."
        Write-Log "Example silent install: AirwatchAgent.msi /quiet ENROLL=Y DM=1 SERVER=<your-DS-URL> LGName=<OG> USERNAME=<user> PASSWORD=<pass>"
    }
    catch { Write-Log "Error reinstalling Hub: $_" "ERROR" }
}

function Get-HubLogs {
    Write-Log "Locating Hub diagnostic logs..."
    $logPaths = @(
        "$env:ProgramData\AirWatch\UnifiedAgent\Logs",
        "$env:LOCALAPPDATA\Packages"
    )
    foreach ($p in $logPaths) {
        if (Test-Path $p) { Write-Log "Log location present: $p" }
        else { Write-Log "Not found: $p" "WARN" }
    }
    Write-Log "Tip: Hub has a built-in 'Send Log' / 'Support Info' option under the app's settings/about screen - use that for full diagnostic bundles."
}

function Show-Menu {
    Write-Host "`n===== Intelligent Hub Remediation =====" -ForegroundColor Cyan
    Write-Host "1. Check Hub version"
    Write-Host "2. Check running Hub processes"
    Write-Host "3. Restart Hub app"
    Write-Host "4. Restart Hub background services"
    Write-Host "5. Clear Hub cache"
    Write-Host "6. Reinstall Hub (guided)"
    Write-Host "7. Locate Hub logs"
    Write-Host "8. Run full diagnostic (1,2,7)"
    Write-Host "0. Exit"
    Write-Host "========================================"
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" { Get-HubVersion }
        "2" { Get-HubProcesses }
        "3" { Restart-HubApp }
        "4" { Restart-HubBackgroundServices }
        "5" { Clear-HubCache }
        "6" { Reinstall-Hub }
        "7" { Get-HubLogs }
        "8" { Get-HubVersion; Get-HubProcesses; Get-HubLogs }
        "0" { Write-Log "Exiting." }
        default { Write-Host "Invalid option." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Log "==================== Intelligent Hub Remediation Ended ===================="
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Green
