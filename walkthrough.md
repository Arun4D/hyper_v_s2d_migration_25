# Walkthrough - Hyper-V S2D Migration Framework (Enhanced)

I have implemented a comprehensive 4-script framework to automate the rolling upgrade of a Hyper-V S2D cluster from Windows Server 2016 to Windows Server 2025. This version includes **centralized logging** and **shared drive identity exports**.

## Overview of Scripts

| Phase | Script | Purpose |
| :--- | :--- | :--- |
| **Phase 1** | [Phase1-PreValidate.ps1](file:///c:/Arun/workspaces/arun4d_github/hyper_v_s2d_migration_25/Phase1-PreValidate.ps1) | Captures MAC addresses, NIC names, and IP configuration. Exports JSON to Shared Drive. |
| **Phase 2** | [Phase2-Migrate.ps1](file:///c:/Arun/workspaces/arun4d_github/hyper_v_s2d_migration_25/Phase2-Migrate.ps1) | Drains and evicts the node. Logs activity to Shared Drive. |
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
Manually install **Windows Server 2025**.

### 5. Post-Reinstall (on Windows Server 2025)
Run `Phase3-PostValidate.ps1` pointing to the identity file on the shared drive.
```powershell
.\Phase3-PostValidate.ps1 -IdentityFile "\\FS01\Migration\NodeIdentity_NODE01.json" -ClusterName "S2DCluster" -SharedPath "\\FS01\Migration"
```

### 6. Finalize (After ALL nodes are 2025)
Run `Finalize-ClusterUpgrade.ps1`.
```powershell
.\Finalize-ClusterUpgrade.ps1 -SharedPath "\\FS01\Migration"
```

## Safety Features:
- **Centralized Log**: Every script appends to `Migration_History.log` on the shared drive.
- **Identity Safety**: Node identity is stored off-box before eviction.
- **DNA Matching**: NICs are renamed based on MAC addresses to ensure the SET switch is built correctly.
