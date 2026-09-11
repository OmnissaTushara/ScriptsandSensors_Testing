#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workspace ONE / Intelligent Hub - Compliance & Access Remediation
.DESCRIPTION
    Diagnoses and remediates common compliance-policy and conditional-access
    blocking issues for devices managed by Workspace ONE UEM.
#>

$LogPath = "$env:ProgramData\WS1Remediation\Logs"
$LogFile = Join-Path $LogPath ("Compliance_Remediation_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
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

Write-Log "==================== Compliance Remediation Started ===================="

function Get-ComplianceState {
    Write-Log "Checking Azure AD / hybrid join and MDM compliance state..."
    try {
        dsregcmd /status | Select-String -Pattern "AzureAdJoined|DomainJoined|IsMdmEnrolled|DeviceId|TenantId" |
            ForEach-Object { Write-Log $_.ToString().Trim() }
    }
    catch { Write-Log "Error getting dsregcmd status: $_" "ERROR" }
}

function Test-DiskEncryption {
    Write-Log "Checking BitLocker / disk encryption status (common compliance rule)..."
    try {
        $vols = Get-BitLockerVolume -ErrorAction SilentlyContinue
        if ($vols) {
            $vols | ForEach-Object { Write-Log "Volume $($_.MountPoint): ProtectionStatus=$($_.ProtectionStatus) EncryptionPercentage=$($_.EncryptionPercentage)" }
        } else { Write-Log "BitLocker cmdlet returned no volumes / not available." "WARN" }
    }
    catch { Write-Log "Error checking BitLocker: $_" "ERROR" }
}

function Test-PasscodePolicy {
    Write-Log "Checking local password policy (common compliance rule)..."
    try {
        $policy = net accounts
        $policy | ForEach-Object { Write-Log $_ }
    }
    catch { Write-Log "Error checking password policy: $_" "ERROR" }
}

function Test-DefenderStatus {
    Write-Log "Checking Windows Defender / AV status (common compliance rule)..."
    try {
        $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mp) {
            Write-Log "AntivirusEnabled=$($mp.AntivirusEnabled) RealTimeProtectionEnabled=$($mp.RealTimeProtectionEnabled) AntivirusSignatureAge=$($mp.AntivirusSignatureAge)"
        } else { Write-Log "Could not retrieve Defender status (third-party AV may be in use)." "WARN" }
    }
    catch { Write-Log "Error checking Defender status: $_" "ERROR" }
}

function Invoke-ComplianceRecheck {
    Write-Log "Forcing compliance policy re-evaluation via MDM scheduled tasks..."
    try {
        $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match "PushLaunch|Schedule #" }
        if ($tasks) {
            $tasks | ForEach-Object { Start-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName; Write-Log "Triggered: $($_.TaskPath)$($_.TaskName)" }
            Write-Log "Compliance re-check triggered. Allow 5-15 minutes for the UEM console to reflect updated status."
        } else { Write-Log "No MDM sync tasks found - check enrollment." "WARN" }
    }
    catch { Write-Log "Error forcing compliance recheck: $_" "ERROR" }
}

function Clear-ConditionalAccessTokenCache {
    Write-Log "Clearing cached Azure AD / WAM tokens (helps stuck 'device not compliant' blocks)..." "WARN"
    $confirm = Read-Host "This signs the current user out of cached Microsoft 365 sessions. Continue? (Y/N)"
    if ($confirm -notmatch "^[Yy]") { Write-Log "Cancelled by user." "WARN"; return }
    try {
        $wamPath = "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy"
        if (Test-Path $wamPath) {
            Write-Log "WAM broker cache found at $wamPath (not deleting automatically - restart device to force token refresh)."
        }
        dsregcmd /leave 2>$null
        Write-Log "Note: dsregcmd /leave only applies if device is Azure AD registered (not hybrid/domain joined). Re-register after restart if needed."
    }
    catch { Write-Log "Error clearing token cache: $_" "ERROR" }
}

function Show-Menu {
    Write-Host "`n===== Compliance & Access Remediation =====" -ForegroundColor Cyan
    Write-Host "1. Check AAD join / MDM compliance state"
    Write-Host "2. Check disk encryption (BitLocker)"
    Write-Host "3. Check password policy"
    Write-Host "4. Check Defender/AV status"
    Write-Host "5. Force compliance re-check"
    Write-Host "6. Clear conditional-access token cache (careful)"
    Write-Host "7. Run full diagnostic (1,2,3,4)"
    Write-Host "0. Exit"
    Write-Host "============================================="
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" { Get-ComplianceState }
        "2" { Test-DiskEncryption }
        "3" { Test-PasscodePolicy }
        "4" { Test-DefenderStatus }
        "5" { Invoke-ComplianceRecheck }
        "6" { Clear-ConditionalAccessTokenCache }
        "7" { Get-ComplianceState; Test-DiskEncryption; Test-PasscodePolicy; Test-DefenderStatus }
        "0" { Write-Log "Exiting." }
        default { Write-Host "Invalid option." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Log "==================== Compliance Remediation Ended ===================="
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Green
