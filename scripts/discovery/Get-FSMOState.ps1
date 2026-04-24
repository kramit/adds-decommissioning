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
$roleAssignments = @()

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
                $roleAssignments += [pscustomobject]@{
                    Scope = 'Domain'
                    Domain = $domain.DNSRoot
                    Role = 'PDC Emulator'
                    Holder = $domain.PDCEmulator
                }
                $roleAssignments += [pscustomobject]@{
                    Scope = 'Domain'
                    Domain = $domain.DNSRoot
                    Role = 'RID Master'
                    Holder = $domain.RIDMaster
                }
                $roleAssignments += [pscustomobject]@{
                    Scope = 'Domain'
                    Domain = $domain.DNSRoot
                    Role = 'Infrastructure Master'
                    Holder = $domain.InfrastructureMaster
                }
            }
            catch {
                $warnings += "Unable to read domain '$domainName': $($_.Exception.Message)"
            }
        }
        $roleAssignments += [pscustomobject]@{
            Scope = 'Forest'
            Domain = $forest.RootDomain
            Role = 'Schema Master'
            Holder = $forest.SchemaMaster
        }
        $roleAssignments += [pscustomobject]@{
            Scope = 'Forest'
            Domain = $forest.RootDomain
            Role = 'Domain Naming Master'
            Holder = $forest.DomainNamingMaster
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

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings -Tables @{
    'RoleAssignments' = @($roleAssignments)
    'DomainDetails' = @($domainData)
    'ForestDetails' = @([pscustomobject]@{
        Name = $forestData.Name
        RootDomain = $forestData.RootDomain
        SchemaMaster = $forestData.SchemaMaster
        DomainNamingMaster = $forestData.DomainNamingMaster
        GlobalCatalogs = @($forestData.GlobalCatalogs)
    })
}
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    CsvFiles = $artifact.CsvFiles
    RunRoot = $context.RunRoot
}
