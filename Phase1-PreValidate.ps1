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

Write-Log "--- Starting Phase 1: Pre-Validate for $NodeName ---" -Color Cyan

# 1. Capture Network Identity (DNA)
Write-Log "[1/3] Capturing Network DNA..." -Color Yellow
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

# 2. Check Cluster Health & Storage Resync
Write-Log "[2/3] Checking Cluster Health and Storage Resync..." -Color Yellow
try {
    $SubSystem = Get-StorageSubSystem -FriendlyName "Clustered Windows Storage*"
    $ClusterHealth = $SubSystem | Get-StorageHealthReport
    
    # Validating Cluster Health
    if ($SubSystem.HealthStatus -ne "Healthy") {
        Write-Log "WARNING: Cluster Health is $($SubSystem.HealthStatus). Review health report before proceeding." -Color Yellow
        $ClusterHealth.Items | Out-String | Write-Log -Color Gray
    }
    else {
        Write-Log "Success: Cluster Health is Healthy." -Color Green
    }

    $StorageJobs = Get-StorageJob | Where-Object { $_.IsBackgroundTask -eq $false -and $_.JobState -ne "Completed" }

    if ($StorageJobs) {
        Write-Log "CRITICAL: Active storage jobs detected. Do NOT proceed until resync is complete." -Color Red
        $StorageJobs | Select-Object Name, JobState, PercentComplete | Out-String | Write-Log -Color White
        exit 1
    }
    Write-Log "Success: No active storage resync jobs." -Color Green
}
catch {
    Write-Log "Could not retrieve storage health via StorageSubSystem. Ensure you are running on an S2D Node." -Color Warning
}

# 3. Export Node Identity
Write-Log "[3/3] Exporting Identity to $ExportPath..." -Color Yellow
$IdentityData = [PSCustomObject]@{
    NodeName      = $NodeName
    Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    OSVersion     = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
    NetworkConfig = $IPConfig
}

$IdentityData | ConvertTo-Json -Depth 5 | Out-File $ExportPath
Write-Log "DONE: Identity exported successfully." -Color Green
Write-Log "Please verify $ExportPath exists on your shared storage before proceeding to Phase 2." -Color White
