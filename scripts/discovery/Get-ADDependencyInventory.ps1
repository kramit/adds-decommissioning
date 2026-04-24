param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output'),
    [string]$RunId
)

$commonPath = Join-Path $PSScriptRoot '..\lib\Discovery.Common.ps1'
. $commonPath

$context = New-DiscoveryContext -ScriptName 'Get-ADDependencyInventory' -OutputRoot $OutputRoot -RunId $RunId
$warnings = @()

$adModuleLoaded = Test-OptionalModule -Name 'ActiveDirectory'
if (-not $adModuleLoaded) {
    $warnings += 'ActiveDirectory module was not available.'
}

$groupPolicyLoaded = Test-OptionalModule -Name 'GroupPolicy'
if (-not $groupPolicyLoaded) {
    $warnings += 'GroupPolicy module was not available.'
}

$trusts = @()
$computers = @()
$serviceAccounts = @()
$delegationAccounts = @()
$gmsaAccounts = @()
$ouGpoLinks = @()
$gpos = @()

if ($adModuleLoaded) {
    try {
        $trusts = @(Get-ADTrust -Filter * | Select-Object Name, Source, Target, TrustType, TrustDirection, DisallowTransivity, SelectiveAuthentication, SIDFilteringForestAware)
    }
    catch {
        $warnings += "Unable to enumerate trusts: $($_.Exception.Message)"
    }

    try {
        $computers = @(Get-ADComputer -Filter * -Properties LastLogonDate, OperatingSystem, DNSHostName, ServicePrincipalName, TrustedForDelegation, Enabled | Select-Object Name, DNSHostName, OperatingSystem, LastLogonDate, Enabled, TrustedForDelegation, @{Name='SPNCount';Expression={ @($_.ServicePrincipalName).Count }})
    }
    catch {
        $warnings += "Unable to enumerate computers: $($_.Exception.Message)"
    }

    try {
        $serviceAccounts = @(Get-ADUser -Filter 'ServicePrincipalName -like "*"' -Properties ServicePrincipalName, PasswordNeverExpires, Enabled, LastLogonDate, TrustedForDelegation | Select-Object SamAccountName, Enabled, PasswordNeverExpires, LastLogonDate, TrustedForDelegation, @{Name='SPNCount';Expression={ @($_.ServicePrincipalName).Count }})
    }
    catch {
        $warnings += "Unable to enumerate user-based service accounts: $($_.Exception.Message)"
    }

    try {
        $delegationAccounts = @(Get-ADObject -LDAPFilter '(|(userAccountControl:1.2.840.113556.1.4.803:=524288)(msDS-AllowedToDelegateTo=*))' -Properties objectClass, userAccountControl, msDS-AllowedToDelegateTo, servicePrincipalName | Select-Object DistinguishedName, ObjectClass, @{Name='AllowedToDelegateToCount';Expression={ @($_.'msDS-AllowedToDelegateTo').Count }}, @{Name='SPNCount';Expression={ @($_.ServicePrincipalName).Count }})
    }
    catch {
        $warnings += "Unable to enumerate delegation-related objects: $($_.Exception.Message)"
    }

    try {
        $gmsaAccounts = @(Get-ADServiceAccount -Filter * -Properties Enabled, PrincipalsAllowedToRetrieveManagedPassword, DNSHostName | Select-Object Name, DNSHostName, Enabled, @{Name='AllowedPrincipalsCount';Expression={ @($_.PrincipalsAllowedToRetrieveManagedPassword).Count }})
    }
    catch {
        $warnings += "Unable to enumerate gMSA accounts: $($_.Exception.Message)"
    }

    try {
        $ouGpoLinks = @(Get-ADOrganizationalUnit -Filter * -Properties gPLink, gPOptions | Where-Object { $_.gPLink } | Select-Object DistinguishedName, gPLink, gPOptions)
    }
    catch {
        $warnings += "Unable to enumerate OU GPO links: $($_.Exception.Message)"
    }
}

if ($groupPolicyLoaded) {
    try {
        $gpos = @(Get-GPO -All | Select-Object DisplayName, Id, Owner, GpoStatus, CreationTime, ModificationTime)
    }
    catch {
        $warnings += "Unable to enumerate GPOs: $($_.Exception.Message)"
    }
}

$data = [pscustomobject]@{
    Trusts = @($trusts)
    Computers = @($computers)
    ServiceAccounts = @($serviceAccounts)
    DelegationAccounts = @($delegationAccounts)
    ManagedServiceAccounts = @($gmsaAccounts)
    OUGroupPolicyLinks = @($ouGpoLinks)
    GroupPolicies = @($gpos)
    Notes = @(
        'This script collects likely dependency signals from AD.',
        'It is not a full application dependency scanner, but it highlights SPNs, delegation, trusts, and OU-linked GPOs.'
    )
}

$summary = @(
    "Trusts: $(@($trusts).Count)",
    "Computers: $(@($computers).Count)",
    "Service accounts with SPNs: $(@($serviceAccounts).Count)",
    "Delegation-related objects: $(@($delegationAccounts).Count)",
    "gMSA accounts: $(@($gmsaAccounts).Count)",
    "OU GPO links: $(@($ouGpoLinks).Count)",
    "GPOs: $(@($gpos).Count)"
)

$artifact = Save-DiscoveryArtifact -Context $context -Data $data -SummaryLines $summary -Warnings $warnings
[pscustomobject]@{
    ScriptName = $context.ScriptName
    TextPath = $artifact.TextPath
    JsonPath = $artifact.JsonPath
    RunRoot = $context.RunRoot
}
