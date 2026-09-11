#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workspace ONE / Intelligent Hub - Miscellaneous BYOD & Device-Specific Remediation
.DESCRIPTION
    Catch-all diagnostics for BYOD/COPE devices: connectivity, device sample
    submission, sensor collection, time sync, and general health checks.
#>

$LogPath = "$env:ProgramData\WS1Remediation\Logs"
$LogFile = Join-Path $LogPath ("Misc_Remediation_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
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

Write-Log "==================== Misc BYOD Remediation Started ===================="

function Get-DeviceIdentity {
    Write-Log "Collecting device identity info..."
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $bios = Get-CimInstance Win32_BIOS
        Write-Log "Manufacturer: $($cs.Manufacturer) | Model: $($cs.Model) | SerialNumber: $($bios.SerialNumber)"
        Write-Log "ComputerName: $env:COMPUTERNAME | OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"
    }
    catch { Write-Log "Error collecting device identity: $_" "ERROR" }
}

function Test-TimeSync {
    Write-Log "Checking time sync (skewed clocks break cert auth and enrollment)..."
    try {
        w32tm /query /status | ForEach-Object { Write-Log $_ }
        $currentTime = Get-Date
        Write-Log "Local system time: $currentTime"
    }
    catch { Write-Log "Error checking time sync: $_" "ERROR" }
}

function Invoke-TimeResync {
    Write-Log "Resyncing system clock with time server..."
    try {
        w32tm /resync | ForEach-Object { Write-Log $_ }
    }
    catch { Write-Log "Error resyncing time: $_" "ERROR" }
}

function Test-ConnectivityToUemConsole {
    Write-Log "Testing connectivity to Workspace ONE UEM console/DS endpoints..."
    $urls = Read-Host "Enter your UEM Device Services / console hostname (e.g. ds123.awmdm.com) - leave blank to skip"
    if ($urls) {
        try {
            $result = Test-NetConnection -ComputerName $urls -Port 443 -WarningAction SilentlyContinue
            Write-Log "Endpoint $urls : TcpTestSucceeded=$($result.TcpTestSucceeded)"
        }
        catch { Write-Log "Error testing $urls : $_" "ERROR" }
    } else {
        Write-Log "Skipped - no hostname provided." "WARN"
    }
}

function Invoke-SensorCollection {
    Write-Log "Forcing device sensor/sample collection (updates inventory shown in console)..."
    try {
        $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match "PushLaunch|Schedule #" }
        if ($tasks) { $tasks | ForEach-Object { Start-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName; Write-Log "Triggered: $($_.TaskPath)$($_.TaskName)" } }
        else { Write-Log "No MDM sync tasks found." "WARN" }
    }
    catch { Write-Log "Error forcing sensor collection: $_" "ERROR" }
}

function Get-BatteryHealth {
    Write-Log "Checking battery health (relevant for BYOD laptops/tablets)..."
    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if ($battery) {
            $battery | ForEach-Object { Write-Log "BatteryStatus: $($_.BatteryStatus) EstimatedChargeRemaining: $($_.EstimatedChargeRemaining)%" }
        } else { Write-Log "No battery detected (desktop device)." "WARN" }
    }
    catch { Write-Log "Error checking battery: $_" "ERROR" }
}

function Get-StorageHealth {
    Write-Log "Checking storage health / free space..."
    try {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
            $totalGB = [math]::Round($_.Size / 1GB, 2)
            Write-Log "Drive $($_.DeviceID): $freeGB GB free of $totalGB GB"
        }
    }
    catch { Write-Log "Error checking storage: $_" "ERROR" }
}

function Restart-DmwappushService {
    Write-Log "Restarting Device Management WAP Push service (dmwappushservice) - underpins MDM push notifications..."
    try {
        Restart-Service -Name "dmwappushservice" -Force -ErrorAction Stop
        Write-Log "Restarted dmwappushservice."
    }
    catch { Write-Log "Error restarting dmwappushservice: $_" "ERROR" }
}

function Export-DiagnosticBundle {
    Write-Log "Exporting a consolidated diagnostic bundle..."
    $bundlePath = Join-Path $LogPath ("DiagBundle_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    New-Item -Path $bundlePath -ItemType Directory -Force | Out-Null
    try {
        dsregcmd /status > "$bundlePath\dsregcmd.txt"
        Get-CimInstance Win32_ComputerSystem | Format-List * > "$bundlePath\computersystem.txt"
        Get-Service | Where-Object { $_.Name -match "AirWatch|dmwappushservice" } | Format-Table -AutoSize > "$bundlePath\services.txt"
        netsh wlan show profiles > "$bundlePath\wifi_profiles.txt"
        Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue | Format-List * > "$bundlePath\vpn_profiles.txt"
        Write-Log "Diagnostic bundle exported to: $bundlePath"
    }
    catch { Write-Log "Error exporting diagnostic bundle: $_" "ERROR" }
}

function Show-Menu {
    Write-Host "`n===== Misc BYOD & Device-Specific Remediation =====" -ForegroundColor Cyan
    Write-Host "1. Device identity info"
    Write-Host "2. Check time sync"
    Write-Host "3. Force time resync"
    Write-Host "4. Test connectivity to UEM console"
    Write-Host "5. Force sensor/sample collection"
    Write-Host "6. Check battery health"
    Write-Host "7. Check storage health"
    Write-Host "8. Restart dmwappushservice"
    Write-Host "9. Export full diagnostic bundle"
    Write-Host "10. Run full diagnostic (1,2,6,7,9)"
    Write-Host "0. Exit"
    Write-Host "====================================================="
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" { Get-DeviceIdentity }
        "2" { Test-TimeSync }
        "3" { Invoke-TimeResync }
        "4" { Test-ConnectivityToUemConsole }
        "5" { Invoke-SensorCollection }
        "6" { Get-BatteryHealth }
        "7" { Get-StorageHealth }
        "8" { Restart-DmwappushService }
        "9" { Export-DiagnosticBundle }
        "10" { Get-DeviceIdentity; Test-TimeSync; Get-BatteryHealth; Get-StorageHealth; Export-DiagnosticBundle }
        "0" { Write-Log "Exiting." }
        default { Write-Host "Invalid option." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Log "==================== Misc BYOD Remediation Ended ===================="
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Green
