# AGENTS.md

## Project Summary

This repository supports an AD DS decommission project for a hybrid environment moving to cloud-only identity.

The work is split into four tracks:

- DC-side discovery and evidence collection
- DC decommission planning and execution driven by discovery artifacts
- EntraConnect tenant discovery and tenant sync disablement
- Local EntraConnect sync-host uninstall workflow

The repo is a nested git repository inside a larger Obsidian vault. Future work should stay inside this repo root unless the user explicitly asks otherwise.

## Current Repository Structure

- `ADDS Decommissioning.md` and `ADDS Decom checklist.md` contain the original project notes and checklist.
- `scripts/discovery/` contains DC-side discovery scripts.
- `scripts/execution/` contains the discovery-driven DC decommission plan and execution scripts.
- `scripts/entra-connect/` contains tenant-side EntraConnect scripts.
- `scripts/entra-connect/precheck/` contains the Graph permissions dry-run check.
- `scripts/entra-connect/local/` contains the local sync-host uninstall workflow.
- `scripts/output/` is created at runtime and should not be committed.

## What Has Already Been Built

### DC-side discovery

- `run-discovery.ps1`
- `scripts/README.md`
- `scripts/lib/Discovery.Common.ps1`
- `scripts/discovery/Export-DiscoveryPack.ps1`
- `scripts/discovery/Get-DCOverview.ps1`
- `scripts/discovery/Get-FSMOState.ps1`
- `scripts/discovery/Get-ADReplicationHealth.ps1`
- `scripts/discovery/Get-DNSState.ps1`
- `scripts/discovery/Get-LocalServerFootprint.ps1`
- `scripts/discovery/Get-ADDependencyInventory.ps1`
- `scripts/discovery/Get-SyncFootprint.ps1`

Purpose:

- inventory the DC
- capture AD health and FSMO state
- inventory DNS, local services, tasks, and likely AD dependencies
- detect Entra Connect / Cloud Sync footprint on the server
- emit detailed per-script TXT, CSV, and JSON artifacts
- generate a consolidated `Discovery-Report.md` and `Discovery-Index.csv`

### DC decommission planning and execution

- `run-dc-decommission.ps1`
- `scripts/execution/README.md`
- `scripts/execution/lib/Decommission.Common.ps1`
- `scripts/execution/Build-DCDecommissionPlan.ps1`
- `scripts/execution/Invoke-DCDecommission.ps1`

Purpose:

- consume the discovery pack as the source of truth
- build a human-reviewable decommission plan
- highlight blockers such as replication issues, FSMO ownership, and sync footprints
- capture transcript, event logs, and command diagnostics during execution
- perform the controlled AD DS demotion path only when explicitly requested

### Tenant-side EntraConnect discovery and disablement

- `run-entra-connect.ps1`
- `scripts/entra-connect/README.md`
- `scripts/entra-connect/lib/EntraConnect.Common.ps1`
- `scripts/entra-connect/discovery/Get-EntraSyncTenantState.ps1`
- `scripts/entra-connect/discovery/Get-EntraSyncObjectInventory.ps1`
- `scripts/entra-connect/change/Disable-EntraDirectorySync.ps1`
- `scripts/entra-connect/change/Wait-EntraDirectorySyncDisabled.ps1`
- `scripts/entra-connect/Export-EntraConnectPack.ps1`
- `scripts/entra-connect/EntraConnect-Decommission-Checklist.md`

Purpose:

- sign in to Microsoft Graph
- baseline tenant sync state
- inventory synced users and groups
- disable directory synchronization in the tenant
- verify the tenant reports sync disabled

### Local EntraConnect uninstall workflow

- `run-entra-connect-full.ps1`
- `scripts/entra-connect/precheck/Test-EntraConnectGraphPrereqs.ps1`
- `scripts/entra-connect/precheck/README.md`
- `scripts/entra-connect/local/README.md`
- `scripts/entra-connect/local/EntraConnect.Local.Common.ps1`
- `scripts/entra-connect/local/Get-EntraConnectLocalState.ps1`
- `scripts/entra-connect/local/Test-EntraConnectLocalPrereqs.ps1`
- `scripts/entra-connect/local/Stop-EntraConnectSyncServices.ps1`
- `scripts/entra-connect/local/Uninstall-EntraConnect.ps1`
- `scripts/entra-connect/local/Verify-EntraConnectRemoval.ps1`
- `scripts/entra-connect/local/Export-EntraConnectLocalPack.ps1`

Purpose:

- preflight Graph permissions before change night
- inventory the local sync host
- check readiness for uninstall
- stop sync-related services
- uninstall the local Entra Connect install
- verify the local footprint is gone

## Execution Order

Recommended order for a full change cycle:

1. Run `scripts/entra-connect/precheck/Test-EntraConnectGraphPrereqs.ps1`
2. Run `scripts/entra-connect/discovery/Get-EntraSyncTenantState.ps1`
3. Run `scripts/entra-connect/discovery/Get-EntraSyncObjectInventory.ps1`
4. Run `scripts/entra-connect/local/Get-EntraConnectLocalState.ps1`
5. Run `scripts/entra-connect/local/Test-EntraConnectLocalPrereqs.ps1`
6. Run `scripts/entra-connect/local/Stop-EntraConnectSyncServices.ps1`
7. Run `scripts/entra-connect/local/Uninstall-EntraConnect.ps1`
8. Run `scripts/entra-connect/change/Disable-EntraDirectorySync.ps1`
9. Run `scripts/entra-connect/change/Wait-EntraDirectorySyncDisabled.ps1`
10. Run `scripts/entra-connect/local/Verify-EntraConnectRemoval.ps1`
11. Run `run-dc-decommission.ps1` without `-Execute`
12. Review the DC decommission plan output
13. Run `run-dc-decommission.ps1 -Execute` when the plan is approved

## Entry Points

- `pwsh -File .\run-discovery.ps1`
- `pwsh -File .\run-entra-connect.ps1`
- `pwsh -File .\run-entra-connect-full.ps1`
- `pwsh -File .\run-dc-decommission.ps1`

## Output Convention

- Every discovery script writes a JSON artifact, a human-readable TXT report, and one or more detailed CSV tables.
- Some scripts also write attachment TXT files for raw command output.
- The discovery pack runner generates a consolidated `Discovery-Report.md` and `Discovery-Index.csv` at the run root.
- Shared `RunId` values group evidence into one run folder.
- Runtime output belongs under `scripts/output/` and should remain untracked.

## Coding Conventions

- Keep scripts modular. Do not turn the workflow back into one monolithic script.
- Prefer read-only discovery scripts unless the script is clearly labeled as a change action.
- Use `ShouldProcess` / `-WhatIf` / `-Confirm` for high-impact local change scripts where applicable.
- Use Microsoft Graph PowerShell for tenant-side queries and changes.
- Support interactive login or device-code login for Graph where possible.
- Keep helper functions in the relevant `lib/` folder.
- Use ASCII by default.

## Validation So Far

- All `.ps1` files in the repo were parse-checked with PowerShell and were valid at the time they were created.
- The repo has been pushed to GitHub and is tracking `origin/main`.

## Safety Notes

- Do not modify the parent Obsidian repo unless explicitly asked.
- Do not stage or revert unrelated user changes outside this repo.
- Treat tenant sync disablement and local Entra Connect uninstall as high-impact actions.
- Use `-WhatIf` or `-Confirm` during testing for destructive scripts.

## Useful File References

- [`README.md`](/Users/mike/Library/CloudStorage/OneDrive-Personal/Documents/Obsidian/MikesVault/General%20Notes/ADDS%20decomissioning/README.md)
- [`scripts/README.md`](/Users/mike/Library/CloudStorage/OneDrive-Personal/Documents/Obsidian/MikesVault/General%20Notes/ADDS%20decomissioning/scripts/README.md)
- [`scripts/execution/README.md`](/Users/mike/Library/CloudStorage/OneDrive-Personal/Documents/Obsidian/MikesVault/General%20Notes/ADDS%20decomissioning/scripts/execution/README.md)
- [`scripts/entra-connect/README.md`](/Users/mike/Library/CloudStorage/OneDrive-Personal/Documents/Obsidian/MikesVault/General%20Notes/ADDS%20decomissioning/scripts/entra-connect/README.md)
- [`scripts/entra-connect/local/README.md`](/Users/mike/Library/CloudStorage/OneDrive-Personal/Documents/Obsidian/MikesVault/General%20Notes/ADDS%20decomissioning/scripts/entra-connect/local/README.md)
- [`scripts/entra-connect/precheck/README.md`](/Users/mike/Library/CloudStorage/OneDrive-Personal/Documents/Obsidian/MikesVault/General%20Notes/ADDS%20decomissioning/scripts/entra-connect/precheck/README.md)
