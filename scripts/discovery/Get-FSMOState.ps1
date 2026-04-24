param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot '..\lib\Discovery.Common.ps1'
. $commonPath

$context = New-DiscoveryContext -ScriptName 'Get-FSMOState' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$adModuleLoaded = Test-OptionalModule -Name 'ActiveDirectory'
if (-not $adModuleLoaded) {
    $warnings += 'ActiveDirectory module was not available.'
}

$forestData = $null
$domainData = @()

if ($adModuleLoaded) {
    try {
        $forest = Get-ADForest -ErrorAction Stop
        $forestData = [pscustomobject]@{
            Name = $forest.Name
            RootDomain = $forest.RootDomain
            SchemaMaster = $forest.SchemaMaster
            DomainNamingMaster = $forest.DomainNamingMaster
            GlobalCatalogs = @($forest.GlobalCatalogs)
        }

        foreach ($domainName in @($forest.Domains)) {
            try {
                $domain = Get-ADDomain -Identity $domainName -ErrorAction Stop
                $domainData += [pscustomobject]@{
                    Name = $domain.DNSRoot
                    PDCEmulator = $domain.PDCEmulator
                    RIDMaster = $domain.RIDMaster
                    InfrastructureMaster = $domain.InfrastructureMaster
                    NetBIOSName = $domain.NetBIOSName
                }
            }
            catch {
                $warnings += "Unable to read domain '$domainName': $($_.Exception.Message)"
            }
        }
    }
    catch {
        $warnings += "Unable to read forest state: $($_.Exception.Message)"
    }
}

$data = [pscustomobject]@{
    Forest = $forestData
    Domains = @($domainData)
    Notes = @(
        'This script records FSMO role holders before any role transfer or demotion.',
        'Use it as a baseline for the decommission evidence pack.'
    )
}

$summary = @()
if ($forestData) {
    $summary += "Forest: $($forestData.Name)"
    $summary += "Schema master: $($forestData.SchemaMaster)"
    $summary += "Domain naming master: $($forestData.DomainNamingMaster)"
}
foreach ($domain in @($domainData)) {
    $summary += "Domain $($domain.Name) PDC: $($domain.PDCEmulator)"
    $summary += "Domain $($domain.Name) RID: $($domain.RIDMaster)"
    $summary += "Domain $($domain.Name) Infrastructure: $($domain.InfrastructureMaster)"
}

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
