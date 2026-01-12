# Walkthrough - Hyper-V S2D Migration Framework (Rolling Upgrade)

I have implemented a comprehensive 4-script framework to automate the rolling upgrade of a Hyper-V S2D cluster from Windows Server 2016 to Windows Server 2019, 2022, or 2025. This version includes a **16-point pre-validation checklist** and **safeguarded eviction processes**.

## Overview of Scripts

| Phase | Script | Purpose |
| :--- | :--- | :--- |
| **Phase 1** | [Phase1-PreValidate.ps1](file:///c:/Arun/workspaces/arun4d_github/hyper_v_s2d_migration_25/Phase1-PreValidate.ps1) | Executes the 16-point checklist (Backups, VMs, SCCM, etc.) and captures Network DNA. |
| **Phase 2** | [Phase2-Migrate.ps1](file:///c:/Arun/workspaces/arun4d_github/hyper_v_s2d_migration_25/Phase2-Migrate.ps1) | Drains/evicts node, places disks in maintenance, verifies status, and cleans up AD. |
| **Phase 3** | [Phase3-PostValidate.ps1](file:///c:/Arun/workspaces/arun4d_github/hyper_v_s2d_migration_25/Phase3-PostValidate.ps1) | Restores NIC names from Shared Drive JSON, rebuilds SET Switch, and rejoins cluster. |
| **Finalize** | [Finalize-ClusterUpgrade.ps1](file:///c:/Arun/workspaces/arun4d_github/hyper_v_s2d_migration_25/Finalize-ClusterUpgrade.ps1) | Updates Functional Level and Storage Pools once all nodes are upgraded. |

## Detailed Workflow

### 1. Preparation
Ensure a **Shared Network Drive** is accessible (e.g., `\\FS01\Migration`).

### 2. Pre-Migration (on Windows Server 2016)
Run `Phase1-PreValidate.ps1` providing the shared path.
```powershell
.\Phase1-PreValidate.ps1 -SharedPath "\\FS01\Migration"
```

### 3. Eviction (on Windows Server 2016)
Run `Phase2-Migrate.ps1`.
```powershell
.\Phase2-Migrate.ps1 -SharedPath "\\FS01\Migration"
```

### 4. OS Reinstall
Manually install the target OS (**Windows Server 2019, 2022, or 2025**).

### 5. Post-Reinstall (on Target OS Node)
Run `Phase3-PostValidate.ps1` pointing to the identity file on the shared drive.
```powershell
.\Phase3-PostValidate.ps1 -IdentityFile "\\FS01\Migration\NodeIdentity_NODE01.json" -ClusterName "S2DCluster" -SharedPath "\\FS01\Migration"
```

### 6. Finalize (After ALL nodes are Upgraded)
Run `Finalize-ClusterUpgrade.ps1`.
```powershell
.\Finalize-ClusterUpgrade.ps1 -SharedPath "\\FS01\Migration"
```

## Safety Features:
- **16-Point Checklist**: Ensures all prerequisites (backups, service notifications, AD coordination) are met before starting.
- **Centralized Log**: Every script appends to per-node log files on the shared drive.
- **Identity Safety**: Node identity is stored off-box before eviction.
- **DNA Matching**: NICs are renamed based on MAC addresses to ensure the SET switch is built correctly.
