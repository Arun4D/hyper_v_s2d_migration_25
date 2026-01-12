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

$Confirm = Read-Host "CRITICAL: Are you sure you want to EVICT $NodeName and CLEAR its local storage metadata? (y/n)"
if ($Confirm -ne 'y') {
    Write-Host "Aborted by user." -ForegroundColor Red
    exit 0
}

Write-Log "--- Starting Phase 2: Migrate/Eviction for $NodeName ---" -Color Cyan

# 1. Drain and Remove Node
Write-Log "[1/2] Draining and Removing Node from Cluster..." -Color Yellow
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

# 2. Clear S2D Metadata
Write-Log "[2/2] Clearing Storage Metadata on Local Disks..." -Color Yellow
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
