# AD DS Decommissioning

This repository contains the working notes, discovery scripts, and evidence-pack helpers for retiring the on-prem AD DS environment and moving fully to cloud-only identity.

The intent is to keep the work modular:

- the markdown files hold the project notes and checklist
- `scripts/` holds the PowerShell discovery tooling
- `scripts/output/` is created at runtime for evidence artifacts

## Quick Start

Run the full discovery pack from the repo root:

```powershell
pwsh -File .\run-discovery.ps1
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

For script-level details, see [`scripts/README.md`](scripts/README.md).

## Notes

- The discovery scripts are read-only.
- They are intended to run on the domain controller being assessed.
- Output artifacts are written as both JSON and a short text summary.
