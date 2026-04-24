# EntraConnect Decommission Scripts

This folder contains the tenant-side discovery, verification, and change scripts for removing Microsoft Entra Connect from the hybrid identity stack.

## What this folder does

- captures a baseline of tenant sync state
- inventories synced users and groups
- disables directory synchronization in the tenant
- waits for the tenant to report sync disabled

The scripts use Microsoft Graph PowerShell login and can prompt interactively or by device code.

## Folder layout

- `scripts/entra-connect/lib/EntraConnect.Common.ps1` - shared Graph/auth/output helpers
- `scripts/entra-connect/discovery/` - read-only tenant discovery scripts
- `scripts/entra-connect/change/` - tenant change and verification scripts
- `scripts/entra-connect/EntraConnect-Decommission-Checklist.md` - manual checklist for the full workflow
- `scripts/entra-connect/Export-EntraConnectPack.ps1` - read-only wrapper that runs both discovery scripts

## Script list

### `Get-EntraSyncTenantState.ps1`
Captures tenant-level sync state:

- current Microsoft Graph session information
- organization sync flag and last sync time
- verified domains
- Entra AD Synchronization Service service principal
- directory roles

Use this first to baseline the tenant before any sync changes.

### `Get-EntraSyncObjectInventory.ps1`
Captures synced object inventory:

- synced users
- synced groups
- samples by default
- full list if `-IncludeFullList` is used

Use this to understand how much identity data is still sourced from on-premises AD.

### `Disable-EntraDirectorySync.ps1`
Disables tenant-level directory synchronization.

The script:

- signs in to Microsoft Graph
- captures the pre-change tenant state
- disables directory synchronization using the available Microsoft-supported cmdlet path
- captures the post-change state

Use `-WhatIf` or `-Confirm` during testing. This is the change script.

### `Wait-EntraDirectorySyncDisabled.ps1`
Polls the tenant until directory synchronization reports disabled or the timeout is reached.

Use this after the disable step to prove the tenant has converged.

### `Export-EntraConnectPack.ps1`
Runs the read-only tenant discovery scripts with one shared `RunId`.

Use this when you want one evidence pack before the change window.

## Suggested run order

1. `Get-EntraSyncTenantState.ps1`
2. `Get-EntraSyncObjectInventory.ps1`
3. `Disable-EntraDirectorySync.ps1`
4. `Wait-EntraDirectorySyncDisabled.ps1`

## Suggested scopes

The discovery scripts request read scopes for:

- `Organization.Read.All`
- `Directory.Read.All`
- `Domain.Read.All`
- `Application.Read.All`
- `RoleManagement.Read.Directory`
- `User.Read.All`
- `Group.Read.All`

The disable script requests write scopes for:

- `OnPremDirectorySynchronization.ReadWrite.All`
- `Organization.ReadWrite.All`
- `Organization.Read.All`
- `Directory.Read.All`

## Notes

- Microsoft documents that disabling directory synchronization can take up to 72 hours to finish.
- These scripts are tenant-side only. The local sync server uninstall is still a separate step on the DC or sync host.
- The DC-side `scripts/discovery/` folder already contains `Get-SyncFootprint.ps1` to help confirm the local sync footprint before you remove it.
