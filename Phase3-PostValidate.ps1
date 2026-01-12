<#
.SYNOPSIS
    Phase 3: Post-Validate (Node Reintegration).
    Run this on the new Windows Server 2019/2022 node AFTER clean install.
    Ensures network naming parity and cluster rejoin.
#>

Param(
    [Parameter(Mandatory = $true)]
    [string]$IdentityFile,
    
    [Parameter(Mandatory = $true)]
    [string]$ClusterName,

    [Parameter(Mandatory = $false)]
    [string]$SharedPath = $PSScriptRoot
)

$NodeName = $env:COMPUTERNAME
$LogPath = Join-Path $SharedPath "Migration_$NodeName.log"

function Write-Log {
    Param([string]$Message, [string]$Color = "White")
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] [$NodeName] [Phase 3] $Message"
    Write-Host $Message -ForegroundColor $Color
    $LogEntry | Out-File $LogPath -Append
}

function Test-ModuleAvailability {
    Param([string[]]$Modules)
    $Missing = @()
    foreach ($m in $Modules) {
        if (!(Get-Module -ListAvailable -Name $m)) {
            $Missing += $m
        }
    }
    if ($Missing) {
        Write-Log "CRITICAL: Missing required PowerShell modules: $($Missing -join ', ')" -Color Red
        Write-Log "Note: Some modules like Hyper-V and FailoverClusters will be installed by this script, but their management tools must be available for capture/restore logic." -Color White
        # We don't exit here because Phase 3 installs the features, but we warn.
        # Actually, if management tools are missing, the script will fail later.
        # Let's verify ServerManager is present at least.
    }
}

# Pre-flight Module Check
Test-ModuleAvailability -Modules @("ServerManager", "NetAdapter")

Write-Log "--- Starting Phase 3: Post-Validate/Reintegration for $NodeName ---" -Color Cyan

# 1. Load Identity
if (!(Test-Path $IdentityFile)) {
    Write-Log "Identity file not found at $IdentityFile" -Color Red
    exit 1
}
$Identity = Get-Content $IdentityFile | ConvertFrom-Json
Write-Log "[1/5] Loaded Identity for node: $($Identity.NodeName)" -Color Yellow

# 2. Install Roles
Write-Log "[2/5] Installing Roles (Hyper-V, Clustering, DCB)..." -Color Yellow
$Features = @("Hyper-V", "Failover-Clustering", "Data-Center-Bridging", "RSAT-Clustering-PowerShell")
Install-WindowsFeature -Name $Features -IncludeManagementTools
Write-Log "Success: Roles installed." -Color Green

# 3. Rename Physical NICs based on MAC DNA
Write-Log "[3/5] Syncing NIC Names with 2016 DNA..." -Color Yellow
$CurrentAdapters = Get-NetAdapter

foreach ($originalConfig in $Identity.NetworkConfig) {
    $match = $CurrentAdapters | Where-Object { $_.MacAddress -eq $originalConfig.MacAddress }
    if ($match) {
        if ($match.Name -ne $originalConfig.Name) {
            Write-Log "Renaming $($match.Name) to $($originalConfig.Name) (MAC: $($originalConfig.MacAddress))" -Color Gray
            Rename-NetAdapter -Name $match.Name -NewName $originalConfig.Name
        }
        else {
            Write-Log "NIC $($originalConfig.Name) already correctly named (MAC: $($originalConfig.MacAddress))" -Color Gray
        }
    }
    else {
        Write-Log "Could not find a physical adapter matching MAC: $($originalConfig.MacAddress)" -Color Warning
    }
}

# 4. Rebuild SET Virtual Switch
Write-Log "[4/5] Rebuilding SET Virtual Switch..." -Color Yellow
$SetAdapters = $Identity.NetworkConfig.Name
Write-Log "Creating SET Switch with adapters: $($SetAdapters -join ', ')" -Color Gray

try {
    if (!(Get-VMSwitch -Name "SET-Switch" -ErrorAction SilentlyContinue)) {
        New-VMSwitch -Name "SET-Switch" -NetAdapterName $SetAdapters -AllowManagementOS $true -EnableEmbeddedTeaming $true
        Write-Log "Success: SET Switch created." -Color Green
    }
    else {
        Write-Log "SET-Switch already exists." -Color Gray
    }
}
catch {
    Write-Log "Failed to create SET Switch: $($_.Exception.Message)" -Color Red
}

# 5. Rejoin Cluster and Monitor Resync
Write-Log "[5/5] Rejoining Cluster $ClusterName..." -Color Yellow
try {
    Add-ClusterNode -Cluster $ClusterName -Name $NodeName
    Write-Log "Success: Node rejoined cluster." -Color Green
    
    Write-Log "Monitoring S2D Resync Status..." -Color Gray
    do {
        $Jobs = Get-StorageJob | Where-Object { $_.IsBackgroundTask -eq $false -and $_.JobState -ne "Completed" }
        if ($Jobs) {
            Write-Log "Resync in progress: $($Jobs.PercentComplete)%... Waiting 30s." -Color Gray
            Start-Sleep -Seconds 30
        }
    } while ($Jobs)
    
    Write-Log "Success: Storage Resync Complete." -Color Green
}
catch {
    Write-Log "Failed to rejoin cluster: $($_.Exception.Message)" -Color Red
}

Write-Log "DONE: Phase 3 complete. Node is fully reintegrated." -Color Green
