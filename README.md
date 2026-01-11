# Hyper-V S2D Migration Framework (2016 to 2025)

This framework provides an automated, 3-phase PowerShell approach to migrating Hyper-V Storage Spaces Direct (S2D) clusters from Windows Server 2016 to Windows Server 2025 using a "Clean-Install Rolling Upgrade" strategy.

## 🚀 Key Features
- **Network DNA Preservation**: Automatically captures MAC-to-Interface mappings and SET Switch configurations to ensure consistency after OS reinstall.
- **Production Safety**: Multi-stage health checks (Cluster Health, Storage Resync) prevent destructive actions if the cluster is unhealthy.
- **Traceability**: Per-node logging (`Migration_<NodeName>.log`) saved to a centralized shared drive.
- **Idempotency**: Scripts can be run multiple times; they verify existing state before applying changes.

## 📁 Repository Structure
- `Phase1-PreValidate.ps1`: Run on 2016 nodes to capture identity.
- `Phase2-Migrate.ps1`: Run on 2016 nodes to drain and evict.
- `Phase3-PostValidate.ps1`: Run on 2025 nodes to restore identity and rejoin.
- `Finalize-ClusterUpgrade.ps1`: Run once after all nodes are upgraded.
- `walkthrough.md`: Detailed step-by-step execution guide.

## 🛠️ Infrastructure Requirements
1. **Shared Network Drive**: Accessible by all nodes (e.g., `\\FS01\Migration`).
2. **Admin Credentials**: PowerShell must be run as Administrator on cluster nodes.

## 📖 Quick Start
1. **Capture Identity**: 
   ```powershell
   .\Phase1-PreValidate.ps1 -SharedPath "\\FS01\Migration"
   ```
2. **Evict Node**:
   ```powershell
   .\Phase2-Migrate.ps1 -SharedPath "\\FS01\Migration"
   ```
3. **Re-Integrate (Windows 2025)**:
   ```powershell
   .\Phase3-PostValidate.ps1 -IdentityFile "\\FS01\Migration\NodeIdentity_NODE01.json" -ClusterName "S2DCluster" -SharedPath "\\FS01\Migration"
   ```

## 🛡️ Architectural Review Summary
- **Risk**: Local identity loss during wipe. -> **Mitigation**: Off-box JSON export of NIC DNA.
- **Risk**: Inconsistent SET Switch naming. -> **Mitigation**: MAC-based NIC renaming before Switch creation.
- **Risk**: Interweaving logs. -> **Mitigation**: Per-node log file naming.
- **Risk**: Migration during resync. -> **Mitigation**: Forced blocking if `Get-StorageJob` returns active background tasks.

---
*Maintained by arun4d.*
