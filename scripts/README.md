# AD DS Decommission Discovery Scripts

These scripts are the discovery phase for the AD DS decommission project. They are intended to run on the domain controller as a read-only inventory pass before any cutover, demotion, or sync removal work.

## Layout

- `scripts/lib/Discovery.Common.ps1` - shared helpers for output folders, artifact writing, module checks, and external command capture
- `scripts/discovery/` - one script per discovery concern
- `scripts/output/` - timestamped output folders created at runtime

## Output model

Each script writes two files into its own output folder:

- `*.json` - machine-readable inventory
- `*.txt` - short summary and the JSON file path

When run with the same `-RunId`, scripts write into a shared run folder so the evidence stays grouped together.

## Script list

### `Get-DCOverview.ps1`
Captures the basic identity of the current DC:

- computer name
- domain membership
- OS and uptime
- network addresses
- AD domain controller details
- forest and domain metadata
- time source information

Use this first when you need a baseline record of the server you are about to decommission.

### `Get-FSMOState.ps1`
Records the current FSMO role holders:

- schema master
- domain naming master
- PDC emulator
- RID master
- infrastructure master

Use this before any role transfer or DC demotion work.

### `Get-ADReplicationHealth.ps1`
Captures replication and directory health signals:

- DC inventory
- replication failures
- replication partner metadata
- key AD-related services
- `dcdiag` output
- `repadmin /replsummary` output

Use this to confirm the directory is healthy before any retirement step.

### `Get-DNSState.ps1`
Captures DNS state hosted on the DC:

- zones
- forwarders
- conditional forwarders
- scavenging settings
- zone record summaries

Use this to understand what DNS cleanup or replacement planning is needed.

### `Get-LocalServerFootprint.ps1`
Captures the local server footprint that could matter during decommissioning:

- installed Windows features
- key services
- SMB shares
- scheduled tasks with likely AD/DNS/sync relevance

Use this to identify local server components that might need removal or documentation.

### `Get-ADDependencyInventory.ps1`
Collects likely AD dependency indicators:

- trusts
- computers
- user-based service accounts with SPNs
- delegation-related objects
- gMSA accounts
- OU-linked GPOs
- Group Policy objects when the module is available

Use this to find signs of LDAP, Kerberos, SPN, delegation, or policy dependencies.

### `Get-SyncFootprint.ps1`
Detects directory sync tooling on the DC:

- Entra Connect Sync services and application entries
- Cloud Sync provisioning agent services and application entries
- registry fingerprints
- optional ADSync scheduler data

Use this to determine whether the DC is hosting the sync component and which sync model is present.

### `Export-DiscoveryPack.ps1`
Runs all discovery scripts with one shared `-RunId` and stores the results together.

Use this when you want a single inventory pass and a grouped evidence pack.

## Suggested run order

1. `Get-DCOverview.ps1`
2. `Get-FSMOState.ps1`
3. `Get-ADReplicationHealth.ps1`
4. `Get-DNSState.ps1`
5. `Get-LocalServerFootprint.ps1`
6. `Get-ADDependencyInventory.ps1`
7. `Get-SyncFootprint.ps1`
8. `Export-DiscoveryPack.ps1` if you want all of them at once

## Notes

- These scripts are intentionally read-only.
- They assume the scripts are being run on a Windows Server domain controller.
- Some sections depend on optional modules such as `ActiveDirectory`, `DnsServer`, `GroupPolicy`, or `ADSync`. If a module is missing, the script will still write output and note the gap.
