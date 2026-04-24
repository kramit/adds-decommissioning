# Local Entra Connect Uninstall Scripts

This folder contains the local, sync-host side workflow for retiring Microsoft Entra Connect from the server that runs it.

## What this folder does

- inventories the local Entra Connect install and services
- checks whether the host is ready for the uninstall
- stops the sync services
- uninstalls the local Entra Connect application when explicitly requested
- verifies that the local footprint is gone

These scripts run on the sync host itself. They are separate from the tenant-side Graph scripts in `scripts/entra-connect/`.

## Folder layout

- `scripts/entra-connect/local/EntraConnect.Local.Common.ps1` - shared local inventory and uninstall helpers
- `scripts/entra-connect/local/Get-EntraConnectLocalState.ps1` - read-only local footprint inventory
- `scripts/entra-connect/local/Test-EntraConnectLocalPrereqs.ps1` - local precheck before uninstall
- `scripts/entra-connect/local/Stop-EntraConnectSyncServices.ps1` - stops the sync-related Windows services
- `scripts/entra-connect/local/Uninstall-EntraConnect.ps1` - controlled uninstall workflow
- `scripts/entra-connect/local/Verify-EntraConnectRemoval.ps1` - post-uninstall verification
- `scripts/entra-connect/local/Export-EntraConnectLocalPack.ps1` - read-only wrapper for the local discovery scripts

## Script list

### `Get-EntraConnectLocalState.ps1`
Captures the current local footprint:

- install entries
- services
- scheduled tasks
- registry fingerprints

Use this before any local change.

### `Test-EntraConnectLocalPrereqs.ps1`
Checks whether the host is ready for uninstall:

- confirms the session is elevated
- checks that Entra Connect is installed
- checks that sync services are present
- gathers uninstall candidates

Use this as a dry-run precheck before the maintenance window.

### `Stop-EntraConnectSyncServices.ps1`
Stops the local sync services.

Use this immediately before uninstalling the local sync client.

### `Uninstall-EntraConnect.ps1`
Runs the controlled uninstall path for the local Entra Connect installation.

Use `-Execute` when you are ready to run the uninstall command.

### `Verify-EntraConnectRemoval.ps1`
Confirms the local footprint is gone or reduced to zero.

Use this after the uninstall step.

### `Export-EntraConnectLocalPack.ps1`
Runs the read-only local inventory scripts with one shared `RunId`.

Use this when you want a local evidence pack before making changes.

## Suggested run order

1. `Get-EntraConnectLocalState.ps1`
2. `Test-EntraConnectLocalPrereqs.ps1`
3. `Stop-EntraConnectSyncServices.ps1`
4. `Uninstall-EntraConnect.ps1`
5. `Verify-EntraConnectRemoval.ps1`

## Notes

- This workflow runs on the server hosting Entra Connect.
- The scripts are intentionally separated from the tenant-side Graph changes.
- The repo root orchestrator `run-entra-connect-full.ps1` can call this folder together with the tenant-side scripts.
