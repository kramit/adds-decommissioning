. (Join-Path $PSScriptRoot '..\..\lib\Discovery.Common.ps1')

function New-DecommissionContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\output'),

        [string]$RunId
    )

    if (-not $RunId) {
        $RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
    }

    $safeScriptName = $ScriptName -replace '[^A-Za-z0-9._-]', '_'
    $runRoot = Join-Path (Join-Path $OutputRoot 'decommission') $RunId
    $artifactRoot = Join-Path $runRoot $safeScriptName

    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

    [pscustomobject]@{
        ScriptName     = $ScriptName
        SafeName       = $safeScriptName
        RunId          = $RunId
        OutputRoot     = $OutputRoot
        RunRoot        = $runRoot
        ArtifactRoot   = $artifactRoot
        JsonPath       = Join-Path $artifactRoot "$safeScriptName.json"
        TextPath       = Join-Path $artifactRoot "$safeScriptName.txt"
        LogPath        = Join-Path $artifactRoot "$safeScriptName.log"
        TranscriptPath = Join-Path $artifactRoot "$safeScriptName.transcript.txt"
    }
}

function Resolve-DiscoveryIndexPath {
    param(
        [string]$DiscoveryRunRoot,
        [string]$DiscoveryIndexPath
    )

    if ($DiscoveryIndexPath) {
        return $DiscoveryIndexPath
    }

    if (-not $DiscoveryRunRoot) {
        throw 'Specify either -DiscoveryIndexPath or -DiscoveryRunRoot.'
    }

    $candidate = Join-Path $DiscoveryRunRoot 'Discovery-Index.csv'
    if (-not (Test-Path $candidate)) {
        throw "Discovery index not found: $candidate"
    }

    return $candidate
}

function Read-DiscoveryIndex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DiscoveryIndexPath
    )

    if (-not (Test-Path $DiscoveryIndexPath)) {
        throw "Discovery index not found: $DiscoveryIndexPath"
    }

    Import-Csv -Path $DiscoveryIndexPath
}

function Get-DiscoveryArtifactPathMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DiscoveryIndexPath
    )

    $rows = @(Read-DiscoveryIndex -DiscoveryIndexPath $DiscoveryIndexPath)
    $map = @{}

    foreach ($row in $rows) {
        $csvPaths = @()
        if ($row.CsvPaths) {
            $csvPaths = @(
                $row.CsvPaths -split ';' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ }
            )
        }

        $map[$row.ScriptName] = [pscustomobject]@{
            ScriptName = $row.ScriptName
            TextPath = $row.TextPath
            JsonPath = $row.JsonPath
            CsvPaths = @($csvPaths)
        }
    }

    $map
}

function Get-DiscoveryTablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DiscoveryIndexPath,

        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    $map = Get-DiscoveryArtifactPathMap -DiscoveryIndexPath $DiscoveryIndexPath
    if (-not $map.ContainsKey($ScriptName)) {
        return $null
    }

    $safeTableName = $TableName -replace '[^A-Za-z0-9._-]', '_'
    $expectedLeaf = "$($map[$ScriptName].ScriptName)-$safeTableName.csv"

    foreach ($csvPath in @($map[$ScriptName].CsvPaths)) {
        if ((Split-Path -Path $csvPath -Leaf) -ieq $expectedLeaf) {
            return $csvPath
        }
    }

    return $null
}

function Import-DiscoveryTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DiscoveryIndexPath,

        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    $tablePath = Get-DiscoveryTablePath -DiscoveryIndexPath $DiscoveryIndexPath -ScriptName $ScriptName -TableName $TableName
    if (-not $tablePath -or -not (Test-Path $tablePath)) {
        return @()
    }

    @(Import-Csv -Path $tablePath)
}

function Get-DiscoveryArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DiscoveryIndexPath,

        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    $map = Get-DiscoveryArtifactPathMap -DiscoveryIndexPath $DiscoveryIndexPath
    if (-not $map.ContainsKey($ScriptName)) {
        return $null
    }

    $jsonPath = $map[$ScriptName].JsonPath
    if (-not (Test-Path $jsonPath)) {
        return $null
    }

    Get-Content -Path $jsonPath -Raw | ConvertFrom-Json -Depth 30
}

function Test-DiscoveryHostMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $normalizedValue = ($Value -split '[\\/,; ]')[0]
    $normalizedValue = $normalizedValue.Split('.')[0]

    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $normalizedName = ($name -split '[\\/,; ]')[0]
        $normalizedName = $normalizedName.Split('.')[0]
        if ($normalizedValue -ieq $normalizedName) {
            return $true
        }
    }

    return $false
}

function Write-DecommissionLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    Add-Content -Path $Path -Value $line
}

function Test-PendingReboot {
    $sources = New-Object System.Collections.Generic.List[string]

    $registryChecks = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    foreach ($path in $registryChecks) {
        if (Test-Path $path) {
            $sources.Add($path)
        }
    }

    try {
        $sessionManager = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        if ($sessionManager.PendingFileRenameOperations) {
            $sources.Add('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations')
        }
    }
    catch {
    }

    [pscustomobject]@{
        PendingReboot = $sources.Count -gt 0
        Sources = @($sources)
    }
}

function Get-ExecutionEnvironmentSnapshot {
    $modules = @()
    foreach ($moduleName in 'ActiveDirectory', 'ADDSDeployment', 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.DirectoryManagement', 'DnsServer', 'GroupPolicy', 'ServerManager', 'ADSync') {
        $availableModule = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
        $loadedModule = Get-Module -Name $moduleName | Select-Object -First 1

        $modules += [pscustomobject]@{
            Name = $moduleName
            Available = [bool]$availableModule
            Loaded = [bool]$loadedModule
            Version = if ($availableModule) { $availableModule.Version.ToString() } else { $null }
        }
    }

    $services = @()
    foreach ($name in 'NTDS', 'DNS', 'DFSR', 'Netlogon', 'ADWS', 'W32Time', 'ADSync', 'AzureADConnectProvisioningAgent', 'AzureADConnectAuthenticationAgent') {
        try {
            $service = Get-Service -Name $name -ErrorAction Stop
            $cimService = Get-CimInstance Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue
            $services += [pscustomobject]@{
                Name = $service.Name
                DisplayName = $service.DisplayName
                Status = $service.Status
                StartType = if ($cimService) { $cimService.StartMode } else { $null }
                StartName = if ($cimService) { $cimService.StartName } else { $null }
            }
        }
        catch {
        }
    }

    $computerSystem = $null
    $os = $null
    try { $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { }
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }

    $pendingReboot = Test-PendingReboot

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        UserName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Edition = $PSVersionTable.PSEdition
        IsAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        OperatingSystem = if ($os) {
            [pscustomobject]@{
                Caption = $os.Caption
                Version = $os.Version
                BuildNumber = $os.BuildNumber
                LastBootUpTime = $os.LastBootUpTime
            }
        } else { $null }
        ComputerSystem = if ($computerSystem) {
            [pscustomobject]@{
                Domain = $computerSystem.Domain
                Manufacturer = $computerSystem.Manufacturer
                Model = $computerSystem.Model
                PartOfDomain = $computerSystem.PartOfDomain
            }
        } else { $null }
        PendingReboot = $pendingReboot.PendingReboot
        PendingRebootSources = @($pendingReboot.Sources)
        Modules = @($modules)
        Services = @($services)
    }
}

function Get-RecentEventLogEntries {
    param(
        [string[]]$LogName = @('Directory Service', 'DNS Server', 'DFS Replication', 'System', 'Application'),
        [int]$MaxEvents = 50
    )

    $entries = @()
    foreach ($log in $LogName) {
        try {
            $events = Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 2, 3 } -MaxEvents $MaxEvents -ErrorAction Stop
            foreach ($event in $events) {
                $entries += [pscustomobject]@{
                    LogName = $log
                    TimeCreated = $event.TimeCreated
                    Id = $event.Id
                    LevelDisplayName = $event.LevelDisplayName
                    ProviderName = $event.ProviderName
                    MachineName = $event.MachineName
                    Message = ($event.Message -replace '\s+', ' ').Trim()
                }
            }
        }
        catch {
        }
    }

    $entries
}

function Get-DCDecommissionAssessment {
    param(
        [string]$DiscoveryRunRoot,

        [string]$DiscoveryIndexPath
    )

    $resolvedIndex = Resolve-DiscoveryIndexPath -DiscoveryRunRoot $DiscoveryRunRoot -DiscoveryIndexPath $DiscoveryIndexPath
    $warnings = New-Object System.Collections.Generic.List[string]

    $requiredArtifacts = @(
        'Get-DCOverview',
        'Get-FSMOState',
        'Get-ADReplicationHealth',
        'Get-DNSState',
        'Get-LocalServerFootprint',
        'Get-ADDependencyInventory',
        'Get-SyncFootprint'
    )

    $artifacts = [ordered]@{}
    foreach ($scriptName in $requiredArtifacts) {
        $artifact = Get-DiscoveryArtifact -DiscoveryIndexPath $resolvedIndex -ScriptName $scriptName
        if ($artifact) {
            $artifacts[$scriptName] = $artifact
        }
        else {
            $warnings.Add("Missing discovery artifact: $scriptName")
        }
    }

    $overview = $artifacts['Get-DCOverview']
    $fsmo = $artifacts['Get-FSMOState']
    $replication = $artifacts['Get-ADReplicationHealth']
    $dns = $artifacts['Get-DNSState']
    $local = $artifacts['Get-LocalServerFootprint']
    $dependencies = $artifacts['Get-ADDependencyInventory']
    $sync = $artifacts['Get-SyncFootprint']

    $currentHost = if ($overview -and $overview.Computer -and $overview.Computer.Name) { [string]$overview.Computer.Name } else { $env:COMPUTERNAME }
    $currentHostNames = @($env:COMPUTERNAME, $currentHost)
    if ($overview -and $overview.Domain -and $overview.Domain.Name) {
        $currentHostNames += "$($env:COMPUTERNAME).$($overview.Domain.Name)"
        $currentHostNames += "$currentHost.$($overview.Domain.Name)"
    }
    $currentHostNames = @($currentHostNames | Where-Object { $_ })

    $tables = [ordered]@{}

    foreach ($tableSpec in @(
        @{ Key = 'DiscoveryDomainControllers'; Script = 'Get-ADReplicationHealth'; Table = 'DomainControllers' },
        @{ Key = 'DiscoveryReplicationFailures'; Script = 'Get-ADReplicationHealth'; Table = 'ReplicationFailures' },
        @{ Key = 'DiscoveryReplicationPartners'; Script = 'Get-ADReplicationHealth'; Table = 'PartnerMetadata' },
        @{ Key = 'DiscoveryServiceChecks'; Script = 'Get-ADReplicationHealth'; Table = 'ServiceChecks' },
        @{ Key = 'DiscoveryFsmoRoleAssignments'; Script = 'Get-FSMOState'; Table = 'RoleAssignments' },
        @{ Key = 'DiscoveryFsmoDomainDetails'; Script = 'Get-FSMOState'; Table = 'DomainDetails' },
        @{ Key = 'DiscoveryDnsZones'; Script = 'Get-DNSState'; Table = 'Zones' },
        @{ Key = 'DiscoveryDnsForwarders'; Script = 'Get-DNSState'; Table = 'Forwarders' },
        @{ Key = 'DiscoveryDnsConditionalForwarders'; Script = 'Get-DNSState'; Table = 'ConditionalForwarders' },
        @{ Key = 'DiscoveryDnsZoneSummary'; Script = 'Get-DNSState'; Table = 'ZoneRecordSummary' },
        @{ Key = 'DiscoveryDnsRecords'; Script = 'Get-DNSState'; Table = 'ZoneRecords' },
        @{ Key = 'DiscoveryInstalledFeatures'; Script = 'Get-LocalServerFootprint'; Table = 'InstalledFeatures' },
        @{ Key = 'DiscoveryKeyServices'; Script = 'Get-LocalServerFootprint'; Table = 'KeyServices' },
        @{ Key = 'DiscoveryShares'; Script = 'Get-LocalServerFootprint'; Table = 'SMBShares' },
        @{ Key = 'DiscoveryShareAccess'; Script = 'Get-LocalServerFootprint'; Table = 'SMBShareAccess' },
        @{ Key = 'DiscoveryScheduledTasks'; Script = 'Get-LocalServerFootprint'; Table = 'ScheduledTasks' },
        @{ Key = 'DiscoveryTrusts'; Script = 'Get-ADDependencyInventory'; Table = 'Trusts' },
        @{ Key = 'DiscoveryComputers'; Script = 'Get-ADDependencyInventory'; Table = 'Computers' },
        @{ Key = 'DiscoveryServiceAccounts'; Script = 'Get-ADDependencyInventory'; Table = 'ServiceAccounts' },
        @{ Key = 'DiscoveryServiceAccountSpns'; Script = 'Get-ADDependencyInventory'; Table = 'ServiceAccountSpns' },
        @{ Key = 'DiscoveryDelegationAccounts'; Script = 'Get-ADDependencyInventory'; Table = 'DelegationAccounts' },
        @{ Key = 'DiscoveryManagedServiceAccounts'; Script = 'Get-ADDependencyInventory'; Table = 'ManagedServiceAccounts' },
        @{ Key = 'DiscoveryOuGpoLinks'; Script = 'Get-ADDependencyInventory'; Table = 'OUGroupPolicyLinks' },
        @{ Key = 'DiscoveryGpos'; Script = 'Get-ADDependencyInventory'; Table = 'GroupPolicies' },
        @{ Key = 'DiscoverySyncServices'; Script = 'Get-SyncFootprint'; Table = 'Services' },
        @{ Key = 'DiscoverySyncApplications'; Script = 'Get-SyncFootprint'; Table = 'InstalledApplications' },
        @{ Key = 'DiscoverySyncRegistry'; Script = 'Get-SyncFootprint'; Table = 'RegistryEntries' },
        @{ Key = 'DiscoverySyncScheduler'; Script = 'Get-SyncFootprint'; Table = 'ADSyncScheduler' }
    )) {
        $rows = @(Import-DiscoveryTable -DiscoveryIndexPath $resolvedIndex -ScriptName $tableSpec.Script -TableName $tableSpec.Table)
        if ($rows.Count -gt 0) {
            $tables[$tableSpec.Key] = $rows
        }
    }

    $heldRoles = @()
    if ($fsmo) {
        foreach ($domain in @($fsmo.Domains)) {
            foreach ($roleName in 'PDCEmulator', 'RIDMaster', 'InfrastructureMaster') {
                $holder = $domain.$roleName
                if (Test-DiscoveryHostMatch -Value $holder -Names $currentHostNames) {
                    $heldRoles += [pscustomobject]@{
                        Scope = 'Domain'
                        Domain = $domain.Name
                        Role = $roleName
                        Holder = $holder
                    }
                }
            }
        }

        if ($fsmo.Forest) {
            foreach ($roleName in 'SchemaMaster', 'DomainNamingMaster') {
                $holder = $fsmo.Forest.$roleName
                if (Test-DiscoveryHostMatch -Value $holder -Names $currentHostNames) {
                    $heldRoles += [pscustomobject]@{
                        Scope = 'Forest'
                        Domain = $fsmo.Forest.RootDomain
                        Role = $roleName
                        Holder = $holder
                    }
                }
            }
        }
    }

    $replicationFailures = @()
    if ($replication -and $replication.ReplicationFailures) {
        $replicationFailures = @($replication.ReplicationFailures)
    }

    $dcCount = if ($tables.Contains('DiscoveryDomainControllers')) { @($tables['DiscoveryDomainControllers']).Count } else { 0 }
    $zoneCount = if ($tables.Contains('DiscoveryDnsZones')) { @($tables['DiscoveryDnsZones']).Count } else { 0 }
    $shareCount = if ($tables.Contains('DiscoveryShares')) { @($tables['DiscoveryShares']).Count } else { 0 }
    $serviceAccountCount = if ($tables.Contains('DiscoveryServiceAccounts')) { @($tables['DiscoveryServiceAccounts']).Count } else { 0 }
    $syncClassification = if ($sync -and $sync.Classification) { [string]$sync.Classification } else { 'Unknown' }

    $blockers = New-Object System.Collections.Generic.List[object]
    $recommendations = New-Object System.Collections.Generic.List[object]

    if ($dcCount -eq 0) {
        $warnings.Add('No domain controller table was discovered in the latest discovery pack.')
    }

    if ($replicationFailures.Count -gt 0) {
        $blockers.Add([pscustomobject]@{
            Severity = 'High'
            Category = 'Replication'
            Finding = "Replication failures discovered: $($replicationFailures.Count)"
            Action = 'Resolve AD replication issues before demotion.'
        })
    }

    if ($heldRoles.Count -gt 0) {
        $blockers.Add([pscustomobject]@{
            Severity = 'High'
            Category = 'FSMO'
            Finding = "This host holds FSMO role assignments: $($heldRoles.Count)"
            Action = 'Transfer FSMO roles to another DC before decommissioning or explicitly override with a forced removal path.'
        })
    }

    if ($syncClassification -ne 'No sync footprint detected' -and $syncClassification -ne 'Unknown') {
        $blockers.Add([pscustomobject]@{
            Severity = 'High'
            Category = 'EntraConnect'
            Finding = "Sync footprint detected: $syncClassification"
            Action = 'Complete the EntraConnect disconnect workflow before retiring this DC.'
        })
    }

    if ($zoneCount -gt 0) {
        $recommendations.Add([pscustomobject]@{
            Area = 'DNS'
            Observation = "DNS zones are hosted on this server: $zoneCount"
            Action = 'Review zone hosting, forwarders, and delegation cleanup before demotion.'
        })
    }

    if ($shareCount -gt 0) {
        $recommendations.Add([pscustomobject]@{
            Area = 'SMB'
            Observation = "SMB shares discovered: $shareCount"
            Action = 'Validate share paths and ACLs so file-services dependencies can be relocated or retired.'
        })
    }

    if ($serviceAccountCount -gt 0) {
        $recommendations.Add([pscustomobject]@{
            Area = 'AD Dependencies'
            Observation = "Service accounts with SPNs discovered: $serviceAccountCount"
            Action = 'Review SPNs, delegation accounts, and application ownership before decommissioning.'
        })
    }

    $discoveryRunRootResolved = Split-Path -Path $resolvedIndex -Parent

    $summaryLines = @(
        "Discovery run root: $discoveryRunRootResolved",
        "Current host: $currentHost",
        "Domain controllers discovered: $dcCount",
        "FSMO role assignments on this host: $($heldRoles.Count)",
        "Replication failures discovered: $($replicationFailures.Count)",
        "DNS zones discovered: $zoneCount",
        "SMB shares discovered: $shareCount",
        "Service accounts discovered: $serviceAccountCount",
        "Sync footprint: $syncClassification"
    )

    [pscustomobject]@{
        DiscoveryIndexPath = $resolvedIndex
        DiscoveryRunRoot = $discoveryRunRootResolved
        CurrentHost = $currentHost
        CurrentHostNames = @($currentHostNames)
        SourceArtifacts = $artifacts
        Tables = $tables
        HeldRoles = @($heldRoles)
        ReplicationFailures = @($replicationFailures)
        Blockers = @($blockers)
        Recommendations = @($recommendations)
        Warnings = @($warnings)
        SummaryLines = $summaryLines
        CanProceed = $blockers.Count -eq 0
        SyncClassification = $syncClassification
    }
}

function Save-DecommissionArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [object]$Data,

        [string[]]$SummaryLines = @(),

        [string[]]$Warnings = @(),

        [System.Collections.IDictionary]$Tables = @{},

        [System.Collections.IDictionary]$TextAttachments = @{}
    )

    Save-DiscoveryArtifact -Context $Context -Data $Data -SummaryLines $SummaryLines -Warnings $Warnings -Tables $Tables -TextAttachments $TextAttachments
}

function Start-DecommissionTranscript {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    Start-Transcript -Path $Context.TranscriptPath -Force -ErrorAction Stop | Out-Null
}

function Stop-DecommissionTranscript {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
}
