<#
.SYNOPSIS
    Finalize-ClusterUpgrade.ps1
    Run this ONLY after ALL nodes in the cluster have been upgraded to Windows Server 2025.
#>

Param(
    [Parameter(Mandatory = $false)]
    [string]$SharedPath = $PSScriptRoot
)

$NodeName = $env:COMPUTERNAME
$LogPath = Join-Path $SharedPath "Migration_Finalize_$NodeName.log"

function Write-Log {
    Param([string]$Message, [string]$Color = "White")
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] [$NodeName] [Finalize] $Message"
    Write-Host $Message -ForegroundColor $Color
    $LogEntry | Out-File $LogPath -Append
}

Write-Log "--- Starting Cluster Upgrade Finalization ---" -Color Cyan

# 1. Update Cluster Functional Level
Write-Log "[1/2] Updating Cluster Functional Level..." -Color Yellow
try {
    $CurrentLevel = (Get-Cluster).ClusterFunctionalLevel
    if ($CurrentLevel -lt 11) {
        Update-ClusterFunctionalLevel -Confirm:$true
        Write-Log "Success: Cluster Functional Level updated." -Color Green
    }
    else {
        Write-Log "Cluster Functional Level is already at the latest version ($CurrentLevel)." -Color Gray
    }
}
catch {
    Write-Log "Failed to update Cluster Functional Level: $($_.Exception.Message)" -Color Red
}

# 2. Update Storage Pool
Write-Log "[2/2] Updating Storage Pool(s)..." -Color Yellow
try {
    $Pools = Get-StoragePool | Where-Object { $_.IsPrimordial -eq $false }
    foreach ($pool in $Pools) {
        Write-Log "Updating Storage Pool: $($pool.FriendlyName)..." -Color Gray
        Update-StoragePool -FriendlyName $pool.FriendlyName -Confirm:$true
    }
    Write-Log "Success: Storage Pools updated." -Color Green
}
catch {
    Write-Log "Failed to update Storage Pools: $($_.Exception.Message)" -Color Red
}

Write-Log "DONE: Cluster migration and upgrade are finalized." -Color Green
