<#
.SYNOPSIS
    Phase 2: Migrate (Node Eviction).
    Run this script to drain and remove the node from the cluster.
    Supports rolling upgrades from Windows Server 2016 to 2019/2022.
    WARNING: This script will remove the node and clear storage metadata.
#>

Param(
    [Parameter(Mandatory = $false)]
    [string]$SharedPath = $PSScriptRoot
)

$NodeName = $env:COMPUTERNAME
$LogPath = Join-Path $SharedPath "Migration_$NodeName.log"

function Write-Log {
    Param([string]$Message, [string]$Color = "White")
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] [$NodeName] [Phase 2] $Message"
    Write-Host $Message -ForegroundColor $Color
    $LogEntry | Out-File $LogPath -Append
}

function Test-ModuleAvailability {
    Param([string[]]$Modules, [bool]$Fatal = $true)
    $Missing = @()
    foreach ($m in $Modules) {
        if (!(Get-Module -ListAvailable -Name $m)) {
            $Missing += $m
        }
    }
    if ($Missing) {
        $MsgSeverity = if ($Fatal) { "CRITICAL" } else { "WARNING" }
        $Color = if ($Fatal) { "Red" } else { "Yellow" }
        Write-Log "[$MsgSeverity] Missing modules: $($Missing -join ', ')" -Color $Color
        if ($Fatal) { exit 1 }
    }
}

# Pre-flight Module Check
Test-ModuleAvailability -Modules @("FailoverClusters", "Storage")
Test-ModuleAvailability -Modules @("ActiveDirectory") -Fatal $false

$Confirm = Read-Host "CRITICAL: Are you sure you want to EVICT $NodeName and CLEAR its local storage metadata? (y/n)"
if ($Confirm -ne 'y') {
    Write-Host "Aborted by user." -ForegroundColor Red
    exit 0
}

Write-Log "--- Starting Phase 2: Migrate/Eviction for $NodeName ---" -Color Cyan

# 1. Place Physical Disks in Maintenance Mode
Write-Log "[1/5] Placing Physical Disks in Maintenance Mode..." -Color Yellow
try {
    $StorageNode = Get-StorageNode -Name $NodeName
    $Disks = $StorageNode | Get-PhysicalDisk
    foreach ($disk in $Disks) {
        Write-Log "Setting Disk $($disk.FriendlyName) to Maintenance Mode..." -Color Gray
        $disk | Set-PhysicalDisk -MaintenanceMode $true -ErrorAction Stop
    }
    
    # Verification
    $MaintenanceCheck = $Disks | Get-PhysicalDisk | Where-Object { $_.OperationalStatus -notcontains 'In Maintenance Mode' }
    if ($MaintenanceCheck) {
        Write-Log "WARNING: Some disks did not enter maintenance mode: $($MaintenanceCheck.FriendlyName -join ', ')" -Color Yellow
    }
    else {
        Write-Log "Success: All local disks are in Maintenance Mode." -Color Green
    }
}
catch {
    Write-Log "Failed to set disks to maintenance mode: $($_.Exception.Message)" -Color Warning
}

# 2. Drain and Remove Node
Write-Log "[2/5] Draining and Removing Node from Cluster..." -Color Yellow
try {
    Write-Log "Suspending node with drain..." -Color Gray
    Suspend-ClusterNode -Name $NodeName -Drain -ErrorAction Stop
    
    Write-Log "Removing node from cluster..." -Color Gray
    Remove-ClusterNode -Name $NodeName -Force -ErrorAction Stop
    
    Write-Log "Success: Node evicted from cluster." -Color Green
}
catch {
    Write-Log "Failed to evict node: $($_.Exception.Message)" -Color Red
    exit 1
}

# 3. Verify Eviction and Cluster Service Status
Write-Log "[3/5] Verifying Node Eviction and Cluster Service Status..." -Color Yellow
$ClusterService = Get-Service -Name ClusSvc -ErrorAction SilentlyContinue
if ($ClusterService.Status -eq 'Running') {
    Write-Log "WARNING: Cluster Service is still running. Attempting to stop..." -Color Yellow
    Stop-Service -Name ClusSvc -Force
}

if (!(Get-ClusterNode -Name $NodeName -ErrorAction SilentlyContinue)) {
    Write-Log "Success: Node $NodeName is no longer visible in cluster." -Color Green
}
else {
    Write-Log "CRITICAL: Node $NodeName is still reported as a cluster member!" -Color Red
}

# 4. Active Directory Cleanup
Write-Log "[4/5] Deleting Node Computer Account from Active Directory..." -Color Yellow
Write-Log "This step requires ActiveDirectory module and appropriate permissions." -Color White
try {
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory
        $ADComputer = Get-ADComputer -Identity $NodeName -ErrorAction SilentlyContinue
        if ($ADComputer) {
            Write-Log "Removing $NodeName from AD..." -Color Gray
            Remove-ADComputer -Identity $NodeName -Confirm:$false -ErrorAction Stop
            Write-Log "Success: Computer account removed from AD." -Color Green
        }
        else {
            Write-Log "Computer account $NodeName not found in AD (already removed or wrong DC)." -Color Gray
        }
    }
    else {
        Write-Log "ActiveDirectory module not found. Please manually delete '$NodeName' from AD." -Color Yellow
    }
}
catch {
    Write-Log "Failed to remove AD account: $($_.Exception.Message)" -Color Warning
}

# 5. Clear S2D Metadata
Write-Log "[5/5] Clearing Storage Metadata on Local Disks..." -Color Yellow
$S2DDisks = Get-PhysicalDisk | Where-Object { $_.CanPool -eq $false -and $_.BusType -ne "USB" }

foreach ($disk in $S2DDisks) {
    try {
        Write-Log "Clearing metadata on Disk $($disk.Number) ($($disk.FriendlyName))..." -Color Gray
        $disk | Reset-PhysicalDisk -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "Could not reset metadata on Disk $($disk.Number)." -Color Warning
    }
}

Write-Log "DONE: Phase 2 complete. The node is ready for OS Reinstallation." -Color Green
