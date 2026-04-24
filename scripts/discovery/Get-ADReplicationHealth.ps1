param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot '..\lib\Discovery.Common.ps1'
. $commonPath

$context = New-DiscoveryContext -ScriptName 'Get-ADReplicationHealth' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$adModuleLoaded = Test-OptionalModule -Name 'ActiveDirectory'
if (-not $adModuleLoaded) {
    $warnings += 'ActiveDirectory module was not available.'
}

$dcdiag = $null
$repadmin = $null
$dcList = @()
$replicationFailures = @()
$partnerMetadata = @()

if ($adModuleLoaded) {
    try {
        $dcList = @(Get-ADDomainController -Filter * | Select-Object HostName, Site, IPv4Address, IsGlobalCatalog, OperationMasterRoles)
    }
    catch {
        $warnings += "Unable to enumerate domain controllers: $($_.Exception.Message)"
    }

    try {
        $replicationFailures = @(Get-ADReplicationFailure -Scope Forest -ErrorAction Stop)
    }
    catch {
        $warnings += "Unable to query replication failures: $($_.Exception.Message)"
    }

    try {
        $partnerMetadata = @(Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -Scope Server -ErrorAction Stop)
    }
    catch {
        $warnings += "Unable to query replication partner metadata: $($_.Exception.Message)"
    }
}

if (Get-Command dcdiag.exe -ErrorAction SilentlyContinue) {
    $dcdiag = Invoke-ExternalCommand -FilePath 'dcdiag.exe' -Arguments @('/test:advertising', '/test:replications', '/test:sysvolcheck', '/test:dns', '/v')
}
else {
    $warnings += 'dcdiag.exe was not available.'
}

if (Get-Command repadmin.exe -ErrorAction SilentlyContinue) {
    $repadmin = Invoke-ExternalCommand -FilePath 'repadmin.exe' -Arguments @('/replsummary')
}
else {
    $warnings += 'repadmin.exe was not available.'
}

$services = @()
foreach ($name in 'NTDS', 'DNS', 'DFSR', 'Netlogon', 'ADWS', 'W32Time') {
    try {
        $services += Get-Service -Name $name -ErrorAction Stop | Select-Object Name, Status, StartType
    }
    catch {
        $warnings += "Service '$name' was not found."
    }
}

$data = [pscustomobject]@{
    DomainControllers = @($dcList)
    ReplicationFailures = @($replicationFailures)
    PartnerMetadata = @($partnerMetadata)
    Services = @($services)
    DcDiag = $dcdiag
    RepAdmin = $repadmin
    Notes = @(
        'This script captures replication health signals and command-line diagnostics.',
        'It is intended to be run before any role transfers or demotion.'
    )
}

$summary = @(
    "Domain controllers discovered: $(@($dcList).Count)",
    "Replication failures: $(@($replicationFailures).Count)",
    "Partner metadata entries: $(@($partnerMetadata).Count)",
    "Selected services checked: $(@($services).Count)",
    "dcdiag captured: $([bool]$dcdiag)",
    "repadmin captured: $([bool]$repadmin)"
)

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
