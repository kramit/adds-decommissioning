# EntraConnect Decommission Checklist

This checklist covers the tenant-side part of removing Microsoft Entra Connect from the environment. It is intended to be used together with the DC-side scripts in `scripts/discovery/`.

## Discovery and readiness

- [ ] Confirm the tenant and admin account that will be used for the change
- [ ] Confirm at least two break-glass accounts are available and tested
- [ ] Capture a baseline of current tenant sync state with `Get-EntraSyncTenantState.ps1`
- [ ] Capture a baseline of synced users and groups with `Get-EntraSyncObjectInventory.ps1`
- [ ] Confirm whether the environment is using Entra Connect Sync or Cloud Sync
- [ ] Confirm which tenant domains are verified and which domain is default
- [ ] Confirm any downstream apps, scripts, or services that still depend on synced identity

## Change order

- [ ] Uninstall the sync client from the server that hosts Entra Connect
- [ ] Disable directory synchronization at the tenant level
- [ ] Confirm the tenant reports directory synchronization disabled
- [ ] Wait for Microsoft to finish propagation
- [ ] Re-run the verification script until the tenant shows sync disabled

## Verification

- [ ] Confirm `onPremisesSyncEnabled` is `false`
- [ ] Confirm the Entra AD Synchronization Service service principal is no longer the active sync control point
- [ ] Confirm synced users and groups behave as expected in the tenant
- [ ] Confirm cloud-only object management works for new users and groups
- [ ] Confirm the on-premises sync server no longer performs sync cycles

## Evidence pack

- [ ] Save the tenant state JSON and text output from `Get-EntraSyncTenantState.ps1`
- [ ] Save the synced object inventory from `Get-EntraSyncObjectInventory.ps1`
- [ ] Save the change output from `Disable-EntraDirectorySync.ps1`
- [ ] Save the polling evidence from `Wait-EntraDirectorySyncDisabled.ps1`
- [ ] Save the local DC-side sync footprint evidence from `scripts/discovery/Get-SyncFootprint.ps1`

## Notes

- Microsoft documents that disabling directory synchronization can take up to 72 hours to fully complete.
- The scripts in this folder are designed to use Microsoft Graph PowerShell login prompts, including device code flow when requested.
- Treat the disable script as a high-impact change and use `-WhatIf` or `-Confirm` during testing.
