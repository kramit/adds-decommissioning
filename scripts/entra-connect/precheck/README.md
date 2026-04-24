# Entra Connect Graph Precheck

This folder contains the dry-run tenant precheck script for the Entra Connect change window.

## Script list

### `Test-EntraConnectGraphPrereqs.ps1`
Validates the Microsoft Graph sign-in and the permissions needed for the tenant-side change steps.

It checks:

- Graph login works
- the requested scopes are present in the session
- the tenant organization object can be read
- tenant domains can be read
- the Entra AD Synchronization Service service principal can be read
- the required change cmdlets are available in the session

Use this before change night to catch missing permissions early.
