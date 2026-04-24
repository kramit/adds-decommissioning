# AD DS Decommissioning

This repository contains the working notes, discovery scripts, and evidence-pack helpers for retiring the on-prem AD DS environment and moving fully to cloud-only identity.

The intent is to keep the work modular:

- the markdown files hold the project notes and checklist
- `scripts/` holds the PowerShell discovery tooling for the DC side
- `scripts/entra-connect/` holds the tenant-side EntraConnect disconnect tooling
- `scripts/entra-connect/local/` holds the local Entra Connect uninstall workflow
- `scripts/entra-connect/precheck/` holds the Graph permissions dry-run precheck
- `scripts/output/` is created at runtime for evidence artifacts

## Quick Start

Run the full discovery pack from the repo root:

```powershell
pwsh -File .\run-discovery.ps1
```

That produces one run folder under `scripts/output/` with per-script TXT/CSV/JSON artifacts plus a consolidated `Discovery-Report.md`.

Run the EntraConnect tenant discovery pack from the repo root:

```powershell
pwsh -File .\run-entra-connect.ps1
```

Run the full EntraConnect change orchestrator from the repo root:

```powershell
pwsh -File .\run-entra-connect-full.ps1
```

You can optionally provide a shared run ID so multiple script runs land in the same evidence folder:

```powershell
pwsh -File .\run-discovery.ps1 -RunId 20260424-120000
```

## What the scripts do

- `scripts/discovery/Get-DCOverview.ps1` captures the basic identity of the current domain controller.
- `scripts/discovery/Get-FSMOState.ps1` records FSMO role holders.
- `scripts/discovery/Get-ADReplicationHealth.ps1` captures replication health and AD diagnostics.
- `scripts/discovery/Get-DNSState.ps1` inventories DNS state hosted on the DC.
- `scripts/discovery/Get-LocalServerFootprint.ps1` inventories server roles, services, shares, and tasks.
- `scripts/discovery/Get-ADDependencyInventory.ps1` collects likely AD dependency indicators.
- `scripts/discovery/Get-SyncFootprint.ps1` detects Entra Connect or Cloud Sync footprints.
- `scripts/discovery/Export-DiscoveryPack.ps1` runs the full discovery set with one shared `RunId`.
- `scripts/entra-connect/discovery/Get-EntraSyncTenantState.ps1` captures tenant sync state.
- `scripts/entra-connect/discovery/Get-EntraSyncObjectInventory.ps1` inventories synced users and groups.
- `scripts/entra-connect/precheck/Test-EntraConnectGraphPrereqs.ps1` validates Graph login and permissions.
- `scripts/entra-connect/local/Get-EntraConnectLocalState.ps1` inventories the local sync host.
- `scripts/entra-connect/local/Test-EntraConnectLocalPrereqs.ps1` checks the local host before uninstall.
- `scripts/entra-connect/local/Stop-EntraConnectSyncServices.ps1` stops local sync services.
- `scripts/entra-connect/local/Uninstall-EntraConnect.ps1` removes the local Entra Connect install.
- `scripts/entra-connect/local/Verify-EntraConnectRemoval.ps1` verifies the local uninstall result.
- `scripts/entra-connect/change/Disable-EntraDirectorySync.ps1` disables directory synchronization in the tenant.
- `scripts/entra-connect/change/Wait-EntraDirectorySyncDisabled.ps1` waits for the tenant to report sync disabled.
- `scripts/entra-connect/Export-EntraConnectPack.ps1` runs the read-only tenant discovery pack.
- `run-entra-connect-full.ps1` orchestrates the precheck, discovery, local uninstall, and tenant sync disable flow.

For script-level details, see [`scripts/README.md`](scripts/README.md).
For the EntraConnect workflow, see [`scripts/entra-connect/README.md`](scripts/entra-connect/README.md).

## Notes

- The discovery scripts are read-only.
- They are intended to run on the domain controller being assessed.
- Output artifacts are written as detailed JSON, TXT, CSV, and a consolidated markdown report.
