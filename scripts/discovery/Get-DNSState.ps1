param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot '..\lib\Discovery.Common.ps1'
. $commonPath

$context = New-DiscoveryContext -ScriptName 'Get-DNSState' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$dnsModuleLoaded = Test-OptionalModule -Name 'DnsServer'
if (-not $dnsModuleLoaded) {
    $warnings += 'DnsServer module was not available.'
}

$zones = @()
$forwarders = @()
$conditionalForwarders = @()
$scavenging = $null
$hostRecordHits = @()

if ($dnsModuleLoaded) {
    try {
        $zones = @(Get-DnsServerZone | Select-Object ZoneName, ZoneType, IsDsIntegrated, IsAutoCreated, IsReverseLookupZone, ReplicationScope)
    }
    catch {
        $warnings += "Unable to enumerate DNS zones: $($_.Exception.Message)"
    }

    try {
        $forwarders = @(Get-DnsServerForwarder | Select-Object IPAddress, UseRootHint, Timeout)
    }
    catch {
        $warnings += "Unable to enumerate DNS forwarders: $($_.Exception.Message)"
    }

    try {
        $conditionalForwarders = @(Get-DnsServerConditionalForwarderZone | Select-Object ZoneName, MasterServers, ReplicationScope)
    }
    catch {
        $warnings += "Unable to enumerate conditional forwarders: $($_.Exception.Message)"
    }

    try {
        $scavenging = Get-DnsServerScavenging
    }
    catch {
        $warnings += "Unable to read scavenging settings: $($_.Exception.Message)"
    }

    foreach ($zone in @($zones)) {
        try {
            $records = @(Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -ErrorAction Stop)
            $hostRecordHits += [pscustomobject]@{
                ZoneName = $zone.ZoneName
                RecordCount = $records.Count
                RecordTypes = @($records | Group-Object RecordType | Sort-Object Name | Select-Object Name, Count)
                HasDomainControllerNames = [bool]($records | Where-Object {
                    $_.HostName -match [regex]::Escape($env:COMPUTERNAME) -or
                    $_.RecordData -match [regex]::Escape($env:COMPUTERNAME)
                })
            }
        }
        catch {
            $warnings += "Unable to read records for zone '$($zone.ZoneName)': $($_.Exception.Message)"
        }
    }
}

$data = [pscustomobject]@{
    Zones = @($zones)
    Forwarders = @($forwarders)
    ConditionalForwarders = @($conditionalForwarders)
    Scavenging = $scavenging
    ZoneRecordSummary = @($hostRecordHits)
    Notes = @(
        'This script inventories the DNS role state hosted on the DC.',
        'It is intended to reveal zones, forwarders, and likely DNS cleanup work.'
    )
}

$summary = @(
    "Zones: $(@($zones).Count)",
    "Forwarders: $(@($forwarders).Count)",
    "Conditional forwarders: $(@($conditionalForwarders).Count)",
    "Zones with record summaries: $(@($hostRecordHits).Count)",
    "Scavenging captured: $([bool]$scavenging)"
)

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
