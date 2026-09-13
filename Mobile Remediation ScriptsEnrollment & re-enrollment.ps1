#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workspace ONE / Intelligent Hub - Enrollment & Re-Enrollment Remediation
.DESCRIPTION
    Diagnoses and remediates common MDM enrollment issues on Windows devices managed
    by Workspace ONE UEM (AirWatch). Run in PowerShell ISE "as Administrator".
.NOTES
    Review with your UEM admin before running in production. The full-unenroll
    option is destructive and requires typed confirmation.
#>

$LogPath   = "$env:ProgramData\WS1Remediation\Logs"
$LogFile   = Join-Path $LogPath ("Enrollment_Remediation_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "ERROR: This script must be run as Administrator. Right-click PowerShell ISE > Run as Administrator." -ForegroundColor Red
    return
}

Write-Log "==================== Enrollment Remediation Started ===================="

function Get-EnrollmentStatus {
    Write-Log "Checking device MDM enrollment status..."
    try {
        $enrollments = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue
        if (-not $enrollments) {
            Write-Log "No enrollment records found under HKLM:\SOFTWARE\Microsoft\Enrollments" "WARN"
        }
        else {
            foreach ($enr in $enrollments) {
                $providerId = (Get-ItemProperty -Path $enr.PSPath -Name "ProviderID" -ErrorAction SilentlyContinue).ProviderID
                if ($providerId) {
                    Write-Log "Found enrollment: $($enr.PSChildName) -> Provider: $providerId"
                }
            }
        }
        Write-Log "---- dsregcmd /status (MDM section) ----"
        $dsreg = dsregcmd /status | Select-String -Pattern "MdmUrl|MdmTenantId|IsDeviceJoined|IsMdmEnrolled|AzureAdJoined"
        $dsreg | ForEach-Object { Write-Log $_.ToString().Trim() }
    }
    catch {
        Write-Log "Error checking enrollment status: $_" "ERROR"
    }
}

function Test-HubInstalled {
    Write-Log "Checking Workspace ONE Intelligent Hub installation..."
    $hubApp = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*WorkspaceONEIntelligentHub*" -or $_.Name -like "*AirWatchLLC*" }
    if ($hubApp) {
        Write-Log "Intelligent Hub found: $($hubApp.Name) v$($hubApp.Version)"
        return $true
    }
    else {
        Write-Log "Intelligent Hub app NOT found on this device." "WARN"
        return $false
    }
}

function Test-HubServices {
    Write-Log "Checking AirWatch / Hub related services..."
    $services = Get-Service | Where-Object { $_.Name -match "AirWatch|VMware|AwWindowsIpc|AwWindowsMdmAgent" }
    if ($services) {
        $services | ForEach-Object { Write-Log "Service: $($_.Name) - Status: $($_.Status)" }
    }
    else {
        Write-Log "No AirWatch/Hub background services found (this can be normal on newer Hub builds using MDM stack directly)." "WARN"
    }
}

function Invoke-MdmSync {
    Write-Log "Attempting to force MDM sync via scheduled task..."
    try {
        $task = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match "PushLaunch|Schedule #" }
        if ($task) {
            $task | ForEach-Object {
                Start-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName
                Write-Log "Triggered scheduled task: $($_.TaskPath)$($_.TaskName)"
            }
        }
        else {
            Write-Log "No EnterpriseMgmt scheduled tasks found - device may not be MDM enrolled." "WARN"
        }
    }
    catch {
        Write-Log "Error forcing MDM sync: $_" "ERROR"
    }
}

function Restart-HubServices {
    Write-Log "Restarting Hub / AirWatch related services..."
    $svcNames = @("AirWatchService", "AwWindowsIpcSvc")
    foreach ($name in $svcNames) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            try {
                Restart-Service -Name $name -Force -ErrorAction Stop
                Write-Log "Restarted service: $name"
            }
            catch {
                Write-Log "Failed to restart $name : $_" "ERROR"
            }
        }
        else {
            Write-Log "Service $name not present." "WARN"
        }
    }
}

function Invoke-FullUnenroll {
    Write-Log "Starting FULL UNENROLL sequence..." "WARN"
    $confirm = Read-Host "This will remove MDM enrollment and all managed profiles/apps. Type YES to continue"
    if ($confirm -ne "YES") {
        Write-Log "Unenroll cancelled by user." "WARN"
        return
    }

    try {
        $enrollIds = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue |
            Where-Object {
                (Get-ItemProperty $_.PSPath -Name "ProviderID" -ErrorAction SilentlyContinue).ProviderID -match "AirWatchMDM|MDM"
            }

        foreach ($id in $enrollIds) {
            $enrollGuid = $id.PSChildName
            Write-Log "Removing enrollment GUID: $enrollGuid"
            Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\$enrollGuid\*" -ErrorAction SilentlyContinue |
                Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path $id.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Removed registry enrollment key for $enrollGuid"
        }

        $hubApp = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*WorkspaceONEIntelligentHub*" -or $_.Name -like "*AirWatchLLC*" }
        if ($hubApp) {
            $hubApp | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Write-Log "Removed Intelligent Hub app package."
        }

        $paths = @(
            "$env:ProgramData\AirWatch",
            "$env:ProgramData\AirWatchMDM",
            "$env:LOCALAPPDATA\AirWatchLLC"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed residual folder: $p"
            }
        }

        Write-Log "Unenroll sequence complete. Restart the device, then re-enroll via Settings > Accounts > Access work or school, or reinstall Intelligent Hub from Microsoft Store / MSI."
    }
    catch {
        Write-Log "Error during unenroll: $_" "ERROR"
    }
}

function Test-EnrollmentCertificates {
    Write-Log "Checking device certificates related to MDM enrollment..."
    try {
        $certs = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object { $_.Subject -match "AirWatch|Workspace ONE" }
        if ($certs) {
            $certs | ForEach-Object {
                Write-Log "Cert: $($_.Subject) | Expires: $($_.NotAfter) | Thumbprint: $($_.Thumbprint)"
                if ($_.NotAfter -lt (Get-Date)) {
                    Write-Log "Certificate EXPIRED: $($_.Subject)" "WARN"
                }
            }
        }
        else {
            Write-Log "No AirWatch/Workspace ONE certificates found in LocalMachine\My store." "WARN"
        }
    }
    catch {
        Write-Log "Error checking certificates: $_" "ERROR"
    }
}

function Show-Menu {
    Write-Host ""
    Write-Host "===== Enrollment & Re-Enrollment Remediation =====" -ForegroundColor Cyan
    Write-Host "1. Check enrollment status"
    Write-Host "2. Check Hub install + services"
    Write-Host "3. Force MDM sync (non-destructive)"
    Write-Host "4. Restart Hub services"
    Write-Host "5. Check enrollment certificates"
    Write-Host "6. FULL UNENROLL (destructive - use for re-enrollment)"
    Write-Host "7. Run full diagnostic (1,2,3,5)"
    Write-Host "0. Exit"
    Write-Host "==================================================="
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" { Get-EnrollmentStatus }
        "2" { Test-HubInstalled; Test-HubServices }
        "3" { Invoke-MdmSync }
        "4" { Restart-HubServices }
        "5" { Test-EnrollmentCertificates }
        "6" { Invoke-FullUnenroll }
        "7" { Get-EnrollmentStatus; Test-HubInstalled; Test-HubServices; Invoke-MdmSync; Test-EnrollmentCertificates }
        "0" { Write-Log "Exiting." }
        default { Write-Host "Invalid option." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Log "==================== Enrollment Remediation Ended ===================="
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Green
