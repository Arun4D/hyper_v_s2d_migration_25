<#
.SYNOPSIS
    Phase 1: Pre-Validate and Identity Capture for S2D Migration.
    Run this on the Windows Server 2016 node BEFORE eviction.
#>

Param(
    [Parameter(Mandatory = $false)]
    [string]$SharedPath = $PSScriptRoot
)

$NodeName = $env:COMPUTERNAME
$ExportPath = Join-Path $SharedPath "NodeIdentity_$NodeName.json"
# Per-node logging to prevent interweaving logs in production
$LogPath = Join-Path $SharedPath "Migration_$NodeName.log"

function Write-Log {
    Param([string]$Message, [string]$Color = "White")
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] [$NodeName] [Phase 1] $Message"
    Write-Host $Message -ForegroundColor $Color
    $LogEntry | Out-File $LogPath -Append
}

function Read-Confirmation {
    Param([string]$Message)
    $response = Read-Host "$Message (y/n)"
    if ($response -ne 'y') {
        Write-Log "ABORTED: User did not confirm '$Message'." -Color Red
        exit 1
    }
}

Write-Log "--- Starting Phase 1: Pre-Validate for $NodeName ---" -Color Cyan

# 1. Manual Coordination & Backup Confirmations
Write-Log "[1/16] Coordination & Backup Confirmations..." -Color Yellow
Read-Confirmation "1. Have you backed up the Host OS and configuration?"
Read-Confirmation "2. Have you backed up all Virtual Machines?"
Read-Confirmation "12. Have you notified stakeholders and scheduled downtime?"
Read-Confirmation "14. Have you coordinated with the backup team and received shutdown approval?"
Read-Confirmation "15. Have you coordinated with the AD team regarding VM backup encryption keys?"

# 2. Capture Network Identity (DNA)
Write-Log "[2/16] Capturing Network DNA..." -Color Yellow
$NetworkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object Name, InterfaceDescription, MacAddress, LinkSpeed

$IPConfig = foreach ($adapter in $NetworkAdapters) {
    $IPs = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 | Select-Object IPAddress, PrefixLength
    $Gateways = Get-NetRoute -InterfaceAlias $adapter.Name -DestinationPrefix "0.0.0.0/0" | Select-Object NextHop
    
    [PSCustomObject]@{
        Name        = $adapter.Name
        MacAddress  = $adapter.MacAddress
        IPAddresses = $IPs
        Gateways    = $Gateways.NextHop
    }
}

# 3. Check OS Version
Write-Log "[3/16] Checking OS Version..." -Color Yellow
$OSInfo = Get-CimInstance Win32_OperatingSystem
Write-Log "Current OS: $($OSInfo.Caption) ($($OSInfo.Version))" -Color Gray

# 4. Verify Free Disk Space
Write-Log "[4/16] Verifying Free Disk Space..." -Color Yellow
$SystemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$FreeGB = [math]::Round($SystemDrive.FreeSpace / 1GB, 2)
if ($FreeGB -lt 20) {
    Write-Log "WARNING: Low disk space on C: ($FreeGB GB free). 20GB recommended." -Color Yellow
}
else {
    Write-Log "Success: $FreeGB GB free on C:." -Color Green
}

# 5. Check for Pending Updates / Reboots
Write-Log "[5/16] Checking for Pending Updates/Reboots..." -Color Yellow
$PendingReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
$UpdatePending = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue

if ($PendingReboot -or $UpdatePending) {
    Write-Log "CRITICAL: Pending reboot detected. Please reboot before proceeding." -Color Red
    exit 1
}
Write-Log "Success: No pending reboots detected." -Color Green

# 6 & 13. Validate VM Status and Record Disk Paths
Write-Log "[6/16] Validating Virtual Machine Status..." -Color Yellow
$VMs = Get-VM
$VMData = foreach ($vm in $VMs) {
    $Disks = $vm | Get-VMHardDiskDrive | Select-Object Path
    [PSCustomObject]@{
        Name      = $vm.Name
        State     = $vm.State
        DiskPaths = $Disks.Path
    }
}

$UnhealthyVMs = $VMData | Where-Object { $_.State -ne 'Running' -and $_.State -ne 'Off' }
if ($UnhealthyVMs) {
    Write-Log "WARNING: Some VMs are in non-standard states (e.g., Paused, Saved)." -Color Yellow
    $UnhealthyVMs | Out-String | Write-Log -Color Gray
}

# 7. Export VM Configuration
Write-Log "[7/16] Exporting VM Configurations (Metadata only)..." -Color Yellow
$VMExportPath = Join-Path $SharedPath "VM_Configs_$NodeName"
if (!(Test-Path $VMExportPath)) { New-Item -Path $VMExportPath -ItemType Directory }

foreach ($vm in $VMs) {
    Write-Log "Exporting config for $($vm.Name)..." -Color Gray
    # Exporting metadata only to shared path (not full data)
    $vm | Select-Object * | Export-Clixml -Path (Join-Path $VMExportPath "$($vm.Name).xml")
}

# 8. Virtual Switch configuration
Write-Log "[8/16] Capturing Virtual Switch Configuration..." -Color Yellow
$VMSwitches = Get-VMSwitch | Select-Object Name, SwitchType, NetAdapterInterfaceDescription, NetAdapterInterfaceAlias, EmbeddedTeamingEnabled

# 9. Verify Storage Volumes and Disk Health
Write-Log "[9/16] Checking Cluster Health and Storage Resync..." -Color Yellow
try {
    $SubSystem = Get-StorageSubSystem -FriendlyName "Clustered Windows Storage*"
    $ClusterHealth = $SubSystem | Get-StorageHealthReport
    
    if ($SubSystem.HealthStatus -ne "Healthy") {
        Write-Log "WARNING: Cluster Health is $($SubSystem.HealthStatus)." -Color Yellow
        $ClusterHealth.Items | Out-String | Write-Log -Color Gray
    }
    else {
        $HealthCount = ($ClusterHealth.Items | Where-Object { $_.Severity -eq 'Critical' -or $_.Severity -eq 'Warning' }).Count
        Write-Log "Success: Cluster Health is Healthy (Active Alerts: $HealthCount)." -Color Green
    }

    $StorageJobs = Get-StorageJob | Where-Object { $_.IsBackgroundTask -eq $false -and $_.JobState -ne "Completed" }
    if ($StorageJobs) {
        Write-Log "CRITICAL: Active storage jobs detected. Do NOT proceed." -Color Red
        exit 1
    }
}
catch {
    Write-Log "Could not retrieve storage health." -Color Warning
}

# 11. Check SCCM collection membership
Write-Log "[11/16] Checking SCCM Client Status..." -Color Yellow
if (Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue) {
    Write-Log "SCCM Client (CcmExec) is present and $($ (Get-Service CcmExec).Status )." -Color Green
}
else {
    Write-Log "SCCM Client not found." -Color Gray
}

# 16. Domain Controller Certificates
Write-Log "[16/16] Checking for Expiring Certificates..." -Color Yellow
$ExpiringCerts = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.NotAfter -lt (Get-Date).AddDays(30) }
if ($ExpiringCerts) {
    Write-Log "WARNING: Found certificates expiring within 30 days." -Color Yellow
    $ExpiringCerts | Select-Object Subject, NotAfter | Out-String | Write-Log -Color Gray
}

# Final Export
Write-Log "Finalizing Identity Export..." -Color Yellow
$IdentityData = [PSCustomObject]@{
    NodeName      = $NodeName
    Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    OSVersion     = $OSInfo.Caption
    NetworkConfig = $IPConfig
    VMSwitches    = $VMSwitches
    VMs           = $VMData
    DiskSpace     = $FreeGB
}

$IdentityData | ConvertTo-Json -Depth 5 | Out-File $ExportPath
Write-Log "DONE: Phase 1 complete. Evidence saved to $ExportPath" -Color Green
