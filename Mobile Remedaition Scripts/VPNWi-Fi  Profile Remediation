#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workspace ONE / Intelligent Hub - VPN / Wi-Fi / Profile Remediation
.DESCRIPTION
    Diagnoses and remediates VPN, Wi-Fi, and configuration profile issues
    pushed via Workspace ONE UEM (WMI Bridge / CSP-based profiles).
#>

$LogPath = "$env:ProgramData\WS1Remediation\Logs"
$LogFile = Join-Path $LogPath ("Network_Remediation_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
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

Write-Log "==================== VPN/Wi-Fi/Profile Remediation Started ===================="

function Get-VpnProfiles {
    Write-Log "Checking configured VPN profiles..."
    try {
        $vpns = Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue
        if ($vpns) { $vpns | ForEach-Object { Write-Log "VPN: $($_.Name) | ServerAddress: $($_.ServerAddress) | ConnectionStatus: $($_.ConnectionStatus)" } }
        else { Write-Log "No all-user VPN profiles found." "WARN" }

        $vpnsUser = Get-VpnConnection -ErrorAction SilentlyContinue
        if ($vpnsUser) { $vpnsUser | ForEach-Object { Write-Log "User VPN: $($_.Name) | Status: $($_.ConnectionStatus)" } }
    }
    catch { Write-Log "Error checking VPN profiles: $_" "ERROR" }
}

function Get-WifiProfiles {
    Write-Log "Checking configured Wi-Fi profiles..."
    try {
        $profiles = netsh wlan show profiles | Select-String "All User Profile"
        $profiles | ForEach-Object { Write-Log $_.ToString().Trim() }

        Write-Log "---- Current Wi-Fi interface status ----"
        netsh wlan show interfaces | Select-String "State|SSID|Signal|Authentication" | ForEach-Object { Write-Log $_.ToString().Trim() }
    }
    catch { Write-Log "Error checking Wi-Fi profiles: $_" "ERROR" }
}

function Remove-WifiProfile {
    param([string]$ProfileName)
    if (-not $ProfileName) { $ProfileName = Read-Host "Enter the exact Wi-Fi profile name to remove" }
    Write-Log "Removing Wi-Fi profile: $ProfileName"
    try {
        netsh wlan delete profile name="$ProfileName" | ForEach-Object { Write-Log $_ }
    }
    catch { Write-Log "Error removing Wi-Fi profile: $_" "ERROR" }
}

function Remove-VpnProfile {
    param([string]$VpnName)
    if (-not $VpnName) { $VpnName = Read-Host "Enter the exact VPN profile name to remove" }
    Write-Log "Removing VPN profile: $VpnName"
    try {
        Remove-VpnConnection -Name $VpnName -AllUserConnection -Force -ErrorAction SilentlyContinue
        Remove-VpnConnection -Name $VpnName -Force -ErrorAction SilentlyContinue
        Write-Log "Removed VPN profile: $VpnName (will be re-pushed by UEM on next sync)"
    }
    catch { Write-Log "Error removing VPN profile: $_" "ERROR" }
}

function Test-ProfileServiceStatus {
    Write-Log "Checking Windows profile/CSP delivery pipeline (WMI Bridge, DM Client)..."
    foreach ($svc in @("wdiwifi", "WwanSvc", "RasMan", "dmwappushservice")) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) { Write-Log "Service $svc : Status=$($s.Status) StartType=$($s.StartType)" }
        else { Write-Log "Service $svc not found." "WARN" }
    }
}

function Invoke-ProfileResync {
    Write-Log "Forcing MDM profile resync..."
    try {
        $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match "PushLaunch|Schedule #" }
        if ($tasks) { $tasks | ForEach-Object { Start-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName; Write-Log "Triggered: $($_.TaskPath)$($_.TaskName)" } }
        else { Write-Log "No MDM sync tasks found." "WARN" }
    }
    catch { Write-Log "Error forcing profile resync: $_" "ERROR" }
}

function Reset-NetworkStack {
    Write-Log "Resetting network stack (Winsock/IP) - use for persistent connectivity issues..." "WARN"
    $confirm = Read-Host "This resets Winsock and IP stack; a reboot is required afterward. Continue? (Y/N)"
    if ($confirm -notmatch "^[Yy]") { Write-Log "Cancelled by user." "WARN"; return }
    try {
        netsh winsock reset | ForEach-Object { Write-Log $_ }
        netsh int ip reset | ForEach-Object { Write-Log $_ }
        ipconfig /flushdns | ForEach-Object { Write-Log $_ }
        Write-Log "Network stack reset complete. RESTART THE DEVICE to apply."
    }
    catch { Write-Log "Error resetting network stack: $_" "ERROR" }
}

function Show-Menu {
    Write-Host "`n===== VPN / Wi-Fi / Profile Remediation =====" -ForegroundColor Cyan
    Write-Host "1. Check VPN profiles"
    Write-Host "2. Check Wi-Fi profiles"
    Write-Host "3. Remove a Wi-Fi profile (will be re-pushed by UEM)"
    Write-Host "4. Remove a VPN profile (will be re-pushed by UEM)"
    Write-Host "5. Check profile delivery services"
    Write-Host "6. Force MDM profile resync"
    Write-Host "7. Reset network stack (Winsock/IP) - requires reboot"
    Write-Host "8. Run full diagnostic (1,2,5)"
    Write-Host "0. Exit"
    Write-Host "==============================================="
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" { Get-VpnProfiles }
        "2" { Get-WifiProfiles }
        "3" { Remove-WifiProfile }
        "4" { Remove-VpnProfile }
        "5" { Test-ProfileServiceStatus }
        "6" { Invoke-ProfileResync }
        "7" { Reset-NetworkStack }
        "8" { Get-VpnProfiles; Get-WifiProfiles; Test-ProfileServiceStatus }
        "0" { Write-Log "Exiting." }
        default { Write-Host "Invalid option." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Log "==================== VPN/Wi-Fi/Profile Remediation Ended ===================="
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Green
