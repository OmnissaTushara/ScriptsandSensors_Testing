#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workspace ONE / Intelligent Hub - Email Profile Remediation
.DESCRIPTION
    Diagnoses and remediates common managed-email (EAS / cert-based) issues
    pushed via Workspace ONE UEM profiles on Windows.
#>

$LogPath = "$env:ProgramData\WS1Remediation\Logs"
$LogFile = Join-Path $LogPath ("Email_Remediation_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
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

Write-Log "==================== Email Remediation Started ===================="

function Get-EmailProfiles {
    Write-Log "Enumerating configured mail accounts (current user context)..."
    try {
        $outlookProfiles = Get-ChildItem "HKCU:\Software\Microsoft\Office\*\Outlook\Profiles" -ErrorAction SilentlyContinue -Recurse
        if ($outlookProfiles) {
            $outlookProfiles | ForEach-Object { Write-Log "Outlook profile key: $($_.Name)" }
        } else {
            Write-Log "No Outlook profile registry keys found for current user." "WARN"
        }

        Write-Log "Checking Windows Mail app configured accounts..."
        Get-Service -Name "WpnUserService*" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "Service: $($_.Name) - Status: $($_.Status)"
        }
    }
    catch { Write-Log "Error enumerating email profiles: $_" "ERROR" }
}

function Test-EmailCertificates {
    Write-Log "Checking client/email certificates (S/MIME, cert-based auth)..."
    try {
        $certs = Get-ChildItem -Path "Cert:\CurrentUser\My" -ErrorAction SilentlyContinue
        if ($certs) {
            foreach ($c in $certs) {
                Write-Log "Cert: $($c.Subject) | Expires: $($c.NotAfter) | Thumbprint: $($c.Thumbprint)"
                if ($c.NotAfter -lt (Get-Date)) { Write-Log "EXPIRED cert: $($c.Subject)" "WARN" }
                if (-not $c.HasPrivateKey) { Write-Log "Missing private key for: $($c.Subject)" "WARN" }
            }
        } else {
            Write-Log "No certificates found in CurrentUser\My store." "WARN"
        }
    }
    catch { Write-Log "Error checking email certs: $_" "ERROR" }
}

function Invoke-ProfileResync {
    Write-Log "Requesting UEM profile resync (device-wide, via MDM scheduled tasks)..."
    try {
        $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match "PushLaunch|Schedule #" }
        if ($tasks) {
            $tasks | ForEach-Object {
                Start-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName
                Write-Log "Triggered: $($_.TaskPath)$($_.TaskName)"
            }
        } else { Write-Log "No MDM sync tasks found - check enrollment." "WARN" }
    }
    catch { Write-Log "Error triggering profile resync: $_" "ERROR" }
}

function Reset-OutlookProfile {
    Write-Log "Resetting Outlook profile cache (current user)..." "WARN"
    $confirm = Read-Host "This clears the local Outlook profile cache for the current user. Continue? (Y/N)"
    if ($confirm -notmatch "^[Yy]") { Write-Log "Cancelled by user." "WARN"; return }
    try {
        Stop-Process -Name "OUTLOOK" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $ostPath = "$env:LOCALAPPDATA\Microsoft\Outlook"
        if (Test-Path $ostPath) {
            $backup = "$ostPath`_backup_$(Get-Date -Format yyyyMMddHHmmss)"
            Rename-Item -Path $ostPath -NewName (Split-Path $backup -Leaf) -ErrorAction SilentlyContinue
            Write-Log "Renamed Outlook cache folder to: $backup (backup, not deleted)"
        }
        Write-Log "Relaunch Outlook to rebuild the profile / re-download mailbox data."
    }
    catch { Write-Log "Error resetting Outlook profile: $_" "ERROR" }
}

function Test-ExchangeConnectivity {
    Write-Log "Testing connectivity to Exchange / EAS endpoints..."
    $endpoints = @("outlook.office365.com", "autodiscover-s.outlook.com")
    foreach ($ep in $endpoints) {
        try {
            $result = Test-NetConnection -ComputerName $ep -Port 443 -WarningAction SilentlyContinue
            Write-Log "Endpoint $ep : TcpTestSucceeded=$($result.TcpTestSucceeded)"
        }
        catch { Write-Log "Error testing $ep : $_" "ERROR" }
    }
}

function Show-Menu {
    Write-Host "`n===== Email Profile Remediation =====" -ForegroundColor Cyan
    Write-Host "1. Enumerate email profiles / mail services"
    Write-Host "2. Check email certificates (S/MIME, cert-auth)"
    Write-Host "3. Force UEM profile resync"
    Write-Host "4. Reset Outlook local profile cache (backs up, does not delete)"
    Write-Host "5. Test Exchange/EAS connectivity"
    Write-Host "6. Run full diagnostic (1,2,3,5)"
    Write-Host "0. Exit"
    Write-Host "======================================="
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" { Get-EmailProfiles }
        "2" { Test-EmailCertificates }
        "3" { Invoke-ProfileResync }
        "4" { Reset-OutlookProfile }
        "5" { Test-ExchangeConnectivity }
        "6" { Get-EmailProfiles; Test-EmailCertificates; Invoke-ProfileResync; Test-ExchangeConnectivity }
        "0" { Write-Log "Exiting." }
        default { Write-Host "Invalid option." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Log "==================== Email Remediation Ended ===================="
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Green
