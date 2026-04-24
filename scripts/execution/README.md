# DC Decommission Execution Scripts

This folder contains the execution layer that turns the discovery pack into a reviewable decommission plan and, when explicitly requested, performs the controlled domain-controller demotion.

## What this folder does

- reads the discovery pack produced by `scripts/discovery/`
- builds a human-readable decommission plan from those artifacts
- captures execution-time diagnostics so failures are easier to troubleshoot
- runs the AD DS demotion path only when the operator explicitly opts in
- keeps the dangerous parts separate from the review/reporting parts

The scripts assume they are running on the target DC as an administrator or enterprise admin.

## Folder layout

- `scripts/execution/lib/Decommission.Common.ps1` - shared discovery parsing, diagnostics, and report helpers
- `scripts/execution/Build-DCDecommissionPlan.ps1` - reads the discovery pack and produces a plan/report
- `scripts/execution/Invoke-DCDecommission.ps1` - executes the demotion path with debug capture
- `run-dc-decommission.ps1` - thin repo-root launcher

## Script list

### `Build-DCDecommissionPlan.ps1`
Loads the discovery pack and collates the items a human should review before any change:

- FSMO role holders
- replication failures
- DNS zones and records
- SMB shares and access lists
- service accounts, SPNs, delegation objects, and gMSAs
- Entra Connect or Cloud Sync footprint
- execution-environment state and recent event log warnings

Use this first to review blockers and sign off on the change path.

### `Invoke-DCDecommission.ps1`
Runs the decommission workflow when `-Execute` is supplied.

It captures:

- transcript output
- current environment snapshot
- recent event logs
- `dcdiag` and `repadmin` diagnostics before and after the action when possible
- step-by-step execution records

It refuses to proceed if the discovery pack shows obvious blockers unless `-BypassBlockers` is supplied.

### `run-dc-decommission.ps1`
Thin launcher at the repo root.

Without `-Execute`, it builds the plan only.
With `-Execute`, it runs the plan and then the execution script with the same inputs.

## Suggested run order

1. Run `run-discovery.ps1`
2. Review the discovery output artifacts and `Discovery-Report.md`
3. Run `run-dc-decommission.ps1` without `-Execute`
4. Review the decommission plan output
5. Run `run-dc-decommission.ps1 -Execute` when the plan is approved

## Debug capture

The execution layer writes:

- a transcript file
- a structured JSON artifact
- a human-readable TXT report
- detailed CSV tables
- raw `dcdiag` / `repadmin` command output attachments when available
- recent event log rows for the most relevant channels

## Notes

- If the discovery pack shows an Entra Connect or Cloud Sync footprint, finish the EntraConnect workflow before demotion.
- Forced removal is intentionally left as an override path, not the default.
- The output root for this folder is `scripts/output/decommission/`.
