param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot '..\lib\Discovery.Common.ps1'
. $commonPath

$context = New-DiscoveryContext -ScriptName 'Get-DCOverview' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

try {
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $networkAdapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
    $ipAddresses = foreach ($adapter in $networkAdapters) {
        foreach ($ip in @($adapter.IPAddress)) {
            if ($ip -and $ip -notlike '169.254*' -and $ip -notlike 'fe80:*') {
                $ip
            }
        }
    }

    $adModuleLoaded = Test-OptionalModule -Name 'ActiveDirectory'
    $adComputer = $null
    $adDomain = $null
    $adForest = $null

    if ($adModuleLoaded) {
        try { $adComputer = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop } catch { $warnings += "Unable to read AD domain controller details: $($_.Exception.Message)" }
        try { $adDomain = Get-ADDomain -ErrorAction Stop } catch { $warnings += "Unable to read AD domain details: $($_.Exception.Message)" }
        try { $adForest = Get-ADForest -ErrorAction Stop } catch { $warnings += "Unable to read AD forest details: $($_.Exception.Message)" }
    }
    else {
        $warnings += 'ActiveDirectory module was not available.'
    }

    $timeStatus = Invoke-ExternalCommand -FilePath 'w32tm.exe' -Arguments @('/query', '/status')
    $timeSource = Invoke-ExternalCommand -FilePath 'w32tm.exe' -Arguments @('/query', '/source')

    $data = [pscustomobject]@{
        Computer = [pscustomobject]@{
            Name = $env:COMPUTERNAME
            Domain = $computerSystem.Domain
            PartOfDomain = $computerSystem.PartOfDomain
            Manufacturer = $computerSystem.Manufacturer
            Model = $computerSystem.Model
            Uptime = (New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date))
            OS = [pscustomobject]@{
                Caption = $os.Caption
                Version = $os.Version
                BuildNumber = $os.BuildNumber
                InstallDate = $os.InstallDate
            }
            IPv4Addresses = @($ipAddresses)
            GlobalCatalog = if ($adComputer) { [bool]$adComputer.IsGlobalCatalog } else { $null }
            Site = if ($adComputer) { $adComputer.Site } else { $null }
            Roles = if ($adComputer) { @($adComputer.OperationMasterRoles) } else { @() }
        }
        Domain = if ($adDomain) {
            [pscustomobject]@{
                Name = $adDomain.DNSRoot
                NetBIOSName = $adDomain.NetBIOSName
                DistinguishedName = $adDomain.DistinguishedName
                PDCEmulator = $adDomain.PDCEmulator
                RIDMaster = $adDomain.RIDMaster
                InfrastructureMaster = $adDomain.InfrastructureMaster
            }
        } else { $null }
        Forest = if ($adForest) {
            [pscustomobject]@{
                Name = $adForest.Name
                Domains = @($adForest.Domains)
                RootDomain = $adForest.RootDomain
                SchemaMaster = $adForest.SchemaMaster
                DomainNamingMaster = $adForest.DomainNamingMaster
                GlobalCatalogs = @($adForest.GlobalCatalogs)
            }
        } else { $null }
        Time = [pscustomobject]@{
            Status = @($timeStatus.Output)
            Source = @($timeSource.Output)
        }
        Notes = @(
            'This script is read-only.',
            'It captures local DC identity, domain membership, forest metadata, and time source.'
        )
    }
}
catch {
    throw
}

$summary = @(
    "Computer: $($data.Computer.Name)",
    "Domain: $($data.Computer.Domain)",
    "IPv4 addresses: $(@($data.Computer.IPv4Addresses).Count)",
    "Global Catalog: $($data.Computer.GlobalCatalog)",
    "FSMO roles on this DC: $(@($data.Computer.Roles).Count)",
    "Time source command exit code: $($timeSource.ExitCode)"
)

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
